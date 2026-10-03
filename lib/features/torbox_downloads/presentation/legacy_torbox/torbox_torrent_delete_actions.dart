import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/torbox_torrent_control_service.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_selection_state.dart';

typedef TorboxTorrentDeleteActionsDeps = ({
  TorboxCatalogState catalogState,
  // TEMP(torbox): showComingSoon -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_magnet_actions.dart at step 4.
  void Function(String action) showComingSoon,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  TorboxSelectionState selectionState,
});

class TorboxTorrentDeleteActions {
  TorboxTorrentDeleteActions(this._deps);
  final TorboxTorrentDeleteActionsDeps _deps;

  Future<void> confirmDeleteAll() async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showComingSoon('Add Torbox API key');
      return;
    }

    if (_deps.catalogState.torrents.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Delete all torrents?'),
        content: Text(
          'Are you sure you want to delete all ${_deps.catalogState.torrents.length} cached torrents from Torbox? This action cannot be undone.',
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
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxTorrentControlService.deleteTorrent(
        apiKey: key,
        deleteAll: true,
      );

      if (!_deps.mounted()) return;

      _deps.setState(() {
        _deps.catalogState.torrents.clear();
        _deps.catalogState.hasMore = false;
        _deps.selectionState.selectedTorrentIds.clear();
        _deps.selectionState.isSelectionMode = false;
      });

      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('All Torbox torrents deleted.')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Failed to delete torrents: $e')));
    }
  }

  Future<void> confirmDeleteTorrent(TorboxTorrent torrent) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showComingSoon('Add Torbox API key');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Delete torrent?'),
        content: Text(
          'Are you sure you want to delete "${torrent.name}" from Torbox? This action cannot be undone.',
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
      await TorboxTorrentControlService.deleteTorrent(
        apiKey: key,
        torrentId: torrent.id,
      );

      if (!_deps.mounted()) return;

      _deps.setState(() {
        _deps.catalogState.torrents.removeWhere(
          (item) => item.id == torrent.id,
        );
      });

      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Torrent deleted from Torbox.')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;

      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Failed to delete torrent: $e')));
    }
  }
}
