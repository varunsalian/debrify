import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kIsWeb,
        listEquals,
        mapEquals,
        setEquals;
import 'package:flutter/material.dart';
import '../../models/iptv_playlist.dart';
import '../../services/debrify_image_cache.dart';
import '../browse/brand_accent.dart';
import '../browse/browse_results_focus.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_catalog_key.dart';
import '../../services/iptv_channel_order.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/iptv_load_phase.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/stremio_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../utils/iptv_player_paging.dart';
import '../../utils/tv_keys.dart' show TvHeldKeyGuard;
import '../../screens/iptv/xtream_series_detail.dart';
import '../../screens/settings/iptv_settings_page.dart';
import '../hero_trailer_backdrop.dart';
import '../../theme/app_theme_scope.dart';
import '../see_all/see_all_filter_bar.dart';
import '../see_all/stremio_dropdown.dart';
import '../../services/iptv_epg_service.dart';
import 'db_channel_list.dart';
import 'iptv_centered_selector.dart';
import 'iptv_filters.dart';
import 'iptv_channel_row.dart';
import 'iptv_list_picker_dialog.dart';
import 'iptv_list_name_dialog.dart';
import 'iptv_empty_state.dart';
import 'iptv_epg_panel.dart';
import 'iptv_command_rail.dart';
import 'iptv_stage_panel.dart';
import 'styles/iptv_console_widgets.dart';
import 'styles/iptv_edition_hero.dart';
import 'styles/iptv_style.dart';
import '../../screens/settings/recordings_page.dart';
import '../../services/desktop_recording_service.dart';
import '../../services/desktop_schedule_service.dart';
import '../../services/iptv_source_stats.dart';
import '../../services/profiles/profile_preferences.dart';

import '../../services/live_recording_service.dart';
import '../recording_limit_dialogs.dart';

typedef _TabletChannelIdentity = ({
  int? channelNumber,
  String name,
  String url,
  String? group,
  String? contentType,
});

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)"
/// — pulled out of the rail's big title into its sub-line (the channel rows do
/// the same split for themselves).
final RegExp _railResExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

/// State of the bottom-right background-refresh chip.
enum _CatalogChipState { hidden, updating, success, failure }

/// Who currently owns the single status chip, in priority order.
///
/// Background jobs overlap — the guide download starts when the list is
/// presented, the maintenance pipeline two seconds later, and a refresh after
/// that — so without a rank the last writer wins and the chip flickers between
/// unrelated messages. News about the LIST itself outranks news about the
/// guide, and a stage only clears the chip if it still holds it.
enum _ChipOwner { none, guide, maintenance, refresh }

/// Main view for IPTV M3U results, to be embedded in TorrentSearchScreen
class IptvResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;

  /// Callback when up arrow is pressed from filters (to go back to source dropdown)
  final VoidCallback? onUpArrowFromFilters;

  const IptvResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    this.onUpArrowFromFilters,
  });

  @override
  State<IptvResultsView> createState() => IptvResultsViewState();
}

