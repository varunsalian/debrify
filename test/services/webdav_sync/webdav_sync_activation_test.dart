import 'connector_test_fakes.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_discovery.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_existing_root_connector.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'dart:async';
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
  late Directory supportDirectory;
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
    supportDirectory = Directory(p.join(temporaryDirectory.path, 'support'));
    final cache = Directory(p.join(temporaryDirectory.path, 'cache'));
    await documents.create(recursive: true);
    await supportDirectory.create(recursive: true);
    await cache.create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: supportDirectory,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(supportDirectory.path, 'profiles.db'),
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

  WebDavSyncNewRootInitializer initializer({
    void Function(String, Object?)? diagnostic,
  }) => WebDavSyncNewRootInitializer(
    bindingStore: bindingStore,
    stateRepository: states,
    seedSource: seeds,
    transportFactory: ({required binding, required secrets}) => transport,
    clock: () => DateTime.utc(2026, 9, 1),
    diagnostic: diagnostic,
  );

  test('non-linearizable store failure aborts before root mutation', () async {
    transport.linearizabilityProbeError =
        const WebDavSyncStoreNotLinearizableException();

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<WebDavSyncStoreNotLinearizableException>()),
    );

    expect(transport.linearizabilityProbeCalls, 1);
    expect(transport.events, isNot(contains('read:root')));
    expect(transport.events, isNot(contains('create:root')));
    expect(transport.marker, isNull);
    expect((await bindingStore.load()).activeBinding, isNull);
  });

  test(
    'inconclusive linearizability probe aborts before authority writes',
    () async {
      transport.linearizabilityProbeError =
          const WebDavSyncSetupInconclusiveException(
            probeStep: 2,
            exceptionKind: WebDavErrorKind.timeout,
          );

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavSyncSetupInconclusiveException>()),
      );

      expect(transport.linearizabilityProbeCalls, 1);
      expect(transport.events, isNot(contains('read:root')));
      expect(transport.events, isNot(contains('create:root')));
      expect(transport.marker, isNull);
      expect((await bindingStore.load()).activeBinding, isNull);
    },
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
        <String>[
          'read:section:bootstrap',
          'read:section:profiles',
          'read:section:resources',
        ],
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

  test('a different valid authority on create read-back is adopted', () async {
    final winnerMarker = await WebDavSyncCodec().sealRoot(
      passphrase: 'winner-secret',
      circleId: 'winner-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 64,
      iterations: 1,
    );
    final winnerAuthority = WebDavSyncAuthorityFile(
      markerBytes: winnerMarker,
      syncPassphrase: 'winner-secret',
    ).encode();
    transport.replaceMarkerAfterCreate = winnerAuthority;

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncConcurrentRoot>());
    final stored = await bindingStore.load();
    final adopted = stored.bindings[binding.id]!;
    expect(adopted.circleId, 'winner-circle');
    expect(adopted.lifecycle, WebDavSyncLifecycle.awaitingAdoption);
    expect(
      (await bindingStore.readSecrets(adopted)).syncPassphrase,
      'winner-secret',
    );
    expect(
      stored.namespaceFor(adopted)!.markerBytes,
      orderedEquals(winnerMarker),
    );
  });
  test(
    'ambiguous MKCOL 405 with a missing root collection fails closed',
    () async {
      transport.activationLayoutExists = false;

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavSyncAuthorityClaimException>()),
      );

      expect(transport.marker, isNull);
      expect((await bindingStore.load()).activeBinding, isNull);
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

  for (final republish in [false, true]) {
    test(
      'local edits remain pending during ${republish ? 'republish' : 'initial seed'} manifest I/O',
      () async {
        if (republish) {
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
          transport.marker = marker;
          states.state = WebDavSyncEngineState(
            circleToLocalProfiles: seeds.maps.circleToLocalProfiles,
            circleToLocalResources: seeds.maps.circleToLocalResources,
          );
        }
        final prefs = await ProfilePreferences.instance();
        await prefs.setString('theme', 'old');
        seeds.guardPreferences = true;
        final baseline = WebDavSyncHotMerge.build(
          WebDavSyncBuildInput(
            circleProfileId: 'profile-circle',
            deviceId: 'device-a',
            rawPreferences: const {'theme': 'old'},
            portablePreferences: const {'theme': 'old'},
            identityMaps: seeds.maps,
            localNowMs: 1000,
            clockOffsetMs: 0,
            serverNowMs: 1000,
          ),
        ).document;
        seeds.profileStates = {
          'profile-circle': WebDavSyncProfileEngineState(baseline: baseline),
        };
        final started = Completer<void>();
        final release = Completer<void>();
        transport.beforeManifestWrite = () async {
          started.complete();
          await release.future;
        };
        final publisher = WebDavSyncOwnManifestPublisher(
          bindingStore: bindingStore,
          stateRepository: states,
          seedSource: seeds,
          transportFactory: ({required binding, required secrets}) => transport,
          clock: () => DateTime.utc(2026, 9, 1),
        );
        final operation = republish
            ? publisher.publish(
                bindingId: binding.id,
                authorization: authorization,
              )
            : initializer().initialize(
                bindingId: binding.id,
                authorization: authorization,
              );
        await started.future.timeout(const Duration(seconds: 5));
        const tombstone = WebDavSyncTombstone(
          key: 'completion/movie/dHQx',
          stamp: WebDavSyncStamp(
            normalizedTimeMs: 2000,
            originDeviceId: 'device-a',
          ),
        );
        try {
          // A real UI write in the caller's zone must finish while HTTP is pending.
          await prefs
              .setString('theme', 'new')
              .timeout(const Duration(seconds: 1));
          states.state = states.state.copyWith(
            profiles: {
              'profile-circle': WebDavSyncProfileEngineState(
                tombstones: {tombstone.key: tombstone},
              ),
            },
          );
        } finally {
          release.complete();
          await operation;
        }
        expect(prefs.getString('theme'), 'new');
        final saved = states.state.profiles['profile-circle']!;
        expect(saved.baseline!.scalars.values['theme'], 'old');
        expect(saved.tombstones[tombstone.key], tombstone);
        final next = WebDavSyncHotMerge.build(
          WebDavSyncBuildInput(
            circleProfileId: 'profile-circle',
            deviceId: 'device-a',
            rawPreferences: {'theme': prefs.getString('theme')},
            portablePreferences: {'theme': prefs.getString('theme')},
            identityMaps: seeds.maps,
            localNowMs: 3000,
            clockOffsetMs: 0,
            serverNowMs: 3000,
            previous: saved.baseline,
          ),
        ).document;
        expect(next.scalars.values['theme'], 'new');
        expect(next.semanticDigest, isNot(saved.baseline!.semanticDigest));
        expect(states.state.ownManifest, isNotNull);
      },
    );
  }

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
      final persistedCandidate = Uint8List.fromList(
        base64Decode(
          interruptedNamespace.values[WebDavSyncBindingStore
                  .seedCandidateMarkerValueKey]
              as String,
        ),
      );
      expect(
        () => WebDavSyncAuthorityFile.parse(persistedCandidate),
        throwsA(isA<WebDavSyncAuthorityFileException>()),
      );
      expect(
        (await WebDavSyncCodec().openRoot(
          persistedCandidate,
          'circle-secret',
        )).document.circleId,
        isNotEmpty,
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

  test('lost create response converges through marker read-back', () async {
    transport.createStoresThenThrows = true;

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncInitialized>());
    expect(
      transport.events.where((event) => event == 'create:root'),
      hasLength(1),
    );
    final completed = await bindingStore.load();
    final completedBinding = completed.bindings[binding.id]!;
    final completedNamespace = completed.namespaceFor(completedBinding)!;
    expect(
      completedNamespace.markerBytes,
      webDavSyncInnerMarker(transport.marker!),
    );
    expect(
      completedNamespace.values,
      isNot(contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey)),
    );
    expect(completedBinding.lifecycle, WebDavSyncLifecycle.active);
  });

  test(
    'a concurrent winner is pinned and enters adoption, not Active',
    () async {
      final codec = WebDavSyncCodec();
      final winningMarker = await codec.sealRoot(
        passphrase: 'circle-secret',
        circleId: 'winning-circle',
        createdAt: DateTime.utc(2026, 8, 31),
        memoryKiB: 64,
        iterations: 1,
      );
      transport.marker = WebDavSyncAuthorityFile(
        markerBytes: winningMarker,
        syncPassphrase: 'circle-secret',
      ).encode();

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
    transport.markerOnCreateError = WebDavSyncAuthorityFile(
      markerBytes: winningMarker,
      syncPassphrase: 'circle-secret',
    ).encode();
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
      markerBytes: WebDavSyncAuthorityFile(
        markerBytes: marker,
        syncPassphrase: 'circle-secret',
      ).encode(),
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
      markerBytes: WebDavSyncAuthorityFile(
        markerBytes: winningMarker,
        syncPassphrase: 'circle-secret',
      ).encode(),
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

  test('Koofr-style overwrite semantics pass the authority flow', () async {
    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncInitialized>());
    expect(transport.linearizabilityProbeCalls, 1);
    final authority = WebDavSyncAuthorityFile.parse(transport.marker!);
    expect(authority.syncPassphrase, 'circle-secret');
    expect((await bindingStore.load()).activeBindingId, binding.id);
  });

  test('two LWW initializers converge on the one standing authority', () async {
    final server = _IgnoringPreconditionsServer();
    final firstSecret = WebDavSyncCodec.generateSyncSecret();
    final secondSecret = WebDavSyncCodec.generateSyncSecret();
    expect(firstSecret, isNot(secondSecret));
    SharedPreferences.setMockInitialValues(const <String, Object>{});

    final firstStore = WebDavSyncBindingStore();
    final secondStore = WebDavSyncBindingStore(
      debugStorageKey: 'webdav_sync_db_adoption_gate_v1',
    );

    final firstLocation = WebDavSyncFolderLocation(
      endpoint: 'https://first-device.test/dav',
      folderPath: 'Family',
      serverName: 'First device',
    );
    var firstBinding = await firstStore.stageBinding(
      location: firstLocation,
      config: WebDavConfig(
        id: 'first-device',
        name: 'First device',
        baseUrl: firstLocation.endpoint.toString(),
        username: 'alice',
        password: 'first-password',
      ),
      syncPassphrase: firstSecret,
    );
    firstBinding = await firstStore.markAwaitingSeedCommit(firstBinding.id);

    final secondLocation = WebDavSyncFolderLocation(
      endpoint: 'https://second-device.test/dav',
      folderPath: 'Family',
      serverName: 'Second device',
    );
    var secondBinding = await secondStore.stageBinding(
      location: secondLocation,
      config: WebDavConfig(
        id: 'second-device',
        name: 'Second device',
        baseUrl: secondLocation.endpoint.toString(),
        username: 'bob',
        password: 'second-password',
      ),
      syncPassphrase: secondSecret,
    );
    secondBinding = await secondStore.markAwaitingSeedCommit(secondBinding.id);
    var prepared = 0;
    final bothPrepared = Completer<void>();
    Future<void> holdUntilBothPrepared() async {
      prepared++;
      if (prepared == 2) bothPrepared.complete();
      await bothPrepared.future;
    }

    final firstSeeds = _FakeSeedSource()..beforeReturn = holdUntilBothPrepared;
    final secondSeeds = _FakeSeedSource()..beforeReturn = holdUntilBothPrepared;

    final first = WebDavSyncNewRootInitializer(
      bindingStore: firstStore,
      stateRepository: _MemoryStateRepository(),
      seedSource: firstSeeds,
      transportFactory: ({required binding, required secrets}) =>
          server.connect(),
      clock: () => DateTime.utc(2026, 9, 1),
    );
    final second = WebDavSyncNewRootInitializer(
      bindingStore: secondStore,
      stateRepository: _MemoryStateRepository(),
      seedSource: secondSeeds,
      transportFactory: ({required binding, required secrets}) =>
          server.connect(),
      clock: () => DateTime.utc(2026, 9, 1),
    );

    Future<Object> settle(
      Future<WebDavSyncInitializationOutcome> operation,
    ) async {
      try {
        return await operation;
      } catch (error) {
        return error;
      }
    }

    final results =
        await Future.wait(<Future<Object>>[
          settle(
            first.initialize(
              bindingId: firstBinding.id,
              authorization: authorization,
            ),
          ),
          settle(
            second.initialize(
              bindingId: secondBinding.id,
              authorization: authorization,
            ),
          ),
        ]).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'race stalled: probes=${server.probeCalls}, prepared=$prepared, '
            'writes=${server.markerCreateCalls}',
          ),
        );

    expect(server.probeCalls, 2);
    expect(server.markerCreateCalls, 2);
    final standing = WebDavSyncAuthorityFile.parse(server.marker!);
    expect(results.whereType<WebDavSyncInitialized>(), hasLength(1));
    expect(results.whereType<WebDavSyncConcurrentRoot>(), hasLength(1));
    final firstFinal = (await firstStore.load()).bindings[firstBinding.id]!;
    final secondFinal = (await secondStore.load()).bindings[secondBinding.id]!;
    expect(firstFinal.circleId, secondFinal.circleId);
    expect(firstFinal.circleId, isNotNull);
    expect(
      (await firstStore.readSecrets(firstFinal)).syncPassphrase,
      standing.syncPassphrase,
    );
    expect(
      (await secondStore.readSecrets(secondFinal)).syncPassphrase,
      standing.syncPassphrase,
    );
    // Follow the losing initializer through the same connector pin gate as a
    // fresh join, using the standing full authority and its persisted inner pin.
    final loserStore = results.first is WebDavSyncConcurrentRoot
        ? firstStore
        : secondStore;
    final loser = results.first is WebDavSyncConcurrentRoot
        ? firstFinal
        : secondFinal;
    final namespace = (await loserStore.load()).namespaceFor(loser)!;
    expect(namespace.markerBytes, orderedEquals(standing.markerBytes));
    expect(namespace.matchesAuthority(server.marker!), isTrue);
    final root = await WebDavSyncCodec().openRoot(
      standing.markerBytes,
      standing.syncPassphrase,
      runInBackground: false,
    );
    final manifest = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: 'bootstrap-device',
      updatedAtMs: 1,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const {},
      resourceMap: const {},
      sections: const [],
    );
    final joinSnapshot = WebDavSyncExistingRootSnapshot(
      binding: loser,
      namespace: namespace,
      root: root,
      markerBytes: server.marker!,
      serverNowMs: 1,
      manifests: const {},
      schemaRatchet: 1,
      bootstrap: WebDavSyncDiscoveredGraph(
        manifest: manifest,
        document: OpenedWebDavSyncGraph(
          kind: WebDavSyncGraphKind.bootstrap,
          semanticDigest:
              '1111111111111111111111111111111111111111111111111111111111111111',
          package: PortableProfilePackage(
            mode: 'deviceGraph',
            createdAt: DateTime.utc(2026, 9, 1),
            profiles: const [],
            resources: const [],
            sections: const {},
            omissions: const {},
          ),
        ),
      ),
    );
    final joinStates = ConnectorMemoryStateRepository();
    final joinEvents = <String>[];
    final runner = ConnectorPinCheckingEngine(loserStore, joinEvents);
    final connector = WebDavSyncExistingRootConnector(
      bindingStore: loserStore,
      stateRepository: joinStates,
      discovery: ConnectorFakeDiscovery(joinSnapshot, joinEvents),
      adoption: ConnectorFakeAdoption(joinStates, joinEvents),
      publisher: ConnectorFakePublisher(joinStates, joinSnapshot, joinEvents),
      engine: runner,
    );
    final active = await connector.connect(
      bindingId: loser.id,
      authorization: authorization,
      recaptureAuthorization: () async => authorization,
      replacementConfirmed: true,
    );
    expect(runner.runCalls, 1);
    expect(active.lifecycle, WebDavSyncLifecycle.active);
    expect((await loserStore.load()).activeBindingId, loser.id);
  });

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
  Map<String, WebDavSyncProfileEngineState> profileStates = {};
  String? omittedSection;
  String? seenCircleId;
  WebDavSyncCircleKey? seenCircleKey;
  int prepareCalls = 0;
  Future<void> Function()? beforeReturn;

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
    prepareCalls++;
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
      profileStates: profileStates,
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

    final result = await (guardPreferences
        ? ProfilePreferences.captureMutationSnapshot(build)
        : build(null));
    await beforeReturn?.call();
    return result;
  }
}

