import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

import 'pikpak_navigation_state.dart';
import 'pikpak_search_state.dart';
import 'pikpak_selection_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakBackNavigationDeps = ({
  PikpakSelectionState selectionState,
  void Function() exitSelectionMode,
  PikpakSearchState searchState,
  void Function() toggleSearch,
  PikpakViewState viewState,
  PikpakNavigationState navigationState,
  void Function() navigateUpWithVirtual,
  bool Function() isPushedRoute,
  BuildContext Function() context,
});

class PikpakBackNavigation {
  PikpakBackNavigation(this._deps);
  final PikpakBackNavigationDeps _deps;

  /// Handle back navigation for folder browsing.
  /// Returns true if handled (navigated up), false if at root level.
  bool handleBackNavigation() {
    // Exit selection mode first if active
    if (_deps.selectionState.isSelectionMode) {
      _deps.exitSelectionMode();
      return true;
    }

    // Close search first if active
    if (_deps.searchState.isSearchActive) {
      _deps.toggleSearch();
      return true;
    }

    // If inside a virtual folder or subfolder, navigate up
    if (_deps.viewState.isInVirtualFolder ||
        _deps.navigationState.navigationStack.isNotEmpty ||
        (_deps.navigationState.restrictedFolderId != null &&
            _deps.navigationState.currentFolderId !=
                _deps.navigationState.restrictedFolderId)) {
      _deps.navigateUpWithVirtual();
      return true;
    }

    // At torrent/folder root level (no subfolders to go up to)
    if (_deps.navigationState.currentFolderId != null) {
      // If pushed as a route, pop to go back
      if (_deps.isPushedRoute()) {
        Navigator.of(_deps.context()).pop();
        return true;
      }
      // If came from torrent search flow, switch back to torrent search tab
      if (MainPageBridge.returnToTorrentSearchOnBack) {
        MainPageBridge.returnToTorrentSearchOnBack = false;
        MainPageBridge.switchTab?.call(MainTab.legacyTorrentSearch);
        return true;
      }
    }

    return false; // At root, let app handle it
  }
}
