import 'dart:convert';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/tv_episode_driver.dart';

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

PlaylistEntry _e(String name, {Map<String, String>? headers}) =>
    PlaylistEntry(url: _url(name), title: name, httpHeaders: headers);

Future<void> _press(TvEpisodeDriver d, dynamic callback) async {
  expect(callback, isNotNull);
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => callback()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 200));
}

Future<void> _next(TvEpisodeDriver d) => _press(d, playerControls(d.t).onNext);
Future<void> _previous(TvEpisodeDriver d) =>
    _press(d, playerControls(d.t).onPrevious);

Future<void> _ended(TvEpisodeDriver d) async {
  d.player.emit('completed', true);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

void _playAt(TvEpisodeDriver d, Duration position) {
  d.player.state = d.player.state.copyWith(position: position);
  d.player.emit('position', position);
}

Future<void> _shuffleOnce(TvEpisodeDriver d) async {
  playerControls(d.t).onRandom();
  await d.f.advance(d.t, const Duration(milliseconds: 350));
  final menu = d.t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
  d.observe(menu.onShuffleOnce);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

/// A seek that restores the five-minute bookmark, not a start-at-zero.
bool _resumed(TvEpisodeDriver d, int from) =>
    d.seeks.skip(from).any((s) => s >= const Duration(minutes: 4));

Future<List<PlaylistEntry>?> _resolve(
  Torrent s, {
  bool Function()? canContinue,
}) async => [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];

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
      'name': 'Gap Show $imdb',
      'externals': {'imdb': imdb},
      'genres': <String>[],
    }),
    200,
  );
}

Future<TvEpisodeDriver> _start(
  WidgetTester t,
  VideoPlayerScreen screen, {
  http.Response? Function(http.Request)? network,
}) async {
  final d = TvEpisodeDriver(t);
  await d.initialize();
  await d.f.finish(t, TVMazeService.clearCache());
  d.f.network.handler = (r) => network?.call(r) ?? http.Response('{}', 404);
  await d.mount(screen: screen);
  return d;
}

