import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import '../services/playback/decoder_diagnostics.dart';
import 'video_player/services/player_terminal_backend.dart';
import 'package:debrify/services/storage/iptv_prefs.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

// Removed volume_controller; using media_kit player volume instead
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/storage_service.dart';
import '../services/local_playback_resume_resolver.dart';
import '../services/startup_stream_policy.dart';
import '../services/resume_write_guard.dart';
import '../services/skip_segment_service.dart';
import '../services/analytics_service.dart';
import '../services/pip_service.dart';
import '../services/audio_effect_session_service.dart';
import '../services/tvos_decode_remedy.dart';
import '../services/android_native_downloader.dart';
import '../widgets/recording_limit_dialogs.dart';
import '../services/profiles/profile_lock_controller.dart';
import '../services/tracking_source_policy.dart';
import '../services/cloud/cloud_provider_registry.dart';
import '../utils/platform_util.dart';
import '../utils/player_audio_config.dart';
import '../utils/time_formatters.dart';
import '../utils/series_parser.dart';
import '../utils/movie_parser.dart';
import '../services/movie_metadata_service.dart';
import '../models/iptv_playlist.dart';
import '../services/stremio_iptv_service.dart';
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../services/next_episode_service.dart';

import '../widgets/player/identify_title_sheet.dart';
import '../widgets/video_output_lease.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

// Video Player Components
import 'video_player/models/playlist_entry.dart';
import 'video_player/player_launch_config.dart';
import 'video_player/resume_controller.dart';
import 'video_player/subtitle_track_controller.dart';
import '../services/playback/iptv_recording_controller.dart';
import 'video_player/iptv_zap_controller.dart';
import 'video_player/services/subtitle_track_utils.dart';
import 'video_player/models/gesture_state.dart';
import 'video_player/models/hud_state.dart';
import 'video_player/painters/double_tap_ripple_painter.dart';
import 'video_player/utils/gesture_helpers.dart';
import 'video_player/utils/language_mapping.dart';
import 'video_player/utils/aspect_mode_utils.dart';
import 'video_player/player_presentation_controls.dart';
import 'video_player/player_transport_visibility.dart';
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
import 'video_player/widgets/debrify_tv_banner.dart';
import '../models/stremio_subtitle.dart';
import '../models/torrent.dart';
import '../models/android_video_renderer_mode.dart';
import '../services/series_source_fetcher.dart';
import '../services/scrobble/scrobble.dart';
import '../utils/tv_keys.dart';

// Re-export PlaylistEntry for backward compatibility
export 'video_player/models/playlist_entry.dart';
export 'video_player/models/channel_entry.dart';

