import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_mutation.dart';

/// IPTV favorites / watch history / video resume on debrify_tv.db, including
/// the one-time import of the legacy SharedPreferences JSON blobs. Everything
/// is driven through the public StorageService API, which is what the app
/// actually calls.
void main() {
  const favoritesKey = 'iptv_favorite_channels_v1';
  const historyKey = 'iptv_watch_history_v1';
  const resumeKey = 'video_resume_v1';

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    IptvMediaStore.debugLibraryClock = DateTime.now;
    WebDavSyncLibraryMutation.originDeviceId = 'local-device';
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            // Production enables this in onConfigure, and list membership is a
            // foreign key onto iptv_lists — without it the cascade rules under
            // test here simply wouldn't fire.
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
  });

  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
    IptvMediaStore.debugLibraryClock = DateTime.now;
    WebDavSyncLibraryMutation.originDeviceId = 'local-device';
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
  });

  group('legacy prefs import', () {
    test('imports all three stores once and removes the prefs keys', () async {
      SharedPreferences.setMockInitialValues({
        favoritesKey: jsonEncode({
          'http://h/live/u/p/1.ts': {
            'name': 'Спорт ᴴᴰ',
            'logoUrl': 'http://h/logo/1.png',
            'group': 'Sports',
            'playlistId': 'p1',
            'httpHeaders': {'User-Agent': 'TiviMate'},
            'addedAt': 111,
          },
        }),
        historyKey: jsonEncode({
          'http://h/movie/u/p/9.mp4': {
            'name': 'A Movie',
            'playlistId': 'p1',
            'seriesId': 's1',
            'seriesName': 'A Show',
            'season': 2,
            'episode': 5,
            'hasNext': true,
            'lastPlayedAt': 222,
          },
        }),
        resumeKey: jsonEncode({
          'http://h/movie/u/p/9.mp4': {
            'positionMs': 60000,
            'durationMs': 120000,
            'speed': 1.5,
            'aspect': 'fill',
            'updatedAt': 333,
          },
        }),
      });
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications++;
      };

      final favorites = await StorageService.getIptvFavoriteChannels();
      final meta = favorites['http://h/live/u/p/1.ts']!;
      expect(meta['name'], 'Спорт ᴴᴰ');
      expect(meta['group'], 'Sports');
      expect(meta['playlistId'], 'p1');
      expect(meta['httpHeaders'], {'User-Agent': 'TiviMate'});
      expect(meta['addedAt'], 111);

      final history = await StorageService.getIptvWatchHistory();
      final watched = history['http://h/movie/u/p/9.mp4']!;
      expect(watched['name'], 'A Movie');
      expect(watched['seriesId'], 's1');
      expect(watched['seriesName'], 'A Show');
      expect(watched['season'], 2);
      expect(watched['episode'], 5);
      expect(watched['hasNext'], true);
      expect(watched['lastPlayedAt'], 222);

      final resume = await StorageService.getVideoResume(
        'http://h/movie/u/p/9.mp4',
      );
      expect(resume, isNotNull);
      expect(resume!['positionMs'], 60000);
      expect(resume['durationMs'], 120000);
      expect(resume['speed'], 1.5);
      expect(resume['aspect'], 'fill');
      expect(resume['updatedAt'], 333);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(favoritesKey),
        isNull,
        reason: 'the legacy blob is deleted after a successful import',
      );
      expect(prefs.getString(historyKey), isNull);
      expect(prefs.getString(resumeKey), isNull);
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      expect(
        (await db.query(
          'webdav_sync_record_state',
          columns: const <String>['origin_device_id'],
          where: 'kind IN (?, ?, ?)',
          whereArgs: const <Object?>[
            WebDavSyncLibraryKinds.iptvListChannels,
            WebDavSyncLibraryKinds.iptvWatchHistory,
            WebDavSyncLibraryKinds.videoResume,
          ],
        )).map((row) => row['origin_device_id']),
        everyElement('migration'),
      );
      expect(
        (await db.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '3',
      );
      final favoriteState = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
      )).single;
      expect(favoriteState['owner_key'], IptvMediaStore.favoritesListId);
      expect(favoriteState['item_key'], 'http://h/live/u/p/1.ts');
      expect(favoriteState['updated_at_ms'], 111);
      expect(notifications, 0);
    });

    test(
      'an oversized legacy history blob imports only the newest rows',
      () async {
        final blob = <String, Object?>{
          for (var i = 0; i < 250; i++)
            'http://h/movie/$i.mp4': <String, Object?>{
              'name': 'Movie $i',
              'playlistId': 'p1',
              'lastPlayedAt': 1000 + i,
            },
        };
        SharedPreferences.setMockInitialValues({historyKey: jsonEncode(blob)});

        final history = await StorageService.getIptvWatchHistory();
        expect(history, hasLength(100));
        expect(history.containsKey('http://h/movie/249.mp4'), isTrue);
        expect(history.containsKey('http://h/movie/150.mp4'), isTrue);
        expect(
          history.containsKey('http://h/movie/149.mp4'),
          isFalse,
          reason: 'the import honors the same retention as the live writer',
        );

        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        expect(
          await db.query(
            'webdav_sync_record_state',
            where: 'kind = ?',
            whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvWatchHistory],
          ),
          hasLength(100),
          reason: 'capped-out rows carry no migration stamps',
        );
      },
    );

    test(
      'a corrupt legacy blob imports as empty, matching the old reader',
      () async {
        SharedPreferences.setMockInitialValues({favoritesKey: 'not json {'});

        expect(await StorageService.getIptvFavoriteChannels(), isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(favoritesKey), isNull);
      },
    );

    test(
      'replayed legacy rows cannot overwrite their tombstoned sidecars',
      () async {
        const favoriteUrl = 'https://panel.invalid/live/tombstoned';
        const mediaUrl = 'https://panel.invalid/movie/tombstoned';
        SharedPreferences.setMockInitialValues({
          favoritesKey: jsonEncode({
            favoriteUrl: <String, Object?>{
              'name': 'Stale favorite',
              'playlistId': 'source-1',
              'addedAt': 10,
            },
          }),
          historyKey: jsonEncode({
            mediaUrl: <String, Object?>{
              'name': 'Stale history',
              'playlistId': 'source-1',
              'lastPlayedAt': 11,
            },
          }),
          resumeKey: jsonEncode({
            mediaUrl: <String, Object?>{
              'positionMs': 12,
              'durationMs': 120,
              'updatedAt': 12,
            },
          }),
        });
        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        final batch = db.batch();
        for (final state in <(String, String, String)>[
          (
            WebDavSyncLibraryKinds.iptvListChannels,
            IptvMediaStore.favoritesListId,
            favoriteUrl,
          ),
          (WebDavSyncLibraryKinds.iptvWatchHistory, 'source-1', mediaUrl),
          (WebDavSyncLibraryKinds.videoResume, 'source-1', mediaUrl),
        ]) {
          batch.insert('webdav_sync_record_state', <String, Object?>{
            'kind': state.$1,
            'owner_key': state.$2,
            'item_key': state.$3,
            'updated_at_ms': 99,
            'origin_device_id': 'device-b',
            'normalized': 1,
            'deleted': 1,
            'aux': null,
          });
        }
        await batch.commit(noResult: true);

        expect(await StorageService.getIptvFavoriteChannels(), isEmpty);
        expect(await db.query('iptv_list_channels'), isEmpty);
        expect(await db.query('iptv_watch_history'), isEmpty);
        expect(await db.query('video_resume'), isEmpty);
        final states = await db.query(
          'webdav_sync_record_state',
          orderBy: 'kind',
        );
        expect(states, hasLength(3));
        expect(states.map((state) => state['updated_at_ms']), everyElement(99));
        expect(
          states.map((state) => state['origin_device_id']),
          everyElement('device-b'),
        );
        expect(states.map((state) => state['normalized']), everyElement(1));
        expect(states.map((state) => state['deleted']), everyElement(1));
      },
    );
  });

  group('list library sync', () {
    test('create, rename, reorder and delete stamp once per call', () async {
      var now = 1000;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      WebDavSyncLibraryMutation.originDeviceId = 'device-a';
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications++;
      };

      final alpha = await IptvMediaStore.createList('Alpha');
      final beta = await IptvMediaStore.createList('Beta');
      expect(alpha, matches(RegExp(r'^list_1000_[A-Za-z0-9_-]{11}$')));
      expect(beta, matches(RegExp(r'^list_1001_[A-Za-z0-9_-]{11}$')));
      expect(alpha, isNot(beta));
      await IptvMediaStore.renameList(alpha, 'Renamed');

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      var alphaState = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ? AND owner_key = ?',
        whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvLists, alpha],
      )).single;
      expect(alphaState['updated_at_ms'], 1002);
      expect(alphaState['origin_device_id'], 'device-a');
      expect(alphaState['deleted'], 0);

      await IptvMediaStore.reorderLists(<String>[beta, alpha]);
      final reordered = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvLists],
      );
      expect(reordered.map((row) => row['updated_at_ms']).toSet(), <Object?>{
        1003,
      });
      await IptvMediaStore.deleteList(alpha);

      alphaState = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ? AND owner_key = ?',
        whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvLists, alpha],
      )).single;
      expect(alphaState['deleted'], 1);
      expect(alphaState['updated_at_ms'], 1004);
      expect(
        await db.query(
          'webdav_sync_record_state',
          where: 'kind = ? AND owner_key = ?',
          whereArgs: const <Object?>[
            WebDavSyncLibraryKinds.iptvLists,
            IptvMediaStore.favoritesListId,
          ],
        ),
        isEmpty,
        reason: 'Favorites never has a metadata record',
      );
      expect(notifications, 5);
      expect(
        (await db.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '5',
      );
    });

    test('list deletion leaves member states live for merge pruning', () async {
      final listId = await IptvMediaStore.createList('Temporary');
      await IptvMediaStore.setChannelInList(
        listId,
        'https://panel.invalid/live/1',
        true,
      );

      await IptvMediaStore.deleteList(listId);

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      expect(
        await db.query(
          'iptv_list_channels',
          where: 'list_id = ?',
          whereArgs: <Object?>[listId],
        ),
        isEmpty,
      );
      final memberState = (await db.query(
        'webdav_sync_record_state',
        where: 'kind = ? AND owner_key = ?',
        whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvListChannels, listId],
      )).single;
      expect(memberState['deleted'], 0);
    });

    test(
      'custom and Favorites membership writes stamp one record each',
      () async {
        var now = 2000;
        IptvMediaStore.debugLibraryClock = () =>
            DateTime.fromMillisecondsSinceEpoch(now++);
        final listId = await IptvMediaStore.createList('Sports');
        var notifications = 0;
        WebDavSyncLibraryMutation.debugUserMutationObserver = () {
          notifications++;
        };

        await IptvMediaStore.setChannelInList(
          listId,
          'https://panel.invalid/live/1',
          true,
          playlistId: 'source-1',
        );
        await IptvMediaStore.setChannelFavorited(
          'https://panel.invalid/live/2',
          true,
          playlistId: 'source-1',
        );

        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        final states = await db.query(
          'webdav_sync_record_state',
          where: 'kind = ?',
          whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
          orderBy: 'owner_key',
        );
        expect(states, hasLength(2));
        expect(states.map((row) => row['owner_key']).toSet(), <Object?>{
          listId,
          IptvMediaStore.favoritesListId,
        });
        expect(states.map((row) => row['deleted']), everyElement(0));
        expect(notifications, 2);
      },
    );

    test('playlist deletion tombstones all removed members once', () async {
      var now = 3000;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      final listId = await IptvMediaStore.createList('Sports');
      await IptvMediaStore.setChannelInList(
        listId,
        'https://panel.invalid/live/1',
        true,
        playlistId: 'source-1',
      );
      await IptvMediaStore.setChannelFavorited(
        'https://panel.invalid/live/2',
        true,
        playlistId: 'source-1',
      );
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications++;
      };

      await IptvMediaStore.removeFavoritesByPlaylistId('source-1');

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      final states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
      );
      expect(states, hasLength(2));
      expect(states.map((row) => row['deleted']), everyElement(1));
      expect(states.map((row) => row['updated_at_ms']).toSet(), <Object?>{
        3003,
      });
      expect(notifications, 1);
    });

    test('member reorder stamps every moved row with one stamp', () async {
      var now = 3500;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      const urls = <String>[
        'https://panel.invalid/live/1',
        'https://panel.invalid/live/2',
        'https://panel.invalid/live/3',
      ];
      for (final url in urls) {
        await IptvMediaStore.setChannelFavorited(url, true);
      }
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications++;
      };

      await IptvMediaStore.reorderListChannels(
        IptvMediaStore.favoritesListId,
        const <String>[
          'https://panel.invalid/live/3',
          'https://panel.invalid/live/1',
          'https://panel.invalid/live/2',
        ],
      );

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      final states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
      );
      expect(states.map((row) => row['updated_at_ms']).toSet(), <Object?>{
        3503,
      });
      expect(
        (await db.query(
          'iptv_list_channels',
          orderBy: 'position',
        )).map((row) => row['url']),
        <String>[urls[2], urls[0], urls[1]],
      );
      expect(notifications, 1);
    });

    test(
      'URL reconciliation tombstones old keys and stamps new keys',
      () async {
        var now = 4000;
        IptvMediaStore.debugLibraryClock = () =>
            DateTime.fromMillisecondsSinceEpoch(now++);
        const oldUrl = 'http://h/live/u/p/7.m3u8';
        const newUrl = 'http://h/live/u/p/7.ts';
        await IptvMediaStore.setChannelFavorited(oldUrl, true);
        var notifications = 0;
        WebDavSyncLibraryMutation.debugUserMutationObserver = () {
          notifications++;
        };

        await IptvMediaStore.reconcileFavoriteUrls(<IptvChannel>[
          IptvChannel(name: 'Seven', url: newUrl),
        ]);

        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        final states = await db.query(
          'webdav_sync_record_state',
          where: 'kind = ?',
          whereArgs: const <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
          orderBy: 'item_key',
        );
        expect(states, hasLength(2));
        expect(
          states.singleWhere((row) => row['item_key'] == oldUrl)['deleted'],
          1,
        );
        expect(
          states.singleWhere((row) => row['item_key'] == newUrl)['deleted'],
          0,
        );
        expect(states.map((row) => row['updated_at_ms']).toSet(), <Object?>{
          4001,
        });
        expect(notifications, 1);
      },
    );

    test('maintenance-origin list writes never stamp or notify', () async {
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications++;
      };
      final listId = await IptvMediaStore.createList(
        'Silent',
        origin: WebDavSyncMutationOrigin.maintenance,
      );
      await IptvMediaStore.renameList(
        listId,
        'Still silent',
        origin: WebDavSyncMutationOrigin.maintenance,
      );
      await IptvMediaStore.setChannelInList(
        listId,
        'https://panel.invalid/live/1',
        true,
        origin: WebDavSyncMutationOrigin.maintenance,
      );
      await IptvMediaStore.deleteList(
        listId,
        origin: WebDavSyncMutationOrigin.maintenance,
      );

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      expect(await db.query('webdav_sync_record_state'), isEmpty);
      expect(
        (await db.query(
          'webdav_sync_meta',
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '0',
      );
      expect(notifications, 0);
    });
  });

  group('category channel orders', () {
    test('source deletion tombstones every order vector once', () async {
      var now = 3000;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      const item = IptvChannelOrderIdentity(
        url: 'https://panel.invalid/live/1',
        name: 'One',
        occurrence: 0,
      );
      await IptvMediaStore.setCategoryChannelOrder(
        'source-1',
        'News',
        const <IptvChannelOrderIdentity>[item],
      );
      await IptvMediaStore.setCategoryChannelOrder(
        'source-1',
        'Sports',
        const <IptvChannelOrderIdentity>[item],
      );

      await IptvMediaStore.removeCategoryOrdersForSource('source-1');

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      expect(await db.query('iptv_category_channel_orders'), isEmpty);
      final states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvCategoryChannelOrders],
        orderBy: 'item_key',
      );
      expect(states.map((row) => row['item_key']), <Object?>['News', 'Sports']);
      expect(states.map((row) => row['deleted']), everyElement(1));
      expect(states.map((row) => row['updated_at_ms']).toSet(), <Object?>{
        3002,
      });
      expect(
        (await db.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '3',
      );
    });
  });

  group('favorites', () {
    test('toggle on stores metadata, toggle off removes it', () async {
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/7.ts',
        true,
        channelName: 'News',
        logoUrl: 'http://h/logo.png',
        group: 'News',
        playlistId: 'p1',
        channelNumber: 407,
        httpHeaders: {'Referer': 'http://h/'},
      );

      var favorites = await StorageService.getIptvFavoriteChannels();
      final meta = favorites['http://h/live/u/p/7.ts']!;
      expect(meta['name'], 'News');
      expect(meta['channelNumber'], 407);
      expect(meta['httpHeaders'], {'Referer': 'http://h/'});
      expect(meta['addedAt'], greaterThan(0));

      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/7.ts',
        false,
      );
      favorites = await StorageService.getIptvFavoriteChannels();
      expect(favorites, isEmpty);
    });

    test(
      're-starring under a different URL form replaces the old entry',
      () async {
        await StorageService.setIptvChannelFavorited(
          'http://h/live/u/p/7.m3u8',
          true,
          channelName: 'HLS form',
        );
        await StorageService.setIptvChannelFavorited(
          'http://h/live/u/p/7.ts',
          true,
          channelName: 'TS form',
        );

        final favorites = await StorageService.getIptvFavoriteChannels();
        expect(
          favorites.keys,
          ['http://h/live/u/p/7.ts'],
          reason: 'canonically-equal duplicates must collapse to one row',
        );
      },
    );

    test('deleting a playlist removes only its favorites', () async {
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/1.ts',
        true,
        playlistId: 'p1',
      );
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/2.ts',
        true,
        playlistId: 'p2',
      );

      await StorageService.removeIptvFavoritesByPlaylistId('p1');

      final favorites = await StorageService.getIptvFavoriteChannels();
      expect(favorites.keys, ['http://h/live/u/p/2.ts']);
    });
  });

  group('watch history', () {
    test('metadata round-trips, including series markers', () async {
      await StorageService.recordIptvWatch(
        'http://h/series/u/p/55.mp4',
        channelName: 'S02E05',
        playlistId: 'p1',
        httpHeaders: {'User-Agent': 'X'},
        seriesId: 's9',
        seriesName: 'A Show',
        season: 2,
        episode: 5,
        hasNextEpisode: true,
      );

      final history = await StorageService.getIptvWatchHistory();
      final meta = history['http://h/series/u/p/55.mp4']!;
      expect(meta['name'], 'S02E05');
      expect(meta['httpHeaders'], {'User-Agent': 'X'});
      expect(meta['seriesId'], 's9');
      expect(meta['hasNext'], true);
      expect(meta['lastPlayedAt'], greaterThan(0));
      expect(meta.containsKey('logoUrl'), isTrue);
    });

    test('a movie entry has no series keys at all', () async {
      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/9.mp4',
        channelName: 'A Movie',
      );

      final meta =
          (await StorageService.getIptvWatchHistory())['http://h/movie/u/p/9.mp4']!;
      expect(meta.containsKey('seriesId'), isFalse);
      expect(meta.containsKey('season'), isFalse);
      expect(meta.containsKey('hasNext'), isFalse);
    });

    test('history is pruned to the 100 most recent', () async {
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      for (var i = 0; i < 100; i++) {
        await db.insert('iptv_watch_history', {
          'url': 'http://h/movie/u/p/$i.mp4',
          'name': 'Old $i',
          'last_played_at': 1000 + i,
        });
      }

      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/new.mp4',
        channelName: 'Newest',
      );

      final history = await StorageService.getIptvWatchHistory();
      expect(history.length, 100);
      expect(history.keys, contains('http://h/movie/u/p/new.mp4'));
      expect(
        history.keys,
        isNot(contains('http://h/movie/u/p/0.mp4')),
        reason: 'the oldest entry makes room for the newest',
      );
    });

    test('retention pruning is silent and keeps live wire state', () async {
      var notifications = 0;
      var now = 1000;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      WebDavSyncLibraryMutation.debugUserMutationObserver = () =>
          notifications++;
      for (var i = 0; i < 101; i++) {
        await IptvMediaStore.recordWatch(
          'https://panel.invalid/movie/$i',
          playlistId: 'source-1',
        );
      }

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      expect(await db.query('iptv_watch_history'), hasLength(100));
      final states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvWatchHistory],
      );
      expect(states, hasLength(101));
      expect(states.map((row) => row['deleted']), everyElement(0));
      expect(
        notifications,
        101,
        reason: 'the 101 user writes notify; the maintenance prune does not',
      );
      expect(
        (await db.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '101',
      );
    });

    test('deleting a playlist removes its history', () async {
      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/1.mp4',
        playlistId: 'p1',
      );
      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/2.mp4',
        playlistId: 'p2',
      );

      await StorageService.removeIptvWatchHistoryByPlaylistId('p1');

      expect((await StorageService.getIptvWatchHistory()).keys, [
        'http://h/movie/u/p/2.mp4',
      ]);
    });
  });

  group('resume + continue watching', () {
    Future<void> watchAndResume(
      String url, {
      required int positionMs,
      required int durationMs,
      required int updatedAt,
      String? seriesId,
      bool? hasNext,
      String? playlistId,
    }) async {
      await StorageService.recordIptvWatch(
        url,
        channelName: url,
        playlistId: playlistId ?? 'p1',
        seriesId: seriesId,
        seriesName: seriesId == null ? null : 'Show $seriesId',
        hasNextEpisode: hasNext,
      );
      await StorageService.upsertVideoResume(url, {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': updatedAt,
      });
    }

    test(
      'in-progress items show, barely-started and finished movies do not',
      () async {
        await watchAndResume(
          'http://h/mid.mp4',
          positionMs: 50000,
          durationMs: 100000,
          updatedAt: 30,
        );
        await watchAndResume(
          'http://h/blip.mp4',
          positionMs: 500,
          durationMs: 100000,
          updatedAt: 20,
        );
        await watchAndResume(
          'http://h/done.mp4',
          positionMs: 99000,
          durationMs: 100000,
          updatedAt: 10,
        );

        final shelf = await StorageService.getIptvContinueWatching();
        expect(shelf.map((e) => e['url']), ['http://h/mid.mp4']);
        expect(shelf.single['progress'], closeTo(0.5, 0.001));
        expect(shelf.single['positionMs'], 50000);
      },
    );

    test(
      'a finished series episode with a next episode stays on the shelf',
      () async {
        await watchAndResume(
          'http://h/s1e1.mp4',
          positionMs: 99000,
          durationMs: 100000,
          updatedAt: 100,
          seriesId: 's1',
          hasNext: true,
        );

        final shelf = await StorageService.getIptvContinueWatching();
        expect(
          shelf.map((e) => e['url']),
          ['http://h/s1e1.mp4'],
          reason: 'a finished middle episode keeps the series visible',
        );
      },
    );

    test(
      'tracking off stops recording and hides what was already stored',
      () async {
        await watchAndResume(
          'http://h/before.mp4',
          positionMs: 50000,
          durationMs: 100000,
          updatedAt: 30,
        );

        await StorageService.setIptvTrackContinueWatching(false);
        await watchAndResume(
          'http://h/after.mp4',
          positionMs: 50000,
          durationMs: 100000,
          updatedAt: 40,
        );

        expect(
          await StorageService.getIptvContinueWatching(),
          isEmpty,
          reason: 'the shelf is hidden wholesale while tracking is off',
        );
        // Resume positions are a separate store and deliberately survive, so
        // both items still play from where they were left.
        expect(
          await StorageService.getVideoResume('http://h/after.mp4'),
          isNotNull,
        );

        await StorageService.setIptvTrackContinueWatching(true);
        final shelf = await StorageService.getIptvContinueWatching();
        expect(
          shelf.map((e) => e['url']),
          ['http://h/before.mp4'],
          reason: 'nothing was deleted, but nothing new was recorded either',
        );
      },
    );

    test('most recently played sorts first', () async {
      await watchAndResume(
        'http://h/older.mp4',
        positionMs: 50000,
        durationMs: 100000,
        updatedAt: 100,
      );
      await watchAndResume(
        'http://h/newer.mp4',
        positionMs: 50000,
        durationMs: 100000,
        updatedAt: 200,
      );

      final shelf = await StorageService.getIptvContinueWatching();
      expect(shelf.map((e) => e['url']), [
        'http://h/newer.mp4',
        'http://h/older.mp4',
      ]);
    });

    test('a resume entry without a timestamp falls back to the watch-history '
        'recency instead of sorting to 1970', () async {
      await watchAndResume(
        'http://h/timed.mp4',
        positionMs: 50000,
        durationMs: 100000,
        updatedAt: 5,
      );
      await StorageService.recordIptvWatch(
        'http://h/untimed.mp4',
        channelName: 'Untimed',
      );
      await StorageService.upsertVideoResume('http://h/untimed.mp4', {
        'positionMs': 50000,
        'durationMs': 100000,
        // no updatedAt — the shape very old legacy entries had
      });

      final shelf = await StorageService.getIptvContinueWatching();
      expect(
        shelf.first['url'],
        'http://h/untimed.mp4',
        reason: 'recordIptvWatch stamped it now, far newer than updatedAt=5',
      );
    });

    test('resume windows: positions only inside the resumable band', () async {
      await StorageService.upsertVideoResume('http://h/mid.mp4', {
        'positionMs': 50000,
        'durationMs': 100000,
        'updatedAt': 1,
      });
      await StorageService.upsertVideoResume('http://h/done.mp4', {
        'positionMs': 99000,
        'durationMs': 100000,
        'updatedAt': 2,
      });

      final positions = await StorageService.getIptvResumePositions([
        'http://h/mid.mp4',
        'http://h/done.mp4',
        'http://h/none.mp4',
      ]);
      expect(positions, {
        'http://h/mid.mp4': 50000,
      }, reason: 'a finished item restarts from the beginning');

      final progress = await StorageService.getIptvProgressForUrls([
        'http://h/mid.mp4',
        'http://h/done.mp4',
      ]);
      expect(progress['http://h/mid.mp4'], closeTo(0.5, 0.001));
      expect(
        progress['http://h/done.mp4'],
        closeTo(0.99, 0.001),
        reason: 'progress bars do show full for finished items',
      );
    });

    test(
      'a resume lookup spanning multiple IN-chunks finds every row',
      () async {
        final urls = [for (var i = 0; i < 1200; i++) 'http://h/v$i.mp4'];
        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        final batch = db.batch();
        for (final url in urls) {
          batch.insert('video_resume', {
            'resume_key': url,
            'position_ms': 5000,
            'duration_ms': 10000,
            'updated_at': 1,
          });
        }
        await batch.commit(noResult: true);

        final progress = await StorageService.getIptvProgressForUrls(urls);
        expect(progress.length, 1200);
      },
    );

    test('clearAllPlaybackData empties the resume store', () async {
      await StorageService.upsertVideoResume('http://h/v.mp4', {
        'positionMs': 1000,
        'durationMs': 2000,
        'updatedAt': 1,
      });

      await StorageService.clearAllPlaybackData();

      expect(await StorageService.getVideoResume('http://h/v.mp4'), isNull);
    });

    test('clear-all writes one tombstone per resume in one revision', () async {
      var now = 2000;
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(now++);
      await IptvMediaStore.upsertVideoResume(
        'generic-title',
        const <String, dynamic>{'positionMs': 1, 'durationMs': 2},
      );
      await IptvMediaStore.upsertVideoResume(
        'https://panel.invalid/movie/1',
        const <String, dynamic>{'positionMs': 3, 'durationMs': 4},
        sourceId: 'source-1',
      );

      await IptvMediaStore.clearVideoResume();

      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      final states = await db.query(
        'webdav_sync_record_state',
        where: 'kind = ?',
        whereArgs: <Object?>[WebDavSyncLibraryKinds.videoResume],
        orderBy: 'item_key',
      );
      expect(states, hasLength(2));
      expect(states.map((row) => row['deleted']), everyElement(1));
      expect(states.map((row) => row['updated_at_ms']).toSet(), <Object?>{
        2002,
      });
      expect(
        (await db.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        '3',
      );
    });

    test(
      'clear-all tombstones a live state after silent physical cleanup',
      () async {
        IptvMediaStore.debugLibraryClock = () =>
            DateTime.fromMillisecondsSinceEpoch(4000);
        await IptvMediaStore.upsertVideoResume(
          'generic-title',
          const <String, dynamic>{'positionMs': 1, 'durationMs': 2},
        );
        final db = DebrifyTvDatabase.debugDatabaseOverride!;
        await db.delete(
          'video_resume',
          where: 'resume_key = ?',
          whereArgs: const <Object?>['generic-title'],
        );

        await IptvMediaStore.clearVideoResume();

        final state = (await db.query(
          'webdav_sync_record_state',
          where: 'kind = ? AND item_key = ?',
          whereArgs: const <Object?>[
            WebDavSyncLibraryKinds.videoResume,
            'generic-title',
          ],
        )).single;
        expect(state['deleted'], 1);
        expect(
          (await db.query(
            'webdav_sync_meta',
            columns: const <String>['value'],
            where: 'key = ?',
            whereArgs: const <Object>['mutation_revision'],
          )).single['value'],
          '2',
        );
      },
    );

    // App reset wipes the device without minting circle-wide deletions.
    test('device-local reset clears resume without tombstones', () async {
      var notifications = 0;
      WebDavSyncLibraryMutation.debugUserMutationObserver = () {
        notifications += 1;
      };
      IptvMediaStore.debugLibraryClock = () =>
          DateTime.fromMillisecondsSinceEpoch(5000);
      await IptvMediaStore.upsertVideoResume(
        'generic-title',
        const <String, dynamic>{'positionMs': 1, 'durationMs': 2},
      );
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      final revisionBefore = (await db.query(
        'webdav_sync_meta',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>['mutation_revision'],
      )).single['value'];
      final notificationsBefore = notifications;

      await IptvMediaStore.clearVideoResume(
        origin: WebDavSyncMutationOrigin.maintenance,
      );

      expect(await db.query('video_resume'), isEmpty);
      // No tombstones, and no retained live stamps either: an exact stamp
      // left behind would block the circle's resume from re-materializing.
      expect(
        await db.query(
          'webdav_sync_record_state',
          where: 'kind = ?',
          whereArgs: const <Object?>[WebDavSyncLibraryKinds.videoResume],
        ),
        isEmpty,
      );
      expect(
        (await db.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>['mutation_revision'],
        )).single['value'],
        revisionBefore,
      );
      expect(notifications, notificationsBefore);
    });

    // Backs Home's "Remove from Continue Watching" on an IPTV card.
    test(
      'removing a movie drops its shelf row AND its saved position',
      () async {
        await watchAndResume(
          'http://h/keep.mp4',
          positionMs: 50000,
          durationMs: 100000,
          updatedAt: 10,
        );
        await watchAndResume(
          'http://h/drop.mp4',
          positionMs: 50000,
          durationMs: 100000,
          updatedAt: 20,
        );

        await StorageService.removeIptvContinueWatchingItem(
          'http://h/drop.mp4',
        );

        final shelf = await StorageService.getIptvContinueWatching();
        expect(shelf.map((e) => e['url']), ['http://h/keep.mp4']);
        expect(
          await StorageService.getVideoResume('http://h/drop.mp4'),
          isNull,
          reason: 'the position must go too, or a replay resumes mid-item',
        );
        expect(
          await StorageService.getVideoResume('http://h/keep.mp4'),
          isNotNull,
          reason: 'nothing else may be touched',
        );
      },
    );

    test('removing a series clears every episode — position included — and '
        'leaves other series alone', () async {
      for (var i = 1; i <= 3; i++) {
        await watchAndResume(
          'http://h/s1e$i.mp4',
          positionMs: 50000,
          durationMs: 100000,
          updatedAt: 100 + i,
          seriesId: 's1',
          hasNext: true,
        );
      }
      await watchAndResume(
        'http://h/s2e1.mp4',
        positionMs: 50000,
        durationMs: 100000,
        updatedAt: 10,
        seriesId: 's2',
        hasNext: true,
      );

      await StorageService.removeIptvContinueWatchingSeries(
        playlistId: 'p1',
        seriesId: 's1',
      );

      final shelf = await StorageService.getIptvContinueWatching();
      expect(
        shelf.map((e) => e['url']),
        ['http://h/s2e1.mp4'],
        reason: 'only the removed series leaves the shelf',
      );
      for (var i = 1; i <= 3; i++) {
        expect(
          await StorageService.getVideoResume('http://h/s1e$i.mp4'),
          isNull,
          reason: 'episode $i kept its position, so its progress bar lives on',
        );
      }
      expect(
        await StorageService.getVideoResume('http://h/s2e1.mp4'),
        isNotNull,
      );
    });

    test('a series removal is scoped to its own playlist', () async {
      await watchAndResume(
        'http://h/a/s1e1.mp4',
        positionMs: 50000,
        durationMs: 100000,
        updatedAt: 10,
        seriesId: 's1',
        hasNext: true,
        playlistId: 'p1',
      );
      // Same series id on a DIFFERENT provider — a distinct show as far as the
      // shelf is concerned (it groups on <playlistId>::<seriesId>).
      await watchAndResume(
        'http://h/b/s1e1.mp4',
        positionMs: 50000,
        durationMs: 100000,
        updatedAt: 20,
        seriesId: 's1',
        hasNext: true,
        playlistId: 'p2',
      );

      await StorageService.removeIptvContinueWatchingSeries(
        playlistId: 'p1',
        seriesId: 's1',
      );

      final shelf = await StorageService.getIptvContinueWatching();
      expect(shelf.map((e) => e['url']), ['http://h/b/s1e1.mp4']);
      expect(
        await StorageService.getVideoResume('http://h/b/s1e1.mp4'),
        isNotNull,
      );
    });
  });
}
