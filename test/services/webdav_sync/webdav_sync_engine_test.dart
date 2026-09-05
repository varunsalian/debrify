import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_clock.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_diagnostics.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_local_adapter.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
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

  Future<WebDavSyncManifest> openManifest(String deviceId) async {
    final payload = await codec.openDocument(
      key: root.key,
      encoded: transport.manifests[deviceId]!,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    return WebDavSyncManifest.fromJson(payload);
  }

  for (final malformedEnvelope in [true, false]) {
    test(
      'invalid peer reports ${malformedEnvelope ? 'decode' : 'parse'} stage',
      () async {
        final failures = <WebDavSyncManifestFailure>[];
        engine = WebDavSyncEngine(
          stateRepository: states,
          localAdapter: local,
          transportFactory: (_) => transport,
          codec: codec,
          clock: () => now,
          diagnostic: (_, error) {
            if (error is WebDavSyncManifestFailure) failures.add(error);
          },
        );
        transport.manifests['device-b'] = malformedEnvelope
            ? Uint8List.fromList(utf8.encode('invalid envelope'))
            : await codec.sealDocument(
                key: root.key,
                circleId: root.document.circleId,
                deviceId: 'device-b',
                logicalName: 'manifest',
                schemaVersion: WebDavSyncManifest.schemaVersion,
                payload: const {'not': 'a manifest'},
                maxBytes: WebDavSyncLimits.maxManifestBytes,
              );
        final report = await runFixture(context());
        expect(report.disposition, WebDavSyncCycleDisposition.completed);
        expect(failures, hasLength(1));
        expect(
          failures.single.stage,
          malformedEnvelope
              ? WebDavSyncManifestReadStage.decode
              : WebDavSyncManifestReadStage.parse,
        );
        expect(failures.single.category, 'format');
      },
    );
  }

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
      expect(states.state.lastPushMs, now.millisecondsSinceEpoch);
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
      for (var index = 0; index < transport.events.length - 1; index++) {
        if (transport.events[index].startsWith('write:section:')) {
          expect(
            transport.events[index + 1],
            isNot(startsWith('read:section:device-a:')),
          );
        }
      }
      expect(
        transport.events.sublist(firstManifestWrite, firstManifestWrite + 2),
        <String>['write:manifest', 'read:manifest:device-a'],
      );
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
      expect(states.state.lastPushMs, now.millisecondsSinceEpoch);
      expect(transport.writeCount, writesAfterFirst);
    },
  );

  test('hide on A reaches B, and unhide tombstone never resurrects', () async {
    final stamp = WebDavSyncStamp(
      normalizedTimeMs: now.millisecondsSinceEpoch - 10,
      originDeviceId: 'device-a',
    );
    final hiddenKey = 'catalog/hidden/resource-circle/m3u/${'a' * 64}';
    final source = _FakeLibraryLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      document: WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          hiddenKey: WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: stamp,
            value: const <String, Object?>{'group': 'Adult'},
          ),
          'future/family/opaque': WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: stamp,
            value: const <String, Object?>{'opaque': true},
          ),
        },
      ),
    );
    final receiver = _FakeLibraryLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      document: const WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
      ),
    );
    final sourceStates = _MemoryStateRepository();
    final receiverStates = _MemoryStateRepository();
    final sourceEngine = WebDavSyncEngine(
      stateRepository: sourceStates,
      localAdapter: source,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );
    final receiverEngine = WebDavSyncEngine(
      stateRepository: receiverStates,
      localAdapter: receiver,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );
    WebDavSyncCycleContext deviceContext(String device, String localProfile) =>
        WebDavSyncCycleContext(
          namespaceId: 'circle:circle-1',
          deviceId: device,
          markerPin: marker,
          root: root,
          circleToLocalProfiles: <String, String>{
            'profile-circle': localProfile,
          },
          circleToLocalResources: const <String, String>{
            'resource-circle': 'local-resource',
          },
        );

    await sourceEngine.runCycle(
      deviceContext('device-a', 'local-a'),
      allowPreActivation: true,
    );
    final report = await receiverEngine.runCycle(
      deviceContext('device-b', 'local-b'),
      allowPreActivation: true,
    );

    expect(report.disposition, WebDavSyncCycleDisposition.completed);
    expect(receiver.appliedLibraries, hasLength(1));
    final applied = receiver.appliedLibraries.single;
    expect(
      applied.records.values.map((leaf) => leaf.stamp),
      everyElement(
        isA<WebDavSyncStamp>()
            .having(
              (value) => value.normalizedTimeMs,
              'time',
              stamp.normalizedTimeMs,
            )
            .having((value) => value.originDeviceId, 'origin', 'device-a'),
      ),
    );
    expect(applied.records[hiddenKey]!.value!['group'], 'Adult');
    expect(applied.records, contains('future/family/opaque'));
    expect(
      receiverStates.state.ownManifest!.section('library/profile-circle'),
      isNotNull,
    );

    source.document = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        ...source.document.records,
        hiddenKey: WebDavSyncCircleLeaf<Map<String, Object?>>(
          stamp: WebDavSyncStamp(
            normalizedTimeMs: now.millisecondsSinceEpoch,
            originDeviceId: 'device-a',
          ),
          value: null,
        ),
      },
    );
    source.revisions = WebDavSyncDatabaseRevisions(
      debrifyTv: source.revisions.debrifyTv,
      iptvCatalog: source.revisions.iptvCatalog + 1,
    );
    await sourceEngine.runCycle(
      deviceContext('device-a', 'local-a'),
      allowPreActivation: true,
    );
    await receiverEngine.runCycle(
      deviceContext('device-b', 'local-b'),
      allowPreActivation: true,
    );

    expect(receiver.document.records[hiddenKey]!.value, isNull);
    final writesBeforeEcho = transport.writeCount;
    await sourceEngine.runCycle(
      deviceContext('device-a', 'local-a'),
      allowPreActivation: true,
    );
    expect(source.document.records[hiddenKey]!.value, isNull);
    expect(transport.writeCount, writesBeforeEcho);
  });

  test('library revision conflict is benign and next cycle applies', () async {
    final libraryLocal = _FakeLibraryLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      document: WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'future/item': WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: now.millisecondsSinceEpoch,
              originDeviceId: 'device-a',
            ),
            value: const <String, Object?>{'value': 1},
          ),
        },
      ),
    )..conflictNextLibraryApply = true;
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: libraryLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    final first = await runFixture(context());
    expect(first.localChangeFollowUp, isTrue);
    expect(
      states.state.profiles['profile-circle']!.pendingLibraryApply,
      isNull,
    );
    expect(libraryLocal.appliedLibraries, isEmpty);

    final second = await runFixture(context());
    expect(second.disposition, WebDavSyncCycleDisposition.completed);
    expect(libraryLocal.appliedLibraries, hasLength(1));
  });

  test('pending library apply is replayed after a crash', () async {
    final target = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        'future/item': WebDavSyncCircleLeaf<Map<String, Object?>>(
          stamp: WebDavSyncStamp(
            normalizedTimeMs: now.millisecondsSinceEpoch,
            originDeviceId: 'device-a',
          ),
          value: const <String, Object?>{'value': 1},
        ),
      },
    );
    final libraryLocal = _FakeLibraryLocalAdapter(<String, Object?>{
      'theme': 'dark',
    }, document: target)..failNextLibraryApply = true;
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: libraryLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    await expectLater(runFixture(context()), throwsStateError);
    final pending =
        states.state.profiles['profile-circle']!.pendingLibraryApply!;
    expect(pending.target.semanticDigest, target.semanticDigest);
    expect(pending.observedRevisions, libraryLocal.revisions);

    await runFixture(context());

    expect(libraryLocal.libraryReplayFlags, contains(true));
    expect(
      states.state.profiles['profile-circle']!.pendingLibraryApply,
      isNull,
    );
    expect(
      states.state.profiles['profile-circle']!.libraryBaseline!.semanticDigest,
      target.semanticDigest,
    );
  });

  test(
    'a peer manifest without a library section remains compatible',
    () async {
      final libraryLocal = _FakeLibraryLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        document: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
      );
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'old-device',
        manifestTime: now,
        hot: _document(),
        tombstones: const WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{},
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: libraryLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );

      final report = await runFixture(context());

      expect(report.disposition, WebDavSyncCycleDisposition.completed);
      expect(libraryLocal.appliedLibraries, hasLength(1));
      expect(libraryLocal.document.records, isEmpty);
    },
  );

  test('section PUT rejects contradictory response metadata', () async {
    transport.sectionWriteMetadata = WebDavResponseMetadata(
      statusCode: 201,
      uri: Uri.parse('https://example.test/dav'),
      headers: const <String, String>{'etag': '   '},
      etag: '   ',
    );

    await expectLater(runFixture(context()), throwsStateError);

    expect(
      transport.events,
      isNot(contains(startsWith('read:section:device-a:'))),
    );
    expect(transport.events, isNot(contains('write:manifest')));
  });

  for (final status in <int>[403, 405, 409, 412]) {
    test(
      'pre-existing hot sections accept HTTP $status by read-back',
      () async {
        transport.sectionWriteFailure = WebDavException(
          kind: switch (status) {
            403 => WebDavErrorKind.authentication,
            409 => WebDavErrorKind.conflict,
            412 => WebDavErrorKind.preconditionFailed,
            _ => WebDavErrorKind.unexpectedStatus,
          },
          message: 'immutable section already exists',
          statusCode: status,
        );

        final report = await runFixture(context());

        expect(report.disposition, WebDavSyncCycleDisposition.completed);
        expect(report.sectionsPushed, 2);
        expect(
          transport.events,
          contains(startsWith('read:section:device-a:')),
        );
        expect(
          transport.events.sublist(
            transport.events.indexOf('write:manifest'),
            transport.events.indexOf('write:manifest') + 2,
          ),
          <String>['write:manifest', 'read:manifest:device-a'],
        );
      },
    );
  }

  test(
    'immutable hot replay rethrows when the existing hash differs',
    () async {
      transport
        ..sectionWriteFailure = const WebDavException(
          kind: WebDavErrorKind.conflict,
          message: 'immutable section already exists',
          statusCode: 409,
        )
        ..corruptSectionOnWriteFailure = true;

      await expectLater(
        runFixture(context()),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.statusCode,
            'status',
            409,
          ),
        ),
      );

      expect(transport.events, contains(startsWith('read:section:device-a:')));
      expect(transport.events, isNot(contains('write:manifest')));
    },
  );

  test(
    'hot PUT has no GET while profiles and resources PUTs read back',
    () async {
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );

      final report = await runFixture(context());

      expect(report.disposition, WebDavSyncCycleDisposition.completed);
      final manifest = states.state.ownManifest!;
      final hot = manifest.section('hot/profile-circle')!;
      final profiles = manifest.section('profiles')!;
      final resources = manifest.section('resources')!;
      final hotWrite = transport.events.indexOf(
        'write:section:${hot.contentHash}',
      );
      final profilesWrite = transport.events.indexOf(
        'write:section:${profiles.contentHash}',
      );
      final resourcesWrite = transport.events.indexOf(
        'write:section:${resources.contentHash}',
      );
      expect(hotWrite, isNonNegative);
      expect(profilesWrite, isNonNegative);
      expect(resourcesWrite, isNonNegative);
      expect(
        transport.events,
        isNot(contains('read:section:device-a:hot/profile-circle')),
      );
      expect(
        transport.events[profilesWrite + 1],
        'read:section:device-a:profiles',
      );
      expect(
        transport.events[resourcesWrite + 1],
        'read:section:device-a:resources',
      );
    },
  );

  test('corrupt stored resources section is caught during push', () async {
    final circleLocal = _FakeCircleLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Local',
            time: now.millisecondsSinceEpoch,
            origin: 'device-a',
          ),
        },
      ),
    );
    transport.corruptLargeSectionWrites = true;
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: circleLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    await expectLater(runFixture(context()), throwsStateError);

    expect(transport.events, contains('read:section:device-a:resources'));
    expect(transport.events, isNot(contains('write:manifest')));
  });

  test('invalid own hot section is marked dirty and republished', () async {
    await runFixture(context());
    final oldHot = states.state.ownManifest!.section('hot/profile-circle')!;
    transport.sections['device-a:${oldHot.contentHash}']![0] ^= 0xff;
    transport.events.clear();

    final report = await runFixture(context());

    final newHot = states.state.ownManifest!.section('hot/profile-circle')!;
    expect(report.disposition, WebDavSyncCycleDisposition.completed);
    expect(states.hotDigestWasCleared, isTrue);
    expect(newHot.contentHash, isNot(oldHot.contentHash));
    expect(
      transport.events,
      contains('read:section:device-a:hot/profile-circle'),
    );
    expect(transport.events, contains('write:section:${newHot.contentHash}'));
    expect(
      states.state.profiles['profile-circle']!.lastPushedHotDigest,
      newHot.semanticDigest,
    );
  });

  test('remote-change cycle records its successful pull time', () async {
    final report = await engine.runCycle(
      context(),
      allowPreActivation: true,
      trigger: WebDavSyncTrigger.remoteChange,
    );

    expect(report.disposition, WebDavSyncCycleDisposition.completed);
    expect(states.state.lastRemoteChangeMs, now.millisecondsSinceEpoch);
  });

  test('cycle failure descriptions keep shape, never data', () {
    expect(
      describeWebDavSyncCycleFailure(
        const ResourceAuthorizationException('Profile session is locked'),
      ),
      'ResourceAuthorizationException:profile_locked',
    );
    expect(
      describeWebDavSyncCycleFailure(
        const ResourceAuthorizationException(
          'https://user:password@private.invalid/path',
        ),
      ),
      'ResourceAuthorizationException:other',
    );

    expect(
      describeWebDavSyncCycleFailure(
        const WebDavException(
          kind: WebDavErrorKind.transient,
          message: 'unavailable at https://example.test/secret',
          statusCode: 503,
        ),
      ),
      'WebDavException:transient:503',
    );
    expect(
      describeWebDavSyncCycleFailure(
        const WebDavException(
          kind: WebDavErrorKind.network,
          message: 'socket closed',
        ),
      ),
      'WebDavException:network',
    );
    // Our fixed-literal assertions are worth keeping verbatim.
    expect(
      describeWebDavSyncCycleFailure(
        StateError('Active WebDAV sync requires a verified local manifest'),
      ),
      'StateError:Active WebDAV sync requires a verified local manifest',
    );
    expect(
      describeWebDavSyncCycleFailure(
        StateError('WebDAV sync hot/profiles identity map is inconsistent'),
      ),
      'StateError:WebDAV sync hot/profiles identity map is inconsistent',
    );
    // Anything carrying an id, path, digit, or a foreign prefix drops to the
    // bare type.
    expect(
      describeWebDavSyncCycleFailure(
        StateError('WebDAV sync circle-7f3a export omitted an identity'),
      ),
      'StateError',
    );
    expect(
      describeWebDavSyncCycleFailure(
        StateError('profiles failed adoption integrity check'),
      ),
      'StateError',
    );
    expect(
      describeWebDavSyncCycleFailure(
        StateError('WebDAV sync saw https://example.test/private'),
      ),
      'StateError',
    );
    expect(
      describeWebDavSyncCycleFailure(ArgumentError('user@example.test')),
      'ArgumentError',
    );
  });

  test('a failed cycle records only the failure shape', () async {
    final directory = await Directory.systemTemp.createTemp(
      'debrify-webdav-cycle-failure-diagnostics-',
    );
    await DiagnosticLog.instance.initialize(directoryOverride: directory);
    try {
      // The message deliberately carries a URI-shaped secret: none of it may
      // reach the diagnostic store, only the error's kind and status.
      // A failed write is normally read back and accepted when the content
      // hash matches; corrupting the read-back makes the cycle genuinely fail.
      transport
        ..sectionWriteFailure = const WebDavException(
          kind: WebDavErrorKind.transient,
          message: 'upstream unavailable at https://example.test/secret-path',
          statusCode: 503,
        )
        ..corruptSectionOnWriteFailure = true;
      await expectLater(
        engine.runCycle(
          context(),
          allowPreActivation: true,
          trigger: WebDavSyncTrigger.localChange,
        ),
        throwsA(isA<WebDavException>()),
      );

      final exported = await DiagnosticLog.instance.exportLastWindow();
      final events = const LineSplitter()
          .convert(utf8.decode(exported.bytes))
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .where((entry) => entry['event'] == 'cycle')
          .toList(growable: false);
      expect(events, hasLength(1));
      final fields = events.single['fields'] as Map<String, dynamic>;
      expect(fields['disposition'], 'failed');
      expect(fields['failureKind'], 'WebDavException:transient:503');

      final payload = jsonEncode(events.single);
      expect(payload, isNot(contains('secret-path')));
      expect(payload, isNot(contains('upstream unavailable')));
      expect(payload, isNot(contains('example.test')));
    } finally {
      await DiagnosticLog.instance.debugReset();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  test('cycle emits one complete redacted instrumentation event', () async {
    final directory = await Directory.systemTemp.createTemp(
      'debrify-webdav-cycle-diagnostics-',
    );
    await DiagnosticLog.instance.initialize(directoryOverride: directory);
    try {
      final report = await engine.runCycle(
        context(),
        allowPreActivation: true,
        trigger: WebDavSyncTrigger.localChange,
      );
      expect(report.disposition, WebDavSyncCycleDisposition.completed);
      recordWebDavSyncDiagnostic(
        'Ignored a removed WebDAV sync peer',
        ArgumentError('https://example.test/private-path'),
      );
      recordWebDavSyncDiagnostic('Read a legacy WebDAV sync hot section', null);
      recordWebDavSyncLocalChangeTrigger('subtitle_language');

      final exported = await DiagnosticLog.instance.exportLastWindow();
      final allEvents = const LineSplitter()
          .convert(utf8.decode(exported.bytes))
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      final events = allEvents
          .where((entry) => entry['event'] == 'cycle')
          .toList(growable: false);
      expect(events, hasLength(1));
      final fields = events.single['fields'] as Map<String, dynamic>;
      expect(
        fields.keys,
        unorderedEquals(<String>{
          'trigger',
          'peerCount',
          'rootMs',
          'listMs',
          'manifestsMs',
          'sectionsMs',
          'mergeApplyMs',
          'sealMs',
          'pushMs',
          'readBackMs',
          'totalMs',
          'requestCount',
          'bytesUp',
          'bytesDown',
          'sectionsSkipped',
          'bytesSaved',
          'disposition',
        }),
      );
      expect(fields['trigger'], 'localChange');
      expect(fields['disposition'], 'completed');
      expect(fields['requestCount'], greaterThan(0));
      expect(fields['bytesUp'], greaterThan(0));
      expect(fields['bytesDown'], greaterThan(0));
      for (final phase in const <String>[
        'rootMs',
        'listMs',
        'manifestsMs',
        'sectionsMs',
        'mergeApplyMs',
        'sealMs',
        'pushMs',
        'readBackMs',
        'totalMs',
      ]) {
        expect(fields[phase], isA<int>());
        expect(fields[phase] as int, greaterThanOrEqualTo(0));
      }

      final payload = jsonEncode(events.single);
      for (final privateValue in const <String>[
        'example.test',
        '/dav',
        'theme',
        'circle-1',
        'profile-circle',
        'local-profile',
        'device-a',
      ]) {
        expect(payload, isNot(contains(privateValue)));
      }
      expect(payload, isNot(contains('/')));

      final notes = allEvents
          .where((entry) => entry['event'] == 'engine_note')
          .toList(growable: false);
      expect(notes, hasLength(2));
      expect(notes[0]['level'], 'warning');
      expect(notes[0]['fields'], <String, Object?>{
        'message': 'ignored_a_removed_webdav_sync_peer',
      });
      expect(notes[1]['level'], 'info');
      expect(notes[1]['fields'], <String, Object?>{
        'message': 'read_a_legacy_webdav_sync_hot_section',
      });
      expect(jsonEncode(notes), isNot(contains('example.test')));
      expect(jsonEncode(notes), isNot(contains('private-path')));

      final localChangeTriggers = allEvents
          .where((entry) => entry['event'] == 'local_change_trigger')
          .toList(growable: false);
      expect(localChangeTriggers, hasLength(1));
      expect(localChangeTriggers.single['fields'], <String, Object?>{
        'preferenceKey': 'subtitle_language',
      });
    } finally {
      await DiagnosticLog.instance.debugReset();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

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

  test('manifest republish drops a legacy graph reference', () async {
    await runFixture(context());
    final current = states.state.ownManifest!;
    final legacy = WebDavSyncManifest(
      circleId: current.circleId,
      deviceId: current.deviceId,
      updatedAtMs: current.updatedAtMs,
      clockOffsetMs: current.clockOffsetMs,
      graphSchemaClaim: current.graphSchemaClaim,
      profileMap: current.profileMap,
      resourceMap: current.resourceMap,
      sections: <WebDavSyncSectionReference>[
        ...current.sections,
        WebDavSyncSectionReference(
          name: 'graph',
          contentHash: '1' * 64,
          semanticDigest: '2' * 64,
          updatedAtMs: current.updatedAtMs,
          schemaVersion: 1,
          size: 1,
        ),
      ],
    );
    states.state = states.state.copyWith(ownManifest: legacy);
    transport.manifests['device-a'] = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: 'device-a',
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      payload: legacy.toJson(),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    transport.events.clear();

    final report = await runFixture(context());

    expect(report.disposition, WebDavSyncCycleDisposition.completed);
    expect(transport.events, contains('write:manifest'));
    expect(states.state.ownManifest!.section('graph'), isNull);
  });

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
        local.events.indexOf('read:local-profile'),
        lessThan(local.events.indexOf('apply:local-profile')),
      );
      expect(transport.events.first, 'read:root');
      expect(states.state.profiles['profile-circle']!.pendingApply, isNull);
    },
  );

  test(
    'active profile applies before earlier mapped background profiles',
    () async {
      local.activeProfileId = 'local-profile';
      await runFixture(
        context(
          profiles: const {
            'background-circle': 'background-local',
            'profile-circle': 'local-profile',
            'last-circle': 'last-local',
          },
        ),
      );
      expect(
        local.events.where((event) => event.startsWith('apply:')).toList(),
        ['apply:local-profile', 'apply:background-local', 'apply:last-local'],
      );
    },
  );

  for (final uploadFails in [false, true]) {
    test(
      'library refresh precedes uploads and is not repeated (failure=$uploadFails)',
      () async {
        final adapter = _FakeLibraryLocalAdapter(
          <String, Object?>{'theme': 'dark'},
          document: WebDavSyncLibraryDocument(
            circleProfileId: 'profile-circle',
            records: const {},
          ),
        )..activeProfileId = 'local-profile';
        final notifications = <Set<String>>[];
        final writesAtRefresh = <int>[];
        final pendingAtRefresh = <bool>[];
        engine = WebDavSyncEngine(
          stateRepository: states,
          localAdapter: adapter,
          transportFactory: (_) => transport,
          codec: codec,
          clock: () => now,
          appliedKeysCallback: (profileId, keys) {
            notifications.add(keys);
            writesAtRefresh.add(transport.writeCount);
            pendingAtRefresh.add(
              states.state.profiles['profile-circle']!.pendingLibraryApply !=
                  null,
            );
          },
        );
        if (uploadFails) {
          transport.sectionWriteFailure = const WebDavException(
            kind: WebDavErrorKind.authentication,
            message: 'simulated upload rejection',
            statusCode: 401,
          );
          transport.corruptSectionOnWriteFailure = true;
          await expectLater(
            runFixture(context()),
            throwsA(isA<WebDavException>()),
          );
        } else {
          await runFixture(context());
        }
        expect(notifications, hasLength(1));
        expect(notifications.single, contains('catalog/hidden'));
        expect(writesAtRefresh, [0]);
        expect(pendingAtRefresh, [false]);
        expect(adapter.appliedLibraries, hasLength(1));
      },
    );
  }

  test(
    'active profile refresh arrives while another profile is still loading',
    () async {
      local.activeProfileId = 'local-profile';
      final backgroundRead = Completer<void>();
      final releaseBackground = Completer<void>();
      local.beforeProfileRead = () async {
        if (local.events.last == 'read:background-local') {
          backgroundRead.complete();
          await releaseBackground.future;
        }
      };
      final refreshedProfiles = <String>[];
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        appliedKeysCallback: (profileId, _) => refreshedProfiles.add(profileId),
      );
      final cycle = runFixture(
        context(
          profiles: const {
            'background-circle': 'background-local',
            'profile-circle': 'local-profile',
          },
        ),
      );
      try {
        await backgroundRead.future.timeout(const Duration(seconds: 5));
        expect(refreshedProfiles, ['local-profile']);
        expect(transport.writeCount, 0);
      } finally {
        releaseBackground.complete();
        await cycle;
      }
      expect(refreshedProfiles, ['local-profile', 'background-local']);
    },
  );

  test('active-profile apply dispatches mapped UI callbacks once', () async {
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: 'local-profile',
        dataGeneration: 1,
        sessionEpoch: 1,
      ),
    );
    final originalTvHomeStyle = MainPageBridge.tvHomeStyleChanged;
    final originalDiscoverLayout = MainPageBridge.discoverLayoutChanged;
    addTearDown(() {
      MainPageBridge.tvHomeStyleChanged = originalTvHomeStyle;
      MainPageBridge.discoverLayoutChanged = originalDiscoverLayout;
      ProfileRuntime.debugReset();
    });
    var tvHomeCalls = 0;
    var discoverCalls = 0;
    MainPageBridge.tvHomeStyleChanged = () => tvHomeCalls++;
    MainPageBridge.discoverLayoutChanged = () => discoverCalls++;
    local.activeProfileId = 'local-profile';
    local.preferences = <String, Object?>{
      'tv_home_style': 'classic',
      'discover_layout': 'grid',
    };
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      sectionCache: sectionCache,
      clock: () => now,
      appliedKeysCallback: dispatchWebDavSyncAppliedKeysForActiveProfile,
    );

    await runFixture(context());

    expect(tvHomeCalls, 1);
    expect(discoverCalls, 1);
  });

  test('non-active profile apply dispatches no UI callback', () async {
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: 'different-profile',
        dataGeneration: 1,
        sessionEpoch: 1,
      ),
    );
    final originalTvHomeStyle = MainPageBridge.tvHomeStyleChanged;
    addTearDown(() {
      MainPageBridge.tvHomeStyleChanged = originalTvHomeStyle;
      ProfileRuntime.debugReset();
    });
    var tvHomeCalls = 0;
    MainPageBridge.tvHomeStyleChanged = () => tvHomeCalls++;
    local.activeProfileId = 'different-profile';
    local.preferences = <String, Object?>{'tv_home_style': 'classic'};
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      sectionCache: sectionCache,
      clock: () => now,
      appliedKeysCallback: dispatchWebDavSyncAppliedKeysForActiveProfile,
    );

    await runFixture(context());

    expect(tvHomeCalls, 0);
  });

  test('a pure echo with zero applied keys publishes no callback', () async {
    var callbackCalls = 0;
    local.appliedKeysOverride = const <String>{};
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      sectionCache: sectionCache,
      clock: () => now,
      appliedKeysCallback: (_, _) => callbackCalls++,
    );

    await runFixture(context());

    expect(callbackCalls, 0);
  });

  test('pending apply replay dispatches active UI callback once', () async {
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: 'local-profile',
        dataGeneration: 1,
        sessionEpoch: 1,
      ),
    );
    final originalTvHomeStyle = MainPageBridge.tvHomeStyleChanged;
    addTearDown(() {
      MainPageBridge.tvHomeStyleChanged = originalTvHomeStyle;
      ProfileRuntime.debugReset();
    });
    var tvHomeCalls = 0;
    MainPageBridge.tvHomeStyleChanged = () => tvHomeCalls++;
    local.activeProfileId = 'local-profile';
    local.preferences = <String, Object?>{'tv_home_style': 'classic'};
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      sectionCache: sectionCache,
      clock: () => now,
      appliedKeysCallback: dispatchWebDavSyncAppliedKeysForActiveProfile,
    );
    local.failNextApply = true;

    await expectLater(runFixture(context()), throwsStateError);
    expect(tvHomeCalls, 0);
    expect(states.state.profiles['profile-circle']!.pendingApply, isNotNull);

    await runFixture(context());

    expect(local.replayingPendingFlags, <bool>[false, true, false]);
    expect(tvHomeCalls, 1);
    expect(states.state.profiles['profile-circle']!.pendingApply, isNull);
  });

  test(
    'pending replay remerges a newer local write and retries its fence',
    () async {
      local.failNextApply = true;
      await expectLater(runFixture(context()), throwsStateError);
      expect(states.state.profiles['profile-circle']!.pendingApply, isNotNull);

      local.preferences = <String, Object?>{'theme': 'interim'};
      local.conflictNextApply = true;
      final later = now.add(const Duration(seconds: 1));
      transport.serverDate = later;
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: sectionCache,
        clock: () => later,
      );

      await runFixture(context());

      expect(local.replayingPendingFlags, <bool>[false, true, true, false]);
      expect(local.applied.first['theme'], 'interim');
      expect(local.preferences['theme'], 'interim');
      expect(states.state.profiles['profile-circle']!.pendingApply, isNull);
    },
  );

  test(
    'pending replay fence retry reloads an interim deletion tombstone',
    () async {
      final key = WebDavSyncRecordKey.finishedMovie('tt1');
      local.preferences = <String, Object?>{
        WebDavSyncHotMerge.finishedMoviesPreference: <String>['tt1'],
      };
      local.failNextApply = true;
      await expectLater(runFixture(context()), throwsStateError);
      expect(
        states
            .state
            .profiles['profile-circle']!
            .pendingApply!
            .target
            .watchState
            .records,
        contains(key),
      );

      final later = now.add(const Duration(seconds: 1));
      local.conflictNextApply = true;
      local.beforeConflict = () {
        local.preferences = <String, Object?>{
          WebDavSyncHotMerge.finishedMoviesPreference: <String>[],
        };
        final profile = states.state.profiles['profile-circle']!;
        states.state = states.state.copyWith(
          profiles: <String, WebDavSyncProfileEngineState>{
            ...states.state.profiles,
            'profile-circle': profile.copyWith(
              tombstones: <String, WebDavSyncTombstone>{
                key: WebDavSyncTombstone(
                  key: key,
                  stamp: WebDavSyncStamp(
                    normalizedTimeMs: later.millisecondsSinceEpoch,
                    originDeviceId: 'device-a',
                  ),
                  rawLocalTime: true,
                ),
              },
            ),
          },
        );
      };
      transport.serverDate = later;
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: sectionCache,
        clock: () => later,
      );

      await runFixture(context());

      expect(
        local.preferences[WebDavSyncHotMerge.finishedMoviesPreference],
        isEmpty,
      );
      expect(
        states.state.profiles['profile-circle']!.baseline!.watchState.records,
        isNot(contains(key)),
      );
      expect(
        states.state.profiles['profile-circle']!.tombstones,
        contains(key),
      );
    },
  );

  test(
    'circle apply journals exact target and replays before network after crash',
    () async {
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        activeProfileId: 'local-profile',
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
      )..failNextCircleApply = true;
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );

      await expectLater(runFixture(context()), throwsStateError);
      final journaled = states.state.pendingCircleApply;
      expect(journaled, isNotNull);
      final exactTarget = WebDavSyncCodec.canonicalJson(journaled!.toJson());
      expect(transport.events, isNot(contains('write:manifest')));

      transport.events.clear();
      await runFixture(context());

      expect(circleLocal.circleReplayFlags, <bool>[false, true, false]);
      expect(circleLocal.appliedCircleJson[1], exactTarget);
      expect(transport.events.first, 'read:root');
      expect(states.state.pendingCircleApply, isNull);
    },
  );

  test(
    'circle conflict keeps baselines unadvanced and republishes the newer edit',
    () async {
      final diagnostics = <String>[];
      final stale = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Before edit',
            time: now.millisecondsSinceEpoch,
            origin: 'device-a',
          ),
        },
      );
      final newer = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Edited locally',
            time: now.millisecondsSinceEpoch + 1,
            origin: 'device-a',
          ),
        },
      );
      final circleLocal = _FakeCircleLocalAdapter(<String, Object?>{
        'theme': 'dark',
      }, profiles: stale)..conflictNextCircleApply = true;
      circleLocal.beforeCircleApply = (_) {
        circleLocal.profiles = newer;
        circleLocal.beforeCircleApply = null;
      };
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );

      final conflicted = await runFixture(context());

      expect(conflicted.localChangeFollowUp, isTrue);
      expect(states.state.pendingCircleApply, isNull);
      expect(states.state.circleProfilesBaseline, isNull);
      expect(states.state.circleResourcesBaseline, isNull);
      expect(
        diagnostics,
        contains(
          'Deferred WebDAV circle apply after a concurrent local registry '
          'change',
        ),
      );
      expect(
        diagnostics,
        isNot(contains('Quarantined an invalid pending WebDAV circle target')),
      );

      final followedUp = await runFixture(context());

      expect(followedUp.localChangeFollowUp, isFalse);
      expect(followedUp.sectionsPushed, greaterThan(0));
      expect(
        states
            .state
            .circleProfilesBaseline!
            .profiles['profile-circle']!
            .value!
            .name,
        'Edited locally',
      );
      expect(
        circleLocal
            .appliedRequests
            .last
            .profiles
            .profiles['profile-circle']!
            .stamp
            .normalizedTimeMs,
        now.millisecondsSinceEpoch + 1,
      );
    },
  );

  test(
    'circle conflict follow-up publishes a post-snapshot deletion',
    () async {
      final stale = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Delete locally',
            time: now.millisecondsSinceEpoch,
            origin: 'device-a',
          ),
        },
      );
      final tombstone = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: now.millisecondsSinceEpoch + 1,
              originDeviceId: 'device-a',
            ),
            value: null,
          ),
        },
      );
      final circleLocal = _FakeCircleLocalAdapter(<String, Object?>{
        'theme': 'dark',
      }, profiles: stale)..conflictNextCircleApply = true;
      circleLocal.beforeCircleApply = (_) {
        circleLocal.profiles = tombstone;
        circleLocal.beforeCircleApply = null;
      };
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );

      final conflicted = await runFixture(context());

      expect(conflicted.localChangeFollowUp, isTrue);
      expect(states.state.pendingCircleApply, isNull);
      expect(states.state.circleProfilesBaseline, isNull);
      expect(states.state.lastPushedProfilesDigest, isNull);
      expect(states.state.lastPushedResourcesDigest, isNull);
      expect(
        conflicted.sectionsPushed,
        2,
        reason: 'hot sections still publish',
      );
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        containsAll(<String>[
          'hot/profile-circle',
          'tombstones/profile-circle',
        ]),
      );
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        isNot(contains(anyOf('profiles', 'resources'))),
      );

      final followedUp = await runFixture(context());

      expect(followedUp.sectionsPushed, greaterThan(0));
      final published =
          states.state.circleProfilesBaseline!.profiles['profile-circle']!;
      expect(published.value, isNull);
      expect(published.stamp.normalizedTimeMs, now.millisecondsSinceEpoch + 1);
    },
  );

  test(
    'failed outbox drain blocks only circle publication until drained',
    () async {
      final diagnostics = <String>[];
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
      )..outboxDrained = false;
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );

      final failed = await runFixture(context());
      final stillFailed = await runFixture(context());

      expect(failed.disposition, WebDavSyncCycleDisposition.completed);
      expect(failed.localPublicationConfirmed, isFalse);
      expect(failed.statusHint, contains('deletion history'));
      expect(stillFailed.statusHint, contains('deletion history'));
      expect(circleLocal.buildRequests, isEmpty);
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        isNot(anyOf(contains('profiles'), contains('resources'))),
      );
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        contains('hot/profile-circle'),
      );
      expect(
        diagnostics,
        contains(
          'Deferred WebDAV circle publication until the registry tombstone '
          'outbox drains',
        ),
      );

      circleLocal.outboxDrained = true;
      final recovered = await runFixture(context());

      expect(recovered.statusHint, isNull);
      expect(circleLocal.buildRequests, hasLength(1));
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        containsAll(<String>['profiles', 'resources']),
      );
    },
  );

  test(
    'deletion committed after drain cannot publish its stale circle leaf',
    () async {
      final diagnostics = <String>[];
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Stale local profile',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
      );
      var deletionCommitted = false;
      circleLocal.beforeCircleSnapshot = () async {
        if (deletionCommitted) return;
        deletionCommitted = true;
        circleLocal.registryOutboxRowCount = 1;
        circleLocal.outboxDrainError = StateError('simulated drain failure');
        try {
          await circleLocal.drainRegistryTombstoneOutbox();
        } catch (_) {}
      };
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );

      final raced = await runFixture(context());

      expect(raced.disposition, WebDavSyncCycleDisposition.completed);
      expect(raced.statusHint, contains('deletion history'));
      expect(circleLocal.outboxDrainCalls, 2);
      expect(circleLocal.appliedRequests, isEmpty);
      expect(states.state.circleProfilesBaseline, isNull);
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        isNot(contains('profiles')),
      );
      expect(
        diagnostics,
        contains(
          'Deferred WebDAV circle publication because the registry snapshot '
          'has pending tombstones',
        ),
      );

      circleLocal
        ..beforeCircleSnapshot = null
        ..outboxDrainError = null
        ..outboxDrained = true
        ..registryOutboxRowCount = 0
        ..profiles = _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: now.millisecondsSinceEpoch,
                originDeviceId: 'device-a',
              ),
              value: null,
            ),
          },
        );

      final recovered = await runFixture(context());

      expect(recovered.disposition, WebDavSyncCycleDisposition.completed);
      expect(recovered.statusHint, isNot(contains('deletion history')));
      expect(circleLocal.appliedRequests, hasLength(1));
      expect(
        circleLocal
            .appliedRequests
            .single
            .profiles
            .profiles['profile-circle']!
            .value,
        isNull,
      );
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        contains('profiles'),
      );
    },
  );

  test(
    'unavailable mapped profile does not abort remaining hot sync',
    () async {
      final diagnostics = <String>[];
      final twoProfileLocal = _FakeLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        unavailableProfileIds: const <String>{'local-deleted'},
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: twoProfileLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );

      final report = await runFixture(
        context(
          profiles: const <String, String>{
            'deleted-circle': 'local-deleted',
            'profile-circle': 'local-profile',
          },
        ),
      );

      expect(report.disposition, WebDavSyncCycleDisposition.completed);
      expect(report.profilesApplied, 1);
      expect(twoProfileLocal.applied, hasLength(1));
      expect(twoProfileLocal.events, contains('read:local-deleted'));
      expect(twoProfileLocal.events, contains('apply:local-profile'));
      expect(
        diagnostics,
        contains('Skipped an unavailable mapped WebDAV sync profile'),
      );
    },
  );

  test('pending setting accepts its grant from local inventory', () async {
    final diagnostics = <String>[];
    const localGrant = (
      circleProfileId: 'local-profile',
      circleResourceId: 'local-resource',
    );
    final pendingResources = WebDavSyncResourcesDocument(
      resources: const <String, WebDavSyncResourceEntry>{},
      grants:
          const <
            String,
            Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>
          >{},
      settings:
          <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>>{
            'profile-circle':
                <String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>{
                  'resource-circle': WebDavSyncCircleLeaf(
                    stamp: WebDavSyncStamp(
                      normalizedTimeMs: now.millisecondsSinceEpoch,
                      originDeviceId: 'device-b',
                    ),
                    value: const WebDavSyncSettingsValue(
                      enabled: true,
                      settings: <String, Object?>{'mode': 'pending'},
                    ),
                  ),
                },
          },
      bindings:
          const <
            String,
            Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
          >{},
    );
    final circleLocal = _FakeCircleLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Local',
            time: now.millisecondsSinceEpoch,
            origin: 'device-a',
          ),
        },
      ),
      localResourceIds: const <String>{'local-resource'},
      localGrantIds: const <WebDavSyncCircleGrantId>{localGrant},
    );
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile',
      },
      circleToLocalResources: const <String, String>{
        'resource-circle': 'local-resource',
      },
      pendingCircleApply: WebDavSyncPendingCircleApply(
        profiles: _circleProfiles(const {}),
        resources: pendingResources,
      ),
    );
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: circleLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
      diagnostic: (message, _) => diagnostics.add(message),
    );

    await runFixture(
      context(
        resources: const <String, String>{'resource-circle': 'local-resource'},
      ),
    );

    expect(
      diagnostics,
      isNot(contains('Quarantined an invalid pending WebDAV circle target')),
    );
    expect(circleLocal.circleReplayFlags.first, isTrue);
    expect(
      circleLocal
          .appliedRequests
          .first
          .resources
          .settings['profile-circle']!['resource-circle']!
          .value,
      isNotNull,
    );
    expect(states.state.pendingCircleApply, isNull);
  });

  test(
    'pending child of a tombstoned parent is suppressed from local apply',
    () async {
      final diagnostics = <String>[];
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
      );
      final poisonedResources = WebDavSyncResourcesDocument(
        resources: <String, WebDavSyncResourceEntry>{
          'r-poison': WebDavSyncResourceEntry(
            metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: now.millisecondsSinceEpoch,
                originDeviceId: 'device-a',
              ),
              value: null,
            ),
          ),
        },
        grants:
            <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{
              'profile-circle':
                  <String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>{
                    'r-poison': WebDavSyncCircleLeaf<WebDavSyncGrantValue>(
                      stamp: WebDavSyncStamp(
                        normalizedTimeMs: now.millisecondsSinceEpoch + 1,
                        originDeviceId: 'device-b',
                      ),
                      value: const WebDavSyncGrantValue(permissions: 1),
                    ),
                  },
            },
        settings: const {},
        bindings: const {},
      );
      states.state = WebDavSyncEngineState(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{
          'r-poison': 'local-poison',
        },
        pendingCircleApply: WebDavSyncPendingCircleApply(
          profiles: circleLocal.profiles,
          resources: poisonedResources,
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );

      await runFixture(
        context(resources: const <String, String>{'r-poison': 'local-poison'}),
      );

      expect(
        diagnostics,
        isNot(contains('Quarantined an invalid pending WebDAV circle target')),
      );
      expect(circleLocal.circleReplayFlags.first, isTrue);
      expect(
        circleLocal.appliedRequests.first.resources.grants['profile-circle'],
        isNull,
      );
      expect(states.state.pendingCircleApply, isNull);
      expect(transport.events, contains('read:root'));
    },
  );

  test('persisted zero-admin target defers its local managing Admin', () async {
    final diagnostics = <String>[];
    final circleLocal = _FakeCircleLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Local',
            time: now.millisecondsSinceEpoch,
            origin: 'device-a',
          ),
        },
      ),
      honorProfileSuppression: true,
    );
    final zeroAdmin =
        _circleProfiles(<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Demoted',
            time: now.millisecondsSinceEpoch,
            origin: 'device-b',
            role: UserProfileRole.member,
          ),
        });
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile',
      },
      circleToLocalResources: const <String, String>{},
      pendingCircleApply: WebDavSyncPendingCircleApply(
        profiles: zeroAdmin,
        resources: _circleResources(const <String, WebDavSyncResourceEntry>{}),
      ),
    );
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: circleLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
      diagnostic: (message, _) => diagnostics.add(message),
    );

    final safetyReport = await runFixture(context());
    expect(safetyReport.localPublicationConfirmed, isTrue);
    expect(safetyReport.localProfilesSuppressed, isTrue);

    expect(
      diagnostics,
      contains('Deferred a WebDAV sync admin change for local safety'),
    );
    expect(diagnostics.join('\n'), isNot(contains('Local')));
    expect(states.state.statusHint, 'sync kept Local as Admin on this device');
    expect(
      diagnostics,
      isNot(contains('Quarantined an invalid pending WebDAV circle target')),
    );
    expect(circleLocal.circleReplayFlags.first, isTrue);
    expect(
      circleLocal.appliedRequests.first.deferredAdminCircleProfileId,
      'profile-circle',
    );
    expect(states.state.pendingCircleApply, isNull);
    expect(states.state.pendingAdminSafetyProfile, 'local-profile');
    expect(transport.events, contains('read:root'));
  });

  test('foreign circle maps are durable before registry apply', () async {
    final circleLocal = _FakeCircleLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Local',
            time: now.millisecondsSinceEpoch - 1,
            origin: 'device-a',
          ),
        },
      ),
    );
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
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'foreign-profile': _circleProfileLeaf(
            name: 'Foreign',
            time: now.millisecondsSinceEpoch,
            origin: 'device-b',
          ),
        },
      ),
    );
    circleLocal.beforeCircleApply = (request) {
      final localId =
          request.identityMaps.circleToLocalProfiles['foreign-profile'];
      expect(localId, isNotNull);
      expect(
        states.state.circleToLocalProfiles?['foreign-profile'],
        localId,
        reason: 'the mapping must commit before registry apply begins',
      );
    };
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: circleLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    await runFixture(context());

    expect(states.state.circleToLocalProfiles, contains('foreign-profile'));
    expect(
      circleLocal.appliedRequests.single.profiles.profiles,
      contains('foreign-profile'),
    );
  });

  test(
    'a partial circle read defers an orphan locally but republishes it live',
    () async {
      final diagnostics = <String>[];
      final stamp = WebDavSyncStamp(
        normalizedTimeMs: now.millisecondsSinceEpoch,
        originDeviceId: 'device-b',
      );
      final orphan = _circleResources(<String, WebDavSyncResourceEntry>{
        'resource-orphan': WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: stamp,
            value: const WebDavSyncResourceMetadata(
              type: ConnectionResourceType.realDebrid,
              label: 'Shared RD',
              ownerCircleProfileId: 'profile-missing-this-cycle',
              publicConfig: <String, Object?>{'schemaVersion': 1},
              publicSchemaVersion: 1,
              enabled: true,
            ),
          ),
          secretConfig: WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
            stamp: stamp,
            value: WebDavSyncResourceSecretConfig(
              semanticDigest: 'a' * 64,
              type: ConnectionResourceType.realDebrid,
              ownerCircleProfileId: 'profile-missing-this-cycle',
              publicSchemaVersion: 1,
              payloadVersion: 1,
              envelope: base64Encode(const <int>[1]),
            ),
          ),
        ),
      });
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
      );
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
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-missing-this-cycle': _circleProfileLeaf(
              name: 'Remote owner',
              time: now.millisecondsSinceEpoch,
              origin: 'device-b',
            ),
          },
        ),
        resources: orphan,
      );
      transport.sectionNotFoundFailures.add('device-b:profiles');
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );

      await runFixture(context());

      expect(
        circleLocal.appliedRequests.single.resources.resources,
        isNot(contains('resource-orphan')),
      );
      final published = states.state.circleResourcesBaseline!;
      expect(published.resources['resource-orphan']!.metadata.value, isNotNull);
      expect(
        published.resources['resource-orphan']!.secretConfig!.value,
        isNotNull,
      );
      expect(
        WebDavSyncCodec.canonicalJson(published.toJson()),
        isNot(contains('"value":null')),
      );
      expect(
        states.state.ownManifest!.section('resources')!.semanticDigest,
        published.semanticDigest,
      );
      expect(
        diagnostics,
        contains(
          'Deferred a WebDAV circle resource whose owner profile was absent '
          'from this cycle',
        ),
      );
      final peerMerge = WebDavSyncCircleMerge.mergeResources(
        <WebDavSyncResourcesDocument>[orphan, published],
      );
      expect(peerMerge.resources['resource-orphan']!.metadata.value, isNotNull);
      expect(
        peerMerge.resources['resource-orphan']!.secretConfig!.value,
        isNotNull,
      );
    },
  );

  test(
    'heartbeat-stale admin deletion stays on wire and defers local apply',
    () async {
      final staleTime = now.subtract(const Duration(days: 31));
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        activeProfileId: 'local-profile',
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: staleTime.millisecondsSinceEpoch - 1,
              origin: 'device-a',
            ),
          },
        ),
      );
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-b',
        manifestTime: staleTime,
        hot: _document(),
        tombstones: const WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{},
        ),
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: staleTime.millisecondsSinceEpoch,
                originDeviceId: 'device-b',
              ),
              value: null,
            ),
          },
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );

      await runFixture(context());

      expect(
        circleLocal
            .appliedRequests
            .single
            .profiles
            .profiles['profile-circle']!
            .value,
        isNull,
      );
      expect(transport.events, contains('read:section:device-b:profiles'));
      expect(states.state.pendingActiveProfileDeletion, 'local-profile');
      expect(
        states.state.pendingActiveProfile?.reason,
        WebDavSyncPendingActiveProfileReason.deleted,
      );
      expect(states.state.pendingAdminSafetyProfile, 'local-profile');
      expect(suppressWebDavSyncActiveProfileRetirement(states.state), isTrue);
      expect(
        states.state.statusHint,
        'sync kept active Local because it is this device\'s only managing '
        'Admin',
      );
      expect(
        circleLocal.appliedRequests.single.deferredActiveCircleProfileId,
        'profile-circle',
      );
      expect(
        circleLocal.appliedRequests.single.deferredAdminCircleProfileId,
        'profile-circle',
      );
    },
  );

  test(
    'promotion conflict retains Admin safety until follow-up commits',
    () async {
      final localProfiles = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'active-admin': _circleProfileLeaf(
            name: 'Active Admin',
            time: now.millisecondsSinceEpoch - 2,
            origin: 'device-a',
          ),
          'member': _circleProfileLeaf(
            name: 'Member',
            time: now.millisecondsSinceEpoch - 2,
            origin: 'device-a',
            role: UserProfileRole.member,
          ),
        },
      );
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        activeProfileId: 'local-active',
        localProfileIds: const <String>{'local-active', 'local-member'},
        managingAdminLocalProfileIds: const <String>{'local-active'},
        localProfileNames: const <String, String>{
          'local-active': 'Active Admin',
          'local-member': 'Member',
        },
        honorProfileSuppression: true,
        profiles: localProfiles,
      );
      final deletion = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
        stamp: WebDavSyncStamp(
          normalizedTimeMs: now.millisecondsSinceEpoch,
          originDeviceId: 'device-b',
        ),
        value: null,
      );
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
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'active-admin': deletion,
          },
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      final mappedContext = context(
        profiles: const <String, String>{
          'active-admin': 'local-active',
          'member': 'local-member',
        },
      );

      await runFixture(mappedContext);

      expect(states.state.pendingActiveProfileDeletion, 'local-active');
      expect(states.state.pendingAdminSafetyProfile, 'local-active');
      expect(suppressWebDavSyncActiveProfileRetirement(states.state), isTrue);
      expect(circleLocal.localProfileIds, contains('local-active'));
      expect(circleLocal.activeProfileId, 'local-active');

      final later = now.add(const Duration(minutes: 1));
      transport.serverDate = later;
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-b',
        manifestTime: later,
        hot: _document(),
        tombstones: const WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{},
        ),
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'active-admin': deletion,
            'member': _circleProfileLeaf(
              name: 'Promoted',
              time: later.millisecondsSinceEpoch,
              origin: 'device-b',
            ),
          },
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => later,
      );
      circleLocal.conflictNextCircleApply = true;

      final conflicted = await engine.runCycle(
        mappedContext,
        allowPreActivation: true,
      );

      expect(conflicted.localChangeFollowUp, isTrue);
      expect(states.state.pendingAdminSafetyProfile, 'local-active');
      expect(suppressWebDavSyncActiveProfileRetirement(states.state), isTrue);

      await engine.runCycle(mappedContext, allowPreActivation: true);

      expect(states.state.pendingActiveProfileDeletion, 'local-active');
      expect(states.state.pendingAdminSafetyProfile, isNull);
      expect(suppressWebDavSyncActiveProfileRetirement(states.state), isFalse);
      expect(
        circleLocal.appliedRequests.last.deferredAdminCircleProfileId,
        isNull,
      );
    },
  );

  test(
    'stored disabled marker clears when remote re-enables after switch',
    () async {
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        activeProfileId: 'local-x',
        localProfileIds: const <String>{'local-x', 'local-y'},
        managingAdminLocalProfileIds: const <String>{'local-x', 'local-y'},
        localProfileNames: const <String, String>{
          'local-x': 'X',
          'local-y': 'Y',
        },
        honorProfileSuppression: true,
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'x-admin': _circleProfileLeaf(
              name: 'X',
              time: now.millisecondsSinceEpoch - 2,
              origin: 'device-a',
            ),
            'y-admin': _circleProfileLeaf(
              name: 'Y',
              time: now.millisecondsSinceEpoch - 2,
              origin: 'device-a',
            ),
          },
        ),
      );
      final disabled = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'x-admin': _circleProfileLeaf(
            name: 'X',
            time: now.millisecondsSinceEpoch,
            origin: 'device-b',
            enabled: false,
          ),
        },
      );
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
        profiles: disabled,
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      final twoProfileContext = context(
        profiles: const <String, String>{
          'x-admin': 'local-x',
          'y-admin': 'local-y',
        },
      );

      await runFixture(twoProfileContext);
      final converged = await runFixture(twoProfileContext);

      expect(circleLocal.activeProfileId, 'local-x');
      expect(
        states.state.pendingActiveProfile?.reason,
        WebDavSyncPendingActiveProfileReason.disabled,
      );
      expect(
        circleLocal.appliedRequests.first.deferredActiveCircleProfileId,
        'x-admin',
      );
      expect(
        circleLocal.buildRequests[1].suppressedLocalProfileIds,
        contains('local-x'),
      );
      expect(converged.sectionsPushed, 0);
      expect(converged.localProfilesSuppressed, isTrue);

      final later = now.add(const Duration(minutes: 1));
      circleLocal.activeProfileId = 'local-y';
      transport.serverDate = later;
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-b',
        manifestTime: later,
        hot: _document(),
        tombstones: const WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{},
        ),
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'x-admin': _circleProfileLeaf(
              name: 'X',
              time: later.millisecondsSinceEpoch,
              origin: 'device-b',
            ),
          },
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => later,
      );

      await engine.runCycle(twoProfileContext, allowPreActivation: true);

      expect(states.state.pendingActiveProfile, isNull);
      expect(circleLocal.activeProfileId, 'local-y');
      expect(
        circleLocal
            .appliedRequests
            .last
            .profiles
            .profiles['x-admin']!
            .value!
            .enabled,
        isTrue,
      );
      expect(
        circleLocal.appliedRequests.last.deferredActiveCircleProfileId,
        isNull,
      );
      final convergedAfterSwitch = await engine.runCycle(
        twoProfileContext,
        allowPreActivation: true,
      );
      expect(states.state.pendingActiveProfile, isNull);
      expect(convergedAfterSwitch.sectionsPushed, 0);
      expect(convergedAfterSwitch.localProfilesSuppressed, isFalse);
    },
  );

  test(
    'admin deferral suppresses republication and clears on remote promotion',
    () async {
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        activeProfileId: 'local-x',
        localProfileIds: const <String>{'local-x', 'local-y'},
        managingAdminLocalProfileIds: const <String>{'local-x', 'local-y'},
        localProfileNames: const <String, String>{
          'local-x': 'X',
          'local-y': 'Y',
        },
        honorProfileSuppression: true,
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'x-admin': _circleProfileLeaf(
              name: 'X',
              time: now.millisecondsSinceEpoch - 2,
              origin: 'device-a',
            ),
            'y-admin': _circleProfileLeaf(
              name: 'Y',
              time: now.millisecondsSinceEpoch - 2,
              origin: 'device-a',
            ),
          },
        ),
      );
      final demotions = _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'x-admin': _circleProfileLeaf(
            name: 'X',
            time: now.millisecondsSinceEpoch - 1,
            origin: 'device-b',
            role: UserProfileRole.member,
          ),
          'y-admin': _circleProfileLeaf(
            name: 'Y',
            time: now.millisecondsSinceEpoch - 1,
            origin: 'device-b',
            role: UserProfileRole.member,
          ),
        },
      );
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
        profiles: demotions,
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      final twoProfileContext = context(
        profiles: const <String, String>{
          'x-admin': 'local-x',
          'y-admin': 'local-y',
        },
      );

      await runFixture(twoProfileContext);
      final converged = await runFixture(twoProfileContext);

      expect(states.state.pendingAdminSafetyProfile, 'local-y');
      expect(states.state.statusHint, 'sync kept Y as Admin on this device');
      expect(
        circleLocal.appliedRequests.first.deferredAdminCircleProfileId,
        'y-admin',
      );
      expect(
        circleLocal.buildRequests[1].suppressedLocalProfileIds,
        contains('local-y'),
      );
      expect(converged.sectionsPushed, 0);

      final later = now.add(const Duration(minutes: 1));
      transport.serverDate = later;
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-b',
        manifestTime: later,
        hot: _document(),
        tombstones: const WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{},
        ),
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'x-admin': demotions.profiles['x-admin']!,
            'y-admin': _circleProfileLeaf(
              name: 'Y',
              time: later.millisecondsSinceEpoch,
              origin: 'device-b',
            ),
          },
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => later,
      );

      await engine.runCycle(twoProfileContext, allowPreActivation: true);

      expect(states.state.pendingAdminSafetyProfile, isNull);
      expect(states.state.statusHint, isNull);
      expect(
        circleLocal.appliedRequests.last.deferredAdminCircleProfileId,
        isNull,
      );
      expect(
        circleLocal
            .appliedRequests
            .last
            .profiles
            .profiles['y-admin']!
            .value!
            .role,
        UserProfileRole.admin,
      );
    },
  );

  test(
    'two-device circle merge publishes one reference and a later owner secret',
    () async {
      final stamp = WebDavSyncStamp(
        normalizedTimeMs: now.millisecondsSinceEpoch,
        originDeviceId: 'device-b',
      );
      final metadata = WebDavSyncResourceMetadata(
        type: ConnectionResourceType.realDebrid,
        label: 'Shared RD',
        ownerCircleProfileId: 'profile-circle',
        publicConfig: const <String, Object?>{'schemaVersion': 1},
        publicSchemaVersion: 1,
        enabled: true,
      );
      final metadataOnly = _circleResources(<String, WebDavSyncResourceEntry>{
        'resource-circle': WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: stamp,
            value: metadata,
          ),
        ),
      });
      final circleLocal = _FakeCircleLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        profiles: _circleProfiles(
          <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
            'profile-circle': _circleProfileLeaf(
              name: 'Local',
              time: now.millisecondsSinceEpoch,
              origin: 'device-a',
            ),
          },
        ),
        resources: metadataOnly,
        localResourceIds: const <String>{'local-resource'},
      );
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
        resources: metadataOnly,
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: circleLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      final mappedContext = context(
        resources: const <String, String>{'resource-circle': 'local-resource'},
      );

      await runFixture(mappedContext);
      expect(
        circleLocal
            .appliedRequests
            .single
            .resources
            .resources['resource-circle']!
            .secretConfig,
        isNull,
      );

      circleLocal.resources = _circleResources(
        <String, WebDavSyncResourceEntry>{
          'resource-circle': WebDavSyncResourceEntry(
            metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
              stamp: stamp,
              value: metadata,
            ),
            secretConfig: WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: now.millisecondsSinceEpoch,
                originDeviceId: 'device-a',
              ),
              value: WebDavSyncResourceSecretConfig(
                semanticDigest: 'a' * 64,
                type: ConnectionResourceType.realDebrid,
                ownerCircleProfileId: 'profile-circle',
                publicSchemaVersion: 1,
                payloadVersion: 1,
                envelope: base64Encode(const <int>[1]),
              ),
            ),
          ),
        },
      );
      await runFixture(mappedContext);

      expect(
        circleLocal
            .appliedRequests
            .last
            .resources
            .resources['resource-circle']!
            .secretConfig!
            .value,
        isNotNull,
      );
      final manifest = states.state.ownManifest!;
      expect(
        manifest.sections.where((section) => section.name == 'profiles'),
        hasLength(1),
      );
      expect(
        manifest.sections.where((section) => section.name == 'resources'),
        hasLength(1),
      );
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
    expect(states.state.peerManifestValidators['device-b'], isNotNull);

    transport.manifests.remove('device-b');
    await runFixture(context());

    expect(states.state.currentDeviceIds, <String>{'device-a'});
    expect(states.state.peerManifestHighWater, contains('device-b'));
  });

  test(
    'four-peer concurrent reads match sequential merged output and writes',
    () async {
      final source = _FakeTransport(marker: marker, serverDate: now);
      for (var index = 0; index < 4; index++) {
        await source.addPeer(
          codec: codec,
          root: root,
          deviceId: 'device-peer-$index',
          manifestTime: now,
          hot: _document(scalars: <String, Object>{'peer_$index': index}),
          tombstones: const WebDavSyncTombstoneDocument(
            circleProfileId: 'profile-circle',
            items: <String, WebDavSyncTombstone>{},
          ),
        );
      }

      _FakeTransport cloneTransport() {
        final clone = _FakeTransport(marker: marker, serverDate: now)
          ..readDelay = const Duration(milliseconds: 1);
        clone.manifests.addAll(<String, Uint8List>{
          for (final entry in source.manifests.entries)
            entry.key: Uint8List.fromList(entry.value),
        });
        clone.sections.addAll(<String, Uint8List>{
          for (final entry in source.sections.entries)
            entry.key: Uint8List.fromList(entry.value),
        });
        return clone;
      }

      WebDavSyncCodec deterministicCodec() {
        var nonce = 0;
        return WebDavSyncCodec(
          randomBytes: (length) => Uint8List.fromList(
            List<int>.generate(length, (_) => nonce++ & 0xff),
          ),
        );
      }

      Future<
        ({
          _MemoryStateRepository state,
          _FakeLocalAdapter local,
          _FakeTransport transport,
          WebDavSyncCycleReport report,
        })
      >
      runWithConcurrency(int concurrency) async {
        final state = _MemoryStateRepository();
        final local = _FakeLocalAdapter(<String, Object?>{'theme': 'dark'});
        final transport = cloneTransport();
        final comparisonEngine = WebDavSyncEngine(
          stateRepository: state,
          localAdapter: local,
          transportFactory: (_) => transport,
          codec: deterministicCodec(),
          clock: () => now,
          readConcurrency: concurrency,
        );
        final report = await comparisonEngine.runCycle(
          context(),
          allowPreActivation: true,
        );
        return (
          state: state,
          local: local,
          transport: transport,
          report: report,
        );
      }

      final sequential = await runWithConcurrency(1);
      final concurrent = await runWithConcurrency(4);

      expect(concurrent.report.disposition, sequential.report.disposition);
      expect(concurrent.local.preferences, sequential.local.preferences);
      expect(
        concurrent.state.state.ownManifest!.toJson(),
        sequential.state.state.ownManifest!.toJson(),
      );
      expect(
        concurrent.transport.manifests['device-a'],
        orderedEquals(sequential.transport.manifests['device-a']!),
      );
      expect(concurrent.transport.maxConcurrentReads, inInclusiveRange(2, 4));
      expect(sequential.transport.maxConcurrentReads, 1);
    },
  );

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
    'unchanged peer references skip reads with an identical merged outcome',
    () async {
      final peerLibrary = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'future/library/record': WebDavSyncCircleLeaf(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: now.millisecondsSinceEpoch,
              originDeviceId: 'device-b',
            ),
            value: const <String, Object?>{'value': 'peer'},
          ),
        },
      );
      local = _FakeLibraryLocalAdapter(
        <String, Object?>{'theme': 'dark'},
        document: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: WebDavSyncSectionCache(),
        clock: () => now,
      );
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'device-b',
        manifestTime: now,
        hot: _document(scalars: const <String, Object>{'peerSetting': true}),
        tombstones: const WebDavSyncTombstoneDocument(
          circleProfileId: 'profile-circle',
          items: <String, WebDavSyncTombstone>{},
        ),
        library: peerLibrary,
      );

      await runFixture(context());
      final readsAfterFirst = transport.events
          .where((event) => event.startsWith('read:section:device-b:'))
          .length;
      expect(
        states.state.lastMergedPeerSections['device-b']!.keys,
        containsAll(<String>[
          'hot/profile-circle',
          'tombstones/profile-circle',
          'library/profile-circle',
        ]),
      );

      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: WebDavSyncSectionCache(),
        clock: () => now,
      );
      await runFixture(context());
      final skippedOutcome = WebDavSyncCodec.canonicalJson(
        states.state.profiles['profile-circle']!.baseline!.toJson(),
      );
      final skippedLibraryOutcome = WebDavSyncCodec.canonicalJson(
        states.state.profiles['profile-circle']!.libraryBaseline!.toJson(),
      );
      expect(
        transport.events
            .where((event) => event.startsWith('read:section:device-b:'))
            .length,
        readsAfterFirst,
      );

      states.state = states.state.copyWith(
        lastMergedPeerSections:
            const <String, Map<String, WebDavSyncSectionReference>>{},
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: WebDavSyncSectionCache(),
        clock: () => now,
      );
      await runFixture(context());
      final alwaysReadOutcome = WebDavSyncCodec.canonicalJson(
        states.state.profiles['profile-circle']!.baseline!.toJson(),
      );
      final alwaysReadLibraryOutcome = WebDavSyncCodec.canonicalJson(
        states.state.profiles['profile-circle']!.libraryBaseline!.toJson(),
      );

      expect(
        transport.events
            .where((event) => event.startsWith('read:section:device-b:'))
            .length,
        readsAfterFirst + 3,
      );
      expect(skippedOutcome, alwaysReadOutcome);
      expect(skippedLibraryOutcome, alwaysReadLibraryOutcome);
    },
  );

  test('a changed peer section reference is read and committed', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: _document(scalars: const <String, Object>{'peerSetting': 'before'}),
      tombstones: const WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{},
      ),
    );
    await runFixture(context());
    final oldReference =
        states.state.lastMergedPeerSections['device-b']!['hot/profile-circle']!;
    final readsBefore = transport.events
        .where((event) => event == 'read:section:device-b:hot/profile-circle')
        .length;

    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'device-b',
      manifestTime: now,
      hot: _document(scalars: const <String, Object>{'peerSetting': 'after'}),
      tombstones: const WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{},
      ),
    );
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      sectionCache: WebDavSyncSectionCache(),
      clock: () => now,
    );

    await runFixture(context());

    final newReference =
        states.state.lastMergedPeerSections['device-b']!['hot/profile-circle']!;
    expect(
      transport.events
          .where((event) => event == 'read:section:device-b:hot/profile-circle')
          .length,
      readsBefore + 1,
    );
    expect(newReference.contentHash, isNot(oldReference.contentHash));
    expect(local.preferences['peerSetting'], 'after');
  });

  test('a failed cycle does not advance peer section references', () async {
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
    local.failNextApply = true;

    await expectLater(runFixture(context()), throwsStateError);

    expect(states.state.lastMergedPeerSections, isEmpty);
  });

  test('a conflicted cycle does not advance peer section references', () async {
    final circleLocal = _FakeCircleLocalAdapter(
      <String, Object?>{'theme': 'dark'},
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Local',
            time: now.millisecondsSinceEpoch,
            origin: 'device-a',
          ),
        },
      ),
    )..conflictNextCircleApply = true;
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
      profiles: _circleProfiles(
        <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
          'profile-circle': _circleProfileLeaf(
            name: 'Peer',
            time: now.millisecondsSinceEpoch,
            origin: 'device-b',
          ),
        },
      ),
    );
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: circleLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    final report = await runFixture(context());

    expect(report.localChangeFollowUp, isTrue);
    // The veto is per tier: the conflicted circle tier must not advance its
    // profiles/resources references, while the peer's hot/tombstone tier
    // applied cleanly and advances — a perpetual circle follow-up must not
    // doom every peer section to be re-downloaded forever.
    final deviceSections = states.state.lastMergedPeerSections['device-b'];
    expect(deviceSections, isNotNull);
    expect(deviceSections!.keys, isNot(contains('profiles')));
    expect(deviceSections.keys, isNot(contains('resources')));
    expect(deviceSections.keys, contains('hot/profile-circle'));
  });

  test('compression migration republishes once only while active', () async {
    await runFixture(context());
    final legacyReferences = <String, String>{
      for (final section in states.state.ownManifest!.sections)
        section.name: section.contentHash,
    };
    expect(states.state.sealedCompressionMigrated, isFalse);
    transport.events.clear();

    local.failNextApply = true;
    await expectLater(engine.runCycle(context(active: true)), throwsStateError);
    expect(states.state.sealedCompressionMigrated, isFalse);
    transport.events.clear();

    final migrated = await engine.runCycle(context(active: true));
    final migratedReferences = <String, String>{
      for (final section in states.state.ownManifest!.sections)
        section.name: section.contentHash,
    };

    expect(migrated.sectionsPushed, 2);
    expect(states.state.sealedCompressionMigrated, isTrue);
    expect(
      migratedReferences['hot/profile-circle'],
      isNot(legacyReferences['hot/profile-circle']),
    );
    expect(
      migratedReferences['tombstones/profile-circle'],
      isNot(legacyReferences['tombstones/profile-circle']),
    );

    transport.events.clear();
    final settled = await engine.runCycle(context(active: true));

    expect(settled.sectionsPushed, 0);
    expect(
      transport.events.where((event) => event.startsWith('write:section:')),
      isEmpty,
    );
    expect(states.state.sealedCompressionMigrated, isTrue);
  });

  test('a profile without a baseline reads every peer section', () async {
    const emptyLibrary = WebDavSyncLibraryDocument(
      circleProfileId: 'profile-circle',
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
    );
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
      library: emptyLibrary,
    );
    final peerManifest = await openManifest('device-b');
    states.state = WebDavSyncEngineState(
      profiles: const <String, WebDavSyncProfileEngineState>{
        'profile-circle': WebDavSyncProfileEngineState(
          libraryBaseline: emptyLibrary,
        ),
      },
      lastMergedPeerSections: <String, Map<String, WebDavSyncSectionReference>>{
        'device-b': <String, WebDavSyncSectionReference>{
          for (final section in peerManifest.sections) section.name: section,
        },
      },
    );
    local = _FakeLibraryLocalAdapter(<String, Object?>{
      'theme': 'dark',
    }, document: emptyLibrary);
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );

    await runFixture(context());

    expect(
      transport.events
          .where((event) => event.startsWith('read:section:device-b:'))
          .toList(),
      containsAll(<String>[
        'read:section:device-b:hot/profile-circle',
        'read:section:device-b:tombstones/profile-circle',
        'read:section:device-b:library/profile-circle',
      ]),
    );
  });

  test('read cursors and compression migration state round-trip durably', () {
    final reference = WebDavSyncSectionReference(
      name: 'library/profile-circle',
      contentHash: 'a' * 64,
      semanticDigest: 'b' * 64,
      updatedAtMs: now.millisecondsSinceEpoch,
      schemaVersion: WebDavSyncLibraryDocument.schemaVersion,
      size: 123,
    );
    final restored = WebDavSyncEngineState.fromJson(
      WebDavSyncEngineState(
        lastMergedPeerSections:
            <String, Map<String, WebDavSyncSectionReference>>{
              'device-b': <String, WebDavSyncSectionReference>{
                reference.name: reference,
              },
            },
        sealedCompressionMigrated: true,
      ).toJson(),
    );

    expect(
      restored.lastMergedPeerSections['device-b']![reference.name]!.contentHash,
      reference.contentHash,
    );
    expect(restored.sealedCompressionMigrated, isTrue);
  });

  test('hot manifest gate reads v1 and silently skips v3', () async {
    final diagnostics = <String>[];
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      sectionCache: sectionCache,
      clock: () => now,
      diagnostic: (message, _) => diagnostics.add(message),
    );
    final legacyPayload = _legacyHotJson(
      device: 'legacy-device',
      scalarTime: now.millisecondsSinceEpoch - 1,
      scalars: const <String, Object>{'legacyPeerOnly': true},
    );
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'legacy-device',
      manifestTime: now,
      hot: _document(),
      hotSchemaVersion: 1,
      hotPayload: legacyPayload,
      tombstones: const WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{},
      ),
    );
    final v3Payload = Map<String, Object?>.from(
      _document(
        scalars: const <String, Object>{'newerPeerOnly': true},
      ).toJson(),
    )..['version'] = 3;
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'newer-device',
      manifestTime: now,
      hot: _document(),
      hotSchemaVersion: 3,
      hotPayload: v3Payload,
      tombstones: const WebDavSyncTombstoneDocument(
        circleProfileId: 'profile-circle',
        items: <String, WebDavSyncTombstone>{},
      ),
    );

    await runFixture(context());

    expect(local.applied.last['legacyPeerOnly'], isTrue);
    expect(local.applied.last, isNot(contains('newerPeerOnly')));
    expect(
      transport.events,
      contains('read:section:legacy-device:hot/profile-circle'),
    );
    expect(
      transport.events,
      isNot(contains('read:section:newer-device:hot/profile-circle')),
    );
    expect(diagnostics, <String>['Read a legacy WebDAV sync hot section']);
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

  test(
    'root pin mismatch discards the concurrent listing before manifest reads',
    () async {
      final changedMarker = Uint8List.fromList(marker)..[0] ^= 0xff;
      transport = _FakeTransport(marker: changedMarker, serverDate: now);
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: sectionCache,
        clock: () => now,
      );

      await expectLater(
        runFixture(context()),
        throwsA(isA<WebDavSyncRootChangedException>()),
      );

      expect(transport.events, <String>['read:root', 'list:devices']);
      expect(transport.events, isNot(contains(startsWith('read:manifest:'))));
      expect(transport.writeCount, 0);
    },
  );

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

  test(
    'cutover strips stale TV records from the next main publication',
    () async {
      final diagnostics = <String>[];
      final ambient = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'future/ambient': const WebDavSyncCircleLeaf(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 1,
              originDeviceId: 'device-a',
            ),
            value: <String, Object?>{'value': 'kept'},
          ),
        },
      );
      local = _FakeLibraryLocalAdapter(<String, Object?>{}, document: ambient);
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: sectionCache,
        clock: () => now,
        diagnostic: (message, _) => diagnostics.add(message),
      );
      final stalePeer = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          ...ambient.records,
          'tv/ch/bGVnYWN5': const WebDavSyncCircleLeaf(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 2,
              originDeviceId: 'device-b',
            ),
            value: <String, Object?>{'name': 'legacy'},
          ),
        },
      );
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
        library: stalePeer,
      );

      await runFixture(context());

      final manifest = await openManifest('device-a');
      final reference = manifest.section('library/profile-circle')!;
      final payload = await codec.openDocument(
        key: root.key,
        encoded: transport.sections['device-a:${reference.contentHash}']!,
        circleId: root.document.circleId,
        deviceId: 'device-a',
        logicalName: reference.name,
        schemaVersion: reference.schemaVersion,
        payloadDecoder: decodeWebDavSyncLibraryDocument,
        maxBytes: WebDavSyncLibraryDocument.maxEncodedBytes,
      );
      final published = payload as WebDavSyncLibraryDocument;
      expect(published.records, contains('future/ambient'));
      expect(published.records.keys, everyElement(isNot(startsWith('tv/'))));
      expect(
        diagnostics.where(
          (message) =>
              message ==
              'Ignored Debrify TV records in an ambient library section',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'TV data moves only when the foreground manual operation runs',
    () async {
      final tvLocal = _FakeTvLibraryLocalAdapter(
        <String, Object?>{},
        document: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
        tvDocument: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
      );
      local = tvLocal;
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: tvLocal,
        transportFactory: (_) => transport,
        codec: codec,
        sectionCache: sectionCache,
        clock: () => now,
      );
      await runFixture(context());
      final remote = _tvLibraryDocument(
        name: 'Remote channel',
        time: now.millisecondsSinceEpoch - 2,
        infohash: 'a' * 40,
      );
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
        tvLibrary: remote,
      );

      await engine.runCycle(context(active: true));
      expect(tvLocal.tvDocument.records, isEmpty);
      expect(
        transport.events,
        isNot(contains('read:section:device-b:tv-library/profile-circle')),
      );

      final first = await engine.runTvSync(
        context(active: true),
        cancellationToken: WebDavSyncTvCancellationToken(),
      );
      expect(first.disposition, WebDavSyncTvManualDisposition.completed);
      expect(tvLocal.tvDocument.semanticDigest, remote.semanticDigest);
      expect(
        (await openManifest('device-a')).section('tv-library/profile-circle'),
        isNotNull,
      );

      transport.events.clear();
      final unchanged = await engine.runTvSync(
        context(active: true),
        cancellationToken: WebDavSyncTvCancellationToken(),
      );
      expect(unchanged.disposition, WebDavSyncTvManualDisposition.completed);
      expect(
        transport.events,
        isNot(contains('read:section:device-b:tv-library/profile-circle')),
        reason: 'the merged peer reference is skipped on the next manual run',
      );

      final updated = _tvLibraryDocument(
        name: 'Updated remote channel',
        time: now.millisecondsSinceEpoch - 1,
        infohash: 'b' * 40,
      );
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
        tvLibrary: updated,
      );
      await engine.runCycle(context(active: true));
      expect(tvLocal.tvDocument.semanticDigest, remote.semanticDigest);
      final second = await engine.runTvSync(
        context(active: true),
        cancellationToken: WebDavSyncTvCancellationToken(),
      );
      expect(second.disposition, WebDavSyncTvManualDisposition.completed);
      expect(tvLocal.tvDocument.semanticDigest, updated.semanticDigest);
    },
  );

  test(
    'manual TV sync imports an old peer main library without consuming it',
    () async {
      final tvLocal = _FakeTvLibraryLocalAdapter(
        <String, Object?>{},
        document: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
        tvDocument: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
      );
      local = tvLocal;
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: tvLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      await runFixture(context());
      final oldPeerTv = _tvLibraryDocument(
        name: 'Old-app channel',
        time: now.millisecondsSinceEpoch - 1,
        infohash: 'd' * 40,
      );
      final mixedOldPeer = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          ...oldPeerTv.records,
          'future/ambient': WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: now.millisecondsSinceEpoch - 1,
              originDeviceId: 'device-b',
            ),
            value: const <String, Object?>{'kept': true},
          ),
        },
      );
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
        library: mixedOldPeer,
      );

      final manual = await engine.runTvSync(
        context(active: true),
        cancellationToken: WebDavSyncTvCancellationToken(),
      );

      expect(manual.disposition, WebDavSyncTvManualDisposition.completed);
      expect(tvLocal.tvDocument.semanticDigest, oldPeerTv.semanticDigest);
      expect(
        states.state.lastMergedPeerSections['device-b'],
        isNot(contains('library/profile-circle')),
      );

      await engine.runCycle(context(active: true));
      expect(tvLocal.document.records, contains('future/ambient'));
      expect(
        tvLocal.document.records.keys,
        everyElement(isNot(startsWith('tv/'))),
      );
      expect(
        states.state.lastMergedPeerSections['device-b'],
        contains('library/profile-circle'),
        reason: 'the ambient cycle tracks its own main-library reference',
      );
    },
  );

  test('manual TV cancellation after apply is resumable', () async {
    final tvLocal = _FakeTvLibraryLocalAdapter(
      <String, Object?>{},
      document: const WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
      ),
      tvDocument: const WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
      ),
    );
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: tvLocal,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
    );
    await runFixture(context());
    final remote = _tvLibraryDocument(
      name: 'Remote channel',
      time: now.millisecondsSinceEpoch - 1,
      infohash: 'c' * 40,
    );
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
      tvLibrary: remote,
    );
    final token = WebDavSyncTvCancellationToken();

    final cancelled = await engine.runTvSync(
      context(active: true),
      cancellationToken: token,
      onStage: (stage) {
        if (stage == WebDavSyncTvManualStage.applying) token.cancel();
      },
    );

    expect(cancelled.disposition, WebDavSyncTvManualDisposition.cancelled);
    expect(tvLocal.tvDocument.semanticDigest, remote.semanticDigest);
    expect(
      (await openManifest('device-a')).section('tv-library/profile-circle'),
      isNull,
    );
    expect(tvLocal.completedTvSyncs, 0);
    final resumed = await engine.runTvSync(
      context(active: true),
      cancellationToken: WebDavSyncTvCancellationToken(),
    );
    expect(resumed.disposition, WebDavSyncTvManualDisposition.completed);
    expect(tvLocal.completedTvSyncs, 1);
  });

  test(
    'manual TV sync refuses inactive, first-join, and running cycles',
    () async {
      final tvLocal = _FakeTvLibraryLocalAdapter(
        <String, Object?>{},
        document: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
        tvDocument: const WebDavSyncLibraryDocument(
          circleProfileId: 'profile-circle',
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{},
        ),
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: tvLocal,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      expect(
        (await engine.runTvSync(
          context(),
          cancellationToken: WebDavSyncTvCancellationToken(),
        )).disposition,
        WebDavSyncTvManualDisposition.inactive,
      );
      expect(
        (await engine.runTvSync(
          context(active: true),
          cancellationToken: WebDavSyncTvCancellationToken(),
        )).disposition,
        WebDavSyncTvManualDisposition.firstJoinPending,
      );
      await runFixture(context());
      final entered = Completer<void>();
      final release = Completer<void>();
      tvLocal.beforeProfileRead = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final ambientCycle = engine.runCycle(context(active: true));
      await entered.future;
      final refused = await engine.runTvSync(
        context(active: true),
        cancellationToken: WebDavSyncTvCancellationToken(),
      );
      expect(refused.disposition, WebDavSyncTvManualDisposition.cycleRunning);
      release.complete();
      await ambientCycle;
    },
  );

  test(
    'cleared activity recovers capacity without resurrecting offline history',
    () async {
      final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        for (var i = 0; i <= WebDavSyncLibraryDocument.maxAmbientLeaves; i++)
          'resume/resource-circle/item-$i': const WebDavSyncCircleLeaf(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 1,
              originDeviceId: 'device-a',
            ),
            value: <String, Object?>{'positionMs': 1000},
          ),
      };
      final old = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: records,
      );
      final adapter = _FakeLibraryLocalAdapter(
        <String, Object?>{},
        document: old,
      );
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: adapter,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      expect(
        (await runFixture(context())).disposition,
        WebDavSyncCycleDisposition.capacityBlocked,
      );
      final cleared = WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: {
          for (final key in records.keys)
            key: const WebDavSyncCircleLeaf<Map<String, Object?>>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: 2,
                originDeviceId: 'device-a',
              ),
              value: null,
            ),
        },
      );
      local = _FakeLibraryLocalAdapter(<String, Object?>{}, document: cleared);
      engine = WebDavSyncEngine(
        stateRepository: states,
        localAdapter: local,
        transportFactory: (_) => transport,
        codec: codec,
        clock: () => now,
      );
      expect(
        (await runFixture(context())).disposition,
        WebDavSyncCycleDisposition.completed,
      );
      final published =
          states.state.profiles['profile-circle']!.libraryBaseline!;
      expect(published.records, hasLength(records.length));
      final reunited = WebDavSyncLibraryMerge.merge(
        circleProfileId: 'profile-circle',
        documents: [published, old],
      );
      expect(
        reunited.records.values.every((leaf) => leaf.value == null),
        isTrue,
      );
      expect(states.state.statusHint, isNull);
    },
  );

  test('ambient library persists an actionable 20k capacity block', () async {
    final diagnostics = <String>[];
    final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
      for (
        var index = 0;
        index <= WebDavSyncLibraryDocument.maxAmbientLeaves;
        index++
      )
        'future/$index': WebDavSyncCircleLeaf(
          stamp: const WebDavSyncStamp(
            normalizedTimeMs: 1,
            originDeviceId: 'device-a',
          ),
          value: <String, Object?>{'index': index},
        ),
    };
    local = _FakeLibraryLocalAdapter(
      <String, Object?>{},
      document: WebDavSyncLibraryDocument(
        circleProfileId: 'profile-circle',
        records: records,
      ),
    );
    engine = WebDavSyncEngine(
      stateRepository: states,
      localAdapter: local,
      transportFactory: (_) => transport,
      codec: codec,
      clock: () => now,
      diagnostic: (message, _) => diagnostics.add(message),
    );

    final report = await runFixture(context());

    expect(report.disposition, WebDavSyncCycleDisposition.capacityBlocked);
    expect(report.statusHint, contains('Remove older history or lists'));
    expect(states.state.statusHint, report.statusHint);
    expect(
      diagnostics,
      contains('Refused WebDAV ambient library build above 20,000 records'),
    );
    expect(transport.events, isNot(contains('write:manifest')));
  });
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
      semanticDigest: semanticDigestOf(scalars),
      entries: <String, WebDavSyncStampedValue>{
        for (final entry in scalars.entries)
          entry.key: WebDavSyncStampedValue(
            stamp: const WebDavSyncStamp(
              normalizedTimeMs: 0,
              originDeviceId: 'device-b',
            ),
            value: entry.value,
          ),
      },
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

