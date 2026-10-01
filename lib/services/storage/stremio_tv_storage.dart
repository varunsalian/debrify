import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/foundation.dart';

final class StremioTvStorage {
  const StremioTvStorage._();

  // Stremio TV settings
  static const String _stremioTvRotationMinutesKey = 'stremio_tv_rotation_minutes';
  static const String _stremioTvSeriesRotationMinutesKey = 'stremio_tv_series_rotation_minutes';
  static const String _stremioTvAutoRefreshKey = 'stremio_tv_auto_refresh';
  static const String _stremioTvFavoriteChannelsKey = 'stremio_tv_favorite_channels_v1';
  static const String _stremioTvPreferredQualityKey = 'stremio_tv_preferred_quality';
  static const String _stremioTvDebridProviderKey = 'stremio_tv_debrid_provider';
  static const String _stremioTvMaxStartPercentKey = 'stremio_tv_max_start_percent';
  static const String _stremioTvRandomEpisodesKey = 'stremio_tv_random_episodes';
  static const String _stremioTvHideNowPlayingKey = 'stremio_tv_hide_now_playing';
  static const String _stremioTvTorrentsFirstKey = 'stremio_tv_torrents_first';

  // ==========================================================================
  // Stremio TV Settings
  // ==========================================================================

  /// Get the Stremio TV rotation interval in minutes (default: 90)
  static Future<int> getStremioTvRotationMinutes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvRotationMinutesKey) ?? 90;
  }

  /// Save the Stremio TV rotation interval in minutes
  static Future<void> setStremioTvRotationMinutes(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvRotationMinutesKey, value);
  }

  /// Get the Stremio TV series rotation interval in minutes (default: 45)
  static Future<int> getStremioTvSeriesRotationMinutes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvSeriesRotationMinutesKey) ?? 45;
  }

  /// Save the Stremio TV series rotation interval in minutes
  static Future<void> setStremioTvSeriesRotationMinutes(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvSeriesRotationMinutesKey, value);
  }

  /// Get whether Stremio TV picks a random episode each time (default: false)
  static Future<bool> getStremioTvRandomEpisodes() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvRandomEpisodesKey) ?? false;
  }

  /// Save whether Stremio TV picks a random episode each time
  static Future<void> setStremioTvRandomEpisodes(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvRandomEpisodesKey, value);
  }

  /// Get whether Stremio TV auto-refreshes catalogs (default: true)
  static Future<bool> getStremioTvAutoRefresh() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvAutoRefreshKey) ?? true;
  }

  /// Save whether Stremio TV auto-refreshes catalogs
  static Future<void> setStremioTvAutoRefresh(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvAutoRefreshKey, value);
  }

  /// Get whether Stremio TV hides now-playing details (default: false)
  static Future<bool> getStremioTvHideNowPlaying() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvHideNowPlayingKey) ?? false;
  }

  /// Save whether Stremio TV hides now-playing details
  static Future<void> setStremioTvHideNowPlaying(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvHideNowPlayingKey, value);
  }

  static Future<bool> getStremioTvTorrentsFirst() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_stremioTvTorrentsFirstKey) ?? true;
  }

  static Future<void> setStremioTvTorrentsFirst(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_stremioTvTorrentsFirstKey, value);
  }

  /// Get preferred quality for Stremio TV streams (default: 'auto')
  /// Values: 'auto', '720p', '1080p', '2160p'
  static Future<String> getStremioTvPreferredQuality() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_stremioTvPreferredQualityKey) ?? 'auto';
  }

  /// Save preferred quality for Stremio TV streams
  static Future<void> setStremioTvPreferredQuality(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_stremioTvPreferredQualityKey, value);
  }

  /// Get preferred debrid provider for Stremio TV (auto = first available)
  static Future<String> getStremioTvDebridProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_stremioTvDebridProviderKey) ?? 'auto';
  }

  /// Save preferred debrid provider for Stremio TV
  static Future<void> setStremioTvDebridProvider(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_stremioTvDebridProviderKey, value);
  }

  /// Get max start position percent for Stremio TV (0 = always from beginning, -1 = no limit)
  static Future<int> getStremioTvMaxStartPercent() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioTvMaxStartPercentKey) ?? -1;
  }

  /// Save max start position percent for Stremio TV
  static Future<void> setStremioTvMaxStartPercent(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioTvMaxStartPercentKey, value);
  }

  // ==========================================================================
  // Stremio TV Channel Favorites
  // ==========================================================================

  /// Check if a Stremio TV channel is favorited
  static Future<bool> isStremioTvChannelFavorited(String channelId) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelId);
    } catch (e) {
      debugPrint('Error reading Stremio TV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a Stremio TV channel
  static Future<void> setStremioTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (isFavorited) {
      favorites[channelId] = true;
    } else {
      favorites.remove(channelId);
    }

    await prefs.setString(_stremioTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Stremio TV channel IDs
  static Future<Set<String>> getStremioTvFavoriteChannelIds() async {
    final prefs = await ProfilePreferences.instance();
    final favoritesJson = prefs.getString(_stremioTvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading Stremio TV channel favorites: $e');
      return {};
    }
  }

  // ==========================================================================
  // Stremio TV Channel Filters
  // ==========================================================================

  static const String _stremioTvDisabledChannelFiltersKey = 'stremio_tv_disabled_channel_filters_v1';

  /// Get set of disabled channel filter IDs (addon, catalog, or genre level).
  static Future<Set<String>> getStremioTvDisabledFilters() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvDisabledChannelFiltersKey);
    if (json == null) return {};

    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading Stremio TV disabled filters: $e');
      return {};
    }
  }

  /// Save set of disabled channel filter IDs.
  static Future<void> setStremioTvDisabledFilters(Set<String> disabled) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_stremioTvDisabledChannelFiltersKey);
    } else {
      await prefs.setString(
        _stremioTvDisabledChannelFiltersKey,
        jsonEncode(disabled.toList()),
      );
    }
  }
}
