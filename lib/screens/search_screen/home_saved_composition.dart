import 'package:flutter/widgets.dart';
import '../../models/stremio_addon.dart';
import '../../models/iptv_playlist.dart';
import '../../models/profiles/profile_policy.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../features/search/presentation/catalog_search_section.dart';
import '../../features/home/presentation/home_playlist_actions.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/home/presentation/home_saved_iptv_actions.dart';
import '../../features/home/presentation/home_watchlist_actions.dart';
import '../../features/home/presentation/home_saved_content_rows.dart';
import '../../features/home/presentation/home_classic_favorite_rows.dart';
import '../../features/home/presentation/home_item_actions.dart';
import 'home_view_bindings.dart';
import 'home_board_composition.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_continuation_return.dart';
import '../../features/home/presentation/home_classic_section.dart';
import 'home_hero_composition.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';

typedef HomeSavedCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  HomeViewBindings Function() view,
  HomeBoardWorkflow Function() board,
  HomeRowsNavigation Function() navigation,
  HomeContinuationReturn Function() returning,
  HomeClassicSection Function() classic,
  HomeHeroComposition Function() hero,
  bool Function(ProfileFeature) allowed,
  bool Function() profileCurrent,
});

typedef HomeSavedComposition = ({
  HomePlaylistActions playlist,
  HomeSavedContentSection section,
  HomeSavedIptvActions iptv,
  HomeWatchlistActions watchlist,
  HomeSavedContentRows rows,
});

/// Constructs saved content, playback dispatch and row wiring in their original order.
HomeSavedComposition createHomeSavedContent(
  HomeSavedCompositionDeps deps, {
  required SearchInputSection input,
  required CatalogSearchSection catalog,
  required HomeItemActions items,
  required Future<void> Function(
    BuildContext,
    Map<String, dynamic>, {
    bool playRandom,
  })
  playPlaylist,
  required void Function(BuildContext, String, IptvChannel, bool) launchIptv,
  required Future<void> Function(StremioMeta) removeWatchlist,
  required String Function(String) iptvListId,
}) {
  late final HomePlaylistActions playlist;
  late final HomeSavedContentSection section;
  late final HomeSavedIptvActions iptv;
  late final HomeWatchlistActions watchlist;
  late final HomeSavedContentRows rows;
  playlist = HomePlaylistActions((
    mounted: deps.mounted,
    profileCurrent: deps.profileCurrent,
    context: deps.context,
    controller: () => section.playlistController,
    reload: () => section.loadPlaylistFavorites(),
    play: playPlaylist,
  ));
  section = HomeSavedContentSection((
    bindings: () => deps.view().favoriteBindings,
    mounted: deps.mounted,
    setState: deps.setState,
    disabled: () => deps.board().boardSection.homeDisabled,
    autoFocus: () => deps.board().boardFocus.maybeAutoFocusBoard(),
    focusContent: input.focusContent,
    requestRowFocus: (nodes, desired) =>
        deps.board().boardFocus.requestRowFocus(nodes, desired),
    debrifyTvAllowed: () => deps.allowed(ProfileFeature.debrifyTv),
    stremioTvAllowed: () => deps.allowed(ProfileFeature.stremioTv),
    iptvAllowed: () => deps.allowed(ProfileFeature.iptv),
    iptvListId: iptvListId,
    playChannel: (channel) =>
        HomeHeroShellBridge.playSavedDebrifyChannel(channel.id),
    playStremio: (channel) =>
        HomeHeroShellBridge.playSavedStremioChannel(channel.id),
  ), catalog);
  iptv = HomeSavedIptvActions((
    mounted: deps.mounted,
    context: deps.context,
    isTelevision: deps.isTelevision,
    launch: launchIptv,
  ));
  watchlist = HomeWatchlistActions(
    (
      mounted: deps.mounted,
      profileCurrent: deps.profileCurrent,
      context: deps.context,
      isTelevision: deps.isTelevision,
      remove: removeWatchlist,
      reload: section.loadMyWatchlist,
      addonForContinue: (id) => deps.navigation().addonForContinue(id),
      refreshAfterPlayback: ({trackers = false}) =>
          deps.returning().refreshAfterPlayback(trackers: trackers),
    ),
    iptv,
    items,
  );
  rows = HomeSavedContentRows(
    (
      classicRows: (rowId, nodes) => HomeClassicFavoriteRows(
        context: deps.context(),
        isTelevision: deps.isTelevision(),
        posterWidth: deps.classic().railPosterW(deps.context()),
        captionBand: deps.hero().displaySection.homeArtPosterCaptionBand,
        showTitle: () =>
            !deps.hero().displaySection.hideHomeCardTitlesAndRatings,
        nodes: nodes,
        up: (col) =>
            () => deps.board().boardFocus.focusRelativeHomeRail(rowId, -1, col),
        down: (col) =>
            () => deps.board().boardFocus.focusRelativeHomeRail(rowId, 1, col),
        sidebar: HomeHeroShellBridge.focusTvSidebar,
        clearLive: deps.hero().heroLive.clearHeroLiveIptv,
        previewLive: deps.hero().heroLive.setHeroLiveIptv,
      ),
      playChannel: section.playChannel,
      playStremio: section.playStremioTvChannel,
      playIptv: iptv.playIptvChannel,
      playIptvList: iptv.playIptvListChannel,
      openWatchlist: watchlist.openMyWatchlistItem,
    ),
    section,
    playlist,
  );
  return (
    playlist: playlist,
    section: section,
    iptv: iptv,
    watchlist: watchlist,
    rows: rows,
  );
}
