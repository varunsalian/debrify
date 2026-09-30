import 'dart:async';
import 'package:flutter/material.dart';
import '../../../widgets/cinema_sources_layout.dart';
import '../models/keyword_search_state.dart';
import '../models/keyword_results_state.dart';
import 'search_result_bindings.dart';
import 'keyword_focus_controller.dart';
import 'keyword_viewport.dart';
import 'keyword_results_projection.dart';
import 'keyword_search_actions.dart';
import 'keyword_selection.dart';
import 'keyword_search_page.dart';
import '../../../models/source_appearance.dart';
import '../../../theme/app_theme_scope.dart';
import 'keyword_search_dialogs.dart';
import 'keyword_search_frame.dart';
import 'keyword_results_list.dart';
import 'keyword_source_tabs.dart';
import 'keyword_toolbar.dart';
import 'catalog_search_prompt.dart';

typedef KeywordSearchRowsDeps = ({
  bool Function() mounted,
  bool Function() isTelevision,
  SearchResultBindings Function() bindings,
  KeywordFocusController Function() focus,
  SourceAppearance Function() appearance,
  Widget Function(IconData, String, String, {VoidCallback? onRetry}) message,
  VoidCallback focusSearch,
  VoidCallback focusSidebar,
  VoidCallback focusAboveResults,
  VoidCallback freeze,
  VoidCallback adopt,
  ValueChanged<String?> setSourceTab,
});

/// Keyword page, toolbar, source tabs and result rows, with the same widget tree.
class KeywordSearchRows {
  KeywordSearchRows(
    this._deps,
    this._viewport,
    this._actions,
    this._dialogs,
    this._selection,
    this._frame,
  );
  final KeywordSearchRowsDeps _deps;
  final KeywordViewport _viewport;
  final KeywordSearchActions _actions;
  final KeywordSearchDialogs _dialogs;
  final KeywordSelection _selection;
  final KeywordSearchFrame _frame;
  KeywordSearchState get _search => _deps.bindings().search;
  KeywordResultsState get _results => _deps.bindings().results;
  late final _projection = KeywordResultsProjection(() => _results);
  Widget buildKeyword(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => _buildKeywordContent(
      context,
      cinema: useCinemaSourcesLayout(
        constraints,
        isTelevision: _deps.isTelevision(),
      ),
    ),
  );

  Widget _buildKeywordContent(BuildContext context, {required bool cinema}) =>
      KeywordSearchPage(
        search: _search,
        isTelevision: _deps.isTelevision(),
        messageBuilder: _deps.message,
        sourcesBuilder: (_) => _kwSourcesButton(context),
        resultsBuilder: (_) => _buildKeywordResults(context, cinema: cinema),
      );

  Widget _buildKeywordResults(BuildContext context, {required bool cinema}) {
    final narrow =
        !_deps.isTelevision() && MediaQuery.of(context).size.width < 600;
    _viewport.restoreAfterLayout(
      hasResults: _results.results.isNotEmpty,
      isCurrent: _deps.mounted,
    );
    final content = Column(
      children: [
        // Tabs are suppressed during multi-select: switching source mid-select
        // would hide checked rows under the user while "Add · N" still counts
        // them (matching the toolbar's own selection lock-out).
        if (!cinema && _projection.kwTabsVisible && !_results.selectionMode)
          _kwSourceTabs(),
        _buildKeywordToolbar(floatingSelect: narrow),
        if (_search.searching && !cinema) const KeywordSearchingStrip(),
        if (_deps.bindings().cache.cachedOnly && _results.all.isNotEmpty)
          _kwCachedOnlyNotice(context),
        Expanded(
          child: KeywordResultsList(
            state: _results,
            cache: _deps.bindings().cache.badges,
            appearance: _deps.appearance(),
            isTelevision: _deps.isTelevision(),
            cinema: cinema,
            scrollController: _viewport.scroll,
            focusNodes: _deps.focus().rows,
            onFreeze: _deps.freeze,
            onFocusAbove: _deps.focusAboveResults,
            onCopy: (torrent) => unawaited(_actions.copyKwLink(torrent)),
            onActivate: _actions.activateKeywordResult,
            onLongPress: _actions.longPressKeywordResult,
            emptyBuilder: (_) => _deps.message(
              Icons.search_off_rounded,
              _results.all.isEmpty ? 'No results' : 'No matches',
              _results.all.isEmpty
                  ? 'Nothing found for "${_search.query}". Try different '
                        'keywords or enable more sources.'
                  : 'No results match your filters. Adjust or clear them.',
            ),
            // Never renumber selected rows by adopting arrivals mid-selection.
            pendingResults:
                _projection.kwPendingNewCount > 0 && !_results.selectionMode
                ? _kwNewResultsPill()
                : null,
          ),
        ),
      ],
    );

    return _frame.build(cinema: cinema, narrow: narrow, content: content);
  }

