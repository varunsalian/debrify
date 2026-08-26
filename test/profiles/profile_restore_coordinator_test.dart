import 'dart:io';

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
import 'package:debrify/services/profiles/profile_data_generation.dart';
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
      await ProfileRestoreCoordinator(
        registry: registry,
        cipher: cipher,
      ).restoreDeviceGraph(package: package, authorization: authorization);

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
}
