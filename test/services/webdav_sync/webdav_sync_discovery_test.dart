import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_clock.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_discovery.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_setup_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 9, 2);
  late WebDavSyncCodec codec;
  late Uint8List marker;
  late OpenedWebDavSyncRoot root;
  late WebDavSyncBindingStore store;
  late WebDavSyncBinding binding;
  late _MemoryStateRepository states;
  late _FakeDiscoveryTransport transport;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 17)),
    );
    var nonce = 0;
    codec = WebDavSyncCodec(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (_) => nonce++ & 0xff)),
    );
    marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-one',
      createdAt: now.subtract(const Duration(days: 90)),
      memoryKiB: 8,
      iterations: 1,
    );
    root = await codec.openRoot(marker, 'circle-secret');
    var random = 0;
    store = WebDavSyncBindingStore(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => random++ & 0xff),
      ),
    );
    binding = await store.stageBinding(
      location: WebDavSyncFolderLocation(
        endpoint: 'https://example.test/dav',
        folderPath: 'Family',
        serverName: 'Server',
      ),
      config: const WebDavConfig(
        id: 'server',
        name: 'Server',
        baseUrl: 'https://example.test/dav',
        username: 'alice',
        password: 'secret',
      ),
      syncPassphrase: 'circle-secret',
    );
    binding = await store.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: marker,
    );
    states = _MemoryStateRepository();
    transport = _FakeDiscoveryTransport(marker: marker, serverDate: now);
  });

  tearDown(DeviceKeyProvider.debugReset);

  WebDavSyncExistingRootDiscovery discovery() =>
      WebDavSyncExistingRootDiscovery(
        bindingStore: store,
        stateRepository: states,
        codec: codec,
        transportFactory: ({required binding, required secrets}) => transport,
        clock: () => now,
      );

  test(
    'a dormant authentic bootstrap still makes the folder joinable',
    () async {
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'sleeping-device',
        manifestTime: now.subtract(const Duration(days: 45)),
        bootstrapTime: now.subtract(const Duration(days: 46)),
      );

      final found = await discovery().discover(bindingId: binding.id);

      expect(found.bootstrap.manifest.deviceId, 'sleeping-device');
      expect(found.manifests, hasLength(1));
      expect(found.binding.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
      expect(transport.closed, isTrue);
    },
  );

  test('legacy graph metadata is ignored during bootstrap discovery', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'bootstrap-device',
      manifestTime: now.subtract(const Duration(days: 50)),
      bootstrapTime: now.subtract(const Duration(days: 60)),
    );
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'live-device',
      manifestTime: now,
      graphTime: now.subtract(const Duration(minutes: 1)),
      graphSchemaClaim: 2,
    );

    final found = await discovery().discover(bindingId: binding.id);

    expect(found.bootstrap.manifest.deviceId, 'bootstrap-device');
    expect(found.schemaRatchet, 1);
    expect(states.state.peerManifestHighWater, hasLength(2));
    expect(transport.sectionReads, <String>['bootstrap']);
  });

  test('a future bootstrap schema is ratcheted before adoption', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'future-bootstrap-device',
      manifestTime: now,
      bootstrapTime: now,
      bootstrapSchemaVersion: 2,
    );

    await expectLater(
      discovery().discover(bindingId: binding.id),
      throwsA(isA<WebDavSyncBootstrapUpgradeRequiredException>()),
    );

    expect(states.state.schemaRatchet, 2);
    expect(transport.sectionReads, isEmpty);
  });

  test(
    'a corrupt newest bootstrap falls back to an older complete one',
    () async {
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'older-device',
        manifestTime: now.subtract(const Duration(days: 2)),
        bootstrapTime: now.subtract(const Duration(days: 2)),
      );
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'newer-device',
        manifestTime: now,
        bootstrapTime: now,
        corruptBootstrap: true,
      );

      final found = await discovery().discover(bindingId: binding.id);

      expect(found.bootstrap.manifest.deviceId, 'older-device');
    },
  );

  test(
    'a malformed newest bootstrap falls back to an older complete one',
    () async {
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'older-device',
        manifestTime: now.subtract(const Duration(days: 2)),
        bootstrapTime: now.subtract(const Duration(days: 2)),
      );
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'newer-device',
        manifestTime: now,
        bootstrapTime: now,
        malformedBootstrap: true,
      );

      final found = await discovery().discover(bindingId: binding.id);

      expect(found.bootstrap.manifest.deviceId, 'older-device');
    },
  );

  test('a far-future manifest cannot win or poison high-water', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'valid-device',
      manifestTime: now,
      bootstrapTime: now,
    );
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'future-device',
      manifestTime: now.add(const Duration(hours: 2)),
      bootstrapTime: now.add(const Duration(hours: 2)),
    );

    final found = await discovery().discover(bindingId: binding.id);

    expect(found.bootstrap.manifest.deviceId, 'valid-device');
    expect(found.manifests, isNot(contains('future-device')));
    expect(
      states.state.peerManifestHighWater,
      isNot(contains('future-device')),
    );
  });

  test(
    'a committed marker without any complete bootstrap refuses adoption',
    () async {
      await transport.addPeer(
        codec: codec,
        root: root,
        deviceId: 'broken-device',
        manifestTime: now,
        bootstrapTime: now,
        corruptBootstrap: true,
      );

      await expectLater(
        discovery().discover(bindingId: binding.id),
        throwsA(isA<WebDavSyncBootstrapUnavailableException>()),
      );
      final snapshot = await store.load();
      expect(
        snapshot.bindings[binding.id]!.lifecycle,
        WebDavSyncLifecycle.rootVerified,
      );
      expect(snapshot.activeBindingId, isNull);
      expect(transport.closed, isTrue);
    },
  );

  test('only a missing root marker is reported as an empty folder', () async {
    transport.rootMissing = true;

    await expectLater(
      discovery().discover(bindingId: binding.id),
      throwsA(isA<WebDavSyncRootMissingException>()),
    );
  });

  test(
    'a missing devices collection is not reported as an empty folder',
    () async {
      transport.deviceListingMissing = true;

      await expectLater(
        discovery().discover(bindingId: binding.id),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.kind,
            'kind',
            WebDavErrorKind.notFound,
          ),
        ),
      );
    },
  );

  test('active maintenance scan downloads no graph or bootstrap', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'bootstrap-device',
      manifestTime: now.subtract(const Duration(days: 50)),
      bootstrapTime: now.subtract(const Duration(days: 60)),
    );
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'live-device',
      manifestTime: now,
      graphTime: now.subtract(const Duration(minutes: 1)),
    );
    final ownManifest = WebDavSyncManifest(
      circleId: 'circle-one',
      deviceId: (await store.load()).namespaceFor(binding)!.deviceId,
      updatedAtMs: now.millisecondsSinceEpoch,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const <String, String>{'profile-0': 'profile-circle'},
      resourceMap: const <String, String>{},
      sections: const <WebDavSyncSectionReference>[],
    );
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: const <String, String>{
        'profile-circle': 'local-profile',
      },
      circleToLocalResources: const <String, String>{},
      ownManifest: ownManifest,
    );
    binding = await store.setLifecycle(binding.id, WebDavSyncLifecycle.active);
    await store.promoteStaged(binding.id);

    final found = await discovery().scanActive(bindingId: binding.id);

    expect(found.manifests, hasLength(2));
    expect(transport.sectionReads, isEmpty);
    expect((await store.load()).activeBindingId, binding.id);
  });

  test('a repeated clock outlier is persisted and recoverable', () async {
    await transport.addPeer(
      codec: codec,
      root: root,
      deviceId: 'bootstrap-device',
      manifestTime: now,
      bootstrapTime: now,
    );
    states.state = WebDavSyncEngineState(
      clock: WebDavSyncClockState(
        acceptedOffsetMs: 0,
        serverHighWaterMs: now.millisecondsSinceEpoch,
      ),
    );
    transport.serverDate = now.add(const Duration(days: 2));

    await expectLater(
      discovery().discover(bindingId: binding.id),
      throwsStateError,
    );
    expect(states.state.clock.outlierCount, 1);
    expect(
      states.state.lastClockPauseReason,
      WebDavSyncClockPauseReason.offsetOutlier,
    );

    final recovered = await discovery().discover(bindingId: binding.id);

    expect(recovered.bootstrap.manifest.deviceId, 'bootstrap-device');
    expect(states.state.clock.outlierCount, 0);
    expect(states.state.lastClockPauseReason, isNull);
  });
}

