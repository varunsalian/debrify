import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/features/pikpak_files/models/pikpak_search_result.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_sort_policy.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_playlist_titles.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_link_policy.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/cloud/cloud_file_row.dart';
import '../../widgets/cloud/cloud_row_skeleton.dart';
import '../../widgets/cloud/cloud_theme.dart';
import '../../widgets/tv_text_field.dart';

class PikPakFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;

  const PikPakFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
    this.isPushedRoute = false,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<PikPakFilesScreen> createState() => _PikPakFilesScreenState();
}

class _PikPakFilesScreenState extends State<PikPakFilesScreen> {
  final _catalog = PikpakCatalogState();
  final _nav = PikpakNavigationState();
  final _view = PikpakViewState();
  final _focus = PikpakFocusState();
  final _selection = PikpakSelectionState();
  final _search = PikpakSearchState();
  final _link = PikpakLinkState();
  PikpakSections? _sectionCache;
  PikpakSections get _sections => _sectionCache ??= createPikpakSections(
    (
      setState: setState,
      mounted: () => mounted,
      context: () => context,
      initialFolderId: () => widget.initialFolderId,
      initialFolderName: () => widget.initialFolderName,
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

  // TV content focus handler (stored for proper unregistration)

  // Add link state

  // Pagination state

  // Folder navigation state

  // View mode state (per-folder persistence during session)

  // Virtual folder navigation for Series Arrange mode

  // e.g., "Season 1"
  // Files in virtual Season

  // Cache for recursive file listings (avoid repeated API calls)

  // Focus nodes for TV/DPAD navigation

  // Flag to focus first item after data loads (set by TV content focus handler)

  // Multi-select state

  // Search state (for folder browsing mode)

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('pikpak_files');
    _focus.scrollController.addListener(_sections.catalogLoading.onScroll);
    _sections.catalogLoading.loadSettings();

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
      // Set up timeout - only when DEEP-LINKED into a specific folder
      // (initialFolderId). Browsing from the Cloud hub has no target, so the
      // root is the resting state — no spurious auto-close.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted &&
            widget.isPushedRoute &&
            widget.initialFolderId != null &&
            _nav.currentFolderId == null) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open folder. Please try again.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      });
    } else {
      MainPageBridge.registerTabBackHandler(
        'pikpak',
        _sections.backNavigation.handleBackNavigation,
      );
      // Register TV sidebar focus handler (tab index 6 = PikPak)
      _focus.tvContentFocusHandler = () {
        // Set flag to focus after data loads
        _focus.shouldFocusOnLoad = true;
        // Try to focus now in case data is already loaded
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        6,
        _focus.tvContentFocusHandler!,
      );
    }
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.unregisterTabBackHandler('pikpak');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          6,
          _focus.tvContentFocusHandler!,
        );
      }
    }

    _focus.scrollController.dispose();
    _link.linkController.dispose();
    _focus.refreshButtonFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.retryButtonFocusNode.dispose();
    _focus.settingsButtonFocusNode.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.addLinkButtonFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _search.searchController.dispose();
    _search.searchFocusNode.dispose();
    _search.searchButtonFocusNode.dispose();
    _search.searchClearFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    super.dispose();
  }

  // --- Multi-select helpers ---

  // ========== VIEW MODE TRANSFORMATION METHODS ==========

  /// Build the view mode dropdown (shown below AppBar when inside folders)
  Widget _buildViewModeDropdown() {
    final theme = Theme.of(context);
    final mode = _sections.viewModes.getCurrentViewMode();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Navigate to back button on up arrow
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _focus.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<FolderViewMode>(
          focusNode: _focus.viewModeDropdownFocusNode,
          autofocus: true,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == FolderViewMode.raw
                  ? Icons.view_list
                  : mode == FolderViewMode.sortedAZ
                  ? Icons.sort_by_alpha
                  : Icons.video_library,
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
            DropdownMenuItem(value: FolderViewMode.raw, child: Text('Raw')),
            DropdownMenuItem(
              value: FolderViewMode.sortedAZ,
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

  // ============ Search Methods ============

  /// Build the search bar widget
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
              focusNode: _search.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _search.searchFocusNode.unfocus(),
              onDownArrow: () => _search.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _search.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search files...',
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
              onSubmitted: (_) => _search.searchFocusNode.unfocus(),
            ),
          ),
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _search.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    setState(() {
                      _search.searchController.clear();
                      _search.searchResults.clear();
                    });
                    _search.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _search.searchFocusNode.requestFocus();
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
                            _search.searchResults.clear();
                          });
                          _search.searchFocusNode.requestFocus();
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

  /// Build search results list
  Widget _buildSearchResults() {
    if (_search.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search files',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_search.searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _search.searchResults.length,
      itemBuilder: (context, index) {
        final result = _search.searchResults[index];
        return _buildSearchResultCard(result);
      },
    );
  }

  /// Build a card for a search result
  Widget _buildSearchResultCard(PikPakSearchResult result) {
    final file = result.file;
    final name = file['name'] as String? ?? 'Unknown';
    final size = file['size'] as String? ?? '0';

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: CloudRowKind.video,
        title: name,
        meta: result.path.isEmpty
            ? Formatters.formatFileSize(int.tryParse(size) ?? 0)
            : result.path,
        onTap: () => _sections.sourceBinding.selectBoundSource(file),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _sections.filePlayback.playFile(file),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.blue,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.path,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      Text(
                        Formatters.formatFileSize(int.tryParse(size) ?? 0),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pushed from the Cloud hub to browse (no folder target) — the root has no
  /// folder-up Back, so the AppBar offers a Back-to-hub instead.
  bool get _isBrowsePush =>
      widget.isPushedRoute && widget.initialFolderId == null;

  @override
  Widget build(BuildContext context) {
    // When DEEP-LINKED into a specific folder (pushed WITH a target) and still
    // at root, show the loading state. Browsing from the Cloud hub has no target
    // (and non-restricted accounts stay at a null root folder), so don't gate the
    // real content behind a spinner.
    if (widget.isPushedRoute &&
        widget.initialFolderId != null &&
        _nav.currentFolderId == null) {
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

    if (!_catalog.pikpakEnabled) {
      return _buildNotEnabled();
    }

    if (_catalog.initialLoad && _catalog.isLoading) {
      return const CloudScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_catalog.errorMessage.isNotEmpty) {
      return _buildError();
    }

    // Check if we should show the view mode dropdown
    // Only show when navigated at least one level deep (inside a folder)
    final showViewModeDropdown =
        _nav.navigationStack.isNotEmpty || _view.isInVirtualFolder;
    final currentMode = _sections.viewModes.getCurrentViewMode();
    final showSearch =
        showViewModeDropdown &&
        currentMode != FolderViewMode.seriesArrange &&
        !_view.isInVirtualFolder;

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
            (_nav.currentFolderId != null && !_nav.isAtRestrictedRoot) ||
                _view.isInVirtualFolder
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
                  onPressed: () =>
                      _sections.backNavigation.handleBackNavigation(),
                  tooltip: 'Back',
                ),
              )
            // At the browse root (opened from the Cloud hub with no folder
            // target) there's no folder-up back — offer a Back-to-hub instead.
            : (_isBrowsePush
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
              _view.isInVirtualFolder
                  ? _view.virtualFolderName ?? 'Virtual Folder'
                  : widget.selectSourceMode
                  ? 'Select PikPak Source'
                  : _nav.currentFolderName,
            ),
            if (_nav.restrictedFolderId != null && !_view.isInVirtualFolder)
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
          if ((_catalog.files.isNotEmpty || _catalog.isLoading) &&
              !_view.isInVirtualFolder &&
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
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _search.searchButtonFocusNode,
              icon: Icon(_search.isSearchActive ? Icons.close : Icons.search),
              onPressed: _sections.searchActions.toggleSearch,
              tooltip: _search.isSearchActive ? 'Close search' : 'Search files',
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (!widget.selectSourceMode)
            IconButton(
              focusNode: _focus.addLinkButtonFocusNode,
              icon: const Icon(Icons.add_link),
              onPressed: _catalog.isLoading
                  ? null
                  : _sections.linkActions.showAddLinkDialog,
              tooltip: 'Add Link',
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _focus.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _catalog.isLoading
                ? null
                : _sections.feedback.refreshFiles,
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
          if (_selection.isSelectionMode) _buildSelectionBar(),
          // View mode dropdown (only shown when inside folders)
          if (showViewModeDropdown && !_view.isInVirtualFolder)
            _buildViewModeDropdown(),
          if (_search.isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: _search.isSearchActive
                ? _buildSearchResults()
                : FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: RefreshIndicator(
                      onRefresh: _sections.feedback.refreshFiles,
                      // Folder navigation clears _files, so a fetch with
                      // nothing to show gets the shimmer skeleton;
                      // pull-to-refresh keeps its items and skips it.
                      child: _catalog.isLoading && _catalog.files.isEmpty
                          ? const CloudRowSkeletonList()
                          : _catalog.files.isEmpty
                          ? _buildEmpty()
                          : _buildFileList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotEnabled() {
    final app = AppThemeScope.of(context);
    return CloudScaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
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
                  'PikPak Not Configured',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Configure your PikPak account in Settings to view and manage files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () {
                    // TODO: Navigate to settings
                    _sections.feedback.showSnackBar(
                      'Open Settings > PikPak to configure',
                      isError: false,
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                  style: FilledButton.styleFrom().copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: app.core.tx, width: 3);
                      }
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final app = AppThemeScope.of(context);
    return CloudScaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
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
                  'Failed to Load Files',
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
                  onPressed: _sections.feedback.refreshFiles,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom().copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: app.core.tx, width: 3);
                      }
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isInFolder = _nav.currentFolderId != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
                  : 'Add torrents from the search screen to see them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final app = AppThemeScope.of(context);
    final theme = Theme.of(context);
    final count = _selection.selectedFileIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: app.shape.br(12),
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
            style:
                FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  disabledBackgroundColor: theme.colorScheme.error.withValues(
                    alpha: 0.3,
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: app.core.tx, width: 3);
                    }
                    return null;
                  }),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    // Add 1 to item count for loading indicator when loading more
    final itemCount =
        _catalog.files.length +
        (_catalog.isLoadingMore || _catalog.hasMore ? 1 : 0);

    return ListView.builder(
      controller: _focus.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Show loading indicator at the end
        if (index >= _catalog.files.length) {
          return _buildLoadingIndicator();
        }
        final file = _catalog.files[index];
        return KeyedSubtree(
          key: ValueKey(file['id'] ?? index),
          child: _buildFileCard(file, index),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    if (_catalog.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Show a subtle hint that more can be loaded
    if (_catalog.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Scroll for more',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFileCard(Map<String, dynamic> file, int index) {
    final name = file['name']?.toString() ?? 'Unknown';
    final size = file['size'];
    final mimeType = file['mime_type'] ?? '';
    final kind = file['kind'] ?? '';
    final phase = file['phase'] ?? '';
    final createdTime = file['created_time'] ?? '';
    final fileId = file['id'] as String?;

    final isFolder = kind == 'drive#folder';
    final isVirtualFolder = kind == 'virtual#season'; // Virtual Season folder
    final isVideo =
        mimeType.startsWith('video/') || FileUtils.isVideoFile(name);
    final isComplete = phase == 'PHASE_TYPE_COMPLETE';

    final date = _formatDate(createdTime);
    final metaParts = <String>[
      if (size != null)
        Formatters.formatFileSize(int.tryParse(size.toString()) ?? 0),
      if (date.isNotEmpty) date,
    ];

    if (widget.selectSourceMode) {
      final selectable =
          !isVirtualFolder && (isFolder || (isVideo && isComplete));
      return CloudFileRow(
        kind: isVirtualFolder
            ? CloudRowKind.season
            : isFolder
            ? CloudRowKind.folder
            : isVideo
            ? CloudRowKind.video
            : CloudRowKind.file,
        title: name,
        meta: metaParts.isEmpty ? null : metaParts.join(' · '),
        extra: (!isComplete && !isVirtualFolder)
            ? Text(
                'Still downloading',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 12.5),
              )
            : null,
        onTap: selectable
            ? () => _sections.sourceBinding.selectBoundSource(file)
            : null,
        actions: isFolder
            ? [
                CloudRowAction(
                  icon: Icons.folder_open_rounded,
                  label: 'Browse folder',
                  onSelected: () => _sections.folderNavigation
                      .navigateIntoFolder(file['id'], name),
                ),
              ]
            : const [],
        focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old pills + ⋮ menu offered.
    // Virtual Season folders keep their special shape: Open only (via tap),
    // no menu, not selectable.
    final actions = <CloudRowAction>[
      if (!isVirtualFolder) ...[
        if (isFolder || (isVideo && isComplete))
          CloudRowAction(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            showInStrip: true,
            onSelected: () {
              if (isFolder) {
                _sections.folderPlayback.playFolder(file);
              } else {
                _sections.filePlayback.playFile(file);
              }
            },
          ),
        CloudRowAction(
          icon: Icons.download,
          label: 'Download',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _sections.folderDownload.downloadFolder(file);
            } else {
              _sections.fileDownload.downloadFile(file);
            }
          },
        ),
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _sections.playlistActions.handleAddToPlaylist(file),
        ),
        CloudRowAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onSelected: () => _sections.deleteActions.showDeleteDialog(file),
        ),
      ],
    ];

    return CloudFileRow(
      kind: isVirtualFolder
          ? CloudRowKind.season
          : isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: name,
      meta: metaParts.isEmpty ? null : metaParts.join(' · '),
      // Virtual season rows are client-synthesized and carry no 'phase', so
      // without the !isVirtualFolder gate they'd show a perpetual spinner.
      extra: (!isComplete && !isVirtualFolder && !_selection.isSelectionMode)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Downloading...',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            )
          : null,
      onTap: isVirtualFolder
          ? () => _sections.folderNavigation.navigateIntoVirtualFolder(file)
          : isFolder
          ? () =>
                _sections.folderNavigation.navigateIntoFolder(file['id'], name)
          : (isVideo && isComplete)
          ? () => _sections.filePlayback.playFile(file)
          : null,
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: fileId != null && _selection.selectedFileIds.contains(fileId),
      selectable: fileId != null && !isVirtualFolder,
      onToggleSelected: fileId != null
          ? () => _sections.selectionActions.toggleFileSelection(fileId)
          : null,
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }

  // ============================================================================
  // Add Link Dialog
  // ============================================================================
}

/// Original-code characterization seam: fresh state and real action tear-offs.
@visibleForTesting
Map<String, Object?> pikpakFilesTestAccess(State<PikPakFilesScreen> state) {
  final s = state as _PikPakFilesScreenState;
  return {
    'scrollController': s._focus.scrollController,
    'files': s._catalog.files,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'isLoading': s._catalog.isLoading,
    'initialLoad': s._catalog.initialLoad,
    'errorMessage': s._catalog.errorMessage,
    'pikpakEnabled': s._catalog.pikpakEnabled,
    'showVideosOnly': s._catalog.showVideosOnly,
    'ignoreSmallVideos': s._catalog.ignoreSmallVideos,
    'linkController': s._link.linkController,
    'isAddingLink': s._link.isAddingLink,
    'nextPageToken': s._catalog.nextPageToken,
    'hasMore': s._catalog.hasMore,
    'isLoadingMore': s._catalog.isLoadingMore,
    'currentFolderId': s._nav.currentFolderId,
    'currentFolderName': s._nav.currentFolderName,
    'navigationStack': s._nav.navigationStack,
    'restrictedFolderId': s._nav.restrictedFolderId,
    'restrictedFolderName': s._nav.restrictedFolderName,
    'isAtRestrictedRoot': s._nav.isAtRestrictedRoot,
    'folderViewModes': s._view.folderViewModes,
    'isInVirtualFolder': s._view.isInVirtualFolder,
    'virtualFolderName': s._view.virtualFolderName,
    'virtualFolderFiles': s._view.virtualFolderFiles,
    'recursiveFileCache': s._view.recursiveFileCache,
    'refreshButtonFocusNode': s._focus.refreshButtonFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'retryButtonFocusNode': s._focus.retryButtonFocusNode,
    'settingsButtonFocusNode': s._focus.settingsButtonFocusNode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'addLinkButtonFocusNode': s._focus.addLinkButtonFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedFileIds': s._selection.selectedFileIds,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'isSearchActive': s._search.isSearchActive,
    'searchController': s._search.searchController,
    'searchFocusNode': s._search.searchFocusNode,
    'searchButtonFocusNode': s._search.searchButtonFocusNode,
    'searchClearFocusNode': s._search.searchClearFocusNode,
    'searchResults': s._search.searchResults,
    'selectableFileCount': s._sections.selectionActions.selectableFileCount,
    'isAllSelected': s._sections.selectionActions.isAllSelected,
    'selectBoundSource': s._sections.sourceBinding.selectBoundSource,
    'onScroll': s._sections.catalogLoading.onScroll,
    'resetListScroll': s._sections.catalogLoading.resetListScroll,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'loadSettings': s._sections.catalogLoading.loadSettings,
    'handleRestrictedFolderDeleted':
        s._sections.catalogLoading.handleRestrictedFolderDeleted,
    'loadFiles': s._sections.catalogLoading.loadFiles,
    'loadMoreFiles': s._sections.catalogLoading.loadMoreFiles,
    'filterFiles': s._sections.folderNavigation.filterFiles,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'navigateUpWithVirtual': s._sections.folderNavigation.navigateUpWithVirtual,
    'navigateIntoVirtualFolder':
        s._sections.folderNavigation.navigateIntoVirtualFolder,
    'playFile': s._sections.filePlayback.playFile,
    'downloadFile': s._sections.fileDownload.downloadFile,
    'downloadFolder': s._sections.folderDownload.downloadFolder,
    'downloadSelectedPikPakFiles':
        s._sections.folderDownload.downloadSelectedPikPakFiles,
    'refreshFiles': s._sections.feedback.refreshFiles,
    'showDeleteDialog': s._sections.deleteActions.showDeleteDialog,
    'deleteFile': s._sections.deleteActions.deleteFile,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleFileSelection': s._sections.selectionActions.toggleFileSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'handleDeleteSelected': s._sections.deleteActions.handleDeleteSelected,
    'executeDeleteSelected': s._sections.deleteActions.executeDeleteSelected,
    'showSnackBar': s._sections.feedback.showSnackBar,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'setViewMode': s._sections.viewModes.setViewMode,
    'showFallbackToSorted': s._sections.viewModes.showFallbackToSorted,
    'applyViewMode': s._sections.viewModes.applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySeriesArrangeView': s._sections.viewModes.applySeriesArrangeView,
    'toggleSearch': s._sections.searchActions.toggleSearch,
    'performSearch': s._sections.searchActions.performSearch,
    'isBrowsePush': s._isBrowsePush,
    'formatDate': s._formatDate,
    'playFolder': s._sections.folderPlayback.playFolder,
    'playPikPakVideos': s._sections.folderPlayback.playPikPakVideos,
    'handleAddToPlaylist': s._sections.playlistActions.handleAddToPlaylist,
    'addSingleFileToPlaylist':
        s._sections.playlistActions.addSingleFileToPlaylist,
    'addFolderToPlaylist': s._sections.playlistActions.addFolderToPlaylist,
    'pikpakDisplayName': pikpakDisplayName,
    'formatPikPakPlaylistTitle': formatPikPakPlaylistTitle,
    'combineSeriesAndEpisodeTitle': combineSeriesAndEpisodeTitle,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'showAddLinkDialog': s._sections.linkActions.showAddLinkDialog,
    'autoPasteLink': s._sections.linkActions.autoPasteLink,
    'isValidPikPakLink': isValidPikPakLink,
    'addLink': s._sections.linkActions.addLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
