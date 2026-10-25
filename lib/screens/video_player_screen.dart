import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import '../models/source_playlist_resolver.dart';
import '../widgets/playback_startup_view.dart';
import '../utils/episode_playback_request.dart';
import 'video_player/player_pip_route.dart';
import 'dart:async';
import '../services/player_visibility.dart';
import '../utils/media_kit_init.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kProfileMode, kReleaseMode, visibleForTesting;
import 'package:flutter/material.dart';
import '../models/custom_series_identity.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import '../services/player_display_controls.dart';
import 'package:synchronized/synchronized.dart';

// Removed volume_controller; using media_kit player volume instead
import '../services/local_playback_resume_resolver.dart';
import '../services/startup_stream_policy.dart';
import '../services/media_server_watch_sync.dart';
import '../services/resume_write_guard.dart';
import '../services/skip_segment_service.dart';
import '../services/analytics_service.dart';
import '../services/pip_service.dart';
import '../services/tvos_decode_remedy.dart';
import '../services/tvos_display_match_service.dart';
import '../services/android_native_downloader.dart';
import '../services/desktop_recording_service.dart';
import '../services/main_page_bridge.dart';
import '../services/profiles/profile_lock_controller.dart';
import '../utils/platform_util.dart';
import '../utils/series_parser.dart';
import '../models/iptv_playlist.dart';
import '../services/stremio_iptv_service.dart';
import '../services/iptv_epg_service.dart';
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';

import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

// Video Player Components
import 'video_player/models/playlist_entry.dart';
import 'video_player/models/gesture_state.dart';
import 'video_player/models/hud_state.dart';
import 'video_player/painters/double_tap_ripple_painter.dart';
import 'video_player/utils/gesture_helpers.dart';
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
import 'video_player/services/iptv_tune_diagnostics.dart';
import 'video_player/services/iptv_live_recovery.dart';
import 'video_player/widgets/skip_segment_button.dart';
import 'video_player/widgets/sleep_timer_sheet.dart';
import 'video_player/widgets/debrify_tv_banner.dart';
import '../models/stremio_subtitle.dart';
import '../models/stremio_addon.dart';
import '../models/torrent.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/content_display_match_mode.dart';
import '../services/series_source_fetcher.dart';
import '../utils/tv_keys.dart';

// Re-export PlaylistEntry for backward compatibility
export 'video_player/models/playlist_entry.dart';
export 'video_player/models/channel_entry.dart';
export '../features/video_player/models/iptv_catchup_request_gate.dart'
    show IptvCatchupRequestGate;
