import 'dart:async';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/local_completion_driver.dart';
import 'support/secondary_tracker_driver.dart' show secondaryReply;
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_trakt_snapshots_test.dart' show traktBrowser;

void main() {
  TraktTestTransport.install();
  for (final startIndex in [0, 1]) {
    testWidgets(
      'Completion nameless source replacement observes transient old index $startIndex before URL resolution and completion reset',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        final resolution = Completer<http.Response>();
        final candidate = source(
          'Incoming.Show.S01E03.mkv',
          'https://player.test/completion-incoming.mp4',
        );
        final fetcher = SeriesSourceFetcher(
          searchPacks: (season, episode) async => [],
          searchEpisodes: (season, episode) async => [candidate],
          season: 1,
          episode: 1,
        );
        try {
          await f.finish(
            t,
            TorboxStorage.saveTorboxApiKey('vplayer-synthetic-torbox'),
          );
          await d.mount(
            VideoPlayerScreen(
              videoUrl: 'https://player.test/nameless-1.mp4',
              title: '',
              playlist: const [
                PlaylistEntry(
                  url: 'https://player.test/nameless-1.mp4',
                  title: '',
                ),
                PlaylistEntry(
                  url: 'https://player.test/nameless-2.mp4',
                  title: '',
                ),
              ],
              startIndex: startIndex,
              disableAutoResume: true,
              viewMode: PlaylistViewMode.series,
              contentType: 'series',
              contentImdbId: 'tt7100000',
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
          expect(browser.seriesPlaylist.seriesTitle, isNull);
          expect(browser.currentEpisodeIndex, startIndex);
          await d.percent(85);
          await d.drain();
          f.network.handler = (request) => request.url.host.contains('torbox')
              ? resolution.future
              : secondaryReply(request);
          final selection = browser.onEpisodeSelected(1, 3);
          await f.until(
            t,
            () => f.network.requests.any(
              (request) => request.url.host.contains('torbox'),
            ),
          );
          expect(
            f.player.calls.where((call) => call.$1 == 'open'),
            hasLength(1),
          );
          await d.percent(85);
          await d.drain();
          expect(
            await d.finishedEpisode(
              title: 'Incoming Show',
              season: 1,
              episode: 3,
            ),
            startIndex == 0 ? isNotNull : isNull,
            reason: 'The original checks the old index before the later reset',
          );
          resolution.complete(http.Response('{}', 404));
          await f.finish(t, selection);
          await d.drain();
        } finally {
          if (!resolution.isCompleted) {
            resolution.complete(http.Response('{}', 404));
          }
          await d.close();
        }
      },
    );
  }
}
