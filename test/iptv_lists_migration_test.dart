import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_mutation.dart';

/// The v5 migration: favorites stop being their own table and become the
/// built-in list of the custom-lists schema.
///
/// This is a one-way, destructive edit of user data — it copies rows out of
/// `iptv_favorites` and then drops the table — so every upgrade path that can
/// reach it is exercised here, not just the newest one. The interesting ones
/// are v1/v2: those databases never had an `iptv_favorites` table, and since
/// `createIptvStoreTables` no longer creates one, a blind `SELECT` from it
/// would throw mid-upgrade and wedge the store.
void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('debrify_tv_migration');
    dbPath = p.join(dir.path, 'debrify_tv.db');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> configure(Database db) => db.execute('PRAGMA foreign_keys = ON');

  /// The v1 shape: Debrify-TV channels only, before channel_number and
  /// before any IPTV table existed.
  Future<void> createV1(Database db, int _) async {
    await db.execute('''
      CREATE TABLE tv_channels (
        channel_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avoid_nsfw INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// v2 added channel_number to tv_channels; IPTV tables still absent.
  Future<void> createV2(Database db, int _) async {
    await db.execute('''
      CREATE TABLE tv_channels (
        channel_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avoid_nsfw INTEGER NOT NULL DEFAULT 1,
        channel_number INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  /// v3 introduced iptv_favorites — without channel_number.
  Future<void> createV3(Database db, int version) async {
    await createV2(db, version);
    await db.execute('''
      CREATE TABLE iptv_favorites (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        http_headers_json TEXT,
        added_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// v4 added channel_number to iptv_favorites.
  Future<void> createV4(Database db, int version) async {
    await createV2(db, version);
    await db.execute('''
      CREATE TABLE iptv_favorites (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        channel_number INTEGER,
        http_headers_json TEXT,
        added_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// v5 introduced lists, before membership rows had a manual position.
  Future<void> createV5(Database db, int _) async {
    await db.execute('''
      CREATE TABLE iptv_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE iptv_list_channels (
        list_id TEXT NOT NULL,
        url TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        channel_number INTEGER,
        content_type TEXT,
        duration INTEGER,
        http_headers_json TEXT,
        added_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (list_id, url),
        FOREIGN KEY (list_id) REFERENCES iptv_lists(id) ON DELETE CASCADE
      )
    ''');
    await db.insert('iptv_lists', {
      'id': 'favorites',
      'name': 'Favorites',
      'position': 0,
      'is_builtin': 1,
      'created_at': 0,
      'updated_at': 0,
    });
  }

  Future<Database> openAt(
    int version,
    Future<void> Function(Database, int) onCreate,
  ) {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: configure,
        onCreate: onCreate,
      ),
    );
  }

  Future<Database> upgradeToV5() {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: configure,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
        onUpgrade: DebrifyTvDatabase.runUpgrade,
      ),
    );
  }

  Future<Database> upgradeToV6() {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: configure,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
        onUpgrade: DebrifyTvDatabase.runUpgrade,
      ),
    );
  }

  Future<Database> upgradeToV7() {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: configure,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
        onUpgrade: DebrifyTvDatabase.runUpgrade,
      ),
    );
  }

  Future<Database> upgradeToV8() {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onConfigure: configure,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
        onUpgrade: DebrifyTvDatabase.runUpgrade,
      ),
    );
  }

  Future<Database> upgradeToV9() {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 9,
        onConfigure: configure,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
        onUpgrade: DebrifyTvDatabase.runUpgrade,
      ),
    );
  }

  Future<Database> upgradeToV10() {
    return databaseFactoryFfiNoIsolate.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 10,
        onConfigure: configure,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
        onUpgrade: DebrifyTvDatabase.runUpgrade,
      ),
    );
  }

  Future<bool> hasTable(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    );
    return rows.isNotEmpty;
  }

  group('upgrades that never had an iptv_favorites table', () {
    test('v1 reaches v5 with the lists schema and no copy step', () async {
      var db = await openAt(1, createV1);
      await db.close();

      db = await upgradeToV5();
      addTearDown(db.close);

      expect(await hasTable(db, 'iptv_lists'), isTrue);
      expect(await hasTable(db, 'iptv_list_channels'), isTrue);
      expect(
        await hasTable(db, 'iptv_favorites'),
        isFalse,
        reason: 'v5 never creates the legacy table',
      );
      expect(await db.query('iptv_list_channels'), isEmpty);

      final lists = await db.query('iptv_lists');
      expect(lists.single['id'], 'favorites');
      expect(lists.single['is_builtin'], 1);

      // The v1 step must still have run.
      final columns = await db.rawQuery('PRAGMA table_info(tv_channels)');
      expect(columns.map((c) => c['name']), contains('channel_number'));
    });

    test('v2 reaches v5 the same way', () async {
      var db = await openAt(2, createV2);
      await db.close();

      db = await upgradeToV5();
      addTearDown(db.close);

      expect(await hasTable(db, 'iptv_lists'), isTrue);
      expect(await hasTable(db, 'iptv_favorites'), isFalse);
      expect(await db.query('iptv_list_channels'), isEmpty);
    });
  });

  group('upgrades that carry favorites across', () {
    test('v3 gets the channel_number ALTER before the copy', () async {
      var db = await openAt(3, createV3);
      await db.insert('iptv_favorites', {
        'url': 'http://h/live/u/p/1.ts',
        'name': 'Sky',
        'logo_url': 'http://h/1.png',
        'channel_group': 'Sports',
        'playlist_id': 'p1',
        'http_headers_json': '{"User-Agent":"TiviMate"}',
        'added_at': 111,
      });
      await db.close();

      db = await upgradeToV5();
      addTearDown(db.close);

      final rows = await db.query('iptv_list_channels');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['list_id'], 'favorites');
      expect(row['url'], 'http://h/live/u/p/1.ts');
      expect(row['name'], 'Sky');
      expect(row['channel_group'], 'Sports');
      expect(row['playlist_id'], 'p1');
      expect(row['http_headers_json'], '{"User-Agent":"TiviMate"}');
      expect(row['added_at'], 111);
      expect(
        row['channel_number'],
        isNull,
        reason:
            'a v3 row never had one; the ALTER only makes the copy '
            'column-compatible',
      );
      expect(row['content_type'], isNull);
      expect(await hasTable(db, 'iptv_favorites'), isFalse);
    });

    test('v4 copies channel_number and preserves added_at ordering', () async {
      var db = await openAt(4, createV4);
      for (final entry in [
        ('http://h/live/u/p/3.ts', 'Third', 300),
        ('http://h/live/u/p/1.ts', 'First', 100),
        ('http://h/live/u/p/2.ts', 'Second', 200),
      ]) {
        await db.insert('iptv_favorites', {
          'url': entry.$1,
          'name': entry.$2,
          'channel_number': entry.$3 ~/ 100,
          'added_at': entry.$3,
        });
      }
      await db.close();

      db = await upgradeToV5();
      addTearDown(db.close);

      final rows = await db.query(
        'iptv_list_channels',
        orderBy: 'added_at ASC, url ASC',
      );
      expect(
        rows.map((r) => r['name']),
        ['First', 'Second', 'Third'],
        reason: 'oldest-starred-first ordering survives the copy',
      );
      expect(rows.map((r) => r['channel_number']), [1, 2, 3]);
      expect(rows.every((r) => r['list_id'] == 'favorites'), isTrue);
      expect(await hasTable(db, 'iptv_favorites'), isFalse);
    });
  });

  group('seeding the built-in list', () {
    test('re-running the create step leaves memberships alone', () async {
      var db = await openAt(4, createV4);
      await db.insert('iptv_favorites', {
        'url': 'http://h/live/u/p/1.ts',
        'name': 'Keep me',
        'added_at': 1,
      });
      await db.close();

      db = await upgradeToV5();
      addTearDown(db.close);
      expect(await db.query('iptv_list_channels'), hasLength(1));

      // This is what every subsequent app launch does. If the built-in row
      // were seeded with INSERT OR REPLACE, the conflicting parent row would
      // be DELETEd with foreign-key actions firing and cascade every
      // membership away — data loss on launch, not an edge case.
      await DebrifyTvDatabase.createIptvStoreTables(db);
      await DebrifyTvDatabase.seedBuiltinList(db);

      expect(
        await db.query('iptv_list_channels'),
        hasLength(1),
        reason: 'seeding is INSERT OR IGNORE, never OR REPLACE',
      );
      expect(await db.query('iptv_lists'), hasLength(1));
    });

    test('deleting a custom list cascades its memberships away', () async {
      final db = await openAt(
        5,
        (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
      );
      addTearDown(db.close);

      await db.insert('iptv_lists', {
        'id': 'l1',
        'name': 'Kids',
        'position': 1,
        'is_builtin': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('iptv_list_channels', {
        'list_id': 'l1',
        'url': 'http://h/live/u/p/1.ts',
        'added_at': 1,
      });
      await db.insert('iptv_list_channels', {
        'list_id': 'favorites',
        'url': 'http://h/live/u/p/1.ts',
        'added_at': 1,
      });

      await db.delete('iptv_lists', where: 'id = ?', whereArgs: ['l1']);

      final remaining = await db.query('iptv_list_channels');
      expect(remaining, hasLength(1));
      expect(
        remaining.single['list_id'],
        'favorites',
        reason: 'only the deleted list loses its rows',
      );
    });
  });

  test('v5→v6 backfills the exact former A-Z list order', () async {
    var db = await openAt(5, createV5);
    for (final entry in const [
      ('zulu', 'Zulu', 100),
      ('alpha', 'alpha', 300),
      ('mike', 'Mike', 200),
    ]) {
      await db.insert('iptv_list_channels', {
        'list_id': 'favorites',
        'url': entry.$1,
        'name': entry.$2,
        'added_at': entry.$3,
      });
    }
    await db.close();

    db = await upgradeToV6();
    addTearDown(db.close);
    final rows = await db.query('iptv_list_channels', orderBy: 'position ASC');
    expect(rows.map((row) => row['name']), ['alpha', 'Mike', 'Zulu']);
    expect(rows.map((row) => row['position']), [0, 1, 2]);
    expect(await hasTable(db, 'iptv_category_channel_orders'), isTrue);
  });

  test('fresh v7 and v6→v7 both create the library-sync sidecars', () async {
    var db = await upgradeToV7();
    expect(await hasTable(db, 'webdav_sync_record_state'), isTrue);
    expect(await hasTable(db, 'webdav_sync_meta'), isTrue);
    expect(
      (await db.query(
        'webdav_sync_meta',
        where: 'key = ?',
        whereArgs: const <Object>['mutation_revision'],
      )).single['value'],
      '0',
    );
    await db.close();

    await File(dbPath).delete();
    db = await openAt(6, (db, _) async {
      await DebrifyTvDatabase.createIptvStoreTables(db);
      await db.delete('webdav_sync_meta');
      await db.execute('DROP TABLE webdav_sync_record_state');
      await db.execute('DROP TABLE webdav_sync_meta');
    });
    await db.close();
    db = await upgradeToV7();
    addTearDown(db.close);
    expect(await hasTable(db, 'webdav_sync_record_state'), isTrue);
    expect(await hasTable(db, 'webdav_sync_meta'), isTrue);
  });

  test(
    'v7→v8 adds resume source identity and backfills all IPTV states',
    () async {
      var db = await openAt(7, (db, _) async {
        await DebrifyTvDatabase.createIptvStoreTables(db);
        await db.execute('DROP TABLE video_resume');
        await db.execute('''
        CREATE TABLE video_resume (
          resume_key TEXT PRIMARY KEY,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          speed REAL NOT NULL DEFAULT 1.0,
          aspect TEXT NOT NULL DEFAULT 'contain',
          updated_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
      });
      await db.insert('iptv_watch_history', <String, Object?>{
        'url': 'https://panel.invalid/movie/1',
        'playlist_id': 'source-1',
        'last_played_at': 120,
      });
      await db.insert('video_resume', <String, Object?>{
        'resume_key': 'https://panel.invalid/movie/1',
        'position_ms': 10,
        'duration_ms': 20,
        'updated_at': 130,
      });
      await db.insert('iptv_category_channel_orders', <String, Object?>{
        'source_id': 'source-1',
        'channel_group': 'News',
        'url': 'https://panel.invalid/live/1',
        'name': 'One',
        'occurrence': 0,
        'position': 0,
      });
      await db.close();

      db = await upgradeToV8();
      addTearDown(db.close);
      final columns = await db.rawQuery('PRAGMA table_info(video_resume)');
      expect(columns.map((row) => row['name']), contains('source_id'));
      expect((await db.query('video_resume')).single['source_id'], 'source-1');
      final states = await db.query('webdav_sync_record_state');
      expect(states.map((row) => row['kind']).toSet(), <Object?>{
        WebDavSyncLibraryKinds.iptvCategoryChannelOrders,
        WebDavSyncLibraryKinds.iptvWatchHistory,
        WebDavSyncLibraryKinds.videoResume,
      });
      expect(
        states.map((row) => row['origin_device_id']),
        everyElement('migration'),
      );
    },
  );

  test('v8→v9 backfills channels and pools with migration origin', () async {
    WebDavSyncLibraryMutation.debugTvGenerationId = () => 'migration-gen';
    addTearDown(WebDavSyncLibraryMutation.resetDebugTvHooks);
    var db = await openAt(8, (db, _) async {
      await DebrifyTvDatabase.createIptvStoreTables(db);
      await db.execute('''
        CREATE TABLE tv_channels (
          channel_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          avoid_nsfw INTEGER NOT NULL DEFAULT 1,
          channel_number INTEGER NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE tv_cached_torrents (
          channel_id TEXT NOT NULL,
          infohash TEXT NOT NULL,
          name TEXT NOT NULL,
          size_bytes INTEGER NOT NULL,
          created_unix INTEGER NOT NULL,
          seeders INTEGER NOT NULL,
          leechers INTEGER NOT NULL,
          completed INTEGER NOT NULL,
          scraped_date INTEGER NOT NULL,
          keywords_json TEXT NOT NULL,
          sources_json TEXT NOT NULL,
          added_at INTEGER NOT NULL,
          PRIMARY KEY (channel_id, infohash)
        )
      ''');
    });
    await db.insert('tv_channels', <String, Object?>{
      'channel_id': 'channel-a',
      'name': 'Alpha',
      'avoid_nsfw': 1,
      'channel_number': 4,
      'created_at': 10,
      'updated_at': 123,
    });
    await db.insert('tv_cached_torrents', <String, Object?>{
      'channel_id': 'channel-a',
      'infohash': 'a' * 40,
      'name': 'Pool',
      'size_bytes': 1,
      'created_unix': 2,
      'seeders': 3,
      'leechers': 4,
      'completed': 5,
      'scraped_date': 6,
      'keywords_json': '[]',
      'sources_json': '[]',
      'added_at': 999999,
    });
    await db.close();

    db = await upgradeToV9();
    addTearDown(db.close);
    final channelState = (await db.query(
      'webdav_sync_record_state',
      where: 'kind = ?',
      whereArgs: const <Object>[WebDavSyncLibraryKinds.tvChannels],
    )).single;
    final generationState = (await db.query(
      'webdav_sync_record_state',
      where: 'kind = ?',
      whereArgs: const <Object>[WebDavSyncLibraryKinds.tvPoolGeneration],
    )).single;
    expect(channelState['updated_at_ms'], 123);
    expect(channelState['origin_device_id'], 'migration');
    expect(generationState['origin_device_id'], 'migration');
    expect(generationState['aux'], 'migration-gen');
    expect(generationState['updated_at_ms'], isNot(999999));
  });

  test('v9→v10 seeds custom lists and every membership', () async {
    var db = await openAt(
      9,
      (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
    );
    await db.insert('iptv_lists', <String, Object?>{
      'id': 'list_100_1',
      'name': 'Sports',
      'position': 1,
      'is_builtin': 0,
      'created_at': 90,
      'updated_at': 100,
    });
    await db.insert('iptv_list_channels', <String, Object?>{
      'list_id': 'favorites',
      'url': 'https://panel.invalid/live/1',
      'added_at': 110,
      'position': 0,
    });
    await db.insert('iptv_list_channels', <String, Object?>{
      'list_id': 'list_100_1',
      'url': 'https://panel.invalid/live/2',
      'added_at': 120,
      'position': 0,
    });
    await db.close();

    db = await upgradeToV10();
    addTearDown(db.close);
    final listStates = await db.query(
      'webdav_sync_record_state',
      where: 'kind = ?',
      whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvLists],
    );
    expect(listStates, hasLength(1));
    expect(listStates.single['owner_key'], 'list_100_1');
    expect(listStates.single['updated_at_ms'], 100);
    expect(listStates.single['origin_device_id'], 'migration');

    final memberStates = await db.query(
      'webdav_sync_record_state',
      where: 'kind = ?',
      whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
      orderBy: 'owner_key',
    );
    expect(memberStates, hasLength(2));
    expect(memberStates.map((row) => row['owner_key']).toSet(), <Object?>{
      'favorites',
      'list_100_1',
    });
    expect(memberStates.map((row) => row['updated_at_ms']).toSet(), <Object?>{
      110,
      120,
    });
    expect(
      memberStates.map((row) => row['origin_device_id']),
      everyElement('migration'),
    );
  });
}
