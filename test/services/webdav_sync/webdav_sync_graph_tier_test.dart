import 'dart:io';

import 'package:debrify/services/transfer/streaming_encrypted_file.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_snapshot_models.dart';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_discovery.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph_tier.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_manifest_publisher.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _digest =
    '1111111111111111111111111111111111111111111111111111111111111111';
final _now = DateTime.utc(2026, 9, 2);

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ProfileAuthorizationContext authorization;
  late WebDavSyncBindingStore bindingStore;
  late WebDavSyncBinding binding;
  late WebDavSyncGraphBuilder graphBuilder;
  late _MemoryStateRepository states;
  late _FakeDiscovery discovery;
  late _FakePublisher publisher;
  late _FakeAdoption adoption;
  late _FakeCycleRunner cycle;
  late WebDavSyncActiveRootSnapshot snapshot;
  late String localProfileId;
  late List<String> events;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 5)),
    );
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'webdav-sync-graph-tier-',
    );
    final documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    final support = Directory(p.join(temporaryDirectory.path, 'support'));
    final cache = Directory(p.join(temporaryDirectory.path, 'cache'));
    await documents.create(recursive: true);
    await support.create(recursive: true);
    await cache.create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    localProfileId = admin.id;
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
    );
    authorization = await ProfileAuthorizationContext.capture(registry);
    graphBuilder = WebDavSyncGraphBuilder(
      ProfilePackageService(
        registry: registry,
        resources: ConnectionResourceService(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
        ),
      ),
    );
    bindingStore = WebDavSyncBindingStore(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    binding = await bindingStore.stageBinding(
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
    final codec = WebDavSyncCodec();
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-one',
      createdAt: _now,
      memoryKiB: 8,
      iterations: 1,
    );
    final root = await codec.openRoot(marker, 'circle-secret');
    binding = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: marker,
    );
    binding = await bindingStore.setLifecycle(
      binding.id,
      WebDavSyncLifecycle.active,
    );
    await bindingStore.promoteStaged(binding.id);
    final namespace = (await bindingStore.load()).namespaceFor(binding)!;
    final ownManifest = _completeManifest(
      circleId: root.document.circleId,
      deviceId: namespace.deviceId,
    );
    final peerManifest = _completeManifest(
      circleId: root.document.circleId,
      deviceId: 'peer-device',
      includeLegacyGraph: true,
    );
    states = _MemoryStateRepository(
      WebDavSyncEngineState(
        circleToLocalProfiles: <String, String>{
          'profile-circle': localProfileId,
        },
        circleToLocalResources: const <String, String>{},
        ownManifest: ownManifest,
        publishedBootstrapDatabaseDigest: _digest,
      ),
    );
    snapshot = WebDavSyncActiveRootSnapshot(
      binding: binding,
      namespace: namespace,
      root: root,
      markerBytes: marker,
      serverNowMs: _now.millisecondsSinceEpoch,
      manifests: <String, WebDavSyncManifest>{
        namespace.deviceId: ownManifest,
        'peer-device': peerManifest,
      },
      schemaRatchet: 1,
    );
    events = <String>[];
    discovery = _FakeDiscovery(() => snapshot, events);
    publisher = _FakePublisher(states, () => snapshot, events);
    adoption = _FakeAdoption(events);
    cycle = _FakeCycleRunner(events);
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  WebDavSyncGraphTier tier({
    Future<WebDavSyncCycleContext?> Function()? contextProvider,
    WebDavSyncGraphTransportFactory? transportFactory,
    WebDavSyncCodec? codec,
  }) => WebDavSyncGraphTier(
    bindingStore: bindingStore,
    stateRepository: states,
    discovery: discovery,
    graphBuilder: graphBuilder,
    adoption: adoption,
    publisher: publisher,
    cycleRunner: cycle,
    contextProvider: contextProvider ?? () async => null,
    transportFactory: transportFactory,
    codec: codec,
    clock: () => _now,
  );

  test('maintain does not compare or prompt for remote graphs', () async {
    final report = await tier().maintain(
      authorization: authorization,
      runBootstrapMaintenance: false,
    );

    expect(report.disposition, WebDavSyncGraphTierDisposition.unchanged);
    expect(events, <String>['scan']);
    expect(snapshot.manifests['peer-device']!.section('graph'), isNotNull);
  });

  WebDavSyncVerifiedMaintenance verifiedCycle({
    String? namespaceId,
    String? authorityHash,
    int? checkedAtMs,
    int schemaRatchet = 1,
  }) {
    states.state = states.state.copyWith(
      lastSuccessfulSyncMs: _now.millisecondsSinceEpoch,
    );
    return WebDavSyncVerifiedMaintenance(
      namespaceId: namespaceId ?? binding.namespaceId,
      authorityContentHash:
          authorityHash ?? snapshot.namespace.pinnedAuthorityHash!,
      ownManifest: states.state.ownManifest,
      schemaRatchet: schemaRatchet,
      syncedAtMs: _now.millisecondsSinceEpoch,
      checkedAtMs: checkedAtMs ?? _now.millisecondsSinceEpoch,
    );
  }

  test(
    'immediate maintenance reuses a verified cycle and leaves daily work due',
    () async {
      final report = await tier().maintain(
        authorization: authorization,
        runBootstrapMaintenance: false,
        verifiedCycle: verifiedCycle(),
      );
      expect(report.disposition, WebDavSyncGraphTierDisposition.unchanged);
      expect(events, isEmpty, reason: 'zero additional server requests');
      expect(states.state.lastBootstrapCheckMs, isNull);
      expect(states.state.publishedBootstrapDatabaseDigest, _digest);
    },
  );

  for (final changed in [
    'namespace',
    'authority',
    'age',
    'clock',
    'state',
    'manifest',
    'force',
  ]) {
    test(
      'maintenance rescans when verified cycle cannot be reused: $changed',
      () async {
        final proof = verifiedCycle(
          namespaceId: changed == 'namespace' ? 'old-namespace' : null,
          authorityHash: changed == 'authority' ? 'old-authority' : null,
          checkedAtMs: changed == 'age'
              ? _now
                    .subtract(const Duration(seconds: 31))
                    .millisecondsSinceEpoch
              : changed == 'clock'
              ? _now.add(const Duration(seconds: 1)).millisecondsSinceEpoch
              : null,
        );
        if (changed == 'state') {
          states.state = states.state.copyWith(lastSuccessfulSyncMs: 1);
        }
        if (changed == 'manifest') {
          states.state = states.state.copyWith(
            ownManifest: snapshot.manifests['peer-device'],
          );
        }
        await tier().maintain(
          authorization: authorization,
          runBootstrapMaintenance: false,
          force: changed == 'force',
          verifiedCycle: proof,
        );
        expect(events, contains('scan'));
      },
    );
  }

  test(
    'verified future bootstrap schema still blocks publication and ratchets',
    () async {
      final futureVersion = WebDavSyncGraphBuilder.bootstrapSchemaVersion + 1;
      final report = await tier().maintain(
        authorization: authorization,
        runBootstrapMaintenance: false,
        verifiedCycle: verifiedCycle(schemaRatchet: futureVersion),
      );
      expect(report.disposition, WebDavSyncGraphTierDisposition.updateRequired);
      expect(states.state.schemaRatchet, futureVersion);
      expect(events, isEmpty);
    },
  );

  test(
    'an incomplete verified manifest still requires foreground repair',
    () async {
      states.state = states.state.copyWith(
        ownManifest: _completeManifest(
          circleId: snapshot.root.document.circleId,
          deviceId: snapshot.namespace.deviceId,
          includeLegacyGraph: true,
        ),
      );
      final report = await tier().maintain(
        authorization: authorization,
        runBootstrapMaintenance: false,
        verifiedCycle: verifiedCycle(),
      );
      expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
      expect(events, ['publish']);
    },
  );

  test(
    'idle maintenance skips server and archive work when its durable check is current',
    () async {
      states.state = states.state.copyWith(
        lastBootstrapCheckMs: _now.millisecondsSinceEpoch,
      );
      final report = await tier().maintain(
        authorization: authorization,
        bootstrapOnly: true,
      );
      expect(report.disposition, WebDavSyncGraphTierDisposition.unchanged);
      expect(events, isEmpty);
    },
  );

  test('identity reconciliation republishes the complete seed', () async {
    await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
      actingProfileId: authorization.profileId,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
    authorization = await ProfileAuthorizationContext.capture(registry);

    final report = await tier().maintain(
      authorization: authorization,
      runBootstrapMaintenance: false,
    );

    expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
    expect(events, <String>['publish']);
  });

  test('own manifest repair removes a legacy graph reference', () async {
    final legacyOwn = _completeManifest(
      circleId: snapshot.root.document.circleId,
      deviceId: snapshot.namespace.deviceId,
      includeLegacyGraph: true,
    );
    snapshot = WebDavSyncActiveRootSnapshot(
      binding: snapshot.binding,
      namespace: snapshot.namespace,
      root: snapshot.root,
      markerBytes: snapshot.markerBytes,
      serverNowMs: snapshot.serverNowMs,
      manifests: <String, WebDavSyncManifest>{
        snapshot.namespace.deviceId: legacyOwn,
      },
      schemaRatchet: 1,
    );

    final report = await tier().maintain(
      authorization: authorization,
      runBootstrapMaintenance: false,
    );

    expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
    expect(events, <String>['scan', 'publish']);
    expect(states.state.ownManifest!.section('graph'), isNull);
  });

  test('daily maintenance regenerates the bootstrap database digest', () async {
    final maps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: <String, String>{'profile-circle': localProfileId},
      circleToLocalResources: const <String, String>{},
    );
    final bootstrap = await graphBuilder.build(
      kind: WebDavSyncGraphKind.bootstrap,
      authorization: authorization,
      identityMaps: maps,
    );
    states.state = states.state.copyWith(
      publishedBootstrapDatabaseDigest: bootstrap.bootstrapDatabaseDigest,
    );

    final report = await tier().maintain(authorization: authorization);

    expect(report.disposition, WebDavSyncGraphTierDisposition.unchanged);
    expect(states.state.lastBootstrapCheckMs, _now.millisecondsSinceEpoch);
    expect(events, <String>['scan']);
  });

  test('signed-out devices stay visible and safe to remove', () async {
    final codec = WebDavSyncCodec();
    final maps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: <String, String>{'profile-circle': localProfileId},
      circleToLocalResources: const <String, String>{},
    );
    final bootstrap = await graphBuilder.build(
      kind: WebDavSyncGraphKind.bootstrap,
      authorization: authorization,
      identityMaps: maps,
    );
    addTearDown(() => bootstrap.snapshot?.dispose());
    final sharedObject = File('${bootstrap.snapshot!.staging.path}/remote.enc');
    final sealed = await StreamingEncryptedFile.encrypt(
      source: bootstrap.snapshot!.archive,
      destination: sharedObject,
      context: 'debrify/sync-snapshot/v2/${snapshot.root.document.circleId}',
      key: snapshot.root.key.secretKey,
    );
    final descriptor = WebDavSyncSnapshotDescriptor(
      contentHash: sealed.sha256Hex,
      size: sealed.bytes,
      semanticDigest: bootstrap.semanticDigest,
      databaseDigest: bootstrap.bootstrapDatabaseDigest!,
      profileMap: bootstrap.profileMap,
      resourceMap: bootstrap.resourceMap,
    );
    final bootstrapBytes = await codec.sealDocument(
      key: snapshot.root.key,
      circleId: snapshot.root.document.circleId,
      deviceId: snapshot.namespace.deviceId,
      logicalName: 'bootstrap',
      schemaVersion: 2,
      payload: descriptor.toJson(),
      maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
    );
    final bootstrapReference = WebDavSyncSectionReference(
      name: 'bootstrap',
      contentHash: contentHashOf(bootstrapBytes),
      semanticDigest: bootstrap.semanticDigest,
      updatedAtMs: _now.millisecondsSinceEpoch,
      schemaVersion: 2,
      size: bootstrapBytes.length,
    );
    final ownManifest = _completeManifest(
      circleId: snapshot.root.document.circleId,
      deviceId: snapshot.namespace.deviceId,
      bootstrap: bootstrapReference,
      profileMap: bootstrap.profileMap,
      resourceMap: bootstrap.resourceMap,
    );
    final targetManifest = _completeManifest(
      circleId: snapshot.root.document.circleId,
      deviceId: 'peer-device',
      includeLegacyGraph: true,
    );
    snapshot = WebDavSyncActiveRootSnapshot(
      binding: snapshot.binding,
      namespace: snapshot.namespace,
      root: snapshot.root,
      markerBytes: snapshot.markerBytes,
      serverNowMs: snapshot.serverNowMs,
      manifests: <String, WebDavSyncManifest>{
        snapshot.namespace.deviceId: ownManifest,
        'peer-device': targetManifest,
      },
      schemaRatchet: 1,
    );
    states.state = states.state.copyWith(ownManifest: ownManifest);
    final targetBytes = await codec.sealDocument(
      key: snapshot.root.key,
      circleId: snapshot.root.document.circleId,
      deviceId: 'peer-device',
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      payload: targetManifest.toJson(),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    final registration = await codec.sealDocument(
      key: snapshot.root.key,
      circleId: snapshot.root.document.circleId,
      deviceId: 'peer-device',
      logicalName: 'registration',
      schemaVersion: 1,
      payload: const {'signedOut': true},
      maxBytes: 4096,
    );
    final transport = _ForgetTransport(
      registration: registration,
      marker: snapshot.markerBytes,
      bootstrap: bootstrapBytes,
      sharedObject: sharedObject,
      targetManifest: targetBytes,
      events: events,
    );
    final context = WebDavSyncCycleContext(
      namespaceId: snapshot.namespace.id,
      deviceId: snapshot.namespace.deviceId,
      markerPin: snapshot.markerBytes,
      root: snapshot.root,
      circleToLocalProfiles: maps.circleToLocalProfiles,
      circleToLocalResources: maps.circleToLocalResources,
      wireProfileMap: bootstrap.profileMap,
      wireResourceMap: bootstrap.resourceMap,
      active: true,
    );

    final devices = await tier(
      transportFactory: ({required binding, required secrets}) => transport,
      codec: codec,
    ).listDevices();
    expect(devices, hasLength(2));
    expect(devices.first.isThisDevice, isTrue);
    expect(devices.first.isRegistered, isTrue);
    expect(devices.last.deviceId, 'peer-device');
    expect(devices.last.isRegistered, isFalse);
    events.clear();
    await tier(
      contextProvider: () async => context,
      transportFactory: ({required binding, required secrets}) => transport,
      codec: codec,
    ).forgetDevice(deviceId: 'peer-device', authorization: authorization);

    expect(events.first, 'cycle');
    expect(events.where((event) => event == 'scan'), hasLength(1));
    expect(events, contains('read:bootstrap'));
    expect(events, isNot(contains('read:graph')));
    expect(events, contains('delete:peer-device'));
  });
}

