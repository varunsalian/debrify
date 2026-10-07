import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_composition.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_catalog_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_navigation_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_view_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_focus_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_selection_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_search_state.dart';
import 'package:debrify/features/premiumize_files/presentation/legacy_premiumize/premiumize_link_state.dart';
import 'package:debrify/features/premiumize_files/models/folder_view_mode.dart';
import 'package:debrify/features/premiumize_files/models/premiumize_view.dart';
import 'package:debrify/features/premiumize_files/application/premiumize_sort_policy.dart';
import 'package:debrify/features/premiumize_files/application/premiumize_playlist_titles.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// re-exports PlaylistEntry
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';
import '../../models/premiumize_folder_item.dart';
import '../../models/premiumize_transfer.dart';
import '../../utils/formatters.dart';
import '../../widgets/cloud/cloud_file_row.dart';
import '../../widgets/cloud/cloud_row_skeleton.dart';
import '../../widgets/cloud/cloud_segmented_tabs.dart';
import '../../widgets/cloud/cloud_theme.dart';
import '../../widgets/tv_text_field.dart';
import '../debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';

/// Cloud-library browser for Premiumize, mirroring the Torbox/PikPak navigation
/// pages. Premiumize's cloud is a real server-side folder hierarchy, so this
/// browses folders by id (like PikPak) and additionally exposes a Transfers
/// view (Premiumize's queued/running magnet transfers).
class PremiumizeFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final String? initialSearchQuery;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation pops the route instead of switching tabs.
  final bool isPushedRoute;

  const PremiumizeFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
    this.initialSearchQuery,
    this.isPushedRoute = false,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<PremiumizeFilesScreen> createState() => _PremiumizeFilesScreenState();
}

class _PremiumizeFilesScreenState extends State<PremiumizeFilesScreen> {
  PremiumizeSections? _sectionCache;
  PremiumizeSections get _sections =>
      _sectionCache ??= createPremiumizeSections(
        (
          context: () => context,
          mounted: () => mounted,
          setState: setState,
          initialFolderId: () => widget.initialFolderId,
          initialFolderName: () => widget.initialFolderName,
          initialSearchQuery: () => widget.initialSearchQuery,
          isPushedRoute: () => widget.isPushedRoute,
          selectSourceMode: () => widget.selectSourceMode,
          onSourceSelected: () => widget.onSourceSelected,
        ),
        (
          catalogState: _catalog,
          navigationState: _nav,
          viewState: _view,
          focusState: _focus,
          selectionState: _selection,
          searchState: _search,
          linkState: _link,
        ),
      );

  final _catalog = PremiumizeCatalogState();
  final _nav = PremiumizeNavigationState();
  final _view = PremiumizeViewState();
  final _focus = PremiumizeFocusState();
  final _selection = PremiumizeSelectionState();
  final _search = PremiumizeSearchState();
  final _link = PremiumizeLinkState();

