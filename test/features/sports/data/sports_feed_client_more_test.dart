import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:flutter_test/flutter_test.dart';

String _body(String name) =>
    File('test/features/sports/fixtures/$name').readAsStringSync();

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

  group('tennis is tournament-wide', () {
    final atp = sportsLeagueById('atp')!;

    test('first day and today only, events trimmed to the window', () async {
      serve = (_) => _body('espn_atp.json');
      final events = await client.fetchLeague(
        atp,
        fromUtc: DateTime.utc(2026, 10, 28),
        toUtc: DateTime.utc(2026, 10, 29, 23, 59),
      );
      // The payload is the whole tournament: the window's first day plus
      // today (a tournament can start inside the window) is enough.
      expect(requested.map((u) => u.queryParameters['dates']), [
        '20261028',
        '20261029',
      ]);
      expect(
        requested.every(
          (u) => u.path == '/apis/site/v2/sports/tennis/atp/scoreboard',
        ),
        isTrue,
      );
      expect(events, isNotEmpty);
      for (final e in events) {
        expect(e.start.isBefore(DateTime.utc(2026, 10, 28)), isFalse);
        expect(e.start.isAfter(DateTime.utc(2026, 10, 29, 23, 59)), isFalse);
      }
      expect(events.map((e) => e.id), contains('185198'));
      expect(events.map((e) => e.id), isNot(contains('187149')));
      // Same matches arrive in both payloads: no duplicates.
      final ids = events.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('a live match that began before the window is kept', () async {
      final json = jsonDecode(_body('espn_atp.json')) as Map<String, dynamic>;
      for (final e in (json['events'] as List).cast<Map<String, dynamic>>()) {
        for (final g in (e['groupings'] as List).cast<Map<String, dynamic>>()) {
          for (final c
              in (g['competitions'] as List).cast<Map<String, dynamic>>()) {
            if (c['id'] == '187149') {
              final type = (c['status'] as Map)['type'] as Map<String, dynamic>;
              type['state'] = 'in';
              type['name'] = 'STATUS_IN_PROGRESS';
              type['completed'] = false;
            }
          }
        }
      }
      serve = (_) => jsonEncode(json);
      final events = await client.fetchLeague(
        atp,
        fromUtc: DateTime.utc(2026, 10, 28),
        toUtc: DateTime.utc(2026, 10, 29, 23, 59),
      );
      expect(events.map((e) => e.id), contains('187149'));
    });

    test('overlapping windows reuse the cached days', () async {
      serve = (_) => _body('espn_atp.json');
      await client.fetchLeague(
        atp,
        fromUtc: DateTime.utc(2026, 10, 28),
        toUtc: DateTime.utc(2026, 11, 3),
      );
      await client.fetchLeague(
        atp,
        fromUtc: DateTime.utc(2026, 10, 28, 6),
        toUtc: DateTime.utc(2026, 10, 28, 20),
      );
      // Both windows need Oct 28 (first day) and Oct 29 (today).
      expect(requested, hasLength(2));
    });
  });

  group('multi-day live events do not keep a day hot', () {
    // A Ranji match that started two days ago is still "in" at stumps; its
    // day must not refetch every 90 s: the 15-minute rule applies.
    test(
      'a live event that started over 12 hours ago uses the schedule TTL',
      () async {
        serve = (_) => _body('espn_cricket_ranji.json');
        final ranji = sportsLeagueById('ranji')!;
        Future<void> fetch() => client.fetchLeague(
          ranji,
          fromUtc: DateTime.utc(2026, 10, 29),
          toUtc: DateTime.utc(2026, 10, 29, 23),
        );
        await fetch();
        now = now.add(const Duration(minutes: 5));
        await fetch();
        expect(requested, hasLength(1));
        now = now.add(const Duration(minutes: 11));
        await fetch();
        expect(requested, hasLength(2));
      },
    );

    test('a live event that started recently keeps the live TTL', () async {
      now = DateTime.utc(2026, 10, 27, 12); // the Test began 08:30 today
      serve = (_) => _body('espn_cricket_test.json');
      final ipl = sportsLeagueById('ipl')!;
      Future<void> fetch() => client.fetchLeague(
        ipl,
        fromUtc: DateTime.utc(2026, 10, 27),
        toUtc: DateTime.utc(2026, 10, 27, 23),
      );
      await fetch();
      now = now.add(const Duration(minutes: 2));
      await fetch();
      expect(requested, hasLength(2));
    });
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
