import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets('horizontal seek HUD formats original target and signed delta', (
    tester,
  ) async {
    final fixture = VideoPlayerEnvironment();
    await tester.runAsync(fixture.initialize);
    try {
      await fixture.mount(
        tester,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/seek-hud.mp4',
          title: 'Seek HUD',
        ),
      );
      fixture.player.publishFrame(duration: const Duration(hours: 2));
      await fixture.advance(tester);
      final gesture = tester
          .widgetList<GestureDetector>(find.byType(GestureDetector))
          .singleWhere((widget) => widget.onPanStart != null);
      for (final (base, dx, target, text) in [
        (123, 320.0, 153, '02:33  (+00:30)'),
        (3723, 320.0, 3753, '01:02:33  (+00:30)'),
        (123, -320.0, 93, '01:33  (--00:30)'),
      ]) {
        await fixture.player.seek(Duration(seconds: base));
        await fixture.advance(tester);
        gesture.onPanStart!(
          DragStartDetails(localPosition: const Offset(640, 400)),
        );
        await fixture.advance(tester);
        gesture.onPanUpdate!(
          DragUpdateDetails(
            delta: Offset(dx, 0),
            globalPosition: Offset(640 + dx, 400),
            localPosition: Offset(640 + dx, 400),
          ),
        );
        await fixture.advance(tester, const Duration(milliseconds: 150));
        expect(find.byType(SeekHud), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        gesture.onPanEnd!(DragEndDetails());
        await fixture.advance(tester, const Duration(milliseconds: 300));
        expect(fixture.player.state.position, Duration(seconds: target));
        expect(find.byType(SeekHud), findsNothing);
      }
    } finally {
      await fixture.close(tester);
    }
  });
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
  for (final (season, episodeNumber, expectedFilename) in [
    (3, 7, 'S03E07 Plain title'),
    (12, 34, 'S12E34 Plain title'),
  ]) {
    testWidgets(
      season == 3
          ? 'original controls render duration and synthetic guide stamps padded episode identity'
          : 'synthetic guide preserves two-digit season and episode',
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
              contentSeason: season,
              contentEpisode: episodeNumber,
              seriesSourceFetcher: SeriesSourceFetcher(
                searchPacks: (s, e) async => [],
                searchEpisodes: (s, e) async => [],
                season: season,
                episode: episodeNumber,
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
          expect(episode.filename, expectedFilename);
          expect(episode.seriesInfo.season, season);
          expect(episode.seriesInfo.episode, episodeNumber);
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
}
