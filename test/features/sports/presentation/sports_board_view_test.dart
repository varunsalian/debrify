// The mounted board: what it renders from a loaded state, how the remote
// moves through it, and what it does while loading or failing.
//
// Everything runs offline. Fixtures are parsed by the real parser and then
// stripped of their team logo urls, so every crest paints its abbreviation
// plate; guide channels carry no logos either. A fake feed client answers the
// controller's fetches, the guide is a fake source and the clock is fixed at
// 2026-10-28 20:41 local, which is what makes the section rows deterministic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/application/sports_board_controller.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/espn_scoreboard_parser.dart';
import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_board_view.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/features/sports/fixtures';

/// Fixed board clock: 2026-10-28 20:41, local.
final _clock = DateTime(2026, 10, 28, 20, 41);

final _ucl = sportsLeagueById('ucl')!;
final _epl = sportsLeagueById('epl')!;

const _sky = SportsChannelRef(
  name: 'UK: Sky Sports Main Event FHD',
  url: 'http://test/sky.m3u8',
);

const _newsChannel = SportsChannelRef(
  name: 'Sky Sports News',
  url: 'http://test/news.m3u8',
);

ValueKey<String> _cardKey(SportsEvent event) =>
    ValueKey('sports-card-${event.leagueId}-${event.id}');

const _detailsPanelKey = ValueKey('sports-details-panel');
const _heroPreviewKey = ValueKey('sports-hero-preview');

/// Fixture events with every team logo removed, so no crest reaches the
/// network during a widget test.
List<SportsEvent> _fixture(String name, String leagueId) => parseEspnScoreboard(
  jsonDecode(File('$_fixtureDir/$name').readAsStringSync()),
  leagueId: leagueId,
).map(_withoutLogos).toList();

SportsEvent _withoutLogos(SportsEvent event) => SportsEvent(
  id: event.id,
  leagueId: event.leagueId,
  start: event.start,
  status: event.status,
  home: _team(event.home),
  away: _team(event.away),
  homeScore: event.homeScore,
  awayScore: event.awayScore,
  title: event.title,
  subtitle: event.subtitle,
  clock: event.clock,
  statusLabel: event.statusLabel,
  broadcasts: event.broadcasts,
);

SportsTeam? _team(SportsTeam? team) => team == null
    ? null
    : SportsTeam(
        id: team.id,
        name: team.name,
        shortName: team.shortName,
        abbreviation: team.abbreviation,
        color: team.color,
      );

final _uclLive = _fixture('espn_ucl_live.json', 'ucl');
final _eplScheduled = _fixture('espn_epl_scheduled.json', 'epl');

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
  start: _clock.subtract(const Duration(hours: 1)).toUtc(),
  stop: _clock.add(const Duration(hours: 1)).toUtc(),
);

/// Serves pre-parsed fixtures; the real client would hit the network.
class _FakeFeedClient extends SportsFeedClient {
  _FakeFeedClient() : super(fetch: _noNetwork);

  static Future<String> _noNetwork(Uri uri) =>
      throw StateError('the board never reaches the network in tests');

  /// Parsed events per league id; a league absent here loads as empty.
  final Map<String, List<SportsEvent>> events = {};

  /// League ids whose feed fails for this call.
  final Set<String> failing = {};

  /// Held by a test to keep the first refresh in flight.
  final Completer<void> gate = Completer<void>();

  /// One entry per call, so a test can prove a retry was a forced refresh.
  final List<({String leagueId, bool force})> calls = [];

  /// While false (default) a gated client still answers immediately.
  bool gated = false;

  @override
  Future<List<SportsEvent>> fetchLeague(
    SportsLeague league, {
    required DateTime fromUtc,
    required DateTime toUtc,
    bool force = false,
  }) async {
    calls.add((leagueId: league.id, force: force));
    if (gated) await gate.future;
    if (failing.contains(league.id)) {
      throw SportsFeedException(Uri.parse('fake://${league.id}'), 'feed down');
    }
    return events[league.id] ?? const [];
  }
}

class _FakeGuideSource implements SportsGuideSource {
  SportsGuideSnapshot snapshot = SportsGuideSnapshot.empty;

  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async => snapshot;
}

class _FakePrefs implements SportsPrefs {
  final Map<String, List<String>> lists = {};
  final Map<String, bool> flags = {};

