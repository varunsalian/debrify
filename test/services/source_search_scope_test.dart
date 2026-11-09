import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/services/source_search_scope.dart';
import 'package:flutter_test/flutter_test.dart';

String? label(Map<String, Object?> fields, String key) =>
    (fields[key] as DiagnosticLabel?)?.value;

void main() {
  Map<String, Object?> fieldsFor({
    String imdbId = 'tt123',
    bool isMovie = false,
    int? season,
    int? episode,
    String? contentType = 'series',
    String? originVideoId,
    bool enginesRequested = true,
    Map<String, dynamic> result = const {},
  }) => SourceSearchScope.fields(
    surface: 'sources',
    imdbId: imdbId,
    isMovie: isMovie,
    season: season,
    episode: episode,
    contentType: contentType,
    originVideoId: originVideoId,
    enginesRequested: enginesRequested,
    result: result,
  );

  test('anime with an IMDb ID runs scrapers, channels never do', () {
    expect(label(fieldsFor(contentType: 'anime'), 'scrapers'), 'ran');
    expect(
      label(fieldsFor(contentType: 'channel'), 'scrapers'),
      'skipped_content_type',
    );
    expect(label(fieldsFor(contentType: null), 'scrapers'), 'ran');
  });

  test('names why scrapers were skipped without logging the ID', () {
    final fields = fieldsFor(imdbId: 'mal:12345', contentType: 'anime');
    expect(label(fields, 'scrapers'), 'skipped_not_imdb');
    expect(label(fields, 'id_kind'), 'mal');
    expect(
      fields.values.map((v) => '$v'),
      everyElement(isNot(contains('12345'))),
    );
    expect(
      label(fieldsFor(originVideoId: 'RO_1'), 'scrapers'),
      'skipped_custom_episode',
    );
  });

  test('addon-supplied types and ID schemes collapse to fixed labels', () {
    final fields = fieldsFor(
      imdbId: 'someone-private:1',
      contentType: 'My Private List',
    );
    expect(label(fields, 'content_type'), 'other');
    expect(label(fields, 'id_kind'), 'other');
  });

  test('tells a Season Packs search from an episode search', () {
    expect(label(fieldsFor(), 'search_scope'), 'whole_series');
    expect(label(fieldsFor(season: 2), 'search_scope'), 'season');
    expect(label(fieldsFor(season: 1, episode: 2), 'search_scope'), 'episode');
    expect(label(fieldsFor(isMovie: true), 'search_scope'), 'movie');
  });

  test('splits result counts by where they came from', () {
    final fields = fieldsFor(
      result: {
        'torrents': [1, 2, 3, 4, 5, 6],
        'engineCounts': {
          'torrentio': 1,
          'stremio:comet': 2,
          'mediaserver:plex': 3,
        },
        'engineErrors': {'yts': 'timeout'},
      },
    );
    expect(fields['scraper_results'], 1);
    expect(fields['addon_results'], 2);
    expect(fields['media_server_results'], 3);
    expect(fields['total_results'], 6);
    expect(fields['error_count'], 1);
  });

  test('counts an addon-only search, which uses its own result keys', () {
    final fields = fieldsFor(
      enginesRequested: false,
      result: {
        'torrents': [1, 2],
        'addonCounts': {'stremio:comet': 2},
        'addonErrors': {'stremio:other': 'failed'},
      },
    );
    expect(fields['scraper_results'], 0);
    expect(fields['addon_results'], 2);
    expect(fields['total_results'], 2);
    expect(fields['error_count'], 1);
  });

  test('a stage that never asked for scrapers says so', () {
    expect(
      label(fieldsFor(enginesRequested: false), 'scrapers'),
      'not_requested',
    );
  });
}
