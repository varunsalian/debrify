import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../search/search_screen_shells.dart';
import '../search/continue_watching_controller.dart';
import '../search/hero_presenter.dart';
import '../search/discover_lifecycle.dart';
import '../search/discover_view.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import '../../services/storage_service.dart';
import '../../services/app_route_observer.dart';
import '../see_all/catalog_see_all_screen.dart';
import '../see_all/continue_watching_see_all_screen.dart';
import '../see_all/trakt_see_all_screen.dart';
import '../see_all/simkl_see_all_screen.dart';
import '../see_all/mdblist_see_all_screen.dart';
import '../../services/mdblist/mdblist_list_source.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import 'search_content_session.dart';
import '../search_screen.dart'
    show discoverLandingLoadIsCurrent, SearchBoardMode;

/// Standalone Discover composition. Home/Search shares the content session,
/// without constructing its legacy State on this route.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({
    super.key,
    this.isTelevision = false,
    this.host,
    this.readCwMergedRows = HomePrefs.getHomeCwMergedRows,
  });
  final bool isTelevision;
  final Widget? host;
  final Future<bool> Function(String) readCwMergedRows;
  bool get searchMode => false;
  bool get discoverMode => true;
  int get tabIndex =>
      searchScreenTabIndex(searchMode: false, discoverMode: true);
  String get variantKey =>
      searchScreenVariantKey(searchMode: false, discoverMode: true);
  String get analyticsName =>
      searchScreenAnalyticsName(searchMode: false, discoverMode: true);
  List<String> get sharedControllers => kSearchScreenSharedControllerNames;
  @override
  Widget build(BuildContext context) =>
      host ??
      _DiscoverComposition(
        isTelevision: isTelevision,
        readCwMergedRows: readCwMergedRows,
      );
}

class _DiscoverComposition extends StatefulWidget {
  const _DiscoverComposition({
    required this.isTelevision,
    required this.readCwMergedRows,
  });
  final bool isTelevision;
  final Future<bool> Function(String) readCwMergedRows;
  bool get searchMode => false;
  bool get discoverMode => true;
  int get tabIndex =>
      searchScreenTabIndex(searchMode: false, discoverMode: true);
  String get variantKey =>
      searchScreenVariantKey(searchMode: false, discoverMode: true);
  String get analyticsName =>
      searchScreenAnalyticsName(searchMode: false, discoverMode: true);
  @override
  State<_DiscoverComposition> createState() => _DiscoverScreenState();
}

const _discCw = kDiscoverSourceCw;
const _discTrakt = kDiscoverSourceTrakt;
const _discSimkl = kDiscoverSourceSimkl;
const _discMdblist = kDiscoverSourceMdblist;
const _discAddonPrefix = kDiscoverSourceAddonPrefix;

