import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:flutter_test/flutter_test.dart';

String _body(String name) =>
    File('test/features/sports/fixtures/$name').readAsStringSync();

bool _isHeader(Uri u) => u.path.endsWith('/scoreboard/header');

String _seriesOf(Uri u) => u.pathSegments[u.pathSegments.length - 2];

void main() {
  late List<Uri> requested;
  late String Function(Uri uri) serve;
  late DateTime now;
  late SportsFeedClient client;

  setUp(() {
    requested = [];
    serve = (_) => jsonEncode({'events': <Object>[]});
    now = DateTime.utc(2026, 10, 29, 10);
    client = SportsFeedClient(
      fetch: (uri) async {
        requested.add(uri);
        return serve(uri);
      },
      clock: () => now,
    );
  });

  test('header URI', () {
    expect(
      SportsFeedClient.espnHeaderUri('cricket').toString(),
      'https://site.api.espn.com/apis/v2/scoreboard/header'
      '?sport=cricket&lang=en&region=in',
    );
  });

  group('international cricket is discovered', () {
    final intl = sportsLeagueById('intl-cricket')!;

    setUp(() {
      serve = (uri) {
        if (_isHeader(uri)) return _body('espn_header_cricket.json');
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
      final headers = requested.where(_isHeader);
      expect(headers, hasLength(1));
      expect(headers.single, SportsFeedClient.espnHeaderUri('cricket'));
      final seriesDays = requested
          .where((u) => !_isHeader(u))
          .map((u) => '${_seriesOf(u)}@${u.queryParameters['dates']}')
          .toSet();
      expect(seriesDays, {
        for (final id in ['24756', '24203', '24799', '1550706', '19439'])
          for (final day in ['20261028', '20261029']) '$id@$day',
      });
      expect(events.map((e) => e.id), ['1525661']);
      expect(events.single.leagueId, 'intl-cricket');
      expect(events.single.homeScoreText, '329');
    });

    test('the header is cached for the schedule TTL', () async {
      Future<void> fetch() => client.fetchLeague(
        intl,
        fromUtc: DateTime.utc(2026, 10, 29),
        toUtc: DateTime.utc(2026, 10, 29, 23),
      );
      await fetch();
      await fetch();
      expect(requested.where(_isHeader), hasLength(1));
      now = now.add(const Duration(minutes: 16));
      await fetch();
      expect(requested.where(_isHeader), hasLength(2));
    });

    test('series seen in the last 3 days survive a rest day', () async {
      var restDay = false;
      serve = (uri) {
        if (_isHeader(uri)) {
          return restDay
              ? jsonEncode({'sports': <Object>[]})
              : _body('espn_header_cricket.json');
        }
        return jsonEncode({'events': <Object>[]});
      };
      Future<void> fetch() => client.fetchLeague(
        intl,
        fromUtc: DateTime.utc(now.year, now.month, now.day),
        toUtc: now,
        force: true,
      );
      await fetch();
      restDay = true;
      now = now.add(const Duration(days: 2));
      requested.clear();
      await fetch();
      expect(requested.where((u) => !_isHeader(u)).map(_seriesOf).toSet(), {
        '24756',
        '24203',
        '24799',
        '1550706',
        '19439',
      });
      now = now.add(const Duration(days: 2));
      requested.clear();
      await fetch();
      expect(requested.where((u) => !_isHeader(u)), isEmpty);
    });

    test('a failing header with nothing remembered throws', () async {
      client = SportsFeedClient(
        fetch: (uri) async => throw StateError('offline'),
        clock: () => now,
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

  test('a manual refresh refetches the cricket series boards', () async {
    final intl = sportsLeagueById('intl-cricket')!;
    serve = (uri) => uri.path.endsWith('/scoreboard/header')
        ? _body('espn_header_cricket.json')
        : jsonEncode({'events': <Object>[]});
    Future<void> fetch({bool force = false}) => client.fetchLeague(
      intl,
      fromUtc: DateTime.utc(2026, 10, 29),
      toUtc: DateTime.utc(2026, 10, 29, 23),
      force: force,
    );
    await fetch();
    final boards = requested.where((u) => !u.path.endsWith('/header')).length;
    await fetch();
    expect(requested.where((u) => !u.path.endsWith('/header')).length, boards);
    await fetch(force: true);
    expect(
      requested.where((u) => !u.path.endsWith('/header')).length,
      boards * 2,
    );
  });
}
