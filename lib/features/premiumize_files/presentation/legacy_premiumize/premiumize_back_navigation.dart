import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

import 'premiumize_navigation_state.dart';
import 'premiumize_search_state.dart';
import 'premiumize_selection_state.dart';

typedef PremiumizeBackNavigationDeps = ({
  PremiumizeSelectionState selectionState,
  void Function() exitSelectionMode,
  PremiumizeSearchState searchState,
  void Function() toggleSearch,
  PremiumizeNavigationState navigationState,
  void Function() navigateUp,
  bool Function() isPushedRoute,
  BuildContext Function() context,
});

class PremiumizeBackNavigation {
  PremiumizeBackNavigation(this._deps);
  final PremiumizeBackNavigationDeps _deps;

  bool handleBackNavigation() {
    if (_deps.selectionState.isSelectionMode) {
      _deps.exitSelectionMode();
      return true;
    }
    if (_deps.searchState.isSearchActive) {
      _deps.toggleSearch();
      return true;
    }
    if (_deps.navigationState.navigationStack.isNotEmpty) {
      _deps.navigateUp();
      return true;
    }
    // At this folder's root (no deeper stack). If opened as a pushed route
    // (e.g. deep-linked into a specific folder), pop back to the caller.
    if (_deps.isPushedRoute()) {
      Navigator.of(_deps.context()).pop();
      return true;
    }
    if (MainPageBridge.returnToTorrentSearchOnBack) {
      MainPageBridge.returnToTorrentSearchOnBack = false;
      MainPageBridge.switchTab?.call(MainTab.legacyTorrentSearch);
      return true;
    }
    return false;
  }
}
