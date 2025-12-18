import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../utils/series_parser.dart';
import '../screens/video_player_screen.dart';
import '../services/episode_info_service.dart';

/// Represents a group of duplicate episodes
class DuplicateGroup {
  final int season;
  final int episode;
  final List<int> indices;
  final List<int> fileSizes;

  DuplicateGroup({
    required this.season,
    required this.episode,
    required this.indices,
    required this.fileSizes,
  });

  /// Get index of the largest file
  int get largestFileIndex {
    if (fileSizes.isEmpty) return indices.first;

    int maxSize = 0;
    int maxIndex = 0;
    for (int i = 0; i < fileSizes.length; i++) {
      if (fileSizes[i] > maxSize) {
        maxSize = fileSizes[i];
        maxIndex = i;
      }
    }
    return indices[maxIndex];
  }
}

class EpisodeInfo {
  final String? title;
  final String? plot;
  final String? poster;
  final double? rating;
  final String? year;
  final String? episodeNumber;
  final String? seasonNumber;
  final int? runtime;
  final String? airDate;
  final String? language;
  final List<String> genres;
  final String? network;
  final String? country;

  const EpisodeInfo({
    this.title,
    this.plot,
    this.poster,
    this.rating,
    this.year,
    this.episodeNumber,
    this.seasonNumber,
    this.runtime,
    this.airDate,
    this.language,
    this.genres = const [],
    this.network,
    this.country,
  });

  factory EpisodeInfo.fromTVMaze(Map<String, dynamic> json, {Map<String, dynamic>? showInfo}) {
    // Extract genres from the show info if available
    List<String> genres = [];
    if (showInfo != null && showInfo['genres'] != null) {
      genres = List<String>.from(showInfo['genres']);
    }
    
    // Extract language and country from show info
    String? language;
    String? country;
    String? network;
    
    if (showInfo != null) {
      language = showInfo['language'];
      country = showInfo['network']?['country']?['name'];
      network = showInfo['network']?['name'];
    }
    
    return EpisodeInfo(
      title: json['name'],
      plot: json['summary']?.toString().replaceAll(RegExp(r'<[^>]*>'), ''), // Remove HTML tags
      poster: json['image']?['medium'],
      rating: json['rating']?['average']?.toDouble(),
      year: json['airdate']?.toString().substring(0, 4),
      episodeNumber: json['number']?.toString(),
      seasonNumber: json['season']?.toString(),
      runtime: json['runtime'],
      airDate: json['airdate'],
      language: language,
      genres: genres,
      network: network,
      country: country,
    );
  }
}

class SeriesEpisode {
  final String url;
  final String title;
  final String filename;
  SeriesInfo seriesInfo; // Not final to allow TVMaze updates
  final int originalIndex;
  EpisodeInfo? episodeInfo;

  SeriesEpisode({
    required this.url,
    required this.title,
    required this.filename,
    required this.seriesInfo,
    required this.originalIndex,
    this.episodeInfo,
  });

  String get displayTitle {
    // If we have TVMaze episode info with a title, use that
    if (episodeInfo?.title != null && episodeInfo!.title!.isNotEmpty) {
      return episodeInfo!.title!;
    }

    // For Season 0 content (extras, alternate versions), use the episodeTitle
    if (seriesInfo.season == 0 && seriesInfo.episodeTitle != null && seriesInfo.episodeTitle!.isNotEmpty) {
      return seriesInfo.episodeTitle!;
    }

    // Fallback to episode number for series
    if (seriesInfo.isSeries && seriesInfo.season != null && seriesInfo.episode != null) {
      return 'Episode ${seriesInfo.episode}';
    }

    // Final fallback to filename/title
    return title;
  }

  String get seasonEpisodeString {
    if (seriesInfo.isSeries && seriesInfo.season != null && seriesInfo.episode != null) {
      return 'S${seriesInfo.season.toString().padLeft(2, '0')}E${seriesInfo.episode.toString().padLeft(2, '0')}';
    }
    return '';
  }
}

class SeriesSeason {
  final int seasonNumber;
  final List<SeriesEpisode> episodes;
  final String? seriesTitle;

