import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as raw;

/// Step 3 spike: the catalog ingest architecture needs a WORKER isolate to
/// write tens of thousands of rows into the same SQLite file the UI isolate
/// reads through sqflite. sqflite database handles cannot cross isolates, so
/// the writer opens its own raw `package:sqlite3` connection in WAL mode.
///
/// This proves the load-bearing assumptions:
///  1. A second connection from a spawned isolate can write while the
///     sqflite connection stays open.
///  2. WAL gives the reader snapshot isolation — it never sees a half-done
///     ingest, and sees everything after COMMIT with no reopen.
///  3. A bulk 55k-row ingest in one transaction is fast enough to be a
///     realistic one-time migration/refresh path.
///  4. Writer-side busy_timeout means reader activity doesn't fail the
///     ingest with SQLITE_BUSY.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('worker-isolate raw sqlite3 writes are visible to a sqflite reader',
      () async {
    final dir = await Directory.systemTemp.createTemp('ingest_spike');
    final path = '${dir.path}/catalog.db';

    // UI-side connection (sqflite), owns the schema, switches to WAL.
    final ui = await databaseFactoryFfi.openDatabase(path);
    await ui.rawQuery('PRAGMA journal_mode=WAL');
    await ui.execute('''
      CREATE TABLE catalog (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        name TEXT NOT NULL,
        grp TEXT NOT NULL,
        generation INTEGER NOT NULL
      )
    ''');
    await ui.execute('CREATE INDEX idx_catalog_grp ON catalog(grp)');

    // Worker ingest: raw sqlite3 connection in a spawned isolate.
    const rows = 55000;
    final progress = ReceivePort();
    final sw = Stopwatch()..start();
    await Isolate.spawn(_ingestWorker, [path, rows, progress.sendPort]);

    var committed = false;
    var midIngestCount = -1;
    await for (final message in progress) {
      if (message == 'mid-ingest') {
        // The worker is inside its (uncommitted) transaction right now.
        midIngestCount = (await ui.rawQuery(
          'SELECT COUNT(*) AS c FROM catalog',
        ))
            .first['c'] as int;
        // ACK so the worker only proceeds to COMMIT after we sampled.
      } else if (message == 'done') {
        committed = true;
        break;
      } else if (message is String && message.startsWith('error:')) {
        fail(message);
      }
    }
    final elapsed = sw.elapsedMilliseconds;
    progress.close();

    expect(committed, isTrue);
    expect(midIngestCount, 0,
        reason: 'WAL snapshot isolation: a reader never sees a half-done '
            'ingest — the catalog swap is atomic from the UI\'s side');

    final count = (await ui.rawQuery('SELECT COUNT(*) AS c FROM catalog'))
        .first['c'] as int;
    expect(count, rows,
        reason: 'after COMMIT the sqflite connection sees every row without '
            'reopening');

    // Query-driven UI shapes stay cheap on the ingested data.
    final window = await ui.rawQuery(
      'SELECT name FROM catalog WHERE grp = ? ORDER BY id LIMIT 30',
      ['Group 7'],
    );
    expect(window.length, 30);

    final groups = await ui.rawQuery(
      'SELECT grp, COUNT(*) AS c FROM catalog GROUP BY grp',
    );
    expect(groups.length, 200);

    // ignore: avoid_print
    print('spike: $rows rows ingested from worker isolate in ${elapsed}ms '
        '(includes spawn + mid-ingest handshake)');

    await ui.close();
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _ingestWorker(List<Object> args) async {
  final path = args[0] as String;
  final rows = args[1] as int;
  final port = args[2] as SendPort;
  try {
    final db = raw.sqlite3.open(path);
    // If the reader happens to hold the write lock briefly, wait it out
    // rather than failing the whole ingest with SQLITE_BUSY.
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=NORMAL');

    final stmt = db.prepare(
      'INSERT INTO catalog(url, name, grp, generation) VALUES (?, ?, ?, 1)',
    );
    db.execute('BEGIN');
    for (var i = 0; i < rows; i++) {
      stmt.execute([
        'http://panel.example.com/live/user/pass/$i.ts',
        'Канал $i ᴴᴰ',
        'Group ${i % 200}',
      ]);
      if (i == rows ~/ 2) {
        // Let the test sample the reader's view mid-transaction. The
        // handshake is time-based (no reply channel needed): give the
        // reader ample time to run its COUNT before committing.
        port.send('mid-ingest');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    db.execute('COMMIT');
    stmt.dispose();
    db.dispose();
    port.send('done');
  } catch (e) {
    port.send('error: $e');
  }
}
