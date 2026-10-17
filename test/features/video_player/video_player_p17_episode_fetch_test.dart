import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'support/tv_episode_driver.dart';
import 'support/sleep_timer_driver.dart' show waitSleepToast;

void main() {
  for (final stage in ['pinned', 'existing', 'episodes', 'packs', 'none']) {
    testWidgets(
      'P17 episode ladder reaches $stage in order and prunes after commit',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final trace = <String>[];
        final initial = episodeSource('Show.S01E01');
        final winner = episodeSource(
          stage == 'packs' ? 'Season pack' : 'Show.S01E02',
          type: stage == 'packs' ? StreamType.torrent : StreamType.directUrl,
        );
        final rejected = episodeSource('Rejected.S01E02');
        final fetched = SeriesSourceFetcher(
          season: 1,
          episode: 1,
          pinnedDirectCandidates:
              (season, episode, {onPreferredMissing}) async* {
                trace.add('pinned:$season:$episode');
                if (stage == 'pinned') {
                  yield winner;
                }
              },
          searchEpisodes: (s, e) async {
            trace.add('episodes:$s:$e');
            return stage == 'episodes' ? [winner] : [];
          },
          searchPacks: (s, e) async {
            trace.add('packs:$s:$e');
            return stage == 'packs' ? [winner] : [];
          },
          validateCandidate: (source) async {
            trace.add('allow:${source.name}');
            return source != rejected;
          },
        );
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: initial.directUrl!,
              title: 'Show.S01E01.mkv',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              playlist: [
                PlaylistEntry(
                  url: initial.directUrl!,
                  title: 'Show.S01E01.mkv',
                ),
              ],
              stremioSources: [
                initial,
                if (stage == 'existing') winner,
                rejected,
              ],
              seriesSourceFetcher: fetched,
              resolveSourceToPlaylist: (source, {canContinue}) async {
                trace.add('resolve:${source.name}:${canContinue!()}');
                return [
                  PlaylistEntry(
                    url: source.directUrl!,
                    title: stage == 'packs'
                        ? 'Unparseable'
                        : source.displayTitle,
                  ),
                ];
              },
            ),
          );
          trace.clear();
          final b = await d.browser();
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => b.onEpisodeSelected(1, 2))
                as Future<dynamic>,
          );
          if (stage == 'none') {
            expect(d.opens, hasLength(1));
            await waitSleepToast(t, d.f, 'No playable source found for S01E02');
            expect(
              find.text('No playable source found for S01E02'),
              findsOneWidget,
            );
            expect(trace, [
              'pinned:1:2',
              'allow:Rejected.S01E02.mkv',
              'episodes:1:2',
              'packs:1:2',
            ]);
          } else {
            expect(d.opens.last.uri, winner.directUrl);
            expect(trace.first, 'pinned:1:2');
            expect(trace.last, 'resolve:${winner.name}:true');
            expect(
              trace.where((v) => v.startsWith('packs:')).length,
              stage == 'packs' ? 1 : 0,
            );
            expect(
              trace.where((v) => v.startsWith('episodes:')).length,
              ['packs', 'episodes'].contains(stage) ? 1 : 0,
            );
            // The sheet exposes the actual pruned source list/index after the
            // synchronous retainForEpisode call, rather than awaiting a seam.
            final sheet = await d.sourceSheet();
            expect(sheet.currentSourceIndex, stage == 'existing' ? 0 : 1);
            expect(sheet.sources.any((s) => s.name == initial.name), isFalse);
            expect(sheet.sources[sheet.currentSourceIndex].name, winner.name);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final result in [
    'throw',
    'empty',
    'wrong singleton',
    'unparseable singleton',
    'pack missing',
    'pack match',
  ]) {
    testWidgets('P17 candidate resolution $result', (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final candidate = episodeSource('Show.S01E02');
      var resolved = 0;
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
              searchEpisodes: (s, e) async => [candidate],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (source, {canContinue}) async {
              resolved++;
              expect(canContinue!(), isTrue);
              if (result == 'throw') {
                throw StateError('resolver failure');
              }
              if (result == 'empty') {
                return [];
              }
              if (result == 'pack missing') {
                return [
                  const PlaylistEntry(
                    url: 'https://player.test/3.mp4',
                    title: 'Show.S01E03.mkv',
                  ),
                  const PlaylistEntry(
                    url: 'https://player.test/4.mp4',
                    title: 'Show.S01E04.mkv',
                  ),
                ];
              }
              if (result == 'pack match') {
                return [
                  const PlaylistEntry(
                    url: 'https://player.test/3.mp4',
                    title: 'Show.S01E03.mkv',
                  ),
                  const PlaylistEntry(
                    url: 'https://player.test/2.mp4',
                    title: 'Show.S01E02.mkv',
                  ),
                ];
              }
              return [
                PlaylistEntry(
                  url: 'https://player.test/2.mp4',
                  title: result == 'wrong singleton'
                      ? 'Show.S01E03.mkv'
                      : 'Undetected',
                ),
              ];
            },
          ),
        );
        final b = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 2))
              as Future<dynamic>,
        );
        expect(resolved, 1);
        final success = [
          'unparseable singleton',
          'pack match',
        ].contains(result);
        expect(d.opens.length, success ? 2 : 1);
        if (success) {
          expect(d.opens.last.uri, 'https://player.test/2.mp4');
          final sheet = await d.sourceSheet();
          expect(sheet.currentSourceIndex, 0);
        }
        expect(d.logs.any((v) => v.contains('next_episode_candidate')), isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
  for (final boundary in ['allow', 'fetch', 'resolver']) {
    testWidgets(
      'P17 fetch latch stays held at $boundary while a newer guide request is rejected',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final gate = Completer<void>();
        var entered = false;
        var searches = 0;
        final candidate = episodeSource('Show.S01E02');
        Future<void> hold(String site) async {
          if (boundary == site && !entered) {
            entered = true;
            await gate.future;
          }
        }

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
                searchEpisodes: (s, e) async {
                  searches++;
                  await hold('fetch');
                  return [candidate];
                },
                searchPacks: (s, e) async => [],
                validateCandidate: (s) async {
                  await hold('allow');
                  return true;
                },
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async {
                await hold('resolver');
                return [
                  PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
                ];
              },
            ),
          );
          final b = await d.browser();
          final old =
              d.observe<dynamic>(() => b.onEpisodeSelected(1, 2))
                  as Future<dynamic>;
          await d.f.until(t, () => entered);
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => b.onEpisodeSelected(1, 3))
                as Future<dynamic>,
          );
          expect(searches, 1);
          expect(d.opens, hasLength(1));
          gate.complete();
          await d.f.finish(t, old);
          // A request declined by the boolean latch does not bump navigation.
          expect(d.opens.last.uri, candidate.directUrl);
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          await d.close();
        }
      },
    );
  }
  for (final mode in ['existing', 'episodes', 'packs']) {
    testWidgets('P17 $mode candidate attempt cap and external filtering', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final allowed = <String>[];
      final sources = [
        episodeSource('External.S01E02', type: StreamType.externalUrl),
        for (var i = 0; i < 8; i++)
          episodeSource(
            'Candidate$i.S01E02',
            type: mode == 'episodes'
                ? StreamType.directUrl
                : StreamType.torrent,
            coverage: mode == 'existing' ? 'seasonPack' : null,
            season: 1,
          ),
      ];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: mode == 'existing'
                ? [episodeSource('Original.S01E01'), ...sources]
                : null,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchEpisodes: (s, e) async => mode == 'episodes' ? sources : [],
              searchPacks: (s, e) async => mode == 'packs' ? sources : [],
              validateCandidate: (s) async {
                allowed.add(s.name);
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
          d.observe<dynamic>(() => b.onEpisodeSelected(1, 2))
              as Future<dynamic>,
        );
        expect(
          allowed,
          hasLength({'existing': 4, 'episodes': 5, 'packs': 3}[mode]!),
        );
        expect(allowed.any((s) => s.startsWith('External')), isFalse);
        expect(d.opens, hasLength(1));
      } finally {
        await d.close();
      }
    });
  }
  testWidgets(
    'P17 stale pinned yield after disposal cannot merge or show preferred-missing feedback',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final stream = StreamController<Torrent>.broadcast();
      void Function()? missing;
      var listened = false;
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
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              pinnedDirectCandidates: (s, e, {onPreferredMissing}) {
                listened = true;
                missing = onPreferredMissing;
                return stream.stream;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        final b = await d.browser();
        final action =
            d.observe<dynamic>(() => b.onEpisodeSelected(1, 2))
                as Future<dynamic>;
        await d.f.until(t, () => listened);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        d.observe(() => missing!());
        stream.add(episodeSource('Show.S01E02'));
        await d.f.finish(t, action);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.f.finish(t, stream.close());
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 current pinned preferred-missing callback queues its exact feedback before fallback',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final stream = StreamController<Torrent>.broadcast();
      void Function()? missing;
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
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              pinnedDirectCandidates: (s, e, {onPreferredMissing}) {
                missing = onPreferredMissing;
                return stream.stream;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        final b = await d.browser();
        final Future<dynamic> task = d.observe<dynamic>(
          () => b.onEpisodeSelected(1, 2),
        );
        await d.f.until(t, () => missing != null);
        d.observe(() => missing!());
        await waitSleepToast(
          t,
          d.f,
          'Your previous source is unavailable for this episode. Trying other sources.',
        );
        expect(
          find.text(
            'Your previous source is unavailable for this episode. Trying other sources.',
          ),
          findsOneWidget,
        );
        await d.f.finish(t, stream.close());
        await d.f.finish(t, task);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.f.finish(t, stream.close());
        await d.close();
      }
    },
  );
}
