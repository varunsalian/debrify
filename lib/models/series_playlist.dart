import '../utils/series_parser.dart';
import '../screens/video_player_screen.dart';
import '../services/episode_info_service.dart';

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
    if (seriesInfo.isSeries && seriesInfo.season != null && seriesInfo.episode != null) {
      return 'Episode ${seriesInfo.episode}';
    }
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
      // Return as a single "season" for movies
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
    if (!isSeries || seriesTitle == null) return;

    for (final season in seasons) {
      for (final episode in season.episodes) {
        if (episode.seriesInfo.season != null && episode.seriesInfo.episode != null) {
          try {
            final episodeInfo = await EpisodeInfoService.getEpisodeInfoByTitle(
              seriesTitle!,
              episode.seriesInfo.season!,
              episode.seriesInfo.episode!,
            );
            episode.episodeInfo = episodeInfo;
          } catch (e) {
            // Silently fail - episode info is optional
            print('Failed to fetch episode info: $e');
          }
        }
      }
    }
  }
} 