import 'dart:convert';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_plex_server.dart';

void main() {
  late FakePlexServer server;
  late MediaServerClient client;
  final account = plexAccount();

  http.Response json(Object body) => http.Response(jsonEncode(body), 200);

  setUp(() {
    server = FakePlexServer(
      handler: (r) {
        final path = r.url.path;
        if (path.endsWith('/library/metadata/4/children')) {
          return json(plexFixture('season_children'));
        }
        if (path.endsWith('/photo/:/transcode')) {
          return r.url.queryParameters['url'] == '/library/metadata/2/thumb'
              ? http.Response.bytes([1, 2, 3], 200)
              : http.Response('none', 404);
        }
        return null;
      },
    );
    client = MediaServerClient(client: server.client);
  });

  tearDown(() => client.close());

  Map<String, String> lastQuery() => server.requests.last.url.queryParameters;

  test(
    'libraries are the server sections, with their collection types',
    () async {
      final views = await client.library(account, views: true);
      expect(views.items.map((i) => (i.id, i.name, i.isFolder)), [
        ('s1', 'Movies', true),
        ('s2', 'TV Shows', true),
      ]);
      expect(views.items.map((i) => i.data['CollectionType']), [
        'movies',
        'tvshows',
      ]);
      expect(views.nextOffset, isNull);
    },
  );

  test('a library page sorts, pages and searches by title', () async {
    final page = await client.library(
      account,
      parentId: 's1',
      sort: 'DateCreated',
      offset: 60,
    );
    expect(page.items.every((i) => i.playable), isTrue);
    expect(lastQuery(), {
      'X-Plex-Container-Start': '60',
      'X-Plex-Container-Size': '60',
      'sort': 'addedAt:desc',
    });
    expect(page.nextOffset, isNull);

    await client.library(account, parentId: 's1', search: ' dead ');
    expect(lastQuery()['title'], 'dead');
    expect(lastQuery()['sort'], 'titleSort');
    await client.library(account, parentId: 's1', sort: 'ProductionYear');
    expect(lastQuery()['sort'], 'year:desc');
  });

  test('recent and resume rows ask for videos, not shows', () async {
    await client.library(account, parentId: 's2', mode: 'recent');
    expect(lastQuery()['type'], '4');
    expect(lastQuery()['sort'], 'addedAt:desc');
    await client.library(account, parentId: 's1', mode: 'resume');
    expect(lastQuery()['type'], '1');
    expect(lastQuery()['inProgress'], '1');
    expect(lastQuery()['sort'], 'lastViewedAt:desc');
  });

  test('a show opens its seasons and a season its numbered episodes', () async {
    final seasons = await client.library(account, parentId: '3');
    expect(seasons.items.single.type, 'Season');
    expect(seasons.items.single.isFolder, isTrue);
    final episodes = await client.library(
      account,
      parentId: seasons.items.single.id,
      episodeOrder: true,
    );
    expect(episodes.items.map((i) => (i.season, i.episode)), [(1, 1), (1, 2)]);
    expect(
      episodes.items.every((i) => i.numberedEpisode && i.playable),
      isTrue,
    );
  });

  test('ids that are not Plex ids and unknown queries are refused', () {
    expect(
      () => client.library(account, parentId: 's1/../2'),
      throwsArgumentError,
    );
    expect(
      () => client.library(account, parentId: '../3'),
      throwsArgumentError,
    );
    expect(
      () => client.library(account, parentId: 's1', sort: 'Random'),
      throwsArgumentError,
    );
    expect(
      () => client.libraryImage(account, 'x/../2'),
      throwsA(isA<MediaServerException>()),
    );
  });

  test(
    'artwork comes resized through the token header; none is null',
    () async {
      expect(await client.libraryImage(account, '2'), [1, 2, 3]);
      final request = server.requests.last;
      expect(request.url.queryParameters['width'], '360');
      expect(request.headers['X-Plex-Token'], plexToken);
      expect(request.url.toString(), isNot(contains(plexToken)));
      expect(await client.libraryImage(account, '5'), isNull);
    },
  );

  test('an item refreshes from the server before playback', () async {
    final item = await client.libraryItem(account, '2');
    expect(item.name, 'Night of the Living Dead');
    expect(item.playable, isTrue);
  });
}
