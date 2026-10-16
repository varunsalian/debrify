import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  for (final replacementMs in [0, 1]) {
    testWidgets(
      replacementMs == 0
          ? 'Resume P14 direct switch with unknown duration guards the carried target before duration recovers'
          : 'Resume P14 direct switch with a one millisecond known duration exempts the carried target before duration recovers',
      (t) async {
        late final VideoPlayerEnvironment f;
        var opens = 0;
        f = VideoPlayerEnvironment(
          configurePlayer: (p) {
            p.seekAcknowledgementPosition = Duration.zero;
            p.onOpen = () {
              p.publishFrame(
                duration: opens++ == 0
                    ? const Duration(minutes: 20)
                    : Duration(milliseconds: replacementMs),
              );
              f.controllers.last.publishFrame();
            };
          },
        );
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        final a = source(
          'P14 unknown A.mkv',
          'https://player.test/p14-unknown-a.mp4',
        );
        final b = source(
          'P14 unknown B.mkv',
          'https://player.test/p14-unknown-b.mp4',
        );
        try {
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: 'P14 unknown duration',
              traktProgressPercent: 20,
              stremioSources: [a, b],
              stremioCurrentSourceIndex: 0,
              resolveStremioSource: (s) async => s.directUrl,
            ),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            contains(const Duration(minutes: 4)),
          );
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
          final url = (await f.finish(t, sheet.resolveSource(b)))!;
          final callback = sheet.onSourceSelected as dynamic;
          final selected = f.actions.start(
            'direct source without duration',
            () async {
              final result = callback(1, url);
              if (result is Future) await result;
            },
          );
          await f.finish(t, selected.future);
          expect(f.player.state.playlist.medias.first.uri, b.directUrl);
          expect(
            f.player.state.duration,
            Duration(milliseconds: replacementMs),
          );
          expect(f.player.state.position, Duration.zero);
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            everyElement(const Duration(minutes: 4)),
          );
          f.player.state = f.player.state.copyWith(
            duration: const Duration(minutes: 20),
          );
          f.player.emit('duration', f.player.state.duration);
          await f.advance(t);
          final menu = await display.menu(PlayerMenuSection.speed);
          menu.onSpeedSelected(1.5);
          await f.actions.settle(t);
          final saved = await f.finish(
            t,
            VideoResumeStorage.getVideoResume(a.directUrl!),
          );
          expect(saved?['positionMs'], replacementMs == 0 ? 240000 : 0);
          expect(saved?['speed'], 1.5);
          expect(saved?['durationMs'], 1200000);
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
