import 'dart:async';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  for (final stage in ['policy', 'seek']) {
    testWidgets(
      'Resume P14 newer local restore overlaps old $stage and preserves launch spending and epoch capture',
      (t) async {
        final gate = Completer<void>();
        var firstSeek = false;
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) {
            if (stage == 'seek') {
              p.seekAcknowledgementPosition = Duration.zero;
              p.heldOperation = (n, v) => n == 'seek' && !firstSeek;
              p.beforeOperation = (n, v) async {
                if (n == 'seek' && !firstSeek) {
                  firstSeek = true;
                  await gate.future;
                }
              };
            }
          },
        );
        await t.runAsync(f.initialize);
        final read = CompletionDelivery(
          'maybeRestoreResume',
          (v) => stage == 'policy' && v is TrackingSourcePolicy,
        );
        final verifier = ResumeVerifierDriver(t, f);
        final a = source(
          'P14 overlap.mkv',
          'https://player.test/p14-overlap-a.mp4',
        );
        final b = source(
          'P14 overlap.mkv',
          'https://player.test/p14-overlap-b.mp4',
        );
        final target = stage == 'policy' ? 300000 : 480000;
        try {
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume('pikpak_overlap-b', {
              'positionMs': target,
              'speed': 1.0,
              'aspect': 'contain',
            }),
          );
          await verifier.observe(
            () => read.run(
              () => f.mount(
                t,
                VideoPlayerScreen(
                  videoUrl: a.directUrl!,
                  title: a.name,
                  playlist: [
                    PlaylistEntry(
                      url: a.directUrl!,
                      title: a.name,
                      provider: 'pikpak',
                      pikpakFileId: 'overlap-a',
                    ),
                  ],
                  traktProgressPercent: 20,
                  mdblistProgressPercent: 30,
                  simklProgressPercent: 40,
                  stremioSources: [a, b],
                  stremioCurrentSourceIndex: 0,
                  resolveStremioSource: (s) async => s.directUrl,
                  resolveSourceToPlaylist: (s, {canContinue}) async => [
                    PlaylistEntry(
                      url: s.directUrl!,
                      title: s.name,
                      provider: 'pikpak',
                      pikpakFileId: 'overlap-b',
                    ),
                  ],
                ),
              ),
            ),
          );
          await f.until(
            t,
            () => stage == 'policy' ? read.pending.isNotEmpty : firstSeek,
          );
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
          final url = (await f.finish(t, sheet.resolveSource(b)))!;
          final callback = sheet.onSourceSelected as dynamic;
          final selection = f.actions.start('newer source restore', () async {
            final result = callback(1, url);
            if (result is Future) await result;
          });
          await f.finish(t, selection.future);
          await f.until(
            t,
            () =>
                f.player.calls.where((c) => c.$1 == 'seek').length ==
                (stage == 'seek' ? 2 : 1),
          );
          expect(f.player.state.playlist.medias.first.uri, b.directUrl);
          final before = verifier.timers.length;
          read.release();
          gate.complete();
          if (stage == 'policy') {
            await f.until(
              t,
              () => f.player.calls.where((c) => c.$1 == 'seek').length == 2,
            );
            expect(
              f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
              everyElement(Duration(milliseconds: target)),
              reason:
                  'The local-preferred newer restore spends all three original launch promises before the older call resumes',
            );
            await f.advance(t, const Duration(milliseconds: 800));
            await verifier.drain();
          } else {
            await f.until(t, () => verifier.pending);
            expect(verifier.timers.length, greaterThan(before));
            expect(
              verifier.timers.last.$1,
              const Duration(milliseconds: 200),
              reason:
                  'The old seek reads the current epoch after its await and can attach its verifier to the new source',
            );
            f.player.seekAcknowledgementPosition = null;
            final controls = playerControls(t);
            controls.onSeekBarChanged(0.1);
            controls.onSeekBarChangeEnd();
            await f.advance(t, const Duration(milliseconds: 250));
            await verifier.drain();
          }
        } finally {
          read.release();
          if (!gate.isCompleted) gate.complete();
          await f.close(t);
        }
      },
    );
  }
}
