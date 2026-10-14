import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/services/external_subtitle_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/subtitle_apply_driver.dart';
import 'support/subtitle_streaming_http.dart';

const captionBytes = [
  49,
  10,
  48,
  48,
  58,
  48,
  48,
  58,
  48,
  49,
  44,
  48,
  48,
  48,
  32,
  45,
  45,
  62,
  32,
  48,
  48,
  58,
  48,
  48,
  58,
  48,
  50,
  44,
  48,
  48,
  48,
  10,
  0xe9,
  0xa1,
  10,
];

StremioSubtitle payloadSubtitle(String name) => StremioSubtitle(
  id: name,
  url: 'https://payload.test/$name.srt',
  lang: 'eng',
  source: 'Streaming original caller',
);

Future<void> removeFixture(SubtitleApplyDriver d) async {
  await d.close();
  await d.t.runAsync(() => d.f.directory.delete(recursive: true));
}

void main() {
  for (final encoding in ['raw', 'gzip', 'zip']) {
    testWidgets('subtitle download preserves actual $encoding non-UTF8 bytes', (
      t,
    ) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final transport = SubtitleStreamingHttp(d.f.network);
      HttpOverrides.global = transport;
      final sub = payloadSubtitle(encoding);
      List<int> bytes = captionBytes;
      if (encoding == 'gzip') {
        bytes = GZipEncoder().encode(bytes);
      }
      if (encoding == 'zip') {
        bytes = ZipEncoder().encode(
          Archive()..addFile(ArchiveFile('inside.srt', bytes.length, bytes)),
        );
      }
      transport.routes[sub.url] = () async => http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
      );
      try {
        await d.mount();
        final panel = await d.menu();
        expect(
          await d.f.finish(
            t,
            d.observe(() => panel.onAddonSubtitleSelected(sub, '1')),
          ),
          isTrue,
        );
        final file = File(
          '${d.f.directory.path}/stremio_sub_${externalSubtitleCacheStem(sub.url)}.srt',
        );
        expect(await t.runAsync(file.readAsBytes), captionBytes);
        expect(
          transport.requests.map((r) => r.url.toString()),
          contains(sub.url),
        );
        expect(transport.closed, hasLength(1));
        expect(
          d.logs,
          contains(
            'VideoPlayer: Subtitle written to temp file: ${file.path} (${captionBytes.length} bytes)',
          ),
        );
      } finally {
        await removeFixture(d);
      }
    });
  }

  for (final kind in [
    'declared too large',
    'declared limit',
    'undeclared limit',
    'undeclared too large',
    'empty',
    'html',
    'status',
    'body error',
  ]) {
    testWidgets('subtitle streaming $kind pins limits, effects and client close', (
      t,
    ) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final transport = SubtitleStreamingHttp(d.f.network);
      HttpOverrides.global = transport;
      final sub = payloadSubtitle(kind.replaceAll(' ', '-'));
      var listened = false;
      final full = Uint8List(maxSubtitleResponseBytes)..setAll(0, captionBytes);
      final body = kind == 'html'
          ? utf8.encode('  <!DOCTYPE HTML><html>login</html>')
          : kind == 'empty'
          ? <int>[]
          : captionBytes;
      transport.routes[sub.url] = () async => http.StreamedResponse(
        kind == 'body error'
            ? Stream.error(StateError('stream delivery failed'))
            : Stream<List<int>>.multi((c) {
                listened = true;
                c.add(kind.startsWith('undeclared') ? full : body);
                if (kind == 'undeclared too large') {
                  c.add([0]);
                }
                c.close();
              }),
        kind == 'status' ? 503 : 200,
        contentLength: kind == 'declared too large'
            ? maxSubtitleResponseBytes + 1
            : kind == 'declared limit'
            ? maxSubtitleResponseBytes
            : null,
      );
      try {
        await d.mount();
        final panel = await d.menu();
        final result = await d.f.finish(
          t,
          d.observe(() => panel.onAddonSubtitleSelected(sub, '1')),
        );
        final accepted = kind == 'declared limit' || kind == 'undeclared limit';
        expect(result, accepted);
        final file = File(
          '${d.f.directory.path}/stremio_sub_${externalSubtitleCacheStem(sub.url)}.srt',
        );
        expect(file.existsSync(), accepted);
        if (accepted) {
          expect(
            file.lengthSync(),
            kind.startsWith('undeclared') ? full.length : body.length,
          );
          expect(
            (await t.runAsync(file.readAsBytes))!.take(captionBytes.length),
            captionBytes,
          );
        } else {
          expect(d.player.state.track.subtitle.id, '1');
        }
        if (kind == 'declared too large' || kind == 'status') {
          expect(listened, isFalse);
        }
        expect(transport.closed, hasLength(1));
        if (kind == 'declared too large') {
          expect(
            d.logs,
            contains(
              'VideoPlayer: Subtitle download rejected: ${maxSubtitleResponseBytes + 1} bytes exceeds limit',
            ),
          );
        } else if (kind == 'status') {
          expect(
            d.logs,
            contains('VideoPlayer: Subtitle download failed: HTTP 503'),
          );
        } else if (kind == 'body error') {
          expect(
            d.logs,
            contains(
              'VideoPlayer: Subtitle download/write failed: Bad state: stream delivery failed',
            ),
          );
        }
      } finally {
        await removeFixture(d);
      }
    });
  }

  for (final stage in ['header', 'body']) {
    testWidgets(
      'subtitle $stage timeout starts its own fifteen-second budget',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final transport = SubtitleStreamingHttp(d.f.network);
        HttpOverrides.global = transport;
        final sub = payloadSubtitle(stage);
        final headers = Completer<http.StreamedResponse>();
        var listened = false;
        final stream = StreamController<List<int>>(
          onListen: () => listened = true,
        );
        transport.routes[sub.url] = () => headers.future;
        try {
          await d.mount();
          final panel = await d.menu();
          var completed = false;
          final pending = d.observe(
            () => panel.onAddonSubtitleSelected(sub, '1'),
          );
          pending.then((_) => completed = true);
          await d.f.until(
            t,
            () => transport.requests.any((r) => r.url.toString() == sub.url),
          );
          await d.f.advance(t, const Duration(seconds: 14));
          expect(completed, isFalse);
          expect(transport.closed, isEmpty);
          if (stage == 'body') {
            headers.complete(http.StreamedResponse(stream.stream, 200));
            await d.f.until(t, () => listened);
            await d.f.advance(t, const Duration(seconds: 14));
            expect(completed, isFalse);
            expect(transport.closed, isEmpty);
          }
          await d.f.advance(t, const Duration(seconds: 1));
          expect(completed, isTrue);
          expect(await d.f.finish(t, pending), isFalse);
          expect(transport.closed, hasLength(1));
          expect(d.player.state.track.subtitle.id, '1');
          if (stage == 'header') {
            headers.complete(
              http.StreamedResponse(Stream.value(captionBytes), 200),
            );
          } else {
            stream.add(captionBytes);
            await stream.close();
          }
          await d.f.advance(t);
          expect(
            d.f.directory.listSync().where(
              (f) => f.path.contains('stremio_sub_'),
            ),
            isEmpty,
          );
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
}
