import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import 'imdb_enrichment_service.dart';
import 'metadata_preferences_service.dart';
import 'tmdb_metadata_repository.dart';

class MetadataTrailer {
  const MetadataTrailer({
    required this.key,
    required this.title,
    required this.language,
    required this.type,
    required this.official,
  });
  final String key;
  final String title;
  final String language;
  final String type;
  final bool official;
}

class MetadataDetailsService {
  MetadataDetailsService({TmdbMetadataRepository? repository})
    : repository = repository ?? TmdbMetadataRepository.instance;
  static final instance = MetadataDetailsService();
  final TmdbMetadataRepository repository;

  /// Default details retain their existing IMDb runtime precedence. Explicit
  /// information choices use the presented fields, with opt-in IMDb fallback.
  static String? informationRuntime(
    StremioMeta presented,
    ImdbEnrichment? existing,
    MetadataPreferences? preferences,
  ) {
    if (preferences == null ||
        preferences.provider(MetadataCategory.information) ==
            MetadataPreferences.current) {
      return existing?.runtime;
    }
    return text(presented.runtime) ??
        (preferences.fallback ? existing?.runtime : null);
  }

  static List<String> informationGenres(
    StremioMeta presented,
    ImdbEnrichment? existing,
    MetadataPreferences? preferences,
  ) {
    if (presented.genres?.isNotEmpty == true) return presented.genres!;
    final allowFallback =
        preferences == null ||
        preferences.provider(MetadataCategory.information) ==
            MetadataPreferences.current ||
        preferences.fallback;
    return allowFallback ? (existing?.genres ?? const []) : const [];
  }

  /// A poster is a cross-category fallback, not a selected backdrop.
  static String? backdrop(
    StremioMeta presented,
    MetadataPreferences? preferences,
  ) {
    if (preferences == null ||
        preferences.provider(MetadataCategory.backgrounds) ==
            MetadataPreferences.current) {
      return presented.background ?? presented.poster;
    }
    return text(presented.background) ??
        (preferences.fallback ? presented.poster : null);
  }

  Future<ImdbEnrichment?> credits(
    StremioMeta item,
    ImdbEnrichment? existing, {
    MetadataPreferences? preferences,
  }) async {
    return enrich(
      item,
      loadExisting: () async => existing,
      preferences: preferences,
    );
  }

  /// Fetch independent IMDb enrichment and selected credits concurrently, then
  /// apply policy once both inputs are available. All futures are observed.
  Future<ImdbEnrichment?> enrich(
    StremioMeta item, {
    required Future<ImdbEnrichment?> Function() loadExisting,
    MetadataPreferences? preferences,
  }) async {
    final prefs = preferences ?? await MetadataPreferencesService.load();
    final results = await Future.wait<Object?>([
      loadExisting(),
      _creditsData(item, prefs),
    ]);
    var existing = results[0] as ImdbEnrichment?;
    final data = results[1] as Map<String, dynamic>?;
    if (existing != null &&
        prefs.provider(MetadataCategory.information) !=
            MetadataPreferences.current &&
        !prefs.fallback) {
      existing = existing.withCredits(
        cast: existing.cast,
        director: existing.director,
        retainPlot: false,
        retainRuntimeAndGenres: false,
        retainStars: true,
      );
    }
    if (prefs.provider(MetadataCategory.credits) != MetadataPreferences.tmdb) {
      return existing;
    }
    try {
      if (data == null) {
        return prefs.fallback ? existing : existing?.withCredits(cast: []);
      }
      final cast = <CastMember>[];
      for (final row in maps(data['cast'])) {
        final name = text(row['name']);
        if (name == null) continue;
        final roles = maps(row['roles']);
        cast.add(
          CastMember(
            name: name,
            character:
                text(row['character']) ??
                (roles.isEmpty ? null : text(roles.first['character'])),
            imageUrl: TmdbMetadataRepository.image(
              row['profile_path'],
              size: 'w185',
            ),
            tmdbPersonId: positiveId(row['id']),
          ),
        );
      }
      final directors = maps(data['crew'])
          .where(
            (r) =>
                r['job'] == 'Director' ||
                maps(r['jobs']).any((j) => j['job'] == 'Director'),
          )
          .map((r) => text(r['name']))
          .whereType<String>()
          .toSet();
      if (cast.isEmpty && prefs.fallback) return existing;
      return (existing ?? const ImdbEnrichment()).withCredits(
        cast: cast,
        director: directors.isEmpty ? null : directors.join(', '),
      );
    } catch (_) {
      return prefs.fallback ? existing : existing?.withCredits(cast: []);
    }
  }

