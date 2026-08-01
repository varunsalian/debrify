import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_tv_database.dart';

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

  Future<void> configure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

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
      expect(await hasTable(db, 'iptv_favorites'), isFalse,
          reason: 'v5 never creates the legacy table');
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
      expect(row['channel_number'], isNull,
          reason: 'a v3 row never had one; the ALTER only makes the copy '
              'column-compatible');
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
      expect(rows.map((r) => r['name']), ['First', 'Second', 'Third'],
          reason: 'oldest-starred-first ordering survives the copy');
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

      expect(await db.query('iptv_list_channels'), hasLength(1),
          reason: 'seeding is INSERT OR IGNORE, never OR REPLACE');
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
      expect(remaining.single['list_id'], 'favorites',
          reason: 'only the deleted list loses its rows');
    });
  });
}
