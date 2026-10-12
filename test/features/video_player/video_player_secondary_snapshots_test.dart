import 'dart:async';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

Future<void> saveSecondarySnapshot(
  String tracker,
  String id,
  Map<String, double> percents,
) => tracker == 'simkl'
    ? TrackerEpisodeProgressStorage.saveEpisodeSimklProgress(
        imdbId: id,
        percents: percents,
      )
    : TrackerEpisodeProgressStorage.saveEpisodeMdblistProgress(
        imdbId: id,
        percents: percents,
      );

void main() {
  TraktTestTransport.install();
  for (final tracker in ['simkl', 'mdblist']) {
    final simkl = tracker == 'simkl';
    for (final race in ['episode', 'show', 'A-B-A', 'profile', 'dispose']) {
      testWidgets(
        'Secondary $tracker suspended snapshot $race pins late coordinates and original identity guard',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = SecondaryTrackerDriver(t, f);
          await d.initialize();
          final reads = TraktSnapshotReads('p6-$tracker-$race', skip: 1);
          final errors = <Object>[];
          final remote = Completer<http.Response>();
          try {
            await t.runAsync(() async {
              await reads.seed({
                'tt5100000': {'1_1': 30, '1_2': 40},
                'tt5200000': {'1_1': 60, '1_2': 65},
              }, store: 'episode_${tracker}_progress_v1');
              await TrackingSourceStorage.setWatchProgressSource(
                simkl ? WatchProgressSource.simkl : WatchProgressSource.mdblist,
              );
            });
            await d.mount(
              secondaryScreen(
                simkl: false,
                mdblist: false,
                playlist: traktPlaylist,
                simklPercent: simkl ? 50 : null,
                mdblistPercent: simkl ? null : 50,
              ),
            );
            if (race == 'profile') {
              f.network.handler = (r) =>
                  r.method == 'GET' &&
                      [
                        'api.trakt.tv',
                        'api.simkl.com',
                        'api.mdblist.com',
                      ].contains(r.url.host)
                  ? remote.future
                  : secondaryReply(r);
            }
            final b = (await runZonedGuarded(
              () => traktBrowser(t, f),
              (e, s) => errors.add(e),
            ))!;
            if (race == 'profile') {
              await f.until(
                t,
                () => f.network.requests.any(
                  (r) =>
                      r.method == 'GET' &&
                      [
                        'api.trakt.tv',
                        'api.simkl.com',
                        'api.mdblist.com',
                      ].contains(r.url.host),
                ),
              );
            }
            final selection = reads.run(() => b.onEpisodeSelected(1, 2));
            await f.until(t, () => reads.pending.isNotEmpty);
            expect(reads.deliveries, 1);
            if (race == 'profile') {
              await incomingProfile(t, f);
              remote.complete(http.Response('{}', 404));
            }
            if (race == 'dispose') await d.retired();
            if (['episode', 'show', 'A-B-A'].contains(race)) {
              if (race != 'episode') b.seriesPlaylist.imdbId = 'tt5200000';
              await f.finish(t, b.onEpisodeSelected(1, 1));
              expect(
                d.seeks.last,
                Duration(seconds: race == 'episode' ? 360 : 720),
              );
              if (race == 'A-B-A') {
                await t.runAsync(
                  () => saveSecondarySnapshot(tracker, 'tt5100000', {
                    '1_1': 70,
                    '1_2': 75,
                  }),
                );
                b.seriesPlaylist.imdbId = 'tt5100000';
                await f.finish(t, b.onEpisodeSelected(1, 2));
                expect(d.seeks.last, const Duration(seconds: 900));
              }
            }
            final before = d.seeks.length;
            reads.release();
            await f.finish(t, selection);
            await d.drain();
            if (race == 'show') {
              expect(d.seeks, hasLength(before));
            } else {
              expect(d.seeks.skip(before), [
                Duration(seconds: race == 'episode' ? 360 : 480),
              ]);
            }
            expect(d.forTracker('simkl'), isEmpty);
            expect(d.forTracker('mdblist'), isEmpty);
            if (!remote.isCompleted) remote.complete(http.Response('{}', 404));
            expect(
              errors,
              race == 'profile'
                  ? [
                      isA<StateError>().having(
                        (e) => e.message,
                        'message',
                        'Profile session changed before async completion',
                      ),
                    ]
                  : isEmpty,
            );
          } finally {
            reads.release();
            if (!remote.isCompleted) remote.complete(http.Response('{}', 404));
            await d.close();
          }
        },
      );
    }

    testWidgets(
      'Secondary $tracker launch promise is spent once and episode snapshots stay cached per bound show',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 30,
              '1_2': 25,
            });
            await TrackingSourceStorage.setWatchProgressSource(
              simkl ? WatchProgressSource.simkl : WatchProgressSource.mdblist,
            );
          });
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
              simklPercent: simkl ? 50 : null,
              mdblistPercent: simkl ? null : 50,
            ),
          );
          expect(d.seeks, [const Duration(seconds: 600)]);
          final b = await traktBrowser(t, f);
          await f.finish(t, b.onEpisodeSelected(1, 2));
          expect(d.seeks.last, const Duration(seconds: 300));
          await t.runAsync(
            () => saveSecondarySnapshot(tracker, 'tt5100000', {
              '1_1': 70,
              '1_2': 75,
            }),
          );
          await f.finish(t, b.onEpisodeSelected(1, 1));
          expect(d.seeks.last, const Duration(seconds: 360));
          expect(
            d.seeks.where((p) => p == const Duration(seconds: 600)),
            hasLength(1),
          );
          expect(d.forTracker(tracker), isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'Secondary $tracker single-file snapshot resolves effective coordinates before resuming',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await t.runAsync(() async {
            await saveSecondarySnapshot(tracker, 'tt5100000', {'2_3': 40});
            await TrackingSourceStorage.setWatchProgressSource(
              simkl ? WatchProgressSource.simkl : WatchProgressSource.mdblist,
            );
          });
          await d.mount(secondaryScreen(simkl: false, mdblist: false));
          expect(d.seeks, [const Duration(seconds: 480)]);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final oldTracker in ['simkl', 'mdblist']) {
    final nextTracker = oldTracker == 'simkl' ? 'mdblist' : 'simkl';
    testWidgets(
      'Secondary concurrent $oldTracker and $nextTracker readers reset the shared identity and sibling cache',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = TraktSnapshotReads('concurrent-$oldTracker', skip: 1);
        try {
          await t.runAsync(() async {
            await reads.seed({
              'tt5100000': {'1_1': 30, '1_2': 40},
            }, store: 'episode_${oldTracker}_progress_v1');
            await saveSecondarySnapshot(nextTracker, 'tt5100000', {
              '1_1': 35,
              '1_2': 45,
            });
            await saveSecondarySnapshot(nextTracker, 'tt5200000', {
              '1_1': 60,
              '1_2': 65,
            });
          });
          await d.mount(
            secondaryScreen(
              simkl: false,
              mdblist: false,
              playlist: traktPlaylist,
              simklPercent: oldTracker == 'simkl' ? 50 : null,
              mdblistPercent: oldTracker == 'mdblist' ? 50 : null,
            ),
          );
          final b = await traktBrowser(t, f);
          await t.runAsync(
            () => TrackingSourceStorage.setWatchProgressSource(
              oldTracker == 'simkl'
                  ? WatchProgressSource.simkl
                  : WatchProgressSource.mdblist,
            ),
          );
          final selection = reads.run(() => b.onEpisodeSelected(1, 2));
          await f.until(t, () => reads.pending.isNotEmpty);
          b.seriesPlaylist.imdbId = 'tt5200000';
          await t.runAsync(
            () => TrackingSourceStorage.setWatchProgressSource(
              nextTracker == 'simkl'
                  ? WatchProgressSource.simkl
                  : WatchProgressSource.mdblist,
            ),
          );
          await f.finish(t, b.onEpisodeSelected(1, 1));
          expect(d.seeks.last, const Duration(seconds: 720));
          final before = d.seeks.length;
          reads.release();
          await f.finish(t, selection);
          await d.drain();
          expect(d.seeks, hasLength(before));
          expect(d.seeks.last, const Duration(seconds: 720));
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
