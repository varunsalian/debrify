import 'dart:io';

import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Every table the real catalog schema creates must be classified as durable
/// or rebuildable, or manual local backups fail with "not classified". This
/// binds the allowlist in [ProfileDatabaseSnapshot] to the live schema so a
/// new migration cannot silently break local backups while the suite stays
/// green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('iptv-catalog-classify-');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
  });

  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    await dir.delete(recursive: true);
  });

  test('every real iptv_catalog.db table is classified for local backup', () {
    final db = raw.sqlite3.open(
      IptvCatalogDb.path,
      mode: raw.OpenMode.readOnly,
    );
    try {
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .where((name) => !name.startsWith('sqlite_'))
          .where((name) => name != 'android_metadata')
          .toSet();
      expect(tables, isNotEmpty);
      final classified = <String>{
        ...ProfileDatabaseSnapshot.durableCatalogTables,
        ...ProfileDatabaseSnapshot.rebuildableCatalogTables,
      };
      final unclassified = tables.difference(classified).toList()..sort();
      expect(
        unclassified,
        isEmpty,
        reason:
            'Add each table to durableCatalogTables or '
            'rebuildableCatalogTables in profile_database_snapshot.dart',
      );
      final stale = classified.difference(tables).toList()..sort();
      expect(
        stale,
        isEmpty,
        reason: 'Classified tables no longer exist in the schema',
      );
      expect(
        ProfileDatabaseSnapshot.durableCatalogTables.intersection(
          ProfileDatabaseSnapshot.rebuildableCatalogTables,
        ),
        isEmpty,
      );
    } finally {
      db.dispose();
    }
  });
}
