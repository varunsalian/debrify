import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/hero_metadata_presentation.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_card_metadata_repository.dart';
import '../models/home_card_metadata.dart';
import 'home_board_providers.dart';

final homeCardMetadataProvider = NotifierProvider.autoDispose
    .family<
      HomeCardMetadataController,
      HomeCardMetadataState,
      HomeCardMetadataSession
    >(
      HomeCardMetadataController.new,
      retry: (count, error) => null,
      dependencies: [homeCardMetadataRepositoryProvider],
    );

class HomeCardMetadataController extends Notifier<HomeCardMetadataState> {
  HomeCardMetadataController(this.session) : _accepted = session.initial;
  final HomeCardMetadataSession session;
  HomeCardMetadataState _accepted;
  late HomeCardMetadataRepository _repository;
  Timer? _retry;
  int _attempt = 0;
  int _generation = 0;
  bool _retired = false;

  @override
  HomeCardMetadataState build() {
    _repository = ref.watch(homeCardMetadataRepositoryProvider(session.epoch));
    ref.onDispose(() {
      _generation++;
      _retry?.cancel();
    });
    return _accepted;
  }

  bool get _active =>
      ref.mounted &&
      !_retired &&
      session.epoch.owner == ProfileSessionMemory.captureOwner() &&
      _repository.isCurrent();

  void _publish(HomeCardMetadataState next) {
    _accepted = next;
    state = next;
  }

  /// A view retires its old binding before provider disposal at frame end.
  void retire() {
    _retired = true;
    _generation++;
    _retry?.cancel();
  }

  Future<void> load({required bool Function() isCurrent}) async {
    if (!_active || !isCurrent()) return;
    final generation = ++_generation;
    final repository = _repository;
    final original = session.initial.original;
    final timing = Stopwatch()..start();
    bool active() => _active && generation == _generation && isCurrent();
    try {
      final preferences = await repository.readPreferences();
      if (!active()) return;
      _publish(
        HomeCardMetadataState(
          original: original,
          presentation: state.presentation,
          preferences: preferences,
          resolvedOnce: state.resolvedOnce,
        ),
      );
      if (!active()) return;
      final cached = repository.prepareAndTake(original, preferences);
      final presentation =
          (cached != null && cached.expires.isAfter(DateTime.now())
              ? cached.value
              : null) ??
          await repository.present(original, preferences, active);
      if (!active()) return;
      repository.accept(original, presentation, (
        elapsedMs: timing.elapsedMilliseconds,
        retryable: presentation.retryable,
        cacheHit: cached != null && cached.expires.isAfter(DateTime.now()),
        attempt: _attempt,
        missing: presentation.unavailable.length,
      ));
      if (!active()) return;
      if (presentation.retryable && _attempt < 2) {
        _retry?.cancel();
        _retry = Timer(Duration(seconds: ++_attempt * 2), () {
          if (active()) unawaited(load(isCurrent: isCurrent));
        });
      }
      final presented =
          identical(presentation.item, original) && preferences.isCurrent
          ? null
          : presentation.retryable && state.presentation != null
          ? mergeHeroMetadata(state.presentation!, presentation.item)
          : presentation.item;
      _publish(
        HomeCardMetadataState(
          original: original,
          presentation: presented,
          preferences: preferences,
          resolvedOnce: true,
        ),
      );
    } catch (_) {
      // Preserve the legacy optional-read behaviour and already usable artwork.
    }
  }
}
