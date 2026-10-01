import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/mdblist_list_choice.dart';
import '../../utils/tv_search_focus_handoff.dart';
import '../../features/discover/presentation/discover_section.dart';
import 'home_board_presentation_composition.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_hero_composition.dart';
import '../../features/home/presentation/home_hero_shell_bridge.dart';
import 'keyword_composition.dart';
import '../../features/search/presentation/keyword_return.dart';
import '../../features/search/presentation/keyword_search_actions.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import '../../features/search/presentation/keyword_selection.dart';
import 'search_mode_composition.dart';
import '../../features/search/presentation/search_mode_section.dart';
import 'search_title_composition.dart';
import 'search_input_composition.dart';
import 'search_session_lifecycle.dart';
import '../../features/search/presentation/lists_navigation.dart';

typedef SearchPresentationDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  SearchSessionLifecycle Function() session,
  HomeBoardPresentation Function() board,
  HomeCatalogPresentation Function() catalog,
  HomeHeroComposition Function() hero,
  bool Function() keywordAllowed,
  bool Function() floatingNavigation,
  bool mdblistEnabled,
});

typedef SearchPresentation = ({
  KeywordComposition keyword,
  KeywordReturn returning,
  SearchModeComposition modes,
  SearchInputComposition input,
});

/// Wires the keyword, mode and query owners without starting search or restoring state.
SearchPresentation createSearchPresentation(
  WidgetRef ref,
  SearchPresentationDeps deps, {
  required TextEditingController searchController,
  required TvSearchFocusHandoff submitFocus,
  required DiscoverSection discover,
  required KeywordSearchActions Function(KeywordSearchSection, KeywordSelection)
  createKeywordActions,
  required void Function(MdblistListChoice) trackOpen,
  required ListsNavigation Function() createNavigation,
  required SearchTitleComposition Function(SearchModeSection Function())
  createTitles,
}) {
  late final KeywordComposition keyword;
  late final KeywordReturn returning;
  late final SearchModeComposition modes;
  late final SearchInputComposition input;

  // Discriminates the three route variants so preserved keyword results return
  // only to the same kind of tab.
  String variant() => deps.searchMode()
      ? 'search'
      : deps.discoverMode()
      ? 'discover'
      : 'board';
  keyword = createKeywordSearch(ref, (
    mounted: deps.mounted,
    setState: deps.setState,
    context: deps.context,
    isTelevision: deps.isTelevision,
    session: () => deps.session(),
    mode: () => modes.mode,
    input: () => input.inputSection,
    board: () => deps.board().rendering.rendering,
    floatingNavigation: deps.floatingNavigation,
    sidebar: HomeHeroShellBridge.focusTvSidebar,
    createActions: createKeywordActions,
  ), submitFocus);
  returning = KeywordReturn(
    (
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      keywordAllowed: deps.keywordAllowed,
      variant: variant,
      mode: () => modes.mode.mode,
      setMode: (mode) => modes.mode.mode = mode,
      repository: () => deps.session().keywordSnapshots,
      bindings: () => deps.session().searchResultBindings,
      focus: () => keyword.keywordSection.keywordFocus,
      syncTabs: keyword.keywordSection.syncKwTabNodes,
    ),
    searchController,
    keyword.keywordSection.keywordViewport,
  );
  modes = createSearchModes(
    ref,
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      session: () => deps.session(),
      input: () => input.inputSection,
      board: () => deps.board().workflow,
      keywordAllowed: deps.keywordAllowed,
      mdblistEnabled: deps.mdblistEnabled,
      trackOpen: trackOpen,
      createNavigation: createNavigation,
    ),
    searchController: searchController,
    submitFocus: submitFocus,
    keyword: keyword,
    createTitles: createTitles,
  );
  input = createSearchInput(
    (
      mounted: deps.mounted,
      setState: deps.setState,
      context: deps.context,
      isTelevision: deps.isTelevision,
      searchMode: deps.searchMode,
      discoverMode: deps.discoverMode,
      mdblistEnabled: deps.mdblistEnabled,
      mdblistAuthenticated: () =>
          deps.catalog().integrations.isMdblistAuthenticated,
      keywordAllowed: deps.keywordAllowed,
      board: () => deps.board().workflow,
      spotlight: () => deps.hero().spotlightSection,
      geometry: () => deps.board().geometry,
      rendering: () => deps.board().rendering.rendering,
    ),
    searchController: searchController,
    searchSubmitFocus: submitFocus,
    modeSection: modes.mode,
    catalogSection: modes.catalog,
    discoverSection: discover,
    listsSection: modes.lists,
    titleSection: modes.title,
    keyword: keyword,
  );
  return (keyword: keyword, returning: returning, modes: modes, input: input);
}
