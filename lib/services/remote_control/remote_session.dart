import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'remote_constants.dart';

/// Protocol v2 session crypto for the UDP remote control.
///
/// Shape: a 4-message commit-then-reveal X25519 handshake (ZRTP-style, so a
/// man-in-the-middle cannot grind the short pairing code), triple-DH so both
/// long-term identities are proven, HKDF key schedule bound to the transcript
/// hash, AES-GCM envelopes with counter nonces and a sliding replay window,
/// and a 6-digit SAS ("pairing code") derived independently on both ends —
/// never transmitted — whose comparison authenticates credential transfers.
///
/// Everything in this file is socket-free and side-effect-free (state machines
/// take messages in and hand messages out), so the whole protocol is unit
/// testable by bridging two managers in memory.

// ---------------------------------------------------------------------------
// Pure crypto
// ---------------------------------------------------------------------------

class SessionKeys {
  final List<int> c2s; // sender → receiver AES-256-GCM key
  final List<int> s2c; // receiver → sender AES-256-GCM key
  final List<int> conf; // key-confirmation / pairing-proof MAC key
  final List<int> sas; // pairing-code derivation key

  const SessionKeys({
    required this.c2s,
    required this.s2c,
    required this.conf,
    required this.sas,
  });
}

class RemoteSessionCrypto {
  RemoteSessionCrypto._();

  static final X25519 x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Sha256 _sha256 = Sha256();
  static final Hmac _hmac = Hmac.sha256();

  static const String _transcriptLabel = 'debrify-rc-v2';

  static Future<Uint8List> sha256Of(List<int> data) async {
    final hash = await _sha256.hash(data);
    return Uint8List.fromList(hash.bytes);
  }

  static Future<Uint8List> hmacOf(List<int> key, List<int> data) async {
    final mac = await _hmac.calculateMac(data, secretKey: SecretKey(key));
    return Uint8List.fromList(mac.bytes);
  }

  /// hs1 commitment: SHA256(epk_s ∥ nc). Binds the sender to its ephemeral
  /// before the receiver reveals anything, which is what makes the SAS
  /// ungrindable by an active MITM.
  static Future<Uint8List> commitment(List<int> epkS, List<int> nc) =>
      sha256Of([...epkS, ...nc]);

  /// Byte-exact transcript hash both sides must agree on.
  static Future<Uint8List> transcriptHash({
    required List<int> sid,
    required List<int> com,
    required List<int> epkS,
    required List<int> spkS,
    required List<int> epkR,
    required List<int> spkR,
    required List<int> nc,
    int? senderProtocolVersion,
    int? receiverProtocolVersion,
  }) => sha256Of([
    ...utf8.encode(_transcriptLabel),
    ...sid,
    ...com,
    ...epkS,
    ...spkS,
    ...epkR,
    ...spkR,
    ...nc,
    // v2-v4 did not bind capability versions into the transcript. Preserve
    // that handshake exactly for older peers; two v5+ peers authenticate both
    // advertised versions so a LAN attacker cannot upgrade/downgrade the
    // complete-profile capability independently of the proven device keys.
    if ((senderProtocolVersion ?? 0) >= 5 &&
        (receiverProtocolVersion ?? 0) >= 5) ...[
      ...utf8.encode('capabilities'),
      ..._nBytes(senderProtocolVersion!),
      ..._nBytes(receiverProtocolVersion!),
    ],
  ]);

  /// HKDF-SHA256(salt = transcript, ikm = ee ∥ es ∥ se) → the four session
  /// keys, separated by info label.
  static Future<SessionKeys> deriveKeys({
    required List<int> ikm,
    required List<int> transcript,
  }) async {
    Future<List<int>> derive(String info) async {
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final key = await hkdf.deriveKey(
        secretKey: SecretKey(ikm),
        nonce: transcript,
        info: utf8.encode(info),
      );
      return key.extractBytes();
    }

    return SessionKeys(
      c2s: await derive('drc2 c2s'),
      s2c: await derive('drc2 s2c'),
      conf: await derive('drc2 conf'),
      sas: await derive('drc2 sas'),
    );
  }

  /// 6-digit pairing code. 48 input bits make the mod-10^6 bias negligible.
  static Future<String> sasCode(List<int> kSas) async {
    final mac = await hmacOf(kSas, utf8.encode('sas'));
    var value = 0;
    for (var i = 0; i < 6; i++) {
      value = (value << 8) | mac[i];
    }
    return (value % 1000000).toString().padLeft(6, '0');
  }

