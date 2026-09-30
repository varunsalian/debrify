import '../../../services/storage_service.dart';
import '../../../services/stremio_iptv_service.dart';
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

  static Future<void> recordWatch(IptvChannel channel) =>
      StorageService.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: channel.attributes['list_playlist_id'],
        httpHeaders: channel.httpHeaders.isEmpty ? null : channel.httpHeaders,
      );

  static Future<List<IptvPlaylist>> playlists() =>
      StorageService.getIptvPlaylists(forSettings: false);

  static bool isStremioChannelUrl(String url) =>
      StremioIptvService.isStremioChannelUrl(url);

  static Future<List<StremioIptvCandidate>> resolveCandidates(
    String url, {
    required bool refreshIfEmpty,
  }) => StremioIptvService.instance.resolveCandidates(
    url,
    refreshIfEmpty: refreshIfEmpty,
  );

  static String unplayableMessage(String url, String name) =>
      StremioIptvService.instance.unplayableMessage(url, name);

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
