import '../profiles/profile_runtime.dart';
import '../profiles/profile_session_memory.dart';
import 'simkl_service.dart';

/// Shared by Home and legacy menus. Null is retirement, distinct from failure.
class SimklContinueWatchingRemoval {
  const SimklContinueWatchingRemoval(this.owner);
  final ProfileSessionOwner owner;

  Future<bool?> remove(
    String id,
    String type, {
    required bool Function() isCurrent,
  }) async {
    bool current() =>
        isCurrent() && owner == ProfileSessionMemory.captureOwner();
    if (!current()) return null;
    Future<bool?> write() async {
      final service = SimklService.instance;
      if (type == 'series') {
        final held = await service.addToList(
          id,
          type,
          'hold',
          canContinue: current,
        );
        if (!current()) return null;
        if (!held) return false;
        // On Hold already removes the series from both CW feeds. Failure to
        // clear its paused session must not change the successful status move.
        await service.deletePlaybackForImdb(
          id,
          contentType: type,
          canContinue: current,
        );
        return current() ? true : null;
      }
      final removed = await service.deletePlaybackForImdb(
        id,
        contentType: type,
        canContinue: current,
      );
      return current() ? removed : null;
    }

    final scope = owner.scope;
    return scope == null
        ? write()
        : ProfileRuntime.withCapturedScope(scope, write);
  }
}
