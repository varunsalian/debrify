import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/discover_card_settings.dart';
import 'discover_card_settings_dependencies.dart';

final discoverCardSettingsProvider = NotifierProvider.autoDispose
    .family<
      DiscoverCardSettingsController,
      DiscoverCardSettings,
      DiscoverCardSettingsSession
    >(
      DiscoverCardSettingsController.new,
      retry: (count, error) => null,
      dependencies: [discoverCardSettingsReaderProvider],
    );

/// Accepted card chrome for one view. Discover refreshes its displayed snapshot
/// explicitly; Home expansions read a fresh snapshot without changing that state.
class DiscoverCardSettingsController extends Notifier<DiscoverCardSettings> {
  DiscoverCardSettingsController(this.session);
  final DiscoverCardSettingsSession session;
  late DiscoverCardSettingsReader _read;
  DiscoverCardSettings? _accepted;
  int _generation = 0;

  @override
  DiscoverCardSettings build() {
    _read = ref.watch(discoverCardSettingsReaderProvider(session));
    ref.onDispose(() => _generation++);
    return _accepted ??=
        _readCurrent(() => true) ?? defaultDiscoverCardSettings;
  }

  DiscoverCardSettings get current =>
      ref.mounted ? state : (_accepted ?? defaultDiscoverCardSettings);
  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  DiscoverCardSettings? _readCurrent(bool Function() isCurrent) {
    if (!_active || !isCurrent()) return null;
    final generation = _generation;
    final next = _read();
    return _active && generation == _generation && isCurrent() ? next : null;
  }

  bool refresh({required bool Function() isCurrent}) {
    final next = _readCurrent(isCurrent);
    if (next == null || next == state) return false;
    _accepted = next;
    state = next;
    return true;
  }

  /// A route opened from Home must use the current warmed flags even when no
  /// Discover instance received the settings notification. Do not repaint Home.
  DiscoverCardSettings readSnapshot({required bool Function() isCurrent}) =>
      _readCurrent(isCurrent) ?? current;
}
