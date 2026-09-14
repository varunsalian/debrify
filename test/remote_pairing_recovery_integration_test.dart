import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/services/remote_control/remote_pairing_store.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/udp_command_service.dart';
import 'package:debrify/services/remote_control/udp_discovery_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/remote/remote_pairing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final lost in ['request', 'challenge', 'ok', 'legacy_ok']) {
    testWidgets('real UDP pairing recovers a lost $lost without retyping', (
      tester,
    ) async {
      late RemoteControlState state;
      late Directory cache;
      late UdpCommandService receiver;
      late RemoteSessionManager manager;
      var now = DateTime.now();
      final gate = PairingGate(isRemembered: (_) => false, now: () => now);
      var dropped = false;
      await tester.runAsync(() async {
        state = RemoteControlState()..debugReliablePort = 0;
        SharedPreferences.setMockInitialValues({});
        SecretVault.debugReset(deviceIdOverride: 'pairing-integration-test');
        await RemotePairingStore.resetDeviceIdentity();
        cache = await Directory.systemTemp.createTemp(
          'remote-pairing-integration-',
        );
        AppStorage.debugOverride(cache: cache);
        final key = await RemoteSessionCrypto.x25519.newKeyPair();
        manager = RemoteSessionManager(
          loadStaticKeyPair: () async => key,
          deviceName: () => 'Receiver',
        );
        receiver = UdpCommandService(isTv: true, commandPort: 0);
        receiver.onSessionMessage = (json, address, port) async {
          if (json['type'] != RemoteMessageType.ecmd) {
            final result = await manager.handle(json);
            for (final reply in result.outgoing) {
              receiver.sendRaw(reply, address.address, port: port);
            }
            return;
          }
          final opened = await manager.openCommand(json);
          final session = opened.session;
          final command = opened.command;
          if (session == null || command == null) return;
          final name = command['command'];
          String? reply;
          String? data;
          if (name == PairCommand.request) {
            if (lost == 'request' && !dropped) {
              dropped = true;
              return;
            }
            reply =
                gate.request(session) == PairingRequestOutcome.autoAuthorized
                ? PairCommand.ok
                : PairCommand.challenge;
          } else if (name == PairCommand.confirm) {
            // Confirm the sender's proof through the same receiver gate.
            now = now.add(const Duration(seconds: 3));
            final proof = base64Decode(command['data'] as String);
            final outcome = lost == 'legacy_ok' && session.authorized
                ? PairProofOutcome.noRequest
                : await gate.confirmProof(session, proof);
            reply = outcome == PairProofOutcome.ok
                ? PairCommand.ok
                : PairCommand.err;
            data = outcome == PairProofOutcome.ok
                ? null
                : outcome == PairProofOutcome.noRequest
                ? 'no_request'
                : outcome.name;
          } else if (name == PairCommand.cancel) {
            gate.cancelSession(session);
          }
          if (reply == null) return;
          if ((reply == lost ||
                  (lost == 'legacy_ok' && reply == PairCommand.ok)) &&
              !dropped) {
            dropped = true;
            return;
          }
          receiver.sendRaw(
            await manager.sealCommand(session, {
              'action': RemoteAction.pair,
              'command': reply,
              if (data != null) 'data': data,
            }),
            address.address,
            port: port,
          );
        };
        await receiver.start();
        state.debugCommandPort = receiver.boundPort!;
      });
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold(body: Text('Sender'));
            },
          ),
        ),
      );
      var finished = false;
      RemoteSession? result;
      Object? failure;
      await tester.runAsync(() async {
        unawaited(
          ensureAuthorizedSession(
            context,
            state,
            DiscoveredDevice(
              deviceName: 'Receiver',
              ip: '127.0.0.1',
              protocolVersionKnown: false,
            ),
          ).then(
            (session) {
              result = session;
              finished = true;
            },
            onError: (Object error) {
              failure = error;
              finished = true;
            },
          ),
        );
      });
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 350 && !ready(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(ready(), isTrue);
      }

      try {
        await until(
          () => find.byType(TextField).evaluate().isNotEmpty || finished,
        );
        expect(failure, isNull);
        expect(finished, isFalse);
        await tester.enterText(find.byType(TextField), gate.current!.code);
        await until(() => finished);
        expect(failure, isNull);
        expect(dropped, isTrue);
        expect(result?.authorized, isTrue);
        expect(find.byType(TextField), findsNothing);
      } finally {
        await tester.runAsync(() async {
          await state.debugResetForTesting();
          await receiver.stop();
          await RemotePairingStore.resetDeviceIdentity();
          SecretVault.debugReset();
          AppStorage.debugReset();
          await cache.delete(recursive: true);
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
