import 'dart:convert';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/player_launch/data/native_ledger_session.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/ledger/ledger_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Session extends LedgerSession {
  @override
  Future<bool> isAuthenticated({bool Function()? canContinue}) async => true;
  @override
  Future<String?> accessToken() async => 't';
  @override
  Future<String?> renewAfterRejection(String rejectedToken) async => null;
}

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  late List<Map<String, dynamic>> sent;

  setUp(() {
    sent = [];
    final session = _Session();
    NativeLedgerSession.debugService = LedgerService.forTesting(
      session: session,
      api: LedgerApi(
        tokens: session,
        baseUrl: 'https://ledger.test',
        client: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }),
      ),
    );
    NativeLedgerSession.reset();
  });

  tearDown(() {
    NativeLedgerSession.reset();
    NativeLedgerSession.debugService = null;
  });

  Future<List<String>> actions() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return [for (final body in sent) body['action'] as String];
  }

  const movie = NativeLedgerTarget(
    enabled: true,
    imdbId: 'tt0133093',
    isSeries: false,
  );
  const series = NativeLedgerTarget(
    enabled: true,
    imdbId: 'tt0944947',
    isSeries: true,
  );

  void ping(
    NativeLedgerTarget target,
    double progress, {
    bool playing = true,
    bool completed = false,
    int? season,
    int? episode,
  }) => NativeLedgerSession.onProgress(
    target,
    progress: progress,
    isPlaying: playing,
    completed: completed,
    season: season,
    episode: episode,
  );

  test('play, repeated pings, pause, then exit after a pause', () async {
    ping(movie, 10);
    ping(movie, 11);
    ping(movie, 12, playing: false);
    NativeLedgerSession.onExit(movie);
    expect(await actions(), ['SCROBBLE_ACTION_START', 'SCROBBLE_ACTION_PAUSE']);
    expect(NativeLedgerSession.heartbeatTimer, isNull);
  });

  test('exit while playing sends one stop at the last position', () async {
    ping(movie, 30);
    NativeLedgerSession.onExit(movie);
    expect(await actions(), ['SCROBBLE_ACTION_START', 'SCROBBLE_ACTION_STOP']);
    expect(sent.last['progress'], 30);
  });

  test('completion stops once; past 80% a start becomes a stop', () async {
    ping(movie, 85);
    ping(movie, 99, completed: true);
    NativeLedgerSession.onExit(movie);
    expect(await actions(), ['SCROBBLE_ACTION_STOP']);
  });

  test('an episode switch finalises the previous episode', () async {
    ping(series, 40, season: 1, episode: 1);
    ping(series, 1, season: 1, episode: 2);
    final actionsSent = await actions();
    expect(actionsSent, [
      'SCROBBLE_ACTION_START',
      'SCROBBLE_ACTION_STOP',
      'SCROBBLE_ACTION_START',
    ]);
    expect(sent[1]['item'], {
      'kind': 'MEDIA_KIND_EPISODE',
      'showIds': {'imdb': 'tt0944947'},
      'season': 1,
      'number': 1,
    });
    expect(sent[1]['progress'], 40);
  });

  test(
    'an unresolved series episode or a disabled target sends nothing',
    () async {
      ping(series, 40);
      ping(
        const NativeLedgerTarget(
          enabled: false,
          imdbId: 'tt1',
          isSeries: false,
        ),
        40,
      );
      NativeLedgerSession.onExit(series);
      expect(await actions(), isEmpty);
    },
  );

  test('never started means nothing to stop on exit', () async {
    NativeLedgerSession.onExit(movie);
    expect(await actions(), isEmpty);
  });
}
