import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentProgressDeps = ({
  PlaylistContentSeriesState seriesState,
  PlaylistContentCatalogState catalogState,
  void Function(List<RDFileNode> videoFiles) applySortedPlaylistOrder,
  bool Function() mounted,
  Map<String, dynamic> Function() playlistItem,
  void Function(VoidCallback) setState,
});

class PlaylistContentProgress {
  PlaylistContentProgress(this._deps);
  final PlaylistContentProgressDeps _deps;

  /// Get progress data for a specific file
  Map<String, dynamic>? getProgressForFile(RDFileNode file) {
    // ALWAYS try to parse season/episode from filename first (regardless of view mode)
    // This ensures progress is consistent across Raw and Series Arrange modes
    final seriesInfo = SeriesParser.parseFilename(file.name);
    if (seriesInfo.season != null && seriesInfo.episode != null) {
      final key = '${seriesInfo.season}_${seriesInfo.episode}';
      final progressData = _deps.seriesState.fileProgressCache[key];
      if (progressData != null) {
        return progressData;
      }
    }

    // Fallback: For files without parseable season/episode, use sequential indexing
    // This is for non-series content like movies or special features
    if (_deps.catalogState.rootContent != null) {
      final allFiles = _deps.catalogState.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      // IMPORTANT: Apply sorting if in sortedAZ mode to match the index used when saving progress
      // When playing in Sort A-Z mode, progress is saved using indices from the sorted list,
      // so we must apply the same sorting here to look up the correct progress key
      _deps.applySortedPlaylistOrder(videoFiles);

      final fileIndex = videoFiles.indexWhere(
        (node) => node.name == file.name && node.path == file.path,
      );

      if (fileIndex >= 0) {
        final key = '0_${fileIndex + 1}'; // season 0, 1-based episode index
        return _deps.seriesState.fileProgressCache[key];
      }
    }

    // Final fallback: try using filename as key
    return _deps.seriesState.fileProgressCache[file.name];
  }

  /// Determine initial season based on most recently watched episode
  /// Returns the season number to start with (defaults to 1 if no progress)
  int determineInitialSeason() {
    if (_deps.seriesState.fileProgressCache.isEmpty) return 1;

    // Find most recently watched episode
    String? mostRecentKey;
    int? mostRecentTimestamp;

    for (var entry in _deps.seriesState.fileProgressCache.entries) {
      final updatedAt = entry.value['updatedAt'];
      if (updatedAt != null) {
        try {
          // Handle both int (milliseconds) and String formats
          int timestamp;
          if (updatedAt is int) {
            // Assume it's already in milliseconds (most common format)
            timestamp = updatedAt;
          } else if (updatedAt is String) {
            // Try parsing as numeric timestamp first, then as ISO date string
            final parsed = int.tryParse(updatedAt);
            if (parsed != null) {
              // Detect if it's likely seconds (10 digits) vs milliseconds (13 digits)
              // Unix timestamp in seconds: ~10 digits (e.g., 1735134769)
              // Unix timestamp in milliseconds: ~13 digits (e.g., 1735134769000)
              if (parsed < 10000000000) {
                // Likely seconds, convert to milliseconds
                timestamp = parsed * 1000;
              } else {
                // Already milliseconds
                timestamp = parsed;
              }
            } else {
              // Parse as ISO date string
              timestamp = DateTime.parse(updatedAt).millisecondsSinceEpoch;
            }
          } else {
            continue;
          }

          if (mostRecentTimestamp == null || timestamp > mostRecentTimestamp) {
            mostRecentTimestamp = timestamp;
            mostRecentKey = entry.key;
          }
        } catch (e) {
          print(
            '⚠️ Failed to parse updatedAt timestamp: $updatedAt (${e.toString()})',
          );
        }
      }
    }

    if (mostRecentKey != null) {
      // Extract season from key format "{season}_{episode}"
      final parts = mostRecentKey.split('_');
      if (parts.length >= 2) {
        final seasonNum = int.tryParse(parts[0]);
        if (seasonNum != null) {
          print(
            '🎯 Found most recent season: $seasonNum from key: $mostRecentKey',
          );
          return seasonNum;
        }
      }
    }

    print('📺 No recent progress found, defaulting to Season 1');
    return 1; // Default to season 1
  }

