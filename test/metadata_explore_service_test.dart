import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const movie = StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Movie');
  test(
    'disabled and discovery-only details do not fetch extra metadata',
    () async {
      var reads = 0;
      final service = MetadataExploreService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            reads++;
            return http.Response('{}', 200);
          }),
        ),
      );
      for (final prefs in [
        MetadataPreferences(features: {}),
        MetadataPreferences(features: {MetadataFeature.discovery}),
      ]) {
        expect((await service.details(movie, prefs)).franchise, isEmpty);
      }
      expect(reads, 0);
    },
  );

  test('default preferences load people and allow their filmography', () async {
    final requests = <Uri>[];
    final service = MetadataExploreService(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(jsonEncode(
            request.url.path.endsWith('/person/3')
                ? {'combined_credits': {'cast': [
                    {'id': 2, 'title': 'Film', 'media_type': 'movie'},
                  ]}}
                : {'credits': {'cast': [{'id': 3, 'name': 'Person'}]}},
          ), 200);
        }),
      ),
    );
    final prefs = MetadataPreferences();
    final details = await service.details(movie, prefs);
    expect(details.people.single['id'], 3);
    expect(details.franchise, isEmpty);
    expect(details.companies, isEmpty);
    expect(details.providers, isEmpty);
    final filmography = await service.browse(
      kind: 'person', id: 3, preferences: prefs,
    );
    expect(filmography.items.single.name, 'Film');
    expect(requests, hasLength(2));
    expect(requests.first.queryParameters['append_to_response'], 'credits');
    expect(requests.last.path, endsWith('/person/3'));
    expect(requests.last.queryParameters['append_to_response'], 'combined_credits');
  });

  test(
    'franchise failure preserves people, studios and regional availability',
    () async {
      final service = MetadataExploreService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            if (request.url.path.contains('/collection/')) {
              return http.Response('{}', 503);
            }
            return http.Response(
              jsonEncode({
                'belongs_to_collection': {'id': 2},
                'credits': {
                  'cast': [
                    {'id': 3, 'name': 'Person'},
                    {'id': 4},
                    null,
                  ],
                },
                'production_companies': [
                  {'id': 5, 'name': 'Studio'},
                  {'name': 'Invalid'},
                ],
                'watch/providers': {
                  'results': {
                    'IN': {
                      'flatrate': [
                        {'provider_name': 'India provider'},
                      ],
                      'link': 'https://www.themoviedb.org/movie/1/watch',
                    },
                    'US': {
                      'flatrate': [
                        {'provider_name': 'US provider'},
                      ],
                    },
                  },
                },
              }),
              200,
            );
          }),
        ),
      );
      final result = await service.details(
        movie,
        MetadataPreferences(
          region: 'IN',
          features: {
            MetadataFeature.franchises,
            MetadataFeature.people,
            MetadataFeature.companies,
            MetadataFeature.availability,
          },
        ),
      );
      expect(result.unavailable, {MetadataFeature.franchises});
      expect(result.people.single['name'], 'Person');
      expect(result.companies.single['name'], 'Studio');
      expect(
        result.providers['flatrate']!.single['provider_name'],
        'India provider',
      );
    },
  );

  test(
    'disabled or invalid browse sources do not issue a discover request',
    () async {
      var reads = 0;
      final service = MetadataExploreService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            reads++;
            return http.Response('{}', 200);
          }),
        ),
      );
      for (final kind in [
        'person',
        'company',
        'network',
        'discover',
        'invalid',
      ]) {
        expect(
          (await service.browse(
            kind: kind,
            id: 1,
            preferences: MetadataPreferences(features: {}),
          )).items,
          isEmpty,
        );
      }
      expect(
        (await service.browse(
          kind: 'company',
          preferences: MetadataPreferences(
            features: {MetadataFeature.companies},
          ),
        )).items,
        isEmpty,
      );
      expect(reads, 0);
    },
  );

  test(
    'person pages deduplicate before slicing and preserve movie versus TV identity',
    () async {
      var reads = 0;
      final rows = List.generate(
        25,
        (i) => {
          'id': i + 1,
          'title': 'Title $i',
          'media_type': 'movie',
          'popularity': i,
        },
      );
      final service = MetadataExploreService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            reads++;
            return http.Response(
              jsonEncode({
                'biography': 'Biography',
                'combined_credits': {
                  'cast': [
                    ...rows,
                    {
                      'id': 25,
                      'name': 'Show',
                      'media_type': 'tv',
                      'popularity': 100,
                    },
                    {'id': 100, 'media_type': 'movie'},
                    {'name': 'Invalid', 'media_type': 'movie'},
                  ],
                  'crew': rows,
                },
              }),
              200,
            );
          }),
        ),
      );
      final prefs = MetadataPreferences(features: {MetadataFeature.people});
      final first = await service.browse(
        kind: 'person',
        id: 1,
        preferences: prefs,
      );
      final second = await service.browse(
        kind: 'person',
        id: 1,
        preferences: prefs,
        page: 2,
      );
      expect(first.items, hasLength(20));
      expect(second.items, hasLength(6));
      expect(first.items.first.type, 'series');
      expect(first.items[1].type, 'movie');
      expect(first.hasMore, isTrue);
      expect(second.hasMore, isFalse);
      expect(reads, 1);
    },
  );
}
