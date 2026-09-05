import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
// Flutter's test SDK supplies fake_async transitively for deterministic timers.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Uint8List marker;
  late OpenedWebDavSyncRoot root;

  setUp(() async {
    final codec = WebDavSyncCodec(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    root = await codec.openRoot(marker, 'circle-secret');
  });

  WebDavSyncCycleContext context() => WebDavSyncCycleContext(
    namespaceId: 'circle:circle-1',
    deviceId: 'device-a',
    markerPin: marker,
    root: root,
    circleToLocalProfiles: const <String, String>{
      'profile-circle': 'local-profile',
    },
    circleToLocalResources: const <String, String>{},
    active: true,
  );

  test('scheduler starts unarmed and performs no cycle', () async {
    final runner = _Runner();
    final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
    addTearDown(scheduler.dispose);

    final report = await scheduler.signal(WebDavSyncTrigger.launch);

    expect(report.disposition, WebDavSyncCycleDisposition.inactive);
    expect(runner.runs, 0);
  });

  test('scheduler disarm closes retained cycle transports', () {
    final runner = _Runner();
    final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
    scheduler.arm(() async => context());

    scheduler.disarm();

    expect(runner.transportCloses, 1);
  });

  test('disarm during an in-flight poll cannot touch the rearmed client', () {
    fakeAsync((async) {
      final clients = <_PollClient>[];
      final owner = WebDavSyncBindingHttpClientOwner(
        clientFactory: () {
          final client = _PollClient();
          clients.add(client);
          return client;
        },
      );
      final staleBorrow = owner.borrow('binding-a');
      final runner = _Runner()..onTransportClose = owner.close;
      final staleTransport = _PollTransport(
        clock: () => DateTime.utc(2026, 9, 1).add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final pendingContext = Completer<WebDavSyncRemotePollContext?>();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => DateTime.utc(2026, 9, 1).add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () => pendingContext.future,
      );
      async.elapse(idlePollPeriod);
      async.flushMicrotasks();

      scheduler.disarm();
      final rearmedBorrow = owner.borrow('binding-a');
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => null,
      );
      pendingContext.complete(
        WebDavSyncRemotePollContext(
          transport: staleTransport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
          clientGeneration: staleBorrow.generation,
          isClientGenerationCurrent: owner.isGenerationCurrent,
        ),
      );
      async.flushMicrotasks();

      expect(staleTransport.probedDeviceIds, isEmpty);
      expect(clients, hasLength(2));
      expect(clients.first.closeCalls, 1);
      expect(clients.last.closeCalls, 0);
      expect(owner.isGenerationCurrent(rearmedBorrow.generation), isTrue);

      scheduler.disarm();
      expect(clients.last.closeCalls, 1);
      scheduler.dispose();
      expect(clients.last.closeCalls, 1);
    });
  });

  test('scheduler admits the dedicated registry and library keys', () {
    expect(
      WebDavSyncScheduler.admitsLocalChangeKey(
        ProfilePreferences.webDavSyncRegistryLogicalKey,
      ),
      isTrue,
    );
    expect(
      WebDavSyncScheduler.admitsLocalChangeKey(
        ProfilePreferences.webDavSyncLibraryLogicalKey,
      ),
      isTrue,
    );
    expect(
      WebDavSyncScheduler.admitsLocalChangeKey(
        'remote_webdav_sync_registry_other',
      ),
      isFalse,
    );
  });

  test('hot-local-only checkpoint writes are not admitted or scheduled', () {
    fakeAsync((async) {
      final observedKeys = <String>[];
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        localChangeObserver: observedKeys.add,
      );
      scheduler.arm(() async => context());

      expect(
        WebDavSyncScheduler.admitsLocalChangeKey(
          WebDavSyncHotMerge.mdblistSyncCheckpointPreference,
        ),
        isFalse,
      );
      scheduler.notifyLocalChange(
        WebDavSyncHotMerge.mdblistSyncCheckpointPreference,
      );
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(runner.runs, 0);
      expect(observedKeys, isEmpty);
      scheduler.dispose();
    });
  });

  test(
    'armed scheduler debounces automatic triggers but manual bypasses',
    () async {
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => DateTime.utc(2026, 9, 1),
      );
      addTearDown(scheduler.dispose);
      scheduler.arm(() async => context());

      await scheduler.signal(WebDavSyncTrigger.foreground);
      await scheduler.signal(WebDavSyncTrigger.playbackStopped);
      await scheduler.signal(WebDavSyncTrigger.manual);

      expect(runner.runs, 2);
    },
  );

  test('TV playback and tvOS low-memory gates suppress work', () async {
    final runner = _Runner();
    final gate = _Gate()..televisionPlayback = true;
    final scheduler = WebDavSyncScheduler(runner: runner, gate: gate);
    addTearDown(scheduler.dispose);
    scheduler.arm(() async => context());

    await scheduler.signal(WebDavSyncTrigger.manual);
    gate
      ..televisionPlayback = false
      ..lowMemory = true;
    await scheduler.signal(WebDavSyncTrigger.manual);

    expect(runner.runs, 0);
  });

  test(
    'a backward local clock does not suppress automatic sync forever',
    () async {
      var now = DateTime.utc(2026, 9, 2);
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => now,
      );
      addTearDown(scheduler.dispose);
      scheduler.arm(() async => context());

      await scheduler.signal(WebDavSyncTrigger.foreground);
      now = DateTime.utc(2026, 9, 1);
      await scheduler.signal(WebDavSyncTrigger.foreground);

      expect(runner.runs, 2);
    },
  );

  test('concurrent signals cannot race while context is loading', () async {
    final runner = _Runner();
    final gate = Completer<WebDavSyncCycleContext?>();
    final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
    addTearDown(scheduler.dispose);
    scheduler.arm(() => gate.future);

    final first = scheduler.signal(WebDavSyncTrigger.manual);
    final second = await scheduler.signal(WebDavSyncTrigger.manual);
    gate.complete(context());
    final firstReport = await first;

    expect(second.disposition, WebDavSyncCycleDisposition.inactive);
    expect(firstReport.disposition, WebDavSyncCycleDisposition.completed);
    expect(runner.runs, 1);
  });

  test('burst of ten local changes runs once two seconds after first', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(() async => context());

      for (var index = 0; index < 10; index++) {
        scheduler.notifyLocalChange('theme');
        async.elapse(const Duration(milliseconds: 100));
      }
      // The window opens at the FIRST write of the burst, so it fires 2s
      // after t=0 (not after the last write).
      async.elapse(const Duration(milliseconds: 850));
      expect(runner.runs, 0);

      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();
      expect(runner.runs, 1);
      expect(runner.triggers, <WebDavSyncTrigger?>[
        WebDavSyncTrigger.localChange,
      ]);
      scheduler.dispose();
    });
  });

  test('lifecycle flush runs immediately only with a pending intent', () {
    fakeAsync((async) {
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
      scheduler.arm(() async => context());

      // Nothing pending: a focus flip or shade pull spends no cycle.
      scheduler.flushPendingLocalChangeForLifecycle();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(runner.runs, 0);

      scheduler.notifyLocalChange('theme');
      scheduler.flushPendingLocalChangeForLifecycle();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(runner.runs, 1, reason: 'the flush bypasses the 2s window');
      expect(runner.triggers, <WebDavSyncTrigger?>[
        WebDavSyncTrigger.localChange,
      ]);

      // The completed cycle cleared the intent; the next flip is free again.
      scheduler.flushPendingLocalChangeForLifecycle();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(runner.runs, 1);
      scheduler.dispose();
    });
  });

  test('lifecycle flush is not blocked by an in-flight poll probe', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: const <String, WebDavSyncManifestProbe>{
          'device-b': WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      )..probeBlocker = Completer<void>();
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      // Reach the first idle probe and leave its request hanging, the way a
      // slow server holds a poll open across a lifecycle handoff.
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isNotEmpty);

      scheduler.notifyLocalChange('theme');
      scheduler.flushPendingLocalChangeForLifecycle();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(
        runner.runs,
        1,
        reason: 'the flush cycle must start while the probe still hangs',
      );

      transport.probeBlocker!.complete();
      async.flushMicrotasks();
      scheduler.dispose();
    });
  });

  test('flush during a covering cycle adds no redundant follow-up', () {
    fakeAsync((async) {
      final firstRun = Completer<void>();
      final runner = _Runner()..blocker = firstRun;
      final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      // The running cycle started at the pending sequence: it covers the
      // intent, so the lifecycle flush must not order another cycle.
      scheduler.flushPendingLocalChangeForLifecycle();
      runner.blocker = null;
      firstRun.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(runner.runs, 1);
      scheduler.dispose();
    });
  });

  test('a foreground cycle re-warms remote polling', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: const <String, WebDavSyncManifestProbe>{
          'device-b': WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      // Freshly armed, the scheduler is idle: nothing probes within one warm
      // period.
      async.elapse(warmPollPeriod);
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);

      // Focusing the app runs a foreground cycle. On desktop that is the only
      // attention signal (polling never paused, so resume never re-warms), so
      // it must re-warm on its own: the next probe lands one warm period
      // later instead of waiting out the idle period.
      scheduler.signal(WebDavSyncTrigger.foreground);
      async.flushMicrotasks();
      expect(runner.triggers, contains(WebDavSyncTrigger.foreground));
      async.elapse(warmPollPeriod);
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, hasLength(1));
    });
  });

  test('a foreground cycle never probes ahead of a server-answered backoff', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: const <String, WebDavSyncManifestProbe>{
          'device-b': WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      )..failuresRemaining = 1;
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      // The first idle probe is answered with 429: a server-requested backoff
      // of one idle period that deliberately survives completed cycles.
      async.elapse(idlePollPeriod);
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, hasLength(1));

      // Foreground re-warms, but the backoff deadline still owns the timer:
      // no probe within a warm period...
      scheduler.signal(WebDavSyncTrigger.foreground);
      async.flushMicrotasks();
      async.elapse(warmPollPeriod);
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, hasLength(1));

      // ...and exactly one at the deadline the server asked for.
      async.elapse(idlePollPeriod - warmPollPeriod);
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, hasLength(2));
    });
  });

  test('a completed cycle releases remote-poll backoff jail', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: const <String, WebDavSyncManifestProbe>{
          'device-b': WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      )
        ..failuresRemaining = 3
        ..failWithoutStatus = true;
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      // Three connectivity failures (no HTTP status) escalate to a 240s jail.
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 120));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, hasLength(3));

      // A completed local-change cycle proves the server reachable.
      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      // The next probe runs at the warm cadence, not 240 seconds later.
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
      expect(
        transport.probedDeviceIds.length,
        greaterThan(3),
        reason: 'poll backoff must not outlive a proven-reachable server',
      );
      scheduler.dispose();
    });
  });

  test('local-change visibility reports only the most recent key', () {
    fakeAsync((async) {
      final observedKeys = <String>[];
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        localChangeObserver: observedKeys.add,
      );
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      scheduler.notifyLocalChange('subtitle_language');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(runner.runs, 1);
      expect(observedKeys, <String>['subtitle_language']);
      scheduler.dispose();
    });
  });

  test('a sustained write stream cannot starve the local-change push', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(() async => context());

      // Writes every second forever; the 2s window must still fire on schedule.
      for (var index = 0; index < 6; index++) {
        scheduler.notifyLocalChange('theme');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
      }
      expect(runner.runs, greaterThanOrEqualTo(2));
      scheduler.dispose();
    });
  });

  test('playback uses sixty-second local-change coalescing', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final gate = _Gate()..playback = true;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: gate,
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 59));
      async.flushMicrotasks();
      expect(runner.runs, 0);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(runner.runs, 1);
      scheduler.dispose();
    });
  });

  test('local change during a run schedules exactly one delayed follow-up', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final firstRun = Completer<void>();
      final runner = _Runner()..blocker = firstRun;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      for (var index = 0; index < 10; index++) {
        scheduler.notifyLocalChange('theme');
      }
      runner.blocker = null;
      firstRun.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(runner.runs, 2);
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(runner.runs, 2);
      scheduler.dispose();
    });
  });

  test('capacity block suppresses retries until the next local write', () {
    fakeAsync((async) {
      final runner = _Runner()
        ..nextDisposition = WebDavSyncCycleDisposition.capacityBlocked;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        remotePollingEnabled: false,
      );
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      async.elapse(const Duration(minutes: 31));
      async.flushMicrotasks();
      unawaited(scheduler.signal(WebDavSyncTrigger.foreground));
      unawaited(scheduler.signal(WebDavSyncTrigger.remoteChange));
      async.flushMicrotasks();
      expect(runner.runs, 1, reason: 'the over-cap revision stays latched');

      runner.nextDisposition = WebDavSyncCycleDisposition.completed;
      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 2, reason: 'a new local revision re-arms sync');
      scheduler.dispose();
    });
  });

  test('registry conflict overrides a pending debounce with one follow-up', () {
    fakeAsync((async) {
      final runner = _Runner()..requestFollowUpOnNextRun = true;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => DateTime.utc(2026, 9, 1).add(async.elapsed),
      );
      scheduler.arm(() async => context());

      // An ordinary write already has the two-second coalescing timer armed
      // when the manual cycle discovers the fenced conflict.
      scheduler.notifyLocalChange('theme');
      unawaited(scheduler.signal(WebDavSyncTrigger.manual));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(runner.runs, 2);
      expect(runner.triggers, <WebDavSyncTrigger?>[
        WebDavSyncTrigger.manual,
        WebDavSyncTrigger.localChange,
      ]);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 2);
      scheduler.dispose();
    });
  });

  test('local-change cycles respect television and low-memory gates', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final gate = _Gate()..televisionPlayback = true;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: gate,
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(runner.runs, 0);

      gate
        ..televisionPlayback = false
        ..lowMemory = true;
      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(runner.runs, 0);
      scheduler.dispose();
    });
  });

  test('disarm cancels a pending local-change cycle', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(() async => context());

      scheduler.notifyLocalChange('theme');
      scheduler.disarm();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(runner.runs, 0);
      expect(scheduler.isArmed, isFalse);
      scheduler.dispose();
    });
  });

  test('local-change completion warms polling then decays to idle', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(milliseconds: 1999));
      async.flushMicrotasks();
      expect(runner.runs, 0);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(runner.runs, 1);
      expect(transport.probedDeviceIds, isEmpty);

      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.probeSeconds, <int>[7]);

      async.elapse(const Duration(minutes: 2, seconds: 50));
      async.flushMicrotasks();
      expect(transport.probeSeconds.last, 177);
      final warmProbeCount = transport.probeSeconds.length;

      // Warmth expires at t=182. That boundary re-arms the idle cadence,
      // whose next probe is sixty seconds later without another event.
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(transport.probeSeconds, hasLength(warmProbeCount));
      async.elapse(const Duration(seconds: 59));
      async.flushMicrotasks();
      expect(transport.probeSeconds, hasLength(warmProbeCount));
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.probeSeconds.last, 242);
      scheduler.dispose();
    });
  });

  test('manual sync warms remote polling', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      unawaited(scheduler.signal(WebDavSyncTrigger.manual));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(transport.probeSeconds, <int>[5]);
      scheduler.dispose();
    });
  });

  test('changed validator starts one cycle and warms remote polling', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      var storedValidator = const WebDavSyncManifestValidator.etag('"v1"');
      final runner = _Runner()
        ..onRun = (trigger) {
          if (trigger == WebDavSyncTrigger.remoteChange) {
            storedValidator = const WebDavSyncManifestValidator.etag('"v2"');
          }
        };
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v2"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: <String, WebDavSyncManifestValidator>{
            'device-b': storedValidator,
          },
        ),
      );

      async.elapse(const Duration(seconds: 65));
      async.flushMicrotasks();

      expect(runner.runs, 1);
      expect(runner.triggers, <WebDavSyncTrigger?>[
        WebDavSyncTrigger.remoteChange,
      ]);
      expect(transport.probeSeconds, <int>[60, 65]);
      scheduler.dispose();
    });
  });

  test('unchanged validators start no polling cycles', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();

      expect(transport.probedDeviceIds, hasLength(5));
      expect(runner.runs, 0);
      scheduler.dispose();
    });
  });

  test('no-validator server disables poll but periodic sync continues', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: null,
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{},
        ),
      );

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(scheduler.pollState, WebDavSyncPollState.disabledNoValidators);
      expect(runner.runs, 0);

      async.elapse(const Duration(minutes: 14));
      async.flushMicrotasks();
      expect(runner.triggers, <WebDavSyncTrigger?>[WebDavSyncTrigger.periodic]);
      expect(transport.probedDeviceIds, <String>['device-b']);
      scheduler.dispose();
    });
  });

  test('429 poll failures back off to fifteen minutes and success resets', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final runner = _Runner();
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      )..failuresRemaining = 5;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      void advanceTo(int seconds) {
        async.elapse(Duration(seconds: seconds) - async.elapsed);
        async.flushMicrotasks();
      }

      advanceTo(60);
      expect(scheduler.pollState, WebDavSyncPollState.pausedBackoff);
      advanceTo(120);
      advanceTo(180);
      advanceTo(240);
      advanceTo(480);
      advanceTo(960);
      advanceTo(1860);
      expect(transport.probeSeconds, <int>[60, 120, 240, 480, 960, 1860]);
      expect(scheduler.pollState, WebDavSyncPollState.active);

      advanceTo(1920);
      expect(transport.probeSeconds.last, 1920);
      expect(
        runner.triggers.where(
          (trigger) => trigger == WebDavSyncTrigger.remoteChange,
        ),
        isEmpty,
      );
      scheduler.dispose();
    });
  });

  test('failure backoff overrides warm cadence and resets on success', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      )..failuresRemaining = 1;
      final scheduler = WebDavSyncScheduler(
        runner: _Runner(),
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      scheduler.pauseRemotePolling();
      scheduler.resumeRemotePolling();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(transport.probeSeconds, <int>[5]);
      expect(scheduler.pollState, WebDavSyncPollState.pausedBackoff);

      async.elapse(const Duration(seconds: 59));
      async.flushMicrotasks();
      expect(transport.probeSeconds, <int>[5]);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.probeSeconds, <int>[5, 65]);
      expect(scheduler.pollState, WebDavSyncPollState.active);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(transport.probeSeconds, <int>[5, 65, 70]);
      scheduler.dispose();
    });
  });

  test('foreground resume warms polling and background pauses it', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: _Runner(),
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      scheduler.pauseRemotePolling();
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);
      expect(scheduler.pollState, WebDavSyncPollState.gated);

      scheduler.resumeRemotePolling();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, <String>['device-b']);

      scheduler.pauseRemotePolling();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, <String>['device-b']);
      expect(scheduler.pollState, WebDavSyncPollState.gated);
      scheduler.dispose();
    });
  });

  test('disabled poll define gate wins over every warm trigger', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: _Runner(),
        gate: _Gate(),
        remotePollingEnabled: false,
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      unawaited(scheduler.signal(WebDavSyncTrigger.manual));
      async.flushMicrotasks();
      scheduler.notifyLocalChange('theme');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      scheduler.pauseRemotePolling();
      scheduler.resumeRemotePolling();
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();

      expect(transport.probedDeviceIds, isEmpty);
      expect(scheduler.pollState, WebDavSyncPollState.gated);
      scheduler.dispose();
    });
  });

  test('poll skips a running cycle and never probes unknown device IDs', () {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 9, 1);
      final blocked = Completer<void>();
      final runner = _Runner()..blocker = blocked;
      final transport = _PollTransport(
        clock: () => start.add(async.elapsed),
        probes: <String, WebDavSyncManifestProbe>{
          'device-b': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"v1"'),
          ),
          'unknown-device': const WebDavSyncManifestProbe(
            exists: true,
            validator: WebDavSyncManifestValidator.etag('"new"'),
          ),
        },
      );
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => start.add(async.elapsed),
      );
      scheduler.arm(
        () async => context(),
        remotePollContextProvider: () async => WebDavSyncRemotePollContext(
          transport: transport,
          peerDeviceIds: const <String>['device-b'],
          validators: const <String, WebDavSyncManifestValidator>{
            'device-b': WebDavSyncManifestValidator.etag('"v1"'),
          },
        ),
      );

      unawaited(scheduler.signal(WebDavSyncTrigger.manual));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);

      runner.blocker = null;
      blocked.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, <String>['device-b']);
      expect(transport.probedDeviceIds, isNot(contains('unknown-device')));
      scheduler.dispose();
    });
  });

  test('every raw preference key consumed by the hot builder is admitted', () {
    final source = File(
      'lib/services/webdav_sync/webdav_sync_hot_merge.dart',
    ).readAsStringSync();
    final block = source.substring(
      source.indexOf('abstract final class WebDavSyncHotMerge'),
      source.indexOf('/// Per-device cursor used by MDBList'),
    );
    final declarations = RegExp(
      r"static const String (\w+)\s*=\s*'([^']*)';",
      multiLine: true,
    ).allMatches(block);
    final consumedKeys = <String>[
      for (final match in declarations)
        match.group(1)!.endsWith('Prefix')
            ? '${match.group(2)!}drift-probe'
            : match.group(2)!,
    ];

    expect(consumedKeys, hasLength(7));
    expect(
      consumedKeys,
      everyElement(predicate<String>(WebDavSyncScheduler.admitsLocalChangeKey)),
    );
  });

  test('every hot-local-only scalar key is excluded from admission', () {
    expect(WebDavSyncHotMerge.hotLocalOnlyScalarKeys, isNotEmpty);
    expect(
      WebDavSyncHotMerge.hotLocalOnlyScalarKeys,
      everyElement(
        predicate<String>(
          (key) => !WebDavSyncScheduler.admitsLocalChangeKey(key),
        ),
      ),
    );
  });

  group('durable local-change intent', () {
    for (final networkFailure in [false, true]) {
      test(
        'profile switch preserves intent and handles network=$networkFailure backoff',
        () {
          ProfileRuntime.debugReset();
          ProfileRuntime.initializeCommitted(
            ProfileScope(profileId: 'a', dataGeneration: 1, sessionEpoch: 1),
          );
          try {
            fakeAsync((async) {
              final delays = <Duration>[];
              final runner = _Runner()..failuresRemaining = 3;
              runner.onRun = (_) {
                if (runner.runs == 3) {
                  ProfileRuntime.publish(
                    ProfileScope(
                      profileId: 'b',
                      dataGeneration: 1,
                      sessionEpoch: 2,
                    ),
                  );
                  if (networkFailure) {
                    throw const WebDavException(
                      kind: WebDavErrorKind.network,
                      message: 'offline',
                    );
                  }
                }
              };
              final scheduler = WebDavSyncScheduler(
                runner: runner,
                gate: _Gate(),
                localChangeDeferredObserver: (_, __, delay) =>
                    delays.add(delay),
              );
              scheduler.arm(() async => context());
              scheduler.notifyLocalChange('home_tick_sources');
              async.elapse(const Duration(seconds: 8));
              expect(runner.runs, 3);
              expect(delays, [
                const Duration(seconds: 2),
                const Duration(seconds: 4),
                Duration(seconds: networkFailure ? 8 : 2),
              ]);
              runner.failuresRemaining = 0;
              async.elapse(Duration(seconds: networkFailure ? 8 : 2));
              expect(runner.runs, 4);
              async.elapse(const Duration(minutes: 2));
              expect(runner.runs, 4);
              scheduler.dispose();
            });
          } finally {
            ProfileRuntime.debugReset();
          }
        },
      );
    }

    test('a failed cycle re-arms the intent and the retry pushes', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner()..failuresRemaining = 1;
        final deferred = <String>[];
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
          localChangeDeferredObserver: (reason, attempt, delay) =>
              deferred.add('$reason#$attempt/${delay.inSeconds}'),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(runner.runs, 1); // attempt failed
        expect(deferred, isNotEmpty);
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(runner.runs, 2); // bounded retry flushed the intent
        async.elapse(const Duration(minutes: 3));
        expect(runner.runs, 2); // cleared: no storm afterwards
        scheduler.dispose();
      });
    });

    test('a gated attempt re-arms instead of dropping', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner();
        final gate = _Gate()..lowMemory = true;
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: gate,
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(runner.runs, 0);
        gate.lowMemory = false;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        scheduler.dispose();
      });
    });

    test('an inactive context re-arms instead of dropping', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner();
        var provideContext = false;
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(() async => provideContext ? context() : null);
        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(runner.runs, 0); // context refused; intent must survive
        provideContext = true;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        scheduler.dispose();
      });
    });

    test('a non-completed disposition re-arms', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner()
          ..nextDisposition = WebDavSyncCycleDisposition.adoptionBlocked;
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        runner.nextDisposition = WebDavSyncCycleDisposition.completed;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(runner.runs, 2);
        async.elapse(const Duration(minutes: 3));
        expect(runner.runs, 2);
        scheduler.dispose();
      });
    });

    test('a same-tick write survives the older cycle and a timer disarm', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner();
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        runner.blocker = Completer<void>();
        scheduler.arm(() async => context());
        // This is the cycle a warm poll starts after observing a changed peer.
        unawaited(scheduler.signal(WebDavSyncTrigger.remoteChange));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        // Lands mid-cycle, without advancing the injected wall clock.
        scheduler.notifyLocalChange('home_tick_sources');
        runner.blocker!.complete();
        runner.blocker = null;
        async.flushMicrotasks();
        // The fake clock has not advanced since the cycle started. A wall-time
        // comparison therefore cannot distinguish this write from the older
        // snapshot. Cancel the dirty follow-up to prove the durable marker,
        // rather than that incidental timer, retains the intent.
        scheduler.disarm();
        scheduler.arm(() async => context());
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 2); // follow-up flushed the mid-cycle write
        async.elapse(const Duration(minutes: 3));
        expect(runner.runs, 2);
        scheduler.dispose();
      });
    });

    test('arm during the initial window replaces it with one fresh kick', () {
      fakeAsync((async) {
        final runner = _Runner();
        final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');

        async.elapse(const Duration(seconds: 1));
        scheduler.arm(() async => context());
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(runner.runs, 0); // the old window was cancelled
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        async.elapse(const Duration(minutes: 3));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        scheduler.dispose();
      });
    });

    test('a throwing context provider re-arms instead of dropping', () {
      fakeAsync((async) {
        final runner = _Runner();
        var contextAttempts = 0;
        final deferred = <String>[];
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          localChangeDeferredObserver: (reason, attempt, delay) =>
              deferred.add('$reason#$attempt/${delay.inSeconds}'),
        );
        scheduler.arm(() async {
          contextAttempts++;
          if (contextAttempts == 1) throw StateError('context unavailable');
          return context();
        });

        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 0);
        expect(deferred, <String>['cycle did not start#1/2']);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        scheduler.dispose();
      });
    });

    test('a conflict follow-up remains durable across disarm', () {
      fakeAsync((async) {
        final firstRun = Completer<void>();
        final runner = _Runner()
          ..blocker = firstRun
          ..requestFollowUpOnNextRun = true;
        final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        runner.blocker = null;
        firstRun.complete();
        async.flushMicrotasks();

        // Cancel the requested immediate retry before its zero-delay timer can
        // run. The unsatisfied intent must make arm() kick a replacement.
        scheduler.disarm();
        scheduler.arm(() async => context());
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 2);
        scheduler.dispose();
      });
    });

    test('the intent survives a disarm/rearm bounce', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner();
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');
        scheduler.disarm(); // timer cancelled before the window fired
        async.elapse(const Duration(seconds: 10));
        expect(runner.runs, 0);
        scheduler.arm(() async => context());
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        scheduler.dispose();
      });
    });

    test('the intent survives disarm while a retry is armed', () {
      fakeAsync((async) {
        final runner = _Runner()..failuresRemaining = 1;
        final scheduler = WebDavSyncScheduler(runner: runner, gate: _Gate());
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 1);

        scheduler.disarm();
        async.elapse(const Duration(seconds: 10));
        expect(runner.runs, 1);
        scheduler.arm(() async => context());
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 2);
        scheduler.dispose();
      });
    });

    test('playback debounce is the retry backoff base', () {
      fakeAsync((async) {
        final gate = _Gate()..playback = true;
        final runner = _Runner()..failuresRemaining = 1;
        final delays = <Duration>[];
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: gate,
          localChangeDeferredObserver: (_, _, delay) => delays.add(delay),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');

        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        expect(delays, <Duration>[const Duration(seconds: 60)]);
        async.elapse(const Duration(seconds: 59));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(runner.runs, 2);
        scheduler.dispose();
      });
    });

    test('retry delay has a positive floor and saturating cap', () {
      fakeAsync((async) {
        final gate = _Gate();
        final runner = _Runner()..failuresRemaining = 2;
        final delays = <Duration>[];
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: gate,
          localChangeDebounce: Duration.zero,
          playbackDebounce: const Duration(days: 1000000),
          localChangeDeferredObserver: (_, _, delay) => delays.add(delay),
        );
        runner.onRun = (_) {
          gate.playback = runner.runs > 1;
        };
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');

        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(runner.runs, 1);
        expect(delays, <Duration>[WebDavSyncScheduler.localChangeRetryFloor]);

        async.elapse(WebDavSyncScheduler.localChangeRetryFloor);
        async.flushMicrotasks();
        expect(runner.runs, 2);
        expect(delays.last, WebDavSyncScheduler.localChangeRetryCap);

        async.elapse(WebDavSyncScheduler.localChangeRetryCap);
        async.flushMicrotasks();
        expect(runner.runs, 3);
        scheduler.dispose();
      });
    });

    test('deferred observer cannot orphan or duplicate a retry', () {
      fakeAsync((async) {
        final firstRun = Completer<void>();
        final runner = _Runner()
          ..blocker = firstRun
          ..failuresRemaining = 1;
        late final WebDavSyncScheduler scheduler;
        var deferredCalls = 0;
        scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          localChangeDeferredObserver: (_, _, _) {
            deferredCalls++;
            scheduler.notifyConflictFollowUp();
          },
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        runner.blocker = null;
        firstRun.complete();
        async.flushMicrotasks();
        expect(deferredCalls, 1);
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(runner.runs, 2);
        async.elapse(const Duration(minutes: 3));
        async.flushMicrotasks();
        expect(runner.runs, 2);
        expect(deferredCalls, 1);
        scheduler.dispose();
      });
    });

    test('persistent failure backs off bounded with no storm', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner()..failuresRemaining = 1 << 30;
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('home_tick_sources');
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        // 2s window + retries 2,4,8,16,32s then capped repeats; well under
        // one attempt per ten seconds over ten minutes.
        expect(runner.runs, lessThan(12));
        expect(runner.runs, greaterThan(3));
        scheduler.dispose();
      });
    });
  });

  group('playback checkpoint and session warmth', () {
    test('a checkpoint flushes the playback window immediately', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner();
        final gate = _Gate()..playback = true;
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: gate,
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('playback_state_v1');
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(runner.runs, 0); // still inside the 60s playback window
        for (var index = 0; index < 20; index++) {
          scheduler.notifyPlaybackCheckpoint(); // pause/seek burst
        }
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(runner.runs, 1);
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(runner.runs, 1); // replaced playback timer never fires later
        scheduler.dispose();
      });
    });

    test('an immediate checkpoint preserves durable retry accounting', () {
      fakeAsync((async) {
        final runner = _Runner()..failuresRemaining = 2;
        final delays = <Duration>[];
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          localChangeDeferredObserver: (_, _, delay) => delays.add(delay),
        );
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('playback_state_v1');

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        expect(delays, <Duration>[const Duration(seconds: 2)]);

        async.elapse(const Duration(seconds: 1));
        scheduler.notifyPlaybackCheckpoint();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(runner.runs, 2);
        expect(delays, <Duration>[
          const Duration(seconds: 2),
          const Duration(seconds: 4),
        ]);

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(runner.runs, 2);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(runner.runs, 3);
        scheduler.dispose();
      });
    });

    test('television checkpoints leave the gated retry timer untouched', () {
      fakeAsync((async) {
        final gate = _Gate()..televisionPlayback = true;
        final runner = _Runner();
        final scheduler = WebDavSyncScheduler(runner: runner, gate: gate);
        scheduler.arm(() async => context());
        scheduler.notifyLocalChange('playback_state_v1');

        async.elapse(const Duration(seconds: 30));
        for (var index = 0; index < 20; index++) {
          scheduler.notifyPlaybackCheckpoint();
        }
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(runner.runs, 0);

        gate.televisionPlayback = false;
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(runner.runs, 1);
        scheduler.dispose();
      });
    });

    test(
      'a checkpoint during a running cycle produces one immediate follow-up',
      () {
        fakeAsync((async) {
          final start = DateTime.utc(2026, 9, 3);
          final runner = _Runner();
          final scheduler = WebDavSyncScheduler(
            runner: runner,
            gate: _Gate(),
            clock: () => start.add(async.elapsed),
          );
          runner.blocker = Completer<void>();
          scheduler.arm(() async => context());
          scheduler.notifyLocalChange('playback_state_v1');
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();
          expect(runner.runs, 1);
          scheduler.notifyPlaybackCheckpoint();
          scheduler.notifyPlaybackCheckpoint(); // burst coalesces
          runner.blocker!.complete();
          runner.blocker = null;
          async.flushMicrotasks();
          async.elapse(Duration.zero);
          async.flushMicrotasks();
          expect(runner.runs, 2);
          async.elapse(const Duration(seconds: 30));
          expect(runner.runs, 2);
          scheduler.dispose();
        });
      },
    );

    test('extendWarmSession keeps the fast poll cadence alive', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        final runner = _Runner();
        var probes = 0;
        final scheduler = WebDavSyncScheduler(
          runner: runner,
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(
          () async => context(),
          remotePollContextProvider: () async {
            probes++;
            return null; // counted, then treated as inactive
          },
        );
        // Idle past the initial warm window so cadence decays.
        async.elapse(const Duration(minutes: 4));
        final decayed = probes;
        // Remote watch activity arrives: cadence must return to warm.
        scheduler.extendWarmSession();
        async.elapse(const Duration(seconds: 30));
        final warmed = probes - decayed;
        expect(warmed, greaterThanOrEqualTo(5)); // ~6 probes at 5s cadence
        scheduler.dispose();
      });
    });

    test('warm polling decays after real watch activity stops', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 9, 3);
        var probes = 0;
        final scheduler = WebDavSyncScheduler(
          runner: _Runner(),
          gate: _Gate(),
          clock: () => start.add(async.elapsed),
        );
        scheduler.arm(
          () async => context(),
          remotePollContextProvider: () async {
            probes++;
            return null;
          },
        );
        scheduler.extendWarmSession();

        async.elapse(warmDuration);
        async.flushMicrotasks();
        final atExpiry = probes;
        expect(atExpiry, greaterThanOrEqualTo(35));
        async.elapse(const Duration(seconds: 59));
        async.flushMicrotasks();
        expect(probes, atExpiry);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(probes, atExpiry + 1);
        scheduler.dispose();
      });
    });
  });
}

