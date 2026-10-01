import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:flutter/foundation.dart';

final class EpisodeResumeStorage {
  const EpisodeResumeStorage._();

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData is! Map || seriesData['type'] != 'series') return null;

    // Find the most recently updated episode. Parse defensively (matching
    // getVideoPlaybackStateByImdbId above): a corrupt or old-schema entry
    // must skip, not throw, on this resume hot path.
    Map<String, dynamic>? lastEpisode;
    int lastUpdated = 0;

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return null;
    for (final seasonEntry in seasons.entries) {
      final season = int.tryParse(seasonEntry.key.toString());
      final episodes = seasonEntry.value;
      if (season == null || episodes is! Map) continue;

      for (final episodeEntry in episodes.entries) {
        final episode = int.tryParse(episodeEntry.key.toString());
        final episodeData = episodeEntry.value;
        if (episode == null || episodeData is! Map) continue;
        final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

        if (updatedAt > lastUpdated) {
          lastUpdated = updatedAt;
          lastEpisode = {
            'season': season,
            'episode': episode,
            ...Map<String, dynamic>.from(episodeData),
          };
        }
      }
    }

    if (lastEpisode != null) {
      debugPrint(
        'StorageService: getLastPlayedEpisode found S${lastEpisode['season']}E${lastEpisode['episode']} for "$seriesTitle"',
      );
    } else {
      debugPrint(
        'StorageService: getLastPlayedEpisode no episodes for "$seriesTitle"',
      );
    }

    return lastEpisode;
  }

  /// Get all episode watch progress for a series by IMDB ID.
  /// Returns a map of "season-episode" → progress percentage (0-100).
  static Future<Map<String, double>> getEpisodeWatchProgressByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, double>{};

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys). Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (seriesEntries.isEmpty && videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        final posMs = (videoFallback['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (videoFallback['durationMs'] as num?)?.toInt() ?? 1;
        if (durMs > 0 && posMs > 0) {
          result['$season-$episode'] = (posMs / durMs * 100).clamp(0.0, 100.0);
        }
        return result;
      }
    }

    if (seriesEntries.isEmpty) return result;

    // Aggregate progress across ALL matching series entries
    for (final seriesData in seriesEntries) {
      final finishedMap = seriesData['finishedEpisodes'] as Map<String, dynamic>?;

      final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
      for (final seasonEntry in seasons.entries) {
        final seasonNum = seasonEntry.key;
        final episodes = seasonEntry.value as Map<String, dynamic>? ?? {};

        // Get finished episodes for this season
        final finishedEps = finishedMap?[seasonNum] as Map<String, dynamic>?;

        for (final episodeEntry in episodes.entries) {
          final epNum = episodeEntry.key;
          final epData = episodeEntry.value as Map<String, dynamic>;
          final key = '$seasonNum-$epNum';

          // Check if finished first
          if (finishedEps != null && finishedEps.containsKey(epNum)) {
            result[key] = 100.0;
            continue;
          }

          final positionMs = (epData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (epData['durationMs'] as num?)?.toInt() ?? 1;
          if (durationMs > 0 && positionMs > 0) {
            final progress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
            // Keep higher progress if duplicate across entries
            if (!result.containsKey(key) || progress > result[key]!) {
              result[key] = progress;
            }
          }
        }
      }
    }

    return result;
  }

  /// Look up the last played episode by IMDB ID.
  /// Scans all series entries for a matching imdbId field.
  /// Also checks single-file video entries (type=video) as a fallback,
  /// parsing season/episode from the title.
  static Future<Map<String, dynamic>?> getLastPlayedEpisodeByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys, e.g. "young sheldon (2017)" vs "young sheldon").
    // Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesEntries.isNotEmpty) {
      // Find most recently updated episode across ALL matching series entries
      Map<String, dynamic>? lastEpisode;
      Map<String, dynamic>? lastEpisodeSeriesData; // track which entry it came from
      int lastUpdated = 0;

      for (final seriesData in seriesEntries) {
        final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
        for (final seasonEntry in seasons.entries) {
          final season = int.parse(seasonEntry.key);
          final episodes = seasonEntry.value as Map<String, dynamic>;

          for (final episodeEntry in episodes.entries) {
            final episode = int.parse(episodeEntry.key);
            final episodeData = episodeEntry.value as Map<String, dynamic>;
            final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

            if (updatedAt > lastUpdated) {
              lastUpdated = updatedAt;
              lastEpisode = {
                'season': season,
                'episode': episode,
                ...episodeData,
              };
              lastEpisodeSeriesData = seriesData;
            }
          }
        }
      }

      if (lastEpisode != null && lastEpisodeSeriesData != null) {
        // Check if this episode is marked as finished (in its own series entry)
        final finishedEpisodes = lastEpisodeSeriesData['finishedEpisodes'] as Map<String, dynamic>?;
        if (finishedEpisodes != null) {
          final seasonFinished = finishedEpisodes[lastEpisode['season'].toString()] as Map<String, dynamic>?;
          if (seasonFinished != null && seasonFinished.containsKey(lastEpisode['episode'].toString())) {
            lastEpisode['finished'] = true;
          }
        }
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId found S${lastEpisode['season']}E${lastEpisode['episode']} for "$imdbId"${lastEpisode['finished'] == true ? ' (finished)' : ''}',
        );
      }
      return lastEpisode;
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!);
        final episode = int.parse(match.group(2)!);
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId (video fallback) parsed S${season}E$episode from "$title" for "$imdbId"',
        );
        return {
          'season': season,
          'episode': episode,
          'positionMs': videoFallback['positionMs'] ?? 0,
          'durationMs': videoFallback['durationMs'] ?? 1,
          'updatedAt': videoFallback['updatedAt'] ?? 0,
        };
      }
    }

    return null;
  }
}
