import 'dart:convert';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/ledger/models/ledger_media.dart';
import 'package:debrify/features/ledger/models/ledger_tracking.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Token source double: hands out [token] and, after a 401, [renewed].
class _Tokens implements LedgerTokenSource {
  _Tokens(this.token, {this.renewed});
  String? token;
  String? renewed;
  final rejected = <String>[];

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> renewAfterRejection(String rejectedToken) async {
    rejected.add(rejectedToken);
    token = renewed;
    return renewed;
  }
}

// Recorded from the live API (debrify-api.garib.dev, 2026-11-20).
const _episodeJson = {
  'kind': 'MEDIA_KIND_EPISODE',
  'id': '01a1f52e-8a18-76a9-9c1c-ca19f17ca43e',
  'name': 'The Kingsroad',
  'ids': {'tvdb': '3436411', 'imdb': '', 'tmdb': '0'},
  'runtime': 55,
  'show': {
    'kind': 'MEDIA_KIND_SHOW',
    'id': '01a1f52e-8a13-712e-aa84-fc8456b3b233',
    'name': 'Game of Thrones',
    'slug': 'game-of-thrones',
    'year': 2011,
    'ids': {'tvdb': '121361', 'imdb': 'tt0944947', 'tmdb': '1399'},
    'status': 'Ended',
  },
  'season': 1,
  'number': 2,
  'aired': '2011-04-24',
};

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  late List<http.Request> requests;
  http.Response Function(http.Request request)? respond;

  LedgerApi api(_Tokens tokens) => LedgerApi(
    tokens: tokens,
    baseUrl: 'https://ledger.test',
    client: MockClient((request) async {
      requests.add(request);
      return respond!(request);
    }),
  );

  setUp(() {
    requests = [];
    respond = null;
  });

  test('scrobble sends the action, ref, clamped progress and source', () async {
    respond = (_) => http.Response(
      jsonEncode({'action': 'SCROBBLE_ACTION_STOP', 'watched': true}),
      200,
    );
    final result = await api(_Tokens('t')).scrobble(
      action: LedgerScrobbleAction.stop,
      item: LedgerMediaRef.episode('tt0944947', 1, 2),
      progress: 140,
    );
    expect(result.watched, isTrue);
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/me/scrobble');
    expect(request.headers['Authorization'], 'Bearer t');
    expect(jsonDecode(request.body), {
      'action': 'SCROBBLE_ACTION_STOP',
      'item': {
        'kind': 'MEDIA_KIND_EPISODE',
        'showIds': {'imdb': 'tt0944947'},
        'season': 1,
        'number': 2,
      },
      'progress': 100.0,
      'source': 'debrify',
    });
  });

  test('history add wraps items; history remove sends bare refs', () async {
    // The live API rejects a wrapped item on remove ("must not be in list
    // [0]") and a bare one on add ("value is required").
    respond = (_) => http.Response('{}', 200);
    final client = api(_Tokens('t'));
    await client.addHistory([LedgerMediaRef.movie('tt0133093')]);
    await client.removeHistory([LedgerMediaRef.movie('tt0133093')]);
    expect(jsonDecode(requests[0].body)['items'], [
      {
        'item': {
          'kind': 'MEDIA_KIND_MOVIE',
          'ids': {'imdb': 'tt0133093'},
        },
      },
    ]);
    expect(requests[1].url.path, '/v1/me/history:remove');
    expect(jsonDecode(requests[1].body)['items'], [
      {
        'kind': 'MEDIA_KIND_MOVIE',
        'ids': {'imdb': 'tt0133093'},
      },
    ]);
  });

  test('a 401 renews once and retries with the new token', () async {
    final tokens = _Tokens('old', renewed: 'new');
    respond = (request) => request.headers['Authorization'] == 'Bearer old'
        ? http.Response('{"code":16}', 401)
        : http.Response(jsonEncode({'playback': []}), 200);
    expect(await api(tokens).playback(), isEmpty);
    expect(tokens.rejected, ['old']);
    expect(requests.map((r) => r.headers['Authorization']), [
      'Bearer old',
      'Bearer new',
    ]);
  });

  test('a 401 that cannot renew fails without a second request', () async {
    final tokens = _Tokens('old');
    respond = (_) => http.Response('{"code":16}', 401);
    await expectLater(
      api(tokens).upNext(),
      throwsA(
        isA<LedgerApiException>().having((e) => e.unauthorized, '', true),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('signed out never reaches the network', () async {
    await expectLater(
      api(_Tokens(null)).watchlist(),
      throwsA(isA<LedgerApiException>()),
    );
    expect(requests, isEmpty);
  });

  test('status sends the ref as dotted query fields; 404 is null', () async {
    respond = (_) => http.Response('{"code":5}', 404);
    expect(
      await api(_Tokens('t')).status(LedgerMediaRef.episode('tt1', 2, 3)),
      isNull,
    );
    expect(requests.single.url.queryParameters, {
      'item.kind': 'MEDIA_KIND_EPISODE',
      'item.showIds.imdb': 'tt1',
      'item.season': '2',
      'item.number': '3',
    });
  });

  test('up next parses resume and next entries from live shapes', () async {
    respond = (_) => http.Response(
      jsonEncode({
        'entries': [
          {
            'item': _episodeJson,
            'reason': 'UP_NEXT_REASON_NEXT',
            'aired': 73,
            'completed': 2,
          },
          {
            'item': {
              'kind': 'MEDIA_KIND_MOVIE',
              'name': 'The Matrix',
              'ids': {'tvdb': '169', 'imdb': 'tt0133093'},
            },
            'reason': 'UP_NEXT_REASON_RESUME',
            'progress': 42,
            'playbackId': 'pb1',
          },
          {'item': 'garbage'},
        ],
      }),
      200,
    );
    final entries = await api(_Tokens('t')).upNext();
    expect(entries, hasLength(2));
    expect(entries[0].reason, LedgerUpNextReason.next);
    expect(entries[0].item.titleImdbId, 'tt0944947');
    expect(entries[0].item.ids.imdb, isNull, reason: 'empty imdb dropped');
    expect(entries[0].item.ids.tmdb, isNull, reason: 'zero tmdb dropped');
    expect(entries[1].reason, LedgerUpNextReason.resume);
    expect(entries[1].progress, 42);
    expect(entries[1].playbackId, 'pb1');
  });

  test('watched shows expose their episodes as season/number pairs', () async {
    respond = (_) => http.Response(
      jsonEncode({
        'items': [
          {
            'item': _episodeJson['show'],
            'plays': 1,
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 2, 'plays': 1},
                  {'number': 0},
                ],
              },
            ],
          },
        ],
      }),
      200,
    );
    final shows = await api(_Tokens('t')).watched(LedgerMediaKind.show);
    expect(requests.single.url.queryParameters['includeEpisodes'], 'true');
    expect(shows.single.episodes.map((e) => '${e.season}_${e.episode}'), [
      '1_2',
    ]);
  });

  test('non-finite proto floats are not progress', () {
    expect(ledgerPercent('NaN'), isNull);
    expect(ledgerPercent('Infinity'), isNull);
    expect(ledgerPercent(250), 100);
    expect(ledgerPercent(-1), 0);
  });
}
