// Shared offline harness for the mounted Sports board: a fake feed client, a
// fake guide, in-memory prefs for follows and league choices, and a fixed
// clock (2026-10-28 20:41 local). Fixture events are parsed by the real
// parser and stripped of logo urls so no crest reaches the network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/application/sports_league_filter_notifier.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/espn_scoreboard_parser.dart';
import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_board_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/features/sports/fixtures';

/// Fixed board clock: 2026-10-28 20:41, local.
final boardClock = DateTime(2026, 10, 28, 20, 41);

/// The whole app, dialogs included, for golden captures.
const sportsBoardCaptureKey = ValueKey('sports-board-capture');

ValueKey<String> sportsCardKey(SportsEvent event) =>
    ValueKey('sports-card-${event.leagueId}-${event.id}');

/// Fixture events with every team logo removed.
List<SportsEvent> sportsFixture(String name, String leagueId) =>
    parseEspnScoreboard(
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

/// Serves pre-parsed fixtures; the real client would hit the network.
class FakeSportsFeedClient extends SportsFeedClient {
  FakeSportsFeedClient() : super(fetch: _noNetwork);

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

class FakeSportsGuideSource implements SportsGuideSource {
  SportsGuideSnapshot snapshot = SportsGuideSnapshot.empty;

  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async => snapshot;
}

class FakeSportsPrefs implements SportsPrefs {
  final Map<String, List<String>> lists = {};
  final Map<String, bool> flags = {};

  @override
  List<String>? getStringList(String key) => lists[key];

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    lists[key] = List.of(value);
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

/// Root-scope overrides for the app-wide league choices.
List<Override> sportsLeagueFilterOverrides(FakeSportsPrefs prefs) => [
  sportsLeagueFilterStoreProvider.overrideWithValue(
    SportsLeagueFilterStore(() async => prefs),
  ),
];

class SportsBoardHarness {
  SportsBoardHarness({
    Map<String, List<SportsEvent>> eventsByLeague = const {},
    Set<String> failing = const {},
    SportsGuideSnapshot guide = SportsGuideSnapshot.empty,
    Set<String> followedLeagues = const {},
    List<String> leagueIds = const ['ucl', 'epl'],
    DateTime? clock,
  }) : leagues = [for (final id in leagueIds) sportsLeagueById(id)!],
       clock = clock ?? boardClock {
    feed.events.addAll(eventsByLeague);
    feed.failing.addAll(failing);
    guideSource.snapshot = guide;
    if (followedLeagues.isNotEmpty) {
      prefs.lists[SportsFollowStore.leaguesKey] = [...followedLeagues];
    }
  }

  final FakeSportsFeedClient feed = FakeSportsFeedClient();
  final FakeSportsGuideSource guideSource = FakeSportsGuideSource();
  final FakeSportsPrefs prefs = FakeSportsPrefs();

  /// League choices (the Sports & leagues sheet's storage).
  final FakeSportsPrefs leaguePrefs = FakeSportsPrefs();
  final List<SportsChannelRef> played = [];
  final List<SportsLeague> leagues;

  /// The board's fixed "now".
  final DateTime clock;

  Widget app({ThemeData? theme}) => ProviderScope(
    overrides: [
      sportsFeedClientProvider.overrideWithValue(feed),
      sportsFollowStoreProvider.overrideWithValue(
        SportsFollowStore(() async => prefs),
      ),
      sportsGuideSourceProvider.overrideWithValue(guideSource),
      sportsClockProvider.overrideWithValue(() => clock),
      sportsLeaguesProvider.overrideWithValue(leagues),
      ...sportsLeagueFilterOverrides(leaguePrefs),
    ],
    child: RepaintBoundary(
      key: sportsBoardCaptureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(body: SportsBoardView(onPlay: played.add)),
      ),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }
}
