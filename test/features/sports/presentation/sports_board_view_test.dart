// The mounted board: what it renders from a loaded state, how the remote
// moves through it, and what it does while loading or failing.
//
// Everything runs offline through [SportsBoardHarness]: fixtures parsed by
// the real parser without logos, a fake feed and guide, and the clock fixed
// at 2026-10-28 20:41 local, which makes the day sections deterministic.
import 'package:debrify/features/sports/application/sports_board_controller.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_board_header.dart';
import 'package:debrify/features/sports/presentation/sports_board_rows.dart';
import 'package:debrify/features/sports/presentation/sports_event_card_bodies.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sports_board_test_harness.dart';

const _sky = SportsChannelRef(
  name: 'UK: Sky Sports Main Event FHD',
  url: 'http://test/sky.m3u8',
);

const _newsChannel = SportsChannelRef(
  name: 'Sky Sports News',
  url: 'http://test/news.m3u8',
);

const _detailsPanelKey = ValueKey('sports-details-panel');
const _heroPreviewKey = ValueKey('sports-hero-preview');

final _uclLive = sportsFixture('espn_ucl_live.json', 'ucl');
final _eplScheduled = sportsFixture('espn_epl_scheduled.json', 'epl');

final _liveEvent = _uclLive.firstWhere(
  (event) => event.status == SportsEventStatus.live,
);

/// A guide programme for the live fixture, matching both team names.
final _skyListing = SportsGuideListing(
  channel: _sky,
  title: 'Champions League: Como v Manchester United',
  start: _liveEvent.start,
  stop: _liveEvent.start.add(const Duration(hours: 3)),
);

/// A programme airing half-way through on a sports channel, for the
/// live-channels row.
final _newsListing = SportsGuideListing(
  channel: _newsChannel,
  title: 'Sports Desk Live',
  start: boardClock.subtract(const Duration(hours: 1)).toUtc(),
  stop: boardClock.add(const Duration(hours: 1)).toUtc(),
);

/// Any day section (`day-1` … `day-6`); which one depends on the local zone.
final _daySection = find.byWidgetPredicate(
  (widget) =>
      widget is SportsBoardSectionSliver &&
      widget.section.id.startsWith('day-'),
);

