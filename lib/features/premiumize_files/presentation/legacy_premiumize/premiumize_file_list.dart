import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';
import 'premiumize_selection_state.dart';

typedef PremiumizeFileListDeps = ({
  PremiumizeFocusState focusState,
  PremiumizeCatalogState catalogState,
  String Function(int seconds) formatUnixDate,
  bool Function() selectSourceMode,
  Future<void> Function(PremiumizeFolderItem item) selectBoundSource,
  void Function(PremiumizeFolderItem folder) navigateIntoFolder,
  Future<void> Function(PremiumizeFolderItem folder) playFolder,
  Future<void> Function(PremiumizeFolderItem file) playFile,
  Future<void> Function(PremiumizeFolderItem folder) downloadFolder,
  Future<void> Function(PremiumizeFolderItem file) downloadFile,
  Future<void> Function(PremiumizeFolderItem item) addToPlaylist,
  void Function(PremiumizeFolderItem item) showDeleteDialog,
  PremiumizeSelectionState selectionState,
  void Function(String id) toggleSelection,
});

class PremiumizeFileList {
  PremiumizeFileList(this._deps);
  final PremiumizeFileListDeps _deps;

  Widget buildFileList() {
    return ListView.builder(
      controller: _deps.focusState.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _deps.catalogState.items.length,
      itemBuilder: (context, index) {
        final item = _deps.catalogState.items[index];
        return KeyedSubtree(
          key: ValueKey(item.id),
          child: buildFileCard(item, index),
        );
      },
    );
  }

  Widget buildFileCard(
    PremiumizeFolderItem item,
    int index, {
    bool autofocusFirst = true,
  }) {
    final isVideo = item.isVideo;
    final date = _deps.formatUnixDate(item.createdAt);
    final metaParts = <String>[
      if (!item.isFolder && item.size > 0) Formatters.formatFileSize(item.size),
      if (date.isNotEmpty) date,
    ];

    if (_deps.selectSourceMode()) {
      return CloudFileRow(
        kind: item.isFolder
            ? CloudRowKind.folder
            : isVideo
            ? CloudRowKind.video
            : CloudRowKind.file,
        title: item.name,
        meta: metaParts.isEmpty ? null : metaParts.join(' · '),
        onTap: (item.isFolder || isVideo)
            ? () => _deps.selectBoundSource(item)
            : null,
        actions: item.isFolder
            ? [
                CloudRowAction(
                  icon: Icons.folder_open_rounded,
                  label: 'Browse folder',
                  onSelected: () => _deps.navigateIntoFolder(item),
                ),
              ]
            : const [],
        focusNode: (autofocusFirst && index == 0)
            ? _deps.focusState.firstItemFocusNode
            : null,
      );
    }

    // Same action set (labels, icons, conditions) the old Open/Play pills +
    // ⋮ menu offered; the row's tap now carries Open (folders) and Play
    // (videos).
    final actions = <CloudRowAction>[
      // Videos get a ▶ too, even though tapping the row already plays them —
      // folder rows have one, and a video row without it reads as unplayable.
      if (item.isFolder || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (item.isFolder) {
              _deps.playFolder(item);
            } else {
              _deps.playFile(item);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () {
          if (item.isFolder) {
            _deps.downloadFolder(item);
          } else {
            _deps.downloadFile(item);
          }
        },
      ),
      if (item.isFolder || isVideo)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _deps.addToPlaylist(item),
        ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _deps.showDeleteDialog(item),
      ),
    ];

    return CloudFileRow(
      kind: item.isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: item.name,
      meta: metaParts.isEmpty ? null : metaParts.join(' · '),
      onTap: item.isFolder
          ? () => _deps.navigateIntoFolder(item)
          : isVideo
          ? () => _deps.playFile(item)
          : null,
      actions: actions,
      selectionMode: _deps.selectionState.isSelectionMode,
      selected: _deps.selectionState.selectedIds.contains(item.id),
      onToggleSelected: () => _deps.toggleSelection(item.id),
      focusNode: (autofocusFirst && index == 0)
          ? _deps.focusState.firstItemFocusNode
          : null,
    );
  }
}
