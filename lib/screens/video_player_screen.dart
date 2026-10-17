import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/playlist_artwork_storage.dart';
import 'package:debrify/services/storage/playlist_metadata_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import '../models/source_playlist_resolver.dart';
import '../widgets/playback_startup_view.dart';
import '../utils/episode_playback_request.dart';
import '../utils/show_shuffle.dart';
import '../models/subtitle_source_priority.dart';
import 'video_player/utils/subtitle_priority_selection.dart';
import 'video_player/player_pip_route.dart';
import 'dart:async';
import '../services/source_selection_diagnostics.dart';
import '../services/player_visibility.dart';
import '../utils/media_kit_init.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, kProfileMode, kReleaseMode, listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import '../models/custom_series_identity.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/app_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import '../services/player_display_controls.dart';
import 'package:synchronized/synchronized.dart';

// Removed volume_controller; using media_kit player volume instead
import '../services/local_playback_resume_resolver.dart';
import '../services/startup_stream_policy.dart';
import '../services/direct_source_authorization.dart';
import '../services/media_server_watch_sync.dart';
import '../services/resume_write_guard.dart';
import '../models/profiles/profile_policy.dart';
import '../services/profiles/profile_policy_guard.dart';
import '../services/skip_segment_service.dart';
import '../services/analytics_service.dart';
import '../services/pip_service.dart';
import '../services/audio_effect_session_service.dart';
import '../services/tvos_decode_remedy.dart';
import '../services/tvos_display_match_service.dart';
import '../services/android_native_downloader.dart';
import '../services/desktop_recording_service.dart';
import '../services/live_recording_service.dart';
import '../services/main_page_bridge.dart';
import '../services/profiles/profile_lock_controller.dart';
import '../services/tracking_source_policy.dart';
import '../services/profiles/profile_runtime.dart';
import '../widgets/recording_limit_dialogs.dart';
import '../services/debrid_service.dart';
import '../services/premiumize_service.dart';
import '../services/alldebrid_service.dart';
import '../utils/platform_util.dart';
import '../utils/player_audio_config.dart';
import '../utils/time_formatters.dart';
import '../utils/series_parser.dart';
import '../utils/movie_parser.dart';
import '../utils/iptv_player_paging.dart';
import '../services/movie_metadata_service.dart';
import '../models/iptv_playlist.dart';
import '../services/stremio_iptv_service.dart';
import '../services/iptv_epg_service.dart';
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/next_episode_service.dart';

import '../widgets/tv_text_field.dart';
import '../widgets/video_output_lease.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

// Video Player Components
import 'video_player/models/playlist_entry.dart';
import 'video_player/services/external_subtitle_payload.dart';
import 'video_player/services/subtitle_track_utils.dart';
import 'video_player/models/gesture_state.dart';
import 'video_player/models/hud_state.dart';
import 'video_player/painters/double_tap_ripple_painter.dart';
import 'video_player/utils/gesture_helpers.dart';
import 'video_player/utils/language_mapping.dart';
import 'video_player/utils/subtitle_audio_policy.dart';
import 'video_player/utils/aspect_mode_utils.dart';
import 'video_player/constants/timing_constants.dart';
import 'video_player/widgets/auto_sync_pill.dart';
import 'video_player/widgets/seek_hud.dart';
import 'video_player/widgets/vertical_hud.dart';
import 'video_player/widgets/aspect_ratio_hud.dart';
import 'video_player/widgets/controls.dart';
import 'video_player/widgets/dock_style.dart';
import 'video_player/widgets/tv_controls.dart';
import 'video_player/widgets/aspect_ratio_video.dart';
import 'video_player/widgets/transition_overlay.dart';
import 'video_player/widgets/pikpak_retry_overlay.dart';
import 'video_player/widgets/buffering_indicator.dart';
import 'video_player/widgets/tracks_sheet.dart';
import 'video_player/widgets/player_menu_panel.dart';
import 'video_player/widgets/playlist_sheet.dart';
import 'video_player/widgets/channel_guide.dart';
import 'video_player/widgets/iptv_channel_sheet.dart';
import 'video_player/widgets/iptv_zap_banner.dart';
import 'video_player/widgets/player_guide_style.dart';
import '../widgets/iptv/styles/iptv_style.dart';
import 'video_player/widgets/source_sheet.dart';
import 'video_player/widgets/stremio_tv_guide_sheet.dart';
import 'video_player/models/channel_entry.dart';
import 'video_player/services/network_tuning.dart';
import 'video_player/services/subtitle_settings_service.dart';
import 'video_player/services/media_kit_subtitle_auto_sync.dart';
import 'video_player/services/playback_ui_clock.dart';
import 'video_player/services/skip_segment_ui_controller.dart';
import 'video_player/services/android_renderer_startup_fallback.dart';
import 'video_player/services/iptv_tune_diagnostics.dart';
import 'video_player/services/iptv_live_recovery.dart';
import 'video_player/widgets/subtitle_line_picker_overlay.dart';
import 'video_player/widgets/skip_segment_button.dart';
import 'video_player/widgets/sleep_timer_sheet.dart';
import 'video_player/widgets/sync_stepper_overlay.dart';
import 'video_player/widgets/spotlight_dialog.dart';
import 'video_player/widgets/debrify_tv_banner.dart';
import '../models/stremio_subtitle.dart';
import '../models/stremio_addon.dart';
import '../models/torrent.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/content_display_match_mode.dart';
import '../services/series_source_fetcher.dart';
import '../services/stremio_service.dart';
import '../services/stremio_subtitle_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/simkl/simkl_service.dart';
import '../services/mdblist/mdblist_models.dart';
import '../services/mdblist/mdblist_scrobble_session.dart';
import '../services/mdblist/mdblist_service.dart';
import 'package:http/http.dart' as http;
import '../utils/episode_progress_merge.dart';
import '../utils/tv_keys.dart';
import '../utils/tv_search_focus_handoff.dart';

// Re-export PlaylistEntry for backward compatibility
export 'video_player/models/playlist_entry.dart';
export 'video_player/models/channel_entry.dart';
export '../features/video_player/models/iptv_catchup_request_gate.dart'
    show IptvCatchupRequestGate;
import '../features/video_player/models/vp_manual_source_validation_failure.dart';
import '../features/video_player/models/vp_season_episode_selection.dart';
import '../features/video_player/models/vp_subtitle_apply_attempt.dart';
import '../features/video_player/models/vp_iptv_zap_page.dart';
import '../features/video_player/models/iptv_catchup_request_gate.dart';
import '../features/video_player/presentation/vp_random_choice_tile.dart';
import '../features/video_player/application/vp_format.dart';
import '../features/video_player/application/vp_filename_hash.dart';
import '../features/video_player/application/vp_identity_text.dart';
import '../features/video_player/application/vp_subtitle_identity.dart';
import '../features/video_player/presentation/legacy_video_player/vp_sleep_timer_controller.dart';
import '../features/video_player/presentation/legacy_video_player/vp_skip_segment_controller.dart';
import '../features/video_player/presentation/legacy_video_player/vp_display_mode_controller.dart';
import '../features/video_player/presentation/legacy_video_player/vp_trakt_scrobbler.dart';
import '../features/video_player/presentation/legacy_video_player/vp_simkl_scrobbler.dart';
import '../features/video_player/presentation/legacy_video_player/vp_mdblist_scrobbler.dart';
import '../features/video_player/presentation/legacy_video_player/vp_local_completion.dart';
import '../features/video_player/presentation/legacy_video_player/vp_pip_lifecycle.dart';
import '../features/video_player/presentation/legacy_video_player/vp_subtitle_auto_sync.dart';
import '../features/video_player/presentation/legacy_video_player/vp_subtitle_apply.dart';
import '../features/video_player/presentation/legacy_video_player/vp_subtitle_language_policy.dart';
import '../features/video_player/presentation/legacy_video_player/vp_track_preferences.dart';
import '../features/video_player/presentation/legacy_video_player/vp_addon_subtitles.dart';
import '../features/video_player/presentation/legacy_video_player/vp_identify_title.dart';
import '../features/video_player/presentation/legacy_video_player/vp_identify_title_ui.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_menu_ui.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_menu.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_recording.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_recording_resources.dart';
import '../features/video_player/presentation/legacy_video_player/vp_resume_keys.dart';
import '../features/video_player/presentation/legacy_video_player/vp_resume_restore.dart';
import '../features/video_player/presentation/legacy_video_player/vp_resume_save.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_zap_ring.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_zap_ladder.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_guide_catchup.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_channel_switch.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_live_sources.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_watch_memory.dart';
import '../features/video_player/presentation/legacy_video_player/vp_iptv_zap_banner.dart';

/// A full-featured video player screen with playlist support and navigation controls.
///
/// Features:
/// - Play/pause controls
/// - Next/Previous episode navigation (when playlist is available)
/// - Gesture controls for seeking, volume, and brightness
/// - Aspect ratio controls
/// - Playback speed controls
/// - Audio and subtitle track selection
/// - Auto-advance to next episode when current episode ends
/// - Resume playback from last position
/// - Series-aware episode ordering and tracking
class VideoPlayerScreen extends StatefulWidget {
  /// Final local-resume selection. Server/custom identities must not inherit
  /// URL-keyed progress belonging to catalog or generic playback.
  static Future<Map<String, dynamic>?> readLocalResume({
    required String? contentId,
    required String resumeKey,
    required Future<Map<String, dynamic>?> Function() enhanced,
  }) async {
    final state = await enhanced();
    if (state != null ||
        CustomSeriesIdentity.isCustom(contentId) ||
        (contentId?.startsWith('medialibrary:') ?? false)) {
      return state;
    }
    return VideoResumeStorage.getVideoResume(resumeKey);
  }

  final String videoUrl;

  /// Optional separate audio track played alongside [videoUrl] via mpv's
  /// external-audio support (high-res YouTube serves video/audio separately).
  final String? audioUrl;
  final String title;
  final String? subtitle;
  final List<PlaylistEntry>? playlist;
  final int? startIndex;
  final String? rdTorrentId; // For updating playlist poster (RealDebrid)
  final String? torboxTorrentId; // For updating playlist poster (Torbox)
  final String? pikpakCollectionId; // For updating playlist poster (PikPak)
  // Optional: Debrify TV provider to fetch the next playable item (url & title)
  final Future<Map<String, String>?> Function()? requestMagicNext;
  // Optional: Debrify TV channel switcher (firstUrl, firstTitle, channel metadata)
  final Future<Map<String, dynamic>?> Function()? requestNextChannel;
  // Optional: Switch to a specific channel by ID
  final Future<Map<String, dynamic>?> Function(String channelId)?
  requestChannelById;
  // Optional: Channel directory for channel guide
  final List<Map<String, dynamic>>? channelDirectory;
  // Advanced: start each video at a random timestamp
  final bool initialContinuousShuffle;
  final bool startFromRandom;
  final int randomStartMaxPercent;
  // Start video at a specific percentage (0.0 to 1.0)
  final double? startAtPercent;
  // Advanced: hide seekbar (double-tap seek still enabled)
  final bool hideSeekbar;
  // Channel name badge overlay
  final bool showChannelName;
  final String? channelName;
  final int? channelNumber;
  // Show video title in player controls
  final bool showVideoTitle;
  // Hide all bottom options (next, audio, etc.) - back button stays
  final bool hideOptions;
  // Hide back button - use device back gesture or escape key
  final bool hideBackButton;
  // HTTP headers for authenticated streaming (e.g., PikPak, private CDNs)
  final Map<String, String>? httpHeaders;
  // Disable auto-resume - start from the specified startIndex instead of last played
  final bool disableAutoResume;
  // Explicit view mode - if null, auto-detect from filenames
  final PlaylistViewMode? viewMode;
  // Content metadata for fetching external subtitles from Stremio addons
  final String? contentImdbId;
  final String? contentType; // 'movie' or 'series'
  final int? contentSeason;
  final int? contentEpisode;
  final String? contentTitle; // Clean display name (IMDB title)
  final PlaybackResumePolicy resumePolicy;
  // IPTV channel list for in-player channel switching
  final List<IptvChannel>? iptvChannels;
  final int? iptvStartIndex;
  final List<String>? iptvCategories;
  final String? iptvSourceId;
  final String? iptvSourceName;
  final String? iptvSelectedCategory;
  final String? iptvContentType;
  final List<Map<String, dynamic>>? iptvSources;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  iptvBrowseProvider;
  // Stremio sources for in-player source switching
  final List<Torrent>? stremioSources;
  final int? stremioCurrentSourceIndex;
  final Future<String?> Function(Torrent)? resolveStremioSource;
  // Torrent search source switching: resolves a Torrent to a full playlist
  final SourcePlaylistResolve? resolveSourceToPlaylist;
  final bool startupFailoverEnabled;
  final String? startupResolverProvider;
  final Future<void> Function(Torrent)? onStremioSourceCommitted;
  final Future<void> Function()? onStartupSourcesExhausted;
  // "Load more sources" backend for the source sheet (series pack/episode
  // searches, or the movie search for bound movie plays)
  final SeriesSourceFetcher? seriesSourceFetcher;
  // Stremio TV channel guide data
  final List<Map<String, dynamic>>? stremioTvChannels;
  final String? stremioTvCurrentChannelId;
  final Future<Map<String, dynamic>?> Function(List<String>)?
  stremioTvGuideDataProvider;
  final Future<Map<String, dynamic>?> Function(String)?
  stremioTvChannelSwitchProvider;
  final Future<Map<String, dynamic>?> Function(String)? stremioTvNextProvider;
  // Trakt scrobble: send playback progress to Trakt when playing from Trakt screen
  final bool traktScrobble;
  // Trakt progress: resume fallback when no local resume exists (0-100)
  final double? traktProgressPercent;
  // Simkl scrobble/progress — fully parallel to the Trakt pair above (both
  // trackers can run simultaneously; see the Simkl integration plan).
  final bool simklScrobble;
  final double? simklProgressPercent;
  final bool mdblistScrobble;
  final double? mdblistProgressPercent;

  /// Subtitle tracks known at launch (e.g. YouTube closed captions), surfaced
  /// in the subtitle menu as a pre-loaded provider group. Null for sources
  /// whose subtitles are fetched lazily from Stremio addons by IMDb id.
  final List<StremioSubtitle>? initialSubtitles;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.audioUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    this.rdTorrentId,
    this.torboxTorrentId,
    this.pikpakCollectionId,
    this.requestMagicNext,
    this.requestNextChannel,
    this.requestChannelById,
    this.channelDirectory,
    this.initialContinuousShuffle = false,
    this.startFromRandom = false,
    this.randomStartMaxPercent = 40,
    this.startAtPercent,
    this.hideSeekbar = false,
    this.showChannelName = false,
    this.channelName,
    this.channelNumber,
    this.showVideoTitle = true,
    this.hideOptions = false,
    this.hideBackButton = false,
    this.httpHeaders,
    this.disableAutoResume = false,
    this.viewMode,
    this.contentImdbId,
    this.contentType,
    this.contentSeason,
    this.contentEpisode,
    this.contentTitle,
    this.resumePolicy = PlaybackResumePolicy.sourceSpecific,
    this.iptvChannels,
    this.iptvStartIndex,
    this.iptvCategories,
    this.iptvSourceId,
    this.iptvSourceName,
    this.iptvSelectedCategory,
    this.iptvContentType,
    this.iptvSources,
    this.iptvBrowseProvider,
    this.stremioSources,
    this.stremioCurrentSourceIndex,
    this.resolveStremioSource,
    this.resolveSourceToPlaylist,
    this.startupFailoverEnabled = false,
    this.startupResolverProvider,
    this.onStremioSourceCommitted,
    this.onStartupSourcesExhausted,
    this.seriesSourceFetcher,
    this.stremioTvChannels,
    this.stremioTvCurrentChannelId,
    this.stremioTvGuideDataProvider,
    this.stremioTvChannelSwitchProvider,
    this.stremioTvNextProvider,
    this.traktScrobble = false,
    this.traktProgressPercent,
    this.simklScrobble = false,
    this.simklProgressPercent,
    this.mdblistScrobble = false,
    this.mdblistProgressPercent,
    this.initialSubtitles,
  }) : assert(randomStartMaxPercent >= 0);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with TickerProviderStateMixin {
  _VideoPlayerScreenState() {
    _sleep = VpSleepTimerController(_VpSleepTimerHostAdapter(this));
    _skip = VpSkipSegmentController(_VpSkipSegmentHostAdapter(this));
    _display = VpDisplayModeController(_VpDisplayModeHostAdapter(this));
    _trakt = VpTraktScrobbler(_VpTraktScrobblerHostAdapter(this));
    _simkl = VpSimklScrobbler(_VpSimklScrobblerHostAdapter(this));
    _mdblist = VpMdblistScrobbler(_VpMdblistScrobblerHostAdapter(this));
    _completion = VpLocalCompletion(_VpLocalCompletionHostAdapter(this));
    _pip = VpPipLifecycle(_VpPipLifecycleHostAdapter(this));
    _subtitleSync = VpSubtitleAutoSync(_VpSubtitleAutoSyncHostAdapter(this));
    _subtitleApply = VpSubtitleApply(_VpSubtitleApplyHostAdapter(this));
    _subtitleLanguage = VpSubtitleLanguagePolicy(
      _VpSubtitleLanguagePolicyHostAdapter(this),
    );
    _trackPreferences = VpTrackPreferences(
      _VpTrackPreferencesHostAdapter(this),
    );
    _addonSubtitles = VpAddonSubtitles(_VpAddonSubtitlesHostAdapter(this));
    _identify = VpIdentifyTitle(_VpIdentifyTitleHostAdapter(this));
    _identifyUi = VpIdentifyTitleUi(_VpIdentifyTitleUiHostAdapter(this));
    _menuUi = VpPlayerMenuUi(_VpPlayerMenuUiHostAdapter(this));
    _menu = VpPlayerMenu(_VpPlayerMenuHostAdapter(this));
    _recording = VpIptvRecording(_VpIptvRecordingHostAdapter(this));
    _recordingResources = VpIptvRecordingResources(
      _VpIptvRecordingResourcesHostAdapter(this),
    );
    _resumeKeys = VpResumeKeys(_VpResumeKeysHostAdapter(this));
    _resumeRestore = VpResumeRestore(_VpResumeRestoreHostAdapter(this));
    _resumeSave = VpResumeSave(_VpResumeSaveHostAdapter(this));
    _zapRing = VpIptvZapRing(_VpIptvZapRingHostAdapter(this));
    _zapLadder = VpIptvZapLadder(_VpIptvZapLadderHostAdapter(this));
    _iptvGuide = VpIptvGuideCatchup(_VpIptvGuideCatchupHostAdapter(this));
    _iptvSwitch = VpIptvChannelSwitch(_VpIptvChannelSwitchHostAdapter(this));
    _iptvSources = VpIptvLiveSources(_VpIptvLiveSourcesHostAdapter(this));
    _iptvMemory = VpIptvWatchMemory(_VpIptvWatchMemoryHostAdapter(this));
    _iptvBanner = VpIptvZapBanner(_VpIptvZapBannerHostAdapter(this));
  }
  void _vpSetState(VoidCallback fn) => setState(fn);

  static const MethodChannel _tvReleaseLogChannel = MethodChannel(
    'debrify/tvlog',
  );
  static const MethodChannel _androidPlayerDiagnosticChannel = MethodChannel(
    'debrify/player_diagnostics',
  );

  late mk.Player _player;
  // _player is assigned partway through the async _initializePlayer(); if the
  // user backs out before that (or init throws first), dispose() must not
  // touch the unassigned late field (LateInitializationError during pop).
  bool _playerCreated = false;

  /// Audio session announced to system effect apps (Android only). Non-null
  /// only while an OPEN broadcast is outstanding — see
  /// [_attachAudioEffectSession] / [_releaseAudioEffectSession].
  int? _audioEffectSessionId;
  late mkv.VideoController _videoController;
  AndroidVideoRendererMode _androidVideoRendererMode =
      AndroidVideoRendererMode.automatic;

  /// Apple TV blue-screen ladder (PLAYER_TVOS_10BIT_PLAN.md): watches what
  /// the decoder produced and re-routes high-bit VideoToolbox surfaces the
  /// GLES interop cannot represent. Null everywhere but tvOS.
  TvosDecodeRemedy? _tvosDecodeRemedy;

  /// tvOS manual escape hatch — forces `hwdec=no` at controller creation.
  /// Preloaded in [_loadPlayerDefaults]; [_createPlayerInstance] is
  /// synchronous and cannot read prefs itself.
  bool _tvosForceSoftwareDecode = false;
  ContentDisplayMatchMode _contentDisplayMatchMode =
      ContentDisplayMatchMode.systemDefault;
  int _tvosDisplayMatchToken = 0;
  Timer? _tvosDisplayMatchTimer;
  String? _lastTvosDisplayMatchSignature;

  /// Audio-output settings (AUDIO_FIDELITY_PLAN.md), preloaded in
  /// [_loadPlayerDefaults] and applied by [_configurePlayerAudio].
  bool _audioPassthroughEnabled = false;
  bool _systemAudioEffectsEnabled = false;
  bool _appleMultichannelEnabled = false;
  int _tvosRouteOutputChannels = 0;
  bool _tvosForceStereoAudio = false;
  bool _tvosLegacyAudioOutput = false;
  int _playerInstanceGeneration = 0;
  bool _playerPresentationInitialized = false;

  // Explicit Android renderers can be rejected by a vendor codec, GPU, or
  // surface implementation. The startup guard is deliberately
  // limited to the first successfully decoded item in this screen: once the
  // output has attached, later network/media failures must not be blamed on the
  // renderer. A confirmed renderer failure recreates the whole player once.
  bool _rendererValidatedForSession = false;
  bool _rendererFallbackInProgress = false;
  int _rendererStartupGuardToken = 0;
  int _rendererStartupValidationGeneration = -1;
  mk.Media? _activeOpenedMedia;
  bool _activeMediaShouldPlay = false;
  bool _activeMediaUserPaused = false;
  final math.Random _random = math.Random();
  SeriesPlaylist? _cachedSeriesPlaylist;
  List<PlaylistEntry>? _activePlaylist;
  late final bool _seriesImdbKnownAtLaunch;
  Future<void>? _episodeMetadataReady;
  late final Future<void> _playerInitializationFuture;
  int _playlistIdentityToken = 0;
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
  String?
  _currentStreamUrl; // Last resolved stream URL for the active playlist entry

  // Cached IMDB ID for single-file movie playback (when no playlist exists)
  String? _singleFileImdbId;
  bool _singleFileImdbFetched = false;

  // User-selected identity override for addon subtitle lookups in this item.
  String? _manualContentImdbId;
  String? _manualContentType;
  int? _manualContentSeason;
  int? _manualContentEpisode;
  String? _manualSubtitleDisplayLabel;

  // PikPak cold storage retry logic
  bool _isPikPakRetrying = false;
  int _pikPakRetryCount = 0;
  String? _pikPakRetryMessage;
  int _pikPakRetryId =
      0; // Cancellation token: increments on each new video to cancel old retries

  /// Construct playlist item data for the Fix Metadata feature
  Map<String, dynamic>? _constructPlaylistItemData() {
    // Need at least one identifier
    if ((widget.rdTorrentId == null || widget.rdTorrentId!.isEmpty) &&
        (widget.torboxTorrentId == null || widget.torboxTorrentId!.isEmpty) &&
        (widget.pikpakCollectionId == null ||
            widget.pikpakCollectionId!.isEmpty) &&
        (_activePlaylist == null || _activePlaylist!.isEmpty)) {
      return null;
    }

    final data = <String, dynamic>{};

    // Add RealDebrid torrent ID if available
    if (widget.rdTorrentId != null && widget.rdTorrentId!.isNotEmpty) {
      data['rdTorrentId'] = widget.rdTorrentId;
    }

    // Add Torbox torrent ID if available
    if (widget.torboxTorrentId != null && widget.torboxTorrentId!.isNotEmpty) {
      data['torboxTorrentId'] = widget.torboxTorrentId;
    }

    // Add PikPak collection ID if available
    if (widget.pikpakCollectionId != null &&
        widget.pikpakCollectionId!.isNotEmpty) {
      data['pikpakFileId'] = widget.pikpakCollectionId;
    }

    // Add title
    data['title'] = widget.title;

    return data.isNotEmpty ? data : null;
  }

  SeriesPlaylist? get _seriesPlaylist {
    if (_activePlaylist == null || _activePlaylist!.isEmpty) return null;
    if (_cachedSeriesPlaylist == null) {
      try {
        // Determine forceSeries: prefer viewMode, then use contentType from catalog
        bool? forceSeries = widget.viewMode?.toForceSeries();
        if (forceSeries == null && widget.contentType != null) {
          // Use catalog content type: 'series' -> force series, 'movie' -> force not series
          forceSeries = widget.contentType == 'series';
        }

        _cachedSeriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          _activePlaylist!,
          collectionTitle: widget.title, // Pass video title as fallback
          forceSeries: forceSeries,
        );
        if (CustomSeriesIdentity.isCustom(widget.contentImdbId)) {
          _cachedSeriesPlaylist!.imdbId = widget.contentImdbId;
        }
      } catch (e) {
        return null;
      }
    }
    return _cachedSeriesPlaylist;
  }

  Timer? _hideTimer;

  // ---- Television transport bar -------------------------------------------
  // The TV bar is a separate widget with real focus; these are the pieces the
  // SCREEN has to own, because raising the bar, restoring focus and deciding
  // whether auto-hide is allowed are all decisions that live with the keys.
  final FocusScopeNode _tvBarScope = FocusScopeNode(debugLabel: 'tvBar');
  final FocusNode _tvPlayPauseFocus = FocusNode(debugLabel: 'tvPlayPause');
  final FocusNode _tvProgressFocus = FocusNode(debugLabel: 'tvProgress');

  /// Focus parks here whenever the bar is down, an overlay closes or a scrub
  /// is cancelled. Without an owned root node the remote goes dead the moment
  /// the focused control is excluded from the tree.
  final FocusNode _tvRootFocus = FocusNode(debugLabel: 'tvPlayerRoot');

  /// True when there is genuinely nothing to seek: a live channel's ordinary
  /// position/duration is just the HLS rolling window. Start Over may expose
  /// its finite archive timeline explicitly. Mirrors the signal the bar uses,
  /// so the keys and the UI can never disagree.
  bool get _tvNoTimeline =>
      (_iptvZapBannerOwnsIdentity &&
          !_iptvGuide.iptvStartOverTimelineVisible) ||
      widget.hideSeekbar ||
      _duration <= Duration.zero;

  /// Cinema scrub, matching the native TV player: holding LEFT/RIGHT pauses
  /// playback and previews a destination that OK confirms and BACK cancels.
  /// [_tvScrubTarget] non-null means a scrub is in flight.
  Duration? _tvScrubTarget;

  /// When the last LEFT/RIGHT arrived, so a held key (fast repeats) can be
  /// told from deliberate taps without needing key-up, which the tvOS fork
  /// does not reliably deliver.
  DateTime? _tvLastArrowAt;
  bool _tvScrubWasPlaying = false;
  int _tvScrubRepeats = 0;

  /// Bumped on every transition and on dispose. A confirm carrying a stale
  /// generation is dropped, so a scrub started before a source switch can
  /// never seek the item that replaced it.
  int _tvScrubGeneration = 0;

  /// The generation in force when the current scrub began.
  int _tvScrubStartedAtGeneration = 0;

  // Text subtitles stay in MediaKit's Flutter renderer. Bitmap subtitles are
  // the narrow exception: their decoded image cues cannot enter a text widget,
  // so the selection path temporarily enables mpv's native compositor.
  bool _isSeekingWithSlider = false;
  Duration? _lastSliderSeekPos;

  // Channel badge auto-hide
  // Debrify TV lower-third (replaces the two legacy corner badges).
  bool _showDebrifyBanner = false;
  bool _debrifyBannerFloatingMounted = false;
  Timer? _debrifyBannerTimer;

  // IPTV zap banner (live channels) — the broadcast lower third.
  //
  // It has two homes. Floating over bare video after a zap, and embedded as
  // the header of the controls dock (they share the bottom strip, so they
  // merge into one panel rather than fight for it). The channel/EPG data
  // below belongs to the playing channel and outlives either presentation.
  bool _showIptvZapBanner = false;
  // Kept in the tree until the fade-out finishes, then dropped — this screen
  // rebuilds on every position tick, so an invisible banner would keep
  // costing layout.
  bool _iptvZapFloatingMounted = false;
  IptvChannel? _iptvZapChannel;
  EpgNowNext? _iptvZapEpg;
  bool _iptvZapEpgLoading = false;
  // The clock the banner's countdown and elapsed rule read. Ticked once a
  // second only while the banner is up, so the rule advances on screen
  // without costing a rebuild for the rest of the session.
  DateTime _iptvZapClock = DateTime.now();

  DoubleTapRipple? _ripple;
  bool _panIgnore = false;
  int _currentIndex = 0;
  Offset? _lastTapLocal;
  bool _isManualEpisodeSelection =
      false; // Track if episode was manually selected
  bool _isAutoAdvancing = false; // Track if episode is auto-advancing
  bool _allowResumeForManualSelection =
      false; // Allow resuming for manual selections with progress
  Timer? _manualSelectionResetTimer; // Timer to reset manual selection flag
  bool _continuousShuffleEnabled = false;
  final List<int> _shuffleBag = [];
  final ShowShuffle _showShuffle = ShowShuffle();
  bool _showShuffleInProgress = false;
  int? _activeShowShuffleGeneration;
  int _showShuffleGeneration = 0;
  int _episodeNavigationGeneration = 0;

  // Channel metadata for Debrify TV flows
  String? _currentChannelName;
  int? _currentChannelNumber;
  String? _currentChannelId;

  // Channel guide state
  bool _showChannelGuide = false;
  bool _showSyncOverlay = false;
  List<ChannelEntry> _channelEntries = [];

  // IPTV channel sheet state
  bool _showIptvChannelSheet = false;
  int _currentIptvIndex = 0;

  /// Phase 0 of the IPTV resilience plan: per-tune debugPrint diagnostics,
  /// same log grammar as the native player's IptvTuneDiagnostics.kt. Inert
  /// for non-IPTV playback (nothing calls onTuneStart there).
  final IptvTuneDiagnostics _iptvDiag = IptvTuneDiagnostics();

  // ── IPTV live recovery (Phases 2/5 of the resilience plan) ─────────────
  //
  // The ONE owner of live re-opens. Sources: live EOF (mpv completed),
  // stream errors, the stall detector, lifecycle rejoin. See
  // iptv_live_recovery.dart; the native player runs the same machine.

  /// Bottom-center reconnect pill text; null = hidden.
  final ValueNotifier<String?> _iptvReconnectText = ValueNotifier(null);

  late final IptvLiveRecovery _iptvLiveRecovery = IptvLiveRecovery(
    isEligible: _iptvSwitch.iptvRecoveryEligible,
    performRetune: _iptvSwitch.performIptvLiveRetune,
    onEpisodeVisible: (_) => _iptvReconnectText.value = 'Reconnecting…',
    onRecovered: () => _iptvReconnectText.value = null,
    onSurrender: (source) {
      _iptvDiag.onRecovery(source, 'surrender');
      _iptvReconnectText.value = 'Stream lost';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${_currentIptvChannel?.name ?? 'This channel'} keeps dropping",
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _iptvLiveRecovery.userRetry('snackbar-retry'),
          ),
        ),
      );
    },
  );

  List<IptvChannel>? _iptvChannelsOverride;
  IptvGuideContext? _iptvGuideContextOverride;
  bool _iptvStartOverActive = false;
  bool _iptvStartOverLoading = false;
  bool _iptvStartOverTimelineRequested = false;

  /// The guide may replace the launch window after a source/category/search
  /// request. Playback always reads this effective list so the selected row,
  /// resume key, title, headers, and later episode navigation stay aligned.
  List<IptvChannel>? get _effectiveIptvChannels =>
      _iptvChannelsOverride ?? widget.iptvChannels;

  /// Live IPTV presents its identity in the bottom zap banner, so the corner
  /// title/channel badges stand down: they said the same thing twice, and the
  /// right-hand one was painted from launch state a zap never refreshed.
  bool get _iptvZapBannerOwnsIdentity => _currentIptvChannel?.isLive == true;

  /// The in-player IPTV guide look, read once at launch (see
  /// [PlayerGuideStyle]). Classic keeps every legacy paint path verbatim.
  PlayerGuideStyle _playerGuideStyle = PlayerGuideStyle.classic;

  // Player dock prefs, read once at launch alongside the guide style.
  PlayerDockStyle _dockStyle = PlayerDockStyle.classic;
  PlayerDockPalette _dockPalette = PlayerDockPalette.ultraviolet;
  PlayerDockSize _dockSize = PlayerDockSize.auto;

  /// The styled dock's measured height. Six host behaviours below assume a
  /// FIXED dock height (the skip button's 160/28, four 72lp gesture bands and
  /// the PikPak overlay's 80); under `two_tier` the dock is variable, so they
  /// read this instead. Seeded to the full viewport height so the very first
  /// frame can only over-protect — under-protection is the actual bug.
  /// `classic` never publishes and every consumer keeps its literal.
  final ValueNotifier<double> _dockExtent = ValueNotifier<double>(0);

  /// Measured height of the IPTV info panel, which the dock's vertical budget
  /// must reserve. Starts at the conservative bound and is corrected by the
  /// panel's own reporter on the next frame.
  double _infoPanelHeight = DockLayoutInput.kInfoPanelBound;

  /// 0..1, mirrored for the dock's volume control. mpv takes 0..100.
  double _dockVolume = 1.0;

  /// The panel's STRUCTURAL signature — which rows exist, not what they say.
  /// Every row is bounded to one line, so content cannot change the height;
  /// only presence can. Recomputed each build, and a change resets the cached
  /// height so a taller panel can never be under-reserved.
  ///
  /// Deliberately excludes `_iptvZapClock`: that ticks every second and would
  /// otherwise reset the cache continuously.
  String get _infoPanelSignature {
    final channel = _iptvZapChannel;
    if (channel == null || !_iptvZapBannerOwnsIdentity) {
      // Debrify TV's flush identity row: presence of plate/title is the
      // whole structure (single bounded row).
      if (_debrifyTvOwnsIdentity) {
        final name = (_currentChannelName ?? widget.channelName)?.trim();
        return [
          'dtv',
          (name?.isNotEmpty ?? false) || _currentChannelNumber != null
              ? 'p'
              : '',
          widget.showVideoTitle ? 't' : '',
        ].join('|');
      }
      return '-';
    }
    final epg = _iptvZapEpg;
    return [
      _playerGuideStyle.name,
      channel.channelNumber != null ? 'n' : '',
      (channel.group?.isNotEmpty ?? false) ? 'g' : '',
      channel.logoUrl != null ? 'l' : '',
      epg?.now != null ? 'w' : '',
      epg?.next != null ? 'x' : '',
      _iptvZapEpgLoading ? 'L' : '',
      _recording.recordingActiveNow ? 'r' : '',
    ].join('|');
  }

  String _lastInfoPanelSignature = '';

  /// Bumped on a panel STRUCTURE change. Separate from the dock generation:
  /// resetting `_infoPanelHeight` alone was not enough — if the newly measured
  /// height happened to equal the reporter's cached value it would suppress
  /// the callback and the budget would stay stuck at the 200lp bound.
  int _infoPanelGeneration = 0;

  /// Bumped whenever the dock's geometry inputs change. A measurement
  /// callback captures this and is discarded if it comes back stale, so a
  /// post-frame report from the previous layout cannot overwrite a newer one.
  int _dockGeometryGeneration = 0;

  /// Everything that can change the dock's height without the dock itself
  /// changing: the viewport, the safe-area insets, the text scaler, the
  /// chosen style and size, and the two flags that add or remove whole rows.
  String _dockGeometrySignature(MediaQueryData media) => [
    media.size.width.round(),
    media.size.height.round(),
    media.padding.top.round(),
    media.padding.bottom.round(),
    media.textScaler.scale(100).round(),
    _dockStyle.name,
    _dockSize.name,
    widget.hideOptions,
    widget.hideSeekbar,
  ].join('|');

  String _lastDockGeometrySignature = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pip.iosPipSession = PlayerPipSession.of(context);
    _refreshDockGeometry();
  }

  /// Drops the cached dock geometry whenever anything that can change the
  /// dock's height changes.
  void _refreshDockGeometry() {
    // Rotation, window resize, split-screen, a safe-area change or a font-size
    // change all land here. Any of them can make the cached extent wrong, and
    // a stale extent means a tap near the bottom is judged against the wrong
    // band — so drop back to the legacy constants until a fresh measurement
    // arrives, rather than trusting the old number for a frame.
    final signature = _dockGeometrySignature(MediaQuery.of(context));
    if (signature == _lastDockGeometrySignature) return;
    _lastDockGeometrySignature = signature;
    _dockGeometryGeneration++;
    _dockExtent.value = 0;
    _infoPanelGeneration++;
    _infoPanelHeight = DockLayoutInput.kInfoPanelBound;
    _lastInfoPanelSignature = '';
  }

  /// Reserved panel height for this build. Resets to the bound (or 0 when no
  /// panel is mounted) the moment the structure changes.
  double get _reservedInfoPanelHeight {
    final signature = _infoPanelSignature;
    if (signature != _lastInfoPanelSignature) {
      _lastInfoPanelSignature = signature;
      _infoPanelGeneration++;
      _infoPanelHeight = signature == '-' ? 0 : DockLayoutInput.kInfoPanelBound;
    }
    return _infoPanelHeight;
  }

  /// Tokens for [_playerGuideStyle], derived once with it — null for classic.
  IptvStyleTokens? _playerGuideTokens;

  // ── IPTV recording (libmpv `stream-record`) ─────────────────────────────
  /// True once the player is confirmed to run on a native (libmpv) backend —
  /// recording is unavailable on the web backend.
  bool _recordingSupported = false;
  bool _isRecording = false;

  /// Filesystem path libmpv is writing the active recording to.
  String? _recordingTempPath;

  /// Watches for the app leaving the foreground, on behalf of two jobs.
  ///
  /// A TEE recording here is backed by nothing but this widget — no
  /// foreground service — so once the app is backgrounded the process can be
  /// killed with the file never published. Finishing at that moment mirrors
  /// what the native TV player does in onStop, and costs nothing: a
  /// backgrounded player isn't reading bytes. ENGINE recordings ignore all of
  /// this — surviving backgrounding is their whole reason to exist.
  ///
  /// PLAYBACK pauses at the same moment. There is no background-audio service
  /// or media notification, so "keep playing" after Home/power really meant
  /// mpv decoding video into an invisible surface — for hours, on devices
  /// where the user granted the battery-optimization exemption recording asks
  /// for. Picture-in-Picture is unaffected for the same reason recording is:
  /// a visible PiP activity reports `inactive`, never `paused`.
  AppLifecycleListener? _lifecycle;

  /// True while playback is paused because the APP left the foreground, not
  /// because the user asked — the flag that authorizes the matching
  /// auto-resume on return, so coming back to the player looks exactly like
  /// it always has (playing). A user's own pause never sets it and is never
  /// resumed over.
  bool _pausedByLifecycle = false;

  /// The recording ENGINE's capture of the CURRENTLY PLAYING live channel
  /// (LiveRecordingService task id), or null. Independent of the tee's
  /// [_isRecording]: an engine capture belongs to the service, not this
  /// widget, so nothing in this screen's lifecycle may stop it implicitly.
  String? _engineTaskId;

  /// Engine-vs-tee flag (Settings → IPTV → Recording), loaded at player setup.
  bool _engineFlagOn = false;

  /// Tap on mpv's log stream while a TEE recording is armed. stream-record
  /// failing INSIDE mpv (its own fopen refused, demuxer that can't dump) is
  /// completely invisible otherwise — the property set succeeds, Dart sees no
  /// error, and no file ever appears. Only errors surface by default (the
  /// player config requests error-level logs), which is exactly the band
  /// stream-record failures log in.
  StreamSubscription<mk.PlayerLog>? _recordLogSub;
  StreamSubscription<mk.PlayerLog>? _subtitleDiagnosticLogSub;
  int _subtitleDiagnosticGeneration = 0;
  VpSubtitleApplyAttempt? _activeSubtitleApplyAttempt;
  final ValueNotifier<String?> _subtitleSelectionCorrection = ValueNotifier(
    null,
  );

  /// Repaints the Record button when a desktop capture starts or ends behind
  /// this screen's back — a scheduled one firing on the channel being watched,
  /// or any capture self-ending (stream drop, 6h cap). Sampling on rebuild
  /// alone would leave the button claiming to record something already dead.
  ///
  /// This screen deliberately keeps NO handle on a desktop capture. Desktop has
  /// no tee (mpv can't mux on media_kit's libs) and no Android engine — the raw
  /// HTTP copy is the only recorder there — but like the engine it belongs to
  /// the SERVICE, so closing the player leaves it running and nothing here may
  /// stop it implicitly. [_desktopCaptureForCurrent] asks the service instead,
  /// which is also what makes a SCHEDULER-started capture stoppable from this
  /// same button.
  VoidCallback? _desktopRecordingRevisionListener;

  /// Bumped whenever a stop, a channel change or a teardown supersedes an
  /// in-flight [_startRecording]. That start does async work (storage lookup,
  /// mkdir) during which `_isRecording` is still false, so the stop-if-
  /// recording checks elsewhere cannot see it; without this token the awaits
  /// could resume and arm libmpv on the NEW channel under the OLD channel's
  /// filename, or arm an already-disposed player and leave the file untracked.
  int _recordingStartGen = 0;

  /// Bumped whenever the guide reports a browse the user drove (a category
  /// pick, a search, a source change). An in-flight re-anchor that predates
  /// the change must not land: it would reset the ring and the persisted
  /// category, silently undoing what the user just asked for.
  int _iptvGuideContextGeneration = 0;

  // Stremio source sheet state
  bool _showSourceSheet = false;
  int _currentSourceIndex = 0;
  final _serverWatch = MediaServerWatchController();
  Torrent? _openedWatchSource;
  int _watchOpenEpoch = 0;
  List<PlaylistEntry>? _pendingSourcePlaylist;
  int _sourcePlaylistResolution = 0;
  // Overrides for sources after Stremio TV channel switch
  List<Torrent>? _stremioSourcesOverride;
  Future<String?> Function(Torrent)? _resolveStremioSourceOverride;
  // Sources grown by the sheet's "Load more" (append-only merge over
  // widget.stremioSources; the fetcher's flags track what was searched)
  List<Torrent>? _augmentedSources;

  // Unified player menu (Spotlight panel) state. The subtitle-identity
  // context is captured at open time, exactly like the old tracks sheet
  // captured it in its `show` arguments.
  bool _showPlayerMenu = false;
  PlayerMenuSection _playerMenuInitialSection = PlayerMenuSection.subtitles;
  final GlobalKey<PlayerMenuPanelState> _playerMenuKey =
      GlobalKey<PlayerMenuPanelState>();
  String? _menuImdbId;
  String? _menuContentType;
  int? _menuSeason;
  int? _menuEpisode;
  List<AddonSubtitleSlot>? _menuCachedSlots;
  String? _menuCacheKey;

  // Stremio TV guide state
  bool _showStremioTvGuide = false;
  String? _currentStremioTvChannelId;
  List<Map<String, dynamic>>? _stremioTvChannelsOverride;
  bool _showStremioTvNextLoading = false;
  String? _currentStremioTvContentImdbId;
  String? _currentStremioTvContentType;
  int? _currentStremioTvContentSeason;
  int? _currentStremioTvContentEpisode;
  String? _currentStremioTvContentTitle;

  /// Effective sources: override from channel switch, load-more-augmented
  /// list, or initial widget sources (in that priority order).
  List<Torrent>? get _effectiveSources =>
      _stremioSourcesOverride ?? _augmentedSources ?? widget.stremioSources;

  /// Effective source resolver: override from channel switch, or initial widget resolver.
  Future<String?> Function(Torrent)? get _effectiveResolver =>
      _resolveStremioSourceOverride ?? widget.resolveStremioSource;

  List<Map<String, dynamic>>? get _effectiveStremioTvChannels =>
      _stremioTvChannelsOverride ?? widget.stremioTvChannels;

  String? get _effectiveContentImdbId =>
      _currentStremioTvContentImdbId ?? widget.contentImdbId;
  String? get _effectiveContentType =>
      _currentStremioTvContentType ?? widget.contentType;
  int? get _effectiveContentSeason =>
      _currentStremioTvContentSeason ?? widget.contentSeason;
  int? get _effectiveContentEpisode =>
      _currentStremioTvContentEpisode ?? widget.contentEpisode;
  String? get _effectiveContentTitle =>
      _currentStremioTvContentTitle ?? widget.contentTitle;

  /// Stable show identity for in-session guide/resume work. Unlike scrobble
  /// initialization, this may legitimately appear after launch when TVMaze
  /// enriches a release-only playlist.
  String? get _currentSeriesImdbId {
    if (CustomSeriesIdentity.isCustom(_effectiveContentImdbId))
      return _effectiveContentImdbId;
    final value =
        _seriesPlaylist?.imdbId ??
        _syntheticGuidePlaylist?.imdbId ??
        _effectiveContentImdbId;
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  late final VpSkipSegmentController _skip;

  // Subtitle style settings
  SubtitleSettingsData? _subtitleSettings;

  // Cached Stremio addon subtitles (per-item cache like Android TV)
  List<StremioSubtitle>? _cachedStremioSubtitles;
  // Per-addon view of the same fetch (drives the sheet's addon groups);
  // _cachedStremioSubtitles is its deduped flat projection.
  List<AddonSubtitleSlot>? _cachedAddonSlots;
  // Subtitle tracks supplied at launch (e.g. YouTube captions), surfaced as a
  // pre-loaded provider group. Content-independent: not keyed by IMDb, so it
  // survives the IMDb-gated cache logic and is offered whenever no per-item
  // slots exist. Built once in initState from widget.initialSubtitles.
  List<AddonSubtitleSlot>? _injectedSubtitleSlots;
  String? _cachedSubtitleKey; // Format: "imdbId:season:episode" or "imdbId"
  String?
  _selectedStremioSubtitleId; // Track selected addon subtitle for UI state
  bool _embeddedSubtitleApplied =
      false; // Track if embedded subtitle was auto-selected
  bool _userManuallySelectedSubtitle =
      false; // Track if user manually selected a subtitle
  bool _trackPreferencesReadyForAddonSubtitles = false;
  int _addonSubtitleFetchToken = 0;
  String? _activeExternalSubtitlePath;
  bool _subtitleOnlyForeignAudio = false;
  bool _subtitleForcedOnly = false;
  bool get _hasSubtitlePolicy =>
      _subtitleOnlyForeignAudio || _subtitleForcedOnly;
  String? _subtitlePreferredAudio;
  String? _subtitleSelectedAudio;
  int _subtitleAudioRevision = 0;
  late final VpSubtitleAutoSync _subtitleSync;
  late final VpSubtitleApply _subtitleApply;
  late final VpSubtitleLanguagePolicy _subtitleLanguage;
  late final VpTrackPreferences _trackPreferences;
  late final VpAddonSubtitles _addonSubtitles;
  late final VpIdentifyTitle _identify;
  late final VpIdentifyTitleUi _identifyUi;
  late final VpPlayerMenuUi _menuUi;
  late final VpPlayerMenu _menu;
  late final VpIptvRecording _recording;
  late final VpIptvRecordingResources _recordingResources;
  late final VpResumeKeys _resumeKeys;
  late final VpResumeRestore _resumeRestore;
  late final VpResumeSave _resumeSave;
  late final VpIptvZapRing _zapRing;
  late final VpIptvZapLadder _zapLadder;
  late final VpIptvGuideCatchup _iptvGuide;
  late final VpIptvChannelSwitch _iptvSwitch;
  late final VpIptvLiveSources _iptvSources;
  late final VpIptvWatchMemory _iptvMemory;
  late final VpIptvZapBanner _iptvBanner;

  // The quiet bottom-right auto-sync surface: a 5s announce line, then
  // nothing until a real event — statuses during passes, word-only results.
  final ValueNotifier<AutoSyncPillModel?> _autoSyncPill =
      ValueNotifier<AutoSyncPillModel?>(null); // announce auto-dismiss
  // Last non-null model, kept so the dismiss fade has content to fade out.
  AutoSyncPillModel? _autoSyncPillLastShown;

  // media_kit state
  bool _isReady = false;
  bool _startupGateActive = false;
  // Debrid-direct first open keeps the LOGICAL gate (tracking suppression,
  // restore sequencing) but hides the overlay: the player's own surface and
  // buffering spinner show and controls come up on tap — the pre-ladder look.
  // The overlay appears only when failover actually starts retrying.
  bool _startupGateOverlayHidden = false;
  // A source explicitly picked from the in-player sheet is validated as one
  // isolated candidate. While this is true, renderer events belong to an
  // untrusted replacement and must not update local completion or any tracker.
  bool _manualSourceGateActive = false;
  bool get _validationGateActive =>
      _startupGateActive ||
      _manualSourceGateActive ||
      (_stremioTvStartupWatch?.blocksProgress ?? false);
  String _startupGateMessage = 'Checking stream…';
  // Blocks the autosave from filing a near-zero position over a deep resume
  // point while a requested resume seek has not landed. See ResumeWriteGuard.
  final ResumeWriteGuard _resumeWriteGuard = ResumeWriteGuard();
  // The 6s tick and explicit UI checkpoints can land together. Serialize the
  // read/modify/write saves so an older autosave cannot finish after, and
  // overwrite, a newer pause or settled-seek checkpoint.
  final Lock _resumeSaveLock = Lock();
  // Bumped whenever the media the landing verifier is watching stops being
  // current (item change, source switch). Aborts the verifier WITHOUT
  // releasing the guard — the guard must survive through the outgoing
  // checkpoint save, which the verifier must not outlive.
  int _resumeVerifyEpoch = 0;
  final DeferredStartupSeek _stremioTvStartupSeek = DeferredStartupSeek();
  ChannelStartupWatch? _stremioTvStartupWatch;
  bool _isPlaying = false;
  // True while the activity is shrunk into a Picture-in-Picture window; the
  // build collapses all interactive/decorative chrome so only the video shows.
  bool _isPipActive = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final PlaybackUiClockController _playbackUiClock =
      PlaybackUiClockController();
  final SkipSegmentUiController _activeSkipSegmentUi =
      SkipSegmentUiController();
  bool _isTransitioning = false; // Show black screen during transitions

  /// One-shot guard set the moment we pop to hand the next episode back to the
  /// host for Quick Play. End-of-video auto-advance (_onPlaybackEnded) and a
  /// manual Next press both funnel into _handleSeriesNextEpisode, which awaits a
  /// network lookup and then pops — without this, the two can race and pop
  /// twice, ejecting the user off the host screen instead of playing the next.
  bool _seriesNextDispatched = false;
  late final VpLocalCompletion _completion;

  // We render using a large logical surface; fit is controlled by BoxFit
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _paramsSub;
  StreamSubscription? _trackSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _iptvErrorSub;
  StreamSubscription? _rendererStartupErrorSub;

  /// Runtime hardware-decoder probe. mpv's configured `hwdec=auto-safe` only
  /// describes what it should try; `hwdec-current` is the decoder that actually
  /// opened for this item. Generations are advanced by every app-owned open,
  /// while property observers catch a decoder/output transition mid-stream.
  int _decoderProbeGeneration = 0;
  int _decoderProbeToken = 0;
  mk.VideoParams? _decoderProbeParams;
  Timer? _decoderProbeTimer;
  String? _lastDecoderDiagnosticSignature;

  // Buffering indicator
  final ValueNotifier<bool> _showBufferingIndicator = ValueNotifier(false);
  Timer? _bufferingDebounceTimer;

  // Gesture state
  GestureMode _mode = GestureMode.none;
  Offset _gestureStartPosition = Offset.zero;
  Duration _gestureStartVideoPosition = Duration.zero;
  double _gestureStartVolume = 0.0;
  double _gestureStartBrightness = 0.0;

  // HUD state
  final ValueNotifier<SeekHudState?> _seekHud = ValueNotifier<SeekHudState?>(
    null,
  );
  final ValueNotifier<VerticalHudState?> _verticalHud =
      ValueNotifier<VerticalHudState?>(null);
  final ValueNotifier<AspectRatioHudState?> _aspectRatioHud =
      ValueNotifier<AspectRatioHudState?>(null);
  late final VpDisplayModeController _display;

  late final VpSleepTimerController _sleep;

  /// Latched from a sleep-timer stop until the user explicitly starts playback
  /// again. Advancing is asynchronous here (resolve the URL, then open), so a
  /// countdown expiring mid-flight would otherwise be undone by the episode
  /// that was already on its way.
  bool _sleepStopLatched = false;
  final ValueNotifier<bool> _speedHoldHud = ValueNotifier<bool>(false);

  /// Whether this player should OPEN upright rather than turning the device
  /// landscape for the user (Settings → Playback → "Open the player in
  /// portrait").
  ///
  /// Phone-only on purpose. A TV has no portrait to open in, and on desktop
  /// [SystemChrome.setPreferredOrientations] does nothing — but honouring the
  /// pref there would still flip the rotate button's label to "Landscape" over
  /// a window that is already wide, describing a rotation that can't happen.
  bool get _startsInPortrait =>
      PlatformUtil.isPhone && PlayerSettingsStorage.playerStartPortraitCached;

  // Rainbow next animation
  late AnimationController _rainbowController;
  late Animation<double> _rainbowOpacity;
  bool _rainbowActive = false;
  bool _transitionRunning = false;
  Timer? _transitionStopTimer;
  Timer? _transitionPhaseTimer;
  int _transitionPhase = 1; // 1 = static, 2 = reveal
  DateTime? _transitionPhase2Started;

  // Retro TV static loading messages
  String _tvStaticMessage = '📺 TUNING...';
  String _tvStaticSubtext = ''; // Second line for video title
  final List<String> _tvStaticMessages = [
    '📺 BUFFERING... JUST KIDDING',
    '📺 RETICULATING SPLINES...',
    '📺 SUMMONING VIDEO GODS...',
    '📺 ENGAGING HYPERDRIVE...',
    '📺 CALIBRATING FLUX CAPACITOR',
    '📺 CONSULTING THE ALGORITHMS',
    '📺 WARMING UP THE PIXELS',
    '📺 BRIBING THE SERVERS...',
  ];

  // Dynamic title for Debrify TV (no-playlist) flow
  String _dynamicTitle = '';
  late final VpTraktScrobbler _trakt;
  late final VpSimklScrobbler _simkl;
  late final VpMdblistScrobbler _mdblist;

  String? _episodeTrackerProgressImdbId;
  // Keeps the analytics session alive during long, interaction-free playback.
  Timer? _analyticsHeartbeatTimer;

  Duration? _randomStartOffset(Duration duration) {
    final num clampedPercent = widget.randomStartMaxPercent.clamp(0, 99);
    if (duration <= Duration.zero || clampedPercent <= 0) {
      return null;
    }
    final maxFraction = clampedPercent.toDouble() / 100.0;
    if (maxFraction <= 0) {
      return null;
    }
    final randomFraction = _random.nextDouble() * maxFraction;
    final milliseconds = (duration.inMilliseconds * randomFraction).floor();
    if (milliseconds <= 0) {
      return null;
    }
    return Duration(milliseconds: milliseconds);
  }

  Duration? _percentStartOffset(Duration duration) {
    final percent = widget.startAtPercent;
    if (percent == null || percent <= 0 || duration <= Duration.zero) {
      return null;
    }
    final clamped = percent.clamp(0.0, 0.99);
    final ms = (duration.inMilliseconds * clamped).floor();
    return ms > 0 ? Duration(milliseconds: ms) : null;
  }

  @override
  void initState() {
    super.initState();
    _continuousShuffleEnabled = widget.initialContinuousShuffle;
    _activeHttpHeaders = widget.httpHeaders;
    PlayerVisibility.opened(this);
    AnalyticsService.screenView('video_player');
    _startAnalyticsHeartbeat();
    _activePlaylist = widget.playlist
        ?.map((entry) => entry.withDefaultHttpHeaders(widget.httpHeaders))
        .toList();
    _seriesImdbKnownAtLaunch = widget.contentImdbId?.trim().isNotEmpty == true;
    // The dock and the zap banner share the bottom strip, and the dock is
    // raised from several places that never go through _toggleControls
    // (volume keys, pointer wake). Watching the notifier catches all of them.
    _controlsVisible.addListener(_onControlsVisibilityChanged);

    // onPause fires on the transition to AppLifecycleState.paused — Android's
    // onStop, i.e. Home or an app switch. Picture-in-Picture keeps the
    // activity visible and reports `inactive` instead, so a PiP'd stream keeps
    // recording AND keeps playing. Deliberately not onInactive: that fires for
    // the notification shade, permission dialogs and the app switcher peek,
    // none of which should stop the video.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        unawaited(_recording.stopRecording(userInitiated: false));
        _pip.pauseForBackground();
      },
      onResume: _pip.resumeFromBackground,
    );

    // Observe, don't sample: see [_desktopRecordingRevisionListener].
    if (DesktopRecordingService.instance.isSupported && !VpS2Hooks.isIOS) {
      void onRevision() {
        if (mounted) setState(() {});
      }

      _desktopRecordingRevisionListener = onRevision;
      DesktopRecordingService.instance.revision.addListener(onRevision);
    }

    // Launch-time subtitles (e.g. YouTube captions): wrap into a single loaded
    // provider group so they appear in the subtitle menu without an addon
    // fetch. Grouped under the first track's source label (e.g. "YouTube").
    final initialSubs = widget.initialSubtitles;
    if (initialSubs != null && initialSubs.isNotEmpty) {
      _injectedSubtitleSlots = [
        AddonSubtitleSlot(
          addonId: 'injected',
          addonName: initialSubs.first.source,
          status: AddonSubtitleStatus.ok,
          subtitles: initialSubs,
        ),
      ];
    }

    // Picture-in-Picture (Android phone and iOS): once native confirms capability,
    // become the active PiP owner and listen so we can collapse chrome inside
    // the tiny window. Auto-enter is armed later, when the video is actually
    // ready (see the player `ready` callback), so pressing Home never shrinks
    // a black/loading frame. Skipped when options are hidden — that context
    // deliberately suppresses the PiP button and tap controls.
    if ((VpS2Hooks.isAndroid || (VpS2Hooks.isIOS && !PlatformUtil.isTvOS)) &&
        !widget.hideOptions) {
      PipService.resolveSupport().then((ok) {
        if (!mounted || !ok) return;
        PipService.attach(
          this,
          onMode: _pip.onPipModeChanged,
          onAction: _pip.onPipAction,
          onRestore: _pip.restoreIosPipPlayer,
        );
        // Reveal the PiP button now that support is known.
        setState(() {});
        // If the player became ready before native support resolved, arm now.
        if (_isReady) _pip.armPipAutoEnter();
      });
    }

    // Log playlist entries to trace relativePath
    if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
      debugPrint(
        '📺 VideoPlayerScreen.initState: Initialized with ${_activePlaylist!.length} playlist entries',
      );
      for (int i = 0; i < _activePlaylist!.length && i < 5; i++) {
        final entry = _activePlaylist![i];
        debugPrint(
          '  Entry[$i]: title="${entry.title}", relativePath="${entry.relativePath}"',
        );
      }
    }

    if (widget.channelName != null && widget.channelName!.trim().isNotEmpty) {
      _currentChannelName = widget.channelName;
    }
    _currentChannelNumber = widget.channelNumber;
    _currentIptvIndex = widget.iptvStartIndex ?? 0;
    _currentSourceIndex = widget.stremioCurrentSourceIndex ?? 0;
    _iptvSources.initIptvStremioSources();
    _currentStremioTvChannelId = _findInitialStremioTvChannelId();
    _parseChannelDirectory();
    // The sync offset is per-subtitle and session-scoped, but it lives in a
    // process-wide singleton — clear it at the start of every player session so
    // a previous video's offset can't leak in (mirrors the TV side's onCreate).
    SubtitleSettingsService.instance.resetSyncOffset();
    _subtitleSync.loadSubtitleSettings();
    unawaited(_completion.loadTrackingPolicy());
    unawaited(_skip.loadSkipSegmentSettings());
    unawaited(_completion.loadLocalCompletionThresholds());
    VideoPlayerScreenTestHooks._ensureInitialized();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // The player opens landscape — a video wants the long edge — unless the
    // user asked it to open upright, in which case the Portrait/Landscape
    // button is how they turn it. Read from the SYNCHRONOUS cache: setting
    // landscape here and correcting it once an async read lands would perform
    // the exact flip the setting exists to prevent.
    _display.landscapeLocked = !_startsInPortrait;
    SystemChrome.setPreferredOrientations(
      _display.landscapeLocked
          ? const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const <DeviceOrientation>[DeviceOrientation.portraitUp],
    );
    // Held for the LOADING phase only — a slow debrid resolve must not let
    // the screen sleep before the first frame. From the first playing event
    // onward the lock follows play/pause (see _syncWakelock).
    unawaited(PlayerDisplayControls.instance.setWakelock(true));
    if (Platform.isWindows || Platform.isLinux) {
      windowManager.setFullScreen(true);
    }
    // System volume UI not modified

    // Initialize the player asynchronously
    _playerInitializationFuture = _initializePlayer();

    // Init rainbow animation
    _rainbowController = AnimationController(
      vsync: this,
      duration: VideoPlayerTimingConstants.rainbowAnimationDuration,
    );
    _rainbowOpacity = CurvedAnimation(
      parent: _rainbowController,
      curve: Curves.easeInOut,
    );

    // Check if Trakt scrobbling should be enabled for this playback
    _trakt.initTraktScrobble();
    _simkl.initSimklScrobble();
    _mdblist.initMdblistScrobble();
  }

  /// The position trackers and stores may persist: the live position, unless
  /// a requested resume never landed — then the HELD target. The live value in
  /// that window describes a stream that restarted at the beginning, and
  /// scrobbling it would reset every tracker's REMOTE resume point to ~0:
  /// invisible on this device (local kept the bookmark) but lost on every
  /// other one, since resume takes the furthest of local and tracker.
  Duration get _persistablePosition {
    final heldMs = _resumeWriteGuard.heldTargetIfBlocked(
      _position.inMilliseconds,
    );
    if (heldMs == null) return _position;
    // The target was <80% of the duration AT ARM TIME, but _duration mirrors
    // mpv live and can transiently read short on a fresh remote stream —
    // against which the held target could compute as >80% or >100% progress,
    // turning a tracker start/pause into a stop (a watched mark for content
    // playing at 0:00). Same rule as _saveResume's short-duration skip: fall
    // back to the raw position for the few seconds the reading is off. A raw
    // ~0 start-scrobble in that window is the pre-guard behavior, not a new
    // harm.
    final durMs = _duration.inMilliseconds;
    if (durMs <= 0 || heldMs >= (durMs * 0.8).floor()) return _position;
    return Duration(milliseconds: heldMs);
  }

  /// Resolve season/episode: prefer current playlist entry (tracks auto-advance),
  /// fall back to launch args, then filename parsing.
  ({int? season, int? episode}) _traktSeasonEpisode() {
    // Movies never have season/episode — avoid filename false positives (e.g. "5.1" surround)
    if (widget.contentType == 'movie') {
      return (season: null, episode: null);
    }
    // Prefer current playlist entry — correct even after auto-advance
    if (_activePlaylist != null &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      final info = SeriesParser.parseFilename(
        _activePlaylist![_currentIndex].title,
      );
      if (info.season != null && info.episode != null) {
        return (season: info.season, episode: info.episode);
      }
    }
    // Fallback: explicit launch args (single-stream series playback)
    if (widget.contentSeason != null && widget.contentEpisode != null) {
      return (season: widget.contentSeason, episode: widget.contentEpisode);
    }
    final info = SeriesParser.parseFilename(widget.title);
    return (season: info.season, episode: info.episode);
  }

  /// Periodic analytics ping so a long, interaction-free watch keeps the
  /// analytics session alive. Independent of Trakt (fires regardless of Trakt
  /// auth); only emits while actually playing. No content details are sent.
  void _startAnalyticsHeartbeat() {
    _analyticsHeartbeatTimer?.cancel();
    _analyticsHeartbeatTimer = Timer.periodic(
      AnalyticsService.heartbeatInterval,
      (_) {
        if (_isPlaying) {
          AnalyticsService.playbackHeartbeat('dart');
        }
      },
    );
  }

  void _resumeTrackingAfterValidationGate() {
    if (!mounted || _validationGateActive) return;
    _mdblist.updateMdblistPosition();
    if (!_isPlaying || _duration <= Duration.zero) return;
    _trakt.traktScrobble('start');
    if (_trakt.traktLastScrobbleAction == 'start') _trakt.startTraktHeartbeat();
    if (_simkl.simklScrobbleEnabled) {
      // Simkl uses a local playing marker and pause-based checkpoints; sending
      // its remote "start" would erase the resumable playback entry.
      _simkl.simklLastScrobbleAction = 'start';
      _simkl.startSimklHeartbeat();
    }
    _mdblist.mdblistPlay();
  }

  /// The current episode's cross-device Trakt progress percent (0-100), or null.
  /// Loaded once per series from the dedicated store (kept apart from the
  /// ms-based resume state) and looked up by the current episode's season/episode.
  void _bindEpisodeTrackerProgressIdentity(String imdbId) {
    if (_episodeTrackerProgressImdbId == imdbId) return;
    _episodeTrackerProgressImdbId = imdbId;
    _trakt.traktEpisodeProgress = null;
    _simkl.simklEpisodeProgress = null;
    _mdblist.mdblistEpisodeProgress = null;
  }

  /// Load an external audio track to play alongside a video-only stream
  /// (high-res YouTube serves video and audio separately). Uses media_kit's
  /// AudioTrack.uri (mpv `audio-add`), which is URL-safe — unlike the
  /// `audio-files` path-list option, which mangles URLs on the `:`/`,`
  /// separators. Must be called AFTER the main media has loaded.
  Future<void> _setExternalAudioTrack(String audioUrl) async {
    try {
      await _player.setAudioTrack(mk.AudioTrack.uri(audioUrl));
    } catch (e) {
      debugPrint('VideoPlayer: failed to set external audio track: $e');
    }
  }

  /// Put Android audio on an effects-capable output and announce the session,
  /// so system effect apps (Wavelet, OEM equalizers, hearing-accessibility
  /// tools) can process our playback like they do for other video apps.
  ///
  /// Two separate things block that by default:
  ///
  ///  1. media_kit pins Android to `ao=opensles`, and mpv's OpenSL ES output
  ///     never sets SL_ANDROID_KEY_PERFORMANCE_MODE — so Android applies its
  ///     default low-latency path, which is documented to carry *no* hardware
  ///     or software effects. Nothing can attach to our audio at all, which is
  ///     why even a global/"legacy mode" equalizer has no effect on us.
  ///     `audiotrack` is an ordinary AudioTrack and is effects-capable; the
  ///     `opensles` fallback keeps today's behaviour on any device where
  ///     AudioTrack fails to initialise, so audio can't be lost outright.
  ///  2. Effect apps attach to a session id learned from the standard OPEN
  ///     broadcast. mpv generates an id internally and tells nobody, so we pin
  ///     our own via `audiotrack-session-id` and announce that.
  ///
  /// Fails soft at every step: effects are a nice-to-have, playback is not.
  /// Opt-in (Settings → Player Settings): switching the audio backend is a real
  /// change to how every device outputs sound, so off must leave playback byte
  /// for byte as it was.
  Future<void> _attachAudioEffectSession() async {
    if (!Platform.isAndroid) return;
    // Everything below is inside the catch: _initializePlayer() runs
    // unawaited, so anything that escapes here would abort the rest of init
    // and leave a black screen — including for users who have this turned off,
    // since the settings read itself happens either way.
    try {
      final platform = _player.platform;
      if (platform is! mk.NativePlayer) return;
      // The CACHED field, deliberately: [_configurePlayerAudio] chose the
      // audio output from it, and a fresh preference read here could
      // diverge mid-session — announcing a session on an output that was
      // never switched, or vice versa. "Restart playback to apply" is the
      // settings contract for both halves.
      if (!_systemAudioEffectsEnabled) return;
      // `ao=audiotrack,...` itself is owned by [_configurePlayerAudio] now
      // (the passthrough setting needs the same output, and two writers of
      // `ao` is how the two settings would fight) — this method keeps only
      // the session-id half.
      final sessionId = await AudioEffectSessionService.generateSessionId();
      // No id available: still worth keeping the effects-capable output, since
      // effect apps that detect sessions on their own can then attach.
      if (sessionId == null) return;
      await platform.setProperty('audiotrack-session-id', '$sessionId');
      await AudioEffectSessionService.open(sessionId);
      _audioEffectSessionId = sessionId;
    } catch (e) {
      debugPrint('VideoPlayer: audio effect session setup failed: $e');
    }
  }

  /// Release the announced audio session. Unpaired OPENs leave effect apps
  /// attached to dead audio and degrade *other* apps' equalizers, so this must
  /// run on every exit from the player.
  void _releaseAudioEffectSession() {
    final sessionId = _audioEffectSessionId;
    if (sessionId == null) return;
    _audioEffectSessionId = null;
    AudioEffectSessionService.close(sessionId);
  }

  /// This player's claim on the process's one video output.
  ///
  /// HELD for the controller's lifetime rather than taken as a momentary
  /// barrier. A barrier that released before construction left a gap: a trailer
  /// parked on the lease would be granted it and build its own output while
  /// this player was still constructing — the two-output case, which is a
  /// SIGABRT on tvOS.
  VideoOutputLeaseHandle? _outputLease;

  /// Take the slot before building a controller.
  ///
  /// The ambient trailer surfaces tear down when playback launches, but the
  /// native release is asynchronous — "teardown was requested" is not "the
  /// output is gone".
  ///
  /// **Bounded, deliberately.** Review pushed back on this twice: a timeout
  /// that proceeds can, in principle, recreate the two-output case. The
  /// judgement here is that an unbounded wait turns a stuck native disposal
  /// into "video never plays again this session", which is a worse and far more
  /// likely outcome than the crash it guards against — and by the time three
  /// seconds have passed, something is already wrong. It logs, and it still
  /// takes the slot when it finally frees, so the player never ends up
  /// untracked.
  ///
  /// tvOS waits longer before giving up: proceeding into the overlap is a
  /// certain SIGABRT there, and since the native Dispose handshake became
  /// completion-gated (mpv render context freed before the channel call
  /// returns) a held lease reliably frees — a slow release is a wait, not a
  /// lockout.
  static final Duration _outputLeaseTimeout = PlatformUtil.isTvOS
      ? const Duration(seconds: 10)
      : const Duration(seconds: 3);

  Future<void> _claimVideoOutput() async {
    if (_outputLease != null) return; // renderer fallback reuses the claim
    if (!VideoOutputLease.isHeld) {
      final handle = await VideoOutputLease.acquire(debugLabel: 'player');
      if (_screenDisposed) {
        handle.release();
        return;
      }
      _outputLease = handle;
      return;
    }
    final pending = VideoOutputLease.acquire(debugLabel: 'player');
    VideoOutputLeaseHandle? handle;
    try {
      handle = await pending.timeout(_outputLeaseTimeout);
    } on TimeoutException {
      debugPrint(
        'VideoOutputLease: player proceeding without the slot — a previous '
        'video output has not released after '
        '${_outputLeaseTimeout.inSeconds}s.',
      );
      // The wait was abandoned, not cancelled. Take the slot whenever it does
      // arrive rather than handing it back: this player IS alive and holding a
      // video output, so releasing would leave it untracked and let a trailer
      // build a second one beside it.
      unawaited(
        pending.then((late) {
          if (_screenDisposed || _outputLease != null) {
            late.release();
          } else {
            _outputLease = late;
          }
        }),
      );
    }
    if (_screenDisposed) {
      handle?.release();
      return;
    }
    _outputLease = handle;
  }

  void _releaseVideoOutput() {
    _outputLease?.release();
    _outputLease = null;
  }

  /// Set once `dispose()` has run, so a claim still in flight at that moment
  /// gives the slot straight back instead of being stranded by the `!mounted`
  /// return at its call site — which would block every future trailer engine
  /// for the rest of the session.
  bool _screenDisposed = false;

  void _createPlayerInstance(AndroidVideoRendererMode rendererMode) {
    final instanceGeneration = ++_playerInstanceGeneration;
    _isReady = false;
    final player = VideoPlayerScreenTestHooks._createPlayer(
      configuration: mk.PlayerConfiguration(
        logLevel: mk.MPVLogLevel.error,
        ready: () => _onPlayerInstanceReady(instanceGeneration),
      ),
    );
    _player = player;
    _playerCreated = true;
    _videoController = VideoPlayerScreenTestHooks._createVideoController(
      player,
      configuration: mkv.VideoControllerConfiguration(
        vo: rendererMode.videoOutput,
        // The tvOS escape hatch outranks the renderer mode (which is an
        // Android concept; its decoder string is null off-Android anyway).
        hwdec: PlatformUtil.isTvOS && _tvosForceSoftwareDecode
            ? 'no'
            : rendererMode.hardwareDecoder,
      ),
    );
    _installTvosDecodeRemedy(player);
    _bindPlayerInstanceSubscriptions(instanceGeneration, player);
    unawaited(_installDecoderObservers(instanceGeneration, player));
    unawaited(_display.applyAspectVideoZoom());
  }

  /// Serializes live passthrough flips: each runs WHOLE, in order. Without
  /// this a rapid double-toggle could interleave two aid cycles and leave
  /// the newer one reading `aid=no` mid-way through the older one's cycle —
  /// stranding the player silent.
  Future<void> _passthroughFlipChain = Future<void>.value();

  /// The in-player passthrough flip — persists the same setting the
  /// Playback Defaults row writes, applies the explicit property values
  /// (including the OFF restores), then cycles the audio track so the
  /// CURRENT file's audio chain re-initialises: `audio-spdif` is read at
  /// decoder init, and `ao` reloads on the reconfig. Sub-second audio gap,
  /// position untouched. Fails soft: playback outlives any of this (and
  /// mpv gives no rejection signal to roll a switch back on — the toggle's
  /// caption owns the "silence means off" contract).
  Future<void> _setAudioPassthroughLive(bool enabled) {
    final flip = _passthroughFlipChain.then(
      (_) => _applyPassthroughFlip(enabled),
    );
    _passthroughFlipChain = flip.catchError((_) {});
    return flip;
  }

  Future<void> _applyPassthroughFlip(bool enabled) async {
    _audioPassthroughEnabled = enabled;
    try {
      await PlayerSettingsStorage.setAudioPassthroughEnabled(enabled);
      // An audio filter would force compressed passthrough formats through a
      // PCM decoder. Remove the passive analysis chain before the aid cycle;
      // when passthrough is disabled, re-arm only after PCM output is restored.
      if (enabled) {
        await _subtitleSync.subtitleAutoSync?.setPassthroughEnabled(true);
      }
      final platform = _player.platform;
      if (platform is! mk.NativePlayer) return;
      for (final (property, value)
          in PlayerAudioConfig.androidLiveToggleProperties(
            passthroughEnabled: enabled,
            systemAudioEffects: _systemAudioEffectsEnabled,
          )) {
        await platform.setProperty(property, value);
      }
      final aid = await platform.getProperty('aid');
      if (aid.isNotEmpty && aid != 'no') {
        await platform.setProperty('aid', 'no');
        await platform.setProperty('aid', aid);
      }
      if (!enabled) {
        await _subtitleSync.subtitleAutoSync?.setPassthroughEnabled(false);
      }
    } catch (e) {
      debugPrint('VideoPlayer: live passthrough toggle failed: $e');
    }
  }

  /// The single owner of the player's audio-output properties — ordered
  /// list from [PlayerAudioConfig], awaited before the first open, run at
  /// EVERY player-instance creation site (initial + the Android renderer
  /// fallback recreate). Fails soft per property: audio configuration is a
  /// nice-to-have, playback is not.
  Future<void> _configurePlayerAudio(mk.Player player) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;
    final props = PlayerAudioConfig.audioProperties(
      isAndroid: !kIsWeb && Platform.isAndroid,
      isApple: PlatformUtil.isTvOS || PlatformUtil.isIosMobile,
      isTvOS: PlatformUtil.isTvOS,
      routeOutputChannels: _tvosRouteOutputChannels,
      tvosForceStereo: _tvosForceStereoAudio,
      tvosLegacyAudioOutput: _tvosLegacyAudioOutput,
      passthroughEnabled: _audioPassthroughEnabled,
      systemAudioEffects: _systemAudioEffectsEnabled,
      multichannelEnabled: _appleMultichannelEnabled,
    );
    for (final (property, value) in props) {
      try {
        await platform.setProperty(property, value);
      } catch (e) {
        debugPrint('VideoPlayer: audio config $property=$value failed: $e');
      }
    }
    // Preferred audio language, handed to mpv itself as `alang`. The Dart
    // matcher (_applyDefaultAudioLanguage) only runs after the track list
    // reaches Dart and only matches on metadata; mpv applies the preference
    // at stream selection, and its matcher also weighs the default/forced
    // dispositions. Users with no preference set send nothing.
    try {
      final lang = await SubtitleSettingsStorage.getDefaultAudioLanguage();
      if (lang != null && lang.isNotEmpty) {
        final alang = LanguageMapper.alangForCode(lang);
        if (alang.isNotEmpty) await platform.setProperty('alang', alang);
      }
    } catch (e) {
      debugPrint('VideoPlayer: alang config failed: $e');
    }
  }

  /// tvOS only: the 10-bit remedy ladder, bound to THIS player instance's
  /// property interface. Plain post-create property access — deliberately
  /// not `mpv_observe_property` (see the SIGABRT note in
  /// [_installDecoderObservers]); the ladder is driven by the existing
  /// Dart-side videoParams stream instead.
  void _installTvosDecodeRemedy(mk.Player player) {
    if (!PlatformUtil.isTvOS) return;
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;
    _tvosDecodeRemedy?.dispose();
    _tvosDecodeRemedy = TvosDecodeRemedy(
      getProperty: platform.getProperty,
      setProperty: platform.setProperty,
      // The standard 8-bit-surface pin, applied before every file's decoder
      // exists: 8-bit content is NV12 already (no change), 10-bit decodes
      // straight to NV12 with no blue flash and no mid-play cycle. The
      // reactive ladder underneath only ever engages if VideoToolbox
      // rejects the pin for some exotic stream.
      pinNv12FromStart: true,
      // A settle is a decode-path change the one-shot probe has already
      // reported around — re-arm it so the diagnostic line carries the
      // remedy journey.
      onStateChanged: () {
        if (mounted) _scheduleDecoderProbe();
      },
    );
  }

  void _onPlayerInstanceReady(int instanceGeneration) {
    if (!mounted || instanceGeneration != _playerInstanceGeneration) return;
    _isReady = true;
    _pip.armPipAutoEnter();
    if (PlatformUtil.isTelevision && _controlsVisible.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Never while a guide/sheet is up: on tvOS IPTV the instance becomes
        // ready SECONDS after a zap (and again on remedy-ladder restarts), so
        // this fired after the sheet's one-shot focus claim and silently
        // yanked the remote off it — the guide's focus went dead at random.
        if (mounted &&
            instanceGeneration == _playerInstanceGeneration &&
            _controlsVisible.value &&
            !_anyPlayerOverlayOpen &&
            !_tvBarScope.hasFocus) {
          _tvPlayPauseFocus.requestFocus();
        }
      });
    }
    setState(() {});

    // These are screen-presentation side effects, not player-instance setup.
    // Re-running them during the compatibility restart would re-raise launch
    // banners and reset guide context while preserving the same media item.
    if (_playerPresentationInitialized) return;
    _playerPresentationInitialized = true;
    final iptvChannel = _currentIptvChannel;
    if (iptvChannel != null && iptvChannel.isLive) {
      _hideTimer?.cancel();
      _controlsVisible.value = false;
      _iptvBanner.prepareIptvBannerData(iptvChannel);
      _iptvBanner.raiseIptvZapBanner();
      _iptvGuide.anchorIptvGuideCategory(iptvChannel);
      _zapRing.ensureIptvZapPagingArmed();
    } else {
      _raiseDebrifyBanner();
    }
  }

  Future<void> _initializePlayer() async {
    // Load default player settings
    await _loadPlayerDefaults();
    unawaited(_loadDockPrefs());
    if (VpS2Hooks.isAndroid && !PlatformUtil.isAndroidTvCached) {
      _androidVideoRendererMode =
          await PlayerSettingsStorage.getAndroidVideoRendererMode();
    }

    // Determine the initial URL and index
    String initialUrl = widget.videoUrl;
    var initialRankedAttemptFailed = false;
    int initialIndex = 0;

    if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
      // Initialize playlist

      // If auto-resume is disabled, use startIndex directly
      if (widget.disableAutoResume) {
        initialIndex = widget.startIndex ?? 0;
        debugPrint(
          'VideoPlayer: auto-resume disabled, using startIndex=$initialIndex',
        );
      } else {
        // Check if this is a series and we should find the first episode by season/episode
        final seriesPlaylist = _seriesPlaylist;
        if (seriesPlaylist != null && seriesPlaylist.isSeries) {
          // If a specific target episode was requested (e.g. quick play from Trakt),
          // jump directly to it instead of resuming from last played.
          bool targetEpisodeResolved = false;
          final hadExplicitTarget =
              widget.contentSeason != null && widget.contentEpisode != null;
          if (hadExplicitTarget) {
            final targetIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(
              widget.contentSeason!,
              widget.contentEpisode!,
            );
            if (targetIndex != -1) {
              initialIndex = targetIndex;
              targetEpisodeResolved = true;
              debugPrint(
                'VideoPlayer: target episode S${widget.contentSeason}E${widget.contentEpisode} → index=$initialIndex',
              );
            }
          }

          if (!targetEpisodeResolved) {
            // Only resume from the last-played episode when NO specific episode
            // was requested. If a target WAS requested but isn't in this pack
            // (e.g. "Next" with no bound source landed on a source that lacks
            // that episode), resuming would replay the last-played — usually the
            // episode the user just finished — which is the "Next replays the
            // same episode" bug. In that case skip straight to the first episode.
            final lastEpisode = hadExplicitTarget
                ? null
                : await _getLastPlayedEpisode(seriesPlaylist);
            if (lastEpisode != null) {
              debugPrint(
                'VideoPlayer: resume series "${seriesPlaylist.seriesTitle}" at S${lastEpisode['season']}E${lastEpisode['episode']} originalIndex=${lastEpisode['originalIndex']}',
              );
              initialIndex = lastEpisode['originalIndex'] as int;
            } else {
              // Find the first episode (lowest season, lowest episode)
              final firstEpisodeIndex = seriesPlaylist
                  .getFirstEpisodeOriginalIndex();
              if (firstEpisodeIndex != -1) {
                initialIndex = firstEpisodeIndex;
              } else {
                initialIndex = widget.startIndex ?? 0;
              }
              debugPrint(
                'VideoPlayer: no resume target for "${seriesPlaylist.seriesTitle}"'
                '${hadExplicitTarget ? ' (requested S${widget.contentSeason}E${widget.contentEpisode} not in pack)' : ''}, defaulting to index=$initialIndex',
              );
            }
          }
        } else {
          // For non-series playlists, try to restore the last played video
          if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
            // Try to find the last played video by checking each playlist entry
            int lastPlayedIndex = -1;
            Map<String, dynamic>? lastPlayedState;

            for (int i = 0; i < _activePlaylist!.length; i++) {
              final entry = _activePlaylist![i];
              final resumeId = _resumeKeys.resumeIdForEntry(entry);
              debugPrint(
                'Resume: checking entry[$i] title="${entry.title}" resumeId=$resumeId',
              );
              final state = await VideoProgressStorage.getVideoPlaybackState(
                videoTitle: resumeId,
              );
              if (state != null) {
                debugPrint(
                  'Resume: found state for entry[$i] resumeId=$resumeId updatedAt=${state['updatedAt']}',
                );
                final updatedAt = state['updatedAt'] as int? ?? 0;
                if (lastPlayedState == null ||
                    updatedAt > (lastPlayedState['updatedAt'] as int? ?? 0)) {
                  lastPlayedState = state;
                  lastPlayedIndex = i;
                }
              }
            }

            if (lastPlayedIndex != -1) {
              debugPrint('Resume: restoring playlist index $lastPlayedIndex');
              initialIndex = lastPlayedIndex;
            } else {
              debugPrint(
                'Resume: no prior playback state found, using default ordering',
              );
              // Pick the first item from Main group (by year asc then size desc)
              final indices = _getMainGroupIndices(_activePlaylist!);
              initialIndex = indices.isNotEmpty
                  ? indices.first
                  : (widget.startIndex ?? 0);
            }
          } else {
            // Not a series or no series playlist, use the provided startIndex
            initialIndex = widget.startIndex ?? 0;
          }
        }
      }
    } else {}

    // A stale launch index (resume record from a longer pack, negative
    // startIndex) must not reach list indexing: _currentIndex is used
    // unconditionally below and in later playback paths.
    if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
      initialIndex = initialIndex.clamp(0, _activePlaylist!.length - 1);
    }

    // Get the initial URL from the determined index
    if (_activePlaylist != null &&
        _activePlaylist!.isNotEmpty &&
        initialIndex < _activePlaylist!.length) {
      final entry = _activePlaylist![initialIndex];
      if (entry.url.isNotEmpty) {
        initialUrl = entry.url;
      } else {
        try {
          final resolvedUrl = await _resolvePlaylistEntryUrl(initialIndex);
          if (resolvedUrl.isNotEmpty) {
            initialUrl = resolvedUrl;
          } else if (widget.videoUrl.isNotEmpty) {
            initialUrl = widget.videoUrl;
          } else {
            initialRankedAttemptFailed = true;
          }
        } catch (e) {
          // Only fall back to widget.videoUrl if resolution fails
          if (widget.videoUrl.isNotEmpty) {
            initialUrl = widget.videoUrl;
          } else {
            initialRankedAttemptFailed = true;
          }
        }
      }
    }

    _currentIndex = initialIndex;
    _dynamicTitle = widget.title;
    await _claimVideoOutput();
    if (!mounted) return;
    _createPlayerInstance(_androidVideoRendererMode);
    await _configurePlayerAudio(_player);
    _subtitleSync.installSubtitleAutoSyncForPlayer(_player);
    // libmpv exposes `stream-record`; the web backend does not. Gate the
    // record control on having a native player — and, on Android, on the
    // finished file being publishable at all. Below API 29 there is no
    // MediaStore.Downloads and no WRITE_EXTERNAL_STORAGE, so a recording
    // could only sit in app-private storage the user can't reach — offering
    // the button would just be a way to lose footage.
    //
    // Deny-by-default: Android starts unsupported and flips true only on a
    // positive probe. The opposite order would leave a rebuild window where
    // an API 21–28 device shows Record, and a tap in that window starts a
    // recording whose Stop button the probe then hides.
    final nativeBackend = _player.platform is mk.NativePlayer;
    // A profile without the recordings feature never sees Record — the
    // platform probe below must not be able to flip it back on.
    final recordingsAllowed = ProfilePolicyGuard.allowsSync(
      ProfileFeature.recordings,
    );
    _recordingSupported =
        recordingsAllowed && nativeBackend && !Platform.isAndroid;
    if (recordingsAllowed && nativeBackend && Platform.isAndroid) {
      unawaited(
        AndroidNativeDownloader.canPublishRecordings().then((canPublish) {
          if (!canPublish || !mounted) return;
          setState(() => _recordingSupported = true);
        }),
      );
      // Engine flag + any capture of this channel already running (a recording
      // started in an earlier player session survives into this one).
      unawaited(
        LiveRecordingService.engineEnabled().then((on) {
          if (!mounted) return;
          _engineFlagOn = on || ProfileRuntime.isProfileCommitted;
          if (_engineFlagOn)
            unawaited(_recording.refreshEngineRecordingState());
        }),
      );
    }

    // Must happen before the first open() — mpv reads both audio options when
    // it creates the audio output, which is on first playback.
    await _attachAudioEffectSession();

    _currentStreamUrl = initialUrl.isNotEmpty ? initialUrl : null;
    if (_activePlaylist != null &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      _activeHttpHeaders =
          _activePlaylist![_currentIndex].httpHeaders ?? widget.httpHeaders;
    }

    // IPTV launch: the first tune starts here, before either open branch
    // below (IPTV is never PikPak). Zaps re-arm this in _switchToIptvChannel.
    var launchIsLiveIptv = false;
    final launchIptvChannels = _effectiveIptvChannels;
    if (launchIptvChannels != null && initialUrl.isNotEmpty) {
      final launchIdx = widget.iptvStartIndex ?? 0;
      final launchChannel =
          (launchIdx >= 0 && launchIdx < launchIptvChannels.length)
          ? launchIptvChannels[launchIdx]
          : null;
      _iptvDiag.onTuneStart(
        launchChannel?.name,
        initialUrl,
        isLive: launchChannel?.isLive ?? true,
      );
      _iptvLiveRecovery.onTuneStarted();
      launchIsLiveIptv = launchChannel?.isLive ?? true;
    }

    final canAttemptRankedStartup =
        initialRankedAttemptFailed &&
        (_effectiveContentType == 'movie' ||
            _effectiveContentType == 'series') &&
        _effectiveSources?.isNotEmpty == true;

    // An empty initial URL caused by a failed lazy resolution is itself the
    // first failed candidate. Enter the ranked ladder so remaining sources
    // still get their configured attempts.
    if (initialUrl.isNotEmpty || canAttemptRankedStartup) {
      // For PikPak videos from playlist or any PikPak URL, use cold storage retry logic
      final currentEntry = _activePlaylist?[_currentIndex];
      final isPikPak =
          currentEntry?.provider?.toLowerCase() == 'pikpak' ||
          currentEntry?.pikpakFileId != null;
      // For non-playlist flows (Debrify TV, Stremio TV, etc.), detect PikPak by URL
      final isPikPakUrl =
          _activePlaylist == null && initialUrl.contains('mypikpak.com');
      final isDebrifyTV = isPikPakUrl && widget.requestMagicNext != null;

      if (initialUrl.isNotEmpty &&
          ((isPikPak && _activePlaylist != null) || isPikPakUrl)) {
        // The continuation can sleep up to 10s in _waitForVideoReady; the
        // screen may be left (player disposed) or the player replaced by a
        // renderer fallback in that window, so it must re-check before every
        // touch of _player.
        final pikpakGeneration = _playerInstanceGeneration;
        bool pikpakStillCurrent() =>
            mounted &&
            !_screenDisposed &&
            pikpakGeneration == _playerInstanceGeneration;
        final launchSource =
            _effectiveSources != null &&
                _currentSourceIndex >= 0 &&
                _currentSourceIndex < _effectiveSources!.length
            ? _effectiveSources![_currentSourceIndex]
            : null;
        _playPikPakVideoWithRetry(initialUrl, isDebrifyTV: isDebrifyTV).then((
          loaded,
        ) async {
          if (!pikpakStillCurrent()) return;
          if (!loaded) return;
          // PikPak uses its own cold-storage readiness gate instead of the
          // ranked VOD gate. Report the winner only after that gate confirms
          // duration, otherwise a queued-but-unplayable file would be pinned.
          unawaited(_commitValidatedStremioSource(launchSource));
          // Wait for the video to load and duration to be available
          await _waitForVideoReady();
          if (!pikpakStillCurrent()) return;
          // Random start takes precedence over resume, then startAtPercent.
          // Same initial-open shape as the ranked branch below — and PikPak
          // cold-storage streams are the slowest remote opens in the app, the
          // likeliest to answer the startup seek with a restart at 0 — so the
          // same guarded, landing-verified seeks apply.
          if (widget.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              // A random start has no bookmark to protect — plain seek.
              await _player.seek(offset);
            } else {
              await _resumeRestore.maybeRestoreResume(verifyLanding: true);
            }
          } else if (widget.startAtPercent != null) {
            final offset = _percentStartOffset(_duration);
            if (offset != null) {
              await _resumeRestore.seekForResume(
                offset.inMilliseconds,
                verifyLanding: true,
              );
            }
          } else {
            await _resumeRestore.maybeRestoreResume(verifyLanding: true);
          }
          if (!pikpakStillCurrent()) return;
          // Restore audio and subtitle track preferences
          await _trackPreferences.restoreTrackPreferences();
        });
      } else {
        // High-res YouTube serves video and audio as separate streams. Open
        // PAUSED, attach the external audio track, then start — so both tracks
        // are loaded before the first frame and play in sync from the start.
        // (Attaching audio mid-playback makes mpv resync, causing a few seconds
        // of A/V drift.)
        final hasExternalAudio =
            widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
        final isStremioTv = _effectiveStremioTvChannels?.isNotEmpty == true;
        final deferStremioTvStart =
            isStremioTv && initialUrl.isNotEmpty && !widget.startFromRandom;
        var directOpenCompleted = false;
        int? directOpenEpoch;
        try {
          final opened = await StartupStreamPolicy.openInitialMedia(
            hasResolvedUrl: initialUrl.isNotEmpty,
            hasExternalAudio: hasExternalAudio,
            isLiveIptv: launchIsLiveIptv,
            // Stremio TV owns channel selection and slot changes. As on native
            // TV, a slow channel must not hit the VOD gate's one-attempt limit.
            isStremioTv: isStremioTv,
            openDirect: () async {
              final opening = _openMedia(
                mk.Media(initialUrl, httpHeaders: _activeHttpHeaders),
                play: !hasExternalAudio,
                desiredPlay: true,
                liveStream: launchIsLiveIptv,
                // Subscribe before open: media-kit reports failures later.
                beforeOpen: isStremioTv
                    ? () {
                        _watchStremioTvStartup(initialUrl);
                        if (deferStremioTvStart) {
                          _stremioTvStartupSeek.arm(
                            widget.startAtPercent,
                            epoch: _resumeVerifyEpoch,
                          );
                        }
                        return true;
                      }
                    : null,
              );
              directOpenEpoch = _resumeVerifyEpoch;
              await opening;
              directOpenCompleted = true;
            },
            openValidated: () => _openInitialVodWithFailover(
              initialUrl,
              httpHeaders: _activeHttpHeaders,
              initialAttemptAlreadyFailed: initialRankedAttemptFailed,
            ),
          );
          if (!opened) {
            await _reportStartupFailure();
            return;
          }
          // Wait for duration-dependent resume and random-start calculations.
          await _waitForVideoReady();
          if (!mounted ||
              _screenDisposed ||
              (isStremioTv && _stremioTvStartupWatch?.hasFailed == true)) {
            return;
          }
          if (hasExternalAudio) {
            await _setExternalAudioTrack(widget.audioUrl!);
          }
          // Random start takes precedence over resume, then startAtPercent.
          if (widget.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              // A random start has no bookmark to protect and no "correct"
              // position to verify against — plain seek, as before.
              await _player.seek(offset);
            } else {
              await _resumeRestore.maybeRestoreResume(verifyLanding: true);
            }
          } else if (widget.startAtPercent != null) {
            final offset = deferStremioTvStart
                ? null
                : _percentStartOffset(_duration);
            if (offset != null) {
              // An explicit promised start position, exposed to the same
              // startup seek failure as a stored resume.
              await _resumeRestore.seekForResume(
                offset.inMilliseconds,
                verifyLanding: true,
              );
            }
          } else {
            await _resumeRestore.maybeRestoreResume(verifyLanding: true);
          }
          _scheduleAutoHide();
          await _trackPreferences.restoreTrackPreferences();
          if (hasExternalAudio) await _player.play();
          // The candidate is now decoded, resume has been applied, and track
          // restoration is complete. Only now may progress escape to local
          // completion or remote scrobblers.
          _setStartupGateActive(false);
          _resumeTrackingAfterValidationGate();
        } catch (e) {
          if (isStremioTv &&
              !directOpenCompleted &&
              directOpenEpoch == _resumeVerifyEpoch) {
            final watch = _stremioTvStartupWatch;
            if (watch != null) {
              watch.fail();
            } else {
              await _reportStartupFailure(
                isCurrent: () => directOpenEpoch == _resumeVerifyEpoch,
              );
            }
          }
          _setStartupGateActive(false);
          // A late throw (seek/track restore) can land after a successful
          // open — playback proceeds, so re-arm tracking or the start
          // scrobble stays swallowed until the next play/pause transition.
          _resumeTrackingAfterValidationGate();
          debugPrint('VideoPlayer: initial open failed: $e');
        }
      }
    } else {
      // If no valid URL, try to load the first playlist entry
      if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
        _loadPlaylistIndex(_currentIndex, autoplay: false);
      }
    }
    _autosaveTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _resumeSave.saveResume(debounced: true),
    );

    // Preload episode information if this is a series
    _episodeMetadataReady ??= _preloadEpisodeInfo();
  }

  void _watchStremioTvStartup(String url) {
    _stremioTvStartupWatch?.dispose();
    final epoch = _resumeVerifyEpoch;
    final instance = _playerInstanceGeneration;
    final mediaGeneration = _decoderProbeGeneration;
    final sources = _effectiveSources;
    final source =
        sources != null &&
            _currentSourceIndex >= 0 &&
            _currentSourceIndex < sources.length
        ? sources[_currentSourceIndex]
        : null;
    final sourceName = [
      source?.source,
      source?.addonDisplayName,
      source?.name,
    ].whereType<String>().join(' ');
    final isAioStreams = StartupStreamPolicy.isAioStreams(
      addonId: source?.stremioAddonId,
      sourceName: sourceName,
      url: url,
    );
    bool isCurrent() =>
        mounted &&
        !_screenDisposed &&
        epoch == _resumeVerifyEpoch &&
        instance == _playerInstanceGeneration;
    _stremioTvStartupWatch = ChannelStartupWatch(
      errors: _player.stream.error,
      widths: _player.stream.width,
      positions: _player.stream.position,
      durations: _player.stream.duration,
      completed: _player.stream.completed,
      addonId: source?.stremioAddonId,
      sourceName: sourceName,
      url: url,
      isCurrent: isCurrent,
      onReady: () {
        if (isCurrent() && isAioStreams) {
          _resumeTrackingAfterValidationGate();
        }
      },
      // Do not depend on which error-stream subscription runs first. The
      // renderer listener owns recoverable output errors; the new backend
      // installs its own watch and can still report an unrecoverable failure.
      shouldDeferError: (error) =>
          AndroidRendererStartupFallback.isRendererFailure(error) &&
          _canFallbackExplicitRenderer(
            instanceGeneration: instance,
            mediaGeneration: mediaGeneration,
          ),
      onFailure: () {
        _stremioTvStartupSeek.cancel();
        unawaited(_reportStartupFailure(isCurrent: isCurrent));
      },
    );
  }

  Future<void> _reportStartupFailure({bool Function()? isCurrent}) async {
    bool current() =>
        mounted && !_screenDisposed && (isCurrent?.call() ?? true);
    if (!current()) return;
    final canRecover = widget.onStartupSourcesExhausted != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          canRecover
              ? 'Saved source failed. Looking for another source…'
              : 'No playable source could be started.',
        ),
      ),
    );
    // A covering dialog may leave later. Only close this player route, and
    // abandon the failure if the viewer has since selected different media.
    final playerRoute = ModalRoute.of(context);
    await Future<void>.delayed(Duration(milliseconds: canRecover ? 250 : 900));
    while (current() && playerRoute?.isActive == true) {
      if (playerRoute?.isCurrent == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || !current() || playerRoute?.isCurrent != true) return;
    if (canRecover) {
      Navigator.of(
        context,
      ).pop(<String, dynamic>{'startupSourcesExhausted': true});
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _bindPlayerInstanceSubscriptions(
    int instanceGeneration,
    mk.Player player,
  ) {
    bool isCurrent() =>
        mounted && instanceGeneration == _playerInstanceGeneration;

    _subtitleDiagnosticLogSub = player.stream.log.listen((log) {
      if (!isCurrent()) return;
      final searchable = '${log.prefix} ${log.text}'.toLowerCase();
      if (!searchable.contains('sub') &&
          !searchable.contains('libass') &&
          !searchable.contains('track')) {
        return;
      }
      debugPrint('[SubtitleDiag] mpv[${log.level}] ${log.prefix}: ${log.text}');
      final level = log.level.toLowerCase();
      final subtitleFailure =
          (level == 'error' || level == 'fatal') &&
          (log.prefix.toLowerCase().startsWith('sub') ||
              searchable.contains('subtitle decoder') ||
              searchable.contains('subtitle converter'));
      final attempt = _activeSubtitleApplyAttempt;
      if (subtitleFailure && attempt != null) {
        unawaited(_subtitleApply.handleSubtitleApplyFailure(attempt, log.text));
      }
    });
    // Subscribe before open() so fast local media and immediate renderer
    // failures are visible to both diagnostics and the startup guard.
    _paramsSub = player.stream.videoParams.listen((params) {
      if (!isCurrent()) return;
      // First sized params ≈ first decoded frame — close enough for the
      // zap-speed number, and it avoids one more subscription slot.
      if ((params.w ?? 0) > 0) {
        _iptvDiag.onFirstFrame();
        _iptvLiveRecovery.onFirstFrame();
      }
      _handleDecoderProbeParams(params);
    });
    _rendererStartupErrorSub = player.stream.error.listen((error) {
      final source = _openedWatchSource;
      if (isCurrent() && source != null) {
        // mpv errors can contain credential-bearing URLs; record only category.
        logSourceSelection(
          'media_server_player_error',
          source: source,
          player: 'mpv',
          reason: mediaServerPlayerErrorCategory(error),
        );
      }
      // mpv also emits nonfatal decoder/stream log errors here. Re-evaluate
      // actual state; healthy playback may not emit another state event.
      if (isCurrent()) {
        PlayerVisibility.playbackState(
          this,
          ready: player.state.playing && !player.state.buffering,
        );
      }
      if (!isCurrent() ||
          !AndroidRendererStartupFallback.isRendererFailure(error)) {
        return;
      }
      unawaited(
        _fallbackExplicitRendererToAutomatic(
          instanceGeneration: instanceGeneration,
          mediaGeneration: _decoderProbeGeneration,
          reason: 'renderer_error',
        ),
      );
    });
    _posSub = player.stream.position.listen((d) {
      if (!isCurrent()) return;
      if (VpS2Hooks.isIOS && d.inSeconds != _pip.lastIosPipPositionSecond) {
        _pip.lastIosPipPositionSecond = d.inSeconds;
        _pip.pushPipState();
      }
      _subtitleSync.subtitleAutoSync?.observePosition(d.inMilliseconds);
      _iptvDiag.onProgress(d, playing: _isPlaying);
      // _isPlaying tracks mpv's pause property: a cache-stall keeps it true
      // (stall detector armed), a user pause flips it false (excluded).
      if (_effectiveIptvChannels != null) {
        _iptvLiveRecovery.onProgress(d, wantsPlayback: _isPlaying);
      }
      _position = d;
      _resumeSave.observeServerWatch();
      _prepareNextDirectEpisode();
      _mdblist.updateMdblistPosition();
      _playbackUiClock.updatePosition(d);
      _skip.syncSkipSegmentsForCurrentContent();
      _skip.syncActiveSkipSegmentUi();
      _completion.checkAndApplyLocalCompletion();
    });
    if (_subtitleSync.subtitleAutoSyncEnabled || _hasSubtitlePolicy) {
      var lastAudioTrackId = player.state.track.audio.id;
      var lastAudioLanguage = player.state.track.audio.language;
      _trackSub = player.stream.track.listen((track) {
        if (!isCurrent()) return;
        final audioTrackId = track.audio.id;
        if (audioTrackId != lastAudioTrackId ||
            track.audio.language != lastAudioLanguage) {
          lastAudioTrackId = audioTrackId;
          lastAudioLanguage = track.audio.language;
          unawaited(_subtitleLanguage.refreshSubtitleAudioPolicy());
          _subtitleSync.subtitleAutoSync?.audioTrackChanged();
        }
      });
    }
    _durSub = player.stream.duration.listen((d) {
      if (!isCurrent()) return;
      final hadDuration = _duration > Duration.zero;
      _duration = d;
      final startupOffset = _stremioTvStartupSeek.take(
        d,
        epoch: _resumeVerifyEpoch,
      );
      if (startupOffset != null) {
        unawaited(
          _resumeRestore
              .seekForResume(startupOffset.inMilliseconds, verifyLanding: true)
              .catchError((Object error) {
                debugPrint('Player: Stremio TV startup seek failed: $error');
              }),
        );
      }
      _mdblist.updateMdblistPosition();
      // `playing=true` commonly arrives before libmpv publishes duration. In
      // that ordering the playing listener cannot arm MDBList, and no second
      // playing event is guaranteed. Treat the first usable duration as the
      // missing edge so the initial durable pause checkpoint is sent.
      if (!hadDuration && d > Duration.zero && _isPlaying) {
        _mdblist.mdblistPlay();
      }
      _playbackUiClock.updateDuration(d);
      if (d > Duration.zero) _skip.skipSegmentsMediaReady = true;
      _skip.syncSkipSegmentsForCurrentContent();
      _skip.syncActiveSkipSegmentUi();
      setState(() {});
    });
    _playSub = player.stream.playing.listen((p) {
      if (!isCurrent()) return;
      PlayerVisibility.playbackState(this, ready: p && !player.state.buffering);
      if (p && _pausedByLifecycle && !_isPipActive) {
        unawaited(player.pause());
        return;
      }
      final wasPlaying = _isPlaying;
      _isPlaying = p;
      _resumeSave.observeServerWatch();
      ProfileLockController.instance.setPlaybackActive(p);
      _pip.syncWakelock(p);
      _pip.pushPipState();
      if (p) _iptvMemory.noteLiveChannelPlaying();
      if (!_validationGateActive && p && _duration > Duration.zero) {
        _trakt.traktScrobble('start');
        if (_trakt.traktLastScrobbleAction == 'start') {
          _trakt.startTraktHeartbeat();
        }
      } else if (!_validationGateActive &&
          !p &&
          wasPlaying &&
          !_isTransitioning &&
          _trakt.traktLastScrobbleAction != 'stop') {
        _trakt.traktScrobble('pause');
        _trakt.stopTraktHeartbeat();
      }
      if (!_validationGateActive &&
          _simkl.simklScrobbleEnabled &&
          p &&
          _duration > Duration.zero) {
        _simkl.simklLastScrobbleAction = 'start';
        _simkl.startSimklHeartbeat();
      } else if (!_validationGateActive &&
          !p &&
          wasPlaying &&
          !_isTransitioning &&
          _simkl.simklLastScrobbleAction != 'stop') {
        _simkl.simklScrobble('pause');
        _simkl.stopSimklHeartbeat();
      }
      if (!_validationGateActive && p && _duration > Duration.zero) {
        _mdblist.mdblistPlay();
      } else if (!_validationGateActive &&
          !p &&
          wasPlaying &&
          !_isTransitioning) {
        _mdblist.mdblistPause();
      }
      if (p && _transitionRunning) {
        _transitionStopTimer?.cancel();
        _transitionPhaseTimer?.cancel();
        _transitionPhase = 1;
        _transitionPhase2Started = null;
        debugPrint(
          'Player: Playback started; overlay phase 1 (static) 1500ms.',
        );
        _transitionPhaseTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!isCurrent()) return;
          _transitionPhase = 2;
          _transitionPhase2Started = DateTime.now();
          setState(() {});
          debugPrint('Player: Overlay phase 2 (cinematic bars) 1500ms.');
        });
        _transitionStopTimer = Timer(const Duration(milliseconds: 3000), () {
          if (!isCurrent()) return;
          _rainbowController.stop();
          _transitionRunning = false;
          _rainbowActive = false;
          setState(() {});
          debugPrint('Player: Transition overlay stopped (3s complete).');
        });
      }
      setState(() {});
    });
    _completedSub = player.stream.completed.listen((done) {
      if (done && isCurrent()) {
        PlayerVisibility.playbackState(this, ready: false);
        _iptvDiag.onPlaybackEnded(_position);
        _onPlaybackEnded();
      }
    });
    _bufferingSub = player.stream.buffering.listen((isBuffering) {
      if (isCurrent()) {
        PlayerVisibility.playbackState(
          this,
          ready: !isBuffering && player.state.playing,
        );
      }
      if (isCurrent()) _iptvDiag.onBuffering(isBuffering, _position);
      if (!isCurrent() || !_isReady || _isTransitioning) return;
      if (isBuffering) {
        _bufferingDebounceTimer?.cancel();
        _bufferingDebounceTimer = Timer(
          VideoPlayerTimingConstants.bufferingDebounceDelay,
          () {
            if (isCurrent() &&
                player.state.buffering &&
                _isReady &&
                !_isTransitioning &&
                !_isPikPakRetrying) {
              _showBufferingIndicator.value = true;
            }
          },
        );
      } else {
        _bufferingDebounceTimer?.cancel();
        _showBufferingIndicator.value = false;
      }
    });
    if (_effectiveIptvChannels != null) {
      _iptvErrorSub = player.stream.error.listen((error) {
        if (isCurrent()) _iptvSources.onIptvStreamError(error);
      });
    }
  }

  Future<void> _cancelPlayerInstanceSubscriptions() async {
    final subscriptions = <StreamSubscription?>[
      _posSub,
      _durSub,
      _playSub,
      _paramsSub,
      _trackSub,
      _completedSub,
      _bufferingSub,
      _iptvErrorSub,
      _rendererStartupErrorSub,
      _subtitleDiagnosticLogSub,
    ];
    _posSub = null;
    _durSub = null;
    _playSub = null;
    _paramsSub = null;
    _trackSub = null;
    _completedSub = null;
    _bufferingSub = null;
    _iptvErrorSub = null;
    _rendererStartupErrorSub = null;
    _subtitleDiagnosticLogSub = null;
    for (final subscription in subscriptions) {
      if (subscription == null) continue;
      try {
        await subscription.cancel();
      } catch (_) {
        // A broken listener must not strand the old native player during the
        // compatibility restart.
      }
    }
  }

  int _mediaServerFrameGeneration = -1;

  void _handleDecoderProbeParams(mk.VideoParams params) {
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0) {
      // Player.open() normally resets VideoParams before loading the next item.
      // Treat it as an extra invalidation signal, but do not require it: the
      // app-owned generation started in _openMedia is the session boundary.
      _decoderProbeToken++;
      _decoderProbeTimer?.cancel();
      _decoderProbeTimer = null;
      _decoderProbeParams = null;
      _rendererStartupGuardToken++;
      _rendererStartupValidationGeneration = -1;
      _resetTvosDisplayMatchForMediaBoundary();
      return;
    }
    if (_openedWatchSource != null &&
        _mediaServerFrameGeneration != _decoderProbeGeneration) {
      _mediaServerFrameGeneration = _decoderProbeGeneration;
      logSourceSelection(
        'media_server_first_frame',
        source: _openedWatchSource,
        player: 'mpv',
      );
    }
    _decoderProbeParams = params;
    _scheduleTvosDisplayMatch(params);
    _scheduleDecoderProbe();
    _scheduleRendererStartupValidation();
    final remedy = _tvosDecodeRemedy;
    if (remedy != null) {
      // Only ever STARTS the ladder (from idle, on a triggering format) —
      // the ladder's own transitional events are ignored inside it.
      unawaited(remedy.evaluate(params, _decoderProbeGeneration));
    }
  }

  void _resetTvosDisplayMatchForMediaBoundary() {
    _tvosDisplayMatchToken++;
    _tvosDisplayMatchTimer?.cancel();
    _tvosDisplayMatchTimer = null;
    _lastTvosDisplayMatchSignature = null;
    if (!PlatformUtil.isTvOS || !_contentDisplayMatchMode.requestsMatching) {
      return;
    }
    // AVDisplayManager retains criteria until explicitly replaced. Clear the
    // outgoing item's request so content with missing/invalid fps metadata can
    // never inherit the previous refresh rate.
    unawaited(
      TvosDisplayMatchService.clear().catchError((Object error) {
        debugPrint('DisplayMatch: tvOS boundary clear failed: $error');
      }),
    );
  }

  void _scheduleTvosDisplayMatch(mk.VideoParams params) {
    if (!PlatformUtil.isTvOS || !_contentDisplayMatchMode.requestsMatching) {
      return;
    }
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0) return;
    final token = ++_tvosDisplayMatchToken;
    _tvosDisplayMatchTimer?.cancel();
    _tvosDisplayMatchTimer = Timer(const Duration(milliseconds: 200), () async {
      if (_screenDisposed || token != _tvosDisplayMatchToken) return;
      final platform = _player.platform;
      if (platform is! mk.NativePlayer) return;
      final selectedTrack = _player.state.track.video;
      var fps = selectedTrack.fps;
      if (fps == null || !fps.isFinite || fps <= 0) {
        for (final property in const ['container-fps', 'estimated-vf-fps']) {
          try {
            final candidate = double.tryParse(
              await platform.getProperty(property),
            );
            if (candidate != null && candidate.isFinite && candidate > 0) {
              fps = candidate;
              break;
            }
          } catch (_) {
            // Some containers publish only one of the two fps properties.
          }
        }
      }
      if (_screenDisposed ||
          token != _tvosDisplayMatchToken ||
          fps == null ||
          !fps.isFinite ||
          fps <= 0) {
        return;
      }
      var codec = selectedTrack.codec;
      if (codec == null || codec.isEmpty) {
        try {
          codec = await platform.getProperty('video-codec');
        } catch (_) {
          codec = null;
        }
      }
      if (_screenDisposed || token != _tvosDisplayMatchToken) return;
      final signature =
          '${_contentDisplayMatchMode.storageKey}|$width|$height|${fps.toStringAsFixed(4)}|${codec ?? ''}';
      if (signature == _lastTvosDisplayMatchSignature) return;
      try {
        final status = await TvosDisplayMatchService.apply(
          mode: _contentDisplayMatchMode,
          width: width,
          height: height,
          refreshRate: fps,
          codec: codec,
        );
        if (_screenDisposed || token != _tvosDisplayMatchToken) return;
        _lastTvosDisplayMatchSignature = signature;
        debugPrint(
          'DisplayMatch: tvOS requested ${width}x$height@${fps.toStringAsFixed(3)} '
          'mode=${_contentDisplayMatchMode.storageKey} '
          'enabled=${status['matchingEnabled']}',
        );
      } catch (error) {
        debugPrint('DisplayMatch: tvOS request failed: $error');
      }
    });
  }

  Future<void> _installDecoderObservers(
    int instanceGeneration,
    mk.Player player,
  ) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;

    // ANDROID ONLY, deliberately.
    //
    // These observers exist to feed the Android explicit-renderer fallback
    // (`_scheduleRendererStartupValidation`), which is itself
    // gated on `Platform.isAndroid` — so everywhere else they were pure cost.
    //
    // They are also `mpv_observe_property` calls issued unawaited, at the same
    // moment the video controller is building the native render context on its
    // own worker — which is the window a tvOS SIGABRT was landing in.
    //
    // NOT confirmed as the cause: the crash stopped after this change AND a
    // reinstall that wiped the device's preferences, and either could have
    // done it. Kept regardless, because a probe that only feeds an
    // Android-gated fallback has no business running anywhere else.
    if (!Platform.isAndroid) return;

    try {
      await platform.observeProperty('hwdec-current', (value) async {
        if (mounted && instanceGeneration == _playerInstanceGeneration) {
          _scheduleDecoderProbe();
        }
      });
    } catch (_) {
      // The one-shot query below still works if this property is unavailable.
    }
    try {
      await platform.observeProperty('current-vo', (value) async {
        if (mounted && instanceGeneration == _playerInstanceGeneration) {
          _scheduleDecoderProbe();
        }
      });
    } catch (_) {
      // Keep the independent hwdec observer when only current-vo is unavailable.
    }
  }

  void _scheduleRendererStartupValidation() {
    if (!AndroidRendererStartupFallback.shouldArm(
          isAndroid: Platform.isAndroid,
          isAndroidTv: PlatformUtil.isAndroidTvCached,
          mode: _androidVideoRendererMode,
          alreadyValidated: _rendererValidatedForSession,
          fallbackInProgress: _rendererFallbackInProgress,
        ) ||
        _iptvErrorsMuted ||
        _rendererStartupValidationGeneration == _decoderProbeGeneration) {
      return;
    }
    _rendererStartupValidationGeneration = _decoderProbeGeneration;
    final guardToken = ++_rendererStartupGuardToken;
    final instanceGeneration = _playerInstanceGeneration;
    final mediaGeneration = _decoderProbeGeneration;
    final player = _player;
    unawaited(
      _validateRendererStartup(
        guardToken: guardToken,
        instanceGeneration: instanceGeneration,
        mediaGeneration: mediaGeneration,
        player: player,
      ),
    );
  }

  Future<void> _validateRendererStartup({
    required int guardToken,
    required int instanceGeneration,
    required int mediaGeneration,
    required mk.Player player,
  }) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;

    // VideoParams is already positive at this point, so this is not a network
    // startup timeout. Give Android's SurfaceProducer/codec bridge three seconds
    // to attach the requested output and require two matching reads.
    var previousOutput = '';
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted ||
          guardToken != _rendererStartupGuardToken ||
          instanceGeneration != _playerInstanceGeneration ||
          mediaGeneration != _decoderProbeGeneration) {
        return;
      }
      try {
        final output = await platform.getProperty('current-vo');
        if (AndroidRendererStartupFallback.isExpectedOutput(
              mode: _androidVideoRendererMode,
              value: output,
            ) &&
            output == previousOutput) {
          _rendererValidatedForSession = true;
          _rendererStartupGuardToken++;
          return;
        }
        previousOutput = output;
      } catch (_) {
        // A transient property-query failure gets the remainder of the window.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    await _fallbackExplicitRendererToAutomatic(
      instanceGeneration: instanceGeneration,
      mediaGeneration: mediaGeneration,
      reason: 'requested_output_not_ready',
    );
  }

  bool _canFallbackExplicitRenderer({
    required int instanceGeneration,
    required int mediaGeneration,
  }) =>
      AndroidRendererStartupFallback.shouldArm(
        isAndroid: VpS2Hooks.isAndroid,
        isAndroidTv: PlatformUtil.isAndroidTvCached,
        mode: _androidVideoRendererMode,
        alreadyValidated: _rendererValidatedForSession,
        fallbackInProgress: _rendererFallbackInProgress,
      ) &&
      mounted &&
      instanceGeneration == _playerInstanceGeneration &&
      mediaGeneration == _decoderProbeGeneration &&
      _activeOpenedMedia != null &&
      !_isRecording &&
      !_iptvErrorsMuted &&
      !_isTransitioning;

  Future<void> _fallbackExplicitRendererToAutomatic({
    required int instanceGeneration,
    required int mediaGeneration,
    required String reason,
  }) async {
    if (!_canFallbackExplicitRenderer(
      instanceGeneration: instanceGeneration,
      mediaGeneration: mediaGeneration,
    )) {
      return;
    }

    _rendererFallbackInProgress = true;
    _rendererStartupGuardToken++;
    final startupEpoch = _resumeVerifyEpoch;
    final restartChannelWatch = _stremioTvStartupWatch?.isPending == true;
    int? recoveryOpenEpoch;
    final media = _activeOpenedMedia!;
    final oldPlayer = _player;
    final oldState = oldPlayer.state;
    // A renderer rebuild mid-startup can race an unlanded resume seek: the
    // live position is then a restart artifact, and the rebuilt player must
    // come back at the promised target, not ~0. (Pure query — the guard stays
    // armed for the rebuilt player's own landing.)
    final livePosition = _position > Duration.zero
        ? _position
        : oldState.position;
    final heldMs = _resumeWriteGuard.heldTargetIfBlocked(
      livePosition.inMilliseconds,
    );
    final resumePosition = heldMs != null
        ? Duration(milliseconds: heldMs)
        : livePosition;
    final shouldResumePlayback =
        _activeMediaShouldPlay && !_activeMediaUserPaused && !_sleepStopLatched;
    final rate = oldState.rate;
    final volume = oldState.volume;
    final isLive = _currentIptvChannel?.isLive == true;
    final externalAudio = widget.audioUrl;
    final hasExternalAudio = externalAudio != null && externalAudio.isNotEmpty;

    final failedRenderer = _androidVideoRendererMode.storageKey;
    _releasePlayerDiagnostic(
      'generation=$mediaGeneration phase=fallback '
      'status=renderer_startup_failed platform=android backend=libmpv '
      'requested_renderer=$failedRenderer fallback=automatic reason=$reason',
    );

    // Invalidate every old callback before the first await. Only one native
    // player may own audio and the Android surface during the restart.
    _playerInstanceGeneration++;
    _playerCreated = false;
    _isReady = false;
    _isPlaying = false;
    _showBufferingIndicator.value = false;
    setState(() {});

    try {
      await _cancelPlayerInstanceSubscriptions();
      await _subtitleSync.disposeSubtitleAutoSync();
      _activeExternalSubtitlePath = null;
      _releaseAudioEffectSession();
      try {
        await oldPlayer.pause();
      } catch (_) {}
      try {
        await oldPlayer.dispose();
      } catch (_) {
        // Disposal normally succeeds, but retain ownership if the native
        // backend throws so route teardown can make one final cleanup attempt.
        _playerCreated = true;
        rethrow;
      }
      if (!mounted) return;

      // Remember the compatibility result. The setting now visibly reads
      // Automatic, and choosing an explicit renderer again retries it.
      _androidVideoRendererMode = AndroidVideoRendererMode.automatic;
      try {
        await PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.automatic,
        );
      } catch (_) {
        // Playback can still recover for this session if preferences are full
        // or unavailable.
      }
      if (!mounted) return;

      _duration = Duration.zero;
      _position = Duration.zero;
      await _claimVideoOutput();
      if (!mounted) return;
      _createPlayerInstance(AndroidVideoRendererMode.automatic);
      await _configurePlayerAudio(_player);
      _subtitleSync.installSubtitleAutoSyncForPlayer(_player);
      await _attachAudioEffectSession();
      if (!mounted) return;
      setState(() {});

      final needsPreparation =
          hasExternalAudio || (!isLive && resumePosition > Duration.zero);
      final playOnOpen =
          shouldResumePlayback && !_pausedByLifecycle && !needsPreparation;
      // Navigation during the rebuild wins over this old media's restart.
      if (startupEpoch != _resumeVerifyEpoch) return;
      final reopening = _openMedia(
        media,
        play: playOnOpen,
        desiredPlay: shouldResumePlayback,
        // The recreated player starts with a clean property set — without
        // this a live channel would silently lose its ffmpeg reconnect
        // options at the renderer fallback (codex round 2, finding 16).
        liveStream: isLive,
        preserveStartupEpoch: startupEpoch,
        beforeOpen: restartChannelWatch
            ? () {
                _watchStremioTvStartup(media.uri);
                return true;
              }
            : null,
      );
      recoveryOpenEpoch = _resumeVerifyEpoch;
      await reopening;
      if (needsPreparation) await _waitForVideoReady();
      if (!mounted) return;
      await _player.setRate(rate);
      await _player.setVolume(volume);
      if (hasExternalAudio) {
        await _setExternalAudioTrack(externalAudio);
      }
      if (!isLive && resumePosition > Duration.zero) {
        // Re-ARMS the guard at the carried position: the rebuilt player gets
        // its own protected landing instead of an unguarded raw seek.
        await _resumeRestore.seekForResume(resumePosition.inMilliseconds);
      }
      unawaited(_trackPreferences.restoreTrackPreferences());
      if (shouldResumePlayback && !_pausedByLifecycle && !playOnOpen) {
        await _player.play();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Direct Surface was unavailable. Using Automatic renderer.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      _releasePlayerDiagnostic(
        'generation=$mediaGeneration phase=fallback '
        'status=failed platform=android backend=libmpv '
        'requested_renderer=direct_surface fallback=automatic',
      );
      final failureEpoch = recoveryOpenEpoch ?? startupEpoch;
      if (restartChannelWatch && failureEpoch == _resumeVerifyEpoch) {
        final watch = _stremioTvStartupWatch;
        if (watch?.hasFailed != true) {
          watch?.dispose();
          _stremioTvStartupSeek.cancel();
          unawaited(
            _reportStartupFailure(
              isCurrent: () => failureEpoch == _resumeVerifyEpoch,
            ),
          );
        }
      }
    } finally {
      _rendererFallbackInProgress = false;
    }
  }

  void _scheduleDecoderProbe() {
    final params = _decoderProbeParams;
    if (params == null) return;
    _decoderProbeTimer?.cancel();
    final generation = _decoderProbeGeneration;
    final token = ++_decoderProbeToken;
    _decoderProbeTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(
        _reportActiveVideoDecoder(
          params: params,
          generation: generation,
          token: token,
        ),
      );
    });
  }

  Future<void> _reportActiveVideoDecoder({
    required mk.VideoParams params,
    required int generation,
    required int token,
  }) async {
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) {
      _emitDecoderDiagnosticOnce(
        generation: generation,
        signature: 'web',
        fields:
            'phase=stable status=unavailable platform=web backend=web '
            'reason=no_native_decoder',
      );
      return;
    }

    var decoder = '';
    var codec = '';
    var output = '';
    var previousDecoder = '';
    var previousOutput = '';
    var stable = false;
    // Audio, read on the DEVICE side (AUDIO_FIDELITY_PLAN.md): what the AO
    // actually writes, not what the decoder produced — the gap between the
    // two is the downgrade being diagnosed.
    var aoName = '';
    var audioChannels = '';
    var previousAo = '';
    var previousAudioChannels = '';
    var audioCodec = '';
    var decodedChannels = '';
    var audioFormat = '';

    try {
      // VideoParams means a decoder has produced metadata, not necessarily
      // that the output surface has finished attaching. Require two matching
      // reads so an early `current-vo=null` is never presented as the verdict.
      // Audio joins the match condition but not the readiness one: a
      // video-only file has no AO to wait for, and empty-matches-empty.
      for (var attempt = 0; attempt < 12; attempt++) {
        if (!mounted ||
            generation != _decoderProbeGeneration ||
            token != _decoderProbeToken) {
          return;
        }
        decoder = await platform.getProperty('hwdec-current');
        output = await platform.getProperty('current-vo');
        aoName = await platform.getProperty('current-ao');
        audioChannels = await platform.getProperty(
          'audio-out-params/channel-count',
        );
        final outputReady = output.isNotEmpty && output != 'null';
        final decoderReady = decoder.isNotEmpty;
        if (decoderReady &&
            outputReady &&
            decoder == previousDecoder &&
            output == previousOutput &&
            aoName == previousAo &&
            audioChannels == previousAudioChannels) {
          stable = true;
          break;
        }
        previousDecoder = decoder;
        previousOutput = output;
        previousAo = aoName;
        previousAudioChannels = audioChannels;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted ||
          generation != _decoderProbeGeneration ||
          token != _decoderProbeToken) {
        return;
      }
      codec = await platform.getProperty('video-codec');
      audioCodec = await platform.getProperty('audio-codec-name');
      decodedChannels = await platform.getProperty(
        'audio-params/channel-count',
      );
      audioFormat = await platform.getProperty('audio-out-params/format');
    } catch (_) {
      if (!mounted || generation != _decoderProbeGeneration) return;
      _emitDecoderDiagnosticOnce(
        generation: generation,
        signature: 'error',
        fields:
            'phase=error status=unavailable '
            'platform=${Platform.operatingSystem} reason=property_query_failed',
      );
      return;
    }

    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    final status = decoder == 'no'
        ? 'software'
        : decoder.isEmpty
        ? 'unavailable'
        : 'hardware';
    final normalizedOutput = output.isEmpty || output == 'null'
        ? 'unknown'
        : output;
    final requestedRenderer = Platform.isAndroid
        ? _androidVideoRendererMode.storageKey
        : 'platform_default';
    // The remedy journey (tvOS): what the decoder produced originally, what
    // it produces now, and where the ladder settled. In the signature too —
    // a settle re-arms this probe, and dedupe on the old signature would
    // swallow exactly the report that proves the remedy ran.
    final remedy = _tvosDecodeRemedy;
    final remedyState = switch (remedy?.state) {
      null || TvosRemedyState.none => 'none',
      TvosRemedyState.nv12 => 'nv12',
      TvosRemedyState.software => 'software',
      TvosRemedyState.gaveUp => 'gave_up',
    };
    // confirmed/failed mean the remedy's own settling poll verified the
    // format by DIRECT read — the stream-captured params above can lag
    // behind a settle (no final event is guaranteed after reconfig).
    final remedyOutcome = remedy == null
        ? 'none'
        : remedy.applying
        ? 'pending'
        : switch (remedy.state) {
            TvosRemedyState.none => 'none',
            TvosRemedyState.nv12 || TvosRemedyState.software => 'confirmed',
            TvosRemedyState.gaveUp => 'failed',
          };
    final remedyFields = remedy == null
        ? ''
        : 'pixelformat=${params.pixelformat ?? 'unknown'} '
              'hw_pixelformat=${params.hwPixelformat ?? 'none'} '
              'detected_hw_pixelformat=${remedy.detectedHwPixelformat ?? 'none'} '
              'verified_hw_pixelformat=${remedy.verifiedHwPixelformat ?? 'none'} '
              'gamma=${params.gamma ?? 'unknown'} '
              'primaries=${params.primaries ?? 'unknown'} '
              'remedy=$remedyState remedy_outcome=$remedyOutcome ';
    final signature =
        '$decoder|$normalizedOutput|$codec|${width}x$height|'
        '$remedyState|$remedyOutcome';
    _emitDecoderDiagnosticOnce(
      generation: generation,
      signature: signature,
      fields:
          'phase=${stable ? 'stable' : 'partial'} status=$status '
          'platform=${Platform.operatingSystem} backend=libmpv '
          'codec=${codec.isEmpty ? 'unknown' : codec} '
          'decoder=${decoder.isEmpty ? 'unknown' : decoder} '
          'output=$normalizedOutput '
          '$remedyFields'
          'audio_codec=${audioCodec.isEmpty ? 'none' : audioCodec} '
          'decoded_channels=${decodedChannels.isEmpty ? 'none' : decodedChannels} '
          'audio_channels=${audioChannels.isEmpty ? 'none' : audioChannels} '
          'audio_format=${audioFormat.isEmpty ? 'none' : audioFormat} '
          'ao=${aoName.isEmpty ? 'none' : aoName} '
          'requested_renderer=$requestedRenderer '
          'resolution=${width}x$height',
    );
  }

  void _emitDecoderDiagnosticOnce({
    required int generation,
    required String signature,
    required String fields,
  }) {
    if (generation != _decoderProbeGeneration) return;
    final taggedSignature = '$generation|$signature';
    if (_lastDecoderDiagnosticSignature == taggedSignature) return;
    _lastDecoderDiagnosticSignature = taggedSignature;
    _releasePlayerDiagnostic('generation=$generation $fields');
  }

  void _beginMediaGeneration({int? preserveStartupEpoch}) {
    if (preserveStartupEpoch == null) {
      _stremioTvStartupSeek.cancel();
    } else {
      _stremioTvStartupSeek.carryTo(
        fromEpoch: preserveStartupEpoch,
        toEpoch: _resumeVerifyEpoch,
      );
    }
    _stremioTvStartupWatch?.dispose();
    _stremioTvStartupWatch = null;
    _decoderProbeGeneration++;
    _decoderProbeToken++;
    _rendererStartupGuardToken++;
    _rendererStartupValidationGeneration = -1;
    _decoderProbeTimer?.cancel();
    _decoderProbeTimer = null;
    _decoderProbeParams = null;
    _lastDecoderDiagnosticSignature = null;
    // This is the guaranteed boundary for every playlist item, IPTV zap,
    // startup candidate, and manual source switch. VideoParams normally emits
    // an invalid value too, but display correctness must not depend on it.
    _resetTvosDisplayMatchForMediaBoundary();
    _playbackUiClock.beginMedia();
    _activeSkipSegmentUi.clear();
  }

  /// The user's Network & Buffering presets, loaded once per screen. A
  /// mid-session settings change applies on the next playback — accurate
  /// today because Settings isn't reachable without popping the player; an
  /// in-player settings entry point would have to re-read this.
  NetworkTuning? _networkTuning;

  /// Stock values of exactly the player-global properties [_networkTuning]
  /// has overridden, captured before the first override. A later live open
  /// on the same player (mixed playlist) restores these, so the tuned live
  /// IPTV pipeline can never inherit VOD tuning. Null until tuning has
  /// actually touched the player — the Standard path never populates it and
  /// so never sets a single property.
  Map<String, String>? _networkTuningDefaults;

  /// Serializes tuning applies: a rapid zap starts a newer [_openMedia]
  /// while an older one is suspended mid-capture, and interleaved property
  /// writes could land VOD tuning on the newer open's live stream. Each
  /// apply runs WHOLE, in order, and bails via its generation check when a
  /// newer open owns the player.
  Future<void> _networkTuningChain = Future<void>.value();

  Future<void> _applyNetworkTuning(
    mk.NativePlayer platform,
    NetworkTuning tuning, {
    required bool liveStream,
    required int generation,
  }) {
    return _networkTuningChain = _networkTuningChain.then(
      (_) => _applyNetworkTuningInner(
        platform,
        tuning,
        liveStream: liveStream,
        generation: generation,
      ),
    );
  }

  Future<void> _applyNetworkTuningInner(
    mk.NativePlayer platform,
    NetworkTuning tuning, {
    required bool liveStream,
    required int generation,
  }) async {
    final want = liveStream ? const <String, String>{} : tuning.mpvProperties;
    // Standard (and live-before-any-tuning): nothing was ever applied,
    // nothing to restore — the player is untouched.
    if (want.isEmpty && _networkTuningDefaults == null) return;
    if (generation != _decoderProbeGeneration) return; // superseded in queue
    try {
      if (want.isNotEmpty && _networkTuningDefaults == null) {
        final defaults = <String, String>{};
        for (final key in want.keys) {
          final value = await platform.getProperty(key);
          // The vendored getProperty returns '' instead of throwing when mpv
          // has no value. An empty "default" would silently fail to restore
          // later — refuse to tune rather than capture poison.
          if (value.isEmpty) {
            debugPrint('Player: network tuning skipped — $key unreadable');
            return;
          }
          defaults[key] = value;
        }
        if (generation != _decoderProbeGeneration) return;
        _networkTuningDefaults = defaults;
      }
      for (final entry in _networkTuningDefaults!.entries) {
        if (generation != _decoderProbeGeneration) return;
        await platform.setProperty(entry.key, want[entry.key] ?? entry.value);
      }
    } catch (e) {
      debugPrint('Player: network tuning apply failed: $e');
    }
  }

  Future<void> _openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  }) async {
    if (request?.isCurrent == false) return;
    final watchEpoch = ++_watchOpenEpoch;
    final sources = _effectiveSources;
    final indexedSource =
        sources != null &&
            _currentSourceIndex >= 0 &&
            _currentSourceIndex < sources.length
        ? sources[_currentSourceIndex]
        : null;
    final candidate =
        source ??
        (indexedSource?.directUrl == media.uri ? indexedSource : null);
    final watchSource = MediaServerWatchController.isServerSource(candidate)
        ? candidate
        : null;
    if (!identical(watchSource, _openedWatchSource)) {
      _resumeSave.observeServerWatch();
      _serverWatch.commit(null);
    }
    // EVERY content open invalidates the outgoing media's resume protection —
    // the one choke point all switch paths share, so no path (Stremio TV
    // channel, Magic TV next, zap, source switch, startup ladder) can leave a
    // stale guard suppressing the new media's saves or a live verifier
    // re-seeking the old target against it. Ordering is safe by construction:
    // every outgoing checkpoint save runs BEFORE its new open, and every path
    // that re-protects (_seekForResume) re-arms AFTER it.
    _resumeVerifyEpoch++;
    _resumeWriteGuard.clear();
    _beginMediaGeneration(preserveStartupEpoch: preserveStartupEpoch);
    // Live IPTV (Phase 2, Layer 1): ffmpeg-level reconnect. mpv's default
    // reconnect covers only seekable inputs — a live/streamed input NEVER
    // reconnects without reconnect_streamed. Repairs happen inside the
    // protocol layer while the demuxer cache plays through, so the common
    // connection drop is invisible. Cleared for non-live opens: the
    // property is player-global and reconnect-on-error semantics are wrong
    // for finite files (mpv's own defaults handle those).
    final platform = _player.platform;
    if (platform is mk.NativePlayer) {
      final tuningGeneration = _decoderProbeGeneration;
      NetworkTuning tuning;
      try {
        tuning = _networkTuning ??= await NetworkTuning.load();
      } catch (e) {
        // Profile storage refusing a read must degrade to "no tuning", never
        // block playback — this line is on the Standard path too.
        debugPrint('Player: network tuning load failed: $e');
        tuning = _networkTuning = const NetworkTuning(
          patience: NetworkTuning.standard,
          buffer: NetworkTuning.standard,
        );
      }
      try {
        await platform.setProperty(
          'stream-lavf-o',
          // reconnect_on_http_error=5xx covers server-side hiccups at the
          // protocol layer. Deliberately narrow: NOT auth-class 4xx (same
          // answer every time — must surface), and not 429 (a comma-list
          // value can't ride mpv's key-value list safely, and escalating a
          // rate limit to the slower ladder is politer to the origin).
          //
          // VOD opens carry the user's Network & Buffering patience preset
          // ('' at Standard — today's exact behavior).
          liveStream
              ? 'reconnect=1,reconnect_streamed=1,'
                    'reconnect_on_network_error=1,'
                    'reconnect_on_http_error=5xx,'
                    'reconnect_delay_max=5'
              : tuning.vodLavfOptions,
        );
      } catch (e) {
        debugPrint('Player: stream-lavf-o set failed: $e');
      }
      await _applyNetworkTuning(
        platform,
        tuning,
        liveStream: liveStream,
        generation: tuningGeneration,
      );
    }
    final remedy = _tvosDecodeRemedy;
    if (remedy != null) {
      // AWAITED before open: remedy properties are ordinary runtime options
      // on a reused native player — this is the boundary that restores them
      // (and pre-applies the session hint) so a previous file's ladder can
      // never leak into this one.
      final generation = _decoderProbeGeneration;
      await remedy.onNewMedia(generation);
      // A rapid zap can start a newer open while the restore ran; the newer
      // call owns the player now.
      if (_screenDisposed || generation != _decoderProbeGeneration) return;
    }
    // `sub-visibility` is player-global. Reset it before a reused player opens
    // new media so a previous bitmap track cannot make auto-selected text draw
    // both natively and in Flutter. Restored bitmap selections re-enable it.
    if (platform is mk.NativePlayer) {
      try {
        if (_hasSubtitlePolicy) {
          await platform.setProperty('sid', 'no');
        }
        await platform.setProperty(
          'sub-visibility',
          VpS2Hooks.isIOS && (_isPipActive || _pip.iosPipStarting)
              ? 'yes'
              : 'no',
        );
      } catch (error) {
        debugPrint('Player: subtitle visibility reset failed: $error');
      }
    }
    Future<void> commitOpen() async {
      // Final ownership check after setup AND asynchronous authorization.
      if (_screenDisposed || !mounted) return;
      if (watchSource != null) {
        await _serverWatch.prepare(
          watchSource,
          contentTitle: _effectiveContentTitle,
        );
        await DirectSourceAuthorization.authorize(watchSource);
      }
      if (_screenDisposed ||
          !mounted ||
          watchEpoch != _watchOpenEpoch ||
          request?.isCurrent == false) {
        return;
      }
      // This callback arms candidate validation. Never arm it while the old
      // media could still emit events during a server watch-state request.
      if (beforeOpen != null && !beforeOpen()) return;
      if (watchSource != null) {
        logSourceSelection(
          'media_server_open',
          source: watchSource,
          player: 'mpv',
        );
      }
      _openedWatchSource = watchSource;
      _activeOpenedMedia = media;
      _activeMediaShouldPlay = desiredPlay ?? play;
      _activeMediaUserPaused = false;
      PlayerVisibility.playbackState(this, ready: false);
      if (request != null) {
        await request.commit(() => _player.open(media, play: play));
        return;
      }
      return _player.open(media, play: play);
    }

    // Startup direct fallbacks bypass URL resolvers. Recheck their captured
    // capability here so revoked/disabled/reconnected sources cannot open.
    if (source != null) {
      return DirectSourceAuthorization.runIfAuthorized(source, commitOpen);
    }
    return commitOpen();
  }

  void _releasePlayerDiagnostic(String fields) {
    final message = 'DEBRIFY_PLAYER_DECODER $fields';
    if (Platform.isAndroid) {
      // A dedicated native tag lets release captures select only this
      // privacy-safe line. Capturing Flutter's general stdout exposed unrelated
      // service logs and must not be required for decoder diagnostics.
      unawaited(
        _androidPlayerDiagnosticChannel
            .invokeMethod<void>('logDecoder', {'message': fields})
            .catchError((_) {}),
      );
      return;
    }
    if (PlatformUtil.isTvOS) {
      // tvOS release builds deliberately do not bridge every debugPrint call,
      // because unrelated logs can contain private playback data. This narrow,
      // privacy-safe diagnostic still needs to reach the Xcode/device console.
      unawaited(
        _tvReleaseLogChannel
            .invokeMethod<void>('log', message)
            .catchError((_) {}),
      );
      return;
    }

    // Intentional: print reaches desktop process consoles in release builds.
    // Keep this payload free of titles, URLs and account IDs.
    // ignore: avoid_print
    print(message);
  }

  @override
  void didUpdateWidget(covariant VideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `hideOptions` / `hideSeekbar` arrive through the widget, not through an
    // inherited dependency, so didChangeDependencies never fires for them.
    _refreshDockGeometry();
    if (widget.channelName != oldWidget.channelName) {
      final String? trimmed = widget.channelName?.trim();
      if ((trimmed == null || trimmed.isEmpty) && _currentChannelName != null) {
        setState(() {
          _currentChannelName = null;
        });
      } else if (trimmed != null &&
          trimmed.isNotEmpty &&
          _currentChannelName != widget.channelName) {
        setState(() {
          _currentChannelName = widget.channelName;
        });
      }
    }
  }

  // Wait for the video to be ready and duration to be available
  Future<void> _waitForVideoReady() async {
    // Wait up to 10 seconds for the video to be ready
    for (int i = 0; i < 100; i++) {
      if (_duration > Duration.zero) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // Wait for duration to be available before attempting position restoration
  Future<void> _waitForDuration() async {
    // Wait up to 20 seconds for duration to be available
    for (int i = 0; i < 200; i++) {
      if (_duration > Duration.zero) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Get the last played episode for a series
  Future<Map<String, dynamic>?> _getLastPlayedEpisode(
    SeriesPlaylist seriesPlaylist,
  ) async {
    try {
      final lastEpisode = await EpisodeResumeStorage.getLastPlayedEpisode(
        seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
      );

      if (lastEpisode != null) {
        final season = lastEpisode['season'] as int;
        final episode = lastEpisode['episode'] as int;
        debugPrint(
          'VideoPlayer: StorageService returned resume S${season}E$episode for "${seriesPlaylist.seriesTitle}"',
        );

        // Find the original index for this episode
        final originalIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(
          season,
          episode,
        );
        if (originalIndex != -1) {
          return {...lastEpisode, 'originalIndex': originalIndex};
        }
        debugPrint(
          'VideoPlayer: resume entry S${season}E$episode not found in playlist for "${seriesPlaylist.seriesTitle}"',
        );
      }
    } catch (e) {
      debugPrint('VideoPlayer: failed to read last episode resume: $e');
    }
    return null;
  }

  Future<void> _onPlaybackEnded() async {
    // A manually selected replacement is not playback until its validation
    // gate commits it. In particular, a short provider error video can emit
    // `completed`; never let that become a watched/scrobble event.
    if (_validationGateActive) return;
    _resumeSave.observeServerWatch(completed: true);
    // LIVE IPTV: an ended live stream is a dropped connection, not a
    // finished item — the origin closed on us (mpv's keep-open parks on the
    // last frame, which is the "fake pause" from the Discord report). The
    // recovery machine re-tunes to the live edge; nothing below this line
    // (scrobble stop, mark-as-finished, episode advance) may interpret a
    // live EOF as "watched to the end" — so live returns here even when the
    // machine declines (backgrounded, sleep-stopped).
    final endedLiveChannel = _currentIptvChannel;
    if (endedLiveChannel != null && endedLiveChannel.isLive) {
      _iptvLiveRecovery.onEnded();
      return;
    }

    // Scrobble stop to Trakt when movie finishes
    _trakt.stopTraktHeartbeat();
    _trakt.traktScrobble('stop');
    _simkl.stopSimklHeartbeat();
    _simkl.simklScrobble('stop');
    _mdblist.mdblistStop(complete: true);

    // Mark the current episode as finished if it's a series
    await _completion.markCurrentEpisodeAsFinished();
    // A locally tracked movie may finish before the next periodic position
    // save; make EOF a completion too (tracker sessions keep their existing
    // scrobble-only path above).
    await _completion.markCurrentMovieAsFinished();

    // "Stop at the end of this episode": suppress every advance below and let
    // the screen sleep. Playback has already finished, so there is nothing
    // left to pause.
    if (_sleep.sleepTimerMode == SleepTimerMode.endOfItem) {
      _sleep.cancelSleepTimer();
      _sleepStopLatched = true;
      _activeMediaShouldPlay = false;
      _sleep.showSleepTimerToast('Sleep timer — stopping here');
      return;
    }

    // IPTV episode list (series/VOD): advance to the next episode in the
    // season, mirroring the Next button. Checked first because IPTV episodes
    // carry no playlist / magic-next, so the branches below would otherwise
    // leave the player parked on the final frame with a next episode available.
    if (_hasIptvNext) {
      await _iptvSwitch.switchToIptvChannel(_currentIptvIndex + 1);
      return;
    }

    // Playlist auto-advance keeps priority over guide-based Stremio TV next.
    if (_continuousShuffleEnabled) {
      if (await _playShowShuffle(autoAdvance: true)) return;
      final shuffleIndex = _pickShuffleIndex();
      if (shuffleIndex != null) {
        _isAutoAdvancing = true;
        await _loadPlaylistIndex(shuffleIndex, autoplay: true);
        return;
      }
    }

    final nextIndex = _findNextEpisodeIndex();
    if (nextIndex != -1) {
      _isAutoAdvancing = true;
      await _loadPlaylistIndex(nextIndex, autoplay: true);
      return;
    }

    if (_hasStremioTvNext) {
      final handled = await _goToNextStremioTvSlot(
        resumeCurrentOnFailure: false,
      );
      if (handled) return;
      debugPrint(
        'Player: Stremio TV auto-next unavailable; leaving playback ended.',
      );
      return;
    }

    // Debrify TV (no playlist): auto-advance using provider if available
    if ((_activePlaylist == null || _activePlaylist!.isEmpty) &&
        widget.requestMagicNext != null) {
      await _goToNextEpisode();
      return;
    }

    // Match manual Next for direct links and exhausted packs: keep the player
    // alive while resolving the following episode.
    if (await _fetchNextEpisodeInPlayer(autoAdvance: true)) return;

    if (_activePlaylist == null || _activePlaylist!.isEmpty) {
      // No playlist — try series next episode
      await _handleSeriesNextEpisode();
      return;
    }

    // End of playlist — try series next episode
    await _handleSeriesNextEpisode();
  }

  void _startTransitionOverlay() {
    if (!mounted) return;
    _rainbowActive = true;
    _transitionRunning = true;
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 1;
    // Pick a random retro TV message and reset subtext
    _tvStaticMessage =
        _tvStaticMessages[math.Random().nextInt(_tvStaticMessages.length)];
    _tvStaticSubtext = ''; // Clear subtext until video is ready
    debugPrint('Player: Transition overlay started.');
    // Match Android TV: update every 50ms for smooth static effect
    _rainbowController.repeat(
      period: VideoPlayerTimingConstants.rainbowRepeatPeriod,
    );
    if (mounted) setState(() {});
  }

  /// Get the current episode title for display
  String _getCurrentEpisodeTitle() => _getCurrentEpisodeTitleInfo().title;

  /// The dock title plus whether it's a fetched, human name (TVMaze episode
  /// title, catalog content title, channel name) as opposed to a release
  /// filename. TvControls skips its release-noise cleaner for fetched names —
  /// the token list would truncate a real title containing e.g. "Proper".
  ({String title, bool fetched}) _getCurrentEpisodeTitleInfo() {
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _activePlaylist != null) {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return episode title if available, otherwise use the playlist entry title
          if (currentEpisode.episodeInfo?.title != null &&
              currentEpisode.episodeInfo!.title!.isNotEmpty) {
            final episodeTitle = currentEpisode.episodeInfo!.title!;
            // "Show — Episode" when TVMaze supplied the official show name;
            // the subtitle then drops the name to avoid saying it twice.
            final show = seriesPlaylist.tvmazeShowName;
            return (
              title: show == null || show.isEmpty
                  ? episodeTitle
                  : '$show — $episodeTitle',
              fetched: true,
            );
          } else if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog singleton without TVMaze data yet: the clean catalog
            // title beats a bare "Episode N".
            final contentTitle = _effectiveContentTitle;
            if (_activePlaylist!.length == 1 &&
                contentTitle != null &&
                contentTitle.isNotEmpty &&
                _effectiveStremioTvChannels == null) {
              return (title: contentTitle, fetched: true);
            }
            final episodeTitle = 'Episode ${currentEpisode.seriesInfo.episode}';
            final show = seriesPlaylist.tvmazeShowName;
            return (
              title: show == null || show.isEmpty
                  ? episodeTitle
                  : '$show — $episodeTitle',
              fetched: true,
            );
          }
        } catch (e) {
          // Silently fail
        }
      }
    }

    // Stremio TV: use dynamic title when a channel switch has occurred
    if (_hasStremioTvGuide && _dynamicTitle.isNotEmpty) {
      return (title: _dynamicTitle, fetched: true);
    }

    // Catalog single stream (Quick Play / Sources tap): prefer the clean
    // content title over the release filename. Packs are handled by the
    // series branch above; Debrify TV, IPTV and Stremio TV keep their
    // dynamic titles.
    final contentTitle = _effectiveContentTitle;
    if (contentTitle != null &&
        contentTitle.isNotEmpty &&
        widget.requestMagicNext == null &&
        _effectiveIptvChannels == null &&
        _effectiveStremioTvChannels == null &&
        (_activePlaylist == null || _activePlaylist!.length <= 1)) {
      return (title: contentTitle, fetched: true);
    }

    // Fallback to the current playlist entry title
    if (_activePlaylist != null &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      return (title: _activePlaylist![_currentIndex].title, fetched: false);
    }

    // If Debrify TV (no playlist) is active, use dynamic title when available
    // (a Debrify TV title can be a torrent name — keep the cleaner on it).
    if ((_activePlaylist == null || _activePlaylist!.isEmpty) &&
        widget.requestMagicNext != null) {
      return _dynamicTitle.isNotEmpty
          ? (title: _dynamicTitle, fetched: false)
          : (title: widget.title, fetched: false);
    }

    // IPTV: use current channel name
    final iptvChannels = _effectiveIptvChannels;
    if (iptvChannels != null &&
        _currentIptvIndex >= 0 &&
        _currentIptvIndex < iptvChannels.length) {
      return (
        title: iptvChannels[_currentIptvIndex].numberedName,
        fetched: true,
      );
    }

    // Final fallback
    return (title: widget.title, fetched: false);
  }

  /// Get the current episode subtitle for display
  String? _getCurrentEpisodeSubtitle() {
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _activePlaylist != null) {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return series name and season/episode info as subtitle
          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog singleton: the filename-parsed series name can be a
            // mangled release string; the clean catalog title is authoritative.
            // While TVMaze hasn't supplied an episode title yet, the title line
            // is already showing the catalog name — don't repeat it here.
            final contentTitle = _effectiveContentTitle;
            final isCatalogSingleton =
                _activePlaylist!.length == 1 &&
                contentTitle != null &&
                contentTitle.isNotEmpty &&
                _effectiveStremioTvChannels == null;
            final seasonEpisode =
                'Season ${currentEpisode.seriesInfo.season}, Episode ${currentEpisode.seriesInfo.episode}';
            // When TVMaze supplied the show name, the TITLE line already
            // reads "Show — Episode", so repeating the name here would say
            // it twice. Without it, fall back to the filename-parsed series
            // name — release strings only as a last resort, same rule as the
            // native player's OTT identity row.
            final showName = seriesPlaylist.tvmazeShowName;
            if (showName != null && showName.isNotEmpty) {
              return seasonEpisode;
            }
            if (isCatalogSingleton) {
              final hasEpisodeTitle =
                  currentEpisode.episodeInfo?.title?.isNotEmpty == true;
              return hasEpisodeTitle
                  ? '$contentTitle • $seasonEpisode'
                  : seasonEpisode;
            }
            return '${seriesPlaylist.seriesTitle} • $seasonEpisode';
          }
        } catch (e) {}
      }
    }

    // IPTV: use current channel group as subtitle
    final iptvChannels = _effectiveIptvChannels;
    if (iptvChannels != null &&
        _currentIptvIndex >= 0 &&
        _currentIptvIndex < iptvChannels.length) {
      return iptvChannels[_currentIptvIndex].group ?? 'IPTV';
    }

    // Catalog single stream: when the title shows the clean content name,
    // surface the episode identity (and the release detail line) here.
    final contentTitle = _effectiveContentTitle;
    if (contentTitle != null &&
        contentTitle.isNotEmpty &&
        widget.requestMagicNext == null &&
        _effectiveStremioTvChannels == null &&
        (_activePlaylist == null || _activePlaylist!.length <= 1)) {
      final season = _effectiveContentSeason;
      final episode = _effectiveContentEpisode;
      final parts = <String>[
        if (season != null && episode != null)
          'Season $season, Episode $episode',
        if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty)
          widget.subtitle!,
      ];
      if (parts.isNotEmpty) return parts.join(' • ');
    }

    // Fallback to the current subtitle or widget subtitle
    return widget.subtitle;
  }

  /// Get enhanced metadata for OTT-style display
  Map<String, dynamic> _getEnhancedMetadata() {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _activePlaylist != null) {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.episodeInfo != null) {
            final episodeInfo = currentEpisode.episodeInfo!;

            final metadata = {
              'rating': episodeInfo.rating,
              'runtime': episodeInfo.runtime,
              'year': episodeInfo.year,
              'airDate': episodeInfo.airDate,
              'language': episodeInfo.language,
              'genres': episodeInfo.genres,
              'network': episodeInfo.network,
              'country': episodeInfo.country,
              'plot': episodeInfo.plot,
            };

            return metadata;
          }
        } catch (e) {}
      }
    }

    return {};
  }

  /// Find the next logical episode index for auto-advance
  int _findNextEpisodeIndex() {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (widget.viewMode == PlaylistViewMode.raw ||
          widget.viewMode == PlaylistViewMode.sorted) {
        if (_activePlaylist == null || _activePlaylist!.isEmpty) return -1;
        if (_currentIndex + 1 < _activePlaylist!.length) {
          return _currentIndex + 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (_activePlaylist == null || _activePlaylist!.isEmpty) return -1;
      final indices = _getMainGroupIndices(_activePlaylist!);
      if (indices.isEmpty) return -1;

      final currentPos = indices.indexOf(_currentIndex);
      if (currentPos == -1) {
        return indices.first;
      }

      if (currentPos + 1 < indices.length) {
        return indices[currentPos + 1];
      }

      return -1;
    }

    // Series mode: existing logic
    try {
      // Find current episode in the sorted allEpisodes list
      final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
        (episode) => episode.originalIndex == _currentIndex,
        orElse: () {
          if (seriesPlaylist.allEpisodes.isEmpty) {
            throw StateError('allEpisodes is empty');
          }
          return seriesPlaylist.allEpisodes.first;
        },
      );

      // Find the index of current episode in allEpisodes
      final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(
        currentEpisode,
      );

      if (currentEpisodeIndex == -1 ||
          currentEpisodeIndex + 1 >= seriesPlaylist.allEpisodes.length) {
        return -1;
      }

      // Get the next episode from the sorted list
      final nextEpisode = seriesPlaylist.allEpisodes[currentEpisodeIndex + 1];
      return nextEpisode.originalIndex;
    } catch (e) {
      return -1;
    }
  }

  /// Compute the Main group indices for movie collections (size >= 70% of largest)
  List<int> _getMainGroupIndices(List<PlaylistEntry> entries) {
    int maxSize = -1;
    for (final e in entries) {
      final s = e.sizeBytes ?? -1;
      if (s > maxSize) maxSize = s;
    }
    final double threshold = maxSize > 0 ? maxSize * 0.40 : -1;
    final main = <int>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isSmall =
          threshold > 0 && (e.sizeBytes != null && e.sizeBytes! < threshold);
      if (!isSmall) main.add(i);
    }
    int sizeOf(int idx) => entries[idx].sizeBytes ?? -1;
    int? yearOf(int idx) {
      final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(entries[idx].title);
      if (m != null) return int.tryParse(m.group(0)!);
      return null;
    }

    main.sort((a, b) {
      final ya = yearOf(a);
      final yb = yearOf(b);
      if (ya != null && yb != null) return ya.compareTo(yb); // older first
      return sizeOf(b).compareTo(sizeOf(a));
    });
    return main;
  }

  Future<void> _showRandomPlaybackMenu() async {
    final entries = _activePlaylist ?? const [];
    if (entries.isEmpty && !_canFetchEpisodes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playlist items available')),
      );
      return;
    }

    if (kUnifiedPlayerMenuEnabled) {
      _menu.openPlayerMenuQuick(PlayerMenuSection.shuffle);
      return;
    }

    _hideTimer?.cancel();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
        final shuffleLabel = _continuousShuffleEnabled
            ? 'Turn Off Continuous Shuffle'
            : 'Shuffle Continuously';
        final shuffleSubtitle = _continuousShuffleEnabled
            ? 'Return to normal ordered playback'
            : 'Keep picking random items after each episode ends';

        return AlertDialog(
          backgroundColor: const Color(0xFF141824),
          title: const Text(
            'Shuffle Playback',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VpRandomChoiceTile(
                icon: Icons.shuffle_rounded,
                title: 'Play Random Once',
                subtitle: 'Pick one random item, then resume normal order',
                onTap: () => Navigator.of(context).pop('once'),
              ),
              const SizedBox(height: 8),
              VpRandomChoiceTile(
                icon: _continuousShuffleEnabled
                    ? Icons.check_circle_rounded
                    : Icons.all_inclusive_rounded,
                title: shuffleLabel,
                subtitle: shuffleSubtitle,
                onTap: () => Navigator.of(context).pop('continuous'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    _scheduleAutoHide();

    if (choice == 'once') {
      await _playRandomOnce(disableContinuousShuffle: true);
    } else if (choice == 'continuous') {
      await _toggleContinuousShuffle();
    }
  }

  Future<void> _toggleContinuousShuffle() async {
    if (_continuousShuffleEnabled) {
      setState(() {
        _continuousShuffleEnabled = false;
        _shuffleBag.clear();
        _showShuffle.clear();
        _showShuffleGeneration++;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Continuous shuffle off')));
    } else {
      setState(() {
        _continuousShuffleEnabled = true;
        _shuffleBag.clear();
        _showShuffle.clear();
        _showShuffleGeneration++;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Continuous shuffle on')));
      await _playRandomOnce(disableContinuousShuffle: false);
    }
  }

  Future<void> _playRandomOnce({required bool disableContinuousShuffle}) async {
    if (disableContinuousShuffle) {
      if (_continuousShuffleEnabled) {
        setState(() {
          _continuousShuffleEnabled = false;
          _shuffleBag.clear();
          _showShuffle.clear();
          _showShuffleGeneration++;
        });
      } else {
        _shuffleBag.clear();
        _showShuffle.clear();
        _showShuffleGeneration++;
      }
    }

    if (await _playShowShuffle()) return;
    final nextIndex = _pickShuffleIndex();
    if (nextIndex == null) return;
    _setManualSelectionMode();
    await _loadPlaylistIndex(nextIndex, autoplay: true);
  }

  /// Returns true when show-wide shuffle owns this request, including failure.
  /// Never fall through to ordered playback after exhausting random candidates.
  Future<bool> _playShowShuffle({bool autoAdvance = false}) async {
    if (!_canFetchEpisodes) return false;
    final generation = _showShuffleGeneration;
    final navigation = _episodeNavigationGeneration;
    while (_showShuffleInProgress || _episodeFetchInProgress) {
      if (_showShuffleInProgress &&
          _activeShowShuffleGeneration == generation) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (!mounted ||
          generation != _showShuffleGeneration ||
          navigation != _episodeNavigationGeneration) {
        return true;
      }
    }
    _showShuffleInProgress = true;
    _activeShowShuffleGeneration = generation;
    bool requestIsCurrent() =>
        mounted &&
        generation == _showShuffleGeneration &&
        (!autoAdvance || !_sleepStopLatched);
    final request = EpisodePlaybackRequest(
      currentIdentity: () => _playlistIdentityToken,
      currentNavigation: () => _episodeNavigationGeneration,
      isActive: requestIsCurrent,
    );
    try {
      final customInventory =
          widget.seriesSourceFetcher?.loadCustomEpisodeInventory;
      final List<Map<String, dynamic>> full;
      if (customInventory != null) {
        full = await customInventory();
      } else {
        await (_episodeMetadataReady ??= _preloadEpisodeInfo());
        if (!request.isCurrent) return true;
        if (_seriesPlaylist == null) {
          final synthetic = _buildSyntheticGuide();
          if (synthetic != null && synthetic.$1.fullTvmazeEpisodes.isEmpty) {
            await synthetic.$1.fetchEpisodeInfo(
              playlistItem: _constructPlaylistItemData(),
              imdbId: _currentSeriesImdbId,
            );
          }
        }
        if (!request.isCurrent) return true;
        full = _seriesPlaylist?.fullTvmazeEpisodes.isNotEmpty == true
            ? _seriesPlaylist!.fullTvmazeEpisodes
            : (_syntheticGuidePlaylist?.fullTvmazeEpisodes ??
                  const <Map<String, dynamic>>[]);
      }
      if (!request.isCurrent) return true;
      if (full.isEmpty && customInventory == null) return false;
      final eligible = full
          .where((m) => isShuffleEpisodeEligible(m))
          .map((m) => (m['season'] as int, m['number'] as int))
          .toList();
      final attempted = <ShuffleEpisode>{};
      for (var attempt = 0; attempt < 3; attempt++) {
        final current = _traktSeasonEpisode();
        final target = _showShuffle.pick(
          eligible,
          current.season == null || current.episode == null
              ? null
              : (current.season!, current.episode!),
          excluded: attempted,
        );
        if (target == null) break;
        attempted.add(target);
        final index =
            _seriesPlaylist?.findOriginalIndexBySeasonEpisode(
              target.$1,
              target.$2,
            ) ??
            -1;
        if (index >= 0) {
          // EOF loads must retain sleep-stop and start-from-zero semantics,
          // including when URL resolution outlasts the manual-selection timer.
          _isAutoAdvancing = autoAdvance;
          if (!autoAdvance) _setManualSelectionMode();
          final outcome = await request.attempt(
            () => _loadPlaylistIndex(
              index,
              autoplay: true,
              suppressResume: true,
              request: request,
            ),
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return true;
          // A pack entry can have an unavailable URL. Try another source for
          // this episode before moving on to the next random candidate.
        }
        final outcome = await _fetchAndPlayEpisode(
          target.$1,
          target.$2,
          shuffleGeneration: generation,
          autoAdvance: autoAdvance,
          request: request,
        );
        if (outcome != EpisodePlaybackOutcome.unavailable) return true;
      }
      if (mounted) {
        setState(() => _isTransitioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No other playable episode found for shuffle'),
          ),
        );
      }
      return true;
    } catch (error) {
      debugPrint('Show shuffle failed: $error');
      if (mounted) {
        setState(() => _isTransitioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load a random episode')),
        );
      }
      return true;
    } finally {
      _showShuffleInProgress = false;
      _activeShowShuffleGeneration = null;
      if (mounted && generation != _showShuffleGeneration && _isTransitioning) {
        setState(() => _isTransitioning = false);
      }
    }
  }

  List<int> _shuffleEligibleIndices() {
    final entries = _activePlaylist;
    if (entries == null || entries.isEmpty) return const [];

    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final indices = seriesPlaylist.allEpisodes
          .map((episode) => episode.originalIndex)
          .where((index) => index >= 0 && index < entries.length)
          .toSet()
          .toList();
      if (indices.isNotEmpty) return indices;
    }

    if (widget.viewMode == PlaylistViewMode.raw ||
        widget.viewMode == PlaylistViewMode.sorted) {
      return List<int>.generate(entries.length, (index) => index);
    }

    final mainIndices = _getMainGroupIndices(
      entries,
    ).where((index) => index >= 0 && index < entries.length).toList();
    if (mainIndices.isNotEmpty) return mainIndices;

    return List<int>.generate(entries.length, (index) => index);
  }

  int? _pickShuffleIndex() {
    final eligible = _shuffleEligibleIndices();
    if (eligible.isEmpty) return null;
    if (eligible.length == 1) return eligible.first;

    final eligibleSet = eligible.toSet();
    _shuffleBag.removeWhere(
      (index) => !eligibleSet.contains(index) || index == _currentIndex,
    );

    if (_shuffleBag.isEmpty) {
      _shuffleBag.addAll(
        eligible.where((index) => index != _currentIndex).toList()
          ..shuffle(_random),
      );
    }

    if (_shuffleBag.isEmpty) return null;
    return _shuffleBag.removeLast();
  }

  /// Find the previous logical episode index
  int _findPreviousEpisodeIndex() {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (widget.viewMode == PlaylistViewMode.raw ||
          widget.viewMode == PlaylistViewMode.sorted) {
        if (_activePlaylist == null || _activePlaylist!.isEmpty) return -1;
        if (_currentIndex - 1 >= 0) {
          return _currentIndex - 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (_activePlaylist == null || _activePlaylist!.isEmpty) return -1;
      final indices = _getMainGroupIndices(_activePlaylist!);
      if (indices.isEmpty) return -1;

      final currentPos = indices.indexOf(_currentIndex);
      if (currentPos == -1) {
        return indices.first;
      }

      if (currentPos - 1 >= 0) {
        return indices[currentPos - 1];
      }

      return -1;
    }

    // Series mode: existing logic
    try {
      // Find current episode in the sorted allEpisodes list
      final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
        (episode) => episode.originalIndex == _currentIndex,
        orElse: () {
          if (seriesPlaylist.allEpisodes.isEmpty) {
            throw StateError('allEpisodes is empty');
          }
          return seriesPlaylist.allEpisodes.first;
        },
      );

      // Find the index of current episode in allEpisodes
      final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(
        currentEpisode,
      );

      if (currentEpisodeIndex <= 0) {
        return -1;
      }

      // Get the previous episode from the sorted list
      final previousEpisode =
          seriesPlaylist.allEpisodes[currentEpisodeIndex - 1];
      return previousEpisode.originalIndex;
    } catch (e) {
      return -1;
    }
  }

  /// Check if there's a next episode available
  bool _hasNextEpisode() {
    if (_findNextEpisodeIndex() != -1) return true;
    if (_canFetchEpisodes) {
      final se = _traktSeasonEpisode();
      if (se.season != null && se.episode != null) return true;
    }
    // Series content may have a next episode discoverable via Stremio metadata.
    // Requires episode info from widget params or a parsed series playlist.
    if (widget.requestMagicNext == null &&
        widget.contentType == 'series' &&
        widget.contentImdbId != null &&
        (widget.contentSeason != null || _seriesPlaylist != null)) {
      return true;
    }
    return false;
  }

  /// Check if there's a previous episode available
  bool _hasPreviousEpisode() {
    if (_findPreviousEpisodeIndex() != -1) return true;
    // Beyond the pack's start: a previous episode may exist show-wide and be
    // fetchable in-player (metadata-list adjacency decides at press time).
    if (_canFetchEpisodes) {
      final se = _traktSeasonEpisode();
      if (se.season != null && se.episode != null) {
        return _adjacentEpisode(se.season!, se.episode!, -1) != null ||
            (widget.seriesSourceFetcher?.resolveAdjacentEpisode != null &&
                (se.season! > 1 || se.episode! > 1));
      }
    }
    return false;
  }

  void _clearBufferingIndicator() {
    _bufferingDebounceTimer?.cancel();
    _showBufferingIndicator.value = false;
  }

  /// Navigate to next episode
  Future<void> _goToNextEpisode() async {
    // Check if widget is still mounted before any state changes
    if (!mounted) return;

    // Show black screen during transition to hide previous frame
    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
    });

    // Only show transition overlay for Debrify TV content (when requestMagicNext is available)
    final isDebrifyTV = widget.requestMagicNext != null;
    if (isDebrifyTV) {
      _startTransitionOverlay();
    }
    try {
      await _player.pause();
    } catch (_) {}
    if (_continuousShuffleEnabled) {
      if (await _playShowShuffle()) return;
      final shuffleIndex = _pickShuffleIndex();
      if (shuffleIndex != null) {
        _setManualSelectionMode();
        await _loadPlaylistIndex(shuffleIndex, autoplay: true);
        return;
      }
    }

    final nextIndex = _findNextEpisodeIndex();
    if (nextIndex != -1) {
      // Mark this as a manual episode selection
      _setManualSelectionMode();
      await _loadPlaylistIndex(nextIndex, autoplay: true);
      return;
    }

    if (_hasStremioTvNext) {
      final handled = await _goToNextStremioTvSlot();
      if (handled) return;
    }

    // Series content beyond the pack: fetch the next episode IN-PLAYER when
    // possible (no relaunch), falling back to the pop-and-quick-play handoff.
    if (await _fetchNextEpisodeInPlayer()) return;

    // Series content without season pack: find next episode and trigger Quick Play
    if (widget.requestMagicNext == null) {
      final handled = await _handleSeriesNextEpisode();
      if (handled) return;
    }

    // If there is no playlist-based next item and Debrify TV provider is present, use it
    if (widget.requestMagicNext != null) {
      debugPrint('Player: MagicTV next requested.');
      try {
        final result = await widget.requestMagicNext!();
        final url = result != null ? (result['url'] ?? '') : '';
        final title = result != null ? (result['title'] ?? '') : '';
        final provider = result != null ? (result['provider'] ?? '') : '';
        final pikpakFileId = result != null
            ? (result['pikpakFileId'] ?? '')
            : '';

        if (url.isNotEmpty) {
          debugPrint(
            'Player: MagicTV next success. Opening new URL (provider: $provider, pikpakFileId: $pikpakFileId).',
          );

          // Clear subtitle, IMDB, and local completion state when switching content
          _resetSubtitleState();
          _singleFileImdbId = null;
          _singleFileImdbFetched = false;
          _completion.resetLocalCompletionState();

          // Update TV static overlay to show signal acquired
          if (title.isNotEmpty && mounted) {
            setState(() {
              _tvStaticMessage = '📺 SIGNAL ACQUIRED';
              _tvStaticSubtext = '▶ ${title.toUpperCase()}';
            });
          }

          // Use PikPak retry logic if this is a PikPak video
          final isPikPak =
              provider.toLowerCase() == 'pikpak' || pikpakFileId.isNotEmpty;
          if (isPikPak) {
            debugPrint(
              'Player: Detected PikPak video from Debrify TV, using retry logic',
            );
            // _playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
            await _playPikPakVideoWithRetry(
              url,
              overrideProvider: provider,
              overridePikPakFileId: pikpakFileId,
              isDebrifyTV: true,
            );
          } else {
            // Cancel any ongoing PikPak retry when switching to non-PikPak video
            _pikPakRetryId++;
            await _openMedia(
              mk.Media(url, httpHeaders: _activeHttpHeaders),
              play: true,
            );
          }
          _currentStreamUrl = url;
          // Disable auto-enabled embedded subtitles to prevent duplicates
          await _subtitleApply.setSubtitleTrackWithDiagnostics(
            mk.SubtitleTrack.no(),
            source: 'debrify-tv-open-disable-auto',
          );
          // If advanced option is enabled, jump to a random timestamp for Debrify TV items
          if (widget.startFromRandom) {
            await _waitForVideoReady();
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            }
          } else if (widget.startAtPercent != null) {
            await _waitForVideoReady();
            final offset = _percentStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            }
          }
          if (title.isNotEmpty) {
            setState(() {
              _dynamicTitle = title;
            });
          }
          // Clear transition state when video is ready
          if (mounted) {
            setState(() {
              _isTransitioning = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('Player: MagicTV next failed: $e');
      }
    }

    // Clear transition state if no next episode found
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
    }
  }

  /// Shared manual/EOF path beyond the current pack. A handled fetch, including
  /// cancellation or failure, stays in-player rather than relaunching it.
  Future<bool> _fetchNextEpisodeInPlayer({bool autoAdvance = false}) async {
    if (!_canFetchEpisodes) return false;
    if (_episodeFetchInProgress) return true;
    final identity = _playlistIdentityToken;
    final navigation = _episodeNavigationGeneration;
    bool stale() =>
        !mounted ||
        identity != _playlistIdentityToken ||
        navigation != _episodeNavigationGeneration ||
        (autoAdvance && _sleepStopLatched);
    if (stale()) return true;
    final se = _traktSeasonEpisode();
    if (se.season == null || se.episode == null) return false;
    var next = _adjacentEpisode(se.season!, se.episode!, 1);
    if (next == null) {
      final resolved = await _resolveAdjacentWithCachedGuide(
        se.season!,
        se.episode!,
        1,
      );
      if (resolved != null) next = (resolved.season, resolved.episode);
    }
    if (next == null &&
        widget.seriesSourceFetcher?.resolveAdjacentEpisode == null &&
        widget.contentImdbId != null) {
      final episode = await NextEpisodeService.findNextEpisode(
        widget.contentImdbId!,
        se.season!,
        se.episode!,
      );
      if (episode != null) next = (episode.season, episode.episode);
    }
    if (stale()) return true;
    if (next == null) return false;
    debugPrint(
      'Player: Next episode S${next.$1}E${next.$2} in-player autoAdvance=$autoAdvance',
    );
    await _fetchAndPlayEpisode(next.$1, next.$2, autoAdvance: autoAdvance);
    return true;
  }

  /// Legacy fallback: pop with the next episode for the caller's Quick Play.
  Future<bool> _handleSeriesNextEpisode() async {
    // Already popping to hand off the next episode — a second trigger (manual
    // Next racing end-of-video auto-advance) must not run again.
    if (_seriesNextDispatched) return true;
    if (widget.contentType != 'series' ||
        widget.contentImdbId == null ||
        widget.seriesSourceFetcher?.resolveAdjacentEpisode != null) {
      return false;
    }

    // Determine the CURRENT episode: prefer the series playlist (tracks actual
    // playback position within a season pack) over widget params (set at launch).
    int? currentSeason;
    int? currentEpisode;

    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _activePlaylist != null &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      try {
        final current = seriesPlaylist.allEpisodes.firstWhere(
          (ep) => ep.originalIndex == _currentIndex,
        );
        currentSeason = current.seriesInfo.season;
        currentEpisode = current.seriesInfo.episode;
      } catch (_) {
        // firstWhere threw — no match, fall through to widget params
      }
    }

    // Fallback to widget params (single-file playback without a series playlist)
    currentSeason ??= widget.contentSeason;
    currentEpisode ??= widget.contentEpisode;

    if (currentSeason == null || currentEpisode == null) return false;

    debugPrint(
      'Player: Looking up next episode after S${currentSeason}E$currentEpisode',
    );
    final nextEp = await NextEpisodeService.findNextEpisode(
      widget.contentImdbId!,
      currentSeason,
      currentEpisode,
    );

    if (nextEp == null) {
      debugPrint(
        'Player: No next episode found (last episode or lookup failed)',
      );
      return false;
    }

    debugPrint(
      'Player: Found next episode S${nextEp.season}E${nextEp.episode}, popping for Quick Play',
    );
    // Re-check the guard right before popping. Because nothing awaits between
    // here and the pop, this set-and-pop is atomic on Dart's single thread, so
    // a concurrent call that already passed the top guard and is resuming from
    // its own await will see the flag set and return without a second pop.
    if (!mounted || _seriesNextDispatched) return true;
    _seriesNextDispatched = true;
    final result = <String, dynamic>{
      'quickPlayNext': true,
      'imdbId': widget.contentImdbId,
      'season': nextEp.season,
      'episode': nextEp.episode,
      'title': widget.contentTitle ?? widget.title,
      'contentType': widget.contentType,
    };
    if (_pip.iosPipSession?.isParked ?? false) {
      _pip.iosPipSession!.close(result);
    } else {
      Navigator.of(context).pop(result);
    }
    return true;
  }

  /// Parse channel directory from widget params into ChannelEntry list
  void _parseChannelDirectory() {
    final directory = widget.channelDirectory;
    if (directory == null || directory.isEmpty) {
      _channelEntries = [];
      return;
    }

    _channelEntries = directory.asMap().entries.map((e) {
      final entry = ChannelEntry.fromMap(e.value, order: e.key);
      // Check if this is the current channel
      if (entry.isCurrent && _currentChannelId == null) {
        _currentChannelId = entry.id;
        if (entry.number != null) _currentChannelNumber = entry.number;
      }
      return entry;
    }).toList();
  }

  /// Load default player settings (aspect)
  /// The vertical band at the bottom of the screen the dock occupies.
  ///
  /// `classic` keeps the literal each consumer has always used; only the
  /// styled dock, whose height is variable, reports a measured value. The
  /// branch at six call sites is deliberate — one uniform value is impossible,
  /// since the consumers' legacy constants are 160/28, 72 and 80.
  double _dockBand(double legacy) =>
      _dockStyle.isStyled ? math.max(legacy, _dockExtent.value) : legacy;

  /// Where the skip-segment button sits above the bottom edge.
  ///
  /// The legacy value is not simply "160": it is 160 only while controls are
  /// visible AND (television OR options shown), else 28. Televisions build
  /// `TvControls`, so the styled path never engages there.
  double _skipButtonBottom(
    BuildContext context,
    bool controlsVisible,
    double dockExtent,
  ) {
    if (!_dockStyle.isStyled) {
      return controlsVisible &&
              (PlatformUtil.isTelevision || !widget.hideOptions)
          ? 160
          : 28;
    }
    // `infoPanel` mounts OUTSIDE the hideOptions guard, so a live panel can be
    // on screen while `!hideOptions` is false.
    final dockVisible =
        controlsVisible &&
        (_buildIptvInfoPanel(flush: true) != null ||
            _buildDebrifyTvInfoPanel(flush: true) != null ||
            !widget.hideOptions);
    if (!dockVisible) return 28;
    final inset = MediaQuery.paddingOf(context).bottom;
    return math.max(28.0, dockExtent + 8 - inset);
  }

  Future<void> _loadDockPrefs() async {
    final style = await PlayerAppearanceStorage.getPlayerDockStyle();
    final palette = await PlayerAppearanceStorage.getPlayerDockPalette();
    final size = await PlayerAppearanceStorage.getPlayerDockSize();
    if (!mounted) return;
    setState(() {
      _dockStyle = PlayerDockStyle.fromPref(style);
      _dockPalette = PlayerDockPalette.fromPref(palette);
      _dockSize = PlayerDockSize.fromPref(size);
      // Style/size are part of the geometry signature but arrive here, not
      // through an inherited dependency.
      _lastDockGeometrySignature = '';
      // Deliberately NOT seeded to the viewport height. Over-protecting the
      // whole screen kills every gesture until the first measurement, and it
      // also strands the fallback case: when DockMetrics.compute returns null
      // the classic subtree renders and no reporter is ever mounted, so the
      // seed would never be corrected. 0 means `_dockBand` yields the legacy
      // constant, which is exactly right for both.
    });
  }

  Future<void> _loadPlayerDefaults() async {
    _subtitleOnlyForeignAudio =
        await SubtitleSettingsStorage.getSubtitleOnlyForeignAudio();
    _subtitleForcedOnly = await SubtitleSettingsStorage.getSubtitleForcedOnly();
    _subtitlePreferredAudio =
        await SubtitleSettingsStorage.getDefaultAudioLanguage();
    _subtitleSync.subtitleAutoSyncEnabled =
        await SubtitleSettingsStorage.getSubtitleAutoSyncEnabled();
    debugPrint(
      'SubtitleAutoSync: pref loaded, enabled=${_subtitleSync.subtitleAutoSyncEnabled}',
    );
    // Load default aspect index
    final aspectIndex =
        await PlayerSettingsStorage.getPlayerDefaultAspectIndex();
    const aspects = AspectMode.values;
    _display.aspectMode = aspects[aspectIndex.clamp(0, aspects.length - 1)];

    // In-player guide look. `_initializePlayer` awaits this before playback
    // setup, so every IPTV surface that can actually appear (first tune,
    // zap, guide) already has the real value.
    _playerGuideStyle = PlayerGuideStyle.fromPref(
      await IptvAppearanceStorage.getIptvPlayerGuideStyle(),
    );
    _playerGuideTokens = PlayerGuideTokens.of(_playerGuideStyle);

    if (PlatformUtil.isTvOS) {
      _tvosForceSoftwareDecode =
          await PlayerSettingsStorage.getTvosForceSoftwareDecode();
      _contentDisplayMatchMode =
          await PlayerNetworkStorage.getContentDisplayMatchMode();
      if (!_contentDisplayMatchMode.requestsMatching) {
        try {
          await TvosDisplayMatchService.clear();
        } catch (error) {
          debugPrint('DisplayMatch: tvOS clear failed: $error');
        }
      }
    }

    // Audio-output settings, preloaded for [_configurePlayerAudio] — the
    // single owner of ao / audio-spdif / audio-channels
    // (AUDIO_FIDELITY_PLAN.md).
    if (!kIsWeb && Platform.isAndroid) {
      _audioPassthroughEnabled =
          await PlayerSettingsStorage.getAudioPassthroughEnabled();
      _systemAudioEffectsEnabled =
          await PlayerSettingsStorage.getPlayerSystemAudioEffects();
    } else if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile) {
      _appleMultichannelEnabled =
          await PlayerSettingsStorage.getAppleMultichannelAudio();
    }
    if (PlatformUtil.isTvOS) {
      _tvosForceStereoAudio =
          await PlayerSettingsStorage.getTvosForceStereoAudio();
      _tvosLegacyAudioOutput =
          await PlayerSettingsStorage.getTvosLegacyAudioOutput();
      // What the CURRENT output route can take. ao_avfoundation passes the
      // file's native layout through, so a 5.1 track on a two-channel route
      // (AirPods, Bluetooth, stereo TV) folds badly; PlayerAudioConfig caps
      // those to stereo. 0 means "unknown" and leaves mpv's default alone.
      try {
        _tvosRouteOutputChannels =
            await _tvReleaseLogChannel.invokeMethod<int>(
              'outputChannelCount',
            ) ??
            0;
      } catch (_) {
        _tvosRouteOutputChannels = 0;
      }
    }

    debugPrint('VideoPlayer: Loaded defaults - aspect=${_display.aspectMode}');
  }

  /// Overlays inside the player share its route scope, which already has a
  /// focused child (the player root) — so their `autofocus` is silently
  /// discarded and the first OK does nothing. Releasing the current focus as
  /// the overlay appears lets its autofocus node claim it.
  void _tvReleaseFocusForOverlay() {
    if (!PlatformUtil.isTelevision) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Show channel guide overlay
  void _showChannelGuideOverlay() {
    if (_channelEntries.isEmpty) {
      debugPrint('Player: No channels available for guide');
      return;
    }
    _iptvBanner.hideIptvZapBanner();
    setState(() {
      _showChannelGuide = true;
      _controlsVisible.value = false;
    });
  }

  /// Hide channel guide overlay
  void _hideChannelGuideOverlay() {
    setState(() {
      _showChannelGuide = false;
    });
  }

  // ── Live channel zapping ─────────────────────────────────────────────────
  //
  // Port of the native player's zap ladder (`zapIptvChannel`): step inside the
  // loaded window, page through the rest of the category at the window's
  // edges, and cross into the adjacent category when the category itself runs
  // out — wrapping at the last one. The browse provider already speaks this
  // protocol (native drove it), so the only thing this side has to carry is
  // where the window sits and what is already on its way.
  //
  // One deliberate divergence: native trims its hidden window to 600 rows to
  // keep a TV's adapter light, and re-fetches what it dropped. Here the same
  // list backs the guide, which has no scroll-prefetch to refill it, so
  // trimming would silently shrink the guide instead.

  /// Page size asked of the browse provider. It clamps to its own per-launch
  /// maximum, so drift here changes only how many rows arrive, never
  /// correctness: an overlapping backward page merges, a short one just
  /// leaves more to fetch.
  static const int _kIptvZapPageSize = 1500;

  /// Absolute position, within the active category, of the first channel of
  /// [_effectiveIptvChannels].
  int _iptvZapWindowOffset = 0;

  /// How many channels the active category holds in total; the window is a
  /// slice of it.
  int _iptvZapCategoryTotal = 0;

  /// The ring came from a paged response, so [_iptvZapWindowOffset] and
  /// [_iptvZapCategoryTotal] describe it. False for the launch window or a
  /// browse result standing in — zapping then just wraps inside the list,
  /// which is what native does before its paging session starts.
  bool _iptvZapPagingActive = false;
  String? _iptvZapCategory;
  List<String> _iptvZapCategories = const [];
  bool _iptvZapRequestInFlight = false;

  /// Presses that arrived while a page was loading. Crossing a page or a
  /// category is a round trip, so holding the key down has to queue rather
  /// than drop.
  final List<int> _iptvZapPendingInputs = [];

  /// Monotonic ticket for IPTV channel switches. The Stremio candidate ladder
  /// can hold [_switchToIptvChannel] open for many seconds; a newer switch
  /// must strand the older one (no opens, no winner marks) or an abandoned
  /// ladder would hijack playback back to its channel.
  int _iptvSwitchTicket = 0;

  /// The stremio-tv:// key of the IPTV channel currently playing, when it is
  /// a Stremio-addon channel — non-null routes source-sheet selections down
  /// the live path instead of the movie source-switch pipeline.
  String? _iptvChannelKey;

  /// Suppresses [_onIptvStreamError] for errors that aren't the tuned
  /// channel's to own. Set for the whole of [_switchToIptvChannel] and
  /// cleared the moment the new media is actually opened, because until then
  /// mpv is still draining the OUTGOING channel — while [_currentIptvIndex]
  /// already points at the new one, so a report would blame the wrong
  /// channel. A Stremio ladder stays muted throughout: dead candidates are
  /// normal there and it reports for itself.
  bool _iptvErrorsMuted = false;

  /// mpv reports a failed stream as several errors in a row; only the first of
  /// a burst is worth a message. Cleared on every zap so each channel the user
  /// tries can report once — collapsing a burst must not silence the next
  /// channel's genuine failure.
  DateTime? _lastIptvErrorShown;

  /// Switch to IPTV channel at given index
  /// The IPTV channel currently playing, or null
  /// when not in an IPTV context or the index is out of range.
  IptvChannel? get _currentIptvChannel {
    final chans = _effectiveIptvChannels;
    if (chans == null ||
        _currentIptvIndex < 0 ||
        _currentIptvIndex >= chans.length) {
      return null;
    }
    return chans[_currentIptvIndex];
  }

  /// Next/Previous (and end-of-episode auto-advance) are scoped to an Xtream
  /// SERIES episode list — NOT every non-live IPTV item. A plain Movies-grid
  /// play also passes iptvChannels, and advancing to the next unrelated movie
  /// (or showing Next/Prev on it) would be a regression; those keep the channel
  /// sheet only, exactly as before. [_isIptvSeriesContext] gates on the
  /// series_id the launcher stamps onto episode channels.
  bool get _hasIptvNext =>
      _isIptvSeriesContext &&
      _currentIptvIndex + 1 < (_effectiveIptvChannels?.length ?? 0);

  bool get _hasIptvPrevious =>
      _isIptvSeriesContext && _currentIptvIndex - 1 >= 0;

  /// True only for an Xtream SERIES episode — the launcher stamps `series_id`
  /// (+ `series_playlist_id`) into the channel's attributes. Audio-language
  /// memory is scoped to this: a plain VOD / catchup single item (non-live but
  /// not a series) gets the normal default-language handling, not per-series
  /// carry-over.
  bool get _isIptvSeriesContext {
    final ch = _currentIptvChannel;
    if (ch == null || ch.isLive) return false;
    return (ch.attributes['series_id'] ?? '').isNotEmpty;
  }

  /// Opens one VOD candidate with the real media-kit player and keeps that
  /// exact player session on success. Unlike the old Dart HEAD probe this has
  /// no validation/playback race: decoded video or advancing position commits
  /// the candidate; an error, open throw, or bounded startup stall rejects it.
  /// Debrid-resolved candidates skip the decode probe. The debrid API minted
  /// (and thereby vouched for) the URL moments ago, so the probe's dead-link
  /// protection is redundant — and its cost is real: committing on the first
  /// decoded frame means the resume seek lands mid-startup-burst at 0, which
  /// mpv on a cold stream answers by restarting (the masked-seek repro).
  /// A plain open instead accepts on duration (header metadata, pre-decode),
  /// so the resume seek folds into startup as "begin here" — the pre-ladder
  /// timing that always worked. Addon direct URLs (the stale-cached-link
  /// class the probe exists for) keep the full validation.
  Future<bool> _openStartupDebridDirect(
    String url, {
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final stopwatch = Stopwatch()..start();
    final completer = Completer<bool>();
    var candidateDuration = Duration.zero;
    var bufferedAmount = Duration.zero;
    final sourceFields = _startupSourceFields(sourceIndex, source);
    debugPrint(
      '[StartupFailover] event=candidate_open platform=flutter '
      'attempt=$attempt/$maxAttempts $sourceFields route=debrid_direct '
      'timeoutMs=${timeout.inMilliseconds}',
    );
    void finish(bool ok, String reason) {
      if (completer.isCompleted) return;
      debugPrint(
        '[StartupFailover] event=candidate_result platform=flutter '
        'attempt=$attempt/$maxAttempts $sourceFields ok=$ok reason=$reason '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'durationMs=${candidateDuration.inMilliseconds}',
      );
      completer.complete(ok);
    }

    // A dead debrid link (deleted torrent race, expired token) errors or
    // serves something with no parseable duration — either way the ladder
    // advances to the next candidate exactly like a failed probe.
    final subs = <StreamSubscription>[
      _player.stream.error.listen((error) {
        if (AndroidRendererStartupFallback.isRendererFailure(error) &&
            AndroidRendererStartupFallback.shouldArm(
              isAndroid: Platform.isAndroid,
              isAndroidTv: PlatformUtil.isAndroidTvCached,
              mode: _androidVideoRendererMode,
              alreadyValidated: _rendererValidatedForSession,
              fallbackInProgress: _rendererFallbackInProgress,
            )) {
          // Renderer-bound failure, owned by the renderer fallback — same
          // contract as the probe path (see _tryOpenStartupVod).
          finish(true, 'renderer_fallback_deferred');
          return;
        }
        finish(false, 'player_error');
      }),
      _player.stream.duration.listen((value) {
        candidateDuration = value;
        if (value > Duration.zero) finish(true, 'duration_known');
      }),
      // Durationless media (some MPEG-TS/M2TS and non-seekable progressive
      // files) never publishes a duration — accept on decoded, advancing
      // video like the probe would, or the watchdog eventually kills a
      // stream that is visibly playing. Duration almost always arrives
      // first, so this fallback does not delay the common case.
      _player.stream.width.listen((width) {
        if ((width ?? 0) > 0 && _player.state.position > Duration.zero) {
          finish(true, 'decoded_video');
        }
      }),
      _player.stream.position.listen((value) {
        if (value > Duration.zero && (_player.state.width ?? 0) > 0) {
          finish(true, 'decoded_video');
        }
      }),
      _player.stream.buffer.listen((value) {
        bufferedAmount = value;
      }),
    ];
    try {
      await _openMedia(
        mk.Media(url, httpHeaders: httpHeaders),
        play: true,
        source: source,
      );
    } catch (e) {
      debugPrint(
        '[StartupFailover] event=open_exception platform=flutter '
        '$sourceFields exception=${e.runtimeType}',
      );
      finish(false, 'open_exception');
    }
    // Same slow-versus-dead distinction as the probe path: a link whose
    // buffer keeps growing is downloading, not dead — failing it would burn
    // a possibly single-use debrid link. Extend in steps up to the same cap.
    const extendStep = Duration(seconds: 3);
    const maxWait = Duration(seconds: 45);
    var lastBufferMark = Duration.zero;
    var ok = false;
    while (true) {
      final remaining = timeout - stopwatch.elapsed;
      try {
        ok = await completer.future.timeout(
          remaining > Duration.zero ? remaining : extendStep,
        );
        break;
      } on TimeoutException {
        if (bufferedAmount > lastBufferMark && stopwatch.elapsed < maxWait) {
          lastBufferMark = bufferedAmount;
          debugPrint(
            '[StartupFailover] event=watchdog_extend platform=flutter '
            '$sourceFields elapsedMs=${stopwatch.elapsedMilliseconds} '
            'bufferedMs=${bufferedAmount.inMilliseconds}',
          );
          continue;
        }
        finish(false, 'timeout');
        ok = false;
        break;
      }
    }
    for (final sub in subs) {
      unawaited(sub.cancel());
    }
    if (!ok) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    return ok;
  }

  Future<bool> _tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  }) async {
    final stopwatch = Stopwatch()..start();
    final completer = Completer<bool>();
    var armed = false;
    var videoWidth = 0;
    var position = Duration.zero;
    var candidateDuration = Duration.zero;
    Timer? durationGraceTimer;
    final isAioStreams = StartupStreamPolicy.isAioStreams(
      addonId: source?.stremioAddonId,
      sourceName: source?.source,
      url: url,
    );
    final sourceFields = _startupSourceFields(sourceIndex, source);
    debugPrint(
      '[StartupFailover] event=candidate_open platform=flutter '
      'attempt=$attempt/$maxAttempts $sourceFields aio=$isAioStreams '
      'timeoutMs=${timeout.inMilliseconds}',
    );
    void finish(bool ok, String reason) {
      if (completer.isCompleted) return;
      debugPrint(
        '[StartupFailover] event=candidate_result platform=flutter '
        'attempt=$attempt/$maxAttempts $sourceFields ok=$ok reason=$reason '
        'elapsedMs=${stopwatch.elapsedMilliseconds} width=$videoWidth '
        'positionMs=${position.inMilliseconds} '
        'durationMs=${candidateDuration.inMilliseconds}',
      );
      completer.complete(ok);
    }

    void maybeCommit() {
      // Width alone can be parsed from container metadata before a decoder has
      // produced anything. Requiring the media clock to advance as well keeps
      // metadata-only and permanently-buffering candidates behind the gate.
      if (!armed || videoWidth <= 0 || position <= Duration.zero) return;
      if (StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
        addonId: source?.stremioAddonId,
        sourceName: source?.source,
        url: url,
        duration: candidateDuration,
      )) {
        finish(false, 'aiostreams_error_slate');
        return;
      }
      if (isAioStreams && candidateDuration <= Duration.zero) {
        // Progressive sources can publish duration just after playback starts.
        // Give that metadata a bounded chance to expose AIOStreams' short,
        // decodable error slate; unknown-duration real streams still proceed.
        durationGraceTimer ??= Timer(const Duration(seconds: 1), () {
          final isSlate = StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
            addonId: source?.stremioAddonId,
            sourceName: source?.source,
            url: url,
            duration: candidateDuration,
          );
          finish(
            !isSlate,
            isSlate ? 'aiostreams_error_slate' : 'decoded_video',
          );
        });
        return;
      }
      finish(true, 'decoded_video');
    }

    var bufferedAmount = Duration.zero;
    final subs = <StreamSubscription>[
      _player.stream.error.listen((error) {
        if (!armed) return;
        // An explicit-renderer startup failure is owned by the renderer
        // fallback (_rendererStartupErrorSub sees this same event): it
        // disposes and rebuilds the player, then reopens THIS media on the
        // automatic renderer. Failing the candidate here would race two
        // opens on one surface — the ladder advancing on a player being
        // disposed — and the failure is renderer-bound, not source-bound,
        // so every other candidate would fail identically anyway. Accept
        // the candidate and let the fallback finish its recovery.
        if (AndroidRendererStartupFallback.isRendererFailure(error) &&
            AndroidRendererStartupFallback.shouldArm(
              isAndroid: Platform.isAndroid,
              isAndroidTv: PlatformUtil.isAndroidTvCached,
              mode: _androidVideoRendererMode,
              alreadyValidated: _rendererValidatedForSession,
              fallbackInProgress: _rendererFallbackInProgress,
            )) {
          finish(true, 'renderer_fallback_deferred');
          return;
        }
        finish(false, 'player_error');
      }),
      _player.stream.width.listen((width) {
        videoWidth = width ?? 0;
        maybeCommit();
      }),
      _player.stream.position.listen((value) {
        position = value;
        maybeCommit();
      }),
      _player.stream.duration.listen((value) {
        candidateDuration = value;
        maybeCommit();
      }),
      _player.stream.buffer.listen((value) {
        bufferedAmount = value;
      }),
    ];
    try {
      // Arm at the final open boundary, after setup and authorization. Old
      // candidate events during those awaits must not validate this source.
      await _openMedia(
        mk.Media(url, httpHeaders: httpHeaders),
        play: true,
        source: source,
        beforeOpen: () {
          armed = true;
          return true;
        },
      );
    } catch (e) {
      // Exception strings from media backends may embed signed stream URLs.
      // The runtime type is enough to distinguish open failures safely.
      debugPrint(
        '[StartupFailover] event=open_exception platform=flutter '
        '$sourceFields exception=${e.runtimeType}',
      );
      finish(false, 'open_exception');
    }
    // The base timeout is for dead sources (no error, no data). A source
    // that is demonstrably still downloading — its buffer keeps growing —
    // is slow, not dead (large 4K remux, cold CDN, slow debrid peering);
    // failing it would burn a possibly single-use link and fall to a
    // lower-ranked source. Extend in short steps while bytes keep arriving,
    // bounded by a hard cap.
    const extendStep = Duration(seconds: 3);
    const maxWait = Duration(seconds: 45);
    var lastBufferMark = Duration.zero;
    var ok = false;
    while (true) {
      final remaining = timeout - stopwatch.elapsed;
      try {
        ok = await completer.future.timeout(
          remaining > Duration.zero ? remaining : extendStep,
        );
        break;
      } on TimeoutException {
        if (bufferedAmount > lastBufferMark && stopwatch.elapsed < maxWait) {
          lastBufferMark = bufferedAmount;
          debugPrint(
            '[StartupFailover] event=watchdog_extend platform=flutter '
            '$sourceFields elapsedMs=${stopwatch.elapsedMilliseconds} '
            'bufferedMs=${bufferedAmount.inMilliseconds}',
          );
          continue;
        }
        finish(false, 'timeout');
        ok = false;
        break;
      }
    }
    durationGraceTimer?.cancel();
    for (final sub in subs) {
      unawaited(sub.cancel());
    }
    if (!ok) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    return ok;
  }

  /// Startup-only automatic failover for Stremio/Quick Play VOD. Candidates
  /// remain behind the player loading surface until the actual player decodes
  /// one. The successful URL is never reopened, which is essential for
  /// single-use and first-request-IP-bound debrid links.
  Future<bool> _openInitialVodWithFailover(
    String initialUrl, {
    Map<String, String>? httpHeaders,
    bool initialAttemptAlreadyFailed = false,
  }) async {
    final sources = _effectiveSources;
    final contentType = _effectiveContentType;
    final isVod = contentType == 'movie' || contentType == 'series';
    if (!isVod) {
      debugPrint(
        '[StartupFailover] event=bypass platform=flutter reason=non_vod '
        'contentType=${contentType ?? 'unknown'}',
      );
      return _tryOpenStartupVod(initialUrl, httpHeaders: httpHeaders);
    }

    _setStartupGateActive(true);
    if (sources == null || sources.isEmpty) {
      debugPrint(
        '[StartupFailover] event=begin platform=flutter contentType=$contentType '
        'sourceCount=0 policy=single_candidate',
      );
      final ok = await _tryOpenStartupVod(initialUrl, httpHeaders: httpHeaders);
      // A successful candidate stays gated through resume/track restoration
      // in the caller. Failure must release the surface before route cleanup.
      if (!ok) _setStartupGateActive(false);
      return ok;
    }

    final rules = widget.startupFailoverEnabled
        ? await QuickPlayStorage.getQuickPlayRules(
            isMovie: contentType == 'movie',
          )
        : null;
    final tryNext = rules?.tryNextOnFailure ?? false;
    final maxAttempts = tryNext ? rules!.maxAttempts.clamp(1, 10) : 1;
    final firstIndex = _currentSourceIndex.clamp(0, sources.length - 1);
    final start = StartupStreamPolicy.rankedFailoverStart(
      selectedSourceIndex: firstIndex,
      initialAttemptAlreadyFailed: initialAttemptAlreadyFailed,
    );
    var attempts = start.attempts;
    debugPrint(
      '[StartupFailover] event=begin platform=flutter contentType=$contentType '
      'sourceCount=${sources.length} selectedIndex=$firstIndex '
      'startIndex=${start.sourceIndex} initialFailed=$initialAttemptAlreadyFailed '
      'tryNext=$tryNext maxAttempts=$maxAttempts '
      'targetSeason=${_effectiveContentSeason ?? '-'} '
      'targetEpisode=${_effectiveContentEpisode ?? '-'}',
    );

    final pikPakResolver =
        widget.startupResolverProvider?.toLowerCase() == 'pikpak';
    var pikPakTorrentAcquisitionAttempted =
        StartupStreamPolicy.initialPikPakAcquisitionAttempted(
          isPikPakResolver: pikPakResolver,
          initialSourceIsTorrent:
              sources[firstIndex].streamType == StreamType.torrent,
          hasResolvedInitialUrl: initialUrl.isNotEmpty,
          initialAttemptAlreadyFailed: initialAttemptAlreadyFailed,
        );

    for (
      var sourceIndex = start.sourceIndex;
      sourceIndex < sources.length && attempts < maxAttempts;
      sourceIndex++
    ) {
      final source = sources[sourceIndex];
      // The launch URL is already resolved and playable in-app regardless of
      // how its source row is typed — never skip it over streamType.
      final isResolvedLaunchUrl =
          sourceIndex == firstIndex && initialUrl.isNotEmpty;
      if (!isResolvedLaunchUrl && source.streamType == StreamType.externalUrl) {
        debugPrint(
          '[StartupFailover] event=candidate_skip platform=flutter '
          '${_startupSourceFields(sourceIndex, source)} reason=external_url',
        );
        continue;
      }
      if (pikPakResolver &&
          !isResolvedLaunchUrl &&
          source.streamType == StreamType.torrent) {
        if (pikPakTorrentAcquisitionAttempted) {
          debugPrint(
            '[StartupFailover] event=candidate_skip platform=flutter '
            '${_startupSourceFields(sourceIndex, source)} '
            'reason=pikpak_acquisition_limit',
          );
          continue;
        }
        // Count the acquisition before resolving: a cold-storage request may
        // have been queued even when the resolver ultimately returns null.
        pikPakTorrentAcquisitionAttempted = true;
      }
      attempts++;
      final sourceFields = _startupSourceFields(sourceIndex, source);
      // A debrid-direct first open isn't "checking" anything — it's loading
      // the user's own source; say so. Failover retries keep the counter
      // (the ladder really is trying alternatives at that point).
      final firstAttempt = attempts == 1 && !initialAttemptAlreadyFailed;
      final debridFirstOpen =
          firstAttempt &&
          !pikPakResolver &&
          source.streamType == StreamType.torrent;
      if (_startupGateOverlayHidden != debridFirstOpen) {
        _startupGateOverlayHidden = debridFirstOpen;
        if (mounted) setState(() {});
      }
      _setStartupGateMessage(
        debridFirstOpen
            ? 'Loading stream…'
            : firstAttempt
            ? 'Checking stream 1 of $maxAttempts…'
            : 'Stream unavailable · Trying $attempts of $maxAttempts…',
      );

      String? url;
      List<PlaylistEntry>? resolvedPlaylist;
      var resolvedPlaylistIndex = 0;
      if (isResolvedLaunchUrl) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=launch_url',
        );
        url = initialUrl;
      } else if (source.streamType == StreamType.directUrl &&
          source.directUrl?.isNotEmpty == true) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=direct_url',
        );
        url = source.directUrl;
      } else if (widget.resolveSourceToPlaylist != null) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=playlist',
        );
        try {
          resolvedPlaylist = await widget.resolveSourceToPlaylist!(
            source,
            canContinue: () => mounted && !_screenDisposed,
          );
        } catch (e) {
          debugPrint(
            '[StartupFailover] event=resolve_result platform=flutter '
            '$sourceFields ok=false reason=exception exception=${e.runtimeType}',
          );
          resolvedPlaylist = null;
        }
        if (resolvedPlaylist != null && resolvedPlaylist.isNotEmpty) {
          if (StartupStreamPolicy.requiresExactEpisodeMatch(
                isSeries: contentType == 'series',
                playlistLength: resolvedPlaylist.length,
              ) &&
              _effectiveContentSeason != null &&
              _effectiveContentEpisode != null) {
            final parsed = SeriesPlaylist.fromPlaylistEntries(
              resolvedPlaylist,
              collectionTitle: widget.title,
              forceSeries: true,
            );
            final target = parsed.findOriginalIndexBySeasonEpisode(
              _effectiveContentSeason!,
              _effectiveContentEpisode!,
            );
            final exactIndex = StartupStreamPolicy.resolvedPlaylistIndex(
              requiresEpisodeMatch: true,
              matchedEpisodeIndex: target,
            );
            if (exactIndex == null) {
              // A pack that omits the requested episode is not a valid
              // fallback. Opening row zero would silently play the wrong
              // episode and then adopt that unrelated playlist.
              resolvedPlaylist = null;
              debugPrint(
                '[StartupFailover] event=candidate_reject platform=flutter '
                '$sourceFields reason=playlist_missing_episode '
                'targetSeason=$_effectiveContentSeason '
                'targetEpisode=$_effectiveContentEpisode',
              );
              continue;
            }
            resolvedPlaylistIndex = exactIndex;
          }
          url = resolvedPlaylist[resolvedPlaylistIndex].url;
        }
      } else if (_effectiveResolver != null) {
        debugPrint(
          '[StartupFailover] event=resolve platform=flutter attempt=$attempts/$maxAttempts '
          '$sourceFields route=single_url',
        );
        try {
          url = await _effectiveResolver!(source);
        } catch (e) {
          debugPrint(
            '[StartupFailover] event=resolve_result platform=flutter '
            '$sourceFields ok=false reason=exception exception=${e.runtimeType}',
          );
          url = null;
        }
      }

      if (url == null || url.isEmpty) {
        debugPrint(
          '[StartupFailover] event=candidate_reject platform=flutter '
          '$sourceFields reason=empty_resolution',
        );
        continue;
      }
      // Debrid-resolved torrents bypass the decode probe (see
      // _openStartupDebridDirect); addon direct URLs keep it, and so do
      // PikPak sessions — cold-storage opens are the slowest in the app and
      // have their own readiness needs.
      final isDebridResolved =
          !pikPakResolver && source.streamType == StreamType.torrent;
      final candidateHeaders = isResolvedLaunchUrl
          ? httpHeaders
          : resolvedPlaylist != null
          ? resolvedPlaylist[resolvedPlaylistIndex].httpHeaders
          : source.httpHeaders;
      final ok = isDebridResolved
          ? await _openStartupDebridDirect(
              url,
              httpHeaders: candidateHeaders,
              source: source,
              sourceIndex: sourceIndex,
              attempt: attempts,
              maxAttempts: maxAttempts,
            )
          : await _tryOpenStartupVod(
              url,
              httpHeaders: candidateHeaders,
              source: source,
              sourceIndex: sourceIndex,
              attempt: attempts,
              maxAttempts: maxAttempts,
            );
      if (!mounted) return false;
      if (!ok) continue;

      _activeHttpHeaders = candidateHeaders;

      _currentSourceIndex = sourceIndex;
      _currentStreamUrl = url;
      if (resolvedPlaylist != null && resolvedPlaylist.isNotEmpty) {
        _activePlaylist = resolvedPlaylist;
        _currentIndex = resolvedPlaylistIndex;
        _cachedSeriesPlaylist = null;
        _playlistIdentityToken++;
      }
      unawaited(_commitValidatedStremioSource(source));
      debugPrint(
        '[StartupFailover] event=commit platform=flutter '
        'attempt=$attempts/$maxAttempts $sourceFields '
        'playlistItems=${resolvedPlaylist?.length ?? 0} '
        'playlistIndex=$resolvedPlaylistIndex',
      );
      return true;
    }
    _setStartupGateActive(false);
    debugPrint(
      '[StartupFailover] event=exhausted platform=flutter '
      'attempts=$attempts maxAttempts=$maxAttempts sourceCount=${sources.length}',
    );
    return false;
  }

  Future<void> _commitValidatedStremioSource(Torrent? source) async {
    if (identical(source, _openedWatchSource)) {
      _serverWatch.commit(source);
    }
    logSourceSelection(
      'player_source_committed',
      source: source,
      index: _currentSourceIndex,
      player: 'mpv',
    );
    final commit = widget.onStremioSourceCommitted;
    if (source == null || commit == null) return;
    try {
      await commit(source);
    } catch (error) {
      debugPrint(
        '[StartupFailover] event=binding_commit_failed platform=flutter '
        'exception=${error.runtimeType}',
      );
    }
  }

  String _startupSourceFields(int? index, Torrent? source) {
    String safe(String? value) {
      if (value == null || value.isEmpty) return '-';
      final compact = value.replaceAll(RegExp(r'\s+'), ' ');
      return compact.length <= 64 ? compact : compact.substring(0, 64);
    }

    return 'sourceIndex=${index ?? '-'} type=${source?.streamType.name ?? '-'} '
        'addon=${safe(source?.stremioAddonId)} source=${safe(source?.source)}';
  }

  void _setStartupGateActive(bool active) {
    if (_startupGateActive == active) return;
    _startupGateActive = active;
    if (!active) _startupGateOverlayHidden = false;
    if (mounted) setState(() {});
  }

  void _setStartupGateMessage(String message) {
    if (_startupGateMessage == message) return;
    _startupGateMessage = message;
    if (mounted && _startupGateActive) setState(() {});
  }

  // ─── Stremio Source Sheet ───────────────────────────────────────────

  void _showSourceSheetOverlay() {
    final sources = _effectiveSources;
    if (sources == null || sources.isEmpty) return;
    _iptvBanner.hideIptvZapBanner();
    setState(() {
      _showSourceSheet = true;
      _controlsVisible.value = false;
    });
  }

  void _hideSourceSheet() {
    _sourcePlaylistResolution++;
    setState(() {
      _showSourceSheet = false;
    });
  }

  Future<String?> Function(Torrent) _buildSourceSheetResolver() {
    if (widget.resolveSourceToPlaylist != null) {
      return (Torrent torrent) async {
        final generation = ++_sourcePlaylistResolution;
        bool active() =>
            mounted &&
            !_screenDisposed &&
            _showSourceSheet &&
            generation == _sourcePlaylistResolution;
        final playlist = await widget.resolveSourceToPlaylist!(
          torrent,
          canContinue: active,
        );
        if (!active() || playlist == null || playlist.isEmpty) return null;
        _pendingSourcePlaylist = playlist;
        final firstUrl = playlist.first.url;
        return firstUrl.isNotEmpty ? firstUrl : null;
      };
    }
    return _effectiveResolver!;
  }

  Future<void> _handleSourceSelected(int index, String url) async {
    // Picking a source aborts the landing verifier — it must not re-issue the
    // old target against the replacement stream (that could even trip the
    // validator's position gate). The GUARD deliberately stays armed: the
    // switch paths below checkpoint the outgoing position, and that save must
    // still be protected (they substitute the held target where needed).
    _resumeVerifyEpoch++;
    // Live IPTV channel: the movie pipeline below seeks to the previous
    // position and reloads subtitles — both meaningless (and harmful) for a
    // live stream. Route to the dedicated live switch instead.
    if (_iptvChannelKey != null) {
      await _iptvSwitch.switchToIptvSource(index, url);
      return;
    }
    final pendingPlaylist = _pendingSourcePlaylist;
    _pendingSourcePlaylist = null;
    if (pendingPlaylist != null && pendingPlaylist.isNotEmpty) {
      await _switchToSourcePlaylist(
        index,
        pendingPlaylist,
        validateExplicitSelection: true,
      );
    } else {
      await _switchToStremioSource(index, url);
    }
  }

  Future<bool> _switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
    bool suppressResume = false,
    EpisodePlaybackRequest? request,
  }) async {
    if (request == null) _episodeNavigationGeneration++;
    if (request?.isCurrent == false) return false;
    _hideSourceSheet();
    _clearBufferingIndicator();
    final outgoingPlaylist = _activePlaylist == null
        ? null
        : List<PlaylistEntry>.of(_activePlaylist!);
    final outgoingIndex = _currentIndex;
    final outgoingCachedSeries = _cachedSeriesPlaylist;
    final outgoingSourceIndex = _currentSourceIndex;
    // If a startup resume never landed, the live position is a restart
    // artifact — carry the HELD target across the switch (and into the
    // failure-restore path) so the new source opens at the bookmark, not ~0.
    // Pure query: the guard itself stays armed for the checkpoint save below.
    final outgoingHeldMs = _resumeWriteGuard.heldTargetIfBlocked(
      _position.inMilliseconds,
    );
    final outgoingPosition = outgoingHeldMs != null
        ? Duration(milliseconds: outgoingHeldMs)
        : _position;
    final outgoingDirectUrl = _currentStreamUrl;
    final outgoingHeaders = _activeHttpHeaders;
    final selectedSource =
        (_effectiveSources != null &&
            sourceIndex >= 0 &&
            sourceIndex < _effectiveSources!.length)
        ? _effectiveSources![sourceIndex]
        : null;
    // Capture the episode we're on BEFORE swapping the playlist, so we can
    // land on it in the new source instead of jumping to the pack's first
    // entry (S1E1). Read from the current playlist entry (tracks auto-advance).
    // An episode-guide fetch targets a DIFFERENT episode: land there instead.
    final current = _traktSeasonEpisode();
    final explicitTarget = targetSeason != null && targetEpisode != null;
    final se = explicitTarget
        ? (season: targetSeason, episode: targetEpisode)
        : current;
    // Checkpoint the OUTGOING episode now, while _activePlaylist/_currentIndex
    // still point at it — after the swap the index would resolve against the
    // new playlist. _loadPlaylistIndex below is told to skip its own save.
    await _resumeSave.saveResume();
    if (!mounted || request?.isCurrent == false) return false;
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
    });
    _startTransitionOverlay();
    try {
      await _player.pause();
    } catch (_) {}
    if (!mounted || request?.isCurrent == false) return false;

    // Replace playlist and invalidate series cache. A source/episode switch
    // stays within the same show, so the full TVMaze episode list carries
    // over — without it, guide adjacency and the full episode sheet would go
    // dark until another TVMaze fetch succeeds (never, when offline).
    final outgoingSeries = _seriesPlaylist ?? _syntheticGuidePlaylist;
    final carriedGuide = outgoingSeries?.fullTvmazeEpisodes.isNotEmpty == true
        ? outgoingSeries!.fullTvmazeEpisodes
        : null;
    final carriedImdbId = outgoingSeries?.imdbId ?? _currentSeriesImdbId;
    final carriedTvmazeShowId = outgoingSeries?.tvmazeShowId;
    final carriedTvmazeShowName = outgoingSeries?.tvmazeShowName;
    final carriedPosterUrl = outgoingSeries?.showPosterUrl;
    void replacePlaylist() => setState(() {
      _currentSourceIndex = sourceIndex;
      _activePlaylist = newPlaylist;
      _cachedSeriesPlaylist = null;
      _playlistIdentityToken++;
    });
    if (request != null) {
      if (!request.replacePlaylist(replacePlaylist)) return false;
    } else {
      replacePlaylist();
    }
    final rebuilt = _seriesPlaylist;
    if (rebuilt != null) {
      rebuilt.imdbId ??= carriedImdbId;
      rebuilt.tvmazeShowId ??= carriedTvmazeShowId;
      rebuilt.tvmazeShowName ??= carriedTvmazeShowName;
      rebuilt.showPosterUrl ??= carriedPosterUrl;
      if (carriedGuide != null &&
          carriedGuide.isNotEmpty &&
          rebuilt.fullTvmazeEpisodes.isEmpty) {
        rebuilt.fullTvmazeEpisodes = carriedGuide;
      }
      _episodeMetadataReady = _preloadEpisodeInfo();
    }

    // Resume the SAME episode from the new source (a season/complete pack would
    // otherwise restart at S1E1); _loadPlaylistIndex restores its saved
    // position.
    var targetIndex = 0;
    // Whether the new source landed on the SAME content we were watching — only
    // then does "prefer the checkpointed local position over Trakt" apply. When
    // we fall back to a different episode, its own Trakt resume must still work.
    // An explicit episode-guide target is different content by definition.
    var landedOnSameContent =
        !explicitTarget ||
        (targetSeason == current.season && targetEpisode == current.episode);
    var containsRequestedEpisode = true;
    if (se.season != null && se.episode != null) {
      final sp = _seriesPlaylist;
      final idx =
          sp?.findOriginalIndexBySeasonEpisode(se.season!, se.episode!) ?? -1;
      if (idx >= 0) {
        targetIndex = idx;
      } else if (newPlaylist.length == 1) {
        // A single resolved stream often has an unparseable name ("Torrentio
        // 1080p", anime/absolute numbering); its one entry IS the requested
        // episode — the fetch was episode-scoped. This must hold for manual
        // sheet picks too (no explicit target), or a legitimate singleton
        // would be rejected below without ever being opened. Mirrors the
        // Kotlin cursor's `episodes.size <= 1` exemption.
        targetIndex = 0;
      } else {
        landedOnSameContent = false;
        containsRequestedEpisode = false;
        // The exact episode isn't in this source. Don't fall back to raw entry
        // 0 — in torrent order that's often an extras/bonus clip. Land on the
        // first REAL episode (skips season 0 / specials) and warn the user.
        final firstReal = sp?.getFirstEpisodeOriginalIndex() ?? -1;
        if (firstReal >= 0) targetIndex = firstReal;
        if (mounted && !validateExplicitSelection) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'S${se.season}E${se.episode} not in this source — playing from the start',
              ),
            ),
          );
        }
      }
    }
    // A source switch must resume the outgoing episode's position (saved above).
    // Clear any lingering manual-selection state first: if the user had manually
    // jumped to an episode within the last 30s, that stale flag makes
    // `_maybeRestoreResume` bail out and the new source opens at 0:00 instead of
    // resuming. The switch is not a "manual episode pick", so drop the flag.
    _isManualEpisodeSelection = false;
    _allowResumeForManualSelection = false;
    // Resume the checkpointed LOCAL position, not Trakt (this is a source swap
    // mid-episode, not a fresh open) — but only when the new source landed on
    // the same content; a fallback episode keeps its own Trakt resume.
    var committed = false;
    if (!validateExplicitSelection) {
      try {
        committed = await _loadPlaylistIndex(
          targetIndex,
          autoplay: true,
          skipInitialSave: true,
          preferLocalResume: landedOnSameContent,
          suppressResume: suppressResume,
          request: request,
        );
      } catch (error) {
        if (request == null) rethrow;
        debugPrint('Episode source load failed: $error');
        committed = false;
      }
    } else {
      _manualSourceGateActive = true;
      try {
        try {
          if (containsRequestedEpisode) {
            committed = await _loadPlaylistIndex(
              targetIndex,
              autoplay: true,
              skipInitialSave: true,
              preferLocalResume: landedOnSameContent,
              suppressResume: suppressResume,
              request: request,
              manualValidationSource: selectedSource,
              manualValidationSourceIndex: sourceIndex,
            );
          }
        } catch (error) {
          debugPrint(
            'Player: manual playlist source rejected '
            '(${error.runtimeType})',
          );
          committed = false;
        }
        if (!mounted || request?.isCurrent == false) return false;
        if (!committed &&
            outgoingPlaylist != null &&
            outgoingPlaylist.isNotEmpty) {
          setState(() {
            _activePlaylist = outgoingPlaylist;
            _cachedSeriesPlaylist = null;
            _playlistIdentityToken++;
            _currentSourceIndex = outgoingSourceIndex;
            _currentIndex = outgoingIndex.clamp(0, outgoingPlaylist.length - 1);
          });
          final restored = await _loadPlaylistIndex(
            _currentIndex,
            autoplay: true,
            skipInitialSave: true,
            preferLocalResume: true,
          );
          if (restored && outgoingPosition > Duration.zero) {
            // Guarded: a failure-path restore must not leave the bookmark at
            // the mercy of a stream that answers this seek with a restart.
            await _resumeRestore.seekForResume(outgoingPosition.inMilliseconds);
          }
        } else if (!committed &&
            outgoingDirectUrl != null &&
            outgoingDirectUrl.isNotEmpty) {
          // A direct launch has no active playlist to restore. The candidate
          // validator has stopped its media on failure, so explicitly rebuild
          // the outgoing direct session instead of leaving the player stopped
          // with the rejected playlist selected.
          setState(() {
            _activePlaylist = null;
            _cachedSeriesPlaylist = null;
            _playlistIdentityToken++;
            _currentSourceIndex = outgoingSourceIndex;
            _currentIndex = outgoingIndex;
          });
          try {
            _activeHttpHeaders = outgoingHeaders;
            await _openMedia(
              mk.Media(outgoingDirectUrl, httpHeaders: _activeHttpHeaders),
              play: true,
            );
            await _waitForVideoReady();
            if (outgoingPosition > Duration.zero) {
              await _resumeRestore.seekForResume(
                outgoingPosition.inMilliseconds,
              );
            }
            _currentStreamUrl = outgoingDirectUrl;
            _serverWatch.commit(_openedWatchSource);
            unawaited(_trackPreferences.restoreTrackPreferences());
          } catch (restoreError) {
            debugPrint(
              'Player: outgoing direct source restore failed '
              '(${restoreError.runtimeType})',
            );
          }
        }
      } finally {
        _manualSourceGateActive = false;
        _resumeTrackingAfterValidationGate();
      }
    }
    if (!mounted) return false;
    if (!committed && request != null) {
      // Only roll back preparation. If media open has started, the request
      // retains the incoming identity so progress stays with that media.
      final restored = request.restorePlaylist(
        () => setState(() {
          _activePlaylist = outgoingPlaylist;
          _cachedSeriesPlaylist = outgoingCachedSeries;
          _playlistIdentityToken++;
          _currentSourceIndex = outgoingSourceIndex;
          _currentIndex = outgoingIndex;
          _currentStreamUrl = outgoingDirectUrl;
          _activeHttpHeaders = outgoingHeaders;
        }),
      );
      if (restored) await _mdblist.switchMdblistTarget();
    }
    if (request?.isCurrent == false) return false;

    if (committed) {
      unawaited(_commitValidatedStremioSource(selectedSource));
    }
    if (validateExplicitSelection && !committed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This source is unavailable. Choose another source.'),
        ),
      );
    }

    // End transition (same pattern as _switchToStremioSource)
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 2;
    _transitionPhase2Started = DateTime.now();
    setState(() {
      _isTransitioning = false;
    });
    _transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _rainbowController.stop();
      _transitionRunning = false;
      _rainbowActive = false;
      if (mounted) setState(() {});
    });
    return committed;
  }

  Map<String, String>? _activeHttpHeaders;

  Future<void> _switchToStremioSource(int index, String url) async {
    _hideSourceSheet();

    // Capture current position before switching so playback continues
    // seamlessly. A held (unlanded) resume target outranks the live position —
    // the live value is a restart artifact and the new source must open at
    // the bookmark. Pure query; the guard stays armed so the new source's own
    // landing (or failure) keeps the bookmark protected.
    final heldSwitchMs = _resumeWriteGuard.heldTargetIfBlocked(
      _position.inMilliseconds,
    );
    final resumePosition = heldSwitchMs != null
        ? Duration(milliseconds: heldSwitchMs)
        : _position;
    final previousUrl = _currentStreamUrl;
    final previousHeaders = _activeHttpHeaders;
    final previousSourceIndex = _currentSourceIndex;
    final source =
        (_effectiveSources != null &&
            index >= 0 &&
            index < _effectiveSources!.length)
        ? _effectiveSources![index]
        : null;

    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentSourceIndex = index;
    });
    _startTransitionOverlay();

    try {
      await _player.pause();
    } catch (_) {}

    if (!mounted) return;

    _manualSourceGateActive = true;

    // For YouTube each quality is a video-only track sharing one audio stream
    // (widget.audioUrl). Mirror the initial-launch ordering: open PAUSED,
    // attach the external audio, seek, then play — so both tracks load in sync
    // (attaching audio mid-play makes mpv resync and drift). Sources without a
    // separate audio track (torrents) keep the plain open-and-play path.
    final hasExternalAudio =
        widget.audioUrl != null && widget.audioUrl!.isNotEmpty;

    // For direct/torrent switches, `_player.open` discards the old media's
    // subtitle tracks, so an active external/addon subtitle would silently
    // vanish and the cached identifiers would dangle. Reset now (mirrors
    // `_loadPlaylistIndex`) so the new media starts clean and addon-subtitle
    // logic re-runs. Deliberately NOT done for the external-audio (YouTube)
    // path — that flow is left exactly as before to avoid any regression.
    if (!hasExternalAudio) {
      _resetSubtitleState();
    }

    var committed = false;
    try {
      final valid = hasExternalAudio
          ? await (() async {
              await _openMedia(mk.Media(url), play: false, desiredPlay: true);
              await _waitForVideoReady();
              return _duration > Duration.zero;
            })()
          : await _tryOpenStartupVod(
              url,
              httpHeaders: source?.httpHeaders,
              source: source,
              sourceIndex: index,
            );
      if (!mounted) return;
      if (!valid) {
        throw const VpManualSourceValidationFailure();
      }
      if (!mounted) return;
      if (hasExternalAudio) {
        await _setExternalAudioTrack(widget.audioUrl!);
      }
      // Seek to the position from the previous source. _seekForResume
      // re-ARMS the guard (a pure held-target query never restarted the
      // settle window), so a switched-to stream that restarts at 0 cannot
      // have its first autosave file ~0 over the carried bookmark — the
      // identical failure the guard exists for, on the switch path.
      if (resumePosition > Duration.zero) {
        await _resumeRestore.seekForResume(resumePosition.inMilliseconds);
      }
      if (hasExternalAudio) {
        await _player.play();
      } else {
        // Restore stored audio/subtitle track preferences for this content
        // (same as the playlist path). Skipped for the external-audio (YouTube)
        // case above, where the merged audio track is set explicitly and track
        // preferences would fight it.
        //
        // Fire-and-forget: `_restoreTrackPreferences` awaits `_waitForSubtitleTracks`,
        // which polls up to ~5s on media with no embedded subtitle tracks
        // (common for direct MP4/torrent streams). Awaiting it here would hold
        // the black transition overlay for that whole wait — a regression vs the
        // old direct-switch path, which ended the transition right after the
        // seek. Let it apply in the background; the overlay ends below on time.
        unawaited(_trackPreferences.restoreTrackPreferences());
      }
      _currentSourceIndex = index;
      _currentStreamUrl = url;
      _activeHttpHeaders = source?.httpHeaders;
      committed = true;
      unawaited(_commitValidatedStremioSource(source));
    } catch (e) {
      debugPrint('Player: manual Stremio source rejected (${e.runtimeType})');
      logSourceSelection(
        'player_switch_rejected',
        source: source,
        index: index,
        previousIndex: previousSourceIndex,
        player: 'mpv',
        reason: 'validation_failed',
      );
      // The candidate player is stopped by the validator. Restore the known
      // working stream when possible, but never validate/fail over to another
      // row: this was an explicit user selection.
      if (previousUrl != null && previousUrl.isNotEmpty) {
        try {
          _activeHttpHeaders = previousHeaders;
          await _openMedia(
            mk.Media(previousUrl, httpHeaders: _activeHttpHeaders),
            play: true,
            source:
                _effectiveSources != null &&
                    previousSourceIndex >= 0 &&
                    previousSourceIndex < _effectiveSources!.length &&
                    MediaServerWatchController.isServerSource(
                      _effectiveSources![previousSourceIndex],
                    )
                ? _effectiveSources![previousSourceIndex]
                : null,
          );
          await _waitForVideoReady();
          if (hasExternalAudio) {
            // YouTube-style split streams: the reopen dropped the external
            // audio track — without this the restored video plays silent.
            await _setExternalAudioTrack(widget.audioUrl!);
          }
          if (resumePosition > Duration.zero) {
            await _resumeRestore.seekForResume(resumePosition.inMilliseconds);
          }
          _currentStreamUrl = previousUrl;
          _serverWatch.commit(_openedWatchSource);
          if (!hasExternalAudio) {
            // Subtitle state was reset for the candidate; bring the user's
            // subtitle/audio choices back on the restored stream.
            unawaited(_trackPreferences.restoreTrackPreferences());
          }
        } catch (restoreError) {
          debugPrint(
            'Player: previous source restore failed '
            '(${restoreError.runtimeType})',
          );
        }
      }
      _currentSourceIndex = previousSourceIndex;
    } finally {
      _manualSourceGateActive = false;
      _resumeTrackingAfterValidationGate();
    }

    if (!mounted) return;

    if (!committed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This source is unavailable. Choose another source.'),
        ),
      );
    }

    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 2;
    _transitionPhase2Started = DateTime.now();
    setState(() {
      _isTransitioning = false;
    });
    _transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _rainbowController.stop();
      _transitionRunning = false;
      _rainbowActive = false;
      if (mounted) setState(() {});
    });
  }

  // ─── Stremio TV Guide ─────────────────────────────────────────────

  String? _findInitialStremioTvChannelId() {
    // Use explicitly provided current channel ID
    if (widget.stremioTvCurrentChannelId != null) {
      return widget.stremioTvCurrentChannelId;
    }
    return null;
  }

  bool get _hasStremioTvGuide =>
      _effectiveStremioTvChannels != null &&
      _effectiveStremioTvChannels!.isNotEmpty &&
      widget.stremioTvChannelSwitchProvider != null;

  bool get _hasStremioTvNext =>
      _currentStremioTvChannelId != null &&
      widget.stremioTvNextProvider != null;

  bool get _hasAnyNext =>
      _hasNextEpisode() || widget.requestMagicNext != null || _hasStremioTvNext;

  void _showStremioTvGuideOverlay() {
    if (!_hasStremioTvGuide) return;
    setState(() {
      _showStremioTvGuide = true;
      _controlsVisible.value = false;
    });
  }

  void _hideStremioTvGuide() {
    setState(() {
      _showStremioTvGuide = false;
    });
  }

  void _setStremioTvNextLoading(bool loading) {
    if (!mounted || _showStremioTvNextLoading == loading) return;
    setState(() {
      _showStremioTvNextLoading = loading;
    });
  }

  void _applyStremioTvGuidePlaybackData(
    String channelId, {
    Map<String, dynamic>? nowPlaying,
    Map<String, dynamic>? nextUp,
  }) {
    final current = _effectiveStremioTvChannels;
    if (current == null || current.isEmpty) return;

    _stremioTvChannelsOverride = current
        .map((entry) {
          final copy = Map<String, dynamic>.from(entry);
          if (copy['id'] == channelId) {
            if (nowPlaying != null) {
              copy['nowPlaying'] = Map<String, dynamic>.from(nowPlaying);
            }
            if (nextUp != null) {
              copy['nextUp'] = Map<String, dynamic>.from(nextUp);
            }
          }
          return copy;
        })
        .toList(growable: false);
  }

  List<Torrent>? _parseStremioTvSources(dynamic rawSources) {
    if (rawSources is! List) return null;
    return rawSources
        .map(
          (s) =>
              s is Map ? Torrent.fromJson(Map<String, dynamic>.from(s)) : null,
        )
        .whereType<Torrent>()
        .toList();
  }

  Future<void> _switchToStremioTvChannel(
    String channelId,
    String url,
    String title, {
    String? contentImdbId,
    String? contentType,
    int? contentSeason,
    int? contentEpisode,
    Map<String, dynamic>? nowPlaying,
    Map<String, dynamic>? nextUp,
    double? startAtPercent,
    List<Torrent>? newSources,
    int? newSourceIndex,
    Future<String?> Function(Torrent)? sourceResolver,
  }) async {
    _hideStremioTvGuide();
    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentStremioTvChannelId = channelId;
      _dynamicTitle = title;
      _currentStremioTvContentImdbId = contentImdbId;
      _currentStremioTvContentType = contentType;
      _currentStremioTvContentSeason = contentSeason;
      _currentStremioTvContentEpisode = contentEpisode;
      _currentStremioTvContentTitle = title;
      _applyStremioTvGuidePlaybackData(
        channelId,
        nowPlaying: nowPlaying,
        nextUp: nextUp,
      );
      if (newSources != null) {
        _stremioSourcesOverride = newSources;
        _currentSourceIndex = newSourceIndex ?? 0;
      }
      if (sourceResolver != null) {
        _resolveStremioSourceOverride = sourceResolver;
      }
    });
    _startTransitionOverlay();

    try {
      await _player.pause();
    } catch (_) {}

    _resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;
    _completion.resetLocalCompletionState();

    try {
      _pikPakRetryId++;
      await _openMedia(mk.Media(url), play: true);
      _currentStreamUrl = url;
      await _subtitleApply.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'stremio-tv-switch-disable-auto',
      );
      if (startAtPercent != null && startAtPercent > 0) {
        // Apply start position once duration is known
        _player.stream.duration.firstWhere((d) => d > Duration.zero).then((d) {
          if (mounted) {
            final seekTo = Duration(
              milliseconds: (d.inMilliseconds * startAtPercent).round(),
            );
            _player.seek(seekTo);
          }
        });
      }
    } catch (e) {
      debugPrint('Player: Stremio TV channel switch failed: $e');
    }

    if (!mounted) return;

    // End transition
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 2;
    _transitionPhase2Started = DateTime.now();
    setState(() {
      _isTransitioning = false;
    });
    _transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _rainbowController.stop();
      _transitionRunning = false;
      _rainbowActive = false;
      if (mounted) setState(() {});
    });
  }

  Future<bool> _goToNextStremioTvSlot({
    bool resumeCurrentOnFailure = true,
  }) async {
    final requestNext = widget.stremioTvNextProvider;
    final channelId = _currentStremioTvChannelId;
    if (requestNext == null || channelId == null || channelId.isEmpty) {
      return false;
    }
    if (_showStremioTvNextLoading) {
      return true;
    }

    Map<String, dynamic>? result;
    _setStremioTvNextLoading(true);
    try {
      result = await requestNext(channelId);
    } catch (e) {
      debugPrint('Player: Stremio TV next failed: $e');
    }

    if (!mounted) return true;
    _setStremioTvNextLoading(false);

    if (result == null) {
      setState(() => _isTransitioning = false);
      if (!resumeCurrentOnFailure) return false;
      try {
        await _player.play();
      } catch (_) {}
      return true;
    }

    final url = result['url'] as String?;
    final title = result['title'] as String? ?? _dynamicTitle;
    if (url == null || url.isEmpty) {
      setState(() => _isTransitioning = false);
      if (!resumeCurrentOnFailure) return false;
      try {
        await _player.play();
      } catch (_) {}
      return true;
    }

    final newSources = _parseStremioTvSources(result['stremioSources']);
    final sourceResolver =
        result['sourceResolver'] as Future<String?> Function(Torrent)?;

    await _switchToStremioTvChannel(
      result['channelId'] as String? ?? channelId,
      url,
      title,
      contentImdbId: result['contentImdbId'] as String?,
      contentType: result['contentType'] as String?,
      contentSeason: (result['contentSeason'] as num?)?.toInt(),
      contentEpisode: (result['contentEpisode'] as num?)?.toInt(),
      nowPlaying: result['nowPlaying'] is Map
          ? Map<String, dynamic>.from(result['nowPlaying'] as Map)
          : null,
      nextUp: result['nextUp'] is Map
          ? Map<String, dynamic>.from(result['nextUp'] as Map)
          : null,
      startAtPercent: (result['startAtPercent'] as num?)?.toDouble(),
      newSources: newSources,
      newSourceIndex: (result['stremioCurrentSourceIndex'] as num?)?.toInt(),
      sourceResolver: sourceResolver,
    );
    return true;
  }

  /// Switch to a specific channel by ID (from channel guide)
  Future<void> _goToChannelById(ChannelEntry channel) async {
    _hideChannelGuideOverlay();

    final request = widget.requestChannelById;
    if (request == null) {
      debugPrint('Player: requestChannelById not provided');
      return;
    }

    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentChannelId = channel.id;
      _currentChannelName = channel.name;
      if (channel.number != null) {
        _currentChannelNumber = channel.number;
      }
    });
    _startTransitionOverlay();

    try {
      await _player.pause();
    } catch (_) {}

    Map<String, dynamic>? payload;
    try {
      payload = await request(channel.id);
    } catch (e) {
      debugPrint('Player: Channel switch by ID failed: $e');
    }

    if (!mounted) return;

    if (payload == null) {
      setState(() {
        _tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _tvStaticSubtext = '';
        _isTransitioning = false;
      });
      return;
    }

    final dynamic rawUrl = payload['firstUrl'] ?? payload['url'];
    final dynamic rawTitle = payload['firstTitle'] ?? payload['title'];
    final String nextUrl = rawUrl is String ? rawUrl : '';
    final String nextTitle = rawTitle is String ? rawTitle : '';

    // Update channel metadata from payload if provided
    final String? payloadChannelName = payload['channelName'] is String
        ? (payload['channelName'] as String)
        : null;
    final String? payloadChannelId = payload['channelId'] is String
        ? (payload['channelId'] as String)
        : null;
    final dynamic channelNumberRaw = payload['channelNumber'];
    int? payloadChannelNumber;
    if (channelNumberRaw is int) {
      payloadChannelNumber = channelNumberRaw;
    } else if (channelNumberRaw is String) {
      payloadChannelNumber = int.tryParse(channelNumberRaw);
    }

    setState(() {
      if (payloadChannelId != null) _currentChannelId = payloadChannelId;
      if (payloadChannelName != null && payloadChannelName.trim().isNotEmpty) {
        _currentChannelName = payloadChannelName;
      }
      if (payloadChannelNumber != null) {
        _currentChannelNumber = payloadChannelNumber;
      }
    });

    _raiseDebrifyBanner();

    if (nextUrl.isEmpty) {
      setState(() {
        _tvStaticMessage = '⚠ CHANNEL HAS NO STREAMS';
        _tvStaticSubtext = '';
        _isTransitioning = false;
      });
      return;
    }

    if (nextTitle.isNotEmpty) {
      setState(() {
        _tvStaticMessage = '📺 SIGNAL ACQUIRED';
        _tvStaticSubtext = '▶ ${nextTitle.toUpperCase()}';
      });
    }

    // Clear subtitle and IMDB state when switching channels
    _resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;

    try {
      _pikPakRetryId++;
      await _openMedia(
        mk.Media(nextUrl, httpHeaders: _activeHttpHeaders),
        play: true,
      );
      _currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _subtitleApply.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'channel-switch-disable-auto',
      );
    } catch (e) {
      debugPrint('Player: Failed to open channel stream: $e');
      setState(() {
        _tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _tvStaticSubtext = '';
        _isTransitioning = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isTransitioning = false;
        if (nextTitle.isNotEmpty) {
          _dynamicTitle = nextTitle;
        }
      });
    }
  }

  /// Switch to the next Debrify TV channel (MediaKit fallback)
  Future<void> _goToNextChannel() async {
    final request = widget.requestNextChannel;
    if (request == null) {
      return;
    }

    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
    });
    _startTransitionOverlay();

    try {
      await _player.pause();
    } catch (_) {}

    Map<String, dynamic>? payload;
    try {
      payload = await request();
    } catch (e) {
      debugPrint('Player: Next channel request failed: $e');
    }

    if (!mounted) {
      return;
    }

    if (payload == null) {
      setState(() {
        _tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _tvStaticSubtext = '';
        _isTransitioning = false;
      });
      return;
    }

    final dynamic rawUrl = payload['firstUrl'] ?? payload['url'];
    final dynamic rawTitle = payload['firstTitle'] ?? payload['title'];
    final String nextUrl = rawUrl is String ? rawUrl : '';
    final String nextTitle = rawTitle is String ? rawTitle : '';

    final String? channelName = payload['channelName'] is String
        ? (payload['channelName'] as String)
        : null;
    final String? channelId = payload['channelId'] is String
        ? (payload['channelId'] as String)
        : null;
    final dynamic channelNumberRaw = payload['channelNumber'];
    int? channelNumber;
    if (channelNumberRaw is int) {
      channelNumber = channelNumberRaw;
    } else if (channelNumberRaw is String) {
      channelNumber = int.tryParse(channelNumberRaw);
    }

    if ((channelName != null && channelName.trim().isNotEmpty) ||
        channelNumber != null ||
        channelId != null) {
      setState(() {
        if (channelId != null) {
          _currentChannelId = channelId;
        }
        if (channelName != null && channelName.trim().isNotEmpty) {
          _currentChannelName = channelName;
        }
        if (channelNumber != null) {
          _currentChannelNumber = channelNumber;
        }
      });
      _raiseDebrifyBanner();
    }

    if (nextUrl.isEmpty) {
      setState(() {
        _tvStaticMessage = '⚠ CHANNEL HAS NO STREAMS';
        _tvStaticSubtext = '';
        _isTransitioning = false;
      });
      return;
    }

    if (nextTitle.isNotEmpty) {
      setState(() {
        _tvStaticMessage = '📺 SIGNAL ACQUIRED';
        _tvStaticSubtext = '▶ ${nextTitle.toUpperCase()}';
      });
    }

    // Clear subtitle and IMDB state when switching channels
    _resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;

    try {
      // Cancel any ongoing PikPak retry when switching channels
      _pikPakRetryId++;
      await _openMedia(
        mk.Media(nextUrl, httpHeaders: _activeHttpHeaders),
        play: true,
      );
      _currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _subtitleApply.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'next-channel-disable-auto',
      );
    } catch (e) {
      debugPrint('Player: Failed to open next channel stream: $e');
      setState(() {
        _tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _tvStaticSubtext = '';
        _isTransitioning = false;
      });
      return;
    }

    if (widget.startFromRandom) {
      await _waitForVideoReady();
      final offset = _randomStartOffset(_duration);
      if (offset != null) {
        await _player.seek(offset);
      }
    } else if (widget.startAtPercent != null) {
      await _waitForVideoReady();
      final offset = _percentStartOffset(_duration);
      if (offset != null) {
        await _player.seek(offset);
      }
    }

    if (mounted) {
      setState(() {
        if (nextTitle.isNotEmpty) {
          _dynamicTitle = nextTitle;
        }
        _isTransitioning = false;
      });
    }
  }

  /// Navigate to previous episode
  Future<void> _goToPreviousEpisode() async {
    // Show black screen during transition to hide previous frame
    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
    });

    final previousIndex = _findPreviousEpisodeIndex();
    if (previousIndex != -1) {
      // Mark this as a manual episode selection
      _setManualSelectionMode();
      await _loadPlaylistIndex(previousIndex, autoplay: true);
    } else {
      // Beyond the pack's start: fetch the previous episode in-player.
      if (_canFetchEpisodes) {
        final se = _traktSeasonEpisode();
        var prev = (se.season != null && se.episode != null)
            ? _adjacentEpisode(se.season!, se.episode!, -1)
            : null;
        if (prev == null && se.season != null && se.episode != null) {
          final resolved = await _resolveAdjacentWithCachedGuide(
            se.season!,
            se.episode!,
            -1,
          );
          if (resolved != null) prev = (resolved.season, resolved.episode);
        }
        if (prev != null) {
          await _fetchAndPlayEpisode(prev.$1, prev.$2);
          return;
        }
      }
      // Clear transition state if no previous episode found
      if (mounted) {
        setState(() {
          _isTransitioning = false;
        });
      }
    }
  }

  /// Tear down the black transition overlay when a load fails partway (bad
  /// index, or no resolvable URL — e.g. a dead debrid/torbox link on the next
  /// episode). Without this the UI stays stuck on the black transition
  /// `Container` and the rainbow overlay never stops. The source-switch caller
  /// clears transition state itself, so this only rescues the other callers
  /// (`_goToNextEpisode`, shuffle). Safe to call redundantly.
  void _clearTransitionOnFailure() {
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _rainbowController.stop();
    _transitionRunning = false;
    _rainbowActive = false;
    // No new media will open, so the duration emit that normally re-arms the
    // skip lookup never comes. Leaving it disarmed would silently cost the
    // skip button for the rest of whatever is still playing.
    _skip.skipSegmentsMediaReady = true;
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
    } else {
      _isTransitioning = false;
    }
  }

  Future<bool> _loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    // Source switch on the same content: resume the checkpointed local position
    // exactly (see _maybeRestoreResume).
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) async {
    if (request == null) {
      return _loadPlaylistIndexAttempt(
        index,
        autoplay: autoplay,
        skipInitialSave: skipInitialSave,
        preferLocalResume: preferLocalResume,
        suppressResume: suppressResume,
        manualValidationSource: manualValidationSource,
        manualValidationSourceIndex: manualValidationSourceIndex,
      );
    }
    final outgoingIndex = _currentIndex;
    final outgoingUrl = _currentStreamUrl;
    final outgoingHeaders = _activeHttpHeaders;
    final outgoingMedia = _activeOpenedMedia;
    final outgoingShouldPlay = _activeMediaShouldPlay;
    final outgoingPaused = _activeMediaUserPaused;
    var loaded = false;
    try {
      loaded = await _loadPlaylistIndexAttempt(
        index,
        autoplay: autoplay,
        request: request,
        skipInitialSave: skipInitialSave,
        preferLocalResume: preferLocalResume,
        suppressResume: suppressResume,
        manualValidationSource: manualValidationSource,
        manualValidationSourceIndex: manualValidationSourceIndex,
      );
      return loaded;
    } finally {
      if (!loaded && mounted) {
        final restored = request.restorePlaylist(() {
          _currentIndex = outgoingIndex;
          _currentStreamUrl = outgoingUrl;
          _activeHttpHeaders = outgoingHeaders;
          _activeOpenedMedia = outgoingMedia;
          _activeMediaShouldPlay = outgoingShouldPlay;
          _activeMediaUserPaused = outgoingPaused;
          _isAutoAdvancing = false;
        });
        if (restored) await _mdblist.switchMdblistTarget();
      }
    }
  }

  Future<bool> _loadPlaylistIndexAttempt(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    // Source switch on the same content: resume the checkpointed local position
    // exactly (see _maybeRestoreResume).
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) async {
    if (request == null) _episodeNavigationGeneration++;
    if (request?.isCurrent == false) return false;
    // A new item is being loaded: any scrub in flight belongs to the outgoing
    // one and must never land on this one; same for the landing verifier
    // (epoch bump — a verifier retry must never seek the incoming item).
    // NOTE: the resume write GUARD is deliberately NOT cleared here — the
    // outgoing item's checkpoint _saveResume() below must still run against
    // the armed guard, or an unlanded resume's ~0 position would be filed over
    // that item's bookmark by the very switch that abandons it. The clear sits
    // immediately after that save.
    _tvScrubGeneration++;
    _tvAbandonScrub();
    _resumeVerifyEpoch++;
    if (_activePlaylist == null ||
        index < 0 ||
        index >= _activePlaylist!.length) {
      _clearTransitionOnFailure();
      return false;
    }

    // A sleep stop wins over anything already queued. Checked BEFORE any state
    // moves: bailing out after _currentIndex has advanced would leave the
    // playlist pointing at an episode that never opened, so resume and
    // metadata would file against the wrong item. Only automatic advances are
    // suppressed — picking something by hand means the viewer is awake, so it
    // clears the latch instead.
    if (_sleepStopLatched) {
      if (autoplay && _isAutoAdvancing) {
        _isAutoAdvancing = false;
        _clearTransitionOnFailure();
        return false;
      }
      _sleepStopLatched = false;
    }

    print(
      'PikPak: _loadPlaylistIndex called with index: $index, autoplay: $autoplay',
    );

    // Resolve before changing the playing identity: a cancelled or failed
    // lookup must not label the outgoing stream as the unplayed target.
    final entry = _activePlaylist![index];
    // Resolve the actual streaming URL if needed
    String videoUrl = entry.url;
    if (videoUrl.isEmpty) {
      try {
        videoUrl = await _resolvePlaylistEntryUrl(index);
      } catch (e) {
        final errorText = e.toString().replaceFirst('Exception: ', '');
        if (mounted && request?.isCurrent != false) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to prepare video: $errorText',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: VideoPlayerTimingConstants.controlsAutoHideDuration,
            ),
          );
        }
        videoUrl = entry.url;
      }
    }
    if (!mounted || request?.isCurrent == false) return false;
    if (videoUrl.isEmpty) {
      if (request == null) _currentStreamUrl = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No playable URL found for this entry',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: VideoPlayerTimingConstants.controlsAutoHideDuration,
          ),
        );
      }
      _clearTransitionOnFailure();
      return false;
    }

    // Scrobble stop for the current episode before switching
    _trakt.stopTraktHeartbeat();
    _trakt.traktScrobble('stop');
    _simkl.stopSimklHeartbeat();
    _simkl.simklScrobble('stop');
    // Keep the MDBList session's playing bit until switchTarget captures it.
    // Calling exit here would make the incoming episode look paused and would
    // prevent its initial checkpoint/timer from starting.
    _mdblist.updateMdblistPosition();

    // Callers that already checkpointed the outgoing episode (e.g. a source
    // switch, which saves BEFORE swapping the playlist) skip this save so it
    // can't write the current position against the newly-swapped playlist.
    if (!skipInitialSave) {
      await _resumeSave.saveResume();
    }
    if (!mounted || request?.isCurrent == false) return false;
    // The outgoing item's guarded checkpoint has run; from here on the guard
    // belongs to nobody. Clearing now stops it suppressing the incoming item's
    // saves and makes any in-flight landing verifier abort instead of
    // re-issuing the outgoing item's target against the new one.
    _resumeWriteGuard.clear();
    _currentIndex = index;
    await _mdblist.switchMdblistTarget();
    if (!mounted || request?.isCurrent == false) return false;
    _completion.resetLocalCompletionState();

    // Clear subtitle cache and selection when changing content
    _resetSubtitleState();
    _skip.resetSkipSegmentState();

    // For movie collections, prefetch movie metadata for the new index
    // This runs in background so subtitles are ready when user opens TracksSheet
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null && !seriesPlaylist.isSeries) {
      seriesPlaylist.fetchMovieMetadataForIndex(index).catchError((e) {
        // Silently ignore errors - metadata is optional
        return null;
      });
    }

    print(
      'PikPak: Loading playlist entry - provider: ${entry.provider}, pikpakFileId: ${entry.pikpakFileId}',
    );

    _currentStreamUrl = videoUrl;

    // Check if this is a PikPak video
    final currentEntry = _activePlaylist?[index];
    _activeHttpHeaders = currentEntry?.httpHeaders;
    final isPikPak =
        currentEntry?.provider?.toLowerCase() == 'pikpak' ||
        currentEntry?.pikpakFileId != null;

    // ALWAYS use retry logic for PikPak videos, regardless of autoplay
    if (isPikPak) {
      // For PikPak, we need retry logic even if not autoplaying
      // _playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
      final pikPakLoaded = await _playPikPakVideoWithRetry(
        videoUrl,
        request: request,
        // A manual source transaction owns its single failure message. The
        // retry UI remains unchanged while cold storage is being reactivated.
        showFailure: manualValidationSourceIndex == null,
      );
      if (manualValidationSourceIndex != null && !pikPakLoaded) return false;
      if (request != null && suppressResume && !pikPakLoaded) return false;
      if (!autoplay) {
        // Still use retry but without autoplay; pause only after it succeeds.
        _activeMediaShouldPlay = false;
        if (pikPakLoaded) await _player.pause();
      }
    } else {
      // Non-PikPak videos play normally
      // Cancel any ongoing PikPak retry when switching to non-PikPak video
      _pikPakRetryId++;
      if (manualValidationSourceIndex != null) {
        final valid = await _tryOpenStartupVod(
          videoUrl,
          httpHeaders: _activeHttpHeaders,
          source: manualValidationSource,
          sourceIndex: manualValidationSourceIndex,
        );
        if (!valid) return false;
        if (!autoplay) await _player.pause();
      } else {
        await _openMedia(
          mk.Media(videoUrl, httpHeaders: _activeHttpHeaders),
          play: autoplay,
          request: request,
        );
      }
    }

    if (!mounted || request?.isCurrent == false) return false;
    // Shuffle needs playback proof to decide whether to try another episode.
    // Ordinary episode/source navigation retains its existing readiness path.
    if (request != null && suppressResume) {
      final ready = await waitForEpisodePlayback(
        isCurrent: () => request.isCurrent,
        isPaused: () => _activeMediaUserPaused || _pausedByLifecycle,
        isReady: () =>
            _player.state.duration > Duration.zero &&
            (_activeMediaUserPaused ||
                _pausedByLifecycle ||
                (_player.state.playing &&
                    _player.state.position >=
                        const Duration(milliseconds: 40))),
      );
      if (!ready) return false;
    } else {
      await _waitForVideoReady();
    }
    if (!mounted || request?.isCurrent == false) return false;
    if (suppressResume) {
      // Starting a random episode at zero is independent of whether the
      // viewer requested it or EOF advanced automatically.
      _resumeWriteGuard.clear();
      _isAutoAdvancing = false;
    } else {
      await _resumeRestore.maybeRestoreResume(
        preferLocalResume: preferLocalResume,
      );
    }
    // Restore audio and subtitle track preferences
    await _trackPreferences.restoreTrackPreferences();

    // Clear transition state when video is ready
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
    }
    // Ordinary episode opens use the readiness path above, rather than the
    // startup/manual-source commit callback. Bind sync only after that lands.
    if (manualValidationSourceIndex == null) {
      _serverWatch.commit(_openedWatchSource);
    }
    return true;
  }

  Future<String> _resolvePlaylistEntryUrl(int index) async {
    if (_activePlaylist == null ||
        index < 0 ||
        index >= _activePlaylist!.length) {
      return '';
    }

    final entry = _activePlaylist![index];

    if (entry.url.isNotEmpty) {
      return entry.url;
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (fileId == null || (torrentId == null && webDownloadId == null)) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await TorboxStorage.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Torbox API key');
      }
      try {
        String url;
        if (webDownloadId != null) {
          // Web download - use web download API
          url = await TorboxService.requestWebDownloadFileLink(
            apiKey: apiKey,
            webId: webDownloadId,
            fileId: fileId,
          );
        } else {
          // Torrent - use torrent API
          url = await TorboxService.requestFileDownloadLink(
            apiKey: apiKey,
            torrentId: torrentId!,
            fileId: fileId,
          );
        }
        if (url.isEmpty) {
          throw Exception('Torbox returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('Torbox link failed: $e');
      }
    }

    // PikPak lazy resolution
    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      final fileId = entry.pikpakFileId;
      if (fileId == null) {
        throw Exception('PikPak file metadata missing');
      }
      try {
        final pikpak = PikPakApiService.instance;
        final fileData = await pikpak.getFileDetails(fileId);
        final url = pikpak.getStreamingUrl(fileData);
        if (url == null || url.isEmpty) {
          throw Exception('PikPak returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('PikPak link failed: $e');
      }
    }

    // Premiumize cloud-browser lazy resolution: re-fetch a fresh direct link by
    // cloud item id (items saved from the cloud browser have no infohash).
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      try {
        final file = await PremiumizeService.resolveItemById(
          apiKey,
          entry.premiumizeItemId!,
        );
        if (file == null || file.link.isEmpty) {
          throw Exception('File not found in Premiumize cloud');
        }
        return file.link;
      } catch (e) {
        throw Exception('Premiumize link failed: $e');
      }
    }

    // Premiumize lazy resolution: re-fetch direct links by infohash and match
    // the file by its stored path (Premiumize direct links eventually expire).
    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      if (hash == null || hash.isEmpty || path == null || path.isEmpty) {
        throw Exception('Premiumize file metadata missing');
      }
      final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      try {
        final files = await PremiumizeService.resolveFilesByHash(apiKey, hash);
        final match = files.firstWhere(
          (f) => f.path == path,
          orElse: () => throw Exception('File not found in Premiumize cloud'),
        );
        if (match.link.isEmpty) {
          throw Exception('Premiumize returned an empty stream URL');
        }
        return match.link;
      } catch (e) {
        throw Exception('Premiumize link failed: $e');
      }
    }

    if (entry.restrictedLink != null) {
      final apiKey = await RealDebridStorage.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Real Debrid API key');
      }
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          apiKey,
          entry.restrictedLink!,
        );
        final url = unrestrictResult['download']?.toString() ?? '';
        if (url.isEmpty) {
          throw Exception('Real Debrid returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('Real Debrid link failed: $e');
      }
    }

    // AllDebrid lazy resolution: unlock the stored locked link on demand
    // (mirrors Real-Debrid's restrictedLink → unrestrict). The locked link is
    // stable; only the unlocked CDN URL expires, so this is also more robust
    // than resolving every episode up front.
    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      final lockedLink = entry.allDebridLink;
      if (lockedLink == null || lockedLink.isEmpty) {
        throw Exception('AllDebrid link metadata missing');
      }
      final apiKey = await AllDebridStorage.getAllDebridApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing AllDebrid API key');
      }
      try {
        final url = await AllDebridService.unlockLink(apiKey, lockedLink);
        if (url.isEmpty) {
          throw Exception('AllDebrid returned an empty stream URL');
        }
        return url;
      } catch (e) {
        throw Exception('AllDebrid link failed: $e');
      }
    }

    throw Exception('No URL metadata available for this entry');
  }

  /// Waits for video metadata (duration) to become available
  /// Returns true if metadata loads, false if timeout or cancelled
  /// This is the only reliable way to detect if a PikPak file is actually loading
  ///
  /// The additionalMonitoringSeconds parameter allows continuous monitoring during retry delays
  /// to detect if video loads during the delay period (prevents unnecessary player resets)
  Future<bool> _waitForVideoMetadata({
    int timeoutSeconds = 15,
    required int retryId,
    int additionalMonitoringSeconds = 0,
  }) async {
    final totalTimeoutSeconds = timeoutSeconds + additionalMonitoringSeconds;
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed.inSeconds < totalTimeoutSeconds) {
      // Check if this retry has been cancelled (user navigated to different video)
      if (_pikPakRetryId != retryId) {
        print(
          'PikPak: Retry cancelled (token mismatch: current=$_pikPakRetryId, expected=$retryId)',
        );
        return false;
      }

      // Check if widget was disposed (prevents operations on unmounted widget)
      if (!mounted) {
        print('PikPak: Widget disposed during metadata wait');
        return false;
      }

      // FIX: Check BOTH _duration field (from stream) AND player.state.duration (direct state)
      // This ensures we catch the video loading whether the stream has fired or not
      // For the first video, streams might not fire reliably, so we need the direct state check
      final streamDuration = _duration;
      final directDuration = _player.state.duration;
      final effectiveDuration = streamDuration > Duration.zero
          ? streamDuration
          : directDuration;

      if (effectiveDuration > Duration.zero) {
        print(
          'PikPak: Video duration available (stream: $streamDuration, direct: $directDuration, effective: $effectiveDuration)',
        );

        // Additional verification: wait a bit longer to ensure playback actually started
        // This gives the player time to transition from "has duration" to "is playing"
        // and allows all stream listeners to synchronize their state updates
        print(
          'PikPak: Duration detected, waiting for playback to stabilize...',
        );
        await Future.delayed(const Duration(milliseconds: 800));

        // Check mounted state after delay
        if (!mounted) {
          print('PikPak: Widget disposed during stabilization delay');
          return false;
        }

        // Final cancellation check after stabilization delay
        if (_pikPakRetryId != retryId) {
          print(
            'PikPak: Retry cancelled during stabilization (navigation occurred)',
          );
          return false;
        }

        // Verify playback is actually happening, not just buffering with duration
        // This prevents false positives where duration loads but video won't play
        // Check both stream state and direct player state for reliability
        final streamPlaying = _isPlaying;
        final directPlaying = _player.state.playing;

        if (streamPlaying || directPlaying) {
          print(
            'PikPak: Video confirmed playing - duration: $effectiveDuration, playing: true (stream: $streamPlaying, direct: $directPlaying)',
          );
        } else {
          // Duration is available but playback hasn't started yet
          // This is acceptable - duration alone is sufficient for cold storage detection
          print(
            'PikPak: Duration available ($effectiveDuration), playback will start shortly',
          );
        }

        // CRITICAL FIX: Clear retry state IMMEDIATELY when video loads
        // This prevents the retry UI from remaining visible if video loaded during monitoring
        _isPikPakRetrying = false;
        _pikPakRetryMessage = null;
        _pikPakRetryCount = 0;

        if (mounted) {
          setState(() {
            // State already cleared above - this just triggers rebuild
          });
        }

        return true;
      }

      // Wait a bit before checking again
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Timeout - video metadata never loaded, file is likely in cold storage
    print(
      'PikPak: Timeout waiting for video metadata (${totalTimeoutSeconds}s elapsed)',
    );
    return false;
  }

  /// Attempts to play a PikPak video with retry logic for cold storage
  Future<bool> _playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  }) async {
    if (request?.isCurrent == false) return false;
    // Only apply retry logic for PikPak videos
    // Support both playlist entries and Debrify TV (requestMagicNext) flows
    final currentEntry =
        _activePlaylist != null &&
            _currentIndex >= 0 &&
            _currentIndex < _activePlaylist!.length
        ? _activePlaylist![_currentIndex]
        : null;
    final isPikPak =
        overrideProvider?.toLowerCase() == 'pikpak' ||
        overridePikPakFileId != null ||
        currentEntry?.provider?.toLowerCase() == 'pikpak' ||
        currentEntry?.pikpakFileId != null ||
        isDebrifyTV ||
        videoUrl.contains(
          'mypikpak.com',
        ); // Detect PikPak by URL (Stremio TV, etc.)

    print(
      'PikPak: _playPikPakVideoWithRetry called for index $_currentIndex, isPikPak: $isPikPak, overrideProvider: $overrideProvider, overridePikPakFileId: $overridePikPakFileId, isDebrifyTV: $isDebrifyTV',
    );

    if (!isPikPak) {
      // Not a PikPak video, play normally
      await _openMedia(
        mk.Media(videoUrl, httpHeaders: _activeHttpHeaders),
        play: true,
        request: request,
      );
      return true;
    }

    print('PikPak: Starting retry logic for cold storage handling');

    // Generate a new retry ID to cancel any previous retry loops
    _pikPakRetryId++;
    final myRetryId = _pikPakRetryId;
    print('PikPak: Generated retry ID: $myRetryId');

    // Reset retry state
    _pikPakRetryCount = 0;
    _isPikPakRetrying = false;
    _pikPakRetryMessage = null;

    // Retry with exponential backoff
    // Standardized retry parameters to match Java/Kotlin implementation
    const maxRetries = 5; // 6 total attempts including initial
    const baseDelaySeconds = 2;
    const metadataTimeoutSeconds = 10; // Standardized timeout
    const maxDelaySeconds = 18; // Standardized max delay cap

    // CRITICAL FIX: Open player ONCE before the retry loop
    // This prevents resetting the video to 0:00 if it loads during a retry delay
    print('PikPak: Initial playback attempt - opening media...');
    try {
      await _openMedia(
        mk.Media(videoUrl, httpHeaders: _activeHttpHeaders),
        play: true,
        request: request,
      );
    } catch (e) {
      print('PikPak: Initial player.open() failed with error: $e');
      // Continue with retry loop - might work on subsequent attempts
    }

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // Check if cancelled before starting attempt
        if (_pikPakRetryId != myRetryId || request?.isCurrent == false) {
          print(
            'PikPak: Retry loop cancelled before attempt ${attempt + 1} (navigation occurred)',
          );
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (mounted) {
            setState(() {});
          }
          return false;
        }

        print('PikPak: Monitoring attempt ${attempt + 1}/${maxRetries + 1}...');

        // Calculate delay for this attempt (0 for first attempt)
        final delaySeconds = attempt == 0
            ? 0
            : (baseDelaySeconds * (1 << (attempt - 1)));
        final cappedDelay = delaySeconds > maxDelaySeconds
            ? maxDelaySeconds
            : delaySeconds;

        // CRITICAL FIX: Wait for video metadata with EXTENDED monitoring during delay period
        // This allows detection of video loading DURING the delay, preventing unnecessary player resets
        print(
          'PikPak: Waiting for video duration (${metadataTimeoutSeconds}s) + monitoring during delay (${cappedDelay}s)...',
        );
        final loadSuccess = await _waitForVideoMetadata(
          timeoutSeconds: metadataTimeoutSeconds,
          retryId: myRetryId,
          additionalMonitoringSeconds: cappedDelay,
        );

        if (request?.isCurrent == false) return false;
        if (loadSuccess) {
          // Success! Video loaded (either immediately or during monitoring/delay)
          print('PikPak: Video metadata loaded successfully - file is ready!');
          // Note: Retry state already cleared by _waitForVideoMetadata
          print('PikPak: Retry mechanism fully deactivated, playback ready');
          return true;
        }

        // Video didn't load even after monitoring during delay
        print(
          'PikPak: Video metadata failed to load after ${metadataTimeoutSeconds + cappedDelay}s - file likely in cold storage',
        );

        // Check if this was the last attempt (all retries exhausted)
        if (attempt >= maxRetries) {
          // ALL RETRIES EXHAUSTED - handle here
          print('PikPak: All retry attempts exhausted. Video failed to load.');

          // Clear retry state
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;

          if (mounted) {
            setState(() {});

            if (isDebrifyTV) {
              // Auto-skip for Debrify TV
              print('PikPak: Auto-advancing to next video in Debrify TV queue');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Video failed to load. Skipping to next...',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
              await _goToNextEpisode();
            } else if (showFailure) {
              // Show error for regular playlist
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Failed to play video after multiple attempts. Please try again later.',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
          return false; // Exhausted the cold-storage retries.
        }

        // Still have retries left - continue with retry logic
        // Calculate delay for NEXT attempt
        final nextDelaySeconds = baseDelaySeconds * (1 << attempt);
        final nextDelay = nextDelaySeconds > maxDelaySeconds
            ? maxDelaySeconds
            : nextDelaySeconds;

        // Update UI to show retry state
        if (mounted) {
          setState(() {
            _isPikPakRetrying = true;
            _pikPakRetryCount = attempt + 1;
            _pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print(
          'PikPak: Retry ${attempt + 1} - reopening player and waiting ${nextDelay}s before next check...',
        );

        // Check if widget was disposed
        if (!mounted) {
          print('PikPak: Widget disposed before retry');
          return false;
        }

        // Check if cancelled
        if (_pikPakRetryId != myRetryId || request?.isCurrent == false) {
          print(
            'PikPak: Retry loop cancelled before reopening player (navigation occurred)',
          );
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (mounted) {
            setState(() {});
          }
          return false;
        }

        // Try reopening the player (might help reactivate cold storage file)
        try {
          await _openMedia(
            mk.Media(videoUrl, httpHeaders: _activeHttpHeaders),
            play: true,
            request: request,
          );
        } catch (e) {
          print(
            'PikPak: Retry ${attempt + 1} - player.open() failed with error: $e',
          );
          // Continue - the monitoring in next iteration might still detect if it loads
        }
      } catch (e) {
        print('PikPak: Retry attempt ${attempt + 1} failed with error: $e');

        // Check if this was the last attempt (all retries exhausted)
        if (attempt >= maxRetries) {
          // ALL RETRIES EXHAUSTED - handle here
          print(
            'PikPak: All retry attempts exhausted after error. Video failed to load.',
          );

          // Clear retry state
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;

          if (mounted) {
            setState(() {});

            if (isDebrifyTV) {
              // Auto-skip for Debrify TV
              print('PikPak: Auto-advancing to next video in Debrify TV queue');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Video failed to load. Skipping to next...',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
              await _goToNextEpisode();
            } else if (showFailure) {
              // Show error for regular playlist
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Failed to play video after multiple attempts. Please try again later.',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
          return false; // Exhausted the cold-storage retries.
        }

        // Still have retries left - continue with retry logic
        // Calculate delay for next attempt
        final delaySeconds = baseDelaySeconds * (1 << attempt);
        final nextDelay = delaySeconds > maxDelaySeconds
            ? maxDelaySeconds
            : delaySeconds;

        if (mounted) {
          setState(() {
            _isPikPakRetrying = true;
            _pikPakRetryCount = attempt + 1;
            _pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print(
          'PikPak: Error in attempt ${attempt + 1}, waiting ${nextDelay}s before retry...',
        );

        // Check if widget was disposed
        if (!mounted) {
          print('PikPak: Widget disposed during error handling');
          return false;
        }

        // Check if cancelled
        if (_pikPakRetryId != myRetryId || request?.isCurrent == false) {
          print(
            'PikPak: Retry loop cancelled during error handling (navigation occurred)',
          );
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (mounted) {
            setState(() {});
          }
          return false;
        }

        // Try reopening the player for next attempt
        try {
          await _openMedia(
            mk.Media(videoUrl, httpHeaders: _activeHttpHeaders),
            play: true,
            request: request,
          );
        } catch (reopenError) {
          print(
            'PikPak: Error retry - player.open() failed with error: $reopenError',
          );
          // Continue - next iteration might succeed
        }
      }

      attempt++;
    }
    return false;
  }

  /// Preload episode information in the background
  Future<void> _preloadEpisodeInfo() async {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlistIdentityToken = _playlistIdentityToken;
      // Preload episode information in the background
      // Pass IMDB ID from catalog for faster, more accurate lookup
      await seriesPlaylist
          .fetchEpisodeInfo(
            playlistItem: _constructPlaylistItemData(),
            imdbId: widget.contentImdbId,
          )
          .then((_) async {
            if (!mounted ||
                playlistIdentityToken != _playlistIdentityToken ||
                !identical(seriesPlaylist, _seriesPlaylist)) {
              return;
            }

            // TVMaze can discover the series IMDB ID after the initial subtitle
            // restore has already run. Retry the existing addon subtitle path so
            // RD/Torbox season packs do not require reopening the player.
            _retryAddonSubtitleFetchAfterSeriesMetadata(
              seriesPlaylist,
              playlistIdentityToken,
            );

            // Trigger UI update to show the episode info
            setState(() {});

            // Save discovered IMDB ID back to playlist item for future direct plays
            await _saveImdbIdToPlaylist(seriesPlaylist);

            // Extract poster URL from series data and save to playlist
            await _saveSeriesPosterToPlaylist(seriesPlaylist);
          })
          .catchError((error) {
            // Silently handle errors - this is just preloading
          });
    } else if (seriesPlaylist != null && !seriesPlaylist.isSeries) {
      // For non-series content (movie collections), fetch movie metadata for current index
      // This enables subtitles for movies from Debrid/Torbox/PikPak
      await seriesPlaylist
          .fetchMovieMetadataForIndex(_currentIndex)
          .then((imdbId) {
            // Trigger UI update if IMDB ID was discovered
            if (mounted && imdbId != null) {
              setState(() {});
            }
          })
          .catchError((error) {
            // Silently handle errors - this is just preloading
          });
    } else if (seriesPlaylist == null && widget.contentImdbId == null) {
      // Single-file playback (no playlist) - try to fetch movie metadata from title
      await _fetchSingleFileMovieMetadata();
    }
  }

  void _retryAddonSubtitleFetchAfterSeriesMetadata(
    SeriesPlaylist seriesPlaylist,
    int playlistIdentityToken,
  ) {
    final imdbId = seriesPlaylist.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (playlistIdentityToken != _playlistIdentityToken) return;
    if (!identical(seriesPlaylist, _seriesPlaylist)) return;

    // If track preferences have not completed yet, the normal restore path will
    // see the newly discovered IMDB ID and fetch subtitles at the right time.
    if (!_trackPreferencesReadyForAddonSubtitles) {
      debugPrint(
        'VideoPlayer: Series IMDB resolved before track restore; subtitle fetch will run during restore',
      );
      return;
    }

    debugPrint(
      'VideoPlayer: Series IMDB resolved after initial subtitle fetch, retrying addon subtitles (IMDB: $imdbId)',
    );
    unawaited(_addonSubtitles.fetchAndMaybeAutoSelectAddonSubtitle());
  }

  /// Fetch movie metadata for single-file playback (when no playlist exists)
  Future<void> _fetchSingleFileMovieMetadata() async {
    // Skip if already fetched or we have an IMDB ID
    if (_singleFileImdbFetched || widget.contentImdbId != null) {
      return;
    }

    _singleFileImdbFetched = true;

    // Use dynamic title (updated on stream switch) or fall back to widget title
    final title = _dynamicTitle.isNotEmpty ? _dynamicTitle : widget.title;
    if (title.isEmpty) {
      debugPrint('MovieMetadata: No title for single-file lookup');
      return;
    }

    debugPrint('MovieMetadata: Single-file lookup for "$title"');

    // Parse the title for movie info
    final movieInfo = MovieParser.parseFilename(title);

    if (!movieInfo.hasYear) {
      debugPrint('MovieMetadata: No year pattern in single-file title');
      return;
    }

    if (movieInfo.title == null || movieInfo.title!.isEmpty) {
      debugPrint('MovieMetadata: Could not extract title from single-file');
      return;
    }

    debugPrint(
      'MovieMetadata: Parsed single-file title="${movieInfo.title}", year=${movieInfo.year}',
    );

    try {
      final metadata = await MovieMetadataService.lookupMovie(
        movieInfo.title!,
        movieInfo.year,
      );

      if (metadata != null) {
        _singleFileImdbId = metadata.imdbId;
        debugPrint(
          'MovieMetadata: Found IMDB ID "${metadata.imdbId}" for single-file "${metadata.title}"',
        );
        if (mounted) {
          setState(() {});
        }
      } else {
        debugPrint('MovieMetadata: No match found for single-file');
      }
    } catch (e) {
      debugPrint('MovieMetadata: Error during single-file lookup: $e');
    }
  }

  Future<void> _saveImdbIdToPlaylist(SeriesPlaylist seriesPlaylist) async {
    final imdbId = seriesPlaylist.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (widget.contentImdbId != null) return;

    await PlaylistMetadataStorage.updatePlaylistItemImdbId(
      imdbId,
      rdTorrentId: widget.rdTorrentId,
      torboxTorrentId: widget.torboxTorrentId,
      pikpakCollectionId: widget.pikpakCollectionId,
    );
  }

  /// Save series poster URL to playlist item
  Future<void> _saveSeriesPosterToPlaylist(
    SeriesPlaylist seriesPlaylist,
  ) async {
    print('🎬 _saveSeriesPosterToPlaylist called');
    print('  seriesTitle: ${seriesPlaylist.seriesTitle}');

    if (seriesPlaylist.seriesTitle == null) {
      print('  ⚠️ No series title, skipping poster save');
      return;
    }

    // Get identifiers from widget parameters
    final rdTorrentId = widget.rdTorrentId;
    final torboxTorrentId = widget.torboxTorrentId;
    final pikpakCollectionId = widget.pikpakCollectionId;

    print('  rdTorrentId: $rdTorrentId');
    print('  torboxTorrentId: $torboxTorrentId');
    print('  pikpakCollectionId: $pikpakCollectionId');

    // Need at least one identifier to save poster
    if ((rdTorrentId == null || rdTorrentId.isEmpty) &&
        (torboxTorrentId == null || torboxTorrentId.isEmpty) &&
        (pikpakCollectionId == null || pikpakCollectionId.isEmpty)) {
      print('  ⚠️ No valid identifier found, skipping poster save');
      return;
    }

    final posterUrl = seriesPlaylist.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) {
      print('  ⚠️ No poster URL from fetchEpisodeInfo');
      return;
    }

    print('  Poster URL: $posterUrl');
    try {
      if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
    } catch (e) {
      print('  ❌ Error saving poster: $e');
    }
  }

  late final VpPipLifecycle _pip;

  @override
  void dispose() {
    _stremioTvStartupWatch?.dispose();
    _stremioTvStartupSeek.cancel();
    _resumeSave.observeServerWatch();
    unawaited(_serverWatch.close());
    _watchOpenEpoch++;
    final replacedPip =
        (_pip.iosPipSession?.wasReplaced ?? false) ||
        (_pip.iosPipDetached && !PipService.isOwner(this));
    _pip.iosPipSession?.close();
    PlayerVisibility.closed(this);
    if (!replacedPip) ProfileLockController.instance.setPlaybackActive(false);
    _iptvDiag.onSessionEnd();
    _iptvLiveRecovery.cancel();
    _iptvReconnectText.dispose();
    _subtitleSync.autoSyncPillHold?.cancel();
    _subtitleSync.autoSyncPillPhaseTimer?.cancel();
    _autoSyncPill.dispose();
    // The sleep timer belongs to this playback session — a pending one must not
    // outlive the player and fire against a disposed state.
    _sleep.sleepTimer?.cancel();
    _sleep.sleepTimer = null;
    _lifecycle?.dispose();
    final revisionListener = _desktopRecordingRevisionListener;
    if (revisionListener != null) {
      DesktopRecordingService.instance.revision.removeListener(
        revisionListener,
      );
      _desktopRecordingRevisionListener = null;
    }
    // Nothing to do for a desktop capture: closing the player is not a stop
    // request, on either platform. This screen used to finish its own capture
    // because it was the only stop control desktop had; the Recordings hub
    // (one Stop card per capture, both backends) is that control now, so the
    // contract matches Android's engine — "runs while the app runs" — and
    // endings are announced by the app-level reporter in main(), which
    // outlives this screen.
    // Finalize any in-progress recording before the player is torn down. The
    // bump also cancels a start still awaiting its storage setup (it would
    // otherwise arm a disposed player and leave the file untracked).
    //
    // Done inline rather than through `_stopRecording`: dispose() cannot await,
    // so that call would race `_player.dispose()` a few lines below AND reach
    // its own setState() mid-teardown. The order that matters is preserved by
    // hand — state cleared now, publish handed off immediately (it reads the
    // .ts from disk and never touches mpv), property clear issued best-effort.
    // A live .ts stays playable even if its tail is lost to the teardown, and
    // the lifecycle listener above already caught the common backgrounding
    // case with a clean, awaited flush.
    _recordingStartGen++;
    if (_isRecording) {
      final path = _recordingTempPath;
      final platform = _playerCreated ? _player.platform : null;
      _isRecording = false;
      _recordingTempPath = null;
      if (platform is mk.NativePlayer) {
        // Publication is CHAINED after the property clear, not run alongside
        // it: libmpv keeps appending until stream-record is cleared, and a
        // concurrent copy could reach EOF early, publish a truncated file and
        // delete the source out from under the still-writing muxer.
        unawaited(
          platform
              .setProperty('stream-record', '')
              .catchError(
                (Object e) => debugPrint(
                  'VideoPlayer: stop recording on dispose failed: $e',
                ),
              )
              .whenComplete(() {
                if (path != null && Platform.isAndroid) {
                  _recording.publishRecording(path, userInitiated: false);
                }
              }),
        );
      } else if (path != null && Platform.isAndroid) {
        unawaited(_recording.publishRecording(path, userInitiated: false));
      }
    }
    _iptvGuide.iptvCatchupRequests.cancel();
    // Detach from PiP (disarms auto-enter); ignored if a newer player already
    // took ownership, so route replacement can't disarm the incoming screen.
    PipService.detach(this);
    // Scrobble stop to Trakt when user exits player
    _trakt.stopTraktHeartbeat();
    _analyticsHeartbeatTimer?.cancel();
    _trakt.traktScrobble('stop');
    _simkl.stopSimklHeartbeat();
    _simkl.simklScrobble('stop');
    _mdblist.mdblistStop();
    unawaited(_mdblist.mdblistSession?.close() ?? Future.value());

    // Save the current state before disposing
    _resumeSave.saveResume();
    // Every in-app player route converges here, including callers that push
    // VideoPlayerScreen directly. The sync trigger is debounced, so the async
    // resume write above settles before its hot-state snapshot is built.
    MainPageBridge.notifyContentPlaybackStopped();

    // Cancel any ongoing PikPak retry operations
    _pikPakRetryId++;
    _isPikPakRetrying = false;
    _pikPakRetryCount = 0;
    _pikPakRetryMessage = null;

    _addonSubtitles.cleanupTempSubtitleFilesSync();
    _skip.skipSegmentsFetchGeneration++;
    _skip.skipSegmentProvider?.close();
    _skip.skipSegmentProvider = null;
    _hideTimer?.cancel();
    _autosaveTimer?.cancel();
    _manualSelectionResetTimer?.cancel();
    _debrifyBannerTimer?.cancel();
    _iptvBanner.iptvZapHideTimer?.cancel();
    _iptvBanner.iptvZapTicker?.cancel();
    _tvScrubGeneration++; // invalidate any scrub still in flight
    _tvBarScope.dispose();
    _dockExtent.dispose();
    _tvPlayPauseFocus.dispose();
    _tvProgressFocus.dispose();
    _tvRootFocus.dispose();
    _controlsVisible.removeListener(_onControlsVisibilityChanged);
    _controlsVisible.dispose();
    _seekHud.dispose();
    _verticalHud.dispose();
    _speedHoldHud.dispose();
    _recordLogSub?.cancel();
    _subtitleDiagnosticLogSub?.cancel();
    _subtitleSelectionCorrection.dispose();
    _subtitleDiagnosticGeneration++;
    _activeSubtitleApplyAttempt = null;
    _decoderProbeGeneration++;
    _decoderProbeToken++;
    _rendererStartupGuardToken++;
    _playerInstanceGeneration++;
    _decoderProbeTimer?.cancel();
    _decoderProbeTimer = null;
    _tvosDisplayMatchToken++;
    _tvosDisplayMatchTimer?.cancel();
    _tvosDisplayMatchTimer = null;
    if (PlatformUtil.isTvOS && !replacedPip) {
      unawaited(
        TvosDisplayMatchService.clear().catchError((Object error) {
          debugPrint('DisplayMatch: tvOS dispose clear failed: $error');
        }),
      );
    }
    _posSub?.cancel();
    _durSub?.cancel();
    _playbackUiClock.dispose();
    _activeSkipSegmentUi.dispose();
    _playSub?.cancel();
    _iptvMemory.lastLiveChannelTimer?.cancel();
    _paramsSub?.cancel();
    _trackSub?.cancel();
    _tvosDecodeRemedy?.dispose();
    _tvosDecodeRemedy = null;
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    _iptvErrorSub?.cancel();
    _rendererStartupErrorSub?.cancel();
    _bufferingDebounceTimer?.cancel();
    _showBufferingIndicator.dispose();
    _releaseAudioEffectSession();
    _screenDisposed = true;
    final subtitleAutoSync = _subtitleSync.subtitleAutoSync;
    _subtitleSync.subtitleAutoSync = null;
    if (_playerCreated) {
      // The slot frees only once the native output has actually gone, not when
      // disposal is requested — the same rule the trailer engines follow.
      () async {
        await subtitleAutoSync?.dispose();
        await _player.dispose();
      }().whenComplete(_releaseVideoOutput);
    } else if (subtitleAutoSync != null) {
      unawaited(subtitleAutoSync.dispose());
      _releaseVideoOutput();
    }
    _transitionStopTimer?.cancel();
    _rainbowController.dispose();
    // Each helper awaits native failures before completing, including disposal.
    if (!replacedPip) {
      unawaited(PlayerDisplayControls.instance.resetBrightness());
      unawaited(PlayerDisplayControls.instance.setWakelock(false));
    }
    if (Platform.isWindows || Platform.isLinux) {
      windowManager.setFullScreen(false);
    }
    if (!replacedPip) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      AndroidNativeDownloader.isTelevision().then((isTv) {
        if (!isTv) {
          // Restore all orientations so the app respects device auto-rotate
          // after the player exits (matches main.dart's _initOrientation).
          // Locking portraitUp here forced users to flip the device back to
          // browse lists after watching in landscape.
          SystemChrome.setPreferredOrientations(<DeviceOrientation>[
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      });
    }
    super.dispose();
  }

  Timer? _autosaveTimer;

  /// True while the auto-hide poll is being held off by a scrub, a pause, a
  /// route or an overlay — so the tick that finds the blocker gone can grant a
  /// full interval instead of hiding on the spot.
  bool _tvAutoHideBlocked = false;

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(VideoPlayerTimingConstants.controlsAutoHideDuration, () {
      if (!mounted) return;
      // Televisions dismiss the dock on INACTIVITY, the way an OTT transport
      // bar does, and only while something is actually playing. A paused TV
      // bar staying up is correct — BACK is how you dismiss that one.
      if (PlatformUtil.isTelevision) {
        // Nothing on screen to dismiss — let the timer lapse rather than
        // re-arming one that would poll forever behind a hidden bar.
        if (!_controlsVisible.value) return;
        // BLOCKED, not finished. A tracks/episodes sheet is a ROUTE: it takes
        // focus, and the bar would be excluded underneath it, leaving nothing
        // sane to focus when the sheet closes. A scrub owns the bar outright,
        // and a paused player is meant to keep it.
        //
        // Re-arm instead of returning: this is a one-shot Timer, so a bare
        // return SPENT it — a scrub or a sheet lasting longer than the
        // interval meant the dock never auto-hid again for the rest of the
        // session. Re-arming makes the block a pause, not a cancellation.
        final route = ModalRoute.of(context);
        if (_tvScrubTarget != null ||
            !_isPlaying ||
            (route != null && !route.isCurrent) ||
            _anyPlayerOverlayOpen) {
          _tvAutoHideBlocked = true;
          _scheduleAutoHide();
          return;
        }
        if (_tvAutoHideBlocked) {
          // The blocker cleared somewhere inside the last poll. Start the
          // interval again from NOW: closing a sheet must not be met by a
          // countdown that already ran out behind it.
          _tvAutoHideBlocked = false;
          _scheduleAutoHide();
          return;
        }
        // Deliberately NOT gated on "focus is inside the bar". Raising the bar
        // always focuses Play/Pause, so that test is true for the entire life
        // of the bar and the timer could never fire — the dock sat over
        // playing video until the user pressed BACK. Every key that reaches
        // the player and every bar action reschedules this timer, so what
        // actually elapses here is INACTIVITY, which is what an OTT dock
        // dismisses on. Route through _tvHideBar so focus leaves the bar
        // before it is excluded; setting the flag alone would strand the
        // remote on a node that no longer exists.
        _tvHideBar();
        return;
      }
      _controlsVisible.value = false;
    });
  }

  // ---- Television transport bar -------------------------------------------

  /// Raise the bar and put focus on Play/Pause (not the first button — the
  /// control you want 90% of the time should be under the thumb already).
  void _tvShowBar() {
    _controlsVisible.value = true;
    // A fresh raise starts from a clean slate: a stale "was blocked" left over
    // from the previous time the bar was up would silently buy this one an
    // extra interval before it could hide.
    _tvAutoHideBlocked = false;
    _scheduleAutoHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controlsVisible.value) return;
      // An open overlay owns the remote — the bar must not pull focus out
      // from under it.
      if (_anyPlayerOverlayOpen) return;
      if (!_tvBarScope.hasFocus) _tvPlayPauseFocus.requestFocus();
    });
  }

  /// Lower the bar and take focus back to the player root. Without the second
  /// half the focused control is excluded from the tree and the remote dies.
  void _tvHideBar() {
    _controlsVisible.value = false;
    // With an overlay up, focus belongs to the overlay (its claim may still
    // be a frame away) — grabbing the root here would strand its DPAD.
    if (!_anyPlayerOverlayOpen) _tvRootFocus.requestFocus();
  }

  /// Cinema scrub: hold LEFT/RIGHT to pause and preview a destination, OK to
  /// confirm, BACK/DOWN to cancel. One seek on confirm, so the trackers and
  /// resume see a single jump instead of a burst.
  void _tvScrubBegin(int direction) {
    if (_tvNoTimeline) return;
    _tvScrubStartedAtGeneration = _tvScrubGeneration;
    _tvScrubWasPlaying = _isPlaying;
    if (_isPlaying) _player.pause();
    _tvScrubTarget = _position;
    _tvShowBar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tvScrubTarget != null) _tvProgressFocus.requestFocus();
    });
    _tvScrubStep(direction);
  }

  void _tvScrubStep(int direction) {
    final base = _tvScrubTarget;
    if (base == null) return;
    // Accelerate with the hold: fine control at first, then long strides so a
    // two-hour remux is crossable without holding the key for a minute.
    final step = _tvScrubRepeats < 8
        ? 10
        : _tvScrubRepeats < 16
        ? 30
        : 60;
    _tvScrubRepeats++;
    final next = base + Duration(seconds: step * direction);
    setState(() {
      _tvScrubTarget = next < Duration.zero
          ? Duration.zero
          : (next > _duration ? _duration : next);
    });
    _scheduleAutoHide();
  }

  void _tvScrubCommit() {
    final target = _tvScrubTarget;
    // Captured when the scrub STARTED. Reading it here would always match and
    // the guard would never fire — a scrub begun before a source switch would
    // happily seek whatever replaced it.
    final generation = _tvScrubStartedAtGeneration;
    if (target == null) return;
    setState(() => _tvScrubTarget = null);
    _tvScrubRepeats = 0;
    // A source switch or dispose bumps the generation; a confirm that lands
    // afterwards must not seek whatever replaced the item being scrubbed.
    if (generation != _tvScrubGeneration || !mounted) return;
    _player.seek(target);
    _trakt.traktScrobbleSeek(target);
    _simkl.simklScrobbleSeek(target);
    _mdblist.mdblistScrobbleSeek(target);
    if (_tvScrubWasPlaying) _player.play();
    if (!_anyPlayerOverlayOpen) _tvPlayPauseFocus.requestFocus();
    // Fresh interval: the countdown that was running belonged to the scrub,
    // and inheriting its remainder could drop the bar the instant OK lands.
    _scheduleAutoHide();
  }

  /// Drop a scrub without seeking and without touching playback — the item it
  /// belonged to is going away. Restoring "was playing" here would fight the
  /// transition, which drives play/pause itself.
  void _tvAbandonScrub() {
    if (_tvScrubTarget == null) return;
    _tvScrubTarget = null;
    _tvScrubRepeats = 0;
  }

  void _tvScrubCancel() {
    if (_tvScrubTarget == null) return;
    setState(() => _tvScrubTarget = null);
    _tvScrubRepeats = 0;
    if (_tvScrubWasPlaying) _player.play();
    if (!_anyPlayerOverlayOpen) _tvPlayPauseFocus.requestFocus();
    _scheduleAutoHide();
  }

  /// The television bar. Reuses every flag the touch call site already
  /// computes, so the two stay in step: live comes from the same
  /// zap-banner signal, sources/guide/record from the same capability checks.
  Widget _buildTvControls() {
    // Live means a live CHANNEL — it decides which button set the dock shows.
    // `hideSeekbar` is a different thing entirely: Magic/Debrify TV sets it on
    // ordinary seekable VOD to hide the scrub bar, and treating it as live
    // stripped episodes, sources and speed from those sessions.
    final isLive = _iptvZapBannerOwnsIdentity;
    final hasSources =
        _effectiveSources != null &&
        _effectiveSources!.isNotEmpty &&
        (_effectiveResolver != null || widget.resolveSourceToPlaylist != null);
    final hasGuide =
        (_channelEntries.isNotEmpty && widget.requestChannelById != null) ||
        _hasStremioTvGuide;

    // BACK precedence, mounted with the bar so `canPop` is always current:
    // cancel a scrub, else close an overlay, else lower the bar, else leave the
    // player. Menu on tvOS arrives here rather than as a key event (measured),
    // so this — not the key handler — is what makes BACK behave.
    return PopScope(
      canPop:
          _tvScrubTarget == null &&
          !_controlsVisible.value &&
          !_anyPlayerOverlayOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        if (_tvScrubTarget != null) {
          _tvScrubCancel();
          return;
        }
        if (_anyPlayerOverlayOpen) {
          _closeTopPlayerOverlay();
          return;
        }
        if (_controlsVisible.value) _tvHideBar();
      },
      child: TvControlsScope(
        seek: (target) {
          _player.seek(target);
          _trakt.traktScrobbleSeek(target);
          _simkl.simklScrobbleSeek(target);
          _mdblist.mdblistScrobbleSeek(target);
          _scheduleAutoHide();
        },
        // `_` on purpose: `context` inside must keep resolving to the State's
        // context, exactly as before this wrapper existed — sheet callbacks
        // like _showTracksSheet await before using it, and the Builder's own
        // element dies whenever the controls subtree is dropped (PiP,
        // not-ready), which the State's context survives.
        child: Builder(
          builder: (_) {
            final showIdentity =
                widget.showVideoTitle && !widget.showChannelName;
            final titleInfo = showIdentity
                ? _getCurrentEpisodeTitleInfo()
                : null;
            return TvControls(
              title: titleInfo?.title ?? '',
              titleIsClean: titleInfo?.fetched ?? false,
              subtitle: showIdentity ? _getCurrentEpisodeSubtitle() : null,
              infoPanel:
                  _buildIptvInfoPanel(flush: true) ??
                  _buildDebrifyTvInfoPanel(flush: true),
              clock: _playbackUiClock,
              isPlaying: _isPlaying,
              isLive: isLive,
              isTransitioning: _isTransitioning,
              scopeNode: _tvBarScope,
              playPauseFocusNode: _tvPlayPauseFocus,
              progressFocusNode: _tvProgressFocus,
              // Dead controls are never focusable: a live stream or an unknown
              // duration has nothing to scrub, so traversal skips the row entirely
              // rather than parking the remote on it.
              progressFocusable: !_tvNoTimeline,
              // OK is claimed by the dock's own buttons, so those presses never
              // reach _handleTvKey and never restarted the countdown.
              onInteract: _scheduleAutoHide,
              scrubPreview: _tvScrubTarget,
              onPlayPause: _togglePlay,
              onShowTracks: () => _menuUi.showTracksSheet(context),
              onSpeed: _display.onSpeedButton,
              onAspect: _display.onAspectButton,
              onSleepTimer: _sleep.showSleepTimerSheet,
              sleepTimerLabel: _sleep.sleepTimerButtonLabel,
              speed: _display.playbackSpeed,
              aspectMode: _display.aspectMode,
              hideOptions: widget.hideOptions,
              onNext: _hasIptvNext
                  ? () => _iptvSwitch.switchToIptvChannel(_currentIptvIndex + 1)
                  : _zapRing.canZapIptvChannel
                  ? () => _zapLadder.zapIptvChannel(1)
                  : (_hasAnyNext ? _goToNextEpisode : null),
              onPrevious: _hasIptvPrevious
                  ? () => _iptvSwitch.switchToIptvChannel(_currentIptvIndex - 1)
                  : _zapRing.canZapIptvChannel
                  ? () => _zapLadder.zapIptvChannel(-1)
                  : (_hasPreviousEpisode() ? _goToPreviousEpisode : null),
              onNextChannel: widget.requestNextChannel != null
                  ? _goToNextChannel
                  : null,
              onShowPlaylist:
                  (_activePlaylist != null && _activePlaylist!.isNotEmpty) ||
                      _canFetchEpisodes
                  ? () => _showPlaylistSheet(context)
                  : null,
              onRandom:
                  _effectiveIptvChannels == null &&
                      ((_activePlaylist?.isNotEmpty ?? false) ||
                          _canFetchEpisodes)
                  ? () => unawaited(_showRandomPlaybackMenu())
                  : null,
              onShowSources: hasSources ? _showSourceSheetOverlay : null,
              onShowGuide: hasGuide
                  ? (_channelEntries.isNotEmpty &&
                            widget.requestChannelById != null
                        ? _showChannelGuideOverlay
                        : _showStremioTvGuideOverlay)
                  : null,
              onShowIptvChannels: _effectiveIptvChannels?.isNotEmpty == true
                  ? _iptvGuide.showIptvChannelSheetOverlay
                  : null,
              hasRecord: _recording.canRecord,
              isRecording: _recording.recordingActiveNow,
              onRecord: _recording.canRecord
                  ? _recording.toggleRecording
                  : null,
              onLiveEdgeAction: _iptvGuide.iptvLiveEdgeAction,
              liveEdgeActionActive: _iptvStartOverActive,
              liveEdgeActionLoading: _iptvStartOverLoading,
              onToggleStartOverTimeline: _iptvStartOverActive
                  ? _iptvGuide.toggleIptvStartOverTimeline
                  : null,
              startOverTimelineVisible: _iptvGuide.iptvStartOverTimelineVisible,
            );
          },
        ),
      ),
    );
  }

  /// Any of the player's in-route overlays. They are not routes, so BACK has to
  /// close them explicitly or it would pop the whole player instead.

  /// Lets BACK reach the IPTV guide's own contract: from the schedule pane it
  /// returns to the channel pane, and closing restores the category an
  /// unfinished all-category search interrupted. On tvOS the Menu press never
  /// reaches the sheet as a key, so the host has to hand it over.
  final GlobalKey<IptvChannelSheetState> _iptvSheetKey =
      GlobalKey<IptvChannelSheetState>();

  /// True once, for the tail of the very BACK press that closed an overlay.
  ///
  /// Driven by an explicit signal from the overlay rather than a clock: a close
  /// by OK, tap or selection must not swallow the user's next deliberate BACK,
  /// which a pure time window did.
  bool get _overlayJustClosed => TvOverlayBack.consume();

  bool get _anyPlayerOverlayOpen =>
      _showSyncOverlay ||
      _showChannelGuide ||
      _showIptvChannelSheet ||
      _showSourceSheet ||
      _showStremioTvGuide ||
      _showPlayerMenu;

  /// Closes the topmost overlay and returns focus to the player root, which the
  /// individual hide methods do not do on their own.
  void _closeTopPlayerOverlay() {
    if (_showPlayerMenu) {
      // Delegate: BACK inside the menu walks values -> rail before closing
      // (tvOS Menu arrives here via PopScope, never as a key).
      if (_playerMenuKey.currentState?.handleHostBack() != true) {
        _menu.hidePlayerMenu();
      }
      // Still open means the press was spent on a pane change.
      if (_showPlayerMenu) return;
    } else if (_showSyncOverlay) {
      _subtitleSync.hideSyncOverlay();
    } else if (_showChannelGuide) {
      _hideChannelGuideOverlay();
    } else if (_showIptvChannelSheet) {
      // Delegate: the guide's own back walks schedule -> channels first, and
      // its close restores a search-interrupted category.
      if (_iptvSheetKey.currentState?.handleHostBack() != true) {
        _iptvGuide.hideIptvChannelSheet();
      }
      // It may still be open (pane change rather than close). Taking focus to
      // the player root would leave its DPAD dead.
      if (_showIptvChannelSheet) return;
    } else if (_showSourceSheet) {
      _hideSourceSheet();
    } else if (_showStremioTvGuide) {
      _hideStremioTvGuide();
    } else {
      return;
    }
    if (PlatformUtil.isTelevision) _tvRootFocus.requestFocus();
  }

  /// Opens whichever guide this session actually has, in the order the dock
  /// offers them. Returns false when there is none, so the caller can fall back
  /// to raising the transport bar.
  bool _openTvGuide() {
    if (_channelEntries.isNotEmpty && widget.requestChannelById != null) {
      _showChannelGuideOverlay();
      return true;
    }
    if (_hasStremioTvGuide) {
      _showStremioTvGuideOverlay();
      return true;
    }
    if (_effectiveIptvChannels?.isNotEmpty == true) {
      _iptvGuide.showIptvChannelSheetOverlay();
      return true;
    }
    return false;
  }

  /// Returns null to let the desktop mapping below handle the key.
  KeyEventResult? _handleTvKey(LogicalKeyboardKey key) {
    // Not const: LogicalKeyboardKey overrides ==, which a const set forbids.
    // The Siri Remote's click pad arrives as `enter` (measured on device);
    // `select`/`gameButtonA` cover Android TV remotes and game controllers.
    final activate = <LogicalKeyboardKey>{
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.gameButtonA,
    };
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;
    final isBack =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

    // A scrub in flight owns the remote completely.
    if (_tvScrubTarget != null) {
      if (isLeft || isRight) {
        _tvScrubStep(isRight ? 1 : -1);
      } else if (activate.contains(key)) {
        _tvScrubCommit();
      } else if (isBack || key == LogicalKeyboardKey.arrowDown) {
        _tvScrubCancel();
      }
      return KeyEventResult.handled;
    }

    // Nothing is actionable until the first frame, and acting during a
    // transition would drive the OUTGOING item.
    // Nothing is actionable before the first frame, and during a switch most
    // actions would drive the OUTGOING item. Two exceptions, both deliberate:
    // BACK must always get you out (a tune can hang on the network), and
    // LEFT/RIGHT must still zap, because a newer switch is allowed to
    // supersede a slow one (_iptvSwitchTicket).
    if (!_isReady || _isTransitioning) {
      if (isBack) return null;
      // Zap directly rather than falling through: the mapping below only zaps
      // when the bar is hidden, so with it up the press would reach the seek
      // branch and seek the OUTGOING item.
      if ((isLeft || isRight) && _zapRing.canZapIptvChannel) {
        _zapLadder.zapIptvChannel(isRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (!_controlsVisible.value) {
      if (activate.contains(key)) {
        // While a skip is offered it owns OK: the button is on screen naming
        // the action, and it lives outside the bar's focus scope so the remote
        // has no other way to reach it.
        if (_skip.activeSkipSegment != null) {
          _skip.skipActiveSegment();
          return KeyEventResult.handled;
        }
        // Native TV player: OK both toggles playback and raises the bar.
        _togglePlay();
        _tvShowBar();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _tvShowBar();
        return KeyEventResult.handled;
      }
      // UP opens the guide, matching the native TV player. The desktop mapping
      // below only knows the Debrify-TV and Stremio guides, so on an IPTV
      // session it fell through to volume and UP appeared dead.
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_openTvGuide()) return KeyEventResult.handled;
        _tvShowBar();
        return KeyEventResult.handled;
      }
      if ((isLeft || isRight) && _tvNoTimeline) {
        // No timeline to move along. Hand the key down ONLY when the mapping
        // below has something real to do with it — zapping to the next
        // channel. Falling through unconditionally reached the generic 10s
        // seek, which on a live stream is a blind jump on a rolling window and
        // on a `hideSeekbar` session is exactly the seek that session turned
        // off. And never enter a scrub whose progress row is hidden.
        return _zapRing.canZapIptvChannel ? null : KeyEventResult.handled;
      }
      if ((isLeft || isRight) && !_zapRing.canZapIptvChannel) {
        // Repeats arriving in quick succession mean the key is held; the third
        // one enters scrub. Slower taps stay 10s nudges, so a single press
        // still does the obvious thing.
        final now = DateTime.now();
        final last = _tvLastArrowAt;
        _tvScrubRepeats =
            (last != null && now.difference(last).inMilliseconds < 400)
            ? _tvScrubRepeats + 1
            : 0;
        _tvLastArrowAt = now;
        if (_tvScrubRepeats >= 2 && _duration > Duration.zero) {
          _tvScrubRepeats = 0;
          _tvScrubBegin(isRight ? 1 : -1);
          return KeyEventResult.handled;
        }
      }
      // UP keeps its existing precedence (channel guide, Stremio guide) and
      // LEFT/RIGHT fall through to zap-or-seek, both already below.
      return null;
    }

    // Bar up: it owns the DPAD and OK.
    if (isBack) {
      _tvHideBar();
      return KeyEventResult.handled;
    }
    if ((isLeft || isRight) && _tvProgressFocus.hasFocus) {
      if (!_tvNoTimeline) {
        _tvScrubBegin(isRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled; // nothing to scrub; don't fall through
    }
    _scheduleAutoHide();
    // Traversal and activation belong to the bar's own focus tree.
    return KeyEventResult.ignored;
  }

  void _toggleControls() {
    _controlsVisible.value = !_controlsVisible.value;
    if (_controlsVisible.value) {
      _scheduleAutoHide();
      // Identity rides IN the bar (IPTV zap panel / Debrify TV banner both
      // embed as the dock's info panel), so nothing floats when it rises.
    }
  }

  void _onControlsVisibilityChanged() {
    _syncPlaybackClockVisibility();
    // The dock carries its own copy of the panel, so the floating one goes the
    // instant the dock opens. Fading it would cross-dissolve two copies of the
    // same panel at two different heights.
    if (_controlsVisible.value) {
      _iptvBanner.hideIptvZapBanner(immediate: true);
      _hideDebrifyBanner(immediate: true);
      // The Record button is about to be looked at — make sure it reflects
      // engine captures stopped from the notification (which this screen
      // otherwise never hears about).
      if (_engineFlagOn) unawaited(_recording.refreshEngineRecordingState());
    }
    // Return focus to the player root whenever the bar goes down, so the
    // remote is never left pointing at a control that has just been excluded
    // from the tree.
    if (PlatformUtil.isTelevision) {
      // Not while an overlay is up: the source / guide / channel sheets
      // autofocus their own KeyboardListener and drive a virtual focus index,
      // so taking focus back here would leave them unable to see any keys.
      if (!_controlsVisible.value &&
          _tvBarScope.hasFocus &&
          !_anyPlayerOverlayOpen) {
        _tvRootFocus.requestFocus();
      }
    }
    _iptvBanner.syncIptvBannerTicker();
  }

  Future<void> _handleDoubleTap(TapDownDetails details) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final localPos = details.localPosition;
    // Avoid edge conflicts with system back gesture by requiring a margin
    const edgeGuard = 24.0;
    if (localPos.dx < edgeGuard || localPos.dx > size.width - edgeGuard) return;
    // If controls visible, ignore double-taps near top/bottom bars to not clash with buttons/slider
    if (_controlsVisible.value) {
      const topBar = 72.0;
      final bottomBar = _dockBand(72.0);
      if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) return;
    }

    // Default seek behavior for left/right taps
    final isLeft = localPos.dx < size.width / 2;
    final delta = VideoPlayerTimingConstants.seekDelta;
    final target = _position + (isLeft ? -delta : delta);
    final minPos = Duration.zero;
    final maxPos = _duration;
    final clamped = target < minPos
        ? minPos
        : (target > maxPos ? maxPos : target);
    await _player.seek(clamped);
    _trakt.traktScrobbleSeek(clamped);
    _simkl.simklScrobbleSeek(clamped);
    _mdblist.mdblistScrobbleSeek(clamped);
    _ripple = DoubleTapRipple(
      center: localPos,
      icon: isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
    );
    setState(() {});
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _ripple = null);
    });
  }

  void _onPanStart(DragStartDetails details) async {
    // If controls are visible, ignore pans that begin within top/bottom bars so buttons and slider work unaffected
    _panIgnore = false;
    if (_controlsVisible.value) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        final size = box.size;
        const topBar = 72.0;
        final bottomBar = _dockBand(72.0);
        final dy = details.localPosition.dy;
        if (dy < topBar || dy > size.height - bottomBar) {
          _panIgnore = true;
          return;
        }
      }
    }
    _gestureStartPosition = details.localPosition;
    _gestureStartVideoPosition = _position;
    _gestureStartVolume = (_player.state.volume / 100.0).clamp(0.0, 1.0);
    _gestureStartBrightness = await PlayerDisplayControls.instance.brightness();
    if (!mounted) return;
    _mode = GestureMode.none;
    _verticalHud.value = null;
    _seekHud.value = null;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_panIgnore) return;
    final dx = details.localPosition.dx - _gestureStartPosition.dx;
    final dy = details.localPosition.dy - _gestureStartPosition.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();
    final size = (context.findRenderObject() as RenderBox).size;

    // Decide mode on first significant movement
    if (_mode == GestureMode.none) {
      if (absDx > 12 && absDx > absDy) {
        _mode = GestureMode.seek;
      } else if (absDy > 12) {
        final isLeftHalf = _gestureStartPosition.dx < size.width / 2;
        if (isLeftHalf && !PlayerDisplayControls.supportsBrightness) return;
        _mode = isLeftHalf ? GestureMode.brightness : GestureMode.volume;
      }
    }

    if (_mode == GestureMode.seek) {
      final duration = _duration;
      if (duration == Duration.zero) return;
      // Map horizontal delta to seconds, proportional to width
      final totalSeconds = duration.inSeconds.toDouble();
      final seekSeconds = (dx / size.width) * math.min(120.0, totalSeconds);
      var newPos =
          _gestureStartVideoPosition + Duration(seconds: seekSeconds.round());
      if (newPos < Duration.zero) newPos = Duration.zero;
      if (newPos > duration) newPos = duration;
      _seekHud.value = SeekHudState(
        target: newPos,
        base: _position,
        isForward: newPos >= _position,
      );
    } else if (_mode == GestureMode.volume) {
      var newVol = (_gestureStartVolume - dy / size.height).clamp(0.0, 1.0);
      _player.setVolume((newVol * 100).clamp(0.0, 100.0));
      _verticalHud.value = VerticalHudState(
        kind: VerticalKind.volume,
        value: newVol,
      );
    } else if (_mode == GestureMode.brightness) {
      var newBright = (_gestureStartBrightness - dy / size.height).clamp(
        0.0,
        1.0,
      );
      unawaited(PlayerDisplayControls.instance.setBrightness(newBright));
      _verticalHud.value = VerticalHudState(
        kind: VerticalKind.brightness,
        value: newBright,
      );
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panIgnore) return;
    if (_mode == GestureMode.seek && _seekHud.value != null) {
      final target = _seekHud.value!.target;
      _player.seek(target);
      _trakt.traktScrobbleSeek(target);
      _simkl.simklScrobbleSeek(target);
      _mdblist.mdblistScrobbleSeek(target);
    }
    _mode = GestureMode.none;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        _seekHud.value = null;
        _verticalHud.value = null;
      }
    });
  }

  void _togglePlay() {
    if (!_isReady) return;
    if (_isPlaying) {
      _activeMediaUserPaused = true;
      _activeMediaShouldPlay = false;
      _player.pause();
      unawaited(_resumeSave.saveResume(positionOverride: _position));
    } else {
      // An explicit press is the one thing that clears a sleep stop.
      _sleepStopLatched = false;
      _activeMediaUserPaused = false;
      _activeMediaShouldPlay = true;
      _player.play();
    }
    _scheduleAutoHide();
  }

  /// Sets manual episode selection mode with automatic reset after 30 seconds
  void _setManualSelectionMode({bool allowResume = false}) {
    _isManualEpisodeSelection = true;
    _allowResumeForManualSelection = allowResume;
    _manualSelectionResetTimer?.cancel();
    _manualSelectionResetTimer = Timer(
      VideoPlayerTimingConstants.manualSelectionResetDuration,
      () {
        _isManualEpisodeSelection = false;
        _allowResumeForManualSelection = false;
      },
    );
  }

  // Build subtitle view configuration from settings
  // NOTE: the television bar deliberately does NOT move subtitles.
  //
  // Native visibility remains off for text tracks because enabling it draws
  // every line twice (MediaKit also renders those cues in Flutter). Bitmap
  // selections toggle it separately because they have no text cues. Padding
  // subtitles upward fought the user's own subtitle
  // elevation setting and threw them into the middle of the screen. The bar is
  // transient and the elevation setting already exists for exactly this
  // preference, so subtitles stay where the user put them.
  mkv.SubtitleViewConfiguration _buildSubtitleViewConfig() {
    if (VpS2Hooks.isIOS && (_isPipActive || _pip.iosPipStarting)) {
      return const mkv.SubtitleViewConfiguration(visible: false);
    }
    final settings = _subtitleSettings;
    if (settings == null) {
      return const mkv.SubtitleViewConfiguration();
    }

    return mkv.SubtitleViewConfiguration(
      style: settings.buildTextStyle(),
      padding: EdgeInsets.fromLTRB(16, 0, 16, settings.elevation.bottomPadding),
    );
  }

  // Build video with custom aspect ratio
  Widget _buildCustomAspectRatioVideo() {
    return AspectRatioVideo(
      key: ValueKey(
        'video_elevation_${_subtitleSettings?.elevationIndex ?? 0}',
      ),
      videoController: _videoController,
      pauseUponEnteringBackgroundMode: !Platform.isIOS,
      customAspectRatio: _display.getCustomAspectRatio(),
      currentFit: _display.currentFit(),
      subtitleViewConfiguration: _buildSubtitleViewConfig(),
    );
  }

  // Fullscreen transition overlay: retro TV static effect (matches Android TV)
  Widget _buildTransitionOverlay() {
    return TransitionOverlay(
      rainbowController: _rainbowController,
      tvStaticMessage: _tvStaticMessage,
      tvStaticSubtext: _tvStaticSubtext,
    );
  }

  Widget _buildStremioTvNextLoadingOverlay() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _showStremioTvNextLoading ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Loading next...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The live-IPTV panel, or null when this playback has no channel identity
  /// to present. [flush] embeds it in the controls dock; otherwise it floats.
  /// Debrify TV owns the session identity when the launch asked for the
  /// channel chrome and no live IPTV banner does.
  bool get _debrifyTvOwnsIdentity =>
      widget.showChannelName && !_iptvZapBannerOwnsIdentity;

  Widget? _buildDebrifyTvInfoPanel({required bool flush}) {
    if (!_debrifyTvOwnsIdentity) return null;
    final name = (_currentChannelName ?? widget.channelName)?.trim();
    final title = widget.showVideoTitle ? _getCurrentEpisodeTitle() : null;
    if ((name == null || name.isEmpty) &&
        _currentChannelNumber == null &&
        (title == null || title.isEmpty)) {
      return null;
    }
    return DebrifyTvBanner(
      channelNumber: _currentChannelNumber,
      channelName: name,
      title: title,
      clock: _playbackUiClock,
      // hideSeekbar keeps runtimes a surprise — the banner must not leak
      // what the dock hides.
      showProgress: !widget.hideSeekbar,
      flush: flush,
    );
  }

  /// The clock is an optimization gate — it only publishes while something
  /// on screen reads it. That used to mean "the bar"; the floating Debrify
  /// banner's progress row reads it too (only when the session shows
  /// progress at all).
  void _syncPlaybackClockVisibility() {
    _playbackUiClock.setVisible(
      _controlsVisible.value ||
          (_showDebrifyBanner && _debrifyTvOwnsIdentity && !widget.hideSeekbar),
    );
  }

  /// Raises the floating lower-third (tune, zap, launch). The hide timer
  /// re-arms while a channel switch is still resolving — the old corner
  /// badges timed out DURING the resolve, which is why tvOS never saw them.
  void _raiseDebrifyBanner() {
    if (!_debrifyTvOwnsIdentity) return;
    if (_anyPlayerOverlayOpen || _controlsVisible.value) return;
    _debrifyBannerTimer?.cancel();
    setState(() {
      _showDebrifyBanner = true;
      _debrifyBannerFloatingMounted = true;
    });
    _syncPlaybackClockVisibility();
    _armDebrifyBannerTimer();
  }

  void _armDebrifyBannerTimer() {
    // While resolving, poll fast — so the FULL display window is granted
    // from (roughly) the moment the new stream lands, not from zap start.
    final resolving = _isTransitioning;
    _debrifyBannerTimer = Timer(
      resolving
          ? const Duration(milliseconds: 400)
          : VideoPlayerTimingConstants.badgeDisplayDuration,
      () {
        if (!mounted) return;
        if (resolving || _isTransitioning) {
          // Either this was a resolve-poll, or a new switch began
          // mid-window: keep the identity up and re-evaluate.
          _armDebrifyBannerTimer();
          return;
        }
        setState(() => _showDebrifyBanner = false);
        _syncPlaybackClockVisibility();
      },
    );
  }

  void _hideDebrifyBanner({bool immediate = false}) {
    _debrifyBannerTimer?.cancel();
    if (!_showDebrifyBanner && !(immediate && _debrifyBannerFloatingMounted)) {
      return;
    }
    setState(() {
      _showDebrifyBanner = false;
      if (immediate) _debrifyBannerFloatingMounted = false;
    });
    _syncPlaybackClockVisibility();
  }

  Widget? _buildIptvInfoPanel({required bool flush}) {
    final channel = _iptvZapChannel;
    if (channel == null || !_iptvZapBannerOwnsIdentity) return null;
    return IptvZapBanner(
      channel: channel,
      epg: _iptvZapEpg,
      epgLoading: _iptvZapEpgLoading,
      now: _iptvZapClock,
      flush: flush,
      style: _playerGuideStyle,
      tokens: _playerGuideTokens,
      isRecording: _recording.recordingActiveNow,
    );
  }

  // ─── Episode guide: in-player fetch of absent episodes ────────────────

  /// Whether an episode that isn't in the current playlist can be fetched
  /// and played without leaving the player: catalog series content with a
  /// live fetcher + resolver, outside the channel-style modes (Stremio TV /
  /// IPTV / Debrify TV own their identity and next/prev semantics).
  bool get _canFetchEpisodes =>
      widget.seriesSourceFetcher != null &&
      !widget.seriesSourceFetcher!.isMovie &&
      widget.resolveSourceToPlaylist != null &&
      _stremioSourcesOverride == null &&
      _effectiveStremioTvChannels == null &&
      _effectiveIptvChannels == null &&
      widget.requestMagicNext == null;

  bool _episodeFetchInProgress = false;

  // Synthetic 1-entry guide backing for single-stream launches (no playlist):
  // lets the episode guide open and offer the show's full episode list.
  SeriesPlaylist? _syntheticGuidePlaylist;
  List<PlaylistEntry>? _syntheticGuideEntries;

  (SeriesPlaylist, List<PlaylistEntry>)? _buildSyntheticGuide() {
    final existingSp = _syntheticGuidePlaylist;
    final existingEntries = _syntheticGuideEntries;
    if (existingSp != null && existingEntries != null) {
      return (existingSp, existingEntries);
    }
    final se = _traktSeasonEpisode();
    if (se.season == null || se.episode == null) return null;
    var title = widget.title;
    final info = SeriesParser.parseFilename(title);
    if (info.season == null || info.episode == null) {
      // Stamp the playing episode's identity so the guide groups it right.
      title = 'S${vpPad2(se.season!)}E${vpPad2(se.episode!)} $title';
    }
    final entries = [PlaylistEntry(url: widget.videoUrl, title: title)];
    final sp = SeriesPlaylist.fromPlaylistEntries(
      entries,
      collectionTitle: widget.contentTitle ?? widget.title,
      forceSeries: true,
    );
    sp.imdbId = _currentSeriesImdbId;
    _syntheticGuidePlaylist = sp;
    _syntheticGuideEntries = entries;
    return (sp, entries);
  }

  bool _packCoversSeason(Torrent t, int season) {
    switch (t.coverageType) {
      case 'completeSeries':
        final start = t.startSeason;
        final end = t.endSeason;
        if (start == null && end == null) return true;
        return season >= (start ?? 1) && season <= (end ?? season);
      case 'multiSeasonPack':
        final start = t.startSeason;
        final end = t.endSeason;
        return start != null && end != null && season >= start && season <= end;
      case 'seasonPack':
        return t.seasonNumber == season;
      default:
        return false;
    }
  }

  /// Quick-play an episode that isn't in the current playlist, WITHOUT
  /// leaving the player: try packs already in the source list, then an
  /// episode-targeted fetch, then a fresh pack search — switching to the
  /// first candidate that resolves and actually contains the episode.
  Future<EpisodePlaybackOutcome> _fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  }) async {
    if (!_canFetchEpisodes || _episodeFetchInProgress) {
      // A next/prev press may have raised the transition curtain already;
      // never leave it up when the request can't run.
      if (mounted && _isTransitioning) {
        setState(() => _isTransitioning = false);
      }
      return EpisodePlaybackOutcome.cancelled;
    }
    if (request == null) _episodeNavigationGeneration++;
    request ??= EpisodePlaybackRequest(
      currentIdentity: () => _playlistIdentityToken,
      currentNavigation: () => _episodeNavigationGeneration,
      isActive: () =>
          mounted &&
          (!autoAdvance || !_sleepStopLatched) &&
          (shuffleGeneration == null ||
              shuffleGeneration == _showShuffleGeneration),
    );
    final fetcher = widget.seriesSourceFetcher!;
    _episodeFetchInProgress = true;
    final messenger = ScaffoldMessenger.of(context);
    final label = 'S${vpPad2(season)}E${vpPad2(episode)}';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Fetching $label…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final pinned = fetcher.pinnedDirectCandidates;
      if (pinned != null) {
        await for (final candidate in pinned(
          season,
          episode,
          onPreferredMissing: () {
            if (!request!.isCurrent || !mounted) return;
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Your previous source is unavailable for this episode. Trying other sources.',
                ),
              ),
            );
          },
        )) {
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
          final sources = List<Torrent>.of(_effectiveSources ?? const []);
          final index = sources.length;
          sources.add(candidate);
          setState(() => _augmentedSources = sources);
          final outcome = await _tryEpisodeCandidate(
            index,
            candidate,
            season,
            episode,
            request,
            shuffleGeneration: shuffleGeneration,
            autoAdvance: autoAdvance,
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
        }
      }

      // 1. Try what's already in the source list: exact-episode singles and
      // packs covering the season (often already unlocked on the account).
      final existing = List<Torrent>.of(_effectiveSources ?? const <Torrent>[]);
      var attempts = 0;
      for (var i = 0; i < existing.length && attempts < 4; i++) {
        if (i == _currentSourceIndex) continue;
        final t = existing[i];
        if (t.streamType == StreamType.externalUrl) continue;
        final info = SeriesParser.parseFilename(t.displayTitle);
        final matchesEpisode = info.season == season && info.episode == episode;
        final coversAsPack =
            t.streamType == StreamType.torrent && _packCoversSeason(t, season);
        if (!matchesEpisode && !coversAsPack) continue;
        attempts++;
        final outcome = await _tryEpisodeCandidate(
          i,
          t,
          season,
          episode,
          request,
          shuffleGeneration: shuffleGeneration,
          autoAdvance: autoAdvance,
        );
        if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
        if (!request.isCurrent) {
          return EpisodePlaybackOutcome.cancelled;
        }
      }

      // 2. Episode-targeted fetch (direct links resolve instantly).
      List<Torrent>? fetched;
      try {
        fetched = await fetcher.fetch(
          SeriesSourceFetcher.modeEpisodes,
          season: season,
          episode: episode,
        );
      } catch (_) {
        fetched = null;
      }
      if (!request.isCurrent) {
        return EpisodePlaybackOutcome.cancelled;
      }
      if (fetched != null && fetched.isNotEmpty) {
        final base = _effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, fetched);
        setState(() => _augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 5; i++) {
          final t = merged[i];
          if (t.streamType == StreamType.externalUrl) continue;
          attempts++;
          final outcome = await _tryEpisodeCandidate(
            i,
            t,
            season,
            episode,
            request,
            shuffleGeneration: shuffleGeneration,
            autoAdvance: autoAdvance,
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
        }
      }

      // 3. Last resort: a fresh pack search for that season.
      List<Torrent>? packs;
      try {
        packs = await fetcher.fetch(
          SeriesSourceFetcher.modePacks,
          season: season,
          episode: episode,
        );
      } catch (_) {
        packs = null;
      }
      if (!request.isCurrent) {
        return EpisodePlaybackOutcome.cancelled;
      }
      if (packs != null && packs.isNotEmpty) {
        final base = _effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, packs);
        setState(() => _augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 3; i++) {
          final t = merged[i];
          if (t.streamType != StreamType.torrent) continue;
          // Pack-search results are season-targeted; only skip ones whose
          // detected coverage positively excludes the season.
          if (t.coverageType != null && !_packCoversSeason(t, season)) {
            continue;
          }
          attempts++;
          final outcome = await _tryEpisodeCandidate(
            i,
            t,
            season,
            episode,
            request,
            shuffleGeneration: shuffleGeneration,
            autoAdvance: autoAdvance,
          );
          if (outcome != EpisodePlaybackOutcome.unavailable) return outcome;
          if (!request.isCurrent) {
            return EpisodePlaybackOutcome.cancelled;
          }
        }
      }

      if (request.isCurrent) {
        // A next/prev press raised the transition curtain before calling in
        // here — drop it, or a failed fetch leaves the screen black.
        if (_isTransitioning) {
          setState(() => _isTransitioning = false);
        }
        messenger.showSnackBar(
          SnackBar(content: Text('No playable source found for $label')),
        );
      }
      return EpisodePlaybackOutcome.unavailable;
    } finally {
      _episodeFetchInProgress = false;
    }
  }

  /// Resolve one candidate and switch to it when it actually contains the
  /// target episode, reporting failure independently of playlist replacement.
  Future<EpisodePlaybackOutcome> _tryEpisodeCandidate(
    int sourceIndex,
    Torrent t,
    int season,
    int episode,
    EpisodePlaybackRequest request, {
    int? shuffleGeneration,
    bool autoAdvance = false,
  }) async {
    logSourceSelection(
      'next_episode_candidate',
      source: t,
      index: sourceIndex,
      season: season,
      episode: episode,
      player: 'mpv',
    );
    if (!await widget.seriesSourceFetcher!.allowsCandidate(t)) {
      return EpisodePlaybackOutcome.unavailable;
    }
    if (!request.isCurrent) return EpisodePlaybackOutcome.cancelled;
    List<PlaylistEntry>? playlist;
    try {
      playlist = await widget.resolveSourceToPlaylist!(
        t,
        canContinue: () => request.isCurrent,
      );
    } catch (_) {
      playlist = null;
    }
    if (!request.isCurrent) return EpisodePlaybackOutcome.cancelled;
    if (playlist == null || playlist.isEmpty) {
      logSourceSelection(
        'next_episode_candidate_rejected',
        source: t,
        index: sourceIndex,
        season: season,
        episode: episode,
        player: 'mpv',
        reason: 'no_playlist',
      );
      return EpisodePlaybackOutcome.unavailable;
    }
    if (playlist.length == 1) {
      final info = SeriesParser.parseFilename(playlist.first.title);
      if (info.season == null || info.episode == null) {
        // Unparseable single stream: stamp the target identity into the
        // title so parsing (titles, scrobbling, the guide) stays coherent.
        playlist = [
          playlist.first.copyWithTitle(
            'S${vpPad2(season)}E${vpPad2(episode)} ${playlist.first.title}',
          ),
        ];
      } else if (info.season != season || info.episode != episode) {
        return EpisodePlaybackOutcome
            .unavailable; // resolves to a DIFFERENT episode — wrong result
      }
    } else {
      final sp = SeriesPlaylist.fromPlaylistEntries(
        playlist,
        collectionTitle: widget.title,
        forceSeries: true,
      );
      if (sp.findOriginalIndexBySeasonEpisode(season, episode) < 0) {
        return EpisodePlaybackOutcome
            .unavailable; // pack without the target — try the next candidate
      }
    }
    _setManualSelectionMode(allowResume: true);
    _isAutoAdvancing = autoAdvance;
    final resolvedPlaylist = playlist;
    final outcome = await request.attempt(
      () => _switchToSourcePlaylist(
        sourceIndex,
        resolvedPlaylist,
        targetSeason: season,
        targetEpisode: episode,
        suppressResume: autoAdvance || shuffleGeneration != null,
        request: request,
      ),
    );
    if (outcome == EpisodePlaybackOutcome.committed &&
        mounted &&
        request.isCurrent) {
      final retained = SeriesSourceFetcher.retainForEpisode(
        _effectiveSources ?? const <Torrent>[],
        season,
        episode,
      );
      var retainedIndex = retained.indexWhere((source) => identical(source, t));
      retainedIndex = retainedIndex >= 0
          ? retainedIndex
          : retained.indexWhere(
              (source) =>
                  SeriesSourceFetcher.sourceKey(source) ==
                  SeriesSourceFetcher.sourceKey(t),
            );
      if (retainedIndex >= 0) {
        setState(() {
          _augmentedSources = retained;
          _currentSourceIndex = retainedIndex;
        });
      }
    }
    logSourceSelection(
      'next_episode_candidate_outcome',
      source: t,
      index: sourceIndex,
      season: season,
      episode: episode,
      player: 'mpv',
      reason: outcome.name,
    );
    return outcome;
  }

  /// Resolve with the origin first; only an unavailable guide permits fallback.
  Future<({int season, int episode})?> _resolveAdjacentWithCachedGuide(
    int season,
    int episode,
    int direction,
  ) async {
    final resolver = widget.seriesSourceFetcher?.resolveAdjacentEpisode;
    if (resolver == null) return null;
    return resolveAdjacentWithGuideFallback(
      resolver: resolver,
      season: season,
      episode: episode,
      direction: direction,
      cachedGuide: () {
        final target = _adjacentEpisode(
          season,
          episode,
          direction,
          allowResolverFallback: true,
        );
        return target == null ? null : (season: target.$1, episode: target.$2);
      },
    );
  }

  (int, int)? _adjacentEpisode(
    int season,
    int episode,
    int direction, {
    bool allowResolverFallback = false,
  }) {
    // Custom catalogs own their episode order, even after TVMaze fills the guide.
    if (!allowResolverFallback &&
        widget.seriesSourceFetcher?.resolveAdjacentEpisode != null)
      return null;
    final full = _seriesPlaylist?.fullTvmazeEpisodes.isNotEmpty == true
        ? _seriesPlaylist!.fullTvmazeEpisodes
        : (_syntheticGuidePlaylist?.fullTvmazeEpisodes ??
              const <Map<String, dynamic>>[]);
    final target = cachedGuideAdjacentEpisode(full, season, episode, direction);
    return target == null ? null : (target.season, target.episode);
  }

  void _prepareNextDirectEpisode() {
    final fetcher = widget.seriesSourceFetcher;
    final sources = _effectiveSources;
    if (fetcher == null ||
        _validationGateActive ||
        !_isPlaying ||
        _isTransitioning ||
        sources == null ||
        _currentSourceIndex < 0 ||
        _currentSourceIndex >= sources.length)
      return;
    final current = _identify.currentSeasonEpisodeForIdentity();
    if (current == null) return;
    unawaited(
      fetcher.prepareFromProgress(
        source: sources[_currentSourceIndex],
        season: current.season,
        episode: current.episode,
        positionMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
      ),
    );
  }

  Future<void> _showPlaylistSheet(BuildContext context) async {
    var playlist = _activePlaylist ?? const <PlaylistEntry>[];
    var seriesPlaylist = _seriesPlaylist;
    var currentIndex = _currentIndex;
    final canFetch = _canFetchEpisodes;
    if (playlist.isEmpty && canFetch) {
      // Single stream without a playlist: back the guide with a synthetic
      // 1-entry playlist so the full episode list can render.
      final synthetic = _buildSyntheticGuide();
      if (synthetic == null) return;
      seriesPlaylist = synthetic.$1;
      playlist = synthetic.$2;
      currentIndex = 0;
    }
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      _episodeMetadataReady ??= _preloadEpisodeInfo();
    }
    await PlaylistSheet.show(
      context,
      playlist: playlist,
      currentIndex: currentIndex,
      seriesPlaylist: seriesPlaylist,
      playlistItemData: _constructPlaylistItemData(),
      imdbId: seriesPlaylist?.imdbId ?? _currentSeriesImdbId,
      imdbKnownAtLaunch: _seriesImdbKnownAtLaunch,
      metadataReady: _episodeMetadataReady,
      viewMode: widget.viewMode,
      onSelect: (index, {bool allowResume = false}) async {
        // Synthetic guide: its only playlist row IS the playing stream.
        if (_activePlaylist == null || _activePlaylist!.isEmpty) return;
        _setManualSelectionMode(allowResume: allowResume);
        await _loadPlaylistIndex(index, autoplay: true);
      },
      onFetchEpisode: canFetch ? _fetchAndPlayEpisode : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _isReady;
    // In the PiP window, hide every interactive/decorative layer so only the
    // video texture (and the buffering spinner) shows. Restores on exit.
    final inPip = _isPipActive;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        left: false,
        top: false,
        right: false,
        bottom: false,
        child: Focus(
          focusNode: _tvRootFocus,
          autofocus: true,
          onKey: (node, event) {
            if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;

            // Unified menu is open. Like the IPTV sheet, it owns every key
            // including BACK (values -> rail -> close, with TvOverlayBack
            // marking the closing press); its KeyboardListener holds focus.
            if (_showPlayerMenu) {
              return KeyEventResult.ignored;
            }

            // Sync overlay is open - handle its keys first
            if (_showSyncOverlay) {
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _subtitleSync.hideSyncOverlay();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            // Channel guide is open - handle its keys first
            if (_showChannelGuide) {
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _hideChannelGuideOverlay();
                return KeyEventResult.handled;
              }
              // Let channel guide handle other keys
              return KeyEventResult.ignored;
            }

            // IPTV channel sheet is open. It owns BACK itself — from the
            // schedule pane it returns to channels rather than closing, and
            // closing restores a search-interrupted category. Handling BACK
            // here as well fired both: the sheet changed pane and this closed
            // it. Its KeyboardListener holds focus (it claims it on mount), so
            // every key including BACK reaches it first.
            if (_showIptvChannelSheet) {
              return KeyEventResult.ignored;
            }

            // Source sheet is open - handle its keys first
            if (_showSourceSheet) {
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _hideSourceSheet();
                return KeyEventResult.handled;
              }
              // Let source sheet handle other keys
              return KeyEventResult.ignored;
            }

            // Stremio TV guide is open - handle its keys first
            if (_showStremioTvGuide) {
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _hideStremioTvGuide();
                return KeyEventResult.handled;
              }
              // Let guide sheet handle other keys
              return KeyEventResult.ignored;
            }

            // ---- Television remote ------------------------------------
            // Everything below was written for a desktop keyboard: letters,
            // volume on UP/DOWN, arrows that always seek. A remote has no
            // letters, its OK arrives as `enter`, and while the bar is up the
            // DPAD belongs to the bar. Mirrors the native Android TV player so
            // both players behave the same. Touch and desktop never enter here.
            if (PlatformUtil.isTelevision) {
              final tvResult = _handleTvKey(key);
              if (tvResult != null) return tvResult;
            }

            // A -> Aspect ratio
            if (key == LogicalKeyboardKey.keyA) {
              _display.cycleAspectMode();
              return KeyEventResult.handled;
            }

            // G -> Channel guide (Debrify TV or Stremio TV)
            if (key == LogicalKeyboardKey.keyG) {
              if (_channelEntries.isNotEmpty &&
                  widget.requestChannelById != null) {
                _showChannelGuideOverlay();
                return KeyEventResult.handled;
              }
              if (_hasStremioTvGuide) {
                _showStremioTvGuideOverlay();
                return KeyEventResult.handled;
              }
              if (_effectiveIptvChannels?.isNotEmpty == true) {
                _iptvGuide.showIptvChannelSheetOverlay();
                return KeyEventResult.handled;
              }
            }

            // C -> IPTV channel sheet
            if (key == LogicalKeyboardKey.keyC) {
              if (_effectiveIptvChannels?.isNotEmpty == true) {
                _iptvGuide.showIptvChannelSheetOverlay();
                return KeyEventResult.handled;
              }
            }

            // S -> Stremio source sheet
            if (key == LogicalKeyboardKey.keyS) {
              if (_effectiveSources != null &&
                  _effectiveSources!.isNotEmpty &&
                  (_effectiveResolver != null ||
                      widget.resolveSourceToPlaylist != null)) {
                _showSourceSheetOverlay();
                return KeyEventResult.handled;
              }
            }

            // Space -> Pause resume
            if (key == LogicalKeyboardKey.space) {
              _togglePlay();
              return KeyEventResult.handled;
            }

            // Up arrow -> Channel guide (if channels available) or Volume
            if (key == LogicalKeyboardKey.arrowUp) {
              // If channels are available, show channel guide
              if (_channelEntries.isNotEmpty &&
                  widget.requestChannelById != null) {
                _showChannelGuideOverlay();
                return KeyEventResult.handled;
              }
              // Stremio TV guide
              if (_hasStremioTvGuide) {
                _showStremioTvGuideOverlay();
                return KeyEventResult.handled;
              }

              // Otherwise, control volume
              _controlsVisible.value = true;
              _scheduleAutoHide();

              // Increase volume
              final currentVolume = (_player.state.volume / 100.0).clamp(
                0.0,
                1.0,
              );
              final newVolume = (currentVolume + 0.1).clamp(0.0, 1.0);
              _player.setVolume((newVolume * 100).clamp(0.0, 100.0));

              // Show volume HUD
              _verticalHud.value = VerticalHudState(
                kind: VerticalKind.volume,
                value: newVolume,
              );
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted) {
                  _verticalHud.value = null;
                }
              });

              return KeyEventResult.handled;
            }

            if (key == LogicalKeyboardKey.arrowDown) {
              // Show controls first
              _controlsVisible.value = true;
              _scheduleAutoHide();

              // Decrease volume
              final currentVolume = (_player.state.volume / 100.0).clamp(
                0.0,
                1.0,
              );
              final newVolume = (currentVolume - 0.1).clamp(0.0, 1.0);
              _player.setVolume((newVolume * 100).clamp(0.0, 100.0));

              // Show volume HUD
              _verticalHud.value = VerticalHudState(
                kind: VerticalKind.volume,
                value: newVolume,
              );
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted) {
                  _verticalHud.value = null;
                }
              });

              return KeyEventResult.handled;
            }

            // Center/Enter toggles play or shows controls
            if (isActivateKey(key)) {
              if (_controlsVisible.value) {
                _togglePlay();
              } else {
                _toggleControls();
              }
              return KeyEventResult.handled;
            }

            // DPAD left/right zap channels on a live channel with the controls
            // hidden — the same contract as the native player's
            // isLiveIptvZapContext(). There is nothing to seek on a live
            // stream, and with the dock up these keys belong to its buttons.
            if (_zapRing.canZapIptvChannel && !_controlsVisible.value) {
              if (key == LogicalKeyboardKey.arrowRight) {
                _zapLadder.zapIptvChannel(1);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                _zapLadder.zapIptvChannel(-1);
                return KeyEventResult.handled;
              }
            }

            // DPAD left/right seek 10s
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.mediaRewind) {
              final candidate =
                  _position - VideoPlayerTimingConstants.seekDelta;
              final newPos = candidate < Duration.zero
                  ? Duration.zero
                  : (candidate > _duration ? _duration : candidate);
              _player.seek(newPos);
              _trakt.traktScrobbleSeek(newPos);
              _simkl.simklScrobbleSeek(newPos);
              _mdblist.mdblistScrobbleSeek(newPos);
              // Don't show controls or any overlay for keyboard seeking
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowRight ||
                key == LogicalKeyboardKey.mediaFastForward) {
              final candidate =
                  _position + VideoPlayerTimingConstants.seekDelta;
              final newPos = candidate < Duration.zero
                  ? Duration.zero
                  : (candidate > _duration ? _duration : candidate);
              _player.seek(newPos);
              _trakt.traktScrobbleSeek(newPos);
              _simkl.simklScrobbleSeek(newPos);
              _mdblist.mdblistScrobbleSeek(newPos);
              // Don't show controls or any overlay for keyboard seeking
              return KeyEventResult.handled;
            }

            // Media play/pause keys
            if (key == LogicalKeyboardKey.mediaPlayPause ||
                key == LogicalKeyboardKey.mediaPlay ||
                key == LogicalKeyboardKey.mediaPause) {
              _togglePlay();
              return KeyEventResult.handled;
            }

            // N key for next episode (Mac)
            if (key == LogicalKeyboardKey.keyN) {
              if (_hasAnyNext) {
                _goToNextEpisode();
                return KeyEventResult.handled;
              }
            }

            // F / F11: toggle fullscreen on Windows/Linux
            if ((key == LogicalKeyboardKey.keyF ||
                    key == LogicalKeyboardKey.f11) &&
                (Platform.isWindows || Platform.isLinux)) {
              windowManager.isFullScreen().then((isFullScreen) {
                if (!mounted) return;
                windowManager.setFullScreen(!isFullScreen);
              });
              return KeyEventResult.handled;
            }

            // An overlay closed itself on this very BACK press (see
            // [TvOverlayBack]): the press is already spent, so it must not
            // also quit the player.
            if ((key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack) &&
                _overlayJustClosed) {
              return KeyEventResult.handled;
            }

            // Escape key: exit fullscreen first, then quit the player
            if (key == LogicalKeyboardKey.escape) {
              // On Windows/Linux desktop, exit fullscreen first if in fullscreen
              if (Platform.isWindows || Platform.isLinux) {
                windowManager.isFullScreen().then((isFullScreen) {
                  if (!mounted) return; // Safety check for async callback
                  if (isFullScreen) {
                    // Exit fullscreen but don't quit the player
                    windowManager.setFullScreen(false);
                  } else {
                    // Not in fullscreen, quit the player
                    Navigator.of(context).pop();
                  }
                });
                return KeyEventResult.handled;
              }
              // On other platforms (mobile, macOS), just quit
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }

            // Next/Previous episode navigation
            if (key == LogicalKeyboardKey.mediaSkipForward) {
              if (_hasAnyNext) {
                _goToNextEpisode();
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.mediaSkipBackward) {
              if (_hasPreviousEpisode()) {
                _goToPreviousEpisode();
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.channelUp ||
                key == LogicalKeyboardKey.pageUp) {
              if (_zapRing.canZapIptvChannel) {
                _zapLadder.zapIptvChannel(1);
                return KeyEventResult.handled;
              }
              if (widget.requestNextChannel != null) {
                _goToNextChannel();
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.channelDown ||
                key == LogicalKeyboardKey.pageDown) {
              if (_zapRing.canZapIptvChannel) {
                _zapLadder.zapIptvChannel(-1);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: _controlsVisible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video texture (media_kit renderer)
                if (isReady && !_isTransitioning)
                  _display.getCustomAspectRatio() != null
                      ? _buildCustomAspectRatioVideo()
                      : mkv.Video(
                          key: ValueKey(
                            'video_elevation_${_subtitleSettings?.elevationIndex ?? 0}',
                          ),
                          controller: _videoController,
                          pauseUponEnteringBackgroundMode: !Platform.isIOS,
                          controls: null,
                          fit: _display.currentFit(),
                          subtitleViewConfiguration: _buildSubtitleViewConfig(),
                        )
                else if (_isTransitioning)
                  // Black screen during transitions to hide previous frame
                  Container(color: Colors.black)
                else
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                // Non-startup transitions still use the existing loading UI.
                if (_rainbowActive) _buildTransitionOverlay(),
                if (_showStremioTvNextLoading)
                  _buildStremioTvNextLoadingOverlay(),
                // Double-tap ripple
                if (_ripple != null)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: DoubleTapRipplePainter(_ripple!),
                    ),
                  ),
                // HUDs
                ValueListenableBuilder<SeekHudState?>(
                  valueListenable: _seekHud,
                  builder: (context, hud, _) {
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: hud == null ? 0 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Center(
                          child: hud == null
                              ? const SizedBox.shrink()
                              : SeekHud(hud: hud, format: vpFormatDuration),
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<VerticalHudState?>(
                  valueListenable: _verticalHud,
                  builder: (context, hud, _) {
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: hud == null ? 0 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 24),
                            child: hud == null
                                ? const SizedBox.shrink()
                                : VerticalHud(hud: hud),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<AspectRatioHudState?>(
                  valueListenable: _aspectRatioHud,
                  builder: (context, hud, _) {
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: hud == null ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 80, right: 24),
                            child: hud == null
                                ? const SizedBox.shrink()
                                : AspectRatioHud(hud: hud),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _speedHoldHud,
                  builder: (context, active, _) {
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: active ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fast_forward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '2× Speed',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Subtitle auto-sync countdown pill: quiet bottom-right glass,
                // display-only, outside the subtitle reading zone. TV keeps it
                // inside the overscan safe area.
                ValueListenableBuilder<AutoSyncPillModel?>(
                  valueListenable: _autoSyncPill,
                  builder: (context, model, _) {
                    if (model != null) _autoSyncPillLastShown = model;
                    // Fade out over the LAST shown model — swapping to an
                    // empty box here would make the dismiss fade invisible.
                    final display = model ?? _autoSyncPillLastShown;
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: model == null ? 0 : 1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: AutoSyncPill.cornerInset,
                              bottom: AutoSyncPill.cornerInset,
                            ),
                            child: display == null
                                ? const SizedBox.shrink()
                                : AutoSyncPill(model: display),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // IPTV live reconnect pill (Phase 5 of the resilience plan):
                // only a recovery episode that has run >2s shows it — the
                // invisible fast reconnects stay invisible.
                ValueListenableBuilder<String?>(
                  valueListenable: _iptvReconnectText,
                  builder: (context, text, _) {
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: text != null ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 56),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Text(
                                text ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Buffering indicator (OTT-style centered spinner)
                ValueListenableBuilder<bool>(
                  valueListenable: _showBufferingIndicator,
                  builder: (context, show, _) {
                    // The startup gate has its own spinner and explanatory
                    // status. Keeping the ordinary buffering indicator above
                    // it produces two overlapping loaders while candidates
                    // are being rejected and retried.
                    if (_startupGateActive && !_startupGateOverlayHidden) {
                      return const SizedBox.shrink();
                    }
                    return IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: show ? 1 : 0,
                        duration: show
                            ? const Duration(milliseconds: 250)
                            : const Duration(milliseconds: 200),
                        child: const Center(child: BufferingIndicator()),
                      ),
                    );
                  },
                ),
                // Full-screen gesture layer (placed below controls)
                if (!inPip)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) => _lastTapLocal = d.localPosition,
                    onTap: () {
                      // Disable single tap when both back button and options are hidden
                      if (widget.hideBackButton && widget.hideOptions) {
                        return;
                      }
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final size = box.size;
                      final pos = _lastTapLocal ?? Offset.zero;
                      if (shouldToggleForTap(
                        pos,
                        size,
                        controlsVisible: _controlsVisible.value,
                        bottomBar: _dockBand(72.0),
                      )) {
                        _toggleControls();
                      }
                    },
                    onDoubleTapDown: _handleDoubleTap,
                    onLongPressStart: _display.onLongPressStart,
                    onLongPressEnd: _display.onLongPressEnd,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                  ),
                // Above the gesture layer: startup hides normal controls, but
                // leaving the player must remain available while links resolve.
                if (_startupGateActive && !_startupGateOverlayHidden)
                  Positioned.fill(
                    child: inPip
                        // PiP must not reveal candidates before validation succeeds.
                        // No controls, focus, or gestures in the compact shield.
                        ? const AbsorbPointer(
                            child: ColoredBox(color: Colors.black),
                          )
                        : PlaybackStartupView(
                            title: widget.contentTitle ?? widget.title,
                            episode:
                                widget.contentType == 'series' &&
                                    widget.contentSeason != null &&
                                    widget.contentEpisode != null
                                ? 'Season ${widget.contentSeason} · Episode ${widget.contentEpisode}'
                                : null,
                            details: _startupGateMessage,
                            retrying: _startupGateMessage.startsWith(
                              'Stream unavailable',
                            ),
                            onBack: widget.hideBackButton
                                ? null
                                : () => Navigator.of(context).maybePop(),
                          ),
                  ),
                // Controls overlay (shown only when ready)
                if (isReady &&
                    !inPip &&
                    (!_startupGateActive || _startupGateOverlayHidden))
                  ValueListenableBuilder<bool>(
                    valueListenable: _controlsVisible,
                    builder: (context, visible, _) {
                      return AnimatedOpacity(
                        opacity: visible ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: !visible,
                          // Televisions get their own bar: the touch Controls
                          // has no focus nodes at all, so a remote cannot
                          // reach anything in it. ExcludeFocus keeps a hidden
                          // bar out of traversal — IgnorePointer stops taps
                          // but NOT focus, which would strand the DPAD on
                          // invisible buttons.
                          child: PlatformUtil.isTelevision
                              ? ExcludeFocus(
                                  excluding: !visible,
                                  child: _buildTvControls(),
                                )
                              : Controls(
                                  // Live IPTV leaves the top bar empty on purpose:
                                  // its identity is in the info panel below, and
                                  // repeating the channel in both corners is the
                                  // duplication this redesign set out to remove.
                                  title:
                                      widget.showVideoTitle &&
                                          !widget.showChannelName
                                      ? _getCurrentEpisodeTitle()
                                      : '',
                                  subtitle:
                                      widget.showVideoTitle &&
                                          !widget.showChannelName
                                      ? _getCurrentEpisodeSubtitle()
                                      : null,
                                  // Merged into the dock: the channel panel rides on
                                  // top of the transport bar as one surface.
                                  infoPanel:
                                      _buildIptvInfoPanel(flush: true) ??
                                      _buildDebrifyTvInfoPanel(flush: true),
                                  infoPanelHeight: _reservedInfoPanelHeight,
                                  geometryGeneration: _dockGeometryGeneration,
                                  infoPanelGeneration: _infoPanelGeneration,
                                  onInfoPanelExtent: (h, generation) {
                                    // A report from a previous layout is
                                    // stale by definition — drop it.
                                    if (generation != _infoPanelGeneration) {
                                      return;
                                    }
                                    // Publish increases exactly; only ignore
                                    // sub-pixel shrinkage.
                                    if (h > _infoPanelHeight ||
                                        (_infoPanelHeight - h) >= 1.0) {
                                      setState(() => _infoPanelHeight = h);
                                    }
                                  },
                                  volume: _dockVolume,
                                  onVolumeChanged: (v) {
                                    setState(() => _dockVolume = v);
                                    _player.setVolume(
                                      (v * 100).clamp(0.0, 100.0),
                                    );
                                  },
                                  // windowManager drives fullscreen only on
                                  // Windows/Linux; macOS and mobile leave it
                                  // to the OS, so the button would be a lie.
                                  showFullscreen:
                                      Platform.isWindows || Platform.isLinux,
                                  onFullscreen: () async {
                                    final isFull = await windowManager
                                        .isFullScreen();
                                    if (!mounted) return;
                                    await windowManager.setFullScreen(!isFull);
                                  },
                                  dockStyle: _dockStyle,
                                  dockPalette: _dockPalette,
                                  dockSize: _dockSize,
                                  // Rotation only means something in the hand.
                                  showRotate: PlatformUtil.isPhone,
                                  onDockExtent: (h, generation) {
                                    if (generation != _dockGeometryGeneration) {
                                      return;
                                    }
                                    // Publish every increase exactly; only
                                    // suppress sub-pixel shrinkage.
                                    final prev = _dockExtent.value;
                                    if (h > prev || (prev - h) >= 1.0) {
                                      _dockExtent.value = h;
                                    }
                                  },
                                  enhancedMetadata: _getEnhancedMetadata(),
                                  clock: _playbackUiClock,
                                  isPlaying: _isPlaying,
                                  isReady: isReady,
                                  onPlayPause: _togglePlay,
                                  onBack: () => Navigator.of(context).pop(),
                                  onAspect: _display.onAspectButton,
                                  onSpeed: _display.onSpeedButton,
                                  onSleepTimer: _sleep.showSleepTimerSheet,
                                  sleepTimerLabel: _sleep.sleepTimerButtonLabel,
                                  speed: _display.playbackSpeed,
                                  aspectMode: _display.aspectMode,
                                  isLandscape: _display.landscapeLocked,
                                  onRotate: _display.toggleOrientation,
                                  hasPlaylist:
                                      (_activePlaylist != null &&
                                          _activePlaylist!.isNotEmpty) ||
                                      _canFetchEpisodes,
                                  onShowPlaylist: () =>
                                      _showPlaylistSheet(context),
                                  onShowTracks: () =>
                                      _menuUi.showTracksSheet(context),
                                  onSeekBarChangedStart: () {
                                    _isSeekingWithSlider = true;
                                    // The viewer owns the position from the
                                    // first touch — release the resume guard
                                    // NOW, not at drag end, or the landing
                                    // verifier could re-issue its target and
                                    // yank playback mid-drag.
                                    _stremioTvStartupSeek.cancel();
                                    _resumeWriteGuard.noteUserSeek();
                                  },
                                  onSeekBarChanged: (v) {
                                    final newPos = _duration * v;
                                    _playbackUiClock.updatePosition(
                                      newPos,
                                      immediate: true,
                                    );
                                    _player.seek(newPos);
                                    _lastSliderSeekPos = newPos;
                                  },
                                  onSeekBarChangeEnd: () {
                                    _isSeekingWithSlider = false;
                                    _scheduleAutoHide();
                                    if (_lastSliderSeekPos != null) {
                                      final settledPosition =
                                          _lastSliderSeekPos!;
                                      _trakt.traktScrobbleSeek(settledPosition);
                                      _simkl.simklScrobbleSeek(settledPosition);
                                      _mdblist.mdblistScrobbleSeek(
                                        settledPosition,
                                      );
                                      _lastSliderSeekPos = null;
                                      // A settled seek is a handoff moment:
                                      // persist and let sync flush promptly.
                                      unawaited(
                                        _resumeSave.saveResume(
                                          positionOverride: settledPosition,
                                        ),
                                      );
                                    }
                                  },
                                  // IPTV episode list (series/VOD) gets Next/Previous
                                  // that walk the season; a live channel gets the
                                  // same pair as previous/next channel, which is the
                                  // only way to zap without a CH +/- key. Falls back
                                  // to the Debrify-TV episode/playlist flow.
                                  onNext: _hasIptvNext
                                      ? () => _iptvSwitch.switchToIptvChannel(
                                          _currentIptvIndex + 1,
                                        )
                                      : _zapRing.canZapIptvChannel
                                      ? () => _zapLadder.zapIptvChannel(1)
                                      : (_hasAnyNext ? _goToNextEpisode : null),
                                  onNextChannel:
                                      widget.requestNextChannel != null
                                      ? _goToNextChannel
                                      : null,
                                  onPrevious: _hasIptvPrevious
                                      ? () => _iptvSwitch.switchToIptvChannel(
                                          _currentIptvIndex - 1,
                                        )
                                      : _zapRing.canZapIptvChannel
                                      ? () => _zapLadder.zapIptvChannel(-1)
                                      : (_hasPreviousEpisode()
                                            ? _goToPreviousEpisode
                                            : null),
                                  hasNext:
                                      _hasAnyNext ||
                                      _hasIptvNext ||
                                      _zapRing.canZapIptvChannel,
                                  hasNextChannel:
                                      widget.requestNextChannel != null,
                                  hasGuide:
                                      (_channelEntries.isNotEmpty &&
                                          widget.requestChannelById != null) ||
                                      _hasStremioTvGuide,
                                  onShowGuide:
                                      _channelEntries.isNotEmpty &&
                                          widget.requestChannelById != null
                                      ? _showChannelGuideOverlay
                                      : _hasStremioTvGuide
                                      ? _showStremioTvGuideOverlay
                                      : null,
                                  hasPrevious:
                                      _hasPreviousEpisode() ||
                                      _hasIptvPrevious ||
                                      _zapRing.canZapIptvChannel,
                                  // A live channel has no timeline to scrub: the
                                  // position/duration mpv reports is just the HLS
                                  // rolling window, so the bar counts something
                                  // meaningless and sits under the programme rule,
                                  // which is the progress that actually means
                                  // something here. Derived, not a launch arg, so
                                  // zapping to on-demand brings it straight back.
                                  hideSeekbar:
                                      widget.hideSeekbar ||
                                      (_iptvZapBannerOwnsIdentity &&
                                          !_iptvGuide
                                              .iptvStartOverTimelineVisible),
                                  // Same call the native dock makes for live.
                                  hideSpeed: _iptvZapBannerOwnsIdentity,
                                  // Shuffle picks from _activePlaylist, which an
                                  // IPTV session never has — the button could only
                                  // ever open a menu that does nothing.
                                  hideRandom: _effectiveIptvChannels != null,
                                  hideOptions: widget.hideOptions,
                                  hideBackButton: widget.hideBackButton,
                                  onRandom: () =>
                                      unawaited(_showRandomPlaybackMenu()),
                                  hasIptvChannels:
                                      _effectiveIptvChannels?.isNotEmpty ==
                                      true,
                                  onShowIptvChannels:
                                      _effectiveIptvChannels?.isNotEmpty == true
                                      ? _iptvGuide.showIptvChannelSheetOverlay
                                      : null,
                                  hasStremioSources:
                                      _effectiveSources != null &&
                                      _effectiveSources!.isNotEmpty &&
                                      (_effectiveResolver != null ||
                                          widget.resolveSourceToPlaylist !=
                                              null),
                                  onShowStremioSources:
                                      _effectiveSources != null &&
                                          _effectiveSources!.isNotEmpty &&
                                          (_effectiveResolver != null ||
                                              widget.resolveSourceToPlaylist !=
                                                  null)
                                      ? _showSourceSheetOverlay
                                      : null,
                                  showPipButton: PipService.isOwner(this),
                                  onPip: PipService.isOwner(this)
                                      ? _pip.enterPip
                                      : null,
                                  hasRecord: _recording.canRecord,
                                  isRecording: _recording.recordingActiveNow,
                                  onRecord: _recording.canRecord
                                      ? _recording.toggleRecording
                                      : null,
                                  onLiveEdgeAction:
                                      _iptvGuide.iptvLiveEdgeAction,
                                  liveEdgeActionActive: _iptvStartOverActive,
                                  liveEdgeActionLoading: _iptvStartOverLoading,
                                  onToggleStartOverTimeline:
                                      _iptvStartOverActive
                                      ? _iptvGuide.toggleIptvStartOverTimeline
                                      : null,
                                  startOverTimelineVisible:
                                      _iptvGuide.iptvStartOverTimelineVisible,
                                ),
                        ),
                      );
                    },
                  ),
                // Manual OTT-style skip action. It stays available even when
                // the main controls are hidden, and lifts above the dock when
                // they are visible so neither control intercepts the other.
                if (!inPip)
                  ValueListenableBuilder<SkipSegment?>(
                    valueListenable: _activeSkipSegmentUi,
                    builder: (context, activeSkipSegment, _) {
                      if (activeSkipSegment == null) {
                        return const SizedBox.shrink();
                      }
                      return ValueListenableBuilder<bool>(
                        valueListenable: _controlsVisible,
                        builder: (context, controlsVisible, _) {
                          // Rebuilds when the styled dock's height changes;
                          // otherwise the button would keep a stale position
                          // until some unrelated rebuild happened to occur.
                          return ValueListenableBuilder<double>(
                            valueListenable: _dockExtent,
                            builder: (context, dockExtent, _) {
                              return AnimatedPositioned(
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeOut,
                                right: 24,
                                // Classic keeps the exact legacy ternary. The
                                // styled dock is variable-height, so it uses the
                                // measured band and subtracts this button's OWN
                                // bottom SafeArea inset, which the child re-adds.
                                bottom: _skipButtonBottom(
                                  context,
                                  controlsVisible,
                                  dockExtent,
                                ),
                                child: SafeArea(
                                  top: false,
                                  left: false,
                                  child: SkipSegmentButton(
                                    key: ValueKey(activeSkipSegment.type),
                                    type: activeSkipSegment.type,
                                    onPressed: _skip.skipActiveSegment,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                // Debrify TV lower-third — channel plate + playing title —
                // floating over bare video (the dock embeds its own copy).
                // Replaces the two legacy corner badges.
                if (_debrifyBannerFloatingMounted &&
                    _debrifyTvOwnsIdentity &&
                    !inPip)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        opacity: _showDebrifyBanner ? 1.0 : 0.0,
                        duration: Duration(
                          milliseconds: _showDebrifyBanner ? 200 : 350,
                        ),
                        curve: Curves.easeInOut,
                        // Unmount once faded: this screen rebuilds every
                        // position tick, and a transparent banner would keep
                        // re-laying out for the rest of the session.
                        onEnd: () {
                          if (!mounted || _showDebrifyBanner) return;
                          setState(() => _debrifyBannerFloatingMounted = false);
                        },
                        child:
                            _buildDebrifyTvInfoPanel(flush: false) ??
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                // IPTV zap banner, floating over bare video after a zap. When
                // the dock is open this is absent — the same panel is inside
                // it instead. Ahead of the sheets and the guide in the stack
                // so anything the user opens draws over it.
                if (_iptvZapFloatingMounted && !inPip)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _showIptvZapBanner ? 1.0 : 0.0,
                      duration: Duration(
                        milliseconds: _showIptvZapBanner ? 160 : 180,
                      ),
                      curve: Curves.easeInOut,
                      // Drop the subtree once it has faded out. This screen
                      // rebuilds on every position tick, so leaving a
                      // fully-transparent banner mounted would re-lay it out
                      // for the rest of the session. Only the presentation
                      // goes — the channel/EPG data stays for the dock.
                      onEnd: () {
                        if (!mounted || _showIptvZapBanner) return;
                        setState(() => _iptvZapFloatingMounted = false);
                      },
                      child:
                          _buildIptvInfoPanel(flush: false) ??
                          const SizedBox.shrink(),
                    ),
                  ),
                // PikPak retry overlay - non-blocking, positioned at bottom right
                if (_isPikPakRetrying && _pikPakRetryMessage != null && !inPip)
                  ValueListenableBuilder<double>(
                    valueListenable: _dockExtent,
                    builder: (context, dockExtent, _) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: _controlsVisible,
                          builder: (context, controlsVisible, _) {
                            // Only lifts while the dock is actually on screen:
                            // Controls stays mounted under AnimatedOpacity when
                            // hidden, so the extent alone is not enough.
                            final dockVisible =
                                _dockStyle.isStyled &&
                                controlsVisible &&
                                (_buildIptvInfoPanel(flush: true) != null ||
                                    _buildDebrifyTvInfoPanel(flush: true) !=
                                        null ||
                                    !widget.hideOptions);
                            return PikPakRetryOverlay(
                              message: _pikPakRetryMessage!,
                              bottom: dockVisible
                                  ? math.max(80.0, dockExtent + 12)
                                  : 80.0,
                            );
                          },
                        ),
                  ),
                // Channel guide overlay
                if (_showChannelGuide && _channelEntries.isNotEmpty && !inPip)
                  Positioned.fill(
                    child: ChannelGuide(
                      channels: _channelEntries,
                      currentChannelId: _currentChannelId,
                      currentChannelNumber: _currentChannelNumber,
                      onChannelSelected: _goToChannelById,
                      onClose: _hideChannelGuideOverlay,
                    ),
                  ),
                // IPTV channel sheet overlay
                if (_showIptvChannelSheet &&
                    _effectiveIptvChannels?.isNotEmpty == true &&
                    !inPip)
                  Positioned.fill(
                    child: IptvChannelSheet(
                      key: _iptvSheetKey,
                      channels: _effectiveIptvChannels!,
                      currentIndex: _currentIptvIndex,
                      onChannelSelected: _iptvGuide.switchToIptvGuideChannel,
                      onPlayProgramme: _iptvGuide.playIptvCatchup,
                      onClose: _iptvGuide.hideIptvChannelSheet,
                      categories:
                          _iptvGuideContextOverride?.categories ??
                          widget.iptvCategories ??
                          const [],
                      sourceId: _iptvGuideContextOverride == null
                          ? widget.iptvSourceId
                          : _iptvGuideContextOverride!.sourceId,
                      sourceName: _iptvGuideContextOverride == null
                          ? widget.iptvSourceName
                          : _iptvGuideContextOverride!.sourceName,
                      selectedCategory: _iptvGuideContextOverride == null
                          ? widget.iptvSelectedCategory
                          : _iptvGuideContextOverride!.selectedCategory,
                      contentType:
                          _iptvGuideContextOverride?.contentType ??
                          widget.iptvContentType ??
                          'live',
                      sources: widget.iptvSources ?? const [],
                      browseProvider: widget.iptvBrowseProvider,
                      onContextChanged: _iptvGuide.persistIptvGuideContext,
                      style: _playerGuideStyle,
                      tokens: _playerGuideTokens,
                    ),
                  ),
                // Stremio source sheet overlay
                if (_showSourceSheet &&
                    _effectiveSources != null &&
                    _effectiveSources!.isNotEmpty &&
                    (_effectiveResolver != null ||
                        widget.resolveSourceToPlaylist != null) &&
                    !inPip)
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        // A Stremio TV channel switch replaces the sources
                        // wholesale — the launch fetcher no longer matches the
                        // content, so load-more is only offered pre-switch.
                        final fetcher = _stremioSourcesOverride == null
                            ? widget.seriesSourceFetcher
                            : null;
                        final se = _traktSeasonEpisode();
                        return SourceSheet(
                          sources: _effectiveSources!,
                          currentSourceIndex: _currentSourceIndex,
                          resolveSource: _buildSourceSheetResolver(),
                          onSourceSelected: _handleSourceSelected,
                          onClose: _hideSourceSheet,
                          seriesFetcher: fetcher,
                          currentSeason: se.season,
                          currentEpisode: se.episode,
                          onSourcesMerged: (merged) {
                            if (!mounted) return;
                            setState(() => _augmentedSources = merged);
                          },
                        );
                      },
                    ),
                  ),
                // Stremio TV guide sheet overlay
                if (_showStremioTvGuide && _hasStremioTvGuide && !inPip)
                  Positioned.fill(
                    child: StremioTvGuideSheet(
                      channels: _effectiveStremioTvChannels!,
                      currentChannelId: _currentStremioTvChannelId,
                      guideDataProvider: widget.stremioTvGuideDataProvider,
                      channelSwitchProvider:
                          widget.stremioTvChannelSwitchProvider!,
                      onChannelSwitched: _switchToStremioTvChannel,
                      onClose: _hideStremioTvGuide,
                    ),
                  ),
                // Unified player menu (Spotlight panel)
                if (_showPlayerMenu && !inPip)
                  Positioned.fill(child: _menuUi.buildPlayerMenuPanel()),
                // Subtitle sync overlay
                if (_showSyncOverlay && !inPip)
                  _subtitleSync.buildSyncOverlay(),
              ],
            ),
            builder: (context, controlsVisible, child) {
              // Hide the desktop mouse pointer once controls fade out; any
              // mouse movement wakes both the cursor and the controls.
              // Keep the cursor visible whenever an overlay/sheet is open —
              // those set _controlsVisible=false but still need the pointer.
              final hideCursor = !controlsVisible && !_isAnyOverlayOpen;
              return MouseRegion(
                cursor: hideCursor
                    ? SystemMouseCursors.none
                    : MouseCursor.defer,
                onHover: (_) => _wakeControlsOnPointer(),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  /// True while any overlay/sheet is open on top of the player. These set
  /// _controlsVisible=false but must keep the mouse pointer visible.
  bool get _isAnyOverlayOpen =>
      _showSyncOverlay ||
      _showChannelGuide ||
      _showIptvChannelSheet ||
      _showSourceSheet ||
      _showStremioTvGuide ||
      _showPlayerMenu;

  /// Called on mouse movement: reveal controls (and the cursor) if hidden and
  /// (re)start the auto-hide countdown so continuous movement keeps them alive.
  void _wakeControlsOnPointer() {
    // Don't disturb the base controls while an overlay owns the screen; the
    // cursor is already kept visible by _isAnyOverlayOpen in the builder.
    if (_isAnyOverlayOpen) return;
    if (!_controlsVisible.value) {
      _controlsVisible.value = true;
    }
    _scheduleAutoHide();
  }

  /// Reset subtitle-related state when switching content.
  void _resetSubtitleState() {
    _cachedStremioSubtitles = null;
    _cachedAddonSlots = null;
    _cachedSubtitleKey = null;
    _selectedStremioSubtitleId = null;
    _manualContentImdbId = null;
    _manualContentType = null;
    _manualContentSeason = null;
    _manualContentEpisode = null;
    _manualSubtitleDisplayLabel = null;
    _embeddedSubtitleApplied = false;
    _subtitleSelectedAudio = null;
    _subtitleAudioRevision++;
    _userManuallySelectedSubtitle = false;
    _trackPreferencesReadyForAddonSubtitles = false;
    _addonSubtitleFetchToken++;
    _subtitleDiagnosticGeneration++;
    _activeSubtitleApplyAttempt = null;
    _addonSubtitles.cleanupTempSubtitleFilesSync();
    _subtitleSync.setActiveExternalSubtitlePath(null);
    _showSyncOverlay = false;
    // The menu's subtitle pane is keyed to the outgoing item's identity.
    _showPlayerMenu = false;
    // Content changed: the previous item's sync offset no longer applies.
    _subtitleSync.resetSubtitleSyncOffset();
  }

  SeriesEpisode? _findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  ) {
    for (final episode in seriesPlaylist.allEpisodes) {
      if (episode.originalIndex == _currentIndex) {
        return episode;
      }
    }
    if (_currentIndex >= 0 &&
        _currentIndex < seriesPlaylist.allEpisodes.length) {
      return seriesPlaylist.allEpisodes[_currentIndex];
    }
    return null;
  }
}

class _VpIptvZapBannerHostAdapter implements VpIptvZapBannerHost {
  _VpIptvZapBannerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  bool get iptvZapBannerOwnsIdentity => _s._iptvZapBannerOwnsIdentity;
  @override
  IptvChannel? get iptvZapChannel => _s._iptvZapChannel;
  @override
  set iptvZapChannel(IptvChannel? v) => _s._iptvZapChannel = v;
  @override
  set iptvZapClock(DateTime v) => _s._iptvZapClock = v;
  @override
  EpgNowNext? get iptvZapEpg => _s._iptvZapEpg;
  @override
  set iptvZapEpg(EpgNowNext? v) => _s._iptvZapEpg = v;
  @override
  bool get iptvZapEpgLoading => _s._iptvZapEpgLoading;
  @override
  set iptvZapEpgLoading(bool v) => _s._iptvZapEpgLoading = v;
  @override
  bool get iptvZapFloatingMounted => _s._iptvZapFloatingMounted;
  @override
  set iptvZapFloatingMounted(bool v) => _s._iptvZapFloatingMounted = v;
  @override
  bool get showChannelGuide => _s._showChannelGuide;
  @override
  bool get showIptvChannelSheet => _s._showIptvChannelSheet;
  @override
  bool get showIptvZapBanner => _s._showIptvZapBanner;
  @override
  set showIptvZapBanner(bool v) => _s._showIptvZapBanner = v;
  @override
  bool get showSourceSheet => _s._showSourceSheet;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
}

class _VpIptvWatchMemoryHostAdapter implements VpIptvWatchMemoryHost {
  _VpIptvWatchMemoryHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  IptvGuideContext? get iptvGuideContextOverride =>
      _s._iptvGuideContextOverride;
  @override
  int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override
  bool get isIptvSeriesContext => _s._isIptvSeriesContext;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  mk.Player get player => _s._player;
  @override
  bool get mounted => _s.mounted;
  @override
  String? get iptvSourceId => _s.widget.iptvSourceId;
}

class _VpIptvLiveSourcesHostAdapter implements VpIptvLiveSourcesHost {
  _VpIptvLiveSourcesHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  String? get iptvChannelKey => _s._iptvChannelKey;
  @override
  set iptvChannelKey(String? v) => _s._iptvChannelKey = v;
  @override
  IptvTuneDiagnostics get iptvDiag => _s._iptvDiag;
  @override
  bool get iptvErrorsMuted => _s._iptvErrorsMuted;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  bool iptvRecoveryEligible() => _s._iptvSwitch.iptvRecoveryEligible();
  @override
  bool get iptvStartOverActive => _s._iptvStartOverActive;
  @override
  set iptvStartOverActive(bool v) => _s._iptvStartOverActive = v;
  @override
  set iptvStartOverTimelineRequested(bool v) =>
      _s._iptvStartOverTimelineRequested = v;
  @override
  DateTime? get lastIptvErrorShown => _s._lastIptvErrorShown;
  @override
  set lastIptvErrorShown(DateTime? v) => _s._lastIptvErrorShown = v;
  @override
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  }) => _s._openMedia(
    media,
    play: play,
    desiredPlay: desiredPlay,
    liveStream: liveStream,
    request: request,
    beforeOpen: beforeOpen,
    source: source,
    preserveStartupEpoch: preserveStartupEpoch,
  );
  @override
  mk.Player get player => _s._player;
  @override
  Future<String?> Function(Torrent)? get resolveStremioSourceOverride =>
      _s._resolveStremioSourceOverride;
  @override
  set resolveStremioSourceOverride(Future<String?> Function(Torrent)? v) =>
      _s._resolveStremioSourceOverride = v;
  @override
  Future<void> stopRecording({bool userInitiated = true}) =>
      _s._recording.stopRecording(userInitiated: userInitiated);
  @override
  List<Torrent>? get stremioSourcesOverride => _s._stremioSourcesOverride;
  @override
  set stremioSourcesOverride(List<Torrent>? v) =>
      _s._stremioSourcesOverride = v;
  @override
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false}) =>
      _s._iptvSwitch.switchToIptvChannel(index, quietRecovery: quietRecovery);
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  int? get iptvStartIndex => _s.widget.iptvStartIndex;
  @override
  String get videoUrl => _s.widget.videoUrl;
}

class _VpIptvChannelSwitchHostAdapter implements VpIptvChannelSwitchHost {
  _VpIptvChannelSwitchHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get activeMediaUserPaused => _s._activeMediaUserPaused;
  @override
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories}) =>
      _s._iptvGuide.anchorIptvGuideCategory(channel, categories: categories);
  @override
  Future<void> applyIptvAudioPreference(int ticket) =>
      _s._iptvMemory.applyIptvAudioPreference(ticket);
  @override
  void cancelPendingIptvCatchup({bool hideFeedback = true}) =>
      _s._iptvGuide.cancelPendingIptvCatchup(hideFeedback: hideFeedback);
  @override
  void clearBufferingIndicator() => _s._clearBufferingIndicator();
  @override
  set currentChannelName(String? v) => _s._currentChannelName = v;
  @override
  set currentChannelNumber(int? v) => _s._currentChannelNumber = v;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  set currentIptvIndex(int v) => _s._currentIptvIndex = v;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  bool get engineFlagOn => _s._engineFlagOn;
  @override
  void hideIptvChannelSheet() => _s._iptvGuide.hideIptvChannelSheet();
  @override
  void hideIptvZapBanner({bool immediate = false}) =>
      _s._iptvBanner.hideIptvZapBanner(immediate: immediate);
  @override
  void hideSourceSheet() => _s._hideSourceSheet();
  @override
  String? get iptvChannelKey => _s._iptvChannelKey;
  @override
  IptvTuneDiagnostics get iptvDiag => _s._iptvDiag;
  @override
  set iptvErrorsMuted(bool v) => _s._iptvErrorsMuted = v;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  ValueNotifier<String?> get iptvReconnectText => _s._iptvReconnectText;
  @override
  bool get iptvStartOverActive => _s._iptvStartOverActive;
  @override
  set iptvStartOverActive(bool v) => _s._iptvStartOverActive = v;
  @override
  bool get iptvStartOverLoading => _s._iptvStartOverLoading;
  @override
  set iptvStartOverLoading(bool v) => _s._iptvStartOverLoading = v;
  @override
  set iptvStartOverTimelineRequested(bool v) =>
      _s._iptvStartOverTimelineRequested = v;
  @override
  int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override
  set iptvSwitchTicket(int v) => _s._iptvSwitchTicket = v;
  @override
  bool get iptvZapPagingActive => _s._iptvZapPagingActive;
  @override
  bool get isIptvSeriesContext => _s._isIptvSeriesContext;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  set lastIptvErrorShown(DateTime? v) => _s._lastIptvErrorShown = v;
  @override
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  }) => _s._openMedia(
    media,
    play: play,
    desiredPlay: desiredPlay,
    liveStream: liveStream,
    request: request,
    beforeOpen: beforeOpen,
    source: source,
    preserveStartupEpoch: preserveStartupEpoch,
  );
  @override
  bool get pausedByLifecycle => _s._pausedByLifecycle;
  @override
  mk.Player get player => _s._player;
  @override
  void prepareIptvBannerData(IptvChannel channel) =>
      _s._iptvBanner.prepareIptvBannerData(channel);
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  void raiseIptvZapBanner() => _s._iptvBanner.raiseIptvZapBanner();
  @override
  Future<void> recordIptvWatchForChannel(IptvChannel channel) =>
      _s._iptvMemory.recordIptvWatchForChannel(channel);
  @override
  Future<void> refreshEngineRecordingState() =>
      _s._recording.refreshEngineRecordingState();
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  void setIptvSources(
    String? channelKey,
    List<StremioIptvCandidate>? candidates, {
    int currentIndex = 0,
  }) => _s._iptvSources.setIptvSources(
    channelKey,
    candidates,
    currentIndex: currentIndex,
  );
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  void startTransitionOverlay() => _s._startTransitionOverlay();
  @override
  Future<void> stopRecording({bool userInitiated = true}) =>
      _s._recording.stopRecording(userInitiated: userInitiated);
  @override
  set transitionPhase(int v) => _s._transitionPhase = v;
  @override
  set transitionPhase2Started(DateTime? v) => _s._transitionPhase2Started = v;
  @override
  Timer? get transitionPhaseTimer => _s._transitionPhaseTimer;
  @override
  set transitionRunning(bool v) => _s._transitionRunning = v;
  @override
  Timer? get transitionStopTimer => _s._transitionStopTimer;
  @override
  set transitionStopTimer(Timer? v) => _s._transitionStopTimer = v;
  @override
  Future<bool> tryOpenLiveStream(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
  }) => _s._iptvSources.tryOpenLiveStream(
    url,
    timeout: timeout,
    httpHeaders: httpHeaders,
  );
  @override
  void tvAbandonScrub() => _s._tvAbandonScrub();
  @override
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  SleepTimerMode get sleepTimerMode => _s._sleep.sleepTimerMode;
}

class _VpIptvGuideCatchupHostAdapter implements VpIptvGuideCatchupHost {
  _VpIptvGuideCatchupHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  Duration get duration => _s._duration;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  void hideIptvZapBanner({bool immediate = false}) =>
      _s._iptvBanner.hideIptvZapBanner(immediate: immediate);
  @override
  set iptvChannelsOverride(List<IptvChannel>? v) =>
      _s._iptvChannelsOverride = v;
  @override
  IptvTuneDiagnostics get iptvDiag => _s._iptvDiag;
  @override
  int get iptvGuideContextGeneration => _s._iptvGuideContextGeneration;
  @override
  set iptvGuideContextGeneration(int v) => _s._iptvGuideContextGeneration = v;
  @override
  IptvGuideContext? get iptvGuideContextOverride =>
      _s._iptvGuideContextOverride;
  @override
  set iptvGuideContextOverride(IptvGuideContext? v) =>
      _s._iptvGuideContextOverride = v;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  bool iptvRecoveryEligible() => _s._iptvSwitch.iptvRecoveryEligible();
  @override
  bool get iptvStartOverActive => _s._iptvStartOverActive;
  @override
  set iptvStartOverActive(bool v) => _s._iptvStartOverActive = v;
  @override
  bool get iptvStartOverLoading => _s._iptvStartOverLoading;
  @override
  set iptvStartOverLoading(bool v) => _s._iptvStartOverLoading = v;
  @override
  bool get iptvStartOverTimelineRequested => _s._iptvStartOverTimelineRequested;
  @override
  set iptvStartOverTimelineRequested(bool v) =>
      _s._iptvStartOverTimelineRequested = v;
  @override
  int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override
  EpgNowNext? get iptvZapEpg => _s._iptvZapEpg;
  @override
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  }) => _s._openMedia(
    media,
    play: play,
    desiredPlay: desiredPlay,
    liveStream: liveStream,
    request: request,
    beforeOpen: beforeOpen,
    source: source,
    preserveStartupEpoch: preserveStartupEpoch,
  );
  @override
  Future<void> reanchorIptvRingToCategory(
    IptvChannel channel, {
    required int switchTicket,
  }) => _s._zapRing.reanchorIptvRingToCategory(
    channel,
    switchTicket: switchTicket,
  );
  @override
  void resetIptvZapPaging() => _s._zapRing.resetIptvZapPaging();
  @override
  void scheduleAutoHide() => _s._scheduleAutoHide();
  @override
  set showIptvChannelSheet(bool v) => _s._showIptvChannelSheet = v;
  @override
  Future<void> stopRecording({bool userInitiated = true}) =>
      _s._recording.stopRecording(userInitiated: userInitiated);
  @override
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false}) =>
      _s._iptvSwitch.switchToIptvChannel(index, quietRecovery: quietRecovery);
  @override
  FocusNode get tvProgressFocus => _s._tvProgressFocus;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  String? get iptvSourceId => _s.widget.iptvSourceId;
  @override
  List<String>? get iptvCategories => _s.widget.iptvCategories;
  @override
  String? get iptvContentType => _s.widget.iptvContentType;
  @override
  String? get iptvSourceName => _s.widget.iptvSourceName;
}

class _VpIptvZapLadderHostAdapter implements VpIptvZapLadderHost {
  _VpIptvZapLadderHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  void applyIptvGuideCategory(String? category, List<String>? categories) =>
      _s._iptvGuide.applyIptvGuideCategory(category, categories);
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  void ensureIptvZapPagingArmed() => _s._zapRing.ensureIptvZapPagingArmed();
  @override
  void installIptvZapWindow(
    VpIptvZapPage page, {
    required bool preservePlayingChannel,
  }) => _s._zapRing.installIptvZapWindow(
    page,
    preservePlayingChannel: preservePlayingChannel,
  );
  @override
  List<String> get iptvZapCategories => _s._iptvZapCategories;
  @override
  String? get iptvZapCategory => _s._iptvZapCategory;
  @override
  int get iptvZapCategoryTotal => _s._iptvZapCategoryTotal;
  @override
  bool get iptvZapPagingActive => _s._iptvZapPagingActive;
  @override
  List<int> get iptvZapPendingInputs => _s._iptvZapPendingInputs;
  @override
  bool get iptvZapRequestInFlight => _s._iptvZapRequestInFlight;
  @override
  int get iptvZapWindowOffset => _s._iptvZapWindowOffset;
  @override
  int get iptvZapPageSize => _VideoPlayerScreenState._kIptvZapPageSize;
  @override
  void mergeIptvZapPage(VpIptvZapPage page) =>
      _s._zapRing.mergeIptvZapPage(page);
  @override
  Future<VpIptvZapPage?> requestIptvZapPage({
    required String? category,
    required int offset,
    bool fromEnd = false,
  }) => _s._zapRing.requestIptvZapPage(
    category: category,
    offset: offset,
    fromEnd: fromEnd,
  );
  @override
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false}) =>
      _s._iptvSwitch.switchToIptvChannel(index, quietRecovery: quietRecovery);
  @override
  bool get mounted => _s.mounted;
}

class _VpIptvZapRingHostAdapter implements VpIptvZapRingHost {
  _VpIptvZapRingHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories}) =>
      _s._iptvGuide.anchorIptvGuideCategory(channel, categories: categories);
  @override
  void clearIptvZapBoundaryCache() => _s._zapLadder.clearIptvZapBoundaryCache();
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  set currentIptvIndex(int v) => _s._currentIptvIndex = v;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  set iptvChannelsOverride(List<IptvChannel>? v) =>
      _s._iptvChannelsOverride = v;
  @override
  int get iptvGuideContextGeneration => _s._iptvGuideContextGeneration;
  @override
  IptvGuideContext? get iptvGuideContextOverride =>
      _s._iptvGuideContextOverride;
  @override
  int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override
  set iptvZapCategories(List<String> v) => _s._iptvZapCategories = v;
  @override
  String? get iptvZapCategory => _s._iptvZapCategory;
  @override
  set iptvZapCategory(String? v) => _s._iptvZapCategory = v;
  @override
  set iptvZapCategoryTotal(int v) => _s._iptvZapCategoryTotal = v;
  @override
  bool get iptvZapPagingActive => _s._iptvZapPagingActive;
  @override
  set iptvZapPagingActive(bool v) => _s._iptvZapPagingActive = v;
  @override
  List<int> get iptvZapPendingInputs => _s._iptvZapPendingInputs;
  @override
  bool get iptvZapRequestInFlight => _s._iptvZapRequestInFlight;
  @override
  set iptvZapRequestInFlight(bool v) => _s._iptvZapRequestInFlight = v;
  @override
  int get iptvZapWindowOffset => _s._iptvZapWindowOffset;
  @override
  set iptvZapWindowOffset(int v) => _s._iptvZapWindowOffset = v;
  @override
  int get iptvZapPageSize => _VideoPlayerScreenState._kIptvZapPageSize;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider => _s.widget.iptvBrowseProvider;
  @override
  String? get iptvSourceId => _s.widget.iptvSourceId;
}

class _VpResumeSaveHostAdapter implements VpResumeSaveHost {
  _VpResumeSaveHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  String? get currentStreamUrl => _s._currentStreamUrl;
  @override
  String? get currentStremioTvContentTitle => _s._currentStremioTvContentTitle;
  @override
  Duration get duration => _s._duration;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  String? get effectiveContentTitle => _s._effectiveContentTitle;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  IptvGuideContext? get iptvGuideContextOverride =>
      _s._iptvGuideContextOverride;
  @override
  bool get isManualEpisodeSelection => _s._isManualEpisodeSelection;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  bool get isReady => _s._isReady;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  Duration get position => _s._position;
  @override
  Lock get resumeSaveLock => _s._resumeSaveLock;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  MediaServerWatchController get serverWatch => _s._serverWatch;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  String resumeIdForEntry(PlaylistEntry entry) =>
      _s._resumeKeys.resumeIdForEntry(entry);
  @override
  String get resumeKey => _s._resumeKeys.resumeKey;
  @override
  String get title => _s.widget.title;
  @override
  String get videoUrl => _s.widget.videoUrl;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  String? get iptvSourceId => _s.widget.iptvSourceId;
  @override
  PlaybackResumePolicy get resumePolicy => _s.widget.resumePolicy;
  @override
  String? get currentLocalMovieImdbId => _s._completion.currentLocalMovieImdbId;
  @override
  bool get currentMovieMarkedAsFinished =>
      _s._completion.currentMovieMarkedAsFinished;
  @override
  double get playbackSpeed => _s._display.playbackSpeed;
  @override
  AspectMode get aspectMode => _s._display.aspectMode;
  @override
  double? get speedBeforeHold => _s._display.speedBeforeHold;
}

class _VpResumeRestoreHostAdapter implements VpResumeRestoreHost {
  _VpResumeRestoreHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get allowResumeForManualSelection => _s._allowResumeForManualSelection;
  @override
  Duration get duration => _s._duration;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  bool get isAutoAdvancing => _s._isAutoAdvancing;
  @override
  set isAutoAdvancing(bool v) => _s._isAutoAdvancing = v;
  @override
  bool get isManualEpisodeSelection => _s._isManualEpisodeSelection;
  @override
  mk.Player get player => _s._player;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  Future<void> waitForDuration() => _s._waitForDuration();
  @override
  Future<Map<String, dynamic>?> getEnhancedPlaybackState() =>
      _s._resumeSave.getEnhancedPlaybackState();
  @override
  String get resumeKey => _s._resumeKeys.resumeKey;
  @override
  bool get mounted => _s.mounted;
  @override
  double? get traktProgressPercent => _s.widget.traktProgressPercent;
  @override
  double? get mdblistProgressPercent => _s.widget.mdblistProgressPercent;
  @override
  double? get simklProgressPercent => _s.widget.simklProgressPercent;
  @override
  bool get launchTraktPercentSpent => _s._trakt.launchTraktPercentSpent;
  @override
  set launchTraktPercentSpent(bool v) => _s._trakt.launchTraktPercentSpent = v;
  @override
  bool get launchSimklPercentSpent => _s._simkl.launchSimklPercentSpent;
  @override
  set launchSimklPercentSpent(bool v) => _s._simkl.launchSimklPercentSpent = v;
  @override
  bool get launchMdblistPercentSpent => _s._mdblist.launchMdblistPercentSpent;
  @override
  set launchMdblistPercentSpent(bool v) =>
      _s._mdblist.launchMdblistPercentSpent = v;
  @override
  String? get currentLocalMovieImdbId => _s._completion.currentLocalMovieImdbId;
  @override
  set playbackSpeed(double v) => _s._display.playbackSpeed = v;
  @override
  set aspectMode(AspectMode v) => _s._display.aspectMode = v;
  @override
  Future<double?> currentEpisodeTraktPercent({bool forGuide = false}) =>
      _s._trakt.currentEpisodeTraktPercent(forGuide: forGuide);
  @override
  Future<double?> currentEpisodeSimklPercent({bool forGuide = false}) =>
      _s._simkl.currentEpisodeSimklPercent(forGuide: forGuide);
  @override
  Future<double?> currentEpisodeMdblistPercent({bool forGuide = false}) =>
      _s._mdblist.currentEpisodeMdblistPercent(forGuide: forGuide);
  @override
  Future<void> applyAspectVideoZoom() => _s._display.applyAspectVideoZoom();
  @override
  Future<Map<String, dynamic>?> readLocalResume({
    required String? contentId,
    required String resumeKey,
    required Future<Map<String, dynamic>?> Function() enhanced,
  }) => VideoPlayerScreen.readLocalResume(
    contentId: contentId,
    resumeKey: resumeKey,
    enhanced: enhanced,
  );
}

class _VpResumeKeysHostAdapter implements VpResumeKeysHost {
  _VpResumeKeysHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  String get title => _s.widget.title;
  @override
  String get videoUrl => _s.widget.videoUrl;
}

class _VpIptvRecordingResourcesHostAdapter
    implements VpIptvRecordingResourcesHost {
  _VpIptvRecordingResourcesHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  String? get currentStreamUrl => _s._currentStreamUrl;
  @override
  mk.Player get player => _s._player;
  @override
  StreamSubscription<mk.PlayerLog>? get recordLogSub => _s._recordLogSub;
  @override
  set recordLogSub(StreamSubscription<mk.PlayerLog>? v) => _s._recordLogSub = v;
  @override
  String? get iptvSourceId => _s.widget.iptvSourceId;
  @override
  List<Map<String, dynamic>>? get iptvSources => _s.widget.iptvSources;
}

class _VpIptvRecordingHostAdapter implements VpIptvRecordingHost {
  _VpIptvRecordingHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  BuildContext get context => _s.context;
  @override
  bool get mounted => _s.mounted;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  Future<({String id, int revision})?> currentRecordingResource() =>
      _s._recordingResources.currentRecordingResource();
  @override
  DesktopRecordingCapture? desktopCaptureForCurrent() =>
      _s._recordingResources.desktopCaptureForCurrent();
  @override
  bool get engineFlagOn => _s._engineFlagOn;
  @override
  Future<String?> engineRecordUrlForCurrent() =>
      _s._recordingResources.engineRecordUrlForCurrent();
  @override
  String? get engineTaskId => _s._engineTaskId;
  @override
  set engineTaskId(String? v) => _s._engineTaskId = v;
  @override
  bool get iptvZapBannerOwnsIdentity => _s._iptvZapBannerOwnsIdentity;
  @override
  bool get isRecording => _s._isRecording;
  @override
  set isRecording(bool v) => _s._isRecording = v;
  @override
  mk.Player get player => _s._player;
  @override
  bool get playerCreated => _s._playerCreated;
  @override
  String? playingLiveUrl(IptvChannel channel) =>
      _s._recordingResources.playingLiveUrl(channel);
  @override
  String recordingFileName(String channelName) =>
      _s._recordingResources.recordingFileName(channelName);
  @override
  int get recordingStartGen => _s._recordingStartGen;
  @override
  set recordingStartGen(int v) => _s._recordingStartGen = v;
  @override
  bool get recordingSupported => _s._recordingSupported;
  @override
  Future<String> recordingTargetPath(
    String channelName, {
    String extension = 'mkv',
  }) => _s._recordingResources.recordingTargetPath(
    channelName,
    extension: extension,
  );
  @override
  String? get recordingTempPath => _s._recordingTempPath;
  @override
  set recordingTempPath(String? v) => _s._recordingTempPath = v;
  @override
  void tapMpvLogsForRecording() =>
      _s._recordingResources.tapMpvLogsForRecording();
  @override
  void untapMpvLogs() => _s._recordingResources.untapMpvLogs();
  @override
  bool get isIOS => VpS2Hooks.isIOS;
}

class _VpPlayerMenuHostAdapter implements VpPlayerMenuHost {
  _VpPlayerMenuHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get mounted => _s.mounted;
  @override
  int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override
  List<AddonSubtitleSlot>? get cachedAddonSlots => _s._cachedAddonSlots;
  @override
  String? get cachedSubtitleKey => _s._cachedSubtitleKey;
  @override
  void captureIptvAudioLanguage(String audioId) =>
      _s._iptvMemory.captureIptvAudioLanguage(audioId);
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  bool get hasSubtitlePolicy => _s._hasSubtitlePolicy;
  @override
  void hideIptvZapBanner({bool immediate = false}) =>
      _s._iptvBanner.hideIptvZapBanner(immediate: immediate);
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  List<AddonSubtitleSlot>? get injectedSubtitleSlots =>
      _s._injectedSubtitleSlots;
  @override
  int? get manualContentEpisode => _s._manualContentEpisode;
  @override
  String? get manualContentImdbId => _s._manualContentImdbId;
  @override
  int? get manualContentSeason => _s._manualContentSeason;
  @override
  String? get manualContentType => _s._manualContentType;
  @override
  set menuCacheKey(String? v) => _s._menuCacheKey = v;
  @override
  set menuCachedSlots(List<AddonSubtitleSlot>? v) => _s._menuCachedSlots = v;
  @override
  set menuContentType(String? v) => _s._menuContentType = v;
  @override
  set menuEpisode(int? v) => _s._menuEpisode = v;
  @override
  set menuImdbId(String? v) => _s._menuImdbId = v;
  @override
  set menuSeason(int? v) => _s._menuSeason = v;
  @override
  mk.Player get player => _s._player;
  @override
  set playerMenuInitialSection(PlayerMenuSection v) =>
      _s._playerMenuInitialSection = v;
  @override
  set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  bool get showPlayerMenu => _s._showPlayerMenu;
  @override
  set showPlayerMenu(bool v) => _s._showPlayerMenu = v;
  @override
  String? get singleFileImdbId => _s._singleFileImdbId;
  @override
  int get subtitleAudioRevision => _s._subtitleAudioRevision;
  @override
  set subtitleAudioRevision(int v) => _s._subtitleAudioRevision = v;
  @override
  void tvReleaseFocusForOverlay() => _s._tvReleaseFocusForOverlay();
  @override
  FocusNode get tvRootFocus => _s._tvRootFocus;
  @override
  bool get userManuallySelectedSubtitle => _s._userManuallySelectedSubtitle;
  @override
  set userManuallySelectedSubtitle(bool v) =>
      _s._userManuallySelectedSubtitle = v;
  @override
  String currentPlaybackTitleForIdentity() =>
      _s._identify.currentPlaybackTitleForIdentity();
  @override
  void setActiveExternalSubtitlePath(String? path) =>
      _s._subtitleSync.setActiveExternalSubtitlePath(path);
  @override
  Future<void> persistTrackChoice(String audioId, String subtitleId) =>
      _s._trackPreferences.persistTrackChoice(audioId, subtitleId);
  @override
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  }) => _s._subtitleApply.setSubtitleTrackWithDiagnostics(
    track,
    source: source,
    isCurrent: isCurrent,
  );
  @override
  void showSubtitleFailureMessage(String message) =>
      _s._subtitleApply.showSubtitleFailureMessage(message);
  @override
  Future<void> refreshSubtitleAudioPolicy({bool reselect = true}) =>
      _s._subtitleLanguage.refreshSubtitleAudioPolicy(reselect: reselect);
  @override
  Future<String?> downloadStremioSubtitleToTempFile(StremioSubtitle sub) =>
      _s._addonSubtitles.downloadStremioSubtitleToTempFile(sub);
  @override
  Future<bool> applyExternalSubtitleTrack(mk.SubtitleTrack track) =>
      _s._addonSubtitles.applyExternalSubtitleTrack(track);
}

class _VpPlayerMenuUiHostAdapter implements VpPlayerMenuUiHost {
  _VpPlayerMenuUiHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  Future<bool> applyStremioSubtitleFromTracksSheet(StremioSubtitle sub) =>
      _s._menu.applyStremioSubtitleFromTracksSheet(sub);
  @override
  bool get audioPassthroughEnabled => _s._audioPassthroughEnabled;
  @override
  Future<void> audioTrackChoiceChanged(String audioId, String currentSubId) =>
      _s._menu.audioTrackChoiceChanged(audioId, currentSubId);
  @override
  List<AddonSubtitleSlot>? get cachedAddonSlots => _s._cachedAddonSlots;
  @override
  set cachedAddonSlots(List<AddonSubtitleSlot>? v) => _s._cachedAddonSlots = v;
  @override
  set cachedStremioSubtitles(List<StremioSubtitle>? v) =>
      _s._cachedStremioSubtitles = v;
  @override
  String? get cachedSubtitleKey => _s._cachedSubtitleKey;
  @override
  set cachedSubtitleKey(String? v) => _s._cachedSubtitleKey = v;
  @override
  bool get canFetchEpisodes => _s._canFetchEpisodes;
  @override
  void captureIptvAudioLanguage(String audioId) =>
      _s._iptvMemory.captureIptvAudioLanguage(audioId);
  @override
  bool get continuousShuffleEnabled => _s._continuousShuffleEnabled;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  Future<void> fetchSingleFileMovieMetadata() =>
      _s._fetchSingleFileMovieMetadata();
  @override
  void hidePlayerMenu() => _s._menu.hidePlayerMenu();
  @override
  List<AddonSubtitleSlot>? get injectedSubtitleSlots =>
      _s._injectedSubtitleSlots;
  @override
  bool get iptvZapBannerOwnsIdentity => _s._iptvZapBannerOwnsIdentity;
  @override
  int? get manualContentEpisode => _s._manualContentEpisode;
  @override
  String? get manualContentImdbId => _s._manualContentImdbId;
  @override
  int? get manualContentSeason => _s._manualContentSeason;
  @override
  String? get manualContentType => _s._manualContentType;
  @override
  String? get menuCacheKey => _s._menuCacheKey;
  @override
  List<AddonSubtitleSlot>? get menuCachedSlots => _s._menuCachedSlots;
  @override
  String? get menuContentType => _s._menuContentType;
  @override
  int? get menuEpisode => _s._menuEpisode;
  @override
  String? get menuImdbId => _s._menuImdbId;
  @override
  int? get menuSeason => _s._menuSeason;
  @override
  Future<bool> menuSelectAddonSubtitle(StremioSubtitle sub, String audioId) =>
      _s._menu.menuSelectAddonSubtitle(sub, audioId);
  @override
  Future<void> menuSelectAudio(String audioId, String currentSubId) =>
      _s._menu.menuSelectAudio(audioId, currentSubId);
  @override
  Future<bool> menuSelectEmbeddedSubtitle(String subId, String audioId) =>
      _s._menu.menuSelectEmbeddedSubtitle(subId, audioId);
  @override
  Future<bool> menuSubtitlesOff(String audioId) =>
      _s._menu.menuSubtitlesOff(audioId);
  @override
  void openPlayerMenuAt(
    PlayerMenuSection section, {
    String? imdbId,
    String? contentType,
    int? season,
    int? episode,
    List<AddonSubtitleSlot>? cachedSlots,
    String? cacheKey,
  }) => _s._menu.openPlayerMenuAt(
    section,
    imdbId: imdbId,
    contentType: contentType,
    season: season,
    episode: episode,
    cachedSlots: cachedSlots,
    cacheKey: cacheKey,
  );
  @override
  Future<void> playRandomOnce({bool disableContinuousShuffle = false}) =>
      _s._playRandomOnce(disableContinuousShuffle: disableContinuousShuffle);
  @override
  mk.Player get player => _s._player;
  @override
  PlayerMenuSection get playerMenuInitialSection =>
      _s._playerMenuInitialSection;
  @override
  GlobalKey<PlayerMenuPanelState> get playerMenuKey => _s._playerMenuKey;
  @override
  String? get selectedStremioSubtitleId => _s._selectedStremioSubtitleId;
  @override
  set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  Future<void> setAudioPassthroughLive(bool enabled) =>
      _s._setAudioPassthroughLive(enabled);
  @override
  bool get singleFileImdbFetched => _s._singleFileImdbFetched;
  @override
  String? get singleFileImdbId => _s._singleFileImdbId;
  @override
  ValueNotifier<String?> get subtitleSelectionCorrection =>
      _s._subtitleSelectionCorrection;
  @override
  Future<void> toggleContinuousShuffle() => _s._toggleContinuousShuffle();
  @override
  set userManuallySelectedSubtitle(bool v) =>
      _s._userManuallySelectedSubtitle = v;
  @override
  Future<bool> withManualSubtitleChoice(Future<bool> Function() apply) =>
      _s._menu.withManualSubtitleChoice(apply);
  @override
  String currentPlaybackTitleForIdentity() =>
      _s._identify.currentPlaybackTitleForIdentity();
  @override
  Future<TracksSheetSubtitleSearchResult?> identifyTitleAndFetchSubtitles() =>
      _s._identify.identifyTitleAndFetchSubtitles();
  @override
  String? subtitleIdentityLabelForSheet() =>
      _s._identify.subtitleIdentityLabelForSheet();
  @override
  void setActiveExternalSubtitlePath(String? path) =>
      _s._subtitleSync.setActiveExternalSubtitlePath(path);
  @override
  void resetSubtitleSyncOffset() => _s._subtitleSync.resetSubtitleSyncOffset();
  @override
  void onSubtitleStyleChanged(SubtitleSettingsData settings) =>
      _s._subtitleSync.onSubtitleStyleChanged(settings);
  @override
  void showSyncOverlayPanel() => _s._subtitleSync.showSyncOverlayPanel();
  @override
  Future<void> persistTrackChoice(String audioId, String subtitleId) =>
      _s._trackPreferences.persistTrackChoice(audioId, subtitleId);
  @override
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  }) => _s._subtitleApply.setSubtitleTrackWithDiagnostics(
    track,
    source: source,
    isCurrent: isCurrent,
  );
  @override
  double get playbackSpeed => _s._display.playbackSpeed;
  @override
  void setPlaybackSpeed(double speed) => _s._display.setPlaybackSpeed(speed);
  @override
  AspectMode get aspectMode => _s._display.aspectMode;
  @override
  void setAspectModeDirect(AspectMode mode) =>
      _s._display.setAspectModeDirect(mode);
  @override
  SleepTimerMode get sleepTimerMode => _s._sleep.sleepTimerMode;
  @override
  int get sleepTimerArmedMinutes => _s._sleep.sleepTimerArmedMinutes;
  @override
  int get sleepTimerMinutesLeft => _s._sleep.sleepTimerMinutesLeft;
  @override
  void applySleepTimerSelection(SleepTimerSelection picked) =>
      _s._sleep.applySleepTimerSelection(picked);
}

class _VpIdentifyTitleUiHostAdapter implements VpIdentifyTitleUiHost {
  _VpIdentifyTitleUiHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  BuildContext get context => _s.context;
  @override
  bool get mounted => _s.mounted;
}

class _VpIdentifyTitleHostAdapter implements VpIdentifyTitleHost {
  _VpIdentifyTitleHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  BuildContext get context => _s.context;
  @override
  bool get mounted => _s.mounted;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override
  set addonSubtitleFetchToken(int v) => _s._addonSubtitleFetchToken = v;
  @override
  set cachedAddonSlots(List<AddonSubtitleSlot>? v) => _s._cachedAddonSlots = v;
  @override
  set cachedStremioSubtitles(List<StremioSubtitle>? v) =>
      _s._cachedStremioSubtitles = v;
  @override
  set cachedSubtitleKey(String? v) => _s._cachedSubtitleKey = v;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  int? get currentStremioTvContentEpisode => _s._currentStremioTvContentEpisode;
  @override
  int? get currentStremioTvContentSeason => _s._currentStremioTvContentSeason;
  @override
  String? get currentStremioTvContentTitle => _s._currentStremioTvContentTitle;
  @override
  String get dynamicTitle => _s._dynamicTitle;
  @override
  set embeddedSubtitleApplied(bool v) => _s._embeddedSubtitleApplied = v;
  @override
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  ) => _s._findSeriesEpisodeForCurrentIndex(seriesPlaylist);
  @override
  int? get manualContentEpisode => _s._manualContentEpisode;
  @override
  set manualContentEpisode(int? v) => _s._manualContentEpisode = v;
  @override
  set manualContentImdbId(String? v) => _s._manualContentImdbId = v;
  @override
  int? get manualContentSeason => _s._manualContentSeason;
  @override
  set manualContentSeason(int? v) => _s._manualContentSeason = v;
  @override
  set manualContentType(String? v) => _s._manualContentType = v;
  @override
  String? get manualSubtitleDisplayLabel => _s._manualSubtitleDisplayLabel;
  @override
  set manualSubtitleDisplayLabel(String? v) =>
      _s._manualSubtitleDisplayLabel = v;
  @override
  Future<VpSeasonEpisodeSelection?> requestSeasonEpisodeForIdentity(
    String title,
  ) => _s._identifyUi.requestSeasonEpisodeForIdentity(title);
  @override
  String? get selectedStremioSubtitleId => _s._selectedStremioSubtitleId;
  @override
  set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  Future<StremioMeta?> showIdentifyTitleSearchSheet({
    required String initialQuery,
  }) => _s._identifyUi.showIdentifyTitleSearchSheet(initialQuery: initialQuery);
  @override
  set userManuallySelectedSubtitle(bool v) =>
      _s._userManuallySelectedSubtitle = v;
  @override
  String get title => _s.widget.title;
  @override
  String? get contentTitle => _s.widget.contentTitle;
  @override
  int? get contentSeason => _s.widget.contentSeason;
  @override
  int? get contentEpisode => _s.widget.contentEpisode;
  @override
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle() =>
      _s._addonSubtitles.fetchAndMaybeAutoSelectAddonSubtitle();
}

class _VpAddonSubtitlesHostAdapter implements VpAddonSubtitlesHost {
  _VpAddonSubtitlesHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override
  Future<bool> applyDefaultSubtitleLanguage({
    bool ignoreSourcePriority = false,
  }) => _s._subtitleLanguage.applyDefaultSubtitleLanguage(
    ignoreSourcePriority: ignoreSourcePriority,
  );
  @override
  Future<bool> applyForcedSubtitle(String? language, bool Function() current) =>
      _s._subtitleLanguage.applyForcedSubtitle(language, current);
  @override
  bool get audioAllowsAutomaticSubtitles =>
      _s._subtitleLanguage.audioAllowsAutomaticSubtitles;
  @override
  List<AddonSubtitleSlot>? get cachedAddonSlots => _s._cachedAddonSlots;
  @override
  set cachedAddonSlots(List<AddonSubtitleSlot>? v) => _s._cachedAddonSlots = v;
  @override
  List<StremioSubtitle>? get cachedStremioSubtitles =>
      _s._cachedStremioSubtitles;
  @override
  set cachedStremioSubtitles(List<StremioSubtitle>? v) =>
      _s._cachedStremioSubtitles = v;
  @override
  String? get cachedSubtitleKey => _s._cachedSubtitleKey;
  @override
  set cachedSubtitleKey(String? v) => _s._cachedSubtitleKey = v;
  @override
  int? get currentStremioTvContentEpisode => _s._currentStremioTvContentEpisode;
  @override
  int? get currentStremioTvContentSeason => _s._currentStremioTvContentSeason;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  bool get embeddedSubtitleApplied => _s._embeddedSubtitleApplied;
  @override
  set embeddedSubtitleApplied(bool v) => _s._embeddedSubtitleApplied = v;
  @override
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  ) => _s._findSeriesEpisodeForCurrentIndex(seriesPlaylist);
  @override
  int? get manualContentEpisode => _s._manualContentEpisode;
  @override
  String? get manualContentImdbId => _s._manualContentImdbId;
  @override
  int? get manualContentSeason => _s._manualContentSeason;
  @override
  String? get manualContentType => _s._manualContentType;
  @override
  mk.Player get player => _s._player;
  @override
  String? get selectedStremioSubtitleId => _s._selectedStremioSubtitleId;
  @override
  set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  String? get singleFileImdbId => _s._singleFileImdbId;
  @override
  int get subtitleAudioRevision => _s._subtitleAudioRevision;
  @override
  bool get subtitleForcedOnly => _s._subtitleForcedOnly;
  @override
  bool get trackPreferencesReadyForAddonSubtitles =>
      _s._trackPreferencesReadyForAddonSubtitles;
  @override
  bool get userManuallySelectedSubtitle => _s._userManuallySelectedSubtitle;
  @override
  int? get contentSeason => _s.widget.contentSeason;
  @override
  int? get contentEpisode => _s.widget.contentEpisode;
  @override
  void setActiveExternalSubtitlePath(String? path) =>
      _s._subtitleSync.setActiveExternalSubtitlePath(path);
  @override
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  }) => _s._subtitleApply.setSubtitleTrackWithDiagnostics(
    track,
    source: source,
    isCurrent: isCurrent,
  );
}

class _VpTrackPreferencesHostAdapter implements VpTrackPreferencesHost {
  _VpTrackPreferencesHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt =>
      _s._activeSubtitleApplyAttempt;
  @override
  int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override
  Future<void> applyDefaultAudioLanguage() =>
      _s._subtitleLanguage.applyDefaultAudioLanguage();
  @override
  Future<bool> applyDefaultSubtitleLanguage({
    bool ignoreSourcePriority = false,
  }) => _s._subtitleLanguage.applyDefaultSubtitleLanguage(
    ignoreSourcePriority: ignoreSourcePriority,
  );
  @override
  Future<void> applyIptvAudioPreference(int ticket) =>
      _s._iptvMemory.applyIptvAudioPreference(ticket);
  @override
  set embeddedSubtitleApplied(bool v) => _s._embeddedSubtitleApplied = v;
  @override
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle() =>
      _s._addonSubtitles.fetchAndMaybeAutoSelectAddonSubtitle();
  @override
  bool get hasSubtitlePolicy => _s._hasSubtitlePolicy;
  @override
  int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override
  bool get isIptvSeriesContext => _s._isIptvSeriesContext;
  @override
  mk.Player get player => _s._player;
  @override
  Future<void> refreshSubtitleAudioPolicy({bool reselect = true}) =>
      _s._subtitleLanguage.refreshSubtitleAudioPolicy(reselect: reselect);
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  set trackPreferencesReadyForAddonSubtitles(bool v) =>
      _s._trackPreferencesReadyForAddonSubtitles = v;
  @override
  set userManuallySelectedSubtitle(bool v) =>
      _s._userManuallySelectedSubtitle = v;
  @override
  String get title => _s.widget.title;
  @override
  Future<void> waitForSubtitleTracks({required int token}) =>
      _s._subtitleApply.waitForSubtitleTracks(token: token);
  @override
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  }) => _s._subtitleApply.setSubtitleTrackWithDiagnostics(
    track,
    source: source,
    isCurrent: isCurrent,
  );
}

class _VpSubtitleLanguagePolicyHostAdapter
    implements VpSubtitleLanguagePolicyHost {
  _VpSubtitleLanguagePolicyHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override
  Future<void> applySubtitleSourcePriority(
    List<AddonSubtitleSlot> slots,
    int token, {
    bool discoveryReady = true,
  }) => _s._addonSubtitles.applySubtitleSourcePriority(
    slots,
    token,
    discoveryReady: discoveryReady,
  );
  @override
  List<AddonSubtitleSlot>? get cachedAddonSlots => _s._cachedAddonSlots;
  @override
  set embeddedSubtitleApplied(bool v) => _s._embeddedSubtitleApplied = v;
  @override
  bool get hasSubtitlePolicy => _s._hasSubtitlePolicy;
  @override
  mk.Player get player => _s._player;
  @override
  set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;
  @override
  int get subtitleAudioRevision => _s._subtitleAudioRevision;
  @override
  set subtitleAudioRevision(int v) => _s._subtitleAudioRevision = v;
  @override
  bool get subtitleForcedOnly => _s._subtitleForcedOnly;
  @override
  bool get subtitleOnlyForeignAudio => _s._subtitleOnlyForeignAudio;
  @override
  String? get subtitlePreferredAudio => _s._subtitlePreferredAudio;
  @override
  String? get subtitleSelectedAudio => _s._subtitleSelectedAudio;
  @override
  set subtitleSelectedAudio(String? v) => _s._subtitleSelectedAudio = v;
  @override
  bool get trackPreferencesReadyForAddonSubtitles =>
      _s._trackPreferencesReadyForAddonSubtitles;
  @override
  bool get userManuallySelectedSubtitle => _s._userManuallySelectedSubtitle;
  @override
  void setActiveExternalSubtitlePath(String? path) =>
      _s._subtitleSync.setActiveExternalSubtitlePath(path);
  @override
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  }) => _s._subtitleApply.setSubtitleTrackWithDiagnostics(
    track,
    source: source,
    isCurrent: isCurrent,
  );
}

class _VpSubtitleApplyHostAdapter implements VpSubtitleApplyHost {
  _VpSubtitleApplyHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  mk.Player get player => _s._player;
  @override
  int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override
  bool get isIOS => VpS2Hooks.isIOS;
  @override
  bool get isAndroid => VpS2Hooks.isAndroid;
  @override
  bool get isPipActive => _s._isPipActive;
  @override
  bool get iosPipStarting => _s._pip.iosPipStarting;
  @override
  AndroidVideoRendererMode get androidVideoRendererMode =>
      _s._androidVideoRendererMode;
  @override
  String? get selectedStremioSubtitleId => _s._selectedStremioSubtitleId;
  @override
  set selectedStremioSubtitleId(String? v) => _s._selectedStremioSubtitleId = v;
  @override
  String? get activeExternalSubtitlePath => _s._activeExternalSubtitlePath;
  @override
  ValueNotifier<String?> get subtitleSelectionCorrection =>
      _s._subtitleSelectionCorrection;
  @override
  GlobalKey<PlayerMenuPanelState> get playerMenuKey => _s._playerMenuKey;
  @override
  void setActiveExternalSubtitlePath(String? path) =>
      _s._subtitleSync.setActiveExternalSubtitlePath(path);
  @override
  Future<void> persistTrackChoice(String audio, String subtitle) =>
      _s._trackPreferences.persistTrackChoice(audio, subtitle);
  @override
  int get subtitleDiagnosticGeneration => _s._subtitleDiagnosticGeneration;
  @override
  set subtitleDiagnosticGeneration(int v) =>
      _s._subtitleDiagnosticGeneration = v;
  @override
  VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt =>
      _s._activeSubtitleApplyAttempt;
  @override
  set activeSubtitleApplyAttempt(VpSubtitleApplyAttempt? v) =>
      _s._activeSubtitleApplyAttempt = v;
}

class _VpSubtitleAutoSyncHostAdapter implements VpSubtitleAutoSyncHost {
  _VpSubtitleAutoSyncHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  mk.Player get player => _s._player;
  @override
  Duration get position => _s._position;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  bool get audioPassthroughEnabled => _s._audioPassthroughEnabled;
  @override
  SubtitleSettingsData? get subtitleSettings => _s._subtitleSettings;
  @override
  set subtitleSettings(SubtitleSettingsData? v) => _s._subtitleSettings = v;
  @override
  String? get activeExternalSubtitlePath => _s._activeExternalSubtitlePath;
  @override
  set activeExternalSubtitlePath(String? v) =>
      _s._activeExternalSubtitlePath = v;
  @override
  ValueNotifier<AutoSyncPillModel?> get autoSyncPill => _s._autoSyncPill;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  set showSyncOverlay(bool v) => _s._showSyncOverlay = v;
  @override
  void tvReleaseFocusForOverlay() => _s._tvReleaseFocusForOverlay();
}

class _VpPipLifecycleHostAdapter implements VpPipLifecycleHost {
  _VpPipLifecycleHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  Object get pipOwner => _s;
  @override
  bool get isIOS => VpS2Hooks.isIOS;
  @override
  bool get isAndroid => VpS2Hooks.isAndroid;
  @override
  mk.Player get player => _s._player;
  @override
  bool get playerCreated => _s._playerCreated;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  bool get isPipActive => _s._isPipActive;
  @override
  set isPipActive(bool v) => _s._isPipActive = v;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  bool get hasAnyNext => _s._hasAnyNext;
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  Future<void> setNativeSubtitleVisibilityForTrack(mk.SubtitleTrack track) =>
      _s._subtitleApply.setNativeSubtitleVisibilityForTrack(track);
  @override
  void togglePlay() => _s._togglePlay();
  @override
  Future<void> goToNextEpisode() => _s._goToNextEpisode();
  @override
  void cancelPendingIptvCatchup({bool hideFeedback = true}) =>
      _s._iptvGuide.cancelPendingIptvCatchup(hideFeedback: hideFeedback);
  @override
  bool get rendererFallbackInProgress => _s._rendererFallbackInProgress;
  @override
  bool get pausedByLifecycle => _s._pausedByLifecycle;
  @override
  set pausedByLifecycle(bool v) => _s._pausedByLifecycle = v;
  @override
  bool get iptvStartOverActive => _s._iptvStartOverActive;
  @override
  bool get activeMediaShouldPlay => _s._activeMediaShouldPlay;
  @override
  bool get activeMediaUserPaused => _s._activeMediaUserPaused;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  ValueNotifier<String?> get iptvReconnectText => _s._iptvReconnectText;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  void traktScrobbleSeek(Duration position) =>
      _s._trakt.traktScrobbleSeek(position);
  @override
  void simklScrobbleSeek(Duration position) =>
      _s._simkl.simklScrobbleSeek(position);
  @override
  void mdblistScrobbleSeek(Duration position) =>
      _s._mdblist.mdblistScrobbleSeek(position);
  @override
  bool get landscapeLocked => _s._display.landscapeLocked;
}

class _VpLocalCompletionHostAdapter implements VpLocalCompletionHost {
  _VpLocalCompletionHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  bool get traktScrobble => _s.widget.traktScrobble;
  @override
  bool get simklScrobble => _s.widget.simklScrobble;
  @override
  bool get mdblistScrobble => _s.widget.mdblistScrobble;
  @override
  List<Map<String, dynamic>>? get stremioTvChannels =>
      _s.widget.stremioTvChannels;
  @override
  String? get contentType => _s.widget.contentType;
  @override
  int? get contentSeason => _s.widget.contentSeason;
  @override
  int? get contentEpisode => _s.widget.contentEpisode;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  String? get contentTitle => _s.widget.contentTitle;
  @override
  String get title => _s.widget.title;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  Duration get position => _s._position;
  @override
  Duration get duration => _s._duration;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  String get resumeKey => _s._resumeKeys.resumeKey;
}

class _VpMdblistScrobblerHostAdapter implements VpMdblistScrobblerHost {
  _VpMdblistScrobblerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  Duration get duration => _s._duration;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  String? get contentType => _s.widget.contentType;
  @override
  String? get currentSeriesImdbId => _s._currentSeriesImdbId;
  @override
  String? get episodeTrackerProgressImdbId => _s._episodeTrackerProgressImdbId;
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  void bindEpisodeTrackerProgressIdentity(String imdbId) =>
      _s._bindEpisodeTrackerProgressIdentity(imdbId);
  @override
  bool get mdblistScrobble => _s.widget.mdblistScrobble;
  @override
  Duration get position => _s._position;
  @override
  Duration get persistablePosition => _s._persistablePosition;
  @override
  Future<void> get playerInitializationFuture => _s._playerInitializationFuture;
}

class _VpSimklScrobblerHostAdapter implements VpSimklScrobblerHost {
  _VpSimklScrobblerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  Duration get duration => _s._duration;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  String? get contentType => _s.widget.contentType;
  @override
  String? get currentSeriesImdbId => _s._currentSeriesImdbId;
  @override
  String? get episodeTrackerProgressImdbId => _s._episodeTrackerProgressImdbId;
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  void bindEpisodeTrackerProgressIdentity(String imdbId) =>
      _s._bindEpisodeTrackerProgressIdentity(imdbId);
  @override
  bool get simklScrobble => _s.widget.simklScrobble;
  @override
  double traktProgress() => _s._trakt.traktProgress();
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
}

class _VpTraktScrobblerHostAdapter implements VpTraktScrobblerHost {
  _VpTraktScrobblerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  Duration get duration => _s._duration;
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  String? get contentType => _s.widget.contentType;
  @override
  String? get currentSeriesImdbId => _s._currentSeriesImdbId;
  @override
  String? get episodeTrackerProgressImdbId => _s._episodeTrackerProgressImdbId;
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  void bindEpisodeTrackerProgressIdentity(String imdbId) =>
      _s._bindEpisodeTrackerProgressIdentity(imdbId);
  @override
  bool get traktScrobble => _s.widget.traktScrobble;
  @override
  Duration get persistablePosition => _s._persistablePosition;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
}

class _VpDisplayModeHostAdapter implements VpDisplayModeHost {
  _VpDisplayModeHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  mk.Player get player => _s._player;
  @override
  void scheduleAutoHide() => _s._scheduleAutoHide();
  @override
  Future<void> saveResume() => _s._resumeSave.saveResume();
  @override
  void openPlayerMenuQuick(PlayerMenuSection section) =>
      _s._menu.openPlayerMenuQuick(section);
  @override
  ValueNotifier<AspectRatioHudState?> get aspectRatioHud => _s._aspectRatioHud;
  @override
  ValueNotifier<bool> get speedHoldHud => _s._speedHoldHud;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  double dockBand(double legacy) => _s._dockBand(legacy);
  @override
  bool get hideBackButton => _s.widget.hideBackButton;
  @override
  bool get hideOptions => _s.widget.hideOptions;
}

class _VpSkipSegmentHostAdapter implements VpSkipSegmentHost {
  _VpSkipSegmentHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  Duration get duration => _s._duration;
  @override
  Duration get position => _s._position;
  @override
  set position(Duration v) => _s._position = v;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist sp) =>
      _s._findSeriesEpisodeForCurrentIndex(sp);
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  bool get playerCreated => _s._playerCreated;
  @override
  PlaybackUiClockController get playbackUiClock => _s._playbackUiClock;
  @override
  mk.Player get player => _s._player;
  @override
  SkipSegmentUiController get activeSkipSegmentUi => _s._activeSkipSegmentUi;
  @override
  void traktScrobbleSeek(Duration target) =>
      _s._trakt.traktScrobbleSeek(target);
  @override
  void simklScrobbleSeek(Duration target) =>
      _s._simkl.simklScrobbleSeek(target);
  @override
  void mdblistScrobbleSeek(Duration target) =>
      _s._mdblist.mdblistScrobbleSeek(target);
}

class _VpSleepTimerHostAdapter implements VpSleepTimerHost {
  _VpSleepTimerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  void openPlayerMenuQuick(PlayerMenuSection section) =>
      _s._menu.openPlayerMenuQuick(section);
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  void scheduleAutoHide() => _s._scheduleAutoHide();
  @override
  set sleepStopLatched(bool v) => _s._sleepStopLatched = v;
  @override
  set activeMediaShouldPlay(bool v) => _s._activeMediaShouldPlay = v;
  @override
  bool get playerCreated => _s._playerCreated;
  @override
  Future<void> saveResume() => _s._resumeSave.saveResume();
  @override
  mk.Player get player => _s._player;
}

/// Three interception points for the original player characterization harness.
@visibleForTesting
class VideoPlayerScreenTestHooks {
  const VideoPlayerScreenTestHooks({
    required this.ensureInitialized,
    required this.createPlayer,
    required this.createVideoController,
  });
  final void Function() ensureInitialized;
  final mk.Player Function(mk.PlayerConfiguration configuration) createPlayer;
  final mkv.VideoController Function(
    mk.Player player,
    mkv.VideoControllerConfiguration configuration,
  )
  createVideoController;
  static VideoPlayerScreenTestHooks? _installed;
  static void install(VideoPlayerScreenTestHooks? hooks) {
    if (kReleaseMode || kProfileMode) {
      throw StateError(
        'Video player test hooks require an assertion-enabled test',
      );
    }
    if (!const bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS')) {
      throw StateError('Video player test hooks require DEBRIFY_VP_TEST_HOOKS');
    }
    assert(() {
      _installed = hooks;
      return true;
    }());
  }

  static void _ensureInitialized() {
    final hooks = _installed;
    if (hooks == null) {
      MediaKitInit.ensureInitialized();
    } else {
      hooks.ensureInitialized();
    }
  }

  static mk.Player _createPlayer({
    required mk.PlayerConfiguration configuration,
  }) {
    final hooks = _installed;
    return hooks == null
        ? mk.Player(configuration: configuration)
        : hooks.createPlayer(configuration);
  }

  static mkv.VideoController _createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) {
    final hooks = _installed;
    return hooks == null
        ? mkv.VideoController(player, configuration: configuration)
        : hooks.createVideoController(player, configuration);
  }
}

/// Platform predicates for the separately reviewed PiP characterization seam.
@visibleForTesting
class VpS2Hooks {
  const VpS2Hooks({this.ios, this.android});
  final bool Function()? ios;
  final bool Function()? android;
  static VpS2Hooks? _installed;

  static void install(VpS2Hooks? hooks) {
    if (kReleaseMode || kProfileMode) {
      throw StateError(
        'Video player platform hooks require an assertion-enabled test',
      );
    }
    if (!const bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS')) {
      throw StateError(
        'Video player platform hooks require DEBRIFY_VP_TEST_HOOKS',
      );
    }
    assert(() {
      _installed = hooks;
      return true;
    }());
  }

  static bool get isIOS => _installed?.ios?.call() ?? Platform.isIOS;
  static bool get isAndroid =>
      _installed?.android?.call() ?? Platform.isAndroid;
}
