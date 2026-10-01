import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_display_preferences_repository.dart';
import '../models/home_display_preferences.dart';
import 'home_board_providers.dart';

final homeDisplayPreferencesProvider = NotifierProvider.autoDispose
    .family<
      HomeDisplayPreferencesController,
      HomeDisplayPreferences,
      HomeDisplaySession
    >(
      HomeDisplayPreferencesController.new,
      retry: (count, error) => null,
      dependencies: [homeDisplayPreferencesRepositoryProvider],
    );

class HomeDisplayPreferencesController
    extends Notifier<HomeDisplayPreferences> {
  HomeDisplayPreferencesController(this.session);
  final HomeDisplaySession session;
  late HomeDisplayPreferencesRepository _repository;
  HomeDisplayPreferences? _accepted;
  int _generation = 0;

  @override
  HomeDisplayPreferences build() {
    _repository = ref.watch(homeDisplayPreferencesRepositoryProvider);
    ref.onDispose(() => _generation++);
    return _accepted ?? session.initial;
  }

  HomeDisplayPreferences get current =>
      ref.mounted ? state : initialHomeDisplayPreferences;

  /// Startup and explicit settings refresh share newest-request ownership.
  /// Read failures propagate without replacing the last accepted preferences.
  Future<bool> load({required bool Function() isCurrent}) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return false;
    final next = await _repository.read(isCurrent: current);
    if (!current() || next == null || next == state) return false;
    _accepted = next;
    state = next;
    return true;
  }
}
