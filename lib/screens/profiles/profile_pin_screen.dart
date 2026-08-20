import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../../widgets/tv_text_field.dart';

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

  bool get _tv => PlatformUtil.isTelevision;

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    const ground = Color(0xFF070708);
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
                    child: _EditorialBackdrop(
                      profile: widget.profile,
                      phone: phone,
                      television: _tv,
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

  Widget _identity({required double titleSize, bool compact = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'PROFILE ACCESS',
        style: TextStyle(
          color: Color(0xFFED3E53),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.1,
        ),
      ),
      SizedBox(height: compact ? 10 : 16),
      Text(
        'Welcome back,',
        key: const Key('profile-pin-title'),
        style: TextStyle(
          color: const Color(0xFFF4F0E8),
          fontSize: titleSize,
          height: .93,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '${widget.profile.name}.',
          key: const Key('profile-pin-name'),
          maxLines: 1,
          style: TextStyle(
            color: const Color(0xFFED3E53),
            fontSize: titleSize,
            height: .93,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
        ),
      ),
      SizedBox(height: compact ? 10 : 16),
      Text(
        'Your watchlist is waiting.',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .62),
          fontSize: compact ? 12 : 15,
        ),
      ),
    ],
  );

  Widget _indicators({required bool compact}) => Row(
    key: const Key('profile-pin-indicators'),
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      8,
      (index) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: compact ? 10 : 12,
        height: compact ? 10 : 12,
        margin: EdgeInsets.only(right: compact ? 14 : 17),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: index < _digits.length
              ? const Color(0xFFED3E53)
              : Colors.transparent,
          border: Border.all(
            color: index < _digits.length
                ? const Color(0xFFED3E53)
                : Colors.white.withValues(alpha: .58),
          ),
        ),
      ),
    ),
  );

  Widget _submitKey({required bool horizontal}) => _PinKey(
    key: const ValueKey('profile-pin-submit'),
    icon: Icons.check_rounded,
    semanticLabel: 'Unlock profile',
    enabled: !_busy,
    busy: _busy,
    onPressed: _submit,
    horizontal: horizontal,
  );

  List<Widget> _keys({required bool horizontal, bool includeSubmit = true}) => [
    for (var digit = 1; digit <= 9; digit++)
      _PinKey(
        key: ValueKey('profile-pin-key-$digit'),
        label: '$digit',
        autofocus: digit == 1,
        onPressed: () => _add(digit),
        horizontal: horizontal,
      ),
    _PinKey(
      key: const ValueKey('profile-pin-backspace'),
      icon: Icons.backspace_outlined,
      semanticLabel: 'Backspace',
      onPressed: _backspace,
      horizontal: horizontal,
    ),
    _PinKey(
      key: const ValueKey('profile-pin-key-0'),
      label: '0',
      onPressed: () => _add(0),
      horizontal: horizontal,
    ),
    if (includeSubmit) _submitKey(horizontal: horizontal),
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
                style: const TextStyle(color: Color(0xFFFF7887), fontSize: 12),
              ),
      ),
      if (widget.onRecovery != null)
        TextButton(
          onPressed: _busy ? null : _forgotPin,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: .62),
            padding: EdgeInsets.zero,
          ),
          child: const Text('Forgot PIN?'),
        ),
    ],
  );

  Widget _buildPhone() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 102, 28, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _identity(titleSize: 43, compact: true),
        const SizedBox(height: 30),
        _indicators(compact: true),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.55,
          children: _keys(horizontal: false),
        ),
        _statusAndRecovery(center: true),
      ],
    ),
  );

  Widget _buildDesktop({required bool compactHeight}) => Padding(
    padding: compactHeight
        ? const EdgeInsets.fromLTRB(52, 16, 34, 16)
        : const EdgeInsets.fromLTRB(64, 64, 64, 42),
    child: Row(
      children: [
        Expanded(
          flex: 11,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: _identity(
                titleSize: compactHeight ? 42 : 58,
                compact: compactHeight,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compactHeight ? 280 : 390),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _indicators(compact: false),
                  SizedBox(height: compactHeight ? 12 : 24),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: compactHeight ? 2.2 : 1.55,
                    children: _keys(horizontal: false),
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
    padding: const EdgeInsets.fromLTRB(56, 44, 56, 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _identity(titleSize: 58),
            ),
          ),
        ),
        _indicators(compact: false),
        const SizedBox(height: 18),
        Row(
          children: [
            for (final key in _keys(horizontal: true, includeSubmit: false))
              Expanded(child: key),
          ],
        ),
        const SizedBox(height: 6),
        // One full-width target beneath the keypad means Down reaches Submit
        // from every number/backspace position. This is substantially easier
        // than traversing to the far-right end of a twelve-button TV row.
        SizedBox(width: double.infinity, child: _submitKey(horizontal: true)),
        _statusAndRecovery(),
      ],
    ),
  );
}

class _EditorialBackdrop extends StatelessWidget {
  const _EditorialBackdrop({
    required this.profile,
    required this.phone,
    required this.television,
  });

  final UserProfile profile;
  final bool phone;
  final bool television;

  @override
  Widget build(BuildContext context) {
    final wash = ProfileAvatarView.washColor(profile.avatarKey, profile.role);
    final size = phone
        ? 270.0
        : television
        ? 520.0
        : 620.0;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: phone
                    ? const Alignment(1.15, -1.15)
                    : television
                    ? const Alignment(1.05, -.15)
                    : const Alignment(-1.05, 0),
                radius: 1.15,
                colors: [wash.withValues(alpha: .18), const Color(0xFF070708)],
              ),
            ),
          ),
        ),
        Positioned(
          right: phone
              ? -95
              : television
              ? -120
              : null,
          left: !phone && !television ? -250 : null,
          top: phone
              ? -150
              : television
              ? -80
              : -90,
          child: IgnorePointer(
            child: Opacity(
              opacity: .58,
              child: Container(
                width: size,
                height: size,
                padding: EdgeInsets.all(size * .08),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFED3E53).withValues(alpha: .12),
                  border: Border.all(
                    color: const Color(0xFFED3E53).withValues(alpha: .25),
                  ),
                ),
                child: ClipOval(
                  child: ProfileAvatarView(
                    profileId: profile.id,
                    avatarKey: profile.avatarKey,
                    role: profile.role,
                    name: profile.name,
                    animateWhenIdle: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
      backgroundColor: Colors.black.withValues(alpha: .28),
    ),
    icon: const Icon(Icons.arrow_back_rounded),
  );
}

class _PinKey extends StatefulWidget {
  const _PinKey({
    super.key,
    this.label,
    this.icon,
    this.semanticLabel,
    this.autofocus = false,
    this.enabled = true,
    this.busy = false,
    required this.onPressed,
    required this.horizontal,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final bool autofocus;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;
  final bool horizontal;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: widget.semanticLabel ?? widget.label,
    child: Focus(
      autofocus: widget.autofocus,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.horizontal ? 58 : null,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withValues(alpha: .09)
                : Colors.transparent,
            border: Border.all(
              width: _focused ? 2 : 1,
              color: _focused
                  ? Colors.white
                  : Colors.white.withValues(alpha: .15),
            ),
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : widget.icon != null
              ? Icon(widget.icon, color: const Color(0xFFF4F0E8), size: 21)
              : Text(
                  widget.label!,
                  style: const TextStyle(
                    color: Color(0xFFF4F0E8),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    ),
  );
}