import '../features/video_player/models/vp_season_episode_selection.dart';
import '../features/video_player/models/vp_subtitle_apply_attempt.dart';
import '../features/video_player/models/vp_iptv_zap_page.dart';
import '../features/video_player/application/vp_format.dart';
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
import '../features/video_player/presentation/legacy_video_player/vp_startup_candidates.dart';
import '../features/video_player/presentation/legacy_video_player/vp_startup_failover.dart';
import '../features/video_player/presentation/legacy_video_player/vp_startup_gate.dart';
import '../features/video_player/presentation/legacy_video_player/vp_source_switch.dart';
import '../features/video_player/presentation/legacy_video_player/vp_source_playlist_switch.dart';
import '../features/video_player/presentation/legacy_video_player/vp_debrify_tv_channels.dart';
import '../features/video_player/presentation/legacy_video_player/vp_debrify_tv_banner.dart';
import '../features/video_player/presentation/legacy_video_player/vp_stremio_tv_channels.dart';
import '../features/video_player/presentation/legacy_video_player/vp_episode_fetch.dart';
import '../features/video_player/presentation/legacy_video_player/vp_episode_guide.dart';
import '../features/video_player/presentation/legacy_video_player/vp_playback_ended.dart';
import '../features/video_player/presentation/legacy_video_player/vp_episode_next.dart';
import '../features/video_player/presentation/legacy_video_player/vp_episode_adjacent.dart';
import '../features/video_player/presentation/legacy_video_player/vp_shuffle.dart';
import '../features/video_player/presentation/legacy_video_player/vp_episode_title_info.dart';
import '../features/video_player/presentation/legacy_video_player/vp_playlist_load.dart';
import '../features/video_player/presentation/legacy_video_player/vp_playlist_entry_resolve.dart';
import '../features/video_player/presentation/legacy_video_player/vp_media_waits.dart';
import '../features/video_player/presentation/legacy_video_player/vp_pikpak_retry.dart';
import '../features/video_player/presentation/legacy_video_player/vp_metadata_preload.dart';
import '../features/video_player/presentation/legacy_video_player/vp_audio_output.dart';
import '../features/video_player/presentation/legacy_video_player/vp_video_output_lease.dart';
import '../features/video_player/presentation/legacy_video_player/vp_tvos_video.dart';
import '../features/video_player/presentation/legacy_video_player/vp_decoder_probe.dart';
import '../features/video_player/presentation/legacy_video_player/vp_renderer_fallback.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_defaults.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_instance.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_subscriptions.dart';
import '../features/video_player/presentation/legacy_video_player/vp_network_tuning.dart';
import '../features/video_player/presentation/legacy_video_player/vp_media_open.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_startup.dart';
import '../features/video_player/presentation/legacy_video_player/vp_transition_overlay.dart';
import '../features/video_player/presentation/legacy_video_player/vp_dock_layout.dart';
import '../features/video_player/presentation/legacy_video_player/vp_controls_runtime.dart';
import '../features/video_player/presentation/legacy_video_player/vp_tv_remote.dart';
import '../features/video_player/presentation/legacy_video_player/vp_player_gestures.dart';

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
    _startupCandidates = VpStartupCandidates(
      _VpStartupCandidatesHostAdapter(this),
    );
    _startupFailover = VpStartupFailover(_VpStartupFailoverHostAdapter(this));
    _startupGate = VpStartupGate(_VpStartupGateHostAdapter(this));
    _sourceSwitch = VpSourceSwitch(_VpSourceSwitchHostAdapter(this));
    _sourcePlaylistSwitch = VpSourcePlaylistSwitch(
      _VpSourcePlaylistSwitchHostAdapter(this),
    );
    _debrifyChannels = VpDebrifyTvChannels(
      _VpDebrifyTvChannelsHostAdapter(this),
    );
    _debrifyBanner = VpDebrifyTvBanner(_VpDebrifyTvBannerHostAdapter(this));
    _stremioTv = VpStremioTvChannels(_VpStremioTvChannelsHostAdapter(this));
    _episodeFetch = VpEpisodeFetch(_VpEpisodeFetchHostAdapter(this));
    _episodeGuide = VpEpisodeGuide(_VpEpisodeGuideHostAdapter(this));
    _playbackEnded = VpPlaybackEnded(_VpPlaybackEndedHostAdapter(this));
    _episodeNext = VpEpisodeNext(_VpEpisodeNextHostAdapter(this));
    _episodeAdjacent = VpEpisodeAdjacent(_VpEpisodeAdjacentHostAdapter(this));
    _shuffle = VpShuffle(_VpShuffleHostAdapter(this));
    _episodeTitleInfo = VpEpisodeTitleInfo(
      _VpEpisodeTitleInfoHostAdapter(this),
    );
    _playlistLoad = VpPlaylistLoad(_VpPlaylistLoadHostAdapter(this));
    _playlistEntryResolve = VpPlaylistEntryResolve(
      _VpPlaylistEntryResolveHostAdapter(this),
    );
    _mediaWaits = VpMediaWaits(_VpMediaWaitsHostAdapter(this));
    _pikPakRetry = VpPikPakRetry(_VpPikPakRetryHostAdapter(this));
    _metadataPreload = VpMetadataPreload(_VpMetadataPreloadHostAdapter(this));
    _audioOutput = VpAudioOutput(_VpAudioOutputHostAdapter(this));
    _videoOutputLease = VpVideoOutputLease(
      _VpVideoOutputLeaseHostAdapter(this),
    );
    _tvosVideo = VpTvosVideo(_VpTvosVideoHostAdapter(this));
    _decoderProbe = VpDecoderProbe(_VpDecoderProbeHostAdapter(this));
    _rendererFallback = VpRendererFallback(
      _VpRendererFallbackHostAdapter(this),
    );
    _playerDefaults = VpPlayerDefaults(_VpPlayerDefaultsHostAdapter(this));
    _playerInstance = VpPlayerInstance(_VpPlayerInstanceHostAdapter(this));
    _playerSubscriptions = VpPlayerSubscriptions(
      _VpPlayerSubscriptionsHostAdapter(this),
    );
    _networkTuner = VpNetworkTuning(_VpNetworkTuningHostAdapter(this));
    _mediaOpen = VpMediaOpen(_VpMediaOpenHostAdapter(this));
    _playerStartup = VpPlayerStartup(_VpPlayerStartupHostAdapter(this));
    _transitionOverlay = VpTransitionOverlay(
      _VpTransitionOverlayHostAdapter(this),
    );
    _dockLayout = VpDockLayout(_VpDockLayoutHostAdapter(this));
    _controlsRuntime = VpControlsRuntime(_VpControlsRuntimeHostAdapter(this));
    _tvRemote = VpTvRemote(_VpTvRemoteHostAdapter(this));
    _gestures = VpPlayerGestures(_VpPlayerGesturesHostAdapter(this));
  }
  void _vpSetState(VoidCallback fn) => setState(fn);

  static const MethodChannel _tvReleaseLogChannel = MethodChannel(
    'debrify/tvlog',
  );

  late mk.Player _player;
  // _player is assigned partway through the async _initializePlayer(); if the
  // user backs out before that (or init throws first), dispose() must not
  // touch the unassigned late field (LateInitializationError during pop).
  bool _playerCreated = false;
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

  /// Audio-output settings (AUDIO_FIDELITY_PLAN.md), preloaded in
  /// [_loadPlayerDefaults] and applied by [_configurePlayerAudio].
  bool _audioPassthroughEnabled = false;
  bool _systemAudioEffectsEnabled = false;
  bool _appleMultichannelEnabled = false;
  int _tvosRouteOutputChannels = 0;
  bool _tvosForceStereoAudio = false;
  bool _tvosLegacyAudioOutput = false;
  int _playerInstanceGeneration = 0;

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

  /// Bumped on every transition and on dispose. A confirm carrying a stale
  /// generation is dropped, so a scrub started before a source switch can
  /// never seek the item that replaced it.
  int _tvScrubGeneration = 0;

  // Text subtitles stay in MediaKit's Flutter renderer. Bitmap subtitles are
  // the narrow exception: their decoded image cues cannot enter a text widget,
  // so the selection path temporarily enables mpv's native compositor.
  bool _isSeekingWithSlider = false;
  Duration? _lastSliderSeekPos;

  // Channel badge auto-hide
  // Debrify TV lower-third (replaces the two legacy corner badges).
  bool _showDebrifyBanner = false;
  bool _debrifyBannerFloatingMounted = false;

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
  int _currentIndex = 0;
  Offset? _lastTapLocal;
  bool _isManualEpisodeSelection =
      false; // Track if episode was manually selected
  bool _isAutoAdvancing = false; // Track if episode is auto-advancing
  bool _allowResumeForManualSelection =
      false; // Allow resuming for manual selections with progress
  Timer? _manualSelectionResetTimer; // Timer to reset manual selection flag
  bool _continuousShuffleEnabled = false;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pip.iosPipSession = PlayerPipSession.of(context);
    _dockLayout.refreshDockGeometry();
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
    if (CustomSeriesIdentity.isCustom(_effectiveContentImdbId)) {
      return _effectiveContentImdbId;
    }
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
  late final VpStartupCandidates _startupCandidates;
  late final VpStartupFailover _startupFailover;
  late final VpStartupGate _startupGate;
  late final VpSourceSwitch _sourceSwitch;
  late final VpSourcePlaylistSwitch _sourcePlaylistSwitch;
  late final VpDebrifyTvChannels _debrifyChannels;
  late final VpDebrifyTvBanner _debrifyBanner;
  late final VpStremioTvChannels _stremioTv;
  late final VpEpisodeFetch _episodeFetch;
  late final VpEpisodeGuide _episodeGuide;
  late final VpPlaybackEnded _playbackEnded;
  late final VpEpisodeNext _episodeNext;
  late final VpEpisodeAdjacent _episodeAdjacent;
  late final VpShuffle _shuffle;
  late final VpEpisodeTitleInfo _episodeTitleInfo;
  late final VpPlaylistLoad _playlistLoad;
  late final VpPlaylistEntryResolve _playlistEntryResolve;
  late final VpMediaWaits _mediaWaits;
  late final VpPikPakRetry _pikPakRetry;
  late final VpMetadataPreload _metadataPreload;
  late final VpAudioOutput _audioOutput;
  late final VpVideoOutputLease _videoOutputLease;
  late final VpTvosVideo _tvosVideo;
  late final VpDecoderProbe _decoderProbe;
  late final VpRendererFallback _rendererFallback;
  late final VpPlayerDefaults _playerDefaults;
  late final VpPlayerInstance _playerInstance;
  late final VpPlayerSubscriptions _playerSubscriptions;
  late final VpNetworkTuning _networkTuner;
  late final VpMediaOpen _mediaOpen;
  late final VpPlayerStartup _playerStartup;
  late final VpTransitionOverlay _transitionOverlay;
  late final VpDockLayout _dockLayout;
  late final VpControlsRuntime _controlsRuntime;
  late final VpTvRemote _tvRemote;
  late final VpPlayerGestures _gestures;

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
  String _tvStaticSubtext = '';

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
    _controlsVisible.addListener(_controlsRuntime.onControlsVisibilityChanged);

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
    _currentStremioTvChannelId = _stremioTv.findInitialStremioTvChannelId();
    _debrifyChannels.parseChannelDirectory();
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
    _playerInitializationFuture = _playerStartup.initializePlayer();

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

  /// Set once `dispose()` has run, so a claim still in flight at that moment
  /// gives the slot straight back instead of being stranded by the `!mounted`
  /// return at its call site — which would block every future trailer engine
  /// for the rest of the session.
  bool _screenDisposed = false;

  @override
  void didUpdateWidget(covariant VideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `hideOptions` / `hideSeekbar` arrive through the widget, not through an
    // inherited dependency, so didChangeDependencies never fires for them.
    _dockLayout.refreshDockGeometry();
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

  Map<String, String>? _activeHttpHeaders;

  bool get _hasStremioTvGuide =>
      _effectiveStremioTvChannels != null &&
      _effectiveStremioTvChannels!.isNotEmpty &&
      widget.stremioTvChannelSwitchProvider != null;

  bool get _hasStremioTvNext =>
      _currentStremioTvChannelId != null &&
      widget.stremioTvNextProvider != null;

  bool get _hasAnyNext =>
      _episodeAdjacent.hasNextEpisode() ||
      widget.requestMagicNext != null ||
      _hasStremioTvNext;

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
    _debrifyBanner.debrifyBannerTimer?.cancel();
    _iptvBanner.iptvZapHideTimer?.cancel();
    _iptvBanner.iptvZapTicker?.cancel();
    _tvScrubGeneration++; // invalidate any scrub still in flight
    _tvBarScope.dispose();
    _dockExtent.dispose();
    _tvPlayPauseFocus.dispose();
    _tvProgressFocus.dispose();
    _tvRootFocus.dispose();
    _controlsVisible.removeListener(
      _controlsRuntime.onControlsVisibilityChanged,
    );
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
    _audioOutput.releaseAudioEffectSession();
    _screenDisposed = true;
    final subtitleAutoSync = _subtitleSync.subtitleAutoSync;
    _subtitleSync.subtitleAutoSync = null;
    if (_playerCreated) {
      // The slot frees only once the native output has actually gone, not when
      // disposal is requested — the same rule the trailer engines follow.
      () async {
        await subtitleAutoSync?.dispose();
        await _player.dispose();
      }().whenComplete(_videoOutputLease.releaseVideoOutput);
    } else if (subtitleAutoSync != null) {
      unawaited(subtitleAutoSync.dispose());
      _videoOutputLease.releaseVideoOutput();
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
          _tvRemote.tvScrubCancel();
          return;
        }
        if (_anyPlayerOverlayOpen) {
          _controlsRuntime.closeTopPlayerOverlay();
          return;
        }
        if (_controlsVisible.value) _controlsRuntime.tvHideBar();
      },
      child: TvControlsScope(
        seek: (target) {
          _player.seek(target);
          _trakt.traktScrobbleSeek(target);
          _simkl.simklScrobbleSeek(target);
          _mdblist.mdblistScrobbleSeek(target);
          _controlsRuntime.scheduleAutoHide();
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
                ? _episodeTitleInfo.getCurrentEpisodeTitleInfo()
                : null;
            return TvControls(
              title: titleInfo?.title ?? '',
              titleIsClean: titleInfo?.fetched ?? false,
              subtitle: showIdentity
                  ? _episodeTitleInfo.getCurrentEpisodeSubtitle()
                  : null,
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
              onInteract: _controlsRuntime.scheduleAutoHide,
              scrubPreview: _tvScrubTarget,
              onPlayPause: _controlsRuntime.togglePlay,
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
                  : (_hasAnyNext ? _episodeNext.goToNextEpisode : null),
              onPrevious: _hasIptvPrevious
                  ? () => _iptvSwitch.switchToIptvChannel(_currentIptvIndex - 1)
                  : _zapRing.canZapIptvChannel
                  ? () => _zapLadder.zapIptvChannel(-1)
                  : (_episodeAdjacent.hasPreviousEpisode()
                        ? _episodeAdjacent.goToPreviousEpisode
                        : null),
              onNextChannel: widget.requestNextChannel != null
                  ? _debrifyChannels.goToNextChannel
                  : null,
              onShowPlaylist:
                  (_activePlaylist != null && _activePlaylist!.isNotEmpty) ||
                      _canFetchEpisodes
                  ? () => _episodeGuide.showPlaylistSheet(context)
                  : null,
              onRandom:
                  _effectiveIptvChannels == null &&
                      ((_activePlaylist?.isNotEmpty ?? false) ||
                          _canFetchEpisodes)
                  ? () => unawaited(_shuffle.showRandomPlaybackMenu())
                  : null,
              onShowSources: hasSources
                  ? _sourceSwitch.showSourceSheetOverlay
                  : null,
              onShowGuide: hasGuide
                  ? (_channelEntries.isNotEmpty &&
                            widget.requestChannelById != null
                        ? _debrifyChannels.showChannelGuideOverlay
                        : _stremioTv.showStremioTvGuideOverlay)
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
    final title = widget.showVideoTitle
        ? _episodeTitleInfo.getCurrentEpisodeTitle()
        : null;
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
                _debrifyChannels.hideChannelGuideOverlay();
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
                _sourceSwitch.hideSourceSheet();
                return KeyEventResult.handled;
              }
              // Let source sheet handle other keys
              return KeyEventResult.ignored;
            }

            // Stremio TV guide is open - handle its keys first
            if (_showStremioTvGuide) {
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _stremioTv.hideStremioTvGuide();
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
              final tvResult = _tvRemote.handleTvKey(key);
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
                _debrifyChannels.showChannelGuideOverlay();
                return KeyEventResult.handled;
              }
              if (_hasStremioTvGuide) {
                _stremioTv.showStremioTvGuideOverlay();
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
                _sourceSwitch.showSourceSheetOverlay();
                return KeyEventResult.handled;
              }
            }

            // Space -> Pause resume
            if (key == LogicalKeyboardKey.space) {
              _controlsRuntime.togglePlay();
              return KeyEventResult.handled;
            }

            // Up arrow -> Channel guide (if channels available) or Volume
            if (key == LogicalKeyboardKey.arrowUp) {
              // If channels are available, show channel guide
              if (_channelEntries.isNotEmpty &&
                  widget.requestChannelById != null) {
                _debrifyChannels.showChannelGuideOverlay();
                return KeyEventResult.handled;
              }
              // Stremio TV guide
              if (_hasStremioTvGuide) {
                _stremioTv.showStremioTvGuideOverlay();
                return KeyEventResult.handled;
              }

              // Otherwise, control volume
              _controlsVisible.value = true;
              _controlsRuntime.scheduleAutoHide();

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
              _controlsRuntime.scheduleAutoHide();

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
                _controlsRuntime.togglePlay();
              } else {
                _controlsRuntime.toggleControls();
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
              _controlsRuntime.togglePlay();
              return KeyEventResult.handled;
            }

            // N key for next episode (Mac)
            if (key == LogicalKeyboardKey.keyN) {
              if (_hasAnyNext) {
                _episodeNext.goToNextEpisode();
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
                _episodeNext.goToNextEpisode();
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.mediaSkipBackward) {
              if (_episodeAdjacent.hasPreviousEpisode()) {
                _episodeAdjacent.goToPreviousEpisode();
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
                _debrifyChannels.goToNextChannel();
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
                        _controlsRuntime.toggleControls();
                      }
                    },
                    onDoubleTapDown: _gestures.handleDoubleTap,
                    onLongPressStart: _display.onLongPressStart,
                    onLongPressEnd: _display.onLongPressEnd,
                    onPanStart: _gestures.onPanStart,
                    onPanUpdate: _gestures.onPanUpdate,
                    onPanEnd: _gestures.onPanEnd,
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
                                      ? _episodeTitleInfo
                                            .getCurrentEpisodeTitle()
                                      : '',
                                  subtitle:
                                      widget.showVideoTitle &&
                                          !widget.showChannelName
                                      ? _episodeTitleInfo
                                            .getCurrentEpisodeSubtitle()
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
                                  enhancedMetadata: _episodeTitleInfo
                                      .getEnhancedMetadata(),
                                  clock: _playbackUiClock,
                                  isPlaying: _isPlaying,
                                  isReady: isReady,
                                  onPlayPause: _controlsRuntime.togglePlay,
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
                                      _episodeGuide.showPlaylistSheet(context),
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
                                    _controlsRuntime.scheduleAutoHide();
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
                                      : (_hasAnyNext
                                            ? _episodeNext.goToNextEpisode
                                            : null),
                                  onNextChannel:
                                      widget.requestNextChannel != null
                                      ? _debrifyChannels.goToNextChannel
                                      : null,
                                  onPrevious: _hasIptvPrevious
                                      ? () => _iptvSwitch.switchToIptvChannel(
                                          _currentIptvIndex - 1,
                                        )
                                      : _zapRing.canZapIptvChannel
                                      ? () => _zapLadder.zapIptvChannel(-1)
                                      : (_episodeAdjacent.hasPreviousEpisode()
                                            ? _episodeAdjacent
                                                  .goToPreviousEpisode
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
                                      ? _debrifyChannels.showChannelGuideOverlay
                                      : _hasStremioTvGuide
                                      ? _stremioTv.showStremioTvGuideOverlay
                                      : null,
                                  hasPrevious:
                                      _episodeAdjacent.hasPreviousEpisode() ||
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
                                  onRandom: () => unawaited(
                                    _shuffle.showRandomPlaybackMenu(),
                                  ),
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
                                      ? _sourceSwitch.showSourceSheetOverlay
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
                      onChannelSelected: _debrifyChannels.goToChannelById,
                      onClose: _debrifyChannels.hideChannelGuideOverlay,
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
                          resolveSource: _sourceSwitch
                              .buildSourceSheetResolver(),
                          onSourceSelected: _sourceSwitch.handleSourceSelected,
                          onClose: _sourceSwitch.hideSourceSheet,
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
                      onChannelSwitched: _stremioTv.switchToStremioTvChannel,
                      onClose: _stremioTv.hideStremioTvGuide,
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
                onHover: (_) => _controlsRuntime.wakeControlsOnPointer(),
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

class _VpPlayerGesturesHostAdapter implements VpPlayerGesturesHost {
  _VpPlayerGesturesHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  Duration get duration => _s._duration;
  @override
  mk.Player get player => _s._player;
  @override
  Duration get position => _s._position;
  @override
  set ripple(DoubleTapRipple? v) => _s._ripple = v;
  @override
  ValueNotifier<SeekHudState?> get seekHud => _s._seekHud;
  @override
  ValueNotifier<VerticalHudState?> get verticalHud => _s._verticalHud;
  @override
  double dockBand(double legacy) => _s._dockBand(legacy);
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  void mdblistScrobbleSeek(Duration target) =>
      _s._mdblist.mdblistScrobbleSeek(target);
  @override
  void simklScrobbleSeek(Duration seekTarget) =>
      _s._simkl.simklScrobbleSeek(seekTarget);
  @override
  void traktScrobbleSeek(Duration seekTarget) =>
      _s._trakt.traktScrobbleSeek(seekTarget);
}

class _VpTvRemoteHostAdapter implements VpTvRemoteHost {
  _VpTvRemoteHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get anyPlayerOverlayOpen => _s._anyPlayerOverlayOpen;
  @override
  List<ChannelEntry> get channelEntries => _s._channelEntries;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  Duration get duration => _s._duration;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  bool get hasStremioTvGuide => _s._hasStremioTvGuide;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  bool get isReady => _s._isReady;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  mk.Player get player => _s._player;
  @override
  Duration get position => _s._position;
  @override
  bool get tvNoTimeline => _s._tvNoTimeline;
  @override
  FocusNode get tvPlayPauseFocus => _s._tvPlayPauseFocus;
  @override
  FocusNode get tvProgressFocus => _s._tvProgressFocus;
  @override
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  Duration? get tvScrubTarget => _s._tvScrubTarget;
  @override
  set tvScrubTarget(Duration? v) => _s._tvScrubTarget = v;
  @override
  void scheduleAutoHide() => _s._controlsRuntime.scheduleAutoHide();
  @override
  void tvShowBar() => _s._controlsRuntime.tvShowBar();
  @override
  void tvHideBar() => _s._controlsRuntime.tvHideBar();
  @override
  void togglePlay() => _s._controlsRuntime.togglePlay();
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  Future<Map<String, dynamic>?> Function(String channelId)?
  get requestChannelById => _s.widget.requestChannelById;
  @override
  void showChannelGuideOverlay() =>
      _s._debrifyChannels.showChannelGuideOverlay();
  @override
  void showIptvChannelSheetOverlay() =>
      _s._iptvGuide.showIptvChannelSheetOverlay();
  @override
  void mdblistScrobbleSeek(Duration target) =>
      _s._mdblist.mdblistScrobbleSeek(target);
  @override
  void simklScrobbleSeek(Duration seekTarget) =>
      _s._simkl.simklScrobbleSeek(seekTarget);
  @override
  SkipSegment? get activeSkipSegment => _s._skip.activeSkipSegment;
  @override
  void skipActiveSegment() => _s._skip.skipActiveSegment();
  @override
  void showStremioTvGuideOverlay() => _s._stremioTv.showStremioTvGuideOverlay();
  @override
  void traktScrobbleSeek(Duration seekTarget) =>
      _s._trakt.traktScrobbleSeek(seekTarget);
  @override
  void zapIptvChannel(int delta) => _s._zapLadder.zapIptvChannel(delta);
  @override
  bool get canZapIptvChannel => _s._zapRing.canZapIptvChannel;
}

class _VpControlsRuntimeHostAdapter implements VpControlsRuntimeHost {
  _VpControlsRuntimeHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set activeMediaShouldPlay(bool v) => _s._activeMediaShouldPlay = v;
  @override
  set activeMediaUserPaused(bool v) => _s._activeMediaUserPaused = v;
  @override
  bool get anyPlayerOverlayOpen => _s._anyPlayerOverlayOpen;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  bool get engineFlagOn => _s._engineFlagOn;
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  set hideTimer(Timer? v) => _s._hideTimer = v;
  @override
  GlobalKey<IptvChannelSheetState> get iptvSheetKey => _s._iptvSheetKey;
  @override
  bool get isAnyOverlayOpen => _s._isAnyOverlayOpen;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  bool get isReady => _s._isReady;
  @override
  mk.Player get player => _s._player;
  @override
  GlobalKey<PlayerMenuPanelState> get playerMenuKey => _s._playerMenuKey;
  @override
  Duration get position => _s._position;
  @override
  bool get showChannelGuide => _s._showChannelGuide;
  @override
  bool get showIptvChannelSheet => _s._showIptvChannelSheet;
  @override
  bool get showPlayerMenu => _s._showPlayerMenu;
  @override
  bool get showSourceSheet => _s._showSourceSheet;
  @override
  bool get showStremioTvGuide => _s._showStremioTvGuide;
  @override
  bool get showSyncOverlay => _s._showSyncOverlay;
  @override
  set sleepStopLatched(bool v) => _s._sleepStopLatched = v;
  @override
  FocusScopeNode get tvBarScope => _s._tvBarScope;
  @override
  FocusNode get tvPlayPauseFocus => _s._tvPlayPauseFocus;
  @override
  FocusNode get tvRootFocus => _s._tvRootFocus;
  @override
  Duration? get tvScrubTarget => _s._tvScrubTarget;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void hideDebrifyBanner({bool immediate = false}) =>
      _s._debrifyBanner.hideDebrifyBanner(immediate: immediate);
  @override
  void syncPlaybackClockVisibility() =>
      _s._debrifyBanner.syncPlaybackClockVisibility();
  @override
  void hideChannelGuideOverlay() =>
      _s._debrifyChannels.hideChannelGuideOverlay();
  @override
  void hideIptvZapBanner({bool immediate = false}) =>
      _s._iptvBanner.hideIptvZapBanner(immediate: immediate);
  @override
  void syncIptvBannerTicker() => _s._iptvBanner.syncIptvBannerTicker();
  @override
  void hideIptvChannelSheet() => _s._iptvGuide.hideIptvChannelSheet();
  @override
  void hidePlayerMenu() => _s._menu.hidePlayerMenu();
  @override
  Future<void> refreshEngineRecordingState() =>
      _s._recording.refreshEngineRecordingState();
  @override
  Future<void> saveResume({
    bool debounced = false,
    Duration? positionOverride,
  }) => _s._resumeSave.saveResume(
    debounced: debounced,
    positionOverride: positionOverride,
  );
  @override
  void hideSourceSheet() => _s._sourceSwitch.hideSourceSheet();
  @override
  void hideStremioTvGuide() => _s._stremioTv.hideStremioTvGuide();
  @override
  void hideSyncOverlay() => _s._subtitleSync.hideSyncOverlay();
}

class _VpDockLayoutHostAdapter implements VpDockLayoutHost {
  _VpDockLayoutHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  ValueNotifier<double> get dockExtent => _s._dockExtent;
  @override
  int get dockGeometryGeneration => _s._dockGeometryGeneration;
  @override
  set dockGeometryGeneration(int v) => _s._dockGeometryGeneration = v;
  @override
  set dockPalette(PlayerDockPalette v) => _s._dockPalette = v;
  @override
  PlayerDockSize get dockSize => _s._dockSize;
  @override
  set dockSize(PlayerDockSize v) => _s._dockSize = v;
  @override
  PlayerDockStyle get dockStyle => _s._dockStyle;
  @override
  set dockStyle(PlayerDockStyle v) => _s._dockStyle = v;
  @override
  int get infoPanelGeneration => _s._infoPanelGeneration;
  @override
  set infoPanelGeneration(int v) => _s._infoPanelGeneration = v;
  @override
  set infoPanelHeight(double v) => _s._infoPanelHeight = v;
  @override
  set lastInfoPanelSignature(String v) => _s._lastInfoPanelSignature = v;
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get hideOptions => _s.widget.hideOptions;
  @override
  bool get hideSeekbar => _s.widget.hideSeekbar;
}

class _VpTransitionOverlayHostAdapter implements VpTransitionOverlayHost {
  _VpTransitionOverlayHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Timer? get bufferingDebounceTimer => _s._bufferingDebounceTimer;
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  ValueNotifier<bool> get showBufferingIndicator => _s._showBufferingIndicator;
  @override
  set transitionPhase(int v) => _s._transitionPhase = v;
  @override
  Timer? get transitionPhaseTimer => _s._transitionPhaseTimer;
  @override
  set transitionRunning(bool v) => _s._transitionRunning = v;
  @override
  Timer? get transitionStopTimer => _s._transitionStopTimer;
  @override
  set tvStaticMessage(String v) => _s._tvStaticMessage = v;
  @override
  set tvStaticSubtext(String v) => _s._tvStaticSubtext = v;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
}

class _VpPlayerStartupHostAdapter implements VpPlayerStartupHost {
  _VpPlayerStartupHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  set activeHttpHeaders(Map<String, String>? v) => _s._activeHttpHeaders = v;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  AndroidVideoRendererMode get androidVideoRendererMode =>
      _s._androidVideoRendererMode;
  @override
  set androidVideoRendererMode(AndroidVideoRendererMode v) =>
      _s._androidVideoRendererMode = v;
  @override
  set autosaveTimer(Timer? v) => _s._autosaveTimer = v;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  set currentIndex(int v) => _s._currentIndex = v;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  Duration get duration => _s._duration;
  @override
  set dynamicTitle(String v) => _s._dynamicTitle = v;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  List<Map<String, dynamic>>? get effectiveStremioTvChannels =>
      _s._effectiveStremioTvChannels;
  @override
  bool get engineFlagOn => _s._engineFlagOn;
  @override
  set engineFlagOn(bool v) => _s._engineFlagOn = v;
  @override
  Future<void>? get episodeMetadataReady => _s._episodeMetadataReady;
  @override
  set episodeMetadataReady(Future<void>? v) => _s._episodeMetadataReady = v;
  @override
  IptvTuneDiagnostics get iptvDiag => _s._iptvDiag;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  mk.Player get player => _s._player;
  @override
  int get playerInstanceGeneration => _s._playerInstanceGeneration;
  @override
  set recordingSupported(bool v) => _s._recordingSupported = v;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;
  @override
  ChannelStartupWatch? get stremioTvStartupWatch => _s._stremioTvStartupWatch;
  @override
  Future<void> loadDockPrefs() => _s._dockLayout.loadDockPrefs();
  @override
  Duration? randomStartOffset(Duration duration) =>
      _s._randomStartOffset(duration);
  @override
  Duration? percentStartOffset(Duration duration) =>
      _s._percentStartOffset(duration);
  @override
  void scheduleAutoHide() => _s._controlsRuntime.scheduleAutoHide();
  @override
  Future<void> loadPlayerDefaults() => _s._playerDefaults.loadPlayerDefaults();
  @override
  void createPlayerInstance(AndroidVideoRendererMode rendererMode) =>
      _s._playerInstance.createPlayerInstance(rendererMode);
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
  }) => _s._mediaOpen.openMedia(
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
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  String? get audioUrl => _s.widget.audioUrl;
  @override
  int? get contentEpisode => _s.widget.contentEpisode;
  @override
  int? get contentSeason => _s.widget.contentSeason;
  @override
  bool get disableAutoResume => _s.widget.disableAutoResume;
  @override
  Map<String, String>? get httpHeaders => _s.widget.httpHeaders;
  @override
  int? get iptvStartIndex => _s.widget.iptvStartIndex;
  @override
  Future<Map<String, String>?> Function()? get requestMagicNext =>
      _s.widget.requestMagicNext;
  @override
  double? get startAtPercent => _s.widget.startAtPercent;
  @override
  bool get startFromRandom => _s.widget.startFromRandom;
  @override
  int? get startIndex => _s.widget.startIndex;
  @override
  String get title => _s.widget.title;
  @override
  String get videoUrl => _s.widget.videoUrl;
  @override
  bool get isAndroid => VpS2Hooks.isAndroid;
  @override
  Future<void> attachAudioEffectSession() =>
      _s._audioOutput.attachAudioEffectSession();
  @override
  Future<void> configurePlayerAudio(mk.Player player) =>
      _s._audioOutput.configurePlayerAudio(player);
  @override
  Future<void> setExternalAudioTrack(String audioUrl) =>
      _s._audioOutput.setExternalAudioTrack(audioUrl);
  @override
  List<int> getMainGroupIndices(List<PlaylistEntry> entries) =>
      _s._episodeAdjacent.getMainGroupIndices(entries);
  @override
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  Future<void> preloadEpisodeInfo() => _s._metadataPreload.preloadEpisodeInfo();
  @override
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  }) => _s._pikPakRetry.playPikPakVideoWithRetry(
    videoUrl,
    overrideProvider: overrideProvider,
    overridePikPakFileId: overridePikPakFileId,
    isDebrifyTV: isDebrifyTV,
    showFailure: showFailure,
    request: request,
  );
  @override
  Future<String> resolvePlaylistEntryUrl(int index) =>
      _s._playlistEntryResolve.resolvePlaylistEntryUrl(index);
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  Future<void> refreshEngineRecordingState() =>
      _s._recording.refreshEngineRecordingState();
  @override
  String resumeIdForEntry(PlaylistEntry entry) =>
      _s._resumeKeys.resumeIdForEntry(entry);
  @override
  Future<void> maybeRestoreResume({
    bool preferLocalResume = false,
    bool verifyLanding = false,
  }) => _s._resumeRestore.maybeRestoreResume(
    preferLocalResume: preferLocalResume,
    verifyLanding: verifyLanding,
  );
  @override
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false}) =>
      _s._resumeRestore.seekForResume(targetMs, verifyLanding: verifyLanding);
  @override
  Future<void> saveResume({
    bool debounced = false,
    Duration? positionOverride,
  }) => _s._resumeSave.saveResume(
    debounced: debounced,
    positionOverride: positionOverride,
  );
  @override
  Future<void> commitValidatedStremioSource(Torrent? source) =>
      _s._startupCandidates.commitValidatedStremioSource(source);
  @override
  Future<bool> openInitialVodWithFailover(
    String initialUrl, {
    Map<String, String>? httpHeaders,
    bool initialAttemptAlreadyFailed = false,
  }) => _s._startupFailover.openInitialVodWithFailover(
    initialUrl,
    httpHeaders: httpHeaders,
    initialAttemptAlreadyFailed: initialAttemptAlreadyFailed,
  );
  @override
  Future<void> reportStartupFailure({bool Function()? isCurrent}) =>
      _s._startupGate.reportStartupFailure(isCurrent: isCurrent);
  @override
  void resumeTrackingAfterValidationGate() =>
      _s._startupGate.resumeTrackingAfterValidationGate();
  @override
  void setStartupGateActive(bool active) =>
      _s._startupGate.setStartupGateActive(active);
  @override
  void watchStremioTvStartup(String url) =>
      _s._startupGate.watchStremioTvStartup(url);
  @override
  void installSubtitleAutoSyncForPlayer(mk.Player player) =>
      _s._subtitleSync.installSubtitleAutoSyncForPlayer(player);
  @override
  Future<void> restoreTrackPreferences() =>
      _s._trackPreferences.restoreTrackPreferences();
  @override
  Future<void> claimVideoOutput() => _s._videoOutputLease.claimVideoOutput();
}

