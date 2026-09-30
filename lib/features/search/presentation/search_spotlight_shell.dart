import 'package:flutter/material.dart';
import '../../home/application/home_layout_policy.dart';
import '../models/search_mode.dart';
import 'search_page_shell.dart';
import 'search_input_section.dart';
import 'search_mode_section.dart';
import 'catalog_search_section.dart';

typedef SearchSpotlightShellDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  String Function() rawStyle,
  bool Function() loading,
  bool Function() hasHero,
});

/// Off-TV Spotlight search-sheet eligibility, focus latch and shell rendering.
class SearchSpotlightShell {
  SearchSpotlightShell(
    this._deps,
    this._searchController,
    this._inputSection,
    this._modeSection,
    this._catalogSection,
  );
  final SearchSpotlightShellDeps _deps;
  final TextEditingController _searchController;
  final SearchInputSection _inputSection;
  final SearchModeSection _modeSection;
  final CatalogSearchSection _catalogSection;

  // ── Off-TV Spotlight shell state ─────────────────────────────────────────
  //
  // Four separate questions, deliberately not one predicate (the sheet is a
  // latched state machine — see SPOTLIGHT_RESPONSIVE_PLAN.md):
  //  • [spotlightSelected] — the resolved pref says Spotlight.
  //  • [spotlightShellActive] — this Home instance renders the shell branch
  //    (either of its two states) instead of the plain classic Column.
  //  • [sheetForced] — search state that REQUIRES the header on screen.
  //  • [searchSheetOpen] — the latch. Set by the search button, by field
  //    focus, and silently whenever [sheetForced] is observed true; cleared
  //    only by the explicit close/back reset. The latch is what stops the
  //    header collapsing under a focused field when its force condition
  //    momentarily clears (deleting the last character of a query).

  /// The stored style, resolved for this platform, is Spotlight. Off-TV only.
  bool get spotlightSelected =>
      !_deps.isTelevision() &&
      effectiveOffTvHomeStyle(_deps.rawStyle()) == 'spotlight';

  /// Whether the off-TV Home renders the Spotlight shell branch. While the
  /// selected layout is loading, retain this branch so a newly mounted Home
  /// cannot flash Classic's persistent search bar before its hero arrives.
  /// After loading, the hero guard still matters: CW/favourites-only content
  /// would otherwise render a large empty hero.
  bool get spotlightShellActive =>
      !_deps.searchMode() &&
      !_deps.discoverMode() &&
      shouldUseOffTvSpotlightShell(
        rawStyle: _deps.rawStyle(),
        loading: _deps.loading(),
        hasHero: _deps.hasHero(),
      );

  /// Search state that forces the header/sheet to be visible. Typing is
  /// covered by the focus latch (one can only type while the field is
  /// focused, and focus latches [searchSheetOpen]); this covers the states
  /// that arrive WITHOUT the field being touched: the async keyword-default
  /// restore, preserved keyword results, a committed catalog search, or the
  /// dedicated Lists surface.
  bool get sheetForced =>
      _modeSection.mode != SearchMode.catalog ||
      _catalogSection.catalogQuery.isNotEmpty ||
      _catalogSection.catalogSearching ||
      // Belt to the focus latch's braces: interactive typing always comes
      // through a focused field, but autofill or a programmatic controller
      // write would not — and text on screen must force the header that
      // renders it.
      _searchController.text.isNotEmpty;

  /// The sheet latch. See the block comment above.
  late final searchSheet = SpotlightSearchSheet(
    field: _inputSection.searchFocusNode,
    isForced: () => sheetForced,
    hasText: () => _searchController.text.isNotEmpty,
    isSpotlightSelected: () => spotlightSelected,
    resetSearch: () {
      // Mode changes before clearing requests, results and the field.
      _modeSection.mode = SearchMode.catalog;
      _modeSection.clearQuery();
    },
    rebuild: _deps.setState,
    isCurrent: () => _deps.mounted(),
  );
  bool get searchSheetOpen => searchSheet.isOpen;

  Widget buildSpotlightShell() {
    // Preserve the build-time latch for async default-mode/query restoration.
    searchSheet.observeForcedState();
    return buildSpotlightSearchShell(
      context: _deps.context(),
      sheetOpen: searchSheetOpen,
      canClose: !sheetForced && _searchController.text.isEmpty,
      onClose: searchSheet.close,
      onOpen: searchSheet.open,
      header: _inputSection.buildHeader,
      sourcesBar: _inputSection.buildUnifiedCatalogSourcesBar,
      body: _inputSection.buildBody,
    );
  }
}
