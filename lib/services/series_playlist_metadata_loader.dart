import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/series_playlist.dart';
import '../utils/series_parser.dart';
import '../utils/movie_parser.dart';
import 'episode_info_service.dart';
import 'tvmaze_service.dart';
import 'movie_metadata_service.dart';

abstract final class SeriesPlaylistMetadataLoader {
  /// Fetch episode information for all episodes in the playlist
  /// Pass [playlistItem] to enable saved TVMaze mapping lookup
  /// Pass [imdbId] to use direct IMDB lookup (faster and more accurate when available)
  static Future<void> fetchEpisodeInfo(
    SeriesPlaylist playlist, {
    Map<String, dynamic>? playlistItem,
    String? imdbId,
  }) async {
    if (!playlist.isSeries) {
      debugPrint('SeriesPlaylist: Not a series, skipping TVMaze fetch');
      return;
    }

    // Store imdbId immediately so SeriesBrowser can use it even if IMDB lookup is slow
    if (imdbId != null && imdbId.startsWith('tt')) {
      playlist.imdbId = imdbId;
    }

    // Try to extract series title from filenames if not already set
    String? searchTitle = playlist.seriesTitle;
    if (searchTitle == null && playlist.allEpisodes.isNotEmpty) {
      searchTitle = playlist.allEpisodes.first.seriesInfo.title;
    }

    // Validate the series title before searching (unless we have IMDB ID)
    if (imdbId == null && !SeriesParser.isValidSeriesTitle(searchTitle)) {
      debugPrint('TVMaze: Cannot search - invalid title "$searchTitle"');
      return;
    }

    final validSearchTitle = searchTitle ?? '';
    if (imdbId != null) {
      debugPrint('TVMaze: Using IMDB ID "$imdbId" for direct lookup');
    } else {
      debugPrint('TVMaze: Searching for "$validSearchTitle"');
    }

    // Check for saved TVMaze mapping first
    int? overrideShowId;
    if (playlistItem != null) {
      try {
        final mapping = await _getTVMazeMapping(playlistItem);
        if (mapping != null && mapping['tvmazeShowId'] != null) {
          overrideShowId = mapping['tvmazeShowId'] as int;
          debugPrint(
            'TVMaze: Using saved mapping - Show ID $overrideShowId (${mapping['showName']})',
          );
        }
      } catch (e) {
        debugPrint('TVMaze: Error loading saved mapping: $e');
      }
    }

    // First, get the show information to extract genres, language, network, etc.
    Map<String, dynamic>? showInfo;
    try {
      if (overrideShowId != null) {
        // Use the saved show ID directly
        showInfo = await _getShowById(overrideShowId);
        if (showInfo != null) {
          debugPrint('TVMaze: Loaded show info using saved mapping');
          // Extract IMDB ID from externals for subtitle fetching
          _extractImdbFromExternals(playlist, showInfo);
        }
      } else if (imdbId != null && imdbId.startsWith('tt')) {
        // Use IMDB ID for direct lookup (most accurate)
        showInfo = await _lookupByImdbId(imdbId);
        if (showInfo != null) {
          debugPrint('TVMaze: Loaded show info using IMDB ID "$imdbId"');
          // Extract show ID for subsequent episode lookups (avoids title-based searches)
          if (showInfo['id'] != null) {
            overrideShowId = showInfo['id'] as int;
            debugPrint(
              'TVMaze: Extracted show ID $overrideShowId from IMDB lookup',
            );
          }
          // Extract IMDB ID from externals (in case it differs or wasn't passed)
          _extractImdbFromExternals(playlist, showInfo);
        } else {
          // Fallback to title search if IMDB lookup fails
          debugPrint(
            'TVMaze: IMDB lookup failed, falling back to title search',
          );
          if (validSearchTitle.isNotEmpty) {
            showInfo = await EpisodeInfoService.getSeriesInfo(validSearchTitle);
            // Extract show ID for subsequent episode lookups
            if (showInfo != null && showInfo['id'] != null) {
              overrideShowId = showInfo['id'] as int;
              debugPrint(
                'TVMaze: Extracted show ID $overrideShowId from title fallback',
              );
            }
            // Extract IMDB ID from externals for subtitle fetching
            _extractImdbFromExternals(playlist, showInfo);
          }
        }
      } else if (validSearchTitle.isNotEmpty) {
        // Fall back to searching by series title
        showInfo = await EpisodeInfoService.getSeriesInfo(validSearchTitle);
        // Extract show ID for subsequent episode lookups
        if (showInfo != null && showInfo['id'] != null) {
          overrideShowId = showInfo['id'] as int;
          debugPrint(
            'TVMaze: Extracted show ID $overrideShowId from title search',
          );
        }
        // Extract IMDB ID from externals for subtitle fetching
        _extractImdbFromExternals(playlist, showInfo);
      }
      // Found series info (no log needed, success assumed)
    } catch (e) {
      debugPrint('TVMaze: Series lookup failed: $e');
    }

    // Extract show poster URL for playlist item updates
    if (showInfo != null && showInfo['image'] != null) {
      playlist.showPosterUrl =
          showInfo['image']['original'] as String? ??
          showInfo['image']['medium'] as String?;
    }

    // Fetch all episodes upfront when we have a show ID (much more efficient than per-episode API calls)
    List<Map<String, dynamic>> allTVMazeEpisodes = [];
    if (showInfo != null && overrideShowId != null) {
      // Store show ID for SeriesBrowser reuse (avoids redundant title searches)
      playlist.tvmazeShowId = overrideShowId;
      final officialName = showInfo['name'];
      if (officialName is String && officialName.trim().isNotEmpty) {
        playlist.tvmazeShowName = officialName.trim();
      }
      try {
        allTVMazeEpisodes = await _getEpisodesByShowId(overrideShowId);
        // Retain the show's FULL episode list: the player's episode guide
        // renders every episode of the show (not just the pack's files) and
        // uses this to offer absent episodes for fetching.
        playlist.fullTvmazeEpisodes = allTVMazeEpisodes;
        debugPrint(
          'TVMaze: Fetched ${allTVMazeEpisodes.length} episodes upfront for show ID $overrideShowId',
        );
      } catch (e) {
        debugPrint('TVMaze: Episode list failed: $e');
      }
    }

    // Process each episode
    // Process each episode
    for (final season in playlist.seasons) {
      for (final episode in season.episodes) {
        // Skip Season 0 (special content)
        if (episode.seriesInfo.season == 0) {
          continue;
        }

        if (episode.seriesInfo.season != null &&
            episode.seriesInfo.episode != null) {
          // Standard episode with S##E## format
          try {
            Map<String, dynamic>? episodeData;

            if (allTVMazeEpisodes.isNotEmpty) {
              // Use pre-fetched episodes list (efficient - no API call per episode)
              for (final ep in allTVMazeEpisodes) {
                if (ep['season'] == episode.seriesInfo.season &&
                    ep['number'] == episode.seriesInfo.episode) {
                  episodeData = ep;
                  break;
                }
              }
            } else {
              // Fall back to searching by series title (only when we don't have show ID)
              episodeData = await EpisodeInfoService.getEpisodeInfo(
                validSearchTitle,
                episode.seriesInfo.season!,
                episode.seriesInfo.episode!,
              );
            }

            if (episodeData != null) {
              episode.episodeInfo = EpisodeInfo.fromTVMaze(
                episodeData,
                showInfo: showInfo,
              );
            }
          } catch (e) {
            // Silently fail - episode info is optional
          }
        } else if (allTVMazeEpisodes.isNotEmpty) {
          // Title-only episode - try to match by filename
          final filename = episode.filename.toLowerCase();
          Map<String, dynamic>? bestMatch;
          double bestScore = 0.0;

          for (final tvEpisode in allTVMazeEpisodes) {
            final tvTitle = (tvEpisode['name'] ?? '').toString().toLowerCase();
            final score = _calculateTitleSimilarity(filename, tvTitle);

            if (score > bestScore && score > 0.6) {
              // 60% similarity threshold
              bestScore = score;
              bestMatch = tvEpisode;
            }
          }

          if (bestMatch != null) {
            episode.episodeInfo = EpisodeInfo.fromTVMaze(
              bestMatch,
              showInfo: showInfo,
            );
            // Update the SeriesInfo with matched S##E##
            final matchedSeason = bestMatch['season'] as int?;
            final matchedEpisode = bestMatch['number'] as int?;
            if (matchedSeason != null && matchedEpisode != null) {
              episode.seriesInfo = episode.seriesInfo.copyWith(
                season: matchedSeason,
                episode: matchedEpisode,
              );
              debugPrint(
                'TVMaze: Title match "${episode.filename}" → S${matchedSeason.toString().padLeft(2, '0')}E${matchedEpisode.toString().padLeft(2, '0')} (${(bestScore * 100).toStringAsFixed(0)}%)',
              );
            }
          }
          // No match - skip logging for cleaner output
        }
      }
    }

    // If TVMaze fetch failed completely, log fallback
    if (showInfo == null && playlist.isSeries) {
      debugPrint(
        'SeriesPlaylist: TVMaze unavailable, treating as MOVIE_COLLECTION fallback',
      );
    }
  }