  /// Key-confirmation tag for hs3 (sender) / hs4 (receiver), 16 bytes.
  static Future<Uint8List> confirmTag(List<int> kConf, String label) async {
    final mac = await hmacOf(kConf, utf8.encode(label));
    return Uint8List.sublistView(mac, 0, 16);
  }

  /// Proof the phone-side user typed the code the TV displayed, 16 bytes.
  static Future<Uint8List> pairProof(List<int> kConf, String code) async {
    final mac = await hmacOf(kConf, [
      ...utf8.encode('pair-proof'),
      ...utf8.encode(code),
    ]);
    return Uint8List.sublistView(mac, 0, 16);
  }

  /// Device fingerprint: first 16 bytes of SHA-256(static pubkey), hex.
  static Future<String> fingerprint(List<int> spk) async {
    final hash = await sha256Of(spk);
    return hash
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 12-byte big-endian nonce from the per-session counter.
  static Uint8List nonceFor(int n) {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(4, n);
    return nonce;
  }

  static Uint8List _nBytes(int n) {
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setUint64(0, n);
    return bytes;
  }

  static List<int> _ecmdAad(List<int> sid, int n) => [
    ...utf8.encode('drc2 ecmd'),
    ...sid,
    ..._nBytes(n),
  ];

  /// Binding transferId+kind stops a MITM re-labeling a blob to a different
  /// config handler.
  static List<int> _blobAad(
    List<int> sid,
    int n,
    String transferId,
    String kind,
  ) => [
    ...utf8.encode('drc2 blob'),
    ...sid,
    ..._nBytes(n),
    ...utf8.encode(transferId),
    ...utf8.encode(kind),
  ];

  static Future<String> _seal(
    List<int> key,
    int n,
    List<int> aad,
    List<int> plaintext,
  ) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonceFor(n),
      aad: aad,
    );
    return base64Encode([...box.cipherText, ...box.mac.bytes]);
  }

  static Future<List<int>?> _open(
    List<int> key,
    int n,
    List<int> aad,
    String ctB64,
  ) async {
    try {
      final packed = base64Decode(ctB64);
      if (packed.length < 16) return null;
      final box = SecretBox(
        packed.sublist(0, packed.length - 16),
        nonce: nonceFor(n),
        mac: Mac(packed.sublist(packed.length - 16)),
      );
      return await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad);
    } catch (_) {
      return null;
    }
  }

  static Future<String> sealEcmd({
    required List<int> key,
    required List<int> sid,
    required int n,
    required String commandJson,
  }) => _seal(key, n, _ecmdAad(sid, n), utf8.encode(commandJson));

  static Future<String?> openEcmd({
    required List<int> key,
    required List<int> sid,
    required int n,
    required String ctB64,
  }) async {
    final plaintext = await _open(key, n, _ecmdAad(sid, n), ctB64);
    return plaintext == null ? null : utf8.decode(plaintext);
  }

  static Future<String> sealBlob({
    required List<int> key,
    required List<int> sid,
    required int n,
    required String transferId,
    required String kind,
    required String payload,
  }) => _seal(key, n, _blobAad(sid, n, transferId, kind), utf8.encode(payload));

  static Future<String?> openBlob({
    required List<int> key,
    required List<int> sid,
    required int n,
    required String transferId,
    required String kind,
    required String ctB64,
  }) async {
    final plaintext = await _open(
      key,
      n,
      _blobAad(sid, n, transferId, kind),
      ctB64,
    );
    return plaintext == null ? null : utf8.decode(plaintext);
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

// ---------------------------------------------------------------------------
// Replay window
// ---------------------------------------------------------------------------

/// Per-direction sliding acceptance window: accepts each counter value at
/// most once, tolerates UDP reordering within 64 of the highest seen.
class ReplayWindow {
  int _max = 0;
  int _mask = 0; // bit i set ⇔ (_max - i) was seen; bit 0 is _max itself.

  bool tryAccept(int n) {
    if (n <= 0) return false;
    if (n > _max) {
      final shift = n - _max;
      _mask = shift >= 64 ? 1 : ((_mask << shift) | 1) & _maskAll;
      _max = n;
      return true;
    }
    final offset = _max - n;
    if (offset >= 64) return false;
    final bit = 1 << offset;
    if (_mask & bit != 0) return false;
    _mask |= bit;
    return true;
  }

  static const int _maskAll = 0xFFFFFFFFFFFFFFFF;
}

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

enum RemoteSessionRole { sender, receiver }

class RemoteSession {
  final Uint8List sid;
  final String sidB64;
  final RemoteSessionRole role;
  final SessionKeys keys;
  final List<int> peerStaticKey;
  final String peerFingerprint;
  final String peerName;

  /// Capability version the peer placed in its handshake message. This lets
  /// manual-IP/VPN peers report capabilities without a broadcast discovery
  /// record. Early encrypted peers that omit the field are treated as v2.
  final int peerProtocolVersion;

  /// The 6-digit SAS, derived locally. Displayed on the receiver; compared on
  /// the sender against what the user reads off the TV.
  final String sasCode;

  final DateTime establishedAt;
  DateTime lastUsed;

  /// Whether a pairing code (or remembered-device shortcut) has authorized
  /// this session for credential/config traffic.
  bool authorized = false;

  int _sendCounter = 0;
  final ReplayWindow _recvWindow = ReplayWindow();

  RemoteSession({
    required this.sid,
    required this.role,
    required this.keys,
    required this.peerStaticKey,
    required this.peerFingerprint,
    required this.peerName,
    this.peerProtocolVersion = kProtoVersion,
    required this.sasCode,
    required this.establishedAt,
  }) : sidB64 = base64Encode(sid),
       lastUsed = establishedAt;

  List<int> get sendKey =>
      role == RemoteSessionRole.sender ? keys.c2s : keys.s2c;
  List<int> get recvKey =>
      role == RemoteSessionRole.sender ? keys.s2c : keys.c2s;

  /// Single counter shared by ecmd and blob sends — nonces can never collide.
  int nextN() => ++_sendCounter;

  bool acceptIncoming(int n) => _recvWindow.tryAccept(n);

  int _lastBlobN = 0;

  /// Blob counters are checked separately from the ecmd window: a chunked
  /// transfer reassembles seconds after its n was allocated, by which time
  /// later ecmds have advanced the sliding window past it. Blobs are rare and
  /// sent serially, so strictly-increasing is both safe (each n still used at
  /// most once ⇒ replay rejected) and sufficient.
  bool acceptBlob(int n) {
    if (n <= _lastBlobN) return false;
    _lastBlobN = n;
    return true;
  }
}

/// Trust facts about the inbound path a command arrived over, handed to the
/// router so it can gate config/addon writes.
class RemoteCommandContext {
  final bool encrypted;
  final bool authorized;

  /// True only when the receiver's persisted pairing store contains this
  /// cryptographically authenticated peer fingerprint.
  final bool remembered;
  final String? sidB64;
  final String? peerFingerprint;
  final String? peerName;

  /// Datagram source address for plaintext commands — the only identity a v1
  /// sender has. The legacy-consent flow keys its buffer and its approval
  /// window on this, so approving one phone never blankets other LAN hosts.
  final String? sourceIp;

  /// Sends a privacy-safe rejection over the already-authenticated session.
  /// Routers never receive the socket or keys themselves; this capability is
  /// deliberately absent for plaintext traffic.
  final Future<void> Function(String code)? reject;

  const RemoteCommandContext({
    required this.encrypted,
    required this.authorized,
    this.remembered = false,
    this.sidB64,
    this.peerFingerprint,
    this.peerName,
    this.sourceIp,
    this.reject,
  });

  static const plaintext = RemoteCommandContext(
    encrypted: false,
    authorized: false,
  );
}

// ---------------------------------------------------------------------------
// Handshake state machines
// ---------------------------------------------------------------------------

/// What [RemoteSessionManager.handle] wants done: messages to put on the wire
/// (addressing is the caller's job) and, possibly, a newly established
/// session or a failed handshake.
class SessionHandleResult {
  final List<Map<String, dynamic>> outgoing = [];
  RemoteSession? established;
  String? failedSid;
}

class _SenderHandshake {
  final Uint8List sid;
  final String sidB64;
  final SimpleKeyPair ephemeral;
  final List<int> epk;
  final Uint8List nc;
  final Uint8List com;
  final DateTime startedAt;
  DateTime lastSentAt;
  int transmits = 1;
  Map<String, dynamic>? hs3; // cached for retransmit after hs2

  _SenderHandshake({
    required this.sid,
    required this.ephemeral,
    required this.epk,
    required this.nc,
    required this.com,
    required this.startedAt,
  }) : sidB64 = base64Encode(sid),
       lastSentAt = startedAt;
}

class _ReceiverPending {
  final Uint8List sid;
  final List<int> com;
  final SimpleKeyPair ephemeral;
  final List<int> epk;
  final DateTime createdAt;

  /// The sender's display name travels ONLY in hs1 — carried here so the
  /// established session (created on hs3) can name its peer.
  final String senderName;
  final int senderProtocolVersion;
  final Map<String, dynamic> hs2; // cached: duplicate hs1 → identical hs2
  Map<String, dynamic>? hs4; // cached: duplicate hs3 → identical hs4

  _ReceiverPending({
    required this.sid,
    required this.com,
    required this.ephemeral,
    required this.epk,
    required this.createdAt,
    required this.senderName,
    required this.senderProtocolVersion,
    required this.hs2,
  });
}

/// Message-in/messages-out protocol engine for one device (either role).
/// Owns pending handshakes and established sessions; sockets, timers and
/// addressing live in the wiring layer.
class RemoteSessionManager {
  final Future<SimpleKeyPair> Function() loadStaticKeyPair;
  final String Function() deviceName;
  final DateTime Function() now;
  final List<int> Function(int) randomBytes;
  final int protocolVersion;

  final Map<String, _SenderHandshake> _senderHandshakes = {};
  final Map<String, _ReceiverPending> _receiverPending = {};
  final Map<String, RemoteSession> sessions = {};

  RemoteSessionManager({
    required this.loadStaticKeyPair,
    required this.deviceName,
    DateTime Function()? now,
    List<int> Function(int)? randomBytes,
    this.protocolVersion = kProtoVersion,
  }) : assert(protocolVersion >= 2),
       now = now ?? DateTime.now,
       randomBytes = randomBytes ?? _secureRandomBytes;

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  // ------------------------------------------------------------- sender ---

  /// Begin a handshake. Returns the hs1 message to send.
  Future<Map<String, dynamic>> startHandshake() async {
    final sid = Uint8List.fromList(randomBytes(8));
    final ephemeral = await RemoteSessionCrypto.x25519.newKeyPair();
    final epk = (await ephemeral.extractPublicKey()).bytes;
    final nc = Uint8List.fromList(randomBytes(16));
    final com = await RemoteSessionCrypto.commitment(epk, nc);
    final handshake = _SenderHandshake(
      sid: sid,
      ephemeral: ephemeral,
      epk: epk,
      nc: nc,
      com: com,
      startedAt: now(),
    );
    _senderHandshakes[handshake.sidB64] = handshake;
    return _hs1For(handshake);
  }

  Map<String, dynamic> _hs1For(_SenderHandshake handshake) => {
    'type': RemoteMessageType.hs1,
    'v': protocolVersion,
    'sid': handshake.sidB64,
    'com': base64Encode(handshake.com),
    'name': deviceName(),
  };

  /// Handshake messages that need retransmitting (call on a timer; addressing
  /// is the caller's). Expired attempts are dropped.
  List<Map<String, dynamic>> tick() {
    final current = now();
    final out = <Map<String, dynamic>>[];
    _senderHandshakes.removeWhere((sidB64, handshake) {
      if (current.difference(handshake.startedAt) > kHandshakeTimeout) {
        _senderDerived.remove(sidB64);
        return true;
      }
      if (current.difference(handshake.lastSentAt) >= kHandshakeRetransmit &&
          handshake.transmits < kHandshakeMaxRetransmits) {
        handshake.lastSentAt = current;
        handshake.transmits += 1;
        out.add(handshake.hs3 ?? _hs1For(handshake));
      }
      return false;
    });
    _receiverPending.removeWhere(
      (_, pending) =>
          current.difference(pending.createdAt) > kPendingHandshakeExpiry,
    );
    _expireSessions(current);
    return out;
  }

  void _expireSessions(DateTime current) {
    sessions.removeWhere(
      (_, session) =>
          current.difference(session.lastUsed) > kSessionIdleTimeout ||
          current.difference(session.establishedAt) > kSessionMaxAge,
    );
    while (sessions.length > kMaxSessions) {
      String? oldest;
      DateTime? oldestUsed;
      for (final entry in sessions.entries) {
        if (oldestUsed == null || entry.value.lastUsed.isBefore(oldestUsed)) {
          oldest = entry.key;
          oldestUsed = entry.value.lastUsed;
        }
      }
      sessions.remove(oldest);
    }
  }

  /// Route an inbound v2 message (hs1..hs4, serr). Unknown/invalid input is
  /// dropped silently — this is a UDP port on a LAN.
  Future<SessionHandleResult> handle(Map<String, dynamic> json) async {
    final result = SessionHandleResult();
    try {
      switch (json['type']) {
        case RemoteMessageType.hs1:
          await _onHs1(json, result);
          break;
        case RemoteMessageType.hs2:
          await _onHs2(json, result);
          break;
        case RemoteMessageType.hs3:
          await _onHs3(json, result);
          break;
        case RemoteMessageType.hs4:
          await _onHs4(json, result);
          break;
      }
    } catch (_) {
      debugPrint('RemoteSessionManager: dropped malformed message');
    }
    return result;
  }

  Future<void> _onHs2(
    Map<String, dynamic> json,
    SessionHandleResult result,
  ) async {
    final sidB64 = json['sid'] as String?;
    final handshake = _senderHandshakes[sidB64];
    if (handshake == null || handshake.hs3 != null) {
      // Unknown, expired, or hs3 already sent (duplicate hs2) — resend hs3 if
      // we have one so a lost hs3 recovers.
      final done = _senderHandshakes[sidB64]?.hs3;
      if (done != null) result.outgoing.add(done);
      return;
    }
    final epkR = base64Decode(json['epk'] as String);
    final spkR = base64Decode(json['spk'] as String);
    final peerName = (json['name'] as String?) ?? 'TV';
    final peerProtocolVersion = _readProtocolVersion(json['v']);

    final statics = await loadStaticKeyPair();
    final spkS = (await statics.extractPublicKey()).bytes;

    final ee = await _dh(handshake.ephemeral, epkR);
    final es = await _dh(handshake.ephemeral, spkR);
    final se = await _dh(statics, epkR);
    final transcript = await RemoteSessionCrypto.transcriptHash(
      sid: handshake.sid,
      com: handshake.com,
      epkS: handshake.epk,
      spkS: spkS,
      epkR: epkR,
      spkR: spkR,
      nc: handshake.nc,
      senderProtocolVersion: protocolVersion,
      receiverProtocolVersion: peerProtocolVersion,
    );
    final keys = await RemoteSessionCrypto.deriveKeys(
      ikm: [...ee, ...es, ...se],
      transcript: transcript,
    );
    final tagS = await RemoteSessionCrypto.confirmTag(
      keys.conf,
      'drc2 hs3 sender',
    );

    handshake.hs3 = {
      'type': RemoteMessageType.hs3,
      'sid': handshake.sidB64,
      'epk': base64Encode(handshake.epk),
      'spk': base64Encode(spkS),
      'nc': base64Encode(handshake.nc),
      'tag': base64Encode(tagS),
    };
    // Park the derived material on the handshake so hs4 can finish without
    // recomputing; stored via closure fields below.
    _senderDerived[handshake.sidB64] = (
      keys: keys,
      peerSpk: spkR,
      peerName: peerName,
      peerProtocolVersion: peerProtocolVersion,
    );
    result.outgoing.add(handshake.hs3!);
  }

  final Map<
    String,
    ({
      SessionKeys keys,
      List<int> peerSpk,
      String peerName,
      int peerProtocolVersion,
    })
  >
  _senderDerived = {};

  Future<void> _onHs4(
    Map<String, dynamic> json,
    SessionHandleResult result,
  ) async {
    final sidB64 = json['sid'] as String?;
    final handshake = _senderHandshakes[sidB64];
    final derived = _senderDerived[sidB64];
    if (handshake == null || derived == null) return;
    final expected = await RemoteSessionCrypto.confirmTag(
      derived.keys.conf,
      'drc2 hs4 receiver',
    );
    final tag = base64Decode(json['tag'] as String);
    if (!RemoteSessionCrypto.constantTimeEquals(expected, tag)) {
      debugPrint('RemoteSessionManager: hs4 tag mismatch, dropping');
      return;
    }
    final session = RemoteSession(
      sid: handshake.sid,
      role: RemoteSessionRole.sender,
      keys: derived.keys,
      peerStaticKey: derived.peerSpk,
      peerFingerprint: await RemoteSessionCrypto.fingerprint(derived.peerSpk),
      peerName: derived.peerName,
      peerProtocolVersion: derived.peerProtocolVersion,
      sasCode: await RemoteSessionCrypto.sasCode(derived.keys.sas),
      establishedAt: now(),
    );
    sessions[session.sidB64] = session;
    _senderHandshakes.remove(sidB64);
    _senderDerived.remove(sidB64);
    _expireSessions(now());
    result.established = session;
  }

  // ----------------------------------------------------------- receiver ---

  Future<void> _onHs1(
    Map<String, dynamic> json,
    SessionHandleResult result,
  ) async {
    final sidB64 = json['sid'] as String?;
    if (sidB64 == null) return;
    final com = base64Decode(json['com'] as String);

    final existing = _receiverPending[sidB64];
    if (existing != null) {
      // Duplicate hs1: same commitment gets the cached (identical) hs2;
      // a different commitment under the same sid is hostile — ignore.
      if (RemoteSessionCrypto.constantTimeEquals(existing.com, com)) {
        result.outgoing.add(existing.hs2);
      }
      return;
    }
    // Each pending entry costs an X25519 keygen and lives up to 30s — cap
    // them so an hs1 flood can't grow state or burn CPU on the always-on TV.
    if (_receiverPending.length >= kMaxSessions * 2) {
      debugPrint('RemoteSessionManager: pending handshake cap hit, dropping');
      return;
    }

    final statics = await loadStaticKeyPair();
    final spkR = (await statics.extractPublicKey()).bytes;
    final ephemeral = await RemoteSessionCrypto.x25519.newKeyPair();
    final epkR = (await ephemeral.extractPublicKey()).bytes;
    final pending = _ReceiverPending(
      sid: base64Decode(sidB64),
      com: com,
      ephemeral: ephemeral,
      epk: epkR,
      createdAt: now(),
      senderName: (json['name'] as String?) ?? 'Phone',
      senderProtocolVersion: _readProtocolVersion(json['v']),
      hs2: {
        'type': RemoteMessageType.hs2,
        'v': protocolVersion,
        'sid': sidB64,
        'epk': base64Encode(epkR),
        'spk': base64Encode(spkR),
        'name': deviceName(),
      },
    );
    _receiverPending[sidB64] = pending;
    result.outgoing.add(pending.hs2);
  }

  Future<void> _onHs3(
    Map<String, dynamic> json,
    SessionHandleResult result,
  ) async {
    final sidB64 = json['sid'] as String?;
    final pending = _receiverPending[sidB64];
    if (pending == null) return;
    if (pending.hs4 != null) {
      // Duplicate hs3 — replay the cached hs4.
      result.outgoing.add(pending.hs4!);
      return;
    }
    final epkS = base64Decode(json['epk'] as String);
    final spkS = base64Decode(json['spk'] as String);
    final nc = base64Decode(json['nc'] as String);
    final tagS = base64Decode(json['tag'] as String);

    // The reveal must match the commitment from hs1 — this ordering is the
    // whole point of the extra round trip.
    final expectedCom = await RemoteSessionCrypto.commitment(epkS, nc);
    if (!RemoteSessionCrypto.constantTimeEquals(expectedCom, pending.com)) {
      debugPrint('RemoteSessionManager: hs3 commitment mismatch, dropping');
      return;
    }

    final statics = await loadStaticKeyPair();
    final spkR = (await statics.extractPublicKey()).bytes;
    final ee = await _dh(pending.ephemeral, epkS);
    final es = await _dh(statics, epkS);
    final se = await _dh(pending.ephemeral, spkS);
    final transcript = await RemoteSessionCrypto.transcriptHash(
      sid: pending.sid,
      com: pending.com,
      epkS: epkS,
      spkS: spkS,
      epkR: pending.epk,
      spkR: spkR,
      nc: nc,
      senderProtocolVersion: pending.senderProtocolVersion,
      receiverProtocolVersion: protocolVersion,
    );
    final keys = await RemoteSessionCrypto.deriveKeys(
      ikm: [...ee, ...es, ...se],
      transcript: transcript,
    );
    final expectedTag = await RemoteSessionCrypto.confirmTag(
      keys.conf,
      'drc2 hs3 sender',
    );
    if (!RemoteSessionCrypto.constantTimeEquals(expectedTag, tagS)) {
      debugPrint('RemoteSessionManager: hs3 tag mismatch, dropping');
      return;
    }

    final tagR = await RemoteSessionCrypto.confirmTag(
      keys.conf,
      'drc2 hs4 receiver',
    );
    pending.hs4 = {
      'type': RemoteMessageType.hs4,
      'sid': sidB64,
      'tag': base64Encode(tagR),
    };

    final session = RemoteSession(
      sid: pending.sid,
      role: RemoteSessionRole.receiver,
      keys: keys,
      peerStaticKey: spkS,
      peerFingerprint: await RemoteSessionCrypto.fingerprint(spkS),
      // hs3 carries no name field — the sender introduced itself in hs1.
      peerName: pending.senderName,
      peerProtocolVersion: pending.senderProtocolVersion,
      sasCode: await RemoteSessionCrypto.sasCode(keys.sas),
      establishedAt: now(),
    );
    sessions[session.sidB64] = session;
    _expireSessions(now());
    result.outgoing.add(pending.hs4!);
    result.established = session;
  }

  static Future<List<int>> _dh(
    SimpleKeyPair keyPair,
    List<int> remotePublicKey,
  ) async {
    final shared = await RemoteSessionCrypto.x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return shared.extractBytes();
  }

  static int _readProtocolVersion(Object? raw) {
    final value = raw is num ? raw.toInt() : 2;
    return value >= 2 && value <= 1000 ? value : 2;
  }

  // ------------------------------------------------------------ traffic ---

  RemoteSession? sessionBySid(String sidB64) => sessions[sidB64];

  /// Whether [sidB64] belongs to anything this manager is tracking —
  /// established, mid-handshake as sender, or pending as receiver. The wiring
  /// layer uses this to refuse caching endpoints for arbitrary sids a LAN
  /// flooder invents.
  bool knowsSid(String sidB64) =>
      sessions.containsKey(sidB64) ||
      _senderHandshakes.containsKey(sidB64) ||
      _receiverPending.containsKey(sidB64);

  /// Seal a command JSON into an ecmd envelope on [session].
  Future<Map<String, dynamic>> sealCommand(
    RemoteSession session,
    Map<String, dynamic> commandJson,
  ) async {
    final n = session.nextN();
    session.lastUsed = now();
    return {
      'type': RemoteMessageType.ecmd,
      'sid': session.sidB64,
      'n': n,
      'ct': await RemoteSessionCrypto.sealEcmd(
        key: session.sendKey,
        sid: session.sid,
        n: n,
        commandJson: jsonEncode(commandJson),
      ),
    };
  }

  /// Open an inbound ecmd. Returns the decoded inner command and its session,
  /// or a serr reply for an unknown sid, or nothing for replays/tampering.
  Future<
    ({
      Map<String, dynamic>? command,
      RemoteSession? session,
      Map<String, dynamic>? serr,
    })
  >
  openCommand(Map<String, dynamic> json) async {
    final sidB64 = json['sid'] as String?;
    final n = (json['n'] as num?)?.toInt();
    final ct = json['ct'] as String?;
    if (sidB64 == null || n == null || ct == null) {
      return (command: null, session: null, serr: null);
    }
    final session = sessions[sidB64];
    if (session == null) {
      return (
        command: null,
        session: null,
        serr: {
          'type': RemoteMessageType.serr,
          'sid': sidB64,
          'code': 'unknown_sid',
        },
      );
    }
    final plaintext = await RemoteSessionCrypto.openEcmd(
      key: session.recvKey,
      sid: session.sid,
      n: n,
      ctB64: ct,
    );
    if (plaintext == null) return (command: null, session: null, serr: null);
    // Only counters that authenticated may advance the replay window.
    if (!session.acceptIncoming(n)) {
      return (command: null, session: null, serr: null);
    }
    session.lastUsed = now();
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map<String, dynamic>) {
      return (command: null, session: null, serr: null);
    }
    return (command: decoded, session: session, serr: null);
  }
}

