import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:flutter/foundation.dart';

final class SeriesProgressStorage {
  const SeriesProgressStorage._();

  /// Exact series reset; never touches source bindings or unrelated titles.
  static Future<void> clearSeriesWatchProgress(
    String imdbId,
    String title,
  ) async {
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty) throw ArgumentError.value(imdbId, 'imdbId');
    final map = await PlaybackStateStore.getPlaybackStateMap();
    map.removeWhere((key, raw) {
      if (raw is! Map) return false;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      return storedId == id ||
          (!PlaybackIdentityStorage.requiresExactProgressIdentity(id) &&
              (storedId == null || storedId.isEmpty) &&
              raw['type'] == 'series' &&
              raw['title']?.toString().trim().toLowerCase() == title.trim().toLowerCase());
    });
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    await MovieProgressStorage.setSeriesExplicitlyWatched(id, watched: false);
    await TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(imdbId: id, percents: {});
    await TrackerEpisodeProgressStorage.saveEpisodeSimklProgress(imdbId: id, percents: {});
    await TrackerEpisodeProgressStorage.saveEpisodeMdblistProgress(imdbId: id, percents: {});
    LocalCompletionStorage.localCompletionRevision.value++;
  }

  static Future<void> saveSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
    String? recoveryCheckpointId,
    int? recoveryUpdatedAtMs,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    if (!map.containsKey(key)) {
      map[key] = {'type': 'series', 'title': seriesTitle, 'seasons': {}};
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided (enables lookup by IMDB ID)
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    seriesData['seasons'][season.toString()][episode.toString()] = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      if (recoveryCheckpointId != null) 'recoveryCheckpointId': recoveryCheckpointId,
    };

    debugPrint(
      'StorageService: saveSeriesPlaybackState title="$seriesTitle" S${season}E$episode position=${positionMs}ms duration=${durationMs}ms',
    );

    await PlaybackStateStore.savePlaybackStateMap(map);
  }

  /// Get playback state for series content
  static Future<Map<String, dynamic>?> getSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;

    final seasonData = seriesData['seasons'][season.toString()];
    if (seasonData == null) return null;

    final episodeData = seasonData[episode.toString()];
    if (episodeData == null) return null;

    return episodeData as Map<String, dynamic>;
  }
}
