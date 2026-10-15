import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/movie_collection_browser.dart';

import 'support/menu_metadata_driver.dart';
import 'support/player_actions.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

void main() {
  for (final success in [false, true]) {
    for (final event in ['none', 'profile', 'content', 'dispose', 'repeated']) {
      testWidgets(
        'p13 live tracks metadata success=$success event=$event preserves original snapshots',
        (t) async {
          final d = MenuMetadataDriver(t);
          await d.setup();
          try {
            await d.mountMovies();
            final before = d.pending.length;
            d.tracks();
            await d.f.until(t, () => d.pending.length > before);
            expect(
              find.byType(PlayerMenuPanel),
              findsNothing,
              reason: 'tracks awaits live movie metadata',
            );
            if (event == 'repeated') {
              d.tracks();
              await d.f.until(t, () => d.pending.length > before + 1);
            }
            if (event == 'profile') await incomingProfile(t, d.f);
            if (event == 'content') {
              playerControls(t).onShowPlaylist();
              await d.f.until(
                t,
                () => find.byType(MovieCollectionBrowser).evaluate().isNotEmpty,
              );
              final browser = t.widget<MovieCollectionBrowser>(
                find.byType(MovieCollectionBrowser),
              );
              d.observe(() => browser.onSelectIndex(1));
              d.f.navigator.currentState!.pop();
              await d.f.until(
                t,
                () => d.player.calls.where((c) => c.$1 == 'open').length >= 2,
              );
              await d.f.advance(t, const Duration(milliseconds: 350));
            }
            if (event == 'dispose') {
              await t.pumpWidget(const SizedBox());
              await d.f.until(t, () => d.player.disposed.isCompleted);
            }
            d.release(success: success);
            if (event == 'dispose') {
              await d.f.actions.settle(t);
              expect(find.byType(PlayerMenuPanel), findsNothing);
            } else {
              await d.shown();
              expect(d.panel.initialSection, PlayerMenuSection.subtitles);
              expect(d.panel.contentImdbId, success ? 'tt1300001' : null);
              expect(d.panel.contentType, success ? 'movie' : null);
              expect(d.panel.contentSeason, isNull);
              expect(d.panel.contentEpisode, isNull);
              if (event == 'content') {
                expect(
                  d.player.calls.where((c) => c.$1 == 'open').length,
                  greaterThanOrEqualTo(2),
                );
              }
            }
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  }
  for (final section in [
    PlayerMenuSection.sleep,
    PlayerMenuSection.speed,
    PlayerMenuSection.aspect,
    PlayerMenuSection.shuffle,
  ]) {
    testWidgets(
      'p13 quick $section opens without awaiting or fetching metadata',
      (t) async {
        final d = MenuMetadataDriver(t);
        await d.setup();
        try {
          await d.mountMovies();
          final searches = d.searches.length;
          final controls = playerControls(t);
          switch (section) {
            case PlayerMenuSection.sleep:
              controls.onSleepTimer();
            case PlayerMenuSection.speed:
              controls.onSpeed();
            case PlayerMenuSection.aspect:
              controls.onAspect();
            case PlayerMenuSection.shuffle:
              controls.onRandom();
            default:
              throw StateError('unexpected test section');
          }
          await d.shown();
          expect(d.panel.initialSection, section);
          expect(d.panel.audioPassthrough, isNull);
          expect(d.panel.onAudioPassthroughChanged, isNull);
          expect(d.panel.contentImdbId, isNull);
          expect(d.searches, hasLength(searches));
          d.panel.onClose();
          await d.f.advance(t, const Duration(milliseconds: 350));
          expect(find.byType(PlayerMenuPanel), findsNothing);
          d.release();
          await d.f.actions.settle(t);
          expect(
            find.byType(PlayerMenuPanel),
            findsNothing,
            reason: 'metadata completion alone never reopens a quick menu',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
