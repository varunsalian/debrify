import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class StorageService {
  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  static const String _postTorrentActionKey = 'post_torrent_action';
  static const String _batteryOptStatusKey = 'battery_opt_status_v1'; // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _playbackStateKey = 'playback_state_v1';
  
  // API Key methods
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, apiKey);
  }

  static Future<void> deleteApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
  }

  // File Selection methods
  static Future<String> getFileSelection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fileSelectionKey) ?? 'largest'; // Default to largest file
  }

  static Future<void> saveFileSelection(String selection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileSelectionKey, selection);
  }

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_postTorrentActionKey) ?? 'none';
  }

  static Future<void> savePostTorrentAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postTorrentActionKey, action);
  }

  // Battery optimization status
  static Future<String> getBatteryOptimizationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_batteryOptStatusKey) ?? 'unknown';
  }

  static Future<void> setBatteryOptimizationStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_batteryOptStatusKey, status);
  }

  // Enhanced Playback State methods
  static Future<Map<String, dynamic>> _getPlaybackStateMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playbackStateKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _savePlaybackStateMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playbackStateKey, jsonEncode(map));
  }

  /// Save playback state for series content
  static Future<void> saveSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
      };
    }
    
    final seriesData = map[key] as Map<String, dynamic>;
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }
    
    seriesData['seasons'][season.toString()][episode.toString()] = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _savePlaybackStateMap(map);
  }

  /// Get playback state for series content
  static Future<Map<String, dynamic>?> getSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;
    
    final seasonData = seriesData['seasons'][season.toString()];
    if (seasonData == null) return null;
    
    final episodeData = seasonData[episode.toString()];
    if (episodeData == null) return null;
    
    return episodeData as Map<String, dynamic>;
  }

  /// Save playback state for non-series content (movies, single videos)
  static Future<void> saveVideoPlaybackState({
    required String videoTitle,
    required String videoUrl,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    map[key] = {
      'type': 'video',
      'title': videoTitle,
      'url': videoUrl,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _savePlaybackStateMap(map);
  }

  /// Get playback state for non-series content
  static Future<Map<String, dynamic>?> getVideoPlaybackState({
    required String videoTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;
    
    return videoData as Map<String, dynamic>;
  }

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;
    
    // Find the most recently updated episode
    Map<String, dynamic>? lastEpisode;
    int lastUpdated = 0;
    
    final seasons = seriesData['seasons'] as Map<String, dynamic>;
    for (final seasonEntry in seasons.entries) {
      final season = int.parse(seasonEntry.key);
      final episodes = seasonEntry.value as Map<String, dynamic>;
      
      for (final episodeEntry in episodes.entries) {
        final episode = int.parse(episodeEntry.key);
        final episodeData = episodeEntry.value as Map<String, dynamic>;
        final updatedAt = episodeData['updatedAt'] as int;
        
        if (updatedAt > lastUpdated) {
          lastUpdated = updatedAt;
          lastEpisode = {
            'season': season,
            'episode': episode,
            ...episodeData,
          };
        }
      }
    }
    
    return lastEpisode;
  }

  /// Clean up old playback state data (older than 30 days)
  static Future<void> cleanupOldPlaybackState() async {
    final map = await _getPlaybackStateMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);
    
    final keysToRemove = <String>[];
    
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final updatedAt = data['updatedAt'] as int?;
      
      if (updatedAt != null && updatedAt < thirtyDaysAgo) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      map.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      await _savePlaybackStateMap(map);
    }
  }

  // Video resume map helpers (legacy - keeping for backward compatibility)
  static Future<Map<String, dynamic>> _getVideoResumeMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_videoResumeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveVideoResumeMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoResumeKey, jsonEncode(map));
  }

  static Future<Map<String, dynamic>?> getVideoResume(String key) async {
    final map = await _getVideoResumeMap();
    final entry = map[key];
    if (entry is Map<String, dynamic>) return entry;
    return null;
  }

  static Future<void> upsertVideoResume(String key, Map<String, dynamic> entry) async {
    final map = await _getVideoResumeMap();
    map[key] = entry;
    await _saveVideoResumeMap(map);
  }
} 