void main() {
  testWidgets('P18 manual Next checkpoints the outgoing item position', (
    t,
  ) async {
    final d = await _start(
      t,
      VideoPlayerScreen(
        videoUrl: _url('Gap save one'),
        title: 'Gap save',
        viewMode: PlaylistViewMode.raw,
        disableAutoResume: true,
        startIndex: 0,
        playlist: [_e('Gap save one'), _e('Gap save two')],
      ),
    );
    try {
      _playAt(d, const Duration(minutes: 5));
      await d.f.advance(t);
      await _next(d);
      expect(d.opens.last.uri, _url('Gap save two'));
      final saved = await d.f.finish(
        t,
        VideoResumeStorage.getVideoResume('Gap save one'.hashCode.toString()),
      );
      expect(saved?['positionMs'], 300000);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 manual Next does not restore the next item bookmark inside the manual window',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Gap manual one'),
          title: 'Gap manual',
          viewMode: PlaylistViewMode.raw,
          playlist: [_e('Gap manual one'), _e('Gap manual two')],
        ),
      );
      try {
        // Auto-resume launches start at the first item.
        await _next(d);
        expect(d.opens.last.uri, _url('Gap manual two'));
        await d.f.advance(t, const Duration(seconds: 31));
        // Previous checkpoints "two" at five minutes.
        _playAt(d, const Duration(minutes: 5));
        await d.f.advance(t);
        await _previous(d);
        expect(d.opens.last.uri, _url('Gap manual one'));
        final bookmark = await d.f.finish(
          t,
          VideoResumeStorage.getVideoResume(
            'Gap manual two'.hashCode.toString(),
          ),
        );
        expect(bookmark?['positionMs'], 300000);
        // The manual window opened by Previous expires.
        await d.f.advance(t, const Duration(seconds: 31));
        final from = d.seeks.length;
        await _next(d);
        expect(d.opens.last.uri, _url('Gap manual two'));
        await d.f.advance(t, const Duration(seconds: 3));
        expect(
          _resumed(d, from),
          isFalse,
          reason: 'a manual pick starts from the beginning',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 manual Next after a sleep stop at end of item clears the stop and plays',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Gap sleep one'),
          title: 'Gap sleep',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [_e('Gap sleep one'), _e('Gap sleep two')],
        ),
      );
      try {
        await pickSleep(
          t,
          d.f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        final before = d.opens.length;
        await _ended(d);
        await waitSleepToast(t, d.f, 'Sleep timer — stopping here');
        expect(d.opens.length, before, reason: 'the sleep stop holds EOF');
        await _next(d);
        expect(d.opens.length, before + 1);
        expect(d.opens.last.uri, _url('Gap sleep two'));
        expect(d.openAutoplay.last, isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 Next at the end of a pack fetches the following TVMaze guide episode in-player',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Late.S01E03.mkv'),
          title: 'Late.S01E03.mkv',
          contentImdbId: 'tt9180091',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 3,
          disableAutoResume: true,
          startIndex: 1,
          playlist: [_e('Late.S01E02.mkv'), _e('Late.S01E03.mkv')],
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 1,
            episode: 3,
            searchEpisodes: (s, e) async {
              searched.add((s, e));
              return [episodeSource('Late.S0${s}E0$e')];
            },
            searchPacks: (s, e) async => [],
          ),
          resolveSourceToPlaylist: _resolve,
        ),
        network: (r) => _tvmaze(r, 'tt9180091', [1, 2, 3, 4]),
      );
      try {
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

  testWidgets(
    'P18 shuffle once from the last episode of a two-episode pack plays the first',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Duo.S01E02.mkv'),
          title: 'Duo.S01E02.mkv',
          contentType: 'series',
          disableAutoResume: true,
          startIndex: 1,
          playlist: [_e('Duo.S01E01.mkv'), _e('Duo.S01E02.mkv')],
        ),
      );
      try {
        final before = d.opens.length;
        await _shuffleOnce(d);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('Duo.S01E01.mkv'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 shuffle once without any episode guide falls back to the pack',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Bare.S01E01.mkv'),
          title: 'Bare.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [_e('Bare.S01E01.mkv'), _e('Bare.S01E02.mkv')],
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 1,
            episode: 1,
            searchEpisodes: (s, e) async => [],
            searchPacks: (s, e) async => [],
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        final before = d.opens.length;
        await _shuffleOnce(d);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('Bare.S01E02.mkv'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 continuous show shuffle at EOF starts the picked pack episode from zero',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Spin.S01E01.mkv'),
          title: 'Spin.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          startIndex: 0,
          initialContinuousShuffle: true,
          playlist: [_e('Spin.S01E01.mkv'), _e('Spin.S01E02.mkv')],
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 1,
            episode: 1,
            loadCustomEpisodeInventory: () async => [
              for (final n in [1, 2])
                {'season': 1, 'number': n, 'airdate': '2020-01-0$n'},
            ],
            searchEpisodes: (s, e) async => [],
            searchPacks: (s, e) async => [],
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        // Next checkpoints E01 at five minutes and shuffles to E02.
        _playAt(d, const Duration(minutes: 5));
        await d.f.advance(t);
        final before = d.opens.length;
        await _next(d);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('Spin.S01E02.mkv'));
        await d.f.advance(t, const Duration(seconds: 31));
        final from = d.seeks.length;
        final opened = d.opens.length;
        await _ended(d);
        await d.f.until(t, () => d.opens.length > opened);
        expect(d.opens.last.uri, _url('Spin.S01E01.mkv'));
        await d.f.advance(t, const Duration(seconds: 3));
        expect(
          _resumed(d, from),
          isFalse,
          reason: 'show shuffle starts episodes from zero',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a two-episode pack without TVMaze data titles the episode, not the catalog title',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Twin.S01E01.mkv'),
          title: 'Twin.S01E01.mkv',
          contentTitle: 'Clean Twin',
          contentType: 'series',
          disableAutoResume: true,
          startIndex: 0,
          playlist: [_e('Twin.S01E01.mkv'), _e('Twin.S01E02.mkv')],
        ),
      );
      try {
        await d.f.advance(t, const Duration(seconds: 1));
        expect(playerControls(t).title, 'Episode 1');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 Next opens the next entry with its own HTTP headers', (
    t,
  ) async {
    final d = await _start(
      t,
      VideoPlayerScreen(
        videoUrl: _url('Gap head one'),
        title: 'Gap head',
        viewMode: PlaylistViewMode.raw,
        disableAutoResume: true,
        startIndex: 0,
        playlist: [
          _e('Gap head one'),
          _e('Gap head two', headers: {'Referer': 'https://ref.test/'}),
        ],
      ),
    );
    try {
      await _next(d);
      expect(d.opens.last.uri, _url('Gap head two'));
      expect(d.opens.last.httpHeaders, {'Referer': 'https://ref.test/'});
    } finally {
      await d.close();
    }
  });
}