final class _Runner
    implements WebDavSyncCycleRunner, WebDavSyncCycleTransportOwner {
  int runs = 0;
  int transportCloses = 0;
  void Function()? onTransportClose;
  Completer<void>? blocker;
  void Function(WebDavSyncTrigger? trigger)? onRun;
  bool requestFollowUpOnNextRun = false;
  final List<WebDavSyncTrigger?> triggers = <WebDavSyncTrigger?>[];

  @override
  void closeCycleTransports() {
    transportCloses++;
    onTransportClose?.call();
  }

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  }) async {
    runs++;
    triggers.add(trigger);
    onRun?.call(trigger);
    await blocker?.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('cycle failed for the fixture');
    }
    final followUp = requestFollowUpOnNextRun;
    requestFollowUpOnNextRun = false;
    return WebDavSyncCycleReport(
      disposition: nextDisposition,
      localChangeFollowUp: followUp,
    );
  }

  int failuresRemaining = 0;
  WebDavSyncCycleDisposition nextDisposition =
      WebDavSyncCycleDisposition.completed;
}

final class _PollClient extends http.BaseClient {
  int closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

final class _Gate implements WebDavSyncRuntimeGate {
  bool playback = false;
  bool televisionPlayback = false;
  bool lowMemory = false;

  @override
  bool get playbackActive => playback || televisionPlayback;

