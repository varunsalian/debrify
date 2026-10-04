import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentDormantDeps = ({
  Map<String, dynamic> Function() playlistItem,
  void Function(VoidCallback) setState,
  PlaylistContentSeriesState seriesState,
});

class PlaylistContentDormant {
  PlaylistContentDormant(this._deps);
  final PlaylistContentDormantDeps _deps;

  /// Load progress data for all files
  Future<void> _loadProgressData() async {
    try {
      Map<String, Map<String, dynamic>> episodeProgress = {};

      // 1. Try IMDB ID lookup first (most reliable — avoids title mismatches)
      final imdbId = _deps.playlistItem()['imdbId'] as String?;
      if (imdbId != null && imdbId.isNotEmpty) {
        episodeProgress =
            await MergedEpisodeProgressStorage.getEpisodeProgressByImdbId(
              imdbId,
            );
      }

      // 2. Fallback: try seriesTitle field
      if (episodeProgress.isEmpty) {
        final seriesTitle = _deps.playlistItem()['seriesTitle'] as String?;
        if (seriesTitle != null && seriesTitle.isNotEmpty) {
          episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
            seriesTitle: seriesTitle,
          );
        }
      }

      // 3. Fallback: try raw title
      if (episodeProgress.isEmpty) {
        final title = _deps.playlistItem()['title'] as String?;
        if (title != null) {
          episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
            seriesTitle: title,
          );
        }
      }

      _deps.setState(() {
        _deps.seriesState.fileProgressCache = episodeProgress;
      });
    } catch (e) {
      print('❌ Error loading progress data: $e');
      _deps.seriesState.fileProgressCache = {};
    }
  }
}
