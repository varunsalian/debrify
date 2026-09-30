import 'package:flutter/material.dart';
import '../../features/home/data/home_board_services.dart';
import '../../features/home/presentation/home_board_deferred.dart';
import '../../features/home/presentation/home_board_media.dart';
import '../../features/home/presentation/home_board_section.dart';
import '../../features/home/presentation/home_board_focus.dart';
import '../../features/home/presentation/home_board_paging.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_stage_rails.dart';
import '../../features/home/presentation/home_stage_section.dart';
import '../../features/home/presentation/home_stage_favorites.dart';
import '../../features/home/presentation/home_stage_geometry.dart';
import '../../features/home/presentation/home_stage_cells.dart';
import '../../features/home/presentation/home_stage_boards.dart';
import '../../features/home/presentation/home_atrium_section.dart';
import '../../features/home/presentation/home_tonight_section.dart';
import '../../features/home/presentation/home_spotlight_rows.dart';
import 'search_spotlight_results.dart';
import '../../features/home/presentation/home_spotlight_boards.dart';
import '../../features/home/presentation/home_display_section.dart';
import '../../features/home/presentation/home_hero_preview.dart';
import '../../features/home/presentation/home_spotlight_section.dart';
import '../../features/home/presentation/home_continuation_projection.dart';
import '../../features/home/presentation/home_continuation_section.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/home/presentation/home_hero_section.dart';
import '../../features/home/presentation/home_hero_live.dart';
import '../../features/home/presentation/home_saved_iptv_actions.dart';
import '../../features/home/presentation/home_watchlist_actions.dart';
import '../../features/home/presentation/home_playlist_actions.dart';
import '../../features/home/presentation/home_continuation_menu.dart';
import '../../features/home/presentation/home_item_actions.dart';
import '../../features/home/presentation/home_catalog_actions.dart';
import '../../features/search/presentation/catalog_search_section.dart';

typedef HomeStageCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  HomeBoardSection Function() board,
  HomeBoardFocus Function() focus,
  HomeBoardPaging Function() paging,
  HomeRowsNavigation Function() navigation,
  HomeCatalogBadges Function() badges,
  HomeBoardMedia Function() media,
  VoidCallback sidebar,
});

typedef HomeStages = ({
  HomeStageRails stageRailsSection,
  HomeStageSection stageSection,
  HomeStageFavorites stageFavorites,
  HomeStageGeometry stageGeometry,
  HomeStageBoards stageBoards,
  HomeAtriumSection atriumLayout,
  HomeTonightSection tonightLayout,
  HomeSpotlightRows spotlightRows,
  SearchSpotlightResults spotlightResults,
  HomeSpotlightBoards spotlightBoards,
});

