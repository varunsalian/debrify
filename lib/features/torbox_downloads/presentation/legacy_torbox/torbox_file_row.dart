import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/torbox_folder_tree_builder.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'torbox_focus_state.dart';
import 'torbox_navigation_state.dart';

typedef TorboxFileRowDeps = ({
  Future<void> Function(RDFileNode folderNode) playFolderVideos,
  Future<void> Function(RDFileNode fileNode) playVideoFile,
  Future<void> Function(RDFileNode node) downloadFileOrFolder,
  TorboxNavigationState navigationState,
  Future<void> Function(RDFileNode node) addFileOrFolderToPlaylist,
  Future<void> Function(RDFileNode node) copyFileLink,
  void Function(RDFileNode folderNode) navigateIntoFolder,
  TorboxFocusState focusState,
});

class TorboxFileRow {
  TorboxFileRow(this._deps);
  final TorboxFileRowDeps _deps;

  /// Build a card for a file or folder node (inside a torrent)
  Widget buildFileOrFolderCard(RDFileNode node, int index) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);
    final folderHasVideos =
        isFolder && TorboxFolderTreeBuilder.hasVideoFiles(node);

    // Same action set (labels, conditions) the old pills + ⋮ menu offered —
    // note: no delete at node granularity, and Add to Playlist only for
    // torrents (not web downloads), exactly as before.
    final actions = <CloudRowAction>[
      if (folderHasVideos || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _deps.playFolderVideos(node);
            } else {
              _deps.playVideoFile(node);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _deps.downloadFileOrFolder(node),
      ),
      if (_deps.navigationState.currentWebDownload == null &&
          (isVideo || folderHasVideos))
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _deps.addFileOrFolderToPlaylist(node),
        ),
      if (!isFolder)
        CloudRowAction(
          icon: Icons.link,
          label: 'Copy Link',
          onSelected: () => _deps.copyFileLink(node),
        ),
    ];

    return CloudFileRow(
      kind: isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: node.name,
      meta: isFolder
          ? '${node.fileCount} items · ${Formatters.formatFileSize(node.totalBytes)}'
          : Formatters.formatFileSize(node.bytes ?? 0),
      onTap: isFolder
          ? () => _deps.navigateIntoFolder(node)
          : isVideo
          ? () => _deps.playVideoFile(node)
          : null,
      actions: actions,
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
    );
  }
}
