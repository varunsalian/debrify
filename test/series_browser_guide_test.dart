import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/widgets/series_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  SeriesPlaylist buildPlaylist({bool withGuide = true}) {
    final sp = SeriesPlaylist.fromPlaylistEntries([
      const PlaylistEntry(url: 'http://x/1', title: 'Show.S01E01.1080p.mkv'),
      const PlaylistEntry(url: 'http://x/2', title: 'Show.S01E02.1080p.mkv'),
    ], forceSeries: true);
    if (withGuide) {
      sp.fullTvmazeEpisodes = [
        {'season': 1, 'number': 1, 'name': 'Pilot'},
        {'season': 1, 'number': 2, 'name': 'Second Steps'},
        {'season': 1, 'number': 3, 'name': 'The Third One'},
        {'season': 1, 'number': 4, 'name': 'Finale'},
        {'season': 2, 'number': 1, 'name': 'Return'},
        {'season': 2, 'number': 2, 'name': 'Aftermath'},
      ];
    }
    return sp;
  }

  Future<void> pumpBrowser(
    WidgetTester tester, {
    required SeriesPlaylist playlist,
    required bool showAllEpisodes,
    required List<(int, int)> selections,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: SeriesBrowser(
                      seriesPlaylist: playlist,
                      currentEpisodeIndex: 0,
                      showAllEpisodes: showAllEpisodes,
                      onEpisodeSelected: (season, episode) =>
                          selections.add((season, episode)),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('full-guide mode lists absent episodes as fetchable rows', (
    tester,
  ) async {
    final selections = <(int, int)>[];
    await pumpBrowser(
      tester,
      playlist: buildPlaylist(),
      showAllEpisodes: true,
      selections: selections,
    );

    // Absent S1 episodes render (dimmed) alongside the pack's two files.
    expect(find.text('The Third One'), findsOneWidget);
    expect(find.text('Tap to fetch'), findsWidgets);
    // E4 sits below the fold of the lazy list — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Finale'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Finale'), findsOneWidget);

    // Tapping an absent episode still reports its (season, episode); the
    // sheet layer turns that into an in-player fetch.
    await tester.tap(find.text('The Third One'));
    await tester.pump();
    expect(selections, [(1, 3)]);
  });

  testWidgets('full-guide mode unions seasons into the picker', (tester) async {
    await pumpBrowser(
      tester,
      playlist: buildPlaylist(),
      showAllEpisodes: true,
      selections: <(int, int)>[],
    );

    // The pack only has S1; TVMaze adds S2 to the picker.
    await tester.tap(find.text('Season 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Season 2'), findsOneWidget);

    await tester.tap(find.text('Season 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Return'), findsOneWidget);
    expect(find.text('Aftermath'), findsOneWidget);
    expect(find.text('Tap to fetch'), findsNWidgets(2));
  });

  testWidgets('without full-guide mode only pack episodes render', (
    tester,
  ) async {
    await pumpBrowser(
      tester,
      playlist: buildPlaylist(),
      showAllEpisodes: false,
      selections: <(int, int)>[],
    );

    expect(find.text('The Third One'), findsNothing);
    expect(find.text('Tap to fetch'), findsNothing);
    // No TVMaze-only seasons in the picker either: single season = plain
    // label, no popup affordance.
    expect(find.byType(PopupMenuButton<int>), findsNothing);
  });
}
