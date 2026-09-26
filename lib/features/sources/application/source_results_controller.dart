import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/torrent.dart';
import '../../../models/torrent_filter_state.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/source_priority.dart';
import '../models/source_presentation_settings.dart';
import '../models/source_results_state.dart';
import '../models/source_toolbar_state.dart';
import '../models/sources_session.dart';
import 'source_result_projection.dart';
import 'source_seasons_dependencies.dart';

final sourceResultsProvider = NotifierProvider.autoDispose
    .family<SourceResultsController, SourceResultsState, SourcesSession>(
      SourceResultsController.new,
      retry: (count, error) => null,
      dependencies: [sourcesSessionActiveProvider],
    );

/// Owns when prepared rows become adopted results. Rendering and focus stay
/// in the view; search generations are checked before offering a batch.
class SourceResultsController extends Notifier<SourceResultsState> {
  SourceResultsController(this.session);
  final SourcesSession session;

  @override
  SourceResultsState build() {
    ref.watch(sourcesSessionActiveProvider(session));
    return SourceResultsState();
  }

  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  void beginSearch() {
    if (!_active) return;
    state = SourceResultsState(toolbar: state.toolbar);
  }

  void freeze() {
    if (!_active || state.frozen) return;
    state = SourceResultsState(
      displayed: state.displayed,
      pending: state.pending,
      frozen: true,
      toolbar: state.toolbar,
    );
  }

  /// Park the full replacement once the user has interacted. A new batch
  /// replaces pending rows, rather than accumulating obsolete pending sets.
  bool bufferIfFrozen(List<Torrent> rows) {
    if (!_active || !state.frozen) return false;
    state = SourceResultsState(
      displayed: state.displayed,
      pending: rows,
      frozen: true,
      toolbar: state.toolbar,
    );
    return true;
  }

  /// Explicit display/adoption, after the view has captured its old focus.
  void display(List<Torrent> rows) {
    if (!_active) return;
    state = SourceResultsState(
      displayed: rows,
      frozen: state.frozen,
      toolbar: state.toolbar,
    );
  }

  void _setToolbar(SourceToolbarState toolbar) {
    state = SourceResultsState(
      displayed: state.displayed,
      pending: state.pending,
      frozen: state.frozen,
      toolbar: toolbar,
    );
  }

  void selectProvider(String? key) {
    if (!_active) return;
    _setToolbar(state.toolbar.withSource(key));
  }

  void setFilters(TorrentFilterState filters) {
    if (!_active) return;
    _setToolbar(state.toolbar.copyWith(filters: filters));
  }

  void selectSort(String value) {
    if (!_active) return;
    _setToolbar(state.toolbar.copyWith(sortBy: value));
  }

  void toggleSortDirection() {
    if (!_active) return;
    _setToolbar(state.toolbar.copyWith(sortAsc: !state.toolbar.sortAsc));
  }

  /// Completion-only reconciliation uses the full authoritative set, including
  /// rows parked behind the pill. Early batches must not clear a selection.
  bool reconcileProvider(List<Torrent> fullSet, Map<String, String> aliases) {
    if (!_active) return false;
    final selected = state.toolbar.sourceFilter;
    if (selected == null ||
        fullSet.any(
          (torrent) =>
              SourcePriority.keyForSource(torrent.source, aliases: aliases) ==
              selected,
        )) {
      return false;
    }
    selectProvider(null);
    return true;
  }

  List<Torrent> project(List<Torrent> rows, SourcePrioritySettings priority) {
    final toolbar = state.toolbar;
    return projectSourceResults(
      rows,
      sourceFilter: toolbar.sourceFilter,
      sourceAliases: priority.aliases,
      isSeries: session.selection.isSeries,
      filters: toolbar.filters,
      sourcePriority: priority.providers,
      sortBy: toolbar.sortBy,
      sortAsc: toolbar.sortAsc,
    );
  }
}
