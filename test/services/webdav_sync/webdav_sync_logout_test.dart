import 'dart:io';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_logout.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = WebDavConfig(
  id: 'server',
  name: 'Cloud',
  baseUrl: 'https://example.test/dav',
  username: 'alice',
  password: 'password',
);

void main() {
  late WebDavSyncBindingStore store;
  late WebDavSyncCodec codec;
  late OpenedWebDavSyncRoot root;
  late WebDavSyncBinding binding;
  late String deviceId;
  late _Transport transport;
  late WebDavSyncLogout logout;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'local-data': 'keep me'});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List.generate(32, (i) => i)),
    );
    store = WebDavSyncBindingStore();
    codec = WebDavSyncCodec();
    final marker = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: 'circle-one',
      createdAt: DateTime.utc(2026, 9, 1),
      memoryKiB: 8,
      iterations: 1,
    );
    root = await codec.openRoot(marker, 'circle-secret');
    final authority = WebDavSyncAuthorityFile(
      markerBytes: marker,
      syncPassphrase: 'circle-secret',
    ).encode();
    binding = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(config, 'Sync'),
      config: config,
      syncPassphrase: 'circle-secret',
    );
    binding = await store.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: authority,
    );
    deviceId = (await store.load()).namespaceFor(binding)!.deviceId;
    final manifest = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: deviceId,
      updatedAtMs: 1000,
      clockOffsetMs: 0,
      graphSchemaClaim: 1,
      profileMap: const {},
      resourceMap: const {},
      sections: [
        WebDavSyncSectionReference(
          name: 'bootstrap',
          contentHash: 'a' * 64,
          semanticDigest: 'b' * 64,
          updatedAtMs: 1000,
          schemaVersion: 1,
          size: 100,
        ),
      ],
    );
    transport = _Transport(
      authority,
      await codec.sealDocument(
        key: root.key,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: 'manifest',
        schemaVersion: 1,
        payload: manifest.toJson(),
      ),
    );
    logout = WebDavSyncLogout(
      store: store,
      codec: codec,
      transportFactory: (_, _) => transport,
    );
  });
  tearDown(DeviceKeyProvider.debugReset);

  test(
    'logout unregisters, forgets credentials and identity, and preserves data',
    () async {
      final manifest = transport.manifest;
      expect(
        await webDavSyncDeviceIsRegistered(
          transport: transport,
          codec: codec,
          root: root,
          deviceId: deviceId,
        ),
        isTrue,
      );
      await logout.run(authorize: () async {});
      expect(
        await webDavSyncDeviceIsRegistered(
          transport: transport,
          codec: codec,
          root: root,
          deviceId: deviceId,
        ),
        isFalse,
      );
      final snapshot = await store.load();
      expect(snapshot.bindings, isEmpty);
      expect(snapshot.namespaces, isEmpty);
      expect(transport.manifest, same(manifest));
      expect(
        (await SharedPreferences.getInstance()).getString('local-data'),
        'keep me',
      );
      final fresh = await store.stageBinding(
        location: binding.location,
        config: config,
        syncPassphrase: 'circle-secret',
      );
      final freshId = (await store.load()).namespaceFor(fresh)!.deviceId;
      expect(freshId, isNot(deviceId));
      expect(
        await webDavSyncDeviceIsRegistered(
          transport: transport,
          codec: codec,
          root: root,
          deviceId: freshId,
        ),
        isTrue,
      );
    },
  );

  test(
    'logout removes engine caches without deleting local profile files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'logout-cache-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final localFile = File('${directory.path}/local-profile-data');
      await localFile.writeAsString('keep me');
      final states = WebDavSyncEngineStateStore(
        bindingStore: store,
        directoryProvider: () async => directory,
      );
      await states.update(
        binding.namespaceId,
        (state) => state.copyWith(lastSuccessfulSyncMs: 1000),
      );
      expect(
        await directory
            .list(recursive: true)
            .where((entry) => entry is File)
            .length,
        greaterThan(1),
      );
      await logout.run(
        authorize: () async {},
        forgetLocalNamespace: states.forgetLoggedOutNamespace,
      );
      expect(
        await directory
            .list(recursive: true)
            .where((entry) => entry is File)
            .length,
        1,
      );
      expect(await localFile.readAsString(), 'keep me');
      expect((await store.load()).namespaces, isEmpty);
    },
  );

  test(
    'password repair keeps logout paused and the device identity stable',
    () async {
      await store.setLifecycle(binding.id, WebDavSyncLifecycle.active);
      await store.promoteStaged(binding.id);
      await store.beginLogout();
      final repaired = await store.repairLogoutCredentials(
        bindingId: binding.id,
        authorityBytes: transport.authority,
        config: const WebDavConfig(
          id: 'server',
          name: 'Cloud',
          baseUrl: 'https://example.test/dav',
          username: 'alice',
          password: 'new-password',
        ),
        syncPassphrase: 'circle-secret',
      );
      final snapshot = await store.load();
      expect(snapshot.namespaceFor(repaired)!.deviceId, deviceId);
      expect(WebDavSyncBindingStore.logoutPending(snapshot), isTrue);
      expect((await store.readSecrets(repaired)).password, 'new-password');
    },
  );

  for (final retained in [false, true]) {
    test(
      'repair ${retained ? "retained" : "staged"} logout binding preserves pointers',
      () async {
        if (retained) {
          await store.setLifecycle(binding.id, WebDavSyncLifecycle.active);
          await store.promoteStaged(binding.id);
          final other = await store.stageBinding(
            location: WebDavSyncFolderLocation.fromConfig(config, 'Other'),
            config: config,
            syncPassphrase: 'circle-secret',
          );
          await store.markRootVerified(
            bindingId: other.id,
            root: root.document,
            markerBytes: transport.authority,
          );
          await store.setLifecycle(other.id, WebDavSyncLifecycle.active);
          await store.promoteStaged(other.id);
        }
        transport.offline = true;
        await expectLater(
          logout.run(authorize: () async {}),
          throwsA(isA<WebDavException>()),
        );
        final before = await store.load();
        expect(
          before.namespaceFor(binding)!.values['logoutNeedsAttentionBindingId'],
          binding.id,
        );
        final repaired = await store.repairLogoutCredentials(
          bindingId: binding.id,
          config: const WebDavConfig(
            id: 'server',
            name: 'Cloud',
            baseUrl: 'https://example.test/dav',
            username: 'alice',
            password: 'repaired',
          ),
          syncPassphrase: 'circle-secret',
          authorityBytes: transport.authority,
        );
        final after = await store.load();
        expect(after.activeBindingId, before.activeBindingId);
        expect(after.stagedBindingId, before.stagedBindingId);
        expect(repaired.lifecycle, before.bindings[binding.id]!.lifecycle);
        expect(
          after.namespaceFor(repaired)!.toJson(),
          before.namespaceFor(binding)!.toJson(),
        );
        expect((await store.readSecrets(repaired)).password, 'repaired');
        transport.offline = false;
        await logout.run(authorize: () async {});
        expect((await store.load()).bindings, isEmpty);
      },
    );
  }

  test('logout repair refuses a changed authority and key', () async {
    await store.beginLogout();
    for (final changedKey in [false, true]) {
      await expectLater(
        store.repairLogoutCredentials(
          bindingId: binding.id,
          config: config,
          syncPassphrase: changedKey ? 'changed-secret' : 'circle-secret',
          authorityBytes: changedKey
              ? transport.authority
              : Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(anything),
      );
      expect(
        (await store.readSecrets(
          (await store.load()).bindings[binding.id]!,
        )).password,
        'password',
      );
    }
  });

  test('deleted root finishes logout and permits a new connection', () async {
    transport.rootMissing = true;
    final forgotten = <String>[];
    await logout.run(
      authorize: () async {},
      forgetLocalNamespace: (namespace) async {
        forgotten.add(namespace.id);
      },
    );
    expect(forgotten, isNotEmpty);
    expect((await store.load()).bindings, isEmpty);
    expect(transport.registrations, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString('local-data'),
      'keep me',
    );
    await store.stageBinding(
      location: binding.location,
      config: config,
      syncPassphrase: 'new-secret',
    );
    expect((await store.load()).bindings, isNotEmpty);
  });

  test(
    'explicit local logout recovers offline pending logout without remote access',
    () async {
      transport.offline = true;
      await expectLater(
        logout.run(authorize: () async {}),
        throwsA(isA<WebDavException>()),
      );
      final localLogout = WebDavSyncLogout(
        store: store,
        transportFactory: (_, _) => throw StateError('must not contact server'),
      );
      await localLogout.run(authorize: () async {}, localOnly: true);
      expect((await store.load()).bindings, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('local-data'),
        'keep me',
      );
    },
  );

  test('local-only logout still requires authorization', () async {
    await expectLater(
      logout.run(
        authorize: () async {
          throw StateError('not admin');
        },
        localOnly: true,
      ),
      throwsStateError,
    );
    expect((await store.load()).bindings, isNotEmpty);
  });

  test('offline logout keeps a durable pause and can be retried', () async {
    transport.offline = true;
    await expectLater(
      logout.run(authorize: () async {}),
      throwsA(isA<WebDavException>()),
    );
    var snapshot = await WebDavSyncBindingStore().load();
    expect(WebDavSyncBindingStore.logoutPending(snapshot), isTrue);
    expect(snapshot.bindings, isNotEmpty);
    await expectLater(
      store.stageBinding(
        location: binding.location,
        config: config,
        syncPassphrase: 'circle-secret',
      ),
      throwsStateError,
    );
    transport.offline = false;
    await logout.run(authorize: () async {});
    snapshot = await store.load();
    expect(snapshot.bindings, isEmpty);
  });

  test(
    'unverified registration write does not forget the credentials',
    () async {
      transport.ignoreWrite = true;
      await expectLater(logout.run(authorize: () async {}), throwsStateError);
      expect((await store.load()).bindings, isNotEmpty);
      expect(WebDavSyncBindingStore.logoutPending(await store.load()), isTrue);
    },
  );

  test(
    'authorization failure leaves registration and connection untouched',
    () async {
      await expectLater(
        logout.run(
          authorize: () async {
            throw StateError('locked');
          },
        ),
        throwsStateError,
      );
      expect(transport.registrations, isEmpty);
      expect(WebDavSyncBindingStore.logoutPending(await store.load()), isFalse);
    },
  );

  test('changed authority cannot unregister a different sync folder', () async {
    transport.authority = Uint8List.fromList([1, 2, 3]);
    await expectLater(logout.run(authorize: () async {}), throwsStateError);
    expect(transport.registrations, isEmpty);
    expect((await store.load()).bindings, isNotEmpty);
  });

  test('local cleanup failure retains the logout journal for retry', () async {
    await expectLater(
      logout.run(
        authorize: () async {},
        forgetLocalNamespace: (_) async {
          throw StateError('disk failure');
        },
      ),
      throwsStateError,
    );
    expect(WebDavSyncBindingStore.logoutPending(await store.load()), isTrue);
    expect(
      await webDavSyncDeviceIsRegistered(
        transport: transport,
        codec: codec,
        root: root,
        deviceId: deviceId,
      ),
      isFalse,
    );
    await logout.run(authorize: () async {});
    expect((await store.load()).bindings, isEmpty);
  });
}

