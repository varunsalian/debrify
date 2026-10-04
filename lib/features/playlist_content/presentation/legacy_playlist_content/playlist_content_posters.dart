import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/services/storage/playlist_artwork_storage.dart';
import 'package:debrify/services/storage/playlist_poster_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentPostersDeps = ({
  PlaylistContentSeriesState seriesState,
  Map<String, dynamic> Function() playlistItem,
});

class PlaylistContentPosters {
  PlaylistContentPosters(this._deps);
  final PlaylistContentPostersDeps _deps;

  Future<void> saveDetectedSeriesPosterToPlaylist() async {
    final posterUrl = _deps.seriesState.seriesPlaylist?.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) return;

    try {
      await PlaylistPosterStorage.savePlaylistPosterOverride(
        playlistItem: _deps.playlistItem(),
        posterUrl: posterUrl,
      );

      final itemKey = PlaylistStorage.computePlaylistDedupeKey(
        _deps.playlistItem(),
      );
      final items = await PlaylistStorage.getPlaylistItemsRaw();
      final itemIndex = items.indexWhere(
        (item) => PlaylistStorage.computePlaylistDedupeKey(item) == itemKey,
      );

      if (itemIndex >= 0) {
        items[itemIndex]['posterUrl'] = posterUrl;
        await PlaylistStorage.savePlaylistItemsRaw(items);
      }
    } catch (e) {
      debugPrint('Error saving detected series poster: $e');
    }
  }

  /// Update the playlist item's poster/cover image with the TVMaze show poster
  Future<void> updatePlaylistPoster(Map<String, dynamic> showInfo) async {
    try {
      // Extract poster URL from TVMaze show data
      // TVMaze provides 'image' with 'medium' and 'original' URLs
      final image = showInfo['image'];
      String? posterUrl;

      if (image != null && image is Map<String, dynamic>) {
        // Prefer original over medium for better quality
        posterUrl = image['original'] as String? ?? image['medium'] as String?;
      }

      if (posterUrl == null || posterUrl.isEmpty) {
        print('No poster URL found in TVMaze show data');
        return;
      }

      print('🎬 Updating playlist poster with: $posterUrl');

      // CRITICAL: Save poster override to persistent storage
      // This ensures the poster persists across app restarts
      await PlaylistPosterStorage.savePlaylistPosterOverride(
        playlistItem: _deps.playlistItem(),
        posterUrl: posterUrl,
      );

      // Also update the in-memory playlist item for immediate UI update
      final provider =
          (_deps.playlistItem()['provider'] as String?) ?? 'realdebrid';
      bool updated = false;

      if (provider.toLowerCase() == 'realdebrid') {
        final rdTorrentId = _deps.playlistItem()['rdTorrentId'] as String?;
        if (rdTorrentId != null) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            rdTorrentId: rdTorrentId,
          );
        }
      } else if (provider.toLowerCase() == 'torbox') {
        final torboxTorrentId = _deps.playlistItem()['torboxTorrentId'];
        if (torboxTorrentId != null) {
          // Torbox uses integer IDs, but updatePlaylistItemPoster expects String
          // We need to update the playlist manually
          final items = await PlaylistStorage.getPlaylistItemsRaw();
          final itemIndex = items.indexWhere(
            (item) => item['torboxTorrentId'] == torboxTorrentId,
          );

          if (itemIndex >= 0) {
            items[itemIndex]['posterUrl'] = posterUrl;
            await PlaylistStorage.savePlaylistItemsRaw(items);
            updated = true;
          }
        }
      } else if (provider.toLowerCase() == 'pikpak') {
        final pikpakCollectionId =
            _deps.playlistItem()['pikpakFileId'] as String?;
        if (pikpakCollectionId != null) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            pikpakCollectionId: pikpakCollectionId,
          );
        }
      } else if (provider.toLowerCase() == 'premiumize') {
        final premiumizeHash = _deps.playlistItem()['torrent_hash'] as String?;
        final premiumizeItemId = _deps
            .playlistItem()['premiumizeItemId']
            ?.toString();
        if (premiumizeHash != null && premiumizeHash.isNotEmpty) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            premiumizeHash: premiumizeHash,
          );
        } else if (premiumizeItemId != null && premiumizeItemId.isNotEmpty) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            premiumizeItemId: premiumizeItemId,
          );
        }
      } else if (provider.toLowerCase() == 'alldebrid') {
        final allDebridHash = _deps.playlistItem()['torrent_hash'] as String?;
        if (allDebridHash != null && allDebridHash.isNotEmpty) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            allDebridHash: allDebridHash,
          );
        }
      }

      if (updated) {
        print(
          '✅ Successfully updated playlist poster in memory and persistent storage',
        );
      } else {
        print(
          '⚠️ Updated persistent storage but in-memory update failed - poster will still persist on restart',
        );
      }
    } catch (e) {
      print('❌ Error updating playlist poster: $e');
    }
  }
}
