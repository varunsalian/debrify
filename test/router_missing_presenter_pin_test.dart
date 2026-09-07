import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_remote_lease.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_chunked_send.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/udp_command_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/remote/remote_router_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression pin for the router's missing-presenter policy.
///
/// `RemoteCommandRouter` raises three dialogs through a `RouterDialogs`
/// presenter that `main.dart` registers beside the navigator key. This file
/// never registers one up front (each test file runs in its own isolate, so
/// the singleton starts bare) and pins what every public entry does in that
/// state, before any state change:
///
///  * a `pair/request` still answers the phone and the gate keeps its code,
///    but no dialog is drawn (the origin's no-navigator outcome);
///  * a profile-graph import is refused to the sender before the
///    confirmation dialog and before any restore work, with the same
///    result the origin sends when no screen is open;
///  * a v1 plaintext packet takes the consent queue's headless branch and
///    latches nothing: registering the presenter afterwards and resending
///    raises the dialog, which a latched queue could never do.
///
/// Test order is load-bearing: the consent test registers the production
/// presenter at its end to prove the queue is not latched, and the router
/// exposes no unregister, so it runs last. Same harnesses as
/// `router_pairing_fallback_origin_pin_test.dart` and
/// `router_dialogs_origin_pin_test.dart`, driven through the same real entry
/// points against a real `MaterialApp`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final router = RemoteCommandRouter();
  // Built in the real zone on purpose; see the pairing pin.
  final state = RemoteControlState();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late GlobalKey<NavigatorState> navigatorKey;
  late GlobalKey<ScaffoldMessengerState> messengerKey;
  late List<RemoteCommand> outbound;

  Future<void> pumpHost(WidgetTester tester) async {
    navigatorKey = GlobalKey<NavigatorState>();
    messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    router.setNavigatorKey(navigatorKey);
    router.setScaffoldMessengerKey(messengerKey);
  }

  SessionKeys buildKeys(int seed) => SessionKeys(
    c2s: List<int>.generate(32, (i) => i),
    s2c: List<int>.generate(32, (i) => 255 - i),
    conf: List<int>.filled(32, seed),
    sas: List<int>.filled(32, 6),
  );

  group('pairing fallback without a presenter', () {
    late RemoteSession session;
    late RemoteSessionManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      outbound = <RemoteCommand>[];
      session = RemoteSession(
        sid: Uint8List.fromList(List<int>.generate(16, (i) => i + 41)),
        role: RemoteSessionRole.receiver,
        keys: buildKeys(41),
        peerStaticKey: List<int>.filled(32, 2),
        peerFingerprint: 'peer-pairing',
        peerName: 'Phone',
        sasCode: '654321',
        establishedAt: DateTime.now(),
      );
      manager = RemoteSessionManager(
        loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
        deviceName: () => 'TV',
      );
      manager.sessions[session.sidB64] = session;
      router.clearProfileSessionState();
    });

    tearDown(() async {
      await state.debugResetForTesting();
      router.clearProfileSessionState();
      ProfileRuntime.debugReset();
    });

    Future<PairingGate> startReceiver(WidgetTester tester) async {
      await tester.runAsync(() => state.startTvListener('TV'));
      state.debugInstallSessionManager(manager);
      state.debugInstallOutboundSession(session, ip: '10.4.4.9');
      state.debugCommandSealer = (_, commandJson) async {
        outbound.add(RemoteCommand.fromJson(commandJson));
        return <String, dynamic>{'type': 'ecmd', 'ct': 'sealed'};
      };
      state.debugRawSender = (_, _, _) => true;
      return state.pairingGate!;
    }

    testWidgets('a request is answered and the gate keeps the code, but no '
        'dialog is drawn and nothing is latched', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      expect(gate.hasPresenter, isFalse, reason: 'no panel mounted');

      await tester.runAsync(
        () => router.handlePairMessage(
          state,
          session,
          PairCommand.request,
          null,
        ),
      );
      await tester.pumpAndSettle();

      final replies = [
        for (final command in outbound)
          if (command.action == RemoteAction.pair) command,
      ];
      expect(replies.single.command, PairCommand.challenge);
      expect(gate.current!.code, '654321');
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // The gate is still the authority: cancelling it clears the request
      // the router never drew, so nothing is stuck behind a missing dialog.
      gate.cancel();
      await tester.pumpAndSettle();
      expect(gate.current, isNull);
    });
  });

  group('profile-graph import and v1 consent without a presenter', () {
    late Directory temporaryDirectory;
    late ProfileRegistry registry;
    late String adminId;
    late RemoteSession session;
    late RemoteSessionManager manager;
    late RemoteCommandContext peer;

    setUp(() async {
      ProfileRuntime.debugReset();
      DeviceKeyProvider.debugReset();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'router-missing-presenter-pin-',
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
        policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
        setupComplete: true,
      );
      adminId = admin.id;
      await registry.commitBootstrap(
        activeProfileId: adminId,
        migratedLegacyInstall: false,
      );
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (i) => 250 - i),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);
      ProfileBootstrap.debugInstallRegistry(registry);
      final scope = ProfileScope(
        profileId: adminId,
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      ProfileRemoteLease.instance.authorize(
        (await registry.getProfile(adminId))!,
        scope,
      );

      session = RemoteSession(
        sid: Uint8List.fromList(List<int>.generate(16, (i) => i + 41)),
        role: RemoteSessionRole.receiver,
        keys: buildKeys(5),
        peerStaticKey: List<int>.filled(32, 2),
        peerFingerprint: 'peer-dialogs',
        peerName: 'Phone',
        sasCode: '654321',
        establishedAt: DateTime.now(),
      )..authorized = true;
      manager = RemoteSessionManager(
        loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
        deviceName: () => 'TV',
      );
      manager.sessions[session.sidB64] = session;

      outbound = <RemoteCommand>[];
      state.debugInstallSessionManager(manager);
      state.debugInstallOutboundSession(session, ip: '10.2.2.7');
      state.debugCommandSealer = (_, commandJson) async {
        outbound.add(RemoteCommand.fromJson(commandJson));
        return <String, dynamic>{'type': 'ecmd', 'ct': 'sealed'};
      };
      state.debugRawSender = (_, _, _) => true;

      peer = RemoteCommandContext(
        encrypted: true,
        authorized: true,
        sidB64: session.sidB64,
        peerFingerprint: 'peer-dialogs',
        peerName: 'Phone',
      );
      router.clearProfileSessionState();
    });

    tearDown(() async {
      state.debugCommandSealer = null;
      state.debugRawSender = null;
      router.clearProfileSessionState();
      ProfileRemoteLease.instance.revoke();
      await DebrifyTvDatabase.instance.closeScope();
      IptvMediaStore.debugResetMigration();
      ProfileRuntime.debugReset();
      ProfileBootstrap.debugInstallRegistry(null);
      DeviceKeyProvider.debugReset();
      AppStorage.debugReset();
      await registry.close();
      await temporaryDirectory.delete(recursive: true);
    });

    Future<String> graphPayload() async {
      final sections = <String, dynamic>{
        for (var i = 0; i < 2; i++)
          'section-$i': await PortableProfilePackage.buildSection(
            <String, Object?>{'theme_mode': 'restored-$i'},
          ),
      };
      return PortableProfilePackage.encodeAuthenticatedJson(
        PortableProfilePackage(
          mode: 'deviceGraph',
          createdAt: DateTime.utc(2026, 9, 1),
          profiles: <Map<String, dynamic>>[
            for (var i = 0; i < 2; i++)
              <String, dynamic>{
                'backupId': 'profile-$i',
                'name': 'Imported $i',
                'role': UserProfileRole.member.name,
                'policy': ProfilePolicy.defaultsFor(
                  UserProfileRole.member,
                ).encode(),
                'preferencesSection': 'section-$i',
              },
          ],
          resources: const <Map<String, dynamic>>[],
          sections: sections,
          omissions: const <String, dynamic>{},
        ),
      );
    }

    List<({String? requestId, bool ok, String message})> graphResults() => [
      for (final command in outbound)
        if (command.command == ConfigCommand.profileGraphResult)
          parseProfileGraphResultBody(command.data!)!,
    ];

    testWidgets('an import is refused to the sender before the confirmation '
        'and before any restore work', (tester) async {
      await pumpHost(tester);
      final payload = (await tester.runAsync(graphPayload))!;
      // Registry reads are real I/O the fake clock never delivers; run them,
      // and the dispatch (isolate decode, sealed reply), on the real loop.
      final before = (await tester.runAsync(() => registry.listProfiles()))!;

      // Same shape as the busy-dialog pin's `beginImport`: run the dispatch
      // far enough on the real loop for the decode and the checks to land,
      // without awaiting it, so a wrong branch that opens the confirmation
      // dialog fails the assertions below instead of hanging on the dialog.
      late final Future<void> dispatch;
      await tester.runAsync(() async {
        dispatch = router.debugDispatchAndWait(
          RemoteAction.config,
          ConfigCommand.profileGraph,
          payload,
          peer,
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump();

      expect(find.text('Import 2 profiles?'), findsNothing);
      expect(find.text('Importing profiles…'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // The refusal goes out on every channel the origin reports on; each
      // copy is the same "no screen" result, never a success.
      final results = graphResults();
      expect(results, isNotEmpty);
      expect(results.map((r) => r.ok).toSet(), {false});
      expect(results.map((r) => r.message).toSet(), {
        'Open the Debrify screen on the TV, then resend',
      });
      // Nothing restored: the registry still holds only the admin profile.
      final after = (await tester.runAsync(() => registry.listProfiles()))!;
      expect(after.map((e) => e.id), before.map((e) => e.id));
      expect(after, hasLength(1));
      // The refusal completed the dispatch; nothing is left waiting on UI.
      await tester.runAsync(
        () => dispatch.timeout(const Duration(seconds: 5)),
      );
    });

    // Runs last: it registers the production presenter to prove the queue
    // did not latch, and the router exposes no unregister.
    testWidgets('a plaintext packet latches nothing: once a presenter exists '
        'the next packet raises the consent dialog', (tester) async {
      ProfileRemoteLease.instance.revoke();
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      await pumpHost(tester);

      Future<void> plaintext() async {
        await router.debugDispatchAndWait(
          RemoteAction.config,
          ConfigCommand.realDebrid,
          'rd-secret',
          const RemoteCommandContext(
            encrypted: false,
            authorized: false,
            sourceIp: '192.168.7.21',
          ),
        );
        await tester.pump();
      }

      await plaintext();
      await tester.pumpAndSettle();
      expect(find.text('Incoming settings'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      router.setDialogs(const RemoteRouterDialogs());
      await plaintext();
      await tester.pumpAndSettle();
      expect(
        find.text('Incoming settings'),
        findsOneWidget,
        reason: 'a latched queue would have swallowed this packet',
      );
      expect(
        find.textContaining('The device at 192.168.7.21 wants to send'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Deny'));
      await tester.pumpAndSettle();
      expect(find.text('Incoming settings'), findsNothing);
      // Drain the buffer expiry timer the first packet armed.
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
    });
  });
}
