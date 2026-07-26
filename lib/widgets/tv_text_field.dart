import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/storage_service.dart';
import '../utils/platform_util.dart';
import '../utils/tv_keys.dart';
import 'tv_keyboard.dart';

/// Text field that is safe to use on TV.
///
/// On TV (with the Debrify keyboard enabled in Settings) the DPAD stop is a
/// SHELL: landing on it never opens any keyboard. OK begins editing — the
/// in-app [TvKeyboardPanel] appears and the remote navigates it; Back ends
/// editing and returns to the shell. The backing TextField keeps focus while
/// editing (real caret, and hardware/BT keyboards still type inline) but uses
/// [TextInputType.none], so the system IME — broken for DPAD on many TVs
/// (flutter/flutter#177360) — is never involved.
///
/// Off TV, or when the user opts out of the Debrify keyboard, this renders a
/// plain [TextField] with identical behavior to before the conversion.
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.labelText,
    this.hintText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.style,
    this.textAlign = TextAlign.start,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.cursorColor,
    this.inputFormatters,
    this.autofillHints,
    this.validator,
    this.shellRing = true,
    this.onChanged,
    this.onSubmitted,
    this.onUpArrow,
    this.onDownArrow,
    this.onLeftArrow,
    this.onRightArrow,
  });

  final TextEditingController controller;

  /// The DPAD stop other controls chain to: the shell node on TV, the
  /// TextField's own node elsewhere. Created internally when omitted.
  final FocusNode? focusNode;

  /// Full decoration override. When provided it is used as-is (with the shell
  /// borrowing its `focusedBorder` for the focus ring); otherwise a decoration
  /// is assembled from the label/hint/icon fields below and the shell draws
  /// its own accent ring.
  final InputDecoration? decoration;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  final TextStyle? style;
  final TextAlign textAlign;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;

  /// Off-TV / opt-out only; the shell always uses [TextInputType.none].
  final TextInputType? keyboardType;

  /// On TV this focuses the SHELL (no keyboard pops); elsewhere the field.
  final bool autofocus;
  final bool enabled;
  final bool obscureText;
  final Color? cursorColor;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  /// Non-null makes this a [TextFormField] (participates in an enclosing
  /// [Form]'s validate/save pass) in both shell and passthrough modes.
  final FormFieldValidator<String>? validator;

  /// Set false when the call site draws its own focus ring around the field
  /// (otherwise the shell's fallback accent ring would double it up).
  final bool shellRing;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Explicit DPAD exits from the SHELL (not while editing). Null falls back
  /// to bubbling the key so an ancestor handler or traversal takes it.
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrow;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onRightArrow;

  @override
  State<TvTextField> createState() => TvTextFieldState();
}

/// Keyboard-nav intents, mapped over the field ONLY while editing (the
/// Shortcuts sit below the shell, so they resolve only when the editor holds
/// focus). They shadow the framework's caret bindings, which is intentional:
/// while our keyboard is up, arrows move its highlight, not the caret.
class _KbNavIntent extends Intent {
  const _KbNavIntent(this.dx, this.dy);
  final int dx;
  final int dy;
}

class _KbActivateIntent extends Intent {
  const _KbActivateIntent();
}

class _KbNavAction extends Action<_KbNavIntent> {
  _KbNavAction(this.state);
  final TvTextFieldState state;

  @override
  bool isEnabled(_KbNavIntent intent) => state._editing && state._kb != null;

  @override
  Object? invoke(_KbNavIntent intent) {
    state._kb!.nav(intent.dx, intent.dy);
    return null;
  }
}

class _KbActivateAction extends Action<_KbActivateIntent> {
  _KbActivateAction(this.state);
  final TvTextFieldState state;

  @override
  bool isEnabled(_KbActivateIntent intent) =>
      state._editing && state._kb != null;

  @override
  Object? invoke(_KbActivateIntent intent) {
    state._kb!.activateHighlighted();
    return null;
  }
}

/// Passthrough-mode (TV, Debrify keyboard opted out) edge-of-text arrow exits.
/// Modeled as Shortcuts+Actions with [Action.isEnabled] so a disabled state
/// falls straight through to the framework's own caret handling.
class _EdgeLeftIntent extends Intent {
  const _EdgeLeftIntent();
}

