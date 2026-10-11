import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identity_fixture.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
      'identity search filters and labels results then ${cancel ? 'cancels' : 'validates and accepts'} the season episode',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        await installIdentityCatalog(tester, fixture);
        try {
          await fixture.mount(
            tester,
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/unknown.mp4',
              title: 'Unknown file',
            ),
          );
          final menu = await openPlayerMenu(tester, fixture);
          final result = menu.onIdentifyTitle!();
          await fixture.until(
            tester,
            () => find.text('Fixture Series').evaluate().isNotEmpty,
            reason: 'Original search must render catalog results',
          );
          expect(find.text('Sparse duplicate'), findsNothing);
          expect(find.text('Unsupported TV'), findsNothing);
          expect(find.text('No IMDb'), findsNothing);
          expect(find.text('Series | 2024 | Fixture search'), findsOneWidget);
          expect(find.text('Movie | 2020 | Fixture search'), findsOneWidget);
          final posters = tester
              .widgetList<Image>(find.byType(Image))
              .map((image) => image.image)
              .whereType<NetworkImage>();
          expect(
            posters.map((image) => image.url),
            contains('https://player.test/poster.png'),
          );
          await tester.tap(find.text('Fixture Series'));
          await fixture.advance(tester, const Duration(milliseconds: 350));
          expect(find.text('Which episode?'), findsOneWidget);
          if (cancel) {
            await tester.tap(find.text('Cancel'));
            expect(await fixture.finish(tester, result), isNull);
            await fixture.advance(tester, const Duration(milliseconds: 300));
            expect(
              tester
                  .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
                  .contentImdbId,
              isNull,
            );
          } else {
            await tester.tap(find.text('Apply'));
            await fixture.advance(tester);
            expect(
              find.text('Enter a valid season and episode.'),
              findsOneWidget,
            );
            final seasonField = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Season',
            );
            final episodeField = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Episode',
            );
            await tester.enterText(seasonField, '0');
            await tester.enterText(episodeField, '-2');
            await tester.tap(find.text('Apply'));
            await fixture.advance(tester);
            expect(find.text('Which episode?'), findsOneWidget);
            await tester.enterText(seasonField, ' 3 ');
            await tester.enterText(episodeField, ' 7 ');
            await tester.tap(find.text('Apply'));
            final accepted = await fixture.finish(tester, result);
            expect(accepted, isNotNull);
            expect(accepted!.imdbId, 'tt900001');
            expect(accepted.contentType, 'series');
            expect(accepted.season, 3);
            expect(accepted.episode, 7);
            expect(
              accepted.identityLabel,
              'Subtitles for Fixture Series (2024) S3E7',
            );
            await fixture.advance(tester, const Duration(milliseconds: 300));
            final updated = tester.widget<PlayerMenuPanel>(
              find.byType(PlayerMenuPanel),
            );
            expect(
              updated.subtitleIdentityLabel,
              'Subtitles for Fixture Series (2024) S3E7',
            );
          }
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
}
