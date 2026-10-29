// The Sports & leagues sheet on its own: two-pane remote grammar, Select
// toggles, the per-sport "All" switch, reset, Back with focus returning to
// the opener, and the stacked touch layout at phone width. League choices
// live in an in-memory store behind the real notifier.
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_league_sheet.dart';
import 'package:debrify/features/sports/presentation/sports_league_sheet_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sports_board_test_harness.dart';

const _openerKey = ValueKey('opener');

Finder _key(String key) => find.byKey(ValueKey(key));

String? get _focused => FocusManager.instance.primaryFocus?.debugLabel;

bool _switchOn(WidgetTester tester, String rowKey) => tester
    .widget<SportsSwitchGlyph>(
      find.descendant(
        of: _key(rowKey),
        matching: find.byType(SportsSwitchGlyph),
      ),
    )
    .value;

int get _defaultOn => kSportsLeagues.where((l) => l.enabledByDefault).length;

Future<FakeSportsPrefs> _open(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prefs = FakeSportsPrefs();
  await tester.pumpWidget(
    ProviderScope(
      overrides: sportsLeagueFilterOverrides(prefs),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                key: _openerKey,
                autofocus: true,
                onPressed: () => showSportsLeagueSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(_key('sports-league-sheet'), findsOneWidget);
  return prefs;
}

void main() {
  testWidgets('opens on the first sport with its leagues and a summary', (
    tester,
  ) async {
    await _open(tester);

    expect(_focused, 'sports-sheet-soccer');
    expect(find.text('All football'), findsOneWidget);
    expect(find.text('Champions League'), findsOneWidget);
    expect(find.text('UEFA'), findsWidgets);
    expect(
      find.text('$_defaultOn of ${kSportsLeagues.length} leagues on'),
      findsOneWidget,
    );
    // Football ships with niche leagues off, so its All switch is off.
    expect(_switchOn(tester, 'sports-sheet-all-soccer'), isFalse);
    expect(_switchOn(tester, 'sports-sheet-league-ucl'), isTrue);
    final football = kSportsLeagues.where((l) => l.sport == SportKind.soccer);
    expect(
      find.text(
        '${football.where((l) => l.enabledByDefault).length}/'
        '${football.length}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('arrows move between and within panes; Select toggles', (
    tester,
  ) async {
    final prefs = await _open(tester);

    // Down the sports list: the right pane follows the focused sport.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focused, 'sports-sheet-cricket');
    expect(find.text('All cricket'), findsOneWidget);

    // Right into the leagues, down to the first one, Select switches it off.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_focused, 'sports-sheet-all-cricket');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focused, 'sports-sheet-intl-cricket');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(prefs.lists[SportsLeagueFilterStore.offKey], ['intl-cricket']);
    expect(_switchOn(tester, 'sports-sheet-league-intl-cricket'), isFalse);
    // Cricket: seven leagues, four on by default, one now switched off.
    expect(find.text('4/7'), findsNothing);
    expect(find.text('3/7'), findsOneWidget, reason: 'cricket on-count');

    // Left returns to the selected sport, not to whatever is nearest.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_focused, 'sports-sheet-cricket');

    // Select on a sport steps into its leagues.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final third = _focused;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_focused, startsWith('sports-sheet-all-'));
    expect(third, isNot('sports-sheet-cricket'));
  });

  testWidgets('the All switch turns every league of the sport on, then off', (
    tester,
  ) async {
    final prefs = await _open(tester);
    await tester.tap(_key('sports-sheet-sport-rugby'));
    await tester.pumpAndSettle();
    expect(find.text('All rugby'), findsOneWidget);
    expect(_switchOn(tester, 'sports-sheet-all-rugby'), isFalse);

    await tester.tap(_key('sports-sheet-all-rugby'));
    await tester.pumpAndSettle();
    expect(_switchOn(tester, 'sports-sheet-all-rugby'), isTrue);
    expect(prefs.lists[SportsLeagueFilterStore.onKey], [
      'prem-rugby',
      'top14',
      'urc',
    ]);
    for (final id in ['six-nations', 'prem-rugby', 'urc', 'top14']) {
      expect(_switchOn(tester, 'sports-sheet-league-$id'), isTrue, reason: id);
    }

    await tester.tap(_key('sports-sheet-all-rugby'));
    await tester.pumpAndSettle();
    expect(prefs.lists[SportsLeagueFilterStore.onKey], isEmpty);
    expect(prefs.lists[SportsLeagueFilterStore.offKey], ['six-nations']);
    expect(_switchOn(tester, 'sports-sheet-league-six-nations'), isFalse);

    await tester.tap(_key('sports-sheet-reset'));
    await tester.pumpAndSettle();
    expect(prefs.lists[SportsLeagueFilterStore.offKey], isEmpty);
    expect(_switchOn(tester, 'sports-sheet-league-six-nations'), isTrue);
  });

  testWidgets('Back closes the sheet and focus returns to the opener', (
    tester,
  ) async {
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_key('sports-league-sheet'), findsNothing);
    final opener = tester.widget<TextButton>(find.byKey(_openerKey));
    expect(opener.focusNode, isNull);
    expect(
      Focus.of(tester.element(find.text('Open'))).hasFocus,
      isTrue,
      reason: 'the button that opened the sheet has focus again',
    );
  });

  testWidgets('Done and the close button both close it', (tester) async {
    await _open(tester);
    await tester.tap(_key('sports-sheet-done'));
    await tester.pumpAndSettle();
    expect(_key('sports-league-sheet'), findsNothing);

    await tester.tap(find.byKey(_openerKey));
    await tester.pumpAndSettle();
    await tester.tap(_key('sports-sheet-close'));
    await tester.pumpAndSettle();
    expect(_key('sports-league-sheet'), findsNothing);
  });

  testWidgets('a phone stacks the panes and touch toggles leagues', (
    tester,
  ) async {
    final prefs = await _open(tester, size: const Size(390, 800));

    // The sports become a horizontal strip above the leagues.
    final strip = tester.getTopLeft(_key('sports-sheet-sport-soccer'));
    final leagues = tester.getTopLeft(_key('sports-sheet-all-soccer'));
    expect(leagues.dy, greaterThan(strip.dy));
    expect(
      tester.getTopLeft(_key('sports-sheet-sport-cricket')).dx,
      greaterThan(strip.dx),
    );

    // Further sports scroll into reach along the strip.
    await tester.scrollUntilVisible(
      _key('sports-sheet-sport-tennis'),
      120,
      scrollable: find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal,
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(_key('sports-sheet-sport-tennis'));
    await tester.pumpAndSettle();
    await tester.tap(_key('sports-sheet-sport-tennis'));
    await tester.pumpAndSettle();
    expect(find.text('All tennis'), findsOneWidget);
    await tester.tap(_key('sports-sheet-league-wta'));
    await tester.pumpAndSettle();
    expect(prefs.lists[SportsLeagueFilterStore.offKey], ['wta']);
    expect(tester.takeException(), isNull);
  });
}