class _EdgeRightIntent extends Intent {
  const _EdgeRightIntent();
}

class _EdgeLeftAction extends Action<_EdgeLeftIntent> {
  _EdgeLeftAction(this.state);
  final TvTextFieldState state;

  @override
  bool isEnabled(_EdgeLeftIntent intent) =>
      state.widget.onLeftArrow != null && state._caretAtStart;

  @override
  Object? invoke(_EdgeLeftIntent intent) {
    state.widget.onLeftArrow!();
    return null;
  }
}

class _EdgeRightAction extends Action<_EdgeRightIntent> {
  _EdgeRightAction(this.state);
  final TvTextFieldState state;

  @override
  bool isEnabled(_EdgeRightIntent intent) =>
      state.widget.onRightArrow != null && state._caretAtEnd;

  @override
  Object? invoke(_EdgeRightIntent intent) {
    state.widget.onRightArrow!();
    return null;
  }
}

class TvTextFieldState extends State<TvTextField> {
  /// TV only: the actual TextField's node — skipTraversal so the shell is the
  /// only DPAD stop; focused exclusively by OK ("start editing") or a tap.
  final FocusNode _editNode = FocusNode(
    debugLabel: 'tv-textfield-edit',
    skipTraversal: true,
  );

  FocusNode? _internalShellNode;
  FocusNode get _shellNode =>
      widget.focusNode ?? (_internalShellNode ??= FocusNode(debugLabel: 'tv-textfield-shell'));

  TvKeyboardController? _kb;
  OverlayEntry? _overlay;
  bool _editing = false;
  bool _focused = false;

  /// The field was handed to the system IME (the keyboard's smartphone key):
  /// it runs with a real input type so the Google TV phone-remote keyboard /
  /// voice input engage, and this widget intercepts NOTHING — keys, focus and
  /// Back behave exactly like the Debrify-keyboard-off mode, which is the
  /// known-good escape path. Restores shell mode the moment focus leaves the
  /// field, so the next DPAD visit starts on the Debrify keyboard again.
  bool _useSystemIme = false;

  /// Guards the deliberate unfocus/refocus cycle [_showSystemIme] performs so
  /// the focus-loss listener doesn't read it as "editing was abandoned".
  bool _imeSwitch = false;

  bool get _tvShell =>
      PlatformUtil.isAndroidTvCached &&
      StorageService.tvKeyboardEnabledCached &&
      widget.enabled;