  const SeriesSeason({
    required this.seasonNumber,
    required this.episodes,
    this.seriesTitle,
  });

  int get episodeCount => episodes.length;

  SeriesEpisode? getEpisode(int episodeNumber) {
    try {
      return episodes.firstWhere((ep) => ep.seriesInfo.episode == episodeNumber);
    } catch (e) {
      return null;
    }
  }
}

class SeriesPlaylist {
  final String? seriesTitle;
  final List<SeriesSeason> seasons;
  final List<SeriesEpisode> allEpisodes;
  final bool isSeries;

  const SeriesPlaylist({
    this.seriesTitle,
    required this.seasons,
    required this.allEpisodes,
    required this.isSeries,
  });

  int get totalEpisodes => allEpisodes.length;
  int get seasonCount => seasons.length;

  SeriesEpisode? getEpisode(int seasonNumber, int episodeNumber) {
    final season = seasons.firstWhere(
      (s) => s.seasonNumber == seasonNumber,
      orElse: () => throw Exception('Season $seasonNumber not found'),
    );
    return season.getEpisode(episodeNumber);
  }

  SeriesSeason? getSeason(int seasonNumber) {
    try {
      return seasons.firstWhere((s) => s.seasonNumber == seasonNumber);
    } catch (e) {
      return null;
    }
  }

