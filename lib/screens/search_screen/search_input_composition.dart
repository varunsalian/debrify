import 'package:flutter/material.dart';
import '../../utils/tv_search_focus_handoff.dart';
import 'home_board_composition.dart';
import '../../features/home/presentation/home_board_rendering.dart';
import '../../features/home/presentation/home_classic_section.dart';
import '../../features/home/presentation/home_spotlight_section.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import '../../features/discover/presentation/discover_section.dart';
import '../../features/search/presentation/search_input_section.dart';
import '../../features/search/presentation/search_mode_section.dart';
import '../../features/search/presentation/catalog_search_section.dart';
import '../../features/search/presentation/lists_search_section.dart';
import '../../features/search/presentation/search_title_section.dart';
import 'keyword_composition.dart';
import '../../features/search/presentation/lists_search_rows.dart';
import '../../features/search/presentation/search_page_shell.dart'
    show buildSearchModeContent;

typedef SearchInputCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool mdblistEnabled,
  bool Function() mdblistAuthenticated,
  bool Function() keywordAllowed,
  HomeBoardWorkflow Function() board,
  HomeSpotlightSection Function() spotlight,
  HomeClassicSection Function() classic,
  HomeBoardRendering Function() rendering,
});

typedef SearchInputComposition = ({
  SearchInputSection inputSection,
  ListsSearchRows listsRows,
});

/// Constructs shared query input and Lists rows; callbacks keep later Home owners live.
SearchInputComposition createSearchInput(
  SearchInputCompositionDeps deps, {
  required TextEditingController searchController,
  required TvSearchFocusHandoff searchSubmitFocus,
  required SearchModeSection modeSection,
  required CatalogSearchSection catalogSection,
  required DiscoverSection discoverSection,
  required ListsSearchSection listsSection,
  required SearchTitleSection titleSection,
  required KeywordComposition keyword,
}) {
  late final SearchInputSection inputSection;
  late final ListsSearchRows listsRows;

  inputSection = SearchInputSection(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: () => deps.isTelevision(),
      searchMode: () => deps.searchMode(),
      mdblistEnabled: deps.mdblistEnabled,
      mdblistAuthenticated: deps.mdblistAuthenticated,
      keywordAllowed: deps.keywordAllowed,
      focusContent: () => inputSection.searchFocus.focusContent(
        discoverMode: deps.discoverMode(),
        searchMode: deps.searchMode(),
        isTelevision: deps.isTelevision(),
        mode: modeSection.mode,
        discoverSource: discoverSection.discSourceNode,
        keywordToolbar: keyword.keywordSection.kwToolbarVisible
            ? keyword.keywordSection.kwToolbarNodes.first
            : null,
        listsResult:
            listsSection.listsResults.isNotEmpty &&
                listsSection.listsNodes.isNotEmpty
            ? listsSection.listsNodes.first
            : null,
        catalogResult:
            catalogSection.catalogQuery.isNotEmpty &&
                deps.board().boardSection.rowNodes.isNotEmpty &&
                deps.board().boardSection.rowNodes.first.isNotEmpty
            ? deps.board().boardSection.rowNodes.first.first
            : null,
        focusCatalogShelf: deps.spotlight().spotlightKey.currentState == null
            ? null
            : () => deps.spotlight().spotlightKey.currentState!.focusShelf(0),
        topBoardNode: () => deps.board().boardFocus.topBoardFocusNode(),
        loading: deps.board().boardSection.loading,
        focusSidebar: HomeHeroShellBridge.focusTvSidebar,
      ),
      focusSidebar: HomeHeroShellBridge.focusTvSidebar,
      fieldFocusContent: () {
        if (keyword.keywordSection.kwSourcesButtonVisible) {
          keyword.keywordSection.kwSourcesBtnFocus.requestFocus();
        } else if (catalogSection.catalogSourcesButtonVisible) {
          catalogSection.catalogSourcesBtnFocus.requestFocus();
        } else {
          inputSection.focusContent();
        }
      },
      catalogSourcesButton: () =>
          catalogSection.catalogSourcesButton(deps.context()),
      body: () => buildSearchModeContent(
        mode: modeSection.mode,
        catalogSearching: catalogSection.catalogSearching,
        catalogEmpty: deps.board().boardSection.sections.isEmpty,
        dedicatedSearch: deps.searchMode(),
        queryEmpty: catalogSection.catalogQuery.isEmpty,
        keyword: () => keyword.keywordRows.buildKeyword(deps.context()),
        lists: () => listsRows.build(deps.context()),
        prompt: () => catalogSection.buildSearchPrompt(deps.context()),
        board: () => deps.rendering().buildBoard(),
      ),
    ),
    modeSection,
    searchController,
    titleSection.presentation.suggestions,
    searchSubmitFocus,
  );
  listsRows = ListsSearchRows((
    state: () => listsSection.listsState,
    nodes: () => listsSection.listsNodes,
    isTelevision: () => deps.isTelevision(),
    posterWidth: (context) => deps.classic().railPosterW(context),
    header: (onSeeAll) => deps.classic().railHeader(
      title: 'MDBList Lists',
      tag: 'LISTS',
      onSeeAll: onSeeAll,
    ),
    message: (icon, title, body) => deps.rendering().message(icon, title, body),
    open: listsSection.openListsResult,
    openSeeAll: listsSection.openListsSeeAll,
    focusSidebar: HomeHeroShellBridge.focusTvSidebar,
    onUp: () => deps.board().boardFocus.leaveBoardTop(),
  ));
  return (inputSection: inputSection, listsRows: listsRows);
}
