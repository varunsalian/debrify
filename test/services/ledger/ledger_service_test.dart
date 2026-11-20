import 'dart:convert';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/ledger/ledger_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _SignedInSession extends LedgerSession {
  bool signedIn = true;

  @override
  Future<bool> isAuthenticated({bool Function()? canContinue}) async =>
      signedIn && canContinue?.call() != false;

  @override
  Future<String?> accessToken() async => signedIn ? 'token' : null;

  @override
  Future<String?> renewAfterRejection(String rejectedToken) async => null;
}

Map<String, Object?> _show(String imdb, {String id = 'show-id'}) => {
  'kind': 'MEDIA_KIND_SHOW',
  'id': id,
  'name': imdb,
  'ids': {'imdb': imdb},
};

Map<String, Object?> _episode(String showImdb, int season, int number) => {
  'kind': 'MEDIA_KIND_EPISODE',
  'show': _show(showImdb),
  'season': season,
  'number': number,
};

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  late List<http.Request> requests;
  late Map<String, Object?> Function(http.Request) routes;
  late _SignedInSession session;
  late LedgerService service;

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileSessionMemory.debugReset();
    requests = [];
    session = _SignedInSession();
    service = LedgerService.forTesting(
      session: session,
      api: LedgerApi(
        tokens: session,
        baseUrl: 'https://ledger.test',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(routes(request)), 200);
        }),
      ),
    );
  });

  Map<String, Object?> watchedRoutes(
    http.Request request, {
    List<Object?> upNext = const [],
    List<Object?> hidden = const [],
  }) => switch (request.url.path) {
    '/v1/me/watched'
        when request.url.queryParameters['kind'] == 'MEDIA_KIND_MOVIE' =>
      {
        'items': [
          {
            'item': {
              'kind': 'MEDIA_KIND_MOVIE',
              'ids': {'imdb': 'tt0133093'},
            },
            'plays': 1,
          },
        ],
      },
    '/v1/me/watched' => {
      'items': [
        for (final imdb in ['tt1000001', 'tt1000002', 'tt1000003'])
          {
            'item': _show(imdb),
            'episodes': 1,
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1},
                ],
              },
            ],
          },
      ],
    },
    '/v1/me/up-next' => {'entries': upNext},
    '/v1/me/hidden' => {
      'items': [
        for (final item in hidden) {'item': item},
      ],
    },
    _ => <String, Object?>{},
  };

  group('fetchCompletedTitleIds', () {
    test('a watched show is caught up when Up Next does not list it', () async {
      routes = (r) => watchedRoutes(
        r,
        upNext: [
          {
            'item': _episode('tt1000001', 1, 2),
            'reason': 'UP_NEXT_REASON_NEXT',
          },
        ],
        hidden: [_show('tt1000003')],
      );
      final completed = (await service.fetchCompletedTitleIds())!;
      expect(completed.movies, {'tt0133093'});
      // tt1000001 still has a next episode; tt1000003 is hidden from Up Next,
      // so its absence there proves nothing.
      expect(completed.series, {'tt1000002'});
    });

    test(
      'a full Up Next page could be truncated: no series are claimed',
      () async {
        routes = (r) => watchedRoutes(
          r,
          upNext: [
            for (var i = 0; i < 100; i++)
              {
                'item': {
                  'kind': 'MEDIA_KIND_MOVIE',
                  'ids': {'imdb': 'tt${2000000 + i}'},
                },
                'reason': 'UP_NEXT_REASON_RESUME',
                'progress': 10,
              },
          ],
        );
        final completed = (await service.fetchCompletedTitleIds())!;
        expect(completed.movies, {'tt0133093'});
        expect(completed.series, isEmpty);
      },
    );

    test('signed out reads nothing and reports unknown', () async {
      session.signedIn = false;
      routes = (r) => watchedRoutes(r);
      expect(await service.fetchCompletedTitleIds(), isNull);
      expect(requests, isEmpty);
    });
  });

  test(
    'episode progress keeps the newest point per episode of that show',
    () async {
      routes = (_) => {
        'playback': [
          {
            'id': 'a',
            'item': _episode('tt1000001', 1, 2),
            'progress': 20,
            'updateTime': '2026-11-20T05:00:00Z',
          },
          {
            'id': 'b',
            'item': _episode('tt1000001', 1, 2),
            'progress': 45,
            'updateTime': '2026-11-20T06:00:00Z',
          },
          {
            'id': 'c',
            'item': _episode('tt9999999', 1, 2),
            'progress': 70,
            'updateTime': '2026-11-20T07:00:00Z',
          },
        ],
      };
      expect(await service.episodePlaybackProgress('TT1000001'), {'1_2': 45});
      final latest = (await service.latestEpisodePlayback('tt1000001'))!;
      expect((latest.season, latest.episode, latest.progress), (1, 2, 45));
      expect(
        requests.where((r) => r.url.path == '/v1/me/playback'),
        hasLength(1),
        reason: 'the cached list serves both reads',
      );
    },
  );

  test('deletePlayback removes only the matching episode points', () async {
    routes = (r) => r.method == 'GET'
        ? {
            'playback': [
              {
                'id': 'keep',
                'item': _episode('tt1000001', 1, 3),
                'progress': 5,
              },
              {
                'id': 'drop',
                'item': _episode('tt1000001', 1, 2),
                'progress': 5,
              },
            ],
          }
        : <String, Object?>{};
    final revision = service.revision.value;
    expect(
      await service.deletePlayback('tt1000001', season: 1, episode: 2),
      isTrue,
    );
    expect(requests.where((r) => r.method == 'DELETE').map((r) => r.url.path), [
      '/v1/me/playback/drop',
    ]);
    expect(service.revision.value, revision + 1);
  });

  test(
    'writes for ids the tracker cannot resolve never leave the app',
    () async {
      routes = (_) => {};
      expect(await service.markWatched('simkl:123', 'movie'), isFalse);
      expect(await service.markEpisodesWatched('', const []), isFalse);
      expect(requests, isEmpty);
    },
  );

  test('a scrobble checkpoint refreshes caches without announcing', () async {
    routes = (_) => {'action': 'SCROBBLE_ACTION_PAUSE'};
    final revision = service.revision.value;
    expect(
      await service.scrobble(LedgerScrobbleAction.pause, 'tt0133093', 40),
      isTrue,
    );
    expect(service.revision.value, revision);
    expect(
      await service.scrobble(LedgerScrobbleAction.stop, 'tt0133093', 95),
      isTrue,
    );
    expect(service.revision.value, revision + 1);
  });

  test('removing an up-next show hides it from progress', () async {
    routes = (_) => {};
    expect(
      await service.removeFromContinueWatching(
        imdbId: 'tt1000001',
        isMovie: false,
      ),
      isTrue,
    );
    final request = requests.single;
    expect(request.url.path, '/v1/me/hidden');
    expect(jsonDecode(request.body), {
      'section': 'HIDDEN_SECTION_PROGRESS',
      'items': [
        {
          'kind': 'MEDIA_KIND_SHOW',
          'ids': {'imdb': 'tt1000001'},
        },
      ],
    });
  });
}
