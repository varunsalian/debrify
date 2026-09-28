import 'profile_local_writes.dart';
import 'profile_preferences.dart';
import 'profile_runtime.dart';
import 'profile_session_memory.dart';

class PlaybackPreparationRetired implements Exception {
  const PlaybackPreparationRetired();
}

/// Keeps playback preparation and its accepted local writes with the origin.
/// Native callbacks may outlive launch, so the caller supplies the session guard.
class ProfilePlaybackPreparation {
  const ProfilePlaybackPreparation({
    required this.owner,
    required this.canContinue,
  });
  final ProfileSessionOwner owner;
  final bool Function() canContinue;
  bool get isCurrent =>
      owner == ProfileSessionMemory.captureOwner() && canContinue();

  Future<T> run<T>(Future<T> Function() action) async {
    if (!isCurrent) throw const PlaybackPreparationRetired();
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(action)
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  /// Acceptance occurs after the preference barrier. Accepted writes finish in
  /// their original scope and participate in the existing profile handoff drain.
  Future<void> write(Future<void> Function() action) => run(
    () => ProfileLocalWrites.run(
      () => ProfilePreferences.synchronizeExternalMutation(() async {
        if (!isCurrent) return;
        await action();
      }, marksMutation: false),
    ),
  );
}
