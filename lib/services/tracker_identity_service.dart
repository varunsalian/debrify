import '../models/media_identity.dart';
import 'simkl/simkl_service.dart';

/// Resolves API identifiers without changing the playback/progress identity.
/// A Simkl detail lookup must echo the exact requested ID and media type.
/// There is deliberately no title search or filename fallback.
class TrackerIdentityService {
  TrackerIdentityService({Future<dynamic> Function(String)? fetchSimkl})
    : _fetchSimkl = fetchSimkl ?? SimklService.instance.fetchPublicOrNull;

  static final instance = TrackerIdentityService();
  final Future<dynamic> Function(String) _fetchSimkl;
  final _cache = <String, ({DateTime at, Map<String, dynamic> ids})>{};
  final _pending = <String, Future<Map<String, dynamic>?>>{};

  static Map<String, dynamic>? directIds(String id, String type) {
    id = id.trim().toLowerCase();
    if (type != 'movie' && type != 'series') return null;
    if (MediaIdentity.isImdb(id)) return {'imdb': id};
    if (MediaIdentity.isNative(id) && id.startsWith('tmdb:')) {
      if (id.startsWith('tmdb:movie:') && type != 'movie') return null;
      return {'tmdb': int.parse(id.split(':').last)};
    }
    return null;
  }

  Future<Map<String, dynamic>?> resolve(String id, String type) async {
    final direct = directIds(id, type);
    if (direct != null) return direct;
    if (!MediaIdentity.isNative(id) ||
        !id.startsWith('simkl:') ||
        (type != 'movie' && type != 'series')) {
      return null;
    }
    final key = '$type:$id';
    final hit = _cache[key];
    if (hit != null &&
        DateTime.now().difference(hit.at) < const Duration(minutes: 15)) {
      return Map.of(hit.ids);
    }
    final active = _pending[key];
    if (active != null) return active;
    final future = _lookup(id, type);
    _pending[key] = future;
    try {
      final ids = await future;
      if (ids != null) {
        if (_cache.length >= 128) _cache.remove(_cache.keys.first);
        _cache[key] = (at: DateTime.now(), ids: Map.of(ids));
      }
      return ids;
    } finally {
      _pending.remove(key);
    }
  }

  Future<Map<String, dynamic>?> _lookup(String id, String type) async {
    try {
      final route = type == 'movie' ? 'movies' : 'tv';
      final raw = await _fetchSimkl(
        'https://api.simkl.com/$route/${id.split(':').last}',
      ).timeout(const Duration(seconds: 8));
      final records = raw is List ? raw : [raw];
      // Ambiguous detail responses cannot establish an identity.
      if (records.length != 1 || records.single is! Map) return null;
      final row = records.single as Map;
      if (row['type'] != (type == 'movie' ? 'movie' : 'show')) return null;
      final ids = row['ids'];
      if (!MediaIdentity.matches(ids, id)) return null;
      final tmdb = MediaIdentity.positiveInt(ids['tmdb']);
      if (tmdb != null) return {'tmdb': tmdb};
      final imdb = ids['imdb']?.toString().trim().toLowerCase();
      if (MediaIdentity.isImdb(imdb)) return {'imdb': imdb};
      final tvdb = MediaIdentity.positiveInt(ids['tvdb']);
      if (type == 'series' && tvdb != null) return {'tvdb': tvdb};
    } catch (_) {
      // Missing mappings and transient failures never guess a different show.
    }
    return null;
  }

  static bool matches(
    Map<String, dynamic> wanted,
    Map<String, dynamic> candidate,
  ) =>
      wanted.isNotEmpty &&
      wanted.entries.every(
        (entry) =>
            candidate[entry.key]?.toString().trim().toLowerCase() ==
            entry.value.toString().trim().toLowerCase(),
      );
}
