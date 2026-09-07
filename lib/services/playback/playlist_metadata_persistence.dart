import 'package:flutter/foundation.dart';

import '../../models/series_playlist.dart';
import '../storage/playback_progress_store.dart';

/// Writes TVMaze-discovered series metadata (imdb id, show poster) back to the
/// playlist item that launched playback, keyed by the launch identifiers.
///
/// Moved from `_VideoPlayerScreenState` (`_saveImdbIdToPlaylist`,
/// `_saveSeriesPosterToPlaylist`); the bodies are unchanged apart from taking
/// the launch identifiers as arguments instead of reading `widget.*`, and
/// logging through `debugPrint` so the service layer stays behind the
/// redacting sink that `PrivacyLog.install()` provides.
class PlaylistMetadataPersistence {
  const PlaylistMetadataPersistence._();

  static Future<void> saveImdbId(
    SeriesPlaylist seriesPlaylist, {
    required String? launchContentImdbId,
    required String? rdTorrentId,
    required String? torboxTorrentId,
    required String? pikpakCollectionId,
  }) async {
    final imdbId = seriesPlaylist.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (launchContentImdbId != null) return;

    await PlaybackProgressStore.updatePlaylistItemImdbId(
      imdbId,
      rdTorrentId: rdTorrentId,
      torboxTorrentId: torboxTorrentId,
      pikpakCollectionId: pikpakCollectionId,
    );
  }

  /// Save series poster URL to playlist item
  static Future<void> saveSeriesPoster(
    SeriesPlaylist seriesPlaylist, {
    required String? rdTorrentId,
    required String? torboxTorrentId,
    required String? pikpakCollectionId,
  }) async {
    debugPrint('🎬 _saveSeriesPosterToPlaylist called');
    debugPrint('  seriesTitle: ${seriesPlaylist.seriesTitle}');

    if (seriesPlaylist.seriesTitle == null) {
      debugPrint('  ⚠️ No series title, skipping poster save');
      return;
    }

    // Get identifiers from widget parameters

    debugPrint('  rdTorrentId: $rdTorrentId');
    debugPrint('  torboxTorrentId: $torboxTorrentId');
    debugPrint('  pikpakCollectionId: $pikpakCollectionId');

    // Need at least one identifier to save poster
    if ((rdTorrentId == null || rdTorrentId.isEmpty) &&
        (torboxTorrentId == null || torboxTorrentId.isEmpty) &&
        (pikpakCollectionId == null || pikpakCollectionId.isEmpty)) {
      debugPrint('  ⚠️ No valid identifier found, skipping poster save');
      return;
    }

    final posterUrl = seriesPlaylist.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) {
      debugPrint('  ⚠️ No poster URL from fetchEpisodeInfo');
      return;
    }

    debugPrint('  Poster URL: $posterUrl');
    try {
      if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
        await PlaybackProgressStore.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await PlaybackProgressStore.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await PlaybackProgressStore.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
    } catch (e) {
      debugPrint('  ❌ Error saving poster: $e');
    }
  }
}
