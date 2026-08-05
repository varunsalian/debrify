import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';
import 'remote_control_state.dart';

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

/// Split a payload into base64 slices sized so the JSON packet carrying one
/// still fits a single UDP datagram. See [kChunkRawBytesPerChunk] for the
/// budget arithmetic; `remote_chunked_send_test.dart` pins the result.
List<String> encodePayloadChunks(String payload) {
  final bytes = utf8.encode(payload);
  final chunks = <String>[];
  for (var offset = 0; offset < bytes.length; offset += kChunkRawBytesPerChunk) {
    final end = (offset + kChunkRawBytesPerChunk).clamp(0, bytes.length);
    chunks.add(base64.encode(Uint8List.sublistView(bytes, offset, end)));
  }
  return chunks;
}

/// Reassemble what [encodePayloadChunks] produced. Slices are decoded to bytes
/// and joined *before* the UTF-8 decode — a multi-byte character straddling a
/// slice boundary would be mangled by decoding each one separately.
String decodePayloadChunks(List<String> chunks) {
  return utf8.decode([
    for (final chunk in chunks) ...base64.decode(chunk),
  ]);
}

/// The start packet's body: what the transfer is, and how many pieces to wait
/// for.
String chunkStartBody({
  required String transferId,
  required String command,
  required String label,
  required int totalChunks,
}) {
  return jsonEncode({
    'transferId': transferId,
    'kind': command,
    // Older receivers read this field and have no notion of `kind`; keeping it
    // populated means they show a sensible label before failing to parse the
    // payload as a channel, rather than throwing on a missing key.
    'channelName': label,
    'totalChunks': totalChunks,
  });
}

/// One chunk packet's body.
String chunkPieceBody({
  required String transferId,
  required int index,
  required String data,
}) {
  return jsonEncode({
    'transferId': transferId,
    'index': index,
    'data': data,
  });
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
}) async {
  if (fitsSinglePacket(payload)) {
    return state.sendConfigCommandToDevice(
      command,
      targetIp,
      configData: payload,
    );
  }

  final chunks = encodePayloadChunks(payload);

  debugPrint(
    'RemoteChunkedSend: $label via $command '
    '(${chunks.length} chunks)',
  );

  final transferId =
      '${DateTime.now().microsecondsSinceEpoch}_${label.hashCode.abs() % 1000000000}';

  final startOk = await state.sendConfigCommandToDevice(
    ConfigCommand.debrifyChannelStart,
    targetIp,
    configData: chunkStartBody(
      transferId: transferId,
      command: command,
      label: label,
      totalChunks: chunks.length,
    ),
  );
  if (!startOk) return false;

  for (var i = 0; i < chunks.length; i++) {
    // Pace the send: a burst of hundreds of datagrams overruns the receiver's
    // socket buffer, and a chunk dropped there costs the whole transfer.
    await Future.delayed(const Duration(milliseconds: 50));
    final ok = await state.sendConfigCommandToDevice(
      ConfigCommand.debrifyChannelChunk,
      targetIp,
      configData: chunkPieceBody(
        transferId: transferId,
        index: i,
        data: chunks[i],
      ),
    );
    if (!ok) return false;
  }

  return true;
}
