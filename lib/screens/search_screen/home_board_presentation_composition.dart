import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/search/presentation/search_input_section.dart';
import 'search_mode_composition.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import '../../features/home/presentation/home_board_bindings.dart';
import 'home_board_composition.dart';
import 'home_stage_composition.dart';
import 'home_rendering_composition.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_media_composition.dart';
import 'home_hero_composition.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/home/presentation/home_spotlight_section.dart';
import 'home_continuation_content_composition.dart';
import 'home_continuation_presentation_composition.dart';
import 'home_saved_composition.dart';
import 'home_item_composition.dart';
import '../../features/home/presentation/home_classic_geometry.dart';
import 'home_catalog_item_actions_adapter.dart';
import '../../features/home/presentation/home_board_rendering.dart';

typedef HomeBoardPresentationDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeBoardBindings Function() bindings,
  Object? Function() scope,
  HomeCatalogPresentation Function() catalog,
  HomeMediaComposition Function() media,
  int Function() tabIndex,
  bool Function() profileCurrent,
  int Function() heroIdentity,
});

typedef HomeBoardPresentation = ({
  HomeStages stages,
  HomeBoardWorkflow workflow,
  HomeBoardRendering rendering,
  HomeClassicGeometry geometry,
});

/// Constructs the board's stage layouts, workflow and rendering in that order.
/// Startup and teardown remain explicit phases owned by the calling route.
HomeBoardPresentation createHomeBoardPresentation(
  WidgetRef ref,
  HomeBoardPresentationDeps deps, {
  required HomeHeroComposition hero,
  required HomeSpotlightSection spotlight,
  required SearchInputSection input,
  required DiscoverSection discover,
  required SearchModeComposition search,
  required KeywordSearchSection keyword,
  required HomeContinuationContent continuation,
  required HomeContinuationPresentation continuationView,
  required HomeSavedComposition saved,
  required HomeItemComposition actions,
  required ValueNotifier<String?> ambientArt,
  required ValueNotifier<Color?> heroTint,
  required ValueNotifier<bool> Function() ready,
}) {
  late final HomeStages stages;
  late final HomeBoardWorkflow workflow;
  late final HomeBoardRendering rendering;
  // One catalog-item role and one Classic geometry for every board consumer.
  final items = HomeCatalogItemActionsAdapter(
    badges: () => deps.catalog().badges,
    navigation: () => deps.catalog().navigation,
  );
  final geometry = HomeClassicGeometry((
    context: deps.context,
    isTelevision: deps.isTelevision,
    searchMode: deps.searchMode,
  ), hero.displaySection);
  stages = createHomeStages(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      board: () => workflow.boardSection,
      focus: () => workflow.boardFocus,
      paging: () => workflow.boardPaging,
      navigation: () => deps.catalog().navigation,
      media: () => deps.media().media,
      sidebar: HomeHeroShellBridge.focusTvSidebar,
    ),
    displaySection: hero.displaySection,
    heroPreview: hero.heroPreview,
    spotlightSection: spotlight,
    continuationProjection: continuationView.projection,
    continuationSection: continuation.section,
    savedSection: saved.section,
    heroSection: hero.heroSection,
    heroLive: hero.heroLive,
    savedIptv: saved.iptv,
    watchlistActions: saved.watchlist,
    playlistActions: saved.playlist,
    continuationMenu: continuationView.menu,
    itemActions: actions.items,
    catalogActions: actions.catalog,
    catalogSection: search.catalog,
    ambientArt: ambientArt,
    heroTint: heroTint,
    items: items,
  );
  workflow = createHomeBoardWorkflow(
    ref,
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      bindings: deps.bindings,
      scope: deps.scope,
      badges: () => deps.catalog().badges,
      geometry: geometry,
      tabIndex: deps.tabIndex,
    ),
    catalogSection: search.catalog,
    displaySection: hero.displaySection,
    spotlightSection: spotlight,
    inputSection: input,
    discoverSection: discover,
    listsSection: search.lists,
    continuationSection: continuation.section,
    savedSection: saved.section,
    heroPreview: hero.heroPreview,
    keywordSection: keyword,
    continuationLoading: continuation.loading,
    modeSection: search.mode,
    heroSection: hero.heroSection,
    heroLive: hero.heroLive,
    stages: stages,
    ready: ready(),
  );
  rendering = createHomeRendering(
    (
      mounted: deps.mounted,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      profileCurrent: deps.profileCurrent,
      media: () => deps.media(),
      heroIdentity: deps.heroIdentity,
    ),
    board: workflow,
    catalog: search.catalog,
    hero: hero,
    stages: stages,
    saved: saved.section,
    savedRows: saved.rows,
    continuationProjection: continuationView.projection,
    continuationMenu: continuationView.menu,
    continuationRows: continuationView.rows,
    spotlight: spotlight,
    items: items,
    geometry: geometry,
  );
  return (
    stages: stages,
    workflow: workflow,
    rendering: rendering,
    geometry: geometry,
  );
}
