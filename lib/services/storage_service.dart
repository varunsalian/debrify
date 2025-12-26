import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'debrid_service.dart';

class StorageService {
  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _rdEndpointKey = 'real_debrid_endpoint';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  static const String _torboxApiKey = 'torbox_api_key';
  static const String _torboxCacheCheckPref =
      'torbox_check_cache_before_search';
  static const String _realDebridIntegrationEnabledKey =
      'real_debrid_integration_enabled';
  static const String _realDebridHiddenFromNavKey =
      'real_debrid_hidden_from_nav';
  static const String _torboxIntegrationEnabledKey =
      'torbox_integration_enabled';
  static const String _torboxHiddenFromNavKey =
      'torbox_hidden_from_nav';
  static const String _pikpakHiddenFromNavKey =
      'pikpak_hidden_from_nav';
  static const String _postTorrentActionKey = 'post_torrent_action';
  static const String _torboxPostTorrentActionKey =
      'torbox_post_torrent_action';
  static const String _pikpakPostTorrentActionKey =
      'pikpak_post_torrent_action';
  static const String _batteryOptStatusKey =
      'battery_opt_status_v1'; // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _playbackStateKey = 'playback_state_v1';
  static const String _defaultTorrentsCsvEnabledKey =
      'default_torrents_csv_enabled';
  static const String _defaultPirateBayEnabledKey =
      'default_pirate_bay_enabled';
  static const String _defaultYtsEnabledKey = 'default_yts_enabled';
  static const String _defaultSolidTorrentsEnabledKey =
      'default_solid_torrents_enabled';
  static const String _maxTorrentsCsvResultsKey = 'max_torrents_csv_results';
  static const String _maxSolidTorrentsResultsKey =
      'max_solid_torrents_results';
  static const String _debrifyTvStartRandomKey = 'debrify_tv_start_random';
  static const String _debrifyTvHideSeekbarKey = 'debrify_tv_hide_seekbar';
  static const String _debrifyTvShowChannelNameKey =
      'debrify_tv_show_watermark';
  static const String _debrifyTvShowVideoTitleKey =
      'debrify_tv_show_video_title';
  static const String _debrifyTvHideOptionsKey = 'debrify_tv_hide_options';
  static const String _debrifyTvHideBackButtonKey =
      'debrify_tv_hide_back_button';
  static const String _debrifyTvAvoidNsfwKey = 'debrify_tv_avoid_nsfw';
  static const String _debrifyTvProviderKey = 'debrify_tv_provider';
  static const String _debrifyTvRandomStartPercentKey =
      'debrify_tv_random_start_percent';
  static const String _debrifyTvChannelsKey = 'debrify_tv_channels';

  // Startup settings
  static const String _startupAutoLaunchEnabledKey =
      'startup_auto_launch_enabled';
  static const String _startupChannelIdKey = 'startup_channel_id';
  static const String _startupModeKey = 'startup_mode'; // 'channel' or 'playlist'
  static const String _startupPlaylistItemIdKey = 'startup_playlist_item_id';

  // PikPak API settings
  static const String _pikpakEnabledKey = 'pikpak_enabled';
  static const String _pikpakEmailKey = 'pikpak_email';
  static const String _pikpakPasswordKey = 'pikpak_password';
  static const String _pikpakAccessTokenKey = 'pikpak_access_token';
  static const String _pikpakRefreshTokenKey = 'pikpak_refresh_token';
  static const String _pikpakDeviceIdKey = 'pikpak_device_id';
  static const String _pikpakCaptchaTokenKey = 'pikpak_captcha_token';
  static const String _pikpakUserIdKey = 'pikpak_user_id';
  static const String _pikpakShowVideosOnlyKey = 'pikpak_show_videos_only';
  static const String _pikpakIgnoreSmallVideosKey =
      'pikpak_ignore_small_videos';
  static const String _pikpakRestrictedFolderIdKey =
      'pikpak_restricted_folder_id';
  static const String _pikpakRestrictedFolderNameKey =
      'pikpak_restricted_folder_name';
  static const String _pikpakTorrentsFolderIdKey =
      'pikpak_torrents_folder_id';
  static const String _pikpakTvFolderIdKey = 'pikpak_tv_folder_id';

  // TVMaze series mapping keys
  static const String _tvMazeSeriesMappingKey = 'tvmaze_series_mappings';

  // Playlist poster override storage key
  static const String _playlistPosterOverridesKey = 'playlist_poster_overrides_v1';

  // Debrify TV search engine settings
  static const String _debrifyTvUseTorrentsCsvKey =
      'debrify_tv_use_torrents_csv';
  static const String _debrifyTvUsePirateBayKey = 'debrify_tv_use_pirate_bay';
  static const String _debrifyTvUseYtsKey = 'debrify_tv_use_yts';
  static const String _debrifyTvUseSolidTorrentsKey =
      'debrify_tv_use_solid_torrents';

  // Channel limits - Small (< threshold keywords)
  static const String _debrifyTvChannelSmallTorrentsCsvMaxKey =
      'debrify_tv_channel_small_torrents_csv_max';
  static const String _debrifyTvChannelSmallSolidTorrentsMaxKey =
      'debrify_tv_channel_small_solid_torrents_max';
  static const String _debrifyTvChannelSmallYtsMaxKey =
      'debrify_tv_channel_small_yts_max';

