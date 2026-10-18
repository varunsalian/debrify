import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/tv_episode_driver.dart';

const _preferredMissing =
    'Your previous source is unavailable for this episode. Trying other sources.';

Future<void> _expireSleep(WidgetTester t, TvEpisodeDriver d) async {
  await pickSleep(t, d.f, const SleepTimerSelection(SleepTimerMode.countdown));
  await waitSleepToast(t, d.f, 'Sleep timer ended — paused');
}

void main() {
  testWidgets(
    'P17 pinned ladder tries the next pinned candidate after an unavailable one',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final first = episodeSource('First.S01E02');
      final second = episodeSource('Second.S01E02');
      final trace = <String>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              pinnedDirectCandidates:
                  (season, episode, {onPreferredMissing}) async* {
                    yield first;
                    yield second;
                  },
              searchEpisodes: (s, e) async {
                trace.add('episodes');
                return [];
              },
              searchPacks: (s, e) async {
                trace.add('packs');
                return [];
              },
              validateCandidate: (source) async => source != first,
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
        );
        expect(d.opens.last.uri, second.directUrl);
        expect(trace, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 pinned ladder stops without resuming the stream once an unavailable candidate went stale',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final first = episodeSource('First.S01E02');
      final gate = Completer<bool>();
      final trace = <String>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 2),
              pinnedDirectCandidates:
                  (season, episode, {onPreferredMissing}) async* {
                    trace.add('pinned');
                    yield first;
                    trace.add('resumed');
                    yield episodeSource('Second.S01E02');
                  },
              searchEpisodes: (s, e) async {
                trace.add('episodes');
                return [];
              },
              searchPacks: (s, e) async {
                trace.add('packs');
                return [];
              },
              validateCandidate: (source) {
                trace.add('allow:${source.name}');
                return source == first ? gate.future : Future.value(true);
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        d.player.emit('completed', true);
        await d.f.until(t, () => trace.contains('allow:${first.name}'));
        await _expireSleep(t, d);
        gate.complete(false);
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(trace, ['pinned', 'allow:${first.name}']);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete(false);
        await d.close();
      }
    },
  );

  for (final stale in [false, true]) {
    testWidgets(
      'P17 preferred-missing notice ${stale ? 'is suppressed for a stale' : 'shows for a current'} request',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final gate = Completer<void>();
        var entered = false;
        var seen = false;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S01E01.mkv',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                resolveAdjacentEpisode: (s, e, direction) async =>
                    (season: 1, episode: 2),
                pinnedDirectCandidates:
                    (season, episode, {onPreferredMissing}) async* {
                      entered = true;
                      await gate.future;
                      onPreferredMissing!();
                    },
                searchEpisodes: (s, e) async => [],
                searchPacks: (s, e) async => [],
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
              ],
            ),
          );
          d.player.emit('completed', true);
          await d.f.until(t, () => entered);
          if (stale) await _expireSleep(t, d);
          gate.complete();
          for (var i = 0; i < 80; i++) {
            await d.f.advance(t, const Duration(milliseconds: 100));
            seen = seen || find.text(_preferredMissing).evaluate().isNotEmpty;
          }
          expect(seen, !stale);
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P17 guide fetch advances the navigation generation and supersedes a pending EOF next',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final adjacent = Completer<({int season, int episode})?>();
      var entered = false;
      final searches = <(int, int)>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              resolveAdjacentEpisode: (s, e, direction) {
                entered = true;
                return adjacent.future;
              },
              searchEpisodes: (s, e) async {
                searches.add((s, e));
                return [];
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        d.player.emit('completed', true);
        await d.f.until(t, () => entered);
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 3)),
        );
        expect(searches, [(1, 3)]);
        adjacent.complete((season: 1, episode: 2));
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(searches, [(1, 3)]);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!adjacent.isCompleted) adjacent.complete(null);
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 existing-source stage starts at index zero when another source is current',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final allowed = <String>[];
      final zero = episodeSource('Zero.S01E02');
      final current = episodeSource('Current.S01E01');
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: current.directUrl!,
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [zero, current],
            stremioCurrentSourceIndex: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              validateCandidate: (source) async {
                allowed.add(source.displayTitle);
                return true;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        allowed.clear();
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
        );
        expect(allowed, [zero.displayTitle]);
        expect(d.opens.last.uri, zero.directUrl);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 synthetic guide refuses an identity with an episode but no season',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show E05',
            contentType: 'series',
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 5,
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        // Observed so a guard regression surfaces as a recorded error.
        d.observe(() => playerControls(t).onShowPlaylist());
        await d.f.advance(t, const Duration(seconds: 1));
        expect(find.byType(SeriesBrowser), findsNothing);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 blocked fetch reached after dispose leaves the disposed curtain alone',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final search = Completer<List<Torrent>>();
      final previous = Completer<({int season, int episode})?>();
      var searching = false;
      var resolving = false;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E02.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 2,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 2,
              resolveAdjacentEpisode: (s, e, direction) {
                resolving = true;
                return previous.future;
              },
              searchEpisodes: (s, e) {
                searching = true;
                return search.future;
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final b = await d.browser();
        d.observe<dynamic>(() => b.onEpisodeSelected(1, 3));
        await d.f.until(t, () => searching);
        d.f.navigator.currentState!.pop();
        await d.f.advance(t, const Duration(milliseconds: 400));
        final press = playerControls(t).onPrevious!;
        d.observe<dynamic>(() => press());
        await d.f.until(t, () => resolving);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        previous.complete((season: 1, episode: 1));
        await d.f.actions.settle(t);
        expect(d.errors, isEmpty);
      } finally {
        if (!previous.isCompleted) previous.complete(null);
        if (!search.isCompleted) search.complete([]);
        await d.close();
      }
    },
  );

  for (final stage in ['existing', 'episodes', 'packs']) {
    testWidgets(
      'P17 $stage stage stops after an unavailable candidate went stale',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final type = stage == 'packs'
            ? StreamType.torrent
            : StreamType.directUrl;
        final first = episodeSource('First.S01E02', type: type);
        final second = episodeSource('Second.S01E02', type: type);
        final gate = Completer<bool>();
        final trace = <String>[];
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S01E01.mkv',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              stremioSources: [
                episodeSource('Original.S01E01'),
                if (stage == 'existing') ...[first, second],
              ],
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                resolveAdjacentEpisode: (s, e, direction) async =>
                    (season: 1, episode: 2),
                searchEpisodes: (s, e) async {
                  trace.add('episodes');
                  return stage == 'episodes' ? [first, second] : [];
                },
                searchPacks: (s, e) async {
                  trace.add('packs');
                  return stage == 'packs' ? [first, second] : [];
                },
                validateCandidate: (source) {
                  trace.add('allow:${source.name}');
                  return source == first ? gate.future : Future.value(false);
                },
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
              ],
            ),
          );
          trace.clear();
          d.player.emit('completed', true);
          await d.f.until(t, () => trace.contains('allow:${first.name}'));
          await _expireSleep(t, d);
          gate.complete(false);
          await d.f.actions.settle(t);
          await d.f.advance(t, const Duration(seconds: 1));
          expect(trace, [
            if (stage != 'existing') 'episodes',
            if (stage == 'packs') 'packs',
            'allow:${first.name}',
          ]);
          expect(d.opens, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete(false);
          await d.close();
        }
      },
    );
  }

  for (final stage in ['episodes', 'packs']) {
    testWidgets(
      'P17 $stage search that completes after staleness tries no candidate',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final type = stage == 'packs'
            ? StreamType.torrent
            : StreamType.directUrl;
        final found = episodeSource('Found.S01E02', type: type);
        final search = Completer<List<Torrent>>();
        final trace = <String>[];
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S01E01.mkv',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                resolveAdjacentEpisode: (s, e, direction) async =>
                    (season: 1, episode: 2),
                searchEpisodes: (s, e) {
                  trace.add('episodes');
                  return stage == 'episodes'
                      ? search.future
                      : Future.value(<Torrent>[]);
                },
                searchPacks: (s, e) {
                  trace.add('packs');
                  return stage == 'packs'
                      ? search.future
                      : Future.value(<Torrent>[]);
                },
                validateCandidate: (source) async {
                  trace.add('allow:${source.name}');
                  return true;
                },
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
              ],
            ),
          );
          trace.clear();
          d.player.emit('completed', true);
          await d.f.until(t, () => trace.contains(stage));
          await _expireSleep(t, d);
          search.complete([found]);
          await d.f.actions.settle(t);
          await d.f.advance(t, const Duration(seconds: 1));
          expect(trace, ['episodes', if (stage == 'packs') 'packs']);
          expect(d.opens, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          if (!search.isCompleted) search.complete([]);
          await d.close();
        }
      },
    );
  }

  for (final stage in ['episodes', 'packs']) {
    testWidgets(
      'P17 $stage stage exhausting a short result list reports no source',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final type = stage == 'packs'
            ? StreamType.torrent
            : StreamType.directUrl;
        final only = episodeSource('Only.S01E02', type: type);
        final allowed = <String>[];
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S01E01.mkv',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                searchEpisodes: (s, e) async =>
                    stage == 'episodes' ? [only] : [],
                searchPacks: (s, e) async => stage == 'packs' ? [only] : [],
                validateCandidate: (source) async {
                  allowed.add(source.name);
                  return false;
                },
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async => [],
            ),
          );
          allowed.clear();
          final b = await d.browser();
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
          );
          await waitSleepToast(t, d.f, 'No playable source found for S01E02');
          expect(allowed, [only.name]);
          expect(d.opens, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final stage in ['existing', 'episodes', 'packs']) {
    testWidgets('P17 $stage stage stops at the first committed candidate', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final type = stage == 'packs' ? StreamType.torrent : StreamType.directUrl;
      final winner = episodeSource('Winner.S01E02', type: type);
      final spare = episodeSource('Spare.S01E02', type: type);
      final allowed = <String>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [
              episodeSource('Original.S01E01'),
              if (stage == 'existing') ...[winner, spare],
            ],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchEpisodes: (s, e) async =>
                  stage == 'episodes' ? [winner, spare] : [],
              searchPacks: (s, e) async =>
                  stage == 'packs' ? [winner, spare] : [],
              validateCandidate: (source) async {
                allowed.add(source.name);
                return true;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(
                url: s.directUrl!,
                title: stage == 'packs' ? 'Unparseable' : s.displayTitle,
              ),
            ],
          ),
        );
        allowed.clear();
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
        );
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(allowed, [winner.name]);
        expect(d.opens, hasLength(2));
        expect(d.opens.last.uri, winner.directUrl);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }

  testWidgets(
    'P17 failed previous-episode fetch drops the transition curtain it raised',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E02.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 2,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 2,
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 1),
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        expect(find.byType(mkv.Video), findsOneWidget);
        final dynamic previous = playerControls(t).onPrevious!;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => previous()));
        await waitSleepToast(t, d.f, 'No playable source found for S01E01');
        await d.f.advance(t);
        expect(find.byType(mkv.Video), findsOneWidget);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 single resolved stream with an episode but no season is stamped and played',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final found = episodeSource('Found.S01E02');
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchEpisodes: (s, e) async => [found],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: 'Show E02'),
            ],
          ),
        );
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
        );
        await d.f.actions.settle(t);
        expect(d.opens, hasLength(2));
        expect(d.opens.last.uri, found.directUrl);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
