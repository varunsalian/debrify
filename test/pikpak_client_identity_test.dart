import 'package:debrify/features/pikpak/models/client_identity.dart';
import 'package:debrify/features/pikpak/data/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

const identity = PikPakClientIdentity(
  userAgent: 'TestAgent/1.0',
  clientId: 'client-1',
  clientSecret: 'secret',
  clientVersion: '2.0.0',
  packageName: 'mypikpak.com',
  captchaSalts: ['salt-a', 'salt-b'],
);

void main() {
  group('headers', () {
    test('every call carries the same fingerprint', () {
      final headers = identity.headers();

      expect(headers['user-agent'], 'TestAgent/1.0');
      expect(headers['x-client-id'], 'client-1');
      // The one that had gone missing from three of five paths.
      expect(headers['x-client-version'], '2.0.0');
    });

    test('per-request pieces appear only when there is one', () {
      expect(identity.headers().containsKey('x-device-id'), isFalse);
      expect(
        identity.headers(deviceId: '').containsKey('x-device-id'),
        isFalse,
      );
      expect(identity.headers(deviceId: 'd1')['x-device-id'], 'd1');
      expect(identity.headers(captchaToken: 'c1')['x-captcha-token'], 'c1');
      expect(identity.headers(accessToken: 't1')['authorization'], 'Bearer t1');
    });

    test(
      'names are lower-cased so a caller override replaces, not duplicates',
      () {
        expect(identity.headers().keys, everyElement(equals(anything)));
        for (final key in identity.headers(deviceId: 'd').keys) {
          expect(key, key.toLowerCase());
        }
      },
    );
  });

  group('captchaSign', () {
    test('is deterministic for the same device and instant', () {
      expect(
        identity.captchaSign('device-1', '1700000000000'),
        identity.captchaSign('device-1', '1700000000000'),
      );
    });

    test('changes with the device and with the instant', () {
      final base = identity.captchaSign('device-1', '1700000000000');

      expect(identity.captchaSign('device-2', '1700000000000'), isNot(base));
      expect(identity.captchaSign('device-1', '1700000000001'), isNot(base));
    });

    test('the salt chain is folded in, not ignored', () {
      const unsalted = PikPakClientIdentity(
        userAgent: 'TestAgent/1.0',
        clientId: 'client-1',
        clientSecret: 'secret',
        clientVersion: '2.0.0',
        packageName: 'mypikpak.com',
        captchaSalts: [],
      );

      expect(
        identity.captchaSign('device-1', '1700000000000'),
        isNot(unsalted.captchaSign('device-1', '1700000000000')),
      );
    });

    test('carries PikPak\'s version prefix', () {
      expect(identity.captchaSign('d', '1'), startsWith('1.'));
    });
  });

  group('captchaMeta', () {
    test('signs the very timestamp it reports — they cannot drift apart', () {
      final meta = identity.captchaMeta(deviceId: 'd1');

      expect(
        meta['captcha_sign'],
        identity.captchaSign('d1', meta['timestamp']!),
      );
    });

    test('a signin identifies by username', () {
      final meta = identity.captchaMeta(deviceId: 'd1', username: 'me@x.test');

      expect(meta['username'], 'me@x.test');
      expect(meta.containsKey('user_id'), isFalse);
    });

    test('everything else identifies by user id', () {
      final meta = identity.captchaMeta(deviceId: 'd1', userId: 'u1');

      expect(meta['user_id'], 'u1');
      expect(meta.containsKey('username'), isFalse);
    });

    test('neither is sent when neither is known', () {
      final meta = identity.captchaMeta(deviceId: 'd1');

      expect(meta.containsKey('username'), isFalse);
      expect(meta.containsKey('user_id'), isFalse);
    });

    test('carries the same fingerprint the headers do', () {
      final meta = identity.captchaMeta(deviceId: 'd1', timestamp: '17');

      expect(meta['client_id'], 'client-1');
      expect(meta['client_version'], '2.0.0');
      expect(meta['package_name'], 'mypikpak.com');
      expect(meta['device_id'], 'd1');
      expect(meta['timestamp'], '17');
    });
  });

  test('the shipped identity is the web client PikPak expects', () {
    const web = PikPakApiService.webIdentity;

    expect(web.userAgent, contains('Firefox'));
    expect(web.packageName, 'mypikpak.com');
    expect(web.captchaSalts, isNotEmpty);
    expect(web.headers()['x-client-version'], web.clientVersion);
  });
}