  // Channel limits - Large (>= threshold keywords)
  static const String _debrifyTvChannelLargeTorrentsCsvMaxKey =
      'debrify_tv_channel_large_torrents_csv_max';
  static const String _debrifyTvChannelLargeSolidTorrentsMaxKey =
      'debrify_tv_channel_large_solid_torrents_max';
  static const String _debrifyTvChannelLargeYtsMaxKey =
      'debrify_tv_channel_large_yts_max';

  // Quick Play limits
  static const String _debrifyTvQuickPlayTorrentsCsvMaxKey =
      'debrify_tv_quick_play_torrents_csv_max';
  static const String _debrifyTvQuickPlaySolidTorrentsMaxKey =
      'debrify_tv_quick_play_solid_torrents_max';
  static const String _debrifyTvQuickPlayYtsMaxKey =
      'debrify_tv_quick_play_yts_max';
  static const String _debrifyTvQuickPlayMaxKeywordsKey =
      'debrify_tv_quick_play_max_keywords';

  // General settings
  static const String _debrifyTvChannelBatchSizeKey =
      'debrify_tv_channel_batch_size';
  static const String _debrifyTvKeywordThresholdKey =
      'debrify_tv_keyword_threshold';
  static const String _debrifyTvMinTorrentsPerKeywordKey =
      'debrify_tv_min_torrents_per_keyword';

  static const String _playlistKey = 'user_playlist_v1';
  static const String _playlistViewModesKey = 'playlist_view_modes_v1';
  static const String _onboardingCompleteKey = 'initial_setup_complete_v1';

  // Torrent Search History
  static const String _torrentSearchHistoryKey = 'torrent_search_history_v1';
  static const String _torrentSearchHistoryEnabledKey = 'torrent_search_history_enabled';
  static const int _debrifyTvRandomStartPercentDefault = 20;
  static const int _debrifyTvRandomStartPercentMin = 10;
  static const int _debrifyTvRandomStartPercentMax = 90;

  // Note: Plain text storage is fine for API key since they're stored locally on user's device
  // and can be easily regenerated if compromised
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