class _DiscoverScreenState extends State<_DiscoverComposition>
    with RouteAware, WidgetsBindingObserver
    implements SearchContentSurface, SearchContentPresentation {
  final SearchContentSession _content = SearchContentSession();
  final DiscoverLifecycle _discover = DiscoverLifecycle();
  String _discSource = _discCw;
  int _discSourceRevision = 0;
  List<StremioAddon> _discAddons = const [];
  MdblistListChoice? _discMdblistList;
  FocusNode get _discSourceNode => _discover.sourceNode;
  ValueNotifier<StremioMeta?> get _discFocused => _discover.focused;
  ValueNotifier<StremioMeta?> get _discShown => _discover.shown;
  void _onDiscFocused(StremioMeta item) => _discover.onFocused(item);
  late final ProfileSessionOwner _profileSessionOwner;
  bool _catalogSourcesBarShown = false;
  Timer? _catalogSourcesHideTimer;
  ({int generation, DateTime appliedAt}) _sectionCommit = (
    generation: 0,
    appliedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
  int _stageGeneration = 0;
  // Discover has no favourite hero tile. Keep the existing clear capability
  // and its notifier lifetime without importing a private Home stage model.
  final ValueNotifier<Never?> _favouriteHeroFocus = ValueNotifier(null);
  late final HeroPresenter _hero = HeroPresenter(
    environment: () => HeroEnvironment(
      isTelevision: widget.isTelevision,
      searchMode: false,
      discoverMode: true,
      catalogQuery: _content.catalogSearch.query,
      // The original Discover home-style guard resolves to classic.
      stageActive: false,
      stagePublishesShellArt: false,
      stageWantsAmbient: false,
      homeStyle: 'classic',
      hasFavouriteFocus: _favouriteHeroFocus.value != null,
    ),
    isMounted: () => mounted,
    hostContext: () => context,
    updateHost: (change) => setState(change),
    clearFavouriteFocus: () => _favouriteHeroFocus.value = null,
    // Discover never mounts a Spotlight widget.
    showingHeroId: () => null,
  );

  @override
  void commit(VoidCallback change) => setState(change);
  @override
  void beforeApplySections() {
    _sectionCommit = (
      generation: _sectionCommit.generation + 1,
      appliedAt: DateTime.now(),
    );
  }

  @override
  void resetStageGeneration() => _stageGeneration++;
  @override
  void seedHero(List<CatalogSection> sections) => _hero.seedSections(sections);
  @override
  void publishTopShelfSpotlight() {
    // Preserve the original Discover guard before any spotlight lookup/IO.
    if (!PlatformUtil.isTvOS || widget.searchMode || widget.discoverMode) {
      return;
    }
  }

  @override
  void maybeAutoFocusBoard() {
    // User-requested deferred Down precedes the original variant return.
    _content.boardRuntime.maybeCompleteDeferredDown();
    if (!widget.isTelevision) return;
    if (widget.searchMode || widget.discoverMode) return;
  }

  @override
  void focusContent() => _discSourceNode.requestFocus();
  @override
  Widget wrapSeeAll(Widget child) {
    // The original Home-expanded wrapper exits before consulting preferences.
    if (widget.searchMode || widget.discoverMode) return child;
    return child;
  }

  void _leaveBoardTop() {
    if (widget.searchMode) _content.searchFocusNode.requestFocus();
  }

  void _onDiscoverPreferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _content.surface = this;
    _content.presentation = this;
    _content.readOptions = () => (
      isTelevision: widget.isTelevision,
      searchMode: false,
      discoverMode: true,
    );
    _content.boardRuntime.leaveBoardTop = _leaveBoardTop;
    // No pending stage request is created by Discover. Runtime completion
    // returns on its real null-pending guard, before reading stage callbacks.
    _content.initialize(readMergedRows: widget.readCwMergedRows);
    WidgetsBinding.instance.addObserver(this);
    _profileSessionOwner = ProfileSessionMemory.captureOwner();
    AnalyticsService.screenView(widget.analyticsName);
    MainPageBridge.registerTvContentFocusHandler(
      widget.tabIndex,
      focusContent,
    );
    final pending = MainPageBridge.pendingMdblistListOpen;
    if (pending != null) {
      MainPageBridge.pendingMdblistListOpen = null;
      _discMdblistList = MdblistListChoice(
        id: (pending['id'] as num?)?.toInt() ?? -1,
        name: pending['name'] as String? ?? 'Untitled list',
        ownerName: pending['ownerName'] as String?,
        itemCount: (pending['itemCount'] as num?)?.toInt() ?? 0,
        liked: pending['liked'] == true,
        likes: (pending['likes'] as num?)?.toInt() ?? 0,
      );
      _discSource = _discMdblist;
      unawaited(StorageService.setDiscoverLastSource(_discMdblist));
    }
    _hero.registerTv();
    _discover.addListener(_onDiscoverPreferencesChanged);
    _discover.start(isTelevision: widget.isTelevision);
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    MainPageBridge.addPlaybackReturnListener(_content.onPlaybackReturned);
    MainPageBridge.addPlayerLaunchListener(_content.markPlaybackStarted);
    if (!widget.isTelevision) {
      _content.searchFocusNode.addListener(_onSearchFocusForSources);
    }
    _content.boardRuntime.boardScroll.addListener(
      _content.boardRuntime.onBoardScroll,
    );
    _content.refreshTraktAuthState();
    _content.refreshSimklAuthState();
    _content.refreshMdblistAuthState();
    _content.loadMergedSeriesFlag();
    unawaited(_content.keyword.loadDefaultFilters());
    _content.loading = false;
    _content.refreshPikpakOnly();
    _loadDiscoverAddons();
    _content.primeDiscoverRows();
  }

  void _onIntegrationsChanged() {
    _content.refreshTraktAuthState();
    _content.refreshSimklAuthState();
    _content.refreshMdblistAuthState();
    _content.refreshPikpakOnly();
    // Original Discover skips local CW and board reload, but keeps trackers.
    _content.cw.loadTraktContinueWatching();
    _content.cw.loadSimklContinueWatching();
    _content.cw.loadMdblistContinueWatching();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (!_content.cw.maybeRefreshTraktOnResume(
      searchMode: false,
      isTraktAuthenticated: _content.isTraktAuthenticated,
      playedSinceRefresh: _content.playedSinceRefresh,
      routeIsCurrent: ModalRoute.of(context)?.isCurrent ?? false,
    )) {
      return;
    }
    unawaited(_content.cw.loadTraktContinueWatching());
  }

  @override
  void dispose() {
    _content.board.removeListener(_content.onBoardChanged);
    _content.board.dispose();
    _content.catalogSearch.removeListener(_content.onCatalogSearchChanged);
    _content.catalogSearch.dispose();
    _content.keyword.preserve(
      _profileSessionOwner,
      widget.variantKey,
      modeIsKeyword: _content.mode == SearchBoardMode.keyword,
    );
    _content.keyword.dispose();
    _content.cw.removeListener(_content.onContinueWatchingChanged);
    _content.cw.dispose();
    WidgetsBinding.instance.removeObserver(this);
    MainPageBridge.unregisterTvContentFocusHandler(
      widget.tabIndex,
      focusContent,
    );
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    MainPageBridge.removePlaybackReturnListener(_content.onPlaybackReturned);
    MainPageBridge.removePlayerLaunchListener(_content.markPlaybackStarted);
    for (final row in _content.favourites.iptvListRows) {
      for (final n in row.nodes) {
        n.dispose();
      }
      row.nodes.clear();
    }
    _favouriteHeroFocus.dispose();
    // trailerActive excludes Discover, so detach never subscribes/unsubscribes
    // a route. Other HeroPresenter cleanup still executes in the same slot.
    _hero.detachShell(unsubscribeRoute: _unsubscribeRoute);
    _hero.dispose();
    _content.searchController.dispose();
    _catalogSourcesHideTimer?.cancel();
    _content.searchFocusNode.removeListener(_onSearchFocusForSources);
    _content.searchFocusNode.dispose();
    _content.disposeListsNodes();
    _discover.removeListener(_onDiscoverPreferencesChanged);
    _discover.dispose(isTelevision: widget.isTelevision);
    _content.boardRuntime.boardScroll.dispose();
    _content.boardRuntime.disposeNodes();
    for (final n in [
      ..._content.favourites.tvFavNodes,
      ..._content.favourites.stvFavNodes,
      ..._content.favourites.iptvFavNodes,
      ..._content.favourites.watchlistMovieNodes,
      ..._content.favourites.watchlistSeriesNodes,
      ..._content.favourites.playlistFavNodes,
    ]) {
      n.dispose();
    }
    _content.favourites.tvFavNodes.clear();
    _content.favourites.stvFavNodes.clear();
    _content.favourites.iptvFavNodes.clear();
    _content.favourites.watchlistMovieNodes.clear();
    _content.favourites.watchlistSeriesNodes.clear();
    _content.favourites.playlistFavNodes.clear();
    super.dispose();
  }

  void _unsubscribeRoute() {
    appRouteObserver.unsubscribe(this);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.home.bg,
      body: Container(
        decoration: BoxDecoration(gradient: app.home.wash),
        child: SafeArea(
          child: DiscoverView(
            isTelevision: widget.isTelevision,
            lifecycle: _discover,
            panel: _buildDiscoverPanel(),
          ),
        ),
      ),
    );
  }

  Future<void> _loadDiscoverAddons() async {
    final revision = _discSourceRevision;
    final values = await Future.wait([
      StorageService.getDiscoverDefaultSource(),
      StorageService.getDiscoverLastSource(),
    ]);
    if (!mounted) return;
    final defaultSource = values[0];
    final lastSource = values[1];
    var landing = defaultSource == StorageService.discoverDefaultRememberLast
        ? lastSource
        : defaultSource;
    final fixedSource =
        landing == _discCw ||
        landing == _discTrakt ||
        landing == _discSimkl ||
        (kMdblistEnabled && landing == _discMdblist);

    // Search→MDBList handoff is a stronger, explicit navigation intent. For
    // ordinary fixed defaults, paint now instead of waiting on manifests.
    if (fixedSource &&
        discoverLandingLoadIsCurrent(
          capturedRevision: revision,
          currentRevision: _discSourceRevision,
          hasPendingHandoff: _discMdblistList != null,
        )) {
      if (_discSource != landing) setState(() => _discSource = landing);
      unawaited(StorageService.setDiscoverLastSource(landing));
    }

    List<StremioAddon> addons = const [];
    try {
      addons = await _content.stremio.getCatalogAddons();
    } catch (_) {}
    if (!mounted) return;
    final browsable = [
      for (final a in addons)
        if (a.catalogs.any((c) => c.isBrowsable)) a,
    ];
    landing = resolveDiscoverLandingSource(
      defaultSource: defaultSource,
      lastSource: lastSource,
      mdblistEnabled: kMdblistEnabled,
      browsableAddonIds: browsable.map((a) => a.id),
    );
    setState(() {
      _discAddons = browsable;
      for (final a in addons) {
        _content.addonsById.putIfAbsent(a.id, () => a);
      }
      if (!fixedSource &&
          discoverLandingLoadIsCurrent(
            capturedRevision: revision,
            currentRevision: _discSourceRevision,
            hasPendingHandoff: _discMdblistList != null,
          )) {
        _discSource = landing;
      }
    });
    if (!fixedSource &&
        discoverLandingLoadIsCurrent(
          capturedRevision: revision,
          currentRevision: _discSourceRevision,
          hasPendingHandoff: _discMdblistList != null,
        )) {
      unawaited(StorageService.setDiscoverLastSource(landing));
    }
  }

  Widget _buildDiscoverPanel() {
    final source = StremioDropdown<String>(
      label: 'Source',
      value: _discSource,
      isTelevision: widget.isTelevision,
      // TV: a quiet violet segment leading the filter line — the row's identity
      // color (chrome accent), distinct from the white filter values.
      quiet: widget.isTelevision,
      quietAccent: true,
      focusNode: _discSourceNode,
      options: [
        for (final o in discoverSourceDropdownOptions(
          mdblistEnabled: kMdblistEnabled,
          mdblistAuthenticated: _content.isMdblistAuthenticated,
          currentSource: _discSource,
          addons: [for (final a in _discAddons) (id: a.id, name: a.name)],
        ))
          StremioDropdownOption(o.value, o.label),
      ],
      onSelected: (s) {
        if (s == _discSource) return;
        // Swapping source re-mounts the grid and drops DPAD focus back onto the
        // Source dropdown — clear the rail (and the stage backdrop behind it)
        // so they show the prompt/ink, not a stale title from the previous
        // source, until a new tile is focused.
        _discFocused.value = null;
        _discShown.value = null;
        setState(() {
          _discSourceRevision++;
          _discSource = s;
        });
        unawaited(StorageService.setDiscoverLastSource(s));
        // The swap re-mounts the embedded panel (new ValueKey), which re-attaches
        // this shared node; pin the DPAD ring back on the Source dropdown so it
        // isn't lost in the dispose/reattach.
        if (widget.isTelevision) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _discSourceNode.requestFocus();
          });
        }
      },
    );

    if (_discSource == _discTrakt) {
      return TraktSeeAllScreen(
        key: const ValueKey('disc_trakt'),
        cwItems: _content.cw.traktAll,
        cwProgress: _content.cw.cwCardMaps(CwKind.trakt).progress,
        onOpen: _content.cw.openTrakt,
        onQuickPlay: _content.pikpakOnly ? null : _content.cw.playTrakt,
        onItemFocused: _onDiscFocused,
        isBound: _content.isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    if (_discSource == _discSimkl) {
      return SimklSeeAllScreen(
        key: const ValueKey('disc_simkl'),
        // CW is folded in as the leading "List" option (like the Trakt source).
        // Plain open/play for the browse lists; the CW-aware handlers (resume at
        // the paused/up-next episode) apply ONLY while the CW list is showing.
        cwItems: _content.cw.simklAll,
        cwProgress: _content.cw.simklProgress,
        onOpen: _content.actions.openSimklItem,
        onQuickPlay: _content.pikpakOnly
            ? null
            : _content.actions.playSimklItem,
        cwOnOpen: _content.cw.openSimkl,
        cwOnQuickPlay: _content.pikpakOnly ? null : _content.cw.playSimkl,
        onItemFocused: _onDiscFocused,
        isBound: _content.isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    if (_discSource == _discMdblist) {
      // MDBList items are plain catalog titles (StremioMeta w/ imdb id), so they
      // open and quick-play through the same generic catalog paths as an addon
      // catalog item — no MDBList-specific handlers needed.
      return MdblistSeeAllScreen(
        key: const ValueKey('disc_mdblist'),
        initialList: _discMdblistList,
        onOpen: (item) => _content.actions.openItem(
          item,
          _content.addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        ),
        onQuickPlay: _content.pikpakOnly
            ? null
            : (item) => _content.actions.onCatalogPlay(
                item,
                _content.addonForContinue(item.sourceAddon?.id),
                isMdblistSource: true,
              ),
        onItemFocused: _onDiscFocused,
        isBound: _content.isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    // An installed addon catalog source.
    if (_discSource.startsWith(_discAddonPrefix)) {
      final addon =
          _content.addonsById[_discSource.substring(_discAddonPrefix.length)];
      final catalog = addon?.catalogs.cast<StremioAddonCatalog?>().firstWhere(
        (c) => c != null && c.isBrowsable,
        orElse: () => null,
      );
      if (addon != null && catalog != null) {
        return CatalogSeeAllScreen(
          key: ValueKey('disc_${addon.id}'),
          addon: addon,
          initialCatalog: catalog,
          isTelevision: widget.isTelevision,
          onOpenItem: (item) => _content.actions.openItem(item, addon),
          onQuickPlay: _content.pikpakOnly
              ? null
              : (item) => _content.actions.onCatalogPlay(item, addon),
          onItemFocused: _onDiscFocused,
          embedded: true,
          leading: source,
          leadingNode: _discSourceNode,
        );
      }
      // Addon vanished (uninstalled) — fall through to Continue Watching.
    }

    // Default: Continue Watching.
    return ContinueWatchingSeeAllScreen(
      key: const ValueKey('disc_cw'),
      title: 'Continue Watching',
      items: _content.cw.cwAll,
      progressOf: (m) => _content.cw.cwCardProgress(CwKind.local, m),
      onOpen: _content.cw.openLocal,
      onQuickPlay: _content.pikpakOnly ? null : _content.cw.playLocal,
      onItemFocused: _onDiscFocused,
      isBound: _content.isBound,
      isTelevision: widget.isTelevision,
      embedded: true,
      leading: source,
      leadingNode: _discSourceNode,
      // Re-fetch when a detail/player route pops back so finished titles drop out
      // (the quick-play path doesn't reload _content.cw.cwAll on its own).
      onReload: () async {
        await _content.cw.loadContinueWatching();
        if (!mounted) return const <StremioMeta>[];
        return List<StremioMeta>.of(_content.cw.cwAll);
      },
    );
  }

  void _onSearchFocusForSources() {
    if (_content.searchFocusNode.hasFocus) {
      _catalogSourcesHideTimer?.cancel();
      if (!_catalogSourcesBarShown) {
        setState(() => _catalogSourcesBarShown = true);
      }
    } else {
      _catalogSourcesHideTimer?.cancel();
      _catalogSourcesHideTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && _catalogSourcesBarShown) {
          setState(() => _catalogSourcesBarShown = false);
        }
      });
    }
  }
}
