import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';

/// User-created IPTV channel lists. Favorites is the built-in one, so the
/// interesting cases are the ones a single list could never produce: the same
/// channel in several lists at once, per-list canonical de-duplication, and
/// the protections that keep the built-in list from being renamed or deleted.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
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

  group('list CRUD', () {
    test('a fresh store has only the built-in Favorites list', () async {
      final lists = await StorageService.getIptvLists();
      expect(lists, hasLength(1));
      expect(lists.single.id, StorageService.iptvFavoritesListId);
      expect(lists.single.isBuiltin, isTrue);
      expect(lists.single.isFavorites, isTrue);
      expect(lists.single.position, 0);
      expect(lists.single.channelCount, 0);
    });

    test('created lists keep creation order after Favorites', () async {
      await StorageService.createIptvList('Kids');
      await StorageService.createIptvList('Sports');

      final lists = await StorageService.getIptvLists();
      expect(lists.map((l) => l.name), ['Favorites', 'Kids', 'Sports']);
      expect(lists.map((l) => l.isBuiltin), [true, false, false]);
    });

    test('names are trimmed and the count reflects membership', () async {
      final id = await StorageService.createIptvList('  Kids  ');
      await StorageService.setIptvChannelInList(
        id,
        'http://h/live/u/p/1.ts',
        true,
        channelName: 'Cartoons',
      );

      final kids = (await StorageService.getIptvLists()).firstWhere(
        (l) => l.id == id,
      );
      expect(kids.name, 'Kids');
      expect(kids.channelCount, 1);
    });

    test('renaming and deleting a custom list works', () async {
      final id = await StorageService.createIptvList('Kids');

      await StorageService.renameIptvList(id, 'Family');
      expect((await StorageService.getIptvLists()).map((l) => l.name), [
        'Favorites',
        'Family',
      ]);

      await StorageService.deleteIptvList(id);
      expect((await StorageService.getIptvLists()).map((l) => l.name), [
        'Favorites',
      ]);
    });

    test(
      'deleting a list drops its memberships but not the other lists',
      () async {
        final kids = await StorageService.createIptvList('Kids');
        const url = 'http://h/live/u/p/1.ts';
        await StorageService.setIptvChannelInList(kids, url, true);
        await StorageService.setIptvChannelFavorited(url, true);

        await StorageService.deleteIptvList(kids);

        expect(await StorageService.getIptvListChannels(kids), isEmpty);
        expect(
          (await StorageService.getIptvFavoriteChannels()).keys,
          [url],
          reason: 'the channel stays in every other list it belongs to',
        );
      },
    );

    test('the built-in list cannot be renamed or deleted', () async {
      const favorites = StorageService.iptvFavoritesListId;

      await StorageService.renameIptvList(favorites, 'Starred');
      await StorageService.deleteIptvList(favorites);

      final lists = await StorageService.getIptvLists();
      expect(
        lists.map((l) => l.name),
        ['Favorites'],
        reason:
            'Favorites is structural — the UI has no affordance for '
            'either, but the store refuses regardless',
      );
    });

    test('reorder assigns 1..n and leaves Favorites pinned first', () async {
      final kids = await StorageService.createIptvList('Kids');
      final sports = await StorageService.createIptvList('Sports');
      final news = await StorageService.createIptvList('News');

      await StorageService.reorderIptvLists([news, kids, sports]);

      final lists = await StorageService.getIptvLists();
      expect(lists.map((l) => l.name), ['Favorites', 'News', 'Kids', 'Sports']);
      expect(lists.first.position, 0);
      expect(lists.map((l) => l.position), [0, 1, 2, 3]);
    });

    test('reorder ignores the built-in list even when it is named', () async {
      final kids = await StorageService.createIptvList('Kids');

      await StorageService.reorderIptvLists([
        kids,
        StorageService.iptvFavoritesListId,
      ]);

      final lists = await StorageService.getIptvLists();
      expect(lists.first.isFavorites, isTrue);
      expect(lists.first.position, 0);
    });
  });

  group('membership', () {
    const url = 'http://h/live/u/p/7.ts';

    test('one channel can belong to several lists at once', () async {
      final kids = await StorageService.createIptvList('Kids');
      final sports = await StorageService.createIptvList('Sports');

      await StorageService.setIptvChannelFavorited(
        url,
        true,
        channelName: 'News',
      );
      await StorageService.setIptvChannelInList(
        kids,
        url,
        true,
        channelName: 'News',
      );
      await StorageService.setIptvChannelInList(
        sports,
        url,
        true,
        channelName: 'News',
      );

      final membership = await StorageService.getIptvChannelMembership();
      expect(membership[url], {
        StorageService.iptvFavoritesListId,
        kids,
        sports,
      });

      await StorageService.setIptvChannelInList(kids, url, false);
      expect(
        (await StorageService.getIptvChannelMembership())[url],
        {StorageService.iptvFavoritesListId, sports},
        reason: 'removing from one list leaves the others alone',
      );
    });

    test(
      'metadata round-trips per list, including presentation fields',
      () async {
        final kids = await StorageService.createIptvList('Kids');
        await StorageService.setIptvChannelInList(
          kids,
          'http://h/movie/u/p/9.mp4',
          true,
          channelName: 'A Movie',
          logoUrl: 'http://h/9.png',
          group: 'Films',
          playlistId: 'p1',
          channelNumber: 12,
          contentType: 'vod',
          duration: 5400,
          httpHeaders: {'Referer': 'http://h/'},
        );

        final meta = (await StorageService.getIptvListChannels(
          kids,
        ))['http://h/movie/u/p/9.mp4']!;
        expect(meta['name'], 'A Movie');
        expect(meta['logoUrl'], 'http://h/9.png');
        expect(meta['group'], 'Films');
        expect(meta['playlistId'], 'p1');
        expect(meta['channelNumber'], 12);
        expect(meta['contentType'], 'vod');
        expect(meta['duration'], 5400);
        expect(meta['httpHeaders'], {'Referer': 'http://h/'});
        expect(meta['addedAt'], greaterThan(0));
      },
    );

    test(
      'a channel with no stored presentation omits the keys entirely',
      () async {
        await StorageService.setIptvChannelFavorited(url, true);

        final meta = (await StorageService.getIptvFavoriteChannels())[url]!;
        expect(meta.containsKey('contentType'), isFalse);
        expect(meta.containsKey('duration'), isFalse);
      },
    );

    test(
      'canonical duplicates collapse within a list but not across lists',
      () async {
        final kids = await StorageService.createIptvList('Kids');

        // Same channel, two URL forms the panel has served over time.
        await StorageService.setIptvChannelInList(
          kids,
          'http://h/live/u/p/7.m3u8',
          true,
          channelName: 'HLS form',
        );
        await StorageService.setIptvChannelInList(
          kids,
          'http://h/live/u/p/7.ts',
          true,
          channelName: 'TS form',
        );
        await StorageService.setIptvChannelFavorited(
          'http://h/live/u/p/7.m3u8',
          true,
          channelName: 'HLS form',
        );

        final kidsChannels = await StorageService.getIptvListChannels(kids);
        expect(
          kidsChannels.keys,
          ['http://h/live/u/p/7.ts'],
          reason: 'canonically-equal duplicates collapse to one row per list',
        );

        expect(
          (await StorageService.getIptvFavoriteChannels()).keys,
          ['http://h/live/u/p/7.m3u8'],
          reason: 'the de-dup is scoped to the list being written',
        );
      },
    );

    test('listsForChannel matches older URL forms canonically', () async {
      final kids = await StorageService.createIptvList('Kids');
      await StorageService.setIptvChannelInList(
        kids,
        'http://h/u/p/7.ts',
        true,
      );

      expect(
        await StorageService.getIptvListsForChannel('http://h/live/u/p/7.m3u8'),
        {kids},
        reason:
            'the picker must show the right checkmarks even when the '
            'catalog now serves a different URL form',
      );
    });

    test('origins are kept per (list, url), not collapsed per url', () async {
      // The same channel URL can legitimately be saved into two lists from
      // two different providers. Collapsing the origins would replay one
      // membership under the other's credentials, and hand it to the wrong
      // provider-deletion sweep.
      final kids = await StorageService.createIptvList('Kids');
      await StorageService.setIptvChannelFavorited(url, true, playlistId: 'p1');
      await StorageService.setIptvChannelInList(
        kids,
        url,
        true,
        playlistId: 'p2',
      );

      final snapshot = await StorageService.getIptvMembershipSnapshot();
      expect(snapshot.origins[(StorageService.iptvFavoritesListId, url)], 'p1');
      expect(snapshot.origins[(kids, url)], 'p2');

      // And the sweep is row-based, so it takes only the matching membership.
      await StorageService.removeIptvListChannelsByPlaylistId('p1');
      expect(await StorageService.getIptvFavoriteChannels(), isEmpty);
      expect(
        (await StorageService.getIptvListChannels(kids)).keys,
        [url],
        reason: 'the other provider\'s membership survives',
      );
    });

    test('deleting a provider sweeps its channels out of every list', () async {
      final kids = await StorageService.createIptvList('Kids');
      await StorageService.setIptvChannelInList(
        kids,
        'http://h/live/u/p/1.ts',
        true,
        playlistId: 'p1',
      );
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/1.ts',
        true,
        playlistId: 'p1',
      );
      await StorageService.setIptvChannelInList(
        kids,
        'http://h/live/u/p/2.ts',
        true,
        playlistId: 'p2',
      );

      await StorageService.removeIptvListChannelsByPlaylistId('p1');

      expect((await StorageService.getIptvListChannels(kids)).keys, [
        'http://h/live/u/p/2.ts',
      ]);
      expect(
        await StorageService.getIptvFavoriteChannels(),
        isEmpty,
        reason: 'a deleted provider leaves nothing playable behind',
      );
      expect(
        (await StorageService.getIptvLists()).map((l) => l.name),
        ['Favorites', 'Kids'],
        reason: 'the list itself survives, possibly empty',
      );
    });
  });

  group('channel order', () {
    test(
      'list order persists and metadata refresh keeps the saved rank',
      () async {
        final list = await StorageService.createIptvList('Sports');
        for (final entry in const [
          ('a', 'Alpha'),
          ('b', 'Bravo'),
          ('c', 'Charlie'),
        ]) {
          await StorageService.setIptvChannelInList(
            list,
            'http://h/${entry.$1}',
            true,
            channelName: entry.$2,
          );
        }

        await StorageService.reorderIptvListChannels(list, const [
          'http://h/c',
          'http://h/a',
          'http://h/b',
        ]);
        expect((await StorageService.getIptvListChannels(list)).keys, [
          'http://h/c',
          'http://h/a',
          'http://h/b',
        ]);

        await StorageService.setIptvChannelInList(
          list,
          'http://h/a',
          true,
          channelName: 'Alpha HD',
        );
        final refreshed = await StorageService.getIptvListChannels(list);
        expect(refreshed.keys, ['http://h/c', 'http://h/a', 'http://h/b']);
        expect(refreshed['http://h/a']!['name'], 'Alpha HD');
      },
    );

    test(
      'stale editor save cannot resurrect removals and appends new rows',
      () async {
        final list = await StorageService.createIptvList('News');
        for (final id in const ['a', 'b', 'c']) {
          await StorageService.setIptvChannelInList(list, 'http://h/$id', true);
        }
        const staleEditorOrder = ['http://h/c', 'http://h/a', 'http://h/b'];

        await StorageService.setIptvChannelInList(list, 'http://h/b', false);
        await StorageService.setIptvChannelInList(list, 'http://h/d', true);
        await StorageService.reorderIptvListChannels(list, staleEditorOrder);

        expect((await StorageService.getIptvListChannels(list)).keys, [
          'http://h/c',
          'http://h/a',
          'http://h/d',
        ]);
      },
    );

    test(
      'order notifications run outside the database operation Zone',
      () async {
        final list = await StorageService.createIptvList('News');
        await StorageService.setIptvChannelInList(list, 'http://h/a', true);

        bool? listRevisionInOperationZone;
        bool? orderRevisionInOperationZone;
        void onListRevision() {
          listRevisionInOperationZone =
              DebrifyTvDatabase.instance.debugInOperationZone;
        }

        void onOrderRevision() {
          orderRevisionInOperationZone =
              DebrifyTvDatabase.instance.debugInOperationZone;
        }

        IptvMediaStore.listsRevision.addListener(onListRevision);
        IptvChannelOrderSignal.revision.addListener(onOrderRevision);
        addTearDown(() {
          IptvMediaStore.listsRevision.removeListener(onListRevision);
          IptvChannelOrderSignal.revision.removeListener(onOrderRevision);
        });

        await StorageService.reorderIptvListChannels(list, const [
          'http://h/a',
        ]);
        expect(listRevisionInOperationZone, isFalse);
        expect(orderRevisionInOperationZone, isFalse);

        orderRevisionInOperationZone = null;
        await StorageService.setIptvCategoryChannelOrder('source', 'News', [
          const IptvChannelOrderIdentity(
            url: 'http://h/a',
            name: 'Alpha',
            occurrence: 0,
          ),
        ]);
        expect(orderRevisionInOperationZone, isFalse);
      },
    );

    test(
      'local category order distinguishes duplicates and appends new rows',
      () async {
        IptvChannel channel(String name, String url, String group) =>
            IptvChannel(name: name, url: url, group: group);

        final provider = [
          channel('Duplicate', 'http://h/same', 'Sports'),
          channel('Other group', 'http://h/other', 'News'),
          channel('Bravo', 'http://h/b', 'Sports'),
          channel('Duplicate', 'http://h/same', 'Sports'),
        ];
        final initial = await StorageService.getIptvCategoryOrderEntries(
          'local-1',
          provider,
          'Sports',
        );
        expect(initial.map((entry) => entry.identity.occurrence), [0, 0, 1]);

        await StorageService.setIptvCategoryChannelOrder('local-1', 'Sports', [
          initial[1].identity,
          initial[2].identity,
          initial[0].identity,
        ]);
        final withNewRow = [
          ...provider,
          channel('Delta', 'http://h/d', 'Sports'),
        ];
        final ordered = await StorageService.getIptvCategoryOrderEntries(
          'local-1',
          withNewRow,
          'Sports',
        );
        expect(
          ordered.map(
            (entry) => (entry.channel.name, entry.identity.occurrence),
          ),
          [('Bravo', 0), ('Duplicate', 1), ('Duplicate', 0), ('Delta', 0)],
        );

        final applied = await StorageService.applyIptvCategoryChannelOrders(
          'local-1',
          withNewRow,
        );
        expect(
          applied.map((channel) => channel.name),
          ['Bravo', 'Other group', 'Duplicate', 'Duplicate', 'Delta'],
          reason: 'the News slot stays put while Sports rows reorder around it',
        );
      },
    );
  });

  group('favorites compatibility', () {
    test('favorites read and write through the built-in list', () async {
      const url = 'http://h/live/u/p/5.ts';
      await StorageService.setIptvChannelFavorited(
        url,
        true,
        channelName: 'News',
      );

      expect(
        (await StorageService.getIptvListChannels(
          StorageService.iptvFavoritesListId,
        ))[url]!['name'],
        'News',
      );
      expect(await StorageService.getIptvFavoriteChannelUrls(), {url});

      await StorageService.setIptvChannelFavorited(url, false);
      expect(await StorageService.getIptvFavoriteChannels(), isEmpty);
    });
  });
}
