import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_pairing_store.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RemoteSessionManager _manager(
  String name, {
  DateTime Function()? now,
  int protocolVersion = kProtoVersion,
  int transferPort = kReliableTransferPort,
}) {
  Future<SimpleKeyPair>? statics;
  return RemoteSessionManager(
    loadStaticKeyPair: () =>
        statics ??= RemoteSessionCrypto.x25519.newKeyPair(),
    deviceName: () => name,
    now: now,
    protocolVersion: protocolVersion,
    transferPort: transferPort,
  );
}

/// Drive a full handshake between [sender] and [receiver], optionally routing
/// messages through [tamper] (a MITM). Returns both established sessions.
Future<({RemoteSession? senderSession, RemoteSession? receiverSession})>
_bridge(
  RemoteSessionManager sender,
  RemoteSessionManager receiver, {
  Map<String, dynamic> Function(Map<String, dynamic>)? tamper,
}) async {
  RemoteSession? senderSession;
  RemoteSession? receiverSession;
  var toReceiver = <Map<String, dynamic>>[await sender.startHandshake()];
  var guard = 0;
  while (toReceiver.isNotEmpty && guard++ < 10) {
    final toSender = <Map<String, dynamic>>[];
    for (final message in toReceiver) {
      final result = await receiver.handle(tamper?.call(message) ?? message);
      receiverSession = result.established ?? receiverSession;
      toSender.addAll(result.outgoing);
    }
    toReceiver = [];
    for (final message in toSender) {
      final result = await sender.handle(tamper?.call(message) ?? message);
      senderSession = result.established ?? senderSession;
      toReceiver.addAll(result.outgoing);
    }
  }
  return (senderSession: senderSession, receiverSession: receiverSession);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('handshake', () {
    test(
      'negotiates authenticated transfer ports in both directions',
      () async {
        final pair = await _bridge(
          _manager('Phone', transferPort: 43123),
          _manager('TV', transferPort: 43124),
        );
        expect(pair.senderSession?.peerTransferPort, 43124);
        expect(pair.receiverSession?.peerTransferPort, 43123);
        expect(pair.senderSession?.sasCode, pair.receiverSession?.sasCode);
      },
    );

    for (final messageType in [RemoteMessageType.hs1, RemoteMessageType.hs2]) {
      test('rejects altered transfer port in $messageType', () async {
        final pair = await _bridge(
          _manager('Phone', transferPort: 43123),
          _manager('TV', transferPort: 43124),
          tamper: (message) => message['type'] == messageType
              ? {...message, 'transferPort': 43125}
              : message,
        );
        expect(pair.senderSession, isNull);
        expect(pair.receiverSession, isNull);
      });
    }

    test('both sides derive identical keys and SAS', () async {
      // Deliberately NOT named "Phone": the receiver-side fallback is
      // 'Phone', and a sender by that name would mask a dropped hs1 name
      // (the name travels only in hs1 — hs3 has no name field).
      final result = await _bridge(_manager('Varun Pixel 9'), _manager('TV'));
      final s = result.senderSession!;
      final r = result.receiverSession!;
      expect(s.keys.c2s, r.keys.c2s);
      expect(s.keys.s2c, r.keys.s2c);
      expect(s.keys.conf, r.keys.conf);
      expect(s.keys.sas, r.keys.sas);
      expect(s.sasCode, r.sasCode);
      expect(s.sasCode, matches(RegExp(r'^\d{6}$')));
      expect(s.peerName, 'TV');
      expect(r.peerName, 'Varun Pixel 9');
      expect(s.peerProtocolVersion, kProtoVersion);
      expect(r.peerProtocolVersion, kProtoVersion);
      // Fingerprints cross-match: each side names the OTHER device.
      expect(s.peerFingerprint, isNot(r.peerFingerprint));
      // Sessions are keyed identically on both ends.
      expect(s.sidB64, r.sidB64);
    });

    for (final versions in [(7, 6), (6, 7)]) {
      test(
        'v${versions.$1}/v${versions.$2} peers retain pairing and TCP capabilities',
        () async {
          final pair = await _bridge(
            _manager(
              'Phone',
              protocolVersion: versions.$1,
              transferPort: 43123,
            ),
            _manager('TV', protocolVersion: versions.$2, transferPort: 43124),
          );
          expect(pair.senderSession?.peerProtocolVersion, versions.$2);
          expect(pair.receiverSession?.peerProtocolVersion, versions.$1);
          expect(pair.senderSession?.peerTransferPort, 43124);
          expect(pair.receiverSession?.peerTransferPort, 43123);
          expect(pair.senderSession!.keys.c2s, pair.receiverSession!.keys.c2s);
        },
      );
    }

    test('handshake records the peer capability version', () async {
      final result = await _bridge(
        _manager('Phone', protocolVersion: 5),
        _manager('Older TV', protocolVersion: 4),
      );
      expect(result.senderSession?.peerProtocolVersion, 4);
      expect(result.receiverSession?.peerProtocolVersion, 5);
    });

    test('v5 capability version is bound to key confirmation', () async {
      final result = await _bridge(
        _manager('Phone', protocolVersion: 5),
        _manager('TV', protocolVersion: 5),
        tamper: (message) {
          if (message['type'] == RemoteMessageType.hs2) {
            return <String, dynamic>{...message, 'v': 4};
          }
          return message;
        },
      );
      expect(result.senderSession, isNull);
      expect(result.receiverSession, isNull);
    });

    test('transcript hash is stable against a fixed vector', () async {
      final th = await RemoteSessionCrypto.transcriptHash(
        sid: List.filled(8, 1),
        com: List.filled(32, 2),
        epkS: List.filled(32, 3),
        spkS: List.filled(32, 4),
        epkR: List.filled(32, 5),
        spkR: List.filled(32, 6),
        nc: List.filled(16, 7),
      );
      // Pins the byte order of the transcript — a reorder is a protocol
      // break even if both ends agree, because deployed builds won't.
      // Value independently verified with Python hashlib over the same
      // concatenation.
      expect(base64Encode(th), 'GZxPHd5EPAStl5oftXMxRtQIIF/RpkYxZqOxuVrzJ3M=');
    });

    test('commitment mismatch in hs3 is rejected', () async {
      final sender = _manager('Phone');
      final receiver = _manager('TV');
      final hs1 = await sender.startHandshake();
      final hs2 = (await receiver.handle(hs1)).outgoing.single;
      final hs3 = (await sender.handle(hs2)).outgoing.single;
      // Tamper with the revealed nonce — the commitment no longer matches.
      final tampered = {...hs3, 'nc': base64Encode(List.filled(16, 9))};
      final result = await receiver.handle(tampered);
      expect(result.outgoing, isEmpty);
      expect(result.established, isNull);
    });

    test('tampered epk in hs2 fails the confirm tags', () async {
      final result = await _bridge(
        _manager('Phone'),
        _manager('TV'),
        tamper: (message) {
          if (message['type'] == RemoteMessageType.hs2) {
            return {...message, 'epk': base64Encode(List.filled(32, 9))};
          }
          return message;
        },
      );
      expect(result.senderSession, isNull);
      expect(result.receiverSession, isNull);
    });

    test('duplicated hs1/hs3 get byte-identical responses', () async {
      final sender = _manager('Phone');
      final receiver = _manager('TV');
      final hs1 = await sender.startHandshake();
      final hs2a = (await receiver.handle(hs1)).outgoing.single;
      final hs2b = (await receiver.handle(hs1)).outgoing.single;
      expect(jsonEncode(hs2a), jsonEncode(hs2b));
      final hs3 = (await sender.handle(hs2a)).outgoing.single;
      final hs4a = (await receiver.handle(hs3)).outgoing.single;
      final hs4b = (await receiver.handle(hs3)).outgoing.single;
      expect(jsonEncode(hs4a), jsonEncode(hs4b));
    });

    test('MITM terminating both legs produces differing SAS codes', () async {
      // The attacker completes a session with each victim separately.
      final phone = _manager('Phone');
      final tv = _manager('TV');
      final mitmTowardsPhone = _manager('FakeTV');
      final mitmTowardsTv = _manager('FakePhone');

      final legA = await _bridge(phone, mitmTowardsPhone);
      final legB = await _bridge(mitmTowardsTv, tv);
      expect(legA.senderSession, isNotNull);
      expect(legB.receiverSession, isNotNull);
      // The user compares the code the TV shows against the code the phone
      // derived — across a MITM they disagree (p = 1e-6 by chance).
      expect(legA.senderSession!.sasCode, isNot(legB.receiverSession!.sasCode));
      // And a proof generated from the phone-leg session fails against the
      // TV-leg session.
      final proof = await RemoteSessionCrypto.pairProof(
        legA.senderSession!.keys.conf,
        legA.senderSession!.sasCode,
      );
      final expected = await RemoteSessionCrypto.pairProof(
        legB.receiverSession!.keys.conf,
        legB.receiverSession!.sasCode,
      );
      expect(RemoteSessionCrypto.constantTimeEquals(proof, expected), isFalse);
    });
  });

  group('ecmd envelope', () {
    late RemoteSession sender;
    late RemoteSessionManager senderManager;
    late RemoteSessionManager receiverManager;

    setUp(() async {
      senderManager = _manager('Phone');
      receiverManager = _manager('TV');
      final result = await _bridge(senderManager, receiverManager);
      sender = result.senderSession!;
    });

    test('round-trips a command', () async {
      final envelope = await senderManager.sealCommand(sender, {
        'type': 'command',
        'action': 'config',
        'command': 'torbox',
        'data': 'k',
      });
      final opened = await receiverManager.openCommand(envelope);
      expect(opened.command!['command'], 'torbox');
      expect(opened.session!.sidB64, sender.sidB64);
    });

    test('mutating sid, n, or ct kills the envelope', () async {
      final envelope = await senderManager.sealCommand(sender, {
        'action': 'config',
        'command': 'torbox',
      });
      final badN = {...envelope, 'n': (envelope['n'] as int) + 1};
      expect((await receiverManager.openCommand(badN)).command, isNull);
      final ct = envelope['ct'] as String;
      final badCt = {
        ...envelope,
        'ct': base64Encode([...base64Decode(ct)]..[0] ^= 0xFF),
      };
      expect((await receiverManager.openCommand(badCt)).command, isNull);
      final badSid = {...envelope, 'sid': base64Encode(List.filled(8, 3))};
      final opened = await receiverManager.openCommand(badSid);
      expect(opened.command, isNull);
      expect(opened.serr?['code'], 'unknown_sid');
      // The original, untouched envelope still opens.
      expect((await receiverManager.openCommand(envelope)).command, isNotNull);
    });

    test(
      'replay of the same n is rejected; reorder inside window is fine',
      () async {
        final e1 = await senderManager.sealCommand(sender, {'command': 'a'});
        final e2 = await senderManager.sealCommand(sender, {'command': 'b'});
        final e3 = await senderManager.sealCommand(sender, {'command': 'c'});
        // Deliver out of order: 3, 1, 2 — all accepted once.
        expect((await receiverManager.openCommand(e3)).command, isNotNull);
        expect((await receiverManager.openCommand(e1)).command, isNotNull);
        expect((await receiverManager.openCommand(e2)).command, isNotNull);
        // Replays rejected.
        expect((await receiverManager.openCommand(e2)).command, isNull);
        expect((await receiverManager.openCommand(e3)).command, isNull);
      },
    );

    test('counters below the 64-window are rejected', () {
      final window = ReplayWindow();
      expect(window.tryAccept(100), isTrue);
      expect(window.tryAccept(100 - 63), isTrue); // inside window
      expect(window.tryAccept(100 - 64), isFalse); // below window
      expect(window.tryAccept(0), isFalse);
      expect(window.tryAccept(-5), isFalse);
    });

    test('ecmd and blob sends share one counter (no nonce reuse)', () async {
      final n1 = sender.nextN();
      await senderManager.sealCommand(sender, {'command': 'x'});
      final n3 = sender.nextN();
      expect(n3, n1 + 2);
    });

    test(
      'blob counters are strictly increasing, independent of the window',
      () async {
        final result = await _bridge(_manager('P'), _manager('T'));
        final r = result.receiverSession!;
        // Simulate many ecmds advancing the window far past an old blob n.
        for (var n = 10; n < 90; n++) {
          r.acceptIncoming(n);
        }
        // A blob sealed long ago (n=5) still lands: blobs use their own check.
        expect(r.acceptBlob(5), isTrue);
        // But replaying it — or anything older — is rejected.
        expect(r.acceptBlob(5), isFalse);
        expect(r.acceptBlob(3), isFalse);
        expect(r.acceptBlob(6), isTrue);
      },
    );
  });

  group('blob seal/open', () {
    test('round-trips and binds transferId/kind', () async {
      final result = await _bridge(_manager('Phone'), _manager('TV'));
      final s = result.senderSession!;
      final r = result.receiverSession!;
      final n = s.nextN();
      final ct = await RemoteSessionCrypto.sealBlob(
        key: s.sendKey,
        sid: s.sid,
        n: n,
        transferId: 't-1',
        kind: 'iptv_playlists',
        payload: '[{"id":"p1"}]',
      );
      expect(
        await RemoteSessionCrypto.openBlob(
          key: r.recvKey,
          sid: r.sid,
          n: n,
          transferId: 't-1',
          kind: 'iptv_playlists',
          ctB64: ct,
        ),
        '[{"id":"p1"}]',
      );
      // Re-labeling the blob to a different handler fails the AAD.
      expect(
        await RemoteSessionCrypto.openBlob(
          key: r.recvKey,
          sid: r.sid,
          n: n,
          transferId: 't-1',
          kind: 'debrify_channel',
          ctB64: ct,
        ),
        isNull,
      );
    });
  });

  group('PairingGate', () {
    late RemoteSession session;
    late DateTime clock;
    late PairingGate gate;
    var remembered = <String>{};

    setUp(() async {
      final result = await _bridge(_manager('Phone'), _manager('TV'));
      session = result.receiverSession!;
      clock = DateTime(2026, 8, 13, 12);
      remembered = <String>{};
      gate = PairingGate(isRemembered: remembered.contains, now: () => clock);
    });

    Future<List<int>> proofFor(RemoteSession s) =>
        RemoteSessionCrypto.pairProof(s.keys.conf, s.sasCode);

    test('happy path: show → wait → correct proof authorizes', () async {
      expect(gate.request(session), PairingRequestOutcome.shown);
      expect(gate.current!.code, session.sasCode);
      clock = clock.add(const Duration(seconds: 4));
      expect(
        await gate.confirmProof(session, await proofFor(session)),
        PairProofOutcome.ok,
      );
      expect(session.authorized, isTrue);
      expect(gate.current, isNull);
    });

    test('proof before the min display window is rejected', () async {
      gate.request(session);
      clock = clock.add(const Duration(seconds: 1));
      expect(
        await gate.confirmProof(session, await proofFor(session)),
        PairProofOutcome.tooEarly,
      );
      expect(session.authorized, isFalse);
    });

    test('wrong proofs rate-limit after 3 attempts', () async {
      gate.request(session);
      clock = clock.add(const Duration(seconds: 4));
      final wrong = List<int>.filled(16, 0);
      for (var i = 0; i < 3; i++) {
        expect(await gate.confirmProof(session, wrong), PairProofOutcome.wrong);
      }
      expect(
        await gate.confirmProof(session, wrong),
        PairProofOutcome.rateLimited,
      );
      // Even the RIGHT proof is refused while rate-limited.
      expect(
        await gate.confirmProof(session, await proofFor(session)),
        PairProofOutcome.rateLimited,
      );
    });

    test('second concurrent request is busy; timeout clears', () async {
      final other = (await _bridge(
        _manager('Phone2'),
        _manager('TV'),
      )).receiverSession!;
      expect(gate.request(session), PairingRequestOutcome.shown);
      expect(gate.request(other), PairingRequestOutcome.busy);
      clock = clock.add(const Duration(seconds: 121));
      gate.tick();
      expect(gate.current, isNull);
    });

    test('remembered fingerprint auto-authorizes without a code', () async {
      remembered.add(session.peerFingerprint);
      expect(gate.request(session), PairingRequestOutcome.autoAuthorized);
      expect(session.authorized, isTrue);
      expect(gate.current, isNull);
    });
  });

  group('pairing store', () {
    setUp(() {
      SecretVault.debugReset(deviceIdOverride: 'store-test');
      SharedPreferences.setMockInitialValues({});
      RemotePairingStore.debugResetKeypairCache();
    });

    test('keypair persists across loads and is sealed at rest', () async {
      final first = await RemotePairingStore.publicKeyBytes();
      RemotePairingStore.debugResetKeypairCache();
      final second = await RemotePairingStore.publicKeyBytes();
      expect(second, first);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('remote_static_keypair_v1'),
        startsWith(SecretVault.prefix),
      );
    });

    test('remember/forget round trip', () async {
      await RemotePairingStore.rememberPeer(
        fingerprint: 'fp1',
        staticKey: List.filled(32, 1),
        name: 'Varun phone',
      );
      expect(await RemotePairingStore.isRemembered('fp1'), isTrue);
      expect(
        (await RemotePairingStore.listPaired()).single.name,
        'Varun phone',
      );
      await RemotePairingStore.forget('fp1');
      expect(await RemotePairingStore.isRemembered('fp1'), isFalse);
      await RemotePairingStore.rememberPeer(
        fingerprint: 'fp2',
        staticKey: List.filled(32, 2),
        name: 'Tablet',
      );
      await RemotePairingStore.forgetAll();
      expect(await RemotePairingStore.listPaired(), isEmpty);
    });

    test('receiver pinning survives and matches by name', () async {
      await RemotePairingStore.pinReceiver(
        fingerprint: 'tvfp',
        staticKey: List.filled(32, 3),
        name: 'Living Room TV',
      );
      final pinned = await RemotePairingStore.knownReceiversNamed(
        'Living Room TV',
      );
      expect(pinned, hasLength(1));
      expect(pinned.single.fingerprint, 'tvfp');
      expect(await RemotePairingStore.isPinnedFingerprint('tvfp'), isTrue);
    });

    test('two receivers sharing a name keep separate pins', () async {
      await RemotePairingStore.pinReceiver(
        fingerprint: 'tv1',
        staticKey: List.filled(32, 1),
        name: 'Debrify TV',
      );
      await RemotePairingStore.pinReceiver(
        fingerprint: 'tv2',
        staticKey: List.filled(32, 2),
        name: 'Debrify TV',
      );
      final pins = await RemotePairingStore.knownReceiversNamed('Debrify TV');
      expect(pins.map((p) => p.fingerprint).toSet(), {'tv1', 'tv2'});
      // Re-pinning one refreshes it without touching the other.
      await RemotePairingStore.pinReceiver(
        fingerprint: 'tv1',
        staticKey: List.filled(32, 9),
        name: 'Debrify TV',
      );
      expect(
        await RemotePairingStore.knownReceiversNamed('Debrify TV'),
        hasLength(2),
      );
    });
  });

  group('legacy interop decision', () {
    test('v2 peer → encrypted; v1 peer under block policy → blocked', () {
      expect(
        decideLegacyCredentialSend(peerAdvertisesV2: true, peerPinnedV2: false),
        LegacySendDecision.encrypted,
      );
      expect(
        decideLegacyCredentialSend(
          peerAdvertisesV2: false,
          peerPinnedV2: false,
          policy: LegacySendPolicy.block,
        ),
        LegacySendDecision.blocked,
      );
      expect(
        decideLegacyCredentialSend(
          peerAdvertisesV2: false,
          peerPinnedV2: false,
          policy: LegacySendPolicy.allowWithOverride,
        ),
        LegacySendDecision.askOverride,
      );
    });

    test('pinned-v2 receiver claiming v1 is a suspected downgrade', () {
      expect(
        decideLegacyCredentialSend(peerAdvertisesV2: false, peerPinnedV2: true),
        LegacySendDecision.suspectedDowngrade,
      );
    });
  });
}
