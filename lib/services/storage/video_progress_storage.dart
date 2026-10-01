import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';

final class VideoProgressStorage {
  const VideoProgressStorage._();

  /// Save playback state for non-series content (movies, single videos)
  static Future<void> saveVideoPlaybackState({
    required String videoTitle,
    required String videoUrl,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
    String? recoveryCheckpointId,
    int? recoveryUpdatedAtMs,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
            (imdbId?.startsWith('medialibrary:') ?? false))
        ? 'video_${imdbId}_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    map[key] = {
      'type': 'video',
      'title': videoTitle,
      'url': videoUrl,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      if (recoveryCheckpointId != null) 'recoveryCheckpointId': recoveryCheckpointId,
      if (imdbId != null) 'imdbId': imdbId,
    };

    await PlaybackStateStore.savePlaybackStateMap(map);
  }

  /// Get playback state for non-series content
  static Future<Map<String, dynamic>?> getVideoPlaybackState({
    required String videoTitle,
    bool includeFinished = false,
    String? contentIdentity,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        (PlaybackIdentityStorage.requiresExactProgressIdentity(contentIdentity) ||
            (contentIdentity?.startsWith('medialibrary:') ?? false))
        ? 'video_${contentIdentity}_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    final imdbId = (videoData['imdbId'] as String?)?.trim();
    // A finished movie can have a stale source-specific state from a final
    // autosave tick. Its local completion record wins over that stale resume.
    if (!includeFinished && imdbId != null && imdbId.isNotEmpty && await MovieProgressStorage.isMovieFinished(imdbId)) {
      return null;
    }

    return videoData as Map<String, dynamic>;
  }

  /// Get video playback state by IMDB ID (scans all video entries, returns most recent).
  static Future<Map<String, dynamic>?> getVideoPlaybackStateByImdbId(
    String imdbId,
  ) async {
    // A blank id would match every record saved without one and hand back an
    // unrelated movie's position.
    final wanted = imdbId.trim();
    if (wanted.isEmpty) return null;
    // A completion write and the periodic player autosave can overlap by one
    // tick. The finished marker is authoritative for movies, so never expose
    // a stale resume record that slipped back in during that tiny window.
    if (await MovieProgressStorage.isMovieFinished(wanted)) return null;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    Map<String, dynamic>? best;
    int bestUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is! Map<String, dynamic> || entry['type'] != 'video') continue;
      // Pattern-matched, not cast: one malformed legacy record must not throw
      // out of a scan over every saved video.
      final recorded = entry['imdbId'];
      if (recorded is String && recorded.trim() == wanted) {
        final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
        if (updatedAt > bestUpdatedAt) {
          bestUpdatedAt = updatedAt;
          best = entry;
        }
      }
    }
    return best;
  }
}
