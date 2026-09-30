import '../features/home/presentation/home_board_rendering.dart';
import '../features/home/presentation/home_classic_section.dart';
import '../features/home/presentation/home_board_rows.dart';
import '../features/home/presentation/home_board_configuration_section.dart';
import '../features/home/presentation/home_board_focus.dart';
import '../features/home/presentation/home_board_deferred.dart';
import '../features/home/presentation/home_board_paging.dart';
import '../features/home/presentation/home_board_loading.dart';
import '../features/home/presentation/home_board_publication.dart';
import '../features/home/presentation/home_board_section.dart';
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
import '../features/home/presentation/home_favorite_bindings.dart';
import '../features/search/presentation/search_result_bindings.dart';
import '../features/search/presentation/lists_navigation.dart';
import '../features/discover/presentation/discover_bindings.dart';
import '../features/home/presentation/home_classic_favorite_rows.dart';
import '../features/home/presentation/home_board_media.dart';
import '../features/home/application/home_detail_action_dependencies.dart';
import '../features/home/presentation/home_detail_menus.dart';
import '../features/home/application/home_simkl_continuation_dependencies.dart';
import '../features/home/presentation/home_detail_action_bridge.dart';
import '../features/discover/presentation/discover_panels.dart';
import '../features/home/presentation/home_hero_shell.dart';
export '../features/home/presentation/spotlight_iptv_card_preview.dart'
    show SpotlightIptvCardPreview;
