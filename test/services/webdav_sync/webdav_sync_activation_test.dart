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

  WebDavSyncNewRootInitializer initializer() => WebDavSyncNewRootInitializer(
    bindingStore: bindingStore,
    stateRepository: states,
    seedSource: seeds,
    transportFactory: ({required binding, required secrets}) => transport,
    clock: () => DateTime.utc(2026, 9, 1),
  );

  test(
    'conditional-create probe failure aborts before root mutation',
    () async {
      transport.conditionalCreateProbeError =
          const WebDavSyncProviderUnsupportedException();

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavSyncProviderUnsupportedException>()),
      );

      expect(transport.conditionalCreateProbeCalls, 1);
      expect(transport.events, isNot(contains('read:key')));
      expect(transport.events, isNot(contains('read:root')));
      expect(transport.events, isNot(contains('create:key')));
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

  test('claims a missing keyfile and verifies its exact read-back', () async {
    transport.rootKey = null;

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncInitialized>());
    expect(transport.events, contains('create:key'));
    expect(
      transport.events.indexOf('create:key'),
      lessThan(transport.events.indexOf('create:root')),
    );
    expect(transport.keyReadCount, greaterThanOrEqualTo(2));
    expect(
      WebDavSyncRootKeyFile.parse(transport.rootKey!).syncPassphrase,
      'circle-secret',
    );
  });

  test(
    'a malformed existing keyfile fails closed before candidate use',
    () async {
      transport.rootKey = Uint8List.fromList(utf8.encode('{"version":1}'));

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavSyncRootKeyClaimException>()),
      );

      expect(transport.events, isNot(contains('create:key')));
      expect(transport.events, isNot(contains('create:root')));
    },
  );

  test('a keyfile disappearing after a 412 claim fails closed', () async {
    transport
      ..rootKey = null
      ..createKeyError = const WebDavException(
        kind: WebDavErrorKind.preconditionFailed,
        message: 'lost key claim',
      );

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<WebDavSyncRootKeyClaimException>()),
    );

    expect(transport.keyReadCount, 2);
    expect(transport.events, isNot(contains('create:root')));
  });

  test('a mismatched keyfile read-back fails closed', () async {
    transport
      ..rootKey = null
      ..replaceKeyAfterCreate = const WebDavSyncRootKeyFile(
        syncPassphrase: 'different-machine-secret',
      ).encode();

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<WebDavSyncRootKeyClaimException>()),
    );

    expect(transport.events, isNot(contains('create:root')));
  });

  test('an ambiguous keyfile create response fails closed', () async {
    transport
      ..rootKey = null
      ..createKeyError = const WebDavException(
        kind: WebDavErrorKind.unexpectedStatus,
        message: 'ambiguous create',
        statusCode: 204,
      );

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<WebDavSyncRootKeyClaimException>()),
    );

    expect(transport.events, isNot(contains('create:root')));
  });

  test(
    'a 412 key claimant adopts the winner before candidate creation',
    () async {
      final winnerKey = const WebDavSyncRootKeyFile(
        syncPassphrase: 'winning-machine-secret',
      ).encode();
      transport
        ..rootKey = null
        ..createKeyError = const WebDavException(
          kind: WebDavErrorKind.preconditionFailed,
          message: 'lost key claim',
        )
        ..keyOnCreateError = winnerKey;

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );
      final active = (outcome as WebDavSyncInitialized).binding;
      final secrets = await bindingStore.readSecrets(active);

      expect(secrets.username, 'alice');
      expect(secrets.password, 'secret');
      expect(secrets.syncPassphrase, 'winning-machine-secret');
      expect(
        await WebDavSyncCodec().openRoot(
          transport.marker!,
          'winning-machine-secret',
          runInBackground: true,
        ),
        isA<OpenedWebDavSyncRoot>(),
      );
    },
  );

  test(
    'a key overwrite during seeding is adopted before marker commit',
    () async {
      final losingDeviceId = (await bindingStore.load())
          .namespaceFor(binding)!
          .deviceId;
      final winnerSecret = 'winning-machine-secret';
      transport.rootKeyOnRead[2] = WebDavSyncRootKeyFile(
        syncPassphrase: winnerSecret,
      ).encode();

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );
      final active = (outcome as WebDavSyncInitialized).binding;

      expect(seeds.prepareCalls, 2);
      expect(transport.conditionalCreateProbeCalls, 1);
      expect(
        transport.events.where((event) => event == 'create:root'),
        hasLength(1),
      );
      expect(transport.events, contains('delete:$losingDeviceId'));
      expect(
        (await bindingStore.readSecrets(active)).syncPassphrase,
        winnerSecret,
      );
      expect(
        await WebDavSyncCodec().openRoot(
          transport.marker!,
          winnerSecret,
          runInBackground: true,
        ),
        isA<OpenedWebDavSyncRoot>(),
      );
    },
  );

  test(
    'a key overwrite at marker commit is repaired to marker authority',
    () async {
      transport.rootKeyAfterMarkerCreate = const WebDavSyncRootKeyFile(
        syncPassphrase: 'racing-machine-secret',
      ).encode();

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(outcome, isA<WebDavSyncInitialized>());
      expect(transport.overwriteKeyCalls, 1);
      expect(
        WebDavSyncRootKeyFile.parse(transport.rootKey!).syncPassphrase,
        'circle-secret',
      );
      expect(
        transport.events.indexOf('overwrite:key'),
        greaterThan(transport.events.indexOf('create:root')),
      );
    },
  );

  test(
    'entry-state divergence resumes from its marker and repairs the key',
    () async {
      final resumedMarker = await WebDavSyncCodec().sealRoot(
        passphrase: 'circle-secret',
        circleId: 'resumed-circle',
        createdAt: DateTime.utc(2026, 9, 1),
        runInBackground: true,
      );
      await bindingStore.updateNamespaceValues(
        binding.namespaceId,
        (values) => <String, Object?>{
          ...values,
          WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
            resumedMarker,
          ),
        },
      );
      transport
        ..marker = resumedMarker
        ..rootKey = const WebDavSyncRootKeyFile(
          syncPassphrase: 'delayed-claimant-secret',
        ).encode();

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(outcome, isA<WebDavSyncInitialized>());
      expect(transport.overwriteKeyCalls, 1);
      expect(
        WebDavSyncRootKeyFile.parse(transport.rootKey!).syncPassphrase,
        'circle-secret',
      );
      expect(
        transport.events.indexOf('read:root'),
        lessThan(transport.events.indexOf('read:key')),
      );
      expect(
        (await bindingStore.readSecrets(
          (await bindingStore.load()).activeBinding!,
        )).syncPassphrase,
        'circle-secret',
      );
      expect(transport.events, isNot(contains('create:root')));
    },
  );

  test('a marker-committed resume provisions its missing key', () async {
    final resumedMarker = await WebDavSyncCodec().sealRoot(
      passphrase: 'circle-secret',
      circleId: 'resumed-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      runInBackground: true,
    );
    await bindingStore.updateNamespaceValues(
      binding.namespaceId,
      (values) => <String, Object?>{
        ...values,
        WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
          resumedMarker,
        ),
      },
    );
    transport
      ..marker = resumedMarker
      ..rootKey = null;

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncInitialized>());
    expect(transport.overwriteKeyCalls, 1);
    expect(
      WebDavSyncRootKeyFile.parse(transport.rootKey!).syncPassphrase,
      'circle-secret',
    );
    expect(transport.events, isNot(contains('create:key')));
    expect(transport.events, isNot(contains('create:root')));
  });

  test('same-marker 412 repairs a key overwritten with the response', () async {
    transport
      ..createError = const WebDavException(
        kind: WebDavErrorKind.preconditionFailed,
        message: 'response says another initializer won',
        statusCode: 412,
      )
      ..rootKeyOnCreateError = const WebDavSyncRootKeyFile(
        syncPassphrase: 'delayed-claimant-secret',
      ).encode()
      ..afterSectionWrite = () async {
        final snapshot = await bindingStore.load();
        final encoded = snapshot
            .namespaceFor(snapshot.bindings[binding.id]!)!
            .values[WebDavSyncBindingStore.seedCandidateMarkerValueKey]!;
        transport.markerOnCreateError = Uint8List.fromList(
          base64Decode(encoded as String),
        );
      };

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncInitialized>());
    expect(transport.overwriteKeyCalls, 1);
    expect(
      WebDavSyncRootKeyFile.parse(transport.rootKey!).syncPassphrase,
      'circle-secret',
    );
  });

  test('key repair does not overwrite after the marker changes', () async {
    const winnerSecret = 'replacement-winner-secret';
    final winnerMarker = await WebDavSyncCodec().sealRoot(
      passphrase: winnerSecret,
      circleId: 'replacement-winner-circle',
      createdAt: DateTime.utc(2026, 9, 1),
      runInBackground: true,
    );
    transport
      ..markerOnRead[5] = winnerMarker
      ..rootKeyOnMarkerRead[5] = const WebDavSyncRootKeyFile(
        syncPassphrase: winnerSecret,
      ).encode();

    final outcome = await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    expect(outcome, isA<WebDavSyncConcurrentRoot>());
    expect(transport.overwriteKeyCalls, 0);
    expect(transport.marker, orderedEquals(winnerMarker));
    expect(
      WebDavSyncRootKeyFile.parse(transport.rootKey!).syncPassphrase,
      winnerSecret,
    );
  });

  test('post-commit key repair failure leaves a typed error binding', () async {
    transport
      ..rootKeyAfterMarkerCreate = const WebDavSyncRootKeyFile(
        syncPassphrase: 'racing-machine-secret',
      ).encode()
      ..overwriteKeyError = const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'repair failed',
      );

    await expectLater(
      initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      ),
      throwsA(isA<WebDavSyncRootKeyClaimException>()),
    );

    final failed = (await bindingStore.load()).bindings[binding.id]!;
    expect(failed.lifecycle, WebDavSyncLifecycle.error);
    expect(
      failed.errorMessage,
      const WebDavSyncRootKeyClaimException().toString(),
    );
    expect(transport.marker, isNotNull);
  });

  test(
    'key adoption discards a stale candidate and its engine state',
    () async {
      final staleMarker = await WebDavSyncCodec().sealRoot(
        passphrase: 'circle-secret',
        circleId: 'stale-circle',
        createdAt: DateTime.utc(2026, 8, 31),
        runInBackground: true,
      );
      await bindingStore.updateNamespaceValues(
        binding.namespaceId,
        (values) => <String, Object?>{
          ...values,
          WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
            staleMarker,
          ),
        },
      );
      states.state = const WebDavSyncEngineState(
        currentDeviceIds: <String>{'stale-device'},
      );
      transport.rootKey = const WebDavSyncRootKeyFile(
        syncPassphrase: 'winning-machine-secret',
      ).encode();

      await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );

      expect(transport.marker, isNot(orderedEquals(staleMarker)));
      expect(states.state.currentDeviceIds, isNot(contains('stale-device')));
      expect(
        (await bindingStore.load()).activeBinding!.lifecycle,
        WebDavSyncLifecycle.active,
      );
    },
  );

  test('resume clears stale state after a crash during key adoption', () async {
    final staleMarker = await WebDavSyncCodec().sealRoot(
      passphrase: 'circle-secret',
      circleId: 'stale-circle',
      createdAt: DateTime.utc(2026, 8, 31),
      runInBackground: true,
    );
    await bindingStore.updateNamespaceValues(
      binding.namespaceId,
      (values) => <String, Object?>{
        ...values,
        WebDavSyncBindingStore.seedCandidateMarkerValueKey: base64Encode(
          staleMarker,
        ),
      },
    );
    states.state = const WebDavSyncEngineState(
      currentDeviceIds: <String>{'stale-device'},
    );
    binding = await bindingStore.adoptSyncSecret(
      binding.id,
      'winning-machine-secret',
    );
    transport.rootKey = const WebDavSyncRootKeyFile(
      syncPassphrase: 'winning-machine-secret',
    ).encode();

    await initializer().initialize(
      bindingId: binding.id,
      authorization: authorization,
    );

    final snapshot = await bindingStore.load();
    final namespace = snapshot.namespaceFor(snapshot.activeBinding!)!;
    expect(states.state.currentDeviceIds, isNot(contains('stale-device')));
    expect(
      namespace.values,
      isNot(
        contains(WebDavSyncBindingStore.seedCandidateResetRequiredValueKey),
      ),
    );
  });

  test(
    'crash-shaped secret adoption rotates file state and converges fresh',
    () async {
      final fileStates = WebDavSyncEngineStateStore(
        bindingStore: bindingStore,
        directoryProvider: () async => supportDirectory,
      );
      await fileStates.update(
        binding.namespaceId,
        (_) => const WebDavSyncEngineState(
          currentDeviceIds: <String>{'stale-device'},
        ),
      );
      await bindingStore.updateNamespaceValues(
        binding.namespaceId,
        (values) => <String, Object?>{
          ...values,
          WebDavSyncBindingStore.registryTombstonesFileValueKey: const {
            'version': 1,
            'storage': 'file',
          },
        },
      );
      final oldDeviceId = (await bindingStore.load())
          .namespaceFor(binding)!
          .deviceId;
      binding = await bindingStore.adoptSyncSecret(
        binding.id,
        'winning-machine-secret',
      );
      var adoptedNamespace = (await bindingStore.load()).namespaceFor(binding)!;
      expect(adoptedNamespace.deviceId, isNot(oldDeviceId));
      expect(
        adoptedNamespace.values.keys,
        isNot(contains(WebDavSyncBindingStore.engineStateFileValueKey)),
      );
      expect(
        adoptedNamespace.values.keys,
        isNot(contains(WebDavSyncBindingStore.registryTombstonesFileValueKey)),
      );
      transport.rootKey = const WebDavSyncRootKeyFile(
        syncPassphrase: 'winning-machine-secret',
      ).encode();
      final fileInitializer = WebDavSyncNewRootInitializer(
        bindingStore: bindingStore,
        stateRepository: fileStates,
        seedSource: seeds,
        transportFactory: ({required binding, required secrets}) => transport,
        clock: () => DateTime.utc(2026, 9, 1),
      );

      expect(
        await fileInitializer.initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        isA<WebDavSyncInitialized>(),
      );

      adoptedNamespace = (await bindingStore.load()).namespaceFor(
        (await bindingStore.load()).activeBinding!,
      )!;
      expect(
        adoptedNamespace.values,
        isNot(
          contains(WebDavSyncBindingStore.seedCandidateResetRequiredValueKey),
        ),
      );
      final stateFiles = Directory(
        p.join(supportDirectory.path, 'webdav-sync', 'engine-state-v1'),
      ).listSync().whereType<File>().toList();
      expect(stateFiles, hasLength(1));
    },
  );

  test(
    'concurrent-root follow re-reads and persists the winning key',
    () async {
      final losingDeviceId = (await bindingStore.load())
          .namespaceFor(binding)!
          .deviceId;
      final winnerSecret = 'winning-machine-secret';
      final winnerMarker = await WebDavSyncCodec().sealRoot(
        passphrase: winnerSecret,
        circleId: 'winner-circle',
        createdAt: DateTime.utc(2026, 9, 1),
        runInBackground: true,
      );
      transport
        ..marker = winnerMarker
        ..rootKeyAfterFirstRead = WebDavSyncRootKeyFile(
          syncPassphrase: winnerSecret,
        ).encode();

      final outcome = await initializer().initialize(
        bindingId: binding.id,
        authorization: authorization,
      );
      final concurrent = outcome as WebDavSyncConcurrentRoot;

      expect(concurrent.root.document.circleId, 'winner-circle');
      expect(
        (await bindingStore.readSecrets(concurrent.binding)).syncPassphrase,
        winnerSecret,
      );
      expect(transport.keyReadCount, greaterThanOrEqualTo(2));
      expect(transport.events, contains('delete:$losingDeviceId'));
    },
  );

  test(
    'ambiguous MKCOL 405 with a missing root collection fails closed',
    () async {
      transport.activationLayoutExists = false;

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavSyncRootKeyClaimException>()),
      );

      expect(transport.events, isNot(contains('read:key')));
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
    'a server ignoring create-only is refused before the TOCTOU window',
    () async {
      transport.conditionalCreateProbeError =
          const WebDavSyncProviderUnsupportedException();

      await expectLater(
        initializer().initialize(
          bindingId: binding.id,
          authorization: authorization,
        ),
        throwsA(isA<WebDavSyncProviderUnsupportedException>()),
      );

      expect(transport.events, isNot(contains('read:key')));
      expect(transport.events, isNot(contains('read:root')));
      expect(transport.events, isNot(contains('create:key')));
      expect(transport.events, isNot(contains('create:root')));
      expect((await bindingStore.load()).activeBindingId, isNull);
    },
  );

  test(
    'two initializers with independent secrets refuse an ignore-all server',
    () async {
      final server = _IgnoringPreconditionsServer();
      final firstSecret = WebDavSyncCodec.generateSyncSecret();
      final secondSecret = WebDavSyncCodec.generateSyncSecret();
      expect(firstSecret, isNot(secondSecret));

      final firstLocation = WebDavSyncFolderLocation(
        endpoint: 'https://first-device.test/dav',
        folderPath: 'Family',
        serverName: 'First device',
      );
      var firstBinding = await bindingStore.stageBinding(
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
      firstBinding = await bindingStore.markAwaitingSeedCommit(firstBinding.id);
      final firstSnapshot = await bindingStore.load();

      final secondLocation = WebDavSyncFolderLocation(
        endpoint: 'https://second-device.test/dav',
        folderPath: 'Family',
        serverName: 'Second device',
      );
      var secondBinding = await bindingStore.stageBinding(
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
      secondBinding = await bindingStore.markAwaitingSeedCommit(
        secondBinding.id,
      );
      final secondSnapshot = await bindingStore.load();
      final combined = WebDavSyncStoreSnapshot(
        stagedBindingId: secondBinding.id,
        bindings: <String, WebDavSyncBinding>{
          firstBinding.id: firstBinding,
          secondBinding.id: secondBinding,
        },
        namespaces: <String, WebDavSyncNamespace>{
          firstBinding.namespaceId: firstSnapshot.namespaceFor(firstBinding)!,
          secondBinding.namespaceId: secondSnapshot.namespaceFor(
            secondBinding,
          )!,
        },
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        WebDavSyncBindingStore.storageKey,
        jsonEncode(combined.toJson()),
      );

      final first = WebDavSyncNewRootInitializer(
        bindingStore: bindingStore,
        stateRepository: _MemoryStateRepository(),
        seedSource: _FakeSeedSource(),
        transportFactory: ({required binding, required secrets}) =>
            server.connect(),
        clock: () => DateTime.utc(2026, 9, 1),
      );
      final second = WebDavSyncNewRootInitializer(
        bindingStore: bindingStore,
        stateRepository: _MemoryStateRepository(),
        seedSource: _FakeSeedSource(),
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

      final results = await Future.wait(<Future<Object>>[
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
      ]);

      expect(server.probeCalls, 2);
      expect(server.keyCreateCalls, 0);
      expect(server.markerCreateCalls, 0);
      expect(server.rootKey, isNull);
      expect(server.marker, isNull);
      expect(
        results,
        everyElement(isA<WebDavSyncProviderUnsupportedException>()),
        reason: 'both initializers must refuse before the race can mutate',
      );
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
  int prepareCalls = 0;

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

class _FakeActivationTransport
    implements
        WebDavSyncActivationTransport,
        WebDavSyncCommittedRootKeyRepairTransport {
  final List<String> events = <String>[];
  final Map<String, Uint8List> sections = <String, Uint8List>{};
  Uint8List? manifest;
  Uint8List? marker;
  Uint8List? rootKey = const WebDavSyncRootKeyFile(
    syncPassphrase: 'circle-secret',
  ).encode();
  Uint8List? rootKeyAfterFirstRead;
  final Map<int, Uint8List> rootKeyOnRead = <int, Uint8List>{};
  Uint8List? rootKeyAfterMarkerCreate;
  int keyReadCount = 0;
  int markerReadCount = 0;
  final Map<int, Uint8List> markerOnRead = <int, Uint8List>{};
  final Map<int, Uint8List> rootKeyOnMarkerRead = <int, Uint8List>{};
  WebDavException? createKeyError;
  Uint8List? keyOnCreateError;
  Uint8List? replaceKeyAfterCreate;
  Object? overwriteKeyError;
  Uint8List? replaceKeyAfterOverwrite;
  int overwriteKeyCalls = 0;
  bool activationLayoutExists = true;
  WebDavException? createError;
  WebDavException? manifestWriteError;
  Uint8List? replaceMarkerAfterCreate;
  Uint8List? markerOnCreateError;
  Uint8List? rootKeyOnCreateError;
  bool createStoresThenThrows = false;
  List<String> deviceIds = const <String>[];
  Future<void> Function()? afterSectionWrite;
  Object? conditionalCreateProbeError;
  int conditionalCreateProbeCalls = 0;

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
      throw const WebDavSyncRootKeyClaimException();
    }
  }

  @override
  Future<void> verifyConditionalCreate({
    required String syncRootPath,
    Future<void> Function()? beforeSend,
  }) async {
    conditionalCreateProbeCalls++;
    events.add('probe:conditional');
    if (conditionalCreateProbeError case final failure?) throw failure;
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
    markerReadCount++;
    if (markerOnRead.remove(markerReadCount) case final replacement?) {
      marker = Uint8List.fromList(replacement);
    }
    if (rootKeyOnMarkerRead.remove(markerReadCount) case final replacement?) {
      rootKey = Uint8List.fromList(replacement);
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
  Future<WebDavBytesResult> readRootKey() async {
    events.add('read:key');
    keyReadCount++;
    if (rootKeyOnRead.remove(keyReadCount) case final replacement?) {
      rootKey = Uint8List.fromList(replacement);
    }
    final value = keyReadCount > 1 && rootKeyAfterFirstRead != null
        ? rootKeyAfterFirstRead
        : rootKey;
    if (value == null) {
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'missing',
      );
    }
    return WebDavBytesResult(bytes: value, metadata: metadata);
  }

  @override
  Future<WebDavResponseMetadata> createRootKey(Uint8List bytes) async {
    events.add('create:key');
    final error = createKeyError;
    if (error != null) {
      final winner = keyOnCreateError;
      if (winner != null) rootKey = Uint8List.fromList(winner);
      throw error;
    }
    rootKey = Uint8List.fromList(replaceKeyAfterCreate ?? bytes);
    return WebDavResponseMetadata(
      statusCode: 201,
      uri: metadata.uri,
      headers: const <String, String>{},
      serverDate: metadata.serverDate,
    );
  }

  @override
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes) async {
    events.add('create:root');
    final error = createError;
    if (error != null) {
      final winningMarker = markerOnCreateError;
      if (winningMarker != null) marker = Uint8List.fromList(winningMarker);
      final winningKey = rootKeyOnCreateError;
      if (winningKey != null) rootKey = Uint8List.fromList(winningKey);
      throw error;
    }
    marker = Uint8List.fromList(replaceMarkerAfterCreate ?? bytes);
    if (rootKeyAfterMarkerCreate case final replacement?) {
      rootKey = Uint8List.fromList(replacement);
      rootKeyAfterMarkerCreate = null;
    }
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
  Future<WebDavResponseMetadata> overwriteRootKey(Uint8List bytes) async {
    events.add('overwrite:key');
    overwriteKeyCalls++;
    if (overwriteKeyError case final failure?) throw failure;
    rootKey = Uint8List.fromList(replaceKeyAfterOverwrite ?? bytes);
    rootKeyAfterFirstRead = null;
    return metadata;
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
  Uint8List? rootKey;
  Uint8List? marker;
  int probeCalls = 0;
  int keyCreateCalls = 0;
  int markerCreateCalls = 0;
  int _initialKeyReads = 0;
  int _initialMarkerReads = 0;
  final Completer<void> _bothKeyReads = Completer<void>();
  final Completer<void> _bothMarkerReads = Completer<void>();
  final Completer<void> _bothKeyCreates = Completer<void>();
  final Completer<void> _bothMarkerCreates = Completer<void>();

  _IgnoringPreconditionsTransport connect() =>
      _IgnoringPreconditionsTransport(this);

  Future<WebDavBytesResult> readKey(WebDavResponseMetadata metadata) async {
    final existing = rootKey;
    if (existing != null) {
      return WebDavBytesResult(bytes: existing, metadata: metadata);
    }
    _initialKeyReads++;
    if (_initialKeyReads == 2) _bothKeyReads.complete();
    await _bothKeyReads.future;
    throw const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
  }

  Future<WebDavBytesResult> readMarker(
    WebDavResponseMetadata metadata, {
    required bool initialRead,
  }) async {
    final existing = marker;
    if (existing != null) {
      return WebDavBytesResult(bytes: existing, metadata: metadata);
    }
    if (initialRead) {
      _initialMarkerReads++;
      if (_initialMarkerReads == 2) _bothMarkerReads.complete();
      await _bothMarkerReads.future;
    }
    throw const WebDavException(
      kind: WebDavErrorKind.notFound,
      message: 'missing',
    );
  }

  Future<void> createKey(Uint8List bytes) async {
    keyCreateCalls++;
    if (keyCreateCalls == 2) _bothKeyCreates.complete();
    await _bothKeyCreates.future;
    // Deliberately ignore If-None-Match and overwrite the shared resource.
    rootKey = Uint8List.fromList(bytes);
  }

  Future<void> createMarker(Uint8List bytes) async {
    markerCreateCalls++;
    if (markerCreateCalls == 2) _bothMarkerCreates.complete();
    await _bothMarkerCreates.future;
    // Deliberately ignore If-None-Match and overwrite the shared resource.
    marker = Uint8List.fromList(bytes);
  }
}

final class _IgnoringPreconditionsTransport extends _FakeActivationTransport {
  _IgnoringPreconditionsTransport(this.server) : super();

  final _IgnoringPreconditionsServer server;
  bool _initialMarkerRead = true;

  @override
  Future<void> verifyConditionalCreate({
    required String syncRootPath,
    Future<void> Function()? beforeSend,
  }) async {
    server.probeCalls++;
    events.add('probe:conditional');
    throw const WebDavSyncProviderUnsupportedException();
  }

  @override
  Future<WebDavBytesResult> readRootKey() {
    events.add('read:key');
    return server.readKey(metadata);
  }

  @override
  Future<WebDavResponseMetadata> createRootKey(Uint8List bytes) async {
    events.add('create:key');
    await server.createKey(bytes);
    return WebDavResponseMetadata(
      statusCode: 201,
      uri: metadata.uri,
      headers: const <String, String>{},
      serverDate: metadata.serverDate,
    );
  }

  @override
  Future<WebDavBytesResult> readRootMarker() async {
    events.add('read:root');
    final initialRead = _initialMarkerRead;
    _initialMarkerRead = false;
    return server.readMarker(metadata, initialRead: initialRead);
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

  @override
  Future<WebDavResponseMetadata> overwriteRootKey(Uint8List bytes) async {
    events.add('overwrite:key');
    server.rootKey = Uint8List.fromList(bytes);
    return metadata;
  }
}
