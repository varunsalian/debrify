import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing persistent cache of TVMaze API responses
/// Caches data for 30 days to reduce API calls
class TVMazeCacheService {
  static const String _cachePrefix = 'tvmaze_cache_';
  static const String _timestampPrefix = 'tvmaze_timestamp_';
  static const Duration _cacheDuration = Duration(days: 30);

  /// Get cached data for a given key
  /// Returns null if data doesn't exist or has expired
  static Future<Map<String, dynamic>?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cachePrefix + key;
      final timestampKey = _timestampPrefix + key;

      // Check if data exists
      final jsonString = prefs.getString(cacheKey);
      if (jsonString == null) {
        return null;
      }

      // Check expiration
      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) {
        // No timestamp, consider expired
        await _remove(key);
        return null;
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();

      if (now.difference(cacheTime) > _cacheDuration) {
        // Cache expired, remove it
        await _remove(key);
        return null;
      }

      // Parse and return data
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      print('⚠️ TVMaze Cache: Error reading cache for key "$key": $e');
      return null;
    }
  }

  /// Get cached list data for a given key
  /// Returns null if data doesn't exist or has expired
  static Future<List<Map<String, dynamic>>?> getList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cachePrefix + key;
      final timestampKey = _timestampPrefix + key;

      // Check if data exists
      final jsonString = prefs.getString(cacheKey);
      if (jsonString == null) {
        return null;
      }

      // Check expiration
      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) {
        // No timestamp, consider expired
        await _remove(key);
        return null;
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();

      if (now.difference(cacheTime) > _cacheDuration) {
        // Cache expired, remove it
        await _remove(key);
        return null;
      }

      // Parse and return data
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      print('⚠️ TVMaze Cache: Error reading list cache for key "$key": $e');
      return null;
    }
  }

  /// Store data in cache with current timestamp
  static Future<void> set(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cachePrefix + key;
      final timestampKey = _timestampPrefix + key;

      // Store data as JSON string
      final jsonString = json.encode(data);
      await prefs.setString(cacheKey, jsonString);

      // Store timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(timestampKey, now);
    } catch (e) {
      print('⚠️ TVMaze Cache: Error writing cache for key "$key": $e');
    }
  }

  /// Store list data in cache with current timestamp
  static Future<void> setList(String key, List<Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cachePrefix + key;
      final timestampKey = _timestampPrefix + key;

      // Store data as JSON string
      final jsonString = json.encode(data);
      await prefs.setString(cacheKey, jsonString);

      // Store timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(timestampKey, now);
    } catch (e) {
      print('⚠️ TVMaze Cache: Error writing list cache for key "$key": $e');
    }
  }

  /// Remove a specific cache entry
  static Future<void> _remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _cachePrefix + key;
      final timestampKey = _timestampPrefix + key;

      await prefs.remove(cacheKey);
      await prefs.remove(timestampKey);
    } catch (e) {
      print('⚠️ TVMaze Cache: Error removing cache for key "$key": $e');
    }
  }

  /// Clean up all expired cache entries
  static Future<void> cleanupExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int removedCount = 0;
      final now = DateTime.now();

      // Find all cache keys
      for (final key in keys) {
        if (key.startsWith(_timestampPrefix)) {
          final timestamp = prefs.getInt(key);
          if (timestamp != null) {
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

            if (now.difference(cacheTime) > _cacheDuration) {
              // Extract the original key (remove prefix)
              final originalKey = key.substring(_timestampPrefix.length);
              await _remove(originalKey);
              removedCount++;
            }
          }
        }
      }

      if (removedCount > 0) {
        print('🧹 TVMaze Cache: Cleaned up $removedCount expired entries');
      }
    } catch (e) {
      print('⚠️ TVMaze Cache: Error during cleanup: $e');
    }
  }

  /// Clear all TVMaze cache
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int removedCount = 0;

      // Remove all keys with our prefix
      for (final key in keys) {
        if (key.startsWith(_cachePrefix) || key.startsWith(_timestampPrefix)) {
          await prefs.remove(key);
          removedCount++;
        }
      }

      print('🧹 TVMaze Cache: Cleared all cache ($removedCount entries)');
    } catch (e) {
      print('⚠️ TVMaze Cache: Error clearing all cache: $e');
    }
  }

  /// Clear cache for a specific series
  static Future<void> clearSeriesCache(String seriesTitle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Clean the series title the same way TVMazeService does
      final cleanName = _cleanShowName(seriesTitle);
      final searchKey = 'search_$cleanName';

      int removedCount = 0;

      // Remove all keys related to this series
      for (final key in keys) {
        if (key.contains(searchKey)) {
          await prefs.remove(key);
          removedCount++;
        }
      }

      if (removedCount > 0) {
        print('🧹 TVMaze Cache: Cleared cache for "$seriesTitle" ($removedCount entries)');
      }
    } catch (e) {
      print('⚠️ TVMaze Cache: Error clearing series cache: $e');
    }
  }

  /// Clear all cached data for a specific show ID from persistent storage
  static Future<void> clearShowCache(int showId) async {
    await _remove('show_$showId');
    await _remove('episodes_$showId');
    debugPrint('🧹 TVMazeCacheService: Cleared persistent cache for show ID $showId');
  }

  /// Clean show name for consistency (mirrors TVMazeService._cleanShowName)
  static String _cleanShowName(String showName) {
    String cleaned = showName.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[._-]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\((\d{4})\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+(\d{4})\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'^\d{4}\s+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+\d{4}$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(1080p|720p|480p|2160p|4K|HDRip|BRRip|WEBRip|BluRay|HDTV|DVDRip)\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(AAC|AC3|DTS|FLAC|MP3|OGG)\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(H\.264|H\.265|HEVC|AVC|XVID|DIVX)\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'-[A-Za-z0-9]+$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ss](\d{1,2})[Ee](\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(\d{1,2})[xX](\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(\d{1,2})\.(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ee]pisode\s*(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ee]p\s*(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ee](\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(REPACK|PROPER|INTERNAL|EXTENDED|DIRFIX|NFOFIX|SUBFIX)\b', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\.[a-zA-Z0-9]{3,4}$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  /// Get cache statistics (for debugging/monitoring)
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int totalEntries = 0;
      int expiredEntries = 0;
      final now = DateTime.now();

      for (final key in keys) {
        if (key.startsWith(_timestampPrefix)) {
          totalEntries++;
          final timestamp = prefs.getInt(key);
          if (timestamp != null) {
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            if (now.difference(cacheTime) > _cacheDuration) {
              expiredEntries++;
            }
          }
        }
      }

      return {
        'total_entries': totalEntries,
        'expired_entries': expiredEntries,
        'active_entries': totalEntries - expiredEntries,
        'cache_duration_days': _cacheDuration.inDays,
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }
}