class IptvResultsViewState extends State<IptvResultsView>
    with WidgetsBindingObserver
    implements BrowseResultsFocusController {
  final ScrollController _scrollController = ScrollController();
  final IptvService _iptvService = IptvService.instance;

  // ---- Startup channel -----------------------------------------------------
  // Grid metrics, published from the LayoutBuilder so the startup launch can
  // scroll to a not-yet-built row.
  int _gridColumns = 1;
  double _gridRowExtent = 72;

  /// Bumped by every cancellation. The whole launch re-checks it after each
  /// await — consuming the pending payload is NOT cancellation, because the
  /// async chain owns the attempt from that moment on.
  int _startupAttempt = 0;

  /// True while a startup launch is in flight. Holds the preview stage off:
  /// `_previewRearmPending` only parks a RE-arm, it does nothing about the
  /// initial 900ms dwell, which would happily open a second live stream
  /// underneath the launching player.
  bool _startupLaunchActive = false;

  // Playlists and settings
  List<IptvPlaylist> _playlists = [];

  // ---- Command Center (rail + stage cockpit) ------------------------------
  /// playlist.id → catalog channel count for the rail; recomputed whenever
  /// the playlist set reloads. Sync, indexed DB reads — no scans, no network.
  Map<String, int> _sourceCounts = const {};

  /// Upcoming scheduled recordings, for the rail's Scheduled badge.
  int _scheduledCount = 0;

  /// Whether this platform can record at all (engine on Android 10+, the
  /// desktop capture elsewhere) — gates the stage's Record/REC affordances.
  bool _pageCanRecord = false;

  /// iOS only: a one-time dismissible notice that recording doesn't exist
  /// there (Apple allows no background capture and no scheduled wake-ups) —
  /// otherwise iOS users go hunting for a Record button that isn't hidden
  /// by a setting, it's hidden by the platform.
  bool _showIosRecordingNotice = false;
  static const String _iosNoticeDismissedPref =
      'iptv_ios_recording_notice_dismissed';
  IptvPlaylist? _selectedPlaylist;
  bool _settingsLoaded = false;

  /// Why the settings pass failed, if it did. [_loadSettings] is the gate in
  /// front of the whole page: it sets [_settingsLoaded] on its LAST line, so
  /// any throw on the way there used to leave the bare spinner up forever with
  /// no error, no Retry and nothing on screen to name the failure — the same
  /// silent-spinner trap [_loadPlaylist] already guards against one level down.
  String? _settingsError;

  /// The cockpit's visual style (`iptv_style` pref). Only the TV/desktop
  /// cockpit branch consults it — classic and touch-tablet layouts ignore it.
  IptvStyle _iptvStyle = IptvStyle.command;

  /// Whether focusing a row may open its stream in the embedded side stage.
  /// The channel identity and stage actions remain available when false; only
  /// the automatic tune is suppressed so it cannot consume a provider slot.
  bool _channelPreviewEnabled = true;

  /// Desktop gets the full two-pane experience too: source rail, embedded
  /// live preview, quiet filters — hover previews, click plays.
  /// Large touch tablets use the same shell with a fixed center selector;
  /// phones and constrained tablet windows keep the single-pane list.
  static final bool _isDesktop =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static const double tabletTwoPaneMinWidth = 900;
  static const double tabletTwoPaneMinHeight = 500;

  static bool shouldUseTouchTabletTwoPane({
    required bool isTelevision,
    required bool isWeb,
    required TargetPlatform platform,
    required Size availableSize,
  }) {
    final touchPlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return !isTelevision &&
        !isWeb &&
        touchPlatform &&
        availableSize.width >= tabletTwoPaneMinWidth &&
        availableSize.height >= tabletTwoPaneMinHeight;
  }

  // Current playlist data
  List<IptvChannel> _allChannels = [];
  List<IptvChannel> _filteredChannels = [];
  List<String> _categories = [];
  String? _selectedCategory;

  /// True once the user has picked a category — INCLUDING "All" — for the
  /// current load. Needed because "All" and "nothing picked yet" are the same
  /// null [_selectedCategory]: the landing-category seed fills the latter and
  /// must never override the former (a background revalidate re-presenting
  /// the catalog would otherwise yank an explicit "All" back to a category).
  bool _categoryManuallyChosen = false;

  /// Armed by [_loadPlaylistInner]'s clearing setState and consumed by the
  /// FIRST present of that load. Only that present may seed a landing
  /// category: the background revalidate re-uses the same present functions
  /// (including the materialized fallback when the DB flag flips off
  /// mid-flight), and an unarmed seed there would yank a user who is sitting
  /// on All mid-browse.
  bool _landingSeedArmed = false;

  /// Non-null exactly while the CURRENT view is DB-backed.
  CatalogSnapshot? _dbSnapshot;

  /// Per-group counts for the DB-backed catalog (replaces the
  /// [_categoryCounts] scan, which would page the whole facade).
  Map<String, int> _dbGroupCounts = const {};

  /// Categories the user has hidden in the CURRENT catalog.
  ///
  /// The channel rows are already excluded in SQL, and so are the groups
  /// derived from them — this set exists for the one list SQL can't reach:
  /// the provider's own `categories_json`, which names categories verbatim
  /// rather than deriving them from rows.
  Set<String> _hiddenCategories = const {};

  /// Shared instance cache for the DB facades of the CURRENT catalog
  /// generation (see [DbChannelList.instanceCache]): reused so a filter /
  /// search recompute keeps identity for rows that stay on screen, instead
  /// of minting new instances that tear down and rebuild every visible row
  /// (EPG re-resolve, focus/image churn — what made search feel laggy).
  final LinkedHashMap<int, IptvChannel> _dbInstanceCache = LinkedHashMap();

  /// `<catalogKey>#<generation>` the [_dbInstanceCache] currently holds —
  /// cleared when either changes (a different playlist, or a refresh's new
  /// generation, whose rows can carry changed data).
  String? _dbInstanceCacheKey;

  /// Same freshness window the services' in-memory caches used: a DB catalog
  /// ingested within it presents without a background revalidate.
  static const Duration _dbCatalogTtl = Duration(minutes: 30);

  /// Set when a playlist switch was made from the TV source rail: once the
  /// new catalog presents, DPAD focus moves into the content pane. Moving
  /// focus off the rail is what collapses its expanded overlay (the rail
  /// stays open only while one of its chips holds focus), so this is how
  /// "pick a source → the picker collapses and the list takes over" works.
  bool _focusContentAfterLoad = false;

  // Content type for Xtream Codes playlists
  String _selectedContentType = 'live';

  // Loading state
  bool _isLoading = false;
  String? _errorMessage;

  // Background catalog refresh (stale-while-revalidate) status chip.
  // `updating` appears only when the revalidate is genuinely slow (a real
  // network fetch), so instant in-memory-cache revalidates never flash it.
  _CatalogChipState _chipState = _CatalogChipState.hidden;
  String _chipMessage = '';
  // ── Blocking-load status ────────────────────────────────────────────────
  // A first load of a big panel is several seconds behind a spinner, and
  // silence reads as "frozen". These carry what is happening plus a real
  // number when one exists.
  //
  // Deliberately NOT setState-ed per update: byte callbacks fire per network
  // chunk, and repainting on each would be exactly the UI-isolate churn this
  // page has spent so long shedding. They are plain fields, and [_loadTicker]
  // repaints once a second — which also makes the elapsed clock tick.
  String? _loadPhase;
  int? _loadBytes;
  int? _loadTotalBytes;
  DateTime? _loadStartedAt;
  Timer? _loadTicker;

  /// Past this, a load is slow enough that the user deserves to be told it is
  /// normal rather than left guessing.
  static const _slowLoadHint = Duration(seconds: 10);

  _ChipOwner _chipOwner = _ChipOwner.none;
  Timer? _chipShowTimer;
  Timer? _maintenanceChipTimer;
  Timer? _chipHideTimer;

  // Progressive (Stremio-addon) loads: [_loadTicket] orphans a superseded
  // load's batches AND its final result, and doubles as the cancel signal
  // that stops its catalog walk; [_isLoadingMore] is true from the first
  // streamed batch until the walk completes — every "N channels" readout and
  // empty state must stay honest while it's set (the list is still growing,
  // so a search can have matches on the way).
  int _loadTicket = 0;

  /// Ticket of a [_loadPlaylist] run that is still in flight, or null.
  /// Guards [_loadSettings]' "no channels yet" fallback: `_allChannels` is
  /// empty for the ENTIRE duration of a first load (cleared at start, filled
  /// at present — tens of seconds on a big panel), so without this any
  /// re-entry in that window (Stremio addons-changed listener, a settings
  /// return, refreshPlaylists) started a SECOND full pipeline. The first was
  /// never cancelled — only its result discarded by ticket — so both kept
  /// buffering up to 50 MB of HTTP body and both held a full parse isolate:
  /// ~200 MB of transient heap, an OOM on a 1 GB box.
  int? _inFlightLoadTicket;
  bool _isLoadingMore = false;
  DateTime? _lastProgressiveApply;

  // Favorites — the built-in list, kept as its own set because every row's
  // star icon reads it on each build.
  Set<String> _favoriteUrls = {};

  /// Which lists each stored channel belongs to (url → list ids). Drives the
  /// list picker's checkmarks without a per-row store round-trip.
  Map<String, Set<String>> _membership = const {};

  /// Every list, Favorites first then custom lists in user order.
  List<IptvListMeta> _lists = const [];

  /// The user's own lists — empty until they create one, which is what keeps
  /// hold-OK meaning "toggle favorite" for everyone who never does.
  List<IptvListMeta> get _customLists => [
    for (final list in _lists)
      if (!list.isBuiltin) list,
  ];

  /// Original playlistId each membership was added from, keyed by
  /// (list id, url). Toggling inside a virtual shelf must keep the channel
  /// tied to its real playlist, so deleting that playlist still sweeps it out
  /// of every list — and the same URL saved into two lists from two different
  /// providers must keep BOTH origins, or one replays under the other's
  /// credentials.
  Map<(String, String), String> _favoritePlaylistIds = {};

  /// Virtual "Favorites" playlist — never persisted; pinned to the top of the
  /// picker and backed by the built-in list instead of a fetch.
  static final IptvPlaylist _favoritesPlaylist = IptvPlaylist(
    id: 'iptv-favorites',
    name: 'Favorites',
    url: 'favorites://',
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Virtual playlist for a user-created list. Ids are derived from the list
  /// id so the player payload, the picker and the browse round-trip all agree
  /// on one identity.
  static IptvPlaylist _listPlaylist(IptvListMeta list) => IptvPlaylist(
    id: 'iptv-list-${list.id}',
    name: list.name,
    url: 'list://${list.id}',
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Virtual "Continue watching" playlist — never persisted; backed by the
  /// watch-history store joined with the positions both players save. Sits
  /// beside Favorites so a half-watched movie is reachable without having
  /// had the foresight to star it first.
  static final IptvPlaylist _continuePlaylist = IptvPlaylist(
    id: 'iptv-continue',
    name: 'Continue watching',
    url: 'continue://',
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Resume fraction (0-1) per channel URL for the loaded list — drives the
  /// bar across each poster. Only on-demand items ever have an entry.
  Map<String, double> _progressByUrl = {};

  /// Whether the current view shows on-demand items, which are drawn as 2:3
  /// posters in taller rows. Derived from the selected view rather than by
  /// scanning the channels: the grid needs one answer for every tile, and
  /// scanning tens of thousands of rows per build to get it isn't free.
  ///
  /// M3U playlists keep the logo layout even for their VOD entries — their
  /// content type is a duration heuristic, so a mixed playlist has no single
  /// honest answer here.
  bool get _showsPosterRows {
    final playlist = _selectedPlaylist;
    if (playlist == null) return false;
    if (playlist.isContinueWatching) return true;
    if (playlist.isXtreamCodes) {
      return _selectedContentType == 'vod' || _selectedContentType == 'series';
    }
    return false;
  }

  /// Playlist each Continue-watching row came from (url → id). Replaying from
  /// that shelf must keep the item tied to its real provider, so deleting the
  /// provider still sweeps it — the same reason [_favoritePlaylistIds] exists.
  Map<String, String> _continuePlaylistIds = {};

  // Focus nodes for DPAD
  final FocusNode _playlistFilterFocusNode = FocusNode(
    debugLabel: 'iptv-playlist-filter',
  );
  final FocusNode _categoryFilterFocusNode = FocusNode(
    debugLabel: 'iptv-category-filter',
  );
  final FocusNode _contentTypeFocusNode = FocusNode(
    debugLabel: 'iptv-content-type-filter',
  );

  /// Per-category channel counts for the current catalog (redesign labels).
  /// Memoized against the list instance AND its length — progressive Stremio
  /// loads append to one list, so identity alone would freeze the counts at
  /// the first batch.
  List<IptvChannel>? _categoryCountsSource;
  int _categoryCountsLength = -1;
  Map<String, int> _categoryCountsCache = const {};
  Map<String, int> get _categoryCounts {
    // Counts come from one GROUP BY at present time — scanning the
    // facade here would page through the whole catalog.
    if (_dbSnapshot != null) return _dbGroupCounts;
    if (!identical(_categoryCountsSource, _allChannels) ||
        _categoryCountsLength != _allChannels.length) {
      final counts = <String, int>{};
      for (final channel in _allChannels) {
        final group = channel.group;
        if (group != null && group.isNotEmpty) {
          counts[group] = (counts[group] ?? 0) + 1;
        }
      }
      _categoryCountsSource = _allChannels;
      _categoryCountsLength = _allChannels.length;
      _categoryCountsCache = counts;
    }
    return _categoryCountsCache;
  }

  /// Whether the current list draws EPG rows (now/next inside each row).
  /// Poster lists never do; otherwise sampled from the first few channels —
  /// Xtream capability is homogeneous (URL parse), but XMLTV matching is
  /// per-channel, and a single unmatched channel at position 0 must not veto
  /// the whole list. Rows without data fall back gracefully; the grid needs
  /// one tile height for everything either way.
  bool get _epgRowsActive {
    if (_showsPosterRows) return false;
    final channels = _filteredChannels;
    if (channels.isEmpty) return false;
    final sample = channels.length < 10 ? channels.length : 10;
    for (var i = 0; i < sample; i++) {
      if (IptvEpgService.isEpgCapable(channels[i])) return true;
    }
    return false;
  }

  // TV preview stage (the two-pane layout's left rail). Notifiers, not
  // setState: a DPAD move over the channel list must repaint the rail alone,
  // never rebuild the whole grid. [_previewShown] is the focused channel;
  // [_previewShowing] flips when the embedded player actually has frames;
  // [_previewEpoch] bumps after returning from real playback so the stage
  // remounts fresh (HeroTrailerBackdrop latches itself off for the rest of a
  // page visit once real content playback launches — a new instance is the
  // supported way to re-arm it).
  final ValueNotifier<IptvChannel?> _previewShown = ValueNotifier<IptvChannel?>(
    null,
  );
  final ValueNotifier<bool> _previewShowing = ValueNotifier<bool>(false);
  final ValueNotifier<int> _previewEpoch = ValueNotifier<int>(0);

  // The URL the preview stage actually plays. For M3U/Xtream channels this is
  // just the channel URL; for Stremio-addon channels it is the current rung of
  // the candidate ladder (resolved async on focus, advanced by
  // [_onPreviewPlaybackFailed] until one plays or the list runs out). Null =
  // nothing to play, the stage shows only its static floor.
  final ValueNotifier<String?> _previewStreamUrl = ValueNotifier<String?>(null);

  /// Candidate URLs for the focused Stremio channel; null while a non-Stremio
  /// channel is focused (their failures keep the old silent-floor behavior).
  List<String>? _previewCandidates;

  /// Guards async resolves against focus moving on before they land.
  int _previewResolveTicket = 0;
  // Keyed by channel INSTANCE rather than list position (focus survives
  // category/search filtering, which reuses the same objects) — and rather
  // than URL: playlists routinely list one stream URL under several names,
  // and a URL key would hand those rows a single shared FocusNode, lighting
  // them all up together and scrambling DPAD traversal around the pair.
  // Instances are stable for a playlist's whole life (progressive Stremio
  // batches append to one list; filters select from it), and the map is
  // rebuilt with the instances on every _loadPlaylist.
  final Map<IptvChannel, FocusNode> _cardFocusNodes = Map.identity();

  /// Channel instances whose row State has been disposed (reported via
  /// IptvChannelRow.onDetached) — the ONLY reliable "this node is detached"
  /// signal. FocusNode.context is assigned on attach and never cleared on
  /// detach (SDK focus_manager.dart), so the old `node.context == null`
  /// sweeps were dead code: nothing was ever retired, and [_cardFocusNodes]
  /// leaked one FocusNode + IptvChannel per row ever scrolled — the
  /// scales-with-catalog OOM on TV. Cleared per-instance when a row is
  /// (re)built, wholesale on reload.
  final Set<IptvChannel> _detachedRows = HashSet.identity();

  void _onRowDetached(IptvChannel channel) {
    _detachedRows.add(channel);
  }

  FocusNode _focusNodeFor(IptvChannel channel) {
    // Being asked for the node means the row is being (re)built right now.
    _detachedRows.remove(channel);
    return _cardFocusNodes.putIfAbsent(
      channel,
      () => FocusNode(debugLabel: 'iptv-card-${channel.name}-${channel.url}'),
    );
  }

  /// Whether [channel]'s row is currently built (its node attached). Nodes
  /// with no map entry count as detached.
  bool _rowAttached(IptvChannel channel) =>
      _cardFocusNodes.containsKey(channel) && !_detachedRows.contains(channel);

  String _lastSearchQuery = '';

  /// Channel whose programme schedule is open. TV and large touch tablets
  /// swap the two-pane layout's right side for the schedule while the preview
  /// keeps playing; classic and desktop-pointer layouts use a bottom sheet.
  IptvChannel? _scheduleChannel;

  /// Whether the last build used the TV two-pane layout. The in-place
  /// schedule pane only exists there — on the classic fallback (narrow TV
  /// canvas) RIGHT must open the bottom sheet instead, or it sets state
  /// nothing renders (a silent dead key).
  bool _tvTwoPaneActive = false;
  bool _touchTabletTwoPaneActive = false;

  /// The fixed tablet cursor owns a logical channel, not a List position.
  /// Progressive Stremio batches and filters replace the List object while
  /// retaining its rows; keeping both identity and the last index makes the
  /// common append-only update O(1), while still finding a moved row.
  int _tabletSelectedIndex = 0;
  _TabletChannelIdentity? _tabletSelectedIdentity;

  /// The schedule action for a row, or null when the channel can't have
  /// guide data (no RIGHT-key handling, no calendar icon).
  VoidCallback? _scheduleActionFor(
    IptvChannel channel, {
    bool inPlace = false,
  }) {
    if (!IptvEpgService.isEpgCapable(channel)) return null;
    if (inPlace) {
      return () => _openSchedulePane(channel);
    }
    return () => showIptvScheduleSheet(
      context,
      channel,
      isTelevision: widget.isTelevision,
      onPlayProgramme: (programme) => _playCatchup(channel, programme),
      onRecordProgramme: _recordProgrammeActionFor(channel),
    );
  }

  void _openSchedulePane(IptvChannel channel) {
    setState(() => _scheduleChannel = channel);
  }

  void _closeSchedulePane() {
    final channel = _scheduleChannel;
    if (channel == null) return;
    setState(() => _scheduleChannel = null);
    if (!widget.isTelevision) return;
    // Hand focus back to the row that opened the schedule. Post-frame: the
    // grid (and the cached node's row) only exists again after this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _cardFocusNodes[channel];
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.isTelevision) {
      // Lifecycle observer completes the parked preview re-arm when the app
      // returns from the native player (see _playChannel); the sidebar
      // listener stops the preview while the menu overlay is open.
      WidgetsBinding.instance.addObserver(this);
      MainPageBridge.addTvSidebarFocusListener(_onTvSidebarFocusChanged);
    }
    // Virtual Stremio playlists come and go with the installed addon set.
    StremioService.instance.addAddonsChangedListener(_onStremioAddonsChanged);
    IptvChannelOrderSignal.revision.addListener(_onChannelOrderChanged);
    // Chained, not fire-and-forget: the startup launch needs the playlist list
    // to exist before it can pick the target's provider.
    // Guarded on the error too, not just mounted: _loadSettings now SWALLOWS
    // its failures (it renders them instead), so this callback runs on a path
    // that used to skip it entirely. _maybeRunStartupLaunch consumes the
    // one-shot startup payload, and burning it against an empty playlist set
    // would cancel a boot-to-channel request that Retry could still honour.
    _loadSettings().then((_) {
      if (mounted && _settingsError == null) {
        unawaited(_maybeRunStartupLaunch());
      }
    });
    _loadFavorites();
    // Stage cockpit: recording availability + the rail's Scheduled badge.
    // Off the critical path; only ever ENABLES affordances.
    unawaited(_initRecordingSupport());
    if (!kIsWeb && Platform.isIOS) {
      unawaited(
        DevicePreferences.instance().then((prefs) {
          if (!mounted) return;
          if (!(prefs.getBool(_iosNoticeDismissedPref) ?? false)) {
            setState(() => _showIosRecordingNotice = true);
          }
        }),
      );
    }
    // Observe, don't sample: schedule mutations from ANY in-process surface
    // (player sheet, manual timer, desktop scheduler firing) update the rail
    // badge, and desktop capture starts/ends flip the stage's Record↔Stop —
    // including a SCHEDULED capture starting while focus parks on its channel.
    LiveRecordingService.schedulesRevision.addListener(_onSchedulesChanged);
    DesktopRecordingService.instance.revision.addListener(
      _onDesktopRecordingChanged,
    );
  }

  void _onSchedulesChanged() {
    if (mounted) unawaited(_refreshScheduledCount());
  }

  void _onDesktopRecordingChanged() {
    if (mounted) setState(() {});
  }

  void _onStremioAddonsChanged() {
    if (mounted) _loadSettings();
  }

  void _onChannelOrderChanged() {
    final playlist = _selectedPlaylist;
    final change = IptvChannelOrderSignal.latest;
    if (!mounted || playlist == null || change == null) return;
    final affected = switch (change.scope) {
      IptvChannelOrderScope.list =>
        (playlist.isFavorites &&
                change.target == StorageService.iptvFavoritesListId) ||
            playlist.customListId == change.target,
      IptvChannelOrderScope.source =>
        change.target.isEmpty || playlist.id == change.target,
      IptvChannelOrderScope.catalog =>
        change.target.isEmpty ||
            IptvCatalogKey.forCategoryOrder(playlist, _selectedContentType) ==
                change.target,
    };
    if (affected) unawaited(_loadPlaylist(playlist));
  }

  Future<void> _loadFavorites() async {
    final lists = await StorageService.getIptvLists();
    final snapshot = await StorageService.getIptvMembershipSnapshot();
    if (mounted) {
      setState(() {
        _lists = lists;
        _membership = snapshot.membership;
        _favoriteUrls = {
          for (final entry in snapshot.membership.entries)
            if (entry.value.contains(StorageService.iptvFavoritesListId))
              entry.key,
        };
        _favoritePlaylistIds = snapshot.origins;
      });
    }
  }

  /// The real playlist a channel belongs to. Inside a virtual shelf the
  /// selected playlist is not a provider at all, so writing its id into the
  /// favorites/history stores would break the sweep that runs when a provider
  /// is deleted (nothing would match 'iptv-favorites' or 'iptv-continue') and
  /// strand entries pointing at URLs that no longer authenticate.
  String? _originPlaylistIdFor(IptvChannel channel) {
    final playlist = _selectedPlaylist;
    if ((playlist?.isFavorites ?? false) || (playlist?.isCustomList ?? false)) {
      // The shelf's own rows carry the origin of the exact membership they
      // were rebuilt from — the only source that stays correct when the same
      // URL sits in two lists under two providers.
      final rowOrigin = channel.attributes[_kListOriginAttribute];
      if (rowOrigin != null && rowOrigin.isNotEmpty) return rowOrigin;
      final listId = playlist!.isFavorites
          ? StorageService.iptvFavoritesListId
          : playlist.customListId;
      if (listId == null) return null;
      return _favoritePlaylistIds[(listId, channel.url)];
    }
    if (playlist?.isContinueWatching ?? false) {
      return _continuePlaylistIds[channel.url];
    }
    return playlist?.id;
  }

  IptvPlaylist? _recordingResourceFor(IptvChannel channel) {
    final originId = _originPlaylistIdFor(channel);
    if (originId == null) return null;
    for (final playlist in _playlists) {
      if (playlist.id == originId && playlist.connectionResourceId != null) {
        return playlist;
      }
    }
    return null;
  }

  /// Attribute carrying a list row's originating provider through the
  /// rebuilt channel, so both origin resolvers can be exact rather than
  /// looking a URL up in a map that can only hold one answer per URL.
  static const String _kListOriginAttribute = 'list_playlist_id';

  Future<void> _toggleFavorite(IptvChannel channel, bool isFavorited) async {
    await StorageService.setIptvChannelFavorited(
      channel.url,
      isFavorited,
      channelName: channel.name,
      logoUrl: channel.logoUrl,
      group: channel.group,
      playlistId: _originPlaylistIdFor(channel),
      channelNumber: channel.channelNumber,
      // A list is replayed from stored metadata, never re-parsed from the
      // playlist — so the channel's own headers have to travel with it, and
      // so does what it IS: without a content type a movie comes back as a
      // live channel and loses its resume bar.
      contentType: channel.contentType,
      duration: channel.duration,
      httpHeaders: channel.httpHeaders,
    );
    if (mounted) {
      setState(() {
        if (isFavorited) {
          _favoriteUrls.add(channel.url);
          _membership = {
            ..._membership,
            channel.url: {
              ...?_membership[channel.url],
              StorageService.iptvFavoritesListId,
            },
          };
        } else {
          _favoriteUrls.remove(channel.url);
          _membership = {
            ..._membership,
            channel.url: {...?_membership[channel.url]}
              ..remove(StorageService.iptvFavoritesListId),
          };
        }
      });
    }
    // Deliberately no shelf reload here, even inside the Favorites view: a
    // reload disposes every row's focus node (see _loadPlaylist) and would
    // scramble DPAD focus out from under the hold the user just finished.
    // The row stays with an empty heart until the next natural reload —
    // which is what it has always done.
  }

  /// Open the "add to list" picker for [channel]. Only reachable once the
  /// user has created a list — before that, the same gesture toggles the
  /// favorite outright, so nobody grows an extra tap they didn't ask for.
  Future<void> _openListPicker(IptvChannel channel) async {
    final changed = await showIptvListPickerDialog(
      context: context,
      channelName: channel.name,
      channelLogoUrl: channel.logoUrl,
      loadLists: () => StorageService.getIptvLists(),
      loadMembership: () => StorageService.getIptvListsForChannel(channel.url),
      onSetMembership: (listId, inList) => StorageService.setIptvChannelInList(
        listId,
        channel.url,
        inList,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: _originPlaylistIdFor(channel),
        channelNumber: channel.channelNumber,
        contentType: channel.contentType,
        duration: channel.duration,
        httpHeaders: channel.httpHeaders,
      ),
      onCreateList: (name) => StorageService.createIptvList(name),
    );
    if (!changed || !mounted) return;
    await _loadFavorites();
    if (!mounted) return;
    _refreshListShelfPresence();
    await _refreshVisibleListShelf(channel);
  }

  /// Create an empty list from the Sources picker — the discoverable path for
  /// someone who hasn't long-pressed a channel yet. Selects it afterwards so
  /// the (empty) shelf explains how to fill it.
  Future<void> _promptCreateList() async {
    final name = await showIptvListNameDialog(
      context: context,
      title: 'New list',
      confirmLabel: 'Create',
      existingNames: [for (final list in _lists) list.name],
    );
    if (name == null || !mounted) return;
    final id = await StorageService.createIptvList(name);
    if (!mounted) return;
    await _loadFavorites();
    if (!mounted) return;
    _refreshListShelfPresence();
    for (final playlist in _playlists) {
      if (playlist.customListId == id) {
        _onPlaylistChanged(playlist);
        break;
      }
    }
  }

  /// Rebuild the shelf the user is looking at when [channel] just left it —
  /// a row the picker removed can't stay on screen claiming otherwise.
  ///
  /// Narrow on purpose. A reload disposes every row's focus node (see
  /// [_loadPlaylist]), so it only earns that cost when the visible grid is
  /// genuinely wrong; adding a channel to some OTHER list changes nothing
  /// here. And deliberately NOT via _loadSettings, which re-derives the
  /// landing selection and would yank the user off the source they are on.
  Future<void> _refreshVisibleListShelf(IptvChannel channel) async {
    final playlist = _selectedPlaylist;
    if (playlist == null) return;
    final listId = playlist.isFavorites
        ? StorageService.iptvFavoritesListId
        : playlist.customListId;
    if (listId == null) return;
    final stillIn = _membership[channel.url]?.contains(listId) ?? false;
    if (stillIn) return;
    final onScreen = _allChannels.any((c) => c.url == channel.url);
    if (!onScreen) return;
    await _loadPlaylist(playlist);
  }

  /// Guarded entry point — see [_settingsError]. Every caller (initState, the
  /// addon-changed listener, returning from Settings, Retry) goes through here
  /// so no path can reintroduce the silent spinner.
  Future<void> _loadSettings({bool forceReload = false}) async {
    try {
      await _loadSettingsInner(forceReload: forceReload);
    } catch (e, st) {
      debugPrint('IPTV: settings load failed: $e\n$st');
      if (!mounted) return;
      // Deliberately NOT setting _settingsLoaded: the page below this gate
      // assumes a loaded playlist set. Failing here keeps the failure
      // contained to the gate, which now renders the reason and a Retry.
      setState(() => _settingsError = '$e');
    }
  }

  Future<void> _loadSettingsInner({bool forceReload = false}) async {
    var playlists = await StorageService.getIptvPlaylists(forSettings: false);
    final defaultPlaylistId = await StorageService.getIptvDefaultPlaylist();
    // Cockpit look. Read on every pass so returning from Settings (which
    // re-enters here) adopts a changed style in the same setState as
    // everything else — no separate listener, no style flash.
    final iptvStyle = IptvStyle.fromPref(await StorageService.getIptvStyle());
    final channelPreviewEnabled =
        await StorageService.getIptvChannelPreviewEnabled();

    // Seed the starter playlist on first run (if not already initialized).
    // Deliberately NOT marked as the stored default: "Default playlist" is an
    // explicit choice the user makes in Settings, and it now outranks the
    // Favorites landing (below) — auto-claiming it here would silently take
    // that landing away from someone who never picked anything.
    final defaultsInitialized =
        await StorageService.getIptvDefaultsInitialized();
    if (!defaultsInitialized) {
      // Add the default iptv-org playlist
      final starterPlaylist = IptvPlaylist(
        id: 'iptv-org-default',
        name: 'iptv-org',
        url: 'https://iptv-org.github.io/iptv/index.m3u',
        addedAt: DateTime.now(),
      );
      playlists = [starterPlaylist, ...playlists];

      // Save the starter playlist and mark as initialized
      playlists = await StorageService.setIptvPlaylistsAndReload(
        playlists,
        forSettings: false,
      );
      await StorageService.setIptvDefaultsInitialized(true);
    }

    // Installed Stremio addons with live-TV catalogs appear as (non-stored)
    // virtual playlists after the user's own entries.
    final virtualPlaylists = await StremioIptvService.instance
        .getVirtualPlaylists();
    playlists = [...playlists, ...virtualPlaylists];

    // The virtual Favorites playlist leads the picker, then Continue watching,
    // then the user's own lists, then the real providers. Hidden only when
    // there is nothing at all (no playlists, no favorites, no lists), so the
    // add-a-playlist empty state can still do its job.
    //
    // One store read covers both the presence probe and the list rows — the
    // per-list channel counts come back with them.
    final lists = await StorageService.getIptvLists();
    final hasFavorites = lists.any((l) => l.isFavorites && l.channelCount > 0);
    final customLists = [
      for (final list in lists)
        if (!list.isBuiltin) list,
    ];
    // "Continue watching" earns its slot only while something is actually
    // half-watched — an empty shelf in the picker is just noise. Custom lists
    // stay visible even when empty: the user made them on purpose, and an
    // empty one is where they go to fill it.
    final hasContinue =
        (await StorageService.getIptvContinueWatching()).isNotEmpty;
    if (hasFavorites || customLists.isNotEmpty || playlists.isNotEmpty) {
      playlists = [
        _favoritesPlaylist,
        if (hasContinue) _continuePlaylist,
        for (final list in customLists) _listPlaylist(list),
        ...playlists,
      ];
    }

    if (!mounted) return;

    // Determine the new selected playlist. The playlist the user starred as
    // "Default" in Settings wins: it is the one landing they asked for out
    // loud, so it outranks the Favorites shelf. With no usable default, at
    // least one starred channel makes Favorites the landing selection;
    // otherwise the first real provider (never landing on an empty Favorites
    // view).
    IptvPlaylist? newSelectedPlaylist;
    IptvPlaylist? firstRealPlaylist;
    for (final p in playlists) {
      // No virtual shelf is a "real" playlist to fall back to — each can be
      // empty or vanish entirely between visits, and landing on an empty
      // custom list reads exactly as broken as landing on empty Favorites.
      // (Stremio addon shelves stay eligible: they are a remote catalog with
      // content of their own, not a view over stored rows.)
      if (!p.isFavorites && !p.isContinueWatching && !p.isCustomList) {
        firstRealPlaylist = p;
        break;
      }
    }
    // Only a default that still resolves to a present provider counts — a
    // stale id (its playlist deleted elsewhere, an addon shelf whose addon is
    // uninstalled) must fall through rather than outrank Favorites.
    IptvPlaylist? defaultPlaylist;
    if (defaultPlaylistId != null) {
      for (final p in playlists) {
        if (p.id == defaultPlaylistId) {
          defaultPlaylist = p;
          break;
        }
      }
    }
    if (defaultPlaylist != null) {
      newSelectedPlaylist = defaultPlaylist;
    } else if (hasFavorites) {
      newSelectedPlaylist = _favoritesPlaylist;
    } else if (playlists.isNotEmpty) {
      newSelectedPlaylist = firstRealPlaylist ?? playlists.first;
    }

    // Check if playlist changed
    final playlistChanged = _selectedPlaylist?.id != newSelectedPlaylist?.id;

    // Rail counts: a handful of indexed reads against the already-open
    // catalog. Skipped entirely when the DB isn't up — the rail just shows
    // no numbers, never a spinner.
    final sourceCounts = <String, int>{};
    if (IptvCatalogDb.isOpen) {
      for (final p in playlists) {
        if (p.isVirtual) continue;
        try {
          final stats = IptvSourceStatsLoader.read(p);
          if (stats.cached) sourceCounts[p.id] = stats.total;
        } catch (_) {
          // A closed/failed DB read leaves this source uncounted, nothing more.
        }
      }
    }

    final previewWasEnabled = _channelPreviewEnabled;
    setState(() {
      _iptvStyle = iptvStyle;
      _channelPreviewEnabled = channelPreviewEnabled;
      _sourceCounts = sourceCounts;
      _playlists = playlists;
      _settingsLoaded = true;
      _selectedPlaylist = newSelectedPlaylist;
      // Adopt the rows this pass just read. Returning from Settings goes
      // through here and NOT through _loadFavorites (a catalog reload only
      // happens when the selected playlist changed), so without this the
      // first list a user creates there would leave long-press still
      // toggling Favorites, and a deleted one would keep a picker pointed at
      // a row that no longer exists.
      _lists = lists;
    });

    // Returning from Settings must release an already-open preview
    // immediately. Re-enabling retunes the still-selected channel so the
    // setting takes effect without requiring an extra focus move.
    if (!channelPreviewEnabled) {
      _stopPreviewPlayback();
    } else if (!previewWasEnabled) {
      final shown = _previewShown.value;
      if (shown != null) _retunePreview(shown);
    }

    // Only reload playlist if it changed or forced, or if we have no channels
    // loaded AND no load is already producing them — "_allChannels.isEmpty"
    // alone is true for a first load's whole duration, and re-entry here
    // (addons-changed listener, settings return) used to stack a second full
    // pipeline on top of the running one. Forced/changed loads still start
    // immediately: bumping the ticket orphans the in-flight run's result.
    if (_selectedPlaylist != null &&
        (forceReload ||
            playlistChanged ||
            (_allChannels.isEmpty && _inFlightLoadTicket == null))) {
      // forceReload follows a settings edit — the user just changed this
      // provider, so a suppressed refresh must not outrank that.
      _loadPlaylist(_selectedPlaylist!, userRequested: forceReload);
    }
  }

  @override
  void didUpdateWidget(IptvResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Search filter when query changes. Debounced: the field live-filters on
    // every keystroke, and re-scanning a 10k-channel playlist per keypress is
    // what made typing janky. Clearing applies immediately so backing out of
    // a search feels instant.
    if (widget.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = widget.searchQuery;
      _searchDebounce?.cancel();
      if (widget.searchQuery.isEmpty) {
        _applyFilters();
      } else {
        _searchDebounce = Timer(const Duration(milliseconds: 220), () {
          if (mounted) _applyFilters();
        });
      }
    }
  }

  Timer? _searchDebounce;

  @override
  void dispose() {
    _sourceCountsDebounce?.cancel();
    _androidRecStateDebounce?.cancel();
    LiveRecordingService.schedulesRevision.removeListener(_onSchedulesChanged);
    DesktopRecordingService.instance.revision.removeListener(
      _onDesktopRecordingChanged,
    );
    if (widget.isTelevision) {
      WidgetsBinding.instance.removeObserver(this);
      MainPageBridge.removeTvSidebarFocusListener(_onTvSidebarFocusChanged);
    }
    StremioService.instance.removeAddonsChangedListener(
      _onStremioAddonsChanged,
    );
    IptvChannelOrderSignal.revision.removeListener(_onChannelOrderChanged);
    _searchDebounce?.cancel();
    _contentTypeDebounce?.cancel();
    _loadTicker?.cancel();
    _maintenanceChipTimer?.cancel();
    _chipShowTimer?.cancel();
    _chipHideTimer?.cancel();
    _scrollController.dispose();
    _playlistFilterFocusNode.dispose();
    _categoryFilterFocusNode.dispose();
    _contentTypeFocusNode.dispose();
    _previewShown.dispose();
    _previewShowing.dispose();
    _previewEpoch.dispose();
    _previewStreamUrl.dispose();
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// The error screen's Retry. Re-reads the stored playlists before loading:
  /// the in-memory record's connection authority can be stale — saving IPTV
  /// sources anywhere (the main Settings page included) rewrites the whole
  /// collection and bumps EVERY source's authorization revision, not just the
  /// edited one — and replaying the same object can then never succeed
  /// ("Connection authority changed" on every press).
  Future<void> _retryLoad() async {
    final current = _selectedPlaylist;
    if (current == null) return;
    var target = current;
    if (!current.isVirtual) {
      try {
        final stored = await StorageService.getIptvPlaylists(
          forSettings: false,
        );
        final byId = {for (final p in stored) p.id: p};
        if (!mounted) return;
        setState(() {
          // Refresh every real entry the rail holds too — they were all
          // invalidated by the same collection write, so a tap on a sibling
          // source would otherwise fail the same way.
          _playlists = [
            for (final p in _playlists)
              if (p.isVirtual) p else byId[p.id] ?? p,
          ];
          target = byId[current.id] ?? current;
          _selectedPlaylist = target;
        });
      } catch (_) {
        // Re-read failed; retry with the in-memory record. _loadPlaylist
        // lands any failure back in this same error state.
      }
    }
    await _loadPlaylist(target, userRequested: true);
  }

  /// [userRequested] marks a load the user explicitly asked for (the error
  /// screen's Retry, a settings round-trip). Such a load ignores the
  /// interrupted-refresh backoff — that guard exists to stop the page from
  /// re-running a refresh the device did not survive, not to override someone
  /// deliberately asking for fresh data.
  Future<void> _loadPlaylist(
    IptvPlaylist playlist, {
    bool userRequested = false,
  }) async {
    final ticket = ++_loadTicket;
    _inFlightLoadTicket = ticket;
    try {
      await _loadPlaylistInner(playlist, ticket, userRequested: userRequested);
    } catch (e, st) {
      // This method is fired-and-forgotten from initState, dropdowns and
      // Retry, and there is no zone guard above it — an escape here used to
      // vanish silently, leaving `_isLoading = true` and the 1 Hz status
      // ticker running forever: a permanent fake spinner. Land every failure
      // (DB open, SQL, a malformed stored playlist) in the real error state,
      // which has a Retry.
      debugPrint('IPTV: playlist load failed: $e\n$st');
      if (mounted && ticket == _loadTicket) {
        IptvEpgService.instance.clearM3uEpgContext();
        _endLoadStatus();
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _errorMessage = 'Could not load this playlist.\n$e';
        });
        _consumeContentFocusRequest();
      }
    } finally {
      if (_inFlightLoadTicket == ticket) _inFlightLoadTicket = null;
    }
  }

  Future<void> _loadPlaylistInner(
    IptvPlaylist playlist,
    int ticket, {
    bool userRequested = false,
  }) async {
    _lastProgressiveApply = null;
    _beginLoadStatus();
    // A lingering refresh chip belongs to the outgoing playlist.
    _chipShowTimer?.cancel();
    _chipHideTimer?.cancel();
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _errorMessage = null;
      _allChannels = [];
      _filteredChannels = [];
      _categories = [];
      _selectedCategory = null;
      // A fresh load may seed a landing category again; the outgoing
      // playlist's explicit pick doesn't carry over.
      _categoryManuallyChosen = false;
      _landingSeedArmed = true;
      _chipState = _CatalogChipState.hidden;
      _chipOwner = _ChipOwner.none;
      _dbSnapshot = null;
      _dbGroupCounts = const {};
      // The outgoing catalog's instances are no use to the incoming one.
      _dbInstanceCache.clear();
      _dbInstanceCacheKey = null;
      // Positions belong to the outgoing playlist's URLs.
      _progressByUrl = {};
      // An open schedule belongs to the outgoing playlist too.
      _scheduleChannel = null;
    });

    // Retire the outgoing catalog's focus nodes AFTER the rebuild that
    // unmounts their rows. Disposing them here — while the old rows are still
    // mounted (the setState above only marks dirty) — would unfocus the
    // primary node into a scope that next frame has zero focusable children:
    // the remote goes dead on the spinner, which on TV reads as a freeze.
    // (Debug builds also assert "used after being disposed".) The map is
    // cleared NOW so new rows mint fresh nodes; the old nodes' dispose runs
    // post-frame, by which point the rebuild has detached them all.
    final outgoingNodes = List<FocusNode>.of(_cardFocusNodes.values);
    final contentHadFocus = outgoingNodes.any((n) => n.hasFocus);
    _cardFocusNodes.clear();
    _detachedRows.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in outgoingNodes) {
        node.dispose();
      }
    });
    // If the user was in the grid when this reload started (content-type
    // switch, post-playback refresh), put them back in it when the new rows
    // land — only rail-initiated switches used to re-home, leaving every
    // other path DPAD-dead.
    if (contentHadFocus) _focusContentAfterLoad = true;
    // The stage's channel belongs to the outgoing playlist.
    _clearPreview();

    // Serve-stale-while-revalidate: network-backed catalogs (Xtream logins,
    // M3U URLs) render their stored rows instantly — no spinner, works
    // offline — then refresh in the background. First-ever loads (nothing
    // ingested yet) fall through to the blocking path below.
    final contentType = _selectedContentType;
    final cacheKey = IptvCatalogKey.forPlaylist(playlist, contentType);

    // ── DB-catalog path ────────────────────────────────────────────────────
    // Cacheable catalogs live in iptv_catalog.db: present the stored rows
    // (paged, constant memory), revalidate in the background when stale.
    if (cacheKey != null) {
      await IptvCatalogDb.open();
      if (!mounted || ticket != _loadTicket) return;
      final snap = IptvCatalogDb.snapshot(cacheKey);
      if (snap != null && snap.channelCount > 0) {
        await _presentDbCatalog(playlist, ticket, snap);
        if (!mounted || ticket != _loadTicket) return;
        // Everything heavy this catalog still needs — pending migration,
        // numbering adoption, an optional refresh — runs as one queued
        // background pipeline that decides for itself what is still required.
        // Started here rather than awaited: the list is already on screen and
        // none of it changes what the user sees.
        unawaited(
          _runCatalogMaintenance(
            playlist,
            contentType,
            cacheKey,
            ticket,
            userRequested: userRequested,
          ),
        );
        return;
      }
      // Never ingested (fresh install / brand-new playlist): fall through to
      // the network fetch below — the parse worker ingests it and hands back
      // a receipt, which _presentCatalog routes to the DB path.
    }

    // Determine source: favorites store, Stremio addon, XC API, local file,
    // or URL
    final IptvParseResult result;
    if (playlist.isFavorites) {
      result = await _buildListResult(StorageService.iptvFavoritesListId);
    } else if (playlist.isCustomList) {
      result = await _buildListResult(playlist.customListId!);
    } else if (playlist.isContinueWatching) {
      result = await _buildContinueResult();
    } else if (playlist.isStremioAddon) {
      final addonId = StremioIptvService.addonIdFromPlaylist(playlist);
      result = addonId == null
          ? const IptvParseResult(
              channels: [],
              categories: [],
              error: 'Broken addon playlist',
            )
          // Progressive: the first catalog page renders as soon as it lands
          // and the list keeps growing batch by batch; switching playlists
          // (or leaving the page) cancels the rest of the walk.
          : await StremioIptvService.instance.fetchChannels(
              addonId,
              isCancelled: () => !mounted || ticket != _loadTicket,
              onProgress: (channels, categories) =>
                  _applyProgressiveBatch(ticket, channels, categories),
            );
    } else if (playlist.isLocalFile) {
      result = await _iptvService.parseContent(playlist.content!);
    } else {
      // First-ever load of a cacheable catalog included: the whole-catalog
      // WRITE (parse+ingest) runs behind the process-wide gate INSIDE the
      // service — so it still can't overlap the previous page's surviving
      // adoption or refresh — but the network download no longer holds the
      // gate. Wrapping the entire fetch here used to queue every other
      // catalog job behind up to two minutes of a slow server.
      result = await _fetchCatalogFromNetwork(playlist, contentType, ticket);
    }

    if (!mounted || ticket != _loadTicket) return;
    _onLoadPhase(ticket, IptvLoadPhases.preparing);

    if (result.hasError) {
      // The context lifecycle follows leaving the playlist, not load
      // success: a failed switch must still drop the previous playlist's
      // guide index (memory + wrong capability answers for its URLs).
      IptvEpgService.instance.clearM3uEpgContext();
      _endLoadStatus();
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = result.error;
      });
      // A rail-initiated switch that errored must still leave the rail: the
      // error (with its Retry) lives in the content pane, and stranding
      // focus on the collapsing rail would trap DPAD. Falls back to the
      // in-pane filter row (channels are empty here).
      _consumeContentFocusRequest();
      return;
    }

    await _presentCatalog(playlist, ticket, result, cacheKey: cacheKey);

    // A first-ever ingest just wrote this catalog, so there is no numbering to
    // adopt and nothing to refresh — but a database that has never been
    // migrated still needs its version stamp and number index. Deliberately
    // last, after that ingest has finished, so the two never overlap.
    if (cacheKey != null && mounted && ticket == _loadTicket) {
      unawaited(
        IptvCatalogDb.runExclusive(
          () => _runPendingMigrations(cacheKey, ticket),
        ),
      );
    }
  }

  /// Bind a loaded catalog to the view: favorites migration, list swap,
  /// progress bars, warning surfacing, filters, EPG context. Shared by the
  /// network path and the stored-catalog path of [_loadPlaylist].
  /// [migrateFavorites] is false for snapshot/memory-cache passes — their
  /// URLs are not fresher than the favorites store's, so migrating against
  /// them is at best a no-op and at worst a backward walk.
  Future<void> _presentCatalog(
    IptvPlaylist playlist,
    int ticket,
    IptvParseResult result, {
    bool migrateFavorites = true,
    String? cacheKey,
  }) async {
    // A parse worker that ingested into the catalog DB hands back a receipt
    // instead of rows — presentation then reads from the DB.
    final receipt = result.ingest;
    if (receipt != null) {
      final snap = IptvCatalogDb.snapshot(receipt.catalogKey);
      if (snap != null && snap.channelCount > 0) {
        await _presentDbCatalog(
          playlist,
          ticket,
          snap,
          warning: result.warning,
          migrateFavorites: migrateFavorites,
        );
        return;
      }
    }
    // Virtual/local catalogs do not live in the SQL catalog. Give their live
    // rows a deterministic session number so every channel surface still has
    // a useful number; persisted network providers use the stable DB mapping.
    if (result.channels.any(
      (channel) => channel.isLive && channel.channelNumber == null,
    )) {
      final usedNumbers = <int>{
        for (final channel in result.channels)
          if (channel.isLive && channel.channelNumber != null)
            channel.channelNumber!,
      };
      var next = 0;
      int nextFreeNumber() {
        do {
          next++;
        } while (usedNumbers.contains(next));
        usedNumbers.add(next);
        return next;
      }

      result = IptvParseResult(
        channels: [
          for (final channel in result.channels)
            if (channel.isLive)
              IptvChannel(
                channelNumber: channel.channelNumber ?? nextFreeNumber(),
                name: channel.name,
                url: channel.url,
                logoUrl: channel.logoUrl,
                group: channel.group,
                duration: channel.duration,
                contentType: channel.contentType,
                attributes: channel.attributes,
                httpHeaders: channel.httpHeaders,
              )
            else
              channel,
        ],
        categories: result.categories,
        error: result.error,
        warning: result.warning,
        epgUrl: result.epgUrl,
      );
    }
    // Migrate list memberships saved under older URL formats (e.g. before the
    // Xtream /live/ URL fix) to the freshly fetched URLs, and backfill the
    // presentation metadata of rows carried over from the pre-v5 favorites
    // table, then reload so the stars line up. (A list shelf's channels ARE
    // the store — nothing to migrate against.)
    if (migrateFavorites &&
        !playlist.isFavorites &&
        !playlist.isCustomList &&
        !playlist.isContinueWatching) {
      await StorageService.reconcileIptvFavoriteUrls(result.channels);
    }
    await _loadFavorites();
    if (!mounted || ticket != _loadTicket) return;

    // Focus nodes are created lazily per channel INSTANCE (identity-keyed,
    // never URL — duplicate URLs are legal and must not share a node) in the
    // grid's itemBuilder via _focusNodeFor.

    // Hidden-category rules apply on this materialized fallback too — for a
    // cacheable source it serves whenever the ingest didn't happen (database
    // unopenable, empty receipt, memory-cache hit), and presenting the raw
    // rows would bring every hidden category back for the session. [result]
    // itself stays unfiltered: the favorites reconcile above and the EPG
    // context below scan hidden rows in DB mode too.
    var channels = result.channels;
    if (playlist.isLocalFile) {
      channels = await StorageService.applyIptvCategoryChannelOrders(
        playlist.id,
        channels,
      );
      if (!mounted || ticket != _loadTicket) return;
    } else if (cacheKey != null) {
      channels = IptvCatalogDb.applyCategoryChannelOrders(cacheKey, channels);
    }
    var categories = result.categories;
    if (playlist.isLocalFile) {
      categories = await applyStoredLocalCategoryOrder(playlist.id, categories);
      if (!mounted || ticket != _loadTicket) return;
      _hiddenCategories = const {};
    } else if (cacheKey == null) {
      // Virtual/addon sources have no durable order or hidden-category rules.
      _hiddenCategories = const {};
    } else {
      categories = IptvCatalogDb.applyCategoryOrder(cacheKey, categories);
      categories = _withoutHidden(cacheKey, categories);
      if (_hiddenCategories.isNotEmpty) {
        channels = [
          for (final channel in channels)
            if (!_hiddenCategories.contains(channel.group)) channel,
        ];
      }
    }

    _endLoadStatus();
    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
      _allChannels = channels;
      _categories = categories;
      // The selected category can be one the hidden set just removed — fall
      // back to All rather than pinning the filter to a chip that no longer
      // exists (the DB path does the same).
      if (_selectedCategory != null &&
          !categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
      _selectedCategory ??= _landingCategory(
        playlist.isLocalFile
            ? IptvCatalogKey.forLocalCategoryOrder(playlist.id)
            : cacheKey,
        categories,
      );
      // Disarmed even when the seed declined (search active, keyless
      // source): only the load's first present gets the chance.
      _landingSeedArmed = false;
      // This present is the materialized fallback — if a previous load left a
      // DB snapshot behind (e.g. the fresh fetch's receipt came back empty
      // while an older generation was still pinned), keeping it would split
      // the view's brain: _applyFilters would build facades over the dead
      // generation while _allChannels holds these rows, and every faulted row
      // would degrade to a placeholder.
      _dbSnapshot = null;
      _dbGroupCounts = const {};
    });

    // After the rows exist, not before: _loadProgress setStates too, and
    // running it first would paint one extra frame against an empty list.
    // The bars simply appear a frame later.
    await _loadProgress(ticket, channels);
    if (!mounted || ticket != _loadTicket) return;

    // Surface non-fatal degradation (e.g. categories unavailable) so missing
    // groups don't look like deleted channels.
    if (result.warning != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.warning!)));
    }

    _applyFilters();
    // Kept for settings round-trips: an EPG-URL edit re-runs the guide
    // context against this result without refetching the whole playlist.
    _lastLoadResult = result;
    _updateEpgContext(playlist, result, ticket);
    _consumeContentFocusRequest();
  }

  /// Local files bypass the catalog-backed load path, but their category-list
  /// order intentionally lives in the same profile-scoped database. Opening it
  /// here makes cold loads and the first load after a profile switch reliable.
  /// The database is optional for playback: if its cache cannot be opened, the
  /// provider order is returned and the local playlist still renders.
  @visibleForTesting
  static Future<List<String>> applyStoredLocalCategoryOrder(
    String playlistId,
    Iterable<String> categories,
  ) async {
    final baseline = categories.toList(growable: false);
    try {
      await IptvCatalogDb.open();
    } catch (error) {
      debugPrint(
        'IPTV: local category-order database unavailable; using provider '
        'order ($error)',
      );
      return baseline;
    }
    return IptvCatalogDb.applyCategoryOrder(
      IptvCatalogKey.forLocalCategoryOrder(playlistId),
      baseline,
    );
  }

  /// Bind a DB-backed catalog to the view: [_allChannels] and
  /// [_filteredChannels] become [DbChannelList] facades that page from SQL.
  /// The DB-mode counterpart of [_presentCatalog]'s list swap.
  Future<void> _presentDbCatalog(
    IptvPlaylist playlist,
    int ticket,
    CatalogSnapshot snap, {
    String? warning,
    bool migrateFavorites = false,
  }) async {
    if (migrateFavorites) {
      // Worker-side scan against the catalog rows — never a facade walk on
      // this isolate.
      await StorageService.reconcileIptvFavoriteUrlsForCatalog(snap.catalogKey);
    }
    await _loadFavorites();
    if (!mounted || ticket != _loadTicket) return;

    // Off-isolate: this GROUP BY scans the whole generation, synchronously
    // ran in exactly the turn that builds the first frame.
    final groups = await IptvCatalogDb.groupsAsync(snap);
    if (!mounted || ticket != _loadTicket) return;
    // Provider category list when the panel served one (its order is the
    // chips' order today); groups derived from the rows otherwise (M3U).
    final categories = _deriveCategories(snap, groups);
    final counts = <String, int>{
      for (final g in groups)
        if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
    };

    _endLoadStatus();
    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
      _dbSnapshot = snap;
      _dbGroupCounts = counts;
      _allChannels = _makeDbList(snap);
      _categories = categories;
      if (_selectedCategory != null &&
          !categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
      _selectedCategory ??= _landingCategory(snap.catalogKey, categories);
      _landingSeedArmed = false;
    });

    if (warning != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
    }

    _applyFilters();
    final displayed = IptvParseResult(
      channels: _allChannels,
      categories: categories,
      epgUrl: snap.epgUrl,
    );
    _lastLoadResult = displayed;
    _updateEpgContext(playlist, displayed, ticket);
    _consumeContentFocusRequest();
    // A first-time source reaches here via a blocking ingest with NO success
    // chip — the rail count for it must not wait for a later refresh.
    _recomputeSourceCounts();
  }

  /// [categories] with the user's hidden ones removed — and, as a side
  /// effect, [_hiddenCategories] re-read for [catalogKey]. The ONE place the
  /// list-filtering semantics live: the DB present/revalidate sites (via
  /// [_deriveCategories]), the materialized fallback and the in-player picker
  /// all route through it, so a change here can't split them.
  List<String> _withoutHidden(String catalogKey, List<String> categories) {
    _hiddenCategories = IptvCatalogDb.hiddenGroups(catalogKey);
    if (_hiddenCategories.isEmpty) return categories;
    return [
      for (final c in categories)
        if (!_hiddenCategories.contains(c)) c,
    ];
  }

  /// The category list the chips/dropdown show, with the user's hidden
  /// categories removed — and, as a side effect, [_hiddenCategories] brought
  /// up to date for [snap].
  ///
  /// [groups] comes from a query that already excludes hidden rows, so the
  /// M3U path (categories derived from the rows) needs no filtering; only the
  /// provider's verbatim list does. Both paths are here so every present /
  /// revalidate site derives the list the same way.
  List<String> _deriveCategories(
    CatalogSnapshot snap,
    List<CatalogGroup> groups,
  ) {
    final categories = _withoutHidden(snap.catalogKey, snap.categories);
    if (snap.categories.isEmpty) {
      return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, [
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!,
      ]);
    }
    return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, categories);
  }

  DbChannelList _makeDbList(
    CatalogSnapshot snap, {
    String? group,
    String? search,
  }) {
    final ticket = _loadTicket;
    return DbChannelList(
      snap,
      group: group,
      search: search,
      onPageLoaded: (page) => _loadPageProgress(ticket, page),
      onEvicted: _retireEvictedInstances,
      instanceCache: _instanceCacheFor(snap),
    );
  }

  /// The shared instance cache for [snap]'s generation, cleared when the
  /// catalog or generation changes so a stale instance (old data) can never
  /// be reused.
  LinkedHashMap<int, IptvChannel> _instanceCacheFor(CatalogSnapshot snap) {
    final key = '${snap.catalogKey}#${snap.generation}';
    if (_dbInstanceCacheKey != key) {
      _dbInstanceCache.clear();
      _dbInstanceCacheKey = key;
    }
    return _dbInstanceCache;
  }

  /// Progress bars for a freshly faulted page — the DB-mode replacement for
  /// [_loadProgress]'s whole-catalog scan. Fired synchronously during a page
  /// fault (possibly mid-build), so all state changes happen after the
  /// storage read's async gap.
  void _loadPageProgress(int ticket, List<IptvChannel> page) {
    final onDemand = [
      for (final channel in page)
        if (!channel.isLive && channel.contentType != 'series') channel.url,
    ];
    if (onDemand.isEmpty) return;
    unawaited(
      StorageService.getIptvProgressForUrls(onDemand).then((progress) {
        if (!mounted || ticket != _loadTicket || progress.isEmpty) return;
        setState(() => _progressByUrl = {..._progressByUrl, ...progress});
      }),
    );
  }

  /// An evicted page's instances can never be handed out again — retire
  /// their focus nodes. Attached or focused nodes are kept (their rows are
  /// still built); the next full reload sweeps them as always. Detachment
  /// comes from the row's own dispose report ([_detachedRows]) — never from
  /// node.context, which stays non-null forever after the first attach.
  void _retireEvictedInstances(List<IptvChannel> evicted) {
    for (final channel in evicted) {
      final node = _cardFocusNodes[channel];
      if (node == null || !_detachedRows.contains(channel) || node.hasFocus) {
        continue;
      }
      _detachedRows.remove(channel);
      _cardFocusNodes.remove(channel)?.dispose();
    }
  }

  /// Catalogs at or above this many rows never refresh on their own.
  ///
  /// Refreshing one means downloading the provider's entire response, decoding
  /// it and ingesting a fresh generation — the single heaviest thing this page
  /// does, and at 50k channels heavy enough that it is what the weakest boxes
  /// die on. Suppressing an interrupted refresh only stops the immediate
  /// retry; it does not make the operation itself affordable, so above this
  /// size it stops being something the page decides to do unprompted. The
  /// stored catalog keeps serving, and Settings → the playlist → Refresh
  /// remains the deliberate, user-chosen way to pull a fresh one.
  static const _autoRefreshRowCeiling = 20000;

  /// Whether a stale DB-backed catalog may refresh itself right now. Pure, so
  /// the policy can be tested without standing up the page.
  @visibleForTesting
  static bool shouldAutoRevalidate({
    required int channelCount,
    required int ageMs,
    required bool userRequested,
    required bool interrupted,
  }) {
    if (ageMs <= _dbCatalogTtl.inMilliseconds) return false;
    // Asking for this load explicitly overrides both guards below — they exist
    // to stop the page choosing to do something expensive, not to refuse the
    // user.
    if (userRequested) return true;
    if (channelCount >= _autoRefreshRowCeiling) return false;
    return !interrupted;
  }

  /// Every heavy background job this catalog needs, run STRICTLY ONE AT A
  /// TIME: pending migration, then numbering adoption, then an optional
  /// refresh.
  ///
  /// Serialization is the point. Each stage is a whole-catalog job that scans
  /// rows and takes the database write lock, and firing them independently
  /// meant two workers grinding over the same 50k rows and contending for that
  /// lock on the very first upgraded open — recreating the overlapping-heavy-
  /// work condition all of this exists to remove. Ordering also saves real
  /// work: migration numbers the rows in catalog order, so the adoption that
  /// follows confirms those numbers instead of rewriting 50k of them.
  Future<void> _runCatalogMaintenance(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket, {
    required bool userRequested,
  }) async {
    // Let the page settle before taking the gate. Nothing on screen waits for
    // any of this, and starting whole-catalog work while the list is still
    // painting its first rows, resolving EPG and loading logos is what tips a
    // weak box over. Deliberately OUTSIDE the gate: holding it through an idle
    // wait would make a foreground load queue behind nothing happening.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || ticket != _loadTicket) return;

    // Process-wide, not just within this page: a previous page's workers keep
    // running after it is gone, and two 50k scans at once is the exact
    // condition being designed out. Whether each stage is still NEEDED is
    // decided inside the gate, against the database as it is by then — a
    // pipeline queued behind one that already did the work finds nothing to do
    // and costs a few indexed reads.
    final shouldRefresh = await IptvCatalogDb.runExclusive(() async {
      if (!mounted || ticket != _loadTicket || !IptvCatalogDb.isOpen) {
        return false;
      }
      // Decided BEFORE the work so the chip can be scheduled up front, and so
      // a launch with nothing outstanding stays completely silent — this is
      // one-time work, and every subsequent launch must say nothing at all.
      final snapBefore = IptvCatalogDb.snapshot(cacheKey);
      final willNumber =
          snapBefore != null &&
          snapBefore.channelCount > 0 &&
          snapBefore.hasLiveChannels &&
          (!IptvCatalogDb.hasNumberingSource(playlist.id) ||
              snapBefore.hasUnnumberedLiveChannels) &&
          !IptvCatalogDb.adoptionRecentlyFailed(playlist.id);
      final narrate = IptvCatalogDb.hasPendingMigrations || willNumber;
      if (narrate) _scheduleMaintenanceChip(ticket);

      var numbersMoved = await _runPendingMigrations(cacheKey, ticket);
      if (!mounted || ticket != _loadTicket) {
        _finishMaintenanceChip(narrate: narrate, numbersMoved: false);
        return false;
      }

      final snap = IptvCatalogDb.snapshot(cacheKey);
      if (snap == null || snap.channelCount == 0) {
        _finishMaintenanceChip(narrate: narrate, numbersMoved: numbersMoved);
        return false;
      }

      final needsNumbering =
          snap.hasLiveChannels &&
          (!IptvCatalogDb.hasNumberingSource(playlist.id) ||
              snap.hasUnnumberedLiveChannels) &&
          !IptvCatalogDb.adoptionRecentlyFailed(playlist.id);
      if (needsNumbering) {
        numbersMoved =
            await _adoptNumbering(playlist, cacheKey, ticket) || numbersMoved;
        if (!mounted || ticket != _loadTicket) {
          _finishMaintenanceChip(narrate: narrate, numbersMoved: false);
          return false;
        }
      }
      _finishMaintenanceChip(narrate: narrate, numbersMoved: numbersMoved);

      // Re-read staleness too: the catalog may have been refreshed by the
      // pipeline this one queued behind.
      final current = IptvCatalogDb.snapshot(cacheKey) ?? snap;
      final age = DateTime.now().millisecondsSinceEpoch - current.ingestedAt;
      if (!shouldAutoRevalidate(
        channelCount: current.channelCount,
        ageMs: age,
        userRequested: userRequested,
        interrupted: IptvCatalogDb.revalidateInterrupted(cacheKey),
      )) {
        return false;
      }
      return true;
    });
    // Network work must not hold the maintenance queue that profile switches
    // drain. The service pins the connection and checks ownership again inside
    // the ingest queue before launching its worker.
    if (shouldRefresh &&
        !_revalidateSuperseded(playlist, contentType, ticket)) {
      await _revalidateDbCatalog(playlist, contentType, cacheKey, ticket);
    }
  }

  /// Narrate the guide download — the longest single background job, and
  /// until now completely silent.
  ///
  /// Lowest chip priority on purpose: news about the channel list (a refresh,
  /// or the one-time numbering pass) always outranks news about the guide.
  /// Throttled to whole megabytes rather than every chunk, since the chip is
  /// small and a digit flickering ten times a second reads as broken.
  void _onGuidePhase(int ticket, int? bytes, int? totalBytes) {
    if (!mounted || ticket != _loadTicket || bytes == null) return;
    final mb = bytes ~/ (1024 * 1024);
    if (mb == _lastGuideMb) return;
    _lastGuideMb = mb;
    if (mb == 0) return; // nothing worth announcing for a small guide
    final label = loadBytesLabel(bytes, totalBytes);
    _showChip(
      _CatalogChipState.updating,
      label == null ? 'Loading TV guide…' : 'Loading TV guide… $label',
      owner: _ChipOwner.guide,
    );
  }

  int _lastGuideMb = -1;

  /// Announce the one-time library preparation — but only if it lasts long
  /// enough to be worth a word. Migration is normally ~45ms, and a chip that
  /// flashes for one frame is noise, so this borrows the refresh chip's
  /// delayed-show trick.
  void _scheduleMaintenanceChip(int ticket) {
    _maintenanceChipTimer?.cancel();
    _maintenanceChipTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || ticket != _loadTicket) return;
      _showChip(
        _CatalogChipState.updating,
        'Preparing channel numbers…',
        owner: _ChipOwner.maintenance,
      );
    });
  }

  /// Close out the maintenance narration.
  ///
  /// [numbersMoved] is the whole reason this exists: when numbers actually
  /// change, every row's label gains a "CH n" prefix at once, and an
  /// unexplained mutation is worse than a slow one. When nothing moved, the
  /// chip simply goes away without ever claiming something happened.
  void _finishMaintenanceChip({
    required bool narrate,
    required bool numbersMoved,
  }) {
    _maintenanceChipTimer?.cancel();
    if (!narrate) return;
    if (numbersMoved) {
      _showChip(
        _CatalogChipState.success,
        'Channel numbers ready',
        autoHide: const Duration(milliseconds: 2200),
        owner: _ChipOwner.maintenance,
      );
      return;
    }
    _hideChipIfOwned(_ChipOwner.maintenance);
  }

  /// Apply any pending catalog-DB upgrade in the background, then show the
  /// result. Never rethrows: a migration that fails leaves rows exactly as
  /// they were (its transaction rolls back), and the page must keep working —
  /// throwing here would strand it on the spinner forever.
  Future<bool> _runPendingMigrations(String cacheKey, int ticket) async {
    try {
      final applied = await IptvCatalogDb.ensureMigrations();
      if (!applied || !mounted || ticket != _loadTicket) return false;
      // Rows presented before the backfill landed hold null numbers; re-fault
      // them so the numbers show up. Skipped entirely when this load already
      // presented after the migration, or moved on to another catalog.
      if (_dbSnapshot?.catalogKey != cacheKey) return true;
      final fresh = IptvCatalogDb.snapshot(cacheKey);
      if (fresh != null) _rebuildDbFacades(fresh);
      return true;
    } catch (e) {
      debugPrint('IptvResultsView: catalog migration failed: $e');
    }
    return false;
  }

  /// Give stored live rows durable numbers, derived on a worker from the
  /// catalog DB. Usually this creates a missing namespace; it also fills gaps
  /// when a classifier change makes an existing unnumbered row live.
  ///
  /// The path this replaces refetched the ENTIRE provider catalog just to
  /// establish the namespace — on a 50k-channel panel a full download, 50k
  /// materialized channels and a second 50k-row generation, re-run on every
  /// visit until one refresh happened to succeed. Nothing about it needed the
  /// network: the rows were already on disk.
  ///
  /// Only ever called from inside [_runCatalogMaintenance]'s exclusivity gate.
  /// A network refresh may follow after that gate is released. It must not queue any
  /// further maintenance itself — that would wait on a gate its own caller is
  /// holding.
  Future<bool> _adoptNumbering(
    IptvPlaylist playlist,
    String cacheKey,
    int ticket,
  ) async {
    try {
      final corrected = await IptvCatalogDb.adoptNumbering(
        catalogKey: cacheKey,
        sourceKey: playlist.id,
      );
      if (!mounted || ticket != _loadTicket) return false;
      // Adoption normally confirms the numbers the v2 backfill already wrote,
      // in which case the rows on screen are correct and rebuilding them would
      // cost focus and scroll for nothing. Relinking an archived namespace or
      // filling a newly-live row is a real correction and must repaint.
      if (corrected > 0) {
        final fresh = IptvCatalogDb.snapshot(cacheKey);
        if (fresh != null) _rebuildDbFacades(fresh);
        return true;
      }
    } catch (e) {
      // Backed off inside adoptNumbering; the catalog is untouched and the
      // rows keep their provisional numbers, so there is nothing to tell the
      // user about.
      debugPrint('IptvResultsView: numbering adoption failed: $e');
    }
    return false;
  }

  /// Re-fault the visible rows from the DB at the SAME generation — for a
  /// change written in place (channel numbers), where [DbChannelList.repin]
  /// does not apply because the generation never moved. Dropping the instance
  /// cache is what forces the stale [IptvChannel] objects to be rebuilt.
  void _rebuildDbFacades(CatalogSnapshot snap) {
    _dbInstanceCache.clear();
    _dbInstanceCacheKey = null;
    setState(() {
      _dbSnapshot = snap;
      _allChannels = _makeDbList(snap);
    });
    _applyFilters();
  }

  /// Background refresh for a DB-backed catalog. The fetch itself ingests a
  /// new generation on the worker; this decides what the UI does with it:
  /// identical content → re-pin the facades (zero disruption, the DB-mode
  /// equivalent of the identity reconcile), changed content → swap facades
  /// and run the same focus-repair the materialized path uses.
  Future<void> _revalidateDbCatalog(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket,
  ) async {
    final target = IptvCatalogDb.captureWriteTarget();
    IptvCatalogDb.markRevalidateStarted(cacheKey);
    try {
      await _revalidateDbCatalogInner(playlist, contentType, cacheKey, ticket);
    } finally {
      // Cleared on EVERY outcome this code can see, so a surviving marker
      // means one thing only: the device died mid-refresh. See
      // IptvCatalogDb.revalidateInterrupted.
      if (target != null) {
        try {
          await IptvCatalogDb.runWithWriteTarget(target, () async {
            IptvCatalogDb.markRevalidateFinished(cacheKey);
          });
        } catch (_) {
          // The old connection is retired; preserve its interrupted marker.
        }
      }
    }
  }

  Future<void> _revalidateDbCatalogInner(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket,
  ) async {
    _chipShowTimer?.cancel();
    _chipShowTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_revalidateSuperseded(playlist, contentType, ticket)) {
        _showChip(_CatalogChipState.updating, 'Updating list…');
      }
    });

    IptvParseResult result;
    try {
      result = await _fetchCatalogFromNetwork(playlist, contentType, ticket);
    } catch (e) {
      result = IptvParseResult(
        channels: const [],
        categories: const [],
        error: '$e',
      );
    }
    _chipShowTimer?.cancel();
    final chipWasVisible = _chipState == _CatalogChipState.updating;

    if (_revalidateSuperseded(playlist, contentType, ticket)) return;

    final receipt = result.ingest;
    if (result.hasError || (receipt == null && result.channels.isEmpty)) {
      _showChip(
        _CatalogChipState.failure,
        'Couldn\'t refresh — showing saved list',
        autoHide: const Duration(milliseconds: 3500),
      );
      return;
    }

    if (receipt == null) {
      // The DB flag flipped off while the fetch was in flight — present the
      // materialized result through the classic path.
      await _presentCatalog(playlist, ticket, result, cacheKey: cacheKey);
      return;
    }

    final old = _dbSnapshot;
    final fresh = IptvCatalogDb.snapshot(cacheKey);
    if (fresh == null) return;

    final oldFirstLive = old?.page(offset: 0, limit: 1, live: true);
    final freshFirstLive = fresh.page(offset: 0, limit: 1, live: true);
    final numberingAdded =
        oldFirstLive?.isNotEmpty == true &&
        oldFirstLive!.first.channelNumber == null &&
        freshFirstLive.isNotEmpty &&
        freshFirstLive.first.channelNumber != null;
    if (old != null &&
        fresh.contentDigest == old.contentDigest &&
        !numberingAdded) {
      // Channel rows unchanged: move the generation pin forward and keep
      // every resident page, instance, focus node and scroll offset exactly
      // as they are.
      final all = _allChannels;
      final filtered = _filteredChannels;
      if (all is DbChannelList) all.repin(fresh);
      if (filtered is DbChannelList) filtered.repin(fresh);
      _dbSnapshot = fresh;
      // The digest covers channel rows only — the provider's own category
      // LIST can still have changed (renamed/reordered categories). The
      // materialized path catches that with its listEquals check; mirror it
      // so the chips never go stale.
      if (!listEquals(fresh.categories, old.categories)) {
        final groups = await IptvCatalogDb.groupsAsync(fresh);
        if (_revalidateSuperseded(playlist, contentType, ticket)) return;
        final categories = _deriveCategories(fresh, groups);
        final selectedVanished =
            _selectedCategory != null &&
            !categories.contains(_selectedCategory);
        setState(() {
          _categories = categories;
          _dbGroupCounts = {
            for (final g in groups)
              if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
          };
          if (selectedVanished) _selectedCategory = null;
        });
        // Falling back to All changes the row set — rebuild the filter.
        if (selectedVanished) _applyFilters();
      }
      if (chipWasVisible) {
        _showChip(
          _CatalogChipState.success,
          'Up to date',
          autoHide: const Duration(milliseconds: 1800),
        );
      }
      return;
    }

    // Real change. Star migration first, against the fresh rows, so
    // favorites line up on the first paint — computed on a worker from the
    // catalog rows, never by walking a facade here.
    final freshAll = _makeDbList(fresh);
    await StorageService.reconcileIptvFavoriteUrlsForCatalog(fresh.catalogKey);
    await _loadFavorites();
    if (_revalidateSuperseded(playlist, contentType, ticket)) return;

    // Capture the DPAD position before the swap.
    IptvChannel? focusedChannel;
    for (final entry in _cardFocusNodes.entries) {
      if (entry.value.hasFocus) {
        focusedChannel = entry.key;
        break;
      }
    }
    final outgoing = _filteredChannels;
    final oldFilteredIndex = focusedChannel == null
        ? -1
        : (outgoing is DbChannelList
              ? (outgoing.indexOfInstance(focusedChannel) ?? -1)
              : outgoing.indexOf(focusedChannel));

    final added = (fresh.channelCount - (old?.channelCount ?? 0)).clamp(
      0,
      1 << 30,
    );

    final groups = await IptvCatalogDb.groupsAsync(fresh);
    if (_revalidateSuperseded(playlist, contentType, ticket)) return;
    final categories = _deriveCategories(fresh, groups);
    setState(() {
      _dbSnapshot = fresh;
      _dbGroupCounts = {
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
      };
      _allChannels = freshAll;
      _categories = categories;
      if (_selectedCategory != null &&
          !categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
    });
    _applyFilters();

    // Post-frame: repair focus if it fell to a bare scope, then retire the
    // outgoing generation's now-detached nodes — same rules and ordering as
    // the materialized revalidate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focusedChannel != null && ticket == _loadTicket) {
        final primary = FocusManager.instance.primaryFocus;
        final focusLost = primary == null || primary is FocusScopeNode;
        if (focusLost) {
          FocusNode? target;
          if (_filteredChannels.isNotEmpty) {
            final idx = oldFilteredIndex < 0
                ? 0
                : oldFilteredIndex.clamp(0, _filteredChannels.length - 1);
            final candidate = _filteredChannels[idx];
            if (_rowAttached(candidate)) target = _cardFocusNodes[candidate];
          }
          if (target == null) {
            for (final entry in _cardFocusNodes.entries) {
              if (_rowAttached(entry.key)) {
                target = entry.value;
                break;
              }
            }
          }
          (target ?? _playlistFilterFocusNode).requestFocus();
        }
      }
      final detached = [
        for (final entry in _cardFocusNodes.entries)
          if (_detachedRows.contains(entry.key) && !entry.value.hasFocus)
            entry.key,
      ];
      for (final channel in detached) {
        _detachedRows.remove(channel);
        _cardFocusNodes.remove(channel)?.dispose();
      }
    });
    WidgetsBinding.instance.scheduleFrame();

    // Guide rebind against the CURRENT stored configuration, mirroring the
    // materialized revalidate. No snapshot write — the DB is the store.
    final storedPlaylists = await StorageService.getIptvPlaylists(
      forSettings: false,
    );
    if (_revalidateSuperseded(playlist, contentType, ticket)) return;
    IptvPlaylist? storedPlaylist;
    for (final p in storedPlaylists) {
      if (p.id == playlist.id) {
        storedPlaylist = p;
        break;
      }
    }
    final displayed = IptvParseResult(
      channels: _allChannels,
      categories: _categories,
      epgUrl: fresh.epgUrl,
    );
    _lastLoadResult = displayed;
    if (storedPlaylist != null &&
        IptvCatalogKey.forPlaylist(storedPlaylist, contentType) == cacheKey) {
      _updateEpgContext(storedPlaylist, displayed, ticket, quiet: true);
    }

    _showChip(
      _CatalogChipState.success,
      added > 0 ? 'Updated • $added new' : 'List updated',
      autoHide: const Duration(milliseconds: 2200),
    );
  }

  /// One network fetch for the cacheable sources, with the content type
  /// captured by the caller — a background revalidate must fetch the type it
  /// was started for even if the user has since switched tabs.
  Future<IptvParseResult> _fetchCatalogFromNetwork(
    IptvPlaylist playlist,
    String contentType,
    int ticket,
  ) async {
    // Built once and shared by every branch below: a branch that forgets to
    // pass it silently loses its progress reporting, which is exactly how the
    // M3U path shipped dead.
    void report(String phase, {int? bytes, int? totalBytes}) =>
        _onLoadPhase(ticket, phase, bytes: bytes, totalBytes: totalBytes);

    bool isCurrent() =>
        mounted &&
        ticket == _loadTicket &&
        _selectedPlaylist?.id == playlist.id &&
        (!playlist.isXtreamCodes || _selectedContentType == contentType);

    if (playlist.isXtreamCodes) {
      final xcService = XtreamCodesService.instance;
      // `?? ''` and not `!`: isXtreamCodes only guarantees serverUrl.
      // A stored entry with no credentials used to TypeError on every page
      // open — unrecoverable without clearing app data. Empty credentials
      // fail the panel's auth instead, which lands in the normal error UI.
      // (IptvCatalogKey.forPlaylist and _updateEpgContext already treat the
      // same fields this way.)
      final username = playlist.username ?? '';
      final password = playlist.password ?? '';
      if (contentType == 'vod') {
        return xcService.fetchVodStreams(
          playlist.serverUrl!,
          username,
          password,
          onPhase: report,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
          isCurrent: isCurrent,
        );
      }
      if (contentType == 'series') {
        return xcService.fetchSeriesStreams(
          playlist.serverUrl!,
          username,
          password,
          onPhase: report,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
          isCurrent: isCurrent,
        );
      }
      return xcService.fetchLiveStreams(
        playlist.serverUrl!,
        username,
        password,
        numberingSourceKey: playlist.id,
        onPhase: report,
        connectionResourceId: playlist.connectionResourceId,
        connectionResourceRevision: playlist.connectionResourceRevision,
        isCurrent: isCurrent,
      );
    }
    return _iptvService.fetchPlaylist(
      playlist.url,
      numberingSourceKey: playlist.id,
      onPhase: report,
      connectionResourceId: playlist.connectionResourceId,
      connectionResourceRevision: playlist.connectionResourceRevision,
      isCurrent: isCurrent,
    );
  }

  /// True when a background revalidate's result no longer belongs on screen.
  /// The ticket covers playlist switches (they bump it synchronously), but a
  /// content-type switch clears the list and only bumps the ticket after its
  /// 350ms debounce — without the extra guards a revalidate completing in
  /// that window would resurrect the outgoing type's rows under the new
  /// type's layout.
  bool _revalidateSuperseded(
    IptvPlaylist playlist,
    String contentType,
    int ticket,
  ) =>
      !mounted ||
      ticket != _loadTicket ||
      _isLoading ||
      _selectedPlaylist?.id != playlist.id ||
      (playlist.isXtreamCodes && _selectedContentType != contentType);

  /// The blocking-load state. A bare spinner is indistinguishable from a hung
  /// app, and on a 50k panel this screen is held for several seconds — so it
  /// says which stage is running, carries a real number when one exists, and
  /// runs a clock so there is always something moving even when the stage
  /// itself is opaque (a buffered download, or the decode/ingest worker).
  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _loadPhase;
    final startedAt = _loadStartedAt;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

    final step = phase == null ? -1 : IptvLoadPhases.ordered.indexOf(phase);
    final stepLabel = step < 0
        ? null
        : 'Step ${step + 1} of ${IptvLoadPhases.ordered.length}';

    final meta = <String>[
      if (_loadBytesLabel != null) _loadBytesLabel!,
      if (elapsed.inSeconds > 0) formatLoadElapsed(elapsed),
    ].join('  ·  ');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              phase ?? 'Loading…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (stepLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                stepLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            // Only after the wait is genuinely long: saying this immediately
            // would make every quick load look slow.
            if (elapsed >= _slowLoadHint) ...[
              const SizedBox(height: 14),
              Text(
                'Large playlists can take a minute on TV devices.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Begin (or restart) the blocking-load status for a fresh load.
  void _beginLoadStatus() {
    _loadPhase = null;
    _loadBytes = null;
    _loadTotalBytes = null;
    _loadStartedAt = DateTime.now();
    _lastGuideMb = -1;
    _loadTicker?.cancel();
    // One repaint a second: enough for a clock and a byte counter to look
    // alive, cheap enough that a TV never notices it.
    _loadTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isLoading) {
        timer.cancel();
        return;
      }
      setState(() {});
    });
  }

  void _endLoadStatus() {
    _loadTicker?.cancel();
    _loadTicker = null;
  }

  /// Receives phase reports from the services. A changed PHASE repaints
  /// immediately (four times a load); byte updates only update the fields and
  /// ride the next tick.
  void _onLoadPhase(int ticket, String phase, {int? bytes, int? totalBytes}) {
    // A superseded load's fetch keeps running to completion; its reports must
    // not relabel the load that replaced it.
    if (!mounted || ticket != _loadTicket) return;
    // Only a BLOCKING load owns this display. A background revalidate runs the
    // same fetch under the same ticket, and its progress belongs in the status
    // chip, not in state the next spinner would inherit.
    if (!_isLoading) return;
    final phaseChanged = phase != _loadPhase;
    _loadPhase = phase;
    _loadBytes = bytes;
    _loadTotalBytes = totalBytes;
    if (phaseChanged && _isLoading) setState(() {});
  }

  @visibleForTesting
  static String formatLoadBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @visibleForTesting
  static String formatLoadElapsed(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// "12.4 / 50.0 MB" when the transfer is observable, "42.1 MB" when only the
  /// landed size is known, null when there is no honest number to show — a
  /// buffered fetch that has not landed yet must not imply progress it cannot
  /// measure.
  @visibleForTesting
  static String? loadBytesLabel(int? bytes, int? totalBytes) {
    if (bytes == null) return null;
    if (totalBytes != null && totalBytes > 0) {
      return '${formatLoadBytes(bytes)} / ${formatLoadBytes(totalBytes)}';
    }
    if (bytes == 0) return null;
    return formatLoadBytes(bytes);
  }

  String? get _loadBytesLabel => loadBytesLabel(_loadBytes, _loadTotalBytes);

  /// Whether a stage owning [incoming] may take the chip from [current].
  /// Pure, so the priority rule is testable without pumping the page.
  @visibleForTesting
  static bool chipClaimAllowed(int current, int incoming) =>
      incoming >= current;

  /// Priority ranks, exposed for the same reason.
  @visibleForTesting
  static int get chipRankNone => _ChipOwner.none.index;
  @visibleForTesting
  static int get chipRankGuide => _ChipOwner.guide.index;
  @visibleForTesting
  static int get chipRankMaintenance => _ChipOwner.maintenance.index;
  @visibleForTesting
  static int get chipRankRefresh => _ChipOwner.refresh.index;

  void _showChip(
    _CatalogChipState state,
    String message, {
    Duration? autoHide,
    _ChipOwner owner = _ChipOwner.refresh,
  }) {
    if (!mounted) return;
    // Every catalog ingestion that completes narrates a success chip — the
    // one choke point where a first-time source (or a background refresh)
    // has just written the snapshot the rail's counts read from.
    if (state == _CatalogChipState.success) _recomputeSourceCounts();
    // Outranked by whatever is already speaking: stay quiet rather than
    // stomping it.
    if (!chipClaimAllowed(_chipOwner.index, owner.index)) return;
    _chipOwner = owner;
    _chipHideTimer?.cancel();
    setState(() {
      _chipState = state;
      _chipMessage = message;
    });
    if (autoHide != null) {
      _chipHideTimer = Timer(autoHide, () {
        if (mounted && _chipState != _CatalogChipState.hidden) {
          setState(() => _chipState = _CatalogChipState.hidden);
        }
        _chipOwner = _ChipOwner.none;
      });
    }
  }

  /// Clear the chip only if [owner] still holds it — a stage that has been
  /// superseded must not blank the message that replaced it.
  void _hideChipIfOwned(_ChipOwner owner) {
    if (_chipOwner != owner) return;
    _chipHideTimer?.cancel();
    _chipOwner = _ChipOwner.none;
    if (mounted && _chipState != _CatalogChipState.hidden) {
      setState(() => _chipState = _CatalogChipState.hidden);
    }
  }

  /// The last successfully loaded parse result (same list instances the page
  /// renders — a couple of references, not a copy).
  IptvParseResult? _lastLoadResult;

  /// Activate (or clear) XMLTV guide data for the loaded playlist. Fire and
  /// forget: the list renders immediately, and rows re-render with their
  /// schedule affordances if/when the guide lands.
  ///
  /// Guide URL resolution, per playlist kind:
  /// - Plain M3U: user-configured epgUrl > the header's url-tvg > (when the
  ///   playlist is really an Xtream `get.php` export, i.e. its channel URLs
  ///   carry credentials) the panel's own xmltv.php.
  /// - Xtream (live view): user-configured epgUrl > the panel's xmltv.php.
  ///   This layers ON TOP of the per-stream get_short_epg endpoints — the
  ///   XMLTV index answers first, the endpoints cover anything it doesn't.
  ///   It's the same source TiviMate reads, so panels whose per-stream EPG
  ///   is broken/disabled (a real-world regular) still get a full guide.
  /// - Everything else (Stremio/favorites/continue): no guide context.
  void _updateEpgContext(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket, {
    // Suppress the user-facing failure hints (background revalidate re-runs
    // already had them surfaced by the foreground pass this visit).
    bool quiet = false,
  }) {
    final service = IptvEpgService.instance;
    _lastGuideMb = -1;
    final isPlainM3u =
        !playlist.isFavorites &&
        !playlist.isContinueWatching &&
        !playlist.isStremioAddon &&
        !playlist.isXtreamCodes;
    final isXtreamLive =
        playlist.isXtreamCodes && _selectedContentType == 'live';
    if (!isPlainM3u && !isXtreamLive) {
      service.clearM3uEpgContext();
      _hideChipIfOwned(_ChipOwner.guide);
      return;
    }
    // A user-configured guide URL beats every derived source.
    final manual = playlist.epgUrl?.trim();
    final hasManualUrl = manual != null && manual.isNotEmpty;
    String? epgUrl;
    if (hasManualUrl) {
      epgUrl = manual;
    } else if (isXtreamLive) {
      epgUrl = IptvEpgService.xmltvUrlFor(
        playlist.serverUrl!,
        playlist.username ?? '',
        playlist.password ?? '',
      );
    } else {
      epgUrl = result.epgUrl;
      if (epgUrl == null || epgUrl.trim().isEmpty) {
        // No configured or declared guide — an Xtream-export M3U can still
        // derive the panel's own xmltv.php from any channel's stream URL.
        // Such exports are homogeneous (every URL carries the credentials),
        // so a bounded sample decides. Bounding matters: the
        // channels list is a paging facade, and walking all of it here would
        // synchronously materialize the whole catalog on the UI isolate for
        // a plain M3U that derives nothing.
        final channels = result.channels;
        final Iterable<IptvChannel> probe = channels is DbChannelList
            ? channels.effectiveSnapshot.page(offset: 0, limit: 50, live: true)
            : channels;
        for (final channel in probe) {
          if (!channel.isLive) continue;
          final derived = IptvEpgService.xmltvUrlForChannelUrl(channel.url);
          if (derived != null) {
            epgUrl = derived;
            break;
          }
        }
      }
    }
    // Started in the ROOT zone on purpose. This is fire-and-forget work that
    // takes the maintenance gate for its catalog scan and guide ingest, and
    // one of its callers (the background refresh) is itself running inside
    // that gate — inheriting the caller's zone would make the gate re-entrant
    // for this long-lived job and let it run alongside the next queued one,
    // which is the overlap being designed out.
    Zone.root
        .run(
          () => service.setM3uEpgContext(
            playlistKey: playlist.id,
            epgUrl: epgUrl,
            channels: result.channels,
            // DB-backed view: the guide stores its rows in iptv_catalog.db and
            // binds URLs through the catalog instead of whole-playlist maps.
            dbCatalogKey: _dbSnapshot?.catalogKey,
            onPhase: (phase, {bytes, totalBytes}) =>
                _onGuidePhase(ticket, bytes, totalBytes),
          ),
        )
        .then((status) {
          // The guide is done one way or another — drop its chip if it is
          // still the one speaking.
          _hideChipIfOwned(_ChipOwner.guide);
          if (!mounted || ticket != _loadTicket) return;
          // Failure hints only for a guide the user configured themselves.
          // Header-derived url-tvg URLs are routinely dead in wild playlists —
          // those users never asked for EPG and got silent no-guide before;
          // nagging them on every load would be a regression.
          void hint(String message) {
            if (quiet || !hasManualUrl) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }

          switch (status) {
            case M3uEpgStatus.matched:
              // Capability changed: rebuild the rows so EPG-covered channels
              // gain the RIGHT-key/calendar affordance. The rail card refreshes
              // itself via the service's contextVersion listener.
              setState(() {});
            // The guide failing is otherwise invisible — rows just never grow
            // their affordances — and "EPG doesn't work" reports can't tell
            // the flavors apart. Say which one happened.
            case M3uEpgStatus.noMatch:
              hint(
                'TV guide loaded, but none of its channels matched this '
                'playlist (the ids and names don\'t line up).',
              );
            case M3uEpgStatus.noProgrammes:
              hint(
                'TV guide matched this playlist, but it has no programme '
                'data for the current period.',
              );
            case M3uEpgStatus.failed:
              hint('Couldn\'t load the TV guide — check the EPG URL.');
            case M3uEpgStatus.inactive:
              break;
          }
        })
        // The chain above had NO error handler: a throw anywhere in the
        // guide pipeline (isolate spawn under memory pressure, malformed
        // XMLTV, a BUSY SqliteException from a colliding write) became an
        // unhandled async rejection — and because the work deliberately runs
        // in the root zone, no caller-side guard could ever catch it either.
        // A failed guide load degrades to "no guide", exactly like the
        // status-carrying failures above.
        .catchError((Object e) {
          debugPrint('IPTV: guide context update failed: $e');
          _hideChipIfOwned(_ChipOwner.guide);
          if (!mounted || ticket != _loadTicket) return;
          if (!quiet && hasManualUrl) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Couldn\'t load the TV guide — check the EPG URL.',
                ),
              ),
            );
          }
        });
  }

  /// A page of Stremio channels landed while the catalog walk is still
  /// running. Batches are cumulative snapshots, so skipped intermediate ones
  /// lose nothing — throttle the repaints and let the next batch (or the
  /// final result) true everything up.
  void _applyProgressiveBatch(
    int ticket,
    List<IptvChannel> channels,
    List<String> categories,
  ) {
    if (!mounted || ticket != _loadTicket) return;
    final now = DateTime.now();
    final last = _lastProgressiveApply;
    final firstBatch = !_isLoadingMore;
    if (!firstBatch &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 300)) {
      return;
    }
    final wasFirstBatch = firstBatch;
    _lastProgressiveApply = now;
    _endLoadStatus();
    setState(() {
      _isLoading = false; // first batch swaps the spinner for real rows
      _isLoadingMore = true;
      _allChannels = channels;
      _categories = categories;
    });
    _applyFilters();
    // A Stremio source picked from the rail: hand focus to the content pane
    // once its first batch of rows is on screen (later batches keep focus).
    if (wasFirstBatch) _consumeContentFocusRequest();
  }

  /// Look up saved positions for the loaded list. Live channels can't have
  /// one, so a playlist with no on-demand items skips the read entirely —
  /// that's the overwhelmingly common case (a live-TV panel).
  Future<void> _loadProgress(int ticket, List<IptvChannel> channels) async {
    // Bars load per faulted page (_loadPageProgress); a full-list
    // refresh (post-playback) re-reads just the RESIDENT pages — the rows
    // that can be on screen.
    if (_dbSnapshot != null) {
      final all = _allChannels;
      final filtered = _filteredChannels;
      final resident = <IptvChannel>[
        if (all is DbChannelList) ...all.residentChannels(),
        if (filtered is DbChannelList) ...filtered.residentChannels(),
      ];
      final urls = <String>{
        for (final channel in resident)
          if (!channel.isLive && channel.contentType != 'series') channel.url,
      };
      if (urls.isEmpty) return;
      final progress = await StorageService.getIptvProgressForUrls(urls);
      if (!mounted || ticket != _loadTicket || progress.isEmpty) return;
      setState(() => _progressByUrl = {..._progressByUrl, ...progress});
      return;
    }

    final onDemand = [
      for (final channel in channels)
        // Series rows carry a sentinel (non-stream) URL — no position can
        // exist for it; their per-episode progress lives on the detail page.
        if (!channel.isLive && channel.contentType != 'series') channel.url,
    ];
    if (onDemand.isEmpty) {
      if (_progressByUrl.isNotEmpty && mounted && ticket == _loadTicket) {
        setState(() => _progressByUrl = {});
      }
      return;
    }

    final progress = await StorageService.getIptvProgressForUrls(onDemand);
    if (!mounted || ticket != _loadTicket) return;
    setState(() => _progressByUrl = progress);
  }

  /// Build the virtual "Continue watching" playlist. Like Favorites, the rows
  /// are replayed from metadata captured at play time rather than re-fetched,
  /// so they survive a provider that has since renumbered or expired.
  Future<IptvParseResult> _buildContinueResult() async {
    final items = await StorageService.getIptvContinueWatching();
    _continuePlaylistIds = {};
    final channels = <IptvChannel>[];
    // A series' episodes collapse to ONE row: items are most-recent-first, so
    // the first entry per (provider, series) wins and the rest are folded in.
    // Non-series items (movies/catchup) keep one row each, exactly as before.
    final seenSeries = <String>{};
    for (final item in items) {
      final seriesId = (item['seriesId'] as String?) ?? '';
      final originId = (item['playlistId'] as String?) ?? '';
      if (seriesId.isNotEmpty) {
        final groupKey = '$originId::$seriesId';
        if (!seenSeries.add(groupKey)) continue; // already have this series
        // A series sentinel URL, so a tap routes into the merged series page
        // (which resumes at the true next-up from the players' saved
        // positions) rather than playing one episode standalone. The origin
        // provider id is baked into the URL: Xtream series ids are per-provider
        // small integers, so two providers routinely share one — a plain
        // `xtream-series://<id>` would collide in the url-keyed row/focus/
        // origin bookkeeping and open the wrong show.
        final sentinelUrl = 'xtream-series://$originId/$seriesId';
        _continuePlaylistIds[sentinelUrl] = originId;
        final seriesName = (item['seriesName'] as String?)?.isNotEmpty == true
            ? item['seriesName'] as String
            : ((item['group'] as String?)?.isNotEmpty == true
                  ? item['group'] as String
                  : 'Unknown series');
        channels.add(
          IptvChannel(
            name: seriesName,
            url: sentinelUrl,
            logoUrl: (item['logoUrl'] as String?)?.isNotEmpty == true
                ? item['logoUrl'] as String
                : null,
            group: seriesName,
            contentType: 'series',
            attributes: {
              'series_id': seriesId,
              if (originId.isNotEmpty) 'series_playlist_id': originId,
            },
          ),
        );
        continue;
      }
      // Defensive cast, matching every other field in this loop: this is
      // decoded storage JSON, and one malformed entry (null/missing url)
      // must skip that row, not TypeError the whole shelf's build.
      final itemUrl = item['url'] as String?;
      if (itemUrl == null || itemUrl.isEmpty) continue;
      _continuePlaylistIds[itemUrl] = originId;
      channels.add(
        IptvChannel(
          name: (item['name'] as String?)?.isNotEmpty == true
              ? item['name'] as String
              : 'Unknown',
          url: itemUrl,
          logoUrl: (item['logoUrl'] as String?)?.isNotEmpty == true
              ? item['logoUrl'] as String
              : null,
          group: (item['group'] as String?)?.isNotEmpty == true
              ? item['group'] as String
              : null,
          // Always on-demand — live channels are never recorded — so the row
          // draws a poster and the "LIVE" dot stays off.
          contentType: 'vod',
          httpHeaders: StorageService.iptvFavoriteHeaders(item),
        ),
      );
    }
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()..sort();
    // Already ordered most-recently-watched first; leave it alone.
    return IptvParseResult(channels: channels, categories: categories);
  }

  /// Build a virtual list shelf (Favorites or a user list) from the stored
  /// membership. Metadata was captured when the channel was added, so no
  /// fetch is needed; Stremio-keyed URLs still resolve on focus/play exactly
  /// like anywhere else.
  Future<IptvParseResult> _buildListResult(String listId) async {
    final stored = await StorageService.getIptvListChannels(listId);
    final channels = stored.entries.map((entry) {
      final meta = entry.value;
      final name = (meta['name'] as String?) ?? '';
      final logoUrl = (meta['logoUrl'] as String?) ?? '';
      final group = (meta['group'] as String?) ?? '';
      return IptvChannel(
        channelNumber: (meta['channelNumber'] as num?)?.toInt(),
        name: name.isEmpty ? 'Unknown Channel' : name,
        url: entry.key,
        logoUrl: logoUrl.isEmpty ? null : logoUrl,
        group: group.isEmpty ? null : group,
        // Rows added before these were stored (and every row migrated
        // from the pre-v5 favorites table) fall back to live, which is
        // how they presented then; the reconcile pass backfills them the
        // first time their provider is opened.
        duration: (meta['duration'] as num?)?.toInt() ?? -1,
        contentType: meta['contentType'] as String?,
        attributes: {
          if ((meta['playlistId'] as String?)?.isNotEmpty ?? false)
            _kListOriginAttribute: meta['playlistId'] as String,
        },
        httpHeaders: StorageService.iptvFavoriteHeaders(meta),
      );
    }).toList();
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()..sort();
    return IptvParseResult(channels: channels, categories: categories);
  }

  void _applyFilters() {
    // DB-backed catalog: the filter IS the query — a new facade with the
    // category/search folded into its SQL. Same substring-over-name+group
    // semantics as searchChannels (the search_key column is the same
    // haystack IptvChannel.searchKey builds).
    final snap = _dbSnapshot;
    if (snap != null) {
      setState(() {
        _filteredChannels = _makeDbList(
          snap,
          group: _selectedCategory,
          search: widget.searchQuery.isEmpty ? null : widget.searchQuery,
        );
      });
      // A new facade mints new instances, so the outgoing filter's rows can
      // never be handed out again — their focus nodes would otherwise pile
      // up until the next full reload (the materialized path reuses
      // instances across filters and doesn't have this). Post-frame, after
      // the new rows are built: retire everything detached and unfocused.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final orphans = [
          for (final entry in _cardFocusNodes.entries)
            if (_detachedRows.contains(entry.key) && !entry.value.hasFocus)
              entry.key,
        ];
        for (final channel in orphans) {
          _detachedRows.remove(channel);
          _cardFocusNodes.remove(channel)?.dispose();
        }
      });
      return;
    }

    var channels = _allChannels;

    // Filter by category
    if (_selectedCategory != null) {
      channels = _iptvService.filterByCategory(channels, _selectedCategory);
    }

    // Filter by search query
    if (widget.searchQuery.isNotEmpty) {
      channels = _iptvService.searchChannels(channels, widget.searchQuery);
    }

    setState(() {
      _filteredChannels = channels;
    });
  }

  void _onPlaylistChanged(IptvPlaylist? playlist, {bool focusContent = false}) {
    if (playlist == null) return;
    if (playlist == _selectedPlaylist) {
      // Re-picking the current source shouldn't reload, but from the rail it
      // still means "take me to the list" — collapse the rail and focus the
      // already-loaded content instead of a dead OK press.
      if (focusContent) {
        _focusContentAfterLoad = true;
        _consumeContentFocusRequest();
      }
      return;
    }

    // A pending content-type load belongs to the outgoing playlist.
    _contentTypeDebounce?.cancel();
    // Honored by the present paths once the new list is on screen. Only the
    // rail/picker set it — a dropdown or programmatic switch keeps focus
    // where it was.
    _focusContentAfterLoad = focusContent;
    setState(() {
      _selectedPlaylist = playlist;
      _selectedCategory = null;
      if (playlist.isXtreamCodes) {
        _selectedContentType = 'live';
      }
    });

    _loadPlaylist(playlist);
  }

  /// Move DPAD focus into the content pane after a rail-initiated playlist
  /// switch, which collapses the source rail's overlay. Post-frame so the
  /// grid's first row (and its lazily-created focus node) exists; falls back
  /// to the in-pane filter row when the new catalog is empty or errored, so
  /// focus never strands on the collapsing rail.
  void _consumeContentFocusRequest() {
    if (!_focusContentAfterLoad) return;
    _focusContentAfterLoad = false;
    if (!widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_filteredChannels.isNotEmpty) {
        _focusNodeFor(_filteredChannels.first).requestFocus();
      } else {
        _playlistFilterFocusNode.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Timer? _contentTypeDebounce;

  void _onContentTypeChanged(String contentType) {
    if (contentType == _selectedContentType) return;

    setState(() {
      _selectedContentType = contentType;
      _selectedCategory = null;
      // The outgoing type's rows leave NOW, not when the debounced load
      // lands: they'd otherwise render for the debounce window under the new
      // type's layout flag (_showsPosterRows flips immediately), and a tap in
      // that window would play an item of a type the filter no longer shows.
      // Mirrors the reset _loadPlaylist performs; the spinner covers the gap
      // exactly as it did when the load was synchronous.
      _isLoading = true;
      // The spinner is up NOW but the load is 350ms away, so the status must
      // reset with it — otherwise this window renders the previous load's
      // phase and byte count against a stale start time, with the ticker
      // already stopped: frozen, wrong text rather than merely old.
      _beginLoadStatus();
      _allChannels = [];
      _filteredChannels = [];
      _categories = [];
      _dbSnapshot = null;
      _dbGroupCounts = const {};
      _progressByUrl = {};
      _scheduleChannel = null;
    });
    _clearPreview();

    // Debounced: the classic layout's toggle CYCLES Live → Movies → Series,
    // so reaching a non-adjacent type means passing through one the user
    // never wanted — a full playlist load (focus-node disposal, possibly a
    // multi-second uncached panel fetch) per intermediate step. Let the
    // selection settle first; only the type the user stops on loads. Short
    // enough to be imperceptible on a single direct pick (the TV dropdown
    // path).
    _contentTypeDebounce?.cancel();
    _contentTypeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_selectedPlaylist != null) {
        _loadPlaylist(_selectedPlaylist!);
      }
    });
  }

  void _onCategoryChanged(String? category) {
    _categoryManuallyChosen = true;
    setState(() => _selectedCategory = category);
    _applyFilters();
  }

  /// The category a fresh load should land on when nothing is picked yet:
  /// the saved default when it still exists in [categories], else the first
  /// category in display order — so the list opens on the user's #1 category
  /// rather than the provider's raw channel order. Null (land on All) when
  /// the user already picked a chip this load, a search is active (a source
  /// switch mid-search must keep searching everything), or the source has no
  /// durable identity to save a choice under ([orderKey] null: virtual
  /// shelves, Stremio addons).
  ///
  /// Only a load's FIRST present may seed ([_landingSeedArmed]); the
  /// revalidate paths share these present functions and must never re-seed —
  /// the vanished-category resets (hidden, renamed, removed by the provider)
  /// keep their fall-back-to-All behavior, because re-seeding mid-browse
  /// would yank the view.
  String? _landingCategory(String? orderKey, List<String> categories) =>
      !_landingSeedArmed
      ? null
      : landingCategoryFor(
          orderKey: orderKey,
          categories: categories,
          manuallyChosen: _categoryManuallyChosen,
          searching: widget.searchQuery.isNotEmpty,
        );

  /// Pure decision behind [_landingCategory], split out for tests.
  @visibleForTesting
  static String? landingCategoryFor({
    required String? orderKey,
    required List<String> categories,
    required bool manuallyChosen,
    required bool searching,
  }) {
    if (manuallyChosen || searching || orderKey == null || categories.isEmpty) {
      return null;
    }
    final stored = IptvCatalogDb.defaultCategory(orderKey);
    if (stored != null && categories.contains(stored)) return stored;
    return categories.first;
  }

  /// Whether categories can be customized in the current view.
  ///
  /// Only catalog-backed sources (M3U / Xtream) qualify: the hidden set is
  /// keyed by catalog, and the virtual shelves (Favorites, custom lists,
  /// Continue watching), Stremio addons and imported files never get one —
  /// they stay materialized in memory. Everything downstream of this getter
  /// can assume [_dbSnapshot] is non-null.
  bool get _canShowCategoryOptions => _dbSnapshot != null;

  /// Hold-OK (TV) or long-press (touch) on a category: make it the source's
  /// default landing category, or hide it. Routed from the same gestures that
  /// used to jump straight to the hide confirmation; hide still confirms
  /// through [_promptHideCategory], so its wording and semantics are
  /// unchanged.
  Future<void> _promptCategoryOptions(String category) async {
    final app = AppThemeScope.of(context);
    final snap = _dbSnapshot;
    if (snap == null || category.isEmpty) return;
    final isDefault =
        IptvCatalogDb.defaultCategory(snap.catalogKey) == category;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => TvHeldKeyGuard(
        child: SimpleDialog(
          backgroundColor: app.iptv.modalBg,
          title: Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w700),
          ),
          children: [
            ListTile(
              autofocus: true,
              leading: Icon(
                isDefault
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_added_rounded,
                color: app.core.tx,
              ),
              title: Text(
                isDefault ? 'Clear default category' : 'Set as default',
                style: TextStyle(color: app.core.tx),
              ),
              subtitle: Text(
                isDefault
                    ? 'This source goes back to opening on its first category'
                    : 'Open this source on "$category"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: app.core.tx.withAlpha(0xB3)),
              ),
              onTap: () => Navigator.of(
                dialogContext,
              ).pop(isDefault ? 'clearDefault' : 'setDefault'),
            ),
            ListTile(
              leading: Icon(Icons.visibility_off_outlined, color: app.core.tx),
              title: Text(
                'Hide category…',
                style: TextStyle(color: app.core.tx),
              ),
              onTap: () => Navigator.of(dialogContext).pop('hide'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'setDefault':
        if (IptvCatalogDb.setDefaultCategory(snap.catalogKey, category)) {
          _showChip(
            _CatalogChipState.success,
            'Opens on "$category" from now on',
            autoHide: const Duration(milliseconds: 2500),
          );
        } else {
          _showChip(
            _CatalogChipState.failure,
            'Couldn\'t save the default — try again',
            autoHide: const Duration(milliseconds: 3500),
          );
        }
      case 'clearDefault':
        if (IptvCatalogDb.setDefaultCategory(snap.catalogKey, null)) {
          _showChip(
            _CatalogChipState.success,
            'Default category cleared',
            autoHide: const Duration(milliseconds: 2500),
          );
        } else {
          _showChip(
            _CatalogChipState.failure,
            'Couldn\'t clear the default — try again',
            autoHide: const Duration(milliseconds: 3500),
          );
        }
      case 'hide':
        await _promptHideCategory(category);
    }
  }

  /// Hide [category] from this source, after confirming.
  ///
  /// The gesture that gets here is a HOLD (TV) or long-press (touch) on the
  /// category in a picker — deliberately confirmed rather than instant, since
  /// it's a destructive-looking change reached from a control whose normal
  /// press just selects.
  Future<void> _promptHideCategory(String category) async {
    final app = AppThemeScope.of(context);
    final snap = _dbSnapshot;
    if (snap == null || category.isEmpty) return;
    final count = _categoryCounts[category] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: app.iptv.modalBg,
        title: Text(
          'Hide this category?',
          style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '$category\n\n'
          '${count == 0 ? 'Its channels' : '$count channel'
                    '${count == 1 ? '' : 's'}'} '
          'will stop showing up in IPTV — in the list, in search and in the '
          'player\'s guide. Nothing is deleted: bring it back any time from '
          'Settings › IPTV › Hidden categories.',
          style: TextStyle(color: app.core.tx.withAlpha(0xB3), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hide'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!IptvCatalogDb.setGroupHidden(snap.catalogKey, category, true)) {
      _showChip(
        _CatalogChipState.failure,
        'Couldn\'t hide "$category" — try again',
        autoHide: const Duration(milliseconds: 3500),
      );
      return;
    }
    await _refreshAfterHiddenChange();
    if (!mounted) return;
    _showChip(
      _CatalogChipState.success,
      'Hid "$category"',
      autoHide: const Duration(milliseconds: 2600),
    );
  }

  /// Re-derive the category list, its counts and the row facades after the
  /// hidden set changed.
  ///
  /// The rows themselves are untouched, so the shared instance cache is kept:
  /// it's keyed by catalog POSITION, which a hidden category doesn't move
  /// (positions are stored column values, not list offsets). Surviving rows
  /// therefore keep their instance, ObjectKey and focus node instead of being
  /// torn down and rebuilt.
  Future<void> _refreshAfterHiddenChange() async {
    final snap = _dbSnapshot;
    if (snap == null) return;
    final ticket = _loadTicket;
    final groups = await IptvCatalogDb.groupsAsync(snap);
    if (!mounted || ticket != _loadTicket) return;
    final categories = _deriveCategories(snap, groups);
    setState(() {
      _dbGroupCounts = {
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
      };
      _categories = categories;
      _allChannels = _makeDbList(snap);
      // The selected category is the one most likely to have just been
      // hidden — fall back to All rather than leaving the filter pinned to
      // something the list no longer offers.
      if (_selectedCategory != null &&
          !categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
    });
    _applyFilters();
  }

  /// Cap on the channel list handed to the player. On TV the whole list is
  /// serialized over the platform channel at launch (one JSON map per channel
  /// for the native guide) — a 10k-channel playlist froze the UI for hundreds
  /// of ms right on OK. A window this size is far more guide than anyone
  /// DPADs through while still launching instantly.
  static const int _kMaxPlayerChannels = 1500;
  static const int _kPlayerZapPageSize = 200;
  List<IptvChannel> _playerSeriesEpisodes = const [];
  String? _playerSeriesEpisodeSourceId;
  String? _playerSeriesTitle;

  List<Map<String, dynamic>> _playerSourcePayload() => [
    for (final playlist in _playlists)
      if (!playlist.isContinueWatching)
        {
          'id': playlist.id,
          'name': playlist.name,
          // Favorites keeps its own flag even though it is now just the
          // built-in list: the native guide's ★ SAVED button resolves the
          // source by it, and expects exactly one.
          'isFavorites': playlist.isFavorites,
          'isContinue': playlist.isContinueWatching,
          'isXtream': playlist.isXtreamCodes,
          'isList': playlist.isCustomList,
          if (playlist.customListId != null) 'listId': playlist.customListId,
          if (playlist.connectionResourceId != null)
            'connectionResourceId': playlist.connectionResourceId,
          if (playlist.connectionResourceRevision != null)
            'connectionResourceRevision': playlist.connectionResourceRevision,
        },
  ];

  /// The user's lists, for the players' "add to list" picker. Shipped once
  /// per launch rather than as a field on every channel — the channel payload
  /// is already capped for size (see [_kMaxPlayerChannels]).
  List<Map<String, dynamic>> _playerListsPayload() => [
    for (final list in _lists)
      {'id': list.id, 'name': list.name, 'isBuiltin': list.isBuiltin},
  ];

  String _playerOriginPlaylistId(IptvChannel channel, IptvPlaylist source) {
    final seriesOrigin = channel.attributes['series_playlist_id'];
    if (seriesOrigin != null && seriesOrigin.isNotEmpty) {
      return seriesOrigin;
    }
    final listId = source.isFavorites
        ? StorageService.iptvFavoritesListId
        : source.customListId;
    final shelfOrigin = (source.isFavorites || source.isCustomList)
        // Prefer the row's own origin (see [_kListOriginAttribute]); the map
        // is only a fallback for rows that predate it.
        ? (channel.attributes[_kListOriginAttribute]?.isNotEmpty ?? false)
              ? channel.attributes[_kListOriginAttribute]
              : (listId == null
                    ? null
                    : _favoritePlaylistIds[(listId, channel.url)])
        : source.isContinueWatching
        ? _continuePlaylistIds[channel.url]
        : null;
    return shelfOrigin?.isNotEmpty == true ? shelfOrigin! : source.id;
  }

  IptvChannel _playerChannelWithOrigin(
    IptvChannel channel,
    IptvPlaylist source,
  ) {
    return IptvChannel(
      channelNumber: channel.channelNumber,
      name: channel.name,
      url: channel.url,
      logoUrl: channel.logoUrl,
      group: channel.group,
      duration: channel.duration,
      contentType: channel.contentType,
      attributes: {
        ...channel.attributes,
        'source_playlist_id': _playerOriginPlaylistId(channel, source),
      },
      httpHeaders: channel.httpHeaders,
    );
  }

  Future<List<Map<String, dynamic>>> _playerChannelPayload(
    List<({IptvChannel channel, IptvPlaylist source})> entries,
  ) async {
    final favoriteUrls = await StorageService.getIptvFavoriteChannelUrls();
    final resumePositions = await StorageService.getIptvResumePositions([
      for (final entry in entries)
        if (!entry.channel.isLive) entry.channel.url,
    ]);
    return [
      for (final entry in entries)
        {
          ...entry.channel.toJson(),
          'sourceId': _playerOriginPlaylistId(entry.channel, entry.source),
          'sourceName': entry.source.name,
          'isFavorite': favoriteUrls.contains(entry.channel.url),
          if ((resumePositions[entry.channel.url] ?? 0) > 0)
            'resumePositionMs': resumePositions[entry.channel.url],
          if (entry.channel.attributes['series_id'] != null)
            'seriesId': entry.channel.attributes['series_id'],
          if (entry.channel.attributes['series_name'] != null)
            'seriesName': entry.channel.attributes['series_name'],
          if (int.tryParse(entry.channel.attributes['season'] ?? '') != null)
            'season': int.parse(entry.channel.attributes['season']!),
          if (int.tryParse(entry.channel.attributes['episode'] ?? '') != null)
            'episode': int.parse(entry.channel.attributes['episode']!),
          if (entry.channel.attributes['has_next_episode'] != null)
            'hasNextEpisode':
                entry.channel.attributes['has_next_episode'] == 'true',
          if (entry.channel.attributes['tv_archive'] != null)
            'tvArchive': entry.channel.attributes['tv_archive'],
          if (int.tryParse(
                entry.channel.attributes['tv_archive_duration'] ?? '',
              ) !=
              null)
            'tvArchiveDuration': int.parse(
              entry.channel.attributes['tv_archive_duration']!,
            ),
          if (entry.channel.attributes['series_playlist_id'] != null)
            'seriesPlaylistId': entry.channel.attributes['series_playlist_id'],
        },
    ];
  }

  /// The source's full category list for the in-player picker — ALL of the
  /// provider's categories, not just the handful present in the ~1500 channels
  /// sent to the player.
  ///
  /// Reuses [_categories], which the view already maintains for its own chips
  /// (provider categories in order, else every distinct group) and refreshes on
  /// each catalog load — so the launch/browse path never re-runs a GROUP BY on
  /// the UI isolate. The snapshot/in-memory branches only cover the rare case
  /// where it hasn't been populated yet.
  List<String> _fullCategoryList() {
    if (_categories.isNotEmpty) return _categories;
    final snap = _dbSnapshot;
    if (snap != null) {
      // Same hidden-category filtering [_deriveCategories] applies, so the
      // in-player picker can't offer a category the page doesn't. groups()
      // is already filtered in SQL; the provider list is not.
      if (snap.categories.isNotEmpty) {
        return IptvCatalogDb.applyCategoryOrder(
          snap.catalogKey,
          _withoutHidden(snap.catalogKey, snap.categories),
        );
      }
      return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, [
        for (final group in snap.groups())
          if (group.name?.isNotEmpty == true) group.name!,
      ]);
    }
    return <String>{
      for (final channel in _allChannels)
        if (channel.group?.isNotEmpty == true) channel.group!,
    }.toList()..sort();
  }

  Future<Map<String, dynamic>?> _providePlayerIptvBrowse(
    Map<String, dynamic> request,
  ) async {
    if (!mounted) return null;
    final action = request['action'] as String? ?? 'browse';
    final query = (request['query'] as String? ?? '').trim();

    final sourceId = request['sourceId'] as String? ?? _selectedPlaylist?.id;
    IptvPlaylist? source;
    for (final playlist in _playlists) {
      if (playlist.id == sourceId) {
        source = playlist;
        break;
      }
    }
    source ??= _selectedPlaylist;
    if (source == null) return null;

    if (action == 'seriesEpisodes') {
      var episodeSource = source;
      final seriesUrl = request['channelUrl'] as String? ?? '';
      String? sentinelOriginId;
      String? sentinelSeriesId;
      if (seriesUrl.startsWith('xtream-series://')) {
        final path = seriesUrl.substring('xtream-series://'.length);
        final slash = path.indexOf('/');
        if (slash > 0) {
          sentinelOriginId = path.substring(0, slash);
          sentinelSeriesId = path.substring(slash + 1);
        } else {
          sentinelSeriesId = path;
        }
      }
      if (!episodeSource.isXtreamCodes && sentinelOriginId != null) {
        for (final playlist in _playlists) {
          if (playlist.id == sentinelOriginId && playlist.isXtreamCodes) {
            episodeSource = playlist;
            break;
          }
        }
      }
      if (!episodeSource.isXtreamCodes) return null;
      if (episodeSource != _selectedPlaylist ||
          _selectedContentType != 'series') {
        setState(() {
          _selectedPlaylist = episodeSource;
          _selectedCategory = null;
          _selectedContentType = 'series';
        });
        await _loadPlaylist(episodeSource);
        if (!mounted) return null;
      }
      IptvChannel? series;
      for (final channel in _allChannels) {
        if (channel.url == seriesUrl ||
            (sentinelSeriesId != null &&
                channel.attributes['series_id'] == sentinelSeriesId)) {
          series = channel;
          break;
        }
      }
      final seriesId =
          series?.attributes['series_id'] ?? sentinelSeriesId ?? '';
      if (seriesId.isEmpty) return null;
      series ??= IptvChannel(
        name: (request['title'] as String?)?.trim().isNotEmpty == true
            ? (request['title'] as String).trim()
            : 'Series',
        url: seriesUrl,
        contentType: 'series',
        attributes: {
          'series_id': seriesId,
          'series_playlist_id': episodeSource.id,
        },
      );
      final info = await XtreamCodesService.instance.fetchSeriesInfo(
        episodeSource.serverUrl!,
        episodeSource.username ?? '',
        episodeSource.password ?? '',
        seriesId,
        connectionResourceId: episodeSource.connectionResourceId,
        connectionResourceRevision: episodeSource.connectionResourceRevision,
      );
      if (!mounted || info == null) return null;
      final episodes = [
        for (var index = 0; index < info.episodes.length; index++)
          IptvChannel(
            name:
                '${series.name} · S${info.episodes[index].season.toString().padLeft(2, '0')}'
                'E${info.episodes[index].episode.toString().padLeft(2, '0')}'
                '${info.episodes[index].title.trim().isEmpty ? '' : ' · ${info.episodes[index].title.trim()}'}',
            url: info.episodes[index].url,
            logoUrl: info.episodes[index].thumbnailUrl?.isNotEmpty == true
                ? info.episodes[index].thumbnailUrl
                : series.logoUrl,
            group: series.name,
            contentType: 'vod',
            attributes: {
              'series_id': seriesId,
              'series_playlist_id': episodeSource.id,
              'series_name': series.name,
              'season': info.episodes[index].season.toString(),
              'episode': info.episodes[index].episode.toString(),
              'has_next_episode': info.episodes
                  .skip(index + 1)
                  .any((episode) => episode.season != 0)
                  .toString(),
            },
          ),
      ];
      _playerSeriesEpisodes = episodes;
      _playerSeriesEpisodeSourceId = episodeSource.id;
      _playerSeriesTitle = series.name;
      return {
        'sourceId': episodeSource.id,
        'sourceName': episodeSource.name,
        'contentType': 'episodes',
        'title': series.name,
        'categories': const <String>[],
        'sources': _playerSourcePayload(),
        'channels': await _playerChannelPayload([
          for (final episode in episodes)
            (channel: episode, source: episodeSource),
        ]),
      };
    }

    final requestedType =
        request['contentType'] as String? ??
        (source.isXtreamCodes ? _selectedContentType : 'live');
    if (requestedType == 'episodes') {
      final cached = source.id == _playerSeriesEpisodeSourceId
          ? _playerSeriesEpisodes
          : const <IptvChannel>[];
      final terms = query.toLowerCase().split(RegExp(r'\s+'));
      final episodes = cached
          .where(
            (channel) =>
                query.isEmpty || terms.every(channel.searchKey.contains),
          )
          .take(_kMaxPlayerChannels)
          .toList();
      return {
        'sourceId': source.id,
        'sourceName': source.name,
        'contentType': 'episodes',
        'title': _playerSeriesTitle ?? 'Episodes',
        'categories': const <String>[],
        'sources': _playerSourcePayload(),
        'channels': await _playerChannelPayload([
          for (final episode in episodes) (channel: episode, source: source),
        ]),
      };
    }
    final needsLoad =
        source != _selectedPlaylist ||
        (source.isXtreamCodes && requestedType != _selectedContentType);
    if (needsLoad) {
      setState(() {
        _selectedPlaylist = source;
        _selectedCategory = null;
        if (source!.isXtreamCodes &&
            const {'live', 'vod', 'series'}.contains(requestedType)) {
          _selectedContentType = requestedType;
        }
      });
      await _loadPlaylist(source);
      if (!mounted) return null;
    }

    final category = (request['category'] as String?)?.trim();
    var effectiveCategory =
        category == null || category.isEmpty || category == 'All'
        ? null
        : category;
    final jumpNumber = action == 'channelNumber'
        ? (request['channelNumber'] as num?)?.toInt()
        : null;
    final isJump = jumpNumber != null && jumpNumber > 0;
    final isZapPage = action == 'zapPage';
    final isPagedRequest = isZapPage || isJump;
    final requestedLimit = (request['limit'] as num?)?.toInt();
    final pageLimit = isPagedRequest
        ? (requestedLimit ?? _kPlayerZapPageSize).clamp(1, _kMaxPlayerChannels)
        : _kMaxPlayerChannels;
    var pageOffset = isPagedRequest
        ? ((request['offset'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30)
        : 0;
    final anchorUrl = (request['anchorUrl'] as String?)?.trim();
    final anchorName = (request['anchorName'] as String?)?.trim();
    final fromEnd = request['fromEnd'] == true;
    List<IptvChannel> channels;
    var totalChannels = 0;
    int? anchorIndex;
    final snap = _dbSnapshot;
    if (snap != null) {
      final live = source.isXtreamCodes
          ? null
          : switch (requestedType) {
              'live' => true,
              'vod' => false,
              _ => null,
            };
      final jumpEntry = isJump ? snap.entryForChannelNumber(jumpNumber) : null;
      if (isJump && jumpEntry == null) {
        return {
          'sourceId': source.id,
          'sourceName': source.name,
          'contentType': requestedType,
          'channelNotFound': true,
        };
      }
      if (jumpEntry != null) effectiveCategory = jumpEntry.channel.group;
      totalChannels = snap.count(group: effectiveCategory, live: live);
      if (jumpEntry != null) {
        anchorIndex = snap.count(
          group: effectiveCategory,
          live: live,
          beforePosition: jumpEntry.position,
        );
      } else if (isZapPage &&
          anchorUrl != null &&
          anchorUrl.isNotEmpty &&
          anchorName != null &&
          anchorName.isNotEmpty) {
        final catalogPosition = snap.positionOf(
          url: anchorUrl,
          name: anchorName,
          group: effectiveCategory,
          live: live,
        );
        if (catalogPosition != null) {
          anchorIndex = snap.count(
            group: effectiveCategory,
            live: live,
            beforePosition: catalogPosition,
          );
        }
      }
      if (isPagedRequest) {
        pageOffset = iptvPlayerZapPageOffset(
          total: totalChannels,
          limit: pageLimit,
          requestedOffset: pageOffset,
          anchorIndex: anchorIndex,
          fromEnd: fromEnd,
        );
      }
      channels = snap.page(
        offset: pageOffset,
        limit: pageLimit,
        group: effectiveCategory,
        search: isPagedRequest || query.isEmpty ? null : query,
        live: live,
      );
    } else {
      Iterable<IptvChannel> filtered = _allChannels;
      IptvChannel? jumpChannel;
      if (isJump) {
        for (final channel in _allChannels) {
          if (channel.channelNumber == jumpNumber && channel.isLive) {
            jumpChannel = channel;
            break;
          }
        }
        if (jumpChannel == null) {
          return {
            'sourceId': source.id,
            'sourceName': source.name,
            'contentType': requestedType,
            'channelNotFound': true,
          };
        }
        effectiveCategory = jumpChannel.group;
      }
      // A list shelf is a curated mix — whatever the user put in it — so it
      // is never narrowed by the requested content type. Without this a list
      // holding movies would come back EMPTY in the player's guide: these
      // sources aren't Xtream, so requestedType falls back to 'live' above
      // and would filter out every on-demand row the user chose to save.
      if (!source.isXtreamCodes &&
          !source.isContinueWatching &&
          !source.isFavorites &&
          !source.isCustomList) {
        filtered = switch (requestedType) {
          'live' => filtered.where((channel) => channel.isLive),
          'vod' => filtered.where(
            (channel) => !channel.isLive && channel.contentType != 'series',
          ),
          'series' => filtered.where(
            (channel) => channel.contentType == 'series',
          ),
          _ => filtered,
        };
      }
      if (effectiveCategory != null) {
        filtered = filtered.where(
          (channel) => channel.group == effectiveCategory,
        );
      }
      if (query.isNotEmpty) {
        final terms = query.toLowerCase().split(RegExp(r'\s+'));
        filtered = filtered.where(
          (channel) => terms.every(channel.searchKey.contains),
        );
      }
      if (isPagedRequest) {
        // Legacy/in-memory catalogs are already materialized. Compute the
        // filtered ordinal once so native can request a small window centered
        // on a channel selected from search.
        final materialized = filtered.toList(growable: false);
        totalChannels = materialized.length;
        if (jumpChannel != null) {
          anchorIndex = materialized.indexWhere(
            (channel) => channel.channelNumber == jumpNumber,
          );
          if (anchorIndex == -1) anchorIndex = null;
        } else if (anchorUrl != null && anchorUrl.isNotEmpty) {
          anchorIndex = materialized.indexWhere(
            (channel) =>
                channel.url == anchorUrl &&
                (anchorName == null ||
                    anchorName.isEmpty ||
                    channel.name == anchorName),
          );
          if (anchorIndex == -1) anchorIndex = null;
        }
        pageOffset = iptvPlayerZapPageOffset(
          total: totalChannels,
          limit: pageLimit,
          requestedOffset: pageOffset,
          anchorIndex: anchorIndex,
          fromEnd: fromEnd,
        );
        channels = materialized
            .skip(pageOffset)
            .take(pageLimit)
            .toList(growable: false);
      } else {
        channels = filtered.take(_kMaxPlayerChannels).toList();
        totalChannels = channels.length;
      }
    }

    final categories = _fullCategoryList();
    return {
      'sourceId': source.id,
      'sourceName': source.name,
      'contentType': requestedType,
      'selectedCategory': effectiveCategory,
      'categories': categories,
      if (isPagedRequest) 'pageOffset': pageOffset,
      if (isPagedRequest) 'totalChannels': totalChannels,
      if (isPagedRequest && anchorIndex != null) 'anchorIndex': anchorIndex,
      if (isJump) 'targetChannelNumber': jumpNumber,
      'sources': _playerSourcePayload(),
      'channels': await _playerChannelPayload([
        for (final channel in channels) (channel: channel, source: source),
      ]),
    };
  }

  /// Latch across the resolve+launch window: resolving a Stremio channel
  /// takes real time, and repeated OK presses on a seemingly-idle row must
  /// not stack player launches.
  bool _launchingChannel = false;

  Future<void> _playChannel(
    IptvChannel channel, {
    bool Function()? shouldCancel,
  }) async {
    if (_launchingChannel) return;
    _launchingChannel = true;
    try {
      await _playChannelInner(channel, shouldCancel: shouldCancel);
    } finally {
      _launchingChannel = false;
    }
  }

  // ==========================================================================
  // Startup channel — boot straight into a live channel
  //
  // Runs against the MOUNTED page rather than as a headless launcher: the
  // player's launch payload includes `iptvBrowseProvider`, a closure into this
  // state, and without it a launched channel plays but cannot zap.
  // ==========================================================================

  /// How long the launch may spend waiting for a catalog. Deliberately under
  /// the overlay's 30s timeout so the failure is ours (with a message) rather
  /// than the overlay's silent give-up.
  static const Duration _startupResolveDeadline = Duration(seconds: 24);

  void _cancelStartupLaunch() {
    _startupAttempt++;
    if (_startupLaunchActive) {
      _startupLaunchActive = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _maybeRunStartupLaunch() async {
    final payload = MainPageBridge.consumeIptvStartupChannel();
    if (payload == null) return;
    // The bootstrap sentinel carries no url/name by design — it means "start on
    // whatever you land on" — so it must skip the stored-identity validation
    // below, which would otherwise reject it and cancel the whole attempt.
    final firstAvailable =
        payload[StorageService.startupIptvFirstAvailable] == true;
    final url = payload['url'];
    final name = payload['name'];
    if (!firstAvailable && (url is! String || url.isEmpty || name is! String)) {
      MainPageBridge.cancelIptvStartupChannel();
      return;
    }

    final attempt = ++_startupAttempt;
    // The epoch, not just the local attempt: cancellation can land in the gap
    // between consuming the payload and registering the callback below, and
    // would then find nothing to call. The epoch records it regardless.
    final epoch = MainPageBridge.iptvStartupEpoch;
    bool cancelled() =>
        attempt != _startupAttempt ||
        epoch != MainPageBridge.iptvStartupEpoch ||
        !mounted;
    if (cancelled()) return;
    _startupLaunchActive = true;
    MainPageBridge.cancelIptvStartup = _cancelStartupLaunch;
    if (mounted) setState(() {});

    try {
      final row = await _resolveStartupRow(payload, cancelled);
      if (cancelled()) return;
      if (row == null) {
        _failStartupLaunch(
          firstAvailable
              ? 'No live channels to start on yet'
              : 'That channel is no longer available',
        );
        return;
      }
      await _scrollAndFocusStartupRow(row);
      if (cancelled()) return;
      await _playChannel(row, shouldCancel: cancelled);
    } catch (e) {
      debugPrint('IPTV startup launch failed: $e');
      if (!cancelled()) _failStartupLaunch('Could not start that channel');
    } finally {
      // Do NOT drop the preview suppression just because push() returned.
      //
      // Focusing the target row above re-tuned the stage, so `_previewStreamUrl`
      // is loaded and only this flag is holding the stage off. On TV push()
      // returns while the native player is merely STARTING — clearing here
      // would remount the stage and open a second live stream underneath it,
      // which is the exact failure `_previewRearmPending` exists to prevent.
      // On the parked-re-arm paths, `_flushPreviewRearm` clears this instead.
      // Keyed on the parked re-arm itself, not on "we think we launched":
      // `_playChannelInner` can also return early WITHOUT launching (a Stremio
      // channel with no playable candidate, say), and treating that as parked
      // would strand the suppression on forever, leaving the preview stage
      // permanently dead until some unrelated playback flushed it.
      final parked = _previewRearmPending;
      if (attempt == _startupAttempt && !parked) {
        _startupLaunchActive = false;
        if (mounted) setState(() {});
      }
      MainPageBridge.cancelIptvStartup = null;
    }
  }

  void _failStartupLaunch(String reason) {
    MainPageBridge.notifyAutoLaunchFailed(reason);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  /// Locate the stored channel and return the *resident* row instance.
  ///
  /// Never returns a self-materialized [IptvChannel]: `_playChannelInner` looks
  /// the row up by IDENTITY (`DbChannelList` is backed by a `HashMap.identity`),
  /// so a foreign instance fails `contains`, falls through to `_allChannels`,
  /// resolves to null, and gets clamped to index 0 — silently launching the
  /// first channel in the catalog.
  Future<IptvChannel?> _resolveStartupRow(
    Map<String, dynamic> payload,
    bool Function() cancelled,
  ) async {
    // Bootstrap case: nothing has ever been watched, so there is no stored
    // channel to look up. Start on whatever the page already landed on — their
    // default provider, else Favourites when they have any (see
    // `_loadSettings`). Deliberately NOT resolved as a stored identity:
    // there is nothing to match, and no user expectation to get wrong.
    if (payload[StorageService.startupIptvFirstAvailable] == true) {
      return _resolveFirstAvailableRow(cancelled);
    }

    final url = payload['url'] as String;
    final name = payload['name'] as String;
    final channelNumber = (payload['channelNumber'] as num?)?.toInt();

    // 1. The target's own provider, resolved BEFORE anything is looked up — a
    //    lookup against the landing playlist's catalog would answer about the
    //    wrong provider entirely.
    final target = _startupPlaylistFor(payload);
    if (target == null) return null;
    if (_selectedPlaylist?.id != target.id) {
      _onPlaylistChanged(target);
    }

    final deadline = DateTime.now().add(_startupResolveDeadline);

    // 2. Do not read the catalog until the OUTGOING one is gone. `_loadPlaylist`
    //    sets its in-flight ticket synchronously, but `_loadPlaylistInner`
    //    clears `_allChannels`/`_dbSnapshot` only after its first awaits — so
    //    for a window the previous provider's rows are still sitting there, and
    //    matching against them would resolve a channel from the wrong account.
    var ready = false;
    while (!ready && !cancelled() && DateTime.now().isBefore(deadline)) {
      if (_inFlightLoadTicket == null) {
        ready = true; // load finished (or a cached catalog was already present)
      } else if (_allChannels.isEmpty && _dbSnapshot == null) {
        ready = true; // cleared — anything arriving now belongs to the target
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    // 3. Wait for that provider's catalog. Stremio shelves arrive
    //    progressively, so this waits for the row to APPEAR, not merely for a
    //    load to finish.
    while (!cancelled() && DateTime.now().isBefore(deadline)) {
      // A load for a DIFFERENT playlist means something (a user action, an
      // addon refresh) moved on from under us — the attempt is void.
      if (_selectedPlaylist?.id != target.id) return null;
      final snap = _dbSnapshot;
      if (snap != null) {
        final entry =
            snap.entryForUrl(url: url, name: name) ??
            (channelNumber != null
                ? snap.entryForChannelNumber(channelNumber)
                : null);
        if (entry != null) {
          return _residentDbRow(entry, url, name, channelNumber);
        }
      } else if (_allChannels.isNotEmpty) {
        final match = _materializedStartupMatch(url, name, channelNumber);
        if (match != null) return _adoptStartupCategory(match);
        // A finished load that still doesn't hold the channel is a real miss;
        // an in-flight one may still deliver it.
        if (_inFlightLoadTicket == null) return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  /// First live row of whatever the page is currently showing.
  ///
  /// Rows come straight off `_filteredChannels`, so they are the facade's own
  /// resident instances — the identity `_playChannelInner` needs — and no
  /// category is adopted, because the landing view is exactly what we want.
  ///
  /// The walk is capped: a VOD-heavy catalog could otherwise page thousands of
  /// rows looking for a live one, and if the first few hundred hold none, the
  /// honest answer is "nothing to start on" rather than a long stall.
  Future<IptvChannel?> _resolveFirstAvailableRow(
    bool Function() cancelled,
  ) async {
    final deadline = DateTime.now().add(_startupResolveDeadline);
    while (!cancelled() && DateTime.now().isBefore(deadline)) {
      final channels = _filteredChannels;
      if (channels.isNotEmpty) {
        final limit = channels.length < 300 ? channels.length : 300;
        for (var i = 0; i < limit; i++) {
          final channel = channels[i];
          if (channel.isLive) return channel;
        }
        // A finished load with no live row in reach is a real answer; an
        // in-flight one (progressive Stremio) may still deliver.
        if (_inFlightLoadTicket == null) return null;
      } else if (_inFlightLoadTicket == null && _settingsLoaded) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  /// Convert a catalog position into the facade's filtered index, then read the
  /// row back out of the live facade so it is a registered, resident instance.
  Future<IptvChannel?> _residentDbRow(
    ({int position, IptvChannel channel}) entry,
    String url,
    String name,
    int? storedNumber,
  ) async {
    final channel = entry.channel;
    // Live-only, enforced on the resolved row rather than by filtering — see
    // the index contract below.
    if (!channel.isLive) return null;
    // A channel-number fallback must corroborate on NAME. Numbers are assigned
    // per load on virtual catalogs, so a shifted numbering is exactly the
    // condition that triggers this path — and "same group" is worthless
    // corroboration when hundreds of channels share "Sports".
    if (channel.url != url &&
        storedNumber != null &&
        _normalizedName(channel.name) != _normalizedName(name)) {
      return null;
    }

    await _adoptStartupCategoryValue(channel.group);
    final snap = _dbSnapshot;
    final list = _filteredChannels;
    if (snap == null || list is! DbChannelList) return null;

    // The index MUST be counted under the facade's own filter set. DbChannelList
    // filters on group + search only — it has no `live` parameter — so counting
    // live-only rows here and indexing a facade holding live+VOD would land on
    // a different channel entirely.
    final index = snap.count(
      group: list.group,
      search: list.search,
      beforePosition: entry.position,
    );
    if (index < 0 || index >= list.length) return null;
    final row = list[index];
    // Verify against what resolution actually returned, not against the stored
    // blob: a successful number-fallback legitimately has a different URL, and
    // checking the stale value would reject every one of them.
    if (row.url != channel.url || row.name != channel.name) return null;
    return row;
  }

  IptvChannel? _materializedStartupMatch(
    String url,
    String name,
    int? storedNumber,
  ) {
    for (final channel in _allChannels) {
      if (channel.url == url && channel.name == name && channel.isLive) {
        return channel;
      }
    }
    if (storedNumber == null) return null;
    for (final channel in _allChannels) {
      if (channel.channelNumber == storedNumber &&
          channel.isLive &&
          _normalizedName(channel.name) == _normalizedName(name)) {
        return channel;
      }
    }
    return null;
  }

  /// Materialized lists hand back the very instance the filtered list holds, so
  /// identity already lines up — only the category needs adopting.
  Future<IptvChannel?> _adoptStartupCategory(IptvChannel channel) async {
    await _adoptStartupCategoryValue(channel.group);
    return _filteredChannels.contains(channel) ? channel : null;
  }

  /// Make the target's own group the active category. Without this the landing
  /// category can simply exclude the target, and no amount of correct counting
  /// inside it will ever materialize the row.
  Future<void> _adoptStartupCategoryValue(String? group) async {
    if (_selectedCategory != group) {
      setState(() => _selectedCategory = group);
      _applyFilters();
      // Let the new facade/filtered list settle before it is indexed.
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  static String _normalizedName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The provider a stored startup channel belongs to.
  ///
  /// Falls back to an Xtream fingerprint (`serverUrl` + `username`) captured
  /// when the channel was saved: re-adding an account mints a brand-new
  /// playlist id, so an id-only lookup would lose the channel every time a user
  /// re-entered their subscription.
  IptvPlaylist? _startupPlaylistFor(Map<String, dynamic> payload) {
    final playlistId = payload['playlistId'];
    if (playlistId is String && playlistId.isNotEmpty) {
      for (final playlist in _playlists) {
        if (playlist.id == playlistId) return playlist;
      }
    }
    final serverUrl = payload['serverUrl'];
    final username = payload['username'];
    if (serverUrl is String && serverUrl.isNotEmpty && username is String) {
      for (final playlist in _playlists) {
        if (playlist.isXtreamCodes &&
            playlist.serverUrl == serverUrl &&
            playlist.username == username) {
          return playlist;
        }
      }
    }
    return null;
  }

  /// Scroll the target into view and focus it, so BACK out of the player lands
  /// on the channel rather than at the top of the list.
  ///
  /// There is no existing scroll-to-index to reuse: the grid's only auto-scroll
  /// is each row's own `ensureVisible`, fired once a BUILT row takes focus — and
  /// a distant lazy row is never built and has no focus node.
  Future<void> _scrollAndFocusStartupRow(IptvChannel row) async {
    final index = _filteredChannels is DbChannelList
        ? (_filteredChannels as DbChannelList).indexOfInstance(row)
        : _filteredChannels.indexOf(row);
    if (index == null || index < 0) return;
    // The touch-tablet two-pane renders IptvCenteredSelector, which owns its
    // OWN controller — `_scrollController` drives the grid only, so scrolling it
    // here would be a no-op. Hand the selector the index through the selection
    // it already reconciles against instead.
    if (_touchTabletTwoPaneActive) {
      setState(() => _selectTabletChannel(index, row));
      return;
    }
    if (_scrollController.hasClients) {
      final target = (index ~/ _gridColumns).toDouble() * (_gridRowExtent + 4);
      final position = _scrollController.position;
      if (position.hasContentDimensions) {
        _scrollController.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
    }
    // The row has to build before it has a focus node to give focus to, and on
    // a slow TV that can take more than the next frame.
    for (var attempt = 0; attempt < 5; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final node = _cardFocusNodes[row];
      if (node != null) {
        node.requestFocus();
        return;
      }
    }
  }

  /// Replay an archived programme (Xtream catchup). The replay is launched
  /// as a single-item on-demand payload rather than through [_playChannel]:
  /// the timeshift URL is a finite VOD-style stream that isn't part of any
  /// channel list, and the in-player guide would otherwise point at an
  /// unrelated channel. Resume/continue-watching ride the normal VOD path —
  /// the timeshift URL is stable for a given programme, so a half-watched
  /// replay picks up where it left off.
  Future<void> _playCatchup(IptvChannel channel, EpgProgramme programme) async {
    if (_launchingChannel) return;
    _launchingChannel = true;
    try {
      // Everything origin-dependent is captured BEFORE the first await: the
      // first-use dialect probe can run for tens of seconds, and the user
      // can switch playlists meanwhile — the widget stays mounted, so
      // `mounted` guards don't cover it. Recording with the switched-to
      // playlist's id would break the provider-deletion sweep (deleting B
      // would purge A's replay; deleting A would strand the entry).
      final originPlaylistId = _originPlaylistIdFor(channel);
      final ticket = _loadTicket;
      final replayFromInPlaceSchedule = _scheduleChannel?.url == channel.url;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparing replay of "${programme.title}"…'),
          // Covers the worst-case first-use probe (3 dialects × 10s timeout);
          // hidden explicitly the moment the probe answers.
          duration: const Duration(seconds: 30),
        ),
      );

      final url = await IptvEpgService.instance.catchupUrl(
        channel.url,
        programme,
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      // Stale: the playlist reloaded/switched, or the in-place schedule pane
      // this replay was picked from is gone — a player appearing over
      // whatever the user moved on to would read as the wrong programme
      // launching itself. Bottom-sheet replays capture false and skip this
      // guard because [_scheduleChannel] is never set in that flow.
      if (ticket != _loadTicket) return;
      if (replayFromInPlaceSchedule && _scheduleChannel?.url != channel.url) {
        return;
      }
      if (url == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Replay not available — the panel did not answer for '
              '"${programme.title}"',
            ),
          ),
        );
        return;
      }

      final replay = IptvChannel(
        name: programme.title,
        url: url,
        logoUrl: channel.logoUrl,
        group: channel.name, // reads as "on <channel>" in the player UI
        contentType: 'vod',
        httpHeaders: channel.httpHeaders,
      );
      await StorageService.recordIptvWatch(
        replay.url,
        channelName: replay.name,
        logoUrl: replay.logoUrl,
        group: replay.group,
        playlistId: originPlaylistId,
        httpHeaders: replay.httpHeaders,
      );
      if (!mounted) return;

      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: url,
          title: programme.title,
          subtitle: channel.name,
          viewMode: PlaylistViewMode.sorted,
          iptvChannels: [replay],
          iptvStartIndex: 0,
          httpHeaders: replay.playbackHeaders,
        ),
      );
      // Same parked preview re-arm discipline as _playChannelInner.
      if (mounted && (widget.isTelevision || _tvTwoPaneActive)) {
        _previewRearmPending = true;
      }
      if (!widget.isTelevision && mounted) {
        if (_touchTabletTwoPaneActive) {
          _flushPreviewRearm();
        } else {
          await _refreshAfterPlayback();
        }
      }
    } finally {
      _launchingChannel = false;
    }
  }

  /// [shouldCancel] is polled after the awaits below and immediately before the
  /// player is pushed. Checking only before `_playChannel` is not enough: this
  /// method still awaits a Stremio candidate resolve and a watch record, and a
  /// BACK landing in either window would otherwise still end in a player.
  Future<void> _playChannelInner(
    IptvChannel channel, {
    bool Function()? shouldCancel,
  }) async {
    // Series entries aren't playable — their sentinel URL routes to the
    // merged series page, whose episode list does the actual playing.
    if (channel.contentType == 'series') {
      await _openSeriesDetail(channel);
      return;
    }
    // Stremio channels have no stream URL yet — resolve the ladder now (the
    // preview's winner cache usually makes this instant) and launch on the
    // best candidate. The in-player guide still gets the full mixed list;
    // both players resolve further stremio-keyed channels on switch.
    var initialUrl = channel.url;
    if (StremioIptvService.isStremioChannelUrl(channel.url)) {
      // Explicit play intent: a cached "nothing playable" is re-checked
      // fresh, and an empty answer explains itself (addon down vs. no
      // streams) instead of a blanket "not playable".
      final candidates = await StremioIptvService.instance.resolveCandidates(
        channel.url,
        refreshIfEmpty: true,
      );
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              StremioIptvService.instance.unplayableMessage(
                channel.url,
                channel.name,
              ),
            ),
          ),
        );
        return;
      }
      initialUrl = candidates.first.url;
      if (shouldCancel != null && shouldCancel()) return;
    }
    // Remember on-demand plays so the Continue-watching shelf can rebuild the
    // row later without re-fetching the panel. Recorded BEFORE the launch:
    // the player process can be killed outright on TV, and a shelf entry with
    // no saved position simply doesn't show up (the join drops it).
    //
    // Live channels are skipped — "62% through Sky Sports" is meaningless.
    if (!channel.isLive) {
      await StorageService.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: _originPlaylistIdFor(channel),
        httpHeaders: channel.httpHeaders,
      );
    }

    // The in-player guide mirrors what the user was browsing: the current
    // category/search filter, not the whole playlist. (Also what keeps the
    // launch payload small when a filter is active.)
    var channels = _filteredChannels.contains(channel)
        ? _filteredChannels
        : _allChannels;
    var channelIndex = channels is DbChannelList
        // Identity lookup against resident pages — the tapped row is by
        // definition resident; a paged indexOf would walk the catalog.
        ? (channels.indexOfInstance(channel) ?? 0)
        : channels.indexOf(channel);
    if (channelIndex < 0) channelIndex = 0;
    if (channels is DbChannelList) {
      // Materialize exactly the launch window from SQL — the facade itself
      // must never be handed to the launcher (serializing it would page the
      // entire catalog).
      final source = channels;
      final total = source.length;
      final lo = total > _kMaxPlayerChannels
          ? (channelIndex - _kMaxPlayerChannels ~/ 2).clamp(
              0,
              total - _kMaxPlayerChannels,
            )
          : 0;
      channels = source.effectiveSnapshot.page(
        offset: lo,
        limit: _kMaxPlayerChannels,
        group: source.group,
        search: source.search,
      );
      if (channels.isEmpty) {
        // The pinned generation was swept between the row painting and OK
        // landing (a background revalidate finished in that window). With an
        // empty list, `clamp(0, -1)` throws ArgumentError in release — play
        // the tapped channel alone instead; the guide simply has one row
        // until the next open.
        channels = [channel];
      }
      channelIndex = (channelIndex - lo).clamp(0, channels.length - 1);
    } else if (channels.length > _kMaxPlayerChannels) {
      final lo = (channelIndex - _kMaxPlayerChannels ~/ 2).clamp(
        0,
        channels.length - _kMaxPlayerChannels,
      );
      channels = channels.sublist(lo, lo + _kMaxPlayerChannels);
      channelIndex -= lo;
    }
    final launchSource = _selectedPlaylist;
    final playerChannels = launchSource == null
        ? channels
        : [
            for (final item in channels)
              _playerChannelWithOrigin(item, launchSource),
          ];
    if (!mounted) return;
    // Last gate before the player exists. Everything above may have taken
    // seconds (Stremio ladder, catalog page, watch record).
    if (shouldCancel != null && shouldCancel()) return;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: channel.name,
        subtitle: channel.group ?? 'IPTV',
        channelName: channel.name,
        channelNumber: channel.channelNumber,
        showChannelName: channel.isLive,
        viewMode: PlaylistViewMode.sorted,
        iptvChannels: playerChannels,
        iptvStartIndex: channelIndex,
        iptvCategories: _fullCategoryList(),
        iptvSourceId: _selectedPlaylist?.id,
        iptvSourceName: _selectedPlaylist?.name,
        iptvSelectedCategory: _selectedCategory,
        iptvContentType: _selectedPlaylist?.isXtreamCodes == true
            ? _selectedContentType
            : (channel.isLive ? 'live' : 'vod'),
        iptvSources: _playerSourcePayload(),
        iptvLists: _playerListsPayload(),
        iptvBrowseProvider: _providePlayerIptvBrowse,
        // Opening headers for the launch channel (later zaps read them off the
        // channel they switch to). Stremio-addon links are already-resolved CDN
        // URLs, so they keep the addon's own defaults.
        httpHeaders: StremioIptvService.isStremioChannelUrl(channel.url)
            ? null
            : channel.playbackHeaders,
      ),
    );
    // Re-arm the preview stage (see [_previewEpoch]) — but NOT yet. On TV,
    // push() returns the moment the native player activity STARTS, while this
    // activity is still resumed: remounting the stage now races the cover
    // (the fresh backdrop's dwell can open a stream UNDER the real player).
    // Park the re-arm; it completes on app resume (native path) or on the
    // next row focus (in-app fallback, whose route is awaited to the pop).
    // Desktop two-pane parks it too — push() can hand off to an EXTERNAL
    // player app and return while it's still playing, so the next hover
    // (a sign the user is back in the app) is the safe re-arm point.
    if (mounted && (widget.isTelevision || _tvTwoPaneActive)) {
      _previewRearmPending = true;
    }
    // Off TV, push() is awaited to the pop — the position just written is
    // already on disk, so refresh now. On TV push() can return while the
    // native player is still starting, and rebuilding the list under a
    // launching player is the worst possible moment for it; the parked
    // re-arm below is the designated "we're back" hook and refreshes there.
    if (!widget.isTelevision) {
      if (_touchTabletTwoPaneActive) {
        _flushPreviewRearm();
      } else {
        await _refreshAfterPlayback();
      }
    }
  }

  /// Open the merged series page for an Xtream series entry. Playback happens
  /// inside that page (episode list / Resume), so none of [_playChannelInner]'s
  /// launch bookkeeping applies here.
  Future<void> _openSeriesDetail(IptvChannel channel) async {
    var playlist = _selectedPlaylist;
    if (playlist == null) return;
    // Reached from a virtual shelf (Continue watching): the selected playlist
    // is the shelf itself, not the provider — resolve the series' real Xtream
    // provider from the origin id stored per row.
    if (!playlist.isXtreamCodes) {
      final originId = _originPlaylistIdFor(channel);
      IptvPlaylist? origin;
      for (final p in _playlists) {
        if (p.id == originId && p.isXtreamCodes) {
          origin = p;
          break;
        }
      }
      if (origin == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("This series' provider is no longer available"),
            ),
          );
        }
        return;
      }
      playlist = origin;
    }
    // Empty the stage BEFORE the route covers it: the app-resume path after
    // in-page playback flushes the parked re-arm, and a remounted backdrop
    // must not open a stream underneath the detail route. With the shown
    // channel cleared, an epoch bump remounts nothing.
    _clearPreview();
    await openXtreamSeries(
      context,
      playlist: playlist,
      series: channel,
      isTelevision: widget.isTelevision,
    );
    if (!mounted) return;
    // Episodes watched inside the page entered the continue-watching shelf —
    // reflect that (and any position changes) now. The preview re-arms itself
    // on the next row focus.
    await _refreshAfterPlayback();
  }

  /// Pull freshly saved positions back into the list after playback. The
  /// Continue-watching shelf is rebuilt outright — an item can have just
  /// entered it (first watch), moved to the front, or aged out by finishing.
  ///
  /// Deliberately NOT via _loadSettings: that path re-derives the landing
  /// selection (and always lands on Favorites when any exist), which would
  /// yank the user off whatever they were browsing every time they came back
  /// from the player.
  Future<void> _refreshAfterPlayback() async {
    if (!mounted) return;
    // Read the shelf ONCE and reuse it below. Each read decodes both the
    // watch-history map and the (potentially large) shared resume map off the
    // UI isolate, and this runs at the exact moment the user lands back on
    // the list — the worst time to do it three times over.
    final items = await StorageService.getIptvContinueWatching();
    if (!mounted) return;
    // A recording may have been started (or stopped) from inside the player —
    // the header's record-dot must not lag until the next resume.
    _armAndroidRecStateRefresh();
    await _loadFavorites();
    if (!mounted) return;
    _refreshContinueShelfPresence(items.isNotEmpty);
    if (!mounted) return;

    // A list shelf can have changed under the user while the player was up —
    // both players can add and remove memberships from their own guide. This
    // covers Favorites AND custom lists; without the custom-list arm a
    // channel removed in the native guide stays on screen until a full
    // reload of the page.
    final shelf = _selectedPlaylist;
    final shelfListId = (shelf?.isFavorites ?? false)
        ? StorageService.iptvFavoritesListId
        : shelf?.customListId;
    if (shelfListId != null) {
      final stored = {
        for (final entry in _membership.entries)
          if (entry.value.contains(shelfListId)) entry.key,
      };
      final current = {for (final channel in _allChannels) channel.url};
      if (!setEquals(stored, current)) {
        await _loadPlaylist(shelf!);
        return;
      }
    }

    // The shelf can empty out from under the user — they just finished its
    // last item. Leaving it selected strands the picker: with no matching
    // option the dropdown renders the FIRST option's label instead, so it
    // would read "Favorites" above an empty shelf.
    if (items.isEmpty && (_selectedPlaylist?.isContinueWatching ?? false)) {
      final remaining = [
        for (final p in _playlists)
          if (!p.isContinueWatching) p,
      ];
      if (remaining.isNotEmpty) {
        _onPlaylistChanged(remaining.first);
        return;
      }
    }

    if (_selectedPlaylist?.isContinueWatching ?? false) {
      // Rebuild only when the shelf's membership actually changed — an item
      // finished and dropped off, or a newly watched one arrived. A reload
      // disposes every row's focus node (see _loadPlaylist), so doing it for
      // a mere position bump would scramble DPAD focus to redraw one bar.
      // Compare against the SAME collapsed keys the shelf renders (a series'
      // episodes fold to one sentinel row — see _buildContinueResult), or a
      // series would read as changed on every return and force a reload.
      final fresh = {
        for (final item in items)
          ((item['seriesId'] as String?)?.isNotEmpty ?? false)
              ? 'xtream-series://${(item['playlistId'] as String?) ?? ''}'
                    '/${item['seriesId']}'
              : item['url'] as String,
      };
      final current = {for (final channel in _allChannels) channel.url};
      if (!setEquals(fresh, current)) {
        await _loadPlaylist(_continuePlaylist);
        return;
      }
    }
    await _loadProgress(_loadTicket, _allChannels);
  }

  /// Add or drop the Continue-watching entry in the picker to match whether
  /// anything is actually half-watched — so the shelf appears after the very
  /// first movie rather than on the next visit to the page, and disappears
  /// once the last item is finished. Selection is left untouched.
  void _refreshContinueShelfPresence(bool hasContinue) {
    final present = _playlists.any((p) => p.isContinueWatching);
    if (hasContinue == present) return;

    setState(() {
      if (hasContinue) {
        // Directly after Favorites, or first when there is no Favorites row.
        final favoritesIndex = _playlists.indexWhere((p) => p.isFavorites);
        _playlists = [..._playlists]
          ..insert(favoritesIndex + 1, _continuePlaylist);
      } else {
        _playlists = [
          for (final p in _playlists)
            if (!p.isContinueWatching) p,
        ];
      }
    });
  }

  /// Re-sync the custom-list rows in the picker after the user created,
  /// renamed, deleted or reordered one, without disturbing what they are
  /// looking at. Same reasoning as [_refreshContinueShelfPresence]: going
  /// through _loadSettings would re-derive the landing selection.
  void _refreshListShelfPresence() {
    if (!mounted) return;
    final desired = [for (final list in _customLists) _listPlaylist(list)];
    final current = [
      for (final p in _playlists)
        if (p.isCustomList) p,
    ];
    // Compare names too, not just ids — a rename has to reach the picker.
    String signature(List<IptvPlaylist> entries) =>
        entries.map((p) => '${p.id}\x00${p.name}').join('\x01');
    if (signature(desired) == signature(current)) return;

    // Rebuild in canonical order: Favorites, Continue, lists, real providers.
    final keptVirtuals = [
      for (final p in _playlists)
        if (p.isFavorites || p.isContinueWatching) p,
    ];
    final realPlaylists = [
      for (final p in _playlists)
        if (!p.isFavorites && !p.isContinueWatching && !p.isCustomList) p,
    ];
    setState(() {
      _playlists = [...keptVirtuals, ...desired, ...realPlaylists];
    });

    // The list being viewed can have just been deleted. Leaving it selected
    // strands the picker: with no matching option the dropdown renders the
    // FIRST option's label, so it would read "Favorites" above the wrong grid.
    final selected = _selectedPlaylist;
    if (selected != null && !_playlists.any((p) => p.id == selected.id)) {
      final fallback = _playlists.isEmpty ? null : _playlists.first;
      if (fallback != null) _onPlaylistChanged(fallback);
    }
  }

  bool _previewRearmPending = false;

  /// Complete a parked preview re-arm (see [_playChannel]).
  void _flushPreviewRearm() {
    if (!_previewRearmPending || !mounted) return;
    _previewRearmPending = false;
    // The startup launch parks its preview suppression here too — this is the
    // designated "we're actually back" hook, and the stage must not remount
    // while the player it launched is still coming up.
    _startupLaunchActive = false;
    _previewEpoch.value++;
    // This fires only after real playback, on both TV return paths (app
    // resume for the native player, next row focus for the in-app fallback) —
    // so it is also exactly when the position the player just saved should be
    // pulled back into the bars and the shelf.
    _refreshAfterPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushPreviewRearm();
      // Android schedules fire NATIVELY (alarm → service) — no in-process
      // revision bump can see that. Coming back to the foreground is the
      // one reliable moment to reconcile the rail's Scheduled badge and the
      // stage's Record↔Stop state.
      unawaited(_refreshScheduledCount());
      unawaited(_refreshAndroidRecordingState());
    }
  }

  /// Sidebar enter = lights out for the preview (Home's grammar: the menu
  /// never competes with a playing stage). Dropping the shown channel unmounts
  /// the backdrop, which releases its engine synchronously; refocusing a
  /// channel row re-arms the stage.
  void _onTvSidebarFocusChanged(bool focused) {
    if (focused) _clearPreview();
  }

  /// Every route into IPTV settings from this page is an "Add playlist"
  /// affordance — the source dropdown's entry, the filter bar's picker, the
  /// empty state's button — so open settings ON the add form rather than
  /// dropping the user at its default landing to go hunting for it.
  // ── Command Center: recording plumbing ──────────────────────────────────

  /// Recording availability for the stage. Deny-by-default: affordances only
  /// ever appear after a positive answer.
  Future<void> _initRecordingSupport() async {
    var can = false;
    if (!kIsWeb && Platform.isAndroid) {
      // needs_permission counts as available — the affordances are how the
      // pre-Q storage grant gets requested in the first place.
      can =
          await LiveRecordingService.engineEnabled() &&
          (await LiveRecordingService.engineSupport()) != 'unsupported';
    } else {
      can = DesktopRecordingService.instance.isSupported;
    }
    if (!mounted) return;
    if (can != _pageCanRecord) setState(() => _pageCanRecord = can);
    unawaited(_refreshScheduledCount());
    unawaited(_refreshAndroidRecordingState());
  }

  Timer? _sourceCountsDebounce;

  /// Re-read the rail's per-source counts from the catalog. Debounced: a
  /// refresh sweep across several sources lands as ONE recompute, and the
  /// reads themselves are a handful of indexed lookups.
  void _recomputeSourceCounts() {
    _sourceCountsDebounce?.cancel();
    _sourceCountsDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !IptvCatalogDb.isOpen) return;
      final counts = <String, int>{};
      for (final p in _playlists) {
        if (p.isVirtual) continue;
        try {
          final stats = IptvSourceStatsLoader.read(p);
          if (stats.cached) counts[p.id] = stats.total;
        } catch (_) {}
      }
      if (!mapEquals(counts, _sourceCounts)) {
        setState(() => _sourceCounts = counts);
      }
    });
  }

  Future<void> _refreshScheduledCount() async {
    var count = 0;
    if (!kIsWeb && Platform.isAndroid) {
      count = (await LiveRecordingService.listSchedules()).length;
    } else if (DesktopScheduleService.instance.isSupported) {
      count = (await DesktopScheduleService.instance.list()).length;
    }
    if (mounted && count != _scheduledCount) {
      setState(() => _scheduledCount = count);
    }
  }

  void _openScheduledRecordings() {
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const RecordingsPage()))
          .then((_) {
            unawaited(_refreshScheduledCount());
            // A capture stopped inside the hub must flip the stage's
            // Record button back too.
            unawaited(_refreshAndroidRecordingState());
          }),
    );
  }

  /// LIVE channels with a capturable URL only. The URL-shape check alone
  /// would also pass VOD movies (direct http, non-segmented) — and "Record"
  /// on a movie is a broken duplicate of Download, spinning the engine on a
  /// static file for up to 6 hours.
  /// Any capture running right now, either backend — drives the classic
  /// header's record-dot. Android state comes from the same url→task map the
  /// stage uses (refreshed at init, on resume, and on hub/player returns);
  /// desktop reads the service directly and repaints via its revision
  /// listener.
  bool get _anyRecordingLive =>
      _androidRecordingsByUrl.isNotEmpty ||
      (DesktopRecordingService.instance.isSupported &&
          DesktopRecordingService.instance.captures.isNotEmpty);

  bool _channelEngineRecordable(IptvChannel channel) =>
      channel.isLive &&
      LiveRecordingService.engineRecordableUrl(channel.url) != null;

  String _stageRecordingFileName(String channelName) {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${base}_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.ts';
  }

  /// Live ANDROID engine captures by url (url → taskId), so the stage's
  /// Record button can read Stop for a channel that's being recorded — same
  /// contract the desktop side already has. Kept fresh by the focus-debounced
  /// query below plus optimistic updates on start/stop.
  final Map<String, String> _androidRecordingsByUrl = {};
  Timer? _androidRecStateDebounce;

  void _armAndroidRecStateRefresh() {
    if (kIsWeb || !Platform.isAndroid || !_pageCanRecord) return;
    _androidRecStateDebounce?.cancel();
    _androidRecStateDebounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_refreshAndroidRecordingState());
    });
  }

  Future<void> _refreshAndroidRecordingState() async {
    if (kIsWeb || !Platform.isAndroid || !_pageCanRecord) return;
    final recordings = await LiveRecordingService.query();
    if (!mounted) return;
    final fresh = <String, String>{
      for (final r in recordings)
        if (r.isRecording) r.url: r.taskId,
    };
    if (!mapEquals(fresh, _androidRecordingsByUrl)) {
      setState(() {
        _androidRecordingsByUrl
          ..clear()
          ..addAll(fresh);
      });
    }
  }

  /// The Android engine task recording [channel], if any (url or Xtream twin).
  String? _androidEngineTaskFor(IptvChannel channel) {
    final direct = _androidRecordingsByUrl[channel.url];
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(channel.url);
    return twin != null ? _androidRecordingsByUrl[twin] : null;
  }

  Future<void> _stageStopAndroidRecording(
    IptvChannel channel,
    String taskId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await LiveRecordingService.stop(taskId);
    if (!mounted) return;
    setState(() {
      _androidRecordingsByUrl.removeWhere((_, id) => id == taskId);
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Recording stopped — saving to Downloads/Debrify/Recordings'
              : "Couldn't stop recording",
        ),
      ),
    );
  }

  /// The desktop capture currently recording [channel], if any — matched on
  /// the channel's URL or its Xtream `.ts` twin. Drives the stage's
  /// Record↔Stop button: with no notifications on desktop, that button is a
  /// page-started capture's ONLY stop surface.
  DesktopRecordingCapture? _desktopCaptureFor(IptvChannel channel) {
    final service = DesktopRecordingService.instance;
    final direct = service.captureForUrl(channel.url);
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(channel.url);
    return twin != null ? service.captureForUrl(twin) : null;
  }

  Future<void> _stageStopDesktopRecording(
    DesktopRecordingCapture capture,
  ) async {
    final savedPath = capture.path;
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await capture.stop();
    if (!mounted) return;
    setState(() {}); // flip the stage button back to Record
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          bytes > 0
              ? 'Recording saved: $savedPath'
              : 'Recording failed — nothing was captured',
        ),
      ),
    );
  }

  /// Stage "Record": start a background capture of [channel] WITHOUT playing
  /// it — the engine on Android, the desktop capture elsewhere.
  Future<void> _stageRecordNow(IptvChannel channel) async {
    final recordUrl = LiveRecordingService.engineRecordableUrl(channel.url);
    if (recordUrl == null) return;
    final messenger = ScaffoldMessenger.of(context);
    // Both recorders behind this button are raw HTTP byte-copiers, and this
    // is the one Record surface with NO player to probe the format. A URL
    // that carries no extension can still answer with an HLS playlist — the
    // engine then kills the capture at its first bytes, long after this code
    // has told the user it started. Ask the server first; only an
    // affirmative playlist answer blocks (see [servesPlaylist]).
    if (!LiveRecordingService.isSchedulableUrl(recordUrl)) {
      // The probe is capped at 3s but still long enough that a silent button
      // reads as broken on a remote — say what's happening.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Checking channel…'),
          duration: Duration(seconds: 3),
        ),
      );
      final playlist = await LiveRecordingService.servesPlaylist(
        recordUrl,
        headers: channel.playbackHeaders,
      );
      if (!mounted) return;
      if (playlist) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              "${channel.name} can't be recorded — it's an adaptive (HLS) "
              'stream. Recording works on progressive/TS channels.',
            ),
          ),
        );
        return;
      }
      messenger.hideCurrentSnackBar();
    }
    if (!mounted) return;
    if (!kIsWeb && Platform.isAndroid) {
      if (!await LiveRecordingService.ensureEngineReady()) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Storage access is needed to save recordings'),
          ),
        );
        return;
      }
      if (!mounted) return;
      if (!await ensureRecordingCapacity(context)) return;
      if (!mounted) return;
      final result = await LiveRecordingService.start(
        url: recordUrl,
        fileName: _stageRecordingFileName(channel.name),
        channelName: channel.name,
        headers: channel.playbackHeaders,
        connectionResourceId: _recordingResourceFor(
          channel,
        )?.connectionResourceId,
        resourceAuthorizationRevision: _recordingResourceFor(
          channel,
        )?.connectionResourceRevision,
      );
      if (!mounted) return;
      if (result.ok) {
        // Optimistic: the stage flips to Stop immediately; the debounced
        // query keeps it honest afterwards.
        setState(() => _androidRecordingsByUrl[recordUrl] = result.id!);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'Recording ${channel.name} — stop from here or the '
                      'notification'
                : switch (result.errorCode) {
                    'recording_limit_reached' =>
                      'Recording limit reached \u2014 free a slot or raise '
                          'the limit in IPTV settings',
                    _ => "Couldn't start recording",
                  },
          ),
        ),
      );
      return;
    }
    if (!DesktopRecordingService.instance.isSupported) return;
    if (!await ensureRecordingCapacity(context)) return;
    if (!mounted) return;
    final path = await DesktopScheduleService.buildRecordingPath(channel.name);
    if (!mounted) return;
    // No onFinished: the revision listener already flips Stop back to Record,
    // and endings are announced app-wide by the reporter in main() — which,
    // unlike this widget, is still around when the capture outlives the page.
    final capture = await DesktopRecordingService.instance.start(
      url: recordUrl,
      path: path,
      channelName: channel.name,
      headers: channel.playbackHeaders,
      connectionResourceId: _recordingResourceFor(
        channel,
      )?.connectionResourceId,
      resourceAuthorizationRevision: _recordingResourceFor(
        channel,
      )?.connectionResourceRevision,
    );
    if (!mounted) return;
    if (capture != null) setState(() {}); // show Stop immediately
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          capture == null
              ? "Couldn't start recording"
              : 'Recording ${channel.name} — stop from this Record button; '
                    'runs while Debrify is open',
        ),
      ),
    );
  }

  /// REC handler for the page's guide surfaces (row-opened sheet, full-day
  /// pane), or null when recording is unavailable or the channel isn't
  /// schedulable — a null hides the REC tags entirely.
  void Function(EpgProgramme programme)? _recordProgrammeActionFor(
    IptvChannel channel,
  ) {
    if (!_pageCanRecord ||
        !LiveRecordingService.isSchedulableUrl(channel.url)) {
      return null;
    }
    return (programme) {
      unawaited(() async {
        final message = await _scheduleProgrammeFromStage(channel, programme);
        if (message != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }());
    };
  }

  /// Stage schedule row → REC. Same flow the channel sheet uses: confirm
  /// dialog, platform-branched backend, honest result copy. Returns the
  /// message the stage shows (null = dismissed).
  Future<String?> _scheduleProgrammeFromStage(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    if (!LiveRecordingService.isSchedulableUrl(channel.url)) {
      return "This channel can't be scheduled — recording needs a direct TS "
          'or Xtream stream';
    }
    final recordUrl = LiveRecordingService.engineRecordableUrl(channel.url);
    if (recordUrl == null || !mounted) return null;
    if (!kIsWeb &&
        Platform.isAndroid &&
        !await LiveRecordingService.ensureEngineReady()) {
      return 'Storage access is needed to save recordings';
    }
    if (!mounted) return null;
    if (!await ensureRecordingCapacity(
      context,
      startMs: programme.start.millisecondsSinceEpoch,
      endMs: programme.stop.millisecondsSinceEpoch,
      candidateUrl: recordUrl,
    )) {
      return null;
    }
    if (!mounted) return null;
    String clock(DateTime t) => MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final airsNow =
        !programme.start.isAfter(DateTime.now()) &&
        programme.stop.isAfter(DateTime.now());
    final app = AppThemeScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: app.iptv.modalBg,
        title: Text(
          'Record programme',
          style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${programme.title}\n'
          '${channel.name} · ${clock(programme.start)} – '
          '${clock(programme.stop)}'
          '${airsNow ? '\n\nAlready airing — records the rest, '
                    'from now until it ends.' : ''}',
          style: TextStyle(color: app.core.tx.withAlpha(0xB3), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return null;
    final resource = _recordingResourceFor(channel);
    final result = (!kIsWeb && Platform.isAndroid)
        ? await LiveRecordingService.schedule(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
            connectionResourceId: resource?.connectionResourceId,
            resourceAuthorizationRevision: resource?.connectionResourceRevision,
          )
        : await DesktopScheduleService.instance.add(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
            connectionResourceId: resource?.connectionResourceId,
            resourceAuthorizationRevision: resource?.connectionResourceRevision,
          );
    unawaited(_refreshScheduledCount());
    if (result.errorCode == 'exact_alarms_required') {
      return 'Allow "Alarms & reminders" for Debrify to schedule recordings';
    }
    return result.ok
        ? (airsNow
              ? 'Recording starts in a few seconds'
              : 'Recording scheduled')
        : switch (result.errorCode) {
            'duplicate' => 'Already scheduled',
            'overlap' => 'Overlaps another scheduled recording',
            'bad_time' => 'This programme is already over',
            _ => "Couldn't schedule recording",
          };
  }

  void _navigateToSettings() {
    // Captured for the EPG-URL-edit case below: _loadSettings only reloads
    // the playlist when the SELECTION changes, so an edit to the current
    // playlist's guide URL would otherwise sit inert until a manual playlist
    // switch — "EPG URL saved" with nothing happening.
    final beforeId = _selectedPlaylist?.id;
    final beforeEpgUrl = _selectedPlaylist?.epgUrl;
    // Settings owns the hidden-categories manager, so a trip through it can
    // reveal (or hide) a category behind this page's back. Captured here
    // because _loadSettings only reloads the catalog when the SELECTION
    // changes — otherwise the facades keep the row count and category list
    // they were built with while the category was hidden.
    final beforeHidden = _hiddenCategories;
    final beforeCatalogKey = _dbSnapshot?.catalogKey;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const IptvSettingsPage(openAddSource: true),
          ),
        )
        .then((_) async {
          // Reload settings when returning
          await _loadSettings();
          if (!mounted) return;
          // Only for the SAME catalog: a settings trip that changed the
          // selection has already been re-presented from scratch, hidden set
          // included, and comparing across two catalogs' rules is meaningless.
          final snap = _dbSnapshot;
          if (snap != null &&
              snap.catalogKey == beforeCatalogKey &&
              !setEquals(
                beforeHidden,
                IptvCatalogDb.hiddenGroups(snap.catalogKey),
              )) {
            await _refreshAfterHiddenChange();
            if (!mounted) return;
          }
          // Settings is where the recording-engine toggle lives: re-probe so
          // enabling exposes the stage/rail affordances immediately, and
          // disabling actually takes them away instead of leaving Record and
          // scheduling active until the page remounts.
          unawaited(_initRecordingSupport());
          final current = _selectedPlaylist;
          final result = _lastLoadResult;
          if (current != null &&
              current.id == beforeId &&
              current.epgUrl != beforeEpgUrl &&
              result != null) {
            _updateEpgContext(current, result, _loadTicket);
          }
        });
  }

  /// Focus the first filter (for DPAD navigation from search input)
  @override
  void focusFirstFilter() {
    _playlistFilterFocusNode.requestFocus();
  }

  /// Focus the first channel card (for DPAD navigation from filters)
  void _focusFirstChannel() {
    // Only focus if we have filtered channels
    if (_filteredChannels.isNotEmpty) {
      _focusNodeFor(_filteredChannels.first).requestFocus();
    }
  }

  /// Refresh playlists from storage (call after settings change)
  Future<void> refreshPlaylists() async {
    await _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      final settingsError = _settingsError;
      if (settingsError == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Could not open IPTV',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                settingsError,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                autofocus: true,
                onPressed: () {
                  setState(() => _settingsError = null);
                  unawaited(_loadSettings(forceReload: true));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // TV: focus selects the embedded preview. Desktop: hover selects and click
    // watches. A large touch tablet gets the same two-pane shell but scrolls
    // rows beneath a fixed center arrow; the settled row owns the preview and
    // a separate stage button launches fullscreen. Constrained tablet windows
    // and phones retain the classic page.
    final Widget body = LayoutBuilder(
      builder: (context, c) {
        final touchTablet = shouldUseTouchTabletTwoPane(
          isTelevision: widget.isTelevision,
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
          availableSize: Size(c.maxWidth, c.maxHeight),
        );
        final eligible = widget.isTelevision || _isDesktop || touchTablet;
        final twoPane = eligible && c.maxWidth >= 760 && c.maxHeight >= 380;
        if (twoPane != _tvTwoPaneActive ||
            touchTablet != _touchTabletTwoPaneActive) {
          // Never write state synchronously from the layout phase: playback
          // and schedule callbacks consult these flags. One post-frame of lag
          // can only occur while the window is actively changing size.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final wasTouchTablet = _touchTabletTwoPaneActive;
            _tvTwoPaneActive = twoPane;
            _touchTabletTwoPaneActive = twoPane && touchTablet;
            if (!twoPane &&
                wasTouchTablet &&
                _scheduleChannel != null &&
                mounted) {
              setState(() => _scheduleChannel = null);
            }
          });
        }
        if (!twoPane) return _buildClassic();
        return _buildTvTwoPane(c, touchSelector: touchTablet);
      },
    );
    // The background-refresh chip floats over whichever layout is active.
    // passthrough: hand the parent's constraints to the body unmodified so
    // the wrap is provably layout-neutral. The iOS notice wraps only while
    // visible, so every other platform's layout path stays byte-identical.
    final Widget page = _showIosRecordingNotice
        ? Column(
            children: [
              _buildIosRecordingNotice(),
              Expanded(child: body),
            ],
          )
        : body;
    return Stack(
      fit: StackFit.passthrough,
      children: [page, _buildCatalogChip()],
    );
  }

  /// The iOS-only "no recording here" banner: dismiss is remembered forever.
  Widget _buildIosRecordingNotice() {
    final app = AppThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
      decoration: BoxDecoration(
        color: app.iptv.surfaceTint,
        borderRadius: app.shape.br(10),
        border: Border.all(color: app.iptv.hairline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.fiber_manual_record_rounded,
            size: 14,
            color: app.core.tx.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Recording isn't available on iOS — Apple doesn't let "
              'apps capture streams in the background.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: app.iptv.inkDim,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: app.core.tx.withValues(alpha: 0.45),
            ),
            onPressed: _dismissIosRecordingNotice,
          ),
        ],
      ),
    );
  }

  void _dismissIosRecordingNotice() {
    setState(() => _showIosRecordingNotice = false);
    unawaited(
      DevicePreferences.instance().then(
        (prefs) => prefs.setBool(_iosNoticeDismissedPref, true),
      ),
    );
  }

  /// Bottom-right status chip for background catalog refreshes. Pure
  /// display: no focusables, no hit-testing — DPAD and touch pass straight
  /// through. Snap show/hide, no tween (TV GPU rule).
  Widget _buildCatalogChip() {
    final app = AppThemeScope.of(context);
    if (_chipState == _CatalogChipState.hidden) {
      return const SizedBox.shrink();
    }
    final Widget leading = switch (_chipState) {
      _CatalogChipState.updating => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: app.seeAll.accent2,
        ),
      ),
      _CatalogChipState.success => const Icon(
        Icons.check_circle_rounded,
        size: 15,
        color: Color(0xFF4ADE80),
      ),
      _CatalogChipState.failure => const Icon(
        Icons.cloud_off_rounded,
        size: 15,
        color: Color(0xFFFBBF24),
      ),
      _CatalogChipState.hidden => const SizedBox.shrink(),
    };
    return Positioned(
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: app.iptv.chipSurface,
            borderRadius: app.shape.br(22),
            border: Border.all(color: app.core.tx.withValues(alpha: 0.10)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 8),
              Text(
                _chipMessage,
                style: TextStyle(
                  fontSize: 12.5,
                  color: app.core.tx.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The single-pane layout: boxed filter bar over a full-width channel list.
  /// Phones keep it (no embedded preview there), and TV/desktop fall back to
  /// it when the canvas can't fit two panes.
  Widget _buildClassic() {
    return Column(
      children: [
        // Filters bar
        IptvFiltersBar(
          playlists: _playlists,
          selectedPlaylist: _selectedPlaylist,
          categories: _categories,
          selectedCategory: _selectedCategory,
          categoryCounts: _categoryCounts,
          channelCount: _filteredChannels.length,
          isLoading: _isLoading,
          isLoadingMore: _isLoadingMore,
          onPlaylistChanged: _onPlaylistChanged,
          onCategoryChanged: _onCategoryChanged,
          onAddPlaylist: _navigateToSettings,
          playlistFocusNode: _playlistFilterFocusNode,
          categoryFocusNode: _categoryFilterFocusNode,
          showContentTypeFilter: _selectedPlaylist?.isXtreamCodes ?? false,
          selectedContentType: _selectedContentType,
          onContentTypeChanged: _onContentTypeChanged,
          contentTypeFocusNode: _contentTypeFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _focusFirstChannel,
          onOpenRecordings: _pageCanRecord ? _openScheduledRecordings : null,
          recordingLive: _anyRecordingLive,
          onCategoryOptions: _canShowCategoryOptions
              ? _promptCategoryOptions
              : null,
        ),

        // Content
        Expanded(child: _buildContent()),
      ],
    );
  }

  // ── TV two-pane ──────────────────────────────────────────────────────────

  Widget _buildTvTwoPane(BoxConstraints c, {required bool touchSelector}) {
    // Every source (Favorites, Continue watching, and each playlist) lives in
    // the header's Sources dropdown now — no left rail eating horizontal space.
    // TV uses a wider focus stage; desktop keeps the compact preview rail so a
    // resizable window never gives up too much guide space.
    final paneW = c.maxWidth;
    final scheduleChannel = _scheduleChannel;

    // An open schedule covers the guide column in place — the preview
    // keeps playing, and BACK restores the list exactly as it was. Offstage
    // (not a swap) keeps the grid, its scroll offset and its focus nodes
    // alive, so closing can hand focus straight back to the originating row;
    // ExcludeFocus keeps DPAD from wandering into the hidden rows meanwhile.
    Widget guideStack({required bool cockpit}) => Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: scheduleChannel != null,
          child: ExcludeFocus(
            excluding: scheduleChannel != null,
            // The LayoutBuilder is inside the Stack (bounded), so the styled
            // branches can gate their display inserts on the real guide
            // height. The command branch below it is the shipped tree,
            // untouched.
            child: LayoutBuilder(
              builder: (context, gc) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 24, 4),
                    child: _buildQuietFilters(),
                  ),
                  // First Edition's editorial hero — display-only (no focus
                  // nodes), inside the Offstage subtree so the schedule pane
                  // covers it. Gate = every vertical consumer at worst case:
                  // filter line ~50 + hero 128 + progressive-status line ~24
                  // + grid top pad 8 + 4 tall EPG rows (4x118) + 3 gaps
                  // (3x4) = 694 → 700 with margin, so >=4 full rows always
                  // survive the insert.
                  if (cockpit &&
                      _iptvStyle == IptvStyle.edition &&
                      gc.maxHeight >= 700)
                    IptvEditionHero(
                      channel: _previewShown,
                      tokens: IptvStyleTokens.edition,
                      suspended: scheduleChannel != null,
                    ),
                  // Master Control's 6-hour strip — same display-only rules
                  // as the hero. Same budget with its own 96px height:
                  // 50 + 96 + 24 + 8 + 472 + 12 = 662 → 670 with margin.
                  if (cockpit &&
                      _iptvStyle == IptvStyle.console &&
                      gc.maxHeight >= 670)
                    IptvConsoleTimeline(
                      channel: _previewShown,
                      tokens: IptvStyleTokens.console,
                      suspended: scheduleChannel != null,
                    ),
                  Expanded(
                    child: _buildContent(
                      tvPane: true,
                      touchSelector: touchSelector,
                      cockpit: cockpit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (scheduleChannel != null)
          IptvSchedulePane(
            channel: scheduleChannel,
            onClose: _closeSchedulePane,
            isTelevision: widget.isTelevision,
            onPlayProgramme: (programme) =>
                _playCatchup(scheduleChannel, programme),
            // The full-day guide records too — same gates and confirm flow
            // as the stage's compact list (it was the one schedule surface
            // that never got the callback).
            onRecordProgramme: _recordProgrammeActionFor(scheduleChannel),
          ),
      ],
    );

    if (!touchSelector) {
      // Command Center (TV + desktop pointer): rail → guide → stage cockpit.
      // Geometry does the DPAD work — the rail's focusables sit left of the
      // grid, the stage's actions sit right of it, and LEFT from the rail
      // bubbles to the shell's global action (the app sidebar) untouched.
      final railW = paneW >= 1150 ? 196.0 : 172.0;
      final cockpitStageW = (paneW * (paneW >= 1200 ? 0.34 : 0.36)).clamp(
        300.0,
        480.0,
      );
      final cockpitTokens = IptvStyleTokens.of(_iptvStyle);
      final cockpitRow = Row(
        key: const ValueKey('iptv-cockpit'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railW,
            child: IptvCommandRail(
              tokens: cockpitTokens,
              playlists: _playlists,
              selectedPlaylist: _selectedPlaylist,
              customLists: _lists,
              sourceCounts: _sourceCounts,
              favoritesCount: _favoriteUrls.length,
              scheduledCount: _scheduledCount,
              // focusContent: OK is a decision, so it lands DPAD on the
              // channels it just loaded. (Merely walking RIGHT does not
              // select — it traverses into the guide, which still shows the
              // selected source.)
              onSelectPlaylist: (p) =>
                  _onPlaylistChanged(p, focusContent: true),
              onOpenScheduled: _openScheduledRecordings,
              onManageSources: _navigateToSettings,
              // Engine off / unsupported: don't advertise a scheduler that
              // would refuse to work (settings hides its row in this state).
              showScheduled: _pageCanRecord,
            ),
          ),
          Expanded(
            // Styled looks paint the guide column's background HERE, not as
            // one sheet under the whole cockpit: the stage's RepaintBoundary
            // is its own compositing layer, so the preview's BlendMode.clear
            // hole cannot erase paint living in an ancestor layer — a page-
            // wide ColoredBox turns the live underlay video into an opaque
            // block (frozen frame + audio-only on TV). The rail and status
            // bar paint their own; the stage's panel color already lives
            // INSIDE the boundary where the hole clears it.
            child: cockpitTokens == null
                ? guideStack(cockpit: true)
                : ColoredBox(
                    color: cockpitTokens.bg,
                    child: guideStack(cockpit: true),
                  ),
          ),
          SizedBox(width: cockpitStageW, child: _buildCockpitStage()),
        ],
      );
      // NO ColoredBox around the cockpit row — see the guide-column note
      // above (the underlay hole must composite against transparency all the
      // way down). Master Control adds its status strip above the cockpit —
      // the Row stays bounded inside the Expanded.
      if (cockpitTokens == null) return cockpitRow;
      if (_iptvStyle == IptvStyle.console) {
        return Column(
          children: [
            IptvConsoleStatusBar(
              tokens: cockpitTokens,
              sourceName: _selectedPlaylist?.name ?? 'IPTV',
              channelCount: _filteredChannels.length,
              recCount: (!kIsWeb && Platform.isAndroid)
                  ? _androidRecordingsByUrl.length
                  : DesktopRecordingService.instance.isSupported
                  ? DesktopRecordingService.instance.captures.length
                  : 0,
              schedCount: _scheduledCount,
              statusText: _chipState == _CatalogChipState.hidden
                  ? null
                  : _chipMessage,
              // The Android url→task map refreshes on selected events only;
              // the bar's tick reconciles it so REC can't sit stale while
              // focus is parked (no-op off Android / when recording is off).
              onTick: () => unawaited(_refreshAndroidRecordingState()),
            ),
            Expanded(child: cockpitRow),
          ],
        );
      }
      return cockpitRow;
    }

    // Touch tablet keeps the shipped preview-left arrangement unchanged.
    final stageW = (paneW * 0.40).clamp(320.0, 470.0);
    return Row(
      key: const ValueKey('iptv-tablet-two-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: stageW,
          child: _buildPreviewRail(touchSelector: touchSelector),
        ),
        Expanded(child: guideStack(cockpit: false)),
      ],
    );
  }

  /// The Command Center stage: live preview on top, identity + now/next,
  /// then the action row and the focused channel's compact day schedule
  /// (IptvStagePanel). One RepaintBoundary so the preview's frames never
  /// re-rasterize the panel and vice versa.
  Widget _buildCockpitStage() {
    final app = AppThemeScope.of(context);
    return _stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 14, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewShown,
            builder: (context, ch, _) {
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: app.shape.br(10),
                  child: ColoredBox(
                    color:
                        IptvStyleTokens.of(_iptvStyle)?.panel ??
                        app.iptv.stageBg,
                    child: ch == null
                        ? const SizedBox.expand()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // UNDERLAY RULE (device-verified 2026-08-05):
                              // the preview subtree is handed over UNWRAPPED,
                              // byte-identical to the shipped Command Center
                              // path. Wrapping it (a CustomPaint, a Column, a
                              // foregroundDecoration Container) froze the
                              // underlay video on Android TV — frozen frame +
                              // audio-only. Styled chrome therefore lives as
                              // SIBLINGS: the caption below is a plain child
                              // of this ALREADY-EXISTING Column, and the
                              // brackets/frame paint inside the preview's own
                              // Stack next to the status chip.
                              _buildPreviewStage(ch, epoch),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: _cockpitIdentity(ch),
                              ),
                              Expanded(
                                // Rebuilds when an XMLTV guide finishes loading
                                // (contextVersion), so a channel that probed
                                // "no EPG" a moment ago gets its schedule.
                                child: ValueListenableBuilder<int>(
                                  valueListenable:
                                      IptvEpgService.instance.contextVersion,
                                  builder: (context, epgVersion, _) {
                                    final desktopCapture = _desktopCaptureFor(
                                      ch,
                                    );
                                    final androidTask =
                                        (!kIsWeb && Platform.isAndroid)
                                        ? _androidEngineTaskFor(ch)
                                        : null;
                                    return IptvStagePanel(
                                      key: ValueKey('stage-${ch.url}'),
                                      tokens: IptvStyleTokens.of(_iptvStyle),
                                      channel: ch,
                                      isTelevision: widget.isTelevision,
                                      isFavorited: _favoriteUrls.contains(
                                        ch.url,
                                      ),
                                      canRecord: _pageCanRecord,
                                      isRecordingThis:
                                          desktopCapture != null ||
                                          androidTask != null,
                                      epgContextVersion: epgVersion,
                                      onWatch: () =>
                                          unawaited(_playChannel(ch)),
                                      onExitLeft: _returnFocusFromStage,
                                      onRecordNow: desktopCapture != null
                                          ? () => unawaited(
                                              _stageStopDesktopRecording(
                                                desktopCapture,
                                              ),
                                            )
                                          : androidTask != null
                                          ? () => unawaited(
                                              _stageStopAndroidRecording(
                                                ch,
                                                androidTask,
                                              ),
                                            )
                                          : _channelEngineRecordable(ch)
                                          ? () => unawaited(_stageRecordNow(ch))
                                          : null,
                                      // _toggleFavorite takes the DESIRED state
                                      // (the row passes !isFavorited too) —
                                      // passing the current one would write a
                                      // no-op.
                                      onToggleFavorite:
                                          ch.contentType == 'series'
                                          ? null
                                          : () => unawaited(
                                              _toggleFavorite(
                                                ch,
                                                !_favoriteUrls.contains(ch.url),
                                              ),
                                            ),
                                      // Only when a guide can exist — otherwise
                                      // the pane could only say "No guide data".
                                      onOpenFullSchedule:
                                          IptvEpgService.isEpgCapable(ch)
                                          ? () => _openSchedulePane(ch)
                                          : null,
                                      // Stricter than Record-now: scheduling has
                                      // no player probe at alarm time, so REC
                                      // rows only appear on affirmatively-TS/
                                      // Xtream channels — never a tag that gets
                                      // refused on press.
                                      onScheduleProgramme:
                                          LiveRecordingService.isSchedulableUrl(
                                            ch.url,
                                          )
                                          ? _scheduleProgrammeFromStage
                                          : null,
                                      onPlayProgramme: (c, p) =>
                                          unawaited(_playCatchup(c, p)),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Compact identity header for the cockpit: logo chip, CH number + name,
  /// group/resolution sub-line, then the shared now/next EPG card.
  Widget _cockpitIdentity(IptvChannel channel) {
    final app = AppThemeScope.of(context);
    final t = IptvStyleTokens.of(_iptvStyle);
    final isConsole = _iptvStyle == IptvStyle.console;
    // Styled looks never paint the brand color.
    final brand = t == null ? brandAccentFor(channel.name) : Colors.transparent;
    final resMatch = _railResExp.firstMatch(channel.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? channel.name
        : channel.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final group = channel.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: t == null
                  ? BoxDecoration(
                      borderRadius: app.shape.br(8),
                      border: Border.all(color: app.iptv.hairline),
                      color: Color.alphaBlend(
                        brand.withValues(alpha: 0.18),
                        const Color(0xFF171B19),
                      ),
                    )
                  : BoxDecoration(
                      shape: isConsole ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isConsole ? app.shape.br(6) : null,
                      border: Border.all(color: t.hairline2),
                      color: t.fg.withValues(alpha: 0.03),
                    ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: channel.logoUrl!,
                        cacheManager: DebrifyImageCache.iptvLogos,
                        fit: BoxFit.contain,
                        memCacheHeight: 96,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.live_tv_rounded,
                          size: 16,
                          color: t?.fgDim ?? brand.withValues(alpha: 0.85),
                        ),
                      )
                    : Icon(
                        Icons.live_tv_rounded,
                        size: 16,
                        color: t?.fgDim ?? brand.withValues(alpha: 0.85),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.channelNumber == null
                        ? displayName
                        : 'CH ${channel.channelNumber}  $displayName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t == null
                        ? TextStyle(
                            color: app.core.tx,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          )
                        : TextStyle(
                            color: t.fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                            fontFamily: t.nameFamily.isEmpty
                                ? null
                                : t.nameFamily,
                          ),
                  ),
                  if (subParts.isNotEmpty)
                    Text(
                      subParts.join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t == null
                          ? TextStyle(
                              color: app.core.tx.withValues(alpha: 0.5),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            )
                          : TextStyle(
                              color: t.fgDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              fontFamily: t.monoFamily.isEmpty
                                  ? null
                                  : t.monoFamily,
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        IptvRailEpgCard(
          channel: channel,
          stageOverlay: true,
          dense: true,
          tokens: t,
        ),
      ],
    );
  }

  /// The Discover-style quiet filter line: bare dot-separated text segments
  /// (source • [Live/Movies] • category • count) instead of boxed pills.
  Widget _buildQuietFilters() {
    final app = AppThemeScope.of(context);
    return SeeAllFilterBar(
      isTelevision: widget.isTelevision,
      quiet: true,
      buildChips: () => [
        // The Sources dropdown — EVERY source in one place: Favorites,
        // Continue watching, and each playlist. Replaces the old left rail.
        // Holds _playlistFilterFocusNode so every wire into "the first filter"
        // (down-from-search-field, revalidate focus repair, focusFirstFilter)
        // keeps working.
        StremioDropdown<String>(
          value: _selectedPlaylist?.id ?? '',
          quiet: true,
          quietAccent: true,
          isTelevision: widget.isTelevision,
          focusNode: _playlistFilterFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _focusFirstChannel,
          options: _sourceDropdownOptions(),
          onSelected: (id) {
            if (id == _kNewListSentinel) {
              _promptCreateList();
              return;
            }
            if (id == _kAddPlaylistSentinel) {
              _navigateToSettings();
              return;
            }
            if (id == _kAddAddonSentinel) {
              _navigateToAddons();
              return;
            }
            for (final p in _playlists) {
              if (p.id == id) {
                _onPlaylistChanged(p);
                return;
              }
            }
          },
        ),
        if (_selectedPlaylist?.isXtreamCodes ?? false)
          StremioDropdown<String>(
            label: 'type',
            value: _selectedContentType,
            quiet: true,
            isTelevision: widget.isTelevision,
            focusNode: _contentTypeFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: const [
              StremioDropdownOption('live', 'Live TV'),
              StremioDropdownOption('vod', 'Movies'),
              StremioDropdownOption('series', 'Series'),
            ],
            onSelected: _onContentTypeChanged,
          ),
        if (_categories.isNotEmpty)
          StremioDropdown<String>(
            label: 'category',
            value: _selectedCategory ?? '',
            quiet: true,
            isTelevision: widget.isTelevision,
            focusNode: _categoryFilterFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: [
              StremioDropdownOption('', 'All · ${_allChannels.length}'),
              for (final cat in _categories)
                StremioDropdownOption(
                  cat,
                  '$cat · ${_categoryCounts[cat] ?? 0}',
                  // "All" is deliberately not holdable — there is no such
                  // category to hide.
                  holdable: _canShowCategoryOptions,
                ),
            ],
            holdHint: widget.isTelevision
                ? 'HOLD OK FOR OPTIONS'
                : 'HOLD FOR OPTIONS',
            onOptionHold: _promptCategoryOptions,
            onSelected: (v) => _onCategoryChanged(v.isEmpty ? null : v),
          ),
        // Non-focusable count — DPAD skips straight over it.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(
            _isLoading
                ? 'Loading…'
                : '${_filteredChannels.length} channel'
                      '${_filteredChannels.length == 1 ? '' : 's'}'
                      // The list is still streaming in — never present a
                      // partial count as final.
                      '${_isLoadingMore ? ' • loading more…' : ''}',
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.40),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  static const String _kAddPlaylistSentinel = '__iptv_add_playlist__';
  static const String _kNewListSentinel = '__iptv_new_list__';
  static const String _kAddAddonSentinel = '__iptv_add_addon__';

  /// The Sources dropdown, grouped: the two derived shelves, then the user's
  /// own lists, their playlists, and any live-TV catalogs their Stremio addons
  /// expose — each ending with the action that adds another one of its kind.
  ///
  /// The grouping mirrors the order [_loadSettings] already builds, so this
  /// only draws the lines where the list already changes character.
  List<StremioDropdownOption<String>> _sourceDropdownOptions() {
    final quickAccess = [
      for (final p in _playlists)
        if (p.isFavorites || p.isContinueWatching) p,
    ];
    final lists = [
      for (final p in _playlists)
        if (p.isCustomList) p,
    ];
    final addons = [
      for (final p in _playlists)
        if (p.isStremioAddon) p,
    ];
    final playlists = [
      for (final p in _playlists)
        if (!p.isVirtual) p,
    ];

    return [
      if (quickAccess.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_quick__', 'Quick access'),
        for (final p in quickAccess) StremioDropdownOption(p.id, p.name),
      ],
      // Always shown, empty or not — it is where "New list" lives, and a user
      // with no lists yet is exactly who needs to find it.
      const StremioDropdownOption.header('__hdr_lists__', 'Your lists'),
      for (final p in lists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(_kNewListSentinel, '＋ New list'),
      const StremioDropdownOption.header('__hdr_playlists__', 'Your playlists'),
      for (final p in playlists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(_kAddPlaylistSentinel, '＋ Add playlist'),
      // Only for people who actually run addons — an empty section would push
      // Stremio at everyone else.
      if (addons.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_addons__', 'Stremio Addons'),
        for (final p in addons) StremioDropdownOption(p.id, p.name),
        const StremioDropdownOption(_kAddAddonSentinel, '＋ Add addon'),
      ],
    ];
  }

  /// Open the Addons hub. Tab-switch rather than a pushed route: the hub is a
  /// tab body with no app bar of its own, so pushing it would strand the user
  /// with no way back.
  void _navigateToAddons() {
    MainPageBridge.switchTab?.call(MainTab.addons);
  }

  /// Stage LEFT-exit: land on the exact row the stage was opened from — the
  /// row that owns the preview — so the return trip never retunes the stream.
  /// Geometric traversal would pick the nearest row instead, refocusing a
  /// DIFFERENT channel and reloading the preview twice on the way back.
  void _returnFocusFromStage() {
    // Full-schedule pane open: the grid is ExcludeFocus'd, so a row focus
    // request would silently strand DPAD. The pane owns navigation (its own
    // LEFT/BACK close it); the stage's LEFT just stays put.
    if (_scheduleChannel != null) return;
    final channel = _previewShown.value;
    if (channel != null && _rowAttached(channel)) {
      _focusNodeFor(channel).requestFocus();
      return;
    }
    _focusFirstChannel();
  }

  /// True while the pointer sits inside the preview stage. See
  /// [_stageHoverGuard].
  bool _pointerInStage = false;

  /// Lets a preview stage claim the pointer, so nothing repoints it while the
  /// cursor is inside on its way to Watch or Record. A row the pointer RESTS on
  /// is exempt (see [_onChannelFocused]) — the cursor cannot be on a row and in
  /// the stage at once, so that exemption also means a flag left stuck true by
  /// a missed onExit can never strand the hover preview.
  Widget _stageHoverGuard(Widget child) {
    if (widget.isTelevision) return child;
    return MouseRegion(
      onEnter: (_) => _pointerInStage = true,
      onExit: (_) => _pointerInStage = false,
      child: child,
    );
  }

  /// Called by a channel row gaining DPAD focus, or by a pointer resting on it
  /// ([fromPointer]) — retunes the preview stage.
  void _onChannelFocused(IptvChannel channel, {bool fromPointer = false}) {
    // Focus-driven retargets (a reload refocusing the first channel, a restore
    // after a route pops) must not swap the panel out from under a cursor
    // already inside it. Only once something IS shown: the very first
    // population has to land even if the pointer happens to be parked there.
    if (!fromPointer && _pointerInStage && _previewShown.value != null) return;
    // The in-app player fallback never pauses the app, so a parked re-arm
    // wouldn't flush via the lifecycle observer — the focus restore after its
    // route pops (or the user's next move) lands here instead.
    _flushPreviewRearm();
    final shown = _previewShown.value;
    if (identical(shown, channel)) return;
    _previewShown.value = channel;
    if (_channelPreviewEnabled) {
      _retunePreview(channel);
    } else {
      _stopPreviewPlayback();
    }
    // Keep the stage's Record↔Stop honest for whichever channel is focused
    // now (debounced — zapping through rows costs nothing).
    _armAndroidRecStateRefresh();
  }

  /// Point the stage at the focused channel's stream. M3U/Xtream channels
  /// carry their URL; Stremio channels resolve theirs first (the 900ms dwell
  /// hides most of that latency) and start the candidate ladder.
  void _retunePreview(IptvChannel channel) {
    _previewResolveTicket++;
    final ticket = _previewResolveTicket;
    _previewCandidates = null;
    // Series carry a sentinel URL, not a stream — the stage rests on its
    // floor (logo slab), like a channel with nothing playable.
    if (channel.contentType == 'series') {
      _previewStreamUrl.value = null;
      _previewShowing.value = false;
      return;
    }
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _previewStreamUrl.value = channel.url;
      return;
    }
    // Unmounting the backdrop skips its teardown notification — reset the
    // "has frames" chip state ourselves or it would keep reading LIVE.
    _previewStreamUrl.value = null;
    _previewShowing.value = false;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || ticket != _previewResolveTicket) return;
      // No playable streams — the stage stays on its floor, exactly like a
      // dead M3U channel.
      if (found.isEmpty) return;
      final urls = [for (final c in found) c.url];
      _previewCandidates = urls;
      _previewStreamUrl.value = urls.first;
    });
  }

  /// The stage's current stream genuinely failed (refused to open, errored, or
  /// stalled past the first-frame timeout). Stremio channels step down their
  /// candidate ladder; anything else keeps the old behavior (silent floor).
  /// [ticket] is the ladder generation the failing backdrop was built for —
  /// the notification is post-frame, so by the time it lands the focus may
  /// already be on another channel whose ladder must not be touched.
  void _onPreviewPlaybackFailed(int ticket) {
    if (ticket != _previewResolveTicket) return;
    final candidates = _previewCandidates;
    final current = _previewStreamUrl.value;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0) return; // stale failure for a URL we've already moved off
    if (next >= candidates.length) {
      // Every candidate is dead: drop back to the floor and forget the cached
      // list so a later attempt re-resolves fresh links.
      final shown = _previewShown.value;
      if (shown != null) StremioIptvService.instance.invalidate(shown.url);
      _previewStreamUrl.value = null;
      _previewShowing.value = false;
      return;
    }
    _previewStreamUrl.value = candidates[next];
  }

  /// First frames arrived — remember which candidate actually plays so the
  /// next preview/play of this channel starts there. Same staleness guard as
  /// the failure path: frames from a previous channel's engine must not
  /// crown the new channel's candidate.
  void _markPreviewWinner(int ticket) {
    if (ticket != _previewResolveTicket) return;
    final shown = _previewShown.value;
    final current = _previewStreamUrl.value;
    if (shown == null || current == null || _previewCandidates == null) return;
    if (StremioIptvService.isStremioChannelUrl(shown.url)) {
      StremioIptvService.instance.markWinner(shown.url, current);
    }
  }

  /// Release the embedded stream and abandon any in-flight Stremio resolve,
  /// while leaving the selected channel's artwork, metadata and actions in
  /// the stage. This is the persistent-setting path.
  void _stopPreviewPlayback() {
    _previewResolveTicket++;
    _previewCandidates = null;
    _previewStreamUrl.value = null;
    _previewShowing.value = false;
  }

  /// Empty the stage entirely (playlist switch, sidebar open) and abandon any
  /// in-flight resolve.
  void _clearPreview() {
    _stopPreviewPlayback();
    _previewShown.value = null;
  }

  Widget _buildPreviewRail({required bool touchSelector}) {
    final app = AppThemeScope.of(context);
    return _stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewShown,
            builder: (context, ch, _) {
              if (widget.isTelevision) {
                return _buildTvFocusStage(ch, epoch);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPreviewStage(ch, epoch),
                  const SizedBox(height: 16),
                  Expanded(child: _IptvRailInfo(channel: ch)),
                  if (touchSelector) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('iptv-tablet-watch-fullscreen'),
                        onPressed: ch == null
                            ? null
                            : () => unawaited(_playChannel(ch)),
                        style: FilledButton.styleFrom(
                          backgroundColor: app.seeAll.accent,
                          foregroundColor: app.inkOn(app.seeAll.accent),
                          disabledBackgroundColor: app.seeAll.panel2.withValues(
                            alpha: 0.72,
                          ),
                          disabledForegroundColor: app.core.tx.withValues(
                            alpha: 0.30,
                          ),
                          overlayColor: app.seeAll.accent2.withValues(
                            alpha: 0.18,
                          ),
                          shadowColor: app.seeAll.accent.withValues(
                            alpha: 0.34,
                          ),
                          elevation: 0,
                          side: BorderSide(
                            color: app.seeAll.accent2.withValues(alpha: 0.46),
                          ),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: app.shape.br(13),
                          ),
                        ),
                        icon: Icon(
                          ch?.contentType == 'series'
                              ? Icons.video_library_rounded
                              : Icons.fullscreen_rounded,
                          size: 21,
                        ),
                        label: Text(
                          ch?.contentType == 'series'
                              ? 'Open series'
                              : 'Watch fullscreen',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        _channelPreviewEnabled
                            ? 'Scroll channels through the arrow to preview'
                            : 'Preview is off · choose Watch fullscreen',
                        style: TextStyle(
                          color: app.seeAll.accent2.withValues(alpha: 0.66),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _channelPreviewEnabled
                            ? 'Hover a channel to preview  ·  Click to watch'
                            : 'Preview is off  ·  Click to watch',
                        style: TextStyle(
                          color: app.iptv.inkFaint,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Television's preview-first composition: a true 16:9 video surface in the
  /// upper section, with identity, EPG and key hints on a separate lower
  /// surface. Keeping chrome outside the video avoids cover-cropping a normal
  /// broadcast into a tall stage.
  Widget _buildTvFocusStage(IptvChannel? ch, int epoch) {
    final app = AppThemeScope.of(context);
    return ClipRRect(
      borderRadius: app.shape.br(8),
      child: ColoredBox(
        color: app.iptv.stageBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPreviewStage(ch, epoch),
            Expanded(
              child: ch == null
                  ? const SizedBox.shrink()
                  : _IptvFocusStageInfo(
                      channel: ch,
                      hasLists: _customLists.isNotEmpty,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewStage(IptvChannel? ch, int epoch) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Painted FIRST so the video covers it: the underlay engine's
            // punched hole wipes these pixels once frames arrive, and the
            // Texture engine simply draws over them. No Opacity/fade wrappers
            // here — anything layer-based over the punched hole would break
            // the punch-through (house underlay invariant). The floor's tuning
            // animation stops itself once frames show, so nothing keeps
            // repainting under a playing video.
            ValueListenableBuilder<bool>(
              valueListenable: _previewShowing,
              builder: (context, showing, _) => _IptvStageFloor(
                channel: ch,
                tuning: _channelPreviewEnabled && ch != null && !showing,
              ),
            ),
            // Startup launch owns the screen: the stage's 900ms dwell would
            // otherwise open a SECOND live stream under the launching player.
            if (ch != null && _channelPreviewEnabled && !_startupLaunchActive)
              ValueListenableBuilder<String?>(
                valueListenable: _previewStreamUrl,
                builder: (context, streamUrl, _) {
                  // Null while a Stremio channel resolves (or when every
                  // candidate died) — only the floor shows.
                  if (streamUrl == null) return const SizedBox.shrink();
                  // Ladder generation these callbacks belong to — they fire
                  // post-frame, possibly after focus moved to another channel.
                  final ticket = _previewResolveTicket;
                  return HeroTrailerBackdrop(
                    key: ValueKey('iptv-preview-$epoch'),
                    imageUrl: null,
                    videoUrl: streamUrl,
                    enabled: true,
                    live: true,
                    // The channel's declared UA/Referer — panels that guard
                    // playback with them guard the preview identically.
                    httpHeaders: ch.playbackHeaders,
                    imageBlurSigma: 0,
                    videoBlurSigma: 0,
                    // The dwell: arrowing down the guide never opens a stream
                    // until focus rests. Live streams also open slower than
                    // trailer clips, so a slightly longer debounce than Home's.
                    startDelay: const Duration(milliseconds: 900),
                    ambientVolume: 100,
                    onPlayingChanged: (p) {
                      if (ticket == _previewResolveTicket) {
                        _previewShowing.value = p;
                      }
                      if (p) _markPreviewWinner(ticket);
                    },
                    onPlaybackFailed: () => _onPreviewPlaybackFailed(ticket),
                    // Stremio ladder needs stalls to count as failures, or a
                    // silent-dead candidate would block the walk to the next.
                    firstFrameTimeout:
                        StremioIptvService.isStremioChannelUrl(ch.url)
                        ? const Duration(seconds: 12)
                        : null,
                  );
                },
              ),
            // Status chip — top-left, direct paint over the stage.
            Positioned(
              left: 10,
              top: 10,
              child: ValueListenableBuilder<bool>(
                valueListenable: _previewShowing,
                builder: (context, showing, _) => _IptvStageChip(
                  channel: ch,
                  showing: showing,
                  previewEnabled: _channelPreviewEnabled,
                ),
              ),
            ),
            // NO styled chrome over the video — final, device-verified rule.
            // Wrapping the preview froze the underlay; even full-rect
            // SIBLING overlays (Positioned.fill brackets/frame painted above
            // the hole, the status-chip pattern) made it flicker on real TV
            // hardware. The styles decorate the panel AROUND this stack only;
            // the shipped chip/identity are the sole overlays. Do not add
            // paint over the preview rect without an on-device test.
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    bool tvPane = false,
    bool touchSelector = false,
    bool cockpit = false,
  }) {
    // Empty state when no playlists
    if (_playlists.isEmpty) {
      return IptvEmptyState(
        hasPlaylists: false,
        onAddPlaylist: _navigateToSettings,
      );
    }

    // Empty state when no playlist selected
    if (_selectedPlaylist == null) {
      return const IptvEmptyState(hasPlaylists: true);
    }

    // Loading
    if (_isLoading) {
      return _buildLoadingState(context);
    }

    // Error
    if (_errorMessage != null && _allChannels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load playlist',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No channels matched. While a progressive load is still streaming in,
    // a definitive "No channels found" would be a lie — matches may simply
    // not have arrived yet, so say that instead.
    if (_filteredChannels.isEmpty) {
      if (_isLoadingMore) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 16),
              Text(
                widget.searchQuery.isNotEmpty
                    ? 'No matches yet — channels are still loading'
                    : _selectedCategory != null
                    ? 'Nothing in this category yet — still loading'
                    : 'Loading channels…',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${_allChannels.length} channel'
                '${_allChannels.length == 1 ? '' : 's'} loaded so far',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      final isFavoritesView = _selectedPlaylist?.isFavorites ?? false;
      final isListView = _selectedPlaylist?.isCustomList ?? false;
      final isContinueView = _selectedPlaylist?.isContinueWatching ?? false;
      final unfiltered =
          widget.searchQuery.isEmpty && _selectedCategory == null;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !unfiltered
                  ? Icons.live_tv_outlined
                  : isContinueView
                  ? Icons.history_rounded
                  : isFavoritesView
                  ? Icons.star_border
                  : isListView
                  ? Icons.playlist_add_rounded
                  : Icons.live_tv_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              !unfiltered
                  ? 'No channels found'
                  : isContinueView
                  ? 'Nothing in progress'
                  : isFavoritesView
                  ? 'No favorites yet'
                  : isListView
                  ? 'Nothing in ${_selectedPlaylist?.name ?? 'this list'} yet'
                  : 'No channels found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : _selectedCategory != null
                  ? 'Try a different category'
                  : isContinueView
                  ? 'Movies you start but do not finish show up here'
                  : isFavoritesView || isListView
                  ? (widget.isTelevision
                        ? 'Hold OK on any channel to add it here'
                        : 'Long-press any channel to add it here')
                  : 'This playlist appears to be empty',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Results — a compact, guide-style list. Multi-column on wide screens so
    // the horizontal space isn't wasted; a single column on phones and in the
    // TV two-pane's guide column (which is roughly phone-width anyway).
    final w = MediaQuery.of(context).size.width;
    final narrowRows = !widget.isTelevision && w < 600;
    final hPadding = tvPane ? 10.0 : (w >= 900 ? 28.0 : 12.0);
    final maxCrossAxisExtent = tvPane ? 720.0 : 440.0;
    const crossAxisSpacing = 12.0;
    final padRight = tvPane ? 24.0 : hPadding;

    // Resolved ONCE per build, not per row: the getter probes channels with
    // IptvEpgService.isEpgCapable, which parses a URL per probe (one for a
    // capable list, up to ten when the leading channels aren't) — reading it
    // from the item builder repeated that for every row the grid materialized.
    // It is constant for the whole list anyway, and the grid gives every tile
    // ONE height, so hoisting also makes the delegate and the rows agree by
    // construction instead of by coincidence.
    final epgRows = _epgRowsActive;
    final rowExtent = _showsPosterRows
        ? kIptvPosterRowExtent
        : epgRows
        ? (cockpit ? kIptvEpgRowTallExtent : kIptvEpgRowExtent)
        : cockpit
        ? kIptvRowTallExtent
        : narrowRows
        ? kIptvNarrowRowExtent
        : kIptvRowExtent;

    final Widget channelBrowser = touchSelector
        ? _buildTabletCenteredSelector(
            _filteredChannels,
            rowExtent: rowExtent,
            epgRows: epgRows,
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              // The delegate's own column math, replicated so rows can know
              // whether they sit on the grid's right edge (those get the
              // RIGHT-opens-schedule key; the rest keep plain traversal).
              final crossExtent = (constraints.maxWidth - hPadding - padRight)
                  .clamp(1.0, double.infinity);
              final columns =
                  (crossExtent / (maxCrossAxisExtent + crossAxisSpacing))
                      .ceil()
                      .clamp(1, 100);
              // Captured together so itemCount and the list the delegate indexes
              // can never disagree: a RangeError in itemBuilder is exactly what a
              // count-from-one-variable / rows-from-another split produces the
              // day someone assigns _filteredChannels outside setState.
              final channelList = _filteredChannels;
              final itemCount = channelList.length;
              // Published for the startup-channel launch, which must scroll to
              // a row that has never been built (so it has no focus node and
              // no ensureVisible of its own). These are LayoutBuilder locals —
              // unreachable from outside without stashing them.
              _gridColumns = columns;
              _gridRowExtent = rowExtent;

              // NOT wrapped in TvFocusScrollWrapper: this subtree has no ancestor
              // Scrollable, so the wrapper's ensureVisible walk was a silent no-op
              // — and each row already runs its own ensureVisible on focus, so the
              // wrapper only ever risked a second, competing scroll animation.
              return FocusTraversalGroup(
                child: GridView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(hPadding, 8, padRight, 24),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxCrossAxisExtent,
                    mainAxisExtent: rowExtent,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: crossAxisSpacing,
                  ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    final channel = channelList[index];
                    // Right edge = last column, or the final item of a partial
                    // last row (nothing exists to its right either way).
                    final rightEdge =
                        index % columns == columns - 1 ||
                        index == itemCount - 1;
                    return IptvChannelRow(
                      // ObjectKey, not ValueKey(url): duplicate URLs are legal
                      // in a playlist and must keep independent row state.
                      key: ObjectKey(channel),
                      channel: channel,
                      isTelevision: widget.isTelevision,
                      onTap: () => _playChannel(channel),
                      focusNode: _focusNodeFor(channel),
                      isFavorited: _favoriteUrls.contains(channel.url),
                      inAnyList: _membership[channel.url]?.isNotEmpty ?? false,
                      onFavoriteToggle: channel.contentType == 'series'
                          ? null
                          : (isFavorited) =>
                                _toggleFavorite(channel, isFavorited),
                      onOpenListPicker: channel.contentType == 'series'
                          ? null
                          : () => _openListPicker(channel),
                      hasCustomLists: _customLists.isNotEmpty,
                      onFocused: tvPane
                          ? () => _onChannelFocused(channel)
                          : null,
                      onPointerRest: tvPane
                          ? () => _onChannelFocused(channel, fromPointer: true)
                          : null,
                      onDetached: () => _onRowDetached(channel),
                      onSchedule: _scheduleActionFor(
                        channel,
                        inPlace: widget.isTelevision && tvPane,
                      ),
                      // Cockpit: RIGHT walks into the stage's actions by
                      // geometry instead; the full schedule pane stays
                      // reachable from the stage's Guide button.
                      scheduleOnRightKey: rightEdge && !cockpit,
                      progress: _progressByUrl[channel.url],
                      poster: _showsPosterRows,
                      epg: epgRows,
                      twoLineName: cockpit && !_showsPosterRows,
                      // Styled looks exist only in the cockpit, and only for
                      // live/EPG rows — VOD/series posters keep the shipped
                      // layout in every style (plan: posters are untouched).
                      style: cockpit && !_showsPosterRows
                          ? _iptvStyle
                          : IptvStyle.command,
                      tileWidth:
                          (crossExtent - (columns - 1) * crossAxisSpacing) /
                          columns,
                    );
                  },
                ),
              );
            },
          );
    // Streamed load still running: a quiet, non-focusable line keeps the
    // visible (possibly filtered) rows honest about being a partial list.
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget buildProgressiveStatus() => Padding(
      padding: EdgeInsets.fromLTRB(hPadding + 4, 6, hPadding, 0),
      child: Row(
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: subtle.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.searchQuery.isNotEmpty
                  ? 'Still loading (${_allChannels.length} so far) — '
                        'search results may be incomplete'
                  : 'Still loading channels — '
                        '${_allChannels.length} so far',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subtle,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (touchSelector) {
      // Keep this parent chain stable when the final progressive result hides
      // the status line. Moving the selector from inside a Column to the root
      // would dispose it even with a stable key and reset its scroll state.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _isLoadingMore ? buildProgressiveStatus() : const SizedBox.shrink(),
          Expanded(
            key: const ValueKey('iptv-tablet-selector-slot'),
            child: channelBrowser,
          ),
        ],
      );
    }

    if (!_isLoadingMore) return channelBrowser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildProgressiveStatus(),
        Expanded(child: channelBrowser),
      ],
    );
  }

  Widget _buildTabletCenteredSelector(
    List<IptvChannel> channels, {
    required double rowExtent,
    required bool epgRows,
  }) {
    final selection = _reconcileTabletSelection(channels);
    return IptvCenteredSelector(
      key: const ValueKey('iptv-tablet-centered-selector'),
      itemCount: channels.length,
      itemExtent: rowExtent,
      initialIndex: selection.index,
      selectionToken: selection.identity,
      onSelected: (index) {
        if (!mounted || index < 0 || index >= channels.length) return;
        _selectTabletChannel(index, channels[index]);
      },
      itemBuilder: (context, index, selected, centerItem) {
        final channel = channels[index];
        final openSchedule = _scheduleActionFor(channel, inPlace: true);
        return IptvChannelRow(
          key: ObjectKey(channel),
          channel: channel,
          isPreviewSelected: selected,
          onTap: centerItem,
          isFavorited: _favoriteUrls.contains(channel.url),
          inAnyList: _membership[channel.url]?.isNotEmpty ?? false,
          onFavoriteToggle: channel.contentType == 'series'
              ? null
              : (isFavorited) => _toggleFavorite(channel, isFavorited),
          onOpenListPicker: channel.contentType == 'series'
              ? null
              : () => _openListPicker(channel),
          hasCustomLists: _customLists.isNotEmpty,
          onSchedule: openSchedule == null
              ? null
              : () {
                  centerItem();
                  _selectTabletChannel(index, channel);
                  openSchedule();
                },
          progress: _progressByUrl[channel.url],
          poster: _showsPosterRows,
          epg: epgRows,
        );
      },
    );
  }

  _TabletChannelIdentity _tabletIdentityOf(IptvChannel channel) => (
    channelNumber: channel.channelNumber,
    name: channel.name,
    url: channel.url,
    group: channel.group,
    contentType: channel.contentType,
  );

  ({int index, _TabletChannelIdentity identity}) _reconcileTabletSelection(
    List<IptvChannel> channels,
  ) {
    assert(channels.isNotEmpty);
    final wanted = _tabletSelectedIdentity;
    if (wanted != null) {
      final previous = _tabletSelectedIndex;
      if (previous >= 0 &&
          previous < channels.length &&
          _tabletIdentityOf(channels[previous]) == wanted) {
        return (index: previous, identity: wanted);
      }

      // Materialized lists (including progressive Stremio snapshots) can
      // cheaply find a row that moved after filtering. Never walk a paged DB
      // facade here: that could fault tens of thousands of rows during build.
      if (channels is! DbChannelList) {
        for (var index = 0; index < channels.length; index++) {
          if (_tabletIdentityOf(channels[index]) == wanted) {
            _tabletSelectedIndex = index;
            return (index: index, identity: wanted);
          }
        }
      } else {
        final shown = _previewShown.value;
        final index = shown == null ? null : channels.indexOfInstance(shown);
        if (index != null && _tabletIdentityOf(channels[index]) == wanted) {
          _tabletSelectedIndex = index;
          return (index: index, identity: wanted);
        }
      }
    }

    final identity = _tabletIdentityOf(channels.first);
    _tabletSelectedIndex = 0;
    _tabletSelectedIdentity = identity;
    return (index: 0, identity: identity);
  }

  void _selectTabletChannel(int index, IptvChannel channel) {
    _tabletSelectedIndex = index;
    _tabletSelectedIdentity = _tabletIdentityOf(channel);
    _onChannelFocused(channel);
  }
}

// ── TV preview rail widgets ─────────────────────────────────────────────────

/// The stage's resting surface: a brand-tinted glass slab with the channel's
/// logo (or a placeholder mark). Sits UNDER the embedded player — the video
/// covers/wipes it once frames arrive, so it needs no fade of its own.
///
/// While [tuning] (a channel is focused but no frames yet) it runs a light
/// broadcast ambience: signal rings rippling out from the logo, a breathing
/// brand glow, a diagonal sheen sweep and a gentle logo breathe. Everything is
/// direct canvas paint / matrix transform — this widget shares a layer with
/// the underlay's punched hole, so Opacity/saveLayer wrappers stay banned.
/// The controller stops the moment frames arrive (or focus clears), so
/// nothing keeps repainting under a playing video.
class _IptvStageFloor extends StatefulWidget {
  final IptvChannel? channel;
  final bool tuning;
  const _IptvStageFloor({required this.channel, required this.tuning});

  @override
  State<_IptvStageFloor> createState() => _IptvStageFloorState();
}

class _IptvStageFloorState extends State<_IptvStageFloor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_IptvStageFloor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final animate = widget.tuning && widget.channel != null;
    if (animate) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating || _ctrl.value != 0) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final ch = widget.channel;
    final brand = ch != null ? brandAccentFor(ch.name) : app.seeAll.accent;
    final logo = ch?.logoUrl;
    final animate = widget.tuning && ch != null;

    Widget mark = ch == null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.live_tv_rounded,
                size: 42,
                color: app.core.tx.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 10),
              Text(
                'Browse channels to preview',
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0.45),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        : (logo != null && logo.isNotEmpty)
        ? Padding(
            padding: const EdgeInsets.all(38),
            child: CachedNetworkImage(
              imageUrl: logo,
              cacheManager: DebrifyImageCache.iptvLogos,
              fit: BoxFit.contain,
              // Cap the decode — see the row logo chip's rationale.
              memCacheHeight: 240,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (_, __, ___) => Icon(
                Icons.live_tv_rounded,
                size: 42,
                color: brand.withValues(alpha: 0.75),
              ),
            ),
          )
        : Icon(
            Icons.live_tv_rounded,
            size: 42,
            color: brand.withValues(alpha: 0.75),
          );

    if (animate) {
      // Transform is a canvas matrix, not a compositing layer — hole-safe.
      mark = AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.015 * math.sin(2 * math.pi * _ctrl.value),
          child: child,
        ),
        child: mark,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              brand.withValues(alpha: 0.18),
              const Color(0xFF171430),
            ),
            const Color(0xFF0F0D20),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (animate)
            CustomPaint(
              painter: _TuningWavesPainter(brand: brand, t: _ctrl),
            ),
          Center(child: mark),
        ],
      ),
    );
  }
}

/// The tuning ambience: staggered signal rings expanding from the stage
/// centre, a soft breathing glow behind the logo, and a slow diagonal sheen
/// sweeping the slab. Plain canvas paints only — this layer is the one the
/// video punch-through wipes, so no saveLayer/Opacity is allowed here.
class _TuningWavesPainter extends CustomPainter {
  final Color brand;
  final Animation<double> t;
  _TuningWavesPainter({required this.brand, required this.t})
    : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final center = size.center(Offset.zero);

    // Breathing glow behind the logo.
    final glowAlpha = 0.10 + 0.05 * math.sin(2 * math.pi * v);
    final glowRadius = size.shortestSide * 0.42;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(center, glowRadius, [
          brand.withValues(alpha: glowAlpha),
          brand.withValues(alpha: 0),
        ]),
    );

    // Signal rings rippling outward from behind the logo.
    final ringColor = Color.lerp(brand, Colors.white, 0.35)!;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final maxGrow = size.shortestSide * 0.62;
    for (int i = 0; i < 3; i++) {
      final phase = (v + i / 3) % 1.0;
      final eased = Curves.easeOut.transform(phase);
      final fade = (1 - phase) * (1 - phase);
      ring.color = ringColor.withValues(alpha: 0.16 * fade);
      canvas.drawCircle(center, 30 + eased * maxGrow, ring);
    }

    // Diagonal sheen sweeping across the slab once per cycle.
    final sweep = Curves.easeInOut.transform(v);
    final x = size.width * (-0.35 + 1.7 * sweep);
    final band = Paint()
      ..shader = ui.Gradient.linear(
        Offset(x - 70, 0),
        Offset(x + 70, size.height),
        [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Offset.zero & size, band);
  }

  @override
  bool shouldRepaint(_TuningWavesPainter oldDelegate) =>
      oldDelegate.brand != brand;
}

/// Status chip on the stage: LIVE (emerald dot) once the preview has frames,
/// TUNING (tiny animated amber signal bars) while a channel is selected but
/// the stream hasn't opened yet, PREVIEW for on-demand items, or PREVIEW OFF
/// when automatic tuning is disabled. Conditional swaps and direct paint only
/// — no fades over the stage, and only the TUNING state animates so nothing
/// repaints while video is playing.
class _IptvStageChip extends StatefulWidget {
  final IptvChannel? channel;
  final bool showing;
  final bool previewEnabled;
  const _IptvStageChip({
    required this.channel,
    required this.showing,
    required this.previewEnabled,
  });

  @override
  State<_IptvStageChip> createState() => _IptvStageChipState();
}

class _IptvStageChipState extends State<_IptvStageChip>
    with SingleTickerProviderStateMixin {
  static const Color _amber = Color(0xFFFBBF24);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool get _tuning =>
      widget.previewEnabled && widget.channel != null && !widget.showing;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_IptvStageChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_tuning) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final ch = widget.channel;
    if (ch == null) return const SizedBox.shrink();
    final isLive = ch.isLive;
    final label = !widget.previewEnabled
        ? 'PREVIEW OFF'
        : widget.showing
        ? (isLive ? 'LIVE' : 'PREVIEW')
        : 'TUNING';
    final dot = !widget.previewEnabled
        ? app.iptv.inkFaint
        : isLive
        ? app.iptv.liveDot
        : app.seeAll.accent2;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        // Deliberately NOT iptv.chipSurface: this chip floats over LIVE
        // VIDEO, so it must stay black glass and legible over an arbitrary
        // picture rather than follow the page (see the token's doc).
        color: const Color(0xB00B0918),
        borderRadius: app.shape.brPill,
        // `onGlass`, not `core.tx`: the fill above is black on EVERY theme by
        // design, so its ink must be what reads on black — a paper theme's
        // near-black page ink would draw an invisible edge here. Same reason
        // the label below uses it.
        border: Border.all(color: app.onGlass.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 9,
            height: 9,
            child: _tuning
                ? CustomPaint(painter: _TuningBarsPainter(t: _ctrl))
                : Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: app.onGlass,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny equalizer-style signal bars for the TUNING chip — direct paint over
/// the stage (same no-saveLayer rule as everything else on it).
class _TuningBarsPainter extends CustomPainter {
  final Animation<double> t;
  _TuningBarsPainter({required this.t}) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _IptvStageChipState._amber;
    const barW = 2.0;
    const gap = 1.5;
    for (int i = 0; i < 3; i++) {
      final v = 0.5 + 0.5 * math.sin(2 * math.pi * (t.value + i * 0.32));
      final h = 3.0 + (size.height - 3.0) * v;
      final x = i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barW, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TuningBarsPainter oldDelegate) => false;
}

/// TV focus-stage identity and programme overlay. The solid lower stop keeps
/// text legible on bright channels without a blur/filter pass.
class _IptvFocusStageInfo extends StatelessWidget {
  final IptvChannel channel;
  final bool hasLists;

  const _IptvFocusStageInfo({required this.channel, this.hasLists = false});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final brand = brandAccentFor(channel.name);
    final resMatch = _railResExp.firstMatch(channel.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? channel.name
        : channel.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final group = channel.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 250;
        final logoSize = dense ? 32.0 : 44.0;
        return ColoredBox(
          color: app.iptv.stageBg,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              dense ? 18 : 24,
              dense ? 8 : 18,
              dense ? 18 : 24,
              dense ? 7 : 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        borderRadius: app.shape.brImg(8),
                        border: Border.all(color: app.iptv.hairline),
                        color: Color.alphaBlend(
                          brand.withValues(alpha: 0.18),
                          const Color(0xFF171B19),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child:
                            (channel.logoUrl != null &&
                                channel.logoUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: channel.logoUrl!,
                                cacheManager: DebrifyImageCache.iptvLogos,
                                fit: BoxFit.contain,
                                memCacheHeight: 96,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.live_tv_rounded,
                                  size: dense ? 16 : 20,
                                  color: brand.withValues(alpha: 0.85),
                                ),
                              )
                            : Icon(
                                Icons.live_tv_rounded,
                                size: dense ? 16 : 20,
                                color: brand.withValues(alpha: 0.85),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.channelNumber == null
                                ? displayName
                                : 'CH ${channel.channelNumber}  $displayName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: app.core.tx,
                              fontSize: dense ? 15 : 19,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          if (subParts.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subParts.join('  •  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: app.core.tx.withValues(alpha: 0.52),
                                fontSize: dense ? 10.5 : 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: dense ? 5 : 13),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: app.core.tx.withValues(alpha: 0.13),
                ),
                SizedBox(height: dense ? 5 : 12),
                IptvRailEpgCard(
                  channel: channel,
                  stageOverlay: true,
                  dense: dense,
                ),
                const Spacer(),
                _IptvRailHints(
                  showGuide: IptvEpgService.isEpgCapable(channel),
                  hasLists: hasLists,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Identity block under the stage: logo chip, channel name (resolution pulled
/// out into the sub-line), group. Empty when nothing is focused yet.
class _IptvRailInfo extends StatelessWidget {
  final IptvChannel? channel;
  const _IptvRailInfo({required this.channel});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final ch = channel;
    if (ch == null) return const SizedBox.shrink();
    final brand = brandAccentFor(ch.name);

    final resMatch = _railResExp.firstMatch(ch.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final cleanName = resMatch == null
        ? ch.name
        : ch.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final displayName = ch.channelNumber == null
        ? cleanName
        : 'CH ${ch.channelNumber}  $cleanName';
    final group = ch.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: app.shape.br(11),
                border: Border.all(color: app.core.tx.withValues(alpha: 0.06)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      brand.withValues(alpha: 0.16),
                      app.iptv.logoPlate,
                    ),
                    // The plate's lower stop — value-equal to iptv.modalBg,
                    // but that role is a dialog ground and must not repaint
                    // logos when a theme moves its sheets.
                    const Color(0xFF14141D),
                  ],
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: (ch.logoUrl != null && ch.logoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: ch.logoUrl!,
                        cacheManager: DebrifyImageCache.iptvLogos,
                        fit: BoxFit.contain,
                        // Cap the decode — see the row logo chip's rationale.
                        memCacheHeight: 96,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.live_tv_rounded,
                          size: 20,
                          color: brand.withValues(alpha: 0.85),
                        ),
                      )
                    : Icon(
                        Icons.live_tv_rounded,
                        size: 20,
                        color: brand.withValues(alpha: 0.85),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (subParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subParts.join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx.withValues(alpha: 0.52),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // What's on: now/next for the focused channel. Renders nothing for
        // channels without guide data, so the rail is unchanged for those.
        const SizedBox(height: 14),
        Flexible(child: IptvRailEpgCard(channel: ch)),
      ],
    );
  }
}

/// Bottom-of-rail key hints: OK to watch fullscreen, hold OK to favourite (or
/// to pick a list, once the user has any), and — when the focused channel has
/// guide data — RIGHT for its schedule.
class _IptvRailHints extends StatelessWidget {
  final bool showGuide;
  final bool hasLists;
  const _IptvRailHints({this.showGuide = false, this.hasLists = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _KeyCap('OK'),
        const SizedBox(width: 6),
        _hint(context, 'Watch'),
        const SizedBox(width: 16),
        const _KeyCap('HOLD OK'),
        const SizedBox(width: 6),
        _hint(context, hasLists ? 'Add to list' : 'Favorite'),
        if (showGuide) ...[
          const SizedBox(width: 16),
          const _KeyCap('▶'),
          const SizedBox(width: 6),
          _hint(context, 'Guide'),
        ],
      ],
    );
  }

  Widget _hint(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.45),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: app.shape.br(5),
        border: Border.all(color: app.core.tx.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: app.home.focus.withValues(alpha: 0.95),
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
