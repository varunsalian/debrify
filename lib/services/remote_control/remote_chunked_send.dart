import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';
import 'remote_control_state.dart';
import 'remote_session.dart';

/// Whether [payload] can ride in one datagram as a plain `configData` string.
///
/// The check has to measure the payload *as serialized*, not raw: the sender
/// embeds it as a JSON string inside the command envelope, so every quote
/// costs two bytes on the wire. A JSON array of channel records is mostly
/// quotes — measuring raw length lets a ~1.2 KB payload go out as a ~1.5 KB
/// datagram, which fragments and gets dropped with no error anywhere.
bool fitsSinglePacket(String payload) {
  return utf8.encode(jsonEncode(payload)).length <= kChunkDataMaxBytes;
}

/// Same question for the encrypted path: the payload rides inside a command
/// JSON that gets AES-GCM sealed and base64d into an ecmd envelope, so the
/// budget shrinks by the 4/3 inflation plus envelope overhead. Worst-case
/// arithmetic, pinned by a budget test.
bool fitsSinglePacketEncrypted(String payload) {
  // Inner command JSON: payload as an escaped JSON string + envelope fields.
  final inner = utf8.encode(jsonEncode(payload)).length + 80;
  // Ciphertext = inner + 16B tag, then base64 (padded up to +4).
  final ctB64 = ((inner + 16) * 4 / 3).ceil() + 4;
  return ctB64 + kEcmdEnvelopeOverhead <= kChunkMaxBytes;
}

/// Split a payload into base64 slices sized so the JSON packet carrying one
/// still fits a single UDP datagram. See [kChunkRawBytesPerChunk] for the
/// budget arithmetic; `remote_chunked_send_test.dart` pins the result.
List<String> encodePayloadChunks(String payload) {
  final bytes = utf8.encode(payload);
  final chunks = <String>[];
  for (
    var offset = 0;
    offset < bytes.length;
    offset += kChunkRawBytesPerChunk
  ) {
    final end = (offset + kChunkRawBytesPerChunk).clamp(0, bytes.length);
    chunks.add(base64.encode(Uint8List.sublistView(bytes, offset, end)));
  }
  return chunks;
}

/// Reassemble what [encodePayloadChunks] produced. Slices are decoded to bytes
/// and joined *before* the UTF-8 decode — a multi-byte character straddling a
/// slice boundary would be mangled by decoding each one separately.
String decodePayloadChunks(List<String> chunks) {
  return utf8.decode([for (final chunk in chunks) ...base64.decode(chunk)]);
}

/// The start packet's body: what the transfer is, and how many pieces to wait
/// for. [encSidB64]/[encN] mark a v2 sealed-blob transfer: the reassembled
/// bytes are AES-GCM ciphertext bound to that session and counter.
String chunkStartBody({
  required String transferId,
  required String command,
  required String label,
  required int totalChunks,
  String? encSidB64,
  int? encN,
}) {
  return jsonEncode({
    'transferId': transferId,
    'kind': command,
    // Older receivers read this field and have no notion of `kind`; keeping it
    // populated means they show a sensible label before failing to parse the
    // payload as a channel, rather than throwing on a missing key.
    'channelName': label,
    'totalChunks': totalChunks,
    if (encSidB64 != null && encN != null) ...{
      'enc': 1,
      'sid': encSidB64,
      'n': encN,
    },
  });
}

/// One chunk packet's body.
String chunkPieceBody({
  required String transferId,
  required int index,
  required String data,
}) {
  return jsonEncode({'transferId': transferId, 'index': index, 'data': data});
}

/// A repair request's body: the receiver names the chunk indices that never
/// arrived. Kept to [kChunkNeedMaxIndices] so the request itself fits one
/// datagram; a round that cannot name every gap catches the rest next round.
String chunkNeedBody({
  required String transferId,
  required List<int> missing,
}) {
  return jsonEncode({
    'transferId': transferId,
    'need': missing.take(kChunkNeedMaxIndices).toList(),
  });
}

