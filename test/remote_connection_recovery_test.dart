import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/remote_control/udp_command_service.dart';
import 'package:debrify/services/remote_control/udp_discovery_service.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/services/remote_control/remote_pairing_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final peer in [
    (name: 'discovered v1', version: 1, known: true, ready: true),
    (name: 'modern', version: 7, known: true, ready: false),
    (name: 'unknown manual', version: 1, known: false, ready: false),
  ]) {
    test(
      '${peer.name} readiness when the receiver ignores handshakes',
      () async {
        final cache = await Directory.systemTemp.createTemp(
          'legacy-readiness-',
        );
        final receiver = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final packets = <Map<String, dynamic>>[];
        receiver.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = receiver.receive();
          if (packet != null) {
            packets.add(
              jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>,
            );
          }
          // Model a v1 receiver: no hs2 and no reply to the ephemeral port.
        });
        final state = RemoteControlState()
          ..debugReliablePort = 0
          ..debugCommandPort = receiver.port;
        AppStorage.debugOverride(cache: cache);
        final settled = Completer<void>();
        void onState() {
          if (state.connectionState != RemoteConnectionState.connecting &&
              !settled.isCompleted) {
            settled.complete();
          }
        }

        try {
          await state.connectToDevice(
            DiscoveredDevice(
              deviceName: peer.name,
              ip: '127.0.0.1',
              protoVersion: peer.version,
              protocolVersionKnown: peer.known,
            ),
          );
          state.addListener(onState);
          onState();
          await settled.future.timeout(const Duration(seconds: 10));
          expect(state.isConnected, peer.ready);
          expect(state.sessionFor('127.0.0.1'), isNull);
          expect(
            packets.any((packet) => packet['type'] == RemoteMessageType.hs1),
            isTrue,
          );
          state.sendNavigateCommand('up');
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            packets.any(
              (packet) =>
                  packet['type'] == RemoteMessageType.command &&
                  packet['action'] == RemoteAction.navigate,
            ),
            peer.ready,
          );
        } finally {
          state.removeListener(onState);
          await state.debugResetForTesting();
          state.debugCommandPort = kCommandPort;
          receiver.close();
          AppStorage.debugReset();
          await cache.delete(recursive: true);
        }
      },
    );
  }
  test(
    'disconnect retires a pending handshake without poisoning its replacement',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'remote-reconnect-test-',
      );
      final listener = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final seen = <String>{};
      listener.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = listener.receive();
        if (packet == null) return;
        final message = jsonDecode(utf8.decode(packet.data));
        if (message['type'] == RemoteMessageType.hs1) {
          seen.add(message['sid'] as String);
        }
      });
      final state = RemoteControlState()
        ..debugReliablePort = 0
        ..debugCommandPort = listener.port;
      AppStorage.debugOverride(cache: cache);
      Future<void> waitFor(int count) async {
        for (var i = 0; i < 100 && seen.length < count; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(seen.length, count);
      }

      try {
        final first = state.ensureEncryptedSession('127.0.0.1');
        await waitFor(1);
        await state.disconnect();
        expect(await first, isNull);
        final second = state.ensureEncryptedSession(
          '127.0.0.1',
          timeout: const Duration(milliseconds: 300),
        );
        await waitFor(2);
        final third = state.ensureEncryptedSession('127.0.0.1');
        expect(await second, isNull);
        expect(await third, isNull);
        expect(seen.length, 2);
      } finally {
        await state.debugResetForTesting();
        state.debugCommandPort = kCommandPort;
        listener.close();
        AppStorage.debugReset();
        await cache.delete(recursive: true);
      }
    },
  );
  test(
    'expired sender handshake cannot reappear after delayed key loading',
    () async {
      var now = DateTime.now();
      final key = await RemoteSessionCrypto.x25519.newKeyPair();
      final identityReady = Completer<void>();
      final sender = RemoteSessionManager(
        loadStaticKeyPair: () async {
          await identityReady.future;
          return key;
        },
        deviceName: () => 'sender',
        now: () => now,
      );
      final receiver = RemoteSessionManager(
        loadStaticKeyPair: () async => key,
        deviceName: () => 'receiver',
      );
      final hs2 = await receiver.handle(await sender.startHandshake());
      final reply = sender.handle(hs2.outgoing.single);
      now = now.add(kHandshakeTimeout + const Duration(seconds: 1));
      sender.tick();
      identityReady.complete();
      expect((await reply).outgoing, isEmpty);
      expect(sender.sessions, isEmpty);
    },
  );
  test(
    'receiver expiry and cancellation notify the matching session',
    () async {
      final key = await RemoteSessionCrypto.x25519.newKeyPair();
      final sender = RemoteSessionManager(
        loadStaticKeyPair: () async => key,
        deviceName: () => 'sender',
      );
      final receiver = RemoteSessionManager(
        loadStaticKeyPair: () async => key,
        deviceName: () => 'receiver',
      );
      final hs2 = await receiver.handle(await sender.startHandshake());
      final hs3 = await sender.handle(hs2.outgoing.single);
      final session = (await receiver.handle(hs3.outgoing.single)).established!;
      var now = DateTime.now();
      final reasons = <String>[];
      final gate = PairingGate(
        isRemembered: (_) => false,
        now: () => now,
        onEnded: (ended, reason) {
          expect(identical(ended, session), isTrue);
          reasons.add(reason);
        },
      );
      gate.request(session);
      now = now.add(kPairingCodeTimeout + const Duration(seconds: 1));
      final proof = await RemoteSessionCrypto.pairProof(
        session.keys.conf,
        session.sasCode,
      );
      expect(
        await gate.confirmProof(session, proof),
        PairProofOutcome.noRequest,
      );
      expect(reasons, ['expired']);
      gate.request(session);
      gate.cancelSession(session);
      expect(gate.current, isNull);
      expect(reasons, ['expired', 'cancelled']);
    },
  );
  test(
    'unreachable manual IP never becomes connected without a response',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'remote-readiness-probe-',
      );
      final state = RemoteControlState()..debugReliablePort = 0;
      AppStorage.debugOverride(cache: cache);
      try {
        await state.connectToManualIp('127.0.0.1');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(state.isConnected, isFalse);
        expect(state.sessionFor('127.0.0.1'), isNull);
      } finally {
        await state.debugResetForTesting();
        AppStorage.debugReset();
        await cache.delete(recursive: true);
      }
    },
  );
  test('lost pairing OK recovers by resending the correct proof', () async {
    final sk = await RemoteSessionCrypto.x25519.newKeyPair();
    final rk = await RemoteSessionCrypto.x25519.newKeyPair();
    final sender = RemoteSessionManager(
      loadStaticKeyPair: () async => sk,
      deviceName: () => 'sender',
    );
    final receiver = RemoteSessionManager(
      loadStaticKeyPair: () async => rk,
      deviceName: () => 'receiver',
    );
    final hs2 = await receiver.handle(await sender.startHandshake());
    final hs3 = await sender.handle(hs2.outgoing.single);
    final hs4 = await receiver.handle(hs3.outgoing.single);
    final session = hs4.established!;
    var now = DateTime.now();
    final gate = PairingGate(isRemembered: (_) => false, now: () => now);
    expect(gate.request(session), PairingRequestOutcome.shown);
    now = now.add(const Duration(seconds: 3));
    final proof = await RemoteSessionCrypto.pairProof(
      session.keys.conf,
      session.sasCode,
    );
    expect(await gate.confirmProof(session, proof), PairProofOutcome.ok);
    // The OK datagram is lost. The UI retries the same valid proof.
    expect(await gate.confirmProof(session, proof), PairProofOutcome.ok);
    expect(session.authorized, isTrue);
  });
  test(
    'forgetting an obsolete endpoint restores the fixed receiver port',
    () async {
      final fixed = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final service = UdpCommandService(isTv: false, commandPort: fixed.port);
      final previous = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final staleReceived = Completer<void>();
      var fixedReceived = false;
      previous.listen((event) {
        if (event == RawSocketEvent.read &&
            previous.receive() != null &&
            !staleReceived.isCompleted) {
          staleReceived.complete();
        }
      });
      fixed.listen((event) {
        if (event == RawSocketEvent.read && fixed.receive() != null) {
          fixedReceived = true;
        }
      });
      try {
        await service.start();
        service.notePeerEndpoint('127.0.0.1', previous.port);
        service.sendRaw({'type': 'hs1'}, '127.0.0.1');
        await staleReceived.future.timeout(const Duration(seconds: 1));
        expect(fixedReceived, isFalse);
        expect(service.portFor('127.0.0.1'), previous.port);
        service.forgetPeerEndpoint('127.0.0.1');
        expect(service.portFor('127.0.0.1'), fixed.port);
      } finally {
        await service.stop();
        fixed.close();
        previous.close();
      }
    },
  );
  test(
    'duplicate hs1 during key loading retains one receiver identity',
    () async {
      final senderKey = await RemoteSessionCrypto.x25519.newKeyPair();
      final receiverKey = await RemoteSessionCrypto.x25519.newKeyPair();
      final gate = Completer<void>();
      final sender = RemoteSessionManager(
        loadStaticKeyPair: () async => senderKey,
        deviceName: () => 'sender',
      );
      final receiver = RemoteSessionManager(
        loadStaticKeyPair: () async {
          await gate.future;
          return receiverKey;
        },
        deviceName: () => 'receiver',
      );
      final hs1 = await sender.startHandshake();
      final first = receiver.handle(hs1);
      final second = receiver.handle(hs1);
      gate.complete();
      final replies = await Future.wait([first, second]);
      expect(
        replies[0].outgoing.single['epk'],
        replies[1].outgoing.single['epk'],
      );
      final hs3 = await sender.handle(replies[0].outgoing.single);
      final result = await receiver.handle(hs3.outgoing.single);
      expect(result.established, isNotNull);
      expect(result.outgoing, hasLength(1));
      final duplicateReply = await sender.handle(replies[1].outgoing.single);
      final retry = await receiver.handle(duplicateReply.outgoing.single);
      expect(retry.established, isNull);
      expect(retry.outgoing, result.outgoing);
    },
  );
  test('occupied receiver port rejects startup', () async {
    final occupied = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: false,
      reusePort: false,
    );
    final service = UdpCommandService(isTv: true, commandPort: occupied.port);
    String? error;
    service.onError = (value) => error = value;
    try {
      await expectLater(service.start(), throwsA(isA<SocketException>()));
      expect(service.isRunning, isFalse);
      expect(error, isNotNull);
    } finally {
      await service.stop();
      occupied.close();
    }
  });
  test(
    'failed identity initialization retries after storage is repaired',
    () async {
      SharedPreferences.setMockInitialValues({});
      await RemotePairingStore.resetDeviceIdentity();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('remote_static_keypair_v1', 42);
      final failed = RemotePairingStore.loadOrCreateKeypair();
      await expectLater(failed, throwsA(isA<TypeError>()));
      await prefs.remove('remote_static_keypair_v1');
      SecretVault.debugReset(deviceIdOverride: 'remote-recovery-test');
      final retry = RemotePairingStore.loadOrCreateKeypair();
      expect(identical(failed, retry), isFalse);
      expect(await retry, isNotNull);
      SecretVault.debugReset();
      await RemotePairingStore.resetDeviceIdentity();
    },
  );
}
