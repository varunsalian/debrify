import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/discover_layout_preferences.dart';
import '../models/discover_layout_session.dart';
import 'discover_layout_dependencies.dart';

final discoverLayoutProvider = NotifierProvider.autoDispose
    .family<DiscoverLayoutController, String, DiscoverLayoutSession>(
      DiscoverLayoutController.new,
      retry: (count, error) => null,
      dependencies: [discoverLayoutPreferencesProvider],
    );

/// A view's accepted layout. Loading is explicit; the caller keeps ordered
/// preview teardown before a settings refresh and rebuilds on accepted change.
class DiscoverLayoutController extends Notifier<String> {
  DiscoverLayoutController(this.session);
  final DiscoverLayoutSession session;
  late DiscoverLayoutPreferences _preferences;
  String? _accepted;
  int _generation = 0;

  @override
  String build() {
    _preferences = ref.watch(discoverLayoutPreferencesProvider(session));
    ref.onDispose(() => _generation++);
    return _accepted ??= _preferences.readCached();
  }

  String get current => ref.mounted ? state : (_accepted ?? 'stage');
  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  Future<void> load({
    required bool Function() isCurrent,
    required void Function() onChanged,
  }) async {
    if (!_active || !isCurrent()) return;
    final generation = ++_generation;
    bool currentRequest() =>
        _active && generation == _generation && isCurrent();
    try {
      final layout = await _preferences.readSaved(currentRequest);
      if (!currentRequest()) return;
      _preferences.remember(layout);
      if (layout == state) return;
      _accepted = layout;
      state = layout;
      if (currentRequest()) onChanged();
    } catch (_) {
      // Preserve active read failures without retries. An outgoing request must
      // not surface its error after a newer request or profile has taken over.
      if (currentRequest()) rethrow;
    }
  }
}
