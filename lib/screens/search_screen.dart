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
import '../features/home/presentation/home_rail_composition.dart';
import '../features/home/presentation/home_stage_favorite_cards.dart';
import '../features/home/presentation/home_classic_navigation.dart';
import '../features/home/presentation/home_stage_navigation.dart';
import '../features/home/presentation/home_tonight_focus.dart';
import '../features/home/presentation/home_mosaic_cell_navigation.dart';
import '../features/home/presentation/home_stage_cards.dart';
import '../features/home/presentation/home_spotlight_favorites.dart';
import '../features/search/presentation/search_spotlight_board.dart';
import '../features/home/presentation/home_spotlight_shelf.dart';
import '../features/search/presentation/catalog_search_status.dart';
import '../features/home/presentation/home_classic_board.dart';
import '../features/home/presentation/home_canvas_board.dart';
import '../features/home/presentation/home_tonight_board.dart';
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
import '../features/home/presentation/home_stage_theater.dart';
import '../features/home/presentation/home_hero_shell.dart';
export '../features/home/presentation/spotlight_iptv_card_preview.dart'
    show SpotlightIptvCardPreview;
import '../features/search/presentation/search_page_shell.dart';
import '../features/home/presentation/home_promenade_board.dart';
import '../features/home/presentation/home_atrium_board.dart';
import '../features/home/presentation/home_atrium_row.dart';
import '../features/home/presentation/home_mosaic_board.dart';
import '../features/home/presentation/home_deck_board.dart';
import '../features/home/presentation/home_stage_row_label.dart';
import '../features/home/presentation/home_tonight_queue_list.dart';
import '../features/home/presentation/home_tonight_rail.dart';
import '../features/home/presentation/home_stage_hold_latch.dart';
import '../features/home/presentation/home_stage_focus_requests.dart';
import '../features/home/presentation/home_stage_deferred_right.dart';
import '../features/home/presentation/home_stage_deferred_advance.dart';
import '../widgets/skeleton_poster.dart' show BrandLoadingStage;
import '../features/home/presentation/home_stage_rows.dart';
import '../features/home/presentation/home_tonight_queue_row.dart';
import '../features/home/presentation/home_favorite_focus.dart';
import '../features/home/models/home_tonight_card_info.dart';
import '../features/home/application/home_stage_metadata.dart';
import '../features/home/presentation/home_classic_rows.dart';
import '../features/home/presentation/home_board_cell.dart';
import '../features/home/models/home_favorite_row_ref.dart';
import '../features/home/presentation/home_favorite_cell.dart';
import '../features/home/presentation/home_art_poster.dart';
import '../features/home/presentation/home_card_style.dart';
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
import '../features/home/application/home_layout_preference.dart';
import '../features/home/application/home_layout_preference_dependencies.dart';
import '../features/home/application/home_default_view.dart';
import '../features/home/application/home_default_view_dependencies.dart';
import '../features/home/application/home_display_preferences_controller.dart';
import '../features/home/models/home_display_preferences.dart';
import '../features/home/presentation/home_progress_publication.dart';
import '../features/home/models/home_stremio_favorites.dart';
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
import '../models/iptv_playlist.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../services/analytics_service.dart';
import '../services/home_collection_rows.dart';
import '../services/home_collections_store.dart';
import '../services/home_list_rows.dart';
import '../services/home_row_order.dart';
import '../services/filtered_catalog_pager.dart';
import '../services/hide_watched_prefs.dart';
import '../services/watched_filter.dart';
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
import '../widgets/home/spotlight_board.dart';
import '../widgets/home/spotlight_catalog_card_cache.dart';
import '../services/tmdb_title_search.dart';
import '../services/metadata_title_service.dart';
import 'collections/collection_folder_screen.dart';
import '../services/mdblist/mdblist_list_source.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../widgets/see_all/discover_card_settings_scope.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../features/home/application/home_layout_policy.dart';

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

/// Smallest poster art a stage rail will draw before it is simply too small
/// to recognise — the floor every derived rail box respects.
const double _kStageMinPosterH = 56;

// ATRIUM metrics. The wall's height is DERIVED from these (never guessed),
// so the dossier column beside it can't be crowded by a taller row.
const double _kAtriumLabelGap = 10;

double _atriumLabelHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(homeStageRowLabelFontSize) * 1.35;