  /// Get episode information for a specific episode
  static Future<EpisodeInfo?> getEpisodeInfoForEpisode(
    String seriesTitle,
    int season,
    int episode,
  ) async {
    try {
      // Get show information first
      final showInfo = await EpisodeInfoService.getSeriesInfo(seriesTitle);

      final episodeData = await EpisodeInfoService.getEpisodeInfo(
        seriesTitle,
        season,
        episode,
      );
      if (episodeData != null) {
        return EpisodeInfo.fromTVMaze(episodeData, showInfo: showInfo);
      }
    } catch (e) {
      // Optional episode metadata lookup or parsing failed; return null below.
    }
    return null;
  }

  /// Calculate similarity between two titles (0.0 to 1.0)
  static double _calculateTitleSimilarity(String s1, String s2) {
    // Simple Levenshtein-based similarity
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    // Normalize strings
    final str1 = s1.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final str2 = s2.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();

    // Check if one string contains the other
    if (str1.contains(str2) || str2.contains(str1)) {
      return 0.8; // High similarity if one contains the other
    }

    // Simple word-based similarity
    final words1 = str1.split(RegExp(r'\s+'));
    final words2 = str2.split(RegExp(r'\s+'));

    int matchingWords = 0;
    for (final word1 in words1) {
      if (word1.length < 3) continue; // Skip short words
      for (final word2 in words2) {
        if (word2.length < 3) continue;
        if (word1 == word2) {
          matchingWords++;
          break;
        }
      }
    }

    final totalWords = math.max(words1.length, words2.length);
    if (totalWords == 0) return 0.0;

    return matchingWords / totalWords;
  }

