import 'package:flutter/material.dart';

/// Confirms the existing local-history action. Deletion remains caller-owned.
/// The dialog may outlive its originating view or profile session.
Future<bool> confirmHomeUnavailableOriginRemoval({
  required BuildContext context,
  required String title,
  required bool Function() canRemove,
  required bool Function() isCurrent,
}) async {
  if (!context.mounted || !isCurrent()) return false;
  final remove = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: const Text(
        'The addon configuration for this series is unavailable. Your local history is still saved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Close'),
        ),
        if (canRemove())
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove from Continue Watching'),
          ),
      ],
    ),
  );
  return context.mounted && isCurrent() && remove == true;
}
