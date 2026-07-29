import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DebrifyTvDatabase {
  DebrifyTvDatabase._();

  static final DebrifyTvDatabase instance = DebrifyTvDatabase._();

  /// Tests inject an in-memory database here (sqflite_common_ffi) so store
  /// logic runs against the real schema without path_provider.
  @visibleForTesting
  static Database? debugDatabaseOverride;

  Database? _db;

  Future<Database> get database async {
    final override = debugDatabaseOverride;
    if (override != null) {
      return override;
    }
    if (_db != null) {
      return _db!;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'debrify_tv.db');

    _db = await openDatabase(
      dbPath,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
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
          CREATE TABLE tv_channel_keywords (
            channel_id TEXT NOT NULL,
            position INTEGER NOT NULL,
            keyword TEXT NOT NULL,
            PRIMARY KEY (channel_id, position),
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE tv_channel_cache_state (
            channel_id TEXT PRIMARY KEY,
            status TEXT NOT NULL DEFAULT 'warming',
            error_message TEXT,
            fetched_at INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
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
            PRIMARY KEY (channel_id, infohash),
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_tv_cached_torrents_channel_added
          ON tv_cached_torrents(channel_id, added_at)
        ''');

        await db.execute('''
          CREATE TABLE tv_keyword_stats (
            channel_id TEXT NOT NULL,
            keyword TEXT NOT NULL,
            total_fetched INTEGER NOT NULL,
            last_searched_at INTEGER NOT NULL,
            pages_pulled INTEGER NOT NULL,
            pirate_bay_hits INTEGER NOT NULL,
            PRIMARY KEY (channel_id, keyword),
            FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
          )
        ''');

        await createIptvStoreTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE tv_channels ADD COLUMN channel_number INTEGER',
          );

          final rows = await db.query(
            'tv_channels',
            columns: ['channel_id'],
            orderBy: 'updated_at DESC',
          );

          var channelNumber = 1;
          for (final row in rows) {
            final channelId = row['channel_id'] as String?;
            if (channelId == null || channelId.isEmpty) {
              continue;
            }
            await db.update(
              'tv_channels',
              {'channel_number': channelNumber},
              where: 'channel_id = ?',
              whereArgs: [channelId],
            );
            channelNumber += 1;
          }

          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_tv_channels_channel_number ON tv_channels(channel_number)',
          );
        }

        if (oldVersion < 3) {
          await createIptvStoreTables(db);
        }
      },
    );

    // Ensure index exists for fresh creates (onCreate already runs for v2 DB)
    await _db!.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tv_channels_channel_number ON tv_channels(channel_number)',
    );

    return _db!;
  }

  Future<T> runTxn<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action, exclusive: false);
  }

  /// IPTV favorites / watch history / video resume tables (schema v3), used
  /// by IptvMediaStore. `IF NOT EXISTS` so it's safe from both onCreate and
  /// onUpgrade, and callable directly by tests on an in-memory database.
  static Future<void> createIptvStoreTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_favorites (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        http_headers_json TEXT,
        added_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_favorites_playlist
      ON iptv_favorites(playlist_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_watch_history (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        http_headers_json TEXT,
        series_id TEXT,
        series_name TEXT,
        season INTEGER,
        episode INTEGER,
        has_next INTEGER,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_watch_history_last_played
      ON iptv_watch_history(last_played_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_watch_history_playlist
      ON iptv_watch_history(playlist_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_resume (
        resume_key TEXT PRIMARY KEY,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        speed REAL NOT NULL DEFAULT 1.0,
        aspect TEXT NOT NULL DEFAULT 'contain',
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}