class _FakeActivationTransport implements WebDavSyncActivationTransport {
  final List<String> events = <String>[];
  final Map<String, Uint8List> sections = <String, Uint8List>{};
  Uint8List? manifest;
  Uint8List? marker;
  int markerReadCount = 0;
  final Map<int, Uint8List> markerOnRead = <int, Uint8List>{};
  bool activationLayoutExists = true;
  WebDavException? createError;
  int markerCreateStatus = 201;
  WebDavException? manifestWriteError;
  Uint8List? replaceMarkerAfterCreate;
  Uint8List? markerOnCreateError;
  bool createStoresThenThrows = false;
  List<String> deviceIds = const <String>[];
  Future<void> Function()? afterSectionWrite;
  Future<void> Function()? beforeManifestWrite;
  Object? linearizabilityProbeError;
  int linearizabilityProbeCalls = 0;

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
  Future<void> ensureActivationLayout() async {
    events.add('ensure:activation');
    if (!activationLayoutExists) {
      throw const WebDavSyncAuthorityClaimException();
    }
  }

  @override
  Future<void> verifyLinearizability({
    required String syncRootPath,
    Future<void> Function()? beforeSend,
  }) async {
    linearizabilityProbeCalls++;
    events.add('probe:linearizable');
    if (linearizabilityProbeError case final failure?) throw failure;
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
    await beforeManifestWrite?.call();
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
    markerReadCount++;
    if (markerOnRead.remove(markerReadCount) case final replacement?) {
      marker = Uint8List.fromList(replacement);
    }
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
      statusCode: markerCreateStatus,
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

final class _IgnoringPreconditionsServer {
  Uint8List? marker;
  int probeCalls = 0;
  int markerCreateCalls = 0;
  final Completer<void> _bothMarkerCreates = Completer<void>();
  final List<Uint8List> _pendingAuthorities = <Uint8List>[];

  _IgnoringPreconditionsTransport connect() =>
      _IgnoringPreconditionsTransport(this);

  Future<WebDavBytesResult> readMarker(WebDavResponseMetadata metadata) async {
    final existing = marker;
    if (existing != null) {
      return WebDavBytesResult(bytes: existing, metadata: metadata);
    }
    throw const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
  }

  Future<void> createMarker(Uint8List bytes) async {
    markerCreateCalls++;
    // Deliberately ignore If-None-Match and overwrite the shared resource.
    _pendingAuthorities.add(Uint8List.fromList(bytes));
    if (markerCreateCalls == 2) {
      marker = Uint8List.fromList(_pendingAuthorities.last);
      _bothMarkerCreates.complete();
    }
    await _bothMarkerCreates.future;
  }
}

final class _IgnoringPreconditionsTransport extends _FakeActivationTransport {
  _IgnoringPreconditionsTransport(this.server) : super();

  final _IgnoringPreconditionsServer server;

  @override
  Future<void> verifyLinearizability({
    required String syncRootPath,
    Future<void> Function()? beforeSend,
  }) async {
    server.probeCalls++;
    events.add('probe:linearizable');
  }

  @override
  Future<WebDavBytesResult> readRootMarker() async {
    events.add('read:root');
    return server.readMarker(metadata);
  }

  @override
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes) async {
    events.add('create:root');
    await server.createMarker(bytes);
    return WebDavResponseMetadata(
      statusCode: 201,
      uri: metadata.uri,
      headers: const <String, String>{},
      serverDate: metadata.serverDate,
    );
  }
}
