import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/home_collection.dart';
import '../../../models/home_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/platform_util.dart';
import '../application/home_catalog_continuation_controller.dart';
import '../application/home_catalog_controller.dart';
import '../application/home_row_order.dart';
import '../data/home_collections_repository.dart';
import '../data/home_return_repository.dart';
import '../models/home_board_configuration.dart';
import '../models/home_catalog_plan.dart';
import '../models/home_catalog_search_status.dart';
import '../models/home_catalog_state.dart';
import 'home_board_bindings.dart';
import 'home_board_viewport.dart';
import 'home_progress_publication.dart';

typedef HomeBoardDeps = ({
  HomeBoardBindings Function() bindings,
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function(String) isTracker,
});

/// The board's displayed rows, viewport, loading flags and live catalog projections.
class HomeBoardSection {
  HomeBoardSection(this._deps, this._catalogSection);
  late final HomeReturnRepository homeReturnRepository;
  late final HomeCollectionsRepository homeCollectionsRepository;
  final HomeBoardDeps _deps;
  final HomeCatalogSearchStatus _catalogSection;

  // Display state below is written only through this class's transitions, at
  // the points each workflow already used; readers go through the getters.
  int _homeReturnRevision = -1;
  int get homeReturnRevision => _homeReturnRevision;
  DateTime? _homeLoadedAt;
  DateTime? get homeLoadedAt => _homeLoadedAt;
  double _homeLastScroll = 0;
  double get homeLastScroll => _homeLastScroll;

  HomeCatalogContinuationController get catalogContinuationController =>
      _deps.bindings().continuation;
  bool get catalogContinuing => catalogContinuationController.busy;
  bool _loading = true;
  bool get loading => _loading;
  String? _error;
  String? get error => _error;
  // Board state. [homeSections] is the homepage cache; [sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  List<CatalogSection> get homeSections => homeCatalogController.rows;
  List<CatalogSection> _sections = [];
  List<CatalogSection> get sections => _sections;
  final boardViewport = HomeBoardViewport();
  List<List<FocusNode>> get rowNodes => boardViewport.nodes;
  // Per-row remembered focus column (leanback-style). DPAD up/down into a row
  // returns to where you left THAT row — the cell it points at is guaranteed
  // mounted, so requestFocus never no-ops on a scrolled-away lazy cell.
  Map<int, int> get rowCol => boardViewport.columns;
  // Board entrance: bumped each time the displayed sections are swapped
  // (initial load, search results in/out), so the first rows replay their
  // one-shot fade/rise entrance. Appends don't bump it.
  int _boardGen = 0;
  int get boardGen => _boardGen;
  DateTime _boardAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime get boardAppliedAt => _boardAppliedAt;
  HomeBoardConfiguration get homeConfiguration =>
      homeCatalogController.current.configuration;
  Set<String> get homeDisabled => homeConfiguration.preferences.disabled;

  // The OPT-IN extra rows (Trakt/Simkl list rows, IPTV custom-list rows) from
  // the same manager — default-off, so they live in their own store
  // (`home_extra_rows_v1`). Tracker ids become [HomeListSection]s at the head
  // of the board in [_load]; `iptvlist:` ids drive the IPTV list favourites
  // rows. Refreshed by [_reloadForHomeSettings].
  List<HomeExtraRow> get homeExtras => homeConfiguration.preferences.extras;

  /// Imported collections — each enabled one is a row of folder tiles.
  List<HomeCollection> get homeCollections => homeConfiguration.collections;

  /// Stable ids in the user's global Home-row order. Rows not present append
  /// canonically; ids whose backing row is temporarily unavailable stay saved.
  List<String> get homeRowOrder => homeConfiguration.preferences.rowOrder;

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Read in [_load], refreshed by
  /// [_reloadForHomeSettings]; resolved into [_spotlightSection.spotlightHeroOverride] by
  /// [_spotlightSection.resolveSpotlightHeroSource].
  HomeHeroSource get heroSource => homeConfiguration.preferences.heroSource;

  /// Whether any Trakt/Simkl list row is opted in — gates the tracker-row
  /// resolve in [_load] and the integrations-triggered reload.
  bool get trackerExtrasEnabled => homeExtras.any((r) => _deps.isTracker(r.id));

  /// Board load generation. [_load] is re-entrant (Home Rows save,
  /// integration connect/disconnect) and mutates shared state
  /// ([boardRefs]/[boardCursor]/[homeSections]); every await inside the
  /// load pipeline re-checks this so a superseded load can neither apply its
  /// stale sections nor advance the new load's cursor.
  int get boardLoadGen => homeCatalogController.generation;
  bool get boardRefreshing => homeCatalogController.current.refreshing;
  bool _progressiveHomeLoadPending = false;
  bool get progressiveHomeLoadPending => _progressiveHomeLoadPending;
  bool _homePaginationDeferred = false;
  bool get homePaginationDeferred => _homePaginationDeferred;
  double _classicAnchorTailPadding = 0;
  double get classicAnchorTailPadding => _classicAnchorTailPadding;
  final homePublication = HomeProgressPublication();

  /// A triggered board reload arrived while a catalog search was showing its
  /// results — running [_load] then would stomp the search view, so it's
  /// latched here and consumed by [_restoreHome].
  bool _pendingBoardReload = false;
  bool get pendingBoardReload => _pendingBoardReload;

