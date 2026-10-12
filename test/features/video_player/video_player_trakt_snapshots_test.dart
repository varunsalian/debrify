import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

const traktPlaylist = [
  PlaylistEntry(
    url: 'https://player.test/trakt-one.mp4',
    title: 'Trakt.Show.S01E01.mkv',
  ),
  PlaylistEntry(
    url: 'https://player.test/trakt-two.mp4',
    title: 'Trakt.Show.S01E02.mkv',
  ),
];

Future<SeriesBrowser> traktBrowser(
  WidgetTester t,
  VideoPlayerEnvironment f,
) async {
  playerControls(t).onShowPlaylist();
  await f.until(t, () => find.byType(SeriesBrowser).evaluate().isNotEmpty);
  return t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
}

Future<void> pickTraktEpisode(
  WidgetTester t,
  TraktPlayerDriver d,
  SeriesBrowser b,
  int episode,
) async {
  unawaited(b.onEpisodeSelected(1, episode));
  await d.drain();
  // The sheet closes itself at selection; the original callback remains a
  // valid caller for an overlapping action while its previous load awaits.
}

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Trakt playlist switch stops outgoing scrobble and timer before a held incoming open',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final open = Completer<void>();
      try {
        await d.mount(traktScreen(playlist: traktPlaylist, percent: 50));
        final b = await traktBrowser(t, f);
        f.player.delays['open'] = open;
        unawaited(b.onEpisodeSelected(1, 2));
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.drain();
        expect(d.actions, ['start', 'stop']);
        d.expectRequest(1, 'stop', 50, season: 1, episode: 1);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        open.complete();
        await d.drain();
      } finally {
        if (!open.isCompleted) open.complete();
        await d.close();
      }
    },
  );
  for (final missing in [true]) {
    testWidgets(
      'Trakt snapshot ${missing ? 'missing episode' : 'empty playlist'} rejects a changed public guide model during storage',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final reads = TraktSnapshotReads('boundary-$missing', skip: 1);
        try {
          await t.runAsync(() async {
            await reads.seed({
              'tt5100000': {'1_1': 30, '1_2': 40},
            });
            await TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.trakt,
            );
          });
          await d.mount(
            traktScreen(enabled: false, playlist: traktPlaylist, percent: 50),
          );
          final b = await traktBrowser(t, f);
          reads.run(() => unawaited(b.onEpisodeSelected(1, 2)));
          await f.until(t, () => reads.pending.isNotEmpty);
          final before = d.seeks.length;
          b.seriesPlaylist.allEpisodes.removeWhere((e) => e.originalIndex == 1);
          reads.release();
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
    'Trakt launch promise is spent once and later playlist items use their own snapshot',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      try {
        await t.runAsync(
          () => TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5100000',
            percents: {'1_1': 30, '1_2': 25},
          ),
        );
        await t.runAsync(
          () => TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.trakt,
          ),
        );
        await d.mount(traktScreen(playlist: traktPlaylist, percent: 50));
        expect(d.seeks, contains(const Duration(seconds: 600)));
        expect(d.seeks, isNot(contains(const Duration(seconds: 360))));
        final b = await traktBrowser(t, f);
        await pickTraktEpisode(t, d, b, 2);
        await f.until(t, () => d.seeks.contains(const Duration(seconds: 300)));
        expect(d.seeks.last, const Duration(seconds: 300));
        await t.runAsync(
          () => TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: 'tt5100000',
            percents: {'1_1': 70, '1_2': 75},
          ),
        );
        await pickTraktEpisode(t, d, b, 1);
        await f.until(t, () => d.seeks.last == const Duration(seconds: 360));
        expect(
          d.seeks.where((p) => p == const Duration(seconds: 600)),
          hasLength(1),
        );
        expect(d.requests.map((r) => r.url.path), contains('/scrobble/stop'));
        final stops = d.requests
            .where((r) => r.url.path == '/scrobble/stop')
            .toList();
        expect(stops, isNotEmpty);
        d.expectRequest(
          d.requests.indexOf(stops.first),
          'stop',
          50,
          season: 1,
          episode: 1,
        );
      } finally {
        await d.close();
      }
    },
  );

  for (final race in ['episode', 'show', 'A-B-A', 'profile', 'dispose']) {
    testWidgets(
      'Trakt suspended snapshot $race reads current coordinates and preserves original identity guard',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        final reads = TraktSnapshotReads('original-$race', skip: 1);
        final errors = <Object>[];
        final remote = Completer<http.Response>();
        try {
          await t.runAsync(
            () => reads.seed({
              'tt5100000': {'1_1': 30, '1_2': 40},
              'tt5200000': {'1_1': 60, '1_2': 65},
            }),
          );
          await t.runAsync(
            () => TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.trakt,
            ),
          );
          await d.mount(
            traktScreen(enabled: false, playlist: traktPlaylist, percent: 50),
          );
          if (race == 'profile') {
            f.network.handler = (request) =>
                request.url.host == 'api.trakt.tv' && request.method == 'GET'
                ? remote.future
                : traktReply(request);
          }
          final b = (await runZonedGuarded(
            () => traktBrowser(t, f),
            (e, s) => errors.add(e),
          ))!;
          if (race == 'profile') {
            await f.until(
              t,
              () => f.network.requests.any(
                (r) => r.url.host == 'api.trakt.tv' && r.method == 'GET',
              ),
            );
          }
          reads.run(() => unawaited(b.onEpisodeSelected(1, 2)));
          await f.until(
            t,
            () => reads.pending.isNotEmpty,
            reason: 'Hold the State resume reader after the sheet preflight',
          );
          expect(reads.deliveries, 1);
          final before = f.player.calls.length;
          if (race == 'profile') {
            await incomingProfile(t, f);
            remote.complete(http.Response('{}', 404));
          }
          if (race == 'dispose') {
            await t.pumpWidget(const SizedBox.shrink());
            await d.drain();
          }
          if (['episode', 'show', 'A-B-A'].contains(race)) {
            if (race != 'episode') b.seriesPlaylist.imdbId = 'tt5200000';
            await pickTraktEpisode(t, d, b, 1);
            await f.until(
              t,
              () =>
                  d.seeks.last ==
                  Duration(seconds: race == 'episode' ? 360 : 720),
            );
            if (race == 'A-B-A') {
              await t.runAsync(
                () => TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
                  imdbId: 'tt5100000',
                  percents: {'1_1': 70, '1_2': 75},
                ),
              );
              b.seriesPlaylist.imdbId = 'tt5100000';
              await pickTraktEpisode(t, d, b, 2);
              await f.until(
                t,
                () => d.seeks.last == const Duration(seconds: 900),
              );
            }
          }
          final preRelease = d.seeks.length;
          reads.release();
          await d.drain();
          if (race == 'episode') {
            expect(d.seeks.skip(preRelease), [const Duration(seconds: 360)]);
          } else if (race == 'show') {
            expect(d.seeks.skip(preRelease), isEmpty);
            expect(d.seeks.last, const Duration(seconds: 720));
          } else if (race == 'A-B-A') {
            // String identity accepts old A over the newer 75% A snapshot.
            expect(d.seeks.skip(preRelease), [const Duration(seconds: 480)]);
          } else {
            // This reader has no mounted/profile guard; the ready route's
            // playlist caller resumes from the outgoing snapshot after retire.
            expect(d.seeks.skip(preRelease), [const Duration(seconds: 480)]);
          }
          expect(f.player.calls.length, greaterThan(before));
          expect(errors, isEmpty);
        } finally {
          if (!remote.isCompleted) remote.complete(http.Response('{}', 404));
          reads.release();
          await d.close();
        }
      },
    );
  }
}
