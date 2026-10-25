import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_secondary_snapshots_test.dart' show saveSecondarySnapshot;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;
import 'support/physical_resume_store.dart';

void main() {
  TraktTestTransport.install();
  for (final companion in ['simkl', 'mdblist']) {
    testWidgets(
      'Secondary $companion guide completion stays masked during an overlapping episode change and Trakt rewatch',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = TraktSnapshotReads(
          'p6-companion-$companion',
          multiple: true,
          when: () => f.player.calls.where((c) => c.$1 == 'open').length >= 2,
        );
        try {
          await t.runAsync(() async {
            await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
              imdbId: 'tt5100000',
              percents: {'1_1': 40, '1_2': 25},
            );
            await saveSecondarySnapshot(companion, 'tt5100000', {'1_1': 95});
          });
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
              traktPercent: 50,
              simklPercent: 0,
              mdblistPercent: 0,
            ),
          );
          expect(d.seeks, [const Duration(seconds: 600)]);
          final browser = await traktBrowser(t, f);
          await t.runAsync(() async {
            await SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: browser.seriesPlaylist.seriesTitle!,
              imdbId: 'tt5100000',
              season: 1,
              episode: 2,
              positionMs: 1140000,
              durationMs: 1200000,
            );
            final map = await PhysicalResumeStore.getPlaybackStateMap();
            map['__vp_snapshot_case__'] = reads.marker;
            await PhysicalResumeStore.savePlaybackStateMap(map);
          });
          final older = reads.run(() => browser.onEpisodeSelected(1, 2));
          await f.until(t, () => reads.pending.isNotEmpty);
          // Keep the older real storage completion held, while a new public
          // selection finishes and changes the episode used by both readers.
          reads.armed = false;
          await t.runAsync(
            () => TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.trakt,
            ),
          );
          await f.finish(t, browser.onEpisodeSelected(1, 1));
          expect(d.seeks.last, const Duration(seconds: 480));
          final before = d.seeks.length;
          reads.release();
          await f.finish(t, older);
          await d.drain();
          // Preserve the original late resume. The non-selected provider's
          // completion cannot block the captured Trakt partial rewatch.
          expect(d.seeks.skip(before), [const Duration(seconds: 300)]);
          expect(d.forTracker('simkl'), isEmpty);
          expect(d.forTracker('mdblist'), isEmpty);
        } finally {
          reads.release();
          await d.close();
        }
      },
    );
  }
}
