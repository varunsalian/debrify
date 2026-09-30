import 'search_title_composition.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/mdblist_list_choice.dart';
import '../../../utils/tv_search_focus_handoff.dart';
import '../../discover/presentation/discover_shell_bridge.dart';
import '../../home/presentation/home_board_composition.dart';
import '../../home/presentation/home_hero_shell_bridge.dart';
import '../models/search_mode.dart';
import 'lists_search_section.dart';
import 'lists_navigation.dart';
import 'search_title_section.dart';
import 'catalog_search_section.dart';
import 'search_mode_section.dart';
import 'search_input_section.dart';
import 'search_session_lifecycle.dart';
import 'keyword_composition.dart';

typedef SearchModeCompositionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  SearchSessionLifecycle Function() session,
  SearchInputSection Function() input,
  HomeBoardWorkflow Function() board,
  bool Function() keywordAllowed,
  ListsNavigation Function() createNavigation,
  void Function(MdblistListChoice) trackOpen,
  bool mdblistEnabled,
});

typedef SearchModeComposition = ({
  ListsSearchSection lists,
  SearchTitleSection title,
  CatalogSearchSection catalog,
  SearchModeSection mode,
});

/// Constructs Lists, title, catalog and mode owners in their original order.
SearchModeComposition createSearchModes(
  WidgetRef ref,
  SearchModeCompositionDeps deps, {
  required TextEditingController searchController,
  required TvSearchFocusHandoff submitFocus,
  required KeywordComposition keyword,
  required SearchTitleComposition Function(SearchModeSection Function())
  createTitles,
}) {
  late final ListsSearchSection lists;
  late final CatalogSearchSection catalog;
  late final SearchModeSection mode;
  lists = ListsSearchSection(ref, (
    session: () => deps.session().searchSession,
    bindings: () => deps.session().searchResultBindings,
    mounted: deps.mounted,
    setState: deps.setState,
    isTelevision: deps.isTelevision,
    mdblistEnabled: deps.mdblistEnabled,
    cancelSubmitFocus: submitFocus.cancel,
    completeSubmitFocus: (target) =>
        deps.input().completeSearchSubmitFocus(target),
    trackOpen: deps.trackOpen,
    handoff: DiscoverShellBridge.openMdblistList,
    context: deps.context,
    createNavigation: deps.createNavigation,
  ));
  final titles = createTitles(() => mode);
  catalog = CatalogSearchSection(ref, (
    session: () => deps.session().searchSession,
    bindings: () => deps.session().searchResultBindings,
    mounted: deps.mounted,
    isTelevision: deps.isTelevision,
    searchField: () => deps.input().searchFocusNode,
    applySections:
        (sections, {bool preserveFocus = false, bool incremental = false}) =>
            deps.board().boardRows.applySections(
              sections,
              preserveFocus: preserveFocus,
              incremental: incremental,
            ),
    firstResult: () =>
        deps.board().boardSection.rowNodes.isNotEmpty &&
            deps.board().boardSection.rowNodes.first.isNotEmpty
        ? deps.board().boardSection.rowNodes.first.first
        : null,
    completeSubmitFocus: (target) =>
        deps.input().completeSearchSubmitFocus(target),
    cancelSubmitFocus: submitFocus.cancel,
    catalogModeActive: () =>
        mode.mode == SearchMode.catalog && deps.searchMode(),
    focusSearch: () => deps.input().focusSearchFieldAtEnd(),
    focusSidebar: HomeHeroShellBridge.focusTvSidebar,
    context: deps.context,
  ));
  mode = SearchModeSection(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      isTelevision: deps.isTelevision,
      keywordAllowed: deps.keywordAllowed,
      cancelTitleSuggestions: titles.section.cancelTitleSuggestions,
      restoreHome: () => deps.board().boardRows.restoreHome(),
      runCatalog: catalog.runCatalogSearch,
      bindings: () => deps.session().searchResultBindings,
      runKeyword: keyword.keywordSection.runKeyword,
      clearKeyword: keyword.keywordSection.clearKeywordSearch,
      searchField: () => deps.input().searchFocusNode,
      exitSelection: keyword.keywordSelection.exitKwSelection,
    ),
    searchController,
    submitFocus,
    lists,
  );
  return (lists: lists, title: titles.section, catalog: catalog, mode: mode);
}
