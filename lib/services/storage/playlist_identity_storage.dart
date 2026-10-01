import 'package:debrify/services/storage/playlist_storage.dart';

final class PlaylistIdentityStorage {
  const PlaylistIdentityStorage._();

  // TVMaze Series Mapping Methods

  /// Get a unique key for a playlist item based on available identifiers
  // Shared within lib/services/storage/.
  static String getPlaylistItemUniqueKeyInternal(Map<String, dynamic> playlistItem) {
    final provider = ((playlistItem['provider'] as String?) ?? 'realdebrid').toLowerCase();

    if (provider == 'webdav') {
      return PlaylistStorage.computePlaylistDedupeKey(playlistItem);
    }

    // Try different identifiers in order of preference
    if (playlistItem['rdTorrentId'] != null) {
      return 'rd_${playlistItem['rdTorrentId']}';
    }
    if (playlistItem['torrent_hash'] != null) {
      return 'hash_${playlistItem['torrent_hash']}';
    }
    if (playlistItem['torboxTorrentId'] != null) {
      return 'torbox_${playlistItem['torboxTorrentId']}';
    }
    if (playlistItem['pikpakFileId'] != null) {
      return 'pikpak_${playlistItem['pikpakFileId']}';
    }
    // Fallback to title if nothing else is available
    final title =
        (playlistItem['title'] as String?)?.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '_',
        ) ??
        'unknown';
    return 'title_$title';
  }

  /// Get the unique key for a playlist item (public accessor for batch lookups)
  static String getPlaylistItemUniqueKey(Map<String, dynamic> item) => getPlaylistItemUniqueKeyInternal(item);
}
