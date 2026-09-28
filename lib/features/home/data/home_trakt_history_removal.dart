import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/trakt/trakt_continue_watching_service.dart';

/// Keeps the whole remote removal on its originating account. Already sent
/// requests may finish; retirement prevents the next write and UI feedback.
class HomeTraktHistoryRemoval {
  const HomeTraktHistoryRemoval(this.owner);
  final ProfileSessionOwner owner;

  Future<bool?> remove(
    TraktContinueWatchingItem item, {
    required bool Function() isCurrent,
  }) async {
    bool current() =>
        isCurrent() && owner == ProfileSessionMemory.captureOwner();
    if (!current()) return null;
    Future<bool> write() => TraktContinueWatchingService.instance.removeItem(
      item,
      canContinue: current,
    );
    final scope = owner.scope;
    final removed = scope == null
        ? await write()
        : await ProfileRuntime.withCapturedScope(scope, write);
    return current() ? removed : null;
  }
}
