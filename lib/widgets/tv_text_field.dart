import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/storage_service.dart';
import '../services/tv_voice_input.dart';
import '../theme/overlay_theme.dart';
import '../services/tvos_keyboard_signal.dart';
import '../utils/platform_util.dart';
import '../utils/tv_keys.dart';
import 'onboarding/tv_keyboard_slot.dart';
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
    this.keyboardSubmitLabel,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.autofocus = false,
    this.forceTvKeyboard = false,
    this.enabled = true,
    this.obscureText = false,
    this.cursorColor,
    this.inputFormatters,
    this.autofillHints,
    this.validator,
    this.shellRing = true,
    this.accent = const Color(0xFF7B5CFF),
    this.keyboardGround = const Color(0xF01A1630),
    this.keyboardInk = Colors.white,
    this.keyboardInkOnAccent = Colors.white,
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
  final String? keyboardSubmitLabel;
  final TextCapitalization textCapitalization;

  /// Off-TV / opt-out only; the shell always uses [TextInputType.none].
  final TextInputType? keyboardType;

  /// On TV this focuses the SHELL (no keyboard pops); elsewhere the field.
  final bool autofocus;

  /// Forces the in-app keyboard even when the platform TV probe is unavailable.
  /// Intended for terminal recovery surfaces where falling back to a broken TV
  /// system IME could make the data-preserving action impossible.
  final bool forceTvKeyboard;
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

  // ─────────────────────────────────────────────────────── caller-supplied ink
  //
  // This field is rendered by themed surfaces, by surfaces still scheduled for
  // conversion, and by the video player — which stays legacy permanently — so
  // it can neither read the app theme nor keep a fixed palette. Each token
  // below is OPTIONAL and defaults to the exact literal it replaces, so a call
  // site that passes nothing renders byte-identically to what shipped and each
  // surface can opt in on its own schedule.

  /// The shell's focus ring, and every filled accent on the keyboard panel
  /// this field owns (highlighted keycap, latched shift, mic disc + halo,
  /// notice bar).
  final Color? accent;

  /// The keyboard panel's ground.
  final Color? keyboardGround;

  /// All keyboard-panel foreground; today's alphas ride on top of it.
  final Color? keyboardInk;

  /// Keyboard foreground ON a filled [accent] — separate from [keyboardInk]
  /// because half the shipped themes have light accents, where white ink on
  /// the highlighted keycap would be invisible.
  final Color? keyboardInkOnAccent;

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
    // Nothing to navigate while the mic is open — the grid isn't on screen.
    // Consumed rather than passed on so a stray press can't move a highlight
    // the user can't see (or worse, escape the field mid-sentence).
    if (state._kb!.listening) return null;
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
    // OK means "done talking" while listening — NOT "press the key under the
    // hidden highlight", which would type a stray letter mid-dictation.
    if (state._kb!.listening) {
      state._stopVoiceInput();
      return null;
    }
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
  @visibleForTesting
  bool get debugHasKeyboardOverlay => _overlay != null;

  /// TV only: the actual TextField's node — skipTraversal so the shell is the
  /// only DPAD stop; focused exclusively by OK ("start editing") or a tap.
  final FocusNode _editNode = FocusNode(
    debugLabel: 'tv-textfield-edit',
    skipTraversal: true,
  );

  FocusNode? _internalShellNode;
  FocusNode get _shellNode =>
      widget.focusNode ??
      (_internalShellNode ??= FocusNode(debugLabel: 'tv-textfield-shell'));

  TvKeyboardController? _kb;
  OverlayEntry? _overlay;
  TvKeyboardSession? _keyboardSlot;
  bool _editing = false;
  bool _focused = false;

  /// Set when a Back KEY-DOWN closed the keyboard; the matching KEY-UP must
  /// be swallowed too. Android fires the actual back action on the UP: an
  /// unhandled up gets redispatched by the engine → onBackPressed →
  /// popRoute — and by then [_editing] is already false, so the PopScope
  /// guard below is un-armed and the route pops. One press would close the
  /// keyboard AND leave the screen.
  bool _swallowBackUp = false;

  /// Keeps the PopScope armed for a beat after a Back-key close. TV builds
  /// differ in HOW the same physical press turns into a route pop (key-event
  /// redispatch, onBackPressed, predictive back) — some paths deliver the
  /// pop after [_editing] already flipped false, un-arming a naive
  /// `canPop: !_editing`. Any pop landing inside this window belongs to the
  /// press that closed the keyboard and is swallowed. Only Back-key closes
  /// arm it — submit/focus-loss closes must not eat a legitimate follow-up
  /// back press.
  bool _popGuard = false;
  Timer? _popGuardTimer;

  /// True while a route pop belongs to this field's in-app keyboard — editing
  /// is active, or the guard window after a Back-key close is still armed.
  ///
  /// A vetoed pop is broadcast to EVERY PopScope on the route, so a page
  /// whose own PopScope vetoes pops (save-on-back editors) must consult this
  /// from its handler and do nothing when the press was the keyboard's.
  bool get popConsumedByShell => _editing || _popGuard;

  void _armPopGuard() {
    _popGuard = true;
    _keyboardSlot?.holdBack();
    _popGuardTimer?.cancel();
    // Same-press pops arrive within milliseconds; 300ms covers any dispatch
    // path's latency while staying under a deliberate human double-press.
    _popGuardTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        _popGuard = false;
        return;
      }
      setState(() => _popGuard = false);
    });
  }

  /// The field was handed to the system IME (the keyboard's smartphone key):
  /// it runs with a real input type so the Google TV phone-remote keyboard /
  /// voice input engage, and this widget intercepts NOTHING — keys, focus and
  /// Back behave exactly like the Debrify-keyboard-off mode, which is the
  /// known-good escape path. Restores shell mode the moment focus leaves the
  /// field, so the next DPAD visit starts on the Debrify keyboard again.
  bool _useSystemIme = false;

  /// A dictation is in flight — from the permission dialog (a system window
  /// that takes our focus) through to the transcript landing. Guards the mic
  /// key against a second session, and the focus-loss teardown against
  /// mistaking the dialog for an abandoned edit.
  bool _voiceListening = false;

  /// Set between "done talking" and the transcript landing — see
  /// [_stopVoiceInput], which must reach native exactly once.
  bool _voiceStopping = false;
  StreamSubscription<TvVoiceEvent>? _voiceSub;

  /// Backstop for a recognition service that binds and then says nothing at
  /// all (seen on some OEM builds): without it the panel would sit on
  /// "Listening…" forever with no way out but Back.
  Timer? _voiceWatchdog;
  Timer? _noticeTimer;

  /// Guards the deliberate unfocus/refocus cycle [_showSystemIme] performs so
  /// the focus-loss listener doesn't read it as "editing was abandoned".
  bool _imeSwitch = false;

  /// Apple TV takes this path too when the user opts into the Debrify keyboard.
  /// Its system keyboard is the tvOS default; [TvosKeyboardSignal] bridges the
  /// platform's missing `onSubmitted` callback for that passthrough path.
  bool get _tvShell =>
      (widget.forceTvKeyboard ||
          (PlatformUtil.isTelevision &&
              StorageService.tvKeyboardEnabledCached)) &&
      widget.enabled;

  /// Cancels the Apple TV "editing finished" subscription.
  VoidCallback? _tvosEndEditing;

  @override
  void initState() {
    super.initState();
    if (PlatformUtil.isTvOS) {
      _tvosEndEditing = TvosKeyboardSignal.listen(_handleTvosEndEditing);
    }
    _shellNode.addListener(_handleFocusChange);
    _editNode.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardSlot = TvKeyboardSlot.maybeOf(context);
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
    // The disabled passthrough TextField sets the shared shell node's
    // canRequestFocus to false. When TV-shell mode comes back, its outer Focus
    // reuses that node and does not reset the property on its own.
    if (!oldWidget.enabled && widget.enabled && _tvShell) {
      _shellNode.canRequestFocus = true;
    }
  }

  @override
  void dispose() {
    _tvosEndEditing?.call();
    _popGuardTimer?.cancel();
    _noticeTimer?.cancel();
    _cancelVoiceSession();
    _removeOverlay();
    final keyboard = _kb;
    final slot = _keyboardSlot;
    _kb = null;
    if (keyboard != null && slot != null) {
      slot.detachDeferred(keyboard, afterDetach: keyboard.dispose);
    } else {
      keyboard?.dispose();
    }
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
    if (_editing &&
        !_imeSwitch &&
        !_voiceListening &&
        !_editNode.hasFocus &&
        !_shellNode.hasFocus) {
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
      onVoice: _startVoiceInput,
      onVoiceStop: _stopVoiceInput,
      onPaste: _pasteFromClipboard,
      voiceAvailable: TvVoiceInput.availableCached ?? false,
      submitLabel:
          widget.keyboardSubmitLabel ??
          switch (widget.textInputAction) {
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
    final slot = _keyboardSlot;
    if (slot != null) {
      slot.attach(_kb!);
    } else {
      final overlay = Overlay.of(context, rootOverlay: true);
      // A bare OverlayEntry inherits nothing local — and this keyboard opens
      // from INCLUDED and FROZEN surfaces alike. Snapshot the field's ambient
      // themes so the panel renders what its field renders (the legacy freeze
      // included when the field sits inside a LegacyThemeBoundary). Inside the
      // Positioned: CapturedThemes.wrap inserts plain widgets, and Positioned
      // must stay the overlay Stack's direct child.
      final capturedThemes = captureAppThemes(context);
      _overlay = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: capturedThemes.wrap(
            SafeArea(
              child: Center(
                child: TvKeyboardPanel(
                  controller: _kb!,
                  // The bottom-anchored panel can cover the very field it
                  // edits; the preview keeps what's typed in sight. Only this
                  // overlay path passes it — the onboarding slot's field band
                  // is already visible directly above its keyboard.
                  previewController: widget.controller,
                  previewObscure: widget.obscureText,
                  previewHint:
                      widget.hintText ??
                      widget.labelText ??
                      widget.decoration?.hintText ??
                      widget.decoration?.labelText,
                  // The panel's own defaults are these same literals, so a token
                  // left null lands on exactly what shipped either way.
                  accent: widget.accent,
                  ground: widget.keyboardGround,
                  ink: widget.keyboardInk,
                  inkOnAccent: widget.keyboardInkOnAccent,
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(_overlay!);
    }
    if (!widget.controller.selection.isValid) {
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    }
    setState(() => _editing = true);
    _editNode.requestFocus();
    // Probe voice support the first time a keyboard opens; the mic key
    // appears if this device has a recognizer (cached process-wide after).
    if (TvVoiceInput.availableCached == null) {
      TvVoiceInput.isAvailable().then((ok) {
        if (mounted && ok) _kb?.setVoiceAvailable(true);
      });
    }
    // Bottom-anchored panel can cover fields in the lower third of a scrollable
    // page (settings rows) — nudge the field into the visible band. No-op when
    // there's no enclosing scrollable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      if (_keyboardSlot == null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.2,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  void _endEdit({bool refocusShell = true}) {
    if (!_editing) return;
    // The mic must never outlive the session that opened it.
    _cancelVoiceSession();
    _noticeTimer?.cancel();
    _editing = false;
    _useSystemIme = false;
    _removeOverlay();
    final keyboard = _kb;
    if (keyboard != null) _keyboardSlot?.detach(keyboard);
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
    final keyboard = _kb;
    if (keyboard != null) _keyboardSlot?.detach(keyboard);
    keyboard?.dispose();
    _kb = null;
    setState(() => _useSystemIme = true);
    _imeSwitch = true;
    _editNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imeSwitch = false;
      if (mounted && _useSystemIme) _editNode.requestFocus();
    });
  }

  // ------------------------------------------------------------------ voice

  /// Mic key: open the microphone IN-APP and let the keyboard panel become the
  /// listening surface. Nothing else appears on screen — no system voice
  /// activity, no second text box — so our activity is never paused, no
  /// lifecycle handler fires (the ambient trailer keeps playing), and focus
  /// never leaves the editor. The only trip out is the one-off permission
  /// dialog, which [_voiceListening] covers.
  Future<void> _startVoiceInput() async {
    if (!_editing || _voiceListening) return;
    _noticeTimer?.cancel();
    _kb?.clearNotice();
    // Set before the await: the permission dialog steals focus, and without
    // the guard the focus-loss listener would tear the whole session down.
    _voiceListening = true;
    final granted = await TvVoiceInput.ensurePermission();
    if (!mounted || !_editing) {
      _voiceListening = false;
      return;
    }
    // The dialog (granted or not) may have taken focus from the editor.
    _editNode.requestFocus();
    if (!granted) {
      _finishVoice(notice: 'Microphone permission needed for voice input');
      return;
    }
    _kb?.beginListening();
    _voiceSub?.cancel();
    _voiceSub = TvVoiceInput.events.listen(_onVoiceEvent);
    _armVoiceWatchdog();
    if (!await TvVoiceInput.start()) {
      _finishVoice(notice: "Voice input isn't working on this device");
    }
  }

  /// OK while listening — stop recording but keep the session: the engine
  /// still transcribes what it heard and a result event follows.
  ///
  /// Strictly once per session. A held OK repeats (SingleActivator counts
  /// repeats by default), and a second `stopListening()` on an already-stopped
  /// engine makes some services answer ERROR_CLIENT — throwing away the very
  /// transcript this press was waiting for.
  void _stopVoiceInput() {
    if (!_voiceListening || _voiceStopping) return;
    _voiceStopping = true;
    _kb?.updateListening(level: 0, status: 'Getting that…');
    TvVoiceInput.stop();
  }

  /// Back while listening — throw the dictation away and return to the keys
  /// with whatever was typed before still intact.
  void _cancelVoiceInput() {
    if (!_voiceListening) return;
    _finishVoice();
  }

  void _onVoiceEvent(TvVoiceEvent event) {
    if (!_voiceListening || !mounted) return;
    _armVoiceWatchdog(); // any sign of life resets the deadline
    switch (event.type) {
      case 'ready':
      case 'speech':
        _kb?.updateListening(status: 'Listening…');
      case 'level':
        // The platform reports roughly -2 dB (silence) to 10 dB (loud);
        // the meter wants 0..1.
        _kb?.updateListening(level: ((event.level ?? 0) + 2) / 12);
      case 'partial':
        _kb?.updateListening(partial: event.text ?? '', status: 'Listening…');
      case 'processing':
        _kb?.updateListening(level: 0, status: 'Getting that…');
      case 'result':
        final spoken = event.text?.trim() ?? '';
        _finishVoice();
        if (spoken.isNotEmpty) _applySpokenText(spoken);
      case 'error':
        // Timeout/no-match AFTER words already appeared isn't a failure worth
        // reporting — keep what was heard rather than throwing it away.
        if (event.code == 6 || event.code == 7) {
          _finishVoiceKeepingWhatWasHeard(
            TvVoiceInput.describeError(event.code),
          );
        } else {
          _finishVoice(notice: TvVoiceInput.describeError(event.code));
        }
      case 'aborted':
        // App went to the background mid-sentence; the mic is gone.
        _finishVoice();
    }
  }

  /// Dictation REPLACES the field, matching every TV voice search: people
  /// speak the whole query, they don't dictate a suffix onto a typo.
  void _applySpokenText(String spoken) {
    _applyEdit(
      widget.controller.value,
      TextEditingValue(
        text: spoken,
        selection: TextSelection.collapsed(offset: spoken.length),
      ),
    );
  }

  /// Ends a session that died AFTER words had already appeared on the panel,
  /// keeping them: the user watched the recognizer get it right, and a service
  /// that then falls over doesn't make that transcript any less theirs.
  /// [notice] is only used when nothing was heard at all.
  void _finishVoiceKeepingWhatWasHeard(String notice) {
    final heard = _kb?.partial.trim() ?? '';
    if (heard.isEmpty) {
      _finishVoice(notice: notice);
      return;
    }
    _finishVoice();
    _applySpokenText(heard);
  }

  void _armVoiceWatchdog() {
    _voiceWatchdog?.cancel();
    // Levels stream continuously while a healthy session is open, so silence
    // this long means the service is gone, not that the user is quiet.
    _voiceWatchdog = Timer(const Duration(seconds: 12), () {
      if (!_voiceListening) return;
      // A stalled OEM service is the likeliest way to reach this — and the
      // likeliest to have emitted partials first. Same salvage as a timeout.
      _finishVoiceKeepingWhatWasHeard("Voice input isn't responding");
    });
  }

  /// Ends the session and puts the keys back. [notice] is shown above them
  /// briefly; a clean finish passes none.
  void _finishVoice({String? notice}) {
    _cancelVoiceSession();
    if (!mounted) return;
    _kb?.endListening(notice: notice);
    if (notice != null) _armNoticeClear();
    if (_editing) _editNode.requestFocus();
  }

  /// Tears down the native session and every timer/subscription behind it,
  /// with no UI side effects — safe from dispose and from [_endEdit].
  void _cancelVoiceSession() {
    _voiceWatchdog?.cancel();
    _voiceWatchdog = null;
    _voiceSub?.cancel();
    _voiceSub = null;
    _voiceStopping = false;
    if (_voiceListening) {
      _voiceListening = false;
      TvVoiceInput.cancel();
    }
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

  /// Inserts text through the same formatter/onChanged path as a keyboard key.
  /// Used by onboarding's Paste method chip.
  void insertText(String s) => _insertText(s);

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

  /// Paste key: the clipboard goes in through the same insert path a keypress
  /// takes, so inputFormatters, onChanged and the caret all behave identically
  /// — a paste is just a very long keystroke.
  Future<void> _pasteFromClipboard() async {
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      // Some TV builds have no clipboard service at all; a dead key beats a
      // crashed keyboard.
      data = null;
    }
    // That await crossed a platform channel, so the session may have ended
    // under it (BACK, submit, a background focus grab) — never write into an
    // editor that is no longer being edited.
    if (!mounted || !_editing) return;
    // Every TvTextField is single-line (the multi-line paste dialogs kept
    // their plain TextFields), so a URL copied with its trailing newline must
    // not bring one along.
    final text = (data?.text ?? '')
        .replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ')
        .trim();
    if (text.isEmpty) {
      _showNotice('Nothing to paste', icon: Icons.content_paste_off_rounded);
      return;
    }
    _insertText(text);
  }

  /// Says one line above the keys, then takes it away again.
  void _showNotice(String text, {IconData? icon}) {
    _kb?.showNotice(text, icon: icon);
    _armNoticeClear();
  }

  void _armNoticeClear() {
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _kb?.clearNotice();
    });
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
    _endPlatformImeSession();
    widget.onSubmitted?.call(text);
  }

  /// Close out a platform-IME hand-off and hand the shell back its focus.
  ///
  /// Separate from [_onFieldSubmitted] because the session can end WITHOUT a
  /// submission — on Apple TV the keyboard can be dismissed having changed
  /// nothing — and that still has to unwind, or the field stays in hand-off
  /// mode with the in-app keyboard gone. Nothing else unwinds it there: the
  /// dismissal produces no Dart focus change.
  void _endPlatformImeSession() {
    if (!_tvShell) return;
    _endEdit();
    if (_useSystemIme) {
      setState(() => _useSystemIme = false);
      _shellNode.requestFocus();
    }
  }

  // ------------------------------------------------------------------- keys

  KeyEventResult _handleShellKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isBackKey =
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack;
    // Arrows accept key-repeat (held DPAD keeps moving); OK/Back act on the
    // initial press only, so holding can't machine-gun edit sessions.
    if (event is KeyUpEvent) {
      // See [_swallowBackUp]: the UP of the press that closed the keyboard
      // must never bubble unhandled, or Android turns it into a back action.
      if (isBackKey && _swallowBackUp) {
        _swallowBackUp = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final repeat = event is KeyRepeatEvent;
    // Flag hygiene: [_swallowBackUp] pairs strictly with the MOST RECENT
    // Back key-down. If an old up never reached this handler (a focus race
    // moved the up elsewhere), a stale flag would eat the up of a later
    // press whose down was deliberately left to the screen.
    if (isBackKey && !repeat) _swallowBackUp = false;
    // System-IME hand-off: intercept NOTHING. Keys, Back and focus behave
    // exactly like the Debrify-keyboard-off mode — the escape paths the
    // screen already provides (and that are known to work) stay intact.
    if (_useSystemIme) return KeyEventResult.ignored;

    if (_editing) {
      // Back during dictation cancels the DICTATION, not the edit — the
      // keyboard comes back with whatever was already typed.
      if (isBackKey && _voiceListening) {
        if (!repeat) {
          _swallowBackUp = true;
          _armPopGuard(); // the up of this press must not pop the route
          _cancelVoiceInput();
        }
        return KeyEventResult.handled;
      }
      if (isBackKey) {
        // Repeats included: a held Back must not leak DOWN events either
        // (only the first press acts; the rest are just consumed).
        if (!repeat) {
          _swallowBackUp = true;
          _armPopGuard(); // before _endEdit — same rebuild registers it
          _endEdit();
        }
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
    if (shellFocused &&
        !_editing &&
        !_useSystemIme &&
        deco.focusedBorder != null) {
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
    bool readOnly = false,
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
        readOnly: readOnly,
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
      readOnly: readOnly,
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
    if (!PlatformUtil.isTelevision) return field;
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

  /// Apple TV finished a platform-keyboard session — the only "submit" signal
  /// the OS gives us (see [TvosKeyboardSignal]).
  ///
  /// Deliberately narrow, because the signal is app-wide and cannot tell a
  /// commit from a cancel:
  /// * only the field actually being edited reacts, so one keyboard session
  ///   can't submit every mounted field;
  /// * only when the platform keyboard was really in play — with the Debrify
  ///   keyboard on, the field is `readOnly` and never opens a platform
  ///   session, so this must not fire there.
  ///
  /// Beyond that it does NOT second-guess the user: see the comment inside.
  void _handleTvosEndEditing() {
    if (!mounted || !PlatformUtil.isTvOS) return;
    final usingPlatformKeyboard = !_tvShell || _useSystemIme;
    if (!usingPlatformKeyboard) return;
    final node = _tvShell ? _editNode : _shellNode;
    if (!node.hasFocus) return;
    // Submit unconditionally — no "did the text change" test.
    //
    // That test looked prudent (it stopped a BACK press from submitting when
    // nothing was typed) but it bought that by breaking the case the fix
    // exists for: pressing the action key on a PREFILLED or deliberately
    // unchanged field then did nothing, and neither did submitting the same
    // search twice. Since the action key and BACK are indistinguishable here,
    // suppressing one necessarily suppresses the other — and of the two, a
    // dead action key is a bug while a redundant re-submit of identical text
    // is merely redundant.
    _onFieldSubmitted(widget.controller.text);
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
      // tvOS presents its fullscreen keyboard for ANY focused text field, and
      // `TextInputType.none` does not stop it the way it does on Android — so
      // pressing a key on the Debrify keyboard summoned Apple's on top of it.
      // `readOnly` is the stronger statement: Flutter never opens a platform
      // text-input connection at all.
      //
      // The trade, stated honestly: without that connection there is no
      // system caret and a paired Bluetooth keyboard cannot type into the
      // field either — the Debrify keys write to the controller directly, so
      // they are unaffected. On tvOS that is the better half of the deal,
      // because the alternative is Apple's keyboard covering ours on every
      // keypress. Lifted for the explicit hand-off below.
      readOnly: PlatformUtil.isTvOS && !_useSystemIme,
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
              ? Border.all(
                  color: widget.accent ?? const Color(0xFF7B5CFF),
                  width: 2,
                )
              : null,
        ),
        child: field,
      );
    }

    // While the Debrify keyboard is up, Back must only take the panel down.
    // Consuming the Back KeyEvent in [_handleShellKey] is not enough on its
    // own: Android also dispatches Back through the navigation channel
    // (onBackPressed / OnBackInvokedCallback — the predictive-back path), which
    // ignores key-event consumption and pops the route. That double dispatch is
    // exactly why the screen used to leave *and* the keyboard close together.
    // PopScope intercepts that nav-channel back so editing ends without popping.
    // [_popGuard] keeps it armed through the whole press: the key-DOWN handler
    // already flipped [_editing] false before the same press's pop arrives, so
    // `!_editing` alone re-arms the route a few milliseconds too early.
    return PopScope(
      canPop: !_editing && !_popGuard,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _endEdit();
      },
      child: Focus(
        focusNode: _shellNode,
        autofocus: widget.autofocus,
        onKeyEvent: _handleShellKey,
        child: Shortcuts(
          // In the system-IME hand-off the panel is gone: leave every key to the
          // IME / stock text editing instead of routing it at a dead keyboard.
          shortcuts: _useSystemIme
              ? const <ShortcutActivator, Intent>{}
              : const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.arrowLeft): _KbNavIntent(
                    -1,
                    0,
                  ),
                  SingleActivator(LogicalKeyboardKey.arrowRight): _KbNavIntent(
                    1,
                    0,
                  ),
                  SingleActivator(LogicalKeyboardKey.arrowUp): _KbNavIntent(
                    0,
                    -1,
                  ),
                  SingleActivator(LogicalKeyboardKey.arrowDown): _KbNavIntent(
                    0,
                    1,
                  ),
                  SingleActivator(LogicalKeyboardKey.select):
                      _KbActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.enter):
                      _KbActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.numpadEnter):
                      _KbActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.gameButtonA):
                      _KbActivateIntent(),
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
      ),
    );
  }
}
