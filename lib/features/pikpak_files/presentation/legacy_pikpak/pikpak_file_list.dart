import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_focus_state.dart';
import 'pikpak_selection_state.dart';

typedef PikpakFileListDeps = ({
  PikpakCatalogState catalogState,
  PikpakFocusState focusState,
  bool Function() selectSourceMode,
  Future<void> Function(Map<String, dynamic> file) selectBoundSource,
  void Function(String folderId, String folderName) navigateIntoFolder,
  Future<void> Function(Map<String, dynamic> folder) playFolder,
  Future<void> Function(Map<String, dynamic> fileData) playFile,
  Future<void> Function(Map<String, dynamic> folder) downloadFolder,
  Future<void> Function(Map<String, dynamic> file) downloadFile,
  Future<void> Function(Map<String, dynamic> file) handleAddToPlaylist,
  void Function(Map<String, dynamic> file) showDeleteDialog,
  PikpakSelectionState selectionState,
  void Function(Map<String, dynamic> virtualFolder) navigateIntoVirtualFolder,
  void Function(String id) toggleFileSelection,
});

class PikpakFileList {
  PikpakFileList(this._deps);
  final PikpakFileListDeps _deps;

  Widget buildFileList() {
    // Add 1 to item count for loading indicator when loading more
    final itemCount =
        _deps.catalogState.files.length +
        (_deps.catalogState.isLoadingMore || _deps.catalogState.hasMore
            ? 1
            : 0);

    return ListView.builder(
      controller: _deps.focusState.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Show loading indicator at the end
        if (index >= _deps.catalogState.files.length) {
          return buildLoadingIndicator();
        }
        final file = _deps.catalogState.files[index];
        return KeyedSubtree(
          key: ValueKey(file['id'] ?? index),
          child: buildFileCard(file, index),
        );
      },
    );
  }

  Widget buildLoadingIndicator() {
    if (_deps.catalogState.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Show a subtle hint that more can be loaded
    if (_deps.catalogState.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Scroll for more',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget buildFileCard(Map<String, dynamic> file, int index) {
    final name = file['name']?.toString() ?? 'Unknown';
    final size = file['size'];
    final mimeType = file['mime_type'] ?? '';
    final kind = file['kind'] ?? '';
    final phase = file['phase'] ?? '';
    final createdTime = file['created_time'] ?? '';
    final fileId = file['id'] as String?;

    final isFolder = kind == 'drive#folder';
    final isVirtualFolder = kind == 'virtual#season'; // Virtual Season folder
    final isVideo =
        mimeType.startsWith('video/') || FileUtils.isVideoFile(name);
    final isComplete = phase == 'PHASE_TYPE_COMPLETE';

    final date = formatDate(createdTime);
    final metaParts = <String>[
      if (size != null)
        Formatters.formatFileSize(int.tryParse(size.toString()) ?? 0),
      if (date.isNotEmpty) date,
    ];

    if (_deps.selectSourceMode()) {
      final selectable =
          !isVirtualFolder && (isFolder || (isVideo && isComplete));
      return CloudFileRow(
        kind: isVirtualFolder
            ? CloudRowKind.season
            : isFolder
            ? CloudRowKind.folder
            : isVideo
            ? CloudRowKind.video
            : CloudRowKind.file,
        title: name,
        meta: metaParts.isEmpty ? null : metaParts.join(' · '),
        extra: (!isComplete && !isVirtualFolder)
            ? Text(
                'Still downloading',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 12.5),
              )
            : null,
        onTap: selectable ? () => _deps.selectBoundSource(file) : null,
        actions: isFolder
            ? [
                CloudRowAction(
                  icon: Icons.folder_open_rounded,
                  label: 'Browse folder',
                  onSelected: () => _deps.navigateIntoFolder(file['id'], name),
                ),
              ]
            : const [],
        focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old pills + ⋮ menu offered.
    // Virtual Season folders keep their special shape: Open only (via tap),
    // no menu, not selectable.
    final actions = <CloudRowAction>[
      if (!isVirtualFolder) ...[
        if (isFolder || (isVideo && isComplete))
          CloudRowAction(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            showInStrip: true,
            onSelected: () {
              if (isFolder) {
                _deps.playFolder(file);
              } else {
                _deps.playFile(file);
              }
            },
          ),
        CloudRowAction(
          icon: Icons.download,
          label: 'Download',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _deps.downloadFolder(file);
            } else {
              _deps.downloadFile(file);
            }
          },
        ),
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _deps.handleAddToPlaylist(file),
        ),
        CloudRowAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onSelected: () => _deps.showDeleteDialog(file),
        ),
      ],
    ];

    return CloudFileRow(
      kind: isVirtualFolder
          ? CloudRowKind.season
          : isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: name,
      meta: metaParts.isEmpty ? null : metaParts.join(' · '),
      // Virtual season rows are client-synthesized and carry no 'phase', so
      // without the !isVirtualFolder gate they'd show a perpetual spinner.
      extra:
          (!isComplete &&
              !isVirtualFolder &&
              !_deps.selectionState.isSelectionMode)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Downloading...',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            )
          : null,
      onTap: isVirtualFolder
          ? () => _deps.navigateIntoVirtualFolder(file)
          : isFolder
          ? () => _deps.navigateIntoFolder(file['id'], name)
          : (isVideo && isComplete)
          ? () => _deps.playFile(file)
          : null,
      actions: actions,
      selectionMode: _deps.selectionState.isSelectionMode,
      selected:
          fileId != null &&
          _deps.selectionState.selectedFileIds.contains(fileId),
      selectable: fileId != null && !isVirtualFolder,
      onToggleSelected: fileId != null
          ? () => _deps.toggleFileSelection(fileId)
          : null,
      focusNode: index == 0 ? _deps.focusState.firstItemFocusNode : null,
    );
  }

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
