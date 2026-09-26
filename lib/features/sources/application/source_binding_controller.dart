import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/series_source.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/saved_sources_repository.dart';
import '../models/sources_session.dart';
import 'saved_sources_controller.dart';
import 'saved_sources_dependencies.dart';
import 'source_seasons_dependencies.dart';

typedef SourceBindingWriter = Future<bool> Function(SeriesSource source);
typedef SourceBindingOperation =
    Future<bool> Function(
      SourceBindingWriter save,
      bool Function() canContinue,
    );

final sourceBindingProvider = NotifierProvider.autoDispose
    .family<SourceBindingController, bool, SourcesSession>(
      SourceBindingController.new,
      retry: (count, error) => null,
    );

/// One shared action gate for torrent, direct/IPTV and local bindings.
/// The caller owns interactive picking; this controller owns busy/reload state.
class SourceBindingController extends Notifier<bool> {
  SourceBindingController(this.session);
  final SourcesSession session;
  late SavedSourcesController _savedSources;
  late SavedSourcesRepository _repository;
  int _generation = 0;

  @override
  bool build() {
    _savedSources = ref.watch(savedSourcesProvider(session).notifier);
    _repository = ref.watch(savedSourcesRepositoryProvider(session));
    ref.watch(sourcesSessionActiveProvider(session));
    _generation++;
    ref.onDispose(() => _generation++);
    return false;
  }

  bool _active(int generation) =>
      ref.mounted &&
      generation == _generation &&
      session.owner == ProfileSessionMemory.captureOwner();

  Future<bool> bind(
    SourceBindingOperation operation, {
    required bool Function() viewIsActive,
  }) async {
    final generation = _generation;
    bool active() => _active(generation) && viewIsActive();
    if (!active() || state) return false;
    final repository = _repository;
    state = true;
    var acceptingWrites = true;
    try {
      final bound = await operation((source) async {
        if (!acceptingWrites || !active()) return false;
        return repository.save(source);
      }, () => acceptingWrites && active());
      acceptingWrites = false;
      if (!bound || !active()) return false;
      final reloaded = await _savedSources.reload();
      return reloaded && active();
    } finally {
      acceptingWrites = false;
      // A retired completion must not clear a replacement action's busy flag.
      if (_active(generation)) state = false;
    }
  }
}