  /// Helper method to get TVMaze mapping from storage
  /// Note: This needs to import StorageService
  static Future<Map<String, dynamic>?> _getTVMazeMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    // Import at top of file: import '../services/storage_service.dart';
    try {
      // Dynamically import to avoid circular dependency
      return await EpisodeInfoService.getTVMazeMapping(playlistItem);
    } catch (e) {
      debugPrint('Error getting TVMaze mapping: $e');
      return null;
    }
  }

  /// Helper method to get show info by ID from TVMaze
  static Future<Map<String, dynamic>?> _getShowById(int showId) async {
    try {
      return await EpisodeInfoService.getShowById(showId);
    } catch (e) {
      debugPrint('Error getting show by ID: $e');
      return null;
    }
  }

  /// Fetch movie metadata from Cinemeta to get IMDB ID for the first item
  ///
  /// This is a convenience method that calls [fetchMovieMetadataForIndex] with index 0.
  /// For movie collections, prefer using [fetchMovieMetadataForIndex] with the current index.
  static Future<void> fetchMovieMetadata(SeriesPlaylist playlist) async {
    await fetchMovieMetadataForIndex(playlist, 0);
  }

  /// Fetch movie metadata from Cinemeta to get IMDB ID for a specific item
  ///
  /// This is called for non-series content (isSeries == false) when:
  /// - The filename has a year pattern (e.g., "Inception.2010.1080p.mkv")
  /// - We don't already have an IMDB ID for this item
  ///
  /// The discovered IMDB ID is stored per-item in the playlist's private cache for subtitle fetching.
  /// Use [SeriesPlaylist.getImdbIdForIndex] to retrieve the IMDB ID for a specific item.
  static Future<String?> fetchMovieMetadataForIndex(
    SeriesPlaylist playlist, int index,
  ) async {
    // Skip if this is a series
    if (playlist.isSeries) {
      debugPrint('MovieMetadata: Skipping - content is a series');
      return playlist.imdbId;
    }

    // Check if we already have IMDB ID for this index
    final cachedId = playlist.cachedMovieImdbId(index);
    if (cachedId != null) {
      debugPrint(
        'MovieMetadata: Using cached IMDB ID for index $index: $cachedId',
      );
      return cachedId;
    }

    // Validate index
    if (index < 0 || index >= playlist.allEpisodes.length) {
      debugPrint(
        'MovieMetadata: Invalid index $index (total: ${playlist.allEpisodes.length})',
      );
      return null;
    }

    final episode = playlist.allEpisodes[index];
    final filename = episode.title;
    debugPrint('MovieMetadata: Checking filename at index $index: "$filename"');

    // Parse the filename for movie info
    final movieInfo = MovieParser.parseFilename(filename);

    // Only proceed if filename has year pattern
    if (!movieInfo.hasYear) {
      debugPrint(
        'MovieMetadata: No year pattern found at index $index, skipping lookup',
      );
      return null;
    }

    if (movieInfo.title == null || movieInfo.title!.isEmpty) {
      debugPrint(
        'MovieMetadata: Could not extract title from filename at index $index',
      );
      return null;
    }

    debugPrint(
      'MovieMetadata: Parsed title="${movieInfo.title}", year=${movieInfo.year} (index $index)',
    );

    // Look up movie in Cinemeta
    try {
      final metadata = await MovieMetadataService.lookupMovie(
        movieInfo.title!,
        movieInfo.year,
      );

      if (metadata != null) {
        // Store per-item IMDB ID
        playlist.recordMovieMetadataSuccess(index, metadata.imdbId);
        debugPrint(
          'MovieMetadata: Found IMDB ID "${metadata.imdbId}" for "${metadata.title}" (index $index)',
        );
        return metadata.imdbId;
      } else {
        debugPrint(
          'MovieMetadata: No match found in Cinemeta for index $index',
        );
        return null;
      }
    } catch (e) {
      debugPrint('MovieMetadata: Error during lookup for index $index: $e');
      return null;
    }
  }

  /// Extract IMDB ID from TVMaze externals object and store it
  /// This enables Stremio subtitle fetching for content discovered via title search
  static void _extractImdbFromExternals(
    SeriesPlaylist playlist, Map<String, dynamic>? showInfo,
  ) {
    if (showInfo == null) return;

    // TVMaze returns externals object with imdb, thetvdb, tvrage IDs
    // Use safe casting to avoid crashes on malformed API responses
    final externals = showInfo['externals'];
    if (externals is Map<String, dynamic>) {
      final externalImdbId = externals['imdb'];
      if (externalImdbId is String && externalImdbId.startsWith('tt')) {
        // Only update if we don't already have an IMDB ID
        if (playlist.imdbId == null || playlist.imdbId!.isEmpty) {
          playlist.imdbId = externalImdbId;
          debugPrint(
            'TVMaze: Extracted IMDB ID "$externalImdbId" from externals',
          );
        }
      }
    }
  }

  /// Helper method to look up show by IMDB ID from TVMaze
  static Future<Map<String, dynamic>?> _lookupByImdbId(String imdbId) async {
    try {
      return await TVMazeService.lookupByImdbId(imdbId);
    } catch (e) {
      debugPrint('Error looking up show by IMDB ID: $e');
      return null;
    }
  }

  /// Helper method to get episodes by show ID from TVMaze
  static Future<List<Map<String, dynamic>>> _getEpisodesByShowId(
    int showId,
  ) async {
    try {
      return await EpisodeInfoService.getEpisodesByShowId(showId);
    } catch (e) {
      debugPrint('Error getting episodes by show ID: $e');
      return [];
    }
  }
}
