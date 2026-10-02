import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/storage/playlist_artwork_storage.dart';
import 'package:flutter/foundation.dart';

final class SeriesPosterPersistence {
  /// Save series poster URL to playlist item (Android TV flow)
  static Future<void> saveSeriesPosterToPlaylist(
    SeriesPlaylist seriesPlaylist, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
  }) async {
    final posterUrl = seriesPlaylist.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) return;

    if ((rdTorrentId == null || rdTorrentId.isEmpty) &&
        (torboxTorrentId == null || torboxTorrentId.isEmpty) &&
        (pikpakCollectionId == null || pikpakCollectionId.isEmpty) &&
        (webDavPath == null || webDavPath.isEmpty)) {
      return;
    }

    try {
      if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
      if (webDavPath != null && webDavPath.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          webDavServerId: webDavServerId,
          webDavBaseUrl: webDavBaseUrl,
          webDavPath: webDavPath,
        );
      }
    } catch (e) {
      debugPrint('Error saving poster: $e');
    }
  }
}
