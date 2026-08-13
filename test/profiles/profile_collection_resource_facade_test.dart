import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String adminId;
  late String memberId;
  late String childId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'collection-facade-test-',
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
    childId = (await registry.createProfile(
      name: 'Child',
      role: UserProfileRole.child,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 11));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'use-only borrower executes opaquely but settings never reveal secret',
    () async {
      final resources = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final owner = await ProfileAuthorizationContext.capture(registry);
      final resource = await resources.create(
        context: owner,
        type: ConnectionResourceType.webDav,
        label: 'Shared DAV',
        publicConfig: const <String, dynamic>{'accountLabel': 'Shared DAV'},
        secretConfig: const <String, dynamic>{
          'baseUrl': 'https://sentinel.invalid/files',
          'username': 'sentinel-user',
          'password': 'sentinel-password',
        },
      );
      await resources.grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
      );

      final settings = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
        forSettings: true,
      );
      expect(settings, hasLength(1));
      expect(settings.single['baseUrl'], isEmpty);
      expect(settings.single['username'], isEmpty);
      expect(settings.single['password'], isEmpty);
      expect(settings.single['_connectionResourceReadOnly'], isTrue);
      expect(settings.single['_connectionResourceCredentialsRedacted'], isTrue);

      expect(
        await ProfileCollectionResourceFacade.read(
          types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
          feature: ProfileFeature.cloud,
          forRemoteTransfer: true,
        ),
        isEmpty,
      );

      ProfileRuntime.publish(
        ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
      );
      await resources.grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: resource.id,
        permissions: const <ResourcePermission>{
          ResourcePermission.use,
          ResourcePermission.writeRemote,
        },
      );
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 4),
      );
      final transferable = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
        forRemoteTransfer: true,
      );
      expect(transferable.single['password'], 'sentinel-password');

      final operational = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
      );
      expect(operational.single['password'], 'sentinel-password');
      await ProfileCollectionResourceFacade.authorizeExecution(
        resourceId: operational.single['_connectionResourceId'] as String,
        resourceRevision:
            operational.single['_connectionResourceRevision'] as int,
        acceptedTypes: const <ConnectionResourceType>{
          ConnectionResourceType.webDav,
        },
        feature: ProfileFeature.cloud,
      );

      ProfileRuntime.publish(
        ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 5),
      );
      await resources.updateSecret(
        context: await ProfileAuthorizationContext.capture(registry),
        resourceId: resource.id,
        secretConfig: const <String, dynamic>{
          'baseUrl': 'https://sentinel.invalid/files',
          'username': 'sentinel-user',
          'password': 'rotated-password',
        },
      );
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 6),
      );
      await expectLater(
        ProfileCollectionResourceFacade.authorizeExecution(
          resourceId: operational.single['_connectionResourceId'] as String,
          resourceRevision:
              operational.single['_connectionResourceRevision'] as int,
          acceptedTypes: const <ConnectionResourceType>{
            ConnectionResourceType.webDav,
          },
          feature: ProfileFeature.cloud,
        ),
        throwsA(isA<ResourceAuthorizationException>()),
      );
    },
  );

  test(
    'all collection credentials stay redacted for Member and Child settings',
    () async {
      final service = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final cases =
          <
            ({
              ConnectionResourceType type,
              ProfileFeature feature,
              Map<String, dynamic> secret,
              List<String> secretFields,
            })
          >[
            (
              type: ConnectionResourceType.webDav,
              feature: ProfileFeature.cloud,
              secret: const <String, dynamic>{
                'baseUrl': 'https://dav-sentinel.invalid',
                'username': 'dav-user-sentinel',
                'password': 'dav-password-sentinel',
              },
              secretFields: const <String>['baseUrl', 'username', 'password'],
            ),
            (
              type: ConnectionResourceType.prowlarr,
              feature: ProfileFeature.torrentSearch,
              secret: const <String, dynamic>{
                'base_url': 'https://indexer-sentinel.invalid',
                'api_key': 'indexer-key-sentinel',
              },
              secretFields: const <String>['base_url', 'api_key'],
            ),
            (
              type: ConnectionResourceType.iptvM3u,
              feature: ProfileFeature.iptv,
              secret: const <String, dynamic>{
                'url': 'https://iptv-sentinel.invalid/list.m3u',
              },
              secretFields: const <String>['url'],
            ),
            (
              type: ConnectionResourceType.stremioAddon,
              feature: ProfileFeature.addonsAndEngines,
              secret: const <String, dynamic>{
                'id': 'sentinel-addon',
                'name': 'Sentinel addon',
                'manifest_url':
                    'https://addon.invalid/credential-sentinel/manifest.json',
                'base_url': 'https://addon.invalid/credential-sentinel',
                'enabled': true,
                'types': <String>['movie'],
                'resources': <String>['stream'],
              },
              secretFields: const <String>['manifest_url', 'base_url'],
            ),
          ];

      final resources = <ConnectionResource>[];
      for (final item in cases) {
        final resource = await service.create(
          context: await ProfileAuthorizationContext.capture(registry),
          type: item.type,
          label: 'Shared ${item.type.name}',
          publicConfig: switch (item.type) {
            ConnectionResourceType.webDav => <String, dynamic>{
              'accountLabel': item.type.name,
            },
            ConnectionResourceType.prowlarr => <String, dynamic>{
              'managerName': item.type.name,
            },
            ConnectionResourceType.iptvM3u => <String, dynamic>{
              'playlistName': item.type.name,
              'providerKind': 'm3u',
            },
            ConnectionResourceType.stremioAddon => <String, dynamic>{
              'addonName': item.type.name,
              'contentKinds': <String>['movie'],
            },
            _ => const <String, dynamic>{},
          },
          secretConfig: item.secret,
        );
        resources.add(resource);
        for (final targetId in <String>[memberId, childId]) {
          await service.grant(
            actor: await ProfileAuthorizationContext.capture(registry),
            targetProfileId: targetId,
            resourceId: resource.id,
            permissions: const <ResourcePermission>{ResourcePermission.use},
          );
        }
      }

      var epoch = 2;
      for (final targetId in <String>[memberId, childId]) {
        ProfileRuntime.publish(
          ProfileScope(
            profileId: targetId,
            dataGeneration: 1,
            sessionEpoch: epoch++,
          ),
        );
        for (var index = 0; index < cases.length; index++) {
          final item = cases[index];
          final settings = await ProfileCollectionResourceFacade.read(
            types: <ConnectionResourceType>{item.type},
            feature: item.feature,
            forSettings: true,
          );
          expect(settings, hasLength(1));
          expect(settings.single['_connectionResourceId'], resources[index].id);
          expect(settings.single['_connectionResourceReadOnly'], isTrue);
          expect(
            settings.single['_connectionResourceCredentialsRedacted'],
            isTrue,
          );
          for (final field in item.secretFields) {
            expect(settings.single[field], isEmpty);
          }
        }
      }
    },
  );

  test('borrowed resource enabled state is profile-local', () async {
    final service = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    final resource = await service.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Shared addon',
      publicConfig: const <String, dynamic>{
        'addonName': 'Shared addon',
        'contentKinds': <String>['movie'],
      },
      secretConfig: const <String, dynamic>{
        'id': 'shared-addon',
        'name': 'Shared addon',
        'manifest_url': 'https://addon.invalid/key/manifest.json',
        'base_url': 'https://addon.invalid/key',
        'enabled': true,
        'types': <String>['movie'],
        'resources': <String>['stream'],
      },
    );
    await service.grant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: memberId,
      resourceId: resource.id,
      permissions: const <ResourcePermission>{ResourcePermission.use},
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.publish(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
    );

    await ProfileCollectionResourceFacade.setLocalEnabled(
      resourceId: resource.id,
      resourceRevision: resource.authorizationRevision,
      feature: ProfileFeature.addonsAndEngines,
      enabled: false,
    );
    expect(
      await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.stremioAddon,
        },
        feature: ProfileFeature.addonsAndEngines,
      ),
      isEmpty,
    );
    final memberSettings = await ProfileCollectionResourceFacade.read(
      types: const <ConnectionResourceType>{
        ConnectionResourceType.stremioAddon,
      },
      feature: ProfileFeature.addonsAndEngines,
      forSettings: true,
    );
    expect(memberSettings.single['enabled'], isFalse);

    await registry.setActiveProfile(adminId);
    ProfileRuntime.publish(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
    );
    final ownerView = await ProfileCollectionResourceFacade.read(
      types: const <ConnectionResourceType>{
        ConnectionResourceType.stremioAddon,
      },
      feature: ProfileFeature.addonsAndEngines,
    );
    expect(ownerView.single['enabled'], isTrue);
  });
}