/// Constructs the stage layouts in their original order; starts no listeners or work.
HomeStages createHomeStages(
  HomeStageCompositionDeps deps, {
  required HomeDisplaySection displaySection,
  required HomeHeroPreview heroPreview,
  required HomeSpotlightSection spotlightSection,
  required HomeContinuationProjection continuationProjection,
  required HomeContinuationSection continuationSection,
  required HomeSavedContentSection savedSection,
  required HomeHeroSection heroSection,
  required HomeHeroLive heroLive,
  required HomeSavedIptvActions savedIptv,
  required HomeWatchlistActions watchlistActions,
  required HomePlaylistActions playlistActions,
  required HomeContinuationMenu continuationMenu,
  required HomeItemActions itemActions,
  required HomeCatalogActions catalogActions,
  required CatalogSearchSection catalogSection,
  required ValueNotifier<String?> ambientArt,
  required ValueNotifier<Color?> heroTint,
}) {
  late final HomeStageRails stageRailsSection;
  late final HomeStageSection stageSection;
  late final HomeStageFavorites stageFavorites;
  late final HomeStageGeometry stageGeometry;
  late final HomeStageCells stageCells;
  late final HomeStageBoards stageBoards;
  late final HomeAtriumSection atriumLayout;
  late final HomeTonightSection tonightLayout;
  late final HomeSpotlightRows spotlightRows;
  late final SearchSpotlightResults spotlightResults;
  late final HomeSpotlightBoards spotlightBoards;

  stageRailsSection = HomeStageRails(
    (
      sections: () => deps.board().sections,
      rowNodes: () => deps.board().rowNodes,
      orderActive: () => deps.board().homeRowOrderActive,
      order: () => deps.board().effectiveHomeRowOrder,
      disabled: () => deps.board().homeDisabled,
      sectionRowId: HomeBoardServices.rowId,
      style: () => displaySection.homeStyleEffective,
      hideCollectionNames: () => displaySection.hideHomeCollectionNames,
      sectionTag: (section) => deps.navigation().sectionTag(section),
    ),
    continuationProjection,
    continuationSection,
    savedSection,
  );
  stageSection = HomeStageSection(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      clearFavoriteFocus: () => stageFavorites.canvasFavFocus.value = null,
      rowsPending: () => deps.board().boardRowsPending,
      canAdvance: () => deps.board().boardCanAdvance,
      focusContinuation: () => deps.focus().focusCatalogContinuation(),
      loadMore: () => deps.paging().loadMoreBoard(),
    ),
    stageRailsSection,
    displaySection,
    heroPreview,
    spotlightSection,
    HomeBoardDeferred.pendingDownMaxAge,
  );
  stageFavorites = HomeStageFavorites(
    stageSection,
    displaySection,
    heroSection,
    heroPreview,
    heroLive,
    savedSection,
    savedIptv,
    watchlistActions,
    playlistActions,
    deps.sidebar,
  );
  stageGeometry = HomeStageGeometry(
    displaySection,
    () => deps.board().sections,
  );
  stageCells = HomeStageCells(
    (
      sectionAt: (index) => deps.board().sections[index],
      isBound: (item) => deps.badges().isBound(item),
      pikpakOnly: () => deps.badges().pikpakOnly,
      openSection: (section, item, {String? heroTag}) =>
          deps.navigation().sectionOpenItem(section, item, heroTag: heroTag),
      playSection: (section, item) =>
          deps.navigation().sectionQuickPlay(section, item),
      sidebar: deps.sidebar,
      loadMore: (row, {bool resume = false}) =>
          deps.paging().loadMoreRow(row, resume: resume),
    ),
    stageGeometry,
    stageSection,
    stageFavorites,
    heroSection,
    continuationMenu,
  );
  stageBoards = HomeStageBoards(
    (context: deps.context, isTelevision: deps.isTelevision, media: deps.media),
    stageSection,
    stageRailsSection,
    stageGeometry,
    stageCells,
    stageFavorites,
    displaySection,
    heroPreview,
  );
  atriumLayout = HomeAtriumSection(
    (
      context: deps.context,
      isTelevision: deps.isTelevision,
      media: deps.media,
      canAdvance: () => deps.board().boardCanAdvance,
      loadMore: () => deps.paging().loadMoreBoard(),
    ),
    stageSection,
    stageRailsSection,
    stageGeometry,
    stageCells,
    stageFavorites,
    displaySection,
    heroPreview,
  );
  tonightLayout = HomeTonightSection(
    (
      context: deps.context,
      isTelevision: deps.isTelevision,
      media: deps.media,
      sidebar: deps.sidebar,
      isBound: (item) => deps.badges().isBound(item),
    ),
    stageSection,
    stageRailsSection,
    stageGeometry,
    stageCells,
    stageFavorites,
    heroPreview,
    heroSection,
    continuationMenu,
  );
  spotlightRows = HomeSpotlightRows(
    (
      sections: () => deps.board().sections,
      rowNodes: () => deps.board().rowNodes,
      catalogTag: (section) => deps.navigation().catalogSourceTag(section),
      seeAll: (section) => deps.navigation().openCatalogSeeAll(section),
      openCollection: (section, item) =>
          deps.navigation().openCollectionFolder(section, item),
    ),
    stageRailsSection,
    stageSection,
    displaySection,
    continuationMenu,
    stageFavorites,
    itemActions,
  );
  spotlightResults = SearchSpotlightResults(
    (
      context: deps.context,
      sections: () => deps.board().sections,
      rowNodes: () => deps.board().rowNodes,
      failures: () => catalogSection.catalogState.failures,
      leaveTop: () => deps.focus().leaveBoardTop(),
      openSection: (section, item, {String? heroTag}) =>
          deps.navigation().sectionOpenItem(section, item, heroTag: heroTag),
      pikpakOnly: () => deps.badges().pikpakOnly,
      catalogTag: (section) => deps.navigation().catalogSourceTag(section),
      seeAll: (section) => deps.navigation().openCatalogSeeAll(section),
      loadMoreRow: (row, {bool resume = false}) =>
          deps.paging().loadMoreRow(row, resume: resume),
    ),
    catalogSection,
    displaySection,
    heroPreview,
    spotlightSection,
    itemActions,
    catalogActions,
  );
  spotlightBoards = HomeSpotlightBoards(
    (
      mounted: deps.mounted,
      isTelevision: deps.isTelevision,
      loadMoreRow: (row, {bool resume = false}) =>
          deps.paging().loadMoreRow(row, resume: resume),
      loadMore: () => deps.paging().loadMoreBoard(),
      rowsPending: () => deps.board().boardRowsPending,
      media: deps.media,
    ),
    stageRailsSection,
    displaySection,
    heroPreview,
    spotlightSection,
    itemActions,
    spotlightRows,
    ambientArt,
    heroTint,
  );
  return (
    stageRailsSection: stageRailsSection,
    stageSection: stageSection,
    stageFavorites: stageFavorites,
    stageGeometry: stageGeometry,
    stageBoards: stageBoards,
    atriumLayout: atriumLayout,
    tonightLayout: tonightLayout,
    spotlightRows: spotlightRows,
    spotlightResults: spotlightResults,
    spotlightBoards: spotlightBoards,
  );
}

/// Releases the stage resources after their shell and keyboard hooks are removed.
void disposeHomeStageResources(HomeStages stages) {
  stages.stageSection.stageTheater.dispose();
  stages.stageFavorites.canvasFavFocus.dispose();
  stages.stageSection.atriumFocusedRailKey.dispose();
  stages.stageSection.tonightFocus.dispose();
  stages.stageSection.stageCol.dispose();
}
