import '../../features/discover/presentation/discover_session_lifecycle.dart';
import '../../features/home/models/home_board_configuration.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/home/presentation/home_return_section.dart';
import '../../features/search/presentation/search_page_shell.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/home_row_refresh.dart';
import '../../services/iptv_media_store.dart';
import '../../services/main_page_bridge.dart';
import '../../services/metadata_preferences_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/stremio_service.dart';
import '../../services/tmdb_title_search.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_search_focus_handoff.dart';
import 'dart:async';
import 'discover_composition.dart';
import 'discover_panel_composition.dart';
import 'home_board_presentation_composition.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_content_startup.dart';
import 'home_hero_composition.dart';
import 'home_item_composition.dart';
import 'home_leading_content_composition.dart';
import 'home_media_composition.dart';
import 'home_stage_composition.dart';
import 'home_view_bindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_presentation_composition.dart';
import 'search_profile_handoff.dart';
import 'search_screen_home_composition.dart';
import 'search_screen_search_composition.dart';
import 'search_screen_session_composition.dart';
import 'search_session_lifecycle.dart';
import '../../services/profiles/profile_scope.dart';
import '../../services/profiles/profile_session_memory.dart';

/// The widget configuration the screen composition reads.
abstract interface class SearchScreenConfig {
  bool get isTelevision;
  bool get searchMode;
  bool get discoverMode;
  TmdbTitleSearch? get titleSearch;
  Future<StremioMeta> Function(StremioMeta)? get suggestedTitleResolver;
}

/// What the composition borrows from the screen's State. The State stays the
/// binding observer, route-aware listener and hero identity.
typedef SearchScreenHost = ({
  SearchScreenConfig Function() widget,
  WidgetRef ref,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(VoidCallback) setState,
  WidgetsBindingObserver observer,
  RouteAware routeAware,
  int identity,
});

/// Builds and wires the screen's Home, Search and Discover owners in their
/// original order, starts them, and tears them down in their original order.
class SearchScreenComposer {
  SearchScreenComposer(
    this.host, {
    required this.titleSearchScope,
    required this.initialHomeConfiguration,
  });
  final SearchScreenHost host;
  final ProfileScope? titleSearchScope;
  final HomeBoardConfiguration initialHomeConfiguration;

  bool get mounted => host.mounted();
  BuildContext get context => host.context();
  void setState(VoidCallback fn) => host.setState(fn);
  SearchScreenConfig get widget => host.widget();
  WidgetRef get ref => host.ref;

  /// Whether the profile session this screen was built for is still active.
  bool profileCurrent() =>
      searchLifecycle.profileSessionOwner ==
      ProfileSessionMemory.captureOwner();

  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get tabIndex => widget.searchMode ? 17 : (widget.discoverMode ? 18 : 15);

  final StremioService stremio = StremioService.instance;

  final TextEditingController searchController = TextEditingController();
  // Ownership is decided when the instance is resolved: a title search passed
  // in by the caller is borrowed and must survive this screen.
  bool _ownsTitleSearch = false;
  late final TmdbTitleSearch titleSearch =
      widget.titleSearch ??
      (() {
        _ownsTitleSearch = true;
        return TmdbTitleSearch();
      })();
  final TvSearchFocusHandoff searchSubmitFocus = TvSearchFocusHandoff();

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [board.workflow.boardConfiguration.reloadForHomeSettings] when the manager saves.
  // Bootstrap is captured at state construction, matching the previous field
  // initialization. All accepted changes live in the controller afterwards.
  late final HomeViewBindings homeView;
  late final HomeContentStartup contentStartup;
  late final HomeBoardPresentation board;
  late final HomeLeadingContent leading;
  late final HomeCatalogPresentation catalogPresentation;
  late final SearchSessionLifecycle searchLifecycle;
  late final SearchProfileHandoff profileHandoff;
  late final HomeReturnSection homeReturn;
  late final HomeItemComposition homeActions;
  late final HomeMediaComposition mediaComposition;
  late final HomeHeroComposition hero;

