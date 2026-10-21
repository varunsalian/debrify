import 'package:debrify/features/video_player/application/vp_filename_hash.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';

const _show = 'P20 Index Show';

/// Deliberately unsorted: the first episode (S01E01) is original index 1.
const _episodes = [
  PlaylistEntry(
    url: 'https://index.test/s1e3.mkv',
    title: 'P20.Index.Show.S01E03.mkv',
  ),
  PlaylistEntry(
    url: 'https://index.test/s1e1.mkv',
    title: 'P20.Index.Show.S01E01.mkv',
  ),
  PlaylistEntry(
    url: 'https://index.test/s2e1.mkv',
    title: 'P20.Index.Show.S02E01.mkv',
  ),
  PlaylistEntry(
    url: 'https://index.test/s1e2.mkv',
    title: 'P20.Index.Show.S01E02.mkv',
  ),
];

VideoPlayerScreen _series({
  int? season,
  int? episode,
  bool disableAutoResume = false,
  int? startIndex,
}) => VideoPlayerScreen(
  videoUrl: _episodes.first.url,
  title: _show,
  contentType: 'series',
  contentSeason: season,
  contentEpisode: episode,
  disableAutoResume: disableAutoResume,
  startIndex: startIndex,
  playlist: _episodes,
);

Future<void> _lastPlayed(EngineDriver d, int season, int episode) =>
    d.f.finish<void>(
      d.t,
      SeriesProgressStorage.saveSeriesPlaybackState(
        seriesTitle: _show,
        season: season,
        episode: episode,
        positionMs: 60000,
        durationMs: 1200000,
      ),
    );

String _opened(EngineDriver d) {
  final open = d.player.calls.firstWhere((c) => c.$1 == 'open');
  return ((open.$2 as (mk.Playable, bool)).$1 as mk.Media).uri;
}

Map<String, String>? _openedHeaders(EngineDriver d) {
  final open = d.player.calls.firstWhere((c) => c.$1 == 'open');
  return ((open.$2 as (mk.Playable, bool)).$1 as mk.Media).httpHeaders;
}

Future<String> _start(
  WidgetTester t,
  VideoPlayerScreen screen, {
  Future<void> Function(EngineDriver)? seed,
  void Function(EngineDriver)? inspect,
}) async {
  final d = EngineDriver(t);
  await d.initialize();
  try {
    if (seed != null) await seed(d);
    await d.mount(screen: screen);
    inspect?.call(d);
    expect(d.errors, isEmpty);
    return _opened(d);
  } finally {
    await d.close();
  }
}

