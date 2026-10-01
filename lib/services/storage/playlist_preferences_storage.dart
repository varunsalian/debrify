import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter/foundation.dart';

final class PlaylistPreferencesStorage {
  const PlaylistPreferencesStorage._();
  // Shared within lib/services/storage/.
  static const String playlistViewModesKey = 'playlist_view_modes_v1';
  // Shared within lib/services/storage/.
  static const String playlistFavoritesKey = 'playlist_favorites_v1';

  /// Get saved view mode for a playlist item
  /// Returns null if no view mode has been saved for this item
  static Future<String?> getPlaylistItemViewMode(
    Map<String, dynamic> item,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(playlistViewModesKey);

    if (viewModesJson == null) return null;

    try {
      final viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      final dedupeKey = PlaylistStorage.computePlaylistDedupeKey(item);
      return viewModes[dedupeKey] as String?;
    } catch (e) {
      debugPrint('Error reading playlist view modes: $e');
      return null;
    }
  }

  /// Save view mode for a playlist item
  static Future<void> savePlaylistItemViewMode(
    Map<String, dynamic> item,
    String viewMode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(playlistViewModesKey);

    Map<String, dynamic> viewModes = {};
    if (viewModesJson != null) {
      try {
        viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist view modes: $e');
      }
    }

    final dedupeKey = PlaylistStorage.computePlaylistDedupeKey(item);
    viewModes[dedupeKey] = viewMode;

    await prefs.setString(playlistViewModesKey, jsonEncode(viewModes));
  }

  /// Check if a playlist item is favorited
  static Future<bool> isPlaylistItemFavorited(Map<String, dynamic> item) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(playlistFavoritesKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      final dedupeKey = PlaylistStorage.computePlaylistDedupeKey(item);
      return favorites[dedupeKey] == true;
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a playlist item
  static Future<void> setPlaylistItemFavorited(
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(playlistFavoritesKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist favorites: $e');
      }
    }

    final dedupeKey = PlaylistStorage.computePlaylistDedupeKey(item);
    if (isFavorited) {
      favorites[dedupeKey] = true;
    } else {
      if (!favorites.containsKey(dedupeKey)) return;
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.playlistFavorite(dedupeKey),
      });
      favorites.remove(dedupeKey);
    }

    await prefs.setString(playlistFavoritesKey, jsonEncode(favorites));
  }

  /// Get all favorite dedupe keys
  static Future<Set<String>> getPlaylistFavoriteKeys() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(playlistFavoritesKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return {};
    }
  }
}
