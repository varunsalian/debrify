import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_tracker_authentication.dart';
import 'home_tracker_authentication_dependencies.dart';

final homeTrackerAuthenticationProvider = NotifierProvider.autoDispose
    .family<HomeTrackerAuthenticationController, bool, HomeTrackerAuthSession>(
      HomeTrackerAuthenticationController.new,
      retry: (count, error) => null,
      dependencies: [homeTrackerAuthReaderProvider],
    );

/// Each tracker has its own request generation and accepted presentation value.
class HomeTrackerAuthenticationController extends Notifier<bool> {
  HomeTrackerAuthenticationController(this.session);
  final HomeTrackerAuthSession session;
  late HomeTrackerAuthReader _read;
  bool _accepted = false;
  int _generation = 0;

  @override
  bool build() {
    _read = ref.watch(homeTrackerAuthReaderProvider(session));
    ref.onDispose(() => _generation++);
    return _accepted;
  }

  bool get current => ref.mounted && state;

  Future<void> load({
    required bool Function() isCurrent,
    void Function(bool)? beforeChange,
    required void Function(bool) onChanged,
  }) async {
    bool active() =>
        ref.mounted &&
        session.view.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!active()) return;
    final generation = ++_generation;
    bool current() => active() && generation == _generation;
    final value = await _read();
    if (!current() || value == state) return;
    // MDBList clears outgoing Lists state before changing mode availability.
    beforeChange?.call(value);
    if (!current()) return;
    _accepted = value;
    state = value;
    if (current()) onChanged(value);
  }
}