class _VpMediaOpenHostAdapter implements VpMediaOpenHost {
  _VpMediaOpenHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set activeMediaShouldPlay(bool v) => _s._activeMediaShouldPlay = v;
  @override
  set activeMediaUserPaused(bool v) => _s._activeMediaUserPaused = v;
  @override
  set activeOpenedMedia(mk.Media? v) => _s._activeOpenedMedia = v;
  @override
  SkipSegmentUiController get activeSkipSegmentUi => _s._activeSkipSegmentUi;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  int get decoderProbeGeneration => _s._decoderProbeGeneration;
  @override
  set decoderProbeGeneration(int v) => _s._decoderProbeGeneration = v;
  @override
  set decoderProbeParams(mk.VideoParams? v) => _s._decoderProbeParams = v;
  @override
  Timer? get decoderProbeTimer => _s._decoderProbeTimer;
  @override
  set decoderProbeTimer(Timer? v) => _s._decoderProbeTimer = v;
  @override
  int get decoderProbeToken => _s._decoderProbeToken;
  @override
  set decoderProbeToken(int v) => _s._decoderProbeToken = v;
  @override
  String? get effectiveContentTitle => _s._effectiveContentTitle;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  bool get hasSubtitlePolicy => _s._hasSubtitlePolicy;
  @override
  bool get isPipActive => _s._isPipActive;
  @override
  set lastDecoderDiagnosticSignature(String? v) =>
      _s._lastDecoderDiagnosticSignature = v;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  set openedWatchSource(Torrent? v) => _s._openedWatchSource = v;
  @override
  PlaybackUiClockController get playbackUiClock => _s._playbackUiClock;
  @override
  mk.Player get player => _s._player;
  @override
  int get rendererStartupGuardToken => _s._rendererStartupGuardToken;
  @override
  set rendererStartupGuardToken(int v) => _s._rendererStartupGuardToken = v;
  @override
  set rendererStartupValidationGeneration(int v) =>
      _s._rendererStartupValidationGeneration = v;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  set resumeVerifyEpoch(int v) => _s._resumeVerifyEpoch = v;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  MediaServerWatchController get serverWatch => _s._serverWatch;
  @override
  DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;
  @override
  ChannelStartupWatch? get stremioTvStartupWatch => _s._stremioTvStartupWatch;
  @override
  set stremioTvStartupWatch(ChannelStartupWatch? v) =>
      _s._stremioTvStartupWatch = v;
  @override
  TvosDecodeRemedy? get tvosDecodeRemedy => _s._tvosDecodeRemedy;
  @override
  int get watchOpenEpoch => _s._watchOpenEpoch;
  @override
  set watchOpenEpoch(int v) => _s._watchOpenEpoch = v;
  @override
  Future<void> applyNetworkTuning(
    mk.NativePlayer platform,
    NetworkTuning tuning, {
    required bool liveStream,
    required int generation,
  }) => _s._networkTuner.applyNetworkTuning(
    platform,
    tuning,
    liveStream: liveStream,
    generation: generation,
  );
  @override
  bool get mounted => _s.mounted;
  @override
  bool get isIOS => VpS2Hooks.isIOS;
  @override
  bool get iosPipStarting => _s._pip.iosPipStarting;
  @override
  void observeServerWatch({bool completed = false}) =>
      _s._resumeSave.observeServerWatch(completed: completed);
  @override
  void resetTvosDisplayMatchForMediaBoundary() =>
      _s._tvosVideo.resetTvosDisplayMatchForMediaBoundary();
  @override
  Object get visibilityOwner => _s;
}

