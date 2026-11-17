import 'dart:async';

import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/widgets/episode_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

/// The standalone episode list (Classic detail → Episodes) keeps itself under
/// Sources and playback, so Back returns to the same season and the list
/// re-reads progress when it is uncovered.
void main() {
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> watchHalfOfFirstEpisode(
    WidgetTester t,
    EpisodesPanelFixture f,
  ) => t.runAsync(
    () => SeriesProgressStorage.saveSeriesPlaybackState(
      seriesTitle: f.show.name,
      season: 1,
      episode: 1,
      positionMs: 5000,
      durationMs: 10000,
      imdbId: f.id,
    ),
  );

  double? firstProgress(WidgetTester t) =>
      t.widget<EpisodeTile>(find.byType(EpisodeTile).first).watchProgress;

  Future<void> untilFirstProgress(
    WidgetTester t,
    EpisodesPanelFixture f,
    double expected,
  ) => f.until(
    t,
    () => firstProgress(t) == expected,
    frame: const Duration(milliseconds: 16),
  );

  testWidgets('quick-play plays on top of the list, one launch at a time', (
    t,
  ) async {
    await episodesPanelCase(t, 'screen-quick-play', 320, (f) async {
      f.heldQuickPlay = Completer<void>();
      await f.mountScreen(t, pushed: true);
      final tile = t.widget<EpisodeTile>(find.byType(EpisodeTile).first);
      tile.onPlay();
      tile.onPlay();
      await settle(t);
      // Nothing was popped: the player (or the Sources it may open instead)
      // lands on this list, and a second press is ignored while resolving.
      expect(f.calls, ['quick:true']);
      expect(find.byType(EpisodeTile), findsNWidgets(2));
      f.heldQuickPlay!.complete();
      await settle(t);
      tile.onPlay();
      await settle(t);
      expect(f.calls, ['quick:true', 'quick:true']);
    });
  });

  testWidgets('Back from Sources refreshes the episode progress', (t) async {
    await episodesPanelCase(t, 'screen-sources-return', 321, (f) async {
      await f.mountScreen(t, pushed: true);
      expect(firstProgress(t), anyOf(isNull, 0));
      t.widget<EpisodeTile>(find.byType(EpisodeTile).first).onSources();
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Sources page')),
        ),
      );
      await settle(t);
      await watchHalfOfFirstEpisode(t, f);
      f.navigator.currentState!.pop();
      await settle(t);
      await untilFirstProgress(t, f, 50);
      expect(find.text('Host'), findsNothing);
    });
  });

  testWidgets('a native player return refreshes only the uncovered list', (
    t,
  ) async {
    await episodesPanelCase(t, 'screen-native-return', 322, (f) async {
      await f.mountScreen(t, pushed: true);
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Sources page')),
        ),
      );
      await settle(t);
      await watchHalfOfFirstEpisode(t, f);
      // Covered by Sources: the list waits for its own didPopNext. Give a
      // refresh far longer than the uncovered one below needs to land.
      MainPageBridge.notifyPlaybackReturned();
      for (var frame = 0; frame < 40; frame++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump(const Duration(milliseconds: 16));
      }
      final covered = t.widget<EpisodeTile>(
        find.byType(EpisodeTile, skipOffstage: false).first,
      );
      expect(covered.watchProgress, anyOf(isNull, 0));
      f.navigator.currentState!.pop();
      await settle(t);
      await untilFirstProgress(t, f, 50);
      // Uncovered: the native-player signal alone refreshes it.
      await t.runAsync(
        () => SeriesProgressStorage.saveSeriesPlaybackState(
          seriesTitle: f.show.name,
          season: 1,
          episode: 1,
          positionMs: 7500,
          durationMs: 10000,
          imdbId: f.id,
        ),
      );
      MainPageBridge.notifyPlaybackReturned();
      await untilFirstProgress(t, f, 75);
    });
  });
}
