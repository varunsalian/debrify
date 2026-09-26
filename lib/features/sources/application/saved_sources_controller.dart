import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/saved_sources_repository.dart';
import '../models/saved_sources_state.dart';
import '../models/sources_session.dart';
import 'saved_sources_dependencies.dart';
import 'source_seasons_dependencies.dart';

final savedSourcesProvider = NotifierProvider.autoDispose
    .family<SavedSourcesController, SavedSourcesState, SourcesSession>(
      SavedSourcesController.new,
      retry: (count, error) => null,
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
}
