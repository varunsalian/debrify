import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';
import 'support/sleep_timer_driver.dart' show waitSleepToast;

void main() {
  testWidgets(
    'P17 candidate validator failure remains eligible and releases the fetch latch for the next guide action',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var validations = 0;
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
              searchEpisodes: (s, e) async => [episodeSource('Show.S01E0$e')],
              searchPacks: (s, e) async => [],
              validateCandidate: (source) async {
                if (++validations == 1) {
                  throw StateError('synthetic validator failure');
                }
                return true;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final b = await d.browser();
        final Future<dynamic> first = b.onEpisodeSelected(1, 2);
        await d.f.finish(t, first);
        expect(d.opens.last.uri, 'https://player.test/Show.S01E02.mp4');
        final Future<dynamic> second = b.onEpisodeSelected(1, 3);
        await d.f.finish(t, second);
        expect(validations, 2);
        expect(d.opens.last.uri, 'https://player.test/Show.S01E03.mp4');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 escaping pinned-stream failure releases the fetch latch for the next guide action',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var requests = 0;
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
              pinnedDirectCandidates: (s, e, {onPreferredMissing}) async* {
                if (++requests == 1) {
                  throw StateError('synthetic pinned stream failure');
                }
              },
              searchEpisodes: (s, e) async => [episodeSource('Show.S01E0$e')],
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final b = await d.browser();
        final Future<dynamic> first = b.onEpisodeSelected(1, 2);
        await expectLater(d.f.finish(t, first), throwsA(isA<StateError>()));
        expect(d.opens, hasLength(1));
        final Future<dynamic> second = b.onEpisodeSelected(1, 3);
        await d.f.finish(t, second);
        expect(requests, 2);
        expect(d.opens.last.uri, 'https://player.test/Show.S01E03.mp4');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final throwing in ['episodes', 'packs']) {
    testWidgets(
      'P17 $throwing search exception is unavailable and preserves the ladder order',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final calls = <String>[];
        final pack = episodeSource('Pack', type: StreamType.torrent);
        var resolutions = 0;
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
                  calls.add('episodes');
                  if (throwing == 'episodes') {
                    throw StateError('episode search failed');
                  }
                  return [];
                },
                searchPacks: (s, e) async {
                  calls.add('packs');
                  if (throwing == 'packs') {
                    throw StateError('pack search failed');
                  }
                  return [pack];
                },
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async {
                resolutions++;
                return [PlaylistEntry(url: s.directUrl!, title: 'Unparseable')];
              },
            ),
          );
          final b = await d.browser();
          final Future<dynamic> action = b.onEpisodeSelected(1, 2);
          await d.f.finish(t, action);
          expect(calls, ['episodes', 'packs']);
          if (throwing == 'episodes') {
            expect(d.opens.last.uri, pack.directUrl);
            expect(resolutions, 1);
          } else {
            expect(d.opens, hasLength(1));
            expect(resolutions, 0);
            await waitSleepToast(t, d.f, 'No playable source found for S01E02');
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
