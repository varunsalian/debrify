import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_local_continuation_repository.dart';
import '../models/home_continuation_session.dart';
import '../models/home_local_continuation.dart';
import '../models/home_local_continuation_state.dart';
import 'home_local_continuation_dependencies.dart';

final homeLocalContinuationProvider = NotifierProvider.autoDispose
    .family<
      HomeLocalContinuationController,
      HomeLocalContinuationState,
      HomeContinuationSession
    >(
      HomeLocalContinuationController.new,
      retry: (count, error) => null,
      dependencies: [homeLocalContinuationRepositoryProvider],
    );

/// Owns accepted data and requests. Synchronous presentation callbacks retain
/// source-setting repaint and focus-before-row-publication ordering.
class HomeLocalContinuationController
    extends Notifier<HomeLocalContinuationState> {
  HomeLocalContinuationController(this.session);
  final HomeContinuationSession session;
  late HomeLocalContinuationRepository _repository;
  int _generation = 0;

  @override
  HomeLocalContinuationState build() {
    _repository = ref.watch(homeLocalContinuationRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const HomeLocalContinuationState.initial();
  }

  HomeLocalContinuationState get current =>
      ref.mounted ? state : const HomeLocalContinuationState.initial();

  bool _owns(int generation) =>
      ref.mounted &&
      generation == _generation &&
      session.owner == ProfileSessionMemory.captureOwner();

  Future<void> load({
    required bool Function() isCurrent,
    required void Function() onProgressSourceChanged,
    required Future<void> Function() beforeEnabledRows,
    required void Function(HomeLocalContinuationState next) beforeRows,
    required void Function(
      HomeLocalContinuationState next,
      bool Function() isCurrent,
    )
    onRows,
  }) async {
    final generation = ++_generation;
    bool current() => _owns(generation) && isCurrent();
    if (!current()) return;
    final repository = _repository;
    final progressSource = await repository.readProgressSource();
    if (!current()) return;
    final enabled = await repository.readEnabled();
    if (!current()) return;
    if (progressSource != state.progressSource) {
      state = state.copyWith(progressSource: progressSource);
      onProgressSourceChanged();
    }
    if (!current()) return;

    HomeLocalContinuation data;
    if (enabled) {
      final loaded = await repository.load(isCurrent: current);
      if (loaded == null || !current()) return;
      data = loaded;
      await beforeEnabledRows();
      if (!current()) return;
    } else {
      data = const HomeLocalContinuation.empty();
    }
    final next = state.copyWith(enabled: enabled, data: data);
    beforeRows(next);
    if (!current()) return;
    state = next;
    onRows(next, current);
  }
}
