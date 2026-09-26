import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/sources_session.dart';
import 'saved_sources_controller.dart';
import 'source_seasons_dependencies.dart';

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
  int _generation = 0;

  @override
  bool build() {
    _savedSources = ref.watch(savedSourcesProvider(session).notifier);
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
    Future<bool> Function() operation, {
    required bool Function() viewIsActive,
  }) async {
    final generation = _generation;
    bool active() => _active(generation) && viewIsActive();
    if (!active() || state) return false;
    state = true;
    try {
      final bound = await operation();
      if (!bound || !active()) return false;
      final reloaded = await _savedSources.reload();
      return reloaded && active();
    } finally {
      // A retired completion must not clear a replacement action's busy flag.
      if (_active(generation)) state = false;
    }
  }
}
