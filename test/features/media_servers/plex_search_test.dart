import 'dart:io';

import 'package:debrify/features/media_servers/data/media_server_connection_store.dart';
import 'package:debrify/features/media_servers/data/plex/plex_connection_resolver.dart';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_plex_server.dart';

/// Plex through the real search path: profile-owned connection, address
/// fallback, source rows, player headers and watch reports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const home = 'https://home.plex.direct:32400/';
  const away = 'https://away.plex.direct:32400/';
  late Directory temp;
  late ProfileRegistry registry;
  late FakePlexServer server;
  final account = plexAccount(
    baseUrl: home,
    connections: const [
      MediaServerConnection(uri: home),
      MediaServerConnection(uri: away, relay: true),
    ],
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    temp = await Directory.systemTemp.createTemp('plex-search-test-');
    registry = await ProfileRegistry.open(path: '${temp.path}/profiles.db');
    final admin = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: admin,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(List.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin, dataGeneration: 1, sessionEpoch: 1),
    );
    // The home address is down: the server answers only away from home.
    server = FakePlexServer(
      handler: (request) => request.url.host == 'home.plex.direct'
          ? throw const SocketException('no route to host')
          : null,
    );
    MediaServerService.clientFactory = () =>
        MediaServerClient(client: server.client);
    final ticket = await MediaServerConnectionStore.begin(
      kind: MediaServerKind.plex,
    );
    await MediaServerConnectionStore.savePlex(ticket, account, 'Den');
  });

  tearDown(() async {
    PlexConnectionResolver.forget(account);
    MediaServerService.clientFactory = MediaServerClient.new;
    await registry.close();
    await temp.delete(recursive: true);
  });

  Future<List<Torrent>> search() async =>
      ((await MediaServerService.search(
                id: 'tt0063350',
                isMovie: true,
              ))['torrents']
              as List)
          .cast<Torrent>();

  test(
    'sources use the address that answered, with the token as a header',
    () async {
      final source = (await search()).single;

      expect(source.directUrl, '${away}library/parts/2/file.mkv');
      expect(source.httpHeaders?['X-Plex-Token'], plexToken);
      expect(source.directUrl, isNot(contains(plexToken)));
      expect(source.streamLabel, 'Plex · Den');
      expect(source.streamDescription, contains('Relay (limited speed)'));
      expect(source.streamDescription, contains('1080p'));
      expect(MediaServerService.owns(source), isTrue);
      final target = MediaServerService.watchTargetFor(source)!;
      expect(target.account.baseUrl, away);
      expect(target.itemId, '2');
      expect(
        server.requests
            .where((r) => r.url.host == 'home.plex.direct')
            .every((r) => !r.headers.containsKey('X-Plex-Token')),
        isTrue,
      );
    },
  );

  test('watch reports reach the timeline with the playback duration', () async {
    final target = MediaServerService.watchTargetFor((await search()).single)!;
    server.requests.clear();
    final session = MediaServerWatchSession(
      client: MediaServerClient(client: server.client),
      account: target.account,
      itemId: target.itemId,
      mediaSourceId: target.mediaSourceId,
      playSessionId: 'abcdef0123456789',
      authorize: () async {},
    );
    session.observe(positionMs: 120000, durationMs: 600000, playing: true);
    await session.close();

    final reports = server.requests
        .where((r) => r.url.path.endsWith('/:/timeline'))
        .map((r) => r.url.queryParameters)
        .toList();
    expect(reports.map((q) => (q['state'], q['time'], q['duration'])), [
      ('playing', '120000', '600000'),
      ('stopped', '120000', '600000'),
    ]);
    expect(
      server.requests.every((r) => r.url.host == 'away.plex.direct'),
      isTrue,
    );
  });
}
