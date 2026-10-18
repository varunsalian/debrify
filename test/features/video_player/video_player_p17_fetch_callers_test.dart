import 'dart:convert';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['next', 'EOF', 'previous', 'shuffle']) {
    testWidgets('P17 retained $route caller fetches outside the pack', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final fetched = <(int, int)>[];
      final episode = route == 'previous' ? 3 : 1;
      const target = 2;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E0$episode',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: episode,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: episode,
              searchPacks: (s, e) async => [],
              searchEpisodes: (s, e) async {
                fetched.add((s, e));
                return [episodeSource('Show.S01E0$e')];
              },
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: e + direction),
              loadCustomEpisodeInventory: () async => [
                {'season': 1, 'number': 1, 'airdate': '2020-01-01'},
                {'season': 1, 'number': 2, 'airdate': '2020-01-02'},
              ],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        if (route == 'EOF') {
          d.player.emit('completed', true);
          await d.f.until(t, () => d.opens.length == 2);
        } else if (route == 'shuffle') {
          playerControls(t).onRandom();
          await d.f.advance(t, const Duration(milliseconds: 350));
          final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
          d.observe(menu.onShuffleOnce);
          await d.f.until(t, () => d.opens.length == 2);
        } else {
          final dynamic action = route == 'next'
              ? playerControls(t).onNext!
              : playerControls(t).onPrevious!;
          await d.f.finish<dynamic>(t, d.observe<dynamic>(() => action()));
        }
        expect(fetched, [(1, target)]);
        expect(d.opens.last.uri, 'https://player.test/Show.S01E0$target.mp4');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
  testWidgets(
    'P17 retained shuffle builds a synthetic guide and carries TVMaze-discovered IMDb identity',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var fetches = 0;
      EpisodeInfoService.clearCache();
      await t.runAsync(TVMazeService.clearCache);
      d.f.network.handler = (r) async {
        if (r.url.host == 'api.tvmaze.com') {
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/episodes')
                  ? [
                      {
                        'id': 17000191,
                        'season': 1,
                        'number': 1,
                        'name': 'First',
                        'airdate': '2020-01-01',
                      },
                      {
                        'id': 17000192,
                        'season': 1,
                        'number': 2,
                        'name': 'Second',
                        'airdate': '2020-01-02',
                      },
                    ]
                  : r.url.path == '/search/shows'
                  ? [
                      {
                        'score': 1.0,
                        'show': {
                          'id': 1700019,
                          'name': 'Synthetic Show',
                          'externals': {'imdb': 'tt1700019'},
                        },
                      },
                    ]
                  : {
                      'id': 1700019,
                      'name': 'Synthetic Show',
                      'externals': {'imdb': 'tt1700019'},
                    },
            ),
            200,
          );
        }
        return http.Response('{}', 404);
      };
      await d.f.finish(t, TVMazeService.refreshAvailability());
      expect(TVMazeService.currentAvailability, isTrue);
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Synthetic.Show.S01E01.mkv',
            contentTitle: 'Synthetic Show',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchPacks: (s, e) async => [],
              searchEpisodes: (s, e) async {
                fetches++;
                return [episodeSource('Synthetic.Show.S01E02')];
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        playerControls(t).onRandom();
        await d.f.advance(t, const Duration(milliseconds: 350));
        d.observe(
          t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).onShuffleOnce,
        );
        await d.f.until(t, () => d.opens.length == 2);
        expect(fetches, 1);
        final browser = await d.browser();
        expect(browser.seriesPlaylist.imdbId, 'tt1700019');
        expect(browser.imdbKnownAtLaunch, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
