import 'package:debrify/services/storage/detail_navigation_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import '../../features/home/application/home_board_providers.dart';
import '../../features/home/application/home_continuation_providers.dart';
import '../../features/home/application/home_detail_providers.dart';
import '../../features/home/presentation/home_detail_actions.dart';
import '../../features/home/presentation/home_return_section.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/home_list_rows.dart';
import '../../services/iptv_cw_router.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_menu_helpers.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/native_series_metadata_service.dart';
import '../../services/playlist_player_service.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/profiles/profile_session_memory.dart';
import '../../services/simkl/simkl_menu_helpers.dart';
import '../../services/tvos_top_shelf_service.dart';
import '../../services/video_player_launcher.dart';
import 'home_board_presentation_composition.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_hero_composition.dart';
import 'home_item_composition.dart';
import 'home_leading_content_composition.dart';
import 'search_screen_composer.dart';

/// Constructs the screen's Home actions, content, hero, board, return and catalog owners, in their original order.
void composeSearchScreenHome(SearchScreenComposer c) {
  c.homeActions = createHomeItemActions(
    c.ref,
    (
      mounted: () => c.mounted,
      profileCurrent: c.profileCurrent,
      context: () => c.context,
      isTelevision: () => c.widget.isTelevision,
      view: () => c.homeView,
      badges: () => c.catalogPresentation.badges,
      returning: () => c.leading.continuation.returning,
      integrations: () => c.catalogPresentation.integrations,
      continuation: () => c.leading.content,
      navigation: () => c.catalogPresentation.navigation,
      removal: () => c.leading.removal,
    ),
    createDetails: (playback, catalog, sources) => HomeDetailActions(
      c.ref,
      (
        context: () => c.context,
        session: () => c.homeView.homeCatalogSession,
        bridge: (route) => c.leading.continuation.returning.detailBridge(
          canStart: () => playback.catalogNavigationCurrent() && route.isActive,
          isCurrent: playback.catalogNavigationCurrent,
        ),
        removeLocal: (action, id, route) =>
            c.leading.removal.handleContinueDetailAction(action, id, route),
        removeTrakt: (id, {detailRoute}) => c.leading.removal
            .removeFromTraktContinueWatching(id, detailRoute: detailRoute),
        removeMdblist: (item) => c.leading.removal.removeMdblistCwItem(item),
        invokeSimkl: (item, action, detailRoute, presetRating) =>
            handleSimklMenuAction(
              c.context,
              item,
              action,
              actions: c.ref.read(
                homeDetailActionsProvider(
                  c.searchLifecycle.profileSessionOwner,
                ),
              ),
              presetRating: presetRating,
              isCurrent: playback.catalogNavigationCurrent,
              removeContinueWatching: () => c.ref
                  .read(
                    homeSimklHistoryRemovalProvider(
                      c.searchLifecycle.profileSessionOwner,
                    ),
                  )
                  .remove(
                    item.progressId ?? item.id,
                    item.type,
                    isCurrent: playback.catalogNavigationCurrent,
                  ),
            ),
        invokeMdblist: (item, action, detailRoute, presetRating) =>
            handleMdblistMenuAction(
              c.context,
              item,
              action,
              actions: c.ref.read(
                homeDetailActionsProvider(
                  c.searchLifecycle.profileSessionOwner,
                ),
              ),
              presetRating: presetRating,
              isCurrent: playback.catalogNavigationCurrent,
            ),
      ),
      playback,
      catalog,
      sources,
    ),
  );
  c.leading = createHomeLeadingContent(
    c.ref,
    (
      mounted: () => c.mounted,
      setState: c.setState,
      context: () => c.context,
      isTelevision: () => c.widget.isTelevision,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      view: () => c.homeView,
      board: () => c.board,
      catalog: () => c.catalogPresentation,
      hero: () => c.hero,
      allowed: ProfilePolicyGuard.allowsSync,
      profileCurrent: c.profileCurrent,
      tabIndex: () => c.tabIndex,
      mdblistEnabled: kMdblistEnabled,
    ),
    search: c.search,
    actions: c.homeActions,
    playPlaylist: PlaylistPlayerService.play,
    removeWatchlist: (item) => WatchlistStorage.setMyWatchlistItem(item, false),
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
      c.context,
      item,
      SimklItemMenuAction.removeFromContinueWatching,
      isCurrent: c.homeActions.playback.catalogNavigationCurrent,
      removeContinueWatching: () => c.ref
          .read(
            homeSimklHistoryRemovalProvider(
              c.searchLifecycle.profileSessionOwner,
            ),
          )
          .remove(
            item.progressId ?? item.id,
            item.type,
            isCurrent: c.homeActions.playback.catalogNavigationCurrent,
          ),
    ),
  );
  c.hero = createHomeHero(
    (
      mounted: () => c.mounted,
      setState: c.setState,
      context: () => c.context,
      isTelevision: () => c.widget.isTelevision,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      media: () => c.homeView.homeMediaBindings,
      resetStageNavigation: () =>
          c.board.stages.stageSection.resetStageNavigation(),
      favorites: () => c.board.stages.stageFavorites,
      board: () => c.board.workflow,
      repository: () => c.ref.read(homeCatalogRepositoryProvider),
      publishTopShelf: (items, {sourceTitle}) => TvosTopShelfService.instance
          .publishSpotlight(items, sourceTitle: sourceTitle),
    ),
    search: c.search.modes,
    input: c.search.input.inputSection,
    searchController: c.searchController,
    ambientArt: MainPageBridge.tvAmbientArt,
    heroTint: MainPageBridge.tvHeroTint,
    chromeDim: MainPageBridge.tvChromeDim,
    lightsOff: MainPageBridge.tvStageLightsOff,
  );
  c.board = createHomeBoardPresentation(
    c.ref,
    (
      mounted: () => c.mounted,
      setState: c.setState,
      context: () => c.context,
      isTelevision: () => c.widget.isTelevision,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      bindings: () => c.homeView.homeBoardBindings,
      scope: () => ProfileRuntime.scope.value,
      catalog: () => c.catalogPresentation,
      media: () => c.mediaComposition,
      tabIndex: () => c.tabIndex,
      profileCurrent: c.profileCurrent,
      heroIdentity: () => c.host.identity,
    ),
    hero: c.hero,
    spotlight: c.hero.spotlightSection,
    input: c.search.input.inputSection,
    discover: c.discover.section,
    search: c.search.modes,
    keyword: c.search.keyword.keywordSection,
    continuation: c.leading.content,
    continuationView: c.leading.continuation,
    saved: c.leading.saved,
    actions: c.homeActions,
    ambientArt: MainPageBridge.tvAmbientArt,
    heroTint: MainPageBridge.tvHeroTint,
    ready: () => MainPageBridge.homeBoardReady,
  );
  c.homeReturn = HomeReturnSection(
    c.ref,
    (
      mounted: () => c.mounted,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      owner: () => c.searchLifecycle.profileSessionOwner,
      currentOwner: ProfileSessionMemory.captureOwner,
      scope: () => ProfileRuntime.scope.value,
      refreshPikpakOnly: () => c.catalogPresentation.badges.refreshPikpakOnly(),
    ),
    c.board.workflow.boardSection,
    c.board.workflow.boardRows,
    c.board.workflow.boardFocus,
    c.board.workflow.boardPaging,
    c.board.workflow.boardPublication,
    c.board.workflow.boardConfiguration,
    c.hero.displaySection,
    c.hero.spotlightSection,
    MainPageBridge.homeBoardReady,
  );
  c.catalogPresentation = createHomeCatalogPresentation(
    c.ref,
    (
      mounted: () => c.mounted,
      setState: c.setState,
      context: () => c.context,
      isTelevision: () => c.widget.isTelevision,
      searchMode: () => c.widget.searchMode,
      discoverMode: () => c.widget.discoverMode,
      view: () => c.homeView,
      nativeAddon: () => NativeSeriesMetadataService.addon,
      readMergedSeriesEnabled:
          DetailNavigationStorage.getMergedSeriesPageEnabled,
      cardSettings: () => c.discoverLifecycle.bindings.cards,
      tabIndex: () => c.tabIndex,
      localCompletion: () => LocalCompletionStorage.localCompletionRevision,
      mdblistPlayback: () => MdblistService.instance.playbackRevision,
    ),
    board: c.board.workflow,
    continuation: c.leading.content,
    search: c.search.modes,
    input: c.search.input.inputSection,
    searchController: c.searchController,
    discover: c.discover.section,
    hero: c.hero,
    actions: c.homeActions,
    playback: c.leading.playback,
    returning: c.leading.continuation.returning,
    saved: c.leading.saved.section,
  );
}