class _VpNetworkTuningHostAdapter implements VpNetworkTuningHost {
  _VpNetworkTuningHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  int get decoderProbeGeneration => _s._decoderProbeGeneration;
}

class _VpPlayerSubscriptionsHostAdapter implements VpPlayerSubscriptionsHost {
  _VpPlayerSubscriptionsHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt =>
      _s._activeSubtitleApplyAttempt;
  @override
  Timer? get bufferingDebounceTimer => _s._bufferingDebounceTimer;
  @override
  set bufferingDebounceTimer(Timer? v) => _s._bufferingDebounceTimer = v;
  @override
  StreamSubscription? get bufferingSub => _s._bufferingSub;
  @override
  set bufferingSub(StreamSubscription? v) => _s._bufferingSub = v;
  @override
  StreamSubscription? get completedSub => _s._completedSub;
  @override
  set completedSub(StreamSubscription? v) => _s._completedSub = v;
  @override
  int get decoderProbeGeneration => _s._decoderProbeGeneration;
  @override
  StreamSubscription? get durSub => _s._durSub;
  @override
  set durSub(StreamSubscription? v) => _s._durSub = v;
  @override
  Duration get duration => _s._duration;
  @override
  set duration(Duration v) => _s._duration = v;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  bool get hasSubtitlePolicy => _s._hasSubtitlePolicy;
  @override
  IptvTuneDiagnostics get iptvDiag => _s._iptvDiag;
  @override
  StreamSubscription? get iptvErrorSub => _s._iptvErrorSub;
  @override
  set iptvErrorSub(StreamSubscription? v) => _s._iptvErrorSub = v;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  bool get isPikPakRetrying => _s._isPikPakRetrying;
  @override
  bool get isPipActive => _s._isPipActive;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  set isPlaying(bool v) => _s._isPlaying = v;
  @override
  bool get isReady => _s._isReady;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  StreamSubscription? get paramsSub => _s._paramsSub;
  @override
  set paramsSub(StreamSubscription? v) => _s._paramsSub = v;
  @override
  bool get pausedByLifecycle => _s._pausedByLifecycle;
  @override
  StreamSubscription? get playSub => _s._playSub;
  @override
  set playSub(StreamSubscription? v) => _s._playSub = v;
  @override
  PlaybackUiClockController get playbackUiClock => _s._playbackUiClock;
  @override
  int get playerInstanceGeneration => _s._playerInstanceGeneration;
  @override
  StreamSubscription? get posSub => _s._posSub;
  @override
  set posSub(StreamSubscription? v) => _s._posSub = v;
  @override
  Duration get position => _s._position;
  @override
  set position(Duration v) => _s._position = v;
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  StreamSubscription? get rendererStartupErrorSub =>
      _s._rendererStartupErrorSub;
  @override
  set rendererStartupErrorSub(StreamSubscription? v) =>
      _s._rendererStartupErrorSub = v;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  ValueNotifier<bool> get showBufferingIndicator => _s._showBufferingIndicator;
  @override
  DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;
  @override
  StreamSubscription<mk.PlayerLog>? get subtitleDiagnosticLogSub =>
      _s._subtitleDiagnosticLogSub;
  @override
  set subtitleDiagnosticLogSub(StreamSubscription<mk.PlayerLog>? v) =>
      _s._subtitleDiagnosticLogSub = v;
  @override
  StreamSubscription? get trackSub => _s._trackSub;
  @override
  set trackSub(StreamSubscription? v) => _s._trackSub = v;
  @override
  set transitionPhase(int v) => _s._transitionPhase = v;
  @override
  set transitionPhase2Started(DateTime? v) => _s._transitionPhase2Started = v;
  @override
  Timer? get transitionPhaseTimer => _s._transitionPhaseTimer;
  @override
  set transitionPhaseTimer(Timer? v) => _s._transitionPhaseTimer = v;
  @override
  bool get transitionRunning => _s._transitionRunning;
  @override
  set transitionRunning(bool v) => _s._transitionRunning = v;
  @override
  Timer? get transitionStopTimer => _s._transitionStopTimer;
  @override
  set transitionStopTimer(Timer? v) => _s._transitionStopTimer = v;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get isIOS => VpS2Hooks.isIOS;
  @override
  void checkAndApplyLocalCompletion() =>
      _s._completion.checkAndApplyLocalCompletion();
  @override
  void handleDecoderProbeParams(mk.VideoParams params) =>
      _s._decoderProbe.handleDecoderProbeParams(params);
  @override
  void prepareNextDirectEpisode() =>
      _s._episodeFetch.prepareNextDirectEpisode();
  @override
  void noteLiveChannelPlaying() => _s._iptvMemory.noteLiveChannelPlaying();
  @override
  void onIptvStreamError(String error) =>
      _s._iptvSources.onIptvStreamError(error);
  @override
  void mdblistPause() => _s._mdblist.mdblistPause();
  @override
  void mdblistPlay() => _s._mdblist.mdblistPlay();
  @override
  void updateMdblistPosition() => _s._mdblist.updateMdblistPosition();
  @override
  int get lastIosPipPositionSecond => _s._pip.lastIosPipPositionSecond;
  @override
  set lastIosPipPositionSecond(int v) => _s._pip.lastIosPipPositionSecond = v;
  @override
  void pushPipState() => _s._pip.pushPipState();
  @override
  void syncWakelock(bool playing) => _s._pip.syncWakelock(playing);
  @override
  Future<void> onPlaybackEnded() => _s._playbackEnded.onPlaybackEnded();
  @override
  Future<void> fallbackExplicitRendererToAutomatic({
    required int instanceGeneration,
    required int mediaGeneration,
    required String reason,
  }) => _s._rendererFallback.fallbackExplicitRendererToAutomatic(
    instanceGeneration: instanceGeneration,
    mediaGeneration: mediaGeneration,
    reason: reason,
  );
  @override
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false}) =>
      _s._resumeRestore.seekForResume(targetMs, verifyLanding: verifyLanding);
  @override
  void observeServerWatch({bool completed = false}) =>
      _s._resumeSave.observeServerWatch(completed: completed);
  @override
  String? get simklLastScrobbleAction => _s._simkl.simklLastScrobbleAction;
  @override
  set simklLastScrobbleAction(String? v) =>
      _s._simkl.simklLastScrobbleAction = v;
  @override
  void simklScrobble(String action) => _s._simkl.simklScrobble(action);
  @override
  bool get simklScrobbleEnabled => _s._simkl.simklScrobbleEnabled;
  @override
  void startSimklHeartbeat() => _s._simkl.startSimklHeartbeat();
  @override
  void stopSimklHeartbeat() => _s._simkl.stopSimklHeartbeat();
  @override
  set skipSegmentsMediaReady(bool v) => _s._skip.skipSegmentsMediaReady = v;
  @override
  void syncActiveSkipSegmentUi() => _s._skip.syncActiveSkipSegmentUi();
  @override
  void syncSkipSegmentsForCurrentContent() =>
      _s._skip.syncSkipSegmentsForCurrentContent();
  @override
  Future<void> handleSubtitleApplyFailure(
    VpSubtitleApplyAttempt attempt,
    String reason,
  ) => _s._subtitleApply.handleSubtitleApplyFailure(attempt, reason);
  @override
  Future<void> refreshSubtitleAudioPolicy({bool reselect = true}) =>
      _s._subtitleLanguage.refreshSubtitleAudioPolicy(reselect: reselect);
  @override
  MediaKitSubtitleAutoSync? get subtitleAutoSync =>
      _s._subtitleSync.subtitleAutoSync;
  @override
  bool get subtitleAutoSyncEnabled => _s._subtitleSync.subtitleAutoSyncEnabled;
  @override
  set subtitleAutoSyncEnabled(bool v) =>
      _s._subtitleSync.subtitleAutoSyncEnabled = v;
  @override
  void startTraktHeartbeat() => _s._trakt.startTraktHeartbeat();
  @override
  void stopTraktHeartbeat() => _s._trakt.stopTraktHeartbeat();
  @override
  String? get traktLastScrobbleAction => _s._trakt.traktLastScrobbleAction;
  @override
  void traktScrobble(String action) => _s._trakt.traktScrobble(action);
  @override
  Object get visibilityOwner => _s;
}

class _VpPlayerInstanceHostAdapter implements VpPlayerInstanceHost {
  _VpPlayerInstanceHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get anyPlayerOverlayOpen => _s._anyPlayerOverlayOpen;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  set isReady(bool v) => _s._isReady = v;
  @override
  set player(mk.Player v) => _s._player = v;
  @override
  set playerCreated(bool v) => _s._playerCreated = v;
  @override
  int get playerInstanceGeneration => _s._playerInstanceGeneration;
  @override
  set playerInstanceGeneration(int v) => _s._playerInstanceGeneration = v;
  @override
  FocusScopeNode get tvBarScope => _s._tvBarScope;
  @override
  FocusNode get tvPlayPauseFocus => _s._tvPlayPauseFocus;
  @override
  bool get tvosForceSoftwareDecode => _s._tvosForceSoftwareDecode;
  @override
  set videoController(mkv.VideoController v) => _s._videoController = v;
  @override
  void bindPlayerInstanceSubscriptions(
    int instanceGeneration,
    mk.Player player,
  ) => _s._playerSubscriptions.bindPlayerInstanceSubscriptions(
    instanceGeneration,
    player,
  );
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) =>
      VideoPlayerScreenTestHooks._createPlayer(configuration: configuration);
  @override
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) => VideoPlayerScreenTestHooks._createVideoController(
    player,
    configuration: configuration,
  );
  @override
  void raiseDebrifyBanner() => _s._debrifyBanner.raiseDebrifyBanner();
  @override
  Future<void> installDecoderObservers(
    int instanceGeneration,
    mk.Player player,
  ) => _s._decoderProbe.installDecoderObservers(instanceGeneration, player);
  @override
  Future<void> applyAspectVideoZoom() => _s._display.applyAspectVideoZoom();
  @override
  void prepareIptvBannerData(IptvChannel channel) =>
      _s._iptvBanner.prepareIptvBannerData(channel);
  @override
  void raiseIptvZapBanner() => _s._iptvBanner.raiseIptvZapBanner();
  @override
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories}) =>
      _s._iptvGuide.anchorIptvGuideCategory(channel, categories: categories);
  @override
  void armPipAutoEnter() => _s._pip.armPipAutoEnter();
  @override
  void installTvosDecodeRemedy(mk.Player player) =>
      _s._tvosVideo.installTvosDecodeRemedy(player);
  @override
  void ensureIptvZapPagingArmed() => _s._zapRing.ensureIptvZapPagingArmed();
}

class _VpPlayerDefaultsHostAdapter implements VpPlayerDefaultsHost {
  _VpPlayerDefaultsHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set appleMultichannelEnabled(bool v) => _s._appleMultichannelEnabled = v;
  @override
  set audioPassthroughEnabled(bool v) => _s._audioPassthroughEnabled = v;
  @override
  ContentDisplayMatchMode get contentDisplayMatchMode =>
      _s._contentDisplayMatchMode;
  @override
  set contentDisplayMatchMode(ContentDisplayMatchMode v) =>
      _s._contentDisplayMatchMode = v;
  @override
  PlayerGuideStyle get playerGuideStyle => _s._playerGuideStyle;
  @override
  set playerGuideStyle(PlayerGuideStyle v) => _s._playerGuideStyle = v;
  @override
  set playerGuideTokens(IptvStyleTokens? v) => _s._playerGuideTokens = v;
  @override
  set subtitleForcedOnly(bool v) => _s._subtitleForcedOnly = v;
  @override
  set subtitleOnlyForeignAudio(bool v) => _s._subtitleOnlyForeignAudio = v;
  @override
  set subtitlePreferredAudio(String? v) => _s._subtitlePreferredAudio = v;
  @override
  set systemAudioEffectsEnabled(bool v) => _s._systemAudioEffectsEnabled = v;
  @override
  set tvosForceSoftwareDecode(bool v) => _s._tvosForceSoftwareDecode = v;
  @override
  set tvosForceStereoAudio(bool v) => _s._tvosForceStereoAudio = v;
  @override
  set tvosLegacyAudioOutput(bool v) => _s._tvosLegacyAudioOutput = v;
  @override
  set tvosRouteOutputChannels(int v) => _s._tvosRouteOutputChannels = v;
  @override
  MethodChannel get tvReleaseLogChannel =>
      _VideoPlayerScreenState._tvReleaseLogChannel;
  @override
  AspectMode get aspectMode => _s._display.aspectMode;
  @override
  set aspectMode(AspectMode v) => _s._display.aspectMode = v;
  @override
  bool get subtitleAutoSyncEnabled => _s._subtitleSync.subtitleAutoSyncEnabled;
  @override
  set subtitleAutoSyncEnabled(bool v) =>
      _s._subtitleSync.subtitleAutoSyncEnabled = v;
}

