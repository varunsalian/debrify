import 'package:debrify/services/ledger/ledger_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_ledger_continuation.dart';

/// Removes a Ledger Continue Watching card for the profile that owns the
/// Home session. Null means the action was retired (profile or view changed),
/// distinct from a failed write.
class HomeLedgerHistoryRemoval {
  const HomeLedgerHistoryRemoval(this.owner, {LedgerService? service})
    : _service = service;
  final ProfileSessionOwner owner;
  final LedgerService? _service;

  Future<bool?> remove(
    HomeLedgerContinuationItem item, {
    required bool Function() isCurrent,
  }) async {
    bool current() =>
        isCurrent() && owner == ProfileSessionMemory.captureOwner();
    if (!current()) return null;
    Future<bool?> write() async {
      final removed = await (_service ?? LedgerService.instance)
          .removeFromContinueWatching(
            imdbId: item.id,
            isMovie: item.isMovie,
            playbackId: item.playbackId,
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