  @override
  List<String>? getStringList(String key) => lists[key];

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    lists[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => flags[key];

  @override
  Future<bool> setBool(String key, bool value) async {
    flags[key] = value;
    return true;
  }
}

class _Harness {
  _Harness({
    Map<String, List<SportsEvent>> eventsByLeague = const {},
    Set<String> failing = const {},
    SportsGuideSnapshot guide = SportsGuideSnapshot.empty,
    Set<String> followedLeagues = const {},
  }) {
    feed.events.addAll(eventsByLeague);
    feed.failing.addAll(failing);
    guideSource.snapshot = guide;
    if (followedLeagues.isNotEmpty) {
      prefs.lists[SportsFollowStore.leaguesKey] = [...followedLeagues];
    }
  }

  final _FakeFeedClient feed = _FakeFeedClient();
  final _FakeGuideSource guideSource = _FakeGuideSource();
  final _FakePrefs prefs = _FakePrefs();
  final List<SportsChannelRef> played = [];
  final List<SportsLeague> leagues = [_ucl, _epl];

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sportsFeedClientProvider.overrideWithValue(feed),
          sportsFollowStoreProvider.overrideWithValue(
            SportsFollowStore(() async => prefs),
          ),
          sportsGuideSourceProvider.overrideWithValue(guideSource),
          sportsClockProvider.overrideWithValue(() => _clock),
          sportsLeaguesProvider.overrideWithValue(leagues),
        ],
        child: MaterialApp(
          home: Scaffold(body: SportsBoardView(onPlay: played.add)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileSessionMemory.clearAll();
  });

  Future<void> mountBoard(WidgetTester tester, _Harness h) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await h.mount(tester);
  }

  testWidgets('renders hero and sections from fixtures', (tester) async {
    final h = _Harness(
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

    // Sections: the live row and the week row, each holding its own cards.
    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.byKey(_cardKey(_liveEvent)), findsOneWidget);
    expect(find.byKey(_cardKey(_eplScheduled.first)), findsOneWidget);
  });

  testWidgets('filter segments switch the sections the board renders', (
    tester,
  ) async {
    final h = _Harness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      guide: SportsGuideSnapshot(listings: [_skyListing]),
    );
    await mountBoard(tester, h);

    // Default is the week view, which carries the scheduled EPL fixtures.
    expect(find.text('Chelsea'), findsOneWidget);

    await tester.tap(find.text('Live 1'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing);
    expect(find.text('Chelsea'), findsNothing);
    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.byKey(_cardKey(_liveEvent)), findsOneWidget);

    // Nothing is followed, so the Following view is honestly empty.
    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.text('No fixtures in this view.'), findsOneWidget);
    expect(find.text('LIVE NOW'), findsNothing);
  });

  testWidgets('following a league populates the Following row', (tester) async {
    final h = _Harness(
      eventsByLeague: {'ucl': _uclLive, 'epl': _eplScheduled},
      followedLeagues: {'epl'},
    );
    await mountBoard(tester, h);

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.text('UPCOMING'), findsOneWidget);
    // The live UCL fixture is not followed, so the live row stays away.
    expect(find.text('LIVE NOW'), findsNothing);
    expect(find.byKey(_cardKey(_eplScheduled.first)), findsOneWidget);
  });

  testWidgets('a whole-board failure shows the message and Try again reloads', (
    tester,
  ) async {
    final h = _Harness(
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
    final h = _Harness(eventsByLeague: {'ucl': _uclLive});
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
    final h = _Harness();
    await mountBoard(tester, h);

    expect(find.text('No fixtures in this view.'), findsOneWidget);
    expect(find.text('LIVE NOW'), findsNothing);
  });

  testWidgets('arrows move focus between cards and enter opens the details', (
    tester,
  ) async {
    final h = _Harness(
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

    // Down into the week row, right to its second fixture, Select opens it.
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
    final h = _Harness(
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
      final h = _Harness(
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
    final h = _Harness(eventsByLeague: {'ucl': _uclLive});
    await mountBoard(tester, h);

    expect(find.text('···'), findsNothing);
    expect(find.text('Scores shown'), findsOneWidget);

    await tester.tap(find.text('Scores shown'));
    await tester.pumpAndSettle();

    expect(find.text('Scores hidden'), findsOneWidget);
    // Hero and card rows all fall back to the hidden-score glyph.
    expect(find.text('···'), findsWidgets);
    expect(h.prefs.flags[SportsFollowStore.hideScoresKey], isTrue);
  });

  testWidgets('the live-channels row lists what is airing and plays the pick', (
    tester,
  ) async {
    final h = _Harness(
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
    final h = _Harness(eventsByLeague: {'ucl': _uclLive});
    await mountBoard(tester, h);
    h.feed.calls.clear();

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(h.feed.calls, isNotEmpty);
    expect(h.feed.calls.every((call) => call.force), isTrue);
  });
}
