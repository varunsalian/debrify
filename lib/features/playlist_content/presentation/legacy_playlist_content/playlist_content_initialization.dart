import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentInitializationDeps = ({
  Future<void> Function() loadSavedViewMode,
  Future<void> Function() loadContent,
  PlaylistContentCatalogState catalogState,
  Future<void> Function() parseSeriesPlaylist,
  Map<String, dynamic> Function() playlistItem,
  PlaylistContentSeriesState seriesState,
  void Function(VoidCallback) setState,
  PlaylistContentNavigationState navigationState,
  void Function(FolderViewMode mode) applyViewMode,
  bool Function() mounted,
  PlaylistContentEpisodeState episodeState,
});

class PlaylistContentInitialization {
  PlaylistContentInitialization(this._deps);
  final PlaylistContentInitializationDeps _deps;

  /// Initialize screen by loading saved mode first, then content
  Future<void> initializeScreen() async {
    // Load saved view mode first
    await _deps.loadSavedViewMode();

    // Then load content
    await _deps.loadContent();

    // Parse series playlist BEFORE applying view mode
    // This ensures _seriesPlaylist is available when _applyViewMode() checks it
    if (_deps.catalogState.rootContent != null) {
      await _deps.parseSeriesPlaylist();

      // Auto-set Series View for detected series (only if no saved preference exists)
      final savedViewMode =
          await PlaylistPreferencesStorage.getPlaylistItemViewMode(
            _deps.playlistItem(),
          );
      if (_deps.seriesState.seriesPlaylist?.isSeries == true &&
          savedViewMode == null) {
        _deps.setState(() {
          _deps.navigationState.currentViewMode = FolderViewMode.seriesArrange;
        });
      }

      // THEN apply view mode (can now use _seriesPlaylist.isSeries)
      _deps.applyViewMode(_deps.navigationState.currentViewMode);
    }

    // Note: Progress is now loaded within _parseSeriesPlaylist()
    // so we don't need to call _loadProgressData() here anymore
  }

  /// Check if running on Android TV
  Future<void> checkIfAndroidTv() async {
    try {
      final isTv = await AndroidNativeDownloader.isTelevision();
      if (_deps.mounted()) {
        _deps.setState(() {
          _deps.episodeState.isAndroidTv = isTv;
        });
      }
    } catch (e) {
      // Ignore errors, default to false
    }
  }
}
