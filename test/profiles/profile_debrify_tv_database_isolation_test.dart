import 'dart:convert';
import 'package:debrify/services/remote_control/remote_channel_file.dart';
import 'package:debrify/services/community/channel_yaml_builder.dart';
import 'dart:async';
import 'dart:io';

import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_mutation.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late ProfileScope profileA;
  late ProfileScope profileB;

  DebrifyTvChannelRecord channel(
    String id, {
    String name = 'Channel',
    List<String> keywords = const <String>['one'],
    int number = 1,
  }) => DebrifyTvChannelRecord(
    channelId: id,
    name: name,
    keywords: keywords,
    avoidNsfw: true,
    channelNumber: number,
    createdAt: DateTime.fromMillisecondsSinceEpoch(10),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(20),
  );

  CachedTorrent torrent(String hash, String name) => CachedTorrent(
    rowid: 0,
    infohash: hash,
    name: name,
    sizeBytes: 1234,
    createdUnix: 90,
    seeders: 8,
    leechers: 2,
    completed: 7,
    scrapedDate: 80,
    sources: const <String>['scraper'],
    keywords: const <String>['one'],
  );

  DebrifyTvChannelCacheEntry cache(
    String channelId,
    List<CachedTorrent> torrents,
  ) => DebrifyTvChannelCacheEntry(
    version: 1,
    channelId: channelId,
    normalizedKeywords: const <String>['one'],
    fetchedAt: 50,
    status: DebrifyTvCacheStatus.ready,
    errorMessage: null,
    torrents: torrents,
    keywordStats: const <String, KeywordStat>{},
  );

  WebDavSyncCircleLeaf<Map<String, Object?>> leaf(
    int time,
    String origin,
    Map<String, Object?>? value,
  ) => WebDavSyncCircleLeaf<Map<String, Object?>>(
    stamp: WebDavSyncStamp(normalizedTimeMs: time, originDeviceId: origin),
    value: value,
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile-debrify-tv-db-');
    documents = await Directory(
      p.join(root.path, 'documents'),
    ).create(recursive: true);
    final support = await Directory(
      p.join(root.path, 'support'),
    ).create(recursive: true);
    final cache = await Directory(
      p.join(root.path, 'cache'),
    ).create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    profileA = ProfileScope(
      profileId: 'profile-a',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    profileB = ProfileScope(
      profileId: 'profile-b',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(profileA);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    WebDavSyncLibraryMutation.originDeviceId = 'device-a';
    WebDavSyncLibraryMutation.debugTvClock = DateTime.now;
    WebDavSyncLibraryMutation.debugTvGenerationId = () => 'generation-default';
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
  });

  tearDown(() async {
    await DebrifyTvDatabase.instance.debugResetScopeState();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    WebDavSyncLibraryMutation.originDeviceId = 'local-device';
    WebDavSyncLibraryMutation.resetDebugTvHooks();
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
    await root.delete(recursive: true);
  });

  test(
    'an A open completing after deactivation cannot become B singleton',
    () async {
      final reachedPublish = Completer<void>();
      final releasePublish = Completer<void>();
      DebrifyTvDatabase.debugBeforeOpenPublish = (_) async {
        reachedPublish.complete();
        await releasePublish.future;
      };

      final openingA = DebrifyTvDatabase.instance.database;
      await reachedPublish.future;
      final closingA = DebrifyTvDatabase.instance.closeScope(profileA);
      releasePublish.complete();

      await expectLater(openingA, throwsStateError);
      await closingA;

      DebrifyTvDatabase.debugBeforeOpenPublish = null;
      ProfileRuntime.publish(profileB);
      DebrifyTvDatabase.instance.activateScope(profileB);
      final dbB = await DebrifyTvDatabase.instance.database;
      await dbB.insert('tv_channels', <String, Object>{
        'channel_id': 'b-channel',
        'name': 'Profile B',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });

      final bRows = await dbB.query('tv_channels');
      expect(bRows.single['channel_id'], 'b-channel');

      final aPath = profileA
          .fileIn(documents, 'documents', 'debrify_tv.db')
          .path;
      final dbA = await databaseFactoryFfi.openDatabase(aPath);
      addTearDown(dbA.close);
      expect(await dbA.query('tv_channels'), isEmpty);
    },
  );

  test(
    'deactivated scope stays closed until rollback reactivates it',
    () async {
      await DebrifyTvDatabase.instance.database;
      await DebrifyTvDatabase.instance.closeScope(profileA);

      await expectLater(DebrifyTvDatabase.instance.database, throwsStateError);

      DebrifyTvDatabase.instance.activateScope(profileA);
      expect(await DebrifyTvDatabase.instance.database, isNotNull);
    },
  );

  test(
    'concurrent opens publish one handle for the authoritative scope',
    () async {
      final handles = await Future.wait(<Future<Database>>[
        DebrifyTvDatabase.instance.database,
        DebrifyTvDatabase.instance.database,
        DebrifyTvDatabase.instance.database,
      ]);

      expect(identical(handles[0], handles[1]), isTrue);
      expect(identical(handles[1], handles[2]), isTrue);
    },
  );

  test('portable export recovers pooled rows without cache state', () async {
    final db = await DebrifyTvDatabase.instance.database;
    await db.insert('tv_channels', <String, Object>{
      'channel_id': 'portable-channel',
      'name': 'Portable channel',
      'avoid_nsfw': 1,
      'channel_number': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('tv_channel_keywords', <String, Object>{
      'channel_id': 'portable-channel',
      'position': 0,
      'keyword': 'science fiction',
    });
    await db.insert('tv_cached_torrents', <String, Object>{
      'channel_id': 'portable-channel',
      'infohash': 'preserved-hash',
      'name': 'Preserved title',
      'size_bytes': 1000,
      'created_unix': 10,
      'seeders': 20,
      'leechers': 2,
      'completed': 30,
      'scraped_date': 40,
      'keywords_json': '["science fiction"]',
      'sources_json': '["custom-source"]',
      'added_at': 50,
    });

    expect(await DebrifyTvCacheService.getEntry('portable-channel'), isNull);
    final remoteYaml = await ChannelYamlBuilder.build(
      channel('portable-channel', keywords: const ['science fiction']),
    );
    expect(remoteYaml, contains('infohash: preserved-hash'));
    final portable = await DebrifyTvCacheService.getEntryForPortableExport(
      'portable-channel',
    );

    expect(portable, isNotNull);
    expect(portable!.status, 'ready');
    expect(portable.normalizedKeywords, <String>['science fiction']);
    expect(portable.torrents.single.infohash, 'preserved-hash');
    expect(portable.torrents.single.sources, <String>['custom-source']);
  });

  test(
    'remote channel file streams a complete pool and rolls back truncation',
    () async {
      final record = channel('remote-large', name: 'ÉMISSIONS');
      await DebrifyTvRepository.instance.upsertChannel(record);
      final pool = List<CachedTorrent>.generate(
        1501,
        (i) => torrent(
          'hash-${i.toString().padLeft(5, '0')}',
          'Saved title $i',
        ).merge(keywords: const ['old association']),
      );
      await DebrifyTvCacheService.saveEntry(cache(record.channelId, pool));
      final file = File(p.join(root.path, 'channel.gz'));
      await RemoteChannelFile.export(record.channelId, file);
      await DebrifyTvCacheService.saveEntry(
        cache(record.channelId, [torrent('local-only', 'Local')]),
      );

      final lines = utf8
          .decode(gzip.decode(await file.readAsBytes()))
          .trimRight()
          .split('\n');
      final header = jsonDecode(lines.first) as Map<String, dynamic>;
      header['name'] = 'émissions';
      lines[0] = jsonEncode(header);
      await file.writeAsBytes(
        gzip.encode(utf8.encode('${lines.join('\n')}\n')),
      );
      final damaged = File(p.join(root.path, 'damaged.gz'));
      await damaged.writeAsBytes(
        gzip.encode(
          utf8.encode('${lines.take(lines.length - 1).join('\n')}\n'),
        ),
      );
      await expectLater(
        RemoteChannelFile.import(damaged),
        throwsFormatException,
      );
      expect(
        (await DebrifyTvCacheService.getEntry(
          record.channelId,
        ))!.torrents.single.infohash,
        'local-only',
      );

      await RemoteChannelFile.import(file);
      final restored = (await DebrifyTvCacheService.getEntry(
        record.channelId,
      ))!;
      expect(
        restored.torrents.map((t) => t.infohash).toSet(),
        pool.map((t) => t.infohash).toSet(),
      );
      expect(
        restored.torrents.every((t) => t.keywords.contains('old association')),
        isTrue,
      );
      expect(
        await DebrifyTvRepository.instance.fetchAllChannels(),
        hasLength(1),
      );
    },
  );

  test('profile close waits for an admitted write transaction', () async {
    final transactionStarted = Completer<void>();
    final releaseTransaction = Completer<void>();
    final transaction = DebrifyTvDatabase.instance.runTxn((txn) async {
      transactionStarted.complete();
      await releaseTransaction.future;
      await txn.insert('tv_channels', <String, Object>{
        'channel_id': 'a-channel',
        'name': 'Profile A',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });
    });
    await transactionStarted.future;

    var closeCompleted = false;
    final closing = DebrifyTvDatabase.instance
        .closeScope(profileA)
        .whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseTransaction.complete();
    await transaction;
    await closing;

    ProfileRuntime.publish(profileB);
    DebrifyTvDatabase.instance.activateScope(profileB);
    final dbB = await DebrifyTvDatabase.instance.database;
    expect(await dbB.query('tv_channels'), isEmpty);
  });

  test('profile close waits for an admitted read operation', () async {
    final readStarted = Completer<void>();
    final releaseRead = Completer<void>();
    final read = DebrifyTvDatabase.instance.runScoped((db) async {
      readStarted.complete();
      await releaseRead.future;
      return db.query('tv_channels');
    });
    await readStarted.future;

    var closeCompleted = false;
    final closing = DebrifyTvDatabase.instance
        .closeScope(profileA)
        .whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseRead.complete();
    expect(await read, isEmpty);
    await closing;
  });

  test('read then nested transaction remains on its admitted scope', () async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.insert('tv_channels', <String, Object>{
        'channel_id': 'source-a',
        'name': 'Profile A',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });
    });

    final readCompleted = Completer<void>();
    final releaseWrite = Completer<void>();
    final operation = DebrifyTvDatabase.instance.runScoped((db) async {
      final sourceRows = await db.query(
        'tv_channels',
        where: 'channel_id = ?',
        whereArgs: ['source-a'],
      );
      readCompleted.complete();
      await releaseWrite.future;
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.insert('tv_channels', <String, Object>{
          'channel_id': 'derived-a',
          'name': '${sourceRows.single['name']} derived',
          'avoid_nsfw': 1,
          'channel_number': 2,
          'created_at': 2,
          'updated_at': 2,
        });
      });
    });
    await readCompleted.future;

    var closeCompleted = false;
    final closing = DebrifyTvDatabase.instance
        .closeScope(profileA)
        .whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseWrite.complete();
    await operation;
    await closing;

    final aPath = profileA.fileIn(documents, 'documents', 'debrify_tv.db').path;
    final dbA = await databaseFactoryFfi.openDatabase(aPath);
    addTearDown(dbA.close);
    expect(
      await dbA.query(
        'tv_channels',
        columns: ['channel_id'],
        orderBy: 'channel_number ASC',
      ),
      hasLength(2),
    );

    ProfileRuntime.publish(profileB);
    DebrifyTvDatabase.instance.activateScope(profileB);
    final bRows = await DebrifyTvDatabase.instance.runScoped(
      (db) => db.query('tv_channels'),
    );
    expect(bRows, isEmpty);
  });

  test(
    'channel create edit delete stamps one record with convergent keywords',
    () async {
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications += 1;
      };
      WebDavSyncLibraryMutation.debugTvClock = () =>
          DateTime.fromMillisecondsSinceEpoch(100);

      await DebrifyTvRepository.instance.upsertChannel(
        channel('channel-a', keywords: const <String>['One', 'Two']),
      );
      var db = await DebrifyTvDatabase.instance.database;
      var states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvChannels],
      );
      expect(states, hasLength(1));
      expect(states.single['updated_at_ms'], 100);
      expect(states.single['origin_device_id'], 'device-a');
      expect(states.single['deleted'], 0);

      WebDavSyncLibraryMutation.debugTvClock = () =>
          DateTime.fromMillisecondsSinceEpoch(200);
      await DebrifyTvRepository.instance.upsertChannel(
        channel(
          'channel-a',
          name: 'Edited',
          keywords: const <String>['Two', 'Three'],
        ),
      );
      expect(
        await DebrifyTvRepository.instance.fetchChannelKeywords('channel-a'),
        <String>['Two', 'Three'],
      );
      states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvChannels],
      );
      expect(states, hasLength(1), reason: 'keywords share the channel stamp');
      expect(states.single['updated_at_ms'], 200);

      WebDavSyncLibraryMutation.debugTvClock = () =>
          DateTime.fromMillisecondsSinceEpoch(300);
      await DebrifyTvRepository.instance.deleteChannel('channel-a');
      db = await DebrifyTvDatabase.instance.database;
      states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvChannels],
      );
      expect(states.single['updated_at_ms'], 300);
      expect(states.single['deleted'], 1);
      expect(notifications, 0, reason: 'TV writers never wake ambient sync');
      expect(
        (await db.query(
          'webdav_sync_meta',
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '3',
      );
      var tvStatus = await DebrifyTvDatabase.instance
          .readWebDavTvSyncMetadata();
      expect(tvStatus.changesPending, isTrue);
      expect(tvStatus.pendingRevision, 3);
      await DebrifyTvDatabase.instance.closeScope(profileA);
      DebrifyTvDatabase.instance.activateScope(profileA);
      tvStatus = await DebrifyTvDatabase.instance.readWebDavTvSyncMetadata();
      expect(tvStatus.changesPending, isTrue);
      expect(tvStatus.pendingRevision, 3);
      await DebrifyTvDatabase.instance.completeWebDavTvSync(
        profileA,
        expectedPendingRevision: 3,
        syncedAtMs: 400,
      );
      tvStatus = await DebrifyTvDatabase.instance.readWebDavTvSyncMetadata();
      expect(tvStatus.changesPending, isFalse);
      expect(tvStatus.lastSyncedMs, 400);
    },
  );

  test(
    'failed restore and maintenance eviction preserve generation silently',
    () async {
      var notifications = 0;
      var generation = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications += 1;
      };
      WebDavSyncLibraryMutation.debugTvGenerationId = () =>
          'generation-${++generation}';
      WebDavSyncLibraryMutation.debugTvClock = () =>
          DateTime.fromMillisecondsSinceEpoch(100);
      await DebrifyTvRepository.instance.upsertChannel(channel('channel-a'));
      await DebrifyTvCacheService.saveEntry(
        cache('channel-a', <CachedTorrent>[torrent('a' * 40, 'Original')]),
      );
      final db = await DebrifyTvDatabase.instance.database;
      final before = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
      )).single;
      final revisionBefore = (await db.query(
        'webdav_sync_meta',
        where: 'key = ?',
        whereArgs: const <Object>['mutation_revision'],
      )).single['value'];
      expect(notifications, 0);

      await DebrifyTvCacheService.saveEntry(
        cache('channel-a', <CachedTorrent>[torrent('b' * 40, 'Restored')]),
        origin: WebDavSyncMutationOrigin.rollback,
      );
      var after = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
      )).single;
      expect(after['aux'], before['aux']);
      expect(notifications, 0);
      expect(
        (await db.query(
          'webdav_sync_meta',
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        revisionBefore,
      );

      await DebrifyTvCacheService.removeEntry(
        'channel-a',
        origin: WebDavSyncMutationOrigin.maintenance,
      );
      after = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
      )).single;
      expect(after['aux'], before['aux']);
      expect(await db.query('tv_cached_torrents'), isEmpty);
      expect(notifications, 0);
    },
  );

  test('explicit pool removal publishes one empty generation', () async {
    var generation = 0;
    var notifications = 0;
    WebDavSyncLibraryMutation.debugTvGenerationId = () =>
        'generation-${++generation}';
    WebDavSyncLibraryMutation.debugUserMutationObserver = () {
      notifications += 1;
    };
    await DebrifyTvRepository.instance.upsertChannel(channel('channel-a'));
    await DebrifyTvCacheService.saveEntry(
      cache('channel-a', <CachedTorrent>[torrent('a' * 40, 'Original')]),
    );
    final db = await DebrifyTvDatabase.instance.database;

    await DebrifyTvCacheService.removeEntry('channel-a');

    final state = (await db.query(
      'webdav_sync_record_state',
      where: 'kind = ?',
      whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
    )).single;
    expect(state['aux'], 'generation-2');
    expect(state['deleted'], 0);
    expect(await db.query('tv_cached_torrents'), isEmpty);
    expect(notifications, 0);
  });

  test(
    'repository clear tombstones channels and cache clear emits no pool stamp',
    () async {
      var generation = 0;
      WebDavSyncLibraryMutation.debugTvGenerationId = () =>
          'generation-${++generation}';
      await DebrifyTvRepository.instance.upsertChannel(channel('channel-a'));
      await DebrifyTvCacheService.saveEntry(
        cache('channel-a', <CachedTorrent>[torrent('a' * 40, 'Original')]),
      );
      final db = await DebrifyTvDatabase.instance.database;
      final poolBefore = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
      )).single;

      await DebrifyTvRepository.instance.clearAll();
      final revisionAfterRepository = (await db.query(
        'webdav_sync_meta',
        where: 'key = ?',
        whereArgs: const <Object>['mutation_revision'],
      )).single['value'];
      await DebrifyTvCacheService.clearAll(
        origin: WebDavSyncMutationOrigin.maintenance,
      );

      final channelState = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvChannels],
      )).single;
      final poolAfter = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
      )).single;
      expect(channelState['deleted'], 1);
      expect(poolAfter['aux'], poolBefore['aux']);
      expect(
        (await db.query(
          'webdav_sync_meta',
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        revisionAfterRepository,
      );
    },
  );

  test(
    'two devices canonicalize channel collisions and converge TV pools',
    () async {
      final channelA = leaf(100, 'device-a', const <String, Object?>{
        'name': 'Alpha',
        'avoidNsfw': true,
        'channelNumber': 7,
        'createdAt': 10,
        'keywords': <String>['alpha'],
      });
      final channelB = leaf(100, 'device-b', const <String, Object?>{
        'name': 'Beta',
        'avoidNsfw': false,
        'channelNumber': 7,
        'createdAt': 11,
        'keywords': <String>['beta'],
      });
      final generationLeaf = leaf(110, 'device-a', const <String, Object?>{
        'generationId': 'generation-a',
      });
      final poolLeaf = leaf(110, 'device-a', const <String, Object?>{
        'generationId': 'generation-a',
        'name': 'Pool title',
        'sizeBytes': 1234,
        'keywords': <String>['alpha'],
        'rank': 0,
      });
      final aTarget = WebDavSyncTvChannelTarget(
        channelId: 'channel-a',
        name: 'Alpha',
        avoidNsfw: true,
        desiredChannelNumber: 7,
        createdAtMs: 10,
        keywords: const <String>['alpha'],
        leaf: channelA,
      );
      final bTarget = WebDavSyncTvChannelTarget(
        channelId: 'channel-b',
        name: 'Beta',
        avoidNsfw: false,
        desiredChannelNumber: 7,
        createdAtMs: 11,
        keywords: const <String>['beta'],
        leaf: channelB,
      );
      final generationTarget = WebDavSyncTvPoolGenerationTarget(
        channelId: 'channel-a',
        generationId: 'generation-a',
        leaf: generationLeaf,
      );
      final poolTarget = WebDavSyncTvPoolTarget(
        channelId: 'channel-a',
        infohash: 'a' * 40,
        generationId: 'generation-a',
        name: 'Pool title',
        sizeBytes: 1234,
        keywords: const <String>['alpha'],
        rank: 0,
        leaf: poolLeaf,
      );

      Future<void> apply(
        ProfileScope scope,
        List<WebDavSyncTvChannelTarget> order,
      ) async {
        final outcome = await DebrifyTvDatabase.instance
            .applyWebDavSyncFamilies(
              scope,
              expectedRevision: 0,
              channelTargets: order,
              generationTargets: <WebDavSyncTvPoolGenerationTarget>[
                generationTarget,
              ],
              poolTargets: <WebDavSyncTvPoolTarget>[poolTarget],
              listTargets: const <WebDavSyncIptvListTarget>[],
              listChannelTargets: const <WebDavSyncIptvListChannelTarget>[],
              orderTargets: const <WebDavSyncIptvOrderTarget>[],
              watchTargets: const <WebDavSyncIptvWatchTarget>[],
              resumeTargets: const <WebDavSyncVideoResumeTarget>[],
            );
        expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
        expect(outcome.touchedNamespaces, <String>{'tv/ch', 'tv/pool'});
      }

      await apply(profileA, <WebDavSyncTvChannelTarget>[bTarget, aTarget]);
      await apply(profileB, <WebDavSyncTvChannelTarget>[aTarget, bTarget]);

      Future<List<Map<String, Object?>>> rows(
        ProfileScope scope,
        String table,
      ) => DebrifyTvDatabase.instance.runOneShotScoped(
        scope,
        (db) => db.query(
          table,
          orderBy: table == 'tv_channels'
              ? 'channel_id'
              : table == 'tv_cached_torrents'
              ? 'channel_id, infohash'
              : 'kind, owner_key, item_key',
        ),
      );
      final channelsA = await rows(profileA, 'tv_channels');
      final channelsB = await rows(profileB, 'tv_channels');
      expect(channelsA, channelsB);
      expect(channelsA.map((row) => row['channel_number']), <Object?>[7, 8]);
      expect(
        await rows(profileA, 'tv_cached_torrents'),
        await rows(profileB, 'tv_cached_torrents'),
      );
      final statesA = await rows(profileA, 'webdav_sync_record_state');
      final statesB = await rows(profileB, 'webdav_sync_record_state');
      expect(statesA, statesB);
      expect(
        statesA.where(
          (row) => row['kind'] == WebDavSyncLibraryKinds.tvChannels,
        ),
        everyElement(containsPair('normalized', 1)),
      );
      expect(
        statesA.where(
          (row) => row['kind'] == WebDavSyncLibraryKinds.tvChannels,
        ),
        everyElement(containsPair('updated_at_ms', 100)),
      );
      final projected = await DebrifyTvDatabase.instance.readWebDavSyncState(
        profileA,
        clockOffsetMs: 0,
        serverNowMs: 1000,
      );
      expect(
        projected.records
            .where((record) => record.kind == WebDavSyncLibraryKinds.tvChannels)
            .map((record) => record.value!['channelNumber']),
        everyElement(7),
        reason: 'physical collision repair must not rewrite desired wire data',
      );
    },
  );

  test(
    'an exact generation stamp with missing pool rows re-materializes',
    () async {
      final channelLeaf = leaf(100, 'device-a', const <String, Object?>{
        'name': 'Alpha',
        'avoidNsfw': false,
        'channelNumber': 7,
        'createdAt': 10,
        'keywords': <String>['alpha'],
      });
      final channelTarget = WebDavSyncTvChannelTarget(
        channelId: 'channel-a',
        name: 'Alpha',
        avoidNsfw: false,
        desiredChannelNumber: 7,
        createdAtMs: 10,
        keywords: const <String>['alpha'],
        leaf: channelLeaf,
      );
      final generationTarget = WebDavSyncTvPoolGenerationTarget(
        channelId: 'channel-a',
        generationId: 'generation-a',
        leaf: leaf(110, 'device-a', const <String, Object?>{
          'generationId': 'generation-a',
        }),
      );
      final poolTarget = WebDavSyncTvPoolTarget(
        channelId: 'channel-a',
        infohash: 'a' * 40,
        generationId: 'generation-a',
        name: 'Pool title',
        sizeBytes: 1234,
        keywords: const <String>['alpha'],
        rank: 0,
        leaf: leaf(110, 'device-a', const <String, Object?>{
          'generationId': 'generation-a',
          'name': 'Pool title',
          'sizeBytes': 1234,
          'keywords': <String>['alpha'],
          'rank': 0,
        }),
      );
      Future<Set<String>> apply(int expectedRevision) async {
        final outcome = await DebrifyTvDatabase.instance
            .applyWebDavSyncFamilies(
              profileA,
              expectedRevision: expectedRevision,
              channelTargets: <WebDavSyncTvChannelTarget>[channelTarget],
              generationTargets: <WebDavSyncTvPoolGenerationTarget>[
                generationTarget,
              ],
              poolTargets: <WebDavSyncTvPoolTarget>[poolTarget],
              listTargets: const <WebDavSyncIptvListTarget>[],
              listChannelTargets: const <WebDavSyncIptvListChannelTarget>[],
              orderTargets: const <WebDavSyncIptvOrderTarget>[],
              watchTargets: const <WebDavSyncIptvWatchTarget>[],
              resumeTargets: const <WebDavSyncVideoResumeTarget>[],
            );
        expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
        return outcome.touchedNamespaces;
      }

      await apply(0);
      // A snapshot or restore path that splits physical rows from their
      // sidecar stamps: rows vanish, the exact generation stamp remains.
      await DebrifyTvDatabase.instance.runOneShotScoped(
        profileA,
        (db) => db.delete('tv_cached_torrents'),
      );

      expect(await apply(1), contains('tv/pool'));
      final pools = await DebrifyTvDatabase.instance.runOneShotScoped(
        profileA,
        (db) => db.query('tv_cached_torrents'),
      );
      expect(pools, hasLength(1));
      expect(pools.single['infohash'], 'a' * 40);
    },
  );

  test(
    'two devices canonicalize custom lists and converge memberships',
    () async {
      final listALeaf = leaf(200, 'device-a', const <String, Object?>{
        'name': 'Alpha',
        'position': 7,
        'createdAt': 10,
      });
      final listBLeaf = leaf(200, 'device-b', const <String, Object?>{
        'name': 'Beta',
        'position': 7,
        'createdAt': 11,
      });
      WebDavSyncIptvListTarget listTarget(
        String id,
        String name,
        int createdAt,
        WebDavSyncCircleLeaf<Map<String, Object?>> value,
      ) => WebDavSyncIptvListTarget(
        listId: id,
        name: name,
        desiredPosition: 7,
        createdAtMs: createdAt,
        leaf: value,
      );
      WebDavSyncIptvListChannelTarget memberTarget(
        String listId,
        String url,
        int position,
      ) => WebDavSyncIptvListChannelTarget(
        listId: listId,
        url: url,
        localSourceId: '',
        leaf: leaf(210, 'device-a', <String, Object?>{
          'url': url,
          'name': url,
          'logoUrl': '',
          'group': 'News',
          'sourceRef': '',
          'addedAt': 20,
          'position': position,
        }),
      );
      final listA = listTarget('list_1_1', 'Alpha', 10, listALeaf);
      final listB = listTarget('list_2_2', 'Beta', 11, listBLeaf);
      final memberA = memberTarget(
        'list_1_1',
        'https://panel.invalid/live/1',
        4,
      );
      final memberB = memberTarget(
        'list_2_2',
        'https://panel.invalid/live/2',
        9,
      );

      Future<void> apply(
        ProfileScope scope,
        List<WebDavSyncIptvListTarget> lists,
        List<WebDavSyncIptvListChannelTarget> members,
      ) async {
        final outcome = await DebrifyTvDatabase.instance
            .applyWebDavSyncFamilies(
              scope,
              expectedRevision: 0,
              channelTargets: const <WebDavSyncTvChannelTarget>[],
              generationTargets: const <WebDavSyncTvPoolGenerationTarget>[],
              poolTargets: const <WebDavSyncTvPoolTarget>[],
              listTargets: lists,
              listChannelTargets: members,
              orderTargets: const <WebDavSyncIptvOrderTarget>[],
              watchTargets: const <WebDavSyncIptvWatchTarget>[],
              resumeTargets: const <WebDavSyncVideoResumeTarget>[],
            );
        expect(outcome.result, WebDavSyncLibraryApplyResult.applied);
        expect(outcome.touchedNamespaces, <String>{
          'iptv/list',
          'iptv/list-ch',
        });
      }

      await apply(
        profileA,
        <WebDavSyncIptvListTarget>[listB, listA],
        <WebDavSyncIptvListChannelTarget>[memberB, memberA],
      );
      await apply(
        profileB,
        <WebDavSyncIptvListTarget>[listA, listB],
        <WebDavSyncIptvListChannelTarget>[memberA, memberB],
      );

      Future<List<Map<String, Object?>>> rows(
        ProfileScope scope,
        String table,
      ) => DebrifyTvDatabase.instance.runOneShotScoped(
        scope,
        (db) => db.query(
          table,
          where: table == 'iptv_lists' ? 'is_builtin = 0' : null,
          orderBy: table == 'iptv_lists'
              ? 'id'
              : table == 'iptv_list_channels'
              ? 'list_id, url'
              : 'kind, owner_key, item_key',
        ),
      );
      final listsA = await rows(profileA, 'iptv_lists');
      final listsB = await rows(profileB, 'iptv_lists');
      expect(listsA, listsB);
      expect(listsA.map((row) => row['position']), <Object?>[1, 2]);
      expect(
        await rows(profileA, 'iptv_list_channels'),
        await rows(profileB, 'iptv_list_channels'),
      );
      expect(
        await rows(profileA, 'webdav_sync_record_state'),
        await rows(profileB, 'webdav_sync_record_state'),
      );
      final projected = await DebrifyTvDatabase.instance.readWebDavSyncState(
        profileA,
        clockOffsetMs: 0,
        serverNowMs: 1000,
      );
      expect(
        projected.records
            .where((record) => record.kind == WebDavSyncLibraryKinds.iptvLists)
            .map((record) => record.value!['position']),
        everyElement(7),
        reason: 'physical compaction must not rewrite desired wire data',
      );

      final drifted = await DebrifyTvDatabase.instance.runOneShotScoped(
        profileA,
        (db) => db.update(
          'iptv_lists',
          <String, Object?>{'position': 99},
          where: 'id = ?',
          whereArgs: const <Object?>['list_1_1'],
        ),
      );
      expect(drifted, 1);
      final healed = await DebrifyTvDatabase.instance.applyWebDavSyncFamilies(
        profileA,
        expectedRevision: projected.mutationRevision,
        channelTargets: const <WebDavSyncTvChannelTarget>[],
        generationTargets: const <WebDavSyncTvPoolGenerationTarget>[],
        poolTargets: const <WebDavSyncTvPoolTarget>[],
        listTargets: <WebDavSyncIptvListTarget>[listA, listB],
        listChannelTargets: <WebDavSyncIptvListChannelTarget>[memberA, memberB],
        orderTargets: const <WebDavSyncIptvOrderTarget>[],
        watchTargets: const <WebDavSyncIptvWatchTarget>[],
        resumeTargets: const <WebDavSyncVideoResumeTarget>[],
      );
      expect(healed.result, WebDavSyncLibraryApplyResult.applied);
      expect(healed.touchedNamespaces, const <String>{'iptv/list'});
      expect(
        (await rows(profileA, 'iptv_lists')).map((row) => row['position']),
        <Object?>[1, 2],
      );
      final favorites = await DebrifyTvDatabase.instance.runOneShotScoped(
        profileA,
        (db) => db.query(
          'iptv_lists',
          where: 'id = ?',
          whereArgs: const <Object?>[DebrifyTvDatabase.favoritesListId],
        ),
      );
      expect(favorites.single['position'], 0);
    },
  );

  test('native payload path contains no Debrify TV SQLite writer', () async {
    final nativeSources = <File>[];
    for (final root in <String>[
      'android',
      'ios',
      'macos',
      'linux',
      'windows',
    ]) {
      final directory = Directory(root);
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File &&
            <String>[
              '.java',
              '.kt',
              '.swift',
              '.m',
              '.mm',
              '.cc',
              '.cpp',
            ].any(entity.path.endsWith)) {
          nativeSources.add(entity);
        }
      }
    }
    for (final file in nativeSources) {
      final source = await file.readAsString();
      expect(source, isNot(contains('tv_channels')), reason: file.path);
      expect(source, isNot(contains('tv_channel_keywords')), reason: file.path);
      expect(source, isNot(contains('tv_cached_torrents')), reason: file.path);
    }
  });
}
