import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/discover/presentation/discover_section.dart';
import '../../features/home/data/home_board_services.dart';
import '../../features/home/presentation/home_board_bindings.dart';
import '../../features/home/presentation/home_board_configuration_section.dart';
import '../../features/home/presentation/home_board_deferred.dart';
import '../../features/home/presentation/home_board_focus.dart';
import '../../features/home/presentation/home_board_loading.dart';
import '../../features/home/presentation/home_board_paging.dart';
import '../../features/home/presentation/home_board_publication.dart';
import '../../features/home/presentation/home_board_rows.dart';
import '../../features/home/presentation/home_board_section.dart';
import '../../features/home/presentation/home_catalog_badges.dart';
import '../../features/home/presentation/home_classic_geometry.dart';
import '../../features/home/presentation/home_continuation_loading.dart';
import '../../features/home/presentation/home_continuation_section.dart';
import '../../features/home/presentation/home_display_section.dart';
import '../../features/home/presentation/home_hero_live.dart';
import '../../features/home/presentation/home_hero_preview.dart';
import '../../features/home/presentation/home_hero_section.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/home/presentation/home_screen_controls.dart';
import '../../features/home/presentation/home_spotlight_section.dart';
import '../../features/search/presentation/catalog_search_section.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import '../../features/search/presentation/lists_search_section.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../features/search/presentation/search_mode_section.dart';
import '../../models/stremio_addon.dart';
import 'home_screen_controls_adapter.dart';
import 'home_stage_composition.dart';

/// Live readers needed only while wiring the board workflow; later owners remain deferred.
typedef HomeBoardCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeBoardBindings Function() bindings,
  Object? Function() scope,
  HomeCatalogBadges Function() badges,
  HomeClassicGeometry geometry,
  int Function() tabIndex,
});

typedef HomeBoardWorkflow = ({
  HomeBoardSection boardSection,
  HomeBoardPublication boardPublication,
  HomeBoardLoading boardLoading,
  HomeBoardPaging boardPaging,
  HomeBoardFocus boardFocus,
  HomeBoardDeferred boardDeferred,
  HomeBoardConfigurationSection boardConfiguration,
  HomeBoardRows boardRows,
  HomeScreenControls controls,
});

