import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 non-IPTV next transition suppresses server observations while native pause is pending',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final server = ResumeServerDriver(t, f);
      final pause = Completer<void>();
      try {
        await server.prepare();
        final screen = server.screen();
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: screen.videoUrl,
            title: screen.title,
            contentType: screen.contentType,
            contentImdbId: screen.contentImdbId,
            httpHeaders: screen.httpHeaders,
            stremioSources: server.sources,
            stremioCurrentSourceIndex: 0,
            resolveStremioSource: screen.resolveStremioSource,
            requestMagicNext: () async => null,
          ),
        );
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.until(t, () => server.reports.isNotEmpty);
        await f.actions.settle(t);
        final before = server.reports.length;
        f.player.delays['pause'] = pause;
        final next = f.actions.start('next with native pause held', () async {
          final dynamic callback = playerControls(t).onNext;
          final result = callback();
          if (result is Future) await result;
        }, held: true);
        await f.until(t, () => f.player.calls.any((c) => c.$1 == 'pause'));
        expect(next.isCompleted, isFalse);
        expect(f.player.state.playing, isTrue);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 6),
        );
        f.player.emit('position', f.player.state.position);
        await f.actions.settle(t);
        expect(next.isCompleted, isFalse);
        expect(server.reports, hasLength(before));
        // A menu checkpoint is also allowed for non-IPTV, but its server
        // observation must obey the same transition guard as the stream.
        await DisplayModeDriver(t, f).speed(1.5);
        await f.actions.settle(t);
        expect(next.isCompleted, isFalse);
        expect(server.reports, hasLength(before));
        pause.complete();
        await f.finish(t, next.future);
        await f.player.play();
        await f.until(t, () => server.reports.length > before);
        expect(
          server.body(server.reports.last)['PositionTicks'],
          360000 * 10000,
        );
      } finally {
        if (!pause.isCompleted) pause.complete();
        await f.close(t);
        server.restoreFactories();
      }
    },
  );
}
