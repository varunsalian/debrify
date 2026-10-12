import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Simkl playlist selection stops its outgoing episode and heartbeat before a held incoming open',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final opening = Completer<void>();
      Future<void>? selection;
      try {
        await d.mount(secondaryScreen(mdblist: false, playlist: traktPlaylist));
        await d.position(300000);
        final browser = await traktBrowser(t, f);
        f.player.delays['open'] = opening;
        selection = browser.onEpisodeSelected(1, 2);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.drain();
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'stop', 25, season: 1, episode: 1);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        opening.complete();
        f.player.delays.remove('open');
        await f.finish(t, selection!);
      } finally {
        if (!opening.isCompleted) opening.complete();
        f.player.delays.remove('open');
        if (selection != null) await f.finish(t, selection);
        await d.close();
      }
    },
  );
  testWidgets(
    'MDBList failed ordinary incoming open retains the incoming tracker target as the original does',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final failure = StateError('synthetic incoming episode open failure');
      try {
        await d.mount(secondaryScreen(simkl: false, playlist: traktPlaylist));
        await d.waitCheckpoint('mdblist', 1);
        final browser = await traktBrowser(t, f);
        await d.position(300000);
        f.player.failures['open'] = failure;
        await expectLater(
          f.finish(t, browser.onEpisodeSelected(1, 2)),
          throwsA(same(failure)),
        );
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
        expect(f.player.state.playlist.medias.first.uri, traktPlaylist[0].url);
        f.player.emit('duration', const Duration(minutes: 20));
        await d.position(600000);
        await d.playing(true);
        await d.tick(const Duration(minutes: 2));
        final requests = d.forTracker('mdblist');
        expect(requests, isNotEmpty);
        d.expectCheckpoint(
          'mdblist',
          requests.length - 1,
          'pause',
          50,
          season: 1,
          episode: 2,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'MDBList failed source preparation checkpoints the unplayed target then restores the outgoing session',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final initial = source(
        'Fixture.Show.S01E01.mkv',
        'https://player.test/source-rollback-one.mp4',
      );
      final unavailable = source(
        'Fixture.Show.S01E02.mkv',
        'https://player.test/source-rollback-two.mp4',
      );
      final fetcher = SeriesSourceFetcher(
        searchPacks: (season, episode) async => [],
        searchEpisodes: (season, episode) async => [unavailable],
        season: 1,
        episode: 1,
      );
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: initial.directUrl!,
            title: initial.name,
            playlist: [
              PlaylistEntry(url: initial.directUrl!, title: initial.name),
            ],
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            mdblistScrobble: true,
            stremioSources: [initial],
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (candidate, {canContinue}) async => [
              PlaylistEntry(
                url: candidate.name == unavailable.name
                    ? ''
                    : initial.directUrl!,
                title: candidate.name,
              ),
            ],
          ),
        );
        await d.waitCheckpoint('mdblist', 1);
        final browser = await traktBrowser(t, f);
        await d.position(300000);
        await f.finish(t, browser.onEpisodeSelected(1, 2));
        await d.drain();
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
        expect(
          d.forTracker('mdblist').map((request) => jsonDecode(request.body)),
          contains(
            equals({
              'show': {
                'ids': {'imdb': 'tt5100000'},
                'season': 1,
                'episode': 2,
              },
              'progress': 1.0,
            }),
          ),
          reason:
              'Preserve the original checkpoint before failed preparation rolls back',
        );
        f.player.emit('duration', const Duration(minutes: 20));
        await d.position(600000);
        await d.playing(true);
        await d.tick(const Duration(minutes: 2));
        final requests = d.forTracker('mdblist');
        d.expectCheckpoint(
          'mdblist',
          requests.length - 1,
          'pause',
          50,
          season: 1,
          episode: 1,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'MDBList playlist switch captures an unlanded outgoing resume before clearing its guard',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (player) {
          player.failures['seek'] = StateError('synthetic unlanded resume');
        },
      );
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(
          secondaryScreen(
            simkl: false,
            playlist: traktPlaylist,
            mdblistPercent: 50,
          ),
        );
        await d.waitCheckpoint('mdblist', 1);
        d.expectCheckpoint('mdblist', 0, 'pause', 0.01, season: 1, episode: 1);
        expect(f.player.state.position, const Duration(milliseconds: 80));
        final browser = await traktBrowser(t, f);
        await f.finish(t, browser.onEpisodeSelected(1, 2));
        await d.waitCheckpoint('mdblist', 3);
        d.expectCheckpoint('mdblist', 1, 'pause', 50, season: 1, episode: 1);
        d.expectCheckpoint('mdblist', 2, 'pause', 1, season: 1, episode: 2);
      } finally {
        await d.close();
      }
    },
  );
}
