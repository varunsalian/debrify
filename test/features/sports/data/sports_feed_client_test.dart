// Feed-client behaviour: URI shape, TTL cache, force, stale-on-error and
// in-flight sharing, all offline through a fake SportsFetch and a fake clock.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/features/sports/fixtures';

String fixtureBody(String name) =>
    File('$_fixtureDir/$name').readAsStringSync();

/// Fixed reference instant: 2026-10-28 20:00 UTC.
final DateTime _t0 = DateTime.utc(2026, 10, 28, 20);

final SportsLeague _epl = sportsLeagueById('epl')!;
final SportsLeague _ucl = sportsLeagueById('ucl')!;
final SportsLeague _f1 = sportsLeagueById('f1')!;

/// A league without any feed implementation (not in the catalog).
const _noFeedLeague = SportsLeague(
  id: 'tennis',
  name: 'Tennis',
  shortName: 'TEN',
  sport: SportKind.soccer,
);

/// Records every requested URI; body and error are programmable.
class _FakeFetch {
  final List<Uri> uris = [];

  Object? error;
  String Function(Uri uri)? bodyBuilder;

  int get callCount => uris.length;

  Future<String> call(Uri uri) async {
    uris.add(uri);
    final error = this.error;
    if (error != null) throw error;
    return (bodyBuilder ?? (_) => '{}')(uri);
  }
}

class _Harness {
  _Harness({this.scheduleTtl, this.liveTtl});

  final Duration? scheduleTtl;
  final Duration? liveTtl;

  late _FakeFetch fetch;
  late DateTime fakeNow;
  late SportsFeedClient client;

  void setUp() {
    fetch = _FakeFetch();
    fakeNow = _t0;
    client = SportsFeedClient(
      fetch: fetch.call,
      clock: () => fakeNow,
      scheduleTtl: scheduleTtl ?? const Duration(minutes: 15),
      liveTtl: liveTtl ?? const Duration(seconds: 90),
    );
  }

  void serve(String body) => fetch.bodyBuilder = (_) => body;

  void advance(Duration by) => fakeNow = fakeNow.add(by);
}

/// The standard EPL day window used by most cache/failure tests.
final DateTime _dayFrom = DateTime.utc(2026, 10, 31);
final DateTime _dayTo = DateTime.utc(2026, 10, 31, 23, 59);

Future<List<SportsEvent>> _fetchEpl(
  SportsFeedClient client, {
  bool force = false,
}) => client.fetchLeague(_epl, fromUtc: _dayFrom, toUtc: _dayTo, force: force);

Map<String, dynamic> _race(
  Object round,
  String date,
  String time, {
  Object season = '2026',
}) => {
  'season': '$season',
  'round': '$round',
  'raceName': 'Race $round',
  'date': date,
  'time': time,
};

