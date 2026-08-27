import 'package:flutter/material.dart';
import '../../../models/series_playlist.dart';
import '../../../models/movie_collection.dart';
import '../../../models/playlist_view_mode.dart';
import '../../../widgets/series_browser.dart';
import '../../../widgets/movie_collection_browser.dart';
import '../models/playlist_entry.dart';
import '../constants/color_constants.dart';
import '../../../services/storage_service.dart';
import '../../../services/tracking_source_policy.dart';
import '../../../utils/episode_progress_merge.dart';
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
  /// - [imdbId]: Show IMDb id, used to look up per-episode tracker progress
  /// - [imdbKnownAtLaunch]: Whether that identity existed before TVMaze ran
  /// - [metadataReady]: Player-side TVMaze enrichment completion signal
  /// - [onSelect]: Callback when episode/movie is selected (index, allowResume)
  /// - [viewMode]: Optional view mode to determine collection organization
  /// - [onFetchEpisode]: When set, the series guide lists EVERY episode of
  ///   the show; tapping one that isn't in the playlist fetches it in-player
  ///   instead of failing with a snackbar.
  static Future<void> show(
    BuildContext context, {
    required List<PlaylistEntry> playlist,
    required int currentIndex,
    SeriesPlaylist? seriesPlaylist,
    Map<String, dynamic>? playlistItemData,
    String? imdbId,
    required bool imdbKnownAtLaunch,
    Future<void>? metadataReady,
    required Future<void> Function(int index, {bool allowResume}) onSelect,
    PlaylistViewMode? viewMode,
    Future<void> Function(int season, int episode)? onFetchEpisode,
  }) async {
    if (playlist.isEmpty) return;

    // Spotlight material, bottom-sheet geometry: an episodes grid genuinely
    // wants the full width, so unlike the small pickers this keeps its shape
    // and only adopts the black glass + hairline.
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101012),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.75,
        ),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(color: Color(0xFF101012)),
            child: seriesPlaylist != null && seriesPlaylist.isSeries
                ? SeriesBrowser(
                    seriesPlaylist: seriesPlaylist,
                    currentEpisodeIndex: currentIndex,
                    playlistItem: playlistItemData,
                    imdbId: imdbId,
                    imdbKnownAtLaunch: imdbKnownAtLaunch,
                    metadataReady: metadataReady,
                    showAllEpisodes: onFetchEpisode != null,
                    onEpisodeSelected: (season, episode) async {
                      // Find the original index in the PlaylistEntry array
                      final originalIndex = seriesPlaylist
                          .findOriginalIndexBySeasonEpisode(season, episode);
                      if (originalIndex != -1) {
                        // Check if this episode has saved progress — local or
                        // any connected tracker — so a partially watched
                        // episode from another device resumes when selected.
                        final title =
                            seriesPlaylist.seriesTitle ?? 'Unknown Series';
                        final resolvedImdbId =
                            (seriesPlaylist.imdbId?.trim().isNotEmpty == true
                            ? seriesPlaylist.imdbId!.trim()
                            : imdbId?.trim());
                        final localProgress =
                            await StorageService.getMergedEpisodeProgress(
                              seriesTitle: title,
                              imdbId: resolvedImdbId,
                            );
                        final trackerMaps =
                            resolvedImdbId != null && resolvedImdbId.isNotEmpty
                            ? await Future.wait([
                                StorageService.getEpisodeTraktProgress(
                                  imdbId: resolvedImdbId,
                                ),
                                StorageService.getEpisodeSimklProgress(
                                  imdbId: resolvedImdbId,
                                ),
                                StorageService.getEpisodeMdblistProgress(
                                  imdbId: resolvedImdbId,
                                ),
                              ])
                            : const <Map<String, double>>[];
                        final episodeKey = '${season}_$episode';
                        final trackingPolicy =
                            await TrackingSourcePolicy.load();
                        final localState = localProgress[episodeKey];
                        final localPosition =
                            (localState?['positionMs'] as num?)?.toInt() ?? 0;
                        final localDuration =
                            (localState?['durationMs'] as num?)?.toInt() ?? 0;
                        final hasLocalResume =
                            trackingPolicy.progressFrom(TrackingSource.local) &&
                            localPosition > 0 &&
                            localDuration > 0 &&
                            localPosition < localDuration;
                        final trackerPercent = furthestEpisodeTrackerPercent([
                          if (trackerMaps.isNotEmpty &&
                              trackingPolicy.progressFrom(TrackingSource.trakt))
                            trackerMaps[0][episodeKey],
                          if (trackerMaps.length > 1 &&
                              trackingPolicy.progressFrom(TrackingSource.simkl))
                            trackerMaps[1][episodeKey],
                          if (trackerMaps.length > 2 &&
                              trackingPolicy.progressFrom(
                                TrackingSource.mdblist,
                              ))
                            trackerMaps[2][episodeKey],
                        ]);
                        final hasTrackerResume =
                            trackerPercent != null &&
                            trackerPercent > 0 &&
                            trackerPercent < 95;

                        // Allow resuming if the episode has saved progress
                        await onSelect(
                          originalIndex,
                          allowResume: hasLocalResume || hasTrackerResume,
                        );
                      } else if (onFetchEpisode != null) {
                        // Not in the playlist: fetch it in-player (the guide
                        // only offers absent episodes when the host can).
                        await onFetchEpisode(season, episode);
                      } else {
                        // Show error message to user
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to find episode S${season}E$episode',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: VideoPlayerColors.errorRed,
                              duration: VideoPlayerTimingConstants
                                  .controlsAutoHideDuration,
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
                          : (viewMode == PlaylistViewMode.sorted
                                ? "sorted A-Z"
                                : "main/extras");
                      debugPrint(
                        '🔍 PlaylistSheet: Creating $collectionType collection from ${playlist.length} entries',
                      );
                      for (int i = 0; i < playlist.length && i < 5; i++) {
                        debugPrint(
                          '  Entry[$i]: title="${playlist[i].title}", relativePath="${playlist[i].relativePath}"',
                        );
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
