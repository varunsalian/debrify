import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Origin pin for the v4 transfer bookkeeping inside `RemoteCommandRouter`:
/// the `_activeRemoteTransfer*` transaction (open / record / expected-manifest
/// / wrapped-item unwrapping) and the `_remoteTransferOutcomes` cache with the
/// best-effort result reporters that feed it
/// (`_reportRemoteTransferResultBestEffort`,
/// `_reportAddonTransferResultBestEffort`,
/// `_reportCompleteTransferResultBestEffort`).
///
/// Everything is driven through the router's public entry points and observed
/// on the wire through `RemoteControlState`'s sealer seam — no source-text
/// greps, no re-implementation of the pinned bodies.
///
/// ORDER MATTERS in the first group: the router's "recent authorized config
/// work" stamp is process-wide singleton state with a ten-minute window, so
/// the completions that must look unsolicited run before anything stamps it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final router = RemoteCommandRouter();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late RemoteSession session;
  late RemoteSessionManager manager;
  late RemoteCommandContext peer;
  late List<RemoteCommand> outbound;

  RemoteSession buildSession() {
    final sid = Uint8List.fromList(List<int>.generate(16, (i) => i + 31));
    final keys = SessionKeys(
      c2s: List<int>.generate(32, (i) => i),
      s2c: List<int>.generate(32, (i) => 255 - i),
      conf: List<int>.filled(32, 7),
      sas: List<int>.filled(32, 9),
    );
    return RemoteSession(
      sid: sid,
      role: RemoteSessionRole.receiver,
      keys: keys,
      peerStaticKey: List<int>.filled(32, 3),
      peerFingerprint: 'peer-book',
      peerName: 'Phone',
      sasCode: '123456',
      establishedAt: DateTime.now(),
    )..authorized = true;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'remote-transfer-bookkeeping-pin-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: true,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    final scope = ProfileScope(
      profileId: admin.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    ProfileRemoteLease.instance.authorize(
      (await registry.getProfile(admin.id))!,
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
    state.debugInstallOutboundSession(session, ip: '10.1.1.9');
    state.debugCommandSealer = (_, commandJson) async {
      outbound.add(RemoteCommand.fromJson(commandJson));
      return <String, dynamic>{'type': 'ecmd', 'ct': 'sealed'};
    };
    state.debugRawSender = (_, _, _) => true;

    peer = RemoteCommandContext(
      encrypted: true,
      authorized: true,
      sidB64: session.sidB64,
      peerFingerprint: 'peer-book',
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
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  List<({String requestId, bool ok, String message})> transferResults() => [
    for (final command in outbound)
      if (command.command == ConfigCommand.remoteTransferResult)
        parseRemoteTransferResultBody(command.data!)!,
  ];

  List<({String requestId, bool ok})> addonResults() => [
    for (final command in outbound)
      if (command.command == ConfigCommand.addonTransferResult)
        parseAddonTransferResultBody(command.data!)!,
  ];

  Future<void> start(String requestId, List<String> expected) =>
      router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.remoteTransferStart,
        remoteTransferRequestBody(requestId, expectedCommands: expected),
        peer,
      );

  Future<void> item(String requestId, String command, String payload) =>
      router.debugDispatchAndWait(
        RemoteAction.config,
        command,
        remoteTransferItemBody(requestId: requestId, payload: payload),
        peer,
      );

  Future<void> complete(String requestId, List<String> expected) =>
      router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.complete,
        remoteTransferRequestBody(requestId, expectedCommands: expected),
        peer,
      );

  // ── completions the receiver refuses still get an answer ────────────────
  //
  // A `complete` that no recent authorized config work backs is a LAN
  // denial-of-service (it can restart the app), so it is refused — but the
  // sender is still told, on the channel its request body implies.
  group('refused completions (before any authorized activity)', () {
    test(
      'an unsolicited completion is refused on the transfer channel',
      () async {
        await complete('rq-unsolicited', const <String>[]);

        final results = transferResults();
        expect(results, isNotEmpty);
        expect(results.first.requestId, 'rq-unsolicited');
        expect(results.first.ok, isFalse);
        expect(
          results.first.message,
          'The TV rejected the transfer completion',
        );
        // The result is UDP: it goes out three times so one lost datagram
        // cannot turn an answered transfer into a timeout on the phone.
        expect(results.length, 3);
      },
    );

    test(
      'a bare request id is answered on the addon channel instead',
      () async {
        await router.debugDispatchAndWait(
          RemoteAction.config,
          ConfigCommand.complete,
          'addon-req-42',
          peer,
        );

        expect(transferResults(), isEmpty);
        final results = addonResults();
        expect(results, isNotEmpty);
        expect(results.first.requestId, 'addon-req-42');
        expect(results.first.ok, isFalse);
        expect(results.length, 3);
      },
    );

    test('an over-long bare request id is not reported at all', () async {
      await router.debugDispatchAndWait(
        RemoteAction.config,
        ConfigCommand.complete,
        'a' * 129,
        peer,
      );
      expect(outbound, isEmpty);
    });

    test('an unauthorized session is never sent a result', () async {
      session.authorized = false;
      await complete('rq-unauth', const <String>[]);
      expect(outbound, isEmpty);
    });

    test('a throwing transport never escapes the report', () async {
      RemoteControlState().debugRawSender = (_, _, _) =>
          throw const SocketException('no route to host');

      await expectLater(complete('rq-throws', const <String>[]), completes);
      // The attempt was made — and swallowed — three times.
      expect(
        outbound.where((c) => c.command == ConfigCommand.remoteTransferResult),
        hasLength(3),
      );
    });
  });

  group('v4 transfer transaction', () {
    // ── the open transaction gates wrapped item bodies ────────────────────
    test(
      'a wrapped item is unwrapped only inside its own transaction',
      () async {
        await start('rq-open', const [ConfigCommand.realDebrid]);

        // A wrapped body naming a DIFFERENT request is not part of the open
        // transaction and is dropped whole — never staged as a raw payload.
        await item('rq-other', ConfigCommand.realDebrid, 'foreign-secret');
        expect(
          router.debugProfileTransferKeys,
          isNot(contains('realDebridApiKey')),
        );

        await item('rq-open', ConfigCommand.realDebrid, 'mine-secret');
        expect(
          router.debugProfileTransferValue('realDebridApiKey'),
          'mine-secret',
        );
      },
    );

    test(
      'a raw (unwrapped) item is refused while a transaction is open',
      () async {
        await start('rq-raw', const [ConfigCommand.realDebrid]);
        await router.debugDispatchAndWait(
          RemoteAction.config,
          ConfigCommand.realDebrid,
          'legacy-raw-secret',
          peer,
        );
        expect(
          router.debugProfileTransferKeys,
          isNot(contains('realDebridApiKey')),
          reason: 'a non-transactional body cannot join an open transaction',
        );
      },
    );

    // ── the expected manifest is counted per received command ─────────────
    test(
      'an unmet manifest reports the shortfall back to the sender',
      () async {
        await start('rq-short', const [
          ConfigCommand.realDebrid,
          ConfigCommand.torbox,
        ]);
        await item('rq-short', ConfigCommand.realDebrid, 'rd-secret');
        await complete('rq-short', const [
          ConfigCommand.realDebrid,
          ConfigCommand.torbox,
        ]);

        final results = transferResults();
        expect(results, isNotEmpty);
        expect(results.first.requestId, 'rq-short');
        expect(results.first.ok, isFalse);
        expect(
          results.first.message,
          'Some configuration packets did not reach the TV',
        );
        expect(results.length, 3);
      },
    );

    test('a satisfied manifest is handed to the apply step', () async {
      await start('rq-full', const [ConfigCommand.realDebrid]);
      await item('rq-full', ConfigCommand.realDebrid, 'rd-secret-applied');
      await complete('rq-full', const [ConfigCommand.realDebrid]);

      // Bookkeeping is satisfied, so the completion is NOT rejected as an
      // incomplete manifest — it reaches the profile commit step, which in a
      // headless harness (no navigator for the confirmation) declines. What
      // is pinned here is that the manifest check passed it through.
      final results = transferResults();
      expect(results, isNotEmpty);
      expect(results.first.requestId, 'rq-full');
      expect(results.first.ok, isFalse);
      expect(results.first.message, 'The TV did not apply the configuration');
      expect(
        results.first.message,
        isNot('Some configuration packets did not reach the TV'),
      );
    });

    // ── the outcome cache answers a retried completion ────────────────────
    test('a retried completion replays the cached outcome verbatim', () async {
      await start('rq-cache', const [ConfigCommand.realDebrid]);
      await complete('rq-cache', const [ConfigCommand.realDebrid]);
      final first = transferResults();
      expect(first.first.ok, isFalse);
      expect(
        first.first.message,
        'Some configuration packets did not reach the TV',
      );

      // The sender retries. Even though the transaction is re-opened and this
      // time fully satisfied — which on a fresh request id reports success —
      // the retained outcome answers instead, so one payload is never applied
      // twice on a lost-ack retry.
      outbound.clear();
      await start('rq-cache', const [ConfigCommand.realDebrid]);
      await item('rq-cache', ConfigCommand.realDebrid, 'rd-secret-retry');
      await complete('rq-cache', const [ConfigCommand.realDebrid]);

      final replayed = transferResults();
      expect(replayed, isNotEmpty);
      expect(replayed.first.requestId, 'rq-cache');
      expect(replayed.first.ok, isFalse);
      expect(
        replayed.first.message,
        'Some configuration packets did not reach the TV',
      );
    });
  });

  // ── the v1 (plaintext) consent queue ────────────────────────────────────
  //
  // A pre-encryption phone's credentials cannot be authenticated, so its
  // packets are parked and the user answers for the whole burst at once.
  group('legacy consent queue', () {
    late GlobalKey<NavigatorState> navigatorKey;
    late GlobalKey<ScaffoldMessengerState> messengerKey;
    late List<String> seen;

    void handler(String action, String command, String? data) =>
        seen.add('$action/$command');

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

    setUp(() {
      // Plaintext never clears the committed-profile gate, so the legacy
      // queue only exists on a device that has not committed one.
      ProfileRemoteLease.instance.revoke();
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      seen = <String>[];
      router.addHandler(handler);
    });

    tearDown(() {
      router.removeHandler(handler);
    });

    Future<void> plaintext(
      WidgetTester tester,
      String command,
      String? data,
      String sourceIp,
    ) async {
      await router.debugDispatchAndWait(
        RemoteAction.config,
        command,
        data,
        RemoteCommandContext(
          encrypted: false,
          authorized: false,
          sourceIp: sourceIp,
        ),
      );
      await tester.pump();
    }

    /// Let any consent still pending expire, so the router's process-wide
    /// legacy state (and its 60s timer) does not leak into the next test.
    Future<void> drainPendingConsent(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
    }

    testWidgets('a plaintext packet is parked behind a consent dialog', (
      tester,
    ) async {
      await pumpHost(tester);
      await plaintext(tester, ConfigCommand.realDebrid, 'rd-1', '192.168.5.10');

      expect(find.text('Incoming settings'), findsOneWidget);
      expect(seen, isEmpty, reason: 'nothing may apply before consent');
      await drainPendingConsent(tester);
    });

    testWidgets('Allow replays the burst in order with complete last', (
      tester,
    ) async {
      await pumpHost(tester);
      await plaintext(tester, ConfigCommand.realDebrid, 'rd-2', '192.168.5.11');
      await plaintext(tester, ConfigCommand.torbox, 'tb-2', '192.168.5.11');
      // The v1 sender fires `complete` before the user can possibly answer;
      // it is parked with the burst and replayed LAST, after the items.
      await plaintext(tester, ConfigCommand.complete, null, '192.168.5.11');
      expect(seen, isEmpty);

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(
        seen,
        containsAllInOrder(<String>[
          '${RemoteAction.config}/${ConfigCommand.realDebrid}',
          '${RemoteAction.config}/${ConfigCommand.torbox}',
          '${RemoteAction.config}/${ConfigCommand.complete}',
        ]),
      );
      await drainPendingConsent(tester);
    });

    testWidgets('a second address cannot ride the pending consent', (
      tester,
    ) async {
      await pumpHost(tester);
      await plaintext(tester, ConfigCommand.realDebrid, 'rd-3', '192.168.5.12');
      await plaintext(tester, ConfigCommand.torbox, 'tb-3', '192.168.5.99');

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(
        seen,
        contains('${RemoteAction.config}/${ConfigCommand.realDebrid}'),
      );
      expect(
        seen,
        isNot(contains('${RemoteAction.config}/${ConfigCommand.torbox}')),
        reason: 'approving one phone must not blanket the whole LAN',
      );
      await drainPendingConsent(tester);
    });

    testWidgets('an approval covers the rest of the burst', (tester) async {
      await pumpHost(tester);
      await plaintext(tester, ConfigCommand.realDebrid, 'rd-4', '192.168.5.13');
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      seen.clear();

      await plaintext(tester, ConfigCommand.torbox, 'tb-4', '192.168.5.13');
      await tester.pumpAndSettle();

      expect(find.text('Incoming settings'), findsNothing);
      expect(seen, contains('${RemoteAction.config}/${ConfigCommand.torbox}'));
      await drainPendingConsent(tester);
    });

    testWidgets('Deny drops the buffer and says so', (tester) async {
      await pumpHost(tester);
      await plaintext(tester, ConfigCommand.realDebrid, 'rd-5', '192.168.5.14');

      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      expect(seen, isEmpty);
      expect(find.text('Incoming settings were blocked'), findsOneWidget);
      await drainPendingConsent(tester);
    });

    testWidgets('an unanswered consent expires and takes its dialog down', (
      tester,
    ) async {
      await pumpHost(tester);
      await plaintext(tester, ConfigCommand.realDebrid, 'rd-6', '192.168.5.15');
      expect(find.text('Incoming settings'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.text('Incoming settings'), findsNothing);
      expect(seen, isEmpty);
      // A silent expiry: the drop notice belongs to an explicit Deny.
      expect(find.text('Incoming settings were blocked'), findsNothing);
    });
  });
}
