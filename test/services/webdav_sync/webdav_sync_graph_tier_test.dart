import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
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

const _appliedDigest =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _remoteDigest =
    '2222222222222222222222222222222222222222222222222222222222222222';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ProfileAuthorizationContext authorization;
  late WebDavSyncBindingStore bindingStore;
  late WebDavSyncBinding binding;
  late _MemoryStateRepository states;
  late WebDavSyncActiveGraphSnapshot snapshot;
  late _FakeDiscovery discovery;
  late _FakeAdoption adoption;
  late _FakePublisher publisher;
  late _FakeCycleRunner cycle;
  late WebDavSyncGraphBuilder graphBuilder;
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
    final codec = WebDavSyncCodec(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-one',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    final root = await codec.openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    binding = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: marker,
    );
    final namespace = (await bindingStore.load()).namespaceFor(binding)!;
    final ownManifest = _manifest(
      circleId: root.document.circleId,
      deviceId: namespace.deviceId,
      digest: _appliedDigest,
    );
    states = _MemoryStateRepository(
      WebDavSyncEngineState(
        circleToLocalProfiles: <String, String>{'profile-circle': admin.id},
        circleToLocalResources: const <String, String>{},
        ownManifest: ownManifest,
        appliedGraphDigest: _appliedDigest,
      ),
    );
    binding = await bindingStore.setLifecycle(
      binding.id,
      WebDavSyncLifecycle.active,
    );
    await bindingStore.promoteStaged(binding.id);
    final remoteManifest = _manifest(
      circleId: root.document.circleId,
      deviceId: 'peer-device',
      digest: _remoteDigest,
    );
    final package = PortableProfilePackage(
      mode: 'deviceGraph',
      createdAt: DateTime.utc(2026, 9, 1),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{'backupId': 'profile-backup'},
      ],
      resources: const <Map<String, dynamic>>[],
      sections: const <String, dynamic>{},
      omissions: const <String, dynamic>{},
    );
    snapshot = WebDavSyncActiveGraphSnapshot(
      binding: binding,
      namespace: namespace,
      root: root,
      markerBytes: marker,
      serverNowMs: DateTime.utc(2026, 9, 2).millisecondsSinceEpoch,
      manifests: <String, WebDavSyncManifest>{
        namespace.deviceId: ownManifest,
        'peer-device': remoteManifest,
      },
      latestGraph: WebDavSyncDiscoveredGraph(
        manifest: remoteManifest,
        document: OpenedWebDavSyncGraph(
          kind: WebDavSyncGraphKind.graph,
          package: package,
          semanticDigest: _remoteDigest,
        ),
      ),
      schemaRatchet: 1,
    );
    events = <String>[];
    discovery = _FakeDiscovery(snapshot, events);
    adoption = _FakeAdoption(states, events);
    publisher = _FakePublisher(states, snapshot, events);
    cycle = _FakeCycleRunner(events);
  });

  tearDown(() async {
    ProfileDatabaseSnapshot.debugExportBudgetOverride = null;
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'oversized bootstrap compacts rebuildable TV data and retains IPTV credentials',
    () async {
      final resourceService = graphBuilder.packageService.resources;
      final resource = await resourceService.create(
        context: authorization,
        type: ConnectionResourceType.iptvXtream,
        label: 'Living room IPTV',
        publicConfig: const <String, dynamic>{
          'playlistName': 'Living room IPTV',
          'providerKind': 'xtream',
        },
        secretConfig: const <String, dynamic>{
          'id': 'iptv-one',
          'name': 'Living room IPTV',
          'url': '',
          'serverUrl': 'https://iptv.invalid',
          'username': 'alice',
          'password': 'secret',
          'addedAt': '2026-09-02T00:00:00.000Z',
        },
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final scope = ProfileRuntime.capture();
      final documents = await AppStorage.documents();
      final debrify = scope.fileIn(documents, 'documents', 'debrify_tv.db');
      await debrify.parent.create(recursive: true);
      final debrifyDb = await openDatabase(debrify.path, singleInstance: false);
      await debrifyDb.execute(
        'CREATE TABLE tv_channels (channel_id TEXT PRIMARY KEY)',
      );
      await debrifyDb.insert('tv_channels', <String, Object?>{
        'channel_id': 'channel-one',
      });
      await debrifyDb.close();

      final catalog = scope.fileIn(documents, 'documents', 'iptv_catalog.db');
      final catalogDb = await openDatabase(catalog.path, singleInstance: false);
      await catalogDb.execute('CREATE TABLE channels (payload TEXT NOT NULL)');
      await catalogDb.execute(
        'CREATE TABLE category_manual_orders '
        '(catalog_key TEXT NOT NULL, grp TEXT NOT NULL, '
        'manual_position INTEGER NOT NULL)',
      );
      await catalogDb.insert('channels', <String, Object?>{
        'payload': List<String>.filled(256 * 1024, 'x').join(),
      });
      await catalogDb.insert('category_manual_orders', <String, Object?>{
        'catalog_key': 'xtream|resource',
        'grp': 'News',
        'manual_position': 0,
      });
      await catalogDb.close();
      ProfileDatabaseSnapshot.debugExportBudgetOverride = 64 * 1024;

      final graph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: authorization,
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: <String, String>{'p-circle': scope.profileId},
          circleToLocalResources: <String, String>{'r-circle': resource.id},
        ),
      );

      expect(
        graph.package.omissions['rebuildableDatabaseCachesOmitted'],
        contains('iptv_catalog.db'),
      );
      expect(
        DebrifyTvBackupOmission.fromOmissions(
          graph.package.omissions,
        )?.channels,
        1,
      );
      final exportedResource = graph.package.resources.single;
      expect(exportedResource['type'], ConnectionResourceType.iptvXtream.name);
      expect((exportedResource['secretConfig'] as Map)['username'], 'alice');
      expect((exportedResource['secretConfig'] as Map)['password'], 'secret');
    },
  );

  WebDavSyncGraphTier tier({
    Future<WebDavSyncCycleContext?> Function()? contextProvider,
    WebDavSyncGraphTransportFactory? transportFactory,
  }) {
    return WebDavSyncGraphTier(
      bindingStore: bindingStore,
      stateRepository: states,
      discovery: discovery,
      graphBuilder: graphBuilder,
      adoption: adoption,
      publisher: publisher,
      cycleRunner: cycle,
      contextProvider: contextProvider ?? () async => null,
      transportFactory: transportFactory,
      clock: () => DateTime.utc(2026, 9, 2),
    );
  }

  test(
    'refresh export orders by circle identity and retains portable files',
    () async {
      final admin = (await registry.listProfiles()).single;
      final kid = await registry.createProfile(
        name: 'Kid',
        role: UserProfileRole.member,
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final resourceService = graphBuilder.packageService.resources;
      final firstResource = await resourceService.create(
        context: authorization,
        type: ConnectionResourceType.realDebrid,
        label: 'First resource',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'apiKey': 'first-secret'},
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final secondResource = await resourceService.create(
        context: authorization,
        type: ConnectionResourceType.allDebrid,
        label: 'Second resource',
        publicConfig: const <String, dynamic>{},
        secretConfig: const <String, dynamic>{'apiKey': 'second-secret'},
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final documents = await AppStorage.documents();
      final engineFile = ProfileScope(
        profileId: admin.id,
        dataGeneration: admin.visibleDataGeneration,
        sessionEpoch: 0,
      ).fileIn(documents, 'documents', 'engines/metadata.json');
      await engineFile.parent.create(recursive: true);
      await engineFile.writeAsString(
        '{"version":"1.0","updatedAt":"2026-09-01T00:00:00Z",'
        '"engines":{}}',
      );

      final graph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: <String, String>{
            'p-z-admin': admin.id,
            'p-a-kid': kid.id,
          },
          circleToLocalResources: <String, String>{
            'r-z-first': firstResource.id,
            'r-a-second': secondResource.id,
          },
        ),
      );

      expect(graph.profileMap.values, <String>['p-a-kid', 'p-z-admin']);
      expect(graph.resourceMap.values, <String>['r-a-second', 'r-z-first']);
      expect(graph.package.profiles.first['name'], 'Kid');
      expect(graph.package.resources.first['label'], 'Second resource');
      expect(graph.package.profiles.last.containsKey('filesSection'), isTrue);
      expect(graph.package.sections, isNotEmpty);
    },
  );

  test('new remote graph is persisted for a quiet prompt', () async {
    final report = await tier().maintain(
      authorization: authorization,
      force: true,
    );

    expect(report.disposition, WebDavSyncGraphTierDisposition.remoteChange);
    expect(report.change?.semanticDigest, _remoteDigest);
    expect(states.state.pendingGraphDigest, _remoteDigest);
    expect(events, <String>['scan']);
  });

  test(
    'legacy row-order and engine-file drift republishes without a prompt',
    () async {
      final admin = (await registry.listProfiles()).single;
      final documents = await AppStorage.documents();
      final engineFile = ProfileScope(
        profileId: admin.id,
        dataGeneration: admin.visibleDataGeneration,
        sessionEpoch: 0,
      ).fileIn(documents, 'documents', 'engines/metadata.json');
      await engineFile.parent.create(recursive: true);
      await engineFile.writeAsString(
        '{"version":"1.0","updatedAt":"2026-09-01T00:00:00Z",'
        '"engines":{}}',
      );
      final local = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: states.state.circleToLocalProfiles!,
          circleToLocalResources: states.state.circleToLocalResources!,
        ),
      );
      final fileSection = await PortableProfilePackage.buildSection(
        <String, Object?>{
          'engines/metadata.json': <String, Object?>{
            'data': base64Encode(
              utf8.encode(
                '{"version":"1.0",'
                '"updatedAt":"2026-09-02T00:00:00Z","engines":{}}',
              ),
            ),
          },
        },
      );
      final legacyProfile =
          Map<String, dynamic>.from(local.package.profiles.single)
            ..['backupId'] = 'profile-backup'
            ..['filesSection'] = 'profile-backup-files';
      final legacyPackage = PortableProfilePackage(
        mode: 'deviceGraph',
        createdAt: DateTime.utc(2026, 9, 1),
        profiles: <Map<String, dynamic>>[legacyProfile],
        resources: const <Map<String, dynamic>>[],
        sections: <String, dynamic>{'profile-backup-files': fileSection},
        omissions: local.package.omissions,
      );
      snapshot = WebDavSyncActiveGraphSnapshot(
        binding: snapshot.binding,
        namespace: snapshot.namespace,
        root: snapshot.root,
        markerBytes: snapshot.markerBytes,
        serverNowMs: snapshot.serverNowMs,
        manifests: snapshot.manifests,
        latestGraph: WebDavSyncDiscoveredGraph(
          manifest: snapshot.latestGraph!.manifest,
          document: OpenedWebDavSyncGraph(
            kind: WebDavSyncGraphKind.graph,
            package: legacyPackage,
            semanticDigest: _remoteDigest,
          ),
        ),
        schemaRatchet: snapshot.schemaRatchet,
      );
      discovery = _FakeDiscovery(snapshot, events);
      publisher = _FakePublisher(states, snapshot, events);

      final report = await tier().maintain(
        authorization: authorization,
        force: true,
      );

      expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
      expect(report.change, isNull);
      expect(states.state.pendingGraphDigest, isNull);
      expect(events, <String>['scan', 'publish']);
    },
  );

  test('a persisted newer graph schema stays update-required', () async {
    states.state = states.state.copyWith(
      schemaRatchet: WebDavSyncGraphBuilder.schemaVersion + 1,
      lastGraphCheckMs: DateTime.utc(2026, 9, 2).millisecondsSinceEpoch,
    );

    final report = await tier().maintain(authorization: authorization);

    expect(report.disposition, WebDavSyncGraphTierDisposition.updateRequired);
    expect(events, isEmpty);
  });

  test('declined graph digest is durable and clears the prompt', () async {
    await states.update(
      binding.namespaceId,
      (current) => current.copyWith(pendingGraphDigest: _remoteDigest),
    );

    await tier().decline(_remoteDigest);

    expect(states.state.pendingGraphDigest, isNull);
    expect(states.state.declinedGraphDigests, contains(_remoteDigest));
  });

  test('declining a graph cannot overflow durable engine state', () async {
    await states.update(
      binding.namespaceId,
      (current) => current.copyWith(
        pendingGraphDigest: _remoteDigest,
        declinedGraphDigests: <String>{
          for (var index = 0; index < WebDavSyncLimits.maxMapEntries; index++)
            index.toRadixString(16).padLeft(64, '0'),
        },
      ),
    );

    await tier().decline(_remoteDigest);

    expect(
      states.state.declinedGraphDigests,
      hasLength(WebDavSyncLimits.maxMapEntries),
    );
    expect(states.state.declinedGraphDigests, contains(_remoteDigest));
    expect(states.state.pendingGraphDigest, isNull);
  });

  test('accepted graph adopts, republishes, and merges in order', () async {
    await states.update(
      binding.namespaceId,
      (current) => current.copyWith(pendingGraphDigest: _remoteDigest),
    );

    await tier().applyRemote(
      expectedDigest: _remoteDigest,
      authorization: authorization,
      recaptureAuthorization: () async => authorization,
    );

    expect(events, <String>['scan', 'adopt', 'publish', 'merge']);
    expect(states.state.pendingGraphDigest, isNull);
    expect(states.state.appliedGraphDigest, _remoteDigest);
  });

  test(
    'accepted graph retry resumes after adoption without importing twice',
    () async {
      await states.update(
        binding.namespaceId,
        (current) => current.copyWith(
          appliedGraphDigest: _remoteDigest,
          pendingGraphDigest: _remoteDigest,
        ),
      );

      await tier().applyRemote(
        expectedDigest: _remoteDigest,
        authorization: authorization,
        recaptureAuthorization: () async => authorization,
      );

      expect(events, <String>['scan', 'publish', 'merge']);
      expect(events, isNot(contains('adopt')));
      expect(states.state.pendingGraphDigest, isNull);
    },
  );

  test(
    'maintenance republishes an applied graph missing from own manifest',
    () async {
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: states.state.circleToLocalProfiles!,
        circleToLocalResources: states.state.circleToLocalResources!,
      );
      final localGraph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: maps,
      );
      states.state = states.state.copyWith(
        appliedGraphDigest: localGraph.semanticDigest,
        lastBootstrapCheckMs: DateTime.utc(2026, 9, 2).millisecondsSinceEpoch,
      );
      snapshot = WebDavSyncActiveGraphSnapshot(
        binding: snapshot.binding,
        namespace: snapshot.namespace,
        root: snapshot.root,
        markerBytes: snapshot.markerBytes,
        serverNowMs: snapshot.serverNowMs,
        manifests: <String, WebDavSyncManifest>{
          snapshot.namespace.deviceId: states.state.ownManifest!,
        },
        latestGraph: null,
        schemaRatchet: 1,
      );
      discovery = _FakeDiscovery(snapshot, events);

      final report = await tier().maintain(
        authorization: authorization,
        force: true,
      );

      expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
      expect(events, <String>['scan', 'publish']);
    },
  );

  test('maintenance rebuilds a missing own device seed', () async {
    snapshot = WebDavSyncActiveGraphSnapshot(
      binding: snapshot.binding,
      namespace: snapshot.namespace,
      root: snapshot.root,
      markerBytes: snapshot.markerBytes,
      serverNowMs: snapshot.serverNowMs,
      manifests: const <String, WebDavSyncManifest>{},
      latestGraph: null,
      schemaRatchet: 1,
    );
    discovery = _FakeDiscovery(snapshot, events);

    final report = await tier().maintain(
      authorization: authorization,
      force: true,
      runBootstrapMaintenance: false,
    );

    expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
    expect(events, <String>['scan', 'publish']);
  });

  test(
    'interactive graph check skips a due bootstrap database snapshot',
    () async {
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: states.state.circleToLocalProfiles!,
        circleToLocalResources: states.state.circleToLocalResources!,
      );
      final localGraph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: maps,
      );
      const staleBootstrapCheckMs = 1;
      const staleDatabaseDigest =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      final own = _manifest(
        circleId: snapshot.root.document.circleId,
        deviceId: snapshot.namespace.deviceId,
        digest: localGraph.semanticDigest,
        bootstrapDigest:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      states.state = states.state.copyWith(
        ownManifest: own,
        appliedGraphDigest: localGraph.semanticDigest,
        publishedBootstrapDatabaseDigest: staleDatabaseDigest,
        lastBootstrapCheckMs: staleBootstrapCheckMs,
      );
      snapshot = WebDavSyncActiveGraphSnapshot(
        binding: snapshot.binding,
        namespace: snapshot.namespace,
        root: snapshot.root,
        markerBytes: snapshot.markerBytes,
        serverNowMs: snapshot.serverNowMs,
        manifests: <String, WebDavSyncManifest>{
          snapshot.namespace.deviceId: own,
        },
        latestGraph: null,
        schemaRatchet: 1,
      );
      discovery = _FakeDiscovery(snapshot, events);

      final report = await tier().maintain(
        authorization: authorization,
        force: true,
        runBootstrapMaintenance: false,
      );

      expect(report.disposition, WebDavSyncGraphTierDisposition.unchanged);
      expect(events, <String>['scan']);
      expect(states.state.lastBootstrapCheckMs, staleBootstrapCheckMs);
      expect(
        states.state.publishedBootstrapDatabaseDigest,
        staleDatabaseDigest,
      );
    },
  );

  test('device list keeps this device first', () async {
    final devices = await tier().listDevices();

    expect(devices, hasLength(2));
    expect(devices.first.isThisDevice, isTrue);
    expect(devices.last.deviceId, 'peer-device');
  });

  test(
    'forced bootstrap maintenance republishes a changed database digest',
    () async {
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: states.state.circleToLocalProfiles!,
        circleToLocalResources: states.state.circleToLocalResources!,
      );
      final localGraph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: maps,
      );
      final localBootstrap = await graphBuilder.build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: authorization,
        identityMaps: maps,
      );
      final own = _manifest(
        circleId: snapshot.root.document.circleId,
        deviceId: snapshot.namespace.deviceId,
        digest: localGraph.semanticDigest,
        bootstrapDigest: localBootstrap.semanticDigest,
      );
      states.state = states.state.copyWith(
        ownManifest: own,
        appliedGraphDigest: localGraph.semanticDigest,
        publishedBootstrapDatabaseDigest: 'f' * 64,
      );
      snapshot = WebDavSyncActiveGraphSnapshot(
        binding: snapshot.binding,
        namespace: snapshot.namespace,
        root: snapshot.root,
        markerBytes: snapshot.markerBytes,
        serverNowMs: snapshot.serverNowMs,
        manifests: <String, WebDavSyncManifest>{
          snapshot.namespace.deviceId: own,
        },
        latestGraph: null,
        schemaRatchet: 1,
      );
      discovery = _FakeDiscovery(snapshot, events);

      final report = await tier().maintain(
        authorization: authorization,
        force: true,
      );

      expect(report.disposition, WebDavSyncGraphTierDisposition.localPublished);
      expect(events, <String>['scan', 'publish']);
    },
  );

  test(
    'unchanged daily bootstrap check records cadence without uploading',
    () async {
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: states.state.circleToLocalProfiles!,
        circleToLocalResources: states.state.circleToLocalResources!,
      );
      final localGraph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: maps,
      );
      final localBootstrap = await graphBuilder.build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: authorization,
        identityMaps: maps,
      );
      final databaseDigest = WebDavSyncGraphBuilder.bootstrapDatabaseDigest(
        localBootstrap.package,
      );
      expect(localBootstrap.bootstrapDatabaseDigest, databaseDigest);
      final own = _manifest(
        circleId: snapshot.root.document.circleId,
        deviceId: snapshot.namespace.deviceId,
        digest: localGraph.semanticDigest,
        bootstrapDigest: localBootstrap.semanticDigest,
      );
      states.state = states.state.copyWith(
        ownManifest: own,
        appliedGraphDigest: localGraph.semanticDigest,
        publishedBootstrapDatabaseDigest: databaseDigest,
      );
      snapshot = WebDavSyncActiveGraphSnapshot(
        binding: snapshot.binding,
        namespace: snapshot.namespace,
        root: snapshot.root,
        markerBytes: snapshot.markerBytes,
        serverNowMs: snapshot.serverNowMs,
        manifests: <String, WebDavSyncManifest>{
          snapshot.namespace.deviceId: own,
        },
        latestGraph: null,
        schemaRatchet: 1,
      );
      discovery = _FakeDiscovery(snapshot, events);

      final report = await tier().maintain(
        authorization: authorization,
        force: true,
      );

      expect(report.disposition, WebDavSyncGraphTierDisposition.unchanged);
      expect(events, <String>['scan']);
      expect(
        states.state.lastBootstrapCheckMs,
        DateTime.utc(2026, 9, 2).millisecondsSinceEpoch,
      );
    },
  );

  test('pending profile cleanup blocks all graph publication', () async {
    states.state = states.state.copyWith(
      prunePendingProfileIds: const <String>{'old-profile'},
    );

    final report = await tier().maintain(
      authorization: authorization,
      force: true,
    );

    expect(report.disposition, WebDavSyncGraphTierDisposition.skipped);
    expect(report.change, isNull);
    expect(states.state.pendingGraphDigest, isNull);
    expect(events, <String>['retry-prunes']);
  });

  test(
    'forget device verifies tombstones and bootstrap continuity before delete',
    () async {
      final maps = WebDavSyncIdentityMaps(
        circleToLocalProfiles: states.state.circleToLocalProfiles!,
        circleToLocalResources: states.state.circleToLocalResources!,
      );
      final bootstrap = await graphBuilder.build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: authorization,
        identityMaps: maps,
      );
      final graph = await graphBuilder.build(
        kind: WebDavSyncGraphKind.graph,
        authorization: authorization,
        identityMaps: maps,
      );
      var nonce = 80;
      final codec = WebDavSyncCodec(
        randomBytes: (length) => Uint8List.fromList(
          List<int>.generate(length, (_) => nonce++ & 0xff),
        ),
      );
      Future<({WebDavSyncSectionReference reference, Uint8List bytes})> seal(
        WebDavSyncPreparedGraph prepared,
      ) async {
        final bytes = await codec.sealDocument(
          key: snapshot.root.key,
          circleId: snapshot.root.document.circleId,
          deviceId: snapshot.namespace.deviceId,
          logicalName: prepared.kind.logicalName,
          schemaVersion: WebDavSyncGraphBuilder.schemaVersion,
          payload: prepared.payload,
          maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
        );
        return (
          reference: WebDavSyncSectionReference(
            name: prepared.kind.logicalName,
            contentHash: contentHashOf(bytes),
            semanticDigest: prepared.semanticDigest,
            updatedAtMs: snapshot.serverNowMs,
            schemaVersion: WebDavSyncGraphBuilder.schemaVersion,
            size: bytes.length,
          ),
          bytes: bytes,
        );
      }

      final sealedBootstrap = await seal(bootstrap);
      final sealedGraph = await seal(graph);
      final ownManifest = WebDavSyncManifest(
        circleId: snapshot.root.document.circleId,
        deviceId: snapshot.namespace.deviceId,
        updatedAtMs: snapshot.serverNowMs,
        clockOffsetMs: 0,
        graphSchemaClaim: 1,
        profileMap: graph.profileMap,
        resourceMap: graph.resourceMap,
        sections: <WebDavSyncSectionReference>[
          sealedBootstrap.reference,
          sealedGraph.reference,
        ],
      );
      final targetManifest = _manifest(
        circleId: snapshot.root.document.circleId,
        deviceId: 'peer-device',
        digest: _remoteDigest,
      );
      final targetManifestBytes = await codec.sealDocument(
        key: snapshot.root.key,
        circleId: snapshot.root.document.circleId,
        deviceId: 'peer-device',
        logicalName: 'manifest',
        schemaVersion: WebDavSyncManifest.schemaVersion,
        payload: targetManifest.toJson(),
        maxBytes: WebDavSyncLimits.maxManifestBytes,
      );
      states.state = states.state.copyWith(
        ownManifest: ownManifest,
        appliedGraphDigest: graph.semanticDigest,
      );
      snapshot = WebDavSyncActiveGraphSnapshot(
        binding: snapshot.binding,
        namespace: snapshot.namespace,
        root: snapshot.root,
        markerBytes: snapshot.markerBytes,
        serverNowMs: snapshot.serverNowMs,
        manifests: <String, WebDavSyncManifest>{
          snapshot.namespace.deviceId: ownManifest,
          'peer-device': targetManifest,
        },
        latestGraph: WebDavSyncDiscoveredGraph(
          manifest: ownManifest,
          document: OpenedWebDavSyncGraph(
            kind: WebDavSyncGraphKind.graph,
            package: graph.package,
            semanticDigest: graph.semanticDigest,
          ),
        ),
        schemaRatchet: 1,
      );
      discovery = _FakeDiscovery(snapshot, events);
      final transport = _FakeForgetTransport(
        marker: snapshot.markerBytes,
        serverDate: DateTime.utc(2026, 9, 2),
        events: events,
        manifests: <String, Uint8List>{'peer-device': targetManifestBytes},
        sections: <String, Uint8List>{
          '${snapshot.namespace.deviceId}:${sealedBootstrap.reference.contentHash}':
              sealedBootstrap.bytes,
          '${snapshot.namespace.deviceId}:${sealedGraph.reference.contentHash}':
              sealedGraph.bytes,
        },
      );
      final context = WebDavSyncCycleContext(
        namespaceId: snapshot.namespace.id,
        deviceId: snapshot.namespace.deviceId,
        markerPin: snapshot.markerBytes,
        root: snapshot.root,
        circleToLocalProfiles: maps.circleToLocalProfiles,
        circleToLocalResources: maps.circleToLocalResources,
        wireProfileMap: ownManifest.profileMap,
        wireResourceMap: ownManifest.resourceMap,
        active: true,
      );

      await tier(
        contextProvider: () async => context,
        transportFactory: ({required binding, required secrets}) => transport,
      ).forgetDevice(deviceId: 'peer-device', authorization: authorization);

      expect(events, <String>[
        'merge',
        'scan',
        'read:bootstrap',
        'read:graph',
        'read:root',
        'read:manifest:peer-device',
        'delete:peer-device',
        'close',
      ]);
      expect(transport.deletedDeviceId, 'peer-device');
    },
  );

  test('forget device publishes continuity before refusing deletion', () async {
    snapshot = WebDavSyncActiveGraphSnapshot(
      binding: snapshot.binding,
      namespace: snapshot.namespace,
      root: snapshot.root,
      markerBytes: snapshot.markerBytes,
      serverNowMs: snapshot.serverNowMs,
      manifests: snapshot.manifests,
      latestGraph: null,
      schemaRatchet: snapshot.schemaRatchet,
    );
    discovery = _FakeDiscovery(snapshot, events);
    final context = WebDavSyncCycleContext(
      namespaceId: snapshot.namespace.id,
      deviceId: snapshot.namespace.deviceId,
      markerPin: snapshot.markerBytes,
      root: snapshot.root,
      circleToLocalProfiles: states.state.circleToLocalProfiles,
      circleToLocalResources: states.state.circleToLocalResources,
      wireProfileMap: states.state.ownManifest!.profileMap,
      wireResourceMap: states.state.ownManifest!.resourceMap,
      active: true,
    );

    await expectLater(
      tier(
        contextProvider: () async => context,
      ).forgetDevice(deviceId: 'peer-device', authorization: authorization),
      throwsStateError,
    );

    expect(events, <String>['merge', 'scan', 'publish', 'scan']);
  });

  test('forget device cannot discard its unapplied winning graph', () async {
    final context = WebDavSyncCycleContext(
      namespaceId: snapshot.namespace.id,
      deviceId: snapshot.namespace.deviceId,
      markerPin: snapshot.markerBytes,
      root: snapshot.root,
      circleToLocalProfiles: states.state.circleToLocalProfiles,
      circleToLocalResources: states.state.circleToLocalResources,
      wireProfileMap: states.state.ownManifest!.profileMap,
      wireResourceMap: states.state.ownManifest!.resourceMap,
      active: true,
    );

    await expectLater(
      tier(
        contextProvider: () async => context,
      ).forgetDevice(deviceId: 'peer-device', authorization: authorization),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Apply or decline'),
        ),
      ),
    );

    expect(events, <String>['merge', 'scan']);
  });
}

