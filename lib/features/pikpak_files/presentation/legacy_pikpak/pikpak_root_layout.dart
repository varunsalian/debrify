import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_focus_state.dart';
import 'pikpak_navigation_state.dart';
import 'pikpak_search_state.dart';
import 'pikpak_selection_state.dart';
import 'pikpak_view_state.dart';

typedef PikpakRootLayoutDeps = ({
  bool Function() isPushedRoute,
  String? Function() initialFolderId,
  PikpakNavigationState navigationState,
  PikpakCatalogState catalogState,
  Widget Function() buildNotEnabled,
  Widget Function() buildError,
  PikpakViewState viewState,
  FolderViewMode Function() getCurrentViewMode,
  PikpakFocusState focusState,
  bool Function() handleBackNavigation,
  bool Function() selectSourceMode,
  PikpakSelectionState selectionState,
  void Function() toggleSelectionMode,
  PikpakSearchState searchState,
  void Function() toggleSearch,
  Future<void> Function() showAddLinkDialog,
  Future<void> Function() refreshFiles,
  Widget Function() buildSelectionBar,
  Widget Function() buildViewModeDropdown,
  Widget Function() buildSearchBar,
  Widget Function() buildSearchResults,
  Widget Function() buildEmpty,
  Widget Function() buildFileList,
});

class PikpakRootLayout {
  PikpakRootLayout(this._deps);
  final PikpakRootLayoutDeps _deps;

  Widget build(BuildContext context) {
    // When DEEP-LINKED into a specific folder (pushed WITH a target) and still
    // at root, show the loading state. Browsing from the Cloud hub has no target
    // (and non-restricted accounts stay at a null root folder), so don't gate the
    // real content behind a spinner.
    if (_deps.isPushedRoute() &&
        _deps.initialFolderId() != null &&
        _deps.navigationState.currentFolderId == null) {
      return CloudScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: const Text('Opening folder...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading folder contents...'),
            ],
          ),
        ),
      );
    }

    if (!_deps.catalogState.pikpakEnabled) {
      return _deps.buildNotEnabled();
    }

    if (_deps.catalogState.initialLoad && _deps.catalogState.isLoading) {
      return const CloudScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_deps.catalogState.errorMessage.isNotEmpty) {
      return _deps.buildError();
    }

    // Check if we should show the view mode dropdown
    // Only show when navigated at least one level deep (inside a folder)
    final showViewModeDropdown =
        _deps.navigationState.navigationStack.isNotEmpty ||
        _deps.viewState.isInVirtualFolder;
    final currentMode = _deps.getCurrentViewMode();
    final showSearch =
        showViewModeDropdown &&
        currentMode != FolderViewMode.seriesArrange &&
        !_deps.viewState.isInVirtualFolder;

    final bool isCompactActions = MediaQuery.sizeOf(context).width < 500;
    final double actionIconSize = isCompactActions ? 20 : 24;
    final EdgeInsets actionIconPadding = isCompactActions
        ? const EdgeInsets.all(6)
        : const EdgeInsets.all(8);
    final BoxConstraints actionIconConstraints = isCompactActions
        ? const BoxConstraints(minWidth: 36, minHeight: 36)
        : const BoxConstraints(minWidth: 48, minHeight: 48);

    // Back navigation is handled via MainPageBridge.handleBackNavigation
    return CloudScaffold(
      appBar: AppBar(
        leading:
            (_deps.navigationState.currentFolderId != null &&
                    !_deps.navigationState.isAtRestrictedRoot) ||
                _deps.viewState.isInVirtualFolder
            ? Focus(
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
                  tooltip: 'Back',
                ),
              )
            // At the browse root (opened from the Cloud hub with no folder
            // target) there's no folder-up back — offer a Back-to-hub instead.
            : (isBrowsePush
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _deps.viewState.isInVirtualFolder
                  ? _deps.viewState.virtualFolderName ?? 'Virtual Folder'
                  : _deps.selectSourceMode()
                  ? 'Select PikPak Source'
                  : _deps.navigationState.currentFolderName,
            ),
            if (_deps.navigationState.restrictedFolderId != null &&
                !_deps.viewState.isInVirtualFolder)
              const Text(
                'Restricted Access',
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
          ],
        ),
        actions: [
          // Keep the button mounted while a navigation fetch runs (_files is
          // cleared then) so the AppBar doesn't flicker and TV focus parked
          // on it isn't dropped.
          if ((_deps.catalogState.files.isNotEmpty ||
                  _deps.catalogState.isLoading) &&
              !_deps.viewState.isInVirtualFolder &&
              !_deps.selectSourceMode())
            IconButton(
              icon: Icon(
                _deps.selectionState.isSelectionMode
                    ? Icons.close
                    : Icons.checklist_outlined,
              ),
              onPressed: _deps.toggleSelectionMode,
              tooltip: _deps.selectionState.isSelectionMode
                  ? 'Exit selection'
                  : 'Select items',
              color: _deps.selectionState.isSelectionMode
                  ? Theme.of(context).colorScheme.error
                  : null,
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _deps.searchState.searchButtonFocusNode,
              icon: Icon(
                _deps.searchState.isSearchActive ? Icons.close : Icons.search,
              ),
              onPressed: _deps.toggleSearch,
              tooltip: _deps.searchState.isSearchActive
                  ? 'Close search'
                  : 'Search files',
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (!_deps.selectSourceMode())
            IconButton(
              focusNode: _deps.focusState.addLinkButtonFocusNode,
              icon: const Icon(Icons.add_link),
              onPressed: _deps.catalogState.isLoading
                  ? null
                  : _deps.showAddLinkDialog,
              tooltip: 'Add Link',
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _deps.focusState.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _deps.catalogState.isLoading ? null : _deps.refreshFiles,
            tooltip: 'Refresh',
            iconSize: actionIconSize,
            padding: actionIconPadding,
            constraints: actionIconConstraints,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_deps.selectionState.isSelectionMode) _deps.buildSelectionBar(),
          // View mode dropdown (only shown when inside folders)
          if (showViewModeDropdown && !_deps.viewState.isInVirtualFolder)
            _deps.buildViewModeDropdown(),
          if (_deps.searchState.isSearchActive && showSearch)
            _deps.buildSearchBar(),
          Expanded(
            child: _deps.searchState.isSearchActive
                ? _deps.buildSearchResults()
                : FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: RefreshIndicator(
                      onRefresh: _deps.refreshFiles,
                      // Folder navigation clears _files, so a fetch with
                      // nothing to show gets the shimmer skeleton;
                      // pull-to-refresh keeps its items and skips it.
                      child:
                          _deps.catalogState.isLoading &&
                              _deps.catalogState.files.isEmpty
                          ? const CloudRowSkeletonList()
                          : _deps.catalogState.files.isEmpty
                          ? _deps.buildEmpty()
                          : _deps.buildFileList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Pushed from the Cloud hub to browse (no folder target) — the root has no
  /// folder-up Back, so the AppBar offers a Back-to-hub instead.
  bool get isBrowsePush =>
      _deps.isPushedRoute() && _deps.initialFolderId() == null;
}
