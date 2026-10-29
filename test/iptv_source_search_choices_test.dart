// Title source search honours the profile's IPTV choices.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/source_search_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  const movie = AdvancedSearchSelection(
    imdbId: 'tt1',
    isSeries: false,
    title: 'Dune',
    year: '2021',
  );
  IptvPlaylist playlist(String id) => IptvPlaylist(
    id: id,
    name: 'TV $id',
    url: '',
    serverUrl: 'https://$id.test',
    username: 'user',
    password: 'secret',
    addedAt: DateTime(2026),
  );
  final a = playlist('playlist-a');
  final b = playlist('playlist-b');

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'iptv-choices-test');
    SharedPreferences.setMockInitialValues({
      'iptv_playlists': [jsonEncode(a.toJson()), jsonEncode(b.toJson())],
    });
    dir = await Directory.systemTemp.createTemp('iptv-choices');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
    for (final p in [a, b]) {
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: IptvCatalogKey.forPlaylist(p, 'vod')!,
        channels: [
          IptvChannel(
            name: 'Dune (2021)',
            url: 'https://${p.id}.test/movie/1.mp4',
            contentType: 'vod',
          ),
        ],
      );
    }
  });
  tearDown(() async {
    await IptvCatalogRefreshService.instance.debugSettle();
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    ProfileRuntime.debugReset();
    await dir.delete(recursive: true);
  });

  Future<Set<String>> searchedPlaylists() async => {
    for (final r in await IptvSourceSearch.search(movie)) r.name,
  };

  test('by default every playlist is searched', () async {
    expect(await searchedPlaylists(), {'TV playlist-a', 'TV playlist-b'});
  });

  test('an excluded playlist is not searched', () async {
    await SourceSearchPreferences.write(
      const SourceSearchChoices(excludedPlaylistIds: {'playlist-a'}),
    );
    expect(await searchedPlaylists(), {'TV playlist-b'});
  });

  test('IPTV off searches no playlist', () async {
    await SourceSearchPreferences.write(const SourceSearchChoices(iptv: false));
    expect(await IptvSourceSearch.search(movie), isEmpty);
  });
}
