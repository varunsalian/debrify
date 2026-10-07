import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AllDebridSelectionDeps = ({
  AllDebridSelectionState selectionState,
  void Function(VoidCallback) setState,
  bool Function() isAllSelected,
  List<AllDebridMagnet> Function() visibleMagnets,
});

class AllDebridSelection {
  final AllDebridSelectionDeps _deps;
  AllDebridSelection(this._deps);
  AllDebridSelectionState get _selection => _deps.selectionState;

  // ── Selection ─────────────────────────────────────────────────────────────

  void toggleSelectionMode() {
    _deps.setState(() {
      _selection.selectionMode = !_selection.selectionMode;
      if (!_selection.selectionMode) _selection.selectedIds.clear();
    });
  }

  void exitSelectionMode() {
    if (!_selection.selectionMode && _selection.selectedIds.isEmpty) return;
    _deps.setState(() {
      _selection.selectionMode = false;
      _selection.selectedIds.clear();
    });
  }

  void toggleSelection(String id) {
    _deps.setState(() {
      if (_selection.selectedIds.contains(id)) {
        _selection.selectedIds.remove(id);
      } else {
        _selection.selectedIds.add(id);
      }
    });
  }

  bool get isAllSelected =>
      _deps.visibleMagnets().isNotEmpty &&
      _deps.visibleMagnets().every(
        (m) => _selection.selectedIds.contains(m.id),
      );

  void toggleSelectAll() {
    _deps.setState(() {
      if (_deps.isAllSelected()) {
        for (final m in _deps.visibleMagnets()) {
          _selection.selectedIds.remove(m.id);
        }
      } else {
        for (final m in _deps.visibleMagnets()) {
          _selection.selectedIds.add(m.id);
        }
      }
    });
  }
}