class _Transport
    implements WebDavSyncTransport, WebDavSyncRegistrationTransport {
  _Transport(this.authority, this.manifest);
  Uint8List authority;
  final Uint8List manifest;
  final registrations = <String, Uint8List>{};
  bool offline = false;
  bool rootMissing = false;
  bool ignoreWrite = false;
  WebDavBytesResult result(Uint8List bytes) => WebDavBytesResult(
    bytes: bytes,
    metadata: WebDavResponseMetadata(
      statusCode: 200,
      uri: Uri.parse('https://example.test/dav'),
      headers: const {},
    ),
  );
  @override
  Future<WebDavBytesResult> readRootMarker() async {
    if (offline) {
      throw const WebDavException(
        kind: WebDavErrorKind.network,
        message: 'offline',
      );
    }
    if (rootMissing)
      throw const WebDavException(
        kind: WebDavErrorKind.notFound,
        message: 'deleted',
      );
    return result(authority);
  }

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) async =>
      result(manifest);
  @override
  Future<WebDavBytesResult?> readRegistration(String deviceId) async =>
      registrations[deviceId] == null ? null : result(registrations[deviceId]!);
  @override
  Future<void> writeRegistration(String deviceId, Uint8List bytes) async {
    if (!ignoreWrite) registrations[deviceId] = bytes;
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
