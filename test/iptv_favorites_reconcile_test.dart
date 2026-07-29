import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/storage_service.dart';

/// Coverage for the IPTV favorites URL migration.
///
/// It rewrites stored favorite keys in place when a freshly fetched channel
/// matches an existing favorite canonically but not literally (e.g. stars
/// saved before the Xtream `/live/` URL fix). That makes it a destructive
/// edit of user data, and it runs on every catalog load — including the
/// background revalidate, while the page is on screen and the user can be
/// starring things. The scan yields to the event loop to keep a 50k-channel
/// playlist from freezing the UI, so "someone else wrote to this key while we
/// were scanning" is a real, reachable interleaving rather than a thought
/// experiment.
void main() {
  const key = 'iptv_favorite_channels_v1';

  Future<Map<String, dynamic>> readFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> seed(Map<String, dynamic> value) async {
    SharedPreferences.setMockInitialValues({key: jsonEncode(value)});
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    expect((result.values.single as Map)['name'], 'Sky',
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
    // reverting anything saved in between.
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

  test('nothing is written when there is nothing to migrate', () async {
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

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNull);
  });
}
