import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';

typedef DebridTorrentBulkDeleteDeps = ({
  BuildContext Function() context,
  DebridCatalogState catalogState,
  bool Function() mounted,
  Future<void> Function(String apiKey, {bool reset}) fetchTorrents,
  void Function(VoidCallback) setState,
  void Function(String message) showSuccess,
  void Function(String message) showError,
});

class DebridTorrentBulkDelete {
  DebridTorrentBulkDelete(this._deps);
  final DebridTorrentBulkDeleteDeps _deps;

  Future<void> showDeleteAllProgressDialog() async {
    bool isCancelled = false;
    int completed = 0;
    int total = 0;
    String phase = 'Fetching all torrents...';
    List<String> failedDeletes = [];
    StateSetter? setDialogState;
    final app = AppThemeScope.of(_deps.context());

    // Show progress dialog
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogStateSetter) {
          setDialogState = dialogStateSetter;
          return AlertDialog(
            backgroundColor: app.cloud.dialogSurface,
            shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
            title: const Text(
              'Deleting All Torrents',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  total == 0
                      ? phase
                      : 'Deleting torrents... ($completed/$total)',
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
                  Navigator.of(context).pop();
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

    // Fetch ALL torrents first (1000 per page for speed)
    List<RDTorrent> allTorrents = [];
    try {
      int page = 1;
      bool hasMore = true;

      while (hasMore && !isCancelled) {
        final result = await DebridService.getTorrents(
          _deps.catalogState.apiKey!,
          page: page,
          limit: 1000,
        );
        final torrents = result['torrents'] as List<RDTorrent>;
        allTorrents.addAll(torrents);
        hasMore = result['hasMore'] as bool;
        page++;

        // Update phase text
        if (setDialogState != null && !isCancelled) {
          phase = 'Fetching torrents... (${allTorrents.length} found)';
          setDialogState!(() {});
        }
      }

      if (isCancelled) {
        if (_deps.mounted()) {
          await _deps.fetchTorrents(_deps.catalogState.apiKey!, reset: true);
        }
        return;
      }

      total = allTorrents.length;
      if (setDialogState != null) setDialogState!(() {});

      // Now delete all torrents
      for (int i = 0; i < allTorrents.length && !isCancelled; i++) {
        final torrent = allTorrents[i];

        try {
          await DebridService.deleteTorrent(
            _deps.catalogState.apiKey!,
            torrent.id,
          );
          completed++;

          // Update dialog state only if not cancelled
          if (!isCancelled && setDialogState != null) {
            setDialogState!(() {});
          }

          // Small delay to prevent overwhelming the API
          await Future.delayed(const Duration(milliseconds: 150));
        } catch (e) {
          failedDeletes.add(torrent.filename);
          completed++;

          // Update dialog state only if not cancelled
          if (!isCancelled && setDialogState != null) {
            setDialogState!(() {});
          }
        }
      }

      // Close progress dialog only if not already cancelled
      if (_deps.mounted() && !isCancelled) {
        Navigator.of(_deps.context()).pop();
      }

      if (!isCancelled) {
        // Update the torrents list
        if (_deps.mounted()) {
          _deps.setState(() {
            _deps.catalogState.torrents.clear();
          });
        }

        // Refresh the list
        if (_deps.mounted()) {
          await _deps.fetchTorrents(_deps.catalogState.apiKey!, reset: true);
        }

        // Show result message
        if (failedDeletes.isEmpty) {
          _deps.showSuccess('All $total torrents deleted successfully!');
        } else {
          _deps.showError(
            'Deleted ${completed - failedDeletes.length} torrents. ${failedDeletes.length} failed to delete.',
          );
        }
      } else {
        // Operation was cancelled, refresh the list to show current state
        if (_deps.mounted()) {
          await _deps.fetchTorrents(_deps.catalogState.apiKey!, reset: true);
        }
      }
    } catch (e) {
      // Close progress dialog
      if (_deps.mounted()) {
        Navigator.of(_deps.context()).pop();
        _deps.showError('Failed to delete torrents: ${e.toString()}');
      }
    }
  }
}
