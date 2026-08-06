import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/iptv_transfer_payload.dart';
import 'package:debrify/services/storage_service.dart';

/// Moving a user's IPTV setup between devices — the shared payload behind both
/// the backup file and the phone→TV transfer.
///
/// The cases that matter are the ones a naive copy gets wrong: the same panel
/// added independently on two devices (different ids, same server), a transfer
/// run twice, and memberships that have to keep pointing at the provider they
/// came from.
void main() {
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

  IptvPlaylist xtream({
    required String id,
    String name = 'Panel',
    String server = 'http://panel.example:8080',
    String user = 'alice',
  }) {
    return IptvPlaylist(
      id: id,
      name: name,
      // Empty, exactly as the app stores an Xtream provider: its identity is
      // server + account, and every request is built from those. A fixture
      // that invented a get.php url here was more realistic than reality, and
      // hid an importer that refused every real Xtream entry.
      url: '',
      serverUrl: server,
      username: user,
      password: 'pw',
      addedAt: DateTime(2026, 1, 1),
    );
  }

  group('providers', () {
    test('round-trips a provider onto a fresh device', () async {
      await StorageService.setIptvPlaylists([xtream(id: 'p1')]);
      final payload = await IptvTransferPayload.buildPlaylists();

      await StorageService.setIptvPlaylists(const []);
      final counts = await IptvTransferPayload.applyPlaylists(payload);

      expect(counts.imported, 1);
      final restored = await StorageService.getIptvPlaylists();
      expect(restored, hasLength(1));
      // The id has to survive: favorites and lists name it as their origin.
      expect(restored.single.id, 'p1');
      expect(restored.single.password, 'pw');
    });

    test('applying the same payload twice adds nothing', () async {
      await StorageService.setIptvPlaylists([xtream(id: 'p1')]);
      final payload = await IptvTransferPayload.buildPlaylists();

      final second = await IptvTransferPayload.applyPlaylists(payload);

      expect(second.imported, 0);
      expect(second.alreadyPresent, 1);
      expect(await StorageService.getIptvPlaylists(), hasLength(1));
    });

    test('the same panel under a different id is not duplicated', () async {
      await StorageService.setIptvPlaylists([xtream(id: 'local-id')]);

      final counts = await IptvTransferPayload.applyPlaylists([
        xtream(id: 'phone-id', name: 'Same panel, other name').toJson(),
      ]);

      expect(counts.alreadyPresent, 1);
      expect(await StorageService.getIptvPlaylists(), hasLength(1));
    });

    test('a different account on the same server is a separate provider',
        () async {
      await StorageService.setIptvPlaylists([xtream(id: 'p1', user: 'alice')]);

      final counts = await IptvTransferPayload.applyPlaylists([
        xtream(id: 'p2', user: 'bob').toJson(),
      ]);

      expect(counts.imported, 1);
      expect(await StorageService.getIptvPlaylists(), hasLength(2));
    });

    test('an id collision with a different provider is refused', () async {
      await StorageService.setIptvPlaylists([xtream(id: 'shared')]);

      final counts = await IptvTransferPayload.applyPlaylists([
        xtream(id: 'shared', server: 'http://other.example:8080').toJson(),
      ]);

      // Playlist equality is id-only, so accepting this would make one of the
      // two unreachable.
      expect(counts.imported, 0);
      expect(counts.failed, 1);
      expect(await StorageService.getIptvPlaylists(), hasLength(1));
    });

    test('a virtual playlist in the payload is refused', () async {
      // Favorites / list / Continue-watching shelves are rebuilt from their
      // backing store on every load. One persisted from an older or hand-
      // edited payload would come back twice under a single id, and id-only
      // equality would start resolving the stale copy.
      final counts = await IptvTransferPayload.applyPlaylists([
        IptvPlaylist(
          id: 'list_123',
          name: 'Sports',
          url: 'list://list_123',
          addedAt: DateTime(2026, 1, 1),
        ).toJson(),
      ]);

      expect(counts.imported, 0);
      expect(counts.failed, 1);
      expect(await StorageService.getIptvPlaylists(), isEmpty);
    });

    test('an Xtream provider imports despite carrying no url', () async {
      // The url is the fetchable address of an M3U provider; an Xtream one has
      // none and is reached through server + account instead. Judging it by the
      // url dropped every Xtream panel on arrival — over Remote and over a
      // backup restore — while a single already-present M3U provider made the
      // TV report "already up to date".
      final counts = await IptvTransferPayload.applyPlaylists([
        xtream(id: 'p1', name: 'trex').toJson(),
      ]);

      expect(counts.imported, 1);
      expect(counts.failed, 0);
      final restored = await StorageService.getIptvPlaylists();
      expect(restored.single.serverUrl, 'http://panel.example:8080');
      expect(restored.single.username, 'alice');
      expect(restored.single.password, 'pw');
    });

    test('an entry with neither a url nor a server is still refused', () async {
      final counts = await IptvTransferPayload.applyPlaylists([
        IptvPlaylist(
          id: 'junk',
          name: 'Nothing to fetch',
          url: '   ',
          addedAt: DateTime(2026, 1, 1),
        ).toJson(),
      ]);

      expect(counts.imported, 0);
      expect(counts.failed, 1);
      expect(await StorageService.getIptvPlaylists(), isEmpty);
    });

    test('file-imported playlists are left out, and are counted so the UI '
        'can say so', () async {
      await StorageService.setIptvPlaylists([
        xtream(id: 'p1'),
        IptvPlaylist(
          id: 'file1',
          name: 'From file',
          url: 'file:///tmp/list.m3u',
          content: '#EXTM3U\n#EXTINF:-1,One\nhttp://a/1',
          addedAt: DateTime(2026, 1, 1),
        ),
      ]);

      final payload = await IptvTransferPayload.buildPlaylists();
      expect(payload, hasLength(1));
      expect(payload.single['id'], 'p1');

      final counts = await IptvTransferPayload.countPlaylists();
      expect(counts.transferable, 1);
      expect(counts.fileImported, 1);
    });

    test('a file-imported playlist\'s starred channels still travel',
        () async {
      // The provider stays behind, but a membership carries its own playable
      // URL and headers — those channels keep working on the other device.
      await IptvMediaStore.setChannelFavorited(
        'http://cdn.example/from-file.ts',
        true,
        channelName: 'From a file playlist',
        playlistId: 'file1',
      );

      final favorites = await IptvTransferPayload.buildFavorites();

      expect(favorites, hasLength(1));
      expect(favorites.single['url'], 'http://cdn.example/from-file.ts');
    });
  });

  group('favorites', () {
    test('round-trips starred channels with their playback headers', () async {
      await IptvMediaStore.setChannelFavorited(
        'http://panel.example:8080/live/alice/pw/1.ts',
        true,
        channelName: 'News HD',
        group: 'News',
        playlistId: 'p1',
        contentType: 'live',
        httpHeaders: const {'User-Agent': 'CustomUA/1.0'},
      );
      final payload = await IptvTransferPayload.buildFavorites();
      expect(payload, hasLength(1));

      await IptvMediaStore.setChannelFavorited(
        'http://panel.example:8080/live/alice/pw/1.ts',
        false,
      );
      final counts = await IptvTransferPayload.applyFavorites(payload);

      expect(counts.channelsImported, 1);
      final restored = await IptvMediaStore.favoriteChannels();
      expect(restored, hasLength(1));
      final meta = restored.values.single;
      expect(meta['name'], 'News HD');
      expect(meta['playlistId'], 'p1');
      // A channel that lost its UA would list fine and then refuse to play.
      expect(meta['httpHeaders'], {'User-Agent': 'CustomUA/1.0'});
    });

    test('a channel re-binds to the local id for the same panel', () async {
      // The sending device knows this panel as "phone-id"; this one already
      // knows it as "tv-id". A membership left pointing at "phone-id" would
      // resolve to no provider here — costing the channel its Xtream
      // credentials on resume, and leaving it behind when the provider is
      // later deleted.
      await StorageService.setIptvPlaylists([xtream(id: 'phone-id')]);
      final favorites = await IptvTransferPayload.buildFavorites();
      expect(favorites, isEmpty);

      await IptvMediaStore.setChannelFavorited(
        'http://panel.example:8080/live/alice/pw/5.ts',
        true,
        channelName: 'Five',
        playlistId: 'phone-id',
      );
      final payload = await IptvTransferPayload.buildFavorites();

      // Now stand up a "receiving device": same panel, different local id, and
      // no memberships yet.
      await StorageService.setIptvPlaylists([xtream(id: 'tv-id')]);
      await IptvMediaStore.setChannelFavorited(
        'http://panel.example:8080/live/alice/pw/5.ts',
        false,
      );

      await IptvTransferPayload.applyFavorites(payload);

      final restored = await IptvMediaStore.favoriteChannels();
      expect(restored.values.single['playlistId'], 'tv-id');
    });

    test('a channel from a panel this device lacks keeps its origin id',
        () async {
      await IptvMediaStore.setChannelFavorited(
        'http://elsewhere/1.ts',
        true,
        channelName: 'Elsewhere',
        playlistId: 'unknown-provider',
      );
      final payload = await IptvTransferPayload.buildFavorites();
      await IptvMediaStore.setChannelFavorited('http://elsewhere/1.ts', false);

      await IptvTransferPayload.applyFavorites(payload);

      final restored = await IptvMediaStore.favoriteChannels();
      expect(restored.values.single['playlistId'], 'unknown-provider');
    });

    test('re-applying favorites does not duplicate them', () async {
      await IptvMediaStore.setChannelFavorited(
        'http://a/1.ts',
        true,
        channelName: 'One',
      );
      final payload = await IptvTransferPayload.buildFavorites();

      final counts = await IptvTransferPayload.applyFavorites(payload);

      expect(counts.channelsImported, 0);
      expect(counts.channelsAlreadyPresent, 1);
      expect(await IptvMediaStore.favoriteChannels(), hasLength(1));
    });
  });

  group('custom lists', () {
    test('round-trips lists with their channels', () async {
      final sports = await IptvMediaStore.createList('Sports');
      await IptvMediaStore.setChannelInList(
        sports,
        'http://a/sport.ts',
        true,
        channelName: 'Sport 1',
      );
      final payload = await IptvTransferPayload.buildCustomLists();
      expect(payload, hasLength(1));
      expect(IptvTransferPayload.countListChannels(payload), 1);

      await IptvMediaStore.deleteList(sports);
      final counts = await IptvTransferPayload.applyCustomLists(payload);

      expect(counts.imported, 1);
      expect(counts.channelsImported, 1);
      final lists = await IptvMediaStore.lists();
      expect(lists.where((l) => !l.isBuiltin).single.name, 'Sports');
    });

    test('an existing list of the same name is topped up, not duplicated',
        () async {
      final sports = await IptvMediaStore.createList('Sports');
      await IptvMediaStore.setChannelInList(sports, 'http://a/1.ts', true);

      final counts = await IptvTransferPayload.applyCustomLists([
        {
          'name': 'sports',
          'channels': [
            {'url': 'http://a/1.ts', 'name': 'Already here'},
            {'url': 'http://a/2.ts', 'name': 'New'},
          ],
        },
      ]);

      expect(counts.imported, 0);
      expect(counts.alreadyPresent, 1);
      expect(counts.channelsImported, 1);
      expect(counts.channelsAlreadyPresent, 1);

      final custom =
          (await IptvMediaStore.lists()).where((l) => !l.isBuiltin).toList();
      expect(custom, hasLength(1));
      expect(custom.single.channelCount, 2);
    });

    test('Favorites is never exported as a custom list', () async {
      await IptvMediaStore.setChannelFavorited('http://a/1.ts', true);
      expect(await IptvTransferPayload.buildCustomLists(), isEmpty);
    });

    test('a nameless entry is counted as failed, not silently dropped',
        () async {
      final counts = await IptvTransferPayload.applyCustomLists([
        {'name': '   ', 'channels': const []},
      ]);

      expect(counts.failed, 1);
      expect(counts.imported, 0);
    });
  });
}
