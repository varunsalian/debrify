import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/playlist_identity_storage.dart';
import 'package:flutter/foundation.dart';

final class PlaylistPosterStorage {
  const PlaylistPosterStorage._();

  // Playlist poster override storage key
  // Shared within lib/services/storage/.
  static const String playlistPosterOverridesKey = 'playlist_poster_overrides_v1';

  // Playlist Poster Override Methods

  /// Save a poster URL override for a playlist item
  /// This ensures the poster persists across app restarts
  static Future<void> savePlaylistPosterOverride({
    required Map<String, dynamic> playlistItem,
    required String posterUrl,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(playlistPosterOverridesKey);

    Map<String, dynamic> overrides = {};
    if (overridesJson != null) {
      try {
        overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist poster overrides: $e');
      }
    }

    final key = PlaylistIdentityStorage.getPlaylistItemUniqueKeyInternal(playlistItem);
    overrides[key] = {
      'posterUrl': posterUrl,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(playlistPosterOverridesKey, jsonEncode(overrides));
    debugPrint('✅ Saved poster override for $key -> $posterUrl');
  }

  /// Get poster URL override for a playlist item
  /// Returns null if no override exists
  static Future<String?> getPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(playlistPosterOverridesKey);

    if (overridesJson == null) return null;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = PlaylistIdentityStorage.getPlaylistItemUniqueKeyInternal(playlistItem);
      final override = overrides[key];

      if (override != null && override is Map<String, dynamic>) {
        final posterUrl = override['posterUrl'] as String?;
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return posterUrl;
        }
      }
    } catch (e) {
      debugPrint('Error reading playlist poster override: $e');
    }

    return null;
  }

  /// Get all poster overrides as a map of item unique key → poster URL.
  /// Reads and parses the overrides blob once for batch lookups.
  static Future<Map<String, String>> getAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(playlistPosterOverridesKey);
    if (overridesJson == null) return {};

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final result = <String, String>{};
      for (final entry in overrides.entries) {
        if (entry.value is Map<String, dynamic>) {
          final posterUrl = (entry.value as Map<String, dynamic>)['posterUrl'] as String?;
          if (posterUrl != null && posterUrl.isNotEmpty) {
            result[entry.key] = posterUrl;
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading playlist poster overrides: $e');
      return {};
    }
  }

  /// Clear poster URL override for a playlist item
  static Future<void> clearPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(playlistPosterOverridesKey);

    if (overridesJson == null) return;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = PlaylistIdentityStorage.getPlaylistItemUniqueKeyInternal(playlistItem);

      if (overrides.containsKey(key)) {
        overrides.remove(key);
        await prefs.setString(
          playlistPosterOverridesKey,
          jsonEncode(overrides),
        );
        debugPrint('✅ Cleared poster override for $key');
      }
    } catch (e) {
      debugPrint('Error clearing playlist poster override: $e');
    }
  }

  /// Clear all playlist poster overrides
  static Future<void> clearAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(playlistPosterOverridesKey);
    debugPrint('✅ Cleared all playlist poster overrides');
  }
}
