import 'dart:convert';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'support/tv_episode_driver.dart';

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

PlaylistEntry _e(String name) => PlaylistEntry(url: _url(name), title: name);

Future<void> _next(TvEpisodeDriver d) async {
  final dynamic next = playerControls(d.t).onNext;
  expect(next, isNotNull, reason: 'Next is offered');
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => next()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 200));
}

Future<void> _ended(TvEpisodeDriver d) async {
  d.player.emit('completed', true);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

Future<List<PlaylistEntry>?> _resolve(
  Torrent s, {
  bool Function()? canContinue,
}) async => [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];

/// Simkl lists the show's episodes as [episodes] (season, episode).
http.Response? _simkl(http.Request r, int id, List<(int, int)> episodes) =>
    r.url.path.contains('/tv/episodes/$id')
    ? http.Response(
        jsonEncode([
          for (final (s, e) in episodes)
            {'season': s, 'episode': e, 'title': 'S${s}E$e'},
        ]),
        200,
      )
    : null;

/// Mounts [screen] as a pushed route so its pop result is observable.
Future<Future<Object?>> _mountRoute(
  TvEpisodeDriver d,
  VideoPlayerScreen screen,
) async {
  final t = d.t;
  final f = d.f;
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      navigatorKey: f.navigator,
      theme: ThemeData.dark(),
      home: const Text('host'),
    ),
  );
  late Future<Object?> popped;
  d.observe(() {
    popped = f.navigator.currentState!.push<Object?>(
      MaterialPageRoute(builder: (_) => screen),
    );
  });
  await f.until(t, () => f.controllers.isNotEmpty);
  f.player.deliverReady();
  await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
  for (var i = 0; i < 20; i++) {
    await f.advance(t, const Duration(milliseconds: 100));
  }
  expect(find.byType(mkv.Video), findsOneWidget);
  return popped;
}

void main() {
  testWidgets(
    'P18 catalog series EOF at a season finale hands Quick Play the next season',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      try {
        d.f.network.handler = (r) =>
            _simkl(r, 86420031, [(1, 1), (1, 2), (2, 1)]) ??
            http.Response('{}', 404);
        final popped = await _mountRoute(
          d,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/finale.mp4',
            title: 'Finale file',
            contentTitle: 'Finale Series',
            contentImdbId: 'simkl:86420031',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 2,
          ),
        );
        d.player.emit('completed', true);
        final result = await d.f.finish(t, popped);
        expect(result, {
          'quickPlayNext': true,
          'imdbId': 'simkl:86420031',
          'season': 2,
          'episode': 1,
          'title': 'Finale Series',
          'contentType': 'series',
        });
      } finally {
        TraktTestTransport.instance.recorder = null;
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a custom episode resolver keeps Next in-player and never hands off to Quick Play',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      var resolved = 0;
      try {
        d.f.network.handler = (r) =>
            _simkl(r, 86420032, [(1, 1), (1, 2)]) ?? http.Response('{}', 404);
        final popped = await _mountRoute(
          d,
          VideoPlayerScreen(
            videoUrl: 'https://player.test/custom.mp4',
            title: 'Custom file',
            contentTitle: 'Custom Series',
            contentImdbId: 'simkl:86420032',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              resolveAdjacentEpisode: (s, e, direction) async {
                resolved++;
                return null;
              },
            ),
            resolveSourceToPlaylist: _resolve,
          ),
        );
        var handedOff = false;
        popped.then((_) => handedOff = true);
        await _ended(d);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(resolved, greaterThan(0), reason: 'the resolver owned EOF');
        expect(handedOff, isFalse);
        expect(find.text('host'), findsNothing);
        expect(find.byType(mkv.Video), findsOneWidget);
      } finally {
        TraktTestTransport.instance.recorder = null;
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Next falls back to the cached TVMaze guide when the custom resolver has no guide',
    (t) async {
      final searched = <(int, int)>[];
      final d = TvEpisodeDriver(t);
      await d.initialize();
      await d.f.finish(t, TVMazeService.clearCache());
      d.f.network.handler = (r) {
        if (r.url.host != 'api.tvmaze.com') return http.Response('{}', 404);
        if (r.url.path.endsWith('/episodes')) {
          return http.Response(
            jsonEncode([
              for (final n in [1, 2, 3, 4])
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
            'id': 9180095,
            'name': 'Fallback Show',
            'externals': {'imdb': 'tt9180095'},
            'genres': <String>[],
          }),
          200,
        );
      };
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Fall.S01E03.mkv'),
            title: 'Fall.S01E03.mkv',
            contentImdbId: 'tt9180095',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 3,
            disableAutoResume: true,
            startIndex: 1,
            playlist: [_e('Fall.S01E02.mkv'), _e('Fall.S01E03.mkv')],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 3,
              searchEpisodes: (s, e) async {
                searched.add((s, e));
                return [episodeSource('Fall.S0${s}E0$e')];
              },
              searchPacks: (s, e) async => [],
              resolveAdjacentEpisode: (s, e, direction) async =>
                  throw const EpisodeGuideUnavailable(),
            ),
            resolveSourceToPlaylist: _resolve,
          ),
        );
        await d.f.until(
          t,
          () => playerControls(t).title.contains('Guide 3'),
          reason: 'TVMaze titled the playing episode',
        );
        await _next(d);
        await d.f.until(t, () => searched.isNotEmpty);
        expect(searched.first, (1, 4));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 EOF of a locally tracked movie records it as finished', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: const VideoPlayerScreen(
          videoUrl: 'https://player.test/finished-movie.mp4',
          title: 'Finished movie',
          contentType: 'movie',
          contentImdbId: 'tt9180096',
          disableAutoResume: true,
        ),
      );
      expect(
        await d.f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
        isNot(contains('tt9180096')),
      );
      await _ended(d);
      expect(
        await d.f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
        contains('tt9180096'),
      );
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 a single file without catalog identity looks its movie up by title',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        d.f.network.handler = (r) => http.Response('{"metas":[]}', 200);
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/lookup.mp4',
            title: 'Gap Lookup Movie 2011 1080p.mkv',
            disableAutoResume: true,
          ),
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) =>
                r.url.host == 'v3-cinemeta.strem.io' &&
                r.url.path.contains('/catalog/movie/top/search='),
          ),
          reason: 'the single-file title is looked up',
        );
      } finally {
        await d.close();
      }
    },
  );
}
