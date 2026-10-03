import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_selection_state.dart';

typedef PikpakSelectionActionsDeps = ({
  PikpakCatalogState catalogState,
  PikpakSelectionState selectionState,
  void Function(VoidCallback) setState,
});

class PikpakSelectionActions {
  PikpakSelectionActions(this._deps);
  final PikpakSelectionActionsDeps _deps;

  int get selectableFileCount => _deps.catalogState.files
      .where((f) => (f['kind'] ?? '') != 'virtual#season')
      .length;

  bool get isAllSelected =>
      _deps.selectionState.selectedFileIds.length == selectableFileCount &&
      selectableFileCount > 0;

  void toggleSelectionMode() {
    _deps.setState(() {
      if (_deps.selectionState.isSelectionMode) {
        _deps.selectionState.selectedFileIds.clear();
      }
      _deps.selectionState.isSelectionMode =
          !_deps.selectionState.isSelectionMode;
    });
  }

  void exitSelectionMode() {
    if (!_deps.selectionState.isSelectionMode) return;
    _deps.setState(() {
      _deps.selectionState.isSelectionMode = false;
      _deps.selectionState.selectedFileIds.clear();
    });
  }

  void toggleFileSelection(String id) {
    _deps.setState(() {
      if (_deps.selectionState.selectedFileIds.contains(id)) {
        _deps.selectionState.selectedFileIds.remove(id);
      } else {
        _deps.selectionState.selectedFileIds.add(id);
      }
    });
  }

  void toggleSelectAll() {
    _deps.setState(() {
      if (isAllSelected) {
        _deps.selectionState.selectedFileIds.clear();
      } else {
        for (final file in _deps.catalogState.files) {
          final kind = file['kind'] ?? '';
          if (kind == 'virtual#season') continue; // Skip virtual folders
          final id = file['id'] as String?;
          if (id != null) _deps.selectionState.selectedFileIds.add(id);
        }
      }
    });
  }
}
