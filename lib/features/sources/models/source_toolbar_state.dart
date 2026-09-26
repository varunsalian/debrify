import '../../../models/torrent_filter_state.dart';

class SourceToolbarState {
  final TorrentFilterState filters;
  final String sortBy;
  final bool sortAsc;
  final String? sourceFilter;

  const SourceToolbarState({
    this.filters = const TorrentFilterState.empty(),
    this.sortBy = 'source',
    this.sortAsc = false,
    this.sourceFilter,
  });

  SourceToolbarState withSource(String? key) => SourceToolbarState(
    filters: filters,
    sortBy: sortBy,
    sortAsc: sortAsc,
    sourceFilter: key,
  );

  SourceToolbarState copyWith({
    TorrentFilterState? filters,
    String? sortBy,
    bool? sortAsc,
  }) => SourceToolbarState(
    filters: filters ?? this.filters,
    sortBy: sortBy ?? this.sortBy,
    sortAsc: sortAsc ?? this.sortAsc,
    sourceFilter: sourceFilter,
  );
}
