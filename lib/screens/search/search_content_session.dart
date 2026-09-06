import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/stremio_addon.dart';
import '../../services/home_collection_rows.dart';
import '../../services/home_list_rows.dart';
import '../search/home_board_controller.dart';
import '../search/search_board_runtime.dart';
import '../search/catalog_search_controller.dart';
import '../search/search_screen_shells.dart';
import '../search/keyword_search_controller.dart';
import '../search/continue_watching_controller.dart';
import '../search/continue_watching_row.dart';
import '../search/fav_rows_controller.dart';
import '../search/search_content_data.dart';
import '../../services/filtered_catalog_pager.dart';
import '../../services/hide_watched_prefs.dart';
import '../../services/watched_filter.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../../services/storage_service.dart';
import '../../services/trakt/trakt_service.dart';
import '../../services/simkl/simkl_service.dart';
import '../../utils/tv_search_focus_handoff.dart';
import '../../services/mdblist/mdblist_list_source.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../episodes_screen.dart';
import 'search_content_actions.dart';
import '../search_screen.dart' show SearchBoardMode;

/// The mounting surface supplies Flutter access only, never content data.
abstract interface class SearchContentSurface {
  BuildContext get context;
  bool get mounted;
  void commit(VoidCallback change);
}

/// Rendering effects remain with the actual Home or Discover composition.
/// These operations retain their original variant guards and effect order.
abstract interface class SearchContentPresentation {
  void beforeApplySections();
  void resetStageGeneration();
  void publishTopShelfSpotlight();
  void seedHero(List<CatalogSection> sections);
  void maybeAutoFocusBoard();
  void focusContent();
  Widget wrapSeeAll(Widget child);
}

typedef SearchContentOptions = ({
  bool isTelevision,
  bool searchMode,
  bool discoverMode,
});

/// Shared controllers and content lifetime for Home/Search and Discover.
/// Presentation and action orchestration have separate owners.
class SearchContentSession {
  late SearchContentSurface surface;
  late SearchContentPresentation presentation;
  late SearchContentOptions Function() readOptions;
  SearchContentOptions get options => readOptions();
  BuildContext get context => surface.context;
  bool get mounted => surface.mounted;
  int get tabIndex => searchScreenTabIndex(
    searchMode: options.searchMode,
    discoverMode: options.discoverMode,
  );

  final StremioService stremio = StremioService.instance;
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode(debugLabel: 'search_field');
  final TvSearchFocusHandoff searchSubmitFocus = TvSearchFocusHandoff();
  String listsQuery = '';
  List<MdblistListChoice> listsResults = const [];
  bool listsSearching = false;
  String? listsError;
  int listsToken = 0;
  final List<FocusNode> listsNodes = [];
  SearchBoardMode mode = SearchBoardMode.catalog;
  bool pikpakOnly = false;
  bool mergedSeriesPage = false;
  bool isTraktAuthenticated = false;
  bool isSimklAuthenticated = false;
  bool isMdblistAuthenticated = false;
  bool loading = true;
  bool playedSinceRefresh = false;
  final SearchContentData contentData = SearchContentData();
  final CwFocusOwner cwNodes = CwFocusOwner();
  final SearchBoardRuntime boardRuntime = SearchBoardRuntime();
  Map<String, StremioAddon> addonsById = {};
  late final HomeBoardController board;
  late final CatalogSearchController catalogSearch;
  late final KeywordSearchController keyword;
  late final FavRowsController favourites;
  late final ContinueWatchingController cw;
  late final ContinueWatchingFlows cwFlows;
  late final SearchContentActions actions;

  SearchContentSession() {
    actions = SearchContentActions(this);
  }

