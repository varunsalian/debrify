// The board's header and sport chips on a mounted board: the When switch's
// counts, selection and remote handling, the Sports & leagues button, the
// chips narrowing the day sections, and the league choices hiding fixtures.
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_team_crest.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sports_board_test_harness.dart';

SportsTeam _team(String id, String name) =>
    SportsTeam(id: id, name: name, shortName: name, abbreviation: id);

final _uclLive = sportsFixture('espn_ucl_live.json', 'ucl');
final _eplScheduled = sportsFixture('espn_epl_scheduled.json', 'epl');

final _ipl = SportsEvent(
  id: 'ipl-1',
  leagueId: 'ipl',
  start: DateTime(2026, 10, 29, 19, 30).toUtc(),
  status: SportsEventStatus.scheduled,
  home: _team('MI', 'Mumbai Indians'),
  away: _team('CSK', 'Chennai Super Kings'),
);

final _nba = SportsEvent(
  id: 'nba-1',
  leagueId: 'nba',
  start: DateTime(2026, 10, 30, 5).toUtc(),
  status: SportsEventStatus.scheduled,
  home: _team('BOS', 'Boston Celtics'),
  away: _team('NYK', 'New York Knicks'),
);

SportsBoardHarness _mixed() => SportsBoardHarness(
  eventsByLeague: {
    'ucl': _uclLive,
    'epl': _eplScheduled,
    'ipl': [_ipl],
    'nba': [_nba],
  },
  leagueIds: const ['ucl', 'epl', 'ipl', 'nba'],
);

Finder _key(String key) => find.byKey(ValueKey(key));

FocusNode _nodeOf(WidgetTester tester, String key) => tester
    .widget<Focus>(
      find.descendant(of: _key(key), matching: find.byType(Focus)).first,
    )
    .focusNode!;

bool _selected(WidgetTester tester, String key) =>
    tester.widget<SportsFocusPill>(_key(key)).selected;

String? _count(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: _key(key), matching: find.byType(Text)),
    )
    .last
    .data;

void main() {
  setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileSessionMemory.clearAll();
  });

  Future<void> mountBoard(WidgetTester tester, SportsBoardHarness h) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await h.mount(tester);
  }

  testWidgets('the When switch counts each window and slides to the pick', (
    tester,
  ) async {
    await mountBoard(tester, _mixed());

    expect(find.text('Sports'), findsOneWidget);
    expect(find.text('Updated 20:41'), findsOneWidget);
    expect(_count(tester, 'sports-filter-live'), '1');
    expect(_count(tester, 'sports-filter-today'), '1');
    expect(_count(tester, 'sports-filter-week'), '7');
    expect(_selected(tester, 'sports-filter-week'), isTrue);
    AnimatedAlign indicator() =>
        tester.widget<AnimatedAlign>(_key('sports-when-indicator'));
    expect(indicator().alignment, const Alignment(1, 0));

    await tester.tap(_key('sports-filter-today'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'sports-filter-today'), isTrue);
    expect(_selected(tester, 'sports-filter-week'), isFalse);
    expect(indicator().alignment, const Alignment(0, 0));
    expect(find.text('Chelsea'), findsNothing);
    expect(find.text('LIVE NOW'), findsOneWidget);

    // The three segments are equally wide.
    final widths = {
      for (final f in ['live', 'today', 'week'])
        tester.getSize(_key('sports-filter-$f')).width,
    };
    expect(widths, hasLength(1));
  });

  testWidgets('the remote walks the When switch and Select picks', (
    tester,
  ) async {
    await mountBoard(tester, _mixed());

    _nodeOf(tester, 'sports-filter-live').requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_nodeOf(tester, 'sports-filter-today').hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_selected(tester, 'sports-filter-today'), isTrue);
    // Focus stays on the segment that was picked.
    expect(_nodeOf(tester, 'sports-filter-today').hasFocus, isTrue);
  });

  testWidgets('the leagues button opens the sheet; Back returns focus to it', (
    tester,
  ) async {
    await mountBoard(tester, _mixed());

    final opener = _nodeOf(tester, 'sports-open-leagues');
    opener.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_key('sports-league-sheet'), findsOneWidget);
    expect(find.text('Sports & leagues'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_key('sports-league-sheet'), findsNothing);
    expect(opener.hasFocus, isTrue);
  });

  testWidgets('sport chips count each sport and narrow the board', (
    tester,
  ) async {
    await mountBoard(tester, _mixed());

    expect(_count(tester, 'sports-chip-all'), '7');
    expect(_count(tester, 'sports-chip-soccer'), '5');
    expect(_count(tester, 'sports-chip-cricket'), '1');
    expect(_count(tester, 'sports-chip-basketball'), '1');
    final xs = [
      for (final chip in ['all', 'soccer', 'cricket', 'basketball'])
        tester.getTopLeft(_key('sports-chip-$chip')).dx,
    ];
    expect(xs, [...xs]..sort(), reason: 'All, then sports by rank');
    expect(_selected(tester, 'sports-chip-all'), isTrue);

    await tester.tap(_key('sports-chip-cricket'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'sports-chip-cricket'), isTrue);
    expect(find.byKey(sportsCardKey(_ipl)), findsOneWidget);
    expect(find.byKey(sportsCardKey(_nba)), findsNothing);
    expect(find.text('Chelsea'), findsNothing);
    expect(find.text('LIVE NOW'), findsNothing);

    await tester.tap(_key('sports-chip-all'));
    await tester.pumpAndSettle();
    expect(find.byKey(sportsCardKey(_nba)), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
  });

  testWidgets('a chip with nothing in the new window falls back to All', (
    tester,
  ) async {
    await mountBoard(tester, _mixed());

    await tester.tap(_key('sports-chip-cricket'));
    await tester.pumpAndSettle();
    await tester.tap(_key('sports-filter-live'));
    await tester.pumpAndSettle();

    // Nothing in cricket is live: All shows the live football instead.
    expect(_key('sports-chip-cricket'), findsNothing);
    expect(_selected(tester, 'sports-chip-all'), isTrue);
    expect(find.text('LIVE NOW'), findsOneWidget);
  });

  testWidgets('leagues switched off disappear; a change reloads the board', (
    tester,
  ) async {
    final h = _mixed();
    h.leaguePrefs.lists[SportsLeagueFilterStore.offKey] = ['nba'];
    await mountBoard(tester, h);

    expect(find.byKey(sportsCardKey(_nba)), findsNothing);
    expect(_key('sports-chip-basketball'), findsNothing);
    final callsBefore = h.feed.calls.length;

    await tester.tap(_key('sports-open-leagues'));
    await tester.pumpAndSettle();
    await tester.tap(_key('sports-sheet-sport-basketball'));
    await tester.pumpAndSettle();
    await tester.tap(_key('sports-sheet-league-nba'));
    await tester.pumpAndSettle();
    await tester.tap(_key('sports-sheet-done'));
    await tester.pumpAndSettle();

    expect(h.leaguePrefs.lists[SportsLeagueFilterStore.offKey], isEmpty);
    expect(find.byKey(sportsCardKey(_nba)), findsOneWidget);
    // The refetch belongs to the board controller (it listens to its league
    // list; see sports_board_controller_test). Closing the sheet adds no
    // forced reload of its own.
    expect(h.feed.calls.skip(callsBefore).every((call) => !call.force), isTrue);
  });
}
