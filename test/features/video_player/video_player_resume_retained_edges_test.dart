import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/resume_driver.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 first Stremio TV duration consumes the deferred verified startup seek once',
    (t) async {
      late VideoPlayerEnvironment f;
      f = VideoPlayerEnvironment(
        configurePlayer: (p) {
          p.onOpen = () {
            p.publishFrame(duration: Duration.zero);
            f.controllers.last.publishFrame();
          };
        },
      );
      await t.runAsync(f.initialize);
      final verifier = ResumeVerifierDriver(t, f);
      try {
        await verifier.observe(
          () => f.mount(
            t,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/p14-deferred.mp4',
              title: 'P14 deferred',
              startAtPercent: .5,
              stremioTvChannels: [
                {'id': 'a', 'name': 'A'},
              ],
              stremioTvCurrentChannelId: 'a',
            ),
          ),
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        f.player.state = f.player.state.copyWith(
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', const Duration(minutes: 20));
        await f.advance(t, const Duration(milliseconds: 800));
        await verifier.drain();
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 10),
        ]);
        f.player.emit('duration', const Duration(minutes: 20));
        await f.advance(t);
        expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
        expect(
          verifier.timers.map((v) => v.$1),
          contains(const Duration(milliseconds: 800)),
        );
      } finally {
        await f.close(t);
        await f.advance(t, const Duration(milliseconds: 800));
        await verifier.drain();
      }
    },
  );

  testWidgets(
    'Resume P14 native playing edges report server pause and resume without a position or save event',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final server = ResumeServerDriver(t, f);
      try {
        await server.prepare();
        await f.mount(t, server.screen());
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.until(t, () => server.reports.isNotEmpty);
        expect(server.body(server.reports.last)['IsPaused'], false);
        final start = server.reports.length;
        await f.player.pause();
        await f.until(t, () => server.reports.length > start);
        expect(server.body(server.reports.last)['IsPaused'], true);
        expect(
          server.body(server.reports.last)['PositionTicks'],
          300000 * 10000,
        );
        final paused = server.reports.length;
        await f.player.play();
        await f.until(t, () => server.reports.length > paused);
        expect(server.body(server.reports.last)['IsPaused'], false);
        expect(
          server.body(server.reports.last)['PositionTicks'],
          300000 * 10000,
        );
      } finally {
        await server.disposePlayback();
        await f.close(t);
        server.restoreFactories();
      }
    },
  );
}
