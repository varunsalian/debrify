import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';

/// Coverage for the IPTV favorites URL migration.
///
/// It rewrites stored favorite URLs in place when a freshly fetched channel
/// matches an existing favorite canonically but not literally (e.g. stars
/// saved before the Xtream `/live/` URL fix). That makes it a destructive
/// edit of user data, and it runs on every catalog load — including the
/// background revalidate, while the page is on screen and the user can be
/// starring things. The scan yields to the event loop to keep a 50k-channel
/// playlist from freezing the UI, so "someone else wrote to the store while
/// we were scanning" is a real, reachable interleaving rather than a thought
/// experiment.
///
/// Favorites live in debrify_tv.db; seeding through the legacy prefs key also
/// exercises the one-time prefs→DB import on every test.
void main() {
  const legacyKey = 'iptv_favorite_channels_v1';

  Future<Map<String, Map<String, dynamic>>> readFavorites() =>
      StorageService.getIptvFavoriteChannels();

  Future<void> seed(Map<String, dynamic> value) async {
    SharedPreferences.setMockInitialValues({legacyKey: jsonEncode(value)});
  }

  IptvChannel channel(String url, {String name = 'Ch'}) =>
      IptvChannel(name: name, url: url);

  /// A list long enough that the scan actually yields (the budget is time
  /// based, so this is generous on purpose) and whose rows all pass the host
  /// pre-filter, keeping the migration candidate alive to the end.
  List<IptvChannel> filler(String host, int count) => [
        for (var i = 0; i < count; i++)
          channel('http://$host/live/u/p/${900000 + i}.ts', name: 'Filler $i'),
      ];

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride =
        await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
      ),
    );
  });

  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
  });

  test('a favorite saved under the legacy URL form is migrated', () async {
    await seed({
      'http://host/u/p/42.ts': {'name': 'Sky', 'playlistId': 'p1'},
    });

    await StorageService.reconcileIptvFavoriteUrls([
      channel('http://host/live/u/p/42.ts', name: 'Sky'),
    ]);

    final result = await readFavorites();
    expect(result.keys, ['http://host/live/u/p/42.ts']);
    expect(result.values.single['name'], 'Sky',
        reason: 'the metadata rides along with the rename');
  });

  test('an extension-only difference is migrated too', () async {
    await seed({
      'http://host/live/u/p/42.m3u8': {'name': 'Sky'},
    });

    await StorageService.reconcileIptvFavoriteUrls([
      channel('http://host/live/u/p/42.ts', name: 'Sky'),
    ]);

    expect((await readFavorites()).keys, ['http://host/live/u/p/42.ts']);
  });

  test('unrelated favorites are left alone', () async {
    await seed({
      'http://other/live/u/p/1.ts': {'name': 'Keep me'},
    });

    await StorageService.reconcileIptvFavoriteUrls([
      channel('http://host/live/u/p/42.ts'),
    ]);

    expect((await readFavorites()).keys, ['http://other/live/u/p/1.ts']);
  });

  test('a channel starred DURING the scan is not discarded', () async {
    // The regression this guards: the scan used to hold a decoded copy of the
    // whole store across its yields and write it back at the end, silently
    // reverting anything saved in between. Row-level writes make the star its
    // own insert, but the rename transaction must still leave it untouched.
    await seed({
      'http://host/u/p/42.ts': {'name': 'Migrates', 'playlistId': 'p1'},
      // A second, non-matching entry keeps the scan from short-circuiting
      // once the first migration candidate is consumed.
      'http://host/u/p/999.ts': {'name': 'Orphan', 'playlistId': 'p1'},
    });

    final channels = [
      ...filler('host', 20000),
      channel('http://host/live/u/p/42.ts', name: 'Migrates'),
    ];

    final scan = StorageService.reconcileIptvFavoriteUrls(channels);
    // Land in the middle of the scan, after at least one yield.
    await Future<void>.delayed(Duration.zero);
    await StorageService.setIptvChannelFavorited(
      'http://host/live/u/p/777.ts',
      true,
      channelName: 'Starred mid-scan',
    );
    await scan;

    final result = await readFavorites();
    expect(result.keys, contains('http://host/live/u/p/777.ts'),
        reason: 'the star must survive the concurrent migration');
    expect(result.keys, contains('http://host/live/u/p/42.ts'),
        reason: 'and the migration must still happen');
  });

  test('a channel un-starred DURING the scan is not resurrected', () async {
    await seed({
      'http://host/u/p/42.ts': {'name': 'Doomed', 'playlistId': 'p1'},
      'http://host/u/p/999.ts': {'name': 'Orphan', 'playlistId': 'p1'},
    });

    final channels = [
      ...filler('host', 20000),
      channel('http://host/live/u/p/42.ts', name: 'Doomed'),
    ];

    final scan = StorageService.reconcileIptvFavoriteUrls(channels);
    await Future<void>.delayed(Duration.zero);
    await StorageService.setIptvChannelFavorited(
      'http://host/u/p/42.ts',
      false,
    );
    await scan;

    final result = await readFavorites();
    expect(result.keys, isNot(contains('http://host/u/p/42.ts')));
    expect(result.keys, isNot(contains('http://host/live/u/p/42.ts')),
        reason: 'a removed favorite must not come back under a new key');
  });

  test('nothing changes when there is nothing to migrate', () async {
    await seed({
      'http://host/live/u/p/42.ts': {'name': 'Already current'},
    });
    final before = jsonEncode(await readFavorites());

    await StorageService.reconcileIptvFavoriteUrls([
      channel('http://host/live/u/p/42.ts'),
    ]);

    expect(jsonEncode(await readFavorites()), before);
  });

  test('an empty store is a no-op', () async {
    SharedPreferences.setMockInitialValues({});

    await StorageService.reconcileIptvFavoriteUrls([
      channel('http://host/live/u/p/42.ts'),
    ]);

    expect(await readFavorites(), isEmpty);
  });

  group('across several lists', () {
    test(
        'two lists holding DIFFERENT historical forms of one channel both '
        'migrate', () async {
      // The canonical map is keyed by canonical URL. Both stored forms
      // collapse onto the same key, so a single-valued map would keep only
      // one of them and leave the other list pointing at a dead URL forever.
      await seed({
        'http://host/u/p/42.ts': {'name': 'Legacy path form'},
      });
      final kids = await StorageService.createIptvList('Kids');
      await StorageService.setIptvChannelInList(
        kids,
        'http://host/live/u/p/42.m3u8',
        true,
        channelName: 'Legacy extension form',
      );

      await StorageService.reconcileIptvFavoriteUrls([
        channel('http://host/live/u/p/42.ts', name: 'Sky'),
      ]);

      expect((await readFavorites()).keys, ['http://host/live/u/p/42.ts']);
      expect(
        (await StorageService.getIptvListChannels(kids)).keys,
        ['http://host/live/u/p/42.ts'],
        reason: 'every list holding the channel moves to the current form',
      );
    });

    test('the same stored URL in two lists migrates in both', () async {
      await seed({
        'http://host/u/p/42.ts': {'name': 'Sky'},
      });
      final kids = await StorageService.createIptvList('Kids');
      await StorageService.setIptvChannelInList(
        kids,
        'http://host/u/p/42.ts',
        true,
        channelName: 'Sky',
      );

      await StorageService.reconcileIptvFavoriteUrls([
        channel('http://host/live/u/p/42.ts', name: 'Sky'),
      ]);

      expect((await readFavorites()).keys, ['http://host/live/u/p/42.ts']);
      expect((await StorageService.getIptvListChannels(kids)).keys,
          ['http://host/live/u/p/42.ts']);
    });

    test('a rename that collides with an existing row collapses it', () async {
      // Both forms already sit in the SAME list (only reachable for rows
      // carried over from the old store, where de-dup was global).
      final kids = await StorageService.createIptvList('Kids');
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      for (final url in [
        'http://host/u/p/42.ts',
        'http://host/live/u/p/42.ts',
      ]) {
        await db.insert('iptv_list_channels', {
          'list_id': kids,
          'url': url,
          'name': 'Sky',
          'added_at': 1,
        });
      }

      await StorageService.reconcileIptvFavoriteUrls([
        channel('http://host/live/u/p/42.ts', name: 'Sky'),
      ]);

      expect((await StorageService.getIptvListChannels(kids)).keys,
          ['http://host/live/u/p/42.ts'],
          reason: 'the duplicate collapses instead of throwing on the '
              '(list_id, url) primary key');
    });
  });

  group('presentation backfill', () {
    test('the in-memory scan fills content type and duration', () async {
      // Local files and Stremio addon catalogs only ever reconcile through
      // this path, so a migrated VOD favorite of theirs would present as
      // live forever if the backfill lived only in the worker variant.
      await seed({
        'http://host/movie/u/p/9.mp4': {'name': 'A Movie'},
      });

      await StorageService.reconcileIptvFavoriteUrls([
        IptvChannel(
          name: 'A Movie',
          url: 'http://host/movie/u/p/9.mp4',
          contentType: 'vod',
          duration: 5400,
        ),
      ]);

      final meta = (await readFavorites())['http://host/movie/u/p/9.mp4']!;
      expect(meta['contentType'], 'vod');
      expect(meta['duration'], 5400);
    });

    test('backfill rides along with a rename', () async {
      await seed({
        'http://host/u/p/42.ts': {'name': 'Sky'},
      });

      await StorageService.reconcileIptvFavoriteUrls([
        IptvChannel(
          name: 'Sky',
          url: 'http://host/live/u/p/42.ts',
          contentType: 'live',
          duration: -1,
        ),
      ]);

      final meta = (await readFavorites())['http://host/live/u/p/42.ts']!;
      expect(meta['contentType'], 'live');
      expect(meta['duration'], -1);
    });

    test('a known content type is never overwritten', () async {
      const url = 'http://host/movie/u/p/9.mp4';
      await StorageService.setIptvChannelFavorited(
        url,
        true,
        channelName: 'A Movie',
        contentType: 'vod',
        duration: 5400,
      );

      // A catalog that mislabels the row must not be able to flip it.
      await StorageService.reconcileIptvFavoriteUrls([
        IptvChannel(name: 'A Movie', url: url, contentType: 'live'),
      ]);

      final meta = (await readFavorites())[url]!;
      expect(meta['contentType'], 'vod');
      expect(meta['duration'], 5400);
    });

    test('backfill reaches every list holding the channel', () async {
      const url = 'http://host/movie/u/p/9.mp4';
      await seed({
        url: {'name': 'A Movie'},
      });
      final kids = await StorageService.createIptvList('Kids');
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      await db.insert('iptv_list_channels', {
        'list_id': kids,
        'url': url,
        'name': 'A Movie',
        'added_at': 1,
      });

      await StorageService.reconcileIptvFavoriteUrls([
        IptvChannel(
          name: 'A Movie',
          url: url,
          contentType: 'vod',
          duration: 5400,
        ),
      ]);

      expect((await StorageService.getIptvListChannels(kids))[url]!['contentType'],
          'vod');
      expect((await readFavorites())[url]!['contentType'], 'vod');
    });
  });

  group('catalog-DB variant (worker-side scan)', () {
    late Directory catalogDir;

    setUp(() async {
      catalogDir = await Directory.systemTemp.createTemp('reconcile_catalog');
      IptvCatalogDb.debugDirectoryOverride = catalogDir.path;
      await IptvCatalogDb.open();
    });

    tearDown(() async {
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = null;
      await catalogDir.delete(recursive: true);
    });

    test('renames a legacy-form favorite against the stored catalog rows',
        () async {
      await seed({
        'http://host/u/p/42.ts': {'name': 'Sky', 'playlistId': 'p1'},
        'http://other/live/u/p/1.ts': {'name': 'Keep me'},
      });
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'xc|http://host|u|live',
        channels: [
          channel('http://host/live/u/p/42.ts', name: 'Sky'),
          channel('http://host/live/u/p/43.ts', name: 'Other'),
        ],
      );

      await StorageService.reconcileIptvFavoriteUrlsForCatalog(
        'xc|http://host|u|live',
      );

      final result = await readFavorites();
      expect(result.keys, contains('http://host/live/u/p/42.ts'),
          reason: 'the favorite migrates to the catalog\'s current URL form');
      expect(result.keys, isNot(contains('http://host/u/p/42.ts')));
      expect(result.keys, contains('http://other/live/u/p/1.ts'),
          reason: 'unrelated favorites are untouched');
      expect(result['http://host/live/u/p/42.ts']!['name'], 'Sky');
    });

    test('a catalog that was never ingested changes nothing', () async {
      await seed({
        'http://host/u/p/42.ts': {'name': 'Sky'},
      });

      await StorageService.reconcileIptvFavoriteUrlsForCatalog('missing|key');

      expect((await readFavorites()).keys, ['http://host/u/p/42.ts']);
    });

    test('different historical forms across two lists both migrate',
        () async {
      await seed({
        'http://host/u/p/42.ts': {'name': 'Sky'},
      });
      final kids = await StorageService.createIptvList('Kids');
      await StorageService.setIptvChannelInList(
        kids,
        'http://host/live/u/p/42.m3u8',
        true,
        channelName: 'Sky',
      );
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'xc|http://host|u|live',
        channels: [channel('http://host/live/u/p/42.ts', name: 'Sky')],
      );

      await StorageService.reconcileIptvFavoriteUrlsForCatalog(
        'xc|http://host|u|live',
      );

      expect((await readFavorites()).keys, ['http://host/live/u/p/42.ts']);
      expect((await StorageService.getIptvListChannels(kids)).keys,
          ['http://host/live/u/p/42.ts']);
    });

    test('the worker scan backfills content type and duration', () async {
      const url = 'http://host/movie/u/p/9.mp4';
      await seed({
        url: {'name': 'A Movie'},
      });
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'xc|http://host|u|vod',
        channels: [
          IptvChannel(
            name: 'A Movie',
            url: url,
            contentType: 'vod',
            duration: 5400,
          ),
        ],
      );

      await StorageService.reconcileIptvFavoriteUrlsForCatalog(
        'xc|http://host|u|vod',
      );

      final meta = (await readFavorites())[url]!;
      expect(meta['contentType'], 'vod');
      expect(meta['duration'], 5400);
    });
  });
}
