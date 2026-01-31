import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

// Removed volume_controller; using media_kit player volume instead
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/storage_service.dart';
import '../services/android_native_downloader.dart';
import '../services/debrid_service.dart';
import '../utils/time_formatters.dart';
import '../utils/series_parser.dart';
import '../services/episode_info_service.dart';
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';

import '../widgets/series_browser.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

// Video Player Components
import 'video_player/models/playlist_entry.dart';
import 'video_player/models/gesture_state.dart';
import 'video_player/models/hud_state.dart';
import 'video_player/painters/double_tap_ripple_painter.dart';
import 'video_player/painters/tv_scanlines_painter.dart';
import 'video_player/painters/tv_vignette_painter.dart';
import 'video_player/utils/gesture_helpers.dart';
import 'video_player/utils/language_mapping.dart';
import 'video_player/utils/aspect_mode_utils.dart';
import 'video_player/constants/timing_constants.dart';
import 'video_player/constants/color_constants.dart';
import 'video_player/widgets/seek_hud.dart';
import 'video_player/widgets/vertical_hud.dart';
import 'video_player/widgets/aspect_ratio_hud.dart';
import 'video_player/widgets/netflix_radio_tile.dart';
import 'video_player/widgets/controls.dart';
import 'video_player/widgets/channel_badge.dart';
import 'video_player/widgets/title_badge.dart';
import 'video_player/widgets/aspect_ratio_video.dart';
import 'video_player/widgets/transition_overlay.dart';
import 'video_player/widgets/pikpak_retry_overlay.dart';
import 'video_player/widgets/tracks_sheet.dart';
import 'video_player/widgets/playlist_sheet.dart';
import 'video_player/widgets/channel_guide.dart';
import 'video_player/models/channel_entry.dart';
import 'video_player/services/subtitle_settings_service.dart';

