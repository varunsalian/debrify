import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 epoch changes during held confirmation reject the old frame before logging a transient landing',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final confirm = CompletionDelivery('resumeSeekLanded', (v) => v == null);
      final verifier = ResumeVerifierDriver(t, f)..captureLogs();
      const a = PlaylistEntry(
        url: 'https://player.test/p14-confirm-a.mp4',
        title: 'P14.Confirm.Show.S01E01.mkv',
      );
      const b = PlaylistEntry(
        url: 'https://player.test/p14-confirm-b.mp4',
        title: 'P14.Confirm.Show.S01E02.mkv',
      );
      try {
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(
            'P14.Confirm.Show.S01E01'.hashCode.toString(),
            {'positionMs': 300000, 'speed': 1.0, 'aspect': 'contain'},
          ),
        );
        await confirm.run(
          () => verifier.observe(
            () => f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: a.url,
                title: 'P14 confirm show',
                playlist: [a, b],
                contentType: 'series',
              ),
            ),
          ),
        );
        await f.until(t, () => confirm.pending.isNotEmpty);
        expect(verifier.pending, isTrue);
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        await f.finish(
          t,
          SeriesProgressStorage.saveSeriesPlaybackState(
            seriesTitle: browser.seriesPlaylist.seriesTitle!,
            imdbId: browser.seriesPlaylist.imdbId,
            season: 1,
            episode: 2,
            positionMs: 300000,
            durationMs: 1200000,
            speed: 1.0,
            aspect: 'contain',
          ),
        );
        f.player.seekAcknowledgementPosition = Duration.zero;
        final selected = f.actions.start(
          'reset while confirmation result is held',
          () => browser.onEpisodeSelected(1, 2),
        );
        await f.finish(t, selected.future);
        expect(f.player.state.playlist.medias.first.uri, b.url);
        expect(f.player.state.position, Duration.zero);
        expect(confirm.pending, hasLength(1));
        confirm.release();
        await verifier.drain();
        expect(
          verifier.logs.where((v) => v.contains('landing was transient')),
          isEmpty,
          reason:
              'The epoch guard runs before treating a replacement player frame as an old masked seek',
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(2));
      } finally {
        confirm.release();
        await t.pumpWidget(const SizedBox.shrink());
        await f.advance(t, const Duration(milliseconds: 800));
        await verifier.drain();
        verifier.restoreLogs();
        await f.close(t);
      }
    },
  );
}
