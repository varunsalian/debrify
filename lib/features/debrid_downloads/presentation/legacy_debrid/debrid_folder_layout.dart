import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_focus_state.dart';
import 'debrid_folder_search_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridFolderLayoutDeps = ({
  FolderViewMode Function() getCurrentViewMode,
  DebridFocusState focusState,
  bool Function() handleBackNavigation,
  String Function() getCurrentFolderTitle,
  DebridFolderSearchState folderSearchState,
  void Function() toggleSearch,
  DebridNavigationState navigationState,
  Future<void> Function(RDTorrent torrent) navigateIntoTorrent,
  Widget Function() buildViewModeDropdown,
  Widget Function() buildSearchBar,
  Widget Function() buildSearchResults,
  Widget Function(RDFileNode node, int index) buildNodeCard,
});

class DebridFolderLayout {
  DebridFolderLayout(this._deps);
  final DebridFolderLayoutDeps _deps;

  Widget buildFolderBrowserScaffold() {
    // Back navigation is handled via MainPageBridge.handleBackNavigation
    final currentMode = _deps.getCurrentViewMode();
    final showSearch = currentMode != FolderViewMode.seriesArrange;

    return CloudScaffold(
      appBar: AppBar(
        leading: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                MainPageBridge.focusTvSidebar != null) {
              MainPageBridge.focusTvSidebar!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: IconButton(
            focusNode: _deps.focusState.backButtonFocusNode,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _deps.handleBackNavigation(),
          ),
        ),
        title: Text(_deps.getCurrentFolderTitle()),
        actions: [
          if (showSearch)
            IconButton(
              focusNode: _deps.focusState.searchButtonFocusNode,
              icon: Icon(
                _deps.folderSearchState.isSearchActive
                    ? Icons.close
                    : Icons.search,
              ),
              onPressed: _deps.toggleSearch,
              tooltip: _deps.folderSearchState.isSearchActive
                  ? 'Close search'
                  : 'Search files',
            ),
          IconButton(
            focusNode: _deps.focusState.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _deps.navigationState.currentTorrent != null
                ? () => _deps.navigateIntoTorrent(
                    _deps.navigationState.currentTorrent!,
                  )
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          _deps.buildViewModeDropdown(),
          if (_deps.folderSearchState.isSearchActive && showSearch)
            _deps.buildSearchBar(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: _deps.folderSearchState.isSearchActive
                  ? _deps.buildSearchResults()
                  : buildFolderContentsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFolderLoadingView() {
    return const CloudRowSkeletonList();
  }

  Widget buildFolderContentsView() {
    if (_deps.navigationState.isLoadingFolder) {
      return buildFolderLoadingView();
    }

    if (_deps.navigationState.currentViewNodes == null ||
        _deps.navigationState.currentViewNodes!.isEmpty) {
      return const Center(child: Text('Empty folder'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deps.navigationState.currentViewNodes!.length,
      cacheExtent: 200.0, // Pre-cache items for smoother scrolling
      addRepaintBoundaries: true, // Optimize repainting
      itemBuilder: (context, index) {
        final node = _deps.navigationState.currentViewNodes![index];
        return RepaintBoundary(child: _deps.buildNodeCard(node, index));
      },
    );
  }
}
