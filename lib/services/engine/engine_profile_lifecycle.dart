import 'engine_registry.dart';
import 'local_engine_storage.dart';

/// Owns the process-global torrent-engine state during a profile transition.
abstract final class EngineProfileLifecycle {
  /// Fail closed before the outgoing profile can cross an await boundary.
  static void prepareDeactivate() {
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
  }

  /// Resolve storage and rebuild parsed engines under the published scope.
  /// Profile rollback calls the same path, so the restored profile is warmed
  /// just as deliberately as a successful candidate.
  static Future<void> warmCurrentScope() async {
    LocalEngineStorage.instance.resetProfileScope();
    await EngineRegistry.instance.reload();
  }
}
