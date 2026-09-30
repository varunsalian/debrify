import '../features/home/presentation/home_spotlight_boards.dart';
import '../features/search/presentation/search_spotlight_results.dart';
import '../features/home/presentation/home_spotlight_rows.dart';
import '../features/home/presentation/home_tonight_section.dart';
import '../features/home/presentation/home_atrium_section.dart';
import '../features/home/presentation/home_stage_boards.dart';
import '../features/home/presentation/home_stage_cells.dart';
import '../features/home/presentation/home_stage_geometry.dart';
import '../features/home/presentation/home_stage_favorites.dart';
import '../features/home/presentation/home_stage_section.dart';
import '../features/home/application/home_catalog_dependencies.dart';
import '../features/home/presentation/home_spotlight_section.dart';
import '../features/search/presentation/search_spotlight_shell.dart';
import '../features/home/presentation/home_display_section.dart';
import '../features/home/presentation/home_stage_rails.dart';
import '../features/home/presentation/home_hero_live.dart';
import '../features/home/presentation/home_hero_preview.dart';
import '../features/home/presentation/home_hero_section.dart';
import '../features/home/presentation/home_continuation_see_all.dart';
import '../features/home/presentation/home_continuation_return.dart';
import '../features/home/presentation/home_continuation_rows.dart';
import '../features/home/presentation/home_continuation_menu.dart';
import '../features/home/presentation/home_continuation_projection.dart';
import '../features/home/presentation/home_continuation_removal.dart';
import '../features/home/presentation/home_continuation_playback.dart';
import '../features/home/presentation/home_continuation_announcements.dart';
import '../features/home/presentation/home_continuation_loading.dart';
import '../features/home/presentation/home_continuation_section.dart';
import '../features/home/presentation/home_watchlist_actions.dart';
import '../features/home/presentation/home_saved_iptv_actions.dart';
import '../features/home/presentation/home_saved_content_rows.dart';
import '../features/home/presentation/home_saved_content_section.dart';
import '../features/home/presentation/home_playlist_actions.dart';
import '../features/home/presentation/home_item_actions.dart';
import '../features/home/presentation/home_detail_actions.dart';
import '../features/home/presentation/home_source_actions.dart';
import '../features/home/presentation/home_catalog_actions.dart';
import '../features/home/presentation/home_playback_navigation.dart';
import '../features/search/presentation/lists_search_rows.dart';
import '../features/search/presentation/search_input_section.dart';
import '../features/search/presentation/search_mode_section.dart';
import '../features/search/presentation/catalog_search_section.dart';
import '../features/search/presentation/search_title_section.dart';
import '../features/search/presentation/search_title_open.dart';
import '../features/search/presentation/lists_search_section.dart';
import '../features/search/presentation/keyword_return.dart';
import '../features/search/presentation/keyword_search_frame.dart';
import '../features/search/presentation/keyword_search_rows.dart';
import '../features/search/presentation/keyword_selection.dart';
import '../features/search/presentation/keyword_search_actions.dart';
import '../features/search/presentation/keyword_search_dialogs.dart';
import '../features/search/presentation/keyword_search_section.dart';
import '../features/discover/application/discover_card_settings_controller.dart';
import '../features/discover/presentation/discover_loading.dart';
import '../features/discover/presentation/discover_section.dart';
import '../features/home/presentation/home_media_bindings.dart';
import '../features/home/presentation/home_board_bindings.dart';
import '../features/home/presentation/home_see_all_navigation.dart';
import '../features/home/application/home_refresh_queue.dart';
import '../features/home/presentation/home_favorite_bindings.dart';
import '../features/search/presentation/search_result_bindings.dart';
import '../features/search/presentation/lists_navigation.dart';
import '../features/discover/presentation/discover_bindings.dart';
import '../features/home/presentation/home_classic_favorite_rows.dart';
import '../features/home/presentation/home_classic_navigation.dart';
import '../features/search/presentation/catalog_search_status.dart';
import '../features/home/presentation/home_classic_board.dart';
import '../features/home/presentation/home_board_media.dart';
import '../ui/core/retry_message.dart';
import '../features/home/presentation/home_board_content.dart';
import '../features/home/application/home_detail_action_dependencies.dart';
import '../features/home/presentation/home_detail_menus.dart';
import '../features/home/application/home_simkl_continuation_dependencies.dart';
import '../features/home/presentation/home_detail_action_bridge.dart';
import '../features/home/presentation/home_catalog_row.dart';
import '../features/home/presentation/home_catalog_row_header.dart';
import '../features/discover/presentation/discover_panels.dart';
import '../features/home/presentation/home_hero_shell.dart';
export '../features/home/presentation/spotlight_iptv_card_preview.dart'
    show SpotlightIptvCardPreview;
import '../features/search/presentation/search_page_shell.dart';
import '../widgets/skeleton_poster.dart' show BrandLoadingStage;
import '../features/home/presentation/home_stage_rows.dart';
import '../features/home/presentation/home_classic_rows.dart';
import '../features/discover/models/discover_source_state.dart';
import '../features/discover/application/metadata_feature_controller.dart';
import '../features/discover/models/metadata_feature_policy.dart';
import '../features/home/models/home_tracker_authentication.dart';
import '../features/home/application/home_tracker_authentication_controller.dart';
import '../features/home/models/home_return_snapshot.dart';
import '../features/home/data/home_return_repository.dart';
import '../features/home/application/home_return_dependencies.dart';
import '../features/home/application/home_pikpak_only_controller.dart';
import '../features/home/application/home_bound_counts_controller.dart';
import '../features/home/application/home_configuration_changes.dart';
import '../features/home/application/home_layout_preference_dependencies.dart';
import '../features/home/application/home_default_view.dart';
import '../features/home/application/home_default_view_dependencies.dart';
import '../features/home/application/home_display_preferences_controller.dart';
import '../features/home/models/home_display_preferences.dart';
import '../features/home/presentation/home_progress_publication.dart';
import '../features/home/presentation/home_continuation_bindings.dart';
import '../features/home/models/home_continuation_session.dart';
import '../features/home/application/home_row_snapshot.dart';
import '../features/home/application/home_board_load.dart';
import '../features/home/application/home_board_dependencies.dart';
import '../features/home/models/home_board_configuration.dart';
import '../features/home/application/home_collections_dependencies.dart';
import '../features/home/application/home_configuration_refresh.dart';
import '../features/home/data/home_collections_repository.dart';
import '../features/home/models/home_catalog_preferences.dart';
import '../features/home/models/home_catalog_session.dart';
import '../features/home/application/home_catalog_controller.dart';
import '../features/home/application/home_catalog_continuation_controller.dart';
import '../features/home/models/home_catalog_state.dart';
import '../features/home/models/home_catalog_plan.dart';
import '../features/home/application/home_catalog_preferences_dependencies.dart';
import '../features/search/application/keyword_snapshot_dependencies.dart';
import '../features/search/data/keyword_snapshot_repository.dart';
import '../features/search/models/keyword_cache_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/search/models/search_session.dart';
import '../features/search/models/search_mode.dart';
import '../services/native_series_metadata_service.dart';
import '../services/profiles/profile_runtime.dart';
import '../models/metadata_preferences.dart';
import '../services/metadata_preferences_service.dart';
import '../services/home_load_deadline.dart';
import '../services/home_load_progress.dart';
import '../features/home/presentation/home_board_viewport.dart';
import '../widgets/home/home_row_focus.dart'
    show homeRowHeight, preserveHomeInsertionAnchor;
import '../features/home/presentation/home_continuation_focus.dart';
import '../features/home/presentation/home_board_frame.dart';
import '../services/home_row_refresh.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_scope.dart';
import '../features/home/presentation/home_classic_row_metrics.dart';
import '../utils/platform_util.dart';
import '../models/home_collection.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../services/analytics_service.dart';
import '../services/home_collection_rows.dart';
import '../services/home_collections_store.dart';
import '../services/home_list_rows.dart';
import '../services/home_row_order.dart';
import '../services/hide_watched_prefs.dart';
import '../services/iptv_cw_router.dart';
import '../services/iptv_media_store.dart';
import '../services/main_page_bridge.dart';
import '../models/profiles/profile_policy.dart';
import '../services/profiles/profile_policy_guard.dart';
import '../services/playlist_player_service.dart';
import '../services/profiles/profile_session_memory.dart';
import '../services/stremio_iptv_service.dart';
import '../services/stremio_service.dart';
import '../services/storage_service.dart';
import '../services/tv_hero_artwork_quality_controller.dart';
import '../services/tvos_top_shelf_service.dart';
import '../services/torrent_bulk_add_service.dart';
import '../services/torrent_playback_service.dart';
import '../services/video_player_launcher.dart';
import '../utils/tv_search_focus_handoff.dart';
import '../widgets/home/card_focus_rise.dart';
import '../widgets/home/home_theme.dart';
import '../services/tmdb_title_search.dart';
import '../services/metadata_title_service.dart';
import 'collections/collection_folder_screen.dart';
import '../services/mdblist/mdblist_list_source.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../widgets/see_all/discover_card_settings_scope.dart';
import '../services/simkl/simkl_menu_helpers.dart';

/// TV focus ring for board cards — violet-300, deliberately LIGHTER than the
/// board's chrome accent: a light ring over dark art pops at 10ft, while the
/// deep accent stays for chrome (tags, sidebar). Pairs with the calm 1.045
/// scale. (The old kStremioAccent/kStremioBg palette constants now live in
/// the app theme as `app.home.chromeAccent` / `app.home.bg`.)
const Color kStremioFocusRing = kCardFocusRing;

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch as
/// the user scrolls, and how many items to keep per row. Enumerating catalogs is
/// free (manifest metadata) — only fetching each row's items costs a call — so we
/// list every catalog up front and lazily pull batches on scroll (Stremio-style)
/// instead of a hard global row cap.
const int _kBoardBatchSize = 8;

/// Dedicated Search tab.
///
/// * CATALOG mode — a Stremio-style board (one horizontal row per addon
///   catalog) with a hero spotlight that reflects the focused title; submitting a
///   query searches every searchable addon and shows one horizontal row of
///   results per addon (same board layout).
/// * KEYWORD mode — raw torrent search → tap a result to add/play.
/// * LISTS mode — MDBList public-list search, isolated from title catalogs.
/// Catalog offers TMDB title suggestions while typing on the
/// dedicated Search tab. Selecting a title opens its existing detail flow.
///
/// All playback (catalog auto-best, sources list, keyword) runs in-tab through
/// the isolated [TorrentPlaybackService]; the Home engine is never invoked.
class SearchScreen extends ConsumerStatefulWidget {
  final bool isTelevision;

  /// Dedicated-search-tab mode (TV only). When true the screen is *only* the
  /// search field + Catalog/Keyword/Lists selector over a blank prompt until
  /// the user types — no hero/board. When false it's the "Home New" board
  /// (chrome-free on TV; persistent search bar on desktop/mobile).
  final bool searchMode;

  /// Discover-tab mode. A single browsable grid with a "Source" dropdown
  /// (Continue Watching / Trakt / …) instead of the board's stacked rails —
  /// reuses this screen's item-open/play handlers and cached CW/Trakt rows.
  final bool discoverMode;

  @visibleForTesting
  final TmdbTitleSearch? titleSearch;

  @visibleForTesting
  final Future<StremioMeta> Function(StremioMeta)? suggestedTitleResolver;

