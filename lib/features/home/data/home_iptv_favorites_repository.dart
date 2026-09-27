import '../../../models/iptv_playlist.dart';

/// Hydrates the existing live-only favourites projection in stored map order.
/// Custom lists have a different media-type contract and do not use this mapping.
class HomeIptvFavoritesRepository {
  const HomeIptvFavoritesRepository({
    required Future<Map<String, Map<String, dynamic>>> Function() favorites,
    required Map<String, String> Function(Map<String, dynamic>) headers,
  }) : _favorites = favorites,
       _headers = headers;

  final Future<Map<String, Map<String, dynamic>>> Function() _favorites;
  final Map<String, String> Function(Map<String, dynamic>) _headers;

  /// Null denotes retirement; malformed metadata and read failures propagate to
  /// the controller's existing silent-retention policy.
  Future<List<IptvChannel>?> read({required bool Function() isCurrent}) async {
    if (!isCurrent()) return null;
    final map = await _favorites();
    if (!isCurrent()) return null;
    return List.unmodifiable([
      for (final entry in map.entries)
        IptvChannel(
          name: entry.value['name'] as String? ?? 'Unknown Channel',
          url: entry.key,
          logoUrl: entry.value['logoUrl'] as String?,
          group: entry.value['group'] as String?,
          duration: -1,
          attributes: const {},
          httpHeaders: Map.unmodifiable(_headers(entry.value)),
        ),
    ]);
  }
}
