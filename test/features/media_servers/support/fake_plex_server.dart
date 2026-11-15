import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/media_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Recorded Plex Media Server responses (test/fixtures/media_servers/plex),
/// served by path so client code can run against them.
Map<String, dynamic> plexFixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/media_servers/plex/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

const plexToken = 'plex-token-0123456789';
const plexClient = 'debrifyclient0123456789abcdef';
const plexServerId = 'cff3c0ac2368b3b2930ab860ccc476244cc38b71';

MediaServerAccount plexAccount({
  String baseUrl = 'https://local.example.plex.direct:32400/',
  List<MediaServerConnection>? connections,
}) => MediaServerAccount(
  kind: MediaServerKind.plex,
  baseUrl: baseUrl,
  userId: 'user-uuid-1',
  token: plexToken,
  serverId: plexServerId,
  deviceId: plexClient,
  connections: connections ?? [MediaServerConnection(uri: baseUrl)],
);

/// A fake server answering the recorded library. [handler] can intercept a
/// request first (return null to fall through).
class FakePlexServer {
  FakePlexServer({this.handler, this.movieAgent = 'tv.plex.agents.movie'});

  final http.Response? Function(http.Request request)? handler;
  final String movieAgent;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final override = handler?.call(request);
    if (override != null) return override;
    return _answer(request);
  });

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response _answer(http.Request request) {
    final path = request.url.path;
    final query = request.url.queryParameters;
    if (path.endsWith('/identity')) return _json(plexFixture('identity'));
    if (request.headers['X-Plex-Token'] != plexToken) {
      return http.Response('unauthorized', 401);
    }
    if (path.endsWith('/library/sections')) {
      final sections = plexFixture('sections');
      for (final section
          in (sections['MediaContainer'] as Map)['Directory'] as List) {
        if (section['key'] == '1') section['agent'] = movieAgent;
      }
      return _json(sections);
    }
    if (path.endsWith('/matches')) {
      return _json(switch (query['title']) {
        'imdb-tt0063350' || 'tmdb-10331' => plexFixture('matches_imdb_movie'),
        'tvdb-81189' ||
        'imdb-tt0903747' ||
        'tmdb-1396' => plexFixture('matches_tvdb_show'),
        _ => plexFixture('matches_none'),
      });
    }
    if (path.endsWith('/library/sections/1/all')) {
      if (query['guid'] != null) {
        return _json(
          query['guid'] == 'plex://movie/5d77683585719b001f3a3946'
              ? plexFixture('guid_filter_movie')
              : {
                  'MediaContainer': {'size': 0},
                },
        );
      }
      return _json(plexFixture('movies_all'));
    }
    if (path.endsWith('/library/sections/2/all')) {
      if (query['type'] == '4') {
        final episodes = plexFixture('season_children');
        final rows = ((episodes['MediaContainer'] as Map)['Metadata'] as List)
            .where(
              (row) =>
                  '${row['index']}' == query['episode.index'] &&
                  '${row['parentIndex']}' == query['season.index'] &&
                  '${row['grandparentRatingKey']}' == query['show.id'],
            )
            .toList();
        return _json({
          'MediaContainer': {'size': rows.length, 'Metadata': rows},
        });
      }
      if (query['guid'] != null) {
        return _json(
          query['guid'] == 'plex://show/5d9c083402391c001f583d09'
              ? plexFixture('shows_all')
              : {
                  'MediaContainer': {'size': 0},
                },
        );
      }
      return _json(plexFixture('shows_all'));
    }
    if (path.endsWith('/library/metadata/2')) {
      return _json(plexFixture('movie_metadata'));
    }
    if (path.endsWith('/library/metadata/5')) {
      return _json(plexFixture('episode_metadata'));
    }
    if (path.endsWith('/library/metadata/16')) {
      return _json(plexFixture('long_movie_metadata'));
    }
    if (path.endsWith('/library/metadata/3/children')) {
      return _json(plexFixture('show_children'));
    }
    if (path.endsWith('/:/timeline') || path.endsWith('/:/scrobble')) {
      return http.Response('', 200);
    }
    return http.Response('not found', 404);
  }
}
