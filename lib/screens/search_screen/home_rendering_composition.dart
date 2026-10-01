import 'package:flutter/widgets.dart';

import '../../features/home/presentation/home_board_rendering.dart';
import '../../features/home/presentation/home_catalog_item_actions.dart';
import '../../features/home/presentation/home_classic_geometry.dart';
import '../../features/home/presentation/home_classic_section.dart';
import '../../features/home/presentation/home_continuation_menu.dart';
import '../../features/home/presentation/home_continuation_projection.dart';
import '../../features/home/presentation/home_continuation_rows.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/home/presentation/home_saved_content_rows.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/home/presentation/home_spotlight_section.dart';
import '../../features/search/presentation/catalog_search_section.dart';
import 'home_board_composition.dart';
import 'home_hero_composition.dart';
import 'home_media_composition.dart';
import 'home_stage_composition.dart';

typedef HomeRenderingCompositionDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() profileCurrent,
  HomeMediaComposition Function() media,
  int Function() heroIdentity,
});

/// Wires the classic rows and layout selector to their existing borrowed owners.
HomeBoardRendering createHomeRendering(
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
  required HomeCatalogItemActions items,
  required HomeClassicGeometry geometry,
}) {
  final classic = HomeClassicSection(
    (
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      media: () => deps.media().media,
      artworkWidth: () => deps.media().artworkCacheWidth,
      artworkHeight: () => deps.media().artworkCacheHeight,
      heroIdentity: deps.heroIdentity,
      sidebar: HomeHeroShellBridge.focusTvSidebar,
      items: items,
    ),
    geometry,
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
  return HomeBoardRendering(
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
}
