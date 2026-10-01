import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_channel_order.dart';
import 'package:debrify/services/iptv_media_store.dart';

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
      final lists = await IptvFavoritesStorage.getIptvLists();
      expect(lists, hasLength(1));
      expect(lists.single.id, IptvFavoritesStorage.iptvFavoritesListId);
      expect(lists.single.isBuiltin, isTrue);
      expect(lists.single.isFavorites, isTrue);
      expect(lists.single.position, 0);
      expect(lists.single.channelCount, 0);
    });

    test('created lists keep creation order after Favorites', () async {
      await IptvFavoritesStorage.createIptvList('Kids');
      await IptvFavoritesStorage.createIptvList('Sports');

      final lists = await IptvFavoritesStorage.getIptvLists();
      expect(lists.map((l) => l.name), ['Favorites', 'Kids', 'Sports']);
      expect(lists.map((l) => l.isBuiltin), [true, false, false]);
    });

    test('names are trimmed and the count reflects membership', () async {
      final id = await IptvFavoritesStorage.createIptvList('  Kids  ');
      await IptvFavoritesStorage.setIptvChannelInList(
        id,
        'http://h/live/u/p/1.ts',
        true,
        channelName: 'Cartoons',
      );

      final kids = (await IptvFavoritesStorage.getIptvLists()).firstWhere(
        (l) => l.id == id,
      );
      expect(kids.name, 'Kids');
      expect(kids.channelCount, 1);
    });

    test('renaming and deleting a custom list works', () async {
      final id = await IptvFavoritesStorage.createIptvList('Kids');

      await IptvFavoritesStorage.renameIptvList(id, 'Family');
      expect((await IptvFavoritesStorage.getIptvLists()).map((l) => l.name), [
        'Favorites',
        'Family',
      ]);

      await IptvFavoritesStorage.deleteIptvList(id);
      expect((await IptvFavoritesStorage.getIptvLists()).map((l) => l.name), [
        'Favorites',
      ]);
    });

    test(
      'deleting a list drops its memberships but not the other lists',
      () async {
        final kids = await IptvFavoritesStorage.createIptvList('Kids');
        const url = 'http://h/live/u/p/1.ts';
        await IptvFavoritesStorage.setIptvChannelInList(kids, url, true);
        await IptvFavoritesStorage.setIptvChannelFavorited(url, true);

        await IptvFavoritesStorage.deleteIptvList(kids);

        expect(await IptvFavoritesStorage.getIptvListChannels(kids), isEmpty);
        expect(
          (await IptvFavoritesStorage.getIptvFavoriteChannels()).keys,
          [url],
          reason: 'the channel stays in every other list it belongs to',
        );
      },
    );

    test('the built-in list cannot be renamed or deleted', () async {
      const favorites = IptvFavoritesStorage.iptvFavoritesListId;

      await IptvFavoritesStorage.renameIptvList(favorites, 'Starred');
      await IptvFavoritesStorage.deleteIptvList(favorites);

      final lists = await IptvFavoritesStorage.getIptvLists();
      expect(
        lists.map((l) => l.name),
        ['Favorites'],
        reason:
            'Favorites is structural — the UI has no affordance for '
            'either, but the store refuses regardless',
      );
    });

    test('reorder assigns 1..n and leaves Favorites pinned first', () async {
      final kids = await IptvFavoritesStorage.createIptvList('Kids');
      final sports = await IptvFavoritesStorage.createIptvList('Sports');
      final news = await IptvFavoritesStorage.createIptvList('News');

      await IptvFavoritesStorage.reorderIptvLists([news, kids, sports]);

      final lists = await IptvFavoritesStorage.getIptvLists();
      expect(lists.map((l) => l.name), ['Favorites', 'News', 'Kids', 'Sports']);
      expect(lists.first.position, 0);
      expect(lists.map((l) => l.position), [0, 1, 2, 3]);
    });

    test('reorder ignores the built-in list even when it is named', () async {
      final kids = await IptvFavoritesStorage.createIptvList('Kids');

      await IptvFavoritesStorage.reorderIptvLists([
        kids,
        IptvFavoritesStorage.iptvFavoritesListId,
      ]);

      final lists = await IptvFavoritesStorage.getIptvLists();
      expect(lists.first.isFavorites, isTrue);
      expect(lists.first.position, 0);
    });
  });

  group('membership', () {
    const url = 'http://h/live/u/p/7.ts';

    test('one channel can belong to several lists at once', () async {
      final kids = await IptvFavoritesStorage.createIptvList('Kids');
      final sports = await IptvFavoritesStorage.createIptvList('Sports');

      await IptvFavoritesStorage.setIptvChannelFavorited(
        url,
        true,
        channelName: 'News',
      );
      await IptvFavoritesStorage.setIptvChannelInList(
        kids,
        url,
        true,
        channelName: 'News',
      );
      await IptvFavoritesStorage.setIptvChannelInList(
        sports,
        url,
        true,
        channelName: 'News',
      );

      final membership = await IptvFavoritesStorage.getIptvChannelMembership();
      expect(membership[url], {
        IptvFavoritesStorage.iptvFavoritesListId,
        kids,
        sports,
      });

      await IptvFavoritesStorage.setIptvChannelInList(kids, url, false);
      expect(
        (await IptvFavoritesStorage.getIptvChannelMembership())[url],
        {IptvFavoritesStorage.iptvFavoritesListId, sports},
        reason: 'removing from one list leaves the others alone',
      );
    });

    test(
      'metadata round-trips per list, including presentation fields',
      () async {
        final kids = await IptvFavoritesStorage.createIptvList('Kids');
        await IptvFavoritesStorage.setIptvChannelInList(
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

        final meta = (await IptvFavoritesStorage.getIptvListChannels(
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
        await IptvFavoritesStorage.setIptvChannelFavorited(url, true);

        final meta = (await IptvFavoritesStorage.getIptvFavoriteChannels())[url]!;
        expect(meta.containsKey('contentType'), isFalse);
        expect(meta.containsKey('duration'), isFalse);
      },
    );

    test(
      'canonical duplicates collapse within a list but not across lists',
      () async {
        final kids = await IptvFavoritesStorage.createIptvList('Kids');

        // Same channel, two URL forms the panel has served over time.
        await IptvFavoritesStorage.setIptvChannelInList(
          kids,
          'http://h/live/u/p/7.m3u8',
          true,
          channelName: 'HLS form',
        );
        await IptvFavoritesStorage.setIptvChannelInList(
          kids,
          'http://h/live/u/p/7.ts',
          true,
          channelName: 'TS form',
        );
        await IptvFavoritesStorage.setIptvChannelFavorited(
          'http://h/live/u/p/7.m3u8',
          true,
          channelName: 'HLS form',
        );

        final kidsChannels = await IptvFavoritesStorage.getIptvListChannels(kids);
        expect(
          kidsChannels.keys,
          ['http://h/live/u/p/7.ts'],
          reason: 'canonically-equal duplicates collapse to one row per list',
        );

        expect(
          (await IptvFavoritesStorage.getIptvFavoriteChannels()).keys,
          ['http://h/live/u/p/7.m3u8'],
          reason: 'the de-dup is scoped to the list being written',
        );
      },
    );

    test('listsForChannel matches older URL forms canonically', () async {
      final kids = await IptvFavoritesStorage.createIptvList('Kids');
      await IptvFavoritesStorage.setIptvChannelInList(
        kids,
        'http://h/u/p/7.ts',
        true,
      );

      expect(
        await IptvFavoritesStorage.getIptvListsForChannel('http://h/live/u/p/7.m3u8'),
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
      final kids = await IptvFavoritesStorage.createIptvList('Kids');
      await IptvFavoritesStorage.setIptvChannelFavorited(url, true, playlistId: 'p1');
      await IptvFavoritesStorage.setIptvChannelInList(
        kids,
        url,
        true,
        playlistId: 'p2',
      );

      final snapshot = await IptvFavoritesStorage.getIptvMembershipSnapshot();
      expect(snapshot.origins[(IptvFavoritesStorage.iptvFavoritesListId, url)], 'p1');
      expect(snapshot.origins[(kids, url)], 'p2');

      // And the sweep is row-based, so it takes only the matching membership.
      await IptvFavoritesStorage.removeIptvListChannelsByPlaylistId('p1');
      expect(await IptvFavoritesStorage.getIptvFavoriteChannels(), isEmpty);
      expect(
        (await IptvFavoritesStorage.getIptvListChannels(kids)).keys,
        [url],
        reason: 'the other provider\'s membership survives',
      );
    });

    test('deleting a provider sweeps its channels out of every list', () async {
      final kids = await IptvFavoritesStorage.createIptvList('Kids');
      await IptvFavoritesStorage.setIptvChannelInList(
        kids,
        'http://h/live/u/p/1.ts',
        true,
        playlistId: 'p1',
      );
      await IptvFavoritesStorage.setIptvChannelFavorited(
        'http://h/live/u/p/1.ts',
        true,
        playlistId: 'p1',
      );
      await IptvFavoritesStorage.setIptvChannelInList(
        kids,
        'http://h/live/u/p/2.ts',
        true,
        playlistId: 'p2',
      );

      await IptvFavoritesStorage.removeIptvListChannelsByPlaylistId('p1');

      expect((await IptvFavoritesStorage.getIptvListChannels(kids)).keys, [
        'http://h/live/u/p/2.ts',
      ]);
      expect(
        await IptvFavoritesStorage.getIptvFavoriteChannels(),
        isEmpty,
        reason: 'a deleted provider leaves nothing playable behind',
      );
      expect(
        (await IptvFavoritesStorage.getIptvLists()).map((l) => l.name),
        ['Favorites', 'Kids'],
        reason: 'the list itself survives, possibly empty',
      );
    });
  });

  group('channel order', () {
    test(
      'list order persists and metadata refresh keeps the saved rank',
      () async {
        final list = await IptvFavoritesStorage.createIptvList('Sports');
        for (final entry in const [
          ('a', 'Alpha'),
          ('b', 'Bravo'),
          ('c', 'Charlie'),
        ]) {
          await IptvFavoritesStorage.setIptvChannelInList(
            list,
            'http://h/${entry.$1}',
            true,
            channelName: entry.$2,
          );
        }

        await IptvFavoritesStorage.reorderIptvListChannels(list, const [
          'http://h/c',
          'http://h/a',
          'http://h/b',
        ]);
        expect((await IptvFavoritesStorage.getIptvListChannels(list)).keys, [
          'http://h/c',
          'http://h/a',
          'http://h/b',
        ]);

        await IptvFavoritesStorage.setIptvChannelInList(
          list,
          'http://h/a',
          true,
          channelName: 'Alpha HD',
        );
        final refreshed = await IptvFavoritesStorage.getIptvListChannels(list);
        expect(refreshed.keys, ['http://h/c', 'http://h/a', 'http://h/b']);
        expect(refreshed['http://h/a']!['name'], 'Alpha HD');
      },
    );

    test(
      'stale editor save cannot resurrect removals and appends new rows',
      () async {
        final list = await IptvFavoritesStorage.createIptvList('News');
        for (final id in const ['a', 'b', 'c']) {
          await IptvFavoritesStorage.setIptvChannelInList(list, 'http://h/$id', true);
        }
        const staleEditorOrder = ['http://h/c', 'http://h/a', 'http://h/b'];

        await IptvFavoritesStorage.setIptvChannelInList(list, 'http://h/b', false);
        await IptvFavoritesStorage.setIptvChannelInList(list, 'http://h/d', true);
        await IptvFavoritesStorage.reorderIptvListChannels(list, staleEditorOrder);

        expect((await IptvFavoritesStorage.getIptvListChannels(list)).keys, [
          'http://h/c',
          'http://h/a',
          'http://h/d',
        ]);
      },
    );

    test(
      'order notifications run outside the database operation Zone',
      () async {
        final list = await IptvFavoritesStorage.createIptvList('News');
        await IptvFavoritesStorage.setIptvChannelInList(list, 'http://h/a', true);

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

        await IptvFavoritesStorage.reorderIptvListChannels(list, const [
          'http://h/a',
        ]);
        expect(listRevisionInOperationZone, isFalse);
        expect(orderRevisionInOperationZone, isFalse);

        orderRevisionInOperationZone = null;
        await IptvFavoritesStorage.setIptvCategoryChannelOrder('source', 'News', [
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
        final initial = await IptvFavoritesStorage.getIptvCategoryOrderEntries(
          'local-1',
          provider,
          'Sports',
        );
        expect(initial.map((entry) => entry.identity.occurrence), [0, 0, 1]);

        await IptvFavoritesStorage.setIptvCategoryChannelOrder('local-1', 'Sports', [
          initial[1].identity,
          initial[2].identity,
          initial[0].identity,
        ]);
        final withNewRow = [
          ...provider,
          channel('Delta', 'http://h/d', 'Sports'),
        ];
        final ordered = await IptvFavoritesStorage.getIptvCategoryOrderEntries(
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

        final applied = await IptvFavoritesStorage.applyIptvCategoryChannelOrders(
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
      await IptvFavoritesStorage.setIptvChannelFavorited(
        url,
        true,
        channelName: 'News',
      );

      expect(
        (await IptvFavoritesStorage.getIptvListChannels(
          IptvFavoritesStorage.iptvFavoritesListId,
        ))[url]!['name'],
        'News',
      );
      expect(await IptvFavoritesStorage.getIptvFavoriteChannelUrls(), {url});

      await IptvFavoritesStorage.setIptvChannelFavorited(url, false);
      expect(await IptvFavoritesStorage.getIptvFavoriteChannels(), isEmpty);
    });
  });
}