// ---------------------------------------------------------------------------
// Pairing gate (receiver side)
// ---------------------------------------------------------------------------

enum PairingRequestOutcome { shown, autoAuthorized, busy }

enum PairProofOutcome { ok, wrong, tooEarly, rateLimited, noRequest }

class PairingDisplay {
  final RemoteSession session;
  final DateTime shownAt;
  PairingDisplay(this.session, this.shownAt);

  String get code => session.sasCode;
  String get peerName => session.peerName;
  String get peerFingerprint => session.peerFingerprint;
}

/// Single-flight controller for the on-TV pairing code. UI layers register as
/// presenters; when none is mounted the router raises a fallback dialog.
class PairingGate extends ChangeNotifier {
  final DateTime Function() now;
  final bool Function(String fingerprint) isRemembered;

  PairingGate({required this.isRemembered, DateTime Function()? now})
    : now = now ?? DateTime.now;

  PairingDisplay? _current;
  PairingDisplay? get current => _current;

  int _presenters = 0;
  bool get hasPresenter => _presenters > 0;
  void registerPresenter() {
    _presenters += 1;
  }

  void unregisterPresenter() {
    if (_presenters > 0) _presenters -= 1;
  }

  final Map<String, List<DateTime>> _attempts = {};

  /// An authorized-or-showing decision for an inbound pair/request.
  PairingRequestOutcome request(RemoteSession session) {
    if (session.authorized) return PairingRequestOutcome.autoAuthorized;
    if (kRememberPairedSenders && isRemembered(session.peerFingerprint)) {
      // The triple-DH already proved possession of the remembered static key.
      session.authorized = true;
      return PairingRequestOutcome.autoAuthorized;
    }
    if (_current != null && _current!.session.sidB64 != session.sidB64) {
      return PairingRequestOutcome.busy;
    }
    _current ??= PairingDisplay(session, now());
    notifyListeners();
    return PairingRequestOutcome.shown;
  }

