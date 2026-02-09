import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'debrid_service.dart';
import '../models/iptv_playlist.dart';

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

  // Home page default keys
  static const String _homeDefaultSourceTypeKey = 'home_default_source_type';
  static const String _homeDefaultAddonUrlKey = 'home_default_addon_url';
  static const String _homeDefaultCatalogIdKey = 'home_default_catalog_id';
  static const String _homeHideProviderCardsKey = 'home_hide_provider_cards';
  static const String _homeFavoritesOpenFolderKey = 'home_favorites_open_folder';

  // Startup settings
  static const String _startupAutoLaunchEnabledKey =
      'startup_auto_launch_enabled';
  static const String _startupChannelIdKey = 'startup_channel_id';
  static const String _startupModeKey = 'startup_mode'; // 'channel' or 'playlist'
  static const String _startupPlaylistItemIdKey = 'startup_playlist_item_id';

  // Reddit settings
  static const String _redditAccessTokenKey = 'reddit_access_token';
  static const String _redditRefreshTokenKey = 'reddit_refresh_token';
  static const String _redditUsernameKey = 'reddit_username';
  static const String _redditEnabledKey = 'reddit_enabled';
  static const String _redditHiddenFromNavKey = 'reddit_hidden_from_nav';
  static const String _redditLastSubredditKey = 'reddit_last_subreddit';
  static const String _redditRecentSubredditsKey = 'reddit_recent_subreddits';
  static const String _redditAllowNsfwKey = 'reddit_allow_nsfw';
  static const String _redditFavoriteSubredditsKey = 'reddit_favorite_subreddits';
  static const String _redditDefaultSubredditKey = 'reddit_default_subreddit';

  // External Player settings
  // Default player mode: 'debrify' (app player), 'external' (external player), 'deovr' (DeoVR on Android)
  static const String _defaultPlayerModeKey = 'default_player_mode';
  static const String _externalPlayerPreferredKey = 'external_player_preferred';
  static const String _externalPlayerCustomPathKey = 'external_player_custom_path';
  static const String _externalPlayerCustomNameKey = 'external_player_custom_name';
  static const String _externalPlayerCustomCommandKey = 'external_player_custom_command';
  // iOS External Player settings
  static const String _iosExternalPlayerPreferredKey = 'ios_external_player_preferred';
  static const String _iosCustomSchemeTemplateKey = 'ios_custom_scheme_template';
  // Linux External Player settings
  static const String _linuxExternalPlayerPreferredKey = 'linux_external_player_preferred';
  static const String _linuxCustomCommandKey = 'linux_custom_command';
  // Windows External Player settings
  static const String _windowsExternalPlayerPreferredKey = 'windows_external_player_preferred';
  static const String _windowsCustomCommandKey = 'windows_custom_command';

  // Debrify Player default settings
  static const String _playerDefaultAspectIndexKey = 'player_default_aspect_index';
  static const String _playerDefaultAspectIndexTvKey = 'player_default_aspect_index_tv';
  static const String _playerNightModeIndexKey = 'player_night_mode_index';
  static const String _playerDefaultSubtitleLanguageKey = 'player_default_subtitle_language';
  static const String _playerDefaultAudioLanguageKey = 'player_default_audio_language';

  // IPTV settings
  static const String _iptvPlaylistsKey = 'iptv_playlists';
  static const String _iptvDefaultPlaylistKey = 'iptv_default_playlist';
  static const String _iptvDefaultsInitializedKey = 'iptv_defaults_initialized';

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
  static const String _debrifyTvFavoriteChannelsKey =
      'debrify_tv_favorite_channels_v1';
  static const String _iptvFavoriteChannelsKey =
      'iptv_favorite_channels_v1';

  // Stremio TV settings
  static const String _stremioTvRotationMinutesKey =
      'stremio_tv_rotation_minutes';
  static const String _stremioTvAutoRefreshKey = 'stremio_tv_auto_refresh';
  static const String _stremioTvFavoriteChannelsKey =
      'stremio_tv_favorite_channels_v1';
  static const String _stremioTvPreferredQualityKey =
      'stremio_tv_preferred_quality';
  static const String _stremioTvDebridProviderKey =
      'stremio_tv_debrid_provider';
  static const String _stremioTvMaxStartPercentKey =
      'stremio_tv_max_start_percent';

  static const String _playlistKey = 'user_playlist_v1';
  static const String _playlistViewModesKey = 'playlist_view_modes_v1';
  static const String _playlistFavoritesKey = 'playlist_favorites_v1';
  static const String _onboardingCompleteKey = 'initial_setup_complete_v1';

  // Torrent Search History
  static const String _torrentSearchHistoryKey = 'torrent_search_history_v1';
  static const String _torrentSearchHistoryEnabledKey = 'torrent_search_history_enabled';

  // Default Torrent Filter Settings
  static const String _defaultFilterQualitiesKey = 'default_filter_qualities_v1';
  static const String _defaultFilterRipSourcesKey = 'default_filter_rip_sources_v1';
  static const String _defaultFilterLanguagesKey = 'default_filter_languages_v1';

  // Default Torrent Provider Settings
  // Values: 'none' (ask every time), 'torbox', 'debrid', 'pikpak'
  static const String _defaultTorrentProviderKey = 'default_torrent_provider_v1';

  // Quick Play VR Settings
  // VR Player Mode: 'disabled' (always regular player), 'auto' (detect VR content), 'always' (always use DeoVR)
  static const String _quickPlayVrModeKey = 'quick_play_vr_mode';
  static const String _quickPlayVrDefaultScreenTypeKey = 'quick_play_vr_default_screen_type';
  static const String _quickPlayVrDefaultStereoModeKey = 'quick_play_vr_default_stereo_mode';
  static const String _quickPlayVrAutoDetectFormatKey = 'quick_play_vr_auto_detect_format';
  static const String _quickPlayVrShowDialogKey = 'quick_play_vr_show_dialog';

  // Quick Play Cache Fallback Settings
  // When enabled, if first torrent is not cached, try next torrents until one works
  static const String _quickPlayTryMultipleTorrentsKey = 'quick_play_try_multiple_torrents';
  static const String _quickPlayMaxRetriesKey = 'quick_play_max_retries';

  // Remote Control Settings
  static const String _remoteControlEnabledKey = 'remote_control_enabled';
  static const String _remoteIntroShownKey = 'remote_intro_shown';
  static const String _remoteTvDeviceNameKey = 'remote_tv_device_name';
  static const String _remoteLastDeviceKey = 'remote_last_device';

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

    // Ensure seasons map exists
    if (!seriesData.containsKey('seasons')) {
      seriesData['seasons'] = {};
    }

    // Ensure finishedEpisodes map exists
    if (!seriesData.containsKey('finishedEpisodes')) {
      seriesData['finishedEpisodes'] = {};
    }

    if (!seriesData['finishedEpisodes'].containsKey(season.toString())) {
      seriesData['finishedEpisodes'][season.toString()] = {};
    }

    seriesData['finishedEpisodes'][season.toString()][episode.toString()] = {
      'finishedAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Also add/update in seasons map so it appears in getEpisodeProgress()
    // This ensures UI can find the episode even if it was never played
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    final episodeData = seriesData['seasons'][season.toString()][episode.toString()];

    if (episodeData == null) {
      // Episode was never played - add dummy data to mark as watched
      seriesData['seasons'][season.toString()][episode.toString()] = {
        'positionMs': 0,
        'durationMs': 1,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
    } else {
      // Episode has existing progress - update it to show as finished
      // Set position = duration to show 100% progress
      final existingData = episodeData as Map<String, dynamic>;
      final durationMs = existingData['durationMs'] as int? ?? 1;
      existingData['positionMs'] = durationMs; // Mark as fully watched
      existingData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    }

    debugPrint(
      'StorageService: markEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
    );

    await _savePlaybackStateMap(map);
  }

  /// Unmark an episode as finished (mark as unwatched)
  static Future<void> unmarkEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return;

    // Remove from finishedEpisodes map
    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes != null) {
      final seasonData = finishedEpisodes[season.toString()];
      if (seasonData != null) {
        seasonData.remove(episode.toString());

        // Clean up empty season map
        if (seasonData.isEmpty) {
          finishedEpisodes.remove(season.toString());
        }
      }
    }

    // Also remove from seasons map if it only has dummy progress data (position 0)
    // This keeps episodes that were actually watched with real progress
    final seasons = seriesData['seasons'];
    if (seasons != null) {
      final seasonData = seasons[season.toString()];
      if (seasonData != null) {
        final episodeData = seasonData[episode.toString()];
        if (episodeData != null) {
          // Only remove if it's dummy data (position 0, duration 1)
          final positionMs = episodeData['positionMs'] ?? 0;
          final durationMs = episodeData['durationMs'] ?? 0;
          if (positionMs == 0 && durationMs == 1) {
            seasonData.remove(episode.toString());

            // Clean up empty season map
            if (seasonData.isEmpty) {
              seasons.remove(season.toString());
            }
          } else {
            // Episode has real progress, just reset it to 0
            episodeData['positionMs'] = 0;
            episodeData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
          }
        }
      }
    }

    debugPrint(
      'StorageService: unmarkEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
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

  /// Clear all progress data for a specific playlist/series
  static Future<void> clearPlaylistProgress({
    required String title,
  }) async {
    final map = await _getPlaybackStateMap();

    debugPrint('StorageService: clearPlaylistProgress called for "$title"');

    final keysToRemove = <String>[];

    // Use the SAME matching logic as when finding series progress
    // Try multiple title variations to find all matching entries

    // Variation 1: Use the full playlist item title
    final fullTitleKey = 'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final fullVideoKey = 'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    // Variation 2: Try extracting clean title (like "breaking bad" from "Breaking.Bad.SEASON.01.S01...")
    // This matches how SeriesPlaylist extracts the title
    String cleanedTitle = title;

    // Remove common patterns to extract series name
    cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.S\d{2}.*', caseSensitive: false), ''); // Remove S01-S08 and everything after
    cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.Season\..*', caseSensitive: false), ''); // Remove Season.1-8
    cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false), ''); // Remove quality
    cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false), ''); // Remove codec
    cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false), ''); // Remove source
    cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

    final cleanTitleKey = 'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final cleanVideoKey = 'video_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    debugPrint('StorageService: checking keys - full: $fullTitleKey / $fullVideoKey, clean: $cleanTitleKey / $cleanVideoKey');
    debugPrint('StorageService: available keys: ${map.keys.toList()}');

    // Check for exact key matches first
    for (final key in [cleanTitleKey, cleanVideoKey, fullTitleKey, fullVideoKey]) {
      if (map.containsKey(key) && !keysToRemove.contains(key)) {
        keysToRemove.add(key);
        debugPrint('StorageService: exact key match: "$key"');
      }
    }

    // Fallback: Search through all series/video entries
    // Check if the input title contains the stored series title
    // This handles cases where playlist title is "Game of Thrones - Season 3" but stored title is "game of thrones"
    for (final entry in map.entries) {
      if ((entry.key.startsWith('series_') || entry.key.startsWith('video_')) &&
          entry.value is Map<String, dynamic> &&
          !keysToRemove.contains(entry.key)) {

        final storedTitle = (entry.value['title'] as String?)?.toLowerCase() ?? '';
        if (storedTitle.isEmpty) continue;

        final titleLower = title.toLowerCase();
        final cleanedTitleLower = cleanedTitle.toLowerCase();

        // Check if the stored series title matches in several ways:
        // 1. Exact match with cleaned title (e.g., "game of thrones" == "game of thrones")
        // 2. Input title contains the stored series title (e.g., "game of thrones - season 3" contains "game of thrones")
        // 3. Cleaned title contains the stored series title
        if (storedTitle == cleanedTitleLower ||
            storedTitle == titleLower ||
            (titleLower.contains(storedTitle) && storedTitle.split(' ').length >= 2)) {
          keysToRemove.add(entry.key);
          debugPrint('StorageService: stored title match - key: "${entry.key}", storedTitle: "$storedTitle"');
        }
      }
    }

    // Remove all matching keys
    for (final key in keysToRemove) {
      map.remove(key);
      debugPrint('StorageService: removed progress entry with key: "$key"');
    }

    // Save the updated map if anything was removed
    if (keysToRemove.isNotEmpty) {
      await _savePlaybackStateMap(map);
      debugPrint('StorageService: clearPlaylistProgress completed - removed ${keysToRemove.length} entries for "$title"');
    } else {
      debugPrint('StorageService: no progress data found for "$title"');
    }
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

  /// Update lastPlayedAt timestamp for a playlist item
  /// Call this when user starts playing a playlist item
  static Future<void> updatePlaylistItemLastPlayed(
    Map<String, dynamic> item,
  ) async {
    final items = await getPlaylistItemsRaw();
    final dedupeKey = computePlaylistDedupeKey(item);
    final index = items.indexWhere(
      (e) => computePlaylistDedupeKey(e) == dedupeKey,
    );

    if (index != -1) {
      items[index]['lastPlayedAt'] = DateTime.now().millisecondsSinceEpoch;
      await savePlaylistItemsRaw(items);
      debugPrint(
        'StorageService: Updated lastPlayedAt for "${items[index]['title']}"',
      );
    }
  }

  /// Get lastPlayedAt timestamp for a playlist item
  /// Returns null if item has never been played
  static int? getPlaylistItemLastPlayed(Map<String, dynamic> item) {
    return item['lastPlayedAt'] as int?;
  }

  static Future<void> clearPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playlistKey);
  }

  /// Clear all playlist-related metadata (view modes, favorites, poster overrides)
  static Future<void> clearAllPlaylistMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playlistViewModesKey);
    await prefs.remove(_playlistFavoritesKey);
    await prefs.remove(_playlistPosterOverridesKey);
    await prefs.remove(_tvMazeSeriesMappingKey);
  }

  /// Clear all startup settings (auto-launch, channel/playlist references)
  static Future<void> clearAllStartupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_startupAutoLaunchEnabledKey);
    await prefs.remove(_startupChannelIdKey);
    await prefs.remove(_startupModeKey);
    await prefs.remove(_startupPlaylistItemIdKey);
  }

  /// Clear integration enabled states (RD, TorBox)
  static Future<void> clearAllIntegrationStates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_realDebridIntegrationEnabledKey);
    await prefs.remove(_realDebridHiddenFromNavKey);
    await prefs.remove(_torboxIntegrationEnabledKey);
    await prefs.remove(_torboxHiddenFromNavKey);
  }

  /// Clear Debrify TV provider and legacy channels key
  static Future<void> clearDebrifyTvProviderAndLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_debrifyTvProviderKey);
    await prefs.remove(_debrifyTvChannelsKey);
  }

  /// Clear filter settings (qualities, rip sources, languages)
  static Future<void> clearAllFilterSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultFilterQualitiesKey);
    await prefs.remove(_defaultFilterRipSourcesKey);
    await prefs.remove(_defaultFilterLanguagesKey);
    await prefs.remove(_defaultTorrentProviderKey);
  }

  /// Clear torrent engine toggles and limits
  static Future<void> clearAllTorrentEngineSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultTorrentsCsvEnabledKey);
    await prefs.remove(_defaultPirateBayEnabledKey);
    await prefs.remove(_defaultYtsEnabledKey);
    await prefs.remove(_defaultSolidTorrentsEnabledKey);
    await prefs.remove(_maxTorrentsCsvResultsKey);
    await prefs.remove(_maxSolidTorrentsResultsKey);
  }

  /// Clear post-torrent action preferences
  static Future<void> clearAllPostTorrentActions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_postTorrentActionKey);
    await prefs.remove(_torboxPostTorrentActionKey);
    await prefs.remove(_pikpakPostTorrentActionKey);
  }

  /// Clear all Debrify TV display and engine settings
  static Future<void> clearAllDebrifyTvSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Display settings
    await prefs.remove(_debrifyTvStartRandomKey);
    await prefs.remove(_debrifyTvHideSeekbarKey);
    await prefs.remove(_debrifyTvShowChannelNameKey);
    await prefs.remove(_debrifyTvShowVideoTitleKey);
    await prefs.remove(_debrifyTvHideOptionsKey);
    await prefs.remove(_debrifyTvHideBackButtonKey);
    await prefs.remove(_debrifyTvAvoidNsfwKey);
    await prefs.remove(_debrifyTvRandomStartPercentKey);
    // Engine toggles
    await prefs.remove(_debrifyTvUseTorrentsCsvKey);
    await prefs.remove(_debrifyTvUsePirateBayKey);
    await prefs.remove(_debrifyTvUseYtsKey);
    await prefs.remove(_debrifyTvUseSolidTorrentsKey);
    // Channel limits
    await prefs.remove(_debrifyTvChannelSmallTorrentsCsvMaxKey);
    await prefs.remove(_debrifyTvChannelSmallSolidTorrentsMaxKey);
    await prefs.remove(_debrifyTvChannelSmallYtsMaxKey);
    await prefs.remove(_debrifyTvChannelLargeTorrentsCsvMaxKey);
    await prefs.remove(_debrifyTvChannelLargeSolidTorrentsMaxKey);
    await prefs.remove(_debrifyTvChannelLargeYtsMaxKey);
    // QuickPlay limits
    await prefs.remove(_debrifyTvQuickPlayTorrentsCsvMaxKey);
    await prefs.remove(_debrifyTvQuickPlaySolidTorrentsMaxKey);
    await prefs.remove(_debrifyTvQuickPlayYtsMaxKey);
    await prefs.remove(_debrifyTvQuickPlayMaxKeywordsKey);
    // Advanced settings
    await prefs.remove(_debrifyTvChannelBatchSizeKey);
    await prefs.remove(_debrifyTvKeywordThresholdKey);
    await prefs.remove(_debrifyTvMinTorrentsPerKeywordKey);
  }

  /// Update an existing playlist item with poster URL
  /// Supports both RealDebrid (rdTorrentId) and PikPak (pikpakCollectionId)
  static Future<bool> updatePlaylistItemPoster(
    String posterUrl, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
  }) async {
    print('🎨 updatePlaylistItemPoster called with:');
    print('  posterUrl: $posterUrl');
    print('  rdTorrentId: $rdTorrentId');
    print('  torboxTorrentId: $torboxTorrentId');
    print('  pikpakCollectionId: $pikpakCollectionId');

    final items = await getPlaylistItemsRaw();
    print('  Total playlist items: ${items.length}');

    int itemIndex = -1;

    // Search by rdTorrentId if provided (RealDebrid)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
      if (itemIndex != -1) {
        print('  ✅ Found item by rdTorrentId at index $itemIndex');
      }
    }

    // Search by torboxTorrentId if provided and not found yet (Torbox)
    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      print('  Searching for torboxTorrentId: $torboxTorrentId');
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final torboxId = item['torboxTorrentId'];
        print('    Item[$i] torboxTorrentId: $torboxId (type: ${torboxId.runtimeType})');
        if (torboxId != null && torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          print('  ✅ Found item by torboxTorrentId at index $itemIndex');
          break;
        }
      }
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
      if (itemIndex != -1) {
        print('  ✅ Found item by pikpakCollectionId at index $itemIndex');
      }
    }

    if (itemIndex == -1) {
      print('  ❌ Item not found in playlist!');
      return false;
    }

    print('  💾 Saving poster to item at index $itemIndex');
    items[itemIndex]['posterUrl'] = posterUrl;
    await savePlaylistItemsRaw(items);
    print('  ✅ Poster saved successfully!');
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

  /// Check if a playlist item is favorited
  static Future<bool> isPlaylistItemFavorited(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
      return favorites[dedupeKey] == true;
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a playlist item
  static Future<void> setPlaylistItemFavorited(Map<String, dynamic> item, bool isFavorited) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist favorites: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    if (isFavorited) {
      favorites[dedupeKey] = true;
    } else {
      favorites.remove(dedupeKey);
    }

    await prefs.setString(_playlistFavoritesKey, jsonEncode(favorites));
  }

  /// Get all favorite dedupe keys
  static Future<Set<String>> getPlaylistFavoriteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_playlistFavoritesKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading playlist favorites: $e');
      return {};
    }
  }

  // ==========================================================================
  // Debrify TV Channel Favorites
  // ==========================================================================

  /// Check if a Debrify TV channel is favorited
  static Future<bool> isDebrifyTvChannelFavorited(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelId);
    } catch (e) {
      debugPrint('Error reading Debrify TV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for a Debrify TV channel
  static Future<void> setDebrifyTvChannelFavorited(
    String channelId,
    bool isFavorited,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

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

    await prefs.setString(_debrifyTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Debrify TV channel IDs
  static Future<Set<String>> getDebrifyTvFavoriteChannelIds() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_debrifyTvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.keys.toSet();
    } catch (e) {
      debugPrint('Error reading Debrify TV channel favorites: $e');
      return {};
    }
  }

  // ==========================================================================
  // IPTV Channel Favorites
  // ==========================================================================

  /// Check if an IPTV channel is favorited (by URL)
  static Future<bool> isIptvChannelFavorited(String channelUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_iptvFavoriteChannelsKey);

    if (favoritesJson == null) return false;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.containsKey(channelUrl);
    } catch (e) {
      debugPrint('Error reading IPTV channel favorites: $e');
      return false;
    }
  }

  /// Set favorite status for an IPTV channel
  static Future<void> setIptvChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_iptvFavoriteChannelsKey);

    Map<String, dynamic> favorites = {};
    if (favoritesJson != null) {
      try {
        favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (isFavorited) {
      // Store channel metadata along with the favorite status
      favorites[channelUrl] = {
        'name': channelName ?? '',
        'logoUrl': logoUrl ?? '',
        'group': group ?? '',
        'playlistId': playlistId ?? '',
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      };
    } else {
      favorites.remove(channelUrl);
    }

    await prefs.setString(_iptvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Remove all IPTV favorites that belong to a specific playlist
  static Future<void> removeIptvFavoritesByPlaylistId(String playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_iptvFavoriteChannelsKey);

    if (favoritesJson == null) return;

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;

      // Remove entries that belong to the deleted playlist
      favorites.removeWhere((url, metadata) {
        if (metadata is Map<String, dynamic>) {
          return metadata['playlistId'] == playlistId;
        }
        return false;
      });

      await prefs.setString(_iptvFavoriteChannelsKey, jsonEncode(favorites));
    } catch (e) {
      debugPrint('Error removing IPTV favorites for playlist $playlistId: $e');
    }
  }

  /// Get all favorite IPTV channel URLs with metadata
  static Future<Map<String, Map<String, dynamic>>> getIptvFavoriteChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_iptvFavoriteChannelsKey);

    if (favoritesJson == null) return {};

    try {
      final favorites = jsonDecode(favoritesJson) as Map<String, dynamic>;
      return favorites.map((key, value) => MapEntry(
        key,
        value is Map<String, dynamic> ? value : {'name': '', 'logoUrl': '', 'group': ''},
      ));
    } catch (e) {
      debugPrint('Error reading IPTV channel favorites: $e');
      return {};
    }
  }

  /// Get all favorite IPTV channel URLs
  static Future<Set<String>> getIptvFavoriteChannelUrls() async {
    final favorites = await getIptvFavoriteChannels();
    return favorites.keys.toSet();
  }

  /// Build progress map for playlist items
  /// Maps playlist dedupe keys to their playback progress data
  static Future<Map<String, Map<String, dynamic>>> buildPlaylistProgressMap(
    List<Map<String, dynamic>> playlistItems,
  ) async {
    final progressMap = <String, Map<String, dynamic>>{};
    final playbackStateMap = await _getPlaybackStateMap();

    for (final item in playlistItems) {
      final dedupeKey = computePlaylistDedupeKey(item);
      final title = (item['title'] as String?) ?? '';

      // Try to find progress data for this item
      Map<String, dynamic>? progressData;

      // Check if it's stored as a video (single file)
      final videoKey = 'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      final videoState = playbackStateMap[videoKey];
      if (videoState != null && videoState['type'] == 'video') {
        progressData = {
          'positionMs': videoState['positionMs'] ?? 0,
          'durationMs': videoState['durationMs'] ?? 0,
          'updatedAt': videoState['updatedAt'] ?? 0,
        };
      }

      // Check if it's stored as a series
      if (progressData == null) {
        // Try multiple title variations to find the series state
        String? matchingSeriesKey;
        Map<String, dynamic>? seriesState;

        // Variation 1: Use the full playlist item title
        final fullTitleKey = 'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Variation 2: Try extracting clean title (like "game of thrones" from torrent name)
        // This matches how SeriesPlaylist extracts the title
        String cleanedTitle = title;

        // Remove common patterns to extract series name
        cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.S\d{2}.*', caseSensitive: false), ''); // Remove S01-S08 and everything after
        cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.Season\..*', caseSensitive: false), ''); // Remove Season.1-8
        cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false), ''); // Remove quality
        cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false), ''); // Remove codec
        cleanedTitle = cleanedTitle.replaceAll(RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false), ''); // Remove source
        cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

        final cleanTitleKey = 'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Try both variations - PRIORITIZE clean title first (where playback state is actually saved)
        if (playbackStateMap[cleanTitleKey] != null && playbackStateMap[cleanTitleKey]['type'] == 'series') {
          matchingSeriesKey = cleanTitleKey;
          seriesState = playbackStateMap[cleanTitleKey] as Map<String, dynamic>;
        } else if (playbackStateMap[fullTitleKey] != null && playbackStateMap[fullTitleKey]['type'] == 'series') {
          matchingSeriesKey = fullTitleKey;
          seriesState = playbackStateMap[fullTitleKey] as Map<String, dynamic>;
        } else {
          // Fallback: Search through all series entries for a partial match
          for (final entry in playbackStateMap.entries) {
            if (entry.key.startsWith('series_') && entry.value['type'] == 'series') {
              final seriesTitle = (entry.value['title'] as String?)?.toLowerCase() ?? '';
              final itemTitleLower = title.toLowerCase();

              // Check if the series title is contained in the item title or vice versa
              if (itemTitleLower.contains(seriesTitle) || seriesTitle.contains(cleanedTitle.toLowerCase())) {
                matchingSeriesKey = entry.key;
                seriesState = entry.value as Map<String, dynamic>;
                break;
              }
            }
          }
        }

        if (seriesState != null && matchingSeriesKey != null) {
          debugPrint('📺 Matched series state for "$title" using key: $matchingSeriesKey');

          // Calculate overall series progress (Option 2)
          // Formula: (finished episodes + partial episode progress) / total episodes

          int totalEpisodes = (item['fileCount'] as int?) ?? (item['count'] as int?) ?? 0;
          if (totalEpisodes == 0) {
            // Try to count from the playlist item structure
            totalEpisodes = 1; // Fallback to at least 1
          }

          // Count finished episodes from both finishedEpisodes and seasons maps
          // Use a Set to track which episodes are finished to avoid double-counting
          final Set<String> finishedEpisodeKeys = {};
          int finishedEpisodeCount = 0;

          // First, count episodes explicitly marked as finished (TV series)
          final finishedEpisodes = seriesState['finishedEpisodes'] as Map<String, dynamic>?;
          if (finishedEpisodes != null) {
            for (final seasonEntry in finishedEpisodes.entries) {
              final seasonKey = seasonEntry.key;
              final seasonFinished = seasonEntry.value as Map<String, dynamic>;
              for (final episodeKey in seasonFinished.keys) {
                final key = '${seasonKey}_$episodeKey';
                finishedEpisodeKeys.add(key);
                finishedEpisodeCount++;
              }
            }
          }

          // Find the most recently played episode (for timestamp and partial progress)
          int latestPosition = 0;
          int latestDuration = 0;
          int latestUpdatedAt = 0;
          String? latestEpisodeKey;

          final seasons = seriesState['seasons'] as Map<String, dynamic>?;
          if (seasons != null) {
            for (final seasonEntry in seasons.entries) {
              final seasonKey = seasonEntry.key;
              final episodes = seasonEntry.value as Map<String, dynamic>;
              for (final episodeEntry in episodes.entries) {
                final episodeKey = episodeEntry.key;
                final episodeData = episodeEntry.value as Map<String, dynamic>;
                final positionMs = episodeData['positionMs'] as int? ?? 0;
                final durationMs = episodeData['durationMs'] as int? ?? 0;
                final updatedAt = episodeData['updatedAt'] as int? ?? 0;

                // Count as finished if >= 95% watched AND not already counted
                final key = '${seasonKey}_$episodeKey';
                if (durationMs > 0 && (positionMs / durationMs) >= 0.95) {
                  if (!finishedEpisodeKeys.contains(key)) {
                    finishedEpisodeKeys.add(key);
                    finishedEpisodeCount++;
                  }
                }

                // Track latest episode for partial progress
                if (updatedAt > latestUpdatedAt) {
                  latestUpdatedAt = updatedAt;
                  latestPosition = positionMs;
                  latestDuration = durationMs;
                  latestEpisodeKey = key;
                }
              }
            }
          }

          // Calculate partial progress from latest episode ONLY if not already counted as finished
          double partialEpisodeProgress = 0.0;
          bool hasPartialProgress = false;
          if (latestDuration > 0 && latestPosition > 0 && latestEpisodeKey != null) {
            partialEpisodeProgress = latestPosition / latestDuration;
            // Only count as partial if < 95% (not already counted as finished)
            if (partialEpisodeProgress < 0.95 && !finishedEpisodeKeys.contains(latestEpisodeKey)) {
              hasPartialProgress = true;
            }
          }

          if (latestUpdatedAt > 0 && totalEpisodes > 0) {
            // Calculate overall series progress
            double totalEpisodesWatched = finishedEpisodeCount.toDouble();
            if (hasPartialProgress) {
              totalEpisodesWatched += partialEpisodeProgress;
            }

            // Create synthetic position/duration representing series progress
            final syntheticDuration = totalEpisodes * 1000000; // 1M ms per episode (arbitrary)
            final syntheticPosition = (totalEpisodesWatched * 1000000).toInt();

            progressData = {
              'positionMs': syntheticPosition,
              'durationMs': syntheticDuration,
              'updatedAt': latestUpdatedAt,
            };

            debugPrint(
              'Series "$title": $finishedEpisodeCount finished + ${partialEpisodeProgress.toStringAsFixed(2)} partial = ${totalEpisodesWatched.toStringAsFixed(2)} / $totalEpisodes episodes (${((totalEpisodesWatched / totalEpisodes) * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      }

      if (progressData != null) {
        progressMap[dedupeKey] = progressData;
        debugPrint(
          'StorageService: Found progress for "$title" - ${progressData['positionMs']}ms / ${progressData['durationMs']}ms (${((progressData['positionMs'] / progressData['durationMs']) * 100).toStringAsFixed(1)}%)',
        );
      }
    }

    debugPrint('StorageService: Built progress map with ${progressMap.length} entries');
    return progressMap;
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

  // Home Page Default Settings
  static Future<String?> getHomeDefaultSourceType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_homeDefaultSourceTypeKey);
  }

  static Future<void> setHomeDefaultSourceType(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_homeDefaultSourceTypeKey);
    } else {
      await prefs.setString(_homeDefaultSourceTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultAddonUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_homeDefaultAddonUrlKey);
  }

  static Future<void> setHomeDefaultAddonUrl(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_homeDefaultAddonUrlKey);
    } else {
      await prefs.setString(_homeDefaultAddonUrlKey, value);
    }
  }

  static Future<String?> getHomeDefaultCatalogId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_homeDefaultCatalogIdKey);
  }

  static Future<void> setHomeDefaultCatalogId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_homeDefaultCatalogIdKey);
    } else {
      await prefs.setString(_homeDefaultCatalogIdKey, value);
    }
  }

  static Future<bool> getHomeHideProviderCards() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_homeHideProviderCardsKey) ?? false;
  }

  static Future<void> setHomeHideProviderCards(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_homeHideProviderCardsKey, value);
  }

  static Future<String> getHomeFavoritesTapAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_homeFavoritesOpenFolderKey) ?? 'choose';
  }

  static Future<void> setHomeFavoritesTapAction(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeFavoritesOpenFolderKey, value);
  }

  static Future<void> clearAllHomePageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeDefaultSourceTypeKey);
    await prefs.remove(_homeDefaultAddonUrlKey);
    await prefs.remove(_homeDefaultCatalogIdKey);
    await prefs.remove(_homeHideProviderCardsKey);
    await prefs.remove(_homeFavoritesOpenFolderKey);
  }

  // Reddit Settings
  static Future<String?> getRedditAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_redditAccessTokenKey);
  }

  static Future<void> setRedditAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_redditAccessTokenKey, token);
  }

  static Future<String?> getRedditRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_redditRefreshTokenKey);
  }

  static Future<void> setRedditRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_redditRefreshTokenKey, token);
  }

  static Future<String?> getRedditUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_redditUsernameKey);
  }

  static Future<void> setRedditUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_redditUsernameKey, username);
  }

  static Future<bool> getRedditEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_redditEnabledKey) ?? true; // Default enabled
  }

  static Future<void> setRedditEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_redditEnabledKey, value);
  }

  static Future<bool> getRedditHiddenFromNav() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_redditHiddenFromNavKey) ?? false;
  }

  static Future<void> setRedditHiddenFromNav(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_redditHiddenFromNavKey, value);
  }

  static Future<String?> getRedditLastSubreddit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_redditLastSubredditKey);
  }

  static Future<void> setRedditLastSubreddit(String subreddit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_redditLastSubredditKey, subreddit);
  }

  static Future<void> clearRedditAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_redditAccessTokenKey);
    await prefs.remove(_redditRefreshTokenKey);
    await prefs.remove(_redditUsernameKey);
  }

  static Future<List<String>> getRedditRecentSubreddits() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_redditRecentSubredditsKey) ?? [];
  }

  static Future<void> setRedditRecentSubreddits(List<String> subreddits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_redditRecentSubredditsKey, subreddits);
  }

  static Future<bool> getRedditAllowNsfw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_redditAllowNsfwKey) ?? false;
  }

  static Future<void> setRedditAllowNsfw(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_redditAllowNsfwKey, value);
  }

  static Future<List<String>> getRedditFavoriteSubreddits() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_redditFavoriteSubredditsKey) ?? [];
  }

  static Future<void> setRedditFavoriteSubreddits(List<String> subreddits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_redditFavoriteSubredditsKey, subreddits);
  }

  static Future<String?> getRedditDefaultSubreddit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_redditDefaultSubredditKey);
  }

  static Future<void> setRedditDefaultSubreddit(String? subreddit) async {
    final prefs = await SharedPreferences.getInstance();
    if (subreddit == null || subreddit.isEmpty) {
      await prefs.remove(_redditDefaultSubredditKey);
    } else {
      await prefs.setString(_redditDefaultSubredditKey, subreddit);
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

  // Default Torrent Filter Settings
  static Future<List<String>> getDefaultFilterQualities() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_defaultFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterQualities(List<String> qualities) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDefaultFilterRipSources() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_defaultFilterRipSourcesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterRipSources(List<String> ripSources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultFilterRipSourcesKey, jsonEncode(ripSources));
  }

  static Future<List<String>> getDefaultFilterLanguages() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_defaultFilterLanguagesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterLanguages(List<String> languages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultFilterLanguagesKey, jsonEncode(languages));
  }

  // Default Torrent Provider methods
  // Returns: 'none' (ask every time), 'torbox', 'debrid', or 'pikpak'
  static Future<String> getDefaultTorrentProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultTorrentProviderKey) ?? 'none';
  }

  static Future<void> setDefaultTorrentProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultTorrentProviderKey, provider);
  }

  static Future<void> clearDefaultTorrentProvider() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultTorrentProviderKey);
  }

  // Quick Play VR Settings methods

  /// Get VR player mode: 'disabled', 'auto', or 'always'
  static Future<String> getQuickPlayVrMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_quickPlayVrModeKey) ?? 'disabled';
  }

  static Future<void> setQuickPlayVrMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quickPlayVrModeKey, mode);
  }

  /// Get default VR screen type (dome, sphere, flat, fisheye, mkx200, rf52)
  static Future<String> getQuickPlayVrDefaultScreenType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_quickPlayVrDefaultScreenTypeKey) ?? 'dome';
  }

  static Future<void> setQuickPlayVrDefaultScreenType(String screenType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quickPlayVrDefaultScreenTypeKey, screenType);
  }

  /// Get default VR stereo mode (sbs, tb, off)
  static Future<String> getQuickPlayVrDefaultStereoMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_quickPlayVrDefaultStereoModeKey) ?? 'sbs';
  }

  static Future<void> setQuickPlayVrDefaultStereoMode(String stereoMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quickPlayVrDefaultStereoModeKey, stereoMode);
  }

  /// Get whether to auto-detect VR format from filename
  static Future<bool> getQuickPlayVrAutoDetectFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_quickPlayVrAutoDetectFormatKey) ?? true;
  }

  static Future<void> setQuickPlayVrAutoDetectFormat(bool autoDetect) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quickPlayVrAutoDetectFormatKey, autoDetect);
  }

  /// Get whether to show VR format selection dialog before launching DeoVR
  static Future<bool> getQuickPlayVrShowDialog() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_quickPlayVrShowDialogKey) ?? true;
  }

  static Future<void> setQuickPlayVrShowDialog(bool showDialog) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quickPlayVrShowDialogKey, showDialog);
  }

  /// Clear all Quick Play VR settings
  static Future<void> clearQuickPlayVrSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_quickPlayVrModeKey);
    await prefs.remove(_quickPlayVrDefaultScreenTypeKey);
    await prefs.remove(_quickPlayVrDefaultStereoModeKey);
    await prefs.remove(_quickPlayVrAutoDetectFormatKey);
    await prefs.remove(_quickPlayVrShowDialogKey);
  }

  // Quick Play Cache Fallback Settings methods

  /// Get whether to try multiple torrents if first is not cached
  /// Default: false (stop on first uncached - current behavior)
  static Future<bool> getQuickPlayTryMultipleTorrents() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? false;
  }

  static Future<void> setQuickPlayTryMultipleTorrents(bool tryMultiple) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_quickPlayTryMultipleTorrentsKey, tryMultiple);
  }

  /// Get max number of torrents to try before giving up
  /// Default: 3, Range: 2-10
  static Future<int> getQuickPlayMaxRetries() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_quickPlayMaxRetriesKey) ?? 3;
  }

  static Future<void> setQuickPlayMaxRetries(int maxRetries) async {
    final prefs = await SharedPreferences.getInstance();
    // Clamp between 2 and 10
    await prefs.setInt(_quickPlayMaxRetriesKey, maxRetries.clamp(2, 10));
  }

  /// Clear all Quick Play Cache Fallback settings
  static Future<void> clearQuickPlayCacheFallbackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_quickPlayTryMultipleTorrentsKey);
    await prefs.remove(_quickPlayMaxRetriesKey);
  }

  // External Player Settings methods

  /// Get default player mode
  /// Returns 'debrify' (built-in player) by default
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<String> getDefaultPlayerMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultPlayerModeKey) ?? 'debrify';
  }

  /// Set default player mode
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<void> setDefaultPlayerMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultPlayerModeKey, mode);
  }

  /// Get preferred external player key
  /// Returns 'system_default' if not set
  static Future<String> getPreferredExternalPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_externalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred external player key
  static Future<void> setPreferredExternalPlayer(String playerKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_externalPlayerPreferredKey, playerKey);
  }

  /// Get custom external player path (for custom player option)
  static Future<String?> getCustomExternalPlayerPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_externalPlayerCustomPathKey);
  }

  /// Set custom external player path
  static Future<void> setCustomExternalPlayerPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_externalPlayerCustomPathKey);
    } else {
      await prefs.setString(_externalPlayerCustomPathKey, path);
    }
  }

  /// Get custom external player display name
  static Future<String?> getCustomExternalPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_externalPlayerCustomNameKey);
  }

  /// Set custom external player display name
  static Future<void> setCustomExternalPlayerName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_externalPlayerCustomNameKey);
    } else {
      await prefs.setString(_externalPlayerCustomNameKey, name);
    }
  }

  /// Get custom external player command template
  /// Should contain {url} placeholder, optionally {title}
  static Future<String?> getCustomExternalPlayerCommand() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_externalPlayerCustomCommandKey);
  }

  /// Set custom external player command template
  static Future<void> setCustomExternalPlayerCommand(String? command) async {
    final prefs = await SharedPreferences.getInstance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_externalPlayerCustomCommandKey);
    } else {
      await prefs.setString(_externalPlayerCustomCommandKey, command);
    }
  }

  // ============================================================
  // iOS External Player Settings
  // ============================================================

  /// Get preferred iOS external player key
  static Future<String> getPreferredIOSExternalPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_iosExternalPlayerPreferredKey) ?? 'vlc';
  }

  /// Set preferred iOS external player key
  static Future<void> setPreferredIOSExternalPlayer(String playerKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_iosExternalPlayerPreferredKey, playerKey);
  }

  /// Get iOS custom URL scheme template
  /// Should contain {url} placeholder, e.g., "myplayer://play?url={url}"
  static Future<String?> getIOSCustomSchemeTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_iosCustomSchemeTemplateKey);
  }

  /// Set iOS custom URL scheme template
  static Future<void> setIOSCustomSchemeTemplate(String? template) async {
    final prefs = await SharedPreferences.getInstance();
    if (template == null || template.isEmpty) {
      await prefs.remove(_iosCustomSchemeTemplateKey);
    } else {
      await prefs.setString(_iosCustomSchemeTemplateKey, template);
    }
  }

  // ============================================================
  // Linux External Player Settings
  // ============================================================

  /// Get preferred Linux external player key
  static Future<String> getPreferredLinuxExternalPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_linuxExternalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred Linux external player key
  static Future<void> setPreferredLinuxExternalPlayer(String playerKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_linuxExternalPlayerPreferredKey, playerKey);
  }

  /// Get Linux custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getLinuxCustomCommand() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_linuxCustomCommandKey);
  }

  /// Set Linux custom command template
  static Future<void> setLinuxCustomCommand(String? command) async {
    final prefs = await SharedPreferences.getInstance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_linuxCustomCommandKey);
    } else {
      await prefs.setString(_linuxCustomCommandKey, command);
    }
  }

  // ============================================================
  // Windows External Player Settings
  // ============================================================

  /// Get preferred Windows external player key
  static Future<String> getPreferredWindowsExternalPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_windowsExternalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred Windows external player key
  static Future<void> setPreferredWindowsExternalPlayer(String playerKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_windowsExternalPlayerPreferredKey, playerKey);
  }

  /// Get Windows custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getWindowsCustomCommand() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_windowsCustomCommandKey);
  }

  /// Set Windows custom command template
  static Future<void> setWindowsCustomCommand(String? command) async {
    final prefs = await SharedPreferences.getInstance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_windowsCustomCommandKey);
    } else {
      await prefs.setString(_windowsCustomCommandKey, command);
    }
  }

  /// Clear all external player settings
  static Future<void> clearExternalPlayerSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultPlayerModeKey);
    await prefs.remove(_externalPlayerPreferredKey);
    await prefs.remove(_externalPlayerCustomPathKey);
    await prefs.remove(_externalPlayerCustomNameKey);
    await prefs.remove(_externalPlayerCustomCommandKey);
  }

  // Debrify Player Default Settings

  /// Get default aspect ratio index for Flutter/mobile player
  /// 0=Contain, 1=Cover, 2=FitWidth, 3=FitHeight, 4=16:9, 5=4:3, 6=21:9, 7=1:1, 8=3:2, 9=5:4
  /// Default: 2 (Fit Width)
  static Future<int> getPlayerDefaultAspectIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_playerDefaultAspectIndexKey) ?? 2;
  }

  /// Set default aspect ratio index for Flutter/mobile player
  static Future<void> setPlayerDefaultAspectIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_playerDefaultAspectIndexKey, index);
  }

  /// Get default aspect ratio index for Android TV player
  /// 0=Fit, 1=Fill, 2=Zoom
  /// Default: 0 (Fit)
  static Future<int> getPlayerDefaultAspectIndexTv() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_playerDefaultAspectIndexTvKey) ?? 0;
  }

  /// Set default aspect ratio index for Android TV player
  static Future<void> setPlayerDefaultAspectIndexTv(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_playerDefaultAspectIndexTvKey, index);
  }

  /// Get night mode index (Android TV only)
  /// 0=Off, 1=Low, 2=Medium, 3=High, 4=Higher, 5=Extreme, 6=Max, 7=Sleeping Baby
  /// Default: 2 (Medium)
  static Future<int> getPlayerNightModeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_playerNightModeIndexKey) ?? 2;
  }

  /// Set night mode index (Android TV only)
  static Future<void> setPlayerNightModeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_playerNightModeIndexKey, index);
  }

  /// Get default subtitle language code
  /// Returns language code (e.g., 'en', 'es') or 'off' for disabled, null for no preference
  static Future<String?> getDefaultSubtitleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playerDefaultSubtitleLanguageKey);
  }

  /// Set default subtitle language code
  /// Pass language code (e.g., 'en', 'es'), 'off' for disabled, or null to clear preference
  static Future<void> setDefaultSubtitleLanguage(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultSubtitleLanguageKey);
    } else {
      await prefs.setString(_playerDefaultSubtitleLanguageKey, languageCode);
    }
  }

  /// Get default audio language code
  /// Returns language code (e.g., 'en', 'es') or null for no preference
  static Future<String?> getDefaultAudioLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playerDefaultAudioLanguageKey);
  }

  /// Set default audio language code
  /// Pass language code (e.g., 'en', 'es') or null to clear preference
  static Future<void> setDefaultAudioLanguage(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultAudioLanguageKey);
    } else {
      await prefs.setString(_playerDefaultAudioLanguageKey, languageCode);
    }
  }

  // IPTV Playlist Settings

  /// Get all saved IPTV playlists
  static Future<List<IptvPlaylist>> getIptvPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_iptvPlaylistsKey) ?? [];
    return jsonList.map((json) {
      try {
        return IptvPlaylist.fromJson(
          Map<String, dynamic>.from(jsonDecode(json) as Map),
        );
      } catch (e) {
        return null;
      }
    }).whereType<IptvPlaylist>().toList();
  }

  /// Save IPTV playlists
  static Future<void> setIptvPlaylists(List<IptvPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = playlists.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_iptvPlaylistsKey, jsonList);
  }

  /// Get default IPTV playlist ID
  static Future<String?> getIptvDefaultPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_iptvDefaultPlaylistKey);
  }

  /// Set default IPTV playlist ID
  static Future<void> setIptvDefaultPlaylist(String? playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    if (playlistId == null || playlistId.isEmpty) {
      await prefs.remove(_iptvDefaultPlaylistKey);
    } else {
      await prefs.setString(_iptvDefaultPlaylistKey, playlistId);
    }
  }

  /// Check if IPTV defaults have been initialized (to avoid re-adding after user deletes)
  static Future<bool> getIptvDefaultsInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_iptvDefaultsInitializedKey) ?? false;
  }

  /// Mark IPTV defaults as initialized
  static Future<void> setIptvDefaultsInitialized(bool initialized) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_iptvDefaultsInitializedKey, initialized);
  }

  // ============================================================================
  // Remote Control Settings
  // ============================================================================

  /// Get whether remote control feature is enabled
  static Future<bool> getRemoteControlEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_remoteControlEnabledKey) ?? true;
  }

  /// Set whether remote control feature is enabled
  static Future<void> setRemoteControlEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_remoteControlEnabledKey, enabled);
  }

  /// Get whether remote intro dialog has been shown
  static Future<bool> getRemoteIntroShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_remoteIntroShownKey) ?? false;
  }

  /// Set whether remote intro dialog has been shown
  static Future<void> setRemoteIntroShown(bool shown) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_remoteIntroShownKey, shown);
  }

  /// Get TV device name for remote control (TV only)
  static Future<String?> getRemoteTvDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_remoteTvDeviceNameKey);
  }

  /// Set TV device name for remote control (TV only)
  static Future<void> setRemoteTvDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remoteTvDeviceNameKey, name);
  }

  /// Get last connected device info (Mobile only)
  static Future<Map<String, dynamic>?> getRemoteLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_remoteLastDeviceKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Save last connected device info (Mobile only)
  static Future<void> setRemoteLastDevice(Map<String, dynamic> device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remoteLastDeviceKey, jsonEncode(device));
  }

  /// Clear last connected device info
  static Future<void> clearRemoteLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_remoteLastDeviceKey);
  }

  // ==========================================================================
  // Stremio TV Settings
  // ==========================================================================

  /// Get the Stremio TV rotation interval in minutes (default: 90)
  static Future<int> getStremioTvRotationMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stremioTvRotationMinutesKey) ?? 90;
  }

  /// Save the Stremio TV rotation interval in minutes
  static Future<void> setStremioTvRotationMinutes(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stremioTvRotationMinutesKey, value);
  }

  /// Get whether Stremio TV auto-refreshes catalogs (default: true)
  static Future<bool> getStremioTvAutoRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_stremioTvAutoRefreshKey) ?? true;
  }

  /// Save whether Stremio TV auto-refreshes catalogs
  static Future<void> setStremioTvAutoRefresh(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stremioTvAutoRefreshKey, value);
  }

  /// Get preferred quality for Stremio TV streams (default: 'auto')
  /// Values: 'auto', '720p', '1080p', '2160p'
  static Future<String> getStremioTvPreferredQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_stremioTvPreferredQualityKey) ?? 'auto';
  }

  /// Save preferred quality for Stremio TV streams
  static Future<void> setStremioTvPreferredQuality(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stremioTvPreferredQualityKey, value);
  }

  /// Get preferred debrid provider for Stremio TV (auto = first available)
  static Future<String> getStremioTvDebridProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_stremioTvDebridProviderKey) ?? 'auto';
  }

  /// Save preferred debrid provider for Stremio TV
  static Future<void> setStremioTvDebridProvider(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stremioTvDebridProviderKey, value);
  }

  /// Get max start position percent for Stremio TV (0 = always from beginning, -1 = no limit)
  static Future<int> getStremioTvMaxStartPercent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stremioTvMaxStartPercentKey) ?? -1;
  }

  /// Save max start position percent for Stremio TV
  static Future<void> setStremioTvMaxStartPercent(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stremioTvMaxStartPercentKey, value);
  }

  // ==========================================================================
  // Stremio TV Channel Favorites
  // ==========================================================================

  /// Check if a Stremio TV channel is favorited
  static Future<bool> isStremioTvChannelFavorited(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
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

    await prefs.setString(
        _stremioTvFavoriteChannelsKey, jsonEncode(favorites));
  }

  /// Get all favorite Stremio TV channel IDs
  static Future<Set<String>> getStremioTvFavoriteChannelIds() async {
    final prefs = await SharedPreferences.getInstance();
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