/// Constructs board workflow owners without registering or starting asynchronous work.
HomeBoardWorkflow createHomeBoardWorkflow(
  WidgetRef ref,
  HomeBoardCompositionDeps deps, {
  required CatalogSearchSection catalogSection,
  required HomeDisplaySection displaySection,
  required HomeSpotlightSection spotlightSection,
  required SearchInputSection inputSection,
  required DiscoverSection discoverSection,
  required ListsSearchSection listsSection,
  required HomeContinuationSection continuationSection,
  required HomeSavedContentSection savedSection,
  required HomeHeroPreview heroPreview,
  required KeywordSearchSection keywordSection,
  required HomeContinuationLoading continuationLoading,
  required SearchModeSection modeSection,
  required HomeHeroSection heroSection,
  required HomeHeroLive heroLive,
  required HomeStages stages,
  required ValueNotifier<bool> ready,
}) {
  final HomeScreenControls controls = HomeScreenControlsAdapter(
    input: inputSection,
    modes: modeSection,
    lists: listsSection,
    keyword: keywordSection,
    discover: discoverSection,
  );
  late final HomeBoardSection boardSection;
  late final HomeBoardPublication boardPublication;
  late final HomeBoardLoading boardLoading;
  late final HomeBoardPaging boardPaging;
  late final HomeBoardFocus boardFocus;
  late final HomeBoardDeferred boardDeferred;
  late final HomeBoardConfigurationSection boardConfiguration;
  late final HomeBoardRows boardRows;

  boardSection = HomeBoardSection((
    bindings: deps.bindings,
    mounted: deps.mounted,
    context: deps.context,
    searchMode: deps.searchMode,
    discoverMode: deps.discoverMode,
    isTracker: HomeBoardServices.isTracker,
  ), catalogSection);
  boardPublication = HomeBoardPublication(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      scope: deps.scope,
      boardHasFocus: () => boardFocus.boardHasFocus(),
      settleAutoFocus: () => boardFocus.autoFocusSettled = true,
      applySections:
          (sections, {bool preserveFocus = false, bool incremental = false}) =>
              boardRows.applySections(
                sections,
                preserveFocus: preserveFocus,
                incremental: incremental,
              ),
      autoFocus: () => boardFocus.maybeAutoFocusBoard(),
      completeDeferredDown: () => boardDeferred.maybeCompleteDeferredDown(),
      autoFill: ({bool resumeDeferred = false}) =>
          boardPaging.maybeAutoFillBoard(resumeDeferred: resumeDeferred),
    ),
    boardSection,
    catalogSection,
    stages.stageSection,
    ready,
  );
  boardLoading = HomeBoardLoading(
    ref,
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      scope: deps.scope,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      rowId: HomeBoardServices.rowId,
      refreshPikpakOnly: () => deps.badges().refreshPikpakOnly(),
      applySections:
          (sections, {bool preserveFocus = false, bool incremental = false}) =>
              boardRows.applySections(
                sections,
                preserveFocus: preserveFocus,
                incremental: incremental,
              ),
      autoFocus: () => boardFocus.maybeAutoFocusBoard(),
      autoFill: ({bool resumeDeferred = false}) =>
          boardPaging.maybeAutoFillBoard(resumeDeferred: resumeDeferred),
    ),
    boardSection,
    catalogSection,
    boardPublication,
    displaySection,
    spotlightSection,
    ready,
  );
  boardPaging = HomeBoardPaging(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      scope: deps.scope,
      rowId: HomeBoardServices.rowId,
      completeDeferredDown: () => boardDeferred.maybeCompleteDeferredDown(),
      refreshBoundSources: () => deps.badges().refreshBoundSources(),
    ),
    boardSection,
    catalogSection,
    boardPublication,
    stages.stageSection,
  );
  boardFocus = HomeBoardFocus(
    (
      mounted: deps.mounted,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      activeTabIndex: () => HomeHeroShellBridge.activeTvTabIndex,
      tabIndex: deps.tabIndex,
      sidebarFocused: () => HomeHeroShellBridge.isTvSidebarFocused(),
      focusSidebar: HomeHeroShellBridge.focusTvSidebar,
      loadMore: boardPaging.loadMoreBoard,
      maybeCompleteDeferredDown: () =>
          boardDeferred.maybeCompleteDeferredDown(),
      deferDownMove:
          ({int rowIndex = -1, String? homeRowId, required int column}) =>
              boardDeferred.deferDownMove(
                rowIndex: rowIndex,
                homeRowId: homeRowId,
                column: column,
              ),
    ),
    boardSection,
    controls,
    continuationSection,
    savedSection,
    displaySection,
    stages.stageSection,
    stages.stageRailsSection,
    spotlightSection,
    heroPreview,
  );
  boardDeferred = HomeBoardDeferred(
    (
      mounted: deps.mounted,
      focusCatalogContinuation: boardFocus.focusCatalogContinuation,
      focusHomeRailAt: boardFocus.focusHomeRailAt,
      focusRow: boardFocus.focusRow,
    ),
    boardSection,
    stages.stageRailsSection,
  );
  boardConfiguration = HomeBoardConfigurationSection(
    ref,
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      bindings: deps.bindings,
    ),
    boardSection,
    boardLoading,
    boardFocus,
    controls,
    displaySection,
    continuationSection,
    continuationLoading,
    heroPreview,
    catalogSection,
    spotlightSection,
    savedSection,
  );
  boardRows = HomeBoardRows(
    (
      setState: deps.setState,
      context: deps.context,
      rowId: HomeBoardServices.rowId,
      classicRowExtent: (context, {CatalogSection? section}) =>
          deps.geometry.classicCatalogRowExtent(context, section: section),
      refreshBoundSources: () => deps.badges().refreshBoundSources(),
    ),
    boardSection,
    boardLoading,
    boardPaging,
    catalogSection,
    displaySection,
    stages.stageSection,
    stages.stageRailsSection,
    stages.stageFavorites,
    spotlightSection,
    heroSection,
    heroPreview,
    heroLive,
  );
  return (
    boardSection: boardSection,
    boardPublication: boardPublication,
    boardLoading: boardLoading,
    boardPaging: boardPaging,
    boardFocus: boardFocus,
    boardDeferred: boardDeferred,
    boardConfiguration: boardConfiguration,
    boardRows: boardRows,
    controls: controls,
  );
}