  void initialize({required Future<bool> Function(String) readMergedRows}) {
    boardRuntime.isLive = () => mounted;
    boardRuntime.commit = surface.commit;
    boardRuntime.environment = () => (
      searchMode: options.searchMode,
      discoverMode: options.discoverMode,
      isTraktAuthenticated: isTraktAuthenticated,
    );
    boardRuntime.refreshBoundSources = refreshBoundSources;
    board = HomeBoardController(
      fetchCatalog: fetchBoardCatalog,
      isLive: () => mounted,
    );
    boardRuntime.board = board;
    board.hideWatched = HideWatchedPrefs.enabled;
    board.addListener(onBoardChanged);
    catalogSearch = CatalogSearchController(
      getDisabledAddons: StorageService.getCatalogSearchDisabledAddons,
      getSearchableAddons: stremio.getSearchableAddons,
      searchCatalog:
          (addon, catalog, query, {required throwOnError, onRawCount}) =>
              stremio.searchSingleCatalog(
                addon,
                catalog,
                query,
                throwOnError: throwOnError,
                onRawCount: onRawCount,
              ),
      isLive: () => mounted,
      isTelevision: () => options.isTelevision,
      onStarted: () {
        if (options.isTelevision && !searchFocusNode.hasFocus) {
          searchFocusNode.requestFocus();
        }
      },
      onClear: () => applySections(const []),
      onApplyFirst: (section) => applySections([section]),
      onAppend: (section) => boardRuntime.appendSections([section]),
      onTelevisionApply: applySections,
      onTelevisionSettled: () {
        if (boardRuntime.rowNodes.isNotEmpty &&
            boardRuntime.rowNodes.first.isNotEmpty) {
          completeSearchSubmitFocus(boardRuntime.rowNodes.first.first);
        } else {
          searchSubmitFocus.cancel();
        }
      },
      onAborted: () => searchSubmitFocus.cancel(),
    );
    boardRuntime.catalogSearch = catalogSearch;
    catalogSearch.addListener(onCatalogSearchChanged);
    favourites = FavRowsController(
      readContext: () => context,
      isLive: () => mounted,
      readIsTelevision: () => options.isTelevision,
      commit: (fn) => surface.commit(fn),
      addonForContinue: addonForContinue,
      readCatalogQuery: () => catalogSearch.query,
      readCatalogSearching: () => catalogSearch.searching,
      focusContent: presentation.focusContent,
      focusRelativeHomeRail: boardRuntime.focusRelativeHomeRail,
      readHomeDisabled: () => board.homeDisabled,
      maybeAutoFocusBoard: presentation.maybeAutoFocusBoard,
      openItem: actions.openItem,
      refreshAfterPlayback: refreshAfterPlayback,
      requestRowFocus: boardRuntime.requestRowFocus,
    );
    boardRuntime.favourites = favourites;
    keyword = KeywordSearchController(
      isLive: () => mounted,
      onCancelSubmitFocus: () => searchSubmitFocus.cancel(),
      onCompleteSubmitFocus: completeSearchSubmitFocus,
      onRestoreQuery: (q) => searchController.text = q,
    );
    cwNodes.onRequestRowFocus = (nodes, index) =>
        boardRuntime.requestRowFocus(nodes, index);
    cw = ContinueWatchingController(
      nodes: cwNodes,
      isLive: () => mounted,
      readMergedRows: readMergedRows,
      onMaybeAutoFocusBoard: presentation.maybeAutoFocusBoard,
      onRefreshBoundSources: refreshBoundSources,
      onSnack: actions.snack,
      onAnnounceTrakt: () => cwFlows.announceTrakt(),
      onAnnounceSimkl: () => cwFlows.announceSimkl(),
      onAnnounceMdblist: () => cwFlows.announceMdblist(),
    );
    boardRuntime.cw = cw;
    cw.actions = ContinueWatchingActions(
      imdbOf: imdbOf,
      addonForContinue: addonForContinue,
      openItem:
          (
            item,
            addon, {
            isTraktSource = false,
            isMdblistSource = false,
            initialSeason,
            initialEpisode,
          }) => actions.openItem(
            item,
            addon,
            isTraktSource: isTraktSource,
            isMdblistSource: isMdblistSource,
            initialSeason: initialSeason,
            initialEpisode: initialEpisode,
          ),
      onCatalogPlay:
          (
            item,
            addon, {
            isTraktSource = false,
            isMdblistSource = false,
            preferTraktResume = false,
          }) => actions.onCatalogPlay(
            item,
            addon,
            isTraktSource: isTraktSource,
            isMdblistSource: isMdblistSource,
            preferTraktResume: preferTraktResume,
          ),
      playSelection: actions.playSelection,
      popUntilNotDetail: () {
        Navigator.of(
          context,
        ).popUntil((route) => route.settings.name != kCatalogDetailRouteName);
      },
    );
    cwFlows = ContinueWatchingFlows(
      controller: cw,
      contextOf: () => context,
      wrap: presentation.wrapSeeAll,
      isBound: isBound,
      isTelevision: () => options.isTelevision,
      pikpakOnly: () => pikpakOnly,
      isLive: () => mounted,
      searchMode: () => options.searchMode,
      discoverMode: () => options.discoverMode,
      loading: () => loading,
      activeTvTabIndex: () => MainPageBridge.activeTvTabIndex,
      tabIndex: () => tabIndex,
      routeIsCurrent: () => ModalRoute.of(context)?.isCurrent ?? true,
      homeDisabled: () => board.homeDisabled,
      favNodeLists: () => [
        for (final kind in favourites.favRowKinds) favourites.favNodesFor(kind),
      ],
      catalogRowNodes: () => boardRuntime.rowNodes,
      showSnack: (msg) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            width: 420,
          ),
        );
      },
      onAfterSeeAllReturn: afterSeeAllReturn,
      refreshAfterPlayback: refreshAfterPlayback,
    );
    cw.bindings = ContinueWatchingBindings(
      openLocal: cw.openLocal,
      playLocal: cw.playLocal,
      removeLocal: (item) => cw.removeLocalCwItem(item, imdbOf: imdbOf),
      seeAllLocal: cwFlows.openLocalSeeAll,
      openTrakt: cw.openTrakt,
      playTrakt: cw.playTrakt,
      removeTrakt: cw.removeTraktCwItem,
      seeAllTrakt: cwFlows.openTraktSeeAll,
      openSimkl: cw.openSimkl,
      playSimkl: cw.playSimkl,
      removeSimkl: actions.removeSimklCwItem,
      seeAllSimkl: cwFlows.openSimklSeeAll,
      openMdblist: cw.openMdblist,
      playMdblist: cw.playMdblist,
      removeMdblist: (item) => cw.removeMdblistCwItem(item, imdbOf: imdbOf),
      canRemoveMdblist: (item) =>
          cw.canRemoveMdblistCwItem(item, imdbOf: imdbOf),
      seeAllMdblist: cwFlows.openMdblistSeeAll,
      openIptv: actions.openIptvCwItem,
      removeIptv: cw.removeIptvCwItem,
    );
    cw.addListener(onContinueWatchingChanged);
  }

  void applySections(List<CatalogSection> sections) {
    presentation.beforeApplySections();
    boardRuntime.pendingStageAdvanceKey = null;
    boardRuntime.pendingStageAdvanceAt = null;
    presentation.resetStageGeneration();
    boardRuntime.disposeNodes();
    for (final section in sections) {
      boardRuntime.rowNodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(
            debugLabel: 'search_r${boardRuntime.rowNodes.length}_c$i',
          ),
        ),
      );
    }
    surface.commit(() => boardRuntime.sections = sections);
    presentation.publishTopShelfSpotlight();
    unawaited(refreshBoundSources());
    presentation.seedHero(sections);
  }

  Future<FilteredPage> fetchBoardCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog, {
    required int skip,
    Set<String>? seenIds,
    int minItems = 12,
  }) => fetchFilteredPage(
    (s, onRaw) =>
        stremio.fetchCatalog(addon, catalog, skip: s, onRawCount: onRaw),
    skip: skip,
    hides: WatchedFilter.predicate,
    seenIds: seenIds,
    minItems: minItems,
  );

  void onBoardChanged() {
    boardRuntime.syncBoardRowNodes();
    if (mounted) surface.commit(() {});
  }

  void onCatalogSearchChanged() {
    if (mounted) surface.commit(() {});
  }

  void onContinueWatchingChanged() {
    if (mounted) surface.commit(() {});
  }

  String? imdbOf(StremioMeta item) => contentData.imdbOf(item);

  bool isBound(StremioMeta item) => contentData.isBound(item);

  int boundCountFor(StremioMeta item) => contentData.boundCountFor(item);

  Future<void> refreshBoundSources() async {
    // Cover every on-screen tile that renders a bound badge: catalog sections
    // AND the Continue Watching rows (whose titles may not appear in any
    // section, so editing their sources must still refresh the CW card badge).
    final items = [
      for (final section in boardRuntime.sections) ...section.items,
      ...cw.cwMovies,
      ...cw.cwSeries,
      ...cw.traktMovies,
      ...cw.traktSeries,
      ...cw.simklMovies,
      ...cw.simklSeries,
      ...cw.mdblistMovies,
      ...cw.mdblistSeries,
    ];
    final result = contentData.readBoundCounts(items);
    final counts = result is Future<Map<String, int>> ? await result : result;
    if (!mounted) return;
    surface.commit(
      () => contentData.boundCounts
        ..clear()
        ..addAll(counts),
    );
  }

  Future<void> refreshPikpakOnly() async {
    final pikpak = await ProviderCredentialPrefs.getPikPakEnabled();
    final rd = await StorageService.getApiKey();
    final tb = await StorageService.getTorboxApiKey();
    final pm = await StorageService.getPremiumizeApiKey();
    final ad = await StorageService.getAllDebridApiKey();
    final anyOther =
        (rd != null && rd.isNotEmpty) ||
        (tb != null && tb.isNotEmpty) ||
        (pm != null && pm.isNotEmpty) ||
        (ad != null && ad.isNotEmpty);
    final onlyPikpak = pikpak && !anyOther;
    if (mounted && onlyPikpak != pikpakOnly) {
      surface.commit(() => pikpakOnly = onlyPikpak);
    }
  }

  Future<void> refreshTraktAuthState() async {
    final auth = await TraktService.instance.isAuthenticated();
    if (!mounted || auth == isTraktAuthenticated) return;
    surface.commit(() => isTraktAuthenticated = auth);
  }

  Future<void> refreshSimklAuthState() async {
    final auth = await SimklService.instance.isAuthenticated();
    if (!mounted || auth == isSimklAuthenticated) return;
    surface.commit(() => isSimklAuthenticated = auth);
  }

  Future<void> refreshMdblistAuthState() async {
    final auth = await MdblistService.instance.isAuthenticated();
    if (!mounted || auth == isMdblistAuthenticated) return;
    final leaveLists = !auth && mode == SearchBoardMode.lists;
    if (leaveLists) {
      listsToken++;
      disposeListsNodes();
    }
    surface.commit(() {
      isMdblistAuthenticated = auth;
      if (leaveLists) {
        mode = SearchBoardMode.catalog;
        listsQuery = '';
        listsResults = const [];
        listsSearching = false;
        listsError = null;
      }
    });
    // A disconnect can remove the currently selected mode. Keep the shared
    // query useful by resolving it through Catalog after the selector falls
    // back, unless those exact Catalog results are already present.
    if (leaveLists) {
      final query = searchController.text.trim();
      if (query.isNotEmpty && query != catalogSearch.query) {
        runCatalogSearch(query);
      }
      if (options.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) searchFocusNode.requestFocus();
        });
      }
    }
  }

  Future<void> loadMergedSeriesFlag() async {
    final on = await StorageService.getMergedSeriesPageEnabled();
    if (mounted && on != mergedSeriesPage) {
      surface.commit(() => mergedSeriesPage = on);
    }
  }

  StremioAddon addonForContinue(String? addonId) {
    if (addonId != null && addonsById.containsKey(addonId)) {
      return addonsById[addonId]!;
    }
    // "Any homepage addon" means a REAL catalog addon — the Trakt/Simkl list
    // rows that now lead board.homeSections carry only a placeholder addon (empty
    // baseUrl), which can't serve /meta or /stream.
    for (final s in board.homeSections) {
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

  void completeSearchSubmitFocus(FocusNode target) {
    searchSubmitFocus.complete(
      field: searchFocusNode,
      isMounted: () => mounted,
      requestFocus: target.requestFocus,
      targetHasFocus: () => target.hasFocus,
    );
  }

  void disposeListsNodes() {
    for (final n in listsNodes) {
      n.dispose();
    }
    listsNodes.clear();
  }

  Future<void> runCatalogSearch(String query) async {
    await catalogSearch.run(query);
  }

  Future<void> primeDiscoverRows() async {
    await Future.wait([
      cw.loadContinueWatching(),
      cw.loadTraktContinueWatching(refreshBound: false),
      // Populates _simklAll/_simklProgress for the Simkl source's Continue
      // Watching list (folded into that source, like Trakt's).
      cw.loadSimklContinueWatching(refreshBound: false),
      cw.loadMdblistContinueWatching(refreshBound: false),
    ]);
    if (mounted) await refreshBoundSources();
  }

  Future<void> refreshAfterPlayback({bool trackers = false}) async {
    actions.resolver.clearSeriesResumeCache();
    // Consume the latch up front: a second refresh racing this one must not
    // repeat the tracker fetches this one is already doing.
    final withTrackers = trackers || playedSinceRefresh;
    playedSinceRefresh = false;
    try {
      await favourites.loadMyWatchlist();
      if (!mounted) return;
      await cw.reloadAfterPlayback(
        searchMode: options.searchMode,
        withTrackers: withTrackers,
      );
      if (!mounted) return;
      await refreshBoundSources();
    } catch (e) {
      debugPrint('SearchScreen: post-playback refresh failed: $e');
    }
  }

  void onPlaybackReturned() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    unawaited(refreshAfterPlayback());
  }

  void markPlaybackStarted() => playedSinceRefresh = true;

  Future<void> afterSeeAllReturn() => refreshAfterPlayback();
}