WebDavSyncLibraryDocument _tvLibraryDocument({
  required String name,
  required int time,
  required String infohash,
}) {
  const channel = 'Y2hhbm5lbA';
  final generation = 'generation-${infohash.substring(0, 1)}';
  WebDavSyncCircleLeaf<Map<String, Object?>> leaf(Map<String, Object?> value) =>
      WebDavSyncCircleLeaf<Map<String, Object?>>(
        stamp: WebDavSyncStamp(
          normalizedTimeMs: time,
          originDeviceId: 'device-b',
        ),
        value: value,
      );
  return WebDavSyncLibraryDocument(
    circleProfileId: 'profile-circle',
    records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
      'tv/ch/$channel': leaf(<String, Object?>{
        'name': name,
        'avoidNsfw': true,
        'channelNumber': 1,
        'createdAt': 1,
        'keywords': <String>['channel'],
      }),
      'tv/pool-gen/$channel': leaf(<String, Object?>{
        'generationId': generation,
      }),
      'tv/pool/$channel/$infohash': leaf(<String, Object?>{
        'generationId': generation,
        'name': name,
        'sizeBytes': 1,
        'keywords': <String>['channel'],
        'rank': 0,
      }),
    },
  );
}

Map<String, Object?> _legacyHotJson({
  required String device,
  required int scalarTime,
  required Map<String, Object> scalars,
}) {
  final emptyWatch = _document().watchState;
  return <String, Object?>{
    'version': 1,
    'circleProfileId': 'profile-circle',
    'scalars': <String, Object?>{
      'stamp': WebDavSyncStamp(
        normalizedTimeMs: scalarTime,
        originDeviceId: device,
      ).toJson(),
      'semanticDigest': semanticDigestOf(scalars),
      'values': scalars,
    },
    'watchState': emptyWatch.toJson(),
  };
}

