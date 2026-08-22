import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'package:debrify/screens/video_player/services/external_subtitle_payload.dart';
import 'package:debrify/screens/video_player/services/subtitle_track_utils.dart';

void main() {
  group('external subtitle payload', () {
    test('decompresses gzip and preserves the underlying extension', () {
      final original = utf8.encode('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
      final compressed = GZipEncoder().encode(original);

      final payload = prepareExternalSubtitlePayload(
        compressed,
        Uri.parse('https://example.test/subtitle.srt.gz'),
      );

      expect(payload.bytes, original);
      expect(payload.extension, 'srt');
    });

    test('extracts a supported subtitle from zip responses', () {
      final captions = utf8.encode('WEBVTT\n\n');
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 4, utf8.encode('nope')))
        ..addFile(ArchiveFile('captions/movie.vtt', captions.length, captions));

      final payload = prepareExternalSubtitlePayload(
        ZipEncoder().encode(archive),
        Uri.parse('https://example.test/download'),
      );

      expect(utf8.decode(payload.bytes), 'WEBVTT\n\n');
      expect(payload.extension, 'vtt');
    });

    test('rejects empty and HTML error payloads', () {
      expect(
        () => prepareExternalSubtitlePayload(
          const [],
          Uri.parse('https://example.test/subtitle'),
        ),
        throwsFormatException,
      );
      expect(
        () => prepareExternalSubtitlePayload(
          utf8.encode('<html>not a subtitle</html>'),
          Uri.parse('https://example.test/subtitle'),
        ),
        throwsFormatException,
      );
    });

    test('stops streamed responses at the compressed input limit', () async {
      final chunk = Uint8List(3 * 1024 * 1024);

      await expectLater(
        readBoundedSubtitleResponse(Stream.fromIterable([chunk, chunk])),
        throwsFormatException,
      );
    });

    test('rejects a gzip bomb before decoded output can exceed the limit', () {
      final expanded = Uint8List(maxDecodedSubtitleBytes + 1)
        ..fillRange(0, maxDecodedSubtitleBytes + 1, 0x41);
      final compressed = GZipEncoder().encode(expanded);
      expect(compressed.length, lessThan(maxSubtitleResponseBytes));

      expect(
        () => prepareExternalSubtitlePayload(
          compressed,
          Uri.parse('https://example.test/bomb.srt.gz'),
        ),
        throwsFormatException,
      );
    });

    test('rejects oversized ZIP entries before materializing content', () {
      final expanded = Uint8List(maxDecodedSubtitleBytes + 1)
        ..fillRange(0, maxDecodedSubtitleBytes + 1, 0x41);
      final archive = Archive()
        ..addFile(ArchiveFile('bomb.srt', expanded.length, expanded));
      final compressed = ZipEncoder().encode(archive);
      expect(compressed.length, lessThan(maxSubtitleResponseBytes));

      expect(
        () => prepareExternalSubtitlePayload(
          compressed,
          Uri.parse('https://example.test/bomb.zip'),
        ),
        throwsFormatException,
      );
    });

    test('bounds ZIP expansion even when size metadata lies', () {
      final expanded = Uint8List(maxDecodedSubtitleBytes + 1)
        ..fillRange(0, maxDecodedSubtitleBytes + 1, 0x41);
      final archive = Archive()
        ..addFile(ArchiveFile('bomb.srt', expanded.length, expanded));
      final compressed = Uint8List.fromList(ZipEncoder().encode(archive));

      _overwriteZipUncompressedSizes(compressed, 1);

      expect(
        () => prepareExternalSubtitlePayload(
          compressed,
          Uri.parse('https://example.test/lying-bomb.zip'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('size limit'),
          ),
        ),
      );
    });

    test('rejects excessive ZIP entries before archive allocation', () {
      final archive = Archive();
      for (var i = 0; i <= maxSubtitleZipEntries; i++) {
        archive.addFile(ArchiveFile('$i.srt', 1, const [0x31]));
      }

      expect(
        () => prepareExternalSubtitlePayload(
          ZipEncoder().encode(archive),
          Uri.parse('https://example.test/many.zip'),
        ),
        throwsFormatException,
      );
    });

    test('cache identity is URL-specific and stable', () {
      final first = externalSubtitleCacheStem('https://a.test/sub?id=1');
      expect(first, externalSubtitleCacheStem('https://a.test/sub?id=1'));
      expect(
        first,
        isNot(externalSubtitleCacheStem('https://a.test/sub?id=2')),
      );
    });
  });

  test('URI subtitle tracks retain external identity', () {
    final track = mk.SubtitleTrack.uri(
      '/tmp/subtitle.srt',
      title: 'English',
      language: 'en',
    );

    expect(track.external, isTrue);
    expect(track.externalFilename, '/tmp/subtitle.srt');
  });

  test(
    'embedded track projection preserves sidecars and excludes addon files',
    () {
      final tracks = <mk.SubtitleTrack>[
        mk.SubtitleTrack.auto(),
        mk.SubtitleTrack.no(),
        const mk.SubtitleTrack('1', 'English', 'en'),
        const mk.SubtitleTrack(
          '2',
          'Sidecar English',
          'en',
          external: true,
          externalFilename: '/movies/title.en.srt',
        ),
        const mk.SubtitleTrack(
          '3',
          'Addon English',
          'en',
          external: true,
          externalFilename: '/tmp/stremio_sub_a1b2c3.srt',
        ),
      ];

      expect(embeddedSubtitleTracks(tracks).map((track) => track.id), [
        '1',
        '2',
      ]);
    },
  );

  test('addon track classification is limited to app-managed temp files', () {
    expect(
      isAppManagedAddonSubtitleTrack(
        mk.SubtitleTrack.uri('file:///tmp/stremio_sub_abc.vtt'),
      ),
      isTrue,
    );
    expect(
      isAppManagedAddonSubtitleTrack(
        const mk.SubtitleTrack(
          '4',
          'Addon',
          'en',
          external: true,
          externalFilename: r'C:\Temp\stremio_sub_abc.ass',
        ),
      ),
      isTrue,
    );
    expect(
      isAppManagedAddonSubtitleTrack(
        mk.SubtitleTrack.uri('/movies/title.en.srt'),
      ),
      isFalse,
    );
  });

  group('native bitmap subtitle rendering', () {
    test('recognizes image metadata and common bitmap codecs', () {
      expect(
        requiresNativeSubtitleRendering(
          const mk.SubtitleTrack('1', 'English', 'en', image: true),
        ),
        isTrue,
      );
      for (final codec in const [
        'hdmv_pgs_subtitle',
        'pgssub',
        'dvb_subtitle',
        'dvd_subtitle',
        'xsub',
      ]) {
        expect(
          requiresNativeSubtitleRendering(
            mk.SubtitleTrack('1', 'English', 'en', codec: codec),
          ),
          isTrue,
          reason: codec,
        );
      }
    });

    test('keeps text, external, auto, and off tracks in Flutter rendering', () {
      for (final track in <mk.SubtitleTrack>[
        const mk.SubtitleTrack('1', 'English', 'en', codec: 'subrip'),
        mk.SubtitleTrack.uri('/tmp/subtitle.ass'),
        mk.SubtitleTrack.auto(),
        mk.SubtitleTrack.no(),
      ]) {
        expect(requiresNativeSubtitleRendering(track), isFalse);
      }
    });
  });
}

void _overwriteZipUncompressedSizes(Uint8List bytes, int size) {
  for (var i = 0; i <= bytes.length - 4; i++) {
    final isLocalHeader =
        bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x03 &&
        bytes[i + 3] == 0x04;
    final isCentralHeader =
        bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x01 &&
        bytes[i + 3] == 0x02;
    if (isLocalHeader) _writeUint32Le(bytes, i + 22, size);
    if (isCentralHeader) _writeUint32Le(bytes, i + 24, size);
  }
}

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