void main() {
  testWidgets(
    'P20 auto-resume off opens the requested start index even with a stored last episode',
    (t) async {
      final url = await _start(
        t,
        _series(disableAutoResume: true, startIndex: 2),
        seed: (d) => _lastPlayed(d, 1, 2),
      );
      expect(url, _episodes[2].url);
    },
  );

  testWidgets(
    'P20 auto-resume off without a start index opens the first entry',
    (t) async {
      final url = await _start(
        t,
        _series(disableAutoResume: true),
        seed: (d) => _lastPlayed(d, 1, 2),
      );
      expect(url, _episodes[0].url);
    },
  );

  testWidgets(
    'P20 an explicit season and episode found in the pack wins over the last-played episode',
    (t) async {
      final url = await _start(
        t,
        _series(season: 2, episode: 1),
        seed: (d) => _lastPlayed(d, 1, 2),
      );
      expect(url, _episodes[2].url);
    },
  );

  testWidgets(
    'P20 an explicit episode missing from the pack opens the first episode, never the last-played one',
    (t) async {
      final url = await _start(
        t,
        _series(season: 5, episode: 9),
        seed: (d) => _lastPlayed(d, 1, 2),
      );
      expect(url, _episodes[1].url);
    },
  );

  testWidgets(
    'P20 a target with only a season is not explicit and resumes the last-played episode',
    (t) async {
      final url = await _start(
        t,
        _series(season: 2),
        seed: (d) => _lastPlayed(d, 1, 2),
      );
      expect(url, _episodes[3].url);
    },
  );

  testWidgets(
    'P20 without a target the last-played episode is resumed by its original index',
    (t) async {
      final url = await _start(t, _series(), seed: (d) => _lastPlayed(d, 1, 2));
      expect(url, _episodes[3].url);
    },
  );

  testWidgets(
    'P20 a last-played episode absent from the pack opens the first episode',
    (t) async {
      final logs = <String>[];
      final url = await _start(
        t,
        _series(),
        seed: (d) => _lastPlayed(d, 4, 4),
        inspect: (d) => logs.addAll(d.logs),
      );
      expect(url, _episodes[1].url);
      expect(
        logs.where(
          (l) => l.contains('resume entry S4E4 not found in playlist'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'P20 an unreadable last-played record is swallowed and the first episode opens',
    (t) async {
      final logs = <String>[];
      final url = await _start(
        t,
        _series(),
        seed: (d) async {
          await _lastPlayed(d, 1, 2);
          final map = await d.f.finish(
            t,
            PlaybackStateStore.getPlaybackStateMap(),
          );
          for (final raw in map.values) {
            final seasons = (raw as Map)['seasons'] as Map;
            for (final episodes in seasons.values) {
              for (final row in (episodes as Map).values) {
                // The spread record keeps this key over the parsed season.
                (row as Map)['season'] = 'one';
              }
            }
          }
          await d.f.finish(t, PlaybackStateStore.savePlaybackStateMap(map));
        },
        inspect: (d) => logs.addAll(d.logs),
      );
      expect(url, _episodes[1].url);
      expect(
        logs.where(
          (l) =>
              l.startsWith('VideoPlayer: failed to read last episode resume'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('P20 a series with no history opens its first episode', (
    t,
  ) async {
    expect(await _start(t, _series()), _episodes[1].url);
  });

  const movies = [
    PlaylistEntry(
      url: 'https://index.test/m0.mkv',
      title: 'Extra clip.mkv',
      sizeBytes: 10,
    ),
    PlaylistEntry(
      url: 'https://index.test/m1.mkv',
      title: 'Main feature.mkv',
      sizeBytes: 1000,
    ),
    PlaylistEntry(
      url: 'https://index.test/m2.mkv',
      title: 'Other feature.mkv',
      sizeBytes: 900,
    ),
  ];
  VideoPlayerScreen collection({int? startIndex}) => VideoPlayerScreen(
    videoUrl: movies.first.url,
    title: 'P20 index collection',
    contentType: 'movie',
    startIndex: startIndex,
    playlist: movies,
  );

  testWidgets(
    'P20 a collection resumes the entry with the newest updatedAt, keeping the earlier entry on a tie',
    (t) async {
      final url = await _start(
        t,
        collection(),
        seed: (d) async {
          for (final entry in movies) {
            await d.f.finish(
              t,
              VideoProgressStorage.saveVideoPlaybackState(
                videoTitle: vpFilenameHash(entry.title),
                videoUrl: entry.url,
                positionMs: 60000,
                durationMs: 1200000,
              ),
            );
          }
          final map = await d.f.finish(
            t,
            PlaybackStateStore.getPlaybackStateMap(),
          );
          final updated = {
            vpFilenameHash(movies[0].title): 300,
            vpFilenameHash(movies[1].title): 100,
            vpFilenameHash(movies[2].title): 300,
          };
          for (final raw in map.values) {
            final row = raw as Map;
            row['updatedAt'] = updated[row['title']];
          }
          await d.f.finish(t, PlaybackStateStore.savePlaybackStateMap(map));
        },
      );
      expect(url, movies[0].url);
    },
  );

  testWidgets(
    'P20 a collection with one stored entry resumes it over the main-group default',
    (t) async {
      final url = await _start(
        t,
        collection(),
        seed: (d) => d.f.finish(
          t,
          VideoProgressStorage.saveVideoPlaybackState(
            videoTitle: vpFilenameHash(movies[2].title),
            videoUrl: movies[2].url,
            positionMs: 60000,
            durationMs: 1200000,
          ),
        ),
      );
      expect(url, movies[2].url);
    },
  );

  testWidgets(
    'P20 a collection with no history opens the first main-group entry, not a small extra',
    (t) async {
      expect(await _start(t, collection(startIndex: 0)), movies[1].url);
    },
  );

  for (final (start, expected) in [(9, 3), (-2, 0)]) {
    testWidgets('P20 a stale start index $start is clamped into the playlist', (
      t,
    ) async {
      final url = await _start(
        t,
        _series(disableAutoResume: true, startIndex: start),
      );
      expect(url, _episodes[expected].url);
    });
  }

  testWidgets(
    'P20 the launch entry headers win and an entry without headers falls back to the widget headers',
    (t) async {
      for (final entryHeaders in [
        {'X-Entry': 'entry'},
        null,
      ]) {
        final d = EngineDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://index.test/h.mkv',
              title: 'P20 headers',
              httpHeaders: const {'X-Widget': 'widget'},
              disableAutoResume: true,
              playlist: [
                PlaylistEntry(
                  url: 'https://index.test/h.mkv',
                  title: 'Headers.mkv',
                  httpHeaders: entryHeaders,
                ),
              ],
            ),
          );
          expect(
            _openedHeaders(d),
            entryHeaders ?? const {'X-Widget': 'widget'},
          );
        } finally {
          await d.close();
        }
      }
    },
  );
}
