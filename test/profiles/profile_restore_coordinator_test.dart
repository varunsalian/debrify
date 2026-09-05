import 'dart:convert';
import 'dart:io';
import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_adoption_operations.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_graph.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_safety_backup.dart';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/legacy_backup_adapter.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_avatar_ingest.dart';
import 'package:debrify/services/profiles/profile_avatar_storage.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:debrify/services/profiles/profile_data_generation.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
import 'package:debrify/services/profiles/profile_package_service.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'avatar_fixtures.dart';

class _SetupCompleteObserver implements ProfileLifecycleParticipant {
  _SetupCompleteObserver(this.registry, this.profileId);

  final ProfileRegistry registry;
  final String profileId;
  bool? setupCompleteDuringCandidateInitialization;

  @override
  Future<void> prepareDeactivate(ProfileScope current) async {}

  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {
    setupCompleteDuringCandidateInitialization = (await registry.getProfile(
      profileId,
    ))?.setupComplete;
  }

  @override
  Future<void> didActivate(ProfileScope active) async {}

  @override
  Future<void> rollback(ProfileScope restored) async {}
}

Future<PortableProfilePackage> _singleProfilePackage({
  required bool? setupComplete,
}) async {
  final section = await PortableProfilePackage.buildSection(
    const <String, Object?>{'theme_mode': 'restored'},
  );
  return PortableProfilePackage(
    mode: 'singleProfile',
    createdAt: DateTime.utc(2026, 8, 29),
    profiles: <Map<String, dynamic>>[
      <String, dynamic>{
        'backupId': 'profile-0',
        if (setupComplete != null) 'setupComplete': setupComplete,
        'preferencesSection': 'preferences',
      },
    ],
    resources: const <Map<String, dynamic>>[],
    sections: <String, dynamic>{'preferences': section},
  );
}

Future<Map<String, dynamic>> _legacyV3EncryptedEnvelope(
  PortableProfilePackage source,
  String passphrase,
) async {
  final body = <String, dynamic>{...source.toJson(), 'version': 3};
  final digest = await Sha256().hash(utf8.encode(jsonEncode(body)));
  final stamped = <String, dynamic>{
    ...body,
    'integrity': <String, dynamic>{
      'algorithm': 'sha256',
      'digest': base64UrlEncode(digest.bytes).replaceAll('=', ''),
    },
  };
  final salt = List<int>.generate(16, (index) => index + 1);
  final key = await Argon2id(
    parallelism: 1,
    memory: 8,
    iterations: 1,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  const aad = 'debrify-profile-backup-v3';
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(stamped)),
    secretKey: key,
    aad: utf8.encode(aad),
  );
  return <String, dynamic>{
    'format': 'debrify-profile-package',
    'version': 3,
    'encrypted': true,
    'createdAt': source.createdAt.toUtc().toIso8601String(),
    'kdf': <String, dynamic>{
      'algorithm': 'argon2id',
      'salt': base64Encode(salt),
      'memory': 8,
      'iterations': 1,
      'parallelism': 1,
    },
    'aead': <String, dynamic>{
      'algorithm': 'aes-256-gcm',
      'aad': aad,
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(<int>[...box.cipherText, ...box.mac.bytes]),
    },
  };
}

