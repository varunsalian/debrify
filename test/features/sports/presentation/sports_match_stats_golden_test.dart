// Visual record of the match stats page (macOS goldens only): a finished NFL
// game on a TV-sized screen, a pre-game NBA preview at phone width and a
// finished Premier League match. The real (trimmed) ESPN summaries feed the
// page through the production parser; artwork URLs are dropped so no image
// is fetched and every plate paints its text fallback.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_match_stats_client.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_match_stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sports_match_stats_fixtures.dart';
import 'sports_board_test_harness.dart' show useTwentyFourHourClock;

final _theme = ThemeData(brightness: Brightness.dark, fontFamily: 'Inter');

Future<void> _loadFonts(WidgetTester t) => t.runAsync(() async {
  for (final family in ['Inter', 'JetBrainsMono']) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
});

Future<void> _mount(
  WidgetTester t, {
  required SportsEvent event,
  required String fixture,
  required Size size,
}) async {
  await _loadFonts(t);
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final body = jsonEncode(withoutArtwork(readSummaryFixture(fixture)));
  final client = SportsMatchStatsClient(fetch: (_) async => body);
  await t.pumpWidget(
    ProviderScope(
      overrides: [sportsMatchStatsClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: _theme,
        debugShowCheckedModeBanner: false,
        home: SportsMatchStatsPage(event: event, hideScores: false),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _expectGolden(String name) => expectLater(
  find.byType(SportsMatchStatsPage),
  matchesGoldenFile('../../../goldens/sports_match_stats/macos/$name.png'),
);

void main() {
  useTwentyFourHourClock();
  // Goldens are recorded on macOS only; other hosts render fonts differently.
  final skip = !Platform.isMacOS;

  testWidgets('finished NFL game, wide', skip: skip, (t) async {
    await _mount(
      t,
      event: nflFinalEvent,
      fixture: 'espn_summary_nfl_final.json',
      size: const Size(1280, 1100),
    );
    await _expectGolden('nfl_final_wide');
  });

  testWidgets('NBA preview, phone', skip: skip, (t) async {
    await _mount(
      t,
      event: nbaScheduledEvent,
      fixture: 'espn_summary_nba_scheduled.json',
      size: const Size(390, 1900),
    );
    await _expectGolden('nba_preview_phone');
  });

  testWidgets('finished Premier League match, wide', skip: skip, (t) async {
    await _mount(
      t,
      event: eplFinalEvent,
      fixture: 'espn_summary_epl_final.json',
      size: const Size(1280, 1200),
    );
    await _expectGolden('epl_final_wide');
  });
}
