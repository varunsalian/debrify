import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 default automatic fetch request rejects sleep expiry during the fetch await',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final response = Completer<List<Torrent>?>();
      var entered = false;
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
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 2),
              searchPacks: (s, e) async => [],
              searchEpisodes: (s, e) {
                entered = true;
                return response.future;
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async {
              resolutions++;
              return [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];
            },
          ),
        );
        d.player.emit('completed', true);
        await d.f.until(t, () => entered);
        await pickSleep(
          t,
          d.f,
          const SleepTimerSelection(SleepTimerMode.countdown),
        );
        await waitSleepToast(t, d.f, 'Sleep timer ended — paused');
        response.complete([episodeSource('Show.S01E02')]);
        await d.f.actions.settle(t);
        expect(resolutions, 0);
        expect(d.opens, hasLength(1));
        expect(d.player.state.playing, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!response.isCompleted) {
          response.complete([]);
        }
        await d.close();
      }
    },
  );
  for (final route in ['guide', 'EOF', 'shuffle']) {
    testWidgets(
      'P17 fetched $route ${route == 'guide' ? 'restores' : 'suppresses'} the saved incoming episode point',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final incoming = episodeSource('Show.S01E02');
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S01E01.mkv',
              contentImdbId: 'tt1700020',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                resolveAdjacentEpisode: (s, e, direction) async =>
                    (season: 1, episode: 2),
                loadCustomEpisodeInventory: () async => [
                  {'season': 1, 'number': 1, 'airdate': '2020-01-01'},
                  {'season': 1, 'number': 2, 'airdate': '2020-01-02'},
                ],
                searchPacks: (s, e) async => [],
                searchEpisodes: (s, e) async => [incoming],
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
              ],
            ),
          );
          final b = await d.browser();
          await d.f.finish(
            t,
            SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: b.seriesPlaylist.seriesTitle!,
              imdbId: b.seriesPlaylist.imdbId,
              season: 1,
              episode: 2,
              positionMs: 240000,
              durationMs: 1200000,
            ),
          );
          d.f.navigator.currentState!.pop();
          await d.f.advance(t, const Duration(milliseconds: 400));
          final before = d.seeks.length;
          if (route == 'guide') {
            await d.f.finish<dynamic>(
              t,
              d.observe<dynamic>(() => b.onEpisodeSelected(1, 2)),
            );
          } else if (route == 'EOF') {
            d.player.emit('completed', true);
            await d.f.until(t, () => d.opens.length == 2);
          } else {
            playerControls(t).onRandom();
            await d.f.advance(t, const Duration(milliseconds: 350));
            d.observe(
              t
                  .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
                  .onShuffleOnce,
            );
            await d.f.until(t, () => d.opens.length == 2);
          }
          await d.f.actions.settle(t);
          await d.f.advance(t, const Duration(seconds: 1));
          expect(d.opens.last.uri, incoming.directUrl);
          if (route == 'guide') {
            expect(d.seeks.skip(before), contains(const Duration(minutes: 4)));
          } else {
            expect(d.seeks.skip(before), isEmpty);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
