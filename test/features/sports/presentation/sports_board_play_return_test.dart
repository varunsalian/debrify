// Playing a match's channel from its details: the player is handed every
// channel offered for the match, and closing the player comes back to the
// same match with the channel just played marked and focused, so the next
// one is a single step away instead of a new walk through the board.
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_event_details.dart';
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

const _tnt = SportsChannelRef(
  name: 'US: TNT Sports 1 HD',
  url: 'http://test/tnt.m3u8',
);

const _panel = ValueKey('sports-details-panel');

final _uclLive = sportsFixture('espn_ucl_live.json', 'ucl');

final _liveEvent = _uclLive.firstWhere(
  (event) => event.status == SportsEventStatus.live,
);

SportsGuideListing _listing(SportsChannelRef channel) => SportsGuideListing(
  channel: channel,
  title: 'Champions League: Como v Manchester United',
  start: _liveEvent.start,
  stop: _liveEvent.start.add(const Duration(hours: 3)),
);

Finder _row(SportsChannelRef channel) =>
    find.byKey(ValueKey('sports-details-channel-${channel.url}'));

void main() {
  setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileSessionMemory.clearAll();
  });

  Future<SportsBoardHarness> openMatch(WidgetTester tester) async {
    final h = SportsBoardHarness(
      eventsByLeague: {'ucl': _uclLive},
      guide: SportsGuideSnapshot(listings: [_listing(_sky), _listing(_tnt)]),
    );
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await h.mount(tester);
    // The live fixture's card owns focus on a TV build.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(_panel), findsOneWidget);
    return h;
  }

  /// The player closed: the board waits for the screen size to settle
  /// before it reopens the match.
  Future<void> closePlayer(WidgetTester tester, SportsBoardHarness h) async {
    h.playing!.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  bool focused(WidgetTester tester, Finder row) => Focus.of(
    tester.element(find.descendant(of: row, matching: find.byType(Text)).first),
  ).hasFocus;

  testWidgets('the player gets every channel offered for the match', (
    tester,
  ) async {
    final h = await openMatch(tester);
    await tester.tap(_row(_tnt));
    await tester.pumpAndSettle();

    expect(h.played, [_tnt]);
    expect(h.lineups.single, unorderedEquals([_sky, _tnt]));
    expect(identical(h.lineups.single.first, h.lineups.single.last), isFalse);
    // The panel is gone while the player is up.
    expect(find.byKey(_panel), findsNothing);
  });

  testWidgets('closing the player returns to the match, the channel marked', (
    tester,
  ) async {
    final h = await openMatch(tester);
    final feedCalls = h.feed.calls.length;
    await tester.tap(_row(_tnt));
    await tester.pumpAndSettle();

    await closePlayer(tester, h);

    expect(find.byKey(_panel), findsOneWidget);
    expect(
      find.descendant(
        of: _row(_tnt),
        matching: find.textContaining(playedLastCopy),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(_sky),
        matching: find.textContaining(playedLastCopy),
      ),
      findsNothing,
    );
    expect(focused(tester, _row(_tnt)), isTrue);

    // The other channel is one tap away; no reload, no new walk.
    await tester.tap(_row(_sky));
    await tester.pumpAndSettle();
    expect(h.played, [_tnt, _sky]);
    expect(h.feed.calls, hasLength(feedCalls));
  });

  testWidgets('closing the reopened match stays on the board', (tester) async {
    final h = await openMatch(tester);
    await tester.tap(_row(_sky));
    await tester.pumpAndSettle();
    await closePlayer(tester, h);
    expect(find.byKey(_panel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(_panel), findsNothing);
    expect(h.played, [_sky]);
  });

  testWidgets('a page left over the board keeps the match from reopening', (
    tester,
  ) async {
    final h = await openMatch(tester);
    await tester.tap(_row(_sky));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Text('covering page')),
    );
    await tester.pumpAndSettle();
    await closePlayer(tester, h);

    expect(find.text('covering page'), findsOneWidget);
    expect(find.byKey(_panel), findsNothing);
  });

  testWidgets('a phone turning upright after the player reopens as a sheet', (
    tester,
  ) async {
    final h = await openMatch(tester);
    await tester.tap(_row(_sky));
    await tester.pumpAndSettle();

    // Back from a landscape player: the size is still landscape when the
    // player hands back and turns portrait a moment later.
    h.playing!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    addTearDown(tester.view.reset);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 860);
    // Frame by frame, as a device renders while the board waits.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sports-details-sheet')), findsOneWidget);
    expect(find.byKey(_panel), findsNothing);
  });

  testWidgets('a failed launch still comes back to the match', (tester) async {
    final h = await openMatch(tester);
    await tester.tap(_row(_sky));
    await tester.pumpAndSettle();

    h.playing!.completeError(StateError('launch failed'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(_panel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
