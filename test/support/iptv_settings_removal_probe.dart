import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'iptv_settings_fixture.dart';

Future<void> seedRemovalProbe(IptvSettingsFixture f) async {
  final target = f.playlists.first;
  final key = IptvCatalogKey.forPlaylist(target, 'live') ?? 'numbering-probe';
  await IptvCatalogDb.ingestM3uLines(
    dbPath: IptvCatalogDb.path,
    catalogKey: key,
    lines: Stream.fromIterable(iptvFixtureM3u.split('\n')),
    numberingSourceKey: target.id,
  );
  await IptvFavoritesStorage.setIptvCategoryChannelOrder(target.id, 'News', [
    const IptvChannelOrderIdentity(
      url: 'https://fixture.invalid/live.ts',
      name: 'Café',
      occurrence: 0,
    ),
  ]);
}

Future<Map<String, Object?>> removalProbeState(String sourceId) async {
  final db = sqlite3.open(IptvCatalogDb.path);
  try {
    final alias = db.select(
      'SELECT is_active, namespace_id FROM channel_number_aliases WHERE source_key = ?',
      [sourceId],
    ).single;
    final namespace = db.select(
      'SELECT active_source_key FROM channel_number_namespaces WHERE namespace_id = ?',
      [alias['namespace_id']],
    ).single;
    final assignments = db.select(
      'SELECT identity_key, channel_number FROM channel_number_assignments WHERE namespace_id = ? ORDER BY identity_key',
      [alias['namespace_id']],
    );
    final media = await DebrifyTvDatabase.instance.database;
    return {
      'active': alias['is_active'],
      'activeSource': namespace['active_source_key'],
      'assignments': assignments
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
      'categoryOrders': (await media.query(
        'iptv_category_channel_orders',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      )).length,
      'memberships': (await media.query(
        'iptv_list_channels',
        where: 'playlist_id = ?',
        whereArgs: [sourceId],
      )).length,
      'history': (await IptvHistoryStorage.getIptvWatchHistory()).length,
    };
  } finally {
    db.dispose();
  }
}

void assertArchivedNumbering(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  expect(before['active'], 1);
  expect(before['activeSource'], isNotNull);
  expect(before['assignments'], isNotEmpty);
  expect(after['active'], 0);
  expect(after['activeSource'], isNull);
  expect(after['assignments'], before['assignments']);
}

Future<void> installRemovalFailure(String boundary) async {
  if (boundary == 'catalog' || boundary == 'local-category') {
    final db = sqlite3.open(IptvCatalogDb.path);
    try {
      final table = boundary == 'catalog'
          ? 'catalogs'
          : 'category_manual_orders';
      db.execute(
        "CREATE TRIGGER removal_probe_failure BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT, 'removal probe $boundary'); END",
      );
    } finally {
      db.dispose();
    }
  } else {
    final db = await DebrifyTvDatabase.instance.database;
    final table = switch (boundary) {
      'media-category' => 'iptv_category_channel_orders',
      'favorites' => 'iptv_list_channels',
      'history' => 'iptv_watch_history',
      _ => throw ArgumentError(boundary),
    };
    await db.execute(
      "CREATE TRIGGER removal_probe_failure BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT, 'removal probe $boundary'); END",
    );
  }
}
