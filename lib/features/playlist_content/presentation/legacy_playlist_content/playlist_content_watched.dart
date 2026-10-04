import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentWatchedDeps = ({
  PlaylistContentSeriesState seriesState,
  Map<String, dynamic> Function() playlistItem,
  Future<void> Function() reloadProgress,
  bool Function() mounted,
  BuildContext Function() context,
});

class PlaylistContentWatched {
  PlaylistContentWatched(this._deps);
  final PlaylistContentWatchedDeps _deps;

  /// Toggle the watched state of an episode
  Future<void> toggleWatchedState(SeriesEpisode episode) async {
    if (_deps.seriesState.seriesPlaylist == null) return;

    // Cloud-playlist rows are intentionally local-only: they have file/folder
    // identity but no reliable tracker title identity. Tracker-aware catalog
    // and detail actions fan out through WatchedActionCoordinator instead.

    // Get the series title for storage
    final String? seriesTitle =
        _deps.seriesState.seriesPlaylist!.seriesTitle ??
        _deps.playlistItem()['title'] as String?;

    if (seriesTitle == null || seriesTitle.isEmpty) {
      print('❌ Cannot toggle watched state: No series title available');
      return;
    }

    // Get episode details
    final season = episode.seriesInfo.season ?? 1;
    final episodeNum = episode.seriesInfo.episode ?? 1;
    final imdbId =
        _deps.seriesState.seriesPlaylist?.imdbId ??
        _deps.playlistItem()['imdbId'] as String?;

    try {
      // Check current watched state
      final isCurrentlyFinished =
          await EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: seriesTitle,
            season: season,
            episode: episodeNum,
            imdbId: imdbId,
          );

      if (isCurrentlyFinished) {
        // Episode is marked as watched, unmark it
        print('🔄 Unmarking as watched: $seriesTitle S${season}E$episodeNum');
        await EpisodeCompletionStorage.unmarkEpisodeAsFinished(
          seriesTitle: seriesTitle,
          season: season,
          episode: episodeNum,
          imdbId: imdbId,
        );
      } else {
        // Episode is not watched, mark it as finished
        print('✅ Marking as watched: $seriesTitle S${season}E$episodeNum');
        await EpisodeCompletionStorage.markEpisodeAsFinished(
          seriesTitle: seriesTitle,
          season: season,
          episode: episodeNum,
          imdbId: imdbId,
        );
      }

      // Reload the progress to update the UI
      await _deps.reloadProgress();

      // Show a snackbar to confirm the action
      // Note: isCurrentlyFinished is the OLD state before toggle, so we invert the message
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(
              isCurrentlyFinished
                  ? 'Episode marked as unwatched'
                  : 'Episode marked as watched',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: isCurrentlyFinished
                ? const Color(0xFF6366F1)
                : const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      print('❌ Error toggling watched state: $e');
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text('Error updating watched state: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
