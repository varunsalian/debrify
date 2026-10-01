import '../data/keyword_defaults_repository.dart';
import 'search_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../../../models/torrent_filter_state.dart';
import '../data/keyword_search_repository.dart';
import '../models/keyword_results_state.dart';
import '../models/search_session.dart';
import 'keyword_cache_controller.dart';
import 'keyword_filter.dart';
import 'keyword_sort.dart';
import 'search_session_provider.dart';
import 'keyword_providers.dart';

final keywordResultsProvider = NotifierProvider.autoDispose
    .family<KeywordResultsController, KeywordResultsState, SearchSession>(
      KeywordResultsController.new,
      retry: (count, error) => null,
    );

/// Owns the user's displayed projection and choices. Engine publications and
/// deliberate interactions are explicit actions, so cache badge notifications
/// cannot reorder rows or implicitly adopt arrivals.
class KeywordResultsController extends Notifier<KeywordResultsState> {
  KeywordResultsController(this.session);
  final SearchSession session;
  late KeywordSearchRepository _repository;
  bool _initialized = false;
  late KeywordDefaultsRepository _defaults;
  int _defaultsGeneration = 0;

  @override
  KeywordResultsState build() {
    _repository = ref.watch(keywordSearchRepositoryProvider(session));
    _defaults = ref.watch(keywordDefaultsRepositoryProvider(session));
    ref.onDispose(() => _defaultsGeneration++);
    final active = ref.watch(searchSessionActiveProvider(session));
    final initial = !_initialized && active
        ? session.initialKeywordResults
        : null;
    _initialized = true;
    return initial ?? KeywordResultsState();
  }

  bool get _current => ref.mounted && _repository.isCurrent;

  /// Explicit startup action. A late read may filter an already completed
  /// search, but must not replace nonempty restored/user-selected filters.
  Future<bool> loadDefaults() async {
    if (!_current || !_defaults.isCurrent) return false;
    final generation = ++_defaultsGeneration;
    try {
      final filters = await _defaults.load();
      if (!_current ||
          !_defaults.isCurrent ||
          generation != _defaultsGeneration ||
          filters.isEmpty ||
          !state.filters.isEmpty) {
        return false;
      }
      _publish(state.copyWith(filters: filters));
      return true;
    } catch (_) {
      // Defaults have always been non-fatal, with no automatic retry.
      return false;
    }
  }

  void begin() {
    if (!_current) return;
    state = state.copyWith(
      frozen: false,
      clearPending: true,
      clearSourceTab: true,
      providers: const KeywordProviders.empty(),
      selectionMode: false,
      selected: {},
    );
  }

  void clear() {
    state = state.copyWith(
      all: [],
      results: [],
      clearPending: true,
      selectionMode: false,
      selected: {},
    );
  }

  KeywordResultsState _withRows(
    KeywordResultsState current,
    List<Torrent> rows,
  ) => current.copyWith(
    all: rows,
    providers: reconcileKeywordProviders(
      rows,
      selectedDirect: current.providers.selectedDirect,
      selectedTorrent: current.providers.selectedTorrent,
      seen: current.providers.seen,
    ),
  );

  void present(List<Torrent> rows) {
    if (!_current) return;
    if (state.frozen) {
      state = state.copyWith(pending: rows);
    } else {
      _publish(_withRows(state, rows));
    }
  }

  void freeze() {
    if (_current && !state.frozen) state = state.copyWith(frozen: true);
  }

  bool adopt() {
    if (!_current || state.pending == null) return false;
    final rows = state.pending!;
    final next = state.copyWith(
      clearPending: true,
      clearSourceTab: !rows.any(
        (row) => keywordSourceOf(row) == state.sourceTab,
      ),
    );
    _publish(_withRows(next, rows));
    return true;
  }

  bool finish() {
    if (!_current) return false;
    final full = state.pending ?? state.all;
    if (state.sourceTab == null ||
        full.any((row) => keywordSourceOf(row) == state.sourceTab)) {
      return false;
    }
    _publish(state.copyWith(clearSourceTab: true));
    return true;
  }

  void recompute() {
    if (_current) _publish(state);
  }

  void _publish(KeywordResultsState next) {
    final cache = ref.read(keywordCacheProvider(session));
    final providers = next.providers;
    final filtered = filterKeywordResults(
      next.all,
      cachedOnly: cache.cachedOnly,
      cache: cache.badges,
      directCounts: providers.directCounts,
      torrentCounts: providers.torrentCounts,
      selectedDirect: providers.selectedDirect,
      selectedTorrent: providers.selectedTorrent,
      sourceTab: next.sourceTab,
      filters: next.filters,
    );
    state = next.copyWith(
      results: sortKeywordResults(
        filtered,
        field: next.sort,
        ascending: next.sortAscending,
      ),
    );
  }

  void setFilters(TorrentFilterState filters) {
    if (_current) _publish(state.copyWith(filters: filters));
  }

  void setSort(String field) {
    if (_current) {
      _publish(
        state.copyWith(
          sort: field,
          sortAscending: keywordSortAscendingByDefault(field),
        ),
      );
    }
  }

  void setSortAscending(bool ascending) {
    if (_current) _publish(state.copyWith(sortAscending: ascending));
  }

  bool setSourceTab(String? source) {
    if (!_current) return false;
    if (!state.all.any((row) => keywordSourceOf(row) == source)) source = null;
    if (state.sourceTab == source) return false;
    _publish(state.copyWith(sourceTab: source, clearSourceTab: source == null));
    return true;
  }

  void toggleProvider(bool direct, String source) {
    if (!_current) return;
    final providers = state.providers;
    final selected = {
      ...(direct ? providers.selectedDirect : providers.selectedTorrent),
    };
    if (!selected.remove(source)) selected.add(source);
    _setProviders(direct, selected);
  }

  void toggleProviderGroup(bool direct) {
    if (!_current) return;
    final providers = state.providers;
    final counts = direct ? providers.directCounts : providers.torrentCounts;
    final selected = direct
        ? providers.selectedDirect
        : providers.selectedTorrent;
    _setProviders(
      direct,
      selected.length == counts.length ? {} : counts.keys.toSet(),
    );
  }

  void _setProviders(bool direct, Set<String> selected) {
    final current = state.providers;
    _publish(
      state.copyWith(
        providers: KeywordProviders(
          directCounts: current.directCounts,
          torrentCounts: current.torrentCounts,
          selectedDirect: direct ? selected : current.selectedDirect,
          selectedTorrent: direct ? current.selectedTorrent : selected,
          seen: current.seen,
        ),
      ),
    );
  }

  void setSelectionMode(bool enabled) {
    if (_current) state = state.copyWith(selectionMode: enabled, selected: {});
  }

  void toggleSelection(String hash) {
    if (!_current) return;
    final selected = {...state.selected};
    if (!selected.remove(hash)) selected.add(hash);
    state = state.copyWith(selected: selected);
  }

  void selectAll() {
    if (_current) {
      state = state.copyWith(
        selected: {
          for (final row in state.results)
            if (!isDirectKeywordResult(row)) row.infohash,
        },
      );
    }
  }

  void deselectAll() {
    if (_current) state = state.copyWith(selected: {});
  }
}
