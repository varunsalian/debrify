import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/addon_search_status.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';
import '../data/source_search_repository.dart';
import '../models/sources_session.dart';
import 'sources_providers.dart';

final sourceRetryProvider = NotifierProvider.autoDispose
    .family<SourceRetryController, Set<String>, SourcesSession>(
      SourceRetryController.new,
      retry: (count, error) => null,
      dependencies: [
        sourceSearchRepositoryProvider,
        sourcesSessionActiveProvider,
      ],
    );

class SourceRetryController extends Notifier<Set<String>> {
  SourceRetryController(this.session);
  final SourcesSession session;
  late SourceSearchRepository _repository;
  int _generation = 0;

  @override
  Set<String> build() {
    _repository = ref.watch(sourceSearchRepositoryProvider(session));
    ref.watch(sourcesSessionActiveProvider(session));
    _generation++;
    ref.onDispose(() => _generation++);
    return const {};
  }

  bool _accept(int generation) =>
      ref.mounted && _repository.isCurrent && generation == _generation;

  void beginSearch() {
    if (!ref.mounted || !_repository.isCurrent) return;
    _generation++;
    state = const {};
  }

  Future<List<Torrent>?> retry(
    AdvancedSearchSelection selection,
    AddonSearchStatus status,
  ) async {
    final generation = _generation;
    final key = status.requestKey;
    if (!_accept(generation) || state.contains(key)) return null;
    state = Set.unmodifiable({...state, key});
    try {
      final rows = await _repository.retry(
        selection,
        key,
        shouldContinue: () => _accept(generation),
      );
      return _accept(generation) ? rows : null;
    } catch (_) {
      // The existing failed chip remains the error indicator. No auto retry.
      return null;
    } finally {
      if (_accept(generation)) {
        state = Set.unmodifiable(state.where((value) => value != key));
      }
    }
  }
}
