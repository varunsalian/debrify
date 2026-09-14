import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import 'metadata_details_service.dart';
import 'tmdb_metadata_repository.dart';

class MetadataExploreData {
  const MetadataExploreData({
    this.people = const [],
    this.companies = const [],
    this.networks = const [],
    this.franchise = const [],
    this.providers = const {},
    this.providerLink,
    this.franchiseName,
    this.unavailable = const {},
  });
  final List<Map<String, dynamic>> people;
  final List<Map<String, dynamic>> companies;
  final List<Map<String, dynamic>> networks;
  final List<StremioMeta> franchise;
  final String? franchiseName;
  final Set<MetadataFeature> unavailable;
  final Map<String, List<Map<String, dynamic>>> providers;
  final String? providerLink;
}

class MetadataBrowseResult {
  const MetadataBrowseResult(
    this.items, {
    this.hasMore = false,
    this.description,
  });
  final List<StremioMeta> items;
  final bool hasMore;
  final String? description;
}

class MetadataExploreService {
  MetadataExploreService({TmdbMetadataRepository? repository})
    : repository = repository ?? TmdbMetadataRepository.instance;
  static final instance = MetadataExploreService();
  final TmdbMetadataRepository repository;

  Future<MetadataExploreData> details(
    StremioMeta item,
    MetadataPreferences prefs,
  ) async {
    if (prefs.features.difference({MetadataFeature.discovery}).isEmpty) {
      return const MetadataExploreData();
    }
    final id = await repository.identify(item);
    if (id == null) return const MetadataExploreData();
    final data = await repository.get('${id.type}/${id.id}', {
      'language': prefs.language,
      'append_to_response': [
        if (prefs.features.contains(MetadataFeature.people)) 'credits',
        if (prefs.features.contains(MetadataFeature.availability))
          'watch/providers',
      ].join(','),
    });
    final credits = data['credits'];
    final cast = credits is Map
        ? MetadataDetailsService.maps(credits['cast'])
        : <Map<String, dynamic>>[];
    final crew = credits is Map
        ? MetadataDetailsService.maps(credits['crew'])
        : <Map<String, dynamic>>[];
    final people = <int, Map<String, dynamic>>{};
    for (final row in [...cast, ...crew.where((r) => r['job'] == 'Director')]) {
      final personId = MetadataDetailsService.positiveId(row['id']);
      if (personId != null &&
          MetadataDetailsService.text(row['name']) != null) {
        people.putIfAbsent(personId, () => row);
      }
    }
    List<StremioMeta> franchise = [];
    String? franchiseName;
    final unavailable = <MetadataFeature>{};
    final collection = data['belongs_to_collection'];
    if (prefs.features.contains(MetadataFeature.franchises) &&
        collection is Map &&
        MetadataDetailsService.positiveId(collection['id']) != null) {
      try {
        final full = await repository.get('collection/${collection['id']}', {
          'language': prefs.language,
        });
        franchiseName = MetadataDetailsService.text(full['name']);
        final parts = MetadataDetailsService.maps(full['parts']);
        parts.sort(
          (a, b) => (MetadataDetailsService.text(a['release_date']) ?? '9999')
              .compareTo(
                MetadataDetailsService.text(b['release_date']) ?? '9999',
              ),
        );
        franchise = MetadataDetailsService.titles(parts, 'movie');
      } catch (_) {
        unavailable.add(MetadataFeature.franchises);
      }
    }
    final availability = prefs.features.contains(MetadataFeature.availability)
        ? data['watch/providers']
        : null;
    final results = availability is Map ? availability['results'] : null;
    final country = results is Map ? results[prefs.region] : null;
    return MetadataExploreData(
      unavailable: unavailable,
      people: prefs.features.contains(MetadataFeature.people)
          ? people.values.toList()
          : [],
      companies: prefs.features.contains(MetadataFeature.companies)
          ? _entities(data['production_companies'])
          : [],
      networks: prefs.features.contains(MetadataFeature.companies)
          ? _entities(data['networks'])
          : [],
      franchise: franchise,
      franchiseName: franchiseName,
      providers: {
        if (country is Map)
          for (final kind in ['flatrate', 'free', 'ads', 'rent', 'buy'])
            if (country[kind] is List)
              kind: MetadataDetailsService.maps(country[kind]),
      },
      providerLink: country is Map
          ? MetadataDetailsService.text(country['link'])
          : null,
    );
  }

  Future<MetadataBrowseResult> browse({
    required String kind,
    int? id,
    required MetadataPreferences preferences,
    int page = 1,
    String type = 'movie',
    Map<String, String> filters = const {},
  }) async {
    final feature = switch (kind) {
      'person' => MetadataFeature.people,
      'company' || 'network' => MetadataFeature.companies,
      'discover' => MetadataFeature.discovery,
      _ => null,
    };
    if (feature == null ||
        !preferences.features.contains(feature) ||
        (kind != 'discover' && (id == null || id <= 0))) {
      return const MetadataBrowseResult([]);
    }
    if (page < 1 || page > 500) return const MetadataBrowseResult([]);
    if (kind == 'person') {
      if (id == null || id <= 0) return const MetadataBrowseResult([]);
      final data = await repository.get('person/$id', {
        'language': preferences.language,
        'append_to_response': 'combined_credits',
      });
      final credits = data['combined_credits'];
      final unique = <String, Map<String, dynamic>>{};
      if (credits is Map) {
        for (final row in [
          ...MetadataDetailsService.maps(credits['cast']),
          ...MetadataDetailsService.maps(credits['crew']),
        ]) {
          if (row['media_type'] != 'movie' && row['media_type'] != 'tv') {
            continue;
          }
          if (MetadataDetailsService.positiveId(row['id']) == null ||
              (MetadataDetailsService.text(row['title']) ??
                      MetadataDetailsService.text(row['name'])) ==
                  null) {
            continue;
          }
          unique.putIfAbsent('${row['media_type']}:${row['id']}', () => row);
        }
      }
      final rows = unique.values.toList()
        ..sort((a, b) {
          num popularity(Map<String, dynamic> r) =>
              r['popularity'] is num ? r['popularity'] as num : 0;
          return popularity(b).compareTo(popularity(a));
        });
      final start = (page - 1) * 20;
      return MetadataBrowseResult(
        MetadataDetailsService.titles(
          rows.skip(start).take(20).toList(),
          'movie',
        ),
        hasMore: start + 20 < rows.length,
        description: MetadataDetailsService.text(data['biography']),
      );
    }
    final media = kind == 'network' || type == 'tv' ? 'tv' : 'movie';
    final data = await repository.get('discover/$media', {
      'language': preferences.language,
      'page': '$page',
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
      if (kind == 'company' && id != null) 'with_companies': '$id',
      if (kind == 'network' && id != null) 'with_networks': '$id',
      'watch_region': preferences.region,
      ...filters,
    });
    return MetadataBrowseResult(
      MetadataDetailsService.titles(data['results'], media),
      hasMore:
          data['total_pages'] is num &&
          page < (data['total_pages'] as num).clamp(1, 500),
    );
  }

  static List<Map<String, dynamic>> _entities(Object? raw) =>
      MetadataDetailsService.maps(raw)
          .where(
            (row) =>
                MetadataDetailsService.positiveId(row['id']) != null &&
                MetadataDetailsService.text(row['name']) != null,
          )
          .toList();
}
