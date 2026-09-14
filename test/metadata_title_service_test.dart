import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_title_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const title = StremioMeta(id: 'tmdb:1', type: 'series', name: 'Title');
  MetadataTitleService service(
    Object? imdb, {
    int status = 200,
    List<StremioAddon> addons = const [],
  }) {
    return MetadataTitleService(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((request) async {
          expect(request.url.path, '/3/tv/1/external_ids');
          return http.Response(jsonEncode({'imdb_id': imdb}), status);
        }),
      ),
      addons: () async => addons,
      preference: () async => null,
    );
  }

  test(
    'hydrates IMDb identity and selects a compatible metadata addon',
    () async {
      final wrong = StremioAddon(
        id: 'wrong',
        name: 'Wrong',
        manifestUrl: '',
        baseUrl: 'https://wrong.test',
        resources: ['meta'],
        types: ['movie'],
      );
      final right = StremioAddon(
        id: 'right',
        name: 'Right',
        manifestUrl: '',
        baseUrl: 'https://right.test',
        resources: ['meta'],
        types: ['series'],
        idPrefixes: ['tt'],
      );
      final result = await service(
        'tt1234567',
        addons: [wrong, right],
      ).resolve(title);
      expect(result.id, 'tt1234567');
      expect(result.effectiveImdbId, 'tt1234567');
      expect(result.sourceAddon?.id, 'right');
      expect(result.name, title.name);
    },
  );

  test('no mapping stays unresolved for title-search fallback', () async {
    expect(await service(null).resolve(title), same(title));
  });

  test('failed lookup and malformed identity do not become details', () async {
    await expectLater(
      service(null, status: 503).resolve(title),
      throwsA(isA<TmdbMetadataException>()),
    );
    await expectLater(
      service('invalid').resolve(title),
      throwsA(isA<TmdbMetadataException>()),
    );
  });
}