class _VpRendererFallbackHostAdapter implements VpRendererFallbackHost {
  _VpRendererFallbackHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set activeExternalSubtitlePath(String? v) =>
      _s._activeExternalSubtitlePath = v;
  @override
  bool get activeMediaShouldPlay => _s._activeMediaShouldPlay;
  @override
  bool get activeMediaUserPaused => _s._activeMediaUserPaused;
  @override
  mk.Media? get activeOpenedMedia => _s._activeOpenedMedia;
  @override
  AndroidVideoRendererMode get androidVideoRendererMode =>
      _s._androidVideoRendererMode;
  @override
  set androidVideoRendererMode(AndroidVideoRendererMode v) =>
      _s._androidVideoRendererMode = v;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get decoderProbeGeneration => _s._decoderProbeGeneration;
  @override
  set duration(Duration v) => _s._duration = v;
  @override
  bool get iptvErrorsMuted => _s._iptvErrorsMuted;
  @override
  set isPlaying(bool v) => _s._isPlaying = v;
  @override
  set isReady(bool v) => _s._isReady = v;
  @override
  bool get isRecording => _s._isRecording;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  bool get pausedByLifecycle => _s._pausedByLifecycle;
  @override
  mk.Player get player => _s._player;
  @override
  set playerCreated(bool v) => _s._playerCreated = v;
  @override
  int get playerInstanceGeneration => _s._playerInstanceGeneration;
  @override
  set playerInstanceGeneration(int v) => _s._playerInstanceGeneration = v;
  @override
  Duration get position => _s._position;
  @override
  set position(Duration v) => _s._position = v;
  @override
  bool get rendererFallbackInProgress => _s._rendererFallbackInProgress;
  @override
  set rendererFallbackInProgress(bool v) => _s._rendererFallbackInProgress = v;
  @override
  int get rendererStartupGuardToken => _s._rendererStartupGuardToken;
  @override
  set rendererStartupGuardToken(int v) => _s._rendererStartupGuardToken = v;
  @override
  int get rendererStartupValidationGeneration =>
      _s._rendererStartupValidationGeneration;
  @override
  set rendererStartupValidationGeneration(int v) =>
      _s._rendererStartupValidationGeneration = v;
  @override
  bool get rendererValidatedForSession => _s._rendererValidatedForSession;
  @override
  set rendererValidatedForSession(bool v) =>
      _s._rendererValidatedForSession = v;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  ValueNotifier<bool> get showBufferingIndicator => _s._showBufferingIndicator;
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;
  @override
  ChannelStartupWatch? get stremioTvStartupWatch => _s._stremioTvStartupWatch;
  @override
  void createPlayerInstance(AndroidVideoRendererMode rendererMode) =>
      _s._playerInstance.createPlayerInstance(rendererMode);
  @override
  Future<void> cancelPlayerInstanceSubscriptions() =>
      _s._playerSubscriptions.cancelPlayerInstanceSubscriptions();
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
  }) => _s._mediaOpen.openMedia(
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
  Future<void> attachAudioEffectSession() =>
      _s._audioOutput.attachAudioEffectSession();
  @override
  Future<void> claimVideoOutput() => _s._videoOutputLease.claimVideoOutput();
  @override
  Future<void> configurePlayerAudio(mk.Player player) =>
      _s._audioOutput.configurePlayerAudio(player);
  @override
  void releaseAudioEffectSession() =>
      _s._audioOutput.releaseAudioEffectSession();
  @override
  void releasePlayerDiagnostic(String fields) =>
      _s._decoderProbe.releasePlayerDiagnostic(fields);
  @override
  Future<void> setExternalAudioTrack(String audioUrl) =>
      _s._audioOutput.setExternalAudioTrack(audioUrl);
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  String? get audioUrl => _s.widget.audioUrl;
  @override
  bool get isAndroid => VpS2Hooks.isAndroid;
  @override
  bool get isAndroidRendererValidation => VpS2Hooks.isAndroidRendererValidation;
  @override
  Future<void> disposeSubtitleAutoSync() =>
      _s._subtitleSync.disposeSubtitleAutoSync();
  @override
  void installSubtitleAutoSyncForPlayer(mk.Player player) =>
      _s._subtitleSync.installSubtitleAutoSyncForPlayer(player);
  @override
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false}) =>
      _s._resumeRestore.seekForResume(targetMs, verifyLanding: verifyLanding);
  @override
  Future<void> restoreTrackPreferences() =>
      _s._trackPreferences.restoreTrackPreferences();
  @override
  void watchStremioTvStartup(String url) =>
      _s._startupGate.watchStremioTvStartup(url);
  @override
  Future<void> reportStartupFailure({bool Function()? isCurrent}) =>
      _s._startupGate.reportStartupFailure(isCurrent: isCurrent);
}

class _VpDecoderProbeHostAdapter implements VpDecoderProbeHost {
  _VpDecoderProbeHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  AndroidVideoRendererMode get androidVideoRendererMode =>
      _s._androidVideoRendererMode;
  @override
  int get decoderProbeGeneration => _s._decoderProbeGeneration;
  @override
  mk.VideoParams? get decoderProbeParams => _s._decoderProbeParams;
  @override
  set decoderProbeParams(mk.VideoParams? v) => _s._decoderProbeParams = v;
  @override
  Timer? get decoderProbeTimer => _s._decoderProbeTimer;
  @override
  set decoderProbeTimer(Timer? v) => _s._decoderProbeTimer = v;
  @override
  int get decoderProbeToken => _s._decoderProbeToken;
  @override
  set decoderProbeToken(int v) => _s._decoderProbeToken = v;
  @override
  String? get lastDecoderDiagnosticSignature =>
      _s._lastDecoderDiagnosticSignature;
  @override
  set lastDecoderDiagnosticSignature(String? v) =>
      _s._lastDecoderDiagnosticSignature = v;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  mk.Player get player => _s._player;
  @override
  int get playerInstanceGeneration => _s._playerInstanceGeneration;
  @override
  int get rendererStartupGuardToken => _s._rendererStartupGuardToken;
  @override
  set rendererStartupGuardToken(int v) => _s._rendererStartupGuardToken = v;
  @override
  set rendererStartupValidationGeneration(int v) =>
      _s._rendererStartupValidationGeneration = v;
  @override
  TvosDecodeRemedy? get tvosDecodeRemedy => _s._tvosDecodeRemedy;
  @override
  MethodChannel get tvReleaseLogChannel =>
      _VideoPlayerScreenState._tvReleaseLogChannel;
  @override
  void resetTvosDisplayMatchForMediaBoundary() =>
      _s._tvosVideo.resetTvosDisplayMatchForMediaBoundary();
  @override
  void scheduleTvosDisplayMatch(mk.VideoParams params) =>
      _s._tvosVideo.scheduleTvosDisplayMatch(params);
  @override
  void scheduleRendererStartupValidation() =>
      _s._rendererFallback.scheduleRendererStartupValidation();
  @override
  bool get mounted => _s.mounted;
  @override
  bool get isAndroidRendererValidation => VpS2Hooks.isAndroidRendererValidation;
}

class _VpTvosVideoHostAdapter implements VpTvosVideoHost {
  _VpTvosVideoHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  ContentDisplayMatchMode get contentDisplayMatchMode =>
      _s._contentDisplayMatchMode;
  @override
  mk.Player get player => _s._player;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  TvosDecodeRemedy? get tvosDecodeRemedy => _s._tvosDecodeRemedy;
  @override
  set tvosDecodeRemedy(TvosDecodeRemedy? v) => _s._tvosDecodeRemedy = v;
  @override
  Timer? get tvosDisplayMatchTimer => _s._tvosDisplayMatchTimer;
  @override
  set tvosDisplayMatchTimer(Timer? v) => _s._tvosDisplayMatchTimer = v;
  @override
  int get tvosDisplayMatchToken => _s._tvosDisplayMatchToken;
  @override
  set tvosDisplayMatchToken(int v) => _s._tvosDisplayMatchToken = v;
  @override
  void scheduleDecoderProbe() => _s._decoderProbe.scheduleDecoderProbe();
  @override
  bool get mounted => _s.mounted;
}

class _VpVideoOutputLeaseHostAdapter implements VpVideoOutputLeaseHost {
  _VpVideoOutputLeaseHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get screenDisposed => _s._screenDisposed;
}

class _VpAudioOutputHostAdapter implements VpAudioOutputHost {
  _VpAudioOutputHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get appleMultichannelEnabled => _s._appleMultichannelEnabled;
  @override
  bool get audioPassthroughEnabled => _s._audioPassthroughEnabled;
  @override
  set audioPassthroughEnabled(bool v) => _s._audioPassthroughEnabled = v;
  @override
  mk.Player get player => _s._player;
  @override
  bool get systemAudioEffectsEnabled => _s._systemAudioEffectsEnabled;
  @override
  bool get tvosForceStereoAudio => _s._tvosForceStereoAudio;
  @override
  bool get tvosLegacyAudioOutput => _s._tvosLegacyAudioOutput;
  @override
  int get tvosRouteOutputChannels => _s._tvosRouteOutputChannels;
  @override
  MediaKitSubtitleAutoSync? get subtitleAutoSync =>
      _s._subtitleSync.subtitleAutoSync;
}

class _VpMetadataPreloadHostAdapter implements VpMetadataPreloadHost {
  _VpMetadataPreloadHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  String get dynamicTitle => _s._dynamicTitle;
  @override
  int get playlistIdentityToken => _s._playlistIdentityToken;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  bool get singleFileImdbFetched => _s._singleFileImdbFetched;
  @override
  set singleFileImdbFetched(bool v) => _s._singleFileImdbFetched = v;
  @override
  set singleFileImdbId(String? v) => _s._singleFileImdbId = v;
  @override
  bool get trackPreferencesReadyForAddonSubtitles =>
      _s._trackPreferencesReadyForAddonSubtitles;
  @override
  Map<String, dynamic>? constructPlaylistItemData() =>
      _s._constructPlaylistItemData();
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  String get title => _s.widget.title;
  @override
  String? get rdTorrentId => _s.widget.rdTorrentId;
  @override
  String? get torboxTorrentId => _s.widget.torboxTorrentId;
  @override
  String? get pikpakCollectionId => _s.widget.pikpakCollectionId;
  @override
  Future<void> fetchAndMaybeAutoSelectAddonSubtitle() =>
      _s._addonSubtitles.fetchAndMaybeAutoSelectAddonSubtitle();
}

class _VpPikPakRetryHostAdapter implements VpPikPakRetryHost {
  _VpPikPakRetryHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  set isPikPakRetrying(bool v) => _s._isPikPakRetrying = v;
  @override
  set pikPakRetryCount(int v) => _s._pikPakRetryCount = v;
  @override
  int get pikPakRetryId => _s._pikPakRetryId;
  @override
  set pikPakRetryId(int v) => _s._pikPakRetryId = v;
  @override
  set pikPakRetryMessage(String? v) => _s._pikPakRetryMessage = v;
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
  }) => _s._mediaOpen.openMedia(
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
  Future<void> goToNextEpisode() => _s._episodeNext.goToNextEpisode();
  @override
  Future<bool> waitForVideoMetadata({
    int timeoutSeconds = 15,
    required int retryId,
    int additionalMonitoringSeconds = 0,
  }) => _s._mediaWaits.waitForVideoMetadata(
    timeoutSeconds: timeoutSeconds,
    retryId: retryId,
    additionalMonitoringSeconds: additionalMonitoringSeconds,
  );
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
}

class _VpMediaWaitsHostAdapter implements VpMediaWaitsHost {
  _VpMediaWaitsHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Duration get duration => _s._duration;
  @override
  set isPikPakRetrying(bool v) => _s._isPikPakRetrying = v;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  set pikPakRetryCount(int v) => _s._pikPakRetryCount = v;
  @override
  int get pikPakRetryId => _s._pikPakRetryId;
  @override
  set pikPakRetryMessage(String? v) => _s._pikPakRetryMessage = v;
  @override
  mk.Player get player => _s._player;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
}

class _VpPlaylistEntryResolveHostAdapter implements VpPlaylistEntryResolveHost {
  _VpPlaylistEntryResolveHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
}