  /// Determine initial episode index to scroll to within the selected season
  /// Returns the episode index (0-based) or null if no specific episode to scroll to
  int? determineInitialEpisodeIndex(SeriesSeason season) {
    if (_deps.seriesState.fileProgressCache.isEmpty) return null;

    // Find most recently watched episode in this season
    int? mostRecentTimestamp;
    int? mostRecentEpisodeNum;

    for (var entry in _deps.seriesState.fileProgressCache.entries) {
      final key = entry.key;
      final parts = key.split('_');

      if (parts.length >= 2) {
        final seasonNum = int.tryParse(parts[0]);
        final episodeNum = int.tryParse(parts[1]);

        // Only consider episodes from the current season
        if (seasonNum == season.seasonNumber && episodeNum != null) {
          final updatedAt = entry.value['updatedAt'];
          if (updatedAt != null) {
            try {
              // Handle both int (milliseconds) and String formats
              int timestamp;
              if (updatedAt is int) {
                // Assume it's already in milliseconds (most common format)
                timestamp = updatedAt;
              } else if (updatedAt is String) {
                // Try parsing as numeric timestamp first, then as ISO date string
                final parsed = int.tryParse(updatedAt);
                if (parsed != null) {
                  // Detect if it's likely seconds (10 digits) vs milliseconds (13 digits)
                  // Unix timestamp in seconds: ~10 digits (e.g., 1735134769)
                  // Unix timestamp in milliseconds: ~13 digits (e.g., 1735134769000)
                  if (parsed < 10000000000) {
                    // Likely seconds, convert to milliseconds
                    timestamp = parsed * 1000;
                  } else {
                    // Already milliseconds
                    timestamp = parsed;
                  }
                } else {
                  // Parse as ISO date string
                  timestamp = DateTime.parse(updatedAt).millisecondsSinceEpoch;
                }
              } else {
                continue;
              }

              if (mostRecentTimestamp == null ||
                  timestamp > mostRecentTimestamp) {
                mostRecentTimestamp = timestamp;
                mostRecentEpisodeNum = episodeNum;
              }
            } catch (e) {
              print(
                '⚠️ Failed to parse updatedAt timestamp: $updatedAt (${e.toString()})',
              );
            }
          }
        }
      }
    }

    if (mostRecentEpisodeNum != null) {
      // Find the episode index in the season's episode list
      for (int i = 0; i < season.episodes.length; i++) {
        final episode = season.episodes[i];
        if (episode.seriesInfo.episode == mostRecentEpisodeNum) {
          print(
            '🎯 Found most recent episode in season: Episode $mostRecentEpisodeNum at index $i',
          );
          return i;
        }
      }
    }

    return null; // No specific episode to scroll to
  }

  /// Reload progress data from storage
  /// Called when returning from video player to refresh progress indicators
  Future<void> reloadProgress() async {
    if (!_deps.mounted()) return;

    try {
      // Get the series/collection title from the playlist item
      // IMPORTANT: Use same logic as _parseSeriesPlaylist() for consistency
      final String? seriesTitle =
          _deps.seriesState.seriesPlaylist?.seriesTitle ??
          _deps.playlistItem()['title'] as String?;

      if (seriesTitle != null && seriesTitle.isNotEmpty) {
        print('🔄 Reloading progress after video playback for: $seriesTitle');
        final episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
          seriesTitle: seriesTitle,
        );

        if (!_deps.mounted()) return; // Check again after async operation

        print(
          '📊 Reloaded ${episodeProgress.length} episodes with updated progress',
        );
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');

        _deps.setState(() {
          _deps.seriesState.fileProgressCache = episodeProgress;
        });
      }
    } catch (e) {
      print('❌ Error reloading progress data: $e');
      // Don't rethrow - this is a non-critical background operation
    }
  }
}