void main() {
  setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileSessionMemory.clearAll();
  });

  Future<void> mountBoard(WidgetTester tester, SportsBoardHarness h) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await h.mount(tester);
  }

  testWidgets('renders hero and day sections from fixtures', (tester) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      guide: SportsGuideSnapshot(listings: [_skyListing]),
    );
    await mountBoard(tester, h);

    // Hero: eyebrow, score and the two actions the loaded state supports.
    expect(find.text("Champions League · LIVE 41'"), findsOneWidget);
    expect(find.text('1 – 0'), findsOneWidget);
    expect(find.text('Watch on Sky Sports Main Event'), findsOneWidget);
    expect(find.text('Where to watch · 1'), findsOneWidget);

    // Live soccer progress: 41 of 90 minutes.
    final played = tester.widget<FractionallySizedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('sports-hero-progress')),
            matching: find.byType(FractionallySizedBox),
          )
          .first,
    );
    expect(played.widthFactor, closeTo(41 / 90, 0.001));

    // Sections: the live one first, then the Saturday fixtures' day.
    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(_daySection, findsOneWidget);
    expect(find.byKey(sportsCardKey(_liveEvent)), findsOneWidget);
    expect(find.byKey(sportsCardKey(_eplScheduled.first)), findsOneWidget);
    // The live card's footer names the matched channel.
    expect(
      find.descendant(
        of: find.byKey(sportsCardKey(_liveEvent)),
        matching: find.text('Sky Sports Main Event'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a day fills a grid: four EPL fixtures share one row', (
    tester,
  ) async {
    final h = SportsBoardHarness(eventsByLeague: {'epl': _eplScheduled});
    await mountBoard(tester, h);

    final tops = {
      for (final event in _eplScheduled)
        tester.getTopLeft(find.byKey(sportsCardKey(event))).dy,
    };
    expect(tops, hasLength(1), reason: 'one grid row at 1280 px');
    final widths = {
      for (final event in _eplScheduled)
        tester.getSize(find.byKey(sportsCardKey(event))).width,
    };
    expect(widths, hasLength(1), reason: 'equal columns');
  });

  testWidgets('When segments switch the sections the board renders', (
    tester,
  ) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      guide: SportsGuideSnapshot(listings: [_skyListing]),
    );
    await mountBoard(tester, h);

    // Default is the week view, which carries the scheduled EPL fixtures.
    expect(find.text('Chelsea'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sports-filter-live')));
    await tester.pumpAndSettle();
    expect(_daySection, findsNothing);
    expect(find.text('Chelsea'), findsNothing);
    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.byKey(sportsCardKey(_liveEvent)), findsOneWidget);

    // Nothing is followed, so Following honestly empties the view.
    await tester.tap(find.byKey(const ValueKey('sports-toggle-following')));
    await tester.pumpAndSettle();
    expect(find.text('No fixtures in this view.'), findsOneWidget);
    expect(find.text('LIVE NOW'), findsNothing);
  });

  testWidgets('following a league keeps only its fixtures', (tester) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      followedLeagues: {'epl'},
    );
    await mountBoard(tester, h);

    await tester.tap(find.byKey(const ValueKey('sports-toggle-following')));
    await tester.pumpAndSettle();
    expect(_daySection, findsOneWidget);
    expect(find.text('YOUR TEAMS'), findsNothing);
    // The live UCL fixture is not followed, so the live row stays away.
    expect(find.text('LIVE NOW'), findsNothing);
    expect(find.byKey(sportsCardKey(_eplScheduled.first)), findsOneWidget);
    expect(
      tester
          .widget<SportsToolButton>(
            find.byKey(const ValueKey('sports-toggle-following')),
          )
          .toggled,
      isTrue,
    );
  });

  testWidgets('a whole-board failure shows the message and Try again reloads', (
    tester,
  ) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      failing: {'ucl', 'epl'},
    );
    await mountBoard(tester, h);

    expect(find.text(kSportsBoardLoadFailed), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('LIVE NOW'), findsNothing);
    // The automatic first load is a plain (cache-allowed) refresh.
    expect(h.feed.calls.every((call) => !call.force), isTrue);

    h.feed.failing.clear();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text(kSportsBoardLoadFailed), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('LIVE NOW'), findsOneWidget);
    // The manual retry bypasses the feed cache.
    expect(h.feed.calls.where((call) => call.force), isNotEmpty);
  });

  testWidgets('a first load with no events paints three skeleton rows', (
    tester,
  ) async {
    final h = SportsBoardHarness(eventsByLeague: {'ucl': _uclLive});
    h.feed.gated = true;
    await mountBoard(tester, h);

    for (final row in const [0, 1, 2]) {
      expect(
        find.byKey(ValueKey('sports-board-skeleton-$row')),
        findsOneWidget,
      );
    }
    expect(find.text('Try again'), findsNothing);
    expect(find.text('No fixtures in this view.'), findsNothing);
  });

  testWidgets('a loaded board with nothing to row says so', (tester) async {
    final h = SportsBoardHarness();
    await mountBoard(tester, h);

    expect(find.text('No fixtures in this view.'), findsOneWidget);
    expect(find.text('LIVE NOW'), findsNothing);
  });

  testWidgets('arrows move focus between cards and enter opens the details', (
    tester,
  ) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      guide: SportsGuideSnapshot(listings: [_skyListing]),
    );
    await mountBoard(tester, h);

    // On a TV build the first card of the first section owns focus on mount,
    // so Select opens its fixture straight away.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(_detailsPanelKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_detailsPanelKey),
        matching: find.text('Manchester United'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(_detailsPanelKey), findsNothing);

    // Down into the day grid, right to its second fixture, Select opens it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(_detailsPanelKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_detailsPanelKey),
        matching: find.text('Coventry City'),
      ),
      findsOneWidget,
    );
    // The first fixture of that row is Chelsea; it must NOT be the one open.
    expect(
      find.descendant(
        of: find.byKey(_detailsPanelKey),
        matching: find.text('Chelsea'),
      ),
      findsNothing,
    );
  });

  testWidgets('the hero plays the first guide option and opens the details', (
    tester,
  ) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive},
      guide: SportsGuideSnapshot(listings: [_skyListing]),
    );
    await mountBoard(tester, h);

    await tester.tap(find.text('Watch on Sky Sports Main Event'));
    await tester.pumpAndSettle();
    expect(h.played, [_sky]);

    await tester.tap(find.text('Where to watch · 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(_detailsPanelKey), findsOneWidget);
  });

  testWidgets(
    'the wide hero adds the channel preview, the narrow one does not',
    (tester) async {
      final h = SportsBoardHarness(
        eventsByLeague: {'ucl': _uclLive},
        guide: SportsGuideSnapshot(listings: [_skyListing]),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await h.mount(tester);

      expect(find.byKey(_heroPreviewKey), findsNothing);

      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      await tester.pumpAndSettle();
      expect(find.byKey(_heroPreviewKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_heroPreviewKey),
          matching: find.text('Sky Sports Main Event'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('the scores toggle hides scores and persists the choice', (
    tester,
  ) async {
    final h = SportsBoardHarness(eventsByLeague: {'ucl': _uclLive});
    await mountBoard(tester, h);
    final scores = find.byKey(const ValueKey('sports-toggle-scores'));

    expect(find.text('···'), findsNothing);
    expect(find.byType(SportsHiddenScore), findsNothing);
    expect(tester.widget<SportsToolButton>(scores).toggled, isTrue);
    expect(tester.widget<SportsToolButton>(scores).label, 'Scores shown');

    await tester.tap(scores);
    await tester.pumpAndSettle();

    expect(tester.widget<SportsToolButton>(scores).toggled, isFalse);
    expect(tester.widget<SportsToolButton>(scores).label, 'Scores hidden');
    // The hero falls back to its glyph, the cards to their bars.
    expect(find.text('···'), findsWidgets);
    expect(find.byType(SportsHiddenScore), findsWidgets);
    expect(h.prefs.flags[SportsFollowStore.hideScoresKey], isTrue);
  });

  testWidgets('the live-channels row lists what is airing and plays the pick', (
    tester,
  ) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive},
      guide: SportsGuideSnapshot(liveSportsListings: [_newsListing]),
    );
    await mountBoard(tester, h);

    expect(find.text('LIVE SPORTS CHANNELS'), findsOneWidget);
    expect(find.text('Sky Sports News'), findsOneWidget);
    expect(find.text('Sports Desk Live'), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);
    // Half-way through a two-hour programme.
    final progress = tester.widget<FractionallySizedBox>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey('sports-live-channel-http://test/news.m3u8'),
            ),
            matching: find.byType(FractionallySizedBox),
          )
          .first,
    );
    expect(progress.widthFactor, closeTo(0.5, 0.01));

    await tester.tap(find.text('Sports Desk Live'));
    await tester.pumpAndSettle();
    expect(h.played.map((channel) => channel.url), ['http://test/news.m3u8']);
  });

  testWidgets('the refresh button forces a reload', (tester) async {
    final h = SportsBoardHarness(eventsByLeague: {'ucl': _uclLive});
    await mountBoard(tester, h);
    h.feed.calls.clear();

    await tester.tap(find.byKey(const ValueKey('sports-refresh')));
    await tester.pumpAndSettle();

    expect(h.feed.calls, isNotEmpty);
    expect(h.feed.calls.every((call) => call.force), isTrue);
  });
}
