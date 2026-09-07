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

/// Origin pin for the two dialogs `RemoteCommandRouter` raises out of its own
/// file: the undismissable busy dialog that covers a profile-graph import
/// (`_RouterBusyDialog`) and the v1 plaintext consent dialog raised by
/// `_presentLegacyConsent` / torn down by `_dismissLegacyConsent`.
///
/// Both are driven through the router's real public entry points against a
/// real `MaterialApp` whose navigator key the router holds — no source-text
/// greps, no re-implementation of the pinned bodies.
///
/// The queue *around* the consent dialog is already pinned by
/// `remote_transfer_bookkeeping_origin_pin_test.dart`; what is added here is
/// the dialog itself: its title, the peer address in its body, its two button
/// labels and which of them holds the default focus, that its barrier cannot
/// dismiss it, and that buffer expiry pops it without answering.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final router = RemoteCommandRouter();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;
  late Directory cache;
  late ProfileRegistry registry;
  late String adminId;
  late RemoteSession session;
  late RemoteSessionManager manager;
  late RemoteCommandContext peer;
  late List<RemoteCommand> outbound;
  late GlobalKey<NavigatorState> navigatorKey;
  late GlobalKey<ScaffoldMessengerState> messengerKey;

  RemoteSession buildSession() {
    final sid = Uint8List.fromList(List<int>.generate(16, (i) => i + 41));
    final keys = SessionKeys(
      c2s: List<int>.generate(32, (i) => i),
      s2c: List<int>.generate(32, (i) => 255 - i),
      conf: List<int>.filled(32, 5),
      sas: List<int>.filled(32, 6),
    );
    return RemoteSession(
      sid: sid,
      role: RemoteSessionRole.receiver,
      keys: keys,
      peerStaticKey: List<int>.filled(32, 2),
      peerFingerprint: 'peer-dialogs',
      peerName: 'Phone',
      sasCode: '654321',
      establishedAt: DateTime.now(),
    )..authorized = true;
  }

  setUp(() async {
    // The production dialog presenter, registered here because these tests
    // pump a bare `MaterialApp` rather than going through `main.dart`.
    router.setDialogs(const RemoteRouterDialogs());
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'router-dialogs-pin-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    cache = Directory(p.join(temporaryDirectory.path, 'cache'));
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
      // Past onboarding, so the import takes the ordinary path rather than
      // the bootstrap hand-off.
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

    session = buildSession();
    manager = RemoteSessionManager(
      loadStaticKeyPair: RemoteSessionCrypto.x25519.newKeyPair,
      deviceName: () => 'TV',
    );
    manager.sessions[session.sidB64] = session;

    outbound = <RemoteCommand>[];
    final state = RemoteControlState();
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
    final state = RemoteControlState();
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

  List<({String? requestId, bool ok, String message})> graphResults() => [
    for (final command in outbound)
      if (command.command == ConfigCommand.profileGraphResult)
        parseProfileGraphResultBody(command.data!)!,
  ];

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

  // ── the busy dialog over a profile-graph import ─────────────────────────
  //
  // `_RouterBusyDialog` is only reachable through the profile graph path, so
  // the pin sends a real authenticated `deviceGraph` package over the router's
  // public dispatch, accepts the confirmation, and then watches the busy
  // dialog for as long as the restore is suspended.
  group('router busy dialog', () {
    /// A real authenticated `deviceGraph` transport payload — the same shape
    /// a paired Admin phone puts on the wire.
    Future<String> graphPayload({
      int profiles = 2,
      String name = 'Imported',
    }) async {
      final sections = <String, dynamic>{
        for (var i = 0; i < profiles; i++)
          'section-$i': await PortableProfilePackage.buildSection(
            <String, Object?>{'theme_mode': 'restored-$i'},
          ),
      };
      return PortableProfilePackage.encodeAuthenticatedJson(
        PortableProfilePackage(
          mode: 'deviceGraph',
          createdAt: DateTime.utc(2026, 9, 1),
          profiles: <Map<String, dynamic>>[
            for (var i = 0; i < profiles; i++)
              <String, dynamic>{
                'backupId': 'profile-$i',
                'name': '$name $i',
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

    /// One turn of the REAL event loop, then a frame. The router's dialog
    /// awaits are chained onto futures created outside the fake clock (the
    /// isolate decode), so their continuations only run when the real loop
    /// turns; a plain `pump()` never delivers them.
    Future<void> realTurn(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    /// Runs the dispatch far enough (in real async) for the isolate decode and
    /// the authorization check to land, leaving the confirmation dialog up.
    Future<Future<void>> beginImport(WidgetTester tester, String data) async {
      late final Future<void> dispatch;
      await tester.runAsync(() async {
        dispatch = router.debugDispatchAndWait(
          RemoteAction.config,
          ConfigCommand.profileGraph,
          data,
          peer,
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump();
      return Future<Future<void>>.value(dispatch);
    }

    testWidgets('an accepted import is covered by an undismissable busy '
        'dialog until the restore finishes', (tester) async {
      await pumpHost(tester);
      final String payload;
      // Building the package runs an isolate; it needs real async too.
      payload = (await tester.runAsync(() => graphPayload()))!;

      final dispatch = await beginImport(tester, payload);
      expect(
        find.text('Import 2 profiles?'),
        findsOneWidget,
        reason: 'the confirmation precedes the busy dialog',
      );
      expect(find.text('Importing profiles…'), findsNothing);

      await tester.tap(find.text('Import profiles'));
      // Settling closes the confirmation, which is what lets the busy dialog
      // open on the next real turn; the restore behind it then parks on I/O
      // the fake clock never delivers.
      await tester.pumpAndSettle();
      await realTurn(tester);

      // The restore is suspended on real I/O the fake clock never delivers,
      // so the busy dialog stays up and can be inspected.
      expect(find.text('Importing profiles…'), findsOneWidget);
      final progress = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(progress, findsOneWidget);

      // Undismissable: the route refuses barrier dismissal, and the dialog's
      // own PopScope refuses a system back.
      final busyRoute = ModalRoute.of(
        tester.element(find.text('Importing profiles…')),
      )!;
      expect(busyRoute.barrierDismissible, isFalse);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(find.text('Importing profiles…'), findsOneWidget);
      final popScope = tester.widget<PopScope>(
        find
            .ancestor(
              of: find.text('Importing profiles…'),
              matching: find.byType(PopScope),
            )
            .first,
      );
      expect(popScope.canPop, isFalse);

      // Let the restore run to completion; the dialog closes itself.
      await tester.runAsync(() => dispatch);
      await tester.pumpAndSettle();
      expect(find.text('Importing profiles…'), findsNothing);
      expect(
        find.text('Import 2 profiles?'),
        findsNothing,
        reason: 'the confirmation was popped before the busy dialog opened',
      );
      // The dialog covered a real, successful restore rather than an early
      // failure that would make this pin vacuous.
      expect(graphResults().last.ok, isTrue);
      expect(graphResults().last.message, contains('imported 2 profiles'));
    });

    testWidgets('a declined import never raises the busy dialog', (
      tester,
    ) async {
      await pumpHost(tester);
      final payload = (await tester.runAsync(() => graphPayload(profiles: 1)))!;
      final dispatch = await beginImport(tester, payload);
      expect(find.text('Import 1 profiles?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await realTurn(tester);
      expect(find.text('Importing profiles…'), findsNothing);
      await tester.runAsync(() => dispatch);
      await tester.pumpAndSettle();

      expect(find.text('Importing profiles…'), findsNothing);
      expect(graphResults().last.message, 'Declined on the TV');
    });

    testWidgets('a failing restore still takes the busy dialog down', (
      tester,
    ) async {
      await pumpHost(tester);
      // The package decodes (its integrity and section digests are sound) but
      // the coordinator refuses the over-long profile name, so
      // `restoreDeviceGraph` throws AFTER the busy dialog is on screen. The
      // `done` notifier fires from the finally arm, so the dialog must still
      // close and the failure snackbar must be the only thing left.
      final payload = (await tester.runAsync(
        () => graphPayload(profiles: 1, name: 'N' * 100),
      ))!;

      final dispatch = await beginImport(tester, payload);
      await tester.tap(find.text('Import profiles'));
      await tester.pumpAndSettle();
      await realTurn(tester);
      expect(find.text('Importing profiles…'), findsOneWidget);

      await tester.runAsync(() => dispatch);
      await tester.pumpAndSettle();

      expect(find.text('Importing profiles…'), findsNothing);
      expect(
        graphResults().last.message,
        'Import failed on the TV; nothing was changed there',
      );
    });
  });

  // ── the v1 (plaintext) consent dialog ───────────────────────────────────
  group('legacy consent dialog', () {
    setUp(() {
      // Plaintext never clears the committed-profile gate, so the legacy
      // consent path only exists on a device without a committed profile.
      ProfileRemoteLease.instance.revoke();
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
    });

    Future<void> plaintext(WidgetTester tester, String sourceIp) async {
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.realDebrid,
        'rd-secret',
        RemoteCommandContext(
          encrypted: false,
          authorized: false,
          sourceIp: sourceIp,
        ),
      );
      await tester.pump();
    }

    Future<void> drainPendingConsent(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
    }

    testWidgets('names the peer and offers Deny before Allow', (tester) async {
      await pumpHost(tester);
      await plaintext(tester, '192.168.7.21');

      expect(find.text('Incoming settings'), findsOneWidget);
      // The address is inside the warning body, not the title.
      expect(
        find.textContaining('The device at 192.168.7.21 wants to send'),
        findsOneWidget,
      );
      expect(find.textContaining('UNENCRYPTED connection'), findsOneWidget);

      final deny = find.widgetWithText(FilledButton, 'Deny');
      final allow = find.widgetWithText(TextButton, 'Allow');
      expect(deny, findsOneWidget);
      expect(allow, findsOneWidget);
      // Deny is the emphasised action AND the one holding first focus, so a
      // TV remote's OK button on an unattended set refuses the transfer.
      expect(tester.widget<FilledButton>(deny).autofocus, isTrue);
      expect(tester.widget<TextButton>(allow).autofocus, isFalse);
      final denyCentre = tester.getCenter(deny);
      final allowCentre = tester.getCenter(allow);
      expect(
        denyCentre.dx,
        lessThan(allowCentre.dx),
        reason: 'Deny is laid out ahead of Allow',
      );

      await drainPendingConsent(tester);
    });

    testWidgets('the barrier cannot dismiss it', (tester) async {
      await pumpHost(tester);
      await plaintext(tester, '192.168.7.22');
      expect(find.text('Incoming settings'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        find.text('Incoming settings'),
        findsOneWidget,
        reason: 'barrierDismissible is false',
      );

      await drainPendingConsent(tester);
    });

    testWidgets('buffer expiry pops it without an answer', (tester) async {
      await pumpHost(tester);
      await plaintext(tester, '192.168.7.23');
      expect(find.text('Incoming settings'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.text('Incoming settings'), findsNothing);
      // A dismissal is not a Deny: the explicit-refusal notice stays away.
      expect(find.text('Incoming settings were blocked'), findsNothing);

      // And the dialog is really gone rather than merely hidden: a second
      // plaintext burst raises a fresh one.
      await plaintext(tester, '192.168.7.24');
      expect(find.text('Incoming settings'), findsOneWidget);
      expect(
        find.textContaining('The device at 192.168.7.24 wants to send'),
        findsOneWidget,
      );
      await drainPendingConsent(tester);
    });
  });
}