class _VpPlaylistLoadHostAdapter implements VpPlaylistLoadHost {
  _VpPlaylistLoadHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  set activeHttpHeaders(Map<String, String>? v) => _s._activeHttpHeaders = v;
  @override
  bool get activeMediaShouldPlay => _s._activeMediaShouldPlay;
  @override
  set activeMediaShouldPlay(bool v) => _s._activeMediaShouldPlay = v;
  @override
  bool get activeMediaUserPaused => _s._activeMediaUserPaused;
  @override
  set activeMediaUserPaused(bool v) => _s._activeMediaUserPaused = v;
  @override
  mk.Media? get activeOpenedMedia => _s._activeOpenedMedia;
  @override
  set activeOpenedMedia(mk.Media? v) => _s._activeOpenedMedia = v;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  set allowResumeForManualSelection(bool v) =>
      _s._allowResumeForManualSelection = v;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  set currentIndex(int v) => _s._currentIndex = v;
  @override
  String? get currentStreamUrl => _s._currentStreamUrl;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  int get episodeNavigationGeneration => _s._episodeNavigationGeneration;
  @override
  set episodeNavigationGeneration(int v) => _s._episodeNavigationGeneration = v;
  @override
  bool get isAutoAdvancing => _s._isAutoAdvancing;
  @override
  set isAutoAdvancing(bool v) => _s._isAutoAdvancing = v;
  @override
  set isManualEpisodeSelection(bool v) => _s._isManualEpisodeSelection = v;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  Timer? get manualSelectionResetTimer => _s._manualSelectionResetTimer;
  @override
  set manualSelectionResetTimer(Timer? v) => _s._manualSelectionResetTimer = v;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  bool get pausedByLifecycle => _s._pausedByLifecycle;
  @override
  int get pikPakRetryId => _s._pikPakRetryId;
  @override
  set pikPakRetryId(int v) => _s._pikPakRetryId = v;
  @override
  mk.Player get player => _s._player;
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  set resumeVerifyEpoch(int v) => _s._resumeVerifyEpoch = v;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  MediaServerWatchController get serverWatch => _s._serverWatch;
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  set sleepStopLatched(bool v) => _s._sleepStopLatched = v;
  @override
  Timer? get transitionPhaseTimer => _s._transitionPhaseTimer;
  @override
  set transitionRunning(bool v) => _s._transitionRunning = v;
  @override
  Timer? get transitionStopTimer => _s._transitionStopTimer;
  @override
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  void resetSubtitleState() => _s._resetSubtitleState();
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
  }) => _s._mediaOpen.openMedia(
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
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  }) => _s._pikPakRetry.playPikPakVideoWithRetry(
    videoUrl,
    overrideProvider: overrideProvider,
    overridePikPakFileId: overridePikPakFileId,
    isDebrifyTV: isDebrifyTV,
    showFailure: showFailure,
    request: request,
  );
  @override
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  Future<String> resolvePlaylistEntryUrl(int index) =>
      _s._playlistEntryResolve.resolvePlaylistEntryUrl(index);
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  Future<void> saveResume() => _s._resumeSave.saveResume();
  @override
  Future<void> maybeRestoreResume({
    bool preferLocalResume = false,
    bool verifyLanding = false,
  }) => _s._resumeRestore.maybeRestoreResume(
    preferLocalResume: preferLocalResume,
    verifyLanding: verifyLanding,
  );
  @override
  void stopTraktHeartbeat() => _s._trakt.stopTraktHeartbeat();
  @override
  void traktScrobble(String action) => _s._trakt.traktScrobble(action);
  @override
  void stopSimklHeartbeat() => _s._simkl.stopSimklHeartbeat();
  @override
  void simklScrobble(String action) => _s._simkl.simklScrobble(action);
  @override
  void updateMdblistPosition() => _s._mdblist.updateMdblistPosition();
  @override
  Future<void> switchMdblistTarget() => _s._mdblist.switchMdblistTarget();
  @override
  void resetLocalCompletionState() =>
      _s._completion.resetLocalCompletionState();
  @override
  set skipSegmentsMediaReady(bool v) => _s._skip.skipSegmentsMediaReady = v;
  @override
  void resetSkipSegmentState() => _s._skip.resetSkipSegmentState();
  @override
  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  }) => _s._startupCandidates.tryOpenStartupVod(
    url,
    timeout: timeout,
    httpHeaders: httpHeaders,
    source: source,
    sourceIndex: sourceIndex,
    attempt: attempt,
    maxAttempts: maxAttempts,
  );
  @override
  Future<void> restoreTrackPreferences() =>
      _s._trackPreferences.restoreTrackPreferences();
}

class _VpEpisodeTitleInfoHostAdapter implements VpEpisodeTitleInfoHost {
  _VpEpisodeTitleInfoHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  String get dynamicTitle => _s._dynamicTitle;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  String? get effectiveContentTitle => _s._effectiveContentTitle;
  @override
  List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override
  List<Map<String, dynamic>>? get effectiveStremioTvChannels =>
      _s._effectiveStremioTvChannels;
  @override
  bool get hasStremioTvGuide => _s._hasStremioTvGuide;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  Future<Map<String, String>?> Function()? get requestMagicNext =>
      _s.widget.requestMagicNext;
  @override
  String get title => _s.widget.title;
  @override
  String? get subtitle => _s.widget.subtitle;
}

class _VpShuffleHostAdapter implements VpShuffleHost {
  _VpShuffleHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  bool get canFetchEpisodes => _s._canFetchEpisodes;
  @override
  bool get continuousShuffleEnabled => _s._continuousShuffleEnabled;
  @override
  set continuousShuffleEnabled(bool v) => _s._continuousShuffleEnabled = v;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  String? get currentSeriesImdbId => _s._currentSeriesImdbId;
  @override
  bool get episodeFetchInProgress => _s._episodeFetchInProgress;
  @override
  Future<void>? get episodeMetadataReady => _s._episodeMetadataReady;
  @override
  set episodeMetadataReady(Future<void>? v) => _s._episodeMetadataReady = v;
  @override
  int get episodeNavigationGeneration => _s._episodeNavigationGeneration;
  @override
  Timer? get hideTimer => _s._hideTimer;
  @override
  set isAutoAdvancing(bool v) => _s._isAutoAdvancing = v;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  int get playlistIdentityToken => _s._playlistIdentityToken;
  @override
  math.Random get random => _s._random;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  int get showShuffleGeneration => _s._showShuffleGeneration;
  @override
  set showShuffleGeneration(int v) => _s._showShuffleGeneration = v;
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  SeriesPlaylist? get syntheticGuidePlaylist => _s._syntheticGuidePlaylist;
  @override
  void scheduleAutoHide() => _s._controlsRuntime.scheduleAutoHide();
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  Map<String, dynamic>? constructPlaylistItemData() =>
      _s._constructPlaylistItemData();
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  void setManualSelectionMode({bool allowResume = false}) =>
      _s._playlistLoad.setManualSelectionMode(allowResume: allowResume);
  @override
  List<int> getMainGroupIndices(List<PlaylistEntry> entries) =>
      _s._episodeAdjacent.getMainGroupIndices(entries);
  @override
  Future<void> preloadEpisodeInfo() => _s._metadataPreload.preloadEpisodeInfo();
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  SeriesSourceFetcher? get seriesSourceFetcher => _s.widget.seriesSourceFetcher;
  @override
  PlaylistViewMode? get viewMode => _s.widget.viewMode;
  @override
  void openPlayerMenuQuick(PlayerMenuSection section) =>
      _s._menu.openPlayerMenuQuick(section);
  @override
  (SeriesPlaylist, List<PlaylistEntry>)? buildSyntheticGuide() =>
      _s._episodeGuide.buildSyntheticGuide();
  @override
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  }) => _s._episodeFetch.fetchAndPlayEpisode(
    season,
    episode,
    shuffleGeneration: shuffleGeneration,
    autoAdvance: autoAdvance,
    request: request,
  );
}

class _VpEpisodeAdjacentHostAdapter implements VpEpisodeAdjacentHost {
  _VpEpisodeAdjacentHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  bool get canFetchEpisodes => _s._canFetchEpisodes;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  bool get episodeFetchInProgress => _s._episodeFetchInProgress;
  @override
  int get episodeNavigationGeneration => _s._episodeNavigationGeneration;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  int get playlistIdentityToken => _s._playlistIdentityToken;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  SeriesPlaylist? get syntheticGuidePlaylist => _s._syntheticGuidePlaylist;
  @override
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  void setManualSelectionMode({bool allowResume = false}) =>
      _s._playlistLoad.setManualSelectionMode(allowResume: allowResume);
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  Future<Map<String, String>?> Function()? get requestMagicNext =>
      _s.widget.requestMagicNext;
  @override
  String? get contentType => _s.widget.contentType;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  int? get contentSeason => _s.widget.contentSeason;
  @override
  SeriesSourceFetcher? get seriesSourceFetcher => _s.widget.seriesSourceFetcher;
  @override
  PlaylistViewMode? get viewMode => _s.widget.viewMode;
  @override
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  }) => _s._episodeFetch.fetchAndPlayEpisode(
    season,
    episode,
    shuffleGeneration: shuffleGeneration,
    autoAdvance: autoAdvance,
    request: request,
  );
}

class _VpEpisodeNextHostAdapter implements VpEpisodeNextHost {
  _VpEpisodeNextHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  bool get continuousShuffleEnabled => _s._continuousShuffleEnabled;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  Duration get duration => _s._duration;
  @override
  set dynamicTitle(String v) => _s._dynamicTitle = v;
  @override
  bool get hasStremioTvNext => _s._hasStremioTvNext;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  int get pikPakRetryId => _s._pikPakRetryId;
  @override
  set pikPakRetryId(int v) => _s._pikPakRetryId = v;
  @override
  mk.Player get player => _s._player;
  @override
  bool get seriesNextDispatched => _s._seriesNextDispatched;
  @override
  set seriesNextDispatched(bool v) => _s._seriesNextDispatched = v;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  set singleFileImdbFetched(bool v) => _s._singleFileImdbFetched = v;
  @override
  set singleFileImdbId(String? v) => _s._singleFileImdbId = v;
  @override
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  set tvStaticMessage(String v) => _s._tvStaticMessage = v;
  @override
  set tvStaticSubtext(String v) => _s._tvStaticSubtext = v;
  @override
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
  @override
  void startTransitionOverlay() =>
      _s._transitionOverlay.startTransitionOverlay();
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  void resetSubtitleState() => _s._resetSubtitleState();
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
  }) => _s._mediaOpen.openMedia(
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
  Duration? randomStartOffset(Duration total) => _s._randomStartOffset(total);
  @override
  Duration? percentStartOffset(Duration total) => _s._percentStartOffset(total);
  @override
  Future<bool> playShowShuffle({bool autoAdvance = false}) =>
      _s._shuffle.playShowShuffle(autoAdvance: autoAdvance);
  @override
  int? pickShuffleIndex() => _s._shuffle.pickShuffleIndex();
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  int findNextEpisodeIndex() => _s._episodeAdjacent.findNextEpisodeIndex();
  @override
  Future<bool> fetchNextEpisodeInPlayer({bool autoAdvance = false}) =>
      _s._episodeAdjacent.fetchNextEpisodeInPlayer(autoAdvance: autoAdvance);
  @override
  void setManualSelectionMode({bool allowResume = false}) =>
      _s._playlistLoad.setManualSelectionMode(allowResume: allowResume);
  @override
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  }) => _s._pikPakRetry.playPikPakVideoWithRetry(
    videoUrl,
    overrideProvider: overrideProvider,
    overridePikPakFileId: overridePikPakFileId,
    isDebrifyTV: isDebrifyTV,
    showFailure: showFailure,
    request: request,
  );
  @override
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  Future<Map<String, String>?> Function()? get requestMagicNext =>
      _s.widget.requestMagicNext;
  @override
  bool get startFromRandom => _s.widget.startFromRandom;
  @override
  double? get startAtPercent => _s.widget.startAtPercent;
  @override
  String? get contentType => _s.widget.contentType;
  @override
  String? get contentImdbId => _s.widget.contentImdbId;
  @override
  int? get contentSeason => _s.widget.contentSeason;
  @override
  int? get contentEpisode => _s.widget.contentEpisode;
  @override
  String? get contentTitle => _s.widget.contentTitle;
  @override
  String get title => _s.widget.title;
  @override
  SeriesSourceFetcher? get seriesSourceFetcher => _s.widget.seriesSourceFetcher;
  @override
  void resetLocalCompletionState() =>
      _s._completion.resetLocalCompletionState();
  @override
  Future<bool> goToNextStremioTvSlot({bool resumeCurrentOnFailure = true}) => _s
      ._stremioTv
      .goToNextStremioTvSlot(resumeCurrentOnFailure: resumeCurrentOnFailure);
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
  PlayerPipSession? get iosPipSession => _s._pip.iosPipSession;
}

class _VpPlaybackEndedHostAdapter implements VpPlaybackEndedHost {
  _VpPlaybackEndedHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set activeMediaShouldPlay(bool v) => _s._activeMediaShouldPlay = v;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  bool get continuousShuffleEnabled => _s._continuousShuffleEnabled;
  @override
  IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override
  int get currentIptvIndex => _s._currentIptvIndex;
  @override
  bool get hasIptvNext => _s._hasIptvNext;
  @override
  bool get hasStremioTvNext => _s._hasStremioTvNext;
  @override
  IptvLiveRecovery get iptvLiveRecovery => _s._iptvLiveRecovery;
  @override
  set isAutoAdvancing(bool v) => _s._isAutoAdvancing = v;
  @override
  set sleepStopLatched(bool v) => _s._sleepStopLatched = v;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  Future<bool> playShowShuffle({bool autoAdvance = false}) =>
      _s._shuffle.playShowShuffle(autoAdvance: autoAdvance);
  @override
  int? pickShuffleIndex() => _s._shuffle.pickShuffleIndex();
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  int findNextEpisodeIndex() => _s._episodeAdjacent.findNextEpisodeIndex();
  @override
  Future<void> goToNextEpisode() => _s._episodeNext.goToNextEpisode();
  @override
  Future<bool> fetchNextEpisodeInPlayer({bool autoAdvance = false}) =>
      _s._episodeAdjacent.fetchNextEpisodeInPlayer(autoAdvance: autoAdvance);
  @override
  Future<bool> handleSeriesNextEpisode() =>
      _s._episodeNext.handleSeriesNextEpisode();
  @override
  Future<Map<String, String>?> Function()? get requestMagicNext =>
      _s.widget.requestMagicNext;
  @override
  void observeServerWatch({bool completed = false}) =>
      _s._resumeSave.observeServerWatch(completed: completed);
  @override
  void stopTraktHeartbeat() => _s._trakt.stopTraktHeartbeat();
  @override
  void traktScrobble(String action) => _s._trakt.traktScrobble(action);
  @override
  void stopSimklHeartbeat() => _s._simkl.stopSimklHeartbeat();
  @override
  void simklScrobble(String action) => _s._simkl.simklScrobble(action);
  @override
  void mdblistStop({bool complete = false}) =>
      _s._mdblist.mdblistStop(complete: complete);
  @override
  Future<void> markCurrentEpisodeAsFinished() =>
      _s._completion.markCurrentEpisodeAsFinished();
  @override
  Future<void> markCurrentMovieAsFinished() =>
      _s._completion.markCurrentMovieAsFinished();
  @override
  SleepTimerMode get sleepTimerMode => _s._sleep.sleepTimerMode;
  @override
  void cancelSleepTimer() => _s._sleep.cancelSleepTimer();
  @override
  void showSleepTimerToast(String message) =>
      _s._sleep.showSleepTimerToast(message);
  @override
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false}) =>
      _s._iptvSwitch.switchToIptvChannel(index, quietRecovery: quietRecovery);
  @override
  Future<bool> goToNextStremioTvSlot({bool resumeCurrentOnFailure = true}) => _s
      ._stremioTv
      .goToNextStremioTvSlot(resumeCurrentOnFailure: resumeCurrentOnFailure);
}

