import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:convert';
import 'debrid_service.dart';
import 'iptv_channel_order.dart';
import 'iptv_media_store.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_credential_facade.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/profile_authorization.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/tvos_recovery_limits.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import 'secret_vault.dart';
import '../models/iptv_playlist.dart';
import '../models/indexer_manager_config.dart';
import '../models/quick_play_rules.dart';
import '../models/sidebar_configuration.dart';
import '../models/stremio_addon.dart';
import '../models/webdav_item.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/tv_hero_artwork_quality.dart';
import '../models/tracking_source.dart';
import '../utils/json_isolate.dart';
import '../utils/platform_util.dart';
import 'tracking_scrobble_preferences.dart';
import 'playlist_dedupe_key.dart';
import 'webdav_sync/webdav_sync_hot_merge.dart';
import 'webdav_sync/webdav_sync_library_models.dart';
import 'webdav_sync/webdav_sync_tombstones.dart';

/// Which ambient-trailer surface a sound/volume preference belongs to.
///
/// A television now has both: the Home board's hero and the Showcase detail
/// page. They are separate preferences because they are separate experiences —
/// a muted Home hero should not mute a detail page you opened deliberately.
enum AmbientTrailerSurface { homeHero, detail }

/// Artwork orientation for TITLE cards on the Home layouts: portrait 2:3
/// posters or landscape 16:9 backdrops. Favourites, channel, and playlist
/// rows keep their own geometry — a station logo or folder is not a title.
/// Promenade is landscape by design and ignores the portrait setting.
enum HomeCardOrientation { portrait, landscape }

/// How the Android TV UI is rastered — see
/// [StorageService.getTvRenderQuality]. Three states, not a switch: the
/// automatic branch is the ABSENCE of the stored pref, because that absence is
/// what lets MainActivity keep making the device-capability call.
enum TvRenderQuality {
  /// Let MainActivity decide (GLES2-class hardware gets the 720p buffer).
  auto,

  /// Always raster at the panel's own resolution.
  sharp,

  /// Always raster at ~720p and let the TV's scaler upscale.
  fast,
}

class StorageService {
  static const String _explicitlyWatchedSeriesKey =
      'explicitly_watched_series_v1';
  static const String trackingScrobbleTargetsKey =
      TrackingScrobblePreferences.key;
  static const String watchProgressSourceKey = 'watch_progress_source';
  static const String homeTickSourcesKey = 'home_tick_sources';

  /// Invalidates policy consumers that keep an in-memory snapshot.
  static final ValueNotifier<int> trackingSourceRevision = ValueNotifier(0);

  /// Tracker/account watched-title invalidation. Kept separate from local
  /// playback so finishing an episode never reloads entire remote histories.
  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier(0);

  /// Local movie, episode, and derived-series completion invalidation.
  static final ValueNotifier<int> localCompletionRevision = ValueNotifier(0);

  /// The tracker snapshots are each stored as one JSON object containing every
  /// show. Serializing their read/modify/write cycle prevents two concurrent
  /// show refreshes from both reading the same old object and dropping whichever
  /// write finishes first.
  static final Lock _episodeTrackerSnapshotWriteLock = Lock();

