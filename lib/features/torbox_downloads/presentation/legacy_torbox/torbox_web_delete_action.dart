import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_web_state.dart';

typedef TorboxWebDeleteActionDeps = ({
  TorboxCatalogState catalogState,
  // TEMP(torbox): showSnackBar -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart at step 4.
  void Function(String message, {bool isError}) showSnackBar,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  TorboxWebState webState,
});

class TorboxWebDeleteAction {
  TorboxWebDeleteAction(this._deps);
  final TorboxWebDeleteActionDeps _deps;

  Future<void> confirmDeleteWebDownload(TorboxWebDownload webDownload) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showSnackBar('Torbox API key not configured');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Delete web download?'),
        content: Text(
          'Are you sure you want to delete "${webDownload.name}" from Torbox? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxService.deleteWebDownload(apiKey: key, webId: webDownload.id);

      if (!_deps.mounted()) return;

      _deps.setState(() {
        _deps.webState.webDownloads.removeWhere(
          (item) => item.id == webDownload.id,
        );
      });

      _deps.showSnackBar('Web download deleted from Torbox.', isError: false);
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar(
        'Failed to delete web download: ${formatTorboxError(e)}',
      );
    }
  }
}
