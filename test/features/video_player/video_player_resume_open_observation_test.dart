import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 late initial open observes the outgoing server after a duration-only change before closing it',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      await t.runAsync(f.initialize);
      final server = ResumeServerDriver(t, f);
      final init = CompletionDelivery('configurePlayerAudio', (v) => v == null);
      try {
        await server.prepare();
        final screen = server.screen();
        await init.run(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              theme: ThemeData.dark(),
              home: VideoPlayerScreen(
                videoUrl: screen.videoUrl,
                title: screen.title,
                contentType: screen.contentType,
                contentImdbId: screen.contentImdbId,
                httpHeaders: screen.httpHeaders,
                // This public split-audio path opens directly; no startup VOD gate
                // masks the late initial continuation being characterized.
                audioUrl: 'https://player.test/p14-audio.m4a',
                stremioSources: server.sources,
                stremioCurrentSourceIndex: 0,
                resolveStremioSource: (s) async => s.directUrl,
              ),
            ),
          ),
        );
        await f.until(
          t,
          () => init.pending.isNotEmpty && f.controllers.isNotEmpty,
        );
        f.player.deliverReady();
        expect(f.player.calls.where((c) => c.$1 == 'open'), isEmpty);
        // The early keyboard caller rebuilds the State after native creation,
        // while initial configuration remains suspended (phase-4 precedent).
        await f.key(t, LogicalKeyboardKey.keyA);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(
          t,
          sheet.resolveSource(server.sources[1]),
        ))!;
        final selected = f.actions.start(
          'source before initial configuration returns',
          () async {
            final dynamic callback = sheet.onSourceSelected;
            final result = callback(1, url);
            if (result is Future) await result;
          },
        );
        await f.finish(t, selected.future);
        expect(init.pending, isNotEmpty);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.until(
          t,
          () => server.reports.any(
            (r) => server.body(r)['PositionTicks'] == 300000 * 10000,
          ),
        );
        expect(
          server.body(server.reports.last)['MediaSourceId'],
          'version_2160',
        );
        expect(
          server.body(server.reports.last)['PositionTicks'],
          300000 * 10000,
        );
        f.player.state = f.player.state.copyWith(
          duration: const Duration(seconds: 1),
        );
        f.player.emit('duration', const Duration(seconds: 1));
        await f.advance(t);
        expect(
          server.reports.where((r) => r.url.path.endsWith('/Stopped')),
          isEmpty,
        );
        final closedBeforeOpen = server.closed.length;
        init.release();
        await f.until(
          t,
          () => server.reports.any((r) => r.url.path.endsWith('/Stopped')),
        );
        final stop = server.reports.firstWhere(
          (r) => r.url.path.endsWith('/Stopped'),
        );
        expect(server.body(stop)['MediaSourceId'], 'version_2160');
        expect(
          server.body(stop)['PositionTicks'],
          1000 * 10000,
          reason:
              'The outgoing observation clamps to the duration-only update before commit(null) closes the old session',
        );
        await f.until(t, () => server.closed.length > closedBeforeOpen);
        await f.advance(t, const Duration(seconds: 2));
        await f.actions.settle(t);
      } finally {
        init.release();
        await f.advance(t, const Duration(seconds: 2));
        // The outgoing client already closed at the open boundary above;
        // route disposal must drain, rather than require another close.
        await f.close(t);
        server.restoreFactories();
      }
    },
  );
}
