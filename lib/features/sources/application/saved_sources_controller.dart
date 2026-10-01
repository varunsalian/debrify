import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/series_source.dart';
import '../data/saved_sources_repository.dart';
import '../models/saved_sources_state.dart';
import '../models/sources_session.dart';
import 'sources_providers.dart';

final savedSourcesProvider = NotifierProvider.autoDispose
    .family<SavedSourcesController, SavedSourcesState, SourcesSession>(
      SavedSourcesController.new,
      retry: (count, error) => null,
      dependencies: [
        savedSourcesRepositoryProvider,
        sourcesSessionActiveProvider,
      ],
    );

class SavedSourcesController extends Notifier<SavedSourcesState> {
  SavedSourcesController(this.session);
  final SourcesSession session;
  late SavedSourcesRepository _repository;
  int _generation = 0;

  @override
  SavedSourcesState build() {
    _repository = ref.watch(savedSourcesRepositoryProvider(session));
    ref.watch(sourcesSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    return SavedSourcesState();
  }

  bool _accept(int generation) =>
      ref.mounted && _repository.isCurrent && generation == _generation;

  Future<bool> reload() async {
    if (!ref.mounted || !_repository.isCurrent) return false;
    final generation = ++_generation;
    try {
      final loaded = await _repository.load();
      if (!_accept(generation)) return false;
      state = loaded;
      return true;
    } catch (_) {
      if (!_accept(generation)) return false;
      rethrow;
    }
  }

  /// Complete an explicit removal for its originating profile, even if the
  /// view closes. Only a live owner may reload/publish afterward. Independent
  /// removals do not cancel one another through the read generation.
  Future<bool> remove(SeriesSource source) async {
    if (!ref.mounted || !_repository.isCurrent) return false;
    final repository = _repository;
    final removed = await repository.remove(source);
    if (!removed ||
        !ref.mounted ||
        !repository.isCurrent ||
        !identical(repository, _repository)) {
      return false;
    }
    return reload();
  }
}
