import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:flutter/material.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_trakt_snapshots_test.dart';

void main() {
  TraktTestTransport.install();
  for (final mode in ['smart', 'local', 'custom', 'trakt']) {
    final local = mode == 'local';
    testWidgets(
      'Secondary guide mask $mode is reloaded after held local resume and late episode metadata',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = TraktSnapshotReads(
          'local-state-$mode',
          multiple: true,
          when: () => f.player.calls.where((c) => c.$1 == 'open').length >= 2,
        );
        try {
          await t.runAsync(() async {
            await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
              imdbId: 'tt5100000',
              percents: {'1_1': 40, if (mode == 'trakt') '1_2': 25},
            );
            await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
              imdbId: const CustomSeriesIdentity('fixture', 'guide').id,
              percents: {'1_1': 40, if (mode == 'trakt') '1_2': 25},
            );
            await TrackerEpisodeProgressStorage.saveEpisodeSimklProgress(
              imdbId: 'tt5100000',
              percents: {'1_2': 25, if (mode == 'trakt') '1_1': 95},
            );
          });
          if (mode == 'trakt') {
            await t.runAsync(
              () => TrackingSourceStorage.setWatchProgressSource(
                WatchProgressSource.trakt,
              ),
            );
          }
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
              simklPercent: mode == 'trakt' ? null : 50,
              traktPercent: mode == 'trakt' ? 50 : null,
            ),
          );
          expect(d.seeks, [const Duration(seconds: 600)]);
          expect(d.heartbeats, isEmpty);
          final b = await traktBrowser(t, f);
          await t.runAsync(() async {
            await SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: b.seriesPlaylist.seriesTitle!,
              imdbId: 'tt5100000',
              season: 1,
              episode: 2,
              positionMs: 1140000,
              durationMs: 1200000,
            );
            final map = await PlaybackStateStore.getPlaybackStateMap();
            map['__vp_snapshot_case__'] = reads.marker;
            await PlaybackStateStore.savePlaybackStateMap(map);
          });
          await t.runAsync(
            () => TrackerEpisodeProgressStorage.saveEpisodeMdblistProgress(
              imdbId: 'tt5100000',
              percents: {'1_1': mode == 'trakt' ? 95 : 45},
            ),
          );
          final before = d.seeks.length;
          final selection = reads.run(() => b.onEpisodeSelected(1, 2));
          await f.until(t, () => reads.pending.isNotEmpty);
          await d.drain();
          expect(d.seeks, hasLength(before));
          b.seriesPlaylist.allEpisodes
              .singleWhere((e) => e.originalIndex == 1)
              .seriesInfo = const SeriesInfo(
            isSeries: true,
            season: 1,
            episode: 1,
          );
          if (local) {
            await t.runAsync(
              () => TrackingSourceStorage.setWatchProgressSource(
                WatchProgressSource.local,
              ),
            );
          }
          if (mode == 'custom') {
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: f.navigator,
                theme: ThemeData.dark(),
                home: secondaryScreen(
                  simkl: false,
                  mdblist: false,
                  id: const CustomSeriesIdentity('fixture', 'guide').id,
                  playlist: traktPlaylist,
                ),
              ),
            );
          }
          reads.release();
          await f.finish(t, selection);
          await d.drain();
          expect(
            d.seeks.skip(before),
            ['smart', 'trakt'].contains(mode)
                ? [const Duration(seconds: 300)]
                : isEmpty,
          );
          expect(d.requests, isEmpty);
        } finally {
          reads.release();
          await d.close();
        }
      },
    );
  }
}
