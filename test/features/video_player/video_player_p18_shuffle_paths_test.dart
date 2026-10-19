import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

PlaylistEntry _e(String name, {int? size}) =>
    PlaylistEntry(url: _url(name), title: name, sizeBytes: size);

Future<PlayerMenuPanel> _shuffleMenu(TvEpisodeDriver d) async {
  playerControls(d.t).onRandom();
  await d.f.advance(d.t, const Duration(milliseconds: 350));
  return d.t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
}

Future<void> _closeMenu(TvEpisodeDriver d) async {
  d.f.navigator.currentState!.maybePop();
  await d.f.advance(d.t, const Duration(milliseconds: 400));
}

Future<void> _run(TvEpisodeDriver d, void Function() action) async {
  d.observe(action);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

Future<void> _ended(TvEpisodeDriver d) async {
  d.player.emit('completed', true);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

List<Map<String, dynamic>> _guide(List<int> numbers) => [
  for (final n in numbers) {'season': 1, 'number': n, 'airdate': '2020-01-0$n'},
];

/// A fetcher whose custom inventory answers from [reads] in call order.
SeriesSourceFetcher _fetcher({
  Future<List<Map<String, dynamic>>> Function()? inventory,
  List<(int, int)>? searched,
  bool found = true,
}) => SeriesSourceFetcher(
  season: 1,
  episode: 1,
  loadCustomEpisodeInventory: inventory,
  searchEpisodes: (s, e) async {
    searched?.add((s, e));
    return found ? [episodeSource('Show.S0${s}E0$e')] : [];
  },
  searchPacks: (s, e) async => [],
);

Future<List<PlaylistEntry>?> _resolve(
  Torrent s, {
  bool Function()? canContinue,
}) async => [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];

/// TVMaze knows the show and the guide [numbers] of season 1.
http.Response? Function(http.Request) _tvmaze(String imdb, List<int> numbers) =>
    (r) {
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
          'id': 77,
          'name': 'Guide Show $imdb',
          'externals': {'imdb': imdb},
          'genres': <String>[],
        }),
        200,
      );
    };

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
  testWidgets(
    'P18 the shuffle control opens only the unified menu section, no legacy dialog',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('a'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [_e('a'), _e('b')],
        ),
      );
      try {
        final menu = await _shuffleMenu(d);
        expect(menu.continuousShuffle, isFalse);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Shuffle Playback'), findsNothing);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 turning continuous shuffle off returns EOF to ordered playback',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('b'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 1,
          initialContinuousShuffle: true,
          playlist: [_e('a'), _e('b')],
        ),
      );
      try {
        var menu = await _shuffleMenu(d);
        expect(menu.continuousShuffle, isTrue);
        await _run(d, menu.onShuffleContinuousToggle);
        await _closeMenu(d);
        menu = await _shuffleMenu(d);
        expect(menu.continuousShuffle, isFalse);
        await _closeMenu(d);
        final before = d.opens.length;
        await _ended(d);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(
          d.opens.length,
          before,
          reason: 'ordered EOF on the last item stays; shuffle would open a',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 shuffle once while continuous shuffle is on turns it off and autoplays',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('b'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 1,
          initialContinuousShuffle: true,
          playlist: [_e('a'), _e('b')],
        ),
      );
      try {
        var menu = await _shuffleMenu(d);
        final before = d.opens.length;
        await _run(d, menu.onShuffleOnce);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('a'));
        expect(d.openAutoplay.last, isTrue);
        await _closeMenu(d);
        menu = await _shuffleMenu(d);
        expect(menu.continuousShuffle, isFalse);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 raw collections shuffle into small files; collection mode keeps to the main group',
    (t) async {
      for (final (mode, expected) in [
        (PlaylistViewMode.raw, 'sample'),
        (PlaylistViewMode.sorted, 'sample'),
        (null, 'feature'),
      ]) {
        final d = await _start(
          t,
          VideoPlayerScreen(
            videoUrl: _url('feature'),
            title: 'Collection',
            viewMode: mode,
            contentType: 'movie',
            disableAutoResume: true,
            startIndex: 0,
            playlist: [
              _e('feature', size: 4000000000),
              _e('sample', size: 10000000),
            ],
          ),
        );
        try {
          final menu = await _shuffleMenu(d);
          final before = d.opens.length;
          await _run(d, menu.onShuffleOnce);
          await d.f.until(t, () => d.opens.length > before);
          expect(d.opens.last.uri, _url(expected), reason: '$mode');
        } finally {
          await d.close();
        }
      }
    },
  );

  testWidgets(
    'P18 show shuffle from the TVMaze guide fetches an episode missing from the pack',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Guide.S01E01.mkv'),
          title: 'Guide.S01E01.mkv',
          contentImdbId: 'tt9180001',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          disableAutoResume: true,
          playlist: [_e('Guide.S01E01.mkv'), _e('Guide.S01E02.mkv')],
          seriesSourceFetcher: _fetcher(searched: searched),
          resolveSourceToPlaylist: _resolve,
        ),
        network: _tvmaze('tt9180001', [1, 3]),
      );
      try {
        final before = d.opens.length;
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        await d.f.until(t, () => searched.isNotEmpty);
        expect(searched, [(1, 3)]);
        expect(
          d.opens.skip(before).map((m) => m.uri),
          isNot(contains(_url('Guide.S01E02.mkv'))),
          reason: 'show shuffle never falls back to the pack order',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 show shuffle loads a guide episode that is in the pack without fetching',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Pack.S01E02.mkv'),
          title: 'Pack.S01E02.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 2,
          disableAutoResume: true,
          startIndex: 1,
          playlist: [_e('Pack.S01E01.mkv'), _e('Pack.S01E02.mkv')],
          seriesSourceFetcher: _fetcher(
            inventory: () async => _guide([1, 2]),
            searched: searched,
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        final before = d.opens.length;
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('Pack.S01E01.mkv'));
        expect(d.openAutoplay.last, isTrue);
        expect(searched, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 show shuffle fetches another source when the pack entry is unavailable',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Dead.S01E02.mkv'),
          title: 'Dead.S01E02.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 2,
          disableAutoResume: true,
          startIndex: 1,
          playlist: [
            const PlaylistEntry(
              url: '',
              title: 'Dead.S01E01.mkv',
              torboxTorrentId: 41,
              torboxFileId: 7,
            ),
            _e('Dead.S01E02.mkv'),
          ],
          seriesSourceFetcher: _fetcher(
            inventory: () async => _guide([1, 2]),
            searched: searched,
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        await d.f.until(t, () => searched.isNotEmpty);
        expect(searched, [(1, 1)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 show shuffle that finds nothing playable stays on the outgoing pack item',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Stay.S01E02.mkv'),
          title: 'Stay.S01E02.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 2,
          disableAutoResume: true,
          startIndex: 1,
          playlist: [
            const PlaylistEntry(
              url: '',
              title: 'Stay.S01E01.mkv',
              torboxTorrentId: 41,
              torboxFileId: 7,
            ),
            _e('Stay.S01E02.mkv'),
          ],
          seriesSourceFetcher: _fetcher(
            inventory: () async => _guide([1, 2]),
            found: false,
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        final title = playerControls(t).title;
        expect(playerControls(t).hasPrevious, isTrue);
        final before = d.opens.length;
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        const gaveUp = 'No other playable episode found for shuffle';
        for (var i = 0; i < 60; i++) {
          if (find.text(gaveUp).evaluate().isNotEmpty) break;
          await d.f.advance(t, const Duration(seconds: 1));
        }
        expect(find.text(gaveUp), findsOneWidget);
        await _closeMenu(d);
        expect(d.opens.length, before);
        expect(playerControls(t).title, title);
        expect(
          playerControls(t).hasPrevious,
          isTrue,
          reason: 'the failed pack load restored the outgoing index',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 show shuffle gives up after three unavailable episodes and says so',
    (t) async {
      final searched = <(int, int)>[];
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Gone.S01E01.mkv'),
          title: 'Gone.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          disableAutoResume: true,
          playlist: [_e('Gone.S01E01.mkv')],
          seriesSourceFetcher: _fetcher(
            inventory: () async => _guide([1, 2, 3, 4, 5, 6]),
            searched: searched,
            found: false,
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        final before = d.opens.length;
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        // Each attempt queues its own fetch notices ahead of the final one.
        const gaveUp = 'No other playable episode found for shuffle';
        for (var i = 0; i < 60; i++) {
          if (find.text(gaveUp).evaluate().isNotEmpty) break;
          await d.f.advance(t, const Duration(seconds: 1));
        }
        expect(find.text(gaveUp), findsOneWidget);
        expect(searched, hasLength(3));
        expect(searched.toSet(), hasLength(3), reason: 'no repeat attempts');
        expect(d.opens.length, before);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 a failing show shuffle inventory reports it and plays nothing',
    (t) async {
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Err.S01E01.mkv'),
          title: 'Err.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          disableAutoResume: true,
          playlist: [_e('Err.S01E01.mkv'), _e('Err.S01E02.mkv')],
          seriesSourceFetcher: _fetcher(
            inventory: () async => throw StateError('inventory down'),
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        final before = d.opens.length;
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        await d.f.until(
          t,
          () => find
              .text('Could not load a random episode')
              .evaluate()
              .isNotEmpty,
        );
        expect(d.logs.any((l) => l.contains('Show shuffle failed')), isTrue);
        expect(d.opens.length, before);
      } finally {
        await d.close();
      }
    },
  );

  for (final (label, second) in [
    ('a second shuffle once', 'once'),
    ('turning continuous shuffle on', 'continuous'),
  ]) {
    testWidgets(
      'P18 $label during an in-flight show shuffle supersedes it and runs fresh',
      (t) async {
        final inventories = <Completer<List<Map<String, dynamic>>>>[];
        final searched = <(int, int)>[];
        final d = await _start(
          t,
          VideoPlayerScreen(
            videoUrl: _url('Race.S01E01.mkv'),
            title: 'Race.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            disableAutoResume: true,
            playlist: [_e('Race.S01E01.mkv')],
            seriesSourceFetcher: _fetcher(
              inventory: () {
                final c = Completer<List<Map<String, dynamic>>>();
                inventories.add(c);
                return c.future;
              },
              searched: searched,
            ),
            resolveSourceToPlaylist: _resolve,
          ),
        );
        try {
          var menu = await _shuffleMenu(d);
          d.observe(menu.onShuffleOnce);
          await d.f.until(t, () => inventories.length == 1);
          await _closeMenu(d);
          menu = await _shuffleMenu(d);
          d.observe(
            second == 'once'
                ? menu.onShuffleOnce
                : menu.onShuffleContinuousToggle,
          );
          await d.f.advance(t, const Duration(milliseconds: 200));
          expect(inventories, hasLength(1), reason: 'the new one waits');
          inventories.first.complete(_guide([1, 2]));
          await d.f.until(t, () => inventories.length == 2);
          inventories.last.complete(_guide([1, 2]));
          await d.f.until(t, () => searched.isNotEmpty);
          await d.f.advance(t, const Duration(seconds: 2));
          await d.f.actions.settle(t);
          expect(searched, [(1, 2)], reason: 'only the fresh shuffle fetches');
        } finally {
          for (final c in inventories) {
            if (!c.isCompleted) c.complete(const []);
          }
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P18 turning continuous shuffle off cancels its in-flight show shuffle',
    (t) async {
      final inventory = Completer<List<Map<String, dynamic>>>();
      final searched = <(int, int)>[];
      var reads = 0;
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _url('Off.S01E01.mkv'),
          title: 'Off.S01E01.mkv',
          contentType: 'series',
          contentSeason: 1,
          contentEpisode: 1,
          disableAutoResume: true,
          playlist: [_e('Off.S01E01.mkv')],
          seriesSourceFetcher: _fetcher(
            inventory: () {
              reads++;
              return inventory.future;
            },
            searched: searched,
          ),
          resolveSourceToPlaylist: _resolve,
        ),
      );
      try {
        var menu = await _shuffleMenu(d);
        d.observe(menu.onShuffleContinuousToggle);
        await d.f.until(t, () => reads == 1);
        await _closeMenu(d);
        menu = await _shuffleMenu(d);
        expect(menu.continuousShuffle, isTrue);
        await _run(d, menu.onShuffleContinuousToggle);
        inventory.complete(_guide([1, 2]));
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.actions.settle(t);
        expect(
          searched,
          isEmpty,
          reason: 'the cancelled shuffle never fetches',
        );
        expect(reads, 1);
      } finally {
        if (!inventory.isCompleted) inventory.complete(const []);
        await d.close();
      }
    },
  );
}