class _VpEpisodeGuideHostAdapter implements VpEpisodeGuideHost {
  _VpEpisodeGuideHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  bool get canFetchEpisodes => _s._canFetchEpisodes;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  String? get currentSeriesImdbId => _s._currentSeriesImdbId;
  @override
  Future<void>? get episodeMetadataReady => _s._episodeMetadataReady;
  @override
  set episodeMetadataReady(Future<void>? v) => _s._episodeMetadataReady = v;
  @override
  bool get seriesImdbKnownAtLaunch => _s._seriesImdbKnownAtLaunch;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  SeriesPlaylist? get syntheticGuidePlaylist => _s._syntheticGuidePlaylist;
  @override
  set syntheticGuidePlaylist(SeriesPlaylist? v) =>
      _s._syntheticGuidePlaylist = v;
  @override
  void setManualSelectionMode({bool allowResume = false}) =>
      _s._playlistLoad.setManualSelectionMode(allowResume: allowResume);
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  Future<void> preloadEpisodeInfo() => _s._metadataPreload.preloadEpisodeInfo();
  @override
  Map<String, dynamic>? constructPlaylistItemData() =>
      _s._constructPlaylistItemData();
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  Future<EpisodePlaybackOutcome> fetchAndPlayEpisode(
    int season,
    int episode, {
    int? shuffleGeneration,
    bool autoAdvance = false,
    EpisodePlaybackRequest? request,
  }) => _s._episodeFetch.fetchAndPlayEpisode(
    season,
    episode,
    shuffleGeneration: shuffleGeneration,
    autoAdvance: autoAdvance,
    request: request,
  );
  @override
  String get title => _s.widget.title;
  @override
  String get videoUrl => _s.widget.videoUrl;
  @override
  String? get contentTitle => _s.widget.contentTitle;
  @override
  PlaylistViewMode? get viewMode => _s.widget.viewMode;
}

class _VpEpisodeFetchHostAdapter implements VpEpisodeFetchHost {
  _VpEpisodeFetchHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set augmentedSources(List<Torrent>? v) => _s._augmentedSources = v;
  @override
  bool get canFetchEpisodes => _s._canFetchEpisodes;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  Duration get duration => _s._duration;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  bool get episodeFetchInProgress => _s._episodeFetchInProgress;
  @override
  set episodeFetchInProgress(bool v) => _s._episodeFetchInProgress = v;
  @override
  int get episodeNavigationGeneration => _s._episodeNavigationGeneration;
  @override
  set episodeNavigationGeneration(int v) => _s._episodeNavigationGeneration = v;
  @override
  set isAutoAdvancing(bool v) => _s._isAutoAdvancing = v;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  int get playlistIdentityToken => _s._playlistIdentityToken;
  @override
  Duration get position => _s._position;
  @override
  int get showShuffleGeneration => _s._showShuffleGeneration;
  @override
  bool get sleepStopLatched => _s._sleepStopLatched;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  void setManualSelectionMode({bool allowResume = false}) =>
      _s._playlistLoad.setManualSelectionMode(allowResume: allowResume);
  @override
  bool get mounted => _s.mounted;
  @override
  BuildContext get context => _s.context;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  SeriesSourceFetcher? get seriesSourceFetcher => _s.widget.seriesSourceFetcher;
  @override
  SourcePlaylistResolve? get resolveSourceToPlaylist =>
      _s.widget.resolveSourceToPlaylist;
  @override
  String get title => _s.widget.title;
  @override
  Future<bool> switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
    bool suppressResume = false,
    EpisodePlaybackRequest? request,
  }) => _s._sourcePlaylistSwitch.switchToSourcePlaylist(
    sourceIndex,
    newPlaylist,
    targetSeason: targetSeason,
    targetEpisode: targetEpisode,
    validateExplicitSelection: validateExplicitSelection,
    suppressResume: suppressResume,
    request: request,
  );
  @override
  VpSeasonEpisodeSelection? currentSeasonEpisodeForIdentity() =>
      _s._identify.currentSeasonEpisodeForIdentity();
}

class _VpStremioTvChannelsHostAdapter implements VpStremioTvChannelsHost {
  _VpStremioTvChannelsHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  String? get currentStremioTvChannelId => _s._currentStremioTvChannelId;
  @override
  set currentStremioTvChannelId(String? v) => _s._currentStremioTvChannelId = v;
  @override
  set currentStremioTvContentEpisode(int? v) =>
      _s._currentStremioTvContentEpisode = v;
  @override
  set currentStremioTvContentImdbId(String? v) =>
      _s._currentStremioTvContentImdbId = v;
  @override
  set currentStremioTvContentSeason(int? v) =>
      _s._currentStremioTvContentSeason = v;
  @override
  set currentStremioTvContentTitle(String? v) =>
      _s._currentStremioTvContentTitle = v;
  @override
  set currentStremioTvContentType(String? v) =>
      _s._currentStremioTvContentType = v;
  @override
  String get dynamicTitle => _s._dynamicTitle;
  @override
  set dynamicTitle(String v) => _s._dynamicTitle = v;
  @override
  List<Map<String, dynamic>>? get effectiveStremioTvChannels =>
      _s._effectiveStremioTvChannels;
  @override
  bool get hasStremioTvGuide => _s._hasStremioTvGuide;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  int get pikPakRetryId => _s._pikPakRetryId;
  @override
  set pikPakRetryId(int v) => _s._pikPakRetryId = v;
  @override
  mk.Player get player => _s._player;
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  set resolveStremioSourceOverride(Future<String?> Function(Torrent)? v) =>
      _s._resolveStremioSourceOverride = v;
  @override
  set showStremioTvGuide(bool v) => _s._showStremioTvGuide = v;
  @override
  bool get showStremioTvNextLoading => _s._showStremioTvNextLoading;
  @override
  set showStremioTvNextLoading(bool v) => _s._showStremioTvNextLoading = v;
  @override
  set singleFileImdbFetched(bool v) => _s._singleFileImdbFetched = v;
  @override
  set singleFileImdbId(String? v) => _s._singleFileImdbId = v;
  @override
  set stremioSourcesOverride(List<Torrent>? v) =>
      _s._stremioSourcesOverride = v;
  @override
  set stremioTvChannelsOverride(List<Map<String, dynamic>>? v) =>
      _s._stremioTvChannelsOverride = v;
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
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
  @override
  void startTransitionOverlay() =>
      _s._transitionOverlay.startTransitionOverlay();
  @override
  void resetSubtitleState() => _s._resetSubtitleState();
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
  }) => _s._mediaOpen.openMedia(
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
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  String? get stremioTvCurrentChannelId => _s.widget.stremioTvCurrentChannelId;
  @override
  Future<Map<String, dynamic>?> Function(String)? get stremioTvNextProvider =>
      _s.widget.stremioTvNextProvider;
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
  void resetLocalCompletionState() =>
      _s._completion.resetLocalCompletionState();
}

class _VpDebrifyTvBannerHostAdapter implements VpDebrifyTvBannerHost {
  _VpDebrifyTvBannerHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  bool get anyPlayerOverlayOpen => _s._anyPlayerOverlayOpen;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  bool get debrifyBannerFloatingMounted => _s._debrifyBannerFloatingMounted;
  @override
  set debrifyBannerFloatingMounted(bool v) =>
      _s._debrifyBannerFloatingMounted = v;
  @override
  bool get debrifyTvOwnsIdentity => _s._debrifyTvOwnsIdentity;
  @override
  bool get isTransitioning => _s._isTransitioning;
  @override
  PlaybackUiClockController get playbackUiClock => _s._playbackUiClock;
  @override
  bool get showDebrifyBanner => _s._showDebrifyBanner;
  @override
  set showDebrifyBanner(bool v) => _s._showDebrifyBanner = v;
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get hideSeekbar => _s.widget.hideSeekbar;
}

class _VpDebrifyTvChannelsHostAdapter implements VpDebrifyTvChannelsHost {
  _VpDebrifyTvChannelsHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  List<ChannelEntry> get channelEntries => _s._channelEntries;
  @override
  set channelEntries(List<ChannelEntry> v) => _s._channelEntries = v;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  String? get currentChannelId => _s._currentChannelId;
  @override
  set currentChannelId(String? v) => _s._currentChannelId = v;
  @override
  set currentChannelName(String? v) => _s._currentChannelName = v;
  @override
  set currentChannelNumber(int? v) => _s._currentChannelNumber = v;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  Duration get duration => _s._duration;
  @override
  set dynamicTitle(String v) => _s._dynamicTitle = v;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  int get pikPakRetryId => _s._pikPakRetryId;
  @override
  set pikPakRetryId(int v) => _s._pikPakRetryId = v;
  @override
  mk.Player get player => _s._player;
  @override
  set showChannelGuide(bool v) => _s._showChannelGuide = v;
  @override
  set singleFileImdbFetched(bool v) => _s._singleFileImdbFetched = v;
  @override
  set singleFileImdbId(String? v) => _s._singleFileImdbId = v;
  @override
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  set tvStaticMessage(String v) => _s._tvStaticMessage = v;
  @override
  set tvStaticSubtext(String v) => _s._tvStaticSubtext = v;
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
  @override
  void startTransitionOverlay() =>
      _s._transitionOverlay.startTransitionOverlay();
  @override
  void resetSubtitleState() => _s._resetSubtitleState();
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
  }) => _s._mediaOpen.openMedia(
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
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  Duration? randomStartOffset(Duration total) => _s._randomStartOffset(total);
  @override
  Duration? percentStartOffset(Duration total) => _s._percentStartOffset(total);
  @override
  void raiseDebrifyBanner() => _s._debrifyBanner.raiseDebrifyBanner();
  @override
  bool get mounted => _s.mounted;
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  List<Map<String, dynamic>>? get channelDirectory =>
      _s.widget.channelDirectory;
  @override
  Future<Map<String, dynamic>?> Function(String)? get requestChannelById =>
      _s.widget.requestChannelById;
  @override
  Future<Map<String, dynamic>?> Function()? get requestNextChannel =>
      _s.widget.requestNextChannel;
  @override
  bool get startFromRandom => _s.widget.startFromRandom;
  @override
  double? get startAtPercent => _s.widget.startAtPercent;
  @override
  void hideIptvZapBanner({bool immediate = false}) =>
      _s._iptvBanner.hideIptvZapBanner(immediate: immediate);
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

class _VpSourcePlaylistSwitchHostAdapter implements VpSourcePlaylistSwitchHost {
  _VpSourcePlaylistSwitchHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  set activeHttpHeaders(Map<String, String>? v) => _s._activeHttpHeaders = v;
  @override
  List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override
  set activePlaylist(List<PlaylistEntry>? v) => _s._activePlaylist = v;
  @override
  set allowResumeForManualSelection(bool v) =>
      _s._allowResumeForManualSelection = v;
  @override
  SeriesPlaylist? get cachedSeriesPlaylist => _s._cachedSeriesPlaylist;
  @override
  set cachedSeriesPlaylist(SeriesPlaylist? v) => _s._cachedSeriesPlaylist = v;
  @override
  int get currentIndex => _s._currentIndex;
  @override
  set currentIndex(int v) => _s._currentIndex = v;
  @override
  String? get currentSeriesImdbId => _s._currentSeriesImdbId;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  String? get currentStreamUrl => _s._currentStreamUrl;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  set episodeMetadataReady(Future<void>? v) => _s._episodeMetadataReady = v;
  @override
  int get episodeNavigationGeneration => _s._episodeNavigationGeneration;
  @override
  set episodeNavigationGeneration(int v) => _s._episodeNavigationGeneration = v;
  @override
  set isManualEpisodeSelection(bool v) => _s._isManualEpisodeSelection = v;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  set manualSourceGateActive(bool v) => _s._manualSourceGateActive = v;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  mk.Player get player => _s._player;
  @override
  int get playlistIdentityToken => _s._playlistIdentityToken;
  @override
  set playlistIdentityToken(int v) => _s._playlistIdentityToken = v;
  @override
  Duration get position => _s._position;
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override
  MediaServerWatchController get serverWatch => _s._serverWatch;
  @override
  SeriesPlaylist? get syntheticGuidePlaylist => _s._syntheticGuidePlaylist;
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
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  BuildContext get context => _s.context;
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
  }) => _s._mediaOpen.openMedia(
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
  Future<void> commitValidatedStremioSource(Torrent? source) =>
      _s._startupCandidates.commitValidatedStremioSource(source);
  @override
  void resumeTrackingAfterValidationGate() =>
      _s._startupGate.resumeTrackingAfterValidationGate();
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  void startTransitionOverlay() =>
      _s._transitionOverlay.startTransitionOverlay();
  @override
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
  @override
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  ({int? season, int? episode}) traktSeasonEpisode() =>
      _s._traktSeasonEpisode();
  @override
  Future<void> preloadEpisodeInfo() => _s._metadataPreload.preloadEpisodeInfo();
  @override
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) => _s._playlistLoad.loadPlaylistIndex(
    index,
    autoplay: autoplay,
    request: request,
    skipInitialSave: skipInitialSave,
    preferLocalResume: preferLocalResume,
    suppressResume: suppressResume,
    manualValidationSource: manualValidationSource,
    manualValidationSourceIndex: manualValidationSourceIndex,
  );
  @override
  void hideSourceSheet() => _s._sourceSwitch.hideSourceSheet();
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get mounted => _s.mounted;
  @override
  Future<void> switchMdblistTarget() => _s._mdblist.switchMdblistTarget();
  @override
  Future<void> seekForResume(int posMs, {bool verifyLanding = false}) =>
      _s._resumeRestore.seekForResume(posMs, verifyLanding: verifyLanding);
  @override
  Future<void> saveResume({
    bool debounced = false,
    Duration? positionOverride,
  }) => _s._resumeSave.saveResume(
    debounced: debounced,
    positionOverride: positionOverride,
  );
  @override
  Future<void> restoreTrackPreferences() =>
      _s._trackPreferences.restoreTrackPreferences();
}

