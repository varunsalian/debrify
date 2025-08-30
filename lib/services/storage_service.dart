import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'secure_storage_service.dart';
import 'debrid_service.dart';

class StorageService {
  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  static const String _postTorrentActionKey = 'post_torrent_action';
  static const String _batteryOptStatusKey = 'battery_opt_status_v1'; // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _playbackStateKey = 'playback_state_v1';
  static const String _maxParallelDownloadsKey = 'max_parallel_downloads_v1';
  static const String _defaultTorrentsCsvEnabledKey = 'default_torrents_csv_enabled';
  static const String _defaultPirateBayEnabledKey = 'default_pirate_bay_enabled';
  static const String _maxTorrentsCsvResultsKey = 'max_torrents_csv_results';
  
  // API Key methods - Updated to use secure storage with migration
  static Future<String?> getApiKey() async {
    // Try secure storage first
    final secureKey = await SecureStorageService.getApiKey();
    if (secureKey != null) return secureKey;
    
    // Fallback to old storage (for migration)
    final prefs = await SharedPreferences.getInstance();
    final oldKey = prefs.getString(_apiKeyKey);
    
    // Migrate to secure storage if found
    if (oldKey != null) {
      await SecureStorageService.saveApiKey(oldKey);
      await prefs.remove(_apiKeyKey); // Clean up old storage
    }
    
    return oldKey;
  }

  static Future<void> saveApiKey(String apiKey) async {
    // Save to secure storage
    await SecureStorageService.saveApiKey(apiKey);
    
    // Clean up old storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
  }

  static Future<void> deleteApiKey() async {
    // Delete from both secure and old storage
    await SecureStorageService.deleteApiKey();
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

  // Download settings
  static Future<int> getMaxParallelDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_maxParallelDownloadsKey);
    if (val == null || val <= 0) return 2; // default
    return val;
  }

  static Future<void> setMaxParallelDownloads(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxParallelDownloadsKey, value.clamp(1, 8));
  }

  // Default search engine settings
  static Future<bool> getDefaultTorrentsCsvEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultTorrentsCsvEnabledKey) ?? true; // Default to enabled
  }

  static Future<void> setDefaultTorrentsCsvEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultTorrentsCsvEnabledKey, enabled);
  }

  static Future<bool> getDefaultPirateBayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultPirateBayEnabledKey) ?? true; // Default to enabled
  }

  static Future<void> setDefaultPirateBayEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultPirateBayEnabledKey, enabled);
  }

  // Max results settings
  static Future<int> getMaxTorrentsCsvResults() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxTorrentsCsvResultsKey) ?? 50; // Default to 50
  }

  static Future<void> setMaxTorrentsCsvResults(int maxResults) async {
    final prefs = await SharedPreferences.getInstance();
    // Clamp between 25 and 500
    final clampedValue = maxResults.clamp(25, 500);
    await prefs.setInt(_maxTorrentsCsvResultsKey, clampedValue);
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

  /// Mark an episode as finished (watched completely)
  static Future<void> markEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'finishedEpisodes': {},
      };
    }
    
    final seriesData = map[key] as Map<String, dynamic>;
    if (!seriesData.containsKey('finishedEpisodes')) {
      seriesData['finishedEpisodes'] = {};
    }
    
    if (!seriesData['finishedEpisodes'].containsKey(season.toString())) {
      seriesData['finishedEpisodes'][season.toString()] = {};
    }
    
    seriesData['finishedEpisodes'][season.toString()][episode.toString()] = {
      'finishedAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _savePlaybackStateMap(map);
  }

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return false;
    
    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes == null) return false;
    
    final seasonData = finishedEpisodes[season.toString()];
    if (seasonData == null) return false;
    
    return seasonData.containsKey(episode.toString());
  }

  /// Get all finished episodes for a series
  static Future<Map<String, Set<int>>> getFinishedEpisodes({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};
    
    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes == null) return {};
    
    final result = <String, Set<int>>{};
    
    for (final seasonEntry in finishedEpisodes.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;
      result[season] = episodes.keys.map((e) => int.parse(e)).toSet();
    }
    
    return result;
  }

  /// Get episode progress for a series
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgress({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};
    
    final seasons = seriesData['seasons'];
    if (seasons == null) return {};
    
    final result = <String, Map<String, dynamic>>{};
    
    for (final seasonEntry in seasons.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;
      
      for (final episodeEntry in episodes.entries) {
        final episode = episodeEntry.key;
        final episodeData = episodeEntry.value as Map<String, dynamic>;
        final episodeKey = '${season}_$episode';
        result[episodeKey] = episodeData;
      }
    }
    
    return result;
  }

  /// Get finished episodes for a specific season
  static Future<Set<int>> getFinishedEpisodesForSeason({
    required String seriesTitle,
    required int season,
  }) async {
    final allFinished = await getFinishedEpisodes(seriesTitle: seriesTitle);
    return allFinished[season.toString()] ?? <int>{};
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

  /// Save audio and subtitle preferences for series content
  static Future<void> saveSeriesTrackPreferences({
    required String seriesTitle,
    required String audioTrackId,
    required String subtitleTrackId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'trackPreferences': {},
      };
    }
    
    final seriesData = map[key] as Map<String, dynamic>;
    if (!seriesData.containsKey('trackPreferences')) {
      seriesData['trackPreferences'] = {};
    }
    
    seriesData['trackPreferences'] = {
      'audioTrackId': audioTrackId,
      'subtitleTrackId': subtitleTrackId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _savePlaybackStateMap(map);
  }

  /// Get audio and subtitle preferences for series content
  static Future<Map<String, dynamic>?> getSeriesTrackPreferences({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;
    
    final trackPreferences = seriesData['trackPreferences'];
    if (trackPreferences == null) return null;
    
    return trackPreferences as Map<String, dynamic>;
  }

  /// Save audio and subtitle preferences for non-series content
  static Future<void> saveVideoTrackPreferences({
    required String videoTitle,
    required String audioTrackId,
    required String subtitleTrackId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'video',
        'title': videoTitle,
        'trackPreferences': {},
      };
    }
    
    final videoData = map[key] as Map<String, dynamic>;
    if (!videoData.containsKey('trackPreferences')) {
      videoData['trackPreferences'] = {};
    }
    
    videoData['trackPreferences'] = {
      'audioTrackId': audioTrackId,
      'subtitleTrackId': subtitleTrackId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _savePlaybackStateMap(map);
  }

  /// Get audio and subtitle preferences for non-series content
  static Future<Map<String, dynamic>?> getVideoTrackPreferences({
    required String videoTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key = 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    
    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;
    
    final trackPreferences = videoData['trackPreferences'];
    if (trackPreferences == null) return null;
    
    return trackPreferences as Map<String, dynamic>;
  }
}

class ApiKeyValidator {
  static bool isValidFormat(String apiKey) {
    // Real Debrid API keys are typically 40 characters
    return apiKey.length == 40 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(apiKey);
  }
  
  static Future<bool> validateApiKey(String apiKey) async {
    if (!isValidFormat(apiKey)) return false;
    
    try {
      final user = await DebridService.getUserInfo(apiKey);
      return true; // If we get here, the API key is valid
    } catch (e) {
      return false;
    }
  }
} 