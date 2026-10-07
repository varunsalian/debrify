import 'dart:async';
import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_sections.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:debrify/widgets/cloud/cloud_theme.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cloud-library browser for AllDebrid. AllDebrid's cloud is a flat list of
/// magnets (each with files), so this is a two-level browser (magnet list →
/// the selected magnet's files), built on the shared cloud widgets
/// (CloudFileRow rows, CloudSegmentedTabs view switcher, CloudScaffold).
class AllDebridFilesScreen extends StatefulWidget {
  final bool isPushedRoute;
  final String? initialSearchQuery;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  const AllDebridFilesScreen({
    super.key,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<AllDebridFilesScreen> createState() => _AllDebridFilesScreenState();
}

class _AllDebridFilesScreenState extends State<AllDebridFilesScreen> {
  AllDebridSections? _sectionCache;
  AllDebridSections get _sections => _sectionCache ??= createAllDebridSections(
    (
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      isPushedRoute: () => widget.isPushedRoute,
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ),
    (
      libraryState: _library,
      navigationState: _navigation,
      searchState: _search,
      focusState: _focus,
      selectionState: _selection,
      feedbackState: _feedback,
    ),
  );

  final _library = AllDebridLibraryState();
  final _navigation = AllDebridNavigationState();
  final _search = AllDebridSearchState();
  final _focus = AllDebridFocusState();
  final _selection = AllDebridSelectionState();
  final _feedback = AllDebridFeedbackState();
  AllDebridFocusState get _f => _focus;
  static const int _tabIndex = 12;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('alldebrid_files');
    final initialQuery = widget.initialSearchQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _search.searchActive = true;
      _search.searchQuery = initialQuery;
      _search.searchController.text = initialQuery;
    }
    if (widget.isPushedRoute) {
      // Pushed as a route (e.g. from the consolidated Cloud hub) — register a
      // pushed-route back handler so hardware/gesture Back navigates up within
      // the screen before popping, matching the other provider screens.
      MainPageBridge.pushRouteBackHandler(
        _sections.navigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.registerTabBackHandler(
        'alldebrid',
        _sections.navigation.handleBackNavigation,
      );
      _f.tvContentFocusHandler = () {
        _f.shouldFocusOnLoad = true;
        _sections.navigation.focusFirstItem();
      };
      MainPageBridge.registerTvContentFocusHandler(
        _tabIndex,
        _f.tvContentFocusHandler!,
      );
    }
    // The "shared web link → open on Web Downloads" deep link works in BOTH tab
    // and pushed (Cloud hub) modes — the Cloud hub always pushes, so gating this
    // on !isPushedRoute would silently drop the feature. Wire the live handler
    // and consume any pending flag regardless of how we were opened.
    MainPageBridge.focusAllDebridWebDownloads =
        _sections.navigation.focusWebDownloads;
    if (MainPageBridge.getAndClearAllDebridFocusWebDownloads()) {
      _navigation.selectedView = AllDebridView.webDownloads;
    }
    _sections.libraryLoading.load();
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      _sections.libraryLoading.loadLinks();
    }
  }

