import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/playlist_identity_storage.dart';
import 'package:flutter/foundation.dart';

final class TvMazeMappingStorage {
  const TvMazeMappingStorage._();

  // TVMaze series mapping keys
  // Shared within lib/services/storage/.
  static const String tvMazeSeriesMappingKey = 'tvmaze_series_mappings';

  /// Save a TVMaze series mapping for a playlist item
  static Future<void> saveTVMazeSeriesMapping({
    required Map<String, dynamic> playlistItem,
    required int tvmazeShowId,
    required String showName,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(tvMazeSeriesMappingKey);

    Map<String, dynamic> mappings = {};
    if (mappingsJson != null) {
      try {
        mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing TVMaze series mappings: $e');
      }
    }

    final key = PlaylistIdentityStorage.getPlaylistItemUniqueKeyInternal(playlistItem);
    mappings[key] = {
      'tvmazeShowId': tvmazeShowId,
      'showName': showName,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(tvMazeSeriesMappingKey, jsonEncode(mappings));
    debugPrint(
      '✅ Saved TVMaze mapping for $key -> Show ID: $tvmazeShowId ($showName)',
    );
  }

  /// Get TVMaze series mapping for a playlist item
  static Future<Map<String, dynamic>?> getTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(tvMazeSeriesMappingKey);

    if (mappingsJson == null) return null;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = PlaylistIdentityStorage.getPlaylistItemUniqueKeyInternal(playlistItem);
      final mapping = mappings[key];

      if (mapping != null && mapping is Map<String, dynamic>) {
        debugPrint(
          '✅ Found TVMaze mapping for $key -> Show ID: ${mapping['tvmazeShowId']} (${mapping['showName']})',
        );
        return mapping;
      }
    } catch (e) {
      debugPrint('Error reading TVMaze series mappings: $e');
    }

    return null;
  }

  /// Clear TVMaze series mapping for a playlist item
  static Future<void> clearTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(tvMazeSeriesMappingKey);

    if (mappingsJson == null) return;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = PlaylistIdentityStorage.getPlaylistItemUniqueKeyInternal(playlistItem);

      if (mappings.containsKey(key)) {
        mappings.remove(key);
        await prefs.setString(tvMazeSeriesMappingKey, jsonEncode(mappings));
        debugPrint('✅ Cleared TVMaze mapping for $key');
      }
    } catch (e) {
      debugPrint('Error clearing TVMaze series mapping: $e');
    }
  }

  /// Clear all TVMaze series mappings
  static Future<void> clearAllTVMazeSeriesMappings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(tvMazeSeriesMappingKey);
    debugPrint('✅ Cleared all TVMaze series mappings');
  }
}
