// The match stats page: what it shows per match state, the hide-scores
// reveal, loading/error/empty states, focus for a remote, Back, layout by
// width, and the details panel's way in.
import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/sports/application/sports_match_stats_notifier.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sports_match_stats_client.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_event_details.dart';
import 'package:debrify/features/sports/presentation/sports_match_stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sports_match_stats_fixtures.dart';
import 'sports_board_test_harness.dart' show useTwentyFourHourClock;

const _probability = ValueKey('sports-stats-probability');
const _team = ValueKey('sports-stats-team');
const _leaders = ValueKey('sports-stats-leaders');
const _form = ValueKey('sports-stats-form');
const _reveal = ValueKey('sports-stats-reveal');
const _retry = ValueKey('sports-stats-retry');
const _back = ValueKey('sports-stats-back');
const _openStats = ValueKey('sports-details-stats');

/// Pumps a home route with an "Open" button that pushes the stats page, so
/// closing the page has somewhere to return to.
Future<FakeSummaryFetch> _pump(
  WidgetTester t, {
  required SportsEvent event,
  Object body = '',
  bool hideScores = false,
  Size size = const Size(1280, 1000),
}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final fetch = FakeSummaryFetch(body);
  // The test binding's fake clock, so the cache ages as test time passes.
  final client = SportsMatchStatsClient(
    fetch: fetch.call,
    clock: () => t.binding.clock.now(),
  );
  // A fresh tree per call: a second pump in one test starts a new app.
  await t.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [sportsMatchStatsClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openSportsMatchStats(
                context,
                event: event,
                hideScores: hideScores,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
  return fetch;
}

bool _isFocusedWithin(Finder finder) {
  final primary = FocusManager.instance.primaryFocus?.context;
  if (primary == null) return false;
  final target = finder.evaluate().single;
  var found = false;
  primary.visitAncestorElements((element) {
    if (element == target) found = true;
    return !found;
  });
  return found || primary == target;
}

/// The NFL fixture as an in-progress game showing [detail] as its clock.
String _liveBody({String detail = 'Q3 5:12'}) {
  final json =
      withoutArtwork(readSummaryFixture('espn_summary_nfl_final.json')) as Map;
  final competition =
      ((json['header'] as Map)['competitions'] as List).first as Map;
  competition['status'] = {
    'type': {
      'state': 'in',
      'name': 'STATUS_IN_PROGRESS',
      'completed': false,
      'shortDetail': detail,
    },
  };
  return jsonEncode(json);
}

void main() {
  useTwentyFourHourClock();

  testWidgets('a finished game: probability, team stats and leaders', (
    t,
  ) async {
    await _pump(
      t,
      event: nflFinalEvent,
      body: summaryBody('espn_summary_nfl_final.json'),
    );
    expect(find.byKey(_probability), findsOneWidget);
    expect(find.text('Win probability'), findsOneWidget);
    expect(find.text('HOU 100%'), findsOneWidget);
    expect(find.text('Team stats'), findsOneWidget);
    expect(find.text('Total yards'), findsOneWidget);
    expect(find.text('Game leaders'), findsOneWidget);
    expect(find.text('C.J. Stroud'), findsOneWidget);
    expect(find.byKey(_form), findsNothing, reason: 'no form after the game');
    expect(find.text('26'), findsOneWidget);
    expect(find.text('4-6'), findsOneWidget, reason: 'team record');
  });

  testWidgets('a preview: predictor, season stats, season leaders, form', (
    t,
  ) async {
    await _pump(
      t,
      event: nbaScheduledEvent,
      body: summaryBody('espn_summary_nba_scheduled.json'),
      size: const Size(390, 2400),
    );
    expect(find.text('Matchup predictor'), findsOneWidget);
    expect(find.text('DET 54%'), findsOneWidget);
    expect(find.text('Season averages'), findsOneWidget);
    expect(find.text('Season leaders'), findsOneWidget);
    expect(find.text('Recent form'), findsOneWidget);
  });

  testWidgets('cards sit in two columns when wide, one when narrow', (t) async {
    await _pump(
      t,
      event: eplFinalEvent,
      body: summaryBody('espn_summary_epl_final.json'),
    );
    final teamLeft = t.getTopLeft(find.byKey(_team)).dx;
    final leadersLeft = t.getTopLeft(find.byKey(_leaders)).dx;
    expect(leadersLeft, greaterThan(teamLeft + 300));

    await _pump(
      t,
      event: eplFinalEvent,
      body: summaryBody('espn_summary_epl_final.json'),
      size: const Size(400, 3000),
    );
    expect(
      t.getTopLeft(find.byKey(_leaders)).dx,
      t.getTopLeft(find.byKey(_team)).dx,
    );
    expect(
      t.getTopLeft(find.byKey(_leaders)).dy,
      greaterThan(t.getTopLeft(find.byKey(_team)).dy),
    );
  });

  group('hide scores', () {
    testWidgets('a played match waits behind a reveal and fetches nothing', (
      t,
    ) async {
      final fetch = await _pump(
        t,
        event: nflFinalEvent,
        body: summaryBody('espn_summary_nfl_final.json'),
        hideScores: true,
      );
      expect(find.text(hiddenStatsCopy), findsOneWidget);
      expect(find.text('26'), findsNothing, reason: 'score hidden');
      expect(find.text('Final'), findsNothing, reason: 'result hidden');
      expect(fetch.calls, isEmpty);
      expect(_isFocusedWithin(find.byKey(_reveal)), isTrue);

      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(fetch.calls, hasLength(1));
      expect(find.text('HOU 100%'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
    });

    testWidgets('a preview waits too: form and records carry results', (
      t,
    ) async {
      final fetch = await _pump(
        t,
        event: nbaScheduledEvent,
        body: summaryBody('espn_summary_nba_scheduled.json'),
        hideScores: true,
      );
      expect(find.text(hiddenStatsCopy), findsOneWidget);
      expect(fetch.calls, isEmpty);
      expect(find.text('Played'), findsNothing);
      await t.tap(find.byKey(_reveal));
      await t.pumpAndSettle();
      expect(find.text('Recent form'), findsOneWidget);
    });

    testWidgets('a board copy that still says scheduled cannot leak', (
      t,
    ) async {
      // The panel opened before kick-off; the match has since finished.
      final staleBoardCopy = SportsEvent(
        id: nflFinalEvent.id,
        leagueId: 'nfl',
        start: nflFinalEvent.start,
        status: SportsEventStatus.scheduled,
        home: nflFinalEvent.home,
        away: nflFinalEvent.away,
      );
      final fetch = await _pump(
        t,
        event: staleBoardCopy,
        body: summaryBody('espn_summary_nfl_final.json'),
        hideScores: true,
      );
      expect(fetch.calls, isEmpty);
      expect(find.text(hiddenStatsCopy), findsOneWidget);
      for (final spoiler in ['26', 'HOU 100%', 'Final', '4-6']) {
        expect(find.text(spoiler), findsNothing, reason: spoiler);
      }
    });

    testWidgets('a postponed match is not called played', (t) async {
      final postponed = SportsEvent(
        id: nflFinalEvent.id,
        leagueId: 'nfl',
        start: nflFinalEvent.start,
        status: SportsEventStatus.postponed,
        home: nflFinalEvent.home,
        away: nflFinalEvent.away,
      );
      await _pump(t, event: postponed, hideScores: true);
      expect(find.text('Postponed'), findsOneWidget);
      expect(find.text('Played'), findsNothing);
    });
  });

  testWidgets('a failed load offers Retry, which recovers', (t) async {
    final fetch = await _pump(
      t,
      event: nflFinalEvent,
      body: StateError('offline'),
    );
    expect(find.text(statsErrorCopy), findsOneWidget);
    expect(_isFocusedWithin(find.byKey(_retry)), isTrue);

    fetch.body = summaryBody('espn_summary_nfl_final.json');
    await t.tap(find.byKey(_retry));
    await t.pumpAndSettle();
    expect(find.text(statsErrorCopy), findsNothing);
    expect(find.text('Win probability'), findsOneWidget);
  });

  testWidgets('a match the feed has nothing for says so', (t) async {
    final empty = (readSummaryFixture('espn_summary_nfl_final.json') as Map)
      ..remove('boxscore')
      ..remove('leaders')
      ..remove('winprobability');
    await _pump(
      t,
      event: nflFinalEvent,
      body: jsonEncode(withoutArtwork(empty)),
    );
    expect(find.text(noStatsCopy), findsOneWidget);
    // Something holds focus, so Escape and the remote's Back still close it.
    expect(
      _isFocusedWithin(find.byKey(const ValueKey('sports-stats-empty-back'))),
      isTrue,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SportsMatchStatsPage), findsNothing);
  });

  testWidgets('a postponed match shows no score, not a 0-0', (t) async {
    final json =
        withoutArtwork(readSummaryFixture('espn_summary_nfl_final.json'))
            as Map;
    final competition =
        ((json['header'] as Map)['competitions'] as List).first as Map;
    competition['status'] = {
      'type': {
        'state': 'post',
        'name': 'STATUS_POSTPONED',
        'completed': false,
        'shortDetail': 'Postponed',
      },
    };
    for (final side in competition['competitors'] as List) {
      (side as Map)['score'] = '0';
    }
    final postponed = SportsEvent(
      id: nflFinalEvent.id,
      leagueId: 'nfl',
      start: nflFinalEvent.start,
      status: SportsEventStatus.postponed,
      home: nflFinalEvent.home,
      away: nflFinalEvent.away,
    );
    await _pump(t, event: postponed, body: jsonEncode(json));
    expect(find.text('Postponed'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a live match stops polling while covered, resumes on top', (
    t,
  ) async {
    final live = SportsEvent(
      id: nflFinalEvent.id,
      leagueId: 'nfl',
      start: nflFinalEvent.start,
      status: SportsEventStatus.live,
      home: nflFinalEvent.home,
      away: nflFinalEvent.away,
    );
    final fetch = await _pump(t, event: live, body: _liveBody());
    expect(fetch.calls, hasLength(1));
    final navigator = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Player')),
      ),
    );
    await t.pumpAndSettle();
    await t.pump(SportsMatchStatsNotifier.pollInterval * 3);
    expect(fetch.calls, hasLength(1), reason: 'covered: no polling');
    navigator.pop();
    await t.pumpAndSettle();
    await t.pump(SportsMatchStatsNotifier.pollInterval);
    await t.pump();
    expect(fetch.calls, hasLength(2), reason: 'on top again: polls');
    // Leave no timer behind.
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('long statuses and big text do not overflow a small phone', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final fetch = FakeSummaryFetch(
      _liveBody(detail: 'End of 3rd Quarter, Official Review In Progress'),
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sportsMatchStatsClientProvider.overrideWithValue(
            SportsMatchStatsClient(fetch: fetch.call),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: SportsMatchStatsPage(
              event: nflFinalEvent,
              hideScores: false,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('HOU'), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  group('remote and keyboard', () {
    testWidgets('focus opens on the first section and D-pad walks down', (
      t,
    ) async {
      await _pump(
        t,
        event: eplFinalEvent,
        body: summaryBody('espn_summary_epl_final.json'),
        size: const Size(960, 540),
      );
      final first = find.byKey(const ValueKey('sports-stats-row-Possession'));
      expect(_isFocusedWithin(first), isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(
        _isFocusedWithin(find.byKey(const ValueKey('sports-stats-row-Shots'))),
        isTrue,
      );
      // Walking far down scrolls the page to keep the focused row in view.
      for (var i = 0; i < 9; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }
      final redCards = find.byKey(const ValueKey('sports-stats-row-Red cards'));
      expect(_isFocusedWithin(redCards), isTrue);
      final bottom = t.getBottomLeft(redCards).dy;
      expect(bottom, lessThanOrEqualTo(540));
    });

    testWidgets('Escape and the remote\'s Back close the page', (t) async {
      for (final key in [
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.goBack,
      ]) {
        await _pump(
          t,
          event: nflFinalEvent,
          body: summaryBody('espn_summary_nfl_final.json'),
        );
        expect(find.byType(SportsMatchStatsPage), findsOneWidget);
        // The host has no physical back key: the remote's BACK rides the
        // escape position with its own key code.
        await t.sendKeyDownEvent(key, physicalKey: PhysicalKeyboardKey.escape);
        await t.sendKeyUpEvent(key, physicalKey: PhysicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.byType(SportsMatchStatsPage), findsNothing, reason: '$key');
      }
    });

    testWidgets('Escape closes it while it is still loading', (t) async {
      final never = Completer<String>();
      await t.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final client = SportsMatchStatsClient(fetch: (_) => never.future);
      await t.pumpWidget(
        ProviderScope(
          overrides: [sportsMatchStatsClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openSportsMatchStats(
                  context,
                  event: nflFinalEvent,
                  hideScores: false,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(SportsMatchStatsPage), findsNothing);
    });

    testWidgets('the Back button closes it', (t) async {
      await _pump(
        t,
        event: nflFinalEvent,
        body: summaryBody('espn_summary_nfl_final.json'),
      );
      await t.tap(find.byKey(_back));
      await t.pumpAndSettle();
      expect(find.byType(SportsMatchStatsPage), findsNothing);
    });
  });

  group('details panel entry', () {
    Future<void> openPanel(WidgetTester t, SportsEvent event) async {
      await t.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final fetch = FakeSummaryFetch(
        summaryBody('espn_summary_nfl_final.json'),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            sportsMatchStatsClientProvider.overrideWithValue(
              SportsMatchStatsClient(fetch: fetch.call),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showSportsEventDetails(
                    context,
                    event: event,
                    watch: const SportsWatchOptions(),
                    follows: const SportsFollows(),
                    onPlay: (_) {},
                    onToggleTeam: (_) {},
                    onToggleLeague: (_) {},
                  ),
                  child: const Text('Details'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Details'));
      await t.pumpAndSettle();
    }

    testWidgets('a team league offers Match stats, which opens the page', (
      t,
    ) async {
      await openPanel(t, nflFinalEvent);
      expect(find.byKey(_openStats), findsOneWidget);
      await t.tap(find.byKey(_openStats));
      await t.pumpAndSettle();
      expect(find.byType(SportsMatchStatsPage), findsOneWidget);
      expect(find.text('Win probability'), findsOneWidget);

      // Back returns to the panel, still open underneath.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(SportsMatchStatsPage), findsNothing);
      expect(find.byKey(_openStats), findsOneWidget);
    });

    testWidgets('D-pad: Up to Match stats, Select, Back returns focus', (
      t,
    ) async {
      await openPanel(t, nflFinalEvent);
      // The panel opens on its first control below the row; walk up to it.
      for (var i = 0; i < 6 && !_isFocusedWithin(find.byKey(_openStats)); i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pumpAndSettle();
      }
      expect(_isFocusedWithin(find.byKey(_openStats)), isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(find.byType(SportsMatchStatsPage), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(SportsMatchStatsPage), findsNothing);
      expect(_isFocusedWithin(find.byKey(_openStats)), isTrue);
    });

    testWidgets('tennis has no stats page', (t) async {
      await openPanel(t, atpEvent);
      expect(find.byKey(_openStats), findsNothing);
    });
  });

  test('availability follows the league and the event shape', () {
    expect(sportsMatchStatsAvailable(nflFinalEvent), isTrue);
    expect(sportsMatchStatsAvailable(atpEvent), isFalse);
    final race = SportsEvent(
      id: 'r',
      leagueId: 'nfl',
      start: DateTime.utc(2030),
      status: SportsEventStatus.scheduled,
      title: 'Not a two-team event',
    );
    expect(sportsMatchStatsAvailable(race), isFalse);
  });
}
