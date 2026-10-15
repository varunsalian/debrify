import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';

/// Delay delivery of one real polling timer. DateTime and the production
/// deadline are untouched: a busy event loop may deliver a timer late.
class DeadlinePollDelivery {
  bool armed = true;
  void Function()? pending;
  final clock = Stopwatch();
  T observe<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final selected =
            armed &&
            duration == const Duration(milliseconds: 200) &&
            StackTrace.current.toString().contains('resumeSeekLanded');
        if (!selected) return parent.createTimer(zone, duration, callback);
        armed = false;
        clock.start();
        return parent.createTimer(zone, duration, () {
          pending = () => zone.run(callback);
        });
      },
    ),
  );

  void release() {
    final callback = pending;
    pending = null;
    callback?.call();
  }
}

void main() {
  testWidgets(
    'Resume P14 deadline expiring during a held poll cannot retry a replacement episode with the same target',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
      );
      await t.runAsync(f.initialize);
      final poll = DeadlinePollDelivery();
      final verifier = ResumeVerifierDriver(t, f)..captureLogs();
      const a = PlaylistEntry(
        url: 'https://player.test/p14-deadline-a.mp4',
        title: 'P14.Deadline.Show.S01E01.mkv',
      );
      const b = PlaylistEntry(
        url: 'https://player.test/p14-deadline-b.mp4',
        title: 'P14.Deadline.Show.S01E02.mkv',
      );
      try {
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(
            'P14.Deadline.Show.S01E01'.hashCode.toString(),
            {'positionMs': 300000, 'speed': 1.0, 'aspect': 'contain'},
          ),
        );
        await poll.observe(
          () => verifier.observe(
            () => f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: a.url,
                title: 'P14 deadline show',
                playlist: [a, b],
                contentType: 'series',
              ),
            ),
          ),
        );
        await f.until(t, () => poll.pending != null);
        expect(verifier.pending, isTrue);
        expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
        // Cross the actual 1.5 second deadline while the final in-flight
        // polling interval is suspended. This is bounded, not fake time.
        await t.runAsync(() async {
          final remaining =
              const Duration(milliseconds: 1600) - poll.clock.elapsed;
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        });
        expect(
          poll.clock.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 1500)),
        );
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
        final selection = f.actions.start(
          'episode reset while expired polling interval is held',
          () => browser.onEpisodeSelected(1, 2),
        );
        await f.finish(t, selection.future);
        expect(f.player.state.playlist.medias.first.uri, b.url);
        expect(f.player.state.position, Duration.zero);
        expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(2));
        expect(verifier.pending, isTrue);
        expect(poll.clock.elapsed, lessThan(const Duration(seconds: 10)));
        poll.release();
        await verifier.drain();
        expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(2));
        expect(
          verifier.logs.where((v) => v.contains('re-issuing')),
          isEmpty,
          reason:
              'Only the post-wait epoch guard rejects an expired old poll when the new guard has the same target',
        );
      } finally {
        poll.release();
        await t.pumpWidget(const SizedBox.shrink());
        await f.advance(t, const Duration(milliseconds: 800));
        await verifier.drain();
        verifier.restoreLogs();
        await f.close(t);
      }
    },
  );
}
