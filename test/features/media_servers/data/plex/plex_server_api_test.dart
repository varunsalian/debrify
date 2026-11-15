import 'dart:io';

import 'package:debrify/features/media_servers/data/plex/plex_connection_resolver.dart';
import 'package:debrify/features/media_servers/models/media_server_errors.dart';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_plex_server.dart';

void main() {
  late FakePlexServer server;
  late MediaServerClient client;
  final account = plexAccount();

  MediaServerClient clientFor(FakePlexServer fake) =>
      MediaServerClient(client: fake.client);

  setUp(() {
    server = FakePlexServer();
    client = clientFor(server);
  });

  tearDown(() => client.close());

  void expectTokenOnlyInHeaders(List<http.Request> requests) {
    for (final request in requests) {
      expect(request.url.toString(), isNot(contains(plexToken)));
      expect(request.followRedirects, isFalse);
    }
  }

  group('exact id lookup', () {
    test(
      'a movie is found through the agent match and its Guid list',
      () async {
        for (final id in ['tt0063350', 'tmdb:10331']) {
          final items = await client.findItems(account, id: id, isMovie: true);
          expect(items.map((i) => (i['Id'], i['Name'], i['Type'])), [
            ('2', 'Night of the Living Dead', 'Movie'),
          ], reason: id);
        }
        final match = server.requests.firstWhere(
          (r) => r.url.path.endsWith('/matches'),
        );
        expect(match.url.queryParameters['agent'], 'tv.plex.agents.movie');
        expect(match.url.queryParameters['language'], 'en-US');
        expect(match.url.queryParameters['manual'], '1');
        expectTokenOnlyInHeaders(server.requests);
      },
    );

    test('an unknown id finds nothing', () async {
      expect(
        await client.findItems(account, id: 'tt9999999', isMovie: true),
        isEmpty,
      );
    });

    test('an episode is found in one filtered call', () async {
      final items = await client.findItems(
        account,
        id: 'tvdb:81189',
        isMovie: false,
        season: 1,
        episode: 2,
      );
      expect(items.single['Id'], '6');
      expect(items.single['Type'], 'Episode');
      expect(items.single['ParentIndexNumber'], 1);
      expect(items.single['IndexNumber'], 2);
      final episodeQuery = server.requests
          .lastWhere((r) => r.url.queryParameters['type'] == '4')
          .url
          .queryParameters;
      expect(episodeQuery['show.id'], '3');
      expect(episodeQuery['season.index'], '1');
      expect(episodeQuery['episode.index'], '2');
    });

    test('a refused agent match falls back to scanning the library', () async {
      server = FakePlexServer(
        handler: (r) => r.url.path.endsWith('/matches')
            ? http.Response('forbidden', 403)
            : null,
      );
      client = clientFor(server);
      final items = await client.findItems(
        account,
        id: 'tt0063350',
        isMovie: true,
      );
      expect(items.single['Id'], '2');
      expect(
        server.requests.any(
          (r) =>
              r.url.path.endsWith('/library/sections/1/all') &&
              r.url.queryParameters['includeGuids'] == '1' &&
              r.url.queryParameters['X-Plex-Container-Size'] == '500',
        ),
        isTrue,
      );
    });

    test('a legacy-agent library is scanned, never matched', () async {
      server = FakePlexServer(movieAgent: 'com.plexapp.agents.imdb');
      client = clientFor(server);
      final items = await client.findItems(
        account,
        id: 'tmdb:10331',
        isMovie: true,
      );
      expect(items.single['Id'], '2');
      expect(
        server.requests.any((r) => r.url.path.endsWith('/matches')),
        isFalse,
      );
    });

    test('a library with no id agent is skipped', () async {
      server = FakePlexServer(movieAgent: 'tv.plex.agents.none');
      client = clientFor(server);
      expect(
        await client.findItems(account, id: 'tt0063350', isMovie: true),
        isEmpty,
      );
      expect(
        server.requests.any((r) => r.url.path.contains('/library/sections/1/')),
        isFalse,
      );
    });

    test(
      'a revoked token while scanning is an error, not "no match"',
      () async {
        server = FakePlexServer(
          movieAgent: 'com.plexapp.agents.imdb',
          handler: (r) => r.url.path.endsWith('/library/sections/1/all')
              ? http.Response('unauthorized', 401)
              : null,
        );
        client = clientFor(server);
        await expectLater(
          client.findItems(account, id: 'tt0063350', isMovie: true),
          throwsA(isA<MediaServerAuthError>()),
        );
      },
    );

    test('a network failure mid-scan fails the search', () async {
      server = FakePlexServer(
        movieAgent: 'com.plexapp.agents.imdb',
        handler: (r) => r.url.path.endsWith('/library/sections/1/all')
            ? throw http.ClientException('connection reset')
            : null,
      );
      client = clientFor(server);
      var incomplete = false;
      await expectLater(
        client.findItems(
          account,
          id: 'tt0063350',
          isMovie: true,
          onIncomplete: () => incomplete = true,
        ),
        throwsA(isA<MediaServerUnreachable>()),
      );
      expect(incomplete, isFalse);
    });

    test('running out of time reports an incomplete search', () async {
      var now = DateTime(2026, 11, 15);
      server = FakePlexServer(
        handler: (r) {
          if (r.url.path.endsWith('/matches')) {
            now = now.add(const Duration(seconds: 30));
          }
          return null;
        },
      );
      client = MediaServerClient(client: server.client, lookupClock: () => now);
      var incomplete = false;
      final items = await client.findItems(
        account,
        id: 'tt0063350',
        isMovie: true,
        onIncomplete: () => incomplete = true,
      );
      expect(incomplete, isTrue);
      expect(items, isEmpty);
    });
  });

  group('playback', () {
    test('each single-file version is a direct-play source', () async {
      final sources = await client.mediaSources(account, '2');
      expect(sources.single['Id'], '2_mkv');
      final metadata = server.requests.last;
      expect(metadata.url.queryParameters['checkFiles'], '1');
      final url = MediaServerClient.playbackUrl(account, '2', '2_mkv');
      expect(
        url.toString(),
        'https://local.example.plex.direct:32400/library/parts/2/file.mkv',
      );
      final headers = MediaServerClient.headers(
        account.deviceId,
        account.token,
        MediaServerKind.plex,
      );
      expect(headers['X-Plex-Token'], plexToken);
      expect(headers['X-Plex-Client-Identifier'], plexClient);
      expect(headers.containsKey('Authorization'), isFalse);
      expectTokenOnlyInHeaders(server.requests);
    });

    test('identifiers from a server are validated before use', () {
      expect(
        () => MediaServerClient.playbackUrl(account, '2', '../2_mkv'),
        throwsA(isA<MediaServerException>()),
      );
      expect(
        () => client.mediaSources(account, '2/../../x'),
        throwsA(isA<MediaServerException>()),
      );
      expect(
        () => MediaServerClient.headers(
          'bad id!',
          plexToken,
          MediaServerKind.plex,
        ),
        throwsA(isA<MediaServerException>()),
      );
    });

    test('a redirect is refused, so the token never follows it', () async {
      server = FakePlexServer(
        handler: (r) => r.url.path.endsWith('/library/metadata/2')
            ? http.Response('', 302, headers: {'location': 'https://evil/'})
            : null,
      );
      client = clientFor(server);
      await expectLater(
        client.mediaSources(account, '2'),
        throwsA(isA<MediaServerHttpError>()),
      );
      expect(server.requests.where((r) => r.url.host == 'evil'), isEmpty);
    });

    test('connection test checks identity and then the token', () async {
      await client.testConnection(account);
      expect(
        server.requests.map((r) => r.url.path.split('/').last),
        containsAllInOrder(['identity', 'identity', 'sections']),
      );
      server = FakePlexServer(
        handler: (r) => r.url.path.endsWith('/library/sections')
            ? http.Response('unauthorized', 401)
            : null,
      );
      client = clientFor(server);
      await expectLater(
        client.testConnection(account),
        throwsA(isA<MediaServerAuthError>()),
      );
    });
  });

  group('watch state', () {
    test('resume position and played state come from the item', () async {
      final state = await client.watchState(account, '16');
      expect(state.positionMs, 91000);
      expect(state.durationMs, greaterThan(600000));
      expect(state.played, isFalse);
      expect(await client.watchSessionId(account, '16'), isNull);
    });

    test('progress goes to the timeline with its duration', () async {
      await client.reportWatchProgress(
        account,
        itemId: '16',
        mediaSourceId: '16_mkv',
        playSessionId: 'abcdef0123456789',
        action: 'progress',
        positionMs: 120000,
        paused: true,
        durationMs: 600000,
      );
      final report = server.requests.single;
      expect(report.method, 'GET');
      expect(report.url.path, endsWith('/:/timeline'));
      expect(report.url.queryParameters, {
        'ratingKey': '16',
        'key': '/library/metadata/16',
        'identifier': 'com.plexapp.plugins.library',
        'state': 'paused',
        'time': '120000',
        'duration': '600000',
      });
      expect(report.headers['X-Plex-Session-Identifier'], 'abcdef0123456789');
      expectTokenOnlyInHeaders(server.requests);
    });

    test(
      'a report without a duration is not sent, as Plex would drop it',
      () async {
        await client.reportWatchProgress(
          account,
          itemId: '16',
          mediaSourceId: '16_mkv',
          playSessionId: 'abcdef0123456789',
          action: 'stop',
          positionMs: 120000,
          paused: false,
        );
        expect(server.requests, isEmpty);
      },
    );

    test('marking watched scrobbles the item', () async {
      await client.markWatched(account, '16');
      final request = server.requests.single;
      expect(request.url.path, endsWith('/:/scrobble'));
      expect(request.url.queryParameters, {
        'key': '16',
        'identifier': 'com.plexapp.plugins.library',
      });
    });
  });

  test('an authorization callback keeps its own error type', () async {
    await expectLater(
      client.mediaSources(
        account,
        '2',
        authorize: () async => throw const FormatException('profile store'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('an agent request that fails falls back to scanning', () async {
    server = FakePlexServer(
      handler: (r) => r.url.path.endsWith('/matches')
          ? http.Response('agent unavailable', 500)
          : null,
    );
    client = clientFor(server);
    final items = await client.findItems(
      account,
      id: 'tt0063350',
      isMovie: true,
    );
    expect(items.single['Id'], '2');
  });

  test('an id the agent does not know costs no library scan', () async {
    expect(
      await client.findItems(account, id: 'tt9999999', isMovie: true),
      isEmpty,
    );
    expect(
      server.requests.where(
        (r) =>
            r.url.queryParameters['includeGuids'] == '1' &&
            r.url.queryParameters['X-Plex-Container-Size'] == '500',
      ),
      isEmpty,
    );
  });

  group('address fallback', () {
    test('a dead address is replaced by a verified one', () async {
      final home = MediaServerConnection(
        uri: 'https://home.plex.direct:32400/',
      );
      final away = MediaServerConnection(
        uri: 'https://away.plex.direct:32400/',
      );
      final fallback = plexAccount(
        baseUrl: home.uri,
        connections: [home, away],
      );
      server = FakePlexServer(
        handler: (r) => r.url.host == 'home.plex.direct'
            ? throw const SocketException('unreachable')
            : null,
      );
      client = clientFor(server);
      final resolved = await client.resolve(fallback, cacheScope: 'fallback');
      expect(resolved.baseUrl, away.uri);
      final sources = await client.mediaSources(resolved, '2');
      expect(sources, isNotEmpty);
      expect(
        server.requests
            .where((r) => r.url.host == 'home.plex.direct')
            .every((r) => !r.headers.containsKey('X-Plex-Token')),
        isTrue,
      );
      PlexConnectionResolver.forget(fallback);
    });
  });
}
