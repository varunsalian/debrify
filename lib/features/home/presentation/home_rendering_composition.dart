import 'package:flutter/widgets.dart';
import '../../search/presentation/catalog_search_section.dart';
import 'home_board_composition.dart';
import 'home_board_rendering.dart';
import 'home_classic_section.dart';
import 'home_catalog_badges.dart';
import 'home_continuation_projection.dart';
import 'home_continuation_menu.dart';
import 'home_continuation_rows.dart';
import 'home_hero_composition.dart';
import 'home_hero_shell_bridge.dart';
import 'home_media_composition.dart';
import 'home_rows_navigation.dart';
import 'home_saved_content_section.dart';
import 'home_saved_content_rows.dart';
import 'home_spotlight_section.dart';
import 'home_stage_composition.dart';

typedef HomeRenderingCompositionDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() profileCurrent,
  HomeMediaComposition Function() media,
  HomeRowsNavigation Function() navigation,
  HomeCatalogBadges Function() badges,
  int Function() heroIdentity,
});

typedef HomeRenderingComposition = ({
  HomeClassicSection classic,
  HomeBoardRendering rendering,
});

/// Wires the classic rows and layout selector to their existing borrowed owners.
HomeRenderingComposition createHomeRendering(
  HomeRenderingCompositionDeps deps, {
  required HomeBoardWorkflow board,
  required CatalogSearchSection catalog,
  required HomeHeroComposition hero,
  required HomeStages stages,
  required HomeSavedContentSection saved,
  required HomeSavedContentRows savedRows,
  required HomeContinuationProjection continuationProjection,
  required HomeContinuationMenu continuationMenu,
  required HomeContinuationRows continuationRows,
  required HomeSpotlightSection spotlight,
}) {
  late final HomeClassicSection classic;
  late final HomeBoardRendering rendering;
  classic = HomeClassicSection(
    (
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      media: () => deps.media().media,
      artworkWidth: () => deps.media().artworkCacheWidth,
      artworkHeight: () => deps.media().artworkCacheHeight,
      sourceTag: (section) => deps.navigation().catalogSourceTag(section),
      openSeeAll: (section) => deps.navigation().openCatalogSeeAll(section),
      heroIdentity: deps.heroIdentity,
      isBound: (item) => deps.badges().isBound(item),
      pikpakOnly: () => deps.badges().pikpakOnly,
      sidebar: HomeHeroShellBridge.focusTvSidebar,
      openItem: (section, item, {String? heroTag}) =>
          deps.navigation().sectionOpenItem(section, item, heroTag: heroTag),
      quickPlay: (section, item) =>
          deps.navigation().sectionQuickPlay(section, item),
    ),
    board.boardSection,
    board.boardFocus,
    board.boardDeferred,
    board.boardPaging,
    catalog,
    hero.displaySection,
    stages.stageRailsSection,
    stages.stageGeometry,
    saved,
    savedRows,
    continuationProjection,
    continuationMenu,
    continuationRows,
    hero.heroSection,
    hero.heroPreview,
    hero.heroLive,
  );
  rendering = HomeBoardRendering(
    (
      mounted: deps.mounted,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      profileCurrent: deps.profileCurrent,
      layouts: () => {
        'canvas': stages.stageBoards.buildCanvasBoard,
        'atrium': stages.atriumLayout.buildAtriumBoard,
        'mosaic': stages.stageBoards.buildMosaicBoard,
        'promenade': stages.stageBoards.buildPromenadeBoard,
        'deck': stages.stageBoards.buildDeckBoard,
        'tonight': stages.tonightLayout.buildTonightBoard,
        'spotlight': stages.spotlightBoards.buildSpotlightBoard,
      },
      classic: classic.buildClassicBoard,
      searchSpotlight: stages.spotlightResults.buildSearchSpotlightBoard,
    ),
    board.boardSection,
    board.boardLoading,
    board.boardPaging,
    board.boardFocus,
    catalog,
    hero.displaySection,
    spotlight,
    stages.spotlightRows,
    saved,
    continuationProjection,
  );
  return (classic: classic, rendering: rendering);
}