  static Future<bool> profileAllowsAdultContent() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return true;
    }
    try {
      final scope = ProfileRuntime.capture();
      final profile = await ProfileBootstrap.registry.getProfile(
        scope.profileId,
      );
      return profile?.allows(ProfileFeature.allowAdultContent) == true;
    } catch (_) {
      return false;
    }
  }

  // ── Update-aware defaults ─────────────────────────────────────────────
  //
  // "Default" in this app has always meant "what an unset pref falls back
  // to" — which never reaches users who installed before a redesign. The
  // defaults GENERATION makes a flagship-look change reach them once:
  // on the first launch at a new generation, every look pref the user
  // NEVER wrote adopts the current bundle; every stored key — an explicit
  // choice, since all these setters write unconditionally — is untouched.
  // After migration the adopted values are stored too, so switching away
  // later sticks forever.
  //
  // Generation 1 (2026-08): the Spotlight era — Spotlight theme, Showcase
  // details, Spotlight TV home, pill rails on TV and desktop/tablet.
  // (text_brightness is deliberately absent: its unset default is already
  // the Look's value.)
  //
  // Generation 2 (2026-08): ambient trailers on, everywhere. Both surfaces
  // used to default by form factor — the hero off on phones and tablets,
  // the detail backdrop off on televisions — so most installs only ever saw
  // one of them. Both now default on for every device, and this generation
  // carries that to installs already in the field.
  //
  // Generation 3 (2026-08): Debrify TV joins the flagship bundle. Installs
  // wearing the Spotlight THEME (via the Look or a custom mix) adopt the
  // rail+stage layout; every other install keeps the grid it has always had.
  //
  // To roll out a future flagship look: bump the generation, append its
  // bundle under a `gen < N` block below.
  static const int _currentDefaultsGeneration = 3;
  static const String _defaultsGenerationKey = 'defaults_generation';

  /// MUST run before [TextBrightnessController.warm] / theme warms in
  /// `main()`: the first frame has to already be the migrated look.
  static Future<void> migrateDefaultsGeneration() async {
    final prefs = await ProfilePreferences.instance();
    final gen = prefs.getInt(_defaultsGenerationKey) ?? 0;
    if (gen >= _currentDefaultsGeneration) return;
    if (gen < 1) {
      // Dormant prefs are written too (desktop pill on a phone, TV home
      // style off-TV): harmless where they don't apply, correct if the
      // device class — or a window size — ever changes.
      //
      // The theme and its `detail_theme` mirror move as a PAIR, in the
      // controller's write-through order (mirror first — old builds read
      // only the mirror, and Showcase resolves its palette from it). The
      // pairing also means an explicit legacy pick (app_theme stored, no
      // mirror by design) keeps its details page untouched.
      if (!prefs.containsKey(_appThemeKey)) {
        if (!prefs.containsKey(_detailThemeKey)) {
          await prefs.setString(_detailThemeKey, 'spotlight');
        }
        await prefs.setString(_appThemeKey, 'spotlight');
      }
      const bundle = <String, String>{
        _detailPageStyleKey: 'showcase',
        _tvHomeStyleKey: 'spotlight',
        _tvSidebarStyleKey: 'pill',
        _desktopSidebarStyleKey: 'pill',
      };
      for (final entry in bundle.entries) {
        if (!prefs.containsKey(entry.key)) {
          await prefs.setString(entry.key, entry.value);
        }
      }
    }
    if (gen < 2) {
      // Both ambient trailer surfaces, for installs whose form factor used to
      // default one of them off. An explicit off — the toggles write
      // unconditionally, so a stored `false` is always a real choice — is left
      // alone: this turns trailers on for people who never had an opinion, not
      // for people who said no.
      const trailers = <String, bool>{
        'home_hero_trailer_enabled': true,
        'detail_trailer_autoplay_enabled': true,
      };
      for (final entry in trailers.entries) {
        if (!prefs.containsKey(entry.key)) {
          await prefs.setBool(entry.key, entry.value);
        }
      }
    }
    if (gen < 3) {
      // Debrify TV joins the flagship bundle. Raw prefs only — this runs
      // before any mirror is warmed, so `app_theme` is read directly rather
      // than through `appThemeCached`. The gen<1 block above has already
      // written `app_theme` for anyone who never chose, including a fresh
      // install, so this read is never against an absent key on a migrated
      // install.
      //
      // NOT unconditional the way generation 1 was: this key has never
      // existed, so `!containsKey` is true for every install on earth, and a
      // blanket 'spotlight' would restyle every Classic user AND flip their
      // Presets picker to Custom (Classic pins this key). The proxy is the
      // THEME, not Look activity — a Custom mix that kept the Spotlight
      // theme adopts the layout the theme implies; everyone else keeps grid.
      if (!prefs.containsKey(_debrifyTvStyleKey)) {
        final theme = prefs.getString(_appThemeKey);
        await prefs.setString(
          _debrifyTvStyleKey,
          theme == 'spotlight' ? 'spotlight' : 'grid',
        );
      }
    }
    await prefs.setInt(_defaultsGenerationKey, _currentDefaultsGeneration);
  }

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
  static const String _rdSkipBlockedTorrentsKey = 'rd_skip_blocked_torrents';
  static const String _torboxIntegrationEnabledKey =
      'torbox_integration_enabled';
  static const String _torboxHiddenFromNavKey = 'torbox_hidden_from_nav';
  static const String _premiumizeApiKey = 'premiumize_api_key';
  static const String _premiumizeIntegrationEnabledKey =
      'premiumize_integration_enabled';
  static const String _premiumizePostTorrentActionKey =
      'premiumize_post_torrent_action';
  static const String _premiumizeCacheCheckPref =
      'premiumize_check_cache_before_search';
  static const String _premiumizeHiddenFromNavKey =
      'premiumize_hidden_from_nav';
  static const String _allDebridApiKey = 'alldebrid_api_key';
  static const String _allDebridIntegrationEnabledKey =
      'alldebrid_integration_enabled';
  static const String _allDebridPostTorrentActionKey =
      'alldebrid_post_torrent_action';
  static const String _allDebridHiddenFromNavKey = 'alldebrid_hidden_from_nav';
  static const String _pikpakHiddenFromNavKey = 'pikpak_hidden_from_nav';
  static const String _postTorrentActionKey = 'post_torrent_action';
  static const String _torboxPostTorrentActionKey =
      'torbox_post_torrent_action';
  static const String _pikpakPostTorrentActionKey =
      'pikpak_post_torrent_action';
  static const String _batteryOptStatusKey =
      'battery_opt_status_v1'; // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _playbackStateKey = 'playback_state_v1';
  static const String _continueWatchingKey = 'continue_watching_v1';
  static const String localSeriesCompletionStateKey =
      'local_series_completion_v1';
  static const String localSeriesCalendarCheckedAtKey =
      'local_series_completion_calendar_checked_at_v1';
  static const String localSeriesCalendarAttemptedAtKey =
      'local_series_completion_calendar_attempted_at_v1';
  static const String _finishedMoviesKey = 'finished_movies_v1';
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
  // Debrify TV playback filters. Quality is matched on the torrent NAME
  // (applied when a channel's cache is read); size is matched on the real
  // per-FILE byte count after the debrid provider returns its file list —
  // per-file sizes are per-episode, so packs need no series/movie detection.
  static const String _debrifyTvFilterQualitiesKey =
      'debrify_tv_filter_qualities';
  static const String _debrifyTvFilterSizesKey = 'debrify_tv_filter_sizes';

  // "You're using an external player" notice shown before Debrify TV hands a
  // stream to another app. Dismissible forever, because the trade-off it
  // explains (one title, no channel rotation) never changes.
  static const String _debrifyTvExternalNoticeDismissedKey =
      'debrify_tv_external_notice_dismissed';

  // Home page default keys
  static const String _homeDefaultSourceTypeKey = 'home_default_source_type';
  static const String _homeDefaultAddonUrlKey = 'home_default_addon_url';
  static const String _homeDefaultCatalogIdKey = 'home_default_catalog_id';
  static const String _homeDefaultTraktListTypeKey =
      'home_default_trakt_list_type';
  static const String _homeDefaultTraktContentTypeKey =
      'home_default_trakt_content_type';
  static const String _homeHideProviderCardsKey = 'home_hide_provider_cards';
  static const String _homeContinueWatchingEnabledKey =
      'home_continue_watching_enabled';
  static const String _homeCwHoldToQuickPlayKey = 'home_cw_hold_to_quick_play';
  static const String _homeCwMergedRowsKeyPrefix = 'home_cw_merge_';
  static const String _homeFavoritesOpenFolderKey =
      'home_favorites_open_folder';
  static const String _homeCardOrientationKey = 'home_card_orientation';
  static const String _homeHideCardTitlesAndRatingsKey =
      'home_hide_card_titles_and_ratings';
  static const String _homeHideCatalogAddonNamesKey =
      'home_hide_catalog_addon_names';
  static const String _supportRemoteConfigCacheKey =
      'support_remote_config_cache_v1';
  static const String _dismissedDonationCampaignIdsKey =
      'dismissed_donation_campaign_ids_v1';

  // Startup settings
  static const String _startupAutoLaunchEnabledKey =
      'startup_auto_launch_enabled';
  static const String _startupChannelIdKey = 'startup_channel_id';
  static const String _startupStremioTvChannelIdKey =
      'startup_stremio_tv_channel_id';
  static const String _startupModeKey =
      'startup_mode'; // 'channel', 'stremio_tv', 'playlist', 'continue_watching', 'trakt_continue_watching_movies', or 'trakt_continue_watching_shows'
  static const String _startupPlaylistItemIdKey = 'startup_playlist_item_id';
  static const String _startupContinueWatchingItemIdKey =
      'startup_continue_watching_item_id';
  static const String _startupTraktContinueWatchingMovieIdKey =
      'startup_trakt_continue_watching_movie_id';
  static const String _startupTraktContinueWatchingShowIdKey =
      'startup_trakt_continue_watching_show_id';

  // Reddit settings
  static const String _redditAccessTokenKey = 'reddit_access_token';
  static const String _redditRefreshTokenKey = 'reddit_refresh_token';
  static const String _redditUsernameKey = 'reddit_username';
  static const String _redditEnabledKey = 'reddit_enabled';
  static const String _redditHiddenFromNavKey = 'reddit_hidden_from_nav';
  static const String _redditLastSubredditKey = 'reddit_last_subreddit';
  static const String _redditRecentSubredditsKey = 'reddit_recent_subreddits';
  static const String _redditAllowNsfwKey = 'reddit_allow_nsfw';
  static const String _redditFavoriteSubredditsKey =
      'reddit_favorite_subreddits';
  static const String _redditDefaultSubredditKey = 'reddit_default_subreddit';
  // Lemmy settings
  static const String _lemmyInstanceKey = 'lemmy_instance';
  static const String _lemmyAllowNsfwKey = 'lemmy_allow_nsfw';
  static const String _lemmyFavoriteCommunitiesKey =
      'lemmy_favorite_communities';
  static const String _lemmyDefaultCommunityKey = 'lemmy_default_community';
  // YouTube settings
  static const String _youtubeMaxHeightKey = 'youtube_max_height';
  // Network tuning (Debrify player). 'standard' = leave the player's own
  // defaults completely untouched — see NetworkTuning.
  static const String _networkConnectPatienceKey = 'network_connect_patience';
  static const String _iptvDecoderModeKey = 'iptv_decoder_mode';
  static const String _networkBufferSizeKey = 'network_buffer_size';
  static const String _updateAutoCheckEnabledKey = 'update_auto_check_enabled';
  static const String _updateIgnoredVersionKey = 'update_ignored_version';

  // External Player settings
  // Default player mode: 'debrify' (app player), 'external' (external player), 'deovr' (DeoVR on Android)
  static const String _defaultPlayerModeKey = 'default_player_mode';
  static const String _externalPlayerPreferredKey = 'external_player_preferred';
  static const String _externalPlayerCustomPathKey =
      'external_player_custom_path';
  static const String _externalPlayerCustomNameKey =
      'external_player_custom_name';
  static const String _externalPlayerCustomCommandKey =
      'external_player_custom_command';
  // iOS External Player settings
  static const String _iosExternalPlayerPreferredKey =
      'ios_external_player_preferred';
  static const String _iosCustomSchemeTemplateKey =
      'ios_custom_scheme_template';
  // Linux External Player settings
  static const String _linuxExternalPlayerPreferredKey =
      'linux_external_player_preferred';
  static const String _linuxCustomCommandKey = 'linux_custom_command';
  // Windows External Player settings
  static const String _windowsExternalPlayerPreferredKey =
      'windows_external_player_preferred';
  static const String _windowsCustomCommandKey = 'windows_custom_command';

  // Debrify Player default settings
  static const String _playerDefaultAspectIndexKey =
      'player_default_aspect_index';
  static const String _playerDefaultAspectIndexTvKey =
      'player_default_aspect_index_tv';
  static const String _playerNightModeIndexKey = 'player_night_mode_index';
  static const String _playerSystemAudioEffectsKey =
      'player_system_audio_effects';
  static const String _playerStartPortraitKey = 'player_start_portrait';
  static const String _movieCompletionThresholdKey =
      'movie_completion_threshold';
  static const String _episodeCompletionThresholdKey =
      'episode_completion_threshold';
  static const String _playbackCompletionMigrationGenerationKey =
      'playback_completion_migration_generation';
  static const int _currentPlaybackCompletionMigrationGeneration = 1;
  static const String _resumeGhostPurgeGenerationKey =
      'resume_ghost_purge_generation';
  static const int _currentResumeGhostPurgeGeneration = 1;
  static const String _androidVideoRendererModeKey =
      'android_video_renderer_mode';
  static const String _androidVideoRendererGpuMigrationKey =
      'android_video_renderer_gpu_migration_v1';
  static const String _tvosForceSoftwareDecodeKey =
      'tvos_force_software_decode';
  static const String _audioPassthroughKey = 'player_audio_passthrough';
  static const String _appleMultichannelAudioKey =
      'player_apple_multichannel_audio';
  static const String _tvosForceStereoAudioKey = 'tvos_force_stereo_audio_v1';
  static const String _tvosLegacyAudioOutputKey = 'tvos_legacy_audio_output_v1';
  static const String _uiSoundsKey = 'ui_sounds';
  static const String _uiHapticsKey = 'ui_haptics';
  static const String _subtitleAutoSyncKey = 'subtitle_auto_sync_enabled';
  static const String _playerDefaultSubtitleLanguageKey =
      'player_default_subtitle_language';
  static const String _playerDefaultAudioLanguageKey =
      'player_default_audio_language';
  static const String _skipSegmentsEnabledKey = 'skip_segments_enabled';
  static const String _skipSegmentProviderKey = 'skip_segment_provider';

  /// Completion thresholds selectable in Settings → Playback. A lower bound
  /// avoids treating a brief accidental play as watched; 95% still lets users
  /// finish a title without waiting through every trailing credit frame.
  static const List<int> localCompletionThresholdOptions = <int>[
    50,
    60,
    70,
    75,
    80,
    85,
    90,
    95,
  ];
  static const int defaultLocalCompletionThreshold = 80;

  /// Stable provider identifier persisted by the Playback settings page.
  /// Kept here rather than using a display label so future provider names can
  /// change without migrating preferences.
  static const String skipSegmentProviderAuto = 'auto';
  static const String skipSegmentProviderSkipDb = 'skipdb';
  static const String skipSegmentProviderIntroDb = 'introdb';
  static const String skipSegmentProviderTheIntroDb = 'theintrodb';
  static const Set<String> _supportedSkipSegmentProviders = <String>{
    skipSegmentProviderAuto,
    skipSegmentProviderSkipDb,
    skipSegmentProviderIntroDb,
    skipSegmentProviderTheIntroDb,
  };

  // IPTV settings
  static const String _iptvPlaylistsKey = 'iptv_playlists';
  static const String _iptvDefaultPlaylistKey = 'iptv_default_playlist';
  static const String _iptvDefaultsInitializedKey = 'iptv_defaults_initialized';
  static const String _iptvLastLiveChannelKey = 'iptv_last_live_channel';

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
  static const String _pikpakTorrentsFolderIdKey = 'pikpak_torrents_folder_id';
  static const String _pikpakTvFolderIdKey = 'pikpak_tv_folder_id';
  static const String _webDavEnabledKey = 'webdav_enabled';
  static const String _webDavHiddenFromNavKey = 'webdav_hidden_from_nav';
  static const String _webDavBaseUrlKey = 'webdav_base_url';
  static const String _webDavUsernameKey = 'webdav_username';
  static const String _webDavPasswordKey = 'webdav_password';
  static const String _webDavShowVideosOnlyKey = 'webdav_show_videos_only';
  static const String _webDavServersKey = 'webdav_servers_v1';
  static const String _webDavSelectedServerIdKey =
      'webdav_selected_server_id_v1';

  // TVMaze series mapping keys
  static const String _tvMazeSeriesMappingKey = 'tvmaze_series_mappings';

  // Playlist poster override storage key
  static const String _playlistPosterOverridesKey =
      'playlist_poster_overrides_v1';

  static const String _debrifyTvFavoriteChannelsKey =
      'debrify_tv_favorite_channels_v1';

  // Stremio TV settings
  static const String _stremioTvRotationMinutesKey =
      'stremio_tv_rotation_minutes';
  static const String _stremioTvSeriesRotationMinutesKey =
      'stremio_tv_series_rotation_minutes';
  static const String _stremioTvAutoRefreshKey = 'stremio_tv_auto_refresh';
  static const String _stremioTvFavoriteChannelsKey =
      'stremio_tv_favorite_channels_v1';
  static const String _stremioTvPreferredQualityKey =
      'stremio_tv_preferred_quality';
  static const String _stremioTvDebridProviderKey =
      'stremio_tv_debrid_provider';
  static const String _stremioTvMaxStartPercentKey =
      'stremio_tv_max_start_percent';
  static const String _stremioTvRandomEpisodesKey =
      'stremio_tv_random_episodes';
  static const String _stremioTvLocalCatalogsKey =
      'stremio_tv_local_catalogs_v1';
  static const String _stremioTvCatalogRepoUrlsKey =
      'stremio_tv_catalog_repo_urls_v1';
  static const String _stremioTvHideNowPlayingKey =
      'stremio_tv_hide_now_playing';
  static const String _stremioTvTorrentsFirstKey = 'stremio_tv_torrents_first';

  static const String _playlistKey = 'user_playlist_v1';
  static const String _playlistViewModesKey = 'playlist_view_modes_v1';
  static const String _playlistFavoritesKey = 'playlist_favorites_v1';
  static const String _myWatchlistKey =
      TvOsRecoveryLimits.myWatchlistPreferenceKey;
  static const String _onboardingCompleteKey = 'initial_setup_complete_v1';

  // Torrent Search History
  static const String _torrentSearchHistoryKey = 'torrent_search_history_v1';
  static const String _torrentSearchHistoryEnabledKey =
      'torrent_search_history_enabled';

  // Default Torrent Filter Settings
  static const String _defaultFilterQualitiesKey =
      'default_filter_qualities_v1';
  static const String _defaultFilterRipSourcesKey =
      'default_filter_rip_sources_v1';
  static const String _defaultFilterLanguagesKey =
      'default_filter_languages_v1';
  static const String _defaultFilterSizesKey = 'default_filter_sizes_v1';
  static const String _defaultFilterDynamicRangesKey =
      'default_filter_dynamic_ranges_v1';
  static const String _quickPlayHonorsFiltersKey =
      'quick_play_honors_filters_v1';

  // Default Torrent Provider Settings
  // Values: 'none' (ask every time), 'torbox', 'debrid', 'pikpak'
  static const String _defaultTorrentProviderKey =
      'default_torrent_provider_v1';
  static const String _indexerManagerConfigsKey = 'indexer_manager_configs_v1';

  // Quick Play VR Settings
  // VR Player Mode: 'disabled' (always regular player), 'auto' (detect VR content), 'always' (always use DeoVR)
  static const String _quickPlayVrModeKey = 'quick_play_vr_mode';
  static const String _quickPlayVrDefaultScreenTypeKey =
      'quick_play_vr_default_screen_type';
  static const String _quickPlayVrDefaultStereoModeKey =
      'quick_play_vr_default_stereo_mode';
  static const String _quickPlayVrAutoDetectFormatKey =
      'quick_play_vr_auto_detect_format';
  static const String _quickPlayVrShowDialogKey = 'quick_play_vr_show_dialog';

  // Quick Play Cache Fallback Settings
  // When enabled, if first torrent is not cached, try next torrents until one works
  static const String _quickPlayTryMultipleTorrentsKey =
      'quick_play_try_multiple_torrents';
  static const String _quickPlayMaxRetriesKey = 'quick_play_max_retries';
  static const String _quickPlayMovieRulesKey = 'quick_play_movie_rules_v2';
  static const String _quickPlaySeriesRulesKey = 'quick_play_series_rules_v2';
  static const String _playButtonModeKey = 'play_button_mode';

  // Series auto-pin: on a series play with no pinned source, search packs
  // first (complete series → season pack), and pin whatever source plays so
  // subsequent episode plays go straight through the bound path.
  /// LEGACY MIRROR ONLY. Written by [setQuickPlayRules] to carry
  /// `preferSeriesPacks` for downgrade builds, and read once by
  /// [_quickPlayRulesFromPrefs] to migrate pre-v2 profiles. Nothing on the live
  /// playback path may read it — see [_seriesAutoPinOnPlayKey].
  static const String _autoBindSeriesPacksKey =
      'auto_bind_series_packs_on_play';

  /// Whether a series play pins the source that played. Split out of
  /// [_autoBindSeriesPacksKey] because that key doubles as the legacy mirror of
  /// `preferSeriesPacks`: turning OFF "Prefer season packs" in Quick Play also
  /// silently disabled all series auto-pinning, so Smart mode never found a pin
  /// and Quick Play lost its fast path. Deliberately does NOT inherit the old
  /// key's value — a `false` there was the packs toggle bleeding through, never
  /// an auto-pin choice (no UI ever wrote it directly).
  static const String _seriesAutoPinOnPlayKey = 'series_auto_pin_on_play';

  // Trakt settings
  static const String _traktAccessTokenKey = 'trakt_access_token';
  static const String _traktRefreshTokenKey = 'trakt_refresh_token';
  static const String _traktUsernameKey = 'trakt_username';
  static const String _traktTokenExpiryKey = 'trakt_token_expiry';

  // Simkl settings. No refresh-token/expiry keys — PIN-issued Simkl tokens
  // don't expire (see SimklService).
  static const String _simklAccessTokenKey = 'simkl_access_token';
  static const String _simklUsernameKey = 'simkl_username';

  // MDBList settings. Auth is a single API key (from mdblist.com/preferences),
  // so there's no token/expiry — just the key and a cached display username.
  static const String _mdblistApiKeyKey = 'mdblist_api_key';
  static const String _mdblistUsernameKey = 'mdblist_username';

  // Remote Control Settings
  static const String _remoteControlEnabledKey = 'remote_control_enabled';
  static const String _remoteIntroShownKey = 'remote_intro_shown';
  static const String _remoteTvDeviceNameKey = 'remote_tv_device_name';
  static const String _remoteLastDeviceKey = 'remote_last_device';

  static const int _debrifyTvRandomStartPercentDefault = 20;
  static const int _debrifyTvRandomStartPercentMin = 10;
  static const int _debrifyTvRandomStartPercentMax = 90;

  static Future<String?> getApiKey({bool forRemoteTransfer = false}) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _apiKeyKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _apiKeyKey);
  }

  static Future<bool> hasRealDebridCredential() =>
      _credentialConfigured(_apiKeyKey, () => getApiKey());

  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _apiKeyKey, apiKey);
  }

  static Future<void> deleteApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_apiKeyKey)) {
      await prefs.remove(_apiKeyKey);
    }
  }

  // Real-Debrid endpoint preference (for fallback to backup endpoint)
  static Future<String> getRdEndpoint() async {
    final prefs = await ProfilePreferences.instance();
    // Default to primary endpoint
    return prefs.getString(_rdEndpointKey) ??
        'https://api.real-debrid.com/rest/1.0';
  }

  static Future<void> saveRdEndpoint(String endpoint) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_rdEndpointKey, endpoint);
  }

  static Future<void> deleteRdEndpoint() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_rdEndpointKey);
  }

  // Torbox API key helpers
  static Future<String?> getTorboxApiKey({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _torboxApiKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _torboxApiKey);
  }

  static Future<bool> hasTorboxCredential() =>
      _credentialConfigured(_torboxApiKey, () => getTorboxApiKey());

  static Future<void> saveTorboxApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _torboxApiKey, apiKey);
  }

  static Future<void> deleteTorboxApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_torboxApiKey)) {
      await prefs.remove(_torboxApiKey);
    }
  }

  static Future<bool> getSeriesBrowserDenseView() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('series_browser_dense_view') ?? false;
  }

  static Future<void> setSeriesBrowserDenseView(bool dense) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('series_browser_dense_view', dense);
  }

  /// Route series & movies to the merged detail+episodes page (the Stremio-styled
  /// single screen) instead of the separate detail → episodes flow. On by
  /// default; can be turned off per-device via [setMergedSeriesPageEnabled].
  static Future<bool> getMergedSeriesPageEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('merged_series_page_enabled') ?? true;
  }

  static Future<void> setMergedSeriesPageEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('merged_series_page_enabled', enabled);
  }

  /// Use the in-app DPAD keyboard for text fields on TV (TvTextField) instead
  /// of the system IME, which can't be navigated with the remote on many
  /// devices (flutter/flutter#177360 — Chromecast/Google TV, some
  /// Philips/Samsung panels). On by default on Android TV. Apple TV defaults
  /// to its system keyboard; the Settings toggle still lets users opt into the
  /// Debrify keyboard.
  ///
  /// [tvKeyboardEnabledCached] mirrors the stored value for synchronous widget
  /// builds — warmed at startup (main.dart) and kept in sync by the setter.
  static bool tvKeyboardEnabledCached = !PlatformUtil.isTvOS;

  // Apple TV keyboard default, generation 1 (2026-08): disable the Debrify
  // keyboard once for every profile, including profiles whose user explicitly
  // enabled it in an older build. The generation is committed only after the
  // new value, so a failed/interrupted write retries safely next launch. Once
  // committed, [setTvKeyboardEnabled] is authoritative and later user changes
  // are never overwritten.
  static const int _currentTvosKeyboardDefaultGeneration = 1;
  static const String _tvosKeyboardDefaultGenerationKey =
      'tvos_keyboard_default_generation';

  static Future<bool> getTvKeyboardEnabled({
    @visibleForTesting bool? tvOs,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final runningOnTvOs = tvOs ?? PlatformUtil.isTvOS;
    final generation = prefs.getInt(_tvosKeyboardDefaultGenerationKey) ?? 0;
    if (runningOnTvOs && generation < _currentTvosKeyboardDefaultGeneration) {
      final disabled = await prefs.setBool('tv_keyboard_enabled', false);
      if (disabled) {
        await prefs.setInt(
          _tvosKeyboardDefaultGenerationKey,
          _currentTvosKeyboardDefaultGeneration,
        );
      }
    }
    tvKeyboardEnabledCached =
        prefs.getBool('tv_keyboard_enabled') ?? !runningOnTvOs;
    return tvKeyboardEnabledCached;
  }

  static Future<void> setTvKeyboardEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tv_keyboard_enabled', enabled);
    tvKeyboardEnabledCached = enabled;
  }

  /// Android TV screen size, as a percentage of the panel's native density.
  ///
  /// A 1080p TV at density 320 gives Flutter a 960x540 logical canvas, so
  /// every screen is drawn 2x and reads as "zoomed in" across a big panel.
  /// A value below 100 makes MainActivity report a proportionally smaller
  /// devicePixelRatio to the engine, which widens the logical canvas (80% ->
  /// 1200x675) so the same layouts fit more and draw smaller — no per-screen
  /// changes involved.
  ///
  /// Read natively from `flutter.tv_ui_scale_percent` BEFORE the Flutter
  /// engine is built, so a change only takes effect on the next cold start.
  /// Android TV only; ignored everywhere else.
  ///
  /// [kTvUiScaleDefault] is 90: at 100 the app reads noticeably larger than
  /// the TV apps people compare it to (Stremio's web-rendered UI lays out
  /// against a canvas far closer to 1920 than to 960), while 80 ran a touch
  /// small for the Canvas-era layouts — Medium is the out-of-the-box balance
  /// and both neighbours are one tap away. MUST stay in step with
  /// MainActivity's `computeUiScale` fallback.
  static const List<int> kTvUiScaleOptions = [100, 90, 80];
  static const int kTvUiScaleDefault = 90;

  static Future<int> getTvUiScalePercent() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getInt('tv_ui_scale_percent');
    return kTvUiScaleOptions.contains(stored) ? stored! : kTvUiScaleDefault;
  }

  static Future<void> setTvUiScalePercent(int percent) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt('tv_ui_scale_percent', percent);
  }

  /// Android TV rendering mode — whether the Flutter UI is rastered at the
  /// panel's own resolution or at a ~720p buffer the TV's scaler blows back
  /// up for free.
  ///
  /// GLES2-class boxes are fill-rate bound: the same build at 720p feels near
  /// native on hardware that judders at 1080p. MainActivity decides this in
  /// `computeRenderScale` and has always been able to be overridden by
  /// `flutter.tv_low_res_render` — there was simply no way to set it. This is
  /// that way.
  ///
  /// TRI-STATE, and the absence of the key is load-bearing: native reads it as
  /// `getBoolean(key, auto)` where `auto` IS the device decision, so
  /// [TvRenderQuality.auto] must REMOVE the key rather than write `false`.
  /// Writing `false` on a weak TV would strip the 720p subsidy off the very
  /// devices that need it — a silent, permanent regression on the hardware
  /// least able to absorb it.
  ///
  /// Read natively before the engine is built, so a change lands on the next
  /// cold start. Android TV only; ignored everywhere else.
  static const String _tvRenderQualityKey = 'tv_low_res_render';

  static Future<TvRenderQuality> getTvRenderQuality() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getBool(_tvRenderQualityKey);
    if (stored == null) return TvRenderQuality.auto;
    return stored ? TvRenderQuality.fast : TvRenderQuality.sharp;
  }

  static Future<void> setTvRenderQuality(TvRenderQuality quality) async {
    final prefs = await ProfilePreferences.instance();
    switch (quality) {
      case TvRenderQuality.auto:
        await prefs.remove(_tvRenderQualityKey);
      case TvRenderQuality.sharp:
        await prefs.setBool(_tvRenderQualityKey, false);
      case TvRenderQuality.fast:
        await prefs.setBool(_tvRenderQualityKey, true);
    }
  }

  /// What MainActivity ACTUALLY decided for the engine currently running —
  /// written natively on every launch (`renderScale < 0.999f`), so under
  /// [TvRenderQuality.auto] it's the only way to see which branch this TV
  /// landed on. Also the honest answer after a change that hasn't been cold-
  /// started into yet: the pref says what will happen, this says what is.
  ///
  /// Written on every ANDROID launch, phones included (the `putBoolean` sits
  /// outside any TV guard) — off TV `renderScale` stays 1.0, so a phone reads
  /// `false`, not null. Null means MainActivity never ran at all: iOS, macOS,
  /// desktop. Callers must treat null as "unknown", never as "full res".
  static Future<bool?> getTvLowResRenderActive() async {
    final device = await DevicePreferences.instance();
    return device.getBool(DevicePreferences.tvLowResRenderActiveKey);
  }

  static const String _tvHeroArtworkQualityKey = 'tv_hero_artwork_quality';

  /// Maximum decode quality for Home hero/stage artwork on Android TV and
  /// tvOS. Unknown values coerce to Automatic so a removed experimental mode
  /// can never strand an installation on an unsupported policy.
  static Future<TvHeroArtworkQuality> getTvHeroArtworkQuality() async {
    final prefs = await ProfilePreferences.instance();
    return TvHeroArtworkQuality.fromStorage(
      prefs.getString(_tvHeroArtworkQualityKey),
    );
  }

  static Future<void> setTvHeroArtworkQuality(
    TvHeroArtworkQuality quality,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_tvHeroArtworkQualityKey, quality.storageValue);
  }

  /// Show the new Stremio-styled Addons hub (single list + source/type filters,
  /// purple Discover theme, 1-click marketplace) instead of the classic two-tab
  /// Addons screen. On by default; can be turned off per-device via
  /// [setStremioAddonHubEnabled].
  static Future<bool> getStremioAddonHubEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('stremio_addon_hub_enabled') ?? true;
  }

  static Future<void> setStremioAddonHubEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('stremio_addon_hub_enabled', enabled);
  }

  /// Autoplay a trailer behind the detail-page backdrop (OTT-style), when the
  /// metadata addon provides one.
  ///
  /// **Defaults ON everywhere** (generation 2). Two earlier rules are retired
  /// here, and neither should be reintroduced without the reason returning:
  /// "exactly one ambient surface per platform" existed because the process
  /// has a single video output, which [VideoOutputLease] plus a covered
  /// trailer releasing its decoder now enforces directly; and the later
  /// hold-back of OFF-on-TV existed only so an existing box wouldn't start
  /// playing trailers on a page that never did, which the generation
  /// migration now handles deliberately rather than by omission.
  static Future<bool> getDetailTrailerAutoplayEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('detail_trailer_autoplay_enabled') ?? true;
  }

  static Future<void> setDetailTrailerAutoplayEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('detail_trailer_autoplay_enabled', enabled);
  }

  /// Ambient trailer in the hero surfaces — the Home board's spotlight and
  /// the Discover rail.
  ///
  /// **Defaults ON everywhere** (generation 2). This was once hard-off
  /// anywhere but a television, then a form-factor default that kept phones
  /// and tablets opted out on battery-and-cellular grounds. The hero is the
  /// Spotlight layout's centrepiece on every device now, so it starts on and
  /// the toggle in Settings is where a phone user turns it off. The stored
  /// value, once written, wins everywhere.
  static Future<bool> getHomeHeroTrailerEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('home_hero_trailer_enabled') ?? true;
  }

  static Future<void> setHomeHeroTrailerEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('home_hero_trailer_enabled', enabled);
  }

  /// Pref key for the ambient-trailer sound pair, resolved per platform.
  /// Resolves to exactly four keys, spelled out here because the returns
  /// below are interpolated and a grep for a literal name would otherwise
  /// find nothing: `home_hero_trailer_audio_enabled`,
  /// `home_hero_trailer_volume`, `detail_trailer_audio_enabled`,
  /// `detail_trailer_volume`. Any future backup allowlist, reset sweep or
  /// migration has to name all four — enumerating one surface silently drops
  /// the other platform's settings.
  /// Each ambient surface owns its own key even though only one of them can
  /// be live on a device: the TV hero/Discover stage keeps the legacy
  /// `home_hero_` pair (renaming would reset every TV install), the non-TV
  /// detail backdrop gets its own. That separation matters because the old
  /// Settings page offered the hero sound rows on EVERY platform — a phone
  /// user could store "sound off" for a hero that never rendered there, and
  /// with one shared key that dead value would now silently mute their detail
  /// backdrop. Per-surface keys make such writes unreadable instead, so
  /// non-TV starts at the defaults its backdrop has always used.
  ///
  /// Now selected by SURFACE rather than by platform. Picking by platform was
  /// sound while a television could only ever have the Home hero; with the
  /// Showcase detail page also playing trailers, a platform pick would have the
  /// detail backdrop silently reading the Home hero's sound and volume.
  static String _ambientTrailerKeyFor(
    AmbientTrailerSurface surface,
    String suffix,
  ) => switch (surface) {
    AmbientTrailerSurface.homeHero => 'home_hero_trailer_$suffix',
    AmbientTrailerSurface.detail => 'detail_trailer_$suffix',
  };

  /// Whether this platform's ambient trailer plays sound (false = video only).
  /// See [_ambientTrailerKey] for which surface that is. Note the IPTV live
  /// preview is a channel feed, not a trailer, and stays at full volume.
  static Future<bool> getAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
  ) async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_ambientTrailerKeyFor(surface, 'audio_enabled')) ??
        true;
  }

  static Future<void> setAmbientTrailerAudioEnabled(
    AmbientTrailerSurface surface,
    bool enabled,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _ambientTrailerKeyFor(surface, 'audio_enabled'),
      enabled,
    );
  }

  /// Ambient trailer volume, percent 10–100. Default 70 — audible but under
  /// the UI, and the level the detail backdrop has always run at. Same
  /// one-surface-per-platform scope as [getAmbientTrailerAudioEnabled].
  static Future<int> getAmbientTrailerVolume(
    AmbientTrailerSurface surface,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_ambientTrailerKeyFor(surface, 'volume')) ?? 70;
    return v.clamp(10, 100);
  }

  static Future<void> setAmbientTrailerVolume(
    AmbientTrailerSurface surface,
    int percent,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _ambientTrailerKeyFor(surface, 'volume'),
      percent.clamp(10, 100),
    );
  }

  /// Android TV: render ambient trailers on a native SurfaceView *under* a
  /// translucent Flutter surface (a hardware overlay plane — Flutter never
  /// composites the video frames) instead of a Flutter Texture. Default on;
  /// the toggle is the escape hatch back to the Texture path for boxes where
  /// the underlay misbehaves. MainActivity reads the same key natively (the
  /// surface mode is fixed at activity creation), so changes take effect on
  /// the next app start.
  static Future<bool> getTvTrailerUnderlayEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('tv_trailer_underlay_enabled') ?? true;
  }

  static Future<void> setTvTrailerUnderlayEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tv_trailer_underlay_enabled', enabled);
  }

  /// First-read-wins snapshot for engine selection. The native side decides
  /// the EFFECTIVE underlay mode at activity creation (user toggle AND device
  /// capability — GLES2-class GPUs can't afford the permanently-translucent
  /// surface, so MainActivity keeps them opaque) and persists it under
  /// `tv_trailer_underlay_effective` BEFORE the first Dart frame. Trust that
  /// over the raw toggle so both sides always agree — an underlay hole
  /// against an opaque Flutter surface would render a black region instead
  /// of video (and the reverse would silently fall back to Texture, which at
  /// least works). Restarting the app applies changes to both sides together.
  static bool? _tvTrailerUnderlaySession;
  static Future<bool> getTvTrailerUnderlayEnabledAtLaunch() async {
    if (_tvTrailerUnderlaySession != null) return _tvTrailerUnderlaySession!;
    final device = await DevicePreferences.instance();
    final effective = device.getBool(
      DevicePreferences.tvTrailerUnderlayEffectiveKey,
    );
    if (effective != null) {
      return _tvTrailerUnderlaySession = effective;
    }
    final prefs = await ProfilePreferences.instance();
    return _tvTrailerUnderlaySession =
        prefs.getBool('tv_trailer_underlay_enabled') ?? true;
  }

  @visibleForTesting
  static void debugResetTvTrailerUnderlaySession() {
    _tvTrailerUnderlaySession = null;
  }

  static Future<bool> getTorboxCacheCheckEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxCacheCheckPref) ?? false;
  }

  static Future<void> setTorboxCacheCheckEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxCacheCheckPref, enabled);
  }

  static Future<bool> getRealDebridIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_realDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setRealDebridIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_realDebridIntegrationEnabledKey, enabled);
  }

  static const String _phoneNavStyleKey = 'phone_nav_style';
  static const String _phoneNavBarIndicesKey = 'phone_nav_bar_indices';

  /// Phone navigation chrome: 'classic' (bottom bar, the default) or
  /// 'floating' (the glass button menu). TV and wide-desktop never read it.
  static Future<String> getPhoneNavStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_phoneNavStyleKey);
    return raw == 'floating' ? 'floating' : 'classic';
  }

  static Future<void> setPhoneNavStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _phoneNavStyleKey,
      style == 'floating' ? 'floating' : 'classic',
    );
  }

  static const String _tvHomeStyleKey = 'tv_home_style';

  /// Every shipping TV Home layout. 'canvas' is the product default;
  /// 'classic' is the original hero + scrolling rows. The rest are the
  /// alternate stages (see `_buildAtriumBoard` and friends in search_screen).
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one — or the long-removed 'shelf' — lands on 'canvas'
  /// rather than rendering nothing.
  static const Set<String> kTvHomeStyles = {
    'canvas',
    'classic',
    'atrium',
    'mosaic',
    'promenade',
    'deck',
    'tonight',
    'spotlight',
  };

  /// TV Home layout. Phone/desktop and the Search tab never read it.
  /// Synchronous mirror of `tvHomeStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String tvHomeStyleCached = 'canvas';

  static Future<String> getTvHomeStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_tvHomeStyleKey);
    return tvHomeStyleCached = kTvHomeStyles.contains(raw) ? raw! : 'canvas';
  }

  static Future<void> setTvHomeStyle(String style) async {
    final normalized = kTvHomeStyles.contains(style) ? style : 'canvas';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    tvHomeStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_tvHomeStyleKey, normalized);
  }

  static const String _debrifyTvStyleKey = 'debrify_tv_style';

  /// Every shipping Debrify TV layout. 'grid' is the historical default — the
  /// channel wall `build()` has always drawn; 'spotlight' is the standing
  /// rail + stage (list + sheet on phone). One key covers every device class:
  /// the style resolves its own layout per device, like `detail_page_style`.
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one lands on 'grid' rather than rendering nothing.
  static const Set<String> kDebrifyTvStyles = {'grid', 'spotlight'};

  /// Synchronous mirror of `debrify_tv_style`, kept so a Look can read the
  /// current value without an await. Every existing caller still goes through
  /// the async getter, which also refreshes this.
  static String debrifyTvStyleCached = 'grid';

  static Future<String> getDebrifyTvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvStyleKey);
    return debrifyTvStyleCached = kDebrifyTvStyles.contains(raw)
        ? raw!
        : 'grid';
  }

  static Future<void> setDebrifyTvStyle(String style) async {
    final normalized = kDebrifyTvStyles.contains(style) ? style : 'grid';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    debrifyTvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvStyleKey, normalized);
  }

  static const String _detailPageStyleKey = 'detail_page_style';

  /// Every value storage will persist for the merged details page look
  /// (Appearance → Details Page). Every known layout is accepted — a
  /// choice written by a newer build has to survive a downgrade rather than be
  /// silently rewritten to the default the first time an older build reads it.
  ///
  /// What a given BUILD can actually draw is a narrower set —
  /// `kDetailPageStylesShipped` in `screens/settings/detail_page_style_page.dart`
  /// — and dispatch/labels/picker all go through `effectiveDetailPageStyle`.
  static const Set<String> kDetailPageStyles = {
    'classic',
    'marquee',
    'dossier',
    'broadsheet',
    'stage',
    'filmstrip',
    'console',
    'vista',
    'monolith',
    'mosaic',
    'halo',
    'premiere',
    'showcase',
  };

  /// The layout a fresh install — and anyone who has never opened the picker —
  /// gets.
  ///
  /// **Console rather than Classic, and that is a deliberate change to what
  /// the app looks like out of the box.** Classic is the one layout that is
  /// deliberately unthemed: it paints its own literals and ignores the app
  /// theme entirely. With Classic as the default, picking an App Theme
  /// appeared to do nothing on the page most people judge the app by — the
  /// setting looked broken when it was working. A themed layout as the default
  /// is what makes it honest.
  ///
  /// This is the FALLBACK, so it moves everyone with no stored value — not
  /// just new installs, but every user who never opened the picker. That
  /// breadth is the point rather than a side effect; Classic is still one row
  /// away for anyone who wants it back.
  static const String kDetailPageStyleDefault = 'console';

  /// Synchronous mirror, warmed in main() before runApp: `MergedDetailScreen`
  /// picks its body in the first build, so an async-only read would paint the
  /// default for a frame and then re-lay-out the whole page.
  ///
  /// Normalizes toward [kDetailPageStyleDefault] on BOTH sides — an
  /// unrecognized value has to mean the default for the reader and the writer
  /// alike.
  static String detailPageStyleCached = kDetailPageStyleDefault;

  static Future<String> getDetailPageStyle() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_detailPageStyleKey);
    detailPageStyleCached = kDetailPageStyles.contains(value)
        ? value!
        : kDetailPageStyleDefault;
    return detailPageStyleCached;
  }

  static Future<void> setDetailPageStyle(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kDetailPageStyles.contains(value)
        ? value
        : kDetailPageStyleDefault;
    await prefs.setString(_detailPageStyleKey, normalized);
    detailPageStyleCached = normalized;
  }

  static const String _detailThemeKey = 'detail_theme';

  /// Every look the details page can wear (Appearance → Details Theme).
  ///
  /// Same contract as [kDetailPageStyles]: all values are accepted from day
  /// one so a theme written by a newer build survives a downgrade, and what a
  /// given BUILD can draw is the narrower `kDetailThemesShipped` in
  /// `screens/settings/detail_theme_page.dart`.
  ///
  /// The layout and the theme are orthogonal — one says where things are, the
  /// other what they look like.
  static const Set<String> kDetailThemes = {
    'signal',
    'noir',
    'broadsheet',
    'phosphor',
    'aurora',
    'concrete',
    'velvet',
    'blueprint',
    'broadcast',
    'sepia',
    'obsidian',
    'halo',
    'prestige',
    'deep_field',
    'graphite',
    'vault',
    'spectrum',
    'verdant',
    'frost',
    'cinemascope',
    // The five premium looks. Accepted here from the build that introduces
    // them, for the same downgrade reason as everything above: a value a newer
    // build wrote must survive being read by an older one, which normalizes it
    // to 'signal' rather than losing the key.
    'glass',
    'field',
    'hearth',
    'console',
    'reel',

    'spotlight',
  };

  /// Synchronous mirror, warmed in main() before runApp — the details page
  /// picks its theme in the first build, so an async-only read would paint
  /// Signal for a frame and then repaint the whole page.
  static String detailThemeCached = 'signal';

  static Future<String> getDetailTheme() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_detailThemeKey);
    detailThemeCached = kDetailThemes.contains(value) ? value! : 'signal';
    return detailThemeCached;
  }

  static Future<void> setDetailTheme(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kDetailThemes.contains(value) ? value : 'signal';
    await prefs.setString(_detailThemeKey, normalized);
    detailThemeCached = normalized;
  }

  static const String _appThemeKey = 'app_theme';
  static const String _themeOverridesKey = 'theme_overrides';

  /// The app-wide theme (Appearance → App Theme). `'legacy'` is the sentinel
  /// meaning "render today's app exactly" and is the default; any other
  /// accepted value is a [kDetailThemes] id applied app-wide.
  ///
  /// Unknown/removed ids normalize to `'legacy'` on BOTH sides — never to a
  /// random theme — so a value written by a newer build downgrades safely.
  ///
  /// Write-through contract (owned by `AppThemeController.select`): choosing a
  /// real app theme also mirrors the id into [_detailThemeKey], and the mirror
  /// is written FIRST — a crash between the two writes must leave an
  /// older-build-consistent view, and old builds only read `detail_theme`.
  static String appThemeCached = 'legacy';

  static Future<String> getAppTheme() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_appThemeKey);
    appThemeCached = (value == 'legacy' || kDetailThemes.contains(value))
        ? value!
        : 'legacy';
    return appThemeCached;
  }

  static Future<void> setAppTheme(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = (value == 'legacy' || kDetailThemes.contains(value))
        ? value
        : 'legacy';
    await prefs.setString(_appThemeKey, normalized);
    appThemeCached = normalized;
  }

  /// The user's per-token edits, as the raw JSON `ThemeOverrides` encodes.
  ///
  /// Kept as a string here rather than a parsed object so this layer stays free
  /// of the theme package — and because the only consumer that matters resolves
  /// it once, on the controller, and memoizes the result.
  ///
  /// Empty string means "no overrides", which is both the default and the fast
  /// path every theme resolution checks first.
  static String themeOverridesCached = '';

  static Future<String> getThemeOverrides() async {
    final prefs = await ProfilePreferences.instance();
    themeOverridesCached = prefs.getString(_themeOverridesKey) ?? '';
    return themeOverridesCached;
  }

  static Future<void> setThemeOverrides(String raw) async {
    final prefs = await ProfilePreferences.instance();
    // Publish the mirror BEFORE the await, like every other live-applied
    // preference here: the controller has already recomputed and notified off
    // this value, and a rebuild that raced the write must not read the old one.
    themeOverridesCached = raw;
    if (raw.isEmpty) {
      await prefs.remove(_themeOverridesKey);
    } else {
      await prefs.setString(_themeOverridesKey, raw);
    }
  }

  static const String _parentsGuideStyleKey = 'parents_guide_style';
  static const Set<String> kParentsGuideStyles = {'classic', 'compass'};

  /// Synchronous mirror used by the Parents Guide widget. Compass is the new
  /// default; Classic remains available as a zero-risk fallback in Appearance.
  static String parentsGuideStyleCached = 'compass';

  static Future<String> getParentsGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_parentsGuideStyleKey);
    parentsGuideStyleCached = kParentsGuideStyles.contains(value)
        ? value!
        : 'compass';
    return parentsGuideStyleCached;
  }

  static Future<void> setParentsGuideStyle(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = kParentsGuideStyles.contains(value) ? value : 'compass';
    await prefs.setString(_parentsGuideStyleKey, normalized);
    parentsGuideStyleCached = normalized;
  }

  static const String _iptvStyleKey = 'iptv_style';
  static const Set<String> _iptvStyles = {'command', 'edition', 'console'};

  /// Whether browsing IPTV channels may open the focused channel in the
  /// embedded side preview. This is on by default to preserve the shipped
  /// experience; users whose provider enforces a small connection limit can
  /// turn it off without affecting explicit fullscreen playback.
  static const String _iptvChannelPreviewEnabledKey =
      'iptv_channel_preview_enabled';

  static Future<bool> getIptvChannelPreviewEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvChannelPreviewEnabledKey) ?? true;
  }

  static Future<void> setIptvChannelPreviewEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvChannelPreviewEnabledKey, enabled);
  }

  /// IPTV cockpit look: 'command' (the shipped Command Center, the default),
  /// 'edition' (First Edition — editorial ink/serif) or 'console' (Master
  /// Control — black instrument). Only the TV/desktop cockpit reads it; the
  /// phone classic layout and the touch-tablet two-pane never do. Unknown or
  /// unset coerces to 'command' on BOTH read and write, so an old build
  /// downgrading past a newer value can never pin a look the reader treats
  /// as the exception.
  /// Synchronous mirror of `iptvStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String iptvStyleCached = 'command';

  static Future<String> getIptvStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvStyleKey);
    return iptvStyleCached = _iptvStyles.contains(raw) ? raw! : 'command';
  }

  static Future<void> setIptvStyle(String style) async {
    final normalized = _iptvStyles.contains(style) ? style : 'command';
    iptvStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iptvStyleKey, normalized);
  }

  // ── Player dock (touch/desktop transport controls) ──────────────────────
  //
  // Three independent prefs so any style works in any palette at any size;
  // bundling them into one "look" would only remove combinations. Palette and
  // size are inert under `classic`, whose values are still preserved so
  // switching to a styled dock restores the user's choices.
  //
  // Read once at player launch. Televisions never consult these — they build
  // `TvControls`, not `Controls`.
  static const String _playerDockStyleKey = 'player_dock_style';
  static const Set<String> _playerDockStyles = {
    'classic',
    'auto',
    'compact',
    'tiers',
    'cinema',
    // The value shipped before the arrangements became selectable. Still
    // accepted on read so existing installs keep the dock they chose; it
    // means the same thing 'auto' does.
    'two_tier',
  };

  static Future<String> getPlayerDockStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockStyleKey);
    return _playerDockStyles.contains(raw) ? raw! : 'classic';
  }

  static Future<void> setPlayerDockStyle(String style) async {
    final normalized = _playerDockStyles.contains(style) ? style : 'classic';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockStyleKey, normalized);
  }

  static const String _playerDockPaletteKey = 'player_dock_palette';
  static const Set<String> _playerDockPalettes = {
    'ultraviolet',
    'crimson',
    'aurum',
    'ice',
  };

  static Future<String> getPlayerDockPalette() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockPaletteKey);
    return _playerDockPalettes.contains(raw) ? raw! : 'ultraviolet';
  }

  static Future<void> setPlayerDockPalette(String palette) async {
    final normalized = _playerDockPalettes.contains(palette)
        ? palette
        : 'ultraviolet';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockPaletteKey, normalized);
  }

  static const String _playerDockSizeKey = 'player_dock_size';
  static const Set<String> _playerDockSizes = {
    'auto',
    'small',
    'medium',
    'large',
  };

  static Future<String> getPlayerDockSize() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playerDockSizeKey);
    return _playerDockSizes.contains(raw) ? raw! : 'auto';
  }

  static Future<void> setPlayerDockSize(String size) async {
    final normalized = _playerDockSizes.contains(size) ? size : 'auto';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playerDockSizeKey, normalized);
  }

  static const String _iptvPlayerGuideStyleKey = 'iptv_player_guide_style';
  static const Set<String> _iptvPlayerGuideStyles = {
    'classic',
    'glass',
    'edition',
    'console',
    'spotlight',
  };

  /// In-player IPTV guide look (zap banner, channel sheet, native guide
  /// overlay + dock): 'classic' (today's look, the default), 'glass'
  /// (Cinema Glass), 'edition' (Midnight Edition) or 'console' (Master
  /// Control). Both players read it once at launch — the Dart player via
  /// this getter, the native TV player via `flutter.iptv_player_guide_style`
  /// in FlutterSharedPreferences. Unknown or unset coerces to 'classic' on
  /// BOTH read and write, so an old build downgrading past a newer value can
  /// never pin a look the reader treats as the exception.
  static Future<String> getIptvPlayerGuideStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvPlayerGuideStyleKey);
    if (_iptvPlayerGuideStyles.contains(raw)) return raw!;
    // Never chosen: Apple TV gets its native idiom, everything else keeps
    // the shipped look. An explicit pick (either way) is stored and wins.
    return PlatformUtil.isTvOS ? 'spotlight' : 'classic';
  }

  static Future<void> setIptvPlayerGuideStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvPlayerGuideStyleKey,
      _iptvPlayerGuideStyles.contains(style) ? style : 'classic',
    );
  }

  static const String _playLoaderStyleKey = 'play_loader_style';
  static const Set<String> _playLoaderStyles = {'marquee', 'classic'};

  /// The look of the play → resolve loader: 'marquee' (the default — backdrop,
  /// logo art and a segmented stage rail) or 'classic' (the poster-and-
  /// checklist card this overlay shipped with). Unknown or unset coerces to
  /// 'marquee' on BOTH read and write, so a value written by a newer build can
  /// never pin a look this one cannot render.
  ///
  /// The play path reads it synchronously through
  /// [PlayLoaderStyleController.cached]; this getter is the warm source.
  static Future<String> getPlayLoaderStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playLoaderStyleKey);
    return _playLoaderStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setPlayLoaderStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _playLoaderStyleKey,
      _playLoaderStyles.contains(style) ? style : 'marquee',
    );
  }

  static const String _tvPlayerControlsStyleKey = 'tv_player_controls_style';
  static const Set<String> _tvPlayerControlsStyles = {
    'classic',
    'ott',
    'frost',
    'marquee',
    'broadcast',
    'pulse',
    'ticket',
  };

  /// Control skin for the NATIVE Android TV player: 'marquee' (editorial
  /// serif — the default), 'ott' (the Apple TV dock ported to Kotlin),
  /// 'classic' (the legacy Cinema Mode controls), or one of the other
  /// premium dock skins ('frost', 'broadcast', 'pulse', 'ticket'). Android TV only; tvOS runs the
  /// Flutter player and has nothing to choose. Read once per player launch — the native side via
  /// `ProfilePreferenceProjection.getString("tv_player_controls_style")`
  /// (falling back to `flutter.tv_player_controls_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'marquee' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getTvPlayerControlsStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_tvPlayerControlsStyleKey);
    return _tvPlayerControlsStyles.contains(raw) ? raw! : 'marquee';
  }

  static Future<void> setTvPlayerControlsStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _tvPlayerControlsStyleKey,
      _tvPlayerControlsStyles.contains(style) ? style : 'marquee',
    );
  }

  static const String _debrifyTvPlayerStyleKey = 'debrify_tv_player_style';
  static const Set<String> _debrifyTvPlayerStyles = {
    'classic',
    'network',
    'cinema',
    'guide',
    'spotlight',
    'prestige',
  };

  /// Playback-screen style for the NATIVE Debrify TV player
  /// (TorboxTvPlayerActivity): 'cinema' (poster + gilded spec line — the
  /// default), 'network' (broadcast lower-third), 'guide' (opaque
  /// broadcast band), 'spotlight' (frosted glass panel), 'prestige'
  /// (quiet serif identity), or 'classic' (the legacy ESPN-style bar +
  /// top marquee). Android TV only. Read once per player launch — the
  /// native side via
  /// `ProfilePreferenceProjection.getString("debrify_tv_player_style")`
  /// (falling back to `flutter.debrify_tv_player_style` in
  /// FlutterSharedPreferences). Unknown or unset coerces to 'cinema' on
  /// BOTH read and write so the two readers can never disagree about the
  /// default.
  static Future<String> getDebrifyTvPlayerStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvPlayerStyleKey);
    return _debrifyTvPlayerStyles.contains(raw) ? raw! : 'cinema';
  }

  static Future<void> setDebrifyTvPlayerStyle(String style) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _debrifyTvPlayerStyleKey,
      _debrifyTvPlayerStyles.contains(style) ? style : 'cinema',
    );
  }

  static const String _discoverLayoutKey = 'discover_layout';
  static const String _discoverDefaultSourceKey = 'discover_default_source';
  static const String _discoverLastSourceKey = 'discover_last_source';

  /// Special value for the Discover default-source setting. When selected,
  /// [getDiscoverLastSource] decides which source opens on the next visit.
  static const String discoverDefaultRememberLast = 'remember';

  static bool _isDiscoverSourceValue(String value) =>
      value == 'cw' ||
      value == 'trakt' ||
      value == 'simkl' ||
      value == 'mdblist' ||
      (value.startsWith('a:') && value.length > 2 && value.length <= 514);

  /// What Discover should show when opened. Unset defaults to remembering the
  /// last source, preserving the most useful behavior for existing installs.
  static Future<String> getDiscoverDefaultSource() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_discoverDefaultSourceKey);
    return value == discoverDefaultRememberLast ||
            (value != null && _isDiscoverSourceValue(value))
        ? value!
        : discoverDefaultRememberLast;
  }

  static Future<void> setDiscoverDefaultSource(String value) async {
    final normalized =
        value == discoverDefaultRememberLast || _isDiscoverSourceValue(value)
        ? value
        : discoverDefaultRememberLast;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverDefaultSourceKey, normalized);
  }

  /// The last source explicitly opened from Discover. A missing or malformed
  /// value safely falls back to Continue Watching.
  static Future<String> getDiscoverLastSource() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_discoverLastSourceKey);
    return value != null && _isDiscoverSourceValue(value) ? value : 'cw';
  }

  static Future<void> setDiscoverLastSource(String value) async {
    if (!_isDiscoverSourceValue(value)) return;
    final prefs = await ProfilePreferences.instance();
    if (prefs.getString(_discoverLastSourceKey) == value) return;
    await prefs.setString(_discoverLastSourceKey, value);
  }

  /// TV Discover layout: 'stage' (the focused title full-bleed with one bottom
  /// shelf, the default) or 'grid' (the detail rail beside a poster wall). Its
  /// own key, deliberately NOT shared with [getTvHomeStyle]: Home's Canvas
  /// switches rails with UP/DOWN and Discover's Stage owns a filter line —
  /// neither layout has the other's axis, so one pref governing both would
  /// promise a symmetry they can't keep. Phone/desktop never read it.
  ///
  /// Unset reads as 'stage', so users who never opened the picker move to it.
  /// Everything else that holds a pre-load placeholder for this pref must
  /// agree, or the UI paints one layout and then swaps: SearchScreen's
  /// `_discLayoutCached`, DiscoverLayoutPage, SettingsScreen.
  /// Synchronous mirror of `discoverLayout`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String discoverLayoutCached = 'stage';

  static Future<String> getDiscoverLayout() async {
    final prefs = await ProfilePreferences.instance();
    return discoverLayoutCached = prefs.getString(_discoverLayoutKey) == 'grid'
        ? 'grid'
        : 'stage';
  }

  /// Normalizes toward 'stage' on the same terms [getDiscoverLayout] does —
  /// an unrecognized value has to mean the default on BOTH sides, or writing
  /// one would silently pin the layout the reader treats as the exception.
  static Future<void> setDiscoverLayout(String layout) async {
    final normalized = layout == 'grid' ? 'grid' : 'stage';
    discoverLayoutCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverLayoutKey, normalized);
  }

  static const String _launchAnimationKey = 'launch_animation';
  // MUST stay in step with kLaunchIdents — an id missing here is silently
  // normalized back to the default, so the picker would appear not to save.
  static const Set<String> _launchAnimationValues = {
    'drop',
    'marquee',
    'prism',
    'horizon',
    'collider',
    'neon',
    'chrome',
    'monogram',
    'aperture',
    'blueprint',
    'ripple',
    'ember',
    'swiss',
    'origami',
    'anamorphic',
    'constellation',
    'silk',
    'rackfocus',
    'imprint',
    'frost',
    'trace',
  };

  /// Exposed so a test can assert this set and `kLaunchIdents` agree in BOTH
  /// directions — drift either way silently strands the pref on the default.
  @visibleForTesting
  static Set<String> get launchAnimationValues => _launchAnimationValues;

  /// Which launch ident the splash plays (Appearance → Launch Animation).
  /// Values are the ids in `widgets/launch/launch_ident.dart`; 'trace' (Trace)
  /// is the default, 'collider' and before it 'horizon' are the idents it
  /// replaced as such, and 'drop' is the original splash.
  ///
  /// [launchAnimationCached] mirrors it for SYNCHRONOUS reads: AppInitializer
  /// builds its splash in initState, before any async pref read could land.
  /// Warmed in main() before runApp and kept in sync by the setter.
  ///
  /// Normalizes toward the default on BOTH sides — an unrecognized value has
  /// to mean the default for the reader and the writer alike. Only installs
  /// that never CHOSE move when this changes: an explicit 'collider' is a
  /// stored value and keeps playing Collider.
  static String launchAnimationCached = 'trace';

  static Future<String> getLaunchAnimation() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_launchAnimationKey);
    launchAnimationCached = _launchAnimationValues.contains(value)
        ? value!
        : 'trace';
    return launchAnimationCached;
  }

  static Future<void> setLaunchAnimation(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _launchAnimationValues.contains(value) ? value : 'trace';
    await prefs.setString(_launchAnimationKey, normalized);
    launchAnimationCached = normalized;
  }

  static const String _launchIdentPaletteKey = 'launch_ident_palette';
  static const Set<String> _launchIdentPalettes = {'ident', 'theme'};

  /// Whether the launch ident wears its OWN colours or the app theme's
  /// (Appearance → Launch Animation).
  ///
  /// Defaults to `'ident'`, so nobody's splash changes until they ask. The
  /// ident's art direction — its geometry, its motion, its mark — is the same
  /// either way; only the room's colours move, and only where they stay
  /// legible (see `IdentPalette.fromTheme`).
  ///
  /// Mirrored synchronously for the same reason [launchAnimationCached] is:
  /// AppInitializer builds the splash in `initState`, before any async read
  /// could land.
  static String launchIdentPaletteCached = 'ident';

  static Future<String> getLaunchIdentPalette() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_launchIdentPaletteKey);
    launchIdentPaletteCached = _launchIdentPalettes.contains(value)
        ? value!
        : 'ident';
    return launchIdentPaletteCached;
  }

  static Future<void> setLaunchIdentPalette(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _launchIdentPalettes.contains(value) ? value : 'ident';
    // Mirror BEFORE the await: the picker rebuilds on the next frame and the
    // splash reads the mirror synchronously.
    launchIdentPaletteCached = normalized;
    await prefs.setString(_launchIdentPaletteKey, normalized);
  }

  static const String _textBrightnessKey = 'text_brightness';
  static const Set<String> _textBrightnessValues = {'bright', 'soft', 'dim'};

  /// App-wide text brightness (Appearance → Text Brightness): 'bright' (pure
  /// white, the default and the app's historical look), 'soft', or 'dim'.
  /// Consumed as a [TextBrightness] preset by the root theme — see
  /// `services/text_brightness.dart` for the actual colors. The synchronous
  /// mirror for first-frame reads is TextBrightnessController's notifier,
  /// warmed in main() before runApp — no cached copy lives here.
  ///
  /// Normalizes toward 'bright' on BOTH sides — an unrecognized value has to
  /// mean the default for the reader and the writer alike, or writing one
  /// would silently pin a preset the reader treats as the exception.
  static Future<String> getTextBrightness() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_textBrightnessKey);
    return _textBrightnessValues.contains(value) ? value! : 'bright';
  }

  static Future<void> setTextBrightness(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _textBrightnessKey,
      _textBrightnessValues.contains(value) ? value : 'bright',
    );
  }

  static const String _tvSidebarStyleKey = 'tv_sidebar_style';
  static const Set<String> _tvSidebarStyles = {
    'classic',
    'ghost',
    'island',
    'marquee',
    'badge',
    'pill',
  };

  /// TV sidebar chrome: 'ghost' (chromeless, the default), 'classic' (the
  /// original liquid glass), 'island', 'marquee', 'badge' or 'pill'.
  ///
  /// The LEFT-only focus model is shared by every style. Chrome-only for the
  /// first five; **'pill' is the one that also changes LAYOUT** — it shows no
  /// rail at rest, so content runs full-bleed and gains 64px. Read the inset
  /// through `TvSidebarNav.contentInsetFor` rather than assuming the constant.
  /// Phone/desktop never read any of it.
  /// Synchronous mirror of `tvSidebarStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String tvSidebarStyleCached = 'ghost';

  static Future<String> getTvSidebarStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_tvSidebarStyleKey);
    return tvSidebarStyleCached =
        (raw != null && _tvSidebarStyles.contains(raw)) ? raw : 'ghost';
  }

  static Future<void> setTvSidebarStyle(String style) async {
    final normalized = _tvSidebarStyles.contains(style) ? style : 'ghost';
    tvSidebarStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_tvSidebarStyleKey, normalized);
  }

  static const String _desktopSidebarStyleKey = 'desktop_sidebar_style';
  static const Set<String> _desktopSidebarStyles = {'rail', 'pill'};

  /// Desktop/tablet sidebar chrome, read only at the wide (≥600) non-TV
  /// layout: 'rail' (the fixed icon rail, the default) or 'pill' (no rail —
  /// content runs full-bleed and a floating capsule shows the current tab;
  /// clicking it opens the menu as an overlay). The TV rail has its own key
  /// above and never reads this; phones never reach the wide layout.
  /// Warmed in `main()` before the first frame — the shell's field
  /// initializer reads it so a migrated/pill user never flashes the rail.
  static String desktopSidebarStyleCached = 'rail';

  static Future<String> getDesktopSidebarStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_desktopSidebarStyleKey);
    return desktopSidebarStyleCached =
        (raw != null && _desktopSidebarStyles.contains(raw)) ? raw : 'rail';
  }

  static Future<void> setDesktopSidebarStyle(String style) async {
    desktopSidebarStyleCached = _desktopSidebarStyles.contains(style)
        ? style
        : 'rail';
    final normalized = _desktopSidebarStyles.contains(style) ? style : 'rail';
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_desktopSidebarStyleKey, normalized);
  }

  static const String _sidebarConfigurationKey = 'sidebar_configuration_v1';

  /// Profile-scoped order and label overrides shared by the Android TV and
  /// desktop/tablet sidebars. The cached mirror is warmed before runApp so a
  /// customized profile never flashes the default order on frame one.
  static SidebarConfiguration sidebarConfigurationCached =
      SidebarConfiguration.defaults();

  static Future<SidebarConfiguration> getSidebarConfiguration() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_sidebarConfigurationKey);
    return sidebarConfigurationCached =
        (raw == null ? null : SidebarConfiguration.tryDecode(raw)) ??
        SidebarConfiguration.defaults();
  }

  static Future<bool> setSidebarConfiguration(
    SidebarConfiguration configuration,
  ) async {
    final normalized = SidebarConfiguration(
      order: configuration.order,
      labels: configuration.labels,
    );
    final prefs = await ProfilePreferences.instance();
    final saved = await prefs.setString(
      _sidebarConfigurationKey,
      normalized.encode(),
    );
    if (saved) sidebarConfigurationCached = normalized;
    return saved;
  }

  static Future<bool> resetSidebarConfiguration() async {
    final prefs = await ProfilePreferences.instance();
    final removed = await prefs.remove(_sidebarConfigurationKey);
    if (removed || !prefs.containsKey(_sidebarConfigurationKey)) {
      sidebarConfigurationCached = SidebarConfiguration.defaults();
      return true;
    }
    return false;
  }

  /// The classic bar's user-chosen middle slots, as REAL tab indices (Home
  /// and More are fixed anchors and never stored). Null = never customized
  /// (defaults apply); an explicit short list is a deliberate choice and the
  /// bar respects its length.
  static Future<List<int>?> getPhoneNavBarIndices() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getStringList(_phoneNavBarIndicesKey);
    if (raw == null) return null;
    return [
      for (final s in raw)
        if (int.tryParse(s) != null) int.parse(s),
    ];
  }

  static Future<void> setPhoneNavBarIndices(List<int> indices) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_phoneNavBarIndicesKey, [
      for (final i in indices) '$i',
    ]);
  }

  static Future<bool> getRealDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_realDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setRealDebridHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_realDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearRealDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_realDebridHiddenFromNavKey);
  }

  static Future<bool> getRdSkipBlockedTorrents() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_rdSkipBlockedTorrentsKey) ?? true;
  }

  static Future<void> setRdSkipBlockedTorrents(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_rdSkipBlockedTorrentsKey, enabled);
  }

  static Future<bool> getTorboxIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxIntegrationEnabledKey) ?? true;
  }

  static Future<void> setTorboxIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxIntegrationEnabledKey, enabled);
  }

  static Future<bool> getTorboxHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxHiddenFromNavKey) ?? false;
  }

  static Future<void> setTorboxHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxHiddenFromNavKey, hidden);
  }

  static Future<void> clearTorboxHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_torboxHiddenFromNavKey);
  }

  // Premiumize API key helpers
  static Future<String?> getPremiumizeApiKey({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _premiumizeApiKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _premiumizeApiKey);
  }

  static Future<bool> hasPremiumizeCredential() =>
      _credentialConfigured(_premiumizeApiKey, () => getPremiumizeApiKey());

  static Future<void> savePremiumizeApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _premiumizeApiKey, apiKey);
  }

  static Future<void> deletePremiumizeApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_premiumizeApiKey)) {
      await prefs.remove(_premiumizeApiKey);
    }
  }

  static Future<bool> getPremiumizeIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeIntegrationEnabledKey) ?? true;
  }

  static Future<void> setPremiumizeIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeIntegrationEnabledKey, enabled);
  }

  static Future<bool> getPremiumizeHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeHiddenFromNavKey) ?? false;
  }

  static Future<void> setPremiumizeHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeHiddenFromNavKey, hidden);
  }

  static Future<void> clearPremiumizeHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_premiumizeHiddenFromNavKey);
  }

  // AllDebrid API key helpers
  static Future<String?> getAllDebridApiKey({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _allDebridApiKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _allDebridApiKey);
  }

  static Future<bool> hasAllDebridCredential() =>
      _credentialConfigured(_allDebridApiKey, () => getAllDebridApiKey());

  static Future<void> saveAllDebridApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _allDebridApiKey, apiKey);
  }

  static Future<void> deleteAllDebridApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_allDebridApiKey)) {
      await prefs.remove(_allDebridApiKey);
    }
  }

  // MDBList API key + cached username helpers
  static Future<String?> getMdblistApiKey({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _mdblistApiKeyKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _mdblistApiKeyKey);
  }

  static Future<bool> hasMdblistCredential() =>
      _credentialConfigured(_mdblistApiKeyKey, () => getMdblistApiKey());

  static Future<bool> _credentialConfigured(
    String key,
    Future<String?> Function() legacyRead,
  ) async {
    final presence = await ProfileCredentialFacade.isConfigured(key);
    if (presence.handled) return presence.configured;
    final value = await legacyRead();
    return value != null && value.isNotEmpty;
  }

  static Future<void> saveMdblistApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _mdblistApiKeyKey, apiKey);
  }

  static Future<String?> getMdblistUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_mdblistUsernameKey);
  }

  static Future<void> setMdblistUsername(String? username) async {
    final prefs = await ProfilePreferences.instance();
    if (username == null || username.isEmpty) {
      await prefs.remove(_mdblistUsernameKey);
    } else {
      await prefs.setString(_mdblistUsernameKey, username);
    }
  }

  /// Clears all stored MDBList auth (key + cached username).
  static Future<void> clearMdblistAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_mdblistApiKeyKey)) {
      await prefs.remove(_mdblistApiKeyKey);
    }
    await prefs.remove(_mdblistUsernameKey);
    await prefs.remove(_mdblistSavedClonesKey);
    await prefs.remove(_mdblistSyncCheckpointKey);
    await fallbackDisconnectedProgressSource(TrackingSource.mdblist);
  }

  // Maps a source MDBList list id -> the id of the static list we CLONED it
  // into on the user's account (the "Save" action). Lets the Save button know a
  // list is already saved and which clone to delete on un-save. JSON object of
  // {"<sourceId>": clonedId}.
  static const String _mdblistSavedClonesKey = 'mdblist_saved_clones';

  static Future<Map<int, int>> getMdblistSavedClones() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_mdblistSavedClonesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, int>{};
      decoded.forEach((k, v) {
        final sid = int.tryParse(k.toString());
        final cid = v is int ? v : (v is num ? v.toInt() : null);
        if (sid != null && cid != null) out[sid] = cid;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> setMdblistSavedClone(int sourceId, int clonedId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map[sourceId] = clonedId;
    await prefs.setString(
      _mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  static Future<void> removeMdblistSavedClone(int sourceId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map.remove(sourceId);
    await prefs.setString(
      _mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  /// Retire the old clone-as-like UI bookkeeping. Remote lists are deliberately
  /// untouched: an old clone is now simply a normal user-owned list.
  static Future<void> retireMdblistSavedCloneMarkers() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_mdblistSavedClonesKey);
  }

  static const String _mdblistSyncCheckpointKey = 'mdblist_sync_checkpoint_v1';

  static Future<Map<String, dynamic>?> getMdblistSyncCheckpoint() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_mdblistSyncCheckpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setMdblistSyncCheckpoint(
    Map<String, dynamic>? value,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_mdblistSyncCheckpointKey);
    } else {
      await prefs.setString(_mdblistSyncCheckpointKey, jsonEncode(value));
    }
  }

  static Future<bool> getAllDebridIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_allDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setAllDebridIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_allDebridIntegrationEnabledKey, enabled);
  }

  // AllDebrid post-torrent action methods
  static Future<String> getAllDebridPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_allDebridPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveAllDebridPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_allDebridPostTorrentActionKey, action);
  }

  // AllDebrid hide-from-navigation
  static Future<bool> getAllDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_allDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setAllDebridHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_allDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearAllDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_allDebridHiddenFromNavKey);
  }

  static Future<bool> isInitialSetupComplete() async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      return prefs.getBool(_onboardingCompleteKey) ?? false;
    }

    final scope = ProfileRuntime.capture();
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (profile == null ||
        !profile.isEnabled ||
        profile.visibleDataGeneration != scope.dataGeneration) {
      throw StateError('Active profile onboarding state is unavailable');
    }

    // Builds that first introduced profiles wrote onboarding state to two
    // places. Honor an explicitly stored value once (notably `false` from a
    // profile reset), reconcile it into the registry, then remove the
    // compatibility value. If the key is absent, the registry was already
    // correct for migrated Admins and Admin-created profiles.
    if (!prefs.containsKey(_onboardingCompleteKey)) {
      return profile.setupComplete;
    }
    final compatibilityValue = prefs.getBool(_onboardingCompleteKey);
    if (compatibilityValue == null) {
      throw const FormatException('Invalid onboarding completion state');
    }
    if (compatibilityValue != profile.setupComplete) {
      final authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      if (ProfileRuntime.capture() != scope ||
          authorization.profileId != scope.profileId) {
        throw StateError('Active profile onboarding session has changed');
      }
      await ProfileBootstrap.registry.setActiveProfileSetupComplete(
        profileId: authorization.profileId,
        setupComplete: compatibilityValue,
        actingAuthorizationRevision: authorization.authorizationRevision,
        actingSessionEpoch: authorization.sessionEpoch,
      );
    }
    if (!await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    return compatibilityValue;
  }

  static Future<void> setInitialSetupComplete(bool value) async {
    final prefs = await ProfilePreferences.instance();
    if (!ProfileRuntime.isProfileCommitted) {
      await prefs.setBool(_onboardingCompleteKey, value);
      return;
    }

    final authorization = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await authorization.validate(ProfileBootstrap.registry);
    // Remove the retired compatibility value before the canonical write. If
    // authority changes, the stale scoped wrapper fails and no other profile
    // can be mutated. A later retry safely starts from the registry value.
    if (prefs.containsKey(_onboardingCompleteKey) &&
        !await prefs.remove(_onboardingCompleteKey)) {
      throw StateError('Could not retire compatibility onboarding state');
    }
    if (profile.setupComplete == value) return;
    await ProfileBootstrap.registry.setActiveProfileSetupComplete(
      profileId: authorization.profileId,
      setupComplete: value,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
  }

  // File Selection methods
  static Future<String> getFileSelection() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_fileSelectionKey) ??
        'smart'; // Default to smart selection
  }

  static Future<void> saveFileSelection(String selection) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_fileSelectionKey, selection);
  }

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_postTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_postTorrentActionKey, action);
  }

  // TorBox post-torrent action methods
  static Future<String> getTorboxPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_torboxPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveTorboxPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_torboxPostTorrentActionKey, action);
  }

  // PikPak post-torrent action methods
  static Future<String> getPikPakPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePikPakPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakPostTorrentActionKey, action);
  }

  // Premiumize post-torrent action methods
  static Future<String> getPremiumizePostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_premiumizePostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePremiumizePostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_premiumizePostTorrentActionKey, action);
  }

  static Future<bool> getPremiumizeCacheCheckEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeCacheCheckPref) ?? false;
  }

  static Future<void> setPremiumizeCacheCheckEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeCacheCheckPref, enabled);
  }

  // Battery optimization status
  static Future<String> getBatteryOptimizationStatus() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_batteryOptStatusKey) ?? 'unknown';
  }

  static Future<void> setBatteryOptimizationStatus(String status) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_batteryOptStatusKey, status);
  }

  // Download settings - Fixed to 1 parallel download
  static Future<int> getMaxParallelDownloads() async {
    return 1; // Always return 1 for single download at a time
  }

  static Future<void> setMaxParallelDownloads(int value) async {
    // No-op: parallel downloads are fixed to 1
  }

  // ── Custom download location (Android SAF tree) ─────────────────────────
  static const String _downloadTreeUriKey = 'download_tree_uri_v1';
  static const String _downloadTreeNameKey = 'download_tree_display_name_v1';

  /// The persisted SAF tree URI for the user-chosen download folder, or null
  /// when downloads go to the default location (Downloads/Debrify).
  static Future<String?> getDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeUriKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<String?> getDownloadTreeDisplayName() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeNameKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadTreeUri(
    String treeUri,
    String displayName,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadTreeUriKey, treeUri);
    await prefs.setString(_downloadTreeNameKey, displayName);
  }

  static Future<void> clearDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadTreeUriKey);
    await prefs.remove(_downloadTreeNameKey);
  }

  // ── Custom download location (desktop: plain filesystem path) ───────────
  // Windows/Linux only. macOS is deliberately excluded: the app is sandboxed
  // with a read-only user-selected-files entitlement, so a picked folder
  // needs security-scoped bookmarks to survive relaunch — separate feature.
  static const String _downloadDirPathKey = 'download_dir_path_v1';

  /// The persisted absolute directory for the user-chosen download folder on
  /// desktop, or null when downloads go to the platform default.
  static Future<String?> getDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadDirPathKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadDirPath(String dirPath) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadDirPathKey, dirPath);
  }

  static Future<void> clearDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadDirPathKey);
  }

  // ── Continue Watching (recently watched items for home screen) ──────────

  /// Get all continue watching items, sorted by most recent first.
  static Future<List<Map<String, dynamic>>> getContinueWatchingItems() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      items.sort(
        (a, b) => ((b['updatedAt'] as int?) ?? 0).compareTo(
          (a['updatedAt'] as int?) ?? 0,
        ),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Add or update a continue watching entry.
  /// Deduplicates by IMDB ID — updates existing entry if found.
  static Future<void> saveContinueWatchingItem({
    required String imdbId,
    required String title,
    required String contentType,
    String? posterUrl,
    String? addonId,
    String? year,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    List<Map<String, dynamic>> items = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = await decodeJsonAsync(raw);
        items = list
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }

    // Remove existing entry with same IMDB ID
    items.removeWhere((e) => e['imdbId'] == imdbId);

    // Add at front
    items.insert(0, {
      'imdbId': imdbId,
      'title': title,
      'contentType': contentType,
      'posterUrl': posterUrl,
      'addonId': addonId,
      'year': year,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep max 50 items
    if (items.length > 50) items = items.sublist(0, 50);

    await _saveContinueWatchingItems(items, tombstoneRemovals: false);
  }

  /// Remove a continue watching entry by IMDB ID.
  static Future<void> removeContinueWatchingItem(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final before = items.length;
      items.removeWhere(
        (e) => (e['imdbId'] as String?)?.trim().toLowerCase() == normalized,
      );
      if (items.length == before) return;
      await _saveContinueWatchingItems(items);
    } catch (_) {}
  }

  /// Clear all continue watching items.
  static Future<void> clearContinueWatching({
    bool recordSyncDeletions = true,
  }) async {
    await _saveContinueWatchingItems(
      const <Map<String, dynamic>>[],
      tombstoneRemovals: recordSyncDeletions,
    );
  }

  static Future<void> _saveContinueWatchingItems(
    List<Map<String, dynamic>> items, {
    bool tombstoneRemovals = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (tombstoneRemovals) {
      final previous = await getContinueWatchingItems();
      final retained = <String>{
        for (final item in items)
          if ((item['imdbId']?.toString().trim().toLowerCase() ?? '')
              .isNotEmpty)
            item['imdbId'].toString().trim().toLowerCase(),
      };
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(
              (item) => item['imdbId']?.toString().trim().toLowerCase() ?? '',
            )
            .where((id) => id.isNotEmpty && !retained.contains(id))
            .map(WebDavSyncRecordKey.continueWatching),
      );
    }
    await prefs.setString(_continueWatchingKey, jsonEncode(items));
  }

  /// Movies finished locally by the Debrify player. This intentionally stays
  /// separate from Trakt and Simkl: tracker-backed sessions use the tracker as
  /// their source of truth, while offline/local sessions still need a durable
  /// completed state for the detail screen.
  static Future<Set<String>> _getFinishedMovieIds() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(_finishedMoviesKey) ?? const <String>[];
    return {
      for (final raw in stored)
        if (raw.trim().isNotEmpty) raw.trim().toLowerCase(),
    };
  }

  /// Snapshot used by poster badges. Returned IDs are normalized lowercase.
  static Future<Set<String>> getFinishedMovieIds() => _getFinishedMovieIds();

  static Future<bool> isMovieFinished(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return (await _getFinishedMovieIds()).contains(normalized);
  }

  /// Mark a locally tracked movie finished, remove it from Continue Watching,
  /// and clear its resumable state. The finished record itself remains so the
  /// detail action can accurately read "Rewatch".
  static Future<void> markMovieAsFinished(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (finished.add(normalized)) {
      final prefs = await ProfilePreferences.instance();
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
      localCompletionRevision.value++;
    }
    await Future.wait([
      removeContinueWatchingItem(normalized),
      clearPlaybackStateByImdbId(normalized),
    ]);
    debugPrint('StorageService: markMovieAsFinished imdbId="$normalized"');
  }

  /// Start a local rewatch. The caller saves a fresh resume point afterwards,
  /// so only the completed marker is removed here.
  static Future<void> unmarkMovieAsFinished(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (!finished.remove(normalized)) return;

    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    final prefs = await ProfilePreferences.instance();
    if (finished.isEmpty) {
      await prefs.remove(_finishedMoviesKey);
    } else {
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
    }
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkMovieAsFinished imdbId="$normalized"');
  }

  static Future<Set<String>> getExplicitlyWatchedSeriesIds() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getStringList(_explicitlyWatchedSeriesKey) ?? const [])
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> setSeriesExplicitlyWatched(
    String imdbId, {
    required bool watched,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final ids = await getExplicitlyWatchedSeriesIds();
    final changed = watched ? ids.add(normalized) : ids.remove(normalized);
    if (!changed) return;
    if (!watched) {
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.explicitlyWatchedSeries(normalized),
      });
    }
    final prefs = await ProfilePreferences.instance();
    if (ids.isEmpty) {
      await prefs.remove(_explicitlyWatchedSeriesKey);
    } else {
      await prefs.setStringList(
        _explicitlyWatchedSeriesKey,
        ids.toList()..sort(),
      );
    }
    localCompletionRevision.value++;
  }

  // Enhanced Playback State methods
  static Future<Map<String, dynamic>> _getPlaybackStateMap() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playbackStateKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Remove all playback state entries (series progress, video progress) for an IMDB ID.
  static Future<void> clearPlaybackStateByImdbId(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final map = await _getPlaybackStateMap();
    final keysToRemove = <String>[];
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic> &&
          (entry.value['imdbId'] as String?)?.trim().toLowerCase() ==
              normalized) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isEmpty) return;
    for (final key in keysToRemove) {
      map.remove(key);
    }
    await _savePlaybackStateMap(map, recordDeletions: true);
    // Series finished-episode markers share this map, so clearing a Continue
    // Watching item must also invalidate derived series completion.
    localCompletionRevision.value++;
    debugPrint(
      'StorageService: Cleared ${keysToRemove.length} playback state entries for "$imdbId"',
    );
  }

  static Future<void> _savePlaybackStateMap(
    Map<String, dynamic> map, {
    bool recordDeletions = false,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (recordDeletions &&
        await WebDavSyncTombstoneRecorder.shouldRecordForCurrentProfile()) {
      final previous = await _getPlaybackStateMap();
      final retained = _webDavPlaybackRecordKeys(map);
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        _webDavPlaybackRecordKeys(previous).difference(retained),
      );
    }
    await prefs.setString(_playbackStateKey, jsonEncode(map));
  }

  static Set<String> _webDavPlaybackRecordKeys(Map<String, dynamic> map) {
    final keys = <String>{};
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final record = Map<String, dynamic>.from(value);
      final seasons = record['seasons'];
      final finished = record['finishedEpisodes'];
      if (seasons is Map || finished is Map || record['type'] == 'series') {
        keys.add(WebDavSyncRecordKey.playbackMeta(entry.key));
        void addEpisodes(Object? source, {required bool completion}) {
          if (source is! Map) return;
          for (final seasonEntry in source.entries) {
            final season = int.tryParse(seasonEntry.key.toString());
            if (season == null || season < 0 || seasonEntry.value is! Map) {
              continue;
            }
            for (final episodeEntry in (seasonEntry.value as Map).entries) {
              final episode = int.tryParse(episodeEntry.key.toString());
              if (episode == null ||
                  episode < 0 ||
                  episodeEntry.value is! Map) {
                continue;
              }
              keys.add(
                completion
                    ? WebDavSyncRecordKey.playbackFinished(
                        entry.key,
                        season,
                        episode,
                      )
                    : WebDavSyncRecordKey.playbackEpisode(
                        entry.key,
                        season,
                        episode,
                      ),
              );
            }
          }
        }

        addEpisodes(seasons, completion: false);
        addEpisodes(finished, completion: true);
      } else {
        keys.add(WebDavSyncRecordKey.playback(entry.key));
      }
    }
    return keys;
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
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    if (!map.containsKey(key)) {
      map[key] = {'type': 'series', 'title': seriesTitle, 'seasons': {}};
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided (enables lookup by IMDB ID)
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }
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
    String? imdbId,
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

    // Store IMDB ID if provided
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }

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

    final episodeData =
        seriesData['seasons'][season.toString()][episode.toString()];

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
    localCompletionRevision.value++;
  }

  /// Unmark an episode as finished (mark as unwatched)
  static Future<void> unmarkEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final currentTitleKey =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;
    var changed = false;
    var aliasesChanged = 0;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      if (_clearEpisodeCompletion(
        seriesData: seriesData,
        season: season,
        episode: episode,
      )) {
        changed = true;
        aliasesChanged++;
      }
    }

    if (!changed) return;

    debugPrint(
      'StorageService: unmarkEpisodeAsFinished title="$seriesTitle" '
      'S${season}E$episode aliases=$aliasesChanged',
    );

    await _savePlaybackStateMap(map, recordDeletions: true);
    localCompletionRevision.value++;
  }

  /// Clear every completed episode owned by a stable series identity.
  ///
  /// This is the local equivalent of removing a show from tracker history.
  /// Synthetic watched rows and completed checkpoints are cleared across all
  /// release-title aliases, while genuine partial rewatch progress survives.
  static Future<void> unmarkSeriesAsFinished(
    String imdbId, {
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final normalizedTitle = seriesTitle?.trim().toLowerCase();
    final map = await _getPlaybackStateMap();
    var changed = false;

    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      final storedTitle = raw['title']?.toString().trim().toLowerCase();
      final matchesStableId = storedId == normalized;
      final matchesLegacyTitle =
          normalizedTitle != null &&
          normalizedTitle.isNotEmpty &&
          storedTitle == normalizedTitle;
      if (!matchesStableId && !matchesLegacyTitle) continue;

      final coordinates = <({int season, int episode})>{};
      void collect(Object? seasons) {
        if (seasons is! Map) return;
        for (final seasonEntry in seasons.entries) {
          final season = int.tryParse(seasonEntry.key.toString());
          final episodes = seasonEntry.value;
          if (season == null || episodes is! Map) continue;
          for (final episodeKey in episodes.keys) {
            final episode = int.tryParse(episodeKey.toString());
            if (episode != null) {
              coordinates.add((season: season, episode: episode));
            }
          }
        }
      }

      collect(raw['finishedEpisodes']);
      collect(raw['seasons']);
      for (final coordinate in coordinates) {
        if (_clearEpisodeCompletion(
          seriesData: raw,
          season: coordinate.season,
          episode: coordinate.episode,
        )) {
          changed = true;
        }
      }
    }

    if (!changed) return;
    await _savePlaybackStateMap(map, recordDeletions: true);
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkSeriesAsFinished imdbId="$normalized"');
  }

  /// Remove one episode's explicit completion and any synthetic/completed
  /// progress produced by marking it watched. Genuine partial progress remains
  /// intact, including a rewatch in progress under another title alias.
  static bool _clearEpisodeCompletion({
    required Map<String, dynamic> seriesData,
    required int season,
    required int episode,
  }) {
    final seasonKey = season.toString();
    final episodeKey = episode.toString();
    var changed = false;

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes is Map) {
      final seasonData = finishedEpisodes[seasonKey];
      if (seasonData is Map && seasonData.containsKey(episodeKey)) {
        seasonData.remove(episodeKey);
        if (seasonData.isEmpty) finishedEpisodes.remove(seasonKey);
        changed = true;
      }
    }

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return changed;
    final seasonData = seasons[seasonKey];
    if (seasonData is! Map) return changed;
    final episodeData = seasonData[episodeKey];
    if (episodeData is! Map) return changed;

    final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
    final isDummy = positionMs == 0 && durationMs == 1;
    final isCompleted = durationMs > 0 && positionMs >= durationMs;
    // Unwatching a fully-watched episode DROPS its row. Zeroing the offset
    // instead used to leave a "played, 0% in, not finished" ghost carrying a
    // fresh updatedAt, which then won `getLastPlayedEpisode*` and pinned
    // Continue Watching to an episode the user had just declared unwatched —
    // and every repeat of mark→unmark re-stamped it fresher.
    if (isDummy || isCompleted) {
      seasonData.remove(episodeKey);
      if (seasonData.isEmpty) seasons.remove(seasonKey);
      return true;
    }
    // Reached only for rows that were never marked watched through
    // [markEpisodeAsFinished] (it overwrites positionMs with durationMs, so a
    // marked row always lands in the branch above). A genuine partial — e.g. a
    // rewatch in progress under another title alias, swept by
    // [unmarkSeriesAsFinished] — keeps its offset.
    return changed;
  }

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await _getPlaybackStateMap();
    final currentTitleKey =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      final finishedEpisodes = seriesData['finishedEpisodes'];
      if (finishedEpisodes is! Map) continue;
      final seasonData = finishedEpisodes[season.toString()];
      if (seasonData is Map && seasonData.containsKey(episode.toString())) {
        return true;
      }
    }
    return false;
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

  /// Resolve finished episodes by stable title identity, falling back to the
  /// historical title-keyed record for installs created before IMDb IDs were
  /// persisted with series playback.
  static Future<Map<String, Set<int>>> getFinishedEpisodesByImdbId({
    required String imdbId,
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    final map = await _getPlaybackStateMap();
    final result = <String, Set<int>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      if (storedId != normalized) continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      for (final entry in finished.entries) {
        final episodes = entry.value;
        if (episodes is! Map) continue;
        result.putIfAbsent(entry.key.toString(), () => <int>{}).addAll({
          for (final episode in episodes.keys)
            if (int.tryParse(episode.toString()) case final value?) value,
        });
      }
    }
    if (result.isNotEmpty) return result;
    if (seriesTitle != null && seriesTitle.isNotEmpty) {
      return getFinishedEpisodes(seriesTitle: seriesTitle);
    }
    return {};
  }

  /// One-pass index for derived series completion. IMDb keys are preferred;
  /// title keys preserve older playback records that predate stable IDs.
  static Future<Map<String, Map<String, Set<int>>>>
  getFinishedSeriesEpisodeIndex() async {
    final map = await _getPlaybackStateMap();
    final result = <String, Map<String, Set<int>>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      final parsed = <String, Set<int>>{
        for (final entry in finished.entries)
          entry.key.toString(): {
            if (entry.value is Map)
              for (final episode in (entry.value as Map).keys)
                if (int.tryParse(episode.toString()) case final value?) value,
          },
      };
      void mergeInto(String key) {
        final target = result.putIfAbsent(key, () => <String, Set<int>>{});
        for (final season in parsed.entries) {
          target.putIfAbsent(season.key, () => <int>{}).addAll(season.value);
        }
      }

      final imdbId = raw['imdbId']?.toString().trim().toLowerCase();
      if (imdbId != null && imdbId.isNotEmpty) mergeInto(imdbId);
      final title = raw['title']?.toString().trim().toLowerCase();
      if (title != null && title.isNotEmpty) mergeInto('title:$title');
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

  // v2: keyed by IMDb id (stable, unambiguous) instead of the normalized series
  // title. Title-keying silently broke the playlist bars whenever the writer's
  // and readers' title derivations diverged; the seed and every reader always
  // have the show's IMDb id, so we key on that. Bumped from _v1 so stale
  // title-keyed data is dropped (it re-seeds on the next series launch).
  static const String _episodeTraktProgressKey = 'episode_trakt_progress_v2';

  /// Normalized storage key for the per-episode Trakt store (keyed by IMDb id).
  static String _episodeTraktKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Trakt playback progress per episode (percent, 0–100), kept
  /// SEPARATE from the ms-based resume state. It drives the playlist progress
  /// bars only — never a resume seek directly (the players convert % → ms at
  /// play time once the real duration is known, so we never store a fake
  /// position). Keyed by the show's IMDb id; episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeTraktProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeTraktProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Trakt per-episode percents for the show [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeTraktProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeTraktProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  // Kept separate from both local playback state and Trakt. This is a
  // replace-on-launch snapshot of Simkl's remote truth, so marking an episode
  // unwatched on Simkl can clear the player tick without mutating local
  // history.
  static const String _episodeSimklProgressKey = 'episode_simkl_progress_v1';

  static String _episodeSimklKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Simkl progress per episode (percent, 0–100), keyed by the
  /// show's IMDb id. Episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeSimklProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeSimklProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeSimklKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Simkl per-episode snapshot for [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeSimklProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeSimklProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  static const String _episodeMdblistProgressKey =
      'episode_mdblist_progress_v1';

  static Future<Map<String, double>> getEpisodeMdblistProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeMdblistProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      return {
        for (final entry in series.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveEpisodeMdblistProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeMdblistProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  /// Replace one show's entry inside a provider's whole-store snapshot.
  /// Capture the originating profile before this operation queues so a profile
  /// switch cannot redirect a delayed write into the newly active profile.
  static Future<void> _saveEpisodeTrackerProgress({
    required String storeKey,
    required String imdbId,
    required Map<String, double> percents,
  }) {
    if (imdbId.isEmpty) return Future.value();
    final normalizedKey = _episodeTraktKeyFor(imdbId);
    final snapshot = Map<String, double>.from(percents);
    final profileScope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;

    Future<void> commit() =>
        _episodeTrackerSnapshotWriteLock.synchronized(() async {
          final prefs = await ProfilePreferences.instance();
          final raw = prefs.getString(storeKey);
          Map<String, dynamic> all = {};
          if (raw != null && raw.isNotEmpty) {
            try {
              final decoded = await decodeJsonAsync(raw);
              if (decoded is Map<String, dynamic>) all = decoded;
            } catch (_) {}
          }
          all[normalizedKey] = snapshot;
          await prefs.setString(storeKey, jsonEncode(all));
        });

    return profileScope == null
        ? commit()
        : ProfileRuntime.withCapturedScope(profileScope, commit);
  }

  /// Get episode progress by IMDB ID (scans playback state for matching imdbId)
  /// Also checks single-file video entries and parses season/episode from title.
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgressByImdbId(
    String imdbId,
  ) async {
    final map = await _getPlaybackStateMap();
    final normalizedImdbId = imdbId.trim().toLowerCase();

    // Merge every legacy title-keyed series entry with this IMDb id. Older
    // builds could save the same show under multiple release-derived titles;
    // stopping at the first record silently hid episodes from the others.
    final seriesResult = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> &&
          entry['imdbId']?.toString().trim().toLowerCase() ==
              normalizedImdbId) {
        if (entry['type'] == 'series') {
          final seasons = entry['seasons'];
          if (seasons is! Map) continue;
          for (final seasonEntry in seasons.entries) {
            final episodes = seasonEntry.value;
            if (episodes is! Map) continue;
            for (final episodeEntry in episodes.entries) {
              final episodeData = episodeEntry.value;
              if (episodeData is! Map) continue;
              final episodeKey = '${seasonEntry.key}_${episodeEntry.key}';
              final candidate = Map<String, dynamic>.from(episodeData);
              final existing = seriesResult[episodeKey];
              final candidateUpdatedAt =
                  (candidate['updatedAt'] as num?)?.toInt() ?? 0;
              final existingUpdatedAt =
                  (existing?['updatedAt'] as num?)?.toInt() ?? -1;
              if (candidateUpdatedAt >= existingUpdatedAt) {
                seriesResult[episodeKey] = candidate;
              }
            }
          }
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesResult.isNotEmpty) return seriesResult;

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        return {
          '${season}_$episode': {
            'positionMs': videoFallback['positionMs'] ?? 0,
            'durationMs': videoFallback['durationMs'] ?? 1,
            'updatedAt': videoFallback['updatedAt'] ?? 0,
          },
        };
      }
    }

    return {};
  }

  /// Merge local episode progress across stable IMDb identity and the current
  /// title-keyed record. The newest update wins duplicate coordinates. Equal
  /// or missing timestamps prefer the current title deterministically, which
  /// preserves legacy behavior without letting an older title record move a
  /// newer cross-alias resume position backwards.
  static Future<Map<String, Map<String, dynamic>>> getMergedEpisodeProgress({
    required String seriesTitle,
    String? imdbId,
  }) async {
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getEpisodeProgressByImdbId(imdbId)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
      if (seriesTitle.isNotEmpty)
        getEpisodeProgress(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
    ]);
    int updatedAt(Map<String, dynamic> state) {
      final value = state['updatedAt'];
      if (value is! num || !value.isFinite) return 0;
      final timestamp = value.toInt();
      return timestamp > 0 ? timestamp : 0;
    }

    final merged = Map<String, Map<String, dynamic>>.from(reads[0]);
    for (final entry in reads[1].entries) {
      final previous = merged[entry.key];
      if (previous == null || updatedAt(entry.value) >= updatedAt(previous)) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  /// IMDb-aware counterpart to [getFinishedEpisodes], unioning historical
  /// release-title records with the current title record.
  static Future<Map<String, Set<int>>> getMergedFinishedEpisodes({
    required String seriesTitle,
    String? imdbId,
  }) async {
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getFinishedEpisodesByImdbId(imdbId: imdbId)
      else
        Future.value(const <String, Set<int>>{}),
      if (seriesTitle.isNotEmpty)
        getFinishedEpisodes(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Set<int>>{}),
    ]);
    final merged = <String, Set<int>>{};
    for (final snapshot in reads) {
      for (final entry in snapshot.entries) {
        merged.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }
    return merged;
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
    String? imdbId,
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
      if (imdbId != null) 'imdbId': imdbId,
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

    final imdbId = (videoData['imdbId'] as String?)?.trim();
    // A finished movie can have a stale source-specific state from a final
    // autosave tick. Its local completion record wins over that stale resume.
    if (imdbId != null && imdbId.isNotEmpty && await isMovieFinished(imdbId)) {
      return null;
    }

    return videoData as Map<String, dynamic>;
  }

  /// Get video playback state by IMDB ID (scans all video entries, returns most recent).
  static Future<Map<String, dynamic>?> getVideoPlaybackStateByImdbId(
    String imdbId,
  ) async {
    // A blank id would match every record saved without one and hand back an
    // unrelated movie's position.
    final wanted = imdbId.trim();
    if (wanted.isEmpty) return null;
    // A completion write and the periodic player autosave can overlap by one
    // tick. The finished marker is authoritative for movies, so never expose
    // a stale resume record that slipped back in during that tiny window.
    if (await isMovieFinished(wanted)) return null;
    final map = await _getPlaybackStateMap();
    Map<String, dynamic>? best;
    int bestUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is! Map<String, dynamic> || entry['type'] != 'video') continue;
      // Pattern-matched, not cast: one malformed legacy record must not throw
      // out of a scan over every saved video.
      final recorded = entry['imdbId'];
      if (recorded is String && recorded.trim() == wanted) {
        final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
        if (updatedAt > bestUpdatedAt) {
          bestUpdatedAt = updatedAt;
          best = entry;
        }
      }
    }
    return best;
  }

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await _getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData is! Map || seriesData['type'] != 'series') return null;

    // Find the most recently updated episode. Parse defensively (matching
    // getVideoPlaybackStateByImdbId above): a corrupt or old-schema entry
    // must skip, not throw, on this resume hot path.
    Map<String, dynamic>? lastEpisode;
    int lastUpdated = 0;

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return null;
    for (final seasonEntry in seasons.entries) {
      final season = int.tryParse(seasonEntry.key.toString());
      final episodes = seasonEntry.value;
      if (season == null || episodes is! Map) continue;

      for (final episodeEntry in episodes.entries) {
        final episode = int.tryParse(episodeEntry.key.toString());
        final episodeData = episodeEntry.value;
        if (episode == null || episodeData is! Map) continue;
        final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

        if (updatedAt > lastUpdated) {
          lastUpdated = updatedAt;
          lastEpisode = {
            'season': season,
            'episode': episode,
            ...Map<String, dynamic>.from(episodeData),
          };
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

  /// Get all episode watch progress for a series by IMDB ID.
  /// Returns a map of "season-episode" → progress percentage (0-100).
  static Future<Map<String, double>> getEpisodeWatchProgressByImdbId(
    String imdbId,
  ) async {
    final map = await _getPlaybackStateMap();
    final result = <String, double>{};

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys). Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (seriesEntries.isEmpty && videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        final posMs = (videoFallback['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (videoFallback['durationMs'] as num?)?.toInt() ?? 1;
        if (durMs > 0 && posMs > 0) {
          result['$season-$episode'] = (posMs / durMs * 100).clamp(0.0, 100.0);
        }
        return result;
      }
    }

    if (seriesEntries.isEmpty) return result;

    // Aggregate progress across ALL matching series entries
    for (final seriesData in seriesEntries) {
      final finishedMap =
          seriesData['finishedEpisodes'] as Map<String, dynamic>?;

      final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
      for (final seasonEntry in seasons.entries) {
        final seasonNum = seasonEntry.key;
        final episodes = seasonEntry.value as Map<String, dynamic>? ?? {};

        // Get finished episodes for this season
        final finishedEps = finishedMap?[seasonNum] as Map<String, dynamic>?;

        for (final episodeEntry in episodes.entries) {
          final epNum = episodeEntry.key;
          final epData = episodeEntry.value as Map<String, dynamic>;
          final key = '$seasonNum-$epNum';

          // Check if finished first
          if (finishedEps != null && finishedEps.containsKey(epNum)) {
            result[key] = 100.0;
            continue;
          }

          final positionMs = (epData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (epData['durationMs'] as num?)?.toInt() ?? 1;
          if (durationMs > 0 && positionMs > 0) {
            final progress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
            // Keep higher progress if duplicate across entries
            if (!result.containsKey(key) || progress > result[key]!) {
              result[key] = progress;
            }
          }
        }
      }
    }

    return result;
  }

  /// Look up the last played episode by IMDB ID.
  /// Scans all series entries for a matching imdbId field.
  /// Also checks single-file video entries (type=video) as a fallback,
  /// parsing season/episode from the title.
  static Future<Map<String, dynamic>?> getLastPlayedEpisodeByImdbId(
    String imdbId,
  ) async {
    final map = await _getPlaybackStateMap();

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys, e.g. "young sheldon (2017)" vs "young sheldon").
    // Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesEntries.isNotEmpty) {
      // Find most recently updated episode across ALL matching series entries
      Map<String, dynamic>? lastEpisode;
      Map<String, dynamic>?
      lastEpisodeSeriesData; // track which entry it came from
      int lastUpdated = 0;

      for (final seriesData in seriesEntries) {
        final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
        for (final seasonEntry in seasons.entries) {
          final season = int.parse(seasonEntry.key);
          final episodes = seasonEntry.value as Map<String, dynamic>;

          for (final episodeEntry in episodes.entries) {
            final episode = int.parse(episodeEntry.key);
            final episodeData = episodeEntry.value as Map<String, dynamic>;
            final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

            if (updatedAt > lastUpdated) {
              lastUpdated = updatedAt;
              lastEpisode = {
                'season': season,
                'episode': episode,
                ...episodeData,
              };
              lastEpisodeSeriesData = seriesData;
            }
          }
        }
      }

      if (lastEpisode != null && lastEpisodeSeriesData != null) {
        // Check if this episode is marked as finished (in its own series entry)
        final finishedEpisodes =
            lastEpisodeSeriesData['finishedEpisodes'] as Map<String, dynamic>?;
        if (finishedEpisodes != null) {
          final seasonFinished =
              finishedEpisodes[lastEpisode['season'].toString()]
                  as Map<String, dynamic>?;
          if (seasonFinished != null &&
              seasonFinished.containsKey(lastEpisode['episode'].toString())) {
            lastEpisode['finished'] = true;
          }
        }
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId found S${lastEpisode['season']}E${lastEpisode['episode']} for "$imdbId"${lastEpisode['finished'] == true ? ' (finished)' : ''}',
        );
      }
      return lastEpisode;
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!);
        final episode = int.parse(match.group(2)!);
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId (video fallback) parsed S${season}E$episode from "$title" for "$imdbId"',
        );
        return {
          'season': season,
          'episode': episode,
          'positionMs': videoFallback['positionMs'] ?? 0,
          'durationMs': videoFallback['durationMs'] ?? 1,
          'updatedAt': videoFallback['updatedAt'] ?? 0,
        };
      }
    }

    return null;
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
      await _savePlaybackStateMap(map, recordDeletions: true);
    }
  }

  /// Clear all playback-related data (series and video states, track prefs, legacy resume)
  /// [recordSyncDeletions] distinguishes a deliberate clear (default, which
  /// deletes on every synced device) from a device-local wipe such as app
  /// reset, which must never mint circle-wide deletions.
  static Future<void> clearAllPlaybackData({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    await _savePlaybackStateMap(
      <String, dynamic>{},
      recordDeletions: recordSyncDeletions,
    );
    if (recordSyncDeletions) {
      final finishedMovies = await _getFinishedMovieIds();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        finishedMovies.map(WebDavSyncRecordKey.finishedMovie),
      );
    }
    await prefs.remove(_finishedMoviesKey);
    await prefs.remove(localSeriesCompletionStateKey);
    await prefs.remove(localSeriesCalendarCheckedAtKey);
    await prefs.remove(localSeriesCalendarAttemptedAtKey);
    localCompletionRevision.value++;
    // Resume lives in the DB now; the prefs key only still exists for users
    // who wipe before the one-time import has run.
    await prefs.remove(_videoResumeKey);
    await IptvMediaStore.clearVideoResume(
      origin: recordSyncDeletions
          ? WebDavSyncMutationOrigin.user
          : WebDavSyncMutationOrigin.maintenance,
    );
    debugPrint(
      'StorageService: cleared playback state, completed movies, and video resume data',
    );
  }

  /// Clear all progress data for a specific playlist/series
  static Future<void> clearPlaylistProgress({required String title}) async {
    final map = await _getPlaybackStateMap();

    debugPrint('StorageService: clearPlaylistProgress called for "$title"');

    final keysToRemove = <String>[];

    // Use the SAME matching logic as when finding series progress
    // Try multiple title variations to find all matching entries

    // Variation 1: Use the full playlist item title
    final fullTitleKey =
        'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final fullVideoKey =
        'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    // Variation 2: Try extracting clean title (like "breaking bad" from "Breaking.Bad.SEASON.01.S01...")
    // This matches how SeriesPlaylist extracts the title
    String cleanedTitle = title;

    // Remove common patterns to extract series name
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.S\d{2}.*', caseSensitive: false),
      '',
    ); // Remove S01-S08 and everything after
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.Season\..*', caseSensitive: false),
      '',
    ); // Remove Season.1-8
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
      '',
    ); // Remove quality
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
      '',
    ); // Remove codec
    cleanedTitle = cleanedTitle.replaceAll(
      RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
      '',
    ); // Remove source
    cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

    final cleanTitleKey =
        'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final cleanVideoKey =
        'video_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    debugPrint(
      'StorageService: checking keys - full: $fullTitleKey / $fullVideoKey, clean: $cleanTitleKey / $cleanVideoKey',
    );
    debugPrint('StorageService: available keys: ${map.keys.toList()}');

    // Check for exact key matches first
    for (final key in [
      cleanTitleKey,
      cleanVideoKey,
      fullTitleKey,
      fullVideoKey,
    ]) {
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
        final storedTitle =
            (entry.value['title'] as String?)?.toLowerCase() ?? '';
        if (storedTitle.isEmpty) continue;

        final titleLower = title.toLowerCase();
        final cleanedTitleLower = cleanedTitle.toLowerCase();

        // Check if the stored series title matches in several ways:
        // 1. Exact match with cleaned title (e.g., "game of thrones" == "game of thrones")
        // 2. Input title contains the stored series title (e.g., "game of thrones - season 3" contains "game of thrones")
        // 3. Cleaned title contains the stored series title
        if (storedTitle == cleanedTitleLower ||
            storedTitle == titleLower ||
            (titleLower.contains(storedTitle) &&
                storedTitle.split(' ').length >= 2)) {
          keysToRemove.add(entry.key);
          debugPrint(
            'StorageService: stored title match - key: "${entry.key}", storedTitle: "$storedTitle"',
          );
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
      await _savePlaybackStateMap(map, recordDeletions: true);
      // Finished episodes live in this same map. Re-derive local series
      // completion so watched badges and Continue Watching update immediately.
      localCompletionRevision.value++;
      debugPrint(
        'StorageService: clearPlaylistProgress completed - removed ${keysToRemove.length} entries for "$title"',
      );
    } else {
      debugPrint('StorageService: no progress data found for "$title"');
    }
  }

  // Video resume — one row per item in debrify_tv.db (see IptvMediaStore).
  static Future<Map<String, dynamic>?> getVideoResume(String key) {
    return IptvMediaStore.videoResume(key);
  }

  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry, {
    String? sourceId,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.upsertVideoResume(
      key,
      entry,
      sourceId: sourceId,
      origin: origin,
    );
  }

  static Future<void> removeVideoResume(
    String key, {
    bool playbackCheckpoint = false,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.removeVideoResume(key, origin: origin, playbackCheckpoint: playbackCheckpoint);
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
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_debrifyTvProviderKey) ?? 'real_debrid';
  }

  static Future<void> saveDebrifyTvProvider(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvProviderKey, value);
  }

  static Future<bool> hasDebrifyTvProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.containsKey(_debrifyTvProviderKey);
  }

  static Future<bool> getDebrifyTvStartRandom() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvStartRandomKey) ?? true;
  }

  static Future<void> saveDebrifyTvStartRandom(bool value) async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getInt(_debrifyTvRandomStartPercentKey);
    return _normalizeDebrifyTvRandomStartPercent(stored);
  }

  static Future<void> saveDebrifyTvRandomStartPercent(int value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = _normalizeDebrifyTvRandomStartPercent(value);
    await prefs.setInt(_debrifyTvRandomStartPercentKey, normalized);
  }

  static Future<bool> getDebrifyTvHideSeekbar() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideSeekbarKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideSeekbar(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideSeekbarKey, value);
  }

  static Future<bool> getDebrifyTvShowChannelName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvShowChannelNameKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowChannelName(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvShowChannelNameKey, value);
  }

  static Future<bool> getDebrifyTvShowVideoTitle() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvShowVideoTitleKey) ?? true;
  }

  static Future<void> saveDebrifyTvShowVideoTitle(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvShowVideoTitleKey, value);
  }

  static Future<bool> getDebrifyTvHideOptions() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideOptionsKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideOptions(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideOptionsKey, value);
  }

  static Future<bool> getDebrifyTvHideBackButton() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvHideBackButtonKey) ?? true;
  }

  static Future<void> saveDebrifyTvHideBackButton(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvHideBackButtonKey, value);
  }

  static Future<bool> getDebrifyTvAvoidNsfw() async {
    if (!await profileAllowsAdultContent()) return true;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvAvoidNsfwKey) ?? true; // Default enabled
  }

  static Future<void> saveDebrifyTvAvoidNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _debrifyTvAvoidNsfwKey,
      await profileAllowsAdultContent() ? value : true,
    );
  }

  static Future<List<Map<String, dynamic>>> getDebrifyTvChannels() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_debrifyTvChannelsKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> saveDebrifyTvChannels(
    List<Map<String, dynamic>> channels,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvChannelsKey, jsonEncode(channels));
  }

  // Playlist storage (local-only MVP)
  static Future<List<Map<String, dynamic>>> getPlaylistItemsRaw() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playlistKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> savePlaylistItemsRaw(
    List<Map<String, dynamic>> items, {
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (recordSyncDeletions) {
      final previous = await getPlaylistItemsRaw();
      final retained = items.map(computePlaylistDedupeKey).toSet();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(computePlaylistDedupeKey)
            .where((key) => !retained.contains(key))
            .map(WebDavSyncRecordKey.playlistItem),
      );
    }
    await prefs.setString(_playlistKey, jsonEncode(items));
  }

  static String computePlaylistDedupeKey(Map<String, dynamic> item) =>
      PlaylistDedupeKey.compute(item);

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
            debugPrint(
              '✅ Torrent hash fetched and stored: $hash for torrent ID: $rdTorrentId',
            );
          } else {
            debugPrint(
              '⚠️ No hash found in torrent info for torrent ID: $rdTorrentId',
            );
          }
        } else {
          debugPrint(
            '❌ Failed to fetch torrent info. Status code: ${response.statusCode} for torrent ID: $rdTorrentId',
          );
        }
      } catch (e) {
        debugPrint(
          '❌ Error fetching torrent hash for torrent ID: $rdTorrentId - $e',
        );
        // Silently continue without hash if fetch fails
        // This ensures playlist addition doesn't fail due to hash fetch issues
      }
    } else {
      debugPrint(
        'ℹ️ Skipping torrent hash fetch - missing rdTorrentId or API key',
      );
    }

    // Log what's being saved to database
    debugPrint('📝 Adding playlist item to database:');
    debugPrint('   Title: ${enriched['title']}');
    debugPrint('   Kind: ${enriched['kind']}');
    debugPrint('   rdTorrentId: ${enriched['rdTorrentId']}');
    debugPrint('   torrent_hash: ${enriched['torrent_hash'] ?? 'null'}');
    debugPrint('   restrictedLink: ${enriched['restrictedLink'] ?? 'null'}');
    debugPrint(
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

    items.insert(0, enriched);
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

  static Future<void> clearPlaylist({bool recordSyncDeletions = true}) async {
    await savePlaylistItemsRaw(
      const <Map<String, dynamic>>[],
      recordSyncDeletions: recordSyncDeletions,
    );
  }

  /// Clear all playlist-related metadata (view modes, favorites, poster overrides)
  static Future<void> clearAllPlaylistMetadata({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (recordSyncDeletions) {
      final favorites = await getPlaylistFavoriteKeys();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        favorites.map(WebDavSyncRecordKey.playlistFavorite),
      );
    }
    await prefs.remove(_playlistViewModesKey);
    await prefs.remove(_playlistFavoritesKey);
    await prefs.remove(_playlistPosterOverridesKey);
    await prefs.remove(_tvMazeSeriesMappingKey);
  }

  /// Clear all startup settings (auto-launch, channel/playlist references)
  static Future<void> clearAllStartupSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_startupAutoLaunchEnabledKey);
    await prefs.remove(_startupChannelIdKey);
    await prefs.remove(_startupStremioTvChannelIdKey);
    await prefs.remove(_startupModeKey);
    await prefs.remove(_startupPlaylistItemIdKey);
    await prefs.remove(_startupContinueWatchingItemIdKey);
    await prefs.remove(_startupTraktContinueWatchingMovieIdKey);
    await prefs.remove(_startupTraktContinueWatchingShowIdKey);
    // The startup-channel memory is a startup reference too — Reset must wipe
    // it, or a fresh setup would inherit the previous install's channel.
    await prefs.remove(_iptvLastLiveChannelKey);
    await prefs.remove(_startupIptvModeKey);
    await prefs.remove(_startupIptvChannelKey);
  }

  /// Clear integration enabled states (RD, TorBox)
  static Future<void> clearAllIntegrationStates() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_realDebridIntegrationEnabledKey);
    await prefs.remove(_realDebridHiddenFromNavKey);
    await prefs.remove(_torboxIntegrationEnabledKey);
    await prefs.remove(_torboxHiddenFromNavKey);
    await prefs.remove(_premiumizeIntegrationEnabledKey);
    await prefs.remove(_premiumizeHiddenFromNavKey);
    await prefs.remove(_allDebridIntegrationEnabledKey);
    await prefs.remove(_allDebridHiddenFromNavKey);
    await prefs.remove(_webDavEnabledKey);
    await prefs.remove(_webDavHiddenFromNavKey);
  }

  /// Clear Debrify TV provider and legacy channels key
  static Future<void> clearDebrifyTvProviderAndLegacy() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_debrifyTvProviderKey);
    await prefs.remove(_debrifyTvChannelsKey);
  }

  /// Clear filter settings (qualities, rip sources, languages)
  static Future<void> clearAllFilterSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultFilterQualitiesKey);
    await prefs.remove(_defaultFilterRipSourcesKey);
    await prefs.remove(_defaultFilterLanguagesKey);
    await prefs.remove(_defaultFilterSizesKey);
    await prefs.remove(_defaultFilterDynamicRangesKey);
    await prefs.remove(_defaultTorrentProviderKey);
  }

  /// Clear torrent engine toggles and limits
  static Future<void> clearAllTorrentEngineSettings() async {
    final prefs = await ProfilePreferences.instance();
    final keys = prefs.getKeys().where(
      (key) =>
          (key.startsWith('engine_') && !key.startsWith('engine_tv_')) ||
          (key.startsWith('default_') && key.endsWith('_enabled')) ||
          (key.startsWith('max_') && key.endsWith('_results')),
    );
    for (final key in keys.toList()) {
      await prefs.remove(key);
    }
  }

  /// Clear post-torrent action preferences
  static Future<void> clearAllPostTorrentActions() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_postTorrentActionKey);
    await prefs.remove(_torboxPostTorrentActionKey);
    await prefs.remove(_pikpakPostTorrentActionKey);
    await prefs.remove(_premiumizePostTorrentActionKey);
    await prefs.remove(_allDebridPostTorrentActionKey);
  }

  /// Clear all Debrify TV display and engine settings
  static Future<void> clearAllDebrifyTvSettings() async {
    final prefs = await ProfilePreferences.instance();
    // Display settings
    await prefs.remove(_debrifyTvStartRandomKey);
    await prefs.remove(_debrifyTvHideSeekbarKey);
    await prefs.remove(_debrifyTvShowChannelNameKey);
    await prefs.remove(_debrifyTvShowVideoTitleKey);
    await prefs.remove(_debrifyTvHideOptionsKey);
    await prefs.remove(_debrifyTvHideBackButtonKey);
    await prefs.remove(_debrifyTvAvoidNsfwKey);
    await prefs.remove(_debrifyTvRandomStartPercentKey);
    // Playback filters
    await prefs.remove(_debrifyTvFilterQualitiesKey);
    await prefs.remove(_debrifyTvFilterSizesKey);
    for (final key
        in prefs
            .getKeys()
            .where(
              (key) =>
                  key.startsWith('engine_tv_') ||
                  key.startsWith('debrify_tv_use_') ||
                  key.startsWith('debrify_tv_channel_small_') ||
                  key.startsWith('debrify_tv_channel_large_') ||
                  key.startsWith('debrify_tv_quick_play_') ||
                  key == 'debrify_tv_keyword_threshold' ||
                  key == 'debrify_tv_min_torrents_per_keyword',
            )
            .toList()) {
      await prefs.remove(key);
    }
  }

  /// Update an existing playlist item with poster URL
  /// Supports both RealDebrid (rdTorrentId) and PikPak (pikpakCollectionId)
  static Future<bool> updatePlaylistItemPoster(
    String posterUrl, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
  }) async {
    debugPrint('🎨 updatePlaylistItemPoster called with:');
    debugPrint('  posterUrl: $posterUrl');
    debugPrint('  rdTorrentId: $rdTorrentId');
    debugPrint('  torboxTorrentId: $torboxTorrentId');
    debugPrint('  pikpakCollectionId: $pikpakCollectionId');
    debugPrint('  webDavServerId: $webDavServerId');
    debugPrint('  webDavPath: $webDavPath');

    final items = await getPlaylistItemsRaw();
    debugPrint('  Total playlist items: ${items.length}');

    int itemIndex = -1;

    // Search by rdTorrentId if provided (RealDebrid)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by rdTorrentId at index $itemIndex');
      }
    }

    // Search by torboxTorrentId if provided and not found yet (Torbox)
    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      debugPrint('  Searching for torboxTorrentId: $torboxTorrentId');
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final torboxId = item['torboxTorrentId'];
        debugPrint(
          '    Item[$i] torboxTorrentId: $torboxId (type: ${torboxId.runtimeType})',
        );
        if (torboxId != null &&
            torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          debugPrint('  ✅ Found item by torboxTorrentId at index $itemIndex');
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
        debugPrint('  ✅ Found item by pikpakCollectionId at index $itemIndex');
      }
    }

    // Search by Premiumize infohash if provided and not found yet (Premiumize)
    if (itemIndex == -1 &&
        premiumizeHash != null &&
        premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                premiumizeHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeHash at index $itemIndex');
      }
    }

    // Search by Premiumize cloud item id if provided and not found yet
    // (cloud-browser items have no torrent hash).
    if (itemIndex == -1 &&
        premiumizeItemId != null &&
        premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by premiumizeItemId at index $itemIndex');
      }
    }

    // Search by AllDebrid infohash if provided and not found yet.
    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                allDebridHash.toLowerCase(),
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by allDebridHash at index $itemIndex');
      }
    }

    if (itemIndex == -1 &&
        webDavPath != null &&
        webDavPath.isNotEmpty &&
        ((webDavServerId != null && webDavServerId.isNotEmpty) ||
            (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty))) {
      final webDavKey = computePlaylistDedupeKey({
        'provider': 'webdav',
        if (webDavServerId != null && webDavServerId.isNotEmpty)
          'webdavServerId': webDavServerId,
        if (webDavBaseUrl != null && webDavBaseUrl.isNotEmpty)
          'webdavBaseUrl': webDavBaseUrl,
        'webdavPath': webDavPath,
      });
      itemIndex = items.indexWhere(
        (item) => computePlaylistDedupeKey(item) == webDavKey,
      );
      if (itemIndex != -1) {
        debugPrint('  ✅ Found item by WebDAV key at index $itemIndex');
      }
    }

    if (itemIndex == -1) {
      debugPrint('  ❌ Item not found in playlist!');
      return false;
    }

    debugPrint('  💾 Saving poster to item at index $itemIndex');
    items[itemIndex]['posterUrl'] = posterUrl;
    await savePlaylistItemsRaw(items);
    debugPrint('  ✅ Poster saved successfully!');
    return true;
  }

  static Future<bool> updatePlaylistItemImdbId(
    String imdbId, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? premiumizeHash,
    String? premiumizeItemId,
    String? allDebridHash,
    bool force = false,
  }) async {
    final items = await getPlaylistItemsRaw();
    int itemIndex = -1;

    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) => (item['rdTorrentId'] as String?) == rdTorrentId,
      );
    }

    if (itemIndex == -1 &&
        premiumizeHash != null &&
        premiumizeHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                premiumizeHash.toLowerCase(),
      );
    }

    if (itemIndex == -1 &&
        premiumizeItemId != null &&
        premiumizeItemId.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'premiumize') &&
            (item['premiumizeItemId']?.toString() == premiumizeItemId),
      );
    }

    if (itemIndex == -1 &&
        torboxTorrentId != null &&
        torboxTorrentId.isNotEmpty) {
      for (int i = 0; i < items.length; i++) {
        final torboxId = items[i]['torboxTorrentId'];
        if (torboxId != null &&
            torboxId.toString() == torboxTorrentId.toString()) {
          itemIndex = i;
          break;
        }
      }
    }

    if (itemIndex == -1 &&
        pikpakCollectionId != null &&
        pikpakCollectionId.isNotEmpty) {
      itemIndex = items.indexWhere((item) {
        final pikpakFileId = item['pikpakFileId'] as String?;
        if (pikpakFileId == pikpakCollectionId) return true;
        final pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;
        if (pikpakFileIds != null && pikpakFileIds.isNotEmpty) {
          return pikpakFileIds[0].toString() == pikpakCollectionId;
        }
        return false;
      });
    }

    if (itemIndex == -1 && allDebridHash != null && allDebridHash.isNotEmpty) {
      itemIndex = items.indexWhere(
        (item) =>
            ((item['provider'] as String?)?.toLowerCase() == 'alldebrid') &&
            (item['torrent_hash'] as String?)?.toLowerCase() ==
                allDebridHash.toLowerCase(),
      );
    }

    if (itemIndex == -1) return false;

    if (!force) {
      final existing = items[itemIndex]['imdbId'] as String?;
      if (existing != null && existing.isNotEmpty) return true;
    }

    items[itemIndex]['imdbId'] = imdbId;
    await savePlaylistItemsRaw(items);
    debugPrint(
      'StorageService: Saved imdbId $imdbId to playlist item "${items[itemIndex]['title']}"',
    );
    return true;
  }

  /// Get saved view mode for a playlist item
  /// Returns null if no view mode has been saved for this item
  static Future<String?> getPlaylistItemViewMode(
    Map<String, dynamic> item,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    if (viewModesJson == null) return null;

    try {
      final viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      final dedupeKey = computePlaylistDedupeKey(item);
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
    final viewModesJson = prefs.getString(_playlistViewModesKey);

    Map<String, dynamic> viewModes = {};
    if (viewModesJson != null) {
      try {
        viewModes = jsonDecode(viewModesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist view modes: $e');
      }
    }

    final dedupeKey = computePlaylistDedupeKey(item);
    viewModes[dedupeKey] = viewMode;

    await prefs.setString(_playlistViewModesKey, jsonEncode(viewModes));
  }

  /// Check if a playlist item is favorited
  static Future<bool> isPlaylistItemFavorited(Map<String, dynamic> item) async {
    final prefs = await ProfilePreferences.instance();
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
  static Future<void> setPlaylistItemFavorited(
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    final prefs = await ProfilePreferences.instance();
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
      if (!favorites.containsKey(dedupeKey)) return;
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.playlistFavorite(dedupeKey),
      });
      favorites.remove(dedupeKey);
    }

    await prefs.setString(_playlistFavoritesKey, jsonEncode(favorites));
  }

  /// Get all favorite dedupe keys
  static Future<Set<String>> getPlaylistFavoriteKeys() async {
    final prefs = await ProfilePreferences.instance();
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

  // ========================================================================
  // My Watchlist (movies + series)
  // ========================================================================

  /// Stable identity for Debrify's local movie/series watchlist. Prefer IMDb
  /// so the same title coming from two addons is one entry; fall back to the
  /// source addon + its content id for titles that do not expose IMDb metadata.
  /// Addon ids are part of that fallback because content ids are addon-local.
  static bool supportsMyWatchlistItem(StremioMeta item) {
    final type = item.type.trim().toLowerCase();
    return type == 'movie' || type == 'series';
  }

  /// Returns the identity-bearing item used by both watchlist reads and
  /// writes. A stored source is authoritative for non-IMDb ids; [fallback]
  /// only fills in a source for a newly opened source-less item.
  static StremioMeta withMyWatchlistSource(
    StremioMeta item,
    StremioAddon fallback,
  ) => item.sourceAddon == null ? item.withSourceAddon(fallback) : item;

  static String myWatchlistItemKey(StremioMeta item) {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final type = item.type.trim().toLowerCase();
    final imdbId = item.effectiveImdbId?.trim();
    if (imdbId != null && imdbId.isNotEmpty) return '$type:$imdbId';

    final sourceId = item.sourceAddon?.id.trim();
    final namespace = (sourceId == null || sourceId.isEmpty)
        ? 'unknown'
        : sourceId;
    return '$type:addon:${Uri.encodeComponent(namespace)}:'
        '${Uri.encodeComponent(item.id)}';
  }

  /// tvOS durability ceiling for the encoded watchlist. The recovery envelope
  /// silently skips any single value over its per-value limit, which would
  /// resurrect the wipe-on-restart bug; the 16KiB margin covers the
  /// JSON-escaping inflation the value picks up inside the envelope.
  static const int myWatchlistTvOsCapBytes =
      TvOsRecoveryLimits.envelopeValueBytes - 16 * 1024;

  /// Test seam: `PlatformUtil.isTvOS` is a `static final` and cannot be
  /// overridden, so tests drive the cap through this instead.
  @visibleForTesting
  static bool? debugMyWatchlistTvOsCapOverride;

  static bool get _myWatchlistCapEnforced =>
      debugMyWatchlistTvOsCapOverride ?? PlatformUtil.isTvOS;

  static int _myWatchlistAddedAt(Map<String, dynamic> row) {
    final raw = row['addedAt'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  /// Recomputes keys from stored metadata so rows written by the original
  /// un-namespaced fallback scheme migrate in memory immediately. The next
  /// mutation persists the canonical key.
  static void _canonicalizeMyWatchlistRowKey(Map<String, dynamic> row) {
    final raw = row['item'];
    if (raw is! Map) return;
    try {
      final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
      if (supportsMyWatchlistItem(item)) {
        row['key'] = myWatchlistItemKey(item);
      }
    } catch (_) {
      // The item loader below will ignore the malformed row.
    }
  }

  static Future<List<Map<String, dynamic>>> _readMyWatchlistRows() async {
    final prefs = await ProfilePreferences.instance();
    final encoded = prefs.getString(_myWatchlistKey);
    if (encoded == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final rows = [
        for (final row in decoded)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      for (final row in rows) {
        _canonicalizeMyWatchlistRowKey(row);
      }
      return rows;
    } catch (e) {
      debugPrint('Error reading My Watchlist: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Saved titles, newest first. Corrupt individual rows are ignored so one
  /// bad addon payload cannot make the whole shelf disappear.
  static Future<List<StremioMeta>> getMyWatchlistItems() async {
    final rows = await _readMyWatchlistRows();
    rows.sort(
      (a, b) => _myWatchlistAddedAt(b).compareTo(_myWatchlistAddedAt(a)),
    );
    final items = <StremioMeta>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.id.isEmpty || !supportsMyWatchlistItem(item)) {
          continue;
        }
        items.add(item);
      } catch (_) {
        // Skip only the malformed row.
      }
    }
    return items;
  }

  static Future<bool> isInMyWatchlist(StremioMeta item) async {
    if (!supportsMyWatchlistItem(item)) return false;
    final key = myWatchlistItemKey(item);
    final rows = await _readMyWatchlistRows();
    return rows.any((row) => row['key'] == key);
  }

  /// Adds, refreshes, or removes a title. Adding stores the full presentation
  /// metadata needed by Home, not just an id, so My Watchlist paints instantly
  /// offline and can route back through the source addon when it is installed.
  static Future<void> setMyWatchlistItem(StremioMeta item, bool saved) async {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final key = myWatchlistItemKey(item);
    final existing = rows.where((row) => row['key'] == key).firstOrNull;
    rows.removeWhere((row) => row['key'] == key);
    if (saved) {
      rows.insert(0, {
        'key': key,
        'addedAt': existing == null
            ? DateTime.now().millisecondsSinceEpoch
            : _myWatchlistAddedAt(existing),
        'item': item.toJson(),
      });
    }
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      var encoded = jsonEncode(rows);
      if (_myWatchlistCapEnforced) {
        // Oldest rows go first. The scan starts past index 0 because the row
        // just written sits there — a re-save keeps its original addedAt, so
        // an oldest-by-timestamp scan could otherwise evict exactly it.
        while (rows.length > 1 &&
            utf8.encode(encoded).length > myWatchlistTvOsCapBytes) {
          var oldest = 1;
          for (var i = 2; i < rows.length; i++) {
            if (_myWatchlistAddedAt(rows[i]) <
                _myWatchlistAddedAt(rows[oldest])) {
              oldest = i;
            }
          }
          rows.removeAt(oldest);
          encoded = jsonEncode(rows);
        }
      }
      await prefs.setString(_myWatchlistKey, encoded);
    }
  }

  /// Removes a saved movie/series once actual playback is about to launch.
  /// IMDb is authoritative. Older/addon-local items without IMDb metadata use
  /// a conservative title/source fallback and are removed only when unique.
  static Future<bool> removeMyWatchlistItemForPlayback({
    String? imdbId,
    required String contentType,
    required String title,
    String? addonId,
  }) async {
    final type = contentType.trim().toLowerCase();
    if (type != 'movie' && type != 'series') return false;
    final normalizedImdb = imdbId?.trim().toLowerCase();
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedAddon = addonId?.trim().toLowerCase();
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.type.trim().toLowerCase() != type) continue;
        final itemImdb = item.effectiveImdbId?.trim().toLowerCase();
        if (normalizedImdb != null && normalizedImdb.isNotEmpty) {
          if (itemImdb == normalizedImdb) matches.add(row);
          continue;
        }
        if (itemImdb != null && itemImdb.isNotEmpty) continue;
        if (normalizedTitle.isEmpty ||
            item.name.trim().toLowerCase() != normalizedTitle) {
          continue;
        }
        final itemAddon = item.sourceAddon?.id.trim().toLowerCase();
        if (normalizedAddon != null &&
            normalizedAddon.isNotEmpty &&
            itemAddon != normalizedAddon) {
          continue;
        }
        matches.add(row);
      } catch (_) {
        // Malformed rows are ignored rather than making playback fail.
      }
    }
    if (matches.length != 1) return false;
    rows.remove(matches.single);
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      await prefs.setString(_myWatchlistKey, jsonEncode(rows));
    }
    return true;
  }

  static Future<void> clearMyWatchlist() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_myWatchlistKey);
  }

  // ==========================================================================
  // Debrify TV Channel Favorites
  // ==========================================================================

  /// Check if a Debrify TV channel is favorited
  static Future<bool> isDebrifyTvChannelFavorited(String channelId) async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
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

  /// Canonical comparison key for an IPTV channel URL (see
  /// [IptvMediaStore.canonicalChannelKey]).
  static String canonicalIptvChannelKey(String url) {
    return IptvMediaStore.canonicalChannelKey(url);
  }

  /// Rewrite stored favorite URLs to the current format when a fetched
  /// channel matches an existing favorite canonically but not literally
  /// (e.g. favorites saved before the Xtream /live/ URL fix). Keeps the
  /// Home favorites row playing working URLs.
  static Future<void> reconcileIptvFavoriteUrls(List<IptvChannel> channels) {
    return IptvMediaStore.reconcileFavoriteUrls(channels);
  }

  /// DB-catalog variant: the fresh URLs come from the catalog rows on a
  /// worker isolate instead of a channel list.
  static Future<void> reconcileIptvFavoriteUrlsForCatalog(String catalogKey) {
    return IptvMediaStore.reconcileFavoriteUrlsForCatalog(catalogKey);
  }

  /// Set favorite status for an IPTV channel
  static Future<void> setIptvChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelFavorited(
      channelUrl,
      isFavorited,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  // ── IPTV custom lists ────────────────────────────────────────────────────

  /// Reserved id of the built-in Favorites list.
  static const String iptvFavoritesListId = IptvMediaStore.favoritesListId;

  /// Every channel list, Favorites first then custom lists in user order.
  static Future<List<IptvListMeta>> getIptvLists() {
    return IptvMediaStore.lists();
  }

  /// Create a channel list and return its id.
  static Future<String> createIptvList(String name) {
    return IptvMediaStore.createList(name);
  }

  static Future<void> renameIptvList(String listId, String name) {
    return IptvMediaStore.renameList(listId, name);
  }

  /// Delete a custom list. The channels themselves are untouched.
  static Future<void> deleteIptvList(String listId) {
    return IptvMediaStore.deleteList(listId);
  }

  static Future<void> reorderIptvLists(List<String> orderedIds) {
    return IptvMediaStore.reorderLists(orderedIds);
  }

  /// Add or remove a channel in a list.
  static Future<void> setIptvChannelInList(
    String listId,
    String channelUrl,
    bool inList, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelInList(
      listId,
      channelUrl,
      inList,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  /// One list's channels, url → metadata.
  static Future<Map<String, Map<String, dynamic>>> getIptvListChannels(
    String listId,
  ) {
    return IptvMediaStore.listChannels(listId);
  }

  /// Persist the display order of channels inside Favorites or a custom list.
  static Future<void> reorderIptvListChannels(
    String listId,
    Iterable<String> orderedUrls,
  ) {
    return IptvMediaStore.reorderListChannels(listId, orderedUrls);
  }

  static Future<List<IptvChannelOrderEntry>> getIptvCategoryOrderEntries(
    String sourceId,
    Iterable<IptvChannel> channels,
    String group,
  ) {
    return IptvMediaStore.categoryOrderEntries(sourceId, channels, group);
  }

  static Future<void> setIptvCategoryChannelOrder(
    String sourceId,
    String group,
    Iterable<IptvChannelOrderIdentity> ordered,
  ) {
    return IptvMediaStore.setCategoryChannelOrder(sourceId, group, ordered);
  }

  static Future<List<IptvChannel>> applyIptvCategoryChannelOrders(
    String sourceId,
    List<IptvChannel> channels,
  ) {
    return IptvMediaStore.applyCategoryChannelOrders(sourceId, channels);
  }

  static Future<void> removeIptvCategoryOrdersForSource(String sourceId) {
    return IptvMediaStore.removeCategoryOrdersForSource(sourceId);
  }

  /// Which lists each stored channel belongs to, url → list ids.
  static Future<Map<String, Set<String>>> getIptvChannelMembership() {
    return IptvMediaStore.channelMembership();
  }

  /// Membership + per-(list, url) origin providers in one read (see
  /// [IptvMediaStore.membershipSnapshot]).
  static Future<
    ({
      Map<String, Set<String>> membership,
      Map<(String, String), String> origins,
    })
  >
  getIptvMembershipSnapshot() {
    return IptvMediaStore.membershipSnapshot();
  }

  /// The lists one channel belongs to, matched canonically.
  static Future<Set<String>> getIptvListsForChannel(String channelUrl) {
    return IptvMediaStore.listsForChannel(channelUrl);
  }

  /// Remove every membership belonging to a playlist, across all lists.
  static Future<void> removeIptvListChannelsByPlaylistId(String playlistId) {
    return IptvMediaStore.removeListChannelsByPlaylistId(playlistId);
  }

  /// Per-channel HTTP headers stored with a favorite (see
  /// [setIptvChannelFavorited]). JSON round-trips them as a dynamic map, and
  /// favorites saved before headers existed simply have none.
  static Map<String, String> iptvFavoriteHeaders(Map<String, dynamic> meta) {
    final raw = meta['httpHeaders'];
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers;
  }

  /// Remove all IPTV favorites that belong to a specific playlist
  static Future<void> removeIptvFavoritesByPlaylistId(String playlistId) {
    return IptvMediaStore.removeFavoritesByPlaylistId(playlistId);
  }

  /// Get all favorite IPTV channel URLs with metadata
  static Future<Map<String, Map<String, dynamic>>> getIptvFavoriteChannels() {
    return IptvMediaStore.favoriteChannels();
  }

  /// Get all favorite IPTV channel URLs
  static Future<Set<String>> getIptvFavoriteChannelUrls() async {
    final favorites = await getIptvFavoriteChannels();
    return favorites.keys.toSet();
  }

  // ── IPTV watch history (backs the virtual "Continue watching" playlist) ──

  /// A watched item counts as in-progress between these fractions: below the
  /// floor nothing meaningful was watched (a mis-click, or a few seconds of
  /// buffering), and above the ceiling it's effectively finished.
  static const double _iptvWatchStartedFraction = 0.02;
  static const double iptvWatchFinishedFraction = 0.95;

  /// Whether on-demand IPTV playback feeds the Continue Watching shelves at
  /// all. Off is enforced at BOTH ends — nothing new is recorded, and whatever
  /// is already stored is filtered out of [getIptvContinueWatching] — so the
  /// shelves empty out immediately without deleting anything: turning it back
  /// on restores the rows that were there.
  ///
  /// Deliberately does NOT touch playback positions. Those live in the
  /// separate video-resume store, which the players write directly and which
  /// backs both resuming a movie where you left off and the progress bars on
  /// VOD/episode cards — all of that keeps working with tracking off.
  static const String _iptvTrackContinueWatchingKey =
      'iptv_track_continue_watching';

  static Future<bool> getIptvTrackContinueWatching() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvTrackContinueWatchingKey) ?? true;
  }

  static Future<void> setIptvTrackContinueWatching(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvTrackContinueWatchingKey, value);
  }

  /// Remember that an on-demand IPTV item was played, capturing enough
  /// metadata to rebuild its row without re-fetching the panel — the same
  /// trick [setIptvChannelFavorited] uses, and necessary for the same reason:
  /// the provider's catalog can be renumbered or gone by the time the shelf
  /// is read.
  ///
  /// The playback position is deliberately NOT stored here. Both players
  /// already write it to the shared video-resume store keyed by stream URL,
  /// and copying it would hand the shelf a second, staler truth to disagree
  /// with; [getIptvContinueWatching] joins the two at read time instead.
  ///
  /// A no-op when [getIptvTrackContinueWatching] is off. Gating here rather
  /// than at each caller is deliberate: this is the single funnel every
  /// on-demand play goes through — both players, the IPTV page, the series
  /// page, the Home shelf, and the native TV player's bridge hop — and live
  /// channels never reach it.
  static Future<void> recordIptvWatch(
    String channelUrl, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
    // Series-episode markers (Xtream series only). When set, the Continue
    // Watching shelf collapses a series' episodes into one row and keeps the
    // series present after a mid-series episode finishes. Absent for movies /
    // catchup / live — their behavior is unchanged.
    String? seriesId,
    String? seriesName,
    int? season,
    int? episode,
    bool? hasNextEpisode,
  }) async {
    if (!await getIptvTrackContinueWatching()) return;
    return IptvMediaStore.recordWatch(
      channelUrl,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      httpHeaders: httpHeaders,
      seriesId: seriesId,
      seriesName: seriesName,
      season: season,
      episode: episode,
      hasNextEpisode: hasNextEpisode,
    );
  }

  static int _iptvWatchTimestamp(dynamic meta) {
    if (meta is Map) {
      final value = meta['lastPlayedAt'];
      if (value is num) return value.toInt();
    }
    return 0;
  }

  /// All remembered on-demand IPTV items (url → metadata).
  static Future<Map<String, Map<String, dynamic>>> getIptvWatchHistory() {
    return IptvMediaStore.watchHistory();
  }

  /// Watched-but-unfinished IPTV items, most recent first. Joins the metadata
  /// captured at play time with the position the players persist to the
  /// video-resume store (both keyed by stream URL), so an item only appears
  /// once it has real progress behind it.
  ///
  /// Each entry is the stored metadata plus `url`, `positionMs`, `durationMs`
  /// and `progress` (0-1).
  static Future<List<Map<String, dynamic>>> getIptvContinueWatching() async {
    // Tracking off hides the shelf everywhere at once: Home's two IPTV rows,
    // the IPTV page's virtual `continue://` playlist (which already drops
    // itself when this comes back empty), and the command rail's count.
    if (!await getIptvTrackContinueWatching()) return [];
    final history = await getIptvWatchHistory();
    if (history.isEmpty) return [];

    // History is capped at 100 entries, so this is a small batched lookup.
    final resumeMap = await IptvMediaStore.resumeEntries(history.keys);

    // Series identity for grouping: <playlistId>::<seriesId>. Same shape the
    // shelf and per-series audio use.
    String? seriesKeyOf(Map<String, dynamic> meta) {
      final sid = meta['seriesId'];
      if (sid == null || (sid is String && sid.isEmpty)) return null;
      return '${meta['playlistId'] ?? ''}::$sid';
    }

    // First pass: gather every started entry with its recency, and track the
    // most-recent recency per series.
    final started = <Map<String, dynamic>>[];
    final seriesLatest = <String, int>{};
    for (final entry in history.entries) {
      final resume = resumeMap[entry.key];
      if (resume == null) continue;
      final positionMs = (resume['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (resume['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) continue;
      final progress = positionMs / durationMs;
      if (progress < _iptvWatchStartedFraction) continue;

      final sortAt =
          (resume['updatedAt'] as num?)?.toInt() ??
          _iptvWatchTimestamp(entry.value);
      final seriesKey = seriesKeyOf(entry.value);
      if (seriesKey != null) {
        final prev = seriesLatest[seriesKey];
        if (prev == null || sortAt > prev) seriesLatest[seriesKey] = sortAt;
      }
      started.add({
        ...entry.value,
        'url': entry.key,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'progress': progress,
        // Prefer when playback last moved; a rebuilt-metadata entry can be
        // older than the watching it describes.
        'sortAt': sortAt,
        if (seriesKey != null) '_seriesKey': seriesKey,
      });
    }

    // Second pass: a partially-watched item always shows. A FINISHED item is
    // kept only when it's a series episode that (a) still has a next episode
    // and (b) is the most-recent watched episode of its series — so a series
    // stays for "next up" after finishing a middle episode, but leaves once
    // its finale (or last-watched episode) is done. Movies/catchup and older
    // finished episodes drop out as before.
    final items = <Map<String, dynamic>>[];
    for (final item in started) {
      final progress = item['progress'] as double;
      if (progress <= iptvWatchFinishedFraction) {
        items.add(item);
        continue;
      }
      final seriesKey = item['_seriesKey'] as String?;
      final keep =
          seriesKey != null &&
          item['hasNext'] == true &&
          (item['sortAt'] as int) == seriesLatest[seriesKey];
      if (keep) items.add(item);
    }

    items.sort((a, b) => (b['sortAt'] as int).compareTo(a['sortAt'] as int));
    return items;
  }

  /// Stored position/duration for whichever of [urls] the players have
  /// progress for. Reads the resume map once — callers are typically a list of
  /// thousands of rows.
  static Future<
    Map<String, ({int positionMs, int durationMs, double fraction})>
  >
  _iptvResumeStates(Iterable<String> urls) async {
    final wanted = urls.toSet();
    if (wanted.isEmpty) return {};

    final resumeMap = await IptvMediaStore.resumeEntries(wanted);
    final states =
        <String, ({int positionMs, int durationMs, double fraction})>{};
    for (final entry in resumeMap.entries) {
      final resume = entry.value;
      final positionMs = (resume['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (resume['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) continue;
      states[entry.key] = (
        positionMs: positionMs,
        durationMs: durationMs,
        fraction: (positionMs / durationMs).clamp(0.0, 1.0),
      );
    }
    return states;
  }

  /// Resume fractions (0-1) for whichever of [urls] have been started. No
  /// upper bound — a finished item shows a full bar, which is the point.
  static Future<Map<String, double>> getIptvProgressForUrls(
    Iterable<String> urls,
  ) async {
    final states = await _iptvResumeStates(urls);
    return {
      for (final entry in states.entries)
        if (entry.value.fraction >= _iptvWatchStartedFraction)
          entry.key: entry.value.fraction,
    };
  }

  /// Resume position in ms for each part-watched item among [urls], using the
  /// same window as the shelf — so a finished item restarts from the
  /// beginning rather than resuming a second from the end.
  static Future<Map<String, int>> getIptvResumePositions(
    Iterable<String> urls,
  ) async {
    final states = await _iptvResumeStates(urls);
    return {
      for (final entry in states.entries)
        if (entry.value.fraction >= _iptvWatchStartedFraction &&
            entry.value.fraction <= iptvWatchFinishedFraction)
          entry.key: entry.value.positionMs,
    };
  }

  /// Remove all watch history that belongs to a deleted playlist — mirrors
  /// [removeIptvFavoritesByPlaylistId] so a removed provider leaves nothing
  /// behind pointing at URLs that no longer authenticate.
  static Future<void> removeIptvWatchHistoryByPlaylistId(String playlistId) {
    return IptvMediaStore.removeWatchHistoryByPlaylistId(playlistId);
  }

  /// Take one on-demand IPTV item off the Continue Watching shelf (history +
  /// saved position). The local counterpart of [removeContinueWatchingItem].
  static Future<void> removeIptvContinueWatchingItem(String url) {
    return IptvMediaStore.removeWatchEntry(url);
  }

  /// Take a whole IPTV series off the Continue Watching shelf — every watched
  /// episode of it, since the shelf collapses them into one card.
  static Future<void> removeIptvContinueWatchingSeries({
    required String playlistId,
    required String seriesId,
  }) {
    return IptvMediaStore.removeWatchSeries(
      playlistId: playlistId,
      seriesId: seriesId,
    );
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
      final videoKey =
          'video_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
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
        final fullTitleKey =
            'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Variation 2: Try extracting clean title (like "game of thrones" from torrent name)
        // This matches how SeriesPlaylist extracts the title
        String cleanedTitle = title;

        // Remove common patterns to extract series name
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.S\d{2}.*', caseSensitive: false),
          '',
        ); // Remove S01-S08 and everything after
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.Season\..*', caseSensitive: false),
          '',
        ); // Remove Season.1-8
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(1080p|720p|2160p|4k).*', caseSensitive: false),
          '',
        ); // Remove quality
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(x264|x265|h264|h265).*', caseSensitive: false),
          '',
        ); // Remove codec
        cleanedTitle = cleanedTitle.replaceAll(
          RegExp(r'\.(BluRay|WEB|HDTV|WEBRip).*', caseSensitive: false),
          '',
        ); // Remove source
        cleanedTitle = cleanedTitle.replaceAll('.', ' ').trim();

        final cleanTitleKey =
            'series_${cleanedTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

        // Try both variations - PRIORITIZE clean title first (where playback state is actually saved)
        if (playbackStateMap[cleanTitleKey] != null &&
            playbackStateMap[cleanTitleKey]['type'] == 'series') {
          matchingSeriesKey = cleanTitleKey;
          seriesState = playbackStateMap[cleanTitleKey] as Map<String, dynamic>;
        } else if (playbackStateMap[fullTitleKey] != null &&
            playbackStateMap[fullTitleKey]['type'] == 'series') {
          matchingSeriesKey = fullTitleKey;
          seriesState = playbackStateMap[fullTitleKey] as Map<String, dynamic>;
        } else {
          // Fallback: Search through all series entries for a partial match
          for (final entry in playbackStateMap.entries) {
            if (entry.key.startsWith('series_') &&
                entry.value['type'] == 'series') {
              final seriesTitle =
                  (entry.value['title'] as String?)?.toLowerCase() ?? '';
              final itemTitleLower = title.toLowerCase();

              // Check if the series title is contained in the item title or vice versa
              if (itemTitleLower.contains(seriesTitle) ||
                  seriesTitle.contains(cleanedTitle.toLowerCase())) {
                matchingSeriesKey = entry.key;
                seriesState = entry.value as Map<String, dynamic>;
                break;
              }
            }
          }
        }

        if (seriesState != null && matchingSeriesKey != null) {
          debugPrint(
            '📺 Matched series state for "$title" using key: $matchingSeriesKey',
          );

          // Calculate overall series progress (Option 2)
          // Formula: (finished episodes + partial episode progress) / total episodes

          int totalEpisodes =
              (item['fileCount'] as int?) ?? (item['count'] as int?) ?? 0;
          if (totalEpisodes == 0) {
            // Try to count from the playlist item structure
            totalEpisodes = 1; // Fallback to at least 1
          }

          // Count finished episodes from both finishedEpisodes and seasons maps
          // Use a Set to track which episodes are finished to avoid double-counting
          final Set<String> finishedEpisodeKeys = {};
          int finishedEpisodeCount = 0;

          // First, count episodes explicitly marked as finished (TV series)
          final finishedEpisodes =
              seriesState['finishedEpisodes'] as Map<String, dynamic>?;
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
          if (latestDuration > 0 &&
              latestPosition > 0 &&
              latestEpisodeKey != null) {
            partialEpisodeProgress = latestPosition / latestDuration;
            // Only count as partial if < 95% (not already counted as finished)
            if (partialEpisodeProgress < 0.95 &&
                !finishedEpisodeKeys.contains(latestEpisodeKey)) {
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
            final syntheticDuration =
                totalEpisodes * 1000000; // 1M ms per episode (arbitrary)
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

    debugPrint(
      'StorageService: Built progress map with ${progressMap.length} entries',
    );
    return progressMap;
  }

  // Startup auto-launch was removed; only [clearAllStartupSettings] remains
  // (used by Reset) to wipe the old persisted keys.

  // Home Page Default Settings
  static Future<String?> getHomeDefaultSourceType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultSourceTypeKey);
  }

  static Future<void> setHomeDefaultSourceType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultSourceTypeKey);
    } else {
      await prefs.setString(_homeDefaultSourceTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultAddonUrl() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultAddonUrlKey);
  }

  static Future<void> setHomeDefaultAddonUrl(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultAddonUrlKey);
    } else {
      await prefs.setString(_homeDefaultAddonUrlKey, value);
    }
  }

  static Future<String?> getHomeDefaultCatalogId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultCatalogIdKey);
  }

  static Future<void> setHomeDefaultCatalogId(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultCatalogIdKey);
    } else {
      await prefs.setString(_homeDefaultCatalogIdKey, value);
    }
  }

  static Future<String?> getHomeDefaultTraktListType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultTraktListTypeKey);
  }

  static Future<void> setHomeDefaultTraktListType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultTraktListTypeKey);
    } else {
      await prefs.setString(_homeDefaultTraktListTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultTraktContentType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultTraktContentTypeKey);
  }

  static Future<void> setHomeDefaultTraktContentType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultTraktContentTypeKey);
    } else {
      await prefs.setString(_homeDefaultTraktContentTypeKey, value);
    }
  }

  static Future<bool> getHomeHideProviderCards() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideProviderCardsKey) ?? true;
  }

  static Future<void> setHomeHideProviderCards(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideProviderCardsKey, value);
  }

  static Future<bool> getHomeContinueWatchingEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeContinueWatchingEnabledKey) ?? true;
  }

  static Future<void> setHomeContinueWatchingEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeContinueWatchingEnabledKey, value);
  }

  /// Whether holding a Continue Watching card should immediately Quick Play
  /// instead of opening the Play / Remove action menu. Off by default so the
  /// removal action remains discoverable until the user opts into the faster
  /// gesture.
  static Future<bool> getHomeCwHoldToQuickPlay() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeCwHoldToQuickPlayKey) ?? false;
  }

  static Future<void> setHomeCwHoldToQuickPlay(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeCwHoldToQuickPlayKey, value);
  }

  /// Whether [provider]'s home Continue Watching shelf combines Movies and
  /// Shows into ONE recency-ordered row instead of two. [provider] is one of
  /// 'local', 'trakt', 'simkl', 'mdblist'. Off by default (two rows, the
  /// original layout).
  static Future<bool> getHomeCwMergedRows(String provider) async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('$_homeCwMergedRowsKeyPrefix$provider') ?? false;
  }

  static Future<void> setHomeCwMergedRows(String provider, bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('$_homeCwMergedRowsKeyPrefix$provider', value);
  }

  static Future<String> getHomeFavoritesTapAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeFavoritesOpenFolderKey) ?? 'choose';
  }

  static Future<void> setHomeFavoritesTapAction(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_homeFavoritesOpenFolderKey, value);
  }

  /// Landscape is the DEFAULT (since 0.8.4): the absence of the key means
  /// landscape, so only an explicit 'portrait' choice reads as portrait.
  static Future<HomeCardOrientation> getHomeCardOrientation() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeCardOrientationKey) == 'portrait'
        ? HomeCardOrientation.portrait
        : HomeCardOrientation.landscape;
  }

  static Future<void> setHomeCardOrientation(
    HomeCardOrientation orientation,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_homeCardOrientationKey, orientation.name);
  }

  /// Keeps Home artwork clean by suppressing the title and rating painted on
  /// content cards. Row headings, hero identity, progress and context metadata
  /// are separate presentation and remain visible.
  static Future<bool> getHomeHideCardTitlesAndRatings() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideCardTitlesAndRatingsKey) ?? false;
  }

  static Future<void> setHomeHideCardTitlesAndRatings(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideCardTitlesAndRatingsKey, value);
  }

  /// Suppresses the source/add-on pill beside Home catalog row headings.
  /// The catalog title itself remains visible so the row keeps its identity.
  static Future<bool> getHomeHideCatalogAddonNames() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideCatalogAddonNamesKey) ?? false;
  }

  static Future<void> setHomeHideCatalogAddonNames(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideCatalogAddonNamesKey, value);
  }

  static Future<void> clearAllHomePageSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_homeDefaultSourceTypeKey);
    await prefs.remove(_homeDefaultAddonUrlKey);
    await prefs.remove(_homeDefaultCatalogIdKey);
    await prefs.remove(_homeHideProviderCardsKey);
    await prefs.remove(_homeContinueWatchingEnabledKey);
    await prefs.remove(_homeCwHoldToQuickPlayKey);
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}local');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}trakt');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}simkl');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}mdblist');
    await prefs.remove(_homeFavoritesOpenFolderKey);
    await prefs.remove(_homeCardOrientationKey);
    await prefs.remove(_homeHideCardTitlesAndRatingsKey);
    await prefs.remove(_homeHideCatalogAddonNamesKey);
  }

  // Reddit Settings
  static Future<String?> getRedditAccessToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _redditAccessTokenKey);
  }

  static Future<void> setRedditAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _redditAccessTokenKey, token);
  }

  static Future<String?> getRedditRefreshToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _redditRefreshTokenKey);
  }

  static Future<void> setRedditRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _redditRefreshTokenKey, token);
  }

  static Future<String?> getRedditUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditUsernameKey);
  }

  static Future<void> setRedditUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_redditUsernameKey, username);
  }

  static Future<bool> getRedditEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditEnabledKey) ?? true; // Default enabled
  }

  static Future<void> setRedditEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_redditEnabledKey, value);
  }

  static Future<bool> getRedditHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditHiddenFromNavKey) ?? false;
  }

  static Future<void> setRedditHiddenFromNav(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_redditHiddenFromNavKey, value);
  }

  // Tracking source policy -------------------------------------------------

  static const Set<TrackingSource> _allTrackingSources = <TrackingSource>{
    TrackingSource.local,
    TrackingSource.trakt,
    TrackingSource.simkl,
    TrackingSource.mdblist,
  };

  /// Reads the new master scrobble switches. On first read, adopt the retired
  /// per-tracker catalog switches once. An absent legacy value means ON: that
  /// matches interactive connection and old Trakt/Simkl restore behavior.
  static Future<Set<TrackingSource>> getTrackingScrobbleTargets() =>
      TrackingScrobblePreferences.readCurrent();

  static Future<void> setTrackingScrobbleTargets(
    Set<TrackingSource> value,
  ) async {
    await TrackingScrobblePreferences.writeCurrent(value);
    trackingSourceRevision.value++;
  }

  /// Turns on scrobbling for a newly connected tracker without disturbing the
  /// user's choices for any other tracker. Connection flows call this after
  /// authentication succeeds so reconnecting restores the provider's default
  /// ON state even when it had previously been unticked.
  static Future<void> enableTrackingScrobbleTarget(
    TrackingSource source,
  ) async {
    final changed = await TrackingScrobblePreferences.enableCurrent(source);
    if (changed) trackingSourceRevision.value++;
  }

  static Future<WatchProgressSource> getWatchProgressSource() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getString(watchProgressSourceKey);
    return WatchProgressSource.values.firstWhere(
      (source) => source.name == stored,
      orElse: () => WatchProgressSource.smart,
    );
  }

  static Future<void> setWatchProgressSource(WatchProgressSource value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(watchProgressSourceKey, value.name);
    trackingSourceRevision.value++;
  }

  static Future<bool> fallbackDisconnectedProgressSource(
    TrackingSource disconnected,
  ) async {
    final current = await getWatchProgressSource();
    final owns = switch (current) {
      WatchProgressSource.trakt => disconnected == TrackingSource.trakt,
      WatchProgressSource.simkl => disconnected == TrackingSource.simkl,
      WatchProgressSource.mdblist => disconnected == TrackingSource.mdblist,
      _ => false,
    };
    if (!owns) return false;
    await setWatchProgressSource(WatchProgressSource.smart);
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('tracking_progress_fallback_notice', true);
    return true;
  }

  static Future<bool> takeTrackingProgressFallbackNotice() async {
    final prefs = await ProfilePreferences.instance();
    final pending = prefs.getBool('tracking_progress_fallback_notice') ?? false;
    if (pending) await prefs.remove('tracking_progress_fallback_notice');
    return pending;
  }

  static Future<Set<TrackingSource>> getHomeTickSources() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(homeTickSourcesKey);
    if (stored == null) return Set<TrackingSource>.of(_allTrackingSources);
    return <TrackingSource>{
      for (final value in stored)
        if (TrackingSourceStorageName.parse(value) case final source?) source,
    };
  }

  static Future<void> setHomeTickSources(Set<TrackingSource> value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = value.where(_allTrackingSources.contains).toSet();
    await prefs.setStringList(
      homeTickSourcesKey,
      normalized.map((source) => source.storageName).toList(growable: false),
    );
    trackingSourceRevision.value++;
  }

  static Future<Map<String, dynamic>> buildTrackingPreferencesPayload() async {
    final scrobble = await getTrackingScrobbleTargets();
    final progress = await getWatchProgressSource();
    final ticks = await getHomeTickSources();
    return <String, dynamic>{
      'scrobble_targets': scrobble
          .map((source) => source.storageName)
          .toList(growable: false),
      'progress_source': progress.name,
      'home_tick_sources': ticks
          .map((source) => source.storageName)
          .toList(growable: false),
    };
  }

  /// Re-adopts the legacy per-tracker switches after restoring an OLD backup
  /// with no tracking payload. The masters were already seeded on first policy
  /// read at app start, so without this the restored legacy values — notably an
  /// MDBList sync-catalog OFF — would be silently ignored.
  static Future<void> reseedTrackingScrobbleTargetsFromLegacy() async {
    await TrackingScrobblePreferences.reseedCurrentFromLegacy();
    trackingSourceRevision.value++;
  }

  /// Applies only explicitly present new-format preferences. Old backups omit
  /// this object; [reseedTrackingScrobbleTargetsFromLegacy] runs on that
  /// restore path instead so the restored legacy switches are re-adopted by
  /// [getTrackingScrobbleTargets], preserving the absent-key migration rule.
  static Future<void> applyTrackingPreferencesPayload(
    Map<dynamic, dynamic> payload,
  ) async {
    final scrobble = payload['scrobble_targets'];
    if (scrobble is List) {
      await setTrackingScrobbleTargets(<TrackingSource>{
        for (final value in scrobble.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
    final progress = payload['progress_source'];
    if (progress is String) {
      final parsed = WatchProgressSource.values
          .where((source) => source.name == progress)
          .firstOrNull;
      if (parsed != null) await setWatchProgressSource(parsed);
    }
    final ticks = payload['home_tick_sources'];
    if (ticks is List) {
      await setHomeTickSources(<TrackingSource>{
        for (final value in ticks.whereType<String>())
          if (TrackingSourceStorageName.parse(value) case final source?) source,
      });
    }
  }

  static Future<String?> getRedditLastSubreddit() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditLastSubredditKey);
  }

  static Future<void> setRedditLastSubreddit(String subreddit) async {
    final prefs = await ProfilePreferences.instance();
    if (prefs.getString(_redditLastSubredditKey) == subreddit) return;
    await prefs.setString(_redditLastSubredditKey, subreddit);
  }

  static Future<void> clearRedditAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_redditAccessTokenKey)) {
      await prefs.remove(_redditAccessTokenKey);
      await prefs.remove(_redditRefreshTokenKey);
    }
    await prefs.remove(_redditUsernameKey);
  }

  // Trakt Settings
  static Future<bool> getTraktSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('trakt_sync_catalog_items') ?? false;
  }

  static Future<void> setTraktSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('trakt_sync_catalog_items', value);
  }

  static Future<String?> getTraktAccessToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _traktAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _traktAccessTokenKey);
  }

  static Future<bool> hasTraktCredential() =>
      _credentialConfigured(_traktAccessTokenKey, () => getTraktAccessToken());

  static Future<void> setTraktAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _traktAccessTokenKey, token);
  }

  static Future<String?> getTraktRefreshToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _traktRefreshTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _traktRefreshTokenKey);
  }

  static Future<void> setTraktRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _traktRefreshTokenKey, token);
  }

  static Future<String?> getTraktUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_traktUsernameKey);
  }

  static Future<void> setTraktUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_traktUsernameKey, username);
  }

  static Future<int?> getTraktTokenExpiry() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_traktTokenExpiryKey);
  }

  static Future<void> setTraktTokenExpiry(int expiryMs) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_traktTokenExpiryKey, expiryMs);
  }

  /// Clears the local Trakt connection first and reports whether this profile
  /// was its unshared owner. Only that disposition may revoke the upstream
  /// token; a borrower must never invalidate the account for other profiles.
  static Future<bool> clearTraktAuth() async {
    final prefs = await ProfilePreferences.instance();
    final disposition = await ProfileCredentialFacade.disconnectWithDisposition(
      _traktAccessTokenKey,
    );
    if (!disposition.handled) {
      await prefs.remove(_traktAccessTokenKey);
      await prefs.remove(_traktRefreshTokenKey);
    }
    await prefs.remove(_traktUsernameKey);
    await prefs.remove(_traktTokenExpiryKey);
    await fallbackDisconnectedProgressSource(TrackingSource.trakt);
    return !disposition.handled || disposition.shouldRevokeRemote;
  }

  static Future<void> setSimklSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('simkl_sync_catalog_items', value);
  }

  static Future<bool> getSimklSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('simkl_sync_catalog_items') ?? false;
  }

  static Future<void> setMdblistSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('mdblist_sync_catalog_items', value);
  }

  static Future<bool> getMdblistSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('mdblist_sync_catalog_items') ?? false;
  }

  static Future<String?> getSimklAccessToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _simklAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _simklAccessTokenKey);
  }

  static Future<bool> hasSimklCredential() =>
      _credentialConfigured(_simklAccessTokenKey, () => getSimklAccessToken());

  static Future<void> setSimklAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _simklAccessTokenKey, token);
  }

  static Future<String?> getSimklUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_simklUsernameKey);
  }

  static Future<void> setSimklUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_simklUsernameKey, username);
  }

  static Future<void> clearSimklAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_simklAccessTokenKey)) {
      await prefs.remove(_simklAccessTokenKey);
    }
    await prefs.remove(_simklUsernameKey);
    await fallbackDisconnectedProgressSource(TrackingSource.simkl);
  }

  static Future<List<String>> getRedditRecentSubreddits() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_redditRecentSubredditsKey) ?? [];
  }

  static Future<void> setRedditRecentSubreddits(List<String> subreddits) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_redditRecentSubredditsKey, subreddits);
  }

  static Future<bool> getRedditAllowNsfw() async {
    if (!await profileAllowsAdultContent()) return false;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_redditAllowNsfwKey) ?? false;
  }

  static Future<void> setRedditAllowNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _redditAllowNsfwKey,
      await profileAllowsAdultContent() && value,
    );
  }

  static Future<List<String>> getRedditFavoriteSubreddits() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_redditFavoriteSubredditsKey) ?? [];
  }

  static Future<void> setRedditFavoriteSubreddits(
    List<String> subreddits,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_redditFavoriteSubredditsKey, subreddits);
  }

  static Future<String?> getRedditDefaultSubreddit() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_redditDefaultSubredditKey);
  }

  static Future<void> setRedditDefaultSubreddit(String? subreddit) async {
    final prefs = await ProfilePreferences.instance();
    if (subreddit == null || subreddit.isEmpty) {
      await prefs.remove(_redditDefaultSubredditKey);
    } else {
      await prefs.setString(_redditDefaultSubredditKey, subreddit);
    }
  }

  // Lemmy Settings
  static Future<String> getLemmyInstance() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_lemmyInstanceKey);
    return (value != null && value.isNotEmpty) ? value : 'https://lemmy.world';
  }

  static Future<void> setLemmyInstance(String instance) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_lemmyInstanceKey, instance);
  }

  static Future<bool> getLemmyAllowNsfw() async {
    if (!await profileAllowsAdultContent()) return false;
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_lemmyAllowNsfwKey) ?? false;
  }

  static Future<void> setLemmyAllowNsfw(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(
      _lemmyAllowNsfwKey,
      await profileAllowsAdultContent() && value,
    );
  }

  static Future<List<String>> getLemmyFavoriteCommunities() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_lemmyFavoriteCommunitiesKey) ?? [];
  }

  static Future<void> setLemmyFavoriteCommunities(
    List<String> communities,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_lemmyFavoriteCommunitiesKey, communities);
  }

  static Future<String?> getLemmyDefaultCommunity() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_lemmyDefaultCommunityKey);
  }

  static Future<void> setLemmyDefaultCommunity(String? community) async {
    final prefs = await ProfilePreferences.instance();
    if (community == null || community.isEmpty) {
      await prefs.remove(_lemmyDefaultCommunityKey);
    } else {
      await prefs.setString(_lemmyDefaultCommunityKey, community);
    }
  }

  // YouTube Settings
  /// Preferred max playback height for YouTube (1080/720/480/360). Default 1080.
  static Future<int> getYoutubeMaxHeight() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getInt(_youtubeMaxHeightKey);
    return (v != null && v > 0) ? v : 1080;
  }

  static Future<void> setYoutubeMaxHeight(int height) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_youtubeMaxHeightKey, height);
  }

  /// Android TV IPTV video decoder: 'auto' | 'hardware' | 'software'.
  ///
  /// Some TV boxes (MediaTek/Amlogic especially) freeze the picture while
  /// audio keeps playing when their hardware decoder is handed a live stream
  /// it mishandles — a device defect no app can work around reliably, which
  /// is why every IPTV player ships this switch. 'software' puts Android's
  /// own software codecs (c2.android.* / OMX.google.*) first; 'auto' leaves
  /// the platform's decoder order untouched.
  static const List<String> iptvDecoderModes = ['auto', 'hardware', 'software'];

  static Future<String> getIptvDecoderMode() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_iptvDecoderModeKey) ?? 'auto';
    return iptvDecoderModes.contains(value) ? value : 'auto';
  }

  static Future<void> setIptvDecoderMode(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvDecoderModeKey,
      iptvDecoderModes.contains(value) ? value : 'auto',
    );
  }

  // Network tuning (Debrify player)
  /// 'standard' | 'extended' | 'patient'. Standard = player defaults untouched.
  static Future<String> getNetworkConnectPatience() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_networkConnectPatienceKey) ?? 'standard';
  }

  static Future<void> setNetworkConnectPatience(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_networkConnectPatienceKey, value);
  }

  /// 'standard' | 'large' | 'huge'. Standard = player defaults untouched.
  static Future<String> getNetworkBufferSize() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_networkBufferSizeKey) ?? 'standard';
  }

  static Future<void> setNetworkBufferSize(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_networkBufferSizeKey, value);
  }

  static int _normalizeLocalCompletionThreshold(int value) {
    return localCompletionThresholdOptions.contains(value)
        ? value
        : defaultLocalCompletionThreshold;
  }

  /// Percentage of a movie that must be watched before the local player marks
  /// it complete. Tracker-backed sessions retain Trakt/Simkl's own semantics.
  static Future<int> getMovieCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_movieCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setMovieCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _movieCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Percentage of an episode that must be watched before the local player
  /// marks it complete. Kept separate from movies because users commonly want
  /// a different rule for episode credits.
  static Future<int> getEpisodeCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_episodeCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setEpisodeCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _episodeCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Re-arms the resume-ghost purge for a restore/transfer preference overlay.
  ///
  /// A restore applies the package key-by-key over the destination profile, so
  /// a key the package does NOT carry keeps its destination value. A backup or
  /// device transfer taken on a pre-purge build carries `playback_state_v1`
  /// (ghosts and all) but no purge marker — so a destination that already ran
  /// the purge would keep `generation = 1` and never inspect the playback state
  /// it just imported, stranding those ghosts forever. Resetting the marker
  /// alongside imported playback lets the one-shot purge run once more against
  /// the new data.
  ///
  /// A package that DOES carry a marker came from a build that already purged
  /// at the source, so its value is honoured untouched.
  static void rearmGhostPurgeForImportedPlayback(
    Map<String, Object?> preferences,
  ) {
    if (!preferences.containsKey(_playbackStateKey)) return;
    if (preferences.containsKey(_resumeGhostPurgeGenerationKey)) return;
    preferences[_resumeGhostPurgeGenerationKey] = 0;
  }

  /// One-time, per-profile purge of the resume "ghosts" older builds minted
  /// when an episode was unwatched.
  ///
  /// Until [_clearEpisodeCompletion] learned to drop the row, unwatching a
  /// fully-watched episode zeroed its `positionMs` and stamped `updatedAt` to
  /// now. The leftover row reads as "played, 0% in, not finished", which is the
  /// newest thing in the series — so it won `getLastPlayedEpisode*` and pinned
  /// Continue Watching (home card, detail pill, and Play alike) to an episode
  /// the user had just declared unwatched. Repeating mark→unmark to shake it
  /// loose only re-stamped it fresher.
  ///
  /// This runs ONCE rather than filtering on every read. A zero-position row is
  /// indistinguishable from an episode legitimately opened and closed before
  /// the first autosave tick, and permanently ignoring that shape would make a
  /// pack reopen the previous (already-watched) episode. Bounding the cleanup
  /// to one pass fixes the installs carrying a ghost — including ones that
  /// received it over a device transfer — while leaving normal playback
  /// bookkeeping exactly as it was.
  ///
  /// Rows marked in `finishedEpisodes` are kept: a mark-only watch stores the
  /// dummy 0ms/1ms shape and still means "watched".
  static Future<void> purgeUnwatchedResumeGhosts() async {
    final prefs = await ProfilePreferences.instance();
    final generation = prefs.getInt(_resumeGhostPurgeGenerationKey) ?? 0;
    if (generation >= _currentResumeGhostPurgeGeneration) return;

    final playback = await _getPlaybackStateMap();
    var purged = 0;

    for (final stateEntry in playback.values) {
      if (stateEntry is! Map<String, dynamic> ||
          stateEntry['type'] != 'series') {
        continue;
      }
      final seasons = stateEntry['seasons'];
      if (seasons is! Map) continue;
      final finishedEpisodes = stateEntry['finishedEpisodes'];

      for (final seasonKey in seasons.keys.toList()) {
        final episodes = seasons[seasonKey];
        if (episodes is! Map) continue;
        final seasonFinished = finishedEpisodes is Map
            ? finishedEpisodes[seasonKey]
            : null;

        for (final episodeKey in episodes.keys.toList()) {
          final episodeData = episodes[episodeKey];
          if (episodeData is! Map) continue;
          if (seasonFinished is Map && seasonFinished.containsKey(episodeKey)) {
            continue;
          }
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          // durationMs > 1 skips the mark-only dummy shape, which is already
          // excluded above whenever its completion record survived.
          if (positionMs == 0 && durationMs > 1) {
            episodes.remove(episodeKey);
            purged++;
          }
        }
        if (episodes.isEmpty) seasons.remove(seasonKey);
      }
    }

    if (purged > 0) {
      await _savePlaybackStateMap(playback, recordDeletions: true);
      localCompletionRevision.value++;
      debugPrint(
        'StorageService: purged $purged unwatched resume ghost(s) from playback state',
      );
    }
    await prefs.setInt(
      _resumeGhostPurgeGenerationKey,
      _currentResumeGhostPurgeGeneration,
    );
  }

  /// One-time, per-profile adoption of the local completion thresholds for
  /// playback recorded before threshold-based watched status existed.
  ///
  /// Movies at/above their threshold become locally finished and leave local
  /// Continue Watching. Series episodes at/above their threshold are folded
  /// into the existing `finishedEpisodes` structure used by episode ticks.
  /// Tracker data is deliberately untouched; this migration only rewrites the
  /// app's local playback state.
  static Future<void> migrateExistingPlaybackCompletionThresholds() async {
    final prefs = await ProfilePreferences.instance();
    final generation =
        prefs.getInt(_playbackCompletionMigrationGenerationKey) ?? 0;
    if (generation >= _currentPlaybackCompletionMigrationGeneration) return;

    final movieThreshold = await getMovieCompletionThreshold();
    final episodeThreshold = await getEpisodeCompletionThreshold();
    final playback = await _getPlaybackStateMap();
    final completedMovieIds = await _getFinishedMovieIds();
    final newlyCompletedMovieIds = <String>{};
    final completedMovieStateKeys = <String>{};
    final completedMovieResumeKeys = <String>{};
    var completedEpisodeCount = 0;
    var playbackChanged = false;

    for (final stateEntry in playback.entries) {
      final rawState = stateEntry.value;
      if (rawState is! Map<String, dynamic>) continue;

      if (rawState['type'] == 'video') {
        final imdbId = (rawState['imdbId'] as String?)?.trim().toLowerCase();
        final positionMs = (rawState['positionMs'] as num?)?.toInt() ?? 0;
        final durationMs = (rawState['durationMs'] as num?)?.toInt() ?? 0;
        if (imdbId == null ||
            imdbId.isEmpty ||
            durationMs <= 0 ||
            positionMs <= 0 ||
            positionMs * 100.0 / durationMs < movieThreshold) {
          continue;
        }
        completedMovieIds.add(imdbId);
        newlyCompletedMovieIds.add(imdbId);
        continue;
      }

      if (rawState['type'] != 'series') continue;
      final seasons = rawState['seasons'];
      if (seasons is! Map<String, dynamic>) continue;
      final finishedEpisodes = rawState['finishedEpisodes'] is Map
          ? Map<String, dynamic>.from(rawState['finishedEpisodes'] as Map)
          : <String, dynamic>{};

      for (final seasonEntry in seasons.entries) {
        final episodesRaw = seasonEntry.value;
        if (episodesRaw is! Map) continue;
        final seasonFinished = finishedEpisodes[seasonEntry.key] is Map
            ? Map<String, dynamic>.from(
                finishedEpisodes[seasonEntry.key] as Map,
              )
            : <String, dynamic>{};

        for (final episodeEntry in episodesRaw.entries) {
          if (episodeEntry.value is! Map) continue;
          final episodeData = Map<String, dynamic>.from(
            episodeEntry.value as Map,
          );
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          if (durationMs <= 0 ||
              positionMs <= 0 ||
              positionMs * 100.0 / durationMs < episodeThreshold ||
              seasonFinished.containsKey(episodeEntry.key)) {
            continue;
          }

          seasonFinished[episodeEntry.key.toString()] = {
            'finishedAt':
                (episodeData['updatedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          };
          // Keep the episode's historical updatedAt so migration does not
          // reorder a show's "last played" episode.
          episodeData['positionMs'] = durationMs;
          episodesRaw[episodeEntry.key] = episodeData;
          completedEpisodeCount++;
          playbackChanged = true;
        }

        if (seasonFinished.isNotEmpty) {
          finishedEpisodes[seasonEntry.key] = seasonFinished;
        }
      }
      rawState['finishedEpisodes'] = finishedEpisodes;
    }

    if (newlyCompletedMovieIds.isNotEmpty) {
      for (final stateEntry in playback.entries) {
        final state = stateEntry.value;
        if (state is! Map<String, dynamic> || state['type'] != 'video') {
          continue;
        }
        final imdbId = (state['imdbId'] as String?)?.trim().toLowerCase();
        if (imdbId != null && newlyCompletedMovieIds.contains(imdbId)) {
          completedMovieStateKeys.add(stateEntry.key);
          final resumeKey = (state['title'] as String?)?.trim();
          if (resumeKey != null && resumeKey.isNotEmpty) {
            completedMovieResumeKeys.add(resumeKey);
          }
        }
      }
      playback.removeWhere((key, _) => completedMovieStateKeys.contains(key));
      playbackChanged = true;
      await prefs.setStringList(
        _finishedMoviesKey,
        completedMovieIds.toList()..sort(),
      );
      localCompletionRevision.value++;

      final rawContinueWatching = prefs.getString(_continueWatchingKey);
      if (rawContinueWatching != null && rawContinueWatching.isNotEmpty) {
        try {
          final decoded = await decodeJsonAsync(rawContinueWatching);
          if (decoded is List) {
            final items = decoded
                .whereType<Map<String, dynamic>>()
                .map(Map<String, dynamic>.from)
                .where((item) {
                  final imdbId = (item['imdbId'] as String?)
                      ?.trim()
                      .toLowerCase();
                  return imdbId == null ||
                      !newlyCompletedMovieIds.contains(imdbId);
                })
                .toList();
            await _saveContinueWatchingItems(items);
          }
        } catch (_) {
          // Leave malformed legacy data untouched; the normal CW reader also
          // treats it as empty, and completion migration can still succeed.
        }
      }
    }

    // The older player resume store uses the playback state's title as its
    // key. Clear it as part of the same migration so a later rewatch cannot
    // resurrect a near-credits position after the enhanced state is removed.
    // Do this before saving the removal so a database failure leaves enough
    // playback metadata for the next startup to retry the cleanup.
    for (final resumeKey in completedMovieResumeKeys) {
      await removeVideoResume(
        resumeKey,
        origin: WebDavSyncMutationOrigin.migration,
      );
    }
    if (playbackChanged) {
      await _savePlaybackStateMap(playback, recordDeletions: true);
    }
    await prefs.setInt(
      _playbackCompletionMigrationGenerationKey,
      _currentPlaybackCompletionMigrationGeneration,
    );
    debugPrint(
      'StorageService: completion migration marked '
      '${newlyCompletedMovieIds.length} movies and '
      '$completedEpisodeCount episodes watched',
    );
  }

  // PikPak API Settings
  static Future<bool> getPikPakEnabled() async {
    final prefs = await ProfilePreferences.instance();
    if (!(prefs.getBool(_pikpakEnabledKey) ?? false)) return false;
    return _credentialConfigured(_pikpakEmailKey, () => getPikPakEmail());
  }

  static Future<bool> hasPikPakCredential() =>
      _credentialConfigured(_pikpakEmailKey, () => getPikPakEmail());

  static Future<void> setPikPakEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakEnabledKey, value);
  }

  static Future<String?> getPikPakEmail({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _pikpakEmailKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakEmailKey);
  }

  static Future<void> setPikPakEmail(String email) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakEmailKey, email);
  }

  static Future<String?> getPikPakPassword() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakPasswordKey);
  }

  static Future<void> setPikPakPassword(String password) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakPasswordKey, password);
  }

  static Future<String?> getPikPakAccessToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakAccessTokenKey);
  }

  static Future<void> setPikPakAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakAccessTokenKey, token);
  }

  static Future<String?> getPikPakRefreshToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakRefreshTokenKey);
  }

  static Future<void> setPikPakRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakRefreshTokenKey, token);
  }

  static Future<void> clearPikPakAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_pikpakEmailKey)) {
      await prefs.remove(_pikpakEmailKey);
      await prefs.remove(_pikpakPasswordKey);
      await prefs.remove(_pikpakAccessTokenKey);
      await prefs.remove(_pikpakRefreshTokenKey);
      await prefs.remove(_pikpakDeviceIdKey);
      await prefs.remove(_pikpakCaptchaTokenKey);
      await prefs.remove(_pikpakUserIdKey);
    }
    await prefs.setBool(_pikpakEnabledKey, false);

    // Also clear restricted folder settings and cached subfolder IDs
    await clearPikPakRestrictedFolder();
    await clearPikPakSubfolderCaches();
    await clearPikPakHiddenFromNav();
  }

  // PikPak Device ID and Captcha Token
  static Future<void> setPikPakDeviceId(String deviceId) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakDeviceIdKey, deviceId);
  }

  static Future<String?> getPikPakDeviceId() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakDeviceIdKey);
  }

  static Future<void> deletePikPakDeviceId() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakDeviceIdKey);
  }

  static Future<void> setPikPakCaptchaToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakCaptchaTokenKey, token);
  }

  static Future<String?> getPikPakCaptchaToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakCaptchaTokenKey);
  }

  static Future<void> clearPikPakCaptchaToken() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakCaptchaTokenKey);
  }

  static Future<void> setPikPakUserId(String userId) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakUserIdKey, userId);
  }

  static Future<String?> getPikPakUserId() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakUserIdKey);
  }

  // PikPak Show Videos Only
  static Future<bool> getPikPakShowVideosOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakShowVideosOnlyKey) ?? true; // Default to true
  }

  static Future<void> setPikPakShowVideosOnly(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakShowVideosOnlyKey, value);
  }

  // PikPak Ignore Small Videos (under 100MB)
  static Future<bool> getPikPakIgnoreSmallVideos() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakIgnoreSmallVideosKey) ??
        true; // Default to true
  }

  static Future<void> setPikPakIgnoreSmallVideos(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakIgnoreSmallVideosKey, value);
  }

  // PikPak Restricted Folder
  static Future<String?> getPikPakRestrictedFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakRestrictedFolderIdKey);
  }

  static Future<String?> getPikPakRestrictedFolderName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakRestrictedFolderNameKey);
  }

  static Future<void> setPikPakRestrictedFolder(
    String? folderId,
    String? folderName,
  ) async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakTorrentsFolderIdKey);
  }

  static Future<void> setPikPakTorrentsFolderId(String folderId) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakTorrentsFolderIdKey, folderId);
  }

  static Future<String?> getPikPakTvFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakTvFolderIdKey);
  }

  static Future<void> setPikPakTvFolderId(String folderId) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakTvFolderIdKey, folderId);
  }

  static Future<void> clearPikPakSubfolderCaches() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakTorrentsFolderIdKey);
    await prefs.remove(_pikpakTvFolderIdKey);
  }

  // PikPak Hidden from Navigation
  static Future<bool> getPikPakHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakHiddenFromNavKey) ?? false;
  }

  static Future<void> setPikPakHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakHiddenFromNavKey, hidden);
  }

  static Future<void> clearPikPakHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakHiddenFromNavKey);
  }

  // WebDAV Settings
  static Future<bool> getWebDavEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavEnabledKey) ?? false;
  }

  static Future<void> setWebDavEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavEnabledKey, value);
  }

  static Future<bool> getWebDavHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavHiddenFromNavKey) ?? false;
  }

  static Future<void> setWebDavHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavHiddenFromNavKey, hidden);
  }

  static Future<void> clearWebDavHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_webDavHiddenFromNavKey);
  }

  static Future<String?> getWebDavBaseUrl() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await getSelectedWebDavServer();
    return selected?.baseUrl ??
        await SecretVault.getString(prefs, _webDavBaseUrlKey);
  }

  static Future<void> setWebDavBaseUrl(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await getWebDavServers(forSettings: false);
        await saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: value,
                    username: item.username,
                    password: item.password,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _webDavBaseUrlKey, value);
  }

  static Future<String?> getWebDavUsername() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await getSelectedWebDavServer();
    return selected?.username ??
        await SecretVault.getString(prefs, _webDavUsernameKey);
  }

  static Future<void> setWebDavUsername(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await getWebDavServers(forSettings: false);
        await saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: item.baseUrl,
                    username: value,
                    password: item.password,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _webDavUsernameKey, value);
  }

  static Future<String?> getWebDavPassword() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await getSelectedWebDavServer();
    return selected?.password ??
        await SecretVault.getString(prefs, _webDavPasswordKey);
  }

  static Future<void> setWebDavPassword(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await getWebDavServers(forSettings: false);
        await saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: item.baseUrl,
                    username: item.username,
                    password: value,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _webDavPasswordKey, value);
  }

  static Future<bool> getWebDavShowVideosOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavShowVideosOnlyKey) ?? true;
  }

  static Future<void> setWebDavShowVideosOnly(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavShowVideosOnlyKey, value);
  }

  static Future<void> clearWebDav({
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: feature,
        items: const <ResourceCollectionItem>[],
      );
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_webDavBaseUrlKey);
    await prefs.remove(_webDavUsernameKey);
    await prefs.remove(_webDavPasswordKey);
    await prefs.remove(_webDavHiddenFromNavKey);
    await prefs.remove(_webDavServersKey);
    await prefs.remove(_webDavSelectedServerIdKey);
    await prefs.setBool(_webDavEnabledKey, false);
  }

  static Future<List<WebDavConfig>> getWebDavServers({
    bool forSettings = true,
    bool forRemoteTransfer = false,
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: feature,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows
          .map(WebDavConfig.fromJson)
          .where(
            (config) =>
                config.baseUrl.trim().isNotEmpty || config.credentialsRedacted,
          )
          .toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _webDavServersKey);
    final servers = <WebDavConfig>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final config = WebDavConfig.fromJson(
                item.cast<String, dynamic>(),
              );
              if (config.baseUrl.trim().isNotEmpty) servers.add(config);
            }
          }
        }
      } catch (_) {}
    }

    if (servers.isEmpty) {
      final legacyUrl = await SecretVault.getString(prefs, _webDavBaseUrlKey);
      if (legacyUrl != null && legacyUrl.trim().isNotEmpty) {
        final config = WebDavConfig(
          id: 'legacy-${legacyUrl.hashCode}',
          name: Uri.tryParse(legacyUrl)?.host ?? 'WebDAV',
          baseUrl: legacyUrl,
          username:
              await SecretVault.getString(prefs, _webDavUsernameKey) ?? '',
          password:
              await SecretVault.getString(prefs, _webDavPasswordKey) ?? '',
        );
        servers.add(config);
        await saveWebDavServers(servers, feature: feature);
        await setSelectedWebDavServerId(config.id);
      }
    }

    return servers;
  }

  static Future<List<WebDavConfig>> saveWebDavServers(
    List<WebDavConfig> servers, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final expectedScope = ProfileRuntime.scope.value;
      if (expectedScope == null) throw StateError('No visible profile scope');
      // Capture the preference namespace before the registry mutation. If a
      // profile switch races this operation, this handle can only write the
      // initiating namespace (or fail); it can never write the new profile.
      final prefs = await ProfilePreferences.instance();
      final rows = await ProfileCollectionResourceFacade.replaceAndRead(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: feature,
        items: <ResourceCollectionItem>[
          for (final server in servers)
            ResourceCollectionItem(
              type: ConnectionResourceType.webDav,
              label: server.name,
              publicConfig: <String, dynamic>{'accountLabel': server.name},
              secretConfig: server.toJson(),
              sourceResourceId: server.connectionResourceId,
            ),
        ],
        forSettings: true,
      );
      final saved = rows.map(WebDavConfig.fromJson).toList(growable: false);
      if (ProfileRuntime.scope.value != expectedScope) {
        throw StateError('Profile changed while saving WebDAV connections');
      }
      await prefs.setBool(_webDavEnabledKey, saved.isNotEmpty);
      if (ProfileRuntime.scope.value != expectedScope) {
        throw StateError('Profile changed while saving WebDAV settings');
      }
      return saved;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(
      prefs,
      _webDavServersKey,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
    await prefs.setBool(_webDavEnabledKey, servers.isNotEmpty);
    return List<WebDavConfig>.unmodifiable(servers);
  }

  static Future<String?> getSelectedWebDavServerId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_webDavSelectedServerIdKey);
  }

  static Future<void> setSelectedWebDavServerId(String? id) async {
    final prefs = await ProfilePreferences.instance();
    if (id == null || id.isEmpty) {
      await prefs.remove(_webDavSelectedServerIdKey);
    } else {
      await prefs.setString(_webDavSelectedServerIdKey, id);
    }
  }

  static Future<WebDavConfig?> getSelectedWebDavServer({
    bool forSettings = true,
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    final servers = await getWebDavServers(
      forSettings: forSettings,
      feature: feature,
    );
    if (servers.isEmpty) return null;
    final selectedId = await getSelectedWebDavServerId();
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final server in servers) {
        if (server.id == selectedId) return server;
      }
    }
    await setSelectedWebDavServerId(servers.first.id);
    return servers.first;
  }

  static Future<WebDavConfig> upsertWebDavServer(
    WebDavConfig config, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    final selectionPrefs = await ProfilePreferences.instance();
    final servers = (await getWebDavServers(feature: feature)).toList();
    final priorResourceIds = <String>{
      for (final server in servers)
        if (server.connectionResourceId != null) server.connectionResourceId!,
    };
    final index = servers.indexWhere((server) => server.id == config.id);
    var persisted = config;
    if (index == -1) {
      servers.add(persisted);
    } else {
      final source = servers[index];
      if (source.connectionReadOnly) {
        throw const ResourceAuthorizationException(
          'Shared WebDAV connections cannot be edited',
        );
      }
      persisted = WebDavConfig(
        id: config.id,
        name: config.name,
        baseUrl: config.baseUrl,
        username: config.username,
        password: config.password,
        connectionResourceId: source.connectionResourceId,
        connectionResourceRevision: source.connectionResourceRevision,
      );
      servers[index] = persisted;
    }
    final saved = await saveWebDavServers(servers, feature: feature);
    final WebDavConfig canonical;
    final sourceResourceId = persisted.connectionResourceId;
    if (sourceResourceId != null) {
      canonical = saved.singleWhere(
        (server) => server.connectionResourceId == sourceResourceId,
      );
    } else if (ProfileCollectionResourceFacade.active) {
      canonical = saved.singleWhere(
        (server) =>
            server.connectionResourceId != null &&
            !priorResourceIds.contains(server.connectionResourceId),
      );
    } else {
      canonical = saved.singleWhere((server) => server.id == persisted.id);
    }
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while selecting a WebDAV connection');
    }
    await selectionPrefs.setString(_webDavSelectedServerIdKey, canonical.id);
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while selecting a WebDAV connection');
    }
    return canonical;
  }

  static Future<void> deleteWebDavServer(
    String id, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    final selectionPrefs = await ProfilePreferences.instance();
    final servers = (await getWebDavServers(feature: feature)).toList();
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while deleting a WebDAV connection');
    }
    servers.removeWhere((server) => server.id == id);
    final saved = await saveWebDavServers(servers, feature: feature);
    final selected = selectionPrefs.getString(_webDavSelectedServerIdKey);
    if (selected == id) {
      if (saved.isEmpty) {
        await selectionPrefs.remove(_webDavSelectedServerIdKey);
      } else {
        await selectionPrefs.setString(
          _webDavSelectedServerIdKey,
          saved.first.id,
        );
      }
    }
    if (saved.isEmpty) {
      await selectionPrefs.setBool(_webDavHiddenFromNavKey, false);
    }
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while deleting a WebDAV connection');
    }
  }

  // TVMaze Series Mapping Methods

  /// Get a unique key for a playlist item based on available identifiers
  static String _getPlaylistItemUniqueKey(Map<String, dynamic> playlistItem) {
    final provider = ((playlistItem['provider'] as String?) ?? 'realdebrid')
        .toLowerCase();

    if (provider == 'webdav') {
      return computePlaylistDedupeKey(playlistItem);
    }

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
    final title =
        (playlistItem['title'] as String?)?.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '_',
        ) ??
        'unknown';
    return 'title_$title';
  }

  /// Save a TVMaze series mapping for a playlist item
  static Future<void> saveTVMazeSeriesMapping({
    required Map<String, dynamic> playlistItem,
    required int tvmazeShowId,
    required String showName,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    Map<String, dynamic> mappings = {};
    if (mappingsJson != null) {
      try {
        mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing TVMaze series mappings: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    mappings[key] = {
      'tvmazeShowId': tvmazeShowId,
      'showName': showName,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
    debugPrint(
      '✅ Saved TVMaze mapping for $key -> Show ID: $tvmazeShowId ($showName)',
    );
  }

  /// Get TVMaze series mapping for a playlist item
  static Future<Map<String, dynamic>?> getTVMazeSeriesMapping(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return null;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);
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
    final mappingsJson = prefs.getString(_tvMazeSeriesMappingKey);

    if (mappingsJson == null) return;

    try {
      final mappings = jsonDecode(mappingsJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (mappings.containsKey(key)) {
        mappings.remove(key);
        await prefs.setString(_tvMazeSeriesMappingKey, jsonEncode(mappings));
        debugPrint('✅ Cleared TVMaze mapping for $key');
      }
    } catch (e) {
      debugPrint('Error clearing TVMaze series mapping: $e');
    }
  }

  /// Clear all TVMaze series mappings
  static Future<void> clearAllTVMazeSeriesMappings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_tvMazeSeriesMappingKey);
    debugPrint('✅ Cleared all TVMaze series mappings');
  }

  // Playlist Poster Override Methods

  /// Save a poster URL override for a playlist item
  /// This ensures the poster persists across app restarts
  static Future<void> savePlaylistPosterOverride({
    required Map<String, dynamic> playlistItem,
    required String posterUrl,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    Map<String, dynamic> overrides = {};
    if (overridesJson != null) {
      try {
        overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing playlist poster overrides: $e');
      }
    }

    final key = _getPlaylistItemUniqueKey(playlistItem);
    overrides[key] = {
      'posterUrl': posterUrl,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await prefs.setString(_playlistPosterOverridesKey, jsonEncode(overrides));
    debugPrint('✅ Saved poster override for $key -> $posterUrl');
  }

  /// Get poster URL override for a playlist item
  /// Returns null if no override exists
  static Future<String?> getPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
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
      debugPrint('Error reading playlist poster override: $e');
    }

    return null;
  }

  /// Get all poster overrides as a map of item unique key → poster URL.
  /// Reads and parses the overrides blob once for batch lookups.
  static Future<Map<String, String>> getAllPlaylistPosterOverrides() async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);
    if (overridesJson == null) return {};

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final result = <String, String>{};
      for (final entry in overrides.entries) {
        if (entry.value is Map<String, dynamic>) {
          final posterUrl =
              (entry.value as Map<String, dynamic>)['posterUrl'] as String?;
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

  /// Get the unique key for a playlist item (public accessor for batch lookups)
  static String getPlaylistItemUniqueKey(Map<String, dynamic> item) =>
      _getPlaylistItemUniqueKey(item);

  /// Clear poster URL override for a playlist item
  static Future<void> clearPlaylistPosterOverride(
    Map<String, dynamic> playlistItem,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final overridesJson = prefs.getString(_playlistPosterOverridesKey);

    if (overridesJson == null) return;

    try {
      final overrides = jsonDecode(overridesJson) as Map<String, dynamic>;
      final key = _getPlaylistItemUniqueKey(playlistItem);

      if (overrides.containsKey(key)) {
        overrides.remove(key);
        await prefs.setString(
          _playlistPosterOverridesKey,
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
    await prefs.remove(_playlistPosterOverridesKey);
    debugPrint('✅ Cleared all playlist poster overrides');
  }

  // ============================================================================
  // Torrent Search History Methods
  // ============================================================================

  /// Get torrent search history
  /// Returns list of maps containing torrent JSON + service + timestamp
  static Future<List<Map<String, dynamic>>> getTorrentSearchHistory() async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_torrentSearchHistoryKey);
  }

  /// Get whether search history tracking is enabled
  static Future<bool> getTorrentSearchHistoryEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torrentSearchHistoryEnabledKey) ?? true;
  }

  /// Set whether search history tracking is enabled
  static Future<void> setTorrentSearchHistoryEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torrentSearchHistoryEnabledKey, enabled);
  }

  /// Whether quick-play ranks candidates by the default filters (the
  /// FilterLadder). ON by default — the ladder only reorders, never drops.
  static Future<bool> getQuickPlayHonorsFilters() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayHonorsFiltersKey) ?? true;
  }

  /// Legacy global preference retained for migration and profile-less callers.
  /// The Quick Play page owns the independent Movie and Series `useFilters`
  /// values; a global write must never silently rewrite either profile.
  static Future<void> setQuickPlayHonorsFilters(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayHonorsFiltersKey, value);
  }

  // Default Torrent Filter Settings
  static Future<List<String>> getDefaultFilterQualities() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterQualities(List<String> qualities) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDefaultFilterRipSources() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterRipSourcesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterRipSources(
    List<String> ripSources,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterRipSourcesKey, jsonEncode(ripSources));
  }

  static Future<List<String>> getDefaultFilterLanguages() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterLanguagesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterLanguages(List<String> languages) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterLanguagesKey, jsonEncode(languages));
  }

  static Future<List<String>> getDefaultFilterSizes() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterSizesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterSizes(List<String> sizes) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterSizesKey, jsonEncode(sizes));
  }

  static Future<List<String>> getDefaultFilterDynamicRanges() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterDynamicRangesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterDynamicRanges(List<String> ranges) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterDynamicRangesKey, jsonEncode(ranges));
  }

  // Debrify TV Filter Settings — scoped to Debrify TV only, deliberately
  // separate from the Search tab's default filters above so tuning a channel
  // feed never changes search behaviour (and vice versa).
  static Future<List<String>> getDebrifyTvFilterQualities() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_debrifyTvFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDebrifyTvFilterQualities(
    List<String> qualities,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDebrifyTvFilterSizes() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_debrifyTvFilterSizesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDebrifyTvFilterSizes(List<String> sizes) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_debrifyTvFilterSizesKey, jsonEncode(sizes));
  }

  /// Whether the user dismissed the Debrify TV external-player notice forever.
  static Future<bool> getDebrifyTvExternalNoticeDismissed() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_debrifyTvExternalNoticeDismissedKey) ?? false;
  }

  static Future<void> setDebrifyTvExternalNoticeDismissed(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_debrifyTvExternalNoticeDismissedKey, value);
  }

  // Default Torrent Provider methods
  // Returns: 'none' (ask every time), 'torbox', 'debrid', or 'pikpak'
  static Future<String> getDefaultTorrentProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_defaultTorrentProviderKey) ?? 'none';
  }

  static Future<void> setDefaultTorrentProvider(String provider) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultTorrentProviderKey, provider);
  }

  static Future<void> clearDefaultTorrentProvider() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultTorrentProviderKey);
  }

  static Future<List<IndexerManagerConfig>> getIndexerManagerConfigs({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows.map(IndexerManagerConfig.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final rawList = await SecretVault.getStringList(
      prefs,
      _indexerManagerConfigsKey,
    );
    return rawList
        .map((raw) {
          try {
            return IndexerManagerConfig.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
          } catch (e) {
            debugPrint('Error loading indexer manager config: $e');
            return null;
          }
        })
        .whereType<IndexerManagerConfig>()
        .toList();
  }

  static Future<List<IndexerManagerConfig>> setIndexerManagerConfigs(
    List<IndexerManagerConfig> configs,
  ) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.replaceAndRead(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
        items: <ResourceCollectionItem>[
          for (final config in configs)
            ResourceCollectionItem(
              type: config.type == IndexerManagerType.prowlarr
                  ? ConnectionResourceType.prowlarr
                  : ConnectionResourceType.jackett,
              label: config.displayName,
              publicConfig: <String, dynamic>{
                'managerName': config.displayName,
              },
              secretConfig: config.toJson(),
              sourceResourceId: config.connectionResourceId,
            ),
        ],
        forSettings: true,
      );
      return rows.map(IndexerManagerConfig.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final rawList = configs
        .map((config) => jsonEncode(config.toJson()))
        .toList();
    await SecretVault.setStringList(prefs, _indexerManagerConfigsKey, rawList);
    return List<IndexerManagerConfig>.unmodifiable(configs);
  }

  static Future<String?> getSupportRemoteConfigCache() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_supportRemoteConfigCacheKey);
  }

  static Future<void> setSupportRemoteConfigCache(String json) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_supportRemoteConfigCacheKey, json);
  }

  static Future<List<String>> getDismissedDonationCampaignIds() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
  }

  static Future<void> dismissDonationCampaign(String campaignId) async {
    final prefs = await DevicePreferences.instance();
    final ids =
        prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
    if (ids.contains(campaignId)) return;
    ids.add(campaignId);
    await prefs.setStringList(_dismissedDonationCampaignIdsKey, ids);
  }

  // Quick Play VR Settings methods

  /// Get VR player mode: 'disabled', 'auto', or 'always'
  static Future<String> getQuickPlayVrMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_quickPlayVrModeKey) ?? 'disabled';
  }

  static Future<void> setQuickPlayVrMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_quickPlayVrModeKey, mode);
  }

  /// Get default VR screen type (dome, sphere, flat, fisheye, mkx200, rf52)
  static Future<String> getQuickPlayVrDefaultScreenType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_quickPlayVrDefaultScreenTypeKey) ?? 'dome';
  }

  static Future<void> setQuickPlayVrDefaultScreenType(String screenType) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_quickPlayVrDefaultScreenTypeKey, screenType);
  }

  /// Get default VR stereo mode (sbs, tb, off)
  static Future<String> getQuickPlayVrDefaultStereoMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_quickPlayVrDefaultStereoModeKey) ?? 'sbs';
  }

  static Future<void> setQuickPlayVrDefaultStereoMode(String stereoMode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_quickPlayVrDefaultStereoModeKey, stereoMode);
  }

  /// Get whether to auto-detect VR format from filename
  static Future<bool> getQuickPlayVrAutoDetectFormat() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayVrAutoDetectFormatKey) ?? true;
  }

  static Future<void> setQuickPlayVrAutoDetectFormat(bool autoDetect) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayVrAutoDetectFormatKey, autoDetect);
  }

  /// Get whether to show VR format selection dialog before launching DeoVR
  static Future<bool> getQuickPlayVrShowDialog() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayVrShowDialogKey) ?? true;
  }

  static Future<void> setQuickPlayVrShowDialog(bool showDialog) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayVrShowDialogKey, showDialog);
  }

  /// Clear all Quick Play VR settings
  static Future<void> clearQuickPlayVrSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_quickPlayVrModeKey);
    await prefs.remove(_quickPlayVrDefaultScreenTypeKey);
    await prefs.remove(_quickPlayVrDefaultStereoModeKey);
    await prefs.remove(_quickPlayVrAutoDetectFormatKey);
    await prefs.remove(_quickPlayVrShowDialogKey);
  }

  // Quick Play Cache Fallback Settings methods

  /// What the Play button does — NOT what it looks like. The button keeps its
  /// label, icon and position in every mode; only the behavior behind the press
  /// changes:
  ///
  ///  * `quick`  — the shipped contract: reuse a pinned source, else search and
  ///               auto-play the best match.
  ///  * `smart`  — reuse a pinned source; when none is usable, hand the user the
  ///               source list instead of auto-picking.
  ///  * `always` — skip pinned sources entirely and always hand over the list.
  ///
  /// Absent key means `quick`, so existing installs are untouched. Only the
  /// user's own Play press honors this ([TorrentPlaybackService.playFromSelection]
  /// applies it solely when a picker opener is supplied) — binge auto-advance and
  /// post-failure recovery keep auto-selecting, since re-prompting mid-chain is
  /// exactly what those paths exist to avoid.
  static Future<String> getPlayButtonMode() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playButtonModeKey);
    return (raw == 'smart' || raw == 'always') ? raw! : 'quick';
  }

  static Future<void> setPlayButtonMode(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playButtonModeKey, value);
  }

  /// Loads the per-content Quick Play profile. When no v2 profile exists,
  /// legacy filter/retry/series-pack preferences are folded into one without
  /// changing what the next play will do. Non-default legacy values are
  /// labelled Custom; an untouched install is Debrify default.
  static Future<QuickPlayRules> getQuickPlayRules({
    required bool isMovie,
  }) async {
    final prefs = await ProfilePreferences.instance();
    return _quickPlayRulesFromPrefs(prefs, isMovie: isMovie);
  }

  static QuickPlayRules _quickPlayRulesFromPrefs(
    SharedPreferences prefs, {
    required bool isMovie,
  }) {
    final key = isMovie ? _quickPlayMovieRulesKey : _quickPlaySeriesRulesKey;
    final stored = prefs.getString(key);
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is Map<String, dynamic>) {
          return QuickPlayRules.fromJson(decoded, isMovie: isMovie);
        }
        if (decoded is Map) {
          return QuickPlayRules.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
            isMovie: isMovie,
          );
        }
      } catch (e) {
        debugPrint('Invalid Quick Play profile, using legacy values: $e');
      }
    }

    final defaults = QuickPlayRules.debrifyDefault(isMovie: isMovie);
    final migrated = defaults.copyWith(
      preset: QuickPlayPreset.debrifyDefault,
      useFilters: prefs.getBool(_quickPlayHonorsFiltersKey) ?? true,
      tryNextOnFailure: prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? true,
      maxAttempts: prefs.getInt(_quickPlayMaxRetriesKey) ?? 5,
      preferSeriesPacks:
          !isMovie && (prefs.getBool(_autoBindSeriesPacksKey) ?? true),
    );
    return migrated == defaults
        ? migrated
        : migrated.copyWith(preset: QuickPlayPreset.custom);
  }

  static Future<void> setQuickPlayRules(
    QuickPlayRules rules, {
    required bool isMovie,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final siblingIsMovie = !isMovie;
    final siblingKey = siblingIsMovie
        ? _quickPlayMovieRulesKey
        : _quickPlaySeriesRulesKey;
    // Snapshot an as-yet-unpersisted sibling BEFORE updating the legacy global
    // mirrors below. Otherwise saving Movies first could make a later Series
    // migration inherit the movie retry count (and vice versa).
    final sibling = prefs.containsKey(siblingKey)
        ? null
        : _quickPlayRulesFromPrefs(prefs, isMovie: siblingIsMovie);
    await prefs.setString(
      isMovie ? _quickPlayMovieRulesKey : _quickPlaySeriesRulesKey,
      jsonEncode(rules.toJson()),
    );
    if (sibling != null) {
      await prefs.setString(siblingKey, jsonEncode(sibling.toJson()));
    }

    // Keep old readers and downgrade builds safe. Media-specific values can't
    // be represented perfectly by the legacy global keys, so the active v2
    // playback path never reads these; they are compatibility mirrors only.
    //
    // That invariant was violated once: series auto-pinning read
    // _autoBindSeriesPacksKey, so writing this mirror turned pinning off
    // whenever the user turned off "Prefer season packs". Auto-pin now owns
    // _seriesAutoPinOnPlayKey. Before adding a reader for any key below, check
    // it is genuinely write-only on this path.
    await prefs.setBool(
      _quickPlayTryMultipleTorrentsKey,
      rules.tryNextOnFailure,
    );
    await prefs.setInt(_quickPlayMaxRetriesKey, rules.maxAttempts);
    if (!isMovie) {
      await prefs.setBool(_autoBindSeriesPacksKey, rules.preferSeriesPacks);
    }
  }

  static Future<void> restoreQuickPlayDefaults() async {
    await setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true),
      isMovie: true,
    );
    await setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: false),
      isMovie: false,
    );
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayHonorsFiltersKey, true);
    // The page's reset button reads as "reset this page", and this function
    // already resets a non-per-tab key above, so the Play button mode goes back
    // to the shipped Quick Play too. Leaving it would restore defaults while
    // Play kept behaving differently.
    await prefs.remove(_playButtonModeKey);
  }

  /// Get whether to try multiple torrents if first is not cached
  /// Default: true (try next torrent on failure)
  static Future<bool> getQuickPlayTryMultipleTorrents() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? true;
  }

  static Future<void> setQuickPlayTryMultipleTorrents(bool tryMultiple) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayTryMultipleTorrentsKey, tryMultiple);
  }

  /// Whether a series play pins the source that played, so later episodes go
  /// straight through the bound path. Defaults ON.
  ///
  /// Independent of "Prefer season packs" — the two shared a key until this
  /// split, which meant turning packs off silently killed pinning. See
  /// [_seriesAutoPinOnPlayKey].
  static Future<bool> getSeriesAutoPinOnPlay() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_seriesAutoPinOnPlayKey) ?? true;
  }

  static Future<void> setSeriesAutoPinOnPlay(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_seriesAutoPinOnPlayKey, enabled);
  }

  /// Get max number of torrents to try before giving up
  /// Default: 5, Range: 2-10
  static Future<int> getQuickPlayMaxRetries() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_quickPlayMaxRetriesKey) ?? 5;
  }

  static Future<void> setQuickPlayMaxRetries(int maxRetries) async {
    final prefs = await ProfilePreferences.instance();
    // Clamp between 2 and 10
    await prefs.setInt(_quickPlayMaxRetriesKey, maxRetries.clamp(2, 10));
  }

  static const String _quickPlaySearchTimeoutKey = 'quick_play_search_timeout';

  static Future<int> getQuickPlaySearchTimeout() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_quickPlaySearchTimeoutKey) ?? 5;
  }

  static Future<void> setQuickPlaySearchTimeout(int seconds) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_quickPlaySearchTimeoutKey, seconds);
  }

  static const String _stremioSourcesTimeoutKey = 'stremio_sources_timeout';

  static Future<int> getStremioSourcesTimeout() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioSourcesTimeoutKey) ?? 15;
  }

  static Future<void> setStremioSourcesTimeout(int seconds) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioSourcesTimeoutKey, seconds);
  }

  /// Clear all Quick Play Cache Fallback settings
  static Future<void> clearQuickPlayCacheFallbackSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_quickPlayTryMultipleTorrentsKey);
    await prefs.remove(_quickPlayMaxRetriesKey);
    await prefs.remove(_quickPlayMovieRulesKey);
    await prefs.remove(_quickPlaySeriesRulesKey);
  }

  // External Player Settings methods

  /// Get default player mode
  /// Returns 'debrify' (built-in player) by default
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<String> getDefaultPlayerMode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_defaultPlayerModeKey) ?? 'debrify';
  }

  /// Set default player mode
  /// Valid values: 'debrify', 'external', 'deovr'
  static Future<void> setDefaultPlayerMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultPlayerModeKey, mode);
  }

  /// Get preferred external player key
  /// Returns 'system_default' if not set
  static Future<String> getPreferredExternalPlayer() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerPreferredKey) ?? 'system_default';
  }

  /// Set preferred external player key
  static Future<void> setPreferredExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_externalPlayerPreferredKey, playerKey);
  }

  /// Get custom external player path (for custom player option)
  static Future<String?> getCustomExternalPlayerPath() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomPathKey);
  }

  /// Set custom external player path
  static Future<void> setCustomExternalPlayerPath(String? path) async {
    final prefs = await ProfilePreferences.instance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_externalPlayerCustomPathKey);
    } else {
      await prefs.setString(_externalPlayerCustomPathKey, path);
    }
  }

  /// Get custom external player display name
  static Future<String?> getCustomExternalPlayerName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomNameKey);
  }

  /// Set custom external player display name
  static Future<void> setCustomExternalPlayerName(String? name) async {
    final prefs = await ProfilePreferences.instance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_externalPlayerCustomNameKey);
    } else {
      await prefs.setString(_externalPlayerCustomNameKey, name);
    }
  }

  /// Get custom external player command template
  /// Should contain {url} placeholder, optionally {title}
  static Future<String?> getCustomExternalPlayerCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_externalPlayerCustomCommandKey);
  }

  /// Set custom external player command template
  static Future<void> setCustomExternalPlayerCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iosExternalPlayerPreferredKey) ?? 'vlc';
  }

  /// Set preferred iOS external player key
  static Future<void> setPreferredIOSExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_iosExternalPlayerPreferredKey, playerKey);
  }

  /// Get iOS custom URL scheme template
  /// Should contain {url} placeholder, e.g., "myplayer://play?url={url}"
  static Future<String?> getIOSCustomSchemeTemplate() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iosCustomSchemeTemplateKey);
  }

  /// Set iOS custom URL scheme template
  static Future<void> setIOSCustomSchemeTemplate(String? template) async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_linuxExternalPlayerPreferredKey) ??
        'system_default';
  }

  /// Set preferred Linux external player key
  static Future<void> setPreferredLinuxExternalPlayer(String playerKey) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_linuxExternalPlayerPreferredKey, playerKey);
  }

  /// Get Linux custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getLinuxCustomCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_linuxCustomCommandKey);
  }

  /// Set Linux custom command template
  static Future<void> setLinuxCustomCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
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
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_windowsExternalPlayerPreferredKey) ??
        'system_default';
  }

  /// Set preferred Windows external player key
  static Future<void> setPreferredWindowsExternalPlayer(
    String playerKey,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_windowsExternalPlayerPreferredKey, playerKey);
  }

  /// Get Windows custom command template
  /// Should contain {url} placeholder, e.g., "vlc --fullscreen {url}"
  static Future<String?> getWindowsCustomCommand() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_windowsCustomCommandKey);
  }

  /// Set Windows custom command template
  static Future<void> setWindowsCustomCommand(String? command) async {
    final prefs = await ProfilePreferences.instance();
    if (command == null || command.isEmpty) {
      await prefs.remove(_windowsCustomCommandKey);
    } else {
      await prefs.setString(_windowsCustomCommandKey, command);
    }
  }

  /// Clear all external player settings
  static Future<void> clearExternalPlayerSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultPlayerModeKey);
    await prefs.remove(_externalPlayerPreferredKey);
    await prefs.remove(_externalPlayerCustomPathKey);
    await prefs.remove(_externalPlayerCustomNameKey);
    await prefs.remove(_externalPlayerCustomCommandKey);
  }

  // Debrify Player Default Settings

  /// Get default aspect ratio index for Flutter/mobile player
  /// 0=Contain, 1=Cover, 2=FitWidth, 3=FitHeight, 4=16:9, 5=4:3, 6=21:9, 7=1:1, 8=3:2, 9=5:4, 10=CinemaZoom
  /// Default: 2 (Fit Width)
  static Future<int> getPlayerDefaultAspectIndex() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerDefaultAspectIndexKey) ?? 2;
  }

  /// Set default aspect ratio index for Flutter/mobile player
  static Future<void> setPlayerDefaultAspectIndex(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerDefaultAspectIndexKey, index);
  }

  /// Get default aspect ratio index for Android TV player
  /// 0=Fit, 1=Fill, 2=Zoom, 3=CinemaZoom
  /// Default: 0 (Fit)
  static Future<int> getPlayerDefaultAspectIndexTv() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerDefaultAspectIndexTvKey) ?? 0;
  }

  /// Set default aspect ratio index for Android TV player
  static Future<void> setPlayerDefaultAspectIndexTv(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerDefaultAspectIndexTvKey, index);
  }

  /// Get night mode index (Android TV only)
  /// 0=Off, 1=Low, 2=Medium, 3=High, 4=Higher, 5=Extreme, 6=Max, 7=Sleeping Baby
  /// Default: 0 (Off)
  static Future<int> getPlayerNightModeIndex() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerNightModeIndexKey) ?? 0;
  }

  /// Set night mode index (Android TV only)
  static Future<void> setPlayerNightModeIndex(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerNightModeIndexKey, index);
  }

  /// Whether to route playback through Android's effects-capable audio output
  /// and announce the session to system equalizer apps (Wavelet, OEM effects).
  /// Android only. Default: false — off changes nothing about how audio is
  /// output today, since enabling it switches the phone player's audio backend.
  static Future<bool> getPlayerSystemAudioEffects() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_playerSystemAudioEffectsKey) ?? false;
  }

  /// Set whether system audio effect apps may process our playback.
  static Future<void> setPlayerSystemAudioEffects(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_playerSystemAudioEffectsKey, enabled);
  }

  /// Android Dart player only: bitstream AC3/EAC3/DTS-core to the audio
  /// device instead of decoding to PCM (AUDIO_FIDELITY_PLAN.md). Default
  /// false — passthrough is fail-loud on routes that misreport support,
  /// so only the user can turn it on.
  static Future<bool> getAudioPassthroughEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_audioPassthroughKey) ?? false;
  }

  static Future<void> setAudioPassthroughEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_audioPassthroughKey, enabled);
  }

  /// Apple (tvOS/iOS) Dart player: request the track's real channel layout
  /// (`audio-channels=auto`) so an HDMI/eARC AVR route gets full
  /// multichannel LPCM. Default false until route-safety is field-proven
  /// (AUDIO_FIDELITY_PLAN.md rev 2).
  static Future<bool> getAppleMultichannelAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_appleMultichannelAudioKey) ?? false;
  }

  static Future<void> setAppleMultichannelAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_appleMultichannelAudioKey, enabled);
  }

  /// Apple TV diagnostics. The player picks `ao=avfoundation,audiounit` and
  /// caps `audio-channels` to stereo on a route that reports two channels;
  /// these two override that automatic choice from either direction, so a
  /// reporter can narrow an audio problem without a custom build.
  ///
  /// Force stereo: cap regardless of what the route claims. Use when a
  /// multichannel route folds badly.
  static Future<bool> getTvosForceStereoAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosForceStereoAudioKey) ?? false;
  }

  static Future<void> setTvosForceStereoAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosForceStereoAudioKey, enabled);
  }

  /// Legacy output: go back to `ao=audiounit`, the pre-2026-08 behaviour.
  /// It is silent on Dolby Atmos routes — which is why avfoundation is now
  /// the default — but it is the escape hatch if the new output misbehaves.
  static Future<bool> getTvosLegacyAudioOutput() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosLegacyAudioOutputKey) ?? false;
  }

  static Future<void> setTvosLegacyAudioOutput(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosLegacyAudioOutputKey, enabled);
  }

  /// Apple TV only: force the media-kit player to software video decoding.
  /// The escape hatch behind the automatic 10-bit remedy ladder (see
  /// PLAYER_TVOS_10BIT_PLAN.md) — for files whose formats read clean but
  /// render wrong. Default false: hardware decoding, today's behavior.
  static Future<bool> getTvosForceSoftwareDecode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosForceSoftwareDecodeKey) ?? false;
  }

  static Future<void> setTvosForceSoftwareDecode(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosForceSoftwareDecodeKey, enabled);
  }

  /// Renderer used by the Flutter media-kit player on Android phones/tablets.
  /// Android TV ignores this and keeps its native Media3 SurfaceView backend.
  static Future<AndroidVideoRendererMode> getAndroidVideoRendererMode() async {
    final prefs = await ProfilePreferences.instance();
    final migrated =
        prefs.getBool(_androidVideoRendererGpuMigrationKey) ?? false;
    final stored = prefs.getString(_androidVideoRendererModeKey);
    if (!migrated) {
      // Direct Surface used to be the default, but mediacodec_embed cannot
      // composite bitmap subtitles. Migrate existing installs once; users may
      // still explicitly choose the performance renderer afterwards.
      if (stored == null ||
          stored == AndroidVideoRendererMode.directSurface.storageKey) {
        await prefs.setString(
          _androidVideoRendererModeKey,
          AndroidVideoRendererMode.directMediaCodec.storageKey,
        );
      }
      await prefs.setBool(_androidVideoRendererGpuMigrationKey, true);
    }
    return AndroidVideoRendererMode.fromStorage(
      prefs.getString(_androidVideoRendererModeKey),
    );
  }

  static Future<void> setAndroidVideoRendererMode(
    AndroidVideoRendererMode mode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_androidVideoRendererModeKey, mode.storageKey);
    await prefs.setBool(_androidVideoRendererGpuMigrationKey, true);
  }

  /// Whether the Debrify Player should request community timestamps and show
  /// manual skip buttons. Manual buttons are enabled by default; this setting
  /// never authorizes automatic seeking.
  static Future<bool> getSkipSegmentsEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_skipSegmentsEnabledKey) ?? true;
  }

  static Future<void> setSkipSegmentsEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_skipSegmentsEnabledKey, enabled);
  }

  /// Timestamp source used by the Debrify Player. Unknown stored values fall
  /// back safely so removing a provider cannot strand the feature.
  static Future<String> getSkipSegmentProvider() async {
    final prefs = await ProfilePreferences.instance();
    final provider = prefs.getString(_skipSegmentProviderKey);
    return _supportedSkipSegmentProviders.contains(provider)
        ? provider!
        : skipSegmentProviderAuto;
  }

  static Future<void> setSkipSegmentProvider(String provider) async {
    final prefs = await ProfilePreferences.instance();
    final supported = _supportedSkipSegmentProviders.contains(provider)
        ? provider
        : skipSegmentProviderAuto;
    await prefs.setString(_skipSegmentProviderKey, supported);
  }

  /// Whether the phone player OPENS upright instead of turning the handset
  /// landscape for you. Off by default — a video wants the long edge, and that
  /// is what the player has always done. On, it opens portrait and the
  /// player's own Portrait/Landscape button is how the user turns it.
  /// Phone-only: a TV has no portrait and a desktop window ignores this
  /// entirely.
  ///
  /// [playerStartPortraitCached] mirrors it for SYNCHRONOUS reads. The player
  /// commits its orientation while building, so an async read there would set
  /// landscape and correct it a frame later — performing the exact flip this
  /// setting exists to prevent. Warmed in main() before runApp (the IPTV
  /// startup channel can open a player on the first frame) and kept in sync by
  /// the setter.
  static bool playerStartPortraitCached = false;

  static Future<bool> getPlayerStartPortrait() async {
    final prefs = await ProfilePreferences.instance();
    playerStartPortraitCached = prefs.getBool(_playerStartPortraitKey) ?? false;
    return playerStartPortraitCached;
  }

  static Future<void> setPlayerStartPortrait(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_playerStartPortraitKey, enabled);
    playerStartPortraitCached = enabled;
  }

  /// Whether interface sound and haptics are allowed at all.
  ///
  /// A VETO, not a switch: the theme decides whether there is anything to play
  /// and these decide whether the user wants to hear or feel it. Both default
  /// ON, because a theme that asks for silence — which is every look except
  /// Console and Warm Room — already produces none, so the default cannot
  /// surprise anybody who has not chosen a look that ticks.
  ///
  /// Synchronous mirrors because `UiFeedback` is consulted from a focus
  /// listener and a key handler, neither of which can await. Warmed in main()
  /// before runApp.
  static bool uiSoundsCached = true;
  static bool uiHapticsCached = true;

  static Future<bool> getUiSounds() async {
    final prefs = await ProfilePreferences.instance();
    uiSoundsCached = prefs.getBool(_uiSoundsKey) ?? true;
    return uiSoundsCached;
  }

  static Future<void> setUiSounds(bool enabled) async {
    // The mirror moves FIRST. `UiFeedback` reads it from a focus listener that
    // cannot await, so publishing after the platform write leaves a window in
    // which a user who has just switched sound off still hears the next tick.
    uiSoundsCached = enabled;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_uiSoundsKey, enabled);
  }

  static Future<bool> getUiHaptics() async {
    final prefs = await ProfilePreferences.instance();
    uiHapticsCached = prefs.getBool(_uiHapticsKey) ?? true;
    return uiHapticsCached;
  }

  static Future<void> setUiHaptics(bool enabled) async {
    uiHapticsCached = enabled;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_uiHapticsKey, enabled);
  }

  /// Whether native players silently align addon subtitles to the audio as
  /// playback runs. Android TV reads the same profile preference natively;
  /// MediaKit reads it in Dart (Android, macOS, Linux, tvOS — platforms whose
  /// bundled libmpv carries the analysis filters) and attaches its passive
  /// filter only while an addon subtitle is active. OFF by default on both
  /// engines — experimental opt-in. The default must stay in lock-step with
  /// the native read in AndroidTvTorrentPlayerActivity.isAutoSyncPrefEnabled.
  static Future<bool> getSubtitleAutoSyncEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_subtitleAutoSyncKey) ?? false;
  }

  static Future<void> setSubtitleAutoSyncEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_subtitleAutoSyncKey, enabled);
  }

  /// Get default subtitle language code
  /// Returns language code (e.g., 'en', 'es') or 'off' for disabled, null for no preference
  static Future<String?> getDefaultSubtitleLanguage() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_playerDefaultSubtitleLanguageKey);
  }

  /// Set default subtitle language code
  /// Pass language code (e.g., 'en', 'es'), 'off' for disabled, or null to clear preference
  static Future<void> setDefaultSubtitleLanguage(String? languageCode) async {
    final prefs = await ProfilePreferences.instance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultSubtitleLanguageKey);
    } else {
      await prefs.setString(_playerDefaultSubtitleLanguageKey, languageCode);
    }
  }

  /// Get default audio language code
  /// Returns language code (e.g., 'en', 'es') or null for no preference
  static Future<String?> getDefaultAudioLanguage() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_playerDefaultAudioLanguageKey);
  }

  /// Set default audio language code
  /// Pass language code (e.g., 'en', 'es') or null to clear preference
  static Future<void> setDefaultAudioLanguage(String? languageCode) async {
    final prefs = await ProfilePreferences.instance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultAudioLanguageKey);
    } else {
      await prefs.setString(_playerDefaultAudioLanguageKey, languageCode);
    }
  }

  static const String _iptvSeriesAudioLangKey = 'iptv_series_audio_lang';

  /// The audio LANGUAGE the user last chose for an IPTV series (keyed by the
  /// series' name). Language, not the mpv track ordinal — episodes are
  /// separate files whose track ordering differs, so an ordinal wouldn't
  /// carry. Null when the series has no remembered choice.
  static Future<String?> getIptvSeriesAudioLanguage(String seriesKey) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[seriesKey] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Remember the audio language for an IPTV series so later episodes (and
  /// future sessions) default to it.
  static Future<void> setIptvSeriesAudioLanguage(
    String seriesKey,
    String languageCode,
  ) async {
    if (seriesKey.isEmpty || languageCode.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    Map<String, dynamic> map = {};
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    map[seriesKey] = languageCode;
    await prefs.setString(_iptvSeriesAudioLangKey, jsonEncode(map));
  }

  // IPTV Playlist Settings

  /// Credential-bearing fields of a stored playlist. Encrypted field-level
  /// rather than sealing the whole element: `content` can be a multi-megabyte
  /// raw M3U body and this getter sits on hot paths, so blob-level AES would
  /// cost real time on TV hardware for data that arrived as a plaintext file
  /// the user chose. Residual: URLs embedded inside a file-imported `content`
  /// body stay plaintext — accepted.
  static const List<String> _iptvPlaylistSecretFields = [
    'url', 'serverUrl', 'username', 'password', 'epgUrl', //
  ];

  /// Restores the `url` key the legacy→profile migration erased.
  ///
  /// An Xtream provider legitimately stores `url: ''` — its endpoint is
  /// [IptvPlaylist.serverUrl]. The migration's shared resource writer stripped
  /// every empty value before sealing, so an Xtream resource migrated by an
  /// affected build carries no `url` key at all, and `IptvPlaylist.fromJson`
  /// threw on the required cast. That took out the ENTIRE playlist list — and
  /// with it the IPTV page — rather than the one provider.
  ///
  /// Fixing the migration cannot help these devices: migration is a one-way
  /// door that never re-runs. Repairing on read is what brings them back, and
  /// it keeps working for anyone who migrated on an affected build and updates
  /// later.
  ///
  /// TWO provider kinds legitimately carry an empty `url`, and both are
  /// repaired: an Xtream login (endpoint in `serverUrl`) and a playlist
  /// imported from a file (body in `content` — see the IPTV settings page,
  /// which writes `url: ''` for exactly that reason). Neither field is
  /// stripped by the migration, so either one identifies a record whose empty
  /// `url` was real rather than missing.
  ///
  /// Still deliberately narrow: a row with none of the three is genuinely
  /// malformed and keeps throwing, because papering over that would turn real
  /// corruption into a silent blank provider.
  static Map<String, dynamic> _repairMigratedIptvRow(Map<String, dynamic> row) {
    if (row['url'] != null) return row;
    if (!_hasText(row['serverUrl']) && !_hasText(row['content'])) return row;
    return <String, dynamic>{...row, 'url': ''};
  }

  static bool _hasText(Object? value) =>
      value is String && value.trim().isNotEmpty;

  /// Get all saved IPTV playlists
  static Future<List<IptvPlaylist>> getIptvPlaylists({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows
          .map(_repairMigratedIptvRow)
          .map(IptvPlaylist.fromJson)
          .toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = prefs.getStringList(_iptvPlaylistsKey) ?? [];
    var legacySeen = false;
    var anyDropped = false;
    final playlists = <IptvPlaylist>[];
    for (final json in jsonList) {
      try {
        final opened = await SecretVault.openFields(
          Map<String, dynamic>.from(jsonDecode(json) as Map),
          _iptvPlaylistSecretFields,
        );
        if (opened.wasLegacy) legacySeen = true;
        // A playlist whose url failed to decrypt throws in fromJson and is
        // dropped here — same signed-out semantics as the standalone keys.
        playlists.add(IptvPlaylist.fromJson(opened.map));
      } catch (e) {
        // Skip malformed entries FOR THIS READ only.
        anyDropped = true;
      }
    }
    // Migrate lazily, but never off a lossy read: rewriting while an entry
    // failed (possibly a transient vault-key hiccup) would turn a one-launch
    // read error into permanent deletion. A later clean read migrates.
    if (legacySeen && !anyDropped) {
      await setIptvPlaylists(playlists);
    }
    return playlists;
  }

  /// Save IPTV playlists.
  ///
  /// Virtual playlists (Favorites, custom lists, Continue watching, Stremio
  /// addon shelves) are dropped here rather than trusted not to arrive: the
  /// page's own list holds real and virtual entries side by side, and a
  /// virtual one that reached the preference would be restored AND injected
  /// on the next load — two entries with the same id, where id-only equality
  /// makes lookups resolve the stale copy.
  static Future<void> setIptvPlaylists(
    List<IptvPlaylist> playlists, {
    bool revokeBorrowers = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final stored = playlists.where((playlist) => !playlist.isVirtual);
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        items: <ResourceCollectionItem>[
          for (final playlist in stored)
            ResourceCollectionItem(
              type: playlist.isXtreamCodes
                  ? ConnectionResourceType.iptvXtream
                  : ConnectionResourceType.iptvM3u,
              label: playlist.name,
              publicConfig: <String, dynamic>{
                'playlistName': playlist.name,
                'providerKind': playlist.isXtreamCodes ? 'xtream' : 'm3u',
              },
              secretConfig: playlist.toJson(),
              sourceResourceId: playlist.connectionResourceId,
            ),
        ],
        revokeBorrowers: revokeBorrowers,
      );
      return;
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = <String>[];
    for (final p in playlists.where((p) => !p.isVirtual)) {
      jsonList.add(
        jsonEncode(
          await SecretVault.sealFields(p.toJson(), _iptvPlaylistSecretFields),
        ),
      );
    }
    await prefs.setStringList(_iptvPlaylistsKey, jsonList);
  }

  /// Persists an IPTV collection and returns the authoritative records.
  ///
  /// In profile mode a collection write can mint or rotate connection
  /// resources, so the caller's input objects are deliberately not execution
  /// capabilities. UI code that keeps using those objects would have no
  /// resource ID for a new playlist, or a stale revision for an existing one.
  static Future<List<IptvPlaylist>> setIptvPlaylistsAndReload(
    List<IptvPlaylist> playlists, {
    required bool forSettings,
    bool revokeBorrowers = false,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    await setIptvPlaylists(playlists, revokeBorrowers: revokeBorrowers);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active ||
            ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while saving IPTV playlists');
    }
    final saved = await getIptvPlaylists(forSettings: forSettings);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active ||
            ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while loading IPTV playlists');
    }
    return saved;
  }

  /// Get default IPTV playlist ID
  static Future<String?> getIptvDefaultPlaylist() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iptvDefaultPlaylistKey);
  }

  /// Set default IPTV playlist ID
  static Future<void> setIptvDefaultPlaylist(String? playlistId) async {
    final prefs = await ProfilePreferences.instance();
    if (playlistId == null || playlistId.isEmpty) {
      await prefs.remove(_iptvDefaultPlaylistKey);
    } else {
      await prefs.setString(_iptvDefaultPlaylistKey, playlistId);
    }
  }

  /// Check if IPTV defaults have been initialized (to avoid re-adding after user deletes)
  static Future<bool> getIptvDefaultsInitialized() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvDefaultsInitializedKey) ?? false;
  }

  /// Mark IPTV defaults as initialized
  static Future<void> setIptvDefaultsInitialized(bool initialized) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvDefaultsInitializedKey, initialized);
  }

  // ==========================================================================
  // Last live IPTV channel (startup-channel memory)
  //
  // Single slot, overwritten. Written ONLY once a live channel has actually
  // reached a playing state — never at tune time. Both players call in from
  // their playing-state transition; recording an *attempted* tune would let one
  // dead stream replace the last working channel, and the startup feature
  // re-tunes this unattended on every cold boot, so a dead entry would mean
  // booting into failure until the user cancels out of it.
  //
  // Deliberately NOT [recordIptvWatch]: that store is the Continue Watching
  // shelf, which is on-demand only ("62% through Sky Sports" is meaningless).
  // ==========================================================================

  /// Remember [url]/[name] as the last live channel that actually played.
  ///
  /// [playlistId] is the channel's ORIGIN provider, not whichever shelf it was
  /// launched from — a channel played out of Favourites or a custom list must
  /// come back under its real provider's credentials.
  ///
  /// The provider fingerprint (`serverUrl` + `username`) is resolved here from
  /// [playlistId] rather than asked of callers: the players know only a source
  /// id, and the fingerprint has to be captured while the playlist still
  /// exists — it is what allows a re-added Xtream account (which mints a fresh
  /// playlist id) to be recognised later. Resolving it costs one prefs read,
  /// paid once per settled channel, never per zap.
  static Future<void> setIptvLastLiveChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) async {
    if (url.isEmpty) return;
    String? serverUrl;
    String? username;
    if (playlistId != null && playlistId.isNotEmpty) {
      try {
        for (final playlist in await getIptvPlaylists()) {
          if (playlist.id == playlistId) {
            if (playlist.isXtreamCodes) {
              serverUrl = playlist.serverUrl;
              username = playlist.username;
            }
            break;
          }
        }
      } catch (_) {
        // Fingerprint is a recovery aid, never a precondition — a failed
        // lookup still stores a usable entry keyed by playlist id.
      }
    }
    final prefs = await ProfilePreferences.instance();
    // Sealed whole: the stored Xtream `url` embeds the account password.
    await SecretVault.setString(
      prefs,
      _iptvLastLiveChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty)
          'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// The last live channel that reached a playing state, or null.
  static Future<Map<String, dynamic>?> getIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _iptvLastLiveChannelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed (hand-edited prefs, or a format change): treat as absent
      // rather than throwing on a startup path.
    }
    return null;
  }

  static Future<void> clearIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_iptvLastLiveChannelKey);
  }

  // ==========================================================================
  // Startup channel (boot straight into a live IPTV channel)
  //
  // Reuses the surviving `startup_auto_launch_enabled` / `startup_mode` keys
  // from the removed general Launch-on-Startup feature; `startup_mode` is set
  // to 'iptv' so a future second mode can coexist without another master flag.
  // ==========================================================================

  static const String _startupIptvModeKey = 'startup_iptv_mode';
  static const String _startupIptvChannelKey = 'startup_iptv_channel';

  /// 'last' (whatever played most recently) or 'pinned' (a chosen channel).
  static const String startupIptvModeLast = 'last';
  static const String startupIptvModePinned = 'pinned';

  /// Payload marker meaning "nothing is remembered yet — start on whatever the
  /// IPTV page lands on". Never persisted; only ever set by [warmStartupIptv].
  static const String startupIptvFirstAvailable = 'firstAvailable';

  static Future<bool> getStartupIptvEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getBool(_startupAutoLaunchEnabledKey) ?? false) &&
        prefs.getString(_startupModeKey) == 'iptv';
  }

  static Future<void> setStartupIptvEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_startupAutoLaunchEnabledKey, enabled);
    if (enabled) {
      await prefs.setString(_startupModeKey, 'iptv');
    } else {
      // Leave the mode behind rather than clearing it: re-enabling should come
      // back to IPTV, not to a blank slate.
      await prefs.remove(_startupModeKey);
    }
  }

  static Future<String> getStartupIptvMode() async {
    final prefs = await ProfilePreferences.instance();
    final mode = prefs.getString(_startupIptvModeKey);
    return mode == startupIptvModePinned
        ? startupIptvModePinned
        : startupIptvModeLast;
  }

  static Future<void> setStartupIptvMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _startupIptvModeKey,
      mode == startupIptvModePinned
          ? startupIptvModePinned
          : startupIptvModeLast,
    );
  }

  /// The pinned startup channel. Same blob shape as [setIptvLastLiveChannel],
  /// so both modes resolve through one code path at launch.
  static Future<Map<String, dynamic>?> getStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _startupIptvChannelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// [playlistId] must be the channel's ORIGIN provider — the picker aggregates
  /// Favourites and custom lists, where the same URL can exist under two
  /// different providers, so a URL alone cannot identify which one was chosen.
  static Future<void> setStartupIptvChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) async {
    if (url.isEmpty) return;
    String? serverUrl;
    String? username;
    if (playlistId != null && playlistId.isNotEmpty) {
      try {
        for (final playlist in await getIptvPlaylists()) {
          if (playlist.id == playlistId) {
            if (playlist.isXtreamCodes) {
              serverUrl = playlist.serverUrl;
              username = playlist.username;
            }
            break;
          }
        }
      } catch (_) {}
    }
    final prefs = await ProfilePreferences.instance();
    // Sealed whole for the same reason as the last-live-channel blob: the
    // Xtream `url` embeds the account password.
    await SecretVault.setString(
      prefs,
      _startupIptvChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty)
          'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
      }),
    );
  }

  static Future<void> clearStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_startupIptvChannelKey);
  }

  // --- Synchronous startup handoff -----------------------------------------
  //
  // MainPage's `_selectedIndex` is a FIELD INITIALIZER: it runs at construction,
  // long before any async prefs read could answer. Warming the decision in
  // main() before runApp is the same trick `PlatformUtil.isAndroidTvCached`
  // uses, and it is what keeps the Home board from mounting and starting its
  // cold-start IO before we swap to IPTV.

  static Map<String, dynamic>? _startupIptvChannelCached;

  /// The channel to boot into, or null. Only meaningful after [warmStartupIptv].
  static Map<String, dynamic>? get startupIptvChannelCached =>
      _startupIptvChannelCached;

  /// Resolve the startup channel once, before `runApp`. Never throws — a
  /// failure here must degrade to "no startup channel", never to a broken boot.
  static Future<void> warmStartupIptv() async {
    try {
      if (!await getStartupIptvEnabled()) return;
      final mode = await getStartupIptvMode();
      final channel = mode == startupIptvModePinned
          ? await getStartupIptvChannel()
          : await getIptvLastLiveChannel();
      final url = channel?['url'];
      if (url is! String || url.isEmpty) {
        // Nothing remembered yet — the very first boot after switching this on.
        // Rather than doing nothing (which reads as broken), hand the IPTV page
        // a sentinel and let it bootstrap from whatever it lands on. Resolved
        // there, not here, because picking "the first channel" needs the loaded
        // catalog and this runs before the first frame.
        //
        // Only for 'last': "a specific channel" with none chosen is a
        // deliberate blank the settings row already labels, and auto-picking
        // something else would contradict what the user asked for.
        if (mode == startupIptvModeLast) {
          _startupIptvChannelCached = const {startupIptvFirstAvailable: true};
        }
        return;
      }
      _startupIptvChannelCached = channel;
    } catch (_) {
      _startupIptvChannelCached = null;
    }
  }

  // ============================================================================
  // Remote Control Settings
  // ============================================================================

  /// Get whether remote control feature is enabled
  static Future<bool> getRemoteControlEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteControlEnabledKey) ?? true;
  }

  static Future<bool> getUpdateAutoCheckEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_updateAutoCheckEnabledKey) ?? true;
  }

  static Future<void> setUpdateAutoCheckEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_updateAutoCheckEnabledKey, enabled);
  }

  static Future<String?> getIgnoredUpdateVersion() async {
    final prefs = await DevicePreferences.instance();
    final value = prefs.getString(_updateIgnoredVersionKey);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> setIgnoredUpdateVersion(String? version) async {
    final prefs = await DevicePreferences.instance();
    if (version == null || version.trim().isEmpty) {
      await prefs.remove(_updateIgnoredVersionKey);
    } else {
      await prefs.setString(_updateIgnoredVersionKey, version);
    }
  }

  /// Set whether remote control feature is enabled
  static Future<void> setRemoteControlEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteControlEnabledKey, enabled);
  }

  /// Get whether remote intro dialog has been shown
  static Future<bool> getRemoteIntroShown() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_remoteIntroShownKey) ?? false;
  }

  /// Set whether remote intro dialog has been shown
  static Future<void> setRemoteIntroShown(bool shown) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_remoteIntroShownKey, shown);
  }

  /// Get TV device name for remote control (TV only)
  static Future<String?> getRemoteTvDeviceName() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_remoteTvDeviceNameKey);
  }

  /// Set TV device name for remote control (TV only)
  static Future<void> setRemoteTvDeviceName(String name) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteTvDeviceNameKey, name);
  }

  /// Get last connected device info (Mobile only)
  static Future<Map<String, dynamic>?> getRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
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
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_remoteLastDeviceKey, jsonEncode(device));
  }

  /// Clear last connected device info
  static Future<void> clearRemoteLastDevice() async {
    final prefs = await DevicePreferences.instance();
    await prefs.remove(_remoteLastDeviceKey);
  }

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
  // Stremio TV Local Catalogs
  // ==========================================================================

  /// Get all locally imported catalogs for Stremio TV.
  static Future<List<Map<String, dynamic>>> getStremioTvLocalCatalogs() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvLocalCatalogsKey);
    if (json == null) return [];

    try {
      final list = await decodeJsonAsync(json) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error reading Stremio TV local catalogs: $e');
      return [];
    }
  }

  /// Save all locally imported catalogs for Stremio TV.
  static Future<void> setStremioTvLocalCatalogs(
    List<Map<String, dynamic>> catalogs,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (catalogs.isEmpty) {
      await prefs.remove(_stremioTvLocalCatalogsKey);
    } else {
      await prefs.setString(_stremioTvLocalCatalogsKey, jsonEncode(catalogs));
    }
  }

  /// Add a single local catalog. Returns false if a catalog with the same ID
  /// already exists.
  static Future<bool> addStremioTvLocalCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final existing = await getStremioTvLocalCatalogs();
    final id = catalog['id'] as String?;
    if (id == null) return false;
    if (existing.any((c) => c['id'] == id)) return false;
    existing.add(catalog);
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  /// Remove a local catalog by its ID.
  static Future<void> removeStremioTvLocalCatalog(String catalogId) async {
    final existing = await getStremioTvLocalCatalogs();
    existing.removeWhere((c) => c['id'] == catalogId);
    await setStremioTvLocalCatalogs(existing);
  }

  /// Update an existing local catalog by its ID (replaces the entry in-place).
  static Future<bool> updateStremioTvLocalCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final existing = await getStremioTvLocalCatalogs();
    final id = catalog['id'] as String?;
    if (id == null) return false;
    final idx = existing.indexWhere((c) => c['id'] == id);
    if (idx < 0) return false;
    existing[idx] = catalog;
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  // --------------------------------------------------------------------------
  // Stremio TV Catalog Repo URLs
  // --------------------------------------------------------------------------

  /// Get saved catalog repository URLs.
  static Future<List<String>> getStremioTvCatalogRepoUrls() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_stremioTvCatalogRepoUrlsKey) ?? [];
  }

  /// Set catalog repository URLs.
  static Future<void> setStremioTvCatalogRepoUrls(List<String> urls) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_stremioTvCatalogRepoUrlsKey, urls);
  }

  /// Add a catalog repository URL. Returns false if already present.
  static Future<bool> addStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    if (urls.contains(url)) return false;
    urls.add(url);
    await setStremioTvCatalogRepoUrls(urls);
    return true;
  }

  /// Remove a catalog repository URL.
  static Future<void> removeStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    urls.remove(url);
    await setStremioTvCatalogRepoUrls(urls);
  }

  // ==========================================================================
  // Stremio TV Channel Filters
  // ==========================================================================

  static const String _stremioTvDisabledChannelFiltersKey =
      'stremio_tv_disabled_channel_filters_v1';

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

  static const String _catalogSearchDisabledAddonsKey =
      'catalog_search_disabled_addons_v1';

  /// Get the set of addon IDs the user has DISABLED for catalog search on the
  /// Search tab (empty = every searchable addon is queried).
  static Future<Set<String>> getCatalogSearchDisabledAddons() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_catalogSearchDisabledAddonsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading catalog search disabled addons: $e');
      return {};
    }
  }

  /// Save the set of addon IDs disabled for catalog search.
  static Future<void> setCatalogSearchDisabledAddons(
    Set<String> disabled,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_catalogSearchDisabledAddonsKey);
    } else {
      await prefs.setString(
        _catalogSearchDisabledAddonsKey,
        jsonEncode(disabled.toList()),
      );
    }
  }

  static const String _homeDisabledSectionsKey = 'home_disabled_sections_v1';

  /// Get the set of Home-row IDs the user has hidden via the Home Page manager
  /// (empty = every row shown). IDs are fixed-section leaves (e.g. `cw:movies`,
  /// `trakt:shows`, `fav:iptv`) and catalog leaves (`addonId:type:catalogId`).
  static Future<Set<String>> getHomeDisabledSections() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeDisabledSectionsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading home disabled sections: $e');
      return {};
    }
  }

  /// Save the set of hidden Home-row IDs.
  static Future<void> setHomeDisabledSections(Set<String> disabled) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_homeDisabledSectionsKey);
    } else {
      await prefs.setString(
        _homeDisabledSectionsKey,
        jsonEncode(disabled.toList()),
      );
    }
  }

  static const String _homeExtraRowsKey = 'home_extra_rows_v1';

  /// The OPT-IN extra Home rows (default-off, so the disabled-set above can't
  /// express them): Trakt/Simkl list rows and IPTV custom-list rows. IDs are
  /// `traktlist:<apiValue>`, `traktlist:custom:<id>`, `traktlist:liked:<id>`,
  /// `simkllist:<enumName>`, `iptvlist:<listId>`. [HomeExtraRow.title] is the
  /// display name captured at opt-in time so dynamic rows (custom/liked
  /// lists, IPTV lists) render a header instantly and stay representable in
  /// the Home Rows manager through an API outage; built-in rows ignore it.
  /// Order is NOT meaningful — the board renders extras in canonical order.
  static Future<List<HomeExtraRow>> getHomeExtraRows() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeExtraRowsKey);
    if (json == null) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final seen = <String>{};
      final out = <HomeExtraRow>[];
      for (final e in list) {
        if (e is! Map) continue;
        final id = e['id'];
        if (id is! String || id.isEmpty || !seen.add(id)) continue;
        final title = e['title'];
        out.add((id: id, title: title is String ? title : ''));
      }
      return out;
    } catch (e) {
      debugPrint('Error reading home extra rows: $e');
      return const [];
    }
  }

  /// Save the opted-in extra Home rows (empty = key removed).
  static Future<void> setHomeExtraRows(List<HomeExtraRow> rows) async {
    final prefs = await ProfilePreferences.instance();
    if (rows.isEmpty) {
      await prefs.remove(_homeExtraRowsKey);
    } else {
      await prefs.setString(
        _homeExtraRowsKey,
        jsonEncode([
          for (final r in rows) {'id': r.id, 'title': r.title},
        ]),
      );
    }
  }

  static const String _homeRowOrderKey = 'home_row_order_v1';

  /// The user's global Home-row order, expressed with the same stable ids used
  /// by the Home Rows manager. Missing/unavailable ids remain in this list so
  /// reconnecting a tracker or reinstalling an addon restores its old slot.
  /// An empty list means the board's canonical order.
  static Future<List<String>> getHomeRowOrder() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeRowOrderKey);
    if (json == null) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      final seen = <String>{};
      return [
        for (final value in raw)
          if (value is String && value.isNotEmpty && seen.add(value)) value,
      ];
    } catch (e) {
      debugPrint('Error reading home row order: $e');
      return const [];
    }
  }

  /// Save the user's global Home-row order. Empty restores canonical order.
  static Future<void> setHomeRowOrder(List<String> order) async {
    final prefs = await ProfilePreferences.instance();
    final seen = <String>{};
    final normalized = [
      for (final id in order)
        if (id.isNotEmpty && seen.add(id)) id,
    ];
    if (normalized.isEmpty) {
      await prefs.remove(_homeRowOrderKey);
    } else {
      await prefs.setString(_homeRowOrderKey, jsonEncode(normalized));
    }
  }

  static const String _homeHeroSourceKey = 'home_hero_source_v1';

  /// Where the Spotlight home layout's hero reel comes from.
  ///
  /// Modes: `random` (the DEFAULT — "Surprise me": any installed browsable
  /// catalog, re-rolled each board load), `auto` (the first non-empty board
  /// row) and `custom` (one of [HomeHeroSource.ids], catalog leaves in the
  /// Home Rows grammar `addonId:type:catalogId`; more than one re-rolls among
  /// them each load). Unknown modes and a custom mode with no ids read back
  /// as `random` so a bad write can never wedge the hero. `auto` is an
  /// explicit choice now, so it is STORED — only the default removes the key.
  static Future<HomeHeroSource> getHomeHeroSource() async {
    const fallback = (mode: HomeHeroSourceMode.random, ids: <String>[]);
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeHeroSourceKey);
    if (json == null) return fallback;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final ids = <String>[];
      final seen = <String>{};
      final rawIds = map['ids'];
      if (rawIds is List) {
        for (final e in rawIds) {
          if (e is String && e.isNotEmpty && seen.add(e)) ids.add(e);
        }
      }
      final mode = switch (map['mode']) {
        'auto' => HomeHeroSourceMode.auto,
        'custom' when ids.isNotEmpty => HomeHeroSourceMode.custom,
        _ => HomeHeroSourceMode.random,
      };
      return (mode: mode, ids: ids);
    } catch (e) {
      debugPrint('Error reading home hero source: $e');
      return fallback;
    }
  }

  /// Save the Spotlight hero source (the default `random` + no ids = key
  /// removed; `auto` is stored, or it would read back as the default).
  static Future<void> setHomeHeroSource(HomeHeroSource source) async {
    final prefs = await ProfilePreferences.instance();
    if (source.mode == HomeHeroSourceMode.random && source.ids.isEmpty) {
      await prefs.remove(_homeHeroSourceKey);
    } else {
      await prefs.setString(
        _homeHeroSourceKey,
        jsonEncode({'mode': source.mode.name, 'ids': source.ids}),
      );
    }
  }

  /// Clears synchronous mirrors before a profile activation is published.
  /// The target bootstrap immediately warms them from its captured scope.
  static void resetProfileCaches() {
    tvKeyboardEnabledCached = !PlatformUtil.isTvOS;
    tvHomeStyleCached = 'canvas';
    debrifyTvStyleCached = 'grid';
    detailPageStyleCached = kDetailPageStyleDefault;
    detailThemeCached = 'signal';
    appThemeCached = 'legacy';
    themeOverridesCached = '';
    parentsGuideStyleCached = 'compass';
    iptvStyleCached = 'command';
    discoverLayoutCached = 'stage';
    launchAnimationCached = 'trace';
    launchIdentPaletteCached = 'ident';
    tvSidebarStyleCached = 'ghost';
    desktopSidebarStyleCached = 'rail';
    sidebarConfigurationCached = SidebarConfiguration.defaults();
    playerStartPortraitCached = false;
    uiSoundsCached = true;
    uiHapticsCached = true;
    _startupIptvChannelCached = null;
  }
}

/// See [StorageService.getHomeHeroSource].
enum HomeHeroSourceMode { auto, random, custom }

/// The Spotlight hero source pref — see [StorageService.getHomeHeroSource].
/// [ids] are kept even in `auto`/`random` mode so a user flipping modes in
/// Settings doesn't lose their custom picks.
typedef HomeHeroSource = ({HomeHeroSourceMode mode, List<String> ids});

/// One opted-in extra Home row — see [StorageService.getHomeExtraRows].
typedef HomeExtraRow = ({String id, String title});

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
