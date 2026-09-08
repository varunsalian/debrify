import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const item = StremioMeta(
    id: 'tmdb:550',
    type: 'movie',
    name: 'Title',
    runtime: '100 min',
    genres: ['Original genre'],
  );
  const imdb = ImdbEnrichment(
    runtime: 'IMDb runtime',
    runtimeMinutes: 150,
    genres: ['IMDb genre'],
    plot: 'IMDb plot',
    rating: 8.8,
    director: 'Director',
  );

  DetailModel model(
    StremioMeta presented,
    ImdbEnrichment? extra,
    MetadataPreferences prefs,
  ) {
    final back = FocusNode();
    final primary = FocusNode();
    addTearDown(back.dispose);
    addTearDown(primary.dispose);
    return DetailModel(
      item: presented,
      metadataPreferences: prefs,
      imdbExtra: extra,
      isMovie: true,
      isTelevision: false,
      accent: Colors.red,
      parentsGuide: null,
      recommendations: const [],
      primaryLabel: 'Play',
      sourceCount: 0,
      hasTrailer: false,
      trailerBusy: false,
      trailerPlaying: false,
      hasTrakt: false,
      traktTracked: false,
      traktLabel: '',
      traktRating: null,
      hasSimkl: false,
      simklTracked: false,
      simklLabel: '',
      simklRating: null,
      showPrimary: true,
      onPrimary: () {},
      onBrowse: null,
      onTrailer: () {},
      onSelectSource: () {},
      onAppMenu: () {},
      onTraktMenu: () {},
      onSimklMenu: () {},
      onRecommendationTap: (_) {},
      onAmbientStill: (_) {},
      focus: DetailFocusCoordinator(backNode: back, primaryEntry: primary),
    );
  }

  void verify(
    StremioMeta presented,
    ImdbEnrichment? extra,
    MetadataPreferences prefs,
    String? runtime,
    List<String> genres,
  ) {
    // Classic hosts use these resolvers; alternate layouts use DetailModel.
    expect(
      MetadataDetailsService.informationRuntime(presented, extra, prefs),
      runtime,
    );
    expect(
      MetadataDetailsService.informationGenres(presented, extra, prefs),
      genres,
    );
    final detail = model(presented, extra, prefs);
    expect(detail.runtime, runtime);
    expect(detail.genres, genres);
    expect(detail.rating, 8.8);
  }

  for (final provider in [
    MetadataPreferences.current,
    MetadataPreferences.tmdb,
  ]) {
    for (final fallback in [false, true]) {
      for (final background in [null, 'selected-background']) {
        test(
          'detail backdrop provider=$provider fallback=$fallback background=$background',
          () {
            final prefs = MetadataPreferences(
              providers: {MetadataCategory.backgrounds: provider},
              fallback: fallback,
            );
            final presented = StremioMeta(
              id: item.id,
              type: item.type,
              name: item.name,
              background: background,
              poster: 'original-poster',
            );
            final expected =
                background ??
                (provider == MetadataPreferences.current || fallback
                    ? 'original-poster'
                    : null);
            expect(MetadataDetailsService.backdrop(presented, prefs), expected);
            expect(model(presented, imdb, prefs).backdrop, expected);
            expect(model(presented, imdb, prefs).poster, 'original-poster');
          },
        );
      }
    }
  }

  test(
    'current information preserves existing runtime and genre precedence',
    () {
      verify(item, imdb, MetadataPreferences(), 'IMDb runtime', [
        'Original genre',
      ]);
      verify(
        const StremioMeta(id: 'tmdb:550', type: 'movie', name: 'Title'),
        imdb,
        MetadataPreferences(),
        'IMDb runtime',
        ['IMDb genre'],
      );
    },
  );

  for (final fallback in [false, true]) {
    for (final populated in [false, true]) {
      test(
        'selected information populated=$populated fallback=$fallback reaches details',
        () async {
          final prefs = MetadataPreferences(
            providers: {MetadataCategory.information: MetadataPreferences.tmdb},
            fallback: fallback,
          );
          final repository = TmdbMetadataRepository(
            token: 'test',
            clientFactory: () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'id': 550,
                  'title': 'Selected title',
                  if (populated) 'runtime': 120,
                  'genres': populated
                      ? [
                          {'id': 1, 'name': 'Selected genre'},
                        ]
                      : [],
                }),
                200,
              ),
            ),
          );
          final presentation = await MetadataProviderService(
            tmdb: repository,
          ).present(item, preferences: prefs);
          final extra = await MetadataDetailsService(
            repository: repository,
          ).credits(item, imdb, preferences: prefs);
          verify(
            presentation.item,
            extra,
            prefs,
            populated ? '120 min' : (fallback ? '100 min' : null),
            populated
                ? ['Selected genre']
                : (fallback ? ['Original genre'] : []),
          );
          expect(extra!.runtime, fallback ? 'IMDb runtime' : null);
          expect(extra.runtimeMinutes, fallback ? 150 : null);
          expect(extra.genres, fallback ? ['IMDb genre'] : isEmpty);
          expect(extra.director, 'Director');
          // A sparse original cannot bypass the explicit IMDb fallback policy.
          verify(
            const StremioMeta(id: 'tmdb:550', type: 'movie', name: 'Title'),
            imdb,
            prefs,
            fallback ? 'IMDb runtime' : null,
            fallback ? ['IMDb genre'] : [],
          );
        },
      );
    }
  }
}
