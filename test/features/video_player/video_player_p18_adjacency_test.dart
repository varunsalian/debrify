import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

PlaylistEntry _e(String name, {int? size}) => PlaylistEntry(
  url: 'https://player.test/${Uri.encodeComponent(name)}.mp4',
  title: name,
  sizeBytes: size,
);

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

Future<void> _press(TvEpisodeDriver d, dynamic callback) async {
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => callback()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 200));
}

Future<void> _next(TvEpisodeDriver d) => _press(d, playerControls(d.t).onNext!);
Future<void> _previous(TvEpisodeDriver d) =>
    _press(d, playerControls(d.t).onPrevious!);

SeriesSourceFetcher _fetcher({
  required int season,
  required int episode,
  required List<(int, int)> searched,
  Future<({int season, int episode})?> Function(int, int, int)? adjacent,
}) => SeriesSourceFetcher(
  season: season,
  episode: episode,
  searchEpisodes: (s, e) async {
    searched.add((s, e));
    return [episodeSource('Show.S0${s}E0$e')];
  },
  searchPacks: (s, e) async => [],
  resolveAdjacentEpisode: adjacent,
);

Future<List<PlaylistEntry>> _resolve(dynamic s, {dynamic canContinue}) async =>
    [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];

void main() {
  for (final mode in [PlaylistViewMode.raw, PlaylistViewMode.sorted]) {
    testWidgets(
      'P18 ${mode.name} view navigates sequentially and stops at both edges',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: _url('b'),
              title: 'Files',
              viewMode: mode,
              disableAutoResume: true,
              startIndex: 1,
              playlist: [_e('a'), _e('b'), _e('c')],
            ),
          );
          expect(playerControls(t).hasPrevious, isTrue);
          expect(playerControls(t).hasNext, isTrue);
          await _next(d);
          expect(d.opens.last.uri, _url('c'));
          expect(playerControls(t).hasNext, isFalse);
          expect(playerControls(t).onNext, isNull);
          await _previous(d);
          expect(d.opens.last.uri, _url('b'));
          await _previous(d);
          expect(d.opens.last.uri, _url('a'));
          expect(playerControls(t).hasPrevious, isFalse);
          expect(playerControls(t).onPrevious, isNull);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P18 collection mode walks the main group by year, excluding small extras',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Movie B 2010'),
            title: 'Collection',
            contentType: 'movie',
            playlist: [
              _e('Movie B 2010', size: 1000),
              _e('Movie A 2005', size: 900),
              _e('Extras 2001', size: 100),
              // Exactly 40% of the largest still belongs to the group.
              _e('Movie C 2012', size: 400),
            ],
          ),
        );
        // No prior state: the first main-group item (oldest year) opens.
        expect(d.opens.last.uri, _url('Movie A 2005'));
        expect(playerControls(t).hasPrevious, isFalse);
        await _next(d);
        expect(d.opens.last.uri, _url('Movie B 2010'));
        await _next(d);
        expect(d.opens.last.uri, _url('Movie C 2012'));
        expect(playerControls(t).hasNext, isFalse);
        await _previous(d);
        expect(d.opens.last.uri, _url('Movie B 2010'));
        expect(
          d.opens.where((m) => m.uri == _url('Extras 2001')),
          isEmpty,
          reason: 'items under 40% of the largest size are outside the group',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 collection item outside the main group jumps to the group head both ways',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        final playlist = [
          _e('Movie B 2010', size: 1000),
          _e('Movie A 2005', size: 900),
          _e('Extras 2001', size: 100),
        ];
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Extras 2001'),
            title: 'Collection',
            contentType: 'movie',
            disableAutoResume: true,
            startIndex: 2,
            playlist: playlist,
          ),
        );
        expect(d.opens.last.uri, _url('Extras 2001'));
        expect(playerControls(t).hasPrevious, isTrue);
        expect(playerControls(t).hasNext, isTrue);
        await _previous(d);
        expect(d.opens.last.uri, _url('Movie A 2005'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 collection Next from outside the main group also lands on the group head',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Extras 2001'),
            title: 'Collection',
            contentType: 'movie',
            disableAutoResume: true,
            startIndex: 2,
            playlist: [
              _e('Movie B 2010', size: 1000),
              _e('Movie A 2005', size: 900),
              _e('Extras 2001', size: 100),
            ],
          ),
        );
        await _next(d);
        expect(d.opens.last.uri, _url('Movie A 2005'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 series pack follows sorted episode order rather than playlist order',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S01E01.mkv'),
            title: 'Show pack',
            playlist: [
              _e('Show.S01E02.mkv'),
              _e('Show.S01E01.mkv'),
              _e('Show.S01E03.mkv'),
            ],
          ),
        );
        expect(d.opens.last.uri, _url('Show.S01E01.mkv'));
        expect(playerControls(t).hasPrevious, isFalse);
        await _next(d);
        expect(d.opens.last.uri, _url('Show.S01E02.mkv'));
        await _next(d);
        expect(d.opens.last.uri, _url('Show.S01E03.mkv'));
        expect(playerControls(t).hasNext, isFalse);
        await _previous(d);
        expect(d.opens.last.uri, _url('Show.S01E02.mkv'));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 catalog series with an IMDb id and season keeps Next available past the pack',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S01E01.mkv'),
            title: 'Show pack',
            contentType: 'series',
            contentImdbId: 'tt1800001',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [_e('Show.S01E01.mkv')],
          ),
        );
        expect(playerControls(t).hasNext, isTrue);
        expect(playerControls(t).hasPrevious, isFalse);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 single series entry without catalog identity has no Next', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: _url('Show.S01E01.mkv'),
          title: 'Show pack',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          playlist: [_e('Show.S01E01.mkv')],
        ),
      );
      expect(playerControls(t).hasNext, isFalse);
      expect(playerControls(t).onNext, isNull);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 fetchable series beyond the pack resolves Next and Previous through the resolver',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final searched = <(int, int)>[];
      final asked = <(int, int, int)>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S02E05.mkv'),
            title: 'Show.S02E05.mkv',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 5,
            seriesSourceFetcher: _fetcher(
              season: 2,
              episode: 5,
              searched: searched,
              adjacent: (s, e, dir) async {
                asked.add((s, e, dir));
                return dir > 0
                    ? (season: 2, episode: 6)
                    : (season: 2, episode: 4);
              },
            ),
            resolveSourceToPlaylist: _resolve,
          ),
        );
        // A previous episode is offered on the resolver's word alone.
        expect(playerControls(t).hasPrevious, isTrue);
        expect(playerControls(t).hasNext, isTrue);
        await _previous(d);
        await d.f.until(t, () => searched.isNotEmpty);
        expect(asked.first, (2, 5, -1));
        expect(searched.first, (2, 4));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 fetchable series beyond the pack fetches Next in-player from the resolver',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final searched = <(int, int)>[];
      final asked = <(int, int, int)>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S02E05.mkv'),
            title: 'Show.S02E05.mkv',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 5,
            seriesSourceFetcher: _fetcher(
              season: 2,
              episode: 5,
              searched: searched,
              adjacent: (s, e, dir) async {
                asked.add((s, e, dir));
                return dir > 0 ? (season: 3, episode: 1) : null;
              },
            ),
            resolveSourceToPlaylist: _resolve,
          ),
        );
        await _next(d);
        await d.f.until(t, () => searched.isNotEmpty);
        expect(asked.first, (2, 5, 1));
        expect(searched.first, (3, 1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 first episode with a resolver but no earlier guide entry offers no Previous',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S01E01.mkv'),
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: _fetcher(
              season: 1,
              episode: 1,
              searched: [],
              adjacent: (s, e, dir) async => null,
            ),
            resolveSourceToPlaylist: _resolve,
          ),
        );
        expect(playerControls(t).hasPrevious, isFalse);
        expect(playerControls(t).onPrevious, isNull);
      } finally {
        await d.close();
      }
    },
  );
}
