import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_trakt_continuation_repository.dart';
import '../models/home_continuation_session.dart';
import '../models/home_trakt_continuation.dart';
import '../models/home_trakt_continuation_read.dart';
import '../models/home_trakt_continuation_state.dart';
import 'home_continuation_providers.dart';

/// Home/Discover seed loading before initState starts the first request.
/// Search does not load on startup. Neither variant performs reads in build.
typedef HomeTraktContinuationScope = ({
  HomeContinuationSession session,
  bool initiallyLoading,
});

final homeTraktContinuationProvider = NotifierProvider.autoDispose
    .family<
      HomeTraktContinuationController,
      HomeTraktContinuationState,
      HomeTraktContinuationScope
    >(
      HomeTraktContinuationController.new,
      retry: (count, error) => null,
      dependencies: [homeTraktContinuationRepositoryProvider],
    );

class HomeTraktContinuationController
    extends Notifier<HomeTraktContinuationState> {
  HomeTraktContinuationController(this.scope);
  final HomeTraktContinuationScope scope;
  late HomeTraktContinuationRepository _repository;
  int _generation = 0;
  bool _built = false;
  DateTime? _lastAttemptAt;

  /// Request bookkeeping is not rendered; the view supplies its existing clock
  /// and retains route/auth/playback eligibility for lifecycle refreshes.
  DateTime? get lastAttemptAt => _lastAttemptAt;

  @override
  HomeTraktContinuationState build() {
    _repository = ref.watch(homeTraktContinuationRepositoryProvider);
    ref.onDispose(() => _generation++);
    final loading = !_built && scope.initiallyLoading;
    _built = true;
    return HomeTraktContinuationState(loading: loading);
  }

  HomeTraktContinuationState get current =>
      ref.mounted ? state : const HomeTraktContinuationState();

  Future<void> load({
    required DateTime attemptedAt,
    required bool Function() isCurrent,
    required Future<void> Function() beforeConnectedRows,
    required void Function(HomeTraktContinuation next) beforeRows,
    required void Function(
      HomeTraktContinuation next,
      bool connected,
      bool hadRows,
      bool Function() isCurrent,
    )
    onRows,
    required void Function(Object error, bool accepted) onFailure,
  }) async {
    _lastAttemptAt = attemptedAt;
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        scope.session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    // The initial request must not publish a provider update from initState.
    if (!state.loading) state = state.copyWith(loading: true);
    final HomeTraktContinuationRead? rows;
    try {
      rows = await _repository.read(isCurrent: current);
    } catch (error) {
      final accepted = current();
      if (accepted) state = state.copyWith(loading: false);
      onFailure(error, accepted);
      return;
    }
    if (!current() || rows == null) return;
    if (rows.authenticated) {
      await beforeConnectedRows();
      if (!current()) return;
    }
    final next = rows.authenticated
        ? HomeTraktContinuation.fromRows(movies: rows.movies, shows: rows.shows)
        : const HomeTraktContinuation.empty();
    final previous = state.data;
    final hadRows = previous.movies.isNotEmpty || previous.series.isNotEmpty;
    beforeRows(next);
    if (!current()) return;
    state = HomeTraktContinuationState(data: next);
    onRows(next, rows.authenticated, hadRows, current);
  }
}
