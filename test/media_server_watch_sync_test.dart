import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/media_server_watch_state.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('played history and an active rewatch bookmark are independent', () {
    for (final duration in [0, 100000]) {
      final rewatch = MediaServerWatchState(
        positionMs: 30000,
        durationMs: duration,
        played: true,
      );
      expect(rewatch.hasPartialBookmark, true);
    }
    for (final position in [0, 100000]) {
      final finished = MediaServerWatchState(
        positionMs: position,
        durationMs: 100000,
        played: true,
      );
      expect(finished.hasPartialBookmark, false);
    }
  });
  test('user data ticks, UTC date, clamping and malformed responses', () {
    final state = MediaServerWatchState.fromItem({
      'RunTimeTicks': 1000000000,
      'UserData': {
        'PlaybackPositionTicks': 1200000000,
        'Played': false,
        'LastPlayedDate': '2026-09-22T01:00:00Z',
      },
    });
    expect(state.durationMs, 100000);
    expect(state.positionMs, 100000);
    expect(
      state.lastPlayedAtMs,
      DateTime.utc(2026, 9, 22, 1).millisecondsSinceEpoch,
    );
    for (final data in [
      null,
      {},
      {'Played': false, 'PlaybackPositionTicks': -1},
    ]) {
      expect(
        () => MediaServerWatchState.fromItem({'UserData': data}),
        throwsFormatException,
      );
    }
  });

  test('import requires new progress or proven newer chronology', () {
    const state = MediaServerWatchState(
      positionMs: 30000,
      durationMs: 100000,
      played: false,
      lastPlayedAtMs: 200,
    );
    expect(
      state.shouldImport(localUpdatedAtMs: null, localPlayed: false),
      true,
    );
    expect(state.shouldImport(localUpdatedAtMs: 100, localPlayed: false), true);
    expect(
      state.shouldImport(localUpdatedAtMs: 200, localPlayed: false),
      false,
    );
    expect(
      state.shouldImport(localUpdatedAtMs: 300, localPlayed: false),
      false,
    );
    expect(
      state.shouldImport(localUpdatedAtMs: null, localPlayed: true),
      false,
    );
    const unknownDate = MediaServerWatchState(
      positionMs: 30000,
      durationMs: 100000,
      played: false,
    );
    expect(
      unknownDate.shouldImport(localUpdatedAtMs: 100, localPlayed: false),
      false,
    );
    const untouched = MediaServerWatchState(
      positionMs: 0,
      durationMs: 100000,
      played: false,
    );
    expect(
      untouched.shouldImport(localUpdatedAtMs: null, localPlayed: false),
      false,
    );
  });

  for (final kind in MediaServerKind.values) {
    final account = MediaServerAccount(
      kind: kind,
      baseUrl: 'https://server.example/base/',
      userId: 'user1',
      token: 'private-token',
      serverId: 'server1',
      deviceId: 'device1',
    );
    test(
      '${kind.label} reads per-user state and accepts empty check-in responses',
      () async {
        final requests = <http.Request>[];
        final client = MediaServerClient(
          client: MockClient((request) async {
            requests.add(request);
            expect(request.headers['X-Emby-Token'], account.token);
            expect(request.url.toString(), isNot(contains(account.token)));
            expect(request.followRedirects, false);
            if (request.url.path.endsWith('/Items/movie1')) {
              expect(request.url.path, '/base/Users/user1/Items/movie1');
              return http.Response(
                jsonEncode({
                  'Id': 'movie1',
                  'RunTimeTicks': 1000000000,
                  'UserData': {
                    'Played': false,
                    'PlaybackPositionTicks': 400000000,
                  },
                }),
                200,
              );
            }
            if (request.url.path.endsWith('/PlaybackInfo')) {
              return http.Response('{"PlaySessionId":"play1"}', 200);
            }
            expect(request.method, 'POST');
            return http.Response('', 204);
          }),
        );
        expect((await client.watchState(account, 'movie1')).positionMs, 40000);
        expect(await client.watchSessionId(account, 'movie1'), 'play1');
        final session = MediaServerWatchSession(
          client: client,
          account: account,
          itemId: 'movie1',
          mediaSourceId: 'version1',
          playSessionId: 'play1',
          authorize: () async {},
        );
        session.observe(positionMs: 40000, durationMs: 100000, playing: true);
        await session.close();
        final reports = requests.where((r) => r.method == 'POST').toList();
        expect(reports.first.url.path, '/base/Sessions/Playing');
        expect(reports.last.url.path, '/base/Sessions/Playing/Stopped');
        for (final request in reports) {
          final body = jsonDecode(request.body) as Map;
          expect(body['PositionTicks'], 400000000);
          expect(body['ItemId'], 'movie1');
          expect(body['MediaSourceId'], 'version1');
          expect(body['PlaySessionId'], 'play1');
          expect(body['PlayMethod'], 'DirectPlay');
        }
      },
    );

    test(
      '${kind.label} throttles, coalesces and orders pause/stop/completion',
      () async {
        var now = DateTime.utc(2026);
        final startEntered = Completer<void>();
        final startRelease = Completer<void>();
        final reports = <http.Request>[];
        final client = MediaServerClient(
          client: MockClient((request) async {
            reports.add(request);
            if (reports.length == 1) {
              startEntered.complete();
              await startRelease.future;
            }
            return http.Response('', 204);
          }),
        );
        final session = MediaServerWatchSession(
          client: client,
          account: account,
          itemId: 'movie1',
          mediaSourceId: 'version1',
          playSessionId: 'play1',
          authorize: () async {},
          now: () => now,
        );
        session.observe(positionMs: 1000, durationMs: 100000, playing: true);
        await startEntered.future;
        for (var i = 2; i < 100; i++) {
          now = now.add(const Duration(seconds: 1));
          session.observe(
            positionMs: i * 1000,
            durationMs: 100000,
            playing: true,
          );
        }
        session.observe(
          positionMs: 100000,
          durationMs: 100000,
          playing: false,
          completed: true,
        );
        final closing = session.close();
        startRelease.complete();
        await closing;
        expect(reports.map((r) => r.url.path), [
          '/base/Sessions/Playing',
          '/base/Sessions/Playing/Progress',
          '/base/Sessions/Playing/Stopped',
          '/base/Users/user1/PlayedItems/movie1',
        ]);
        expect(jsonDecode(reports[1].body)['PositionTicks'], 1000000000);
        expect(jsonDecode(reports[1].body)['EventName'], 'Pause');
        session.observe(positionMs: 5000, durationMs: 100000, playing: true);
        await session.close();
        expect(reports, hasLength(4));
      },
    );

    test(
      '${kind.label} revocation while start is in flight prevents later writes',
      () async {
        var allowed = true;
        final entered = Completer<void>();
        final release = Completer<void>();
        var sent = 0;
        final session = MediaServerWatchSession(
          client: MediaServerClient(
            client: MockClient((request) async {
              sent++;
              entered.complete();
              await release.future;
              return http.Response('', 204);
            }),
          ),
          account: account,
          itemId: 'movie1',
          mediaSourceId: 'version1',
          playSessionId: 'play1',
          authorize: () async {
            if (!allowed) throw StateError('Revoked');
          },
        );
        session.observe(positionMs: 5000, durationMs: 100000, playing: true);
        await entered.future;
        allowed = false;
        session.observe(
          positionMs: 100000,
          durationMs: 100000,
          playing: false,
          completed: true,
        );
        final closing = session.close();
        release.complete();
        await closing;
        expect(sent, 1);
      },
    );

    test(
      '${kind.label} unplayed candidates and paused loads do not mutate server',
      () async {
        var sent = 0;
        final session = MediaServerWatchSession(
          client: MediaServerClient(
            client: MockClient((request) async {
              sent++;
              return http.Response('', 204);
            }),
          ),
          account: account,
          itemId: 'movie1',
          mediaSourceId: 'version1',
          playSessionId: 'play1',
          authorize: () async {},
        );
        session.observe(positionMs: 0, durationMs: 100000, playing: true);
        session.observe(positionMs: 40000, durationMs: 100000, playing: false);
        await session.close();
        expect(sent, 0);
      },
    );

    test(
      '${kind.label} reporting failures do not escape the player lifecycle',
      () async {
        final session = MediaServerWatchSession(
          client: MediaServerClient(
            client: MockClient(
              (request) async => http.Response('unavailable', 503),
            ),
          ),
          account: account,
          itemId: 'movie1',
          mediaSourceId: 'version1',
          playSessionId: 'play1',
          authorize: () async {},
        );
        session.observe(positionMs: 5000, durationMs: 100000, playing: true);
        await expectLater(session.close(), completes);
      },
    );
  }
}
