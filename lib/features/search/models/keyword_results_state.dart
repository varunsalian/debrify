import '../../../models/torrent.dart';
import '../../../models/torrent_filter_state.dart';
import 'keyword_providers.dart';

/// Displayed results can intentionally lag the full pending result while the
/// user interacts. Containers are immutable; focus nodes belong to the view.
class KeywordResultsState {
  final List<Torrent> all;
  final List<Torrent> results;
  final List<Torrent>? pending;
  final bool frozen;
  final TorrentFilterState filters;
  final String sort;
  final bool sortAscending;
  final KeywordProviders providers;
  final String? sourceTab;
  final bool selectionMode;
  final Set<String> selected;

  KeywordResultsState({
    List<Torrent> all = const [],
    List<Torrent> results = const [],
    List<Torrent>? pending,
    this.frozen = false,
    this.filters = const TorrentFilterState.empty(),
    this.sort = 'relevance',
    this.sortAscending = false,
    this.providers = const KeywordProviders.empty(),
    this.sourceTab,
    this.selectionMode = false,
    Set<String> selected = const {},
  }) : all = List.unmodifiable(all),
       results = List.unmodifiable(results),
       pending = pending == null ? null : List.unmodifiable(pending),
       selected = Set.unmodifiable(selected);

  const KeywordResultsState._({
    required this.all,
    required this.results,
    required this.pending,
    required this.frozen,
    required this.filters,
    required this.sort,
    required this.sortAscending,
    required this.providers,
    required this.sourceTab,
    required this.selectionMode,
    required this.selected,
  });

  KeywordResultsState copyWith({
    List<Torrent>? all,
    List<Torrent>? results,
    List<Torrent>? pending,
    bool clearPending = false,
    bool? frozen,
    TorrentFilterState? filters,
    String? sort,
    bool? sortAscending,
    KeywordProviders? providers,
    String? sourceTab,
    bool clearSourceTab = false,
    bool? selectionMode,
    Set<String>? selected,
  }) => KeywordResultsState._(
    all: all == null ? this.all : List.unmodifiable(all),
    results: results == null ? this.results : List.unmodifiable(results),
    pending: clearPending
        ? null
        : pending == null
        ? this.pending
        : List.unmodifiable(pending),
    frozen: frozen ?? this.frozen,
    filters: filters ?? this.filters,
    sort: sort ?? this.sort,
    sortAscending: sortAscending ?? this.sortAscending,
    providers: providers ?? this.providers,
    sourceTab: clearSourceTab ? null : sourceTab ?? this.sourceTab,
    selectionMode: selectionMode ?? this.selectionMode,
    selected: selected == null ? this.selected : Set.unmodifiable(selected),
  );
}
