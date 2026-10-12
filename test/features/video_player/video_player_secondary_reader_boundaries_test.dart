import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/secondary_policy_reads.dart';
import 'support/trakt_policy_reads.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_secondary_snapshots_test.dart' show saveSecondarySnapshot;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  TraktTestTransport.install();
  for (final tracker in ['simkl', 'mdblist']) {
    final source = tracker == 'simkl'
        ? WatchProgressSource.simkl
        : WatchProgressSource.mdblist;
    for (final missing in ['identity', 'coordinates']) {
      testWidgets(
        'Secondary $tracker missing $missing snapshot boundary cannot resume from malformed null keys',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = SecondaryTrackerDriver(t, f);
          await d.initialize();
          final oldPrint = debugPrint;
          final logs = <String>[];
          debugPrint = (String? message, {int? wrapWidth}) {
            if (message != null) logs.add(message);
          };
          try {
            await t.runAsync(() async {
              await saveSecondarySnapshot(tracker, 'tt5100000', {
                'null_null': 50,
                '2_3': 40,
              });
              await TrackingSourceStorage.setWatchProgressSource(source);
            });
            await d.mount(
              secondaryScreen(
                simkl: false,
                mdblist: false,
                id: missing == 'identity' ? null : 'tt5100000',
                season: missing == 'coordinates' ? null : 2,
                episode: missing == 'coordinates' ? null : 3,
              ),
            );
            expect(d.seeks, isEmpty);
            expect(d.forTracker(tracker), isEmpty);
            expect(
              logs.where(
                (line) => line.startsWith('VideoPlayer: initial open failed:'),
              ),
              isEmpty,
              reason:
                  'Missing metadata originally rejects resume without an initialization error',
            );
          } finally {
            debugPrint = oldPrint;
            await d.close();
          }
        },
      );
    }

    testWidgets(
      'Secondary $tracker inner snapshot policy rejects remote resume after the outer policy has been captured',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = TraktPolicyReads(
          () => f.player.calls.where((c) => c.$1 == 'open').length >= 2,
        );
        try {
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 30,
              '1_2': 40,
            });
            await TrackingSourceStorage.setWatchProgressSource(source);
          });
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
              simklPercent: tracker == 'simkl' ? 50 : null,
              mdblistPercent: tracker == 'mdblist' ? 50 : null,
            ),
          );
          final browser = await traktBrowser(t, f);
          final before = d.seeks.length;
          final selection = reads.run(() => browser.onEpisodeSelected(1, 2));
          await f.until(t, () => reads.pending.isNotEmpty);
          await t.runAsync(
            () => TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.local,
            ),
          );
          reads.release();
          await f.finish(t, selection);
          await d.drain();
          expect(d.seeks, hasLength(before));
          // A normal rejected reader must not warm the cache. A later policy
          // selection observes this new snapshot rather than the rejected one.
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 70,
              '1_2': 75,
            });
            await TrackingSourceStorage.setWatchProgressSource(source);
          });
          await f.finish(t, browser.onEpisodeSelected(1, 1));
          expect(d.seeks.last, const Duration(seconds: 840));
        } finally {
          reads.release();
          await d.close();
        }
      },
    );

    testWidgets(
      'Secondary $tracker masked guide read still warms its snapshot for a later selected-provider resume',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 30,
              '1_2': 40,
            });
            await TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.local,
            );
          });
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
            ),
          );
          final browser = await traktBrowser(t, f);
          await t.runAsync(
            () => SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: browser.seriesPlaylist.seriesTitle!,
              imdbId: 'tt5100000',
              season: 1,
              episode: 2,
              positionMs: 1140000,
              durationMs: 1200000,
            ),
          );
          await f.finish(t, browser.onEpisodeSelected(1, 2));
          expect(d.seeks, isEmpty);
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 75,
              '1_2': 70,
            });
            await TrackingSourceStorage.setWatchProgressSource(source);
          });
          await f.finish(t, browser.onEpisodeSelected(1, 1));
          expect(d.seeks, [const Duration(seconds: 360)]);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'Secondary $tracker snapshot custom identity arriving after outer policy capture rejects provider-owned resume',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = MdblistPolicyReads(
          awaitName: 'maybeRestoreResume',
          when: () => f.player.calls.where((c) => c.$1 == 'open').length >= 2,
        );
        final custom = const CustomSeriesIdentity('fixture', 'p6-reader').id;
        try {
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 30,
              '1_2': 40,
            });
            await saveSecondarySnapshot(tracker, custom, {'1_2': 45});
            await TrackingSourceStorage.setWatchProgressSource(source);
          });
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
              simklPercent: tracker == 'simkl' ? 50 : null,
              mdblistPercent: tracker == 'mdblist' ? 50 : null,
            ),
          );
          final browser = await traktBrowser(t, f);
          final before = d.seeks.length;
          final selection = reads.run(() => browser.onEpisodeSelected(1, 2));
          await f.until(t, () => reads.pending.isNotEmpty);
          f.player.emit('duration', Duration.zero);
          await d.drain();
          reads.release();
          await d.drain();
          // The original outer policy has now been consumed and is waiting
          // for usable duration. The reader's own policy must use this identity.
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              theme: ThemeData.dark(),
              home: secondaryScreen(
                simkl: false,
                mdblist: false,
                id: custom,
                playlist: traktPlaylist,
              ),
            ),
          );
          f.player.emit('duration', const Duration(minutes: 20));
          await f.finish(t, selection);
          await d.drain();
          expect(d.seeks, hasLength(before));
        } finally {
          reads.release();
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Secondary simkl missing public guide row during snapshot storage rejects the outgoing resume',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final reads = TraktSnapshotReads('p6-missing-row', skip: 1);
      try {
        await t.runAsync(() async {
          await reads.seed({
            'tt5100000': {'1_1': 30, '1_2': 40},
          }, store: 'episode_simkl_progress_v1');
          await TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.simkl,
          );
        });
        await d.mount(
          secondaryScreen(
            simkl: false,
            mdblist: false,
            playlist: traktPlaylist,
            simklPercent: 50,
          ),
        );
        final browser = await traktBrowser(t, f);
        final selection = reads.run(() => browser.onEpisodeSelected(1, 2));
        await f.until(t, () => reads.pending.isNotEmpty);
        final before = d.seeks.length;
        browser.seriesPlaylist.allEpisodes.removeWhere(
          (episode) => episode.originalIndex == 1,
        );
        Object? selectionError;
        final completed = selection.then<void>(
          (_) {},
          onError: (Object error) {
            selectionError = error;
          },
        );
        reads.release();
        await f.finish(t, completed);
        expect(
          selectionError,
          isNull,
          reason: 'The original missing-row caller completes normally',
        );
        await d.drain();
        expect(d.seeks, hasLength(before));
      } finally {
        reads.release();
        await d.close();
      }
    },
  );
}
