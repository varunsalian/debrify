import 'dart:async';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

PlaylistEntry _e(String name) => PlaylistEntry(
  url: 'https://player.test/${Uri.encodeComponent(name)}.mp4',
  title: name,
);

String _url(String name) =>
    'https://player.test/${Uri.encodeComponent(name)}.mp4';

Future<PlayerMenuPanel> _shuffleMenu(TvEpisodeDriver d) async {
  playerControls(d.t).onRandom();
  await d.f.advance(d.t, const Duration(milliseconds: 350));
  return d.t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
}

Future<void> _run(TvEpisodeDriver d, void Function() action) async {
  d.observe(action);
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

List<Map<String, dynamic>> _guide(int count) => [
  for (var n = 1; n <= count; n++)
    {'season': 1, 'number': n, 'airdate': '2020-01-0$n'},
];

void main() {
  testWidgets(
    'P18 shuffle without a playlist or fetchable episodes only explains why',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/lonely.mp4',
            title: 'Lonely',
          ),
        );
        playerControls(t).onRandom();
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.text('No playlist items available'), findsOneWidget);
        expect(find.byType(PlayerMenuPanel), findsNothing);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P18 shuffle once from the menu plays the other playlist item', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: _url('a'),
          title: 'Files',
          viewMode: PlaylistViewMode.raw,
          disableAutoResume: true,
          startIndex: 0,
          playlist: [_e('a'), _e('b')],
        ),
      );
      final menu = await _shuffleMenu(d);
      expect(menu.continuousShuffle, isFalse);
      final before = d.opens.length;
      await _run(d, menu.onShuffleOnce);
      await d.f.until(t, () => d.opens.length > before);
      expect(d.opens.last.uri, _url('b'));
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P18 continuous shuffle toggles on with a random play and off with a notice',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('a'),
            title: 'Files',
            viewMode: PlaylistViewMode.raw,
            disableAutoResume: true,
            startIndex: 0,
            playlist: [_e('a'), _e('b')],
          ),
        );
        var menu = await _shuffleMenu(d);
        final before = d.opens.length;
        await _run(d, menu.onShuffleContinuousToggle);
        expect(find.text('Continuous shuffle on'), findsOneWidget);
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('b'));
        await d.f.advance(t, const Duration(seconds: 5));
        menu = await _shuffleMenu(d);
        expect(menu.continuousShuffle, isTrue);
        final afterOn = d.opens.length;
        await _run(d, menu.onShuffleContinuousToggle);
        // The notice queues behind the still-visible "on" snackbar.
        for (var i = 0; i < 12; i++) {
          if (find.text('Continuous shuffle off').evaluate().isNotEmpty) break;
          await d.f.advance(t, const Duration(seconds: 1));
        }
        expect(find.text('Continuous shuffle off'), findsOneWidget);
        expect(d.opens.length, afterOn, reason: 'turning it off plays nothing');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 show shuffle fetches a guide episode that is not in the playlist',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final searched = <(int, int)>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S01E01.mkv'),
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [_e('Show.S01E01.mkv')],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              loadCustomEpisodeInventory: () async => _guide(2),
              searchEpisodes: (s, e) async {
                searched.add((s, e));
                return [episodeSource('Show.S0${s}E0$e')];
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        await d.f.until(t, () => searched.isNotEmpty);
        expect(searched.first, (1, 2));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 show shuffle with no other eligible episode reports it and loads nothing',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final searched = <(int, int)>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S01E01.mkv'),
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [_e('Show.S01E01.mkv')],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              loadCustomEpisodeInventory: () async => _guide(1),
              searchEpisodes: (s, e) async {
                searched.add((s, e));
                return [];
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        final before = d.opens.length;
        final menu = await _shuffleMenu(d);
        await _run(d, menu.onShuffleOnce);
        expect(
          find.text('No other playable episode found for shuffle'),
          findsOneWidget,
        );
        expect(searched, isEmpty);
        expect(d.opens.length, before);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P18 manual Next during an in-flight show shuffle supersedes it',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final inventory = Completer<List<Map<String, dynamic>>>();
      final searched = <(int, int)>[];
      var reads = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _url('Show.S01E01.mkv'),
            title: 'Show pack',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [_e('Show.S01E01.mkv'), _e('Show.S01E02.mkv')],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              loadCustomEpisodeInventory: () {
                reads++;
                return inventory.future;
              },
              searchEpisodes: (s, e) async {
                searched.add((s, e));
                return [episodeSource('Show.S0${s}E0$e')];
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final menu = await _shuffleMenu(d);
        d.observe(menu.onShuffleOnce);
        await d.f.until(t, () => reads == 1);
        // Close the menu and press the ordinary Next while the shuffle waits.
        d.f.navigator.currentState!.maybePop();
        await d.f.advance(t, const Duration(milliseconds: 400));
        final before = d.opens.length;
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => next()) as Future<dynamic>,
        );
        await d.f.until(t, () => d.opens.length > before);
        expect(d.opens.last.uri, _url('Show.S01E02.mkv'));
        final afterNext = d.opens.length;
        inventory.complete(_guide(3));
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.actions.settle(t);
        expect(
          searched,
          isEmpty,
          reason: 'the superseded shuffle never fetches',
        );
        expect(d.opens.length, afterNext);
      } finally {
        if (!inventory.isCompleted) inventory.complete(const []);
        await d.close();
      }
    },
  );
}
