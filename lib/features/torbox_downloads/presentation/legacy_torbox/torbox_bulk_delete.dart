import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/torbox_torrent_control_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_web_state.dart';

typedef TorboxBulkDeleteDeps = ({
  BuildContext Function() context,
  TorboxCatalogState catalogState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  TorboxWebState webState,
  TorboxSelectionState selectionState,
  // TEMP(torbox): showSnackBar -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart at step 4.
  void Function(String message, {bool isError}) showSnackBar,
});

class TorboxBulkDelete {
  TorboxBulkDelete(this._deps);
  final TorboxBulkDeleteDeps _deps;

  Future<void> showDeleteSelectedProgressDialog(
    Set<int> ids,
    bool isTorrents,
  ) async {
    bool isCancelled = false;
    bool dialogOpen = true;
    int completed = 0;
    final int total = ids.length;
    List<int> failedDeletes = [];
    StateSetter? setDialogState;
    final nav = Navigator.of(_deps.context());
    final app = AppThemeScope.of(_deps.context());

    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, dialogStateSetter) {
          setDialogState = dialogStateSetter;
          return AlertDialog(
            backgroundColor: app.cloud.dialogSurface,
            shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
            title: Text(
              'Deleting ${isTorrents ? 'Torrents' : 'Web Downloads'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Deleting... ($completed/$total)',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: total > 0 ? completed / total : null,
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 16),
                if (failedDeletes.isNotEmpty)
                  Text(
                    'Failed: ${failedDeletes.length}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCancelled = true;
                  dialogOpen = false;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    final deletedIds = <int>{};

    for (final id in ids) {
      if (isCancelled) break;

      try {
        if (isTorrents) {
          await TorboxTorrentControlService.deleteTorrent(
            apiKey: _deps.catalogState.apiKey!,
            torrentId: id,
          );
        } else {
          await TorboxService.deleteWebDownload(
            apiKey: _deps.catalogState.apiKey!,
            webId: id,
          );
        }
        deletedIds.add(id);
      } catch (e) {
        failedDeletes.add(id);
      }

      completed++;
      if (!isCancelled && setDialogState != null) {
        setDialogState!(() {});
      }

      if (isCancelled) break;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // Close progress dialog if still open
    if (dialogOpen && _deps.mounted()) {
      dialogOpen = false;
      nav.pop();
    }

    if (!isCancelled && _deps.mounted()) {
      _deps.setState(() {
        if (isTorrents) {
          _deps.catalogState.torrents.removeWhere(
            (t) => deletedIds.contains(t.id),
          );
        } else {
          _deps.webState.webDownloads.removeWhere(
            (d) => deletedIds.contains(d.id),
          );
        }
        _deps.selectionState.selectedTorrentIds.clear();
        _deps.selectionState.selectedWebDownloadIds.clear();
        _deps.selectionState.isSelectionMode = false;
      });

      final label = isTorrents ? 'torrents' : 'web downloads';
      if (failedDeletes.isEmpty) {
        _deps.showSnackBar(
          '${deletedIds.length} $label deleted successfully!',
          isError: false,
        );
      } else {
        _deps.showSnackBar(
          'Deleted ${deletedIds.length}. ${failedDeletes.length} failed to delete.',
        );
      }
    } else if (_deps.mounted()) {
      // Cancelled — remove already-deleted items and deselect them, but stay in selection mode
      _deps.setState(() {
        if (isTorrents) {
          _deps.catalogState.torrents.removeWhere(
            (t) => deletedIds.contains(t.id),
          );
          _deps.selectionState.selectedTorrentIds.removeAll(deletedIds);
        } else {
          _deps.webState.webDownloads.removeWhere(
            (d) => deletedIds.contains(d.id),
          );
          _deps.selectionState.selectedWebDownloadIds.removeAll(deletedIds);
        }
      });
    }
  }
}
