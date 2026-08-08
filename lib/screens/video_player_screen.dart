import 'dart:async';
import '../utils/media_kit_init.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/app_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

// Removed volume_controller; using media_kit player volume instead
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/storage_service.dart';
import '../services/skip_segment_service.dart';
import '../services/analytics_service.dart';
import '../services/pip_service.dart';
import '../services/audio_effect_session_service.dart';
import '../services/android_native_downloader.dart';
import '../services/desktop_recording_service.dart';
import '../services/live_recording_service.dart';
import '../widgets/recording_limit_dialogs.dart';
import '../services/debrid_service.dart';
import '../services/premiumize_service.dart';
import '../services/alldebrid_service.dart';
import '../utils/platform_util.dart';
import '../utils/time_formatters.dart';
import '../utils/series_parser.dart';
import '../utils/movie_parser.dart';
import '../utils/iptv_player_paging.dart';
import '../services/episode_info_service.dart';
import '../services/movie_metadata_service.dart';
import '../models/iptv_playlist.dart';
import '../services/stremio_iptv_service.dart';
import '../services/iptv_epg_service.dart';
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/next_episode_service.dart';

import '../widgets/series_browser.dart';
import '../widgets/tv_text_field.dart';
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
import 'video_player/widgets/tv_controls.dart';
import 'video_player/widgets/tv_tappable.dart';
import 'video_player/widgets/channel_badge.dart';
import 'video_player/widgets/title_badge.dart';
import 'video_player/widgets/aspect_ratio_video.dart';
import 'video_player/widgets/transition_overlay.dart';
import 'video_player/widgets/pikpak_retry_overlay.dart';
import 'video_player/widgets/buffering_indicator.dart';
import 'video_player/widgets/tracks_sheet.dart';
import 'video_player/widgets/playlist_sheet.dart';
import 'video_player/widgets/channel_guide.dart';
import 'video_player/widgets/iptv_channel_sheet.dart';
import 'video_player/widgets/iptv_zap_banner.dart';
import 'video_player/widgets/player_guide_style.dart';
import '../widgets/iptv/styles/iptv_style.dart';
import 'video_player/widgets/source_sheet.dart';
import 'video_player/widgets/stremio_tv_guide_sheet.dart';
import 'video_player/models/channel_entry.dart';
import 'video_player/services/subtitle_settings_service.dart';
import 'video_player/widgets/subtitle_line_picker_overlay.dart';
import 'video_player/widgets/skip_segment_button.dart';
import 'video_player/widgets/sleep_timer_sheet.dart';
import '../models/stremio_subtitle.dart';
import '../models/stremio_addon.dart';
import '../models/torrent.dart';
import '../services/series_source_fetcher.dart';
import '../services/stremio_service.dart';
import '../services/stremio_subtitle_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/simkl/simkl_service.dart';
import 'package:http/http.dart' as http;
import '../utils/tv_keys.dart';

// Re-export PlaylistEntry for backward compatibility
export 'video_player/models/playlist_entry.dart';
export 'video_player/models/channel_entry.dart';

class _SeasonEpisodeSelection {
  final int season;
  final int episode;

  const _SeasonEpisodeSelection({required this.season, required this.episode});
}

/// One page of a live IPTV category, as the browse provider returns it.
///
/// [offset] is the page's absolute position inside [category] and [total] is
/// how many channels that category holds — the pair that tells the end of a
/// loaded window apart from the end of the category itself.
class _IptvZapPage {
  final List<IptvChannel> channels;
  final int offset;
  final int total;
  final String? sourceId;
  final String? category;
  final List<String> categories;

  const _IptvZapPage({
    required this.channels,
    required this.offset,
    required this.total,
    required this.sourceId,
    required this.category,
    required this.categories,
  });
}

/// Monotonic ownership gate for asynchronous IPTV replay lookups.
///
/// Starting or cancelling a request makes every older ticket stale, preventing
/// a slow catch-up probe from taking playback back after a newer user action.
class IptvCatchupRequestGate {
  int _generation = 0;
  int? _activeTicket;

  int begin() {
    final ticket = ++_generation;
    _activeTicket = ticket;
    return ticket;
  }

  bool isCurrent(int ticket) =>
      _activeTicket == ticket && _generation == ticket;

  bool complete(int ticket) {
    if (!isCurrent(ticket)) return false;
    _activeTicket = null;
    return true;
  }

  bool cancel() {
    if (_activeTicket == null) return false;
    _generation++;
    _activeTicket = null;
    return true;
  }
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

  /// Subtitle tracks known at launch (e.g. YouTube closed captions), surfaced
  /// in the subtitle menu as a pre-loaded provider group. Null for sources
  /// whose subtitles are fetched lazily from Stremio addons by IMDb id.
  final List<StremioSubtitle>? initialSubtitles;

