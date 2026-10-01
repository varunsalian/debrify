import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:flutter/foundation.dart';

final class EpisodeCompletionStorage {
  const EpisodeCompletionStorage._();

  /// Mark an episode as finished (watched completely)
  static Future<void> markEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
    int? recoveryUpdatedAtMs,
  }) async {
    // Recovery is a historical observation, not a new playback event. Both
    // records must keep its original time so the latest episode remains last.
    final completedAtMs = recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'finishedEpisodes': {},
      };
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }

    // Ensure seasons map exists
    if (!seriesData.containsKey('seasons')) {
      seriesData['seasons'] = {};
    }

    // Ensure finishedEpisodes map exists
    if (!seriesData.containsKey('finishedEpisodes')) {
      seriesData['finishedEpisodes'] = {};
    }

    if (!seriesData['finishedEpisodes'].containsKey(season.toString())) {
      seriesData['finishedEpisodes'][season.toString()] = {};
    }

    seriesData['finishedEpisodes'][season.toString()][episode.toString()] = {
      'finishedAt': completedAtMs,
    };

    // Also add/update in seasons map so it appears in getEpisodeProgress()
    // This ensures UI can find the episode even if it was never played
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    final episodeData = seriesData['seasons'][season.toString()][episode.toString()];

    if (episodeData == null) {
      // Episode was never played - add dummy data to mark as watched
      seriesData['seasons'][season.toString()][episode.toString()] = {
        'positionMs': 0,
        'durationMs': 1,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': completedAtMs,
      };
    } else {
      // Episode has existing progress - update it to show as finished
      // Set position = duration to show 100% progress
      final existingData = episodeData as Map<String, dynamic>;
      // A later rewatch can already be saved while the older watched marker
      // is still pending. Preserve that newer bookmark when filling the gap.
      if (recoveryUpdatedAtMs == null || (existingData['updatedAt'] as num? ?? 0) <= completedAtMs) {
        final durationMs = existingData['durationMs'] as int? ?? 1;
        existingData['positionMs'] = durationMs; // Mark as fully watched
        existingData['updatedAt'] = completedAtMs;
        existingData.remove('recoveryCheckpointId');
      }
    }

    debugPrint(
      'StorageService: markEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
    );

    await PlaybackStateStore.savePlaybackStateMap(map);
    LocalCompletionStorage.localCompletionRevision.value++;
  }

  /// Unmark an episode as finished (mark as unwatched)
  static Future<void> unmarkEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final currentTitleKey = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty ? null : normalizedImdbId;
    var changed = false;
    var aliasesChanged = 0;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> || seriesData['type'] != 'series') {
        continue;
      }
      final storedImdbId = seriesData['imdbId']?.toString().trim().toLowerCase();
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final matchesStableId = stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      if (_clearEpisodeCompletion(
        seriesData: seriesData,
        season: season,
        episode: episode,
      )) {
        changed = true;
        aliasesChanged++;
      }
    }

    if (!changed) return;

    debugPrint(
      'StorageService: unmarkEpisodeAsFinished title="$seriesTitle" '
      'S${season}E$episode aliases=$aliasesChanged',
    );

    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    LocalCompletionStorage.localCompletionRevision.value++;
  }

  /// Clear every completed episode owned by a stable series identity.
  ///
  /// This is the local equivalent of removing a show from tracker history.
  /// Synthetic watched rows and completed checkpoints are cleared across all
  /// release-title aliases, while genuine partial rewatch progress survives.
  static Future<void> unmarkSeriesAsFinished(
    String imdbId, {
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final normalizedTitle = seriesTitle?.trim().toLowerCase();
    final map = await PlaybackStateStore.getPlaybackStateMap();
    var changed = false;

    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      final storedTitle = raw['title']?.toString().trim().toLowerCase();
      final matchesStableId = storedId == normalized;
      final matchesLegacyTitle =
          !PlaybackIdentityStorage.requiresExactProgressIdentity(normalized) &&
          !PlaybackIdentityStorage.requiresExactProgressIdentity(storedId) &&
          normalizedTitle != null &&
          normalizedTitle.isNotEmpty &&
          storedTitle == normalizedTitle;
      if (!matchesStableId && !matchesLegacyTitle) continue;

      final coordinates = <({int season, int episode})>{};
      void collect(Object? seasons) {
        if (seasons is! Map) return;
        for (final seasonEntry in seasons.entries) {
          final season = int.tryParse(seasonEntry.key.toString());
          final episodes = seasonEntry.value;
          if (season == null || episodes is! Map) continue;
          for (final episodeKey in episodes.keys) {
            final episode = int.tryParse(episodeKey.toString());
            if (episode != null) {
              coordinates.add((season: season, episode: episode));
            }
          }
        }
      }

      collect(raw['finishedEpisodes']);
      collect(raw['seasons']);
      for (final coordinate in coordinates) {
        if (_clearEpisodeCompletion(
          seriesData: raw,
          season: coordinate.season,
          episode: coordinate.episode,
        )) {
          changed = true;
        }
      }
    }

    if (!changed) return;
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    LocalCompletionStorage.localCompletionRevision.value++;
    debugPrint('StorageService: unmarkSeriesAsFinished imdbId="$normalized"');
  }

  /// Remove one episode's explicit completion and any synthetic/completed
  /// progress produced by marking it watched. Genuine partial progress remains
  /// intact, including a rewatch in progress under another title alias.
  static bool _clearEpisodeCompletion({
    required Map<String, dynamic> seriesData,
    required int season,
    required int episode,
  }) {
    final seasonKey = season.toString();
    final episodeKey = episode.toString();
    var changed = false;

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes is Map) {
      final seasonData = finishedEpisodes[seasonKey];
      if (seasonData is Map && seasonData.containsKey(episodeKey)) {
        seasonData.remove(episodeKey);
        if (seasonData.isEmpty) finishedEpisodes.remove(seasonKey);
        changed = true;
      }
    }

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return changed;
    final seasonData = seasons[seasonKey];
    if (seasonData is! Map) return changed;
    final episodeData = seasonData[episodeKey];
    if (episodeData is! Map) return changed;

    final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
    final isDummy = positionMs == 0 && durationMs == 1;
    final isCompleted = durationMs > 0 && positionMs >= durationMs;
    // Unwatching a fully-watched episode DROPS its row. Zeroing the offset
    // instead used to leave a "played, 0% in, not finished" ghost carrying a
    // fresh updatedAt, which then won `getLastPlayedEpisode*` and pinned
    // Continue Watching to an episode the user had just declared unwatched —
    // and every repeat of mark→unmark re-stamped it fresher.
    if (isDummy || isCompleted) {
      seasonData.remove(episodeKey);
      if (seasonData.isEmpty) seasons.remove(seasonKey);
      return true;
    }
    // Reached only for rows that were never marked watched through
    // [markEpisodeAsFinished] (it overwrites positionMs with durationMs, so a
    // marked row always lands in the branch above). A genuine partial — e.g. a
    // rewatch in progress under another title alias, swept by
    // [unmarkSeriesAsFinished] — keeps its offset.
    return changed;
  }
}