/// Parse of [chunkNeedBody]; null when malformed (a hostile or corrupt
/// request must simply be ignored).
({String transferId, List<int> missing})? parseChunkNeedBody(String data) {
  try {
    final map = jsonDecode(data) as Map<String, dynamic>;
    final transferId = map['transferId'] as String;
    final raw = map['need'] as List<dynamic>;
    if (transferId.isEmpty || raw.isEmpty) return null;
    final missing = <int>[];
    for (final value in raw.take(kChunkNeedMaxIndices)) {
      if (value is! int || value < 0) return null;
      missing.add(value);
    }
    return (transferId: transferId, missing: missing);
  } catch (_) {
    return null;
  }
}

/// Sent chunks kept for gap repair. Chunks are SEALED ciphertext slices —
/// caching them holds no plaintext — and resends go to the transfer's
/// original target only, never to whoever asked (a forged need can at worst
/// re-send ciphertext to the legitimate receiver).
class ChunkResendCache {
  ChunkResendCache._();

  static final Map<String, _CachedTransfer> _transfers = {};
  static final Set<String> _resendInFlight = {};

  static void register(String transferId, String targetIp, List<String> chunks) {
    // Bound the cache to the receiver's own concurrent-buffer cap (4): a
    // multi-payload export (config export sends three) must not evict the
    // big first payload while its tail is still being repaired.
    while (_transfers.length >= 4) {
      final oldest = _transfers.keys.first;
      _transfers.remove(oldest)?.expiry.cancel();
    }
    _transfers[transferId] = _CachedTransfer(
      targetIp: targetIp,
      chunks: chunks,
      expiry: Timer(kChunkResendCacheTtl, () => _transfers.remove(transferId)),
    );
  }

  static Future<void> resend(
    RemoteControlState state,
    String transferId,
    List<int> indices, {
    required String requesterIp,
  }) async {
    final cached = _transfers[transferId];
    if (cached == null) {
      debugPrint('ChunkResendCache: no cached transfer for repair');
      return;
    }
    // Only the transfer's own receiver may drive repair. Any other
    // authorized peer naming this transferId (ids ride in cleartext on the
    // transport packets) would otherwise hold a ~350x amplification lever
    // aimed at the legitimate receiver.
    if (requesterIp != cached.targetIp) {
      debugPrint('ChunkResendCache: refusing repair from a different peer');
      return;
    }
    // One repair loop per transfer at a time — overlapping needs (the
    // receiver re-asks every stall period) must not multiply resends.
    if (!_resendInFlight.add(transferId)) return;
    try {
      debugPrint('ChunkResendCache: resending ${indices.length} chunk(s)');
      for (final index in indices) {
        if (index < 0 || index >= cached.chunks.length) continue;
        await Future.delayed(kChunkPace);
        await state.sendConfigCommandToDevice(
          ConfigCommand.debrifyChannelChunk,
          cached.targetIp,
          configData: chunkPieceBody(
            transferId: transferId,
            index: index,
            data: cached.chunks[index],
          ),
          plaintextTransport: true,
        );
      }
    } finally {
      _resendInFlight.remove(transferId);
    }
  }

  @visibleForTesting
  static void debugClear() {
    for (final t in _transfers.values) {
      t.expiry.cancel();
    }
    _transfers.clear();
    _resendInFlight.clear();
  }
}

class _CachedTransfer {
  _CachedTransfer({
    required this.targetIp,
    required this.chunks,
    required this.expiry,
  });

  final String targetIp;
  final List<String> chunks;
  final Timer expiry;
}

