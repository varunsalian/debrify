import 'package:flutter/material.dart';

import '../../../widgets/cinema_sources_layout.dart';
import '../models/keyword_results_state.dart';
import '../models/keyword_search_state.dart';
import 'keyword_focus_controller.dart';
import 'keyword_results_projection.dart';
import 'keyword_search_actions.dart';
import 'keyword_search_page.dart';
import 'keyword_selection.dart';
import 'keyword_selection_overlay.dart';
import 'keyword_viewport.dart';
import 'search_result_bindings.dart';

typedef KeywordSearchFrameDeps = ({
  bool Function() isTelevision,
  SearchResultBindings Function() bindings,
  KeywordFocusController Function() focus,
  bool Function() floatingNavigation,
  VoidCallback focusSearchNode,
  VoidCallback freeze,
  ValueChanged<String?> setSourceTab,
});

/// Responsive cinema framing and mobile selection overlay; resources are borrowed.
class KeywordSearchFrame {
  KeywordSearchFrame(
    this._deps,
    this._viewport,
    this._cinemaKey,
    this._actions,
    this._selection,
  );
  final KeywordSearchFrameDeps _deps;
  final KeywordViewport _viewport;
  final GlobalKey<CinemaSourcesLayoutState> _cinemaKey;
  final KeywordSearchActions _actions;
  final KeywordSelection _selection;
  KeywordSearchState get _search => _deps.bindings().search;
  KeywordResultsState get _results => _deps.bindings().results;
  late final _projection = KeywordResultsProjection(() => _results);

  Widget build({
    required bool cinema,
    required bool narrow,
    required Widget content,
  }) {
    return KeywordResultsFrame(
      cinema: cinema,
      narrow: narrow,
      isTelevision: _deps.isTelevision(),
      search: _search,
      results: _results,
      full: _projection.kwFullSet,
      sources: _projection.kwSourceList,
      cinemaKey: _cinemaKey,
      onProviderSelected: (source) {
        _viewport.resetSource();
        _deps.setSourceTab(source);
      },
      onFocusAbove: _deps.focusSearchNode,
      onFocusResults: () => _viewport.focusResults(
        _deps.focus().rows,
        fallback: () => _deps.focus().toolbar.first.requestFocus(),
      ),
      isSourceFocused: () =>
          _viewport.isSourceFocused(_deps.focus().rows, freeze: _deps.freeze),
      selectionOverlay:
          cinema || !narrow || _projection.kwSelectableResults.isEmpty
          ? null
          : KeywordSelectionOverlay(
              selectionMode: _results.selectionMode,
              selectableCount: _projection.kwSelectableResults.length,
              selectedCount: _results.selected.length,
              floatingNavigation: _deps.floatingNavigation(),
              onSelect: _selection.enterKwSelection,
              onCancel: _selection.exitKwSelection,
              onDeselectAll: _selection.deselectAllKw,
              onSelectAll: _selection.selectAllKw,
              onAdd: _actions.openBulkAdd,
            ),
      child: content,
    );
  }
}
