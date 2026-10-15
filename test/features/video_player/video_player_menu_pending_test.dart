import 'dart:async';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';

void main() {
  for (final stage in ['download', 'apply']) {
    for (final failure in [false, true]) {
      testWidgets(
        'p13 close panel during $stage failure=$failure retains apply-owned sync reset',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          final download = Completer<http.Response>();
          final apply = Completer<void>();
          const sub = StremioSubtitle(
            id: 'p13-pending',
            url: 'https://player.test/p13.srt',
            lang: 'eng',
            source: 'Pending fixture',
            label: 'P13 remote captions',
          );
          try {
            await d.mount(
              screen: const VideoPlayerScreen(
                videoUrl: 'https://player.test/menu-pending.mp4',
                title: 'Pending menu',
                initialSubtitles: [sub],
              ),
            );
            final panel = await d.menu();
            panel.onSubtitleStyleChanged!(
              const SubtitleSettingsData(
                sizeIndex: 0,
                colorIndex: 0,
                bgIndex: 0,
                styleIndex: 0,
                syncOffsetMs: 1500,
              ),
            );
            await d.f.advance(t);
            expect(d.native.properties['sub-delay'], '1.500');
            d.f.network.handler = (r) => r.url == Uri.parse(sub.url)
                ? download.future
                : http.Response('{}', 404);
            d.player.heldOperation = (name, value) =>
                stage == 'apply' && name == 'subtitle';
            d.player.beforeOperation = (name, value) async {
              if (d.player.heldOperation!(name, value)) {
                await apply.future;
                if (failure) throw StateError('native apply failed');
              }
            };
            if (stage == 'apply') {
              download.complete(
                http.Response(
                  '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
                  200,
                ),
              );
            }
            await t.ensureVisible(d.row(sub.displayName));
            await d.f.advance(t);
            await t.tap(d.row(sub.displayName));
            await d.f.until(
              t,
              () => stage == 'download'
                  ? d.f.network.requests.any((r) => r.url == Uri.parse(sub.url))
                  : d.player.calls.any(
                      (c) =>
                          c.$1 == 'subtitle' &&
                          c.$2 is mk.SubtitleTrack &&
                          (c.$2 as mk.SubtitleTrack).id.contains(
                            'stremio_sub_',
                          ),
                    ),
            );
            panel.onClose();
            await d.f.advance(t, const Duration(milliseconds: 350));
            expect(find.byType(PlayerMenuPanel), findsNothing);
            if (stage == 'download') {
              download.complete(
                http.Response(
                  failure ? '' : '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
                  failure ? 404 : 200,
                ),
              );
            }
            apply.complete();
            await d.f.actions.settle(t);
            await d.f.advance(t, const Duration(milliseconds: 300));
            expect(
              d.native.properties['sub-delay'],
              failure ? '1.500' : '0.000',
            );
            expect(
              (await d.saved(title: 'Pending menu'))?['subtitleTrackId'],
              failure ? null : 'stremio:p13-pending',
            );
            expect(d.errors, isEmpty);
          } finally {
            if (!download.isCompleted) {
              download.complete(http.Response('', 404));
            }
            if (!apply.isCompleted) apply.complete();
            await d.close();
          }
        },
      );
    }
  }
}
