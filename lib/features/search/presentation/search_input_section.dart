import '../../../utils/tv_search_focus_handoff.dart';
import 'package:flutter/material.dart';
import '../../../widgets/text_field_suggestions.dart';
import '../models/search_mode.dart';
import 'search_mode_section.dart';
import 'search_focus_controller.dart';
import 'search_mode_toggle.dart';
import 'search_header.dart';
import 'search_query_field.dart';
import 'search_page_shell.dart' as shell;

typedef SearchInputSectionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool mdblistEnabled,
  bool Function() mdblistAuthenticated,
  bool Function() keywordAllowed,
  VoidCallback focusContent,
  VoidCallback focusSidebar,
  VoidCallback fieldFocusContent,
  Widget Function() catalogSourcesButton,
  Widget Function() body,
});

/// Shared header, query field and their local focus resources.
class SearchInputSection {
  SearchInputSection(
    this._deps,
    this._mode,
    this._searchController,
    this._suggestions,
    this._searchSubmitFocus,
  );
  final SearchInputSectionDeps _deps;
  final TvSearchFocusHandoff _searchSubmitFocus;
  final SearchModeSection _mode;
  final TextEditingController _searchController;
  final ValueNotifier<List<TextFieldSuggestion>> _suggestions;
  void focusContent() => _deps.focusContent();
  Widget buildBody() => _deps.body();

  late final searchFocus = SearchFocusController(
    onSourcesVisibilityChanged: () {
      if (_deps.mounted()) _deps.setState(() {});
    },
  );
  FocusNode get searchFocusNode => searchFocus.field;
  // DPAD focus targets for the Catalog / Keyword / Lists selector, so the
  // toggle is reachable with a remote (arrow-up from the search field).
  FocusNode get modeCatalogNode => searchFocus.catalog;
  FocusNode get modeKeywordNode => searchFocus.keyword;
  FocusNode get modeListsNode => searchFocus.lists;
  FocusNode get modeDropdownNode => searchFocus.dropdown;

  /// Whether the unified (non-TV) catalog Sources bar under the field is shown.
  /// Driven by search-field focus with a delayed hide (see
  /// [onSearchFocusForSources]) so a click on the button isn't lost.
  bool get catalogSourcesBarShown => searchFocus.sourcesVisible;

  void focusModeToggle() =>
      searchFocus.focusMode(_mode.mode, compact: useCompactModeMenu);

  bool get useCompactModeMenu => SearchFocusController.useCompactModeMenu(
    listsEnabled: _deps.mdblistEnabled,
    isTelevision: _deps.isTelevision(),
    width: MediaQuery.sizeOf(_deps.context()).width,
  );

  void focusSearchFieldAtEnd() =>
      searchFocus.focusFieldAtEnd(_searchController);

  /// Show/hide the unified catalog Sources bar as the search field gains/loses
  /// focus. The hide is DELAYED: clicking the Sources button blurs the field,
  /// and hiding synchronously would unmount the button before its onTap fires
  /// (the bug where "clicking Sources does nothing"). The delay keeps it up
  /// long enough for the tap; a re-focus within the window cancels the hide.
  void onSearchFocusForSources() => searchFocus.onFieldFocusForSources();

  Widget buildUnifiedCatalogSourcesBar() => shell.buildUnifiedCatalogSourcesBar(
    isTelevision: _deps.isTelevision(),
    dedicatedSearch: _deps.searchMode(),
    show: catalogSourcesBarShown && _mode.mode == SearchMode.catalog,
    sourcesButton: _deps.catalogSourcesButton,
  );
  Widget buildHeader() {
    final context = _deps.context();
    final tv = _deps.isTelevision();
    // On narrow phones the search box + mode selector crowd each other in one
    // row, so stack the selector underneath. When even the stacked three labels
    // cannot fit, [SearchModeToggle] becomes a single dropdown.
    final hasLists = _deps.mdblistEnabled && _deps.mdblistAuthenticated();
    // Reserve the three-mode layout whenever the integration is compiled in,
    // even before the async auth check lands. This avoids a one-frame inline →
    // stacked jump for connected users on medium-width windows.
    final narrowBreakpoint = _deps.mdblistEnabled ? 900.0 : 620.0;
    final narrow = !tv && MediaQuery.of(context).size.width < narrowBreakpoint;
    final compactModeMenu = useCompactModeMenu;

    final field = buildSearchField(tv);
    final toggle = SearchModeToggle(
      mode: _mode.mode,
      isTelevision: tv,
      listsAvailable: hasLists,
      keywordAvailable: _deps.keywordAllowed(),
      fullWidth: narrow,
      compact: compactModeMenu,
      onChanged: _mode.switchMode,
      // Keyboard/DPAD wiring (both desktop + TV): the segments are focusable;
      // up/left leave back to the search field, down drops into the content,
      // select switches mode.
      catalogNode: modeCatalogNode,
      keywordNode: modeKeywordNode,
      listsNode: modeListsNode,
      dropdownNode: modeDropdownNode,
      onLeaveToField: focusSearchFieldAtEnd,
      onLeaveToContent: _deps.focusContent,
    );

    return SearchHeader(
      tv: tv,
      dedicatedSearch: _deps.searchMode(),
      narrow: narrow,
      compactModeMenu: compactModeMenu,
      field: field,
      toggle: toggle,
    );
  }

  /// Centered translucent pill search — mirrors Stremio's search bar (rounded
  /// pill, centered text, a search glyph on the right that becomes a clear ✕).
  Widget buildSearchField(bool tv) => SearchQueryField(
    tv: tv,
    dedicatedSearch: _deps.searchMode(),
    mode: _mode.mode,
    controller: _searchController,
    focusNode: searchFocusNode,
    suggestions: _deps.searchMode() && _mode.mode == SearchMode.catalog
        ? _suggestions
        : null,
    onChanged: _mode.onQueryChanged,
    onSubmitted: _mode.onQuerySubmitted,
    onClear: _mode.clearQuery,
    onFocusMode: focusModeToggle,
    onFocusContent: _deps.fieldFocusContent,
    onFocusSidebar: _deps.focusSidebar,
  );
  void completeSearchSubmitFocus(FocusNode target) {
    _searchSubmitFocus.complete(
      field: searchFocusNode,
      isMounted: _deps.mounted,
      requestFocus: target.requestFocus,
      targetHasFocus: () => target.hasFocus,
    );
  }
}
