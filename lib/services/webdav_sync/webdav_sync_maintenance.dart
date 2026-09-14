import 'dart:async';

import 'webdav_sync_engine.dart';
import 'webdav_sync_operation_coordinator.dart';
import 'webdav_sync_scheduler.dart';

/// Admission is checked after acquiring the shared lock and again after the
/// asynchronous authorization capture, before any snapshot work starts.
Future<void> runWebDavSyncMaintenanceAfterLockGate<T>({
  required WebDavSyncOperationCoordinator operations,
  required WebDavSyncRuntimeGate gate,
  required bool Function() isCurrent,
  required bool Function() isForeground,
  required bool bootstrapOnly,
  required Future<T> Function() prepare,
  required Future<void> Function(T) maintain,
}) {
  bool canRun() =>
      isCurrent() &&
      !gate.playbackActiveOnTelevision &&
      !gate.tvOsLowMemory &&
      (!bootstrapOnly || (isForeground() && !gate.playbackActive));
  return operations.run(() async {
    if (!canRun()) return;
    final prepared = await prepare();
    if (!canRun()) return;
    await maintain(prepared);
  });
}

/// Required repairs remain part of the requested sync. Daily snapshot work
/// is scheduled only after that continuation completes for the same account.
Future<WebDavSyncCycleReport> runWebDavSyncWithMaintenance({
  required Future<WebDavSyncCycleReport> Function() sync,
  required Future<void> Function(WebDavSyncCycleReport) maintainRequired,
  required void Function() scheduleOptional,
  required bool Function() isCurrent,
}) async {
  const inactive = WebDavSyncCycleReport(
    disposition: WebDavSyncCycleDisposition.inactive,
  );
  final report = await sync();
  if (!isCurrent()) return inactive;
  if (report.disposition == WebDavSyncCycleDisposition.completed ||
      report.disposition == WebDavSyncCycleDisposition.seedRepairRequired) {
    await maintainRequired(report);
    if (!isCurrent()) return inactive;
    scheduleOptional();
  }
  return report;
}

/// A coalesced idle attempt, never queued in front of normal sync work.
/// Durability belongs to the existing lastBootstrapCheckMs marker: until a
/// verified refresh advances it, maintenance remains due after a restart.
final class WebDavSyncIdleMaintenance {
  WebDavSyncIdleMaintenance({
    required this.operations,
    required this.canRun,
    required this.maintain,
    this.idleDelay = const Duration(seconds: 30),
    this.retryDelay = const Duration(minutes: 5),
  });

  final WebDavSyncOperationCoordinator operations;
  final bool Function() canRun;
  final Future<void> Function() maintain;
  final Duration idleDelay;
  final Duration retryDelay;
  Timer? _timer;
  bool _running = false;
  int _generation = 0;

  void schedule() => _schedule(idleDelay);

  void _schedule(Duration delay) {
    if (_timer != null) return;
    final generation = _generation;
    _timer = operations.createDeferredTimer(delay, () {
      _timer = null;
      unawaited(_attempt(generation));
    });
  }

  Future<void> _attempt(int generation) async {
    if (generation != _generation) return;
    if (_running || !canRun()) {
      _schedule(idleDelay);
      return;
    }
    _running = true;
    var completed = false;
    var failed = false;
    try {
      completed = await operations.runIfIdle(() async {
        if (generation != _generation || !canRun()) return false;
        await maintain();
        return true;
      }, whenBusy: false);
    } catch (_) {
      // Optional network work retries without changing the foreground result.
      failed = true;
    } finally {
      _running = false;
      if (generation == _generation && !completed) {
        _schedule(failed ? retryDelay : idleDelay);
      }
    }
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}
