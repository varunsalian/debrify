import 'package:flutter/widgets.dart';
import '../models/search_mode.dart';
import 'search_result_bindings.dart';
import 'lists_search_section.dart';
import '../../../utils/tv_search_focus_handoff.dart';

typedef SearchModeSectionDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() isTelevision,
  bool Function() keywordAllowed,
  VoidCallback cancelTitleSuggestions,
  VoidCallback restoreHome,
  Future<void> Function(String) runCatalog,
  SearchResultBindings Function() bindings,
  Future<void> Function(String, {bool refocusToolbar}) runKeyword,
  VoidCallback clearKeyword,
  FocusNode Function() searchField,
  VoidCallback exitSelection,
});

/// Owns shared mode/query interactions; feature controllers retain request state.
class SearchModeSection {
  SearchModeSection(
    this._deps,
    this._searchController,
    this._searchSubmitFocus,
    this._lists,
  );
  final SearchModeSectionDeps _deps;
  final TextEditingController _searchController;
  final TvSearchFocusHandoff _searchSubmitFocus;
  final ListsSearchSection _lists;
  SearchMode mode = SearchMode.catalog;

  /// Back on the dedicated Search tab: clear an in-progress search (returning to
  /// the blank prompt) first; a second Back with nothing to clear falls through
  /// to leave the tab. Registered only in [SearchScreen.searchMode].
  bool handleSearchBack() {
    final hasQuery =
        _searchController.text.isNotEmpty ||
        _deps.bindings().catalog.query.isNotEmpty ||
        _deps.bindings().search.query.isNotEmpty ||
        _deps.bindings().lists.query.isNotEmpty;
    if (!hasQuery) return false;
    // Back also drops out of Keyword/Lists mode, so the tab returns to its
    // default Catalog prompt (matches the old overlay-close behaviour).
    // clearQuery rebuilds, so setting the field first is enough.
    mode = SearchMode.catalog;
    clearQuery();
    if (_deps.isTelevision()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_deps.mounted()) _deps.searchField().requestFocus();
      });
    }
    return true;
  }

  void onQueryChanged(String value) {
    _searchSubmitFocus.cancel();
    // Every mode searches on SUBMIT. Because the field is shared, emptying it
    // must invalidate EVERY mode's cached query/result state; otherwise a mode
    // switch can reveal results for text the field no longer contains.
    if (value.trim().isEmpty) {
      clearQuery();
    }
  }

  void onQuerySubmitted(String value) {
    _deps.cancelTitleSuggestions();
    final q = value.trim();
    if (q.isEmpty) {
      _searchSubmitFocus.cancel();
    } else {
      _searchSubmitFocus.arm(enabled: _deps.isTelevision());
    }
    switch (mode) {
      case SearchMode.keyword:
        _deps.runKeyword(q);
        return;
      case SearchMode.catalog:
        if (q.isEmpty) {
          _deps.restoreHome();
        } else {
          _deps.runCatalog(q);
        }
        return;
      case SearchMode.lists:
        if (q.isEmpty) {
          _lists.clearListsSearch();
        } else {
          _lists.runListsSearch(q);
        }
        return;
    }
  }

  void clearQuery() {
    _searchSubmitFocus.cancel();
    _searchController.clear();
    _deps.cancelTitleSuggestions();
    _deps.clearKeyword();
    _lists.disposeListsNodes();
    _lists.listsController.clear();
    _deps.restoreHome();
  }

  void switchMode(SearchMode mode) {
    // Belt for every entry point at once: the keyword surface is gated per
    // profile (catalog search never is).
    if (mode == SearchMode.keyword && !_deps.keywordAllowed()) {
      return;
    }
    if (this.mode == mode) return;
    _deps.cancelTitleSuggestions();
    _deps.setState(() {
      this.mode = mode;
      // Leaving the keyword list drops any in-progress multi-selection.
      _deps.exitSelection();
    });
    // Carry the typed query across: if there's text in the box, run the target
    // mode's search immediately instead of showing the empty state.
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    switch (mode) {
      case SearchMode.keyword:
        if (query != _deps.bindings().search.query) _deps.runKeyword(query);
        return;
      case SearchMode.catalog:
        if (query != _deps.bindings().catalog.query) _deps.runCatalog(query);
        return;
      case SearchMode.lists:
        if (query != _deps.bindings().lists.query) _lists.runListsSearch(query);
        return;
    }
  }
}
