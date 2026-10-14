import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  testWidgets(
    'subtitle metadata arriving after restoration retries discovery through the retained caller',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('metadata');
      await d.order(language: 'eng');
      await d.f.finish(t, TVMazeService.clearCache());
      final search = Completer<http.Response>();
      const show = {
        'id': 110,
        'name': 'Trakt Show',
        'externals': {'imdb': 'tt1100003'},
        'genres': <String>[],
      };
      d.f.network.handler = (r) {
        if (r.url.host == 'api.tvmaze.com') {
          if (r.url.path == '/search/shows') {
            return search.future;
          }
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/episodes')
                  ? [
                      for (var n = 1; n <= 2; n++)
                        {
                          'id': n,
                          'season': 1,
                          'number': n,
                          'name': 'Episode $n',
                        },
                    ]
                  : show,
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.startsWith('/subtitles/series/')) {
          return d.slots('metadata');
        }
        return d.f.network.replies[r.url.toString()] ??
            http.Response('{}', 404);
      };
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/trakt-one.mp4',
            title: 'Trakt.Show.S01E01.mkv',
            playlist: traktPlaylist,
          ),
          publishTracks: false,
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any((r) => r.url.path == '/search/shows'),
        );
        expect(d.player.state.track.subtitle.uri, isFalse);
        expect(
          d.f.network.requests.where(
            (r) => r.url.path.startsWith('/subtitles/series/'),
          ),
          isEmpty,
        );
        expect(d.logs.any((s) => s.contains('restore done')), isTrue);
        search.complete(
          http.Response(
            jsonEncode([
              {'score': 1.0, 'show': show},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        expect(
          d.f.network.requests
              .where((r) => r.url.path.startsWith('/subtitles/series/'))
              .map((r) => r.url.path),
          ['/subtitles/series/tt1100003:1:1.json'],
        );
        expect(d.requests(d.caption('metadata')), 1);
        expect(
          d.logs,
          contains(
            'VideoPlayer: Series IMDB resolved after initial subtitle fetch, retrying addon subtitles (IMDB: tt1100003)',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!search.isCompleted) {
          search.complete(http.Response('[]', 200));
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle same identity metadata retries use the published warm cache without another request',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('metadata');
      await d.order(language: 'eng');
      await d.f.finish(t, TVMazeService.clearCache());
      final search = Completer<http.Response>();
      const show = {
        'id': 110,
        'name': 'Trakt Show',
        'externals': {'imdb': 'tt1100003'},
        'genres': <String>[],
      };
      d.f.network.handler = (r) {
        if (r.url.host == 'api.tvmaze.com') {
          if (r.url.path == '/lookup/shows') {
            return search.future;
          }
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/episodes')
                  ? [
                      for (var n = 1; n <= 2; n++)
                        {
                          'id': n,
                          'season': 1,
                          'number': n,
                          'name': 'Episode $n',
                        },
                    ]
                  : show,
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.startsWith('/subtitles/series/')) {
          return d.slots('metadata');
        }
        return d.f.network.replies[r.url.toString()] ??
            http.Response('{}', 404);
      };
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/trakt-one.mp4',
            title: 'Trakt.Show.S01E01.mkv',
            contentImdbId: 'tt1100003',
            playlist: traktPlaylist,
          ),
          publishTracks: false,
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any((r) => r.url.path == '/lookup/shows'),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        expect(
          d.f.network.requests.where(
            (r) => r.url.path == '/subtitles/series/tt1100003:1:1.json',
          ),
          hasLength(1),
        );
        expect(d.logs.any((s) => s.contains('restore done')), isTrue);
        search.complete(
          http.Response(
            jsonEncode(show),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await d.f.until(
          t,
          () => d.logs.contains('VideoPlayer: Using 1 cached addon subtitles'),
        );
        await d.f.actions.settle(t);
        expect(
          d.f.network.requests
              .where((r) => r.url.path.startsWith('/subtitles/series/'))
              .map((r) => r.url.path),
          ['/subtitles/series/tt1100003:1:1.json'],
        );
        expect(d.requests(d.caption('metadata')), 1);
        expect(
          d.logs,
          contains(
            'VideoPlayer: Series IMDB resolved after initial subtitle fetch, retrying addon subtitles (IMDB: tt1100003)',
          ),
        );
        final panel = await d.menu();
        expect(panel.cachedAddonSlots, hasLength(1));
        expect(panel.cachedAddonSlots!.single.subtitles.single.id, 'metadata');
        expect(d.errors, isEmpty);
      } finally {
        if (!search.isCompleted) {
          search.complete(http.Response('[]', 200));
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle changed metadata identity replaces the warm cache before the public menu reads it',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('metadata');
      await d.order(language: 'eng');
      await d.f.finish(t, TVMazeService.clearCache());
      final search = Completer<http.Response>();
      const show = {
        'id': 110,
        'name': 'Trakt Show',
        'externals': {'imdb': 'tt1100004'},
        'genres': <String>[],
      };
      d.f.network.handler = (r) {
        if (r.url.host == 'api.tvmaze.com') {
          if (r.url.path == '/lookup/shows') {
            return search.future;
          }
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/episodes')
                  ? [
                      for (var n = 1; n <= 2; n++)
                        {
                          'id': n,
                          'season': 1,
                          'number': n,
                          'name': 'Episode $n',
                        },
                    ]
                  : show,
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.startsWith('/subtitles/series/')) {
          return d.slots('metadata');
        }
        return d.f.network.replies[r.url.toString()] ??
            http.Response('{}', 404);
      };
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/trakt-one.mp4',
            title: 'Trakt.Show.S01E01.mkv',
            contentImdbId: 'tt1100003',
            playlist: traktPlaylist,
          ),
          publishTracks: false,
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any((r) => r.url.path == '/lookup/shows'),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        expect(
          d.f.network.requests.where(
            (r) => r.url.path == '/subtitles/series/tt1100003:1:1.json',
          ),
          hasLength(1),
        );
        expect(d.logs.any((s) => s.contains('restore done')), isTrue);
        // The browser exposes this shared legacy model. Model enrichment while
        // its pending metadata callback is held must be read live by the retry.
        final browser = await traktBrowser(t, d.f);
        expect(browser.seriesPlaylist.imdbId, 'tt1100003');
        browser.seriesPlaylist.imdbId = 'tt1100004';
        d.f.navigator.currentState!.pop();
        await d.f.advance(t);
        search.complete(
          http.Response(
            jsonEncode(show),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path == '/subtitles/series/tt1100004:1:1.json',
          ),
        );
        await d.f.actions.settle(t);
        expect(
          d.f.network.requests
              .where((r) => r.url.path.startsWith('/subtitles/series/'))
              .map((r) => r.url.path),
          [
            '/subtitles/series/tt1100003:1:1.json',
            '/subtitles/series/tt1100004:1:1.json',
          ],
        );
        expect(d.requests(d.caption('metadata')), 1);
        expect(
          d.logs,
          contains(
            'VideoPlayer: Series IMDB resolved after initial subtitle fetch, retrying addon subtitles (IMDB: tt1100004)',
          ),
        );
        final panel = await d.menu();
        expect(panel.cachedAddonSlots, hasLength(1));
        expect(panel.cachedAddonSlots!.single.subtitles.single.id, 'metadata');
        expect(d.errors, isEmpty);
      } finally {
        if (!search.isCompleted) {
          search.complete(http.Response('[]', 200));
        }
        await removeFixture(d);
      }
    },
  );
}
