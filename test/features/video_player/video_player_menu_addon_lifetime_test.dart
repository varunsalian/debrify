import 'dart:async';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart'
    show boundaryScreen, crossBoundary;

void main() {
  for (final stage in ['download', 'apply']) {
    for (final event in ['reset', 'dispose']) {
      testWidgets(
        'p13 addon menu $stage completing after $event rejects stale publication',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          final download = Completer<http.Response>();
          final apply = Completer<void>();
          Future<bool>? pending;
          const subtitle = StremioSubtitle(
            id: 'p13-lifetime',
            url: 'https://player.test/lifetime.srt',
            lang: 'eng',
            source: 'Lifetime fixture',
          );
          bool external(Object? value) =>
              value is mk.SubtitleTrack && value.id.contains('stremio_sub_');
          try {
            await d.mount(screen: boundaryScreen);
            d.f.network.handler = (request) =>
                request.url == Uri.parse(subtitle.url)
                ? download.future
                : http.Response('{}', 404);
            d.player.heldOperation = (name, value) =>
                stage == 'apply' &&
                name == 'subtitle' &&
                external(value) &&
                !apply.isCompleted;
            d.player.beforeOperation = (name, value) async {
              if (d.player.heldOperation!(name, value)) await apply.future;
            };
            if (stage == 'apply') {
              download.complete(
                http.Response(
                  '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
                  200,
                ),
              );
            }
            final menu = await d.menu();
            pending = d.observe(
              () => menu.onAddonSubtitleSelected(subtitle, '1'),
            );
            await d.f.until(
              t,
              () => stage == 'download'
                  ? d.f.network.requests.any(
                      (request) => request.url == Uri.parse(subtitle.url),
                    )
                  : d.player.calls.any(
                      (call) => call.$1 == 'subtitle' && external(call.$2),
                    ),
            );
            await crossBoundary(d, event);
            if (!download.isCompleted) {
              download.complete(
                http.Response(
                  '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
                  200,
                ),
              );
            }
            apply.complete();
            expect(await d.f.finish(t, pending!), isFalse);
            final applied = d.player.calls.where(
              (call) => call.$1 == 'subtitle' && external(call.$2),
            );
            expect(
              applied,
              hasLength(stage == 'download' ? 0 : 1),
              reason:
                  'a pre-apply rejection cannot touch native subtitles; an admitted apply keeps its original native write',
            );
            expect(d.errors, isEmpty);
          } finally {
            if (!download.isCompleted) {
              download.complete(http.Response('{}', 404));
            }
            if (!apply.isCompleted) apply.complete();
            if (pending != null) await d.f.finish(t, pending);
            await d.close();
          }
        },
      );
    }
  }
}
