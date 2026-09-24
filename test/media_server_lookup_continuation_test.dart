import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MediaServerAccount account(MediaServerKind kind, {String token = 'test'}) =>
    MediaServerAccount(
      kind: kind,
      baseUrl: 'https://server.invalid/',
      userId: 'user',
      token: token,
      serverId: 'server',
      deviceId: 'device',
    );
Map<String, dynamic> movie(String id) => {
  'Id': id,
  'Name': id,
  'Type': 'Movie',
  'ProviderIds': {'Imdb': 'tt123'},
};
http.Response response(Object data) => http.Response(jsonEncode(data), 200);

void main() {
  for (final kind in MediaServerKind.values) {
    test(
      '${kind.name} combined episode boundaries and invalid ranges',
      () async {
        final client = MediaServerClient(
          client: MockClient(
            (r) async => response({
              'Items': r.url.path.endsWith('/Items')
                  ? [
                      {
                        'Id': 'series',
                        'Type': 'Series',
                        'ProviderIds': {'Imdb': 'tt123'},
                      },
                    ]
                  : [
                      {
                        'Id': 'combined',
                        'Type': 'Episode',
                        'ParentIndexNumber': 0,
                        'IndexNumber': 1,
                        'IndexNumberEnd': 3,
                      },
                      {
                        'Id': 'invalid',
                        'Type': 'Episode',
                        'ParentIndexNumber': 0,
                        'IndexNumber': 4,
                        'IndexNumberEnd': 2,
                      },
                      {
                        'Id': 'wrongseason',
                        'Type': 'Episode',
                        'ParentIndexNumber': 1,
                        'IndexNumber': 1,
                        'IndexNumberEnd': 3,
                      },
                    ],
            }),
          ),
        );
        addTearDown(client.close);
        for (final episode in [0, 1, 2, 3, 4]) {
          final found = await client.findItems(
            account(kind),
            id: 'tt123',
            isMovie: false,
            season: 0,
            episode: episode,
          );
          expect(
            found.map((i) => i['Id']),
            episode >= 1 && episode <= 3 ? ['combined'] : [],
          );
        }
      },
    );

    test(
      '${kind.name} timeout preserves matches and next client resumes',
      () async {
        final scope = Object();
        final offsets = <int>[];
        var failPage = true;
        MediaServerClient create() => MediaServerClient(
          client: MockClient((r) async {
            final offset = int.parse(r.url.queryParameters['StartIndex']!);
            offsets.add(offset);
            if (offset == 1 && failPage) throw TimeoutException('synthetic');
            return response({
              'TotalRecordCount': 2,
              'Items': [movie('movie$offset')],
            });
          }),
        );
        var incomplete = false;
        final first = create();
        final partial = await first.findItems(
          account(kind),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
          onIncomplete: () => incomplete = true,
        );
        first.close();
        expect(incomplete, isTrue);
        expect(partial.map((i) => i['Id']), ['movie0']);
        failPage = false;
        final retry = create();
        addTearDown(retry.close);
        final complete = await retry.findItems(
          account(kind),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
          onIncomplete: () => fail('Should complete'),
        );
        expect(complete.map((i) => i['Id']), ['movie0', 'movie1']);
        expect(offsets, [0, 1, 1]);
        await retry.findItems(
          account(kind),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
        );
        expect(offsets, [0, 1, 1]);
      },
    );
  }

  test(
    'empty completed lookups are refreshed when new content appears',
    () async {
      var present = false;
      var calls = 0;
      final scope = Object();
      final client = MediaServerClient(
        client: MockClient((r) async {
          calls++;
          return response({
            'Items': present ? [movie('new')] : [],
          });
        }),
      );
      addTearDown(client.close);
      expect(
        await client.findItems(
          account(MediaServerKind.jellyfin),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
        ),
        isEmpty,
      );
      present = true;
      expect(
        await client.findItems(
          account(MediaServerKind.jellyfin),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
        ),
        hasLength(1),
      );
      expect(calls, 2);
    },
  );

  test('Emby finds an episode beyond 1000 entries in one season', () async {
    final client = MediaServerClient(
      client: MockClient((r) async {
        if (r.url.path.endsWith('/Items')) {
          return response({
            'Items': [
              {
                'Id': 'series',
                'Type': 'Series',
                'ProviderIds': {'Imdb': 'tt123'},
              },
            ],
          });
        }
        final start = int.parse(r.url.queryParameters['StartIndex']!);
        return response({
          'TotalRecordCount': 1101,
          'Items': List.generate(
            start == 1100 ? 1 : 100,
            (i) => {
              'Id': 'e${start + i}',
              'Type': 'Episode',
              'ParentIndexNumber': 1,
              'IndexNumber': start + i + 1,
            },
          ),
        });
      }),
    );
    addTearDown(client.close);
    final found = await client.findItems(
      account(MediaServerKind.emby),
      id: 'tt123',
      isMovie: false,
      season: 1,
      episode: 1101,
    );
    expect(found.single['Id'], 'e1100');
  });

  test('Emby scans more than 1000 items with server-capped pages', () async {
    final client = MediaServerClient(
      client: MockClient((r) async {
        final start = int.parse(r.url.queryParameters['StartIndex']!);
        expect(r.url.queryParameters['AnyProviderIdEquals'], 'imdb.tt123');
        return response({
          'TotalRecordCount': 1101,
          'Items': List.generate(
            start == 1100 ? 1 : 50,
            (i) => movie('movie${start + i}'),
          ),
        });
      }),
    );
    addTearDown(client.close);
    expect(
      await client.findItems(
        account(MediaServerKind.emby),
        id: 'tt123',
        isMovie: true,
      ),
      hasLength(1101),
    );
  });

  test(
    'cache separates scope, revision, credentials and expires without sliding TTL',
    () async {
      var now = DateTime(2026);
      var calls = 0;
      final owner = Object();
      final client = MediaServerClient(
        lookupClock: () => now,
        client: MockClient((r) async {
          calls++;
          return response({
            'Items': [movie('m')],
          });
        }),
      );
      addTearDown(client.close);
      Future<void> lookup(Object scope, {String token = 'test'}) async {
        await client.findItems(
          account(MediaServerKind.jellyfin, token: token),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
        );
      }

      await lookup((owner, 1));
      now = now.add(const Duration(seconds: 30));
      await lookup((owner, 1));
      expect(calls, 1);
      await lookup((owner, 2));
      await lookup((Object(), 1));
      await lookup((owner, 1), token: 'changed');
      expect(calls, 4);
      now = now.add(const Duration(seconds: 31));
      await lookup((owner, 1));
      expect(calls, 5);
    },
  );

  test('cached results still require authorization', () async {
    final scope = Object();
    final client = MediaServerClient(
      client: MockClient(
        (r) async => response({
          'Items': [movie('m')],
        }),
      ),
    );
    addTearDown(client.close);
    await client.findItems(
      account(MediaServerKind.jellyfin),
      id: 'tt123',
      isMovie: true,
      cacheScope: scope,
    );
    await expectLater(
      client.findItems(
        account(MediaServerKind.jellyfin),
        id: 'tt123',
        isMovie: true,
        cacheScope: scope,
        authorize: () async => throw const MediaServerException('revoked'),
      ),
      throwsA(
        isA<MediaServerException>().having(
          (e) => e.message,
          'message',
          'revoked',
        ),
      ),
    );
  });

  test(
    'authorization loss after a timed-out page cannot publish partial matches',
    () async {
      var revoked = false;
      final client = MediaServerClient(
        client: MockClient((r) async {
          if (r.url.queryParameters['StartIndex'] == '1') {
            revoked = true;
            throw TimeoutException('synthetic');
          }
          return response({
            'TotalRecordCount': 2,
            'Items': [movie('m')],
          });
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.findItems(
          account(MediaServerKind.jellyfin),
          id: 'tt123',
          isMovie: true,
          cacheScope: Object(),
          onIncomplete: () => fail('Must not publish'),
          authorize: () async {
            if (revoked) throw const MediaServerException('revoked');
          },
        ),
        throwsA(
          isA<MediaServerException>().having(
            (e) => e.message,
            'message',
            'revoked',
          ),
        ),
      );
    },
  );

  test(
    'budget exhaustion returns explicitly partial results and resumes on retry',
    () async {
      var now = DateTime(2026);
      final scope = Object();
      final offsets = <int>[];
      final client = MediaServerClient(
        lookupClock: () => now,
        client: MockClient((r) async {
          final start = int.parse(r.url.queryParameters['StartIndex']!);
          offsets.add(start);
          now = now.add(const Duration(seconds: 13));
          return response({
            'TotalRecordCount': 2,
            'Items': [movie('m$start')],
          });
        }),
      );
      addTearDown(client.close);
      var partial = false;
      expect(
        await client.findItems(
          account(MediaServerKind.jellyfin),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
          onIncomplete: () => partial = true,
        ),
        hasLength(1),
      );
      expect(partial, isTrue);
      expect(
        await client.findItems(
          account(MediaServerKind.jellyfin),
          id: 'tt123',
          isMovie: true,
          cacheScope: scope,
          onIncomplete: () => fail('Must complete'),
        ),
        hasLength(2),
      );
      expect(offsets, [0, 1]);
    },
  );
}
