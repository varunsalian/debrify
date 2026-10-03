import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';
import 'debrid_selection_state.dart';

typedef DebridSelectionActionsDeps = ({
  DebridCatalogState catalogState,
  DebridSelectionState selectionState,
  DebridDownloadState downloadState,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function(Set<String> ids, bool isTorrents)
  showDeleteSelectedProgressDialog,
});

// --- Multi-select helpers ---
class DebridSelectionActions {
  DebridSelectionActions(this._deps);
  final DebridSelectionActionsDeps _deps;

  Set<String> get activeSelectedIds =>
      _deps.catalogState.selectedView == DebridDownloadsView.torrents
      ? _deps.selectionState.selectedTorrentIds
      : _deps.selectionState.selectedDownloadIds;

  int get activeItemCount =>
      _deps.catalogState.selectedView == DebridDownloadsView.torrents
      ? _deps.catalogState.torrents.length
      : _deps.downloadState.downloads.length;

  bool get isAllSelected =>
      activeSelectedIds.length == activeItemCount && activeItemCount > 0;

  void toggleSelectionMode() {
    _deps.setState(() {
      if (_deps.selectionState.isSelectionMode) {
        _deps.selectionState.selectedTorrentIds.clear();
        _deps.selectionState.selectedDownloadIds.clear();
      }
      _deps.selectionState.isSelectionMode =
          !_deps.selectionState.isSelectionMode;
    });
  }

  void exitSelectionMode() {
    if (!_deps.selectionState.isSelectionMode) return;
    _deps.setState(() {
      _deps.selectionState.isSelectionMode = false;
      _deps.selectionState.selectedTorrentIds.clear();
      _deps.selectionState.selectedDownloadIds.clear();
    });
  }

  void toggleTorrentSelection(String id) {
    _deps.setState(() {
      if (_deps.selectionState.selectedTorrentIds.contains(id)) {
        _deps.selectionState.selectedTorrentIds.remove(id);
      } else {
        _deps.selectionState.selectedTorrentIds.add(id);
      }
    });
  }

  void toggleDownloadSelection(String id) {
    _deps.setState(() {
      if (_deps.selectionState.selectedDownloadIds.contains(id)) {
        _deps.selectionState.selectedDownloadIds.remove(id);
      } else {
        _deps.selectionState.selectedDownloadIds.add(id);
      }
    });
  }

  void toggleSelectAll() {
    _deps.setState(() {
      if (isAllSelected) {
        activeSelectedIds.clear();
      } else {
        if (_deps.catalogState.selectedView == DebridDownloadsView.torrents) {
          _deps.selectionState.selectedTorrentIds.addAll(
            _deps.catalogState.torrents.map((t) => t.id),
          );
        } else {
          _deps.selectionState.selectedDownloadIds.addAll(
            _deps.downloadState.downloads.map((d) => d.id),
          );
        }
      }
    });
  }

  Future<void> handleDeleteSelected() async {
    if (_deps.catalogState.apiKey == null || activeSelectedIds.isEmpty) return;

    final isTorrents =
        _deps.catalogState.selectedView == DebridDownloadsView.torrents;
    final count = activeSelectedIds.length;
    final itemType = isTorrents ? 'torrent' : 'download';
    final itemTypePlural = isTorrents ? 'torrents' : 'downloads';

    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete $count ${count == 1 ? itemType : itemTypePlural}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete $count selected ${count == 1 ? itemType : itemTypePlural}? This action cannot be undone.',
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
      await _deps.showDeleteSelectedProgressDialog(
        Set<String>.from(activeSelectedIds),
        isTorrents,
      );
    }
  }
}