String _seasonBody(List<Map<String, dynamic>> races) => jsonEncode({
  'MRData': {
    'RaceTable': {'season': '2026', 'Races': races},
  },
});

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness()..setUp();
  });

  Future<List<SportsEvent>> fetchEpl({bool force = false}) =>
      _fetchEpl(h.client, force: force);

  group('espnScoreboardUri', () {
    test('one UTC date becomes a single dates value', () {
      final uri = SportsFeedClient.espnScoreboardUri(
        _epl,
        DateTime.utc(2026, 10, 31, 0, 0),
        DateTime.utc(2026, 10, 31, 23, 59),
      );
      expect(
        uri.toString(),
        'https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1'
        '/scoreboard?dates=20261031&limit=200',
      );
    });

    test('spanning UTC days becomes a from-to range', () {
      final uri = SportsFeedClient.espnScoreboardUri(
        _ucl,
        DateTime.utc(2026, 10, 28, 23),
        DateTime.utc(2026, 11, 4, 1),
      );
      expect(
        uri.toString(),
        'https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions'
        '/scoreboard?dates=20261028-20261104&limit=200',
      );
    });

    test('window bounds are converted to UTC before formatting', () {
      // Same instant pair as the range test, expressed in local time zones.
      final from = DateTime.utc(2026, 10, 28, 23).toLocal();
      final to = DateTime.utc(2026, 11, 4, 1).toLocal();
      final uri = SportsFeedClient.espnScoreboardUri(_epl, from, to);
      expect(uri.queryParameters['dates'], '20261028-20261104');
      // Local instants on one UTC day keep the single-date form.
      final sameDay = SportsFeedClient.espnScoreboardUri(
        _epl,
        DateTime.utc(2026, 10, 31, 0, 30).toLocal(),
        DateTime.utc(2026, 10, 31, 23, 30).toLocal(),
      );
      expect(sameDay.queryParameters['dates'], '20261031');
    });

    test('month and day are zero padded', () {
      final uri = SportsFeedClient.espnScoreboardUri(
        sportsLeagueById('mlb')!,
        DateTime.utc(2027, 1, 5),
        DateTime.utc(2027, 1, 5, 12),
      );
      expect(uri.queryParameters['dates'], '20270105');
      expect(uri.path, '/apis/site/v2/sports/baseball/mlb/scoreboard');
    });

    test('leagues without an ESPN path throw ArgumentError', () {
      expect(
        () => SportsFeedClient.espnScoreboardUri(
          _f1,
          DateTime.utc(2026, 10, 28),
          DateTime.utc(2026, 11, 4),
        ),
        throwsArgumentError,
      );
    });
  });

  group('fetchLeague basics', () {
    test('ESPN body is parsed and requested at the scoreboard URI', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      final events = await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      expect(h.fetch.uris, [
        SportsFeedClient.espnScoreboardUri(
          _epl,
          DateTime.utc(2026, 10, 31),
          DateTime.utc(2026, 10, 31, 23, 59),
        ),
      ]);
      expect(events, hasLength(4));
      expect(events.first.start, DateTime.utc(2026, 10, 31, 12, 30));
      expect(events.first.isTeamEvent, isTrue);
    });

    test('results are sorted by start, then id', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      final events = await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      expect(events.map((e) => e.id), [
        '401879248',
        '401879247',
        '401879249',
        '401879251',
      ]);
    });

    test(
      'a league without any feed yields nothing and never fetches',
      () async {
        final events = await h.client.fetchLeague(
          _noFeedLeague,
          fromUtc: _t0,
          toUtc: _t0.add(const Duration(days: 1)),
        );
        expect(events, isEmpty);
        expect(h.fetch.callCount, 0);
      },
    );

    test('callers receive copies that cannot corrupt the cache', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      final first = await fetchEpl();
      first.clear();
      final second = await fetchEpl();
      expect(second, hasLength(4));
    });
  });

  group('cache TTL', () {
    test('a fresh scheduled entry is served from cache', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      h.advance(const Duration(minutes: 14, seconds: 59));
      final again = await fetchEpl();
      expect(h.fetch.callCount, 1);
      expect(again, hasLength(4));
    });

    test('exactly the schedule TTL expires the entry', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      h.advance(const Duration(minutes: 15));
      await fetchEpl();
      expect(h.fetch.callCount, 2);
    });

    test('a cached live list expires on the live TTL', () async {
      h.serve(fixtureBody('espn_ucl_live.json'));
      await h.client.fetchLeague(
        _ucl,
        fromUtc: DateTime.utc(2026, 10, 21),
        toUtc: DateTime.utc(2026, 10, 21, 23, 59),
      );
      h.advance(const Duration(seconds: 89));
      await h.client.fetchLeague(
        _ucl,
        fromUtc: DateTime.utc(2026, 10, 21),
        toUtc: DateTime.utc(2026, 10, 21, 23, 59),
      );
      expect(h.fetch.callCount, 1);
      h.advance(const Duration(seconds: 1));
      await h.client.fetchLeague(
        _ucl,
        fromUtc: DateTime.utc(2026, 10, 21),
        toUtc: DateTime.utc(2026, 10, 21, 23, 59),
      );
      expect(h.fetch.callCount, 2);
    });

    test('TTLs are constructor configurable', () async {
      h = _Harness(
        scheduleTtl: Duration(seconds: 30),
        liveTtl: Duration(seconds: 5),
      )..setUp();
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      h.advance(const Duration(seconds: 29));
      await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      expect(h.fetch.callCount, 1);
      h.advance(const Duration(seconds: 1));
      await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      expect(h.fetch.callCount, 2);
    });

    test('cache entries are keyed per request URI', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 11, 1),
        toUtc: DateTime.utc(2026, 11, 1, 23, 59),
      );
      expect(h.fetch.callCount, 2);
      await fetchEpl();
      expect(h.fetch.callCount, 2);
      expect(h.fetch.uris.first, isNot(h.fetch.uris[1]));
    });

    test('force refetches even a fresh entry', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      final forced = await fetchEpl();
      expect(h.fetch.callCount, 1);
      final refetched = await fetchEpl(force: true);
      expect(h.fetch.callCount, 2);
      expect(refetched.map((e) => e.id), forced.map((e) => e.id));
    });
  });

  group('failure handling', () {
    test('a failed fetch after a success serves the stale cache', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      h.advance(const Duration(hours: 2));
      h.fetch.error = StateError('offline');
      final stale = await fetchEpl();
      expect(h.fetch.callCount, 2);
      expect(stale.map((e) => e.id), contains('401879248'));
    });

    test('a malformed body after a success serves the stale cache', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      h.advance(const Duration(hours: 1));
      h.serve('<html>rate limited</html>');
      final stale = await fetchEpl();
      expect(stale, hasLength(4));
    });

    test('a failed fetch leaves the cache intact for later retries', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await fetchEpl();
      h.advance(const Duration(hours: 2));
      h.fetch.error = StateError('offline');
      await fetchEpl();
      h.fetch.error = null;
      final fresh = await fetchEpl();
      expect(h.fetch.callCount, 3);
      expect(fresh, hasLength(4));
    });

    test(
      'invalid JSON with nothing cached throws SportsFeedException',
      () async {
        h.serve('not json at all');
        await expectLater(
          fetchEpl(),
          throwsA(
            isA<SportsFeedException>().having(
              (e) => e.message,
              'message',
              contains('not JSON'),
            ),
          ),
        );
      },
    );

    test('a transport error with nothing cached becomes a '
        'SportsFeedException carrying the URI', () async {
      h.fetch.error = TimeoutException('slow');
      final expectedUri = SportsFeedClient.espnScoreboardUri(
        _epl,
        DateTime.utc(2026, 10, 31),
        DateTime.utc(2026, 10, 31, 23, 59),
      );
      await expectLater(
        fetchEpl(),
        throwsA(
          isA<SportsFeedException>()
              .having((e) => e.uri, 'uri', expectedUri)
              .having(
                (e) => e.message,
                'message',
                contains('TimeoutException'),
              ),
        ),
      );
    });

    test(
      'a SportsFeedException from the fetcher is rethrown unchanged',
      () async {
        final uri = SportsFeedClient.espnScoreboardUri(
          _epl,
          DateTime.utc(2026, 10, 31),
          DateTime.utc(2026, 10, 31, 23, 59),
        );
        final original = SportsFeedException(uri, 'HTTP 503');
        h.fetch.error = original;
        await expectLater(fetchEpl(), throwsA(same(original)));
      },
    );

    test('SportsFeedException toString names the uri and message', () {
      final error = SportsFeedException(
        Uri.parse('https://site.api.espn.com/x'),
        'HTTP 500',
      );
      expect(
        error.toString(),
        'SportsFeedException(https://site.api.espn.com/x): HTTP 500',
      );
    });
  });

  group('in-flight sharing', () {
    test('concurrent calls for one URI share a single fetch', () async {
      final gate = Completer<String>();
      final uris = <Uri>[];
      final client = SportsFeedClient(
        fetch: (uri) {
          uris.add(uri);
          return gate.future;
        },
        clock: () => h.fakeNow,
      );
      final from = DateTime.utc(2026, 10, 31);
      final to = DateTime.utc(2026, 10, 31, 23, 59);
      final first = client.fetchLeague(_epl, fromUtc: from, toUtc: to);
      final second = client.fetchLeague(_epl, fromUtc: from, toUtc: to);
      gate.complete(fixtureBody('espn_epl_scheduled.json'));
      final results = await Future.wait([first, second]);
      expect(uris, hasLength(1));
      expect(results[0], hasLength(4));
      expect(results[1].map((e) => e.id), results[0].map((e) => e.id));
    });

    test('concurrent callers for one URI all see the failure', () async {
      final gate = Completer<String>();
      final client = SportsFeedClient(
        fetch: (_) => gate.future,
        clock: () => h.fakeNow,
      );
      final from = DateTime.utc(2026, 10, 31);
      final to = DateTime.utc(2026, 10, 31, 23, 59);
      final first = client.fetchLeague(_epl, fromUtc: from, toUtc: to);
      final second = client.fetchLeague(_epl, fromUtc: from, toUtc: to);
      gate.completeError(StateError('offline'));
      await expectLater(first, throwsA(isA<SportsFeedException>()));
      await expectLater(second, throwsA(isA<SportsFeedException>()));
    });

    test('the in-flight slot is released so later calls refetch', () async {
      h.serve(fixtureBody('espn_epl_scheduled.json'));
      await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      h.advance(const Duration(minutes: 15));
      await h.client.fetchLeague(
        _epl,
        fromUtc: DateTime.utc(2026, 10, 31),
        toUtc: DateTime.utc(2026, 10, 31, 23, 59),
      );
      expect(h.fetch.callCount, 2);
    });
  });

  group('F1 season feed', () {
    Future<List<SportsEvent>> fetchF1({
      DateTime? fromUtc,
      DateTime? toUtc,
      bool force = false,
    }) => h.client.fetchLeague(
      _f1,
      fromUtc: fromUtc ?? DateTime.utc(2026, 10, 28),
      toUtc: toUtc ?? DateTime.utc(2026, 12, 31),
      force: force,
    );

    test(
      'the season URI is fetched and parsed with the injected clock',
      () async {
        h.serve(fixtureBody('jolpica_f1_season.json'));
        final events = await fetchF1();
        expect(h.fetch.uris, [SportsFeedClient.jolpicaSeasonUri]);
        expect(events, hasLength(4));
        expect(events.first.id, 'f1-2026-20');
        expect(events.first.title, 'Brazilian Grand Prix');
        expect(events.first.status, SportsEventStatus.scheduled);
      },
    );

    test(
      'only races inside [from - 3h, to] are kept, bounds inclusive',
      () async {
        h.serve(fixtureBody('jolpica_f1_season.json'));
        final brazil = DateTime.utc(2026, 11, 8, 17);
        // from - 3h lands exactly on the Brazilian start -> included.
        final atEdge = await fetchF1(
          fromUtc: brazil.add(const Duration(hours: 3)),
          toUtc: DateTime.utc(2026, 11, 29, 16),
        );
        expect(atEdge.map((e) => e.id), [
          'f1-2026-20',
          'f1-2026-21',
          'f1-2026-22',
        ]);
        expect(h.fetch.callCount, 1);
        // One millisecond later the race is outside the window.
        final afterEdge = await fetchF1(
          fromUtc: brazil.add(const Duration(hours: 3, milliseconds: 1)),
          toUtc: DateTime.utc(2026, 11, 29, 16),
        );
        expect(afterEdge.map((e) => e.id), ['f1-2026-21', 'f1-2026-22']);
        // toUtc exactly at a race start keeps it; a moment earlier drops it.
        final upToQatar = await fetchF1(
          fromUtc: DateTime.utc(2026, 11, 1),
          toUtc: DateTime.utc(2026, 11, 29, 16),
        );
        expect(upToQatar.last.id, 'f1-2026-22');
        final beforeQatar = await fetchF1(
          fromUtc: DateTime.utc(2026, 11, 1),
          toUtc: DateTime.utc(2026, 11, 29, 15, 59, 59),
        );
        expect(beforeQatar.map((e) => e.id), ['f1-2026-20', 'f1-2026-21']);
        // The window filter never refetched the season.
        expect(h.fetch.callCount, 1);
      },
    );

    test('the cache holds the whole season for narrower windows', () async {
      h.serve(fixtureBody('jolpica_f1_season.json'));
      final wide = await fetchF1();
      expect(wide, hasLength(4));
      final narrow = await fetchF1(
        fromUtc: DateTime.utc(2026, 12, 1),
        toUtc: DateTime.utc(2026, 12, 31),
      );
      expect(h.fetch.callCount, 1);
      expect(narrow.map((e) => e.id), ['f1-2026-23']);
    });

    test('race status comes from the injected clock', () async {
      h.fakeNow = DateTime.utc(2026, 11, 8, 18);
      h.serve(fixtureBody('jolpica_f1_season.json'));
      final events = await fetchF1();
      final brazil = events.firstWhere((e) => e.id == 'f1-2026-20');
      expect(brazil.status, SportsEventStatus.live);
      expect(brazil.statusLabel, 'Live');
      final abuDhabi = events.firstWhere((e) => e.id == 'f1-2026-23');
      expect(abuDhabi.status, SportsEventStatus.scheduled);
    });

    test('a cached live season expires on the live TTL', () async {
      h.fakeNow = DateTime.utc(2026, 11, 8, 18);
      h.serve(fixtureBody('jolpica_f1_season.json'));
      await fetchF1();
      h.advance(const Duration(seconds: 89));
      await fetchF1();
      expect(h.fetch.callCount, 1);
      h.advance(const Duration(seconds: 1));
      await fetchF1();
      expect(h.fetch.callCount, 2);
    });

    test('stale F1 fallback still applies the per-call window', () async {
      h.serve(fixtureBody('jolpica_f1_season.json'));
      await fetchF1();
      h.advance(const Duration(hours: 16));
      h.fetch.error = StateError('offline');
      final stale = await fetchF1(
        fromUtc: DateTime.utc(2026, 11, 20),
        toUtc: DateTime.utc(2026, 11, 30),
      );
      expect(h.fetch.callCount, 2);
      expect(stale.map((e) => e.id), ['f1-2026-21', 'f1-2026-22']);
    });

    test('cached and stale results are sorted by start, then id', () async {
      h.serve(
        _seasonBody([
          _race(2, '2026-03-01', '12:00:00Z'),
          _race(3, '2026-02-01', '12:00:00Z'),
          _race(1, '2026-02-01', '12:00:00Z'),
        ]),
      );
      final events = await fetchF1(
        fromUtc: DateTime.utc(2026, 1, 1),
        toUtc: DateTime.utc(2026, 12, 31),
      );
      expect(events.map((e) => e.id), ['f1-2026-1', 'f1-2026-3', 'f1-2026-2']);
    });
  });
}
