import 'dart:async';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/trakt_player_driver.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_policy_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_trakt_snapshots_test.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Trakt missing coordinates cannot resume from malformed null snapshot keys',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await t.runAsync(
          () => TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5100000',
            percents: {'null_null': 50},
          ),
        );
        await d.mount(traktScreen(season: null, episode: null));
        expect(d.seeks, isEmpty);
        expect(d.requests, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'Trakt snapshot inner policy read rejects remote resume after outer policy has been captured',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final reads = TraktPolicyReads(
        () => f.player.calls.where((c) => c.$1 == 'open').length >= 2,
      );
      try {
        await t.runAsync(
          () => TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5100000',
            percents: {'1_1': 30, '1_2': 40},
          ),
        );
        await d.mount(
          traktScreen(enabled: false, playlist: traktPlaylist, percent: 50),
        );
        final b = await traktBrowser(t, f);
        final before = d.seeks.length;
        reads.run(() => unawaited(b.onEpisodeSelected(1, 2)));
        await f.until(t, () => reads.pending.isNotEmpty);
        await t.runAsync(
          () => TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.local,
          ),
        );
        reads.release();
        await d.drain();
        expect(d.seeks, hasLength(before));
        expect(d.requests, isEmpty);
      } finally {
        reads.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'Trakt single-file snapshot uses effective episode coordinates and caches the first read',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await t.runAsync(() async {
          await TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.trakt,
          );
          await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5100000',
            percents: {'2_3': 40},
          );
        });
        await d.mount(traktScreen());
        expect(d.seeks, [const Duration(seconds: 480)]);
        d.expectRequest(0, 'start', 40);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Trakt concurrent Simkl read changes shared identity and clears the outgoing Trakt cache',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final reads = TraktSnapshotReads('simkl-overlap', skip: 1);
      try {
        await t.runAsync(() async {
          await TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.trakt,
          );
          await SimklStorage.setSimklAccessToken('vplayer-synthetic-simkl');
          await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5100000',
            percents: {'1_1': 30, '1_2': 40},
          );
          await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5200000',
            percents: {'1_1': 60, '1_2': 65},
          );
          await reads.seed({
            'tt5200000': {'1_1': 50, '1_2': 55},
          }, store: 'episode_simkl_progress_v1');
        });
        await d.mount(traktScreen(enabled: false, playlist: traktPlaylist));
        expect(d.seeks, [const Duration(seconds: 360)]);
        final b = await traktBrowser(t, f);
        b.seriesPlaylist.imdbId = 'tt5200000';
        await t.runAsync(
          () => TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.simkl,
          ),
        );
        reads.run(() => unawaited(b.onEpisodeSelected(1, 2)));
        await f.until(t, () => reads.pending.isNotEmpty);
        await t.runAsync(
          () => TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.trakt,
          ),
        );
        await pickTraktEpisode(t, d, b, 1);
        await f.until(t, () => d.seeks.last == const Duration(seconds: 720));
        reads.release();
        await d.drain();
        expect(d.seeks.last, const Duration(seconds: 600));
        await pickTraktEpisode(t, d, b, 2);
        await f.until(t, () => d.seeks.last == const Duration(seconds: 780));
        expect(d.requests, isEmpty);
      } finally {
        reads.release();
        await d.close();
      }
    },
  );
}