  /// Standalone "Sources" pill shown in the pre-search keyword state so users
  /// can pick which trackers are queried before typing a query.
  Widget _kwSourcesButton(BuildContext context) => buildSearchSourcesButton(
    context,
    focusNode: _deps.focus().sources,
    onOpen: _dialogs.openKeywordSources,
    onUp: _deps.focusSearch,
    onSidebar: _deps.focusSidebar,
  );

  /// Horizontal source tabs (All / per-source with counts) above the toolbar —
  /// the fast single-select layer on top of the Providers multi-select. Only
  /// built when [_projection.kwTabsVisible] (2+ sources). Derives from [_projection.kwFullSet]:
  /// counts tick and new source pills appear live even while the rows below
  /// are frozen behind the pill (activating any tab folds the parked set in
  /// first, so what a tab press shows is always the complete picture). DPAD:
  /// left/right across tabs, up to the search field, down into the toolbar,
  /// select to activate.
  Widget _kwSourceTabs() => KeywordSourceTabs(
    sources: _projection.kwSourceList,
    full: _projection.kwFullSet,
    selectedSource: _results.sourceTab,
    focusNodes: _deps.focus().tabs,
    onKey: _deps.focus().handleTabKey,
    onChanged: _deps.setSourceTab,
  );

  /// DPAD/keyboard handling for a focused source tab: select activates,
  /// left/right move between tabs (left edge escapes to the sidebar), up
  /// returns to the search field, down drops into the toolbar pills.
  /// The "+N new results" pill: tap (or OK on TV) folds the parked arrivals
  /// into the list; DOWN returns to the rows, UP reaches the toolbar.
  Widget _kwNewResultsPill() => KeywordNewResultsPill(
    count: _projection.kwPendingNewCount,
    focusNode: _deps.focus().arrivals,
    onAdopt: _deps.adopt,
    onFocusResults: () {
      if (_deps.focus().rows.isNotEmpty) {
        _deps.focus().rows.first.requestFocus();
      }
    },
    onFocusToolbar: () => _deps.focus().toolbar.first.requestFocus(),
  );

  /// [floatingSelect] true on small screens where the multi-select entry is a
  /// floating FAB + bar (Home-style) rather than a toolbar pill — so the
  /// toolbar stays Sort/Filters/Sources and never swaps to selection controls.
  Widget _buildKeywordToolbar({bool floatingSelect = false}) => KeywordToolbar(
    selectionMode: _results.selectionMode,
    floatingSelect: floatingSelect,
    selectableCount: _projection.kwSelectableResults.length,
    selectedCount: _results.selected.length,
    // Every facet counts, including size-only and dynamic-range-only filters.
    filterCount:
        _results.filters.qualities.length +
        _results.filters.ripSources.length +
        _results.filters.languages.length +
        _results.filters.sizes.length +
        _results.filters.dynamicRanges.length,
    showProviderFilter: _projection.kwHasProviderFilter,
    providerFilterCount: _projection.kwProviderFilterActive,
    sortLabel: _sortLabel(_results.sort),
    focusNodes: _deps.focus().toolbar,
    onKey: _deps.focus().handleToolbarKey,
    onCancel: _selection.exitKwSelection,
    onDeselectAll: _selection.deselectAllKw,
    onSelectAll: _selection.selectAllKw,
    onAdd: _actions.openBulkAdd,
    onSort: _dialogs.openKeywordSort,
    onFilters: _dialogs.openKeywordFilters,
    onProviders: _dialogs.openKeywordProviders,
    onSources: _dialogs.openKeywordSources,
    onSelect: _selection.enterKwSelection,
  );

  String _sortLabel(String s) =>
      const {
        'relevance': 'Relevance',
        'seeders': 'Seeders',
        'size': 'Size',
        'date': 'Date',
        'name': 'Name',
      }[s] ??
      s;

  /// Info banner shown above the results when the list is narrowed to
  /// TorBox-cached torrents. Mirrors the old `_buildTorboxCachedOnlyNotice`.
  Widget _kwCachedOnlyNotice(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
        borderRadius: app.shape.br(8),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF38BDF8),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing Torbox cached results only. Disable "Check Torbox cache '
              'during searches" in Torbox settings to see every result.',
              style: TextStyle(
                fontSize: 12,
                color: app.fade(app.core.tx, 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
