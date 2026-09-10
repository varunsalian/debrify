import 'dart:async';

import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_maintenance.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_operation_coordinator.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
// Flutter's test SDK supplies fake_async for deterministic timers.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'onboarding can create and schedule idle maintenance inside nested operations',
    () {
      fakeAsync((async) {
        final operations = WebDavSyncOperationCoordinator();
        late WebDavSyncIdleMaintenance idle;
        var runs = 0;
        var coalesced = false;
        unawaited(
          operations.run(
            () => operations.run(() {
              idle = WebDavSyncIdleMaintenance(
                operations: operations,
                canRun: () => true,
                maintain: () async {
                  expect(operations.isRunning, isTrue);
                  runs++;
                  if (runs == 1) throw StateError('retry upload');
                },
              );
              idle.schedule();
            }),
          ),
        );
        async.flushMicrotasks();
        expect(operations.isRunning, isFalse);
        async.elapse(const Duration(seconds: 30));
        expect(runs, 1);
        unawaited(
          operations.run(() {
            idle.schedule();
            coalesced = true;
          }),
        );
        async.flushMicrotasks();
        expect(coalesced, isTrue);
        async.elapse(const Duration(minutes: 5));
        expect(
          runs,
          2,
          reason: 'retry must also be outside the expired lock scope',
        );
        idle.cancel();
      });
    },
  );

  for (final lowMemory in [false, true]) {
    for (final duringPrepare in [false, true]) {
      test(
        'required maintenance checks TV hold memory=$lowMemory duringPrepare=$duringPrepare',
        () async {
          final operations = WebDavSyncOperationCoordinator();
          final gate = _MaintenanceGate();
          final releaseCycle = Completer<void>();
          final cycleStarted = Completer<void>();
          final authorizationStarted = Completer<void>();
          final authorization = Completer<int>();
          final events = <String>[];
          void hold() {
            if (lowMemory) {
              gate.lowMemory = true;
            } else {
              gate.televisionPlayback = true;
            }
          }

          final cycle = operations.run(() async {
            cycleStarted.complete();
            await releaseCycle.future;
          });
          await cycleStarted.future;
          final maintenance = runWebDavSyncMaintenanceAfterLockGate(
            operations: operations,
            gate: gate,
            isCurrent: () => true,
            isForeground: () => true,
            bootstrapOnly: false,
            prepare: () {
              events.add('authorize');
              authorizationStarted.complete();
              return authorization.future;
            },
            maintain: (value) async {
              expect(value, 7);
              events.add('publish');
            },
          );
          if (!duringPrepare) hold();
          releaseCycle.complete();
          await cycle;
          if (duringPrepare) {
            await authorizationStarted.future;
            hold();
          }
          authorization.complete(7);
          await maintenance;
          expect(events, duringPrepare ? ['authorize'] : isEmpty);
          gate.lowMemory = false;
          gate.televisionPlayback = false;
          await runWebDavSyncMaintenanceAfterLockGate(
            operations: operations,
            gate: gate,
            isCurrent: () => true,
            isForeground: () => true,
            bootstrapOnly: false,
            prepare: () async => 7,
            maintain: (_) async => events.add('publish'),
          );
          expect(
            events.last,
            'publish',
            reason: 'repair resumes after the hold clears',
          );
        },
      );
    }
  }
  for (final disposition in [
    WebDavSyncCycleDisposition.completed,
    WebDavSyncCycleDisposition.seedRepairRequired,
  ]) {
    test('$disposition waits for repairs but not optional maintenance', () {
      fakeAsync((async) {
        final repair = Completer<void>();
        final snapshot = Completer<void>();
        var snapshots = 0;
        final idle = WebDavSyncIdleMaintenance(
          operations: WebDavSyncOperationCoordinator(),
          canRun: () => true,
          maintain: () async {
            snapshots++;
            await snapshot.future;
          },
        );
        WebDavSyncCycleReport? result;
        runWebDavSyncWithMaintenance(
          sync: () async => WebDavSyncCycleReport(disposition: disposition),
          maintainRequired: (_) => repair.future,
          scheduleOptional: idle.schedule,
          isCurrent: () => true,
        ).then((value) => result = value);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(result, isNull);
        expect(snapshots, 0);
        repair.complete();
        async.flushMicrotasks();
        expect(result?.disposition, disposition);
        async.elapse(const Duration(seconds: 30));
        expect(snapshots, 1);
        expect(snapshot.isCompleted, isFalse);
        snapshot.complete();
        async.flushMicrotasks();
        idle.cancel();
      });
    });
  }

  test('required publication failure is not reported as success', () async {
    var scheduled = false;
    await expectLater(
      runWebDavSyncWithMaintenance(
        sync: () async => const WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.completed,
        ),
        maintainRequired: (_) async => throw StateError('verification failed'),
        scheduleOptional: () => scheduled = true,
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(scheduled, isFalse);
  });

  test(
    'old-account completion cannot repair or schedule the new account',
    () async {
      var repairs = 0;
      var scheduled = false;
      final result = await runWebDavSyncWithMaintenance(
        sync: () async => const WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.completed,
        ),
        maintainRequired: (_) async => repairs++,
        scheduleOptional: () => scheduled = true,
        isCurrent: () => false,
      );
      expect(result.disposition, WebDavSyncCycleDisposition.inactive);
      expect(repairs, 0);
      expect(scheduled, isFalse);
    },
  );

  test(
    'reconfiguration during repair suppresses success and idle work',
    () async {
      var current = true;
      var scheduled = false;
      final result = await runWebDavSyncWithMaintenance(
        sync: () async => const WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.completed,
        ),
        maintainRequired: (_) async => current = false,
        scheduleOptional: () => scheduled = true,
        isCurrent: () => current,
      );
      expect(result.disposition, WebDavSyncCycleDisposition.inactive);
      expect(scheduled, isFalse);
    },
  );

  test(
    'idle maintenance coalesces and yields to playback and sync operations',
    () {
      fakeAsync((async) {
        final operations = WebDavSyncOperationCoordinator();
        var allowed = false;
        var runs = 0;
        final idle = WebDavSyncIdleMaintenance(
          operations: operations,
          canRun: () => allowed,
          maintain: () async => runs++,
        );
        idle.schedule();
        idle.schedule();
        async.elapse(const Duration(seconds: 30));
        expect(runs, 0);
        allowed = true;
        final sync = Completer<void>();
        unawaited(operations.run(() => sync.future));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(runs, 0);
        sync.complete();
        async.flushMicrotasks();
        expect(runs, 0, reason: 'maintenance must not queue behind the sync');
        async.elapse(const Duration(seconds: 30));
        expect(runs, 1);
        async.elapse(const Duration(minutes: 5));
        expect(runs, 1);
        idle.cancel();
      });
    },
  );

  test('optional failures retry and cancellation prevents old retries', () {
    fakeAsync((async) {
      var runs = 0;
      final failure = Completer<void>();
      final idle = WebDavSyncIdleMaintenance(
        operations: WebDavSyncOperationCoordinator(),
        canRun: () => true,
        maintain: () async {
          runs++;
          if (runs == 1) throw StateError('offline');
          await failure.future;
        },
      );
      idle.schedule();
      async.elapse(const Duration(seconds: 30));
      expect(runs, 1);
      async.elapse(const Duration(minutes: 4));
      expect(runs, 1);
      async.elapse(const Duration(minutes: 1));
      expect(runs, 2);
      idle.cancel();
      failure.completeError(StateError('old account disconnected'));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 10));
      expect(runs, 2);
    });
  });
}

final class _MaintenanceGate implements WebDavSyncRuntimeGate {
  bool televisionPlayback = false;
  bool lowMemory = false;

  @override
  bool get playbackActive => televisionPlayback;
  @override
  bool get playbackActiveOnTelevision => televisionPlayback;
  @override
  bool get tvOsLowMemory => lowMemory;
}