class _ManualSourceValidationFailure implements Exception {
  const _ManualSourceValidationFailure();
}

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
  final Future<List<PlaylistEntry>?> Function(Torrent)? resolveSourceToPlaylist;
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
  PlayerLaunchConfig get config => PlayerLaunchConfig.fromWidget(widget);

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
      } catch (e) {
        return null;
      }
    }
    return _cachedSeriesPlaylist;
  }


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

  /// True when there is genuinely nothing to seek: a live channel's
  /// position/duration is just the HLS rolling window. Mirrors the signal the
  /// bar itself uses, so the keys and the UI can never disagree.
  bool get _tvNoTimeline =>
      _iptvZapBannerOwnsIdentity ||
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

  bool get _showIptvZapBanner => _zap.showBanner.value;
  bool get _iptvZapFloatingMounted => _zap.floatingMounted.value;
  set _iptvZapFloatingMounted(bool value) =>
      _zap.floatingMounted.value = value;

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

  /// Wall time we were backgrounded; a live channel resumed after more than
  /// 30s away re-tunes to the live edge instead of resuming stale bytes.
  DateTime? _backgroundedAt;

  late final IptvLiveRecovery _iptvLiveRecovery = IptvLiveRecovery(
    isEligible: _iptvRecoveryEligible,
    performRetune: _performIptvLiveRetune,
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

  /// The machine may act only on a LIVE channel with playback wanted and
  /// nobody else in charge: sleep stops outrank reconnects, a backgrounded
  /// app must stay quiet (the resume path re-arms recovery itself).
  bool _iptvRecoveryEligible() {
    if (!mounted || _screenDisposed) return false;
    final channel = _currentIptvChannel;
    if (channel == null || !channel.isLive) return false;
    if (_sleepStopLatched) return false;
    if (_sleepTimerMode == SleepTimerMode.endOfItem) return false;
    if (_pausedByLifecycle) return false;
    // An explicit user pause (including the PiP pause action) means nobody
    // asked for playback — a pending retry must not restart the channel
    // (codex round 2, finding 3).
    if (_activeMediaUserPaused) return false;
    return true;
  }

  /// Re-open the current live channel with its full identity (URL + the
  /// channel's own headers — plan finding P7). A fresh open joins the live
  /// edge. Stremio channels re-run the whole switch so their candidate
  /// ladder stays the owner of which URL plays; [IptvLiveRecovery.expectRetune]
  /// keeps the recovery episode alive across that switch's tune-start.
  void _performIptvLiveRetune(String source, int attempt) {
    final channel = _currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    _iptvDiag.onRecovery(source, 'retune', 'attempt=$attempt');
    if (StremioIptvService.isStremioChannelUrl(channel.url)) {
      // expectRetune is consumed synchronously by the switch's entry (its
      // ticket + machine bookkeeping run before any await), so no real zap
      // can pick the flag up instead.
      _iptvLiveRecovery.expectRetune = true;
      unawaited(_switchToIptvChannel(_currentIptvIndex, quietRecovery: true));
      return;
    }
    // Direct reopen path. The ticket pins this retune to the channel the
    // machine saw: a real zap bumps it and the stale retune dissolves at
    // the checks below instead of stealing playback back (codex round 2's
    // blocker).
    final ticket = _iptvSwitchTicket;
    unawaited(() async {
      // mpv makes no promise about `stream-record` across an open() — a
      // running capture must be stopped first, exactly like every other
      // media replacement path (codex round 2, finding 6).
      await _stopRecording(userInitiated: false);
      if (!mounted || ticket != _iptvSwitchTicket) return;
      _iptvDiag.onTuneStart(channel.name, channel.url, isLive: true);
      _iptvLiveRecovery.expectRetune = true;
      _iptvLiveRecovery.onTuneStarted();
      try {
        await _openMedia(
          mk.Media(channel.url, httpHeaders: channel.playbackHeaders),
          play: true,
          liveStream: true,
        );
      } catch (e) {
        debugPrint('Player: IPTV live retune failed to open: $e');
      }
    }());
  }

  IptvGuideContext? get _iptvGuideContextOverride => _zap.guideContext;

  List<IptvChannel>? get _effectiveIptvChannels => _zap.effectiveChannels;

  bool get _iptvZapBannerOwnsIdentity => _zap.bannerOwnsIdentity;

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

  String get _infoPanelSignature => _zap.infoPanelSignature(
        debrifyTvOwnsIdentity: _debrifyTvOwnsIdentity,
        currentChannelName: _currentChannelName,
        launchChannelName: widget.channelName,
        currentChannelNumber: _currentChannelNumber,
        showVideoTitle: widget.showVideoTitle,
      );

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

  StreamSubscription<mk.PlayerLog>? _subtitleDiagnosticLogSub;
  int _subtitleDiagnosticGeneration = 0;
  SubtitleApplyAttempt? _activeSubtitleApplyAttempt;
  final ValueNotifier<String?> _subtitleSelectionCorrection = ValueNotifier(
    null,
  );

  bool get _canRecord => _recording.canRecord;
  bool get _recordingActiveNow => _recording.recordingActiveNow;
  Future<void> _toggleRecording() => _recording.toggle();
  Future<void> _stopRecording({bool userInitiated = true}) =>
      _recording.stop(userInitiated: userInitiated);


  // Stremio source sheet state
  bool _showSourceSheet = false;
  int _currentSourceIndex = 0;
  List<PlaylistEntry>? _pendingSourcePlaylist;
  // Overrides for sources after Stremio TV channel switch
  List<Torrent>? _stremioSourcesOverride;
  Future<String?> Function(Torrent)? _resolveStremioSourceOverride;
  // Sources grown by the sheet's "Load more" (append-only merge over
  // widget.stremioSources; the fetcher's flags track what was searched)
  List<Torrent>? _augmentedSources;

  // Unified player menu (Spotlight panel) state. The subtitle-identity
  // context is captured at open time, exactly like the old tracks sheet
  // captured it in its `show` arguments.
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
    final value =
        _seriesPlaylist?.imdbId ??
        _syntheticGuidePlaylist?.imdbId ??
        _effectiveContentImdbId;
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  // Community intro/outro markers for the currently playing series episode.
  // The request key includes the stream duration because providers may use it
  // to distinguish releases, and timestamps are always validated against it.
  bool _skipSegmentSettingsLoaded = false;
  bool _skipSegmentsEnabled = false;
  String _skipSegmentProviderId = SkipSegmentProviders.auto;
  SkipSegmentProvider? _skipSegmentProvider;
  SkipSegments _skipSegments = SkipSegments.empty;
  String? _loadedSkipSegmentsKey;
  String? _loadingSkipSegmentsKey;
  int _skipSegmentsFetchGeneration = 0;
  final Map<String, SkipSegments> _skipSegmentsCache = <String, SkipSegments>{};

  /// Whether _position/_duration describe the item currently selected, rather
  /// than the one being switched away from. The native player's equivalent is
  /// `hasEverBeenReady`.
  ///
  /// Cleared when a playlist switch starts and set again on the first real
  /// duration for the incoming media. It cannot stick: media_kit's `open()`
  /// pushes Duration.zero to the duration stream unconditionally, so a fresh
  /// duration always follows — even when the new episode runs exactly as long
  /// as the old one.
  bool _skipSegmentsMediaReady = true;

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
  int _addonSubtitleFetchToken =
      0; // Guard against stale async fetches on content switch
  // Paths of temp SRT/VTT files we've written for addon subtitles. We hand
  // these to libmpv as file URIs so it auto-detects encoding (GBK, Big5,
  // Windows-125x, etc.) instead of our http client pre-decoding as UTF-8.
  final Set<String> _tempSubtitleFiles = {};
  String? _activeExternalSubtitlePath;
  bool _subtitleAutoSyncEnabled = false;
  MediaKitSubtitleAutoSync? _subtitleAutoSync;
  // The quiet bottom-right auto-sync surface: a 5s announce line, then
  // nothing until a real event — statuses during passes, word-only results.
  final ValueNotifier<AutoSyncPillModel?> _autoSyncPill =
      ValueNotifier<AutoSyncPillModel?>(null);
  // True from listening until a verdict/terminal hide: the engine is trying.
  bool _autoSyncWindowActive = false;
  Timer? _autoSyncPillHold; // result auto-hide
  Timer? _autoSyncPillPhaseTimer; // announce auto-dismiss
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
      _startupGateActive || _manualSourceGateActive;
  String _startupGateMessage = 'Checking stream…';
  // Blocks the autosave from filing a near-zero position over a deep resume
  // point while a requested resume seek has not landed. See ResumeWriteGuard.
  final ResumeWriteGuard _resumeWriteGuard = ResumeWriteGuard();
  late final ResumeController _resume = ResumeController(_ResumeSession(this));
  late final SubtitleTrackController _subs =
      SubtitleTrackController(_SubtitleTrackSession(this));
  late final IptvRecordingController _recording =
      IptvRecordingController(_IptvRecordingSession(this));
  late final IptvZapController _zap =
      IptvZapController(_IptvZapSession(this));
  void _runSubtitleSetState(VoidCallback updates) => setState(updates);
  void _runRecordingSetState(VoidCallback updates) => setState(updates);
  void _runZapSetState(VoidCallback updates) => setState(updates);
  // Bumped whenever the media the landing verifier is watching stops being
  // current (item change, source switch). Aborts the verifier WITHOUT
  // releasing the guard — the guard must survive through the outgoing
  // checkpoint save, which the verifier must not outlive.
  int _resumeVerifyEpoch = 0;
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
  bool _currentEpisodeMarkedAsFinished = false;
  bool _currentMovieMarkedAsFinished = false;
  bool _currentMovieRewatchStarted = false;
  int _movieCompletionThreshold =
      StorageService.defaultLocalCompletionThreshold;
  int _episodeCompletionThreshold =
      StorageService.defaultLocalCompletionThreshold;
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
  late final DecoderDiagnostics _decoderDiagnostics;

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
  final _presentation = PlayerPresentationControls();
  late final PlayerTransportVisibility _transportVisibility;

  // Aspect / speed

  // ── Sleep timer ───────────────────────────────────────────────────────────
  // Stops playback after a countdown, or at the end of the current item. The
  // wakelock already follows play state here, so pausing is enough to let the
  // screen sleep — unlike the native players, which pin the screen on.
  SleepTimerMode _sleepTimerMode = SleepTimerMode.off;

  /// When the armed countdown fires. The label is derived from this rather
  /// than from the duration picked, so it counts down instead of reading "30
  /// min" right up to the moment it stops.
  DateTime? _sleepTimerDeadline;

  /// The preset originally picked, so the sheet can keep it checked while the
  /// remaining time ticks away from it.
  int _sleepTimerArmedMinutes = 0;
  Timer? _sleepTimer;

  /// Latched from a sleep-timer stop until the user explicitly starts playback
  /// again. Advancing is asynchronous here (resolve the URL, then open), so a
  /// countdown expiring mid-flight would otherwise be undone by the episode
  /// that was already on its way.
  bool _sleepStopLatched = false;

  // Press-and-hold for 2x speed

  // Orientation
  bool _landscapeLocked = false;

  /// Whether this player should OPEN upright rather than turning the device
  /// landscape for the user (Settings → Playback → "Open the player in
  /// portrait").
  ///
  /// Phone-only on purpose. A TV has no portrait to open in, and on desktop
  /// [SystemChrome.setPreferredOrientations] does nothing — but honouring the
  /// pref there would still flip the rotate button's label to "Landscape" over
  /// a window that is already wide, describing a rotation that can't happen.
  bool get _startsInPortrait =>
      PlatformUtil.isPhone && StorageService.playerStartPortraitCached;

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

  // Scrobble: one coordinator drives Trakt, Simkl, and MDBList targets.
  late final ScrobbleCoordinator _scrobble;
  // The launched item's widget.traktProgressPercent is a first-load-only
  // signal; once spent it must not apply to a later switched-to episode.
  bool _launchTraktPercentSpent = false;
  // Per-episode Trakt cross-device progress ("season_episode" → 0-100), loaded
  // once per series; drives resume for episodes switched to in-session.
  Map<String, double>? _traktEpisodeProgress;
  bool _launchSimklPercentSpent = false;
  // Per-episode Simkl cross-device snapshot ("season_episode" → 0-100),
  // refreshed by the launcher and used when switching episodes in-session.
  Map<String, double>? _simklEpisodeProgress;
  Map<String, double>? _mdblistEpisodeProgress;
  String? _episodeTrackerProgressImdbId;
  bool _launchMdblistPercentSpent = false;
  // Keeps the analytics session alive during long, interaction-free playback.
  Timer? _analyticsHeartbeatTimer;

  Duration? _randomStartOffset(Duration duration) {
    final num clampedPercent = config.randomStartMaxPercent.clamp(0, 99);
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
    final percent = config.startAtPercent;
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
    _transportVisibility = PlayerTransportVisibility(
      visible: _controlsVisible,
      barScope: _tvBarScope,
      playPauseFocus: _tvPlayPauseFocus,
      rootFocus: _tvRootFocus,
      isMounted: () => mounted,
      anyOverlayOpen: () => _anyPlayerOverlayOpen,
      readAutoHideBlocker: () {
        final route = ModalRoute.of(context);
        return _tvScrubTarget != null ||
            !_isPlaying ||
            (route != null && !route.isCurrent) ||
            _anyPlayerOverlayOpen;
      },
      commit: setState,
    );
    _presentation.bind(
      readPlayer: () => _player,
      commit: setState,
      saveResume: () => _resume.saveResume(),
      autoHide: () => _transportVisibility.scheduleAutoHide(),
      isMounted: () => mounted,
    );
    _decoderDiagnostics = DecoderDiagnostics(
      readPlatform: () => _player.platform,
      isMounted: () => mounted,
      generation: () => _decoderProbeGeneration,
      rendererMode: () => _androidVideoRendererMode,
      remedy: () => _tvosDecodeRemedy,
      emit: _releasePlayerDiagnostic,
    );
    AnalyticsService.screenView('video_player');
    _startAnalyticsHeartbeat();
    _activePlaylist = config.playlist;
    _seriesImdbKnownAtLaunch = config.contentImdbId?.trim().isNotEmpty == true;
    // The dock and the zap banner share the bottom strip, and the dock is
    // raised from several places that never go through _transportVisibility.toggleControls
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
        unawaited(_stopRecording(userInitiated: false));
        _pauseForBackground();
      },
      onResume: _resumeFromBackground,
    );

    _recording.observeDesktopRevision();

    // Launch-time subtitles (e.g. YouTube captions): wrap into a single loaded
    // provider group so they appear in the subtitle menu without an addon
    // fetch. Grouped under the first track's source label (e.g. "YouTube").
    final initialSubs = config.initialSubtitles;
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

    // Picture-in-Picture (Android phone): once native confirms capability,
    // become the active PiP owner and listen so we can collapse chrome inside
    // the tiny window. Auto-enter is armed later, when the video is actually
    // ready (see the player `ready` callback), so pressing Home never shrinks
    // a black/loading frame. Skipped when options are hidden — that context
    // deliberately suppresses the PiP button and tap controls.
    if (Platform.isAndroid && !config.hideOptions) {
      PipService.resolveSupport().then((ok) {
        if (!mounted || !ok) return;
        PipService.attach(
          this,
          onMode: _onPipModeChanged,
          onAction: _onPipAction,
        );
        // Reveal the PiP button now that support is known.
        setState(() {});
        // If the player became ready before native support resolved, arm now.
        if (_isReady) _armPipAutoEnter();
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

    if (config.channelName != null && config.channelName!.trim().isNotEmpty) {
      _currentChannelName = config.channelName;
    }
    _currentChannelNumber = config.channelNumber;
    _currentIptvIndex = config.iptvStartIndex ?? 0;
    _currentSourceIndex = config.stremioCurrentSourceIndex ?? 0;
    _initIptvStremioSources();
    _currentStremioTvChannelId = _findInitialStremioTvChannelId();
    _parseChannelDirectory();
    // The sync offset is per-subtitle and session-scoped, but it lives in a
    // process-wide singleton — clear it at the start of every player session so
    // a previous video's offset can't leak in (mirrors the TV side's onCreate).
    SubtitleSettingsService.instance.resetSyncOffset();
    _loadSubtitleSettings();
    unawaited(_loadTrackingPolicy());
    unawaited(_loadSkipSegmentSettings());
    unawaited(_loadLocalCompletionThresholds());
    PlayerTerminalBackend.current.ensureInitialized();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // The player opens landscape — a video wants the long edge — unless the
    // user asked it to open upright, in which case the Portrait/Landscape
    // button is how they turn it. Read from the SYNCHRONOUS cache: setting
    // landscape here and correcting it once an async read lands would perform
    // the exact flip the setting exists to prevent.
    _landscapeLocked = !_startsInPortrait;
    SystemChrome.setPreferredOrientations(
      _landscapeLocked
          ? const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const <DeviceOrientation>[DeviceOrientation.portraitUp],
    );
    // Held for the LOADING phase only — a slow debrid resolve must not let
    // the screen sleep before the first frame. From the first playing event
    // onward the lock follows play/pause (see _syncWakelock).
    try {
      WakelockPlus.enable();
    } catch (_) {
      // Wakelock not supported on this platform (e.g., Linux)
    }
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

    // Check if Trakt/Simkl/MDBList scrobbling should be enabled for this playback
    final scrobblePlayback = ScrobblePlayback(
      imdbIdOf: () => config.contentImdbId,
      contentTypeOf: () => config.contentType,
      durationOf: () => _duration,
      positionOf: () => _position,
      persistablePositionOf: () => _persistablePosition,
      isPlayingOf: () => _isPlaying,
      validationGateActiveOf: () => _validationGateActive,
      mountedOf: () => mounted,
      seasonEpisodeOf: _traktSeasonEpisode,
    );
    _scrobble = ScrobbleCoordinator(
      playback: scrobblePlayback,
      targets: [
        TraktScrobbleTarget.production(
          requested: config.traktScrobble,
          playback: scrobblePlayback,
        ),
        SimklScrobbleTarget.production(
          requested: config.simklScrobble,
          playback: scrobblePlayback,
        ),
        MdblistScrobbleSessionTarget.production(
          requested: config.mdblistScrobble,
          playback: scrobblePlayback,
          playerReady: _playerInitializationFuture,
        ),
      ],
    );
    _scrobble.init();
  }

  Future<void> _loadSkipSegmentSettings() async {
    final values = await Future.wait<Object>([
      StorageService.getSkipSegmentsEnabled(),
      StorageService.getSkipSegmentProvider(),
    ]);
    if (!mounted) return;

    final enabled = values[0] as bool;
    final storedProvider = values[1] as String;
    final providerId = SkipSegmentProviders.isAvailable(storedProvider)
        ? storedProvider
        : SkipSegmentProviders.auto;

    _skipSegmentProvider?.close();
    _skipSegmentProvider = enabled
        ? SkipSegmentProviders.create(providerId)
        : null;
    _skipSegmentsEnabled = enabled;
    _skipSegmentProviderId = providerId;
    _skipSegmentSettingsLoaded = true;
    _syncSkipSegmentsForCurrentContent();
  }

  Future<void> _loadLocalCompletionThresholds() async {
    final values = await Future.wait<int>([
      PlaybackProgressStore.getMovieCompletionThreshold(),
      PlaybackProgressStore.getEpisodeCompletionThreshold(),
    ]);
    if (!mounted) return;
    _movieCompletionThreshold = values[0];
    _episodeCompletionThreshold = values[1];
    // A seek can cross the default threshold before the preference read
    // finishes. Re-evaluate against the configured value once it arrives.
    _checkAndApplyLocalCompletion();
  }

  bool get _usesLocalCompletionTracking =>
      (_forceLocalCompletionTracking ||
          (!widget.traktScrobble &&
              !widget.simklScrobble &&
              !widget.mdblistScrobble)) &&
      widget.stremioTvChannels == null &&
      _effectiveIptvChannels == null;

  bool _forceLocalCompletionTracking = false;

  Future<void> _loadTrackingPolicy() async {
    final policy = await TrackingSourcePolicy.load();
    if (!mounted) return;
    _forceLocalCompletionTracking = policy.forcesLocalCompletion;
    // A very short item can cross its completion threshold before this async
    // profile read returns. Re-evaluate immediately so This-device mode never
    // misses the forced-local rule merely because scrobbling is also enabled.
    _checkAndApplyLocalCompletion();
  }

  String? get _currentLocalMovieImdbId {
    if (_effectiveContentType != 'movie') return null;
    final imdbId = _effectiveContentImdbId?.trim();
    return imdbId == null || imdbId.isEmpty ? null : imdbId;
  }

  void _resetLocalCompletionState() {
    _currentEpisodeMarkedAsFinished = false;
    _currentMovieMarkedAsFinished = false;
    _currentMovieRewatchStarted = false;
  }

  ({String imdbId, int season, int episode, Duration duration, String key})?
  _currentSkipSegmentRequest() {
    // Two stale-media windows, both of which would judge the incoming item
    // against the outgoing one's clock:
    //
    // * _skipSegmentsMediaReady covers a playlist switch. _loadPlaylistIndex
    //   points _currentIndex at the new episode and only then saves resume and
    //   resolves the stream URL — a network round trip for debrid/PikPak
    //   links. Through all of that _position/_duration still describe the
    //   outgoing episode, and that position is usually deep enough to land
    //   inside a segment, so the button flashes on the moment next-episode is
    //   pressed. It also asks the provider for the new episode at the old
    //   episode's duration, which can select or validate the wrong release.
    // * _isTransitioning covers an IPTV zap / source switch, where the key
    //   flips before the incoming stream opens (the same window _saveResume
    //   guards against).
    if (!_skipSegmentSettingsLoaded ||
        !_skipSegmentsEnabled ||
        !_skipSegmentsMediaReady ||
        _isTransitioning ||
        _duration <= Duration.zero) {
      return null;
    }

    final seriesPlaylist = _seriesPlaylist;
    final isSeries =
        _effectiveContentType == 'series' || seriesPlaylist?.isSeries == true;
    if (!isSeries) return null;

    var imdbId = _effectiveContentImdbId?.trim();
    if (imdbId == null || !RegExp(r'^tt\d+$').hasMatch(imdbId)) {
      imdbId = seriesPlaylist?.imdbId?.trim();
    }
    if (imdbId == null || !RegExp(r'^tt\d+$').hasMatch(imdbId)) return null;

    int? season;
    int? episode;
    if (seriesPlaylist?.isSeries == true) {
      final current = _findSeriesEpisodeForCurrentIndex(seriesPlaylist!);
      season = current?.seriesInfo.season;
      episode = current?.seriesInfo.episode;
    }
    season ??= _effectiveContentSeason;
    episode ??= _effectiveContentEpisode;
    if (season == null || episode == null) {
      final parsed = _traktSeasonEpisode();
      season ??= parsed.season;
      episode ??= parsed.episode;
    }
    if (season == null || episode == null || season < 0 || episode < 1) {
      return null;
    }

    final durationSeconds = _duration.inSeconds;
    final key =
        '$_skipSegmentProviderId:$imdbId:$season:$episode:$durationSeconds';
    return (
      imdbId: imdbId,
      season: season,
      episode: episode,
      duration: _duration,
      key: key,
    );
  }

  void _syncSkipSegmentsForCurrentContent() {
    final request = _currentSkipSegmentRequest();
    final provider = _skipSegmentProvider;
    if (request == null || provider == null) return;
    if (_loadedSkipSegmentsKey == request.key ||
        _loadingSkipSegmentsKey == request.key) {
      return;
    }

    if (_skipSegmentsCache.containsKey(request.key)) {
      final cached = _skipSegmentsCache[request.key]!;
      if (mounted) {
        setState(() {
          _skipSegments = cached;
          _loadedSkipSegmentsKey = request.key;
        });
        _syncActiveSkipSegmentUi();
      }
      return;
    }

    final generation = ++_skipSegmentsFetchGeneration;
    _loadingSkipSegmentsKey = request.key;
    provider
        .fetch(
          imdbId: request.imdbId,
          season: request.season,
          episode: request.episode,
          duration: request.duration,
        )
        .then((segments) {
          _skipSegmentsCache[request.key] = segments;
          if (!mounted || generation != _skipSegmentsFetchGeneration) return;
          if (_currentSkipSegmentRequest()?.key != request.key) return;
          setState(() {
            _skipSegments = segments;
            _loadedSkipSegmentsKey = request.key;
          });
          _syncActiveSkipSegmentUi();
        })
        .catchError((Object error) {
          // Missing skip data must never affect playback. Cache the miss for
          // this session so an offline API cannot be retried on every position
          // tick.
          _skipSegmentsCache[request.key] = SkipSegments.empty;
          debugPrint(
            'SkipSegments: ${provider.displayName} fetch failed: $error',
          );
          if (!mounted || generation != _skipSegmentsFetchGeneration) return;
          if (_currentSkipSegmentRequest()?.key != request.key) return;
          setState(() {
            _skipSegments = SkipSegments.empty;
            _loadedSkipSegmentsKey = request.key;
          });
          _syncActiveSkipSegmentUi();
        })
        .whenComplete(() {
          if (_loadingSkipSegmentsKey == request.key) {
            _loadingSkipSegmentsKey = null;
          }
        });
  }

  /// Forget the outgoing item's skip segments when switching playlist entries,
  /// and stop reading its clock until the incoming one opens. The native TV
  /// player does the same in playItem.
  ///
  /// The fetch cache survives on purpose: it's keyed per episode, so going
  /// back to one already looked up is instant.
  void _resetSkipSegmentState() {
    _skipSegmentsFetchGeneration++;
    _loadingSkipSegmentsKey = null;
    _loadedSkipSegmentsKey = null;
    _skipSegments = SkipSegments.empty;
    _skipSegmentsMediaReady = false;
    _activeSkipSegmentUi.clear();
  }

  SkipSegment? get _activeSkipSegment {
    final request = _currentSkipSegmentRequest();
    if (request == null || request.key != _loadedSkipSegmentsKey) return null;
    return _skipSegments.segmentAt(_position);
  }

  void _syncActiveSkipSegmentUi() {
    _activeSkipSegmentUi.update(_activeSkipSegment);
  }

  void _skipActiveSegment() {
    final segment = _activeSkipSegment;
    if (segment == null || !_playerCreated) return;
    final target = _duration > Duration.zero && segment.end > _duration
        ? _duration
        : segment.end;
    _position = target;
    _playbackUiClock.updatePosition(target, immediate: true);
    _syncActiveSkipSegmentUi();
    unawaited(_player.seek(target));
    _scrobbleSeek(target);
    HapticFeedback.selectionClick();
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
    if (config.contentType == 'movie') {
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
    if (config.contentSeason != null && config.contentEpisode != null) {
      return (season: config.contentSeason, episode: config.contentEpisode);
    }
    final info = SeriesParser.parseFilename(config.title);
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

  /// Shared funnel every user-initiated seek passes through (scrubber,
  /// tap/DPAD seek, pan, skip-segment). The resume write guard learns the
  /// user has taken over the position before any tracker-specific early
  /// return — the handover happens whether or not a tracker is connected.
  void _scrobbleSeek(Duration seekTarget) {
    _resumeWriteGuard.noteUserSeek();
    _scrobble.onSeek(seekTarget);
  }

  void _resumeTrackingAfterValidationGate() {
    _scrobble.resumeAfterValidationGate();
  }

  /// The current episode's cross-device Trakt progress percent (0-100), or null.
  /// Loaded once per series from the dedicated store (kept apart from the
  /// ms-based resume state) and looked up by the current episode's season/episode.
  void _bindEpisodeTrackerProgressIdentity(String imdbId) {
    if (_episodeTrackerProgressImdbId == imdbId) return;
    _episodeTrackerProgressImdbId = imdbId;
    _traktEpisodeProgress = null;
    _simklEpisodeProgress = null;
    _mdblistEpisodeProgress = null;
  }

  Future<double?> _currentEpisodeTraktPercent({bool forGuide = false}) async {
    final policy = await TrackingSourcePolicy.load();
    if (!forGuide && !policy.progressFrom(TrackingSource.trakt)) return null;
    final imdbId = _currentSeriesImdbId;
    if (imdbId == null) return null;
    _bindEpisodeTrackerProgressIdentity(imdbId);

    // Await BEFORE reading _currentIndex/season/episode below, so that if the
    // user advances to a different episode while this is in flight, we key
    // off the episode that's actually current when the fetch resolves.
    if (_traktEpisodeProgress == null) {
      final loaded = await PlaybackProgressStore.getEpisodeTraktProgress(
        imdbId: imdbId,
      );
      if (_episodeTrackerProgressImdbId != imdbId) return null;
      _traktEpisodeProgress = loaded;
    }

    int? season;
    int? episode;
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlist = _activePlaylist;
      if (playlist == null ||
          _currentIndex < 0 ||
          _currentIndex >= playlist.length) {
        return null;
      }
      // Must be the CURRENT episode — no orElse-to-first fallback, or we'd seek to
      // an unrelated episode's Trakt position on filtered/reordered playlists.
      SeriesEpisode? ep;
      for (final e in seriesPlaylist.allEpisodes) {
        if (e.originalIndex == _currentIndex) {
          ep = e;
          break;
        }
      }
      if (ep == null) return null;
      season = ep.seriesInfo.season;
      episode = ep.seriesInfo.episode;
    } else if (_effectiveContentType == 'series') {
      // Single-file episode (e.g. a direct-link stream) — no playlist to derive
      // season/episode from; fall back to the same launch args the local
      // resume-state lookup uses.
      season = _effectiveContentSeason;
      episode = _effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;

    final percent = _traktEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.trakt, percent)
        : percent;
  }

  /// Current episode's Simkl snapshot percent. This mirrors the Trakt lookup
  /// above but remains independently stored so remote unwatch changes never
  /// mutate local playback history.
  Future<double?> _currentEpisodeSimklPercent({bool forGuide = false}) async {
    final policy = await TrackingSourcePolicy.load();
    if (!forGuide && !policy.progressFrom(TrackingSource.simkl)) return null;
    final imdbId = _currentSeriesImdbId;
    if (imdbId == null) return null;
    _bindEpisodeTrackerProgressIdentity(imdbId);

    // Await before resolving the episode identity for the same race-safety as
    // [_currentEpisodeTraktPercent].
    if (_simklEpisodeProgress == null) {
      final loaded = await PlaybackProgressStore.getEpisodeSimklProgress(
        imdbId: imdbId,
      );
      if (_episodeTrackerProgressImdbId != imdbId) return null;
      _simklEpisodeProgress = loaded;
    }

    int? season;
    int? episode;
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlist = _activePlaylist;
      if (playlist == null ||
          _currentIndex < 0 ||
          _currentIndex >= playlist.length) {
        return null;
      }
      SeriesEpisode? currentEpisode;
      for (final candidate in seriesPlaylist.allEpisodes) {
        if (candidate.originalIndex == _currentIndex) {
          currentEpisode = candidate;
          break;
        }
      }
      if (currentEpisode == null) return null;
      season = currentEpisode.seriesInfo.season;
      episode = currentEpisode.seriesInfo.episode;
    } else if (_effectiveContentType == 'series') {
      season = _effectiveContentSeason;
      episode = _effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;

    final percent = _simklEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.simkl, percent)
        : percent;
  }

  Future<double?> _currentEpisodeMdblistPercent({bool forGuide = false}) async {
    final policy = await TrackingSourcePolicy.load();
    if (!forGuide && !policy.progressFrom(TrackingSource.mdblist)) return null;
    final imdbId = _currentSeriesImdbId;
    if (imdbId == null) return null;
    _bindEpisodeTrackerProgressIdentity(imdbId);
    if (_mdblistEpisodeProgress == null) {
      final loaded = await PlaybackProgressStore.getEpisodeMdblistProgress(
        imdbId: imdbId,
      );
      if (_episodeTrackerProgressImdbId != imdbId) return null;
      _mdblistEpisodeProgress = loaded;
    }
    final se = _traktSeasonEpisode();
    if (se.season == null || se.episode == null) return null;
    final percent = _mdblistEpisodeProgress!['${se.season}_${se.episode}'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.mdblist, percent)
        : percent;
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
    final terminal = PlayerTerminalBackend.current;
    final player = terminal.createPlayer(
      configuration: mk.PlayerConfiguration(
        logLevel: mk.MPVLogLevel.error,
        ready: () => _onPlayerInstanceReady(instanceGeneration),
      ),
    );
    _player = player;
    _playerCreated = true;
    _videoController = terminal.createVideoController(
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
    unawaited(_presentation.applyAspectVideoZoom());
  }

  void _installSubtitleAutoSyncForPlayer(mk.Player player) {
    if (!_subtitleAutoSyncEnabled || !PlatformUtil.supportsSubtitleAutoSync) {
      debugPrint(
        'SubtitleAutoSync: not installing — enabled=$_subtitleAutoSyncEnabled '
        'web=$kIsWeb platform=${Platform.operatingSystem}',
      );
      return;
    }
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      debugPrint(
        'SubtitleAutoSync: not installing — player backend is not NativePlayer '
        '(${platform.runtimeType})',
      );
      return;
    }
    debugPrint(
      'SubtitleAutoSync: controller installed '
      '(passthrough=${!kIsWeb && Platform.isAndroid && _audioPassthroughEnabled})',
    );
    _subtitleAutoSync = MediaKitSubtitleAutoSync(
      player: platform,
      enabled: _subtitleAutoSyncEnabled,
      passthroughEnabled:
          !kIsWeb && Platform.isAndroid && _audioPassthroughEnabled,
      currentPositionMs: () => _position.inMilliseconds,
      isPlaying: () => _isPlaying,
      currentOffsetMs: () => _subtitleSettings?.syncOffsetMs ?? 0,
      applyOffsetMs: _applyAutoSubtitleSyncOffset,
      onNotice: _showSubtitleAutoSyncNotice,
    );
  }

  Future<void> _disposeSubtitleAutoSync() async {
    final controller = _subtitleAutoSync;
    _subtitleAutoSync = null;
    _hideAutoSyncPill();
    await controller?.dispose();
  }

  Future<void> _applyAutoSubtitleSyncOffset(int milliseconds) async {
    final clamped = milliseconds.clamp(
      SubtitleSettingsService.syncOffsetMinMs,
      SubtitleSettingsService.syncOffsetMaxMs,
    );
    if (!mounted) return;
    _subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: clamped);
    _applySubtitleSyncOffset(clamped);
    setState(() {});
    try {
      await SubtitleSettingsService.instance.setSyncOffsetMs(clamped);
    } catch (error) {
      // The live player already has the safe, bounded offset. A preference
      // write failure must not escape a timer callback or affect playback.
      debugPrint('SubtitleAutoSync: offset persistence failed: $error');
    }
  }

  void _showSubtitleAutoSyncNotice(SubtitleAutoSyncNotice notice) {
    if (!mounted) return;
    // Full detail (offsets, advice) lives here; the pill stays number-free.
    debugPrint('SubtitleAutoSync: ${notice.message}');
    switch (notice.kind) {
      case SubtitleAutoSyncNoticeKind.listening:
        // A fresh window: announce for ~5s, then go quiet until an event.
        _openAutoSyncPillWindow();
      case SubtitleAutoSyncNoticeKind.checking:
        // An alignment pass is genuinely running — surface it, even if the
        // pill was idle-hidden in the meantime.
        if (_autoSyncWindowActive) {
          _autoSyncPillPhaseTimer?.cancel();
          _autoSyncPill.value = const AutoSyncPillModel(
            AutoSyncPillPhase.checking,
          );
        }
      case SubtitleAutoSyncNoticeKind.stillListening:
        // The pass ended with no verdict: leave the screen quiet again.
        if (_autoSyncWindowActive &&
            _autoSyncPill.value?.phase == AutoSyncPillPhase.checking) {
          _autoSyncPill.value = null;
        }
      case SubtitleAutoSyncNoticeKind.synced ||
          SubtitleAutoSyncNoticeKind.resynced:
        // A verify-pass re-sync corrects silently; only the first sync speaks.
        if (notice.kind == SubtitleAutoSyncNoticeKind.resynced &&
            !_autoSyncWindowActive &&
            _autoSyncPill.value == null) {
          return;
        }
        _showAutoSyncPillResult(AutoSyncPillPhase.synced);
      case SubtitleAutoSyncNoticeKind.failed:
        _showAutoSyncPillResult(AutoSyncPillPhase.failed);
    }
  }

  void _openAutoSyncPillWindow() {
    _autoSyncPillHold?.cancel();
    _autoSyncPillHold = null;
    _autoSyncWindowActive = true;
    _autoSyncPill.value = const AutoSyncPillModel(AutoSyncPillPhase.announce);
    _autoSyncPillPhaseTimer?.cancel();
    _autoSyncPillPhaseTimer = Timer(const Duration(seconds: 5), () {
      // The sentence had its moment; the screen goes quiet until a real
      // event (a checking pass or a verdict) has something to say.
      if (_autoSyncWindowActive &&
          _autoSyncPill.value?.phase == AutoSyncPillPhase.announce) {
        _autoSyncPill.value = null;
      }
    });
  }

  void _showAutoSyncPillResult(AutoSyncPillPhase phase) {
    _autoSyncWindowActive = false;
    _autoSyncPillPhaseTimer?.cancel();
    _autoSyncPillPhaseTimer = null;
    _autoSyncPillHold?.cancel();
    _autoSyncPill.value = AutoSyncPillModel(phase);
    _autoSyncPillHold = Timer(
      const Duration(milliseconds: 2400),
      _hideAutoSyncPill,
    );
  }

  void _hideAutoSyncPill() {
    _autoSyncWindowActive = false;
    _autoSyncPillPhaseTimer?.cancel();
    _autoSyncPillPhaseTimer = null;
    _autoSyncPillHold?.cancel();
    _autoSyncPillHold = null;
    if (_autoSyncPill.value != null) _autoSyncPill.value = null;
  }

  void _setActiveExternalSubtitlePath(String? path) {
    if (_activeExternalSubtitlePath == path) return;
    _activeExternalSubtitlePath = path;
    final controller = _subtitleAutoSync;
    debugPrint(
      'SubtitleAutoSync: external subtitle ${path == null ? 'cleared' : 'set'} '
      '(controller=${controller == null ? 'MISSING' : 'present'})',
    );
    if (controller == null) return;
    if (path == null) {
      unawaited(controller.deactivateSubtitle());
      _hideAutoSyncPill();
    } else {
      unawaited(controller.activateSubtitle(path));
    }
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
      await StorageService.setAudioPassthroughEnabled(enabled);
      // An audio filter would force compressed passthrough formats through a
      // PCM decoder. Remove the passive analysis chain before the aid cycle;
      // when passthrough is disabled, re-arm only after PCM output is restored.
      if (enabled) {
        await _subtitleAutoSync?.setPassthroughEnabled(true);
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
        await _subtitleAutoSync?.setPassthroughEnabled(false);
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
      final lang = await StorageService.getDefaultAudioLanguage();
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
        if (mounted) _decoderDiagnostics.schedule();
      },
    );
  }

  void _onPlayerInstanceReady(int instanceGeneration) {
    if (!mounted || instanceGeneration != _playerInstanceGeneration) return;
    _isReady = true;
    _armPipAutoEnter();
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
      _transportVisibility.cancelAutoHide();
      _controlsVisible.value = false;
      _zap.prepareBannerData(iptvChannel);
      _zap.raiseBanner();
      _zap.anchorGuideCategory(iptvChannel);
      _zap.ensurePagingArmed();
    } else {
      _raiseDebrifyBanner();
    }
  }

  Future<void> _initializePlayer() async {
    // Load default player settings
    await _loadPlayerDefaults();
    unawaited(_loadDockPrefs());
    if (Platform.isAndroid && !PlatformUtil.isAndroidTvCached) {
      _androidVideoRendererMode =
          await StorageService.getAndroidVideoRendererMode();
    }

    // Determine the initial URL and index
    String initialUrl = config.videoUrl;
    var initialRankedAttemptFailed = false;
    int initialIndex = 0;

    if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
      // Initialize playlist

      // If auto-resume is disabled, use startIndex directly
      if (config.disableAutoResume) {
        initialIndex = config.startIndex ?? 0;
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
              config.contentSeason != null && config.contentEpisode != null;
          if (hadExplicitTarget) {
            final targetIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(
              config.contentSeason!,
              config.contentEpisode!,
            );
            if (targetIndex != -1) {
              initialIndex = targetIndex;
              targetEpisodeResolved = true;
              debugPrint(
                'VideoPlayer: target episode S${config.contentSeason}E${config.contentEpisode} → index=$initialIndex',
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
                initialIndex = config.startIndex ?? 0;
              }
              debugPrint(
                'VideoPlayer: no resume target for "${seriesPlaylist.seriesTitle}"'
                '${hadExplicitTarget ? ' (requested S${config.contentSeason}E${config.contentEpisode} not in pack)' : ''}, defaulting to index=$initialIndex',
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
              final resumeId = _resume.idForEntry(entry);
              debugPrint(
                'Resume: checking entry[$i] title="${entry.title}" resumeId=$resumeId',
              );
              final state = await StorageService.getVideoPlaybackState(
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
                  : (config.startIndex ?? 0);
            }
          } else {
            // Not a series or no series playlist, use the provided startIndex
            initialIndex = config.startIndex ?? 0;
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
          } else if (config.videoUrl.isNotEmpty) {
            initialUrl = config.videoUrl;
          } else {
            initialRankedAttemptFailed = true;
          }
        } catch (e) {
          // Only fall back to widget.videoUrl if resolution fails
          if (config.videoUrl.isNotEmpty) {
            initialUrl = config.videoUrl;
          } else {
            initialRankedAttemptFailed = true;
          }
        }
      }
    }

    _currentIndex = initialIndex;
    _dynamicTitle = config.title;
    await _claimVideoOutput();
    if (!mounted) return;
    _createPlayerInstance(_androidVideoRendererMode);
    await _configurePlayerAudio(_player);
    _installSubtitleAutoSyncForPlayer(_player);
    _recording.probeSupport();

    // Must happen before the first open() — mpv reads both audio options when
    // it creates the audio output, which is on first playback.
    await _attachAudioEffectSession();

    _currentStreamUrl = initialUrl.isNotEmpty ? initialUrl : null;

    // IPTV launch: the first tune starts here, before either open branch
    // below (IPTV is never PikPak). Zaps re-arm this in _switchToIptvChannel.
    var launchIsLiveIptv = false;
    final launchIptvChannels = _effectiveIptvChannels;
    if (launchIptvChannels != null && initialUrl.isNotEmpty) {
      final launchIdx = config.iptvStartIndex ?? 0;
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
      final isDebrifyTV = isPikPakUrl && config.requestMagicNext != null;

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
          if (config.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              // A random start has no bookmark to protect — plain seek.
              await _player.seek(offset);
            } else {
              await _resume.maybeRestoreResume(verifyLanding: true);
            }
          } else if (config.startAtPercent != null) {
            final offset = _percentStartOffset(_duration);
            if (offset != null) {
              await _resume.seekForResume(offset.inMilliseconds, verifyLanding: true);
            }
          } else {
            await _resume.maybeRestoreResume(verifyLanding: true);
          }
          if (!pikpakStillCurrent()) return;
          // Restore audio and subtitle track preferences
          await _subs.restoreTrackPreferences();
        });
      } else {
        // High-res YouTube serves video and audio as separate streams. Open
        // PAUSED, attach the external audio track, then start — so both tracks
        // are loaded before the first frame and play in sync from the start.
        // (Attaching audio mid-playback makes mpv resync, causing a few seconds
        // of A/V drift.)
        final hasExternalAudio =
            config.audioUrl != null && config.audioUrl!.isNotEmpty;
        try {
          final plainOpen =
              initialUrl.isNotEmpty && (hasExternalAudio || launchIsLiveIptv);
          final opened = plainOpen
              ? await (() async {
                  await _openMedia(
                    mk.Media(initialUrl, httpHeaders: config.httpHeaders),
                    play: !hasExternalAudio,
                    desiredPlay: true,
                    liveStream: launchIsLiveIptv,
                  );
                  return true;
                })()
              : await _openInitialVodWithFailover(
                  initialUrl,
                  httpHeaders: config.httpHeaders,
                  initialAttemptAlreadyFailed: initialRankedAttemptFailed,
                );
          if (!opened) {
            if (mounted) {
              final canRecover = config.onStartupSourcesExhausted != null;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    canRecover
                        ? 'Saved source failed. Looking for another source…'
                        : 'No playable source could be started.',
                  ),
                ),
              );
              // Keep hold of this exact route: a dialog may briefly cover the
              // player while the failure message is visible. Wait for that
              // dialog to leave, but abandon the pending pop if the player
              // itself was dismissed, so an underlying detail route can never
              // be popped by this delayed callback.
              final playerRoute = ModalRoute.of(context);
              await Future<void>.delayed(
                Duration(milliseconds: canRecover ? 250 : 900),
              );
              while (mounted && playerRoute?.isActive == true) {
                if (playerRoute?.isCurrent == true) break;
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
              if (mounted && playerRoute?.isCurrent == true) {
                if (canRecover) {
                  Navigator.of(
                    context,
                  ).pop(<String, dynamic>{'startupSourcesExhausted': true});
                } else {
                  Navigator.of(context).maybePop();
                }
              }
            }
            return;
          }
          // Wait for duration-dependent resume and random-start calculations.
          await _waitForVideoReady();
          if (hasExternalAudio) {
            await _setExternalAudioTrack(config.audioUrl!);
          }
          // Random start takes precedence over resume, then startAtPercent.
          if (config.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              // A random start has no bookmark to protect and no "correct"
              // position to verify against — plain seek, as before.
              await _player.seek(offset);
            } else {
              await _resume.maybeRestoreResume(verifyLanding: true);
            }
          } else if (config.startAtPercent != null) {
            final offset = _percentStartOffset(_duration);
            if (offset != null) {
              // An explicit promised start position, exposed to the same
              // startup seek failure as a stored resume.
              await _resume.seekForResume(offset.inMilliseconds, verifyLanding: true);
            }
          } else {
            await _resume.maybeRestoreResume(verifyLanding: true);
          }
          _transportVisibility.scheduleAutoHide();
          await _subs.restoreTrackPreferences();
          if (hasExternalAudio) await _player.play();
          // The candidate is now decoded, resume has been applied, and track
          // restoration is complete. Only now may progress escape to local
          // completion or remote scrobblers.
          _setStartupGateActive(false);
          _resumeTrackingAfterValidationGate();
        } catch (e) {
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
      (_) => _resume.saveResume(debounced: true),
    );

    // Preload episode information if this is a series
    _episodeMetadataReady ??= _preloadEpisodeInfo();
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
        unawaited(_subs.handleSubtitleApplyFailure(attempt, log.text));
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
      _subtitleAutoSync?.observePosition(d.inMilliseconds);
      _iptvDiag.onProgress(d, playing: _isPlaying);
      // _isPlaying tracks mpv's pause property: a cache-stall keeps it true
      // (stall detector armed), a user pause flips it false (excluded).
      if (_effectiveIptvChannels != null) {
        _iptvLiveRecovery.onProgress(d, wantsPlayback: _isPlaying);
      }
      _position = d;
      _scrobble.updatePosition();
      _playbackUiClock.updatePosition(d);
      _syncSkipSegmentsForCurrentContent();
      _syncActiveSkipSegmentUi();
      _checkAndApplyLocalCompletion();
    });
    if (_subtitleAutoSyncEnabled) {
      var lastAudioTrackId = player.state.track.audio.id;
      _trackSub = player.stream.track.listen((track) {
        if (!isCurrent()) return;
        final audioTrackId = track.audio.id;
        if (audioTrackId != lastAudioTrackId) {
          lastAudioTrackId = audioTrackId;
          _subtitleAutoSync?.audioTrackChanged();
        }
      });
    }
    _durSub = player.stream.duration.listen((d) {
      if (!isCurrent()) return;
      final hadDuration = _duration > Duration.zero;
      _duration = d;
      _scrobble.updatePosition();
      // `playing=true` commonly arrives before libmpv publishes duration. In
      // that ordering the playing listener cannot arm MDBList, and no second
      // playing event is guaranteed. Treat the first usable duration as the
      // missing edge so the initial durable pause checkpoint is sent.
      if (!hadDuration && d > Duration.zero && _isPlaying) {
        _scrobble.onDurationBecameReady();
      }
      _playbackUiClock.updateDuration(d);
      if (d > Duration.zero) _skipSegmentsMediaReady = true;
      _syncSkipSegmentsForCurrentContent();
      _syncActiveSkipSegmentUi();
      setState(() {});
    });
    _playSub = player.stream.playing.listen((p) {
      if (!isCurrent()) return;
      if (p && _pausedByLifecycle && !_isPipActive) {
        unawaited(player.pause());
        return;
      }
      final wasPlaying = _isPlaying;
      _isPlaying = p;
      ProfileLockController.instance.setPlaybackActive(p);
      _syncWakelock(p);
      _pushPipState();
      if (p) _noteLiveChannelPlaying();
      _scrobble.onPlaying(
        p,
        wasPlaying: wasPlaying,
        isTransitioning: _isTransitioning,
      );
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
        _iptvDiag.onPlaybackEnded(_position);
        _onPlaybackEnded();
      }
    });
    _bufferingSub = player.stream.buffering.listen((isBuffering) {
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
        if (isCurrent()) _onIptvStreamError(error);
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

  void _handleDecoderProbeParams(mk.VideoParams params) {
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0) {
      // Player.open() normally resets VideoParams before loading the next item.
      // Treat it as an extra invalidation signal, but do not require it: the
      // app-owned generation started in _openMedia is the session boundary.
      _decoderDiagnostics.invalidateParams();
      _rendererStartupGuardToken++;
      _rendererStartupValidationGeneration = -1;
      return;
    }
    _decoderDiagnostics.updateParams(params);
    _scheduleRendererStartupValidation();
    final remedy = _tvosDecodeRemedy;
    if (remedy != null) {
      // Only ever STARTS the ladder (from idle, on a triggering format) —
      // the ladder's own transitional events are ignored inside it.
      unawaited(remedy.evaluate(params, _decoderProbeGeneration));
    }
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
          _decoderDiagnostics.schedule();
        }
      });
    } catch (_) {
      // The one-shot query below still works if this property is unavailable.
    }
    try {
      await platform.observeProperty('current-vo', (value) async {
        if (mounted && instanceGeneration == _playerInstanceGeneration) {
          _decoderDiagnostics.schedule();
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

  Future<void> _fallbackExplicitRendererToAutomatic({
    required int instanceGeneration,
    required int mediaGeneration,
    required String reason,
  }) async {
    if (!AndroidRendererStartupFallback.shouldArm(
          isAndroid: Platform.isAndroid,
          isAndroidTv: PlatformUtil.isAndroidTvCached,
          mode: _androidVideoRendererMode,
          alreadyValidated: _rendererValidatedForSession,
          fallbackInProgress: _rendererFallbackInProgress,
        ) ||
        !mounted ||
        instanceGeneration != _playerInstanceGeneration ||
        mediaGeneration != _decoderProbeGeneration ||
        _activeOpenedMedia == null ||
        _recording.isTeeRecording ||
        _iptvErrorsMuted ||
        _isTransitioning) {
      return;
    }

    _rendererFallbackInProgress = true;
    _rendererStartupGuardToken++;
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
      await _disposeSubtitleAutoSync();
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
        await StorageService.setAndroidVideoRendererMode(
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
      _installSubtitleAutoSyncForPlayer(_player);
      await _attachAudioEffectSession();
      if (!mounted) return;
      setState(() {});

      final needsPreparation =
          hasExternalAudio || (!isLive && resumePosition > Duration.zero);
      final playOnOpen =
          shouldResumePlayback && !_pausedByLifecycle && !needsPreparation;
      await _openMedia(
        media,
        play: playOnOpen,
        desiredPlay: shouldResumePlayback,
        // The recreated player starts with a clean property set — without
        // this a live channel would silently lose its ffmpeg reconnect
        // options at the renderer fallback (codex round 2, finding 16).
        liveStream: isLive,
      );
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
        await _resume.seekForResume(resumePosition.inMilliseconds);
      }
      unawaited(_subs.restoreTrackPreferences());
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
    } finally {
      _rendererFallbackInProgress = false;
    }
  }

  void _beginMediaGeneration() {
    _decoderProbeGeneration++;
    _decoderDiagnostics.invalidateToken();
    _rendererStartupGuardToken++;
    _rendererStartupValidationGeneration = -1;
    _decoderDiagnostics.clearForMedia();
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
  }) async {
    // EVERY content open invalidates the outgoing media's resume protection —
    // the one choke point all switch paths share, so no path (Stremio TV
    // channel, Magic TV next, zap, source switch, startup ladder) can leave a
    // stale guard suppressing the new media's saves or a live verifier
    // re-seeking the old target against it. Ordering is safe by construction:
    // every outgoing checkpoint save runs BEFORE its new open, and every path
    // that re-protects (_seekForResume) re-arms AFTER it.
    _resumeVerifyEpoch++;
    unawaited(_resume.cancelResumeVerification());
    _resumeWriteGuard.clear();
    _activeOpenedMedia = media;
    _activeMediaShouldPlay = desiredPlay ?? play;
    _activeMediaUserPaused = false;
    _beginMediaGeneration();
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
        await platform.setProperty('sub-visibility', 'no');
      } catch (error) {
        debugPrint('Player: subtitle visibility reset failed: $error');
      }
    }
    return _player.open(media, play: play);
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

  void _showSubtitleFailureMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
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
      final lastEpisode = await PlaybackProgressStore.getLastPlayedEpisode(
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
    _scrobble.onEnded();

    // Mark the current episode as finished if it's a series
    await _markCurrentEpisodeAsFinished();
    // A locally tracked movie may finish before the next periodic position
    // save; make EOF a completion too (tracker sessions keep their existing
    // scrobble-only path above).
    await _markCurrentMovieAsFinished();

    // "Stop at the end of this episode": suppress every advance below and let
    // the screen sleep. Playback has already finished, so there is nothing
    // left to pause.
    if (_sleepTimerMode == SleepTimerMode.endOfItem) {
      _cancelSleepTimer();
      _sleepStopLatched = true;
      _activeMediaShouldPlay = false;
      _showSleepTimerToast('Sleep timer — stopping here');
      return;
    }

    // IPTV episode list (series/VOD): advance to the next episode in the
    // season, mirroring the Next button. Checked first because IPTV episodes
    // carry no playlist / magic-next, so the branches below would otherwise
    // leave the player parked on the final frame with a next episode available.
    if (_hasIptvNext) {
      await _switchToIptvChannel(_currentIptvIndex + 1);
      return;
    }

    // Playlist auto-advance keeps priority over guide-based Stremio TV next.
    if (_continuousShuffleEnabled) {
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
        config.requestMagicNext != null) {
      await _goToNextEpisode();
      return;
    }

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
      if (config.viewMode == PlaylistViewMode.raw ||
          config.viewMode == PlaylistViewMode.sorted) {
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
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playlist items available')),
      );
      return;
    }

    if (kUnifiedPlayerMenuEnabled) {
      _openPlayerMenuQuick(PlayerMenuSection.shuffle);
      return;
    }

    _transportVisibility.cancelAutoHide();
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
              _RandomChoiceTile(
                icon: Icons.shuffle_rounded,
                title: 'Play Random Once',
                subtitle: 'Pick one random item, then resume normal order',
                onTap: () => Navigator.of(context).pop('once'),
              ),
              const SizedBox(height: 8),
              _RandomChoiceTile(
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
    _transportVisibility.scheduleAutoHide();

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
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Continuous shuffle off')));
    } else {
      setState(() {
        _continuousShuffleEnabled = true;
        _shuffleBag.clear();
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
        });
      } else {
        _shuffleBag.clear();
      }
    }

    final nextIndex = _pickShuffleIndex();
    if (nextIndex == null) return;
    _setManualSelectionMode();
    await _loadPlaylistIndex(nextIndex, autoplay: true);
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
      if (config.viewMode == PlaylistViewMode.raw ||
          config.viewMode == PlaylistViewMode.sorted) {
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
    // Series content may have a next episode discoverable via Stremio metadata.
    // Requires episode info from widget params or a parsed series playlist.
    if (config.requestMagicNext == null &&
        config.contentType == 'series' &&
        config.contentImdbId != null &&
        (config.contentSeason != null || _seriesPlaylist != null)) {
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
        return _adjacentEpisode(se.season!, se.episode!, -1) != null;
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
    final isDebrifyTV = config.requestMagicNext != null;
    if (isDebrifyTV) {
      _startTransitionOverlay();
    }
    try {
      await _player.pause();
    } catch (_) {}
    if (_continuousShuffleEnabled) {
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
    if (_canFetchEpisodes) {
      final se = _traktSeasonEpisode();
      if (se.season != null && se.episode != null) {
        var next = _adjacentEpisode(se.season!, se.episode!, 1);
        if (next == null && config.contentImdbId != null) {
          final nextEp = await NextEpisodeService.findNextEpisode(
            config.contentImdbId!,
            se.season!,
            se.episode!,
          );
          if (nextEp != null) next = (nextEp.season, nextEp.episode);
          if (!mounted) return;
        }
        if (next != null) {
          await _fetchAndPlayEpisode(next.$1, next.$2);
          return;
        }
      }
    }

    // Series content without season pack: find next episode and trigger Quick Play
    if (config.requestMagicNext == null) {
      final handled = await _handleSeriesNextEpisode();
      if (handled) return;
    }

    // If there is no playlist-based next item and Debrify TV provider is present, use it
    if (config.requestMagicNext != null) {
      debugPrint('Player: MagicTV next requested.');
      try {
        final result = await config.requestMagicNext!();
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
          _subs.resetSubtitleState();
          _singleFileImdbId = null;
          _singleFileImdbFetched = false;
          _resetLocalCompletionState();

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
              mk.Media(url, httpHeaders: config.httpHeaders),
              play: true,
            );
          }
          _currentStreamUrl = url;
          // Disable auto-enabled embedded subtitles to prevent duplicates
          await _subs.setSubtitleTrackWithDiagnostics(
            mk.SubtitleTrack.no(),
            source: 'debrify-tv-open-disable-auto',
          );
          // If advanced option is enabled, jump to a random timestamp for Debrify TV items
          if (config.startFromRandom) {
            await _waitForVideoReady();
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            }
          } else if (config.startAtPercent != null) {
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

  /// When no playlist-based next episode exists and content is a series,
  /// find the next episode via Stremio meta and pop the player with the result.
  /// The caller (TorrentSearchScreen) will receive this and trigger Quick Play.
  Future<bool> _handleSeriesNextEpisode() async {
    // Already popping to hand off the next episode — a second trigger (manual
    // Next racing end-of-video auto-advance) must not run again.
    if (_seriesNextDispatched) return true;
    if (config.contentType != 'series' || config.contentImdbId == null) {
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
    currentSeason ??= config.contentSeason;
    currentEpisode ??= config.contentEpisode;

    if (currentSeason == null || currentEpisode == null) return false;

    debugPrint(
      'Player: Looking up next episode after S${currentSeason}E$currentEpisode',
    );
    final nextEp = await NextEpisodeService.findNextEpisode(
      config.contentImdbId!,
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
    Navigator.of(context).pop(<String, dynamic>{
      'quickPlayNext': true,
      'imdbId': config.contentImdbId,
      'season': nextEp.season,
      'episode': nextEp.episode,
      'title': config.contentTitle ?? config.title,
      'contentType': config.contentType,
    });
    return true;
  }

  /// Parse channel directory from widget params into ChannelEntry list
  void _parseChannelDirectory() {
    final directory = config.channelDirectory;
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

  /// Load subtitle style settings
  Future<void> _loadSubtitleSettings() async {
    final settings = await SubtitleSettingsService.instance.loadAll();
    if (mounted) {
      setState(() {
        _subtitleSettings = settings;
      });
      if (settings.syncOffsetMs != 0) {
        _applySubtitleSyncOffset(settings.syncOffsetMs);
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

  Future<void> _loadDockPrefs() async {
    final style = await StorageService.getPlayerDockStyle();
    final palette = await StorageService.getPlayerDockPalette();
    final size = await StorageService.getPlayerDockSize();
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
    _subtitleAutoSyncEnabled =
        await StorageService.getSubtitleAutoSyncEnabled();
    debugPrint(
      'SubtitleAutoSync: pref loaded, enabled=$_subtitleAutoSyncEnabled',
    );
    // Load default aspect index
    final aspectIndex = await StorageService.getPlayerDefaultAspectIndex();
    const aspects = AspectMode.values;
    _presentation.aspectMode = aspects[aspectIndex.clamp(0, aspects.length - 1)];

    // In-player guide look. `_initializePlayer` awaits this before playback
    // setup, so every IPTV surface that can actually appear (first tune,
    // zap, guide) already has the real value.
    _playerGuideStyle = PlayerGuideStyle.fromPref(
      await StorageService.getIptvPlayerGuideStyle(),
    );
    _playerGuideTokens = PlayerGuideTokens.of(_playerGuideStyle);

    if (PlatformUtil.isTvOS) {
      _tvosForceSoftwareDecode =
          await StorageService.getTvosForceSoftwareDecode();
    }

    // Audio-output settings, preloaded for [_configurePlayerAudio] — the
    // single owner of ao / audio-spdif / audio-channels
    // (AUDIO_FIDELITY_PLAN.md).
    if (!kIsWeb && Platform.isAndroid) {
      _audioPassthroughEnabled =
          await StorageService.getAudioPassthroughEnabled();
      _systemAudioEffectsEnabled =
          await StorageService.getPlayerSystemAudioEffects();
    } else if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile) {
      _appleMultichannelEnabled =
          await StorageService.getAppleMultichannelAudio();
    }
    if (PlatformUtil.isTvOS) {
      _tvosForceStereoAudio = await StorageService.getTvosForceStereoAudio();
      _tvosLegacyAudioOutput = await StorageService.getTvosLegacyAudioOutput();
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

    debugPrint('VideoPlayer: Loaded defaults - aspect=${_presentation.aspectMode}');
  }

  /// Update subtitle style settings
  void _onSubtitleStyleChanged(SubtitleSettingsData settings) {
    // Style saves are awaited before this fires, so it can land after the
    // whole player route is gone (close right after adjusting a style).
    if (!mounted) return;
    final offsetChanged =
        _subtitleSettings?.syncOffsetMs != settings.syncOffsetMs;
    setState(() {
      _subtitleSettings = settings;
    });
    if (offsetChanged) {
      _subtitleAutoSync?.manualOffsetChanged(settings.syncOffsetMs);
      _hideAutoSyncPill();
      _applySubtitleSyncOffset(settings.syncOffsetMs);
    }
  }

  void _applySubtitleSyncOffset(int ms) {
    final platform = _player.platform;
    if (platform is mk.NativePlayer) {
      platform.setProperty('sub-delay', (ms / 1000.0).toStringAsFixed(3));
    }
  }

  /// Reset the sync offset to 0. The offset belongs to the specific subtitle it
  /// was dialed in against, so it must reset whenever the subtitle or the
  /// content changes. mpv's `sub-delay` is push-based, so zero it explicitly
  /// rather than relying on a stale in-memory value carrying over.
  void _resetSubtitleSyncOffset() {
    SubtitleSettingsService.instance.resetSyncOffset();
    // Keep the UI model in sync (no setState needed: the sync overlay is closed
    // on these transitions and no style rendering depends on the offset).
    _subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: 0);
    _applySubtitleSyncOffset(0);
  }

  /// Overlays inside the player share its route scope, which already has a
  /// focused child (the player root) — so their `autofocus` is silently
  /// discarded and the first OK does nothing. Releasing the current focus as
  /// the overlay appears lets its autofocus node claim it.
  void _tvReleaseFocusForOverlay() {
    if (!PlatformUtil.isTelevision) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _showSyncOverlayPanel() {
    _tvReleaseFocusForOverlay();
    setState(() {
      _showSyncOverlay = true;
      _controlsVisible.value = false;
    });
  }

  void _hideSyncOverlay() {
    setState(() => _showSyncOverlay = false);
  }

  Widget _buildSyncOverlay() {
    final externalPath = _activeExternalSubtitlePath;
    if (externalPath != null) {
      return SubtitleLinePickerOverlay(
        subtitleFilePath: externalPath,
        getCurrentPositionMs: () => _player.state.position.inMilliseconds,
        currentOffsetMs: _subtitleSettings?.syncOffsetMs ?? 0,
        onOffsetChanged: (ms) async {
          await SubtitleSettingsService.instance.setSyncOffsetMs(ms);
          _subtitleAutoSync?.manualOffsetChanged(ms);
          _hideAutoSyncPill();
          _applySubtitleSyncOffset(ms);
          if (mounted) {
            setState(() {
              _subtitleSettings = _subtitleSettings?.copyWith(syncOffsetMs: ms);
            });
          }
        },
        onDismiss: _hideSyncOverlay,
      );
    }

    return _buildSliderSyncOverlay();
  }

  Widget _buildSliderSyncOverlay() {
    return SyncStepperOverlay(
      offsetMs: _subtitleSettings?.syncOffsetMs ?? 0,
      onOffsetChanged: (ms) async {
        final clamped = ms.clamp(
          SubtitleSettingsService.syncOffsetMinMs,
          SubtitleSettingsService.syncOffsetMaxMs,
        );
        await SubtitleSettingsService.instance.setSyncOffsetMs(clamped);
        _subtitleAutoSync?.manualOffsetChanged(clamped);
        _hideAutoSyncPill();
        _applySubtitleSyncOffset(clamped);
        if (mounted) {
          setState(() {
            _subtitleSettings = _subtitleSettings?.copyWith(
              syncOffsetMs: clamped,
            );
          });
        }
      },
      onDismiss: _hideSyncOverlay,
    );
  }

  /// Show channel guide overlay
  void _showChannelGuideOverlay() {
    if (_channelEntries.isEmpty) {
      debugPrint('Player: No channels available for guide');
      return;
    }
    _zap.hideBanner();
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

  void _onIptvStreamError(String error) => _zap.onStreamError(error);

  /// Surface a Stremio IPTV channel's candidate links in the existing source
  /// sheet: the candidates become direct-URL [Torrent] rows via the override
  /// the sheet already honors. Null/empty clears the sheet (plain M3U
  /// channels have exactly one link — nothing to pick).
  void _setIptvSources(
    String? channelKey,
    List<StremioIptvCandidate>? candidates, {
    int currentIndex = 0,
  }) {
    if (!mounted) return;
    _iptvChannelKey = channelKey;
    if (channelKey == null || candidates == null || candidates.isEmpty) {
      if (_stremioSourcesOverride != null ||
          _resolveStremioSourceOverride != null) {
        setState(() {
          _stremioSourcesOverride = null;
          _resolveStremioSourceOverride = null;
        });
      }
      return;
    }
    final sources = <Torrent>[
      for (var i = 0; i < candidates.length; i++)
        Torrent(
          rowid: i,
          // Same synthetic-hash convention _convertToTorrents uses for
          // direct-URL streams (stable per-URL dedupe key, not a real hash).
          infohash:
              'url:${candidates[i].url.hashCode.toRadixString(16).padLeft(40, '0')}',
          name: candidates[i].label,
          sizeBytes: 0,
          createdUnix: 0,
          seeders: 0,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'stremio',
          streamType: StreamType.directUrl,
          directUrl: candidates[i].url,
          hasRealInfoHash: false,
        ),
    ];
    setState(() {
      _stremioSourcesOverride = sources;
      _resolveStremioSourceOverride = (t) async => t.directUrl;
      _currentSourceIndex = currentIndex.clamp(0, sources.length - 1);
    });
  }

  /// The launch already resolved the initial channel's URL, but the source
  /// sheet wants the whole candidate list — fetch it (cache hit from the
  /// launch resolve) and populate the override for the starting channel.
  void _initIptvStremioSources() {
    final channels = _effectiveIptvChannels;
    final idx = config.iptvStartIndex ?? 0;
    if (channels == null || idx < 0 || idx >= channels.length) return;
    final channel = channels[idx];
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) return;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || found.isEmpty) return;
      // The user already zapped away (or a switch populated sources itself).
      if (_iptvChannelKey != null || _currentIptvIndex != idx) return;
      var current = found.indexWhere((c) => c.url == config.videoUrl);
      if (current < 0) current = 0;
      _setIptvSources(channel.url, found, currentIndex: current);
    });
  }

  IptvChannel? get _currentIptvChannel => _zap.currentChannel;

  // ==========================================================================
  // Startup-channel memory
  //
  // Remembers the last LIVE channel that actually reached a playing state, so
  // "start on my last channel" re-tunes what was being watched rather than what
  // was last launched — zapping is how live IPTV is used, and the launch
  // channel is stale the moment the user presses up.
  //
  // Recorded on PLAYBACK, not on tune: a dead stream must never replace the
  // last working channel, because the startup feature re-tunes this unattended
  // on every cold boot.
  // ==========================================================================

  Timer? _lastLiveChannelTimer;
  String? _lastLiveChannelArmedUrl;

  /// Commit-on-settle: a channel counts once it has been *playing* for
  /// [_lastLiveChannelSettle]. Zapping through twenty channels arms and
  /// supersedes one timer rather than writing twenty times, and the commit
  /// lands while the app is alive — an abrupt force-stop runs no lifecycle
  /// callback, so a flush-on-dispose alone would lose it.
  static const Duration _lastLiveChannelSettle = Duration(seconds: 1);

  void _noteLiveChannelPlaying() {
    final channel = _currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    // Already counting down for this very channel — a pause/resume or a
    // re-emitted playing event must not restart the settle window.
    if (_lastLiveChannelArmedUrl == channel.url &&
        (_lastLiveChannelTimer?.isActive ?? false)) {
      return;
    }
    _lastLiveChannelTimer?.cancel();
    _lastLiveChannelArmedUrl = channel.url;
    _lastLiveChannelTimer = Timer(_lastLiveChannelSettle, () {
      // Re-read rather than closing over: the user may have zapped on during
      // the settle window, and the channel that settled is the one that counts.
      final settled = _currentIptvChannel;
      if (settled == null || !settled.isLive || settled.url != channel.url) {
        return;
      }
      if (!_isPlaying) return;
      unawaited(
        StorageService.setIptvLastLiveChannel(
          settled.url,
          name: settled.name,
          // Origin provider, resolved the same way the catchup path does —
          // `_originPlaylistIdFor` lives on the IPTV page and is not reachable
          // from here.
          playlistId:
              settled.attributes['source_playlist_id'] ??
              _iptvGuideContextOverride?.sourceId ??
              widget.iptvSourceId,
          channelNumber: settled.channelNumber,
          group: settled.group,
          logoUrl: settled.logoUrl,
          httpHeaders: settled.httpHeaders.isEmpty ? null : settled.httpHeaders,
        ),
      );
    });
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

  /// Session-scoped audio language the user picked while in this IPTV series
  /// (carries across episode switches in this sitting). Persisted per-series
  /// too — see [StorageService.setIptvSeriesAudioLanguage].
  String? _preferredIptvAudioLanguage;

  /// Per-series key for remembering the audio language — `<playlistId>::<id>`,
  /// the SAME identity Continue Watching keys by, so two series that merely
  /// share a display name never collide. Null unless this is a series episode.
  String? _iptvSeriesAudioKey() {
    final ch = _currentIptvChannel;
    if (ch == null || ch.isLive) return null;
    final sid = ch.attributes['series_id'];
    if (sid == null || sid.isEmpty) return null;
    final pid = ch.attributes['series_playlist_id'] ?? '';
    return '$pid::$sid';
  }

  /// Remember the audio language the user just chose for the current IPTV
  /// series episode, so later episodes and future sessions default to it.
  /// No-op for non-IPTV / live / non-series content.
  void _captureIptvAudioLanguage(String audioId) {
    if (!_isIptvSeriesContext) return;
    String? lang;
    for (final t in _player.state.tracks.audio) {
      if (t.id == audioId) {
        lang = t.language;
        break;
      }
    }
    if (lang == null || lang.isEmpty || lang == 'auto' || lang == 'und') return;
    // onTrackChanged also fires on subtitle-only changes and after our own
    // auto-apply — skip the redundant write when the language is unchanged.
    if (lang == _preferredIptvAudioLanguage) return;
    _preferredIptvAudioLanguage = lang;
    final key = _iptvSeriesAudioKey();
    if (key != null) {
      unawaited(StorageService.setIptvSeriesAudioLanguage(key, lang));
    }
  }

  /// Re-apply the preferred audio track for an IPTV series episode after a
  /// source change: this sitting's pick → this series' stored pick → the
  /// global default audio language. Matches by language (robust across
  /// episodes whose track ordinals differ). [ticket] is the switch generation
  /// this apply belongs to — a newer switch (or unmount) abandons it, so it
  /// can't set audio on the wrong episode. The preferred language is read
  /// AFTER the track wait, so a manual pick made during the wait wins.
  Future<void> _applyIptvAudioPreference(int ticket) async {
    try {
      // Tracks aren't enumerated the instant open() returns — wait briefly,
      // bailing if a newer switch supersedes this one.
      for (var i = 0; i < 20; i++) {
        if (!mounted || ticket != _iptvSwitchTicket) return;
        if (_player.state.tracks.audio.length >= 2) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted || ticket != _iptvSwitchTicket) return;
      final tracks = _player.state.tracks;
      if (tracks.audio.length < 2) return; // nothing to switch to

      // Resolve the target language now (not before the wait): a manual pick
      // during the wait updated _preferredIptvAudioLanguage, and it should win.
      String? lang = _preferredIptvAudioLanguage;
      if (lang == null) {
        final key = _iptvSeriesAudioKey();
        if (key != null) {
          lang = await IptvPrefs.getIptvSeriesAudioLanguage(key);
        }
      }
      lang ??= await StorageService.getDefaultAudioLanguage();
      if (lang == null || !mounted || ticket != _iptvSwitchTicket) return;

      mk.AudioTrack? match;
      for (final t in tracks.audio) {
        if (LanguageMapper.matchesLanguage(lang, t.language) ||
            LanguageMapper.matchesLanguage(lang, t.title)) {
          match = t;
          break;
        }
      }
      if (match != null) await _player.setAudioTrack(match);
    } catch (_) {
      // Non-critical — audio preference is best-effort.
    }
  }

  /// Write one on-demand IPTV item to the watch history, carrying whatever
  /// series identity the channel was built with (see `openXtreamEpisode`,
  /// which stamps these attributes on every episode of a series). The
  /// playlist id has to match the one the series page records or the shelf
  /// would group the same series under two keys.
  Future<void> _recordIptvWatchForChannel(IptvChannel channel) async {
    final attrs = channel.attributes;
    final seriesId = attrs['series_id'];
    final hasNext = attrs['has_next_episode'];
    final headers = channel.httpHeaders;
    try {
      await StorageService.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId:
            attrs['series_playlist_id'] ??
            attrs['source_playlist_id'] ??
            widget.iptvSourceId,
        httpHeaders: headers.isEmpty ? null : headers,
        seriesId: (seriesId != null && seriesId.isNotEmpty) ? seriesId : null,
        seriesName: attrs['series_name'] ?? channel.group,
        season: int.tryParse(attrs['season'] ?? ''),
        episode: int.tryParse(attrs['episode'] ?? ''),
        hasNextEpisode: hasNext == null ? null : hasNext == 'true',
      );
    } catch (e) {
      debugPrint('Player: IPTV watch registration failed: $e');
    }
  }


  Future<void> _switchToIptvChannel(
    int index, {
    bool quietRecovery = false,
  }) async {
    final channels = _effectiveIptvChannels;
    if (channels == null || index < 0 || index >= channels.length) return;
    // Ticket FIRST, before any await — codex round 2's blocker: with the
    // ticket taken after the recording stop below, two overlapping switch
    // calls could resume from that await in either order and the OLDER
    // intent could take the newer ticket, hijacking playback back to the
    // channel the user just left.
    final ticket = ++_iptvSwitchTicket;
    // This switch owns the error gate now (a superseded ladder's state doesn't
    // survive). Muted until the new media is opened below; the burst debounce
    // resets too, so this channel can report its own failure.
    _iptvErrorsMuted = true;
    _zap.clearErrorBurst();
    // One machine tune-start per SWITCH, not per Stremio candidate — the
    // candidate ladder below is this switch's own hunt. A machine-driven
    // stremio re-tune arrives here with expectRetune set and keeps its
    // episode; a real zap resets the machine and takes the pill with it.
    final wasRecoveryRetune = _iptvLiveRecovery.expectRetune;
    _iptvLiveRecovery.onTuneStarted();
    if (!wasRecoveryRetune) _iptvReconnectText.value = null;
    // A channel change ends the current recording (the stream identity flips).
    // Unconditional: it must also cancel a start still awaiting its storage
    // setup, which `_isRecording` would not report yet.
    await _stopRecording(userInitiated: false);
    if (!mounted || ticket != _iptvSwitchTicket) return;
    _zap.cancelPendingCatchup();

    _zap.hideChannelSheet();

    final channel = channels[index];
    _clearBufferingIndicator();
    // The zap path never runs _maybeRestoreResume, so the previous channel's
    // resume guard (a VOD movie mid-resume) would otherwise stay armed and
    // suppress the incoming channel's saves. Same switch-boundary rule as
    // _loadPlaylistIndex.
    _resumeWriteGuard.clear();
    setState(() {
      // A quiet recovery re-tune is not a zap: no transition overlay, no
      // zap banner — the reconnect pill is the only narration (plan
      // invariant "retune ≠ zap"; codex round 2, finding 14).
      _isTransitioning = !quietRecovery;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentIptvIndex = index;
      _currentChannelNumber = channel.channelNumber ?? (index + 1);
      // The corner badge is painted from this pair; without the name it kept
      // showing the launch channel under the new channel's number.
      _currentChannelName = channel.name;
    });
    if (!quietRecovery) _startTransitionOverlay();
    // Identity paints from the channel itself, so it is correct before a
    // single byte of the new stream has arrived; the guide fills in behind it.
    // Zapping to on-demand retires the panel outright — it has no live
    // identity to present, and leaving it up would describe the wrong item.
    if (channel.isLive && !quietRecovery) {
      _zap.prepareBannerData(channel);
      _zap.raiseBanner();
      // The guide follows what is playing, so reopening it lands on the
      // category the current channel actually belongs to. A paged ring is the
      // exception: it already knows its own category from the response, which
      // a single channel's group can't always express — an "All"/uncategorized
      // window would keep narrowing the guide to whichever group it landed on.
      if (!_zap.pagingActive) _zap.anchorGuideCategory(channel);
    } else {
      _zap.hideBanner();
    }

    // Register the item we're switching TO in the IPTV watch history, exactly
    // as the native TV player does before every non-live start. Only the item
    // the user LAUNCHED used to be recorded, so an auto-advanced episode wrote
    // a resume position that no history row accounted for: the Continue
    // Watching shelf kept pointing at the launch episode, and a series-wide
    // removal (which finds episodes through the history) couldn't reach the
    // rest of them. Unawaited — the shelf can settle a frame late, a zap can't.
    if (!channel.isLive) unawaited(_recordIptvWatchForChannel(channel));

    try {
      await _player.pause();
    } catch (_) {}

    if (StremioIptvService.isStremioChannelUrl(channel.url)) {
      // Retire the outgoing channel's source rows NOW — during the resolve
      // await below the sheet must not offer the previous channel's links
      // (picking one would abort this switch's ladder and play the old
      // channel under the new channel's identity).
      _setIptvSources(null, null);
      // Mirror the native path: the UI has already committed to the new
      // channel, so clear the outgoing stream now — a failed or empty
      // resolve must not leave the previous channel's frozen frame sitting
      // under the new channel's title/index.
      try {
        await _player.stop();
      } catch (_) {}
      // Stremio-addon channel: resolve its candidate URLs and walk them until
      // one produces playback — the same serial ladder the IPTV preview runs.
      // A zap is an explicit play intent, so a cached-empty resolve is
      // re-checked fresh instead of replaying a stale "nothing".
      final candidates = await StremioIptvService.instance.resolveCandidates(
        channel.url,
        refreshIfEmpty: true,
      );
      if (!mounted || ticket != _iptvSwitchTicket) return;
      // The candidates double as the source sheet's rows for this channel.
      _setIptvSources(channel.url, candidates);
      var opened = false;
      try {
        for (var i = 0; i < candidates.length; i++) {
          if (!mounted || ticket != _iptvSwitchTicket) return;
          final url = candidates[i].url;
          _iptvDiag.onTuneStart(channel.name, url, isLive: channel.isLive);
          _iptvDiag.note('stremio candidate ${i + 1}/${candidates.length}');
          final ok = await _tryOpenLiveStream(
            url,
            httpHeaders: channel.playbackHeaders,
          );
          // A newer switch superseded this ladder mid-probe: its success or
          // failure belongs to the other channel's playback now — don't
          // credit it here.
          if (ticket != _iptvSwitchTicket) return;
          if (ok) {
            StremioIptvService.instance.markWinner(channel.url, url);
            if (mounted && _currentSourceIndex != i) {
              setState(() => _currentSourceIndex = i);
            }
            opened = true;
            break;
          }
        }
      } finally {
        // Only this ladder's own probing is silenced; a newer switch owns the
        // flag from here (it sets it again on entry).
        if (ticket == _iptvSwitchTicket) _iptvErrorsMuted = false;
      }
      if (ticket != _iptvSwitchTicket) return;
      if (!opened) {
        // Dead channel — forget the stale candidates so a later attempt
        // re-resolves. Playback just stays down, like a dead M3U channel.
        StremioIptvService.instance.invalidate(channel.url);
        debugPrint('Player: no playable stream for ${channel.name}');
      }
    } else {
      // Plain M3U/Xtream channel: single link, no source sheet. Headers are
      // per-channel (the playlist declares them per entry), so they come from
      // the channel rather than widget.httpHeaders.
      _setIptvSources(null, null);
      try {
        _iptvDiag.onTuneStart(
          channel.name,
          channel.url,
          isLive: channel.isLive,
        );
        final media = mk.Media(
          channel.url,
          httpHeaders: channel.playbackHeaders,
        );
        // The outgoing stream is torn down (pause above); everything mpv
        // reports from here is this channel's, including a fast failure that
        // lands while open() is still awaiting.
        _iptvErrorsMuted = false;
        await _openMedia(media, play: true, liveStream: channel.isLive);
      } catch (e) {
        debugPrint('Player: IPTV channel switch failed: $e');
      }
    }

    if (!mounted || ticket != _iptvSwitchTicket) return;

    // Carry the audio choice onto the new episode (series memory). Fire and
    // forget: it waits for the new source's tracks then matches by language;
    // [ticket] is this switch's generation so a newer switch abandons it.
    if (_isIptvSeriesContext) {
      unawaited(_applyIptvAudioPreference(ticket));
    }

    // Directly trigger transition overlay cleanup sequence.
    // Unlike debrid channel switching (where _playSub listener handles
    // the transition phases after 'playing' fires), IPTV URLs are already
    // resolved so we skip phase 1 and go straight to the reveal phase.
    // This prevents the overlay from getting stuck if the playing event
    // doesn't fire reliably for HLS/live streams.
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

    // The NEW channel may itself already be recording (engine captures keep
    // running across zaps) — repaint the Record button from native truth.
    if (_recording.engineFlagOn) unawaited(_recording.refreshEngineState());
  }

  /// Open [url] and wait until it demonstrably plays (a decoded video size or
  /// advancing position) or demonstrably fails (player error, open() throw,
  /// or the timeout — live streams can stall without ever erroring). Used by
  /// the Stremio channel ladder to decide whether to try the next candidate.
  Future<bool> _tryOpenLiveStream(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
  }) async {
    // Every live media replacement ends the recording, not just a channel zap:
    // picking another row in the Sources sheet lands here via
    // _switchToIptvSource, and mpv makes no promise about `stream-record`
    // across an open() — it may quietly stop or overwrite the file while
    // `_isRecording` still claims it is running. Redundant (and harmless) on
    // the _switchToIptvChannel path, which already stopped before its ladder.
    await _stopRecording(userInitiated: false);

    final completer = Completer<bool>();
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    // Position/error events only count after open() returns — the stream can
    // still be draining the previous media's positions (or a dead outgoing
    // channel's queued error) before then. Genuine pre-open failures are
    // covered by the open() throw and the timeout.
    var openDone = false;
    final subs = <StreamSubscription>[
      _player.stream.error.listen((_) {
        if (openDone) finish(false);
      }),
      _player.stream.width.listen((w) {
        if (openDone && w != null && w > 0) finish(true);
      }),
      _player.stream.position.listen((p) {
        if (openDone && p > Duration.zero) finish(true);
      }),
    ];
    try {
      // Plan finding P7: candidate opens used to drop the channel's own
      // headers — the one open path that lost them. Carry them like every
      // other open does.
      await _openMedia(
        mk.Media(url, httpHeaders: httpHeaders),
        play: true,
        liveStream: true,
      );
      openDone = true;
    } catch (e) {
      debugPrint('Player: stremio candidate failed to open: $e');
      finish(false);
    }
    final ok = await completer.future.timeout(timeout, onTimeout: () => false);
    for (final s in subs) {
      unawaited(s.cancel());
    }
    return ok;
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
        if ((width ?? 0) > 0 &&
            _player.state.position > Duration.zero) {
          finish(true, 'decoded_video');
        }
      }),
      _player.stream.position.listen((value) {
        if (value > Duration.zero &&
            (_player.state.width ?? 0) > 0) {
          finish(true, 'decoded_video');
        }
      }),
      _player.stream.buffer.listen((value) {
        bufferedAmount = value;
      }),
    ];
    try {
      await _openMedia(mk.Media(url, httpHeaders: httpHeaders), play: true);
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
      // Arm before open: a fast local/CDN response can render its first frame
      // before open() completes. Initial startup has no previous-media events;
      // subsequent attempts use open()'s media reset to establish the boundary.
      armed = true;
      await _openMedia(mk.Media(url, httpHeaders: httpHeaders), play: true);
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
        ? await QuickPlayPolicyPrefs.getQuickPlayRules(
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
          resolvedPlaylist = await widget.resolveSourceToPlaylist!(source);
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
          !pikPakResolver && source?.streamType == StreamType.torrent;
      final ok = isDebridResolved
          ? await _openStartupDebridDirect(
              url,
              httpHeaders: httpHeaders,
              source: source,
              sourceIndex: sourceIndex,
              attempt: attempts,
              maxAttempts: maxAttempts,
            )
          : await _tryOpenStartupVod(
              url,
              httpHeaders: httpHeaders,
              source: source,
              sourceIndex: sourceIndex,
              attempt: attempts,
              maxAttempts: maxAttempts,
            );
      if (!mounted) return false;
      if (!ok) continue;

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
    _zap.hideBanner();
    setState(() {
      _showSourceSheet = true;
      _controlsVisible.value = false;
    });
  }

  void _hideSourceSheet() {
    setState(() {
      _showSourceSheet = false;
    });
  }

  Future<String?> Function(Torrent) _buildSourceSheetResolver() {
    if (widget.resolveSourceToPlaylist != null) {
      return (Torrent torrent) async {
        final playlist = await widget.resolveSourceToPlaylist!(torrent);
        if (playlist == null || playlist.isEmpty) return null;
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
    unawaited(_resume.cancelResumeVerification());
    // Live IPTV channel: the movie pipeline below seeks to the previous
    // position and reloads subtitles — both meaningless (and harmful) for a
    // live stream. Route to the dedicated live switch instead.
    if (_iptvChannelKey != null) {
      await _switchToIptvSource(index, url);
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

  /// Manual pick from the source sheet while a Stremio IPTV channel plays:
  /// open the chosen link directly. No position seek, no subtitle
  /// bookkeeping, and no auto-advance on failure — the user chose this link
  /// deliberately, so a dead pick just leaves the channel down (they can
  /// pick another from the sheet).
  Future<void> _switchToIptvSource(int index, String url) async {
    _hideSourceSheet();
    final key = _iptvChannelKey;
    final ticket = ++_iptvSwitchTicket;
    final previousIndex = _currentSourceIndex;
    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentSourceIndex = index;
    });
    _startTransitionOverlay();
    // A deliberate source pick is a fresh tune: any recovery episode (and
    // its pill) belonged to the link being abandoned.
    _iptvLiveRecovery.onTuneStarted();
    _iptvReconnectText.value = null;
    try {
      await _player.pause();
    } catch (_) {}
    final ok = await _tryOpenLiveStream(
      url,
      httpHeaders: _currentIptvChannel?.playbackHeaders,
    );
    if (!mounted || ticket != _iptvSwitchTicket) return;
    if (ok) {
      if (key != null) {
        StremioIptvService.instance.markWinner(key, url);
      }
    } else {
      // Failed pick: restore the highlight — leaving it on the dead row
      // would both show a false PLAYING badge and block retrying it (the
      // sheet ignores selecting the "current" source).
      setState(() => _currentSourceIndex = previousIndex);
    }
    // Same direct transition-overlay cleanup as _switchToIptvChannel — the
    // 'playing' event is unreliable for HLS/live streams.
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

  Future<void> _switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
  }) async {
    _hideSourceSheet();
    _clearBufferingIndicator();
    final outgoingPlaylist = _activePlaylist == null
        ? null
        : List<PlaylistEntry>.of(_activePlaylist!);
    final outgoingIndex = _currentIndex;
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
    await _resume.saveResume();
    if (!mounted) return;
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentSourceIndex = sourceIndex;
    });
    _startTransitionOverlay();
    try {
      await _player.pause();
    } catch (_) {}
    if (!mounted) return;

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
    setState(() {
      _activePlaylist = newPlaylist;
      _cachedSeriesPlaylist = null;
      _playlistIdentityToken++;
    });
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
      committed = await _loadPlaylistIndex(
        targetIndex,
        autoplay: true,
        skipInitialSave: true,
        preferLocalResume: landedOnSameContent,
      );
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
        if (!mounted) return;
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
            await _resume.seekForResume(outgoingPosition.inMilliseconds);
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
            await _openMedia(
              mk.Media(outgoingDirectUrl, httpHeaders: widget.httpHeaders),
              play: true,
            );
            await _waitForVideoReady();
            if (outgoingPosition > Duration.zero) {
              await _resume.seekForResume(outgoingPosition.inMilliseconds);
            }
            _currentStreamUrl = outgoingDirectUrl;
            unawaited(_subs.restoreTrackPreferences());
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
    if (!mounted) return;

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
  }

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
      _subs.resetSubtitleState();
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
              httpHeaders: widget.httpHeaders,
              source: source,
              sourceIndex: index,
            );
      if (!mounted) return;
      if (!valid) {
        throw const _ManualSourceValidationFailure();
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
        await _resume.seekForResume(resumePosition.inMilliseconds);
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
        unawaited(_subs.restoreTrackPreferences());
      }
      _currentSourceIndex = index;
      _currentStreamUrl = url;
      committed = true;
      unawaited(_commitValidatedStremioSource(source));
    } catch (e) {
      debugPrint('Player: manual Stremio source rejected (${e.runtimeType})');
      // The candidate player is stopped by the validator. Restore the known
      // working stream when possible, but never validate/fail over to another
      // row: this was an explicit user selection.
      if (previousUrl != null && previousUrl.isNotEmpty) {
        try {
          await _openMedia(
            mk.Media(previousUrl, httpHeaders: widget.httpHeaders),
            play: true,
          );
          await _waitForVideoReady();
          if (hasExternalAudio) {
            // YouTube-style split streams: the reopen dropped the external
            // audio track — without this the restored video plays silent.
            await _setExternalAudioTrack(widget.audioUrl!);
          }
          if (resumePosition > Duration.zero) {
            await _resume.seekForResume(resumePosition.inMilliseconds);
          }
          _currentStreamUrl = previousUrl;
          if (!hasExternalAudio) {
            // Subtitle state was reset for the candidate; bring the user's
            // subtitle/audio choices back on the restored stream.
            unawaited(_subs.restoreTrackPreferences());
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
    if (config.stremioTvCurrentChannelId != null) {
      return config.stremioTvCurrentChannelId;
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

    _subs.resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;
    _resetLocalCompletionState();

    try {
      _pikPakRetryId++;
      await _openMedia(mk.Media(url), play: true);
      _currentStreamUrl = url;
      await _subs.setSubtitleTrackWithDiagnostics(
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
    final requestNext = config.stremioTvNextProvider;
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

    final request = config.requestChannelById;
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
    _subs.resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;

    try {
      _pikPakRetryId++;
      await _openMedia(
        mk.Media(nextUrl, httpHeaders: config.httpHeaders),
        play: true,
      );
      _currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _subs.setSubtitleTrackWithDiagnostics(
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
    final request = config.requestNextChannel;
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
    _subs.resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;

    try {
      // Cancel any ongoing PikPak retry when switching channels
      _pikPakRetryId++;
      await _openMedia(
        mk.Media(nextUrl, httpHeaders: config.httpHeaders),
        play: true,
      );
      _currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _subs.setSubtitleTrackWithDiagnostics(
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

    if (config.startFromRandom) {
      await _waitForVideoReady();
      final offset = _randomStartOffset(_duration);
      if (offset != null) {
        await _player.seek(offset);
      }
    } else if (config.startAtPercent != null) {
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
        final prev = (se.season != null && se.episode != null)
            ? _adjacentEpisode(se.season!, se.episode!, -1)
            : null;
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

  /// Mark the current episode as finished if it's a series
  Future<void> _markCurrentEpisodeAsFinished() async {
    final seriesPlaylist = _seriesPlaylist;
    // Single-file series playback: use widget params
    if ((seriesPlaylist == null || !seriesPlaylist.isSeries) &&
        widget.contentType == 'series' &&
        widget.contentSeason != null &&
        widget.contentEpisode != null &&
        widget.contentImdbId != null) {
      _currentEpisodeMarkedAsFinished = true;
      try {
        await PlaybackProgressStore.markEpisodeAsFinished(
          seriesTitle: widget.contentTitle ?? widget.title,
          season: widget.contentSeason!,
          episode: widget.contentEpisode!,
          imdbId: widget.contentImdbId,
        );
      } catch (_) {}
      return;
    }
    if (seriesPlaylist == null ||
        !seriesPlaylist.isSeries ||
        seriesPlaylist.seriesTitle == null) {
      return;
    }
    _currentEpisodeMarkedAsFinished = true;
    try {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
        final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
          (episode) => episode.originalIndex == _currentIndex,
          orElse: () => seriesPlaylist.allEpisodes.first,
        );

        if (currentEpisode.seriesInfo.season != null &&
            currentEpisode.seriesInfo.episode != null) {
          await PlaybackProgressStore.markEpisodeAsFinished(
            seriesTitle: seriesPlaylist.seriesTitle!,
            season: currentEpisode.seriesInfo.season!,
            episode: currentEpisode.seriesInfo.episode!,
            imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId,
          );
        }
      }
    } catch (e) {}
  }

  Future<void> _markCurrentMovieAsFinished() async {
    final imdbId = _currentLocalMovieImdbId;
    if (!_usesLocalCompletionTracking ||
        _currentMovieMarkedAsFinished ||
        imdbId == null) {
      return;
    }
    // Set this before the await: position events are frequent and completion
    // must perform one cleanup/write, not queue one per frame.
    _currentMovieMarkedAsFinished = true;
    try {
      await Future.wait([
        PlaybackProgressStore.markMovieAsFinished(imdbId),
        StorageService.removeVideoResume(_resume.key),
      ]);
    } catch (_) {
      // Playback remains usable if local storage is temporarily unavailable.
    }
  }

  /// Apply the local, user-configured completion rule. This is synchronous on
  /// purpose because it runs for every position update; actual writes stay
  /// unawaited and are guarded one-shot above/in [_markCurrentEpisodeAsFinished].
  void _checkAndApplyLocalCompletion() {
    if (_validationGateActive ||
        !_usesLocalCompletionTracking ||
        _duration <= Duration.zero ||
        _position <= Duration.zero) {
      return;
    }

    final percent = _position.inMicroseconds * 100 / _duration.inMicroseconds;
    final movieImdbId = _currentLocalMovieImdbId;
    if (movieImdbId != null) {
      if (!_currentMovieRewatchStarted && percent < _movieCompletionThreshold) {
        // The title was finished during an earlier session. A real new play
        // below its threshold is a rewatch, so restore it to normal local
        // Continue Watching behavior before the next resume save.
        _currentMovieRewatchStarted = true;
        unawaited(PlaybackProgressStore.unmarkMovieAsFinished(movieImdbId));
      }
      if (!_currentMovieMarkedAsFinished &&
          percent >= _movieCompletionThreshold) {
        unawaited(_markCurrentMovieAsFinished());
      }
      return;
    }

    final isSeries =
        _effectiveContentType == 'series' || _seriesPlaylist?.isSeries == true;
    if (!isSeries) return;
    if (_currentEpisodeMarkedAsFinished ||
        percent < _episodeCompletionThreshold) {
      return;
    }
    unawaited(_markCurrentEpisodeAsFinished());
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
    _skipSegmentsMediaReady = true;
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
    bool skipInitialSave = false,
    // Source switch on the same content: resume the checkpointed local position
    // exactly (see _maybeRestoreResume).
    bool preferLocalResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) async {
    // A new item is being loaded: any scrub in flight belongs to the outgoing
    // one and must never land on this one; same for the landing verifier
    // (epoch bump — a verifier retry must never seek the incoming item).
    // NOTE: the resume write GUARD is deliberately NOT cleared here — the
    // outgoing item's checkpoint _resume.saveResume() below must still run against
    // the armed guard, or an unlanded resume's ~0 position would be filed over
    // that item's bookmark by the very switch that abandons it. The clear sits
    // immediately after that save.
    _tvScrubGeneration++;
    _tvAbandonScrub();
    _resumeVerifyEpoch++;
    unawaited(_resume.cancelResumeVerification());
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

    // Scrobble stop for the current episode before switching
    _scrobble.onOutgoingEpisode();
    // Keep the MDBList session's playing bit until switchTarget captures it.
    // Calling exit here would make the incoming episode look paused and would
    // prevent its initial checkpoint/timer from starting.

    // Callers that already checkpointed the outgoing episode (e.g. a source
    // switch, which saves BEFORE swapping the playlist) skip this save so it
    // can't write the current position against the newly-swapped playlist.
    if (!skipInitialSave) {
      await _resume.saveResume();
    }
    // The outgoing item's guarded checkpoint has run; from here on the guard
    // belongs to nobody. Clearing now stops it suppressing the incoming item's
    // saves and makes any in-flight landing verifier abort instead of
    // re-issuing the outgoing item's target against the new one.
    _resumeWriteGuard.clear();
    final entry = _activePlaylist![index];
    _currentIndex = index;
    await _scrobble.switchIdentity();
    _resetLocalCompletionState();

    // Clear subtitle cache and selection when changing content
    _subs.resetSubtitleState();
    _resetSkipSegmentState();

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

    // Resolve the actual streaming URL if needed
    String videoUrl = entry.url;
    if (videoUrl.isEmpty) {
      try {
        videoUrl = await _resolvePlaylistEntryUrl(index);
      } catch (e) {
        final errorText = e.toString().replaceFirst('Exception: ', '');
        if (mounted) {
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
    if (videoUrl.isEmpty) {
      _currentStreamUrl = null;
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

    _currentStreamUrl = videoUrl;

    // Check if this is a PikPak video
    final currentEntry = _activePlaylist?[index];
    final isPikPak =
        currentEntry?.provider?.toLowerCase() == 'pikpak' ||
        currentEntry?.pikpakFileId != null;

    // ALWAYS use retry logic for PikPak videos, regardless of autoplay
    if (isPikPak) {
      // For PikPak, we need retry logic even if not autoplaying
      // _playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
      final pikPakLoaded = await _playPikPakVideoWithRetry(
        videoUrl,
        // A manual source transaction owns its single failure message. The
        // retry UI remains unchanged while cold storage is being reactivated.
        showFailure: manualValidationSourceIndex == null,
      );
      if (manualValidationSourceIndex != null && !pikPakLoaded) return false;
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
          httpHeaders: widget.httpHeaders,
          source: manualValidationSource,
          sourceIndex: manualValidationSourceIndex,
        );
        if (!valid) return false;
        if (!autoplay) await _player.pause();
      } else {
        await _openMedia(
          mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
          play: autoplay,
        );
      }
    }

    // Wait for the video to load and duration to be available
    await _waitForVideoReady();
    await _resume.maybeRestoreResume(preferLocalResume: preferLocalResume);
    // Restore audio and subtitle track preferences
    await _subs.restoreTrackPreferences();

    // Clear transition state when video is ready
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
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

    return CloudProviderRegistry.instance.unlockPlayerScreenEntry(entry);
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
  }) async {
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
        mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
        play: true,
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
        mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
        play: true,
      );
    } catch (e) {
      print('PikPak: Initial player.open() failed with error: $e');
      // Continue with retry loop - might work on subsequent attempts
    }

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // Check if cancelled before starting attempt
        if (_pikPakRetryId != myRetryId) {
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
        if (_pikPakRetryId != myRetryId) {
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
            mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
            play: true,
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
        if (_pikPakRetryId != myRetryId) {
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
            mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
            play: true,
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
    unawaited(_subs.fetchAndMaybeAutoSelectAddonSubtitle());
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

    await PlaybackProgressStore.updatePlaylistItemImdbId(
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
        await PlaybackProgressStore.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await PlaybackProgressStore.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await PlaybackProgressStore.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
    } catch (e) {
      print('  ❌ Error saving poster: $e');
    }
  }

  /// Enter PiP now, sized to the current video's pixel aspect when known.
  void _enterPip() {
    if (!PipService.isOwner(this)) return;
    _pushPipState();
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    unawaited(PipService.enterPip(aspectWidth: w, aspectHeight: h));
  }

  /// Arm auto-enter (Home button) for this screen, seeding the current video
  /// aspect so the auto-entered window matches the video shape. No-op unless
  /// this screen is the active, supported PiP owner.
  void _armPipAutoEnter() {
    if (!PipService.isOwner(this)) return;
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    unawaited(PipService.setAutoEnter(true, aspectWidth: w, aspectHeight: h));
  }

  /// Keep the native side's play/pause icon, Next button and window aspect in
  /// sync with the live player — both for an open PiP window and for the next
  /// Home-button auto-enter. No-op unless this screen is the active PiP owner.
  void _pushPipState() {
    if (!PipService.isOwner(this)) return;
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    unawaited(
      PipService.updatePlaybackState(
        isPlaying: _isPlaying,
        hasNext: _hasAnyNext,
        aspectWidth: w,
        aspectHeight: h,
      ),
    );
  }

  /// Collapse the control chrome while inside the small PiP window, and restore
  /// it when the window expands back to fullscreen.
  void _onPipModeChanged(bool inPip) {
    if (!mounted) return;
    if (inPip) {
      _transportVisibility.cancelAutoHide();
      _controlsVisible.value = false;
      _pushPipState();
    }
    setState(() => _isPipActive = inPip);
  }

  /// Handle taps on the PiP window's action buttons.
  void _onPipAction(String action) {
    if (!mounted) return;
    switch (action) {
      case 'playpause':
        _togglePlay();
        break;
      case 'next':
        if (_hasAnyNext) _goToNextEpisode();
        break;
    }
  }

  /// The app left the foreground (Home, power button, app switch): stop
  /// playback instead of decoding video nobody can see. Mobile only — on
  /// desktop a minimized/covered window keeping its audio is normal use, and
  /// desktop power budgets are not why this exists. PiP never gets here: a
  /// visible PiP activity stays at `inactive` (see [_lifecycle]).
  void _pauseForBackground() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // A renderer restart has intentionally invalidated the old player and may
    // not have created the replacement yet. Preserve playback intent without
    // requiring either instance to be live at this exact lifecycle callback.
    if (_rendererFallbackInProgress) {
      _pausedByLifecycle = true;
      if (_playerCreated) unawaited(_player.pause());
      return;
    }
    // _isTransitioning too, not just _isPlaying: mid-switch (next episode, a
    // zap) `playing` is briefly false while an open(play: true) is in flight.
    // Backgrounding in that window must still arm the flag, or the open lands
    // moments later and plays behind the backgrounded app with the guard in
    // the playing listener disarmed. A user's own pause has neither set.
    if (!_playerCreated || (!_isPlaying && !_isTransitioning)) return;
    // A recovery in flight must not re-open streams behind a backgrounded
    // app; the resume path below re-arms recovery when it matters.
    _backgroundedAt = DateTime.now();
    _iptvLiveRecovery.cancel();
    _iptvReconnectText.value = null;
    _pausedByLifecycle = true;
    unawaited(_player.pause());
  }

  /// Undo [_pauseForBackground] when the app returns, restoring the
  /// pre-existing contract that coming back to this screen shows it playing.
  /// A pause the user made themselves (flag unset) stays a pause.
  void _resumeFromBackground() {
    if (!_pausedByLifecycle) return;
    // Cleared BEFORE play(): the playing event this triggers must not read as
    // "playback restarted behind a backgrounded app" to the guard in the
    // playing listener.
    _pausedByLifecycle = false;
    // The replacement player will read the cleared lifecycle flag immediately
    // before open/play. Calling play on the disposing instance would race the
    // one-player ownership guarantee.
    if (_rendererFallbackInProgress) return;
    if (!_playerCreated || !mounted) return;
    // Coming back from the background is not a request to un-stop the night:
    // if the sleep timer fired while we were away, stay paused until someone
    // presses play.
    if (_sleepStopLatched) return;
    // LIVE, back after a real absence: the paused stream is minutes behind
    // the edge (or dead). Re-tune to the live edge — same "comes back
    // playing" contract, at the right point in the broadcast. Short trips
    // keep the cheap in-buffer resume (legitimate timeshift).
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (_currentIptvChannel?.isLive == true &&
        backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt) >
            const Duration(seconds: 30)) {
      _iptvLiveRecovery.userRetry('lifecycle-rejoin');
      return;
    }
    unawaited(_player.play());
  }

  /// The screen wakelock follows PLAYBACK, not this screen's lifetime: a
  /// paused video left on a table must not pin the display on until the
  /// route pops — on phones the display is the single biggest battery
  /// consumer. Buffering stalls keep the lock (media_kit's `playing` tracks
  /// the pause property, which stays false during a stall). initState still
  /// takes the lock up front so the screen can't sleep through a slow
  /// resolve/open before the first playing event arrives.
  void _syncWakelock(bool playing) {
    try {
      if (playing) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {
      // Wakelock not supported on this platform (e.g., Linux).
    }
  }

  @override
  void dispose() {
    ProfileLockController.instance.setPlaybackActive(false);
    _iptvDiag.onSessionEnd();
    _iptvLiveRecovery.cancel();
    _iptvReconnectText.dispose();
    _autoSyncPillHold?.cancel();
    _autoSyncPillPhaseTimer?.cancel();
    _autoSyncPill.dispose();
    // The sleep timer belongs to this playback session — a pending one must not
    // outlive the player and fire against a disposed state.
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _lifecycle?.dispose();
    _recording.detachDesktopRevision();
    _recording.finalizeOnDispose();
    _zap.disposeTimers();
    // Detach from PiP (disarms auto-enter); ignored if a newer player already
    // took ownership, so route replacement can't disarm the incoming screen.
    PipService.detach(this);
    // Scrobble stop to Trakt when user exits player
    _analyticsHeartbeatTimer?.cancel();
    _scrobble.onDispose();

    // Save the current state before disposing
    _resume.saveResume();

    // Cancel any ongoing PikPak retry operations
    _pikPakRetryId++;
    _isPikPakRetrying = false;
    _pikPakRetryCount = 0;
    _pikPakRetryMessage = null;

    _subs.cleanupTempSubtitleFilesSync();
    _skipSegmentsFetchGeneration++;
    _skipSegmentProvider?.close();
    _skipSegmentProvider = null;
    _transportVisibility.cancelAutoHide();
    _autosaveTimer?.cancel();
    _manualSelectionResetTimer?.cancel();
    _debrifyBannerTimer?.cancel();
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
    _presentation.disposeSpeedHoldHud();
    _recording.dispose();
    _subtitleDiagnosticLogSub?.cancel();
    _subtitleSelectionCorrection.dispose();
    _subtitleDiagnosticGeneration++;
    _activeSubtitleApplyAttempt = null;
    _decoderProbeGeneration++;
    _decoderDiagnostics.invalidateToken();
    _rendererStartupGuardToken++;
    _playerInstanceGeneration++;
    _decoderDiagnostics.cancelTimer();
    _posSub?.cancel();
    _durSub?.cancel();
    _playbackUiClock.dispose();
    _activeSkipSegmentUi.dispose();
    _playSub?.cancel();
    _lastLiveChannelTimer?.cancel();
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
    unawaited(_resume.dispose());
    final subtitleAutoSync = _subtitleAutoSync;
    _subtitleAutoSync = null;
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
    // Restore system brightness when exiting the player
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (_) {
      // Screen brightness not supported on this platform (e.g., Linux)
    }
    try {
      WakelockPlus.disable();
    } catch (_) {
      // Wakelock not supported on this platform (e.g., Linux)
    }
    if (Platform.isWindows || Platform.isLinux) {
      windowManager.setFullScreen(false);
    }
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
    super.dispose();
  }

  Timer? _autosaveTimer;

  /// True while the auto-hide poll is being held off by a scrub, a pause, a
  /// route or an overlay — so the tick that finds the blocker gone can grant a
  /// full interval instead of hiding on the spot.


  // ---- Television transport bar -------------------------------------------

  /// Raise the bar and put focus on Play/Pause (not the first button — the
  /// control you want 90% of the time should be under the thumb already).

  /// Lower the bar and take focus back to the player root. Without the second
  /// half the focused control is excluded from the tree and the remote dies.

  /// Cinema scrub: hold LEFT/RIGHT to pause and preview a destination, OK to
  /// confirm, BACK/DOWN to cancel. One seek on confirm, so the trackers and
  /// resume see a single jump instead of a burst.
  void _tvScrubBegin(int direction) {
    if (_tvNoTimeline) return;
    _tvScrubStartedAtGeneration = _tvScrubGeneration;
    _tvScrubWasPlaying = _isPlaying;
    if (_isPlaying) _player.pause();
    _tvScrubTarget = _position;
    _transportVisibility.showBar();
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
    _transportVisibility.scheduleAutoHide();
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
    _scrobbleSeek(target);
    if (_tvScrubWasPlaying) _player.play();
    if (!_anyPlayerOverlayOpen) _tvPlayPauseFocus.requestFocus();
    // Fresh interval: the countdown that was running belonged to the scrub,
    // and inheriting its remainder could drop the bar the instant OK lands.
    _transportVisibility.scheduleAutoHide();
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
    _transportVisibility.scheduleAutoHide();
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
        if (_controlsVisible.value) _transportVisibility.hideBar();
      },
      child: TvControlsScope(
        seek: (target) {
          _player.seek(target);
          _scrobbleSeek(target);
          _transportVisibility.scheduleAutoHide();
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
              onInteract: _transportVisibility.scheduleAutoHide,
              scrubPreview: _tvScrubTarget,
              onPlayPause: _togglePlay,
              onShowTracks: () => _showTracksSheet(context),
              onSpeed: _onSpeedButton,
              onAspect: _onAspectButton,
              onSleepTimer: _showSleepTimerSheet,
              sleepTimerLabel: _sleepTimerButtonLabel,
              speed: _presentation.playbackSpeed,
              aspectMode: _presentation.aspectMode,
              hideOptions: widget.hideOptions,
              onNext: _hasIptvNext
                  ? () => _switchToIptvChannel(_currentIptvIndex + 1)
                  : _zap.canZap
                  ? () => _zap.zap(1)
                  : (_hasAnyNext ? _goToNextEpisode : null),
              onPrevious: _hasIptvPrevious
                  ? () => _switchToIptvChannel(_currentIptvIndex - 1)
                  : _zap.canZap
                  ? () => _zap.zap(-1)
                  : (_hasPreviousEpisode() ? _goToPreviousEpisode : null),
              onNextChannel: widget.requestNextChannel != null
                  ? _goToNextChannel
                  : null,
              onShowPlaylist:
                  (_activePlaylist != null && _activePlaylist!.isNotEmpty) ||
                      _canFetchEpisodes
                  ? () => _showPlaylistSheet(context)
                  : null,
              onShowSources: hasSources ? _showSourceSheetOverlay : null,
              onShowGuide: hasGuide
                  ? (_channelEntries.isNotEmpty &&
                            widget.requestChannelById != null
                        ? _showChannelGuideOverlay
                        : _showStremioTvGuideOverlay)
                  : null,
              onShowIptvChannels: _effectiveIptvChannels?.isNotEmpty == true
                  ? _zap.showChannelSheet
                  : null,
              hasRecord: _canRecord,
              isRecording: _recordingActiveNow,
              onRecord: _canRecord ? _toggleRecording : null,
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
      _transportVisibility.menuVisible;

  /// Closes the topmost overlay and returns focus to the player root, which the
  /// individual hide methods do not do on their own.
  void _closeTopPlayerOverlay() {
    if (_transportVisibility.menuVisible) {
      // Delegate: BACK inside the menu walks values -> rail before closing
      // (tvOS Menu arrives here via PopScope, never as a key).
      if (_playerMenuKey.currentState?.handleHostBack() != true) {
        _transportVisibility.hideMenu();
      }
      // Still open means the press was spent on a pane change.
      if (_transportVisibility.menuVisible) return;
    } else if (_showSyncOverlay) {
      _hideSyncOverlay();
    } else if (_showChannelGuide) {
      _hideChannelGuideOverlay();
    } else if (_showIptvChannelSheet) {
      // Delegate: the guide's own back walks schedule -> channels first, and
      // its close restores a search-interrupted category.
      if (_iptvSheetKey.currentState?.handleHostBack() != true) {
        _zap.hideChannelSheet();
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
      _zap.showChannelSheet();
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
      if ((isLeft || isRight) && _zap.canZap) {
        _zap.zap(isRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (!_controlsVisible.value) {
      if (activate.contains(key)) {
        // While a skip is offered it owns OK: the button is on screen naming
        // the action, and it lives outside the bar's focus scope so the remote
        // has no other way to reach it.
        if (_activeSkipSegment != null) {
          _skipActiveSegment();
          return KeyEventResult.handled;
        }
        // Native TV player: OK both toggles playback and raises the bar.
        _togglePlay();
        _transportVisibility.showBar();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _transportVisibility.showBar();
        return KeyEventResult.handled;
      }
      // UP opens the guide, matching the native TV player. The desktop mapping
      // below only knows the Debrify-TV and Stremio guides, so on an IPTV
      // session it fell through to volume and UP appeared dead.
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_openTvGuide()) return KeyEventResult.handled;
        _transportVisibility.showBar();
        return KeyEventResult.handled;
      }
      if ((isLeft || isRight) && _tvNoTimeline) {
        // No timeline to move along. Hand the key down ONLY when the mapping
        // below has something real to do with it — zapping to the next
        // channel. Falling through unconditionally reached the generic 10s
        // seek, which on a live stream is a blind jump on a rolling window and
        // on a `hideSeekbar` session is exactly the seek that session turned
        // off. And never enter a scrub whose progress row is hidden.
        return _zap.canZap ? null : KeyEventResult.handled;
      }
      if ((isLeft || isRight) && !_zap.canZap) {
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
      _transportVisibility.hideBar();
      return KeyEventResult.handled;
    }
    if ((isLeft || isRight) && _tvProgressFocus.hasFocus) {
      if (!_tvNoTimeline) {
        _tvScrubBegin(isRight ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled; // nothing to scrub; don't fall through
    }
    _transportVisibility.scheduleAutoHide();
    // Traversal and activation belong to the bar's own focus tree.
    return KeyEventResult.ignored;
  }


  void _onControlsVisibilityChanged() {
    _syncPlaybackClockVisibility();
    // The dock carries its own copy of the panel, so the floating one goes the
    // instant the dock opens. Fading it would cross-dissolve two copies of the
    // same panel at two different heights.
    if (_controlsVisible.value) {
      _zap.hideBanner(immediate: true);
      _hideDebrifyBanner(immediate: true);
      // The Record button is about to be looked at — make sure it reflects
      // engine captures stopped from the notification (which this screen
      // otherwise never hears about).
      if (_recording.engineFlagOn) unawaited(_recording.refreshEngineState());
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
    _zap.syncBannerTicker();
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
    _scrobbleSeek(clamped);
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
    try {
      _gestureStartBrightness = await ScreenBrightness().current;
    } catch (_) {
      _gestureStartBrightness = 0.5;
    }
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
      try {
        ScreenBrightness().setScreenBrightness(newBright);
      } catch (_) {
        // Screen brightness not supported on this platform (e.g., Linux)
      }
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
      _scrobbleSeek(target);
    }
    _mode = GestureMode.none;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        _seekHud.value = null;
        _verticalHud.value = null;
      }
    });
  }

  String _format(Duration d) => formatDuration(d);

  void _togglePlay() {
    if (!_isReady) return;
    if (_isPlaying) {
      _activeMediaUserPaused = true;
      _activeMediaShouldPlay = false;
      _player.pause();
    } else {
      // An explicit press is the one thing that clears a sleep stop.
      _sleepStopLatched = false;
      _activeMediaUserPaused = false;
      _activeMediaShouldPlay = true;
      _player.play();
    }
    _transportVisibility.scheduleAutoHide();
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


  // ── Sleep timer ───────────────────────────────────────────────────────────

  /// Whole minutes left, rounded up so a fresh 30-minute timer reads "30".
  int get _sleepTimerMinutesLeft {
    final deadline = _sleepTimerDeadline;
    if (_sleepTimerMode != SleepTimerMode.countdown || deadline == null) {
      return 0;
    }
    final remaining = deadline.difference(DateTime.now()).inMilliseconds;
    if (remaining <= 0) return 0;
    return (remaining / 60000).ceil();
  }

  /// Short label for the controls button, or null when nothing is armed.
  String? get _sleepTimerButtonLabel => switch (_sleepTimerMode) {
    SleepTimerMode.off => null,
    SleepTimerMode.endOfItem => 'Episode',
    SleepTimerMode.countdown => '$_sleepTimerMinutesLeft min',
  };

  Future<void> _showSleepTimerSheet() async {
    if (kUnifiedPlayerMenuEnabled) {
      _openPlayerMenuQuick(PlayerMenuSection.sleep);
      return;
    }
    _transportVisibility.cancelAutoHide();
    final picked = await SleepTimerSheet.show(
      context,
      current: _sleepTimerMode,
      armedMinutes: _sleepTimerArmedMinutes,
      minutesLeft: _sleepTimerMinutesLeft,
      // A live channel has no end to stop at, so only the countdown applies —
      // which is the case people actually want a sleep timer for.
      allowEndOfItem: _currentIptvChannel?.isLive != true,
    );
    if (!mounted) return;
    _transportVisibility.scheduleAutoHide();
    if (picked == null) return;
    _applySleepTimerSelection(picked);
  }

  void _applySleepTimerSelection(SleepTimerSelection picked) {
    switch (picked.mode) {
      case SleepTimerMode.off:
        _cancelSleepTimer();
        _showSleepTimerToast('Sleep timer off');
      case SleepTimerMode.countdown:
        _startSleepCountdown(picked.minutes);
      case SleepTimerMode.endOfItem:
        _cancelSleepTimer();
        setState(() => _sleepTimerMode = SleepTimerMode.endOfItem);
        _showSleepTimerToast('Stopping at the end of this episode');
    }
  }

  void _startSleepCountdown(int minutes) {
    _cancelSleepTimer();
    final duration = Duration(minutes: minutes);
    setState(() {
      _sleepTimerMode = SleepTimerMode.countdown;
      _sleepTimerDeadline = DateTime.now().add(duration);
      _sleepTimerArmedMinutes = minutes;
    });
    _sleepTimer = Timer(duration, _fireSleepTimer);
    _showSleepTimerToast('Sleep timer set for $minutes minutes');
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (_sleepTimerMode == SleepTimerMode.off) return;
    if (mounted) {
      setState(() {
        _sleepTimerMode = SleepTimerMode.off;
        _sleepTimerDeadline = null;
        _sleepTimerArmedMinutes = 0;
      });
    } else {
      _sleepTimerMode = SleepTimerMode.off;
      _sleepTimerDeadline = null;
    }
  }

  /// Stop for the night: persist the position first (losing someone's place
  /// overnight is exactly the moment this feature is meant to be helping),
  /// then pause — which releases the wakelock and lets the screen sleep.
  Future<void> _fireSleepTimer() async {
    _cancelSleepTimer();
    _sleepStopLatched = true;
    _activeMediaShouldPlay = false;
    if (!_playerCreated) return;
    await _resume.saveResume();
    await _player.pause();
    _showSleepTimerToast('Sleep timer ended — paused');
  }

  void _showSleepTimerToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }


  /// Speed button: the menu's Speed pane when the unified menu is on, the
  /// old blind cycle otherwise. Keyboard/long-press cycling is untouched.
  void _onSpeedButton() {
    if (kUnifiedPlayerMenuEnabled) {
      _openPlayerMenuQuick(PlayerMenuSection.speed);
      return;
    }
    _presentation.changeSpeed();
  }

  void _onAspectButton() {
    if (kUnifiedPlayerMenuEnabled) {
      _openPlayerMenuQuick(PlayerMenuSection.aspect);
      return;
    }
    _presentation.cycleAspectMode();
  }



  void _onLongPressStart(LongPressStartDetails details) {
    // Respect the same lock used by the single-tap path
    if (widget.hideBackButton && widget.hideOptions) return;
    // Only engage during playback so a pause-hold doesn't strand speed at 2x
    if (!_isPlaying) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final size = box.size;
      final localPos = details.localPosition;
      // Avoid edge conflicts with the system back gesture
      const edgeGuard = 24.0;
      if (localPos.dx < edgeGuard || localPos.dx > size.width - edgeGuard) {
        return;
      }
      // When controls are visible, skip top/bottom bar regions so buttons/slider win
      if (_controlsVisible.value) {
        const topBar = 72.0;
        final bottomBar = _dockBand(72.0);
        if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) {
          return;
        }
      }
    }
    _presentation.beginHold();
    HapticFeedback.mediumImpact();
  }


  Future<void> _toggleOrientation() async {
    if (_landscapeLocked) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      _landscapeLocked = false;
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _landscapeLocked = true;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) setState(() {});
    _transportVisibility.scheduleAutoHide();
  }

  BoxFit _currentFit() => AspectModeUtils.getBoxFitForMode(_presentation.aspectMode);

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
      customAspectRatio: _getCustomAspectRatio(),
      currentFit: _currentFit(),
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

  Widget? _buildIptvInfoPanel({required bool flush}) =>
      _zap.buildInfoPanel(flush: flush);

  // Get the custom aspect ratio for specific modes
  double? _getCustomAspectRatio() =>
      AspectModeUtils.getAspectRatioValue(_presentation.aspectMode);

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

  static String _pad2(int n) => n.toString().padLeft(2, '0');

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
      title = 'S${_pad2(se.season!)}E${_pad2(se.episode!)} $title';
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
  Future<void> _fetchAndPlayEpisode(int season, int episode) async {
    if (!_canFetchEpisodes || _episodeFetchInProgress) {
      // A next/prev press may have raised the transition curtain already;
      // never leave it up when the request can't run.
      if (mounted && _isTransitioning) {
        setState(() => _isTransitioning = false);
      }
      return;
    }
    final fetcher = widget.seriesSourceFetcher!;
    _episodeFetchInProgress = true;
    final messenger = ScaffoldMessenger.of(context);
    final label = 'S${_pad2(season)}E${_pad2(episode)}';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Fetching $label…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final token = _playlistIdentityToken;

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
        if (await _tryEpisodeCandidate(i, t, season, episode, token)) return;
        if (!mounted || token != _playlistIdentityToken) return;
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
      if (!mounted || token != _playlistIdentityToken) return;
      if (fetched != null && fetched.isNotEmpty) {
        final base = _effectiveSources ?? const <Torrent>[];
        final merged = SeriesSourceFetcher.mergeSources(base, fetched);
        setState(() => _augmentedSources = merged);
        attempts = 0;
        for (var i = base.length; i < merged.length && attempts < 5; i++) {
          final t = merged[i];
          if (t.streamType == StreamType.externalUrl) continue;
          attempts++;
          if (await _tryEpisodeCandidate(i, t, season, episode, token)) return;
          if (!mounted || token != _playlistIdentityToken) return;
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
      if (!mounted || token != _playlistIdentityToken) return;
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
          if (await _tryEpisodeCandidate(i, t, season, episode, token)) return;
          if (!mounted || token != _playlistIdentityToken) return;
        }
      }

      if (mounted && token == _playlistIdentityToken) {
        // A next/prev press raised the transition curtain before calling in
        // here — drop it, or a failed fetch leaves the screen black.
        if (_isTransitioning) {
          setState(() => _isTransitioning = false);
        }
        messenger.showSnackBar(
          SnackBar(content: Text('No playable source found for $label')),
        );
      }
    } finally {
      _episodeFetchInProgress = false;
    }
  }

  /// Resolve one candidate and switch to it when it actually contains the
  /// target episode. Returns true when playback switched (or when the
  /// attempt went stale and the loop must stop).
  Future<bool> _tryEpisodeCandidate(
    int sourceIndex,
    Torrent t,
    int season,
    int episode,
    int token,
  ) async {
    if (!await widget.seriesSourceFetcher!.allowsCandidate(t)) return false;
    if (!mounted || token != _playlistIdentityToken) return true;
    List<PlaylistEntry>? playlist;
    try {
      playlist = await widget.resolveSourceToPlaylist!(t);
    } catch (_) {
      playlist = null;
    }
    if (!mounted || token != _playlistIdentityToken) return true;
    if (playlist == null || playlist.isEmpty) return false;
    if (playlist.length == 1) {
      final info = SeriesParser.parseFilename(playlist.first.title);
      if (info.season == null || info.episode == null) {
        // Unparseable single stream: stamp the target identity into the
        // title so parsing (titles, scrobbling, the guide) stays coherent.
        playlist = [
          playlist.first.copyWithTitle(
            'S${_pad2(season)}E${_pad2(episode)} ${playlist.first.title}',
          ),
        ];
      } else if (info.season != season || info.episode != episode) {
        return false; // resolves to a DIFFERENT episode — wrong result
      }
    } else {
      final sp = SeriesPlaylist.fromPlaylistEntries(
        playlist,
        collectionTitle: widget.title,
        forceSeries: true,
      );
      if (sp.findOriginalIndexBySeasonEpisode(season, episode) < 0) {
        return false; // pack without the target — try the next candidate
      }
    }
    _setManualSelectionMode(allowResume: true);
    await _switchToSourcePlaylist(
      sourceIndex,
      playlist,
      targetSeason: season,
      targetEpisode: episode,
    );
    return true;
  }

  /// The episode adjacent to (season, episode) in the show's full TVMaze
  /// list (specials excluded); null when unknown or out of range.
  (int, int)? _adjacentEpisode(int season, int episode, int direction) {
    final full = _seriesPlaylist?.fullTvmazeEpisodes.isNotEmpty == true
        ? _seriesPlaylist!.fullTvmazeEpisodes
        : (_syntheticGuidePlaylist?.fullTvmazeEpisodes ??
              const <Map<String, dynamic>>[]);
    if (full.isEmpty) return null;
    final eps = <(int, int)>[
      for (final m in full)
        if (m['season'] is int &&
            m['number'] is int &&
            (m['season'] as int) > 0)
          ((m['season'] as int), (m['number'] as int)),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    final idx = eps.indexWhere((p) => p.$1 == season && p.$2 == episode);
    if (idx < 0) return null;
    final target = idx + direction;
    if (target < 0 || target >= eps.length) return null;
    return eps[target];
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
            if (_transportVisibility.menuVisible) {
              return KeyEventResult.ignored;
            }

            // Sync overlay is open - handle its keys first
            if (_showSyncOverlay) {
              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.goBack) {
                _hideSyncOverlay();
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
              _presentation.cycleAspectMode();
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
                _zap.showChannelSheet();
                return KeyEventResult.handled;
              }
            }

            // C -> IPTV channel sheet
            if (key == LogicalKeyboardKey.keyC) {
              if (_effectiveIptvChannels?.isNotEmpty == true) {
                _zap.showChannelSheet();
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
              _transportVisibility.scheduleAutoHide();

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
              _transportVisibility.scheduleAutoHide();

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
                _transportVisibility.toggleControls();
              }
              return KeyEventResult.handled;
            }

            // DPAD left/right zap channels on a live channel with the controls
            // hidden — the same contract as the native player's
            // isLiveIptvZapContext(). There is nothing to seek on a live
            // stream, and with the dock up these keys belong to its buttons.
            if (_zap.canZap && !_controlsVisible.value) {
              if (key == LogicalKeyboardKey.arrowRight) {
                _zap.zap(1);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                _zap.zap(-1);
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
              _scrobbleSeek(newPos);
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
              _scrobbleSeek(newPos);
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
              if (_zap.canZap) {
                _zap.zap(1);
                return KeyEventResult.handled;
              }
              if (widget.requestNextChannel != null) {
                _goToNextChannel();
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.channelDown ||
                key == LogicalKeyboardKey.pageDown) {
              if (_zap.canZap) {
                _zap.zap(-1);
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
                  _getCustomAspectRatio() != null
                      ? _buildCustomAspectRatioVideo()
                      : mkv.Video(
                          key: ValueKey(
                            'video_elevation_${_subtitleSettings?.elevationIndex ?? 0}',
                          ),
                          controller: _videoController,
                          controls: null,
                          fit: _currentFit(),
                          subtitleViewConfiguration: _buildSubtitleViewConfig(),
                        )
                else if (_isTransitioning)
                  // Black screen during transitions to hide previous frame
                  Container(color: Colors.black)
                else
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                if (_startupGateActive && !_startupGateOverlayHidden)
                  ColoredBox(
                    color: Colors.black,
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: PlatformUtil.isTelevision ? 32 : 16,
                            right: PlatformUtil.isTelevision ? 48 : 20,
                          ),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: math.min(
                                PlatformUtil.isTelevision ? 440.0 : 320.0,
                                math.max(
                                  120.0,
                                  MediaQuery.sizeOf(context).width -
                                      (PlatformUtil.isTelevision ? 96.0 : 40.0),
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xE61A1C20),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    color: Colors.white60,
                                    strokeWidth: 1.8,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    _startupGateMessage,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.1,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Transition overlay above video
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
                              : SeekHud(hud: hud, format: _format),
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
                  valueListenable: _presentation.aspectRatioHud,
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
                  valueListenable: _presentation.speedHoldHud,
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
                        _transportVisibility.toggleControls();
                      }
                    },
                    onDoubleTapDown: _handleDoubleTap,
                    onLongPressStart: _onLongPressStart,
                    onLongPressEnd: _presentation.endHold,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
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
                                  onAspect: _onAspectButton,
                                  onSpeed: _onSpeedButton,
                                  onSleepTimer: _showSleepTimerSheet,
                                  sleepTimerLabel: _sleepTimerButtonLabel,
                                  speed: _presentation.playbackSpeed,
                                  aspectMode: _presentation.aspectMode,
                                  isLandscape: _landscapeLocked,
                                  onRotate: _toggleOrientation,
                                  hasPlaylist:
                                      (_activePlaylist != null &&
                                          _activePlaylist!.isNotEmpty) ||
                                      _canFetchEpisodes,
                                  onShowPlaylist: () =>
                                      _showPlaylistSheet(context),
                                  onShowTracks: () => _showTracksSheet(context),
                                  onSeekBarChangedStart: () {
                                    _isSeekingWithSlider = true;
                                    // The viewer owns the position from the
                                    // first touch — release the resume guard
                                    // NOW, not at drag end, or the landing
                                    // verifier could re-issue its target and
                                    // yank playback mid-drag.
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
                                    _transportVisibility.scheduleAutoHide();
                                    if (_lastSliderSeekPos != null) {
                                      _scrobbleSeek(_lastSliderSeekPos!);
                                      _lastSliderSeekPos = null;
                                    }
                                  },
                                  // IPTV episode list (series/VOD) gets Next/Previous
                                  // that walk the season; a live channel gets the
                                  // same pair as previous/next channel, which is the
                                  // only way to zap without a CH +/- key. Falls back
                                  // to the Debrify-TV episode/playlist flow.
                                  onNext: _hasIptvNext
                                      ? () => _switchToIptvChannel(
                                          _currentIptvIndex + 1,
                                        )
                                      : _zap.canZap
                                      ? () => _zap.zap(1)
                                      : (_hasAnyNext ? _goToNextEpisode : null),
                                  onNextChannel:
                                      widget.requestNextChannel != null
                                      ? _goToNextChannel
                                      : null,
                                  onPrevious: _hasIptvPrevious
                                      ? () => _switchToIptvChannel(
                                          _currentIptvIndex - 1,
                                        )
                                      : _zap.canZap
                                      ? () => _zap.zap(-1)
                                      : (_hasPreviousEpisode()
                                            ? _goToPreviousEpisode
                                            : null),
                                  hasNext:
                                      _hasAnyNext ||
                                      _hasIptvNext ||
                                      _zap.canZap,
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
                                      _zap.canZap,
                                  // A live channel has no timeline to scrub: the
                                  // position/duration mpv reports is just the HLS
                                  // rolling window, so the bar counts something
                                  // meaningless and sits under the programme rule,
                                  // which is the progress that actually means
                                  // something here. Derived, not a launch arg, so
                                  // zapping to on-demand brings it straight back.
                                  hideSeekbar:
                                      widget.hideSeekbar ||
                                      _iptvZapBannerOwnsIdentity,
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
                                      ? _zap.showChannelSheet
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
                                      ? _enterPip
                                      : null,
                                  hasRecord: _canRecord,
                                  isRecording: _recordingActiveNow,
                                  onRecord: _canRecord
                                      ? _toggleRecording
                                      : null,
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
                                    onPressed: _skipActiveSegment,
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
                      onChannelSelected: _zap.switchToGuideChannel,
                      onPlayProgramme: _zap.playCatchup,
                      onClose: _zap.hideChannelSheet,
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
                      onContextChanged: _zap.persistGuideContext,
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
                if (_transportVisibility.menuVisible && !inPip)
                  Positioned.fill(child: _buildPlayerMenuPanel()),
                // Subtitle sync overlay
                if (_showSyncOverlay && !inPip) _buildSyncOverlay(),
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
                onHover: (_) => _transportVisibility.wakeOnPointer(),
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
      _transportVisibility.menuVisible;

  /// Called on mouse movement: reveal controls (and the cursor) if hidden and
  /// (re)start the auto-hide countdown so continuous movement keeps them alive.

  String _currentPlaybackTitleForIdentity() {
    if (_activePlaylist != null &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      return _activePlaylist![_currentIndex].title;
    }
    if (_dynamicTitle.isNotEmpty) return _dynamicTitle;
    final stremioTitle = _currentStremioTvContentTitle;
    if (stremioTitle != null && stremioTitle.trim().isNotEmpty) {
      return stremioTitle;
    }
    final contentTitle = config.contentTitle;
    if (contentTitle != null && contentTitle.trim().isNotEmpty) {
      return contentTitle;
    }
    return config.title;
  }


  SeasonEpisodeSelection? _currentSeasonEpisodeForIdentity() {
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final currentEp = _findSeriesEpisodeForCurrentIndex(seriesPlaylist);
      final season = currentEp?.seriesInfo.season;
      final episode = currentEp?.seriesInfo.episode;
      if (season != null && episode != null) {
        return SeasonEpisodeSelection(season: season, episode: episode);
      }
    }

    final seriesInfo = SeriesParser.parseFilename(
      _currentPlaybackTitleForIdentity(),
    );
    final season =
        seriesInfo.season ??
        _manualContentSeason ??
        _currentStremioTvContentSeason ??
        config.contentSeason;
    final episode =
        seriesInfo.episode ??
        _manualContentEpisode ??
        _currentStremioTvContentEpisode ??
        config.contentEpisode;

    if (season == null || episode == null) return null;
    return SeasonEpisodeSelection(season: season, episode: episode);
  }


  Future<void> _showTracksSheet(BuildContext context) async {
    // Dynamically parse season/episode from current video's filename
    final currentTitle = _currentPlaybackTitleForIdentity();
    final seriesInfo = SeriesParser.parseFilename(currentTitle);
    final season =
        seriesInfo.season ?? _manualContentSeason ?? _effectiveContentSeason;
    final episode =
        seriesInfo.episode ?? _manualContentEpisode ?? _effectiveContentEpisode;

    // Get IMDB ID for current item
    // For series: uses shared IMDB ID (all episodes share same show ID)
    // For movies: uses per-item IMDB ID (each movie in collection has unique ID)
    String? effectiveImdbId;
    final seriesPlaylist = _seriesPlaylist;

    if (_manualContentImdbId != null && _manualContentImdbId!.isNotEmpty) {
      effectiveImdbId = _manualContentImdbId;
    } else if (seriesPlaylist != null) {
      if (seriesPlaylist.isSeries) {
        // Series: use shared IMDB ID
        effectiveImdbId = seriesPlaylist.imdbId ?? _effectiveContentImdbId;
      } else {
        // Movie collection: try to get/fetch IMDB ID for current index
        effectiveImdbId = seriesPlaylist.getImdbIdForIndex(_currentIndex);

        // If not cached, try to fetch it now (async but we wait for it)
        if (effectiveImdbId == null && _effectiveContentImdbId == null) {
          debugPrint(
            'VideoPlayer: Fetching movie metadata for index $_currentIndex before showing tracks',
          );
          effectiveImdbId = await seriesPlaylist.fetchMovieMetadataForIndex(
            _currentIndex,
          );
        }

        // Fall back to widget's contentImdbId if still null
        effectiveImdbId ??= _effectiveContentImdbId;
      }
    } else {
      // Single-file playback (no playlist)
      // Try cached single-file IMDB ID, then widget's contentImdbId
      effectiveImdbId = _singleFileImdbId ?? _effectiveContentImdbId;

      // If not cached yet, try to fetch it now
      if (effectiveImdbId == null && !_singleFileImdbFetched) {
        debugPrint(
          'VideoPlayer: Fetching single-file movie metadata before showing tracks',
        );
        await _fetchSingleFileMovieMetadata();
        effectiveImdbId = _singleFileImdbId;
      }
    }

    // Determine content type
    // Priority: manual override > widget/channel metadata > playlist detection
    String? effectiveContentType = _manualContentType ?? _effectiveContentType;
    if (effectiveContentType == null) {
      if (seriesPlaylist?.isSeries == true) {
        effectiveContentType = 'series';
      } else if (effectiveImdbId != null) {
        // We have an IMDB ID (either from playlist or single-file lookup)
        // If not a series, it's a movie
        effectiveContentType = 'movie';
      }
    }

    debugPrint(
      'VideoPlayer: Opening TracksSheet with contentImdbId=$effectiveImdbId, '
      'contentType=$effectiveContentType, '
      'season=$season, episode=$episode (parsed from: $currentTitle)',
    );

    final subtitleSeason = effectiveContentType == 'series' ? season : null;
    final subtitleEpisode = effectiveContentType == 'series' ? episode : null;

    // Build cache key for subtitle caching (per-item like Android TV)
    final String? cacheKey = effectiveImdbId != null
        ? (subtitleSeason != null && subtitleEpisode != null
              ? '$effectiveImdbId:$subtitleSeason:$subtitleEpisode'
              : effectiveImdbId)
        : null;

    // Check if we have cached per-addon subtitle slots for this content.
    final List<AddonSubtitleSlot>? baseSlots =
        (cacheKey != null && _cachedSubtitleKey == cacheKey)
        ? _cachedAddonSlots
        : null;
    // Always include launch-supplied subtitles (e.g. YouTube captions). They
    // aren't IMDb-keyed, so they never live in the per-item cache above and
    // must be appended unconditionally — otherwise identifying the title (which
    // populates _cachedAddonSlots) would make the caption group disappear.
    final List<AddonSubtitleSlot>? cachedSlots = _injectedSubtitleSlots != null
        ? [...?baseSlots, ..._injectedSubtitleSlots!]
        : baseSlots;

    if (cachedSlots != null) {
      debugPrint(
        'VideoPlayer: Using ${cachedSlots.length} cached addon slots for key: $cacheKey',
      );
    }

    if (!context.mounted) return;

    if (kUnifiedPlayerMenuEnabled) {
      _openPlayerMenuAt(
        PlayerMenuSection.subtitles,
        imdbId: effectiveImdbId,
        contentType: effectiveContentType,
        season: subtitleSeason,
        episode: subtitleEpisode,
        cachedSlots: cachedSlots,
        cacheKey: cacheKey,
      );
      return;
    }

    await TracksSheet.show(
      context,
      _player,
      onTrackChanged: (audioId, subtitleId) async {
        _userManuallySelectedSubtitle = true;
        if (!subtitleId.startsWith('stremio:')) {
          _setActiveExternalSubtitlePath(null);
        }
        // Remember the chosen audio language for this IPTV series (carries to
        // later episodes and future sessions). No-op off IPTV.
        _captureIptvAudioLanguage(audioId);
        await _subs.persistTrackChoice(audioId, subtitleId);
      },
      // Fires only on a genuine subtitle switch (not audio, not re-select, not a
      // failed load): the sync offset was calibrated for the previous subtitle.
      onSubtitleTrackChanged: _resetSubtitleSyncOffset,
      // Android bitstream passthrough, applied LIVE (same stored setting as
      // the Playback Defaults row).
      audioPassthrough: !kIsWeb && Platform.isAndroid
          ? _audioPassthroughEnabled
          : null,
      onAudioPassthroughChanged: !kIsWeb && Platform.isAndroid
          ? _setAudioPassthroughLive
          : null,
      onSubtitleStyleChanged: _onSubtitleStyleChanged,
      onSyncOverlayRequested: _showSyncOverlayPanel,
      contentImdbId: effectiveImdbId,
      contentType: effectiveContentType,
      contentSeason: subtitleSeason,
      contentEpisode: subtitleEpisode,
      cachedAddonSlots: cachedSlots,
      onAddonSlotsFetched: (slots) {
        // Cache the per-addon slots (and their flat projection, which the
        // auto-select path consumes) for this content. If the identity was
        // fixed while the sheet was open, the identify flow already re-keyed
        // the cache — updates keyed to the stale open-time identity must not
        // clobber it.
        if (cacheKey == null) return;
        if (_cachedSubtitleKey != null && _cachedSubtitleKey != cacheKey) {
          return;
        }
        _cachedAddonSlots = slots;
        _cachedStremioSubtitles = AddonSubtitleSlot.flatten(slots);
        _cachedSubtitleKey = cacheKey;
      },
      selectedStremioSubtitleId: _selectedStremioSubtitleId,
      subtitleSelectionCorrection: _subtitleSelectionCorrection,
      onStremioSubtitleSelected: (id) {
        _selectedStremioSubtitleId = id;
        _userManuallySelectedSubtitle = true;
      },
      onApplyEmbeddedSubtitle: (track) => _subs.setSubtitleTrackWithDiagnostics(
        track,
        source: 'tracks-sheet-embedded',
      ),
      onApplyStremioSubtitle: _applyStremioSubtitleFromTracksSheet,
      onIdentifyTitle: _subs.identifyTitleAndFetchSubtitles,
      subtitleIdentityLabel: _subs.subtitleIdentityLabelForSheet(),
    );
  }

  // ── Unified player menu (Spotlight panel) ─────────────────────────────

  /// Opens the menu with the subtitle-identity context already resolved
  /// (the tracks-button path, which may await a metadata fetch first).
  void _openPlayerMenuAt(
    PlayerMenuSection section, {
    String? imdbId,
    String? contentType,
    int? season,
    int? episode,
    List<AddonSubtitleSlot>? cachedSlots,
    String? cacheKey,
  }) {
    _zap.hideBanner();
    _transportVisibility.cancelAutoHide();
    _tvReleaseFocusForOverlay();
    setState(() {
      _playerMenuInitialSection = section;
      _menuImdbId = imdbId;
      _menuContentType = contentType;
      _menuSeason = season;
      _menuEpisode = episode;
      _menuCachedSlots = cachedSlots;
      _menuCacheKey = cacheKey;
      _transportVisibility.menuVisible = true;
      _controlsVisible.value = false;
    });
  }

  /// Opens the menu from a non-subtitle entry (speed, sleep, aspect,
  /// shuffle) without awaiting anything: identity comes from caches only.
  /// If the IMDb id was never fetched, the Subtitles pane still offers the
  /// "Fix the title" recovery, so nothing is lost — just not pre-fetched.
  void _openPlayerMenuQuick(PlayerMenuSection section) {
    final currentTitle = _currentPlaybackTitleForIdentity();
    final seriesInfo = SeriesParser.parseFilename(currentTitle);
    final season =
        seriesInfo.season ?? _manualContentSeason ?? _effectiveContentSeason;
    final episode =
        seriesInfo.episode ?? _manualContentEpisode ?? _effectiveContentEpisode;

    String? imdbId;
    final seriesPlaylist = _seriesPlaylist;
    if (_manualContentImdbId != null && _manualContentImdbId!.isNotEmpty) {
      imdbId = _manualContentImdbId;
    } else if (seriesPlaylist != null) {
      imdbId = seriesPlaylist.isSeries
          ? (seriesPlaylist.imdbId ?? _effectiveContentImdbId)
          : (seriesPlaylist.getImdbIdForIndex(_currentIndex) ??
                _effectiveContentImdbId);
    } else {
      imdbId = _singleFileImdbId ?? _effectiveContentImdbId;
    }

    String? contentType = _manualContentType ?? _effectiveContentType;
    if (contentType == null) {
      if (seriesPlaylist?.isSeries == true) {
        contentType = 'series';
      } else if (imdbId != null) {
        contentType = 'movie';
      }
    }

    final subtitleSeason = contentType == 'series' ? season : null;
    final subtitleEpisode = contentType == 'series' ? episode : null;
    final String? cacheKey = imdbId != null
        ? (subtitleSeason != null && subtitleEpisode != null
              ? '$imdbId:$subtitleSeason:$subtitleEpisode'
              : imdbId)
        : null;
    final baseSlots = (cacheKey != null && _cachedSubtitleKey == cacheKey)
        ? _cachedAddonSlots
        : null;
    final cachedSlots = _injectedSubtitleSlots != null
        ? [...?baseSlots, ..._injectedSubtitleSlots!]
        : baseSlots;

    _openPlayerMenuAt(
      section,
      imdbId: imdbId,
      contentType: contentType,
      season: subtitleSeason,
      episode: subtitleEpisode,
      cachedSlots: cachedSlots,
      cacheKey: cacheKey,
    );
  }


  /// The old tracks-sheet `onTrackChanged` closure, verbatim: shared tail of
  /// every track selection made from the menu.
  Future<void> _menuApplyTrackChange(String audioId, String subtitleId) async {
    _userManuallySelectedSubtitle = true;
    if (!subtitleId.startsWith('stremio:')) {
      _setActiveExternalSubtitlePath(null);
    }
    _captureIptvAudioLanguage(audioId);
    await _subs.persistTrackChoice(audioId, subtitleId);
  }

  Future<void> _menuSelectAudio(String audioId, String currentSubId) async {
    final track = _player.state.tracks.audio
        .where((a) => a.id == audioId)
        .firstOrNull;
    if (track == null) return;
    await _player.setAudioTrack(track);
    await _menuApplyTrackChange(audioId, currentSubId);
  }

  Future<bool> _menuSubtitlesOff(String audioId) async {
    final applied = await _subs.setSubtitleTrackWithDiagnostics(
      mk.SubtitleTrack.no(),
      source: 'player-menu-off',
    );
    if (!applied) return false;
    _selectedStremioSubtitleId = null;
    await _menuApplyTrackChange(audioId, 'no');
    return true;
  }

  Future<bool> _menuSelectEmbeddedSubtitle(String subId, String audioId) async {
    final track = _player.state.tracks.subtitle
        .where((s) => s.id == subId)
        .firstOrNull;
    if (track == null) {
      _showSubtitleFailureMessage(
        'That subtitle track is no longer available. Try another track.',
      );
      return false;
    }
    final applied = await _subs.setSubtitleTrackWithDiagnostics(
      track,
      source: 'player-menu-embedded',
    );
    if (!applied) return false;
    _selectedStremioSubtitleId = null;
    await _menuApplyTrackChange(audioId, subId);
    return true;
  }

  /// Returns false when the download/apply failed — the panel keeps the
  /// previous selection (and its sync offset) in that case.
  Future<bool> _menuSelectAddonSubtitle(
    StremioSubtitle sub,
    String audioId,
  ) async {
    // Playback continues behind the menu: if the content switches while the
    // download is in flight (auto-advance, zap), applying the stale subtitle
    // would attach it — and persist its ids — against the NEW item.
    final token = _addonSubtitleFetchToken;
    try {
      final filePath = await _subs.downloadStremioSubtitleToTempFile(sub);
      if (filePath == null) {
        _showSubtitleFailureMessage(
          'Couldn’t load subtitles. Check your connection or try another track.',
        );
        return false;
      }
      if (token != _addonSubtitleFetchToken || !mounted) {
        return false;
      }
      final track = mk.SubtitleTrack.uri(
        filePath,
        title: sub.displayName,
        language: sub.lang,
      );
      final applied = await _subs.applyExternalSubtitleTrack(track);
      if (!applied) return false;
      if (token != _addonSubtitleFetchToken || !mounted) return false;
      _selectedStremioSubtitleId = sub.id;
      _setActiveExternalSubtitlePath(filePath);
      await _menuApplyTrackChange(audioId, 'stremio:${sub.id}');
      return true;
    } catch (e) {
      debugPrint('PlayerMenu: subtitle apply failed - $e');
      _showSubtitleFailureMessage(
        'Couldn’t apply subtitles. Try another embedded or online track.',
      );
      return false;
    }
  }

  Future<bool> _applyStremioSubtitleFromTracksSheet(StremioSubtitle sub) async {
    final token = _addonSubtitleFetchToken;
    try {
      final filePath = await _subs.downloadStremioSubtitleToTempFile(sub);
      if (filePath == null) {
        _showSubtitleFailureMessage(
          'Couldn’t load subtitles. Check your connection or try another track.',
        );
        return false;
      }
      if (token != _addonSubtitleFetchToken || !mounted) {
        return false;
      }
      final applied = await _subs.applyExternalSubtitleTrack(
        mk.SubtitleTrack.uri(
          filePath,
          title: sub.displayName,
          language: sub.lang,
        ),
      );
      if (!applied) return false;
      if (token != _addonSubtitleFetchToken || !mounted) return false;
      _setActiveExternalSubtitlePath(filePath);
      return true;
    } catch (e) {
      debugPrint('TracksSheet: subtitle apply failed - $e');
      _showSubtitleFailureMessage(
        'Couldn’t apply subtitles. Try another embedded or online track.',
      );
      return false;
    }
  }

  Widget _buildPlayerMenuPanel() {
    final audios = _player.state.tracks.audio
        .where((a) => a.id.toLowerCase() != 'no')
        .toList(growable: false);
    final embedded = embeddedSubtitleTracks(_player.state.tracks.subtitle);
    final selectedSub = _selectedStremioSubtitleId != null
        ? 'stremio:$_selectedStremioSubtitleId'
        : _player.state.track.subtitle.id;
    // Captured, not read live: cache write-back must be keyed to the identity
    // the menu opened with (an identity fix re-keys through its own path).
    final cacheKey = _menuCacheKey;

    return PlayerMenuPanel(
      key: _playerMenuKey,
      initialSection: _playerMenuInitialSection,
      onClose: _transportVisibility.hideMenu,
      // mpv's `auto` pseudo-entry heads the list, labeled for what it is —
      // and kept, because persisting 'auto' is the only way to un-pin a
      // stored explicit track for this title (restore treats a stored 'auto'
      // as "use the default selection"). Real tracks are numbered without it
      // so the file's first stream still reads "Track 1".
      audioTracks: LanguageMapper.audioTrackOptions(
        audios,
        (id, label) => PlayerMenuTrackOption(id, label),
      ),
      selectedAudioId: _player.state.track.audio.id,
      onAudioSelected: _menuSelectAudio,
      audioPassthrough: !kIsWeb && Platform.isAndroid
          ? _audioPassthroughEnabled
          : null,
      onAudioPassthroughChanged: !kIsWeb && Platform.isAndroid
          ? _setAudioPassthroughLive
          : null,
      embeddedSubtitles: [
        for (final (i, s) in embedded.indexed)
          PlayerMenuTrackOption(s.id, LanguageMapper.labelForTrack(s, i)),
      ],
      selectedSubtitleId: selectedSub,
      onSubtitlesOff: _menuSubtitlesOff,
      onEmbeddedSubtitleSelected: _menuSelectEmbeddedSubtitle,
      onAddonSubtitleSelected: _menuSelectAddonSubtitle,
      onSubtitleTrackChanged: _resetSubtitleSyncOffset,
      contentImdbId: _menuImdbId,
      contentType: _menuContentType,
      contentSeason: _menuSeason,
      contentEpisode: _menuEpisode,
      cachedAddonSlots: _menuCachedSlots,
      onAddonSlotsFetched: (slots) {
        if (cacheKey == null) return;
        if (_cachedSubtitleKey != null && _cachedSubtitleKey != cacheKey) {
          return;
        }
        _cachedAddonSlots = slots;
        _cachedStremioSubtitles = AddonSubtitleSlot.flatten(slots);
        _cachedSubtitleKey = cacheKey;
      },
      onIdentifyTitle: _subs.identifyTitleAndFetchSubtitles,
      subtitleIdentityLabel: _subs.subtitleIdentityLabelForSheet(),
      onSubtitleStyleChanged: _onSubtitleStyleChanged,
      onSyncRequested: _showSyncOverlayPanel,
      showSpeed: !_iptvZapBannerOwnsIdentity,
      speed: _presentation.playbackSpeed,
      onSpeedSelected: _presentation.setPlaybackSpeed,
      aspectMode: _presentation.aspectMode,
      onAspectSelected: _presentation.setAspectModeDirect,
      sleepMode: _sleepTimerMode,
      sleepArmedMinutes: _sleepTimerArmedMinutes,
      sleepMinutesLeft: _sleepTimerMinutesLeft,
      allowEndOfItem: _currentIptvChannel?.isLive != true,
      onSleepSelected: _applySleepTimerSelection,
      hasPlaylist:
          (_activePlaylist != null && _activePlaylist!.isNotEmpty) ||
          _canFetchEpisodes,
      continuousShuffle: _continuousShuffleEnabled,
      onShuffleOnce: () {
        _transportVisibility.hideMenu();
        unawaited(_playRandomOnce(disableContinuousShuffle: true));
      },
      onShuffleContinuousToggle: () => unawaited(_toggleContinuousShuffle()),
    );
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


  /// Generate a stable hash from filename for non-series playlist state tracking
  String _generateFilenameHash(String filename) {
    // Remove file extension and normalize
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
    // Create a simple hash (we could use a proper hash function, but this is sufficient for our needs)
    final hash = nameWithoutExt.hashCode.toString();
    return hash;
  }
}


class _ResumeSession implements ResumeSession {
  _ResumeSession(this._s);
  final _VideoPlayerScreenState _s;
  @override ResumeWriteGuard get writeGuard => _s._resumeWriteGuard;
  @override int get resumeVerifyEpoch => _s._resumeVerifyEpoch;
  @override List<PlaylistEntry>? get activePlaylist => _s._activePlaylist;
  @override int get currentIndex => _s._currentIndex;
  @override List<IptvChannel>? get effectiveIptvChannels => _s._effectiveIptvChannels;
  @override int get currentIptvIndex => _s._currentIptvIndex;
  @override String get videoUrl => _s.widget.videoUrl;
  @override String get title => _s.widget.title;
  @override PlaybackResumePolicy get resumePolicy => _s.widget.resumePolicy;
  @override double? get traktProgressPercent => _s.widget.traktProgressPercent;
  @override double? get simklProgressPercent => _s.widget.simklProgressPercent;
  @override double? get mdblistProgressPercent => _s.widget.mdblistProgressPercent;
  @override String? get contentImdbId => _s.widget.contentImdbId;
  @override bool get isAutoAdvancing => _s._isAutoAdvancing;
  @override set isAutoAdvancing(bool value) => _s._isAutoAdvancing = value;
  @override bool get isManualEpisodeSelection => _s._isManualEpisodeSelection;
  @override bool get allowResumeForManualSelection => _s._allowResumeForManualSelection;
  @override bool get launchTraktPercentSpent => _s._launchTraktPercentSpent;
  @override set launchTraktPercentSpent(bool value) => _s._launchTraktPercentSpent = value;
  @override bool get launchSimklPercentSpent => _s._launchSimklPercentSpent;
  @override set launchSimklPercentSpent(bool value) => _s._launchSimklPercentSpent = value;
  @override bool get launchMdblistPercentSpent => _s._launchMdblistPercentSpent;
  @override set launchMdblistPercentSpent(bool value) => _s._launchMdblistPercentSpent = value;
  @override Duration get position => _s._position;
  @override Duration get duration => _s._duration;
  @override Duration get playerPosition => _s._player.state.position;
  @override Future<void> seek(Duration target) => _s._player.seek(target);
  @override Future<void> setRate(double speed) => _s._player.setRate(speed);
  @override double get playbackSpeed => _s._presentation.playbackSpeed;
  @override set playbackSpeed(double value) => _s._presentation.playbackSpeed = value;
  @override AspectMode get aspectMode => _s._presentation.aspectMode;
  @override set aspectMode(AspectMode value) => _s._presentation.aspectMode = value;
  @override Future<void> applyAspectVideoZoom() => _s._presentation.applyAspectVideoZoom();
  @override Future<void> waitForDuration() => _s._waitForDuration();
  @override Future<double?> currentEpisodeTraktPercent({bool forGuide = false}) =>
      _s._currentEpisodeTraktPercent(forGuide: forGuide);
  @override Future<double?> currentEpisodeSimklPercent({bool forGuide = false}) =>
      _s._currentEpisodeSimklPercent(forGuide: forGuide);
  @override Future<double?> currentEpisodeMdblistPercent({bool forGuide = false}) =>
      _s._currentEpisodeMdblistPercent(forGuide: forGuide);
  @override String? get currentLocalMovieImdbId => _s._currentLocalMovieImdbId;
  @override SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override String? get effectiveContentType => _s._effectiveContentType;
  @override int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override String? get effectiveContentTitle => _s._effectiveContentTitle;
  @override String? get currentStremioTvContentTitle => _s._currentStremioTvContentTitle;
  @override String? get currentStreamUrl => _s._currentStreamUrl;
  @override bool get validationGateActive => _s._validationGateActive;
  @override bool get isReady => _s._isReady;
  @override bool get isTransitioning => _s._isTransitioning;
  @override bool get currentMovieMarkedAsFinished => _s._currentMovieMarkedAsFinished;
  @override double? get speedBeforeHold => _s._presentation.speedBeforeHold;
  @override bool get isMounted => _s.mounted;
  @override bool get screenDisposed => _s._screenDisposed;
  @override String generateFilenameHash(String filename) =>
      _s._generateFilenameHash(filename);
}

class _SubtitleTrackSession implements SubtitleTrackSession {
  _SubtitleTrackSession(this._s);
  final _VideoPlayerScreenState _s;
  @override mk.Player get player => _s._player;
  @override bool get isMounted => _s.mounted;
  @override BuildContext get hostContext => _s.context;
  @override String get videoTitle => _s.widget.title;
  @override SeriesPlaylist? get seriesPlaylist => _s._seriesPlaylist;
  @override String? get effectiveContentImdbId => _s._effectiveContentImdbId;
  @override String? get effectiveContentType => _s._effectiveContentType;
  @override int? get effectiveContentSeason => _s._effectiveContentSeason;
  @override int? get effectiveContentEpisode => _s._effectiveContentEpisode;
  @override String? get singleFileImdbId => _s._singleFileImdbId;
  @override int? get currentStremioTvContentSeason =>
      _s._currentStremioTvContentSeason;
  @override int? get currentStremioTvContentEpisode =>
      _s._currentStremioTvContentEpisode;
  @override int? get launchContentSeason => _s.config.contentSeason;
  @override int? get launchContentEpisode => _s.config.contentEpisode;
  @override AndroidVideoRendererMode get androidVideoRendererMode =>
      _s._androidVideoRendererMode;
  @override bool get isIptvSeriesContext => _s._isIptvSeriesContext;
  @override int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override int get addonSubtitleFetchToken => _s._addonSubtitleFetchToken;
  @override set addonSubtitleFetchToken(int value) =>
      _s._addonSubtitleFetchToken = value;
  @override int get subtitleDiagnosticGeneration =>
      _s._subtitleDiagnosticGeneration;
  @override set subtitleDiagnosticGeneration(int value) =>
      _s._subtitleDiagnosticGeneration = value;
  @override SubtitleApplyAttempt? get activeSubtitleApplyAttempt =>
      _s._activeSubtitleApplyAttempt;
  @override set activeSubtitleApplyAttempt(SubtitleApplyAttempt? value) =>
      _s._activeSubtitleApplyAttempt = value;
  @override ValueNotifier<String?> get subtitleSelectionCorrection =>
      _s._subtitleSelectionCorrection;
  @override List<StremioSubtitle>? get cachedStremioSubtitles =>
      _s._cachedStremioSubtitles;
  @override set cachedStremioSubtitles(List<StremioSubtitle>? value) =>
      _s._cachedStremioSubtitles = value;
  @override List<AddonSubtitleSlot>? get cachedAddonSlots => _s._cachedAddonSlots;
  @override set cachedAddonSlots(List<AddonSubtitleSlot>? value) =>
      _s._cachedAddonSlots = value;
  @override String? get cachedSubtitleKey => _s._cachedSubtitleKey;
  @override set cachedSubtitleKey(String? value) => _s._cachedSubtitleKey = value;
  @override String? get selectedStremioSubtitleId =>
      _s._selectedStremioSubtitleId;
  @override set selectedStremioSubtitleId(String? value) =>
      _s._selectedStremioSubtitleId = value;
  @override bool get embeddedSubtitleApplied => _s._embeddedSubtitleApplied;
  @override set embeddedSubtitleApplied(bool value) =>
      _s._embeddedSubtitleApplied = value;
  @override bool get userManuallySelectedSubtitle =>
      _s._userManuallySelectedSubtitle;
  @override set userManuallySelectedSubtitle(bool value) =>
      _s._userManuallySelectedSubtitle = value;
  @override bool get trackPreferencesReadyForAddonSubtitles =>
      _s._trackPreferencesReadyForAddonSubtitles;
  @override set trackPreferencesReadyForAddonSubtitles(bool value) =>
      _s._trackPreferencesReadyForAddonSubtitles = value;
  @override Set<String> get tempSubtitleFiles => _s._tempSubtitleFiles;
  @override String? get activeExternalSubtitlePath =>
      _s._activeExternalSubtitlePath;
  @override String? get manualContentImdbId => _s._manualContentImdbId;
  @override set manualContentImdbId(String? value) =>
      _s._manualContentImdbId = value;
  @override String? get manualContentType => _s._manualContentType;
  @override set manualContentType(String? value) =>
      _s._manualContentType = value;
  @override int? get manualContentSeason => _s._manualContentSeason;
  @override set manualContentSeason(int? value) =>
      _s._manualContentSeason = value;
  @override int? get manualContentEpisode => _s._manualContentEpisode;
  @override set manualContentEpisode(int? value) =>
      _s._manualContentEpisode = value;
  @override String? get manualSubtitleDisplayLabel =>
      _s._manualSubtitleDisplayLabel;
  @override set manualSubtitleDisplayLabel(String? value) =>
      _s._manualSubtitleDisplayLabel = value;
  @override void runSetState(VoidCallback updates) =>
      _s._runSubtitleSetState(updates);
  @override void showSubtitleFailureMessage(String message) =>
      _s._showSubtitleFailureMessage(message);
  @override void showSnackBar(String message) {
    if (!_s.mounted) return;
    ScaffoldMessenger.of(_s.context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  @override void setActiveExternalSubtitlePath(String? path) =>
      _s._setActiveExternalSubtitlePath(path);
  @override void resetSubtitleSyncOffset() => _s._resetSubtitleSyncOffset();
  @override void hidePlayerMenuOnContentChange() {
    _s._showSyncOverlay = false;
    // The menu's subtitle pane is keyed to the outgoing item's identity.
    _s._transportVisibility.menuVisible = false;
  }
  @override void reconcileMenuSubtitleSelection(String restoredSelection) {
    _s._playerMenuKey.currentState?.reconcileSubtitleSelection(
      restoredSelection,
    );
  }
  @override Future<void> applyIptvAudioPreference(int ticket) =>
      _s._applyIptvAudioPreference(ticket);
  @override SeriesEpisode? findSeriesEpisodeForCurrentIndex(
    SeriesPlaylist seriesPlaylist,
  ) =>
      _s._findSeriesEpisodeForCurrentIndex(seriesPlaylist);
  @override String currentPlaybackTitleForIdentity() =>
      _s._currentPlaybackTitleForIdentity();
  @override SeasonEpisodeSelection? currentSeasonEpisodeForIdentity() =>
      _s._currentSeasonEpisodeForIdentity();
}


class _IptvZapSession implements IptvZapSession {
  _IptvZapSession(this._s);
  final _VideoPlayerScreenState _s;
  @override bool get isMounted => _s.mounted;
  @override BuildContext get hostContext => _s.context;
  @override List<IptvChannel>? get launchChannels => _s.widget.iptvChannels;
  @override int get currentIptvIndex => _s._currentIptvIndex;
  @override set currentIptvIndex(int value) => _s._currentIptvIndex = value;
  @override int get iptvSwitchTicket => _s._iptvSwitchTicket;
  @override String? get iptvSourceId => _s.widget.iptvSourceId;
  @override String? get iptvSourceName => _s.widget.iptvSourceName;
  @override List<String>? get iptvCategories => _s.widget.iptvCategories;
  @override String? get iptvSelectedCategory => _s.widget.iptvSelectedCategory;
  @override String? get iptvContentType => _s.widget.iptvContentType;
  @override
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
      get iptvBrowseProvider => _s.widget.iptvBrowseProvider;
  @override bool get controlsVisible => _s._controlsVisible.value;
  @override bool get showIptvChannelSheet => _s._showIptvChannelSheet;
  @override bool get showSourceSheet => _s._showSourceSheet;
  @override bool get showChannelGuide => _s._showChannelGuide;
  @override PlayerGuideStyle get playerGuideStyle => _s._playerGuideStyle;
  @override IptvStyleTokens? get playerGuideTokens => _s._playerGuideTokens;
  @override bool get recordingActiveNow => _s._recordingActiveNow;
  @override void runSetState(VoidCallback updates) =>
      _s._runZapSetState(updates);
  @override
  Future<void> onSwitch(IptvChannel channel, {bool quietRecovery = false}) {
    final channels = _s._effectiveIptvChannels;
    if (channels == null) return Future<void>.value();
    final index = channels.indexWhere(
      (candidate) =>
          candidate.url == channel.url && candidate.name == channel.name,
    );
    if (index < 0) return Future<void>.value();
    return _s._switchToIptvChannel(index, quietRecovery: quietRecovery);
  }
  @override
  void openIptvChannelSheet() {
    _s._runZapSetState(() {
      _s._showIptvChannelSheet = true;
      _s._controlsVisible.value = false;
    });
  }
  @override
  void closeIptvChannelSheet() {
    _s._runZapSetState(() => _s._showIptvChannelSheet = false);
  }
  @override bool get iptvErrorsMuted => _s._iptvErrorsMuted;
  @override void noteTuneError(String error) => _s._iptvDiag.onError(error);
  @override bool tryLiveRecoveryOnError() => _s._iptvLiveRecovery.onError();
}

class _IptvRecordingSession implements IptvRecordingSession {
  _IptvRecordingSession(this._s);
  final _VideoPlayerScreenState _s;
  @override mk.Player get player => _s._player;
  @override bool get playerCreated => _s._playerCreated;
  @override bool get isMounted => _s.mounted;
  @override IptvChannel? get currentIptvChannel => _s._currentIptvChannel;
  @override bool get iptvZapBannerOwnsIdentity =>
      _s._iptvZapBannerOwnsIdentity;
  @override String? get currentStreamUrl => _s._currentStreamUrl;
  @override String? get iptvSourceId => _s.widget.iptvSourceId;
  @override List<Map<String, dynamic>>? get iptvSources =>
      _s.widget.iptvSources;
  @override void runSetState(VoidCallback updates) =>
      _s._runRecordingSetState(updates);
  @override void showSnackBar(String message) {
    if (!_s.mounted) return;
    ScaffoldMessenger.of(_s.context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  @override Future<bool> ensureCapacity() =>
      ensureRecordingCapacity(_s.context);
}

class _RandomChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RandomChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFFFCA5A5), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
