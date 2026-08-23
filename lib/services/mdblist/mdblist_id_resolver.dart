import 'mdblist_models.dart';
import 'mdblist_service.dart';

class MdblistIdResolver {
  final MdblistService service;
  final Map<String, Future<MdblistMediaIds?>> _inFlight = {};
  final Map<String, MdblistMediaIds> _cache = {};

  MdblistIdResolver._(this.service);
  factory MdblistIdResolver.forTesting(MdblistService service) =>
      MdblistIdResolver._(service);
  static final MdblistIdResolver instance = MdblistIdResolver._(
    MdblistService.instance,
  );

  void resetProfileScope() {
    _cache.clear();
    _inFlight.clear();
  }

  Future<MdblistMediaIds?> resolve(String imdbId, String type) {
    final normalized = imdbId.trim().toLowerCase();
    if (!normalized.startsWith('tt')) return Future.value(null);
    final key = '${type == 'series' ? 'show' : 'movie'}:$normalized';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final response = await service.resolveImdb(normalized, type);
        final data = response.data;
        if (!response.isSuccess || data == null) return null;
        final nestedIds = data['ids'];
        final ids = MdblistMediaIds.fromJson(
          nestedIds is Map<String, dynamic> ? nestedIds : data,
        );
        final resolved = MdblistMediaIds(
          imdb: ids.imdb ?? data['imdb_id']?.toString() ?? normalized,
          tmdb: ids.tmdb,
          tvdb: ids.tvdb,
          mdblist: ids.mdblist ?? data['mdblist_id']?.toString(),
        );
        _cache[key] = resolved;
        return resolved;
      } finally {
        _inFlight.remove(key);
      }
    });
  }
}
