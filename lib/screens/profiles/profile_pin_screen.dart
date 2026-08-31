import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../../widgets/tv_text_field.dart';

/// The Meridian PIN unlock (2026-08-31): the room is lit for one person.
///
/// The profile's wash colour (not the global brand red) drives every accent —
/// the backdrop aurora, the ghost monogram, the entry segments and the Unlock
/// bar. The keypad is bare thin numerals on glass rather than boxed keys, and
/// entry reads as light segments that start at four slots and grow with the
/// PIN (4–8 digits). Flows are untouched: verification, lockout copy,
/// recovery ("Forgot PIN?"), hardware keys and the TV DPAD contract all
/// behave exactly as before.
class ProfilePinScreen extends StatefulWidget {
  final UserProfile profile;
  final Future<ProfilePinVerification> Function(String pin) onSubmit;
  final VoidCallback onCancel;

  /// Recovery-code fallback for a forgotten PIN. When provided, the screen
  /// shows a "Forgot PIN?" action; a verified code has already REMOVED the
  /// profile's PIN by the time this returns [ProfileRecoveryResult.cleared].
  final Future<ProfileRecoveryResult> Function(String code)? onRecovery;

  const ProfilePinScreen({
    super.key,
    required this.profile,
    required this.onSubmit,
    required this.onCancel,
    this.onRecovery,
  });

  @override
  State<ProfilePinScreen> createState() => _ProfilePinScreenState();
}

class _ProfilePinScreenState extends State<ProfilePinScreen> {
  final List<int> _digits = <int>[];
  bool _busy = false;
  String? _error;

  /// One node per TV ladder key (1..9, 0, backspace), so LEFT on the first
  /// key can wrap to the last and RIGHT on the last can wrap to the first —
  /// eleven presses to reach backspace from 1 was the complaint.
  final List<FocusNode> _ladderNodes = List.generate(
    11,
    (i) => FocusNode(debugLabel: 'pin-ladder-$i'),
  );

  bool get _tv => PlatformUtil.isTelevision;

  /// Unlock is honest about its own guard: with fewer than four digits the
  /// bar/disc dims and refuses, instead of glowing invitingly and eating the
  /// press in silence.
  bool get _canSubmit => !_busy && _digits.length >= 4;

  Color get _wash =>
      ProfileAvatarView.washColor(widget.profile.avatarKey, widget.profile.role);

  @override
  void dispose() {
    for (final node in _ladderNodes) {
      node.dispose();
    }
    _digits.clear();
    super.dispose();
  }

