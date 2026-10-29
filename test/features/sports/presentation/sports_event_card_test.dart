// Card behaviour: what a fixture says (league, status, teams, scores, where to
// watch) and how it answers the remote. No logo urls anywhere, so the crest
// paints its abbreviation plate and the test never touches the network.
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_event_card.dart';
import 'package:debrify/features/sports/presentation/sports_event_card_bodies.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

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

/// The board's live red (the spotlight theme's `rec` token).
final _live = IptvStyleTokens.spotlight.rec;

final _kickoff = DateTime.utc(2026, 10, 29, 19, 45);

SportsEvent _event({
  SportsEventStatus status = SportsEventStatus.live,
  DateTime? start,
  String? clock,
  String statusLabel = '',
  int? homeScore = 2,
  int? awayScore = 1,
  String leagueId = 'ucl',
  String? title,
  String? subtitle,
}) => SportsEvent(
  id: 'e1',
  leagueId: leagueId,
  start: start ?? _kickoff,
  status: status,
  home: title == null ? _home : null,
  away: title == null ? _away : null,
  homeScore: homeScore,
  awayScore: awayScore,
  title: title,
  subtitle: subtitle,
  clock: clock,
  statusLabel: statusLabel,
);

/// A fixture with no scores at all: what the feed sends before kick-off.
SportsEvent _scheduled({DateTime? start}) => _event(
  status: SportsEventStatus.scheduled,
  start: start,
  homeScore: null,
  awayScore: null,
);

const _guideTwo = SportsWatchOptions(
  guide: [
    SportsWatchOption(channel: _sky, kind: SportsMatchKind.guide),
    SportsWatchOption(channel: _tnt, kind: SportsMatchKind.guide),
  ],
);

SportsWatchOption _guide(SportsChannelRef channel) => SportsWatchOption(
  channel: channel,
  kind: SportsMatchKind.guide,
  listing: SportsGuideListing(
    channel: channel,
    title: 'Champions League: Arsenal v Chelsea',
    start: _kickoff,
    stop: _kickoff.add(const Duration(hours: 2)),
  ),
);

/// The dot that marks a live status: a circle in the board's live colour.
final _liveDot = find.byWidgetPredicate((widget) {
  if (widget is! Container) return false;
  final decoration = widget.decoration;
  return decoration is BoxDecoration &&
      decoration.shape == BoxShape.circle &&
      decoration.color == _live;
});

Future<void> _mount(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: card)),
    ),
  );
  await tester.pumpAndSettle();
}

SportsEventCard _card({
  SportsEvent? event,
  SportsWatchOptions watch = SportsWatchOptions.empty,
  bool hideScores = false,
  bool followed = false,
  VoidCallback? onPressed,
  bool autofocus = false,
}) => SportsEventCard(
  event: event ?? _event(),
  hideScores: hideScores,
  followed: followed,
  watch: watch,
  onPressed: onPressed ?? () {},
  autofocus: autofocus,
);

