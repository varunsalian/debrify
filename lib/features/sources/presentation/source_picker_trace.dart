import '../../../models/torrent.dart';
import '../models/source_results_state.dart';

/// Per-view diagnostic snapshots for callbacks that outlive subscriptions.
/// Borrows read callbacks and a captured sink; owns no provider or UI resource.
class SourcePickerTrace {
  SourcePickerTrace({
    required this.pickerId,
    required this.emit,
    required this.isMounted,
    required this.readResults,
    required this.readSearching,
    required this.readBoundCount,
  });

  final int pickerId;
  final void Function(String, Map<String, Object?>) emit;
  final bool Function() isMounted;
  final SourceResultsState Function() readResults;
  final bool Function() readSearching;
  final int Function() readBoundCount;

  int _disposedBoundCount = 0;
  int _disposedResultCount = 0;
  int _disposedMatchIndex = -1;
  bool _disposedProviderFilter = false;
  bool _disposedFrozen = false;
  bool _disposedSearching = false;

  /// Capture each subscription immediately before its existing close point.
  void retireResults(Torrent? selected) {
    final results = readResults();
    _disposedProviderFilter = results.toolbar.sourceFilter != null;
    _disposedFrozen = results.frozen;
    _disposedResultCount = results.displayed.length;
    _disposedMatchIndex = selected == null
        ? -1
        : results.displayed.indexOf(selected);
  }

  void retireSearch() => _disposedSearching = readSearching();
  void retireBound() => _disposedBoundCount = readBoundCount();

  void log(
    String event, {
    required int search,
    required int? season,
    required int? episode,
    required List<Torrent> visible,
    required Torrent? selected,
    required bool railFocus,
    required bool filterFocus,
    required bool pillFocus,
    required bool television,
    Map<String, Object?> detail = const {},
  }) {
    final mounted = isMounted();
    final results = mounted ? readResults() : null;
    emit(event, {
      'picker': pickerId,
      'search': search,
      'season': season,
      'episode': episode,
      'bound_count': mounted ? readBoundCount() : _disposedBoundCount,
      'results': results?.displayed.length ?? _disposedResultCount,
      'visible': visible.length,
      'match_index': results != null
          ? selected == null
                ? -1
                : results.displayed.indexOf(selected)
          : _disposedMatchIndex,
      'visible_index': selected == null ? -1 : visible.indexOf(selected),
      'searching': mounted ? readSearching() : _disposedSearching,
      'frozen': results?.frozen ?? _disposedFrozen,
      'rail_focus': railFocus,
      'filter_focus': filterFocus,
      'pill_focus': pillFocus,
      'tv': television,
      'provider_filter': results != null
          ? results.toolbar.sourceFilter != null
          : _disposedProviderFilter,
      ...detail,
    });
  }
}
