// Board-controller behaviour: the loading contract, feed merging and failure
// policy, guide matching, follow write-through, stale-result rejection and the
// refresh timer. Everything runs offline on a fixed clock: fixtures are served
// by a fake SportsFetch, follows live in an in-memory store and the guide is a
// fake source recording its queries.
import 'dart:async';
import 'dart:io';

import 'package:debrify/features/sports/application/sports_board_controller.dart';
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/features/sports/fixtures';

const loadFailed =
    "Couldn't load fixtures. Check your connection and try again.";

String fixture(String name) => File('$_fixtureDir/$name').readAsStringSync();

/// Fixed reference instant: 2026-10-28 20:00 UTC.
final DateTime _t0 = DateTime.utc(2026, 10, 28, 20);

final SportsLeague _ucl = sportsLeagueById('ucl')!;
final SportsLeague _epl = sportsLeagueById('epl')!;
final SportsLeague _nfl = sportsLeagueById('nfl')!;

/// The board the harness mounts unless a test narrows the catalog.
final List<SportsLeague> _defaultLeagues = [_ucl, _epl, _nfl];

/// `YYYYMMDD` of an instant, the way the feed client spells its window.
String _compactUtc(DateTime instant) {
  final utc = instant.toUtc();
  return '${utc.year}${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// Serves committed fixtures per league, never the network.
class FakeFetch {
  FakeFetch({Map<String, String> bodies = const {}, Set<String>? failing})
    : bodies = Map<String, String>.of(bodies),
      failing = failing ?? <String>{};

  /// Fixture body keyed by league id; a league without one fails.
  final Map<String, String> bodies;

  /// League ids whose feed is down.
  final Set<String> failing;

  /// Held response for the next call only, to make a refresh stale.
  Completer<String>? gate;

  final List<Uri> uris = [];

  int get callCount => uris.length;

  Future<String> respond(Uri uri) async {
    uris.add(uri);
    final held = gate;
    if (held != null) {
      gate = null;
      return held.future;
    }
    final leagueId = _leagueIdOf(uri);
    if (failing.contains(leagueId)) {
      throw SportsFeedException(uri, 'feed down');
    }
    final body = bodies[leagueId];
    if (body == null) throw SportsFeedException(uri, 'no fixture');
    return body;
  }

  static String? _leagueIdOf(Uri uri) {
    if (uri == SportsFeedClient.jolpicaSeasonUri) return 'f1';
    for (final league in kSportsLeagues) {
      final path = league.espnPath;
      if (path != null && uri.path.contains(path)) return league.id;
    }
    return null;
  }
}

class FakePrefs implements SportsPrefs {
  final Map<String, List<String>> lists = {};
  final Map<String, bool> flags = {};
  int writes = 0;

  @override
  List<String>? getStringList(String key) => lists[key];

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    writes++;
    lists[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => flags[key];

  @override
  Future<bool> setBool(String key, bool value) async {
    writes++;
    flags[key] = value;
    return true;
  }
}

class FakeGuideSource implements SportsGuideSource {
  SportsGuideSnapshot snapshot = SportsGuideSnapshot.empty;
  bool fail = false;
  final List<SportsGuideQuery> queries = [];

  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async {
    queries.add(query);
    if (fail) throw StateError('guide unavailable');
    return snapshot;
  }
}

/// One mounted board with all five dependencies overridden by fakes.
class BoardHarness {
  BoardHarness({
    Map<String, String> bodies = const {},
    Set<String>? failing,
    List<SportsLeague>? leagues,
  }) : fetch = FakeFetch(bodies: bodies, failing: failing),
       leagues = leagues ?? _defaultLeagues,
       session = (
         owner: ProfileSessionMemory.captureOwner(),
         viewIdentity: Object(),
       ) {
    container = ProviderContainer.test(
      overrides: [
        sportsFeedClientProvider.overrideWithValue(
          SportsFeedClient(fetch: fetch.respond, clock: () => clock),
        ),
        sportsFollowStoreProvider.overrideWithValue(
          SportsFollowStore(() async {
            if (failStoreRead) throw StateError('storage offline');
            return prefs;
          }),
        ),
        sportsGuideSourceProvider.overrideWithValue(guide),
        sportsClockProvider.overrideWithValue(() => clock),
        sportsLeaguesProvider.overrideWithValue(this.leagues),
      ],
    );
    subscription = container.listen(sportsBoardProvider(session), (_, _) {});
    controller = container.read(sportsBoardProvider(session).notifier);
  }

  final FakeFetch fetch;
  final List<SportsLeague> leagues;
  final SportsSession session;
  final FakePrefs prefs = FakePrefs();
  final FakeGuideSource guide = FakeGuideSource();

  late final ProviderContainer container;
  late final ProviderSubscription<SportsBoardState> subscription;
  late final SportsBoardController controller;

  /// Mutable so a test can move the whole board forward.
  DateTime clock = _t0;

  bool failStoreRead = false;

  SportsBoardState get state => container.read(sportsBoardProvider(session));

  List<String> get eventIds => [for (final e in state.events) e.id];

  void advance(Duration delta) => clock = clock.add(delta);

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

void main() {
  tearDown(ProfileSessionMemory.clearAll);

  test('a mounted board is loading and fetches nothing until asked', () {
    final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_finished.json')});
    addTearDown(h.dispose);
    expect(h.state.loading, isTrue);
    expect(h.state.events, isEmpty);
    expect(h.state.filter, SportsBoardFilter.week);
    expect(h.state.watch, isEmpty);
    expect(h.fetch.callCount, 0);
    expect(h.guide.queries, isEmpty);
    expect(h.prefs.writes, 0);
  });

  test(
    'refresh merges the catalog, sorted by start then id, and dedupes',
    () async {
      // A second catalog entry on the same ESPN feed must not double the board.
      const uclSecond = SportsLeague(
        id: 'ucl',
        name: 'Champions League, return leg',
        shortName: 'UCL2',
        sport: SportKind.soccer,
        espnPath: 'soccer/uefa.champions',
      );
      final h = BoardHarness(
        leagues: [_ucl, uclSecond, _epl],
        bodies: {
          'ucl': fixture('espn_ucl_finished.json'),
          'epl': fixture('espn_epl_scheduled.json'),
        },
      );
      addTearDown(h.dispose);
      await h.controller.refresh();
      expect(h.state.loading, isFalse);
      expect(h.state.error, isNull);
      expect(h.state.updatedAt, h.clock);
      expect(h.state.events, hasLength(8));
      expect(h.eventIds, [
        '401915395',
        '401915396',
        '401915312',
        '401915394',
        '401879248',
        '401879247',
        '401879249',
        '401879251',
      ]);
      expect(
        h.fetch.uris.where((u) => u.path.contains('uefa.champions')),
        hasLength(1),
      );
    },
  );

  test('the feed window is local yesterday to one week ahead', () async {
    final h = BoardHarness(
      leagues: [_epl],
      bodies: {'epl': fixture('espn_epl_scheduled.json')},
    );
    addTearDown(h.dispose);
    await h.controller.refresh();
    // Local midnight of the clock's day, one day back, in UTC.
    final from = DateTime(
      h.clock.year,
      h.clock.month,
      h.clock.day,
    ).subtract(const Duration(days: 1));
    expect([from.hour, from.minute, from.second], [0, 0, 0]);
    final dates = h.fetch.uris.single.queryParameters['dates'];
    expect(
      dates,
      '${_compactUtc(from)}-${_compactUtc(h.clock.add(const Duration(days: 7)))}',
    );
    expect(h.fetch.uris.single.queryParameters['dates'], endsWith('20261104'));
  });

  test('every league failing reports the error and keeps the board', () async {
    final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_finished.json')});
    addTearDown(h.dispose);
    await h.controller.refresh();
    expect(h.state.events, isNotEmpty);
    final before = h.state.events;
    // A new day asks for new feed windows, so nothing cached can cover a
    // failing league and every request genuinely fails.
    h.advance(const Duration(days: 1));
    h.fetch.failing.addAll(['ucl', 'epl', 'nfl']);
    await h.controller.refresh(force: true);
    expect(h.state.error, loadFailed);
    expect(h.state.events, same(before));
    expect(h.state.loading, isFalse);
  });

  test(
    'a first refresh with every league failing still leaves a usable board',
    () async {
      final h = BoardHarness(failing: {'ucl', 'epl', 'nfl'});
      addTearDown(h.dispose);
      await h.controller.refresh();
      expect(h.state.error, loadFailed);
      expect(h.state.events, isEmpty);
      expect(h.state.loading, isFalse);
      // A later good refresh clears the banner.
      h.fetch.failing.clear();
      h.fetch.bodies.addAll({'ucl': fixture('espn_ucl_finished.json')});
      await h.controller.refresh(force: true);
      expect(h.state.error, isNull);
      expect(h.state.events, isNotEmpty);
    },
  );

  test('one dead league contributes nothing and is not an error', () async {
    final h = BoardHarness(
      bodies: {
        'ucl': fixture('espn_ucl_finished.json'),
        'epl': fixture('espn_epl_scheduled.json'),
      },
      failing: {'nfl'},
    );
    addTearDown(h.dispose);
    await h.controller.refresh();
    expect(h.state.error, isNull);
    expect(h.state.loading, isFalse);
    expect(h.state.events.map((e) => e.leagueId).toSet(), {'ucl', 'epl'});
  });

  test('an unreadable store keeps the follows already on screen', () async {
    final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_finished.json')});
    addTearDown(h.dispose);
    h.prefs.lists[SportsFollowStore.leaguesKey] = ['ucl'];
    await h.controller.refresh();
    expect(h.state.follows.leagueIds, {'ucl'});
    h.failStoreRead = true;
    await h.controller.refresh(force: true);
    expect(h.state.follows.leagueIds, {'ucl'});
    expect(h.state.loading, isFalse);
    expect(h.state.error, isNull);
    expect(h.state.events, isNotEmpty);
  });

  test('the guide is asked only about near fixtures and fills watch', () async {
    final h = BoardHarness(
      bodies: {
        'ucl': fixture('espn_ucl_live.json'),
        'epl': fixture('espn_epl_scheduled.json'),
      },
    );
    addTearDown(h.dispose);
    // espn_ucl_live.json kicks off at 2026-10-21 16:45 UTC.
    final kickOff = DateTime.utc(2026, 10, 21, 16, 45);
    final listing = SportsGuideListing(
      channel: const SportsChannelRef(name: 'Sky Sports Main Event', url: 'a'),
      title: 'Manchester United v Como',
      start: kickOff,
      stop: kickOff.add(const Duration(hours: 2)),
    );
    h.guide.snapshot = SportsGuideSnapshot(
      listings: [listing],
      channels: const [SportsChannelRef(name: 'Paramount+ HD', url: 'b')],
      liveSportsListings: [listing],
    );
    await h.controller.refresh();

    final query = h.guide.queries.single;
    expect(query.nowUtc, h.clock);
    expect(query.fromUtc, h.clock.subtract(const Duration(hours: 3)));
    expect(query.toUtc, h.clock.add(const Duration(hours: 36)));
    expect(
      query.titleNeedles,
      containsAll(<String>['como', 'manchester united']),
    );
    expect(query.channelNeedles, contains('paramount'));
    // The EPL round is three days away: neither its teams nor its channels.
    expect(query.titleNeedles, isNot(contains('chelsea')));
    expect(query.channelNeedles, isNot(contains('peacock')));

    final live = h.state.events.firstWhere(
      (e) => e.status == SportsEventStatus.live,
    );
    expect(
      h.state.watchFor(live).guide.single.channel.name,
      'Sky Sports Main Event',
    );
    expect(h.state.watchFor(live).guide.single.listing, listing);
    expect(
      h.state.watchFor(live).possible.single.channel.name,
      'Paramount+ HD',
    );
    expect(h.state.liveSportsListings, [listing]);
    final epl = h.state.events.firstWhere((e) => e.leagueId == 'epl');
    expect(h.state.watch.containsKey('epl/${epl.id}'), isFalse);
  });

  test('a failing guide leaves the fixtures with no watch options', () async {
    final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_live.json')});
    addTearDown(h.dispose);
    h.guide.fail = true;
    await h.controller.refresh();
    expect(h.state.events, isNotEmpty);
    expect(h.state.error, isNull);
    expect(h.guide.queries, hasLength(1));
    expect(h.state.watch.values.every((o) => o.isEmpty), isTrue);
    expect(h.state.liveSportsListings, isEmpty);
  });

  test('follow changes publish at once and write through', () async {
    final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_finished.json')});
    addTearDown(h.dispose);
    await h.controller.toggleLeague('ucl');
    expect(h.state.follows.leagueIds, {'ucl'});
    expect(h.prefs.lists[SportsFollowStore.leaguesKey], ['ucl']);
    await h.controller.toggleLeague('ucl');
    expect(h.state.follows.leagueIds, isEmpty);
    expect(h.prefs.lists[SportsFollowStore.leaguesKey], isEmpty);
    await h.controller.toggleTeam('ucl:1');
    expect(h.state.follows.teamKeys, {'ucl:1'});
    expect(h.prefs.lists[SportsFollowStore.teamsKey], ['ucl:1']);
    await h.controller.setHideScores(true);
    expect(h.state.follows.hideScores, isTrue);
    expect(h.prefs.flags[SportsFollowStore.hideScoresKey], isTrue);
    // The next refresh reads the same choices back out of the store.
    await h.controller.refresh(force: true);
    expect(
      h.state.follows,
      const SportsFollows(teamKeys: {'ucl:1'}, hideScores: true),
    );
  });

  test(
    'a profile change stops follow writes but keeps the visible choice',
    () async {
      final h = BoardHarness();
      addTearDown(h.dispose);
      ProfileSessionMemory.clearAll();
      await h.controller.toggleLeague('ucl');
      await h.controller.toggleTeam('ucl:1');
      await h.controller.setHideScores(true);
      expect(h.state.follows.leagueIds, {'ucl'});
      expect(h.state.follows.teamKeys, {'ucl:1'});
      expect(h.state.follows.hideScores, isTrue);
      expect(h.prefs.writes, 0);
      expect(h.prefs.lists, isEmpty);
    },
  );

  test('a stale refresh publishes nothing', () async {
    final h = BoardHarness(
      bodies: {
        'ucl': fixture('espn_ucl_finished.json'),
        'epl': fixture('espn_epl_scheduled.json'),
        'nfl': fixture('espn_nfl_scheduled.json'),
      },
    );
    addTearDown(h.dispose);
    final gate = Completer<String>();
    h.fetch.gate = gate;
    final stale = h.controller.refresh();
    await pumpEventQueue();
    // A day later the board asks for different feeds, so the newer refresh is
    // not held by the same request.
    h.advance(const Duration(days: 1));
    await h.controller.refresh();
    final published = h.eventIds;
    expect(published, contains('401915395'));
    gate.complete(fixture('espn_nba.json'));
    await stale;
    expect(h.eventIds, published);
    expect(h.eventIds, isNot(contains('401909877')));
    expect(h.state.updatedAt, h.clock);
  });

  test('a profile switch during a refresh publishes nothing', () async {
    final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_finished.json')});
    addTearDown(h.dispose);
    final gate = Completer<String>();
    h.fetch.gate = gate;
    final pending = h.controller.refresh();
    await pumpEventQueue();
    ProfileSessionMemory.clearAll();
    gate.complete(fixture('espn_ucl_finished.json'));
    await pending;
    expect(h.state.loading, isTrue);
    expect(h.state.events, isEmpty);
    expect(h.state.updatedAt, isNull);
  });

  test(
    'setFilter changes the rows without touching feeds or the guide',
    () async {
      final h = BoardHarness(
        bodies: {'ucl': fixture('espn_ucl_finished.json')},
      );
      addTearDown(h.dispose);
      await h.controller.refresh();
      final fetched = h.fetch.callCount;
      final queried = h.guide.queries.length;
      h.controller.setFilter(SportsBoardFilter.following);
      expect(h.state.filter, SportsBoardFilter.following);
      expect(h.fetch.callCount, fetched);
      expect(h.guide.queries.length, queried);
      expect(h.prefs.writes, 0);
    },
  );

  test('a live board refreshes after 90 s, a quiet one after 15 min', () {
    fakeAsync((time) {
      final live = BoardHarness(bodies: {'ucl': fixture('espn_ucl_live.json')});
      unawaited(live.controller.refresh());
      time.flushMicrotasks();
      expect(live.state.loading, isFalse);
      final first = live.fetch.callCount;
      time.elapse(const Duration(seconds: 89));
      expect(live.fetch.callCount, first);
      time.elapse(const Duration(seconds: 1));
      expect(live.fetch.callCount, greaterThan(first));
      live.dispose();
    });
    fakeAsync((time) {
      final quiet = BoardHarness(
        bodies: {'epl': fixture('espn_epl_scheduled.json')},
      );
      unawaited(quiet.controller.refresh());
      time.flushMicrotasks();
      final first = quiet.fetch.callCount;
      time.elapse(const Duration(minutes: 14, seconds: 59));
      expect(quiet.fetch.callCount, first);
      time.elapse(const Duration(seconds: 1));
      expect(quiet.fetch.callCount, greaterThan(first));
      quiet.dispose();
    });
  });

  test('a newer refresh replaces the scheduled one', () {
    fakeAsync((time) {
      final h = BoardHarness(
        bodies: {'epl': fixture('espn_epl_scheduled.json')},
      );
      unawaited(h.controller.refresh());
      time.flushMicrotasks();
      final first = h.fetch.callCount;
      // A manual refresh ten minutes before the scheduled one takes over.
      time.elapse(const Duration(minutes: 5));
      unawaited(h.controller.refresh());
      time.flushMicrotasks();
      final afterManual = h.fetch.callCount;
      expect(afterManual, greaterThan(first));
      // The old 15-minute timer was retired when the manual refresh scheduled
      // its own, so nothing fires between here and the next quarter hour.
      time.elapse(const Duration(minutes: 10));
      expect(
        h.fetch.callCount,
        afterManual,
        reason: 'the retired timer was fired',
      );
      time.elapse(const Duration(minutes: 15));
      expect(h.fetch.callCount, greaterThan(afterManual));
      h.dispose();
    });
  });

  test('disposing the board cancels the scheduled refresh', () {
    fakeAsync((time) {
      final h = BoardHarness(bodies: {'ucl': fixture('espn_ucl_live.json')});
      unawaited(h.controller.refresh());
      time.flushMicrotasks();
      final first = h.fetch.callCount;
      h.dispose();
      time.elapse(const Duration(minutes: 20));
      expect(h.fetch.callCount, first);
    });
  });
}
