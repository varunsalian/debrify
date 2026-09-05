import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _config = WebDavConfig(
  id: 'server-1',
  name: 'Koofr',
  baseUrl: 'https://app.koofr.net/dav/Koofr',
  username: 'alice',
  password: 'server-secret',
);

void main() {
  late WebDavSyncBindingStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.generate(32, (index) => index)),
    );
    var random = 0;
    store = WebDavSyncBindingStore(
      clock: () => DateTime.utc(2026, 9, 1),
      randomBytes: (length) => Uint8List.fromList(
        List<int>.generate(length, (_) => random++ & 0xff),
      ),
    );
  });

  tearDown(() {
    DeviceKeyProvider.debugReset();
    ProfilePreferenceBudget.debugReset();
  });

  test(
    'load rewrites legacy assembled pins without retaining the secret',
    () async {
      final marker = Uint8List.fromList([1, 2, 3]);
      final authority = WebDavSyncAuthorityFile(
        markerBytes: marker,
        syncPassphrase: 'legacy-circle-secret',
      ).encode();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        WebDavSyncBindingStore.storageKey,
        jsonEncode({
          'version': 1,
          'bindings': {},
          'namespaces': {
            'circle:legacy': {
              'id': 'circle:legacy',
              'deviceId': 'device-legacy',
              'markerBytes': base64Encode(authority),
            },
          },
        }),
      );
      final loaded = await store.load();
      final namespace = loaded.namespaces['circle:legacy']!;
      expect(namespace.markerBytes, orderedEquals(marker));
      expect(namespace.matchesAuthority(authority), isTrue);
      final rewritten = prefs.getString(WebDavSyncBindingStore.storageKey)!;
      final rawPin =
          (jsonDecode(rewritten)['namespaces']['circle:legacy']['markerBytes'])
              as String;
      expect(base64Decode(rawPin), orderedEquals(marker));
      expect(
        utf8.decode(base64Decode(rawPin), allowMalformed: true),
        isNot(contains('legacy-circle-secret')),
      );
      expect(rewritten, isNot(contains(base64Encode(authority))));
      await store.load();
      expect(prefs.getString(WebDavSyncBindingStore.storageKey), rewritten);
    },
  );

  test(
    'cycle pin checks accept both shapes but reject different authority content',
    () {
      final marker = Uint8List.fromList([1, 2, 3]);
      final authority = WebDavSyncAuthorityFile(
        markerBytes: marker,
        syncPassphrase: 'circle-secret',
      ).encode();
      final other = WebDavSyncAuthorityFile(
        markerBytes: marker,
        syncPassphrase: 'different-secret',
      ).encode();
      final namespace = WebDavSyncNamespace(
        id: 'circle:test',
        deviceId: 'device-test',
        markerBytes: marker,
        authorityContentHash: webDavSyncAuthorityHash(authority),
      );
      expect(
        namespace.matchesAuthorityPin(authority, namespace.pinnedAuthorityHash),
        isTrue,
      );
      expect(
        namespace.matchesAuthorityPin(marker, namespace.pinnedAuthorityHash),
        isTrue,
      );
      expect(
        namespace.matchesAuthorityPin(other, namespace.pinnedAuthorityHash),
        isFalse,
      );
      expect(
        namespace.matchesAuthorityPin(marker, webDavSyncAuthorityHash(other)),
        isFalse,
      );
      expect(
        namespace.matchesAuthorityPin(null, namespace.pinnedAuthorityHash),
        isFalse,
      );
    },
  );

  test(
    'credentials are device-sealed and candidate identity is stable',
    () async {
      final location = WebDavSyncFolderLocation.fromConfig(
        _config,
        '/TV//Sync/',
      );
      final first = await store.stageBinding(
        location: location,
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final firstNamespace = (await store.load()).namespaceFor(first)!;

      final raw = (await SharedPreferences.getInstance()).getString(
        WebDavSyncBindingStore.storageKey,
      )!;
      expect(raw, isNot(contains('server-secret')));
      expect(raw, isNot(contains('circle-secret')));
      expect((await store.readSecrets(first)).password, 'server-secret');
      expect((await store.readSecrets(first)).syncPassphrase, 'circle-secret');
      expect(location.folderPath, 'TV/Sync');

      final retry = await store.stageBinding(
        location: location,
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final retryNamespace = (await store.load()).namespaceFor(retry)!;
      expect(retryNamespace.deviceId, firstNamespace.deviceId);
    },
  );

  test(
    'changed passphrase restarts an uncommitted candidate identity',
    () async {
      final location = WebDavSyncFolderLocation.fromConfig(_config, 'Sync');
      final first = await store.stageBinding(
        location: location,
        config: _config,
        syncPassphrase: 'first-circle-secret',
      );
      final firstNamespace = (await store.load()).namespaceFor(first)!;
      await store.updateNamespaceValues(
        first.namespaceId,
        (_) => <String, Object?>{'abandoned': true},
      );

      final retry = await store.stageBinding(
        location: location,
        config: _config,
        syncPassphrase: 'second-circle-secret',
      );
      final retryNamespace = (await store.load()).namespaceFor(retry)!;

      expect(retry.namespaceId, first.namespaceId);
      expect(retryNamespace.deviceId, isNot(firstNamespace.deviceId));
      expect(retryNamespace.values, isEmpty);
      expect(
        (await store.readSecrets(retry)).syncPassphrase,
        'second-circle-secret',
      );
    },
  );

  test('atomic key adoption preserves login and lifecycle', () async {
    var binding = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Debrify'),
      config: _config,
      syncPassphrase: 'losing-machine-secret',
    );
    binding = await store.markAwaitingSeedCommit(binding.id);
    final before = (await store.load()).namespaceFor(binding)!;
    await store.updateNamespaceValues(
      binding.namespaceId,
      (_) => <String, Object?>{
        WebDavSyncBindingStore.seedCandidateMarkerValueKey: 'candidate',
        WebDavSyncBindingStore.engineStateFileValueKey: const {
          'version': 1,
          'storage': 'file',
        },
        WebDavSyncBindingStore.registryTombstonesFileValueKey: const {
          'version': 1,
          'storage': 'file',
        },
        'unrelated': true,
      },
    );

    final adopted = await store.adoptSyncSecret(
      binding.id,
      'winning-machine-secret',
    );
    final snapshot = await store.load();
    final namespace = snapshot.namespaceFor(adopted)!;
    final secrets = await store.readSecrets(adopted);

    expect(adopted.lifecycle, WebDavSyncLifecycle.awaitingSeedCommit);
    expect(secrets.username, _config.username);
    expect(secrets.password, _config.password);
    expect(secrets.syncPassphrase, 'winning-machine-secret');
    expect(namespace.deviceId, isNot(before.deviceId));
    expect(
      namespace.values,
      isNot(contains(WebDavSyncBindingStore.seedCandidateMarkerValueKey)),
    );
    expect(
      namespace.values[WebDavSyncBindingStore
          .seedCandidateResetRequiredValueKey],
      before.deviceId,
    );
    expect(
      namespace.values,
      isNot(contains(WebDavSyncBindingStore.engineStateFileValueKey)),
    );
    expect(
      namespace.values,
      isNot(contains(WebDavSyncBindingStore.registryTombstonesFileValueKey)),
    );
    expect(namespace.values['unrelated'], isTrue);
  });

  test(
    'verified root migrates candidate state into a circle namespace',
    () async {
      final binding = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Sync'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      await expectLater(
        store.setLifecycle(binding.id, WebDavSyncLifecycle.rootVerified),
        throwsStateError,
      );
      final verified = await store.markRootVerified(
        bindingId: binding.id,
        root: WebDavSyncRootDocument(
          circleId: 'circle-1',
          createdAt: DateTime.utc(2026, 9, 1),
          schemaFloor: 1,
          kdfSalt: Uint8List(16),
        ),
        markerBytes: const <int>[1, 2, 3],
      );
      final snapshot = await store.load();

      expect(verified.lifecycle, WebDavSyncLifecycle.rootVerified);
      expect(verified.namespaceId, 'circle:circle-1');
      expect(snapshot.namespaceFor(verified)!.markerBytes, <int>[1, 2, 3]);
      expect(() => store.markAwaitingSeedCommit(verified.id), throwsStateError);
    },
  );

  test(
    'change-folder staging leaves the active root intact on cancel',
    () async {
      final first = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'First'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final verified = await store.markRootVerified(
        bindingId: first.id,
        root: WebDavSyncRootDocument(
          circleId: 'circle-1',
          createdAt: DateTime.utc(2026, 9, 1),
          schemaFloor: 1,
          kdfSalt: Uint8List(16),
        ),
        markerBytes: const <int>[1],
      );
      await store.activateAndPromoteStaged(verified.id);

      final secondConfig = WebDavConfig(
        id: 'server-2',
        name: 'Other',
        baseUrl: _config.baseUrl,
        username: _config.username,
        password: _config.password,
      );
      final second = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(secondConfig, 'Second'),
        config: secondConfig,
        syncPassphrase: 'other-secret',
      );
      var snapshot = await store.load();
      expect(snapshot.activeBindingId, verified.id);
      expect(snapshot.activeBinding!.lifecycle, WebDavSyncLifecycle.active);
      expect(snapshot.stagedBindingId, second.id);

      await store.discardStaged();
      snapshot = await store.load();
      expect(snapshot.activeBindingId, verified.id);
      expect(snapshot.activeBinding!.lifecycle, WebDavSyncLifecycle.active);
      expect(snapshot.stagedBindingId, isNull);
      expect(snapshot.bindings, isNot(contains(second.id)));
    },
  );

  test(
    'onboarding intent survives activation until it is acknowledged',
    () async {
      final first = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'First'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final verifiedFirst = await store.markRootVerified(
        bindingId: first.id,
        root: WebDavSyncRootDocument(
          circleId: 'circle-1',
          createdAt: DateTime.utc(2026, 9, 1),
          schemaFloor: 1,
          kdfSalt: Uint8List(16),
        ),
        markerBytes: const <int>[1],
      );
      await store.activateAndPromoteStaged(verifiedFirst.id);

      final candidate = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Second'),
        config: _config,
        syncPassphrase: 'other-secret',
        completeOnboarding: true,
      );
      final restartedStore = WebDavSyncBindingStore();
      expect(
        (await restartedStore.load()).stagedBinding?.completeOnboarding,
        isTrue,
      );

      await restartedStore.discardStaged();
      var snapshot = await restartedStore.load();
      expect(snapshot.activeBindingId, verifiedFirst.id);
      expect(snapshot.activeBinding?.completeOnboarding, isFalse);
      expect(snapshot.bindings, isNot(contains(candidate.id)));

      final retry = await restartedStore.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Second'),
        config: _config,
        syncPassphrase: 'other-secret',
        completeOnboarding: true,
      );
      final verifiedRetry = await restartedStore.markRootVerified(
        bindingId: retry.id,
        root: WebDavSyncRootDocument(
          circleId: 'circle-2',
          createdAt: DateTime.utc(2026, 9, 2),
          schemaFloor: 1,
          kdfSalt: Uint8List(16),
        ),
        markerBytes: const <int>[2],
      );
      await restartedStore.activateAndPromoteStaged(verifiedRetry.id);
      snapshot = await restartedStore.load();
      expect(snapshot.activeBindingId, retry.id);
      expect(snapshot.activeBinding?.completeOnboarding, isTrue);

      await restartedStore.acknowledgeOnboardingIntent(retry.id);
      snapshot = await restartedStore.load();
      expect(snapshot.activeBinding?.completeOnboarding, isFalse);
    },
  );

  test('activation promotes the staged folder in one snapshot', () async {
    final first = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'First'),
      config: _config,
      syncPassphrase: 'circle-secret',
    );
    await store.markRootVerified(
      bindingId: first.id,
      root: WebDavSyncRootDocument(
        circleId: 'circle-1',
        createdAt: DateTime.utc(2026, 9, 1),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: const <int>[1],
    );
    await store.activateAndPromoteStaged(first.id);

    final second = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Second'),
      config: _config,
      syncPassphrase: 'other-secret',
    );
    await store.markRootVerified(
      bindingId: second.id,
      root: WebDavSyncRootDocument(
        circleId: 'circle-2',
        createdAt: DateTime.utc(2026, 9, 2),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: const <int>[2],
    );

    final activated = await store.activateAndPromoteStaged(second.id);
    final snapshot = await store.load();

    expect(activated.lifecycle, WebDavSyncLifecycle.active);
    expect(snapshot.activeBindingId, second.id);
    expect(snapshot.stagedBindingId, isNull);
    expect(
      snapshot.bindings[first.id]!.lifecycle,
      WebDavSyncLifecycle.rootVerified,
    );
  });

  test(
    'cycle binding follows pointers when folders share one circle',
    () async {
      final root = WebDavSyncRootDocument(
        circleId: 'circle-1',
        createdAt: DateTime.utc(2026, 9, 1),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      );
      final first = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'First'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final firstVerified = await store.markRootVerified(
        bindingId: first.id,
        root: root,
        markerBytes: const <int>[1],
      );
      await store.activateAndPromoteStaged(first.id);

      final second = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Second'),
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final secondVerified = await store.markRootVerified(
        bindingId: second.id,
        root: root,
        markerBytes: const <int>[1],
      );
      await store.setLifecycle(
        secondVerified.id,
        WebDavSyncLifecycle.awaitingAdoption,
      );
      final snapshot = await store.load();

      expect(firstVerified.namespaceId, secondVerified.namespaceId);
      expect(
        snapshot
            .bindingForCycle(
              namespaceId: firstVerified.namespaceId,
              preActivation: false,
            )
            ?.id,
        first.id,
      );
      expect(
        snapshot
            .bindingForCycle(
              namespaceId: secondVerified.namespaceId,
              preActivation: true,
            )
            ?.id,
        second.id,
      );
      expect(
        snapshot.bindingForCycle(
          namespaceId: 'circle:other',
          preActivation: false,
        ),
        isNull,
      );
    },
  );

  test(
    'replacing a staged folder removes its abandoned local identity',
    () async {
      final first = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'First'),
        config: _config,
        syncPassphrase: 'first-secret',
      );
      final firstNamespaceId = first.namespaceId;

      final second = await store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(_config, 'Second'),
        config: _config,
        syncPassphrase: 'second-secret',
      );
      final snapshot = await store.load();

      expect(snapshot.stagedBindingId, second.id);
      expect(snapshot.bindings, isNot(contains(first.id)));
      expect(snapshot.namespaces, isNot(contains(firstNamespaceId)));
    },
  );

  test(
    'credential rotation in the same folder preserves active identity',
    () async {
      final location = WebDavSyncFolderLocation.fromConfig(_config, 'First');
      final first = await store.stageBinding(
        location: location,
        config: _config,
        syncPassphrase: 'circle-secret',
      );
      final verified = await store.markRootVerified(
        bindingId: first.id,
        root: WebDavSyncRootDocument(
          circleId: 'circle-1',
          createdAt: DateTime.utc(2026, 9, 1),
          schemaFloor: 1,
          kdfSalt: Uint8List(16),
        ),
        markerBytes: const <int>[1],
      );
      await store.activateAndPromoteStaged(verified.id);

      final rotated = await store.stageBinding(
        location: location,
        config: const WebDavConfig(
          id: 'server-1',
          name: 'Koofr',
          baseUrl: 'https://app.koofr.net/dav/Koofr',
          username: 'alice',
          password: 'rotated-secret',
        ),
        syncPassphrase: 'circle-secret',
        preserveActive: true,
      );

      expect(rotated.lifecycle, WebDavSyncLifecycle.active);
      expect(rotated.circleId, 'circle-1');
      expect(rotated.namespaceId, 'circle:circle-1');
      expect((await store.readSecrets(rotated)).password, 'rotated-secret');
      final snapshot = await store.load();
      expect(snapshot.activeBindingId, rotated.id);
      expect(snapshot.stagedBindingId, isNull);
    },
  );

  test(
    'locked vault defers configuration without persisting secrets',
    () async {
      DeviceKeyProvider.debugReset();

      await expectLater(
        store.stageBinding(
          location: WebDavSyncFolderLocation.fromConfig(_config, 'Sync'),
          config: _config,
          syncPassphrase: 'circle-secret',
        ),
        throwsA(isA<WebDavSyncVaultLockedException>()),
      );
      expect((await store.load()).bindings, isEmpty);
    },
  );

  test('binding metadata is capped before writing UserDefaults', () async {
    final binding = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(_config, 'Sync'),
      config: _config,
      syncPassphrase: 'circle-secret',
    );

    await expectLater(
      store.updateNamespaceValues(
        binding.namespaceId,
        (_) => <String, Object?>{'oversized': 'x' * (70 * 1024)},
      ),
      throwsFormatException,
    );

    expect((await store.load()).namespaceFor(binding)!.values, isEmpty);
  });

  test('binding writes respect the database-wide tvOS budget', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'p.one.g.1.bulk': 'x' * (ProfilePreferenceBudget.limitBytes - 1024),
    });
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    final largeConfig = WebDavConfig(
      id: 'server-large',
      name: 'Koofr',
      baseUrl: _config.baseUrl,
      username: _config.username,
      password: 'p' * 5000,
    );

    await expectLater(
      store.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(largeConfig, 'Sync'),
        config: largeConfig,
        syncPassphrase: 'circle-secret',
      ),
      throwsStateError,
    );

    expect(
      (await SharedPreferences.getInstance()).containsKey(
        WebDavSyncBindingStore.storageKey,
      ),
      isFalse,
    );
  });

  test('binding parser rejects unbounded collections before entries', () {
    expect(
      () => WebDavSyncStoreSnapshot.fromJson(<String, dynamic>{
        'version': 1,
        'bindings': <String, Object?>{
          for (var index = 0; index < 33; index++)
            'binding-$index': const <String, Object?>{},
        },
        'namespaces': const <String, Object?>{},
      }),
      throwsFormatException,
    );
  });
}
