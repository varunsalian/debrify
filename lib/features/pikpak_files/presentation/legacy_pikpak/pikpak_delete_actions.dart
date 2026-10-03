import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_selection_state.dart';

typedef PikpakDeleteActionsDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PikpakCatalogState catalogState,
  PikpakSelectionState selectionState,
  void Function() exitSelectionMode,
});

class PikpakDeleteActions {
  PikpakDeleteActions(this._deps);
  final PikpakDeleteActionsDeps _deps;

  void showDeleteDialog(Map<String, dynamic> file) {
    final fileName = file['name'] ?? 'this item';
    final fileId = file['id'] as String?;

    if (fileId == null) {
      _deps.showSnackBar('Cannot delete: Invalid file ID');
      return;
    }

    showDialog(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What would you like to do with "$fileName"?'),
            const SizedBox(height: 16),
            const Text(
              'Move to Trash: File can be recovered later\nDelete Permanently: Cannot be undone',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true, // Safe default for TV/DPAD
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              deleteFile(fileId, fileName, permanent: false);
            },
            child: const Text('Move to Trash'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              deleteFile(fileId, fileName, permanent: true);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> deleteFile(
    String fileId,
    String fileName, {
    required bool permanent,
  }) async {
    try {
      _deps.showSnackBar(
        permanent ? 'Deleting permanently...' : 'Moving to trash...',
        isError: false,
      );

      if (permanent) {
        await PikPakApiService.instance.batchDeleteFiles([fileId]);
      } else {
        await PikPakApiService.instance.batchTrashFiles([fileId]);
      }

      if (!_deps.mounted()) return;

      // Remove the file from the local list
      _deps.setState(() {
        _deps.catalogState.files.removeWhere((f) => f['id'] == fileId);
      });

      _deps.showSnackBar(
        permanent
            ? '"$fileName" deleted permanently'
            : '"$fileName" moved to trash',
        isError: false,
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar('Failed to delete: $e');
    }
  }

  Future<void> handleDeleteSelected() async {
    if (_deps.selectionState.selectedFileIds.isEmpty) return;

    final count = _deps.selectionState.selectedFileIds.length;
    final itemType = count == 1 ? 'file' : 'files';

    final result = await showDialog<String>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete $count $itemType',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What would you like to do with $count selected $itemType?',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Move to Trash: Files can be recovered later\nDelete Permanently: Cannot be undone',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('trash'),
            child: const Text('Move to Trash'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('permanent'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (result != null && _deps.mounted()) {
      await executeDeleteSelected(
        List<String>.from(_deps.selectionState.selectedFileIds),
        permanent: result == 'permanent',
      );
    }
  }

  Future<void> executeDeleteSelected(
    List<String> ids, {
    required bool permanent,
  }) async {
    final count = ids.length;
    final label = permanent ? 'Deleting permanently' : 'Moving to trash';

    _deps.showSnackBar(
      '$label $count ${count == 1 ? 'file' : 'files'}...',
      isError: false,
    );

    try {
      if (permanent) {
        await PikPakApiService.instance.batchDeleteFiles(ids);
      } else {
        await PikPakApiService.instance.batchTrashFiles(ids);
      }

      if (!_deps.mounted()) return;

      final deletedSet = ids.toSet();
      _deps.setState(() {
        _deps.catalogState.files.removeWhere(
          (f) => deletedSet.contains(f['id']),
        );
        _deps.selectionState.selectedFileIds.clear();
        _deps.selectionState.isSelectionMode = false;
      });

      _deps.showSnackBar(
        permanent
            ? '$count ${count == 1 ? 'file' : 'files'} deleted permanently'
            : '$count ${count == 1 ? 'file' : 'files'} moved to trash',
        isError: false,
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.exitSelectionMode();
      _deps.showSnackBar('Failed to delete: $e');
    }
  }
}
