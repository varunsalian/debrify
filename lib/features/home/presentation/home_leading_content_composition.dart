import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/iptv_cw_entry.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../search/presentation/search_presentation_composition.dart';
import 'home_saved_composition.dart';
import 'home_continuation_content_composition.dart';
import 'home_continuation_playback.dart';
import 'home_continuation_removal.dart';
import 'home_continuation_presentation_composition.dart';
import 'home_board_presentation_composition.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_hero_composition.dart';
import 'home_view_bindings.dart';
import 'home_item_composition.dart';

typedef HomeLeadingContentDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeViewBindings Function() view,
  HomeBoardPresentation Function() board,
  HomeCatalogPresentation Function() catalog,
  HomeHeroComposition Function() hero,
  bool Function(ProfileFeature) allowed,
  bool Function() profileCurrent,
  int Function() tabIndex,
  bool mdblistEnabled,
});

typedef HomeLeadingContent = ({
  HomeSavedComposition saved,
  HomeContinuationContent content,
  HomeContinuationPlayback playback,
  HomeContinuationRemoval removal,
  HomeContinuationPresentation continuation,
});

/// Constructs saved shelves followed by continuation content and its actions.
/// No loads, listener registration or restoration occur during construction.
HomeLeadingContent createHomeLeadingContent(
  WidgetRef ref,
  HomeLeadingContentDeps deps, {
  required SearchPresentation search,
  required HomeItemComposition actions,
  required Future<void> Function(
    BuildContext,
    Map<String, dynamic>, {
    bool playRandom,
  })
  playPlaylist,
  required void Function(BuildContext, String, IptvChannel, bool) launchIptv,
  required Future<void> Function(StremioMeta) removeWatchlist,
  required String Function(String) iptvListId,
  required Future<void> Function(
    BuildContext,
    IptvCwEntry, {
    required bool isTelevision,
  })
  openIptv,
  required Future<void> Function(StremioMeta) removeSimkl,
}) {
  late final HomeSavedComposition saved;
  late final HomeContinuationContent content;
  late final HomeContinuationPlayback playback;
  late final HomeContinuationRemoval removal;
  late final HomeContinuationPresentation continuation;
  saved = createHomeSavedContent(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      view: () => deps.view(),
      board: () => deps.board().workflow,
      navigation: () => deps.catalog().navigation,
      returning: () => continuation.returning,
      classic: () => deps.board().rendering.classic,
      hero: () => deps.hero(),
      allowed: deps.allowed,
      profileCurrent: deps.profileCurrent,
    ),
    input: search.input.inputSection,
    catalog: search.modes.catalog,
    items: actions.items,
    playPlaylist: playPlaylist,
    removeWatchlist: removeWatchlist,
    iptvListId: iptvListId,
    launchIptv: launchIptv,
  );
  content = createHomeContinuationContent((
    mounted: deps.mounted,
    setState: deps.setState,
    context: deps.context,
    isTelevision: deps.isTelevision,
    searchMode: deps.searchMode,
    discoverMode: deps.discoverMode,
    view: () => deps.view(),
    board: () => deps.board().workflow,
    badges: () => deps.catalog().badges,
    tabIndex: deps.tabIndex,
    mdblistEnabled: deps.mdblistEnabled,
  ), saved.section);
  playback = HomeContinuationPlayback(
    (
      context: deps.context,
      isTelevision: deps.isTelevision,
      addonForContinue: (id) => deps.catalog().navigation.addonForContinue(id),
      imdbOf: (item) => deps.catalog().badges.imdbOf(item),
      markPlaybackStarted: () => continuation.returning.markPlaybackStarted(),
      refreshAfterPlayback: ({trackers = false}) =>
          continuation.returning.refreshAfterPlayback(trackers: trackers),
      openIptv: openIptv,
    ),
    content.section,
    actions.playback,
    actions.catalog,
    actions.items,
  );
  removal = HomeContinuationRemoval(
    ref,
    (
      mounted: deps.mounted,
      profileCurrent: deps.profileCurrent,
      session: () => deps.view().homeCatalogSession,
      imdbOf: (item) => deps.catalog().badges.imdbOf(item),
      removeSimkl: removeSimkl,
    ),
    content.section,
    content.loading,
    actions.playback,
  );
  continuation = createHomeContinuationPresentation(
    ref,
    (
      mounted: deps.mounted,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      board: () => deps.board().workflow,
      badges: () => deps.catalog().badges,
      navigation: () => deps.catalog().navigation,
      integrations: () => deps.catalog().integrations,
      classic: () => deps.board().rendering.classic,
      stages: () => deps.board().stages,
      hero: () => deps.hero(),
      view: () => deps.view(),
    ),
    content: content,
    playback: playback,
    catalogNavigation: actions.playback,
    removal: removal,
    catalog: search.modes.catalog,
    saved: saved.section,
  );
  return (
    saved: saved,
    content: content,
    playback: playback,
    removal: removal,
    continuation: continuation,
  );
}

/// Releases continuation and saved-row focus pools in the original interleaved order.
void disposeHomeLeadingFocus(HomeLeadingContent leading) {
  leading.content.section.continuationNodes.disposeNodes();
  leading.saved.section.favoriteNodes.disposeNodes();
  leading.content.section.continuationNodes.clearNodes();
  leading.saved.section.favoriteNodes.clearNodes();
}
