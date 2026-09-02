import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_discovery.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_existing_root_connector.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_manifest_publisher.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _bootstrapDigest =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _graphDigest =
    '2222222222222222222222222222222222222222222222222222222222222222';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ProfileAuthorizationContext authorization;
  late WebDavSyncBindingStore bindingStore;
  late WebDavSyncBinding binding;
  late WebDavSyncExistingRootSnapshot snapshot;
  late _MemoryStateRepository states;
  late List<String> events;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 7)),
    );
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'webdav-sync-connector-',
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
      circleId: 'circle-existing',
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
    final stored = await bindingStore.load();
    final namespace = stored.namespaceFor(binding)!;
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
    WebDavSyncDiscoveredGraph discovered(
      WebDavSyncGraphKind kind,
      String digest,
      String deviceId,
    ) => WebDavSyncDiscoveredGraph(
      manifest: WebDavSyncManifest(
        circleId: 'circle-existing',
        deviceId: deviceId,
        updatedAtMs: 1,
        clockOffsetMs: 0,
        graphSchemaClaim: 1,
        profileMap: const <String, String>{'profile-backup': 'profile-circle'},
        resourceMap: const <String, String>{},
        sections: const <WebDavSyncSectionReference>[],
      ),
      document: OpenedWebDavSyncGraph(
        kind: kind,
        package: package,
        semanticDigest: digest,
      ),
    );
    snapshot = WebDavSyncExistingRootSnapshot(
      binding: binding,
      namespace: namespace,
      root: root,
      markerBytes: marker,
      serverNowMs: 1,
      manifests: const <String, WebDavSyncManifest>{},
      bootstrap: discovered(
        WebDavSyncGraphKind.bootstrap,
        _bootstrapDigest,
        'device-bootstrap',
      ),
      latestGraph: discovered(
        WebDavSyncGraphKind.graph,
        _graphDigest,
        'device-graph',
      ),
      schemaRatchet: 1,
    );
    states = _MemoryStateRepository();
    events = <String>[];
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  WebDavSyncExistingRootConnector connector() {
    final adoption = _FakeAdoption(states, events);
    final publisher = _FakePublisher(states, snapshot, events);
    return WebDavSyncExistingRootConnector(
      bindingStore: bindingStore,
      stateRepository: states,
      discovery: _FakeDiscovery(snapshot, events),
      adoption: adoption,
      publisher: publisher,
      engine: _FakeEngine(events),
    );
  }

  test('first connection requires consent before discovery', () async {
    await expectLater(
      connector().connect(
        bindingId: binding.id,
        authorization: authorization,
        recaptureAuthorization: () async => authorization,
        replacementConfirmed: false,
      ),
      throwsStateError,
    );

    expect(events, isEmpty);
    expect((await bindingStore.load()).activeBindingId, isNull);
  });

  test(
    'bootstrap then graph then seed and hot merge activate in order',
    () async {
      var recaptures = 0;

      final active = await connector().connect(
        bindingId: binding.id,
        authorization: authorization,
        recaptureAuthorization: () async {
          recaptures++;
          return authorization;
        },
        replacementConfirmed: true,
      );

      expect(active.lifecycle, WebDavSyncLifecycle.active);
      expect(events, <String>[
        'discover',
        'adopt:firstJoin',
        'adopt:refresh',
        'publish',
        'merge',
      ]);
      expect(recaptures, 2);
      expect(states.state.appliedGraphDigest, _graphDigest);
      expect((await bindingStore.load()).activeBindingId, binding.id);
    },
  );

  test('retry after applied graph skips destructive adoption', () async {
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: <String, String>{
        'profile-circle': authorization.profileId,
      },
      circleToLocalResources: const <String, String>{},
      appliedGraphDigest: _graphDigest,
    );

    await connector().connect(
      bindingId: binding.id,
      authorization: authorization,
      recaptureAuthorization: () async => authorization,
      replacementConfirmed: true,
    );

    expect(events, <String>['discover', 'publish', 'merge']);
  });

  test('a saved circle cannot reuse mappings from replaced profiles', () async {
    states.state = const WebDavSyncEngineState(
      circleToLocalProfiles: <String, String>{
        'profile-circle': 'profile-from-an-earlier-circle-session',
      },
      circleToLocalResources: <String, String>{},
      appliedGraphDigest: _graphDigest,
    );
    var recaptures = 0;

    await connector().connect(
      bindingId: binding.id,
      authorization: authorization,
      recaptureAuthorization: () async {
        recaptures++;
        return authorization;
      },
      replacementConfirmed: true,
    );

    expect(events, <String>[
      'discover',
      'adopt:firstJoin',
      'adopt:refresh',
      'publish',
      'merge',
    ]);
    expect(recaptures, 2);
  });

  test('recovery recaptures authorization before later writes', () async {
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: <String, String>{
        'profile-circle': authorization.profileId,
      },
      circleToLocalResources: const <String, String>{},
      appliedGraphDigest: _graphDigest,
      adoption: _adoptionRecord(),
    );
    var recaptures = 0;

    await connector().connect(
      bindingId: binding.id,
      authorization: authorization,
      recaptureAuthorization: () async {
        recaptures++;
        return authorization;
      },
      replacementConfirmed: true,
    );

    expect(recaptures, 1);
    expect(events, <String>['recover', 'discover', 'publish', 'merge']);
  });
}

