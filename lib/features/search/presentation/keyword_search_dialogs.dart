import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent_filter_state.dart';
import '../../../widgets/torrent_filters_sheet.dart';
import '../application/keyword_results_controller.dart';
import '../models/keyword_results_state.dart';
import '../models/search_session.dart';
import 'keyword_providers_dialog.dart';
import 'keyword_sources_dialog.dart';
import 'search_result_bindings.dart';

typedef KeywordSearchDialogsDeps = ({
  BuildContext Function() context,
  bool Function() mounted,
  SearchSession Function() session,
  SearchResultBindings Function() bindings,
  List<FocusNode> Function() toolbarNodes,
  VoidCallback freezeAndAdopt,
  VoidCallback syncResults,
  Future<void> Function(String, {bool refocusToolbar}) runKeyword,
});

/// Dialog actions retain live sort/filter updates and the original return focus.
class KeywordSearchDialogs {
  KeywordSearchDialogs(this._ref, this._deps);
  final WidgetRef _ref;
  final KeywordSearchDialogsDeps _deps;
  KeywordResultsController get _resultsController =>
      _ref.read(keywordResultsProvider(_deps.session()).notifier);
  KeywordResultsState get _results => _deps.bindings().results;
  Future<void> openKeywordFilters() async {
    final context = _deps.context();
    // Toolbar use is a deliberate reshuffle: stop live streaming updates and
    // fold parked arrivals in, so the dialog operates on the complete set.
    _deps.freezeAndAdopt();
    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(initialState: _results.filters),
      ),
    );
    if (result == null || !context.mounted) return;
    _resultsController.setFilters(result);
    _deps.syncResults();
  }

  /// Multi-select dialog to filter keyword results by their source, grouped into
  /// Direct and Torrent providers. Ported from the old screen's stream-type
  /// dropdowns, adapted to the new toolbar/dialog idiom.
  Future<void> openKeywordProviders() async {
    final context = _deps.context();
    _deps.freezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (_) => KeywordProvidersDialog(
        session: _deps.session(),
        onChanged: () {
          if (_deps.mounted()) _deps.syncResults();
        },
      ),
    );
  }

  Future<void> openKeywordSort() async {
    final context = _deps.context();
    // Sorting mid-stream over a shifting set would be meaningless — freeze
    // and fold parked arrivals in first.
    _deps.freezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            // Picking a field resets direction to that field's natural default;
            // the toggle below can then flip it. Changes apply live.
            void applyField(String value) {
              setLocal(() {
                _resultsController.setSort(value);
              });
              _deps.syncResults();
            }

            void applyDir(bool asc) {
              setLocal(() => _resultsController.setSortAscending(asc));
              _deps.syncResults();
            }

            Widget tile(String value, String label) => ListTile(
              dense: true,
              title: Text(label),
              trailing: _results.sort == value
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => applyField(value),
            );

            final dirEnabled = _results.sort != 'relevance';
            return AlertDialog(
              backgroundColor: scheme.surfaceContainerHigh,
              title: const Text('Sort by'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tile('relevance', 'Relevance'),
                  tile('seeders', 'Seeders'),
                  tile('size', 'Size'),
                  tile('date', 'Date added'),
                  tile('name', 'Name'),
                  const Divider(height: 12),
                  // Direction toggle — disabled for 'relevance' (engine order).
                  Opacity(
                    opacity: dirEnabled ? 1 : 0.4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Direction')),
                          ToggleButtons(
                            isSelected: [
                              !_results.sortAscending,
                              _results.sortAscending,
                            ],
                            onPressed: dirEnabled
                                ? (i) => applyDir(i == 1)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            constraints: const BoxConstraints(
                              minHeight: 34,
                              minWidth: 46,
                            ),
                            children: const [
                              Icon(Icons.arrow_downward_rounded, size: 18),
                              Icon(Icons.arrow_upward_rounded, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> openKeywordSources() async {
    final context = _deps.context();
    // If the remote was on the toolbar, the re-search below unmounts it (loading
    // spinner) and would strand DPAD focus — restore it at the FIRST streamed
    // paint (see _keywordSection.kwRefocusToolbar), when the toolbar remounts. A completion
    // refocus would arrive seconds after rows became interactive and could
    // yank the remote off a row the user had already navigated to.
    final fromToolbar = _deps.toolbarNodes().any((n) => n.hasFocus);
    await showDialog<void>(
      context: context,
      builder: (_) => KeywordSourcesDialog(session: _deps.session()),
    );
    if (!context.mounted || _deps.bindings().search.query.isEmpty) return;
    // Re-search with the new enabled set.
    await _deps.runKeyword(
      _deps.bindings().search.query,
      refocusToolbar: fromToolbar,
    );
  }
}
