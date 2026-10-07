import 'dart:async';

import 'package:debrify/features/premiumize_files/models/premiumize_view.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';
import 'premiumize_navigation_state.dart';
import 'premiumize_search_state.dart';
import 'premiumize_selection_state.dart';
import 'premiumize_view_state.dart';

typedef PremiumizeRootLayoutDeps = ({
  bool Function() isPushedRoute,
  String? Function() initialFolderId,
  bool Function() isAtRoot,
  PremiumizeCatalogState catalogState,
  Widget Function() buildNotEnabled,
  Widget Function() buildError,
  PremiumizeViewState viewState,
  PremiumizeNavigationState navigationState,
  PremiumizeFocusState focusState,
  bool Function() handleBackNavigation,
  bool Function() selectSourceMode,
  PremiumizeSearchState searchState,
  PremiumizeSelectionState selectionState,
  void Function() toggleSelectionMode,
  void Function() toggleSearch,
  Future<void> Function() showAddLinkDialog,
  Future<void> Function() refresh,
  Widget Function() buildViewSelector,
  Widget Function() buildSelectionBar,
  Widget Function() buildViewModeDropdown,
  Widget Function() buildSearchBar,
  Widget Function() buildSearchResults,
  Widget Function() buildTransfersList,
  Widget Function() buildEmpty,
  Widget Function() buildFileList,
});

class PremiumizeRootLayout {
  PremiumizeRootLayout(this._deps);
  final PremiumizeRootLayoutDeps _deps;

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Pushed from the Cloud hub to browse (no folder target) — the root has no
  /// folder-up Back, so the AppBar offers a Back-to-hub instead.
  bool get isBrowsePush =>
      _deps.isPushedRoute() && _deps.initialFolderId() == null;

  Widget build(BuildContext context) {
    if (_deps.isPushedRoute() &&
        _deps.isAtRoot() &&
        _deps.catalogState.initialLoad) {
      return CloudScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Opening folder...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_deps.catalogState.premiumizeEnabled) return _deps.buildNotEnabled();
    if (_deps.catalogState.initialLoad &&
        (_deps.catalogState.isLoading ||
            _deps.catalogState.isLoadingTransfers)) {
      return const CloudScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_deps.catalogState.errorMessage.isNotEmpty &&
        _deps.catalogState.items.isEmpty &&
        _deps.catalogState.transfers.isEmpty) {
      return _deps.buildError();
    }

    final showViewModeDropdown =
        _deps.viewState.selectedView == PremiumizeView.files &&
        _deps.navigationState.navigationStack.isNotEmpty;
    // Search is available in the files view everywhere: at root it runs a
    // server-side cloud search; inside a folder it filters locally.
    final showSearch = _deps.viewState.selectedView == PremiumizeView.files;

    final bool isCompact = MediaQuery.sizeOf(context).width < 500;
    final double iconSize = isCompact ? 20 : 24;
    final EdgeInsets iconPadding = isCompact
        ? const EdgeInsets.all(6)
        : const EdgeInsets.all(8);
    final BoxConstraints iconConstraints = isCompact
        ? const BoxConstraints(minWidth: 36, minHeight: 36)
        : const BoxConstraints(minWidth: 48, minHeight: 48);

    return CloudScaffold(
      appBar: AppBar(
        leading: (!_deps.isAtRoot())
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
                  onPressed: _deps.handleBackNavigation,
                  tooltip: 'Back',
                ),
              )
            // At the browse root (pushed from the Cloud hub with no folder
            // target) there's no folder-up back — offer a Back-to-hub instead.
            : (isBrowsePush
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
        title: Text(
          _deps.selectSourceMode()
              ? 'Select Premiumize Source'
              : (_deps.isAtRoot()
                    ? 'Premiumize'
                    : _deps.navigationState.currentFolderName),
        ),
        actions: [
          // Keep the button mounted while a navigation fetch runs (_items is
          // cleared then) so the AppBar doesn't flicker and TV focus parked
          // on it isn't dropped.
          if (_deps.viewState.selectedView == PremiumizeView.files &&
              (_deps.catalogState.items.isNotEmpty ||
                  _deps.catalogState.isLoading) &&
              !_deps.searchState.isSearchActive &&
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
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _deps.focusState.searchButtonFocusNode,
              icon: Icon(
                _deps.searchState.isSearchActive ? Icons.close : Icons.search,
              ),
              onPressed: _deps.toggleSearch,
              tooltip: _deps.searchState.isSearchActive
                  ? 'Close search'
                  : 'Search files',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (!_deps.selectSourceMode())
            IconButton(
              focusNode: _deps.focusState.addLinkButtonFocusNode,
              icon: const Icon(Icons.add_link),
              onPressed: _deps.catalogState.isLoading
                  ? null
                  : _deps.showAddLinkDialog,
              tooltip: 'Add to Premiumize',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _deps.focusState.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed:
                (_deps.catalogState.isLoading ||
                    _deps.catalogState.isLoadingTransfers)
                ? null
                : _deps.refresh,
            tooltip: 'Refresh',
            iconSize: iconSize,
            padding: iconPadding,
            constraints: iconConstraints,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_deps.isAtRoot() &&
              !_deps.searchState.isSearchActive &&
              !_deps.selectSourceMode())
            _deps.buildViewSelector(),
          if (_deps.selectionState.isSelectionMode) _deps.buildSelectionBar(),
          if (showViewModeDropdown) _deps.buildViewModeDropdown(),
          if (_deps.searchState.isSearchActive && showSearch)
            _deps.buildSearchBar(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: RefreshIndicator(
                onRefresh: _deps.refresh,
                child: buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBody() {
    if (_deps.searchState.isSearchActive) return _deps.buildSearchResults();
    if (_deps.viewState.selectedView == PremiumizeView.transfers) {
      return _deps.buildTransfersList();
    }
    // Folder navigation clears _items, so a fetch with nothing to show gets
    // the shimmer skeleton. Pull-to-refresh keeps its items and never hits
    // this branch — the RefreshIndicator spinner covers it.
    if (_deps.catalogState.isLoading && _deps.catalogState.items.isEmpty) {
      return const CloudRowSkeletonList();
    }
    if (_deps.catalogState.items.isEmpty) return _deps.buildEmpty();
    return _deps.buildFileList();
  }
}
