import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/features/sources/data/manual_source_preparation.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'source_acquisition_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileRegistry registry;
  late ProfileScope origin;
  late ProfileScope incoming;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues({});
    registry = await ProfileRegistry.open(path: inMemoryDatabasePath);
    final first = await registry.createProfile(
      name: 'First',
      role: UserProfileRole.admin,
    );
    final second = await registry.createProfile(
      name: 'Second',
      role: UserProfileRole.admin,
    );
    origin = ProfileScope(
      profileId: first.id,
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    incoming = ProfileScope(
      profileId: second.id,
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1)),
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    SecretVault.debugReset(deviceIdOverride: 'manual-source-profile');
    await registry.commitBootstrap(
      activeProfileId: origin.profileId,
      migratedLegacyInstall: false,
    );
    ProfileRuntime.initializeCommitted(origin);
    await StorageService.saveApiKey('origin-key');
    await StorageService.saveRdEndpoint('https://origin.test');
    await StorageService.saveFileSelection('all');
    await registry.setActiveProfile(incoming.profileId);
    ProfileRuntime.publish(incoming);
    await ProfileRuntime.withCapturedScope(incoming, () async {
      await StorageService.saveApiKey('incoming-key');
      await StorageService.saveRdEndpoint('https://incoming.test');
      await StorageService.saveFileSelection('largest');
    });
    await registry.setActiveProfile(origin.profileId);
    ProfileRuntime.publish(origin);
  });
  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    SecretVault.debugReset();
    await registry.close();
  });

  for (final scenario in [
    'foreignScope',
    'retiredAfterAdd',
    'rejectedCleanup',
  ]) {
    test('manual acquisition retains origin for $scenario', () async {
      final f = fixture.Fixture('debrid', 'pack');
      final client = MockClient((request) async {
        if (scenario == 'retiredAfterAdd' &&
            request.url.path.endsWith('/addMagnet')) {
          ProfileRuntime.publish(incoming);
        }
        if (scenario == 'rejectedCleanup' &&
            request.url.path.contains('/info/')) {
          f.paths.add(request.url.path);
          f.requests.add(request);
          ProfileRuntime.publish(incoming);
          return http.Response('{"id":"owned","files":[]}', 200);
        }
        return f.respond(request);
      });
      addTearDown(client.close);
      final result = await http.runWithClient(
        () => ProfileRuntime.withCapturedScope(
          incoming,
          () => const ManualSourcePreparation().prepare(
            'debrid',
            fixture.torrent,
            canContinue: () => true,
          ),
        ),
        () => client,
      );
      expect(result.ready, scenario == 'foreignScope');
      expect(f.requests, isNotEmpty);
      expect(f.requests.every((r) => r.url.host == 'origin.test'), isTrue);
      expect(
        f.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer origin-key',
        ),
        isTrue,
      );
      if (scenario == 'retiredAfterAdd') {
        expect(f.paths, ['/torrents/addMagnet']);
      } else if (scenario == 'rejectedCleanup') {
        expect(f.paths, [
          '/torrents/addMagnet',
          '/torrents/info/owned',
          '/torrents/delete/owned',
        ]);
      } else {
        final selection = f.requests.singleWhere(
          (r) => r.url.path.contains('/selectFiles/'),
        );
        expect(selection.bodyFields['files'], '2,1');
      }
      await ProfileRuntime.withCapturedScope(incoming, () async {
        expect(await StorageService.getApiKey(), 'incoming-key');
        expect(await StorageService.getRdEndpoint(), 'https://incoming.test');
        expect(await StorageService.getFileSelection(), 'largest');
      });
    });
  }
  test(
    'PikPak profile switch cannot share an outgoing captcha request',
    () async {
      Future<void> activate(ProfileScope scope) async {
        await registry.setActiveProfile(scope.profileId);
        ProfileRuntime.publish(scope);
      }

      for (final scope in [origin, incoming]) {
        await activate(scope);
        await StorageService.setPikPakAccessToken('access-${scope.profileId}');
        await StorageService.setPikPakRefreshToken(
          'refresh-${scope.profileId}',
        );
        await StorageService.setPikPakDeviceId('same-device');
        await StorageService.setPikPakUserId('same-user');
        await StorageService.setPikPakCaptchaToken(
          'initial-${scope.profileId}',
        );
      }
      await activate(origin);
      final entered = <String, Completer<void>>{
        origin.profileId: Completer<void>(),
        incoming.profileId: Completer<void>(),
      };
      final release = <String, Completer<void>>{
        origin.profileId: Completer<void>(),
        incoming.profileId: Completer<void>(),
      };
      addTearDown(() {
        for (final gate in release.values) {
          if (!gate.isCompleted) gate.complete();
        }
      });
      final captchaOwners = <String>[];
      final client = MockClient((request) async {
        final profileId = ProfileRuntime.capture().profileId;
        if (request.url.host == 'user.mypikpak.net') {
          captchaOwners.add(profileId);
          entered[profileId]!.complete();
          await release[profileId]!.future;
          return http.Response(
            jsonEncode({'captcha_token': 'renewed-$profileId'}),
            200,
          );
        }
        if (request.headers['X-Captcha-Token'] == 'renewed-$profileId') {
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
        final firstOwner = ProfileSessionMemory.captureOwner();
        final first = ProfileRuntime.withCapturedScope(
          origin,
          () => PikPakApiService.instance.getFileDetails(
            'file',
            canContinue: () =>
                firstOwner == ProfileSessionMemory.captureOwner(),
          ),
        );
        final firstOutcome = expectLater(first, throwsStateError);
        await entered[origin.profileId]!.future.timeout(
          const Duration(seconds: 5),
        );
        await activate(incoming);
        final second = PikPakApiService.instance.getFileDetails(
          'file',
          canContinue: () => true,
        );
        await entered[incoming.profileId]!.future.timeout(
          const Duration(seconds: 5),
        );
        release[origin.profileId]!.complete();
        await firstOutcome;
        release[incoming.profileId]!.complete();
        expect(await second, {'id': 'file'});
      }, () => client);
      expect(captchaOwners, [origin.profileId, incoming.profileId]);
      expect(
        await StorageService.getPikPakCaptchaToken(),
        'renewed-${incoming.profileId}',
      );
      await ProfileRuntime.withCapturedScope(origin, () async {
        expect(await StorageService.getPikPakCaptchaToken(), isNull);
      });
      await Future<void>.delayed(const Duration(milliseconds: 110));
    },
  );
}
