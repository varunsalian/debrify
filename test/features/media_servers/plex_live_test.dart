// Opt-in checks against a local Plex Media Server (no account needed):
//   docker run -d --name plexprobe -p 32400:32400 -e ALLOWED_NETWORKS=0.0.0.0/0 \
//     -v <config>:/config -v <media>:/data plexinc/pms-docker
// with a Movies library (Plex Movie agent) holding "Night of the Living Dead
// (1968)", "Big Buck Bunny (2008)" and a 10-minute "Nosferatu (1922)", and a
// TV library (Plex TV Series agent) with "Breaking Bad (2008)" S01E01-E02.
//   DEBRIFY_PLEX_LIVE=1 flutter test --no-pub test/features/media_servers/plex_live_test.dart
// Watch state changed here is restored afterwards.
import 'dart:io';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final live = Platform.environment['DEBRIFY_PLEX_LIVE'] == '1';
  final base =
      Platform.environment['DEBRIFY_PLEX_LIVE_URL'] ??
      'http://localhost:32400/';
  late MediaServerClient client;
  late MediaServerAccount account;

  setUpAll(() async {
    if (!live) return;
    final probe = http.Client();
    final identity = await probe.get(
      Uri.parse('${base}identity'),
      headers: {'Accept': 'application/json'},
    );
    probe.close();
    final serverId = RegExp(
      r'"machineIdentifier":"([^"]+)"',
    ).firstMatch(identity.body)![1]!;
    client = MediaServerClient();
    account = await client.resolve(
      MediaServerAccount(
        kind: MediaServerKind.plex,
        baseUrl: base,
        userId: 'live-test',
        token: 'live-test-token-0001',
        serverId: serverId,
        deviceId: 'debrifylivetest0001',
        connections: [MediaServerConnection(uri: base)],
      ),
      cacheScope: 'plex-live',
    );
  });

  tearDownAll(() {
    if (live) client.close();
  });

  Future<String> movieKey(String id) async =>
      (await client.findItems(account, id: id, isMovie: true)).single['Id']
          as String;

  test('connection test passes', () async {
    await client.testConnection(account);
  }, skip: !live);

  test('movies and an episode are found by exact ids', () async {
    expect(await movieKey('tt0063350'), isNotEmpty);
    expect(await movieKey('tmdb:10378'), isNotEmpty);
    final episode = await client.findItems(
      account,
      id: 'tvdb:81189',
      isMovie: false,
      season: 1,
      episode: 2,
    );
    expect(episode.single['Type'], 'Episode');
    expect(episode.single['IndexNumber'], 2);
    expect(
      await client.findItems(account, id: 'tt9999999', isMovie: true),
      isEmpty,
    );
  }, skip: !live);

  test('the playback URL serves the file with the token as a header', () async {
    final key = await movieKey('tt0063350');
    final source = (await client.mediaSources(account, key)).first;
    final url = MediaServerClient.playbackUrl(
      account,
      key,
      source['Id'] as String,
    );
    final response = await http.Client().send(
      http.Request('GET', url)
        ..headers.addAll({
          ...MediaServerClient.headers(
            account.deviceId,
            account.token,
            MediaServerKind.plex,
          ),
          'Range': 'bytes=0-99',
        }),
    );
    expect(response.statusCode, 206);
    expect((await response.stream.toBytes()).length, 100);
  }, skip: !live);

  test('progress round-trips through the timeline and is restored', () async {
    final key = await movieKey('tmdb:653');
    final before = await client.watchState(account, key);
    Future<void> report(int position) => client.reportWatchProgress(
      account,
      itemId: key,
      mediaSourceId: 'unused',
      playSessionId: 'livetestsession01',
      action: 'stop',
      positionMs: position,
      paused: false,
      durationMs: before.durationMs,
    );
    try {
      await report(123000);
      expect((await client.watchState(account, key)).positionMs, 123000);
    } finally {
      if (before.positionMs > 0) await report(before.positionMs);
    }
  }, skip: !live);

  test('marking watched is visible, then undone', () async {
    final key = await movieKey('tmdb:10378');
    expect((await client.watchState(account, key)).played, isFalse);
    try {
      await client.markWatched(account, key);
      expect((await client.watchState(account, key)).played, isTrue);
    } finally {
      await http.Client().get(
        Uri.parse(
          '$base:/unscrobble?key=$key&identifier=com.plexapp.plugins.library',
        ),
      );
    }
  }, skip: !live);

  test('libraries, a section page and a show open in Discover', () async {
    final views = await client.library(account, views: true);
    expect(
      views.items.map((i) => i.data['CollectionType']),
      containsAll(['movies', 'tvshows']),
    );
    final movies = views.items.firstWhere(
      (i) => i.data['CollectionType'] == 'movies',
    );
    final page = await client.library(account, parentId: movies.id);
    expect(page.items.where((i) => i.playable), isNotEmpty);
    final recent = await client.library(
      account,
      parentId: movies.id,
      mode: 'recent',
    );
    expect(recent.items, isNotEmpty);
    final shows = views.items.firstWhere(
      (i) => i.data['CollectionType'] == 'tvshows',
    );
    final show = (await client.library(
      account,
      parentId: shows.id,
    )).items.first;
    expect(show.isFolder, isTrue);
    final seasons = await client.library(account, parentId: show.id);
    final episodes = await client.library(
      account,
      parentId: seasons.items.first.id,
    );
    expect(episodes.items.every((i) => i.numberedEpisode), isTrue);
    expect(await client.libraryImage(account, page.items.first.id), isNotNull);
  }, skip: !live);
}
