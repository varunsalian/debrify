import 'package:debrify/services/profiles/profile_preferences.dart';
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
// ignore: depend_on_referenced_packages
import 'package:sqflite_common/sqflite_logger.dart';
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
  late _InterruptibleCipher cipher;
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
    cipher = _InterruptibleCipher();
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
    'locked launch sync preserves IPTV catalog mappings without revealing credentials',
    () async {
      final key = IptvCatalogKey.forUrl(playlistUrl);
      await IptvCatalogDb.setCategoryOrder(key, const ['News', 'Sports']);
      final unlocked = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      ProfileLockController.instance.activate(
        (await registry.getProfile(profileId))!,
        unlocked: false,
      );
      final locked = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      const wireKey = 'catalog/category-order/resource-circle/m3u';
      expect(
        locked.document.records[wireKey]?.value,
        unlocked.document.records[wireKey]?.value,
      );
      expect(locked.document.records.containsKey(wireKey), isTrue);
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = catalogB.path;
      await IptvCatalogDb.open();
      final empty = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      final applied = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: locked.document,
          observedRevisions: empty.revisions,
          hiddenGroupNamesByWireKey: locked.hiddenGroupNamesByWireKey,
        ),
      );
      expect(applied.result, WebDavSyncLibraryApplyResult.applied);
      expect(IptvCatalogDb.savedCategoryOrder(key), const ['News', 'Sports']);
      expect(ProfileLockController.instance.isUnlocked, isFalse);
      await expectLater(
        ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).revealSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: sourceId,
          feature: ProfileFeature.manageConnections,
        ),
        throwsA(isA<ResourceAuthorizationException>()),
      );
    },
  );

  for (final kind in ['xtream', 'local']) {
    test(
      'locked sync maps migrated $kind playlists with a missing empty URL',
      () async {
        await ConnectionResourceService(
          registry: registry,
          cipher: cipher,
        ).updateSecret(
          context: await ProfileAuthorizationContext.capture(registry),
          resourceId: sourceId,
          secretConfig: {
            'name': 'Migrated',
            'addedAt': '2026-09-03T00:00:00.000Z',
            if (kind == 'xtream') ...{
              'serverUrl': 'https://panel.invalid',
              'username': 'viewer',
            },
            if (kind == 'local') 'content': '#EXTM3U',
          },
        );
        final key = kind == 'local'
            ? IptvCatalogKey.forLocalCategoryOrder(sourceId)
            : IptvCatalogKey.forXtream(
                'https://panel.invalid',
                'viewer',
                'live',
              );
        await IptvCatalogDb.setCategoryOrder(key, const ['News']);
        ProfileLockController.instance.activate(
          (await registry.getProfile(profileId))!,
          unlocked: false,
        );
        final built = await adapter.readLibrary(
          session,
          profileId,
          buildRequest(maps),
        );
        final variant = kind == 'local' ? 'local' : 'xc-live';
        expect(
          built.document.records.containsKey(
            'catalog/category-order/resource-circle/$variant',
          ),
          isTrue,
        );
      },
    );
  }

  for (final interruption in ['switch', 'revoke']) {
    test('catalog sync rejects $interruption during secret read', () async {
      cipher.afterOpen = () async {
        if (interruption == 'switch') {
          ProfileRuntime.publish(
            ProfileScope(
              profileId: profileId,
              dataGeneration: 1,
              sessionEpoch: 2,
            ),
          );
        } else {
          await registry.revokeGrant(profileId, sourceId);
        }
      };
      await expectLater(
        adapter.readLibrary(session, profileId, buildRequest(maps)),
        throwsStateError,
      );
    });
  }

  test(
    'database playback checkpoints carry a distinct notification origin',
    () async {
      final keys = <String>[];
      ProfilePreferences.webDavSyncLocalChangeSink = (_, key) => keys.add(key);
      try {
        await IptvMediaStore.recordWatch(
          'https://panel.invalid/movie/test',
          channelName: 'Test',
          playlistId: sourceId,
        );
        await IptvMediaStore.upsertVideoResume(
          'https://panel.invalid/movie/test',
          const {'positionMs': 1000, 'durationMs': 10000, 'updatedAt': 1000},
          sourceId: sourceId,
        );
        await IptvMediaStore.removeVideoResume(
          'https://panel.invalid/movie/test',
          playbackCheckpoint: true,
        );
        expect(keys, hasLength(3));
        expect(
          keys,
          everyElement(ProfilePreferences.webDavSyncPlaybackLibraryLogicalKey),
        );
        keys.clear();
        await IptvMediaStore.createList('Explicit edit');
        expect(keys, contains(ProfilePreferences.webDavSyncLibraryLogicalKey));
      } finally {
        ProfilePreferences.webDavSyncLocalChangeSink = null;
      }
    },
  );

  test('ambient build emits no TV records with a 50k saved pool', () async {
    await DebrifyTvRepository.instance.upsertChannel(
      DebrifyTvChannelRecord(
        channelId: 'large-channel',
        name: 'Large',
        keywords: const <String>['large'],
        avoidNsfw: true,
        channelNumber: 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      ),
    );
    await dbA.execute('''
      WITH RECURSIVE rows(n) AS (
        SELECT 1
        UNION ALL
        SELECT n + 1 FROM rows WHERE n < 50000
      )
      INSERT INTO tv_cached_torrents
        (channel_id, infohash, name, size_bytes, created_unix, seeders,
         leechers, completed, scraped_date, keywords_json, sources_json,
         added_at)
      SELECT 'large-channel', printf('%040x', n), 'Saved', 1, 0, 0,
             0, 0, 0, '[]', '[]', n
      FROM rows
    ''');

    final ambient = await adapter.readLibrary(
      session,
      profileId,
      buildRequest(maps),
    );

    expect(
      ambient.document.records.keys,
      everyElement(isNot(startsWith('tv/'))),
    );
  });

  test('ambient apply ignores injected legacy TV records once', () async {
    final diagnostics = <String>[];
    final guardedAdapter = ProfileWebDavSyncLocalAdapter(
      registry,
      diagnostic: diagnostics.add,
    );
    final blank = await guardedAdapter.readLibrary(
      session,
      profileId,
      buildRequest(maps),
    );
    final document = WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        'tv/ch/${_part('legacy-channel')}': WebDavSyncCircleLeaf(
          stamp: const WebDavSyncStamp(
            normalizedTimeMs: 10,
            originDeviceId: 'device-b',
          ),
          value: const <String, Object?>{
            'name': 'Legacy',
            'avoidNsfw': true,
            'channelNumber': 1,
            'createdAt': 1,
            'keywords': <String>['legacy'],
          },
        ),
      },
    );

    final outcome = await guardedAdapter.applyLibrary(
      session,
      profileId,
      WebDavSyncLibraryApplyRequest(
        circleProfileId: circleProfileId,
        identityMaps: maps,
        document: document,
        observedRevisions: blank.revisions,
        hiddenGroupNamesByWireKey: const <String, String>{},
      ),
    );

    expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
    expect(await DebrifyTvRepository.instance.fetchAllChannels(), isEmpty);
    expect(diagnostics, <String>[
      'Ignored Debrify TV records in an ambient library section',
    ]);
  });

  test(
    'a 500-record apply uses a fixed number of database round trips',
    () async {
      await dbA.close();
      final events = <SqfliteLoggerEvent>[];
      // The sqflite logger is intentionally a test-only instrumentation API.
      // ignore: experimental_member_use
      final loggingFactory = SqfliteDatabaseFactoryLogger(
        databaseFactoryFfiNoIsolate,
        options: SqfliteLoggerOptions(log: events.add),
      );
      dbA = await loggingFactory.openDatabase(
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
      events.clear();

      final watchTargets = List<WebDavSyncIptvWatchTarget>.generate(500, (
        index,
      ) {
        final url = 'https://panel.invalid/movie/$index';
        return WebDavSyncIptvWatchTarget(
          sourceId: sourceId,
          url: url,
          leaf: WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 10000 + index,
              originDeviceId: 'device-b',
            ),
            value: <String, Object?>{
              'url': url,
              'name': 'Movie $index',
              'logoUrl': '',
              'group': 'Movies',
              'lastPlayedAt': index,
            },
          ),
        );
      });
      final outcome = await DebrifyTvDatabase.instance.applyWebDavSyncFamilies(
        ProfileRuntime.capture(),
        expectedRevision: 0,
        channelTargets: const <WebDavSyncTvChannelTarget>[],
        generationTargets: const <WebDavSyncTvPoolGenerationTarget>[],
        poolTargets: const <WebDavSyncTvPoolTarget>[],
        listTargets: const <WebDavSyncIptvListTarget>[],
        listChannelTargets: const <WebDavSyncIptvListChannelTarget>[],
        orderTargets: const <WebDavSyncIptvOrderTarget>[],
        // Repeating an exact target must see the state queued by its first
        // occurrence and avoid adding a second set of physical writes.
        watchTargets: <WebDavSyncIptvWatchTarget>[
          ...watchTargets,
          watchTargets.first,
        ],
        resumeTargets: const <WebDavSyncVideoResumeTarget>[],
      );

      expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
      expect(outcome.touchedNamespaces, const <String>{'iptv/watch'});
      expect(events.where((event) => event.name == 'query'), hasLength(10));
      expect(events.where((event) => event.name == 'insert'), isEmpty);
      final batch = events.whereType<SqfliteLoggerBatchEvent>().single;
      expect(batch.operations, hasLength(1502));
      expect(
        events,
        hasLength(13),
        reason:
            'BEGIN + ten fixed preloads + one batch + COMMIT must not grow '
            'with record count',
      );
    },
  );

  test(
    'one ambient and one manual apply carry IPTV and Debrify TV families A to B with exact stamps',
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
      final customListId = await IptvMediaStore.createList('Sports');
      await IptvMediaStore.setChannelInList(
        customListId,
        'https://panel.invalid/live/10',
        true,
        channelName: 'List channel',
        playlistId: sourceId,
        channelNumber: 10,
        contentType: 'live',
        duration: -1,
        httpHeaders: const <String, String>{'Referer': 'https://panel.invalid'},
      );
      await IptvMediaStore.setChannelFavorited(
        'https://panel.invalid/live/11',
        true,
        channelName: 'Favorite channel',
        playlistId: sourceId,
      );
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
      final tvFromA = await adapter.readTvLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      expect(fromA.document.records, hasLength(8));
      expect(
        fromA.document.records.keys,
        containsAll(<String>[
          'catalog/category-order/$circleResourceId/m3u',
          'iptv/list/${_part(customListId)}',
          'iptv/list-ch/${_part(customListId)}/${_sha('https://panel.invalid/live/10')}',
          'iptv/list-ch/${_part(IptvMediaStore.favoritesListId)}/${_sha('https://panel.invalid/live/11')}',
          'iptv/order/$circleResourceId/${_sha('News')}',
          'iptv/watch/$circleResourceId/${_sha('https://panel.invalid/movie/9')}',
          'resume/$circleResourceId/${_sha('https://panel.invalid/movie/9')}',
          'resume/_/${_sha('generic-title')}',
        ]),
      );
      expect(
        fromA.document.records.keys,
        everyElement(isNot(startsWith('tv/'))),
      );
      expect(tvFromA.document.records, hasLength(3));
      expect(
        tvFromA.document.records.keys,
        containsAll(<String>[
          'tv/ch/${_part('channel-a')}',
          'tv/pool-gen/${_part('channel-a')}',
          'tv/pool/${_part('channel-a')}/${'a' * 40}',
        ]),
      );
      expect(
        fromA
            .document
            .records['iptv/list-ch/${_part(customListId)}/${_sha('https://panel.invalid/live/10')}']
            ?.value?['sourceRef'],
        circleResourceId,
      );
      final poolValue = tvFromA
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
        'iptv/list',
        'iptv/list-ch',
        'iptv/order',
        'iptv/watch',
        'resume',
      });
      expect(await DebrifyTvRepository.instance.fetchAllChannels(), isEmpty);
      expect(await DebrifyTvCacheService.getEntry('channel-a'), isNull);
      final beforeTv = await adapter.readTvLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      final tvOutcome = await adapter.applyTvLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: tvFromA.document,
          observedRevisions: beforeTv.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      expect(tvOutcome.result, WebDavSyncLibraryApplyResult.applied);
      expect(tvOutcome.appliedNamespaces, <String>{'tv/ch', 'tv/pool'});
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
      expect(
        (await dbB.query(
          'iptv_lists',
          where: 'id = ?',
          whereArgs: <Object?>[customListId],
        )).single['name'],
        'Sports',
      );
      final memberships = await dbB.query(
        'iptv_list_channels',
        orderBy: 'list_id, url',
      );
      expect(memberships, hasLength(2));
      expect(
        memberships.map((row) => row['playlist_id']),
        everyElement(sourceId),
      );
      expect(
        memberships.singleWhere(
          (row) => row['url'] == 'https://panel.invalid/live/10',
        )['duration'],
        -1,
      );
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
      final tvFromB = await adapter.readTvLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      expect(fromB.document.semanticDigest, fromA.document.semanticDigest);
      expect(tvFromB.document.semanticDigest, tvFromA.document.semanticDigest);
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
      final tvStampsA = <String, WebDavSyncStamp>{
        for (final entry in tvFromA.document.records.entries)
          entry.key: entry.value.stamp,
      };
      final tvStampsB = <String, WebDavSyncStamp>{
        for (final entry in tvFromB.document.records.entries)
          entry.key: entry.value.stamp,
      };
      expect(
        <String, Object?>{
          for (final entry in tvStampsB.entries)
            entry.key: entry.value.toJson(),
        },
        <String, Object?>{
          for (final entry in tvStampsA.entries)
            entry.key: entry.value.toJson(),
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

  test('list membership applies when its sourceRef is unmapped', () async {
    final blank = await adapter.readLibrary(
      session,
      profileId,
      buildRequest(maps),
    );
    const url = 'https://retired.invalid/live/1';
    final remote = WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        'iptv/list-ch/${_part(IptvMediaStore.favoritesListId)}/${_sha(url)}':
            const WebDavSyncCircleLeaf<Map<String, Object?>>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: 7000,
                originDeviceId: 'device-b',
              ),
              value: <String, Object?>{
                'url': url,
                'name': 'Retired source channel',
                'logoUrl': '',
                'group': 'Archive',
                'sourceRef': 'resource-missing',
                'httpHeaders': <String, String>{'User-Agent': 'Legacy'},
                'addedAt': 6000,
                'position': 3,
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

    expect(outcome.appliedNamespaces, const <String>{'iptv/list-ch'});
    final row = (await dbA.query('iptv_list_channels')).single;
    expect(row['url'], url);
    expect(row['playlist_id'], isEmpty);
    expect(row['http_headers_json'], contains('Legacy'));
  });

  test('Favorites metadata is discarded and cannot suppress members', () {
    const url = 'https://panel.invalid/live/favorite';
    final listKey = 'iptv/list/${_part(IptvMediaStore.favoritesListId)}';
    final memberKey =
        'iptv/list-ch/${_part(IptvMediaStore.favoritesListId)}/${_sha(url)}';
    final member = WebDavSyncCircleLeaf<Map<String, Object?>>(
      stamp: const WebDavSyncStamp(
        normalizedTimeMs: 10,
        originDeviceId: 'device-a',
      ),
      value: const <String, Object?>{
        'url': url,
        'name': 'Favorite',
        'logoUrl': '',
        'group': '',
        'sourceRef': '',
        'addedAt': 10,
        'position': 0,
      },
    );
    final merged = WebDavSyncLibraryMerge.merge(
      circleProfileId: circleProfileId,
      documents: <WebDavSyncLibraryDocument>[
        WebDavSyncLibraryDocument(
          circleProfileId: circleProfileId,
          records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
            listKey: const WebDavSyncCircleLeaf<Map<String, Object?>>(
              stamp: WebDavSyncStamp(
                normalizedTimeMs: 11,
                originDeviceId: 'device-b',
              ),
              value: null,
            ),
            memberKey: member,
          },
        ),
      ],
    );

    expect(merged.records, isNot(contains(listKey)));
    expect(merged.records[memberKey], member);
  });

  test('list tombstone prunes members and cascades the local rows', () async {
    final listId = await IptvMediaStore.createList('Temporary');
    const url = 'https://panel.invalid/live/temporary';
    await IptvMediaStore.setChannelInList(listId, url, true);
    final local = await adapter.readLibrary(
      session,
      profileId,
      buildRequest(maps),
    );
    final listKey = 'iptv/list/${_part(listId)}';
    final memberKey = 'iptv/list-ch/${_part(listId)}/${_sha(url)}';
    expect(local.document.records, contains(memberKey));
    final remote = WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
        listKey: const WebDavSyncCircleLeaf<Map<String, Object?>>(
          stamp: WebDavSyncStamp(
            normalizedTimeMs: 100001,
            originDeviceId: 'device-b',
          ),
          value: null,
        ),
      },
    );
    final merged = WebDavSyncLibraryMerge.merge(
      circleProfileId: circleProfileId,
      documents: <WebDavSyncLibraryDocument>[local.document, remote],
    );
    expect(merged.records[listKey]?.value, isNull);
    expect(merged.records, isNot(contains(memberKey)));

    final outcome = await adapter.applyLibrary(
      session,
      profileId,
      WebDavSyncLibraryApplyRequest(
        circleProfileId: circleProfileId,
        identityMaps: maps,
        document: merged,
        observedRevisions: local.revisions,
        hiddenGroupNamesByWireKey: local.hiddenGroupNamesByWireKey,
      ),
    );

    expect(outcome.appliedNamespaces, const <String>{'iptv/list'});
    expect(
      await dbA.query(
        'iptv_lists',
        where: 'id = ?',
        whereArgs: <Object?>[listId],
      ),
      isEmpty,
    );
    expect(
      await dbA.query(
        'iptv_list_channels',
        where: 'list_id = ?',
        whereArgs: <Object?>[listId],
      ),
      isEmpty,
    );
    final memberState = (await dbA.query(
      'webdav_sync_record_state',
      where: 'kind = ? AND owner_key = ?',
      whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvListChannels, listId],
    )).single;
    expect(memberState['deleted'], 0);
  });

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
    'a malformed member is retained on wire and skipped without aborting apply',
    () async {
      final diagnostics = <String>[];
      adapter = ProfileWebDavSyncLocalAdapter(
        registry,
        diagnostic: diagnostics.add,
      );
      session = await adapter.beginCycle();
      final blank = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      const validUrl = 'https://panel.invalid/live/valid';
      const malformedIdentity = 'malformed-member';
      final validKey =
          'iptv/list-ch/${_part(IptvMediaStore.favoritesListId)}/'
          '${_sha(validUrl)}';
      final malformedKey =
          'iptv/list-ch/${_part(IptvMediaStore.favoritesListId)}/'
          '${_sha(malformedIdentity)}';
      final remote = WebDavSyncLibraryDocument(
        circleProfileId: circleProfileId,
        records: <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
          validKey: const WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 49,
              originDeviceId: 'device-b',
            ),
            value: <String, Object?>{
              'url': validUrl,
              'name': 'Valid',
              'logoUrl': '',
              'group': '',
              'sourceRef': '',
              'addedAt': 49,
              'position': 0,
            },
          ),
          malformedKey: const WebDavSyncCircleLeaf<Map<String, Object?>>(
            stamp: WebDavSyncStamp(
              normalizedTimeMs: 50,
              originDeviceId: 'device-b',
            ),
            value: <String, Object?>{'url': 7},
          ),
        },
      );
      final merged = WebDavSyncLibraryMerge.merge(
        circleProfileId: circleProfileId,
        documents: <WebDavSyncLibraryDocument>[remote],
      );
      expect(merged.semanticDigest, remote.semanticDigest);
      expect(merged.records[malformedKey]!.value, const <String, Object?>{
        'url': 7,
      });

      final outcome = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: merged,
          observedRevisions: blank.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );

      expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
      expect(outcome.appliedNamespaces, const <String>{'iptv/list-ch'});
      expect((await dbA.query('iptv_list_channels')).single['url'], validUrl);
      expect(
        diagnostics,
        contains('Ignored an invalid IPTV-list member library leaf'),
      );
    },
  );

  test(
    'oversized member headers stay local and peers materialize headerless',
    () async {
      final diagnostics = <String>[];
      adapter = ProfileWebDavSyncLocalAdapter(
        registry,
        diagnostic: diagnostics.add,
      );
      session = await adapter.beginCycle();
      const url = 'https://panel.invalid/live/oversized-headers';
      final headers = <String, String>{'Authorization': 'x' * 2100};
      await IptvMediaStore.setChannelFavorited(url, true, httpHeaders: headers);
      expect(
        (await StorageService.getIptvFavoriteChannels())[url]?['httpHeaders'],
        headers,
      );

      final snapshot = await adapter.readLibrary(
        session,
        profileId,
        buildRequest(maps),
      );
      final key =
          'iptv/list-ch/${_part(IptvMediaStore.favoritesListId)}/${_sha(url)}';
      expect(snapshot.document.records[key], isNotNull);
      expect(
        snapshot.document.records[key]!.value,
        isNot(contains('httpHeaders')),
      );
      expect(
        diagnostics,
        contains('Omitted oversized IPTV-list member HTTP headers'),
      );
      expect(
        (await dbA.query('iptv_list_channels')).single['http_headers_json'],
        isNotNull,
      );

      await dbA.delete(
        'iptv_list_channels',
        where: 'url = ?',
        whereArgs: const <Object?>[url],
      );
      final outcome = await adapter.applyLibrary(
        session,
        profileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: maps,
          document: snapshot.document,
          observedRevisions: snapshot.revisions,
          hiddenGroupNamesByWireKey: snapshot.hiddenGroupNamesByWireKey,
        ),
      );
      expect(outcome.appliedNamespaces, const <String>{'iptv/list-ch'});
      expect(
        (await dbA.query('iptv_list_channels')).single['http_headers_json'],
        isNull,
      );
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

class _InterruptibleCipher extends MemoryDeviceSecretCipher {
  _InterruptibleCipher() : super(List<int>.generate(32, (i) => i));
  Future<void> Function()? afterOpen;

  @override
  Future<List<int>> open(
    String envelope, {
    required List<int> associatedData,
  }) async {
    final value = await super.open(envelope, associatedData: associatedData);
    final callback = afterOpen;
    afterOpen = null;
    await callback?.call();
    return value;
  }
}
