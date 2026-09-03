import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart'
    show IptvResultsViewState;
import 'package:sqlite3/sqlite3.dart' as raw;

IptvChannel _ch(
  int i, {
  String? group,
  String? name,
  String? contentType = 'live',
  int? duration = -1,
  Map<String, String> attributes = const {},
  Map<String, String> headers = const {},
}) => IptvChannel(
  name: name ?? 'Channel $i',
  url: 'http://h/live/u/p/$i.ts',
  logoUrl: 'http://h/logo/$i.png',
  group: group,
  duration: duration,
  contentType: contentType,
  attributes: attributes,
  httpHeaders: headers,
);

/// A pre-numbering (v1) database at [path] holding [rows] live channels under
/// the catalog key 'big' — the shape every existing install upgrades from.
void _createV1Schema(String path, {required int rows}) {
  final db = raw.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE catalogs (
        catalog_key TEXT PRIMARY KEY,
        generation INTEGER NOT NULL,
        channel_count INTEGER NOT NULL,
        content_digest TEXT NOT NULL,
        categories_json TEXT,
        epg_url TEXT,
        ingested_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE channels (
        id INTEGER PRIMARY KEY,
        catalog_key TEXT NOT NULL,
        generation INTEGER NOT NULL,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        logo_url TEXT,
        grp TEXT,
        duration INTEGER,
        content_type TEXT,
        attributes_json TEXT,
        http_headers_json TEXT,
        search_key TEXT NOT NULL
      )
    ''');
    db.execute(
      'CREATE INDEX idx_channels_page '
      'ON channels(catalog_key, generation, position)',
    );
    db.execute(
      "INSERT INTO catalogs VALUES ('big', 1, $rows, 'd', NULL, NULL, 1)",
    );
    final insert = db.prepare(
      "INSERT INTO channels(catalog_key, generation, position, name, url, "
      "grp, duration, content_type, attributes_json, http_headers_json, "
      "search_key) VALUES ('big', 1, ?, ?, ?, ?, -1, 'live', '{}', '{}', ?)",
    );
    try {
      db.execute('BEGIN');
      for (var i = 0; i < rows; i++) {
        insert.execute([
          i,
          'Channel $i',
          'http://h/$i.ts',
          'G${i % 400}',
          'channel $i',
        ]);
      }
      db.execute('COMMIT');
    } finally {
      insert.dispose();
    }
  } finally {
    db.dispose();
  }
}

int _ingestInWorker(List<Object> args) {
  final channels = [for (var i = 0; i < 500; i++) _ch(i, group: 'G${i % 5}')];
  IptvCatalogDb.ingest(
    dbPath: args[0] as String,
    catalogKey: args[1] as String,
    channels: channels,
  );
  return channels.length;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalog_db_test');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
  });

  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await dir.delete(recursive: true);
  });

  test('cold open prepares the database on a worker isolate', () {
    expect(
      IptvCatalogDb.debugLastPreparationIsolateName,
      'iptv-catalog-db-init',
    );
    expect(IptvCatalogDb.debugPreparationCount, 1);
    expect(IptvCatalogDb.isOpen, isTrue);
  });

  test('fresh schema includes the final library-sync sidecar shape', () {
    final db = raw.sqlite3.open(IptvCatalogDb.path);
    try {
      final tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'webdav_sync_%' ORDER BY name",
          )
          .map((row) => row['name']);
      expect(tables, <String>['webdav_sync_meta', 'webdav_sync_record_state']);
      expect(
        db
            .select(
              "SELECT value FROM webdav_sync_meta "
              "WHERE key = 'mutation_revision'",
            )
            .single['value'],
        '0',
      );
    } finally {
      db.dispose();
    }
  });

  test(
    'v2 upgrade backfills hidden groups and category-order vectors',
    () async {
      final path = IptvCatalogDb.path;
      var db = raw.sqlite3.open(path);
      db.execute(
        'INSERT INTO hidden_groups (catalog_key, grp, hidden_at) '
        'VALUES (?, ?, ?)',
        ['m3u|secret-url', 'Adult', 1234],
      );
      db.execute(
        'INSERT INTO category_manual_orders '
        '(catalog_key, grp, manual_position) VALUES (?, ?, ?)',
        ['m3u|secret-url', 'News', 0],
      );
      db.execute('DELETE FROM webdav_sync_record_state');
      db.execute('PRAGMA user_version = 2');
      db.dispose();
      IptvCatalogDb.debugClose();

      await IptvCatalogDb.open();
      await IptvCatalogDb.ensureMigrations();

      db = raw.sqlite3.open(path);
      try {
        final row = db.select(
          'SELECT * FROM webdav_sync_record_state WHERE kind = ?',
          [WebDavSyncLibraryKinds.hiddenGroups],
        ).single;
        expect(row['owner_key'], 'm3u|secret-url');
        expect(row['item_key'], 'Adult');
        expect(row['updated_at_ms'], 1234);
        expect(row['origin_device_id'], 'migration');
        expect(row['normalized'], 0);
        expect(row['deleted'], 0);
        final categoryOrder = db.select(
          'SELECT * FROM webdav_sync_record_state WHERE kind = ?',
          [WebDavSyncLibraryKinds.categoryManualOrders],
        ).single;
        expect(categoryOrder['owner_key'], 'm3u|secret-url');
        expect(categoryOrder['item_key'], 'order');
        expect(categoryOrder['origin_device_id'], 'migration');
        expect(categoryOrder['normalized'], 0);
        expect(categoryOrder['deleted'], 0);
        expect(db.select('PRAGMA user_version').single.values.single, 4);
      } finally {
        db.dispose();
      }
    },
  );

  test('v1 catalog migration backfills only live channel numbers', () async {
    IptvCatalogDb.debugClose();
    final path = '${dir.path}/iptv_catalog.db';
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    final db = raw.sqlite3.open(path);
    db.execute('''
      CREATE TABLE catalogs (
        catalog_key TEXT PRIMARY KEY,
        generation INTEGER NOT NULL,
        channel_count INTEGER NOT NULL,
        content_digest TEXT NOT NULL,
        categories_json TEXT,
        epg_url TEXT,
        ingested_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE channels (
        id INTEGER PRIMARY KEY,
        catalog_key TEXT NOT NULL,
        generation INTEGER NOT NULL,
        position INTEGER NOT NULL,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        logo_url TEXT,
        grp TEXT,
        duration INTEGER,
        content_type TEXT,
        attributes_json TEXT,
        http_headers_json TEXT,
        search_key TEXT NOT NULL
      )
    ''');
    db.execute("INSERT INTO catalogs VALUES ('old', 1, 4, 'd', NULL, NULL, 1)");
    db.execute(
      "INSERT INTO channels(catalog_key, generation, position, name, url, "
      "duration, content_type, search_key) VALUES "
      "('old', 1, 0, 'Live A', 'a', -1, 'live', 'live a'), "
      "('old', 1, 1, 'Movie', 'm', NULL, 'vod', 'movie'), "
      "('old', 1, 2, 'Live B', 'b', -1, 'live', 'live b'), "
      "('old', 1, 3, 'M3U Zero', 'z', 0, NULL, 'm3u zero')",
    );
    db.dispose();

    await IptvCatalogDb.open();
    await IptvCatalogDb.ensureMigrations();
    final page = IptvCatalogDb.snapshot('old')!.page(offset: 0, limit: 10);
    expect(page.map((channel) => channel.channelNumber), [1, null, 2, 3]);
  });

  test('the number backfill never plans a correlated subquery', () async {
    // The regression this guards is not cosmetic: spelled as a correlated
    // scalar subquery, the backfill re-scans the whole materialized CTE once
    // per updated row and takes 14 SECONDS for 50k channels on a desktop —
    // minutes on the TV boxes those playlists live on, which is what made
    // opening IPTV look like a hang before it was rewritten as a join.
    final db = raw.sqlite3.open(IptvCatalogDb.path);
    try {
      final plan = db
          .select('EXPLAIN QUERY PLAN ${IptvCatalogDb.debugNumberBackfillSql}')
          .map((row) => row['detail'] as String)
          .join('\n');
      expect(plan, isNot(contains('CORRELATED')));
    } finally {
      db.dispose();
    }
  });

  test('migration runs once, then costs nothing on later opens', () async {
    // setUp already opened a fresh database, so the one-time upgrade has not
    // run yet for it.
    expect(IptvCatalogDb.debugMigrationRunCount, 0);
    await IptvCatalogDb.ensureMigrations();
    expect(IptvCatalogDb.debugMigrationRunCount, 1);

    await IptvCatalogDb.ensureMigrations();
    await IptvCatalogDb.ensureMigrations();
    expect(
      IptvCatalogDb.debugMigrationRunCount,
      1,
      reason: 'a migrated database must not re-run the backfill',
    );

    final db = raw.sqlite3.open(IptvCatalogDb.path);
    try {
      expect(db.select('PRAGMA user_version').first.values.first, 4);
    } finally {
      db.dispose();
    }
  });

  test(
    'an interrupted migration leaves a clean v1 database to retry',
    () async {
      IptvCatalogDb.debugClose();
      final path = '${dir.path}/iptv_catalog.db';
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      _createV1Schema(path, rows: 200);

      // Stand in for the device dying mid-upgrade: the migration's transaction
      // never commits. Everything it touched — rows, index and version stamp —
      // must come back together, or a retry would resume from a half state.
      final db = raw.sqlite3.open(path);
      try {
        // The column arrives outside the transaction (metadata-only DDL on the
        // preparation path); only the row work is transactional.
        db.execute('ALTER TABLE channels ADD COLUMN channel_number INTEGER');
        db.execute('BEGIN IMMEDIATE');
        db.execute(IptvCatalogDb.debugNumberBackfillSql);
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_channels_number '
          'ON channels(catalog_key, generation, channel_number)',
        );
        db.execute('PRAGMA user_version = 2');
        db.execute('ROLLBACK');

        expect(db.select('PRAGMA user_version').first.values.first, 0);
        expect(
          db
              .select(
                'SELECT count(*) AS c FROM channels WHERE channel_number '
                'IS NOT NULL',
              )
              .first['c'],
          0,
        );
        expect(
          db
              .select(
                "SELECT count(*) AS c FROM sqlite_master "
                "WHERE name = 'idx_channels_number'",
              )
              .first['c'],
          0,
        );
      } finally {
        db.dispose();
      }

      // The retry then succeeds from an untouched v1 database.
      await IptvCatalogDb.open();
      await IptvCatalogDb.ensureMigrations();
      final numbers = IptvCatalogDb.snapshot(
        'big',
      )!.page(offset: 0, limit: 200).map((channel) => channel.channelNumber);
      expect(numbers.first, 1);
      expect(numbers.last, 200);
    },
  );

  test('a 50k-channel migration stays linear', () async {
    IptvCatalogDb.debugClose();
    final path = '${dir.path}/iptv_catalog.db';
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    _createV1Schema(path, rows: 50000);

    await IptvCatalogDb.open();
    final watch = Stopwatch()..start();
    await IptvCatalogDb.ensureMigrations();
    watch.stop();

    final snap = IptvCatalogDb.snapshot('big')!;
    expect(snap.channelCount, 50000);
    expect(snap.page(offset: 0, limit: 1).single.channelNumber, 1);
    expect(snap.page(offset: 49999, limit: 1).single.channelNumber, 50000);
    // Generous next to the ~50ms the joined form actually takes here, but far
    // under the 14s the quadratic form took — a rewrite that reintroduces the
    // correlated subquery fails this well before it reaches a TV.
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'backfill took ${watch.elapsedMilliseconds}ms',
    );
  });

  group('local numbering adoption', () {
    // A lineup with everything that makes numbering non-trivial: tvg-id rows,
    // rows that fall back to name+group, an exact duplicate pair, and VOD rows
    // interleaved so "live only, in catalog order" is actually exercised.
    List<IptvChannel> lineup() => [
      _ch(1, attributes: const {'tvg-id': 'bbc.uk'}),
      _ch(2, name: 'Sky', group: 'UK'),
      _ch(3, contentType: 'vod'),
      _ch(4, name: 'Sky', group: 'UK'),
      _ch(5, attributes: const {'tvg-id': 'itv.uk'}),
      _ch(6, name: 'No Group', group: null),
    ];

    List<int?> numbersOf(String catalogKey) => IptvCatalogDb.snapshot(
      catalogKey,
    )!.page(offset: 0, limit: 50).map((c) => c.channelNumber).toList();

    test('numbers a stored catalog exactly as an ingest would', () async {
      // 'stored' stands in for a catalog ingested before numbering existed:
      // rows on disk, no namespace. 'ingested' is the same lineup arriving
      // through the numbering-aware path.
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'stored',
        channels: lineup(),
      );
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'ingested',
        channels: lineup(),
        numberingSourceKey: 'provider-b',
      );

      await IptvCatalogDb.adoptNumbering(
        catalogKey: 'stored',
        sourceKey: 'provider-a',
      );

      expect(
        numbersOf('stored'),
        numbersOf('ingested'),
        reason:
            'adoption must agree with ingest, or numbers shift under the '
            'user on the next refresh',
      );
      // Live rows numbered in catalog order; the VOD row skipped entirely.
      expect(numbersOf('stored'), [1, 2, null, 3, 4, 5]);
    });

    test('registers the namespace so it never needs asking again', () async {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'stored',
        channels: lineup(),
      );
      expect(IptvCatalogDb.hasNumberingSource('provider-a'), isFalse);

      await IptvCatalogDb.adoptNumbering(
        catalogKey: 'stored',
        sourceKey: 'provider-a',
      );

      expect(IptvCatalogDb.hasNumberingSource('provider-a'), isTrue);
    });

    test('a second adoption corrects nothing and rewrites no rows', () async {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'stored',
        channels: lineup(),
      );
      final first = await IptvCatalogDb.adoptNumbering(
        catalogKey: 'stored',
        sourceKey: 'provider-a',
      );
      final second = await IptvCatalogDb.adoptNumbering(
        catalogKey: 'stored',
        sourceKey: 'provider-a',
      );

      expect(first, greaterThan(0));
      expect(
        second,
        0,
        reason:
            'a settled catalog must not rewrite rows — the caller uses '
            'this count to decide whether to rebuild the visible list',
      );
    });

    test(
      'existing namespace adopts rows made live by a classification fix',
      () async {
        IptvCatalogDb.ingest(
          dbPath: IptvCatalogDb.path,
          catalogKey: 'stored',
          numberingSourceKey: 'provider-a',
          channels: [
            _ch(1, attributes: const {'tvg-id': 'existing.live'}),
            _ch(
              2,
              contentType: null,
              duration: 5400,
              attributes: const {'tvg-id': 'newly.live'},
            ),
          ],
        );
        expect(IptvCatalogDb.hasNumberingSource('provider-a'), isTrue);

        // Shape of an already-migrated v2 catalog after EXTINF:0 becomes live:
        // the provider namespace and its old assignments exist, while this row
        // was stored as VOD with no number under the previous classifier.
        final db = raw.sqlite3.open(IptvCatalogDb.path);
        try {
          db.execute(
            'UPDATE channels SET duration = 0 WHERE catalog_key = ? AND url = ?',
            ['stored', 'http://h/live/u/p/2.ts'],
          );
        } finally {
          db.dispose();
        }

        var snap = IptvCatalogDb.snapshot('stored')!;
        expect(snap.hasUnnumberedLiveChannels, isTrue);
        expect(snap.page(offset: 0, limit: 10).map((c) => c.channelNumber), [
          1,
          null,
        ]);

        final corrected = await IptvCatalogDb.adoptNumbering(
          catalogKey: 'stored',
          sourceKey: 'provider-a',
        );

        expect(corrected, 1);
        snap = IptvCatalogDb.snapshot('stored')!;
        expect(snap.hasUnnumberedLiveChannels, isFalse);
        expect(
          snap.page(offset: 0, limit: 10).map((c) => c.channelNumber),
          [1, 2],
          reason: 'the old number stays stable and the newly-live row appends',
        );
      },
    );

    test('agrees with the v2 backfill, so nothing is rewritten', () async {
      IptvCatalogDb.debugClose();
      final path = '${dir.path}/iptv_catalog.db';
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      _createV1Schema(path, rows: 300);
      await IptvCatalogDb.open();
      await IptvCatalogDb.ensureMigrations();

      final corrected = await IptvCatalogDb.adoptNumbering(
        catalogKey: 'big',
        sourceKey: 'provider-a',
      );

      expect(
        corrected,
        0,
        reason:
            'the upgrade backfill and adoption both number live rows in '
            'catalog order — they must land on the same numbers',
      );
    });

    test('adopting an unknown catalog is a no-op', () async {
      expect(
        await IptvCatalogDb.adoptNumbering(
          catalogKey: 'missing',
          sourceKey: 'provider-a',
        ),
        0,
      );
      expect(IptvCatalogDb.hasNumberingSource('provider-a'), isFalse);
    });

    test('a failed adoption is backed off, and expires', () async {
      final db = raw.sqlite3.open(IptvCatalogDb.path);
      try {
        expect(IptvCatalogDb.adoptionRecentlyFailed('provider-a'), isFalse);

        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          "INSERT OR REPLACE INTO meta(key, value) VALUES "
          "('numbering_adopt_failed:provider-a', ?)",
          ['$now'],
        );
        expect(IptvCatalogDb.adoptionRecentlyFailed('provider-a'), isTrue);

        db.execute(
          "INSERT OR REPLACE INTO meta(key, value) VALUES "
          "('numbering_adopt_failed:provider-a', ?)",
          ['${now - const Duration(hours: 7).inMilliseconds}'],
        );
        expect(
          IptvCatalogDb.adoptionRecentlyFailed('provider-a'),
          isFalse,
          reason:
              'the backoff must expire, or a transient failure would '
              'strand the catalog unnumbered forever',
        );
      } finally {
        db.dispose();
      }
    });

    test('stores identity keys in the on-disk format', () async {
      // These strings are PERSISTED. Existing installs hold assignments keyed
      // by this exact format, so changing it (a different separator, prefix or
      // occurrence suffix) would make every stored key miss and silently
      // renumber the user's whole lineup on their next refresh. Pin it.
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'stored',
        channels: [
          _ch(1, attributes: const {'tvg-id': 'BBC.uk'}),
          _ch(2, name: 'Sky', group: 'UK'),
          _ch(3, name: 'Sky', group: 'UK'),
        ],
      );
      await IptvCatalogDb.adoptNumbering(
        catalogKey: 'stored',
        sourceKey: 'provider-a',
      );

      final db = raw.sqlite3.open(IptvCatalogDb.path);
      try {
        final keys = db
            .select(
              'SELECT identity_key FROM channel_number_assignments '
              'ORDER BY channel_number',
            )
            .map((row) => row['identity_key'] as String)
            .toList();
        expect(keys, [
          'tvg:bbc.uk\u001f1',
          'name:sky\u001fgroup:uk\u001f1',
          'name:sky\u001fgroup:uk\u001f2',
        ]);
      } finally {
        db.dispose();
      }
    });

    test('archiving a provider clears its adoption backoff', () async {
      final db = raw.sqlite3.open(IptvCatalogDb.path);
      try {
        db.execute(
          "INSERT OR REPLACE INTO meta(key, value) VALUES "
          "('numbering_adopt_failed:provider-a', ?)",
          ['${DateTime.now().millisecondsSinceEpoch}'],
        );
      } finally {
        db.dispose();
      }
      expect(IptvCatalogDb.adoptionRecentlyFailed('provider-a'), isTrue);

      await IptvCatalogDb.archiveNumberingSource('provider-a');

      expect(
        IptvCatalogDb.adoptionRecentlyFailed('provider-a'),
        isFalse,
        reason:
            'a re-added playlist must not inherit the backoff of the '
            'entry it replaced',
      );
    });

    test('a 50k catalog adopts without materializing it', () async {
      IptvCatalogDb.debugClose();
      final path = '${dir.path}/iptv_catalog.db';
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      _createV1Schema(path, rows: 50000);
      await IptvCatalogDb.open();
      await IptvCatalogDb.ensureMigrations();

      final watch = Stopwatch()..start();
      await IptvCatalogDb.adoptNumbering(
        catalogKey: 'big',
        sourceKey: 'provider-a',
      );
      watch.stop();

      expect(IptvCatalogDb.hasNumberingSource('provider-a'), isTrue);
      final snap = IptvCatalogDb.snapshot('big')!;
      expect(snap.page(offset: 0, limit: 1).single.channelNumber, 1);
      expect(snap.page(offset: 49999, limit: 1).single.channelNumber, 50000);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 20)),
        reason: 'adoption took ${watch.elapsedMilliseconds}ms',
      );
    });

    test('a 50k adoption holds identities, never the catalog', () async {
      IptvCatalogDb.debugClose();
      final path = '${dir.path}/iptv_catalog.db';
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) await file.delete();
      }
      _createV1Schema(path, rows: 50000);
      await IptvCatalogDb.open();
      await IptvCatalogDb.ensureMigrations();

      // Run in THIS isolate rather than through the compute() wrapper, so the
      // resident-set delta is the pass's own allocation and not a worker's
      // startup. Timing alone can't tell "streams the catalog" from
      // "materializes it" — this can.
      final db = raw.sqlite3.open(path);
      final before = ProcessInfo.currentRss;
      try {
        IptvCatalogDb.adoptNumberingFromCatalog(
          db,
          catalogKey: 'big',
          sourceKey: 'provider-a',
        );
      } finally {
        db.dispose();
      }
      final grewMb = (ProcessInfo.currentRss - before) / (1024 * 1024);

      // Generous — RSS is noisy and GC timing is not ours to control — but far
      // below what materializing 50k channel rows would take, which is the
      // regression worth catching.
      expect(
        grewMb,
        lessThan(150),
        reason: 'adoption grew RSS by ${grewMb.toStringAsFixed(1)}MB',
      );
      // ignore: avoid_print
      print('50k adoption RSS delta: ${grewMb.toStringAsFixed(1)}MB');
    });
  });

  group('global maintenance queue', () {
    test('overlapping callers never run at the same time', () async {
      // The page cannot cancel a departing instance's workers, so leaving and
      // reopening IPTV (or switching providers) starts a second pipeline while
      // the first is still going. Two whole-catalog scans at once is the
      // low-end-device overload this gate exists to prevent.
      var running = 0;
      var maxConcurrent = 0;
      final order = <String>[];

      Future<void> job(String label) => IptvCatalogDb.runExclusive(() async {
        running++;
        maxConcurrent = running > maxConcurrent ? running : maxConcurrent;
        order.add('start $label');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add('end $label');
        running--;
      });

      await Future.wait([job('a'), job('b'), job('c')]);

      expect(maxConcurrent, 1);
      expect(order, [
        'start a',
        'end a',
        'start b',
        'end b',
        'start c',
        'end c',
      ]);
      expect(IptvCatalogDb.debugMaintenanceRunCount, 3);
    });

    test('nested work runs inline instead of deadlocking', () async {
      // A coarse job (the settings refresh) legitimately contains a finer
      // gated one (catalog deletion). Without re-entrancy the inner call
      // would queue behind a slot its own caller is holding and never return.
      var inner = false;
      await IptvCatalogDb.runExclusive(() async {
        await IptvCatalogDb.runExclusive(() async {
          inner = true;
        }).timeout(const Duration(seconds: 5));
      });
      expect(inner, isTrue);
    });

    test(
      'deleting catalogs takes the gate and runs off this isolate',
      () async {
        IptvCatalogDb.ingest(
          dbPath: IptvCatalogDb.path,
          catalogKey: 'doomed',
          channels: [for (var i = 0; i < 10; i++) _ch(i)],
        );
        final before = IptvCatalogDb.debugMaintenanceRunCount;

        await IptvCatalogDb.removeCatalogsByKeys(['doomed']);

        expect(IptvCatalogDb.snapshot('doomed'), isNull);
        expect(
          IptvCatalogDb.debugMaintenanceRunCount,
          before + 1,
          reason:
              'a mass delete is whole-catalog write work and must queue '
              'with the rest',
        );
      },
    );

    test('a failed job does not break or poison the queue', () async {
      await expectLater(
        IptvCatalogDb.runExclusive(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );

      // The next job must still run, and must not inherit that error.
      var ran = false;
      await IptvCatalogDb.runExclusive(() async => ran = true);
      expect(ran, isTrue);
    });

    test('a queued duplicate finds the work already done', () async {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'stored',
        channels: [for (var i = 0; i < 20; i++) _ch(i)],
      );

      // Two pipelines racing for the same source, exactly as two page
      // instances would. Each re-checks inside the gate, so the second adopts
      // nothing rather than repeating a whole-catalog scan.
      final corrections = <int>[];
      Future<void> pipeline() => IptvCatalogDb.runExclusive(() async {
        if (IptvCatalogDb.hasNumberingSource('provider-a')) {
          corrections.add(-1); // skipped: already adopted
          return;
        }
        corrections.add(
          await IptvCatalogDb.adoptNumbering(
            catalogKey: 'stored',
            sourceKey: 'provider-a',
          ),
        );
      });

      await Future.wait([pipeline(), pipeline()]);

      expect(corrections.first, greaterThan(0));
      expect(
        corrections.last,
        -1,
        reason:
            'the second pipeline must not re-scan a catalog the first '
            'already adopted',
      );
    });
  });

  group('interrupted-refresh backoff', () {
    test('a refresh that never finished suppresses the next automatic one', () {
      expect(IptvCatalogDb.revalidateInterrupted('xc|s|u|live'), isFalse);

      // No matching markRevalidateFinished — this is a device that died
      // mid-refresh.
      IptvCatalogDb.markRevalidateStarted('xc|s|u|live');

      expect(
        IptvCatalogDb.revalidateInterrupted('xc|s|u|live'),
        isTrue,
        reason:
            'handing the same 50k refresh back on every visit is the loop '
            'that made the page unusable',
      );
    });

    test('a refresh that finished leaves nothing behind', () {
      IptvCatalogDb.markRevalidateStarted('xc|s|u|live');
      IptvCatalogDb.markRevalidateFinished('xc|s|u|live');
      expect(IptvCatalogDb.revalidateInterrupted('xc|s|u|live'), isFalse);
    });

    test('the suppression expires', () {
      final db = raw.sqlite3.open(IptvCatalogDb.path);
      try {
        db.execute(
          "INSERT OR REPLACE INTO meta(key, value) VALUES "
          "('catalog_revalidate_started:xc|s|u|live', ?)",
          [
            '${DateTime.now().millisecondsSinceEpoch - const Duration(hours: 7).inMilliseconds}',
          ],
        );
      } finally {
        db.dispose();
      }
      expect(
        IptvCatalogDb.revalidateInterrupted('xc|s|u|live'),
        isFalse,
        reason: 'a catalog must still be able to catch up eventually',
      );
    });

    test('markers are per catalog', () {
      IptvCatalogDb.markRevalidateStarted('xc|a|u|live');
      expect(IptvCatalogDb.revalidateInterrupted('xc|a|u|live'), isTrue);
      expect(IptvCatalogDb.revalidateInterrupted('xc|b|u|live'), isFalse);
    });
  });

  test('ingest does not carry the one-time migration', () async {
    IptvCatalogDb.debugClose();
    final path = '${dir.path}/iptv_catalog.db';
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    _createV1Schema(path, rows: 10);

    // An ordinary background refresh of an unrelated catalog must not drag a
    // whole-database upgrade along with it.
    IptvCatalogDb.ingest(
      dbPath: path,
      catalogKey: 'fresh',
      channels: [for (var i = 0; i < 3; i++) _ch(i)],
    );

    final db = raw.sqlite3.open(path);
    try {
      expect(db.select('PRAGMA user_version').first.values.first, 0);
      expect(
        db
            .select(
              "SELECT count(*) AS c FROM channels "
              "WHERE catalog_key = 'big' AND channel_number IS NOT NULL",
            )
            .first['c'],
        0,
      );
    } finally {
      db.dispose();
    }
  });

  test(
    'concurrent opens share one worker preparation and one handle',
    () async {
      IptvCatalogDb.debugClose();

      await Future.wait([
        IptvCatalogDb.open(),
        IptvCatalogDb.open(),
        IptvCatalogDb.open(),
      ]);

      expect(IptvCatalogDb.debugPreparationCount, 1);
      expect(IptvCatalogDb.isOpen, isTrue);
      expect(IptvCatalogDb.path, endsWith('iptv_catalog.db'));
    },
  );

  test(
    'a failed worker open clears the shared future so retry works',
    () async {
      IptvCatalogDb.debugClose();
      final notDirectory = File('${dir.path}/not-a-directory');
      await notDirectory.writeAsString('x');
      IptvCatalogDb.debugDirectoryOverride = notDirectory.path;

      await expectLater(IptvCatalogDb.open(), throwsA(isA<StateError>()));
      expect(IptvCatalogDb.isOpen, isFalse);

      IptvCatalogDb.debugDirectoryOverride = dir.path;
      await IptvCatalogDb.open();
      expect(IptvCatalogDb.isOpen, isTrue);
      expect(IptvCatalogDb.debugPreparationCount, 1);
    },
  );

  test('ingest → snapshot round-trips every channel field in order', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'xc|http://h|u|live',
      channels: [
        _ch(
          0,
          group: 'Спорт',
          name: 'Канал ᴴᴰ',
          attributes: {'stream_id': '7', 'tvg-id': 'ch7.tv'},
          headers: {'User-Agent': 'X'},
        ),
        _ch(1, group: 'News'),
      ],
      epgUrl: 'http://h/xmltv.php',
    );

    final snap = IptvCatalogDb.snapshot('xc|http://h|u|live')!;
    expect(snap.channelCount, 2);
    expect(snap.epgUrl, 'http://h/xmltv.php');

    final page = snap.page(offset: 0, limit: 10);
    expect(page.map((c) => c.name), ['Канал ᴴᴰ', 'Channel 1']);
    final c = page.first;
    expect(c.url, 'http://h/live/u/p/0.ts');
    expect(c.logoUrl, 'http://h/logo/0.png');
    expect(c.group, 'Спорт');
    expect(c.duration, -1);
    expect(c.contentType, 'live');
    expect(c.attributes, {'stream_id': '7', 'tvg-id': 'ch7.tv'});
    expect(c.httpHeaders, {'User-Agent': 'X'});
    expect(c.isLive, isTrue);
  });

  test('windowed pages walk the full catalog in provider order', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [for (var i = 0; i < 95; i++) _ch(i)],
    );
    final snap = IptvCatalogDb.snapshot('k')!;
    expect(snap.count(), 95);
    expect(snap.page(offset: 30, limit: 30).first.name, 'Channel 30');
    expect(snap.page(offset: 90, limit: 30).length, 5);
  });

  test('live-row check excludes VOD-only catalogs', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'vod-only',
      channels: [
        _ch(1, contentType: 'vod'),
        _ch(2, contentType: 'series'),
      ],
    );
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'mixed',
      channels: [
        _ch(1, contentType: 'vod'),
        _ch(2),
      ],
    );

    expect(IptvCatalogDb.snapshot('vod-only')!.hasLiveChannels, isFalse);
    expect(IptvCatalogDb.snapshot('mixed')!.hasLiveChannels, isTrue);
  });

  test('zero-duration M3U rows stay live through DB paging and EPG scan', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'm3u-zero',
      numberingSourceKey: 'm3u-zero-source',
      channels: [
        _ch(
          0,
          contentType: null,
          duration: 0,
          attributes: const {'tvg-id': 'awe.us', 'tvg-name': 'AWE'},
        ),
        _ch(
          1,
          contentType: null,
          duration: 5400,
          attributes: const {'tvg-id': 'movie.us'},
        ),
      ],
    );

    final snap = IptvCatalogDb.snapshot('m3u-zero')!;
    expect(snap.hasLiveChannels, isTrue);
    expect(snap.count(live: true), 1);
    expect(snap.count(live: false), 1);
    final live = snap.page(offset: 0, limit: 10, live: true).single;
    expect(live.tvgId, 'awe.us');
    expect(live.channelNumber, 1);

    final epgRows = IptvCatalogDb.liveTvgRows(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'm3u-zero',
    );
    expect(epgRows, hasLength(1));
    expect(epgRows.single.tvgId, 'awe.us');
    expect(epgRows.single.tvgName, 'AWE');
  });

  test('live channel numbers survive reorder and append new channels', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'provider-live',
      numberingSourceKey: 'provider-id',
      channels: [
        _ch(1, name: 'One', attributes: {'tvg-id': 'one'}),
        _ch(2, name: 'Two', attributes: {'tvg-id': 'two'}),
        _ch(3, name: 'Movie', contentType: 'vod'),
      ],
    );
    var snap = IptvCatalogDb.snapshot('provider-live')!;
    expect(IptvCatalogDb.hasNumberingSource('provider-id'), isTrue);
    expect(snap.page(offset: 0, limit: 10).map((c) => c.channelNumber), [
      1,
      2,
      null,
    ]);

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'provider-live',
      numberingSourceKey: 'provider-id',
      channels: [
        _ch(2, name: 'Two renamed', attributes: {'tvg-id': 'two'}),
        _ch(4, name: 'Four', attributes: {'tvg-id': 'four'}),
        _ch(1, name: 'One renamed', attributes: {'tvg-id': 'one'}),
      ],
    );
    snap = IptvCatalogDb.snapshot('provider-live')!;
    final page = snap.page(offset: 0, limit: 10);
    expect(page.map((c) => c.channelNumber), [2, 3, 1]);
    expect(snap.entryForChannelNumber(1)?.channel.name, 'One renamed');
    expect(snap.entryForChannelNumber(3)?.position, 1);
    expect(snap.entryForChannelNumber(99), isNull);
  });

  test('delete and re-add restores an archived matching lineup', () async {
    final original = [
      for (var i = 0; i < 25; i++) _ch(i, name: 'Station $i', group: 'Live'),
    ];
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'old-credentials',
      numberingSourceKey: 'old-playlist-id',
      channels: original,
    );
    await IptvCatalogDb.archiveNumberingSource('old-playlist-id');
    await IptvCatalogDb.removeCatalogsByKeys(['old-credentials']);

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'new-server-and-credentials',
      numberingSourceKey: 'new-playlist-id',
      channels: original.reversed.toList(),
    );
    final restored = IptvCatalogDb.snapshot('new-server-and-credentials')!;
    expect(restored.entryForChannelNumber(1)?.channel.name, 'Station 0');
    expect(restored.entryForChannelNumber(25)?.channel.name, 'Station 24');
  });

  test('an active identical provider keeps an independent namespace', () {
    final lineup = [
      for (var i = 0; i < 25; i++)
        _ch(i, name: 'Station $i', attributes: {'tvg-id': 'station-$i'}),
    ];
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'provider-a',
      numberingSourceKey: 'playlist-a',
      channels: lineup,
    );
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'provider-b',
      numberingSourceKey: 'playlist-b',
      channels: lineup.reversed.toList(),
    );
    final providerB = IptvCatalogDb.snapshot('provider-b')!;
    expect(
      providerB.entryForChannelNumber(1)?.channel.attributes['tvg-id'],
      'station-24',
    );
  });

  test('group filter and counts match the chip semantics', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(0, group: 'Sports'),
        _ch(1), // no group — the M3U no-group-title case
        _ch(2, group: 'News'),
        _ch(3, group: 'Sports'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;

    final groups = snap.groups();
    expect(
      [for (final g in groups) '${g.name}:${g.count}'],
      ['Sports:2', 'null:1', 'News:1'],
      reason: 'first-appearance order, null group preserved',
    );

    expect(snap.count(group: 'Sports'), 2);
    expect(snap.page(offset: 0, limit: 10, group: 'Sports').length, 2);
  });

  test('position lookup can stay inside the active zap category', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(7, group: 'News', name: 'Shared'),
        _ch(1, group: 'Sports'),
        _ch(7, group: 'Sports', name: 'Shared'),
        _ch(2, group: 'Sports'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;

    final position = snap.positionOf(
      url: 'http://h/live/u/p/7.ts',
      name: 'Shared',
      group: 'Sports',
      live: true,
    );
    expect(position, 2);
    expect(
      snap.count(group: 'Sports', live: true, beforePosition: position),
      1,
      reason: 'the centered page uses the channel ordinal within its category',
    );
  });

  test(
    'manual category order survives refresh and drives paging arithmetic',
    () async {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'ordered',
        channels: [
          _ch(1, group: 'Sports', name: 'Alpha'),
          _ch(9, group: 'News', name: 'News'),
          _ch(2, group: 'Sports', name: 'Bravo'),
          _ch(3, group: 'Sports', name: 'Charlie'),
        ],
      );
      final first = IptvCatalogDb.snapshot('ordered')!;
      final identities = {
        for (final entry in first.groupOrderEntries('Sports'))
          entry.channel.name: entry.identity,
      };
      expect(
        await IptvCatalogDb.setGroupChannelOrder('ordered', 'Sports', [
          identities['Charlie']!,
          identities['Alpha']!,
          identities['Bravo']!,
        ]),
        isTrue,
      );
      expect(
        IptvCatalogDb.snapshot('ordered')!
            .page(offset: 0, limit: 10, group: 'Sports')
            .map((channel) => channel.name),
        ['Charlie', 'Alpha', 'Bravo'],
      );
      final pagePlan = IptvCatalogDb.snapshot(
        'ordered',
      )!.debugPageQueryPlan(group: 'Sports').join('\n');
      expect(pagePlan, contains('idx_channels_grp_manual'));
      expect(
        pagePlan,
        isNot(contains('USE TEMP B-TREE FOR ORDER BY')),
        reason: 'every page fault must stream the manual-order index',
      );
      final beforeRead = IptvCatalogDb.debugMaintenanceRunCount;
      final orderEntries = await IptvCatalogDb.groupOrderEntriesAsync(
        IptvCatalogDb.snapshot('ordered')!,
        'Sports',
      );
      expect(
        orderEntries.map((entry) => entry.channel.name),
        ['Charlie', 'Alpha', 'Bravo'],
        reason: 'the settings loader decodes complete categories off-isolate',
      );
      expect(
        IptvCatalogDb.debugMaintenanceRunCount,
        beforeRead + 1,
        reason: 'the durable editor scan must share the refresh gate',
      );

      // Settings refresh deletes the published catalog before ingesting it
      // again. The identity table intentionally survives that deletion.
      await IptvCatalogDb.removeCatalogsByKeys(['ordered']);
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'ordered',
        channels: [
          _ch(2, group: 'Sports', name: 'Bravo'),
          _ch(9, group: 'News', name: 'News'),
          _ch(4, group: 'Sports', name: 'Delta'),
          _ch(1, group: 'Sports', name: 'Alpha'),
          _ch(3, group: 'Sports', name: 'Charlie'),
        ],
      );
      final refreshed = IptvCatalogDb.snapshot('ordered')!;
      expect(
        refreshed
            .page(offset: 0, limit: 10, group: 'Sports')
            .map((channel) => channel.name),
        ['Charlie', 'Alpha', 'Bravo', 'Delta'],
        reason: 'known identities retain their ranks and a new row appends',
      );
      expect(
        refreshed.page(offset: 0, limit: 10).map((channel) => channel.name),
        ['Bravo', 'News', 'Delta', 'Alpha', 'Charlie'],
        reason: 'the All view keeps the provider baseline',
      );

      final alphaPosition = refreshed.positionOf(
        url: 'http://h/live/u/p/1.ts',
        name: 'Alpha',
        group: 'Sports',
      )!;
      final charliePosition = refreshed.positionOf(
        url: 'http://h/live/u/p/3.ts',
        name: 'Charlie',
        group: 'Sports',
      )!;
      expect(
        refreshed.count(group: 'Sports', beforePosition: charliePosition),
        0,
      );
      expect(
        refreshed.count(group: 'Sports', beforePosition: alphaPosition),
        1,
        reason: 'position→index conversion follows manual display order',
      );

      await IptvCatalogDb.removeCatalogsByKeys([
        'ordered',
      ], forgetChannelOrders: true);
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'ordered',
        channels: [
          _ch(2, group: 'Sports', name: 'Bravo'),
          _ch(9, group: 'News', name: 'News'),
          _ch(4, group: 'Sports', name: 'Delta'),
          _ch(1, group: 'Sports', name: 'Alpha'),
          _ch(3, group: 'Sports', name: 'Charlie'),
        ],
      );
      expect(
        IptvCatalogDb.snapshot('ordered')!
            .page(offset: 0, limit: 10, group: 'Sports')
            .map((channel) => channel.name),
        ['Bravo', 'Delta', 'Alpha', 'Charlie'],
        reason: 'source deletion removes ranks instead of preserving refresh',
      );
    },
  );

  test(
    'category-list order survives refresh and app reopen, then forgets on delete',
    () async {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'category-list',
        channels: [
          _ch(1, group: 'News'),
          _ch(2, group: 'Sports'),
          _ch(3, group: 'Kids'),
        ],
        categories: const ['News', 'Sports', 'Kids'],
      );

      await IptvCatalogDb.setCategoryOrder('category-list', const [
        'Kids',
        'News',
        'Sports',
      ]);
      expect(IptvCatalogDb.savedCategoryOrder('category-list'), [
        'Kids',
        'News',
        'Sports',
      ]);
      var sidecar = raw.sqlite3.open(IptvCatalogDb.path);
      var orderState = sidecar.select(
        'SELECT deleted, origin_device_id FROM webdav_sync_record_state '
        'WHERE kind = ? AND owner_key = ?',
        [WebDavSyncLibraryKinds.categoryManualOrders, 'category-list'],
      ).single;
      expect(orderState['deleted'], 0);
      expect(orderState['origin_device_id'], 'local-device');
      sidecar.dispose();
      expect(
        IptvCatalogDb.applyCategoryOrder('category-list', const [
          'News',
          'Movies',
          'Sports',
          'Kids',
        ]),
        ['Kids', 'News', 'Sports', 'Movies'],
        reason: 'new provider categories append after every saved rank',
      );
      expect(
        IptvCatalogDb.applyCategoryOrder('category-list', const [
          'News',
          'Kids',
        ]),
        ['Kids', 'News'],
        reason: 'filtering hidden categories does not disturb saved ranks',
      );

      await IptvCatalogDb.removeCatalogsByKeys(['category-list']);
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'category-list',
        channels: [
          _ch(2, group: 'Sports'),
          _ch(4, group: 'Movies'),
          _ch(1, group: 'News'),
          _ch(3, group: 'Kids'),
        ],
        categories: const ['Sports', 'Movies', 'News', 'Kids'],
      );
      expect(
        IptvCatalogDb.applyCategoryOrder(
          'category-list',
          IptvCatalogDb.snapshot('category-list')!.categories,
        ),
        ['Kids', 'News', 'Sports', 'Movies'],
        reason: 'ordinary catalog refresh preserves category-list ranks',
      );

      IptvCatalogDb.debugClose();
      await IptvCatalogDb.open();
      expect(IptvCatalogDb.savedCategoryOrder('category-list'), [
        'Kids',
        'News',
        'Sports',
      ]);

      await IptvCatalogDb.removeCatalogsByKeys([
        'category-list',
      ], forgetChannelOrders: true);
      expect(IptvCatalogDb.savedCategoryOrder('category-list'), isEmpty);
      sidecar = raw.sqlite3.open(IptvCatalogDb.path);
      orderState = sidecar.select(
        'SELECT deleted, origin_device_id FROM webdav_sync_record_state '
        'WHERE kind = ? AND owner_key = ?',
        [WebDavSyncLibraryKinds.categoryManualOrders, 'category-list'],
      ).single;
      expect(orderState['deleted'], 1);
      expect(orderState['origin_device_id'], 'local-device');
      expect(
        sidecar
            .select(
              "SELECT value FROM webdav_sync_meta "
              "WHERE key = 'mutation_revision'",
            )
            .single['value'],
        '2',
      );
      sidecar.dispose();
    },
  );

  test('forgetting category order reopens a closed catalog', () async {
    await IptvCatalogDb.setCategoryOrder('local|removed', const [
      'Kids',
      'News',
    ]);
    await IptvCatalogDb.closeScope();
    expect(IptvCatalogDb.isOpen, isFalse);

    await IptvCatalogDb.forgetCategoryOrders(['local|removed']);

    expect(IptvCatalogDb.isOpen, isTrue);
    expect(IptvCatalogDb.savedCategoryOrder('local|removed'), isEmpty);
  });

  test('default landing category round-trips, overwrites and clears', () {
    expect(IptvCatalogDb.defaultCategory('m3u|http://a'), isNull);

    expect(IptvCatalogDb.setDefaultCategory('m3u|http://a', 'Sports'), isTrue);
    expect(IptvCatalogDb.defaultCategory('m3u|http://a'), 'Sports');

    expect(IptvCatalogDb.setDefaultCategory('m3u|http://a', 'News'), isTrue);
    expect(IptvCatalogDb.defaultCategory('m3u|http://a'), 'News');

    expect(IptvCatalogDb.setDefaultCategory('m3u|http://a', null), isTrue);
    expect(IptvCatalogDb.defaultCategory('m3u|http://a'), isNull);
  });

  test('default landing category is keyed per catalog', () {
    IptvCatalogDb.setDefaultCategory('xc|p|u|live', 'Sports');
    IptvCatalogDb.setDefaultCategory('xc|p|u|vod', 'Movies');

    expect(IptvCatalogDb.defaultCategory('xc|p|u|live'), 'Sports');
    expect(IptvCatalogDb.defaultCategory('xc|p|u|vod'), 'Movies');
    expect(IptvCatalogDb.defaultCategory('m3u|http://other'), isNull);
  });

  test('default landing category survives ordinary catalog refresh', () async {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'xc|p|u|live',
      channels: [_ch(1, group: 'Sports')],
    );
    IptvCatalogDb.setDefaultCategory('xc|p|u|live', 'Sports');

    await IptvCatalogDb.removeCatalogsByKeys(['xc|p|u|live']);

    expect(IptvCatalogDb.defaultCategory('xc|p|u|live'), 'Sports');
  });

  test(
    'default landing category is forgotten with removed source state',
    () async {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'xc|p|u|live',
        channels: [_ch(1, group: 'Sports')],
      );
      IptvCatalogDb.setDefaultCategory('xc|p|u|live', 'Sports');

      await IptvCatalogDb.removeCatalogsByKeys([
        'xc|p|u|live',
      ], forgetChannelOrders: true);

      expect(IptvCatalogDb.defaultCategory('xc|p|u|live'), isNull);
    },
  );

  group('landing category seed', () {
    const key = 'm3u|http://seed';
    const categories = ['Kids', 'News', 'Sports'];

    String? seed({
      String? orderKey = key,
      List<String> cats = categories,
      bool manuallyChosen = false,
      bool searching = false,
    }) => IptvResultsViewState.landingCategoryFor(
      orderKey: orderKey,
      categories: cats,
      manuallyChosen: manuallyChosen,
      searching: searching,
    );

    test('falls back to the first category in display order', () {
      expect(seed(), 'Kids');
    });

    test('prefers the stored default while it still exists', () {
      IptvCatalogDb.setDefaultCategory(key, 'Sports');
      expect(seed(), 'Sports');

      // A default the provider removed (or the user hid) is skipped, not an
      // error — the visible list wins.
      expect(seed(cats: ['Kids', 'News']), 'Kids');
    });

    test('never overrides an explicit pick, a search, or a keyless source', () {
      IptvCatalogDb.setDefaultCategory(key, 'Sports');
      expect(seed(manuallyChosen: true), isNull);
      expect(seed(searching: true), isNull);
      expect(seed(orderKey: null), isNull);
      expect(seed(cats: const []), isNull);
    });
  });

  test('Xtream manual order survives password URL and name changes', () async {
    IptvChannel xtream(String streamId, String password, String name) =>
        IptvChannel(
          name: name,
          url: 'http://panel/live/user/$password/$streamId.ts',
          group: 'Live',
          duration: -1,
          contentType: 'live',
          attributes: {'stream_id': streamId},
        );

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'xc|panel|user|live',
      channels: [
        xtream('1', 'old-password', 'One'),
        xtream('2', 'old-password', 'Two'),
      ],
    );
    final entries = IptvCatalogDb.snapshot(
      'xc|panel|user|live',
    )!.groupOrderEntries('Live');
    await IptvCatalogDb.setGroupChannelOrder('xc|panel|user|live', 'Live', [
      entries[1].identity,
      entries[0].identity,
    ]);

    await IptvCatalogDb.removeCatalogsByKeys(['xc|panel|user|live']);
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'xc|panel|user|live',
      channels: [
        xtream('1', 'new-password', 'One renamed'),
        xtream('2', 'new-password', 'Two'),
      ],
    );

    expect(
      IptvCatalogDb.snapshot('xc|panel|user|live')!
          .page(offset: 0, limit: 10, group: 'Live')
          .map((channel) => channel.name),
      ['Two', 'One renamed'],
    );
  });

  test('search matches name and group, case-insensitively, as substrings', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(0, name: 'Sky Sports Main Event', group: 'UK'),
        _ch(1, name: 'CNN', group: 'News USA'),
        _ch(2, name: 'BBC One', group: 'UK'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;

    expect(
      snap.page(offset: 0, limit: 10, search: 'sport').single.name,
      'Sky Sports Main Event',
    );
    expect(
      snap.page(offset: 0, limit: 10, search: 'usa').single.name,
      'CNN',
      reason: 'the group is part of the search haystack, as today',
    );
    expect(snap.count(search: 'PORT'), 1, reason: 'mid-word substring match');
    expect(snap.count(search: 'zzz'), 0);
  });

  test('LIKE metacharacters in the query match literally', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [
        _ch(0, name: '100% Hits'),
        _ch(1, name: 'Plain'),
      ],
    );
    final snap = IptvCatalogDb.snapshot('k')!;
    expect(
      snap.count(search: '100%'),
      1,
      reason: '"%" must not act as a wildcard',
    );
    expect(snap.count(search: '0% h'), 1);
    expect(
      snap.count(search: '_'),
      0,
      reason: '"_" must not match arbitrary characters',
    );
  });

  test('re-ingest swaps generations atomically and staleness is visible', () {
    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [_ch(0), _ch(1), _ch(2)],
    );
    final old = IptvCatalogDb.snapshot('k')!;
    expect(old.isStale, isFalse);

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [_ch(10), _ch(11)],
    );

    expect(old.isStale, isTrue);
    expect(
      old.count(),
      3,
      reason:
          'the previous generation survives ONE refresh — the UI may '
          'still be scrolled through it while the commit lands',
    );
    expect(old.page(offset: 0, limit: 10).first.name, 'Channel 0');

    final fresh = IptvCatalogDb.snapshot('k')!;
    expect(fresh.channelCount, 2);
    expect(fresh.page(offset: 0, limit: 10).map((c) => c.name), [
      'Channel 10',
      'Channel 11',
    ]);

    IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: [_ch(20)],
    );
    expect(
      old.count(),
      0,
      reason: 'two refreshes later the first generation is finally swept',
    );
    expect(fresh.count(), 2, reason: 'the second is now the retained one');
  });

  test('content digest is order-sensitive and field-sensitive', () {
    final a = [_ch(0), _ch(1)];
    final same = [_ch(0), _ch(1)];
    final reordered = [_ch(1), _ch(0)];
    final renamed = [_ch(0), _ch(1, name: 'Renamed')];

    expect(IptvCatalogDb.contentDigest(a), IptvCatalogDb.contentDigest(same));
    expect(
      IptvCatalogDb.contentDigest(a),
      isNot(IptvCatalogDb.contentDigest(reordered)),
    );
    expect(
      IptvCatalogDb.contentDigest(a),
      isNot(IptvCatalogDb.contentDigest(renamed)),
    );
  });

  test('ingest reports the digest of what it wrote; unchanged re-ingest '
      'produces the stored digest', () {
    final channels = [_ch(0), _ch(1)];
    final digest = IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: channels,
    );
    expect(IptvCatalogDb.snapshot('k')!.contentDigest, digest);

    final again = IptvCatalogDb.ingest(
      dbPath: IptvCatalogDb.path,
      catalogKey: 'k',
      channels: channels,
    );
    expect(
      again,
      digest,
      reason: 'the revalidate path compares digests to decide "Up to date"',
    );
  });

  test('removeCatalogs deletes only the named catalogs', () async {
    for (final key in ['xc|s|u|live', 'xc|s|u|vod', 'm3u|http://other']) {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: key,
        channels: [_ch(0)],
      );
    }

    // A refresh that never finished, on one of the doomed catalogs and on the
    // survivor: deletion must take the deleted catalog's bookkeeping with it,
    // or a delete-and-re-add inside the backoff window would inherit the old
    // entry's suppressed refresh.
    IptvCatalogDb.markRevalidateStarted('xc|s|u|live');
    IptvCatalogDb.markRevalidateStarted('m3u|http://other');

    await IptvCatalogDb.removeCatalogsByKeys(['xc|s|u|live', 'xc|s|u|vod']);

    expect(IptvCatalogDb.snapshot('xc|s|u|live'), isNull);
    expect(IptvCatalogDb.snapshot('xc|s|u|vod'), isNull);
    expect(IptvCatalogDb.snapshot('m3u|http://other')!.channelCount, 1);

    expect(IptvCatalogDb.revalidateInterrupted('xc|s|u|live'), isFalse);
    expect(
      IptvCatalogDb.revalidateInterrupted('m3u|http://other'),
      isTrue,
      reason: 'a surviving catalog keeps its own marker',
    );
  });

  group('live-filter + zap-window queries', () {
    setUp(() {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'k',
        channels: [
          _ch(0, name: 'Sky Sports F1', group: 'Sports'),
          IptvChannel(
            name: 'Sky Movies',
            url: 'http://h/movie/u/p/9.mp4',
            contentType: 'vod',
          ),
          _ch(2, name: 'CNN Sky News', group: 'News'),
          IptvChannel(
            name: 'Old Film',
            url: 'http://h/movie/u/p/10.mp4',
            // no contentType — M3U row; a real duration means on-demand
            duration: 5400,
          ),
        ],
      );
    });

    test('live bucketing matches IptvChannel.isLive exactly', () {
      final snap = IptvCatalogDb.snapshot('k')!;
      expect(
        snap.count(live: true),
        2,
        reason: 'explicit live + the duration-less M3U heuristic',
      );
      expect(
        snap.count(live: false),
        2,
        reason: 'explicit vod + the real-duration M3U row',
      );
    });

    test('positionOf + beforePosition rebuild a zap window', () {
      final snap = IptvCatalogDb.snapshot('k')!;
      final pos = snap.positionOf(
        url: 'http://h/live/u/p/2.ts',
        name: 'CNN Sky News',
        group: 'News',
        live: true,
      )!;
      expect(
        snap.count(live: true, beforePosition: pos),
        1,
        reason: 'one live row precedes it, so it is live index 1',
      );
      final window = snap.page(offset: 0, limit: 10, live: true);
      expect(window[1].name, 'CNN Sky News');
      expect(
        snap.positionOf(
          url: 'http://h/live/u/p/2.ts',
          name: 'CNN Sky News',
          group: 'Sports',
          live: true,
        ),
        isNull,
        reason: 'the search result must anchor inside its selected category',
      );
    });
  });

  group('EPG guide storage', () {
    test('ingest → info + programme rows round-trip; re-ingest replaces', () {
      IptvCatalogDb.ingestEpgGuide(
        dbPath: IptvCatalogDb.path,
        guideKey: 'g1',
        epgUrl: 'http://h/xmltv.php',
        byId: {
          'bbcone.uk': [
            [1000, 2000, 'News', 'The news'],
            [2000, 3000, 'Weather', ''],
          ],
          'itv.uk': [
            [1500, 2500, 'Drama', 'A drama'],
          ],
        },
        nameToId: {'bbcone': 'bbcone.uk'},
        sawWanted: true,
      );

      final info = IptvCatalogDb.epgGuideInfo('g1')!;
      expect(info.channelCount, 2);
      expect(info.sawWanted, isTrue);
      expect(info.nameToId, {'bbcone': 'bbcone.uk'});

      final rows = IptvCatalogDb.epgProgrammes('g1', 'bbcone.uk');
      expect(rows, [
        [1000, 2000, 'News', 'The news'],
        [2000, 3000, 'Weather', ''],
      ]);
      expect(IptvCatalogDb.epgProgrammes('g1', 'nope'), isEmpty);

      IptvCatalogDb.ingestEpgGuide(
        dbPath: IptvCatalogDb.path,
        guideKey: 'g1',
        epgUrl: 'http://h/xmltv.php',
        byId: {
          'bbcone.uk': [
            [5000, 6000, 'Replaced', ''],
          ],
        },
        nameToId: const {},
        sawWanted: true,
      );
      expect(IptvCatalogDb.epgProgrammes('g1', 'bbcone.uk'), [
        [5000, 6000, 'Replaced', ''],
      ]);
      expect(
        IptvCatalogDb.epgProgrammes('g1', 'itv.uk'),
        isEmpty,
        reason: 'a re-ingest fully replaces the guide',
      );
    });

    test('markEpgGuideEmpty writes only metadata (negative cache)', () {
      IptvCatalogDb.markEpgGuideEmpty(
        guideKey: 'g2',
        epgUrl: 'http://h/xmltv.php',
        sawWanted: false,
      );
      final info = IptvCatalogDb.epgGuideInfo('g2')!;
      expect(info.channelCount, 0);
      expect(info.sawWanted, isFalse);
    });

    test(
      'channelTvgIdentity resolves a URL against the current generation',
      () {
        IptvCatalogDb.ingest(
          dbPath: IptvCatalogDb.path,
          catalogKey: 'cat',
          channels: [
            _ch(
              0,
              name: 'BBC One ᴴᴰ',
              attributes: {'tvg-id': 'BBCOne.uk', 'tvg-name': 'BBC One'},
            ),
          ],
        );
        final identity = IptvCatalogDb.channelTvgIdentity(
          catalogKey: 'cat',
          url: 'http://h/live/u/p/0.ts',
        )!;
        expect(identity.name, 'BBC One ᴴᴰ');
        expect(identity.attributes['tvg-id'], 'BBCOne.uk');
        expect(
          IptvCatalogDb.channelTvgIdentity(catalogKey: 'cat', url: 'http://x'),
          isNull,
        );
      },
    );
  });

  test('ingest from a worker isolate is read back on this one', () async {
    final written = await compute(_ingestInWorker, <Object>[
      IptvCatalogDb.path,
      'worker|k',
    ]);
    final snap = IptvCatalogDb.snapshot('worker|k')!;
    expect(snap.channelCount, written);
    expect(snap.count(group: 'G3'), 100);
    expect(snap.page(offset: 499, limit: 1).single.name, 'Channel 499');
  });
}
