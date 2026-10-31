// The folder chooser for devices without a system folder picker (most
// Android TV boxes): pick a USB drive or SD card, or go to the network share
// settings instead. Every row is a plain focus stop, so a remote reaches all
// of them with the arrow keys and Select; Back closes the dialog.

import 'package:flutter/material.dart';

import '../models/storage_volume_choice.dart';

/// What the user chose in [showStorageDriveDialog].
sealed class StorageDriveChoice {
  const StorageDriveChoice();
}

/// Record to [volume].
final class StorageDriveSelected extends StorageDriveChoice {
  const StorageDriveSelected(this.volume);
  final StorageVolumeChoice volume;
}

/// Record to a network share instead: the caller opens its settings.
final class StorageDriveNetworkShare extends StorageDriveChoice {
  const StorageDriveNetworkShare();
}

/// Shows the drives in [volumes]; null when the dialog was dismissed.
/// [currentPath] marks the drive recordings already go to.
Future<StorageDriveChoice?> showStorageDriveDialog(
  BuildContext context, {
  required List<StorageVolumeChoice> volumes,
  String? currentPath,
}) {
  return showDialog<StorageDriveChoice>(
    context: context,
    builder: (_) =>
        StorageDriveDialog(volumes: volumes, currentPath: currentPath),
  );
}

class StorageDriveDialog extends StatelessWidget {
  const StorageDriveDialog({
    super.key,
    required this.volumes,
    this.currentPath,
  });

  final List<StorageVolumeChoice> volumes;
  final String? currentPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    return SimpleDialog(
      title: const Text('Save recordings to'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'This TV has no folder picker. Choose a drive below, or record '
            'to a network share.',
          ),
        ),
        const SizedBox(height: 8),
        if (volumes.isEmpty)
          Padding(
            key: const Key('storage-drive-none'),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              'No USB drive or SD card found. Plug one in and open this '
              'again.',
              style: muted,
            ),
          ),
        for (final (index, volume) in volumes.indexed)
          ListTile(
            key: Key('storage-drive-${volume.path}'),
            autofocus: index == 0,
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.usb_rounded),
            title: Text(volume.name),
            subtitle: storageVolumeSpaceText(volume) == null
                ? null
                : Text(storageVolumeSpaceText(volume)!),
            trailing: volume.path == currentPath
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () =>
                Navigator.of(context).pop(StorageDriveSelected(volume)),
          ),
        ListTile(
          key: const Key('storage-drive-network-share'),
          autofocus: volumes.isEmpty,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.lan_outlined),
          title: const Text('Use a network share instead'),
          onTap: () =>
              Navigator.of(context).pop(const StorageDriveNetworkShare()),
        ),
        if (volumes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              'Recordings on a drive go in a Debrify folder there. Android '
              'deletes that folder if Debrify is uninstalled.',
              style: muted,
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextButton(
              key: const Key('storage-drive-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ),
      ],
    );
  }
}
