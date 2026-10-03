import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';

typedef DebridDeleteAllActionsDeps = ({
  DebridCatalogState catalogState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function() showDeleteAllProgressDialog,
  DebridDownloadState downloadState,
  Future<void> Function() showDeleteAllDownloadsProgressDialog,
});

class DebridDeleteAllActions {
  DebridDeleteAllActions(this._deps);
  final DebridDeleteAllActionsDeps _deps;

  Future<void> handleDeleteAllTorrents() async {
    if (_deps.catalogState.apiKey == null ||
        _deps.catalogState.torrents.isEmpty) {
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete All Torrents',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete all torrents from Real Debrid? This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && _deps.mounted()) {
      await _deps.showDeleteAllProgressDialog();
    }
  }

  Future<void> handleDeleteAllDownloads() async {
    if (_deps.catalogState.apiKey == null ||
        _deps.downloadState.downloads.isEmpty) {
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete All Downloads',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete all downloads from Real Debrid? This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && _deps.mounted()) {
      await _deps.showDeleteAllDownloadsProgressDialog();
    }
  }
}