  // Real-Debrid endpoint preference (for fallback to backup endpoint)
  static Future<String> getRdEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to primary endpoint
    return prefs.getString(_rdEndpointKey) ?? 'https://api.real-debrid.com/rest/1.0';
  }

  static Future<void> saveRdEndpoint(String endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rdEndpointKey, endpoint);
  }

  static Future<void> deleteRdEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rdEndpointKey);
  }

  // Torbox API key helpers
  static Future<String?> getTorboxApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_torboxApiKey);
  }

  static Future<void> saveTorboxApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_torboxApiKey, apiKey);
  }

  static Future<void> deleteTorboxApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_torboxApiKey);
  }

  static Future<bool> getTorboxCacheCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_torboxCacheCheckPref) ?? false;
  }

  static Future<void> setTorboxCacheCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_torboxCacheCheckPref, enabled);
  }

  static Future<bool> getRealDebridIntegrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_realDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setRealDebridIntegrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_realDebridIntegrationEnabledKey, enabled);
  }

  static Future<bool> getRealDebridHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_realDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setRealDebridHiddenFromNav(bool hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_realDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearRealDebridHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_realDebridHiddenFromNavKey);
  }

  static Future<bool> getTorboxIntegrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_torboxIntegrationEnabledKey) ?? true;
  }

  static Future<void> setTorboxIntegrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_torboxIntegrationEnabledKey, enabled);
  }

  static Future<bool> getTorboxHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_torboxHiddenFromNavKey) ?? false;
  }

  static Future<void> setTorboxHiddenFromNav(bool hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_torboxHiddenFromNavKey, hidden);
  }

  static Future<void> clearTorboxHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_torboxHiddenFromNavKey);
  }

  static Future<bool> isInitialSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  static Future<void> setInitialSetupComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, value);
  }

  // File Selection methods
  static Future<String> getFileSelection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fileSelectionKey) ??
        'smart'; // Default to smart selection
  }

  static Future<void> saveFileSelection(String selection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileSelectionKey, selection);
  }

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_postTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePostTorrentAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postTorrentActionKey, action);
  }

  // TorBox post-torrent action methods
  static Future<String> getTorboxPostTorrentAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_torboxPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveTorboxPostTorrentAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_torboxPostTorrentActionKey, action);
  }

  // PikPak post-torrent action methods
  static Future<String> getPikPakPostTorrentAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePikPakPostTorrentAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakPostTorrentActionKey, action);
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

  // Download settings - Fixed to 1 parallel download
  static Future<int> getMaxParallelDownloads() async {
    return 1; // Always return 1 for single download at a time
  }

  static Future<void> setMaxParallelDownloads(int value) async {
    // No-op: parallel downloads are fixed to 1
  }

  // Default search engine settings
  static Future<bool> getDefaultTorrentsCsvEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultTorrentsCsvEnabledKey) ??
        true; // Default to enabled
  }

  static Future<void> setDefaultTorrentsCsvEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultTorrentsCsvEnabledKey, enabled);
  }

  static Future<bool> getDefaultPirateBayEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultPirateBayEnabledKey) ??
        true; // Default to enabled
  }

  static Future<void> setDefaultPirateBayEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultPirateBayEnabledKey, enabled);
  }

  static Future<bool> getDefaultYtsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultYtsEnabledKey) ?? true;
  }

  static Future<void> setDefaultYtsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultYtsEnabledKey, enabled);
  }

  static Future<bool> getDefaultSolidTorrentsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultSolidTorrentsEnabledKey) ?? true;
  }

  static Future<void> setDefaultSolidTorrentsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultSolidTorrentsEnabledKey, enabled);
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

  static Future<int> getMaxSolidTorrentsResults() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxSolidTorrentsResultsKey) ?? 100; // Default to 100
  }

  static Future<void> setMaxSolidTorrentsResults(int maxResults) async {
    final prefs = await SharedPreferences.getInstance();
    // Clamp between 25 and 500
    final clampedValue = maxResults.clamp(25, 500);
    await prefs.setInt(_maxSolidTorrentsResultsKey, clampedValue);
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
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {'type': 'series', 'title': seriesTitle, 'seasons': {}};
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

    debugPrint(
      'StorageService: saveSeriesPlaybackState title="$seriesTitle" S${season}E$episode position=${positionMs}ms duration=${durationMs}ms',
    );

    await _savePlaybackStateMap(map);
  }

  /// Mark an episode as finished (watched completely)
  static Future<void> markEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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

    debugPrint(
      'StorageService: markEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
    );

    await _savePlaybackStateMap(map);
  }

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    return videoData as Map<String, dynamic>;
  }

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
          lastEpisode = {'season': season, 'episode': episode, ...episodeData};
        }
      }
    }

    if (lastEpisode != null) {
      debugPrint(
        'StorageService: getLastPlayedEpisode found S${lastEpisode['season']}E${lastEpisode['episode']} for "$seriesTitle"',
      );
    } else {
      debugPrint(
        'StorageService: getLastPlayedEpisode no episodes for "$seriesTitle"',
      );
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

  /// Clear all playback-related data (series and video states, track prefs, legacy resume)
  static Future<void> clearAllPlaybackData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playbackStateKey);
    await prefs.remove(_videoResumeKey);
    debugPrint('StorageService: cleared playback state and video resume data');
  }

  // Internal helper for services needing shared prefs quickly
  static Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
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

  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry,
  ) async {
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
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

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
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {'type': 'video', 'title': videoTitle, 'trackPreferences': {}};
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
    final key =
        'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    final trackPreferences = videoData['trackPreferences'];
    if (trackPreferences == null) return null;

    return trackPreferences as Map<String, dynamic>;
  }

  // Debrify TV settings methods
  static Future<String> getDebrifyTvProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_debrifyTvProviderKey) ?? 'real_debrid';
  }

  static Future<void> saveDebrifyTvProvider(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debrifyTvProviderKey, value);
  }

  static Future<bool> hasDebrifyTvProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_debrifyTvProviderKey);
  }

  static Future<bool> getDebrifyTvStartRandom() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvStartRandomKey) ?? true;
  }

  static Future<void> saveDebrifyTvStartRandom(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvStartRandomKey, value);
  }

  static int _normalizeDebrifyTvRandomStartPercent(int? value) {
    final candidate = value ?? _debrifyTvRandomStartPercentDefault;
    if (candidate < _debrifyTvRandomStartPercentMin) {
      return _debrifyTvRandomStartPercentMin;
    }
    if (candidate > _debrifyTvRandomStartPercentMax) {
      return _debrifyTvRandomStartPercentMax;
    }
    return candidate;
  }

  static Future<int> getDebrifyTvRandomStartPercent() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_debrifyTvRandomStartPercentKey);
    return _normalizeDebrifyTvRandomStartPercent(stored);
  }

  static Future<void> saveDebrifyTvRandomStartPercent(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeDebrifyTvRandomStartPercent(value);
    await prefs.setInt(_debrifyTvRandomStartPercentKey, normalized);
  }

  static Future<bool> getDebrifyTvHideSeekbar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvHideSeekbarKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideSeekbar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvHideSeekbarKey, value);
  }

  static Future<bool> getDebrifyTvShowChannelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvShowChannelNameKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowChannelName(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvShowChannelNameKey, value);
  }

  static Future<bool> getDebrifyTvShowVideoTitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvShowVideoTitleKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowVideoTitle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvShowVideoTitleKey, value);
  }

  static Future<bool> getDebrifyTvHideOptions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvHideOptionsKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideOptions(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvHideOptionsKey, value);
  }

  static Future<bool> getDebrifyTvHideBackButton() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvHideBackButtonKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideBackButton(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvHideBackButtonKey, value);
  }

  static Future<bool> getDebrifyTvAvoidNsfw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvAvoidNsfwKey) ?? true; // Default enabled
  }

  static Future<void> saveDebrifyTvAvoidNsfw(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvAvoidNsfwKey, value);
  }

  static Future<List<Map<String, dynamic>>> getDebrifyTvChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_debrifyTvChannelsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .where((entry) => entry is Map)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> saveDebrifyTvChannels(
    List<Map<String, dynamic>> channels,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debrifyTvChannelsKey, jsonEncode(channels));
  }

  // Playlist storage (local-only MVP)
  static Future<List<Map<String, dynamic>>> getPlaylistItemsRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> savePlaylistItemsRaw(
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistKey, jsonEncode(items));
  }

  static String computePlaylistDedupeKey(Map<String, dynamic> item) {
    final providerRaw = (item['provider'] as String?) ?? 'realdebrid';
    final provider = providerRaw.toLowerCase();
    final String? torrentHash = item['torrent_hash'] as String?;
    if (torrentHash != null && torrentHash.isNotEmpty) {
      return '$provider|hash:${torrentHash.toLowerCase()}';
    }
    final dynamic torboxIdRaw = item['torboxTorrentId'];
    if (torboxIdRaw != null) {
      final String torboxId = torboxIdRaw.toString();
      final dynamic singleFileId = item['torboxFileId'];
      if (singleFileId != null) {
        final fileKey = 'torbox:${torboxId}:file:${singleFileId.toString()}';
        return '$provider|${fileKey.toLowerCase()}';
      }
      final dynamic multiFileIds = item['torboxFileIds'];
      if (multiFileIds is List && multiFileIds.isNotEmpty) {
        final joined = multiFileIds.map((e) => e.toString()).join(',');
        final filesKey = 'torbox:${torboxId}:files:$joined';
        return '$provider|${filesKey.toLowerCase()}';
      }
      return '$provider|torbox:${torboxId.toLowerCase()}';
    }
    // PikPak file ID based key
    final dynamic pikpakFileId = item['pikpakFileId'];
    if (pikpakFileId != null) {
      return '$provider|pikpak:file:${pikpakFileId.toString().toLowerCase()}';
    }
    final dynamic pikpakFileIds = item['pikpakFileIds'];
    if (pikpakFileIds is List && pikpakFileIds.isNotEmpty) {
      final joined = pikpakFileIds.map((e) => e.toString()).join(',');
      return '$provider|pikpak:files:${joined.toLowerCase()}';
    }
    final String? rdId = (item['rdTorrentId'] as String?);
    if (rdId != null && rdId.isNotEmpty) {
      return '$provider|rd:${rdId.toLowerCase()}';
    }
    final String source =
        (item['restrictedLink'] as String?)?.trim() ??
        (item['url'] as String?)?.trim() ??
        '';
    final String title = (item['title'] as String?)?.trim() ?? '';
    final legacyKey = '${source}|${title}'.toLowerCase();
    return '$provider|$legacyKey';
  }

  /// Add a new playlist item if it does not already exist.
  /// Expected item shape (MVP): { url, title, restrictedLink, rdTorrentId }
  /// Returns true if inserted, false if duplicate.
  static Future<bool> addPlaylistItemRaw(Map<String, dynamic> item) async {
    final items = await getPlaylistItemsRaw();
    final initialKey = computePlaylistDedupeKey(item);
    debugPrint('Playlist dedupe: initialKey=$initialKey');
    for (final existing in items) {
      final existingKey = computePlaylistDedupeKey(existing);
      final existingProvider = (existing['provider'] as String?) ?? 'unknown';
      debugPrint(
        'Playlist dedupe: existingKey=$existingKey provider=$existingProvider',
      );
    }
    final initialExists = items.any(
      (entry) => computePlaylistDedupeKey(entry) == initialKey,
    );
    if (initialExists) {
      debugPrint('Playlist dedupe: blocked by initial key match');
      return false;
    }

    final enriched = Map<String, dynamic>.from(item);
    enriched['addedAt'] = DateTime.now().millisecondsSinceEpoch;
    enriched['provider'] = ((item['provider'] as String?)?.isNotEmpty ?? false)
        ? item['provider']
        : 'realdebrid';

    final bool isTorbox =
        (enriched['provider'] as String?)?.toLowerCase() == 'torbox';

    // Fetch and add torrent hash if we have a torrent ID
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? apiKey = await getApiKey();

    if (!isTorbox &&
        rdTorrentId != null &&
        rdTorrentId.isNotEmpty &&
        apiKey != null &&
        apiKey.isNotEmpty) {
      try {
        // Import DebridService here to avoid circular dependency
        final response = await http.get(
          Uri.parse(
            'https://api.real-debrid.com/rest/1.0/torrents/info/$rdTorrentId',
          ),
          headers: {'Authorization': 'Bearer $apiKey'},
        );

        if (response.statusCode == 200) {
          final torrentInfo = json.decode(response.body);
          final String? hash = torrentInfo['hash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            enriched['torrent_hash'] = hash;
            print(
              '✅ Torrent hash fetched and stored: $hash for torrent ID: $rdTorrentId',
            );
          } else {
            print(
              '⚠️ No hash found in torrent info for torrent ID: $rdTorrentId',
            );
          }
        } else {
          print(
            '❌ Failed to fetch torrent info. Status code: ${response.statusCode} for torrent ID: $rdTorrentId',
          );
        }
      } catch (e) {
        print(
          '❌ Error fetching torrent hash for torrent ID: $rdTorrentId - $e',
        );
        // Silently continue without hash if fetch fails
        // This ensures playlist addition doesn't fail due to hash fetch issues
      }
    } else {
      print('ℹ️ Skipping torrent hash fetch - missing rdTorrentId or API key');
    }

    // Log what's being saved to database
    print('📝 Adding playlist item to database:');
    print('   Title: ${enriched['title']}');
    print('   Kind: ${enriched['kind']}');
    print('   rdTorrentId: ${enriched['rdTorrentId']}');
    print('   torrent_hash: ${enriched['torrent_hash'] ?? 'null'}');
    print('   restrictedLink: ${enriched['restrictedLink'] ?? 'null'}');
    print(
      '   addedAt: ${DateTime.fromMillisecondsSinceEpoch(enriched['addedAt']).toIso8601String()}',
    );

    final finalKey = computePlaylistDedupeKey(enriched);
    if (finalKey != initialKey) {
      final finalExists = items.any(
        (entry) => computePlaylistDedupeKey(entry) == finalKey,
      );
      if (finalExists) {
        debugPrint('Playlist dedupe: blocked by final key match ($finalKey)');
        return false;
      }
    }

    items.add(enriched);
    await savePlaylistItemsRaw(items);

    return true;
  }

  static Future<void> removePlaylistItemByKey(String dedupeKey) async {
    final items = await getPlaylistItemsRaw();
    items.removeWhere((e) => computePlaylistDedupeKey(e) == dedupeKey);
    await savePlaylistItemsRaw(items);
  }

  static Future<void> clearPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playlistKey);
  }

  /// Update an existing playlist item with poster URL
  /// Supports both RealDebrid (rdTorrentId) and PikPak (pikpakCollectionId)
  static Future<bool> updatePlaylistItemPoster(
    String posterUrl, {
    String? rdTorrentId,
    String? pikpakCollectionId,
  }) async {
    final items = await getPlaylistItemsRaw();
    int itemIndex = -1;

    // Search by rdTorrentId if provided (RealDebrid)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
    }

    // Search by pikpakCollectionId if provided and not found yet (PikPak)
    if (itemIndex == -1 &&
        pikpakCollectionId != null &&
        pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        // Check single PikPak files
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) {
          return true;
        }

        // Check PikPak collections (first file ID in array)
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          final firstId = pikpakFileIds[0].toString();
          if (firstId == pikpakCollectionId) {
            return true;
          }
        }

        return false;
      });
    }

    if (itemIndex == -1) return false;

    items[itemIndex]['posterUrl'] = posterUrl;
    await savePlaylistItemsRaw(items);
    return true;
  }

  /// Get saved view mode for a playlist item
  /// Returns null if no view mode has been saved for this item
  static Future<String?> getPlaylistItemViewMode(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    if (viewModesJson == null) return null;

    try {
      final viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
      return viewModes[dedupeKey] as String?;
    } catch (e) {
      print('Error reading playlist view modes: $e');
      return null;
    }
  }

  /// Save view mode for a playlist item
  static Future<void> savePlaylistItemViewMode(Map<String, dynamic> item, String viewMode) async {
    final prefs = await SharedPreferences.getInstance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    Map<String, dynamic> viewModes = {};
    if (viewModesJson != null) {
      try {
        viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      } catch (e) {
        print('Error parsing playlist view modes: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    viewModes[dedupeKey] = viewMode;

    await prefs.setString(_playlistViewModesKey, jsonEncode(viewModes));
  }

  // Debrify TV Search Engine Settings
  static Future<bool> getDebrifyTvUseTorrentsCsv() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvUseTorrentsCsvKey) ?? true;
  }

  static Future<void> setDebrifyTvUseTorrentsCsv(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvUseTorrentsCsvKey, value);
  }

  static Future<bool> getDebrifyTvUsePirateBay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvUsePirateBayKey) ?? true;
  }

  static Future<void> setDebrifyTvUsePirateBay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvUsePirateBayKey, value);
  }

  static Future<bool> getDebrifyTvUseYts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvUseYtsKey) ?? false;
  }

  static Future<void> setDebrifyTvUseYts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvUseYtsKey, value);
  }

  static Future<bool> getDebrifyTvUseSolidTorrents() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_debrifyTvUseSolidTorrentsKey) ?? false;
  }

  static Future<void> setDebrifyTvUseSolidTorrents(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debrifyTvUseSolidTorrentsKey, value);
  }

  // Channel limits - Small
  static Future<int> getDebrifyTvChannelSmallTorrentsCsvMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelSmallTorrentsCsvMaxKey) ?? 100;
  }

  static Future<void> setDebrifyTvChannelSmallTorrentsCsvMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _debrifyTvChannelSmallTorrentsCsvMaxKey,
      value.clamp(25, 500),
    );
  }

  static Future<int> getDebrifyTvChannelSmallSolidTorrentsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelSmallSolidTorrentsMaxKey) ?? 100;
  }

  static Future<void> setDebrifyTvChannelSmallSolidTorrentsMax(
    int value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _debrifyTvChannelSmallSolidTorrentsMaxKey,
      value.clamp(100, 500),
    );
  }

  static Future<int> getDebrifyTvChannelSmallYtsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelSmallYtsMaxKey) ?? 50;
  }

  static Future<void> setDebrifyTvChannelSmallYtsMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvChannelSmallYtsMaxKey, value);
  }

  // Channel limits - Large
  static Future<int> getDebrifyTvChannelLargeTorrentsCsvMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelLargeTorrentsCsvMaxKey) ?? 25;
  }

  static Future<void> setDebrifyTvChannelLargeTorrentsCsvMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _debrifyTvChannelLargeTorrentsCsvMaxKey,
      value.clamp(25, 100),
    );
  }

  static Future<int> getDebrifyTvChannelLargeSolidTorrentsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelLargeSolidTorrentsMaxKey) ?? 100;
  }

  static Future<void> setDebrifyTvChannelLargeSolidTorrentsMax(
    int value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _debrifyTvChannelLargeSolidTorrentsMaxKey,
      value.clamp(100, 200),
    );
  }

  static Future<int> getDebrifyTvChannelLargeYtsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelLargeYtsMaxKey) ?? 50;
  }

  static Future<void> setDebrifyTvChannelLargeYtsMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvChannelLargeYtsMaxKey, value);
  }

  // Quick Play limits
  static Future<int> getDebrifyTvQuickPlayTorrentsCsvMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvQuickPlayTorrentsCsvMaxKey) ?? 500;
  }

  static Future<void> setDebrifyTvQuickPlayTorrentsCsvMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _debrifyTvQuickPlayTorrentsCsvMaxKey,
      value.clamp(100, 500),
    );
  }

  static Future<int> getDebrifyTvQuickPlaySolidTorrentsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvQuickPlaySolidTorrentsMaxKey) ?? 200;
  }

  static Future<void> setDebrifyTvQuickPlaySolidTorrentsMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _debrifyTvQuickPlaySolidTorrentsMaxKey,
      value.clamp(100, 500),
    );
  }

  static Future<int> getDebrifyTvQuickPlayYtsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvQuickPlayYtsMaxKey) ?? 50;
  }

  static Future<void> setDebrifyTvQuickPlayYtsMax(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvQuickPlayYtsMaxKey, value);
  }

  static Future<int> getDebrifyTvQuickPlayMaxKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvQuickPlayMaxKeywordsKey) ?? 5;
  }

  static Future<void> setDebrifyTvQuickPlayMaxKeywords(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvQuickPlayMaxKeywordsKey, value.clamp(1, 20));
  }

  // General settings
  static Future<int> getDebrifyTvChannelBatchSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvChannelBatchSizeKey) ?? 4;
  }

  static Future<void> setDebrifyTvChannelBatchSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvChannelBatchSizeKey, value.clamp(1, 10));
  }

  static Future<int> getDebrifyTvKeywordThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvKeywordThresholdKey) ?? 10;
  }

  static Future<void> setDebrifyTvKeywordThreshold(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvKeywordThresholdKey, value.clamp(1, 50));
  }

  static Future<int> getDebrifyTvMinTorrentsPerKeyword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_debrifyTvMinTorrentsPerKeywordKey) ?? 5;
  }

  static Future<void> setDebrifyTvMinTorrentsPerKeyword(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_debrifyTvMinTorrentsPerKeywordKey, value.clamp(1, 50));
  }

  // Startup Settings
  static Future<bool> getStartupAutoLaunchEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_startupAutoLaunchEnabledKey) ?? false;
  }

  static Future<void> setStartupAutoLaunchEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startupAutoLaunchEnabledKey, value);
  }

  static Future<String?> getStartupChannelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_startupChannelIdKey);
  }

  static Future<void> setStartupChannelId(String? channelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (channelId == null) {
      await prefs.remove(_startupChannelIdKey);
    } else {
      await prefs.setString(_startupChannelIdKey, channelId);
    }
  }

  static Future<String> getStartupMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_startupModeKey) ?? 'channel'; // Default to channel for backward compatibility
  }

  static Future<void> setStartupMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_startupModeKey, mode);
  }

  static Future<String?> getStartupPlaylistItemId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_startupPlaylistItemIdKey);
  }

  static Future<void> setStartupPlaylistItemId(String? itemId) async {
    final prefs = await SharedPreferences.getInstance();
    if (itemId == null) {
      await prefs.remove(_startupPlaylistItemIdKey);
    } else {
      await prefs.setString(_startupPlaylistItemIdKey, itemId);
    }
  }

  // PikPak API Settings
  static Future<bool> getPikPakEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pikpakEnabledKey) ?? false;
  }

  static Future<void> setPikPakEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pikpakEnabledKey, value);
  }

  static Future<String?> getPikPakEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakEmailKey);
  }

  static Future<void> setPikPakEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakEmailKey, email);
  }

  static Future<String?> getPikPakPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakPasswordKey);
  }

  static Future<void> setPikPakPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakPasswordKey, password);
  }

  static Future<String?> getPikPakAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakAccessTokenKey);
  }

  static Future<void> setPikPakAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakAccessTokenKey, token);
  }

  static Future<String?> getPikPakRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakRefreshTokenKey);
  }

  static Future<void> setPikPakRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakRefreshTokenKey, token);
  }

  static Future<void> clearPikPakAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pikpakEmailKey);
    await prefs.remove(_pikpakPasswordKey);
    await prefs.remove(_pikpakAccessTokenKey);
    await prefs.remove(_pikpakRefreshTokenKey);
    await prefs.remove(_pikpakDeviceIdKey);
    await prefs.remove(_pikpakCaptchaTokenKey);
    await prefs.remove(_pikpakUserIdKey);
    await prefs.setBool(_pikpakEnabledKey, false);

    // Also clear restricted folder settings and cached subfolder IDs
    await clearPikPakRestrictedFolder();
    await clearPikPakSubfolderCaches();
    await clearPikPakHiddenFromNav();
  }

  // PikPak Device ID and Captcha Token
  static Future<void> setPikPakDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakDeviceIdKey, deviceId);
  }

  static Future<String?> getPikPakDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakDeviceIdKey);
  }

  static Future<void> setPikPakCaptchaToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakCaptchaTokenKey, token);
  }

  static Future<String?> getPikPakCaptchaToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakCaptchaTokenKey);
  }

  static Future<void> clearPikPakCaptchaToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pikpakCaptchaTokenKey);
  }

  static Future<void> setPikPakUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakUserIdKey, userId);
  }

  static Future<String?> getPikPakUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakUserIdKey);
  }

  // PikPak Show Videos Only
  static Future<bool> getPikPakShowVideosOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pikpakShowVideosOnlyKey) ?? true; // Default to true
  }

  static Future<void> setPikPakShowVideosOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pikpakShowVideosOnlyKey, value);
  }

  // PikPak Ignore Small Videos (under 100MB)
  static Future<bool> getPikPakIgnoreSmallVideos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pikpakIgnoreSmallVideosKey) ??
        true; // Default to true
  }

  static Future<void> setPikPakIgnoreSmallVideos(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pikpakIgnoreSmallVideosKey, value);
  }

  // PikPak Restricted Folder
  static Future<String?> getPikPakRestrictedFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakRestrictedFolderIdKey);
  }

  static Future<String?> getPikPakRestrictedFolderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakRestrictedFolderNameKey);
  }

  static Future<void> setPikPakRestrictedFolder(
    String? folderId,
    String? folderName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (folderId == null) {
      await prefs.remove(_pikpakRestrictedFolderIdKey);
      await prefs.remove(_pikpakRestrictedFolderNameKey);
    } else {
      await prefs.setString(_pikpakRestrictedFolderIdKey, folderId);
      if (folderName != null) {
        await prefs.setString(_pikpakRestrictedFolderNameKey, folderName);
      }
    }
  }

  static Future<void> clearPikPakRestrictedFolder() async {
    await setPikPakRestrictedFolder(null, null);
    // Also clear subfolder caches when restriction changes
    await clearPikPakSubfolderCaches();
  }

  // PikPak Subfolder ID caching (for debrify-torrents and debrify-tv folders)
  static Future<String?> getPikPakTorrentsFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakTorrentsFolderIdKey);
  }

  static Future<void> setPikPakTorrentsFolderId(String folderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakTorrentsFolderIdKey, folderId);
  }

  static Future<String?> getPikPakTvFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pikpakTvFolderIdKey);
  }

  static Future<void> setPikPakTvFolderId(String folderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pikpakTvFolderIdKey, folderId);
  }

  static Future<void> clearPikPakSubfolderCaches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pikpakTorrentsFolderIdKey);
    await prefs.remove(_pikpakTvFolderIdKey);
  }

  // PikPak Hidden from Navigation
  static Future<bool> getPikPakHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pikpakHiddenFromNavKey) ?? false;
  }

  static Future<void> setPikPakHiddenFromNav(bool hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pikpakHiddenFromNavKey, hidden);
  }

  static Future<void> clearPikPakHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pikpakHiddenFromNavKey);
  }

  // TVMaze Series Mapping Methods

  /// Get a unique key for a playlist item based on available identifiers
  static String _getPlaylistItemUniqueKey(Map<String, dynamic> playlistItem) {
    // Try different identifiers in order of preference
    if (playlistItem['rdTorrentId'] != null) {
      return 'rd_${playlistItem['rdTorrentId']}';
    }
    if (playlistItem['torrent_hash'] != null) {
      return 'hash_${playlistItem['torrent_hash']}';
    }
    if (playlistItem['torboxTorrentId'] != null) {
      return 'torbox_${playlistItem['torboxTorrentId']}';
    }
    if (playlistItem['pikpakFileId'] != null) {
      return 'pikpak_${playlistItem['pikpakFileId']}';
    }
    // Fallback to title if nothing else is available
    final title = (playlistItem['title'] as String?)?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_') ?? 'unknown';
    return 'title_$title';
  }

  /// Save a TVMaze series mapping for a playlist item
  static Future<void> saveTVMazeSeriesMapping({
    required Map<String, dynamic> playlistItem,
    required int tvmazeShowId,
    required String showName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    Map<String, dynamic> mappings = {};
    if (mappingsJson != null) {
      try {
        mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      } catch (e) {
        print('Error parsing TVMaze series mappings: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    mappings[key] = {
      'tvmazeShowId': tvmazeShowId,
      'showName': showName,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
    print('✅ Saved TVMaze mapping for $key -> Show ID: $tvmazeShowId ($showName)');
  }

  /// Get TVMaze series mapping for a playlist item
  static Future<Map<String, dynamic>?> getTVMazeSeriesMapping(Map<String, dynamic> playlistItem) async {
    final prefs = await SharedPreferences.getInstance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return null;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
      final mapping = mappings[key];

      if (mapping != null && mapping is Map<String, dynamic>) {
        print('✅ Found TVMaze mapping for $key -> Show ID: ${mapping['tvmazeShowId']} (${mapping['showName']})');
        return mapping;
      }
    } catch (e) {
      print('Error reading TVMaze series mappings: $e');
    }

    return null;
  }

  /// Clear TVMaze series mapping for a playlist item
  static Future<void> clearTVMazeSeriesMapping(Map<String, dynamic> playlistItem) async {
    final prefs = await SharedPreferences.getInstance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (mappings.containsKey(key)) {
        mappings.remove(key);
        await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
        print('✅ Cleared TVMaze mapping for $key');
      }
    } catch (e) {
      print('Error clearing TVMaze series mapping: $e');
    }
  }

  /// Clear all TVMaze series mappings
  static Future<void> clearAllTVMazeSeriesMappings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tvMazeSeriesMappingKey);
    print('✅ Cleared all TVMaze series mappings');
  }

  // Playlist Poster Override Methods

  /// Save a poster URL override for a playlist item
  /// This ensures the poster persists across app restarts
  static Future<void> savePlaylistPosterOverride({
    required Map<String, dynamic> playlistItem,
    required String posterUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    Map<String, dynamic> overrides = {};
    if (overridesJson != null) {
      try {
        overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      } catch (e) {
        print('Error parsing playlist poster overrides: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    overrides[key] = {
      'posterUrl': posterUrl,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_playlistPosterOverridesKey, jsonEncode(overrides));
    print('✅ Saved poster override for $key -> $posterUrl');
  }

  /// Get poster URL override for a playlist item
  /// Returns null if no override exists
  static Future<String?> getPlaylistPosterOverride(Map<String, dynamic> playlistItem) async {
    final prefs = await SharedPreferences.getInstance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return null;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
      final override = overrides[key];

      if (override != null && override is Map<String, dynamic>) {
        final posterUrl = override['posterUrl'] as String?;
        if (posterUrl != null && posterUrl.isNotEmpty) {
          return posterUrl;
        }
      }
    } catch (e) {
      print('Error reading playlist poster override: $e');
    }

    return null;
  }

  /// Clear poster URL override for a playlist item
  static Future<void> clearPlaylistPosterOverride(Map<String, dynamic> playlistItem) async {
    final prefs = await SharedPreferences.getInstance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (overrides.containsKey(key)) {
        overrides.remove(key);
        await prefs.setString(_playlistPosterOverridesKey, jsonEncode(overrides));
        print('✅ Cleared poster override for $key');
      }
    } catch (e) {
      print('Error clearing playlist poster override: $e');
    }
  }

  /// Clear all playlist poster overrides
  static Future<void> clearAllPlaylistPosterOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playlistPosterOverridesKey);
    print('✅ Cleared all playlist poster overrides');
  }

  // ============================================================================
  // Torrent Search History Methods
  // ============================================================================

  /// Get torrent search history
  /// Returns list of maps containing torrent JSON + service + timestamp
  static Future<List<Map<String, dynamic>>> getTorrentSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_torrentSearchHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error loading torrent search history: $e');
      return [];
    }
  }

  /// Add torrent to search history with deduplication
  /// Deduplicates by infohash, keeps max 5 items (FIFO)
  static Future<void> addTorrentToHistory(
    Map<String, dynamic> torrentJson,
    String service,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getTorrentSearchHistory();

    final infohash = torrentJson['infohash'] as String?;
    if (infohash == null || infohash.isEmpty) return;

    // Remove existing entry with same infohash (deduplicate)
    history.removeWhere((entry) {
      final entryTorrent = entry['torrent'] as Map<String, dynamic>?;
      return entryTorrent?['infohash'] == infohash;
    });

    // Add new entry at start
    history.insert(0, {
      'torrent': torrentJson,
      'service': service,
      'clickedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep only last 5
    if (history.length > 5) {
      history.removeRange(5, history.length);
    }

    await prefs.setString(_torrentSearchHistoryKey, jsonEncode(history));
  }

  /// Clear all search history
  static Future<void> clearTorrentSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_torrentSearchHistoryKey);
  }

  /// Get whether search history tracking is enabled
  static Future<bool> getTorrentSearchHistoryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_torrentSearchHistoryEnabledKey) ?? true;
  }

  /// Set whether search history tracking is enabled
  static Future<void> setTorrentSearchHistoryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_torrentSearchHistoryEnabledKey, enabled);
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
      await DebridService.getUserInfo(apiKey);
      return true; // If we get here, the API key is valid
    } catch (e) {
      return false;
    }
  }
}
