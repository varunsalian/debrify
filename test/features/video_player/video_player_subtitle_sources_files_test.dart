import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/screens/video_player/services/external_subtitle_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/subtitle_apply_driver.dart';
import 'support/subtitle_streaming_http.dart';
import 'video_player_subtitle_apply_boundaries_test.dart'
    show boundaryScreen, crossBoundary;
import 'video_player_subtitle_sources_payload_test.dart'
    show captionBytes, payloadSubtitle, removeFixture;

void main() {
  for (final kind in ['reuse', 'empty', 'oversize']) {
    testWidgets('subtitle $kind cache is inspected and registered for cleanup', (
      t,
    ) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final transport = SubtitleStreamingHttp(d.f.network);
      HttpOverrides.global = transport;
      final sub = payloadSubtitle('cache-$kind');
      final stem = externalSubtitleCacheStem(sub.url);
      final cached = File(
        '${d.f.directory.path}/stremio_sub_$stem.${kind == 'reuse' ? 'vtt' : 'srt'}',
      );
      await t.runAsync(
        () => cached.writeAsBytes(
          kind == 'reuse'
              ? captionBytes
              : kind == 'empty'
              ? <int>[]
              : Uint8List(maxDecodedSubtitleBytes + 1),
        ),
      );
      transport.routes[sub.url] = () async =>
          http.StreamedResponse(Stream.value(captionBytes), 200);
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
        final selected = File(
          '${d.f.directory.path}/stremio_sub_$stem.${kind == 'reuse' ? 'vtt' : 'srt'}',
        );
        expect(await t.runAsync(selected.readAsBytes), captionBytes);
        expect(
          transport.requests.where((r) => r.url.toString() == sub.url),
          hasLength(kind == 'reuse' ? 0 : 1),
        );
        await crossBoundary(d, 'dispose');
        expect(selected.existsSync(), isFalse);
        expect(d.f.directory.existsSync(), isTrue);
      } finally {
        await removeFixture(d);
      }
    });
  }

  for (final stage in ['write', 'rename']) {
    for (final event in ['reset', 'dispose']) {
      testWidgets(
        'subtitle held $stage after $event preserves the original file leak',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          final transport = SubtitleStreamingHttp(d.f.network);
          HttpOverrides.global = transport;
          final sub = payloadSubtitle('held-$stage-$event');
          transport.routes[sub.url] = () async =>
              http.StreamedResponse(Stream.value(captionBytes), 200);
          final file = File(
            '${d.f.directory.path}/stremio_sub_${externalSubtitleCacheStem(sub.url)}.srt',
          );
          final partial = File('${file.path}.part');
          final barrier = SubtitleFileBarrier(partial.path, stage);
          try {
            await d.mount(screen: boundaryScreen);
            final panel = await d.menu();
            var completed = false;
            final pending = IOOverrides.runWithIOOverrides(
              () => d.observe(() => panel.onAddonSubtitleSelected(sub, '1')),
              barrier,
            );
            pending.then((_) => completed = true);
            await d.f.until(t, () => barrier.entered.isCompleted);
            await d.f.advance(t, const Duration(milliseconds: 100));
            expect(completed, isFalse);
            expect(barrier.writes, hasLength(1));
            expect(barrier.writes.single.bytes, captionBytes);
            expect(barrier.writes.single.flush, isTrue);
            expect(d.player.state.track.subtitle.id, '1');
            expect(file.existsSync(), isFalse);
            expect(partial.existsSync(), stage == 'rename');
            if (stage == 'rename') {
              expect(await t.runAsync(partial.readAsBytes), captionBytes);
            }
            await crossBoundary(d, event);
            expect(file.existsSync(), isFalse);
            expect(partial.existsSync(), stage == 'rename');
            barrier.release.complete();
            expect(await d.f.finish(t, pending), isFalse);
            expect(file.existsSync(), isTrue);
            expect(await t.runAsync(file.readAsBytes), captionBytes);
            expect(partial.existsSync(), isFalse);
            expect(transport.closedFor(sub.url), hasLength(1));
            expect(d.f.directory.existsSync(), isTrue);
            // These are the application's actual files before fixture deletion.
            // Disposal/reset cleanup already ran before the late registration.
          } finally {
            if (!barrier.release.isCompleted) {
              barrier.release.complete();
            }
            await removeFixture(d);
          }
        },
      );
    }
  }
  testWidgets(
    'subtitle overlapping same-stem downloads replace in completion order and clean one registered file',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final transport = SubtitleStreamingHttp(d.f.network);
      HttpOverrides.global = transport;
      final sub = payloadSubtitle('overlap');
      final responses = <Completer<http.StreamedResponse>>[];
      transport.routes[sub.url] = () {
        final response = Completer<http.StreamedResponse>();
        responses.add(response);
        return response.future;
      };
      try {
        await d.mount();
        final panel = await d.menu();
        final first = d.observe(() => panel.onAddonSubtitleSelected(sub, '1'));
        await d.f.until(t, () => responses.length == 1);
        final second = d.observe(() => panel.onAddonSubtitleSelected(sub, '1'));
        await d.f.until(t, () => responses.length == 2);
        var doneA = false;
        var doneB = false;
        first.then((_) => doneA = true);
        second.then((_) => doneB = true);
        expect(doneA, isFalse);
        expect(doneB, isFalse);
        responses[0].complete(
          http.StreamedResponse(Stream.value(captionBytes), 200),
        );
        expect(await d.f.finish(t, first), isTrue);
        final file = File(d.player.state.track.subtitle.id);
        expect(await t.runAsync(file.readAsBytes), captionBytes);
        expect(doneB, isFalse);
        final replacement = [...captionBytes, 0x0a, 0x41];
        responses[1].complete(
          http.StreamedResponse(Stream.value(replacement), 200),
        );
        expect(await d.f.finish(t, second), isTrue);
        expect(d.player.state.track.subtitle.id, file.path);
        expect(await t.runAsync(file.readAsBytes), replacement);
        expect(File('${file.path}.part').existsSync(), isFalse);
        expect(transport.closedFor(sub.url), hasLength(2));
        await crossBoundary(d, 'dispose');
        expect(file.existsSync(), isFalse);
        expect(
          d.logs.where((s) => s.contains('Failed to delete temp subtitle')),
          isEmpty,
        );
      } finally {
        for (final response in responses) {
          if (!response.isCompleted) {
            response.complete(http.StreamedResponse(const Stream.empty(), 404));
          }
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle cleanup catches a missing file and clears registration before the next reset',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: boundaryScreen);
        expect(await d.addon('cleanup-missing'), isTrue);
        final path = d.player.state.track.subtitle.id;
        await t.runAsync(() => File(path).delete());
        await crossBoundary(d, 'reset');
        final failures = d.logs
            .where(
              (s) => s.startsWith(
                'VideoPlayer: Failed to delete temp subtitle $path:',
              ),
            )
            .toList();
        expect(failures, hasLength(1));
        expect(File(path).existsSync(), isFalse);
        await crossBoundary(d, 'dispose');
        expect(
          d.logs.where(
            (s) => s.startsWith(
              'VideoPlayer: Failed to delete temp subtitle $path:',
            ),
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  for (final ext in ['srt', 'vtt', 'ass', 'ssa', 'ttml', 'xml', 'sub']) {
    testWidgets(
      'subtitle valid $ext cache bypasses HTTP and is deleted by the original cleanup caller',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final transport = SubtitleStreamingHttp(d.f.network);
        HttpOverrides.global = transport;
        final sub = payloadSubtitle('cache-extension-$ext');
        final file = File(
          '${d.f.directory.path}/stremio_sub_${externalSubtitleCacheStem(sub.url)}.$ext',
        );
        await t.runAsync(() => file.writeAsBytes(captionBytes));
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
          expect(d.player.state.track.subtitle.id, file.path);
          expect(await t.runAsync(file.readAsBytes), captionBytes);
          expect(
            transport.requests.where((r) => r.url.toString() == sub.url),
            isEmpty,
          );
          await crossBoundary(d, 'dispose');
          expect(file.existsSync(), isFalse);
          expect(d.f.directory.existsSync(), isTrue);
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final length in [1, maxDecodedSubtitleBytes]) {
    testWidgets(
      'subtitle cache accepts exact $length byte boundary without a download',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final transport = SubtitleStreamingHttp(d.f.network);
        HttpOverrides.global = transport;
        final sub = payloadSubtitle('cache-boundary-$length');
        final cached = File(
          '${d.f.directory.path}/stremio_sub_${externalSubtitleCacheStem(sub.url)}.srt',
        );
        final bytes = Uint8List(length)..[0] = 0x31;
        await t.runAsync(() => cached.writeAsBytes(bytes));
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
          expect(d.player.state.track.subtitle.id, cached.path);
          expect(await t.runAsync(cached.readAsBytes), bytes);
          expect(
            transport.requests.where((r) => r.url.toString() == sub.url),
            isEmpty,
          );
          await crossBoundary(d, 'dispose');
          expect(cached.existsSync(), isFalse);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle invalid cache is removed even if replacement download is rejected',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final transport = SubtitleStreamingHttp(d.f.network);
      HttpOverrides.global = transport;
      final sub = payloadSubtitle('invalid-cache-reject');
      final cached = File(
        '${d.f.directory.path}/stremio_sub_${externalSubtitleCacheStem(sub.url)}.srt',
      );
      await t.runAsync(() => cached.writeAsBytes([]));
      transport.routes[sub.url] = () async =>
          http.StreamedResponse(const Stream.empty(), 503);
      try {
        await d.mount();
        final panel = await d.menu();
        expect(
          await d.f.finish(
            t,
            d.observe(() => panel.onAddonSubtitleSelected(sub, '1')),
          ),
          isFalse,
        );
        expect(cached.existsSync(), isFalse);
        expect(d.player.state.track.subtitle.id, '1');
        expect(transport.closedFor(sub.url), hasLength(1));
      } finally {
        await removeFixture(d);
      }
    },
  );
}
