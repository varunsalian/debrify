import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 guide fetch generation cannot resurrect older shuffle after an ordinary playlist action',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final inventory = Completer<List<Map<String, dynamic>>>();
      var armed = false;
      var reads = 0;
      final calls = <(String, int, int)>[];
      final candidate = episodeSource('Show.S01E03');
      final delivered = CompletionDelivery('playRandomOnce', (v) => v == true);
      const initial = [
        {'season': 1, 'number': 1, 'airdate': '2020-01-01'},
        {'season': 1, 'number': 2, 'airdate': '2020-01-02'},
        {'season': 1, 'number': 3, 'airdate': '2020-01-03'},
        {'season': 1, 'number': 4, 'airdate': '2020-01-04'},
      ];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: const [
              PlaylistEntry(
                url: 'https://player.test/a.mp4',
                title: 'Show.S01E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/b.mp4',
                title: 'Show.S01E02.mkv',
              ),
            ],
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              loadCustomEpisodeInventory: () async {
                if (armed && reads == 0) {
                  reads++;
                  return inventory.future;
                }
                return initial;
              },
              searchEpisodes: (s, e) async {
                calls.add(('episodes', s, e));
                return e == 3 ? [candidate] : [];
              },
              searchPacks: (s, e) async {
                calls.add(('packs', s, e));
                return [];
              },
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final browser = await d.browser();
        await d.f.finish(t, browser.metadataReady!);
        d.f.navigator.currentState!.pop();
        await d.f.advance(t, const Duration(milliseconds: 400));
        armed = true;
        playerControls(t).onRandom();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        d.observe(() => delivered.run(menu.onShuffleOnce));
        await d.f.until(t, () => reads == 1);
        expect(inventory.isCompleted, isFalse);
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => browser.onEpisodeSelected(1, 4)),
        );
        expect(calls, [('episodes', 1, 4), ('packs', 1, 4)]);
        expect(d.opens, hasLength(1));
        await d.f.finish<dynamic>(
          t,
          d.observe<dynamic>(() => browser.onEpisodeSelected(1, 2)),
        );
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        inventory.complete([initial[2]]);
        await d.f.until(t, () => delivered.pending.isNotEmpty);
        expect(delivered.values, [true]);
        expect(calls, [('episodes', 1, 4), ('packs', 1, 4)]);
        expect(d.opens, hasLength(2));
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        expect(d.errors, isEmpty);
        delivered.release();
        await d.f.actions.settle(t);
      } finally {
        if (!inventory.isCompleted) inventory.complete([]);
        delivered.release();
        await d.close();
      }
    },
  );
}
