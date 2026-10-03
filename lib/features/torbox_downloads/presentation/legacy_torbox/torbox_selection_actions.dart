import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_web_state.dart';

typedef TorboxSelectionActionsDeps = ({
  TorboxCatalogState catalogState,
  TorboxSelectionState selectionState,
  TorboxWebState webState,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function(Set<int> ids, bool isTorrents)
  showDeleteSelectedProgressDialog,
});

class TorboxSelectionActions {
  TorboxSelectionActions(this._deps);
  final TorboxSelectionActionsDeps _deps;

  Set<int> get activeSelectedIds =>
      _deps.catalogState.selectedView == TorboxDownloadsView.torrents
      ? _deps.selectionState.selectedTorrentIds
      : _deps.selectionState.selectedWebDownloadIds;

  int get activeItemCount =>
      _deps.catalogState.selectedView == TorboxDownloadsView.torrents
      ? _deps.catalogState.torrents.length
      : _deps.webState.webDownloads.length;

  bool get isAllSelected =>
      activeSelectedIds.length == activeItemCount && activeItemCount > 0;

  void toggleSelectionMode() {
    _deps.setState(() {
      if (_deps.selectionState.isSelectionMode) {
        _deps.selectionState.selectedTorrentIds.clear();
        _deps.selectionState.selectedWebDownloadIds.clear();
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
      _deps.selectionState.selectedWebDownloadIds.clear();
    });
  }

  void toggleTorrentSelection(int id) {
    _deps.setState(() {
      if (_deps.selectionState.selectedTorrentIds.contains(id)) {
        _deps.selectionState.selectedTorrentIds.remove(id);
      } else {
        _deps.selectionState.selectedTorrentIds.add(id);
      }
    });
  }

  void toggleWebDownloadSelection(int id) {
    _deps.setState(() {
      if (_deps.selectionState.selectedWebDownloadIds.contains(id)) {
        _deps.selectionState.selectedWebDownloadIds.remove(id);
      } else {
        _deps.selectionState.selectedWebDownloadIds.add(id);
      }
    });
  }

  void toggleSelectAll() {
    _deps.setState(() {
      if (isAllSelected) {
        activeSelectedIds.clear();
      } else {
        if (_deps.catalogState.selectedView == TorboxDownloadsView.torrents) {
          _deps.selectionState.selectedTorrentIds.addAll(
            _deps.catalogState.torrents.map((t) => t.id),
          );
        } else {
          _deps.selectionState.selectedWebDownloadIds.addAll(
            _deps.webState.webDownloads.map((d) => d.id),
          );
        }
      }
    });
  }

  Future<void> handleDeleteSelected() async {
    if (_deps.catalogState.apiKey == null || activeSelectedIds.isEmpty) return;

    final isTorrents =
        _deps.catalogState.selectedView == TorboxDownloadsView.torrents;
    final count = activeSelectedIds.length;
    final itemType = isTorrents ? 'torrent' : 'web download';
    final itemTypePlural = isTorrents ? 'torrents' : 'web downloads';

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
        Set<int>.from(activeSelectedIds),
        isTorrents,
      );
    }
  }
}
