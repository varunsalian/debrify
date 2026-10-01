import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_mdblist_continuation_repository.dart';
import '../models/home_continuation_session.dart';
import '../models/home_mdblist_continuation.dart';
import 'home_continuation_providers.dart';

final homeMdblistContinuationProvider = NotifierProvider.autoDispose
    .family<
      HomeMdblistContinuationController,
      HomeMdblistContinuation,
      HomeContinuationSession
    >(
      HomeMdblistContinuationController.new,
      retry: (count, error) => null,
      dependencies: [homeMdblistContinuationRepositoryProvider],
    );

/// Owns accepted shelves and request/forced-refresh bookkeeping. The view keeps
/// node reconciliation, repaint and route visibility checks.
class HomeMdblistContinuationController
    extends Notifier<HomeMdblistContinuation> {
  HomeMdblistContinuationController(this.session);
  final HomeContinuationSession session;
  late HomeMdblistContinuationRepository _repository;
  int _generation = 0;
  int _lifetimeGeneration = 0;
  int _revisionGeneration = 0;
  bool _revisionPending = false;
  bool get revisionPending => _revisionPending;
  DateTime? _forcedLoadAt;
  DateTime? get forcedLoadAt => _forcedLoadAt;

  @override
  HomeMdblistContinuation build() {
    _repository = ref.watch(homeMdblistContinuationRepositoryProvider);
    ref.onDispose(() {
      _generation++;
      _lifetimeGeneration++;
      cancelRevisionRefresh();
    });
    return const HomeMdblistContinuation.empty();
  }

  HomeMdblistContinuation get current =>
      ref.mounted ? state : const HomeMdblistContinuation.empty();

  /// The return refresh skips work already queued or completed within three
  /// seconds, including a forced refresh that finishes during other local loads.
  bool shouldRefreshAfterPlayback(DateTime now) =>
      !_revisionPending &&
      (_forcedLoadAt == null ||
          now.difference(_forcedLoadAt!) >= const Duration(seconds: 3));

  void cancelRevisionRefresh() {
    _revisionGeneration++;
    _revisionPending = false;
  }

  Future<void> refreshAfterRevision({
    required bool Function() isCurrent,
    required bool Function() isVisible,
    required Future<void> Function(Duration duration) wait,
    required Future<void> Function() reload,
  }) async {
    bool active() =>
        ref.mounted &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!active()) return;
    _repository.invalidate();
    final token = ++_revisionGeneration;
    _revisionPending = true;
    bool current() => active() && token == _revisionGeneration;
    try {
      // A stop response may arrive during the player pop. Wait for Home, then
      // preserve the service's propagation window before reading its snapshot.
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!current()) return;
        if (isVisible()) break;
        await wait(const Duration(milliseconds: 100));
      }
      if (!current() || !isVisible()) return;
      await wait(const Duration(milliseconds: 750));
      if (!current()) return;
      await reload();
    } finally {
      // Superseded work cannot clear the successor's pending marker.
      if (token == _revisionGeneration) _revisionPending = false;
    }
  }

  /// Explicit removals are independent actions: an intervening feed refresh or
  /// another title's removal must not cancel an already-issued remote command.
  /// Only this controller's lifetime, originating profile and view gate feedback.
  Future<bool> remove(
    String? imdbId, {
    required bool Function() isCurrent,
  }) async {
    final lifetime = _lifetimeGeneration;
    bool current() =>
        ref.mounted &&
        lifetime == _lifetimeGeneration &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return false;
    final item = state.byImdb[imdbId];
    if (item == null || !item.paused) return false;
    final scope = session.owner.scope;
    final removed = scope == null
        ? await _repository.clear(item)
        : await ProfileRuntime.withCapturedScope(
            scope,
            () => _repository.clear(item),
          );
    return current() && removed;
  }

  Future<void> load({
    required bool enabled,
    required bool force,
    required bool refreshBound,
    required bool Function() isCurrent,
    required Future<void> Function() ensureLayout,
    required DateTime Function() now,
    required void Function(String message) trace,
    required void Function(HomeMdblistContinuation next) beforeRows,
    required void Function(HomeMdblistContinuation next, bool hadRows) onRows,
    required void Function() onDisabled,
  }) async {
    final token = ++_generation;
    bool current() =>
        ref.mounted &&
        token == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    trace(
      '[MDBListDiag] Home CW load start token=$token '
      'refreshBound=$refreshBound force=$force flag=$enabled',
    );
    if (!current()) return;
    if (!enabled) {
      // Legacy disable hides rows without clearing progress or focus nodes.
      // Avoid a provider write during initState when already empty.
      if (state.movies.isNotEmpty ||
          state.series.isNotEmpty ||
          state.all.isNotEmpty ||
          state.byImdb.isNotEmpty) {
        state = state.withoutRows();
      }
      onDisabled();
      return;
    }
    final result = await _repository.read(force: force, isCurrent: current);
    if (result == null) return;
    await ensureLayout();
    if (!current() || !result.isUsable) {
      trace(
        '[MDBListDiag] Home CW load discarded token=$token mounted=${isCurrent()} '
        'currentToken=$_generation kind=${result.kind.name}',
      );
      return;
    }
    final next = HomeMdblistContinuation.fromSnapshot(result.data!);
    trace(
      '[MDBListDiag] Home CW ingest token=$token movies=${next.movies.length} '
      'shows=${next.series.length}',
    );
    final hadRows = state.movies.isNotEmpty || state.series.isNotEmpty;
    beforeRows(next);
    if (!current()) return;
    state = next;
    if (force) _forcedLoadAt = now();
    onRows(next, hadRows);
  }
}
