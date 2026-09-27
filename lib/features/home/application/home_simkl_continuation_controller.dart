import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_simkl_continuation_reader.dart';
import '../models/home_continuation_session.dart';
import '../models/home_simkl_continuation.dart';
import 'home_simkl_continuation_dependencies.dart';

final homeSimklContinuationProvider = NotifierProvider.autoDispose
    .family<
      HomeSimklContinuationController,
      HomeSimklContinuation,
      HomeContinuationSession
    >(
      HomeSimklContinuationController.new,
      retry: (count, error) => null,
      dependencies: [homeSimklContinuationReaderProvider],
    );

/// Owns accepted Simkl shelves and request retirement. No startup reads or
/// automatic retries; the view retains focus, artwork and navigation effects.
class HomeSimklContinuationController extends Notifier<HomeSimklContinuation> {
  HomeSimklContinuationController(this.session);
  final HomeContinuationSession session;
  late HomeSimklContinuationReader _read;
  int _generation = 0;

  @override
  HomeSimklContinuation build() {
    _read = ref.watch(homeSimklContinuationReaderProvider);
    ref.onDispose(() => _generation++);
    return const HomeSimklContinuation.empty();
  }

  HomeSimklContinuation get current =>
      ref.mounted ? state : const HomeSimklContinuation.empty();

  Future<void> load({
    required bool Function() isCurrent,
    required Future<void> Function() ensureLayout,
    required void Function(HomeSimklContinuation next) beforeRows,
    required void Function(
      HomeSimklContinuation next,
      bool hadRows,
      bool Function() isCurrent,
    )
    onRows,
  }) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    final rows = await _read();
    if (!current()) return;
    // Simkl warms the shared layout even on a null (failed) feed response.
    await ensureLayout();
    if (!current() || rows == null) return;
    final next = HomeSimklContinuation.fromRows(
      movies: rows.movies,
      shows: rows.shows,
    );
    final hadRows = state.movies.isNotEmpty || state.series.isNotEmpty;
    beforeRows(next);
    if (!current()) return;
    state = next;
    onRows(next, hadRows, current);
  }
}
