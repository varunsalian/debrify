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

/// Send a config payload to a TV, splitting it across packets when it doesn't
/// fit in one.
///
/// UDP gives us ~1400 bytes per datagram, which most credentials fit inside
/// and most collections do not — a few hundred starred channels is tens of
/// kilobytes. Oversized payloads are sliced and bracketed by a start packet
/// naming [command] as the transfer's `kind`, so the receiver can replay the
/// reassembled string through the normal handler for that command.
///
/// There is no acknowledgement or retransmission: a dropped chunk means the
/// receiver's buffer times out and the whole payload is lost. Callers must
/// treat `false` — and silence — as a real failure and say so.
///
/// (`remote_channel_export.dart` predates this and carries its own copy of the
/// same protocol for Debrify TV channels. If that one changes, change this.)
Future<bool> sendConfigPayloadToDevice(
  RemoteControlState state,
  String command,
  String targetIp,
  String payload, {
  required String label,
  Duration chunkPace = const Duration(milliseconds: 50),
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

  final startOk = await state.sendConfigCommandToDevice(
    ConfigCommand.debrifyChannelStart,
    targetIp,
    configData: chunkStartBody(
      transferId: transferId,
      command: command,
      label: label,
      totalChunks: chunks.length,
      encSidB64: encSidB64,
      encN: encN,
    ),
    plaintextTransport: true,
  );
  if (!startOk) return false;

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
