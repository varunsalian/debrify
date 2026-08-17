import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_migration_service.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory documents;
  late Directory support;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DesktopScheduleService.instance.shutdown();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-migration-test-',
    );
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    support = Directory(p.join(temporaryDirectory.path, 'support'));
    await documents.create(recursive: true);
    await support.create(recursive: true);
    AppStorage.debugOverride(documents: documents, support: support);
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1));
    await cipher.initialize();
  });

  tearDown(() async {
    DesktopScheduleService.instance.shutdown();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'migrates a real legacy inventory once into the Admin authority',
    () async {
      final webDav = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'dav-1',
          'name': 'Home DAV',
          'baseUrl': 'https://dav.invalid/files',
          'username': 'legacy-user',
          'password': 'dav-secret',
        },
      ]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'initial_setup_complete_v1': true,
        'theme_mode': 'dark',
        DevicePreferences.tvTrailerUnderlayEffectiveKey: false,
        DevicePreferences.tvLowResRenderActiveKey: true,
        'real_debrid_api_key': 'rd-sentinel',
        'trakt_access_token': 'trakt-sentinel',
        'trakt_refresh_token': 'trakt-refresh-sentinel',
        'webdav_base_url': 'https://superseded.invalid',
        'webdav_servers_v1': webDav,
        'indexer_manager_configs_v1': <String>[
          jsonEncode(<String, Object?>{
            'id': 'idx-1',
            'name': 'Jackett',
            'type': 'jackett',
            'base_url': 'https://indexer.invalid',
            'api_key': 'indexer-sentinel',
          }),
        ],
        'iptv_playlists': <String>[
          jsonEncode(<String, Object?>{
            'id': 'iptv-1',
            'name': 'TV',
            'url': 'https://iptv.invalid/list.m3u',
            'addedAt': '2026-08-13T00:00:00.000Z',
          }),
        ],
        'stremio_addons_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'name': 'Legacy addon',
            'manifestUrl': 'https://addon.invalid/manifest.json',
            'types': <String>['movie'],
          },
        ]),
      });
      await File(p.join(documents.path, 'engines', 'custom.json'))
          .create(recursive: true)
          .then((file) => file.writeAsString('{"enabled":true}'));
      final legacyDbPath = p.join(documents.path, 'debrify_tv.db');
      final legacyDb = await openDatabase(legacyDbPath);
      await legacyDb.execute(
        'CREATE TABLE migration_sentinel (id INTEGER PRIMARY KEY, value TEXT)',
      );
      await legacyDb.insert('migration_sentinel', <String, Object?>{
        'id': 1,
        'value': 'legacy-database-row',
      });
      await legacyDb.close();

      final migration = ProfileMigrationService(
        registry: registry,
        cipher: cipher,
      );
      final admin = await migration.migrate();

      expect(admin.id, ProfileMigrationService.adminProfileId);
      expect(admin.setupComplete, isTrue);
      expect(await registry.isMigrationCommitted(), isTrue);
      expect((await registry.activeProfile())?.id, admin.id);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('real_debrid_api_key'), 'rd-sentinel');
      expect(raw.getString('p.${admin.id}.g.1.theme_mode'), 'dark');
      expect(
        raw.containsKey('p.${admin.id}.g.1.initial_setup_complete_v1'),
        isFalse,
      );
      for (final key in DevicePreferences.nativeLaunchSnapshotKeys) {
        expect(raw.containsKey('p.${admin.id}.g.1.$key'), isFalse);
      }
      expect(raw.containsKey('p.${admin.id}.g.1.real_debrid_api_key'), isFalse);
      expect(
        await registry.getBoundResourceId(admin.id, 'provider.realDebrid'),
        'resource-legacy-real-debrid',
      );
      expect(
        await registry.getBoundResourceId(admin.id, 'provider.webDav.0'),
        'resource-legacy-webdav-0',
      );

      final journal = await registry.migrationJournal(
        ProfileMigrationService.migrationId,
      );
      expect(journal?['stage'], 'committed');
      final payload = Map<String, dynamic>.from(journal?['payload'] as Map);
      final dispositions = Map<String, dynamic>.from(
        payload['resourceSourceDispositions'] as Map,
      );
      expect(
        dispositions.keys,
        containsAll(<String>[
          'real_debrid_api_key',
          'trakt_access_token',
          'trakt_refresh_token',
          'webdav_base_url',
          'webdav_servers_v1',
          'indexer_manager_configs_v1',
          'iptv_playlists',
          'stremio_addons_v1',
        ]),
      );
      expect(dispositions['webdav_base_url'], 'supersededBy:webdav_servers_v1');

      final migratedScope = ProfileScope(
        profileId: admin.id,
        dataGeneration: admin.visibleDataGeneration,
        sessionEpoch: 0,
      );
      final migratedDbPath = migratedScope
          .fileIn(documents, 'documents', 'debrify_tv.db')
          .path;
      expect(await File(migratedDbPath).exists(), isTrue);
      final migratedDb = await openDatabase(migratedDbPath, readOnly: true);
      expect(
        await migratedDb.query('migration_sentinel'),
        <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'value': 'legacy-database-row'},
        ],
      );
      await migratedDb.close();
      expect(await File(legacyDbPath).exists(), isTrue);
      expect(
        await File(
          p.join(
            migratedScope.storageDirectory(documents, 'documents').path,
            'engines',
            'custom.json',
          ),
        ).readAsString(),
        '{"enabled":true}',
      );

      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: admin.id,
          dataGeneration: admin.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );
      final context = await ProfileAuthorizationContext.capture(registry);
      final secret =
          await ConnectionResourceService(
            registry: registry,
            cipher: cipher,
          ).resolveSecretForUse(
            context: context,
            resourceId: 'resource-legacy-real-debrid',
            feature: ProfileFeature.cloud,
          );
      expect(secret['apiKey'], 'rd-sentinel');

      final again = await migration.migrate();
      expect(again.id, admin.id);
      expect(
        (await registry.listGrantedResources(admin.id))
            .where(
              (resource) => resource.type == ConnectionResourceType.realDebrid,
            )
            .length,
        1,
      );
    },
  );

  test('unreadable present credentials block authority publication', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_mode': 'dark',
      'real_debrid_api_key': '${SecretVault.prefix}not-base64',
    });

    await expectLater(
      ProfileMigrationService(registry: registry, cipher: cipher).migrate(),
      throwsA(isA<FormatException>()),
    );
    expect(await registry.isMigrationCommitted(), isFalse);
    expect(await registry.activeProfile(), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('real_debrid_api_key'),
      '${SecretVault.prefix}not-base64',
    );
  });

  test('migrates a database-only install with empty preferences', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final legacyPath = p.join(documents.path, 'iptv_catalog.db');
    final legacy = await openDatabase(legacyPath);
    expect(
      (await legacy.rawQuery('PRAGMA journal_mode=WAL')).single.values.single,
      'wal',
    );
    await legacy.execute(
      'CREATE TABLE migration_sentinel (id INTEGER PRIMARY KEY, value TEXT)',
    );
    await legacy.insert('migration_sentinel', <String, Object?>{
      'id': 7,
      'value': 'database-only-install',
    });
    await legacy.close();

    final admin = await ProfileMigrationService(
      registry: registry,
      cipher: cipher,
    ).migrate();

    expect(await registry.isMigrationCommitted(), isTrue);
    expect(admin.id, ProfileMigrationService.adminProfileId);
    final destination = ProfileScope(
      profileId: admin.id,
      dataGeneration: admin.visibleDataGeneration,
      sessionEpoch: 0,
    ).fileIn(documents, 'documents', 'iptv_catalog.db');
    expect(await destination.exists(), isTrue);
    for (final suffix in const <String>[
      '.migration.tmp',
      '.migration.tmp-wal',
      '.migration.tmp-shm',
      '.migration.tmp-journal',
    ]) {
      expect(await File('${destination.path}$suffix').exists(), isFalse);
    }
    final migrated = await openDatabase(
      destination.path,
      singleInstance: false,
    );
    expect(await migrated.query('migration_sentinel'), <Map<String, Object?>>[
      <String, Object?>{'id': 7, 'value': 'database-only-install'},
    ]);
    await migrated.close();
    expect(await File(legacyPath).exists(), isTrue);
  });

  test('tvOS prunes only rebuildable TVMaze preference caches', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_mode': 'dark',
      'playback_state_v1': '{"position":42}',
      'tvmaze_cache_episodes_1139': 'legacy-cache',
      'tvmaze_timestamp_episodes_1139': 1,
      'p.legacy-admin-v1.g.1.tvmaze_cache_episodes_527': 'partial-copy',
      'p.legacy-admin-v1.g.1.tvmaze_timestamp_episodes_527': 2,
    });

    final preferences = await SharedPreferences.getInstance();
    expect(
      await ProfileMigrationService.pruneTvOsTransientPreferenceCaches(
        preferences: preferences,
        tvOs: true,
      ),
      4,
    );
    expect(preferences.getString('theme_mode'), 'dark');
    expect(preferences.getString('playback_state_v1'), '{"position":42}');
    expect(
      preferences.getKeys().where((key) => key.contains('tvmaze_')),
      isEmpty,
    );
  });

  group('tvOS preference budget preflight', () {
    tearDown(ProfilePreferenceBudget.debugReset);

    test('refuses a migration that would cross the platform limit', () async {
      // Migration is non-destructive, so copying duplicates every profile key
      // into the scoped namespace. That duplication is what aborted the tvOS
      // process; the preflight has to catch it before anything is written.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'initial_setup_complete_v1': true,
        'theme_mode': 'dark',
        'playback_state_v1': 'x' * (ProfilePreferenceBudget.limitBytes ~/ 2),
      });
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      await expectLater(
        ProfileMigrationService(registry: registry, cipher: cipher).migrate(),
        throwsA(isA<ProfilePreferenceBudgetExceeded>()),
      );

      // The refusal precedes createProfile, so neither the registry nor the
      // scoped namespace is touched and the next launch retries cleanly. The
      // rebuildable TVMaze prune does run first on a real device; it is a
      // no-op here because it keys off the platform, not the budget override.
      expect(
        await registry.getProfile(ProfileMigrationService.adminProfileId),
        isNull,
      );
      expect(await registry.isMigrationCommitted(), isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where((key) => key.startsWith('p.')),
        isEmpty,
      );
      expect(preferences.getString('theme_mode'), 'dark');
    });

    test(
      'reserves runtime headroom rather than migrating to the limit',
      () async {
        // Migration duplicates every profile key, so projecting against the full
        // limit would let an install migrate to exactly the ceiling and then
        // refuse every write from its first launch onward.
        final half =
            (ProfilePreferenceBudget.limitBytes -
                ProfilePreferenceBudget.migrationReserveBytes ~/ 2) ~/
            2;
        SharedPreferences.setMockInitialValues(<String, Object>{
          'initial_setup_complete_v1': true,
          'playback_state_v1': 'x' * half,
        });
        ProfilePreferenceBudget.debugEnforcedOverride = true;

        final projected = ProfilePreferenceBudget.measure(
          await SharedPreferences.getInstance(),
        );
        // Fits under the runtime limit once duplicated, but not under the
        // reserved migration ceiling — exactly the case that must be refused.
        expect(projected * 2, lessThan(ProfilePreferenceBudget.limitBytes));
        expect(
          projected * 2,
          greaterThan(ProfilePreferenceBudget.migrationLimitBytes),
        );

        await expectLater(
          ProfileMigrationService(registry: registry, cipher: cipher).migrate(),
          throwsA(isA<ProfilePreferenceBudgetExceeded>()),
        );
      },
    );

    test('an ordinary inventory still migrates with the budget on', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'initial_setup_complete_v1': true,
        'theme_mode': 'dark',
        'playback_state_v1': '{"position":42}',
      });
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      final profile = await ProfileMigrationService(
        registry: registry,
        cipher: cipher,
      ).migrate();

      expect(profile.id, ProfileMigrationService.adminProfileId);
      expect(await registry.isMigrationCommitted(), isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('p.legacy-admin-v1.g.1.theme_mode'), 'dark');
    });
  });

  test(
    'legacy desktop schedules bind to the final Admin revision and are sealed',
    () async {
      final start = DateTime.now().add(const Duration(days: 1));
      SharedPreferences.setMockInitialValues(<String, Object>{
        // Converting this connection advances the staged Admin revision. The
        // schedule must use that final value, never the historical default 1.
        'real_debrid_api_key': 'rd-sentinel',
        'desktop_recording_schedules_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'legacy-schedule',
            'channelName': 'Legacy channel',
            'url': 'https://stream.invalid/live.ts?token=schedule-sentinel',
            'headers': <String, String>{
              'Authorization': 'Bearer schedule-sentinel',
            },
            'startMs': start.millisecondsSinceEpoch,
            'endMs': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
            'programmeTitle': 'Legacy programme',
          },
        ]),
      });

      final admin = await ProfileMigrationService(
        registry: registry,
        cipher: cipher,
      ).migrate();
      expect(admin.authorizationRevision, greaterThan(1));
      DeviceKeyProvider.debugInstallCipher(cipher);
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: admin.id,
          dataGeneration: admin.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );

      await DesktopScheduleService.instance.init();

      final raw = await SharedPreferences.getInstance();
      final persisted =
          (jsonDecode(raw.getString('desktop_recording_schedules_v1')!) as List)
                  .single
              as Map;
      expect(persisted['ownerProfileId'], admin.id);
      expect(
        persisted['profileAuthorizationRevision'],
        admin.authorizationRevision,
      );
      expect(persisted['sealedExecutionPayload'], isA<String>());
      expect(persisted.containsKey('url'), isFalse);
      expect(persisted.containsKey('headers'), isFalse);

      final restored = await DesktopScheduleService.instance.list(
        allOwners: true,
      );
      expect(restored, hasLength(1));
      expect(restored.single.ownerProfileId, admin.id);
      expect(
        restored.single.profileAuthorizationRevision,
        admin.authorizationRevision,
      );
      expect(restored.single.url, contains('schedule-sentinel'));
      expect(
        restored.single.headers['Authorization'],
        'Bearer schedule-sentinel',
      );
    },
  );

  test(
    'legacy download queues bind to the final Admin revision and are sealed',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'real_debrid_api_key': 'rd-sentinel',
        'pending_download_queue_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'queuedId': 'legacy-pending',
            'url': 'https://download.invalid/pending?token=pending-sentinel',
            'providedFileName': 'pending.bin',
          },
        ]),
        'paused_download_queue_v1': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'queuedId': 'legacy-paused',
            'url': 'https://download.invalid/paused?token=paused-sentinel',
            'providedFileName': 'paused.bin',
          },
        ]),
      });

      final admin = await ProfileMigrationService(
        registry: registry,
        cipher: cipher,
      ).migrate();
      expect(admin.authorizationRevision, greaterThan(1));
      DeviceKeyProvider.debugInstallCipher(cipher);
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: admin.id,
          dataGeneration: admin.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );

      final records = await DownloadService.instance
          .debugImportLegacyQueuesForTesting();
      expect(
        records.keys,
        containsAll(<String>['legacy-pending', 'legacy-paused']),
      );
      expect(records['legacy-pending']?['state'], 'queued');
      expect(records['legacy-paused']?['state'], 'paused');
      for (final record in records.values) {
        expect(record['ownerProfileId'], admin.id);
        expect(
          record['profileAuthorizationRevision'],
          admin.authorizationRevision,
        );
      }
      final device = await SharedPreferences.getInstance();
      expect(device.getBool('download_legacy_queue_imported_v2'), isTrue);
      final encrypted = await File(
        p.join(support.path, 'downloads_db_v1.json'),
      ).readAsString();
      expect(encrypted, isNot(contains('pending-sentinel')));
      expect(encrypted, isNot(contains('paused-sentinel')));
      expect(jsonDecode(encrypted), containsPair('version', 2));
    },
  );

  test('migration keeps structurally required empty fields', () async {
    // An Xtream provider stores `url: ''` on purpose — its endpoint is
    // serverUrl. Stripping empty values while sealing dropped the key
    // entirely, and the reader casts it non-null, so the whole playlist
    // collection threw and the IPTV page never left its spinner.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'iptv_playlists': <String>[
        jsonEncode(<String, Object?>{
          'id': 'iptv-xtream',
          'name': 'Panel',
          'url': '',
          'serverUrl': 'https://panel.invalid:8080',
          'username': 'user',
          'password': 'pass',
          'addedAt': '2026-08-14T00:00:00.000Z',
        }),
      ],
    });

    final admin = await ProfileMigrationService(
      registry: registry,
      cipher: cipher,
    ).migrate();
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: admin.id,
        dataGeneration: admin.visibleDataGeneration,
        sessionEpoch: 1,
      ),
    );

    final secret =
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).resolveSecretForUse(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: 'resource-legacy-iptv-0',
          feature: ProfileFeature.iptv,
        );

    expect(
      secret.containsKey('url'),
      isTrue,
      reason: 'the required key must survive even when its value is empty',
    );
    expect(secret['url'], '');
    expect(secret['serverUrl'], 'https://panel.invalid:8080');
  });

  test('an all-empty record still mints no resource', () async {
    // The emptiness TEST is what decides whether a record is worth a
    // resource; it must keep working now that it no longer mutates the map.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'iptv_playlists': <String>[
        jsonEncode(<String, Object?>{'name': '', 'url': ''}),
      ],
    });

    final admin = await ProfileMigrationService(
      registry: registry,
      cipher: cipher,
    ).migrate();

    expect(
      (await registry.listGrantedResources(
        admin.id,
      )).where((resource) => resource.type == ConnectionResourceType.iptvM3u),
      isEmpty,
    );
  });
}
