import 'package:flutter/material.dart';

class LinuxVaultScreen extends StatefulWidget {
  final bool existingVault;
  final bool allowAutoUnlock;
  final Future<void> Function(String passphrase, bool autoUnlock) onSubmit;

  const LinuxVaultScreen({
    super.key,
    required this.existingVault,
    this.allowAutoUnlock = true,
    required this.onSubmit,
  });

  @override
  State<LinuxVaultScreen> createState() => _LinuxVaultScreenState();
}

class _LinuxVaultScreenState extends State<LinuxVaultScreen> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _autoUnlock = true;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _passphrase.text;
    if (value.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (!widget.existingVault && value != _confirmation.text) {
      setState(() => _error = 'The passphrases do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(value, widget.allowAutoUnlock && _autoUnlock);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = widget.existingVault
            ? 'Could not unlock the vault. Check the passphrase.'
            : 'Could not create the encrypted vault.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 48),
                  const SizedBox(height: 20),
                  Text(
                    widget.existingVault
                        ? 'Unlock profiles'
                        : 'Protect profiles',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.existingVault
                        ? 'Enter your existing passphrase once to open your saved connections. Automatic unlock skips this step on future launches.'
                        : 'Choose a passphrase to require on each launch. It cannot be recovered if lost.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passphrase,
                    obscureText: _obscure,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => widget.existingVault ? _submit() : null,
                    decoration: InputDecoration(
                      labelText: 'Vault passphrase',
                      suffixIcon: IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (!widget.existingVault) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmation,
                      obscureText: _obscure,
                      enabled: !_busy,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                      ),
                    ),
                  ],
                  if (widget.allowAutoUnlock)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Unlock automatically on this device'),
                      subtitle: const Text(
                        'Stores access to the vault on this device. Your passphrase will no longer protect it.',
                      ),
                      value: _autoUnlock,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _autoUnlock = value ?? true),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.existingVault ? 'Unlock' : 'Set passphrase',
                          ),
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
