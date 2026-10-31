// The details panel: what it lists, how it closes and what it hands back.
//
// Every channel here has `logoUrl: null`, so the logo plate paints initials
// and no test reaches the network. The wide/narrow split is driven by the test
// surface size, which is the only input the panel reads from the environment.
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_event_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

const _panelKey = ValueKey('sports-details-panel');
const _sheetKey = ValueKey('sports-details-sheet');
const _closeKey = ValueKey('sports-details-close');

ValueKey<String> _rowKey(String url) => ValueKey('sports-details-channel-$url');

ValueKey<String> _followKey(String teamKey) =>
    ValueKey('sports-details-follow-$teamKey');

const _home = SportsTeam(
  id: '1',
  name: 'Arsenal',
  shortName: 'Arsenal',
  abbreviation: 'ARS',
  color: 0xFFEF0107,
);

const _away = SportsTeam(
  id: '2',
  name: 'Chelsea',
  shortName: 'Chelsea',
  abbreviation: 'CHE',
);

const _sky = SportsChannelRef(
  name: 'UK: Sky Sports Main Event FHD',
  url: 'http://test/sky.m3u8',
);

const _tnt = SportsChannelRef(
  name: 'UK: TNT Sports 1 HD',
  url: 'http://test/tnt.m3u8',
);

const _broadcaster = SportsChannelRef(
  name: 'BBC One',
  url: 'http://test/bbc.m3u8',
);

final _start = DateTime.utc(2026, 10, 29, 19, 45);

final _listing = SportsGuideListing(
  channel: _sky,
  title: 'Champions League: Arsenal v Chelsea',
  start: _start,
  stop: _start.add(const Duration(hours: 2)),
);

const _guideOption = SportsWatchOption(
  channel: _sky,
  kind: SportsMatchKind.guide,
);

const _tntOption = SportsWatchOption(
  channel: _tnt,
  kind: SportsMatchKind.guide,
);

const _possibleOption = SportsWatchOption(
  channel: _broadcaster,
  kind: SportsMatchKind.broadcaster,
);

SportsEvent _match({
  SportsEventStatus status = SportsEventStatus.live,
  String? clock,
  int? homeScore = 2,
  int? awayScore = 1,
}) => SportsEvent(
  id: 'e1',
  leagueId: 'ucl',
  start: _start,
  status: status,
  home: _home,
  away: _away,
  homeScore: homeScore,
  awayScore: awayScore,
  clock: clock,
);

final _raceStart = DateTime.utc(2026, 10, 25, 6);

SportsEvent _race() => SportsEvent(
  id: 'f1-1',
  leagueId: 'f1',
  start: _raceStart,
  status: SportsEventStatus.scheduled,
  title: 'Grand Prix of Japan',
  subtitle: 'Suzuka Circuit',
);

/// Opens the panel over a blank route and records every intent it reports.
class _Harness {
  _Harness({
    this.event,
    this.watch = SportsWatchOptions.empty,
    this.follows = const SportsFollows(),
  });

  final SportsEvent? event;
  final SportsWatchOptions watch;
  final SportsFollows follows;

  final List<SportsChannelRef> played = [];
  final List<String> toggledTeams = [];
  final List<String> toggledLeagues = [];

  late Future<void> route;
  late BuildContext context;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
  }) async {
    // The panel picks its layout from the view width, so the test drives the
    // view itself: physical size at a 1.0 ratio is the logical size.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (built) {
              context = built;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    route = showSportsEventDetails(
      context,
      event: event ?? _match(),
      watch: watch,
      follows: follows,
      onPlay: played.add,
      onToggleTeam: toggledTeams.add,
      onToggleLeague: toggledLeagues.add,
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, Key key) =>
      tester.tap(find.byKey(key));
}

