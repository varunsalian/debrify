import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_mutation.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_local_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _sha(String value) => crypto.sha256.convert(value.codeUnits).toString();
String _part(String value) =>
    base64UrlEncode(utf8.encode(value)).replaceAll('=', '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Directory catalogA;
  late Directory catalogB;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late ProfileWebDavSyncLocalAdapter adapter;
  late WebDavSyncLocalSession session;
  late WebDavSyncIdentityMaps maps;
  late String profileId;
  late String sourceId;
  late Database dbA;
  const circleProfileId = 'profile-circle';
  const circleResourceId = 'resource-circle';
  const playlistUrl = 'https://user:pass@panel.invalid/list.m3u';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    directory = await Directory.systemTemp.createTemp('iptv-library-');
    catalogA = await Directory.systemTemp.createTemp('iptv-library-a-');
    catalogB = await Directory.systemTemp.createTemp('iptv-library-b-');
    registry = await ProfileRegistry.open(
      path: p.join(directory.path, 'profiles.db'),
    );
    profileId = (await registry.createProfile(
      id: 'local-profile',
      name: 'Local',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    )).id;
    await registry.commitBootstrap(
      activeProfileId: profileId,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 1),
    );
    final resource =
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).create(
          context: await ProfileAuthorizationContext.capture(registry),
          type: ConnectionResourceType.iptvM3u,
          label: 'Panel',
          publicConfig: const <String, Object?>{
            'playlistName': 'Panel',
            'providerKind': 'm3u',
          },
          secretConfig: const <String, Object?>{
            'name': 'Panel',
            'url': playlistUrl,
            'addedAt': '2026-09-03T00:00:00.000Z',
          },
        );
    sourceId = resource.id;
    maps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: <String, String>{circleProfileId: profileId},
      circleToLocalResources: <String, String>{circleResourceId: sourceId},
    );
    adapter = ProfileWebDavSyncLocalAdapter(registry);
    session = await adapter.beginCycle();

    dbA = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await DebrifyTvDatabase.createTvStoreTables(db);
          await DebrifyTvDatabase.createIptvStoreTables(db);
        },
      ),
    );
    DebrifyTvDatabase.debugDatabaseOverride = dbA;
    IptvMediaStore.debugResetMigration();
    IptvCatalogDb.debugDirectoryOverride = catalogA.path;
    await IptvCatalogDb.open();
    WebDavSyncLibraryMutation.originDeviceId = 'device-a';
    WebDavSyncLibraryMutation.resetDebugTvHooks();
  });

  tearDown(() async {
    WebDavSyncLibraryMutation.originDeviceId = 'local-device';
    WebDavSyncLibraryMutation.resetDebugTvHooks();
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
    IptvMediaStore.debugLibraryClock = DateTime.now;
    IptvCatalogDb.debugLibraryClock = DateTime.now;
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    final db = DebrifyTvDatabase.debugDatabaseOverride;
    DebrifyTvDatabase.debugDatabaseOverride = null;
    if (db != null && db.isOpen) await db.close();
    IptvMediaStore.debugResetMigration();
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await directory.delete(recursive: true);
    await catalogA.delete(recursive: true);
    await catalogB.delete(recursive: true);
  });

  WebDavSyncLibraryBuildRequest buildRequest(WebDavSyncIdentityMaps identity) =>
      WebDavSyncLibraryBuildRequest(
        circleProfileId: circleProfileId,
        identityMaps: identity,
        clockOffsetMs: 0,
        serverNowMs: 100000,
      );

  test(
    'one cycle carries IPTV and Debrify TV families A to B with exact stamps',
    () async {
      var now = 1000;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      IptvCatalogDb.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      WebDavSyncLibraryMutation.debugTvClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      WebDavSyncLibraryMutation.debugTvGenerationId = () => 'generation-a';
      final catalogKey = IptvCatalogKey.forUrl(playlistUrl);
      await IptvCatalogDb.setCategoryOrder(catalogKey, const <String>[
        'News',
        'Sports',
      ]);
      await IptvMediaStore.setCategoryChannelOrder(
        sourceId,
        'News',
        const <IptvChannelOrderIdentity>[
          IptvChannelOrderIdentity(
            url: 'https://panel.invalid/live/2',
            name: 'Two',
            occurrence: 0,
          ),
          IptvChannelOrderIdentity(
            url: 'https://panel.invalid/live/1',
            name: 'One',
            occurrence: 0,
          ),
        ],
      );
      await IptvMediaStore.recordWatch(
        'https://panel.invalid/movie/9',
        channelName: 'Movie',
        playlistId: sourceId,
        httpHeaders: const <String, String>{'Authorization': 'Bearer secret'},
      );
      await IptvMediaStore.upsertVideoResume(
        'https://panel.invalid/movie/9',
        const <String, dynamic>{
          'positionMs': 42000,
          'durationMs': 100000,
          'speed': 1.25,
          'aspect': 'cover',
          'updatedAt': 999,
        },
        sourceId: sourceId,
      );
      await IptvMediaStore.upsertVideoResume(
        'generic-title',
        const <String, dynamic>{
          'positionMs': 7000,
          'durationMs': 90000,
          'speed': 1.0,
          'aspect': 'contain',
          'updatedAt': 1000,
        },
      );
      await DebrifyTvRepository.instance.upsertChannel(
        DebrifyTvChannelRecord(
          channelId: 'channel-a',
          name: 'TV Alpha',
          keywords: const <String>['Alpha', 'Beta'],
          avoidNsfw: true,
          channelNumber: 4,
          createdAt: DateTime.fromMillisecondsSinceEpoch(800),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(900),
        ),
      );
      await DebrifyTvCacheService.saveEntry(
        DebrifyTvChannelCacheEntry(
          version: 1,
          channelId: 'channel-a',
          normalizedKeywords: const <String>['alpha', 'beta'],
          fetchedAt: 901,
          status: DebrifyTvCacheStatus.ready,
          errorMessage: null,
          torrents: <CachedTorrent>[
            CachedTorrent(
              rowid: 0,
              infohash: 'a' * 40,
              name: 'TV Pool Title',
              sizeBytes: 1234,
              createdUnix: 12,
              seeders: 99,
              leechers: 7,
              completed: 88,
              scrapedDate: 13,
              sources: const <String>['private-scraper'],
              keywords: const <String>['alpha'],
            ),
          ],
          keywordStats: const <String, KeywordStat>{},
        ),
      );

      final fromA = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      expect(fromA.document.records, hasLength(8));
      expect(
        fromA.document.records.keys,
        containsAll(<String>[
          'catalog/category-order/$circleResourceId/m3u',
          'iptv/order/$circleResourceId/${_sha('News')}',
          'iptv/watch/$circleResourceId/${_sha('https://panel.invalid/movie/9')}',
          'resume/$circleResourceId/${_sha('https://panel.invalid/movie/9')}',
          'resume/_/${_sha('generic-title')}',
          'tv/ch/${_part('channel-a')}',
          'tv/pool-gen/${_part('channel-a')}',
          'tv/pool/${_part('channel-a')}/${'a' * 40}',
        ]),
      );
      final poolValue = fromA
          .document
          .records['tv/pool/${_part('channel-a')}/${'a' * 40}']!
          .value!;
      expect(poolValue.keys.toSet(), <String>{
        'generationId',
        'name',
        'sizeBytes',
        'keywords',
        'rank',
      });
      for (final key in fromA.document.records.keys) {
        expect(key, isNot(contains('panel.invalid')));
        expect(key, isNot(contains('Bearer secret')));
      }

      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = catalogB.path;
      await IptvCatalogDb.open();
      await dbA.close();
      final dbB = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await DebrifyTvDatabase.createTvStoreTables(db);
            await DebrifyTvDatabase.createIptvStoreTables(db);
          },
        ),
      );
      DebrifyTvDatabase.debugDatabaseOverride = dbB;
      IptvMediaStore.debugResetMigration();
      final blankB = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      var applyNotifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        applyNotifications++;
      };
      final outcome = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: fromA.document,
          observedRevisions: blankB.revisions,
          hiddenGroupNamesByWireKey: fromA.hiddenGroupNamesByWireKey,
        ),
      );
      expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
      expect(
        applyNotifications,
        0,
        reason: 'exact-stamp apply must never look like a local mutation',
      );
      expect(outcome.appliedNamespaces, <String>{
        'catalog/category-order',
        'iptv/order',
        'iptv/watch',
        'resume',
        'tv/ch',
        'tv/pool',
      });
      final tvChannels = await DebrifyTvRepository.instance.fetchAllChannels();
      expect(tvChannels.single.name, 'TV Alpha');
      expect(tvChannels.single.keywords, <String>['Alpha', 'Beta']);
      final tvCache = await DebrifyTvCacheService.getEntry('channel-a');
      expect(tvCache!.torrents.single.infohash, 'a' * 40);
      expect(tvCache.torrents.single.sizeBytes, 1234);
      expect(IptvCatalogDb.savedCategoryOrder(catalogKey), <String>[
        'News',
        'Sports',
      ]);
      final orderRows = await dbB.query(
        'iptv_category_channel_orders',
        orderBy: 'position',
      );
      expect(orderRows.map((row) => row['name']), <String>['Two', 'One']);
      final history = await StorageService.getIptvWatchHistory();
      expect(
        history['https://panel.invalid/movie/9']?['httpHeaders'],
        <String, String>{'Authorization': 'Bearer secret'},
      );
      expect(
        (await StorageService.getVideoResume(
          'https://panel.invalid/movie/9',
        ))?['positionMs'],
        42000,
      );
      expect(
        (await StorageService.getVideoResume('generic-title'))?['positionMs'],
        7000,
      );

      final fromB = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      expect(fromB.document.semanticDigest, fromA.document.semanticDigest);
      final stampsA = <String, WebDavSyncStamp>{
        for (final entry in fromA.document.records.entries)
          entry.key: entry.value.stamp,
      };
      final stampsB = <String, WebDavSyncStamp>{
        for (final entry in fromB.document.records.entries)
          entry.key: entry.value.stamp,
      };
      expect(
        <String, Object?>{
          for (final entry in stampsB.entries) entry.key: entry.value.toJson(),
        },
        <String, Object?>{
          for (final entry in stampsA.entries) entry.key: entry.value.toJson(),
        },
      );
    },
  );

  test(
    'unmapped sources omit non-deletingly and apply after mapping arrives',
    () async {
      await IptvMediaStore.setCategoryChannelOrder(
        sourceId,
        'News',
        const <IptvChannelOrderIdentity>[
          IptvChannelOrderIdentity(
            url: 'https://panel.invalid/live/1',
            name: 'One',
            occurrence: 0,
          ),
        ],
      );
      final unmapped = WebDavSyncIdentityMaps(
        circleToLocalProfiles: <String, String>{circleProfileId: profileId},
        circleToLocalResources: const <String, String>{},
      );
      final skipped = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(unmapped),
      );
      expect(skipped.document.records, isEmpty);
      const remoteGroup = 'Remote';
      final remote = WebDavSyncLibraryDocument(
        circleProfileId: circleProfileId,
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'iptv/order/$circleResourceId/${_sha(remoteGroup)}':
              const WebDavSyncCircleLeaf<Map<String, Object?>>(
                stamp: WebDavSyncStamp(
                  normalizedTimeMs: 9000,
                  originDeviceId: 'device-b',
                ),
                value: <String, Object?>{
                  'group': remoteGroup,
                  'items': <Object?>[
                    <String, Object?>{
                      'url': 'https://panel.invalid/remote/1',
                      'name': 'Remote one',
                      'occurrence': 0,
                    },
                  ],
                },
              ),
        },
      );
      final skippedApply = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: unmapped,
          document: remote,
          observedRevisions: skipped.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      expect(skippedApply.appliedNamespaces, isEmpty);
      expect(
        await dbA.query(
          'iptv_category_channel_orders',
          where: 'channel_group = ?',
          whereArgs: const <Object>[remoteGroup],
        ),
        isEmpty,
      );
      final mapped = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      expect(mapped.document.records.keys.single, startsWith('iptv/order/'));
      final laterApply = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: remote,
          observedRevisions: mapped.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      expect(laterApply.appliedNamespaces, const <String>{'iptv/order'});
      expect(
        await dbA.query(
          'iptv_category_channel_orders',
          where: 'channel_group = ?',
          whereArgs: const <Object>[remoteGroup],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'debrify_tv revision fence rejects a concurrent local mutation',
    () async {
      final blank = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      await IptvMediaStore.upsertVideoResume(
        'local-race',
        const <String, dynamic>{'positionMs': 1, 'durationMs': 2},
      );
      const remoteKey = 'remote-race';
      final remote = WebDavSyncLibraryDocument(
        circleProfileId: circleProfileId,
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'resume/_/${_sha(remoteKey)}':
              const WebDavSyncCircleLeaf<Map<String, Object?>>(
                stamp: WebDavSyncStamp(
                  normalizedTimeMs: 8000,
                  originDeviceId: 'device-b',
                ),
                value: <String, Object?>{
                  'resumeKey': remoteKey,
                  'position': 10,
                  'duration': 20,
                  'speed': 1.0,
                  'aspectRatio': 'contain',
                },
              ),
        },
      );

      final outcome = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: remote,
          observedRevisions: blank.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );

      expect(outcome.result, WebDavSyncLibraryApplyResult.conflict);
      expect(await StorageService.getVideoResume(remoteKey), isNull);
      expect(await StorageService.getVideoResume('local-race'), isNotNull);
    },
  );

  test('both order vectors converge by deterministic whole-vector LWW', () {
    const key = 'iptv/order/resource-circle/hash';
    WebDavSyncCircleLeaf<Map<String, Object?>> leaf(
      int time,
      String origin,
      List<String> urls,
    ) => WebDavSyncCircleLeaf<Map<String, Object?>>(
      stamp: WebDavSyncStamp(normalizedTimeMs: time, originDeviceId: origin),
      value: <String, Object?>{
        'group': 'News',
        'items': <Object?>[
          for (final url in urls)
            <String, Object?>{'url': url, 'name': url, 'occurrence': 0},
        ],
      },
    );
    final a = WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        key: leaf(10, 'device-a', const <String>['a', 'b']),
      },
    );
    final b = WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        key: leaf(10, 'device-b', const <String>['b', 'a']),
      },
    );
    final ab = WebDavSyncLibraryMerge.merge(
      circleProfileId: circleProfileId,
      documents: <WebDavSyncLibraryDocument>[a, b],
    );
    final ba = WebDavSyncLibraryMerge.merge(
      circleProfileId: circleProfileId,
      documents: <WebDavSyncLibraryDocument>[b, a],
    );
    expect(ab.semanticDigest, ba.semanticDigest);
    expect(ab.records[key]?.value, b.records[key]?.value);

    const categoryKey = 'catalog/category-order/resource-circle/m3u';
    final edit = WebDavSyncCircleLeaf<Map<String, Object?>>(
      stamp: const WebDavSyncStamp(
        normalizedTimeMs: 20,
        originDeviceId: 'device-a',
      ),
      value: const <String, Object?>{
        'groups': <String>['Sports', 'News'],
      },
    );
    const deletion = WebDavSyncCircleLeaf<Map<String, Object?>>(
      stamp: WebDavSyncStamp(normalizedTimeMs: 21, originDeviceId: 'device-b'),
      value: null,
    );
    final winner = WebDavSyncLibraryMerge.merge(
      circleProfileId: circleProfileId,
      documents: <WebDavSyncLibraryDocument>[
        WebDavSyncLibraryDocument(
          circleProfileId: circleProfileId,
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            categoryKey: edit,
            key: a.records[key]!,
          },
        ),
        WebDavSyncLibraryDocument(
          circleProfileId: circleProfileId,
          records: const <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            categoryKey: deletion,
            key: WebDavSyncCircleLeaf<Map<String, Object?>>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: 22,
                originDeviceId: 'device-b',
              ),
              value: null,
            ),
          },
        ),
      ],
    );
    expect(winner.records[categoryKey]?.value, isNull);
    expect(winner.records[key]?.value, isNull);
  });

  test(
    'remote history over the cap stays capped and does not replay pruned rows',
    () async {
      final blank = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{};
      for (var i = 0; i < 101; i++) {
        final url = 'https://panel.invalid/movie/$i';
        records['iptv/watch/$circleResourceId/${_sha(url)}'] =
            WebDavSyncCircleLeaf<Map<String, Object?>>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: 10000 + i,
                originDeviceId: 'device-b',
              ),
              value: <String, Object?>{
                'url': url,
                'name': 'Movie $i',
                'logoUrl': '',
                'group': 'Movies',
                'lastPlayedAt': i,
              },
            );
      }
      final remote = WebDavSyncLibraryDocument(
        circleProfileId: circleProfileId,
        records: records,
      );

      final first = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: remote,
          observedRevisions: blank.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      expect(first.appliedNamespaces, const <String>{'iptv/watch'});
      expect(await dbA.query('iptv_watch_history'), hasLength(100));
      expect(
        await dbA.query(
          'webdav_sync_record_state',
          where: 'kind = ?',
          whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvWatchHistory],
        ),
        hasLength(101),
      );

      final afterFirst = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      expect(
        afterFirst.document.records,
        hasLength(100),
        reason: 'the maintenance-pruned value is omitted, never tombstoned',
      );
      final second = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: remote,
          observedRevisions: afterFirst.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      expect(second.appliedNamespaces, isEmpty);
      expect(await dbA.query('iptv_watch_history'), hasLength(100));
    },
  );

  test(
    'malformed sealed values never leak URLs or headers to diagnostics',
    () async {
      final diagnostics = <String>[];
      adapter = ProfileWebDavSyncLocalAdapter(
        registry,
        diagnostic: diagnostics.add,
      );
      session = await adapter.beginCycle();
      const secretUrl = 'https://credential.invalid/user/pass/movie';
      const secretHeader = 'Bearer diagnostic-secret';
      final blank = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      final malformed = WebDavSyncLibraryDocument(
        circleProfileId: circleProfileId,
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          'iptv/watch/$circleResourceId/${_sha(secretUrl)}':
              const WebDavSyncCircleLeaf<Map<String, Object?>>(
                stamp: WebDavSyncStamp(
                  normalizedTimeMs: 50,
                  originDeviceId: 'device-b',
                ),
                value: <String, Object?>{
                  'url': secretUrl,
                  'name': 'Movie',
                  'logoUrl': '',
                  'group': '',
                  'lastPlayedAt': 50,
                  'headers': <String, Object?>{'Authorization': 7},
                  'secretSentinel': secretHeader,
                },
              ),
        },
      );
      final outcome = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: malformed,
          observedRevisions: blank.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
      expect(diagnostics, isNotEmpty);
      expect(diagnostics.join('\n'), isNot(contains(secretUrl)));
      expect(diagnostics.join('\n'), isNot(contains(secretHeader)));
    },
  );
}
