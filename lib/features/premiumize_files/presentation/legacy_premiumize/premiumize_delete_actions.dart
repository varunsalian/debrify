import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_search_state.dart';
import 'premiumize_selection_state.dart';

typedef PremiumizeDeleteActionsDeps = ({
  BuildContext Function() context,
  PremiumizeSelectionState selectionState,
  PremiumizeCatalogState catalogState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PremiumizeSearchState searchState,
});

class PremiumizeDeleteActions {
  PremiumizeDeleteActions(this._deps);
  final PremiumizeDeleteActionsDeps _deps;

  // ── Delete ─────────────────────────────────────────────────────────────────

  void showDeleteDialog(PremiumizeFolderItem item) {
    showDialog(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.isFolder ? 'Folder' : 'File'}'),
        content: Text(
          'Permanently delete "${item.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              executeDelete([item]);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> handleDeleteSelected() async {
    if (_deps.selectionState.selectedIds.isEmpty) return;
    final selected = _deps.catalogState.items
        .where((i) => _deps.selectionState.selectedIds.contains(i.id))
        .toList();
    final count = selected.length;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: Text('Delete $count item${count == 1 ? '' : 's'}'),
        content: Text(
          'Permanently delete $count selected item${count == 1 ? '' : 's'}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await executeDelete(selected);
    }
  }

  Future<void> executeDelete(List<PremiumizeFolderItem> items) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _deps.showSnackBar(
      'Deleting ${items.length} item${items.length == 1 ? '' : 's'}...',
      isError: false,
    );
    final deletedIds = <String>{};
    int fail = 0;
    for (final item in items) {
      try {
        if (item.isFolder) {
          await PremiumizeService.deleteFolder(apiKey, item.id);
        } else {
          await PremiumizeService.deleteItem(apiKey, item.id);
        }
        deletedIds.add(item.id);
      } catch (_) {
        fail++;
      }
    }
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _deps.catalogState.items.removeWhere((i) => deletedIds.contains(i.id));
      _deps.searchState.searchResults.removeWhere(
        (i) => deletedIds.contains(i.id),
      );
      _deps.selectionState.selectedIds.clear();
      _deps.selectionState.isSelectionMode = false;
    });
    if (fail == 0) {
      _deps.showSnackBar(
        'Deleted ${deletedIds.length} item${deletedIds.length == 1 ? '' : 's'}',
        isError: false,
      );
    } else {
      _deps.showSnackBar(
        'Deleted ${deletedIds.length}, $fail failed',
        isError: true,
      );
    }
  }
}
