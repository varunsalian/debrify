import '../models/stremio_addon.dart';
import '../models/media_identity.dart';
import 'tmdb_metadata_repository.dart';
import 'simkl/simkl_service.dart';

/// Episode coordinates belong to the exact provider title, never a title match.
class NativeSeriesMetadataService {
  NativeSeriesMetadataService({TmdbMetadataRepository? tmdb})
    : _tmdb = tmdb ?? TmdbMetadataRepository.instance;
  static final instance = NativeSeriesMetadataService();
  static final addon = StremioAddon(
    id: 'native_metadata',
    name: 'Title metadata',
    manifestUrl: '',
    baseUrl: '',
  );
  final TmdbMetadataRepository _tmdb;

  Future<List<Map<String, dynamic>>> episodes(String id) async {
    if (!MediaIdentity.isNative(id)) return [];
    final number = id.split(':').last;
    if (id.startsWith('simkl:')) {
      final raw = await SimklService.instance.fetchPublicOrNull(
        'https://api.simkl.com/tv/episodes/$number?extended=full',
      );
      if (raw is! List) throw StateError('Episode metadata unavailable');
      return [
        for (final row in raw.whereType<Map>())
          if (row['season'] is int &&
              row['episode'] is int &&
              row['season'] >= 0 &&
              row['episode'] > 0)
            {
              'id': '$id:${row['season']}:${row['episode']}',
              'season': row['season'],
              'episode': row['episode'],
              'title': row['title'],
              'overview': row['description'],
              'released': row['date'],
              if (row['img'] is String)
                'thumbnail': 'https://simkl.in/episodes/${row['img']}_w.webp',
            },
      ];
    }
    final detail = await _tmdb.get('tv/$number');
    final seasons =
        (detail['seasons'] as List? ?? const [])
            .whereType<Map>()
            .map((s) => s['season_number'])
            .whereType<int>()
            .where((s) => s >= 0)
            .toSet()
            .toList()
          ..sort();
    final out = <Map<String, dynamic>>[];
    // Bound fan-out; the repository also shares requests and caches responses.
    for (var offset = 0; offset < seasons.length; offset += 4) {
      final batch = await Future.wait(
        seasons.skip(offset).take(4).map((season) async {
          final data = await _tmdb.get('tv/$number/season/$season');
          return <Map<String, dynamic>>[
            for (final row
                in (data['episodes'] as List? ?? const []).whereType<Map>())
              if (row['episode_number'] is int &&
                  row['episode_number'] > 0 &&
                  row['season_number'] == season)
                {
                  'id': '$id:$season:${row['episode_number']}',
                  'season': season,
                  'episode': row['episode_number'],
                  'title': row['name'],
                  'overview': row['overview'],
                  'released': row['air_date'],
                  if (row['still_path'] is String)
                    'thumbnail': TmdbMetadataRepository.image(
                      row['still_path'],
                      size: 'w300',
                    ),
                },
          ];
        }),
      );
      for (final rows in batch) {
        out.addAll(rows);
      }
    }
    return out;
  }
}
