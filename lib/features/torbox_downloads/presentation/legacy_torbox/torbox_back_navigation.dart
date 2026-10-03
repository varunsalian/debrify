import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

import 'torbox_folder_search_state.dart';
import 'torbox_navigation_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_torrent_search_state.dart';

typedef TorboxBackNavigationDeps = ({
  BuildContext Function() context,
  TorboxSelectionState selectionState,
  void Function() exitSelectionMode,
  TorboxTorrentSearchState torrentSearchState,
  void Function() toggleTorrentSearch,
  TorboxFolderSearchState folderSearchState,
  void Function() toggleSearch,
  bool Function() isAtRoot,
  TorboxNavigationState navigationState,
  void Function() navigateUp,
  bool Function() selectSourceMode,
  bool Function() isPushedRoute,
  TorboxTorrent? Function() initialTorrentToOpen,
});

class TorboxBackNavigation {
  TorboxBackNavigation(this._deps);
  final TorboxBackNavigationDeps _deps;

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

    // Close torrent search first if active
    if (_deps.torrentSearchState.isTorrentSearchActive) {
      _deps.toggleTorrentSearch();
      return true;
    }

    // Close file search first if active
    if (_deps.folderSearchState.isSearchActive) {
      _deps.toggleSearch();
      return true;
    }

    // If inside a subfolder within a torrent, navigate up
    if (!_deps.isAtRoot() && _deps.navigationState.navigationStack.length > 1) {
      _deps.navigateUp();
      return true;
    }

    // At torrent root level (viewing torrent files, not inside a subfolder)
    if (!_deps.isAtRoot() &&
        _deps.navigationState.navigationStack.length == 1) {
      // Deep-linked directly into this torrent (pushed WITH a target) → pop back
      // to the caller. Browsing from the Cloud hub (no target) → fall through to
      // _navigateUp so Back returns to the downloads list, not out of the screen.
      if (_deps.isPushedRoute() && _deps.initialTorrentToOpen() != null) {
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

    return false; // At root, let app handle it
  }
}
