import 'package:debrify/features/torbox_downloads/presentation/folder_view_mode.dart';
import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_folder_search_state.dart';
import 'torbox_navigation_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_torrent_search_state.dart';
import 'torbox_view_state.dart';
import 'torbox_web_state.dart';

typedef TorboxRootLayoutDeps = ({
  bool Function() isAtRoot,
  TorboxCatalogState catalogState,
  TorboxWebState webState,
  TorboxViewState viewState,
  TorboxNavigationState navigationState,
  FolderViewMode Function() getCurrentViewMode,
  TorboxFocusState focusState,
  bool Function() handleBackNavigation,
  String Function() currentFolderName,
  TorboxFolderSearchState folderSearchState,
  void Function() toggleSearch,
  Widget Function() buildToolbar,
  Widget Function() buildViewSelectorBar,
  TorboxTorrentSearchState torrentSearchState,
  Widget Function() buildTorrentSearchBar,
  TorboxSelectionState selectionState,
  Widget Function() buildSelectionBar,
  Widget Function() buildViewModeDropdown,
  Widget Function() buildSearchBar,
  Widget Function() buildTorrentSearchResults,
  Widget Function() buildSearchResults,
  Future<void> Function() refresh,
  Widget Function() buildFilesFoldersList,
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  TorboxTorrent? Function() initialTorrentToOpen,
});

class TorboxRootLayout {
  TorboxRootLayout(this._deps);
  final TorboxRootLayoutDeps _deps;

  /// Get items to display (torrents/web downloads or files/folders)
  List<dynamic> get currentItems {
    if (_deps.isAtRoot()) {
      // At root: show torrents or web downloads based on selected view
      if (_deps.catalogState.selectedView == TorboxDownloadsView.webDownloads) {
        return _deps.webState.webDownloads;
      }
      return _deps.catalogState.torrents;
    } else {
      // Inside torrent/web download: show current folder's children (transformed by view mode)
      return _deps.viewState.currentViewNodes ??
          _deps.navigationState.currentFolderNode?.children ??
          [];
    }
  }

  Widget build(BuildContext context) {
    // Back navigation is handled via MainPageBridge.handleBackNavigation

    // When DEEP-LINKED into a specific torrent (pushed WITH a target) and still
    // at root, show the loading state. Browsing from the Cloud hub has no target,
    // so the list root is the real content — don't gate it behind a spinner.
    if (_deps.isPushedRoute() &&
        !_deps.selectSourceMode() &&
        _deps.initialTorrentToOpen() != null &&
        _deps.isAtRoot()) {
      return CloudScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: const Text('Opening torrent...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading torrent files...'),
            ],
          ),
        ),
      );
    }

    final currentMode = _deps.getCurrentViewMode();
    final showSearch =
        !_deps.isAtRoot() && currentMode != FolderViewMode.seriesArrange;

    return CloudScaffold(
      appBar: _deps.isAtRoot()
          ? (_deps.selectSourceMode()
                ? AppBar(
                    leading: IconButton(
                      focusNode: _deps.focusState.backButtonFocusNode,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                    ),
                    title: const Text('Select Source from TorBox'),
                  )
                : null)
          : AppBar(
              leading: IconButton(
                focusNode: _deps.focusState.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _deps.handleBackNavigation(),
                tooltip: 'Back',
              ),
              title: Text(_deps.currentFolderName()),
              actions: [
                if (showSearch)
                  Focus(
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
                  ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_deps.isAtRoot() && !_deps.selectSourceMode())
            _deps.buildToolbar(),
          if (_deps.isAtRoot()) _deps.buildViewSelectorBar(),
          if (_deps.isAtRoot() &&
              _deps.torrentSearchState.isTorrentSearchActive)
            _deps.buildTorrentSearchBar(),
          if (_deps.isAtRoot() && _deps.selectionState.isSelectionMode)
            _deps.buildSelectionBar(),
          if (!_deps.isAtRoot()) _deps.buildViewModeDropdown(),
          if (_deps.folderSearchState.isSearchActive && showSearch)
            _deps.buildSearchBar(),
          Expanded(
            child:
                _deps.torrentSearchState.isTorrentSearchActive &&
                    _deps.isAtRoot()
                ? _deps.buildTorrentSearchResults()
                : _deps.folderSearchState.isSearchActive
                ? _deps.buildSearchResults()
                : RefreshIndicator(
                    onRefresh: _deps.refresh,
                    child: _deps.buildFilesFoldersList(),
                  ),
          ),
        ],
      ),
    );
  }
}
