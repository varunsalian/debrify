import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final stamped in [false, true]) {
    testWidgets(
      'P17 synthetic guide cache, stamped=$stamped, identity and no-op row',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: stamped ? 'Show.S02E03.mkv' : 'Unknown stream',
              contentTitle: 'Collection',
              contentType: 'series',
              contentSeason: 2,
              contentEpisode: 3,
              contentImdbId: 'tt2222222',
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 2,
                episode: 3,
                searchEpisodes: (s, e) async => [],
                searchPacks: (s, e) async => [],
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async => [],
            ),
          );
          final first = await d.browser();
          expect(first.showAllEpisodes, isTrue);
          expect(first.currentEpisodeIndex, 0);
          expect(first.seriesPlaylist.isSeries, isTrue);
          expect(first.seriesPlaylist.imdbId, 'tt2222222');
          expect(
            first.seriesPlaylist.findOriginalIndexBySeasonEpisode(2, 3),
            0,
          );
          final episode = first.seriesPlaylist.allEpisodes.single;
          expect(
            episode.filename,
            stamped ? 'Show.S02E03.mkv' : 'S02E03 Unknown stream',
          );
          expect(episode.url, 'https://player.test/a.mp4');
          expect(first.imdbKnownAtLaunch, isTrue);
          expect(first.metadataReady, isNotNull);
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => first.onEpisodeSelected(2, 3))
                as Future<dynamic>,
          );
          expect(d.opens, hasLength(1));
          Navigator.of(t.element(find.byType(VideoPlayerScreen))).pop();
          await d.f.advance(t, const Duration(milliseconds: 500));
          final again = await d.browser();
          expect(identical(again.seriesPlaylist, first.seriesPlaylist), isTrue);
          expect(identical(again.metadataReady, first.metadataReady), isTrue);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets('P17 unknown episode cannot synthesize a sheet', (t) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'Unknown',
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 1,
            episode: 1,
            searchEpisodes: (s, e) async => [],
            searchPacks: (s, e) async => [],
          ),
          resolveSourceToPlaylist: (s, {canContinue}) async => [],
        ),
      );
      playerControls(t).onShowPlaylist();
      await d.f.advance(t, const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsNothing);
      expect(d.opens, hasLength(1));
    } finally {
      await d.close();
    }
  });
  for (final coverage in [
    ('completeSeries', null, null, null, true),
    ('completeSeries', null, 1, 3, true),
    ('completeSeries', null, 2, 2, true),
    ('completeSeries', null, 3, 4, false),
    ('completeSeries', null, null, 1, false),
    ('multiSeasonPack', null, 2, 2, true),
    ('multiSeasonPack', null, 1, 3, true),
    ('multiSeasonPack', null, null, 3, false),
    ('multiSeasonPack', null, 1, null, false),
    ('multiSeasonPack', null, 3, 4, false),
    ('seasonPack', 2, null, null, true),
    ('seasonPack', 1, null, null, false),
    ('singleEpisode', null, null, null, false),
    (null, null, null, null, false),
  ]) {
    testWidgets('P17 existing pack coverage $coverage', (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var attempts = 0;
      final pack = episodeSource(
        'Pack',
        type: StreamType.torrent,
        coverage: coverage.$1,
        season: coverage.$2,
        start: coverage.$3,
        end: coverage.$4,
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S02E01.mkv',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 1,
            stremioSources: [episodeSource('Show.S02E01'), pack],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 2,
              episode: 1,
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              validateCandidate: (s) async {
                attempts++;
                return false;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        attempts = 0;
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(2, 2))
              as Future<dynamic>,
        );
        expect(attempts, coverage.$5 ? 1 : 0);
        expect(d.opens, hasLength(1));
      } finally {
        await d.close();
      }
    });
  }
  testWidgets(
    'P17 position subscription primes next direct episode once with current identity',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final primed = <(int, int, Torrent)>[];
      final initial = episodeSource('Show.S02E03');
      final fetcher = _PreparingFetcher(
        prepareNextDirectEpisode: (s, e, source) async {
          primed.add((s, e, source));
        },
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: initial.directUrl!,
            title: initial.displayTitle,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            stremioSources: [initial],
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        fetcher.calls.clear();
        d.player.emit('duration', const Duration(seconds: 200));
        d.player.emit('position', const Duration(seconds: 130));
        await d.f.advance(t);
        d.player.emit('position', const Duration(seconds: 140));
        await d.f.advance(t);
        expect(primed, [(2, 3, initial)]);
        expect(identical(primed.single.$3, initial), isTrue);
        expect(fetcher.calls, [
          (initial, 2, 3, 130000, 200000),
          (initial, 2, 3, 140000, 200000),
        ]);
      } finally {
        await d.close();
      }
    },
  );
  for (final blocked in ['paused', 'transition']) {
    testWidgets('P17 prefetch suppresses position speculation while $blocked', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var primed = 0;
      final held = Completer<Map<String, dynamic>?>();
      Future<dynamic>? navigation;
      final initial = episodeSource('Show.S02E03');
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: initial.directUrl!,
            title: initial.displayTitle,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            stremioSources: [initial],
            requestNextChannel: () => held.future,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 2,
              episode: 3,
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              prepareNextDirectEpisode: (s, e, source) async {
                primed++;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        d.player.emit('duration', const Duration(seconds: 200));
        await d.f.advance(t);
        if (blocked == 'transition') {
          navigation = d.beginNextChannel();
          await d.f.actions.settle(t);
        } else {
          d.player.state = d.player.state.copyWith(playing: false);
          d.player.emit('playing', false);
          await d.f.advance(t);
        }
        d.player.emit('position', const Duration(seconds: 130));
        await d.f.advance(t);
        expect(primed, 0);
        expect(d.errors, isEmpty);
      } finally {
        held.complete(null);
        if (navigation != null) {
          await d.f.finish(t, navigation);
        }
        await d.close();
      }
    });
  }
}

// The existing injected data boundary records the public API arguments and
// still delegates to production dedupe/eligibility. No player-State seam.
class _PreparingFetcher extends SeriesSourceFetcher {
  _PreparingFetcher({required super.prepareNextDirectEpisode})
    : super(
        season: 2,
        episode: 3,
        searchEpisodes: (s, e) async => [],
        searchPacks: (s, e) async => [],
      );
  final calls = <(Torrent, int, int, int, int)>[];
  @override
  Future<void> prepareFromProgress({
    required Torrent source,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
  }) {
    calls.add((source, season, episode, positionMs, durationMs));
    return super.prepareFromProgress(
      source: source,
      season: season,
      episode: episode,
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }
}