WebDavSyncProfilesDocument _circleProfiles(
  Map<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>> profiles,
) => WebDavSyncProfilesDocument(profiles: profiles);

WebDavSyncResourcesDocument _circleResources(
  Map<String, WebDavSyncResourceEntry> resources,
) => WebDavSyncResourcesDocument(
  resources: resources,
  grants:
      const <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{},
  settings:
      const <
        String,
        Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
      >{},
  bindings:
      const <
        String,
        Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
      >{},
);

WebDavSyncCircleLeaf<WebDavSyncProfileValue> _circleProfileLeaf({
  required String name,
  required int time,
  required String origin,
  UserProfileRole role = UserProfileRole.admin,
  bool enabled = true,
}) => WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
  stamp: WebDavSyncStamp(normalizedTimeMs: time, originDeviceId: origin),
  value: WebDavSyncProfileValue(
    name: name,
    role: role,
    policy: Map<String, Object?>.from(
      jsonDecode(ProfilePolicy.allAllowedFor(role).encode()) as Map,
    ),
    enabled: enabled,
    lockOnResume: false,
    setupComplete: true,
    lifecycle: UserProfileLifecycle.active,
    pin: const WebDavSyncProfilePin(resetRequired: false),
  ),
);

final class _MemoryStateRepository implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineState state = const WebDavSyncEngineState();
  int loads = 0;
  int updates = 0;
  bool hotDigestWasCleared = false;

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
    final previous = state;
    state = update(state);
    for (final entry in previous.profiles.entries) {
      if (entry.value.lastPushedHotDigest != null &&
          state.profiles[entry.key]?.lastPushedHotDigest == null) {
        hotDigestWasCleared = true;
      }
    }
    return state;
  }
}

