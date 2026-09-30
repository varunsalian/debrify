import '../features/home/presentation/home_leading_content_composition.dart';
import '../features/search/presentation/search_presentation_composition.dart';
import '../features/discover/presentation/discover_composition.dart';
import '../features/home/presentation/home_board_presentation_composition.dart';
import '../features/home/presentation/home_catalog_presentation_composition.dart';
import '../features/discover/presentation/discover_session_lifecycle.dart';
import '../features/search/presentation/search_title_composition.dart';
import '../features/discover/presentation/discover_panel_composition.dart';
import '../features/home/presentation/home_item_composition.dart';
import '../features/home/presentation/home_hero_shell_bridge.dart';
import '../features/home/presentation/home_content_startup.dart';
import '../features/home/presentation/home_view_bindings.dart';
import '../features/search/presentation/search_session_lifecycle.dart';
import '../features/home/presentation/home_media_composition.dart';
import '../features/home/presentation/home_hero_composition.dart';
import '../features/home/presentation/home_stage_composition.dart';
import '../features/search/presentation/search_profile_handoff.dart';
import '../features/home/presentation/home_return_section.dart';
import '../features/home/application/home_catalog_dependencies.dart';
import '../features/home/presentation/home_detail_actions.dart';
import '../features/search/presentation/keyword_search_actions.dart';
import '../features/search/presentation/lists_navigation.dart';
import '../features/home/application/home_detail_action_dependencies.dart';
import '../features/home/application/home_simkl_continuation_dependencies.dart';
import '../features/search/presentation/search_page_shell.dart';
import '../features/home/models/home_board_configuration.dart';
import '../features/home/models/home_catalog_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/native_series_metadata_service.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/metadata_preferences_service.dart';
import '../services/home_row_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_util.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../services/analytics_service.dart';
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
import '../services/tmdb_title_search.dart';
import '../services/metadata_title_service.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../services/simkl/simkl_menu_helpers.dart';

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

