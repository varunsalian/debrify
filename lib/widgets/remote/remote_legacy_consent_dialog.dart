import 'package:flutter/material.dart';

/// The v1 (plaintext) consent question. Moved out of `RemoteCommandRouter`
/// unchanged: the peer address sits in the warning body, `Deny` is the
/// emphasised action and holds first focus so a TV remote's OK button on an
/// unattended set refuses the transfer.
class RemoteLegacyConsentDialog extends StatelessWidget {
  const RemoteLegacyConsentDialog({super.key, required this.peer});

  final String peer;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Incoming settings'),
      content: Text(
        'The device at $peer wants to send settings and account '
        'credentials to this TV over an UNENCRYPTED connection (its app '
        'version predates encryption).\n\nOnly allow this if it is your '
        'own phone and you started the transfer yourself.',
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Deny'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}