void main() {
  testWidgets('a wide view docks a 420 px panel on the right', (tester) async {
    final h = _Harness(watch: const SportsWatchOptions(guide: [_guideOption]));
    await h.open(tester, size: const Size(1000, 800));

    expect(find.byKey(_sheetKey), findsNothing);
    final panel = find.byKey(_panelKey);
    expect(panel, findsOneWidget);
    final size = tester.getSize(panel);
    expect(size.width, 420);
    expect(size.height, 800);
    // Docked right: the panel's right edge is the view's right edge.
    expect(tester.getTopRight(panel).dx, 1000);
  });

  testWidgets('a narrow view uses a bottom sheet capped at 88 % height', (
    tester,
  ) async {
    final h = _Harness(watch: const SportsWatchOptions(guide: [_guideOption]));
    await h.open(tester, size: const Size(500, 900));
    expect(find.byKey(_panelKey), findsNothing);
    final sheet = find.byKey(_sheetKey);
    expect(sheet, findsOneWidget);
    final cap = tester.widget<ConstrainedBox>(sheet).constraints.maxHeight;
    expect(cap, 900 * 0.88);
    expect(tester.getSize(sheet).height, lessThanOrEqualTo(900 * 0.88));
  });

  testWidgets('the panel shows league, status, both teams and the score', (
    tester,
  ) async {
    final h = _Harness(event: _match(clock: "41'"));
    await h.open(tester);

    expect(find.text('Champions League'), findsOneWidget);
    expect(find.text("LIVE 41'"), findsOneWidget);
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('an unfinished fixture reads with v and no score', (
    tester,
  ) async {
    final h = _Harness(
      event: _match(
        status: SportsEventStatus.scheduled,
        homeScore: null,
        awayScore: null,
      ),
    );
    await h.open(tester);

    expect(find.text('v'), findsOneWidget);
    expect(find.text('at'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('north american leagues read the matchup with at', (
    tester,
  ) async {
    final h = _Harness(
      event: SportsEvent(
        id: 'nba-1',
        leagueId: 'nba',
        start: _start,
        status: SportsEventStatus.scheduled,
        home: SportsTeam(
          id: '5',
          name: 'New York Knicks',
          shortName: 'Knicks',
          abbreviation: 'NYK',
        ),
        away: SportsTeam(
          id: '6',
          name: 'Boston Celtics',
          shortName: 'Celtics',
          abbreviation: 'BOS',
        ),
      ),
    );
    await h.open(tester);

    expect(find.text('at'), findsOneWidget);
    expect(find.text('v'), findsNothing);
    expect(find.text('Follow Knicks'), findsOneWidget);
  });

  testWidgets('a non-team event shows its title and circuit', (tester) async {
    final h = _Harness(event: _race());
    await h.open(tester);

    expect(find.text('Grand Prix of Japan'), findsOneWidget);
    expect(find.text('Suzuka Circuit'), findsOneWidget);
    expect(find.text('v'), findsNothing);
  });

  testWidgets('guide options list under a ticked section and end in Watch', (
    tester,
  ) async {
    final h = _Harness(
      watch: SportsWatchOptions(
        guide: [
          SportsWatchOption(
            channel: _sky,
            kind: SportsMatchKind.guide,
            listing: _listing,
          ),
        ],
      ),
    );
    await h.open(tester);

    expect(find.text('In your guide'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('UK: Sky Sports Main Event FHD'), findsOneWidget);
    expect(find.text('Champions League: Arsenal v Chelsea'), findsOneWidget);
    expect(
      find.text(
        '${DateFormat('HH:mm').format(_start.toLocal())}–'
        '${DateFormat('HH:mm').format(_listing.stop.toLocal())}',
      ),
      findsOneWidget,
    );
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Possible channels'), findsNothing);
  });

  testWidgets('an event stream found by name is watchable on your channels', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(
        guide: [
          SportsWatchOption(channel: _tnt, kind: SportsMatchKind.channelName),
        ],
      ),
    );
    await h.open(tester);

    expect(find.text('On your channels'), findsOneWidget);
    expect(find.text('In your guide'), findsNothing);
    expect(find.text(namedChannelCopy), findsOneWidget);
    expect(find.text(possibleChannelCopy), findsNothing);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('guide listings and named streams keep their own sections', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(
        guide: [
          _guideOption,
          SportsWatchOption(channel: _tnt, kind: SportsMatchKind.channelName),
        ],
      ),
    );
    await h.open(tester);

    expect(find.text('In your guide'), findsOneWidget);
    expect(find.text('On your channels'), findsOneWidget);
    expect(find.text('Watch'), findsNWidgets(2));
  });

  testWidgets('possible channels are a separate section ending in Open', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(possible: [_possibleOption]),
    );
    await h.open(tester);

    expect(find.text('Possible channels'), findsOneWidget);
    expect(find.text('In your guide'), findsNothing);
    expect(find.text('BBC One'), findsOneWidget);
    // A channel with no logo still gets a plate: its initials.
    expect(find.text('BO'), findsOneWidget);
    expect(find.text(possibleChannelCopy), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('both sections appear together when both have options', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(
        guide: [_guideOption, _tntOption],
        possible: [_possibleOption],
      ),
    );
    await h.open(tester);

    expect(find.text('In your guide'), findsOneWidget);
    expect(find.text('Possible channels'), findsOneWidget);
    expect(find.text('Watch'), findsNWidgets(2));
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('an unlisted fixture explains itself instead of listing rows', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);

    expect(find.text(noListingCopy), findsOneWidget);
    expect(find.text('In your guide'), findsNothing);
    expect(find.text('Possible channels'), findsNothing);
  });

  testWidgets('choosing a guide row closes the panel and plays that channel', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(guide: [_guideOption, _tntOption]),
    );
    await h.open(tester);

    await h.press(tester, _rowKey(_tnt.url));
    await tester.pumpAndSettle();

    expect(h.played, [_tnt]);
    expect(find.byKey(_panelKey), findsNothing);
  });

  testWidgets('choosing a possible row plays it too', (tester) async {
    final h = _Harness(
      watch: const SportsWatchOptions(
        guide: [_guideOption],
        possible: [_possibleOption],
      ),
    );
    await h.open(tester, size: const Size(500, 900));

    await h.press(tester, _rowKey(_broadcaster.url));
    await tester.pumpAndSettle();

    expect(h.played, [_broadcaster]);
    expect(find.byKey(_sheetKey), findsNothing);
  });

  testWidgets('the first guide row is focused and Enter plays it', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(guide: [_guideOption, _tntOption]),
    );
    await h.open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(h.played, [_sky]);
  });

  testWidgets('escape closes the panel without playing anything', (
    tester,
  ) async {
    final h = _Harness(watch: const SportsWatchOptions(guide: [_guideOption]));
    await h.open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(h.played, isEmpty);
    expect(find.byKey(_panelKey), findsNothing);
  });

  testWidgets('the remote back key closes the panel too', (tester) async {
    final h = _Harness(watch: const SportsWatchOptions(guide: [_guideOption]));
    await h.open(tester);

    // The host test platform has no physical back key, so the remote's BACK
    // rides the escape position with the goBack key code.
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pumpAndSettle();

    expect(h.played, isEmpty);
    expect(find.byKey(_panelKey), findsNothing);
  });

  testWidgets('the close button dismisses the panel', (tester) async {
    final h = _Harness();
    await h.open(tester);

    expect(find.byKey(_closeKey), findsOneWidget);
    await h.press(tester, _closeKey);
    await tester.pumpAndSettle();

    expect(find.byKey(_panelKey), findsNothing);
    expect(h.played, isEmpty);
    await h.route;
  });

  testWidgets('follow pills start from the followed state and report the key', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(guide: [_guideOption]),
      follows: const SportsFollows(teamKeys: {'ucl:1'}),
    );
    await h.open(tester);

    expect(find.text('Following Arsenal'), findsOneWidget);
    expect(find.text('Follow Chelsea'), findsOneWidget);

    await h.press(tester, _followKey('ucl:1'));
    await tester.pump();

    expect(h.toggledTeams, ['ucl:1']);
    expect(find.text('Follow Arsenal'), findsOneWidget);
    expect(find.text('Following Arsenal'), findsNothing);
  });

  testWidgets('following a team works before anything is followed', (
    tester,
  ) async {
    final h = _Harness(watch: const SportsWatchOptions(guide: [_guideOption]));
    await h.open(tester);

    await h.press(tester, _followKey('ucl:2'));
    await tester.pump();

    expect(h.toggledTeams, ['ucl:2']);
    expect(find.text('Following Chelsea'), findsOneWidget);
  });

  testWidgets('a non-team event offers its league to follow', (tester) async {
    final h = _Harness(
      event: _race(),
      watch: const SportsWatchOptions(guide: [_guideOption]),
    );
    await h.open(tester);

    expect(find.text('Follow Formula 1'), findsOneWidget);
    await h.press(tester, _followKey('f1'));
    await tester.pump();

    expect(h.toggledLeagues, ['f1']);
    expect(find.text('Following Formula 1'), findsOneWidget);
  });

  testWidgets('with no rows the first follow button takes focus', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(h.toggledTeams, ['ucl:1']);
    expect(h.played, isEmpty);
  });

  testWidgets('every row and control is tall enough for a remote', (
    tester,
  ) async {
    final h = _Harness(
      watch: const SportsWatchOptions(
        guide: [_guideOption],
        possible: [_possibleOption],
      ),
    );
    await h.open(tester);

    for (final key in [
      _rowKey(_sky.url),
      _rowKey(_broadcaster.url),
      _closeKey,
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }
    expect(tester.getSize(find.byKey(_rowKey(_sky.url))).height, 52);
  });
}
