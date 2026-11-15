import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_browse.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Jumping by channel number from the Android TV player's toolbar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  IptvChannel live(String name, int number, String group) => IptvChannel(
    name: name,
    url: 'http://example.test/$name',
    group: group,
    channelNumber: number,
    contentType: 'live',
  );

  Future<Map<String, dynamic>?> jump(
    IptvPlaylist source,
    List<IptvChannel> channels,
    int number,
  ) {
    final settings = IptvSettingsState()
      ..playlists = [source]
      ..selectedPlaylist = source;
    final catalog = IptvCatalogState()..allChannels = channels;
    final browse = IptvPlayerBrowse((
      catalogState: catalog,
      playerState: IptvPlayerState(),
      settingsState: settings,
      fullCategoryList: () => const [],
      loadPlaylist: (_, {userRequested = false}) async {},
      mounted: () => true,
      playerChannelPayload: (entries) async => [
        for (final e in entries)
          {'name': e.channel.name, 'channelNumber': e.channel.channelNumber},
      ],
      playerSourcePayload: () => const [],
      setState: (fn) => fn(),
    ));
    return browse.providePlayerIptvBrowse({
      'action': 'channelNumber',
      'sourceId': source.id,
      'contentType': 'live',
      'channelNumber': number,
      'limit': 50,
    });
  }

  final favorites = IptvPlaylist(
    id: 'favorites',
    name: 'Favorites',
    url: 'favorites://',
    addedAt: DateTime(2026),
  );
  final provider = IptvPlaylist(
    id: 'provider',
    name: 'Provider',
    url: 'http://example.test/list.m3u',
    addedAt: DateTime(2026),
  );
  final mixed = [
    live('News One', 101, 'News'),
    live('Sports One', 205, 'Sports'),
    live('News Two', 102, 'News'),
  ];

  test('favorites jump finds the number and keeps the whole list', () async {
    final response = await jump(favorites, mixed, 205);

    expect(response!['channelNotFound'], isNull);
    expect(response['selectedCategory'], isNull);
    expect(response['totalChannels'], 3);
    expect((response['channels'] as List).map((c) => c['name']), [
      'News One',
      'Sports One',
      'News Two',
    ]);
    expect(response['anchorIndex'], 1);
  });

  test('a custom list jump also keeps the whole list', () async {
    final list = IptvPlaylist(
      id: 'list',
      name: 'Evening',
      url: 'list://evening',
      addedAt: DateTime(2026),
    );
    final response = await jump(list, mixed, 102);

    expect(response!['selectedCategory'], isNull);
    expect(response['totalChannels'], 3);
    expect(response['anchorIndex'], 2);
  });

  test('favorites jump to a missing number reports not found', () async {
    final response = await jump(favorites, mixed, 999);

    expect(response!['channelNotFound'], isTrue);
  });

  test('a duplicate number in favorites lands on the first match', () async {
    final duplicated = [...mixed, live('Other Provider News', 101, 'Local')];
    final response = await jump(favorites, duplicated, 101);

    expect(response!['anchorIndex'], 0);
  });

  test('a provider jump still narrows to the channel category', () async {
    final response = await jump(provider, mixed, 102);

    expect(response!['selectedCategory'], 'News');
    expect(response['totalChannels'], 2);
    expect((response['channels'] as List).map((c) => c['name']), [
      'News One',
      'News Two',
    ]);
  });
}