  const SearchScreen({
    super.key,
    this.isTelevision = false,
    this.searchMode = false,
    this.discoverMode = false,
    this.titleSearch,
    this.suggestedTitleResolver,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// Fixed Discover sources; installed addons are appended dynamically (key
/// 'a:{addonId}').
const String _discCw = DiscoverSources.cw;
const String _discTmdb = DiscoverSources.tmdb;
const String _discMdblist = DiscoverSources.mdblist;

class _SearchScreenState extends ConsumerState<SearchScreen>
    with RouteAware, WidgetsBindingObserver {
  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get _tabIndex => widget.searchMode ? 17 : (widget.discoverMode ? 18 : 15);

  final StremioService _stremio = StremioService.instance;
  late final HomeContinuationSeeAll _continuationSeeAll;
  late final HomeContinuationReturn _continuationReturn;
  late final HomeContinuationRows _continuationRows;
  late final HomeContinuationMenu _continuationMenu;
  late final HomeContinuationProjection _continuationProjection;
  late final HomeContinuationRemoval _continuationRemoval;
  late final HomeContinuationPlayback _continuationPlayback;
  late final HomeContinuationAnnouncements _continuationAnnouncements;
  late final HomeContinuationLoading _continuationLoading;
  late final HomeContinuationSection _continuationSection;
  late final HomeContinuationBindings _continuationBindings;
  late final HomeWatchlistActions _watchlistActions;
  late final HomeSavedIptvActions _savedIptv;
  late final HomeSavedContentRows _savedRows;
  late final HomeSavedContentSection _savedSection;
  late final HomeFavoriteBindings _favoriteBindings;
  late final HomePlaylistActions _playlistActions;
  late HomeItemActions _itemActions;
  late HomeDetailActions _detailActions;
  late HomeSourceActions _sourceActions;
  late final HomeCollectionsRepository _homeCollectionsRepository;

  final TextEditingController _searchController = TextEditingController();
  late final _titleSearch = widget.titleSearch ?? TmdbTitleSearch();
  final _titleSearchScope = ProfileRuntime.scope.value;
  final TvSearchFocusHandoff _searchSubmitFocus = TvSearchFocusHandoff();
  // Dedicated MDBList list-search state. Lists is its own Search mode; it
  // never runs as part of Catalog search. Each result card hands off via
  // MainPageBridge.pendingMdblistListOpen. One focus node per card.
  late final SearchSession _searchSession;
  late final SearchResultBindings _searchResultBindings;

  // Retain the plain snapshot adapter: disposal must not resolve WidgetRef.
  late final KeywordSnapshotRepository _keywordSnapshots;

  late final HomeReturnRepository _homeReturnRepository;
  int _homeReturnRevision = -1;
  DateTime? _homeLoadedAt;
  double _homeLastScroll = 0;

  /// Captured at mount, not dispose: an outgoing screen may be torn down after
  /// the next profile is published and must still tag its snapshot as outgoing.
  late final ProfileSessionOwner _profileSessionOwner;

  /// Discriminates the three [SearchScreen] variants so a preserved keyword
  /// search only restores into the same kind of tab it came from.
  String get _variantKey => widget.searchMode
      ? 'search'
      : widget.discoverMode
      ? 'discover'
      : 'board';

  /// True when PikPak is the ONLY configured provider. PikPak can't quick-play
  /// (it queues a cloud download), so catalog "Play" is hidden — matching Home.
  HomePikpakOnlyController get _pikpakOnlyController =>
      _homeBoardBindings.pikpak;
  bool get _pikpakOnly => _pikpakOnlyController.current;

  /// Experimental flag: route series taps to the merged detail+episodes page.
  /// Loaded once on init; movies and the flag-off path keep the existing flow.
  bool _mergedSeriesPage = false;

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  HomeBoundCountsController get _boundCountsController =>
      _homeBoardBindings.boundCounts;
  Map<String, int> get _boundCounts => _boundCountsController.current;

  // Board state. [_homeSections] is the homepage cache; [_sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  final _catalogFocus = HomeContinuationFocus();
  FocusNode get _catalogContinueNode => _catalogFocus.continueNode;
  FocusNode get _catalogMoreNode => _catalogFocus.moreNode;
  HomeCatalogContinuationController get _catalogContinuationController =>
      _homeBoardBindings.continuation;
  bool get _catalogContinuing => _catalogContinuationController.busy;
  bool _loading = true;
  String? _error;
  List<CatalogSection> get _homeSections => _homeCatalogController.rows;
  List<CatalogSection> _sections = [];
  final _boardViewport = HomeBoardViewport();
  List<List<FocusNode>> get _rowNodes => _boardViewport.nodes;
  // Per-row remembered focus column (leanback-style). DPAD up/down into a row
  // returns to where you left THAT row — the cell it points at is guaranteed
  // mounted, so requestFocus never no-ops on a scrolled-away lazy cell.
  Map<int, int> get _rowCol => _boardViewport.columns;
  // Board entrance: bumped each time the displayed sections are swapped
  // (initial load, search results in/out), so the first rows replay their
  // one-shot fade/rise entrance. Appends don't bump it.
  int _boardGen = 0;
  DateTime _boardAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);
  // Catalogs that errored (timeout / HTTP / network) during the current
  // catalog search — distinct from "returned no results". Drives the quiet
  // "N sources didn't respond" note so failing addons don't just vanish.
  int get _catalogSearchFailures => _catalogSection.catalogState.failures;

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [_reloadForHomeSettings] when the manager saves.
  // Bootstrap is captured at state construction, matching the previous field
  // initialization. All accepted changes live in the controller afterwards.
  final _initialHomeConfiguration = HomeBoardConfiguration(
    preferences: const HomeCatalogPreferences.empty(),
    collections: const [],
    collectionsSignature: HomeCollectionsStore.signatureOf(const []),
    hideWatched: HideWatchedPrefs.enabled,
  );
  HomeBoardConfiguration get _homeConfiguration =>
      _homeCatalogController.current.configuration;
  Set<String> get _homeDisabled => _homeConfiguration.preferences.disabled;

  // The OPT-IN extra rows (Trakt/Simkl list rows, IPTV custom-list rows) from
  // the same manager — default-off, so they live in their own store
  // (`home_extra_rows_v1`). Tracker ids become [HomeListSection]s at the head
  // of the board in [_load]; `iptvlist:` ids drive the IPTV list favourites
  // rows. Refreshed by [_reloadForHomeSettings].
  List<HomeExtraRow> get _homeExtras => _homeConfiguration.preferences.extras;

  /// Imported collections — each enabled one is a row of folder tiles.
  List<HomeCollection> get _homeCollections => _homeConfiguration.collections;

  /// Stable ids in the user's global Home-row order. Rows not present append
  /// canonically; ids whose backing row is temporarily unavailable stay saved.
  List<String> get _homeRowOrder => _homeConfiguration.preferences.rowOrder;

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Read in [_load], refreshed by
  /// [_reloadForHomeSettings]; resolved into [_spotlightSection.spotlightHeroOverride] by
  /// [_spotlightSection.resolveSpotlightHeroSource].
  HomeHeroSource get _heroSource => _homeConfiguration.preferences.heroSource;

  /// Whether any Trakt/Simkl list row is opted in — gates the tracker-row
  /// resolve in [_load] and the integrations-triggered reload.
  bool get _trackerExtrasEnabled =>
      _homeExtras.any((r) => HomeExtraRowIds.isTracker(r.id));

  /// Board load generation. [_load] is re-entrant (Home Rows save,
  /// integration connect/disconnect) and mutates shared state
  /// ([_boardRefs]/[_boardCursor]/[_homeSections]); every await inside the
  /// load pipeline re-checks this so a superseded load can neither apply its
  /// stale sections nor advance the new load's cursor.
  int get _boardLoadGen => _homeCatalogController.generation;
  bool get _boardRefreshing => _homeCatalogController.current.refreshing;
  bool _progressiveHomeLoadPending = false;
  bool _homePaginationDeferred = false;
  double _classicAnchorTailPadding = 0;
  final _homePublication = HomeProgressPublication();

  void _publishHomeProgress(
    List<CatalogSection> rows,
    bool first,
    int generation,
    Object? scope,
  ) {
    if (!mounted ||
        generation != _boardLoadGen ||
        scope != ProfileRuntime.scope.value) {
      return;
    }
    _homeCatalogController.replaceRows(rows);
    if (_catalogSection.catalogQuery.isNotEmpty ||
        _catalogSection.catalogSearching) {
      return;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      // Keep data, not new image widgets, while a detail page/player covers
      // Home. Returning first restores the old focused row, then inserts the
      // arrivals with the same scroll-anchor protection as foreground loads.
      _homePublication.defer((
        rows: rows,
        first: first,
        generation: generation,
        scope: scope,
      ));
      return;
    }
    _homePublication.clear();
    if (!first && _boardHasFocus()) _autoFocusSettled = true;
    setState(() {
      _loading = false;
      if (rows.isNotEmpty) _error = null;
    });
    _applySections(rows, preserveFocus: !first, incremental: !first);
    MainPageBridge.homeBoardReady.value = true;
    _maybeAutoFocusBoard();
    _maybeCompleteDeferredDown();
    _stageSection.maybeCompleteStageAdvance();
  }

  void _resumeHomeProgress() => _homePublication.resume(
    isVisible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
    isCurrent: (pending) =>
        pending.generation == _boardLoadGen &&
        pending.scope == ProfileRuntime.scope.value,
    publish: (pending) => _publishHomeProgress(
      pending.rows,
      pending.first,
      pending.generation,
      pending.scope,
    ),
    onResumed: () => _maybeAutoFillBoard(resumeDeferred: true),
  );

  void _resumeDeferredHomePagination() {
    if (!_homePaginationDeferred || _boardRefreshing || !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _homePaginationDeferred = false;
    if (_boardHasMore) unawaited(_loadMoreBoard());
  }

  /// A triggered board reload arrived while a catalog search was showing its
  /// results — running [_load] then would stomp the search view, so it's
  /// latched here and consumed by [_restoreHome].
  bool _pendingBoardReload = false;

  // Riverpod owns inventory, reservation and the last accepted snapshot for
  // this view. Search detours retain the subscription and its cursor.
  late final ProviderSubscription<HomeDefaultView> _homeDefaultViewSubscription;
  HomeDefaultView get _homeDefaultView => _homeDefaultViewSubscription.read();
  late final HomeCatalogSession _homeCatalogSession;
  late final HomeBoardBindings _homeBoardBindings;
  HomeCatalogController get _homeCatalogController =>
      _homeBoardBindings.catalog;
  List<HomeCatalogReference> get _boardRefs =>
      _homeCatalogController.current.references;
  int get _boardCursor => _homeCatalogController.current.cursor;
  HomeCatalogSnapshot? get _committedBoard =>
      _homeCatalogController.current.committed;
  bool get _boardLoadingMore => _homeCatalogController.current.loadingMore;
  ScrollController get _boardScroll => _boardViewport.scroll;

  /// Whether more board rows remain to lazily load (board mode only — never
  /// during a catalog search, which streams and appends its own rows).
  bool get _boardHasMore =>
      _catalogSection.catalogQuery.isEmpty &&
      !_catalogSection.catalogSearching &&
      _boardCursor < _boardRefs.length;

  /// Reserving a batch advances the cursor before all its rows arrive. This
  /// affects deferred navigation, not whether another batch should be fetched.
  bool get _boardRowsPending =>
      _catalogSection.catalogQuery.isEmpty &&
      !_catalogSection.catalogSearching &&
      (_progressiveHomeLoadPending || _boardLoadingMore);

  bool get _boardCanAdvance => _boardHasMore || _boardRowsPending;

  bool get _canPageHome => mounted &&
      (!PlatformUtil.isAndroidTvCached ||
        ((ModalRoute.of(context)?.isCurrent ?? true) &&
          !_homePublication.hasPending && !_homePublication.isScheduled));

  /// TV auto-focus "settle to the top" state. On arrival the board focuses the
  /// best card available immediately (an addon row if the Trakt rows above it
  /// are still loading), remembering that node in [_autoFocusedNode]. As higher
  /// rows load (Trakt, local Continue Watching), focus slides up to the new top
  /// card — but only while the user is idle (focus still sits on the node we
  /// placed). The instant the user moves focus themselves, [_autoFocusSettled]
  /// latches and we never touch focus again.
  FocusNode? _autoFocusedNode;
  bool _autoFocusSettled = false;

  /// Coalesces auto-focus passes: multiple content loads finishing in one frame
  /// schedule a single post-frame placement (which reads the final top after all
  /// their setStates apply), instead of racing several callbacks whose
  /// primaryFocus reads haven't caught up to each other's requestFocus.
  bool _autoFocusScheduled = false;

  /// Whether Trakt is connected — gates the Trakt-syncing detail quick actions
  /// (watchlist / collection / watched / rate / list). App actions (Select
  /// Source, Add to Stremio TV, Search Packs) show regardless.
  Map<HomeTracker, HomeTrackerAuthenticationController>
  get _trackerAuthControllers => _homeBoardBindings.authentication;
  bool get _isTraktAuthenticated =>
      _trackerAuthControllers[HomeTracker.trakt]!.current;

  /// Whether Simkl is connected — gates the Simkl detail quick actions,
  /// rendered as their own strip alongside Trakt's (see [_isTraktAuthenticated]).
  bool get _isSimklAuthenticated =>
      _trackerAuthControllers[HomeTracker.simkl]!.current;

  /// Whether MDBList is connected — gates the MDBList entry in the Discover
  /// source dropdown (hidden when disconnected, so an unauthed user isn't shown
  /// a dead source; kept visible if it's somehow the active source).
  bool get _isMdblistAuthenticated =>
      _trackerAuthControllers[HomeTracker.mdblist]!.current;

  // Addons that produced homepage rows, indexed by id, so a Continue Watching
  // tap can route back through the right addon (for Episodes / next-episode).
  final Map<String, StremioAddon> _addonsById = {};

  /// Home ordering is presentation state for the Home board only. Search and
  /// Discover share some rail/focus helpers, but keep result-source order.
  bool get _homeRowOrderActive =>
      !widget.searchMode &&
      !widget.discoverMode &&
      _catalogSection.catalogQuery.isEmpty &&
      !_catalogSection.catalogSearching;

  /// Saved Home orders created before MDBList was exposed do not contain its
  /// CW ids. Seed those new ids after the Simkl CW family instead of allowing
  /// the generic ordering projection to append them at the bottom. Any MDBList
  /// id already saved keeps its chosen position untouched.
  List<String> get _effectiveHomeRowOrder => HomeRowOrder.seedCollections(
    HomeRowOrder.insertMissingAfter(
      _homeRowOrder,
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    ),
    [
      for (final c in _homeCollections)
        if (c.pinToTop) HomeCollectionRowIds.collection(c.id),
      for (final c in _homeCollections)
        if (!c.pinToTop) HomeCollectionRowIds.collection(c.id),
    ],
  );
  late final HomeMediaBindings _homeMediaBindings;
  late final HomeStageBoards _stageBoards;
  late final HomeAtriumSection _atriumLayout;
  late final HomeTonightSection _tonightLayout;
  late final HomeSpotlightRows _spotlightRows;
  late final SearchSpotlightResults _spotlightResults;
  late final HomeSpotlightBoards _spotlightBoards;
  late final HomeStageCells _stageCells;
  late final HomeStageGeometry _stageGeometry;
  late final HomeStageFavorites _stageFavorites;
  late final HomeStageSection _stageSection;
  late final HomeSpotlightSection _spotlightSection;
  late final SearchSpotlightShell _spotlightShell;
  late final HomeDisplaySection _displaySection;
  late final HomeStageRails _stageRailsSection;
  late final HomeHeroShell _heroShell;
  late final HomeHeroSection _heroSection;
  late final HomeHeroPreview _heroPreview;
  late final HomeHeroLive _heroLive;

  DiscoverCardSettingsController get _discoverCardSettingsController =>
      _discoverBindings.cards;
  late final HomeCatalogActions _catalogActions;
  late final HomePlaybackNavigation _playbackNavigation;
  late final SearchInputSection _inputSection;
  late final SearchModeSection _modeSection;
  late final CatalogSearchSection _catalogSection;
  late final SearchTitleSection _titleSection;
  late final SearchTitleOpen _titleOpen;
  late final ListsSearchSection _listsSection;
  late final ListsSearchRows _listsRows;
  late final KeywordSearchSection _keywordSection;
  late final KeywordReturn _keywordReturn;
  late final KeywordSearchRows _keywordRows;
  late final KeywordSelection _keywordSelection;
  late final KeywordSearchActions _keywordActions;
  late final KeywordSearchDialogs _keywordDialogs;
  late final DiscoverSection _discoverSection;
  late final DiscoverLoading _discoverLoading;
  late final DiscoverBindings _discoverBindings;

  @override
  void initState() {
    super.initState();
    _discoverSection = DiscoverSection((
      bindings: () => _discoverBindings,
      mounted: () => mounted,
      discoverMode: () => widget.discoverMode,
      isTelevision: () => widget.isTelevision,
      discoveryEnabled: () =>
          _metadataFeaturePolicy?.features.contains(
            MetadataFeature.discovery,
          ) ==
          true,
      context: () => context,
      setState: setState,
      buildPanel: () => buildDiscoverPanels(
        selected: _discoverSection.discSource,
        isTelevision: widget.isTelevision,
        sourceNode: _discoverSection.discSourceNode,
        preferences: _metadataFeaturePolicy,
        mdblistEnabled: kMdblistEnabled,
        mdblistAuthenticated: _isMdblistAuthenticated,
        addons: _discoverSection.discAddons,
        onSelectSource: _discoverSection.selectDiscoverSource,
        pikpakOnly: _pikpakOnly,
        onItemFocused: _discoverSection.onDiscFocused,
        isBound: _isBound,
        findAddon: (id) => _addonsById[id],
        addonForContinue: _addonForContinue,
        onOpenCatalog: (item, addon, {isMdblistSource = false}) => _itemActions
            .openItem(item, addon, isMdblistSource: isMdblistSource),
        onPlayCatalog: _catalogActions.onCatalogPlay,
        traktItems: _continuationSection.traktAll,
        traktProgress: () => _continuationSection
            .cwCardMaps(HomeContinuationKind.trakt)
            .progress,
        onOpenTrakt: _continuationPlayback.openTraktItem,
        onPlayTrakt: _continuationPlayback.playTraktItem,
        simklItems: _continuationSection.simklAll,
        simklProgress: _continuationSection.simklProgress,
        onOpenSimkl: _continuationPlayback.openSimklItem,
        onPlaySimkl: _continuationPlayback.playSimklItem,
        onOpenSimklContinuation: _continuationPlayback.openSimklCwItem,
        onPlaySimklContinuation: _continuationPlayback.playSimklCwItem,
        mdblistList: _discoverSection.discMdblistList,
        localItems: _continuationSection.cwAll,
        localProgress: (m) =>
            _continuationSection.cwCardProgress(HomeContinuationKind.local, m),
        onOpenLocal: _continuationPlayback.openContinueItem,
        onPlayLocal: _continuationPlayback.onContinuePlay,
        reloadLocal: () async {
          await _continuationLoading.loadContinueWatching();
          if (!mounted) return const <StremioMeta>[];
          return List<StremioMeta>.of(_continuationSection.cwAll);
        },
      ),
    ));
    _discoverLoading = DiscoverLoading((
      source: () => _discoverBindings.source,
      mounted: () => mounted,
      mdblistEnabled: kMdblistEnabled,
      setState: setState,
      metadataFeaturePolicy: () => _metadataFeaturePolicy,
      refreshMetadataFeaturePolicy: _refreshMetadataFeaturePolicy,
      loadContinueWatching: () => _continuationLoading.loadContinueWatching(),
      loadTraktContinueWatching: ({refreshBound = true}) => _continuationLoading
          .loadTraktContinueWatching(refreshBound: refreshBound),
      loadSimklContinueWatching: ({refreshBound = true}) => _continuationLoading
          .loadSimklContinueWatching(refreshBound: refreshBound),
      loadMdblistContinueWatching: ({refreshBound = true}) =>
          _continuationLoading.loadMdblistContinueWatching(
            refreshBound: refreshBound,
          ),
      refreshBoundSources: _refreshBoundSources,
    ), _addonsById);
    _keywordSection = KeywordSearchSection(ref, (
      session: () => _searchSession,
      bindings: () => _searchResultBindings,
      mode: () => _modeSection.mode,
      mounted: () => mounted,
      setState: setState,
      focusSearch: () => _inputSection.focusSearchFieldAtEnd(),
      focusSearchNode: () => _inputSection.searchFocusNode.requestFocus(),
      focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
      completeSubmitFocus: (target) =>
          _inputSection.completeSearchSubmitFocus(target),
      cancelSubmitFocus: _searchSubmitFocus.cancel,
    ));
    _keywordDialogs = KeywordSearchDialogs(ref, (
      context: () => context,
      mounted: () => mounted,
      session: () => _searchSession,
      bindings: () => _searchResultBindings,
      toolbarNodes: () => _keywordSection.kwToolbarNodes,
      freezeAndAdopt: _keywordSection.kwFreezeAndAdopt,
      syncResults: _keywordSection.syncKeywordResults,
      runKeyword: _keywordSection.runKeyword,
    ));
    _keywordSelection = KeywordSelection((
      mounted: () => mounted,
      controller: () => _keywordSection.keywordResultsController,
      toolbarNodes: () => _keywordSection.kwToolbarNodes,
      freezeAndAdopt: _keywordSection.kwFreezeAndAdopt,
    ));
    _keywordActions = KeywordSearchActions((
      context: () => context,
      mounted: () => mounted,
      bindings: () => _searchResultBindings,
      bulkAdd: TorrentBulkAddService.showBulkAddDialog,
      activate: TorrentPlaybackService.activateTorrent,
      canDownload: (torrent) =>
          ProfilePolicyGuard.allowsSync(ProfileFeature.downloads) &&
          TorrentPlaybackService.supportsDirectStreamDownload(torrent),
      download: TorrentPlaybackService.downloadDirectStream,
      copyText: (link) => Clipboard.setData(ClipboardData(text: link)),
      snack: (message) => _playbackNavigation.snack(message),
      freeze: _keywordSection.kwFreeze,
      selection: _keywordSelection,
    ));
    final keywordFrame = KeywordSearchFrame(
      (
        isTelevision: () => widget.isTelevision,
        bindings: () => _searchResultBindings,
        focus: () => _keywordSection.keywordFocus,
        floatingNavigation: () =>
            MainPageBridge.phoneNavStyleCached == 'floating',
        focusSearchNode: () => _inputSection.searchFocusNode.requestFocus(),
        freeze: _keywordSection.kwFreeze,
        setSourceTab: _keywordSection.setKwSourceTab,
      ),
      _keywordSection.keywordViewport,
      _keywordSection.kwCinemaKey,
      _keywordActions,
      _keywordSelection,
    );
    _keywordRows = KeywordSearchRows(
      (
        mounted: () => mounted,
        isTelevision: () => widget.isTelevision,
        bindings: () => _searchResultBindings,
        focus: () => _keywordSection.keywordFocus,
        appearance: () => _keywordSection.appearance,
        message: _message,
        focusSearch: () => _inputSection.focusSearchFieldAtEnd(),
        focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
        focusAboveResults: _keywordSection.focusAboveKeywordResults,
        freeze: _keywordSection.kwFreeze,
        adopt: _keywordSection.kwAdoptPending,
        setSourceTab: _keywordSection.setKwSourceTab,
      ),
      _keywordSection.keywordViewport,
      _keywordActions,
      _keywordDialogs,
      _keywordSelection,
      keywordFrame,
    );
    _keywordReturn = KeywordReturn(
      (
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        keywordAllowed: () =>
            ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
        variant: () => _variantKey,
        mode: () => _modeSection.mode,
        setMode: (mode) => _modeSection.mode = mode,
        repository: () => _keywordSnapshots,
        bindings: () => _searchResultBindings,
        focus: () => _keywordSection.keywordFocus,
        syncTabs: _keywordSection.syncKwTabNodes,
      ),
      _searchController,
      _keywordSection.keywordViewport,
    );
    _listsSection = ListsSearchSection(ref, (
      session: () => _searchSession,
      bindings: () => _searchResultBindings,
      mounted: () => mounted,
      setState: setState,
      isTelevision: () => widget.isTelevision,
      mdblistEnabled: kMdblistEnabled,
      cancelSubmitFocus: _searchSubmitFocus.cancel,
      completeSubmitFocus: (target) =>
          _inputSection.completeSearchSubmitFocus(target),
      trackOpen: (choice) => AnalyticsService.trackInBackground(
        'mdblist_list_search_open',
        {'liked': choice.liked},
      ),
      handoff: (choice) {
        MainPageBridge.pendingMdblistListOpen = {
          'id': choice.id,
          'name': choice.name,
          'ownerName': choice.ownerName,
          'itemCount': choice.itemCount,
          'liked': choice.liked,
          'likes': choice.likes,
        };
        // Discover tab — main.dart `case 18`.
        MainPageBridge.switchTab?.call(MainTab.discover);
      },
      context: () => context,
      createNavigation: () => ListsNavigation(
        isTelevision: () => widget.isTelevision,
        pikpakOnly: () => _pikpakOnly,
        isBound: _isBound,
        onOpen: (item) => _itemActions.openItem(
          item,
          _addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        ),
        onQuickPlay: (item) => _catalogActions.onCatalogPlay(
          item,
          _addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        ),
        afterReturn: _continuationReturn.afterSeeAllReturn,
      ),
    ));
    _titleSection = SearchTitleSection((
      mode: () => _modeSection.mode,
      searchMode: () => widget.searchMode,
      metadata: () => _metadataFeatureController,
      activeTab: () => MainPageBridge.activeTab.value,
      originCurrent: () => _titleSearchScope == ProfileRuntime.scope.value,
      update: (query, {required language, enabled = true, composing = false}) =>
          _titleSearch.update(
            query,
            language: language,
            enabled: enabled,
            composing: composing,
          ),
      clear: () => _titleSearch.clear(),
      titles: () => _titleSearch.value,
      open: (item) => _titleOpen.openSuggestedTitle(item),
      submit: (query) => _modeSection.onQuerySubmitted(query),
    ), _searchController);
    _titleOpen = SearchTitleOpen(
      (
        mode: () => _modeSection.mode,
        mounted: () => mounted,
        context: () => context,
        activeTab: () => MainPageBridge.activeTab.value,
        originCurrent: () => _titleSearchScope == ProfileRuntime.scope.value,
        cancelSubmitFocus: _searchSubmitFocus.cancel,
        cancelTitleSuggestions: _titleSection.cancelTitleSuggestions,
        openItem: (item, addon) => _itemActions.openItem(item, addon),
        resolver: () =>
            widget.suggestedTitleResolver ??
            MetadataTitleService.instance.resolve,
        submit: (query) => _modeSection.onQuerySubmitted(query),
      ),
      _searchController,
      _titleSection.presentation,
    );
    _catalogSection = CatalogSearchSection(ref, (
      session: () => _searchSession,
      bindings: () => _searchResultBindings,
      mounted: () => mounted,
      isTelevision: () => widget.isTelevision,
      searchField: () => _inputSection.searchFocusNode,
      applySections: _applySections,
      firstResult: () => _rowNodes.isNotEmpty && _rowNodes.first.isNotEmpty
          ? _rowNodes.first.first
          : null,
      completeSubmitFocus: (target) =>
          _inputSection.completeSearchSubmitFocus(target),
      cancelSubmitFocus: _searchSubmitFocus.cancel,
      catalogModeActive: () =>
          _modeSection.mode == SearchMode.catalog && widget.searchMode,
      focusSearch: () => _inputSection.focusSearchFieldAtEnd(),
      focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
      context: () => context,
    ));
    _modeSection = SearchModeSection(
      (
        mounted: () => mounted,
        setState: setState,
        isTelevision: () => widget.isTelevision,
        keywordAllowed: () =>
            ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
        cancelTitleSuggestions: _titleSection.cancelTitleSuggestions,
        restoreHome: _restoreHome,
        runCatalog: _catalogSection.runCatalogSearch,
        bindings: () => _searchResultBindings,
        runKeyword: _keywordSection.runKeyword,
        clearKeyword: _keywordSection.clearKeywordSearch,
        searchField: () => _inputSection.searchFocusNode,
        exitSelection: _keywordSelection.exitKwSelection,
      ),
      _searchController,
      _searchSubmitFocus,
      _listsSection,
    );
    _inputSection = SearchInputSection(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        mdblistEnabled: kMdblistEnabled,
        mdblistAuthenticated: () => _isMdblistAuthenticated,
        keywordAllowed: () =>
            ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
        focusContent: () => _inputSection.searchFocus.focusContent(
          discoverMode: widget.discoverMode,
          searchMode: widget.searchMode,
          isTelevision: widget.isTelevision,
          mode: _modeSection.mode,
          discoverSource: _discoverSection.discSourceNode,
          keywordToolbar: _keywordSection.kwToolbarVisible
              ? _keywordSection.kwToolbarNodes.first
              : null,
          listsResult:
              _listsSection.listsResults.isNotEmpty &&
                  _listsSection.listsNodes.isNotEmpty
              ? _listsSection.listsNodes.first
              : null,
          catalogResult:
              _catalogSection.catalogQuery.isNotEmpty &&
                  _rowNodes.isNotEmpty &&
                  _rowNodes.first.isNotEmpty
              ? _rowNodes.first.first
              : null,
          focusCatalogShelf: _spotlightSection.spotlightKey.currentState == null
              ? null
              : () =>
                    _spotlightSection.spotlightKey.currentState!.focusShelf(0),
          topBoardNode: _topBoardFocusNode,
          loading: _loading,
          focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
        ),
        focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
        fieldFocusContent: () {
          if (_keywordSection.kwSourcesButtonVisible) {
            _keywordSection.kwSourcesBtnFocus.requestFocus();
          } else if (_catalogSection.catalogSourcesButtonVisible) {
            _catalogSection.catalogSourcesBtnFocus.requestFocus();
          } else {
            _inputSection.focusContent();
          }
        },
        catalogSourcesButton: () =>
            _catalogSection.catalogSourcesButton(context),
        body: () => buildSearchModeContent(
          mode: _modeSection.mode,
          catalogSearching: _catalogSection.catalogSearching,
          catalogEmpty: _sections.isEmpty,
          dedicatedSearch: widget.searchMode,
          queryEmpty: _catalogSection.catalogQuery.isEmpty,
          keyword: () => _keywordRows.buildKeyword(context),
          lists: () => _listsRows.build(context),
          prompt: () => _catalogSection.buildSearchPrompt(context),
          board: _buildBoard,
        ),
      ),
      _modeSection,
      _searchController,
      _titleSection.presentation.suggestions,
      _searchSubmitFocus,
    );
    _listsRows = ListsSearchRows((
      state: () => _listsSection.listsState,
      nodes: () => _listsSection.listsNodes,
      isTelevision: () => widget.isTelevision,
      posterWidth: _railPosterW,
      header: (onSeeAll) =>
          _railHeader(title: 'MDBList Lists', tag: 'LISTS', onSeeAll: onSeeAll),
      message: (icon, title, body) => _message(icon, title, body),
      open: _listsSection.openListsResult,
      openSeeAll: _listsSection.openListsSeeAll,
      focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
      onUp: _leaveBoardTop,
    ));
    _playbackNavigation = HomePlaybackNavigation(ref, (
      mounted: () => mounted,
      profileCurrent: () =>
          _profileSessionOwner == ProfileSessionMemory.captureOwner(),
      context: () => context,
      isTelevision: () => widget.isTelevision,
      clearResume: _clearSeriesResume,
      refreshBoundSources: _refreshBoundSources,
      refreshAfterPlayback: ({trackers = false}) =>
          _continuationReturn.refreshAfterPlayback(trackers: trackers),
      imdbOf: _imdbOf,
      boundCountFor: _boundCountFor,
      editSource: (item, {isCurrent}) =>
          _sourceActions.editOrSelectSource(item, isCurrent: isCurrent),
    ));
    _catalogActions = HomeCatalogActions(ref, (
      mounted: () => mounted,
      profileCurrent: () =>
          _profileSessionOwner == ProfileSessionMemory.captureOwner(),
      context: () => context,
      session: () => _homeCatalogSession,
      imdbOf: _imdbOf,
      availability: () => (
        trakt: _isTraktAuthenticated,
        simkl: _isSimklAuthenticated,
        mdblist: _isMdblistAuthenticated,
      ),
      cachedTrakt: (item) =>
          _continuationSection.traktByImdb[item.progressId] ??
          _continuationSection.traktByImdb[item.id],
    ), _playbackNavigation);
    _sourceActions = HomeSourceActions(ref, (
      context: () => context,
      session: () => _homeCatalogSession,
      imdbOf: _imdbOf,
      refreshBindings: _refreshBoundSources,
    ), _playbackNavigation);
    _detailActions = HomeDetailActions(
      ref,
      (
        context: () => context,
        session: () => _homeCatalogSession,
        bridge: (route) => HomeDetailActionBridge(
          isCurrent: () =>
              _playbackNavigation.catalogNavigationCurrent() && route.isActive,
          isSearch: () => widget.searchMode,
          clearResume: _clearSeriesResume,
          refreshLocal: _continuationLoading.loadContinueWatching,
          refreshTrakt: () => _continuationLoading.loadTraktContinueWatching(
            refreshBound: false,
          ),
          refreshSimkl: () => _continuationLoading.loadSimklContinueWatching(
            refreshBound: false,
          ),
          refreshMdblist: () => _continuationLoading
              .loadMdblistContinueWatching(refreshBound: false),
        ),
        removeLocal: (action, id, route) =>
            _continuationRemoval.handleContinueDetailAction(action, id, route),
        removeTrakt: (id, {detailRoute}) => _continuationRemoval
            .removeFromTraktContinueWatching(id, detailRoute: detailRoute),
        removeMdblist: (item) => _continuationRemoval.removeMdblistCwItem(item),
        invokeSimkl: (item, action, detailRoute, presetRating) =>
            handleSimklMenuAction(
              context,
              item,
              action,
              actions: ref.read(
                homeDetailActionsProvider(_profileSessionOwner),
              ),
              presetRating: presetRating,
              isCurrent: () =>
                  _playbackNavigation.catalogNavigationCurrent() &&
                  detailRoute.isActive,
              removeContinueWatching: () => ref
                  .read(homeSimklHistoryRemovalProvider(_profileSessionOwner))
                  .remove(
                    item.progressId ?? item.id,
                    item.type,
                    isCurrent: () =>
                        _playbackNavigation.catalogNavigationCurrent() &&
                        detailRoute.isActive,
                  ),
            ),
        invokeMdblist: (item, action, detailRoute, presetRating) =>
            handleMdblistMenuAction(
              context,
              item,
              action,
              actions: ref.read(
                homeDetailActionsProvider(_profileSessionOwner),
              ),
              presetRating: presetRating,
              isCurrent: () =>
                  _playbackNavigation.catalogNavigationCurrent() &&
                  detailRoute.isActive,
            ),
      ),
      _playbackNavigation,
      _catalogActions,
      _sourceActions,
    );
    _itemActions = HomeItemActions(
      ref,
      (
        context: () => context,
        session: () => _homeCatalogSession,
        isTelevision: () => widget.isTelevision,
        pikpakOnly: () => _pikpakOnly,
        mergedSeriesPage: () => _mergedSeriesPage,
        imdbOf: _imdbOf,
        cwIds: () => _continuationSection.cwIds,
        removeLocalHistory: (id) => _continuationRemoval.removeLocalHistory(id),
        onHistoryRemoved: () async {
          _clearSeriesResume();
          await _continuationLoading.loadContinueWatching();
        },
        onClosed: (returnToTabOnClose) {
          unawaited(_continuationReturn.refreshAfterPlayback());
          _refreshTraktAuthState();
          _refreshSimklAuthState();
          _refreshMdblistAuthState();
          if (returnToTabOnClose != null) {
            MainPageBridge.switchTab?.call(returnToTabOnClose);
          }
        },
        menus: (item, imdb, inCw) {
          // Same for the Trakt Continue Watching rows — removal goes through the
          // Trakt playback/history APIs rather than local storage.
          final inTraktCw =
              imdb != null &&
              _continuationSection.traktByImdb.containsKey(imdb);
          final inMdblistCw =
              imdb != null &&
              _continuationSection.mdblistByImdb[imdb]?.paused == true;

          return HomeDetailMenus(
            type: item.type,
            identity: imdb,
            removalColor: AppThemeScope.of(context).home.danger,
            inLocalContinueWatching: inCw,
            inTraktContinueWatching: inTraktCw,
            inMdblistContinueWatching: inMdblistCw,
            hasBoundSource: () => _isBound(item),
            traktAuthenticated: () => _isTraktAuthenticated,
            simklAuthenticated: () => _isSimklAuthenticated,
            mdblistAuthenticated: () => _isMdblistAuthenticated,
            hasSimklPause: () =>
                _continuationSection
                    .simklByImdb[_continuationSection.simklCardKey(item)]
                    ?.progress !=
                null,
          );
        },
        boundCountFor: _boundCountFor,
      ),
      _playbackNavigation,
      _catalogActions,
      _detailActions,
      _sourceActions,
    );
    _playlistActions = HomePlaylistActions((
      mounted: () => mounted,
      context: () => context,
      controller: () => _savedSection.playlistController,
      reload: () => _savedSection.loadPlaylistFavorites(),
      play: PlaylistPlayerService.play,
    ));
    _savedSection = HomeSavedContentSection((
      bindings: () => _favoriteBindings,
      mounted: () => mounted,
      setState: setState,
      disabled: () => _homeDisabled,
      autoFocus: _maybeAutoFocusBoard,
      focusContent: _inputSection.focusContent,
      requestRowFocus: _requestRowFocus,
      debrifyTvAllowed: () =>
          ProfilePolicyGuard.allowsSync(ProfileFeature.debrifyTv),
      stremioTvAllowed: () =>
          ProfilePolicyGuard.allowsSync(ProfileFeature.stremioTv),
      iptvAllowed: () => ProfilePolicyGuard.allowsSync(ProfileFeature.iptv),
      iptvListId: HomeExtraRowIds.iptvList,
      playChannel: (channel) {
        if (MainPageBridge.watchDebrifyTvChannel != null) {
          MainPageBridge.watchDebrifyTvChannel!(channel.id);
          return;
        }
        MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channel.id);
        MainPageBridge.switchTab?.call(MainTab.debrifyTv);
      },
      playStremio: (channel) {
        if (MainPageBridge.watchStremioTvChannel != null) {
          MainPageBridge.watchStremioTvChannel!(channel.id);
          return;
        }
        MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
        MainPageBridge.switchTab?.call(MainTab.stremioTv);
      },
    ), _catalogSection);
    _savedIptv = HomeSavedIptvActions((
      mounted: () => mounted,
      context: () => context,
      isTelevision: () => widget.isTelevision,
      launch: (context, videoUrl, channel, isStremio) {
        VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: videoUrl,
            title: channel.name,
            subtitle: channel.group ?? 'IPTV',
            viewMode: PlaylistViewMode.sorted,
            // Identify the launch as IPTV for plain channels too (only the
            // Stremio branch used to): it routes playback down the live path
            // and lets the player report a dead stream instead of sitting on a
            // black screen.
            iptvChannels: [channel],
            iptvStartIndex: 0,
            // Playlist-declared headers (+ browser UA fallback) for the launch
            // channel; Stremio-addon links keep the addon's own defaults.
            httpHeaders: isStremio ? null : channel.playbackHeaders,
          ),
        );
      },
    ));
    _watchlistActions = HomeWatchlistActions(
      (
        mounted: () => mounted,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        remove: (item) => StorageService.setMyWatchlistItem(item, false),
        reload: _savedSection.loadMyWatchlist,
        addonForContinue: _addonForContinue,
        refreshAfterPlayback: ({trackers = false}) =>
            _continuationReturn.refreshAfterPlayback(trackers: trackers),
      ),
      _savedIptv,
      _itemActions,
    );
    _savedRows = HomeSavedContentRows(
      (
        classicRows: (rowId, nodes) => HomeClassicFavoriteRows(
          context: context,
          isTelevision: widget.isTelevision,
          posterWidth: _railPosterW(context),
          captionBand: _displaySection.homeArtPosterCaptionBand,
          showTitle: () => !_displaySection.hideHomeCardTitlesAndRatings,
          nodes: nodes,
          up: (col) => _favRowOnUp(rowId, col),
          down: (col) => _favRowOnDown(rowId, col),
          sidebar: () => MainPageBridge.focusTvSidebar?.call(),
          clearLive: _heroLive.clearHeroLiveIptv,
          previewLive: _heroLive.setHeroLiveIptv,
        ),
        playChannel: _savedSection.playChannel,
        playStremio: _savedSection.playStremioTvChannel,
        playIptv: _savedIptv.playIptvChannel,
        playIptvList: _savedIptv.playIptvListChannel,
        openWatchlist: _watchlistActions.openMyWatchlistItem,
      ),
      _savedSection,
      _playlistActions,
    );
    _continuationSection = HomeContinuationSection((
      bindings: () => _continuationBindings,
      artwork: () => _homeBoardBindings.artwork,
      mounted: () => mounted,
      setState: setState,
    ));
    _continuationAnnouncements = HomeContinuationAnnouncements(
      (
        mounted: () => mounted,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        loading: () => _loading,
        activeTab: () => MainPageBridge.activeTvTabIndex == _tabIndex,
        context: () => context,
        disabled: () => _homeDisabled,
        rowNodes: () => _rowNodes,
      ),
      _continuationSection,
      _savedSection,
    );
    _continuationLoading = HomeContinuationLoading(
      (
        mounted: () => mounted,
        setState: setState,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        context: () => context,
        requestRowFocus: _requestRowFocus,
        autoFocus: _maybeAutoFocusBoard,
        announceTrakt: _continuationAnnouncements.maybeAnnounceTraktRows,
        announceSimkl: _continuationAnnouncements.maybeAnnounceSimklRows,
        announceMdblist: _continuationAnnouncements.maybeAnnounceMdblistRows,
        refreshBound: _refreshBoundSources,
      ),
      _continuationSection,
      kMdblistEnabled,
    );
    _continuationPlayback = HomeContinuationPlayback(
      (
        context: () => context,
        isTelevision: () => widget.isTelevision,
        addonForContinue: _addonForContinue,
        imdbOf: _imdbOf,
        markPlaybackStarted: () => _continuationReturn.markPlaybackStarted(),
        refreshAfterPlayback: ({trackers = false}) =>
            _continuationReturn.refreshAfterPlayback(trackers: trackers),
        openIptv: IptvCwRouter.open,
      ),
      _continuationSection,
      _playbackNavigation,
      _catalogActions,
      _itemActions,
    );
    _continuationRemoval = HomeContinuationRemoval(
      ref,
      (
        mounted: () => mounted,
        profileCurrent: () =>
            _profileSessionOwner == ProfileSessionMemory.captureOwner(),
        session: () => _homeCatalogSession,
        imdbOf: _imdbOf,
        removeSimkl: (item) => handleSimklMenuAction(
          context,
          item,
          SimklItemMenuAction.removeFromContinueWatching,
          isCurrent: _playbackNavigation.catalogNavigationCurrent,
          removeContinueWatching: () => ref
              .read(homeSimklHistoryRemovalProvider(_profileSessionOwner))
              .remove(
                item.progressId ?? item.id,
                item.type,
                isCurrent: _playbackNavigation.catalogNavigationCurrent,
              ),
        ),
      ),
      _continuationSection,
      _continuationLoading,
      _playbackNavigation,
    );
    _continuationProjection = HomeContinuationProjection(
      (
        disabled: () => _homeDisabled,
        openLocal: (category) =>
            _continuationSeeAll.openContinueWatchingSeeAll(category),
        openTrakt: (category) => _continuationSeeAll.openTraktSeeAll(category),
        openSimkl: (category) =>
            _continuationSeeAll.openSimklCwSeeAll(category),
        openMdblist: (category) =>
            _continuationSeeAll.openMdblistCwSeeAll(category),
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        traktAuthenticated: () => _isTraktAuthenticated,
      ),
      _continuationSection,
      _continuationPlayback,
      _continuationRemoval,
      _catalogSection,
    );
    _continuationMenu = HomeContinuationMenu(
      ref,
      (
        context: () => context,
        isTelevision: () => widget.isTelevision,
        pikpakOnly: () => _pikpakOnly,
        session: () => _homeCatalogSession,
        requestRowFocus: _requestRowFocus,
        leaveBoardTop: _leaveBoardTop,
      ),
      _continuationProjection,
      _playbackNavigation,
    );
    _continuationRows = HomeContinuationRows(
      (
        header: ({required title, tag, onSeeAll}) =>
            _railHeader(title: title, tag: tag, onSeeAll: onSeeAll),
        isTelevision: () => widget.isTelevision,
        posterWidth: () => _railTitleCardW(context),
        cellHeight: () => _railTitleCardH(context),
        aspectRatio: () => _stageGeometry.titleCardAspect,
        showTitleOverlay: () => !_displaySection.hideHomeCardTitlesAndRatings,
        artOf: (item) => _stageGeometry.titleArtUrl(item),
        isBound: _isBound,
        sidebar: () => MainPageBridge.focusTvSidebar?.call(),
        onFocused: (item) => _heroSection.setHero(item),
        focusRelativeRail: _focusRelativeHomeRail,
      ),
      _continuationSection,
      _continuationMenu,
    );
    _continuationReturn = HomeContinuationReturn(
      (
        controller: () => _homeBoardBindings.playbackRefresh,
        mounted: () => mounted,
        searchMode: () => widget.searchMode,
        context: () => context,
        traktAuthenticated: () => _isTraktAuthenticated,
        clearResume: _clearSeriesResume,
        refreshBound: _refreshBoundSources,
      ),
      _continuationSection,
      _continuationLoading,
      _savedSection,
    );
    _continuationSeeAll = HomeContinuationSeeAll(
      (
        context: () => context,
        navigation: () => _seeAllNavigation,
        pikpakOnly: () => _pikpakOnly,
      ),
      _continuationSection,
      _continuationPlayback,
      _continuationLoading,
      _continuationReturn,
    );
    _heroSection = HomeHeroSection(
      (
        media: () => _homeMediaBindings,
        mounted: () => mounted,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        stageActive: () => _displaySection.stageActive,
        stagePublishesShellArt: () => _displaySection.stagePublishesShellArt,
        clearFavoriteFocus: () => _stageFavorites.canvasFavFocus.value = null,
        preview: () => _heroPreview,
        clearLive: () => _heroLive.clearHeroLiveIptv(),
      ),
      MainPageBridge.tvAmbientArt,
      MainPageBridge.tvHeroTint,
    );
    _heroPreview = HomeHeroPreview((
      media: () => _homeMediaBindings,
      mounted: () => mounted,
      setState: setState,
      context: () => context,
      isTelevision: () => widget.isTelevision,
      searchMode: () => widget.searchMode,
      discoverMode: () => widget.discoverMode,
      stageActive: () => _displaySection.stageActive,
      stageWantsAmbient: () => _displaySection.stageWantsAmbient,
      homeStyle: () => _displaySection.homeStyleEffective,
      hasFavoriteFocus: () => _stageFavorites.canvasFavFocus.value != null,
      hasLiveChannel: () => _heroLive.heroLiveChannel.value != null,
      spotlightHeroId: () =>
          _spotlightSection.spotlightKey.currentState?.currentHeroId,
    ), _heroSection.heroItem);
    _heroLive = HomeHeroLive(
      (media: () => _homeMediaBindings, mounted: () => mounted),
      _heroSection,
      _heroPreview,
      MainPageBridge.tvAmbientArt,
      MainPageBridge.tvHeroTint,
    );
    _heroShell = HomeHeroShell(
      _heroPreview,
      MainPageBridge.tvChromeDim,
      MainPageBridge.tvStageLightsOff,
    );
    _displaySection = HomeDisplaySection(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        spotlightShellActive: () => _spotlightShell.spotlightShellActive,
        searchSheetOpen: () => _spotlightShell.searchSheetOpen,
        resetStageNavigation: () => _stageSection.resetStageNavigation(),
      ),
      _heroSection,
      _heroPreview,
      _heroLive,
      MainPageBridge.tvAmbientArt,
    );
    _spotlightSection = HomeSpotlightSection((
      mounted: () => mounted,
      setState: setState,
      searchMode: () => widget.searchMode,
      discoverMode: () => widget.discoverMode,
      heroSource: () => _heroSource,
      sections: () => _sections,
      repository: () => ref.read(homeCatalogRepositoryProvider),
      publishTopShelf: (items, {sourceTitle}) => TvosTopShelfService.instance
          .publishSpotlight(items, sourceTitle: sourceTitle),
    ), _catalogSection);
    _spotlightShell = SearchSpotlightShell(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        rawStyle: () => _displaySection.tvHomeStyle,
        loading: () => _loading,
        hasHero: () => _spotlightSection.spotlightHero.isNotEmpty,
      ),
      _searchController,
      _inputSection,
      _modeSection,
      _catalogSection,
    );
    _stageRailsSection = HomeStageRails(
      (
        sections: () => _sections,
        rowNodes: () => _rowNodes,
        orderActive: () => _homeRowOrderActive,
        order: () => _effectiveHomeRowOrder,
        disabled: () => _homeDisabled,
        sectionRowId: _sectionRowId,
        style: () => _displaySection.homeStyleEffective,
        hideCollectionNames: () => _displaySection.hideHomeCollectionNames,
        sectionTag: _sectionTag,
      ),
      _continuationProjection,
      _continuationSection,
      _savedSection,
    );
    _stageSection = HomeStageSection(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        clearFavoriteFocus: () => _stageFavorites.canvasFavFocus.value = null,
        rowsPending: () => _boardRowsPending,
        canAdvance: () => _boardCanAdvance,
        focusContinuation: _focusCatalogContinuation,
        loadMore: _loadMoreBoard,
      ),
      _stageRailsSection,
      _displaySection,
      _heroPreview,
      _spotlightSection,
      _pendingDownMaxAge,
    );
    _stageFavorites = HomeStageFavorites(
      _stageSection,
      _displaySection,
      _heroSection,
      _heroPreview,
      _heroLive,
      _savedSection,
      _savedIptv,
      _watchlistActions,
      _playlistActions,
      () => MainPageBridge.focusTvSidebar?.call(),
    );
    _stageGeometry = HomeStageGeometry(_displaySection, () => _sections);
    _stageCells = HomeStageCells(
      (
        sectionAt: (index) => _sections[index],
        isBound: _isBound,
        pikpakOnly: () => _pikpakOnly,
        openSection: _sectionOpenItem,
        playSection: _sectionQuickPlay,
        sidebar: () => MainPageBridge.focusTvSidebar?.call(),
        loadMore: _loadMoreRow,
      ),
      _stageGeometry,
      _stageSection,
      _stageFavorites,
      _heroSection,
      _continuationMenu,
    );
    _stageBoards = HomeStageBoards(
      (
        context: () => context,
        isTelevision: () => widget.isTelevision,
        media: () => _boardMedia,
      ),
      _stageSection,
      _stageRailsSection,
      _stageGeometry,
      _stageCells,
      _stageFavorites,
      _displaySection,
      _heroPreview,
    );
    _atriumLayout = HomeAtriumSection(
      (
        context: () => context,
        isTelevision: () => widget.isTelevision,
        media: () => _boardMedia,
        canAdvance: () => _boardCanAdvance,
        loadMore: _loadMoreBoard,
      ),
      _stageSection,
      _stageRailsSection,
      _stageGeometry,
      _stageCells,
      _stageFavorites,
      _displaySection,
      _heroPreview,
    );
    _tonightLayout = HomeTonightSection(
      (
        context: () => context,
        isTelevision: () => widget.isTelevision,
        media: () => _boardMedia,
        sidebar: () => MainPageBridge.focusTvSidebar?.call(),
        isBound: _isBound,
      ),
      _stageSection,
      _stageRailsSection,
      _stageGeometry,
      _stageCells,
      _stageFavorites,
      _heroPreview,
      _heroSection,
      _continuationMenu,
    );
    _spotlightRows = HomeSpotlightRows(
      (
        sections: () => _sections,
        rowNodes: () => _rowNodes,
        catalogTag: _catalogSourceTag,
        seeAll: _openCatalogSeeAll,
        openCollection: _openCollectionFolder,
      ),
      _stageRailsSection,
      _stageSection,
      _displaySection,
      _continuationMenu,
      _stageFavorites,
      _itemActions,
    );
    _spotlightResults = SearchSpotlightResults(
      (
        context: () => context,
        sections: () => _sections,
        rowNodes: () => _rowNodes,
        failures: () => _catalogSearchFailures,
        leaveTop: _leaveBoardTop,
        openSection: _sectionOpenItem,
        pikpakOnly: () => _pikpakOnly,
        catalogTag: _catalogSourceTag,
        seeAll: _openCatalogSeeAll,
        loadMoreRow: _loadMoreRow,
      ),
      _catalogSection,
      _displaySection,
      _heroPreview,
      _spotlightSection,
      _itemActions,
      _catalogActions,
    );
    _spotlightBoards = HomeSpotlightBoards(
      (
        mounted: () => mounted,
        isTelevision: () => widget.isTelevision,
        loadMoreRow: _loadMoreRow,
        loadMore: _loadMoreBoard,
        rowsPending: () => _boardRowsPending,
        media: () => _boardMedia,
      ),
      _stageRailsSection,
      _displaySection,
      _heroPreview,
      _spotlightSection,
      _itemActions,
      _spotlightRows,
      MainPageBridge.tvAmbientArt,
      MainPageBridge.tvHeroTint,
    );
    _titleSearch.addListener(_titleSection.publishTitleSuggestions);
    _searchController.addListener(_titleSection.onTitleSearchEditingChanged);
    ProfileRuntime.scope.addListener(_onSearchProfileChanged);
    MetadataPreferencesService.revision.addListener(_metadataSettingsChanged);
    final metadataSession = (
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    _metadataFeatureSubscription = ref.listenManual(
      metadataFeaturePolicyProvider(metadataSession),
      (previous, next) {},
    );
    _metadataFeatureController = ref.read(
      metadataFeaturePolicyProvider(metadataSession).notifier,
    );
    unawaited(_refreshMetadataFeaturePolicy());
    WidgetsBinding.instance.addObserver(this);
    _profileSessionOwner = ProfileSessionMemory.captureOwner();
    _homeReturnRepository = ref.read(
      homeReturnRepositoryProvider(_profileSessionOwner),
    );
    _homeCollectionsRepository = ref.read(homeCollectionsRepositoryProvider);
    _keywordSnapshots = ref.read(
      keywordSnapshotRepositoryProvider(_profileSessionOwner),
    );
    final keywordSnapshot = _keywordReturn.take();
    _searchSession = SearchSession(
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initialKeywordQuery: keywordSnapshot?.query ?? '',
      initialKeywordResults: keywordSnapshot?.projection,
      initialKeywordCache:
          keywordSnapshot?.cache ?? const KeywordCacheState.empty(),
    );
    _keywordSection.startAppearance();
    unawaited(_keywordSection.loadSourceTextFormatting());
    // Retain state for this screen's mounted lifetime, including covered routes.
    // Returning from a pushed list must not discard results or replay a request.
    _searchResultBindings = SearchResultBindings(
      ref,
      _searchSession,
      isCurrent: () => mounted,
      isTelevision: () => widget.isTelevision,
      onChanged: () => setState(() {}),
      replaceRows: _applySections,
      appendRows: _appendSections,
      presentKeyword: _keywordSection.presentKwStreaming,
      finishKeyword: _keywordSection.finishKeyword,
      cancelSubmitFocus: _searchSubmitFocus.cancel,
    );
    if (!widget.searchMode && !widget.discoverMode) {
      _homeReturnRepository.observeInvalidation();
    }
    final homeSnapshot = !widget.searchMode && !widget.discoverMode
        ? _homeReturnRepository.take()
        : null;
    final restoredHome = homeSnapshot != null &&
        homeSnapshot.configuration.hideWatched == HideWatchedPrefs.enabled;
    // Seed cached state in provider construction so the first return frame
    // does not mutate a provider during initState or wait for another frame.
    final homeSession = HomeCatalogSession(
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initialBoard: restoredHome && keywordSnapshot == null
          ? homeSnapshot.board : null,
      initialConfiguration: restoredHome && keywordSnapshot == null
          ? homeSnapshot.configuration : _initialHomeConfiguration,
      initialRows: restoredHome && keywordSnapshot == null
          ? homeSnapshot.sections : const [],
      initiallyRefreshing: !widget.searchMode && !widget.discoverMode &&
          !(restoredHome && keywordSnapshot == null),
    );
    _homeCatalogSession = homeSession;
    _homeBoardBindings = HomeBoardBindings(
      ref,
      homeSession,
      isCurrent: () => mounted,
      onContinuationChanged: () => setState(() {}),
    );
    _homeMediaBindings = HomeMediaBindings(ref, homeSession);
    _displaySection.homeLayoutPreferenceSubscription = ref.listenManual(
      homeLayoutPreferenceProvider(homeSession),
      (previous, next) {},
    );
    _displaySection.tvHomeStyle = _displaySection
        .homeLayoutPreferenceSubscription
        .read()
        .initialStyle;
    _heroPreview.startPreferences(ref, homeSession);
    _homeDefaultViewSubscription = ref.listenManual(
      homeDefaultViewProvider(homeSession),
      (previous, next) {},
    );
    final displaySession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initial: restoredHome && keywordSnapshot == null
          ? (
              orientation: homeSnapshot.cardOrientation,
              hideTitlesAndRatings: homeSnapshot.hideCardTitlesAndRatings,
              hideCatalogAddonNames: homeSnapshot.hideCatalogAddonNames,
              hideCollectionNames: homeSnapshot.hideCollectionNames,
              spotlightFocusDetails: false,
              animationsEnabled: false,
              animationStyle: 'snowy_mountain',
            )
          : initialHomeDisplayPreferences,
    );
    _displaySection.homeDisplaySubscription = ref.listenManual(
      homeDisplayPreferencesProvider(displaySession),
      (previous, next) {},
    );
    _displaySection.homeDisplayController = ref.read(
      homeDisplayPreferencesProvider(displaySession).notifier,
    );
    _favoriteBindings = HomeFavoriteBindings(
      ref,
      newSession: () => (owner: _profileSessionOwner, viewIdentity: Object()),
    );
    final localContinuationSession = HomeContinuationSession(
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _continuationBindings = HomeContinuationBindings(
      ref,
      localContinuationSession,
      initiallyLoadingTrakt: !widget.searchMode,
    );
    _homeLastScroll = restoredHome && !widget.isTelevision
        ? homeSnapshot.scrollOffset : 0;
    _boardViewport.initializeScroll(_homeLastScroll);
    // This one widget backs three tabs (Home board / dedicated Search / Discover).
    AnalyticsService.screenView(
      widget.searchMode
          ? 'search'
          : widget.discoverMode
          ? 'discover'
          : 'home',
    );
    MainPageBridge.registerTvContentFocusHandler(
      _tabIndex,
      _inputSection.focusContent,
    );
    if (!widget.searchMode && !widget.discoverMode) {
      StorageService.localCompletionRevision.addListener(
        _continuationLoading.onLocalCompletionChanged,
      );
      MdblistService.instance.playbackRevision.addListener(
        _continuationLoading.onMdblistPlaybackRevision,
      );
      MainPageBridge.addPlaylistChangeListener(
        _savedSection.loadPlaylistFavorites,
      );
    }
    if (widget.searchMode) {
      MainPageBridge.registerTabBackHandler(
        'search',
        _modeSection.handleSearchBack,
      );
      MainPageBridge.activeTab.addListener(
        _titleSection.onTitleSearchTabChanged,
      );
    }
    // A detail-open handed off from another tab (e.g. the Trakt Calendar, a
    // separate tab that can't reach this screen's state). Only the Home board
    // (not the Search/Discover variants) claims it; the opener switches here via
    // switchTab(15) right after setting it, so it's present by the time we mount.
    if (!widget.searchMode && !widget.discoverMode) {
      MainPageBridge.registerCatalogDetailOpenHandler(
        _openPendingCatalogDetail,
      );
      final pending = MainPageBridge.pendingCatalogDetailOpen;
      if (pending != null) {
        MainPageBridge.pendingCatalogDetailOpen = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openPendingCatalogDetail(pending));
        });
      }
    }
    // An MDBList list handed off from the Search tab's Lists mode: start the
    // Discover tab on the MDBList source, focused on that list. The nav
    // rebuilds this screen fresh on every tab switch, so the payload set right
    // before switchTab(18) is present by the time we mount.
    if (widget.discoverMode) {
      final pending = MainPageBridge.pendingMdblistListOpen;
      if (pending != null) {
        MainPageBridge.pendingMdblistListOpen = null;
        _discoverSection.discMdblistList = MdblistListChoice(
          id: (pending['id'] as num?)?.toInt() ?? -1,
          name: pending['name'] as String? ?? 'Untitled list',
          ownerName: pending['ownerName'] as String?,
          itemCount: (pending['itemCount'] as num?)?.toInt() ?? 0,
          liked: pending['liked'] == true,
          likes: (pending['likes'] as num?)?.toInt() ?? 0,
        );
      }
    }
    final discoverSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initialSource: _discoverSection.discMdblistList == null
          ? _discCw
          : _discMdblist,
      hasHandoff: _discoverSection.discMdblistList != null,
    );
    _discoverBindings = DiscoverBindings(ref, discoverSession);
    if (_discoverSection.discMdblistList != null) {
      unawaited(
        _discoverSection.discoverSourceController.rememberCurrent(
          isCurrent: () => mounted,
        ),
      );
    }
    _heroShell.start(this);
    // Discover on TV: relay the trailer takeover to the sidebar chrome-dim so
    // the rail hides when the trailer goes fullscreen. The showing listener
    // arms the theater timer (deep lights-off a few seconds into playback).
    if (widget.discoverMode) {
      _discoverSection.startShell();
    }
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    // Playback that ran in a separate ACTIVITY (Android TV native player,
    // DeoVR, external app) pushes no Flutter route, so nothing on the board
    // ever learns it ended — the Continue Watching rows would keep showing the
    // episode the user just finished. This is that missing signal.
    MainPageBridge.addPlaybackReturnListener(
      _continuationReturn.onPlaybackReturned,
    );
    // Unconditional (the _heroPreview.heroTrailerActive block below registers its own
    // trailer-suppression listener; this one is just the latch that tells the
    // post-playback refresh whether anything was actually played).
    MainPageBridge.addPlayerLaunchListener(
      _continuationReturn.markPlaybackStarted,
    );
    if (widget.isTelevision && widget.searchMode) {
      _reloadSearchCardPrefs();
      MainPageBridge.addHomeSettingsListener(_reloadSearchCardPrefs);
    }
    // Restore a keyword search preserved from a prior tab visit (results +
    // scroll) BEFORE the async default-view load below can start: restoration
    // sets keyword mode synchronously, and a later-resolving catalog default
    // would flip the mode back and could fire a catalog search with the
    // restored keyword text. A successful restore therefore also suppresses
    // the default-view load outright.
    final restoredKeyword = _keywordReturn.restore(keywordSnapshot);
    // Home board only: live-refresh when the Home Rows manager changes which
    // rows are hidden. The bridge also invalidates a saved return snapshot.
    if (!widget.searchMode && !widget.discoverMode) {
      MainPageBridge.addHomeSettingsListener(_reloadForHomeSettings);
      HomeRowRefreshSignal.addListener(_queueHomeRows);
      _stremio.addAddonsChangedListener(_onHomeAddonsChanged);
      // IPTV list mutations (picker, IPTV settings, provider deletion,
      // reconcile, import) all bump the store revision — the only signal a
      // Home that stays alive across tab switches gets about them.
      IptvMediaStore.listsRevision.addListener(
        _savedSection.onIptvListsRevision,
      );
      if (!restoredKeyword) unawaited(_loadHomeDefaultView());
      // Home layout pref: loaded once here, then live-reloaded whenever the
      // Settings picker fires the bridge. HOME board instance only — the
      // Search tab keeps classic and must not steal the single bridge slot.
      // EVERY platform now: off-TV the pref decides Classic vs Spotlight,
      // and without this load the off-TV field would sit on its 'canvas'
      // initial forever (resolved to classic) whatever was chosen.
      unawaited(_displaySection.loadTvHomeStyle());
      unawaited(_displaySection.loadHomeCardOrientation());
      MainPageBridge.tvHomeStyleChanged = _displaySection.onTvHomeStyleChanged;
      if (widget.isTelevision) {
        MainPageBridge.tvHeroArtworkQualityChanged =
            _displaySection.onTvHeroArtworkQualityChanged;
        // Canvas theater mode: a dwell after trailer frames land recedes the
        // shelf so the video owns the screen; any key wakes it. Observe-only
        // handler (the key still performs its normal action) — same rule as
        // _heroPreview.onTakeoverKey.
        _heroPreview.heroTrailerShowing.addListener(
          _stageSection.onCanvasTrailerShowingChanged,
        );
        HardwareKeyboard.instance.addHandler(_stageSection.onCanvasTheaterKey);
        HardwareKeyboard.instance.addHandler(
          _stageSection.stageHold.handleKeyEvent,
        );
      } else {
        // Off-TV Home: system Back closes the Spotlight search sheet before
        // anything else may handle it. Routed through the bridge's tab-back
        // mechanism — a nested PopScope would race the root scope in
        // main.dart (its didPop==false path continues into double-back-exit
        // arming even when an inner scope consumed the press).
        MainPageBridge.registerTabBackHandler(
          'home',
          _spotlightShell.searchSheet.close,
        );
        // Restored keyword results must come back with the sheet open — the
        // full-bleed shell would otherwise hide them behind a hero.
        if (restoredKeyword) _spotlightShell.searchSheet.restore();
        // Hero trailer prefs for the OFF-TV Spotlight reel. Only the pieces
        // that mean "resolve and paint a video" — none of the TV shell
        // machinery the _heroPreview.heroTrailerActive block registers.
        MainPageBridge.addPlayerLaunchListener(
          _heroPreview.onContentPlayerLaunch,
        );
        unawaited(_heroPreview.reloadHeroTrailerPrefs());
      }
    }
    // Unified (non-TV) layout: drive the catalog Sources bar off search-field
    // focus, with a delayed hide so clicking the button doesn't yank it away
    // before the tap lands (blurring the field would otherwise unmount it
    // mid-click). See _inputSection.buildUnifiedCatalogSourcesBar.
    if (!widget.isTelevision && !widget.searchMode) {
      _inputSection.searchFocusNode.addListener(
        _inputSection.onSearchFocusForSources,
      );
    }
    // The focus latch: interacting with the field pins the sheet open, even
    // while the Spotlight shell is not yet eligible — an async style/hero
    // arrival can then never unmount a focused (still blank) field.
    if (!widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      _inputSection.searchFocusNode.addListener(
        _spotlightShell.searchSheet.onFocusChanged,
      );
    }
    _boardScroll.addListener(_onBoardScroll);
    _keywordSection.keywordViewport.observeScroll();
    _refreshTraktAuthState();
    _refreshSimklAuthState();
    _refreshMdblistAuthState();
    _loadMergedSeriesFlag();
    // (The keyword restore itself ran earlier — before _loadHomeDefaultView —
    // see the ordering comment there.) A restored search carries its own
    // filters, so don't overwrite them with the saved defaults.
    if (!restoredKeyword) {
      unawaited(_keywordSection.loadDefaultKeywordFilters());
    }
    // The dedicated Search tab only shows a field + blank prompt until a query,
    // so it skips the whole board pipeline (home catalogs, Continue Watching,
    // Trakt, favourites) — catalog search fetches its addons on demand. It also
    // never runs _load(), which is what clears _loading, so clear it here or the
    // results grid (_buildBoard) would sit on its initial spinner forever.
    if (widget.searchMode) {
      _loading = false;
    } else if (widget.discoverMode) {
      // Discover browses one source at a time via the Source dropdown, so it
      // skips the board's catalog pipeline and just primes the Continue Watching
      // + Trakt rows its first two sources draw from. _refreshPikpakOnly gates the
      // Quick-Play affordance the same way the board does.
      _loading = false;
      _refreshPikpakOnly();
      _discoverLoading.loadAddons();
      _discoverLoading.primeRows();
    } else {
      // TV board: last-resort focus reclaim. Several load/reload paths dispose
      // FocusNodes wholesale (_applySections rebuilds every catalog row's
      // nodes; CW rows re-sync after playback) and any of them can kill the
      // node holding primary focus — leaving the remote dead with no DPAD
      // press able to recover (the shell's recovery only fires when the scope
      // has NO traversable descendants, and the board always has plenty).
      // Watch the FocusManager and re-anchor onto the board when focus dies.
      if (widget.isTelevision) {
        FocusManager.instance.addListener(_onGlobalFocusChange);
      }
      // Kick off every leading-content load. Auto-focus settles to the top as
      // these complete; once they've ALL settled the arrival window is over and
      // re-anchoring latches off (see [_settleAutoFocusAfter]), so a later
      // background reload or a return from playback never yanks focus.
      _settleAutoFocusAfter([
        if (restoredHome && !restoredKeyword)
          _restoreHomeSnapshot(homeSnapshot)
        else
          _load(),
        _continuationLoading.loadContinueWatching(),
        _continuationLoading.loadTraktContinueWatching(),
        // refreshBound:false — _load()'s bound-source scan (which now covers the
        // Simkl rows) runs after this on cold start, so a 2nd concurrent scan
        // here would be pure duplicate startup work on weak TV hardware.
        _continuationLoading.loadSimklContinueWatching(refreshBound: false),
        _continuationLoading.loadMdblistContinueWatching(refreshBound: false),
        _continuationLoading.loadIptvContinueWatching(),
        _savedSection.loadTvFavorites(),
        _savedSection.loadStremioTvFavorites(),
        _savedSection.loadIptvFavorites(),
        _savedSection.loadMyWatchlist(),
        _savedSection.loadIptvListRows(),
        _savedSection.loadPlaylistFavorites(),
      ]);
    }
  }

  /// Await the initial board content loads, then end the auto-focus "arrival
  /// window": one final placement pass, then latch [_autoFocusSettled] so
  /// re-anchoring never fires again (a background CW/Trakt refresh, or focus
  /// restoration after returning from playback, must not move the user's focus).
  Future<void> _settleAutoFocusAfter(List<Future<void>> loads) async {
    await Future.wait(loads.map((f) => f.catchError((_) {})));
    if (!mounted) return;
    _maybeAutoFocusBoard();
    // Latch on the following frame so the placement pass above runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoFocusSettled = true;
    });
  }

  /// Re-read hero trailer prefs when Home survives Settings or a WebDAV
  /// update. TV also needs the live read now that trailer volume can sync
  /// without switching tabs. The existing audio/enable gates remain local.
  ///
  /// Sound/volume read the DETAIL surface keys off-TV: that is the pair the
  /// settings page has always shown on these platforms, so a stored "sound
  /// off" keeps meaning what it meant. Writes go to both surfaces now, so
  /// the pairs converge on first change.
  void _reloadSearchCardPrefs() {
    unawaited(_displaySection.loadHomeCardOrientation());
    unawaited(_heroPreview.reloadHeroTrailerPrefs());
  }

  /// An integration (Trakt / a debrid provider) was connected or disconnected
  /// elsewhere while this tab stayed alive — refresh the state that gates the
  /// detail quick actions, the PikPak-only Play hiding, and the Trakt rows.
  void _onIntegrationsChanged() {
    _refreshTraktAuthState();
    _refreshSimklAuthState();
    _refreshMdblistAuthState();
    _refreshPikpakOnly();
    // Connect/disconnect can change what the local shelves should hold (the
    // single-owner rule keys off scrobbling), so re-read local CW before the
    // tracker rows; _reloadForHomeSettings can legitimately return early when
    // no row/layout preference changed.
    if (!widget.searchMode && !widget.discoverMode) {
      _continuationLoading.loadContinueWatching();
    }
    // Trakt/Simkl Continue Watching rows are never rendered on the dedicated
    // Search tab, so don't refetch them there.
    if (!widget.searchMode) {
      _continuationLoading.loadTraktContinueWatching();
      _continuationLoading.loadSimklContinueWatching();
      _continuationLoading.loadMdblistContinueWatching();
    }
    // Opted-in tracker LIST rows live in the board's section pipeline, so a
    // connect/disconnect needs a board reload to add/drop them. Home board
    // only — this listener is registered by every SearchScreen variant, and
    // Search/Discover must never run the board pipeline. Deferred while a
    // catalog search is showing (see _requestBoardReload); safe against
    // overlap via _boardLoadGen.
    if (!widget.searchMode && !widget.discoverMode && _trackerExtrasEnabled) {
      _requestBoardReload();
    }
  }

  Future<void> _refreshTraktAuthState() =>
      _trackerAuthControllers[HomeTracker.trakt]!.load(
        isCurrent: () => mounted,
        onChanged: (_) => setState(() {}),
      );

  Future<void> _refreshSimklAuthState() =>
      _trackerAuthControllers[HomeTracker.simkl]!.load(
        isCurrent: () => mounted,
        onChanged: (_) => setState(() {}),
      );

  Future<void> _refreshMdblistAuthState() {
    var leaveLists = false;
    return _trackerAuthControllers[HomeTracker.mdblist]!.load(
      isCurrent: () => mounted,
      beforeChange: (auth) {
        leaveLists = !auth && _modeSection.mode == SearchMode.lists;
        if (leaveLists) _listsSection.clearListsSearch();
      },
      onChanged: (_) {
        setState(() {
          if (leaveLists) _modeSection.mode = SearchMode.catalog;
        });
        // A disconnect can remove the currently selected mode. Keep the shared
        // query useful by resolving it through Catalog after the selector falls
        // back, unless those exact Catalog results are already present.
        if (leaveLists) {
          final query = _searchController.text.trim();
          if (query.isNotEmpty && query != _catalogSection.catalogQuery) {
            _catalogSection.runCatalogSearch(query);
          }
          if (widget.isTelevision) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _inputSection.searchFocusNode.requestFocus();
            });
          }
        }
      },
    );
  }

  Future<void> _restoreHomeSnapshot(HomeReturnSnapshot snapshot) async {
    _homeReturnRevision = _homeReturnRepository.revision;
    _homeLoadedAt = snapshot.loadedAt;
    _spotlightSection.spotlightHeroOverride = snapshot.hero;
    _addonsById
      ..clear()
      ..addAll(snapshot.board.addons);
    _loading = false;
    _spotlightSection.spotlightEntryRevealed = true;
    if (snapshot.heroResolutionPending) {
      unawaited(
        _spotlightSection.resolveSpotlightHeroSource(
          _addonsById.values.toList(),
        ),
      );
    }
    _applySections(_homeSections);
    MainPageBridge.homeBoardReady.value = true;
    _maybeAutoFocusBoard();
    _maybeAutoFillBoard();
    unawaited(_refreshPikpakOnly());
    if (_trackerExtrasEnabled) {
      final generation = _boardLoadGen;
      final owner = _profileSessionOwner;
      unawaited(HomeListRowsService.instance.resolve(
        _homeExtras,
        previous: _homeSections.whereType<HomeListSection>().toList(),
        isCurrent: () => mounted && generation == _boardLoadGen &&
            owner == ProfileSessionMemory.captureOwner(),
        onUpdate: (rows) {
          if (!mounted || generation != _boardLoadGen ||
              owner != ProfileSessionMemory.captureOwner()) {
            return;
          }
          _publishHomeProgress(replaceHomeListRows(_homeSections, rows),
            false, generation, ProfileRuntime.scope.value);
        },
      ).catchError((_) => <HomeListSection>[]));
    }
    // Re-read local configuration too, including imports that bypass the UI
    // bridge. Continue Watching and favourite loaders still run on each visit.
    await _reloadForHomeSettings();
  }

  void _preserveHomeSnapshot() {
    final board = _committedBoard;
    final loadedAt = _homeLoadedAt;
    if (widget.searchMode ||
        widget.discoverMode ||
        board == null ||
        loadedAt == null ||
        _loading ||
        _error != null ||
        _boardRefreshing ||
        _boardLoadingMore ||
        _pendingBoardReload) {
      return;
    }
    _homeReturnRepository.store((
      sections: _homeCatalogController.rowsForReturn(),
      board: board,
      configuration: _homeConfiguration,
      hero: _spotlightSection.spotlightHeroOverride == null
          ? null
          : copyHomeRowForReturn(_spotlightSection.spotlightHeroOverride!),
      heroResolutionPending: _spotlightSection.heroSourceResolutionPending,
      cardOrientation: _displaySection.homeCardOrientation,
      hideCardTitlesAndRatings: _displaySection.hideHomeCardTitlesAndRatings,
      hideCatalogAddonNames: _displaySection.hideHomeCatalogAddonNames,
      hideCollectionNames: _displaySection.hideHomeCollectionNames,
      loadedAt: loadedAt,
      scrollOffset: _homeLastScroll,
    ), revision: _homeReturnRevision);
  }

  @override
  void dispose() {
    _preserveHomeSnapshot();
    _homePublication.dispose();
    MetadataPreferencesService.revision.removeListener(_metadataSettingsChanged);
    _catalogFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _continuationSection.mdblistContinuationController.cancelRevisionRefresh();
    _spotlightSection.spotlightHeroNode.dispose();
    _keywordReturn.preserve();
    MainPageBridge.unregisterTvContentFocusHandler(
      _tabIndex,
      _inputSection.focusContent,
    );
    StorageService.localCompletionRevision.removeListener(
      _continuationLoading.onLocalCompletionChanged,
    );
    MdblistService.instance.playbackRevision.removeListener(
      _continuationLoading.onMdblistPlaybackRevision,
    );
    if (!widget.searchMode && !widget.discoverMode) {
      MainPageBridge.removePlaylistChangeListener(
        _savedSection.loadPlaylistFavorites,
      );
      MainPageBridge.unregisterCatalogDetailOpenHandler(
        _openPendingCatalogDetail,
      );
    }
    if (widget.searchMode) {
      MainPageBridge.unregisterTabBackHandler(
        'search',
        _modeSection.handleSearchBack,
      );
      MainPageBridge.activeTab.removeListener(
        _titleSection.onTitleSearchTabChanged,
      );
    }
    if (!widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      // Same closure that registered — the bridge's mid-transition contract.
      MainPageBridge.unregisterTabBackHandler(
        'home',
        _spotlightShell.searchSheet.close,
      );
      _inputSection.searchFocusNode.removeListener(
        _spotlightShell.searchSheet.onFocusChanged,
      );
      MainPageBridge.removePlayerLaunchListener(
        _heroPreview.onContentPlayerLaunch,
      );
    }
    // Safe no-op in the variants that never registered it.
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    MainPageBridge.removePlaybackReturnListener(
      _continuationReturn.onPlaybackReturned,
    );
    MainPageBridge.removePlayerLaunchListener(
      _continuationReturn.markPlaybackStarted,
    );
    MainPageBridge.removeHomeSettingsListener(_reloadForHomeSettings);
    MainPageBridge.removeHomeSettingsListener(_reloadSearchCardPrefs);
    HomeRowRefreshSignal.removeListener(_queueHomeRows);
    _stremio.removeAddonsChangedListener(_onHomeAddonsChanged);
    _homeRefreshQueue.dispose();
    IptvMediaStore.listsRevision.removeListener(
      _savedSection.onIptvListsRevision,
    );
    _savedSection.iptvListFocus.dispose();
    if (MainPageBridge.tvHomeStyleChanged ==
        _displaySection.onTvHomeStyleChanged) {
      MainPageBridge.tvHomeStyleChanged = null;
    }
    if (MainPageBridge.tvHeroArtworkQualityChanged ==
        _displaySection.onTvHeroArtworkQualityChanged) {
      MainPageBridge.tvHeroArtworkQualityChanged = null;
    }
    if (widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      _heroPreview.heroTrailerShowing.removeListener(
        _stageSection.onCanvasTrailerShowingChanged,
      );
      HardwareKeyboard.instance.removeHandler(_stageSection.onCanvasTheaterKey);
      HardwareKeyboard.instance.removeHandler(
        _stageSection.stageHold.handleKeyEvent,
      );
    }
    _stageSection.stageTheater.dispose();
    _stageFavorites.canvasFavFocus.dispose();
    _stageSection.atriumFocusedRailKey.dispose();
    _stageSection.tonightFocus.dispose();
    _stageSection.stageCol.dispose();
    _heroShell.dispose();
    _homeMediaBindings.disposeResumeAndMetadata();
    _heroSection.heroSwap.dispose();
    _homeMediaBindings.disposeTrailerAndTint();
    _heroSection.heroItem.dispose();
    _heroSection.heroEnriched.dispose();
    _heroPreview.heroTrailer.dispose();
    _heroPreview.heroTrailerLoading.dispose();
    _heroPreview.heroTrailerShowing.dispose();
    _heroPreview.heroTrailerTakeover.dispose();
    _homeMediaBindings.disposeLivePreview();
    _heroLive.heroLiveUrl.dispose();
    _heroLive.heroLiveChannel.dispose();
    _heroLive.heroLiveTakeover.dispose();
    _heroSection.heroTint.dispose();
    _searchController.dispose();
    ProfileRuntime.scope.removeListener(_onSearchProfileChanged);
    _discoverBindings.close();
    _metadataFeatureSubscription.close();
    _homeBoardBindings.close();
    _homeMediaBindings.close();
    _displaySection.homeLayoutPreferenceSubscription.close();
    _heroPreview.heroTrailerPreferencesSubscription.close();
    _homeDefaultViewSubscription.close();
    _displaySection.homeDisplaySubscription.close();
    _continuationBindings.closeContent();
    _favoriteBindings.close();
    _continuationBindings.closeLayout();
    _searchResultBindings.closeCatalogAndLists();
    _keywordSection.closeAppearance();
    _searchResultBindings.closeKeyword();
    _titleSearch.removeListener(_titleSection.publishTitleSuggestions);
    _titleSearch.dispose();
    _titleSection.presentation.dispose();
    _inputSection.searchFocusNode.removeListener(
      _inputSection.onSearchFocusForSources,
    );
    _inputSection.searchFocus.dispose();
    _listsSection.disposeListsNodes();
    _discoverSection.dispose();
    _boardViewport.disposeScroll();
    _keywordSection.keywordViewport.dispose();
    _keywordSection.keywordFocus.dispose();
    _catalogSection.catalogSourcesBtnFocus.dispose();

    _disposeNodes();
    _continuationSection.continuationNodes.disposeNodes();
    _savedSection.favoriteNodes.disposeNodes();
    _continuationSection.continuationNodes.clearNodes();
    _savedSection.favoriteNodes.clearNodes();
    super.dispose();
  }

  void _disposeNodes() => _boardViewport.disposeNodes();

  /// Re-read the hidden-rows set + opted-in extras and reload the board if
  /// either actually changed. Fires on any home-settings change (the
  /// broadcast is shared), so the equality guards skip reloads for unrelated
  /// settings.
  Future<void> _reloadForHomeSettings() => _homeBoardBindings.settings.run(
    isCurrent: () => mounted,
    refreshAppearance: (current) =>
        _keywordSection.loadSourceTextFormatting(isCurrent: current),
    refreshDisplay: (current) =>
        _displaySection.loadHomeCardOrientation(isCurrent: current),
    refreshContinuation: (current) => _continuationSection
        .continuationLayoutController
        .refresh(isCurrent: current),
    reconcileContinuation: _reconcileContinuationLayout,
    refreshTrailers: (current) =>
        _heroPreview.reloadHeroTrailerPrefs(isCurrent: current),
    selectDefaultView: (current) => _loadHomeDefaultView(isCurrent: current),
    refreshConfiguration: (current) =>
        HomeConfigurationRefresh(
          catalog: _homeCatalogController,
          preferences: ref.read(homeCatalogPreferencesRepositoryProvider),
          collections: _homeCollectionsRepository,
          readHideWatched: ref.read(homeBoardServicesProvider).hideWatched,
        ).run(
          isCurrent: current,
          isHome: !widget.searchMode && !widget.discoverMode,
        ),
    applyConfiguration: _applyHomeConfigurationChanges,
  );

  // Reconcile nodes against accepted rows without refetching continuation data.
  void _reconcileContinuationLayout() {
    setState(() {
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.local,
        movies: _continuationSection.cwMergeLocal
            ? _continuationSection.cwAll.length
            : _continuationSection.cwMovies.length,
        series: _continuationSection.cwMergeLocal
            ? 0
            : _continuationSection.cwSeries.length,
        requestFocus: _requestRowFocus,
      );
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.trakt,
        movies: _continuationSection.cwMergeTrakt
            ? _continuationSection.traktAll.length
            : _continuationSection.traktMovies.length,
        series: _continuationSection.cwMergeTrakt
            ? 0
            : _continuationSection.traktSeries.length,
        requestFocus: _requestRowFocus,
      );
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.simkl,
        movies: _continuationSection.cwMergeSimkl
            ? _continuationSection.simklAll.length
            : _continuationSection.simklMovies.length,
        series: _continuationSection.cwMergeSimkl
            ? 0
            : _continuationSection.simklSeries.length,
        requestFocus: _requestRowFocus,
      );
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.mdblist,
        movies: _continuationSection.cwMergeMdblist
            ? _continuationSection.mdblistAll.length
            : _continuationSection.mdblistMovies.length,
        series: _continuationSection.cwMergeMdblist
            ? 0
            : _continuationSection.mdblistSeries.length,
        requestFocus: _requestRowFocus,
      );
    });
  }

  void _applyHomeConfigurationChanges(HomeConfigurationChanges changes) {
    setState(() {});
    // Hide-watched changes row MEMBERSHIP, so it takes the full reload path.
    if (changes.reloadBoard) {
      _requestBoardReload();
    } else if (changes.reloadHero) {
      // Only the hero source moved — re-roll the reel without refetching the
      // whole board. `_load` isn't rerun here, so resolve from the addons the
      // last load cached.
      unawaited(
        _spotlightSection.resolveSpotlightHeroSource(
          _addonsById.values.toList(),
        ),
      );
    }
    // IPTV list rows live outside the board's section pipeline. The loader
    // reads its own extras from storage, so it can't race the reload above.
    if (changes.reloadIptv) unawaited(_savedSection.loadIptvListRows());
  }

  /// Run [_load] for a TRIGGERED reload (Home Rows save, integration
  /// connect/disconnect) — unless a catalog search is showing its results, in
  /// which case `_load`'s visible reset would stomp the search view. The
  /// reload is latched instead and [_restoreHome] performs it when the board
  /// comes back. (The initState load never comes through here.)
  void _requestBoardReload() {
    if (_catalogSection.catalogQuery.isNotEmpty ||
        _catalogSection.catalogSearching) {
      _pendingBoardReload = true;
      return;
    }
    _load();
  }

  Future<void> _loadHomeDefaultView({bool Function()? isCurrent}) =>
      _homeDefaultView.load(
        isTelevision: widget.isTelevision,
        isHome: !widget.searchMode && !widget.discoverMode,
        isCurrent: () => mounted && (isCurrent?.call() ?? true),
        select: (mode) {
          if (_modeSection.mode != mode) _modeSection.switchMode(mode);
        },
      );

  void _commitBoardSnapshot() {
    _homeCatalogController.commit(_addonsById);
  }

  Future<void> _load({bool preserveVisibleRows = false}) async {
    _homeReturnRevision = _homeReturnRepository.revision;
    _homeLoadedAt = null;
    final previousLists = _homeSections.whereType<HomeListSection>().toList();
    HomeBoardLoad? operation;
    final keepRows =
        preserveVisibleRows &&
        _homeSections.isNotEmpty &&
        _committedBoard != null;
    final previousBoard = keepRows ? _committedBoard : null;
    final previouslyLoaded = previousBoard?.cursor ?? 0;
    final previousRows = <String, CatalogSection>{
      if (keepRows)
        for (final row in _homeSections)
          if (row is! HomeListSection) _sectionRowId(row): row,
    };
    // A superseded pagination request may never return. Its finally block is
    // generation-guarded, so it cannot clear a newer request's loading flag.
    final gen = _homeCatalogController.beginLoad();
    _homePublication.clear();
    final scope = ProfileRuntime.scope.value;
    bool current() =>
        mounted && gen == _boardLoadGen && scope == ProfileRuntime.scope.value;
    // Refreshes already preserve visible rows. Only the Android TV initial
    // Home path changes publication behavior; Search, Discover and tvOS keep
    // their existing loading contract.
    final progressive =
        PlatformUtil.isAndroidTvCached &&
        !widget.searchMode &&
        !widget.discoverMode &&
        !keepRows;
    final progress = progressive
        ? HomeLoadProgress(
            isCurrent: current,
            rowId: _sectionRowId,
            onPublish: (rows, first) {
              if (first) {
                developer.Timeline.instantSync('Home.contentPublished');
              }
              _publishHomeProgress(rows, first, gen, scope);
            },
          )
        : null;
    if (progressive) developer.Timeline.instantSync('Home.loadStarted');
    var completionGen = gen;
    var expired = false;
    _homePaginationDeferred = false;
    _progressiveHomeLoadPending = progressive;
    setState(() {
      if (!keepRows) {
        _loading = true;
        _classicAnchorTailPadding = 0;
      }
      _error = null;
    });
    unawaited(_refreshPikpakOnly());
    try {
      await runHomeLoadWithDeadline(
        retire: () {
          if (!current()) return;
          expired = true;
          _progressiveHomeLoadPending = false;
          completionGen = _homeCatalogController.retireLoad(gen) ?? gen;
          _homePublication.retireGeneration(gen, completionGen);
          // Retiring the generation stops stale batches. A refresh timeout
          // must restore the paging state belonging to the still-visible rows.
          final recovery = progress?.hasPublished == true
              ? _committedBoard
              : previousBoard;
          if (recovery != null) {
            _homeCatalogController.restore(recovery);
            _addonsById
              ..clear()
              ..addAll(recovery.addons);
          } else {
            _homeCatalogController.install(const []);
          }
        },
        load: () {
          final load = HomeBoardLoad(
            catalog: _homeCatalogController,
            preferences: ref.read(homeCatalogPreferencesRepositoryProvider),
            collections: _homeCollectionsRepository,
            services: ref.read(homeBoardServicesProvider),
          );
          operation = load;
          return load.run(
            generation: gen,
            isHome: () => !widget.searchMode && !widget.discoverMode,
            isCurrent: current,
            useSavedOrder: () => _homeRowOrderActive,
            canContinue: () => _canPageHome,
            captureBatchAcceptance: () {
              final batchScope = ProfileRuntime.scope.value;
              return () =>
                  mounted &&
                  gen == _boardLoadGen &&
                  batchScope == ProfileRuntime.scope.value;
            },
            batchSize: _kBoardBatchSize,
            previouslyLoaded: previouslyLoaded,
            previousRows: previousRows,
            previousLists: previousLists,
            progress: progress,
            onResetCatalogs: () {
              _addonsById.clear();
              _commitBoardSnapshot();
            },
            onInventory: (plan, addons) {
              // The metadata lookup is also used by Discover and detail opens.
              _addonsById
                ..clear()
                ..addAll(plan.addonsById);
              if (progress != null) {
                progress.catalogOrder(
                  _boardRefs.map(homeCatalogRowId).toList(),
                );
                _commitBoardSnapshot();
              }
              if (!widget.searchMode && !widget.discoverMode) {
                unawaited(_spotlightSection.resolveSpotlightHeroSource(addons));
              }
            },
            onCommitBatch: _commitBoardSnapshot,
            onLateLists: (rows) => _publishHomeProgress(
              replaceHomeListRows(_homeSections, rows),
              false,
              gen,
              scope,
            ),
            onCompleted: (rows) {
              if (rows == null) {
                _commitBoardSnapshot();
                _homeLoadedAt = DateTime.now();
                return;
              }
              _homeCatalogController.replaceRows(rows);
              _commitBoardSnapshot();
              _homeLoadedAt = DateTime.now();
              setState(() => _loading = false);
              MainPageBridge.homeBoardReady.value = true;
              // Keep accepted Home data during a catalog search without
              // replacing its visible results or stealing its focus.
              if (_catalogSection.catalogQuery.isNotEmpty ||
                  _catalogSection.catalogSearching) {
                return;
              }
              _applySections(rows, preserveFocus: keepRows);
              _maybeAutoFocusBoard();
            },
          );
        },
      );
    } catch (e) {
      if (!mounted ||
          completionGen != _boardLoadGen ||
          scope != ProfileRuntime.scope.value) {
        return;
      }
      // Mid-search, the error screen must not replace the search results
      // (_buildBoard renders _error before anything else) — latch a retry
      // for _restoreHome instead.
      if (_catalogSection.catalogQuery.isNotEmpty ||
          _catalogSection.catalogSearching) {
        _pendingBoardReload = true;
        setState(() => _loading = false);
        MainPageBridge.homeBoardReady.value = true;
        return;
      }
      setState(() {
        if (!keepRows && progress?.hasPublished != true) {
          _error = expired
              ? 'Home took too long to load. Please try again.'
              : e.toString();
        }
        _loading = false;
      });
      if (expired && keepRows) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text(
              "Couldn't refresh Home. Showing previous rows.",
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                if (mounted) unawaited(_load(preserveVisibleRows: true));
              },
            ),
          ),
        );
      }
      // Terminal state too — the launch splash must not outlive the board's
      // loading phase just because it ended in an error screen.
      MainPageBridge.homeBoardReady.value = true;
    } finally {
      progress?.dispose();
      operation?.finish();
      if (completionGen == _boardLoadGen &&
          scope == ProfileRuntime.scope.value) {
        _homeCatalogController.finishLoad(completionGen);
        _progressiveHomeLoadPending = false;
        // Empty/failed catalogs can end without another content publication.
        // Rebuild the initial Spotlight gate so its cards fallback is shown.
        if (mounted &&
            !_spotlightSection.spotlightEntryRevealed &&
            widget.isTelevision &&
            _displaySection.homeStyleEffective == 'spotlight') {
          setState(() {});
        }
        if (mounted && !expired) {
          _maybeAutoFillBoard(resumeDeferred: true);
        }
      }
    }
  }

  /// After a batch lands, if the board still doesn't fill the viewport (so the
  /// user can't scroll to trigger more) keep pulling batches until it does or
  /// the board is exhausted. No-ops outside board mode (search sets no cursor).
  void _maybeAutoFillBoard({bool resumeDeferred = false}) {
    if (!_canPageHome || !_boardHasMore || _boardLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canPageHome || !_boardHasMore || _boardLoadingMore) return;
      if (resumeDeferred) _resumeDeferredHomePagination();
      if (_boardLoadingMore) return;
      if (!_boardScroll.hasClients) return;
      final pos = _boardScroll.position;
      if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 600) {
        _loadMoreBoard();
      }
    });
  }

  /// Fire off the next batch as the user nears the bottom of the board.
  void _onBoardScroll() {
    if (_boardScroll.hasClients) _homeLastScroll = _boardScroll.offset;
    if (!_canPageHome || !_boardHasMore || _boardLoadingMore) return;
    if (!_boardScroll.hasClients) return;
    final pos = _boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMoreBoard();
    }
  }

  /// Load and append the next batch of board rows (deduped against re-entry).
  Future<bool> _loadMoreBoard() async {
    if (!_canPageHome) return false;
    if (_boardRefreshing) {
      if (PlatformUtil.isAndroidTvCached && _boardHasMore) {
        _homePaginationDeferred = true;
      }
      return false;
    }
    if (_boardLoadingMore || _boardCursor >= _boardRefs.length) {
      return false;
    }
    // Bind this append to the load generation that owns the current cursor —
    // if a full reload lands mid-fetch, the stale batch must not append onto
    // (or advance) the fresh board.
    final gen = _boardLoadGen;
    final scope = ProfileRuntime.scope.value;
    var appended = false;
    if (!_homeCatalogController.beginPage(gen)) return false;
    setState(() {});
    try {
      final page = await _homeCatalogController.loadNextRows(
        _kBoardBatchSize,
        generation: gen,
        isCurrent: () =>
            mounted &&
            gen == _boardLoadGen &&
            scope == ProfileRuntime.scope.value,
        canContinue: () => !PlatformUtil.isAndroidTvCached || _canPageHome,
        currentAddons: () => _addonsById,
        rowId: _sectionRowId,
      );
      if (!mounted ||
          gen != _boardLoadGen ||
          scope != ProfileRuntime.scope.value) {
        return false;
      }
      if (page != null) {
        // Only fold into the live view when the board is still what's
        // shown. If a catalog search started while this batch was in flight,
        // `_sections`/`_rowNodes` now hold search results — appending board rows
        // there would corrupt the search view. They'll reappear on _restoreHome.
        if (_catalogSection.catalogQuery.isEmpty &&
            !_catalogSection.catalogSearching) {
          if (page.appendOnly &&
              !(PlatformUtil.isAndroidTvCached &&
                  !(ModalRoute.of(context)?.isCurrent ?? true))) {
            _appendSections(page.additions);
          } else {
            _publishHomeProgress(page.rows, false, gen, scope);
          }
          appended = true;
          // A DPAD-down past the last row may be waiting on this batch —
          // classic's deferred move, and the stage layouts' rail advance.
          _maybeCompleteDeferredDown();
          _stageSection.maybeCompleteStageAdvance();
        }
      }
    } finally {
      if (mounted &&
          gen == _boardLoadGen &&
          scope == ProfileRuntime.scope.value) {
        setState(() => _homeCatalogController.finishPage(gen));
        _maybeAutoFillBoard();
      }
    }
    return appended;
  }

  /// Append newly-loaded board rows without disturbing the rows already shown:
  /// grow the per-row focus nodes in lockstep with [_sections].
  void _appendSections(List<CatalogSection> more) {
    _boardViewport.appendRows(more);
    setState(() => _sections = [..._sections, ...more]);
    unawaited(_refreshBoundSources());
  }

  /// Fetch the next page for a single catalog row and append it in place, so
  /// rows grow without bound as the user scrolls right (Stremio-style). Only
  /// board rows paginate; search-result rows are single-shot. Safe to call
  /// repeatedly — [CatalogSection.loadingMore]/[CatalogSection.exhausted] guard
  /// re-entrancy and the end of the catalog.
  Future<void> _loadMoreRow(int rowIndex, {bool resume = false}) async {
    // While a catalog search is active, `_sections` holds search results, which
    // don't paginate — leave them alone.
    if (_catalogSection.catalogQuery.isNotEmpty ||
        _catalogSection.catalogSearching) {
      return;
    }
    if (rowIndex < 0 || rowIndex >= _sections.length) return;
    final section = _sections[rowIndex];
    final scope = ProfileRuntime.scope.value;
    int currentIndex() =>
        !mounted ||
            scope != ProfileRuntime.scope.value ||
            _catalogSection.catalogQuery.isNotEmpty ||
            _catalogSection.catalogSearching
        ? -1
        : _sections.indexWhere((row) => identical(row, section));
    if (!_homeCatalogController.beginRowPage(section, resume: resume)) return;
    // Android TV: flip the guard silently. The setState exists to show the
    // classic row's tail spinner, but it fires on the exact keypress that
    // crossed the row-end threshold — a full-screen rebuild landing on the
    // input frame, which an Amlogic box renders as the cursor hitching every
    // time a row pages. The spinner is a nicety; the page landing repaints
    // either way.
    if (!PlatformUtil.isAndroidTvCached || resume) setState(() {});
    try {
      // Dedup against what we already have: some addons return valid ids but
      // repeat entries, and some ignore `skip` entirely. The pager advances
      // `skip` by the addon's RAW counts so paging never under-advances into a
      // false "exhausted", and with hide-watched on it tops the window up so a
      // page of watched titles doesn't end the row early.
      final page = await _homeCatalogController.fetchRowPage(
        (section.addon, section.catalog),
        skip: section.nextSkip,
        existingIds: section.items.map((item) => item.id),
        isCurrent: () => currentIndex() >= 0,
      );
      // Progressive arrivals can move the SAME row. Only a removed/replaced
      // row or a changed session invalidates its page, not a new numeric index.
      final index = currentIndex();
      if (index < 0) return;
      _homeCatalogController.acceptRowPage(section, page);
      final fresh = page.items;
      if (fresh.isEmpty) return;
      // Grow this row's focus nodes in lockstep with the new items.
      _boardViewport.appendItems(index, fresh.length);
      setState(() => _homeCatalogController.appendRowItems(section, fresh));
      // A DPAD-right that ran off the end of this row may be waiting on it.
      _stageSection.maybeCompleteStageRight();
      unawaited(_refreshBoundSources());
    } catch (_) {
      // Transient fetch failure — leave the row as-is so a later scroll retries.
    } finally {
      if (currentIndex() >= 0) {
        setState(() => _homeCatalogController.finishRowPage(section));
      } else {
        _homeCatalogController.finishRowPage(section);
      }
    }
  }

  /// Stable progress key, including supported native provider identities.
  String? _imdbOf(StremioMeta item) {
    final id = item.progressId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool _isBound(StremioMeta item) {
    final id = _imdbOf(item);
    return id != null && (_boundCounts[id] ?? 0) > 0;
  }

  int _boundCountFor(StremioMeta item) {
    final id = _imdbOf(item);
    return id == null ? 0 : (_boundCounts[id] ?? 0);
  }

  /// Re-read how many pinned sources each currently-displayed title has. Called
  /// after sections load and after any bind/unbind/playback.
  Future<void> _refreshBoundSources() {
    // Cover every on-screen tile that renders a bound badge: catalog sections
    // AND the Continue Watching rows (whose titles may not appear in any
    // section, so editing their sources must still refresh the CW card badge).
    final items = [
      for (final section in _sections) ...section.items,
      ..._continuationSection.cwMovies,
      ..._continuationSection.cwSeries,
      ..._continuationSection.traktMovies,
      ..._continuationSection.traktSeries,
      ..._continuationSection.simklMovies,
      ..._continuationSection.simklSeries,
      ..._continuationSection.mdblistMovies,
      ..._continuationSection.mdblistSeries,
    ];
    return _boundCountsController.load(
      ids: items.map(_imdbOf),
      isCurrent: () => mounted,
      onAccepted: () => setState(() {}),
    );
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() => _pikpakOnlyController.load(
    isCurrent: () => mounted,
    onChanged: () => setState(() {}),
  );
  String _sectionRowId(CatalogSection section) => section is HomeListSection
      ? section.rowId
      : section is HomeCollectionSection
      ? section.rowId
      : '${section.addon.id}:${section.catalog.type}:${section.catalog.id}';

  // A DPAD-down pressed while everything below was still loading (Trakt row a
  // focusless skeleton, favourites absent, first catalog batch in flight) used
  // to be swallowed with focus frozen in place — the cell handler had already
  // reported the key handled. Instead the press is remembered briefly and
  // completed the moment a row below lands. Origin node is compared by
  // IDENTITY only (never dereferenced — it may be disposed by then): if focus
  // moved elsewhere meanwhile, the deferred move is dropped, so a late load
  // can never yank focus away from the user.
  FocusNode? _pendingDownOrigin;
  int _pendingDownRowIndex = -1; // set when pressed on a catalog row
  String? _pendingDownHomeRowId; // stable id on the globally ordered Home
  int _pendingDownCol = 0;
  DateTime? _pendingDownAt;
  static const Duration _pendingDownMaxAge = Duration(seconds: 3);

  void _deferDownMove({
    int rowIndex = -1,
    String? homeRowId,
    required int column,
  }) {
    if (!_boardCanAdvance && _focusCatalogContinuation()) return;
    _pendingDownOrigin = FocusManager.instance.primaryFocus;
    if (_pendingDownOrigin == null) return;
    _pendingDownRowIndex = rowIndex;
    _pendingDownHomeRowId = homeRowId;
    _pendingDownCol = column;
    _pendingDownAt = DateTime.now();
  }

  void _clearDeferredDown() {
    _pendingDownOrigin = null;
    _pendingDownAt = null;
    _pendingDownHomeRowId = null;
  }

  /// Complete a recent deferred DPAD-down, called whenever a row load settles.
  /// Post-frame: the freshly-loaded row's cells only mount on the next build,
  /// and [_requestRowFocus] needs mounted cells.
  void _maybeCompleteDeferredDown() {
    if (_pendingDownAt == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final at = _pendingDownAt;
      final origin = _pendingDownOrigin;
      if (at == null || origin == null) return;
      if (DateTime.now().difference(at) > _pendingDownMaxAge) {
        _clearDeferredDown();
        return;
      }
      if (!identical(FocusManager.instance.primaryFocus, origin)) {
        _clearDeferredDown();
        return;
      }
      final col = _pendingDownCol;
      final bool moved;
      final homeRowId = _pendingDownHomeRowId;
      if (homeRowId != null) {
        final rails = _stageRailsSection.canvasRails;
        final current = rails.indexWhere(
          (rail) => _stageRailsSection.canvasRailRowId(rail) == homeRowId,
        );
        moved = current >= 0 && _focusHomeRailAt(current + 1, col);
      } else if (_pendingDownRowIndex >= 0) {
        moved = _focusRow(_pendingDownRowIndex + 1, col);
      } else {
        // From the last favourites row.
        moved = _focusRow(0, col);
      }
      if (moved) _clearDeferredDown();
    });
  }

  VoidCallback _favRowOnUp(String rowId, int column) =>
      () => _focusRelativeHomeRail(rowId, -1, column);

  VoidCallback _favRowOnDown(String rowId, int column) =>
      () => _focusRelativeHomeRail(rowId, 1, column);

  late final _homeRefreshQueue = HomeRefreshQueue(
    isCurrent: () => mounted,
    isVisible: () => ModalRoute.of(context)?.isCurrent ?? false,
    refreshRow: (row) {
      switch (row) {
        case HomeRowRefresh.tvFavorites:
          unawaited(_savedSection.loadTvFavorites());
        case HomeRowRefresh.stremioTvFavorites:
          unawaited(_savedSection.loadStremioTvFavorites());
        case HomeRowRefresh.playlist:
          unawaited(_savedSection.loadPlaylistFavorites());
        case HomeRowRefresh.watchlist:
          unawaited(_savedSection.loadMyWatchlist());
        case HomeRowRefresh.playback:
          // Do not consume the local playback/tracker refresh latch here.
          unawaited(_continuationLoading.loadContinueWatching());
          unawaited(_continuationLoading.loadIptvContinueWatching());
      }
    },
    refreshAddons: () {
      if (_catalogSection.catalogQuery.isNotEmpty ||
          _catalogSection.catalogSearching) {
        _pendingBoardReload = true;
      } else {
        unawaited(_load(preserveVisibleRows: true));
      }
    },
  );

  void _onHomeAddonsChanged() => _homeRefreshQueue.addonsChanged();

  void _queueHomeRows(Set<HomeRowRefresh> rows) =>
      _homeRefreshQueue.enqueue(rows);

  /// Resolve the addon that a Continue Watching title should route through.
  /// Prefers the stored source addon; falls back to any homepage addon, then a
  /// minimal placeholder so Play still works even if the addon is gone.
  StremioAddon _addonForContinue(String? addonId) {
    if (addonId == NativeSeriesMetadataService.addon.id) {
      return NativeSeriesMetadataService.addon;
    }
    for (final addon in _addonsById.values) {
      if (addon.sourceBindingKey == addonId || addon.portableConfigurationKey == addonId) return addon;
    }
    if (addonId != null && _addonsById.containsKey(addonId)) {
      return _addonsById[addonId]!;
    }
    // "Any homepage addon" means a REAL catalog addon — the Trakt/Simkl list
    // rows that now lead _homeSections carry only a placeholder addon (empty
    // baseUrl), which can't serve /meta or /stream.
    for (final s in _homeSections) {
      if (s is! HomeListSection && s is! HomeCollectionSection) {
        return s.addon;
      }
    }
    return StremioAddon(
      id: addonId ?? 'continue_watching',
      name: 'Continue Watching',
      manifestUrl: '',
      baseUrl: '',
    );
  }

  /// Open a board-section item through the right pipeline for its source.
  /// Trakt list rows keep Trakt semantics (`isTraktSource` — status chips,
  /// Trakt-first resume label), Simkl rows open plainly (Discover's
  /// [_continuationPlayback.openSimklItem] routing), and real catalog sections route through their
  /// own addon exactly as before.
  void _sectionOpenItem(
    CatalogSection section,
    StremioMeta item, {
    String? heroTag,
  }) {
    // A folder tile opens the folder's merged grid, never a detail page.
    if (section is HomeCollectionSection) {
      _openCollectionFolder(section, item);
      return;
    }
    if (section is HomeListSection) {
      if (section.simklList != null) {
        _continuationPlayback.openSimklItem(item, heroTag: heroTag);
        return;
      }
      _itemActions.openItem(
        item,
        _addonForContinue(item.sourceAddon?.id),
        isTraktSource: section.isTrakt,
        isMdblistSource: section.isMdblist,
        heroTag: heroTag,
      );
      return;
    }
    _itemActions.openItem(item, section.addon, heroTag: heroTag);
  }

  /// Quick-play counterpart to [_sectionOpenItem]. Trakt rows go through
  /// [_continuationPlayback.playTraktItem] (CW-cached resume, else catalog play with Trakt-first
  /// resume); Simkl rows play plainly like Discover's lists.
  void _sectionQuickPlay(CatalogSection section, StremioMeta item) {
    // A folder tile has nothing to play — open it instead.
    if (section is HomeCollectionSection) {
      _openCollectionFolder(section, item);
      return;
    }
    if (section is HomeListSection) {
      if (section.isTrakt) {
        _continuationPlayback.playTraktItem(item);
      } else if (section.isMdblist) {
        _catalogActions.onCatalogPlay(
          item,
          _addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        );
      } else {
        _continuationPlayback.playSimklItem(item);
      }
      return;
    }
    _catalogActions.onCatalogPlay(item, section.addon);
  }

  /// A folder tile on a collection row opens that folder's merged grid.
  void _openCollectionFolder(HomeCollectionSection section, StremioMeta item) {
    final index = section.folderIndexOf(item);
    _openCollectionScreen(section.collection, index < 0 ? 0 : index);
  }

  /// Push the folder browser on [folderIndex]. Items open through [_itemActions.openItem]
  /// with the addon that served them (the catalog fetch stamps
  /// `sourceAddon`), so the detail flow is the catalog rows' own.
  void _openCollectionScreen(HomeCollection collection, int folderIndex) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _withHomeExpandedCardSettings(
              CollectionFolderScreen(
                collection: collection,
                initialFolderIndex: folderIndex,
                fromHome: true,
                isTelevision: widget.isTelevision,
                onOpenItem: (item) => _itemActions.openItem(
                  item,
                  item.sourceAddon ?? _addonForContinue(null),
                ),
                onQuickPlay: _pikpakOnly
                    ? null
                    : (item) => _catalogActions.onCatalogPlay(
                        item,
                        item.sourceAddon ?? _addonForContinue(null),
                      ),
              ),
            ),
          ),
        )
        .then((_) => _continuationReturn.afterSeeAllReturn());
  }

  /// Open a detail page requested by another tab (see [initState]). Builds a
  /// minimal Trakt-sourced [StremioMeta] from the handoff map and routes through
  /// the normal [_itemActions.openItem] path, so every action button behaves exactly as on
  /// the Home board. For a series it scrolls to the requested season/episode,
  /// and it returns to the origin tab when the detail closes.
  Future<void> _openPendingCatalogDetail(Map<String, dynamic> data) async {
    final imdbId = data['imdbId'] as String?;
    if (imdbId == null || imdbId.isEmpty) return;
    // This can run before the board's async flags settle (they're kicked off
    // fire-and-forget in initState). Await the two that shape the detail so we
    // don't open the wrong thing: the merged-page flag (merged vs legacy screen
    // — only the merged one honours initialSeason/Episode, i.e. the scroll) and
    // Trakt auth (status chips + menu). Both are fast local reads, no network.
    await _loadMergedSeriesFlag();
    await _refreshTraktAuthState();
    if (!mounted) return;
    final type = (data['type'] as String?) == 'movie' ? 'movie' : 'series';
    final meta = StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: type,
      name: (data['title'] as String?) ?? '',
      poster: data['poster'] as String?,
      year: (data['year'] as int?)?.toString(),
    );
    _itemActions.openItem(
      meta,
      _addonForContinue(null),
      isTraktSource: true,
      initialSeason: data['season'] as int?,
      initialEpisode: data['episode'] as int?,
      returnToTabOnClose: data['originTab'] as int?,
    );
  }

  // ── Simkl Continue Watching ───────────────────────────────────────────────

  /// Swap the displayed sections (homepage or search results): rebuild the
  /// per-row focus nodes and reset the hero to the first item.
  void _applySections(
    List<CatalogSection> sections, {
    bool preserveFocus = false,
    bool incremental = false,
  }) {
    String? anchor;
    double? anchorHeight;
    double anchorTailPadding = 0;
    List<String> previousOrder = const [];
    if (incremental && _displaySection.homeStyleEffective == 'classic') {
      final rails = _stageRailsSection.classicHomeRails;
      for (final rail in rails) {
        if (rail.traktSkeletonIndex >= 0) continue;
        final focused = _stageRailsSection
            .canvasRailNodes(rail)
            .where((node) => node.hasFocus);
        if (focused.isEmpty) continue;
        anchor = _stageRailsSection.canvasRailRowId(rail);
        // Newly published rows are catalog/list/collection rows even if the
        // focused anchor is Continue Watching or a favourite in a custom order.
        if (rail.sectionIndex != null) {
          anchorHeight = homeRowHeight(
            focused.first.context,
            ValueKey('board-reveal-$_boardGen-$anchor'),
          );
        }
        anchorHeight ??= _classicCatalogRowExtent(
          focused.first.context ?? context,
          section: rail.sectionIndex == null
              ? null
              : _sections[rail.sectionIndex!],
        );
        break;
      }
      previousOrder = rails.map(_stageRailsSection.canvasRailRowId).toList();
      if (anchor != null &&
          _boardScroll.hasClients &&
          _boardScroll.position.maxScrollExtent <= 0) {
        // A short first batch leaves unused viewport space below its rows.
        // Retain that space as tail padding when rows are inserted above the
        // anchor, otherwise scroll physics clamps away the preserved offset.
        final heights = <double>[];
        for (final rail in rails) {
          if (rail.traktSkeletonIndex >= 0) break;
          final nodes = _stageRailsSection.canvasRailNodes(rail);
          final height = nodes
              .map(
                (node) => homeRowHeight(
                  node.context,
                  ValueKey(
                    'board-reveal-$_boardGen-${_stageRailsSection.canvasRailRowId(rail)}',
                  ),
                ),
              )
              .whereType<double>()
              .firstOrNull;
          if (height == null) break;
          heights.add(height);
        }
        if (heights.length == rails.length) {
          anchorTailPadding = max(
            _classicAnchorTailPadding,
            _boardScroll.position.viewportDimension -
                38 -
                heights.fold<double>(0, (sum, height) => sum + height),
          );
        }
      }
    }
    // Streaming arrivals are not a fresh board: preserve keyed row elements,
    // entrance state, and any pending user-directed move to the next rail.
    if (!incremental) {
      _boardGen++;
      _boardAppliedAt = DateTime.now();
      // Rail keys are content-addressed by stable Home-row id, so a reload can
      // preserve the active rail even when its numeric section index changes.
      _stageSection.stageDeferredAdvance.invalidateForBoardReseed();
      _stageSection.stageFocusRequests.invalidate();
    }
    _boardViewport.replaceRows(
      previous: _sections,
      next: sections,
      rowId: _sectionRowId,
      preserveFocus: preserveFocus,
      incremental: incremental,
    );
    setState(() {
      _sections = sections;
      if (anchor != null && anchorHeight != null) {
        final nextOrder = _stageRailsSection.classicHomeRails
            .map(_stageRailsSection.canvasRailRowId)
            .toList();
        if (nextOrder
            .takeWhile((id) => id != anchor)
            .any((id) => !previousOrder.contains(id))) {
          _classicAnchorTailPadding = max(
            _classicAnchorTailPadding,
            anchorTailPadding,
          );
        }
        preserveHomeInsertionAnchor(
          scroll: _boardScroll,
          previous: previousOrder,
          next: nextOrder,
          anchor: anchor,
          extentOf: (_) => anchorHeight!,
        );
      }
    });
    _spotlightSection.publishTopShelfSpotlight();
    unawaited(_refreshBoundSources());
    if (preserveFocus &&
        _heroSection.heroItem.value != null &&
        sections.any(
          (section) => section.items.any(
            (item) =>
                item.id == _heroSection.heroItem.value!.id &&
                item.type == _heroSection.heroItem.value!.type,
          ),
        )) {
      return;
    }
    // Seed the hero with the first item so it isn't blank before DPAD focus
    // lands (see [_heroSection.heroActive] for when the hero is shown).
    if (_heroSection.heroActive) {
      // Seed from the first real title: a pinned collection row can lead the
      // board, and folder tiles can't drive the hero.
      StremioMeta? first;
      for (final section in sections) {
        if (section is HomeCollectionSection) continue;
        if (section.items.isNotEmpty) {
          first = section.items.first;
          break;
        }
      }
      _heroSection.heroItem.value = first;
      _heroSection.heroEnriched.value = null;
      // Outside the null-check: a board that reloads EMPTY must clear the
      // shell stage too (null item → null art), not keep the last title's.
      _heroSection.publishAmbientArt(first, null);
      if (first != null) {
        _heroSection.enrichHero(first);
        _heroSection.updateHeroTint(first);
        // Billboard effect: the seeded spotlight starts its trailer too, so
        // opening Home settles into a living hero without any DPAD input.
        // A board reload is a fresh visit — lift any after-the-feature
        // suppression, and drop any Canvas favourites override + live feed
        // (a reload landing while a favourite held focus would otherwise
        // keep its stale art/title on the stage — or resume its stream —
        // with no cell focused, and let the seeded trailer start beneath).
        _heroPreview.heroPreviewPolicy.allowNewHero();
        _stageFavorites.canvasFavFocus.value = null;
        _heroLive.clearHeroLiveIptv();
        _heroPreview.scheduleHeroTrailer(first);
      } else {
        _heroPreview.clearHeroTrailer();
        // Clear the COLOUR too, not just the art — an empty reload otherwise
        // left the departed title's tint on the shell stage + sidebar glass.
        _heroSection.heroTint.value = null;
        _heroSection.publishHeroTintToShell(null);
      }
    }
  }

  /// Cancel any pending search and return to the homepage board.
  void _restoreHome() {
    _catalogSection.catalogController.clear();
    // A settings/integration reload arrived mid-search and was deferred so it
    // couldn't stomp the results view — run it now instead of restoring the
    // stale cached board.
    if (_pendingBoardReload) {
      _pendingBoardReload = false;
      _load();
      return;
    }
    _applySections(_homeSections);
    _maybeAutoFillBoard();
  }

  // ── Focus entry ──────────────────────────────────────────────────────────

  /// Place — or re-anchor — the board's auto-focus after content loads, so
  /// arriving on the Home tab lands on a card (no stray arrow press) and then
  /// *settles to the top*: focus the best card available now, and as higher rows
  /// arrive (Trakt filling its reserved slot, local Continue Watching) slide up
  /// to the new top card while the user is idle. See [_autoFocusedNode] /
  /// [_autoFocusSettled] for the state machine.
  ///
  /// TV-only, homepage board only. Deferred a frame so the target row is mounted.
  void _maybeAutoFocusBoard() {
    // Every row-load settle path funnels through here, which makes it the one
    // hook needed to complete a DPAD-down deferred while that row was loading.
    // Runs before the settle latch below — deferred moves are USER presses and
    // must work long after auto-focus has handed over control.
    _maybeCompleteDeferredDown();
    if (_autoFocusSettled || _autoFocusScheduled) return;
    if (!widget.isTelevision) return;
    if (widget.searchMode || widget.discoverMode) return;
    _autoFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Coalesced pass: reads the final top after every same-frame load's
      // setState has applied, so multiple loads don't race.
      _autoFocusScheduled = false;
      if (!mounted || _autoFocusSettled) return;
      if (widget.searchMode || widget.discoverMode) return;
      // Only when this is the tab the user is actually looking at. During the
      // ~350ms tab cross-fade the outgoing board is still mounted and shares the
      // ModalRoute, so isCurrent can't tell them apart — the active-tab index
      // can. (main.dart keeps it in lock-step with the rendered tab.)
      if (MainPageBridge.activeTvTabIndex != _tabIndex) return;
      // Don't grab focus if the board isn't the top route — e.g. the user
      // opened a detail page or player and a slow CW/Trakt load only just
      // finished. Stealing focus here would yank it off the pushed screen onto
      // the hidden board below.
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      if (MainPageBridge.isTvSidebarFocused?.call() ?? false) return;

      final primary = FocusManager.instance.primaryFocus;
      final boardFocused = _boardHasFocus();
      if (_autoFocusedNode == null) {
        // Never placed focus yet. If the user already reached a board card on
        // their own, leave it and latch — nothing to auto-place.
        if (boardFocused) {
          _autoFocusSettled = true;
          return;
        }
      } else if (boardFocused && primary != _autoFocusedNode) {
        // We placed focus earlier and it now sits on a *different* board card —
        // the user has taken control. Stop re-anchoring so we never fight them.
        // (Guarded by boardFocused so our own just-applied requestFocus, or a
        // transient null primaryFocus between loads, can't false-trigger this.)
        _autoFocusSettled = true;
        return;
      }

      final top = _topBoardFocusNode();
      if (top == null) return; // nothing focusable yet — retry on the next load
      if (top == _autoFocusedNode) {
        return; // already anchored to the current top
      }
      top.requestFocus();
      _autoFocusedNode = top;
    });
  }

  /// Whether any focusable element on this screen currently holds focus. Used to
  /// avoid stealing focus from the user in [_maybeAutoFocusBoard].
  bool _boardHasFocus() {
    bool anyOf(List<FocusNode> ns) => ns.any((n) => n.hasFocus);
    if (_inputSection.searchFocus.hasFocus ||
        _discoverSection.discSourceNode.hasFocus ||
        // Spotlight's hero is a focus target the rail lists know nothing
        // about; without this the arrival machinery thinks the board is
        // unfocused while the hero holds the cursor and steals it back.
        _spotlightSection.spotlightHeroNode.hasFocus) {
      return true;
    }
    if (anyOf(_listsSection.listsNodes)) return true;
    if (anyOf(_continuationSection.cwMovieNodes) ||
        anyOf(_continuationSection.cwSeriesNodes) ||
        anyOf(_continuationSection.traktMovieNodes) ||
        anyOf(_continuationSection.traktSeriesNodes) ||
        anyOf(_continuationSection.simklMovieNodes) ||
        anyOf(_continuationSection.simklSeriesNodes) ||
        anyOf(_continuationSection.mdblistMovieNodes) ||
        anyOf(_continuationSection.mdblistSeriesNodes) ||
        anyOf(_savedSection.tvFavNodes) ||
        anyOf(_savedSection.stvFavNodes) ||
        anyOf(_savedSection.iptvFavNodes) ||
        anyOf(_savedSection.watchlistMovieNodes) ||
        anyOf(_savedSection.watchlistSeriesNodes) ||
        anyOf(_savedSection.playlistFavNodes)) {
      return true;
    }
    for (final row in _rowNodes) {
      if (anyOf(row)) return true;
    }
    return false;
  }

  /// The focus node for the board's current top card — the same target
  /// [_inputSection.focusContent] would pick on the board path (Continue Watching →
  /// favourites → catalog rows), or null if nothing is focusable yet. Skeleton
  /// Trakt rows carry no nodes, so they're naturally skipped: while Trakt is
  /// reserving, the top is whatever real row sits below the skeletons, and once
  /// the real Trakt rows land they become the top. Drives the "settle to the
  /// top" re-anchor in [_maybeAutoFocusBoard].
  FocusNode? _topBoardFocusNode() {
    // Canvas shows exactly ONE rail — the classic top-row targets are
    // usually unmounted there (and requestFocus on a detached node only
    // latches a stray later grab), so sidebar hand-off / tab re-entry /
    // auto-focus all aim at the displayed rail's nearest mounted cell.
    // Canvas renders exactly ONE rail, so aim at its nearest mounted cell;
    // null (rails still loading) falls through to the classic targets.
    if (_displaySection.stageActive) return _stageSection.stageFocusTarget();
    for (final rail in _stageRailsSection.canvasRails) {
      final nodes = _stageRailsSection.canvasRailNodes(rail);
      if (nodes.isNotEmpty) return nodes.first;
    }
    return null;
  }

  bool _focusReclaimScheduled = false;

  /// FocusManager listener (TV board only): fires on every app-wide focus
  /// change, so the common path must bail out in a comparison or two. Only a
  /// DEAD state — primary focus fell back to a bare scope (the focused node
  /// was disposed) — schedules the post-frame reclaim pass.
  void _onGlobalFocusChange() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    if (_focusReclaimScheduled) return;
    _focusReclaimScheduled = true;
    // Post-frame: the disposal that killed focus is usually mid-rebuild; the
    // board's surviving cells are attached again by the frame's end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusReclaimScheduled = false;
      _reclaimDeadFocus();
    });
  }

  /// Re-anchor focus onto the board after it died. Deliberately picks the
  /// first MOUNTED cell (Continue Watching → favourites → catalog order) — if
  /// the user was deep in the board, the top rows' cells are unmounted and
  /// requestFocus on them is a silent no-op, so walking to a mounted node also
  /// lands focus near where they were looking.
  void _reclaimDeadFocus() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return; // recovered
    if (MainPageBridge.activeTvTabIndex != _tabIndex) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (MainPageBridge.isTvSidebarFocused?.call() ?? false) return;

    // On a stage layout only ONE rail (and, on Tonight, one zone) is mounted,
    // so the data-order walk below would land wherever the first mounted node
    // happens to be — a different rail, or the wrong Tonight zone with the
    // zone flag left lying. Ask the layout where focus belongs first.
    if (_displaySection.stageActive) {
      final target = _stageSection.stageFocusTarget();
      if (target != null && (target.context?.mounted ?? false)) {
        target.requestFocus();
        return;
      }
    }

    bool tryRow(List<FocusNode> nodes) {
      for (final n in nodes) {
        if (n.context?.mounted ?? false) {
          n.requestFocus();
          return true;
        }
      }
      return false;
    }

    for (final rail in _stageRailsSection.canvasRails) {
      if (tryRow(_stageRailsSection.canvasRailNodes(rail))) return;
    }
  }

  /// DPAD-up from the top row. On the dedicated Search tab the field sits above
  /// the results, so land there; on the Home-New board there's nothing above —
  /// stay put. (This used to hand focus to the sidebar, but the sidebar policy
  /// is now LEFT-only: no other direction may open it.)
  void _leaveBoardTop() {
    _heroPreview.heroPreviewPolicy.resetAttempt();
    if (widget.searchMode) {
      _inputSection.searchFocusNode.requestFocus();
    }
  }

  /// Returns false when the target catalog row isn't loaded/focusable (after
  /// kicking the next batch load if one is available) — same contract as
  /// [_continuationMenu.focusCwRow], so DPAD wiring can defer the move instead of eating it.
  bool _focusRow(int row, int column) {
    if (row >= _rowNodes.length) {
      // Reach visible actions before starting another batch. When no action
      // is mounted, retain the existing deferred move into the next row.
      if (!_boardLoadingMore && _focusCatalogContinuation()) return true;
      if (_boardHasMore) _loadMoreBoard();
      return false;
    }
    if (row < 0) return false;
    final nodes = _rowNodes[row];
    if (nodes.isEmpty) return false;
    // Land on the row's own remembered column, not the source column, so
    // returning to a row you'd scrolled right goes back where you left it (that
    // cell is still mounted). First visit falls back to the incoming column.
    final desired = (_rowCol[row] ?? column).clamp(0, nodes.length - 1);
    _requestRowFocus(nodes, desired);
    return true;
  }

  void _requestRowFocus(List<FocusNode> nodes, int desired) =>
      _boardViewport.requestFocus(nodes, desired, isCurrent: () => mounted);

  // ── TV Home layout (classic / canvas) ────────────────────────────────────

  int get _tvHeroArtworkCacheWidth =>
      TvHeroArtworkQualityController.decodeSize.landscapeWidth;
  int get _tvHeroArtworkCacheHeight =>
      TvHeroArtworkQualityController.decodeSize.posterHeight;

  // ── CANVAS view ──────────────────────────────────────────────────────────

  // ── Spotlight ───────────────────────────────────────────────────────────

  HomeBoardMedia get _boardMedia => HomeBoardMedia(
    item: _heroSection.heroItem,
    enriched: _heroSection.heroEnriched,
    favorite: _stageFavorites.canvasFavFocus,
    cacheWidth: _tvHeroArtworkCacheWidth,
    cacheHeight: _tvHeroArtworkCacheHeight,
    trailer: _heroPreview.heroTrailer,
    isTelevision: widget.isTelevision,
    volume: _heroPreview.heroTrailerVolume,
    loading: _heroPreview.heroTrailerLoading,
    takeover: _heroPreview.heroTrailerTakeover,
    liveChannel: _heroLive.heroLiveChannel,
    liveUrl: _heroLive.heroLiveUrl,
    isAddonChannel: StremioIptvService.isStremioChannelUrl,
    onPlayingChanged: _heroPreview.onHeroTrailerPlaying,
    onLivePlaybackFailed: _heroLive.onHeroLivePlaybackFailed,
  );

  late final _classicNavigation = HomeClassicNavigation(
    rails: () => _stageRailsSection.canvasRails,
    rowIdOf: _stageRailsSection.canvasRailRowId,
    nodesFor: _stageRailsSection.canvasRailNodes,
    requestFocus: _requestRowFocus,
    leaveTop: _leaveBoardTop,
    loadingMore: () => _boardLoadingMore,
    hasMore: () => _boardHasMore,
    focusContinuation: _focusCatalogContinuation,
    loadMore: _loadMoreBoard,
    deferDown: (rowId, column) =>
        _deferDownMove(homeRowId: rowId, column: column),
  );

  bool _focusHomeRailAt(int index, int column) =>
      _classicNavigation.focusAt(index, column);

  void _focusRelativeHomeRail(String rowId, int delta, int column) =>
      _classicNavigation.move(rowId, delta, column);

  // ── PROMENADE view ───────────────────────────────────────────────────────

  // ── ATRIUM view ──────────────────────────────────────────────────────────

  // ── MOSAIC view ──────────────────────────────────────────────────────────

  // ── DECK view ────────────────────────────────────────────────────────────

  // ── TONIGHT view ─────────────────────────────────────────────────────────

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Debounced ambient-trailer load for the spotlighted title. The previous
  /// trailer is torn down IMMEDIATELY on any hero change (a playing trailer
  /// under the wrong title is worse than the static backdrop), then a new one
  /// only starts once focus has RESTED on the card — flying across a row costs
  /// nothing but a timer reset, never a resolve or a decoder spin-up. Both
  /// lookups (Cinemeta /meta for the YouTube id, then the stream resolve) are
  /// cached in their services, so re-resting on a recent card starts fast.
  late final ProviderSubscription<MetadataFeaturePolicy>
  _metadataFeatureSubscription;
  late final MetadataFeatureController _metadataFeatureController;
  MetadataPreferences? get _metadataFeaturePolicy =>
      _metadataFeatureController.current.preferences;

  Future<void> _refreshMetadataFeaturePolicy() =>
      _metadataFeatureController.load(
        isCurrent: () => mounted,
        onAccepted: (prefs) {
          setState(() {});
          _titleSection.scheduleTitleSuggestions();
          if (widget.discoverMode &&
              _discoverSection.discSource == _discTmdb &&
              !prefs.features.contains(MetadataFeature.discovery)) {
            _discoverSection.selectDiscoverSource(_discCw);
          }
        },
      );

  void _metadataSettingsChanged() {
    if (!mounted) return;
    _metadataFeatureController.invalidate();
    _titleSection.cancelTitleSuggestions();
    unawaited(_refreshMetadataFeaturePolicy());
    _continuationSection.episodeArtworkController.refresh(
      isCurrent: () => mounted,
      onChanged: () => setState(() {}),
    );
    _heroPreview.clearHeroTrailer();
    _heroSection.heroEnriched.value = null;
    final item = _heroSection.heroItem.value;
    if (item != null) {
      _heroSection.enrichHero(item);
      _heroPreview.scheduleHeroTrailer(
        item,
        fromSpotlight: _displaySection.homeStyleEffective == 'spotlight',
      );
    }
  }

  // ── Route awareness (Home board trailer only) ────────────────────────────
  // The trailer schedule is time-driven, so without this a pushed route
  // (detail page, player) would let the 2.4s debounce fire UNDER the cover
  // and start a trailer behind it — the backdrop's own RouteAware pause can't
  // help because it mounts after the cover was already pushed and never sees
  // a didPushNext. Kill everything when covered; re-arm the spotlight when
  // the cover pops so browsing resumes its normal rest-to-play.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PlatformUtil.isAndroidTvCached) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _resumeHomeProgress();
      } else {
        _clearDeferredDown();
        _stageSection.stageDeferredAdvance.reset();
      }
    }
    _heroShell.bindRoute(context);
  }

  @override
  void didPushNext() => _heroShell.didPushNext();

  @override
  void didPopNext() {
    // A board reload UNDER a detail page/player can dispose the focused node;
    // the reclaim listener fires while covered and bails on route.isCurrent,
    // and no focus event re-fires it on the way back — re-run the dead check
    // now that the board is the top route again.
    _onGlobalFocusChange();
    if (!_heroPreview.heroTrailerActive || !_heroPreview.heroTrailerEnabled) {
      return;
    }
    final item = _heroSection.heroItem.value;
    if (item != null) _heroPreview.scheduleHeroTrailer(item);
  }

  // ── Search field ─────────────────────────────────────────────────────────

  void _onSearchProfileChanged() {
    _titleSection.cancelTitleSuggestions();
    if (_profileSessionOwner != ProfileSessionMemory.captureOwner()) {
      _searchController.clear();
      _keywordSection.clearKeywordSearch();
      _listsSection.clearListsSearch();
      final hadCatalogSearch =
          _catalogSection.catalogQuery.isNotEmpty ||
          _catalogSection.catalogSearching;
      _catalogSection.catalogController.clear();
      if (hadCatalogSearch) _applySections(const []);
    }
  }

  // ── Playback / detail delegation ───────────────────────────────────────────

  /// Load the experimental merged-series-page flag once on init.
  Future<void> _loadMergedSeriesFlag() async {
    final on = await StorageService.getMergedSeriesPageEnabled();
    if (mounted && on != _mergedSeriesPage) {
      setState(() => _mergedSeriesPage = on);
    }
  }

  void _clearSeriesResume() {
    if (mounted) _homeMediaBindings.seriesResume.clear();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _continuationReturn.didChangeAppLifecycleState(state);

  @override
  Widget build(BuildContext context) => buildSearchPageShell(
    context: context,
    glassHome: _heroPreview.heroTrailerActive,
    discoverMode: widget.discoverMode,
    isTelevision: widget.isTelevision,
    dedicatedSearch: widget.searchMode,
    spotlightActive: () => _spotlightShell.spotlightShellActive,
    discover: _discoverSection.buildDiscover,
    board: _buildBoard,
    spotlight: _spotlightShell.buildSpotlightShell,
    header: _inputSection.buildHeader,
    sourcesBar: _inputSection.buildUnifiedCatalogSourcesBar,
    body: _inputSection.buildBody,
  );

  /// Poster width for a board rail. On TV the logical canvas can be as short as
  /// 540px (a 1080p panel at density 320 → devicePixelRatio 2.0), where a poster
  /// tuned for a 720-logical canvas leaves no room for a row (plus its header and
  /// the next row's header) under the hero. So scale the poster with the screen
  /// height.
  double _railPosterW(BuildContext context) =>
      homeRailPosterWidth(context, isTelevision: widget.isTelevision,
        searchResults: widget.searchMode);

  Size _railTitleCardSize(BuildContext context) => homeClassicCardSize(
    posterWidth: _railPosterW(context),
    landscape: _displaySection.homeLandscapeCards,
  );

  double _railTitleCardW(BuildContext context) =>
      _railTitleCardSize(context).width;
  double _railTitleCardH(BuildContext context) =>
      _railTitleCardSize(context).height;

  double _tvHeroBudget(double boardH) => homeClassicHeroBudget(
    boardHeight: boardH,
    cardHeight: _railTitleCardH(context),
    isTelevision: widget.isTelevision,
    searchResults: widget.searchMode,
  );

  // ── Discover tab ────────────────────────────────────────────────────────────

  bool _focusCatalogContinuation() => _catalogFocus.focusAction();

  void _restoreCatalogContinuationFocus() {
    if (_catalogFocus.restore([
      _stageSection.stageFocusTarget(),
      for (final rail in _stageRailsSection.canvasRails)
        ..._stageRailsSection.canvasRailNodes(rail),
    ])) {
      return;
    }
    MainPageBridge.focusTvSidebar?.call();
  }

  Future<void> _continueHomeCatalogs({required bool moreCatalogs}) async {
    final gen = _boardLoadGen;
    bool current() =>
        mounted &&
        gen == _boardLoadGen &&
        _profileSessionOwner == ProfileSessionMemory.captureOwner();
    final actionNode = moreCatalogs ? _catalogMoreNode : _catalogContinueNode;
    final ownedFocus = actionNode.hasFocus;
    final operation = _catalogContinuationController.start(
      moreCatalogs: moreCatalogs,
      boardLoading: _boardLoadingMore,
      rows: _sections,
      hasMoreCatalogs: () => _boardHasMore,
      isCurrent: current,
      loadMoreCatalogs: () async {
        await _loadMoreBoard();
      },
      resumeRow: (section) async {
        final i = _sections.indexOf(section);
        if (i >= 0) await _loadMoreRow(i, resume: true);
      },
    );
    if (operation == null) return;
    try {
      await operation;
    } finally {
      _catalogFocus.restoreAfterCompletion(
        actionNode,
        ownedFocus: ownedFocus,
        isCurrent: current,
        onRestore: _restoreCatalogContinuationFocus,
      );
    }
  }

  Widget _buildBoard() {
    final pending = [
      for (var i = 0; i < _sections.length; i++)
        if (_sections[i].pagingPaused && !_sections[i].exhausted) i,
    ];
    final hasMoreCatalogs = _boardHasMore;
    final busy =
        _catalogContinuing ||
        _boardLoadingMore ||
        pending.any((i) => _sections[i].loadingMore);
    return buildHomeBoardFrame(
      loading: _loading,
      hasError: _error != null,
      hasCatalogs: _sections.isNotEmpty,
      catalogsEmpty: _sections.every((s) => s.items.isEmpty),
      continuationVisible: _continuationProjection.cwVisible,
      favoritesVisible: _savedSection.anyFavVisible,
      hasPausedRows: pending.isNotEmpty,
      hasMoreCatalogs: hasMoreCatalogs,
      busy: busy,
      continueNode: _catalogContinueNode,
      moreNode: _catalogMoreNode,
      onRestoreFocus: _restoreCatalogContinuationFocus,
      onContinueRows: () => _continueHomeCatalogs(moreCatalogs: false),
      onMoreCatalogs: () => _continueHomeCatalogs(moreCatalogs: true),
      content: _buildBoardContent,
      message: _message,
    );
  }

  Widget _buildBoardContent() {
    if (!_loading &&
        !_spotlightSection.spotlightEntryRevealed &&
        widget.isTelevision &&
        !widget.searchMode &&
        !widget.discoverMode &&
        _catalogSection.catalogQuery.isEmpty &&
        !_catalogSection.catalogSearching &&
        _displaySection.homeStyleEffective == 'spotlight') {
      if (_spotlightSection.spotlightHero.isEmpty &&
          (_boardRefreshing || _spotlightSection.heroSourceResolving)) {
        return BrandLoadingStage(isTelevision: true);
      }
      // Reveal once: background refreshes must not hide an already usable
      // board. Hero success enters on the hero; exhaustion enters on a card.
      _spotlightSection.spotlightEntryRevealed = true;
      _autoFocusSettled = false;
      _maybeAutoFocusBoard();
    }
    return buildHomeBoardContent(
      loading: _loading,
      isTelevision: widget.isTelevision,
      error: _error,
      continuationVisible: _continuationProjection.cwVisible,
      catalogsEmpty: _sections.isEmpty,
      favoritesVisible: _savedSection.anyFavVisible,
      traktReserving: _continuationProjection.traktReserving,
      query: _catalogSection.catalogQuery,
      searchFailures: _catalogSearchFailures,
      searchMode: widget.searchMode,
      style: _displaySection.homeStyleEffective,
      spotlightHasContent: () =>
          _spotlightRows.spotlightShelves.any((s) => s.items.isNotEmpty),
      layouts: {
        'canvas': _stageBoards.buildCanvasBoard,
        'atrium': _atriumLayout.buildAtriumBoard,
        'mosaic': _stageBoards.buildMosaicBoard,
        'promenade': _stageBoards.buildPromenadeBoard,
        'deck': _stageBoards.buildDeckBoard,
        'tonight': _tonightLayout.buildTonightBoard,
        'spotlight': _spotlightBoards.buildSpotlightBoard,
      },
      searchSpotlight: _spotlightResults.buildSearchSpotlightBoard,
      classic: _buildClassicBoard,
      onRetry: () => unawaited(_load()),
      message: _message,
    );
  }

  Widget _buildClassicBoard() {
    final tv = widget.isTelevision;
    return buildHomeClassicBoard(
      context: context,
      isTelevision: tv,
      tvHeroBudget: _tvHeroBudget,
      media: () => _boardMedia,
      trailerActive: () => _heroPreview.heroTrailerActive,
      heroActive: () => _heroSection.heroActive,
      readHeroConfiguration: () => (
        compact: widget.searchMode,
        isTelevision: tv,
        artworkCacheWidth: tv
            ? (_displaySection.homeBoardMode
                  ? _tvHeroArtworkCacheWidth
                  : HomeTheme.heroBackdropCacheWidthTv)
            : HomeTheme.heroBackdropCacheWidth,
        artworkCacheHeight: tv
            ? (_displaySection.homeBoardMode
                  ? _tvHeroArtworkCacheHeight
                  : HomeTheme.heroBackdropCacheHeightTv)
            : null,
        trailerActive: _heroPreview.heroTrailerActive,
      ),
      tint: _heroSection.heroTint,
      trailerShowing: _heroPreview.heroTrailerShowing,
      liveTakeover: _heroLive.heroLiveTakeover,
      showSearchStatus: () =>
          _catalogSection.catalogQuery.isNotEmpty &&
          (_catalogSection.catalogSearching || _catalogSearchFailures > 0),
      searchStatus: _buildSearchStatusStrip,
      rowsBuilder: (_) => _buildClassicRows(),
    );
  }

  Widget _buildClassicRows() {
    // Home uses one globally ordered descriptor list across
    // every row family. Catalog search results never read
    // that Home order.
    final orderedHome = _homeRowOrderActive;
    final homeRails = orderedHome
        ? _stageRailsSection.classicHomeRails
        : const <HomeRail>[];
    return HomeClassicRows.fromRails(
      scrollController: _boardScroll,
      generation: _boardGen,
      catalogRowCount: _sections.length,
      rails: orderedHome ? homeRails : null,
      rowIdOf: _stageRailsSection.canvasRailRowId,
      catalog: _buildRow,
      skeleton: _continuationRows.buildTraktSkeletonRow,
      continuation: _continuationRows.buildContinueWatchingRow,
      favorite: _savedRows.buildFavRow,
      showFooter: _boardLoadingMore,
      tailPadding: _classicAnchorTailPadding,
      footerBuilder: (_) => _buildBoardFooter(),
      isFresh: () =>
          DateTime.now().difference(_boardAppliedAt) <
          const Duration(milliseconds: 1800),
    );
  }

  /// Status strip for a streaming catalog search (see the call site in
  /// [_buildBoard]). Fixed height so the swap from "searching" bar to the
  /// failure note doesn't reflow the rows under DPAD focus.
  Widget _buildSearchStatusStrip() => buildCatalogSearchStatus(
    context,
    searching: _catalogSection.catalogSearching,
    failures: _catalogSearchFailures,
  );

  /// "Movies" / "Series" (etc.) tag for a catalog row, so two "Popular" rows
  /// (one movies, one series) are distinguishable. Null for unknown types.
  /// The row's provenance tag: which SOURCE fills it. Tracker list rows name
  /// their tracker; catalog rows name the addon. The content TYPE stopped
  /// being the tag when it moved into the heading itself ("Popular Movies" —
  /// see [CatalogSection.rowTitle]); the addon moved the other way, out of
  /// the heading it used to shout open ("Cinemeta: Popular") and into the
  /// quiet pill this feeds.
  String _sectionTag(CatalogSection section) {
    if (section is HomeCollectionSection) return 'Collection';
    if (section is HomeListSection) {
      return section.isTrakt
          ? 'Trakt'
          : section.isMdblist
          ? 'MDBList'
          : 'Simkl';
    }
    return section.addon.displayName;
  }

  /// Applies the Home presentation preference only to catalog/source
  /// provenance. Continue Watching type tags bypass this helper and remain
  /// visible so identically titled Movies/Series rows stay distinguishable.
  String? _catalogSourceTag(CatalogSection section) =>
      _displaySection.hideHomeCatalogAddonNames ? null : _sectionTag(section);

  /// Poster walls reached by expanding a Home row share Discover's card-detail
  /// controls. Search stays independent: its standalone result walls retain
  /// their normal labels and badges.
  Widget _withHomeExpandedCardSettings(Widget child) {
    if (widget.searchMode || widget.discoverMode) return child;
    final settings = _discoverCardSettingsController.readSnapshot(
      isCurrent: () => mounted,
    );
    return DiscoverCardSettingsScope(
      showTypeTags: settings.showTypeTags,
      showRatings: settings.showRatings,
      showTitles: settings.showTitles,
      child: child,
    );
  }

  late final _seeAllNavigation = HomeSeeAllNavigation(
    isTelevision: () => widget.isTelevision,
    pikpakOnly: () => _pikpakOnly,
    wrap: _withHomeExpandedCardSettings,
    isBound: _isBound,
    afterReturn: _continuationReturn.afterSeeAllReturn,
    afterTrackerReturn: () =>
        _continuationReturn.refreshAfterPlayback(trackers: true),
    traktItems: () => _continuationSection.traktAll,
    traktProgress: () =>
        _continuationSection.cwCardMaps(HomeContinuationKind.trakt).progress,
    simklItems: () => _continuationSection.simklAll,
    simklProgress: () => _continuationSection.simklProgress,
    openTraktItem: _continuationPlayback.openTraktItem,
    playTraktItem: _continuationPlayback.playTraktItem,
    openSimklItem: _continuationPlayback.openSimklItem,
    playSimklItem: _continuationPlayback.playSimklItem,
    openSimklCwItem: _continuationPlayback.openSimklCwItem,
    playSimklCwItem: _continuationPlayback.playSimklCwItem,
    openMdblist: (item) => _itemActions.openItem(
      item,
      _addonForContinue(item.sourceAddon?.id),
      isMdblistSource: true,
    ),
    playMdblist: (item) => _catalogActions.onCatalogPlay(
      item,
      _addonForContinue(item.sourceAddon?.id),
      isMdblistSource: true,
    ),
    openItem: (item, addon) => _itemActions.openItem(item, addon),
    playItem: _catalogActions.onCatalogPlay,
  );

  void _openCatalogSeeAll(CatalogSection section) {
    // Synthetic list/collection rows must never enter catalog pagination.
    if (section is HomeListSection) {
      _seeAllNavigation.openList(context, section);
    } else if (section is HomeCollectionSection) {
      _openCollectionScreen(section.collection, 0);
    } else {
      _seeAllNavigation.openCatalog(context, section);
    }
  }

  double _classicCatalogRowExtent(
    BuildContext context, {
    CatalogSection? section,
  }) => measureHomeClassicRowExtent(
    context,
    hideHeader:
        _displaySection.hideHomeCollectionNames &&
        section is HomeCollectionSection,
    hideSourceTags: _displaySection.hideHomeCatalogAddonNames,
    titleStyle: () => homeCatalogRowTitleStyle(this.context, fontSize: 15),
    cardHeight: () => _railTitleCardH(context),
  );

  Widget _railHeader({
    required String title,
    String? tag,
    VoidCallback? onSeeAll,
  }) => buildHomeCatalogRowHeader(
    context,
    isTelevision: widget.isTelevision,
    title: title,
    tag: tag,
    onSeeAll: onSeeAll,
  );

  Widget _buildRow(int rowIndex, {String? homeRowId}) {
    final section = _sections[rowIndex];
    final nodes = _rowNodes[rowIndex];
    final tv = widget.isTelevision;
    // Bigger, roomier posters on desktop (Stremio-scale); smaller on phones.
    // Titleless cells (Stremio-style) — just the art box + a little headroom
    // for the hover/focus lift. The box follows the Home Cards orientation.
    // Collection rows draw their folders' own tile shape (a brand tile stays
    // wide even when Home cards are portrait) at the same height as every
    // other rail, so the row grammar stays intact.
    final collection = section is HomeCollectionSection ? section : null;
    final cellH = _railTitleCardH(context);
    final cellAspect =
        collection?.tileAspectRatio ?? _stageGeometry.titleCardAspect;
    final posterW = collection == null
        ? _railTitleCardW(context)
        : cellH * cellAspect;
    // Rows start straight on the first poster (Stremio-style, no
    // leading See-All tile). DPAD-up from row 0 leaves the board;
    // col-0 DPAD-left drops to the sidebar (handled in HomeBoardCell
    // when onLeftEdge is null).
    VoidCallback up(int col) => homeRowId != null
        ? () => _focusRelativeHomeRail(homeRowId, -1, col)
        : rowIndex == 0
        ? (_savedSection.anyFavVisible
              ? () => _savedSection.focusFavRowAt(
                  _savedSection.favRowCount - 1,
                  col,
                )
              : (_continuationProjection.cwVisible
                    ? () => _continuationMenu.focusCwRow(
                        _continuationProjection.cwRows.length - 1,
                        col,
                      )
                    : () => _leaveBoardTop()))
        : () => _focusRow(rowIndex - 1, col);
    // Down past the last loaded row kicks the next batch load
    // (inside _focusRow) and defers the move until it lands.
    VoidCallback down(int col) => homeRowId != null
        ? () => _focusRelativeHomeRail(homeRowId, 1, col)
        : () {
            if (!_focusRow(rowIndex + 1, col)) {
              _deferDownMove(rowIndex: rowIndex, column: col);
            }
          };
    return buildHomeCatalogItems(
      section: section,
      nodes: nodes,
      tv: tv,
      header: collection == null || !_displaySection.hideHomeCollectionNames
          ? _railHeader(
              title: section.title,
              tag: _catalogSourceTag(section),
              onSeeAll: () => _openCatalogSeeAll(section),
            )
          : const SizedBox(height: 8),
      cellH: cellH,
      cellAspect: cellAspect,
      posterW: posterW,
      heroTagFor: (col) => 'poster-${identityHashCode(this)}-$rowIndex-$col',
      isBound: _isBound,
      artOf: (item) => _stageGeometry.titleArtUrl(item),
      showTitle: () => !_displaySection.hideHomeCardTitlesAndRatings,
      pikpakOnly: () => _pikpakOnly,
      onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
      up: up,
      down: down,
      onFocused: (item, col) {
        _heroSection.setHero(item);
        _rowCol[rowIndex] = col;
      },
      onOpen: (item, heroTag) =>
          _sectionOpenItem(section, item, heroTag: heroTag),
      onQuickPlay: (item) => _sectionQuickPlay(section, item),
      onLoadMore: () => _loadMoreRow(rowIndex),
    );
  }

  /// Bottom-of-board loading indicator shown while more catalog rows stream in.
  Widget _buildBoardFooter() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _message(
    IconData icon,
    String title,
    String body, {
    VoidCallback? onRetry,
  }) => buildRetryMessage(
    context,
    icon,
    title,
    body,
    isTelevision: widget.isTelevision,
    onRetry: onRetry,
  );



}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
