import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/services/tmdb_title_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> movie(int id, String title) => {
  'id': id,
  'media_type': 'movie',
  'title': title,
  'release_date': '2021-10-01',
  'poster_path': '/poster.jpg',
};

http.Response response(List<Object?> items) =>
    http.Response(jsonEncode({'results': items}), 200);

void main() {
  test(
    'keeps distinct identities and years, excludes people/adult/bad data',
    () {
      final items = TmdbTitleSearch.parse({
        'results': [
          movie(1, 'Dune'),
          movie(1, 'Duplicate'),
          {...movie(2, 'Dune'), 'release_date': '1984-12-14'},
          {
            'id': 1,
            'media_type': 'tv',
            'name': 'Dune',
            'first_air_date': '2000-12-03',
          },
          {'id': 3, 'media_type': 'person', 'name': 'Dune'},
          {...movie(4, 'Adult'), 'adult': true},
          {
            ...movie(5, 'Invalid artwork'),
            'poster_path': '//elsewhere/private',
          },
          movie(0, 'Bad ID'),
          movie(6, ''),
          'broken',
          null,
        ],
      });
      expect(items.map((i) => '${i.type}:${i.id}'), [
        'movie:tmdb:1',
        'movie:tmdb:2',
        'series:tmdb:1',
        'movie:tmdb:5',
      ]);
      expect(items.map((i) => i.year), ['2021', '1984', '2000', '2021']);
      expect(items.first.poster, 'https://image.tmdb.org/t/p/w185/poster.jpg');
      expect(items.last.poster, isNull);
      expect(
        TmdbTitleSearch.parse({
          'results': List.generate(20, (i) => movie(i + 1, 'Title')),
        }),
        hasLength(6),
      );
    },
  );

  testWidgets('debounces typing and uses cached localized results', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final search = TmdbTitleSearch(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return response([movie(1, request.url.queryParameters['query']!)]);
        }),
      ),
    );
    addTearDown(search.dispose);
    search.update('Du', language: 'hi-IN');
    await tester.pump(const Duration(milliseconds: 200));
    search.update('Dune', language: 'hi-IN');
    await tester.pump(const Duration(milliseconds: 349));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(search.value.single.name, 'Dune');
    expect(requests.single.url.path, '/3/search/multi');
    expect(requests.single.url.queryParameters, {
      'query': 'Dune',
      'language': 'hi-IN',
      'include_adult': 'false',
      'page': '1',
    });
    search.clear();
    search.update('Dune', language: 'hi-IN');
    await tester.pump(const Duration(milliseconds: 350));
    expect(search.value, hasLength(1));
    expect(requests, hasLength(1));
    search.update('Dune', language: 'en-US');
    await tester.pump(const Duration(milliseconds: 350));
    expect(requests, hasLength(2));
  });

  testWidgets('titles containing colons reach TMDB unchanged', (tester) async {
    final queries = <String>[];
    final search = TmdbTitleSearch(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          final query = request.url.queryParameters['query']!;
          queries.add(query);
          return response([movie(1, query)]);
        }),
      ),
    );
    addTearDown(search.dispose);
    const titles = ['Dune: Part Two', 'Alien: Romulus', 'Mission: Impossible'];
    for (final title in titles) {
      search.update(title, language: 'en-US');
      await tester.pump(const Duration(milliseconds: 350));
      expect(search.value.single.name, title);
    }
    expect(queries, titles);
  });

  testWidgets(
    'late requests cannot overwrite newer text or revive cleared results',
    (tester) async {
      final pending = <String, Completer<http.Response>>{};
      final search = TmdbTitleSearch(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) {
            return (pending[request.url.queryParameters['query']!] =
                    Completer<http.Response>())
                .future;
          }),
        ),
      );
      search.update('Du', language: 'en-US');
      await tester.pump(const Duration(milliseconds: 350));
      search.update('Dune', language: 'en-US');
      await tester.pump(const Duration(milliseconds: 350));
      pending['Dune']!.complete(response([movie(2, 'New')]));
      await tester.pump();
      pending['Du']!.complete(response([movie(1, 'Old')]));
      await tester.pump();
      expect(search.value.single.name, 'New');
      search.update('Arrival', language: 'en-US');
      await tester.pump(const Duration(milliseconds: 350));
      search.clear();
      pending['Arrival']!.complete(response([movie(3, 'Arrival')]));
      await tester.pump();
      expect(search.value, isEmpty);
      search.update('Alien', language: 'en-US');
      await tester.pump(const Duration(milliseconds: 350));
      search.dispose();
      pending['Alien']!.complete(response([movie(4, 'Alien')]));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'links, hashes, composition and disabled lookup make no requests',
    (tester) async {
      var requests = 0;
      final search = TmdbTitleSearch(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            requests++;
            return response([]);
          }),
        ),
      );
      addTearDown(search.dispose);
      for (final q in [
        '',
        'D',
        'https://example.com/private',
        'HTTPS://example.com/private',
        'ftp://example.com/private',
        'file:/private/movie.torrent',
        'data:text/plain,private',
        'mailto:person@example.com',
        'magnet:?xt=urn:btih:abc',
        'www.example.com',
        'tt1234567',
        'a' * 40,
        'a' * 64,
        'q' * 201,
      ]) {
        search.update(q, language: 'en-US');
        await tester.pump(const Duration(milliseconds: 400));
      }
      search.update('Dune', language: 'en-US', composing: true);
      await tester.pump(const Duration(milliseconds: 400));
      search.update('Dune', language: 'en-US', enabled: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, 0);
      search.update('Dune', language: 'en-US');
      await tester.pump(const Duration(milliseconds: 350));
      expect(requests, 1);
    },
  );

  testWidgets('unconfigured builds and network failures leave search usable', (
    tester,
  ) async {
    final unconfigured = TmdbTitleSearch(
      repository: TmdbMetadataRepository(
        token: '',
        clientFactory: () => throw StateError('unexpected request'),
      ),
    );
    addTearDown(unconfigured.dispose);
    unconfigured.update('Dune', language: 'en-US');
    await tester.pump(const Duration(milliseconds: 400));
    expect(unconfigured.value, isEmpty);
    final search = TmdbTitleSearch(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient(
          (request) async => request.url.queryParameters['query'] == 'Dune'
              ? http.Response('{}', 503)
              : response([movie(1, 'Arrival')]),
        ),
      ),
    );
    addTearDown(search.dispose);
    search.update('Dune', language: 'en-US');
    await tester.pump(const Duration(milliseconds: 350));
    expect(search.value, isEmpty);
    search.update('Arrival', language: 'en-US');
    await tester.pump(const Duration(milliseconds: 350));
    expect(search.value.single.name, 'Arrival');
  });
}