// Re-export PlaylistEntry for backward compatibility
export 'video_player/models/playlist_entry.dart';
export 'video_player/models/channel_entry.dart';

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

  const VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
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
  })  : assert(randomStartMaxPercent >= 0),
        super(key: key);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with TickerProviderStateMixin {
  late mk.Player _player;
  late mkv.VideoController _videoController;
  final math.Random _random = math.Random();
  SeriesPlaylist? _cachedSeriesPlaylist;
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
  String?
  _currentStreamUrl; // Last resolved stream URL for the active playlist entry

  // PikPak cold storage retry logic
  bool _isPikPakRetrying = false;
  int _pikPakRetryCount = 0;
  String? _pikPakRetryMessage;
  int _pikPakRetryId = 0; // Cancellation token: increments on each new video to cancel old retries

  /// Construct playlist item data for the Fix Metadata feature
  Map<String, dynamic>? _constructPlaylistItemData() {
    // Need at least one identifier
    if ((widget.rdTorrentId == null || widget.rdTorrentId!.isEmpty) &&
        (widget.pikpakCollectionId == null || widget.pikpakCollectionId!.isEmpty) &&
        (widget.playlist == null || widget.playlist!.isEmpty)) {
      return null;
    }

    final data = <String, dynamic>{};

    // Add RealDebrid torrent ID if available
    if (widget.rdTorrentId != null && widget.rdTorrentId!.isNotEmpty) {
      data['rdTorrentId'] = widget.rdTorrentId;
    }

    // Add PikPak collection ID if available
    if (widget.pikpakCollectionId != null && widget.pikpakCollectionId!.isNotEmpty) {
      data['pikpakFileId'] = widget.pikpakCollectionId;
    }

    // Add title
    data['title'] = widget.title;

    return data.isNotEmpty ? data : null;
  }

  SeriesPlaylist? get _seriesPlaylist {
    if (widget.playlist == null || widget.playlist!.isEmpty) return null;
    if (_cachedSeriesPlaylist == null) {
      try {
        // Determine forceSeries: prefer viewMode, then use contentType from catalog
        bool? forceSeries = widget.viewMode?.toForceSeries();
        if (forceSeries == null && widget.contentType != null) {
          // Use catalog content type: 'series' -> force series, 'movie' -> force not series
          forceSeries = widget.contentType == 'series';
        }

        _cachedSeriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          widget.playlist!,
          collectionTitle: widget.title, // Pass video title as fallback
          forceSeries: forceSeries,
        );
      } catch (e) {
        return null;
      }
    }
    return _cachedSeriesPlaylist;
  }

  String? get _channelBadgeText {
    final String? nameSource =
        (_currentChannelName ?? widget.channelName)?.trim();
    final int? numberSource = _currentChannelNumber;

    final bool hasName = nameSource != null && nameSource.isNotEmpty;
    if (!hasName && numberSource == null) {
      return null;
    }

    String formattedNumber = '';
    if (numberSource != null) {
      final int safeNumber = numberSource.clamp(0, 999).toInt();
      formattedNumber = 'CH ${safeNumber.toString().padLeft(2, '0')}';
    }
    if (!hasName) {
      return formattedNumber;
    }

    final upperName = nameSource!.toUpperCase();
    if (formattedNumber.isEmpty) {
      return upperName;
    }
    return '$formattedNumber • $upperName';
  }

  Timer? _hideTimer;
  bool _isSeekingWithSlider = false;

  // Channel badge auto-hide
  bool _showChannelBadge = true;
  Timer? _channelBadgeTimer;

  // Title badge auto-hide
  bool _showTitleBadge = true;
  Timer? _titleBadgeTimer;

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

  // Channel metadata for Debrify TV flows
  String? _currentChannelName;
  int? _currentChannelNumber;
  String? _currentChannelId;

  // Channel guide state
  bool _showChannelGuide = false;
  List<ChannelEntry> _channelEntries = [];

  // Subtitle style settings
  SubtitleSettingsData? _subtitleSettings;

  // media_kit state
  bool _isReady = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isTransitioning = false; // Show black screen during transitions
  // We render using a large logical surface; fit is controlled by BoxFit
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _paramsSub;
  StreamSubscription? _completedSub;

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

  // Aspect / speed
  AspectMode _aspectMode = AspectMode.contain;
  double _playbackSpeed = 1.0;

  // Orientation
  bool _landscapeLocked = false;

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

  Duration? _randomStartOffset(Duration duration) {
    final num clampedPercent =
        widget.randomStartMaxPercent.clamp(0, 99);
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

  @override
  void initState() {
    super.initState();

    // Log playlist entries to trace relativePath
    if (widget.playlist != null && widget.playlist!.isNotEmpty) {
      debugPrint('📺 VideoPlayerScreen.initState: Initialized with ${widget.playlist!.length} playlist entries');
      for (int i = 0; i < widget.playlist!.length && i < 5; i++) {
        final entry = widget.playlist![i];
        debugPrint('  Entry[$i]: title="${entry.title}", relativePath="${entry.relativePath}"');
      }
    }

    if (widget.channelName != null && widget.channelName!.trim().isNotEmpty) {
      _currentChannelName = widget.channelName;
    }
    _currentChannelNumber = widget.channelNumber;
    _parseChannelDirectory();
    _loadSubtitleSettings();
    mk.MediaKit.ensureInitialized();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Default to landscape when entering the player
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _landscapeLocked = true;
    WakelockPlus.enable();
    // System volume UI not modified

    // Initialize the player asynchronously
    _initializePlayer();

    // Init rainbow animation
    _rainbowController = AnimationController(
      vsync: this,
      duration: VideoPlayerTimingConstants.rainbowAnimationDuration,
    );
    _rainbowOpacity = CurvedAnimation(
      parent: _rainbowController,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _initializePlayer() async {
    // Load default player settings
    await _loadPlayerDefaults();

    // Determine the initial URL and index
    String initialUrl = widget.videoUrl;
    int initialIndex = 0;

    if (widget.playlist != null && widget.playlist!.isNotEmpty) {
      // Initialize playlist

      // If auto-resume is disabled, use startIndex directly
      if (widget.disableAutoResume) {
        initialIndex = widget.startIndex ?? 0;
        debugPrint('VideoPlayer: auto-resume disabled, using startIndex=$initialIndex');
      } else {
        // Check if this is a series and we should find the first episode by season/episode
        final seriesPlaylist = _seriesPlaylist;
        if (seriesPlaylist != null && seriesPlaylist.isSeries) {
          // Try to restore the last played episode first
          final lastEpisode = await _getLastPlayedEpisode(seriesPlaylist);
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
              'VideoPlayer: no stored resume for "${seriesPlaylist.seriesTitle}", defaulting to index=$initialIndex',
            );
          }
        } else {
        // For non-series playlists, try to restore the last played video
		if (widget.playlist != null && widget.playlist!.isNotEmpty) {
			// Try to find the last played video by checking each playlist entry
			int lastPlayedIndex = -1;
			Map<String, dynamic>? lastPlayedState;

			for (int i = 0; i < widget.playlist!.length; i++) {
				final entry = widget.playlist![i];
				final resumeId = _resumeIdForEntry(entry);
				debugPrint('Resume: checking entry[$i] title="${entry.title}" resumeId=$resumeId');
				final state = await StorageService.getVideoPlaybackState(
					videoTitle: resumeId,
				);
				if (state != null) {
					debugPrint('Resume: found state for entry[$i] resumeId=$resumeId updatedAt=${state['updatedAt']}');
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
				debugPrint('Resume: no prior playback state found, using default ordering');
				// Pick the first item from Main group (by year asc then size desc)
				final indices = _getMainGroupIndices(widget.playlist!);
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

    // Get the initial URL from the determined index
    if (widget.playlist != null &&
        widget.playlist!.isNotEmpty &&
        initialIndex < widget.playlist!.length) {
      final entry = widget.playlist![initialIndex];
      if (entry.url.isNotEmpty) {
        initialUrl = entry.url;
      } else {
        try {
          final resolvedUrl = await _resolvePlaylistEntryUrl(initialIndex);
          if (resolvedUrl.isNotEmpty) {
            initialUrl = resolvedUrl;
          }
        } catch (e) {
          // Only fall back to widget.videoUrl if resolution fails
          if (widget.videoUrl.isNotEmpty) {
            initialUrl = widget.videoUrl;
          }
        }
      }
    }

    _currentIndex = initialIndex;
    _dynamicTitle = widget.title;
    _player = mk.Player(
      configuration: mk.PlayerConfiguration(
        ready: () {
          _isReady = true;
          if (mounted) {
            setState(() {});
            // Show channel badge when player is ready (if enabled)
            if (widget.showChannelName && _channelBadgeText != null) {
              _showChannelBadgeWithTimer();
            }
            // Show title badge when player is ready (if enabled and in Debrify TV)
            if (widget.showVideoTitle && widget.showChannelName) {
              _showTitleBadgeWithTimer();
            }
          }
        },
      ),
    );
    _videoController = mkv.VideoController(_player);

    _currentStreamUrl = initialUrl.isNotEmpty ? initialUrl : null;

    // Only open the player if we have a valid URL
    if (initialUrl.isNotEmpty) {
      // For PikPak videos from playlist OR Debrify TV, use retry logic
      final currentEntry = widget.playlist?[_currentIndex];
      final isPikPak = currentEntry?.provider?.toLowerCase() == 'pikpak' || currentEntry?.pikpakFileId != null;
      // For Debrify TV (no playlist), check if the URL appears to be PikPak (dl-*.mypikpak.com)
      final isPikPakDebrifyTV = widget.playlist == null && widget.requestMagicNext != null && initialUrl.contains('mypikpak.com');

      if ((isPikPak && widget.playlist != null) || isPikPakDebrifyTV) {
        _playPikPakVideoWithRetry(initialUrl, isDebrifyTV: isPikPakDebrifyTV).then((_) async {
          // Wait for the video to load and duration to be available
          await _waitForVideoReady();
          // Random start takes precedence over resume
          if (widget.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            } else {
              await _maybeRestoreResume();
            }
          } else {
            await _maybeRestoreResume();
          }
          // Restore audio and subtitle track preferences
          await _restoreTrackPreferences();
        });
      } else {
        _player.open(mk.Media(initialUrl, httpHeaders: widget.httpHeaders)).then((_) async {
          // Wait for the video to load and duration to be available
          await _waitForVideoReady();
          // Random start takes precedence over resume
          if (widget.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            } else {
              await _maybeRestoreResume();
            }
          } else {
            await _maybeRestoreResume();
          }
          _scheduleAutoHide();
          // Restore audio and subtitle track preferences
          await _restoreTrackPreferences();
        });
      }
    } else {
      // If no valid URL, try to load the first playlist entry
      if (widget.playlist != null && widget.playlist!.isNotEmpty) {
        _loadPlaylistIndex(_currentIndex, autoplay: false);
      }
    }
    _posSub = _player.stream.position.listen((d) {
      _position = d;
      // throttle UI updates
      if (mounted) setState(() {});
      // Check if episode should be marked as finished (for manual seeking)
      _checkAndMarkEpisodeAsFinished();
    });
    _durSub = _player.stream.duration.listen((d) {
      _duration = d;
      if (mounted) setState(() {});
    });
    _playSub = _player.stream.playing.listen((p) {
      _isPlaying = p;
      if (p && _transitionRunning) {
        // Total 3s: 1.5s static (phase 1) + 1.5s reveal (phase 2)
        _transitionStopTimer?.cancel();
        _transitionPhaseTimer?.cancel();
        _transitionPhase = 1;
        _transitionPhase2Started = null;
        debugPrint(
          'Player: Playback started; overlay phase 1 (static) 1500ms.',
        );
        _transitionPhaseTimer = Timer(const Duration(milliseconds: 1500), () {
          _transitionPhase = 2;
          _transitionPhase2Started = DateTime.now();
          if (mounted) setState(() {});
          debugPrint('Player: Overlay phase 2 (cinematic bars) 1500ms.');
        });
        _transitionStopTimer = Timer(const Duration(milliseconds: 3000), () {
          _rainbowController.stop();
          _transitionRunning = false;
          _rainbowActive = false;
          if (mounted) setState(() {});
          debugPrint('Player: Transition overlay stopped (3s complete).');
        });
      }
      if (mounted) setState(() {});
    });
    // No need to observe video params for sizing; we use a fixed logical surface
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _onPlaybackEnded();
    });

    _autosaveTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _saveResume(debounced: true),
    );

    // Preload episode information if this is a series
    _preloadEpisodeInfo();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channelName != oldWidget.channelName) {
      final String? trimmed = widget.channelName?.trim();
      if ((trimmed == null || trimmed.isEmpty) && _currentChannelName != null) {
        setState(() {
          _currentChannelName = null;
        });
      } else if (trimmed != null && trimmed.isNotEmpty &&
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
      final lastEpisode = await StorageService.getLastPlayedEpisode(
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
    // Mark the current episode as finished if it's a series
    await _markCurrentEpisodeAsFinished();

    // Debrify TV (no playlist): auto-advance using provider if available
    if ((widget.playlist == null || widget.playlist!.isEmpty) &&
        widget.requestMagicNext != null) {
      await _goToNextEpisode();
      return;
    }

    if (widget.playlist == null || widget.playlist!.isEmpty) return;

    // Find the next logical episode
    final nextIndex = _findNextEpisodeIndex();
    if (nextIndex == -1) return; // No next episode found

    // Mark this as auto-advancing to the next episode
    _isAutoAdvancing = true;
    await _loadPlaylistIndex(nextIndex, autoplay: true);
  }

  void _startTransitionOverlay() {
    if (!mounted) return;
    _rainbowActive = true;
    _transitionRunning = true;
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 1;
    // Pick a random retro TV message and reset subtext
    _tvStaticMessage = _tvStaticMessages[
        math.Random().nextInt(_tvStaticMessages.length)];
    _tvStaticSubtext = ''; // Clear subtext until video is ready
    debugPrint('Player: Transition overlay started.');
    // Match Android TV: update every 50ms for smooth static effect
    _rainbowController.repeat(period: VideoPlayerTimingConstants.rainbowRepeatPeriod);
    if (mounted) setState(() {});
  }

  /// Get the current episode title for display
  String _getCurrentEpisodeTitle() {
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        widget.playlist != null) {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return episode title if available, otherwise use the playlist entry title
          if (currentEpisode.episodeInfo?.title != null &&
              currentEpisode.episodeInfo!.title!.isNotEmpty) {
            return currentEpisode.episodeInfo!.title!;
          } else if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            return 'Episode ${currentEpisode.seriesInfo.episode}';
          }
        } catch (e) {}
      }
    }

    // Fallback to the current playlist entry title
    if (widget.playlist != null &&
        _currentIndex >= 0 &&
        _currentIndex < widget.playlist!.length) {
      return widget.playlist![_currentIndex].title;
    }

    // If Debrify TV (no playlist) is active, use dynamic title when available
    if ((widget.playlist == null || widget.playlist!.isEmpty) &&
        widget.requestMagicNext != null) {
      return _dynamicTitle.isNotEmpty ? _dynamicTitle : widget.title;
    }

    // Final fallback
    return widget.title;
  }

  /// Get the current episode subtitle for display
  String? _getCurrentEpisodeSubtitle() {
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        widget.playlist != null) {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
        try {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          // Return series name and season/episode info as subtitle
          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            final seriesName = seriesPlaylist.seriesTitle;
            return '$seriesName • Season ${currentEpisode.seriesInfo.season}, Episode ${currentEpisode.seriesInfo.episode}';
          }
        } catch (e) {}
      }
    }

    // Fallback to the current subtitle or widget subtitle
    return widget.subtitle;
  }

  /// Get enhanced metadata for OTT-style display
  Map<String, dynamic> _getEnhancedMetadata() {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        widget.playlist != null) {
      // Find the current episode info
      if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
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
      if (widget.viewMode == PlaylistViewMode.raw || widget.viewMode == PlaylistViewMode.sorted) {
        if (widget.playlist == null || widget.playlist!.isEmpty) return -1;
        if (_currentIndex + 1 < widget.playlist!.length) {
          return _currentIndex + 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (widget.playlist == null || widget.playlist!.isEmpty) return -1;
      final indices = _getMainGroupIndices(widget.playlist!);
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

  Future<void> _playRandom() async {
    final entries = widget.playlist ?? const [];
    if (entries.isEmpty) return;
    final rnd = math.Random();
    final nextIndex = rnd.nextInt(entries.length);
    _setManualSelectionMode();
    await _loadPlaylistIndex(nextIndex, autoplay: true);
  }

  /// Find the previous logical episode index
  int _findPreviousEpisodeIndex() {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (widget.viewMode == PlaylistViewMode.raw || widget.viewMode == PlaylistViewMode.sorted) {
        if (widget.playlist == null || widget.playlist!.isEmpty) return -1;
        if (_currentIndex - 1 >= 0) {
          return _currentIndex - 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (widget.playlist == null || widget.playlist!.isEmpty) return -1;
      final indices = _getMainGroupIndices(widget.playlist!);
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
    return _findNextEpisodeIndex() != -1;
  }

  /// Check if there's a previous episode available
  bool _hasPreviousEpisode() {
    return _findPreviousEpisodeIndex() != -1;
  }

  /// Navigate to next episode
  Future<void> _goToNextEpisode() async {
    // Check if widget is still mounted before any state changes
    if (!mounted) return;

    // Show black screen during transition to hide previous frame
    setState(() {
      _isTransitioning = true;
    });

    // Only show transition overlay for Debrify TV content (when requestMagicNext is available)
    final isDebrifyTV = widget.requestMagicNext != null;
    if (isDebrifyTV) {
      _startTransitionOverlay();
    }
    try {
      await _player.pause();
    } catch (_) {}
    final nextIndex = _findNextEpisodeIndex();
    if (nextIndex != -1) {
      // Mark this as a manual episode selection
      _setManualSelectionMode();
      await _loadPlaylistIndex(nextIndex, autoplay: true);
      return;
    }

    // If there is no playlist-based next item and Debrify TV provider is present, use it
    if (widget.requestMagicNext != null) {
      debugPrint('Player: MagicTV next requested.');
      try {
        final result = await widget.requestMagicNext!();
        final url = result != null ? (result['url'] ?? '') : '';
        final title = result != null ? (result['title'] ?? '') : '';
        final provider = result != null ? (result['provider'] ?? '') : '';
        final pikpakFileId = result != null ? (result['pikpakFileId'] ?? '') : '';

        if (url.isNotEmpty) {
          debugPrint('Player: MagicTV next success. Opening new URL (provider: $provider, pikpakFileId: $pikpakFileId).');

          // Update TV static overlay to show signal acquired
          if (title.isNotEmpty && mounted) {
            setState(() {
              _tvStaticMessage = '📺 SIGNAL ACQUIRED';
              _tvStaticSubtext = '▶ ${title.toUpperCase()}';
            });
          }

          // Use PikPak retry logic if this is a PikPak video
          final isPikPak = provider.toLowerCase() == 'pikpak' || pikpakFileId.isNotEmpty;
          if (isPikPak) {
            debugPrint('Player: Detected PikPak video from Debrify TV, using retry logic');
            // _playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
            await _playPikPakVideoWithRetry(url, overrideProvider: provider, overridePikPakFileId: pikpakFileId, isDebrifyTV: true);
          } else {
            // Cancel any ongoing PikPak retry when switching to non-PikPak video
            _pikPakRetryId++;
            await _player.open(mk.Media(url, httpHeaders: widget.httpHeaders), play: true);
          }
          _currentStreamUrl = url;
          // If advanced option is enabled, jump to a random timestamp for Debrify TV items
          if (widget.startFromRandom) {
            await _waitForVideoReady();
            final offset = _randomStartOffset(_duration);
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

  /// Load subtitle style settings
  Future<void> _loadSubtitleSettings() async {
    final settings = await SubtitleSettingsService.instance.loadAll();
    if (mounted) {
      setState(() {
        _subtitleSettings = settings;
      });
    }
  }

  /// Load default player settings (aspect)
  Future<void> _loadPlayerDefaults() async {
    // Load default aspect index
    final aspectIndex = await StorageService.getPlayerDefaultAspectIndex();
    const aspects = AspectMode.values;
    _aspectMode = aspects[aspectIndex.clamp(0, aspects.length - 1)];

    debugPrint('VideoPlayer: Loaded defaults - aspect=$_aspectMode');
  }

  /// Update subtitle style settings
  void _onSubtitleStyleChanged(SubtitleSettingsData settings) {
    setState(() {
      _subtitleSettings = settings;
    });
  }

  /// Show channel guide overlay
  void _showChannelGuideOverlay() {
    if (_channelEntries.isEmpty) {
      debugPrint('Player: No channels available for guide');
      return;
    }
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

  /// Switch to a specific channel by ID (from channel guide)
  Future<void> _goToChannelById(ChannelEntry channel) async {
    _hideChannelGuideOverlay();

    final request = widget.requestChannelById;
    if (request == null) {
      debugPrint('Player: requestChannelById not provided');
      return;
    }

    setState(() {
      _isTransitioning = true;
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

    // Show channel badge
    if (widget.showChannelName && _channelBadgeText != null) {
      _showChannelBadgeWithTimer();
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

    try {
      _pikPakRetryId++;
      await _player.open(
          mk.Media(nextUrl, httpHeaders: widget.httpHeaders),
          play: true);
      _currentStreamUrl = nextUrl;
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
      });
    }
  }

  /// Switch to the next Debrify TV channel (MediaKit fallback)
  Future<void> _goToNextChannel() async {
    final request = widget.requestNextChannel;
    if (request == null) {
      return;
    }

    setState(() {
      _isTransitioning = true;
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
      // Show channel badge when switching channels
      if (widget.showChannelName && _channelBadgeText != null) {
        _showChannelBadgeWithTimer();
      }
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

    try {
      // Cancel any ongoing PikPak retry when switching channels
      _pikPakRetryId++;
      await _player.open(mk.Media(nextUrl, httpHeaders: widget.httpHeaders), play: true);
      _currentStreamUrl = nextUrl;
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
    setState(() {
      _isTransitioning = true;
    });

    final previousIndex = _findPreviousEpisodeIndex();
    if (previousIndex != -1) {
      // Mark this as a manual episode selection
      _setManualSelectionMode();
      await _loadPlaylistIndex(previousIndex, autoplay: true);
    } else {
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
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        seriesPlaylist.seriesTitle != null) {
      try {
        // Find the current episode info
        if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            await StorageService.markEpisodeAsFinished(
              seriesTitle: seriesPlaylist.seriesTitle!,
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
            );
          }
        }
      } catch (e) {}
    }
  }

  /// Check if current episode should be marked as finished (for manual seeking)
  Future<void> _checkAndMarkEpisodeAsFinished() async {
    // Only check if we're near the end of the video (within last 30 seconds)
    if (_duration > Duration.zero && _position > Duration.zero) {
      final timeRemaining = _duration - _position;
      if (timeRemaining <= VideoPlayerTimingConstants.endingThreshold) {
        await _markCurrentEpisodeAsFinished();
      }
    }
  }

  Future<void> _loadPlaylistIndex(int index, {bool autoplay = false}) async {
    if (widget.playlist == null ||
        index < 0 ||
        index >= widget.playlist!.length)
      return;

    print('PikPak: _loadPlaylistIndex called with index: $index, autoplay: $autoplay');

    await _saveResume();
    final entry = widget.playlist![index];
    _currentIndex = index;

    print('PikPak: Loading playlist entry - provider: ${entry.provider}, pikpakFileId: ${entry.pikpakFileId}');

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
      return;
    }

    _currentStreamUrl = videoUrl;

    // Check if this is a PikPak video
    final currentEntry = widget.playlist?[index];
    final isPikPak = currentEntry?.provider?.toLowerCase() == 'pikpak' || currentEntry?.pikpakFileId != null;

    // ALWAYS use retry logic for PikPak videos, regardless of autoplay
    if (isPikPak) {
      // For PikPak, we need retry logic even if not autoplaying
      // _playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
      if (autoplay) {
        await _playPikPakVideoWithRetry(videoUrl);
      } else {
        // Still use retry but without autoplay
        await _playPikPakVideoWithRetry(videoUrl);
        await _player.pause(); // Pause after loading if not autoplaying
      }
    } else {
      // Non-PikPak videos play normally
      // Cancel any ongoing PikPak retry when switching to non-PikPak video
      _pikPakRetryId++;
      await _player.open(mk.Media(videoUrl, httpHeaders: widget.httpHeaders), play: autoplay);
    }

    // Wait for the video to load and duration to be available
    await _waitForVideoReady();
    await _maybeRestoreResume();
    // Restore audio and subtitle track preferences
    await _restoreTrackPreferences();

    // Clear transition state when video is ready
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
    }
  }

  Future<String> _resolvePlaylistEntryUrl(int index) async {
    if (widget.playlist == null ||
        index < 0 ||
        index >= widget.playlist!.length) {
      return '';
    }

    final entry = widget.playlist![index];

    if (entry.url.isNotEmpty) {
      return entry.url;
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' || hasTorboxMetadata || hasTorboxWebDownloadMetadata) {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (fileId == null || (torrentId == null && webDownloadId == null)) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await StorageService.getTorboxApiKey();
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

    if (entry.restrictedLink != null) {
      final apiKey = await StorageService.getApiKey();
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
        print('PikPak: Retry cancelled (token mismatch: current=$_pikPakRetryId, expected=$retryId)');
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
      final effectiveDuration = streamDuration > Duration.zero ? streamDuration : directDuration;

      if (effectiveDuration > Duration.zero) {
        print('PikPak: Video duration available (stream: $streamDuration, direct: $directDuration, effective: $effectiveDuration)');

        // Additional verification: wait a bit longer to ensure playback actually started
        // This gives the player time to transition from "has duration" to "is playing"
        // and allows all stream listeners to synchronize their state updates
        print('PikPak: Duration detected, waiting for playback to stabilize...');
        await Future.delayed(const Duration(milliseconds: 800));

        // Check mounted state after delay
        if (!mounted) {
          print('PikPak: Widget disposed during stabilization delay');
          return false;
        }

        // Final cancellation check after stabilization delay
        if (_pikPakRetryId != retryId) {
          print('PikPak: Retry cancelled during stabilization (navigation occurred)');
          return false;
        }

        // Verify playback is actually happening, not just buffering with duration
        // This prevents false positives where duration loads but video won't play
        // Check both stream state and direct player state for reliability
        final streamPlaying = _isPlaying;
        final directPlaying = _player.state.playing;

        if (streamPlaying || directPlaying) {
          print('PikPak: Video confirmed playing - duration: $effectiveDuration, playing: true (stream: $streamPlaying, direct: $directPlaying)');
        } else {
          // Duration is available but playback hasn't started yet
          // This is acceptable - duration alone is sufficient for cold storage detection
          print('PikPak: Duration available ($effectiveDuration), playback will start shortly');
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
    print('PikPak: Timeout waiting for video metadata (${totalTimeoutSeconds}s elapsed)');
    return false;
  }

  /// Attempts to play a PikPak video with retry logic for cold storage
  Future<void> _playPikPakVideoWithRetry(String videoUrl, {String? overrideProvider, String? overridePikPakFileId, bool isDebrifyTV = false}) async {
    // Only apply retry logic for PikPak videos
    // Support both playlist entries and Debrify TV (requestMagicNext) flows
    final currentEntry = widget.playlist != null && _currentIndex >= 0 && _currentIndex < widget.playlist!.length
        ? widget.playlist![_currentIndex]
        : null;
    final isPikPak = overrideProvider?.toLowerCase() == 'pikpak' ||
        overridePikPakFileId != null ||
        currentEntry?.provider?.toLowerCase() == 'pikpak' ||
        currentEntry?.pikpakFileId != null ||
        isDebrifyTV; // Debrify TV PikPak videos are also PikPak

    print('PikPak: _playPikPakVideoWithRetry called for index $_currentIndex, isPikPak: $isPikPak, overrideProvider: $overrideProvider, overridePikPakFileId: $overridePikPakFileId, isDebrifyTV: $isDebrifyTV');

    if (!isPikPak) {
      // Not a PikPak video, play normally
      await _player.open(mk.Media(videoUrl, httpHeaders: widget.httpHeaders), play: true);
      return;
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
      await _player.open(mk.Media(videoUrl, httpHeaders: widget.httpHeaders), play: true);
    } catch (e) {
      print('PikPak: Initial player.open() failed with error: $e');
      // Continue with retry loop - might work on subsequent attempts
    }

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // Check if cancelled before starting attempt
        if (_pikPakRetryId != myRetryId) {
          print('PikPak: Retry loop cancelled before attempt ${attempt + 1} (navigation occurred)');
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (mounted) {
            setState(() {});
          }
          return;
        }

        print('PikPak: Monitoring attempt ${attempt + 1}/${maxRetries + 1}...');

        // Calculate delay for this attempt (0 for first attempt)
        final delaySeconds = attempt == 0 ? 0 : (baseDelaySeconds * (1 << (attempt - 1)));
        final cappedDelay = delaySeconds > maxDelaySeconds ? maxDelaySeconds : delaySeconds;

        // CRITICAL FIX: Wait for video metadata with EXTENDED monitoring during delay period
        // This allows detection of video loading DURING the delay, preventing unnecessary player resets
        print('PikPak: Waiting for video duration (${metadataTimeoutSeconds}s) + monitoring during delay (${cappedDelay}s)...');
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
          return;
        }

        // Video didn't load even after monitoring during delay
        print('PikPak: Video metadata failed to load after ${metadataTimeoutSeconds + cappedDelay}s - file likely in cold storage');

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
            } else {
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
          return; // Exit function
        }

        // Still have retries left - continue with retry logic
        // Calculate delay for NEXT attempt
        final nextDelaySeconds = baseDelaySeconds * (1 << attempt);
        final nextDelay = nextDelaySeconds > maxDelaySeconds ? maxDelaySeconds : nextDelaySeconds;

        // Update UI to show retry state
        if (mounted) {
          setState(() {
            _isPikPakRetrying = true;
            _pikPakRetryCount = attempt + 1;
            _pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print('PikPak: Retry ${attempt + 1} - reopening player and waiting ${nextDelay}s before next check...');

        // Check if widget was disposed
        if (!mounted) {
          print('PikPak: Widget disposed before retry');
          return;
        }

        // Check if cancelled
        if (_pikPakRetryId != myRetryId) {
          print('PikPak: Retry loop cancelled before reopening player (navigation occurred)');
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (mounted) {
            setState(() {});
          }
          return;
        }

        // Try reopening the player (might help reactivate cold storage file)
        try {
          await _player.open(mk.Media(videoUrl, httpHeaders: widget.httpHeaders), play: true);
        } catch (e) {
          print('PikPak: Retry ${attempt + 1} - player.open() failed with error: $e');
          // Continue - the monitoring in next iteration might still detect if it loads
        }
      } catch (e) {
        print('PikPak: Retry attempt ${attempt + 1} failed with error: $e');

        // Check if this was the last attempt (all retries exhausted)
        if (attempt >= maxRetries) {
          // ALL RETRIES EXHAUSTED - handle here
          print('PikPak: All retry attempts exhausted after error. Video failed to load.');

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
            } else {
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
          return; // Exit function
        }

        // Still have retries left - continue with retry logic
        // Calculate delay for next attempt
        final delaySeconds = baseDelaySeconds * (1 << attempt);
        final nextDelay = delaySeconds > maxDelaySeconds ? maxDelaySeconds : delaySeconds;

        if (mounted) {
          setState(() {
            _isPikPakRetrying = true;
            _pikPakRetryCount = attempt + 1;
            _pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print('PikPak: Error in attempt ${attempt + 1}, waiting ${nextDelay}s before retry...');

        // Check if widget was disposed
        if (!mounted) {
          print('PikPak: Widget disposed during error handling');
          return;
        }

        // Check if cancelled
        if (_pikPakRetryId != myRetryId) {
          print('PikPak: Retry loop cancelled during error handling (navigation occurred)');
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (mounted) {
            setState(() {});
          }
          return;
        }

        // Try reopening the player for next attempt
        try {
          await _player.open(mk.Media(videoUrl, httpHeaders: widget.httpHeaders), play: true);
        } catch (reopenError) {
          print('PikPak: Error retry - player.open() failed with error: $reopenError');
          // Continue - next iteration might succeed
        }
      }

      attempt++;
    }
  }

  /// Preload episode information in the background
  Future<void> _preloadEpisodeInfo() async {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      // Preload episode information in the background
      // Pass IMDB ID from catalog for faster, more accurate lookup
      seriesPlaylist
          .fetchEpisodeInfo(
            playlistItem: _constructPlaylistItemData(),
            imdbId: widget.contentImdbId,
          )
          .then((_) async {
            // Extract poster URL from series data and save to playlist
            await _saveSeriesPosterToPlaylist(seriesPlaylist);

            // Trigger UI update to show the episode info
            if (mounted) {
              setState(() {});
            }
          })
          .catchError((error) {
            // Silently handle errors - this is just preloading
          });
    }
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

    // Try to get series info to extract poster URL
    try {
      print('  Fetching series info from TVMaze...');
      final seriesInfo = await EpisodeInfoService.getSeriesInfo(
        seriesPlaylist.seriesTitle!,
      );

      if (seriesInfo != null && seriesInfo['image'] != null) {
        final posterUrl =
            seriesInfo['image']['original'] ?? seriesInfo['image']['medium'];
        print('  Poster URL from TVMaze: $posterUrl');

        if (posterUrl != null && posterUrl.isNotEmpty) {
          // Save poster URL to playlist item (supports RealDebrid, Torbox, and PikPak)
          if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
            print('  Saving poster for RealDebrid item...');
            final success = await StorageService.updatePlaylistItemPoster(
              posterUrl,
              rdTorrentId: rdTorrentId,
            );
            print('  RealDebrid poster save: ${success ? "SUCCESS" : "FAILED"}');
          }
          if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
            print('  Saving poster for Torbox item...');
            final success = await StorageService.updatePlaylistItemPoster(
              posterUrl,
              torboxTorrentId: torboxTorrentId,
            );
            print('  Torbox poster save: ${success ? "SUCCESS" : "FAILED"}');
          }
          if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
            print('  Saving poster for PikPak item...');
            final success = await StorageService.updatePlaylistItemPoster(
              posterUrl,
              pikpakCollectionId: pikpakCollectionId,
            );
            print('  PikPak poster save: ${success ? "SUCCESS" : "FAILED"}');
          }
        } else {
          print('  ⚠️ No poster URL found in series info');
        }
      } else {
        print('  ⚠️ No series info or image found from TVMaze');
      }
    } catch (e) {
      print('  ❌ Error saving poster: $e');
      // Silently fail - poster is optional
    }
  }

  @override
  void dispose() {
    // Save the current state before disposing
    _saveResume();

    // Cancel any ongoing PikPak retry operations
    _pikPakRetryId++;
    _isPikPakRetrying = false;
    _pikPakRetryCount = 0;
    _pikPakRetryMessage = null;

    _hideTimer?.cancel();
    _autosaveTimer?.cancel();
    _manualSelectionResetTimer?.cancel();
    _channelBadgeTimer?.cancel();
    _titleBadgeTimer?.cancel();
    _controlsVisible.dispose();
    _seekHud.dispose();
    _verticalHud.dispose();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _paramsSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    _transitionStopTimer?.cancel();
    _rainbowController.dispose();
    // Restore system brightness when exiting the player
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    AndroidNativeDownloader.isTelevision().then((isTv) {
      if (!isTv) {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]);
      }
    });
    super.dispose();
  }

  Timer? _autosaveTimer;

	String get _resumeKey {
		if (widget.playlist != null &&
			widget.playlist!.isNotEmpty &&
			_currentIndex >= 0 &&
			_currentIndex < widget.playlist!.length) {
			final entry = widget.playlist![_currentIndex];

			// Check for Torbox-specific key
			final torboxKey = _torboxResumeKeyForEntry(entry);
			if (torboxKey != null) {
				debugPrint('ResumeKey: using torbox key $torboxKey for index $_currentIndex');
				return torboxKey;
			}

			// Check for PikPak-specific key
			final pikpakKey = _pikpakResumeKeyForEntry(entry);
			if (pikpakKey != null) {
				debugPrint('ResumeKey: using pikpak key $pikpakKey for index $_currentIndex');
				return pikpakKey;
			}
		}

		// Use playlist-specific resume ID for other items
		if (widget.playlist != null &&
			widget.playlist!.isNotEmpty &&
			_currentIndex >= 0 &&
			_currentIndex < widget.playlist!.length) {
			final id = _resumeIdForEntry(widget.playlist![_currentIndex]);
			debugPrint('ResumeKey: using playlist entry id $id for index $_currentIndex');
			return id;
		}

		// Fallback to videoUrl for single items
		// Note: This is the expected path for Debrify TV mode
		return widget.videoUrl;
	}

	String? _torboxResumeKeyForEntry(PlaylistEntry entry) {
		final provider = entry.provider?.toLowerCase();
		if (provider == 'torbox') {
			final torrentId = entry.torboxTorrentId;
			final webDownloadId = entry.torboxWebDownloadId;
			final fileId = entry.torboxFileId;
			if (webDownloadId != null && fileId != null) {
				debugPrint('ResumeKey: torbox web download detected web=$webDownloadId file=$fileId');
				return 'torbox_web_${webDownloadId}_$fileId';
			}
			if (torrentId != null && fileId != null) {
				debugPrint('ResumeKey: torbox entry detected torrent=$torrentId file=$fileId');
				return 'torbox_${torrentId}_$fileId';
			}
			debugPrint('ResumeKey: torbox entry missing IDs torrent=$torrentId web=$webDownloadId file=$fileId');
		}
		return null;
	}

	String? _pikpakResumeKeyForEntry(PlaylistEntry entry) {
		final provider = entry.provider?.toLowerCase();
		if (provider == 'pikpak') {
			final fileId = entry.pikpakFileId;
			if (fileId != null && fileId.isNotEmpty) {
				debugPrint('ResumeKey: pikpak entry detected fileId=$fileId');
				return 'pikpak_$fileId';
			}
			debugPrint('ResumeKey: pikpak entry missing fileId');
		}
		return null;
	}

	String _resumeIdForEntry(PlaylistEntry entry) {
		// Check for Torbox-specific key
		final torboxKey = _torboxResumeKeyForEntry(entry);
		if (torboxKey != null) {
			return torboxKey;
		}
		// Check for PikPak-specific key
		final pikpakKey = _pikpakResumeKeyForEntry(entry);
		if (pikpakKey != null) {
			return pikpakKey;
		}
		// Fallback to filename hash
		final name = entry.title.isNotEmpty ? entry.title : widget.title;
		return _generateFilenameHash(name);
	}

  Future<void> _maybeRestoreResume() async {
    // If this is auto-advancing, don't restore position
    if (_isAutoAdvancing) {
      _isAutoAdvancing = false; // Reset the flag
      return;
    }

    // If this is a manual episode selection, only restore if we have saved progress
    if (_isManualEpisodeSelection && !_allowResumeForManualSelection) {
      // Don't reset _isManualEpisodeSelection here - let it be reset after a delay
      return;
    }

    // Try enhanced playback state first
    final enhancedData = await _getEnhancedPlaybackState();
    if (enhancedData != null) {
      // Wait for duration to be available before attempting position restoration
      await _waitForDuration();

      final posMs = (enhancedData['positionMs'] ?? 0) as int;
      final speed = (enhancedData['speed'] ?? 1.0) as double;
      final aspect = (enhancedData['aspect'] ?? 'contain') as String;
      final position = Duration(milliseconds: posMs);
      final dur = _duration;

      if (dur > Duration.zero &&
          position > const Duration(seconds: 2) &&
          position < dur * 0.9) {
        await _player.seek(position);
      }

      // restore speed
      if (speed != 1.0) {
        await _player.setRate(speed);
        _playbackSpeed = speed;
      }

      // restore aspect
      _aspectMode = AspectModeUtils.stringToAspectMode(aspect);
      return;
    }
    // Fallback to legacy resume system
    // Wait for duration to be available before attempting position restoration
    await _waitForDuration();
    final data = await StorageService.getVideoResume(_resumeKey);
    if (data == null) {
      return;
    }

    final posMs = (data['positionMs'] ?? 0) as int;
    final speed = (data['speed'] ?? 1.0) as double;
    final aspect = (data['aspect'] ?? 'contain') as String;
    final position = Duration(milliseconds: posMs);
    final dur = _duration;

    if (dur > Duration.zero &&
        position > const Duration(seconds: 2) &&
        position < dur * 0.9) {
      await _player.seek(position);
    }

    // restore speed
    if (speed != 1.0) {
      await _player.setRate(speed);
      _playbackSpeed = speed;
    }
    // restore aspect
    _aspectMode = AspectModeUtils.stringToAspectMode(aspect);
  }

  /// Get enhanced playback state for current content
  Future<Map<String, dynamic>?> _getEnhancedPlaybackState() async {
    try {
      final seriesPlaylist = _seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series, get the current episode info
        if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Only restore position for the exact same episode
            final playbackState = await StorageService.getSeriesPlaybackState(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
            );

            return playbackState;
          }
        }
      } else {
        // For non-series content, check if we have a playlist
		if (widget.playlist != null && widget.playlist!.isNotEmpty) {
			PlaylistEntry? currentEntry;
			if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
				currentEntry = widget.playlist![_currentIndex];
			}

			if (currentEntry != null) {
				final resumeId = _resumeIdForEntry(currentEntry);
				debugPrint('Resume Load: fetching state for resumeId=$resumeId');
				final videoState = await StorageService.getVideoPlaybackState(
					videoTitle: resumeId,
				);
				if (videoState != null) {
					debugPrint('Resume Load: found state for resumeId=$resumeId updatedAt=${videoState['updatedAt']}');
					return videoState;
				}
			}
		}

        // Fallback to collection-based state (legacy behavior)
        final videoTitle = widget.title.isNotEmpty
            ? widget.title
            : 'Unknown Video';

        final videoState = await StorageService.getVideoPlaybackState(
          videoTitle: videoTitle,
        );

        return videoState;
      }
    } catch (e) {}
    return null;
  }

  Future<void> _saveResume({bool debounced = false}) async {
    if (!_isReady) {
      return;
    }

    // If this is a manual episode selection and it's been less than 30 seconds, skip saving
    // This gives the user time to seek to where they want
    if (_isManualEpisodeSelection && debounced) {
      return;
    }

    final pos = _position;
    final dur = _duration;
    if (dur <= Duration.zero) {
      return;
    }

    final aspectStr = AspectModeUtils.aspectModeToString(_aspectMode);

    // Save to enhanced playback state system
    try {
      final seriesPlaylist = _seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content
        if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            await StorageService.saveSeriesPlaybackState(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: _playbackSpeed,
              aspect: aspectStr,
            );
          }
        }
      } else {
        // For non-series content
		if (widget.playlist != null && widget.playlist!.isNotEmpty) {
			PlaylistEntry? currentEntry;
			if (_currentIndex >= 0 && _currentIndex < widget.playlist!.length) {
				currentEntry = widget.playlist![_currentIndex];
			}

			if (currentEntry != null) {
				final resumeId = _resumeIdForEntry(currentEntry);
				debugPrint('Resume Save: storing state resumeId=$resumeId pos=${pos.inMilliseconds} dur=${dur.inMilliseconds}');
				String currentVideoUrl = '';
				if (_currentStreamUrl != null && _currentStreamUrl!.isNotEmpty) {
					currentVideoUrl = _currentStreamUrl!;
				} else if (currentEntry.url.isNotEmpty) {
					currentVideoUrl = currentEntry.url;
				} else if (widget.videoUrl.isNotEmpty) {
					currentVideoUrl = widget.videoUrl;
				}

				await StorageService.saveVideoPlaybackState(
					videoTitle: resumeId,
					videoUrl: currentVideoUrl,
					positionMs: pos.inMilliseconds,
					durationMs: dur.inMilliseconds,
					speed: _playbackSpeed,
					aspect: aspectStr,
				);

				// ALSO save in collection format for playlist progress tracking
				// This allows the playlist screen to display progress indicators
				debugPrint('💾 Collection Save Check: seriesPlaylist=${seriesPlaylist != null}, seriesTitle="${seriesPlaylist?.seriesTitle}", isSeries=${seriesPlaylist?.isSeries}');
				if (seriesPlaylist != null && seriesPlaylist.seriesTitle != null) {
					// Parse season/episode from filename for consistent progress tracking across view modes
					final seriesInfo = SeriesParser.parseFilename(currentEntry.title);
					final season = seriesInfo.season ?? 0;
					final episode = seriesInfo.episode ?? (_currentIndex + 1);

					await StorageService.saveSeriesPlaybackState(
						seriesTitle: seriesPlaylist.seriesTitle!,
						season: season, // Parsed from filename, fallback to 0
						episode: episode, // Parsed from filename, fallback to index
						positionMs: pos.inMilliseconds,
						durationMs: dur.inMilliseconds,
						speed: _playbackSpeed,
						aspect: aspectStr,
					);
					debugPrint('✅ Collection Save: title="${seriesPlaylist.seriesTitle}" S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} (index=${_currentIndex}) filename="${currentEntry.title}"');
				} else {
					debugPrint('❌ Collection Save SKIPPED: seriesPlaylist is null or has no title');
				}
			}
		} else {
			// Single video file (no playlist)
          final currentUrl = widget.videoUrl;
          final videoTitle = widget.title.isNotEmpty
              ? widget.title
              : 'Unknown Video';

          await StorageService.saveVideoPlaybackState(
            videoTitle: videoTitle,
            videoUrl: currentUrl,
            positionMs: pos.inMilliseconds,
            durationMs: dur.inMilliseconds,
            speed: _playbackSpeed,
            aspect: aspectStr,
          );
        }
      }
    } catch (e) {}

    // Also save to legacy system for backward compatibility
    await StorageService.upsertVideoResume(_resumeKey, {
      'positionMs': pos.inMilliseconds,
      'speed': _playbackSpeed,
      'aspect': aspectStr,
      'durationMs': dur.inMilliseconds,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(VideoPlayerTimingConstants.controlsAutoHideDuration, () {
      if (mounted) {
        _controlsVisible.value = false;
      }
    });
  }

  void _toggleControls() {
    _controlsVisible.value = !_controlsVisible.value;
    if (_controlsVisible.value) {
      _scheduleAutoHide();
      // Show channel badge when controls appear (if enabled)
      if (widget.showChannelName && _channelBadgeText != null) {
        _showChannelBadgeWithTimer();
      }
      // Show title badge when controls appear (if enabled and in Debrify TV)
      if (widget.showVideoTitle && widget.showChannelName) {
        _showTitleBadgeWithTimer();
      }
    }
  }

  void _showChannelBadgeWithTimer() {
    // Cancel any existing timer
    _channelBadgeTimer?.cancel();
    // Show the badge
    setState(() {
      _showChannelBadge = true;
    });
    // Hide after 4 seconds (matching Android TV behavior)
    _channelBadgeTimer = Timer(VideoPlayerTimingConstants.badgeDisplayDuration, () {
      if (mounted) {
        setState(() {
          _showChannelBadge = false;
        });
      }
    });
  }

  void _showTitleBadgeWithTimer() {
    // Cancel any existing timer
    _titleBadgeTimer?.cancel();
    // Show the badge
    setState(() {
      _showTitleBadge = true;
    });
    // Hide after 4 seconds (matching Android TV behavior)
    _titleBadgeTimer = Timer(VideoPlayerTimingConstants.badgeDisplayDuration, () {
      if (mounted) {
        setState(() {
          _showTitleBadge = false;
        });
      }
    });
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
      const bottomBar = 72.0;
      if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) return;
    }

    // Check if we're on Android and if the tap is in the far right area for next episode
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final farRightThreshold = size.width * 0.8; // Far right 20% of screen

    if (isAndroid && localPos.dx > farRightThreshold) {
      // Double tap on far right for next episode on Android
      if (_hasNextEpisode() || widget.requestMagicNext != null) {
        _ripple = DoubleTapRipple(
          center: localPos,
          icon: Icons.skip_next_rounded,
        );
        setState(() {});
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted) setState(() => _ripple = null);
        });
        await _goToNextEpisode();
        return;
      }
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
        const bottomBar = 72.0;
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
      ScreenBrightness().setScreenBrightness(newBright);
      _verticalHud.value = VerticalHudState(
        kind: VerticalKind.brightness,
        value: newBright,
      );
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panIgnore) return;
    if (_mode == GestureMode.seek && _seekHud.value != null) {
      _player.seek(_seekHud.value!.target);
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
      _player.pause();
    } else {
      _player.play();
    }
    _scheduleAutoHide();
  }

  /// Sets manual episode selection mode with automatic reset after 30 seconds
  void _setManualSelectionMode({bool allowResume = false}) {
    _isManualEpisodeSelection = true;
    _allowResumeForManualSelection = allowResume;
    _manualSelectionResetTimer?.cancel();
    _manualSelectionResetTimer = Timer(VideoPlayerTimingConstants.manualSelectionResetDuration, () {
      _isManualEpisodeSelection = false;
      _allowResumeForManualSelection = false;
    });
  }

  void _cycleAspectMode() {
    AspectMode newMode;
    String modeName;
    IconData modeIcon;

    switch (_aspectMode) {
      case AspectMode.contain:
        newMode = AspectMode.cover;
        modeName = 'Cover';
        modeIcon = Icons.crop_free_rounded;
        break;
      case AspectMode.cover:
        newMode = AspectMode.fitWidth;
        modeName = 'Fit Width';
        modeIcon = Icons.fit_screen_rounded;
        break;
      case AspectMode.fitWidth:
        newMode = AspectMode.fitHeight;
        modeName = 'Fit Height';
        modeIcon = Icons.fit_screen_rounded;
        break;
      case AspectMode.fitHeight:
        newMode = AspectMode.aspect16_9;
        modeName = '16:9';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect16_9:
        newMode = AspectMode.aspect4_3;
        modeName = '4:3';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect4_3:
        newMode = AspectMode.aspect21_9;
        modeName = '21:9';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect21_9:
        newMode = AspectMode.aspect1_1;
        modeName = '1:1';
        modeIcon = Icons.crop_square_rounded;
        break;
      case AspectMode.aspect1_1:
        newMode = AspectMode.aspect3_2;
        modeName = '3:2';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect3_2:
        newMode = AspectMode.aspect5_4;
        modeName = '5:4';
        modeIcon = Icons.aspect_ratio_rounded;
        break;
      case AspectMode.aspect5_4:
        newMode = AspectMode.contain;
        modeName = 'Contain';
        modeIcon = Icons.crop_free_rounded;
        break;
    }

    setState(() {
      _aspectMode = newMode;
    });

    // Show elegant HUD feedback
    _aspectRatioHud.value = AspectRatioHudState(
      aspectRatio: modeName,
      icon: modeIcon,
    );

    // Auto-hide the HUD after 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _aspectRatioHud.value = null;
      }
    });

    _scheduleAutoHide();
    _saveResume();
  }

  void _changeSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final idx = speeds.indexOf(_playbackSpeed);
    final next = speeds[(idx + 1) % speeds.length];
    _player.setRate(next);
    setState(() => _playbackSpeed = next);
    _scheduleAutoHide();
    _saveResume();
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
    _scheduleAutoHide();
  }

  BoxFit _currentFit() => AspectModeUtils.getBoxFitForMode(_aspectMode);

  // Build subtitle view configuration from settings
  mkv.SubtitleViewConfiguration _buildSubtitleViewConfig() {
    final settings = _subtitleSettings;
    if (settings == null) {
      return const mkv.SubtitleViewConfiguration();
    }

    return mkv.SubtitleViewConfiguration(
      style: settings.buildTextStyle(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
    );
  }

  // Build video with custom aspect ratio
  Widget _buildCustomAspectRatioVideo() {
    return AspectRatioVideo(
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

  Widget _buildChannelBadge(String badgeText) => ChannelBadge(badgeText: badgeText);

  Widget _buildTitleBadge(String title) => TitleBadge(title: title);

  // Get the custom aspect ratio for specific modes
  double? _getCustomAspectRatio() =>
      AspectModeUtils.getAspectRatioValue(_aspectMode);

  Future<void> _showPlaylistSheet(BuildContext context) async {
    await PlaylistSheet.show(
      context,
      playlist: widget.playlist ?? const [],
      currentIndex: _currentIndex,
      seriesPlaylist: _seriesPlaylist,
      playlistItemData: _constructPlaylistItemData(),
      viewMode: widget.viewMode,
      onSelect: (index, {bool allowResume = false}) async {
        _setManualSelectionMode(allowResume: allowResume);
        await _loadPlaylistIndex(index, autoplay: true);
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final isReady = _isReady;
    final duration = _duration;
    final pos = _position;
    final String? channelBadgeText = _channelBadgeText;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        left: false,
        top: false,
        right: false,
        bottom: false,
        child: Focus(
          autofocus: true,
          onKey: (node, event) {
            if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;

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

            // A -> Aspect ratio
            if (key == LogicalKeyboardKey.keyA) {
              _cycleAspectMode();
              return KeyEventResult.handled;
            }

            // G -> Channel guide
            if (key == LogicalKeyboardKey.keyG) {
              if (_channelEntries.isNotEmpty && widget.requestChannelById != null) {
                _showChannelGuideOverlay();
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
              if (_channelEntries.isNotEmpty && widget.requestChannelById != null) {
                _showChannelGuideOverlay();
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
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.gameButtonA) {
              if (_controlsVisible.value) {
                _togglePlay();
              } else {
                _toggleControls();
              }
              return KeyEventResult.handled;
            }

            // DPAD left/right seek 10s
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.mediaRewind) {
              final candidate = _position - VideoPlayerTimingConstants.seekDelta;
              final newPos = candidate < Duration.zero
                  ? Duration.zero
                  : (candidate > _duration ? _duration : candidate);
              _player.seek(newPos);
              // Don't show controls or any overlay for keyboard seeking
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowRight ||
                key == LogicalKeyboardKey.mediaFastForward) {
              final candidate = _position + VideoPlayerTimingConstants.seekDelta;
              final newPos = candidate < Duration.zero
                  ? Duration.zero
                  : (candidate > _duration ? _duration : candidate);
              _player.seek(newPos);
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
              if (_hasNextEpisode() || widget.requestMagicNext != null) {
                _goToNextEpisode();
                return KeyEventResult.handled;
              }
            }

            // Escape key to quit the player
            if (key == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }

            // Next/Previous episode navigation
            if (key == LogicalKeyboardKey.mediaSkipForward) {
              if (_hasNextEpisode() || widget.requestMagicNext != null) {
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
              if (widget.requestNextChannel != null) {
                _goToNextChannel();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video texture (media_kit renderer)
              if (isReady && !_isTransitioning)
                _getCustomAspectRatio() != null
                    ? _buildCustomAspectRatioVideo()
                    : mkv.Video(
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
              // Transition overlay above video
              if (_rainbowActive) _buildTransitionOverlay(),
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
              // Full-screen gesture layer (placed below controls)
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
                  )) {
                    _toggleControls();
                  }
                },
                onDoubleTapDown: _handleDoubleTap,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),
              // Controls overlay (shown only when ready)
              if (isReady)
                ValueListenableBuilder<bool>(
                  valueListenable: _controlsVisible,
                  builder: (context, visible, _) {
                    return AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !visible,
                        child: Controls(
                          title: widget.showVideoTitle && !widget.showChannelName
                              ? _getCurrentEpisodeTitle()
                              : '',
                          subtitle: widget.showVideoTitle && !widget.showChannelName
                              ? _getCurrentEpisodeSubtitle()
                              : null,
                          enhancedMetadata: _getEnhancedMetadata(),
                          duration: duration,
                          position: pos,
                          isPlaying: _isPlaying,
                          isReady: isReady,
                          onPlayPause: _togglePlay,
                          onBack: () => Navigator.of(context).pop(),
                          onAspect: _cycleAspectMode,
                          onSpeed: _changeSpeed,
                          speed: _playbackSpeed,
                          aspectMode: _aspectMode,
                          isLandscape: _landscapeLocked,
                          onRotate: _toggleOrientation,
                          hasPlaylist:
                              widget.playlist != null &&
                              widget.playlist!.isNotEmpty,
                          onShowPlaylist: () => _showPlaylistSheet(context),
                          onShowTracks: () => _showTracksSheet(context),
                          onSeekBarChangedStart: () {
                            _isSeekingWithSlider = true;
                          },
                          onSeekBarChanged: (v) {
                            final newPos = duration * v;
                            _player.seek(newPos);
                          },
                          onSeekBarChangeEnd: () {
                            _isSeekingWithSlider = false;
                            _scheduleAutoHide();
                          },
                          onNext:
                              (_hasNextEpisode() ||
                                  widget.requestMagicNext != null)
                              ? _goToNextEpisode
                              : null,
                          onNextChannel:
                              widget.requestNextChannel != null
                                  ? _goToNextChannel
                                  : null,
                          onPrevious: _hasPreviousEpisode()
                              ? _goToPreviousEpisode
                              : null,
                          hasNext:
                              _hasNextEpisode() ||
                              widget.requestMagicNext != null,
                          hasNextChannel: widget.requestNextChannel != null,
                          hasGuide: _channelEntries.isNotEmpty && widget.requestChannelById != null,
                          onShowGuide: _channelEntries.isNotEmpty && widget.requestChannelById != null
                              ? _showChannelGuideOverlay
                              : null,
                          hasPrevious: _hasPreviousEpisode(),
                          hideSeekbar: widget.hideSeekbar,
                          hideOptions: widget.hideOptions,
                          hideBackButton: widget.hideBackButton,
                          onRandom: _playRandom,
                        ),
                      ),
                    );
                  },
                ),
              // Title Badge with Glassy Blur Effect (top-left, Debrify TV only)
              // Placed after controls to appear on top
              if (widget.showVideoTitle && widget.showChannelName)
                Positioned(
                  top: 20,
                  left: 20,
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedOpacity(
                      opacity: _showTitleBadge ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      child: _buildTitleBadge(_getCurrentEpisodeTitle()),
                    ),
                  ),
                ),
              // Channel Badge with Glassy Blur Effect (top-right)
              // Placed after controls to appear on top
              if (widget.showChannelName &&
                  channelBadgeText != null &&
                  channelBadgeText.isNotEmpty)
                Positioned(
                  top: 20,
                  right: 20,
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedOpacity(
                      opacity: _showChannelBadge ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      child: _buildChannelBadge(channelBadgeText),
                    ),
                  ),
                ),
              // PikPak retry overlay - non-blocking, positioned at bottom right
              if (_isPikPakRetrying && _pikPakRetryMessage != null)
                PikPakRetryOverlay(message: _pikPakRetryMessage!),
              // Channel guide overlay
              if (_showChannelGuide && _channelEntries.isNotEmpty)
                Positioned.fill(
                  child: ChannelGuide(
                    channels: _channelEntries,
                    currentChannelId: _currentChannelId,
                    currentChannelNumber: _currentChannelNumber,
                    onChannelSelected: _goToChannelById,
                    onClose: _hideChannelGuideOverlay,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTracksSheet(BuildContext context) async {
    // Dynamically parse season/episode from current video's filename
    final currentTitle = widget.playlist != null && _currentIndex >= 0 && _currentIndex < widget.playlist!.length
        ? widget.playlist![_currentIndex].title
        : widget.title;
    final seriesInfo = SeriesParser.parseFilename(currentTitle);
    final season = seriesInfo.season ?? widget.contentSeason;
    final episode = seriesInfo.episode ?? widget.contentEpisode;

    // Use discovered IMDB ID from series playlist (via TVMaze) if available,
    // fall back to widget's contentImdbId (from Stremio catalog)
    final effectiveImdbId = _seriesPlaylist?.imdbId ?? widget.contentImdbId;

    // Use series playlist to determine content type if not provided
    final effectiveContentType = widget.contentType ??
        (_seriesPlaylist?.isSeries == true ? 'series' : null);

    debugPrint('VideoPlayer: Opening TracksSheet with contentImdbId=$effectiveImdbId, '
        'contentType=$effectiveContentType, '
        'season=$season, episode=$episode (parsed from: $currentTitle)');
    await TracksSheet.show(
      context,
      _player,
      onTrackChanged: (audioId, subtitleId) async {
        await _persistTrackChoice(audioId, subtitleId);
      },
      onSubtitleStyleChanged: _onSubtitleStyleChanged,
      contentImdbId: effectiveImdbId,
      contentType: effectiveContentType,
      contentSeason: season,
      contentEpisode: episode,
    );
  }

  /// Restore audio and subtitle track preferences
  Future<void> _restoreTrackPreferences() async {
    try {
      final seriesPlaylist = _seriesPlaylist;
      Map<String, dynamic>? trackPreferences;

      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content, get preferences for the entire series
        trackPreferences = await StorageService.getSeriesTrackPreferences(
          seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
        );
      } else {
        // For non-series content, get preferences for this specific video
        final videoTitle = widget.title.isNotEmpty
            ? widget.title
            : 'Unknown Video';
        trackPreferences = await StorageService.getVideoTrackPreferences(
          videoTitle: videoTitle,
        );
      }

      if (trackPreferences != null) {
        final audioTrackId = trackPreferences['audioTrackId'] as String?;
        final subtitleTrackId = trackPreferences['subtitleTrackId'] as String?;

        // Apply audio track preference
        if (audioTrackId != null &&
            audioTrackId.isNotEmpty &&
            audioTrackId != 'auto') {
          final tracks = _player.state.tracks;
          final audioTrack = tracks.audio.firstWhere(
            (track) => track.id == audioTrackId,
            orElse: () => tracks.audio.first,
          );
          await _player.setAudioTrack(audioTrack);
        }

        // Apply subtitle track preference
        if (subtitleTrackId != null && subtitleTrackId.isNotEmpty) {
          final tracks = _player.state.tracks;
          final subtitleTrack = tracks.subtitle.firstWhere(
            (track) => track.id == subtitleTrackId,
            orElse: () => mk.SubtitleTrack.no(),
          );
          await _player.setSubtitleTrack(subtitleTrack);
        }
      }
    } catch (e) {}
  }

  Future<void> _persistTrackChoice(String audio, String subtitle) async {
    try {
      final seriesPlaylist = _seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content, save preferences for the entire series
        await StorageService.saveSeriesTrackPreferences(
          seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
          audioTrackId: audio,
          subtitleTrackId: subtitle,
        );
      } else {
        // For non-series content, save preferences for this specific video
        final videoTitle = widget.title.isNotEmpty
            ? widget.title
            : 'Unknown Video';
        await StorageService.saveVideoTrackPreferences(
          videoTitle: videoTitle,
          audioTrackId: audio,
          subtitleTrackId: subtitle,
        );
      }
    } catch (e) {}
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
