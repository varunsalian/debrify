import 'dart:convert';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/services/ledger/ledger_auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  final now = DateTime.utc(2026, 11, 20, 12);
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;

  LedgerAuthApi auth() => LedgerAuthApi(
    baseUrl: 'https://ledger.test',
    now: () => now,
    client: MockClient((request) async {
      requests.add(request);
      return respond(request);
    }),
  );

  setUp(() => requests = []);

  test('device authorization parses the live response', () async {
    respond = (_) => http.Response(
      jsonEncode({
        'device_code': 'dc',
        'user_code': 'NHCH-ZLZL',
        'verification_uri': 'https://debrify.garib.dev/activate',
        'verification_uri_complete':
            'https://debrify.garib.dev/activate?code=NHCH-ZLZL',
        'expires_in': 600,
        'interval': 5,
      }),
      200,
    );
    final code = (await auth().startDeviceAuthorization())!;
    expect(code.userCode, 'NHCH-ZLZL');
    expect(code.interval, const Duration(seconds: 5));
    expect(code.expiresIn, const Duration(minutes: 10));
    expect(requests.single.bodyFields, {'client_id': 'debrify-app'});
  });

  test('device authorization failure is null', () async {
    respond = (_) => http.Response('nope', 500);
    expect(await auth().startDeviceAuthorization(), isNull);
  });

  for (final (error, status) in [
    ('authorization_pending', LedgerPollStatus.pending),
    ('slow_down', LedgerPollStatus.slowDown),
    ('access_denied', LedgerPollStatus.denied),
    ('expired_token', LedgerPollStatus.expired),
    ('invalid_request', LedgerPollStatus.error),
  ]) {
    test('poll maps $error', () async {
      respond = (_) => http.Response(jsonEncode({'error': error}), 400);
      expect((await auth().pollDeviceToken('dc')).status, status);
      expect(
        requests.single.bodyFields['grant_type'],
        'urn:ietf:params:oauth:grant-type:device_code',
      );
    });
  }

  test('approved poll returns tokens with an absolute expiry', () async {
    respond = (_) => http.Response(
      jsonEncode({
        'access_token': 'a',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'refresh_token': 'r',
      }),
      200,
    );
    final result = await auth().pollDeviceToken('dc');
    expect(result.status, LedgerPollStatus.approved);
    expect(result.tokens!.accessToken, 'a');
    expect(result.tokens!.refreshToken, 'r');
    expect(result.tokens!.expiresAt, now.add(const Duration(hours: 1)));
  });

  test('server errors while polling are transient', () async {
    respond = (_) => http.Response('', 503);
    expect(
      (await auth().pollDeviceToken('dc')).status,
      LedgerPollStatus.networkError,
    );
  });

  test('refresh distinguishes a rejected token from a failure', () async {
    respond = (_) => http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
    final rejected = await auth().refresh('r');
    expect(rejected.rejected, isTrue);
    expect(rejected.tokens, isNull);
    expect(requests.single.bodyFields['grant_type'], 'refresh_token');

    respond = (_) => http.Response('', 502);
    final failed = await auth().refresh('r');
    expect(failed.rejected, isFalse);
    expect(failed.tokens, isNull);
  });
}
