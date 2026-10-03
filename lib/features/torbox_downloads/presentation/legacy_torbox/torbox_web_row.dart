import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'torbox_focus_state.dart';
import 'torbox_selection_state.dart';

typedef TorboxWebRowDeps = ({
  BuildContext Function() context,
  TorboxFocusState focusState,
  Future<void> Function(TorboxWebDownload webDownload) handlePlayWebDownload,
  void Function(TorboxWebDownload webDownload) showWebDownloadOptionsDialog,
  void Function(TorboxWebDownload webDownload) navigateIntoWebDownload,
  Future<void> Function(TorboxWebDownload webDownload) copyWebDownloadLink,
  Future<void> Function(TorboxWebDownload webDownload) confirmDeleteWebDownload,
  TorboxSelectionState selectionState,
  void Function(int id) toggleWebDownloadSelection,
  bool Function() selectSourceMode,
  void Function(SeriesSource)? Function() onSourceSelected,
});

class TorboxWebRow {
  TorboxWebRow(this._deps);
  final TorboxWebRowDeps _deps;

  Widget buildWebDownloadCard(TorboxWebDownload webDownload, int index) {
    final videoCount = webDownload.files
        .where((file) => !file.zipped && torboxFileLooksLikeVideo(file))
        .length;

    if (_deps.selectSourceMode()) {
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: webDownload.name,
        meta:
            '${Formatters.formatFileSize(webDownload.size)} · ${webDownload.files.length} file${webDownload.files.length == 1 ? '' : 's'}',
        onTap: videoCount > 0
            ? () {
                _deps.onSourceSelected()?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: webDownload.name,
                    debridService: 'torbox',
                    debridTorrentId: webDownload.id.toString(),
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

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open.
    final actions = <CloudRowAction>[
      if (videoCount > 0)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _deps.handlePlayWebDownload(webDownload),
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download to device',
        showInStrip: true,
        onSelected: () => _deps.showWebDownloadOptionsDialog(webDownload),
      ),
      CloudRowAction(
        icon: Icons.folder_open,
        label: 'Open',
        onSelected: () => _deps.navigateIntoWebDownload(webDownload),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy Download Link',
        onSelected: () => _deps.copyWebDownloadLink(webDownload),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.confirmDeleteWebDownload(webDownload),
      ),
    ];

    return CloudFileRow(
      kind: CloudRowKind.folder,
      title: webDownload.name,
      meta:
          '${Formatters.formatFileSize(webDownload.size)} · ${webDownload.files.length} file${webDownload.files.length == 1 ? '' : 's'}',
      onTap: () => _deps.navigateIntoWebDownload(webDownload),
      actions: actions,
      selectionMode: _deps.selectionState.isSelectionMode,
      selected: _deps.selectionState.selectedWebDownloadIds.contains(
        webDownload.id,
      ),
      onToggleSelected: () => _deps.toggleWebDownloadSelection(webDownload.id),
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
    );
  }
}