class _FakeLocalAdapter implements WebDavSyncLocalAdapter {
  _FakeLocalAdapter(
    this.preferences, {
    this.activeProfileId = 'active',
    this.unavailableProfileIds = const <String>{},
  });

  Map<String, Object?> preferences;
  String activeProfileId;
  final Set<String> unavailableProfileIds;
  final List<Map<String, Object>> applied = <Map<String, Object>>[];
  final List<String> events = <String>[];
  bool failNextApply = false;
  bool conflictNextApply = false;
  void Function()? beforeConflict;
  bool sessionValid = true;
  void Function()? afterApply;
  Future<void> Function()? beforeProfileRead;
  Set<String>? appliedKeysOverride;
  final List<bool> replayingPendingFlags = <bool>[];

  @override
  Future<WebDavSyncLocalSession> beginCycle() async {
    events.add('begin');
    return WebDavSyncLocalSession(
      ProfileScope(
        profileId: activeProfileId,
        dataGeneration: 1,
        sessionEpoch: 1,
      ),
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
    await beforeProfileRead?.call();
    if (unavailableProfileIds.contains(localProfileId)) {
      throw WebDavSyncMappedProfileUnavailable();
    }
    return WebDavSyncLocalProfileSnapshot(
      localProfileId: localProfileId,
      rawPreferences: Map<String, Object?>.from(preferences),
      portablePreferences: Map<String, Object?>.from(preferences),
    );
  }

  @override
  Future<Set<String>> applyProfile(
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
      beforeConflict?.call();
      beforeConflict = null;
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
    return appliedKeysOverride ?? Set<String>.unmodifiable(values.keys);
  }
}

final class _FakeLibraryLocalAdapter extends _FakeLocalAdapter
    implements WebDavSyncLibraryLocalAdapter {
  _FakeLibraryLocalAdapter(super.preferences, {required this.document});

  WebDavSyncLibraryDocument document;
  WebDavSyncDatabaseRevisions revisions = const WebDavSyncDatabaseRevisions(
    debrifyTv: 0,
    iptvCatalog: 0,
  );
  bool conflictNextLibraryApply = false;
  bool failNextLibraryApply = false;
  final List<WebDavSyncLibraryDocument> appliedLibraries =
      <WebDavSyncLibraryDocument>[];
  final List<bool> libraryReplayFlags = <bool>[];

  @override
  Future<WebDavSyncLocalLibrarySnapshot> readLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryBuildRequest request,
  ) async => WebDavSyncLocalLibrarySnapshot(
    document: document,
    revisions: revisions,
    hiddenGroupNamesByWireKey: <String, String>{
      for (final entry in document.records.entries)
        if (entry.value.value?['group'] is String)
          entry.key: entry.value.value!['group']! as String,
    },
  );

