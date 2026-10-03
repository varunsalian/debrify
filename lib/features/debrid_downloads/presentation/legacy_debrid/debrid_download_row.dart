import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'debrid_focus_state.dart';
import 'debrid_selection_state.dart';

typedef DebridDownloadRowDeps = ({
  BuildContext Function() context,
  DebridFocusState focusState,
  Future<void> Function(DebridDownload download) handlePlayDownload,
  Future<void> Function(DebridDownload download) handleQueueDownload,
  Future<void> Function(DebridDownload download) handleDownloadAction,
  Future<void> Function(DebridDownload download) handleDeleteDownload,
  DebridSelectionState selectionState,
  void Function(String id) toggleDownloadSelection,
  bool Function() selectSourceMode,
  void Function(SeriesSource)? Function() onSourceSelected,
});

class DebridDownloadRow {
  DebridDownloadRow(this._deps);
  final DebridDownloadRowDeps _deps;

  Widget buildDownloadCard(DebridDownload download, int index) {
    final canStream = download.streamable == 1;
    final isVideo = FileUtils.isVideoFile(download.filename);

    if (_deps.selectSourceMode()) {
      final selectable = canStream || isVideo;
      return CloudFileRow(
        kind: selectable ? CloudRowKind.video : CloudRowKind.file,
        title: download.filename,
        meta:
            '${Formatters.formatFileSize(download.filesize)} · ${download.host}',
        onTap: selectable
            ? () {
                _deps.onSourceSelected()?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: download.filename,
                    debridService: 'rd',
                    debridTorrentId: download.id,
                    cloudSourceKind: SeriesSource.cloudKindWebDownload,
                    boundAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                Navigator.of(_deps.context()).pop();
              }
            : null,
        focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
      );
    }

    // Same action set the old Play/Download buttons + ⋮ menu offered; the
    // row's tap now carries Play for streamable downloads.
    // Play is offered for anything WE can stream, not only what the provider
    // flags. `streamable` describes the provider's own transcoding service;
    // we hand the direct link to our player instead, which reads plenty the
    // provider won't transcode (MPEG program streams, for one). Non-video
    // files are unaffected — they still offer download only.
    final actions = <CloudRowAction>[
      if (canStream || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _deps.handlePlayDownload(download),
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _deps.handleQueueDownload(download),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy Link',
        onSelected: () => _deps.handleDownloadAction(download),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.handleDeleteDownload(download),
      ),
    ];

    return CloudFileRow(
      kind: (canStream || isVideo) ? CloudRowKind.video : CloudRowKind.file,
      title: download.filename,
      meta:
          '${Formatters.formatFileSize(download.filesize)} · ${download.host}',
      onTap: (canStream || isVideo)
          ? () => _deps.handlePlayDownload(download)
          : null,
      actions: actions,
      selectionMode: _deps.selectionState.isSelectionMode,
      selected: _deps.selectionState.selectedDownloadIds.contains(download.id),
      onToggleSelected: () => _deps.toggleDownloadSelection(download.id),
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
      upFocusNode: (_deps.selectionState.isSelectionMode && index == 0)
          ? _deps.focusState.deleteButtonFocusNode
          : null,
    );
  }
}
