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
  int _lifetime = 0;
  int _generation = 0;
  int _accepted = 0;

  @override
  HomeContinuationLayout build() {
    _repository = ref.watch(homeContinuationLayoutRepositoryProvider);
    _initialLoad = null;
    ref.onDispose(() {
      _lifetime++;
      _generation++;
    });
    return const HomeContinuationLayout();
  }

  HomeContinuationLayout get current =>
      ref.mounted ? state : const HomeContinuationLayout();

  Future<void> ensureLoaded({required bool Function() isCurrent}) =>
      _initialLoad ??= _loadInitially(isCurrent);

  Future<void> _loadInitially(bool Function() isCurrent) async {
    try {
      await _read(isCurrent, refresh: false);
    } catch (_) {
      // A failed initial preference read must not fail a continuation load.
      // Memoize the fallback too; settings refresh is the explicit retry path.
    }
  }

  Future<bool> refresh({required bool Function() isCurrent}) =>
      _read(isCurrent, refresh: true);

  /// A newer refresh retires an older one. The initial read, which every
  /// loader awaits, is retired only by a refresh that was accepted first, as
  /// main always applied it; a refresh merely starting must not leave the
  /// loaders sizing rows with the default flags.
  Future<bool> _read(bool Function() isCurrent, {required bool refresh}) async {
    final lifetime = _lifetime;
    final generation = refresh ? ++_generation : _generation;
    final accepted = _accepted;
    bool eligible() =>
        ref.mounted &&
        lifetime == _lifetime &&
        (refresh ? generation == _generation : accepted == _accepted) &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!eligible()) return false;
    final next = await _repository.read();
    if (!eligible()) return false;
    if (refresh) _accepted++;
    if (next == state) return false;
    state = next;
    return true;
  }
}