WebDavSyncManifest _completeManifest({
  required String circleId,
  required String deviceId,
  bool includeLegacyGraph = false,
  WebDavSyncSectionReference? bootstrap,
  Map<String, String> profileMap = const <String, String>{
    'profile-backup': 'profile-circle',
  },
  Map<String, String> resourceMap = const <String, String>{},
}) => WebDavSyncManifest(
  circleId: circleId,
  deviceId: deviceId,
  updatedAtMs: _now.millisecondsSinceEpoch,
  clockOffsetMs: 0,
  graphSchemaClaim: 1,
  profileMap: profileMap,
  resourceMap: resourceMap,
  sections: <WebDavSyncSectionReference>[
    bootstrap ?? _reference('bootstrap'),
    _reference('profiles'),
    _reference('resources'),
    _reference('hot/profile-circle'),
    _reference('tombstones/profile-circle'),
    if (includeLegacyGraph) _reference('graph'),
  ],
);

WebDavSyncSectionReference _reference(String name) =>
    WebDavSyncSectionReference(
      name: name,
      contentHash: _digest,
      semanticDigest: _digest,
      updatedAtMs: _now.millisecondsSinceEpoch,
      schemaVersion: 1,
      size: 1,
    );

final class _MemoryStateRepository implements WebDavSyncEngineStateRepository {
  _MemoryStateRepository(this.state);

