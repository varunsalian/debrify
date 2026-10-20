import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/tv_episode_driver.dart';

const _pack = [
  PlaylistEntry(url: 'https://player.test/m1.mp4', title: 'Show.S01E01.mkv'),
  PlaylistEntry(url: 'https://player.test/m2.mp4', title: 'Show.S01E02.mkv'),
];

const _poster = 'https://img.test/show-original.jpg';

http.Response? _tvmaze(http.Request r, {String imdb = 'tt7700042'}) {
  if (r.url.host != 'api.tvmaze.com') return null;
  if (r.url.path.endsWith('/episodes')) {
    return http.Response(
      jsonEncode([
        for (var n = 1; n <= 2; n++)
          {'id': n, 'season': 1, 'number': n, 'name': 'Ep $n'},
      ]),
      200,
    );
  }
  final show = {
    'id': 42,
    'name': 'Show',
    'externals': {'imdb': imdb},
    'image': {
      'medium': 'https://img.test/show-medium.jpg',
      'original': _poster,
    },
    'genres': <String>[],
  };
  if (r.url.path == '/search/shows') {
    return http.Response(
      jsonEncode([
        {'score': 0.9, 'show': show},
      ]),
      200,
    );
  }
  return http.Response(
    jsonEncode({
      'id': 42,
      'name': 'Show',
      'externals': {'imdb': imdb},
      'image': {
        'medium': 'https://img.test/show-medium.jpg',
        'original': _poster,
      },
      'genres': <String>[],
    }),
    200,
  );
}

Future<Map<String, dynamic>> _row(
  TvEpisodeDriver d,
  String key,
  String id,
) async {
  final items = await d.f.finish(d.t, PlaylistStorage.getPlaylistItemsRaw());
  return items.firstWhere((item) => item[key]?.toString() == id);
}

Future<void> _seed(TvEpisodeDriver d, Map<String, dynamic> item) =>
    // Seed the stored row directly; the add path's dedupe and RD hash
    // enrichment are not under test here.
    d.f.finish(d.t, PlaylistStorage.savePlaylistItemsRaw([item]));

void main() {
  testWidgets(
    'P18 TVMaze-discovered series IMDb id and poster are written back to the Real-Debrid playlist row',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.f.finish(t, TVMazeService.clearCache());
        await _seed(d, {
          'title': 'Show pack',
          'provider': 'realdebrid',
          'rdTorrentId': 'rd-77',
          'kind': 'collection',
        });
        d.f.network.handler = (r) => _tvmaze(r) ?? http.Response('{}', 404);
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/m1.mp4',
            title: 'Show pack',
            playlist: _pack,
            rdTorrentId: 'rd-77',
          ),
        );
        await d.f.until(
          t,
          () => d.logs.any((l) => l.contains('Poster URL: $_poster')),
          reason: 'the poster write runs after the IMDb write',
        );
        await d.f.advance(t, const Duration(milliseconds: 500));
        final row = await _row(d, 'rdTorrentId', 'rd-77');
        expect(row['imdbId'], 'tt7700042');
        expect(row.values, contains(_poster));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a catalog IMDb id on the launch suppresses the playlist IMDb write but not the poster',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.f.finish(t, TVMazeService.clearCache());
        await _seed(d, {
          'title': 'Show pack',
          'provider': 'torbox',
          'torboxTorrentId': 5150,
          'kind': 'collection',
        });
        d.f.network.handler = (r) => _tvmaze(r) ?? http.Response('{}', 404);
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/m1.mp4',
            title: 'Show pack',
            playlist: _pack,
            contentImdbId: 'tt7700042',
            torboxTorrentId: '5150',
          ),
        );
        await d.f.until(
          t,
          () => d.logs.any((l) => l.contains('Poster URL: $_poster')),
        );
        await d.f.advance(t, const Duration(milliseconds: 500));
        final row = await _row(d, 'torboxTorrentId', '5150');
        expect(row['imdbId'], isNull);
        expect(row.values, contains(_poster));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 poster write-back is skipped without any playlist identifier',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.f.finish(t, TVMazeService.clearCache());
        d.f.network.handler = (r) => _tvmaze(r) ?? http.Response('{}', 404);
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/m1.mp4',
            title: 'Show pack',
            playlist: _pack,
          ),
        );
        await d.f.until(
          t,
          () => d.logs.any(
            (l) =>
                l.contains('No valid identifier found, skipping poster save'),
          ),
        );
        expect(d.logs.any((l) => l.contains('Poster URL:')), isFalse);
      } finally {
        await d.close();
      }
    },
  );
}
