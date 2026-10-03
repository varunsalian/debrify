import 'package:debrify/features/debrid_downloads/models/rd_search_result.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

import 'debrid_focus_state.dart';
import 'debrid_folder_search_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridFolderSearchDeps = ({
  void Function(VoidCallback) setState,
  DebridFolderSearchState folderSearchState,
  DebridFocusState focusState,
  DebridNavigationState navigationState,
});

class DebridFolderSearch {
  DebridFolderSearch(this._deps);
  final DebridFolderSearchDeps _deps;

  /// Toggle search mode on/off
  void toggleSearch() {
    _deps.setState(() {
      _deps.folderSearchState.isSearchActive =
          !_deps.folderSearchState.isSearchActive;
      if (!_deps.folderSearchState.isSearchActive) {
        _deps.folderSearchState.searchController.clear();
        _deps.folderSearchState.searchResults.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deps.focusState.searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files in current torrent
  void performSearch(String query) {
    if (_deps.navigationState.currentFolderTree == null || query.isEmpty) {
      _deps.setState(() => _deps.folderSearchState.searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <RDSearchResult>[];

    void searchNode(RDFileNode node, List<String> path) {
      if (!node.isFolder) {
        if (FileUtils.isVideoFile(node.name) &&
            node.name.toLowerCase().contains(lowerQuery)) {
          results.add(RDSearchResult(node: node, path: path.join(' / ')));
        }
      } else {
        for (final child in node.children) {
          searchNode(child, [...path, node.name]);
        }
      }
    }

    for (final child in _deps.navigationState.currentFolderTree!.children) {
      searchNode(child, []);
    }

    _deps.setState(() => _deps.folderSearchState.searchResults = results);
  }
}
