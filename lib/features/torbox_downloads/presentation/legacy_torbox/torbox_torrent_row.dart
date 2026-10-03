import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'torbox_focus_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_torrent_search_state.dart';

typedef TorboxTorrentRowDeps = ({
  TorboxTorrentSearchState torrentSearchState,
  TorboxFocusState focusState,
  BuildContext Function() context,
  Future<void> Function(TorboxTorrent torrent) handlePlayTorrent,
  void Function(TorboxTorrent torrent) showDownloadOptionsDialog,
  void Function(TorboxTorrent torrent) navigateIntoTorrent,
  void Function(TorboxTorrent torrent) copyTorboxZipLink,
  Future<void> Function(TorboxTorrent torrent) handleAddToPlaylist,
  Future<void> Function(TorboxTorrent torrent) handleAddToDebrifyTv,
  Future<void> Function(TorboxTorrent torrent) confirmDeleteTorrent,
  TorboxSelectionState selectionState,
  void Function(int id) toggleTorrentSelection,
  bool Function() selectSourceMode,
  void Function(SeriesSource)? Function() onSourceSelected,
});

class TorboxTorrentRow {
  TorboxTorrentRow(this._deps);
  final TorboxTorrentRowDeps _deps;

  /// Build a card for a torrent (displayed as a folder at root level)
  Widget buildTorrentFolderCard(TorboxTorrent torrent, int index) {
    final videoCount = torrent.files.where(torboxFileLooksLikeVideo).length;
    final meta =
        '${Formatters.formatFileSize(torrent.size)} · ${torrent.files.length} files';
    final upNode =
        (index == 0 && _deps.torrentSearchState.isTorrentSearchActive)
        ? _deps.focusState.torrentSearchFocusNode
        : null;

    if (_deps.selectSourceMode()) {
      // Select-source flow: the row IS the Select action — no strip, no menu.
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: torrent.name,
        meta: meta,
        onTap: () {
          final source = SeriesSource(
            torrentHash: torrent.hash,
            torrentName: torrent.name,
            debridService: 'torbox',
            debridTorrentId: torrent.id.toString(),
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
      if (videoCount > 0)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _deps.handlePlayTorrent(torrent),
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download to device',
        showInStrip: true,
        onSelected: () => _deps.showDownloadOptionsDialog(torrent),
      ),
      CloudRowAction(
        icon: Icons.folder_open,
        label: 'Open',
        onSelected: () => _deps.navigateIntoTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy Download Link (Zip)',
        onSelected: () => _deps.copyTorboxZipLink(torrent),
      ),
      if (videoCount > 0)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _deps.handleAddToPlaylist(torrent),
        ),
      CloudRowAction(
        icon: Icons.live_tv_rounded,
        label: 'Add to Debrify TV',
        onSelected: () => _deps.handleAddToDebrifyTv(torrent),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.confirmDeleteTorrent(torrent),
      ),
    ];

    return CloudFileRow(
      kind: CloudRowKind.folder,
      title: torrent.name,
      meta: meta,
      badges: [
        if (torrent.cached)
          const CloudRowBadge('✓ Cached', CloudBadgeKind.ok)
        else if (!torrent.downloadFinished)
          CloudRowBadge(
            '${(torrent.progress * 100).clamp(0, 100).round()}%',
            CloudBadgeKind.warn,
          ),
      ],
      onTap: () => _deps.navigateIntoTorrent(torrent),
      actions: actions,
      selectionMode: _deps.selectionState.isSelectionMode,
      selected: _deps.selectionState.selectedTorrentIds.contains(torrent.id),
      onToggleSelected: () => _deps.toggleTorrentSelection(torrent.id),
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
      upFocusNode: upNode,
    );
  }
}