  // Premiumize tab index in main.dart's page list (for TV focus + back handler).
  static const int _tabIndex = 11;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('premiumize_files');
    _sections.catalogLoading.loadSettings();

    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.registerTabBackHandler(
        'premiumize',
        _sections.backNavigation.handleBackNavigation,
      );
      _focus.tvContentFocusHandler = () {
        _focus.shouldFocusOnLoad = true;
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        _tabIndex,
        _focus.tvContentFocusHandler!,
      );
    }
  }

  @override
  void dispose() {
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.unregisterTabBackHandler('premiumize');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex,
          _focus.tvContentFocusHandler!,
        );
      }
    }
    _search.searchDebounce?.cancel();
    _focus.scrollController.dispose();
    _link.linkController.dispose();
    _search.searchController.dispose();
    _focus.refreshButtonFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.retryButtonFocusNode.dispose();
    _focus.settingsButtonFocusNode.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.addLinkButtonFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    _focus.searchFocusNode.dispose();
    _focus.searchButtonFocusNode.dispose();
    _focus.searchClearFocusNode.dispose();
    super.dispose();
  }

  // ── Series helpers (shared shape with PikPak/playlist player) ────────────────

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Pushed from the Cloud hub to browse (no folder target) — the root has no
  /// folder-up Back, so the AppBar offers a Back-to-hub instead.
  bool get _isBrowsePush =>
      widget.isPushedRoute && widget.initialFolderId == null;

  @override
  Widget build(BuildContext context) {
    if (widget.isPushedRoute &&
        _sections.folderNavigation.isAtRoot &&
        _catalog.initialLoad) {
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

    if (!_catalog.premiumizeEnabled) return _buildNotEnabled();
    if (_catalog.initialLoad &&
        (_catalog.isLoading || _catalog.isLoadingTransfers)) {
      return const CloudScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_catalog.errorMessage.isNotEmpty &&
        _catalog.items.isEmpty &&
        _catalog.transfers.isEmpty) {
      return _buildError();
    }

    final showViewModeDropdown =
        _view.selectedView == PremiumizeView.files &&
        _nav.navigationStack.isNotEmpty;
    // Search is available in the files view everywhere: at root it runs a
    // server-side cloud search; inside a folder it filters locally.
    final showSearch = _view.selectedView == PremiumizeView.files;

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
        leading: (!_sections.folderNavigation.isAtRoot)
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
                  focusNode: _focus.backButtonFocusNode,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _sections.backNavigation.handleBackNavigation,
                  tooltip: 'Back',
                ),
              )
            // At the browse root (pushed from the Cloud hub with no folder
            // target) there's no folder-up back — offer a Back-to-hub instead.
            : (_isBrowsePush
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
        title: Text(
          widget.selectSourceMode
              ? 'Select Premiumize Source'
              : (_sections.folderNavigation.isAtRoot
                    ? 'Premiumize'
                    : _nav.currentFolderName),
        ),
        actions: [
          // Keep the button mounted while a navigation fetch runs (_items is
          // cleared then) so the AppBar doesn't flicker and TV focus parked
          // on it isn't dropped.
          if (_view.selectedView == PremiumizeView.files &&
              (_catalog.items.isNotEmpty || _catalog.isLoading) &&
              !_search.isSearchActive &&
              !widget.selectSourceMode)
            IconButton(
              icon: Icon(
                _selection.isSelectionMode
                    ? Icons.close
                    : Icons.checklist_outlined,
              ),
              onPressed: _sections.selectionActions.toggleSelectionMode,
              tooltip: _selection.isSelectionMode
                  ? 'Exit selection'
                  : 'Select items',
              color: _selection.isSelectionMode
                  ? Theme.of(context).colorScheme.error
                  : null,
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _focus.searchButtonFocusNode,
              icon: Icon(_search.isSearchActive ? Icons.close : Icons.search),
              onPressed: _sections.searchActions.toggleSearch,
              tooltip: _search.isSearchActive ? 'Close search' : 'Search files',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (!widget.selectSourceMode)
            IconButton(
              focusNode: _focus.addLinkButtonFocusNode,
              icon: const Icon(Icons.add_link),
              onPressed: _catalog.isLoading
                  ? null
                  : _sections.linkActions.showAddLinkDialog,
              tooltip: 'Add to Premiumize',
              iconSize: iconSize,
              padding: iconPadding,
              constraints: iconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _focus.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: (_catalog.isLoading || _catalog.isLoadingTransfers)
                ? null
                : _sections.catalogLoading.refresh,
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
          if (_sections.folderNavigation.isAtRoot &&
              !_search.isSearchActive &&
              !widget.selectSourceMode)
            _buildViewSelector(),
          if (_selection.isSelectionMode) _buildSelectionBar(),
          if (showViewModeDropdown) _buildViewModeDropdown(),
          if (_search.isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: RefreshIndicator(
                onRefresh: _sections.catalogLoading.refresh,
                child: _buildBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_search.isSearchActive) return _buildSearchResults();
    if (_view.selectedView == PremiumizeView.transfers) {
      return _buildTransfersList();
    }
    // Folder navigation clears _items, so a fetch with nothing to show gets
    // the shimmer skeleton. Pull-to-refresh keeps its items and never hits
    // this branch — the RefreshIndicator spinner covers it.
    if (_catalog.isLoading && _catalog.items.isEmpty) {
      return const CloudRowSkeletonList();
    }
    if (_catalog.items.isEmpty) return _buildEmpty();
    return _buildFileList();
  }

  Widget _buildViewSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: CloudSegmentedTabs<PremiumizeView>(
        segments: const [
          CloudSegment(PremiumizeView.files, 'My Files', Icons.folder_rounded),
          CloudSegment(
            PremiumizeView.transfers,
            'Transfers',
            Icons.swap_vert_rounded,
          ),
        ],
        selected: _view.selectedView,
        onSelected: _sections.catalogLoading.switchView,
      ),
    );
  }

  Widget _buildViewModeDropdown() {
    final theme = Theme.of(context);
    final mode = _sections.viewModes.getCurrentViewMode();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _focus.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<PremiumizeFolderViewMode>(
          focusNode: _focus.viewModeDropdownFocusNode,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == PremiumizeFolderViewMode.raw
                  ? Icons.view_list
                  : Icons.sort_by_alpha,
              color: theme.colorScheme.primary,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: PremiumizeFolderViewMode.raw,
              child: Text('Raw'),
            ),
            DropdownMenuItem(
              value: PremiumizeFolderViewMode.sortedAZ,
              child: Text('Sort (A-Z)'),
            ),
          ],
          onChanged: (value) {
            if (value != null) _sections.viewModes.setViewMode(value);
          },
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selection.selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _sections.selectionActions.toggleSelectAll,
            child: Text(
              _sections.selectionActions.isAllSelected
                  ? 'Deselect All'
                  : 'Select All',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _focus.deleteButtonFocusNode,
            onPressed: count > 0
                ? _sections.deleteActions.handleDeleteSelected
                : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              disabledBackgroundColor: theme.colorScheme.error.withValues(
                alpha: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _search.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _search.searchController,
              focusNode: _focus.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent
              // wrapper): up to the app-bar actions, down into the results,
              // right to the clear button when visible.
              onUpArrow: () => _focus.searchFocusNode.focusInDirection(
                TraversalDirection.up,
              ),
              onDownArrow: () => _focus.searchFocusNode.focusInDirection(
                TraversalDirection.down,
              ),
              onRightArrow: hasText
                  ? () => _focus.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: _sections.folderNavigation.isAtRoot
                    ? 'Search your Premiumize cloud...'
                    : 'Search files...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _sections.searchActions.performSearch,
              onSubmitted: (_) => _focus.searchFocusNode.unfocus(),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _focus.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key)) {
                    setState(() {
                      _search.searchController.clear();
                      _search.searchResults = [];
                    });
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.06),
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            ? Border.all(color: app.core.tx, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _search.searchController.clear();
                            _search.searchResults = [];
                          });
                          _focus.searchFocusNode.requestFocus();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_search.searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          _sections.folderNavigation.isAtRoot
              ? 'Type to search your cloud'
              : 'Type to search files',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_search.isSearching && _search.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_search.searchResults.isEmpty) {
      return const Center(
        child: Text('No results found', style: TextStyle(color: Colors.grey)),
      );
    }
    // Reuse the full file card so search results get the same Open / Play /
    // ⋮ (Download · Add to Playlist · Delete) actions as the main list.
    // autofocusFirst is disabled so results don't steal focus from the search
    // box while the user is typing.
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _search.searchResults.length,
      itemBuilder: (context, index) {
        final item = _search.searchResults[index];
        return KeyedSubtree(
          key: ValueKey('search-${item.id}'),
          child: _buildFileCard(item, index, autofocusFirst: false),
        );
      },
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      controller: _focus.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _catalog.items.length,
      itemBuilder: (context, index) {
        final item = _catalog.items[index];
        return KeyedSubtree(
          key: ValueKey(item.id),
          child: _buildFileCard(item, index),
        );
      },
    );
  }

  Widget _buildFileCard(
    PremiumizeFolderItem item,
    int index, {
    bool autofocusFirst = true,
  }) {
    final isVideo = item.isVideo;
    final date = _sections.dateFormat.formatUnixDate(item.createdAt);
    final metaParts = <String>[
      if (!item.isFolder && item.size > 0) Formatters.formatFileSize(item.size),
      if (date.isNotEmpty) date,
    ];

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: item.isFolder
            ? CloudRowKind.folder
            : isVideo
            ? CloudRowKind.video
            : CloudRowKind.file,
        title: item.name,
        meta: metaParts.isEmpty ? null : metaParts.join(' · '),
        onTap: (item.isFolder || isVideo)
            ? () => _sections.sourceBinding.selectBoundSource(item)
            : null,
        actions: item.isFolder
            ? [
                CloudRowAction(
                  icon: Icons.folder_open_rounded,
                  label: 'Browse folder',
                  onSelected: () =>
                      _sections.folderNavigation.navigateIntoFolder(item),
                ),
              ]
            : const [],
        focusNode: (autofocusFirst && index == 0)
            ? _focus.firstItemFocusNode
            : null,
      );
    }

    // Same action set (labels, icons, conditions) the old Open/Play pills +
    // ⋮ menu offered; the row's tap now carries Open (folders) and Play
    // (videos).
    final actions = <CloudRowAction>[
      // Videos get a ▶ too, even though tapping the row already plays them —
      // folder rows have one, and a video row without it reads as unplayable.
      if (item.isFolder || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (item.isFolder) {
              _sections.folderPlayback.playFolder(item);
            } else {
              _sections.filePlayback.playFile(item);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download',
        showInStrip: true,
        onSelected: () {
          if (item.isFolder) {
            _sections.folderDownload.downloadFolder(item);
          } else {
            _sections.fileDownload.downloadFile(item);
          }
        },
      ),
      if (item.isFolder || isVideo)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _sections.playlistActions.addToPlaylist(item),
        ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _sections.deleteActions.showDeleteDialog(item),
      ),
    ];

    return CloudFileRow(
      kind: item.isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: item.name,
      meta: metaParts.isEmpty ? null : metaParts.join(' · '),
      onTap: item.isFolder
          ? () => _sections.folderNavigation.navigateIntoFolder(item)
          : isVideo
          ? () => _sections.filePlayback.playFile(item)
          : null,
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedIds.contains(item.id),
      onToggleSelected: () =>
          _sections.selectionActions.toggleSelection(item.id),
      focusNode: (autofocusFirst && index == 0)
          ? _focus.firstItemFocusNode
          : null,
    );
  }

  Widget _buildTransfersList() {
    if (_catalog.isLoadingTransfers && _catalog.transfers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalog.transfers.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Transfers',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Magnets you add appear here while they download.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final app = AppThemeScope.of(context);
    final hasFinished = _catalog.transfers.any((t) => t.isFinished);
    return Column(
      children: [
        if (hasFinished)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextButton.icon(
                onPressed: _sections.transferActions.clearFinishedTransfers,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Clear finished'),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _catalog.transfers.length,
            itemBuilder: (context, index) =>
                _buildTransferCard(_catalog.transfers[index], app),
          ),
        ),
      ],
    );
  }

  Widget _buildTransferCard(PremiumizeTransfer transfer, AppTheme app) {
    Color statusColor;
    IconData statusIcon;
    if (transfer.isFinished) {
      statusColor = const Color(0xFF22C55E);
      statusIcon = Icons.check_circle_outline;
    } else if (transfer.isError) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.error_outline;
    } else {
      statusColor = const Color(0xFFFB923C);
      statusIcon = Icons.downloading_rounded;
    }

    return TvFocusScrollWrapper(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.05),
          borderRadius: app.shape.br(12),
          border: Border.all(color: app.fade(app.core.tx, 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    transfer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: 'Delete transfer',
                  onPressed: () =>
                      _sections.transferActions.deleteTransfer(transfer),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (transfer.isRunning) ...[
              ClipRRect(
                borderRadius: app.shape.br(4),
                child: LinearProgressIndicator(
                  value: transfer.progress > 0 ? transfer.progress : null,
                  minHeight: 5,
                  backgroundColor: app.fade(app.core.tx, 0.08),
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              transfer.message ??
                  (transfer.isFinished
                      ? 'Finished'
                      : transfer.isError
                      ? 'Error'
                      : '${transfer.progressPercent}%'),
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isInFolder = !_sections.folderNavigation.isAtRoot;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 24),
                Text(
                  isInFolder ? 'Folder is Empty' : 'No Files Yet',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  isInFolder
                      ? 'This folder doesn\'t contain any files or subfolders.'
                      : 'Add torrents from search or with the + button to see them here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotEnabled() {
    return CloudScaffold(
      appBar: AppBar(title: const Text('Premiumize')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 24),
                Text(
                  'Premiumize Not Configured',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add your Premiumize API key in Settings to view and manage your cloud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () => _sections.feedback.showSnackBar(
                    'Open Settings > Premiumize to configure',
                    isError: false,
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return CloudScaffold(
      appBar: AppBar(title: const Text('Premiumize')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 24),
                Text(
                  'Failed to Load',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _catalog.errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.retryButtonFocusNode,
                  autofocus: true,
                  onPressed: _sections.catalogLoading.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Original-code characterization seam: fresh state and real action tear-offs.
@visibleForTesting
Map<String, Object?> premiumizeFilesTestAccess(
  State<PremiumizeFilesScreen> state,
) {
  final s = state as _PremiumizeFilesScreenState;
  return {
    'scrollController': s._focus.scrollController,
    'apiKey': s._catalog.apiKey,
    'premiumizeEnabled': s._catalog.premiumizeEnabled,
    'isLoading': s._catalog.isLoading,
    'initialLoad': s._catalog.initialLoad,
    'errorMessage': s._catalog.errorMessage,
    'selectedView': s._view.selectedView,
    'items': s._catalog.items,
    'transfers': s._catalog.transfers,
    'isLoadingTransfers': s._catalog.isLoadingTransfers,
    'currentFolderId': s._nav.currentFolderId,
    'currentFolderName': s._nav.currentFolderName,
    'navigationStack': s._nav.navigationStack,
    'folderViewModes': s._view.folderViewModes,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'linkController': s._link.linkController,
    'isAddingLink': s._link.isAddingLink,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedIds': s._selection.selectedIds,
    'isAllSelected': s._sections.selectionActions.isAllSelected,
    'isSearchActive': s._search.isSearchActive,
    'isSearching': s._search.isSearching,
    'searchDebounce': s._search.searchDebounce,
    'searchController': s._search.searchController,
    'searchResults': s._search.searchResults,
    'refreshButtonFocusNode': s._focus.refreshButtonFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'retryButtonFocusNode': s._focus.retryButtonFocusNode,
    'settingsButtonFocusNode': s._focus.settingsButtonFocusNode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'addLinkButtonFocusNode': s._focus.addLinkButtonFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'searchFocusNode': s._focus.searchFocusNode,
    'searchButtonFocusNode': s._focus.searchButtonFocusNode,
    'searchClearFocusNode': s._focus.searchClearFocusNode,
    'isAtRoot': s._sections.folderNavigation.isAtRoot,
    'loadSettings': s._sections.catalogLoading.loadSettings,
    'loadFolder': s._sections.catalogLoading.loadFolder,
    'loadTransfers': s._sections.catalogLoading.loadTransfers,
    'refresh': s._sections.catalogLoading.refresh,
    'switchView': s._sections.catalogLoading.switchView,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'setViewMode': s._sections.viewModes.setViewMode,
    'applyViewMode': s._sections.viewModes.applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'toggleSearch': s._sections.searchActions.toggleSearch,
    'performSearch': s._sections.searchActions.performSearch,
    'runCloudSearch': s._sections.searchActions.runCloudSearch,
    'selectBoundSource': s._sections.sourceBinding.selectBoundSource,
    'playFile': s._sections.filePlayback.playFile,
    'playFolder': s._sections.folderPlayback.playFolder,
    'playPremiumizeVideos': s._sections.folderPlayback.playPremiumizeVideos,
    'downloadFile': s._sections.fileDownload.downloadFile,
    'downloadFolder': s._sections.folderDownload.downloadFolder,
    'downloadSelectedFiles': s._sections.folderDownload.downloadSelectedFiles,
    'addToPlaylist': s._sections.playlistActions.addToPlaylist,
    'addFileToPlaylist': s._sections.playlistActions.addFileToPlaylist,
    'addFolderToPlaylist': s._sections.playlistActions.addFolderToPlaylist,
    'showDeleteDialog': s._sections.deleteActions.showDeleteDialog,
    'handleDeleteSelected': s._sections.deleteActions.handleDeleteSelected,
    'executeDelete': s._sections.deleteActions.executeDelete,
    'deleteTransfer': s._sections.transferActions.deleteTransfer,
    'clearFinishedTransfers':
        s._sections.transferActions.clearFinishedTransfers,
    'showAddLinkDialog': s._sections.linkActions.showAddLinkDialog,
    'autoPasteLink': s._sections.linkActions.autoPasteLink,
    'addLink': s._sections.linkActions.addLink,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleSelection': s._sections.selectionActions.toggleSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'showLoadingDialog': s._sections.feedback.showLoadingDialog,
    'dismissDialog': s._sections.feedback.dismissDialog,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'showSnackBar': s._sections.feedback.showSnackBar,
    'formatUnixDate': s._sections.dateFormat.formatUnixDate,
    'formatPlaylistTitle': formatPlaylistTitle,
    'composeEntryTitle': composeEntryTitle,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'isBrowsePush': s._isBrowsePush,
    'rawMode': PremiumizeFolderViewMode.raw,
    'sortedMode': PremiumizeFolderViewMode.sortedAZ,
    'filesView': PremiumizeView.files,
    'transfersView': PremiumizeView.transfers,
  };
}
