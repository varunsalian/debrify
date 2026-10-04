import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentRootLayoutDeps = ({
  PlaylistContentFocusState focusState,
  void Function() navigateUp,
  PlaylistContentNavigationState navigationState,
  PlaylistContentSearchState searchState,
  void Function() toggleSearch,
  Future<void> Function() loadContent,
  PlaylistContentCatalogState catalogState,
  void Function(FolderViewMode mode) applyViewMode,
  Widget Function() buildSearchBar,
  Widget Function() buildSearchResults,
  Widget Function() buildContent,
});

class PlaylistContentRootLayout {
  PlaylistContentRootLayout(this._deps);
  final PlaylistContentRootLayoutDeps _deps;

  Widget build(BuildContext context) {
    // Back navigation is handled via MainPageBridge.handleBackNavigation
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          focusNode: _deps.focusState.backButtonFocusNode,
          icon: const Icon(Icons.arrow_back),
          onPressed: _deps.navigateUp,
        ),
        actions: [
          // Search button (only for Raw and Sort A-Z modes)
          if (_deps.navigationState.currentViewMode !=
              FolderViewMode.seriesArrange)
            IconButton(
              focusNode: _deps.focusState.searchButtonFocusNode,
              icon: Icon(
                _deps.searchState.isSearchActive ? Icons.close : Icons.search,
              ),
              onPressed: _deps.toggleSearch,
              tooltip: _deps.searchState.isSearchActive
                  ? 'Close search'
                  : 'Search files',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _deps.loadContent,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // View mode dropdown
          if (!_deps.catalogState.isLoading &&
              _deps.catalogState.errorMessage == null)
            ViewModeDropdown(
              currentMode: _deps.navigationState.currentViewMode,
              onModeChanged: _deps.applyViewMode,
              focusNode: _deps.focusState.viewModeDropdownFocusNode,
            ),

          // Search bar (only for Raw and Sort A-Z modes when active)
          if (_deps.searchState.isSearchActive &&
              _deps.navigationState.currentViewMode !=
                  FolderViewMode.seriesArrange)
            _deps.buildSearchBar(),

          // Content area
          Expanded(
            child: _deps.searchState.isSearchActive
                ? _deps.buildSearchResults()
                : _deps.buildContent(),
          ),
        ],
      ),
    );
  }
}
