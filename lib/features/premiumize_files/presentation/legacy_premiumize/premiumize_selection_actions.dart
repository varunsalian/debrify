import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_selection_state.dart';

typedef PremiumizeSelectionActionsDeps = ({
  PremiumizeSelectionState selectionState,
  PremiumizeCatalogState catalogState,
  void Function(VoidCallback) setState,
});

class PremiumizeSelectionActions {
  PremiumizeSelectionActions(this._deps);
  final PremiumizeSelectionActionsDeps _deps;

  bool get isAllSelected =>
      _deps.selectionState.selectedIds.length ==
          _deps.catalogState.items.length &&
      _deps.catalogState.items.isNotEmpty;

  // ── Multi-select helpers ─────────────────────────────────────────────────────

  void toggleSelectionMode() {
    _deps.setState(() {
      if (_deps.selectionState.isSelectionMode) {
        _deps.selectionState.selectedIds.clear();
      }
      _deps.selectionState.isSelectionMode =
          !_deps.selectionState.isSelectionMode;
    });
  }

  void exitSelectionMode() {
    if (!_deps.selectionState.isSelectionMode) return;
    _deps.setState(() {
      _deps.selectionState.isSelectionMode = false;
      _deps.selectionState.selectedIds.clear();
    });
  }

  void toggleSelection(String id) {
    _deps.setState(() {
      if (_deps.selectionState.selectedIds.contains(id)) {
        _deps.selectionState.selectedIds.remove(id);
      } else {
        _deps.selectionState.selectedIds.add(id);
      }
    });
  }

  void toggleSelectAll() {
    _deps.setState(() {
      if (isAllSelected) {
        _deps.selectionState.selectedIds.clear();
      } else {
        _deps.selectionState.selectedIds
          ..clear()
          ..addAll(_deps.catalogState.items.map((i) => i.id));
      }
    });
  }
}
