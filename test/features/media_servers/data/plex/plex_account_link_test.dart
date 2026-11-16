import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/media_servers/data/plex/plex_account_link.dart';
import 'package:debrify/models/media_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _client = 'debrifyclient0123456789abcdef';
const _accountToken = 'account-token-0123456789';

void main() {
  final now = DateTime(2026, 11, 15, 12);
  late List<http.Request> requests;
  late http.Response Function(http.Request) answer;

  PlexAccountLink link({DateTime Function()? clock}) => PlexAccountLink(
    clientId: _client,
    clock: clock ?? () => now,
    client: MockClient((request) async {
      requests.add(request);
      return answer(request);
    }),
  );

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  setUp(() => requests = []);

  test('a new code is a short plex.tv/link PIN for this client', () async {
    answer = (_) => json({
      'id': 77,
      'code': '425Z',
      'expiresIn': 900,
      'authToken': null,
      'location': {'city': 'Somewhere', 'coordinates': '1, 2'},
    }, 201);

    final pin = await link().createPin();

    expect(pin.code, '425Z');
    expect(pin.expiresAt, now.add(const Duration(minutes: 15)));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://plex.tv/api/v2/pins?strong=false');
    expect(request.headers['X-Plex-Client-Identifier'], _client);
    expect(request.headers['X-Plex-Product'], 'Debrify');
    expect(request.headers['Accept'], 'application/json');
  });

  test('polling returns the token only after the code was entered', () async {
    final pin = PlexPin(
      id: 77,
      code: '425Z',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    answer = (_) => json({'id': 77, 'authToken': null});
    expect(await link().pollPin(pin), isNull);
    answer = (_) => json({'id': 77, 'authToken': _accountToken});
    expect(await link().pollPin(pin), _accountToken);
    expect(requests.last.url.toString(), 'https://plex.tv/api/v2/pins/77');
    expect(requests.last.headers['X-Plex-Client-Identifier'], _client);
  });

  test('an unknown or expired code stops the sign-in', () async {
    final pin = PlexPin(
      id: 77,
      code: '425Z',
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    answer = (_) => http.Response('not found', 404);
    await expectLater(link().pollPin(pin), throwsA(isA<PlexPinExpired>()));
    final late = PlexPin(id: 77, code: '425Z', expiresAt: now);
    await expectLater(link().pollPin(late), throwsA(isA<PlexPinExpired>()));
    expect(requests, hasLength(1));
  });

  test('the account id is read with the token in a header only', () async {
    answer = (_) => json({'id': 1, 'uuid': 'abc123def', 'email': 'x@y.z'});
    expect(await link().userId(_accountToken), 'abc123def');
    expect(requests.single.headers['X-Plex-Token'], _accountToken);
    expect(requests.single.url.toString(), isNot(contains(_accountToken)));
  });

  test(
    'servers are listed with their addresses; other devices are not',
    () async {
      answer = (_) => http.Response(
        File(
          'test/fixtures/media_servers/plex/resources_doc_derived.json',
        ).readAsStringSync(),
        200,
      );

      final servers = await link().servers(_accountToken);

      expect(servers.map((s) => (s.name, s.owned, s.accessToken)), [
        ('Living Room', true, 'server-token-0001'),
        ("Friend's server", false, 'shared-token-0002'),
      ]);
      final home = servers.first.connections;
      expect(home.map((c) => (c.https, c.local, c.relay)), [
        (true, true, false),
        (false, true, false),
        (true, false, false),
        (true, false, true),
      ]);
      expect(home.first.uri, 'https://192-168-1-5.0123abcd.plex.direct:32400/');
      expect(
        plexAllowedConnections(
          home,
          allowInsecureLocal: false,
        ).map((c) => c.uri),
        [
          'https://192-168-1-5.0123abcd.plex.direct:32400/',
          'https://81-2-3-4.0123abcd.plex.direct:32400/',
          'https://1-2-3-4.0123abcd.plex.direct:8443/',
        ],
      );
      expect(
        requests.single.url.toString(),
        'https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1',
      );
    },
  );

  test('a malformed entry is skipped, not the whole list', () async {
    answer = (_) => json([
      'not an object',
      {
        'name': 'Ok',
        'provides': 'server',
        'clientIdentifier': 'srv',
        'accessToken': 'server-token-0001',
        'connections': [
          42,
          {'uri': 'https://ok.plex.direct:32400'},
        ],
      },
      {
        'name': 'Odd',
        'provides': 'server',
        'clientIdentifier': 'odd',
        'accessToken': 'server-token-0002',
        'connections': 'nope',
      },
    ]);
    final servers = await link().servers(_accountToken);
    expect(servers.map((s) => (s.name, s.connections.length)), [
      ('Ok', 1),
      ('Odd', 0),
    ]);
  });

  test('a malformed answer is an error, not an empty list', () async {
    answer = (_) => json({'unexpected': true});
    await expectLater(
      link().servers(_accountToken),
      throwsA(isA<MediaServerException>()),
    );
  });
}