  WebDavSyncEngineState state;

  @override
  Future<WebDavSyncEngineState> load(String namespaceId) async => state;

  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  ) async => state = update(state);
}

final class _FakeDiscovery implements WebDavSyncActiveRootDiscoverer {
  const _FakeDiscovery(this.snapshot, this.events);

  final WebDavSyncActiveRootSnapshot Function() snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncActiveRootSnapshot> scanActive({
    required String bindingId,
  }) async {
    events.add('scan');
    return snapshot();
  }
}

final class _FakePublisher implements WebDavSyncSeedPublisher {
  const _FakePublisher(this.states, this.snapshot, this.events);

  final _MemoryStateRepository states;
  final WebDavSyncActiveRootSnapshot Function() snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncPublishedSeed> publish({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
    WebDavSyncPreparedGraph? preparedBootstrap,
  }) async {
    events.add('publish');
    final current = snapshot();
    final manifest = _completeManifest(
      circleId: current.root.document.circleId,
      deviceId: current.namespace.deviceId,
    );
    await states.update(
      current.namespace.id,
      (state) => state.copyWith(ownManifest: manifest),
    );
    return WebDavSyncPublishedSeed(
      material: WebDavSyncSeedMaterial(
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles:
              states.state.circleToLocalProfiles ?? const <String, String>{},
          circleToLocalResources:
              states.state.circleToLocalResources ?? const <String, String>{},
        ),
        profileMap: manifest.profileMap,
        resourceMap: manifest.resourceMap,
        sections: const <WebDavSyncSeedSection>[],
        profileStates: const <String, WebDavSyncProfileEngineState>{},
        bootstrapDatabaseDigest: _digest,
        beforeRootCommit: () async {},
      ),
      manifest: manifest,
      serverNowMs: _now.millisecondsSinceEpoch,
    );
  }
}

