import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_continuation_layout_repository.dart';
import '../models/home_continuation_layout.dart';
import '../models/home_continuation_session.dart';
import 'home_continuation_providers.dart';

final homeContinuationLayoutProvider = NotifierProvider.autoDispose
    .family<
      HomeContinuationLayoutController,
      HomeContinuationLayout,
      HomeContinuationSession
    >(
      HomeContinuationLayoutController.new,
      retry: (count, error) => null,
      dependencies: [homeContinuationLayoutRepositoryProvider],
    );

/// One initial read shared by all continuation loaders; explicit settings
/// refreshes remain independent reads. Presentation owns node reconciliation.
class HomeContinuationLayoutController
    extends Notifier<HomeContinuationLayout> {
  HomeContinuationLayoutController(this.session);
  final HomeContinuationSession session;
  late HomeContinuationLayoutRepository _repository;
  Future<void>? _initialLoad;
  int _generation = 0;

  @override
  HomeContinuationLayout build() {
    _repository = ref.watch(homeContinuationLayoutRepositoryProvider);
    _initialLoad = null;
    ref.onDispose(() => _generation++);
    return const HomeContinuationLayout();
  }

  HomeContinuationLayout get current =>
      ref.mounted ? state : const HomeContinuationLayout();

  Future<void> ensureLoaded({required bool Function() isCurrent}) =>
      _initialLoad ??= _loadInitially(isCurrent);

  Future<void> _loadInitially(bool Function() isCurrent) async {
    try {
      await refresh(isCurrent: isCurrent);
    } catch (_) {
      // A failed initial preference read must not fail a continuation load.
      // Memoize the fallback too; settings refresh is the explicit retry path.
    }
  }

  Future<bool> refresh({required bool Function() isCurrent}) async {
    final generation = ++_generation;
    bool eligible() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!eligible()) return false;
    final next = await _repository.read();
    if (!eligible() || next == state) return false;
    state = next;
    return true;
  }
}