void main() {
  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;
  late Directory cache;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String profileId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-restore-test-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    cache = Directory(p.join(temporaryDirectory.path, 'cache'));
    await documents.create(recursive: true);
    await support.create(recursive: true);
    await cache.create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    profileId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: profileId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => 250 - i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 1),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('p.$profileId.g.1.theme_mode', 'old');
  });

  tearDown(() async {
    await DebrifyTvDatabase.instance.closeScope();
    IptvMediaStore.debugResetMigration();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'restored backup then circle adoption leaves every collection usable',
    () async {
      final resources = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      const types = {
        ConnectionResourceType.iptvM3u,
        ConnectionResourceType.iptvXtream,
        ConnectionResourceType.stremioAddon,
        ConnectionResourceType.webDav,
        ConnectionResourceType.jackett,
        ConnectionResourceType.prowlarr,
      };
      for (final type in types) {
        final secret = <String, dynamic>{
          'id': 'old-${type.name}',
          'name': type.name,
          'enabled': true,
          // Deliberately retain old compatibility authority in the encrypted
          // payload. Only registry readback may mint an executable model.
          '_connectionResourceId': 'pre-backup-resource',
          '_connectionResourceRevision': 73,
          if (type == ConnectionResourceType.iptvM3u ||
              type == ConnectionResourceType.iptvXtream) ...{
            'url': type == ConnectionResourceType.iptvM3u
                ? 'https://example.invalid/list.m3u'
                : '',
            'addedAt': '2026-08-01T00:00:00.000Z',
            if (type == ConnectionResourceType.iptvXtream) ...{
              'serverUrl': 'https://example.invalid',
              'username': 'test-user',
              'password': 'test-password',
            },
          },
          if (type == ConnectionResourceType.stremioAddon) ...{
            'manifest_url': 'https://example.invalid/manifest.json',
            'base_url': 'https://example.invalid',
            'types': ['movie'],
            'resources': ['catalog'],
            'catalogs': [],
          },
          if (type == ConnectionResourceType.webDav) ...{
            'baseUrl': 'https://example.invalid/dav',
            'username': 'test-user',
            'password': 'test-password',
          },
          if (type == ConnectionResourceType.jackett ||
              type == ConnectionResourceType.prowlarr) ...{
            'type': type.name,
            'base_url': 'https://example.invalid',
            'api_key': 'test-key',
          },
        };
        await resources.create(
          context: await ProfileAuthorizationContext.capture(registry),
          type: type,
          label: type.name,
          publicConfig: const {},
          secretConfig: secret,
        );
      }
      final packages = ProfilePackageService(
        registry: registry,
        resources: resources,
      );
      final circle = await packages.exportAllProfiles(
        context: await ProfileAuthorizationContext.capture(registry),
        includeSecrets: true,
        includeDatabases: false,
      );
      final restore = ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      );
      final restoredBackup = await restore.restoreDeviceGraph(
        package: circle,
        authorization: await ProfileAuthorizationContext.capture(registry),
      );
      final lifecycle = ProfileLifecycleCoordinator(registry: registry);
      addTearDown(lifecycle.dispose);
      await lifecycle.switchTo(restoredBackup.importedProfileIds.single);

      final operations = DefaultWebDavSyncAdoptionOperations(
        registry: registry,
        restoreCoordinator: restore,
        lifecycleCoordinator: lifecycle,
      );
      // The backup source is not part of the restored phone. Remove it before
      // seeding so the circle contains exactly the restored resource graph.
      await operations.pruneProfile(profileId);
      final localProfiles = await registry.listProfiles(includeDisabled: true);
      final localResources = await registry.listAllResourcesIncludingDisabled();
      final seedMaps = WebDavSyncGraphIdentityPlanner.ensure(
        localProfileIds: localProfiles.map((profile) => profile.id),
        localResourceIds: localResources.map((resource) => resource.id),
      ).maps;
      final retained = WebDavSyncGraphIdentityPlanner.ensure(
        localProfileIds: localProfiles.map((profile) => profile.id),
        localResourceIds: localResources.map((resource) => resource.id),
        currentCircleToLocalProfiles: seedMaps.circleToLocalProfiles,
        currentCircleToLocalResources: seedMaps.circleToLocalResources,
      ).maps;
      expect(retained.circleToLocalResources, seedMaps.circleToLocalResources);
      final seed = await WebDavSyncGraphBuilder(packages).build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: await ProfileAuthorizationContext.capture(registry),
        identityMaps: retained,
      );

      Future<List<Map<String, dynamic>>> read() =>
          ProfileCollectionResourceFacade.read(
            types: types,
            feature: ProfileFeature.manageConnections,
          );
      final preJoinScope = ProfileRuntime.capture();
      final oldModels = await read();
      expect(oldModels.length, greaterThanOrEqualTo(types.length));
      final states = _JoinStateRepository();
      final adoption = WebDavSyncCircleAdoption(
        stateRepository: states,
        // Only the backup filesystem is substituted; restore, registry
        // publication, handoff, resource remapping and predecessor prune are real.
        safetyBackups: _JoinSafetyBackups(),
        operations: operations,
      );
      final joined = await adoption.adopt(
        WebDavSyncAdoptionRequest(
          namespaceId: 'circle:regression',
          mode: WebDavSyncAdoptionMode.firstJoin,
          package: seed.package,
          graphSemanticDigest: seed.semanticDigest,
          profileMap: seed.profileMap,
          resourceMap: seed.resourceMap,
          passphrase: 'test-circle-passphrase',
          authorization: await ProfileAuthorizationContext.capture(registry),
          replacementConfirmed: true,
        ),
      );
      expect(joined.phase, WebDavSyncAdoptionPhase.complete);
      expect(states.state.adoption, isNull);
      final current = await read();
      expect(current, hasLength(types.length));
      Future<void> authorize(Map<String, dynamic> row) =>
          ProfileCollectionResourceFacade.authorizeExecution(
            resourceId: row['_connectionResourceId'] as String?,
            resourceRevision: row['_connectionResourceRevision'] as int?,
            acceptedTypes: types,
            feature: ProfileFeature.manageConnections,
          );
      for (final row in current) {
        final resource = await registry.getResource(
          row['_connectionResourceId'] as String,
        );
        expect(
          row['_connectionResourceRevision'],
          resource!.authorizationRevision,
        );
        await authorize(row);
      }
      for (final row in oldModels) {
        await expectLater(
          authorize(row),
          throwsA(isA<ResourceAuthorizationException>()),
        );
      }
      // Exercise the production model getters (not just raw facade records).
      final List<IptvPlaylist> playlists =
          await StorageService.getIptvPlaylists(forSettings: false);
      expect(playlists.where((p) => !p.isVirtual), hasLength(2));
      final List<WebDavConfig> servers = await StorageService.getWebDavServers(
        forSettings: false,
      );
      expect(servers, hasLength(1));
      final List<IndexerManagerConfig> managers =
          await StorageService.getIndexerManagerConfigs(forSettings: false);
      expect(managers, hasLength(2));
      StremioService.instance.invalidateCache();
      // A retired display read must fail soft, without caching an empty result
      // over the new profile's catalog or reviving its old resource authority.
      expect(
        await ProfileRuntime.withCapturedScope(
          preJoinScope,
          () => StremioService.instance.getAddons(),
        ),
        isEmpty,
      );
      final addons = await StremioService.instance.getAddons();
      expect(addons, hasLength(1));
      for (final row in [
        ...playlists.where((p) => !p.isVirtual).map((p) => p.toJson()),
        ...servers.map((p) => p.toJson()),
        ...managers.map((p) => p.toJson()),
        ...addons.map((p) => p.toJson()),
      ]) {
        await authorize(row);
      }
    },
  );

  test('sanitized export emits only reviewed settings and values', () async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'p.$profileId.g.1.';
    await prefs.setString('${prefix}app_theme', 'spotlight');
    await prefs.setBool('${prefix}ui_sounds', true);
    await prefs.setString(
      '${prefix}series_source_tt1234567',
      '{"name":"Private.Release","infoHash":"private-hash",'
          '"filePath":"/Users/private/Downloads/video.mkv"}',
    );
    await prefs.setString(
      '${prefix}continue_watching_v1',
      '[{"title":"Private title"}]',
    );
    await prefs.setString(
      '${prefix}playback_state_v1',
      '{"url":"http://host/movie/username/password/1.mkv"}',
    );
    await prefs.setString(
      '${prefix}future_innocent_name',
      'credential-that-a-denylist-would-miss',
    );
    await prefs.setString(
      '${prefix}detail_theme',
      'https://example.invalid/credential',
    );

    final resourceService = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    await resourceService.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.iptvXtream,
      label: 'Private IPTV account',
      publicConfig: const <String, dynamic>{
        'playlistName': 'Private IPTV',
        'providerKind': 'xtream',
      },
      secretConfig: const <String, dynamic>{
        'url': 'http://host',
        'username': 'private-user',
        'password': 'private-password',
      },
    );

    final package =
        await ProfilePackageService(
          registry: registry,
          resources: resourceService,
        ).exportProfile(
          context: await ProfileAuthorizationContext.capture(registry),
          scope: ProfileRuntime.capture(),
          includeSecrets: false,
          sanitized: true,
        );

    final section = package.sections['profile-0-preferences'] as Map;
    expect(section['values'], <String, Object?>{
      'app_theme': 'spotlight',
      'ui_sounds': true,
    });
    expect(package.mode, 'sanitizedSettings');
    expect(package.resources, isEmpty);
    expect(package.omissions, isNot(contains('borrowedConnections')));
  });

  test(
    'secret-free export omits credential-shaped custom engine settings',
    () async {
      final raw = await SharedPreferences.getInstance();
      final prefix = 'p.$profileId.g.1.';
      await raw.setString(
        '${prefix}engine_custom_indexer_api_key',
        'engine-setting-secret',
      );
      await raw.setBool('${prefix}engine_custom_indexer_enabled', true);

      final package =
          await ProfilePackageService(
            registry: registry,
            resources: ConnectionResourceService(
              registry: registry,
              cipher: cipher,
            ),
          ).exportProfile(
            context: await ProfileAuthorizationContext.capture(registry),
            scope: ProfileRuntime.capture(),
            includeSecrets: false,
            sanitized: false,
          );

      final values =
          (package.sections['profile-0-preferences'] as Map)['values'] as Map;
      expect(values, isNot(contains('engine_custom_indexer_api_key')));
      expect(values['engine_custom_indexer_enabled'], isTrue);
    },
  );

  test(
    'compact profile package reports complete Debrify TV omission',
    () async {
      final scope = ProfileRuntime.capture();
      final source = scope.fileIn(documents, 'documents', 'debrify_tv.db');
      await source.parent.create(recursive: true);
      final database = await openDatabase(source.path, singleInstance: false);
      await database.execute(
        'CREATE TABLE tv_channels (channel_id TEXT PRIMARY KEY)',
      );
      await database.execute(
        'CREATE TABLE tv_cached_torrents '
        '(channel_id TEXT NOT NULL, infohash TEXT NOT NULL)',
      );
      await database.insert('tv_channels', <String, Object?>{
        'channel_id': 'portable-channel',
      });
      await database.insert('tv_cached_torrents', <String, Object?>{
        'channel_id': 'portable-channel',
        'infohash': 'portable-hash',
      });
      await database.close();

      final package =
          await ProfilePackageService(
            registry: registry,
            resources: ConnectionResourceService(
              registry: registry,
              cipher: cipher,
            ),
          ).exportProfile(
            context: await ProfileAuthorizationContext.capture(registry),
            scope: scope,
            includeSecrets: true,
            sanitized: false,
            compactDatabaseSnapshots: true,
          );

      final omission = DebrifyTvBackupOmission.fromOmissions(package.omissions);
      expect(omission?.channels, 1);
      expect(omission?.savedHashes, 1);
      expect(omission?.profilesAffected, 1);
      expect(
        package.omissions,
        isNot(contains('rebuildableDatabaseCachesOmitted')),
      );
    },
  );

  test(
    'compacted TV omission drops matching sync stamps so a joiner backfills',
    () async {
      final scope = ProfileRuntime.capture();
      final source = scope.fileIn(documents, 'documents', 'debrify_tv.db');
      await source.parent.create(recursive: true);
      final database = await openDatabase(source.path, singleInstance: false);
      await database.execute(
        'CREATE TABLE tv_channels (channel_id TEXT PRIMARY KEY)',
      );
      await database.execute(
        'CREATE TABLE tv_cached_torrents '
        '(channel_id TEXT NOT NULL, infohash TEXT NOT NULL)',
      );
      await database.execute(
        'CREATE TABLE webdav_sync_record_state ('
        'kind TEXT NOT NULL, owner_key TEXT NOT NULL, '
        'item_key TEXT NOT NULL, updated_at_ms INTEGER NOT NULL, '
        'origin_device_id TEXT NOT NULL, normalized INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL, aux TEXT, '
        'PRIMARY KEY (kind, owner_key, item_key))',
      );
      await database.insert('tv_channels', <String, Object?>{
        'channel_id': 'portable-channel',
      });
      await database.insert('tv_cached_torrents', <String, Object?>{
        'channel_id': 'portable-channel',
        'infohash': 'portable-hash',
      });
      for (final kind in const <String>[
        'tv_channels',
        'tv_pool_generation',
        'video_resume',
      ]) {
        await database.insert('webdav_sync_record_state', <String, Object?>{
          'kind': kind,
          'owner_key': 'portable-channel',
          'item_key': '',
          'updated_at_ms': 111,
          'origin_device_id': 'other-device',
          'normalized': 1,
          'deleted': 0,
          'aux': kind == 'tv_pool_generation' ? 'generation-one' : null,
        });
      }
      await database.close();

      final authorization = await ProfileAuthorizationContext.capture(registry);
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: ConnectionResourceService(
              registry: registry,
              cipher: cipher,
            ),
          ).exportAllProfiles(
            context: authorization,
            includeSecrets: true,
            compactDatabaseSnapshots: true,
          );
      expect(package.omissions, contains(DebrifyTvBackupOmission.key));

      final report = await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);
      expect(report.profilesImported, 1);
      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      final importedScope = ProfileScope(
        profileId: imported.id,
        dataGeneration: imported.visibleDataGeneration,
        sessionEpoch: 0,
      );
      final restored = await openDatabase(
        importedScope.fileIn(documents, 'documents', 'debrify_tv.db').path,
        readOnly: true,
        singleInstance: false,
      );
      expect(await restored.query('tv_channels'), isEmpty);
      expect(
        await restored.query(
          'webdav_sync_record_state',
          where: 'kind IN (?, ?)',
          whereArgs: const <Object>['tv_channels', 'tv_pool_generation'],
        ),
        isEmpty,
      );
      expect(
        await restored.query(
          'webdav_sync_record_state',
          where: 'kind = ?',
          whereArgs: const <Object>['video_resume'],
        ),
        hasLength(1),
      );
      await restored.close();
    },
  );

  test('publishes only the finalized staged generation', () async {
    final section = await PortableProfilePackage.buildSection(
      const <String, Object?>{'theme_mode': 'restored', 'language': 'en'},
    );
    final package = PortableProfilePackage(
      mode: 'singleProfile',
      createdAt: DateTime.utc(2026, 8, 13),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          'preferencesSection': 'preferences',
        },
      ],
      resources: const <Map<String, dynamic>>[],
      sections: <String, dynamic>{'preferences': section},
    );

    final report =
        await ProfileRestoreCoordinator(
          registry: registry,
          cipher: cipher,
        ).restore(
          package: package,
          destinationProfileId: profileId,
          authorization: await ProfileAuthorizationContext.capture(registry),
        );

    expect(report.publishedGeneration, 2);
    expect(ProfileRuntime.capture().dataGeneration, 2);
    expect((await registry.getProfile(profileId))?.visibleDataGeneration, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('p.$profileId.g.1.theme_mode'), 'old');
    expect(prefs.getString('p.$profileId.g.2.theme_mode'), 'restored');
    expect(prefs.getString('p.$profileId.g.2.language'), 'en');
  });

  test(
    'active restore republishes generation before recovery checkpoint',
    () async {
      final original = ProfileRuntime.capture();
      var observedPublication = false;
      registry.authorityChangedCallback = () async {
        final active = (await registry.getProfile(profileId))!;
        if (active.visibleDataGeneration == original.dataGeneration) return;
        observedPublication = true;
        expect(
          ProfileRuntime.capture().dataGeneration,
          active.visibleDataGeneration,
        );
        expect(
          ProfileRuntime.capture().sessionEpoch,
          greaterThan(original.sessionEpoch),
        );
        await (await ProfileAuthorizationContext.capture(
          registry,
        )).validate(registry);
      };
      await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restore(
        package: await _singleProfilePackage(setupComplete: false),
        destinationProfileId: profileId,
        authorization: await ProfileAuthorizationContext.capture(registry),
      );
      expect(observedPublication, isTrue);
    },
  );

  for (final importedSetupComplete in <bool?>[null, false]) {
    final sourceLabel = importedSetupComplete == null
        ? 'missing setup state'
        : 'setup incomplete';
    test('onboarding restore publishes completion with $sourceLabel', () async {
      expect((await registry.getProfile(profileId))?.setupComplete, isFalse);
      final observer = _SetupCompleteObserver(registry, profileId);

      await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
        lifecycleParticipants: <ProfileLifecycleParticipant>[observer],
      ).restore(
        package: await _singleProfilePackage(
          setupComplete: importedSetupComplete,
        ),
        destinationProfileId: profileId,
        authorization: await ProfileAuthorizationContext.capture(registry),
        completeOnboarding: true,
      );

      expect(
        observer.setupCompleteDuringCandidateInitialization,
        isTrue,
        reason:
            'completion must be visible when the new epoch remounts the app',
      );
      expect((await registry.getProfile(profileId))?.setupComplete, isTrue);
    });
  }

  test('ordinary restore still applies the backup setup state', () async {
    var authorization = await ProfileAuthorizationContext.capture(registry);
    await registry.setActiveProfileSetupComplete(
      profileId: profileId,
      setupComplete: true,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
    expect((await registry.getProfile(profileId))?.setupComplete, isTrue);
    authorization = await ProfileAuthorizationContext.capture(registry);
    final observer = _SetupCompleteObserver(registry, profileId);

    await ProfileRestoreCoordinator(
      registry: registry,
      cipher: cipher,
      lifecycleParticipants: <ProfileLifecycleParticipant>[observer],
    ).restore(
      package: await _singleProfilePackage(setupComplete: false),
      destinationProfileId: profileId,
      authorization: authorization,
    );

    expect(observer.setupCompleteDuringCandidateInitialization, isFalse);
    expect((await registry.getProfile(profileId))?.setupComplete, isFalse);
  });

  test('v3 restore drops preferences that became non-portable in v4', () async {
    final section =
        await PortableProfilePackage.buildSection(const <String, Object?>{
          'theme_mode': 'restored',
          'tvmaze_cache_episodes_1139': 'rebuildable-cache',
          'webdav_username': 'superseded-account-field',
        });
    final source = PortableProfilePackage(
      mode: 'singleProfile',
      createdAt: DateTime.utc(2026, 8, 13),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          'preferencesSection': 'preferences',
        },
      ],
      resources: const <Map<String, dynamic>>[],
      sections: <String, dynamic>{'preferences': section},
    );
    final package = await PortableProfilePackage.decrypt(
      await _legacyV3EncryptedEnvelope(source, 'correct horse'),
      'correct horse',
    );
    expect(package.sourceVersion, 3);

    final report =
        await ProfileRestoreCoordinator(
          registry: registry,
          cipher: cipher,
        ).restore(
          package: package,
          destinationProfileId: profileId,
          authorization: await ProfileAuthorizationContext.capture(registry),
        );

    expect(report.preferencesApplied, 1);
    final raw = await SharedPreferences.getInstance();
    final prefix = 'p.$profileId.g.${report.publishedGeneration}.';
    expect(raw.getString('${prefix}theme_mode'), 'restored');
    expect(raw.containsKey('${prefix}tvmaze_cache_episodes_1139'), isFalse);
    expect(raw.containsKey('${prefix}webdav_username'), isFalse);
  });

  test('v4 restore rejects a preference forbidden by current policy', () async {
    final section = await PortableProfilePackage.buildSection(
      const <String, Object?>{
        'theme_mode': 'restored',
        'tvmaze_cache_episodes_1139': 'unexpected-cache',
      },
    );
    final package = PortableProfilePackage(
      mode: 'singleProfile',
      createdAt: DateTime.utc(2026, 8, 29),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          'preferencesSection': 'preferences',
        },
      ],
      resources: const <Map<String, dynamic>>[],
      sections: <String, dynamic>{'preferences': section},
    );

    await expectLater(
      ProfileRestoreCoordinator(registry: registry, cipher: cipher).restore(
        package: package,
        destinationProfileId: profileId,
        authorization: await ProfileAuthorizationContext.capture(registry),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Forbidden restored preference tvmaze_cache_episodes_1139',
        ),
      ),
    );
    expect(ProfileRuntime.capture().dataGeneration, 1);
  });

  test('v3 single-profile restore skips a degenerate owned resource', () async {
    final section = await PortableProfilePackage.buildSection(
      const <String, Object?>{'theme_mode': 'restored'},
    );
    final package = PortableProfilePackage(
      sourceVersion: 3,
      mode: 'singleProfile',
      createdAt: DateTime.utc(2026, 8, 13),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          'preferencesSection': 'preferences',
        },
      ],
      resources: <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'empty-resource',
          'type': ConnectionResourceType.realDebrid.name,
          'label': 'Empty legacy connection',
          'owned': true,
          'secretConfig': <String, dynamic>{},
        },
      ],
      sections: <String, dynamic>{'preferences': section},
    );

    final report =
        await ProfileRestoreCoordinator(
          registry: registry,
          cipher: cipher,
        ).restore(
          package: package,
          destinationProfileId: profileId,
          authorization: await ProfileAuthorizationContext.capture(registry),
        );

    expect(report.resourcesImported, 0);
    expect(await registry.listGrantedResources(profileId), isEmpty);
    expect(report.publishedGeneration, 2);

    final currentPackage = PortableProfilePackage(
      mode: package.mode,
      createdAt: DateTime.utc(2026, 8, 29),
      profiles: package.profiles,
      resources: package.resources,
      sections: package.sections,
    );
    await expectLater(
      ProfileRestoreCoordinator(registry: registry, cipher: cipher).restore(
        package: currentPackage,
        destinationProfileId: profileId,
        authorization: await ProfileAuthorizationContext.capture(registry),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Imported resource secret is empty',
        ),
      ),
    );
    expect(ProfileRuntime.capture().dataGeneration, 2);
  });

  test('an unknown avatar key does not block single-profile restore', () async {
    var authorization = await ProfileAuthorizationContext.capture(registry);
    await registry.updateProfile(
      id: profileId,
      avatarKey: 'future-avatar:nebula',
      actingProfileId: authorization.profileId,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
    authorization = await ProfileAuthorizationContext.capture(registry);
    final section = await PortableProfilePackage.buildSection(
      const <String, Object?>{'theme_mode': 'restored'},
    );
    final package = PortableProfilePackage(
      mode: 'singleProfile',
      createdAt: DateTime.utc(2026, 8, 14),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          'preferencesSection': 'preferences',
        },
      ],
      resources: const <Map<String, dynamic>>[],
      sections: <String, dynamic>{'preferences': section},
    );

    final report =
        await ProfileRestoreCoordinator(
          registry: registry,
          cipher: cipher,
        ).restore(
          package: package,
          destinationProfileId: profileId,
          authorization: authorization,
        );

    expect(report.publishedGeneration, 2);
    expect(
      (await registry.getProfile(profileId))?.avatarKey,
      'future-avatar:nebula',
    );
  });

  test('invalid preference overlay never changes visible authority', () async {
    final section = await PortableProfilePackage.buildSection(<String, Object?>{
      List<String>.filled(257, 'x').join(): 'invalid',
    });
    final package = PortableProfilePackage(
      mode: 'singleProfile',
      createdAt: DateTime.utc(2026, 8, 13),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          'preferencesSection': 'preferences',
        },
      ],
      resources: const <Map<String, dynamic>>[],
      sections: <String, dynamic>{'preferences': section},
    );

    await expectLater(
      ProfileRestoreCoordinator(registry: registry, cipher: cipher).restore(
        package: package,
        destinationProfileId: profileId,
        authorization: await ProfileAuthorizationContext.capture(registry),
      ),
      throwsA(anything),
    );
    expect(ProfileRuntime.capture().dataGeneration, 1);
    expect((await registry.getProfile(profileId))?.visibleDataGeneration, 1);
  });

  test(
    'device-sealed IPTV execution blobs never cross a profile package',
    () async {
      final raw = await SharedPreferences.getInstance();
      final prefix = 'p.$profileId.g.1.';
      for (final key in const <String>{
        'iptv_last_live_channel',
        'startup_iptv_channel',
      }) {
        await raw.setString('$prefix$key', 'enc1:source-device-ciphertext');
      }

      final authorization = await ProfileAuthorizationContext.capture(registry);
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: ConnectionResourceService(
              registry: registry,
              cipher: cipher,
            ),
          ).exportProfile(
            context: authorization,
            scope: ProfileRuntime.capture(),
            includeSecrets: true,
            sanitized: false,
          );
      final exported =
          (package.sections['profile-0-preferences'] as Map)['values'] as Map;
      for (final key in const <String>{
        'iptv_last_live_channel',
        'startup_iptv_channel',
      }) {
        expect(exported, contains(key));
        expect(exported[key], isNull);
      }

      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restore(
            package: package,
            destinationProfileId: profileId,
            authorization: authorization,
          );
      for (final key in const <String>{
        'iptv_last_live_channel',
        'startup_iptv_channel',
      }) {
        expect(
          raw.containsKey('p.$profileId.g.${report.publishedGeneration}.$key'),
          isFalse,
        );
      }
    },
  );

  test(
    'legacy IPTV memberships bind to the staged destination provider',
    () async {
      const oldProviderId = 'iptv-1';
      final package = LegacyBackupAdapter.adapt(<String, dynamic>{
        'version': 1,
        'createdAt': '2026-08-13T00:00:00.000Z',
        'iptvPlaylists': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': oldProviderId,
            'name': 'Provider',
            'url': 'https://provider.invalid/list.m3u',
            'addedAt': '2026-08-13T00:00:00.000Z',
          },
        ],
        'iptvFavorites': <Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://provider.invalid/live/one',
            'name': 'One',
            'playlistId': oldProviderId,
          },
        ],
        'iptvLists': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Sports',
            'channels': <Map<String, dynamic>>[
              <String, dynamic>{
                'url': 'https://provider.invalid/live/two',
                'name': 'Two',
                'playlistId': oldProviderId,
              },
            ],
          },
        ],
      });

      await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restore(
        package: package,
        destinationProfileId: profileId,
        authorization: await ProfileAuthorizationContext.capture(registry),
      );

      final providers = await registry.listGrantedResources(profileId);
      expect(providers, hasLength(1));
      final destinationProviderId = providers.single.id;
      expect(destinationProviderId, isNot(oldProviderId));
      final favorites = await IptvMediaStore.listChannels(
        IptvMediaStore.favoritesListId,
      );
      expect(
        favorites['https://provider.invalid/live/one']?['playlistId'],
        destinationProviderId,
      );
      final sports = (await IptvMediaStore.lists()).singleWhere(
        (item) => item.name == 'Sports',
      );
      final sportsChannels = await IptvMediaStore.listChannels(sports.id);
      expect(
        sportsChannels['https://provider.invalid/live/two']?['playlistId'],
        destinationProviderId,
      );
    },
  );

  test('a restored Xtream provider keeps its empty url', () async {
    // Same defect the legacy→profile migration had: an Xtream provider stores
    // `url: ''` because its endpoint is serverUrl, and stripping empty values
    // before sealing erased a key the reader casts non-null — which threw for
    // the whole playlist collection, not just the one provider.
    final package = LegacyBackupAdapter.adapt(<String, dynamic>{
      'version': 1,
      'createdAt': '2026-08-14T00:00:00.000Z',
      'iptvPlaylists': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'xtream-1',
          'name': 'Panel',
          'url': '',
          'serverUrl': 'https://panel.invalid:8080',
          'username': 'user',
          'password': 'pass',
          'addedAt': '2026-08-14T00:00:00.000Z',
        },
      ],
    });

    await ProfileRestoreCoordinator(registry: registry, cipher: cipher).restore(
      package: package,
      destinationProfileId: profileId,
      authorization: await ProfileAuthorizationContext.capture(registry),
    );

    final resource = (await registry.listGrantedResources(profileId)).single;
    expect(resource.type, ConnectionResourceType.iptvXtream);
    final secret =
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).resolveSecretForUse(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: resource.id,
          feature: ProfileFeature.iptv,
        );
    expect(secret.containsKey('url'), isTrue);
    expect(secret['url'], '');
    expect(secret['serverUrl'], 'https://panel.invalid:8080');
  });

  test(
    'single-profile restore publishes resource-local settings atomically',
    () async {
      final service = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      var authorization = await ProfileAuthorizationContext.capture(registry);
      final sourceResource = await service.create(
        context: authorization,
        type: ConnectionResourceType.stremioAddon,
        label: 'Locally disabled addon',
        publicConfig: const <String, dynamic>{
          'addonName': 'Locally disabled addon',
          'contentKinds': <String>['series'],
        },
        secretConfig: const <String, dynamic>{
          'id': 'locally-disabled-addon',
          'name': 'Locally disabled addon',
          'manifest_url': 'https://disabled.invalid/manifest.json',
          'base_url': 'https://disabled.invalid',
          'enabled': true,
          'types': <String>['series'],
          'resources': <String>['stream'],
        },
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.setProfileResourceSettings(
        profileId: profileId,
        resourceId: sourceResource.id,
        enabled: false,
        settings: const <String, dynamic>{'presentation': 'compact'},
        actingAuthorizationRevision: authorization.authorizationRevision,
        expectedResourceAuthorizationRevision:
            sourceResource.authorizationRevision,
        feature: ProfileFeature.addonsAndEngines,
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: service,
          ).exportProfile(
            context: authorization,
            scope: ProfileRuntime.capture(),
            includeSecrets: true,
            sanitized: false,
          );

      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restore(
            package: package,
            destinationProfileId: profileId,
            authorization: authorization,
          );
      expect(report.resourcesImported, 1);
      final imported = (await registry.listGrantedResources(profileId))
          .singleWhere(
            (resource) =>
                resource.label == 'Locally disabled addon' &&
                resource.id != sourceResource.id,
          );
      final settings = await registry.getProfileResourceSettings(
        profileId,
        imported.id,
      );
      expect(settings?.enabled, isFalse);
      expect(settings?.settings, <String, dynamic>{'presentation': 'compact'});
    },
  );

  test(
    'single-profile backup preserves an owned disabled connection',
    () async {
      const sourceId = 'disabled-single-profile-resource';
      const type = ConnectionResourceType.reddit;
      final sealed = await cipher.seal(
        utf8.encode(
          jsonEncode(const <String, Object?>{'accessToken': 'archived-token'}),
        ),
        associatedData: utf8.encode(
          'debrify-resource|id=$sourceId|type=${type.name}|'
          'owner=$profileId|public=1|secret=1',
        ),
      );
      var authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.insertResource(
        resource: ConnectionResource(
          id: sourceId,
          type: type,
          label: 'Archived Reddit',
          ownerProfileId: profileId,
          publicConfig: const <String, dynamic>{
            'schemaVersion': 1,
            'accountLabel': 'Archived Reddit',
          },
          authorizationRevision: 1,
          enabled: false,
        ),
        sealedSecretPayload: sealed,
        secretPayloadVersion: 1,
        ownerPermissions: ResourcePermission.values.fold<int>(
          0,
          (mask, permission) => mask | permission.bit,
        ),
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
      );

      authorization = await ProfileAuthorizationContext.capture(registry);
      final service = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: service,
          ).exportProfile(
            context: authorization,
            scope: ProfileRuntime.capture(),
            includeSecrets: true,
            sanitized: false,
          );
      expect(package.resources.single['disabled'], isTrue);

      final report =
          await ProfileRestoreCoordinator(
            registry: registry,
            cipher: cipher,
          ).restore(
            package: package,
            destinationProfileId: profileId,
            authorization: authorization,
          );
      expect(report.resourcesImported, 1);
      final imported = (await registry.listAllResourcesIncludingDisabled())
          .singleWhere(
            (resource) =>
                resource.label == 'Archived Reddit' && resource.id != sourceId,
          );
      expect(imported.enabled, isFalse);
      expect(
        (await registry.listGrantedResources(
          profileId,
        )).map((resource) => resource.id),
        isNot(contains(imported.id)),
      );
      expect(
        await service.revealOwnedSecretForProfileBackup(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: imported.id,
        ),
        <String, dynamic>{'accessToken': 'archived-token'},
      );
    },
  );

  test('graph verification rejects bytes changed after finalization', () async {
    const operationId = 'graph-byte-mutation';
    const stagedProfileId = 'staged-profile';
    await registry.beginProfileGraphRestore(
      operationId: operationId,
      stagedProfileIds: const <String>[stagedProfileId],
    );
    final actor = await ProfileAuthorizationContext.capture(registry);
    await registry.createProfile(
      id: stagedProfileId,
      name: 'Staged',
      role: UserProfileRole.member,
      lifecycle: UserProfileLifecycle.staging,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    final scope = ProfileScope(
      profileId: stagedProfileId,
      dataGeneration: 1,
      sessionEpoch: 0,
    );
    final stagedFile = scope.fileIn(
      documents,
      'documents',
      p.join('engines', 'custom.json'),
    );
    await stagedFile.parent.create(recursive: true);
    await stagedFile.writeAsString('{"value":1}', flush: true);
    final manager = ProfileDataGenerationManager(registry);
    await manager.finalizeGraphProfile(
      operationId: operationId,
      profileId: stagedProfileId,
    );

    await stagedFile.writeAsString('{"value":2}', flush: true);

    await expectLater(
      manager.verifyGraphProfile(
        operationId: operationId,
        profileId: stagedProfileId,
      ),
      throwsStateError,
    );
  });

  test('a carried PIN and its recovery code survive graph restore', () async {
    final pins = ProfilePinService(
      registry: registry,
      params: const PinKdfParams(memory: 64, iterations: 1),
    );
    final recoveryCode = await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '4826',
    );

    final authorization = await ProfileAuthorizationContext.capture(registry);
    final service = ProfilePackageService(
      registry: registry,
      resources: ConnectionResourceService(registry: registry, cipher: cipher),
    );
    final package = await service.exportAllProfiles(
      context: authorization,
      includeSecrets: true,
    );
    final report = await ProfileRestoreCoordinator(
      registry: registry,
      cipher: cipher,
    ).restoreDeviceGraph(package: package, authorization: authorization);

    // The PIN traveled: nothing to reset, and the imported profile opens
    // with the ORIGINAL pin and honors the ORIGINAL recovery code.
    expect(report.pinResetsRequired, 0);
    final imported = (await registry.listProfiles()).singleWhere(
      (profile) => profile.id != profileId,
    );
    expect(
      (await pins.verify(imported.id, '4826')).result,
      ProfilePinResult.verified,
    );
    expect(
      await pins.verifyRecoveryCode(imported.id, recoveryCode),
      ProfileRecoveryResult.cleared,
    );
  });

  test(
    'graph restore prunes an inherited duplicate addon but keeps receiver-only addons',
    () async {
      const duplicateManifest = 'https://v3-cinemeta.strem.io/manifest.json';
      const receiverOnlyManifest =
          'https://receiver-only.invalid/manifest.json';
      final resourceService = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final originalDuplicate = await resourceService.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.stremioAddon,
        label: 'Cinemeta',
        publicConfig: const <String, dynamic>{
          'addonName': 'Cinemeta',
          'contentKinds': <String>['movie', 'series'],
        },
        secretConfig: const <String, dynamic>{
          'id': 'com.linvo.cinemeta',
          'name': 'Cinemeta',
          'manifest_url': duplicateManifest,
          'base_url': 'https://v3-cinemeta.strem.io',
          'enabled': true,
          'types': <String>['movie', 'series'],
          'resources': <String>['catalog', 'meta'],
        },
      );
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: resourceService,
          ).exportAllProfiles(
            context: await ProfileAuthorizationContext.capture(registry),
            includeSecrets: true,
          );

      // This resource exists only on the receiver. Imported profiles should
      // continue to inherit it; only the exact Cinemeta duplicate is removed.
      final receiverOnly = await resourceService.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.stremioAddon,
        label: 'Receiver-only addon',
        publicConfig: const <String, dynamic>{
          'addonName': 'Receiver-only addon',
          'contentKinds': <String>['movie'],
        },
        secretConfig: const <String, dynamic>{
          'id': 'receiver-only',
          'name': 'Receiver-only addon',
          'manifest_url': receiverOnlyManifest,
          'base_url': 'https://receiver-only.invalid',
          'enabled': true,
          'types': <String>['movie'],
          'resources': <String>['stream'],
        },
      );

      await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(
        package: package,
        authorization: await ProfileAuthorizationContext.capture(registry),
      );

      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      final grantedAddons = (await registry.listGrantedResources(imported.id))
          .where(
            (resource) => resource.type == ConnectionResourceType.stremioAddon,
          )
          .toList();
      expect(grantedAddons, hasLength(2));
      expect(
        grantedAddons.where((resource) => resource.label == 'Cinemeta'),
        hasLength(1),
      );
      expect(
        grantedAddons
            .singleWhere((resource) => resource.label == 'Cinemeta')
            .ownerProfileId,
        imported.id,
      );
      expect(
        grantedAddons.map((resource) => resource.id),
        contains(receiverOnly.id),
      );
      expect(
        await registry.getGrant(imported.id, originalDuplicate.id),
        isNull,
      );
      expect(await registry.getGrant(imported.id, receiverOnly.id), isNotNull);
    },
  );

  test(
    'a disabled profile keeps its PIN and recovery code through graph restore',
    () async {
      final pins = ProfilePinService(
        registry: registry,
        params: const PinKdfParams(memory: 64, iterations: 1),
      );
      var authorization = await ProfileAuthorizationContext.capture(registry);
      final archived = await registry.createProfile(
        name: 'Archived member',
        role: UserProfileRole.member,
        setupComplete: true,
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final recoveryCode = await pins.setPinAsAdmin(
        actor: authorization,
        targetProfileId: archived.id,
        pin: '1957',
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.disableProfile(
        archived.id,
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );

      authorization = await ProfileAuthorizationContext.capture(registry);
      final package = await ProfilePackageService(
        registry: registry,
        resources: ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ),
      ).exportAllProfiles(context: authorization, includeSecrets: true);
      final archivedRecord = package.profiles.singleWhere(
        (record) => record['name'] == 'Archived member',
      );
      expect(archivedRecord['disabled'], isTrue);
      expect(archivedRecord['pinRecord'], isA<Map>());

      final report = await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);

      expect(report.pinResetsRequired, 0);
      final importedArchived =
          (await registry.listProfiles(includeDisabled: true)).singleWhere(
            (profile) =>
                profile.id != archived.id && profile.name == 'Archived member',
          );
      expect(importedArchived.isEnabled, isFalse);
      authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.enableProfile(
        importedArchived.id,
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
      expect(
        (await pins.verify(importedArchived.id, '1957')).result,
        ProfilePinResult.verified,
      );
      expect(
        await pins.verifyRecoveryCode(importedArchived.id, recoveryCode),
        ProfileRecoveryResult.cleared,
      );
    },
  );

  test('a broken carried recovery trio degrades to PIN-only', () async {
    final pins = ProfilePinService(
      registry: registry,
      params: const PinKdfParams(memory: 64, iterations: 1),
    );
    final recoveryCode = await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '4826',
    );
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final package = await ProfilePackageService(
      registry: registry,
      resources: ConnectionResourceService(registry: registry, cipher: cipher),
    ).exportAllProfiles(context: authorization, includeSecrets: true);
    (package.profiles.single['pinRecord'] as Map)['recoveryHash'] = 'broken';

    final report = await ProfileRestoreCoordinator(
      registry: registry,
      cipher: cipher,
    ).restoreDeviceGraph(package: package, authorization: authorization);

    // The PIN still travels; only the recovery code is dropped.
    expect(report.pinResetsRequired, 0);
    final imported = (await registry.listProfiles()).singleWhere(
      (profile) => profile.id != profileId,
    );
    expect(
      (await pins.verify(imported.id, '4826')).result,
      ProfilePinResult.verified,
    );
    expect(
      await pins.verifyRecoveryCode(imported.id, recoveryCode),
      ProfileRecoveryResult.notConfigured,
    );
  });

  test('a reset-required profile exports no PIN record', () async {
    final pins = ProfilePinService(
      registry: registry,
      params: const PinKdfParams(memory: 64, iterations: 1),
    );
    await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '4826',
    );
    await pins.requireAdminReset(profileId);

    final authorization = await ProfileAuthorizationContext.capture(registry);
    final package = await ProfilePackageService(
      registry: registry,
      resources: ConnectionResourceService(registry: registry, cipher: cipher),
    ).exportAllProfiles(context: authorization, includeSecrets: true);

    // A backup taken during a lockdown must not carry a credential that
    // could undo it — only the protected flag travels.
    expect(package.profiles.single.containsKey('pinRecord'), isFalse);
    expect(package.profiles.single['wasPinProtected'], isTrue);
  });

  test('a malformed carried PIN degrades to admin reset', () async {
    final pins = ProfilePinService(
      registry: registry,
      params: const PinKdfParams(memory: 64, iterations: 1),
    );
    await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '4826',
    );
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final package = await ProfilePackageService(
      registry: registry,
      resources: ConnectionResourceService(registry: registry, cipher: cipher),
    ).exportAllProfiles(context: authorization, includeSecrets: true);
    (package.profiles.single['pinRecord'] as Map)['hash'] = 'tampered';

    final report = await ProfileRestoreCoordinator(
      registry: registry,
      cipher: cipher,
    ).restoreDeviceGraph(package: package, authorization: authorization);

    expect(report.pinResetsRequired, 1);
    final imported = (await registry.listProfiles()).singleWhere(
      (profile) => profile.id != profileId,
    );
    expect(
      (await pins.verify(imported.id, '4826')).result,
      ProfilePinResult.resetRequired,
    );
  });

  test(
    'metadata provider still matches after graph restore recreates its resource',
    () async {
      const manifestUrl = 'https://metadata.invalid/config-token/manifest.json';
      final addon = StremioAddon(
        id: 'configured.metadata',
        name: 'Configured metadata',
        manifestUrl: manifestUrl,
        baseUrl: 'https://metadata.invalid/config-token',
        types: const <String>['movie', 'series'],
        resources: const <String>['meta'],
      );
      final resourceService = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      final originalResource = await resourceService.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.stremioAddon,
        label: addon.name,
        publicConfig: <String, dynamic>{
          'addonName': addon.name,
          'contentKinds': addon.types,
        },
        secretConfig: addon.toJson(),
      );
      final selectedValue = StremioService.metadataProviderValue(
        addon.copyWith(connectionResourceId: originalResource.id),
      );
      await StremioService.instance.setMetadataProviderPreference(
        selectedValue,
      );

      final authorization = await ProfileAuthorizationContext.capture(registry);
      final package = await ProfilePackageService(
        registry: registry,
        resources: resourceService,
      ).exportAllProfiles(context: authorization, includeSecrets: true);
      final report = await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);

      for (final record in package.resources) {
        final backupId = record['backupId']! as String;
        final restoredId = report.importedResourceIdsByBackupId[backupId];
        expect(restoredId, isNotNull);
        expect(
          (await registry.listAllResourcesIncludingDisabled()).map(
            (resource) => resource.id,
          ),
          contains(restoredId),
        );
      }

      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      final recreatedResource =
          (await registry.listGrantedResources(imported.id)).firstWhere(
            (resource) =>
                resource.type == ConnectionResourceType.stremioAddon &&
                resource.id != originalResource.id,
          );
      expect(recreatedResource.id, isNot(originalResource.id));
      final restoredValue = (await SharedPreferences.getInstance()).getString(
        'p.${imported.id}.g.${imported.visibleDataGeneration}.'
        'stremio_metadata_provider_v1',
      );
      expect(restoredValue, selectedValue);
      expect(
        StremioService.metadataProviderValue(
          addon.copyWith(connectionResourceId: recreatedResource.id),
        ),
        restoredValue,
      );
    },
  );

  test(
    'graph preserves lock settings, resource-local state, IDs, and disabled resources',
    () async {
      var authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.updateProfile(
        id: profileId,
        lockOnResume: true,
        inactivityTimeoutMinutes: 15,
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );

      final resourceService = ConnectionResourceService(
        registry: registry,
        cipher: cipher,
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final enabledResource = await resourceService.create(
        context: authorization,
        type: ConnectionResourceType.stremioAddon,
        label: 'Portable addon',
        publicConfig: const <String, dynamic>{
          'addonName': 'Portable addon',
          'contentKinds': <String>['movie'],
        },
        secretConfig: const <String, dynamic>{
          'id': 'portable-addon',
          'name': 'Portable addon',
          'manifest_url': 'https://addon.invalid/manifest.json',
          'base_url': 'https://addon.invalid',
          'enabled': true,
          'types': <String>['movie'],
          'resources': <String>['stream'],
        },
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.setProfileResourceSettings(
        profileId: profileId,
        resourceId: enabledResource.id,
        enabled: false,
        settings: <String, dynamic>{
          'selectedResource': enabledResource.id,
          'nested': <String, dynamic>{'source': enabledResource.id},
        },
        actingAuthorizationRevision: authorization.authorizationRevision,
        expectedResourceAuthorizationRevision:
            enabledResource.authorizationRevision,
        feature: ProfileFeature.addonsAndEngines,
      );
      final preferences = await ProfilePreferences.instance();
      await preferences.setString('selected_resource', enabledResource.id);
      await preferences.setString(
        'resource_layout_v1',
        jsonEncode(<String, Object?>{
          'primary': enabledResource.id,
          'items': <String>[enabledResource.id],
        }),
      );
      await preferences.setString(
        'engine_custom_indexer_api_key',
        'engine-setting-sentinel',
      );

      const disabledId = 'disabled-resource-sentinel';
      const disabledType = ConnectionResourceType.reddit;
      final disabledSecret = await cipher.seal(
        utf8.encode(
          jsonEncode(const <String, Object?>{'accessToken': 'archived-token'}),
        ),
        associatedData: utf8.encode(
          'debrify-resource|id=$disabledId|type=${disabledType.name}|'
          'owner=$profileId|public=1|secret=1',
        ),
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      await registry.insertResource(
        resource: ConnectionResource(
          id: disabledId,
          type: disabledType,
          label: 'Disabled archive',
          ownerProfileId: profileId,
          publicConfig: const <String, dynamic>{
            'schemaVersion': 1,
            'accountLabel': 'Disabled archive',
          },
          authorizationRevision: 1,
          enabled: false,
        ),
        sealedSecretPayload: disabledSecret,
        secretPayloadVersion: 1,
        ownerPermissions: ResourcePermission.values.fold<int>(
          0,
          (mask, permission) => mask | permission.bit,
        ),
        actingProfileId: authorization.profileId,
        actingAuthorizationRevision: authorization.authorizationRevision,
      );

      authorization = await ProfileAuthorizationContext.capture(registry);
      final package = await ProfilePackageService(
        registry: registry,
        resources: resourceService,
      ).exportAllProfiles(context: authorization, includeSecrets: true);
      expect(
        package.resources.singleWhere(
          (record) => record['sourceResourceId'] == disabledId,
        )['disabled'],
        isTrue,
      );

      await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);

      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      expect(imported.lockOnResume, isTrue);
      expect(imported.inactivityTimeoutMinutes, 15);
      final recreated = (await registry.listAllResourcesIncludingDisabled())
          .where((resource) => resource.ownerProfileId == imported.id)
          .toList();
      final recreatedEnabled = recreated.singleWhere(
        (resource) => resource.label == 'Portable addon',
      );
      final recreatedDisabled = recreated.singleWhere(
        (resource) => resource.label == 'Disabled archive',
      );
      expect(recreatedEnabled.id, isNot(enabledResource.id));
      expect(recreatedDisabled.enabled, isFalse);
      expect(
        (await registry.listGrantedResources(
          imported.id,
        )).map((resource) => resource.id),
        isNot(contains(recreatedDisabled.id)),
      );

      final localSettings = await registry.getProfileResourceSettings(
        imported.id,
        recreatedEnabled.id,
      );
      expect(localSettings?.enabled, isFalse);
      expect(localSettings?.settings['selectedResource'], recreatedEnabled.id);
      expect(
        (localSettings?.settings['nested'] as Map?)?['source'],
        recreatedEnabled.id,
      );

      final raw = await SharedPreferences.getInstance();
      final prefix = 'p.${imported.id}.g.${imported.visibleDataGeneration}.';
      expect(raw.getString('${prefix}selected_resource'), recreatedEnabled.id);
      final layout = jsonDecode(raw.getString('${prefix}resource_layout_v1')!);
      expect(layout['primary'], recreatedEnabled.id);
      expect(layout['items'], <Object?>[recreatedEnabled.id]);
      expect(
        raw.getString('${prefix}engine_custom_indexer_api_key'),
        'engine-setting-sentinel',
      );
    },
  );

  test(
    'structure-only graph excludes preferences and databases and still restores',
    () async {
      final source = ProfileRuntime.capture();
      final preferences = await ProfilePreferences.instance();
      await preferences.setString('theme_mode', 'source-only');
      final sourceDatabase = source.fileIn(
        documents,
        'documents',
        'debrify_tv.db',
      );
      await sourceDatabase.parent.create(recursive: true);
      final database = await openDatabase(
        sourceDatabase.path,
        singleInstance: false,
      );
      await database.execute('CREATE TABLE proof(value TEXT NOT NULL)');
      await database.close();

      final authorization = await ProfileAuthorizationContext.capture(registry);
      final package =
          await ProfilePackageService(
            registry: registry,
            resources: ConnectionResourceService(
              registry: registry,
              cipher: cipher,
            ),
          ).exportAllProfiles(
            context: authorization,
            includeSecrets: true,
            includeDatabases: false,
            includePreferences: false,
          );

      expect(
        package.profiles,
        everyElement(isNot(contains('preferencesSection'))),
      );
      expect(
        package.profiles,
        everyElement(isNot(contains('databasesSection'))),
      );
      expect(
        package.sections.keys,
        isNot(
          contains(anyOf(endsWith('-preferences'), endsWith('-databases'))),
        ),
      );
      final decoded = await PortableProfilePackage.decodeAuthenticatedMap(
        await PortableProfilePackage.withIntegrity(package),
        allowMissingPreferences: true,
      );
      final report = await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: decoded, authorization: authorization);

      expect(report.profilesImported, 1);
      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      final importedPreferences = await ProfilePreferences.forCapturedScope(
        ProfileScope(
          profileId: imported.id,
          dataGeneration: imported.visibleDataGeneration,
          sessionEpoch: 0,
        ),
        CapturedProfilePreferenceAccess.restore,
      );
      expect(importedPreferences.getString('theme_mode'), isNull);
    },
  );

  test(
    'device graph publishes a final manifest covering preferences db and file',
    () async {
      final source = ProfileRuntime.capture();
      final engine = source.fileIn(
        documents,
        'documents',
        p.join('engines', 'portable.json'),
      );
      await engine.parent.create(recursive: true);
      await engine.writeAsString('{"engine":"sentinel"}', flush: true);

      final sourceDatabase = source.fileIn(
        documents,
        'documents',
        'debrify_tv.db',
      );
      await sourceDatabase.parent.create(recursive: true);
      final database = await openDatabase(
        sourceDatabase.path,
        singleInstance: false,
      );
      await database.execute('CREATE TABLE proof(value TEXT NOT NULL)');
      await database.insert('proof', <String, Object>{'value': 'db-sentinel'});
      await database.close();

      final authorization = await ProfileAuthorizationContext.capture(registry);
      final package = await ProfilePackageService(
        registry: registry,
        resources: ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ),
      ).exportAllProfiles(context: authorization, includeSecrets: true);
      final report = await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);

      expect(report.profilesImported, 1);
      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      expect(report.importedProfileIds, <String>[imported.id]);
      expect(imported.lifecycle, UserProfileLifecycle.active);
      final evidence = await registry.profileGenerationManifest(
        profileId: imported.id,
        generation: imported.visibleDataGeneration,
      );
      expect(evidence, isNotNull);
      expect(evidence!.hash, isNotEmpty);
      expect(evidence.manifest['preferenceCount'], greaterThan(0));
      final files = (evidence.manifest['files'] as List)
          .cast<Map>()
          .map((record) => record['path'])
          .toSet();
      expect(files, contains(p.join('documents', 'debrify_tv.db')));
      expect(files, contains(p.join('documents', 'engines', 'portable.json')));

      final importedScope = ProfileScope(
        profileId: imported.id,
        dataGeneration: imported.visibleDataGeneration,
        sessionEpoch: 0,
      );
      expect(
        await importedScope
            .fileIn(documents, 'documents', p.join('engines', 'portable.json'))
            .readAsString(),
        '{"engine":"sentinel"}',
      );
      final restoredDatabase = await openDatabase(
        importedScope.fileIn(documents, 'documents', 'debrify_tv.db').path,
        readOnly: true,
        singleInstance: false,
      );
      expect(await restoredDatabase.query('proof'), <Map<String, Object?>>[
        <String, Object?>{'value': 'db-sentinel'},
      ]);
      await restoredDatabase.close();
    },
  );

  test(
    'graph restore rolls forward after its publication checkpoint throws',
    () async {
      final prepared = await ProfileAvatarIngest.prepare(
        await paintPng(size: 32),
      );
      var authorization = await ProfileAuthorizationContext.capture(registry);
      await ProfileAvatarIngest.publish(
        registry: registry,
        profileId: profileId,
        avatarKey: prepared.avatar.format(),
        prepared: prepared,
        persist: () async {
          await registry.updateProfile(
            id: profileId,
            avatarKey: prepared.avatar.format(),
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        },
        wasPersisted: () async =>
            (await registry.getProfile(profileId))?.avatarKey ==
            prepared.avatar.format(),
      );
      authorization = await ProfileAuthorizationContext.capture(registry);
      final package = await ProfilePackageService(
        registry: registry,
        resources: ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ),
      ).exportAllProfiles(context: authorization, includeSecrets: true);
      var injected = false;
      var publishedCheckpointCalls = 0;
      registry.authorityChangedCallback = () async {
        final journals = await registry.interruptedRestores();
        final graphPublished = journals.any(
          (row) =>
              row['mode'] == 'registryReplace' && row['stage'] == 'published',
        );
        if (graphPublished) publishedCheckpointCalls++;
        if (!injected && graphPublished) {
          injected = true;
          throw StateError('checkpoint failed after graph publication');
        }
      };

      final report = await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);

      expect(injected, isTrue);
      expect(
        publishedCheckpointCalls,
        2,
        reason: 'graph publication must checkpoint again before avatar cleanup',
      );
      expect(report.profilesImported, 1);
      final imported = (await registry.listProfiles()).singleWhere(
        (profile) => profile.id != profileId,
      );
      final avatar = ProfileAvatar.tryParse(imported.avatarKey);
      expect(imported.lifecycle, UserProfileLifecycle.active);
      expect(avatar?.kind, ProfileAvatarKind.image);
      expect(
        await (await ProfileAvatarStorage.fileFor(
          imported.id,
          avatar!,
        )).exists(),
        isTrue,
      );
      final importedScope = ProfileScope(
        profileId: imported.id,
        dataGeneration: imported.visibleDataGeneration,
        sessionEpoch: 0,
      );
      final preferences = await ProfilePreferences.forCapturedScope(
        importedScope,
        CapturedProfilePreferenceAccess.restore,
      );
      expect(preferences.getString('theme_mode'), 'old');
    },
  );

  test('restore preserves original profile creation order', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    // Created in REVERSE of their carried instants: if the adopting device
    // ordered by insertion, Later-but-created-first would sort first and this
    // fixture would fail.
    await registry.createProfile(
      name: 'Second by instant',
      role: UserProfileRole.member,
      createdAtMs: DateTime.utc(2026, 6, 1).millisecondsSinceEpoch,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    await registry.createProfile(
      name: 'First by instant',
      role: UserProfileRole.member,
      createdAtMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );

    final authorization = await ProfileAuthorizationContext.capture(registry);
    final service = ProfilePackageService(
      registry: registry,
      resources: ConnectionResourceService(registry: registry, cipher: cipher),
    );
    final package = await service.exportAllProfiles(
      context: authorization,
      includeSecrets: true,
    );
    final originals = (await registry.listProfiles())
        .map((profile) => profile.id)
        .toSet();
    await ProfileRestoreCoordinator(
      registry: registry,
      cipher: cipher,
    ).restoreDeviceGraph(package: package, authorization: authorization);

    final importedMembers = (await registry.listProfiles())
        .where(
          (profile) =>
              !originals.contains(profile.id) &&
              profile.role == UserProfileRole.member,
        )
        .toList();
    expect(importedMembers, hasLength(2));
    // listProfiles orders by created_at_ms — the ORIGINAL instants traveled,
    // so the January profile sorts first despite being inserted last on both
    // the seed and the adopting device.
    expect(importedMembers.first.name, 'First by instant');
    expect(importedMembers.last.name, 'Second by instant');
    expect(
      importedMembers.first.createdAt.millisecondsSinceEpoch,
      DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    );
  });

  test('a missing or future createdAt falls back to import time', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final before = DateTime.now().millisecondsSinceEpoch;
    final profile = await registry.createProfile(
      name: 'Clock skew',
      role: UserProfileRole.member,
      createdAtMs: DateTime.now()
          .add(const Duration(days: 365))
          .millisecondsSinceEpoch,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    expect(
      profile.createdAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(before),
    );
  });
}

final class _JoinStateRepository implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineState state = const WebDavSyncEngineState();
  @override
  Future<WebDavSyncEngineState> load(String namespaceId) async => state;
  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState) update,
  ) async => state = update(state);
}

final class _JoinSafetyBackups implements WebDavSyncSafetyBackupStore {
  @override
  Future<WebDavSyncSafetyBackup> createVerified({
    required String adoptionId,
    required String passphrase,
    required ProfileAuthorizationContext authorization,
  }) async => WebDavSyncSafetyBackup(
    path: '/test-backup/$adoptionId',
    sha256Hex: 'b' * 64,
  );
  @override
  Future<bool> verifyRetained(WebDavSyncSafetyBackup backup) async => true;
}