  late final DiscoverComposition discover;
  late final SearchPresentation search;
  late final DiscoverPanelComposition discoverPanels;
  late final DiscoverSessionLifecycle discoverLifecycle;

  /// The former `initState` body after `super.initState()`.
  void initialize() {
    composeSearchScreenSearch(this);
    composeSearchScreenHome(this);
    composeSearchScreenSession(this);
    final keywordSnapshot = searchLifecycle.initializeKeyword();
    homeView.initialize(keywordSnapshot);
    // This one widget backs three tabs (Home board / dedicated Search / Discover).
    AnalyticsService.screenView(
      widget.searchMode
          ? 'search'
          : widget.discoverMode
          ? 'discover'
          : 'home',
    );
    catalogPresentation.tabShell.start();
    discoverLifecycle.initialize();
    hero.heroShell.start(host.routeAware);
    // Discover on TV: relay the trailer takeover to the sidebar chrome-dim so
    // the rail hides when the trailer goes fullscreen. The showing listener
    // arms the theater timer (deep lights-off a few seconds into playback).
    if (widget.discoverMode) {
      discover.section.startShell();
    }
    HomeHeroShellBridge.startContentSignals(
      isTelevisionSearch: () => widget.isTelevision && widget.searchMode,
      integration: catalogPresentation.integrations,
      returning: leading.continuation.returning,
      display: hero.displaySection,
    );
    // Restore a keyword search preserved from a prior tab visit (results +
    // scroll) BEFORE the async default-view load below can start: restoration
    // sets keyword mode synchronously, and a later-resolving catalog default
    // would flip the mode back and could fire a catalog search with the
    // restored keyword text. A successful restore therefore also suppresses
    // the default-view load outright.
    final restoredKeyword = search.returning.restore(keywordSnapshot);
    // Home board only: live-refresh when the Home Rows manager changes which
    // rows are hidden. The bridge also invalidates a saved return snapshot.
    if (!widget.searchMode && !widget.discoverMode) {
      board.workflow.boardConfiguration.observeChanges(
        addHomeSettings: MainPageBridge.addHomeSettingsListener,
        addRows: HomeRowRefreshSignal.addListener,
        addAddons: stremio.addAddonsChangedListener,
        iptvRevision: () => IptvMediaStore.listsRevision,
        restoredKeyword: restoredKeyword,
      );
      HomeHeroShellBridge.startHomeLayout(
        isTelevision: () => widget.isTelevision,
        restoredKeyword: restoredKeyword,
        display: hero.displaySection,
        preview: hero.heroPreview,
        stage: board.stages.stageSection,
        closeSearchSheet: hero.spotlightShell.searchSheet.close,
        restoreSearchSheet: hero.spotlightShell.searchSheet.restore,
      );
    }
    hero.spotlightShell.observeSearchFocus();
    board.workflow.boardSection.boardScroll.addListener(
      board.workflow.boardPaging.onBoardScroll,
    );
    search.keyword.keywordSection.keywordViewport.observeScroll();
    contentStartup.start(restoredKeyword: restoredKeyword);
  }

