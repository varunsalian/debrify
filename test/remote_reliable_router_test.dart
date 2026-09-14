import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_channel_file.dart';
import 'package:debrify/services/remote_control/remote_chunked_send.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_reliable_transfer.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/remote_transfer_encoding.dart';
import 'package:debrify/services/remote_control/udp_command_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/local_backup/local_backup_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'profiles/avatar_fixtures.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_backup.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory root;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late RemoteReliableTransfer sender;
  late RemoteSession session;
  late int port;
  final state = RemoteControlState()..debugReliablePort = 0;
  final key = List<int>.generate(32, (i) => i);
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await state.debugResetForTesting();
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('remote-router-test-');
    final docs = await Directory('${root.path}/docs').create();
    final support = await Directory('${root.path}/support').create();
    final cache = await Directory('${root.path}/cache').create();
    AppStorage.debugOverride(documents: docs, support: support, cache: cache);
    registry = await ProfileRegistry.open(path: '${support.path}/profiles.db');
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => 250 - i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    final scope = ProfileScope(
      profileId: admin.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    ProfileRemoteLease.instance.authorize(admin, scope);
    RemoteCommandRouter().clearProfileSessionState();
    session = RemoteSession(
      sid: Uint8List.fromList(List<int>.filled(16, 42)),
      role: RemoteSessionRole.receiver,
      keys: SessionKeys(c2s: key, s2c: key, conf: key, sas: key),
      peerStaticKey: const [8],
      peerFingerprint: 'paired-phone',
      peerName: 'Phone',
      sasCode: '123456',
      establishedAt: DateTime.now(),
    )..authorized = true;
    final manager = RemoteSessionManager(
      loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
      deviceName: () => 'TV',
    );
    manager.sessions[session.sidB64] = session;
    state
      ..debugInstallSessionManager(manager)
      ..debugInstallOutboundSession(session, ip: '127.0.0.1')
      ..debugRememberPeer(session.peerFingerprint);
    port = await ProfileRuntime.withCapturedScope(
      scope,
      state.debugStartReliableReceiver,
    );
    sender = RemoteReliableTransfer(
      directory: Directory('${root.path}/sender'),
      receiveKey: (_, _) async => key,
      onReceive: (_) async {},
      pollInterval: const Duration(milliseconds: 10),
    );
    await sender.start(port: 0);
  });
  tearDown(() async {
    WebDavSyncRuntime.instance.debugResetInitialization();
    await sender.close();
    await state.debugResetForTesting();
    RemoteCommandRouter().clearProfileSessionState();
    ProfileRemoteLease.instance.revoke();
    await DebrifyTvDatabase.instance.closeScope();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, dynamic>?> send(
    File file,
    Map<String, dynamic> metadata,
  ) => sender.send(
    host: '127.0.0.1',
    port: port,
    sessionId: session.sidB64,
    key: key,
    file: file,
    metadata: metadata,
  );

  test(
    'receiver chooses a free port when the preferred port is occupied',
    () async {
      await state.debugResetForTesting();
      final occupied = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      state.debugReliablePort = occupied.port;
      try {
        final selected = await state.debugStartReliableReceiver();
        expect(selected, isNot(occupied.port));
        expect(selected, greaterThan(0));
      } finally {
        state.debugReliablePort = 0;
        await occupied.close(force: true);
      }
    },
  );

  test(
    'channel file travels through real controller, authorization and atomic import',
    () async {
      final db = await DebrifyTvDatabase.instance.database;
      await db.insert('tv_channels', {
        'channel_id': 'source',
        'name': 'Saved channel',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert('tv_channel_keywords', {
        'channel_id': 'source',
        'position': 0,
        'keyword': 'current',
      });
      final batch = db.batch();
      for (var i = 0; i < 1001; i++) {
        batch.insert('tv_cached_torrents', {
          'channel_id': 'source',
          'infohash': 'hash-${i.toString().padLeft(5, '0')}',
          'name': 'Title $i',
          'size_bytes': i + 1,
          'created_unix': 1,
          'seeders': 5,
          'leechers': 0,
          'completed': 1,
          'scraped_date': 1,
          'keywords_json': '["previous"]',
          'sources_json': '["engine"]',
          'added_at': i,
        });
      }
      await batch.commit(noResult: true);
      final file = File('${root.path}/channel.gz');
      await RemoteChannelFile.export('source', file);
      await db.delete('tv_cached_torrents');
      final result = await send(file, {
        'format': 'channel-records-v1',
        'requestId': 'channel-request',
      });
      expect(result!['command'], ConfigCommand.remoteTransferResult);
      expect(jsonDecode(result['data'] as String)['ok'], isTrue);
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM tv_cached_torrents',
        )).single['n'],
        1001,
      );
    },
  );

  test(
    'compressed settings and addons reach the same correlated import batch',
    () async {
      final router = RemoteCommandRouter();
      const requestId = 'settings-and-addons';
      Future<void> command(RemoteCommand value) async {
        final file = File('${root.path}/settings.gz');
        await RemoteTransferEncoding.writeCommand(file, value.toJson());
        await send(file, {'format': 'command-gzip-v1'});
      }

      await command(
        RemoteCommand.config(
          ConfigCommand.remoteTransferStart,
          configData: remoteTransferRequestBody(requestId),
        ),
      );
      await command(
        RemoteCommand.config(
          ConfigCommand.torbox,
          configData: remoteTransferItemBody(
            requestId: requestId,
            payload: 'synthetic-test-credential',
          ),
        ),
      );
      await command(
        RemoteCommand.addon(
          AddonCommand.install,
          manifestUrl: remoteTransferItemBody(
            requestId: requestId,
            payload: 'https://example.invalid/manifest.json',
          ),
        ),
      );
      expect(router.debugProfileTransferKeys, contains('torboxApiKey'));
      expect(
        router.debugProfilePayloadContainsExpected({
          ConfigCommand.torbox: 1,
          RemoteAction.addon: 1,
        }),
        isTrue,
      );
      // Retrying the same batch admission must preserve its received items.
      await command(
        RemoteCommand.config(
          ConfigCommand.remoteTransferStart,
          configData: remoteTransferRequestBody(requestId),
        ),
      );
      expect(
        router.debugProfilePayloadContainsExpected({
          ConfigCommand.torbox: 1,
          RemoteAction.addon: 1,
        }),
        isTrue,
      );
    },
  );

  testWidgets(
    'file-backed profile graph reaches confirmation and durable import',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      RemoteCommandRouter().setNavigatorKey(navigator);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Receiver')),
        ),
      );
      Future<Map<String, dynamic>?>? sending;
      var finished = false;
      Map<String, dynamic>? result;
      Object? failure;
      await tester.runAsync(() async {
        await StorageService.setInitialSetupComplete(true);
        final actor = await ProfileAuthorizationContext.capture(registry);
        await registry.createProfile(
          name: 'Second profile',
          role: UserProfileRole.child,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
        final packageService = ProfilePackageService(
          registry: registry,
          resources: ConnectionResourceService(
            registry: registry,
            cipher: cipher,
          ),
        );
        final resources = ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        );
        for (final type in [
          ConnectionResourceType.torbox,
          ConnectionResourceType.stremioAddon,
        ]) {
          await resources.create(
            context: await ProfileAuthorizationContext.capture(registry),
            type: type,
            label: 'Synthetic ${type.name}',
            publicConfig: {},
            secretConfig: type == ConnectionResourceType.torbox
                ? {'apiKey': 'synthetic-transfer-secret'}
                : {'manifestUrl': 'https://example.invalid/manifest.json'},
            bindingSlot: type.singletonCredentialBindingSlot,
          );
        }
        final staging = await LocalBackupScratch.create('remote-test-export');
        final exported = await LocalBackupExporter(service: packageService)
            .export(
              context: await ProfileAuthorizationContext.capture(registry),
              staging: staging,
              allProfiles: true,
              captureSync: (profiles, resources) async => WebDavSyncBackup(
                connection: {
                  'endpoint': 'https://example.invalid/dav',
                  'folder': '/sync',
                  'name': 'Test sync',
                  'username': 'synthetic-user',
                  'password': 'synthetic-password',
                  'passphrase': 'synthetic-passphrase',
                  'enabled': false,
                  'authority': base64Encode(
                    await WebDavSyncCodec().sealRoot(
                      passphrase: 'synthetic-passphrase',
                      circleId: 'test-circle',
                      createdAt: DateTime.utc(2026),
                      memoryKiB: 8,
                      iterations: 1,
                    ),
                  ),
                },
                profileIds: {'circle-admin': profiles[actor.profileId]!},
              ),
            );
        sending = send(exported.archive, {
          'format': 'profile-archive-v1',
          'requestId': 'graph-request',
        });
        sending!.then(
          (value) {
            result = value;
            finished = true;
          },
          onError: (Object error) {
            failure = error;
            finished = true;
          },
        );
      });
      for (
        var i = 0;
        i < 300 && find.text('Import profiles').evaluate().isEmpty && !finished;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(failure, isNull);
      expect(find.text('Import profiles'), findsOneWidget);
      await tester.tap(find.text('Import profiles'));
      await tester.pump();
      for (var i = 0; i < 1000 && !finished; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(failure, isNull);
      expect(finished, isTrue);
      expect(result!['command'], ConfigCommand.profileGraphResult);
      expect(jsonDecode(result!['data'] as String)['ok'], isTrue);
      await tester.runAsync(() async {
        expect(await registry.listProfiles(), hasLength(4));
        final snapshot = await WebDavSyncBindingStore().load();
        final binding = snapshot.stagedBinding!;
        expect(binding.circleId, 'test-circle');
        expect(binding.lifecycle, WebDavSyncLifecycle.rootVerified);
        final secrets = await WebDavSyncBindingStore().readSecrets(binding);
        expect(secrets.username, 'synthetic-user');
        expect(secrets.password, 'synthetic-password');
        final resources = await registry.listAllResources();
        expect(resources, hasLength(4));
        for (final resource in resources) {
          final sealed = (await registry.getSealedResourceSecret(resource.id))!;
          final decoded = jsonDecode(
            utf8.decode(
              await cipher.open(
                sealed.envelope,
                associatedData:
                    ConnectionResourceService.associatedDataForSecret(
                      resourceId: sealed.resourceId,
                      type: sealed.type,
                      ownerProfileId: sealed.ownerProfileId,
                      publicSchemaVersion: sealed.publicSchemaVersion,
                      payloadVersion: sealed.payloadVersion,
                    ),
              ),
            ),
          );
          expect(
            decoded,
            resource.type == ConnectionResourceType.torbox
                ? {'apiKey': 'synthetic-transfer-secret'}
                : {'manifestUrl': 'https://example.invalid/manifest.json'},
          );
        }
        await state.debugResetForTesting();
      });
      await tester.pumpAndSettle();
    },
  );

  test('persistent receiver uses the new profile after a switch', () async {
    final previous = ProfileRuntime.capture();
    final actor = await ProfileAuthorizationContext.capture(registry);
    final next = await registry.createProfile(
      name: 'New receiver',
      role: UserProfileRole.admin,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    await registry.setActiveProfile(next.id);
    final scope = ProfileScope(
      profileId: next.id,
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.publish(scope);
    ProfileRemoteLease.instance.revoke();
    ProfileRemoteLease.instance.authorize(next, scope);
    RemoteCommandRouter().clearProfileSessionState();
    expect(await state.debugStartReliableReceiver(), port);
    final file = File('${root.path}/switched-avatar.gz');
    await RemoteTransferEncoding.writeCommand(
      file,
      RemoteCommand.config(
        ConfigCommand.profileAvatar,
        configData: jsonEncode({
          'version': 1,
          'requestId': 'switched-avatar',
          'data': base64Encode(await paintPng(size: 32)),
        }),
      ).toJson(),
    );
    final result = await send(file, {'format': 'command-gzip-v1'});
    expect(result!['data'], 'profile_avatar:switched-avatar:ok');
    expect(
      ProfileAvatar.tryParse(
        (await registry.getProfile(next.id))!.avatarKey,
      )?.kind,
      ProfileAvatarKind.image,
    );
    expect(
      ProfileAvatar.tryParse(
        (await registry.getProfile(previous.profileId))!.avatarKey,
      )?.kind,
      isNot(ProfileAvatarKind.image),
    );
  });

  test('avatar command reports success only with a saved image', () async {
    final profileId = ProfileRuntime.capture().profileId;
    final file = File('${root.path}/avatar.gz');
    await RemoteTransferEncoding.writeCommand(
      file,
      RemoteCommand.config(
        ConfigCommand.profileAvatar,
        configData: jsonEncode({
          'version': 1,
          'requestId': 'avatar-request',
          'data': base64Encode(await paintPng(size: 32)),
        }),
      ).toJson(),
    );
    final result = await send(file, {'format': 'command-gzip-v1'});
    expect(result!['data'], 'profile_avatar:avatar-request:ok');
    final profile = (await registry.getProfile(profileId))!;
    expect(
      ProfileAvatar.tryParse(profile.avatarKey)?.kind,
      ProfileAvatarKind.image,
    );
    final avatars = Directory('${root.path}/docs/profiles/$profileId/avatars');
    expect(await avatars.list().length, 1);
  });

  test(
    'locked profile returns failure through receipt without modifying data',
    () async {
      ProfileRemoteLease.instance.revoke();
      final file = File('${root.path}/command.gz');
      await RemoteTransferEncoding.writeCommand(
        file,
        RemoteCommand.config(
          ConfigCommand.remoteTransferStart,
          configData: jsonEncode({'version': 1, 'requestId': 'locked-request'}),
        ).toJson(),
      );
      final result = await send(file, {'format': 'command-gzip-v1'});
      expect(result!['command'], ConfigCommand.remoteTransferResult);
      final outcome = jsonDecode(result['data'] as String);
      expect(outcome['requestId'], 'locked-request');
      expect(outcome['ok'], isFalse);
    },
  );
}