  static SeriesPlaylist fromPlaylistEntries(
    List<PlaylistEntry> entries, {
    List<int>? fileSizes,
    String? collectionTitle,
  }) {
    debugPrint('SeriesPlaylist: Processing ${entries.length} entries${collectionTitle != null ? ", collection: \"$collectionTitle\"" : ""}');

    final filenames = entries.map((e) => e.title).toList();

    // Log first 2 filenames for debugging
    if (filenames.length >= 2) {
      debugPrint('SeriesPlaylist: Samples: [0] ${filenames[0]}, [1] ${filenames[1]}${filenames.length > 2 ? " ... +${filenames.length - 2} more" : ""}');
    } else if (filenames.length == 1) {
      debugPrint('SeriesPlaylist: Single file: ${filenames[0]}');
    }

    // Filter out SAMPLE files first
    final validIndices = <int>[];
    final validEntries = <PlaylistEntry>[];
    final validFilenames = <String>[];
    final validFileSizes = <int>[];

    for (int i = 0; i < entries.length; i++) {
      if (!SeriesParser.isSampleFile(filenames[i])) {
        validIndices.add(i);
        validEntries.add(entries[i]);
        validFilenames.add(filenames[i]);
        if (fileSizes != null && i < fileSizes.length) {
          validFileSizes.add(fileSizes[i]);
        } else {
          validFileSizes.add(0); // Default size if not provided
        }
      } else {
        debugPrint('SeriesPlaylist: Filtering out SAMPLE file: ${filenames[i]}');
      }
    }

    if (validEntries.isEmpty) {
      debugPrint('SeriesPlaylist: No valid entries after filtering samples');
      return SeriesPlaylist(
        seriesTitle: null,
        seasons: [],
        allEpisodes: [],
        isSeries: false,
      );
    }

    // Parse with file sizes for duplicate resolution
    final seriesInfos = SeriesParser.parsePlaylist(validFilenames, fileSizes: validFileSizes);
    final analysis = SeriesParser.analyzePlaylistConfidence(validFilenames);
    final isSeries = analysis.classification == PlaylistClassification.SERIES;

    debugPrint('SeriesPlaylist: Playlist classification: ${analysis.classification} (confidence: ${analysis.confidenceScore})');

    if (!isSeries) {
      debugPrint('SeriesPlaylist: Treating as movie collection');

      // For collections, use the collectionTitle if provided
      String? collectionSeriesTitle = collectionTitle;
      if (collectionSeriesTitle != null) {
        debugPrint('SeriesPlaylist: Using collection title for movie collection: "$collectionSeriesTitle"');
      } else if (seriesInfos.firstOrNull?.title != null) {
        collectionSeriesTitle = seriesInfos.firstOrNull!.title;
        debugPrint('SeriesPlaylist: Using extracted title from first file: "$collectionSeriesTitle"');
      } else {
        debugPrint('SeriesPlaylist: No title available for collection');
      }

      // Treat as movie collection: single season with all entries
      final episodes = validEntries.asMap().entries.map((entry) {
        final index = entry.key;
        final entryData = entry.value;
        return SeriesEpisode(
          url: entryData.url,
          title: entryData.title,
          filename: entryData.title,
          seriesInfo: seriesInfos[index],
          originalIndex: validIndices[index],
        );
      }).toList();

      return SeriesPlaylist(
        seriesTitle: collectionSeriesTitle,
        seasons: [
          SeriesSeason(
            seasonNumber: 1,
            episodes: episodes,
            seriesTitle: collectionSeriesTitle,
          ),
        ],
        allEpisodes: episodes,
        isSeries: false,
      );
    }

    // Detect and resolve duplicates
    final duplicateGroups = _detectDuplicates(seriesInfos, validFileSizes);
    final indicesToKeep = <int>{};
    final duplicateIndicesToMoveSeason0 = <int, String>{}; // index -> original S##E## label

    for (final group in duplicateGroups.values) {
      if (group.indices.length > 1) {
        final keepIndex = group.largestFileIndex;
        indicesToKeep.add(keepIndex);
        debugPrint('SeriesPlaylist: Found duplicate S${group.season.toString().padLeft(2, '0')}E${group.episode.toString().padLeft(2, '0')} - keeping largest (index $keepIndex, ${validFileSizes[keepIndex]} bytes)');

        // Track other duplicates to move to Season 0
        for (final idx in group.indices) {
          if (idx != keepIndex) {
            final label = 'S${group.season.toString().padLeft(2, '0')}E${group.episode.toString().padLeft(2, '0')}';
            duplicateIndicesToMoveSeason0[idx] = label;
            debugPrint('SeriesPlaylist: Will move duplicate to Season 0: ${validFilenames[idx]}');
          }
        }
      } else {
        indicesToKeep.add(group.indices.first);
      }
    }

    // Also keep entries that aren't duplicates
    for (int i = 0; i < seriesInfos.length; i++) {
      final info = seriesInfos[i];
      if (!info.isSeries || info.season == null || info.episode == null) {
        indicesToKeep.add(i);
      }
    }

    // MULTI-STRATEGY SERIES TITLE EXTRACTION
    // Try multiple methods to get the correct series title

    String? extractedTitle;
    String? collectionDerivedTitle;

    // Strategy 1: Extract common title from ALL filenames
    debugPrint('SeriesPlaylist: Attempting common title extraction from ${validFilenames.length} files');
    extractedTitle = SeriesParser.extractCommonSeriesTitle(validFilenames);

    if (extractedTitle != null) {
      debugPrint('SeriesPlaylist: Extracted common title from filenames: "$extractedTitle"');
    }

    // Strategy 2: Prepare collection-derived title
    if (collectionTitle != null) {
      collectionDerivedTitle = SeriesParser.cleanCollectionTitle(collectionTitle);
      if (SeriesParser.isValidSeriesTitle(collectionDerivedTitle)) {
        debugPrint('SeriesPlaylist: Cleaned collection title: "$collectionDerivedTitle"');
      } else {
        debugPrint('SeriesPlaylist: Collection title invalid after cleaning: "$collectionDerivedTitle"');
        collectionDerivedTitle = null;
      }
    }

    // Strategy 3: Decision logic - choose the best title
    String? seriesTitle;
    if (extractedTitle != null && SeriesParser.isValidSeriesTitle(extractedTitle)) {
      // Extracted title is valid, use it
      seriesTitle = extractedTitle;
      debugPrint('SeriesPlaylist: Using extracted title: "$seriesTitle"');
    } else if (collectionDerivedTitle != null) {
      // Fallback to collection title
      seriesTitle = collectionDerivedTitle;
      debugPrint('SeriesPlaylist: Using collection title: "$seriesTitle" (original: "$collectionTitle")');
    } else if (extractedTitle != null) {
      // Last resort: use extracted even if validation is weak
      seriesTitle = extractedTitle;
      debugPrint('SeriesPlaylist: Using extracted title (weak validation): "$seriesTitle"');
    } else {
      // No title available
      seriesTitle = null;
      debugPrint('SeriesPlaylist: No valid title found from filenames or collection');
    }

    // Group episodes by season, handling Season 0 for special content
    final seasonMap = <int, List<SeriesEpisode>>{};
    int season0Counter = 1;

    for (int i = 0; i < validEntries.length; i++) {
      if (!indicesToKeep.contains(i)) {
        debugPrint('SeriesPlaylist: Skipping duplicate at index $i');
        continue;
      }

      final entry = validEntries[i];
      var seriesInfo = seriesInfos[i];

      // Check if this is special content (pass parsedInfo to avoid false positives)
      final specialType = SeriesParser.getSpecialContentType(
        validFilenames[i],
        parsedInfo: seriesInfo,
      );
      if (specialType != null) {
        debugPrint('SeriesPlaylist: Moving \'$specialType\' to Season 0: ${validFilenames[i]}');
        // Update series info to Season 0
        seriesInfo = seriesInfo.copyWith(
          season: 0,
          episode: season0Counter++,
          episodeTitle: specialType,
        );
      }

      if (seriesInfo.isSeries && seriesInfo.season != null) {
        final seasonNumber = seriesInfo.season!;
        // Title extraction is now handled by multi-strategy logic above
        // No need to extract per-file anymore

        seasonMap.putIfAbsent(seasonNumber, () => []);
        seasonMap[seasonNumber]!.add(SeriesEpisode(
          url: entry.url,
          title: entry.title,
          filename: entry.title,
          seriesInfo: seriesInfo,
          originalIndex: validIndices[i],
        ));
      }
    }

    // Add duplicate files to Season 0 as Alternate Versions
    // Start episode numbering after any existing Season 0 content
    if (duplicateIndicesToMoveSeason0.isNotEmpty) {
      seasonMap.putIfAbsent(0, () => []);
      final existingSeason0Count = seasonMap[0]!.length;
      int alternateEpisodeNum = existingSeason0Count + 1;

      for (final entry in duplicateIndicesToMoveSeason0.entries) {
        final idx = entry.key;
        final originalLabel = entry.value;
        final playlistEntry = validEntries[idx];
        final originalInfo = seriesInfos[idx];

        // Create episode title with original label and filename for reference
        final episodeTitle = 'Alternate Version - $originalLabel (${validFilenames[idx]})';

        final alternateSeriesInfo = originalInfo.copyWith(
          season: 0,
          episode: alternateEpisodeNum,
          episodeTitle: episodeTitle,
        );

        seasonMap[0]!.add(SeriesEpisode(
          url: playlistEntry.url,
          title: playlistEntry.title,
          filename: playlistEntry.title,
          seriesInfo: alternateSeriesInfo,
          originalIndex: validIndices[idx],
        ));

        debugPrint('SeriesPlaylist: Added alternate version to S00E${alternateEpisodeNum.toString().padLeft(2, '0')}: $episodeTitle');
        alternateEpisodeNum++;
      }
    }

    // Title selection is now handled by multi-strategy logic above
    // No need for collection title fallback here

    if (seasonMap.isEmpty) {
      // Detected as series but no season numbers were parsed; fallback to a single implicit season.
      debugPrint('SeriesPlaylist: No seasons detected, using fallback to Season 1');
      final fallbackEpisodes = validEntries.asMap().entries.map((entry) {
        final index = entry.key;
        final entryData = entry.value;
        final info = seriesInfos[index];

        // Preserve parsed episode numbers when available; otherwise derive from order (1-based).
        final fallbackInfo = info.isSeries
            ? info
            : SeriesInfo(
                title: info.title,
                season: 1,
                episode: index + 1,
                episodeTitle: info.episodeTitle,
                year: info.year,
                quality: info.quality,
                audioCodec: info.audioCodec,
                videoCodec: info.videoCodec,
                group: info.group,
                isSeries: true,
              );

        return SeriesEpisode(
          url: entryData.url,
          title: entryData.title,
          filename: entryData.title,
          seriesInfo: SeriesInfo(
            title: fallbackInfo.title,
            season: fallbackInfo.season ?? 1,
            episode: fallbackInfo.episode ?? (index + 1),
            episodeTitle: fallbackInfo.episodeTitle,
            year: fallbackInfo.year,
            quality: fallbackInfo.quality,
            audioCodec: fallbackInfo.audioCodec,
            videoCodec: fallbackInfo.videoCodec,
            group: fallbackInfo.group,
            isSeries: true,
          ),
          originalIndex: validIndices[index],
        );
      }).toList();

      return SeriesPlaylist(
        seriesTitle: seriesInfos.firstOrNull?.title,
        seasons: [
          SeriesSeason(
            seasonNumber: 1,
            episodes: fallbackEpisodes,
            seriesTitle: seriesInfos.firstOrNull?.title,
          ),
        ],
        allEpisodes: fallbackEpisodes,
        isSeries: true,
      );
    }

    // Sort episodes within each season
    for (final season in seasonMap.values) {
      season.sort((a, b) {
        final aEpisode = a.seriesInfo.episode ?? 0;
        final bEpisode = b.seriesInfo.episode ?? 0;
        return aEpisode.compareTo(bEpisode);
      });
    }

    // Create season objects
    final seasons = seasonMap.entries.map((entry) {
      return SeriesSeason(
        seasonNumber: entry.key,
        episodes: entry.value,
        seriesTitle: seriesTitle,
      );
    }).toList();

    // Sort seasons
    seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

    // Create flat list of all episodes
    final allEpisodes = seasons.expand((season) => season.episodes).toList();

    return SeriesPlaylist(
      seriesTitle: seriesTitle,
      seasons: seasons,
      allEpisodes: allEpisodes,
      isSeries: true,
    );
  }