class _VpSourceSwitchHostAdapter implements VpSourceSwitchHost {
  _VpSourceSwitchHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  Map<String, String>? get activeHttpHeaders => _s._activeHttpHeaders;
  @override
  set activeHttpHeaders(Map<String, String>? v) => _s._activeHttpHeaders = v;
  @override
  ValueNotifier<bool> get controlsVisible => _s._controlsVisible;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  String? get currentStreamUrl => _s._currentStreamUrl;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  Duration get duration => _s._duration;
  @override
  Future<String?> Function(Torrent)? get effectiveResolver =>
      _s._effectiveResolver;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  String? get iptvChannelKey => _s._iptvChannelKey;
  @override
  set isTransitioning(bool v) => _s._isTransitioning = v;
  @override
  set manualSourceGateActive(bool v) => _s._manualSourceGateActive = v;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  mk.Player get player => _s._player;
  @override
  Duration get position => _s._position;
  @override
  set rainbowActive(bool v) => _s._rainbowActive = v;
  @override
  AnimationController get rainbowController => _s._rainbowController;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  set resumeVerifyEpoch(int v) => _s._resumeVerifyEpoch = v;
  @override
  ResumeWriteGuard get resumeWriteGuard => _s._resumeWriteGuard;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  MediaServerWatchController get serverWatch => _s._serverWatch;
  @override
  bool get showSourceSheet => _s._showSourceSheet;
  @override
  set showSourceSheet(bool v) => _s._showSourceSheet = v;
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
  int get tvScrubGeneration => _s._tvScrubGeneration;
  @override
  set tvScrubGeneration(int v) => _s._tvScrubGeneration = v;
  @override
  BuildContext get context => _s.context;
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
  }) => _s._mediaOpen.openMedia(
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
  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  }) => _s._startupCandidates.tryOpenStartupVod(
    url,
    timeout: timeout,
    httpHeaders: httpHeaders,
    source: source,
    sourceIndex: sourceIndex,
    attempt: attempt,
    maxAttempts: maxAttempts,
  );
  @override
  Future<void> commitValidatedStremioSource(Torrent? source) =>
      _s._startupCandidates.commitValidatedStremioSource(source);
  @override
  Future<bool> switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
    bool suppressResume = false,
    EpisodePlaybackRequest? request,
  }) => _s._sourcePlaylistSwitch.switchToSourcePlaylist(
    sourceIndex,
    newPlaylist,
    targetSeason: targetSeason,
    targetEpisode: targetEpisode,
    validateExplicitSelection: validateExplicitSelection,
    suppressResume: suppressResume,
    request: request,
  );
  @override
  void resumeTrackingAfterValidationGate() =>
      _s._startupGate.resumeTrackingAfterValidationGate();
  @override
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
  @override
  void startTransitionOverlay() =>
      _s._transitionOverlay.startTransitionOverlay();
  @override
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
  @override
  void resetSubtitleState() => _s._resetSubtitleState();
  @override
  Future<void> waitForVideoReady() => _s._mediaWaits.waitForVideoReady();
  @override
  Future<void> setExternalAudioTrack(String url) =>
      _s._audioOutput.setExternalAudioTrack(url);
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get mounted => _s.mounted;
  @override
  SourcePlaylistResolve? get resolveSourceToPlaylist =>
      _s.widget.resolveSourceToPlaylist;
  @override
  String? get audioUrl => _s.widget.audioUrl;
  @override
  void hideIptvZapBanner({bool immediate = false}) =>
      _s._iptvBanner.hideIptvZapBanner(immediate: immediate);
  @override
  Future<void> switchToIptvSource(int index, String url) =>
      _s._iptvSwitch.switchToIptvSource(index, url);
  @override
  Future<void> seekForResume(int posMs, {bool verifyLanding = false}) =>
      _s._resumeRestore.seekForResume(posMs, verifyLanding: verifyLanding);
  @override
  Future<void> restoreTrackPreferences() =>
      _s._trackPreferences.restoreTrackPreferences();
}

class _VpStartupGateHostAdapter implements VpStartupGateHost {
  _VpStartupGateHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  int get decoderProbeGeneration => _s._decoderProbeGeneration;
  @override
  Duration get duration => _s._duration;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  bool get isPlaying => _s._isPlaying;
  @override
  mk.Player get player => _s._player;
  @override
  int get playerInstanceGeneration => _s._playerInstanceGeneration;
  @override
  int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  bool get startupGateActive => _s._startupGateActive;
  @override
  set startupGateActive(bool v) => _s._startupGateActive = v;
  @override
  String get startupGateMessage => _s._startupGateMessage;
  @override
  set startupGateMessage(String v) => _s._startupGateMessage = v;
  @override
  set startupGateOverlayHidden(bool v) => _s._startupGateOverlayHidden = v;
  @override
  DeferredStartupSeek get stremioTvStartupSeek => _s._stremioTvStartupSeek;
  @override
  ChannelStartupWatch? get stremioTvStartupWatch => _s._stremioTvStartupWatch;
  @override
  set stremioTvStartupWatch(ChannelStartupWatch? v) =>
      _s._stremioTvStartupWatch = v;
  @override
  bool get validationGateActive => _s._validationGateActive;
  @override
  BuildContext get context => _s.context;
  @override
  bool canFallbackExplicitRenderer({
    required int instanceGeneration,
    required int mediaGeneration,
  }) => _s._rendererFallback.canFallbackExplicitRenderer(
    instanceGeneration: instanceGeneration,
    mediaGeneration: mediaGeneration,
  );
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get mounted => _s.mounted;
  @override
  Future<void> Function()? get onStartupSourcesExhausted =>
      _s.widget.onStartupSourcesExhausted;
  @override
  String? get traktLastScrobbleAction => _s._trakt.traktLastScrobbleAction;
  @override
  bool get simklScrobbleEnabled => _s._simkl.simklScrobbleEnabled;
  @override
  set simklLastScrobbleAction(String? v) =>
      _s._simkl.simklLastScrobbleAction = v;
  @override
  void traktScrobble(String action) => _s._trakt.traktScrobble(action);
  @override
  void startTraktHeartbeat() => _s._trakt.startTraktHeartbeat();
  @override
  void startSimklHeartbeat() => _s._simkl.startSimklHeartbeat();
  @override
  void updateMdblistPosition() => _s._mdblist.updateMdblistPosition();
  @override
  void mdblistPlay() => _s._mdblist.mdblistPlay();
}

class _VpStartupFailoverHostAdapter implements VpStartupFailoverHost {
  _VpStartupFailoverHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  set activeHttpHeaders(Map<String, String>? v) => _s._activeHttpHeaders = v;
  @override
  set activePlaylist(List<PlaylistEntry>? v) => _s._activePlaylist = v;
  @override
  set cachedSeriesPlaylist(SeriesPlaylist? v) => _s._cachedSeriesPlaylist = v;
  @override
  set currentIndex(int v) => _s._currentIndex = v;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  set currentSourceIndex(int v) => _s._currentSourceIndex = v;
  @override
  set currentStreamUrl(String? v) => _s._currentStreamUrl = v;
  @override
  int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override
  int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override
  String? get effectiveContentType => _s._effectiveContentType;
  @override
  Future<String?> Function(Torrent)? get effectiveResolver =>
      _s._effectiveResolver;
  @override
  List<Torrent>? get effectiveSources => _s._effectiveSources;
  @override
  int get playlistIdentityToken => _s._playlistIdentityToken;
  @override
  set playlistIdentityToken(int v) => _s._playlistIdentityToken = v;
  @override
  bool get screenDisposed => _s._screenDisposed;
  @override
  bool get startupGateOverlayHidden => _s._startupGateOverlayHidden;
  @override
  set startupGateOverlayHidden(bool v) => _s._startupGateOverlayHidden = v;
  @override
  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  }) => _s._startupCandidates.tryOpenStartupVod(
    url,
    timeout: timeout,
    httpHeaders: httpHeaders,
    source: source,
    sourceIndex: sourceIndex,
    attempt: attempt,
    maxAttempts: maxAttempts,
  );
  @override
  Future<bool> openStartupDebridDirect(
    String url, {
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
    Duration timeout = const Duration(seconds: 12),
  }) => _s._startupCandidates.openStartupDebridDirect(
    url,
    httpHeaders: httpHeaders,
    source: source,
    sourceIndex: sourceIndex,
    attempt: attempt,
    maxAttempts: maxAttempts,
    timeout: timeout,
  );
  @override
  String startupSourceFields(int? index, Torrent? source) =>
      _s._startupCandidates.startupSourceFields(index, source);
  @override
  Future<void> commitValidatedStremioSource(Torrent? source) =>
      _s._startupCandidates.commitValidatedStremioSource(source);
  @override
  void setStartupGateActive(bool active) =>
      _s._startupGate.setStartupGateActive(active);
  @override
  void setStartupGateMessage(String message) =>
      _s._startupGate.setStartupGateMessage(message);
  @override
  void setState(VoidCallback fn) => _s._vpSetState(fn);
  @override
  bool get mounted => _s.mounted;
  @override
  bool get startupFailoverEnabled => _s.widget.startupFailoverEnabled;
  @override
  String? get startupResolverProvider => _s.widget.startupResolverProvider;
  @override
  SourcePlaylistResolve? get resolveSourceToPlaylist =>
      _s.widget.resolveSourceToPlaylist;
  @override
  String get title => _s.widget.title;
}

class _VpStartupCandidatesHostAdapter implements VpStartupCandidatesHost {
  _VpStartupCandidatesHostAdapter(this._s);
  final _VideoPlayerScreenState _s;
  @override
  AndroidVideoRendererMode get androidVideoRendererMode =>
      _s._androidVideoRendererMode;
  @override
  int get currentSourceIndex => _s._currentSourceIndex;
  @override
  Torrent? get openedWatchSource => _s._openedWatchSource;
  @override
  mk.Player get player => _s._player;
  @override
  bool get rendererFallbackInProgress => _s._rendererFallbackInProgress;
  @override
  bool get rendererValidatedForSession => _s._rendererValidatedForSession;
  @override
  MediaServerWatchController get serverWatch => _s._serverWatch;
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
  }) => _s._mediaOpen.openMedia(
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
  Future<void> Function(Torrent)? get onStremioSourceCommitted =>
      _s.widget.onStremioSourceCommitted;
  @override
  bool get isAndroid => VpS2Hooks.isAndroid;
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
  }) => _s._mediaOpen.openMedia(
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
  void clearBufferingIndicator() =>
      _s._transitionOverlay.clearBufferingIndicator();
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
  void hideSourceSheet() => _s._sourceSwitch.hideSourceSheet();
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
  }) => _s._mediaOpen.openMedia(
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
  void startTransitionOverlay() =>
      _s._transitionOverlay.startTransitionOverlay();
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
  void tvAbandonScrub() => _s._tvRemote.tvAbandonScrub();
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
  }) => _s._mediaOpen.openMedia(
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
  void scheduleAutoHide() => _s._controlsRuntime.scheduleAutoHide();
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
  Future<void> waitForDuration() => _s._mediaWaits.waitForDuration();
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
  void tvReleaseFocusForOverlay() =>
      _s._controlsRuntime.tvReleaseFocusForOverlay();
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
      _s._metadataPreload.fetchSingleFileMovieMetadata();
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
  Future<void> playRandomOnce({bool disableContinuousShuffle = false}) => _s
      ._shuffle
      .playRandomOnce(disableContinuousShuffle: disableContinuousShuffle);
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
      _s._audioOutput.setAudioPassthroughLive(enabled);
  @override
  bool get singleFileImdbFetched => _s._singleFileImdbFetched;
  @override
  String? get singleFileImdbId => _s._singleFileImdbId;
  @override
  ValueNotifier<String?> get subtitleSelectionCorrection =>
      _s._subtitleSelectionCorrection;
  @override
  Future<void> toggleContinuousShuffle() =>
      _s._shuffle.toggleContinuousShuffle();
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
  void tvReleaseFocusForOverlay() =>
      _s._controlsRuntime.tvReleaseFocusForOverlay();
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
  void togglePlay() => _s._controlsRuntime.togglePlay();
  @override
  Future<void> goToNextEpisode() => _s._episodeNext.goToNextEpisode();
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
  void scheduleAutoHide() => _s._controlsRuntime.scheduleAutoHide();
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
  void scheduleAutoHide() => _s._controlsRuntime.scheduleAutoHide();
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
  const VpS2Hooks({this.ios, this.android, this.androidRendererValidation});
  final bool Function()? ios;
  final bool Function()? android;
  final bool Function()? androidRendererValidation;
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
  static bool get isAndroidRendererValidation =>
      _installed?.androidRendererValidation?.call() ?? Platform.isAndroid;
}