class _SearchScreenState extends ConsumerState<SearchScreen>
    with RouteAware, WidgetsBindingObserver {
  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get _tabIndex => widget.searchMode ? 17 : (widget.discoverMode ? 18 : 15);

  final StremioService _stremio = StremioService.instance;

  final TextEditingController _searchController = TextEditingController();
  late final _titleSearch = widget.titleSearch ?? TmdbTitleSearch();
  final _titleSearchScope = ProfileRuntime.scope.value;
  final TvSearchFocusHandoff _searchSubmitFocus = TvSearchFocusHandoff();

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [_board.workflow.boardConfiguration.reloadForHomeSettings] when the manager saves.
  // Bootstrap is captured at state construction, matching the previous field
  // initialization. All accepted changes live in the controller afterwards.
  final _initialHomeConfiguration = HomeBoardConfiguration(
    preferences: const HomeCatalogPreferences.empty(),
    collections: const [],
    collectionsSignature: HomeCollectionsStore.signatureOf(const []),
    hideWatched: HideWatchedPrefs.enabled,
  );
  late final HomeViewBindings _homeView;
  late final HomeContentStartup _contentStartup;
  late final HomeBoardPresentation _board;
  late final HomeLeadingContent _leading;
  late final HomeCatalogPresentation _catalogPresentation;
  late final SearchSessionLifecycle _searchLifecycle;
  late final SearchProfileHandoff _profileHandoff;
  late final HomeReturnSection _homeReturn;
  late final HomeItemComposition _homeActions;
  late final HomeMediaComposition _mediaComposition;
  late final HomeHeroComposition _hero;

  late final DiscoverComposition _discover;
  late final SearchPresentation _search;
  late final DiscoverPanelComposition _discoverPanels;
  late final DiscoverSessionLifecycle _discoverLifecycle;

  @override
  void initState() {
    super.initState();
    _discover = createDiscover((
      mounted: () => mounted,
      setState: setState,
      context: () => context,
      discoverMode: () => widget.discoverMode,
      isTelevision: () => widget.isTelevision,
      bindings: () => _discoverLifecycle.bindings,
      catalog: () => _catalogPresentation,
      continuation: () => _leading.content,
      board: () => _board.workflow.boardSection,
      buildPanel: (section) => _discoverPanels.build(section),
      mdblistEnabled: kMdblistEnabled,
    ));
    _search = createSearchPresentation(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        session: () => _searchLifecycle,
        board: () => _board,
        catalog: () => _catalogPresentation,
        hero: () => _hero,
        keywordAllowed: () =>
            ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
        floatingNavigation: () =>
            MainPageBridge.phoneNavStyleCached == 'floating',
        mdblistEnabled: kMdblistEnabled,
      ),
      searchController: _searchController,
      submitFocus: _searchSubmitFocus,
      discover: _discover.section,
      createKeywordActions: (section, selection) => KeywordSearchActions((
        context: () => context,
        mounted: () => mounted,
        bindings: () => _searchLifecycle.searchResultBindings,
        bulkAdd: TorrentBulkAddService.showBulkAddDialog,
        activate: TorrentPlaybackService.activateTorrent,
        canDownload: (torrent) =>
            ProfilePolicyGuard.allowsSync(ProfileFeature.downloads) &&
            TorrentPlaybackService.supportsDirectStreamDownload(torrent),
        download: TorrentPlaybackService.downloadDirectStream,
        copyText: (link) => Clipboard.setData(ClipboardData(text: link)),
        snack: (message) => _homeActions.playback.snack(message),
        freeze: section.kwFreeze,
        selection: selection,
      )),
      trackOpen: (choice) => AnalyticsService.trackInBackground(
        'mdblist_list_search_open',
        {'liked': choice.liked},
      ),
      createNavigation: () => ListsNavigation(
        isTelevision: () => widget.isTelevision,
        pikpakOnly: () => _catalogPresentation.badges.pikpakOnly,
        isBound: (item) => _catalogPresentation.badges.isBound(item),
        onOpen: (item) => _homeActions.items.openItem(
          item,
          _catalogPresentation.navigation.addonForContinue(
            item.sourceAddon?.id,
          ),
          isMdblistSource: true,
        ),
        onQuickPlay: (item) => _homeActions.catalog.onCatalogPlay(
          item,
          _catalogPresentation.navigation.addonForContinue(
            item.sourceAddon?.id,
          ),
          isMdblistSource: true,
        ),
        afterReturn: _leading.continuation.returning.afterSeeAllReturn,
      ),
      createTitles: (readMode) => createSearchTitles(
        (
          mounted: () => mounted,
          context: () => context,
          mode: readMode,
          searchMode: () => widget.searchMode,
          metadata: () =>
              _catalogPresentation.metadata.metadataFeatureController,
          activeTab: () => MainPageBridge.activeTab.value,
          originCurrent: () => _titleSearchScope == ProfileRuntime.scope.value,
          update:
              (query, {required language, enabled = true, composing = false}) =>
                  _titleSearch.update(
                    query,
                    language: language,
                    enabled: enabled,
                    composing: composing,
                  ),
          clear: () => _titleSearch.clear(),
          titles: () => _titleSearch.value,
          resolver: () =>
              widget.suggestedTitleResolver ??
              MetadataTitleService.instance.resolve,
          openItem: (item, addon) => _homeActions.items.openItem(item, addon),
        ),
        _searchController,
        _searchSubmitFocus,
      ),
    );
    _homeActions = createHomeItemActions(
      ref,
      (
        mounted: () => mounted,
        profileCurrent: () =>
            _searchLifecycle.profileSessionOwner ==
            ProfileSessionMemory.captureOwner(),
        context: () => context,
        isTelevision: () => widget.isTelevision,
        view: () => _homeView,
        badges: () => _catalogPresentation.badges,
        returning: () => _leading.continuation.returning,
        integrations: () => _catalogPresentation.integrations,
        continuation: () => _leading.content,
        navigation: () => _catalogPresentation.navigation,
        removal: () => _leading.removal,
      ),
      createDetails: (playback, catalog, sources) => HomeDetailActions(
        ref,
        (
          context: () => context,
          session: () => _homeView.homeCatalogSession,
          bridge: (route) => _leading.continuation.returning.detailBridge(
            () => playback.catalogNavigationCurrent() && route.isActive,
          ),
          removeLocal: (action, id, route) =>
              _leading.removal.handleContinueDetailAction(action, id, route),
          removeTrakt: (id, {detailRoute}) => _leading.removal
              .removeFromTraktContinueWatching(id, detailRoute: detailRoute),
          removeMdblist: (item) => _leading.removal.removeMdblistCwItem(item),
          invokeSimkl: (item, action, detailRoute, presetRating) =>
              handleSimklMenuAction(
                context,
                item,
                action,
                actions: ref.read(
                  homeDetailActionsProvider(
                    _searchLifecycle.profileSessionOwner,
                  ),
                ),
                presetRating: presetRating,
                isCurrent: () =>
                    playback.catalogNavigationCurrent() && detailRoute.isActive,
                removeContinueWatching: () => ref
                    .read(
                      homeSimklHistoryRemovalProvider(
                        _searchLifecycle.profileSessionOwner,
                      ),
                    )
                    .remove(
                      item.progressId ?? item.id,
                      item.type,
                      isCurrent: () =>
                          playback.catalogNavigationCurrent() &&
                          detailRoute.isActive,
                    ),
              ),
          invokeMdblist: (item, action, detailRoute, presetRating) =>
              handleMdblistMenuAction(
                context,
                item,
                action,
                actions: ref.read(
                  homeDetailActionsProvider(
                    _searchLifecycle.profileSessionOwner,
                  ),
                ),
                presetRating: presetRating,
                isCurrent: () =>
                    playback.catalogNavigationCurrent() && detailRoute.isActive,
              ),
        ),
        playback,
        catalog,
        sources,
      ),
    );
    _leading = createHomeLeadingContent(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        view: () => _homeView,
        board: () => _board,
        catalog: () => _catalogPresentation,
        hero: () => _hero,
        allowed: ProfilePolicyGuard.allowsSync,
        profileCurrent: () =>
            _searchLifecycle.profileSessionOwner ==
            ProfileSessionMemory.captureOwner(),
        tabIndex: () => _tabIndex,
        mdblistEnabled: kMdblistEnabled,
      ),
      search: _search,
      actions: _homeActions,
      playPlaylist: PlaylistPlayerService.play,
      removeWatchlist: (item) => StorageService.setMyWatchlistItem(item, false),
      iptvListId: HomeExtraRowIds.iptvList,
      openIptv: IptvCwRouter.open,
      launchIptv: (context, videoUrl, channel, isStremio) {
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
      removeSimkl: (item) => handleSimklMenuAction(
        context,
        item,
        SimklItemMenuAction.removeFromContinueWatching,
        isCurrent: _homeActions.playback.catalogNavigationCurrent,
        removeContinueWatching: () => ref
            .read(
              homeSimklHistoryRemovalProvider(
                _searchLifecycle.profileSessionOwner,
              ),
            )
            .remove(
              item.progressId ?? item.id,
              item.type,
              isCurrent: _homeActions.playback.catalogNavigationCurrent,
            ),
      ),
    );
    _hero = createHomeHero(
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        media: () => _homeView.homeMediaBindings,
        resetStageNavigation: () =>
            _board.stages.stageSection.resetStageNavigation(),
        favorites: () => _board.stages.stageFavorites,
        board: () => _board.workflow,
        repository: () => ref.read(homeCatalogRepositoryProvider),
        publishTopShelf: (items, {sourceTitle}) => TvosTopShelfService.instance
            .publishSpotlight(items, sourceTitle: sourceTitle),
      ),
      search: _search.modes,
      input: _search.input.inputSection,
      searchController: _searchController,
      ambientArt: MainPageBridge.tvAmbientArt,
      heroTint: MainPageBridge.tvHeroTint,
      chromeDim: MainPageBridge.tvChromeDim,
      lightsOff: MainPageBridge.tvStageLightsOff,
    );
    _board = createHomeBoardPresentation(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        bindings: () => _homeView.homeBoardBindings,
        scope: () => ProfileRuntime.scope.value,
        catalog: () => _catalogPresentation,
        media: () => _mediaComposition,
        tabIndex: () => _tabIndex,
        profileCurrent: () =>
            _searchLifecycle.profileSessionOwner ==
            ProfileSessionMemory.captureOwner(),
        heroIdentity: () => identityHashCode(this),
      ),
      hero: _hero,
      spotlight: _hero.spotlightSection,
      input: _search.input.inputSection,
      discover: _discover.section,
      search: _search.modes,
      keyword: _search.keyword.keywordSection,
      continuation: _leading.content,
      continuationView: _leading.continuation,
      saved: _leading.saved,
      actions: _homeActions,
      ambientArt: MainPageBridge.tvAmbientArt,
      heroTint: MainPageBridge.tvHeroTint,
      ready: () => MainPageBridge.homeBoardReady,
    );
    _homeReturn = HomeReturnSection(
      ref,
      (
        mounted: () => mounted,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        owner: () => _searchLifecycle.profileSessionOwner,
        currentOwner: ProfileSessionMemory.captureOwner,
        scope: () => ProfileRuntime.scope.value,
        refreshPikpakOnly: () =>
            _catalogPresentation.badges.refreshPikpakOnly(),
      ),
      _board.workflow.boardSection,
      _board.workflow.boardRows,
      _board.workflow.boardFocus,
      _board.workflow.boardPaging,
      _board.workflow.boardPublication,
      _board.workflow.boardConfiguration,
      _hero.displaySection,
      _hero.spotlightSection,
      MainPageBridge.homeBoardReady,
    );
    _catalogPresentation = createHomeCatalogPresentation(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        context: () => context,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        view: () => _homeView,
        nativeAddon: () => NativeSeriesMetadataService.addon,
        readMergedSeriesEnabled: StorageService.getMergedSeriesPageEnabled,
        cardSettings: () => _discoverLifecycle.bindings.cards,
        tabIndex: () => _tabIndex,
        localCompletion: () => StorageService.localCompletionRevision,
        mdblistPlayback: () => MdblistService.instance.playbackRevision,
      ),
      board: _board.workflow,
      continuation: _leading.content,
      search: _search.modes,
      input: _search.input.inputSection,
      searchController: _searchController,
      discover: _discover.section,
      hero: _hero,
      actions: _homeActions,
      playback: _leading.playback,
      returning: _leading.continuation.returning,
      saved: _leading.saved.section,
    );
    _profileHandoff = SearchProfileHandoff(
      () =>
          _searchLifecycle.profileSessionOwner !=
          ProfileSessionMemory.captureOwner(),
      _searchController,
      _search.modes.title,
      _search.keyword.keywordSection,
      _search.modes.lists,
      _search.modes.catalog,
      _board.workflow.boardRows,
    );
    _mediaComposition = HomeMediaComposition(
      (
        artworkWidth: () =>
            TvHeroArtworkQualityController.decodeSize.landscapeWidth,
        artworkHeight: () =>
            TvHeroArtworkQualityController.decodeSize.posterHeight,
        isTelevision: () => widget.isTelevision,
        isAddonChannel: StremioIptvService.isStremioChannelUrl,
      ),
      _hero,
      _board.stages.stageFavorites,
    );
    _searchLifecycle = SearchSessionLifecycle(
      ref,
      (
        mounted: () => mounted,
        isTelevision: () => widget.isTelevision,
        setState: setState,
      ),
      _search.keyword.keywordSection,
      _search.returning,
      _board.workflow.boardRows,
      _board.workflow.boardPaging,
      _searchSubmitFocus,
    );
    _homeView = HomeViewBindings(
      ref,
      (
        mounted: () => mounted,
        setState: setState,
        isTelevision: () => widget.isTelevision,
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        hideWatched: () => HideWatchedPrefs.enabled,
        search: () => _searchLifecycle,
      ),
      _initialHomeConfiguration,
      _board.workflow.boardSection,
      _board.workflow.boardConfiguration,
      _hero.displaySection,
      _hero.heroPreview,
    );
    _contentStartup = HomeContentStartup(
      (
        searchMode: () => widget.searchMode,
        discoverMode: () => widget.discoverMode,
        isTelevision: () => widget.isTelevision,
      ),
      _board.workflow,
      _catalogPresentation,
      _discover.loading,
      _homeView,
      _homeReturn,
      _leading.content.loading,
      _leading.saved.section,
      _search.keyword.keywordSection,
    );
    _discoverPanels = DiscoverPanelComposition(
      (
        mounted: () => mounted,
        isTelevision: () => widget.isTelevision,
        mdblistEnabled: kMdblistEnabled,
      ),
      _catalogPresentation.metadata,
      _catalogPresentation.integrations,
      _catalogPresentation.badges,
      _board.workflow.boardSection,
      _catalogPresentation.navigation,
      _homeActions,
      _leading.content,
      _leading.playback,
    );
    _discoverLifecycle = DiscoverSessionLifecycle(ref, (
      mounted: () => mounted,
      discoverMode: () => widget.discoverMode,
      owner: () => _searchLifecycle.profileSessionOwner,
    ), _discover.section);
    _titleSearch.addListener(_search.modes.title.publishTitleSuggestions);
    _searchController.addListener(
      _search.modes.title.onTitleSearchEditingChanged,
    );
    ProfileRuntime.scope.addListener(_profileHandoff.onSearchProfileChanged);
    MetadataPreferencesService.revision.addListener(
      _catalogPresentation.metadata.metadataSettingsChanged,
    );
    _catalogPresentation.metadata.start((
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    ));
    WidgetsBinding.instance.addObserver(this);
    _searchLifecycle.profileSessionOwner = ProfileSessionMemory.captureOwner();
    _homeView.initializeRepositories();
    final keywordSnapshot = _searchLifecycle.initializeKeyword();
    _homeView.initialize(keywordSnapshot);
    // This one widget backs three tabs (Home board / dedicated Search / Discover).
    AnalyticsService.screenView(
      widget.searchMode
          ? 'search'
          : widget.discoverMode
          ? 'discover'
          : 'home',
    );
    _catalogPresentation.tabShell.start();
    _discoverLifecycle.initialize();
    _hero.heroShell.start(this);
    // Discover on TV: relay the trailer takeover to the sidebar chrome-dim so
    // the rail hides when the trailer goes fullscreen. The showing listener
    // arms the theater timer (deep lights-off a few seconds into playback).
    if (widget.discoverMode) {
      _discover.section.startShell();
    }
    HomeHeroShellBridge.startContentSignals(
      isTelevisionSearch: () => widget.isTelevision && widget.searchMode,
      integration: _catalogPresentation.integrations,
      returning: _leading.continuation.returning,
      display: _hero.displaySection,
    );
    // Restore a keyword search preserved from a prior tab visit (results +
    // scroll) BEFORE the async default-view load below can start: restoration
    // sets keyword mode synchronously, and a later-resolving catalog default
    // would flip the mode back and could fire a catalog search with the
    // restored keyword text. A successful restore therefore also suppresses
    // the default-view load outright.
    final restoredKeyword = _search.returning.restore(keywordSnapshot);
    // Home board only: live-refresh when the Home Rows manager changes which
    // rows are hidden. The bridge also invalidates a saved return snapshot.
    if (!widget.searchMode && !widget.discoverMode) {
      _board.workflow.boardConfiguration.observeChanges(
        addHomeSettings: MainPageBridge.addHomeSettingsListener,
        addRows: HomeRowRefreshSignal.addListener,
        addAddons: _stremio.addAddonsChangedListener,
        iptvRevision: () => IptvMediaStore.listsRevision,
        restoredKeyword: restoredKeyword,
      );
      HomeHeroShellBridge.startHomeLayout(
        isTelevision: () => widget.isTelevision,
        restoredKeyword: restoredKeyword,
        display: _hero.displaySection,
        preview: _hero.heroPreview,
        stage: _board.stages.stageSection,
        spotlight: _hero.spotlightShell,
      );
    }
    _hero.spotlightShell.observeSearchFocus();
    _board.workflow.boardSection.boardScroll.addListener(
      _board.workflow.boardPaging.onBoardScroll,
    );
    _search.keyword.keywordSection.keywordViewport.observeScroll();
    _contentStartup.start(restoredKeyword: restoredKeyword);
  }

  @override
  void dispose() {
    _homeReturn.preserveHomeSnapshot();
    _board.workflow.boardSection.homePublication.dispose();
    MetadataPreferencesService.revision.removeListener(
      _catalogPresentation.metadata.metadataSettingsChanged,
    );
    _board.workflow.boardFocus.catalogFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _leading.content.section.mdblistContinuationController
        .cancelRevisionRefresh();
    _hero.spotlightSection.spotlightHeroNode.dispose();
    _search.returning.preserve();
    _catalogPresentation.tabShell.dispose();
    HomeHeroShellBridge.disposeContentSignals(
      offTvHome: () =>
          !widget.isTelevision && !widget.searchMode && !widget.discoverMode,
      spotlight: _hero.spotlightShell,
      searchField: () => _search.input.inputSection.searchFocusNode,
      preview: _hero.heroPreview,
      reclaimFocus: _board.workflow.boardFocus.onGlobalFocusChange,
      integration: _catalogPresentation.integrations,
      returning: _leading.continuation.returning,
      configuration: _board.workflow.boardConfiguration,
      display: _hero.displaySection,
    );
    _board.workflow.boardConfiguration.stopObservingChanges(
      removeRows: HomeRowRefreshSignal.removeListener,
      removeAddons: _stremio.removeAddonsChangedListener,
      iptvRevision: () => IptvMediaStore.listsRevision,
    );
    _leading.saved.section.iptvListFocus.dispose();
    HomeHeroShellBridge.disposeHomeLayout(
      isTelevisionHome: () =>
          widget.isTelevision && !widget.searchMode && !widget.discoverMode,
      display: _hero.displaySection,
      preview: _hero.heroPreview,
      stage: _board.stages.stageSection,
    );
    disposeHomeStageResources(_board.stages);
    _hero.heroShell.dispose();
    disposeHomeHeroMedia(_hero, _homeView.homeMediaBindings);
    _searchController.dispose();
    ProfileRuntime.scope.removeListener(_profileHandoff.onSearchProfileChanged);
    _discoverLifecycle.bindings.close();
    _catalogPresentation.metadata.metadataFeatureSubscription.close();
    _homeView.closePresentationBindings();
    _searchLifecycle.searchResultBindings.closeCatalogAndLists();
    _search.keyword.keywordSection.closeAppearance();
    _searchLifecycle.searchResultBindings.closeKeyword();
    _titleSearch.removeListener(_search.modes.title.publishTitleSuggestions);
    _titleSearch.dispose();
    _search.modes.title.presentation.dispose();
    _search.input.inputSection.disposeFocus();
    _search.modes.lists.disposeListsNodes();
    _discover.section.dispose();
    _board.workflow.boardSection.boardViewport.disposeScroll();
    _search.keyword.keywordSection.keywordViewport.dispose();
    _search.keyword.keywordSection.keywordFocus.dispose();
    _search.modes.catalog.catalogSourcesBtnFocus.dispose();

    _board.workflow.boardSection.boardViewport.disposeNodes();
    disposeHomeLeadingFocus(_leading);
    super.dispose();
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
        _board.workflow.boardPublication.resumeHomeProgress();
      } else {
        _board.workflow.boardDeferred.clearDeferredDown();
        _board.stages.stageSection.stageDeferredAdvance.reset();
      }
    }
    _hero.heroShell.bindRoute(context);
  }

  @override
  void didPushNext() => _hero.heroShell.didPushNext();

  @override
  void didPopNext() {
    // A board reload UNDER a detail page/player can dispose the focused node;
    // the reclaim listener fires while covered and bails on route.isCurrent,
    // and no focus event re-fires it on the way back — re-run the dead check
    // now that the board is the top route again.
    _board.workflow.boardFocus.onGlobalFocusChange();
    if (!_hero.heroPreview.heroTrailerActive ||
        !_hero.heroPreview.heroTrailerEnabled) {
      return;
    }
    final item = _hero.heroSection.heroItem.value;
    if (item != null) _hero.heroPreview.scheduleHeroTrailer(item);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _leading.continuation.returning.didChangeAppLifecycleState(state);

  @override
  Widget build(BuildContext context) => buildSearchPageShell(
    context: context,
    glassHome: _hero.heroPreview.heroTrailerActive,
    discoverMode: widget.discoverMode,
    isTelevision: widget.isTelevision,
    dedicatedSearch: widget.searchMode,
    spotlightActive: () => _hero.spotlightShell.spotlightShellActive,
    discover: _discover.section.buildDiscover,
    board: _board.rendering.rendering.buildBoard,
    spotlight: _hero.spotlightShell.buildSpotlightShell,
    header: _search.input.inputSection.buildHeader,
    sourcesBar: _search.input.inputSection.buildUnifiedCatalogSourcesBar,
    body: _search.input.inputSection.buildBody,
  );
}