  @override
  void dispose() {
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(
        _sections.navigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.unregisterTabBackHandler('alldebrid');
      if (_f.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          _tabIndex,
          _f.tvContentFocusHandler!,
        );
      }
    }
    if (MainPageBridge.focusAllDebridWebDownloads ==
        _sections.navigation.focusWebDownloads) {
      MainPageBridge.focusAllDebridWebDownloads = null;
    }
    _search.searchController.dispose();
    _f.searchFocusNode.dispose();
    _f.searchClearFocusNode.dispose();
    _search.fileSearchController.dispose();
    _f.fileSearchFocusNode.dispose();
    _f.scrollController.dispose();
    _f.backButtonFocusNode.dispose();
    _f.deleteButtonFocusNode.dispose();
    _f.toolbarSearchFocusNode.dispose();
    _f.firstItemFocusNode.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CloudScaffold(
      appBar: _sections.navigation.isAtRoot
          ? null
          : AppBar(
              leading: IconButton(
                focusNode: _f.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: _sections.navigation.navigateUp,
                tooltip: 'Back',
              ),
              title: Text(_navigation.currentMagnet!.name),
              actions: [
                if (_navigation.currentFiles.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _search.fileSearchActive ? Icons.close : Icons.search,
                    ),
                    onPressed: () {
                      setState(() {
                        _search.fileSearchActive = !_search.fileSearchActive;
                        if (!_search.fileSearchActive) {
                          _search.fileSearchQuery = '';
                          _search.fileSearchController.clear();
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _f.fileSearchFocusNode.requestFocus();
                          });
                        }
                      });
                    },
                    tooltip: 'Search files',
                  ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_sections.navigation.isAtRoot) _buildToolbar(),
          if (_sections.navigation.isAtRoot) _buildViewSelectorBar(),
          if (_sections.navigation.isAtRoot && _search.searchActive)
            _buildSearchBar(),
          if (_sections.navigation.isAtRoot && _selection.selectionMode)
            _buildSelectionBar(),
          if (!_sections.navigation.isAtRoot && _search.fileSearchActive)
            _buildFileSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// Pushed (from the Cloud hub or the openAllDebridFolder deep link) to browse
  /// — the root has no other Back affordance, so show one.
  bool get _isBrowsePush => widget.isPushedRoute;

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);
    final isWeb = _navigation.selectedView == AllDebridView.webDownloads;
    final hasItems = isWeb
        ? _library.links.isNotEmpty
        : _library.magnets.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.05),
            borderRadius: app.shape.br(12),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
          ),
          child: Row(
            children: [
              if (_isBrowsePush) ...[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.arrow_back),
                    color: theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 8),
              ],
              if (widget.selectSourceMode)
                const Text(
                  'Select AllDebrid Source',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              const Spacer(),
              // Selection mode is torrents-only (it bulk-deletes magnets).
              if (!widget.selectSourceMode && !isWeb && hasItems)
                Tooltip(
                  message: _selection.selectionMode
                      ? 'Exit selection'
                      : 'Select items',
                  child: IconButton(
                    onPressed: _sections.selection.toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _selection.selectionMode
                          ? Icons.close
                          : Icons.checklist_outlined,
                    ),
                    color: _selection.selectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (!widget.selectSourceMode && hasItems) ...[
                Tooltip(
                  message: isWeb ? 'Delete all links' : 'Delete all magnets',
                  child: IconButton(
                    onPressed: isWeb
                        ? _sections.deleteActions.confirmDeleteAllLinks
                        : _sections.deleteActions.confirmDeleteAll,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: _search.searchActive
                      ? 'Close search'
                      : (isWeb ? 'Search links' : 'Search magnets'),
                  child: IconButton(
                    focusNode: _f.toolbarSearchFocusNode,
                    onPressed: _sections.search.toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _search.searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _search.searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              if (widget.selectSourceMode && hasItems)
                Tooltip(
                  message: _search.searchActive
                      ? 'Close search'
                      : (isWeb ? 'Search links' : 'Search magnets'),
                  child: IconButton(
                    focusNode: _f.toolbarSearchFocusNode,
                    onPressed: _sections.search.toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _search.searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _search.searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (!widget.selectSourceMode)
                Tooltip(
                  message: isWeb ? 'Add link' : 'Add magnet link',
                  child: IconButton(
                    onPressed: isWeb
                        ? _sections.addActions.showAddLinkDialog
                        : _sections.addActions.showAddMagnetDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.add_circle_outline),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Tooltip(
                message: 'Refresh',
                child: IconButton(
                  onPressed: _sections.navigation.refresh,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.refresh),
                  color: theme.colorScheme.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget _buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<AllDebridView>(
        segments: const [
          CloudSegment(
            AllDebridView.torrents,
            'Torrent Downloads',
            Icons.folder_rounded,
          ),
          CloudSegment(
            AllDebridView.webDownloads,
            'Web Downloads',
            Icons.link_rounded,
          ),
        ],
        selected: _navigation.selectedView,
        onSelected: (value) {
          if (value == _navigation.selectedView) return;
          _sections.selection.exitSelectionMode();
          // Both root lists share _scrollController; reset so the incoming
          // view doesn't inherit the outgoing list's scroll offset.
          if (_f.scrollController.hasClients) _f.scrollController.jumpTo(0);
          setState(() {
            _navigation.selectedView = value;
            _search.searchActive = false;
            _search.searchQuery = '';
            _search.searchController.clear();
          });
          if (value == AllDebridView.webDownloads &&
              !_library.linksLoadedOnce) {
            _sections.libraryLoading.loadLinks();
          }
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selection.selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
            onPressed: _sections.selection.toggleSelectAll,
            child: Text(
              _sections.selection.isAllSelected ? 'Deselect All' : 'Select All',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _f.deleteButtonFocusNode,
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

  /// Shared search-field decoration matching the cloud-screen styling.
  InputDecoration _searchDecoration(String hint) {
    final app = AppThemeScope.of(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
      prefixIcon: Icon(
        Icons.search_rounded,
        color: app.fade(app.core.tx, 0.4),
        size: 20,
      ),
      filled: true,
      fillColor: app.fade(app.core.tx, 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: app.cloud.accent),
      ),
    );
  }

  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _search.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _search.searchController,
              focusNode: _f.searchFocusNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              // D-pad exits (formerly a Focus/onKeyEvent wrapper): up to the
              // toolbar, down into the results, right to the clear button.
              onUpArrow: () => _sections.search.moveFocusTo(
                _f.toolbarSearchFocusNode,
                _f.searchFocusNode,
              ),
              onDownArrow: () => _sections.search.moveFocusTo(
                _f.firstItemFocusNode,
                _f.searchFocusNode,
              ),
              onRightArrow: hasText
                  ? () => _f.searchClearFocusNode.requestFocus()
                  : null,
              onChanged: (v) => setState(() => _search.searchQuery = v),
              onSubmitted: (_) => _f.searchFocusNode.unfocus(),
              decoration: _searchDecoration(
                _navigation.selectedView == AllDebridView.webDownloads
                    ? 'Search your links...'
                    : 'Search your magnets...',
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _f.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key)) {
                    _search.searchController.clear();
                    setState(() => _search.searchQuery = '');
                    _f.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _f.searchFocusNode.requestFocus();
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
                        onPressed: () {
                          _search.searchController.clear();
                          setState(() => _search.searchQuery = '');
                          _f.searchFocusNode.requestFocus();
                        },
                        icon: Icon(
                          Icons.clear_rounded,
                          color: app.fade(app.core.tx, 0.4),
                          size: 18,
                        ),
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

  Widget _buildFileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TvTextField(
        controller: _search.fileSearchController,
        focusNode: _f.fileSearchFocusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        // D-pad exits (formerly a Focus/onKeyEvent wrapper): up to the back
        // button, down into the results.
        onUpArrow: () => _sections.search.moveFocusTo(
          _f.backButtonFocusNode,
          _f.fileSearchFocusNode,
        ),
        onDownArrow: () => _sections.search.moveFocusTo(
          _f.firstItemFocusNode,
          _f.fileSearchFocusNode,
        ),
        onChanged: (v) => setState(() => _search.fileSearchQuery = v),
        onSubmitted: (_) => _f.fileSearchFocusNode.unfocus(),
        decoration: _searchDecoration('Search files...'),
      ),
    );
  }

  Widget _buildBody() {
    final app = AppThemeScope.of(context);
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      return _buildLinksView();
    }
    if (_library.loading) {
      return const CloudRowSkeletonList();
    }
    if (_library.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: app.fade(app.core.tx, 0x62 / 0xFF),
              ),
              const SizedBox(height: 16),
              Text(_library.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sections.libraryLoading.load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_sections.navigation.isAtRoot) {
      return _buildFilesView();
    }
    return _buildMagnetsView();
  }

  Widget _buildMagnetsView() {
    final app = AppThemeScope.of(context);
    final magnets = _sections.search.visibleMagnets;
    if (magnets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _sections.libraryLoading.load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _search.searchQuery.isNotEmpty
                    ? 'No magnets match your search.'
                    : 'Your AllDebrid library is empty.',
                style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _sections.libraryLoading.load,
      child: ListView.builder(
        controller: _f.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: magnets.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(magnets[index].id),
            child: _buildMagnetCard(magnets[index], index),
          );
        },
      ),
    );
  }

  Widget _buildMagnetCard(AllDebridMagnet m, int index) {
    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: m.name.isEmpty ? '(unnamed)' : m.name,
        meta: Formatters.formatFileSize(m.size),
        badges: const [CloudRowBadge('Ready', CloudBadgeKind.ok)],
        onTap: () async {
          if (m.hash.trim().isEmpty) {
            _sections.feedback.snack(
              'This AllDebrid magnet has no infohash to bind.',
              isError: true,
            );
            return;
          }
          await widget.onSourceSelected?.call(
            SeriesSource(
              torrentHash: m.hash,
              torrentName: m.name,
              debridService: 'alldebrid',
              debridTorrentId: m.id,
              boundAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          if (!mounted) return;
          Navigator.of(context).pop();
        },
        focusNode: index == 0 ? _f.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open for ready magnets.
    final actions = <CloudRowAction>[
      if (m.isReady)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _sections.playback.playMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.download,
          label: 'Download to device',
          showInStrip: true,
          onSelected: () => _sections.downloads.downloadMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.folder_open,
          label: 'Open',
          onSelected: () => _sections.navigation.openMagnet(m),
        ),
      if (m.isReady)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _sections.playlistActions.addMagnetToPlaylist(m),
        ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _sections.deleteActions.deleteMagnets([m]),
      ),
    ];

    return CloudFileRow(
      kind: m.isError ? CloudRowKind.error : CloudRowKind.folder,
      title: m.name.isEmpty ? '(unnamed)' : m.name,
      meta: m.isReady ? Formatters.formatFileSize(m.size) : null,
      badges: [
        if (m.isError)
          const CloudRowBadge('Failed', CloudBadgeKind.error)
        else if (!m.isReady)
          CloudRowBadge(
            'Downloading ${m.progressPercent}%',
            CloudBadgeKind.warn,
          ),
      ],
      // Not-ready magnets keep a tap action too: _openMagnet explains why it
      // can't open ("still downloading" / "failed") — better than the menu
      // fallback, which here would be a Delete-only menu.
      onTap: () => _sections.navigation.openMagnet(m),
      actions: actions,
      selectionMode: _selection.selectionMode,
      selected: _selection.selectedIds.contains(m.id),
      onToggleSelected: () => _sections.selection.toggleSelection(m.id),
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }

  Widget _buildLinksView() {
    final app = AppThemeScope.of(context);
    if (_library.loadingLinks) {
      return const CloudRowSkeletonList();
    }
    if (_library.linksError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: app.fade(app.core.tx, 0x62 / 0xFF),
              ),
              const SizedBox(height: 16),
              Text(_library.linksError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sections.libraryLoading.loadLinks,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final links = _sections.search.visibleLinks;
    if (links.isEmpty) {
      return RefreshIndicator(
        onRefresh: _sections.libraryLoading.loadLinks,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _search.searchQuery.isNotEmpty
                    ? 'No links match your search.'
                    : 'No saved links yet.',
                style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _sections.libraryLoading.loadLinks,
      child: ListView.builder(
        controller: _f.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: links.length,
        itemBuilder: (context, index) {
          return KeyedSubtree(
            key: ValueKey(links[index].link),
            child: _buildLinkCard(links[index], index),
          );
        },
      ),
    );
  }

  Widget _buildLinkCard(AllDebridLink l, int index) {
    final isVideo = FileUtils.isVideoFile(l.fileName);
    final subtitle = [
      if (l.size > 0) Formatters.formatFileSize(l.size),
      if (l.host.isNotEmpty) l.host,
    ].join(' · ');

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
        title: l.fileName,
        meta: subtitle.isEmpty ? null : subtitle,
        onTap: isVideo
            ? () async {
                await widget.onSourceSelected?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: l.fileName,
                    debridService: 'alldebrid',
                    debridTorrentId: SeriesSource.opaqueCloudReference(l.link),
                    cloudSourceKind: SeriesSource.cloudKindWebDownload,
                    boundAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                if (!mounted) return;
                Navigator.of(context).pop();
              }
            : null,
        focusNode: index == 0 ? _f.firstItemFocusNode : null,
      );
    }

    final actions = <CloudRowAction>[
      if (isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _sections.playback.playLink(l),
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: isVideo ? 'Download to device' : 'Download',
        showInStrip: true,
        onSelected: () => _sections.downloads.downloadLink(l),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy link',
        onSelected: () => _sections.downloads.copyLink(l),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => _sections.deleteActions.deleteLinks([l]),
      ),
    ];

    return CloudFileRow(
      kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
      title: l.fileName,
      meta: subtitle.isEmpty ? null : subtitle,
      onTap: isVideo ? () => _sections.playback.playLink(l) : null,
      actions: actions,
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }

  Widget _buildFilesView() {
    final app = AppThemeScope.of(context);
    if (_navigation.loadingFiles) {
      return const CloudRowSkeletonList();
    }
    final files = _sections.search.visibleFiles;
    if (files.isEmpty) {
      return Center(
        child: Text(
          _search.fileSearchQuery.isNotEmpty
              ? 'No files match your search.'
              : 'No files in this magnet.',
          style: TextStyle(color: app.fade(app.core.tx, 0x8A / 0xFF)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        return KeyedSubtree(
          key: ValueKey(
            '${_navigation.currentMagnet!.id}:${files[index].path}:$index',
          ),
          child: _buildFileCard(files[index], index),
        );
      },
    );
  }

  Widget _buildFileCard(AllDebridFile f, int index) {
    final isVideo = _sections.playback.looksLikeVideo(f);

    // Parity with the old card: files inside a magnet only offer Play (video)
    // and Download — no delete or playlist at file granularity.
    final actions = <CloudRowAction>[
      if (isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () => _sections.playback.playFile(f),
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _sections.downloads.downloadFile(f),
      ),
    ];

    return CloudFileRow(
      kind: isVideo ? CloudRowKind.video : CloudRowKind.file,
      title: f.fileName,
      meta: Formatters.formatFileSize(f.size),
      onTap: isVideo ? () => _sections.playback.playFile(f) : null,
      actions: actions,
      focusNode: index == 0 ? _f.firstItemFocusNode : null,
    );
  }
}

/// Frozen step-0 seam: state reads and the dormant forced-files refresh only.
@visibleForTesting
Map<String, Object?> allDebridFilesTestAccess(
  State<AllDebridFilesScreen> state,
) {
  final s = state as _AllDebridFilesScreenState;
  return {
    'apiKey': s._library.apiKey,
    'loading': s._library.loading,
    'error': s._library.error,
    'magnets': List<AllDebridMagnet>.unmodifiable(s._library.magnets),
    'selectedView': s._navigation.selectedView.name,
    'links': List<AllDebridLink>.unmodifiable(s._library.links),
    'loadingLinks': s._library.loadingLinks,
    'linksLoadedOnce': s._library.linksLoadedOnce,
    'linksError': s._library.linksError,
    'currentMagnet': s._navigation.currentMagnet,
    'currentFiles': List<AllDebridFile>.unmodifiable(
      s._navigation.currentFiles,
    ),
    'loadingFiles': s._navigation.loadingFiles,
    'isAtRoot': s._sections.navigation.isAtRoot,
    'searchActive': s._search.searchActive,
    'searchQuery': s._search.searchQuery,
    'fileSearchActive': s._search.fileSearchActive,
    'fileSearchQuery': s._search.fileSearchQuery,
    'selectionMode': s._selection.selectionMode,
    'selectedIds': Set<String>.unmodifiable(s._selection.selectedIds),
    'isAllSelected': s._sections.selection.isAllSelected,
    'visibleMagnets': List<AllDebridMagnet>.unmodifiable(
      s._sections.search.visibleMagnets,
    ),
    'visibleFiles': List<AllDebridFile>.unmodifiable(
      s._sections.search.visibleFiles,
    ),
    'visibleLinks': List<AllDebridLink>.unmodifiable(
      s._sections.search.visibleLinks,
    ),
    'loadingDialogOpen': s._feedback.loadingDialogOpen,
    'scrollController': s._f.scrollController,
    'searchFocusNode': s._f.searchFocusNode,
    'searchClearFocusNode': s._f.searchClearFocusNode,
    'fileSearchFocusNode': s._f.fileSearchFocusNode,
    'backButtonFocusNode': s._f.backButtonFocusNode,
    'deleteButtonFocusNode': s._f.deleteButtonFocusNode,
    'toolbarSearchFocusNode': s._f.toolbarSearchFocusNode,
    'firstItemFocusNode': s._f.firstItemFocusNode,
    'shouldFocusOnLoad': s._f.shouldFocusOnLoad,
    'refresh': s._sections.navigation.refresh,
  };
}
