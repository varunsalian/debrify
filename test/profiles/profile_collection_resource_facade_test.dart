import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/screens/settings/provider_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
    'secret-pending resource is visible in settings but not selectable',
    () async {
      const resourceId = 'pending-webdav';
      final pending = ConnectionResource(
        id: resourceId,
        type: ConnectionResourceType.webDav,
        label: 'Pending DAV',
        ownerProfileId: adminId,
        publicConfig: const <String, dynamic>{'schemaVersion': 1},
        publicSchemaVersion: 1,
        authorizationRevision: 1,
        enabled: true,
        secretPending: true,
      );
      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(resource: pending, updatedAtMs: 10),
          ],
          grants: <SyncedRegistryGrantRecord>[
            SyncedRegistryGrantRecord(
              profileId: adminId,
              resourceId: resourceId,
              permissions: ResourcePermission.values.fold<int>(
                0,
                (mask, permission) => mask | permission.bit,
              ),
              updatedAtMs: 11,
            ),
          ],
          bindings: <SyncedRegistryBindingRecord>[
            SyncedRegistryBindingRecord(
              profileId: adminId,
              slot: 'provider.webDav.legacy',
              resourceId: resourceId,
              updatedAtMs: 12,
            ),
          ],
        ),
      );

      final presence = await ProfileCredentialFacade.isConfigured(
        'webdav_base_url',
      );
      expect(presence.configured, isFalse);
      expect(presence.pending, isTrue);
      expect(
        await ProfileCollectionResourceFacade.read(
          types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
          feature: ProfileFeature.cloud,
        ),
        isEmpty,
      );
      final settings = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: ProfileFeature.cloud,
        forSettings: true,
      );
      expect(settings.single['_connectionResourceSecretPending'], isTrue);
      expect(settings.single['_connectionResourceCredentialsRedacted'], isTrue);

      const secret = <String, dynamic>{
        'baseUrl': 'https://dav.invalid/files',
        'username': 'owner',
        'password': 'secret',
      };
      final sealed = await cipher.seal(
        utf8.encode(jsonEncode(secret)),
        associatedData: ConnectionResourceService.associatedDataForSecret(
          resourceId: resourceId,
          type: ConnectionResourceType.webDav,
          ownerProfileId: adminId,
          publicSchemaVersion: 1,
          payloadVersion: ConnectionResourceService.secretPayloadVersion,
        ),
      );
      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: pending,
              updatedAtMs: 12,
              sealedSecretPayload: sealed,
              secretPayloadVersion:
                  ConnectionResourceService.secretPayloadVersion,
              expectedPriorUpdatedAtMs: 10,
            ),
          ],
        ),
      );

      final completed = await ProfileCredentialFacade.isConfigured(
        'webdav_base_url',
      );
      expect(completed.configured, isTrue);
      expect(completed.pending, isFalse);
      expect(
        (await ProfileCollectionResourceFacade.read(
          types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
          feature: ProfileFeature.cloud,
        )).single['baseUrl'],
        'https://dav.invalid/files',
      );
    },
  );

  test(
    'secret-pending PikPak is reported pending and not selectable',
    () async {
      const resourceId = 'pending-pikpak';
      await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: <SyncedRegistryResourceRecord>[
            SyncedRegistryResourceRecord(
              resource: ConnectionResource(
                id: resourceId,
                type: ConnectionResourceType.pikpak,
                label: 'Pending PikPak',
                ownerProfileId: adminId,
                publicConfig: const <String, dynamic>{'schemaVersion': 1},
                publicSchemaVersion: 1,
                authorizationRevision: 1,
                enabled: true,
                secretPending: true,
              ),
              updatedAtMs: 10,
            ),
          ],
          grants: <SyncedRegistryGrantRecord>[
            SyncedRegistryGrantRecord(
              profileId: adminId,
              resourceId: resourceId,
              permissions: ResourcePermission.values.fold<int>(
                0,
                (mask, permission) => mask | permission.bit,
              ),
              updatedAtMs: 11,
            ),
          ],
          bindings: <SyncedRegistryBindingRecord>[
            SyncedRegistryBindingRecord(
              profileId: adminId,
              slot: 'provider.pikpak',
              resourceId: resourceId,
              updatedAtMs: 12,
            ),
          ],
        ),
      );
      await StorageService.setPikPakEnabled(true);

      final presence = await ProfileCredentialFacade.isConfigured(
        'pikpak_email',
      );

      expect(presence.pending, isTrue);
      expect(presence.configured, isFalse);
      expect(await StorageService.hasPikPakCredential(), isFalse);
      expect(await StorageService.getPikPakEnabled(), isFalse);
    },
  );

  test('PikPak selection requires authentication and a ready secret', () async {
    await StorageService.setPikPakEmail('ready@example.test');
    await StorageService.setPikPakAccessToken('access-token');
    await StorageService.setPikPakRefreshToken('refresh-token');
    final authenticated = await PikPakApiService.instance.isAuthenticated();
    final readyPresence = await ProfileCredentialFacade.isConfigured(
      'pikpak_email',
    );

    expect(authenticated, isTrue);
    expect(readyPresence.pending, isFalse);
    expect(
      pikPakProviderIsSelectable(
        isAuthenticated: authenticated,
        secretPending: readyPresence.pending,
      ),
      isTrue,
    );
    expect(
      pikPakProviderIsSelectable(
        isAuthenticated: authenticated,
        secretPending: true,
      ),
      isFalse,
      reason: 'authenticated but pending must not be selectable',
    );

    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await StorageService.setPikPakEmail('restored@example.test');
    final restoredAuthentication = await PikPakApiService.instance
        .isAuthenticated();

    expect(await StorageService.getPikPakEmail(), 'restored@example.test');
    expect(restoredAuthentication, isFalse);
    expect(
      pikPakProviderIsSelectable(
        isAuthenticated: restoredAuthentication,
        secretPending: false,
      ),
      isFalse,
      reason: 'a restored email without tokens is not authentication',
    );
  });

  test(
    'confirmed IPTV collection removal revokes borrower grants atomically',
    () async {
      await StorageService.setIptvPlaylists(<IptvPlaylist>[
        IptvPlaylist(
          id: 'shared-iptv',
          name: 'Shared IPTV',
          url: 'https://iptv.invalid/shared.m3u',
          addedAt: DateTime.utc(2026, 8, 26),
        ),
      ]);
      final stored = await StorageService.getIptvPlaylists(forSettings: true);
      final resourceId = stored.single.connectionResourceId!;
      final service = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      await service.grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: resourceId,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );

      await expectLater(
        StorageService.setIptvPlaylistsAndReload(
          const <IptvPlaylist>[],
          forSettings: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('shared connection'),
          ),
        ),
      );
      expect(await registry.getResource(resourceId), isNotNull);
      expect(await registry.getGrant(memberId, resourceId), isNotNull);

      final remaining = await StorageService.setIptvPlaylistsAndReload(
        const <IptvPlaylist>[],
        forSettings: true,
        revokeBorrowers: true,
      );
      expect(remaining, isEmpty);
      expect(await registry.getResource(resourceId), isNull);
      expect(await registry.getGrant(memberId, resourceId), isNull);
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

  test('an unusable grant does not hide usable collection resources', () async {
    final service = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    final first = await service.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Usable subtitles',
      publicConfig: const <String, dynamic>{
        'addonName': 'Usable subtitles',
        'contentKinds': <String>['movie'],
      },
      secretConfig: const <String, dynamic>{
        'id': 'usable-subtitles',
        'name': 'Usable subtitles',
        'manifest_url': 'https://usable.invalid/manifest.json',
        'base_url': 'https://usable.invalid',
        'resources': <String>['subtitles'],
      },
    );
    final denied = await service.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Denied subtitles',
      publicConfig: const <String, dynamic>{
        'addonName': 'Denied subtitles',
        'contentKinds': <String>['movie'],
      },
      secretConfig: const <String, dynamic>{
        'id': 'denied-subtitles',
        'name': 'Denied subtitles',
        'manifest_url': 'https://denied.invalid/manifest.json',
        'base_url': 'https://denied.invalid',
        'resources': <String>['subtitles'],
      },
    );
    await registry.upsertGrant(
      profileId: memberId,
      resourceId: denied.id,
      permissions: ResourcePermission.download.bit,
      grantedByProfileId: adminId,
      origin: const <String, dynamic>{'origin': 'testRestrictedGrant'},
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.publish(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
    );

    final rows = await ProfileCollectionResourceFacade.read(
      types: const <ConnectionResourceType>{
        ConnectionResourceType.stremioAddon,
      },
      feature: ProfileFeature.addonUse,
    );

    expect(rows, hasLength(1));
    expect(rows.single['_connectionResourceId'], first.id);
  });

  test(
    'a profile switch cannot return a partially decrypted collection',
    () async {
      final service = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      for (final name in <String>['A subtitles', 'Z subtitles']) {
        await service.create(
          context: await ProfileAuthorizationContext.capture(registry),
          type: ConnectionResourceType.stremioAddon,
          label: name,
          publicConfig: <String, dynamic>{'addonName': name},
          secretConfig: <String, dynamic>{
            'id': name,
            'name': name,
            'base_url': 'https://${name.codeUnitAt(0)}.invalid',
            'resources': <String>['subtitles'],
          },
        );
      }
      final blocking = _NthOpenBlockingCipher(cipher, blockAt: 2);
      DeviceKeyProvider.debugInstallCipher(blocking);

      final read = ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.stremioAddon,
        },
        feature: ProfileFeature.addonUse,
      );
      await blocking.operationStarted.future;
      await registry.setActiveProfile(memberId);
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
      );
      blocking.release();

      await expectLater(read, throwsA(isA<ResourceAuthorizationException>()));
    },
  );

  test('IPTV mutation readback returns current execution authority', () async {
    final existing = IptvPlaylist(
      id: 'legacy-provider-id',
      name: 'Existing provider',
      url: 'https://iptv.invalid/existing.m3u',
      addedAt: DateTime.utc(2026, 8, 1),
    );
    await StorageService.setIptvPlaylists(<IptvPlaylist>[existing]);
    final migrated = await StorageService.getIptvPlaylists(forSettings: false);
    expect(migrated.single.connectionResourceId, isNotNull);
    final existingResourceId = migrated.single.connectionResourceId;
    final existingResourceRevision = migrated.single.connectionResourceRevision;

    // This is the upgrade path that used to fail: the starter is a raw UI
    // model while the existing provider is replaced in the resource graph.
    final starter = IptvPlaylist(
      id: 'iptv-org-default',
      name: 'iptv-org',
      url: 'https://iptv-org.github.io/iptv/index.m3u',
      addedAt: DateTime.utc(2026, 8, 14),
    );
    final canonical = await StorageService.setIptvPlaylistsAndReload(
      <IptvPlaylist>[starter, ...migrated],
      forSettings: false,
    );

    expect(canonical, hasLength(2));
    final preserved = canonical.singleWhere(
      (playlist) => playlist.connectionResourceId == existingResourceId,
    );
    expect(preserved.connectionResourceId, existingResourceId);
    expect(
      preserved.connectionResourceRevision,
      greaterThan(existingResourceRevision!),
    );
    for (final playlist in canonical) {
      expect(playlist.connectionResourceId, isNotNull);
      expect(playlist.connectionResourceRevision, isNotNull);
      await ProfileCollectionResourceFacade.authorizeExecution(
        resourceId: playlist.connectionResourceId,
        resourceRevision: playlist.connectionResourceRevision,
        acceptedTypes: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
        },
        feature: ProfileFeature.iptv,
      );
    }
  });

  test('WebDAV save selects and returns its canonical connection', () async {
    final saved = await StorageService.upsertWebDavServer(
      const WebDavConfig(
        id: 'editor-temporary-id',
        name: 'Media DAV',
        baseUrl: 'https://dav.invalid/files',
        username: 'user',
        password: 'password',
      ),
    );

    expect(saved.id, saved.connectionResourceId);
    expect(saved.connectionResourceRevision, isNotNull);
    expect(await StorageService.getSelectedWebDavServerId(), saved.id);
    await ProfileCollectionResourceFacade.authorizeExecution(
      resourceId: saved.connectionResourceId,
      resourceRevision: saved.connectionResourceRevision,
      acceptedTypes: const <ConnectionResourceType>{
        ConnectionResourceType.webDav,
      },
      feature: ProfileFeature.cloud,
    );

    final edited = await StorageService.upsertWebDavServer(
      WebDavConfig(
        id: saved.id,
        name: 'Media DAV edited',
        baseUrl: saved.baseUrl,
        username: saved.username,
        password: saved.password,
      ),
    );
    expect(edited.connectionResourceId, saved.connectionResourceId);
    expect(
      edited.connectionResourceRevision,
      greaterThan(saved.connectionResourceRevision!),
    );

    await StorageService.deleteWebDavServer(edited.id);
    expect(await StorageService.getWebDavServers(), isEmpty);
    expect(await StorageService.getSelectedWebDavServerId(), isNull);
  });

  test(
    'WebDAV migration reads use backupRestore independently of cloud',
    () async {
      final saved = await StorageService.upsertWebDavServer(
        const WebDavConfig(
          id: 'migration-dav',
          name: 'Migration DAV',
          baseUrl: 'https://dav.invalid/files',
          username: 'migration-user',
          password: 'migration-password',
        ),
      );
      final member = (await registry.getProfile(memberId))!;
      final actor = await ProfileAuthorizationContext.capture(registry);
      await registry.updateProfile(
        id: memberId,
        policy: ProfilePolicy(
          enabled: member.policy.enabled.toSet()..remove(ProfileFeature.cloud),
        ),
        actingProfileId: actor.profileId,
        actingAuthorizationRevision: actor.authorizationRevision,
        actingSessionEpoch: actor.sessionEpoch,
      );
      await ConnectionResourceService(registry: registry, cipher: cipher).grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: saved.connectionResourceId!,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );
      await registry.setActiveProfile(memberId);
      ProfileRuntime.publish(
        ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
      );

      await expectLater(
        StorageService.getWebDavServers(forSettings: false),
        throwsA(isA<ResourceAuthorizationException>()),
      );
      final migrationServers = await StorageService.getWebDavServers(
        forSettings: false,
        feature: ProfileFeature.backupRestore,
      );
      expect(migrationServers, hasLength(1));
      expect(migrationServers.single.password, 'migration-password');
      expect(
        (await StorageService.getSelectedWebDavServer(
          forSettings: false,
          feature: ProfileFeature.backupRestore,
        ))?.connectionResourceId,
        saved.connectionResourceId,
      );

      final createdForMigration = await StorageService.upsertWebDavServer(
        const WebDavConfig(
          id: 'new-migration-dav',
          name: 'New migration destination',
          baseUrl: 'https://new-dav.invalid/files',
          username: 'new-user',
          password: 'new-password',
        ),
        feature: ProfileFeature.backupRestore,
      );
      expect(createdForMigration.connectionResourceId, isNotNull);
      expect(createdForMigration.password, 'new-password');
      expect(
        await StorageService.getWebDavServers(
          forSettings: false,
          feature: ProfileFeature.backupRestore,
        ),
        hasLength(2),
      );

      await StorageService.deleteWebDavServer(
        createdForMigration.id,
        feature: ProfileFeature.backupRestore,
      );
      expect(
        await StorageService.getWebDavServers(
          forSettings: false,
          feature: ProfileFeature.backupRestore,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a shared WebDAV connection does not block unrelated mutations',
    () async {
      final shared = await StorageService.upsertWebDavServer(
        const WebDavConfig(
          id: 'shared-editor-id',
          name: 'Shared DAV',
          baseUrl: 'https://shared-dav.invalid/files',
          username: 'shared-user',
          password: 'shared-password',
        ),
      );
      await ConnectionResourceService(registry: registry, cipher: cipher).grant(
        actor: await ProfileAuthorizationContext.capture(registry),
        targetProfileId: memberId,
        resourceId: shared.connectionResourceId!,
        permissions: const <ResourcePermission>{ResourcePermission.use},
      );

      final unrelated = await StorageService.upsertWebDavServer(
        const WebDavConfig(
          id: 'unrelated-editor-id',
          name: 'Private DAV',
          baseUrl: 'https://private-dav.invalid/files',
          username: 'private-user',
          password: 'private-password',
        ),
      );
      expect(await StorageService.getWebDavServers(), hasLength(2));

      await StorageService.deleteWebDavServer(unrelated.id);
      final remaining = await StorageService.getWebDavServers();
      expect(remaining, hasLength(1));
      expect(
        remaining.single.connectionResourceId,
        shared.connectionResourceId,
      );
      expect(
        await registry.getGrant(memberId, shared.connectionResourceId!),
        isNotNull,
      );

      await expectLater(
        StorageService.deleteWebDavServer(shared.id),
        throwsA(isA<StateError>()),
      );
      expect(await StorageService.getWebDavServers(), hasLength(1));
    },
  );

  test('transfer models never retain connection-resource authority', () {
    final webDav = WebDavConfig(
      id: 'dav-id',
      name: 'DAV',
      baseUrl: 'https://dav.invalid',
      username: 'user',
      password: 'password',
      connectionResourceId: 'sender-dav-resource',
      connectionResourceRevision: 4,
    );
    final indexer = IndexerManagerConfig(
      id: 'indexer-id',
      name: 'Prowlarr',
      type: IndexerManagerType.prowlarr,
      baseUrl: 'https://prowlarr.invalid',
      apiKey: 'api-key',
      connectionResourceId: 'sender-indexer-resource',
      connectionResourceRevision: 5,
    );
    final iptv = IptvPlaylist(
      id: 'iptv-id',
      name: 'IPTV',
      url: 'https://iptv.invalid/list.m3u',
      addedAt: DateTime.utc(2026, 8, 18),
      connectionResourceId: 'sender-iptv-resource',
      connectionResourceRevision: 6,
    );

    for (final json in <Map<String, dynamic>>[
      webDav.toTransferJson(),
      indexer.toTransferJson(),
      iptv.toTransferJson(),
    ]) {
      expect(
        json.keys.any((key) => key.startsWith('_connectionResource')),
        isFalse,
      );
    }
    expect(
      WebDavConfig.fromTransferJson(webDav.toJson()).connectionResourceId,
      isNull,
    );
    expect(
      IndexerManagerConfig.fromTransferJson(
        indexer.toJson(),
      ).connectionResourceId,
      isNull,
    );
    expect(
      IptvPlaylist.fromTransferJson(iptv.toJson()).connectionResourceId,
      isNull,
    );
  });

  test('indexer collection writes return current stable authority', () async {
    const input = IndexerManagerConfig(
      id: 'editor-temporary-id',
      name: 'Prowlarr',
      type: IndexerManagerType.prowlarr,
      baseUrl: 'https://prowlarr.invalid',
      apiKey: 'sentinel-key',
    );
    final created = (await StorageService.setIndexerManagerConfigs(
      const <IndexerManagerConfig>[input],
    )).single;
    expect(created.id, created.connectionResourceId);
    expect(created.connectionResourceRevision, isNotNull);

    final updated = created.copyWith(maxResults: 100);
    final canonical = (await StorageService.setIndexerManagerConfigs(
      <IndexerManagerConfig>[updated],
    )).single;
    expect(canonical.connectionResourceId, created.connectionResourceId);
    expect(
      canonical.connectionResourceRevision,
      greaterThan(created.connectionResourceRevision!),
    );
    await ProfileCollectionResourceFacade.authorizeExecution(
      resourceId: canonical.connectionResourceId,
      resourceRevision: canonical.connectionResourceRevision,
      acceptedTypes: const <ConnectionResourceType>{
        ConnectionResourceType.prowlarr,
      },
      feature: ProfileFeature.torrentSearch,
    );
  });

  test('an Xtream resource migrated without url still loads', () async {
    // Exactly the shape an affected build left behind: the migration stripped
    // every empty value before sealing, so `url: ''` — which an Xtream
    // provider stores on purpose, its endpoint being serverUrl — vanished.
    // The reader casts url non-null, so ONE such resource threw for the whole
    // collection and the IPTV page never left its spinner. Migration is a
    // one-way door, so these devices are only reachable from the read side.
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.iptvXtream,
      label: 'Panel',
      publicConfig: const <String, dynamic>{'playlistName': 'Panel'},
      secretConfig: const <String, dynamic>{
        'name': 'Panel',
        'serverUrl': 'https://panel.invalid:8080',
        'username': 'user',
        'password': 'pass',
        'addedAt': '2026-08-14T00:00:00.000Z',
      },
    );

    final playlists = await StorageService.getIptvPlaylists(forSettings: false);
    final panel = playlists.singleWhere((p) => p.name == 'Panel');
    expect(panel.url, '');
    expect(panel.serverUrl, 'https://panel.invalid:8080');
    expect(panel.isXtreamCodes, isTrue);
  });

  test('a file-imported playlist migrated without url still loads', () async {
    // The other kind that stores `url: ''` on purpose: an M3U imported from a
    // file keeps its body in `content` (see the IPTV settings page). It hits
    // the same strip as Xtream, so the repair must recognise it too.
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.iptvM3u,
      label: 'From file',
      publicConfig: const <String, dynamic>{'playlistName': 'From file'},
      secretConfig: const <String, dynamic>{
        'name': 'From file',
        'content': '#EXTM3U\n#EXTINF:-1,One\nhttps://file.invalid/one',
        'addedAt': '2026-08-14T00:00:00.000Z',
      },
    );

    final playlists = await StorageService.getIptvPlaylists(forSettings: false);
    final imported = playlists.singleWhere((p) => p.name == 'From file');
    expect(imported.url, '');
    expect(imported.isLocalFile, isTrue);
  });

  test('a row missing both url and serverUrl is not papered over', () async {
    // The repair is deliberately narrow: genuine corruption must still
    // surface rather than being silently turned into a blank provider.
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.iptvM3u,
      label: 'Broken',
      publicConfig: const <String, dynamic>{'playlistName': 'Broken'},
      secretConfig: const <String, dynamic>{
        'name': 'Broken',
        'addedAt': '2026-08-14T00:00:00.000Z',
      },
    );

    await expectLater(
      StorageService.getIptvPlaylists(forSettings: false),
      throwsA(isA<TypeError>()),
    );
  });
}

class _NthOpenBlockingCipher implements DeviceSecretCipher {
  final DeviceSecretCipher delegate;
  final int blockAt;
  final Completer<void> operationStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int _opens = 0;

  _NthOpenBlockingCipher(this.delegate, {required this.blockAt});

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    _opens++;
    if (_opens == blockAt) {
      operationStarted.complete();
      await _release.future;
    }
    return delegate.open(envelope, associatedData: associatedData);
  }

  @override
  Future<String> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) => delegate.seal(plaintext, associatedData: associatedData);

  void release() => _release.complete();
}
