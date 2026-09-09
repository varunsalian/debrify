import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_runtime.dart';

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

  testWidgets(
    'invalid selected configuration returns a failed application receipt',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final router = RemoteCommandRouter()..setNavigatorKey(navigator);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Receiver')),
        ),
      );
      const requestId = 'invalid-config-probe';
      Future<Map<String, dynamic>?> command(String kind, String data) async {
        final file = File('${root.path}/settings.gz');
        await RemoteTransferEncoding.writeCommand(
          file,
          RemoteCommand.config(kind, configData: data).toJson(),
        );
        return send(file, {'format': 'command-gzip-v1'});
      }

      Map<String, dynamic>? outcome;
      Object? failure;
      var finished = false;
      await tester.runAsync(() async {
        await StorageService.setInitialSetupComplete(true);
        await command(
          ConfigCommand.remoteTransferStart,
          remoteTransferRequestBody(requestId),
        );
        await command(
          ConfigCommand.pikpak,
          remoteTransferItemBody(requestId: requestId, payload: '{}'),
        );
        command(
          ConfigCommand.complete,
          remoteTransferRequestBody(
            requestId,
            expectedCommands: [ConfigCommand.pikpak],
          ),
        ).then(
          (value) {
            outcome = value;
            finished = true;
          },
          onError: (Object error) {
            failure = error;
            finished = true;
          },
        );
      });
      for (var i = 0; i < 60 && find.text('Import').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Import'), findsOneWidget);
      await tester.tap(find.text('Import'));
      for (var i = 0; i < 100 && !finished; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(failure, isNull);
      expect(finished, isTrue);
      expect(jsonDecode(outcome!['data'] as String)['ok'], isFalse);
      await tester.pump(const Duration(seconds: 10));
      router.setNavigatorKey(GlobalKey<NavigatorState>());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
