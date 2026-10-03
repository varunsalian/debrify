import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'debrid_focus_state.dart';
import 'debrid_selection_state.dart';
import 'debrid_torrent_search_state.dart';

typedef DebridTorrentRowDeps = ({
  DebridSelectionState selectionState,
  DebridFocusState focusState,
  DebridTorrentSearchState torrentSearchState,
  BuildContext Function() context,
  Future<void> Function(RDTorrent torrent) handlePlayMultiFileTorrent,
  Future<void> Function(RDTorrent torrent) handleDownloadTorrent,
  Future<void> Function(RDTorrent torrent) handleAddTorrentToPlaylist,
  Future<void> Function(RDTorrent torrent) handleAddTorrentToDebrifyTv,
  Future<void> Function(RDTorrent torrent) handleDeleteTorrent,
  Future<void> Function(RDTorrent torrent) navigateIntoTorrent,
  void Function(String id) toggleTorrentSelection,
  bool Function() selectSourceMode,
  void Function(SeriesSource)? Function() onSourceSelected,
});

class DebridTorrentRow {
  DebridTorrentRow(this._deps);
  final DebridTorrentRowDeps _deps;

  Widget buildTorrentCard(RDTorrent torrent, int index) {
    final meta =
        '${Formatters.formatFileSize(torrent.bytes)} · ${torrent.links.length} ${torrent.links.length == 1 ? 'file' : 'files'} · ${formatDate(torrent.added)}';
    final upNode = (index == 0)
        ? (_deps.selectionState.isSelectionMode
              ? _deps.focusState.deleteButtonFocusNode
              : (_deps.torrentSearchState.isTorrentSearchActive
                    ? _deps.focusState.torrentSearchFocusNode
                    : null))
        : null;

    if (_deps.selectSourceMode()) {
      // Select-source flow: the row IS the Select action — no strip, no menu.
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: torrent.filename,
        meta: meta,
        onTap: () {
          final source = SeriesSource(
            torrentHash: torrent.hash,
            torrentName: torrent.filename,
            debridService: 'rd',
            debridTorrentId: torrent.id,
            boundAt: DateTime.now().millisecondsSinceEpoch,
          );
          _deps.onSourceSelected()?.call(source);
          Navigator.of(_deps.context()).pop();
        },
        focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
        upFocusNode: upNode,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open.
    final actions = <CloudRowAction>[
      CloudRowAction(
        icon: Icons.play_arrow_rounded,
        label: 'Play',
        showInStrip: true,
        onSelected: () => _deps.handlePlayMultiFileTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _deps.handleDownloadTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onSelected: () => _deps.handleAddTorrentToPlaylist(torrent),
      ),
      CloudRowAction(
        icon: Icons.live_tv_rounded,
        label: 'Add to Debrify TV',
        onSelected: () => _deps.handleAddTorrentToDebrifyTv(torrent),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.handleDeleteTorrent(torrent),
      ),
    ];

    return CloudFileRow(
      kind: CloudRowKind.folder,
      title: torrent.filename,
      meta: meta,
      onTap: () => _deps.navigateIntoTorrent(torrent),
      actions: actions,
      selectionMode: _deps.selectionState.isSelectionMode,
      selected: _deps.selectionState.selectedTorrentIds.contains(torrent.id),
      onToggleSelected: () => _deps.toggleTorrentSelection(torrent.id),
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
      upFocusNode: upNode,
    );
  }

  /// Format date to relative time or absolute date
  String formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }
}
