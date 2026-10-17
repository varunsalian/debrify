import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/widgets/movie_collection_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final supplied in [false, true]) {
    testWidgets(
      'P17 synthetic collection title uses supplied=$supplied and preserves launch IMDb before publication',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Orchid Voyage',
              contentTitle: supplied ? 'Catalogue' : null,
              contentType: 'series',
              contentSeason: 2,
              contentEpisode: 3,
              contentImdbId: 'tt1717171',
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
            browser.seriesPlaylist.seriesTitle,
            supplied ? 'Catalogue' : 'Orchid Voyage',
          );
          expect(browser.seriesPlaylist.imdbId, 'tt1717171');
          expect(browser.imdbId, 'tt1717171');
          expect(browser.showAllEpisodes, isTrue);
          expect(browser.metadataReady, isNotNull);
          expect(
            browser.seriesPlaylist.allEpisodes.single.filename,
            'S02E03 Orchid Voyage',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 ordinary series sheet disables fetching and selects the real playlist index with manual policy',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/a.mp4',
                title: 'Show.S01E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/b.mp4',
                title: 'Show.S01E02.mkv',
              ),
            ],
          ),
        );
        final browser = await d.browser();
        expect(browser.showAllEpisodes, isFalse);
        expect(browser.metadataReady, isNotNull);
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => browser.onEpisodeSelected(1, 2)),
        );
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        expect(d.openAutoplay.last, isTrue);
        expect(
          d.timers.where(
            (v) =>
                v.stack.contains('setManualSelectionMode') &&
                v.stack.contains('showPlaylistSheet') &&
                v.timer.isActive,
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 movie sheet selects its original index without series metadata requests',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Movies',
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/a.mp4',
                title: 'Movie One.2020.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/b.mp4',
                title: 'Movie Two.2021.mkv',
              ),
            ],
          ),
        );
        final before = d.f.network.requests.length;
        playerControls(t).onShowPlaylist();
        await d.f.until(
          t,
          () => find.byType(MovieCollectionBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<MovieCollectionBrowser>(
          find.byType(MovieCollectionBrowser),
        );
        expect(browser.currentIndex, 0);
        expect(
          d.f.network.requests
              .skip(before)
              .where((r) => r.url.path.contains('/episodes')),
          isEmpty,
        );
        final dynamic select = browser.onSelectIndex;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => select(1)));
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        expect(d.openAutoplay.last, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