WebDavSyncManifest _manifest({
  required String circleId,
  required String deviceId,
  required String digest,
  String? bootstrapDigest,
}) => WebDavSyncManifest(
  circleId: circleId,
  deviceId: deviceId,
  updatedAtMs: 1,
  clockOffsetMs: 0,
  graphSchemaClaim: 1,
  profileMap: const <String, String>{'profile-backup': 'profile-circle'},
  resourceMap: const <String, String>{},
  sections: <WebDavSyncSectionReference>[
    if (bootstrapDigest != null)
      WebDavSyncSectionReference(
        name: 'bootstrap',
        contentHash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        semanticDigest: bootstrapDigest,
        updatedAtMs: 1,
        schemaVersion: 1,
        size: 1,
      ),
    WebDavSyncSectionReference(
      name: 'graph',
      contentHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      semanticDigest: digest,
      updatedAtMs: 1,
      schemaVersion: 1,
      size: 1,
    ),
  ],
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

final class _FakeDiscovery implements WebDavSyncActiveGraphDiscoverer {
  const _FakeDiscovery(this.snapshot, this.events);

  final WebDavSyncActiveGraphSnapshot snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncActiveGraphSnapshot> scanActive({
    required String bindingId,
  }) async {
    events.add('scan');
    return snapshot;
  }
}

final class _FakeAdoption implements WebDavSyncAdoptionRunner {
  const _FakeAdoption(this.states, this.events);

  final _MemoryStateRepository states;
  final List<String> events;

  @override
  Future<WebDavSyncAdoptionRecord> adopt(
    WebDavSyncAdoptionRequest request,
  ) async {
    events.add('adopt');
    await states.update(
      request.namespaceId,
      (current) => current.copyWith(
        appliedGraphDigest: request.graphSemanticDigest,
        clearPendingGraph: true,
      ),
    );
    return WebDavSyncAdoptionRecord(
      adoptionId: 'adoption-test',
      mode: request.mode,
      phase: WebDavSyncAdoptionPhase.complete,
      graphSemanticDigest: request.graphSemanticDigest,
      preRestoreProfileIds: const <String>{'profile-before'},
      backupPath: '/backup',
      backupSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      backupVerified: true,
    );
  }

  @override
  Future<WebDavSyncAdoptionRecord?> recover(String namespaceId) async => null;

  @override
  Future<Set<String>> retryPendingPrunes(String namespaceId) async {
    events.add('retry-prunes');
    return states.state.prunePendingProfileIds;
  }
}

final class _FakePublisher implements WebDavSyncSeedPublisher {
  const _FakePublisher(this.states, this.snapshot, this.events);

  final _MemoryStateRepository states;
  final WebDavSyncActiveGraphSnapshot snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncPublishedSeed> publish({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
  }) async {
    events.add('publish');
    final current = await states.load(snapshot.namespace.id);
    final manifest = _manifest(
      circleId: snapshot.root.document.circleId,
      deviceId: snapshot.namespace.deviceId,
      digest: current.appliedGraphDigest!,
    );
    await states.update(
      snapshot.namespace.id,
      (state) => state.copyWith(ownManifest: manifest),
    );
    return WebDavSyncPublishedSeed(
      material: WebDavSyncSeedMaterial(
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: current.circleToLocalProfiles!,
          circleToLocalResources: current.circleToLocalResources!,
        ),
        profileMap: manifest.profileMap,
        resourceMap: manifest.resourceMap,
        sections: const <WebDavSyncSeedSection>[],
        profileStates: const <String, WebDavSyncProfileEngineState>{},
        bootstrapDatabaseDigest:
            '5555555555555555555555555555555555555555555555555555555555555555',
        beforeRootCommit: _done,
      ),
      manifest: manifest,
      serverNowMs: 1,
    );
  }

  static Future<void> _done() async {}
}

