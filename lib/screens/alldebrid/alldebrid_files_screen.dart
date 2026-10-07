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
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
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