  @override
  Future<WebDavSyncLibraryApplyOutcome> applyLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryApplyRequest request, {
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  }) async {
    libraryReplayFlags.add(replayingPending);
    await beforeWrite?.call();
    if (failNextLibraryApply) {
      failNextLibraryApply = false;
      throw StateError('simulated library apply crash');
    }
    if (conflictNextLibraryApply) {
      conflictNextLibraryApply = false;
      revisions = WebDavSyncDatabaseRevisions(
        debrifyTv: revisions.debrifyTv,
        iptvCatalog: revisions.iptvCatalog + 1,
      );
      return const WebDavSyncLibraryApplyOutcome(
        result: WebDavSyncLibraryApplyResult.conflict,
      );
    }
    appliedLibraries.add(request.document);
    document = request.document;
    revisions = WebDavSyncDatabaseRevisions(
      debrifyTv: revisions.debrifyTv,
      iptvCatalog: revisions.iptvCatalog + 1,
    );
    return const WebDavSyncLibraryApplyOutcome(
      result: WebDavSyncLibraryApplyResult.applied,
      appliedNamespaces: <String>{'catalog/hidden'},
    );
  }
}

final class _FakeTvLibraryLocalAdapter extends _FakeLibraryLocalAdapter
    implements WebDavSyncTvLibraryLocalAdapter {
  _FakeTvLibraryLocalAdapter(
    super.preferences, {
    required super.document,
    required this.tvDocument,
    String activeProfileId = 'local-profile',
  }) {
    this.activeProfileId = activeProfileId;
  }

  WebDavSyncLibraryDocument tvDocument;
  int tvRevision = 0;
  int tvPendingRevision = 1;
  int completedTvSyncs = 0;
  final List<WebDavSyncLibraryDocument> appliedTvLibraries =
      <WebDavSyncLibraryDocument>[];

  @override
  Future<WebDavSyncLocalLibrarySnapshot> readTvLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryBuildRequest request,
  ) async => WebDavSyncLocalLibrarySnapshot(
    document: tvDocument,
    revisions: WebDavSyncDatabaseRevisions(
      debrifyTv: tvRevision,
      iptvCatalog: 0,
    ),
    tvPendingRevision: tvPendingRevision,
  );

  @override
  Future<WebDavSyncLibraryApplyOutcome> applyTvLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryApplyRequest request,
  ) async {
    appliedTvLibraries.add(request.document);
    tvDocument = request.document;
    tvRevision++;
    return const WebDavSyncLibraryApplyOutcome(
      result: WebDavSyncLibraryApplyResult.applied,
      appliedNamespaces: <String>{'tv/ch', 'tv/pool'},
    );
  }

  @override
  Future<void> completeTvLibrarySync(
    WebDavSyncLocalSession session,
    String localProfileId, {
    required int expectedPendingRevision,
    required int syncedAtMs,
  }) async {
    expect(expectedPendingRevision, tvPendingRevision);
    completedTvSyncs++;
  }
}

