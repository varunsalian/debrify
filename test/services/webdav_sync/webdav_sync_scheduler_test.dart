import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
// Flutter's test SDK supplies fake_async transitively for deterministic timers.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('burst of ten local changes runs once after trailing debounce', () {
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
      // The window opens at the FIRST write of the burst, so it fires 10s
      // after t=0 (not after the last write).
      async.elapse(const Duration(milliseconds: 8850));
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

      // Writes every 5s forever; the 10s window must still fire on schedule.
      for (var index = 0; index < 6; index++) {
        scheduler.notifyLocalChange('theme');
        async.elapse(const Duration(seconds: 5));
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
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(runner.runs, 1);

      for (var index = 0; index < 10; index++) {
        scheduler.notifyLocalChange('theme');
      }
      runner.blocker = null;
      firstRun.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 9));
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
      async.elapse(const Duration(seconds: 10));
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
}

final class _Runner implements WebDavSyncCycleRunner {
  int runs = 0;
  Completer<void>? blocker;
  final List<WebDavSyncTrigger?> triggers = <WebDavSyncTrigger?>[];

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  }) async {
    runs++;
    triggers.add(trigger);
    await blocker?.future;
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
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
