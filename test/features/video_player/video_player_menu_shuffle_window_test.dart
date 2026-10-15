import 'dart:async';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/subtitle_apply_driver.dart';

void main() {
  testWidgets(
    'p13 shuffle once closes its menu before custom episode inventory completes',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final inventory = Completer<List<Map<String, dynamic>>>();
      var inventoryReads = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/only.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              searchPacks: (season, episode) async => [],
              searchEpisodes: (season, episode) async => [],
              loadCustomEpisodeInventory: () {
                inventoryReads++;
                return inventory.future;
              },
            ),
            resolveSourceToPlaylist: (source, {canContinue}) async => [],
          ),
        );
        playerControls(t).onRandom();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        expect(menu.hasPlaylist, isTrue);
        d.observe(menu.onShuffleOnce);
        await d.f.until(t, () => inventoryReads == 1);
        await d.f.advance(t);
        expect(inventory.isCompleted, isFalse);
        expect(find.byType(PlayerMenuPanel), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        if (!inventory.isCompleted) inventory.complete([]);
        await d.close();
      }
    },
  );
}