final class _FakeCircleLocalAdapter extends _FakeLocalAdapter
    implements
        WebDavSyncCircleLocalAdapter,
        WebDavSyncRegistryTombstoneOutboxDrainer {
  _FakeCircleLocalAdapter(
    super.preferences, {
    super.activeProfileId,
    required this.profiles,
    this.localProfileIds = const <String>{'local-profile'},
    this.localResourceIds = const <String>{},
    this.localGrantIds = const <WebDavSyncCircleGrantId>{},
    this.managingAdminLocalProfileIds = const <String>{'local-profile'},
    this.localProfileNames = const <String, String>{'local-profile': 'Local'},
    this.honorProfileSuppression = false,
    this.resources = const WebDavSyncResourcesDocument(
      resources: <String, WebDavSyncResourceEntry>{},
      grants:
          <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{},
      settings:
          <
            String,
            Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
          >{},
      bindings:
          <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>>{},
    ),
  });

  WebDavSyncProfilesDocument profiles;
  WebDavSyncResourcesDocument resources;
  final Set<String> localProfileIds;
  final Set<String> localResourceIds;
  final Set<WebDavSyncCircleGrantId> localGrantIds;
  final Set<String> managingAdminLocalProfileIds;
  final Map<String, String> localProfileNames;
  final bool honorProfileSuppression;
  bool outboxDrained = true;
  Object? outboxDrainError;
  int outboxDrainCalls = 0;
  int registryOutboxRowCount = 0;
  Future<void> Function()? beforeCircleSnapshot;
  bool failNextCircleApply = false;
  bool conflictNextCircleApply = false;
  void Function(WebDavSyncCircleApplyRequest request)? beforeCircleApply;
  final List<bool> circleReplayFlags = <bool>[];
  final List<WebDavSyncCircleApplyRequest> appliedRequests =
      <WebDavSyncCircleApplyRequest>[];
  final List<WebDavSyncCircleBuildRequest> buildRequests =
      <WebDavSyncCircleBuildRequest>[];
  final List<String> appliedCircleJson = <String>[];

  @override
  Future<WebDavSyncCircleInventory> readCircleInventory(
    WebDavSyncLocalSession session,
  ) async => WebDavSyncCircleInventory(
    localProfileIds: localProfileIds,
    localResourceIds: localResourceIds,
    localGrantIds: localGrantIds,
    managingAdminLocalProfileIds: managingAdminLocalProfileIds,
    localProfileNames: localProfileNames,
  );

  @override
  Future<WebDavSyncBuiltCircleState> buildCircleState(
    WebDavSyncLocalSession session,
    WebDavSyncCircleBuildRequest request,
  ) async {
    buildRequests.add(request);
    await beforeCircleSnapshot?.call();
    if (!honorProfileSuppression || request.suppressedLocalProfileIds.isEmpty) {
      return WebDavSyncBuiltCircleState(
        profiles: profiles,
        resources: resources,
        registryOutboxRowCount: registryOutboxRowCount,
      );
    }
    final unsuppressed = <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
      for (final entry in profiles.profiles.entries)
        if (!request.suppressedLocalProfileIds.contains(
          request.identityMaps.circleToLocalProfiles[entry.key],
        ))
          entry.key: entry.value,
    };
    return WebDavSyncBuiltCircleState(
      profiles:
          WebDavSyncCircleMerge.mergeProfiles(<WebDavSyncProfilesDocument>[
            if (request.previousProfiles != null) request.previousProfiles!,
            _circleProfiles(unsuppressed),
          ]),
      resources: resources,
      registryOutboxRowCount: registryOutboxRowCount,
    );
  }

  @override
  Future<bool> drainRegistryTombstoneOutbox() async {
    outboxDrainCalls++;
    final error = outboxDrainError;
    if (error != null) throw error;
    return outboxDrained;
  }

  @override
  Future<WebDavSyncCircleApplyResult> applyCircleState(
    WebDavSyncLocalSession session,
    WebDavSyncCircleApplyRequest request, {
    bool replayingPending = false,
  }) async {
    circleReplayFlags.add(replayingPending);
    appliedRequests.add(request);
    appliedCircleJson.add(
      WebDavSyncCodec.canonicalJson(
        WebDavSyncPendingCircleApply(
          profiles: request.profiles,
          resources: request.resources,
        ).toJson(),
      ),
    );
    beforeCircleApply?.call(request);
    if (failNextCircleApply) {
      failNextCircleApply = false;
      throw StateError('simulated circle apply crash');
    }
    if (conflictNextCircleApply) {
      conflictNextCircleApply = false;
      return WebDavSyncCircleApplyResult.conflict;
    }
    return WebDavSyncCircleApplyResult.applied;
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
  final Set<String> sectionNotFoundFailures = <String>{};
  final Set<String> sectionNetworkFailures = <String>{};
  final Set<String> listedWithoutManifest = <String>{};
  WebDavException? rootError;
  WebDavResponseMetadata? sectionWriteMetadata;
  WebDavException? sectionWriteFailure;
  bool corruptSectionOnWriteFailure = false;
  bool corruptLargeSectionWrites = false;
  int factories = 0;
  Duration readDelay = Duration.zero;
  int activeReads = 0;
  int maxConcurrentReads = 0;

  int get writeCount =>
      events.where((event) => event.startsWith('write:')).length;
  Iterable<String> get allWrittenText => writtenText;

  WebDavResponseMetadata get _metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav'),
    headers: const <String, String>{},
    serverDate: serverDate,
  );

  WebDavResponseMetadata _manifestMetadata(String deviceId) =>
      WebDavResponseMetadata(
        statusCode: 200,
        uri: Uri.parse('https://example.test/dav'),
        headers: <String, String>{'etag': '"$deviceId"'},
        serverDate: serverDate,
        etag: '"$deviceId"',
      );

  Future<void> _trackRead() async {
    if (readDelay == Duration.zero) return;
    activeReads++;
    if (activeReads > maxConcurrentReads) maxConcurrentReads = activeReads;
    try {
      await Future<void>.delayed(readDelay);
    } finally {
      activeReads--;
    }
  }

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
    await _trackRead();
    return WebDavBytesResult(
      bytes: bytes,
      metadata: _manifestMetadata(deviceId),
    );
  }

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) async {
    final bytes = manifests[deviceId];
    return WebDavSyncManifestProbe(
      exists: bytes != null,
      validator: bytes == null
          ? null
          : WebDavSyncManifestValidator.metadata(
              lastModified: HttpDate.format(serverDate!.toUtc()),
              contentLength: bytes.length,
            ),
    );
  }

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) async {
    events.add('read:section:$deviceId:${reference.name}');
    if (sectionNotFoundFailures.contains('$deviceId:${reference.name}')) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'peer section is missing',
      );
    }
    if (sectionNetworkFailures.contains('$deviceId:${reference.name}')) {
      throw const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'peer section connection dropped',
      );
    }
    await _trackRead();
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
    if (corruptLargeSectionWrites &&
        maxBytes == WebDavSyncLimits.maxGraphDocumentBytes) {
      sections['$deviceId:$contentHash']![0] ^= 0xff;
    }
    writtenText.add(String.fromCharCodes(bytes));
    if (sectionWriteFailure case final error?) {
      if (corruptSectionOnWriteFailure) {
        sections['$deviceId:$contentHash']![0] ^= 0xff;
      }
      throw error;
    }
    return sectionWriteMetadata ?? _metadata;
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
    int hotSchemaVersion = WebDavSyncHotDocument.schemaVersion,
    Object? hotPayload,
    WebDavSyncProfilesDocument? profiles,
    WebDavSyncResourcesDocument? resources,
    WebDavSyncLibraryDocument? library,
    WebDavSyncLibraryDocument? tvLibrary,
  }) async {
    Future<WebDavSyncSectionReference> addSection(
      String name,
      Object payload,
      String semanticDigest,
      int maxBytes,
      int schemaVersion,
    ) async {
      final bytes = await codec.sealDocument(
        key: root.key,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: name,
        schemaVersion: schemaVersion,
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
        schemaVersion: schemaVersion,
        size: bytes.length,
      );
    }

    final resolvedHotPayload = hotPayload ?? hot.toJson();
    final hotRef = await addSection(
      'hot/profile-circle',
      resolvedHotPayload,
      semanticDigestOf(resolvedHotPayload),
      WebDavSyncLimits.maxHotDocumentBytes,
      hotSchemaVersion,
    );
    final tombstoneRef = await addSection(
      'tombstones/profile-circle',
      tombstones.toJson(),
      tombstones.semanticDigest,
      WebDavSyncLimits.maxTombstoneDocumentBytes,
      WebDavSyncTombstoneDocument.schemaVersion,
    );
    final profileRef = profiles == null
        ? null
        : await addSection(
            'profiles',
            profiles.toJson(),
            profiles.semanticDigest,
            WebDavSyncLimits.maxHotDocumentBytes,
            WebDavSyncProfilesDocument.schemaVersion,
          );
    final resourceRef = resources == null
        ? null
        : await addSection(
            'resources',
            resources.toJson(),
            resources.semanticDigest,
            WebDavSyncLimits.maxGraphDocumentBytes,
            WebDavSyncResourcesDocument.schemaVersion,
          );
    final libraryRef = library == null
        ? null
        : await addSection(
            'library/${library.circleProfileId}',
            library.toJson(),
            library.semanticDigest,
            WebDavSyncLibraryDocument.maxEncodedBytes,
            WebDavSyncLibraryDocument.schemaVersion,
          );
    final tvLibraryRef = tvLibrary == null
        ? null
        : await addSection(
            'tv-library/${tvLibrary.circleProfileId}',
            tvLibrary.toJson(),
            tvLibrary.semanticDigest,
            WebDavSyncLibraryDocument.maxEncodedBytes,
            WebDavSyncLibraryDocument.schemaVersion,
          );
    final manifest = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: deviceId,
      updatedAtMs: manifestTime.millisecondsSinceEpoch,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const <String, String>{},
      resourceMap: const <String, String>{},
      sections: <WebDavSyncSectionReference>[
        hotRef,
        tombstoneRef,
        if (profileRef != null) profileRef,
        if (resourceRef != null) resourceRef,
        if (libraryRef != null) libraryRef,
        if (tvLibraryRef != null) tvLibraryRef,
      ],
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