final class _MemoryStateRepository implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineState state = const WebDavSyncEngineState();

  @override
  Future<WebDavSyncEngineState> load(String namespaceId) async => state;

  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  ) async => state = update(state);
}

final class _FakeDiscoveryTransport implements WebDavSyncTransport {
  _FakeDiscoveryTransport({required this.marker, required this.serverDate});

  final Uint8List marker;
  DateTime serverDate;
  final Map<String, Uint8List> manifests = <String, Uint8List>{};
  final Map<String, Uint8List> sections = <String, Uint8List>{};
  final List<String> sectionReads = <String>[];
  bool closed = false;
  bool rootMissing = false;
  bool deviceListingMissing = false;

  WebDavResponseMetadata get _metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav/Family/debrify-sync'),
    headers: const <String, String>{},
    serverDate: serverDate,
  );

  @override
  Future<WebDavBytesResult> readRootMarker() async {
    if (rootMissing) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'root marker missing',
      );
    }
    return WebDavBytesResult(
      bytes: Uint8List.fromList(marker),
      metadata: _metadata,
    );
  }

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() async {
    if (deviceListingMissing) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'devices collection missing',
      );
    }
    return WebDavSyncPeerListing(
      deviceIds: manifests.keys.toList()..sort(),
      metadata: _metadata,
    );
  }

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) async =>
      WebDavBytesResult(bytes: manifests[deviceId]!, metadata: _metadata);

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) async {
    sectionReads.add(reference.name);
    return WebDavBytesResult(
      bytes: sections['$deviceId:${reference.contentHash}']!,
      metadata: _metadata,
    );
  }

  @override
  Future<void> ensureOwnLayout(String deviceId) => throw UnimplementedError();

  @override
  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  }) => throw UnimplementedError();

  @override
  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  ) => throw UnimplementedError();

  @override
  void close() => closed = true;

  Future<void> addPeer({
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required DateTime manifestTime,
    DateTime? bootstrapTime,
    DateTime? graphTime,
    bool corruptBootstrap = false,
    bool malformedBootstrap = false,
    int bootstrapSchemaVersion = 1,
    int graphSchemaClaim = 1,
  }) async {
    final references = <WebDavSyncSectionReference>[];
    Future<void> addGraph(WebDavSyncGraphKind kind, DateTime updatedAt) async {
      final package = await _package(kind);
      final payload =
          kind == WebDavSyncGraphKind.bootstrap && malformedBootstrap
          ? jsonEncode(await _malformedPackageEnvelope(package))
          : jsonEncode(await PortableProfilePackage.withIntegrity(package));
      var encoded = await codec.sealDocument(
        key: root.key,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: kind.logicalName,
        schemaVersion: kind == WebDavSyncGraphKind.bootstrap
            ? bootstrapSchemaVersion
            : 1,
        payload: payload,
        maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
      );
      if (kind == WebDavSyncGraphKind.bootstrap && corruptBootstrap) {
        encoded = Uint8List.fromList(encoded)..[encoded.length - 1] ^= 1;
      }
      final reference = WebDavSyncSectionReference(
        name: kind.logicalName,
        contentHash: contentHashOf(encoded),
        semanticDigest: WebDavSyncGraphBuilder.semanticDigest(package),
        updatedAtMs: updatedAt.millisecondsSinceEpoch,
        schemaVersion: kind == WebDavSyncGraphKind.bootstrap
            ? bootstrapSchemaVersion
            : 1,
        size: encoded.length,
      );
      sections['$deviceId:${reference.contentHash}'] = encoded;
      references.add(reference);
    }

    if (bootstrapTime != null) {
      await addGraph(WebDavSyncGraphKind.bootstrap, bootstrapTime);
    }
    if (graphTime != null) {
      await addGraph(WebDavSyncGraphKind.graph, graphTime);
    }
    final manifest = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: deviceId,
      updatedAtMs: manifestTime.millisecondsSinceEpoch,
      clockOffsetMs: 0,
      graphSchemaClaim: graphSchemaClaim,
      profileMap: const <String, String>{'profile-0': 'profile-circle'},
      resourceMap: const <String, String>{},
      sections: references,
    );
    manifests[deviceId] = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      payload: manifest.toJson(),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
  }
}

