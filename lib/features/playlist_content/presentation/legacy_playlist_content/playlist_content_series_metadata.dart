import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/playlist_metadata_storage.dart';
import 'package:debrify/services/storage/tvmaze_mapping_storage.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/widgets/tvmaze_search_dialog.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentSeriesMetadataDeps = ({
  PlaylistContentSeriesState seriesState,
  Map<String, dynamic> Function() playlistItem,
  PlaylistContentCatalogState catalogState,
  int Function() determineInitialSeason,
  void Function(VoidCallback) setState,
  Future<void> Function() saveDetectedSeriesPosterToPlaylist,
  bool Function() mounted,
  BuildContext Function() context,
  Future<void> Function(Map<String, dynamic> showInfo) updatePlaylistPoster,
});

class PlaylistContentSeriesMetadata {
  PlaylistContentSeriesMetadata(this._deps);
  final PlaylistContentSeriesMetadataDeps _deps;

  /// Parse series playlist from current view nodes
  Future<void> saveImdbIdToPlaylist({bool force = false}) async {
    final imdbId = _deps.seriesState.seriesPlaylist?.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (!force && (_deps.playlistItem()?['imdbId'] as String?) != null) return;

    final rdTorrentId = _deps.playlistItem()?['rdTorrentId'] as String?;
    final torboxTorrentId = _deps
        .playlistItem()?['torboxTorrentId']
        ?.toString();
    final pikpakCollectionId = _deps.playlistItem()?['pikpakFileId'] as String?;
    final isPremiumize =
        (_deps.playlistItem()?['provider'] as String?)?.toLowerCase() ==
        'premiumize';
    final String? premiumizeHash = isPremiumize
        ? (_deps.playlistItem()?['torrent_hash'] as String?)
        : null;
    final String? premiumizeItemId = isPremiumize
        ? (_deps.playlistItem()?['premiumizeItemId']?.toString())
        : null;
    final bool isAllDebrid =
        (_deps.playlistItem()?['provider'] as String?)?.toLowerCase() ==
        'alldebrid';
    final String? allDebridHash = isAllDebrid
        ? (_deps.playlistItem()?['torrent_hash'] as String?)
        : null;

    await PlaylistMetadataStorage.updatePlaylistItemImdbId(
      imdbId,
      rdTorrentId: rdTorrentId,
      torboxTorrentId: torboxTorrentId,
      pikpakCollectionId: pikpakCollectionId,
      premiumizeHash: premiumizeHash,
      premiumizeItemId: premiumizeItemId,
      allDebridHash: allDebridHash,
      force: force,
    );
  }

  Future<void> parseSeriesPlaylist() async {
    if (_deps.catalogState.rootContent == null) return;

    try {
      // Get ALL video files recursively from the entire content tree
      final allFiles = _deps.catalogState.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        return;
      }

      // Create PlaylistEntry objects from video files
      final entries = videoFiles
          .map(
            (f) => PlaylistEntry(
              url: '', // Not needed for parsing
              title: f.name,
              relativePath:
                  f.relativePath ??
                  f.path, // Use relativePath if available, fallback to path
            ),
          )
          .toList();

      // Get series/collection title from playlist item
      // Try 'seriesTitle' first (if previously extracted), fallback to 'title' (raw torrent name)
      final String? collectionTitle =
          _deps.playlistItem()['seriesTitle'] as String? ??
          _deps.playlistItem()['title'] as String?;

      _deps.seriesState.seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle: collectionTitle,
      );

      // Reload progress with the clean extracted series/collection title!
      // This works for both series and movie collections
      final String? titleForProgress =
          _deps.seriesState.seriesPlaylist!.seriesTitle ??
          _deps.playlistItem()['title'] as String?;

      if (titleForProgress != null && titleForProgress.isNotEmpty) {
        print('🔄 Reloading progress with clean title: $titleForProgress');
        print('📌 isSeries: ${_deps.seriesState.seriesPlaylist!.isSeries}');
        final episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
          seriesTitle: titleForProgress,
        );
        print('📊 Loaded ${episodeProgress.length} episodes with progress');
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');
        _deps.seriesState.fileProgressCache = episodeProgress;

