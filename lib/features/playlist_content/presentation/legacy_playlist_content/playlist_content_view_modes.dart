import 'dart:async';
import 'package:debrify/features/playlist_content/application/playlist_content_sort_policy.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentViewModesDeps = ({
  Map<String, dynamic> Function() playlistItem,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PlaylistContentNavigationState navigationState,
  PlaylistContentCatalogState catalogState,
  PlaylistContentSearchState searchState,
  PlaylistContentSeriesState seriesState,
});

class PlaylistContentViewModes {
  PlaylistContentViewModes(this._deps);
  final PlaylistContentViewModesDeps _deps;

  /// Load saved view mode for this playlist item
  Future<void> loadSavedViewMode() async {
    final savedModeString =
        await PlaylistPreferencesStorage.getPlaylistItemViewMode(
          _deps.playlistItem(),
        );
    if (savedModeString != null && _deps.mounted()) {
      _deps.setState(() {
        _deps.navigationState.currentViewMode = viewModeFromString(
          savedModeString,
        );
      });
    }
  }

  /// Convert string to FolderViewMode
  FolderViewMode viewModeFromString(String mode) {
    switch (mode) {
      case 'raw':
        return FolderViewMode.raw;
      case 'sortedAZ':
        return FolderViewMode.sortedAZ;
      case 'seriesArrange':
        return FolderViewMode.seriesArrange;
      default:
        return FolderViewMode.raw;
    }
  }

  /// Convert FolderViewMode to string
  String viewModeToString(FolderViewMode mode) {
    switch (mode) {
      case FolderViewMode.raw:
        return 'raw';
      case FolderViewMode.sortedAZ:
        return 'sortedAZ';
      case FolderViewMode.seriesArrange:
        return 'seriesArrange';
    }
  }

  /// Convert FolderViewMode to PlaylistViewMode for video player
  PlaylistViewMode convertToPlaylistViewMode(FolderViewMode mode) {
    switch (mode) {
      case FolderViewMode.raw:
        return PlaylistViewMode.raw;
      case FolderViewMode.sortedAZ:
        return PlaylistViewMode.sorted;
      case FolderViewMode.seriesArrange:
        return PlaylistViewMode.series;
    }
  }

  /// Apply view mode transformation
  void applyViewMode(FolderViewMode mode) {
    if (_deps.catalogState.rootContent == null) return;

    _deps.setState(() {
      _deps.navigationState.currentViewMode = mode;

      // Close search when switching to Series Arrange mode
      if (mode == FolderViewMode.seriesArrange &&
          _deps.searchState.isSearchActive) {
        _deps.searchState.isSearchActive = false;
        _deps.searchState.searchController.clear();
        _deps.searchState.searchResults.clear();
      }

      // Get current folder's nodes
      RDFileNode currentFolder = _deps.catalogState.rootContent!;
      for (final segment in _deps.navigationState.folderPath) {
        // Find child folder by name
        RDFileNode? child;
        try {
          child = currentFolder.children.firstWhere(
            (c) => c.name == segment && c.isFolder,
          );
        } catch (e) {
          // Folder not found - reset to root
          print(
            'Warning: Folder "$segment" not found in current view, resetting to root',
          );
          _deps.navigationState.folderPath.clear();
          currentFolder = _deps.catalogState.rootContent!;
          break;
        }

        if (child != null) {
          currentFolder = child;
        }
      }

      // Apply transformation based on mode
      switch (mode) {
        case FolderViewMode.raw:
          _deps.navigationState.currentViewNodes = currentFolder.children;
          break;
        case FolderViewMode.sortedAZ:
          _deps.navigationState.currentViewNodes = applySortedView(
            currentFolder.children,
          );
          break;
        case FolderViewMode.seriesArrange:
          _deps.navigationState.currentViewNodes = applySeriesArrangeView(
            currentFolder.children,
          );
          break;
      }
    });

    // Save view mode preference
    PlaylistPreferencesStorage.savePlaylistItemViewMode(
      _deps.playlistItem(),
      viewModeToString(mode),
    );
  }

  /// Apply series arrange view (creates virtual season folders)
  List<RDFileNode> applySeriesArrangeView(List<RDFileNode> nodes) {
    final videoFiles = nodes
        .where((n) => !n.isFolder && FileUtils.isVideoFile(n.name))
        .toList();
    final otherNodes = nodes
        .where((n) => n.isFolder || !FileUtils.isVideoFile(n.name))
        .toList();

    if (videoFiles.length < 3) {
      // Not enough files for series detection, fallback to sorted
      return applySortedView(nodes);
    }

    // Use the already-parsed _seriesPlaylist instead of re-parsing filenames
    // This is more accurate (considers TVMaze mappings) and faster
    if (_deps.seriesState.seriesPlaylist == null ||
        !_deps.seriesState.seriesPlaylist!.isSeries) {
      return applySortedView(nodes);
    }

    // Parse filenames for season/episode extraction
    final filenames = videoFiles.map((f) => f.name).toList();
    final parsed = SeriesParser.parsePlaylist(filenames);

    // Group by season
    final Map<int, List<RDFileNode>> seasonMap = {};
    for (int i = 0; i < videoFiles.length; i++) {
      final info = parsed[i];
      if (info.isSeries && info.season != null) {
        seasonMap.putIfAbsent(info.season!, () => []);
        seasonMap[info.season!]!.add(videoFiles[i]);
      }
    }

    // Create virtual season folders
    final List<RDFileNode> seasonFolders = [];
    for (final seasonNum in seasonMap.keys.toList()..sort()) {
      final seasonFiles = seasonMap[seasonNum]!;
      seasonFolders.add(
        RDFileNode.folder(
          name: seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
          children: seasonFiles,
        ),
      );
    }

    return [...otherNodes, ...seasonFolders];
  }
}
