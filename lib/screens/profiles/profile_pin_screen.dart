import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_pin_service.dart';

class ProfilePinScreen extends StatefulWidget {
  final UserProfile profile;
  final Future<ProfilePinVerification> Function(String pin) onSubmit;
  final VoidCallback onCancel;

  const ProfilePinScreen({
    super.key,
    required this.profile,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<ProfilePinScreen> createState() => _ProfilePinScreenState();
}

class _ProfilePinScreenState extends State<ProfilePinScreen> {
  final List<int> _digits = <int>[];
  bool _busy = false;
  String? _error;

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
    final result = await widget.onSubmit(pin);
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
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
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
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleHardwareKey,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Enter PIN',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List<Widget>.generate(
                        8,
                        (index) => Container(
                          width: 13,
                          height: 13,
                          margin: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index < _digits.length
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 40,
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
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
