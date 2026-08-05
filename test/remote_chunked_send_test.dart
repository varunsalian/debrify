import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/remote_control/remote_chunked_send.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';

/// The framing that carries an oversized config payload to a TV.
///
/// UDP has no retransmission here, so a packet that exceeds the MTU and gets
/// fragmented (or dropped) costs the entire transfer with no error anywhere.
/// The size budget in [kChunkRawBytesPerChunk] was computed by hand; these
/// tests are what keep it honest as the envelope changes.
void main() {
  String packetFor(String data) => chunkPieceBody(
        // Worst case for the id: the real one is microseconds + a hash, so
        // pad to a length no live transfer will exceed.
        transferId: '9' * 40,
        index: 999999,
        data: data,
      );

  group('packet budget', () {
    test('a full chunk packet still fits one datagram', () {
      final payload = 'x' * (kChunkRawBytesPerChunk * 3);
      final chunks = encodePayloadChunks(payload);

      // The first chunk is a full slice — the worst case.
      final packet = packetFor(chunks.first);
      expect(utf8.encode(packet).length, lessThanOrEqualTo(kChunkMaxBytes));
    });

    test('a start packet fits one datagram', () {
      final body = chunkStartBody(
        transferId: '9' * 40,
        command: ConfigCommand.iptvFavorites,
        label: 'IPTV favorites',
        totalChunks: 99999,
      );
      expect(utf8.encode(body).length, lessThanOrEqualTo(kChunkMaxBytes));
    });

    test('multi-byte text does not overflow a packet', () {
      // base64 of N bytes is the same length whatever those bytes are, but a
      // payload of emoji reaches the byte budget in a quarter of the
      // characters — the slicing has to be by bytes, not runes.
      final payload = '🎬' * 2000;
      final chunks = encodePayloadChunks(payload);
      for (final chunk in chunks) {
        expect(
          utf8.encode(packetFor(chunk)).length,
          lessThanOrEqualTo(kChunkMaxBytes),
        );
      }
    });
  });

  group('single-packet threshold', () {
    test('accounts for the escaping the envelope adds', () {
      // A JSON array of channel records is mostly quotes, and the sender
      // embeds this string inside another JSON document — so every quote
      // costs two bytes on the wire. Fill right up to the raw budget and the
      // escaped form is well past it: measuring raw length would send this as
      // one oversized datagram that fragments and vanishes.
      final records = <Map<String, String>>[];
      var payload = '[]';
      while (true) {
        final next = [
          ...records,
          {
            'url': 'http://panel.example:8080/live/user/pw/${records.length}.ts',
            'name': 'Channel ${records.length}',
            'playlistId': 'p1',
          },
        ];
        if (jsonEncode(next).length > kChunkDataMaxBytes) break;
        records.add(next.last);
        payload = jsonEncode(records);
      }

      expect(payload.length, lessThanOrEqualTo(kChunkDataMaxBytes),
          reason: 'raw length fits the budget');
      expect(fitsSinglePacket(payload), isFalse,
          reason: 'but the escaped form does not');
    });

    test('a small payload still goes direct', () {
      expect(fitsSinglePacket(jsonEncode({'access_token': 'abc123'})), isTrue);
    });

    test('anything rejected by the threshold survives chunking', () {
      final payload = jsonEncode([
        for (var i = 0; i < 8; i++)
          {'url': 'http://panel.example:8080/live/user/pw/$i.ts'},
      ]);
      if (!fitsSinglePacket(payload)) {
        expect(decodePayloadChunks(encodePayloadChunks(payload)), payload);
      }
    });
  });

  group('round trip', () {
    test('reassembles exactly what was sent', () {
      final payload = jsonEncode([
        for (var i = 0; i < 400; i++)
          {
            'url': 'http://panel.example:8080/live/user/pw/$i.ts',
            'name': 'Channel $i',
            'group': 'Entertainment',
            'playlistId': 'p1',
          },
      ]);

      final chunks = encodePayloadChunks(payload);

      expect(chunks.length, greaterThan(1), reason: 'payload should chunk');
      expect(decodePayloadChunks(chunks), payload);
    });

    test('survives a character straddling a slice boundary', () {
      // Decoding each slice on its own would split this emoji's bytes across
      // two utf8.decode calls and corrupt it.
      final payload = '${'a' * (kChunkRawBytesPerChunk - 2)}🎬${'b' * 50}';
      expect(decodePayloadChunks(encodePayloadChunks(payload)), payload);
    });

    test('a payload just over the single-packet budget chunks cleanly', () {
      final payload = 'y' * (kChunkDataMaxBytes + 1);
      final chunks = encodePayloadChunks(payload);
      expect(decodePayloadChunks(chunks), payload);
    });
  });

  group('start packet', () {
    test('names the command so the receiver can replay it', () {
      final decoded = jsonDecode(
        chunkStartBody(
          transferId: 't1',
          command: ConfigCommand.iptvLists,
          label: 'IPTV lists',
          totalChunks: 7,
        ),
      ) as Map<String, dynamic>;

      expect(decoded['kind'], ConfigCommand.iptvLists);
      expect(decoded['totalChunks'], 7);
      // Receivers built before `kind` existed read this key and would throw
      // on its absence.
      expect(decoded['channelName'], 'IPTV lists');
    });
  });
}
