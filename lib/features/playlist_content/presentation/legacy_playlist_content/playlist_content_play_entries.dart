import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentPlayEntriesDeps = ({
  PlaylistContentCatalogState catalogState,
  BuildContext Function() context,
  void Function(List<RDFileNode> videoFiles) applySortedPlaylistOrder,
  Map<String, dynamic> Function() playlistItem,
  Future<void> Function(List<RDFileNode> videoFiles, int startIndex)
  playRealDebridPlaylist,
  Future<void> Function(List<RDFileNode> videoFiles, int startIndex)
  playTorboxPlaylist,
  Future<void> Function(List<RDFileNode> videoFiles, int startIndex)
  playPikPakPlaylist,
  Future<void> Function(List<RDFileNode> videoFiles, int startIndex)
  playWebDavPlaylist,
  Future<void> Function(List<RDFileNode> videoFiles, int startIndex)
  playPremiumizePlaylist,
  Future<void> Function(List<RDFileNode> videoFiles, int startIndex)
  playAllDebridPlaylist,
  bool Function() mounted,
  Future<void> Function() reloadProgress,
  PlaylistContentNavigationState navigationState,
});

class PlaylistContentPlayEntries {
  PlaylistContentPlayEntries(this._deps);
  final PlaylistContentPlayEntriesDeps _deps;

  /// Play a file with full playlist support
  Future<void> playFile(RDFileNode file) async {
    if (file.isFolder || _deps.catalogState.rootContent == null) return;

    try {
      // Show loading dialog
      final app = AppThemeScope.of(_deps.context());
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          // A MODAL ground, which is why it is cloud.dialogSurface and not
          // playlist.card — legacy spells both #1E293B.
          backgroundColor: app.cloud.dialogSurface,
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…'),
            ],
          ),
        ),
      );

      // Get all video files from the entire tree
      final allFiles = _deps.catalogState.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        if (Navigator.of(_deps.context()).canPop()) {
          Navigator.of(_deps.context()).pop();
        }
        return;
      }

      // Apply Sort A-Z sorting if in sortedAZ mode
      // Use EXACT same sorting logic as UI view mode (_applySortedView)
      _deps.applySortedPlaylistOrder(videoFiles);

      // Find the selected file index
      int startIndex = 0;
      for (int i = 0; i < videoFiles.length; i++) {
        if (videoFiles[i].name == file.name &&
            videoFiles[i].path == file.path) {
          startIndex = i;
          break;
        }
      }

      final provider =
          ((_deps.playlistItem()['provider'] as String?) ?? 'realdebrid')
              .toLowerCase();

      if (provider == 'realdebrid') {
        await _deps.playRealDebridPlaylist(videoFiles, startIndex);
      } else if (provider == 'torbox') {
        await _deps.playTorboxPlaylist(videoFiles, startIndex);
      } else if (provider == 'pikpak') {
        await _deps.playPikPakPlaylist(videoFiles, startIndex);
      } else if (provider == 'webdav') {
        await _deps.playWebDavPlaylist(videoFiles, startIndex);
      } else if (provider == 'premiumize') {
        await _deps.playPremiumizePlaylist(videoFiles, startIndex);
      } else if (provider == 'alldebrid') {
        await _deps.playAllDebridPlaylist(videoFiles, startIndex);
      }

      if (_deps.mounted() && Navigator.of(_deps.context()).canPop()) {
        Navigator.of(_deps.context()).pop();
      }

      // Reload progress after returning from video player
      if (_deps.mounted()) {
        await _deps.reloadProgress();
      }
    } catch (e) {
      print('❌ Error playing file: $e');
      if (_deps.mounted() && Navigator.of(_deps.context()).canPop()) {
        Navigator.of(_deps.context()).pop();
      }

      // Reload progress even if an error occurred
      // (user might have watched part of video before error)
      if (_deps.mounted()) {
        await _deps.reloadProgress();
      }

      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to play file: $e')));
      }
    }
  }

  /// Play episode from OTT view with full playlist support
  Future<void> playEpisode(SeriesEpisode episode) async {
    if (_deps.catalogState.rootContent == null || !_deps.mounted()) return;

    try {
      // Show loading dialog
      final app = AppThemeScope.of(_deps.context());
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          // A MODAL ground, which is why it is cloud.dialogSurface and not
          // playlist.card — legacy spells both #1E293B.
          backgroundColor: app.cloud.dialogSurface,
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…'),
            ],
          ),
        ),
      );

      // Get all video files from the entire tree
      final allFiles = _deps.catalogState.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        if (Navigator.of(_deps.context()).canPop()) {
          Navigator.of(_deps.context()).pop();
        }
        return;
      }

      // Apply Sort A-Z sorting if in sortedAZ mode
      // Use EXACT same sorting logic as UI view mode (_applySortedView)
      _deps.applySortedPlaylistOrder(videoFiles);

      // Find the selected episode index
      // The approach differs based on view mode:
      // - sortedAZ: Sorting changes indices, so we MUST find by filename
      // - raw/series/collection: originalIndex is still accurate (faster and more reliable)
      int startIndex = 0;
      if (_deps.navigationState.currentViewMode == FolderViewMode.sortedAZ) {
        // After sorting, indices change - must find by filename
        for (int i = 0; i < videoFiles.length; i++) {
          if (videoFiles[i].name == episode.filename) {
            startIndex = i;
            break;
          }
        }
      } else {
        // Raw/Series/Collection modes: originalIndex is still correct
        if (episode.originalIndex >= 0 &&
            episode.originalIndex < videoFiles.length) {
          startIndex = episode.originalIndex;
        } else {
          // Fallback: try to match by filename
          for (int i = 0; i < videoFiles.length; i++) {
            if (videoFiles[i].name == episode.filename) {
              startIndex = i;
              break;
            }
          }
        }
      }

      final provider =
          ((_deps.playlistItem()['provider'] as String?) ?? 'realdebrid')
              .toLowerCase();

      if (provider == 'realdebrid') {
        await _deps.playRealDebridPlaylist(videoFiles, startIndex);
      } else if (provider == 'torbox') {
        await _deps.playTorboxPlaylist(videoFiles, startIndex);
      } else if (provider == 'pikpak') {
        await _deps.playPikPakPlaylist(videoFiles, startIndex);
      } else if (provider == 'webdav') {
        await _deps.playWebDavPlaylist(videoFiles, startIndex);
      } else if (provider == 'premiumize') {
        await _deps.playPremiumizePlaylist(videoFiles, startIndex);
      } else if (provider == 'alldebrid') {
        await _deps.playAllDebridPlaylist(videoFiles, startIndex);
      }

      if (_deps.mounted() && Navigator.of(_deps.context()).canPop()) {
        Navigator.of(_deps.context()).pop();
      }

      // Reload progress after returning from video player
      if (_deps.mounted()) {
        await _deps.reloadProgress();
      }
    } catch (e) {
      print('❌ Error playing episode: $e');
      if (_deps.mounted() && Navigator.of(_deps.context()).canPop()) {
        Navigator.of(_deps.context()).pop();
      }

      // Reload progress even if an error occurred
      // (user might have watched part of video before error)
      if (_deps.mounted()) {
        await _deps.reloadProgress();
      }

      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }
}
