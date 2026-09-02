import 'dart:typed_data';

import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_clock.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_local_adapter.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WebDavSyncCodec codec;
  late Uint8List marker;
  late OpenedWebDavSyncRoot root;
  late _MemoryStateRepository states;
  late _FakeLocalAdapter local;
  late _FakeTransport transport;
  late WebDavSyncEngine engine;
  late WebDavSyncSectionCache sectionCache;
  final now = DateTime.utc(2026, 9, 1);

  setUp(() async {
    var nonce = 0;
    codec = WebDavSyncCodec(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (_) => nonce++ & 0xff)),
    );
    marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-1',
      createdAt: now,
      memoryKiB: 8,
      iterations: 1,
    );
    root = await codec.openRoot(marker, 'circle-secret');
    states = _MemoryStateRepository();
    local = _FakeLocalAdapter(<String, Object?>{'theme': 'dark'});
    transport = _FakeTransport(marker: marker, serverDate: now);
    sectionCache = WebDavSyncSectionCache();
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) {
        transport.factories++;
        return transport;
      },
      codec: codec,
      sectionCache: sectionCache,
      clock: () => now,
    );
  });

  WebDavSyncCycleContext context({
    bool active = false,
    Map<String, String>? profiles = const <String, String>{
      'profile-circle': 'local-profile',
    },
    Map<String, String>? resources = const <String, String>{},
    OpenedWebDavSyncRoot? rootOverride,
  }) => WebDavSyncCycleContext(
    namespaceId: 'circle:circle-1',
    deviceId: 'device-a',
    markerPin: marker,
    root: rootOverride ?? root,
    circleToLocalProfiles: profiles,
    circleToLocalResources: resources,
    active: active,
  );

  Future<WebDavSyncCycleReport> runFixture(WebDavSyncCycleContext value) =>
      engine.runCycle(value, allowPreActivation: true);

  test('missing root or either identity map is a total no-op', () async {
    final reports = <WebDavSyncCycleReport>[
      await engine.runCycle(null, allowPreActivation: true),
      await runFixture(context(profiles: null)),
      await runFixture(context(resources: null)),
      await runFixture(
        WebDavSyncCycleContext(
          namespaceId: 'circle:circle-1',
          deviceId: 'device-a',
          markerPin: marker,
          root: null,
          circleToLocalProfiles: const <String, String>{
            'profile-circle': 'local-profile',
          },
          circleToLocalResources: const <String, String>{},
          active: true,
        ),
      ),
    ];

    expect(
      reports.map((report) => report.disposition),
      everyElement(WebDavSyncCycleDisposition.inactive),
    );
    expect(states.loads, 0);
    expect(states.updates, 0);
    expect(local.events, isEmpty);
    expect(transport.factories, 0);
    expect(transport.events, isEmpty);
  });

  test(
    'cycle commits sections before manifest and convergence stops writes',
    () async {
      final first = await runFixture(context());

      expect(first.disposition, WebDavSyncCycleDisposition.completed);
      expect(first.sectionsPushed, 2);
      expect(local.applied, hasLength(1));
      final firstManifestWrite = transport.events.indexOf('write:manifest');
      final lastSectionWrite = transport.events.lastIndexWhere(
        (event) => event.startsWith('write:section:'),
      );
      expect(firstManifestWrite, greaterThan(lastSectionWrite));
      expect(
        transport.events.lastIndexOf('read:root'),
        lessThan(firstManifestWrite),
      );
      expect(
        transport.events.where((event) => event == 'read:root'),
        hasLength(2),
      );
      expect(transport.events.last, 'read:manifest:device-a');
      expect(
        transport.allWrittenText,
        everyElement(
          isNot(anyOf(contains('local-profile'), contains('local-resource'))),
        ),
      );

      final writesAfterFirst = transport.writeCount;
      final second = await runFixture(context());

      expect(second.disposition, WebDavSyncCycleDisposition.completed);
      expect(second.sectionsPushed, 0);
      expect(transport.writeCount, writesAfterFirst);
    },
  );

  test(
    'a missing own manifest is repaired without rewriting sections',
    () async {
      await runFixture(context());
      final writesAfterSeed = transport.writeCount;
      transport.manifests.remove('device-a');
      transport.listedWithoutManifest.add('device-a');

      final repaired = await runFixture(context());

      expect(repaired.sectionsPushed, 0);
      expect(transport.writeCount, writesAfterSeed + 1);
      expect(transport.events.last, 'read:manifest:device-a');
      expect(transport.manifests, contains('device-a'));

      final writesAfterRepair = transport.writeCount;
      await runFixture(context());
      expect(transport.writeCount, writesAfterRepair);
    },
  );

  test(
    'a missing own device directory requests a complete seed repair',
    () async {
      await runFixture(context());
      final writesAfterSeed = transport.writeCount;
      transport.manifests.remove('device-a');
      transport.sections.removeWhere((key, _) => key.startsWith('device-a:'));
      transport.events.clear();
      local.events.clear();

      final report = await runFixture(context());

      expect(report.disposition, WebDavSyncCycleDisposition.seedRepairRequired);
      expect(transport.writeCount, 0);
      expect(writesAfterSeed, greaterThan(0));
      expect(local.events, isEmpty);
      expect(transport.events, <String>['read:root', 'list:devices']);
    },
  );

  test(
    'pending apply is replayed before any diff or network after a crash',
    () async {
      local.failNextApply = true;
      await expectLater(runFixture(context()), throwsStateError);
      expect(states.state.profiles['profile-circle']!.pendingApply, isNotNull);

      transport.events.clear();
      local.events.clear();
      await runFixture(context());

      expect(local.events, contains('apply:local-profile'));
      expect(local.replayingPendingFlags, <bool>[false, true, false]);
      expect(
        local.events.indexOf('apply:local-profile'),
        lessThan(local.events.indexOf('read:local-profile')),
      );
      expect(transport.events.first, 'read:root');
      expect(states.state.profiles['profile-circle']!.pendingApply, isNull);
    },
  );

  test(
    'a local mutation conflict never journals a stale pending apply',
    () async {
      local.conflictNextApply = true;

      await expectLater(
        runFixture(context()),
        throwsA(isA<ProfilePreferenceMutationConflict>()),
      );

      expect(states.state.profiles['profile-circle']?.pendingApply, isNull);
      expect(local.applied, isEmpty);
      expect(transport.events, isNot(contains('write:manifest')));
    },
  );

  test('unmapped local tombstones are promoted when maps arrive', () async {
    final key = WebDavSyncRecordKey.finishedMovie('tt-pending');
    states.state = WebDavSyncEngineState(
      pendingLocalProfiles: <String, WebDavSyncProfileEngineState>{
        'local-profile': WebDavSyncProfileEngineState(
          tombstones: <String, WebDavSyncTombstone>{
            key: WebDavSyncTombstone(
              key: key,
              stamp: WebDavSyncStamp(
                normalizedTimeMs: now.millisecondsSinceEpoch,
                originDeviceId: 'device-a',
              ),
              rawLocalTime: true,
            ),
          },
        ),
      },
    );

    await runFixture(context());

    expect(states.state.pendingLocalProfiles, isEmpty);
    expect(states.state.profiles['profile-circle']!.tombstones, contains(key));
  });

  test('GC deletes only old unreferenced own sections', () async {
    final gc = _GcFakeTransport(marker: marker, serverDate: now);
    transport = gc;
    await runFixture(context());
    final referenced = states.state.ownManifest!.sections.first.contentHash;
    final old = now.subtract(const Duration(days: 8)).millisecondsSinceEpoch;
    final young = now.subtract(const Duration(days: 6)).millisecondsSinceEpoch;
    final oldOrphan = 'a' * 64;
    final youngOrphan = 'b' * 64;
    gc.stored = <WebDavSyncStoredSection>[
      WebDavSyncStoredSection(contentHash: referenced, lastModifiedMs: old),
      WebDavSyncStoredSection(contentHash: oldOrphan, lastModifiedMs: old),
      WebDavSyncStoredSection(contentHash: youngOrphan, lastModifiedMs: young),
    ];

    await runFixture(context());

    expect(gc.deleted, <String>[oldOrphan]);
  });

  test('current device IDs exclude absent historical manifests', () async {
    await runFixture(context());
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: _document(),
      tombstones: const WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{},
      ),
    );
    await runFixture(context());
    expect(states.state.currentDeviceIds, <String>{'device-a', 'device-b'});

    transport.manifests.remove('device-b');
    await runFixture(context());

    expect(states.state.currentDeviceIds, <String>{'device-a'});
    expect(states.state.peerManifestHighWater, contains('device-b'));
  });

  test('section cache survives construction of a new cycle engine', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: _document(),
      tombstones: const WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{},
      ),
    );
    await runFixture(context());
    final peerReads = transport.events
        .where((event) => event.startsWith('read:section:device-b:'))
        .length;
    final nextEngine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      sectionCache: sectionCache,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    await nextEngine.runCycle(context(), allowPreActivation: true);

    expect(
      transport.events
          .where((event) => event.startsWith('read:section:device-b:'))
          .length,
      peerReads,
    );
  });

  test(
    'stale hot data is excluded but its tombstones remain eligible',
    () async {
      final key = WebDavSyncRecordKey.finishedMovie('tt1');
      final baseline = _document(
        recordKey: key,
        recordTime: now
            .subtract(const Duration(days: 60))
            .millisecondsSinceEpoch,
        recordValue: true,
      );
      states.state = WebDavSyncEngineState(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{},
        profiles: <String, WebDavSyncProfileEngineState>{
          'profile-circle': WebDavSyncProfileEngineState(baseline: baseline),
        },
      );
      local.preferences = <String, Object?>{
        WebDavSyncHotMerge.finishedMoviesPreference: <String>['tt1'],
      };
      final staleTime = now.subtract(const Duration(days: 31));
      final staleHot = _document(
        scalars: const <String, Object>{'stalePeerOnly': true},
        recordKey: key,
        recordTime: now
            .subtract(const Duration(days: 50))
            .millisecondsSinceEpoch,
        recordValue: true,
      );
      final tombstone = WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{
          key: WebDavSyncTombstone(
            key: key,
            stamp: WebDavSyncStamp(
              normalizedTimeMs: now
                  .subtract(const Duration(days: 40))
                  .millisecondsSinceEpoch,
              originDeviceId: 'device-b',
            ),
            firstPublishedAtMs: now
                .subtract(const Duration(days: 31))
                .millisecondsSinceEpoch,
          ),
        },
      );
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-b',
        manifestTime: staleTime,
        hot: staleHot,
        tombstones: tombstone,
      );

      await runFixture(context());

      final applied = local.applied.last;
      expect(applied[WebDavSyncHotMerge.finishedMoviesPreference], isEmpty);
      expect(applied, isNot(contains('stalePeerOnly')));
    },
  );

  test('pending apply rejects non-finite scalar values', () {
    final target = _document();
    expect(
      () => WebDavSyncPendingApply.fromJson(<String, Object?>{
        'localProfileId': 'local-profile',
        'values': <String, Object>{'bad': double.nan},
        'target': target.toJson(),
      }),
      throwsFormatException,
    );
    expect(
      () => WebDavSyncPendingApply.fromJson(<String, Object?>{
        'localProfileId': 'local-profile',
        'values': <String, Object>{'bad': double.infinity},
        'target': target.toJson(),
      }),
      throwsFormatException,
    );
  });

  test(
    'local WebDAV playlist tombstones publish with circle identity',
    () async {
      const localDedupe = 'webdav|server:local-resource|path:/one';
      const wireDedupe = 'webdav|server:resource-circle|path:/one';
      final localKey = WebDavSyncRecordKey.playlistItem(localDedupe);
      final wireKey = WebDavSyncRecordKey.playlistItem(wireDedupe);
      states.state = WebDavSyncEngineState(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{
          'resource-circle': 'local-resource',
        },
        profiles: <String, WebDavSyncProfileEngineState>{
          'profile-circle': WebDavSyncProfileEngineState(
            tombstones: <String, WebDavSyncTombstone>{
              localKey: WebDavSyncTombstone(
                key: localKey,
                stamp: WebDavSyncStamp(
                  normalizedTimeMs: now.millisecondsSinceEpoch - 1,
                  originDeviceId: 'device-a',
                ),
                rawLocalTime: true,
              ),
            },
          ),
        },
      );

      await runFixture(
        context(
          resources: const <String, String>{
            'resource-circle': 'local-resource',
          },
        ),
      );

      final published = states.state.profiles['profile-circle']!.tombstones;
      expect(published, contains(wireKey));
      expect(published, isNot(contains(localKey)));
      expect(published[wireKey]!.pendingPublication, isFalse);
    },
  );

  test('a locally re-added record cancels its unpublished tombstone', () async {
    final key = WebDavSyncRecordKey.finishedMovie('tt1');
    final baseline = _document(
      recordKey: key,
      recordTime: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      recordValue: true,
    );
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile',
      },
      circleToLocalResources: const <String, String>{},
      profiles: <String, WebDavSyncProfileEngineState>{
        'profile-circle': WebDavSyncProfileEngineState(
          baseline: baseline,
          tombstones: <String, WebDavSyncTombstone>{
            key: WebDavSyncTombstone(
              key: key,
              stamp: WebDavSyncStamp(
                normalizedTimeMs: now.millisecondsSinceEpoch - 1,
                originDeviceId: 'device-a',
              ),
              rawLocalTime: true,
            ),
          },
        ),
      },
    );
    local.preferences = <String, Object?>{
      WebDavSyncHotMerge.finishedMoviesPreference: <String>['tt1'],
    };

    await runFixture(context());

    expect(
      local.applied.last[WebDavSyncHotMerge.finishedMoviesPreference],
      contains('tt1'),
    );
    expect(
      states.state.profiles['profile-circle']!.tombstones,
      isNot(contains(key)),
    );
  });

  test('section cache revalidates the authenticated manifest digest', () async {
    final peerHot = _document(
      scalars: const <String, Object>{'peerSetting': true},
    );
    final peerTombstones = WebDavSyncTombstoneDocument(
      circleProfileId: 'profile-circle',
      items: const <String, WebDavSyncTombstone>{},
    );
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: peerHot,
      tombstones: peerTombstones,
    );
    await runFixture(context());
    final readsBefore = transport.events
        .where((event) => event == 'read:section:device-b:hot/profile-circle')
        .length;

    await transport.rewritePeerHotDigest(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now.add(const Duration(seconds: 1)),
      semanticDigest: '0' * 64,
    );
    await runFixture(context());
    final readsAfter = transport.events
        .where((event) => event == 'read:section:device-b:hot/profile-circle')
        .length;

    expect(readsAfter, readsBefore + 1);
  });

  test('section cache revalidates the manifest publication time', () async {
    final diagnostics = <String>[];
    final cachedEngine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
      diagnostic: (message, _) => diagnostics.add(message),
    );
    final peerHot = _document(
      recordKey: WebDavSyncRecordKey.finishedMovie('tt-cache-time'),
      recordTime: now.millisecondsSinceEpoch,
      recordValue: true,
    );
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: peerHot,
      tombstones: WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: const <String, WebDavSyncTombstone>{},
      ),
    );
    await cachedEngine.runCycle(context(), allowPreActivation: true);
    final readsBefore = transport.events
        .where((event) => event == 'read:section:device-b:hot/profile-circle')
        .length;

    await transport.rewritePeerHotDigest(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now.add(const Duration(seconds: 1)),
      sectionTime: now.subtract(const Duration(seconds: 1)),
      semanticDigest: peerHot.semanticDigest,
    );
    await cachedEngine.runCycle(context(), allowPreActivation: true);

    expect(diagnostics, contains('Ignored an invalid WebDAV sync hot section'));
    expect(
      transport.events
          .where((event) => event == 'read:section:device-b:hot/profile-circle')
          .length,
      readsBefore + 1,
      reason: 'changed authenticated reference metadata must miss the cache',
    );
  });

  test('section cache stays within its entry and byte budgets', () async {
    final padding = 'x' * (256 * 1024);
    for (var index = 0; index < 20; index++) {
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-$index',
        manifestTime: now,
        hot: _document(
          scalars: <String, Object>{'peerSetting': '$index$padding'},
        ),
        tombstones: WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: const <String, WebDavSyncTombstone>{},
        ),
      );
    }

    await runFixture(context());

    expect(engine.debugSectionCacheEntries, lessThanOrEqualTo(32));
    expect(engine.debugSectionCacheBytes, lessThanOrEqualTo(4 * 1024 * 1024));
  });

  test('a peer manifest network failure aborts before any publish', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: _document(),
      tombstones: WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: const <String, WebDavSyncTombstone>{},
      ),
    );
    transport.manifestNetworkFailures.add('device-b');

    await expectLater(runFixture(context()), throwsA(isA<WebDavException>()));

    expect(transport.writeCount, 0);
    expect(local.applied, isEmpty);
  });

  test(
    'a far-future manifest is ignored without poisoning high-water',
    () async {
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-future',
        manifestTime: now.add(const Duration(hours: 2)),
        hot: _document(scalars: const <String, Object>{'futurePeerOnly': true}),
        tombstones: WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: const <String, WebDavSyncTombstone>{},
        ),
      );

      await runFixture(context());

      expect(local.applied.last, isNot(contains('futurePeerOnly')));
      expect(
        states.state.peerManifestHighWater,
        isNot(contains('device-future')),
      );
      expect(
        transport.events,
        isNot(contains('read:section:device-future:hot/profile-circle')),
      );
    },
  );

  test('a peer section network failure aborts before any publish', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: _document(),
      tombstones: WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: const <String, WebDavSyncTombstone>{},
      ),
    );
    transport.sectionNetworkFailures.add('device-b:hot/profile-circle');

    await expectLater(runFixture(context()), throwsA(isA<WebDavException>()));

    expect(transport.writeCount, 0);
    expect(local.applied, isEmpty);
  });

  test('a missing pinned root is a hard sync-root error', () async {
    transport.rootError = const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'root marker missing',
    );

    await expectLater(
      runFixture(context()),
      throwsA(isA<WebDavSyncRootMissingException>()),
    );

    expect(transport.writeCount, 0);
    expect(local.applied, isEmpty);
  });

  test('clock pause telemetry persists and clears after recovery', () async {
    transport.serverDate = null;

    final paused = await runFixture(context());

    expect(paused.disposition, WebDavSyncCycleDisposition.clockPaused);
    expect(
      states.state.lastClockPauseReason,
      WebDavSyncClockPauseReason.missingServerDate,
    );
    expect(states.state.deviceClockWarning, isFalse);

    transport.serverDate = now;
    final recovered = await runFixture(context());

    expect(recovered.disposition, WebDavSyncCycleDisposition.completed);
    expect(states.state.lastClockPauseReason, isNull);
    expect(states.state.deviceClockWarning, isFalse);
  });

  test('Active state refuses to invent a replacement local manifest', () async {
    await expectLater(
      engine.runCycle(context(active: true)),
      throwsA(isA<StateError>()),
    );
    expect(states.updates, 0);
    expect(local.events, isEmpty);
    expect(transport.events, isEmpty);
  });

  test(
    'a corrupt local manifest identity fails before local or network work',
    () async {
      states.state = WebDavSyncEngineState(
        ownManifest: WebDavSyncManifest(
          circleId: 'different-circle',
          deviceId: 'device-a',
          updatedAtMs: now.millisecondsSinceEpoch,
          clockOffsetMs: 0,
          graphSchemaClaim: 1,
          profileMap: const <String, String>{},
          resourceMap: const <String, String>{},
          sections: <WebDavSyncSectionReference>[
            WebDavSyncSectionReference(
              name: 'hot/profile-circle',
              contentHash: '1' * 64,
              semanticDigest: '2' * 64,
              updatedAtMs: now.millisecondsSinceEpoch,
              schemaVersion: 1,
              size: 100,
            ),
          ],
        ),
      );

      await expectLater(runFixture(context()), throwsStateError);

      expect(local.events, isEmpty);
      expect(transport.events, isEmpty);
    },
  );

  test('durable adoption intent blocks all local and network work', () async {
    states.state = WebDavSyncEngineState(
      adoption: WebDavSyncAdoptionRecord(
        adoptionId: 'adoption-1',
        mode: WebDavSyncAdoptionMode.firstJoin,
        phase: WebDavSyncAdoptionPhase.restoring,
        graphSemanticDigest: 'a' * 64,
        preRestoreProfileIds: const <String>{'local-profile'},
        backupPath: 'pre-join-backups/backup.enc',
        backupSha256: 'b' * 64,
        backupVerified: true,
      ),
    );

    final report = await engine.runCycle(context(active: true));

    expect(report.disposition, WebDavSyncCycleDisposition.adoptionBlocked);
    expect(states.loads, 1);
    expect(states.updates, 0);
    expect(local.events, isEmpty);
    expect(transport.factories, 0);
    expect(transport.events, isEmpty);
  });

  test('adoption starting mid-cycle blocks the manifest commit', () async {
    local.afterApply = () {
      states.state = states.state.copyWith(
        adoption: WebDavSyncAdoptionRecord(
          adoptionId: 'adoption-mid-cycle',
          mode: WebDavSyncAdoptionMode.refresh,
          phase: WebDavSyncAdoptionPhase.restoring,
          graphSemanticDigest: 'c' * 64,
          preRestoreProfileIds: const <String>{'local-profile'},
          backupPath: 'pre-join-backups/backup.enc',
          backupSha256: 'd' * 64,
          backupVerified: true,
        ),
      );
    };

    final report = await runFixture(context());

    expect(report.disposition, WebDavSyncCycleDisposition.adoptionBlocked);
    expect(transport.writeCount, 0);
    expect(
      transport.events.where((event) => event.startsWith('ensure:')),
      isEmpty,
    );
  });

  test('profile switch after apply blocks the manifest commit', () async {
    local.afterApply = () => local.sessionValid = false;

    await expectLater(runFixture(context()), throwsStateError);

    expect(transport.writeCount, 0);
    expect(
      transport.events.where((event) => event.startsWith('ensure:')),
      isEmpty,
    );
  });

  test(
    'phone Mi Box tvOS and desktop converge and then stop writing',
    () async {
      const deviceIds = <String>['phone', 'mi-box', 'tvos', 'desktop'];
      final deviceLocals = <String, _FakeLocalAdapter>{};
      final deviceEngines = <String, WebDavSyncEngine>{};
      final contexts = <String, WebDavSyncCycleContext>{};

      for (final deviceId in deviceIds) {
        final state = _MemoryStateRepository();
        final adapter = _FakeLocalAdapter(<String, Object?>{
          'setting_$deviceId': deviceId,
        });
        deviceLocals[deviceId] = adapter;
        deviceEngines[deviceId] = WebDavSyncEngine(
          stateRepository: state,
          localAdapter: adapter,
          transportFactory: (_) => transport,
          codec: codec,
          clock: () => now,
        );
        contexts[deviceId] = WebDavSyncCycleContext(
          namespaceId: 'circle:circle-1',
          deviceId: deviceId,
          markerPin: marker,
          root: root,
          circleToLocalProfiles: <String, String>{
            'profile-circle': 'local-$deviceId',
          },
          circleToLocalResources: const <String, String>{},
        );
      }

      for (var round = 0; round < 5; round++) {
        final order = round.isEven ? deviceIds : deviceIds.reversed;
        for (final deviceId in order) {
          final report = await deviceEngines[deviceId]!.runCycle(
            contexts[deviceId],
            allowPreActivation: true,
          );
          expect(report.disposition, WebDavSyncCycleDisposition.completed);
        }
      }

      for (final adapter in deviceLocals.values) {
        for (final deviceId in deviceIds) {
          expect(adapter.preferences['setting_$deviceId'], deviceId);
        }
      }
      expect(transport.manifests.keys, containsAll(deviceIds));

      final settledWrites = transport.writeCount;
      for (final deviceId in deviceIds) {
        final report = await deviceEngines[deviceId]!.runCycle(
          contexts[deviceId],
          allowPreActivation: true,
        );
        expect(report.sectionsPushed, 0);
      }
      expect(
        transport.writeCount,
        settledWrites,
        reason: 'a converged matrix must not keep rewriting sections/manifests',
      );
    },
  );
}