final class _FakeAdoption implements WebDavSyncAdoptionRunner {
  const _FakeAdoption(this.events);

  final List<String> events;

  @override
  Future<WebDavSyncAdoptionRecord> adopt(WebDavSyncAdoptionRequest request) =>
      throw UnimplementedError();

  @override
  Future<WebDavSyncAdoptionRecord?> recover(String namespaceId) async => null;

  @override
  Future<Set<String>> retryPendingPrunes(String namespaceId) async {
    events.add('prune');
    return const <String>{};
  }
}

final class _FakeCycleRunner implements WebDavSyncCycleRunner {
  const _FakeCycleRunner(this.events);

  final List<String> events;

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  }) async {
    events.add('cycle');
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
  }
}

final class _ForgetTransport
    implements
        WebDavSyncActivationTransport,
        WebDavSyncRegistrationTransport,
        WebDavSyncSharedObjectTransport {
  const _ForgetTransport({
    required this.marker,
    required this.bootstrap,
    required this.sharedObject,
    required this.targetManifest,
    required this.events,
    this.registration,
  });

  final File sharedObject;
  @override
  Future<WebDavExistenceResult> probeSharedObject(String contentHash) =>
      throw UnimplementedError();
  @override
  Future<WebDavResponseMetadata> writeSharedObject(
    String contentHash,
    File file, {
    required int maxBytes,
  }) => throw UnimplementedError();
  @override
  Future<WebDavFileResult> readSharedObject(
    String contentHash,
    File destination, {
    required int maxBytes,
    void Function()? checkCancelled,
  }) async {
    checkCancelled?.call();
    await sharedObject.copy(destination.path);
    return WebDavFileResult(
      file: destination,
      bytesWritten: await destination.length(),
      metadata: _metadata,
    );
  }

  final Uint8List? registration;
  @override
  Future<WebDavBytesResult?> readRegistration(String deviceId) async =>
      deviceId == 'peer-device' && registration != null
      ? WebDavBytesResult(bytes: registration!, metadata: _metadata)
      : null;
  @override
  Future<void> writeRegistration(String deviceId, Uint8List bytes) async =>
      throw UnimplementedError();

  final Uint8List marker;
  final Uint8List bootstrap;
  final Uint8List targetManifest;
  final List<String> events;

  WebDavResponseMetadata get _metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav'),
    headers: const <String, String>{},
    serverDate: _now,
  );

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) async {
    events.add('read:${reference.name}');
    return WebDavBytesResult(bytes: bootstrap, metadata: _metadata);
  }

  @override
  Future<WebDavBytesResult> readRootMarker() async =>
      WebDavBytesResult(bytes: marker, metadata: _metadata);

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) async =>
      WebDavBytesResult(bytes: targetManifest, metadata: _metadata);

  @override
  Future<void> deleteDeviceDirectory(String deviceId) async {
    events.add('delete:$deviceId');
  }

  @override
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<void> ensureActivationLayout() => throw UnimplementedError();

  @override
  Future<void> verifyLinearizability({
    required String syncRootPath,
    Future<void> Function()? beforeSend,
  }) => throw UnimplementedError();

  @override
  Future<void> ensureOwnLayout(String deviceId) => throw UnimplementedError();

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() => throw UnimplementedError();

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) =>
      throw UnimplementedError();

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