  @override
  bool get playbackActiveOnTelevision => televisionPlayback;

  @override
  bool get tvOsLowMemory => lowMemory;
}

final class _PollTransport implements WebDavSyncTransport {
  _PollTransport({required this.clock, required this.probes});

  final DateTime Function() clock;
  final Map<String, WebDavSyncManifestProbe> probes;
  final List<String> probedDeviceIds = <String>[];
  final List<int> probeSeconds = <int>[];
  int failuresRemaining = 0;

  Completer<void>? probeBlocker;
  bool failWithoutStatus = false;

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) async {
    probedDeviceIds.add(deviceId);
    probeSeconds.add(clock().difference(DateTime.utc(2026, 9, 1)).inSeconds);
    if (probeBlocker != null) await probeBlocker!.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      if (failWithoutStatus) {
        throw const WebDavException(
          kind: WebDavErrorKind.transient,
          message: 'offline',
        );
      }
      throw const WebDavException(
        kind: WebDavErrorKind.transient,
        message: 'rate limited',
        statusCode: HttpStatus.tooManyRequests,
      );
    }
    return probes[deviceId]!;
  }

  @override
  Future<void> ensureOwnLayout(String deviceId) => throw UnimplementedError();

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() => throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readRootMarker() => throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) => throw UnimplementedError();

  @override
  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  ) => throw UnimplementedError();

  @override
  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  }) => throw UnimplementedError();

  @override
  void close() {}
}
