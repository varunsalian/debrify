import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 synthetic cache survives a completed close and fresh sheet',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S02E03.mkv',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
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
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        await d.f.until(t, () => find.byType(SeriesBrowser).evaluate().isEmpty);
        final again = await d.browser();
        expect(identical(again, first), isFalse);
        expect(
          identical(again.onEpisodeSelected, first.onEpisodeSelected),
          isFalse,
        );
        expect(identical(again.seriesPlaylist, first.seriesPlaylist), isTrue);
        expect(identical(again.metadataReady, first.metadataReady), isTrue);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets('P17 synthetic guide stamps a parsed episode lacking a season', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'Example Episode 3',
          contentType: 'series',
          contentSeason: 2,
          contentEpisode: 3,
          seriesSourceFetcher: SeriesSourceFetcher(
            season: 2,
            episode: 3,
            searchEpisodes: (s, e) async => [],
            searchPacks: (s, e) async => [],
          ),
          resolveSourceToPlaylist: (s, {canContinue}) async => [],
        ),
      );
      final browser = await d.browser();
      expect(
        browser.seriesPlaylist.allEpisodes.single.filename,
        'S02E03 Example Episode 3',
      );
      expect(browser.seriesPlaylist.findOriginalIndexBySeasonEpisode(2, 3), 0);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });
  for (final bounds in [(null, 2, 1, true), (3, null, 2, false)]) {
    testWidgets('P17 complete-series lower bound $bounds through guide fetch', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var validations = 0;
      final pack = episodeSource(
        'Pack',
        type: StreamType.torrent,
        coverage: 'completeSeries',
        start: bounds.$1,
        end: bounds.$2,
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [episodeSource('Original.S01E01'), pack],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchEpisodes: (s, e) async => [],
              searchPacks: (s, e) async => [],
              validateCandidate: (s) async {
                validations++;
                return false;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        validations = 0;
        final browser = await d.browser();
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => browser.onEpisodeSelected(bounds.$3, 2)),
        );
        expect(validations, bounds.$4 ? 1 : 0);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
  for (final mode in [
    'fetch ladder counters',
    'existing candidate filtering',
  ]) {
    testWidgets(
      'P17 $mode keeps stage budgets and exact matching independent',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final allowed = <String>[];
        final searches = <String>[];
        final original = episodeSource('Original.S01E01');
        final existing = mode == 'fetch ladder counters'
            ? [for (var i = 0; i < 7; i++) episodeSource('Existing$i.S01E02')]
            : [
                episodeSource('WrongSeason.S02E02'),
                episodeSource('WrongEpisode.S01E03'),
                episodeSource('DirectPack', coverage: 'seasonPack', season: 1),
                episodeSource('Good.S01E02'),
                episodeSource(
                  'TorrentPack',
                  type: StreamType.torrent,
                  coverage: 'seasonPack',
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
              stremioSources: [original, ...existing],
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                searchEpisodes: (s, e) async {
                  searches.add('episodes');
                  return mode == 'fetch ladder counters'
                      ? [
                          for (var i = 0; i < 7; i++)
                            episodeSource('Fetched$i.S01E02'),
                        ]
                      : [];
                },
                searchPacks: (s, e) async {
                  searches.add('packs');
                  return mode == 'fetch ladder counters'
                      ? [
                          for (var i = 0; i < 7; i++)
                            episodeSource('Pack$i', type: StreamType.torrent),
                        ]
                      : [];
                },
                validateCandidate: (source) async {
                  allowed.add(source.displayTitle);
                  return false;
                },
              ),
              resolveSourceToPlaylist: (source, {canContinue}) async => [],
            ),
          );
          allowed.clear();
          searches.clear();
          final browser = await d.browser();
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => browser.onEpisodeSelected(1, 2)),
          );
          expect(searches, ['episodes', 'packs']);
          expect(
            allowed,
            mode == 'fetch ladder counters'
                ? [
                    for (var i = 0; i < 4; i++) 'Existing$i.S01E02.mkv',
                    for (var i = 0; i < 5; i++) 'Fetched$i.S01E02.mkv',
                    for (var i = 0; i < 3; i++) 'Pack$i',
                  ]
                : ['Good.S01E02.mkv', 'TorrentPack'],
          );
          expect(d.opens, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
