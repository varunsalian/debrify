import 'dart:convert';

import 'package:debrify/core/http/gateway.dart';
import 'package:debrify/features/pikpak/models/client_identity.dart';
import 'package:debrify/features/pikpak/data/session.dart';
import 'package:debrify/core/http/default_gateway.dart';
import 'package:debrify/features/pikpak/data/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testIdentity = PikPakClientIdentity(
  userAgent: 'PikPakWeb/2.0.0',
  clientId: 'YUMx5nI8ZU8Ap8pm',
  clientSecret: 'secret',
  clientVersion: '2.0.0',
  packageName: 'mypikpak.com',
  captchaSalts: ['salt-a', 'salt-b'],
);

void main() {
  late _FakeSession session;
  final url = Uri.parse('https://api-drive.mypikpak.com/drive/v1/files');

  setUp(() => session = _FakeSession());

  PikPakApi apiFor(Future<http.Response> Function(http.Request) handler) =>
      PikPakApi(
        http: DefaultHttpGateway(
          client: MockClient(handler),
          userAgent: 'Debrify/1.0',
          sleep: (_) async {},
        ),
        session: session,
        identity: testIdentity,
      );

  group('headers', () {
    test('PikPak\'s own User-Agent overrides the gateway default', () async {
      String? seen;
      final api = apiFor((request) async {
        seen = request.headers['user-agent'];
        return http.Response('{}', 200);
      });

      await api.send(HttpMethod.get, url);

      expect(seen, 'PikPakWeb/2.0.0');
    });

    test('device and captcha ride along when the session has them', () async {
      late Map<String, String> seen;
      final api = apiFor((request) async {
        seen = request.headers;
        return http.Response('{}', 200);
      });

      await api.send(HttpMethod.get, url);

      expect(seen['x-client-id'], 'YUMx5nI8ZU8Ap8pm');
      expect(seen['x-device-id'], 'device-1');
      expect(seen['x-captcha-token'], 'captcha-1');
      expect(seen['authorization'], 'Bearer token-1');
    });

    test('an absent captcha is simply not sent', () async {
      session.captcha = null;
      late Map<String, String> seen;
      final api = apiFor((request) async {
        seen = request.headers;
        return http.Response('{}', 200);
      });

      await api.send(HttpMethod.get, url);

      expect(seen.containsKey('x-captcha-token'), isFalse);
    });
  });

  group('stale token', () {
    test('a 401 refreshes once and retries with the new token', () async {
      final tokens = <String?>[];
      final api = apiFor((request) async {
        tokens.add(request.headers['authorization']);
        if (tokens.length == 1) return http.Response('{}', 401);
        return http.Response('{"ok":true}', 200);
      });

      final result = await api.send(HttpMethod.get, url);

      expect(session.refreshes, 1);
      expect(tokens, ['Bearer token-1', 'Bearer token-2']);
      expect(result, {'ok': true});
    });

    test('error_code 16 on a 200 means the same thing', () async {
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        if (calls == 1) {
          return http.Response('{"error_code":16,"error":"x"}', 200);
        }
        return http.Response('{"ok":true}', 200);
      });

      await api.send(HttpMethod.get, url);

      expect(session.refreshes, 1);
      expect(calls, 2);
    });

    test('an unauthenticated error string means the same thing', () async {
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        if (calls == 1) {
          return http.Response('{"error":"unauthenticated"}', 400);
        }
        return http.Response('{"ok":true}', 200);
      });

      await api.send(HttpMethod.get, url);

      expect(session.refreshes, 1);
    });

    test('the retry happens exactly once, never in a loop', () async {
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        return http.Response('{}', 401);
      });

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<PikPakRequestFailed>()),
      );

      expect(calls, 2);
      expect(session.refreshes, 1);
    });

    test('a failed refresh reports, but does not clear, the session', () async {
      session.canRefresh = false;
      final api = apiFor((_) async => http.Response('{}', 401));

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<PikPakSessionExpired>()),
      );

      // refreshAccessToken() returns false for recoverable reasons too — a
      // re-auth cooldown, a network blip — and clearing here wiped the user's
      // stored email, password, device id and restricted-folder pin.
      expect(session.token, isNotNull);
    });

    test('no access token at all fails before any request', () async {
      session.token = null;
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        return http.Response('{}', 200);
      });

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<PikPakSessionExpired>()),
      );

      expect(calls, 0);
    });
  });

  group('failures', () {
    test('429 is a typed rate limit, not a generic exception', () async {
      final api = apiFor((_) async => http.Response('{}', 429));

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<PikPakRateLimited>()),
      );
    });

    test('PikPak\'s error_description becomes the message', () async {
      final api = apiFor(
        (_) async => http.Response(
          '{"error_code":9,"error_description":"file not found"}',
          404,
        ),
      );

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(
          isA<PikPakRequestFailed>()
              .having((e) => e.message, 'message', 'file not found')
              .having((e) => e.code, 'code', 9)
              .having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test('error_code 4002 clears the captcha on the way out', () async {
      final api = apiFor(
        (_) async =>
            http.Response('{"error_code":4002,"error":"captcha"}', 400),
      );

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<PikPakRequestFailed>()),
      );

      expect(session.captchaInvalidated, isTrue);
    });

    test('an HTML error page is typed, not a FormatException', () async {
      final api = apiFor(
        (_) async => http.Response('<html>blocked</html>', 200),
      );

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<PikPakUnexpectedResponse>()),
      );
    });

    test('a hung request times out instead of hanging forever', () async {
      final api = PikPakApi(
        http: DefaultHttpGateway(
          client: MockClient((_) => Future.any([])),
          userAgent: 'Debrify/1.0',
          sleep: (_) async {},
        ),
        session: session,
        identity: testIdentity,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        api.send(HttpMethod.get, url),
        throwsA(isA<HttpTimeoutFailure>()),
      );
    });
  });

  group('requests', () {
    test('a body is JSON-encoded with the right content type', () async {
      String? body;
      String? type;
      final api = apiFor((request) async {
        body = request.body;
        type = request.headers['content-type'];
        return http.Response('{"id":"f1"}', 200);
      });

      await api.send(
        HttpMethod.post,
        url,
        body: {'kind': 'drive#folder', 'name': 'Movies'},
      );

      expect(jsonDecode(body!), {'kind': 'drive#folder', 'name': 'Movies'});
      expect(type, startsWith('application/json'));
    });

    test('a 204 delete comes back as an empty map, not a crash', () async {
      final api = apiFor((_) async => http.Response('', 204));

      expect(await api.send(HttpMethod.delete, url), isEmpty);
    });
  });
}

class _FakeSession implements PikPakSession {
  String? token = 'token-1';
  String? device = 'device-1';
  String? captcha = 'captcha-1';
  bool canRefresh = true;
  int refreshes = 0;
  bool captchaInvalidated = false;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> deviceId() async => device;

  @override
  Future<String?> captchaToken() async => captcha;

  @override
  Future<bool> refresh() async {
    refreshes++;
    if (!canRefresh) return false;
    token = 'token-${refreshes + 1}';
    return true;
  }

  @override
  Future<void> invalidateCaptcha() async {
    captchaInvalidated = true;
    captcha = null;
  }
}
