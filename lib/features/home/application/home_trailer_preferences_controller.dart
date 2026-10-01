import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_trailer_preferences_repository.dart';
import '../models/home_catalog_session.dart';
import '../models/home_trailer_preferences.dart';
import 'home_hero_providers.dart';

final homeTrailerPreferencesProvider = NotifierProvider.autoDispose
    .family<
      HomeTrailerPreferencesController,
      HomeTrailerPreferences,
      HomeCatalogSession
    >(
      HomeTrailerPreferencesController.new,
      retry: (count, error) => null,
      dependencies: [homeTrailerPreferencesRepositoryProvider],
    );

/// Owns accepted preference values, not trailer scheduling or player resources.
class HomeTrailerPreferencesController
    extends Notifier<HomeTrailerPreferences> {
  HomeTrailerPreferencesController(this.session);
  final HomeCatalogSession session;
  late HomeTrailerPreferencesRepository _repository;
  HomeTrailerPreferences? _accepted;
  int _generation = 0;

  @override
  HomeTrailerPreferences build() {
    _repository = ref.watch(homeTrailerPreferencesRepositoryProvider);
    ref.onDispose(() => _generation++);
    return _accepted ?? initialHomeTrailerPreferences;
  }

  HomeTrailerPreferences get current =>
      ref.mounted ? state : initialHomeTrailerPreferences;

  Future<void> load({
    required bool useHomeAudio,
    required bool Function() isCurrent,
    required void Function(HomeTrailerPreferences) onAccepted,
  }) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    final preferences = await _repository.read(useHomeAudio: useHomeAudio);
    if (!current()) return;
    _accepted = preferences;
    state = preferences;
    // Repeated disabled refreshes must still ask the view to stop a trailer.
    if (current()) onAccepted(preferences);
  }
}
