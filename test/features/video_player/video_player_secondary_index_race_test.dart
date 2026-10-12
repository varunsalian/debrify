import 'dart:async';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_snapshot_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Secondary simkl snapshot rejects the transient old index while a shorter source playlist awaits URL resolution',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final snapshot = TraktSnapshotReads('p6-index-window', skip: 1);
      final resolution = Completer<http.Response>();
      final missing = source(
        'Fixture.Show.S01E03.mkv',
        'https://player.test/index-three.mp4',
      );
      final fetcher = SeriesSourceFetcher(
        searchPacks: (season, episode) async => [],
        searchEpisodes: (season, episode) async => [missing],
        season: 1,
        episode: 1,
      );
      try {
        await t.runAsync(() async {
          await snapshot.seed({
            'tt5100000': {'1_1': 30, '1_2': 40},
          }, store: 'episode_simkl_progress_v1');
          await TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.simkl,
          );
          await TorboxStorage.saveTorboxApiKey('vplayer-synthetic-torbox');
        });
        await d.mount(
          VideoPlayerScreen(
            videoUrl: traktPlaylist.first.url,
            title: traktPlaylist.first.title,
            playlist: traktPlaylist,
            contentImdbId: 'tt5100000',
            contentType: 'series',
            simklProgressPercent: 50,
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (candidate, {canContinue}) async => [
              PlaylistEntry(
                url: '',
                title: candidate.name,
                provider: 'torbox',
                torboxTorrentId: 123,
                torboxFileId: 456,
              ),
            ],
          ),
        );
        final browser = await traktBrowser(t, f);
        final older = snapshot.run(() => browser.onEpisodeSelected(1, 2));
        await f.until(t, () => snapshot.pending.isNotEmpty);
        f.network.handler = (request) => request.url.host.contains('torbox')
            ? resolution.future
            : secondaryReply(request);
        final newer = browser.onEpisodeSelected(1, 3);
        await f.until(
          t,
          () => f.network.requests.any(
            (request) => request.url.host.contains('torbox'),
          ),
        );
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
        final before = d.seeks.length;
        Object? selectionError;
        final completed = older.then<void>(
          (_) {},
          onError: (Object error) {
            selectionError = error;
          },
        );
        snapshot.release();
        await f.finish(t, completed);
        expect(
          selectionError,
          isNull,
          reason: 'The original guarded reader completes normally',
        );
        await d.drain();
        expect(d.seeks, hasLength(before));
        resolution.complete(http.Response('{}', 404));
        await f.finish(t, newer);
        await d.drain();
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
      } finally {
        snapshot.release();
        if (!resolution.isCompleted) {
          resolution.complete(http.Response('{}', 404));
        }
        await d.close();
      }
    },
  );
}
