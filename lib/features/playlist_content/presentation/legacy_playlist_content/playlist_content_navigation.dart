import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentNavigationDeps = ({
  PlaylistContentSearchState searchState,
  void Function() toggleSearch,
  PlaylistContentNavigationState navigationState,
  void Function(VoidCallback) setState,
  void Function(FolderViewMode mode) applyViewMode,
  BuildContext Function() context,
});

class PlaylistContentNavigation {
  PlaylistContentNavigation(this._deps);
  final PlaylistContentNavigationDeps _deps;

  /// Handle back navigation for folder browsing.
  /// Returns true if handled (navigated up folder), false if at root (let Navigator.pop handle it).
  bool handleBackNavigation() {
    // Close search first if active
    if (_deps.searchState.isSearchActive) {
      _deps.toggleSearch();
      return true; // We handled the back press (closed search)
    }
    if (_deps.navigationState.folderPath.isNotEmpty) {
      navigateUp();
      return true; // We handled the back press (navigated up a folder)
    }
    return false; // At root, let the normal pop behavior happen
  }

  /// Navigate into a folder
  void navigateIntoFolder(RDFileNode folder) {
    if (!folder.isFolder) return;

    _deps.setState(() {
      _deps.navigationState.folderPath.add(folder.name);
    });

    _deps.applyViewMode(_deps.navigationState.currentViewMode);
  }

  /// Navigate up one level
  void navigateUp() {
    if (_deps.navigationState.folderPath.isEmpty) {
      Navigator.of(_deps.context()).pop();
      return;
    }

    _deps.setState(() {
      _deps.navigationState.folderPath.removeLast();
    });

    _deps.applyViewMode(_deps.navigationState.currentViewMode);
  }
}
