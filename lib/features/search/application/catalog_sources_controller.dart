import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog_search_repository.dart';
import '../models/catalog_sources_state.dart';
import '../models/search_session.dart';
import 'search_providers.dart';
import 'search_session_provider.dart';

final catalogSourcesProvider = NotifierProvider.autoDispose
    .family<CatalogSourcesController, CatalogSourcesState, SearchSession>(
      CatalogSourcesController.new,
      retry: (count, error) => null,
    );

class CatalogSourcesController extends Notifier<CatalogSourcesState> {
  CatalogSourcesController(this.session);
  final SearchSession session;
  late CatalogSearchRepository _repository;
  int _generation = 0;

  @override
  CatalogSourcesState build() {
    _repository = ref.watch(catalogSearchRepositoryProvider(session));
    ref.watch(searchSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    return const CatalogSourcesState.loading();
  }

  bool _accepts(int generation) =>
      ref.mounted && generation == _generation && _repository.isCurrent;

  Future<void> load() async {
    final generation = ++_generation;
    if (!_repository.isCurrent) return;
    try {
      // Preserve dialog read order (search itself reads settings first).
      final addons = await _repository.searchableAddons();
      final disabled = await _repository.readDisabledAddons();
      if (!_accepts(generation)) return;
      state = CatalogSourcesState(addons: addons, disabled: disabled);
    } catch (_) {
      // Preserve the existing loading presentation when settings cannot load.
      // Record the boundary failure without logging profile/source data.
      debugPrint('Catalog search sources could not be loaded.');
    }
  }

  Future<void> setEnabled(String addonId, bool enabled) {
    final disabled = Set<String>.of(state.disabled);
    if (enabled) {
      disabled.remove(addonId);
    } else {
      disabled.add(addonId);
    }
    return _save(disabled);
  }

  Future<void> enableAll() => _save({});
  Future<void> disableAll() => _save(state.addons.map((a) => a.id).toSet());

  Future<void> _save(Set<String> disabled) async {
    if (!_repository.isCurrent || state.loading) return;
    final generation = ++_generation;
    state = CatalogSourcesState(addons: state.addons, disabled: disabled);
    try {
      // Immediate writes survive dialog dismissal. The adapter captures a value
      // snapshot and profile scope; disposal does not cancel an accepted write.
      await _repository.writeDisabledAddons(disabled);
    } catch (error) {
      if (_accepts(generation)) {
        state = CatalogSourcesState(
          addons: state.addons,
          disabled: state.disabled,
          failure: error,
        );
      }
      debugPrint('Catalog search source settings could not be saved.');
    }
  }
}