  /// Fetch episode information for all episodes in the playlist
  Future<void> fetchEpisodeInfo() async {
    if (!isSeries) {
      debugPrint('SeriesPlaylist: Not a series, skipping TVMaze fetch');
      return;
    }

    // Try to extract series title from filenames if not already set
    String? searchTitle = seriesTitle;
    if (searchTitle == null && allEpisodes.isNotEmpty) {
      searchTitle = allEpisodes.first.seriesInfo.title;
    }

    // Validate the series title before searching
    if (!SeriesParser.isValidSeriesTitle(searchTitle)) {
      debugPrint('TVMaze: Cannot search - invalid title "$searchTitle"');
      return;
    }

    final validSearchTitle = searchTitle!;
    debugPrint('TVMaze: Searching for "$validSearchTitle"');

    // First, get the show information to extract genres, language, network, etc.
    Map<String, dynamic>? showInfo;
    try {
      showInfo = await EpisodeInfoService.getSeriesInfo(validSearchTitle);
      // Found series info (no log needed, success assumed)
    } catch (e) {
      debugPrint('TVMaze: Series lookup failed: $e');
    }

    // Get all episodes from TVMaze if available for title-only matching
    List<Map<String, dynamic>> allTVMazeEpisodes = [];
    bool hasTitleOnlyEpisodes = allEpisodes.any((ep) =>
      ep.seriesInfo.season == null || ep.seriesInfo.episode == null
    );

    if (hasTitleOnlyEpisodes && showInfo != null) {
      try {
        allTVMazeEpisodes = await EpisodeInfoService.getAllEpisodes(validSearchTitle);
        debugPrint('TVMaze: Got ${allTVMazeEpisodes.length} episodes for title matching');
      } catch (e) {
        debugPrint('TVMaze: Episode list failed: $e');
      }
    }

    // Process each episode
    for (final season in seasons) {
      for (final episode in season.episodes) {
        // Skip Season 0 (special content)
        if (episode.seriesInfo.season == 0) {
          continue;
        }

        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          // Standard episode with S##E## format
          try {
            final episodeData = await EpisodeInfoService.getEpisodeInfo(
              validSearchTitle,
              episode.seriesInfo.season!,
              episode.seriesInfo.episode!,
            );
            if (episodeData != null) {
              episode.episodeInfo = EpisodeInfo.fromTVMaze(episodeData, showInfo: showInfo);
              // Episode matched (no log per episode)
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

            if (score > bestScore && score > 0.6) { // 60% similarity threshold
              bestScore = score;
              bestMatch = tvEpisode;
            }
          }

          if (bestMatch != null) {
            episode.episodeInfo = EpisodeInfo.fromTVMaze(bestMatch, showInfo: showInfo);
            // Update the SeriesInfo with matched S##E##
            final matchedSeason = bestMatch['season'] as int?;
            final matchedEpisode = bestMatch['number'] as int?;
            if (matchedSeason != null && matchedEpisode != null) {
              episode.seriesInfo = episode.seriesInfo.copyWith(
                season: matchedSeason,
                episode: matchedEpisode,
              );
              debugPrint('TVMaze: Title match "${episode.filename}" → S${matchedSeason.toString().padLeft(2, '0')}E${matchedEpisode.toString().padLeft(2, '0')} (${(bestScore * 100).toStringAsFixed(0)}%)');
            }
          }
          // No match - skip logging for cleaner output
        }
      }
    }

    // If TVMaze fetch failed completely, log fallback
    if (showInfo == null && isSeries) {
      debugPrint('SeriesPlaylist: TVMaze unavailable, treating as MOVIE_COLLECTION fallback');
    }
   }

