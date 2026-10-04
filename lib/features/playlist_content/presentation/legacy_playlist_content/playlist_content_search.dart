import 'package:debrify/features/playlist_content/models/playlist_content_search_result.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentSearchDeps = ({
  void Function(VoidCallback) setState,
  PlaylistContentSearchState searchState,
  PlaylistContentFocusState focusState,
  PlaylistContentCatalogState catalogState,
});

class PlaylistContentSearch {
  PlaylistContentSearch(this._deps);
  final PlaylistContentSearchDeps _deps;

  // ============ Search Methods ============
  /// Toggle search mode on/off
  void toggleSearch() {
    _deps.setState(() {
      _deps.searchState.isSearchActive = !_deps.searchState.isSearchActive;
      if (!_deps.searchState.isSearchActive) {
        _deps.searchState.searchController.clear();
        _deps.searchState.searchResults.clear();
      } else {
        // Focus the search field when activating
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deps.focusState.searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files
  void performSearch(String query) {
    if (_deps.catalogState.rootContent == null || query.isEmpty) {
      _deps.setState(() => _deps.searchState.searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <PlaylistContentSearchResult>[];

    // Recursive function to search with path tracking
    void searchNode(RDFileNode node, List<String> path) {
      if (!node.isFolder) {
        // Only search video files
        if (FileUtils.isVideoFile(node.name) &&
            node.name.toLowerCase().contains(lowerQuery)) {
          results.add(
            PlaylistContentSearchResult(node: node, path: path.join(' / ')),
          );
        }
      } else {
        // Recurse into folder
        for (final child in node.children) {
          searchNode(child, [...path, node.name]);
        }
      }
    }

    // Start search from root's children (skip root name itself)
    for (final child in _deps.catalogState.rootContent!.children) {
      searchNode(child, []);
    }

    _deps.setState(() => _deps.searchState.searchResults = results);
  }
}
