import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/native_profile_projection.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceSecretChannel = MethodChannel('debrify/device_secret');
  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('profile rollout flags are enabled for the test rollout', () {
    expect(ProfileBootstrap.profilesEnabled, isTrue);
    expect(ProfileBootstrap.migrationRolloutReady, isTrue);
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-bootstrap-test-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    await documents.create(recursive: true);
    await support.create(recursive: true);
    AppStorage.debugOverride(documents: documents, support: support);
  });

  tearDown(() async {
    await ProfileBootstrap.close();
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, null);
    AppStorage.debugReset();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'existing registry forbids native key replacement and routes loss to recovery',
    () async {
      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      await registry.close();

      DeviceKeyProvider.debugLinuxOverride = false;
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceSecretChannel, (call) async {
            received = call;
            throw PlatformException(
              code: 'device_secret_missing',
              message:
                  'initialize:DeviceSecretMissingException:DeviceSecretMissingException',
            );
          });

      await expectLater(
        ProfileBootstrap.initialize(),
        throwsA(
          isA<ProfileBootstrapRecoveryRequired>().having(
            (error) => error.deviceVaultFailure?.failure,
            'device vault failure',
            DeviceVaultFailure.missing,
          ),
        ),
      );
      expect(received?.method, 'initialize');
      expect(received?.arguments, <String, Object>{'allowCreate': false});
      expect(ProfileRuntime.isInitialized, isFalse);
    },
  );

  test('missing registry recovery never replaces a WebDAV device key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profiles_committed_once_v1': true,
      WebDavSyncBindingStore.storageKey: '{"existing":"sealed-state"}',
    });
    DeviceKeyProvider.debugLinuxOverride = false;
    final received = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          received.add(call);
          throw PlatformException(
            code: 'device_secret_missing',
            message:
                'initialize:DeviceSecretMissingException:DeviceSecretMissingException',
          );
        });

    await expectLater(
      ProfileBootstrap.initialize(),
      throwsA(
        isA<ProfileBootstrapRecoveryRequired>().having(
          (error) => error.deviceVaultFailure?.failure,
          'device vault failure',
          DeviceVaultFailure.missing,
        ),
      ),
    );

    expect(received.single.method, 'initialize');
    expect(received.single.arguments, <String, Object>{'allowCreate': false});
    expect(await ProfileRegistry.defaultRegistryExists(), isFalse);

    await expectLater(
      ProfileBootstrap.initializeRecoveryAuthority(),
      throwsA(
        isA<DeviceVaultException>().having(
          (error) => error.failure,
          'device vault failure',
          DeviceVaultFailure.missing,
        ),
      ),
    );
    expect(received, hasLength(2));
    expect(received.last.arguments, <String, Object>{'allowCreate': false});
  });

  test('empty WebDAV state does not block a fresh device key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WebDavSyncBindingStore.storageKey:
          '{"version":1,"bindings":{},"namespaces":{}}',
    });
    DeviceKeyProvider.debugLinuxOverride = false;
    MethodCall? initializeCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          if (call.method == 'initialize') {
            initializeCall = call;
            return 'ready';
          }
          return null;
        });

    await ProfileBootstrap.initialize();

    expect(initializeCall?.arguments, <String, Object>{'allowCreate': true});
    expect(ProfileRuntime.isProfileCommitted, isTrue);
  });

  test('malformed audit metadata routes to controlled recovery', () async {
    final registry = await ProfileRegistry.open();
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    await registry.close();
    SharedPreferences.setMockInitialValues(<String, Object>{
      WebDavSyncBindingStore.storageKey: '{',
    });
    DeviceKeyProvider.debugLinuxOverride = false;
    var committedCanary = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          if (call.method == 'initialize') {
            return 'migration_audit_required';
          }
          if (call.method == 'commitMigrationAudit') {
            committedCanary = true;
            return true;
          }
          return null;
        });

    await expectLater(
      ProfileBootstrap.initialize(),
      throwsA(
        isA<ProfileBootstrapRecoveryRequired>()
            .having(
              (error) => error.message,
              'message',
              'Stored credential metadata is unreadable',
            )
            .having(
              (error) => error.deviceVaultFailure,
              'device vault failure',
              isNull,
            ),
      ),
    );

    expect(committedCanary, isFalse);
    expect(ProfileRuntime.isInitialized, isFalse);
  });

  test('malformed envelope is not misclassified as device-key loss', () async {
    final registry = await ProfileRegistry.open();
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    await registry.insertResource(
      resource: ConnectionResource(
        id: 'resource-corrupt-envelope',
        type: ConnectionResourceType.stremioAddon,
        label: 'Corrupt addon',
        ownerProfileId: admin.id,
        publicConfig: const <String, dynamic>{'schemaVersion': 1},
        publicSchemaVersion: 1,
        authorizationRevision: 1,
        enabled: true,
      ),
      sealedSecretPayload: 'not-a-native-envelope',
      secretPayloadVersion: ConnectionResourceService.secretPayloadVersion,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );
    await registry.close();

    DeviceKeyProvider.debugLinuxOverride = false;
    var nativeOpenCalled = false;
    var committedCanary = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          switch (call.method) {
            case 'initialize':
              return 'migration_audit_required';
            case 'open':
              nativeOpenCalled = true;
              return base64Encode(<int>[1]);
            case 'commitMigrationAudit':
              committedCanary = true;
              return true;
          }
          return null;
        });

    await expectLater(
      ProfileBootstrap.initialize(),
      throwsA(
        isA<ProfileBootstrapRecoveryRequired>()
            .having(
              (error) => error.message,
              'message',
              'Stored credential metadata is unreadable',
            )
            .having(
              (error) => error.deviceVaultFailure,
              'device vault failure',
              isNull,
            ),
      ),
    );

    expect(nativeOpenCalled, isFalse);
    expect(committedCanary, isFalse);
    expect(ProfileRuntime.isInitialized, isFalse);
  });

  test(
    'one valid envelope proves the key despite unrelated metadata damage',
    () async {
      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      await registry.insertResource(
        resource: ConnectionResource(
          id: 'resource-valid-proof',
          type: ConnectionResourceType.stremioAddon,
          label: 'Valid addon',
          ownerProfileId: admin.id,
          publicConfig: const <String, dynamic>{'schemaVersion': 1},
          publicSchemaVersion: 1,
          authorizationRevision: 1,
          enabled: false,
        ),
        sealedSecretPayload: 'native1:valid-proof',
        secretPayloadVersion: ConnectionResourceService.secretPayloadVersion,
        ownerPermissions: ResourcePermission.values.fold<int>(
          0,
          (mask, permission) => mask | permission.bit,
        ),
      );
      await registry.close();
      SharedPreferences.setMockInitialValues(<String, Object>{
        WebDavSyncBindingStore.storageKey: '{',
      });

      DeviceKeyProvider.debugLinuxOverride = false;
      var committedCanary = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceSecretChannel, (call) async {
            switch (call.method) {
              case 'initialize':
                return 'migration_audit_required';
              case 'open':
                return base64Encode(utf8.encode('{}'));
              case 'commitMigrationAudit':
                committedCanary = true;
                return true;
            }
            return null;
          });

      await ProfileBootstrap.initialize();

      expect(committedCanary, isTrue);
      expect(ProfileRuntime.isProfileCommitted, isTrue);
    },
  );

  test(
    'pre-canary alias rejects mixed old-key and replacement-key envelopes',
    () async {
      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      const resourceId = 'resource-existing-webdav';
      const resource = ConnectionResource(
        id: resourceId,
        type: ConnectionResourceType.webDav,
        label: 'Existing WebDAV',
        ownerProfileId: 'placeholder',
        publicConfig: <String, dynamic>{
          'schemaVersion': 1,
          'endpoint': 'https://example.invalid',
        },
        publicSchemaVersion: 1,
        authorizationRevision: 1,
        enabled: false,
      );
      final actualResource = ConnectionResource(
        id: resource.id,
        type: resource.type,
        label: resource.label,
        ownerProfileId: admin.id,
        publicConfig: resource.publicConfig,
        publicSchemaVersion: resource.publicSchemaVersion,
        authorizationRevision: resource.authorizationRevision,
        enabled: resource.enabled,
      );
      await registry.insertResource(
        resource: actualResource,
        sealedSecretPayload: 'native1:old-key-envelope',
        secretPayloadVersion: ConnectionResourceService.secretPayloadVersion,
        ownerPermissions: ResourcePermission.values.fold<int>(
          0,
          (mask, permission) => mask | permission.bit,
        ),
      );
      const replacementResourceId = 'resource-new-key-addon';
      final replacementResource = ConnectionResource(
        id: replacementResourceId,
        type: ConnectionResourceType.stremioAddon,
        label: 'Replacement-key addon',
        ownerProfileId: admin.id,
        publicConfig: const <String, dynamic>{'schemaVersion': 1},
        publicSchemaVersion: 1,
        authorizationRevision: 1,
        enabled: true,
      );
      await registry.insertResource(
        resource: replacementResource,
        sealedSecretPayload: 'native1:replacement-key-envelope',
        secretPayloadVersion: ConnectionResourceService.secretPayloadVersion,
        ownerPermissions: ResourcePermission.values.fold<int>(
          0,
          (mask, permission) => mask | permission.bit,
        ),
      );
      await registry.close();

      DeviceKeyProvider.debugLinuxOverride = false;
      var committedCanary = false;
      var openCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceSecretChannel, (call) async {
            switch (call.method) {
              case 'initialize':
                return 'migration_audit_required';
              case 'open':
                openCalls++;
                if (openCalls == 1) {
                  throw PlatformException(
                    code: 'device_secret_failed',
                    message: 'open:AEADBadTagException:AEADBadTagException',
                  );
                }
                return base64Encode(<int>[1]);
              case 'commitMigrationAudit':
                committedCanary = true;
                return true;
            }
            return null;
          });

      await expectLater(
        ProfileBootstrap.initialize(),
        throwsA(
          isA<ProfileBootstrapRecoveryRequired>().having(
            (error) => error.deviceVaultFailure?.failure,
            'device vault failure',
            DeviceVaultFailure.unreadable,
          ),
        ),
      );
      expect(openCalls, 2);
      expect(committedCanary, isFalse);
      expect(ProfileRuntime.isInitialized, isFalse);
    },
  );

  test(
    'committed registry stays authoritative when rollout flags are off',
    () async {
      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
      );
      await registry.close();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'profiles_committed_once_v1': true,
      });
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 23),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      await ProfileBootstrap.initialize(enabled: false);

      expect(ProfileRuntime.isProfileCommitted, isTrue);
      expect(ProfileRuntime.capture().profileId, admin.id);
    },
  );

  test(
    'committed Linux registry waits for vault unlock before publishing',
    () async {
      DeviceKeyProvider.debugLinuxOverride = true;
      const passphrase = 'correct horse battery staple';
      await DeviceKeyProvider.createLinuxVault(passphrase);

      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
      );
      await registry.close();

      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        NativeProfileProjection.deviceKey,
        jsonEncode(<String, Object?>{
          'version': 2,
          'state': 'active',
          'publication': 1,
        }),
      );
      DeviceKeyProvider.lockLinuxVault();

      await ProfileBootstrap.initialize();

      expect(ProfileRuntime.isProfileCommitted, isTrue);
      expect(ProfileBootstrap.requiresLinuxVault, isTrue);
      expect(ProfileBootstrap.linuxVaultAlreadyConfigured, isTrue);
      expect(DeviceKeyProvider.isUnlocked, isFalse);
      expect(
        jsonDecode(
          preferences.getString(NativeProfileProjection.deviceKey)!,
        )['state'],
        'denied',
      );

      await ProfileBootstrap.completeLinuxVault(passphrase);

      expect(DeviceKeyProvider.isUnlocked, isTrue);
      expect(ProfileBootstrap.requiresLinuxVault, isFalse);
      expect(
        jsonDecode(
          preferences.getString(NativeProfileProjection.deviceKey)!,
        )['profileId'],
        admin.id,
      );
    },
  );

  test(
    'committed Linux registry without a wrapped key unlocks automatically',
    () async {
      DeviceKeyProvider.debugLinuxOverride = true;

      final registry = await ProfileRegistry.open();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: true,
      );
      await registry.close();

      await ProfileBootstrap.initialize();

      expect(ProfileBootstrap.requiresLinuxVault, isFalse);
      expect(DeviceKeyProvider.linuxAutoUnlockEnabled, isTrue);

      expect(DeviceKeyProvider.isUnlocked, isTrue);
      expect(await DeviceKeyProvider.linuxHasWrappedKey(), isTrue);
      expect(ProfileBootstrap.requiresLinuxVault, isFalse);
    },
  );

  test(
    'automatic Linux vault does not classify a fresh install as legacy',
    () async {
      DeviceKeyProvider.debugLinuxOverride = true;
      await ProfileBootstrap.initialize();
      expect(DeviceKeyProvider.linuxAutoUnlockEnabled, isTrue);
      expect(ProfileBootstrap.requiresLinuxVault, isFalse);
      expect(
        (await ProfileBootstrap.registry.activeProfile())?.id,
        ProfileBootstrap.freshAdminId,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where(
          (key) =>
              key.startsWith('p.') &&
              key.endsWith(DeviceKeyProvider.linuxStateKey),
        ),
        isEmpty,
      );
    },
  );

  test(
    'native launch snapshots do not turn a fresh install into a migration',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DevicePreferences.tvTrailerUnderlayEffectiveKey: false,
        DevicePreferences.tvLowResRenderActiveKey: true,
      });
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 7),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      await ProfileBootstrap.initialize();

      expect(
        (await ProfileBootstrap.registry.activeProfile())?.id,
        ProfileBootstrap.freshAdminId,
      );
    },
  );

  test(
    'an over-budget legacy install starts in legacy mode instead of failing',
    () async {
      // main() catches only ProfileBootstrapRecoveryRequired, so anything else
      // escaping initialize() stops the app from starting. A migration that
      // cannot fit the tvOS preference budget has to degrade, not throw.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'initial_setup_complete_v1': true,
        'theme_mode': 'dark',
        'playback_state_v1': 'x' * (ProfilePreferenceBudget.limitBytes ~/ 2),
      });
      ProfilePreferenceBudget.debugEnforcedOverride = true;
      addTearDown(ProfilePreferenceBudget.debugReset);
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 9),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      await ProfileBootstrap.initialize();

      expect(ProfileRuntime.isInitialized, isTrue);
      expect(ProfileRuntime.isProfileCommitted, isFalse);
      // The legacy install is untouched and still readable.
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('theme_mode'), 'dark');
      expect(
        preferences.getKeys().where((key) => key.startsWith('p.')),
        isEmpty,
      );
    },
  );

  test(
    'a migration that throws still starts the app on the untouched legacy install',
    () async {
      // The budget case above degrades correctly because it is caught by name.
      // Every OTHER migration failure escaped, and main() catches only
      // ProfileBootstrapRecoveryRequired — so on an upgrade the app simply did
      // not start, with no way back in.
      //
      // migrate() throws StateError for nine conditions that are realistic on
      // a device with real accumulated data. This drives the cheapest of them:
      // a credential-shaped legacy key the classifier has no disposition for,
      // which is what an older build leaving a provider key behind looks like.
      //
      // Degrading is safe because migration copies rather than moves —
      // authority changes only at the final commitBootstrap — so a failure
      // before that leaves the legacy install whole. Both halves are asserted:
      // that the app starts, and that legacy data survived intact.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'initial_setup_complete_v1': true,
        'theme_mode': 'dark',
        'some_retired_provider_api_key': 'legacy-secret',
      });
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 11),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      await ProfileBootstrap.initialize();

      expect(
        ProfileRuntime.isInitialized,
        isTrue,
        reason: 'the app must reach a usable state, not fail to launch',
      );
      expect(
        ProfileRuntime.isProfileCommitted,
        isFalse,
        reason: 'a failed migration must not claim profile authority',
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('theme_mode'), 'dark');
      expect(
        preferences.getString('some_retired_provider_api_key'),
        'legacy-secret',
        reason: 'migration copies rather than moves; legacy must be untouched',
      );
      expect(
        preferences.getKeys().where((key) => key.startsWith('p.')),
        isEmpty,
        reason: 'no half-migrated scoped namespace may be left behind',
      );
    },
  );

  test('one-way marker plus missing registry enters recovery', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profiles_committed_once_v1': true,
      'theme_mode': 'legacy-must-not-mount',
    });

    await expectLater(
      ProfileBootstrap.initialize(enabled: false),
      throwsA(isA<ProfileBootstrapRecoveryRequired>()),
    );
    expect(ProfileRuntime.isInitialized, isFalse);
  });

  test('one-way marker plus zero-byte registry enters recovery', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profiles_committed_once_v1': true,
    });
    await File(await ProfileRegistry.defaultPath()).create(recursive: true);

    await expectLater(
      ProfileBootstrap.initialize(enabled: false),
      throwsA(isA<ProfileBootstrapRecoveryRequired>()),
    );
    expect(ProfileRuntime.isInitialized, isFalse);
  });

  test(
    'recovery quarantines an unreadable registry and creates safe Admin',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'profiles_committed_once_v1': true,
        'legacy_secret': 'must-not-be-mounted',
      });
      final originalPath = await ProfileRegistry.defaultPath();
      await File(originalPath).create(recursive: true);
      await File(originalPath).writeAsBytes(const <int>[1, 2, 3, 4]);
      await expectLater(
        ProfileBootstrap.initialize(enabled: false),
        throwsA(isA<ProfileBootstrapRecoveryRequired>()),
      );
      final cipher = MemoryDeviceSecretCipher(
        List<int>.generate(32, (index) => index + 41),
      );
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);

      final recovered = await ProfileBootstrap.initializeRecoveryAuthority();
      final active = await recovered.activeProfile();
      expect(active?.id, ProfileBootstrap.recoveryAdminId);
      expect(active?.role, UserProfileRole.admin);
      expect(ProfileRuntime.capture().profileId, active?.id);
      expect(
        support.listSync().whereType<File>().any(
          (file) => file.path.contains('profiles.db.recovery-'),
        ),
        isTrue,
      );
    },
  );
}