  /// Get episode information for a specific episode
  Future<EpisodeInfo?> getEpisodeInfoForEpisode(String seriesTitle, int season, int episode) async {
    try {
      // Get show information first
      final showInfo = await EpisodeInfoService.getSeriesInfo(seriesTitle);
      
      final episodeData = await EpisodeInfoService.getEpisodeInfo(seriesTitle, season, episode);
      if (episodeData != null) {
        return EpisodeInfo.fromTVMaze(episodeData, showInfo: showInfo);
      }
    } catch (e) {
    }
    return null;
  }

  /// Find the original index in the PlaylistEntry array by season and episode
  /// Returns -1 if not found
  int findOriginalIndexBySeasonEpisode(int season, int episode) {
    for (int i = 0; i < allEpisodes.length; i++) {
      final episodeInfo = allEpisodes[i];
      if (episodeInfo.seriesInfo.season == season && 
          episodeInfo.seriesInfo.episode == episode) {
        return episodeInfo.originalIndex;
      }
    }
    return -1;
  }

  /// Get the original index of the first episode (lowest season > 0, lowest episode)
  /// Skips Season 0 (extras/alternate versions) unless that's all there is
  /// Returns -1 if no episodes found
  int getFirstEpisodeOriginalIndex() {
    if (allEpisodes.isEmpty) {
      return -1;
    }

    // Find first episode where season > 0 (skip extras/alternate versions)
    for (final episode in allEpisodes) {
      if (episode.seriesInfo.season != null &&
          episode.seriesInfo.season! > 0 &&
          episode.seriesInfo.episode != null) {
        return episode.originalIndex;
      }
    }

    // Fallback to Season 0 if no regular seasons exist
    final firstEpisode = allEpisodes.first;
    if (firstEpisode.seriesInfo.season != null && firstEpisode.seriesInfo.episode != null) {
      return firstEpisode.originalIndex;
    }
    return -1;
  }

  /// Detect duplicate episodes based on S##E## numbers
  static Map<String, DuplicateGroup> _detectDuplicates(
    List<SeriesInfo> seriesInfos,
    List<int> fileSizes,
  ) {
    final duplicateMap = <String, DuplicateGroup>{};

    for (int i = 0; i < seriesInfos.length; i++) {
      final info = seriesInfos[i];
      if (info.isSeries && info.season != null && info.episode != null) {
        final key = 'S${info.season}E${info.episode}';

        if (!duplicateMap.containsKey(key)) {
          duplicateMap[key] = DuplicateGroup(
            season: info.season!,
            episode: info.episode!,
            indices: [],
            fileSizes: [],
          );
        }

        duplicateMap[key]!.indices.add(i);
        if (i < fileSizes.length) {
          duplicateMap[key]!.fileSizes.add(fileSizes[i]);
        } else {
          duplicateMap[key]!.fileSizes.add(0);
        }
      }
    }

    return duplicateMap;
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
}