WebDavSyncHotDocument _document({
  Map<String, Object> scalars = const <String, Object>{},
  String? recordKey,
  int recordTime = 0,
  Object? recordValue,
}) {
  final records = <String, WebDavSyncStampedValue>{
    if (recordKey != null)
      recordKey: WebDavSyncStampedValue(
        stamp: WebDavSyncStamp(
          normalizedTimeMs: recordTime,
          originDeviceId: 'device-b',
        ),
        value: recordValue,
      ),
  };
  final watchPayload = <String, Object?>{
    'records': <String, Object?>{
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    },
    'orders': const <String, Object?>{},
  };
  return WebDavSyncHotDocument(
    circleProfileId: 'profile-circle',
    scalars: WebDavSyncScalarPart(
      stamp: const WebDavSyncStamp(
        normalizedTimeMs: 0,
        originDeviceId: 'device-b',
      ),
      semanticDigest: semanticDigestOf(scalars),
      values: scalars,
    ),
    watchState: WebDavSyncWatchPart(
      stamp: WebDavSyncStamp(
        normalizedTimeMs: recordTime,
        originDeviceId: 'device-b',
      ),
      semanticDigest: semanticDigestOf(watchPayload),
      records: records,
      orders: const <String, WebDavSyncOrderValue>{},
    ),
  );
}