/// Dim painted over every strip cell that isn't focused, so the centre-locked
/// cell reads as the lit one. A flat fill inside the card's own clip (see
/// [CardFocusRise.restVeil]) — no Opacity, no saveLayer.
const Color _kPromRestVeil = Color(0x8C0D0B1A);

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
  late final _spotlightCatalogCards = SpotlightCatalogCardCache(
    wideArtwork: homeStageWideArtwork,
    onOpen: (item, addon) => _itemActions.openItem(item, addon),
  );

  /// Stable ids in the user's global Home-row order. Rows not present append
  /// canonically; ids whose backing row is temporarily unavailable stay saved.
  List<String> get _homeRowOrder => _homeConfiguration.preferences.rowOrder;

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Read in [_load], refreshed by
  /// [_reloadForHomeSettings]; resolved into [_spotlightHeroOverride] by
  /// [_resolveSpotlightHeroSource].
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
    _maybeCompleteStageAdvance();
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
          focusCatalogShelf: _spotlightKey.currentState == null
              ? null
              : () => _spotlightKey.currentState!.focusShelf(0),
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
          captionBand: _homeArtPosterCaptionBand,
          showTitle: () => !_hideHomeCardTitlesAndRatings,
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
        aspectRatio: () => _titleCardAspect,
        showTitleOverlay: () => !_hideHomeCardTitlesAndRatings,
        artOf: _titleArtUrl,
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
        stageActive: () => _stageActive,
        stagePublishesShellArt: () => _stagePublishesShellArt,
        clearFavoriteFocus: () => _canvasFavFocus.value = null,
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
      stageActive: () => _stageActive,
      stageWantsAmbient: () => _stageWantsAmbient,
      homeStyle: () => _homeStyleEffective,
      hasFavoriteFocus: () => _canvasFavFocus.value != null,
      hasLiveChannel: () => _heroLive.heroLiveChannel.value != null,
      spotlightHeroId: () => _spotlightKey.currentState?.currentHeroId,
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
    _homeLayoutPreferenceSubscription = ref.listenManual(
      homeLayoutPreferenceProvider(homeSession),
      (previous, next) {},
    );
    _tvHomeStyle = _homeLayoutPreferenceSubscription.read().initialStyle;
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
    _homeDisplaySubscription = ref.listenManual(
      homeDisplayPreferencesProvider(displaySession),
      (previous, next) {},
    );
    _homeDisplayController = ref.read(
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
      unawaited(_loadTvHomeStyle());
      unawaited(_loadHomeCardOrientation());
      MainPageBridge.tvHomeStyleChanged = _onTvHomeStyleChanged;
      if (widget.isTelevision) {
        MainPageBridge.tvHeroArtworkQualityChanged =
            _onTvHeroArtworkQualityChanged;
        // Canvas theater mode: a dwell after trailer frames land recedes the
        // shelf so the video owns the screen; any key wakes it. Observe-only
        // handler (the key still performs its normal action) — same rule as
        // _heroPreview.onTakeoverKey.
        _heroPreview.heroTrailerShowing.addListener(
          _onCanvasTrailerShowingChanged,
        );
        HardwareKeyboard.instance.addHandler(_onCanvasTheaterKey);
        HardwareKeyboard.instance.addHandler(_stageHold.handleKeyEvent);
      } else {
        // Off-TV Home: system Back closes the Spotlight search sheet before
        // anything else may handle it. Routed through the bridge's tab-back
        // mechanism — a nested PopScope would race the root scope in
        // main.dart (its didPop==false path continues into double-back-exit
        // arming even when an inner scope consumed the press).
        MainPageBridge.registerTabBackHandler('home', _searchSheet.close);
        // Restored keyword results must come back with the sheet open — the
        // full-bleed shell would otherwise hide them behind a hero.
        if (restoredKeyword) _searchSheet.restore();
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
      _inputSection.searchFocusNode.addListener(_searchSheet.onFocusChanged);
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
    unawaited(_loadHomeCardOrientation());
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
    _spotlightHeroOverride = snapshot.hero;
    _addonsById
      ..clear()
      ..addAll(snapshot.board.addons);
    _loading = false;
    _spotlightEntryRevealed = true;
    if (snapshot.heroResolutionPending) {
      unawaited(_resolveSpotlightHeroSource(_addonsById.values.toList()));
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
      hero: _spotlightHeroOverride == null
          ? null
          : copyHomeRowForReturn(_spotlightHeroOverride!),
      heroResolutionPending: _heroSourceResolutionPending,
      cardOrientation: _homeCardOrientation,
      hideCardTitlesAndRatings: _hideHomeCardTitlesAndRatings,
      hideCatalogAddonNames: _hideHomeCatalogAddonNames,
      hideCollectionNames: _hideHomeCollectionNames,
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
    _spotlightHeroNode.dispose();
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
      MainPageBridge.unregisterTabBackHandler('home', _searchSheet.close);
      _inputSection.searchFocusNode.removeListener(_searchSheet.onFocusChanged);
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
    if (MainPageBridge.tvHomeStyleChanged == _onTvHomeStyleChanged) {
      MainPageBridge.tvHomeStyleChanged = null;
    }
    if (MainPageBridge.tvHeroArtworkQualityChanged ==
        _onTvHeroArtworkQualityChanged) {
      MainPageBridge.tvHeroArtworkQualityChanged = null;
    }
    if (widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      _heroPreview.heroTrailerShowing.removeListener(
        _onCanvasTrailerShowingChanged,
      );
      HardwareKeyboard.instance.removeHandler(_onCanvasTheaterKey);
      HardwareKeyboard.instance.removeHandler(_stageHold.handleKeyEvent);
    }
    _stageTheater.dispose();
    _canvasFavFocus.dispose();
    _atriumFocusedRailKey.dispose();
    _tonightFocus.dispose();
    _stageCol.dispose();
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
    _homeLayoutPreferenceSubscription.close();
    _heroPreview.heroTrailerPreferencesSubscription.close();
    _homeDefaultViewSubscription.close();
    _homeDisplaySubscription.close();
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
    refreshDisplay: (current) => _loadHomeCardOrientation(isCurrent: current),
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
      unawaited(_resolveSpotlightHeroSource(_addonsById.values.toList()));
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
                unawaited(_resolveSpotlightHeroSource(addons));
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
            !_spotlightEntryRevealed &&
            widget.isTelevision &&
            _homeStyleEffective == 'spotlight') {
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
          _maybeCompleteStageAdvance();
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
      _maybeCompleteStageRight();
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
        final rails = _canvasRails;
        final current = rails.indexWhere(
          (rail) => _canvasRailRowId(rail) == homeRowId,
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

  /// First of [a], [b] that is a non-empty string, else null.
  String? _firstNonEmpty(String? a, String? b) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

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
    if (incremental && _homeStyleEffective == 'classic') {
      final rails = _classicHomeRails;
      for (final rail in rails) {
        if (rail.traktSkeletonIndex >= 0) continue;
        final focused = _canvasRailNodes(rail).where((node) => node.hasFocus);
        if (focused.isEmpty) continue;
        anchor = _canvasRailRowId(rail);
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
      previousOrder = rails.map(_canvasRailRowId).toList();
      if (anchor != null &&
          _boardScroll.hasClients &&
          _boardScroll.position.maxScrollExtent <= 0) {
        // A short first batch leaves unused viewport space below its rows.
        // Retain that space as tail padding when rows are inserted above the
        // anchor, otherwise scroll physics clamps away the preserved offset.
        final heights = <double>[];
        for (final rail in rails) {
          if (rail.traktSkeletonIndex >= 0) break;
          final nodes = _canvasRailNodes(rail);
          final height = nodes
              .map(
                (node) => homeRowHeight(
                  node.context,
                  ValueKey('board-reveal-$_boardGen-${_canvasRailRowId(rail)}'),
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
      _stageDeferredAdvance.invalidateForBoardReseed();
      _stageFocusRequests.invalidate();
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
        final nextOrder = _classicHomeRails.map(_canvasRailRowId).toList();
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
    _publishTopShelfSpotlight();
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
        _canvasFavFocus.value = null;
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
        _spotlightHeroNode.hasFocus) {
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
    if (_stageActive) return _stageFocusTarget();
    for (final rail in _canvasRails) {
      final nodes = _canvasRailNodes(rail);
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
    if (_stageActive) {
      final target = _stageFocusTarget();
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

    for (final rail in _canvasRails) {
      if (tryRow(_canvasRailNodes(rail))) return;
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

  /// Active home layout, from `tv_home_style`. The HOME board renders it on
  /// TV; off-TV the pref is resolved through [effectiveOffTvHomeStyle] and
  /// only Spotlight passes through — Search tab and Discover always render
  /// classic (via [_homeStyleEffective], regardless of this field). Canvas is
  /// the TV default; matching it here avoids a one-frame classic flash at
  /// boot there, and resolves to classic off-TV.
  late String _tvHomeStyle;
  late final ProviderSubscription<HomeLayoutPreference>
  _homeLayoutPreferenceSubscription;

  // Landscape default matches the stored default, so a fresh boot doesn't
  // flash portrait rows before the async pref read lands.
  late final HomeDisplayPreferencesController _homeDisplayController;
  late final ProviderSubscription<HomeDisplayPreferences>
  _homeDisplaySubscription;
  HomeDisplayPreferences get _homeDisplay => _homeDisplayController.current;
  HomeCardOrientation get _homeCardOrientation => _homeDisplay.orientation;
  bool get _hideHomeCardTitlesAndRatings => _homeDisplay.hideTitlesAndRatings;
  bool get _hideHomeCatalogAddonNames => _homeDisplay.hideCatalogAddonNames;
  bool get _hideHomeCollectionNames => _homeDisplay.hideCollectionNames;
  bool get _spotlightFocusDetails => _homeDisplay.spotlightFocusDetails;
  bool get _homeAnimationsEnabled => _homeDisplay.animationsEnabled;
  String get _homeAnimationStyle => _homeDisplay.animationStyle;

  bool get _homeLandscapeCards =>
      _homeCardOrientation == HomeCardOrientation.landscape;

  double get _homeArtPosterCaptionBand =>
      _hideHomeCardTitlesAndRatings ? 0 : HomeArtCaption.band(context);

  bool get _homeBoardMode =>
      widget.isTelevision && !widget.searchMode && !widget.discoverMode;

  // ── Off-TV Spotlight shell state ─────────────────────────────────────────
  //
  // Four separate questions, deliberately not one predicate (the sheet is a
  // latched state machine — see SPOTLIGHT_RESPONSIVE_PLAN.md):
  //  • [_spotlightSelected] — the resolved pref says Spotlight.
  //  • [_spotlightShellActive] — this Home instance renders the shell branch
  //    (either of its two states) instead of the plain classic Column.
  //  • [_sheetForced] — search state that REQUIRES the header on screen.
  //  • [_searchSheetOpen] — the latch. Set by the search button, by field
  //    focus, and silently whenever [_sheetForced] is observed true; cleared
  //    only by the explicit close/back reset. The latch is what stops the
  //    header collapsing under a focused field when its force condition
  //    momentarily clears (deleting the last character of a query).

  /// The stored style, resolved for this platform, is Spotlight. Off-TV only.
  bool get _spotlightSelected =>
      !widget.isTelevision &&
      effectiveOffTvHomeStyle(_tvHomeStyle) == 'spotlight';

  /// Whether the off-TV Home renders the Spotlight shell branch. While the
  /// selected layout is loading, retain this branch so a newly mounted Home
  /// cannot flash Classic's persistent search bar before its hero arrives.
  /// After loading, the hero guard still matters: CW/favourites-only content
  /// would otherwise render a large empty hero.
  bool get _spotlightShellActive =>
      !widget.searchMode &&
      !widget.discoverMode &&
      shouldUseOffTvSpotlightShell(
        rawStyle: _tvHomeStyle,
        loading: _loading,
        hasHero: _spotlightHero.isNotEmpty,
      );

  /// Search state that forces the header/sheet to be visible. Typing is
  /// covered by the focus latch (one can only type while the field is
  /// focused, and focus latches [_searchSheetOpen]); this covers the states
  /// that arrive WITHOUT the field being touched: the async keyword-default
  /// restore, preserved keyword results, a committed catalog search, or the
  /// dedicated Lists surface.
  bool get _sheetForced =>
      _modeSection.mode != SearchMode.catalog ||
      _catalogSection.catalogQuery.isNotEmpty ||
      _catalogSection.catalogSearching ||
      // Belt to the focus latch's braces: interactive typing always comes
      // through a focused field, but autofill or a programmatic controller
      // write would not — and text on screen must force the header that
      // renders it.
      _searchController.text.isNotEmpty;

  /// The sheet latch. See the block comment above.
  late final _searchSheet = SpotlightSearchSheet(
    field: _inputSection.searchFocusNode,
    isForced: () => _sheetForced,
    hasText: () => _searchController.text.isNotEmpty,
    isSpotlightSelected: () => _spotlightSelected,
    resetSearch: () {
      // Mode changes before clearing requests, results and the field.
      _modeSection.mode = SearchMode.catalog;
      _modeSection.clearQuery();
    },
    rebuild: setState,
    isCurrent: () => mounted,
  );
  bool get _searchSheetOpen => _searchSheet.isOpen;

  int get _tvHeroArtworkCacheWidth =>
      TvHeroArtworkQualityController.decodeSize.landscapeWidth;
  int get _tvHeroArtworkCacheHeight =>
      TvHeroArtworkQualityController.decodeSize.posterHeight;

  /// The layout the CURRENT surface should render (guards non-home surfaces).
  /// The layout the CURRENT surface should render. TV: the stored style on
  /// the Home board, classic everywhere else. Off-TV: Spotlight only while
  /// the full-bleed shell is actually on screen — results, keyword mode and
  /// the open search sheet all dispatch to the classic board, so the search
  /// experience is byte-identical to today whenever search is in play.
  String get _homeStyleEffective {
    if (widget.isTelevision) return _homeBoardMode ? _tvHomeStyle : 'classic';
    return _spotlightShellActive && !_searchSheetOpen ? 'spotlight' : 'classic';
  }

  bool get _stageActive => isHomeStageLayout(_homeStyleEffective);

  bool get _stageWantsAmbient => homeStageWantsAmbient(_homeStyleEffective);

  // Live channel previews remain available on every stage, including Mosaic.
  bool get _stageWantsLivePreview => _stageActive;

  bool get _stagePublishesShellArt =>
      homeStagePublishesShellArt(_homeStyleEffective);

  bool get _theaterEligible => homeStageTheaterEligible(_homeStyleEffective);

  late final HomeStageFocusRequests _stageFocusRequests = HomeStageFocusRequests(
    isMounted: () => mounted,
    readStyle: () => _homeStyleEffective,
  );

  late final HomeStageDeferredAdvance _stageDeferredAdvance =
      HomeStageDeferredAdvance(
        stageActive: () => _stageActive,
        maxAge: _pendingDownMaxAge,
      );

  late final HomeStageDeferredRight _stageDeferredRight = HomeStageDeferredRight(
    currentRail: () => _canvasRailKey,
    stageActive: () => _stageActive,
    scheduleFocus: _stageFocusRequests.schedule,
    maxAge: _pendingDownMaxAge,
  );

  void _maybeCompleteStageRight() {
    _stageDeferredRight.complete((key, column) {
      final rails = _stageRails;
      final i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
      if (i < 0) return null;
      final nodes = _canvasRailNodes(rails[i]);
      if (column >= nodes.length) return null;
      return (nodes[column].context?.mounted ?? false) ? nodes[column] : null;
    });
  }

  /// Every piece of per-layout navigation state, cleared as one. Called on a
  /// real layout transition (either the picker or the saved pref landing at
  /// cold start) — never partially, or a layout inherits a rail/zone/column
  /// that means something else in its own geometry.
  void _resetStageNavigation() {
    _stageNavigation.resetSeed();
    _stageTheater.reset();
    _canvasFavFocus.value = null;
    _canvasRailKey = null;
    _canvasCols.clear();
    _tonightFocus.resetPosition();
    _atriumFocusedRailKey.value = null;
    _tonightCard.value = null;
    _stageCol.value = 0;
    _stageDeferredAdvance.reset();
    _stageDeferredRight.reset();
    _stageHold.reset();
    _stageFocusRequests.invalidate();
  }

  /// THE single layout-transition path. Both entry points route here — the
  /// Settings picker AND the cold-start load, which is also a transition
  /// (the field starts at the product default, so a saved 'mosaic' relayouts
  /// a board that may already have a trailer or a live preview running).
  void _applyStageTransition(String style) {
    // Tear the live players down BEFORE the relayout: the underlay engine
    // widget must never be re-parented into a different geometry mid-play.
    _heroPreview.clearHeroTrailer();
    _heroLive.clearHeroLiveIptv();
    _resetStageNavigation();
    // The shell's ambient art is per-layout (ink-ground layouts publish
    // none), so clear it rather than leaving the old layout's lighting in
    // the strip behind the ghost rail.
    _heroSection.ambientArtItemId = null;
    if (MainPageBridge.tvAmbientArt.value != null) {
      MainPageBridge.tvAmbientArt.value = null;
    }
    setState(() => _tvHomeStyle = style);
    // …then republish for the layout we just switched TO: Canvas/Promenade
    // want the shell lit again, and the ink layouts want it to stay dark.
    // Without this the shell keeps whatever the previous layout left until
    // some unrelated hero change happens to refresh it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _heroSection.publishAmbientArt(
        _heroSection.heroItem.value,
        _heroSection.heroEnriched.value,
      );
      _heroSection.publishHeroTintToShell(_heroSection.heroTint.value);
    });
  }

  Future<void> _loadTvHomeStyle() =>
      _homeLayoutPreferenceSubscription.read().load(
        isCurrent: () => mounted,
        currentStyle: () => _tvHomeStyle,
        transition: _applyStageTransition,
      );

  Future<void> _loadHomeCardOrientation({bool Function()? isCurrent}) async {
    final changed = await _homeDisplayController.load(
      isCurrent: () => mounted && (isCurrent?.call() ?? true),
    );
    if (mounted && changed) setState(() {});
  }

  /// Settings picker fired: tear down live players BEFORE the relayout, so
  /// the underlay engine widget is never re-parented mid-play, then re-read
  /// the pref and rebuild.
  void _onTvHomeStyleChanged() {
    if (!mounted) return;
    unawaited(_loadTvHomeStyle());
  }

  void _onTvHeroArtworkQualityChanged() {
    if (!mounted || !_homeBoardMode) return;
    setState(() {});
  }

  // ── CANVAS view ──────────────────────────────────────────────────────────

  /// IDENTITY of the active Canvas rail (not an index): rails stream in and
  /// reorder — CW rails prepend when Trakt/Simkl land seconds after a cold
  /// start — and a raw index would silently swap the shelf's content and
  /// teleport focus/hero when that happens. Null = first rail.
  late final _stageNavigation = HomeStageNavigation(
    keyOf: _canvasRailKeyOf,
    nodesFor: _canvasRailNodes,
    itemsFor: _canvasRailItems,
  );
  String? get _canvasRailKey => _stageNavigation.activeKey;
  set _canvasRailKey(String? key) => _stageNavigation.activeKey = key;

  /// The focused column of the active rail, as a notifier — Deck's peek stack
  /// has to re-derive "the next two titles" on every horizontal move, and the
  /// remembered-column MAP is a plain field write that rebuilds nothing.
  final ValueNotifier<int> _stageCol = ValueNotifier<int>(0);

  /// Remembered column per rail key (the Canvas mirror of classic's _rowCol).
  Map<String, int> get _canvasCols => _stageNavigation.columns;

  /// Stage override while a favourites cell has focus (see
  /// [HomeFavoriteFocus]). A ValueNotifier — NOT setState — so scrubbing along
  /// a favourites rail repaints only the stage layers that listen (art +
  /// identity), never the whole board (the hero pipeline's own pattern).
  final ValueNotifier<HomeFavoriteFocus?> _canvasFavFocus =
      ValueNotifier<HomeFavoriteFocus?>(null);

  /// A Canvas favourites cell took focus: remember the column, stop any
  /// catalog trailer machinery (a PENDING hero swap firing later would start
  /// a full-bleed trailer of an unrelated title under favourites browsing),
  /// drive the live preview for IPTV, and hand the stage the favourite's own
  /// art + name.
  void _canvasFavFocused(
    String railKey,
    int col,
    HomeFavoriteFocus focus, {
    IptvChannel? liveChannel,
  }) {
    _canvasCols[railKey] = col;
    _stageCol.value = col;
    // Atrium's two-row window needs to know which row owns focus (favourites
    // cells don't go through a HomeBoardCell onFocused), and favourites only
    // ever live in Tonight's RAIL zone, never its Continue queue.
    _atriumFocusedRailKey.value = railKey;
    _tonightZoneIsQueue = false;
    _heroSection.heroSwap.cancel();
    _heroPreview.clearHeroTrailer();
    if (liveChannel != null && _stageWantsLivePreview) {
      _heroLive.setHeroLiveIptv(liveChannel);
    } else {
      _heroLive.clearHeroLiveIptv();
    }
    _canvasFavFocus.value = focus;
  }

  /// One favourites cell on the Canvas shelf — the SAME [HomeFavoriteCell] +
  /// [HomeArtPoster] stack the classic rows use (identical art, badges, hold
  /// behaviour and open actions), with UP/DOWN rewired to rail switching and
  /// focus driving the Canvas stage override (and the full-bleed live
  /// preview, for IPTV).
  Widget _canvasFavCell(
    HomeFavoriteRowRef ref,
    String railKey,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
  }) {
    final cells = HomeStageFavoriteCards(
      nodes: _savedSection.favNodesFor(ref),
      column: col,
      showTitle: !_hideHomeCardTitlesAndRatings,
      onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
      onUp: onUp ?? () => _stageSwitchRail(-1),
      onDown: onDown ?? () => _stageSwitchRail(1),
      onLeft: onLeft,
      onRight: onRight,
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onFocused: (focus, liveChannel) =>
          _canvasFavFocused(railKey, col, focus, liveChannel: liveChannel),
    );
    if (ref.isIptvList) {
      final row = _savedSection.iptvListRows[ref.list];
      final channel = row.channels[col];
      return cells.iptv(
        channel,
        subtitle: () => 'IPTV · ${row.title.toUpperCase()}',
        previewLive: channel.isLive,
        onOpen: () => _savedIptv.playIptvListChannel(channel),
      );
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        final items = ref.kind == HomeFavoriteKind.watchlistMovies
            ? _savedSection.watchlistMovieItems
            : _savedSection.watchlistSeriesItems;
        final item = items[col];
        return cells.watchlist(
          item,
          onOpen: () => _watchlistActions.openMyWatchlistItem(item),
        );
      case HomeFavoriteKind.iptv:
        final channel = _savedSection.iptvFavChannels[col];
        return cells.iptv(
          channel,
          subtitle: () => 'IPTV · FAVORITES',
          previewLive: true,
          onOpen: () => _savedIptv.playIptvChannel(channel),
        );
      case HomeFavoriteKind.debrify:
        final channel = _savedSection.tvFavChannels[col];
        return cells.debrify(
          channel,
          onOpen: () => _savedSection.playChannel(channel),
        );
      case HomeFavoriteKind.stremio:
        final channel = _savedSection.stvFavChannels[col];
        return cells.stremio(
          channel,
          item: _savedSection.stvNowPlaying(channel)?.item,
          onOpen: () => _savedSection.playStremioTvChannel(channel),
        );
      case HomeFavoriteKind.playlist:
        final item = _savedSection.playlistItems[col];
        return cells.playlist(
          item,
          progress: _savedSection.playlistController.current.progressFor(item),
          onOpen: () => _playlistActions.onPlaylistItemTap(item),
        );
    }
  }

  /// Theater mode: after the ambient trailer has been SHOWING frames for a
  /// dwell, the shelf/tabs (and their bottom scrim) recede so the video owns
  /// the whole screen — logo + AMBIENT chip hold. Any key wakes the lights
  /// (observe-only: the key still does its job), and if playback continues
  /// uninterrupted the dwell re-arms. The shelf is hidden VISUALLY only
  /// (opacity/slide, never unmounted), so focus stays exactly where it was.
  late final HomeStageTheater _stageTheater = HomeStageTheater(
    isCurrent: () => mounted,
    isEligible: () => _theaterEligible,
    isShowing: () => _heroPreview.heroTrailerShowing.value,
    onChanged: () => setState(() {}),
  );
  bool get _canvasTheater => _stageTheater.active;

  void _onCanvasTrailerShowingChanged() => _stageTheater.showingChanged();

  bool _onCanvasTheaterKey(KeyEvent event) => _stageTheater.handleKey(event);

  String _canvasRailKeyOf(HomeRail rail) {
    return 'row:${_canvasRailRowId(rail)}';
  }

  /// Where the active rail currently sits in [rails] — re-resolved every
  /// build so insertions above it never change WHICH rail is shown.
  int _resolveCanvasRailIndex(List<HomeRail> rails) =>
      _stageNavigation.resolveIndex(rails);

  FocusNode? _nearestMountedNode(List<FocusNode> nodes, int col) =>
      HomeStageNavigation.nearestMountedNode(nodes, col);

  // ── Spotlight ───────────────────────────────────────────────────────────

  final GlobalKey<SpotlightBoardState> _spotlightKey =
      GlobalKey<SpotlightBoardState>();
  final FocusNode _spotlightHeroNode = FocusNode(debugLabel: 'spotlight-hero');

  /// The hero reel fetched from the user's chosen source (`random`/`custom`
  /// modes), fetched by [_resolveSpotlightHeroSource] independently of the
  /// board batches — the chosen catalog may sit pages down the board, or be
  /// hidden as a row entirely. Null in `auto` mode, while the fetch is in
  /// flight, and when every candidate came up dead — all of which fall back
  /// to the first non-empty board row below.
  CatalogSection? _spotlightHeroOverride;

  /// Guards [_resolveSpotlightHeroSource] against overlapping runs (a Home
  /// Rows save landing mid-load): only the newest run may commit.
  int _heroSourceResolveGen = 0;
  bool _heroSourceResolving = false;
  // The presentation deadline can expire while the underlying request is
  // still pending. A return snapshot must resume that request too.
  bool _heroSourceResolutionPending = false;
  bool _spotlightEntryRevealed = false;

  /// Fetch the hero reel for the current [_heroSource] pref.
  ///
  /// Candidates come from the FULL browsable set, not [_boardRefs] — hiding a
  /// catalog's row on the board must not blank a hero pinned to that same
  /// catalog. Candidates are shuffled so `random` mode and a multi-pick
  /// `custom` re-roll on every board load; the first candidate that returns
  /// items wins. Attempts are capped so a wall of dead catalogs can't fan out
  /// unbounded fetches; exhausting the cap (or the candidates) clears the
  /// override, which IS the auto fallback.
  Future<void> _resolveSpotlightHeroSource(List<StremioAddon> addons) async {
    final gen = ++_heroSourceResolveGen;
    _heroSourceResolving = true;
    _heroSourceResolutionPending = true;
    try {
      // The initial presentation must not wait forever on a dead hero source.
      // A late result may still populate the reel after the cards fallback.
      await _fetchSpotlightHeroSource(addons, gen).whenComplete(() {
        if (mounted && gen == _heroSourceResolveGen) {
          _heroSourceResolutionPending = false;
        }
      }).timeout(
        const Duration(seconds: 25),
        onTimeout: () {},
      );
    } finally {
      if (mounted && gen == _heroSourceResolveGen) {
        setState(() => _heroSourceResolving = false);
      }
    }
  }

  Future<void> _fetchSpotlightHeroSource(List<StremioAddon> addons, int gen) async {
    final source = _heroSource;
    if (source.mode != HomeHeroSourceMode.auto) {
      final all = [
        for (final a in addons)
          for (final c in a.catalogs)
            if (c.isBrowsable) (a, c),
      ];
      final List<(StremioAddon, StremioAddonCatalog)> candidates;
      if (source.mode == HomeHeroSourceMode.random) {
        // Random draws TITLES only. Live catalogs — 'tv' is what the
        // Stremio-IPTV service itself keys on, 'channel'/'radio' are the
        // spec's other live-ish types — serve channel logos as their art, so
        // the reel cover-crops a wordmark to a full screen (TvVoo's logo,
        // full-bleed, was the report). An EXPLICIT custom pick of such a
        // catalog is left alone: choosing it by name is a deliberate act.
        const live = {'tv', 'channel', 'radio'};
        candidates = [
          for (final ref in all)
            if (!live.contains(ref.$2.type.toLowerCase())) ref,
        ];
      } else {
        // Stored picks that no longer resolve (addon uninstalled, catalog
        // gone from its manifest) simply drop out; they are NOT removed from
        // the pref, so reinstalling the addon brings the pick back.
        final byId = {
          for (final (a, c) in all) '${a.id}:${c.type}:${c.id}': (a, c),
        };
        candidates = [
          for (final id in source.ids)
            if (byId.containsKey(id)) byId[id]!,
        ];
      }
      candidates.shuffle(Random());
      const maxAttempts = 8;
      var attempts = 0;
      for (final (addon, catalog) in candidates) {
        if (attempts++ >= maxAttempts) break;
        if (!mounted || gen != _heroSourceResolveGen) return;
        try {
          final page = await fetchFilteredPage(
            (skip, onRaw) => _stremio.fetchCatalog(
              addon,
              catalog,
              skip: skip,
              onRawCount: onRaw,
            ),
            skip: 0,
            hides: WatchedFilter.predicate,
            minItems: 8,
          );
          if (!mounted || gen != _heroSourceResolveGen) return;
          if (page.items.isEmpty) continue;
          setState(() {
            _spotlightHeroOverride = CatalogSection(
              title: CatalogSection.rowTitle(catalog),
              addon: addon,
              catalog: catalog,
              items: page.items.toList(),
              nextSkip: page.nextSkip,
            );
          });
          _publishTopShelfSpotlight();
          return;
        } catch (_) {
          // Dead addon or catalog — try the next candidate.
        }
      }
    }
    // Auto mode, no usable candidate, or every attempt failed — drop any
    // stale override so the reel falls back rather than pinning old prefs.
    if (!mounted || gen != _heroSourceResolveGen) return;
    if (_spotlightHeroOverride != null) {
      setState(() => _spotlightHeroOverride = null);
    }
    _publishTopShelfSpotlight();
  }

  /// The hero reel.
  ///
  /// NOT `_stageRails[0]`: the user's first row may be a channel, playlist, or
  /// Continue Watching rail rather than a catalog, and rails can arrive as
  /// tracker data lands. The hero needs a
  /// stable list of real catalog titles, so it takes the user's resolved
  /// source pick when there is one, else the first section that has any items
  /// — and caps it either way: a reel longer than about eight is a list, not
  /// a hero.
  CatalogSection? get _spotlightHeroSection {
    // A catalog search swaps `_sections` to results, and the reel follows
    // them — the pinned source is Home-board furniture and must not paint
    // over a search.
    final override = _spotlightHeroOverride;
    if (override != null &&
        _catalogSection.catalogQuery.isEmpty &&
        !_catalogSection.catalogSearching) {
      return override;
    }
    for (final section in _sections) {
      // Folder tiles aren't titles, so they can't feed the hero reel.
      if (section is HomeCollectionSection) continue;
      if (section.items.isNotEmpty) return section;
    }
    return null;
  }

  List<StremioMeta> get _spotlightHero =>
      _spotlightHeroSection?.items.take(8).toList() ?? const [];

  void _publishTopShelfSpotlight() {
    if (!PlatformUtil.isTvOS || widget.searchMode || widget.discoverMode) {
      return;
    }
    unawaited(
      TvosTopShelfService.instance.publishSpotlight(
        _spotlightHero,
        sourceTitle: _spotlightHeroSection?.title,
      ),
    );
  }

  List<SpotlightShelf> get _spotlightShelves => [
    for (final rail in _canvasRails) _spotlightShelfForRail(rail),
  ];

  SpotlightShelf _spotlightShelfForRail(HomeRail rail) =>
      buildHomeSpotlightShelf(
        rail,
        railKey: _canvasRailKeyOf(rail),
        landscape: _homeLandscapeCards,
        hideCollectionNames: _hideHomeCollectionNames,
        sections: _sections,
        rowNodes: _rowNodes,
        catalogTag: _catalogSourceTag,
        onSeeAll: _openCatalogSeeAll,
        onCollectionOpen: _openCollectionFolder,
        onContinuationOptions: _continuationMenu.openCwCardMenu,
        favoriteShelf: _spotlightFavShelf,
        catalogCard: (item, addon) => _spotlightCatalogCards.resolve(
          item,
          addon,
          landscape: _homeLandscapeCards,
        ),
      );

  /// A favourites rail as Spotlight cards.
  ///
  /// The four kinds are NOT the same shape. A playlist is a container rather
  /// than a title, so it keeps the poster it was given (or its override) and
  /// says how many items it holds. The three channel kinds carry LOGOS — wide,
  /// frequently transparent marks — which a 2:3 crop cuts in half, so they get
  /// a square tile that contains the art on a plate instead of filling with it.
  SpotlightShelf _spotlightFavShelf(HomeFavoriteRowRef ref, {String? id}) {
    final nodes = _savedSection.favNodesFor(ref);
    if (ref.isIptvList) {
      final row = _savedSection.iptvListRows[ref.list];
      return buildSpotlightIptvFavorites(
        id: id,
        title: row.title,
        nodes: nodes,
        channels: row.channels,
        landscape: _homeLandscapeCards,
        previewVolume: () => _heroPreview.heroTrailerVolume,
        onOpen: _savedIptv.playIptvListChannel,
      );
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        final movies = ref.kind == HomeFavoriteKind.watchlistMovies;
        return buildSpotlightWatchlist(
          id: id,
          nodes: nodes,
          items: movies
              ? _savedSection.watchlistMovieItems
              : _savedSection.watchlistSeriesItems,
          movies: movies,
          landscape: _homeLandscapeCards,
          onOpen: _watchlistActions.openMyWatchlistItem,
        );
      case HomeFavoriteKind.playlist:
        return buildSpotlightPlaylists(
          id: id,
          nodes: nodes,
          items: _savedSection.playlistItems,
          progress: _savedSection.playlistController.current.progressFor,
          onOpen: _playlistActions.onPlaylistItemTap,
        );
      case HomeFavoriteKind.iptv:
        return buildSpotlightIptvFavorites(
          id: id,
          title: 'IPTV Favourites',
          nodes: nodes,
          channels: _savedSection.iptvFavChannels,
          landscape: _homeLandscapeCards,
          previewVolume: () => _heroPreview.heroTrailerVolume,
          onOpen: _savedIptv.playIptvChannel,
        );
      case HomeFavoriteKind.debrify:
        return buildSpotlightDebrifyFavorites(
          id: id,
          nodes: nodes,
          channels: _savedSection.tvFavChannels,
          landscape: _homeLandscapeCards,
          onOpen: _savedSection.playChannel,
        );
      case HomeFavoriteKind.stremio:
        return buildSpotlightStremioFavorites(
          id: id,
          nodes: nodes,
          channels: _savedSection.stvFavChannels,
          landscape: _homeLandscapeCards,
          artwork: _stvFavArt,
          nowPlaying: (channel) => _savedSection.stvNowPlaying(channel)?.item,
          onOpen: _savedSection.playStremioTvChannel,
        );
    }
  }

  /// A Stremio TV favourite's card art: the channel's rotating now-playing
  /// poster — the same resolution the classic and Canvas rails use. Spotlight
  /// landscape mode instead chooses the title's best wide art. Null
  /// (placeholder) until the channel's items load.
  String? _stvFavArt(HomeStremioFavorite ch, {bool landscape = false}) {
    final item = _savedSection.stvNowPlaying(ch)?.item;
    if (item == null) return null;
    if (landscape) return homeStageWideArtwork(item);
    return _firstNonEmpty(item.poster, item.background);
  }

  HomeBoardMedia get _boardMedia => HomeBoardMedia(
    item: _heroSection.heroItem,
    enriched: _heroSection.heroEnriched,
    favorite: _canvasFavFocus,
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

  Widget _buildSearchSpotlightBoard() => buildSearchSpotlightBoard(
    context: context,
    sections: List<CatalogSection>.of(_sections),
    rowNodes: _rowNodes,
    boardKey: _spotlightKey,
    heroNode: _spotlightHeroNode,
    query: _catalogSection.catalogQuery,
    searching: _catalogSection.catalogSearching,
    failures: _catalogSearchFailures,
    landscape: _homeLandscapeCards,
    showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
    expandFocusedCard: _spotlightFocusDetails,
    trailersEnabled: _heroPreview.heroTrailerEnabled,
    trailerVolume: _heroPreview.heroTrailerVolume,
    onExitTop: _leaveBoardTop,
    onTrailerStop: _heroPreview.clearHeroTrailer,
    onHeroOpen: _itemActions.openItem,
    onOpen: _sectionOpenItem,
    onPlay: _pikpakOnly ? null : _catalogActions.onCatalogPlay,
    sourceTag: _catalogSourceTag,
    onSeeAll: _openCatalogSeeAll,
    onLoadMore: (section) {
      final current = _sections.indexOf(section);
      if (current >= 0) unawaited(_loadMoreRow(current));
    },
  );

  Widget _buildSpotlightBoard() {
    // Snapshot row descriptors with the shelf list: async inserts must not
    // make a callback page a different catalog than the shelf it came from.
    final rails = _canvasRails;
    return SpotlightBoard(
      largeScreenInteractions: true,
      key: _spotlightKey,
      animationsEnabled: _homeAnimationsEnabled,
      animationStyle: _homeAnimationStyle,
      hero: _spotlightHero,
      sections: _spotlightShelves,
      heroNode: _spotlightHeroNode,
      heroAddon: _spotlightHeroSection?.addon,
      dpad: widget.isTelevision,
      showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
      expandFocusedCard: _spotlightFocusDetails,
      cardTrailerVolume: _heroPreview.heroTrailerVolume,
      onHeroOpen: _itemActions.openItem,
      onLoadMoreRow: (row) {
        if (row < 0 || row >= rails.length) return;
        final catalogRow = rails[row].sectionIndex;
        if (catalogRow != null) unawaited(_loadMoreRow(catalogRow));
      },
      onLoadMoreShelves: _loadMoreBoard,
      pendingShelves: PlatformUtil.isAndroidTvCached && _boardRowsPending,
      // The board owns the CADENCE; the resolve and the video stay here.
      //
      // Every other entry into `_heroPreview.scheduleHeroTrailer` is still excluded for
      // this style — init, section loads, focus changes, `_heroSection.applyHero`, route
      // return, sidebar return — so the board's clock is the single owner and
      // the two cannot start a trailer under different titles.
      // Suppression is enforced inside
      // _heroPreview.scheduleHeroTrailer. Folding it in here disarms the board's dwell
      // clock entirely — and the dwell is the only event that can LIFT the
      // suppression when the reel moves to a new title, so one post-playback
      // rebuild would have frozen trailers until the tab was recreated.
      trailersEnabled: _heroPreview.heroTrailerEnabled,
      onDwell: (item) =>
          _heroPreview.scheduleHeroTrailer(item, fromSpotlight: true),
      onTrailerStop: _heroPreview.clearHeroTrailer,
      // Full bleed on every form factor — a letterboxed 16:9 band was tried
      // on the phone and read as a TV set embedded in the artwork (user call).
      // The portrait cover-crop is the design; sharpness comes from the 1080p
      // resolve and medium-filter texture sampling.
      trailer: _heroPreview.heroTrailerRenderable
          ? _boardMedia.trailerLayer(540, fullBleed: true)
          : null,
      // TV only: the glass stage the publish feeds exists behind the TV
      // sidebar rail. Off-TV there is no consumer, and writing the shared
      // notifiers from a phone Home would leave stale art for the next TV
      // session of a hot-restarted debug run.
      onAmbient: widget.isTelevision
          ? (art, tint) {
              if (!mounted) return;
              MainPageBridge.tvAmbientArt.value = art;
              MainPageBridge.tvHeroTint.value = tint;
            }
          : null,
    );
  }

  /// The displayed Canvas rail's best focus target (sidebar hand-off, tab
  /// re-entry, auto-focus and dead-focus reclaim all route through this via
  /// [_topBoardFocusNode]).
  FocusNode? _stageFocusTarget() {
    // Spotlight owns its own cursor — the hero is a focusable row, which the
    // rail-based resolution below cannot describe.
    if (_homeStyleEffective == 'spotlight') {
      return _spotlightKey.currentState?.focusTarget();
    }
    // Tonight parks focus in its vertical queue until the user walks down
    // into the rail zone; the rail resolution below is only right for the
    // rail zone.
    if (_homeStyleEffective == 'tonight' && _tonightZoneIsQueue) {
      final queue = _tonightQueue;
      if (queue.isNotEmpty) {
        final e = queue[_resolveTonightQueueIndex(queue)];
        return _nearestMountedNode(e.rail.cw!.nodes, e.col);
      }
    }
    return _stageNavigation.railTarget(
      _stageRails,
      focusedAtriumKey: _homeStyleEffective == 'atrium'
          ? _atriumFocusedRailKey.value
          : null,
    );
  }

  /// Every non-empty Home rail in the board's built-in order. Search's
  /// dedicated Lists mode has its own body and never enters this collection.
  /// FocusNode lists are reused from the classic board's per-row lists — only
  /// one view is ever mounted, and reuse keeps node counts synced through
  /// paging for free.
  List<HomeRail> get _canonicalCanvasRails => HomeRailComposition.canonical(
    continuation: _continuationProjection.cwVisible
        ? _continuationProjection.cwRows
        : const [],
    favorites: _savedSection.favRowKinds,
    favoriteCount: _canvasFavItemCount,
    sectionCount: _sections.length,
    nodeRowCount: _rowNodes.length,
    sectionHasItems: (index) => _sections[index].items.isNotEmpty,
    rowId: _canvasRailRowId,
  );

  List<HomeRail> _orderedHomeRails(List<HomeRail> rails) => _homeRowOrderActive
      ? HomeRowOrder.apply(rails, _effectiveHomeRowOrder, _canvasRailRowId)
      : rails;

  List<HomeRail> get _canvasRails => _orderedHomeRails(_canonicalCanvasRails);

  List<HomeRail> get _classicHomeRails => _orderedHomeRails(
    HomeRailComposition.classic(
      canonical: _canonicalCanvasRails,
      reserveTrakt: _continuationProjection.traktReserving,
      mergeTrakt: _continuationSection.cwMergeTrakt,
      disabled: _homeDisabled,
    ),
  );

  String _canvasRailRowId(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.rowId;
    if (rail.favKind != null) return _savedSection.favRowId(rail.favKind!);
    if (rail.traktSkeletonIndex >= 0) {
      return rail.traktSkeletonIndex == 0 ? 'trakt:movies' : 'trakt:shows';
    }
    return _sectionRowId(_sections[rail.sectionIndex!]);
  }

  late final _classicNavigation = HomeClassicNavigation(
    rails: () => _canvasRails,
    rowIdOf: _canvasRailRowId,
    nodesFor: _canvasRailNodes,
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

  // ── TONIGHT zone state ───────────────────────────────────────────────────

  late final _tonightFocus = HomeTonightFocus(
    railKeyOf: _canvasRailKeyOf,
    nearestNode: _nearestMountedNode,
  );
  bool get _tonightZoneIsQueue => _tonightFocus.isQueue;
  set _tonightZoneIsQueue(bool value) => _tonightFocus.isQueue = value;
  ValueNotifier<HomeTonightCardInfo?> get _tonightCard => _tonightFocus.card;

  final HomeStageHoldLatch _stageHold = HomeStageHoldLatch();

  List<HomeTonightQueueEntry> get _tonightQueue =>
      _continuationProjection.cwVisible
      ? HomeRailComposition.tonightQueue(_canvasRails)
      : [];

  List<HomeRail> get _stageRails => HomeRailComposition.stage(
    _canvasRails,
    tonight: _homeStyleEffective == 'tonight',
  );

  int _canvasFavItemCount(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) {
      return _savedSection.iptvListRows[ref.list].channels.length;
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return _savedSection.watchlistMovieItems.length;
      case HomeFavoriteKind.watchlistSeries:
        return _savedSection.watchlistSeriesItems.length;
      case HomeFavoriteKind.iptv:
        return _savedSection.iptvFavChannels.length;
      case HomeFavoriteKind.debrify:
        return _savedSection.tvFavChannels.length;
      case HomeFavoriteKind.stremio:
        return _savedSection.stvFavChannels.length;
      case HomeFavoriteKind.playlist:
        return _savedSection.playlistItems.length;
    }
  }

  String _canvasFavTitle(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) return _savedSection.iptvListRows[ref.list].title;
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return 'Watchlist Movies';
      case HomeFavoriteKind.watchlistSeries:
        return 'Watchlist Series';
      case HomeFavoriteKind.iptv:
        return 'IPTV Favorites';
      case HomeFavoriteKind.debrify:
        return 'Debrify TV';
      case HomeFavoriteKind.stremio:
        return 'Stremio TV';
      case HomeFavoriteKind.playlist:
        return 'Playlist';
    }
  }

  String _canvasRailTitle(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.title;
    if (rail.favKind != null) return _canvasFavTitle(rail.favKind!);
    final section = _sections[rail.sectionIndex!];
    if (_hideHomeCollectionNames && section is HomeCollectionSection) {
      return '';
    }
    return section.title;
  }

  List<StremioMeta> _canvasRailItems(HomeRail rail) =>
      rail.cw?.items ?? _sections[rail.sectionIndex!].items;

  List<FocusNode> _canvasRailNodes(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.nodes;
    if (rail.favKind != null) return _savedSection.favNodesFor(rail.favKind!);
    return _rowNodes[rail.sectionIndex!];
  }

  /// UP/DOWN on the shelf: swap which rail the shelf shows — the screen never
  /// scrolls. DOWN past the last loaded rail pulls the next catalog batch;
  /// the new rail becomes reachable when it lands.
  void _stageSwitchRail(int delta) {
    _stageNavigation.switchRail(
      rails: _stageRails,
      delta: delta,
      rowsPending: () => _boardRowsPending,
      canAdvance: () => _boardCanAdvance,
      focusContinuation: _focusCatalogContinuation,
      deferAdvance: _stageDeferredAdvance.defer,
      loadMore: _loadMoreBoard,
      activate: (nextKey) {
        setState(() {
          _canvasRailKey = nextKey;
          // Re-anchor Atrium's visible window before resolving deferred focus.
          if (_homeStyleEffective == 'atrium') {
            _atriumFocusedRailKey.value = nextKey;
          }
        });
      },
      scheduleFocus: () => _stageFocusRequests.schedule(_stageFocusTarget),
    );
  }

  /// The CANVAS home: full-bleed stage (idle art → ambient trailer via the
  /// same underlay engine, whose hole simply gets the whole canvas) with ONE
  /// shelf of large posters at the bottom and quiet rail tabs above it. No
  /// vertical scrolling, nothing clips at a fold, no row headers.
  Widget _buildCanvasBoard() {
    final view = _resolveStageRail();
    if (view == null) {
      // First batch still streaming (or every loaded row is empty) — hold
      // the brand stage rather than an empty black canvas.
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    return buildHomeCanvasBoard(
      hostContext: context,
      view: view,
      media: () => _boardMedia,
      theater: () => _canvasTheater,
      trailerActive: () => _heroPreview.heroTrailerActive,
      trailerShowing: _heroPreview.heroTrailerShowing,
      cardAspect: () => _stageCardAspect(view.rail),
      captionBandHeight: () => _homeArtPosterCaptionBand,
      favoriteCount: () => _canvasFavItemCount(view.rail.favKind!),
      railTitle: (index) => _canvasTabTitle(view.rails, index),
      favoriteBuilder: (_, col) =>
          _canvasFavCell(view.rail.favKind!, view.key, col),
      itemBuilder: (_, col) => _canvasCell(view, col),
    );
  }

  late final _stageCards = HomeStageCards(
    sectionAt: (index) => _sections[index],
    collectionFor: _stageCollection,
    aspectOf: _stageCardAspect,
    artOf: _stageCardArt,
    isBound: _isBound,
    pikpakOnly: () => _pikpakOnly,
    openSection: _sectionOpenItem,
    playSection: _sectionQuickPlay,
    openContinuationMenu: _continuationMenu.openCwCardMenu,
    onFocused: (railKey, item, column) {
      _heroSection.setHero(item);
      _canvasCols[railKey] = column;
    },
    focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
    switchRail: _stageSwitchRail,
    loadMore: _loadMoreRow,
  );

  Widget _canvasCell(HomeStageRailView view, int col) {
    final rail = view.rail;
    final railKey = view.key;
    final items = view.items;
    final nodes = view.nodes;
    return _stageCards.build(
      rail: rail,
      railKey: railKey,
      item: items[col],
      nodes: nodes,
      column: col,
    );
  }

  /// A DOWN that ran off the end of the rail list asked for another batch.
  /// Called when one lands: completes the move only if the user is STILL on
  /// the rail they pressed DOWN from, and the request hasn't gone stale — a
  /// late batch must never yank focus out of wherever they went instead.
  void _maybeCompleteStageAdvance() {
    late final List<HomeRail> rails;
    late final int i;
    final move = _stageDeferredAdvance.take(
      waitingForMore: (key) {
        rails = _stageRails;
        i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
        return _boardRowsPending && i >= 0 && i + 1 >= rails.length;
      },
    );
    if (move == null) return;
    final key = move.railKey;
    final fillLower = move.fillsLower;
    final origin = move.origin;
    if (i < 0 || i + 1 >= rails.length) return;
    // Still where the key was pressed? On Atrium that means the focused ROW,
    // everywhere else the active rail.
    final whereNow = _homeStyleEffective == 'atrium'
        ? (_atriumFocusedRailKey.value ?? _canvasRailKey)
        : _canvasRailKey;
    if (whereNow != key) return;
    if (fillLower) {
      // Atrium had only a top row: the window stays put and focus drops into
      // the row that just landed beneath it.
      _stageFocusRequests.schedule(() {
        if (!identical(FocusManager.instance.primaryFocus, origin)) return null;
        final now = _stageRails;
        final at = now.indexWhere((r) => _canvasRailKeyOf(r) == key);
        if (at < 0 || at + 1 >= now.length) return null;
        final rail = now[at + 1];
        _atriumFocusedRailKey.value = _canvasRailKeyOf(rail);
        return _nearestMountedNode(
          _canvasRailNodes(rail),
          _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
        );
      });
      return;
    }
    if (_homeStyleEffective == 'atrium') {
      // Atrium pressed DOWN from the window's BOTTOM row; its own advance
      // re-resolves the window and lands focus on the new bottom row.
      _atriumAdvance(origin: origin);
      return;
    }
    setState(() => _canvasRailKey = _canvasRailKeyOf(rails[i + 1]));
    _stageFocusRequests.schedule(() {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return null;
      final primary = FocusManager.instance.primaryFocus;
      // Deck/Mosaic replace the entire rail. That intentional replacement
      // detaches the origin before this frame callback and leaves route-scope
      // focus. A different attached card still means the user moved elsewhere.
      final detachedBySwap = origin?.parent == null &&
          (primary == null || identical(primary, FocusScope.of(context)));
      return identical(primary, origin) || detachedBySwap
          ? _stageFocusTarget() : null;
    });
  }

  /// A rail strip reserves ONE box height for every rail kind (invariant: a
  /// per-kind height bounces the layout on every fav↔catalog switch). The two
  /// kinds FILL it differently rather than one wasting the other's space: a
  /// catalog poster is the full box, a favourite's poster is the box minus its
  /// caption band, so both end exactly on the box's bottom edge.
  /// TITLE cards follow the Home Cards orientation setting; everything else
  /// (favourites, channels, playlists) keeps its own fixed shape.
  double get _titleCardAspect =>
      homeTitleCardAspect(landscape: _homeLandscapeCards);

  /// The art for a title card under the current orientation. Null keeps the
  /// cell's own default (the 2:3 poster) — only landscape needs a derived
  /// wide still.
  String? _titleArtUrl(StremioMeta item) =>
      _homeLandscapeCards ? homeStageWideArtwork(item) : null;

  HomeCollectionSection? _stageCollection(HomeRail rail) {
    final index = rail.sectionIndex;
    if (index == null) return null;
    final section = _sections[index];
    return section is HomeCollectionSection ? section : null;
  }

  double _stageCardAspect(HomeRail rail, {double? fallback}) =>
      _stageCollection(rail)?.tileAspectRatio ?? fallback ?? _titleCardAspect;

  String? _stageCardArt(HomeRail rail, StremioMeta item, {bool wide = false}) =>
      _stageCollection(rail) != null
          ? item.poster
          : wide
          ? homeStageWideArtwork(item)
          : _titleArtUrl(item);

  double _stageFavW(BuildContext context, double boxH) {
    // Poster + caption must equal the box EXACTLY. A width floor here would
    // make the poster taller than the space left by a scaled caption and
    // overflow the row — so the art simply gets whatever is left (never
    // below a hairline, so the cell is still hit-testable).
    final art = boxH - _homeArtPosterCaptionBand;
    return (art < 16 ? 16.0 : art) * 2 / 3;
  }

  /// The box height a rail strip may actually use: the layout's preference,
  /// but never less than a favourite cell needs at the CURRENT text scale
  /// (its two-line caption grows with accessibility settings, and a fixed box
  /// would clip it), and never more than [maxH].
  double _stageRailBoxH(
    BuildContext context,
    double preferred, {
    required double maxH,
  }) {
    final floor = _homeArtPosterCaptionBand + _kStageMinPosterH;
    final lo = min(floor, maxH);
    return preferred.clamp(lo, max(lo, maxH));
  }

  /// One-shot: hand entry focus to the active rail the first time a stage
  /// board builds. Shared by every stage layout — the target resolution
  /// ([_stageFocusTarget]) already knows which zone owns focus.
  void _seedStageFocusOnce() => _stageNavigation.seedFocus(
    schedule: _stageFocusRequests.schedule,
    resolveTarget: _stageFocusTarget,
  );

  /// Every stage board resolves the same four things before painting: the
  /// rails, which one is active, its identity key (persisted so a rail
  /// streaming in above it can't swap the content under the user) and its
  /// nodes. Null means "nothing to show yet" — the caller holds the brand
  /// stage.
  HomeStageRailView? _resolveStageRail() =>
      _stageNavigation.resolveView(_stageRails);

  // ── PROMENADE view ───────────────────────────────────────────────────────

  /// PROMENADE: Canvas's stage, symmetric. The identity sits centred in the
  /// lower third and the rail becomes a CENTRE-LOCKED strip — the focused
  /// cell is pinned to the middle of the board and the strip travels under
  /// it. Centre-lock is free: board cards already
  /// `ensureVisible(alignment: 0.5)`; the half-viewport pads below simply let
  /// the FIRST and LAST cell reach the middle too, which a plain list can't.
  Widget _buildPromenadeBoard() {
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    return buildHomePromenadeBoard(
      hostContext: context,
      view: view,
      media: () => _boardMedia,
      theater: () => _canvasTheater,
      trailerActive: () => _heroPreview.heroTrailerActive,
      trailerShowing: _heroPreview.heroTrailerShowing,
      railBoxHeight: _stageRailBoxH,
      favoriteWidth: _stageFavW,
      cardAspect: () => _stageCardAspect(view.rail, fallback: 16 / 9),
      favoriteCount: () => _canvasFavItemCount(view.rail.favKind!),
      railTitle: () => _canvasTabTitle(view.rails, view.index),
      favoriteBuilder: (_, col) =>
          _canvasFavCell(view.rail.favKind!, view.key, col),
      itemBuilder: (_, col) =>
          _promenadeCell(view.rail, view.key, view.items, view.nodes, col),
    );
  }

  /// One wide strip cell — the SAME [HomeBoardCell] every board uses, in a 16:9
  /// box with derived landscape art, so hold-OK menus, quick-play, paging and
  /// the focus grammar are identical to Canvas's shelf.
  Widget _promenadeCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
  ) {
    return _stageCards.build(
      rail: rail,
      railKey: railKey,
      item: items[col],
      nodes: nodes,
      column: col,
      wide: true,
      restVeil: _kPromRestVeil,
    );
  }

  // ── ATRIUM view ──────────────────────────────────────────────────────────

  /// Which rail currently owns focus in Atrium's two-row wall — drives the
  /// eyebrow above the identity only, so it is a notifier rather than
  /// setState: crossing between the rows must not rebuild the board.
  final ValueNotifier<String?> _atriumFocusedRailKey = ValueNotifier<String?>(
    null,
  );

  /// Focus the nearest mounted cell of the rail at [index] (its own remembered
  /// column). Both wall rows are mounted, so this always has a target.
  void _atriumFocusRail(int index) {
    final rails = _stageRails;
    if (index < 0 || index >= rails.length) return;
    final rail = rails[index];
    _nearestMountedNode(
      _canvasRailNodes(rail),
      _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
    )?.requestFocus();
  }

  /// DOWN from the BOTTOM row: scroll the two-row window on by one, so the
  /// row you were on becomes the top row and focus lands on the rail below
  /// it. (Plain [_stageSwitchRail] would focus the rail you are already on.)
  void _atriumAdvance({FocusNode? origin}) {
    final rails = _stageRails;
    final cur = _resolveCanvasRailIndex(rails);
    if (cur + 2 >= rails.length) {
      // Nothing below the bottom row yet — pull the next catalog batch and
      // remember the move so it completes when the rail lands.
      if (_boardCanAdvance) {
        _stageDeferredAdvance.defer(
          _canvasRailKeyOf(rails[min(cur + 1, rails.length - 1)]),
        );
        _loadMoreBoard();
      }
      return;
    }
    setState(() => _canvasRailKey = _canvasRailKeyOf(rails[cur + 1]));
    _stageFocusRequests.schedule(() {
      if (_homeStyleEffective != 'atrium') return null;
      // Deferred completions pass the node that pressed DOWN; focus can move
      // during the frame gap, and a late batch must not yank it back.
      if (origin != null &&
          !identical(FocusManager.instance.primaryFocus, origin)) {
        return null;
      }
      // After the shift the window is [cur+1, cur+2]; land on its bottom row.
      final rails = _stageRails;
      final i = _resolveCanvasRailIndex(rails) + 1;
      if (i >= rails.length) return null;
      final rail = rails[i];
      _atriumFocusedRailKey.value = _canvasRailKeyOf(rail);
      return _nearestMountedNode(
        _canvasRailNodes(rail),
        _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
      );
    });
  }

  /// ATRIUM: a hard vertical cut. Left is a flat ink column carrying the
  /// title's dossier and never taking focus; right is the art (and the
  /// trailer, in the same rect — the hole simply follows the layer's box)
  /// with a two-row poster wall standing on its lower half.
  Widget _buildAtriumBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    return buildHomeAtriumBoard(
      view: view,
      media: () => _boardMedia,
      trailerActive: () => _heroPreview.heroTrailerActive,
      focusedRailKey: _atriumFocusedRailKey,
      trailerShowing: _heroPreview.heroTrailerShowing,
      panelColor: app.home.bg,
      seamColor: app.fade(app.core.tx, 0.09),
      labelHeight: _atriumLabelHeight,
      labelGap: _kAtriumLabelGap,
      minimumRowHeight: () => _homeArtPosterCaptionBand + _kStageMinPosterH,
      railBoxHeight: _stageRailBoxH,
      railKeyOf: _canvasRailKeyOf,
      railTitle: (index) => _canvasTabTitle(view.rails, index),
      rowBuilder: (index, height, {required isTopRow, required hasRowBelow}) =>
          _atriumRow(
            view.rails,
            index,
            height,
            isTopRow: isTopRow,
            hasRowBelow: hasRowBelow,
          ),
    );
  }

  /// One row of Atrium's wall: a quiet rail label over a horizontal strip of
  /// the SAME cells every other board uses.
  Widget _atriumRow(
    List<HomeRail> rails,
    int index,
    double rowBoxH, {
    required bool isTopRow,
    required bool hasRowBelow,
  }) {
    final rail = rails[index];
    final railKey = _canvasRailKeyOf(rail);
    final favRail = rail.favKind != null;
    final items = favRail ? const <StremioMeta>[] : _canvasRailItems(rail);
    final nodes = _canvasRailNodes(rail);
    final cardW = favRail
        ? _stageFavW(context, rowBoxH)
        : rowBoxH * _stageCardAspect(rail);
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;

    // The window is [active, active+1]. From the top row UP leaves the
    // window; from the bottom row DOWN scrolls it on. Crossing between them
    // is a plain focus request.
    final onUp = isTopRow
        ? () => _stageSwitchRail(-1)
        : () => _atriumFocusRail(index - 1);
    final onDown = isTopRow
        ? (hasRowBelow
              ? () => _atriumFocusRail(index + 1)
              : (rails.length > index + 1
                    // Only one row is drawn: DOWN scrolls the window on.
                    ? () => _stageSwitchRail(1)
                    : () {
                        // No lower row YET — remember the move so focus drops into
                        // it when the batch lands, instead of eating the keypress.
                        if (_boardCanAdvance) {
                          _stageDeferredAdvance.defer(
                            railKey,
                            fillsLower: true,
                          );
                          _loadMoreBoard();
                        }
                      }))
        : _atriumAdvance;

    return buildHomeAtriumRow(
      context: context,
      title: _canvasTabTitle(rails, index),
      androidTv: PlatformUtil.isAndroidTvCached,
      labelGap: _kAtriumLabelGap,
      rowHeight: rowBoxH,
      railKey: railKey,
      itemCount: count,
      itemBuilder: (context, col) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Center(
          child: SizedBox(
            width: cardW,
            child: favRail
                ? _canvasFavCell(
                    rail.favKind!,
                    railKey,
                    col,
                    onUp: () {
                      _atriumFocusedRailKey.value = railKey;
                      onUp();
                    },
                    onDown: () {
                      _atriumFocusedRailKey.value = railKey;
                      onDown();
                    },
                  )
                : SizedBox(
                    height: rowBoxH,
                    child: _stageCards.build(
                      rail: rail,
                      railKey: railKey,
                      item: items[col],
                      readActionItem: () => items[col],
                      nodes: nodes,
                      column: col,
                      onUp: onUp,
                      onDown: onDown,
                      onFocusedExtra: () =>
                          _atriumFocusedRailKey.value = railKey,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── MOSAIC view ──────────────────────────────────────────────────────────

  /// MOSAIC: no hero at all. The active rail becomes a WALL of posters on a
  /// heavily veiled wash of the focused title's art, with the identity moved
  /// to a fixed top band. The cheapest layout on the list: one image, one
  /// flat veil, one grid — and no ambient video (see [_stageWantsAmbient]),
  /// which is why it stays smooth on weak TV hardware.
  Widget _buildMosaicBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    final count = view.rail.favKind != null
        ? _canvasFavItemCount(view.rail.favKind!)
        : view.items.length;
    return buildHomeMosaicBoard(
      hostContext: context,
      view: view,
      itemCount: count,
      media: () => _boardMedia,
      trailerActive: () => _heroPreview.heroTrailerActive,
      trailerShowing: _heroPreview.heroTrailerShowing,
      cardAspect: () => _stageCardAspect(view.rail),
      captionBandHeight: () => _homeArtPosterCaptionBand,
      hintColor: app.fade(app.core.tx, 0.34),
      railTitle: () => _canvasTabTitle(view.rails, view.index),
      itemBuilder: (col, perRow, cellWidth) => _mosaicCell(
        view.rail,
        view.key,
        view.items,
        view.nodes,
        col,
        count,
        perRow,
        cellWidth,
      ),
    );
  }

  /// One wall cell. The grid overrides all four arrows: LEFT hands off to the
  /// sidebar only at a ROW edge (a grid's leftmost cell is not column 0, so
  /// the row grammar would leave the sidebar unreachable from every row but
  /// the first), and UP/DOWN step a whole row before falling through to rail
  /// switching.
  Widget _mosaicCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
    int count,
    int perRow,
    double cellW,
  ) {
    final navigation = HomeMosaicCellNavigation(
      column: col,
      count: count,
      perRow: perRow,
      nodes: nodes,
      hold: _stageHold,
      focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
      switchRail: _stageSwitchRail,
      loadMore: rail.sectionIndex == null
          ? null
          : () => _loadMoreRow(rail.sectionIndex!),
      deferRight: () => _stageDeferredRight.defer(railKey, col),
    );

    if (rail.favKind != null) {
      return _canvasFavCell(
        rail.favKind!,
        railKey,
        col,
        onUp: navigation.up,
        onDown: navigation.down,
        onLeft: navigation.left,
        onRight: navigation.right,
        onUpHold: navigation.upHold,
        onDownHold: navigation.downHold,
      );
    }
    return SizedBox(
      height: cellW / _stageCardAspect(rail),
      child: _stageCards.build(
        rail: rail,
        railKey: railKey,
        item: items[col],
        nodes: nodes,
        column: col,
        pageNearEnd: false,
        onUp: navigation.up,
        onDown: navigation.down,
        onUpHold: navigation.upHold,
        onDownHold: navigation.downHold,
        onLeft: navigation.left,
        onRight: navigation.right,
      ),
    );
  }

  // ── DECK view ────────────────────────────────────────────────────────────

  /// DECK: the trailer stops being wallpaper and becomes an OBJECT — a
  /// rounded 16:9 card floating on ink with the next two titles stacked
  /// behind it. The hole follows the card's laid-out rect (Canvas proved that
  /// needs no native work); the rounded corners are four ink wedges painted
  /// ABOVE the layers, because a clip would put a saveLayer over the hole.
  Widget _buildDeckBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    return buildHomeDeckBoard(
      hostContext: context,
      view: view,
      itemCount: view.rail.favKind != null
          ? _canvasFavItemCount(view.rail.favKind!)
          : view.items.length,
      media: () => _boardMedia,
      theater: () => _canvasTheater,
      trailerActive: () => _heroPreview.heroTrailerActive,
      focusedColumn: _stageCol,
      trailerShowing: _heroPreview.heroTrailerShowing,
      borderColor: app.fade(app.core.tx, 0.10),
      railBoxHeight: _stageRailBoxH,
      labelHeight: _atriumLabelHeight,
      labelGap: _kAtriumLabelGap,
      favoriteWidth: _stageFavW,
      cardAspect: () => _stageCardAspect(view.rail),
      railTitle: () => _canvasTabTitle(view.rails, view.index),
      favoriteBuilder: (_, col) =>
          _canvasFavCell(view.rail.favKind!, view.key, col),
      itemBuilder: (_, col) =>
          _stageShelfCell(view.rail, view.key, view.items, view.nodes, col),
    );
  }

  /// The shared poster shelf cell (Canvas grammar: L/R along the rail, U/D
  /// switches rails) — used by Deck and Tonight's bottom strip.
  Widget _stageShelfCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
    VoidCallback? onFocusedExtra,
  }) {
    return _stageCards.build(
      rail: rail,
      railKey: railKey,
      item: items[col],
      nodes: nodes,
      column: col,
      onUp: onUp,
      onDown: onDown,
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onFocusedExtra: () {
        _stageCol.value = col;
        onFocusedExtra?.call();
      },
    );
  }

  // ── TONIGHT view ─────────────────────────────────────────────────────────

  int _resolveTonightQueueIndex(List<HomeTonightQueueEntry> queue) =>
      _tonightFocus.resolveIndex(queue);

  bool _tonightFocusQueue() => _tonightFocus.focusQueue(_tonightQueue);

  bool _tonightFocusRail() {
    final node = () {
      final rails = _stageRails;
      if (rails.isEmpty) return null;
      final rail = rails[_resolveCanvasRailIndex(rails)];
      return _nearestMountedNode(
        _canvasRailNodes(rail),
        _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
      );
    }();
    return _tonightFocus.focusRail(node);
  }

  /// TONIGHT: resume-first. A large card carries whatever has focus, a
  /// vertical Continue queue stands beside it, and one rail runs underneath.
  /// UP/DOWN walks the two zones as a single column, so the Continue rows sit
  /// "above" the first rail exactly as they read.
  Widget _buildTonightBoard() {
    final queue = _tonightQueue;
    final rails = _stageRails;
    if (queue.isEmpty && rails.isEmpty) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    // A zone that no longer exists can't hold focus.
    if (_tonightZoneIsQueue && queue.isEmpty) _tonightZoneIsQueue = false;
    if (!_tonightZoneIsQueue && rails.isEmpty) _tonightZoneIsQueue = true;
    final view = rails.isEmpty ? null : _resolveStageRail();
    _seedStageFocusOnce();

    return buildHomeTonightBoard(
      hostContext: context,
      queueCount: queue.length,
      hasRail: rails.isNotEmpty,
      media: () => _boardMedia,
      trailerActive: () => _heroPreview.heroTrailerActive,
      cardInfo: _tonightCard,
      labelHeight: _atriumLabelHeight,
      labelGap: _kAtriumLabelGap,
      railBoxHeight: _stageRailBoxH,
      onQueueHidden: () => _tonightZoneIsQueue = false,
      queueBuilder: (height, width) =>
          _tonightQueueList(queue, height, width, rails.isNotEmpty),
      railBuilder: view == null
          ? null
          : (height, queueAbove) =>
                _tonightRail(view, height, queueAbove: queueAbove),
    );
  }

  Widget _tonightQueueList(
    List<HomeTonightQueueEntry> queue,
    double rowH,
    double queueW,
    bool hasRail,
  ) {
    return buildHomeTonightQueueList(
      itemCount: queue.length,
      rowHeight: rowH,
      queueWidth: queueW,
      itemBuilder: (context, i, thumbW) {
        final e = queue[i];
        final cw = e.rail.cw!;
        final item = cw.items[e.col];
        return HomeTonightQueueRow(
          item: item,
          height: rowH,
          thumbWidth: thumbW,
          focusNode: cw.nodes[e.col],
          episode: cw.episodeOf(item),
          progress: cw.progressOf(item),
          hasBoundSource: _isBound(item),
          onFocused: () {
            _tonightFocus.selectQueue(e, i, item);
            _heroSection.setHero(item);
          },
          onOpen: () => cw.onOpen(item),
          onLongPress: () =>
              _continuationMenu.openCwCardMenu(cw, item, e.rail.cwIndex, e.col),
          onUp: () {
            if (_stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
            if (i > 0) {
              _nearestMountedNode(
                queue[i - 1].rail.cw!.nodes,
                queue[i - 1].col,
              )?.requestFocus();
            }
          },
          onDown: () {
            if (_stageHold.swallows(LogicalKeyboardKey.arrowDown)) return;
            if (i + 1 < queue.length) {
              _nearestMountedNode(
                queue[i + 1].rail.cw!.nodes,
                queue[i + 1].col,
              )?.requestFocus();
            } else if (hasRail) {
              _tonightFocusRail();
            }
          },
          // HELD down: leave the queue for the rail in one gesture.
          // The queue is every Continue Watching item from every
          // source flattened into one column, so stepping past it a
          // row at a time can be a long walk.
          onDownHold: hasRail
              ? () => _stageHold.jump(
                  LogicalKeyboardKey.arrowDown,
                  _tonightFocusRail,
                )
              : null,
          onLeft: () => MainPageBridge.focusTvSidebar?.call(),
        );
      },
    );
  }

  Widget _tonightRail(
    HomeStageRailView view,
    double boxH, {
    required bool queueAbove,
  }) {
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;
    // UP walks back through the rails and then into the queue — the two zones
    // are one vertical column.
    void up() {
      if (_stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
      if (view.index > 0) {
        _stageSwitchRail(-1);
      } else if (queueAbove) {
        _tonightFocusQueue();
      }
    }

    void down() {
      if (_stageHold.swallows(LogicalKeyboardKey.arrowDown)) return;
      _stageSwitchRail(1);
    }

    // HELD up: back to the Continue queue from any rail, the mirror of the
    // queue's held DOWN.
    final upHold = queueAbove
        ? () => _stageHold.jump(LogicalKeyboardKey.arrowUp, _tonightFocusQueue)
        : null;

    return buildHomeTonightRail(
      railHeight: boxH,
      labelGap: _kAtriumLabelGap,
      railKey: railKey,
      itemCount: count,
      label: buildHomeStageRowLabel(
        context: context,
        title: _canvasTabTitle(view.rails, view.index),
      ),
      itemBuilder: (context, col) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Center(
          child: SizedBox(
            width: favRail
                ? _stageFavW(context, boxH)
                : boxH * _stageCardAspect(rail),
            child: favRail
                ? _canvasFavCell(
                    rail.favKind!,
                    railKey,
                    col,
                    onUp: up,
                    onDown: down,
                    onUpHold: upHold,
                  )
                : SizedBox(
                    height: boxH,
                    child: _stageShelfCell(
                      rail,
                      railKey,
                      items,
                      nodes,
                      col,
                      onUp: up,
                      onDown: down,
                      onUpHold: upHold,
                      onFocusedExtra: () {
                        _tonightFocus.selectRail(rail, items[col]);
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// Tab label for a rail, with colliding titles disambiguated by the
  /// section's provenance tag. Titles carry their content type themselves
  /// now ("Popular Movies" — [CatalogSection.rowTitle]), so the only way two
  /// tabs still collide is the same catalog name+type from two ADDONS — and
  /// the addon is exactly what tells those apart.
  String _canvasTabTitle(List<HomeRail> rails, int i) {
    final title = _canvasRailTitle(rails[i]);
    if (title.isEmpty) return '';
    final rail = rails[i];
    if (rail.sectionIndex == null) return title;
    final duplicated = rails.any(
      (r) => !identical(r, rail) && _canvasRailTitle(r) == title,
    );
    if (!duplicated) return title;
    return '$title · ${_sectionTag(_sections[rail.sectionIndex!])}';
  }

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
        fromSpotlight: _homeStyleEffective == 'spotlight',
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
        _stageDeferredAdvance.reset();
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
    spotlightActive: () => _spotlightShellActive,
    discover: _discoverSection.buildDiscover,
    board: _buildBoard,
    spotlight: _buildSpotlightShell,
    header: _inputSection.buildHeader,
    sourcesBar: _inputSection.buildUnifiedCatalogSourcesBar,
    body: _inputSection.buildBody,
  );

  Widget _buildSpotlightShell() {
    // Preserve the build-time latch for async default-mode/query restoration.
    _searchSheet.observeForcedState();
    return buildSpotlightSearchShell(
      context: context,
      sheetOpen: _searchSheetOpen,
      canClose: !_sheetForced && _searchController.text.isEmpty,
      onClose: _searchSheet.close,
      onOpen: _searchSheet.open,
      header: _inputSection.buildHeader,
      sourcesBar: _inputSection.buildUnifiedCatalogSourcesBar,
      body: _inputSection.buildBody,
    );
  }

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
    landscape: _homeLandscapeCards,
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
      _stageFocusTarget(),
      for (final rail in _canvasRails) ..._canvasRailNodes(rail),
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
        !_spotlightEntryRevealed &&
        widget.isTelevision &&
        !widget.searchMode &&
        !widget.discoverMode &&
        _catalogSection.catalogQuery.isEmpty &&
        !_catalogSection.catalogSearching &&
        _homeStyleEffective == 'spotlight') {
      if (_spotlightHero.isEmpty &&
          (_boardRefreshing || _heroSourceResolving)) {
        return BrandLoadingStage(isTelevision: true);
      }
      // Reveal once: background refreshes must not hide an already usable
      // board. Hero success enters on the hero; exhaustion enters on a card.
      _spotlightEntryRevealed = true;
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
      style: _homeStyleEffective,
      spotlightHasContent: () =>
          _spotlightShelves.any((s) => s.items.isNotEmpty),
      layouts: {
        'canvas': _buildCanvasBoard,
        'atrium': _buildAtriumBoard,
        'mosaic': _buildMosaicBoard,
        'promenade': _buildPromenadeBoard,
        'deck': _buildDeckBoard,
        'tonight': _buildTonightBoard,
        'spotlight': _buildSpotlightBoard,
      },
      searchSpotlight: _buildSearchSpotlightBoard,
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
            ? (_homeBoardMode
                  ? _tvHeroArtworkCacheWidth
                  : HomeTheme.heroBackdropCacheWidthTv)
            : HomeTheme.heroBackdropCacheWidth,
        artworkCacheHeight: tv
            ? (_homeBoardMode
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
    final homeRails = orderedHome ? _classicHomeRails : const <HomeRail>[];
    return HomeClassicRows.fromRails(
      scrollController: _boardScroll,
      generation: _boardGen,
      catalogRowCount: _sections.length,
      rails: orderedHome ? homeRails : null,
      rowIdOf: _canvasRailRowId,
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
      _hideHomeCatalogAddonNames ? null : _sectionTag(section);

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
    hideHeader: _hideHomeCollectionNames && section is HomeCollectionSection,
    hideSourceTags: _hideHomeCatalogAddonNames,
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
    final cellAspect = collection?.tileAspectRatio ?? _titleCardAspect;
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
      header: collection == null || !_hideHomeCollectionNames
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
      artOf: _titleArtUrl,
      showTitle: () => !_hideHomeCardTitlesAndRatings,
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
