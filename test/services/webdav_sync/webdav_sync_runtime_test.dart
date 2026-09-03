import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_database_adoption_gate.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_feature.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one authentication failure does not disable a healthy binding', () {
    final tracker = WebDavSyncAuthenticationFailureTracker();

    expect(tracker.recordFailure('binding-a'), isFalse);
    expect(tracker.recordFailure('binding-a'), isFalse);
    expect(tracker.recordFailure('binding-a'), isTrue);
  });

  test('a successful cycle resets the consecutive failure count', () {
    final tracker = WebDavSyncAuthenticationFailureTracker();

    expect(tracker.recordFailure('binding-a'), isFalse);
    expect(tracker.recordFailure('binding-a'), isFalse);
    tracker.recordSuccess('binding-a');
    expect(tracker.recordFailure('binding-a'), isFalse);
  });

  test(
    'two cycle transports and a poll reuse one binding client until disarm',
    () {
      var factoryCalls = 0;
      late _CountingClient client;
      final owner = WebDavSyncBindingHttpClientOwner(
        clientFactory: () {
          factoryCalls++;
          return client = _CountingClient();
        },
      );
      final location = WebDavSyncFolderLocation(
        endpoint: 'https://example.test/dav',
        folderPath: 'Family',
        serverName: 'Test',
      );
      const credentials = WebDavCredentials(username: 'alice', password: 'x');

      ProtocolWebDavSyncTransport(
        location: location,
        credentials: credentials,
        client: owner.borrow('binding-a').client,
      ).close();
      ProtocolWebDavSyncTransport(
        location: location,
        credentials: credentials,
        client: owner.borrow('binding-a').client,
      ).close();
      ProtocolWebDavSyncTransport(
        location: location,
        credentials: credentials,
        client: owner.borrow('binding-a').client,
      ).close();

      expect(factoryCalls, 1);
      expect(client.closeCalls, 0);
      expect(owner.debugHasClient, isTrue);

      owner.close();

      expect(client.closeCalls, 1);
      expect(owner.debugHasClient, isFalse);
    },
  );

  test(
    'binding change closes the old client and failed use stays owned',
    () async {
      final clients = <_CountingClient>[];
      final owner = WebDavSyncBindingHttpClientOwner(
        clientFactory: () {
          final client = _CountingClient();
          clients.add(client);
          return client;
        },
      );

      owner.borrow('binding-a');
      final failedTransport = ProtocolWebDavSyncTransport(
        location: WebDavSyncFolderLocation(
          endpoint: 'https://example.test/dav',
          folderPath: 'Family',
          serverName: 'Test',
        ),
        credentials: const WebDavCredentials(username: '', password: ''),
        client: owner.borrow('binding-b').client,
      );

      expect(clients, hasLength(2));
      expect(clients.first.closeCalls, 1);
      expect(clients.last.closeCalls, 0);

      await expectLater(
        failedTransport.readRootMarker(),
        throwsA(isA<WebDavException>()),
      );
      failedTransport.close();
      expect(clients.last.closeCalls, 0);

      // A failed cycle does not orphan a separate client: the retained binding
      // client remains owned until disarm/reset closes it.
      owner.close();
      expect(clients.last.closeCalls, 1);
    },
  );

  test('stale generations cannot use or close a rearmed client', () async {
    final clients = <_CountingClient>[];
    final owner = WebDavSyncBindingHttpClientOwner(
      clientFactory: () {
        final client = _CountingClient();
        clients.add(client);
        return client;
      },
    );
    final stale = owner.borrow('binding-a');

    owner.close(ifGeneration: stale.generation);
    expect(owner.borrowIfGeneration('binding-a', stale.generation), isNull);
    final rearmed = owner.borrow('binding-a');
    expect(owner.borrowIfGeneration('binding-a', stale.generation), isNull);
    owner.close(ifGeneration: stale.generation);

    expect(clients, hasLength(2));
    expect(clients.first.closeCalls, 1);
    expect(clients.last.closeCalls, 0);
    expect(owner.debugHasClient, isTrue);
    await expectLater(
      stale.client.send(
        http.Request('GET', Uri.parse('https://example.test/stale')),
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(clients.last.sendCalls, 0);

    owner.close(ifGeneration: rearmed.generation);
    owner.close(ifGeneration: rearmed.generation);

    expect(clients.first.closeCalls, 1);
    expect(clients.last.closeCalls, 1);
    expect(owner.debugHasClient, isFalse);
  });

  test('corrupt persisted sync state cannot trap startup in a loop', () async {
    final fixture = await _openRuntimeFixture('corrupt-state');
    addTearDown(fixture.dispose);
    final runtime = WebDavSyncRuntime.instance;
    final prefs = await SharedPreferences.getInstance();
    const corrupt =
        '{"version":2,"bindings":{},"namespaces":{},"future":"kept"}';
    await prefs.setString(WebDavSyncBindingStore.storageKey, corrupt);
    await ProfileDatabaseAdoptionGate.hold();

    await runtime.initialize().timeout(const Duration(seconds: 3));

    expect(ProfileDatabaseAdoptionGate.isHeld, isFalse);
    expect((await runtime.status()).localStateMissing, isTrue);
    expect(prefs.getString(WebDavSyncBindingStore.storageKey), corrupt);
  });

  test(
    'rollback runtime releases a purged adoption journal for recovery UI',
    () async {
      final fixture = await _openRuntimeFixture('missing-journal');
      addTearDown(fixture.dispose);

      final runtime = WebDavSyncRuntime.instance;
      const config = WebDavConfig(
        id: 'server',
        name: 'Server',
        baseUrl: 'https://example.test/dav',
        username: 'alice',
        password: 'secret',
      );
      var binding = await runtime.bindingStore.stageBinding(
        location: WebDavSyncFolderLocation.fromConfig(config, 'Family'),
        config: config,
        syncPassphrase: 'circle-secret',
      );
      binding = await runtime.bindingStore.markRootVerified(
        bindingId: binding.id,
        root: WebDavSyncRootDocument(
          circleId: 'circle-one',
          createdAt: DateTime.utc(2026, 9, 1),
          schemaFloor: 1,
          kdfSalt: Uint8List(16),
        ),
        markerBytes: const <int>[1, 2, 3],
      );
      await runtime.bindingStore.activateAndPromoteStaged(binding.id);
      await runtime.stateStore.update(
        binding.namespaceId,
        (state) => state.copyWith(
          circleToLocalProfiles: <String, String>{
            'profile-circle': fixture.adminId,
          },
          circleToLocalResources: const <String, String>{},
        ),
      );
      final journals = await fixture.support
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .cast<File>()
          .toList();
      expect(journals, isNotEmpty);
      for (final journal in journals) {
        await journal.delete();
      }
      await ProfileDatabaseAdoptionGate.hold();

      await runtime.initialize().timeout(const Duration(seconds: 3));

      expect(ProfileDatabaseAdoptionGate.isHeld, isFalse);
      final recovered = (await runtime.bindingStore.load()).activeBinding!;
      expect(recovered.lifecycle, WebDavSyncLifecycle.error);
      expect(recovered.requiresStateReconnect, isTrue);
    },
  );
}

final class _CountingClient extends http.BaseClient {
  int closeCalls = 0;
  int sendCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCalls++;
    throw http.ClientException('connection failed', request.url);
  }

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

final class _RuntimeFixture {
  const _RuntimeFixture({
    required this.temporary,
    required this.support,
    required this.registry,
    required this.adminId,
  });

  final Directory temporary;
  final Directory support;
  final ProfileRegistry registry;
  final String adminId;

  Future<void> dispose() async {
    WebDavSyncRuntime.instance.debugResetInitialization();
    WebDavSyncFeature.debugOverride = null;
    ProfileDatabaseAdoptionGate.debugReset();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporary.delete(recursive: true);
  }
}

Future<_RuntimeFixture> _openRuntimeFixture(String label) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WebDavSyncRuntime.instance.debugResetInitialization();
  ProfileDatabaseAdoptionGate.debugReset();
  ProfileRuntime.debugReset();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final temporary = await Directory.systemTemp.createTemp(
    'webdav-sync-runtime-$label-',
  );
  final documents = Directory(p.join(temporary.path, 'documents'));
  final support = Directory(p.join(temporary.path, 'support'));
  final cache = Directory(p.join(temporary.path, 'cache'));
  await documents.create(recursive: true);
  await support.create(recursive: true);
  await cache.create(recursive: true);
  AppStorage.debugOverride(
    documents: documents,
    support: support,
    cache: cache,
  );
  final registry = await ProfileRegistry.open(
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
  ProfileBootstrap.debugInstallRegistry(registry);
  ProfileRuntime.initializeCommitted(
    ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
  );
  DeviceKeyProvider.debugInstallCipher(
    MemoryDeviceSecretCipher(List<int>.filled(32, 7)),
  );
  WebDavSyncFeature.debugOverride = false;
  return _RuntimeFixture(
    temporary: temporary,
    support: support,
    registry: registry,
    adminId: admin.id,
  );
}
