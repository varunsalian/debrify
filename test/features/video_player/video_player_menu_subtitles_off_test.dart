import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_sources_driver.dart';

void main() {
  for (final failed in [false, true]) {
    testWidgets(
      'p13 subtitles off after an addon selection failure=$failed preserves its result and menu identity',
      (t) async {
        final d = SubtitleSourcesDriver(t);
        await d.setup();
        try {
          await d.register('p13-off');
          await d.order();
          await d.mount(
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/off.mp4',
              title: 'Off boundary',
              contentImdbId: 'tt1100001',
              contentType: 'movie',
            ),
          );
          final menu = await d.menu();
          final slots = await d.f.finish(
            t,
            StremioSubtitleService.instance.fetchSubtitleSlots(
              type: 'movie',
              imdbId: 'tt1100001',
            ),
          );
          final subtitle = slots.single.subtitles.single;
          expect(
            await d.f.finish(t, menu.onAddonSubtitleSelected(subtitle, '1')),
            isTrue,
          );
          d.player.emit('position', const Duration(seconds: 2));
          await d.f.advance(t);
          expect(
            t
                .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
                .selectedSubtitleId,
            'stremio:${subtitle.id}',
          );
          if (failed) {
            d.player.beforeOperation = (name, value) {
              if (name == 'subtitle' &&
                  value is mk.SubtitleTrack &&
                  value.id == 'no') {
                throw StateError('fixture off refused');
              }
            };
          }
          expect(await d.f.finish(t, menu.onSubtitlesOff('1')), !failed);
          menu.onClose();
          await d.f.advance(t, const Duration(milliseconds: 350));
          await d.menu();
          expect(
            t
                .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
                .selectedSubtitleId,
            failed ? 'stremio:${subtitle.id}' : 'no',
          );
          t
              .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
              .onSyncRequested!();
          await d.f.advance(t);
          expect(
            find.byType(SubtitleLinePickerOverlay),
            failed ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(SyncStepperOverlay),
            failed ? findsNothing : findsOneWidget,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
