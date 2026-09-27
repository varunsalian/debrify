import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_mdblist_continuation_repository.dart';
import '../models/home_continuation_session.dart';
import '../models/home_mdblist_continuation.dart';
import 'home_mdblist_continuation_dependencies.dart';

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
/// node reconciliation, repaint, route eligibility and delayed revision work.
class HomeMdblistContinuationController
    extends Notifier<HomeMdblistContinuation> {
  HomeMdblistContinuationController(this.session);
  final HomeContinuationSession session;
  late HomeMdblistContinuationRepository _repository;
  int _generation = 0;
  DateTime? _forcedLoadAt;
  DateTime? get forcedLoadAt => _forcedLoadAt;

  @override
  HomeMdblistContinuation build() {
    _repository = ref.watch(homeMdblistContinuationRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const HomeMdblistContinuation.empty();
  }

  HomeMdblistContinuation get current =>
      ref.mounted ? state : const HomeMdblistContinuation.empty();

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
