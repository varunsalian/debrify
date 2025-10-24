import '../utils/series_parser.dart';
import '../screens/video_player_screen.dart';
import '../services/episode_info_service.dart';

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
  final SeriesInfo seriesInfo;
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

  static SeriesPlaylist fromPlaylistEntries(List<PlaylistEntry> entries) {
    final filenames = entries.map((e) => e.title).toList();
    final seriesInfos = SeriesParser.parsePlaylist(filenames);
    final isSeries = SeriesParser.isSeriesPlaylist(filenames);

    if (!isSeries) {
      // Treat as movie collection: single season with all entries
      final episodes = entries.asMap().entries.map((entry) {
        final index = entry.key;
        final entryData = entry.value;
        return SeriesEpisode(
          url: entryData.url,
          title: entryData.title,
          filename: entryData.title,
          seriesInfo: seriesInfos[index],
          originalIndex: index,
        );
      }).toList();

      return SeriesPlaylist(
        seriesTitle: seriesInfos.firstOrNull?.title,
        seasons: [
          SeriesSeason(
            seasonNumber: 1,
            episodes: episodes,
            seriesTitle: seriesInfos.firstOrNull?.title,
          ),
        ],
        allEpisodes: episodes,
        isSeries: false,
      );
    }

    // Group episodes by season
    final seasonMap = <int, List<SeriesEpisode>>{};
    String? seriesTitle;

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final seriesInfo = seriesInfos[i];
      
      if (seriesInfo.isSeries && seriesInfo.season != null) {
        final seasonNumber = seriesInfo.season!;
        seriesTitle ??= seriesInfo.title;
        
        seasonMap.putIfAbsent(seasonNumber, () => []);
        seasonMap[seasonNumber]!.add(SeriesEpisode(
          url: entry.url,
          title: entry.title,
          filename: entry.title,
          seriesInfo: seriesInfo,
          originalIndex: i,
        ));
      }
    }

    if (seasonMap.isEmpty) {
      // Detected as series but no season numbers were parsed; fallback to a single implicit season.
      final fallbackEpisodes = entries.asMap().entries.map((entry) {
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
          originalIndex: index,
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
    if (!isSeries || seriesTitle == null) {
      return;
    }

    // First, get the show information to extract genres, language, network, etc.
    Map<String, dynamic>? showInfo;
    try {
      showInfo = await EpisodeInfoService.getSeriesInfo(seriesTitle!);
    } catch (e) {
    }

    for (final season in seasons) {
      for (final episode in season.episodes) {
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          try {
            final episodeData = await EpisodeInfoService.getEpisodeInfo(
              seriesTitle!,
              episode.seriesInfo.season!,
              episode.seriesInfo.episode!,
            );
            if (episodeData != null) {
              episode.episodeInfo = EpisodeInfo.fromTVMaze(episodeData, showInfo: showInfo);
            }
          } catch (e) {
            // Silently fail - episode info is optional
          }
        }
      }
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

  /// Get the original index of the first episode (lowest season, lowest episode)
  /// Returns -1 if no episodes found
  int getFirstEpisodeOriginalIndex() {
    if (allEpisodes.isEmpty) {
      return -1;
    }
    
    // The allEpisodes list is already sorted by season and episode
    // So the first episode is the one with lowest season and episode
    final firstEpisode = allEpisodes.first;
    if (firstEpisode.seriesInfo.season != null && firstEpisode.seriesInfo.episode != null) {
      return firstEpisode.originalIndex;
    }
    return -1;
  }
} 
