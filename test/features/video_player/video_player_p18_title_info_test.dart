import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

const _pack = [
  PlaylistEntry(url: 'https://player.test/t1.mp4', title: 'Show.S01E01.mkv'),
  PlaylistEntry(url: 'https://player.test/t2.mp4', title: 'Show.S01E02.mkv'),
];

// Its own show name: a show cache from an earlier suite in the same isolate
// must not supply episode data to the no-TVMaze case.
const _plainPack = [
  PlaylistEntry(url: 'https://player.test/p1.mp4', title: 'Plain.S01E01.mkv'),
  PlaylistEntry(url: 'https://player.test/p2.mp4', title: 'Plain.S01E02.mkv'),
];

/// TVMaze answers for the pack above: show 'Official Show', episode titles
/// and an enhanced-metadata payload for S01E01.
http.Response? _tvmaze(http.Request request) {
  if (request.url.host != 'api.tvmaze.com') return null;
  if (request.url.path.endsWith('/episodes')) {
    return http.Response(
      jsonEncode([
        for (var n = 1; n <= 2; n++)
          {
            'id': n,
            'season': 1,
            'number': n,
            'name': 'Pilot $n',
            'airdate': '2020-01-0$n',
            'runtime': 42,
            'rating': {'average': 8.5},
            'summary': '<p>Plot $n</p>',
          },
      ]),
      200,
    );
  }
  return http.Response(
    jsonEncode({
      'id': 77,
      'name': 'Official Show',
      'externals': {'imdb': 'tt7700001'},
      'genres': ['Drama'],
      'language': 'English',
      'premiered': '2020-01-01',
      'network': {
        'name': 'Net',
        'country': {'name': 'Land'},
      },
    }),
    200,
  );
}

Future<VideoPlayerEnvironment> _start(
  WidgetTester t,
  VideoPlayerScreen screen, {
  bool tvmaze = false,
  bool tv = false,
}) async {
  final f = VideoPlayerEnvironment();
  await t.runAsync(f.initialize);
  if (tv) PlatformUtil.debugSetAndroidTvCached(true);
  await f.finish(t, TVMazeService.clearCache());
  f.network.handler = (request) =>
      (tvmaze ? _tvmaze(request) : null) ??
      f.network.replies[request.url.toString()] ??
      http.Response('{}', 404);
  await f.mount(t, screen);
  return f;
}

Controls _controls(WidgetTester t) => playerControls(t);

void main() {
  testWidgets(
    'P18 series pack without TVMaze data titles "Episode N" and subtitles the parsed series',
    (t) async {
      final f = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/p1.mp4',
          title: 'Plain.S01E01.mkv',
          playlist: _plainPack,
          startIndex: 0,
        ),
      );
      try {
        expect(_controls(t).title, 'Episode 1');
        // The filename parser lowercases the series name it extracts.
        expect(_controls(t).subtitle, 'plain • Season 1, Episode 1');
        expect(_controls(t).enhancedMetadata, isEmpty);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'P18 TVMaze episode data prefixes the official show and drops it from the subtitle',
    (t) async {
      final f = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/t1.mp4',
          title: 'Show.S01E01.mkv',
          playlist: _pack,
          startIndex: 0,
          contentImdbId: 'tt7700001',
        ),
        tvmaze: true,
      );
      try {
        await f.until(
          t,
          () => _controls(t).title == 'Official Show — Pilot 1',
          reason: 'TVMaze episode title must reach the dock',
        );
        expect(_controls(t).subtitle, 'Season 1, Episode 1');
        final meta = _controls(t).enhancedMetadata;
        expect(meta.keys.toSet(), {
          'rating',
          'runtime',
          'year',
          'airDate',
          'language',
          'genres',
          'network',
          'country',
          'plot',
        });
        expect(meta['runtime'], 42);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'P18 catalog singleton without an episode title shows the clean content title once',
    (t) async {
      final f = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/one.mp4',
          title: 'Mangled.Release.S02E03.mkv',
          contentTitle: 'Clean Show',
          contentType: 'series',
          playlist: [
            PlaylistEntry(
              url: 'https://player.test/one.mp4',
              title: 'Mangled.Release.S02E03.mkv',
            ),
          ],
          startIndex: 0,
        ),
      );
      try {
        expect(_controls(t).title, 'Clean Show');
        expect(_controls(t).subtitle, 'Season 2, Episode 3');
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'P18 catalog single stream joins episode identity with the release subtitle',
    (t) async {
      final f = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/single.mp4',
          title: 'Some.Release.1080p.mkv',
          subtitle: 'WEB 1080p',
          contentTitle: 'Clean Title',
          contentType: 'series',
          contentImdbId: 'tt0000099',
          contentSeason: 4,
          contentEpisode: 7,
        ),
      );
      try {
        expect(_controls(t).title, 'Clean Title');
        expect(_controls(t).subtitle, 'Season 4, Episode 7 • WEB 1080p');
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'P18 non-series collection falls back to the entry title and widget subtitle',
    (t) async {
      final f = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/m1.mp4',
          title: 'Collection',
          subtitle: 'Box set',
          contentType: 'movie',
          playlist: [
            PlaylistEntry(url: 'https://player.test/m1.mp4', title: 'Alpha'),
            PlaylistEntry(url: 'https://player.test/m2.mp4', title: 'Beta'),
          ],
          startIndex: 0,
        ),
      );
      try {
        expect(_controls(t).title, 'Alpha');
        expect(_controls(t).subtitle, 'Box set');
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'P18 TV dock marks fetched titles clean and release entry titles raw',
    (t) async {
      final f = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/m1.mp4',
          title: 'Collection',
          contentType: 'movie',
          playlist: [
            PlaylistEntry(
              url: 'https://player.test/m1.mp4',
              title: 'Alpha.2019.PROPER.mkv',
            ),
            PlaylistEntry(url: 'https://player.test/m2.mp4', title: 'Beta'),
          ],
          startIndex: 0,
        ),
        tv: true,
      );
      try {
        final tv = t.widget<TvControls>(find.byType(TvControls));
        expect(tv.title, 'Alpha.2019.PROPER.mkv');
        expect(tv.titleIsClean, isFalse);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets('P18 TV dock marks a catalog content title clean', (t) async {
    final f = await _start(
      t,
      const VideoPlayerScreen(
        videoUrl: 'https://player.test/single.mp4',
        title: 'Release.Name.PROPER.mkv',
        contentTitle: 'Real Title Proper',
      ),
      tv: true,
    );
    try {
      final tv = t.widget<TvControls>(find.byType(TvControls));
      expect(tv.title, 'Real Title Proper');
      expect(tv.titleIsClean, isTrue);
      expect(tv.subtitle, isNull);
    } finally {
      await f.close(t);
    }
  });
}
