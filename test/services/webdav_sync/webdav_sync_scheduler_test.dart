import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
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

  test('scheduler admits only the dedicated registry synthetic key', () {
    expect(
      WebDavSyncScheduler.admitsLocalChangeKey(
        ProfilePreferences.webDavSyncRegistryLogicalKey,
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

  test('registry conflict overrides a pending debounce with one follow-up', () {
    fakeAsync((async) {
      final runner = _Runner()..requestFollowUpOnNextRun = true;
      final scheduler = WebDavSyncScheduler(
        runner: runner,
        gate: _Gate(),
        clock: () => DateTime.utc(2026, 9, 1).add(async.elapsed),
      );
      scheduler.arm(() async => context());

      // An ordinary write already has the ten-second coalescing timer armed
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
      async.elapse(const Duration(seconds: 10));
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

  test('changed validator starts exactly one remote-change cycle', () {
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

      async.elapse(const Duration(minutes: 3));
      async.flushMicrotasks();

      expect(runner.runs, 1);
      expect(runner.triggers, <WebDavSyncTrigger?>[
        WebDavSyncTrigger.remoteChange,
      ]);
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

  test('remote polling pauses in background and resumes cleanly', () {
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
      async.elapse(const Duration(seconds: 59));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, isEmpty);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(transport.probedDeviceIds, <String>['device-b']);
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
      async.elapse(const Duration(seconds: 60));
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
}

final class _Runner implements WebDavSyncCycleRunner {
  int runs = 0;
  Completer<void>? blocker;
  void Function(WebDavSyncTrigger? trigger)? onRun;
  bool requestFollowUpOnNextRun = false;
  final List<WebDavSyncTrigger?> triggers = <WebDavSyncTrigger?>[];

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
    final followUp = requestFollowUpOnNextRun;
    requestFollowUpOnNextRun = false;
    return WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
      localChangeFollowUp: followUp,
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

final class _PollTransport implements WebDavSyncTransport {
  _PollTransport({required this.clock, required this.probes});

  final DateTime Function() clock;
  final Map<String, WebDavSyncManifestProbe> probes;
  final List<String> probedDeviceIds = <String>[];
  final List<int> probeSeconds = <int>[];
  int failuresRemaining = 0;

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) async {
    probedDeviceIds.add(deviceId);
    probeSeconds.add(clock().difference(DateTime.utc(2026, 9, 1)).inSeconds);
    if (failuresRemaining > 0) {
      failuresRemaining--;
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
