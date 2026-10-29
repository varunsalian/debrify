import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:flutter_test/flutter_test.dart';

String _body(String name) =>
    File('test/features/sports/fixtures/$name').readAsStringSync();

final DateTime _now = DateTime.utc(2026, 10, 29, 10);

void main() {
  late List<Uri> requested;
  late String Function(Uri uri) serve;
  late SportsFeedClient client;

  setUp(() {
    requested = [];
    serve = (_) => jsonEncode({'events': <Object>[]});
    client = SportsFeedClient(
      fetch: (uri) async {
        requested.add(uri);
        return serve(uri);
      },
      clock: () => _now,
    );
  });

  test('header URI', () {
    expect(
      SportsFeedClient.espnHeaderUri('cricket').toString(),
      'https://site.api.espn.com/apis/v2/scoreboard/header?sport=cricket&lang=en&region=in',
    );
  });

  group('tennis is tournament-wide', () {
    test('one request for the whole window, events trimmed to it', () async {
      serve = (_) => _body('espn_atp.json');
      final events = await client.fetchLeague(
        sportsLeagueById('atp')!,
        fromUtc: DateTime.utc(2026, 10, 28),
        toUtc: DateTime.utc(2026, 10, 29, 23, 59),
      );
      expect(requested, hasLength(1));
      expect(requested.single.queryParameters['dates'], '20261028');
      expect(
        requested.single.path,
        '/apis/site/v2/sports/tennis/atp/scoreboard',
      );
      expect(events, isNotEmpty);
      for (final e in events) {
        expect(
          e.start.isBefore(DateTime.utc(2026, 10, 28)),
          isFalse,
          reason: e.id,
        );
        expect(
          e.start.isAfter(DateTime.utc(2026, 10, 29, 23, 59)),
          isFalse,
          reason: e.id,
        );
      }
      expect(events.map((e) => e.id), contains('185198'));
      expect(events.map((e) => e.id), isNot(contains('187149')));
    });

    test(
      'a second window over the same first day is served from cache',
      () async {
        serve = (_) => _body('espn_atp.json');
        final league = sportsLeagueById('atp')!;
        await client.fetchLeague(
          league,
          fromUtc: DateTime.utc(2026, 10, 28),
          toUtc: DateTime.utc(2026, 11, 3),
        );
        await client.fetchLeague(
          league,
          fromUtc: DateTime.utc(2026, 10, 28, 6),
          toUtc: DateTime.utc(2026, 10, 28, 20),
        );
        expect(requested, hasLength(1));
      },
    );
  });

  group('international cricket is discovered', () {
    final intl = sportsLeagueById('intl-cricket')!;

    setUp(() {
      serve = (uri) {
        if (uri.path.endsWith('/scoreboard/header')) {
          return _body('espn_header_cricket.json');
        }
        if (uri.path.contains('/cricket/24203/')) {
          return _body('espn_cricket_test.json');
        }
        return jsonEncode({'events': <Object>[]});
      };
    });

    test('header once, then every series for every day', () async {
      final events = await client.fetchLeague(
        intl,
        fromUtc: DateTime.utc(2026, 10, 28),
        toUtc: DateTime.utc(2026, 10, 29, 23),
      );
      final headers = requested.where(
        (u) => u.path.endsWith('/scoreboard/header'),
      );
      expect(headers, hasLength(1));
      expect(headers.single, SportsFeedClient.espnHeaderUri('cricket'));
      final seriesDays = requested
          .where((u) => !u.path.endsWith('/scoreboard/header'))
          .map(
            (u) =>
                '${u.pathSegments[u.pathSegments.length - 2]}@${u.queryParameters['dates']}',
          )
          .toSet();
      expect(seriesDays, {
        for (final id in ['24756', '24203', '24799', '1550706', '19439'])
          for (final day in ['20261028', '20261029']) '$id@$day',
      });
      expect(events.map((e) => e.id), ['1525661']);
      expect(events.single.leagueId, 'intl-cricket');
      expect(events.single.homeScoreText, '329');
    });

    test('the header is cached like any other feed', () async {
      await client.fetchLeague(
        intl,
        fromUtc: DateTime.utc(2026, 10, 29),
        toUtc: DateTime.utc(2026, 10, 29, 23),
      );
      await client.fetchLeague(
        intl,
        fromUtc: DateTime.utc(2026, 10, 29),
        toUtc: DateTime.utc(2026, 10, 29, 23),
      );
      expect(
        requested.where((u) => u.path.endsWith('/scoreboard/header')),
        hasLength(1),
      );
    });

    test('a failing header with nothing cached throws', () async {
      client = SportsFeedClient(
        fetch: (uri) async => throw StateError('offline'),
        clock: () => _now,
      );
      await expectLater(
        client.fetchLeague(
          intl,
          fromUtc: DateTime.utc(2026, 10, 29),
          toUtc: DateTime.utc(2026, 10, 29, 23),
        ),
        throwsA(isA<SportsFeedException>()),
      );
    });

    test(
      'no international series means no events and no series requests',
      () async {
        serve = (uri) => jsonEncode({'sports': <Object>[]});
        final events = await client.fetchLeague(
          intl,
          fromUtc: DateTime.utc(2026, 10, 29),
          toUtc: DateTime.utc(2026, 10, 29, 23),
        );
        expect(events, isEmpty);
        expect(requested, hasLength(1));
      },
    );
  });

  test('ordinary ESPN leagues still request every day', () async {
    await client.fetchLeague(
      sportsLeagueById('epl')!,
      fromUtc: DateTime.utc(2026, 10, 28),
      toUtc: DateTime.utc(2026, 10, 30, 12),
    );
    expect(requested.map((u) => u.queryParameters['dates']), [
      '20261028',
      '20261029',
      '20261030',
    ]);
  });
}