  void _add(int digit) {
    if (_busy || _digits.length == 8) return;
    setState(() {
      _digits.add(digit);
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _submit() async {
    if (_busy || _digits.length < 4) return;
    final pin = _digits.join();
    setState(() => _busy = true);
    late final ProfilePinVerification result;
    try {
      result = await widget.onSubmit(pin);
    } catch (_) {
      if (!mounted) return;
      _digits.clear();
      setState(() {
        _busy = false;
        _error = 'Could not unlock profile. Try again.';
      });
      return;
    }
    if (!mounted) return;
    _digits.clear();
    setState(() {
      _busy = false;
      _error = switch (result.result) {
        ProfilePinResult.invalid =>
          result.lockedUntil == null
              ? 'Incorrect PIN'
              : 'Too many attempts. Try again later.',
        ProfilePinResult.locked => 'Profile is temporarily locked',
        ProfilePinResult.resetRequired => 'An Admin must reset this PIN',
        _ => null,
      };
    });
  }

  Future<void> _forgotPin() async {
    final onRecovery = widget.onRecovery;
    if (onRecovery == null || _busy) return;
    final controller = TextEditingController();
    String? errorText;
    var submitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (submitting || controller.text.trim().isEmpty) return;
            setDialogState(() => submitting = true);
            ProfileRecoveryResult result;
            try {
              result = await onRecovery(controller.text);
            } catch (_) {
              result = ProfileRecoveryResult.invalid;
            }
            if (!dialogContext.mounted) return;
            switch (result) {
              case ProfileRecoveryResult.cleared:
                Navigator.of(dialogContext).pop();
              case ProfileRecoveryResult.invalid:
                setDialogState(() {
                  submitting = false;
                  errorText = 'That code does not match';
                });
              case ProfileRecoveryResult.notConfigured:
                setDialogState(() {
                  submitting = false;
                  errorText =
                      'No recovery code exists for this profile — an Admin '
                      'must reset the PIN';
                });
            }
          }

          return AlertDialog(
            title: const Text('Recover profile'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the recovery code shown when this PIN was set. '
                  'It removes the PIN so you can set a new one.',
                ),
                const SizedBox(height: 12),
                TvTextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Recover',
                  decoration: InputDecoration(
                    labelText: 'Recovery code',
                    hintText: 'XXXXX-XXXXX',
                    errorText: errorText,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Recover'),
              ),
            ],
          );
        },
      ),
    );
    controller
      ..clear()
      ..dispose();
  }

  KeyEventResult _handleHardwareKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final label = key.keyLabel;
    if (label.length == 1 && RegExp(r'^\d$').hasMatch(label)) {
      _add(int.parse(label));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    // Enter/select are NEVER claimed here: this handler sits on an ancestor
    // of whichever keypad button holds focus, and claiming them is what
    // broke TV entry — DPAD-center submitted an (empty) PIN instead of
    // pressing the focused button. Digits and backspace are safe to handle
    // for physical keyboards because no child wants them.
    return KeyEventResult.ignored;
  }

  /// Horizontal wrap for the TV ladder: LEFT on the leftmost key jumps to the
  /// rightmost and vice versa. Everything in between stays with the
  /// framework's geometric traversal, so this claims an arrow only at the
  /// two ends.
  KeyEventResult _handleLadderKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        _ladderNodes.first.hasFocus) {
      _ladderNodes.last.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _ladderNodes.last.hasFocus) {
      _ladderNodes.first.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    const ground = Color(0xFF07080C);
    return Scaffold(
      backgroundColor: ground,
      // A pure key LISTENER, never a focus target: when this wrapper was
      // focusable (autofocus: true), it took primary focus and trapped it —
      // every button lies inside its rect, so directional DPAD traversal
      // found no candidate "in any direction" and the keypad was unreachable.
      // With the wrapper unfocusable, the digit-1 button's own autofocus
      // wins, and bubbling still delivers hardware digits/backspace here.
      body: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleHardwareKey,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final phone = constraints.maxWidth < 600;
              final short = constraints.maxHeight < 620;
              return Stack(
                children: [
                  Positioned.fill(
                    child: _MeridianBackdrop(
                      initial: widget.profile.name.trim().isEmpty
                          ? '?'
                          : widget.profile.name
                                .trim()
                                .characters
                                .first
                                .toUpperCase(),
                      wash: _wash,
                      phone: phone,
                    ),
                  ),
                  Positioned(
                    left: phone ? 12 : 20,
                    top: phone ? 8 : 14,
                    child: _RoundBackButton(onPressed: widget.onCancel),
                  ),
                  Positioned.fill(
                    child: phone
                        ? _buildPhone()
                        : _tv
                        ? _buildTelevision()
                        : _buildDesktop(compactHeight: short),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _squircleAvatar(double size) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .26),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
      boxShadow: [
        BoxShadow(
          color: _wash.withValues(alpha: .34),
          blurRadius: size * .4,
          spreadRadius: 2,
        ),
        const BoxShadow(color: Color(0x88000000), blurRadius: 24),
      ],
    ),
    child: ProfileAvatarView(
      profileId: widget.profile.id,
      avatarKey: widget.profile.avatarKey,
      role: widget.profile.role,
      name: widget.profile.name,
      animateWhenIdle: true,
    ),
  );

  Widget _identity({
    required double titleSize,
    bool compact = false,
    bool centered = false,
  }) {
    final nameTint = Color.lerp(_wash, Colors.white, .35)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'PROFILE LOCKED',
          style: TextStyle(
            color: Color.lerp(_wash, Colors.white, .22),
            fontSize: compact ? 9.5 : 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.4,
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(
          'Welcome back,',
          key: const Key('profile-pin-title'),
          style: TextStyle(
            color: const Color(0xFFF4F0E8),
            fontSize: titleSize,
            height: .97,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          child: Text(
            '${widget.profile.name}.',
            key: const Key('profile-pin-name'),
            maxLines: 1,
            style: TextStyle(
              color: nameTint,
              fontSize: titleSize,
              height: .97,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(
          compact || centered
              ? 'Your watchlist is waiting.'
              : 'Enter your PIN — your watchlist is waiting.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .58),
            fontSize: compact ? 12 : 14.5,
          ),
        ),
      ],
    );
  }

  /// The entry segments: four slots that light up in the profile's colour and
  /// grow with the entry (PIN is 4–8 digits) instead of parading eight empty
  /// dots.
  Widget _indicators({required bool compact, bool centered = false}) {
    final slots = _digits.length.clamp(4, 8);
    final segWidth = compact ? 26.0 : 34.0;
    final segHeight = compact ? 8.0 : 10.0;
    final gap = compact ? 10.0 : 13.0;
    return Row(
      key: const Key('profile-pin-indicators'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: List.generate(slots, (index) {
        final filled = index < _digits.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: segWidth,
          height: segHeight,
          margin: EdgeInsets.only(right: index == slots - 1 ? 0 : gap),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(segHeight),
            color: filled ? null : Colors.white.withValues(alpha: .12),
            gradient: filled
                ? LinearGradient(
                    colors: [
                      Color.lerp(_wash, Colors.white, .12)!,
                      Color.lerp(_wash, Colors.white, .38)!,
                    ],
                  )
                : null,
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: _wash.withValues(alpha: .6),
                      blurRadius: 14,
                    ),
                  ]
                : const [],
          ),
        );
      }),
    );
  }

  List<Widget> _digitKeys({List<FocusNode>? nodes, bool horizontal = false}) => [
    for (var digit = 1; digit <= 9; digit++)
      _PinKey(
        key: ValueKey('profile-pin-key-$digit'),
        label: '$digit',
        wash: _wash,
        autofocus: digit == 1,
        focusNode: nodes == null ? null : nodes[digit - 1],
        horizontal: horizontal,
        onPressed: () => _add(digit),
      ),
  ];

  Widget _zeroKey({FocusNode? node, bool horizontal = false}) => _PinKey(
    key: const ValueKey('profile-pin-key-0'),
    label: '0',
    wash: _wash,
    focusNode: node,
    horizontal: horizontal,
    onPressed: () => _add(0),
  );

  Widget _backspaceKey({FocusNode? node, bool horizontal = false}) => _PinKey(
    key: const ValueKey('profile-pin-backspace'),
    icon: Icons.backspace_outlined,
    semanticLabel: 'Backspace',
    wash: _wash,
    focusNode: node,
    horizontal: horizontal,
    onPressed: _backspace,
  );

  List<Widget> _gridKeys() => [
    ..._digitKeys(),
    _backspaceKey(),
    _zeroKey(),
    _PinKey(
      key: const ValueKey('profile-pin-submit'),
      icon: Icons.check_rounded,
      semanticLabel: 'Unlock profile',
      wash: _wash,
      accent: true,
      enabled: _canSubmit,
      busy: _busy,
      onPressed: _submit,
    ),
  ];

  /// Visual order IS node order: [_handleLadderKey] wraps on
  /// `_ladderNodes.first`/`.last`, so any reorder here must move the node
  /// assignments with it.
  List<Widget> _ladderKeys() => [
    ..._digitKeys(nodes: _ladderNodes, horizontal: true),
    _zeroKey(node: _ladderNodes[9], horizontal: true),
    _backspaceKey(node: _ladderNodes[10], horizontal: true),
  ];

  Widget _statusAndRecovery({bool center = false}) => Column(
    crossAxisAlignment: center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 30,
        child: _error == null
            ? null
            : Text(
                _error!,
                key: const Key('profile-pin-error'),
                style: const TextStyle(color: Color(0xFFFF8A97), fontSize: 12),
              ),
      ),
      if (widget.onRecovery != null)
        TextButton(
          onPressed: _busy ? null : _forgotPin,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: .55),
            padding: EdgeInsets.zero,
          ),
          child: const Text('Forgot PIN?'),
        ),
    ],
  );

  Widget _buildPhone() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 66, 28, 24),
    child: Column(
      children: [
        _squircleAvatar(96),
        const SizedBox(height: 22),
        _identity(titleSize: 30, compact: true, centered: true),
        const SizedBox(height: 26),
        _indicators(compact: true, centered: true),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.55,
          children: _gridKeys(),
        ),
        _statusAndRecovery(center: true),
      ],
    ),
  );

  Widget _buildDesktop({required bool compactHeight}) => Padding(
    padding: compactHeight
        ? const EdgeInsets.fromLTRB(52, 16, 34, 16)
        : const EdgeInsets.fromLTRB(64, 56, 64, 42),
    child: Row(
      children: [
        Expanded(
          flex: 11,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _squircleAvatar(compactHeight ? 96 : 148),
                  SizedBox(height: compactHeight ? 18 : 34),
                  _identity(
                    titleSize: compactHeight ? 38 : 54,
                    compact: compactHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compactHeight ? 280 : 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _indicators(compact: false),
                  SizedBox(height: compactHeight ? 12 : 26),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: compactHeight ? 2.2 : 1.4,
                    children: _gridKeys(),
                  ),
                  _statusAndRecovery(),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildTelevision() => Padding(
    padding: const EdgeInsets.fromLTRB(56, 40, 56, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Row(
                children: [
                  _squircleAvatar(128),
                  const SizedBox(width: 34),
                  Flexible(child: _identity(titleSize: 40)),
                ],
              ),
            ),
          ),
        ),
        _indicators(compact: false),
        const SizedBox(height: 14),
        // The wrap listener is a pure ancestor: arrows bubble up from the
        // focused key and are claimed only at the two ends of the ladder.
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _handleLadderKey,
          child: Row(
            children: [
              for (final key in _ladderKeys()) Expanded(child: key),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // One full-width target beneath the keypad means Down reaches Unlock
        // from every number/backspace position. This is substantially easier
        // than traversing to the far-right end of a twelve-button TV row.
        _UnlockBar(
          key: const ValueKey('profile-pin-submit'),
          wash: _wash,
          enabled: _canSubmit,
          busy: _busy,
          onPressed: _submit,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _statusAndRecovery()),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '◀ ▶ move  ·  ▼ unlock  ·  OK press',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .3),
                  fontSize: 11,
                  letterSpacing: .4,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Ghost monogram + the person's colour washing the dark — the identity
/// backdrop behind every layout.
class _MeridianBackdrop extends StatelessWidget {
  const _MeridianBackdrop({
    required this.initial,
    required this.wash,
    required this.phone,
  });

  final String initial;
  final Color wash;
  final bool phone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final monoSize = phone
          ? constraints.maxHeight * .58
          : constraints.maxHeight * .95;
      return Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: phone
                      ? const Alignment(0, -1.1)
                      : const Alignment(-.85, -.55),
                  radius: 1.2,
                  colors: [
                    wash.withValues(alpha: .17),
                    const Color(0xFF07080C),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.05, 1.2),
                  radius: .9,
                  colors: [
                    wash.withValues(alpha: .08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: phone ? -monoSize * .28 : null,
            left: phone ? null : -monoSize * .1,
            top: phone ? -monoSize * .12 : null,
            bottom: phone ? null : -monoSize * .22,
            child: IgnorePointer(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: monoSize,
                  height: .8,
                  fontWeight: FontWeight.w800,
                  color: Color.lerp(
                    wash,
                    Colors.white,
                    .12,
                  )!.withValues(alpha: .07),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _RoundBackButton extends StatelessWidget {
  const _RoundBackButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('profile-pin-cancel'),
    tooltip: 'Back',
    onPressed: onPressed,
    style: IconButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: .05),
      side: BorderSide(color: Colors.white.withValues(alpha: .1)),
    ),
    icon: const Icon(Icons.arrow_back_rounded),
  );
}

/// The one activation contract for every PIN target: Semantics(button) over
/// a Focus that fires on select/enter/space behind the enabled guard, over an
/// opaque tap region. A TV-remote quirk (a new logical key some remote
/// sends) gets fixed here exactly once.
class _PinActivatable extends StatefulWidget {
  const _PinActivatable({
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.semanticLabel,
    required this.onPressed,
    required this.builder,
  });

  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final String? semanticLabel;
  final VoidCallback onPressed;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<_PinActivatable> createState() => _PinActivatableState();
}

class _PinActivatableState extends State<_PinActivatable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: widget.semanticLabel,
    child: Focus(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (_, event) {
        if (!widget.enabled || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onPressed : null,
        child: widget.builder(context, _focused),
      ),
    ),
  );
}

/// A keypad key: a bare thin numeral (or icon) on glass. Focus lights the
/// glyph and draws a small underline bar in the profile's colour; [accent]
/// renders the grid's Unlock key as a filled colour disc instead.
class _PinKey extends StatelessWidget {
  const _PinKey({
    super.key,
    this.label,
    this.icon,
    this.semanticLabel,
    this.autofocus = false,
    this.enabled = true,
    this.busy = false,
    this.accent = false,
    this.focusNode,
    required this.wash,
    required this.onPressed,
    this.horizontal = false,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final bool autofocus;
  final bool enabled;
  final bool busy;
  final bool accent;
  final FocusNode? focusNode;
  final Color wash;
  final VoidCallback onPressed;
  final bool horizontal;

  @override
  Widget build(BuildContext context) => _PinActivatable(
    autofocus: autofocus,
    focusNode: focusNode,
    enabled: enabled,
    semanticLabel: semanticLabel ?? label,
    onPressed: onPressed,
    builder: (context, focused) => SizedBox(
      height: horizontal ? 58 : null,
      child: accent ? _accentBody(focused) : _bareBody(focused),
    ),
  );

  /// The grid's Unlock disc, filled with the profile's colour; dims while
  /// fewer than four digits make it a dead end.
  Widget _accentBody(bool focused) => Center(
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: enabled || busy ? 1 : .4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(wash, Colors.white, .16)!,
              Color.lerp(wash, Colors.black, .28)!,
            ],
          ),
          border: Border.all(
            width: focused ? 2 : 0,
            color: focused ? Colors.white : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: wash.withValues(alpha: focused ? .6 : .35),
              blurRadius: focused ? 26 : 16,
            ),
          ],
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    ),
  );

  Widget _bareBody(bool focused) {
    final glyphColor = Colors.white.withValues(alpha: focused ? 1 : .48);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, color: glyphColor, size: horizontal ? 20 : 22)
        else
          Text(
            label!,
            style: TextStyle(
              color: glyphColor,
              fontSize: horizontal ? 26 : 30,
              fontWeight: focused ? FontWeight.w500 : FontWeight.w300,
              shadows: focused
                  ? [Shadow(color: wash.withValues(alpha: .8), blurRadius: 18)]
                  : const [],
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 120),
          bottom: horizontal ? 6 : 4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: focused ? 26 : 0,
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: Color.lerp(wash, Colors.white, .15),
              boxShadow: [
                BoxShadow(color: wash.withValues(alpha: .8), blurRadius: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The TV's full-width Unlock light bar, sitting beneath the ladder so Down
/// always lands on it. Dims while the entry is too short to submit.
class _UnlockBar extends StatelessWidget {
  const _UnlockBar({
    super.key,
    required this.wash,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final Color wash;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _PinActivatable(
    enabled: enabled,
    semanticLabel: 'Unlock profile',
    onPressed: onPressed,
    builder: (context, focused) => AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: enabled || busy ? 1 : .45,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(wash, Colors.white, .14)!,
              Color.lerp(wash, Colors.black, .3)!,
            ],
          ),
          border: Border.all(
            width: focused ? 2 : 1,
            color: focused ? Colors.white : Colors.white.withValues(alpha: .25),
          ),
          boxShadow: [
            BoxShadow(
              color: wash.withValues(alpha: focused ? .55 : .3),
              blurRadius: focused ? 34 : 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'UNLOCK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
      ),
    ),
  );
}
