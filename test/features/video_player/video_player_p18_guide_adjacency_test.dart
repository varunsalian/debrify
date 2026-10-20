import 'dart:convert';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

PlaylistEntry _e(String name) => PlaylistEntry(url: _url(name), title: name);

/// TVMaze knows the show and the season-1 guide [numbers].
http.Response? _tvmaze(http.Request r, String imdb, List<int> numbers) {
  if (r.url.host != 'api.tvmaze.com') return null;
  if (r.url.path.endsWith('/episodes')) {
    return http.Response(
      jsonEncode([
        for (final n in numbers)
          {
            'id': n,
            'season': 1,
            'number': n,
            'name': 'Guide $n',
            'airdate': '2020-01-0$n',
          },
      ]),
      200,
    );
  }
  return http.Response(
    jsonEncode({
      'id': int.parse(imdb.substring(2)),
      'name': 'Adjacent Show $imdb',
      'externals': {'imdb': imdb},
      'genres': <String>[],
    }),
    200,
  );
}

Future<List<PlaylistEntry>?> _resolve(
  Torrent s, {
  bool Function()? canContinue,
}) async => [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];

/// A pack that starts at E02 of show [name] whose TVMaze guide is [guide].
/// Each case uses its own show: series metadata is cached by show title.
Future<TvEpisodeDriver> _start(
  WidgetTester t,
  String name,
  String imdb,
  List<int> guide,
  List<(int, int)> searched,
) async {
  final d = TvEpisodeDriver(t);
  await d.initialize();
  await d.f.finish(t, TVMazeService.clearCache());
  d.f.network.handler = (r) =>
      _tvmaze(r, imdb, guide) ?? http.Response('{}', 404);
  await d.mount(
    screen: VideoPlayerScreen(
      videoUrl: _url('$name.S01E02.mkv'),
      title: '$name.S01E02.mkv',
      contentImdbId: imdb,
      contentType: 'series',
      contentSeason: 1,
      contentEpisode: 2,
      disableAutoResume: true,
      startIndex: 0,
      playlist: [_e('$name.S01E02.mkv'), _e('$name.S01E03.mkv')],
      seriesSourceFetcher: SeriesSourceFetcher(
        season: 1,
        episode: 2,
        searchEpisodes: (s, e) async {
          searched.add((s, e));
          return [episodeSource('$name.S0${s}E0$e')];
        },
        searchPacks: (s, e) async => [],
      ),
      resolveSourceToPlaylist: _resolve,
    ),
  );
  // The guide arrives with the TVMaze episode preload.
  await d.f.until(
    t,
    () => playerControls(t).title.contains('Guide 2'),
    reason: 'TVMaze titled the playing episode',
  );
  await d.f.advance(t, const Duration(seconds: 1));
  return d;
}

void main() {
  testWidgets(
    'P18 a pack start offers Previous when the TVMaze guide has an earlier episode and fetches it',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(t, 'Early', 'tt9180077', [1, 2, 3], searched);
      try {
        expect(playerControls(t).hasPrevious, isTrue);
        final dynamic previous = playerControls(t).onPrevious!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => previous()) as Future<dynamic>,
        );
        await d.f.until(t, () => searched.isNotEmpty);
        expect(searched.first, (1, 1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a pack start offers no Previous when the TVMaze guide starts at this episode',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(t, 'Opener', 'tt9180078', [2, 3], searched);
      try {
        expect(playerControls(t).hasPrevious, isFalse);
        expect(searched, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
