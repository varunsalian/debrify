import '../../../models/torrent.dart';
import 'source_toolbar_state.dart';

/// Full adopted and pending rows, before toolbar projection. Both snapshots
/// retain Torrent identity for saved-source matching and focus restoration.
class SourceResultsState {
  final List<Torrent> displayed;
  final List<Torrent>? pending;
  final bool frozen;
  final SourceToolbarState toolbar;

  SourceResultsState({
    List<Torrent> displayed = const [],
    List<Torrent>? pending,
    this.frozen = false,
    this.toolbar = const SourceToolbarState(),
  }) : displayed = List.unmodifiable(displayed),
       pending = pending == null ? null : List.unmodifiable(pending);

  static String _rowKey(Torrent torrent) =>
      torrent.hasRealInfoHash && torrent.infohash.isNotEmpty
      ? 'h:${torrent.infohash.toLowerCase()}'
      : 'n:${torrent.name}|${torrent.directUrl ?? ''}';

  /// Count pending rows whose keys are absent from the adopted set. This is
  /// not a length delta: a smaller replacement can still contain new rows.
  /// Repeated new keys count per pending row, preserving the existing pill.
  int get pendingNewCount {
    final rows = pending;
    if (rows == null) return 0;
    final shown = {for (final row in displayed) _rowKey(row)};
    return rows.where((row) => !shown.contains(_rowKey(row))).length;
  }
}