import '../features/search/presentation/search_page_shell.dart';
import '../features/home/presentation/home_stage_rows.dart';
import '../features/discover/models/discover_source_state.dart';
import '../features/discover/application/metadata_feature_controller.dart';
import '../features/discover/models/metadata_feature_policy.dart';
import '../features/home/models/home_tracker_authentication.dart';
import '../features/home/application/home_tracker_authentication_controller.dart';
import '../features/home/models/home_return_snapshot.dart';
import '../features/home/application/home_return_dependencies.dart';
import '../features/home/application/home_pikpak_only_controller.dart';
import '../features/home/application/home_bound_counts_controller.dart';
import '../features/home/application/home_layout_preference_dependencies.dart';
import '../features/home/application/home_default_view_dependencies.dart';
import '../features/home/application/home_display_preferences_controller.dart';
import '../features/home/models/home_display_preferences.dart';
import '../features/home/presentation/home_continuation_bindings.dart';
import '../features/home/models/home_continuation_session.dart';
import '../features/home/application/home_row_snapshot.dart';
import '../features/home/models/home_board_configuration.dart';
import '../features/home/application/home_collections_dependencies.dart';
import '../features/home/models/home_catalog_preferences.dart';
import '../features/home/models/home_catalog_session.dart';
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
import '../services/home_load_progress.dart';
import '../services/home_row_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_scope.dart';
import '../utils/platform_util.dart';
import '../models/home_collection.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../services/analytics_service.dart';
import '../services/home_collection_rows.dart';
import '../services/home_collections_store.dart';
import '../services/home_list_rows.dart';
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

  // Board state. [_boardSection.homeSections] is the homepage cache; [_boardSection.sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  // Catalogs that errored (timeout / HTTP / network) during the current
  // catalog search — distinct from "returned no results". Drives the quiet
  // "N sources didn't respond" note so failing addons don't just vanish.
  int get _catalogSearchFailures => _catalogSection.catalogState.failures;

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [_boardConfiguration.reloadForHomeSettings] when the manager saves.
  // Bootstrap is captured at state construction, matching the previous field
  // initialization. All accepted changes live in the controller afterwards.
  final _initialHomeConfiguration = HomeBoardConfiguration(
    preferences: const HomeCatalogPreferences.empty(),
    collections: const [],
    collectionsSignature: HomeCollectionsStore.signatureOf(const []),
    hideWatched: HideWatchedPrefs.enabled,
  );
  // Riverpod owns inventory, reservation and the last accepted snapshot for
  // this view. Search detours retain the subscription and its cursor.
  late final HomeCatalogSession _homeCatalogSession;
  late final HomeBoardBindings _homeBoardBindings;

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

  late final HomeBoardConfigurationSection _boardConfiguration;
  late final HomeBoardRendering _boardRendering;
  late final HomeClassicSection _classicSection;
  late final HomeBoardRows _boardRows;
  late final HomeBoardFocus _boardFocus;
  late final HomeBoardDeferred _boardDeferred;
  late final HomeBoardPaging _boardPaging;
  late final HomeBoardLoading _boardLoading;
  late final HomeBoardPublication _boardPublication;
  late final HomeBoardSection _boardSection;
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
        findAddon: (id) => _boardSection.addonsById[id],
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
    ), () => _boardSection.addonsById);
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
        message: (icon, title, body, {VoidCallback? onRetry}) =>
            _boardRendering.message(icon, title, body, onRetry: onRetry),
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
      applySections:
          (sections, {bool preserveFocus = false, bool incremental = false}) =>
              _boardRows.applySections(
                sections,
                preserveFocus: preserveFocus,
                incremental: incremental,
              ),
      firstResult: () =>
          _boardSection.rowNodes.isNotEmpty &&
              _boardSection.rowNodes.first.isNotEmpty
          ? _boardSection.rowNodes.first.first
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
        restoreHome: () => _boardRows.restoreHome(),
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
                  _boardSection.rowNodes.isNotEmpty &&
                  _boardSection.rowNodes.first.isNotEmpty
              ? _boardSection.rowNodes.first.first
              : null,
          focusCatalogShelf: _spotlightSection.spotlightKey.currentState == null
              ? null
              : () =>
                    _spotlightSection.spotlightKey.currentState!.focusShelf(0),
          topBoardNode: () => _boardFocus.topBoardFocusNode(),
          loading: _boardSection.loading,
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
          catalogEmpty: _boardSection.sections.isEmpty,
          dedicatedSearch: widget.searchMode,
          queryEmpty: _catalogSection.catalogQuery.isEmpty,
          keyword: () => _keywordRows.buildKeyword(context),
          lists: () => _listsRows.build(context),
          prompt: () => _catalogSection.buildSearchPrompt(context),
          board: () => _boardRendering.buildBoard(),
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
      posterWidth: (context) => _classicSection.railPosterW(context),
      header: (onSeeAll) => _classicSection.railHeader(
        title: 'MDBList Lists',
        tag: 'LISTS',
        onSeeAll: onSeeAll,
      ),
      message: (icon, title, body) =>
          _boardRendering.message(icon, title, body),
      open: _listsSection.openListsResult,
      openSeeAll: _listsSection.openListsSeeAll,
      focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
      onUp: () => _boardFocus.leaveBoardTop(),
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
      disabled: () => _boardSection.homeDisabled,
      autoFocus: () => _boardFocus.maybeAutoFocusBoard(),
      focusContent: _inputSection.focusContent,
      requestRowFocus: (nodes, desired) =>
          _boardFocus.requestRowFocus(nodes, desired),
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
          posterWidth: _classicSection.railPosterW(context),
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
        loading: () => _boardSection.loading,
        activeTab: () => MainPageBridge.activeTvTabIndex == _tabIndex,
        context: () => context,
        disabled: () => _boardSection.homeDisabled,
        rowNodes: () => _boardSection.rowNodes,
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
        requestRowFocus: (nodes, desired) =>
            _boardFocus.requestRowFocus(nodes, desired),
        autoFocus: () => _boardFocus.maybeAutoFocusBoard(),
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
        disabled: () => _boardSection.homeDisabled,
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
        requestRowFocus: (nodes, desired) =>
            _boardFocus.requestRowFocus(nodes, desired),
        leaveBoardTop: () => _boardFocus.leaveBoardTop(),
      ),
      _continuationProjection,
      _playbackNavigation,
    );
    _continuationRows = HomeContinuationRows(
      (
        header: ({required title, tag, onSeeAll}) => _classicSection.railHeader(
          title: title,
          tag: tag,
          onSeeAll: onSeeAll,
        ),
        isTelevision: () => widget.isTelevision,
        posterWidth: () => _classicSection.railTitleCardW(context),
        cellHeight: () => _classicSection.railTitleCardH(context),
        aspectRatio: () => _stageGeometry.titleCardAspect,
        showTitleOverlay: () => !_displaySection.hideHomeCardTitlesAndRatings,
        artOf: (item) => _stageGeometry.titleArtUrl(item),
        isBound: _isBound,
        sidebar: () => MainPageBridge.focusTvSidebar?.call(),
        onFocused: (item) => _heroSection.setHero(item),
        focusRelativeRail: (rowId, delta, column) =>
            _boardFocus.focusRelativeHomeRail(rowId, delta, column),
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
      heroSource: () => _boardSection.heroSource,
      sections: () => _boardSection.sections,
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
        loading: () => _boardSection.loading,
        hasHero: () => _spotlightSection.spotlightHero.isNotEmpty,
      ),
      _searchController,
      _inputSection,
      _modeSection,
      _catalogSection,
    );
    _stageRailsSection = HomeStageRails(
      (
        sections: () => _boardSection.sections,
        rowNodes: () => _boardSection.rowNodes,
        orderActive: () => _boardSection.homeRowOrderActive,
        order: () => _boardSection.effectiveHomeRowOrder,
        disabled: () => _boardSection.homeDisabled,
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
        rowsPending: () => _boardSection.boardRowsPending,
        canAdvance: () => _boardSection.boardCanAdvance,
        focusContinuation: () => _boardFocus.focusCatalogContinuation(),
        loadMore: () => _boardPaging.loadMoreBoard(),
      ),
      _stageRailsSection,
      _displaySection,
      _heroPreview,
      _spotlightSection,
      HomeBoardDeferred.pendingDownMaxAge,
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
    _stageGeometry = HomeStageGeometry(
      _displaySection,
      () => _boardSection.sections,
    );
    _stageCells = HomeStageCells(
      (
        sectionAt: (index) => _boardSection.sections[index],
        isBound: _isBound,
        pikpakOnly: () => _pikpakOnly,
        openSection: _sectionOpenItem,
        playSection: _sectionQuickPlay,
        sidebar: () => MainPageBridge.focusTvSidebar?.call(),
        loadMore: (row, {bool resume = false}) =>
            _boardPaging.loadMoreRow(row, resume: resume),
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
        canAdvance: () => _boardSection.boardCanAdvance,
        loadMore: () => _boardPaging.loadMoreBoard(),
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
        sections: () => _boardSection.sections,
        rowNodes: () => _boardSection.rowNodes,
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
        sections: () => _boardSection.sections,
        rowNodes: () => _boardSection.rowNodes,
        failures: () => _catalogSearchFailures,
        leaveTop: () => _boardFocus.leaveBoardTop(),
        openSection: _sectionOpenItem,
        pikpakOnly: () => _pikpakOnly,
        catalogTag: _catalogSourceTag,
        seeAll: _openCatalogSeeAll,
        loadMoreRow: (row, {bool resume = false}) =>
            _boardPaging.loadMoreRow(row, resume: resume),
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
        loadMoreRow: (row, {bool resume = false}) =>
            _boardPaging.loadMoreRow(row, resume: resume),
        loadMore: () => _boardPaging.loadMoreBoard(),
        rowsPending: () => _boardSection.boardRowsPending,
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
    _boardSection = HomeBoardSection((
      bindings: () => _homeBoardBindings,
      mounted: () => mounted,
      context: () => context,
      searchMode: () => widget.searchMode,
      discoverMode: () => widget.discoverMode,
      isTracker: HomeExtraRowIds.isTracker,
    ), _catalogSection);
    _boardPublication = HomeBoardPublication(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        scope: () => ProfileRuntime.scope.value,
        boardHasFocus: () => _boardFocus.boardHasFocus(),
        settleAutoFocus: () => _boardFocus.autoFocusSettled = true,
        applySections:
            (
              sections, {
              bool preserveFocus = false,
              bool incremental = false,
            }) => _boardRows.applySections(
              sections,
              preserveFocus: preserveFocus,
              incremental: incremental,
            ),
        autoFocus: () => _boardFocus.maybeAutoFocusBoard(),
        completeDeferredDown: () => _boardDeferred.maybeCompleteDeferredDown(),
        autoFill: ({bool resumeDeferred = false}) =>
            _boardPaging.maybeAutoFillBoard(resumeDeferred: resumeDeferred),
      ),
      _boardSection,
      _catalogSection,
      _stageSection,
      MainPageBridge.homeBoardReady,
    );
    _boardLoading = HomeBoardLoading(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        scope: () => ProfileRuntime.scope.value,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        rowId: _sectionRowId,
        refreshPikpakOnly: _refreshPikpakOnly,
        applySections:
            (
              sections, {
              bool preserveFocus = false,
              bool incremental = false,
            }) => _boardRows.applySections(
              sections,
              preserveFocus: preserveFocus,
              incremental: incremental,
            ),
        autoFocus: () => _boardFocus.maybeAutoFocusBoard(),
        autoFill: ({bool resumeDeferred = false}) =>
            _boardPaging.maybeAutoFillBoard(resumeDeferred: resumeDeferred),
      ),
      _boardSection,
      _catalogSection,
      _boardPublication,
      _displaySection,
      _spotlightSection,
      MainPageBridge.homeBoardReady,
    );
    _boardPaging = HomeBoardPaging(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        scope: () => ProfileRuntime.scope.value,
        rowId: _sectionRowId,
        completeDeferredDown: () => _boardDeferred.maybeCompleteDeferredDown(),
        refreshBoundSources: _refreshBoundSources,
      ),
      _boardSection,
      _catalogSection,
      _boardPublication,
      _stageSection,
    );
    _boardFocus = HomeBoardFocus(
      (
        mounted: () => mounted,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        activeTabIndex: () => MainPageBridge.activeTvTabIndex,
        tabIndex: () => _tabIndex,
        sidebarFocused: () =>
            MainPageBridge.isTvSidebarFocused?.call() ?? false,
        focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
        loadMore: _boardPaging.loadMoreBoard,
        maybeCompleteDeferredDown: () =>
            _boardDeferred.maybeCompleteDeferredDown(),
        deferDownMove:
            ({int rowIndex = -1, String? homeRowId, required int column}) =>
                _boardDeferred.deferDownMove(
                  rowIndex: rowIndex,
                  homeRowId: homeRowId,
                  column: column,
                ),
      ),
      _boardSection,
      _inputSection,
      _discoverSection,
      _listsSection,
      _continuationSection,
      _savedSection,
      _displaySection,
      _stageSection,
      _stageRailsSection,
      _spotlightSection,
      _heroPreview,
    );
    _boardDeferred = HomeBoardDeferred(
      (
        mounted: () => mounted,
        focusCatalogContinuation: _boardFocus.focusCatalogContinuation,
        focusHomeRailAt: _boardFocus.focusHomeRailAt,
        focusRow: _boardFocus.focusRow,
      ),
      _boardSection,
      _stageRailsSection,
    );
    _boardConfiguration = HomeBoardConfigurationSection(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        bindings: () => _homeBoardBindings,
      ),
      _boardSection,
      _boardLoading,
      _boardFocus,
      _keywordSection,
      _displaySection,
      _continuationSection,
      _continuationLoading,
      _heroPreview,
      _modeSection,
      _catalogSection,
      _spotlightSection,
      _savedSection,
    );
    _boardRows = HomeBoardRows(
      (
        setState: setState,
        context: () => context,
        rowId: _sectionRowId,
        classicRowExtent: (context, {CatalogSection? section}) =>
            _classicSection.classicCatalogRowExtent(context, section: section),
        refreshBoundSources: _refreshBoundSources,
      ),
      _boardSection,
      _boardLoading,
      _boardPaging,
      _catalogSection,
      _displaySection,
      _stageSection,
      _stageRailsSection,
      _stageFavorites,
      _spotlightSection,
      _heroSection,
      _heroPreview,
      _heroLive,
    );
    _classicSection = HomeClassicSection(
      (
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        media: () => _boardMedia,
        artworkWidth: () => _tvHeroArtworkCacheWidth,
        artworkHeight: () => _tvHeroArtworkCacheHeight,
        sourceTag: _catalogSourceTag,
        openSeeAll: _openCatalogSeeAll,
        heroIdentity: () => identityHashCode(this),
        isBound: _isBound,
        pikpakOnly: () => _pikpakOnly,
        sidebar: () => MainPageBridge.focusTvSidebar?.call(),
        openItem: _sectionOpenItem,
        quickPlay: _sectionQuickPlay,
      ),
      _boardSection,
      _boardFocus,
      _boardDeferred,
      _boardPaging,
      _catalogSection,
      _displaySection,
      _stageRailsSection,
      _stageGeometry,
      _savedSection,
      _savedRows,
      _continuationProjection,
      _continuationMenu,
      _continuationRows,
      _heroSection,
      _heroPreview,
      _heroLive,
    );
    _boardRendering = HomeBoardRendering(
      (
        mounted: () => mounted,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        profileCurrent: () =>
            _profileSessionOwner == ProfileSessionMemory.captureOwner(),
        layouts: () => {
          'canvas': _stageBoards.buildCanvasBoard,
          'atrium': _atriumLayout.buildAtriumBoard,
          'mosaic': _stageBoards.buildMosaicBoard,
          'promenade': _stageBoards.buildPromenadeBoard,
          'deck': _stageBoards.buildDeckBoard,
          'tonight': _tonightLayout.buildTonightBoard,
          'spotlight': _spotlightBoards.buildSpotlightBoard,
        },
        classic: _classicSection.buildClassicBoard,
        searchSpotlight: _spotlightResults.buildSearchSpotlightBoard,
      ),
      _boardSection,
      _boardLoading,
      _boardPaging,
      _boardFocus,
      _catalogSection,
      _displaySection,
      _spotlightSection,
      _spotlightRows,
      _savedSection,
      _continuationProjection,
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
    _boardSection.homeReturnRepository = ref.read(
      homeReturnRepositoryProvider(_profileSessionOwner),
    );
    _boardSection.homeCollectionsRepository = ref.read(
      homeCollectionsRepositoryProvider,
    );
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
      replaceRows: _boardRows.applySections,
      appendRows: _boardPaging.appendSections,
      presentKeyword: _keywordSection.presentKwStreaming,
      finishKeyword: _keywordSection.finishKeyword,
      cancelSubmitFocus: _searchSubmitFocus.cancel,
    );
    if (!widget.searchMode && !widget.discoverMode) {
      _boardSection.homeReturnRepository.observeInvalidation();
    }
    final homeSnapshot = !widget.searchMode && !widget.discoverMode
        ? _boardSection.homeReturnRepository.take()
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
    _boardConfiguration.homeDefaultViewSubscription = ref.listenManual(
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
    _boardSection.homeLastScroll = restoredHome && !widget.isTelevision
        ? homeSnapshot.scrollOffset
        : 0;
    _boardSection.boardViewport.initializeScroll(_boardSection.homeLastScroll);
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
      MainPageBridge.addHomeSettingsListener(
        _boardConfiguration.reloadForHomeSettings,
      );
      HomeRowRefreshSignal.addListener(_boardConfiguration.queueHomeRows);
      _stremio.addAddonsChangedListener(
        _boardConfiguration.onHomeAddonsChanged,
      );
      // IPTV list mutations (picker, IPTV settings, provider deletion,
      // reconcile, import) all bump the store revision — the only signal a
      // Home that stays alive across tab switches gets about them.
      IptvMediaStore.listsRevision.addListener(
        _savedSection.onIptvListsRevision,
      );
      if (!restoredKeyword) {
        unawaited(_boardConfiguration.loadHomeDefaultView());
      }
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
    _boardSection.boardScroll.addListener(_boardPaging.onBoardScroll);
    _keywordSection.keywordViewport.observeScroll();
    _refreshTraktAuthState();
    _refreshSimklAuthState();
    _refreshMdblistAuthState();
    _loadMergedSeriesFlag();
    // (The keyword restore itself ran earlier — before _boardConfiguration.loadHomeDefaultView —
    // see the ordering comment there.) A restored search carries its own
    // filters, so don't overwrite them with the saved defaults.
    if (!restoredKeyword) {
      unawaited(_keywordSection.loadDefaultKeywordFilters());
    }
    // The dedicated Search tab only shows a field + blank prompt until a query,
    // so it skips the whole board pipeline (home catalogs, Continue Watching,
    // Trakt, favourites) — catalog search fetches its addons on demand. It also
    // never runs _boardLoading.load(), which is what clears _boardSection.loading, so clear it here or the
    // results grid (_boardRendering.buildBoard) would sit on its initial spinner forever.
    if (widget.searchMode) {
      _boardSection.loading = false;
    } else if (widget.discoverMode) {
      // Discover browses one source at a time via the Source dropdown, so it
      // skips the board's catalog pipeline and just primes the Continue Watching
      // + Trakt rows its first two sources draw from. _refreshPikpakOnly gates the
      // Quick-Play affordance the same way the board does.
      _boardSection.loading = false;
      _refreshPikpakOnly();
      _discoverLoading.loadAddons();
      _discoverLoading.primeRows();
    } else {
      // TV board: last-resort focus reclaim. Several load/reload paths dispose
      // FocusNodes wholesale (_boardRows.applySections rebuilds every catalog row's
      // nodes; CW rows re-sync after playback) and any of them can kill the
      // node holding primary focus — leaving the remote dead with no DPAD
      // press able to recover (the shell's recovery only fires when the scope
      // has NO traversable descendants, and the board always has plenty).
      // Watch the FocusManager and re-anchor onto the board when focus dies.
      if (widget.isTelevision) {
        FocusManager.instance.addListener(_boardFocus.onGlobalFocusChange);
      }
      // Kick off every leading-content load. Auto-focus settles to the top as
      // these complete; once they've ALL settled the arrival window is over and
      // re-anchoring latches off (see [_settleAutoFocusAfter]), so a later
      // background reload or a return from playback never yanks focus.
      _settleAutoFocusAfter([
        if (restoredHome && !restoredKeyword)
          _restoreHomeSnapshot(homeSnapshot)
        else
          _boardLoading.load(),
        _continuationLoading.loadContinueWatching(),
        _continuationLoading.loadTraktContinueWatching(),
        // refreshBound:false — _boardLoading.load()'s bound-source scan (which now covers the
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
  /// window": one final placement pass, then latch [_boardFocus.autoFocusSettled] so
  /// re-anchoring never fires again (a background CW/Trakt refresh, or focus
  /// restoration after returning from playback, must not move the user's focus).
  Future<void> _settleAutoFocusAfter(List<Future<void>> loads) async {
    await Future.wait(loads.map((f) => f.catchError((_) {})));
    if (!mounted) return;
    _boardFocus.maybeAutoFocusBoard();
    // Latch on the following frame so the placement pass above runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _boardFocus.autoFocusSettled = true;
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
    // tracker rows; _boardConfiguration.reloadForHomeSettings can legitimately return early when
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
    // catalog search is showing (see _boardConfiguration.requestBoardReload); safe against
    // overlap via _boardSection.boardLoadGen.
    if (!widget.searchMode &&
        !widget.discoverMode &&
        _boardSection.trackerExtrasEnabled) {
      _boardConfiguration.requestBoardReload();
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
    _boardSection.homeReturnRevision =
        _boardSection.homeReturnRepository.revision;
    _boardSection.homeLoadedAt = snapshot.loadedAt;
    _spotlightSection.spotlightHeroOverride = snapshot.hero;
    _boardSection.addonsById
      ..clear()
      ..addAll(snapshot.board.addons);
    _boardSection.loading = false;
    _spotlightSection.spotlightEntryRevealed = true;
    if (snapshot.heroResolutionPending) {
      unawaited(
        _spotlightSection.resolveSpotlightHeroSource(
          _boardSection.addonsById.values.toList(),
        ),
      );
    }
    _boardRows.applySections(_boardSection.homeSections);
    MainPageBridge.homeBoardReady.value = true;
    _boardFocus.maybeAutoFocusBoard();
    _boardPaging.maybeAutoFillBoard();
    unawaited(_refreshPikpakOnly());
    if (_boardSection.trackerExtrasEnabled) {
      final generation = _boardSection.boardLoadGen;
      final owner = _profileSessionOwner;
      unawaited(
        HomeListRowsService.instance
            .resolve(
              _boardSection.homeExtras,
              previous: _boardSection.homeSections
                  .whereType<HomeListSection>()
                  .toList(),
              isCurrent: () =>
                  mounted &&
                  generation == _boardSection.boardLoadGen &&
                  owner == ProfileSessionMemory.captureOwner(),
              onUpdate: (rows) {
                if (!mounted ||
                    generation != _boardSection.boardLoadGen ||
                    owner != ProfileSessionMemory.captureOwner()) {
                  return;
                }
                _boardPublication.publishHomeProgress(
                  replaceHomeListRows(_boardSection.homeSections, rows),
                  false,
                  generation,
                  ProfileRuntime.scope.value,
                );
              },
            )
            .catchError((_) => <HomeListSection>[]),
      );
    }
    // Re-read local configuration too, including imports that bypass the UI
    // bridge. Continue Watching and favourite loaders still run on each visit.
    await _boardConfiguration.reloadForHomeSettings();
  }

  void _preserveHomeSnapshot() {
    final board = _boardSection.committedBoard;
    final loadedAt = _boardSection.homeLoadedAt;
    if (widget.searchMode ||
        widget.discoverMode ||
        board == null ||
        loadedAt == null ||
        _boardSection.loading ||
        _boardSection.error != null ||
        _boardSection.boardRefreshing ||
        _boardSection.boardLoadingMore ||
        _boardSection.pendingBoardReload) {
      return;
    }
    _boardSection.homeReturnRepository.store((
      sections: _boardSection.homeCatalogController.rowsForReturn(),
      board: board,
      configuration: _boardSection.homeConfiguration,
      hero: _spotlightSection.spotlightHeroOverride == null
          ? null
          : copyHomeRowForReturn(_spotlightSection.spotlightHeroOverride!),
      heroResolutionPending: _spotlightSection.heroSourceResolutionPending,
      cardOrientation: _displaySection.homeCardOrientation,
      hideCardTitlesAndRatings: _displaySection.hideHomeCardTitlesAndRatings,
      hideCatalogAddonNames: _displaySection.hideHomeCatalogAddonNames,
      hideCollectionNames: _displaySection.hideHomeCollectionNames,
      loadedAt: loadedAt,
      scrollOffset: _boardSection.homeLastScroll,
    ), revision: _boardSection.homeReturnRevision);
  }

  @override
  void dispose() {
    _preserveHomeSnapshot();
    _boardSection.homePublication.dispose();
    MetadataPreferencesService.revision.removeListener(
      _metadataSettingsChanged,
    );
    _boardFocus.catalogFocus.dispose();
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
    FocusManager.instance.removeListener(_boardFocus.onGlobalFocusChange);
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    MainPageBridge.removePlaybackReturnListener(
      _continuationReturn.onPlaybackReturned,
    );
    MainPageBridge.removePlayerLaunchListener(
      _continuationReturn.markPlaybackStarted,
    );
    MainPageBridge.removeHomeSettingsListener(
      _boardConfiguration.reloadForHomeSettings,
    );
    MainPageBridge.removeHomeSettingsListener(_reloadSearchCardPrefs);
    HomeRowRefreshSignal.removeListener(_boardConfiguration.queueHomeRows);
    _stremio.removeAddonsChangedListener(
      _boardConfiguration.onHomeAddonsChanged,
    );
    _boardConfiguration.homeRefreshQueue.dispose();
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
    _boardConfiguration.homeDefaultViewSubscription.close();
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
    _boardSection.boardViewport.disposeScroll();
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

  void _disposeNodes() => _boardSection.boardViewport.disposeNodes();

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
      for (final section in _boardSection.sections) ...section.items,
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

  VoidCallback _favRowOnUp(String rowId, int column) =>
      () => _boardFocus.focusRelativeHomeRail(rowId, -1, column);

  VoidCallback _favRowOnDown(String rowId, int column) =>
      () => _boardFocus.focusRelativeHomeRail(rowId, 1, column);

  /// Resolve the addon that a Continue Watching title should route through.
  /// Prefers the stored source addon; falls back to any homepage addon, then a
  /// minimal placeholder so Play still works even if the addon is gone.
  StremioAddon _addonForContinue(String? addonId) {
    if (addonId == NativeSeriesMetadataService.addon.id) {
      return NativeSeriesMetadataService.addon;
    }
    for (final addon in _boardSection.addonsById.values) {
      if (addon.sourceBindingKey == addonId ||
          addon.portableConfigurationKey == addonId) {
        return addon;
      }
    }
    if (addonId != null && _boardSection.addonsById.containsKey(addonId)) {
      return _boardSection.addonsById[addonId]!;
    }
    // "Any homepage addon" means a REAL catalog addon — the Trakt/Simkl list
    // rows that now lead _boardSection.homeSections carry only a placeholder addon (empty
    // baseUrl), which can't serve /meta or /stream.
    for (final s in _boardSection.homeSections) {
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

  // ── Focus entry ──────────────────────────────────────────────────────────

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
        _boardPublication.resumeHomeProgress();
      } else {
        _boardDeferred.clearDeferredDown();
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
    _boardFocus.onGlobalFocusChange();
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
      if (hadCatalogSearch) _boardRows.applySections(const []);
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
    board: _boardRendering.buildBoard,
    spotlight: _spotlightShell.buildSpotlightShell,
    header: _inputSection.buildHeader,
    sourcesBar: _inputSection.buildUnifiedCatalogSourcesBar,
    body: _inputSection.buildBody,
  );

  // ── Discover tab ────────────────────────────────────────────────────────────

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
}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
