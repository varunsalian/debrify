import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/menu_metadata_driver.dart';
import 'support/player_actions.dart';

void main() {
  for (final success in [false, true]) {
    for (final event in ['none', 'repeated', 'dispose']) {
      testWidgets(
        'p13 single-file tracks after handoff success=$success event=$event preserves lookup timing',
        (t) async {
          final d = MenuMetadataDriver(t);
          await d.setup();
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/initial.mp4',
                title: 'Initial title without a year',
                disableAutoResume: true,
                requestMagicNext: () async => {
                  'url': 'https://player.test/changed.mp4',
                  'title': 'Menu.Movie.2024.mkv',
                  'provider': 'fixture',
                },
              ),
            );
            expect(d.searches, isEmpty);
            d.observe(() => playerControls(t).onNext!());
            await d.f.until(
              t,
              () => d.player.calls.where((c) => c.$1 == 'open').length == 2,
            );
            await d.f.actions.settle(t);
            d.player.publishFrame();
            await d.f.advance(t, const Duration(milliseconds: 350));
            expect(
              d.searches,
              isEmpty,
              reason: 'handoff does not preload single-file metadata',
            );
            d.tracks();
            await d.f.until(t, () => d.pending.isNotEmpty);
            expect(find.byType(PlayerMenuPanel), findsNothing);
            final requests = d.searches.length;
            if (event == 'repeated') {
              d.tracks();
              playerControls(t).onSpeed();
              await d.shown();
              expect(d.panel.initialSection, PlayerMenuSection.speed);
              expect(d.panel.contentImdbId, isNull);
              expect(
                d.searches,
                hasLength(requests),
                reason: 'the first request already set the fetch latch',
              );
            }
            if (event == 'dispose') {
              await t.pumpWidget(const SizedBox());
              await d.f.until(t, () => d.player.disposed.isCompleted);
            }
            d.release(success: success);
            await d.f.actions.settle(t);
            if (event == 'dispose') {
              expect(find.byType(PlayerMenuPanel), findsNothing);
            } else {
              await d.f.until(
                t,
                () =>
                    find.byType(PlayerMenuPanel).evaluate().isNotEmpty &&
                    d.panel.contentImdbId == (success ? 'tt1300001' : null),
              );
              expect(d.panel.initialSection, PlayerMenuSection.subtitles);
              expect(d.panel.contentType, success ? 'movie' : null);
              expect(d.panel.contentSeason, isNull);
              expect(d.panel.contentEpisode, isNull);
              expect(d.searches, hasLength(requests));
            }
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  }
}
