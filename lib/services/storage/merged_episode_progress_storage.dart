import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';

final class MergedEpisodeProgressStorage {
  const MergedEpisodeProgressStorage._();

  /// Get episode progress by IMDB ID (scans playback state for matching imdbId)
  /// Also checks single-file video entries and parses season/episode from title.
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgressByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final normalizedImdbId = imdbId.trim().toLowerCase();

    // Merge every legacy title-keyed series entry with this IMDb id. Older
    // builds could save the same show under multiple release-derived titles;
    // stopping at the first record silently hid episodes from the others.
    final seriesResult = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId']?.toString().trim().toLowerCase() == normalizedImdbId) {
        if (entry['type'] == 'series') {
          final seasons = entry['seasons'];
          if (seasons is! Map) continue;
          for (final seasonEntry in seasons.entries) {
            final episodes = seasonEntry.value;
            if (episodes is! Map) continue;
            for (final episodeEntry in episodes.entries) {
              final episodeData = episodeEntry.value;
              if (episodeData is! Map) continue;
              final episodeKey = '${seasonEntry.key}_${episodeEntry.key}';
              final candidate = Map<String, dynamic>.from(episodeData);
              final existing = seriesResult[episodeKey];
              final candidateUpdatedAt = (candidate['updatedAt'] as num?)?.toInt() ?? 0;
              final existingUpdatedAt = (existing?['updatedAt'] as num?)?.toInt() ?? -1;
              if (candidateUpdatedAt >= existingUpdatedAt) {
                seriesResult[episodeKey] = candidate;
              }
            }
          }
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesResult.isNotEmpty) return seriesResult;

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        return {
          '${season}_$episode': {
            'positionMs': videoFallback['positionMs'] ?? 0,
            'durationMs': videoFallback['durationMs'] ?? 1,
            'updatedAt': videoFallback['updatedAt'] ?? 0,
          },
        };
      }
    }

    return {};
  }

  /// Merge local episode progress across stable IMDb identity and the current
  /// title-keyed record. The newest update wins duplicate coordinates. Equal
  /// or missing timestamps prefer the current title deterministically, which
  /// preserves legacy behavior without letting an older title record move a
  /// newer cross-alias resume position backwards.
  static Future<Map<String, Map<String, dynamic>>> getMergedEpisodeProgress({
    required String seriesTitle,
    String? imdbId,
  }) async {
    if (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
        (imdbId?.startsWith('medialibrary:') ?? false)) {
      return getEpisodeProgressByImdbId(imdbId!);
    }
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getEpisodeProgressByImdbId(imdbId)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
      if (seriesTitle.isNotEmpty)
        EpisodeProgressStorage.getEpisodeProgress(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
    ]);
    int updatedAt(Map<String, dynamic> state) {
      final value = state['updatedAt'];
      if (value is! num || !value.isFinite) return 0;
      final timestamp = value.toInt();
      return timestamp > 0 ? timestamp : 0;
    }

    final merged = Map<String, Map<String, dynamic>>.from(reads[0]);
    for (final entry in reads[1].entries) {
      final previous = merged[entry.key];
      if (previous == null || updatedAt(entry.value) >= updatedAt(previous)) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  /// IMDb-aware counterpart to `EpisodeProgressStorage.getFinishedEpisodes`, unioning historical
  /// release-title records with the current title record.
  static Future<Map<String, Set<int>>> getMergedFinishedEpisodes({
    required String seriesTitle,
    String? imdbId,
  }) async {
    if (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
        (imdbId?.startsWith('medialibrary:') ?? false)) {
      return EpisodeProgressStorage.getFinishedEpisodesByImdbId(imdbId: imdbId!);
    }
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        EpisodeProgressStorage.getFinishedEpisodesByImdbId(imdbId: imdbId)
      else
        Future.value(const <String, Set<int>>{}),
      if (seriesTitle.isNotEmpty)
        EpisodeProgressStorage.getFinishedEpisodes(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Set<int>>{}),
    ]);
    final merged = <String, Set<int>>{};
    for (final snapshot in reads) {
      for (final entry in snapshot.entries) {
        merged.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }
    return merged;
  }

  /// Get finished episodes for a specific season
  static Future<Set<int>> getFinishedEpisodesForSeason({
    required String seriesTitle,
    required int season,
  }) async {
    final allFinished = await EpisodeProgressStorage.getFinishedEpisodes(seriesTitle: seriesTitle);
    return allFinished[season.toString()] ?? <int>{};
  }
}