/// Send a config payload to a TV, splitting it across packets when it doesn't
/// fit in one.
///
/// UDP gives us ~1400 bytes per datagram, which most credentials fit inside
/// and most collections do not — a few hundred starred channels is tens of
/// kilobytes. Oversized payloads are sliced and bracketed by a start packet
/// naming [command] as the transfer's `kind`, so the receiver can replay the
/// reassembled string through the normal handler for that command.
///
/// Loss is repaired, not prevented: the receiver watches for stalls and asks
/// for exactly the missing indices ([ConfigCommand.debrifyChannelNeed]),
/// which the sender replays from [ChunkResendCache] — that is what makes the
/// aggressive [kChunkPace] safe. A `false` return still means the transfer
/// never got off the ground and callers must say so.
Future<bool> sendConfigPayloadToDevice(
  RemoteControlState state,
  String command,
  String targetIp,
  String payload, {
  required String label,
  Duration chunkPace = kChunkPace,
}) async {
  final session = state.sessionFor(targetIp);

  if (session == null
      ? fitsSinglePacket(payload)
      : fitsSinglePacketEncrypted(payload)) {
    // Small payloads ride the command envelope directly — which is itself
    // sealed end-to-end when a session exists.
    return state.sendConfigCommandToDevice(
      command,
      targetIp,
      configData: payload,
    );
  }

  final transferId =
      '${DateTime.now().microsecondsSinceEpoch}_${label.hashCode.abs() % 1000000000}';

  if (session == null) {
    // Same no-plaintext rule the direct path enforces: with the session gone
    // (expired or revoked mid-transfer), a large payload must FAIL — the
    // chunk pieces ride plaintextTransport and would otherwise carry the raw
    // credential payload past the state-level refusal.
    debugPrint('RemoteChunkedSend: refusing transfer without a session');
    return false;
  }

  // Seal ONCE, then chunk the ciphertext. The chunk transport packets stay
  // plaintext deliberately: they carry only ciphertext and routing
  // metadata, and wrapping each ~1400-byte piece in a second base64-
  // inflating ecmd envelope would blow the single-fragment UDP budget.
  final encN = session.nextN();
  final encSidB64 = session.sidB64;
  final wirePayload = await RemoteSessionCrypto.sealBlob(
    key: session.sendKey,
    sid: session.sid,
    n: encN,
    transferId: transferId,
    kind: command,
    payload: payload,
  );

  final chunks = encodePayloadChunks(wirePayload);

  debugPrint('RemoteChunkedSend: sending sealed chunked transfer');

  // Register for gap repair BEFORE anything hits the wire, so a need that
  // races the tail of the send still finds the cache.
  ChunkResendCache.register(transferId, targetIp, chunks);

  final startBody = chunkStartBody(
    transferId: transferId,
    command: command,
    label: label,
    totalChunks: chunks.length,
    encSidB64: encSidB64,
    encN: encN,
  );
  final startOk = await state.sendConfigCommandToDevice(
    ConfigCommand.debrifyChannelStart,
    targetIp,
    configData: startBody,
    plaintextTransport: true,
  );
  if (!startOk) return false;
  // A lost START is the one packet repair cannot recover (the receiver has
  // no buffer to notice gaps in), so send it twice. Duplicates are safe
  // ONLY here: the receiver rebuilds the buffer on a repeated start, which
  // is a no-op before any chunk has landed and destructive after.
  await Future.delayed(chunkPace);
  await state.sendConfigCommandToDevice(
    ConfigCommand.debrifyChannelStart,
    targetIp,
    configData: startBody,
    plaintextTransport: true,
  );

  for (var i = 0; i < chunks.length; i++) {
    // Pace the send: a burst of hundreds of datagrams overruns the receiver's
    // socket buffer, and a chunk dropped there costs the whole transfer.
    await Future.delayed(chunkPace);
    final ok = await state.sendConfigCommandToDevice(
      ConfigCommand.debrifyChannelChunk,
      targetIp,
      configData: chunkPieceBody(
        transferId: transferId,
        index: i,
        data: chunks[i],
      ),
      plaintextTransport: true,
    );
    if (!ok) return false;
  }

  return true;
}