final class _FakeCycleRunner implements WebDavSyncCycleRunner {
  const _FakeCycleRunner(this.events);

  final List<String> events;

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
  }) async {
    events.add('merge');
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
  }
}

final class _FakeForgetTransport implements WebDavSyncActivationTransport {
  _FakeForgetTransport({
    required this.marker,
    required this.serverDate,
    required this.events,
    required this.manifests,
    required this.sections,
  });

  final Uint8List marker;
  final DateTime serverDate;
  final List<String> events;
  final Map<String, Uint8List> manifests;
  final Map<String, Uint8List> sections;
  String? deletedDeviceId;

  WebDavResponseMetadata get _metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav/Family/debrify-sync'),
    headers: const <String, String>{},
    serverDate: serverDate,
  );

  @override
  Future<WebDavBytesResult> readRootMarker() async {
    events.add('read:root');
    return WebDavBytesResult(bytes: marker, metadata: _metadata);
  }

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) async {
    events.add('read:manifest:$deviceId');
    return WebDavBytesResult(bytes: manifests[deviceId]!, metadata: _metadata);
  }

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) async {
    events.add('read:${reference.name}');
    return WebDavBytesResult(
      bytes: sections['$deviceId:${reference.contentHash}']!,
      metadata: _metadata,
    );
  }

  @override
  Future<void> deleteDeviceDirectory(String deviceId) async {
    events.add('delete:$deviceId');
    deletedDeviceId = deviceId;
  }

  @override
  void close() => events.add('close');

  @override
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<void> ensureOwnLayout(String deviceId) => throw UnimplementedError();

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() => throw UnimplementedError();

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
}
