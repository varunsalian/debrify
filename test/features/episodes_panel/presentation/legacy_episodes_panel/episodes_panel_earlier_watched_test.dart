// "Mark earlier episodes watched" in the episode options sheet: the tile
// appears only when the episode has aired predecessors, confirming marks
// them (local ticks re-read from storage), cancelling marks nothing.
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

const tileLabel = 'Mark earlier episodes watched';
const confirmTitle = 'Mark earlier episodes watched?';

/// Season 1 with three aired episodes: E3 has two predecessors, E1 has none.
List<Map<String, Object?>> threeEpisodeSeason(String id) => [
  for (final number in [1, 2, 3])
    {
      'id': '$id:1:$number',
      'season': 1,
      'episode': number,
      'title': 'Episode 1.$number',
      'overview': 'An original episode.',
      'released': '2026-01-01T00:00:00Z',
      'imdbRating': 7.5,
    },
];

Future<void> openEarlierSheet(
  WidgetTester t,
  EpisodesPanelFixture f, {
  required String title,
}) async {
  // Close a sheet left open by an earlier step of the same test.
  if (find.text('Play').evaluate().isNotEmpty) {
    f.navigator.currentState!.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }
  f.view.options(f.view.episodes.firstWhere((e) => e.title == title));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  expect(find.text('Play'), findsOneWidget);
}

Future<void> waitForText(WidgetTester t, String text) async {
  for (var i = 0; i < 200 && find.text(text).evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(
    find.text(text),
    findsOneWidget,
    reason: 'never saw "$text"; onscreen: ${dump(t)}',
  );
}

String dump(WidgetTester t) => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .where((s) => s != null && s.isNotEmpty)
    .join(' | ');

void main() {
  testWidgets(
    'tile appears on S1E3 with two predecessors and is absent on S1E1',
    (t) async {
      await episodesPanelCase(t, 'earlier-tile', 70, (f) async {
        f.videosOverride = threeEpisodeSeason(f.id);
        f.progressLoader = () async => {};
        await f.mount(t);
        expect(f.view.episodes.map((e) => '${e.season}-${e.number}'), [
          '1-1',
          '1-2',
          '1-3',
        ]);
        // S1E1: nothing earlier — no tile.
        f.view.options(f.view.episodes.first);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Play'), findsOneWidget);
        expect(find.text(tileLabel), findsNothing);
        // S1E3: two aired episodes earlier — the tile names them.
        await openEarlierSheet(t, f, title: 'Episode 1.3');
        expect(find.text(tileLabel), findsOneWidget);
        expect(find.text('2 episodes before this one'), findsOneWidget);
      });
    },
  );

  testWidgets('confirming marks every earlier episode', (t) async {
    await episodesPanelCase(t, 'earlier-confirm', 71, (f) async {
      f.videosOverride = threeEpisodeSeason(f.id);
      final map = <String, double>{};
      f.progressLoader = () async => map;
      await f.authenticate({TrackingSource.trakt});
      await f.mount(t);
      expect(f.view.episodes, hasLength(3));
      f.requests.clear();
      await openEarlierSheet(t, f, title: 'Episode 1.3');
      await t.tap(find.widgetWithText(ListTile, tileLabel));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(confirmTitle), findsOneWidget);
      await t.tap(find.text('Mark watched'));
      await waitForText(t, 'Marked 2 episodes watched');
      await t.runAsync(() async {
        for (final number in [1, 2]) {
          expect(
            await EpisodeProgressStorage.isEpisodeFinished(
              seriesTitle: f.show.name,
              season: 1,
              episode: number,
              imdbId: f.id,
            ),
            isTrue,
            reason: 'S1E$number was not marked finished',
          );
        }
        expect(
          await EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: f.show.name,
            season: 1,
            episode: 3,
            imdbId: f.id,
          ),
          isFalse,
        );
      });
    });
  });

  testWidgets('cancelling marks nothing', (t) async {
    await episodesPanelCase(t, 'earlier-cancel', 72, (f) async {
      f.videosOverride = threeEpisodeSeason(f.id);
      final map = <String, double>{};
      f.progressLoader = () async => map;
      await f.authenticate({TrackingSource.trakt});
      await f.mount(t);
      f.requests.clear();
      await openEarlierSheet(t, f, title: 'Episode 1.3');
      await t.tap(find.widgetWithText(ListTile, tileLabel));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(confirmTitle), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(confirmTitle), findsNothing);
      expect(f.requests, isEmpty);
      expect(map, isEmpty);
      await t.runAsync(() async {
        expect(
          await EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: f.show.name,
            season: 1,
            episode: 1,
            imdbId: f.id,
          ),
          isFalse,
        );
      });
    });
  });
}
