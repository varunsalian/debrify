import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../utils/platform_util.dart';
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
    // Enter/select are NEVER claimed here: this handler sits on an ancestor
    // of whichever keypad button holds focus, and claiming them is what
    // broke TV entry — DPAD-center submitted an (empty) PIN instead of
    // pressing the focused button. Digits and backspace are safe to handle
    // for physical keyboards because no child wants them.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.close),
        ),
        title: Text(widget.profile.name),
      ),
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
          child: Center(
            // TV logical height is ~540px at the default scale, where the
            // phone's square keypad cells push the submit row off-screen and
            // out of DPAD reach. Short wide cells + a scroll fallback keep
            // every control visible and focusable on any display.
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _tv ? 430 : 380),
                child: Padding(
                  padding: EdgeInsets.all(_tv ? 12 : 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Enter PIN',
                        style: _tv
                            ? Theme.of(context).textTheme.titleMedium
                            : Theme.of(context).textTheme.headlineSmall,
                      ),
                      SizedBox(height: _tv ? 10 : 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List<Widget>.generate(
                          8,
                          (index) => Container(
                            width: _tv ? 10 : 13,
                            height: _tv ? 10 : 13,
                            margin: EdgeInsets.all(_tv ? 4 : 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index < _digits.length
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: _tv ? 30 : 40,
                        child: _error == null
                            ? null
                            : Center(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                      ),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        childAspectRatio: _tv ? 2.4 : 1.0,
                        mainAxisSpacing: _tv ? 8 : 10,
                        crossAxisSpacing: _tv ? 8 : 10,
                        children: <Widget>[
                        for (var digit = 1; digit <= 9; digit++)
                          FilledButton.tonal(
                            autofocus: digit == 1,
                            onPressed: () => _add(digit),
                            child: Text('$digit'),
                          ),
                        IconButton(
                          onPressed: _backspace,
                          icon: const Icon(Icons.backspace),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _add(0),
                          child: const Text('0'),
                        ),
                        IconButton(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : const Icon(Icons.check_rounded),
                        ),
                      ],
                      ),
                      if (widget.onRecovery != null) ...[
                        SizedBox(height: _tv ? 8 : 14),
                        TextButton(
                          onPressed: _busy ? null : _forgotPin,
                          child: const Text('Forgot PIN?'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
