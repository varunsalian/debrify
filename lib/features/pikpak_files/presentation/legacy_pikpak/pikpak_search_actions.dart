import 'package:debrify/features/pikpak_files/models/pikpak_search_result.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_navigation_state.dart';
import 'pikpak_search_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakSearchActionsDeps = ({
  void Function(VoidCallback) setState,
  PikpakSearchState searchState,
  PikpakNavigationState navigationState,
  PikpakViewState viewState,
  PikpakCatalogState catalogState,
});

// ============ Search Methods ============
class PikpakSearchActions {
  PikpakSearchActions(this._deps);
  final PikpakSearchActionsDeps _deps;

  /// Toggle search mode on/off
  void toggleSearch() {
    _deps.setState(() {
      _deps.searchState.isSearchActive = !_deps.searchState.isSearchActive;
      if (!_deps.searchState.isSearchActive) {
        _deps.searchState.searchController.clear();
        _deps.searchState.searchResults.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deps.searchState.searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files in current folder recursively
  Future<void> performSearch(String query) async {
    if (query.isEmpty) {
      _deps.setState(() => _deps.searchState.searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <PikPakSearchResult>[];

    // Get cached recursive files or fetch them
    final folderId = _deps.navigationState.currentFolderId ?? '';
    List<Map<String, dynamic>> allFiles;

    if (_deps.viewState.recursiveFileCache.containsKey(folderId)) {
      allFiles = _deps.viewState.recursiveFileCache[folderId]!;
    } else {
      // For search, we need to use the current files if recursive cache not available
      allFiles = _deps.catalogState.files;
    }

    for (final file in allFiles) {
      final name = file['name'] as String? ?? '';
      final kind = file['kind'] as String? ?? '';
      final isVideo = kind.contains('video') || FileUtils.isVideoFile(name);

      if (isVideo && name.toLowerCase().contains(lowerQuery)) {
        // Get path from file data if available
        final parentPath = file['parent_name'] as String? ?? '';
        results.add(PikPakSearchResult(file: file, path: parentPath));
      }
    }

    _deps.setState(() => _deps.searchState.searchResults = results);
  }
}
