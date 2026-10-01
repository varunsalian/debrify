import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/foundation.dart';

final class PlaylistProgressStorage {
  const PlaylistProgressStorage._();

  /// Clear all progress data for a specific playlist/series
  static Future<void> clearPlaylistProgress({required String title}) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();

    debugPrint('StorageService: clearPlaylistProgress called for "$title"');

    final keysToRemove = <String>[];

    // Use the SAME matching logic as when finding series progress
    // Try multiple title variations to find all matching entries

    // Variation 1: Use the full playlist item title
    final fullTitleKey = 'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final fullVideoKey = 'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    // Variation 2: Try extracting clean title (like "breaking bad" from "Breaking.Bad.SEASON.01.S01...")
    // This matches how SeriesPlaylist extracts the title
    String cleanedTitle = title;

    // Remove common patterns to extract series name
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.S\d{2}.*', caseSensitive: false),
      '',
    ); // Remove S01-S08 and everything after
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.Season\..*', caseSensitive: false),
      '',
    ); // Remove Season.1-8
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
      '',
    ); // Remove quality
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
      '',
    ); // Remove codec
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
      '',
    ); // Remove source
    cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

    final cleanTitleKey = 'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final cleanVideoKey = 'video_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    debugPrint(
      'StorageService: checking keys - full: $fullTitleKey / $fullVideoKey, clean: $cleanTitleKey / $cleanVideoKey',
    );
    debugPrint('StorageService: available keys: ${map.keys.toList()}');

    // Check for exact key matches first
    for (final key in [
      cleanTitleKey,
      cleanVideoKey,
      fullTitleKey,
      fullVideoKey,
    ]) {
      if (map.containsKey(key) && !keysToRemove.contains(key)) {
        keysToRemove.add(key);
        debugPrint('StorageService: exact key match: "$key"');
      }
    }

    // Fallback: Search through all series/video entries
    // Check if the input title contains the stored series title
    // This handles cases where playlist title is "Game of Thrones - Season 3" but stored title is "game of thrones"
    for (final entry in map.entries) {
      if ((entry.key.startsWith('series_') || entry.key.startsWith('video_')) &&
          entry.value is Map<String, dynamic> &&
          !keysToRemove.contains(entry.key)) {
        final storedTitle = (entry.value['title'] as String?)?.toLowerCase() ?? '';
        if (storedTitle.isEmpty) continue;

        final titleLower = title.toLowerCase();
        final cleanedTitleLower = cleanedTitle.toLowerCase();

        // Check if the stored series title matches in several ways:
        // 1. Exact match with cleaned title (e.g., "game of thrones" == "game of thrones")
        // 2. Input title contains the stored series title (e.g., "game of thrones - season 3" contains "game of thrones")
        // 3. Cleaned title contains the stored series title
        if (storedTitle == cleanedTitleLower ||
            storedTitle == titleLower ||
            (titleLower.contains(storedTitle) && storedTitle.split(' ').length >= 2)) {
          keysToRemove.add(entry.key);
          debugPrint(
            'StorageService: stored title match - key: "${entry.key}", storedTitle: "$storedTitle"',
          );
        }
      }
    }

    // Remove all matching keys
    for (final key in keysToRemove) {
      map.remove(key);
      debugPrint('StorageService: removed progress entry with key: "$key"');
    }

    // Save the updated map if anything was removed
    if (keysToRemove.isNotEmpty) {
      await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
      // Finished episodes live in this same map. Re-derive local series
      // completion so watched badges and Continue Watching update immediately.
      StorageService.localCompletionRevision.value++;
      debugPrint(
        'StorageService: clearPlaylistProgress completed - removed ${keysToRemove.length} entries for "$title"',
      );
    } else {
      debugPrint('StorageService: no progress data found for "$title"');
    }
  }

  /// Build progress map for playlist items
  /// Maps playlist dedupe keys to their playback progress data
  static Future<Map<String, Map<String, dynamic>>> buildPlaylistProgressMap(
    List<Map<String, dynamic>> playlistItems,
  ) async {
    final progressMap = <String, Map<String, dynamic>>{};
    final playbackStateMap = await PlaybackStateStore.getPlaybackStateMap();

    for (final item in playlistItems) {
      final dedupeKey = PlaylistStorage.computePlaylistDedupeKey(item);
      final title = (item['title'] as String?) ?? '';

      // Try to find progress data for this item
      Map<String, dynamic>? progressData;

      // Check if it's stored as a video (single file)
      final videoKey = 'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      final videoState = playbackStateMap[videoKey];
      if (videoState != null && videoState['type'] == 'video') {
        progressData = {
          'positionMs': videoState['positionMs'] ?? 0,
          'durationMs': videoState['durationMs'] ?? 0,
          'updatedAt': videoState['updatedAt'] ?? 0,
        };
      }

      // Check if it's stored as a series
      if (progressData == null) {
        // Try multiple title variations to find the series state
        String? matchingSeriesKey;
        Map<String, dynamic>? seriesState;

        // Variation 1: Use the full playlist item title
        final fullTitleKey = 'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Variation 2: Try extracting clean title (like "game of thrones" from torrent name)
        // This matches how SeriesPlaylist extracts the title
        String cleanedTitle = title;

        // Remove common patterns to extract series name
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.S\d{2}.*', caseSensitive: false),
          '',
        ); // Remove S01-S08 and everything after
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.Season\..*', caseSensitive: false),
          '',
        ); // Remove Season.1-8
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
          '',
        ); // Remove quality
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
          '',
        ); // Remove codec
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
          '',
        ); // Remove source
        cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

        final cleanTitleKey = 'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Try both variations - PRIORITIZE clean title first (where playback state is actually saved)
        if (playbackStateMap[cleanTitleKey] != null && playbackStateMap[cleanTitleKey]['type'] == 'series') {
          matchingSeriesKey = cleanTitleKey;
          seriesState = playbackStateMap[cleanTitleKey] as Map<String, dynamic>;
        } else if (playbackStateMap[fullTitleKey] != null && playbackStateMap[fullTitleKey]['type'] == 'series') {
          matchingSeriesKey = fullTitleKey;
          seriesState = playbackStateMap[fullTitleKey] as Map<String, dynamic>;
        } else {
          // Fallback: Search through all series entries for a partial match
          for (final entry in playbackStateMap.entries) {
            if (entry.key.startsWith('series_') && entry.value['type'] == 'series') {
              final seriesTitle = (entry.value['title'] as String?)?.toLowerCase() ?? '';
              final itemTitleLower = title.toLowerCase();

              // Check if the series title is contained in the item title or vice versa
              if (itemTitleLower.contains(seriesTitle) || seriesTitle.contains(cleanedTitle.toLowerCase())) {
                matchingSeriesKey = entry.key;
                seriesState = entry.value as Map<String, dynamic>;
                break;
              }
            }
          }
        }

        if (seriesState != null && matchingSeriesKey != null) {
          debugPrint(
            '📺 Matched series state for "$title" using key: $matchingSeriesKey',
          );

          // Calculate overall series progress (Option 2)
          // Formula: (finished episodes + partial episode progress) / total episodes

          int totalEpisodes = (item['fileCount'] as int?) ?? (item['count'] as int?) ?? 0;
          if (totalEpisodes == 0) {
            // Try to count from the playlist item structure
            totalEpisodes = 1; // Fallback to at least 1
          }

          // Count finished episodes from both finishedEpisodes and seasons maps
          // Use a Set to track which episodes are finished to avoid double-counting
          final Set<String> finishedEpisodeKeys = {};
          int finishedEpisodeCount = 0;

          // First, count episodes explicitly marked as finished (TV series)
          final finishedEpisodes = seriesState['finishedEpisodes'] as Map<String, dynamic>?;
          if (finishedEpisodes != null) {
            for (final seasonEntry in finishedEpisodes.entries) {
              final seasonKey = seasonEntry.key;
              final seasonFinished = seasonEntry.value as Map<String, dynamic>;
              for (final episodeKey in seasonFinished.keys) {
                final key = '${seasonKey}_$episodeKey';
                finishedEpisodeKeys.add(key);
                finishedEpisodeCount++;
              }
            }
          }

          // Find the most recently played episode (for timestamp and partial progress)
          int latestPosition = 0;
          int latestDuration = 0;
          int latestUpdatedAt = 0;
          String? latestEpisodeKey;

          final seasons = seriesState['seasons'] as Map<String, dynamic>?;
          if (seasons != null) {
            for (final seasonEntry in seasons.entries) {
              final seasonKey = seasonEntry.key;
              final episodes = seasonEntry.value as Map<String, dynamic>;
              for (final episodeEntry in episodes.entries) {
                final episodeKey = episodeEntry.key;
                final episodeData = episodeEntry.value as Map<String, dynamic>;
                final positionMs = episodeData['positionMs'] as int? ?? 0;
                final durationMs = episodeData['durationMs'] as int? ?? 0;
                final updatedAt = episodeData['updatedAt'] as int? ?? 0;

                // Count as finished if >= 95% watched AND not already counted
                final key = '${seasonKey}_$episodeKey';
                if (durationMs > 0 && (positionMs / durationMs) >= 0.95) {
                  if (!finishedEpisodeKeys.contains(key)) {
                    finishedEpisodeKeys.add(key);
                    finishedEpisodeCount++;
                  }
                }

                // Track latest episode for partial progress
                if (updatedAt > latestUpdatedAt) {
                  latestUpdatedAt = updatedAt;
                  latestPosition = positionMs;
                  latestDuration = durationMs;
                  latestEpisodeKey = key;
                }
              }
            }
          }

          // Calculate partial progress from latest episode ONLY if not already counted as finished
          double partialEpisodeProgress = 0.0;
          bool hasPartialProgress = false;
          if (latestDuration > 0 && latestPosition > 0 && latestEpisodeKey != null) {
            partialEpisodeProgress = latestPosition / latestDuration;
            // Only count as partial if < 95% (not already counted as finished)
            if (partialEpisodeProgress < 0.95 && !finishedEpisodeKeys.contains(latestEpisodeKey)) {
              hasPartialProgress = true;
            }
          }

          if (latestUpdatedAt > 0 && totalEpisodes > 0) {
            // Calculate overall series progress
            double totalEpisodesWatched = finishedEpisodeCount.toDouble();
            if (hasPartialProgress) {
              totalEpisodesWatched += partialEpisodeProgress;
            }

            // Create synthetic position/duration representing series progress
            final syntheticDuration = totalEpisodes * 1000000; // 1M ms per episode (arbitrary)
            final syntheticPosition = (totalEpisodesWatched * 1000000).toInt();

            progressData = {
              'positionMs': syntheticPosition,
              'durationMs': syntheticDuration,
              'updatedAt': latestUpdatedAt,
            };

            debugPrint(
              'Series "$title": $finishedEpisodeCount finished + ${partialEpisodeProgress.toStringAsFixed(2)} partial = ${totalEpisodesWatched.toStringAsFixed(2)} / $totalEpisodes episodes (${((totalEpisodesWatched / totalEpisodes) * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      }

      if (progressData != null) {
        progressMap[dedupeKey] = progressData;
        debugPrint(
          'StorageService: Found progress for "$title" - ${progressData['positionMs']}ms / ${progressData['durationMs']}ms (${((progressData['positionMs'] / progressData['durationMs']) * 100).toStringAsFixed(1)}%)',
        );
      }
    }

    debugPrint(
      'StorageService: Built progress map with ${progressMap.length} entries',
    );
    return progressMap;
  }
}
