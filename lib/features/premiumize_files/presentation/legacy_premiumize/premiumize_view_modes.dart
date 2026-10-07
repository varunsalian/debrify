import 'package:debrify/features/premiumize_files/application/premiumize_sort_policy.dart';
import 'package:debrify/features/premiumize_files/models/folder_view_mode.dart';
import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_navigation_state.dart';
import 'premiumize_view_state.dart';

typedef PremiumizeViewModesDeps = ({
  bool Function() isAtRoot,
  PremiumizeViewState viewState,
  PremiumizeNavigationState navigationState,
  void Function(VoidCallback) setState,
  PremiumizeCatalogState catalogState,
});

class PremiumizeViewModes {
  PremiumizeViewModes(this._deps);
  final PremiumizeViewModesDeps _deps;

  // ── View modes ─────────────────────────────────────────────────────────────

  PremiumizeFolderViewMode getCurrentViewMode() {
    if (_deps.isAtRoot()) return PremiumizeFolderViewMode.raw;
    return _deps.viewState.folderViewModes[_deps
            .navigationState
            .currentFolderId!] ??
        PremiumizeFolderViewMode.raw;
  }

  void setViewMode(PremiumizeFolderViewMode mode) {
    if (_deps.isAtRoot()) return;
    _deps.setState(() {
      _deps.viewState.folderViewModes[_deps.navigationState.currentFolderId!] =
          mode;
      final reordered = applyViewMode(mode, _deps.catalogState.items);
      _deps.catalogState.items
        ..clear()
        ..addAll(reordered);
    });
  }

  List<PremiumizeFolderItem> applyViewMode(
    PremiumizeFolderViewMode mode,
    List<PremiumizeFolderItem> items,
  ) {
    if (mode == PremiumizeFolderViewMode.raw) return List.of(items);
    return applySortedView(items);
  }
}
