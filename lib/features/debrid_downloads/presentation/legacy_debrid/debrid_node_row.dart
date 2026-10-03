import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'debrid_focus_state.dart';

typedef DebridNodeRowDeps = ({
  Future<void> Function(RDFileNode folder) playFolder,
  Future<void> Function(RDFileNode file) playFile,
  Future<void> Function(RDFileNode folder) downloadFolder,
  Future<void> Function(RDFileNode file) downloadFile,
  Future<void> Function(RDFileNode folder) addFolderToPlaylist,
  Future<void> Function(RDFileNode file) addNodeFileToPlaylist,
  Future<void> Function(RDFileNode node) copyNodeDownloadLink,
  void Function(RDFileNode folder) navigateIntoFolder,
  DebridFocusState focusState,
});

class DebridNodeRow {
  DebridNodeRow(this._deps);
  final DebridNodeRowDeps _deps;

  Widget buildNodeCard(RDFileNode node, int index) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);

    // Same action set (labels, conditions) the old pills + ⋮ menu offered —
    // no delete at node granularity, exactly as before.
    final actions = <CloudRowAction>[
      if (isFolder || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _deps.playFolder(node);
            } else {
              _deps.playFile(node);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () {
          if (isFolder) {
            _deps.downloadFolder(node);
          } else {
            _deps.downloadFile(node);
          }
        },
      ),
      if (isFolder || isVideo)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () {
            if (isFolder) {
              _deps.addFolderToPlaylist(node);
            } else {
              _deps.addNodeFileToPlaylist(node);
            }
          },
        ),
      if (!isFolder)
        CloudRowAction(
          icon: Icons.link,
          label: 'Copy Download Link',
          onSelected: () => _deps.copyNodeDownloadLink(node),
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
          ? '${RDFolderTreeBuilder.countFiles(node)} files · ${Formatters.formatFileSize(node.totalBytes)}'
          : Formatters.formatFileSize(node.bytes ?? 0),
      onTap: isFolder
          ? () => _deps.navigateIntoFolder(node)
          : isVideo
          ? () => _deps.playFile(node)
          : null,
      actions: actions,
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
    );
  }
}