Future<Map<String, dynamic>> _malformedPackageEnvelope(
  PortableProfilePackage package,
) async {
  final body = Map<String, dynamic>.from(package.toJson())
    ..['profiles'] = <Object?>['not-a-profile-map'];
  final digest = await Sha256().hash(utf8.encode(jsonEncode(body)));
  return <String, dynamic>{
    ...body,
    'integrity': <String, dynamic>{
      'algorithm': 'sha256',
      'digest': base64UrlEncode(digest.bytes).replaceAll('=', ''),
    },
  };
}

Future<PortableProfilePackage> _package(WebDavSyncGraphKind kind) async {
  final includePreferences = kind == WebDavSyncGraphKind.bootstrap;
  final section = await PortableProfilePackage.buildSection(
    const <String, Object?>{'theme_mode': 'dark'},
  );
  return PortableProfilePackage(
    mode: 'deviceGraph',
    createdAt: DateTime.utc(2026, 1, 1),
    profiles: <Map<String, dynamic>>[
      <String, dynamic>{
        'backupId': 'profile-0',
        'name': 'Admin',
        'role': 'admin',
        'policy': 'manageProfiles,backupRestore',
        if (includePreferences) 'preferencesSection': 'profile-0-preferences',
      },
    ],
    resources: const <Map<String, dynamic>>[],
    sections: <String, dynamic>{
      if (includePreferences) 'profile-0-preferences': section,
    },
  );
}