  /// The former `dispose` body before `super.dispose()`.
  void dispose() {
    homeReturn.preserveHomeSnapshot();
    board.workflow.boardSection.homePublication.dispose();
    MetadataPreferencesService.revision.removeListener(
      catalogPresentation.metadata.metadataSettingsChanged,
    );
    board.workflow.boardFocus.catalogFocus.dispose();
    WidgetsBinding.instance.removeObserver(host.observer);
    leading.content.section.mdblistContinuationController
        .cancelRevisionRefresh();
    hero.spotlightSection.spotlightHeroNode.dispose();
    search.returning.preserve();
    catalogPresentation.tabShell.dispose();
    HomeHeroShellBridge.disposeContentSignals(
      offTvHome: () =>
          !widget.isTelevision && !widget.searchMode && !widget.discoverMode,
      closeSearchSheet: hero.spotlightShell.searchSheet.close,
      searchSheetFocusChanged: hero.spotlightShell.searchSheet.onFocusChanged,
      searchField: () => search.input.inputSection.searchFocusNode,
      preview: hero.heroPreview,
      reclaimFocus: board.workflow.boardFocus.onGlobalFocusChange,
      integration: catalogPresentation.integrations,
      returning: leading.continuation.returning,
      configuration: board.workflow.boardConfiguration,
      display: hero.displaySection,
    );
    board.workflow.boardConfiguration.stopObservingChanges(
      removeRows: HomeRowRefreshSignal.removeListener,
      removeAddons: stremio.removeAddonsChangedListener,
      iptvRevision: () => IptvMediaStore.listsRevision,
    );
    leading.saved.section.iptvListFocus.dispose();
    HomeHeroShellBridge.disposeHomeLayout(
      isTelevisionHome: () =>
          widget.isTelevision && !widget.searchMode && !widget.discoverMode,
      display: hero.displaySection,
      preview: hero.heroPreview,
      stage: board.stages.stageSection,
    );
    disposeHomeStageResources(board.stages);
    hero.heroShell.dispose();
    disposeHomeHeroMedia(hero, homeView.homeMediaBindings);
    searchController.dispose();
    ProfileRuntime.scope.removeListener(profileHandoff.onSearchProfileChanged);
    discoverLifecycle.bindings.close();
    catalogPresentation.metadata.metadataFeatureSubscription.close();
    homeView.closePresentationBindings();
    searchLifecycle.searchResultBindings.closeCatalogAndLists();
    search.keyword.keywordSection.closeAppearance();
    searchLifecycle.searchResultBindings.closeKeyword();
    titleSearch.removeListener(search.modes.title.publishTitleSuggestions);
    if (_ownsTitleSearch) titleSearch.dispose();
    search.modes.title.presentation.dispose();
    search.input.inputSection.disposeFocus();
    search.modes.lists.disposeListsNodes();
    discover.section.dispose();
    board.workflow.boardSection.boardViewport.disposeScroll();
    search.keyword.keywordSection.keywordViewport.dispose();
    search.keyword.keywordSection.keywordFocus.dispose();
    search.modes.catalog.catalogSourcesBtnFocus.dispose();

    board.workflow.boardSection.boardViewport.disposeNodes();
    disposeHomeLeadingFocus(leading);
  }

  /// The former `didChangeDependencies` body after the super call.
  void didChangeDependencies() {
    if (PlatformUtil.isAndroidTvCached) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        board.workflow.boardPublication.resumeHomeProgress();
      } else {
        board.workflow.boardDeferred.clearDeferredDown();
        board.stages.stageSection.stageDeferredAdvance.reset();
      }
    }
    hero.heroShell.bindRoute(context);
  }

  void didPushNext() => hero.heroShell.didPushNext();

  void didPopNext() {
    // A board reload UNDER a detail page/player can dispose the focused node;
    // the reclaim listener fires while covered and bails on route.isCurrent,
    // and no focus event re-fires it on the way back — re-run the dead check
    // now that the board is the top route again.
    board.workflow.boardFocus.onGlobalFocusChange();
    if (!hero.heroPreview.heroTrailerActive ||
        !hero.heroPreview.heroTrailerEnabled) {
      return;
    }
    final item = hero.heroSection.heroItem.value;
    if (item != null) hero.heroPreview.scheduleHeroTrailer(item);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  void didChangeAppLifecycleState(AppLifecycleState state) =>
      leading.continuation.returning.didChangeAppLifecycleState(state);

  Widget build(BuildContext context) => buildSearchPageShell(
    context: context,
    glassHome: hero.heroPreview.heroTrailerActive,
    discoverMode: widget.discoverMode,
    isTelevision: widget.isTelevision,
    dedicatedSearch: widget.searchMode,
    spotlightActive: () => hero.spotlightShell.spotlightShellActive,
    discover: discover.section.buildDiscover,
    board: board.rendering.rendering.buildBoard,
    spotlight: hero.spotlightShell.buildSpotlightShell,
    header: search.input.inputSection.buildHeader,
    sourcesBar: search.input.inputSection.buildUnifiedCatalogSourcesBar,
    body: search.input.inputSection.buildBody,
  );
}