  @override
  void initState() {
    super.initState();
    _shellNode.addListener(_handleFocusChange);
    _editNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant TvTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalShellNode)?.removeListener(
        _handleFocusChange,
      );
      _shellNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _kb?.dispose();
    (widget.focusNode ?? _internalShellNode)?.removeListener(
      _handleFocusChange,
    );
    _internalShellNode?.dispose();
    _editNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    // Editing must not outlive the editor's focus: if a background focus grab
    // (or a route push) moves focus elsewhere, take the keyboard down instead
    // of leaving a zombie overlay. hasFocus on the shell includes the editor
    // (it's a descendant), so the ring stays lit while editing.
    if (_editing && !_imeSwitch && !_editNode.hasFocus && !_shellNode.hasFocus) {
      _endEdit(refocusShell: false);
    }
    // System-IME hand-off ends itself when focus leaves the field — shell mode
    // (and the Debrify keyboard) come back for the next visit.
    if (_useSystemIme && !_imeSwitch && !_editNode.hasFocus) {
      _useSystemIme = false;
      if (mounted) setState(() {});
    }
    final focused = _shellNode.hasFocus || _editNode.hasFocus;
    if (mounted && focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  // ---------------------------------------------------------------- editing

  void _beginEdit() {
    if (_editing || !mounted) return;
    _useSystemIme = false;
    _kb?.dispose();
    _kb = TvKeyboardController(
      onInsert: _insertText,
      onBackspace: _backspace,
      onClear: _clearText,
      onSubmit: _submitFromKeyboard,
      onSystemIme: _switchToSystemIme,
      submitLabel: switch (widget.textInputAction) {
        TextInputAction.search => 'Search',
        TextInputAction.go => 'Go',
        TextInputAction.next => 'Next',
        TextInputAction.send => 'Send',
        _ => 'Done',
      },
      startShifted:
          widget.textCapitalization != TextCapitalization.none &&
          widget.controller.text.isEmpty,
    );
    final overlay = Overlay.of(context, rootOverlay: true);
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 16,
        child: SafeArea(
          child: Center(child: TvKeyboardPanel(controller: _kb!)),
        ),
      ),
    );
    overlay.insert(_overlay!);
    if (!widget.controller.selection.isValid) {
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    }
    setState(() => _editing = true);
    _editNode.requestFocus();
    // Bottom-anchored panel can cover fields in the lower third of a scrollable
    // page (settings rows) — nudge the field into the visible band. No-op when
    // there's no enclosing scrollable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 150),
      );
    });
  }

  void _endEdit({bool refocusShell = true}) {
    if (!_editing) return;
    _editing = false;
    _useSystemIme = false;
    _removeOverlay();
    if (mounted) {
      if (refocusShell) _shellNode.requestFocus();
      setState(() {});
    }
  }

  /// Hand the field to the system keyboard: end OUR editing session entirely
  /// (no overlay, no interception left anywhere), rebuild the field with a
  /// real input type, then cycle focus so the editor opens a fresh input
  /// connection and SHOWS the IME — that visible TV-side session is what makes
  /// the phone-remote keyboard (and voice) light up. From here the field is a
  /// plain TextField until focus leaves it.
  void _switchToSystemIme() {
    if (!_editing || _useSystemIme) return;
    _editing = false;
    _removeOverlay();
    _kb?.dispose();
    _kb = null;
    setState(() => _useSystemIme = true);
    _imeSwitch = true;
    _editNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imeSwitch = false;
      if (mounted && _useSystemIme) _editNode.requestFocus();
    });
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
  }

  /// Applies the edit exactly like an IME would: run [TvTextField.inputFormatters]
  /// over the candidate value, write the result, and report onChanged only when
  /// the text actually changed (a formatter may reject the whole edit).
  void _applyEdit(TextEditingValue oldValue, TextEditingValue candidate) {
    var next = candidate;
    for (final f in widget.inputFormatters ?? const <TextInputFormatter>[]) {
      next = f.formatEditUpdate(oldValue, next);
    }
    widget.controller.value = next;
    if (next.text != oldValue.text) widget.onChanged?.call(next.text);
  }

  void _insertText(String s) {
    final v = widget.controller.value;
    final sel = v.selection;
    final start = sel.isValid ? sel.start : v.text.length;
    final end = sel.isValid ? sel.end : v.text.length;
    _applyEdit(
      v,
      TextEditingValue(
        text: v.text.replaceRange(start, end, s),
        selection: TextSelection.collapsed(offset: start + s.length),
      ),
    );
  }

  void _backspace() {
    final v = widget.controller.value;
    final sel = v.selection;
    final start = sel.isValid ? sel.start : v.text.length;
    final end = sel.isValid ? sel.end : v.text.length;
    if (start == end) {
      if (start == 0) return;
      // Delete one grapheme, not one code unit, so emoji/accents don't split.
      final before = v.text.substring(0, start);
      final len = before.characters.last.length;
      _applyEdit(
        v,
        TextEditingValue(
          text: v.text.replaceRange(start - len, start, ''),
          selection: TextSelection.collapsed(offset: start - len),
        ),
      );
      return;
    }
    _applyEdit(
      v,
      TextEditingValue(
        text: v.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }

  void _clearText() {
    _applyEdit(
      widget.controller.value,
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
  }

  void _submitFromKeyboard() {
    final text = widget.controller.text;
    _endEdit();
    widget.onSubmitted?.call(text);
  }

  /// IME editor action (from the system keyboard during a hand-off, or a
  /// phone-remote app) — treat it like our Search key: session over, back to
  /// the shell.
  void _onFieldSubmitted(String text) {
    if (_tvShell) {
      _endEdit();
      if (_useSystemIme) {
        setState(() => _useSystemIme = false);
        _shellNode.requestFocus();
      }
    }
    widget.onSubmitted?.call(text);
  }

  // ------------------------------------------------------------------- keys

  KeyEventResult _handleShellKey(FocusNode node, KeyEvent event) {
    // Arrows accept key-repeat (held DPAD keeps moving); OK/Back act on the
    // initial press only, so holding can't machine-gun edit sessions.
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final repeat = event is KeyRepeatEvent;
    // System-IME hand-off: intercept NOTHING. Keys, Back and focus behave
    // exactly like the Debrify-keyboard-off mode — the escape paths the
    // screen already provides (and that are known to work) stay intact.
    if (_useSystemIme) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_editing) {
      if (!repeat &&
          (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.browserBack)) {
        _endEdit();
        return KeyEventResult.handled;
      }
      // Safety net: the edit-time Shortcuts below normally consume these
      // before they bubble this far.
      if (_kb != null && _kb!.handleKey(event)) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }

    // Only when the SHELL itself is the focused node: OK on a focusable child
    // inside the field (a suffix ✕ / submit icon) must bubble on to the
    // framework's activation shortcuts and press that button instead.
    if (!repeat && isActivateKey(key) && node.hasPrimaryFocus) {
      _beginEdit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onUpArrow != null) {
      widget.onUpArrow!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && widget.onDownArrow != null) {
      widget.onDownArrow!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && widget.onLeftArrow != null) {
      widget.onLeftArrow!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && widget.onRightArrow != null) {
      widget.onRightArrow!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------ build

  InputDecoration _buildDecoration(bool shellFocused) {
    var deco =
        widget.decoration ??
        InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          errorText: widget.errorText,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
        );
    // The shell isn't the TextField's focus, so borrow the focused border for
    // the ring — the field looks "selected" without any keyboard appearing.
    if (shellFocused && !_editing && !_useSystemIme && deco.focusedBorder != null) {
      deco = deco.copyWith(enabledBorder: deco.focusedBorder);
    }
    return deco;
  }

  /// One editor construction for both modes; [TextFormField] when a
  /// [TvTextField.validator] is given so enclosing Forms keep working.
  Widget _buildField({
    required FocusNode focusNode,
    required InputDecoration decoration,
    required TextInputType? keyboardType,
    required ValueChanged<String>? onSubmitted,
    bool autofocus = false,
    bool enabled = true,
    GestureTapCallback? onTap,
  }) {
    if (widget.validator != null) {
      return TextFormField(
        controller: widget.controller,
        focusNode: focusNode,
        autofocus: autofocus,
        decoration: decoration,
        style: widget.style,
        textAlign: widget.textAlign,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        keyboardType: keyboardType,
        enabled: enabled,
        obscureText: widget.obscureText,
        cursorColor: widget.cursorColor,
        inputFormatters: widget.inputFormatters,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        onChanged: widget.onChanged,
        onFieldSubmitted: onSubmitted,
        onTap: onTap,
      );
    }
    return TextField(
      controller: widget.controller,
      focusNode: focusNode,
      autofocus: autofocus,
      decoration: decoration,
      style: widget.style,
      textAlign: widget.textAlign,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      keyboardType: keyboardType,
      enabled: enabled,
      obscureText: widget.obscureText,
      cursorColor: widget.cursorColor,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
    );
  }

  /// Caret-at-edge checks for the passthrough arrow exits. An invalid
  /// selection (field never focused yet) counts as both edges.
  bool get _caretAtStart {
    final sel = widget.controller.selection;
    return widget.controller.text.isEmpty ||
        !sel.isValid ||
        (sel.isCollapsed && sel.start <= 0);
  }

  bool get _caretAtEnd {
    final sel = widget.controller.selection;
    return widget.controller.text.isEmpty ||
        !sel.isValid ||
        (sel.isCollapsed && sel.end >= widget.controller.text.length);
  }

  /// TV with the Debrify keyboard opted out: the converted screens deleted
  /// their per-field DPAD handlers (the shell replaces them), so this restores
  /// arrow exits for the plain-TextField mode. Up/Down always leave — a
  /// single-line field has no vertical caret, and the focused editable would
  /// otherwise consume them and trap the remote in the field — falling back to
  /// directional traversal when no explicit callback is wired. Left/Right
  /// leave only from the text edges, via a Shortcuts override because the
  /// editable otherwise consumes edge presses silently. Never active off TV.
  Widget _wrapPassthroughArrows(Widget field) {
    if (!PlatformUtil.isAndroidTvCached) return field;
    if (widget.onLeftArrow != null || widget.onRightArrow != null) {
      field = Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): _EdgeLeftIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _EdgeRightIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _EdgeLeftIntent: _EdgeLeftAction(this),
            _EdgeRightIntent: _EdgeRightAction(this),
          },
          child: field,
        ),
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored; // repeats ok
        // Wired callback: always consume. Default: consume only when
        // traversal actually moved focus — otherwise the key must keep
        // bubbling so ancestor handlers (zone-model sheets, screen-level
        // Focus interceptors) still see it, exactly as before conversion.
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (widget.onUpArrow != null) {
            widget.onUpArrow!();
            return KeyEventResult.handled;
          }
          return _shellNode.focusInDirection(TraversalDirection.up)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (widget.onDownArrow != null) {
            widget.onDownArrow!();
            return KeyEventResult.handled;
          }
          return _shellNode.focusInDirection(TraversalDirection.down)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_tvShell) {
      return _wrapPassthroughArrows(
        _buildField(
          focusNode: _shellNode,
          autofocus: widget.autofocus,
          decoration: _buildDecoration(false),
          keyboardType: widget.keyboardType,
          enabled: widget.enabled,
          onSubmitted: widget.onSubmitted,
        ),
      );
    }

    final shellFocused = _focused;
    Widget field = _buildField(
      focusNode: _editNode,
      decoration: _buildDecoration(shellFocused),
      // The whole point: never let the system IME near this field — except in
      // the explicit hand-off (smartphone key), which needs a real input type
      // for the phone-remote/voice IME session to engage.
      keyboardType: _useSystemIme
          ? (widget.keyboardType ?? TextInputType.text)
          : TextInputType.none,
      onSubmitted: _onFieldSubmitted,
      // During a system-IME hand-off a tap belongs to the stock field (it
      // re-shows the IME); otherwise it starts a Debrify-keyboard session.
      onTap: _useSystemIme ? null : _beginEdit,
    );

    // The shell needs a visible focused state. Decorations that define a
    // focusedBorder get it via the swap in [_buildDecoration]; for the rest
    // (none given, or one that leans on the theme for its focused look) draw
    // the same accent ring the hand-rolled _TvFriendlyTextField shells drew.
    if (widget.shellRing && widget.decoration?.focusedBorder == null) {
      field = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: shellFocused && !_editing && !_useSystemIme
              ? Border.all(color: const Color(0xFF7B5CFF), width: 2)
              : null,
        ),
        child: field,
      );
    }

    return Focus(
      focusNode: _shellNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleShellKey,
      child: Shortcuts(
        // In the system-IME hand-off the panel is gone: leave every key to the
        // IME / stock text editing instead of routing it at a dead keyboard.
        shortcuts: _useSystemIme
            ? const <ShortcutActivator, Intent>{}
            : const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.arrowLeft): _KbNavIntent(-1, 0),
                SingleActivator(LogicalKeyboardKey.arrowRight): _KbNavIntent(1, 0),
                SingleActivator(LogicalKeyboardKey.arrowUp): _KbNavIntent(0, -1),
                SingleActivator(LogicalKeyboardKey.arrowDown): _KbNavIntent(0, 1),
                SingleActivator(LogicalKeyboardKey.select): _KbActivateIntent(),
                SingleActivator(LogicalKeyboardKey.enter): _KbActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter): _KbActivateIntent(),
                SingleActivator(LogicalKeyboardKey.gameButtonA): _KbActivateIntent(),
              },
        child: Actions(
          // isEnabled-gated: outside an active edit session (e.g. a suffix ✕
          // button inside this subtree holds focus) the disabled actions fall
          // through, so the key keeps bubbling instead of dying against a
          // null/stale keyboard controller.
          actions: <Type, Action<Intent>>{
            _KbNavIntent: _KbNavAction(this),
            _KbActivateIntent: _KbActivateAction(this),
          },
          child: field,
        ),
      ),
    );
  }
}