final class _MemoryStateRepository implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineState state = const WebDavSyncEngineState();
  int loads = 0;
  int updates = 0;

  @override
  Future<WebDavSyncEngineState> load(String namespaceId) async {
    loads++;
    return state;
  }

  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  ) async {
    updates++;
    state = update(state);
    return state;
  }
}

final class _FakeLocalAdapter implements WebDavSyncLocalAdapter {
  _FakeLocalAdapter(this.preferences);

  Map<String, Object?> preferences;
  final List<Map<String, Object>> applied = <Map<String, Object>>[];
  final List<String> events = <String>[];
  bool failNextApply = false;
  bool conflictNextApply = false;
  bool sessionValid = true;
  void Function()? afterApply;
  final List<bool> replayingPendingFlags = <bool>[];

  @override
  Future<WebDavSyncLocalSession> beginCycle() async {
    events.add('begin');
    return WebDavSyncLocalSession(
      ProfileScope(profileId: 'active', dataGeneration: 1, sessionEpoch: 1),
      revalidate: () {
        if (!sessionValid) throw StateError('simulated profile switch');
      },
    );
  }

  @override
  Future<WebDavSyncLocalProfileSnapshot> readProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
  ) async {
    events.add('read:$localProfileId');
    return WebDavSyncLocalProfileSnapshot(
      localProfileId: localProfileId,
      rawPreferences: Map<String, Object?>.from(preferences),
      portablePreferences: Map<String, Object?>.from(preferences),
    );
  }

  @override
  Future<void> applyProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
    Map<String, Object> values, {
    ProfilePreferenceMutationToken? expectedMutationToken,
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  }) async {
    events.add('apply:$localProfileId');
    replayingPendingFlags.add(replayingPending);
    if (conflictNextApply) {
      conflictNextApply = false;
      throw const ProfilePreferenceMutationConflict();
    }
    await beforeWrite?.call();
    if (failNextApply) {
      failNextApply = false;
      throw StateError('simulated crash');
    }
    applied.add(Map<String, Object>.from(values));
    preferences = Map<String, Object?>.from(values);
    afterApply?.call();
  }
}

