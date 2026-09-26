import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/concurrency.dart';
import '../data/catalog_search_repository.dart';
import '../models/catalog_search_row.dart';
import '../models/catalog_search_state.dart';
import '../models/search_session.dart';
import 'catalog_search_dependencies.dart';

final catalogSearchProvider = NotifierProvider.autoDispose
    .family<CatalogSearchController, CatalogSearchState, SearchSession>(
      CatalogSearchController.new,
      retry: (count, error) => null,
    );

class CatalogSearchController extends Notifier<CatalogSearchState> {
  CatalogSearchController(this.session);

  final SearchSession session;
  late CatalogSearchRepository _repository;
  int _generation = 0;

  @override
  CatalogSearchState build() {
    _repository = ref.watch(catalogSearchRepositoryProvider(session));
    ref.onDispose(() => _generation++);
    return const CatalogSearchState();
  }

  bool _accepts(int generation) =>
      ref.mounted && generation == _generation && _repository.isCurrent;

  void clear() {
    _generation++;
    // Home restore previously retained the failure count until the next search.
    state = CatalogSearchState(failures: state.failures);
  }

  Future<CatalogSearchCompletion> search(
    String query, {
    required bool batchResults,
  }) async {
    if (!_repository.isCurrent) return CatalogSearchCompletion.stale;
    final generation = ++_generation;
    state = CatalogSearchState(query: query, searching: true);
    try {
      final disabled = await _repository.readDisabledAddons();
      final addons = await _repository.searchableAddons();
      final tasks = [
        for (final addon in addons)
          if (!disabled.contains(addon.id))
            for (final catalog in addon.catalogs)
              if (catalog.supportsSearch) (addon: addon, catalog: catalog),
      ];
      // Existing helper bounds fan-out to ten and preserves input order. TV
      // publishes the completed batch; other layouts publish completion order.
      final rows = await mapWithConcurrency(tasks, (entry) async {
        CatalogSearchRow? row;
        try {
          row = await _repository.searchCatalog(
            entry.addon,
            entry.catalog,
            query,
          );
        } catch (_) {
          if (_accepts(generation)) {
            state = state.copyWith(failures: state.failures + 1);
          }
          return null;
        }
        if (!_accepts(generation) || row == null) return null;
        if (!batchResults) state = state.copyWith(rows: [...state.rows, row]);
        return row;
      });
      if (!_accepts(generation)) return CatalogSearchCompletion.stale;
      if (batchResults) {
        state = state.copyWith(
          rows: rows.whereType<CatalogSearchRow>().toList(),
        );
      }
      state = state.copyWith(searching: false);
      return CatalogSearchCompletion.accepted;
    } catch (_) {
      if (!_accepts(generation)) return CatalogSearchCompletion.stale;
      state = state.copyWith(searching: false);
      return CatalogSearchCompletion.failed;
    }
  }
}
