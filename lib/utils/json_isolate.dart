import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Payloads below this decode faster inline than the isolate round-trip
/// (spawn + copying the source string out and the decoded tree back) costs.
/// Above it, decoding on the UI isolate is what causes the frame-drop
/// micro-stutters while catalog rows / torrent lists load on weak TV CPUs.
const int _isolateDecodeThreshold = 32 * 1024;

dynamic _decode(String source) => json.decode(source);

/// [json.decode] that runs big payloads through [compute] so the UI isolate
/// never blocks on parsing a large catalog/stream/torrent response. Small
/// payloads decode inline — same result, no isolate overhead. Throws
/// [FormatException] on invalid JSON either way, so it's a drop-in
/// replacement inside existing try/catch blocks.
Future<dynamic> decodeJsonAsync(String source) async {
  if (source.length < _isolateDecodeThreshold) {
    return json.decode(source);
  }
  return compute(_decode, source, debugLabel: 'decodeJsonAsync');
}
