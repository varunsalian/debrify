import '../data/home_collections_repository.dart';
import '../data/home_return_repository.dart';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/home_collection.dart';
import '../../../models/home_preferences.dart';
import '../../../utils/platform_util.dart';
import '../application/home_catalog_controller.dart';
import '../application/home_catalog_continuation_controller.dart';
import '../application/home_row_order.dart';
import '../models/home_catalog_state.dart';
import '../models/home_catalog_plan.dart';
import '../models/home_board_configuration.dart';
import '../../search/presentation/catalog_search_section.dart';
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
  final CatalogSearchSection _catalogSection;

  int homeReturnRevision = -1;
  DateTime? homeLoadedAt;
  double homeLastScroll = 0;

  HomeCatalogContinuationController get catalogContinuationController =>
      _deps.bindings().continuation;
  bool get catalogContinuing => catalogContinuationController.busy;
  bool loading = true;
  String? error;
  // Board state. [homeSections] is the homepage cache; [sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  List<CatalogSection> get homeSections => homeCatalogController.rows;
  List<CatalogSection> sections = [];
  final boardViewport = HomeBoardViewport();
  List<List<FocusNode>> get rowNodes => boardViewport.nodes;
  // Per-row remembered focus column (leanback-style). DPAD up/down into a row
  // returns to where you left THAT row — the cell it points at is guaranteed
  // mounted, so requestFocus never no-ops on a scrolled-away lazy cell.
  Map<int, int> get rowCol => boardViewport.columns;
  // Board entrance: bumped each time the displayed sections are swapped
  // (initial load, search results in/out), so the first rows replay their
  // one-shot fade/rise entrance. Appends don't bump it.
  int boardGen = 0;
  DateTime boardAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);
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
  bool progressiveHomeLoadPending = false;
  bool homePaginationDeferred = false;
  double classicAnchorTailPadding = 0;
  final homePublication = HomeProgressPublication();

  /// A triggered board reload arrived while a catalog search was showing its
  /// results — running [_load] then would stomp the search view, so it's
  /// latched here and consumed by [_restoreHome].
  bool pendingBoardReload = false;

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
}