  Future<PairProofOutcome> confirmProof(
    RemoteSession session,
    List<int> proof,
  ) async {
    final display = _current;
    if (display == null || display.session.sidB64 != session.sidB64) {
      return PairProofOutcome.noRequest;
    }
    if (now().difference(display.shownAt) < kPairingMinDisplay) {
      return PairProofOutcome.tooEarly;
    }
    final fp = session.peerFingerprint;
    final window = _attempts[fp] ?? <DateTime>[];
    window.removeWhere((t) => now().difference(t) > kPairingAttemptWindow);
    if (window.length >= kPairingMaxAttempts) {
      return PairProofOutcome.rateLimited;
    }
    final expected = await RemoteSessionCrypto.pairProof(
      session.keys.conf,
      display.code,
    );
    if (RemoteSessionCrypto.constantTimeEquals(expected, proof)) {
      session.authorized = true;
      _attempts.remove(fp);
      _current = null;
      notifyListeners();
      return PairProofOutcome.ok;
    }
    window.add(now());
    _attempts[fp] = window;
    notifyListeners();
    return PairProofOutcome.wrong;
  }

  void cancel() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Expire a stale code (call on a timer).
  void tick() {
    final display = _current;
    if (display != null &&
        now().difference(display.shownAt) > kPairingCodeTimeout) {
      _current = null;
      notifyListeners();
    }
  }
}

// ---------------------------------------------------------------------------
// Legacy interop decision
// ---------------------------------------------------------------------------

enum LegacySendDecision {
  /// Peer speaks v2 — encrypt.
  encrypted,

  /// Peer never advertised v2 and policy is block: refuse with "update the
  /// TV app first".
  blocked,

  /// Peer never advertised v2 and policy allows an explicit override.
  askOverride,

  /// Peer previously advertised v2 (pinned) but now claims v1 — treat as an
  /// active downgrade, never fall back.
  suspectedDowngrade,
}

LegacySendDecision decideLegacyCredentialSend({
  required bool peerAdvertisesV2,
  required bool peerPinnedV2,
  LegacySendPolicy policy = kLegacyCredentialPolicy,
}) {
  if (peerAdvertisesV2) return LegacySendDecision.encrypted;
  if (peerPinnedV2) return LegacySendDecision.suspectedDowngrade;
  return policy == LegacySendPolicy.block
      ? LegacySendDecision.blocked
      : LegacySendDecision.askOverride;
}