void main() {
  testWidgets('live fixture shows league, clock, both teams and scores', (
    tester,
  ) async {
    await _mount(
      tester,
      _card(
        event: _event(clock: "41'"),
        watch: _guideTwo,
      ),
    );

    // The header names the league in full and the live clock beside its dot.
    expect(find.text('Champions League'), findsOneWidget);
    expect(find.text("41'"), findsOneWidget);
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // No logo url: each crest falls back to its abbreviation plate.
    expect(find.text('ARS'), findsOneWidget);
    expect(find.text('CHE'), findsOneWidget);
    // Live is marked by a dot of its own, not only by the word.
    expect(_liveDot, findsOneWidget);
    // The card shows the first guide channel plus the overflow count.
    expect(find.text('Sky Sports Main Event'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('TNT Sports 1'), findsNothing);
  });

  testWidgets('a live fixture with no clock still says it is live', (
    tester,
  ) async {
    await _mount(tester, _card(event: _event(clock: null)));

    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('finished fixture falls back to FT and keeps final scores', (
    tester,
  ) async {
    await _mount(
      tester,
      _card(
        event: _event(
          status: SportsEventStatus.finished,
          homeScore: 3,
          awayScore: 0,
        ),
      ),
    );

    expect(find.text('FT'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(_liveDot, findsNothing);
  });

  testWidgets('finished fixture prefers the feed status label', (tester) async {
    await _mount(
      tester,
      _card(
        event: _event(
          status: SportsEventStatus.finished,
          statusLabel: 'AET',
          homeScore: 1,
          awayScore: 1,
        ),
      ),
    );

    expect(find.text('AET'), findsOneWidget);
    expect(find.text('FT'), findsNothing);
  });

  testWidgets('scheduled fixture shows local kickoff and no scores', (
    tester,
  ) async {
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20, 15);
    await _mount(tester, _card(event: _scheduled(start: tonight)));

    expect(find.text('20:15'), findsOneWidget);
    expect(
      find.textContaining(DateFormat('EEE').format(tonight)),
      findsNothing,
    );
    expect(find.text('2'), findsNothing);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('scheduled fixture names the weekday once it is not today', (
    tester,
  ) async {
    final now = DateTime.now();
    final later = DateTime(
      now.year,
      now.month,
      now.day,
      20,
      15,
    ).add(const Duration(days: 2));
    await _mount(tester, _card(event: _scheduled(start: later)));

    expect(
      find.text('${DateFormat('EEE').format(later)} 20:15'),
      findsOneWidget,
    );
  });

  testWidgets('postponed fixture says Postponed instead of a kickoff time', (
    tester,
  ) async {
    await _mount(
      tester,
      _card(
        event: _event(
          status: SportsEventStatus.postponed,
          statusLabel: 'Postponed',
          homeScore: null,
          awayScore: null,
        ),
      ),
    );

    expect(find.text('Postponed'), findsOneWidget);
    expect(
      find.text(DateFormat('HH:mm').format(_kickoff.toLocal())),
      findsNothing,
    );
  });

  testWidgets('hidden scores keep the fixture and replace digits with bars', (
    tester,
  ) async {
    await _mount(tester, _card(hideScores: true, watch: _guideTwo));

    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.byType(SportsHiddenScore), findsNWidgets(2));
  });

  testWidgets('a scheduled fixture has no score slot to hide', (tester) async {
    await _mount(tester, _card(event: _scheduled(), hideScores: true));

    expect(find.byType(SportsHiddenScore), findsNothing);
    expect(find.text('Arsenal'), findsOneWidget);
  });

  testWidgets('non-team events show title and subtitle instead of team rows', (
    tester,
  ) async {
    await _mount(
      tester,
      _card(
        event: _event(
          leagueId: 'f1',
          title: 'Grand Prix of Japan',
          subtitle: 'Suzuka Circuit',
          homeScore: null,
          awayScore: null,
        ),
      ),
    );

    expect(find.text('Grand Prix of Japan'), findsOneWidget);
    expect(find.text('Suzuka Circuit'), findsOneWidget);
    expect(find.text('Formula 1'), findsOneWidget);
    expect(find.text('Arsenal'), findsNothing);
  });

  testWidgets('a single guide option shows no overflow count', (tester) async {
    await _mount(
      tester,
      _card(watch: SportsWatchOptions(guide: [_guide(_sky)])),
    );

    expect(find.text('Sky Sports Main Event'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\+')), findsNothing);
  });

  testWidgets('unconfirmed options count themselves as possible', (
    tester,
  ) async {
    await _mount(
      tester,
      _card(
        watch: const SportsWatchOptions(
          possible: [
            SportsWatchOption(channel: _sky, kind: SportsMatchKind.broadcaster),
            SportsWatchOption(channel: _tnt, kind: SportsMatchKind.broadcaster),
          ],
        ),
      ),
    );

    expect(find.text('2 possible'), findsOneWidget);
    expect(find.text('Sky Sports Main Event'), findsNothing);
  });

  testWidgets('a fixture with nothing found says it is not on your channels', (
    tester,
  ) async {
    await _mount(tester, _card());

    expect(find.text('Not on your channels yet'), findsOneWidget);
  });

  testWidgets('a followed event marks its league row with a star', (
    tester,
  ) async {
    await _mount(tester, _card(followed: true));
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await _mount(tester, _card(followed: false));
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('the card is one button whose label reads the whole fixture', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _mount(
      tester,
      _card(
        event: _event(clock: "41'"),
        watch: _guideTwo,
        followed: true,
      ),
    );

    // One control announces the whole fixture...
    expect(
      find.bySemanticsLabel(
        "Followed, Champions League, Arsenal v Chelsea, LIVE 41', "
        'Sky Sports Main Event +1',
      ),
      findsOneWidget,
    );
    // ...and its rows are hidden from a reader, so nothing is read twice.
    expect(find.bySemanticsLabel('Arsenal'), findsNothing);
    expect(find.bySemanticsLabel('UCL'), findsNothing);
    handle.dispose();
  });

  testWidgets('enter on a focused card presses it exactly once', (
    tester,
  ) async {
    var pressed = 0;
    await _mount(tester, _card(autofocus: true, onPressed: () => pressed++));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pressed, 1);
  });

  testWidgets('a held OK acts once while space and numpad enter activate', (
    tester,
  ) async {
    var pressed = 0;
    await _mount(tester, _card(autofocus: true, onPressed: () => pressed++));

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(pressed, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
    expect(pressed, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(pressed, 3);
  });

  testWidgets('a focus node supplied by the board owns the card focus', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await _mount(
      tester,
      SportsEventCard(
        event: _event(),
        hideScores: false,
        followed: false,
        watch: SportsWatchOptions.empty,
        onPressed: () {},
        focusNode: node,
      ),
    );

    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
  });
}
