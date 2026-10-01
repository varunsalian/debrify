import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/presentation/home_catalog_actions.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_continuation_removal.dart';
import '../../features/home/presentation/home_continuation_return.dart';
import '../../features/home/presentation/home_detail_actions.dart';
import '../../features/home/presentation/home_detail_menus.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/home/presentation/home_integration_section.dart';
import '../../features/home/presentation/home_item_actions.dart';
import '../../features/home/presentation/home_playback_navigation.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_source_actions.dart';
import '../../features/sources/presentation/local_source_picker_composition.dart';
import '../../theme/app_theme_scope.dart';
import 'home_continuation_content_composition.dart';
import 'home_sources_entry.dart';
import 'home_view_bindings.dart';

typedef HomeItemCompositionDeps = ({
  bool Function() mounted,
  bool Function() profileCurrent,
  BuildContext Function() context,
  bool Function() isTelevision,
  HomeViewBindings Function() view,
  HomeCatalogBadges Function() badges,
  HomeContinuationReturn Function() returning,
  HomeIntegrationSection Function() integrations,
  HomeContinuationContent Function() continuation,
  HomeRowsNavigation Function() navigation,
  HomeContinuationRemoval Function() removal,
});

typedef HomeItemComposition = ({
  HomePlaybackNavigation playback,
  HomeCatalogActions catalog,
  HomeItemActions items,
});

/// Constructs item/detail/playback coordinators with deferred view dependencies.
/// Platform menu callbacks are supplied at the screen's composition boundary.
HomeItemComposition createHomeItemActions(
  WidgetRef ref,
  HomeItemCompositionDeps deps, {
  required HomeDetailActions Function(
    HomePlaybackNavigation,
    HomeCatalogActions,
    HomeSourceActions,
  )
  createDetails,
}) {
  late final HomePlaybackNavigation playback;
  late final HomeCatalogActions catalog;
  late final HomeSourceActions sources;
  late final HomeDetailActions details;
  late final HomeItemActions items;
  playback = HomePlaybackNavigation(ref, (
    mounted: deps.mounted,
    profileCurrent: deps.profileCurrent,
    context: deps.context,
    isTelevision: deps.isTelevision,
    clearResume: () {
      if (deps.mounted()) deps.view().homeMediaBindings.seriesResume.clear();
    },
    refreshBoundSources: () => deps.badges().refreshBoundSources(),
    refreshAfterPlayback: ({trackers = false}) =>
        deps.returning().refreshAfterPlayback(trackers: trackers),
    imdbOf: (item) => deps.badges().imdbOf(item),
    boundCountFor: (item) => deps.badges().boundCountFor(item),
    editSource: (item, {isCurrent}) =>
        sources.editOrSelectSource(item, isCurrent: isCurrent),
    sources: () => ref.read(homeSourcesNavigationProvider),
  ));
  catalog = HomeCatalogActions(ref, (
    mounted: deps.mounted,
    profileCurrent: deps.profileCurrent,
    context: deps.context,
    session: () => deps.view().homeCatalogSession,
    imdbOf: (item) => deps.badges().imdbOf(item),
    availability: () => (
      trakt: deps.integrations().isTraktAuthenticated,
      simkl: deps.integrations().isSimklAuthenticated,
      mdblist: deps.integrations().isMdblistAuthenticated,
    ),
    cachedTrakt: (item) =>
        deps.continuation().section.traktByImdb[item.progressId] ??
        deps.continuation().section.traktByImdb[item.id],
  ), playback);
  sources = HomeSourceActions(ref, (
    context: deps.context,
    session: () => deps.view().homeCatalogSession,
    imdbOf: (item) => deps.badges().imdbOf(item),
    refreshBindings: () => deps.badges().refreshBoundSources(),
    localPicker: () =>
        HomeLocalSourcePickerAdapter(ref.read(localSourcePickerProvider)),
  ), playback);
  details = createDetails(playback, catalog, sources);
  items = HomeItemActions(
    ref,
    (
      context: deps.context,
      session: () => deps.view().homeCatalogSession,
      isTelevision: deps.isTelevision,
      pikpakOnly: () => deps.badges().pikpakOnly,
      mergedSeriesPage: () => deps.navigation().mergedSeriesPage,
      imdbOf: (item) => deps.badges().imdbOf(item),
      cwIds: () => deps.continuation().section.cwIds,
      removeLocalHistory: (id) => deps.removal().removeLocalHistory(id),
      onHistoryRemoved: () async {
        if (deps.mounted()) deps.view().homeMediaBindings.seriesResume.clear();
        await deps.continuation().loading.loadContinueWatching();
      },
      onClosed: (returnToTabOnClose) {
        unawaited(deps.returning().refreshAfterPlayback());
        deps.integrations().refreshTraktAuthState();
        deps.integrations().refreshSimklAuthState();
        deps.integrations().refreshMdblistAuthState();
        if (returnToTabOnClose != null) {
          HomeHeroShellBridge.switchTab(returnToTabOnClose);
        }
      },
      menus: (item, imdb, inCw) {
        // Same for the Trakt Continue Watching rows — removal goes through the
        // Trakt playback/history APIs rather than local storage.
        final inTraktCw =
            imdb != null &&
            deps.continuation().section.traktByImdb.containsKey(imdb);
        final inMdblistCw =
            imdb != null &&
            deps.continuation().section.mdblistByImdb[imdb]?.paused == true;

        return HomeDetailMenus(
          type: item.type,
          identity: imdb,
          removalColor: AppThemeScope.of(deps.context()).home.danger,
          inLocalContinueWatching: inCw,
          inTraktContinueWatching: inTraktCw,
          inMdblistContinueWatching: inMdblistCw,
          hasBoundSource: () => deps.badges().isBound(item),
          traktAuthenticated: () => deps.integrations().isTraktAuthenticated,
          simklAuthenticated: () => deps.integrations().isSimklAuthenticated,
          mdblistAuthenticated: () =>
              deps.integrations().isMdblistAuthenticated,
          hasSimklPause: () =>
              deps
                  .continuation()
                  .section
                  .simklByImdb[deps.continuation().section.simklCardKey(item)]
                  ?.progress !=
              null,
        );
      },
      boundCountFor: (item) => deps.badges().boundCountFor(item),
    ),
    playback,
    catalog,
    details,
    sources,
  );
  return (playback: playback, catalog: catalog, items: items);
}