class _FakeTransport implements WebDavSyncTransport {
  _FakeTransport({required this.marker, required this.serverDate});

  final Uint8List marker;
  DateTime? serverDate;
  final Map<String, Uint8List> manifests = <String, Uint8List>{};
  final Map<String, Uint8List> sections = <String, Uint8List>{};
  final List<String> events = <String>[];
  final List<String> writtenText = <String>[];
  final Set<String> manifestNetworkFailures = <String>{};
  final Set<String> sectionNetworkFailures = <String>{};
  final Set<String> listedWithoutManifest = <String>{};
  WebDavException? rootError;
  int factories = 0;

  int get writeCount =>
      events.where((event) => event.startsWith('write:')).length;
  Iterable<String> get allWrittenText => writtenText;

  WebDavResponseMetadata get _metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav'),
    headers: const <String, String>{},
    serverDate: serverDate,
  );

  @override
  Future<WebDavBytesResult> readRootMarker() async {
    events.add('read:root');
    if (rootError case final error?) throw error;
    return WebDavBytesResult(bytes: marker, metadata: _metadata);
  }

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() async {
    events.add('list:devices');
    return WebDavSyncPeerListing(
      deviceIds: <String>{...manifests.keys, ...listedWithoutManifest}.toList()
        ..sort(),
      metadata: _metadata,
    );
  }

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) async {
    events.add('read:manifest:$deviceId');
    if (manifestNetworkFailures.contains(deviceId)) {
      throw const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'peer manifest connection dropped',
      );
    }
    final bytes = manifests[deviceId];
    if (bytes == null) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'peer manifest is missing',
      );
    }
    return WebDavBytesResult(bytes: bytes, metadata: _metadata);
  }

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) async {
    events.add('read:section:$deviceId:${reference.name}');
    if (sectionNetworkFailures.contains('$deviceId:${reference.name}')) {
      throw const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'peer section connection dropped',
      );
    }
    return WebDavBytesResult(
      bytes: sections['$deviceId:${reference.contentHash}']!,
      metadata: _metadata,
    );
  }

  @override
  Future<void> ensureOwnLayout(String deviceId) async {
    events.add('ensure:$deviceId');
  }

  @override
  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  }) async {
    events.add('write:section:$contentHash');
    sections['$deviceId:$contentHash'] = Uint8List.fromList(bytes);
    writtenText.add(String.fromCharCodes(bytes));
    return _metadata;
  }

  @override
  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  ) async {
    events.add('write:manifest');
    manifests[deviceId] = Uint8List.fromList(bytes);
    writtenText.add(String.fromCharCodes(bytes));
    return _metadata;
  }

  Future<void> addPeer({
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required DateTime manifestTime,
    required WebDavSyncHotDocument hot,
    required WebDavSyncTombstoneDocument tombstones,
  }) async {
    Future<WebDavSyncSectionReference> addSection(
      String name,
      Object payload,
      String semanticDigest,
      int maxBytes,
    ) async {
      final bytes = await codec.sealDocument(
        key: root.key,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: name,
        schemaVersion: 1,
        payload: payload,
        maxBytes: maxBytes,
      );
      final hash = contentHashOf(bytes);
      sections['$deviceId:$hash'] = bytes;
      return WebDavSyncSectionReference(
        name: name,
        contentHash: hash,
        semanticDigest: semanticDigest,
        updatedAtMs: manifestTime.millisecondsSinceEpoch,
        schemaVersion: 1,
        size: bytes.length,
      );
    }

    final hotRef = await addSection(
      'hot/profile-circle',
      hot.toJson(),
      hot.semanticDigest,
      WebDavSyncLimits.maxHotDocumentBytes,
    );
    final tombstoneRef = await addSection(
      'tombstones/profile-circle',
      tombstones.toJson(),
      tombstones.semanticDigest,
      WebDavSyncLimits.maxTombstoneDocumentBytes,
    );
    final manifest = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: deviceId,
      updatedAtMs: manifestTime.millisecondsSinceEpoch,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const <String, String>{},
      resourceMap: const <String, String>{},
      sections: <WebDavSyncSectionReference>[hotRef, tombstoneRef],
    );
    manifests[deviceId] = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: 1,
      payload: manifest.toJson(),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
  }

  Future<void> rewritePeerHotDigest({
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required DateTime manifestTime,
    DateTime? sectionTime,
    required String semanticDigest,
  }) async {
    final payload = await codec.openDocument(
      key: root.key,
      encoded: manifests[deviceId]!,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    final current = WebDavSyncManifest.fromJson(payload);
    final sections = <WebDavSyncSectionReference>[
      for (final section in current.sections)
        section.name == 'hot/profile-circle'
            ? WebDavSyncSectionReference(
                name: section.name,
                contentHash: section.contentHash,
                semanticDigest: semanticDigest,
                updatedAtMs:
                    (sectionTime ?? manifestTime).millisecondsSinceEpoch,
                schemaVersion: section.schemaVersion,
                size: section.size,
              )
            : section,
    ];
    final replacement = WebDavSyncManifest(
      circleId: current.circleId,
      deviceId: current.deviceId,
      updatedAtMs: manifestTime.millisecondsSinceEpoch,
      clockOffsetMs: current.clockOffsetMs,
      graphSchemaClaim: current.graphSchemaClaim,
      profileMap: current.profileMap,
      resourceMap: current.resourceMap,
      sections: sections,
    );
    manifests[deviceId] = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      payload: replacement.toJson(),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
  }

  @override
  void close() {}
}

final class _GcFakeTransport extends _FakeTransport
    implements WebDavSyncSectionGcTransport {
  _GcFakeTransport({required super.marker, required super.serverDate});

  List<WebDavSyncStoredSection> stored = const <WebDavSyncStoredSection>[];
  final List<String> deleted = <String>[];

  @override
  Future<List<WebDavSyncStoredSection>> listOwnSections(String deviceId) async {
    events.add('list:sections:$deviceId');
    return List<WebDavSyncStoredSection>.from(stored);
  }

  @override
  Future<void> deleteOwnSection(String deviceId, String contentHash) async {
    events.add('delete:section:$contentHash');
    deleted.add(contentHash);
  }
}
