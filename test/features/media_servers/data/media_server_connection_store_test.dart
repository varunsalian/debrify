import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/media_servers/data/media_server_connection_store.dart';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

MediaServerAccount _plex({String deviceId = 'debrifyclient0123456789'}) =>
    MediaServerAccount(
      kind: MediaServerKind.plex,
      baseUrl: 'https://home.plex.direct:32400/',
      userId: 'user-uuid-1',
      token: 'server-token-0001',
      serverId: 'server-1',
      deviceId: deviceId,
      connections: const [
        MediaServerConnection(uri: 'https://home.plex.direct:32400/'),
        MediaServerConnection(
          uri: 'https://relay.plex.direct:8443/',
          relay: true,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ProfileRegistry registry;
  late ConnectionResourceService resources;
  late String admin;
  late String member;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    temp = await Directory.systemTemp.createTemp('media-server-store-test-');
    registry = await ProfileRegistry.open(path: '${temp.path}/profiles.db');
    admin = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    member = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: admin,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(List.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    await registry.close();
    await temp.delete(recursive: true);
  });

  Future<List<ConnectionResource>> servers(String profileId) async =>
      (await registry.listGrantedResources(
        profileId,
      )).where((r) => r.type == ConnectionResourceType.mediaServer).toList();

  Future<Map<String, dynamic>> secret(ConnectionResource resource) async =>
      resources.resolveSecretForUse(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        feature: ProfileFeature.cloud,
      );

  Future<void> switchTo(String profileId) async {
    await registry.setActiveProfile(profileId);
    ProfileRuntime.publish(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 2),
    );
  }

  test(
    'a Plex connection is saved with its kind and allowed addresses',
    () async {
      final ticket = await MediaServerConnectionStore.begin(
        kind: MediaServerKind.plex,
      );
      await MediaServerConnectionStore.savePlex(ticket, _plex(), '');

      final saved = (await servers(admin)).single;
      expect(saved.label, 'Plex');
      expect(saved.publicConfig['accountLabel'], 'Plex');
      final stored = MediaServerAccount.fromJson(await secret(saved));
      expect(stored.kind, MediaServerKind.plex);
      expect(stored.connections.map((c) => (c.uri, c.relay)), [
        ('https://home.plex.direct:32400/', false),
        ('https://relay.plex.direct:8443/', true),
      ]);
    },
  );

  test('a profile switch between sign-in and save writes nothing', () async {
    final ticket = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
    );
    await switchTo(member);

    await expectLater(
      MediaServerConnectionStore.savePlex(ticket, _plex(), 'Den'),
      throwsA(anything),
    );
    expect(await servers(admin), isEmpty);
    expect(await servers(member), isEmpty);
  });

  test('reconnecting keeps the kind and the device id', () async {
    final first = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
    );
    await MediaServerConnectionStore.savePlex(first, _plex(), 'Den');
    final resource = (await servers(admin)).single;

    final again = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
      replaceId: resource.id,
    );
    expect(again.reconnecting, isTrue);
    expect(
      await MediaServerConnectionStore.previousDeviceId(again),
      'debrifyclient0123456789',
    );
    await expectLater(
      MediaServerConnectionStore.begin(
        kind: MediaServerKind.jellyfin,
        replaceId: resource.id,
      ),
      throwsA(
        isA<MediaServerException>().having(
          (e) => e.message,
          'message',
          contains('different server type'),
        ),
      ),
    );
    await MediaServerConnectionStore.savePlex(
      again,
      _plex(deviceId: 'debrifyclient0123456789'),
      'ignored on reconnect',
    );
    final updated = (await servers(admin)).single;
    expect(updated.label, 'Den');
    expect(updated.publicConfig['accountLabel'], 'Plex');
  });

  test('a connection changed during sign-in is not overwritten', () async {
    final first = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
    );
    await MediaServerConnectionStore.savePlex(first, _plex(), 'Den');
    final resource = (await servers(admin)).single;
    final older = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
      replaceId: resource.id,
    );
    final newer = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
      replaceId: resource.id,
    );
    // A different sign-in (another token) actually changes the secret.
    await MediaServerConnectionStore.savePlex(
      newer,
      _plex(deviceId: 'debrifyclient9999999999'),
      '',
    );
    // Refused: any credential update also moves the profile's authorization
    // revision, so the ticket's profile check rejects the older save before
    // the resource-revision check is reached. Either way the newer sign-in
    // is kept.
    await expectLater(
      MediaServerConnectionStore.savePlex(older, _plex(), ''),
      throwsA(anything),
    );
    final kept = MediaServerAccount.fromJson(
      await secret((await servers(admin)).single),
    );
    expect(kept.deviceId, 'debrifyclient9999999999');
  });

  test(
    'a connection without a known type reconnects as Jellyfin only',
    () async {
      final created = await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.mediaServer,
        label: 'Living room',
        publicConfig: {'accountLabel': 'Living room'},
        secretConfig: {'kind': 'jellyfin'},
      );
      final ticket = await MediaServerConnectionStore.begin(
        kind: MediaServerKind.jellyfin,
        replaceId: created.id,
      );
      expect(ticket.reconnecting, isTrue);
      await expectLater(
        MediaServerConnectionStore.begin(
          kind: MediaServerKind.plex,
          replaceId: created.id,
        ),
        throwsA(isA<MediaServerException>()),
      );
    },
  );

  test('only Plex accounts can be saved through the Plex path', () async {
    final ticket = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.jellyfin,
    );
    await expectLater(
      MediaServerConnectionStore.savePlex(ticket, _plex(), ''),
      throwsA(isA<MediaServerException>()),
    );
    expect(await servers(admin), isEmpty);
  });

  group('account JSON', () {
    test('Jellyfin and Emby secrets keep exactly their old keys', () {
      const jellyfin = MediaServerAccount(
        kind: MediaServerKind.jellyfin,
        baseUrl: 'https://media.example/',
        userId: 'u',
        token: 't',
        serverId: 's',
        deviceId: 'd',
      );
      expect(
        jsonEncode(jellyfin.toJson()),
        jsonEncode({
          'kind': 'jellyfin',
          'baseUrl': 'https://media.example/',
          'userId': 'u',
          'token': 't',
          'serverId': 's',
          'deviceId': 'd',
        }),
      );
      expect(
        MediaServerAccount.fromJson(jellyfin.toJson()).connections,
        isEmpty,
      );
    });

    test('a Plex secret round-trips its addresses', () {
      final account = _plex();
      final copy = MediaServerAccount.fromJson(
        jsonDecode(jsonEncode(account.toJson())) as Map<String, dynamic>,
      );
      expect(copy.kind, MediaServerKind.plex);
      expect(copy.connections.map((c) => c.toJson()), [
        {'uri': 'https://home.plex.direct:32400/'},
        {'uri': 'https://relay.plex.direct:8443/', 'relay': true},
      ]);
      expect(
        copy.withBaseUrl('https://relay.plex.direct:8443/').usesRelay,
        isTrue,
      );
      expect(copy.usesRelay, isFalse);
    });

    test(
      'sync sees an unchanged Plex secret as unchanged, and order as meaningful',
      () {
        final account = _plex();
        final decoded = jsonDecode(jsonEncode(account.toJson()));
        expect(
          WebDavSyncCodec.canonicalJson(decoded),
          WebDavSyncCodec.canonicalJson(account.toJson()),
        );
        final reordered = MediaServerAccount(
          kind: account.kind,
          baseUrl: account.baseUrl,
          userId: account.userId,
          token: account.token,
          serverId: account.serverId,
          deviceId: account.deviceId,
          connections: account.connections.reversed.toList(),
        );
        expect(
          WebDavSyncCodec.canonicalJson(reordered.toJson()),
          isNot(WebDavSyncCodec.canonicalJson(account.toJson())),
        );
      },
    );
  });
}
