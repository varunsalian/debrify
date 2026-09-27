import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/iptv_cw_history.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_continuation_session.dart';
import '../models/home_iptv_continuation_state.dart';
import 'home_iptv_continuation_dependencies.dart';

final homeIptvContinuationProvider = NotifierProvider.autoDispose
    .family<
      HomeIptvContinuationController,
      HomeIptvContinuationState,
      HomeContinuationSession
    >(
      HomeIptvContinuationController.new,
      retry: (count, error) => null,
      dependencies: [homeIptvContinuationRepositoryProvider],
    );

/// Owns IPTV shelf data for one view/profile. Presentation keeps focus and
/// playback; loading only reads the existing history boundary.
class HomeIptvContinuationController
    extends Notifier<HomeIptvContinuationState> {
  HomeIptvContinuationController(this.session);
  final HomeContinuationSession session;
  late IptvCwHistory _repository;
  int _generation = 0;

  @override
  HomeIptvContinuationState build() {
    _repository = ref.watch(homeIptvContinuationRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const HomeIptvContinuationState.empty();
  }

  HomeIptvContinuationState get current =>
      ref.mounted ? state : const HomeIptvContinuationState.empty();

  Future<void> load({
    required bool Function() isCurrent,
    required void Function(HomeIptvContinuationState next) beforeRows,
    required void Function() onRows,
  }) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    final rows = await _repository.load();
    if (!current()) return;
    final next = HomeIptvContinuationState.fromRows(rows);
    beforeRows(next);
    if (!current()) return;
    state = next;
    onRows();
  }
}