WebDavSyncAdoptionRecord _adoptionRecord() => WebDavSyncAdoptionRecord(
  adoptionId: 'adoption-recovery',
  mode: WebDavSyncAdoptionMode.refresh,
  phase: WebDavSyncAdoptionPhase.complete,
  graphSemanticDigest: _graphDigest,
  preRestoreProfileIds: const <String>{'local-before'},
  backupPath: '/backup',
  backupSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  backupVerified: true,
);

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

final class _FakeDiscovery implements WebDavSyncExistingRootDiscoverer {
  const _FakeDiscovery(this.snapshot, this.events);

  final WebDavSyncExistingRootSnapshot snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncExistingRootSnapshot> discover({
    required String bindingId,
  }) async {
    events.add('discover');
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
    events.add('adopt:${request.mode.name}');
    await states.update(
      request.namespaceId,
      (current) => current.copyWith(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{},
        appliedGraphDigest: request.graphSemanticDigest,
      ),
    );
    return WebDavSyncAdoptionRecord(
      adoptionId: 'adoption-test',
      mode: request.mode,
      phase: WebDavSyncAdoptionPhase.complete,
      graphSemanticDigest: request.graphSemanticDigest,
      preRestoreProfileIds: const <String>{'local-before'},
      backupPath: '/backup',
      backupSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      backupVerified: true,
    );
  }

  @override
  Future<WebDavSyncAdoptionRecord?> recover(String namespaceId) async {
    final record = states.state.adoption;
    if (record == null) return null;
    events.add('recover');
    await states.update(
      namespaceId,
      (current) => current.copyWith(clearAdoption: true),
    );
    return record;
  }

  @override
  Future<Set<String>> retryPendingPrunes(String namespaceId) async =>
      const <String>{};
}

final class _FakePublisher implements WebDavSyncSeedPublisher {
  const _FakePublisher(this.states, this.snapshot, this.events);

  final _MemoryStateRepository states;
  final WebDavSyncExistingRootSnapshot snapshot;
  final List<String> events;

  @override
  Future<WebDavSyncPublishedSeed> publish({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
  }) async {
    events.add('publish');
    final manifest = WebDavSyncManifest(
      circleId: snapshot.root.document.circleId,
      deviceId: snapshot.namespace.deviceId,
      updatedAtMs: 2,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const <String, String>{'profile-backup': 'profile-circle'},
      resourceMap: const <String, String>{},
      sections: const <WebDavSyncSectionReference>[],
    );
    final state = await states.load(snapshot.namespace.id);
    await states.update(
      snapshot.namespace.id,
      (current) => current.copyWith(ownManifest: manifest),
    );
    return WebDavSyncPublishedSeed(
      material: WebDavSyncSeedMaterial(
        identityMaps: WebDavSyncIdentityMaps(
          circleToLocalProfiles: state.circleToLocalProfiles!,
          circleToLocalResources: state.circleToLocalResources!,
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
      serverNowMs: 2,
    );
  }

  static Future<void> _done() async {}
}

final class _FakeEngine implements WebDavSyncCycleRunner {
  const _FakeEngine(this.events);

  final List<String> events;

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
  }) async {
    expect(allowPreActivation, isTrue);
    expect(context?.active, isFalse);
    events.add('merge');
    return const WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.completed,
    );
  }
}
