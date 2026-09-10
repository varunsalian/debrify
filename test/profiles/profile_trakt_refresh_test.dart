import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ConnectionResourceService resources;
  late MemoryDeviceSecretCipher cipher;
  late String adminId;
  late String memberId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'credential-disconnect-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    memberId = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<ConnectionResource> createTrakt() async {
    final resource = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.trakt,
      label: 'Trakt',
      publicConfig: const <String, dynamic>{},
      secretConfig: const <String, dynamic>{
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'expiryMs': 1,
      },
    );
    await registry.bindResource(
      profileId: adminId,
      slot: 'tracker.trakt',
      resourceId: resource.id,
    );
    return resource;
  }

  Future<ConnectionResource> shareTrakt() async {
    final resource = await createTrakt();
    await resources.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const {ResourcePermission.use},
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.publish(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
    );
    return resource;
  }

  const tokens = (
    accessToken: 'new-access',
    refreshToken: 'new-refresh',
    expiryMs: 9000000000000,
  );

  test(
    'use-only borrower refreshes shared tokens and expiry without gaining manage',
    () async {
      final resource = await shareTrakt();
      final context = await ProfileAuthorizationContext.capture(registry);
      expect(
        await ProfileCredentialFacade.refreshTraktSession((token) async {
          expect(token, 'refresh');
          return tokens;
        }),
        isTrue,
      );
      expect(await StorageService.getTraktAccessToken(), tokens.accessToken);
      expect(await StorageService.getTraktRefreshToken(), tokens.refreshToken);
      expect(await StorageService.getTraktTokenExpiry(), tokens.expiryMs);
      await context.validate(registry);
      await expectLater(
        StorageService.setTraktAccessToken('other-account'),
        throwsA(isA<ResourceAuthorizationException>()),
      );
      await registry.setActiveProfile(adminId);
      ProfileRuntime.publish(
        ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
      );
      expect(await StorageService.getTraktAccessToken(), tokens.accessToken);
      expect(await StorageService.getTraktRefreshToken(), tokens.refreshToken);
      expect(await StorageService.getTraktTokenExpiry(), tokens.expiryMs);
      expect(
        (await registry.getResource(resource.id))!.ownerProfileId,
        adminId,
      );
    },
  );

  test('concurrent refreshes of a shared connection exchange once', () async {
    await shareTrakt();
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    Future<({String accessToken, String refreshToken, int expiryMs})?> exchange(
      String token,
    ) async {
      calls++;
      started.complete();
      await release.future;
      return tokens;
    }

    final first = ProfileCredentialFacade.refreshTraktSession(exchange);
    await started.future;
    final second = ProfileCredentialFacade.refreshTraktSession(exchange);
    // Drain registry reads so the second call can join the pending exchange.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    release.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(calls, 1);
  });

  test('disconnect during exchange cannot publish rotated tokens', () async {
    final resource = await shareTrakt();
    final future = ProfileCredentialFacade.refreshTraktSession((token) async {
      await StorageService.clearTraktAuth();
      return tokens;
    });
    await expectLater(
      future,
      throwsA(anyOf(isA<StateError>(), isA<ResourceAuthorizationException>())),
    );
    await registry.setActiveProfile(adminId);
    ProfileRuntime.publish(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
    );
    expect(await StorageService.getTraktAccessToken(), 'access');
    expect(await StorageService.getTraktRefreshToken(), 'refresh');
    expect(await registry.getGrant(memberId, resource.id), isNull);
  });

  test('expired borrower session refreshes through Trakt HTTP path', () async {
    await shareTrakt();
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['refresh_token'], 'refresh');
      expect(body['grant_type'], 'refresh_token');
      return http.Response(
        jsonEncode({
          'access_token': 'http-access',
          'refresh_token': 'http-refresh',
          'expires_in': 86400,
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      expect(await TraktService.instance.isAuthenticated(), isTrue);
      expect(await TraktService.instance.isAuthenticated(), isTrue);
    }, () => client);
    expect(calls, 1);
    expect(await StorageService.getTraktAccessToken(), 'http-access');
    expect(await StorageService.getTraktRefreshToken(), 'http-refresh');
  });

  test('binding removed at commit boundary rejects token write', () async {
    await shareTrakt();
    registry.authorityWillChangeCallback = () async {
      registry.authorityWillChangeCallback = null;
      await registry.unbindResource(memberId, 'tracker.trakt');
    };
    await expectLater(
      ProfileCredentialFacade.refreshTraktSession((_) async => tokens),
      throwsA(isA<StateError>()),
    );
    await registry.setActiveProfile(adminId);
    ProfileRuntime.publish(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
    );
    expect(await StorageService.getTraktAccessToken(), 'access');
    expect(await StorageService.getTraktRefreshToken(), 'refresh');
  });

  test('failed exchange keeps the complete previous session', () async {
    await shareTrakt();
    expect(
      await ProfileCredentialFacade.refreshTraktSession((_) async => null),
      isFalse,
    );
    expect(await StorageService.getTraktAccessToken(), 'access');
    expect(await StorageService.getTraktRefreshToken(), 'refresh');
  });

  test(
    'scalar expiry replacement updates sealed expiry and preserves tokens',
    () async {
      await createTrakt();
      await StorageService.setTraktAccessToken('replacement-access');
      await StorageService.setTraktRefreshToken('replacement-refresh');
      await StorageService.setTraktTokenExpiry(tokens.expiryMs);
      expect(await StorageService.getTraktTokenExpiry(), tokens.expiryMs);
      expect(await StorageService.getTraktAccessToken(), 'replacement-access');
      expect(
        await StorageService.getTraktRefreshToken(),
        'replacement-refresh',
      );
    },
  );

  for (final expiry in <int?>[9000000000000, 1, null]) {
    test('backup replaces an existing sealed expiry with $expiry', () async {
      await StorageService.setTraktSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiryMs: 5000000000000,
      );
      final prefs = await ProfilePreferences.instance();
      await prefs.setInt('trakt_token_expiry', 5000000000000);
      final report = await BackupRestoreService.applyBackup({
        'trakt': {
          'access_token': 'import-access',
          'refresh_token': 'import-refresh',
          if (expiry != null) 'expiry_ms': expiry,
        },
      }, refreshEngineRuntime: false);
      expect(report.errors, isEmpty);
      expect(report.trakt, isTrue);
      expect(await StorageService.getTraktAccessToken(), 'import-access');
      expect(await StorageService.getTraktRefreshToken(), 'import-refresh');
      expect(await StorageService.getTraktTokenExpiry(), expiry);
    });
  }

  test('use-only borrower cannot edit shared expiry', () async {
    await shareTrakt();
    await expectLater(
      StorageService.setTraktTokenExpiry(tokens.expiryMs),
      throwsA(isA<ResourceAuthorizationException>()),
    );
    expect(await StorageService.getTraktTokenExpiry(), 1);
  });

  test('legacy session replacement clears omitted expiry', () async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await StorageService.setTraktSession(
      accessToken: 'old',
      refreshToken: 'old-refresh',
      expiryMs: tokens.expiryMs,
    );
    await StorageService.setTraktSession(
      accessToken: 'replacement',
      refreshToken: 'replacement-refresh',
      expiryMs: null,
    );
    expect(await StorageService.getTraktTokenExpiry(), isNull);
    expect(await StorageService.getTraktAccessToken(), 'replacement');
  });

  test('sign-in stores one owner session with shared expiry', () async {
    expect(
      await ProfileCredentialFacade.storeTraktSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiryMs: tokens.expiryMs,
      ),
      isTrue,
    );
    expect(await StorageService.getTraktTokenExpiry(), tokens.expiryMs);
    expect(await StorageService.getTraktRefreshToken(), tokens.refreshToken);
    expect(
      await ProfileCredentialFacade.storeTraktSession(
        accessToken: 'replacement',
        refreshToken: 'replacement-refresh',
        expiryMs: 12345,
      ),
      isTrue,
    );
    expect(await StorageService.getTraktAccessToken(), 'replacement');
    expect(await StorageService.getTraktTokenExpiry(), 12345);
  });
}
