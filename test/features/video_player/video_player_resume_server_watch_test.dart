import 'dart:async';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/resume_driver.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final scenario in [
    'save without a new tick',
    'held resume',
    'EOF',
    'profile retirement',
    'source handoff',
    'quiet dispose',
  ]) {
    testWidgets(
      'Resume P14 server watch $scenario reports exact ownership and close order',
      (t) async {
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) {
            if (scenario == 'held resume') {
              p.seekAcknowledgementPosition = const Duration(seconds: 5);
            }
          },
        );
        await t.runAsync(f.initialize);
        final server = ResumeServerDriver(t, f);
        final display = DisplayModeDriver(t, f);
        final verifier = ResumeVerifierDriver(t, f);
        final gate = Completer<void>();
        try {
          await server.prepare();
          final screen = server.screen();
          if (scenario == 'held resume') {
            final target = MediaServerService.watchTargetFor(
              server.sources.first,
            )!;
            await f.finish(
              t,
              VideoProgressStorage.saveVideoPlaybackState(
                videoTitle: screen.title,
                videoUrl: screen.videoUrl,
                imdbId: target.contentId,
                positionMs: 300000,
                durationMs: 1200000,
              ),
            );
          }
          await f.mount(t, screen);
          await f.actions.settle(t);
          if (scenario == 'held resume') {
            expect(
              f.player.state.position,
              const Duration(seconds: 5),
              reason:
                  'Use a shallow positive frame that the server session would otherwise accept',
            );
            expect(
              f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              contains(const Duration(minutes: 5)),
            );
            expect(server.reports, isEmpty);
            final menu = await display.menu(PlayerMenuSection.speed);
            menu.onSpeedSelected(1.25);
            await f.actions.settle(t);
            expect(
              server.reports,
              isEmpty,
              reason:
                  'Neither streams nor save can report the shallow guarded position',
            );
            expect(
              (await f.finish(
                t,
                VideoResumeStorage.getVideoResume(screen.videoUrl),
              ))?['positionMs'],
              300000,
            );
            f.player.seekAcknowledgementPosition = null;
            playerControls(t).onSeekBarChanged(0.3);
            playerControls(t).onSeekBarChangeEnd();
            await f.until(t, () => server.reports.isNotEmpty);
            expect(
              server.body(server.reports.first)['PositionTicks'],
              5000 * 10000,
              reason:
                  'Releasing the guard lets the request-time save observe the old shallow frame before the seek stream edge',
            );
            await f.until(
              t,
              () => server.reports.any(
                (r) => server.body(r)['PositionTicks'] == 360000 * 10000,
              ),
            );
            expect(
              server.body(server.reports.last)['PositionTicks'],
              360000 * 10000,
            );
          } else if (scenario == 'quiet dispose') {
            expect(server.reports, isEmpty);
            await server.disposePlayback();
            expect(server.reports.map((r) => r.url.path), [
              '/base/Sessions/Playing',
              '/base/Sessions/Playing/Stopped',
            ]);
            expect(
              server.reports.map((r) => server.body(r)['PositionTicks']),
              everyElement(80 * 10000),
            );
            expect(
              (await f.finish(
                t,
                VideoResumeStorage.getVideoResume(screen.videoUrl),
              ))?['positionMs'],
              80,
              reason:
                  'Exit still issues its later local checkpoint after observing/closing the watch session',
            );
          } else if (scenario == 'save without a new tick') {
            expect(server.reports, isEmpty);
            final menu = await display.menu(PlayerMenuSection.speed);
            menu.onSpeedSelected(1.25);
            await f.until(t, () => server.reports.isNotEmpty);
            expect(
              server.body(server.reports.first)['PositionTicks'],
              80 * 10000,
            );
            expect(server.body(server.reports.first)['IsPaused'], false);
          } else if (scenario == 'EOF') {
            f.player.state = f.player.state.copyWith(
              position: const Duration(minutes: 20),
            );
            f.player.emit('position', f.player.state.position);
            await f.until(t, () => server.reports.isNotEmpty);
            await f.actions.settle(t);
            expect(
              server.reports.where(
                (r) =>
                    r.url.path.endsWith('/Stopped') ||
                    r.url.path.contains('/PlayedItems/'),
              ),
              isEmpty,
              reason:
                  'A last-position frame alone is not EOF; normal observations default completed=false',
            );
            f.player.state = f.player.state.copyWith(completed: true);
            f.player.emit('completed', true);
            await f.until(
              t,
              () => server.reports.any(
                (r) => r.url.path.contains('/PlayedItems/'),
              ),
            );
            final paths = server.reports.map((r) => r.url.path).toList();
            final stop = paths.indexWhere((p) => p.endsWith('/Stopped'));
            final mark = paths.indexWhere((p) => p.contains('/PlayedItems/'));
            expect(stop, isNonNegative);
            expect(mark, greaterThan(stop));
            expect(
              server.body(server.reports[stop])['PositionTicks'],
              1200000 * 10000,
            );
          } else if (scenario == 'source handoff') {
            f.player.state = f.player.state.copyWith(
              position: const Duration(minutes: 5),
            );
            f.player.emit('position', f.player.state.position);
            await f.until(t, () => server.reports.isNotEmpty);
            playerControls(t).onShowStremioSources!();
            await f.advance(t, const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final selected = server.sources[1];
            final url = (await f.finish(t, sheet.resolveSource(selected)))!;
            final callback = sheet.onSourceSelected as dynamic;
            final selection = verifier.observe(
              () => f.actions.start('server source switch', () async {
                final value = callback(1, url);
                if (value is Future) await value;
              }),
            );
            await f.finish(t, selection.future);
            expect(
              verifier.timers,
              isEmpty,
              reason:
                  'A direct mid-session carried seek does not opt into landing verification',
            );
            await f.until(
              t,
              () =>
                  f.player.state.playlist.medias.first.uri ==
                  selected.directUrl,
            );
            await f.actions.settle(t);
            await f.player.play();
            await f.advance(t);
            playerControls(t).onPlayPause();
            await f.until(
              t,
              () => server.reports.any(
                (r) =>
                    r.url.path.contains('/Sessions/Playing') &&
                    server.body(r)['MediaSourceId'] == 'version_2160',
              ),
            );
            final oldStop = server.reports.indexWhere(
              (r) =>
                  r.url.path.endsWith('/Stopped') &&
                  server.body(r)['MediaSourceId'] == 'version_1080',
            );
            final freshStart = server.reports.indexWhere(
              (r) =>
                  r.url.path.endsWith('/Playing') &&
                  server.body(r)['MediaSourceId'] == 'version_2160',
            );
            expect(oldStop, isNonNegative);
            expect(freshStart, greaterThan(oldStop));
            expect(
              server.body(server.reports[oldStop])['PositionTicks'],
              300000 * 10000,
            );
          } else {
            server.beforeReport = (_) => gate.future;
            final menu = await display.menu(PlayerMenuSection.speed);
            menu.onSpeedSelected(1.25);
            await f.until(t, () => server.reports.isNotEmpty);
            expect(gate.isCompleted, isFalse);
            await completionIncomingProfile(t, f);
            gate.complete();
            await f.actions.settle(t);
            await server.disposePlayback();
            expect(
              server.reports,
              hasLength(1),
              reason:
                  'A retired capability cannot send a stop to the incoming profile',
            );
          }
          for (final report in server.reports.where(
            (r) => r.url.path.contains('/Sessions/Playing'),
          )) {
            expect(report.method, 'POST');
            expect(report.headers['X-Emby-Token'], 'p14-synthetic-access');
            expect(server.body(report)['ItemId'], 'item1');
            expect(
              server.body(report)['MediaSourceId'],
              scenario == 'source handoff'
                  ? anyOf('version_1080', 'version_2160')
                  : 'version_1080',
            );
            expect(server.body(report)['PlaySessionId'], 'p14-watch');
          }
          if (scenario != 'profile retirement' && scenario != 'quiet dispose') {
            await server.disposePlayback();
          }
        } finally {
          if (!gate.isCompleted) gate.complete();
          server.beforeReport = null;
          await f.close(t);
          await f.advance(t, const Duration(milliseconds: 800));
          await verifier.drain();
          server.restoreFactories();
        }
      },
    );
  }
}
