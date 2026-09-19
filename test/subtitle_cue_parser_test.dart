import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/video_player/services/subtitle_cue_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'subtitle-cue-parser-test-',
    );
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  Future<List<SubtitleCue>> parseBytes(
    List<int> bytes, {
    String extension = 'srt',
  }) async {
    final file = File('${tempDirectory.path}/subtitle.$extension');
    await file.writeAsBytes(bytes);
    return SubtitleCueParser.parseFile(file.path);
  }

  test(
    'decodes UTF-8 Arabic instead of treating bytes as characters',
    () async {
      const arabic = 'مرحبا بالعالم';
      final cues = await parseBytes(
        utf8.encode('1\n00:00:01,000 --> 00:00:03,000\n$arabic\n'),
      );

      expect(cues, hasLength(1));
      expect(cues.single.text, arabic);
    },
  );

  test('decodes UTF-8 BOM without leaking it into parsing', () async {
    final cues = await parseBytes([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('1\n00:00:01,000 --> 00:00:03,000\n你好\n'),
    ]);

    expect(cues, hasLength(1));
    expect(cues.single.text, '你好');
  });

  test('decodes little-endian UTF-16 BOM', () async {
    const content = '1\n00:00:01,000 --> 00:00:03,000\nПривет\n';
    final bytes = <int>[0xFF, 0xFE];
    for (final codeUnit in content.codeUnits) {
      bytes
        ..add(codeUnit & 0xFF)
        ..add(codeUnit >> 8);
    }

    final cues = await parseBytes(bytes);

    expect(cues, hasLength(1));
    expect(cues.single.text, 'Привет');
  });

  test('decodes big-endian UTF-16 BOM', () async {
    const content = 'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n日本語\n';
    final bytes = <int>[0xFE, 0xFF];
    for (final codeUnit in content.codeUnits) {
      bytes
        ..add(codeUnit >> 8)
        ..add(codeUnit & 0xFF);
    }

    final cues = await parseBytes(bytes, extension: 'vtt');

    expect(cues, hasLength(1));
    expect(cues.single.text, '日本語');
  });

  test('keeps the legacy single-byte fallback', () async {
    final cues = await parseBytes([
      ...latin1.encode('1\n00:00:01,000 --> 00:00:03,000\nCaf'),
      0xE9,
      0x0A,
    ]);

    expect(cues, hasLength(1));
    expect(cues.single.text, 'Café');
  });
}