  const VideoPlayerScreen({
    Key? key,
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
    this.initialSubtitles,
  }) : assert(randomStartMaxPercent >= 0),
       super(key: key);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with TickerProviderStateMixin {
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
  final math.Random _random = math.Random();
  SeriesPlaylist? _cachedSeriesPlaylist;
  List<PlaylistEntry>? _activePlaylist;
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

  String? get _channelBadgeText {
    final String? nameSource = (_currentChannelName ?? widget.channelName)
        ?.trim();
    final int? numberSource = _currentChannelNumber;

    final bool hasName = nameSource != null && nameSource.isNotEmpty;
    if (!hasName && numberSource == null) {
      return null;
    }

    String formattedNumber = '';
    if (numberSource != null) {
      final int safeNumber = numberSource < 0 ? 0 : numberSource;
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

  // NOTE: do NOT drive mpv's `sub-visibility` here. media_kit renders
  // subtitles as a Flutter widget and keeps mpv's own renderer switched off;
  // turning it back on draws every subtitle twice. Lifting subtitles clear of
  // the bar belongs in the subtitle view's padding instead.
  bool _isSeekingWithSlider = false;
  Duration? _lastSliderSeekPos;

  // Channel badge auto-hide
  bool _showChannelBadge = true;
  Timer? _channelBadgeTimer;

  // Title badge auto-hide
  bool _showTitleBadge = true;
  Timer? _titleBadgeTimer;

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
  Timer? _iptvZapHideTimer;
  Timer? _iptvZapTicker;
  int _iptvZapEpgTicket = 0;

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
  List<IptvChannel>? _iptvChannelsOverride;
  IptvGuideContext? _iptvGuideContextOverride;
  final IptvCatchupRequestGate _iptvCatchupRequests = IptvCatchupRequestGate();

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

  /// Supersedes stale engine-state refreshes (zap during a query round-trip).
  int _engineRefreshTicket = 0;

  /// Tap on mpv's log stream while a TEE recording is armed. stream-record
  /// failing INSIDE mpv (its own fopen refused, demuxer that can't dump) is
  /// completely invisible otherwise — the property set succeeds, Dart sees no
  /// error, and no file ever appears. Only errors surface by default (the
  /// player config requests error-level logs), which is exactly the band
  /// stream-record failures log in.
  StreamSubscription<mk.PlayerLog>? _recordLogSub;

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

  /// Record is offered only for live IPTV on a libmpv backend.
  bool get _canRecord => _recordingSupported && _iptvZapBannerOwnsIdentity;

  /// Bumped whenever the guide reports a browse the user drove (a category
  /// pick, a search, a source change). An in-flight re-anchor that predates
  /// the change must not land: it would reset the ring and the persisted
  /// category, silently undoing what the user just asked for.
  int _iptvGuideContextGeneration = 0;

  void _persistIptvGuideContext(IptvGuideContext context) {
    if (!mounted) return;
    _iptvGuideContextGeneration++;
    setState(() => _iptvGuideContextOverride = context);
  }

  /// Make the guide's selected category follow the playing channel.
  ///
  /// The native player re-anchors its browsing context to the playing
  /// channel's group on every tune and every pick. Here the category only
  /// ever moved when the user chose one, so after zapping — or after picking
  /// a channel from a different category — reopening the guide showed a
  /// category that no longer contained what was on screen.
  void _anchorIptvGuideCategory(IptvChannel channel, {Object? categories}) {
    if (!mounted || !channel.isLive) return;
    final group = channel.group?.trim();
    _applyIptvGuideCategory(
      (group == null || group.isEmpty) ? null : group,
      categories is List ? categories.whereType<String>().toList() : null,
    );
  }

  /// Point the guide at [category] verbatim, without inferring it from a
  /// channel. A zap that crossed a category boundary knows the category it
  /// landed in from the response — including the null the "All"/uncategorized
  /// wrap lands on, which no single channel's group can express.
  ///
  /// Deliberately does NOT bump [_iptvGuideContextGeneration]: that counter
  /// means "the user browsed", and an in-flight zap prefetch reading it must
  /// not be invalidated by the zap's own bookkeeping.
  void _applyIptvGuideCategory(String? category, List<String>? categories) {
    if (!mounted) return;
    final current = _iptvGuideContextOverride;
    final nextCategories =
        categories ??
        (current?.categories ?? widget.iptvCategories ?? const <String>[]);
    if (current != null &&
        current.selectedCategory == category &&
        listEquals(nextCategories, current.categories)) {
      return;
    }
    setState(() {
      _iptvGuideContextOverride = IptvGuideContext(
        categories: nextCategories,
        sourceId: current?.sourceId ?? widget.iptvSourceId,
        // Same fallback the sheet applies to a nameless source.
        sourceName: current?.sourceName ?? widget.iptvSourceName ?? 'IPTV',
        selectedCategory: category,
        contentType: current?.contentType ?? widget.iptvContentType ?? 'live',
      );
    });
  }

  void _cancelPendingIptvCatchup({bool hideFeedback = true}) {
    if (!_iptvCatchupRequests.cancel()) return;
    if (hideFeedback && mounted) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
  }

  int _beginIptvCatchupRequest() {
    _cancelPendingIptvCatchup();
    return _iptvCatchupRequests.begin();
  }

  bool _isCurrentIptvCatchupRequest(int ticket) =>
      mounted && _iptvCatchupRequests.isCurrent(ticket);

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

  // media_kit state
  bool _isReady = false;
  bool _isPlaying = false;
  // True while the activity is shrunk into a Picture-in-Picture window; the
  // build collapses all interactive/decorative chrome so only the video shows.
  bool _isPipActive = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isTransitioning = false; // Show black screen during transitions


  /// One-shot guard set the moment we pop to hand the next episode back to the
  /// host for Quick Play. End-of-video auto-advance (_onPlaybackEnded) and a
  /// manual Next press both funnel into _handleSeriesNextEpisode, which awaits a
  /// network lookup and then pops — without this, the two can race and pop
  /// twice, ejecting the user off the host screen instead of playing the next.
  bool _seriesNextDispatched = false;
  bool _currentEpisodeMarkedAsFinished = false;
  // We render using a large logical surface; fit is controlled by BoxFit
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _paramsSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _iptvErrorSub;

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

  // Aspect / speed
  AspectMode _aspectMode = AspectMode.contain;
  double _playbackSpeed = 1.0;

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
  double? _speedBeforeHold;
  final ValueNotifier<bool> _speedHoldHud = ValueNotifier<bool>(false);

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

  // Trakt scrobble state
  bool _traktScrobbleEnabled = false;
  // The launched item's widget.traktProgressPercent is a first-load-only
  // signal; once spent it must not apply to a later switched-to episode.
  bool _launchTraktPercentSpent = false;
  // Per-episode Trakt cross-device progress ("season_episode" → 0-100), loaded
  // once per series; drives resume for episodes switched to in-session.
  Map<String, double>? _traktEpisodeProgress;
  String? _traktLastScrobbleAction;
  Timer? _traktHeartbeatTimer;
  // Simkl scrobble state — a fully parallel mirror of the Trakt fields above
  // (independent dedup guard + heartbeat; the two trackers never share state).
  bool _simklScrobbleEnabled = false;
  bool _launchSimklPercentSpent = false;
  // Per-episode Simkl cross-device snapshot ("season_episode" → 0-100),
  // refreshed by the launcher and used when switching episodes in-session.
  Map<String, double>? _simklEpisodeProgress;
  String? _simklLastScrobbleAction;
  Timer? _simklHeartbeatTimer;
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
    AnalyticsService.screenView('video_player');
    _startAnalyticsHeartbeat();
    _activePlaylist = widget.playlist;
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
        unawaited(_stopRecording(userInitiated: false));
        _pauseForBackground();
      },
      onResume: _resumeFromBackground,
    );

    // Observe, don't sample: see [_desktopRecordingRevisionListener].
    if (DesktopRecordingService.instance.isSupported) {
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

    // Picture-in-Picture (Android phone): once native confirms capability,
    // become the active PiP owner and listen so we can collapse chrome inside
    // the tiny window. Auto-enter is armed later, when the video is actually
    // ready (see the player `ready` callback), so pressing Home never shrinks
    // a black/loading frame. Skipped when options are hidden — that context
    // deliberately suppresses the PiP button and tap controls.
    if (Platform.isAndroid && !widget.hideOptions) {
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

    if (widget.channelName != null && widget.channelName!.trim().isNotEmpty) {
      _currentChannelName = widget.channelName;
    }
    _currentChannelNumber = widget.channelNumber;
    _currentIptvIndex = widget.iptvStartIndex ?? 0;
    _currentSourceIndex = widget.stremioCurrentSourceIndex ?? 0;
    _initIptvStremioSources();
    _currentStremioTvChannelId = _findInitialStremioTvChannelId();
    _parseChannelDirectory();
    // The sync offset is per-subtitle and session-scoped, but it lives in a
    // process-wide singleton — clear it at the start of every player session so
    // a previous video's offset can't leak in (mirrors the TV side's onCreate).
    SubtitleSettingsService.instance.resetSyncOffset();
    _loadSubtitleSettings();
    unawaited(_loadSkipSegmentSettings());
    MediaKitInit.ensureInitialized();
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

    // Check if Trakt scrobbling should be enabled for this playback
    _initTraktScrobble();
    _initSimklScrobble();
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
  }

  SkipSegment? get _activeSkipSegment {
    final request = _currentSkipSegmentRequest();
    if (request == null || request.key != _loadedSkipSegmentsKey) return null;
    return _skipSegments.segmentAt(_position);
  }

  void _skipActiveSegment() {
    final segment = _activeSkipSegment;
    if (segment == null || !_playerCreated) return;
    final target = _duration > Duration.zero && segment.end > _duration
        ? _duration
        : segment.end;
    _position = target;
    unawaited(_player.seek(target));
    _traktScrobbleSeek(target);
    _simklScrobbleSeek(target);
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  Future<void> _initTraktScrobble() async {
    if (!widget.traktScrobble) return;
    if (widget.contentImdbId == null) return;
    if (widget.contentType != 'movie' && widget.contentType != 'series') return;
    _traktScrobbleEnabled = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    // If player started playing before auth resolved, scrobble start now
    if (_traktScrobbleEnabled && _isPlaying && _duration > Duration.zero) {
      _traktScrobble('start');
      if (_traktLastScrobbleAction == 'start') {
        _startTraktHeartbeat();
      }
    }
  }

  double _traktProgress() {
    if (_duration.inMilliseconds <= 0) return 0.0;
    return (_position.inMilliseconds / _duration.inMilliseconds * 100).clamp(
      0.0,
      100.0,
    );
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

  void _traktScrobble(String action) {
    if (!_traktScrobbleEnabled || widget.contentImdbId == null) return;
    final imdbId = widget.contentImdbId!;
    final progress = _traktProgress();
    final se = _traktSeasonEpisode();
    // Trakt rejects start/pause when progress > 80% — send stop instead
    if ((action == 'start' || action == 'pause') && progress > 80) {
      action = 'stop';
    }
    if (_traktLastScrobbleAction == action) return;
    _traktLastScrobbleAction = action;
    switch (action) {
      case 'start':
        TraktService.instance.scrobbleStart(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
      case 'pause':
        TraktService.instance.scrobblePause(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
      case 'stop':
        TraktService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
    }
  }

  /// Start periodic heartbeat to checkpoint progress to Trakt every 2 minutes.
  void _startTraktHeartbeat() {
    _traktHeartbeatTimer?.cancel();
    _traktHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_traktScrobbleEnabled || widget.contentImdbId == null) return;
      if (!_isPlaying || _duration.inMilliseconds <= 0) return;
      final imdbId = widget.contentImdbId!;
      final progress = _traktProgress();
      final se = _traktSeasonEpisode();
      // Trakt rejects start/pause above 80% — send stop and end heartbeat
      if (progress > 80) {
        _traktLastScrobbleAction = 'stop';
        TraktService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        debugPrint(
          'Trakt: Heartbeat stop at ${progress.toStringAsFixed(1)}% (>80%)',
        );
        _stopTraktHeartbeat();
        return;
      }
      // Force-send start (bypass dedup) to keep session alive and checkpoint progress
      _traktLastScrobbleAction = 'start';
      TraktService.instance.scrobbleStart(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      debugPrint(
        'Trakt: Heartbeat scrobble at ${progress.toStringAsFixed(1)}%',
      );
    });
  }

  void _stopTraktHeartbeat() {
    _traktHeartbeatTimer?.cancel();
    _traktHeartbeatTimer = null;
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

  /// Send updated progress to Trakt after a user seek (bypasses dedup guard).
  void _traktScrobbleSeek(Duration seekTarget) {
    if (!_traktScrobbleEnabled || widget.contentImdbId == null) return;
    if (!_isPlaying || _duration.inMilliseconds <= 0) return;
    final imdbId = widget.contentImdbId!;
    final progress =
        (seekTarget.inMilliseconds / _duration.inMilliseconds * 100).clamp(
          0.0,
          100.0,
        );
    final se = _traktSeasonEpisode();
    // Trakt rejects start above 80% — send stop instead
    if (progress > 80) {
      _traktLastScrobbleAction = 'stop';
      TraktService.instance.scrobbleStop(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      _stopTraktHeartbeat();
    } else {
      _traktLastScrobbleAction = 'start';
      TraktService.instance.scrobbleStart(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      _startTraktHeartbeat();
    }
  }

  // ── Simkl scrobble machine — fully parallel mirror of the Trakt one above.
  // Zero shared state: its own enable flag, dedup guard and heartbeat, driven
  // by the same (tracker-agnostic) _traktProgress()/_traktSeasonEpisode()
  // helpers. See the Simkl integration plan.

  Future<void> _initSimklScrobble() async {
    if (!widget.simklScrobble) return;
    if (widget.contentImdbId == null) return;
    if (widget.contentType != 'movie' && widget.contentType != 'series') return;
    _simklScrobbleEnabled = await SimklService.instance.isAuthenticated();
    if (!mounted) return;
    // Pause-centric model: do NOT POST Simkl's /scrobble/start. Unlike Trakt,
    // it persists NO resumable position AND deletes the existing /sync/playback
    // entry (verified: returns id:0, wipes the session). We leave the resume
    // point untouched and let the pause-based heartbeat keep it current.
    // BUT still stamp the marker 'start' (no POST) — the local action marker
    // must read "playing" so a later user-pause / exit-stop isn't dedup-
    // suppressed at _simklScrobble's guard. Mirrors the Trakt block and the TV
    // launcher's self-healing marker. (Field assignment, NOT _simklScrobble
    // ('start'), which now routes to a pause POST.)
    if (_simklScrobbleEnabled && _isPlaying && _duration > Duration.zero) {
      _simklLastScrobbleAction = 'start';
      _startSimklHeartbeat();
    }
  }

  /// A series whose season/episode can't be resolved must NOT be scrobbled to
  /// Simkl: [SimklService._scrobble] would send the show id in a movie-shaped
  /// body, recording a bogus movie on the account. A movie legitimately has
  /// (null, null), so this only blocks the series case. (Trakt has the same
  /// latent gap; this guard is Simkl-only per the no-touch-Trakt convention.)
  bool _simklSeriesSEUnresolved(({int? season, int? episode}) se) =>
      widget.contentType == 'series' &&
      (se.season == null || se.episode == null);

  void _simklScrobble(String action) {
    if (!_simklScrobbleEnabled || widget.contentImdbId == null) return;
    final imdbId = widget.contentImdbId!;
    final progress = _traktProgress();
    final se = _traktSeasonEpisode();
    if (_simklSeriesSEUnresolved(se)) return;
    // Simkl marks watched server-side at ≥80% on stop — mirror Trakt's rule
    // and finalize instead of keeping a start/pause session alive.
    if ((action == 'start' || action == 'pause') && progress > 80) {
      action = 'stop';
    }
    if (_simklLastScrobbleAction == action) return;
    _simklLastScrobbleAction = action;
    switch (action) {
      // 'start' shares the pause path (no caller passes it in the pause-centric
      // model; play stamps the marker directly). Kept defensive and merged so
      // the two can't silently diverge: NEVER send Simkl's /scrobble/start — it
      // persists nothing and wipes the resume point, so a 'start' intent maps to
      // a pause checkpoint.
      case 'start':
      case 'pause':
        SimklService.instance.scrobblePause(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
      case 'stop':
        SimklService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
    }
  }

  /// Periodic Simkl checkpoint — comfortably above Simkl's 20-second per-user
  /// scrobble rate lock. Uses /scrobble/pause (NOT /scrobble/start): on Simkl,
  /// start returns id:0 and persists NO resumable position — only pause/stop
  /// create the /sync/playback entry that Continue Watching + episode-card
  /// resume read. So the heartbeat pauses to keep a resume point current every
  /// interval; a hard kill (SIGINT/power-off, no graceful stop) then still
  /// resumes from the last checkpoint instead of the episode start.
  void _startSimklHeartbeat() {
    _simklHeartbeatTimer?.cancel();
    _simklHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!_simklScrobbleEnabled || widget.contentImdbId == null) return;
      if (!_isPlaying || _duration.inMilliseconds <= 0) return;
      final imdbId = widget.contentImdbId!;
      final progress = _traktProgress();
      final se = _traktSeasonEpisode();
      if (_simklSeriesSEUnresolved(se)) return;
      if (progress > 80) {
        _simklLastScrobbleAction = 'stop';
        SimklService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        debugPrint(
          'Simkl: Heartbeat stop at ${progress.toStringAsFixed(1)}% (>80%)',
        );
        _stopSimklHeartbeat();
        return;
      }
      // Force-send pause (direct call, bypasses dedup) to checkpoint a RESUMABLE
      // position. Simkl's /scrobble/start saves nothing (id:0); only pause/stop
      // persist to /sync/playback, so this must be pause to survive a hard kill.
      // Leave the marker 'start' (live), NOT 'pause': stamping 'pause' here would
      // make the user's real pause dedup-suppress at _simklScrobble and strand
      // the true pause position at this (older) heartbeat %.
      _simklLastScrobbleAction = 'start';
      SimklService.instance.scrobblePause(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      debugPrint(
        'Simkl: Heartbeat pause checkpoint at ${progress.toStringAsFixed(1)}%',
      );
    });
  }

  void _stopSimklHeartbeat() {
    _simklHeartbeatTimer?.cancel();
    _simklHeartbeatTimer = null;
  }

  /// Simkl reaction to a user seek. Deliberately TRANSITION-ONLY, unlike
  /// Trakt's seek handler which re-sends start with fresh progress on every
  /// seek: Simkl's docs say not to call /scrobble/start on seek events (plus
  /// a 20s rate lock), so this only acts when the seek changes the effective
  /// action — crossing the 80% boundary (→ stop), or seeking back below it
  /// after a stop (→ a new start). The 2-minute heartbeat carries fresh
  /// progress either way.
  void _simklScrobbleSeek(Duration seekTarget) {
    if (!_simklScrobbleEnabled || widget.contentImdbId == null) return;
    if (!_isPlaying || _duration.inMilliseconds <= 0) return;
    final imdbId = widget.contentImdbId!;
    final progress =
        (seekTarget.inMilliseconds / _duration.inMilliseconds * 100).clamp(
          0.0,
          100.0,
        );
    final se = _traktSeasonEpisode();
    if (_simklSeriesSEUnresolved(se)) return;
    if (progress > 80 && _simklLastScrobbleAction != 'stop') {
      _simklLastScrobbleAction = 'stop';
      SimklService.instance.scrobbleStop(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      _stopSimklHeartbeat();
    } else if (progress <= 80 && _simklLastScrobbleAction == 'stop') {
      // Seeked back under 80% after a finalize — re-establish a RESUMABLE
      // session via pause (start would wipe it and persist nothing) and resume
      // the heartbeat.
      _simklLastScrobbleAction = 'pause';
      SimklService.instance.scrobblePause(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      _startSimklHeartbeat();
    }
  }

  /// The current episode's cross-device Trakt progress percent (0-100), or null.
  /// Loaded once per series from the dedicated store (kept apart from the
  /// ms-based resume state) and looked up by the current episode's season/episode.
  Future<double?> _currentEpisodeTraktPercent() async {
    final imdbId = widget.contentImdbId;
    if (imdbId == null || imdbId.isEmpty) return null;

    // Await BEFORE reading _currentIndex/season/episode below, so that if the
    // user advances to a different episode while this is in flight, we key
    // off the episode that's actually current when the fetch resolves.
    _traktEpisodeProgress ??= await StorageService.getEpisodeTraktProgress(
      imdbId: imdbId,
    );

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

    return _traktEpisodeProgress!['${season}_$episode'];
  }

  /// Current episode's Simkl snapshot percent. This mirrors the Trakt lookup
  /// above but remains independently stored so remote unwatch changes never
  /// mutate local playback history.
  Future<double?> _currentEpisodeSimklPercent() async {
    final imdbId = widget.contentImdbId;
    if (imdbId == null || imdbId.isEmpty) return null;

    // Await before resolving the episode identity for the same race-safety as
    // [_currentEpisodeTraktPercent].
    _simklEpisodeProgress ??= await StorageService.getEpisodeSimklProgress(
      imdbId: imdbId,
    );

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

    return _simklEpisodeProgress!['${season}_$episode'];
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
      if (!await StorageService.getPlayerSystemAudioEffects()) return;
      await platform.setProperty('ao', 'audiotrack,opensles');
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

  Future<void> _initializePlayer() async {
    // Load default player settings
    await _loadPlayerDefaults();

    // Determine the initial URL and index
    String initialUrl = widget.videoUrl;
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
              final resumeId = _resumeIdForEntry(entry);
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
        logLevel: mk.MPVLogLevel.error, // Suppress verbose subtitle logging
        ready: () {
          _isReady = true;
          // Now that there's a real video frame, arm PiP auto-enter (no-op
          // unless this screen is the active, supported PiP owner).
          _armPipAutoEnter();
          // The bar is mounted only once ready, and _controlsVisible starts
          // true — so on a television it appears with focus still on the
          // player root, where OK does nothing. Claim it now. Live force-hides
          // the bar just below, and that path parks focus on the root itself.
          if (PlatformUtil.isTelevision && _controlsVisible.value) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _controlsVisible.value && !_tvBarScope.hasFocus) {
                _tvPlayPauseFocus.requestFocus();
              }
            });
          }
          if (mounted) {
            setState(() {});
            // First tune on a live channel: the zap banner doubles as the
            // "here's what's on" card, and it owns the identity instead of
            // the corner badges.
            final iptvChannel = _currentIptvChannel;
            if (iptvChannel != null && iptvChannel.isLive) {
              // The dock opens visible and nothing on this path auto-hides
              // it, so it would both cover the banner and leave a live
              // channel presenting a seek bar it cannot use. The banner is
              // this tune's presentation; one tap brings the dock back.
              _hideTimer?.cancel();
              _controlsVisible.value = false;
              _prepareIptvBannerData(iptvChannel);
              _raiseIptvZapBanner();
              // Anchor the browsing context to what is playing, the way the
              // native player bootstraps it. Both halves matter: the category
              // alone would label the guide with a group the launch window
              // does not match, and the list would then shrink to it the
              // moment anything re-filtered.
              _anchorIptvGuideCategory(iptvChannel);
              // Arms the zap ladder for the launch channel. Routed through the
              // shared helper so a zap arriving before this lands re-arms it
              // instead of leaving the ladder inactive for the session.
              _ensureIptvZapPagingArmed();
            } else {
              // Show channel badge when player is ready (if enabled)
              if (widget.showChannelName && _channelBadgeText != null) {
                _showChannelBadgeWithTimer();
              }
              // Show title badge when player is ready (if enabled and in Debrify TV)
              if (widget.showVideoTitle && widget.showChannelName) {
                _showTitleBadgeWithTimer();
              }
            }
          }
        },
      ),
    );
    _playerCreated = true;
    _videoController = mkv.VideoController(_player);
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
    _recordingSupported = nativeBackend && !Platform.isAndroid;
    if (nativeBackend && Platform.isAndroid) {
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
          _engineFlagOn = on;
          if (on) unawaited(_refreshEngineRecordingState());
        }),
      );
    }

    // Must happen before the first open() — mpv reads both audio options when
    // it creates the audio output, which is on first playback.
    await _attachAudioEffectSession();

    _currentStreamUrl = initialUrl.isNotEmpty ? initialUrl : null;

    // Only open the player if we have a valid URL
    if (initialUrl.isNotEmpty) {
      // For PikPak videos from playlist or any PikPak URL, use cold storage retry logic
      final currentEntry = _activePlaylist?[_currentIndex];
      final isPikPak =
          currentEntry?.provider?.toLowerCase() == 'pikpak' ||
          currentEntry?.pikpakFileId != null;
      // For non-playlist flows (Debrify TV, Stremio TV, etc.), detect PikPak by URL
      final isPikPakUrl =
          _activePlaylist == null && initialUrl.contains('mypikpak.com');
      final isDebrifyTV = isPikPakUrl && widget.requestMagicNext != null;

      if ((isPikPak && _activePlaylist != null) || isPikPakUrl) {
        _playPikPakVideoWithRetry(initialUrl, isDebrifyTV: isDebrifyTV).then((
          _,
        ) async {
          // Wait for the video to load and duration to be available
          await _waitForVideoReady();
          // Random start takes precedence over resume, then startAtPercent
          if (widget.startFromRandom) {
            final offset = _randomStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            } else {
              await _maybeRestoreResume();
            }
          } else if (widget.startAtPercent != null) {
            final offset = _percentStartOffset(_duration);
            if (offset != null) {
              await _player.seek(offset);
            }
          } else {
            await _maybeRestoreResume();
          }
          // Restore audio and subtitle track preferences
          await _restoreTrackPreferences();
        });
      } else {
        // High-res YouTube serves video and audio as separate streams. Open
        // PAUSED, attach the external audio track, then start — so both tracks
        // are loaded before the first frame and play in sync from the start.
        // (Attaching audio mid-playback makes mpv resync, causing a few seconds
        // of A/V drift.)
        final hasExternalAudio =
            widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
        _player
            .open(
              mk.Media(initialUrl, httpHeaders: widget.httpHeaders),
              play: !hasExternalAudio,
            )
            .then((_) async {
              // Wait for the video to load and duration to be available
              await _waitForVideoReady();
              if (hasExternalAudio) {
                await _setExternalAudioTrack(widget.audioUrl!);
              }
              // Random start takes precedence over resume, then startAtPercent
              if (widget.startFromRandom) {
                final offset = _randomStartOffset(_duration);
                if (offset != null) {
                  await _player.seek(offset);
                } else {
                  await _maybeRestoreResume();
                }
              } else if (widget.startAtPercent != null) {
                final offset = _percentStartOffset(_duration);
                if (offset != null) {
                  await _player.seek(offset);
                }
              } else {
                await _maybeRestoreResume();
              }
              _scheduleAutoHide();
              // Restore audio and subtitle track preferences
              await _restoreTrackPreferences();
              // Start playback now that video + external audio are both loaded.
              if (hasExternalAudio) {
                await _player.play();
              }
            })
            .catchError((e) {
              debugPrint('VideoPlayer: YouTube open failed: $e');
            });
      }
    } else {
      // If no valid URL, try to load the first playlist entry
      if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
        _loadPlaylistIndex(_currentIndex, autoplay: false);
      }
    }
    _posSub = _player.stream.position.listen((d) {
      _position = d;
      _syncSkipSegmentsForCurrentContent();
      // throttle UI updates
      if (mounted) setState(() {});
      // Check if episode should be marked as finished (for manual seeking)
      _checkAndMarkEpisodeAsFinished();
    });
    _durSub = _player.stream.duration.listen((d) {
      _duration = d;
      // A real duration means the incoming media has opened, so the clock the
      // skip lookup reads is finally the new item's.
      if (d > Duration.zero) _skipSegmentsMediaReady = true;
      _syncSkipSegmentsForCurrentContent();
      if (mounted) setState(() {});
    });
    _playSub = _player.stream.playing.listen((p) {
      // Backgrounded via the lifecycle pause, yet something started playing:
      // an open(play: true) that was already in flight when Home was pressed
      // (a zap, an episode load) landing after the pause. Re-pause instead of
      // letting it decode invisibly — the exact drain the lifecycle pause
      // exists to stop. Early return, before any scrobble/heartbeat side
      // effects can arm off a playback that is being taken back down.
      if (p && _pausedByLifecycle && !_isPipActive) {
        unawaited(_player.pause());
        return;
      }
      final wasPlaying = _isPlaying;
      _isPlaying = p;
      _syncWakelock(p);
      _pushPipState();
      // Startup-channel memory — armed only by real playback, never by a tune.
      if (p) _noteLiveChannelPlaying();
      // Trakt scrobble on play/pause
      if (p && _duration > Duration.zero) {
        _traktScrobble('start');
        // Only start heartbeat if scrobble wasn't converted to stop (>80%)
        if (_traktLastScrobbleAction == 'start') {
          _startTraktHeartbeat();
        }
      } else if (!p &&
          wasPlaying &&
          !_isTransitioning &&
          _traktLastScrobbleAction != 'stop') {
        _traktScrobble('pause');
        _stopTraktHeartbeat();
      }
      // Simkl scrobble on play/pause — parallel to the Trakt block above, but
      // pause-centric: NO 'start' POST on play (it wipes the Simkl resume
      // point; see _initSimklScrobble). We DO stamp the marker 'start' (no POST)
      // so it reads "playing" — otherwise a leftover 'pause'/'stop' marker (from
      // the heartbeat or an episode-switch stop) would dedup-suppress this
      // episode's user-pause and exit-stop. Then run the pause-based heartbeat.
      // Gated on _simklScrobbleEnabled (the old _simklScrobble('start') call did
      // this implicitly) so a non-Simkl session doesn't leak an idle heartbeat.
      if (_simklScrobbleEnabled && p && _duration > Duration.zero) {
        _simklLastScrobbleAction = 'start';
        _startSimklHeartbeat();
      } else if (!p &&
          wasPlaying &&
          !_isTransitioning &&
          _simklLastScrobbleAction != 'stop') {
        _simklScrobble('pause');
        _stopSimklHeartbeat();
      }
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
    _bufferingSub = _player.stream.buffering.listen((isBuffering) {
      if (!_isReady || _isTransitioning) return;
      if (isBuffering) {
        _bufferingDebounceTimer?.cancel();
        _bufferingDebounceTimer = Timer(
          VideoPlayerTimingConstants.bufferingDebounceDelay,
          () {
            if (mounted &&
                _player.state.buffering &&
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

    // Plain IPTV channels had no error path at all: a refused or dead stream
    // just left a black screen with a spinner, indistinguishable from "the app
    // is broken". (The Stremio ladder reports for itself — see the probing
    // guard in the handler.)
    if (_effectiveIptvChannels != null) {
      _iptvErrorSub = _player.stream.error.listen(_onIptvStreamError);
    }

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

  // Wait for subtitle tracks to be parsed from the media file
  // media_kit initially only has 'auto' and 'no' tracks, real tracks come later
  Future<void> _waitForSubtitleTracks({required int token}) async {
    // Wait up to 5 seconds for subtitle tracks to be available
    for (int i = 0; i < 50; i++) {
      if (token != _addonSubtitleFetchToken) return;
      final tracks = _player.state.tracks.subtitle;
      // Check if we have any real tracks (not just 'auto' and 'no')
      final hasRealTracks = tracks.any(
        (t) => t.id != 'auto' && t.id != 'no' && t.id.isNotEmpty,
      );
      if (hasRealTracks) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Timeout reached - video may not have embedded subtitles
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
    // Scrobble stop to Trakt when movie finishes
    _stopTraktHeartbeat();
    _traktScrobble('stop');
    _stopSimklHeartbeat();
    _simklScrobble('stop');

    // Mark the current episode as finished if it's a series
    await _markCurrentEpisodeAsFinished();

    // "Stop at the end of this episode": suppress every advance below and let
    // the screen sleep. Playback has already finished, so there is nothing
    // left to pause.
    if (_sleepTimerMode == SleepTimerMode.endOfItem) {
      _cancelSleepTimer();
      _sleepStopLatched = true;
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
        widget.requestMagicNext != null) {
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
  String _getCurrentEpisodeTitle() {
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
            return currentEpisode.episodeInfo!.title!;
          } else if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            return 'Episode ${currentEpisode.seriesInfo.episode}';
          }
        } catch (e) {
          // Silently fail
        }
      }
    }

    // Stremio TV: use dynamic title when a channel switch has occurred
    if (_hasStremioTvGuide && _dynamicTitle.isNotEmpty) {
      return _dynamicTitle;
    }

    // Fallback to the current playlist entry title
    if (_activePlaylist != null &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      return _activePlaylist![_currentIndex].title;
    }

    // If Debrify TV (no playlist) is active, use dynamic title when available
    if ((_activePlaylist == null || _activePlaylist!.isEmpty) &&
        widget.requestMagicNext != null) {
      return _dynamicTitle.isNotEmpty ? _dynamicTitle : widget.title;
    }

    // IPTV: use current channel name
    final iptvChannels = _effectiveIptvChannels;
    if (iptvChannels != null &&
        _currentIptvIndex >= 0 &&
        _currentIptvIndex < iptvChannels.length) {
      return iptvChannels[_currentIptvIndex].numberedName;
    }

    // Final fallback
    return widget.title;
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
            final seriesName = seriesPlaylist.seriesTitle;
            return '$seriesName • Season ${currentEpisode.seriesInfo.season}, Episode ${currentEpisode.seriesInfo.episode}';
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
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playlist items available')),
      );
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
    _scheduleAutoHide();

    if (choice == 'once') {
      await _playRandomOnce(disableContinuousShuffle: true);
    } else if (choice == 'continuous') {
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
    return _findPreviousEpisodeIndex() != -1;
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

          // Clear subtitle, IMDB, and episode-finished state when switching content
          _resetSubtitleState();
          _singleFileImdbId = null;
          _singleFileImdbFetched = false;
          _currentEpisodeMarkedAsFinished = false;

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
            await _player.open(
              mk.Media(url, httpHeaders: widget.httpHeaders),
              play: true,
            );
          }
          _currentStreamUrl = url;
          // Disable auto-enabled embedded subtitles to prevent duplicates
          await _player.setSubtitleTrack(mk.SubtitleTrack.no());
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

  /// When no playlist-based next episode exists and content is a series,
  /// find the next episode via Stremio meta and pop the player with the result.
  /// The caller (TorrentSearchScreen) will receive this and trigger Quick Play.
  Future<bool> _handleSeriesNextEpisode() async {
    // Already popping to hand off the next episode — a second trigger (manual
    // Next racing end-of-video auto-advance) must not run again.
    if (_seriesNextDispatched) return true;
    if (widget.contentType != 'series' || widget.contentImdbId == null) {
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
    Navigator.of(context).pop(<String, dynamic>{
      'quickPlayNext': true,
      'imdbId': widget.contentImdbId,
      'season': nextEp.season,
      'episode': nextEp.episode,
      'title': widget.contentTitle ?? widget.title,
      'contentType': widget.contentType,
    });
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
  Future<void> _loadPlayerDefaults() async {
    // Load default aspect index
    final aspectIndex = await StorageService.getPlayerDefaultAspectIndex();
    const aspects = AspectMode.values;
    _aspectMode = aspects[aspectIndex.clamp(0, aspects.length - 1)];

    // In-player guide look. `_initializePlayer` awaits this before playback
    // setup, so every IPTV surface that can actually appear (first tune,
    // zap, guide) already has the real value.
    _playerGuideStyle = PlayerGuideStyle.fromPref(
      await StorageService.getIptvPlayerGuideStyle(),
    );
    _playerGuideTokens = PlayerGuideTokens.of(_playerGuideStyle);

    debugPrint('VideoPlayer: Loaded defaults - aspect=$_aspectMode');
  }

  /// Update subtitle style settings
  void _onSubtitleStyleChanged(SubtitleSettingsData settings) {
    final offsetChanged =
        _subtitleSettings?.syncOffsetMs != settings.syncOffsetMs;
    setState(() {
      _subtitleSettings = settings;
    });
    if (offsetChanged) {
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
    final settings = _subtitleSettings;
    final ms = settings?.syncOffsetMs ?? 0;
    final accent = settings?.syncOffsetColor ?? const Color(0xFF4CAF50);
    final label = settings?.syncOffsetLabel ?? '0';
    const minMs = SubtitleSettingsService.syncOffsetMinMs;
    const maxMs = SubtitleSettingsService.syncOffsetMaxMs;
    const step = SubtitleSettingsService.syncOffsetStepMs;

    void update(int newMs) async {
      final clamped = newMs.clamp(minMs, maxMs);
      await SubtitleSettingsService.instance.setSyncOffsetMs(clamped);
      _applySubtitleSyncOffset(clamped);
      if (mounted) {
        setState(() {
          _subtitleSettings = _subtitleSettings?.copyWith(
            syncOffsetMs: clamped,
          );
        });
      }
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 28),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'SUBTITLE SYNC',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TvTappable(
                    autofocus: true,
                    onTap: () => update(0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TvTappable(
                    onTap: _hideSyncOverlay,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TvTappable(
                    onTap: () => update(ms - step),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.remove_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: accent,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                        thumbColor: Colors.white,
                        overlayColor: accent.withValues(alpha: 0.2),
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: ms.toDouble(),
                        min: minMs.toDouble(),
                        max: maxMs.toDouble(),
                        divisions: (maxMs - minMs) ~/ step,
                        onChanged: (v) => update(v.round()),
                      ),
                    ),
                  ),
                  TvTappable(
                    onTap: () => update(ms + step),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Line picker is only available for addon subtitles',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Text(
                      '-1hr',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 9,
                      ),
                    ),
                  ),
                  Text(
                    '0',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 9,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: Text(
                      '+1hr',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show channel guide overlay
  void _showChannelGuideOverlay() {
    if (_channelEntries.isEmpty) {
      debugPrint('Player: No channels available for guide');
      return;
    }
    _hideIptvZapBanner();
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

  /// Show IPTV channel sheet overlay
  void _showIptvChannelSheetOverlay() {
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    _hideIptvZapBanner();
    setState(() {
      _showIptvChannelSheet = true;
      _controlsVisible.value = false;
    });
  }

  /// Hide IPTV channel sheet overlay
  void _hideIptvChannelSheet() {
    _cancelPendingIptvCatchup();
    setState(() {
      _showIptvChannelSheet = false;
    });
  }

  /// A full-catalog guide result is not necessarily part of the launch
  /// window. Adopt the result set before tuning so every player read uses the
  /// selected channel's real index and metadata.
  Future<void> _switchToIptvGuideChannel(
    List<IptvChannel> channels,
    int index,
  ) async {
    if (index < 0 || index >= channels.length) return;
    _cancelPendingIptvCatchup();
    final channel = channels[index];
    // Adopt the visible list first so playback starts immediately; the
    // re-anchor below then replaces it with the channel's own category.
    // A browse result is not a page of any category, so the zap window's
    // coordinates stop describing the ring until the re-anchor lands.
    _resetIptvZapPaging();
    _iptvChannelsOverride = List<IptvChannel>.from(channels);
    // Take this tune's generation from the call itself. _switchToIptvChannel
    // bumps the ticket synchronously before its first await, and it returns
    // normally when a newer tune supersedes it — so reading the ticket AFTER
    // the await would read the newer tune's value and defeat every staleness
    // check downstream.
    final switchFuture = _switchToIptvChannel(index);
    final switchTicket = _iptvSwitchTicket;
    await switchFuture;
    if (!mounted || switchTicket != _iptvSwitchTicket) return;
    unawaited(_reanchorIptvRingToCategory(channel, switchTicket: switchTicket));
  }

  /// Rebuild the channel ring around [channel] from its own category.
  ///
  /// The native guide does this on every pick (`beginIptvCategoryZapSession`):
  /// the list you navigate afterwards is the channel's category, never the
  /// list you happened to pick from. Without it, choosing a channel out of a
  /// search left the search matches standing in as the entire channel list —
  /// so the guide reopened onto a handful of unrelated channels, and the
  /// category shown alongside them belonged to the previous selection.
  ///
  /// Best effort by design: playback has already started, so a failed or
  /// unhelpful page simply leaves the adopted list in place, which is what
  /// the native fallback does too.
  Future<void> _reanchorIptvRingToCategory(
    IptvChannel channel, {
    required int switchTicket,
  }) async {
    final provider = widget.iptvBrowseProvider;
    if (provider == null || !channel.isLive) return;
    if (switchTicket != _iptvSwitchTicket) return;
    final category = channel.group?.trim();
    final contextGeneration = _iptvGuideContextGeneration;

    Map<String, dynamic>? result;
    try {
      result = await provider({
        'action': 'zapPage',
        'sourceId': _iptvGuideContextOverride?.sourceId ?? widget.iptvSourceId,
        'contentType': 'live',
        'category': (category == null || category.isEmpty) ? null : category,
        'query': '',
        'anchorUrl': channel.url,
        'anchorName': channel.name,
        'offset': 0,
        // A full page rather than the native player's 200: unlike the native
        // guide this one has no scroll-prefetch to grow a small window, so the
        // ring has to arrive anchored AND whole. Anything past the provider's
        // own maximum is clamped there.
        'limit': _kIptvZapPageSize,
      });
    } catch (error) {
      debugPrint('Player: IPTV ring re-anchor failed: $error');
      return;
    }
    if (!mounted || result == null) return;
    // A newer zap owns the ring now — installing this page would drop the
    // viewer onto the wrong channel's neighbours.
    if (switchTicket != _iptvSwitchTicket) return;
    // The user browsed while this was in flight. Their category is the
    // current intent; this page predates it.
    if (contextGeneration != _iptvGuideContextGeneration) return;
    // Last line of defence: whatever else moved, the ring must only ever be
    // rebuilt around the channel that is actually playing.
    final playing = _currentIptvChannel;
    if (playing == null ||
        playing.url != channel.url ||
        playing.name != channel.name) {
      return;
    }

    final page = _parseIptvZapPage(result);
    if (page == null) return;
    final playingIndex = page.channels.indexWhere(
      (candidate) =>
          candidate.url == channel.url && candidate.name == channel.name,
    );
    // The page has to contain what is playing, or the ring would no longer
    // describe the channel on screen.
    if (playingIndex < 0) return;

    _clearIptvZapBoundaryCache();
    setState(() {
      _iptvChannelsOverride = page.channels;
      _currentIptvIndex = playingIndex;
      // Where this window sits in the category. Zapping past its edge needs
      // both numbers: without them the window's end and the category's end
      // are indistinguishable, and a category larger than one page would
      // cross into the next category partway through.
      _iptvZapWindowOffset = page.offset;
      _iptvZapCategoryTotal = page.total;
      // Binds every later boundary request to the source this ring came from,
      // however far the guide wanders afterwards.
      _iptvZapSourceId =
          page.sourceId ??
          _iptvGuideContextOverride?.sourceId ??
          widget.iptvSourceId;
      _iptvZapCategory = page.category;
      if (page.categories.isNotEmpty) _iptvZapCategories = page.categories;
      _iptvZapPagingActive = true;
    });
    _anchorIptvGuideCategory(channel, categories: result['categories']);
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

  /// How close to the window's edge counts as "about to need what's next".
  static const int _kIptvZapEdgeMargin = 12;

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

  /// The source and category the ring belongs to. Kept apart from the guide's
  /// selection on purpose: browsing can move the guide to another source or
  /// category — and leave it there without ever tuning — while the ring keeps
  /// describing what is playing. Asking the guide's source for the ring's
  /// category would fetch a category that source may not even have.
  String? _iptvZapSourceId;
  String? _iptvZapCategory;
  List<String> _iptvZapCategories = const [];

  int _iptvZapRequestTicket = 0;
  bool _iptvZapRequestInFlight = false;

  /// Presses that arrived while a page was loading. Crossing a page or a
  /// category is a round trip, so holding the key down has to queue rather
  /// than drop.
  final List<int> _iptvZapPendingInputs = [];
  bool _iptvZapDrainingInputs = false;

  /// The adjacent category, fetched before it is needed so crossing one costs
  /// no more than stepping inside the current one.
  String? _iptvZapCachedOriginCategory;
  int _iptvZapCachedDirection = 0;
  _IptvZapPage? _iptvZapCachedPage;

  /// Live IPTV with somewhere to zap to — either more than one channel in the
  /// ring, or a paged context that can fetch more.
  bool get _canZapIptvChannel =>
      _currentIptvChannel?.isLive == true &&
      ((_effectiveIptvChannels?.length ?? 0) > 1 || _iptvZapPagingActive);

  void _clearIptvZapBoundaryCache() {
    _iptvZapCachedOriginCategory = null;
    _iptvZapCachedDirection = 0;
    _iptvZapCachedPage = null;
  }

  /// The ring is about to stop being a page of a category. Bumping the request
  /// ticket strands anything in flight: it would otherwise merge a page of the
  /// old category into the new ring at positions that mean nothing there.
  void _resetIptvZapPaging() {
    _iptvZapPagingActive = false;
    _iptvZapWindowOffset = 0;
    _iptvZapCategoryTotal = 0;
    _iptvZapSourceId = null;
    _iptvZapCategory = null;
    _iptvZapRequestTicket++;
    _iptvZapRequestInFlight = false;
    _iptvZapPendingInputs.clear();
    _clearIptvZapBoundaryCache();
  }

  /// A re-anchor is out arming the ladder, so a burst of presses can't stack
  /// full-category queries behind it.
  bool _iptvZapArmingPaging = false;

  /// Arm the ladder around whatever live channel is playing now.
  ///
  /// The launch bootstrap re-anchors the channel the player opened with, but a
  /// zap landing before that response does moves the switch ticket on and the
  /// response is dropped. Nothing else would re-arm it, so the ladder would sit
  /// inactive and zapping would circle the launch window until the user opened
  /// the guide and retuned. Retrying from the zap itself closes that: the first
  /// press after a lost bootstrap arms the ladder for the channel it landed on.
  void _ensureIptvZapPagingArmed() {
    if (_iptvZapPagingActive || _iptvZapArmingPaging) return;
    if (widget.iptvBrowseProvider == null) return;
    final channel = _currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    _iptvZapArmingPaging = true;
    unawaited(
      _reanchorIptvRingToCategory(
        channel,
        switchTicket: _iptvSwitchTicket,
      ).whenComplete(() => _iptvZapArmingPaging = false),
    );
  }

  /// Previous/next channel in guide order.
  void _zapIptvChannel(int delta) {
    final channels = _effectiveIptvChannels;
    final current = _currentIptvChannel;
    if (channels == null || current == null || !current.isLive) return;
    if (!_iptvZapPagingActive && channels.length < 2) return;
    final from = _currentIptvIndex.clamp(0, channels.length - 1);
    final next = from + delta;

    if (!_iptvZapPagingActive) {
      // No paged context: the ring is all there is, so wrap inside it.
      unawaited(
        _switchToIptvChannel((next + channels.length) % channels.length),
      );
      // Tuning has already moved the index and the switch ticket, so this arms
      // the ladder around the channel just landed on.
      _ensureIptvZapPagingArmed();
      return;
    }

    if (next >= 0 && next < channels.length) {
      unawaited(_switchToIptvChannel(next));
      unawaited(_prefetchIptvZapPage(delta));
      unawaited(_prefetchAdjacentIptvCategory(delta));
      return;
    }

    final firstAbsolute = _iptvZapWindowOffset;
    final lastAbsolute = _iptvZapWindowOffset + channels.length - 1;
    final hasAnotherPage = delta > 0
        ? lastAbsolute + 1 < _iptvZapCategoryTotal
        : firstAbsolute > 0;
    if (hasAnotherPage) {
      // The category continues past the window. Hold the press until the page
      // it needs has landed, then replay it against the grown ring.
      _queuePendingIptvZapInput(delta);
      unawaited(_prefetchIptvZapPage(delta));
      return;
    }

    if (_consumeCachedAdjacentIptvCategory(delta)) return;
    unawaited(_requestAdjacentIptvCategory(delta));
  }

  /// One page request at a time, like native: a second in-flight request would
  /// race the first into the ring with no way to order the two.
  Future<_IptvZapPage?> _requestIptvZapPage({
    required String? category,
    required int offset,
    bool fromEnd = false,
  }) async {
    final provider = widget.iptvBrowseProvider;
    if (provider == null || _iptvZapRequestInFlight) return null;
    final ticket = ++_iptvZapRequestTicket;
    final contextGeneration = _iptvGuideContextGeneration;
    _iptvZapRequestInFlight = true;

    Map<String, dynamic>? result;
    try {
      result = await provider({
        'action': 'zapPage',
        // The ring's own source, not the guide's — see [_iptvZapSourceId].
        'sourceId':
            _iptvZapSourceId ??
            _iptvGuideContextOverride?.sourceId ??
            widget.iptvSourceId,
        'contentType': 'live',
        'category': (category == null || category.isEmpty) ? null : category,
        'query': '',
        'offset': offset < 0 ? 0 : offset,
        'limit': _kIptvZapPageSize,
        'fromEnd': fromEnd,
      });
    } catch (error) {
      debugPrint('Player: IPTV zap page failed: $error');
    }
    // A newer request (or a reset) owns the flag now — leave it to them.
    if (ticket != _iptvZapRequestTicket) return null;
    _iptvZapRequestInFlight = false;
    if (!mounted || result == null) {
      // Replaying queued presses against a ring that never grew would spin.
      _iptvZapPendingInputs.clear();
      return null;
    }
    // The user browsed while this was in flight; their category is the current
    // intent and every queued press belonged to the old one.
    if (contextGeneration != _iptvGuideContextGeneration) {
      _iptvZapPendingInputs.clear();
      return null;
    }
    return _parseIptvZapPage(result);
  }

  _IptvZapPage? _parseIptvZapPage(Map<String, dynamic> result) {
    final raw = result['channels'];
    if (raw is! List) return null;
    final channels = [
      for (final entry in raw.whereType<Map>())
        iptvChannelFromBrowsePayload(Map<String, dynamic>.from(entry)),
    ];
    final rawOffset = result['pageOffset'];
    final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
    final rawTotal = result['totalChannels'];
    final total = rawTotal is num ? rawTotal.toInt() : channels.length;
    final rawSourceId = (result['sourceId'] as String?)?.trim();
    final rawCategory = (result['selectedCategory'] as String?)?.trim();
    final rawCategories = result['categories'];
    return _IptvZapPage(
      channels: channels,
      offset: offset,
      // A total that doesn't cover the page it came with would put the
      // category's end behind the window's own last row.
      total: math.max(total, offset + channels.length),
      sourceId: (rawSourceId == null || rawSourceId.isEmpty)
          ? null
          : rawSourceId,
      category: (rawCategory == null || rawCategory.isEmpty)
          ? null
          : rawCategory,
      categories: rawCategories is List
          ? [
              for (final entry in rawCategories.whereType<String>())
                if (entry.isNotEmpty) entry,
            ]
          : const [],
    );
  }

  /// Replace the ring with [page]. The caller tunes afterwards, so the index
  /// left behind here is only a starting point.
  void _installIptvZapWindow(
    _IptvZapPage page, {
    required bool preservePlayingChannel,
  }) {
    if (page.channels.isEmpty) return;
    if (page.category != _iptvZapCategory) _clearIptvZapBoundaryCache();
    final playing = preservePlayingChannel ? _currentIptvChannel : null;
    var index = 0;
    if (playing != null) {
      final found = page.channels.indexWhere(
        (candidate) =>
            candidate.url == playing.url && candidate.name == playing.name,
      );
      if (found >= 0) index = found;
    }
    setState(() {
      _iptvChannelsOverride = page.channels;
      _currentIptvIndex = index;
      _iptvZapWindowOffset = page.offset;
      _iptvZapCategoryTotal = page.total;
      _iptvZapSourceId = page.sourceId ?? _iptvZapSourceId;
      _iptvZapCategory = page.category;
      if (page.categories.isNotEmpty) _iptvZapCategories = page.categories;
      _iptvZapPagingActive = true;
    });
  }

  /// Splice a freshly loaded page into the ring, growing the window rather
  /// than replacing it — the channel on screen has to keep its place, and the
  /// guide is looking at the same list.
  void _mergeIptvZapPage(_IptvZapPage page) {
    if (!_iptvZapPagingActive || page.channels.isEmpty) return;
    if (page.category != _iptvZapCategory) return;
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;

    final windowStart = _iptvZapWindowOffset;
    final merged = iptvMergeZapWindow(
      window: channels,
      windowOffset: windowStart,
      page: page.channels,
      pageOffset: page.offset,
    );
    // The page didn't touch the window — see iptvMergeZapWindow.
    if (merged == null) return;

    final playing = _currentIptvChannel;
    var index = _currentIptvIndex + (windowStart - merged.offset);
    if (playing != null) {
      final found = merged.channels.indexWhere(
        (candidate) =>
            candidate.url == playing.url && candidate.name == playing.name,
      );
      if (found >= 0) index = found;
    }
    setState(() {
      _iptvChannelsOverride = merged.channels;
      _currentIptvIndex = index.clamp(0, merged.channels.length - 1);
      _iptvZapWindowOffset = merged.offset;
      _iptvZapCategoryTotal = math.max(
        page.total,
        merged.offset + merged.channels.length,
      );
      if (page.categories.isNotEmpty) _iptvZapCategories = page.categories;
    });
  }

  /// Pull in the next page of the current category once zapping gets near the
  /// window's edge.
  Future<void> _prefetchIptvZapPage(int delta) async {
    if (!_iptvZapPagingActive || _iptvZapRequestInFlight) return;
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    final firstAbsolute = _iptvZapWindowOffset;
    final lastAbsolute = firstAbsolute + channels.length - 1;
    final shouldLoad = delta > 0
        ? lastAbsolute + 1 < _iptvZapCategoryTotal &&
              _currentIptvIndex >= channels.length - _kIptvZapEdgeMargin
        : firstAbsolute > 0 && _currentIptvIndex < _kIptvZapEdgeMargin;
    if (!shouldLoad) return;

    final page = await _requestIptvZapPage(
      category: _iptvZapCategory,
      offset: delta > 0
          ? lastAbsolute + 1
          : math.max(0, firstAbsolute - _kIptvZapPageSize),
    );
    if (!mounted || page == null) return;
    _mergeIptvZapPage(page);
    _drainPendingIptvZapInputs();
  }

  String? _adjacentIptvCategory(int delta, int attempt) =>
      iptvAdjacentZapCategory(
        categories: _iptvZapCategories,
        current: _iptvZapCategory,
        delta: delta,
        attempt: attempt,
      );

  Future<void> _prefetchAdjacentIptvCategory(
    int delta, {
    int attempt = 1,
  }) async {
    // A cached page only answers the direction it was fetched for; turning
    // around makes it the wrong end of the wrong category.
    if (_iptvZapCachedPage != null && _iptvZapCachedDirection != delta) {
      _clearIptvZapBoundaryCache();
    }
    if (!_iptvZapPagingActive ||
        _iptvZapRequestInFlight ||
        _iptvZapCategory == null ||
        _iptvZapCachedPage != null) {
      return;
    }
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    final nearBoundary = delta > 0
        ? _iptvZapWindowOffset + channels.length >= _iptvZapCategoryTotal &&
              _currentIptvIndex >= channels.length - _kIptvZapEdgeMargin
        : _iptvZapWindowOffset == 0 && _currentIptvIndex < _kIptvZapEdgeMargin;
    if (!nearBoundary) return;

    final target = _adjacentIptvCategory(delta, attempt);
    if (target == null) return;
    final origin = _iptvZapCategory;
    final page = await _requestIptvZapPage(
      category: target,
      offset: 0,
      fromEnd: delta < 0,
    );
    if (!mounted || page == null) return;
    // Zapping moved on while this loaded; it is no longer the next category.
    if (origin != _iptvZapCategory) return;
    if (page.channels.isEmpty) {
      await _prefetchAdjacentIptvCategory(delta, attempt: attempt + 1);
      return;
    }
    _iptvZapCachedOriginCategory = origin;
    _iptvZapCachedDirection = delta;
    _iptvZapCachedPage = page;
    _drainPendingIptvZapInputs();
  }

  /// Cross into the prefetched category with no round trip. Returns false when
  /// nothing usable was cached, leaving the caller to fetch.
  bool _consumeCachedAdjacentIptvCategory(int delta) {
    final cached = _iptvZapCachedPage;
    if (cached == null ||
        cached.channels.isEmpty ||
        _iptvZapCachedOriginCategory != _iptvZapCategory ||
        _iptvZapCachedDirection != delta) {
      return false;
    }
    _clearIptvZapBoundaryCache();
    _enterIptvZapCategory(cached, delta);
    unawaited(_prefetchAdjacentIptvCategory(delta));
    return true;
  }

  /// Adopt [page] as the ring and tune the channel the zap was heading for:
  /// going forwards that is the new category's first channel, going backwards
  /// its last.
  void _enterIptvZapCategory(_IptvZapPage page, int delta) {
    _installIptvZapWindow(page, preservePlayingChannel: false);
    unawaited(_switchToIptvChannel(delta > 0 ? 0 : page.channels.length - 1));
    // After the tune, not before: the switch anchors the guide to the tuned
    // channel's own group, and the response's category is the more accurate
    // of the two (it can be the null of an uncategorized wrap, which no
    // channel's group expresses).
    _applyIptvGuideCategory(
      page.category,
      page.categories.isEmpty ? null : page.categories,
    );
    unawaited(_prefetchIptvZapPage(delta));
  }

  /// The category ran out. Load the adjacent one, skipping any that come back
  /// empty, and give up once every category has been tried.
  Future<void> _requestAdjacentIptvCategory(
    int delta, {
    int attempt = 1,
  }) async {
    if (_iptvZapRequestInFlight) {
      _queuePendingIptvZapInput(delta);
      return;
    }
    final hasCategories = _iptvZapCategories.any((c) => c.isNotEmpty);
    if (_iptvZapCategory == null || !hasCategories) {
      // An uncategorized/"All" context has no category boundary to cross:
      // wrap by paging the opposite end of the same result set.
      final page = await _requestIptvZapPage(
        category: null,
        offset: 0,
        fromEnd: delta < 0,
      );
      if (!mounted || page == null || page.channels.isEmpty) {
        // Nothing came back to zap into, so nothing will drain these either.
        _iptvZapPendingInputs.clear();
        return;
      }
      _enterIptvZapCategory(page, delta);
      _drainPendingIptvZapInputs();
      return;
    }

    // Null once the walk has been all the way round — every category was
    // empty, so nothing will ever drain the queued presses.
    final target = _adjacentIptvCategory(delta, attempt);
    if (target == null) {
      _iptvZapPendingInputs.clear();
      return;
    }
    final page = await _requestIptvZapPage(
      category: target,
      offset: 0,
      fromEnd: delta < 0,
    );
    if (!mounted || page == null) return;
    if (page.channels.isEmpty) {
      await _requestAdjacentIptvCategory(delta, attempt: attempt + 1);
      return;
    }
    _enterIptvZapCategory(page, delta);
    unawaited(_prefetchAdjacentIptvCategory(delta));
    _drainPendingIptvZapInputs();
  }

  void _queuePendingIptvZapInput(int delta) {
    if (_iptvZapPendingInputs.length >= 24) return;
    _iptvZapPendingInputs.add(delta >= 0 ? 1 : -1);
  }

  void _drainPendingIptvZapInputs() {
    if (_iptvZapDrainingInputs) return;
    _iptvZapDrainingInputs = true;
    try {
      while (_iptvZapPendingInputs.isNotEmpty) {
        final queued = _iptvZapPendingInputs.length;
        _zapIptvChannel(_iptvZapPendingInputs.removeAt(0));
        // Another round trip started: the rest drain when it lands.
        if (_iptvZapRequestInFlight) break;
        // The press went straight back on the queue without starting one, so
        // nothing will arrive to move it along — stop instead of spinning.
        if (_iptvZapPendingInputs.length >= queued) break;
      }
    } finally {
      _iptvZapDrainingInputs = false;
    }
  }

  /// Turn an archived EPG programme into a finite, seekable IPTV item in the
  /// current player. The normal IPTV switching path remains responsible for
  /// headers, transition feedback, tracks, and resume identity.
  Future<void> _playIptvCatchup(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    final requestTicket = _beginIptvCatchupRequest();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Preparing replay of "${programme.title}"…'),
        duration: const Duration(seconds: 30),
      ),
    );
    String? url;
    try {
      url = await IptvEpgService.instance.catchupUrl(channel.url, programme);
    } catch (error) {
      debugPrint('Player: IPTV replay lookup failed: $error');
    }
    if (!_isCurrentIptvCatchupRequest(requestTicket)) return;
    if (url == null) {
      _iptvCatchupRequests.complete(requestTicket);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Replay is not available')),
      );
      return;
    }

    final sourceId =
        channel.attributes['source_playlist_id'] ??
        _iptvGuideContextOverride?.sourceId ??
        widget.iptvSourceId;
    final replay = IptvChannel(
      name: programme.title,
      url: url,
      logoUrl: channel.logoUrl,
      group: channel.name,
      contentType: 'vod',
      httpHeaders: channel.httpHeaders,
      attributes: {if (sourceId != null) 'source_playlist_id': sourceId},
    );
    await StorageService.recordIptvWatch(
      replay.url,
      channelName: replay.name,
      logoUrl: replay.logoUrl,
      group: replay.group,
      playlistId: sourceId,
      httpHeaders: replay.httpHeaders,
    );
    if (!_isCurrentIptvCatchupRequest(requestTicket)) return;
    _iptvCatchupRequests.complete(requestTicket);
    messenger.hideCurrentSnackBar();
    // A replay is a single on-demand item, not a page of any category.
    _resetIptvZapPaging();
    _iptvChannelsOverride = [replay];
    await _switchToIptvChannel(0);
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

  /// mpv reports a failed stream as several errors in a row; only the first of
  /// a burst is worth a message. Cleared on every zap so each channel the user
  /// tries can report once — collapsing a burst must not silence the next
  /// channel's genuine failure.
  DateTime? _lastIptvErrorShown;

  /// A plain IPTV channel's stream failed. Say so — the alternative (and the
  /// pre-existing behavior) is an indefinite black screen that reads as the
  /// whole IPTV section being broken.
  void _onIptvStreamError(String error) {
    if (!mounted || _iptvErrorsMuted) return;
    final channels = _effectiveIptvChannels;
    if (channels == null) return;

    final now = DateTime.now();
    final last = _lastIptvErrorShown;
    if (last != null && now.difference(last) < const Duration(seconds: 6)) {
      return;
    }
    _lastIptvErrorShown = now;

    final name = (_currentIptvIndex >= 0 && _currentIptvIndex < channels.length)
        ? channels[_currentIptvIndex].name
        : 'This channel';
    debugPrint('Player: IPTV stream error on "$name": $error');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$name didn't play — $error"),
        duration: const Duration(seconds: 5),
      ),
    );
  }

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
    final idx = widget.iptvStartIndex ?? 0;
    if (channels == null || idx < 0 || idx >= channels.length) return;
    final channel = channels[idx];
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) return;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || found.isEmpty) return;
      // The user already zapped away (or a switch populated sources itself).
      if (_iptvChannelKey != null || _currentIptvIndex != idx) return;
      var current = found.indexWhere((c) => c.url == widget.videoUrl);
      if (current < 0) current = 0;
      _setIptvSources(channel.url, found, currentIndex: current);
    });
  }

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
          lang = await StorageService.getIptvSeriesAudioLanguage(key);
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

  /// The desktop capture, when it belongs to the CURRENTLY PLAYING channel —
  /// asked of the SERVICE, not this screen's own field, so a capture the
  /// desktop SCHEDULER started shows up on (and stops from) the Record button
  /// too when its channel is being watched.
  DesktopRecordingCapture? _desktopCaptureForCurrent() {
    final channel = _currentIptvChannel;
    if (channel == null) return null;
    final playing = _playingLiveUrl(channel);
    if (playing == null) return null;
    final service = DesktopRecordingService.instance;
    final direct = service.captureForUrl(playing);
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(playing);
    return twin != null ? service.captureForUrl(twin) : null;
  }

  Future<void> _toggleRecording() async {
    // Desktop capture of the current channel: stop it.
    final desktopCapture = _desktopCaptureForCurrent();
    if (desktopCapture != null) {
      final savedPath = desktopCapture.path;
      final bytes = await desktopCapture.stop();
      if (!mounted) return;
      // The revision listener has already repainted (the capture ended during
      // that await); this only guarantees it for the pathological case where
      // the notification was swallowed.
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bytes > 0
                ? 'Recording saved: $savedPath'
                : 'Recording failed — nothing was captured',
          ),
        ),
      );
      return;
    }
    // Engine capture of the current channel: stop it. Finalization is async in
    // the service; its "Saved" notification is the confirmation.
    final engineTask = _engineTaskId;
    if (engineTask != null) {
      setState(() => _engineTaskId = null);
      final ok = await LiveRecordingService.stop(engineTask);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Recording stopped — saving to Downloads/Debrify/Recordings'
                : "Couldn't stop recording",
          ),
        ),
      );
      return;
    }
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    // Engine first on Android: its capture survives zaps, Home, even the app
    // dying. The tee stays as the fallback — and as the only recorder for true
    // HLS, which mpv can capture but the engine cannot.
    if (Platform.isAndroid && _engineFlagOn && _recordingSupported) {
      final channel = _currentIptvChannel;
      final recordUrl = await _engineRecordUrlForCurrent();
      if (channel != null && recordUrl != null) {
        if (!await ensureRecordingCapacity(context)) return;
        if (!mounted) return;
        // This path skips ensureEngineReady (support was pre-checked), so
        // the one-time notification ask lives here explicitly — fire-and-
        // forget, so an unanswered dialog can't delay the capture.
        unawaited(LiveRecordingService.ensureNotificationPermission());
        final result = await LiveRecordingService.start(
          url: recordUrl,
          fileName: _recordingFileName(channel.name),
          channelName: channel.name,
          headers: channel.playbackHeaders,
        );
        if (!mounted) return;
        if (result.ok) {
          setState(() => _engineTaskId = result.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recording in background — keeps going if you zap or leave. '
                'Stop from here or the notification.',
              ),
            ),
          );
        } else if (result.errorCode == 'recording_limit_reached') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recording limit reached — free a slot or raise the limit '
                'in IPTV settings',
              ),
            ),
          );
        } else if (result.errorCode == 'engine_unsupported' ||
            result.errorCode == 'fgs_not_allowed' ||
            result.errorCode == 'missing_plugin') {
          // Engine unreachable: the tee still works, with its semantics.
          await _startRecording();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't start recording")),
          );
        }
        return;
      }
      // recordUrl == null: true segmented stream (no Xtream twin) — only the
      // tee can capture what mpv is demuxing. Fall through.
    }
    // Desktop: the raw HTTP capture is the ONLY recorder that works — the mpv
    // tee is dead on media_kit's stock libs (no muxers in its FFmpeg). Never
    // fall through to the tee here; for unrecordable streams say so instead
    // of starting something that provably writes nothing.
    if (DesktopRecordingService.instance.isSupported && _recordingSupported) {
      final channel = _currentIptvChannel;
      final recordUrl = await _engineRecordUrlForCurrent();
      if (channel == null) return;
      if (recordUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "This channel can't be recorded on desktop (HLS stream)",
            ),
          ),
        );
        return;
      }
      if (!await ensureRecordingCapacity(context)) return;
      if (!mounted) return;
      // Raw byte copy → the capture IS a transport stream: .ts, not the
      // tee's .mkv.
      final path = await _recordingTargetPath(channel.name, extension: 'ts');
      // The screen may have closed during that await. Starting now would be
      // legitimate — captures outlive this screen — but the state below can't
      // be set on a dead widget, and the user asked for this from a surface
      // that is gone.
      if (!mounted) return;
      // No onFinished: endings are announced app-wide by the reporter in
      // main(), which is still alive when this screen isn't, and the revision
      // listener repaints the button. A screen-scoped callback would only
      // duplicate the toast while the player happens to be open.
      final capture = DesktopRecordingService.instance.start(
        url: recordUrl,
        path: path,
        channelName: channel.name,
        headers: channel.playbackHeaders,
      );
      if (!mounted) return;
      if (capture == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start recording")),
        );
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recording in background — keeps going if you zap or leave. '
            'Stop from here or Settings → Recordings.',
          ),
        ),
      );
      return;
    }
    await _startRecording();
  }

  /// The URL actually PLAYING for [channel]. NOT `_currentStreamUrl` for
  /// plain channels — the zap path never updates that field, so after a zap
  /// it still holds the previous channel's URL, and matching on it would pin
  /// the Record button (and its Stop!) to the wrong capture. The channel's
  /// own URL is the identity for everything except Stremio, whose playing URL
  /// is the resolved candidate only `_currentStreamUrl` knows.
  String? _playingLiveUrl(IptvChannel channel) {
    if (!channel.url.startsWith('stremio-tv://')) return channel.url;
    final resolved = _currentStreamUrl;
    if (resolved == null || resolved.startsWith('stremio-tv://')) return null;
    return resolved;
  }

  /// The URL the ENGINE should capture for the current live channel, or null
  /// when only the tee can record it. mpv's own `file-format` is ground truth
  /// for what's actually playing (extension-less URLs lie); the URL shape is
  /// the fallback when the probe is unavailable.
  Future<String?> _engineRecordUrlForCurrent() async {
    final channel = _currentIptvChannel;
    if (channel == null || channel.isLive != true) return null;
    final playing = _playingLiveUrl(channel);
    if (playing == null || playing.isEmpty) return null;
    // The engine speaks HTTP only. rtmp/rtsp/udp/... channels go to the tee —
    // mpv plays them, so mpv can record them. Checked BEFORE the probe: mpv
    // reports e.g. "flv" for RTMP, which would read as progressive below.
    if (!playing.startsWith('http://') && !playing.startsWith('https://')) {
      return null;
    }
    String format = '';
    final platform = _player.platform;
    if (platform is mk.NativePlayer) {
      try {
        format = await platform.getProperty('file-format');
      } catch (_) {}
    }
    final lower = format.toLowerCase();
    if (lower.contains('hls') || lower.contains('dash')) {
      // Segmented for sure — only an Xtream `.ts` twin can rescue it.
      return LiveRecordingService.xtreamTsTwin(playing);
    }
    if (lower.isNotEmpty) {
      // Probe says progressive: record exactly what's playing.
      return playing;
    }
    return LiveRecordingService.engineRecordableUrl(playing);
  }

  /// Re-derive [_engineTaskId] from the native registry — a capture may have
  /// been started in an earlier player session, or stopped from the
  /// notification while this screen was open.
  Future<void> _refreshEngineRecordingState() async {
    if (!Platform.isAndroid || !_engineFlagOn) return;
    final channel = _currentIptvChannel;
    if (channel == null || channel.isLive != true) {
      if (_engineTaskId != null && mounted) {
        setState(() => _engineTaskId = null);
      }
      return;
    }
    final ticket = ++_engineRefreshTicket;
    final playing = _playingLiveUrl(channel);
    if (playing == null) {
      if (_engineTaskId != null) setState(() => _engineTaskId = null);
      return;
    }
    final twin = LiveRecordingService.xtreamTsTwin(playing);
    final recordings = await LiveRecordingService.query();
    if (!mounted || ticket != _engineRefreshTicket) return;
    String? found;
    for (final r in recordings) {
      if (r.isRecording &&
          (r.url == playing || (twin != null && r.url == twin))) {
        found = r.taskId;
        break;
      }
    }
    if (found != _engineTaskId) {
      setState(() => _engineTaskId = found);
    }
  }

  /// `<Channel>_<yyyyMMdd_HHmmss>.ts` — same shape as the tee's target path
  /// (which additionally uniquifies against its own directory; MediaStore
  /// uniquifies for the engine).
  String _recordingFileName(String channelName) {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${base}_$stamp.ts';
  }

  /// Print mpv log lines that matter while a tee recording runs.
  void _tapMpvLogsForRecording() {
    _recordLogSub?.cancel();
    _recordLogSub = _player.stream.log.listen((log) {
      debugPrint('VideoPlayer: mpv[${log.level}] ${log.prefix}: ${log.text}');
    });
  }

  void _untapMpvLogs() {
    _recordLogSub?.cancel();
    _recordLogSub = null;
  }

  Future<void> _startRecording() async {
    if (!_playerCreated) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    final channel = _currentIptvChannel;
    if (channel == null) return;
    final gen = ++_recordingStartGen;
    try {
      final path = await _recordingTargetPath(channel.name);
      final parent = Directory(path).parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      // The channel (or the whole screen) may have gone while the storage work
      // ran. Arming now would tee the NEW stream into the old channel's file.
      if (gen != _recordingStartGen || !mounted || !_playerCreated) return;
      _tapMpvLogsForRecording();
      await platform.setProperty('stream-record', path);
      // Read the property back: proves whether mpv actually ACCEPTED the
      // target (a silent internal failure leaves it set but writes nothing —
      // the log tap above catches that case).
      var echoed = '';
      try {
        echoed = await platform.getProperty('stream-record');
      } catch (_) {}
      debugPrint(
        'VideoPlayer: stream-record armed — mpv reports "$echoed" '
        '(want "$path")',
      );
      if (gen != _recordingStartGen || !mounted) {
        // Lost the race inside setProperty itself: disarm rather than leave an
        // untracked recording running on someone else's stream.
        _untapMpvLogs();
        await _disarmStrayRecording(platform, path);
        return;
      }
      setState(() {
        _isRecording = true;
        _recordingTempPath = path;
      });
      // Crash insurance: registered natively so the file gets published on
      // next launch even if this process never reaches _stopRecording.
      if (Platform.isAndroid) {
        unawaited(
          AndroidNativeDownloader.registerPendingRecording(
            path: path,
            fileName: path.split(Platform.pathSeparator).last,
            mimeType: 'video/x-matroska',
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // The tee records what the player reads, so on Android (where the
            // engine exists as the contrast) say the semantics out loud.
            Platform.isAndroid
                ? 'Recording started (stops if you leave the channel)'
                : 'Recording started',
          ),
        ),
      );
    } catch (e) {
      _untapMpvLogs();
      debugPrint('VideoPlayer: start recording failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start recording')),
      );
    }
  }

  /// Undo a recording that got armed after its channel or screen went away.
  /// The stub file is milliseconds old, so dropping it loses nothing a user
  /// would recognise as a recording.
  Future<void> _disarmStrayRecording(
    mk.NativePlayer platform,
    String path,
  ) async {
    try {
      await platform.setProperty('stream-record', '');
    } catch (e) {
      debugPrint('VideoPlayer: disarm stray recording failed: $e');
    }
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('VideoPlayer: stray recording cleanup failed: $e');
    }
  }

  /// Stop the active recording. Auto-stops (channel change / dispose) pass
  /// [userInitiated] = false to stay quiet.
  Future<void> _stopRecording({bool userInitiated = true}) async {
    // A stop supersedes an in-flight start too — including one that has not
    // yet flipped `_isRecording` and so is invisible to the check below.
    _recordingStartGen++;
    if (!_isRecording) return;
    final path = _recordingTempPath;
    final platform = _playerCreated ? _player.platform : null;
    // Flip state first so a rapid re-tap / channel switch can't double-stop.
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingTempPath = null;
      });
    } else {
      _isRecording = false;
      _recordingTempPath = null;
    }
    try {
      if (platform is mk.NativePlayer) {
        await platform.setProperty('stream-record', '');
      }
    } catch (e) {
      debugPrint('VideoPlayer: stop recording failed: $e');
    }
    _untapMpvLogs();
    if (path == null) return;
    // VERIFY before claiming anything: mpv can accept `stream-record` and
    // still write nothing (internal fopen refused, undumpable demuxer) — the
    // first macOS test hit exactly that, with a "saved" message over an empty
    // folder.
    var fileBytes = 0;
    try {
      final file = File(path);
      if (await file.exists()) fileBytes = await file.length();
    } catch (_) {}
    debugPrint(
      'VideoPlayer: tee recording stopped — $fileBytes bytes on disk at $path',
    );
    final fileOk = fileBytes > 0;
    // Publish to a user-visible location. On Android the file lives in
    // app-private storage, so hand it to the native MediaStore publisher; on
    // desktop it's already under the user's Downloads.
    if (fileOk && Platform.isAndroid) {
      unawaited(_publishRecording(path, userInitiated: userInitiated));
    } else if (userInitiated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fileOk
                ? 'Recording saved: $path'
                : 'Recording failed — mpv wrote no file (see logs)',
          ),
        ),
      );
    }
  }

  Future<void> _publishRecording(
    String path, {
    required bool userInitiated,
  }) async {
    var published = false;
    try {
      final fileName = path.split(Platform.pathSeparator).last;
      final uri = await AndroidNativeDownloader.saveLocalFile(
        path: path,
        fileName: fileName,
        mimeType: 'video/x-matroska',
      );
      published = uri != null;
    } catch (e) {
      debugPrint('VideoPlayer: publish recording failed: $e');
    }
    if (!userInitiated || !mounted) return;
    // On failure, don't claim a save the user can't find: the file sits in
    // app-private storage, its registry entry survives (only a successful
    // publish clears it), and the next app launch re-attempts the publish.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          published
              ? 'Recording saved to Downloads/Debrify/Recordings'
              : "Recording couldn't be added to Downloads — "
                    'will retry next launch',
        ),
      ),
    );
  }

  /// A path no other recording is using. The second-resolution stamp alone
  /// collides when the same channel is stopped and restarted inside one
  /// second, and that collision is destructive: libmpv would truncate (or
  /// append to) the previous file, and on Android the still-running publisher
  /// deletes its source once copied — taking the NEW recording with it. An
  /// existing file therefore means "in use": step aside with a suffix.
  ///
  /// Default `.mkv` (the TEE): mpv's recorder picks the output muxer from the
  /// filename, and media_kit's decode-trimmed FFmpeg ships no `mpegts` muxer
  /// ("recorder: Output format not found" → recording silently disabled —
  /// found live on macOS). Matroska is the only sane target IF a muxer
  /// exists. Raw byte copiers (the desktop capture, the Android engine) pass
  /// `extension: 'ts'` — their bytes ARE a transport stream, no muxer
  /// involved.
  Future<String> _recordingTargetPath(
    String channelName, {
    String extension = 'mkv',
  }) async {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';

    Directory dir;
    if (Platform.isAndroid) {
      dir =
          (await getExternalStorageDirectory()) ??
          await AppStorage.documents();
    } else {
      dir =
          (await getDownloadsDirectory()) ??
          await AppStorage.documents();
    }
    final sep = Platform.pathSeparator;
    final prefix = '${dir.path}${sep}Debrify${sep}Recordings$sep${base}_$stamp';

    var candidate = '$prefix.$extension';
    for (var n = 2; n < 100 && await File(candidate).exists(); n++) {
      candidate = '${prefix}_$n.$extension';
    }
    // Pathological (99 restarts in one second): fall back to microseconds,
    // which cannot collide with any of the names tried above.
    if (await File(candidate).exists()) {
      candidate = '${prefix}_${now.microsecondsSinceEpoch}.$extension';
    }
    return candidate;
  }

  Future<void> _switchToIptvChannel(int index) async {
    final channels = _effectiveIptvChannels;
    if (channels == null || index < 0 || index >= channels.length) return;
    // A channel change ends the current recording (the stream identity flips).
    // Unconditional: it must also cancel a start still awaiting its storage
    // setup, which `_isRecording` would not report yet.
    await _stopRecording(userInitiated: false);
    _cancelPendingIptvCatchup();
    final ticket = ++_iptvSwitchTicket;
    // This switch owns the error gate now (a superseded ladder's state doesn't
    // survive). Muted until the new media is opened below; the burst debounce
    // resets too, so this channel can report its own failure.
    _iptvErrorsMuted = true;
    _lastIptvErrorShown = null;

    _hideIptvChannelSheet();

    final channel = channels[index];
    _clearBufferingIndicator();
    setState(() {
      _isTransitioning = true;
      _tvScrubGeneration++;
      _tvAbandonScrub();
      _currentIptvIndex = index;
      _currentChannelNumber = channel.channelNumber ?? (index + 1);
      // The corner badge is painted from this pair; without the name it kept
      // showing the launch channel under the new channel's number.
      _currentChannelName = channel.name;
    });
    _startTransitionOverlay();
    // Identity paints from the channel itself, so it is correct before a
    // single byte of the new stream has arrived; the guide fills in behind it.
    // Zapping to on-demand retires the panel outright — it has no live
    // identity to present, and leaving it up would describe the wrong item.
    if (channel.isLive) {
      _prepareIptvBannerData(channel);
      _raiseIptvZapBanner();
      // The guide follows what is playing, so reopening it lands on the
      // category the current channel actually belongs to. A paged ring is the
      // exception: it already knows its own category from the response, which
      // a single channel's group can't always express — an "All"/uncategorized
      // window would keep narrowing the guide to whichever group it landed on.
      if (!_iptvZapPagingActive) _anchorIptvGuideCategory(channel);
    } else {
      _hideIptvZapBanner();
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
          final ok = await _tryOpenLiveStream(url);
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
        final media = mk.Media(
          channel.url,
          httpHeaders: channel.playbackHeaders,
        );
        // The outgoing stream is torn down (pause above); everything mpv
        // reports from here is this channel's, including a fast failure that
        // lands while open() is still awaiting.
        _iptvErrorsMuted = false;
        await _player.open(media, play: true);
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
    if (_engineFlagOn) unawaited(_refreshEngineRecordingState());
  }

  /// Open [url] and wait until it demonstrably plays (a decoded video size or
  /// advancing position) or demonstrably fails (player error, open() throw,
  /// or the timeout — live streams can stall without ever erroring). Used by
  /// the Stremio channel ladder to decide whether to try the next candidate.
  Future<bool> _tryOpenLiveStream(
    String url, {
    Duration timeout = const Duration(seconds: 12),
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
      await _player.open(mk.Media(url), play: true);
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

  // ─── Stremio Source Sheet ───────────────────────────────────────────

  void _showSourceSheetOverlay() {
    final sources = _effectiveSources;
    if (sources == null || sources.isEmpty) return;
    _hideIptvZapBanner();
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
      await _switchToSourcePlaylist(index, pendingPlaylist);
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
    try {
      await _player.pause();
    } catch (_) {}
    final ok = await _tryOpenLiveStream(url);
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
    List<PlaylistEntry> newPlaylist,
  ) async {
    _hideSourceSheet();
    _clearBufferingIndicator();
    // Capture the episode we're on BEFORE swapping the playlist, so we can
    // land on it in the new source instead of jumping to the pack's first
    // entry (S1E1). Read from the current playlist entry (tracks auto-advance).
    final se = _traktSeasonEpisode();
    // Checkpoint the OUTGOING episode now, while _activePlaylist/_currentIndex
    // still point at it — after the swap the index would resolve against the
    // new playlist. _loadPlaylistIndex below is told to skip its own save.
    await _saveResume();
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

    // Replace playlist and invalidate series cache
    setState(() {
      _activePlaylist = newPlaylist;
      _cachedSeriesPlaylist = null;
      _playlistIdentityToken++;
    });

    // Resume the SAME episode from the new source (a season/complete pack would
    // otherwise restart at S1E1); _loadPlaylistIndex restores its saved
    // position.
    var targetIndex = 0;
    // Whether the new source landed on the SAME content we were watching — only
    // then does "prefer the checkpointed local position over Trakt" apply. When
    // we fall back to a different episode, its own Trakt resume must still work.
    var landedOnSameContent = true;
    if (se.season != null && se.episode != null) {
      final sp = _seriesPlaylist;
      final idx =
          sp?.findOriginalIndexBySeasonEpisode(se.season!, se.episode!) ?? -1;
      if (idx >= 0) {
        targetIndex = idx;
      } else {
        landedOnSameContent = false;
        // The exact episode isn't in this source. Don't fall back to raw entry
        // 0 — in torrent order that's often an extras/bonus clip. Land on the
        // first REAL episode (skips season 0 / specials) and warn the user.
        final firstReal = sp?.getFirstEpisodeOriginalIndex() ?? -1;
        if (firstReal >= 0) targetIndex = firstReal;
        if (mounted) {
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
    await _loadPlaylistIndex(
      targetIndex,
      autoplay: true,
      skipInitialSave: true,
      preferLocalResume: landedOnSameContent,
    );
    if (!mounted) return;

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

    // Capture current position before switching so playback continues seamlessly
    final resumePosition = _position;

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

    try {
      await _player.open(mk.Media(url), play: !hasExternalAudio);
      // Wait for the new media to load before seeking
      await _waitForVideoReady();
      if (!mounted) return;
      if (hasExternalAudio) {
        await _setExternalAudioTrack(widget.audioUrl!);
      }
      // Seek to the position from the previous source
      if (resumePosition > Duration.zero) {
        await _player.seek(resumePosition);
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
        unawaited(_restoreTrackPreferences());
      }
    } catch (e) {
      debugPrint('Player: Stremio source switch failed: $e');
    }

    if (!mounted) return;

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
    _currentEpisodeMarkedAsFinished = false;

    try {
      _pikPakRetryId++;
      await _player.open(mk.Media(url), play: true);
      _currentStreamUrl = url;
      await _player.setSubtitleTrack(mk.SubtitleTrack.no());
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

    // Clear subtitle and IMDB state when switching channels
    _resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;

    try {
      _pikPakRetryId++;
      await _player.open(
        mk.Media(nextUrl, httpHeaders: widget.httpHeaders),
        play: true,
      );
      _currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _player.setSubtitleTrack(mk.SubtitleTrack.no());
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

    // Clear subtitle and IMDB state when switching channels
    _resetSubtitleState();
    _singleFileImdbId = null;
    _singleFileImdbFetched = false;

    try {
      // Cancel any ongoing PikPak retry when switching channels
      _pikPakRetryId++;
      await _player.open(
        mk.Media(nextUrl, httpHeaders: widget.httpHeaders),
        play: true,
      );
      _currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _player.setSubtitleTrack(mk.SubtitleTrack.no());
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
        await StorageService.markEpisodeAsFinished(
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
        seriesPlaylist.seriesTitle == null)
      return;
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
          await StorageService.markEpisodeAsFinished(
            seriesTitle: seriesPlaylist.seriesTitle!,
            season: currentEpisode.seriesInfo.season!,
            episode: currentEpisode.seriesInfo.episode!,
            imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId,
          );
        }
      }
    } catch (e) {}
  }

  /// Check if current episode should be marked as finished (for manual seeking)
  ///
  /// Sync on purpose: this runs on EVERY position event — dozens of times a
  /// second for the whole session — and as an async function each of those
  /// calls allocated a Future and a microtask just to hit the first early
  /// return. The actual marking stays async and is fired unawaited, exactly
  /// as the position listener already treated it.
  void _checkAndMarkEpisodeAsFinished() {
    if (_currentEpisodeMarkedAsFinished) return;
    // Only check if we're near the end of the video (within last 30 seconds)
    if (_duration > Duration.zero && _position > Duration.zero) {
      final timeRemaining = _duration - _position;
      if (timeRemaining <= VideoPlayerTimingConstants.endingThreshold) {
        unawaited(_markCurrentEpisodeAsFinished());
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
    _skipSegmentsMediaReady = true;
    if (mounted) {
      setState(() {
        _isTransitioning = false;
      });
    } else {
      _isTransitioning = false;
    }
  }

  Future<void> _loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    bool skipInitialSave = false,
    // Source switch on the same content: resume the checkpointed local position
    // exactly (see _maybeRestoreResume).
    bool preferLocalResume = false,
  }) async {
    // A new item is being loaded: any scrub in flight belongs to the outgoing
    // one and must never land on this one.
    _tvScrubGeneration++;
    _tvAbandonScrub();
    if (_activePlaylist == null ||
        index < 0 ||
        index >= _activePlaylist!.length) {
      _clearTransitionOnFailure();
      return;
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
        return;
      }
      _sleepStopLatched = false;
    }

    print(
      'PikPak: _loadPlaylistIndex called with index: $index, autoplay: $autoplay',
    );

    // Scrobble stop for the current episode before switching
    _stopTraktHeartbeat();
    _traktScrobble('stop');
    _stopSimklHeartbeat();
    _simklScrobble('stop');

    // Callers that already checkpointed the outgoing episode (e.g. a source
    // switch, which saves BEFORE swapping the playlist) skip this save so it
    // can't write the current position against the newly-swapped playlist.
    if (!skipInitialSave) {
      await _saveResume();
    }
    final entry = _activePlaylist![index];
    _currentIndex = index;
    _currentEpisodeMarkedAsFinished = false;

    // Clear subtitle cache and selection when changing content
    _resetSubtitleState();
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
      return;
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
      await _player.open(
        mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
        play: autoplay,
      );
    }

    // Wait for the video to load and duration to be available
    await _waitForVideoReady();
    await _maybeRestoreResume(preferLocalResume: preferLocalResume);
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

    // Premiumize cloud-browser lazy resolution: re-fetch a fresh direct link by
    // cloud item id (items saved from the cloud browser have no infohash).
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final apiKey = await StorageService.getPremiumizeApiKey();
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
      final apiKey = await StorageService.getPremiumizeApiKey();
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
      final apiKey = await StorageService.getAllDebridApiKey();
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
  Future<void> _playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
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
      await _player.open(
        mk.Media(videoUrl, httpHeaders: widget.httpHeaders),
        play: true,
      );
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
      await _player.open(
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
          return;
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
          return;
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
          return;
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
          return;
        }

        // Try reopening the player (might help reactivate cold storage file)
        try {
          await _player.open(
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
          return;
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
          return;
        }

        // Try reopening the player for next attempt
        try {
          await _player.open(
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
  }

  /// Preload episode information in the background
  Future<void> _preloadEpisodeInfo() async {
    final seriesPlaylist = _seriesPlaylist;

    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlistIdentityToken = _playlistIdentityToken;
      // Preload episode information in the background
      // Pass IMDB ID from catalog for faster, more accurate lookup
      seriesPlaylist
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
      seriesPlaylist
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
      _fetchSingleFileMovieMetadata();
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
    unawaited(_fetchAndMaybeAutoSelectAddonSubtitle());
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

    await StorageService.updatePlaylistItemImdbId(
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
        await StorageService.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await StorageService.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await StorageService.updatePlaylistItemPoster(
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
      _hideTimer?.cancel();
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
    // _isTransitioning too, not just _isPlaying: mid-switch (next episode, a
    // zap) `playing` is briefly false while an open(play: true) is in flight.
    // Backgrounding in that window must still arm the flag, or the open lands
    // moments later and plays behind the backgrounded app with the guard in
    // the playing listener disarmed. A user's own pause has neither set.
    if (!_playerCreated || (!_isPlaying && !_isTransitioning)) return;
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
    if (!_playerCreated || !mounted) return;
    // Coming back from the background is not a request to un-stop the night:
    // if the sleep timer fired while we were away, stay paused until someone
    // presses play.
    if (_sleepStopLatched) return;
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
    // The sleep timer belongs to this playback session — a pending one must not
    // outlive the player and fire against a disposed state.
    _sleepTimer?.cancel();
    _sleepTimer = null;
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
                  _publishRecording(path, userInitiated: false);
                }
              }),
        );
      } else if (path != null && Platform.isAndroid) {
        unawaited(_publishRecording(path, userInitiated: false));
      }
    }
    _iptvCatchupRequests.cancel();
    // Detach from PiP (disarms auto-enter); ignored if a newer player already
    // took ownership, so route replacement can't disarm the incoming screen.
    PipService.detach(this);
    // Scrobble stop to Trakt when user exits player
    _stopTraktHeartbeat();
    _analyticsHeartbeatTimer?.cancel();
    _traktScrobble('stop');
    _stopSimklHeartbeat();
    _simklScrobble('stop');

    // Save the current state before disposing
    _saveResume();

    // Cancel any ongoing PikPak retry operations
    _pikPakRetryId++;
    _isPikPakRetrying = false;
    _pikPakRetryCount = 0;
    _pikPakRetryMessage = null;

    _cleanupTempSubtitleFilesSync();
    _skipSegmentsFetchGeneration++;
    _skipSegmentProvider?.close();
    _skipSegmentProvider = null;
    _hideTimer?.cancel();
    _autosaveTimer?.cancel();
    _manualSelectionResetTimer?.cancel();
    _channelBadgeTimer?.cancel();
    _titleBadgeTimer?.cancel();
    _iptvZapHideTimer?.cancel();
    _iptvZapTicker?.cancel();
    _tvScrubGeneration++; // invalidate any scrub still in flight
    _tvBarScope.dispose();
    _tvPlayPauseFocus.dispose();
    _tvProgressFocus.dispose();
    _tvRootFocus.dispose();
    _controlsVisible.removeListener(_onControlsVisibilityChanged);
    _controlsVisible.dispose();
    _seekHud.dispose();
    _verticalHud.dispose();
    _speedHoldHud.dispose();
    _recordLogSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _lastLiveChannelTimer?.cancel();
    _paramsSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    _iptvErrorSub?.cancel();
    _bufferingDebounceTimer?.cancel();
    _showBufferingIndicator.dispose();
    _releaseAudioEffectSession();
    if (_playerCreated) _player.dispose();
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

  String get _resumeKey {
    if (_activePlaylist != null &&
        _activePlaylist!.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      final entry = _activePlaylist![_currentIndex];

      // Check for Torbox-specific key
      final torboxKey = _torboxResumeKeyForEntry(entry);
      if (torboxKey != null) {
        debugPrint(
          'ResumeKey: using torbox key $torboxKey for index $_currentIndex',
        );
        return torboxKey;
      }

      // Check for PikPak-specific key
      final pikpakKey = _pikpakResumeKeyForEntry(entry);
      if (pikpakKey != null) {
        debugPrint(
          'ResumeKey: using pikpak key $pikpakKey for index $_currentIndex',
        );
        return pikpakKey;
      }
    }

    // Use playlist-specific resume ID for other items
    if (_activePlaylist != null &&
        _activePlaylist!.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _activePlaylist!.length) {
      final id = _resumeIdForEntry(_activePlaylist![_currentIndex]);
      debugPrint(
        'ResumeKey: using playlist entry id $id for index $_currentIndex',
      );
      return id;
    }

    // IPTV launches carry no playlist, so the fallback below would key every
    // channel in the session to the URL the player was OPENED with — zap to
    // another channel and its position would be filed under the first one's
    // name. Key on the channel actually playing instead. (Identical to the
    // fallback until the user zaps, so existing resume points still resolve.)
    final iptvChannels = _effectiveIptvChannels;
    if (iptvChannels != null &&
        _currentIptvIndex >= 0 &&
        _currentIptvIndex < iptvChannels.length) {
      return iptvChannels[_currentIptvIndex].url;
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
        debugPrint(
          'ResumeKey: torbox web download detected web=$webDownloadId file=$fileId',
        );
        return 'torbox_web_${webDownloadId}_$fileId';
      }
      if (torrentId != null && fileId != null) {
        debugPrint(
          'ResumeKey: torbox entry detected torrent=$torrentId file=$fileId',
        );
        return 'torbox_${torrentId}_$fileId';
      }
      debugPrint(
        'ResumeKey: torbox entry missing IDs torrent=$torrentId web=$webDownloadId file=$fileId',
      );
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

  /// [preferLocalResume]: a source switch landed on the SAME content and
  /// checkpointed the live position — resume exactly there (any position, even
  /// past the 90% cutoff, matching the native TV player) and skip Trakt.
  /// Threaded as a parameter, not ambient state, so an early return or throw
  /// anywhere in the load path can never leak it into a later load.
  Future<void> _maybeRestoreResume({bool preferLocalResume = false}) async {
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
    // The launched item's widget percent is a first-load-only signal; capture it
    // before marking it spent so it can't apply to a later switched-to episode.
    final firstLoad = !_launchTraktPercentSpent;
    _launchTraktPercentSpent = true;
    final simklFirstLoad = !_launchSimklPercentSpent;
    _launchSimklPercentSpent = true;

    await _waitForDuration();
    final dur = _duration;

    // Trakt candidate (cross-device %), skipped for a source switch. Launched
    // item uses the widget percent (first load); a switched item uses its own
    // per-episode store percent. The widget percent is an EXPLICIT promise —
    // the details-screen Resume button advertised this position — so when
    // seekable it wins outright below (never silently overridden by local).
    double? traktPct;
    var explicitLaunch = false;
    if (!preferLocalResume) {
      final launchPct = firstLoad ? widget.traktProgressPercent : null;
      if (launchPct != null) {
        traktPct = launchPct;
        explicitLaunch = true;
      } else {
        traktPct = await _currentEpisodeTraktPercent();
      }
    }
    // Simkl candidate: the explicit launch promise on first load, otherwise
    // this episode's launch-time snapshot. Folded into the same candidate as
    // Trakt so the furthest remote progress wins.
    if (!preferLocalResume) {
      final explicitSimklPct = simklFirstLoad
          ? widget.simklProgressPercent
          : null;
      final simklPct = explicitSimklPct ?? await _currentEpisodeSimklPercent();
      if (simklPct != null && (traktPct == null || simklPct > traktPct)) {
        traktPct = simklPct;
        explicitLaunch = explicitSimklPct != null;
      }
    }
    final int traktMs =
        (traktPct != null &&
            traktPct > 0 &&
            traktPct < 100 &&
            dur > Duration.zero)
        ? (dur.inMilliseconds * traktPct / 100).floor()
        : 0;

    // Local candidate + speed/aspect restore (enhanced state preferred, else the
    // legacy resume store). Speed/aspect are restored regardless of the seek.
    int localMs = 0;
    final state =
        await _getEnhancedPlaybackState() ??
        await StorageService.getVideoResume(_resumeKey);
    if (state != null) {
      localMs = (state['positionMs'] ?? 0) as int;
      final speed = (state['speed'] ?? 1.0) as double;
      final aspect = (state['aspect'] ?? 'contain') as String;
      if (speed != 1.0) {
        await _player.setRate(speed);
        _playbackSpeed = speed;
      }
      _aspectMode = AspectModeUtils.stringToAspectMode(aspect);
    }

    if (dur <= Duration.zero) return;

    // Source switch on the same content: come back EXACTLY where you were —
    // no resumable-window gating (you might be 93% in, mid-credits), matching
    // the native TV player's source-switch semantics.
    if (preferLocalResume) {
      if (localMs > 0 && localMs < dur.inMilliseconds) {
        await _player.seek(Duration(milliseconds: localMs));
      }
      return;
    }

    final loMs =
        VideoPlayerTimingConstants.minimumPlaybackPosition.inMilliseconds;
    final hiMs = (dur.inMilliseconds * 0.9).floor();
    // The details-screen Resume promised THIS position — honour it outright when
    // seekable (matching the pre-rework launched-item behaviour), even over a
    // deeper/stale local. An unseekable promise falls through to furthest-wins.
    if (explicitLaunch && traktMs > loMs && traktMs < hiMs) {
      debugPrint('Resume: explicit launch Trakt percent -> ${traktMs}ms');
      await _player.seek(Duration(milliseconds: traktMs));
      return;
    }
    // FURTHEST-WATCHED WINS: seek the deeper of the local position and the Trakt
    // percent, provided it's in the resumable window (past the first 2s, before
    // the last 10%). If neither qualifies, start fresh.
    // Locally FINISHED (past the 90% cutoff on this device): start fresh, and
    // never let a shallower/stale Trakt percent yank a restarted episode into
    // its middle — local IS the furthest position, it's just not seekable.
    if (localMs >= hiMs && localMs > 0) return;
    final traktCand = (traktMs > loMs && traktMs < hiMs) ? traktMs : 0;
    final localCand = (localMs > loMs && localMs < hiMs) ? localMs : 0;
    final target = traktCand > localCand ? traktCand : localCand;
    if (target > 0) {
      debugPrint(
        'Resume: furthest of trakt=${traktMs}ms local=${localMs}ms -> ${target}ms',
      );
      await _player.seek(Duration(milliseconds: target));
    }
  }

  /// Get enhanced playback state for current content
  Future<Map<String, dynamic>?> _getEnhancedPlaybackState() async {
    try {
      final seriesPlaylist = _seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series, get the current episode info
        if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
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
        if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
          PlaylistEntry? currentEntry;
          if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
            currentEntry = _activePlaylist![_currentIndex];
          }

          if (currentEntry != null) {
            final resumeId = _resumeIdForEntry(currentEntry);
            debugPrint('Resume Load: fetching state for resumeId=$resumeId');
            final videoState = await StorageService.getVideoPlaybackState(
              videoTitle: resumeId,
            );
            if (videoState != null) {
              debugPrint(
                'Resume Load: found state for resumeId=$resumeId updatedAt=${videoState['updatedAt']}',
              );
              return videoState;
            }
          }
        }

        // Single video file (no playlist): if it's a series episode (e.g. a
        // direct-link/addon stream, or Quick Play next episode), the position
        // was saved under the season/episode-keyed series store, not here.
        if (_effectiveContentType == 'series' &&
            _effectiveContentSeason != null &&
            _effectiveContentEpisode != null) {
          final seriesState = await StorageService.getSeriesPlaybackState(
            seriesTitle: _effectiveContentTitle ?? widget.title,
            season: _effectiveContentSeason!,
            episode: _effectiveContentEpisode!,
          );
          if (seriesState != null) {
            return seriesState;
          }
        }

        // A direct-link/addon movie stream's title varies per search (quality
        // tag, mirror, reordered results), so the title-keyed lookup below can
        // miss even though it's the same movie. Prefer the stable
        // imdbId-keyed record when one exists.
        final movieImdbId = _effectiveContentImdbId;
        if (_effectiveContentType != 'series' &&
            movieImdbId != null &&
            movieImdbId.isNotEmpty) {
          final byImdbId = await StorageService.getVideoPlaybackStateByImdbId(
            movieImdbId,
          );
          if (byImdbId != null) {
            return byImdbId;
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

    // An IPTV zap flips _currentIptvIndex — and therefore _resumeKey — before
    // the incoming stream opens, while _position/_duration still describe the
    // OUTGOING one (_isReady is never cleared for the gap). A tick landing in
    // that window would file the old movie's position under the new channel's
    // key, which the Continue-watching shelf would then show as real progress.
    // Nothing is lost by skipping: the next tick saves once the switch lands.
    if (_effectiveIptvChannels != null && _isTransitioning) {
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
    // While the user is holding for temporary 2x boost, persist the prior speed
    // so a kill/dispose mid-hold doesn't strand 2x as the resume value.
    final persistedSpeed = _speedBeforeHold ?? _playbackSpeed;

    // Save to enhanced playback state system
    try {
      final seriesPlaylist = _seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content
        if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
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
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId,
            );
          }
        }
      } else {
        // For non-series content
        if (_activePlaylist != null && _activePlaylist!.isNotEmpty) {
          PlaylistEntry? currentEntry;
          if (_currentIndex >= 0 && _currentIndex < _activePlaylist!.length) {
            currentEntry = _activePlaylist![_currentIndex];
          }

          if (currentEntry != null) {
            final resumeId = _resumeIdForEntry(currentEntry);
            debugPrint(
              'Resume Save: storing state resumeId=$resumeId pos=${pos.inMilliseconds} dur=${dur.inMilliseconds}',
            );
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
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: widget.contentImdbId,
            );

            // ALSO save in collection format for playlist progress tracking
            // This allows the playlist screen to display progress indicators
            debugPrint(
              '💾 Collection Save Check: seriesPlaylist=${seriesPlaylist != null}, seriesTitle="${seriesPlaylist?.seriesTitle}", isSeries=${seriesPlaylist?.isSeries}',
            );
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
                speed: persistedSpeed,
                aspect: aspectStr,
                imdbId: seriesPlaylist.imdbId ?? widget.contentImdbId,
              );
              debugPrint(
                '✅ Collection Save: title="${seriesPlaylist.seriesTitle}" S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} (index=${_currentIndex}) filename="${currentEntry.title}"',
              );
            } else {
              debugPrint(
                '❌ Collection Save SKIPPED: seriesPlaylist is null or has no title',
              );
            }
          }
        } else {
          // Single video file (no playlist)
          // If it's a series episode (from Quick Play next episode), save as series state
          if (_effectiveContentType == 'series' &&
              _effectiveContentSeason != null &&
              _effectiveContentEpisode != null) {
            await StorageService.saveSeriesPlaybackState(
              seriesTitle: _effectiveContentTitle ?? widget.title,
              season: _effectiveContentSeason!,
              episode: _effectiveContentEpisode!,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: _effectiveContentImdbId,
            );
          } else {
            final currentUrl =
                (_currentStreamUrl != null && _currentStreamUrl!.isNotEmpty)
                ? _currentStreamUrl!
                : widget.videoUrl;
            final title = _currentStremioTvContentTitle ?? widget.title;
            final videoTitle = title.isNotEmpty ? title : 'Unknown Video';

            await StorageService.saveVideoPlaybackState(
              videoTitle: videoTitle,
              videoUrl: currentUrl,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: _effectiveContentImdbId,
            );
          }
        }
      }
    } catch (e) {}

    // Also save to legacy system for backward compatibility
    await StorageService.upsertVideoResume(_resumeKey, {
      'positionMs': pos.inMilliseconds,
      'speed': persistedSpeed,
      'aspect': aspectStr,
      'durationMs': dur.inMilliseconds,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

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
      if (!_tvBarScope.hasFocus) _tvPlayPauseFocus.requestFocus();
    });
  }

  /// Lower the bar and take focus back to the player root. Without the second
  /// half the focused control is excluded from the tree and the remote dies.
  void _tvHideBar() {
    _controlsVisible.value = false;
    _tvRootFocus.requestFocus();
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
    _traktScrobbleSeek(target);
    _simklScrobbleSeek(target);
    if (_tvScrubWasPlaying) _player.play();
    _tvPlayPauseFocus.requestFocus();
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
    _tvPlayPauseFocus.requestFocus();
    _scheduleAutoHide();
  }

  /// The television bar. Reuses every flag the touch call site already
  /// computes, so the two stay in step: live comes from the same
  /// zap-banner signal, sources/guide/record from the same capability checks.
  Widget _buildTvControls(Duration duration, Duration pos) {
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
      canPop: _tvScrubTarget == null &&
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
        _traktScrobbleSeek(target);
        _simklScrobbleSeek(target);
        _scheduleAutoHide();
      },
      child: TvControls(
        title: widget.showVideoTitle && !widget.showChannelName
            ? _getCurrentEpisodeTitle()
            : '',
        subtitle: widget.showVideoTitle && !widget.showChannelName
            ? _getCurrentEpisodeSubtitle()
            : null,
        infoPanel: _buildIptvInfoPanel(flush: true),
        duration: duration,
        position: pos,
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
        onShowTracks: () => _showTracksSheet(context),
        onSpeed: _changeSpeed,
        onAspect: _cycleAspectMode,
        onSleepTimer: _showSleepTimerSheet,
        sleepTimerLabel: _sleepTimerButtonLabel,
        speed: _playbackSpeed,
        aspectMode: _aspectMode,
        hideOptions: widget.hideOptions,
        onNext: _hasIptvNext
            ? () => _switchToIptvChannel(_currentIptvIndex + 1)
            : _canZapIptvChannel
            ? () => _zapIptvChannel(1)
            : (_hasAnyNext ? _goToNextEpisode : null),
        onPrevious: _hasIptvPrevious
            ? () => _switchToIptvChannel(_currentIptvIndex - 1)
            : _canZapIptvChannel
            ? () => _zapIptvChannel(-1)
            : (_hasPreviousEpisode() ? _goToPreviousEpisode : null),
        onNextChannel:
            widget.requestNextChannel != null ? _goToNextChannel : null,
        onShowPlaylist: _activePlaylist != null && _activePlaylist!.isNotEmpty
            ? () => _showPlaylistSheet(context)
            : null,
        onShowSources: hasSources ? _showSourceSheetOverlay : null,
        onShowGuide: hasGuide
            ? (_channelEntries.isNotEmpty && widget.requestChannelById != null
                  ? _showChannelGuideOverlay
                  : _showStremioTvGuideOverlay)
            : null,
        onShowIptvChannels: _effectiveIptvChannels?.isNotEmpty == true
            ? _showIptvChannelSheetOverlay
            : null,
        hasRecord: _canRecord,
        isRecording: _recordingActiveNow,
        onRecord: _canRecord ? _toggleRecording : null,
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
      _showStremioTvGuide;

  /// Closes the topmost overlay and returns focus to the player root, which the
  /// individual hide methods do not do on their own.
  void _closeTopPlayerOverlay() {
    if (_showSyncOverlay) {
      _hideSyncOverlay();
    } else if (_showChannelGuide) {
      _hideChannelGuideOverlay();
    } else if (_showIptvChannelSheet) {
      // Delegate: the guide's own back walks schedule -> channels first, and
      // its close restores a search-interrupted category.
      if (_iptvSheetKey.currentState?.handleHostBack() != true) {
        _hideIptvChannelSheet();
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
      _showIptvChannelSheetOverlay();
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
      if ((isLeft || isRight) && _canZapIptvChannel) {
        _zapIptvChannel(isRight ? 1 : -1);
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
        return _canZapIptvChannel ? null : KeyEventResult.handled;
      }
      if ((isLeft || isRight) && !_canZapIptvChannel) {
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
      // Live IPTV keeps its identity in the banner — already dismissed by the
      // visibility listener above — so the corner badges stay down.
      if (_iptvZapBannerOwnsIdentity) return;
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
    _channelBadgeTimer = Timer(
      VideoPlayerTimingConstants.badgeDisplayDuration,
      () {
        if (mounted) {
          setState(() {
            _showChannelBadge = false;
          });
        }
      },
    );
  }

  /// Adopt [channel] as the banner's subject and start its guide lookup.
  ///
  /// Called on the first tune and on every zap, whatever is on screen at the
  /// time: the dock can be opened minutes later and must find the panel's
  /// data already loaded.
  void _prepareIptvBannerData(IptvChannel channel) {
    if (!mounted || !channel.isLive) return;
    final ticket = ++_iptvZapEpgTicket;
    // Whatever the guide already knows paints immediately; the fetch below
    // only ever upgrades it.
    final known = IptvEpgService.instance.peekNowNext(channel.url);
    setState(() {
      _iptvZapChannel = channel;
      _iptvZapEpg = known;
      _iptvZapEpgLoading = known == null;
      _iptvZapClock = DateTime.now();
    });
    if (known == null) unawaited(_loadIptvZapBannerEpg(channel, ticket));
    // Zapping from VOD to live with the dock already open gives the panel its
    // first channel here rather than at raise time — start its clock.
    _syncIptvBannerTicker();
  }

  /// Float the banner over bare video and let it fade itself out.
  void _raiseIptvZapBanner() {
    if (!mounted || _iptvZapChannel == null) return;
    // Anything the user deliberately opened keeps the frame. The dock is the
    // exception it used to share this strip with: it now carries the same
    // panel itself, so there is nothing to raise over it.
    if (_showIptvChannelSheet ||
        _showSourceSheet ||
        _showChannelGuide ||
        _controlsVisible.value) {
      return;
    }
    setState(() {
      _showIptvZapBanner = true;
      _iptvZapFloatingMounted = true;
    });
    _iptvZapHideTimer?.cancel();
    _iptvZapHideTimer = Timer(
      const Duration(milliseconds: 4500),
      _hideIptvZapBanner,
    );
    _syncIptvBannerTicker();
  }

  void _onControlsVisibilityChanged() {
    // The dock carries its own copy of the panel, so the floating one goes the
    // instant the dock opens. Fading it would cross-dissolve two copies of the
    // same panel at two different heights.
    if (_controlsVisible.value) {
      _hideIptvZapBanner(immediate: true);
      // The Record button is about to be looked at — make sure it reflects
      // engine captures stopped from the notification (which this screen
      // otherwise never hears about).
      if (_engineFlagOn) unawaited(_refreshEngineRecordingState());
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
    _syncIptvBannerTicker();
  }

  /// [immediate] skips the fade and unmounts in the same frame — for a handoff
  /// to the dock's copy, where a fade would show both at once.
  void _hideIptvZapBanner({bool immediate = false}) {
    _iptvZapHideTimer?.cancel();
    _iptvZapHideTimer = null;
    final live = _showIptvZapBanner || (immediate && _iptvZapFloatingMounted);
    if (mounted && live) {
      setState(() {
        _showIptvZapBanner = false;
        if (immediate) _iptvZapFloatingMounted = false;
      });
    }
    _syncIptvBannerTicker();
  }

  /// The panel's clock only has to run while the panel is on screen — in
  /// either home. Without it the countdown and the elapsed rule sit frozen,
  /// which is most obvious exactly where the dock is used: while paused,
  /// where the position stream has stopped driving rebuilds.
  void _syncIptvBannerTicker() {
    final onScreen =
        _iptvZapChannel != null &&
        (_showIptvZapBanner ||
            (_controlsVisible.value && _iptvZapBannerOwnsIdentity));
    if (!onScreen) {
      _iptvZapTicker?.cancel();
      _iptvZapTicker = null;
      return;
    }
    if (_iptvZapTicker != null) return;
    _iptvZapTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _iptvZapClock = DateTime.now());
      _refreshIptvBannerEpgIfEnded();
    });
  }

  /// The dock can stay open past the end of the programme it is describing.
  /// Re-ask once the current one has finished rather than leave a listing
  /// that is quietly wrong.
  void _refreshIptvBannerEpgIfEnded() {
    if (_iptvZapEpgLoading) return;
    final channel = _iptvZapChannel;
    final current = _iptvZapEpg?.now;
    if (channel == null || current == null) return;
    if (current.stop.isAfter(DateTime.now())) return;
    final ticket = ++_iptvZapEpgTicket;
    setState(() => _iptvZapEpgLoading = true);
    unawaited(_loadIptvZapBannerEpg(channel, ticket));
  }

  /// The same lazy now/next fetch the guide rows use. [ticket] is the banner's
  /// generation: a zap that lands mid-flight owns the banner, so a late answer
  /// for the previous channel is dropped rather than painted under the new
  /// channel's name.
  Future<void> _loadIptvZapBannerEpg(IptvChannel channel, int ticket) async {
    EpgNowNext? result;
    try {
      result = await IptvEpgService.instance.nowNext(channel.url);
    } catch (_) {
      result = null;
    }
    if (!mounted || ticket != _iptvZapEpgTicket) return;
    setState(() {
      _iptvZapEpg = result;
      _iptvZapEpgLoading = false;
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
    _titleBadgeTimer = Timer(
      VideoPlayerTimingConstants.badgeDisplayDuration,
      () {
        if (mounted) {
          setState(() {
            _showTitleBadge = false;
          });
        }
      },
    );
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
    _traktScrobbleSeek(clamped);
    _simklScrobbleSeek(clamped);
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
      _traktScrobbleSeek(target);
      _simklScrobbleSeek(target);
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
      // An explicit press is the one thing that clears a sleep stop.
      _sleepStopLatched = false;
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
    _hideTimer?.cancel();
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
    _scheduleAutoHide();
    if (picked == null) return;

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
    if (!_playerCreated) return;
    await _saveResume();
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

  void _changeSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final idx = speeds.indexOf(_playbackSpeed);
    final next = speeds[(idx + 1) % speeds.length];
    _player.setRate(next);
    setState(() => _playbackSpeed = next);
    _scheduleAutoHide();
    _saveResume();
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
        const bottomBar = 72.0;
        if (localPos.dy < topBar || localPos.dy > size.height - bottomBar) {
          return;
        }
      }
    }
    _speedBeforeHold = _playbackSpeed;
    _player.setRate(2.0);
    setState(() => _playbackSpeed = 2.0);
    _speedHoldHud.value = true;
    HapticFeedback.mediumImpact();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final prior = _speedBeforeHold;
    if (prior == null) return;
    _speedBeforeHold = null;
    if (!mounted) return;
    _player.setRate(prior);
    setState(() => _playbackSpeed = prior);
    _speedHoldHud.value = false;
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
  // NOTE: the television bar deliberately does NOT move subtitles.
  //
  // Two attempts made things worse: driving mpv's `sub-visibility` drew every
  // line twice (media_kit renders subtitles itself and keeps mpv's own
  // renderer off), and padding them upward fought the user's own subtitle
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

  Widget _buildChannelBadge(String badgeText) =>
      ChannelBadge(badgeText: badgeText);

  Widget _buildTitleBadge(String title) => TitleBadge(title: title);

  /// One truth for "is this playback being recorded right now", shared by
  /// the dock's Record button and the styled zap banner's REC tag — the
  /// three mechanisms are libmpv stream-record, the Android recording
  /// engine, and the desktop capture process.
  bool get _recordingActiveNow =>
      _isRecording ||
      _engineTaskId != null ||
      _desktopCaptureForCurrent() != null;

  /// The live-IPTV panel, or null when this playback has no channel identity
  /// to present. [flush] embeds it in the controls dock; otherwise it floats.
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
      isRecording: _recordingActiveNow,
    );
  }

  // Get the custom aspect ratio for specific modes
  double? _getCustomAspectRatio() =>
      AspectModeUtils.getAspectRatioValue(_aspectMode);

  Future<void> _showPlaylistSheet(BuildContext context) async {
    await PlaylistSheet.show(
      context,
      playlist: _activePlaylist ?? const [],
      currentIndex: _currentIndex,
      seriesPlaylist: _seriesPlaylist,
      playlistItemData: _constructPlaylistItemData(),
      imdbId: widget.contentImdbId,
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
    final activeSkipSegment = _activeSkipSegment;
    final String? channelBadgeText = _channelBadgeText;
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
              _cycleAspectMode();
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
                _showIptvChannelSheetOverlay();
                return KeyEventResult.handled;
              }
            }

            // C -> IPTV channel sheet
            if (key == LogicalKeyboardKey.keyC) {
              if (_effectiveIptvChannels?.isNotEmpty == true) {
                _showIptvChannelSheetOverlay();
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
            if (_canZapIptvChannel && !_controlsVisible.value) {
              if (key == LogicalKeyboardKey.arrowRight) {
                _zapIptvChannel(1);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowLeft) {
                _zapIptvChannel(-1);
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
              _traktScrobbleSeek(newPos);
              _simklScrobbleSeek(newPos);
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
              _traktScrobbleSeek(newPos);
              _simklScrobbleSeek(newPos);
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
              if (_canZapIptvChannel) {
                _zapIptvChannel(1);
                return KeyEventResult.handled;
              }
              if (widget.requestNextChannel != null) {
                _goToNextChannel();
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.channelDown ||
                key == LogicalKeyboardKey.pageDown) {
              if (_canZapIptvChannel) {
                _zapIptvChannel(-1);
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
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
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
                // Buffering indicator (OTT-style centered spinner)
                ValueListenableBuilder<bool>(
                  valueListenable: _showBufferingIndicator,
                  builder: (context, show, _) {
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
                      )) {
                        _toggleControls();
                      }
                    },
                    onDoubleTapDown: _handleDoubleTap,
                    onLongPressStart: _onLongPressStart,
                    onLongPressEnd: _onLongPressEnd,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                  ),
                // Controls overlay (shown only when ready)
                if (isReady && !inPip)
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
                                  child: _buildTvControls(duration, pos),
                                )
                              : Controls(
                            // Live IPTV leaves the top bar empty on purpose:
                            // its identity is in the info panel below, and
                            // repeating the channel in both corners is the
                            // duplication this redesign set out to remove.
                            title:
                                widget.showVideoTitle && !widget.showChannelName
                                ? _getCurrentEpisodeTitle()
                                : '',
                            subtitle:
                                widget.showVideoTitle && !widget.showChannelName
                                ? _getCurrentEpisodeSubtitle()
                                : null,
                            // Merged into the dock: the channel panel rides on
                            // top of the transport bar as one surface.
                            infoPanel: _buildIptvInfoPanel(flush: true),
                            enhancedMetadata: _getEnhancedMetadata(),
                            duration: duration,
                            position: pos,
                            isPlaying: _isPlaying,
                            isReady: isReady,
                            onPlayPause: _togglePlay,
                            onBack: () => Navigator.of(context).pop(),
                            onAspect: _cycleAspectMode,
                            onSpeed: _changeSpeed,
                            onSleepTimer: _showSleepTimerSheet,
                            sleepTimerLabel: _sleepTimerButtonLabel,
                            speed: _playbackSpeed,
                            aspectMode: _aspectMode,
                            isLandscape: _landscapeLocked,
                            onRotate: _toggleOrientation,
                            hasPlaylist:
                                _activePlaylist != null &&
                                _activePlaylist!.isNotEmpty,
                            onShowPlaylist: () => _showPlaylistSheet(context),
                            onShowTracks: () => _showTracksSheet(context),
                            onSeekBarChangedStart: () {
                              _isSeekingWithSlider = true;
                            },
                            onSeekBarChanged: (v) {
                              final newPos = duration * v;
                              _player.seek(newPos);
                              _lastSliderSeekPos = newPos;
                            },
                            onSeekBarChangeEnd: () {
                              _isSeekingWithSlider = false;
                              _scheduleAutoHide();
                              if (_lastSliderSeekPos != null) {
                                _traktScrobbleSeek(_lastSliderSeekPos!);
                                _simklScrobbleSeek(_lastSliderSeekPos!);
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
                                : _canZapIptvChannel
                                ? () => _zapIptvChannel(1)
                                : (_hasAnyNext ? _goToNextEpisode : null),
                            onNextChannel: widget.requestNextChannel != null
                                ? _goToNextChannel
                                : null,
                            onPrevious: _hasIptvPrevious
                                ? () => _switchToIptvChannel(
                                    _currentIptvIndex - 1,
                                  )
                                : _canZapIptvChannel
                                ? () => _zapIptvChannel(-1)
                                : (_hasPreviousEpisode()
                                      ? _goToPreviousEpisode
                                      : null),
                            hasNext:
                                _hasAnyNext ||
                                _hasIptvNext ||
                                _canZapIptvChannel,
                            hasNextChannel: widget.requestNextChannel != null,
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
                                _canZapIptvChannel,
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
                                _effectiveIptvChannels?.isNotEmpty == true,
                            onShowIptvChannels:
                                _effectiveIptvChannels?.isNotEmpty == true
                                ? _showIptvChannelSheetOverlay
                                : null,
                            hasStremioSources:
                                _effectiveSources != null &&
                                _effectiveSources!.isNotEmpty &&
                                (_effectiveResolver != null ||
                                    widget.resolveSourceToPlaylist != null),
                            onShowStremioSources:
                                _effectiveSources != null &&
                                    _effectiveSources!.isNotEmpty &&
                                    (_effectiveResolver != null ||
                                        widget.resolveSourceToPlaylist != null)
                                ? _showSourceSheetOverlay
                                : null,
                            showPipButton: PipService.isOwner(this),
                            onPip: PipService.isOwner(this) ? _enterPip : null,
                            hasRecord: _canRecord,
                            isRecording: _recordingActiveNow,
                            onRecord: _canRecord ? _toggleRecording : null,
                          ),
                        ),
                      );
                    },
                  ),
                // Manual OTT-style skip action. It stays available even when
                // the main controls are hidden, and lifts above the dock when
                // they are visible so neither control intercepts the other.
                if (activeSkipSegment != null && !inPip)
                  ValueListenableBuilder<bool>(
                    valueListenable: _controlsVisible,
                    builder: (context, controlsVisible, _) {
                      return AnimatedPositioned(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        right: 24,
                        bottom: controlsVisible &&
                                (PlatformUtil.isTelevision ||
                                    !widget.hideOptions)
                            ? 160
                            : 28,
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
                  ),
                // Title Badge with Glassy Blur Effect (top-left, Debrify TV only)
                // Placed after controls to appear on top
                if (widget.showVideoTitle &&
                    widget.showChannelName &&
                    !_iptvZapBannerOwnsIdentity &&
                    !inPip)
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
                    channelBadgeText.isNotEmpty &&
                    !_iptvZapBannerOwnsIdentity &&
                    !inPip)
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
                  PikPakRetryOverlay(message: _pikPakRetryMessage!),
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
                      onChannelSelected: _switchToIptvGuideChannel,
                      onPlayProgramme: _playIptvCatchup,
                      onClose: _hideIptvChannelSheet,
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
                      onContextChanged: _persistIptvGuideContext,
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
      _showStremioTvGuide;

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
    final contentTitle = widget.contentTitle;
    if (contentTitle != null && contentTitle.trim().isNotEmpty) {
      return contentTitle;
    }
    return widget.title;
  }

  String _identitySearchInitialQuery() {
    final rawTitle = _currentPlaybackTitleForIdentity();
    final seriesInfo = SeriesParser.parseFilename(rawTitle);
    final seriesTitle = seriesInfo.title?.trim();
    if (seriesInfo.isSeries && seriesTitle != null && seriesTitle.isNotEmpty) {
      return seriesTitle;
    }

    final movieInfo = MovieParser.parseFilename(rawTitle);
    final movieTitle = movieInfo.title?.trim();
    if (movieTitle != null && movieTitle.isNotEmpty) {
      return movieTitle;
    }

    return rawTitle
        .replaceAll(
          RegExp(
            r'\.(mkv|mp4|avi|mov|wmv|flv|webm|m4v|ts|mpg|mpeg)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalisedContentType(String type) =>
      type.toLowerCase() == 'series' ? 'series' : 'movie';

  String? _subtitleIdentityLabelForSheet() {
    final manualLabel = _manualSubtitleDisplayLabel?.trim();
    if (manualLabel != null && manualLabel.isNotEmpty) {
      return 'Subtitles for $manualLabel';
    }

    final detectedTitle = _identitySearchInitialQuery();
    if (detectedTitle.isEmpty) return null;
    return 'Detected: $detectedTitle';
  }

  String _subtitleSearchDisplayLabel(
    StremioMeta meta, {
    required String contentType,
    int? season,
    int? episode,
  }) {
    final year = meta.year?.trim();
    final title = year != null && year.isNotEmpty
        ? '${meta.name} ($year)'
        : meta.name;
    if (contentType == 'series' && season != null && episode != null) {
      return '$title S${season}E$episode';
    }
    return title;
  }

  List<StremioMeta> _filterIdentitySearchResults(List<StremioMeta> metas) {
    final bestByKey = <String, StremioMeta>{};

    for (final meta in metas) {
      final imdbId = meta.effectiveImdbId;
      if (imdbId == null || !imdbId.startsWith('tt')) continue;

      final type = meta.type.toLowerCase();
      if (type != 'movie' && type != 'series') continue;

      final key = '$type:$imdbId';
      final existing = bestByKey[key];
      if (existing == null) {
        bestByKey[key] = meta;
        continue;
      }

      final existingScore =
          (existing.poster != null ? 2 : 0) + (existing.year != null ? 1 : 0);
      final newScore =
          (meta.poster != null ? 2 : 0) + (meta.year != null ? 1 : 0);
      if (newScore > existingScore) {
        bestByKey[key] = meta;
      }
    }

    return bestByKey.values.toList(growable: false);
  }

  String? _normalisePosterUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  String _identityMetaSubtitle(StremioMeta meta) {
    final parts = <String>[
      meta.type.toLowerCase() == 'series' ? 'Series' : 'Movie',
      if (meta.year != null && meta.year!.trim().isNotEmpty) meta.year!,
      if (meta.sourceAddon?.name.trim().isNotEmpty == true)
        meta.sourceAddon!.name,
    ];
    return parts.join(' | ');
  }

  Widget _buildIdentifyTitleResultTile(StremioMeta meta) {
    final posterUrl = _normalisePosterUrl(meta.poster);

    return InkWell(
      onTap: () => Navigator.of(context).pop(meta),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 46,
                height: 68,
                color: Colors.white.withValues(alpha: 0.08),
                child: posterUrl == null
                    ? Icon(
                        Icons.movie_creation_outlined,
                        color: Colors.white.withValues(alpha: 0.45),
                      )
                    : Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.movie_creation_outlined,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _identityMetaSubtitle(meta),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<StremioMeta?> _showIdentifyTitleSearchSheet({
    required String initialQuery,
  }) async {
    if (!mounted) return null;

    final controller = TextEditingController(text: initialQuery);
    var results = <StremioMeta>[];
    var isSearching = false;
    var hasSearched = false;
    String? errorMessage;
    var searchToken = 0;
    var sheetActive = true;

    Future<void> runSearch(String rawQuery, StateSetter setSheetState) async {
      final query = rawQuery.trim();
      final token = ++searchToken;

      if (query.isEmpty) {
        setSheetState(() {
          results = [];
          errorMessage = null;
          isSearching = false;
          hasSearched = false;
        });
        return;
      }

      setSheetState(() {
        isSearching = true;
        errorMessage = null;
        hasSearched = true;
      });

      try {
        final metas = await StremioService.instance.searchCatalogs(query);
        if (!sheetActive || !mounted || token != searchToken) return;
        setSheetState(() {
          results = _filterIdentitySearchResults(metas);
          isSearching = false;
        });
      } catch (e) {
        if (!sheetActive || !mounted || token != searchToken) return;
        setSheetState(() {
          results = [];
          errorMessage = 'Search failed. Try again.';
          isSearching = false;
        });
      }
    }

    final selected =
        await showModalBottomSheet<StremioMeta>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) {
            var initialSearchStarted = false;
            return StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                if (!initialSearchStarted && initialQuery.trim().isNotEmpty) {
                  initialSearchStarted = true;
                  Future(() => runSearch(initialQuery, setSheetState));
                }

                final screenSize = MediaQuery.of(sheetContext).size;
                final sheetHeight = screenSize.height * 0.82;

                return Container(
                  height: sheetHeight,
                  decoration: const BoxDecoration(
                    color: Color(0xFF141414),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search_rounded,
                              color: VideoPlayerColors.netflixRed,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Search Subtitle',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              color: Colors.white70,
                              onPressed: () => Navigator.of(sheetContext).pop(),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: TvTextField(
                          controller: controller,
                          autofocus: initialQuery.trim().isEmpty,
                          onSubmitted: (value) =>
                              runSearch(value, setSheetState),
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search movie or show',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.arrow_forward_rounded),
                              color: VideoPlayerColors.netflixRed,
                              onPressed: () =>
                                  runSearch(controller.text, setSheetState),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Builder(
                          builder: (_) {
                            if (isSearching) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: VideoPlayerColors.netflixRed,
                                ),
                              );
                            }

                            if (errorMessage != null) {
                              return Center(
                                child: Text(
                                  errorMessage!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            }

                            if (hasSearched && results.isEmpty) {
                              return Center(
                                child: Text(
                                  'No IMDb-backed results found',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: results.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                              itemBuilder: (_, index) =>
                                  _buildIdentifyTitleResultTile(results[index]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ).whenComplete(() {
          sheetActive = false;
        });

    controller.dispose();
    return selected;
  }

  _SeasonEpisodeSelection? _currentSeasonEpisodeForIdentity() {
    final seriesPlaylist = _seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final currentEp = _findSeriesEpisodeForCurrentIndex(seriesPlaylist);
      final season = currentEp?.seriesInfo.season;
      final episode = currentEp?.seriesInfo.episode;
      if (season != null && episode != null) {
        return _SeasonEpisodeSelection(season: season, episode: episode);
      }
    }

    final seriesInfo = SeriesParser.parseFilename(
      _currentPlaybackTitleForIdentity(),
    );
    final season =
        seriesInfo.season ??
        _manualContentSeason ??
        _currentStremioTvContentSeason ??
        widget.contentSeason;
    final episode =
        seriesInfo.episode ??
        _manualContentEpisode ??
        _currentStremioTvContentEpisode ??
        widget.contentEpisode;

    if (season == null || episode == null) return null;
    return _SeasonEpisodeSelection(season: season, episode: episode);
  }

  Future<_SeasonEpisodeSelection?> _requestSeasonEpisodeForIdentity(
    String title,
  ) async {
    if (!mounted) return null;

    final seasonController = TextEditingController();
    final episodeController = TextEditingController();
    String? errorText;

    final result = await showDialog<_SeasonEpisodeSelection>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              title: const Text(
                'Episode',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TvTextField(
                          controller: seasonController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Season',
                            labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TvTextField(
                          controller: episodeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Episode',
                            labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: VideoPlayerColors.netflixRed,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final season = int.tryParse(seasonController.text.trim());
                    final episode = int.tryParse(episodeController.text.trim());
                    if (season == null ||
                        season <= 0 ||
                        episode == null ||
                        episode <= 0) {
                      setDialogState(() {
                        errorText = 'Enter a valid season and episode.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _SeasonEpisodeSelection(season: season, episode: episode),
                    );
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    seasonController.dispose();
    episodeController.dispose();
    return result;
  }

  Future<TracksSheetSubtitleSearchResult?>
  _identifyTitleAndFetchSubtitles() async {
    final identifyToken = _addonSubtitleFetchToken;
    final selected = await _showIdentifyTitleSearchSheet(
      initialQuery: _identitySearchInitialQuery(),
    );
    if (!mounted ||
        selected == null ||
        identifyToken != _addonSubtitleFetchToken) {
      return null;
    }

    final imdbId = selected.effectiveImdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected title has no IMDb ID')),
      );
      return null;
    }

    final contentType = _normalisedContentType(selected.type);
    int? season;
    int? episode;

    if (contentType == 'series') {
      final currentEpisode = _currentSeasonEpisodeForIdentity();
      season = currentEpisode?.season;
      episode = currentEpisode?.episode;

      if (season == null || episode == null) {
        final entered = await _requestSeasonEpisodeForIdentity(selected.name);
        if (!mounted ||
            entered == null ||
            identifyToken != _addonSubtitleFetchToken) {
          return null;
        }
        season = entered.season;
        episode = entered.episode;
      }
    }

    final subtitleDisplayLabel = _subtitleSearchDisplayLabel(
      selected,
      contentType: contentType,
      season: season,
      episode: episode,
    );

    final fetchToken = _addonSubtitleFetchToken + 1;
    setState(() {
      _addonSubtitleFetchToken = fetchToken;
      _manualContentImdbId = imdbId;
      _manualContentType = contentType;
      _manualContentSeason = contentType == 'series' ? season : null;
      _manualContentEpisode = contentType == 'series' ? episode : null;
      _manualSubtitleDisplayLabel = subtitleDisplayLabel;
      _selectedStremioSubtitleId = null;
      _embeddedSubtitleApplied = false;
      _userManuallySelectedSubtitle = false;
      _cachedStremioSubtitles = null;
      _cachedAddonSlots = null;
      _cachedSubtitleKey = null;
    });

    try {
      final slots = await StremioSubtitleService.instance.fetchSubtitleSlots(
        type: contentType,
        imdbId: imdbId,
        season: contentType == 'series' ? season : null,
        episode: contentType == 'series' ? episode : null,
      );
      final subtitles = AddonSubtitleSlot.flatten(slots);

      if (!mounted || fetchToken != _addonSubtitleFetchToken) return null;

      final cacheKey =
          contentType == 'series' && season != null && episode != null
          ? '$imdbId:$season:$episode'
          : imdbId;

      _cachedStremioSubtitles = subtitles;
      _cachedAddonSlots = slots;
      _cachedSubtitleKey = cacheKey;

      await _fetchAndMaybeAutoSelectAddonSubtitle();

      if (subtitles.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No online subtitles found for this title'),
          ),
        );
      }

      return TracksSheetSubtitleSearchResult(
        subtitles: subtitles,
        slots: slots,
        selectedSubtitleId: _selectedStremioSubtitleId,
        identityLabel: 'Subtitles for $subtitleDisplayLabel',
        imdbId: imdbId,
        contentType: contentType,
        season: contentType == 'series' ? season : null,
        episode: contentType == 'series' ? episode : null,
      );
    } catch (e) {
      debugPrint('VideoPlayer: Search subtitle fetch failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Subtitle search failed')));
      }
      return null;
    }
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
    await TracksSheet.show(
      context,
      _player,
      onTrackChanged: (audioId, subtitleId) async {
        _userManuallySelectedSubtitle = true;
        if (!subtitleId.startsWith('stremio:')) {
          _activeExternalSubtitlePath = null;
        }
        // Remember the chosen audio language for this IPTV series (carries to
        // later episodes and future sessions). No-op off IPTV.
        _captureIptvAudioLanguage(audioId);
        await _persistTrackChoice(audioId, subtitleId);
      },
      // Fires only on a genuine subtitle switch (not audio, not re-select, not a
      // failed load): the sync offset was calibrated for the previous subtitle.
      onSubtitleTrackChanged: _resetSubtitleSyncOffset,
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
      onStremioSubtitleSelected: (id) {
        _selectedStremioSubtitleId = id;
        _userManuallySelectedSubtitle = true;
      },
      onDownloadStremioSubtitleToFile: _downloadStremioSubtitleToTempFile,
      onIdentifyTitle: _identifyTitleAndFetchSubtitles,
      subtitleIdentityLabel: _subtitleIdentityLabelForSheet(),
    );
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
    _userManuallySelectedSubtitle = false;
    _trackPreferencesReadyForAddonSubtitles = false;
    _addonSubtitleFetchToken++;
    _cleanupTempSubtitleFilesSync();
    _activeExternalSubtitlePath = null;
    _showSyncOverlay = false;
    // Content changed: the previous item's sync offset no longer applies.
    _resetSubtitleSyncOffset();
  }

  /// Restore audio and subtitle track preferences
  Future<void> _restoreTrackPreferences() async {
    // Capture token to detect if content changes during async operations
    final restoreToken = _addonSubtitleFetchToken;

    try {
      debugPrint(
        'SubAuto: _restoreTrackPreferences entered (token=$restoreToken)',
      );
      // Wait for subtitle tracks to be parsed from the media file
      // media_kit initially only has 'auto' and 'no' placeholder tracks
      await _waitForSubtitleTracks(token: restoreToken);

      if (restoreToken != _addonSubtitleFetchToken) {
        debugPrint(
          'SubAuto: restore aborted after track wait (content changed)',
        );
        return;
      }

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

      // Bail out if content changed during preferences fetch
      if (restoreToken != _addonSubtitleFetchToken) {
        debugPrint(
          'SubAuto: restore aborted (content changed during prefs fetch)',
        );
        return;
      }

      final subTracksNow = _player.state.tracks.subtitle
          .map((t) => '${t.id}/${t.language}/${t.title}')
          .toList();
      debugPrint(
        'SubAuto: restore start — prefs=${trackPreferences == null ? 'NONE' : trackPreferences.toString()} '
        'subtitleTracks=$subTracksNow currentSub=${_player.state.track.subtitle.id}',
      );

      bool subtitleApplied = false;

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
        } else {
          // No stored audio preference - apply default audio language setting
          await _applyDefaultAudioLanguage();
        }

        // Bail out if content changed during audio track application
        if (restoreToken != _addonSubtitleFetchToken) return;

        // Apply subtitle track preference. A stored 'auto' is mpv's default
        // placeholder — persisted whenever the user changed AUDIO without
        // ever picking a subtitle — not an explicit subtitle choice. Honoring
        // it would mark an embedded subtitle as applied (mpv 'auto' shows the
        // file's default track, often English) and block addon auto-select of
        // the preferred language. Mirror the audio branch's 'auto' guard and
        // fall through to the default-language path instead.
        if (subtitleTrackId != null &&
            subtitleTrackId.isNotEmpty &&
            subtitleTrackId != 'auto') {
          final tracks = _player.state.tracks;
          // Check if the stored track actually exists in this video
          final trackExists = tracks.subtitle.any(
            (t) => t.id == subtitleTrackId,
          );
          if (trackExists) {
            final subtitleTrack = tracks.subtitle.firstWhere(
              (track) => track.id == subtitleTrackId,
            );
            // A stored pick that CONFLICTS with the current global default
            // language is stale — it predates the user changing the setting
            // (the ids are bare mpv ordinals, so it can't be trusted across
            // setting changes). Let the default-language path win instead:
            // embedded match first, else addon auto-select. Stored 'no'
            // (explicit off for this series) is always honored.
            final defaultLang =
                await StorageService.getDefaultSubtitleLanguage();
            final conflictsWithDefault =
                subtitleTrackId != 'no' &&
                defaultLang != null &&
                (defaultLang == 'off' ||
                    !(LanguageMapper.matchesLanguage(
                          defaultLang,
                          subtitleTrack.language,
                        ) ||
                        LanguageMapper.matchesLanguage(
                          defaultLang,
                          subtitleTrack.title,
                        )));
            if (conflictsWithDefault) {
              debugPrint(
                'SubAuto: stored track id=$subtitleTrackId '
                '(lang=${subtitleTrack.language}/${subtitleTrack.title}) '
                'conflicts with default=$defaultLang → default-language path',
              );
              subtitleApplied = await _applyDefaultSubtitleLanguage();
            } else {
              debugPrint(
                'SubAuto: applying STORED subtitle track id=$subtitleTrackId '
                '(lang=${subtitleTrack.language}/${subtitleTrack.title}) — blocks addon auto-select',
              );
              await _player.setSubtitleTrack(subtitleTrack);
              subtitleApplied = true;
            }
          } else {
            // Stored track doesn't exist in this video - fall through to default
            debugPrint(
              'SubAuto: stored subtitle id=$subtitleTrackId not in this file → default-language path',
            );
            subtitleApplied = await _applyDefaultSubtitleLanguage();
          }
        } else {
          // No stored subtitle preference - apply default subtitle language setting
          debugPrint(
            'SubAuto: stored subtitle id=$subtitleTrackId treated as no-choice → default-language path',
          );
          subtitleApplied = await _applyDefaultSubtitleLanguage();
        }
      } else {
        // No track preferences at all - apply default language settings
        debugPrint('SubAuto: no stored prefs → default-language path');
        await _applyDefaultAudioLanguage();
        subtitleApplied = await _applyDefaultSubtitleLanguage();
      }

      // IPTV series: the language-based memory wins over the per-title ordinal
      // / global default applied above (episodes are separate files whose track
      // orderings differ, so only language carries). No-op off a series episode.
      // No switch is in flight on the initial open, so the current ticket is a
      // valid generation for the staleness guard.
      if (_isIptvSeriesContext) {
        await _applyIptvAudioPreference(_iptvSwitchTicket);
      }

      // Final check before applying state
      if (restoreToken != _addonSubtitleFetchToken) {
        debugPrint('SubAuto: restore aborted post-apply (content changed)');
        return;
      }

      // Track if embedded subtitle was applied for addon fallback
      _embeddedSubtitleApplied = subtitleApplied;
      _trackPreferencesReadyForAddonSubtitles = true;
      debugPrint(
        'SubAuto: restore done — embeddedSubtitleApplied=$subtitleApplied → running addon auto-select',
      );

      // Always fetch Stremio addon subtitles proactively (like Android TV)
      // Auto-selection will only happen if no embedded subtitle was applied
      _fetchAndMaybeAutoSelectAddonSubtitle();
    } catch (e) {
      debugPrint('SubAuto: restore FAILED with exception: $e');
    }
  }

  /// Apply default audio language from settings (when no stored preference exists)
  Future<void> _applyDefaultAudioLanguage() async {
    try {
      final defaultLang = await StorageService.getDefaultAudioLanguage();
      if (defaultLang == null) {
        // No preference set - do nothing, let player use its default
        return;
      }

      final tracks = _player.state.tracks;
      if (tracks.audio.isEmpty) return;

      // Find an audio track matching the preferred language using robust matching
      mk.AudioTrack? matchingTrack;
      for (final track in tracks.audio) {
        if (LanguageMapper.matchesLanguage(defaultLang, track.language)) {
          matchingTrack = track;
          break;
        }
        // Also check title field as some tracks store language there
        if (LanguageMapper.matchesLanguage(defaultLang, track.title)) {
          matchingTrack = track;
          break;
        }
      }

      if (matchingTrack != null) {
        await _player.setAudioTrack(matchingTrack);
      }
    } catch (e) {
      // Silently fail - audio preference is non-critical
    }
  }

  /// Apply default subtitle language from settings (when no stored preference exists)
  /// Returns true if an embedded subtitle was found and applied, false otherwise.
  Future<bool> _applyDefaultSubtitleLanguage() async {
    try {
      final defaultLang = await StorageService.getDefaultSubtitleLanguage();
      debugPrint('SubAuto: defaultSubtitleLanguage setting = $defaultLang');
      if (defaultLang == null) {
        // No preference set - do nothing, let player use its default
        return false;
      }

      final tracks = _player.state.tracks;

      if (defaultLang == 'off') {
        // Explicitly disable subtitles
        await _player.setSubtitleTrack(mk.SubtitleTrack.no());
        return true; // User explicitly disabled, don't try addon
      }

      // Find a subtitle track matching the preferred language using robust matching
      // This handles ISO 639-1, ISO 639-2, regional variants, and language names
      mk.SubtitleTrack? matchingTrack;
      for (final track in tracks.subtitle) {
        if (LanguageMapper.matchesLanguage(defaultLang, track.language)) {
          matchingTrack = track;
          break;
        }
        // Also check title field as some tracks store language there
        if (LanguageMapper.matchesLanguage(defaultLang, track.title)) {
          matchingTrack = track;
          break;
        }
      }

      if (matchingTrack != null) {
        debugPrint(
          'SubAuto: matched EMBEDDED track id=${matchingTrack.id} lang=${matchingTrack.language} title=${matchingTrack.title} — applying',
        );
        await _player.setSubtitleTrack(matchingTrack);
        return true;
      }
      debugPrint(
        'SubAuto: no $defaultLang embedded track → returning false (addon auto-select may run)',
      );
      return false;
    } catch (e) {
      // Silently fail - subtitle preference is non-critical
      debugPrint('SubAuto: _applyDefaultSubtitleLanguage FAILED: $e');
      return false;
    }
  }

  /// Download an addon subtitle's raw bytes and write them to a temp file.
  ///
  /// Returning a file path (rather than a pre-decoded string) lets libmpv
  /// auto-detect the character encoding via its `sub-codepage=auto` default,
  /// which correctly handles GBK, Big5, EUC-KR, Windows-125x, etc. Pre-decoding
  /// via `http.Response.body` would silently corrupt non-UTF-8 subtitle files.
  Future<String?> _downloadStremioSubtitleToTempFile(
    StremioSubtitle sub,
  ) async {
    try {
      final uri = Uri.parse(sub.url);
      final urlPath = uri.path.toLowerCase();
      String ext = 'srt';
      if (urlPath.endsWith('.vtt')) {
        ext = 'vtt';
      } else if (urlPath.endsWith('.ass') || urlPath.endsWith('.ssa')) {
        ext = 'ass';
      } else if (urlPath.endsWith('.ttml') || urlPath.endsWith('.xml')) {
        ext = 'ttml';
      } else if (urlPath.endsWith('.sub')) {
        ext = 'sub';
      } else {
        // No file extension in the path (e.g. YouTube's timedtext endpoint) —
        // fall back to the format carried in the `fmt`/`format` query param so
        // the temp file gets the right extension for libmpv's demuxer.
        final fmt =
            (uri.queryParameters['fmt'] ?? uri.queryParameters['format'] ?? '')
                .toLowerCase();
        if (fmt == 'vtt') {
          ext = 'vtt';
        } else if (fmt == 'ttml') {
          ext = 'ttml';
        }
        // Note: YouTube's srv1/srv2/srv3 are XML timedtext, NOT TTML, and
        // libmpv can't parse them — we deliberately request fmt=vtt for
        // YouTube captions, so those never reach here. Leaving ext='srt' for
        // any unknown fmt is a safe default (WEBVTT/SRT auto-detect by libmpv).
      }

      final dir = await getTemporaryDirectory();
      final stem = sub.id.hashCode.toUnsigned(32).toRadixString(16);
      final file = File('${dir.path}/stremio_sub_$stem.$ext');

      // Re-tapping the same subtitle (or finding a leftover from a previous
      // session) — reuse the existing file instead of re-downloading.
      if (file.existsSync()) {
        _tempSubtitleFiles.add(file.path);
        _activeExternalSubtitlePath = file.path;
        return file.path;
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          'VideoPlayer: Subtitle download failed: HTTP ${response.statusCode}',
        );
        return null;
      }

      await file.writeAsBytes(response.bodyBytes);
      _tempSubtitleFiles.add(file.path);
      _activeExternalSubtitlePath = file.path;
      debugPrint(
        'VideoPlayer: Subtitle written to temp file: ${file.path} (${response.bodyBytes.length} bytes)',
      );
      return file.path;
    } catch (e) {
      debugPrint('VideoPlayer: Subtitle download/write failed: $e');
      return null;
    }
  }

  /// Delete any temp subtitle files we've written. Called from dispose.
  void _cleanupTempSubtitleFilesSync() {
    for (final path in _tempSubtitleFiles) {
      try {
        File(path).deleteSync();
      } catch (e) {
        debugPrint('VideoPlayer: Failed to delete temp subtitle $path: $e');
      }
    }
    _tempSubtitleFiles.clear();
  }

  /// Fetch Stremio addon subtitles proactively and auto-select if no embedded subtitle was applied.
  /// This mirrors the Android TV behavior where subtitles are always fetched on playback start.
  Future<void> _fetchAndMaybeAutoSelectAddonSubtitle() async {
    // Capture token at start to detect if content changes during async operations
    final fetchToken = _addonSubtitleFetchToken;

    try {
      // Get content info for Stremio subtitle fetch
      final seriesPlaylist = _seriesPlaylist;
      String? imdbId;
      String contentType;
      int? season;
      int? episode;

      if (_manualContentImdbId != null && _manualContentImdbId!.isNotEmpty) {
        imdbId = _manualContentImdbId;
        contentType = _manualContentType == 'series' ? 'series' : 'movie';
        if (contentType == 'series') {
          season = _manualContentSeason;
          episode = _manualContentEpisode;
          if ((season == null || episode == null) &&
              seriesPlaylist != null &&
              seriesPlaylist.isSeries) {
            final currentEp = _findSeriesEpisodeForCurrentIndex(seriesPlaylist);
            season ??= currentEp?.seriesInfo.season;
            episode ??= currentEp?.seriesInfo.episode;
          }
          season ??= _currentStremioTvContentSeason ?? widget.contentSeason;
          episode ??= _currentStremioTvContentEpisode ?? widget.contentEpisode;
        }
      } else if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        imdbId = seriesPlaylist.imdbId ?? _effectiveContentImdbId;
        contentType = 'series';
        // Get current episode info from playlist using current index
        final currentEp = _findSeriesEpisodeForCurrentIndex(seriesPlaylist);
        if (currentEp != null) {
          season = currentEp.seriesInfo.season;
          episode = currentEp.seriesInfo.episode;
        }
      } else {
        // Use widget's content IMDB ID or single file IMDB ID
        imdbId = _effectiveContentImdbId ?? _singleFileImdbId;
        // Single-file series playback: use widget params for S/E
        if (_effectiveContentType == 'series' &&
            _effectiveContentSeason != null &&
            _effectiveContentEpisode != null) {
          contentType = 'series';
          season = _effectiveContentSeason;
          episode = _effectiveContentEpisode;
        } else {
          contentType = 'movie';
        }
      }

      // Need IMDB ID to fetch Stremio subtitles
      if (imdbId == null || imdbId.isEmpty) {
        debugPrint('SubAuto: ABORT — no IMDB ID for addon subtitle fetch');
        return;
      }
      debugPrint(
        'SubAuto: addon auto-select start — imdb=$imdbId type=$contentType s=$season e=$episode',
      );

      // Build cache key
      final cacheKey = season != null && episode != null
          ? '$imdbId:$season:$episode'
          : imdbId;

      // Check if we have cached subtitles
      List<StremioSubtitle> subtitles;
      if (_cachedSubtitleKey == cacheKey && _cachedStremioSubtitles != null) {
        subtitles = _cachedStremioSubtitles!;
        debugPrint(
          'VideoPlayer: Using ${subtitles.length} cached addon subtitles',
        );
      } else {
        // Fetch Stremio subtitles proactively (per-addon slots, so the
        // sheet's addon groups are warm when opened)
        debugPrint('VideoPlayer: Fetching addon subtitles (IMDB: $imdbId)');
        final slots = await StremioSubtitleService.instance.fetchSubtitleSlots(
          type: contentType,
          imdbId: imdbId,
          season: season,
          episode: episode,
        );
        subtitles = AddonSubtitleSlot.flatten(slots);

        // Check if content changed during fetch
        if (fetchToken != _addonSubtitleFetchToken) {
          debugPrint(
            'VideoPlayer: Content changed during addon subtitle fetch, discarding results',
          );
          return;
        }

        // Cache the results
        _cachedStremioSubtitles = subtitles;
        _cachedAddonSlots = slots;
        _cachedSubtitleKey = cacheKey;
        debugPrint(
          'VideoPlayer: Fetched and cached ${subtitles.length} addon subtitles',
        );
      }

      // Only auto-select if no embedded subtitle was applied and user hasn't manually selected
      if (_embeddedSubtitleApplied) {
        debugPrint(
          'SubAuto: SKIP — embedded subtitle already applied (_embeddedSubtitleApplied=true)',
        );
        return;
      }

      if (_userManuallySelectedSubtitle) {
        debugPrint(
          'SubAuto: SKIP — user manually selected a subtitle this session',
        );
        return;
      }

      if (subtitles.isEmpty) {
        debugPrint('SubAuto: SKIP — zero addon subtitles fetched');
        return;
      }

      // Get user's default subtitle language preference
      final defaultLang = await StorageService.getDefaultSubtitleLanguage();

      // If subtitles are explicitly disabled, don't auto-select
      if (defaultLang == 'off') {
        debugPrint('SubAuto: SKIP — subtitles set to off');
        return;
      }

      // If no preference set, default to English
      final targetLang = defaultLang ?? 'en';
      final availableLangs = subtitles.map((s) => s.lang).toSet();
      debugPrint(
        'SubAuto: matching targetLang=$targetLang (setting=$defaultLang) '
        'against ${subtitles.length} addon subs, langs=$availableLangs',
      );

      // Find matching subtitle by language
      StremioSubtitle? matchingSub;
      for (final sub in subtitles) {
        if (LanguageMapper.matchesLanguage(targetLang, sub.lang)) {
          matchingSub = sub;
          break;
        }
      }

      if (matchingSub == null) {
        debugPrint('SubAuto: NO MATCH — no $targetLang among $availableLangs');
        return;
      }

      debugPrint(
        'VideoPlayer: Auto-selecting addon subtitle: ${matchingSub.displayName} (${matchingSub.lang})',
      );

      // Download to a temp file so libmpv can detect the encoding itself.
      final filePath = await _downloadStremioSubtitleToTempFile(matchingSub);

      // Check if content changed or user manually selected during download
      if (fetchToken != _addonSubtitleFetchToken) {
        debugPrint(
          'VideoPlayer: Content changed during addon subtitle download, discarding',
        );
        return;
      }
      if (_userManuallySelectedSubtitle) {
        debugPrint(
          'VideoPlayer: User manually selected subtitle during addon download, discarding',
        );
        return;
      }
      if (filePath == null) {
        debugPrint(
          'SubAuto: FAILED to download addon subtitle ${matchingSub.url}',
        );
        return;
      }

      final track = mk.SubtitleTrack.uri(
        filePath,
        title: matchingSub.displayName,
        language: matchingSub.lang,
      );
      await _player.setSubtitleTrack(mk.SubtitleTrack.no());
      await _player.setSubtitleTrack(track);
      _selectedStremioSubtitleId = matchingSub.id;
      _activeExternalSubtitlePath = filePath;

      debugPrint(
        'SubAuto: APPLIED addon subtitle "${matchingSub.displayName}" lang=${matchingSub.lang} source=${matchingSub.source}',
      );
    } catch (e) {
      debugPrint('SubAuto: auto-select FAILED with exception: $e');
    }
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
