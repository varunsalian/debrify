import 'package:flutter/material.dart';
import '../../../models/series_playlist.dart';
import '../../../models/movie_collection.dart';
import '../../../models/playlist_view_mode.dart';
import '../../../widgets/series_browser.dart';
import '../../../widgets/movie_collection_browser.dart';
import '../models/playlist_entry.dart';
import '../constants/color_constants.dart';
import '../../../services/storage_service.dart';
import '../constants/timing_constants.dart';

/// Modal bottom sheet for browsing and selecting playlist items
///
/// Shows either SeriesBrowser (for TV series) or MovieCollectionBrowser
/// (for movie collections) depending on the playlist type.
class PlaylistSheet {
  /// Shows the playlist selection bottom sheet
  ///
  /// Parameters:
  /// - [context]: Build context for showing the modal
  /// - [playlist]: List of playlist entries
  /// - [currentIndex]: Currently playing index
  /// - [seriesPlaylist]: Optional series playlist metadata
  /// - [playlistItemData]: Additional playlist item data
  /// - [onSelect]: Callback when episode/movie is selected (index, allowResume)
  /// - [viewMode]: Optional view mode to determine collection organization
  static Future<void> show(
    BuildContext context, {
    required List<PlaylistEntry> playlist,
    required int currentIndex,
    SeriesPlaylist? seriesPlaylist,
    Map<String, dynamic>? playlistItemData,
    required Future<void> Function(int index, {bool allowResume}) onSelect,
    PlaylistViewMode? viewMode,
  }) async {
    if (playlist.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: VideoPlayerColors.darkBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [VideoPlayerColors.darkerBackground, VideoPlayerColors.darkBackground],
              ),
            ),
            child: seriesPlaylist != null && seriesPlaylist.isSeries
                ? SeriesBrowser(
                    seriesPlaylist: seriesPlaylist,
                    currentEpisodeIndex: currentIndex,
                    playlistItem: playlistItemData,
                    onEpisodeSelected: (season, episode) async {
                      // Find the original index in the PlaylistEntry array
                      final originalIndex = seriesPlaylist
                          .findOriginalIndexBySeasonEpisode(season, episode);
                      if (originalIndex != -1) {
                        // Check if this episode has saved progress
                        final playbackState =
                            await StorageService.getSeriesPlaybackState(
                          seriesTitle:
                              seriesPlaylist.seriesTitle ?? 'Unknown Series',
                          season: season,
                          episode: episode,
                        );

                        // Allow resuming if the episode has saved progress
                        await onSelect(originalIndex, allowResume: playbackState != null);
                      } else {
                        // Show error message to user
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to find episode S${season}E${episode}',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: VideoPlayerColors.errorRed,
                              duration: VideoPlayerTimingConstants.controlsAutoHideDuration,
                            ),
                          );
                        }
                      }
                    },
                  )
                : Builder(
                    builder: (context) {
                      // Log playlist entries before creating MovieCollection
                      String collectionType = viewMode == PlaylistViewMode.raw
                          ? "folder"
                          : (viewMode == PlaylistViewMode.sorted ? "sorted A-Z" : "main/extras");
                      debugPrint('🔍 PlaylistSheet: Creating $collectionType collection from ${playlist.length} entries');
                      for (int i = 0; i < playlist.length && i < 5; i++) {
                        debugPrint('  Entry[$i]: title="${playlist[i].title}", relativePath="${playlist[i].relativePath}"');
                      }

                      // Create MovieCollection based on view mode:
                      // - Raw: Preserve folder structure as-is
                      // - Sorted: Files are already sorted A-Z, create single group
                      // - Series/Other: Use Main/Extras grouping (40% threshold)
                      final MovieCollection collection;
                      if (viewMode == PlaylistViewMode.raw) {
                        collection = MovieCollection.fromFolderStructure(
                          playlist: playlist,
                          title: playlistItemData?['title'] as String?,
                        );
                      } else if (viewMode == PlaylistViewMode.sorted) {
                        collection = MovieCollection.fromSortedPlaylist(
                          playlist: playlist,
                          title: playlistItemData?['title'] as String?,
                        );
                      } else {
                        collection = MovieCollection.fromPlaylistWithMainExtras(
                          playlist: playlist,
                          title: playlistItemData?['title'] as String?,
                        );
                      }

                      return MovieCollectionBrowser(
                        collection: collection,
                        currentIndex: currentIndex,
                        onSelectIndex: (idx) async {
                          await onSelect(idx, allowResume: false);
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}
