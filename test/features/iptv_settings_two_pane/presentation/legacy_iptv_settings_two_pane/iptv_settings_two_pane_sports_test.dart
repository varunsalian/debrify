// The wide IPTV settings' Sports & leagues entry: the last rail entry, a pane
// whose one row opens the same sheet as the Sports board, and focus coming
// back to that row when the sheet closes. The root ProviderScope stands in
// for the app's.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_settings_two_pane_fixture.dart';
import '../../../sports/presentation/sports_board_test_harness.dart';

const _sheet = ValueKey('sports-league-sheet');

String? get _focused => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _settle(WidgetTester t) async {
  // The fixture keeps a frame clock running, so settle by time.
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('Sports & leagues is the last rail entry and opens the sheet', (
    t,
  ) async {
    await twoPaneCase(t, (f) async {
      f.playlists = [twoPaneSource('a')];
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 800);
      await t.pumpWidget(
        ProviderScope(
          overrides: sportsLeagueFilterOverrides(FakeSportsPrefs()),
          child: f.host(),
        ),
      );
      await f.frame(t);

      final titles = [for (final entry in f.rails(t)) entry.title as String];
      expect(titles.last, 'Sports & leagues');
      expect(titles[titles.length - 2], 'Auto-refresh');

      await f.destination(t, 'Sports & leagues');
      expect(f.paneKey, 'sports');
      final rail = _focused;

      // Down from the last entry stays put.
      await f.keyEvent(t, LogicalKeyboardKey.arrowDown);
      expect(_focused, rail);
      // Up reaches Auto-refresh, Down comes back.
      await f.keyEvent(t, LogicalKeyboardKey.arrowUp);
      expect(find.text('All sources in this profile'), findsOneWidget);
      await f.keyEvent(t, LogicalKeyboardKey.arrowDown);
      expect(_focused, rail);

      await f.keyEvent(t, LogicalKeyboardKey.arrowRight);
      expect(_focused, 'iptv-2p-pane-0');
      expect(find.text('Choose sports and leagues'), findsOneWidget);

      await f.keyEvent(t, LogicalKeyboardKey.enter);
      await _settle(t);
      expect(find.byKey(_sheet), findsOneWidget);
      expect(_focused, 'sports-sheet-soccer');

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(t);
      expect(find.byKey(_sheet), findsNothing);
      expect(_focused, 'iptv-2p-pane-0');

      await f.keyEvent(t, LogicalKeyboardKey.arrowLeft);
      expect(_focused, rail);
    });
  });
}
