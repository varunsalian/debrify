import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/ledger_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

/// Ledger's episode snapshot as a resume candidate: consulted whenever Ledger
/// is the connected Progress source (scrobbling to it or not), and never by
/// any other launch.
void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  TraktTestTransport.install();
  const cases = <(String, WatchProgressSource, bool, int)>[
    (
      'Ledger Progress source resumes without scrobbling to Ledger',
      WatchProgressSource.ledger,
      true,
      480000,
    ),
    (
      'Smart without a Ledger launch never consults Ledger',
      WatchProgressSource.smart,
      true,
      0,
    ),
    (
      'a synced Ledger choice without a session here is Smart',
      WatchProgressSource.ledger,
      false,
      0,
    ),
  ];
  for (final (label, source, connected, expected) in cases) {
    testWidgets('Resume Ledger source $label', (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      const id = 'tt1412002';
      try {
        if (connected) {
          // Sealing uses real async crypto: run it outside fake time.
          await t.runAsync(
            () => LedgerStorage.setSession(
              accessToken: 'access',
              refreshToken: 'refresh',
              expiryMs: DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
            ),
          );
        }
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeLedgerProgress(
            imdbId: id,
            percents: {'2_3': 40},
          ),
        );
        await f.finish(t, TrackingSourceStorage.setWatchProgressSource(source));
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/ledger-source.mp4',
            title: 'Ledger source',
            contentImdbId: id,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
          ),
        );
        await f.actions.settle(t);
        final seeks = f.player.calls
            .where((c) => c.$1 == 'seek')
            .map((c) => (c.$2 as Duration).inMilliseconds);
        expect(seeks, expected == 0 ? isEmpty : [expected]);
      } finally {
        await d.close();
      }
    });
  }
}