        // Determine initial season based on most recent viewing history
        if (_deps.seriesState.seriesPlaylist!.isSeries &&
            _deps.seriesState.fileProgressCache.isNotEmpty) {
          final initialSeason = _deps.determineInitialSeason();
          print('🎬 Setting initial season to: $initialSeason');
          _deps.seriesState.selectedSeasonNumber = initialSeason;
        }
      }

      // Check if we have a saved TVMaze mapping (indicates cached data)
      // Only show loading indicator if data needs to be fetched
      bool showLoading = true;
      if (_deps.playlistItem() != null) {
        final mapping = await TvMazeMappingStorage.getTVMazeSeriesMapping(
          _deps.playlistItem()!,
        );
        if (mapping != null) {
          showLoading = false; // Data should be cached, skip loading indicator
        }
      }

      if (showLoading) {
        _deps.setState(() {
          _deps.seriesState.isLoadingSeriesMetadata = true;
        });
      }

      // Fetch TVMaze metadata asynchronously
      if (_deps.seriesState.seriesPlaylist!.isSeries) {
        _deps.seriesState.seriesPlaylist!
            .fetchEpisodeInfo(
              playlistItem: _deps.playlistItem(),
              imdbId: _deps.playlistItem()?['imdbId'] as String?,
            )
            .then((_) async {
              await saveImdbIdToPlaylist();
              await _deps.saveDetectedSeriesPosterToPlaylist();
              if (_deps.mounted()) {
                _deps.setState(() {
                  _deps.seriesState.isLoadingSeriesMetadata = false;
                });
              }
            })
            .catchError((e) {
              print('Failed to fetch episode metadata: $e');
              if (_deps.mounted()) {
                _deps.setState(() {
                  _deps.seriesState.isLoadingSeriesMetadata = false;
                });
              }
            });
      }
    } catch (e) {
      print('Failed to parse series playlist: $e');
      _deps.setState(() {
        _deps.seriesState.isLoadingSeriesMetadata = false;
      });
    }
  }

  /// Show the Fix Metadata dialog to manually select a TV show
  Future<void> showFixMetadataDialog() async {
    // Show the search dialog
    final selectedShow = await showDialog<Map<String, dynamic>>(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (context) => TVMazeSearchDialog(
        initialQuery: _deps.seriesState.seriesPlaylist?.seriesTitle ?? '',
      ),
    );

    if (selectedShow != null && _deps.mounted()) {
      // 1. Get OLD mapping (before it's overwritten)
      final oldMapping = await TvMazeMappingStorage.getTVMazeSeriesMapping(
        _deps.playlistItem(),
      );
      final oldShowId = oldMapping?['tvmazeShowId'] as int?;

      // 2. Clear old show ID cache if it exists
      if (oldShowId != null && oldShowId != selectedShow['id']) {
        debugPrint('🧹 Clearing old show ID cache: $oldShowId');
        await TVMazeService.clearShowCache(oldShowId);
        await EpisodeInfoService.clearShowCache(oldShowId);
      }

      // 3. Clear series name cache (existing logic)
      await EpisodeInfoService.clearSeriesCache(
        _deps.seriesState.seriesPlaylist?.seriesTitle ?? '',
      );
      await TVMazeService.clearSeriesCache(
        _deps.seriesState.seriesPlaylist?.seriesTitle ?? '',
      );

      // 4. Save new mapping
      await TvMazeMappingStorage.saveTVMazeSeriesMapping(
        playlistItem: _deps.playlistItem(),
        tvmazeShowId: selectedShow['id'] as int,
        showName: selectedShow['name'] as String,
      );

      // Update playlist item poster/cover image
      await _deps.updatePlaylistPoster(selectedShow);

      // Show success message
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(
              'Metadata fixed! Using "${selectedShow['name']}" from TVMaze',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload episode info with the new show ID
      if (_deps.seriesState.seriesPlaylist != null &&
          _deps.seriesState.seriesPlaylist!.isSeries &&
          _deps.mounted()) {
        // Clear stale tvmazeShowId so fetchEpisodeInfo reads the new mapping.
        // The name goes with it: fetchEpisodeInfo rewrites it on success, but
        // a failed lookup must not leave the OLD show's name captioning the
        // player dock.
        _deps.seriesState.seriesPlaylist!.tvmazeShowId = null;
        _deps.seriesState.seriesPlaylist!.tvmazeShowName = null;
        _deps.seriesState.seriesPlaylist!.showPosterUrl = null;

        _deps.setState(() {
          _deps.seriesState.isLoadingSeriesMetadata = true;
        });

        _deps.seriesState.seriesPlaylist!
            .fetchEpisodeInfo(
              playlistItem: _deps.playlistItem(),
              imdbId: _deps.playlistItem()?['imdbId'] as String?,
            )
            .then((_) async {
              await saveImdbIdToPlaylist(force: true);
              await _deps.saveDetectedSeriesPosterToPlaylist();
              if (_deps.mounted()) {
                _deps.setState(() {
                  _deps.seriesState.isLoadingSeriesMetadata = false;
                });
              }
            })
            .catchError((e) {
              print('Failed to refresh episode metadata: $e');
              if (_deps.mounted()) {
                _deps.setState(() {
                  _deps.seriesState.isLoadingSeriesMetadata = false;
                });
              }
            });
      }
    }
  }
}
