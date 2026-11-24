// The stats page's data client: which leagues it serves, the URL it asks
// for, how long a summary stays cached per match state, request sharing, the
// stale fallback, and that a finished request never wedges the next one.
import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_match_stats_client.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sports_match_stats_fixtures.dart';

const _nfl = SportsMatchKey(leagueId: 'nfl', eventId: '401873066');

/// The finished NFL fixture re-labelled with ESPN's [state] (`pre`, `in`,
/// `post`).
String _body({String state = 'post', String? date, int pad = 0}) {
  final json =
      withoutArtwork(readSummaryFixture('espn_summary_nfl_final.json')) as Map;
  final competition =
      ((json['header'] as Map)['competitions'] as List).first as Map;
  final type = (competition['status'] as Map)['type'] as Map;
  type['state'] = state;
  type['completed'] = state == 'post';
  if (date != null) competition['date'] = date;
  // Unused bulk, to push a body past the isolate threshold.
  if (pad > 0) json['padding'] = 'x' * pad;
  return jsonEncode(json);
}

void main() {
  late DateTime now;
  late FakeSummaryFetch fetch;
  late SportsMatchStatsClient client;

  setUp(() {
    now = DateTime.utc(2030, 3, 3, 20);
    fetch = FakeSummaryFetch(_body());
    client = SportsMatchStatsClient(fetch: fetch.call, clock: () => now);
  });

  group('supported leagues', () {
    test('two-team ESPN leagues only', () {
      bool supported(String id) =>
          sportsMatchStatsSupported(sportsLeagueById(id));
      for (final id in ['nfl', 'nba', 'nhl', 'mlb', 'epl', 'ucl', 'urc']) {
        expect(supported(id), isTrue, reason: id);
      }
      // Tennis, fights, golf, racing and cricket summaries have other shapes;
      // F1 has no ESPN feed at all.
      for (final id in ['atp', 'ufc', 'pga', 'nascar', 'ipl', 'f1']) {
        expect(supported(id), isFalse, reason: id);
      }
      expect(sportsMatchStatsSupported(null), isFalse);
    });

    test('asks ESPN for the event under the league path', () {
      expect(
        SportsMatchStatsClient.summaryUri(_nfl).toString(),
        'https://site.api.espn.com/apis/site/v2/sports/football/nfl/summary'
        '?event=401873066',
      );
    });

    test('an unsupported league fails without a request', () async {
      const key = SportsMatchKey(leagueId: 'atp', eventId: '1');
      expect(SportsMatchStatsClient.summaryUri(key), isNull);
      await expectLater(client.load(key), throwsA(isA<SportsFeedException>()));
      expect(fetch.calls, isEmpty);
    });
  });

  group('cache lifetime follows the match state', () {
    Future<void> expectFetchesAfter(
      String state,
      Duration fresh,
      Duration stale,
    ) async {
      // Kick-off well ahead, so only the lifetime decides.
      fetch.body = _body(state: state, date: '2031-01-01T00:00Z');
      await client.load(_nfl);
      now = now.add(fresh);
      await client.load(_nfl);
      expect(fetch.calls, hasLength(1), reason: '$state still fresh');
      now = now.add(stale - fresh);
      await client.load(_nfl);
      expect(fetch.calls, hasLength(2), reason: '$state expired');
    }

    test('live: 20 seconds', () async {
      await expectFetchesAfter(
        'in',
        const Duration(seconds: 19),
        const Duration(seconds: 20),
      );
    });

    test('scheduled: 5 minutes', () async {
      await expectFetchesAfter(
        'pre',
        const Duration(minutes: 4),
        const Duration(minutes: 5),
      );
    });

    test('finished: 30 minutes', () async {
      await expectFetchesAfter(
        'post',
        const Duration(minutes: 29),
        const Duration(minutes: 30),
      );
    });
  });

  test('concurrent loads of one match share one request', () async {
    final gate = Completer<String>();
    final shared = SportsMatchStatsClient(
      fetch: (uri) {
        fetch.calls.add(uri);
        return gate.future;
      },
      clock: () => now,
    );
    final first = shared.load(_nfl);
    final second = shared.load(_nfl);
    gate.complete(_body());
    final results = await Future.wait([first, second]);
    expect(fetch.calls, hasLength(1));
    expect(identical(results[0], results[1]), isTrue);
  });

  test('a load after a finished one starts afresh, never hangs', () async {
    fetch.body = TimeoutException('offline');
    await expectLater(client.load(_nfl), throwsA(isA<SportsFeedException>()));
    fetch.body = _body();
    final stats = await client.load(_nfl).timeout(const Duration(seconds: 2));
    expect(stats.home.abbreviation, 'HOU');
    expect(fetch.calls, hasLength(2));
  });

  test('a failed refresh falls back to the last good copy', () async {
    fetch.body = _body(state: 'in');
    final first = await client.load(_nfl);
    now = now.add(const Duration(minutes: 1));
    fetch.body = TimeoutException('offline');
    final second = await client.load(_nfl);
    expect(fetch.calls, hasLength(2));
    expect(second, first);
  });

  test('a live copy stands in for a failed fetch only while recent', () async {
    fetch.body = _body(state: 'in');
    await client.load(_nfl);
    fetch.body = TimeoutException('offline');
    now = now.add(const Duration(minutes: 4));
    expect((await client.load(_nfl)).status, SportsEventStatus.live);
    now = now.add(const Duration(minutes: 2));
    await expectLater(client.load(_nfl), throwsA(isA<SportsFeedException>()));
  });

  test('a finished copy stands in for a failed fetch at any age', () async {
    await client.load(_nfl);
    fetch.body = TimeoutException('offline');
    now = now.add(const Duration(days: 1));
    expect((await client.load(_nfl)).status, SportsEventStatus.finished);
  });

  test('a preview goes stale at kick-off, however recent', () async {
    fetch.body = _body(state: 'pre', date: '2030-03-03T20:02Z');
    await client.load(_nfl);
    now = now.add(const Duration(minutes: 1));
    await client.load(_nfl);
    expect(fetch.calls, hasLength(1), reason: 'before kick-off: cached');
    now = now.add(const Duration(minutes: 1));
    await client.load(_nfl);
    expect(fetch.calls, hasLength(2), reason: 'kick-off reached: refetched');
  });

  test('a parser bug surfaces instead of hiding behind an old copy', () async {
    await client.load(_nfl);
    now = now.add(const Duration(hours: 1));
    fetch.body = StateError('bug');
    await expectLater(client.load(_nfl), throwsA(isA<StateError>()));
  });

  test('a body past the threshold parses in a worker isolate', () async {
    fetch.body = _body(pad: SportsMatchStatsClient.isolateParseThreshold);
    final stats = await client.load(_nfl);
    expect(stats.home.abbreviation, 'HOU');
    expect(stats.teamStats, isNotEmpty);
  });

  test('bodies that are not a match fail as feed errors', () async {
    fetch.body = 'not json';
    await expectLater(client.load(_nfl), throwsA(isA<SportsFeedException>()));
    fetch.body = jsonEncode({'header': {}});
    await expectLater(client.load(_nfl), throwsA(isA<SportsFeedException>()));
  });

  test('keeps only the most recent matches', () async {
    final small = SportsMatchStatsClient(
      fetch: fetch.call,
      clock: () => now,
      maxEntries: 2,
    );
    SportsMatchKey key(String id) =>
        SportsMatchKey(leagueId: 'nfl', eventId: id);
    await small.load(key('a'));
    await small.load(key('b'));
    await small.load(key('c'));
    expect(fetch.calls, hasLength(3));
    await small.load(key('c'));
    await small.load(key('b'));
    expect(fetch.calls, hasLength(3), reason: 'b and c are cached');
    await small.load(key('a'));
    expect(fetch.calls, hasLength(4), reason: 'a was evicted');
  });

  test('the parsed status drives the page', () async {
    fetch.body = _body(state: 'in');
    expect((await client.load(_nfl)).status, SportsEventStatus.live);
  });
}
