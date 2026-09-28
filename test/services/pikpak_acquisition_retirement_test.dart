import 'dart:convert';
import 'dart:async';

import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SecretVault.debugReset(deviceIdOverride: 'pikpak-action-fixture');
    SharedPreferences.setMockInitialValues({
      'pikpak_access_token': 'access-before',
      'pikpak_refresh_token': 'refresh-before',
      'pikpak_device_id': 'device-fixture',
      'pikpak_user_id': 'user-fixture',
      'pikpak_captcha_token': 'captcha-before',
    });
  });
  tearDown(SecretVault.debugReset);

  Future<Object?> invoke(String operation, bool Function() active) {
    final api = PikPakApiService.instance;
    return switch (operation) {
      'add' => api.addOfflineDownload(
        'magnet:?xt=fixture',
        canContinue: active,
      ),
      'task' => api.getTaskStatus('task', canContinue: active),
      'file' => api.getFileDetails('file', canContinue: active),
      _ => api.listFiles(parentId: 'folder', canContinue: active),
    };
  }

  for (final operation in ['add', 'task', 'file', 'folder']) {
    for (final failure in ['401', 'expired', 'captcha']) {
      test(
        '$operation retirement on $failure skips renewal and retry',
        () async {
          var active = true;
          final paths = <String>[];
          final client = MockClient((request) async {
            paths.add(request.url.path);
            active = false;
            return http.Response(
              jsonEncode({
                'error_code': failure == 'captcha' ? 4002 : 16,
                'error_description': failure == 'captcha'
                    ? 'Verification code is invalid'
                    : 'access token expired',
              }),
              failure == '401' ? 401 : 403,
            );
          });
          addTearDown(client.close);
          await http.runWithClient(() async {
            await expectLater(
              invoke(operation, () => active),
              throwsStateError,
            );
          }, () => client);
          expect(paths, hasLength(1));
          expect(await StorageService.getPikPakAccessToken(), 'access-before');
          expect(
            await StorageService.getPikPakCaptchaToken(),
            'captcha-before',
          );
        },
      );
    }
  }

  for (final renewal in ['token', 'captcha']) {
    for (final retired in [false, true]) {
      test(
        '$renewal renewal preserves accepted credentials and guards retry: $retired',
        () async {
          var active = true;
          final paths = <String>[];
          final client = MockClient((request) async {
            paths.add(request.url.path);
            if (paths.length == 1) {
              return http.Response(
                jsonEncode({
                  'error_code': renewal == 'captcha' ? 4002 : 16,
                  'error_description': renewal == 'captcha'
                      ? 'Verification code is invalid'
                      : 'access token expired',
                }),
                renewal == 'token' ? 401 : 403,
              );
            }
            if (paths.length == 2) {
              expect(
                request.url.host,
                renewal == 'token' ? 'user.mypikpak.com' : 'user.mypikpak.net',
              );
              if (retired) active = false;
              return http.Response(
                jsonEncode(
                  renewal == 'token'
                      ? {
                          'access_token': 'access-after',
                          'refresh_token': 'refresh-after',
                        }
                      : {'captcha_token': 'captcha-after'},
                ),
                200,
              );
            }
            expect(request.url.host, 'api-drive.mypikpak.com');
            expect(
              request.headers[renewal == 'token'
                  ? 'Authorization'
                  : 'X-Captcha-Token'],
              renewal == 'token' ? 'Bearer access-after' : 'captcha-after',
            );
            return http.Response(jsonEncode({'id': 'file'}), 200);
          });
          addTearDown(client.close);
          await http.runWithClient(() async {
            final pending = invoke('file', () => active);
            if (retired) {
              await expectLater(pending, throwsStateError);
            } else {
              expect(await pending, {'id': 'file'});
            }
          }, () => client);
          expect(paths, hasLength(retired ? 2 : 3));
          if (renewal == 'token') {
            expect(await StorageService.getPikPakAccessToken(), 'access-after');
          } else {
            expect(
              await StorageService.getPikPakCaptchaToken(),
              retired ? null : 'captcha-after',
            );
            // Let the service's existing completed-captcha retention expire.
            await Future<void>.delayed(const Duration(milliseconds: 110));
          }
        },
      );
    }
  }
  test(
    'concurrent captcha requests never borrow another device token',
    () async {
      final entered = [Completer<void>(), Completer<void>()];
      final release = [Completer<void>(), Completer<void>()];
      final requestedDevices = <String>[];
      addTearDown(() {
        for (final gate in release) {
          if (!gate.isCompleted) gate.complete();
        }
      });
      final client = MockClient((request) async {
        if (request.url.host == 'user.mypikpak.net') {
          final device =
              (jsonDecode(request.body) as Map)['device_id'] as String;
          requestedDevices.add(device);
          final index = device == 'device-one' ? 0 : 1;
          entered[index].complete();
          await release[index].future;
          return http.Response(
            jsonEncode({'captcha_token': 'token-$device'}),
            200,
          );
        }
        final token = request.headers['X-Captcha-Token'];
        if (token?.startsWith('token-') == true) {
          expect(token, 'token-${request.headers['X-Device-ID']}');
          return http.Response(jsonEncode({'id': 'file'}), 200);
        }
        return http.Response(
          jsonEncode({
            'error_code': 4002,
            'error_description': 'Verification code is invalid',
          }),
          403,
        );
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        await StorageService.setPikPakDeviceId('device-one');
        final first = invoke('file', () => true);
        await entered[0].future.timeout(const Duration(seconds: 5));
        await StorageService.setPikPakDeviceId('device-two');
        final second = invoke('file', () => true);
        await entered[1].future.timeout(const Duration(seconds: 5));
        // Request headers are reloaded on retry; restore each caller's device
        // before releasing its independently acquired token.
        await StorageService.setPikPakDeviceId('device-one');
        release[0].complete();
        expect(await first, {'id': 'file'});
        await StorageService.setPikPakDeviceId('device-two');
        release[1].complete();
        expect(await second, {'id': 'file'});
      }, () => client);
      expect(requestedDevices, ['device-one', 'device-two']);
      await Future<void>.delayed(const Duration(milliseconds: 110));
    },
  );
}
