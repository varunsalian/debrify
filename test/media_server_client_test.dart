import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const account = MediaServerAccount(
  kind: MediaServerKind.jellyfin,
  baseUrl: 'https://server.example/jellyfin/',
  userId: 'user1',
  token: 'secret-token',
  serverId: 'server1',
  deviceId: 'device1',
);
http.Response jsonResponse(Object value) =>
    http.Response(jsonEncode(value), 200);

void main() {
  test(
    'URLs preserve reverse-proxy base paths and keep tokens out of links',
    () {
      final url = MediaServerClient.playbackUrl(
        account,
        'item1',
        'version & one',
      );
      expect(url.path, '/jellyfin/Videos/item1/stream');
      expect(url.queryParameters['MediaSourceId'], 'version & one');
      expect(url.queryParameters['Static'], 'true');
      expect(url.toString(), isNot(contains(account.token)));
      for (final bad in [
        'file:///tmp/test',
        'https://user:pass@server',
        'https://server?api_key=secret',
        'https://server/#/home',
      ]) {
        expect(
          () => MediaServerClient.normalizeBaseUrl(bad),
          throwsA(isA<MediaServerException>()),
        );
      }
      expect(
        () => MediaServerClient.playbackUrl(account, '../other', 'a'),
        throwsA(isA<MediaServerException>()),
      );
    },
  );

  for (final kind in MediaServerKind.values) {
    test(
      '${kind.label} API and playback headers support modern and legacy auth',
      () {
        final headers = MediaServerClient.headers(
          'device1',
          'opaque.token_123-abc==',
          kind,
        );
        expect(
          headers['Authorization'],
          '${kind == MediaServerKind.emby ? 'Emby' : 'MediaBrowser'} '
          'Client="Debrify", Device="Debrify", DeviceId="device1", Version="1.0", '
          'Token="opaque.token_123-abc=="',
        );
        expect(headers['X-Emby-Token'], 'opaque.token_123-abc==');
        final anonymous = MediaServerClient.headers('device1', null, kind);
        expect(anonymous['Authorization'], isNot(contains('Token=')));
        expect(anonymous.containsKey('X-Emby-Token'), false);
      },
    );

    test(
      '${kind.label} login sends password only in body and verifies server identity',
      () async {
        final client = MediaServerClient(
          client: MockClient((request) async {
            expect(request.followRedirects, false);
            expect(request.url.toString(), isNot(contains('my-password')));
            if (request.url.path.endsWith('AuthenticateByName')) {
              expect(request.method, 'POST');
              expect(
                request.headers['Authorization'],
                isNot(contains('Token=')),
              );
              expect(jsonDecode(request.body), {
                'Username': 'user',
                'Pw': 'my-password',
              });
              return jsonResponse({
                'User': {'Id': 'user1'},
                'AccessToken': 'secret-token',
                'ServerId': 'server1',
              });
            }
            expect(request.headers['X-Emby-Token'], 'secret-token');
            // Simulate modern Jellyfin: a legacy-only token header is not
            // authentication, even though the login response was successful.
            if (!request.headers['Authorization']!.contains(
              'Token="secret-token"',
            )) {
              return http.Response('Missing authorization token', 401);
            }
            if (request.url.path.endsWith('System/Info')) {
              return http.Response('Administrator access required', 403);
            }
            if (request.url.path.endsWith('System/Info/Public')) {
              return jsonResponse({'Id': 'server1'});
            }
            expect(request.url.path, '/jellyfin/Users/user1');
            return jsonResponse({
              'Id': 'user1',
              'Policy': {'IsAdministrator': false},
            });
          }),
        );
        final result = await client.login(
          kind: kind,
          baseUrl: account.baseUrl,
          username: ' user ',
          password: 'my-password',
          deviceId: account.deviceId,
        );
        await client.testConnection(result);
        expect(jsonEncode(result.toJson()), isNot(contains('my-password')));
        expect(result.kind, kind);
        client.close();
      },
    );
  }

  test(
    'server tokens cannot inject quoted auth parameters or header lines',
    () {
      for (final token in [
        '',
        'token"',
        'token\\',
        'token,DeviceId="other',
        'token\r\nInjected: yes',
        'token\n',
        'token with spaces',
      ]) {
        expect(
          () => MediaServerClient.headers('device1', token),
          throwsA(isA<MediaServerException>()),
        );
      }
    },
  );

  for (final status in [401, 403]) {
    test('public identity does not hide a user-session HTTP $status', () async {
      final paths = <String>[];
      final client = MediaServerClient(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('System/Info/Public')) {
            return jsonResponse({'Id': account.serverId});
          }
          expect(request.headers['X-Emby-Token'], account.token);
          return http.Response('private response', status);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.testConnection(account),
        throwsA(isA<MediaServerException>()),
      );
      expect(paths, ['/jellyfin/System/Info/Public', '/jellyfin/Users/user1']);
    });
  }

  test(
    'connection check rejects a different server before checking the user',
    () async {
      final client = MediaServerClient(
        client: MockClient((request) async {
          expect(request.url.path, '/jellyfin/System/Info/Public');
          return jsonResponse({'Id': 'other-server'});
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.testConnection(account),
        throwsA(
          isA<MediaServerException>().having(
            (e) => e.message,
            'message',
            contains('server identity changed'),
          ),
        ),
      );
    },
  );

  test('connection check rejects a mismatched user record', () async {
    final client = MediaServerClient(
      client: MockClient(
        (request) async => jsonResponse({
          'Id': request.url.path.endsWith('System/Info/Public')
              ? account.serverId
              : 'other-user',
        }),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.testConnection(account),
      throwsA(
        isA<MediaServerException>().having(
          (e) => e.message,
          'message',
          contains('server user changed'),
        ),
      ),
    );
  });

  for (final headers in [
    {'content-type': 'application/json; charset=utf-8'},
    <String, String>{},
  ]) {
    test('JSON preserves Unicode with response headers $headers', () async {
      const title = 'Amélie — 日本語 🎬';
      final client = MediaServerClient(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'movie1',
                    'Type': 'Movie',
                    'Name': title,
                    'ProviderIds': {'Imdb': 'tt123'},
                  },
                ],
                'TotalRecordCount': 1,
              }),
            ),
            200,
            headers: headers,
          ),
        ),
      );
      addTearDown(client.close);
      final items = await client.findItems(account, id: 'tt123', isMovie: true);
      expect(items.single['Name'], title);
    });
  }

  test('movie matching independently verifies IDs and type', () async {
    final client = MediaServerClient(
      client: MockClient((request) async {
        expect(
          request.url.queryParameters['AnyProviderIdEquals'],
          'imdb.tt123',
        );
        expect(request.url.queryParameters['IncludeItemTypes'], 'Movie');
        return jsonResponse({
          'Items': [
            {
              'Id': 'right',
              'Type': 'Movie',
              'ProviderIds': {'Imdb': 'tt123'},
            },
            {
              'Id': 'remake',
              'Type': 'Movie',
              'ProviderIds': {'Imdb': 'tt999'},
            },
            {
              'Id': 'series',
              'Type': 'Series',
              'ProviderIds': {'Imdb': 'tt123'},
            },
            {'Id': 'missing', 'Type': 'Movie', 'ProviderIds': {}},
          ],
        });
      }),
    );
    expect(
      (await client.findItems(
        account,
        id: 'tt123',
        isMovie: true,
      )).map((i) => i['Id']),
      ['right'],
    );
    client.close();
  });

  test(
    'series match uses exact season and episode, including season zero',
    () async {
      final client = MediaServerClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/Items')) {
            return jsonResponse({
              'Items': [
                {
                  'Id': 'series1',
                  'Type': 'Series',
                  'ProviderIds': {'Tvdb': '123'},
                },
              ],
            });
          }
          expect(request.url.path, '/jellyfin/Shows/series1/Episodes');
          expect(request.url.queryParameters['Season'], '0');
          return jsonResponse({
            'Items': [
              {
                'Id': 'special',
                'Type': 'Episode',
                'ParentIndexNumber': 0,
                'IndexNumber': 2,
              },
              {
                'Id': 'regular',
                'Type': 'Episode',
                'ParentIndexNumber': 1,
                'IndexNumber': 2,
              },
              {
                'Id': 'missing',
                'Type': 'Episode',
                'ParentIndexNumber': 0,
                'IndexNumber': 2,
                'IsMissing': true,
              },
              {
                'Id': 'other',
                'Type': 'Episode',
                'ParentIndexNumber': 0,
                'IndexNumber': 3,
              },
            ],
          });
        }),
      );
      expect(
        (await client.findItems(
          account,
          id: 'tvdb:123',
          isMovie: false,
          season: 0,
          episode: 2,
        )).map((i) => i['Id']),
        ['special'],
      );
      client.close();
    },
  );

  test(
    'unsupported IDs and whole-series requests never guess a file',
    () async {
      final client = MediaServerClient(
        client: MockClient((_) async => throw StateError('Unexpected request')),
      );
      expect(
        await client.findItems(
          account,
          id: 'anime:42',
          isMovie: false,
          season: 1,
          episode: 1,
        ),
        isEmpty,
      );
      expect(
        await client.findItems(account, id: 'tt123', isMovie: false),
        isEmpty,
      );
      client.close();
    },
  );

  test('pagination reaches exact movie matches beyond first page', () async {
    final client = MediaServerClient(
      client: MockClient((request) async {
        final start = int.parse(request.url.queryParameters['StartIndex']!);
        return jsonResponse({
          'TotalRecordCount': 101,
          'Items': start == 0
              ? List.generate(
                  100,
                  (i) => {'Id': 'wrong$i', 'Type': 'Movie', 'ProviderIds': {}},
                )
              : [
                  {
                    'Id': 'right',
                    'Type': 'Movie',
                    'ProviderIds': {'Tmdb': '42'},
                  },
                ],
        });
      }),
    );
    expect(
      (await client.findItems(
        account,
        id: 'tmdb:42',
        isMovie: true,
      )).single['Id'],
      'right',
    );
    client.close();
  });

  test(
    'playback excludes remote, opening-required and transcoding-only sources',
    () async {
      final local = {
        'Id': 'v1',
        'SupportsDirectPlay': true,
        'Protocol': 'File',
      };
      final client = MediaServerClient(
        client: MockClient(
          (request) async => jsonResponse({
            'MediaSources': [
              local,
              {...local, 'Id': 'v2', 'IsRemote': true},
              {...local, 'Id': 'v3', 'RequiresOpening': true},
              {...local, 'Id': 'v4', 'SupportsDirectPlay': false},
              {...local, 'Id': 'v5', 'Protocol': 'Http'},
            ],
          }),
        ),
      );
      expect(
        (await client.mediaSources(account, 'item1')).map((s) => s['Id']),
        ['v1'],
      );
      client.close();
    },
  );

  for (final status in [401, 403, 302, 500]) {
    test(
      'HTTP $status produces a safe error without response secrets',
      () async {
        final client = MediaServerClient(
          client: MockClient(
            (_) async => http.Response('secret-token my-password', status),
          ),
        );
        await expectLater(
          client.testConnection(account),
          throwsA(
            isA<MediaServerException>().having(
              (e) => e.message,
              'safe error',
              isNot(contains('secret-token')),
            ),
          ),
        );
        client.close();
      },
    );
  }

  test('authorization is checked after a delayed server response', () async {
    var allowed = true;
    final client = MediaServerClient(
      client: MockClient((_) async {
        allowed = false;
        return jsonResponse({'Id': account.serverId});
      }),
    );
    await expectLater(
      client.testConnection(
        account,
        authorize: () async {
          if (!allowed) throw StateError('revoked');
        },
      ),
      throwsStateError,
    );
    client.close();
  });

  test('timeouts and malformed server responses are actionable', () async {
    final slow = MediaServerClient(
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      slow.testConnection(account),
      throwsA(
        isA<MediaServerException>().having(
          (e) => e.message,
          'timeout',
          contains('timed out'),
        ),
      ),
    );
    slow.close();
    final invalid = MediaServerClient(
      client: MockClient((_) async => http.Response('<html>login</html>', 200)),
    );
    await expectLater(
      invalid.testConnection(account),
      throwsA(isA<MediaServerException>()),
    );
    invalid.close();
  });
}
