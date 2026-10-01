import '../../features/home/presentation/home_playback_navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/search/presentation/catalog_search_section.dart';
import '../../features/home/presentation/home_continuation_projection.dart';
import '../../features/home/presentation/home_continuation_menu.dart';
import '../../features/home/presentation/home_continuation_rows.dart';
import '../../features/home/presentation/home_continuation_return.dart';
import '../../features/home/presentation/home_continuation_see_all.dart';
import 'home_continuation_content_composition.dart';
import '../../features/home/presentation/home_continuation_playback.dart';
import '../../features/home/presentation/home_continuation_removal.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import 'home_board_composition.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_integration_section.dart';
import 'home_stage_composition.dart';
import 'home_hero_composition.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import 'home_view_bindings.dart';
import '../../features/home/presentation/home_classic_geometry.dart';

typedef HomeContinuationPresentationDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeBoardWorkflow Function() board,
  HomeCatalogBadges Function() badges,
  HomeRowsNavigation Function() navigation,
  HomeIntegrationSection Function() integrations,
  HomeClassicGeometry Function() geometry,
  HomeStages Function() stages,
  HomeHeroComposition Function() hero,
  HomeViewBindings Function() view,
});

typedef HomeContinuationPresentation = ({
  HomeContinuationProjection projection,
  HomeContinuationMenu menu,
  HomeContinuationRows rows,
  HomeContinuationReturn returning,
});

/// Wires continuation rows, menus and return navigation to shared route owners.
HomeContinuationPresentation createHomeContinuationPresentation(
  WidgetRef ref,
  HomeContinuationPresentationDeps deps, {
  required HomeContinuationContent content,
  required HomeContinuationPlayback playback,
  required HomePlaybackNavigation catalogNavigation,
  required HomeContinuationRemoval removal,
  required CatalogSearchSection catalog,
  required HomeSavedContentSection saved,
}) {
  late final HomeContinuationProjection projection;
  late final HomeContinuationMenu menu;
  late final HomeContinuationRows rows;
  late final HomeContinuationReturn returning;
  late final HomeContinuationSeeAll seeAll;
  projection = HomeContinuationProjection(
    (
      disabled: () => deps.board().boardSection.homeDisabled,
      openLocal: (category) => seeAll.openContinueWatchingSeeAll(category),
      openTrakt: (category) => seeAll.openTraktSeeAll(category),
      openSimkl: (category) => seeAll.openSimklCwSeeAll(category),
      openMdblist: (category) => seeAll.openMdblistCwSeeAll(category),
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      traktAuthenticated: () => deps.integrations().isTraktAuthenticated,
    ),
    content.section,
    playback,
    removal,
    catalog,
  );
  menu = HomeContinuationMenu(
    ref,
    (
      context: deps.context,
      isTelevision: deps.isTelevision,
      pikpakOnly: () => deps.badges().pikpakOnly,
      session: () => deps.view().homeCatalogSession,
      requestRowFocus: (nodes, desired) =>
          deps.board().boardFocus.requestRowFocus(nodes, desired),
      leaveBoardTop: () => deps.board().boardFocus.leaveBoardTop(),
    ),
    projection,
    catalogNavigation,
  );
  rows = HomeContinuationRows(
    (
      header: ({required title, tag, onSeeAll}) => deps.geometry().railHeader(
        title: title,
        tag: tag,
        onSeeAll: onSeeAll,
      ),
      isTelevision: deps.isTelevision,
      posterWidth: () => deps.geometry().railTitleCardW(deps.context()),
      cellHeight: () => deps.geometry().railTitleCardH(deps.context()),
      aspectRatio: () => deps.stages().stageGeometry.titleCardAspect,
      showTitleOverlay: () =>
          !deps.hero().displaySection.hideHomeCardTitlesAndRatings,
      artOf: (item) => deps.stages().stageGeometry.titleArtUrl(item),
      isBound: (item) => deps.badges().isBound(item),
      sidebar: HomeHeroShellBridge.focusTvSidebar,
      onFocused: (item) => deps.hero().heroSection.setHero(item),
      focusRelativeRail: (rowId, delta, column) =>
          deps.board().boardFocus.focusRelativeHomeRail(rowId, delta, column),
    ),
    content.section,
    menu,
  );
  returning = HomeContinuationReturn(
    (
      controller: () => deps.view().homeBoardBindings.playbackRefresh,
      mounted: deps.mounted,
      searchMode: deps.searchMode,
      context: deps.context,
      traktAuthenticated: () => deps.integrations().isTraktAuthenticated,
      clearResume: () {
        if (deps.mounted()) deps.view().homeMediaBindings.seriesResume.clear();
      },
      refreshBound: () => deps.badges().refreshBoundSources(),
    ),
    content.section,
    content.loading,
    saved,
  );
  seeAll = HomeContinuationSeeAll(
    (
      context: deps.context,
      navigation: () => deps.navigation().seeAllNavigation,
      pikpakOnly: () => deps.badges().pikpakOnly,
    ),
    content.section,
    playback,
    content.loading,
    returning,
  );
  return (projection: projection, menu: menu, rows: rows, returning: returning);
}