  Future<Map<String, dynamic>?> _creditsData(
    StremioMeta item,
    MetadataPreferences prefs,
  ) async {
    if (prefs.provider(MetadataCategory.credits) != MetadataPreferences.tmdb) {
      return null;
    }
    try {
      final id = await repository.identify(item);
      if (id == null) return null;
      return await repository.get(
        '${id.type}/${id.id}/${id.type == 'tv' ? 'aggregate_credits' : 'credits'}',
        {'language': prefs.language},
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<StremioMeta>> recommendations(
    StremioMeta item,
    Future<List<StremioMeta>> Function()? current, {
    MetadataPreferences? preferences,
  }) async {
    final prefs = preferences ?? await MetadataPreferencesService.load();
    if (prefs.provider(MetadataCategory.recommendations) !=
        MetadataPreferences.tmdb) {
      return current == null ? [] : current();
    }
    try {
      final id = await repository.identify(item);
      if (id != null) {
        final data = await repository.get(
          '${id.type}/${id.id}/recommendations',
          {'language': prefs.language, 'page': '1'},
        );
        final result = titles(data['results'], id.type);
        if (result.isNotEmpty || !prefs.fallback) return result;
      }
    } catch (_) {}
    return prefs.fallback && current != null ? current() : [];
  }

  Future<List<MetadataTrailer>> trailers(
    StremioMeta item, {
    MetadataPreferences? preferences,
  }) async {
    final prefs = preferences ?? await MetadataPreferencesService.load();
    if (prefs.provider(MetadataCategory.trailers) != MetadataPreferences.tmdb) {
      return [];
    }
    final id = await repository.identify(item);
    if (id == null) return [];
    var lang = prefs.trailerLanguage == 'same'
        ? prefs.language
        : prefs.trailerLanguage;
    if (lang == 'original') {
      final details = await repository.get('${id.type}/${id.id}');
      lang = text(details['original_language']) ?? 'en';
    }
    var data = await repository.get('${id.type}/${id.id}/videos', {
      'language': lang,
    });
    var result = parseTrailers(data['results']);
    if (result.isEmpty && prefs.fallback && !lang.startsWith('en')) {
      data = await repository.get('${id.type}/${id.id}/videos', {
        'language': 'en-US',
      });
      result = parseTrailers(data['results']);
    }
    return result;
  }

  static List<MetadataTrailer> parseTrailers(Object? raw) {
    final result = <MetadataTrailer>[];
    final seen = <String>{};
    for (final row in maps(raw)) {
      final key = text(row['key']);
      if (row['site'] != 'YouTube' ||
          key == null ||
          !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(key) ||
          !seen.add(key)) {
        continue;
      }
      result.add(
        MetadataTrailer(
          key: key,
          title: text(row['name']) ?? 'Trailer',
          language: text(row['iso_639_1']) ?? '',
          type: text(row['type']) ?? '',
          official: row['official'] == true,
        ),
      );
    }
    int rank(String type) => switch (type) {
      'Trailer' => 0,
      'Teaser' => 1,
      'Clip' => 2,
      _ => 3,
    };
    result.sort((a, b) {
      final type = rank(a.type).compareTo(rank(b.type));
      return type != 0
          ? type
          : (b.official ? 1 : 0).compareTo(a.official ? 1 : 0);
    });
    return result;
  }

  static List<Map<String, dynamic>> maps(Object? raw) =>
      raw is List ? raw.whereType<Map<String, dynamic>>().toList() : [];
  static String? text(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
  static int? positiveId(Object? raw) => raw is int && raw > 0 ? raw : null;

  static List<StremioMeta> titles(Object? raw, String type) => [
    for (final row in maps(raw))
      if (positiveId(row['id']) != null &&
          (text(row['title']) ?? text(row['name'])) != null)
        StremioMeta(
          id: 'tmdb:${row['id']}',
          type: (row['media_type'] ?? type) == 'tv' ? 'series' : 'movie',
          name: text(row['title']) ?? text(row['name'])!,
          description: text(row['overview']),
          poster: TmdbMetadataRepository.image(row['poster_path']),
          background: TmdbMetadataRepository.image(
            row['backdrop_path'],
            size: 'w1280',
          ),
          year: _year(row['release_date'] ?? row['first_air_date']),
        ),
  ];
  static String? _year(Object? value) =>
      value is String && RegExp(r'^\d{4}-').hasMatch(value)
      ? value.substring(0, 4)
      : null;
}
