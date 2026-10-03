import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

import 'debrid_folder_search_state.dart';
import 'debrid_navigation_state.dart';
import 'debrid_selection_state.dart';

typedef DebridBackNavigationDeps = ({
  BuildContext Function() context,
  DebridSelectionState selectionState,
  void Function() exitSelectionMode,
  DebridFolderSearchState folderSearchState,
  void Function() toggleSearch,
  DebridNavigationState navigationState,
  void Function() navigateUp,
  bool Function() selectSourceMode,
  bool Function() isPushedRoute,
  RDTorrent? Function() initialTorrentForOptions,
});

class DebridBackNavigation {
  DebridBackNavigation(this._deps);
  final DebridBackNavigationDeps _deps;

  /// Handle back navigation for folder browsing.
  /// Returns true if handled (navigated up), false if at root level.
  bool handleBackNavigation() {
    // Select-source mode: back always pops the route.
    if (_deps.selectSourceMode() && _deps.isPushedRoute()) {
      Navigator.of(_deps.context()).pop();
      return true;
    }

    // Exit selection mode first if active
    if (_deps.selectionState.isSelectionMode) {
      _deps.exitSelectionMode();
      return true;
    }

    // Close search first if active
    if (_deps.folderSearchState.isSearchActive) {
      _deps.toggleSearch();
      return true;
    }

    // If inside a folder within the torrent, navigate up
    if (_deps.navigationState.currentTorrentId != null &&
        _deps.navigationState.folderPath.isNotEmpty) {
      _deps.navigateUp();
      return true;
    }

    // At torrent root level (viewing torrent files, not inside a subfolder)
    if (_deps.navigationState.currentTorrentId != null &&
        _deps.navigationState.folderPath.isEmpty) {
      // Deep-linked directly into this torrent (pushed WITH a target) → pop back
      // to the caller. Browsing (pushed from the Cloud hub without a target, or a
      // normal tab) → fall through to _navigateUp so Back returns to the torrents
      // list, not straight out of the screen.
      if (_deps.isPushedRoute() && _deps.initialTorrentForOptions() != null) {
        Navigator.of(_deps.context()).pop();
        return true;
      }
      // If came from torrent search flow, switch back to torrent search tab
      if (MainPageBridge.returnToTorrentSearchOnBack) {
        MainPageBridge.returnToTorrentSearchOnBack = false;
        MainPageBridge.switchTab?.call(MainTab.legacyTorrentSearch);
        return true;
      }
      // Normal case: go back to torrents list
      _deps.navigateUp();
      return true;
    }

    return false; // Not in folder mode, let app handle it
  }
}
