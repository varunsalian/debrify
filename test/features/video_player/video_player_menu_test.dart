import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets('active random menu dispatches once and continuous choices', (
    tester,
  ) async {
    final fixture = VideoPlayerEnvironment();
    await tester.runAsync(fixture.initialize);
    try {
      await fixture.mount(
        tester,
        VideoPlayerScreen(
          videoUrl: 'https://player.test/one.mp4',
          title: 'Choice',
          playlist: [
            for (final n in [1, 2])
              PlaylistEntry(
                url: 'https://player.test/${n == 1 ? 'one' : 'two'}.mp4',
                title: 'Choice $n',
              ),
          ],
        ),
      );
      playerControls(tester).onRandom();
      await fixture.advance(tester);
      await fixture.advance(tester, const Duration(milliseconds: 300));
      expect(find.text('Play random once'), findsOneWidget);
      expect(find.text('Continuous shuffle'), findsOneWidget);
      await tester.tap(find.text('Continuous shuffle'));
      await fixture.until(
        tester,
        () => fixture.player.calls.where((c) => c.$1 == 'open').length >= 2,
      );
      playerControls(tester).onRandom();
      await fixture.advance(tester);
      await fixture.advance(tester, const Duration(milliseconds: 300));
      expect(
        tester
            .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
            .continuousShuffle,
        isTrue,
      );
      await tester.tap(find.text('Play random once'));
      await fixture.until(
        tester,
        () => fixture.player.calls.where((c) => c.$1 == 'open').length >= 3,
      );
      playerControls(tester).onRandom();
      await fixture.advance(tester);
      await fixture.advance(tester, const Duration(milliseconds: 300));
      expect(
        tester
            .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
            .continuousShuffle,
        isFalse,
      );
    } finally {
      await fixture.close(tester);
    }
  });
  testWidgets(
    'original controls render duration and synthetic guide stamps padded episode identity',
    (tester) async {
      final fixture = VideoPlayerEnvironment();
      await tester.runAsync(fixture.initialize);
      try {
        await fixture.mount(
          tester,
          VideoPlayerScreen(
            videoUrl: 'https://player.test/plain.mp4',
            title: 'Plain title',
            contentType: 'series',
            contentSeason: 3,
            contentEpisode: 7,
            seriesSourceFetcher: SeriesSourceFetcher(
              searchPacks: (s, e) async => [],
              searchEpisodes: (s, e) async => [],
              season: 3,
              episode: 7,
            ),
            resolveSourceToPlaylist: (source, {canContinue}) async => [],
          ),
        );
        await fixture.player.seek(const Duration(minutes: 2, seconds: 3));
        await fixture.advance(tester);
        expect(find.text('02:03'), findsOneWidget);
        expect(find.text('20:00'), findsOneWidget);
        playerControls(tester).onShowPlaylist();
        await fixture.until(
          tester,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = tester.widget<SeriesBrowser>(
          find.byType(SeriesBrowser),
        );
        final episode = browser.seriesPlaylist.allEpisodes.single;
        expect(episode.filename, 'S03E07 Plain title');
        expect(episode.seriesInfo.season, 3);
        expect(episode.seriesInfo.episode, 7);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
