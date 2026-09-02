import 'dart:async';
import 'dart:typed_data';

import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
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
    final gate = _Gate()..playback = true;
    final scheduler = WebDavSyncScheduler(runner: runner, gate: gate);
    addTearDown(scheduler.dispose);
    scheduler.arm(() async => context());

    await scheduler.signal(WebDavSyncTrigger.manual);
    gate
      ..playback = false
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
}

final class _Runner implements WebDavSyncCycleRunner {
  int runs = 0;

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
  }) async {
    runs++;
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
  }
}

final class _Gate implements WebDavSyncRuntimeGate {
  bool playback = false;
  bool lowMemory = false;

  @override
  bool get playbackActiveOnTelevision => playback;

  @override
  bool get tvOsLowMemory => lowMemory;
}