  // Riverpod owns inventory, reservation and the last accepted snapshot for
  // this view. Search detours retain the subscription and its cursor.

  HomeCatalogController get homeCatalogController => _deps.bindings().catalog;
  List<HomeCatalogReference> get boardRefs =>
      homeCatalogController.current.references;
  int get boardCursor => homeCatalogController.current.cursor;
  HomeCatalogSnapshot? get committedBoard =>
      homeCatalogController.current.committed;
  bool get boardLoadingMore => homeCatalogController.current.loadingMore;
  ScrollController get boardScroll => boardViewport.scroll;

  /// Whether more board rows remain to lazily load (board mode only — never
  /// during a catalog search, which streams and appends its own rows).
  bool get boardHasMore =>
      _catalogSection.catalogQuery.isEmpty &&
      !_catalogSection.catalogSearching &&
      boardCursor < boardRefs.length;

  /// Reserving a batch advances the cursor before all its rows arrive. This
  /// affects deferred navigation, not whether another batch should be fetched.
  bool get boardRowsPending =>
      _catalogSection.catalogQuery.isEmpty &&
      !_catalogSection.catalogSearching &&
      (progressiveHomeLoadPending || boardLoadingMore);

  bool get boardCanAdvance => boardHasMore || boardRowsPending;

  bool get canPageHome =>
      _deps.mounted() &&
      (!PlatformUtil.isAndroidTvCached ||
          ((ModalRoute.of(_deps.context())?.isCurrent ?? true) &&
              !homePublication.hasPending &&
              !homePublication.isScheduled));

  // Addons that produced homepage rows, indexed by id, so a Continue Watching
  // tap can route back through the right addon (for Episodes / next-episode).
  final Map<String, StremioAddon> addonsById = {};

  /// Home ordering is presentation state for the Home board only. Search and
  /// Discover share some rail/focus helpers, but keep result-source order.
  bool get homeRowOrderActive =>
      !_deps.searchMode() &&
      !_deps.discoverMode() &&
      _catalogSection.catalogQuery.isEmpty &&
      !_catalogSection.catalogSearching;

  /// Saved Home orders created before MDBList was exposed do not contain its
  /// CW ids. Seed those new ids after the Simkl CW family instead of allowing
  /// the generic ordering projection to append them at the bottom. Any MDBList
  /// id already saved keeps its chosen position untouched.
  List<String> get effectiveHomeRowOrder => HomeRowOrder.seedCollections(
    HomeRowOrder.insertMissingAfter(
      homeRowOrder,
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    ),
    [
      for (final c in homeCollections)
        if (c.pinToTop) HomeCollectionRowIds.collection(c.id),
      for (final c in homeCollections)
        if (!c.pinToTop) HomeCollectionRowIds.collection(c.id),
    ],
  );
  void commitBoardSnapshot() {
    homeCatalogController.commit(addonsById);
  }

  // ── Display-state transitions ────────────────────────────────────────────
  // Callers invoke these where they previously assigned the fields, inside the
  // same setState calls, so ordering and rebuilds are unchanged.

  /// Captures the Home return cache revision a load or restore is based on.
  void recordReturnRevision() =>
      _homeReturnRevision = homeReturnRepository.revision;

  /// When the displayed Home rows were last accepted (null while loading).
  void recordHomeLoadedAt(DateTime? at) => _homeLoadedAt = at;

  void rememberScroll(double offset) => _homeLastScroll = offset;

  /// A load cycle starts: pagination resumes and progressive reveal is armed.
  void startLoadCycle({required bool progressive}) {
    _homePaginationDeferred = false;
    _progressiveHomeLoadPending = progressive;
  }

  /// Visible loading state for a (re)load. Kept rows keep their anchor space.
  void beginLoading({required bool keepRows}) {
    if (!keepRows) {
      _loading = true;
      _classicAnchorTailPadding = 0;
    }
    _error = null;
  }

  void endProgressiveLoad() => _progressiveHomeLoadPending = false;

  void finishLoading() => _loading = false;

  void failLoading(String message) => _error = message;

  /// Rows were published by a progressive load.
  void publishRows({required bool hasRows}) {
    _loading = false;
    if (hasRows) _error = null;
  }

  void deferPagination() => _homePaginationDeferred = true;

  void resumePagination() => _homePaginationDeferred = false;

  /// A reload that arrived during a catalog search, run when Home returns.
  void deferBoardReload() => _pendingBoardReload = true;

  /// Consumes a deferred reload; true when one was pending.
  bool takeDeferredBoardReload() {
    if (!_pendingBoardReload) return false;
    _pendingBoardReload = false;
    return true;
  }

  /// A fresh (non-incremental) board replaces the rows: replay entrances.
  void markFreshBoard() {
    _boardGen++;
    _boardAppliedAt = DateTime.now();
  }

  void showRows(List<CatalogSection> rows) => _sections = rows;

  void appendRows(List<CatalogSection> more) =>
      _sections = [..._sections, ...more];

  void growClassicAnchorTailPadding(double padding) =>
      _classicAnchorTailPadding = max(_classicAnchorTailPadding, padding);
}
