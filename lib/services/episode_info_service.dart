import 'dart:async';
import 'tvmaze_service.dart';

class EpisodeInfoService {
  static final Map<String, dynamic> _cache = {};
  static final Map<String, int> _seriesIdCache = {};
  static Timer? _rateLimitTimer;
  static bool _isRateLimited = false;

  /// Rate limiting helper
  static Future<void> _rateLimit() async {
    if (_isRateLimited) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _isRateLimited = true;
    _rateLimitTimer?.cancel();
    _rateLimitTimer = Timer(const Duration(milliseconds: 100), () {
      _isRateLimited = false;
    });
  }

  /// Get episode information from TVMaze with fallback
  static Future<Map<String, dynamic>?> getEpisodeInfo(
    String seriesTitle,
    int season,
    int episode,
  ) async {
    final cacheKey = '${seriesTitle}_${season}_$episode';
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached is Map<String, dynamic>) {
        return cached;
      }
    }

    // Check if TVMaze is available
    if (!TVMazeService.currentAvailability) {
      print('TVMaze not available, skipping episode info fetch');
      return null;
    }

    await _rateLimit();

    try {
      final episodeInfo = await TVMazeService.getEpisodeInfo(
        seriesTitle,
        season,
        episode,
      );

      if (episodeInfo != null) {
        _cache[cacheKey] = episodeInfo;
        return episodeInfo;
      }
    } catch (e) {
      print('Failed to get episode info: $e');
    }

    return null;
  }

  /// Get series information from TVMaze with fallback
  static Future<Map<String, dynamic>?> getSeriesInfo(String seriesTitle) async {
    final cacheKey = 'series_$seriesTitle';
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached is Map<String, dynamic>) {
        return cached;
      }
    }

    // Check if TVMaze is available
    if (!TVMazeService.currentAvailability) {
      print('TVMaze not available, skipping series info fetch');
      return null;
    }

    await _rateLimit();

    try {
      final seriesInfo = await TVMazeService.getShowInfo(seriesTitle);
      
      if (seriesInfo != null) {
        _cache[cacheKey] = seriesInfo;
        return seriesInfo;
      }
    } catch (e) {
      print('Failed to get series info: $e');
    }

    return null;
  }

  /// Get all episodes for a series with fallback
  static Future<List<Map<String, dynamic>>> getAllEpisodes(String seriesTitle) async {
    final cacheKey = 'all_episodes_$seriesTitle';
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached is List) {
        return List<Map<String, dynamic>>.from(cached);
      }
    }

    // Check if TVMaze is available
    if (!TVMazeService.currentAvailability) {
      print('TVMaze not available, skipping episodes fetch');
      return [];
    }

    await _rateLimit();

    try {
      // First get series info to get the ID
      final seriesInfo = await getSeriesInfo(seriesTitle);
      if (seriesInfo != null && seriesInfo['id'] != null) {
        final episodes = await TVMazeService.getEpisodes(seriesInfo['id'] as int);
        _cache[cacheKey] = episodes;
        return episodes;
      }
    } catch (e) {
      print('Failed to get all episodes: $e');
    }

    return [];
  }

  /// Force refresh TVMaze availability
  static Future<void> refreshAvailability() async {
    await TVMazeService.refreshAvailability();
  }

  /// Get current TVMaze availability status
  static bool get isTVMazeAvailable => TVMazeService.currentAvailability;

  /// Clear cache
  static void clearCache() {
    _cache.clear();
    _seriesIdCache.clear();
  }

  /// Dispose resources
  static void dispose() {
    _rateLimitTimer?.cancel();
    clearCache();
  }
} 