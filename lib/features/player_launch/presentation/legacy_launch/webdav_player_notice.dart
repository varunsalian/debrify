import 'package:flutter/material.dart';

final class WebdavPlayerNotice {
  static Future<bool> showAuthenticatedWebDavPlayerNotice(
    BuildContext context,
  ) async {
    if (!context.mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('External player unavailable'),
            content: const Text(
              'This server requires authentication. Debrify cannot pass '
              'the required authorization headers to another app, so this video '
              'will open in the Debrify player.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Use Debrify player'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
