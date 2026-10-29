// The narrow IPTV settings hub's Sports & leagues row opens the same sheet
// as the Sports board. The root ProviderScope stands in for the app's.
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_settings_fixture.dart';
import '../../../sports/presentation/sports_board_test_harness.dart';

void main() {
  testWidgets('the hub row opens Sports & leagues and its switches write', (
    tester,
  ) async {
    await iptvSettingsCase(tester, (f) async {
      final prefs = FakeSportsPrefs();
      await f.mount(
        tester,
        size: const Size(420, 900),
        wrap: (app) => ProviderScope(
          overrides: sportsLeagueFilterOverrides(prefs),
          child: app,
        ),
      );

      final row = find.text('Sports & leagues');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('What the Sports board shows'), findsOneWidget);
      await tester.tap(row);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const ValueKey('sports-league-sheet')), findsOneWidget);
      expect(find.text('All football'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sports-sheet-league-ucl')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(prefs.lists[SportsLeagueFilterStore.offKey], ['ucl']);
      expect(tester.takeException(), isNull);
    });
  });
}
