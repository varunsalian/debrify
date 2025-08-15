import 'dart:convert';
import 'package:http/http.dart' as http;

class EpisodeInfo {
  final String? title;
  final String? plot;
  final String? poster;
  final String? rating;
  final String? year;
  final String? episodeNumber;
  final String? seasonNumber;
  final int? runtime;

  const EpisodeInfo({
    this.title,
    this.plot,
    this.poster,
    this.rating,
    this.year,
    this.episodeNumber,
    this.seasonNumber,
    this.runtime,
  });

  factory EpisodeInfo.fromJson(Map<String, dynamic> json) {
    return EpisodeInfo(
      title: json['name'],
      plot: json['overview'],
      poster: json['still_path'] != null 
          ? 'https://image.tmdb.org/t/p/w500${json['still_path']}'
          : null,
      rating: json['vote_average']?.toString(),
      year: json['air_date']?.substring(0, 4),
      episodeNumber: json['episode_number']?.toString(),
      seasonNumber: json['season_number']?.toString(),
      runtime: json['runtime'],
    );
  }
}

class EpisodeInfoService {
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _apiKey = '1b5adf76a72a13bad99b8fc0c68cb085'; // Free public API key
  
  // Cache to avoid repeated API calls
  static final Map<String, EpisodeInfo> _cache = {};
  static final Map<String, int> _seriesIdCache = {};
  
  /// Search for a series by title
  static Future<int?> searchSeriesId(String seriesTitle) async {
    // Check cache first
    if (_seriesIdCache.containsKey(seriesTitle)) {
      return _seriesIdCache[seriesTitle];
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/search/tv?query=${Uri.encodeComponent(seriesTitle)}&api_key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final seriesId = data['results'][0]['id'] as int;
          _seriesIdCache[seriesTitle] = seriesId;
          return seriesId;
        }
      }
    } catch (e) {
      print('Error searching for series: $e');
    }
    return null;
  }

  /// Get episode information by series ID, season, and episode
  static Future<EpisodeInfo?> getEpisodeInfo(int seriesId, int season, int episode) async {
    final cacheKey = '${seriesId}_S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/tv/$seriesId/season/$season/episode/$episode?api_key=$_apiKey'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['name'] != null) {
          final episodeInfo = EpisodeInfo.fromJson(data);
          _cache[cacheKey] = episodeInfo;
          return episodeInfo;
        }
      }
    } catch (e) {
      print('Error fetching episode info: $e');
    }
    return null;
  }

  /// Get episode information by series title, season, and episode
  static Future<EpisodeInfo?> getEpisodeInfoByTitle(String seriesTitle, int season, int episode) async {
    try {
      print('Fetching episode info for: $seriesTitle S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}');
      
      // First search for the series ID
      final seriesId = await searchSeriesId(seriesTitle);
      if (seriesId != null) {
        print('Found series ID: $seriesId');
        final episodeInfo = await getEpisodeInfo(seriesId, season, episode);
        if (episodeInfo != null) {
          print('Episode info loaded - Title: ${episodeInfo.title}, Poster: ${episodeInfo.poster != null ? 'Available' : 'Not available'}');
        } else {
          print('No episode info found');
        }
        return episodeInfo;
      } else {
        print('Series not found: $seriesTitle');
      }
    } catch (e) {
      print('Error getting episode info by title: $e');
    }
    return null;
  }

  /// Clear the cache
  static void clearCache() {
    _cache.clear();
    _seriesIdCache.clear();
  }

  /// Get cache size
  static int get cacheSize => _cache.length;
} 