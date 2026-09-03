import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_activation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
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

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ProfileAuthorizationContext authorization;
  late WebDavSyncBindingStore bindingStore;
  late WebDavSyncBinding binding;
  late _MemoryStateRepository states;
  late _FakeSeedSource seeds;
  late _FakeActivationTransport transport;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    ProfilePreferences.debugResetMutationTracking();
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 9)),
    );
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'webdav-sync-activation-',
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
    var random = 0;
    bindingStore = WebDavSyncBindingStore(
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => random++ & 0xff),
      ),
    );
    final location = WebDavSyncFolderLocation(
      endpoint: 'https://example.test/dav',
      folderPath: 'Family',
      serverName: 'Server',
    );
    binding = await bindingStore.stageBinding(
      location: location,
      config: const WebDavConfig(
        id: 'server',
        name: 'Server',
        baseUrl: 'https://example.test/dav',
        username: 'alice',
        password: 'secret',
      ),
      syncPassphrase: 'circle-secret',
    );
    binding = await bindingStore.markAwaitingSeedCommit(binding.id);
    states = _MemoryStateRepository();
    seeds = _FakeSeedSource();
    transport = _FakeActivationTransport();
    seeds.events = transport.events;
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  WebDavSyncNewRootInitializer initializer() => WebDavSyncNewRootInitializer(
    bindingStore: bindingStore,
    stateRepository: states,
    seedSource: seeds,
    transportFactory: ({required binding, required secrets}) => transport,
    clock: () => DateTime.utc(2026, 9, 1),
  );

  test(
    'publishes complete seed and manifest before creating root last',
    () async {
      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(outcome, isA<WebDavSyncInitialized>());
      final rootWrite = transport.events.indexOf('create:root');
      final manifestRead = transport.events.indexOf('read:manifest');
      final barriers = transport.events
          .asMap()
          .entries
          .where((entry) => entry.value == 'barrier')
          .map((entry) => entry.key)
          .toList(growable: false);
      expect(rootWrite, greaterThan(manifestRead));
      expect(barriers, hasLength(2));
      expect(rootWrite, greaterThan(barriers.last));
      expect(transport.events.last, 'close');
      expect(
        transport.events.where((event) => event.startsWith('write:section:')),
        hasLength(5),
      );
      expect(
        transport.events.where((event) => event.startsWith('read:section:')),
        isEmpty,
      );
      final snapshot = await bindingStore.load();
      expect(snapshot.activeBindingId, binding.id);
      expect(
        snapshot.bindings[binding.id]!.lifecycle,
        WebDavSyncLifecycle.active,
      );
      expect(
        snapshot.namespaceFor(snapshot.bindings[binding.id]!)!.markerBytes,
        isNotEmpty,
      );
      expect(states.state.ownManifest, isNotNull);
      expect(states.state.ownManifest!.sections, hasLength(5));
      expect(
        states.state.ownManifest!.sections.map((section) => section.name),
        containsAll(<String>[
          'bootstrap',
          'profiles',
          'resources',
          'hot/profile-circle',
          'tombstones/profile-circle',
        ]),
      );
      expect(states.state.ownManifest!.section('graph'), isNull);
      expect(seeds.seenCircleId, isNotNull);
      expect(seeds.seenCircleKey, isNotNull);
    },
  );

  test('activation refuses a seed missing a required circle section', () async {
    seeds.omittedSection = 'resources';

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsStateError,
    );

    expect(transport.sections, isEmpty);
    expect(transport.marker, isNull);
    expect(transport.manifest, isNull);
  });

  test('ambiguous root success never activates', () async {
    transport.createError = const WebDavException(
      kind: WebDavErrorKind.unexpectedStatus,
      message: 'ambiguous',
      statusCode: 204,
    );

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(
        isA<WebDavException>().having(
          (error) => error.statusCode,
          'status',
          204,
        ),
      ),
    );
    final snapshot = await bindingStore.load();
    expect(snapshot.activeBindingId, isNull);
    expect(
      snapshot.bindings[binding.id]!.lifecycle,
      WebDavSyncLifecycle.awaitingSeedCommit,
    );
  });

  test('a local preference mutation prevents stale root-last commit', () async {
    seeds.guardPreferences = true;
    transport.afterSectionWrite = () async {
      final preferences = await ProfilePreferences.instance();
      await preferences.setString('theme', 'changed-during-seed-upload');
    };

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<ProfilePreferenceMutationConflict>()),
    );

    expect(transport.manifest, isNull);
    expect(transport.marker, isNull);
    expect(states.state.ownManifest, isNull);
    expect(
      (await bindingStore.load()).bindings[binding.id]!.lifecycle,
      WebDavSyncLifecycle.awaitingSeedCommit,
    );
  });

  test(
    'seed state commit carries only tombstones changed during publication',
    () {
      const key = 'completion/movie/dHQx';
      const original = WebDavSyncTombstone(
        key: key,
        stamp: WebDavSyncStamp(
          normalizedTimeMs: 10,
          originDeviceId: 'device-a',
        ),
        rawLocalTime: true,
      );
      const concurrent = WebDavSyncTombstone(
        key: key,
        stamp: WebDavSyncStamp(
          normalizedTimeMs: 20,
          originDeviceId: 'device-a',
        ),
        rawLocalTime: true,
      );
      final material = WebDavSyncSeedMaterial(
        identityMaps: seeds.maps,
        profileMap: const <String, String>{},
        resourceMap: const <String, String>{},
        sections: const <WebDavSyncSeedSection>[],
        profileStates: const <String, WebDavSyncProfileEngineState>{
          'profile-circle': WebDavSyncProfileEngineState(),
        },
        originalProfileTombstones:
            const <String, Map<String, WebDavSyncTombstone>>{
              'profile-circle': <String, WebDavSyncTombstone>{key: original},
            },
        bootstrapDatabaseDigest: '5' * 64,
        beforeRootCommit: _done,
      );

      final unchanged = material.profileStatesForCommit(
        const <String, WebDavSyncProfileEngineState>{
          'profile-circle': WebDavSyncProfileEngineState(
            tombstones: <String, WebDavSyncTombstone>{key: original},
          ),
        },
      );
      final changed = material.profileStatesForCommit(
        const <String, WebDavSyncProfileEngineState>{
          'profile-circle': WebDavSyncProfileEngineState(
            tombstones: <String, WebDavSyncTombstone>{key: concurrent},
          ),
        },
      );

      expect(unchanged['profile-circle']!.tombstones, isEmpty);
      expect(changed['profile-circle']!.tombstones[key], concurrent);
    },
  );

  test(
    'crash before root-last leaves only accepted candidate litter',
    () async {
      final candidate = (await bindingStore.load()).namespaceFor(binding)!;
      transport.deviceIds = const <String>['existing-peer'];
      transport.manifestWriteError = const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'simulated process loss before manifest publication',
      );

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavException>()),
      );

      final interrupted = await bindingStore.load();
      final interruptedBinding = interrupted.bindings[binding.id]!;
      final interruptedNamespace = interrupted.namespaceFor(
        interruptedBinding,
      )!;
      expect(interrupted.activeBindingId, isNull);
      expect(
        interruptedBinding.lifecycle,
        WebDavSyncLifecycle.awaitingSeedCommit,
      );
      expect(interruptedNamespace.deviceId, candidate.deviceId);
      expect(
        interruptedNamespace.values,
        contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey),
      );
      expect(transport.sections, isNotEmpty);
      expect(transport.manifest, isNull);
      expect(transport.marker, isNull);
      expect(transport.events, isNot(contains('create:root')));
      expect(
        transport.events.where((event) => event.startsWith('delete:')),
        isEmpty,
        reason: 'initializers never garbage-collect another device directory',
      );
    },
  );

  test(
    'retry completes the same root after create succeeds but response fails',
    () async {
      transport.createStoresThenThrows = true;

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavException>()),
      );

      final interrupted = await bindingStore.load();
      final interruptedBinding = interrupted.bindings[binding.id]!;
      final interruptedNamespace = interrupted.namespaceFor(
        interruptedBinding,
      )!;
      final committedMarker = Uint8List.fromList(transport.marker!);
      expect(
        interruptedNamespace.values[WebDavSyncBindingStore
            .seedCandidateMarkerValueKey],
        isA<String>(),
      );
      expect(
        interruptedBinding.lifecycle,
        WebDavSyncLifecycle.awaitingSeedCommit,
      );
      expect(
        transport.events.where((event) => event == 'create:root'),
        hasLength(1),
      );

      transport.events.clear();
      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(outcome, isA<WebDavSyncInitialized>());
      expect(
        transport.events.indexOf('barrier'),
        lessThan(transport.events.indexOf('write:manifest')),
        reason: 'a committed candidate must reauthorize before retry writes',
      );
      final completed = await bindingStore.load();
      final completedBinding = completed.bindings[binding.id]!;
      final completedNamespace = completed.namespaceFor(completedBinding)!;
      expect(completedNamespace.markerBytes, committedMarker);
      expect(
        completedNamespace.values,
        isNot(contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey)),
      );
      expect(completedBinding.lifecycle, WebDavSyncLifecycle.active);
      expect(
        transport.events.where((event) => event == 'create:root'),
        isEmpty,
      );
    },
  );

  test(
    'a concurrent winner is pinned and enters adoption, not Active',
    () async {
      final codec = WebDavSyncCodec();
      transport.marker = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'winning-circle',
        createdAt: DateTime.utc(2026, 8, 31),
        memoryKiB: 64,
        iterations: 1,
      );

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(outcome, isA<WebDavSyncConcurrentRoot>());
      final snapshot = await bindingStore.load();
      final current = snapshot.bindings[binding.id]!;
      expect(current.circleId, 'winning-circle');
      expect(current.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
      expect(snapshot.activeBindingId, isNull);
      expect(
        transport.events.where((event) => event.startsWith('delete:')),
        hasLength(1),
      );
      expect(
        transport.events.indexOf('barrier'),
        lessThan(
          transport.events.indexWhere((event) => event.startsWith('delete:')),
        ),
      );
      expect(
        transport.events,
        isNot(contains('write:manifest')),
        reason: 'a concurrent root is detected before candidate publication',
      );
      expect(transport.events, isNot(contains('create:root')));
    },
  );

  test('a real 412 loser clears all candidate engine state', () async {
    final winningMarker = await WebDavSyncCodec().sealRoot(
      passphrase: 'circle-secret',
      circleId: 'winning-circle',
      createdAt: DateTime.utc(2026, 8, 31),
      memoryKiB: 64,
      iterations: 1,
    );
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: seeds.maps.circleToLocalProfiles,
      circleToLocalResources: seeds.maps.circleToLocalResources,
      profiles: const <String, WebDavSyncProfileEngineState>{
        'profile-circle': WebDavSyncProfileEngineState(),
      },
      ownManifest: _manifest(
        circleId: 'losing-circle',
        deviceId: (await bindingStore.load()).namespaceFor(binding)!.deviceId,
      ),
    );
    transport.markerOnCreateError = winningMarker;
    transport.createError = const WebDavException(
      kind: WebDavErrorKind.preconditionFailed,
      message: 'another initializer won',
      statusCode: 412,
    );

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncConcurrentRoot>());
    expect(states.state.hasAuthenticatedMaps, isFalse);
    expect(states.state.profiles, isEmpty);
    expect(states.state.ownManifest, isNull);
    final current = (await bindingStore.load()).bindings[binding.id]!;
    expect(current.circleId, 'winning-circle');
    expect(current.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
  });

  test('startup recovery finishes a root-verified seed transaction', () async {
    final codec = WebDavSyncCodec();
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'recover-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 64,
      iterations: 1,
    );
    final root = await codec.openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    final candidate = (await bindingStore.load()).namespaceFor(binding)!;
    await bindingStore.updateNamespaceValues(
      candidate.id,
      (values) => <String, Object?>{
        ...values,
        WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
          marker,
        ),
      },
    );
    binding = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: marker,
    );
    final namespace = (await bindingStore.load()).namespaceFor(binding)!;
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: seeds.maps.circleToLocalProfiles,
      circleToLocalResources: seeds.maps.circleToLocalResources,
      ownManifest: _manifest(
        circleId: root.document.circleId,
        deviceId: namespace.deviceId,
      ),
    );

    final recovered = await WebDavSyncSeedActivationRecovery(
      bindingStore: bindingStore,
      stateRepository: states,
    ).recover();

    expect(recovered, isTrue);
    final snapshot = await bindingStore.load();
    expect(snapshot.activeBindingId, binding.id);
    expect(
      snapshot.bindings[binding.id]!.lifecycle,
      WebDavSyncLifecycle.active,
    );
    expect(
      snapshot.namespaceFor(snapshot.bindings[binding.id]!)!.values,
      isNot(contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey)),
    );
  });

  test('startup recovery sends a concurrent winner through adoption', () async {
    final codec = WebDavSyncCodec();
    final candidateMarker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'losing-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 64,
      iterations: 1,
    );
    final winningMarker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'winning-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 64,
      iterations: 1,
    );
    final winningRoot = await codec.openRoot(
      winningMarker,
      'circle-secret',
      runInBackground: false,
    );
    final candidate = (await bindingStore.load()).namespaceFor(binding)!;
    await bindingStore.updateNamespaceValues(
      candidate.id,
      (values) => <String, Object?>{
        ...values,
        WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
          candidateMarker,
        ),
      },
    );
    binding = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: winningRoot.document,
      markerBytes: winningMarker,
    );

    final recovered = await WebDavSyncSeedActivationRecovery(
      bindingStore: bindingStore,
      stateRepository: states,
    ).recover();

    expect(recovered, isTrue);
    final snapshot = await bindingStore.load();
    expect(snapshot.activeBindingId, isNull);
    expect(
      snapshot.bindings[binding.id]!.lifecycle,
      WebDavSyncLifecycle.awaitingAdoption,
    );
    expect(
      snapshot.namespaceFor(snapshot.bindings[binding.id]!)!.values,
      isNot(contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey)),
    );
  });

  test('seed activation rejects an injected oversized peer listing', () async {
    transport.deviceIds = List<String>.generate(
      WebDavSyncLimits.maxPeers + 1,
      (index) => 'device-$index',
    );

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<StateError>()),
    );

    expect(transport.events, isNot(contains('write:manifest')));
    expect(transport.events, isNot(contains('create:root')));
    expect((await bindingStore.load()).activeBindingId, isNull);
  });

  test(
    'a server ignoring create-only still follows the read-back winner',
    () async {
      final winningMarker = await WebDavSyncCodec().sealRoot(
        passphrase: 'circle-secret',
        circleId: 'late-winning-circle',
        createdAt: DateTime.utc(2026, 8, 31),
        memoryKiB: 64,
        iterations: 1,
      );
      transport.replaceMarkerAfterCreate = winningMarker;

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(outcome, isA<WebDavSyncConcurrentRoot>());
      final current = (await bindingStore.load()).bindings[binding.id]!;
      expect(current.circleId, 'late-winning-circle');
      expect(current.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
      expect((await bindingStore.load()).activeBindingId, isNull);
    },
  );

  test('local mutation prevents a stale full-manifest republish', () async {
    final marker = await WebDavSyncCodec().sealRoot(
      passphrase: 'circle-secret',
      circleId: 'existing-circle',
      createdAt: DateTime.utc(2026, 8, 31),
      memoryKiB: 64,
      iterations: 1,
    );
    final root = await WebDavSyncCodec().openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    binding = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: marker,
    );
    binding = await bindingStore.setLifecycle(
      binding.id,
      WebDavSyncLifecycle.awaitingAdoption,
    );
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: seeds.maps.circleToLocalProfiles,
      circleToLocalResources: seeds.maps.circleToLocalResources,
    );
    seeds.guardPreferences = true;
    transport
      ..marker = marker
      ..afterSectionWrite = () async {
        final preferences = await ProfilePreferences.instance();
        await preferences.setString('theme', 'changed-during-seed-upload');
      };
    final publisher = WebDavSyncOwnManifestPublisher(
      bindingStore: bindingStore,
      stateRepository: states,
      seedSource: seeds,
      transportFactory: ({required binding, required secrets}) => transport,
      clock: () => DateTime.utc(2026, 9, 1),
    );

    await expectLater(
      publisher.publish(bindingId: binding.id, authorization: authorization),
      throwsA(isA<ProfilePreferenceMutationConflict>()),
    );

    expect(transport.manifest, isNull);
    expect(states.state.ownManifest, isNull);
    expect(transport.events.last, 'close');
  });

  test('adopted root publishes and verifies a complete own manifest', () async {
    final marker = await WebDavSyncCodec().sealRoot(
      passphrase: 'circle-secret',
      circleId: 'existing-circle',
      createdAt: DateTime.utc(2026, 8, 31),
      memoryKiB: 64,
      iterations: 1,
    );
    final root = await WebDavSyncCodec().openRoot(
      marker,
      'circle-secret',
      runInBackground: false,
    );
    binding = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: marker,
    );
    binding = await bindingStore.setLifecycle(
      binding.id,
      WebDavSyncLifecycle.awaitingAdoption,
    );
    states.state = WebDavSyncEngineState(
      circleToLocalProfiles: seeds.maps.circleToLocalProfiles,
      circleToLocalResources: seeds.maps.circleToLocalResources,
    );
    transport.marker = marker;
    final publisher = WebDavSyncOwnManifestPublisher(
      bindingStore: bindingStore,
      stateRepository: states,
      seedSource: seeds,
      transportFactory: ({required binding, required secrets}) => transport,
      clock: () => DateTime.utc(2026, 9, 1),
    );

    final result = await publisher.publish(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(result.manifest.sections, hasLength(5));
    expect(result.manifest.section('graph'), isNull);
    expect(seeds.seenCircleId, 'existing-circle');
    expect(seeds.seenCircleKey, isNotNull);
    expect(states.state.ownManifest, result.manifest);
    final rootReads = transport.events
        .asMap()
        .entries
        .where((entry) => entry.value == 'read:root')
        .map((entry) => entry.key)
        .toList(growable: false);
    expect(rootReads, hasLength(3));
    expect(transport.events.where((event) => event == 'barrier'), hasLength(2));
    expect(rootReads[1], lessThan(transport.events.lastIndexOf('barrier')));
    expect(
      transport.events.lastIndexOf('barrier'),
      lessThan(transport.events.indexOf('write:manifest')),
    );
    expect(transport.events.indexOf('write:manifest'), lessThan(rootReads[2]));
    expect(transport.events.last, 'close');
    expect((await bindingStore.load()).activeBindingId, isNull);
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

Future<void> _done() async {}

WebDavSyncManifest _manifest({
  required String circleId,
  required String deviceId,
}) => WebDavSyncManifest(
  circleId: circleId,
  deviceId: deviceId,
  updatedAtMs: DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
  clockOffsetMs: 0,
  graphSchemaClaim: 1,
  profileMap: const <String, String>{'profile-0': 'profile-circle'},
  resourceMap: const <String, String>{},
  sections: const <WebDavSyncSectionReference>[
    WebDavSyncSectionReference(
      name: 'bootstrap',
      contentHash:
          '1111111111111111111111111111111111111111111111111111111111111111',
      semanticDigest:
          '2222222222222222222222222222222222222222222222222222222222222222',
      updatedAtMs: 1788220800000,
      schemaVersion: 1,
      size: 1,
    ),
  ],
);

final class _FakeSeedSource implements WebDavSyncSeedSource {
  List<String>? events;
  bool guardPreferences = false;
  String? omittedSection;
  String? seenCircleId;
  WebDavSyncCircleKey? seenCircleKey;

  final maps = WebDavSyncIdentityMaps(
    circleToLocalProfiles: const <String, String>{
      'profile-circle': 'local-profile',
    },
    circleToLocalResources: const <String, String>{},
  );

  @override
  Future<WebDavSyncSeedMaterial> prepare({
    required String namespaceId,
    required String deviceId,
    required ProfileAuthorizationContext authorization,
    required int localNowMs,
    required int serverNowMs,
    required int clockOffsetMs,
    String? circleId,
    WebDavSyncCircleKey? circleKey,
  }) async {
    seenCircleId = circleId;
    seenCircleKey = circleKey;
    Future<WebDavSyncSeedMaterial> build(
      ProfilePreferenceMutationToken? mutationToken,
    ) async => WebDavSyncSeedMaterial(
      identityMaps: maps,
      profileMap: const <String, String>{'profile-0': 'profile-circle'},
      resourceMap: const <String, String>{},
      sections: List<WebDavSyncSeedSection>.unmodifiable(
        const <WebDavSyncSeedSection>[
          WebDavSyncSeedSection(
            name: 'bootstrap',
            schemaVersion: 1,
            payload: 'bootstrap-payload',
            semanticDigest:
                '1111111111111111111111111111111111111111111111111111111111111111',
            maxBytes: 1024 * 1024,
          ),
          WebDavSyncSeedSection(
            name: 'profiles',
            schemaVersion: 1,
            payload: <String, Object?>{
              'version': 1,
              'profiles': <String, Object?>{},
            },
            semanticDigest:
                '2222222222222222222222222222222222222222222222222222222222222222',
            maxBytes: 1024 * 1024,
          ),
          WebDavSyncSeedSection(
            name: 'resources',
            schemaVersion: 1,
            payload: <String, Object?>{
              'version': 1,
              'resources': <String, Object?>{},
              'grants': <String, Object?>{},
              'settings': <String, Object?>{},
              'bindings': <String, Object?>{},
            },
            semanticDigest:
                '6666666666666666666666666666666666666666666666666666666666666666',
            maxBytes: 1024 * 1024,
          ),
          WebDavSyncSeedSection(
            name: 'hot/profile-circle',
            schemaVersion: 1,
            payload: <String, Object?>{'version': 1},
            semanticDigest:
                '3333333333333333333333333333333333333333333333333333333333333333',
            maxBytes: 1024 * 1024,
          ),
          WebDavSyncSeedSection(
            name: 'tombstones/profile-circle',
            schemaVersion: 1,
            payload: <String, Object?>{'version': 1},
            semanticDigest:
                '4444444444444444444444444444444444444444444444444444444444444444',
            maxBytes: 1024 * 1024,
          ),
        ].where((section) => section.name != omittedSection),
      ),
      profileStates: const <String, WebDavSyncProfileEngineState>{},
      bootstrapDatabaseDigest:
          '5555555555555555555555555555555555555555555555555555555555555555',
      beforeRootCommit: () async => events?.add('barrier'),
      preferenceMutationToken: mutationToken,
      circleProfiles: const WebDavSyncProfilesDocument(
        profiles: <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{},
      ),
      circleResources: const WebDavSyncResourcesDocument(
        resources: <String, WebDavSyncResourceEntry>{},
        grants:
            <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{},
        settings:
            <
              String,
              Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
            >{},
        bindings:
            <
              String,
              Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
            >{},
      ),
    );

    return guardPreferences
        ? ProfilePreferences.captureMutationSnapshot(build)
        : build(null);
  }
}

final class _FakeActivationTransport implements WebDavSyncActivationTransport {
  final List<String> events = <String>[];
  final Map<String, Uint8List> sections = <String, Uint8List>{};
  Uint8List? manifest;
  Uint8List? marker;
  WebDavException? createError;
  WebDavException? manifestWriteError;
  Uint8List? replaceMarkerAfterCreate;
  Uint8List? markerOnCreateError;
  bool createStoresThenThrows = false;
  List<String> deviceIds = const <String>[];
  Future<void> Function()? afterSectionWrite;

  WebDavResponseMetadata get metadata => WebDavResponseMetadata(
    statusCode: 200,
    uri: Uri.parse('https://example.test/dav'),
    headers: const <String, String>{},
    serverDate: DateTime.utc(2026, 9, 1),
  );

  @override
  Future<void> ensureOwnLayout(String deviceId) async {
    events.add('ensure:$deviceId');
  }

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() async {
    events.add('list:devices');
    return WebDavSyncPeerListing(deviceIds: deviceIds, metadata: metadata);
  }

  @override
  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  }) async {
    events.add('write:section:$contentHash');
    sections[contentHash] = Uint8List.fromList(bytes);
    final callback = afterSectionWrite;
    if (callback != null) {
      afterSectionWrite = null;
      await callback();
    }
    return metadata;
  }

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) async {
    events.add('read:section:${reference.name}');
    return WebDavBytesResult(
      bytes: sections[reference.contentHash]!,
      metadata: metadata,
    );
  }

  @override
  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  ) async {
    events.add('write:manifest');
    final error = manifestWriteError;
    if (error != null) throw error;
    manifest = Uint8List.fromList(bytes);
    return metadata;
  }

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) async {
    events.add('read:manifest');
    return WebDavBytesResult(bytes: manifest!, metadata: metadata);
  }

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) =>
      throw UnimplementedError();

  @override
  Future<WebDavBytesResult> readRootMarker() async {
    events.add('read:root');
    final value = marker;
    if (value == null) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
    }
    return WebDavBytesResult(bytes: value, metadata: metadata);
  }

  @override
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes) async {
    events.add('create:root');
    final error = createError;
    if (error != null) {
      final winningMarker = markerOnCreateError;
      if (winningMarker != null) marker = Uint8List.fromList(winningMarker);
      throw error;
    }
    marker = Uint8List.fromList(replaceMarkerAfterCreate ?? bytes);
    if (createStoresThenThrows) {
      createStoresThenThrows = false;
      throw const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'response lost after the server stored the marker',
      );
    }
    return WebDavResponseMetadata(
      statusCode: 201,
      uri: metadata.uri,
      headers: const <String, String>{},
      serverDate: metadata.serverDate,
    );
  }

  @override
  Future<void> deleteDeviceDirectory(String deviceId) async {
    events.add('delete:$deviceId');
  }

  @override
  void close() {
    events.add('close');
  }
}
