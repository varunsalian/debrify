import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';

typedef DebridSingleDeleteActionsDeps = ({
  DebridCatalogState catalogState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  void Function(String message) showSuccess,
  void Function(String message) showError,
  DebridDownloadState downloadState,
});

class DebridSingleDeleteActions {
  DebridSingleDeleteActions(this._deps);
  final DebridSingleDeleteActionsDeps _deps;

  Future<void> handleDeleteTorrent(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Torrent',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${torrent.filename}" from Real Debrid? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _deps.mounted()) {
      try {
        // Show loading indicator
        showDialog(
          context: _deps.context(),
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
            content: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Deleting torrent...'),
              ],
            ),
          ),
        );

        // Delete the torrent
        await DebridService.deleteTorrent(
          _deps.catalogState.apiKey!,
          torrent.id,
        );

        // Check if widget is still mounted before updating UI
        if (_deps.mounted()) {
          // Close loading dialog
          Navigator.of(_deps.context()).pop();

          // Remove the torrent from the local list
          _deps.setState(() {
            _deps.catalogState.torrents.removeWhere((t) => t.id == torrent.id);
          });

          // Show success message
          _deps.showSuccess('Torrent deleted successfully!');
        }
      } catch (e) {
        // Check if widget is still mounted before updating UI
        if (_deps.mounted()) {
          // Close loading dialog
          Navigator.of(_deps.context()).pop();

          // Show error message
          _deps.showError('Failed to delete torrent: ${e.toString()}');
        }
      }
    }
  }

  Future<void> handleDeleteDownload(DebridDownload download) async {
    if (_deps.catalogState.apiKey == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Download',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${download.filename}" from Real Debrid? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _deps.mounted()) {
      try {
        // Show loading indicator
        showDialog(
          context: _deps.context(),
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
            content: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Deleting download...'),
              ],
            ),
          ),
        );

        // Delete the download
        await DebridService.deleteDownload(
          _deps.catalogState.apiKey!,
          download.id,
        );

        // Check if widget is still mounted before updating UI
        if (_deps.mounted()) {
          // Close loading dialog
          Navigator.of(_deps.context()).pop();

          // Remove the download from the local list
          _deps.setState(() {
            _deps.downloadState.downloads.removeWhere(
              (d) => d.id == download.id,
            );
          });

          // Show success message
          _deps.showSuccess('Download deleted successfully!');
        }
      } catch (e) {
        // Check if widget is still mounted before updating UI
        if (_deps.mounted()) {
          // Close loading dialog
          Navigator.of(_deps.context()).pop();

          // Show error message
          _deps.showError('Failed to delete download: ${e.toString()}');
        }
      }
    }
  }
}
