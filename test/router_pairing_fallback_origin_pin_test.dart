import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/udp_command_service.dart';
import 'package:debrify/widgets/remote/remote_pairing_dialog.dart';
import 'package:debrify/widgets/remote/remote_router_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Origin pin for `RemoteCommandRouter._ensurePairingUi` — the router's second
/// dialog-layering row, and the reason the router imports
/// `lib/widgets/remote/remote_pairing_dialog.dart` at all.
///
/// The router owns the *decision*: when a `pair/request` resolves to
/// `PairingRequestOutcome.shown`, it raises the fallback code dialog through
/// its own navigator key, but only when no `RemotePairingPanel` has claimed the
/// gate through `PairingGate.registerPresenter()`. Everything here is driven
/// through `RemoteCommandRouter.handlePairMessage` — the exact entry
/// `RemoteControlState` wires to `onPairMessage` — against a real
/// `MaterialApp`, a real `PairingGate` built by the real receiver wiring, and a
/// real session. No source-text greps, no re-implemented bodies.
///
/// The sender-side code entry sheet from the same widgets file is already
/// covered by `test/remote_pairing_dialog_test.dart`; the gate's own state
/// machine by the `PairingGate` group in `test/remote_session_test.dart`. This
/// file adds only what the router contributes: which requests reach the
/// fallback dialog, what that dialog renders, how its outcome gets back to the
/// gate, and the four guards around it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final router = RemoteCommandRouter();
  // Built here, in the real zone, on purpose: `RemoteControlState` serialises
  // role changes on a queue seeded with a `Future` created when the singleton
  // is constructed. Constructed inside a `testWidgets` body that seed belongs
  // to the fake-async zone, and `startTvListener` — awaited on the real loop —
  // would deadlock waiting for a microtask the fake clock never delivers.
  final state = RemoteControlState();

  late RemoteSession session;
  late RemoteSessionManager manager;
  late List<RemoteCommand> outbound;
  late GlobalKey<NavigatorState> navigatorKey;
  late GlobalKey<ScaffoldMessengerState> messengerKey;

  /// An unauthorized receiver-side session — the state a phone is in when its
  /// `pair/request` is the thing that must raise a code.
  RemoteSession buildSession({
    required int seed,
    required String fingerprint,
    String peerName = 'Phone',
    String sasCode = '654321',
  }) {
    final sid = Uint8List.fromList(List<int>.generate(16, (i) => i + seed));
    final keys = SessionKeys(
      c2s: List<int>.generate(32, (i) => i),
      s2c: List<int>.generate(32, (i) => 255 - i),
      conf: List<int>.filled(32, seed),
      sas: List<int>.filled(32, 6),
    );
    return RemoteSession(
      sid: sid,
      role: RemoteSessionRole.receiver,
      keys: keys,
      peerStaticKey: List<int>.filled(32, 2),
      peerFingerprint: fingerprint,
      peerName: peerName,
      sasCode: sasCode,
      establishedAt: DateTime.now(),
    );
  }

  setUp(() async {
    // The production dialog presenter, registered here because these tests
    // pump a bare `MaterialApp` rather than going through `main.dart`.
    router.setDialogs(const RemoteRouterDialogs());
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Plaintext-era runtime: `ProfileAsyncAuthorization.capture` returns null,
    // so the state's outbound path runs without a committed profile scope.
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();

    outbound = <RemoteCommand>[];
    session = buildSession(seed: 41, fingerprint: 'peer-pairing');
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

  /// Brings up the receiver wiring for real: `startTvListener` is the only
  /// path that builds the `PairingGate` the router reads off the state, so the
  /// pin uses it rather than inventing a gate of its own. Socket binds are
  /// best-effort inside `UdpCommandService.start`, so this works headless.
  Future<PairingGate> startReceiver(WidgetTester tester) async {
    await tester.runAsync(() => state.startTvListener('TV'));
    // Replace the manager AFTER wiring (it is installed with `??=`) so the
    // seeded session is the one the gate and the router see.
    state.debugInstallSessionManager(manager);
    state.debugInstallOutboundSession(session, ip: '10.4.4.9');
    state.debugCommandSealer = (_, commandJson) async {
      outbound.add(RemoteCommand.fromJson(commandJson));
      return <String, dynamic>{'type': 'ecmd', 'ct': 'sealed'};
    };
    state.debugRawSender = (_, _, _) => true;
    return state.pairingGate!;
  }

  /// The host the router's navigator/messenger keys point at. [panelGate], when
  /// given, mounts a real `RemotePairingPanel` — which registers itself as the
  /// gate's presenter in `initState`, exactly as the receive screen does.
  Future<void> pumpHost(WidgetTester tester, {PairingGate? panelGate}) async {
    navigatorKey = GlobalKey<NavigatorState>();
    messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        home: Scaffold(
          body: panelGate == null
              ? const SizedBox.shrink()
              : RemotePairingPanel(gate: panelGate),
        ),
      ),
    );
    router.setNavigatorKey(navigatorKey);
    router.setScaffoldMessengerKey(messengerKey);
  }

  /// One inbound pair message through the router's real public entry, run on
  /// the real event loop (the reply seals asynchronously before
  /// `_ensurePairingUi` is reached), then a frame.
  Future<void> pairMessage(
    WidgetTester tester,
    String command, {
    String? data,
    RemoteSession? from,
  }) async {
    await tester.runAsync(
      () => router.handlePairMessage(state, from ?? session, command, data),
    );
    await tester.pump();
  }

  List<RemoteCommand> pairReplies() => [
    for (final command in outbound)
      if (command.action == RemoteAction.pair) command,
  ];

  /// Takes the fallback dialog down through the gate, which is also the only
  /// thing that clears `showRemotePairingDialog`'s process-wide single-flight
  /// latch. Every test that opens the dialog ends here.
  Future<void> closeFallback(WidgetTester tester, PairingGate gate) async {
    gate.cancel();
    await tester.pumpAndSettle();
  }

  group('fallback pairing dialog (no presenter mounted)', () {
    testWidgets('a shown request raises the code dialog on the router\'s '
        'navigator and answers with a challenge', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      expect(gate.hasPresenter, isFalse, reason: 'nothing registered');

      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();

      // The protocol reply goes out before the UI is raised.
      expect(pairReplies().single.command, PairCommand.challenge);
      expect(pairReplies().single.data, isNull);

      // The dialog is a real route on the router's navigator.
      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget);
      expect(
        ModalRoute.of(tester.element(dialog))!.navigator,
        navigatorKey.currentState,
      );
      expect(
        tester.widget<Dialog>(dialog).backgroundColor,
        const Color(0xFF16181D),
      );

      // Body: the peer name, the instruction, the spaced code, one button.
      expect(find.text('"Phone" wants to send settings'), findsOneWidget);
      expect(
        find.text('Enter this code on that device to continue'),
        findsOneWidget,
      );
      expect(find.text('654 321'), findsOneWidget);
      expect(find.text('654321'), findsNothing);
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(cancel, findsOneWidget);
      expect(
        tester.widget<TextButton>(cancel).autofocus,
        isTrue,
        reason: 'a TV remote lands on Cancel',
      );

      // The panel inside the fallback deliberately does NOT count itself as a
      // presenter, so the gate stays "unpresented" while the dialog is up.
      expect(
        tester
            .widget<RemotePairingPanel>(find.byType(RemotePairingPanel))
            .registerAsPresenter,
        isFalse,
      );
      expect(gate.hasPresenter, isFalse);

      // Undismissable by the barrier.
      expect(
        ModalRoute.of(tester.element(dialog))!.barrierDismissible,
        isFalse,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('654 321'), findsOneWidget);

      await closeFallback(tester, gate);
    });

    testWidgets('Cancel in the dialog declines through the gate and takes the '
        'dialog with it', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // The button reaches the gate, and the gate clearing is what pops the
      // route (`_AutoDismissOnGateClear`), not the button.
      expect(gate.current, isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(session.authorized, isFalse);
      // Declining sends nothing extra; the sender learns from the timeout.
      expect(pairReplies().map((c) => c.command), [PairCommand.challenge]);

      // The single-flight latch really released: a fresh request re-raises it.
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.text('654 321'), findsOneWidget);
      await closeFallback(tester, gate);
    });

    testWidgets('a correct proof authorizes through the gate and the dialog '
        'dismisses itself', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      final proof = (await tester.runAsync(
        () => RemoteSessionCrypto.pairProof(session.keys.conf, '654321'),
      ))!;

      // Before `kPairingMinDisplay` the gate refuses — the dialog stays up.
      await pairMessage(
        tester,
        PairCommand.confirm,
        data: base64.encode(proof),
      );
      await tester.pumpAndSettle();
      expect(pairReplies().last.command, PairCommand.err);
      expect(pairReplies().last.data, 'too_early');
      expect(find.byType(Dialog), findsOneWidget);

      // The gate reads the real wall clock, so the min-display window has to
      // pass for real.
      await tester.runAsync(
        () => Future<void>.delayed(
          kPairingMinDisplay + const Duration(milliseconds: 200),
        ),
      );
      await pairMessage(
        tester,
        PairCommand.confirm,
        data: base64.encode(proof),
      );
      await tester.pumpAndSettle();

      expect(pairReplies().last.command, PairCommand.ok);
      expect(pairReplies().last.data, isNull);
      expect(session.authorized, isTrue);
      expect(gate.current, isNull);
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: 'the gate clearing dismisses the fallback',
      );
      expect(find.text('Paired with "Phone"'), findsOneWidget);
    });
  });

  group('presenter registered (no fallback)', () {
    testWidgets('a mounted RemotePairingPanel takes the request instead of '
        'the dialog', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester, panelGate: gate);
      expect(
        gate.hasPresenter,
        isTrue,
        reason: 'the panel registers in initState',
      );
      // Nothing is drawn until a request arrives.
      expect(find.text('654 321'), findsNothing);

      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();

      // The protocol half is unchanged...
      expect(pairReplies().single.command, PairCommand.challenge);
      // ...but the code is presented by the mounted panel, not a dialog route.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(RemotePairingPanel), findsOneWidget);
      expect(find.text('"Phone" wants to send settings'), findsOneWidget);
      expect(find.text('654 321'), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.text('654 321')))!.isFirst,
        isTrue,
      );

      gate.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('a bare registered presenter suppresses the dialog, and '
        'unregistering restores the fallback', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);

      // A "fake" presenter: the gate counts registrations, not widgets.
      gate.registerPresenter();
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(gate.current, isNotNull, reason: 'the gate still holds the code');
      expect(pairReplies().single.command, PairCommand.challenge);
      expect(
        find.byType(Dialog),
        findsNothing,
        reason: 'a registered presenter owns the code',
      );

      // Registrations are counted: one unregister of two still suppresses.
      gate.registerPresenter();
      gate.unregisterPresenter();
      expect(gate.hasPresenter, isTrue);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      // Last one out: the next request falls back to the dialog.
      gate.unregisterPresenter();
      expect(gate.hasPresenter, isFalse);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('654 321'), findsOneWidget);

      await closeFallback(tester, gate);
    });
  });

  group('guards around the fallback', () {
    testWidgets('no navigator: the gate still shows the code, the router just '
        'has nowhere to put it', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      // A key that belongs to no mounted Navigator — the always-on listener
      // before the app tree exists.
      router.setNavigatorKey(GlobalKey<NavigatorState>());

      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();

      expect(pairReplies().single.command, PairCommand.challenge);
      expect(gate.current!.code, '654321');
      expect(find.byType(Dialog), findsNothing);

      // Re-pointing at the live navigator and re-requesting raises it, so the
      // early return was the reason and nothing latched.
      router.setNavigatorKey(navigatorKey);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.text('654 321'), findsOneWidget);

      await closeFallback(tester, gate);
    });

    testWidgets('a repeated request from the same session does not stack a '
        'second dialog', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      await pairMessage(tester, PairCommand.request);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();

      // The gate keeps re-answering `shown`, so the router keeps calling in;
      // the dialog's own single-flight latch is what keeps it to one route.
      expect(pairReplies().map((c) => c.command), [
        PairCommand.challenge,
        PairCommand.challenge,
        PairCommand.challenge,
      ]);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('654 321'), findsOneWidget);

      await closeFallback(tester, gate);
    });

    testWidgets('a second peer while the code is up is refused as busy and '
        'never reaches the UI', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();
      expect(find.text('654 321'), findsOneWidget);

      final intruder = buildSession(
        seed: 90,
        fingerprint: 'peer-intruder',
        peerName: 'Other',
        sasCode: '111222',
      );
      manager.sessions[intruder.sidB64] = intruder;
      state.debugInstallOutboundSession(intruder, ip: '10.4.4.10');

      await pairMessage(tester, PairCommand.request, from: intruder);
      await tester.pumpAndSettle();

      expect(pairReplies().last.command, PairCommand.err);
      expect(pairReplies().last.data, 'busy');
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('"Phone" wants to send settings'), findsOneWidget);
      expect(find.text('"Other" wants to send settings'), findsNothing);
      expect(find.text('111 222'), findsNothing);

      await closeFallback(tester, gate);
    });

    testWidgets('an already-authorized session is auto-authorized and never '
        'raises the dialog', (tester) async {
      final gate = await startReceiver(tester);
      await pumpHost(tester);
      session.authorized = true;

      await pairMessage(tester, PairCommand.request);
      await tester.pumpAndSettle();

      expect(pairReplies().single.command, PairCommand.ok);
      expect(pairReplies().single.data, 'remembered');
      expect(gate.current, isNull);
      expect(find.byType(Dialog), findsNothing);
    });
  });
}
