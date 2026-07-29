import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show compute, kIsWeb, listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';
import '../../utils/tv_keys.dart';
import '../browse/brand_accent.dart';
import '../browse/browse_results_focus.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_catalog_cache.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/stremio_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../screens/iptv/iptv_global_search_page.dart';
import '../../screens/iptv/xtream_series_detail.dart';
import '../../screens/settings/iptv_settings_page.dart';
import '../hero_trailer_backdrop.dart';
import '../home/home_theme.dart';
import '../see_all/see_all_filter_bar.dart';
import '../see_all/see_all_theme.dart';
import '../see_all/stremio_dropdown.dart';
import '../../services/iptv_epg_service.dart';
import 'db_channel_list.dart';
import 'iptv_filters.dart';
import 'iptv_channel_row.dart';
import 'iptv_empty_state.dart';
import 'iptv_epg_panel.dart';
import 'iptv_source_rail.dart';

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)"
/// — pulled out of the rail's big title into its sub-line (the channel rows do
/// the same split for themselves).
final RegExp _railResExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

/// State of the bottom-right background-refresh chip.
enum _CatalogChipState { hidden, updating, success, failure }

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

  // Playlists and settings
  List<IptvPlaylist> _playlists = [];
  IptvPlaylist? _selectedPlaylist;
  bool _settingsLoaded = false;

  /// The redesign flag ([StorageService.getIptvRedesignEnabled]): EPG rows,
  /// the global-search entry points, the TV source rail, category counts.
  /// Off = the exact pre-redesign page.
  bool _redesignEnabled = false;

  /// Desktop gets the full two-pane experience too (redesign): source rail,
  /// embedded live preview, quiet filters — hover previews, click plays.
  /// Phones/tablets deliberately keep the classic list: an autoplaying inline
  /// stream on mobile costs data/battery and has no hover to drive it.
  static final bool _isDesktop =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  // Current playlist data
  List<IptvChannel> _allChannels = [];
  List<IptvChannel> _filteredChannels = [];
  List<String> _categories = [];
  String? _selectedCategory;

  /// DB-catalog mode ([StorageService.getIptvDbCatalogEnabled]): cacheable
  /// catalogs (Xtream logins, M3U URLs) live as rows in iptv_catalog.db and
  /// [_allChannels]/[_filteredChannels] become [DbChannelList] facades that
  /// page from SQL — RAM stops scaling with playlist size. Virtual views
  /// (Favorites, Continue, Stremio, local files) stay materialized.
  bool _dbCatalogEnabled = false;

  /// Non-null exactly while the CURRENT view is DB-backed.
  CatalogSnapshot? _dbSnapshot;

  /// Per-group counts for the DB-backed catalog (replaces the
  /// [_categoryCounts] scan, which would page the whole facade).
  Map<String, int> _dbGroupCounts = const {};

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

  /// Line shown under the loading spinner for named one-time work (the
  /// legacy-snapshot → DB upgrade).
  String? _loadingStatus;

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
  Timer? _chipShowTimer;
  Timer? _chipHideTimer;

  // Progressive (Stremio-addon) loads: [_loadTicket] orphans a superseded
  // load's batches AND its final result, and doubles as the cancel signal
  // that stops its catalog walk; [_isLoadingMore] is true from the first
  // streamed batch until the walk completes — every "N channels" readout and
  // empty state must stay honest while it's set (the list is still growing,
  // so a search can have matches on the way).
  int _loadTicket = 0;
  bool _isLoadingMore = false;
  DateTime? _lastProgressiveApply;

  // Favorites
  Set<String> _favoriteUrls = {};

  /// Original playlistId each favorite was starred from (url → id). Toggling
  /// a star inside the virtual Favorites view must keep the channel tied to
  /// its real playlist, so deleting that playlist still sweeps the favorite.
  Map<String, String> _favoritePlaylistIds = {};

  /// Virtual "Favorites" playlist — never persisted; pinned to the top of the
  /// picker and backed by the starred-channel store instead of a fetch.
  static final IptvPlaylist _favoritesPlaylist = IptvPlaylist(
    id: 'iptv-favorites',
    name: 'Favorites',
    url: 'favorites://',
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
  final FocusNode _playlistFilterFocusNode = FocusNode(debugLabel: 'iptv-playlist-filter');
  final FocusNode _categoryFilterFocusNode = FocusNode(debugLabel: 'iptv-category-filter');
  final FocusNode _contentTypeFocusNode = FocusNode(debugLabel: 'iptv-content-type-filter');
  final FocusNode _globalSearchFocusNode =
      FocusNode(debugLabel: 'iptv-global-search-chip');

  /// Per-category channel counts for the current catalog (redesign labels).
  /// Memoized against the list instance AND its length — progressive Stremio
  /// loads append to one list, so identity alone would freeze the counts at
  /// the first batch.
  List<IptvChannel>? _categoryCountsSource;
  int _categoryCountsLength = -1;
  Map<String, int> _categoryCountsCache = const {};
  Map<String, int> get _categoryCounts {
    // DB mode: counts come from one GROUP BY at present time — scanning the
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
    if (!_redesignEnabled || _showsPosterRows) return false;
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
  final ValueNotifier<IptvChannel?> _previewShown =
      ValueNotifier<IptvChannel?>(null);
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

  FocusNode _focusNodeFor(IptvChannel channel) => _cardFocusNodes.putIfAbsent(
    channel,
    () => FocusNode(debugLabel: 'iptv-card-${channel.name}-${channel.url}'),
  );

  String _lastSearchQuery = '';

  /// Channel whose programme schedule is open. On TV it swaps the two-pane
  /// layout's right side (guide list) for the schedule while the preview
  /// keeps playing; phone/desktop use a bottom sheet and never set this.
  IptvChannel? _scheduleChannel;

  /// Whether the last build used the TV two-pane layout. The in-place
  /// schedule pane only exists there — on the classic fallback (narrow TV
  /// canvas) RIGHT must open the bottom sheet instead, or it sets state
  /// nothing renders (a silent dead key).
  bool _tvTwoPaneActive = false;

  /// The schedule action for a row, or null when the channel can't have
  /// guide data (no RIGHT-key handling, no calendar icon).
  VoidCallback? _scheduleActionFor(IptvChannel channel) {
    if (!IptvEpgService.isEpgCapable(channel)) return null;
    if (widget.isTelevision && _tvTwoPaneActive) {
      return () => _openSchedulePane(channel);
    }
    return () => showIptvScheduleSheet(
          context,
          channel,
          isTelevision: widget.isTelevision,
          onPlayProgramme: (programme) => _playCatchup(channel, programme),
        );
  }

  void _openSchedulePane(IptvChannel channel) {
    setState(() => _scheduleChannel = channel);
  }

  void _closeSchedulePane() {
    final channel = _scheduleChannel;
    if (channel == null) return;
    setState(() => _scheduleChannel = null);
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
    _loadSettings();
    _loadFavorites();
  }

  void _onStremioAddonsChanged() {
    if (mounted) _loadSettings();
  }

  Future<void> _loadFavorites() async {
    final favorites = await StorageService.getIptvFavoriteChannels();
    if (mounted) {
      setState(() {
        _favoriteUrls = favorites.keys.toSet();
        _favoritePlaylistIds = {
          for (final entry in favorites.entries)
            entry.key: (entry.value['playlistId'] as String?) ?? '',
        };
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
    if (playlist?.isFavorites ?? false) return _favoritePlaylistIds[channel.url];
    if (playlist?.isContinueWatching ?? false) {
      return _continuePlaylistIds[channel.url];
    }
    return playlist?.id;
  }

  Future<void> _toggleFavorite(IptvChannel channel, bool isFavorited) async {
    await StorageService.setIptvChannelFavorited(
      channel.url,
      isFavorited,
      channelName: channel.name,
      logoUrl: channel.logoUrl,
      group: channel.group,
      playlistId: _originPlaylistIdFor(channel),
      // Favorites are replayed from stored metadata, never re-parsed from the
      // playlist — so the channel's own headers have to travel with it.
      httpHeaders: channel.httpHeaders,
    );
    if (mounted) {
      setState(() {
        if (isFavorited) {
          _favoriteUrls.add(channel.url);
        } else {
          _favoriteUrls.remove(channel.url);
        }
      });
    }
  }

  Future<void> _loadSettings({bool forceReload = false}) async {
    final redesignEnabled = await StorageService.getIptvRedesignEnabled();
    _dbCatalogEnabled = await StorageService.getIptvDbCatalogEnabled();
    var playlists = await StorageService.getIptvPlaylists();
    var defaultPlaylistId = await StorageService.getIptvDefaultPlaylist();

    // Add default playlist on first run (if not already initialized)
    final defaultsInitialized = await StorageService.getIptvDefaultsInitialized();
    if (!defaultsInitialized) {
      // Add the default iptv-org playlist
      final defaultPlaylist = IptvPlaylist(
        id: 'iptv-org-default',
        name: 'iptv-org',
        url: 'https://iptv-org.github.io/iptv/index.m3u',
        addedAt: DateTime.now(),
      );
      playlists = [defaultPlaylist, ...playlists];
      defaultPlaylistId = defaultPlaylist.id;

      // Save the default playlist and mark as initialized
      await StorageService.setIptvPlaylists(playlists);
      await StorageService.setIptvDefaultPlaylist(defaultPlaylistId);
      await StorageService.setIptvDefaultsInitialized(true);
    }

    // Installed Stremio addons with live-TV catalogs appear as (non-stored)
    // virtual playlists after the user's own entries.
    final virtualPlaylists =
        await StremioIptvService.instance.getVirtualPlaylists();
    playlists = [...playlists, ...virtualPlaylists];

    // The virtual Favorites playlist leads the picker. Hidden only when there
    // is nothing at all (no playlists AND no favorites), so the add-a-playlist
    // empty state can still do its job.
    final hasFavorites =
        (await StorageService.getIptvFavoriteChannelUrls()).isNotEmpty;
    // "Continue watching" earns its slot only while something is actually
    // half-watched — an empty shelf in the picker is just noise.
    final hasContinue =
        (await StorageService.getIptvContinueWatching()).isNotEmpty;
    if (hasFavorites || playlists.isNotEmpty) {
      playlists = [
        _favoritesPlaylist,
        if (hasContinue) _continuePlaylist,
        ...playlists,
      ];
    }

    if (!mounted) return;

    // Determine the new selected playlist. With at least one starred channel,
    // Favorites is the landing selection; otherwise fall back to the stored
    // default (never landing on an empty Favorites view).
    IptvPlaylist? newSelectedPlaylist;
    IptvPlaylist? firstRealPlaylist;
    for (final p in playlists) {
      // Neither virtual shelf is a "real" playlist to fall back to — both can
      // be empty or vanish entirely between visits.
      if (!p.isFavorites && !p.isContinueWatching) {
        firstRealPlaylist = p;
        break;
      }
    }
    if (hasFavorites) {
      newSelectedPlaylist = _favoritesPlaylist;
    } else if (defaultPlaylistId != null && playlists.isNotEmpty) {
      newSelectedPlaylist = playlists.firstWhere(
        (p) => p.id == defaultPlaylistId,
        orElse: () => firstRealPlaylist ?? playlists.first,
      );
    } else if (playlists.isNotEmpty) {
      newSelectedPlaylist = firstRealPlaylist ?? playlists.first;
    }

    // Check if playlist changed
    final playlistChanged = _selectedPlaylist?.id != newSelectedPlaylist?.id;

    setState(() {
      _playlists = playlists;
      _settingsLoaded = true;
      _redesignEnabled = redesignEnabled;
      _selectedPlaylist = newSelectedPlaylist;
    });

    // Only reload playlist if it changed or forced, or if we have no channels loaded
    if (_selectedPlaylist != null && (forceReload || playlistChanged || _allChannels.isEmpty)) {
      _loadPlaylist(_selectedPlaylist!);
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
    if (widget.isTelevision) {
      WidgetsBinding.instance.removeObserver(this);
      MainPageBridge.removeTvSidebarFocusListener(_onTvSidebarFocusChanged);
    }
    StremioService.instance
        .removeAddonsChangedListener(_onStremioAddonsChanged);
    _searchDebounce?.cancel();
    _contentTypeDebounce?.cancel();
    _chipShowTimer?.cancel();
    _chipHideTimer?.cancel();
    _scrollController.dispose();
    _playlistFilterFocusNode.dispose();
    _categoryFilterFocusNode.dispose();
    _contentTypeFocusNode.dispose();
    _globalSearchFocusNode.dispose();
    _previewShown.dispose();
    _previewShowing.dispose();
    _previewEpoch.dispose();
    _previewStreamUrl.dispose();
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPlaylist(IptvPlaylist playlist) async {
    final ticket = ++_loadTicket;
    _lastProgressiveApply = null;
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
      _chipState = _CatalogChipState.hidden;
      _dbSnapshot = null;
      _dbGroupCounts = const {};
      _loadingStatus = null;
      // The outgoing catalog's instances are no use to the incoming one.
      _dbInstanceCache.clear();
      _dbInstanceCacheKey = null;
      // Positions belong to the outgoing playlist's URLs.
      _progressByUrl = {};
      // An open schedule belongs to the outgoing playlist too.
      _scheduleChannel = null;
    });

    // Dispose old focus nodes
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    _cardFocusNodes.clear();
    // The stage's channel belongs to the outgoing playlist.
    _clearPreview();

    // Serve-stale-while-revalidate: network-backed catalogs (Xtream logins,
    // M3U URLs) render their last-known disk snapshot instantly — no spinner,
    // works offline — then refresh in the background. The reconcile in
    // _revalidateCatalog keeps DPAD focus and scroll untouched. First-ever
    // loads (no snapshot yet) fall through to the blocking path below.
    final contentType = _selectedContentType;
    final cacheKey = IptvCatalogCache.keyForPlaylist(playlist, contentType);

    // ── DB-catalog path ────────────────────────────────────────────────────
    // Cacheable catalogs live in iptv_catalog.db: present the stored rows
    // (paged, constant memory), revalidate in the background when stale.
    // First open after the upgrade runs the one-time legacy-snapshot import,
    // deliberately blocking THIS page (never app launch) behind a named
    // spinner, then deletes the legacy file — crash-safe, since the file is
    // only removed after the ingest committed.
    if (_dbCatalogEnabled && cacheKey != null) {
      await IptvCatalogDb.open();
      if (!mounted || ticket != _loadTicket) return;
      var snap = IptvCatalogDb.snapshot(cacheKey);
      if (snap == null) {
        final legacy = await IptvCatalogCache.instance.read(cacheKey);
        if (!mounted || ticket != _loadTicket) return;
        if (legacy != null && legacy.channels.isNotEmpty) {
          setState(() => _loadingStatus = 'Upgrading your library…');
          try {
            await compute(
              ingestLegacySnapshotJob,
              LegacySnapshotIngestJob(
                dbPath: IptvCatalogDb.path,
                catalogKey: cacheKey,
                channels: legacy.channels,
                categories: legacy.categories,
                epgUrl: legacy.epgUrl,
              ),
            );
            await IptvCatalogCache.instance.remove(cacheKey);
          } catch (e) {
            // The legacy snapshot survives an import failure; next open
            // simply retries. Fall through to a plain network load.
            debugPrint('IptvResultsView: legacy import failed: $e');
          }
          if (!mounted || ticket != _loadTicket) return;
          setState(() => _loadingStatus = null);
          snap = IptvCatalogDb.snapshot(cacheKey);
        }
      }
      if (snap != null && snap.channelCount > 0) {
        await _presentDbCatalog(playlist, ticket, snap);
        if (!mounted || ticket != _loadTicket) return;
        final age = DateTime.now().millisecondsSinceEpoch - snap.ingestedAt;
        if (age > _dbCatalogTtl.inMilliseconds) {
          unawaited(
            _revalidateDbCatalog(playlist, contentType, cacheKey, ticket),
          );
        }
        return;
      }
      // Never ingested (fresh install / brand-new playlist): fall through to
      // the network fetch below — the parse worker ingests it and hands back
      // a receipt, which _presentCatalog routes to the DB path.
    }

    if (!_dbCatalogEnabled && cacheKey != null) {
      // Warm path first: the services' in-memory cache (30-min TTL) beats
      // the disk snapshot — same-session tab/playlist switches stay instant
      // with zero disk IO, exactly as before disk caching existed. That data
      // was favorites-reconciled and snapshot-written when first fetched, so
      // neither needs redoing and a revalidate would no-op against it.
      final memory = _memoryCachedCatalog(playlist, contentType);
      if (memory != null) {
        await _presentCatalog(playlist, ticket, memory,
            migrateFavorites: false);
        return;
      }
      final snapshot = await IptvCatalogCache.instance.read(cacheKey);
      if (!mounted || ticket != _loadTicket) return;
      if (snapshot != null && snapshot.channels.isNotEmpty) {
        // migrateFavorites false: snapshot URLs can be OLDER than the
        // favorites store's (migrating here would walk favorites backward);
        // the revalidate migrates forward against fresh URLs instead.
        await _presentCatalog(
          playlist,
          ticket,
          IptvParseResult(
            channels: snapshot.channels,
            categories: snapshot.categories,
            epgUrl: snapshot.epgUrl,
          ),
          migrateFavorites: false,
        );
        // _presentCatalog can bail mid-way when superseded — never spawn a
        // revalidate for a load that's no longer current (its first act
        // would cancel the CURRENT load's chip timer, and it would burn a
        // full catalog fetch whose result gets dropped).
        if (!mounted || ticket != _loadTicket) return;
        unawaited(_revalidateCatalog(playlist, contentType, cacheKey, ticket));
        return;
      }
    }

    // Determine source: favorites store, Stremio addon, XC API, local file,
    // or URL
    final IptvParseResult result;
    if (playlist.isFavorites) {
      result = await _buildFavoritesResult();
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
      result = await _fetchCatalogFromNetwork(playlist, contentType);
    }

    if (!mounted || ticket != _loadTicket) return;

    if (result.hasError) {
      // The context lifecycle follows leaving the playlist, not load
      // success: a failed switch must still drop the previous playlist's
      // guide index (memory + wrong capability answers for its URLs).
      IptvEpgService.instance.clearM3uEpgContext();
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

    // First successful fetch of a cacheable catalog: seed the disk snapshot
    // so the NEXT visit renders instantly.
    if (cacheKey != null && result.channels.isNotEmpty) {
      unawaited(
        IptvCatalogCache.instance.write(
          cacheKey,
          channels: result.channels,
          categories: result.categories,
          epgUrl: result.epgUrl,
        ),
      );
    }

    await _presentCatalog(playlist, ticket, result);
  }

  /// Bind a loaded catalog to the view: favorites migration, list swap,
  /// progress bars, warning surfacing, filters, EPG context. Shared by the
  /// network path and the disk-snapshot path of [_loadPlaylist].
  /// [migrateFavorites] is false for snapshot/memory-cache passes — their
  /// URLs are not fresher than the favorites store's, so migrating against
  /// them is at best a no-op and at worst a backward walk.
  Future<void> _presentCatalog(
    IptvPlaylist playlist,
    int ticket,
    IptvParseResult result, {
    bool migrateFavorites = true,
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
    // Migrate favorites saved under older URL formats (e.g. before the
    // Xtream /live/ URL fix) to the freshly fetched URLs, then reload so
    // the stars line up. (The Favorites view's channels ARE the store —
    // nothing to migrate against.)
    if (migrateFavorites &&
        !playlist.isFavorites &&
        !playlist.isContinueWatching) {
      await StorageService.reconcileIptvFavoriteUrls(result.channels);
    }
    await _loadFavorites();
    if (!mounted || ticket != _loadTicket) return;

    // Focus nodes are created lazily per channel (keyed by URL) in the
    // grid's itemBuilder via _focusNodeFor.

    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
      _allChannels = result.channels;
      _categories = result.categories;
    });

    // After the rows exist, not before: _loadProgress setStates too, and
    // running it first would paint one extra frame against an empty list.
    // The bars simply appear a frame later.
    await _loadProgress(ticket, result.channels);
    if (!mounted || ticket != _loadTicket) return;

    // Surface non-fatal degradation (e.g. categories unavailable) so missing
    // groups don't look like deleted channels.
    if (result.warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.warning!)),
      );
    }

    _applyFilters();
    // Kept for settings round-trips: an EPG-URL edit re-runs the guide
    // context against this result without refetching the whole playlist.
    _lastLoadResult = result;
    _updateEpgContext(playlist, result, ticket);
    _consumeContentFocusRequest();
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
      await StorageService.reconcileIptvFavoriteUrlsForCatalog(
        snap.catalogKey,
      );
    }
    await _loadFavorites();
    if (!mounted || ticket != _loadTicket) return;

    final groups = snap.groups();
    // Provider category list when the panel served one (its order is the
    // chips' order today); groups derived from the rows otherwise (M3U).
    final categories = snap.categories.isNotEmpty
        ? snap.categories
        : [
            for (final g in groups)
              if (g.name != null && g.name!.isNotEmpty) g.name!,
          ];
    final counts = <String, int>{
      for (final g in groups)
        if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
    };

    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
      _loadingStatus = null;
      _dbSnapshot = snap;
      _dbGroupCounts = counts;
      _allChannels = _makeDbList(snap);
      _categories = categories;
      if (_selectedCategory != null &&
          !categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
    });

    if (warning != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(warning)),
      );
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
  /// still built); the next full reload sweeps them as always.
  void _retireEvictedInstances(List<IptvChannel> evicted) {
    for (final channel in evicted) {
      final node = _cardFocusNodes[channel];
      if (node == null || node.context != null || node.hasFocus) continue;
      _cardFocusNodes.remove(channel)?.dispose();
    }
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
    _chipShowTimer?.cancel();
    _chipShowTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_revalidateSuperseded(playlist, contentType, ticket)) {
        _showChip(_CatalogChipState.updating, 'Updating list…');
      }
    });

    IptvParseResult result;
    try {
      result = await _fetchCatalogFromNetwork(playlist, contentType);
    } catch (e) {
      result = IptvParseResult(
          channels: const [], categories: const [], error: '$e');
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
      await _presentCatalog(playlist, ticket, result);
      return;
    }

    final old = _dbSnapshot;
    final fresh = IptvCatalogDb.snapshot(cacheKey);
    if (fresh == null) return;

    if (old != null && fresh.contentDigest == old.contentDigest) {
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
        final groups = fresh.groups();
        final categories = fresh.categories.isNotEmpty
            ? fresh.categories
            : [
                for (final g in groups)
                  if (g.name != null && g.name!.isNotEmpty) g.name!,
              ];
        final selectedVanished = _selectedCategory != null &&
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
    await StorageService.reconcileIptvFavoriteUrlsForCatalog(
      fresh.catalogKey,
    );
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

    final added =
        (fresh.channelCount - (old?.channelCount ?? 0)).clamp(0, 1 << 30);

    final groups = fresh.groups();
    final categories = fresh.categories.isNotEmpty
        ? fresh.categories
        : [
            for (final g in groups)
              if (g.name != null && g.name!.isNotEmpty) g.name!,
          ];
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
            final atIndex = _cardFocusNodes[_filteredChannels[idx]];
            if (atIndex?.context != null) target = atIndex;
          }
          if (target == null) {
            for (final node in _cardFocusNodes.values) {
              if (node.context != null) {
                target = node;
                break;
              }
            }
          }
          (target ?? _playlistFilterFocusNode).requestFocus();
        }
      }
      final detached = [
        for (final entry in _cardFocusNodes.entries)
          if (entry.value.context == null && !entry.value.hasFocus) entry.key,
      ];
      for (final channel in detached) {
        _cardFocusNodes.remove(channel)?.dispose();
      }
    });
    WidgetsBinding.instance.scheduleFrame();

    // Guide rebind against the CURRENT stored configuration, mirroring the
    // materialized revalidate. No snapshot write — the DB is the store.
    final storedPlaylists = await StorageService.getIptvPlaylists();
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
        IptvCatalogCache.keyForPlaylist(storedPlaylist, contentType) ==
            cacheKey) {
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
  ) async {
    if (playlist.isXtreamCodes) {
      final xcService = XtreamCodesService.instance;
      if (contentType == 'vod') {
        return xcService.fetchVodStreams(
            playlist.serverUrl!, playlist.username!, playlist.password!);
      }
      if (contentType == 'series') {
        return xcService.fetchSeriesStreams(
            playlist.serverUrl!, playlist.username!, playlist.password!);
      }
      return xcService.fetchLiveStreams(
          playlist.serverUrl!, playlist.username!, playlist.password!);
    }
    return _iptvService.fetchPlaylist(playlist.url);
  }

  /// Fresh in-memory service-cache result for a cacheable source, or null.
  IptvParseResult? _memoryCachedCatalog(
    IptvPlaylist playlist,
    String contentType,
  ) {
    if (playlist.isXtreamCodes) {
      return XtreamCodesService.instance.cachedResult(
        playlist.serverUrl!,
        playlist.username!,
        contentType,
      );
    }
    return IptvService.instance.cachedResult(playlist.url);
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

  /// Background refresh for a catalog served from its disk snapshot. Fetches
  /// the live catalog, reconciles it against what's on screen so every
  /// unchanged row keeps its exact object identity — focus nodes and the
  /// grid's ObjectKeys are identity-bound, so a naive swap would yank DPAD
  /// focus, drop scroll, and rebuild the whole grid — then applies only the
  /// difference. A refresh that changes nothing touches nothing.
  Future<void> _revalidateCatalog(
    IptvPlaylist playlist,
    String contentType,
    String cacheKey,
    int ticket,
  ) async {
    // Show the updating chip only when the refresh is genuinely slow (a real
    // network fetch). An in-memory service-cache hit resolves instantly and
    // shouldn't flash UI at the user on every tab switch.
    _chipShowTimer?.cancel();
    _chipShowTimer = Timer(const Duration(milliseconds: 400), () {
      // Full superseded check, not just the ticket: a content-type switch
      // clears the list without bumping the ticket for 350ms, and the chip
      // must not flash over the new type's spinner.
      if (!_revalidateSuperseded(playlist, contentType, ticket)) {
        _showChip(_CatalogChipState.updating, 'Updating list…');
      }
    });

    IptvParseResult result;
    try {
      result = await _fetchCatalogFromNetwork(playlist, contentType);
    } catch (e) {
      result =
          IptvParseResult(channels: const [], categories: const [], error: '$e');
    }
    _chipShowTimer?.cancel();
    final chipWasVisible = _chipState == _CatalogChipState.updating;

    if (_revalidateSuperseded(playlist, contentType, ticket)) return;

    if (result.hasError || result.channels.isEmpty) {
      // The snapshot stays on screen — a failed background refresh is a
      // hint, never an error screen.
      _showChip(
        _CatalogChipState.failure,
        'Couldn\'t refresh — showing saved list',
        autoHide: const Duration(milliseconds: 3500),
      );
      return;
    }

    final current = _allChannels;
    final reconciled = _reconcileChannels(current, result.channels);
    final categoriesChanged = !listEquals(_categories, result.categories);
    var listChanged = reconciled.length != current.length;
    if (!listChanged) {
      for (var i = 0; i < reconciled.length; i++) {
        if (!identical(reconciled[i], current[i])) {
          listChanged = true;
          break;
        }
      }
    }

    if (!listChanged && !categoriesChanged) {
      // Fresh catalog is identical to the snapshot: no setState, no disk
      // write, zero disruption. Acknowledge only if the updating chip
      // actually showed (otherwise the whole refresh was invisible — keep
      // it that way).
      if (chipWasVisible) {
        _showChip(
          _CatalogChipState.success,
          'Up to date',
          autoHide: const Duration(milliseconds: 1800),
        );
      }
      return;
    }

    // Survivor set (object identity) — drives orphan-node disposal, the
    // focus repair, and the "+N new" hint.
    final survivors = HashSet<IptvChannel>.identity()..addAll(reconciled);
    var reused = 0;
    for (final c in current) {
      if (survivors.contains(c)) reused++;
    }
    final added = reconciled.length - reused;

    // Star migration must land before the swap so favorites line up on the
    // first paint of the new rows.
    await StorageService.reconcileIptvFavoriteUrls(reconciled);
    await _loadFavorites();
    if (_revalidateSuperseded(playlist, contentType, ticket)) return;

    // Capture the DPAD position before the swap: if the focused row is
    // dropped, its replacement is whatever occupies the same filtered index.
    IptvChannel? focusedChannel;
    for (final entry in _cardFocusNodes.entries) {
      if (entry.value.hasFocus) {
        focusedChannel = entry.key;
        break;
      }
    }
    final oldFilteredIndex = focusedChannel == null
        ? -1
        : _filteredChannels.indexOf(focusedChannel);

    setState(() {
      _allChannels = reconciled;
      _categories = result.categories;
      // The selected category can vanish in a refresh; falling back to All
      // beats silently filtering to nothing.
      if (_selectedCategory != null &&
          !result.categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
    });
    _applyFilters();

    // Post-frame (the surviving rows must be re-mounted first): repair focus
    // whenever the previously-focused row no longer HOLDS it — that covers
    // dropped rows AND survivors a provider reorder pushed out of the built
    // viewport (their element unmounts, the node detaches, and focus falls
    // silently to the bare scope even though the object "survived"). THEN
    // dispose the orphaned nodes — never the other way around.
    final orphans = [
      for (final channel in _cardFocusNodes.keys)
        if (!survivors.contains(channel)) channel,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Unmounted: State.dispose() already disposed every node in the map —
      // touching them here would double-dispose.
      if (!mounted) return;
      if (focusedChannel != null && ticket == _loadTicket) {
        final survivorNode = _cardFocusNodes[focusedChannel];
        final primary = FocusManager.instance.primaryFocus;
        // Repair only when focus was genuinely LOST (fell to a bare scope).
        // If the user moved to the filters/EPG panel meanwhile, leave them.
        final focusLost = !(survivorNode?.hasFocus ?? false) &&
            (primary == null || primary is FocusScopeNode);
        if (focusLost) {
          // Candidates in order: the same row wherever it moved; whatever
          // now occupies the old position; any built row (keeps DPAD in the
          // grid); the filters bar. ATTACHED nodes only — requestFocus on a
          // node the lazy grid never built is a silent no-op and DPAD would
          // stay stranded on the scope.
          FocusNode? target;
          if (survivorNode?.context != null) target = survivorNode;
          if (target == null && _filteredChannels.isNotEmpty) {
            final idx = oldFilteredIndex < 0
                ? 0
                : oldFilteredIndex.clamp(0, _filteredChannels.length - 1);
            final atIndex = _cardFocusNodes[_filteredChannels[idx]];
            if (atIndex?.context != null) target = atIndex;
          }
          if (target == null) {
            for (final node in _cardFocusNodes.values) {
              if (node.context != null) {
                target = node;
                break;
              }
            }
          }
          (target ?? _playlistFilterFocusNode).requestFocus();
        }
      }
      for (final channel in orphans) {
        _cardFocusNodes.remove(channel)?.dispose();
      }
    });
    WidgetsBinding.instance.scheduleFrame();

    await _loadProgress(ticket, reconciled);
    if (_revalidateSuperseded(playlist, contentType, ticket)) return;

    // Settings can delete or re-source this playlist while the fetch was in
    // flight — re-read the stored list so a deleted playlist's snapshot is
    // never resurrected under its old key, and so the guide rebinds against
    // the CURRENT configuration (e.g. an EPG URL edited mid-revalidate),
    // not the object captured at spawn.
    final storedPlaylists = await StorageService.getIptvPlaylists();
    if (_revalidateSuperseded(playlist, contentType, ticket)) return;
    IptvPlaylist? storedPlaylist;
    for (final p in storedPlaylists) {
      if (p.id == playlist.id) {
        storedPlaylist = p;
        break;
      }
    }

    // EPG context re-runs against the reconciled list (the instances on
    // screen), mirroring what _presentCatalog stores.
    final displayed = IptvParseResult(
      channels: reconciled,
      categories: result.categories,
      epgUrl: result.epgUrl,
    );
    _lastLoadResult = displayed;

    if (storedPlaylist != null &&
        IptvCatalogCache.keyForPlaylist(storedPlaylist, contentType) ==
            cacheKey) {
      // quiet: the snapshot pass already surfaced any manual-EPG failure
      // hint this visit; repeating it here would double the snackbar.
      _updateEpgContext(storedPlaylist, displayed, ticket, quiet: true);
      unawaited(
        IptvCatalogCache.instance.write(
          cacheKey,
          channels: reconciled,
          categories: result.categories,
          epgUrl: result.epgUrl,
        ),
      );
    }

    _showChip(
      _CatalogChipState.success,
      added > 0 ? 'Updated • $added new' : 'List updated',
      autoHide: const Duration(milliseconds: 2200),
    );
  }

  /// Stable identity for reconciling a fresh catalog row against the one on
  /// screen. Xtream rows carry unique panel ids; M3U rows fall back to
  /// url+name (duplicate URLs are legal in the wild, so the name joins the
  /// key — remaining duplicates are consumed one-for-one via the list pool
  /// in [_reconcileChannels]).
  String _channelIdentityKey(IptvChannel c) {
    final id = c.attributes['stream_id'] ?? c.attributes['series_id'];
    if (id != null && id.isNotEmpty) {
      return 'id:${c.contentType ?? ''}:$id';
    }
    return 'u:${c.url}\n${c.name}';
  }

  /// True when two rows would render identically (all displayed/played
  /// fields equal).
  bool _channelDataEquals(IptvChannel a, IptvChannel b) =>
      a.name == b.name &&
      a.url == b.url &&
      a.logoUrl == b.logoUrl &&
      a.group == b.group &&
      a.duration == b.duration &&
      a.contentType == b.contentType &&
      mapEquals(a.attributes, b.attributes) &&
      mapEquals(a.httpHeaders, b.httpHeaders);

  /// Rebuild the fresh list reusing the EXISTING object for every row whose
  /// data didn't change. Object reuse is what keeps DPAD focus, ObjectKeys
  /// and scroll untouched across a background refresh.
  List<IptvChannel> _reconcileChannels(
    List<IptvChannel> current,
    List<IptvChannel> fresh,
  ) {
    if (current.isEmpty) return fresh;
    final pool = <String, List<IptvChannel>>{};
    for (final c in current) {
      pool.putIfAbsent(_channelIdentityKey(c), () => []).add(c);
    }
    return [
      for (final f in fresh)
        () {
          final candidates = pool[_channelIdentityKey(f)];
          if (candidates != null && candidates.isNotEmpty) {
            final old = candidates.removeAt(0);
            if (_channelDataEquals(old, f)) return old;
          }
          return f;
        }(),
    ];
  }

  void _showChip(
    _CatalogChipState state,
    String message, {
    Duration? autoHide,
  }) {
    if (!mounted) return;
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
      });
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
    final isPlainM3u = !playlist.isFavorites &&
        !playlist.isContinueWatching &&
        !playlist.isStremioAddon &&
        !playlist.isXtreamCodes;
    final isXtreamLive =
        playlist.isXtreamCodes && _selectedContentType == 'live';
    if (!isPlainM3u && !isXtreamLive) {
      service.clearM3uEpgContext();
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
        // so a bounded sample decides. Bounding matters in DB mode: the
        // channels list is a paging facade, and walking all of it here would
        // synchronously materialize the whole catalog on the UI isolate for
        // a plain M3U that derives nothing.
        final channels = result.channels;
        final Iterable<IptvChannel> probe = channels is DbChannelList
            ? channels.effectiveSnapshot
                .page(offset: 0, limit: 50, live: true)
            : channels;
        for (final channel in probe) {
          if (!channel.isLive) continue;
          final derived =
              IptvEpgService.xmltvUrlForChannelUrl(channel.url);
          if (derived != null) {
            epgUrl = derived;
            break;
          }
        }
      }
    }
    service
        .setM3uEpgContext(
          playlistKey: playlist.id,
          epgUrl: epgUrl,
          channels: result.channels,
          // DB-backed view: the guide stores its rows in iptv_catalog.db and
          // binds URLs through the catalog instead of whole-playlist maps.
          dbCatalogKey: _dbSnapshot?.catalogKey,
        )
        .then((status) {
      if (!mounted || ticket != _loadTicket) return;
      // Failure hints only for a guide the user configured themselves.
      // Header-derived url-tvg URLs are routinely dead in wild playlists —
      // those users never asked for EPG and got silent no-guide before;
      // nagging them on every load would be a regression.
      void hint(String message) {
        if (quiet || !hasManualUrl) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
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
          hint('TV guide loaded, but none of its channels matched this '
              'playlist (the ids and names don\'t line up).');
        case M3uEpgStatus.noProgrammes:
          hint('TV guide matched this playlist, but it has no programme '
              'data for the current period.');
        case M3uEpgStatus.failed:
          hint('Couldn\'t load the TV guide — check the EPG URL.');
        case M3uEpgStatus.inactive:
          break;
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
    // DB mode: bars load per faulted page (_loadPageProgress); a full-list
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
        channels.add(IptvChannel(
          name: seriesName,
          url: sentinelUrl,
          logoUrl: (item['logoUrl'] as String?)?.isNotEmpty == true
              ? item['logoUrl'] as String
              : null,
          group: seriesName,
          contentType: 'series',
          attributes: {'series_id': seriesId},
        ));
        continue;
      }
      _continuePlaylistIds[item['url'] as String] = originId;
      channels.add(IptvChannel(
        name: (item['name'] as String?)?.isNotEmpty == true
            ? item['name'] as String
            : 'Unknown',
        url: item['url'] as String,
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
      ));
    }
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()
      ..sort();
    // Already ordered most-recently-watched first; leave it alone.
    return IptvParseResult(channels: channels, categories: categories);
  }

  /// Build the virtual Favorites playlist from the starred-channel store.
  /// Metadata was captured at star time, so no fetch is needed; Stremio-keyed
  /// URLs still resolve on focus/play exactly like anywhere else.
  Future<IptvParseResult> _buildFavoritesResult() async {
    final favorites = await StorageService.getIptvFavoriteChannels();
    final channels = favorites.entries.map((entry) {
      final meta = entry.value;
      final name = (meta['name'] as String?) ?? '';
      final logoUrl = (meta['logoUrl'] as String?) ?? '';
      final group = (meta['group'] as String?) ?? '';
      return IptvChannel(
        name: name.isEmpty ? 'Unknown Channel' : name,
        url: entry.key,
        logoUrl: logoUrl.isEmpty ? null : logoUrl,
        group: group.isEmpty ? null : group,
        duration: -1,
        httpHeaders: StorageService.iptvFavoriteHeaders(meta),
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()
      ..sort();
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
            if (entry.value.context == null && !entry.value.hasFocus)
              entry.key,
        ];
        for (final channel in orphans) {
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
    setState(() => _selectedCategory = category);
    _applyFilters();
  }

  /// Cap on the channel list handed to the player. On TV the whole list is
  /// serialized over the platform channel at launch (one JSON map per channel
  /// for the native guide) — a 10k-channel playlist froze the UI for hundreds
  /// of ms right on OK. A window this size is far more guide than anyone
  /// DPADs through while still launching instantly.
  static const int _kMaxPlayerChannels = 1500;

  /// Latch across the resolve+launch window: resolving a Stremio channel
  /// takes real time, and repeated OK presses on a seemingly-idle row must
  /// not stack player launches.
  bool _launchingChannel = false;

  Future<void> _playChannel(IptvChannel channel) async {
    if (_launchingChannel) return;
    _launchingChannel = true;
    try {
      await _playChannelInner(channel);
    } finally {
      _launchingChannel = false;
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
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparing replay of "${programme.title}"…'),
          // Covers the worst-case first-use probe (3 dialects × 10s timeout);
          // hidden explicitly the moment the probe answers.
          duration: const Duration(seconds: 30),
        ),
      );

      final url =
          await IptvEpgService.instance.catchupUrl(channel.url, programme);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      // Stale: the playlist reloaded/switched, or (TV two-pane) the schedule
      // pane this replay was picked from is gone — a player appearing over
      // whatever the user moved on to would read as the wrong programme
      // launching itself. The pane check only applies to the pane flow:
      // the TV-classic fallback replays from the bottom SHEET, where
      // _scheduleChannel is never set and the guard would kill every replay.
      if (ticket != _loadTicket) return;
      if (widget.isTelevision &&
          _tvTwoPaneActive &&
          _scheduleChannel?.url != channel.url) {
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
        await _refreshAfterPlayback();
      }
    } finally {
      _launchingChannel = false;
    }
  }

  Future<void> _playChannelInner(IptvChannel channel) async {
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
      final candidates = await StremioIptvService.instance
          .resolveCandidates(channel.url, refreshIfEmpty: true);
      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              StremioIptvService.instance
                  .unplayableMessage(channel.url, channel.name),
            ),
          ),
        );
        return;
      }
      initialUrl = candidates.first.url;
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
    var channels =
        _filteredChannels.contains(channel) ? _filteredChannels : _allChannels;
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
          ? (channelIndex - _kMaxPlayerChannels ~/ 2)
              .clamp(0, total - _kMaxPlayerChannels)
          : 0;
      channels = source.effectiveSnapshot.page(
        offset: lo,
        limit: _kMaxPlayerChannels,
        group: source.group,
        search: source.search,
      );
      channelIndex = (channelIndex - lo).clamp(0, channels.length - 1);
    } else if (channels.length > _kMaxPlayerChannels) {
      final lo = (channelIndex - _kMaxPlayerChannels ~/ 2)
          .clamp(0, channels.length - _kMaxPlayerChannels);
      channels = channels.sublist(lo, lo + _kMaxPlayerChannels);
      channelIndex -= lo;
    }
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: channel.name,
        subtitle: channel.group ?? 'IPTV',
        viewMode: PlaylistViewMode.sorted,
        iptvChannels: channels,
        iptvStartIndex: channelIndex,
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
      await _refreshAfterPlayback();
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
    _refreshContinueShelfPresence(items.isNotEmpty);
    if (!mounted) return;

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
        _playlists = [..._playlists]..insert(favoritesIndex + 1, _continuePlaylist);
      } else {
        _playlists = [
          for (final p in _playlists)
            if (!p.isContinueWatching) p,
        ];
      }
    });
  }

  bool _previewRearmPending = false;

  /// Complete a parked preview re-arm (see [_playChannel]).
  void _flushPreviewRearm() {
    if (!_previewRearmPending || !mounted) return;
    _previewRearmPending = false;
    _previewEpoch.value++;
    // This fires only after real playback, on both TV return paths (app
    // resume for the native player, next row focus for the in-app fallback) —
    // so it is also exactly when the position the player just saved should be
    // pulled back into the bars and the shelf.
    _refreshAfterPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flushPreviewRearm();
  }

  /// Sidebar enter = lights out for the preview (Home's grammar: the menu
  /// never competes with a playing stage). Dropping the shown channel unmounts
  /// the backdrop, which releases its engine synchronously; refocusing a
  /// channel row re-arms the stage.
  void _onTvSidebarFocusChanged(bool focused) {
    if (focused) _clearPreview();
  }

  /// Open the cross-source global search page. The preview is emptied first
  /// for the same reason [_openSeriesDetail] empties it: playback launched
  /// from the covered route must never race a backdrop left running
  /// underneath. On return, freshly watched items land in the shelf/bars.
  void _openGlobalSearch() {
    _clearPreview();
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) =>
            IptvGlobalSearchPage(isTelevision: widget.isTelevision),
      ),
    )
        .then((_) {
      if (mounted) _refreshAfterPlayback();
    });
  }

  /// The source rail's overflow chip: the full playlist picker sheet, for
  /// when there are more sources than the rail has room to show.
  Future<void> _openPlaylistPickerFromRail() async {
    final result = await showIptvPlaylistPicker(
      context,
      playlists: _playlists,
      selectedPlaylist: _selectedPlaylist,
      onAddPlaylist: _navigateToSettings,
    );
    // The picker sheet is dismissed by its own selection; on TV, land DPAD
    // focus on the list rather than back on the (now-collapsed) rail.
    if (result != null) {
      _onPlaylistChanged(result, focusContent: widget.isTelevision);
    }
  }

  void _navigateToSettings() {
    // Captured for the EPG-URL-edit case below: _loadSettings only reloads
    // the playlist when the SELECTION changes, so an edit to the current
    // playlist's guide URL would otherwise sit inert until a manual playlist
    // switch — "EPG URL saved" with nothing happening.
    final beforeId = _selectedPlaylist?.id;
    final beforeEpgUrl = _selectedPlaylist?.epgUrl;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IptvSettingsPage()),
    ).then((_) async {
      // Reload settings when returning
      await _loadSettings();
      if (!mounted) return;
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
      return const Center(child: CircularProgressIndicator());
    }

    // TV: two-pane — a live preview stage on the left (the focused channel
    // plays embedded after a short dwell; OK still launches the full player),
    // quiet filters + the channel guide on the right. Desktop (redesign) gets
    // the same layout with pointer semantics: hovering a row retunes the
    // preview, clicking plays. Falls back to the classic single-column
    // layout on an implausibly narrow canvas; phones/tablets keep classic.
    final Widget body;
    if (widget.isTelevision || (_redesignEnabled && _isDesktop)) {
      body = LayoutBuilder(
        builder: (context, c) {
          _tvTwoPaneActive = c.maxWidth >= 760 && c.maxHeight >= 380;
          if (!_tvTwoPaneActive) return _buildClassic();
          return _buildTvTwoPane(c);
        },
      );
    } else {
      body = _buildClassic();
    }
    // The background-refresh chip floats over whichever layout is active.
    // passthrough: hand the parent's constraints to the body unmodified so
    // the wrap is provably layout-neutral.
    return Stack(
      fit: StackFit.passthrough,
      children: [body, _buildCatalogChip()],
    );
  }

  /// Bottom-right status chip for background catalog refreshes. Pure
  /// display: no focusables, no hit-testing — DPAD and touch pass straight
  /// through. Snap show/hide, no tween (TV GPU rule).
  Widget _buildCatalogChip() {
    if (_chipState == _CatalogChipState.hidden) {
      return const SizedBox.shrink();
    }
    final Widget leading = switch (_chipState) {
      _CatalogChipState.updating => const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: kSeeAllAccent2,
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
            color: const Color(0xF0141225),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
                  color: Colors.white.withValues(alpha: 0.92),
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

  /// The pre-redesign layout: boxed filter bar over a full-width channel list.
  /// Phone/desktop keep it (no embedded preview there), and TV falls back to
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
          categoryCounts: _redesignEnabled ? _categoryCounts : null,
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
          onGlobalSearch: _redesignEnabled ? _openGlobalSearch : null,
          globalSearchFocusNode:
              _redesignEnabled ? _globalSearchFocusNode : null,
        ),

        // Content
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  // ── TV two-pane ──────────────────────────────────────────────────────────

  Widget _buildTvTwoPane(BoxConstraints c) {
    // Wide desktop windows get the rail inline-expanded (persistent labeled
    // list, no overlay to dismiss); TV and narrow windows keep the compact
    // icon rail. The preview's share is computed from the width that
    // actually remains for the two panes.
    final inlineRail =
        _redesignEnabled && !widget.isTelevision && c.maxWidth >= 1200;
    final double sourceRailW = !_redesignEnabled
        ? 0.0
        : inlineRail
            ? kIptvSourceRailExpandedWidth
            : kIptvSourceRailWidth;
    final paneW = c.maxWidth - sourceRailW;
    final railW = (paneW * 0.40).clamp(320.0, 470.0);
    final scheduleChannel = _scheduleChannel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_redesignEnabled)
          IptvSourceRail(
            playlists: _playlists,
            selectedId: _selectedPlaylist?.id,
            isTelevision: widget.isTelevision,
            inlineExpanded: inlineRail,
            // On TV, picking a source collapses the rail's overlay and hands
            // focus to the list — the standard sidebar → content flow. (On
            // desktop the rail is an inline column / hover overlay that the
            // pointer already dismisses, so leave focus alone.)
            onSelect: (playlist) => _onPlaylistChanged(
              playlist,
              focusContent: widget.isTelevision,
            ),
            onManage: _navigateToSettings,
            onOverflow: _openPlaylistPickerFromRail,
            // RIGHT from a rail chip lands on the quiet filter row's first
            // chip (the search pill — it holds _playlistFilterFocusNode).
            onRight: () => _playlistFilterFocusNode.requestFocus(),
          ),
        SizedBox(width: railW, child: _buildPreviewRail()),
        Expanded(
          // An open schedule covers the guide column in place — the preview
          // rail keeps playing, and BACK restores the list exactly as it
          // was. Offstage (not a swap) keeps the grid, its scroll offset and
          // its focus nodes alive, so closing can hand focus straight back
          // to the originating row; ExcludeFocus keeps DPAD from wandering
          // into the hidden rows meanwhile.
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: scheduleChannel != null,
                child: ExcludeFocus(
                  excluding: scheduleChannel != null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 24, 4),
                        child: _buildQuietFilters(),
                      ),
                      Expanded(child: _buildContent(tvPane: true)),
                    ],
                  ),
                ),
              ),
              if (scheduleChannel != null)
                IptvSchedulePane(
                  channel: scheduleChannel,
                  onClose: _closeSchedulePane,
                  onPlayProgramme: (programme) =>
                      _playCatchup(scheduleChannel, programme),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The Discover-style quiet filter line: bare dot-separated text segments
  /// (playlist • [Live/Movies] • category • count) instead of boxed pills.
  Widget _buildQuietFilters() {
    return SeeAllFilterBar(
      isTelevision: widget.isTelevision,
      quiet: true,
      buildChips: () => [
        // Redesign: the source rail owns playlist switching, so the row's
        // first chip becomes the global-search pill instead of the playlist
        // dropdown. It inherits _playlistFilterFocusNode on purpose — every
        // existing wire into "the first filter" (down-from-search-field,
        // revalidate focus repair, focusFirstFilter) keeps working unchanged.
        if (_redesignEnabled)
          _QuietSearchChip(
            focusNode: _playlistFilterFocusNode,
            onPressed: _openGlobalSearch,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
          )
        else
          StremioDropdown<String>(
            label: 'playlist',
            value: _selectedPlaylist?.id ?? '',
            quiet: true,
            quietAccent: true,
            isTelevision: widget.isTelevision,
            focusNode: _playlistFilterFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: [
              for (final p in _playlists) StremioDropdownOption(p.id, p.name),
              const StremioDropdownOption(
                  _kAddPlaylistSentinel, '＋ Add playlist'),
            ],
            onSelected: (id) {
              if (id == _kAddPlaylistSentinel) {
                _navigateToSettings();
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
              StremioDropdownOption(
                  '',
                  _redesignEnabled
                      ? 'All · ${_allChannels.length}'
                      : 'All'),
              for (final cat in _categories)
                StremioDropdownOption(
                    cat,
                    _redesignEnabled
                        ? '$cat · ${_categoryCounts[cat] ?? 0}'
                        : cat),
            ],
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
              color: Colors.white.withValues(alpha: 0.40),
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

  /// Called by a channel row gaining DPAD focus — retunes the preview stage.
  void _onChannelFocused(IptvChannel channel) {
    // The in-app player fallback never pauses the app, so a parked re-arm
    // wouldn't flush via the lifecycle observer — the focus restore after its
    // route pops (or the user's next move) lands here instead.
    _flushPreviewRearm();
    if (_previewShown.value?.url == channel.url) return;
    _previewShown.value = channel;
    _retunePreview(channel);
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

  /// Empty the stage entirely (playlist switch, sidebar open) and abandon any
  /// in-flight resolve.
  void _clearPreview() {
    _previewResolveTicket++;
    _previewCandidates = null;
    _previewShown.value = null;
    _previewStreamUrl.value = null;
    _previewShowing.value = false;
  }

  Widget _buildPreviewRail() {
    return Padding(
      // The source rail supplies the left inset when it's present.
      padding: EdgeInsets.fromLTRB(_redesignEnabled ? 14 : 24, 16, 12, 16),
      child: ValueListenableBuilder<int>(
        valueListenable: _previewEpoch,
        builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
          valueListenable: _previewShown,
          builder: (context, ch, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPreviewStage(ch, epoch),
              const SizedBox(height: 16),
              Expanded(child: _IptvRailInfo(channel: ch)),
              // Remote-key hints are TV language; the pointer world gets one
              // quiet line instead.
              if (widget.isTelevision)
                _IptvRailHints(
                  showGuide: ch != null && IptvEpgService.isEpgCapable(ch),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Hover a channel to preview  ·  Click to watch',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewStage(IptvChannel? ch, int epoch) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
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
                tuning: ch != null && !showing,
              ),
            ),
            if (ch != null)
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({bool tvPane = false}) {
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
      final status = _loadingStatus;
      if (status == null) {
        return const Center(child: CircularProgressIndicator());
      }
      // One-time work worth naming (the legacy-snapshot → catalog-DB
      // upgrade blocks this page, deliberately — see _loadPlaylist).
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
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
                onPressed: () => _loadPlaylist(_selectedPlaylist!),
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
      final isContinueView = _selectedPlaylist?.isContinueWatching ?? false;
      final unfiltered = widget.searchQuery.isEmpty && _selectedCategory == null;
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
                          : isFavoritesView
                              ? 'Star channels in any playlist and they show up here'
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

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        // The delegate's own column math, replicated so rows can know
        // whether they sit on the grid's right edge (those get the
        // RIGHT-opens-schedule key; the rest keep plain traversal).
        final crossExtent =
            (constraints.maxWidth - hPadding - padRight).clamp(1.0, double.infinity);
        final columns = (crossExtent / (maxCrossAxisExtent + crossAxisSpacing))
            .ceil()
            .clamp(1, 100);
        final itemCount = _filteredChannels.length;

        return TvFocusScrollWrapper(
          child: FocusTraversalGroup(
            child: GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(hPadding, 8, padRight, 24),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: maxCrossAxisExtent,
                // A grid has one tile height for every row, so the taller
                // poster rows are all-or-nothing per view. On-demand lists are
                // homogeneous in practice (the type dropdown splits live from
                // movies, and both virtual shelves are single-kind). EPG rows
                // (redesign) are taller again — now/next lives in the row.
                mainAxisExtent: _showsPosterRows
                    ? kIptvPosterRowExtent
                    : epgRows
                        ? kIptvEpgRowExtent
                        : kIptvRowExtent,
                mainAxisSpacing: 4,
                crossAxisSpacing: crossAxisSpacing,
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                final channel = _filteredChannels[index];
                // Right edge = last column, or the final item of a partial
                // last row (nothing exists to its right either way).
                final rightEdge = index % columns == columns - 1 ||
                    index == itemCount - 1;
                return IptvChannelRow(
                  // ObjectKey, not ValueKey(url): duplicate URLs are legal in a
                  // playlist, and sibling rows must never share a key (or the
                  // focus node cached behind it — see _cardFocusNodes).
                  key: ObjectKey(channel),
                  channel: channel,
                  isTelevision: widget.isTelevision,
                  onTap: () => _playChannel(channel),
                  focusNode: _focusNodeFor(channel),
                  isFavorited: _favoriteUrls.contains(channel.url),
                  // Series rows can't be starred: the favorites store replays
                  // entries by URL, and a series' sentinel URL isn't playable
                  // (nor are its credentials recoverable from the store).
                  onFavoriteToggle: channel.contentType == 'series'
                      ? null
                      : (isFavorited) =>
                          _toggleFavorite(channel, isFavorited),
                  onFocused: tvPane ? () => _onChannelFocused(channel) : null,
                  onSchedule: _scheduleActionFor(channel),
                  scheduleOnRightKey: rightEdge,
                  progress: _progressByUrl[channel.url],
                  poster: _showsPosterRows,
                  epg: epgRows,
                );
              },
            ),
          ),
        );
      },
    );
    if (!_isLoadingMore) return grid;

    // Streamed load still running: a quiet, non-focusable line keeps the
    // visible (possibly filtered) rows honest about being a partial list.
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
        ),
        Expanded(child: grid),
      ],
    );
  }
}

/// The quiet filter row's global-search pill (redesign): same bare-segment
/// language as the quiet dropdowns beside it, opens the cross-source search
/// page. Carries the row's "first filter" focus node — see the call site.
class _QuietSearchChip extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onUpArrowPressed;
  final VoidCallback? onDownArrowPressed;

  const _QuietSearchChip({
    required this.focusNode,
    required this.onPressed,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
  });

  @override
  State<_QuietSearchChip> createState() => _QuietSearchChipState();
}

class _QuietSearchChipState extends State<_QuietSearchChip> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onUpArrowPressed != null) {
          widget.onUpArrowPressed!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onDownArrowPressed != null) {
          widget.onDownArrowPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
          decoration: BoxDecoration(
            color: _focused
                ? kSeeAllAccent.withValues(alpha: 0.30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            // Constant thickness — only the color changes on focus, so the
            // row never reflows on DPAD moves (quiet-chip house rule).
            border: Border.all(
              width: 1.2,
              color: _focused
                  ? kSeeAllAccent2.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 14,
                color: _focused ? Colors.white : kSeeAllAccent2,
              ),
              const SizedBox(width: 5),
              Text(
                'Search all',
                style: TextStyle(
                  color: _focused ? Colors.white : kSeeAllAccent2,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final ch = widget.channel;
    final brand = ch != null ? brandAccentFor(ch.name) : kSeeAllAccent;
    final logo = ch?.logoUrl;
    final animate = widget.tuning && ch != null;

    Widget mark = ch == null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.live_tv_rounded,
                size: 42,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 10),
              Text(
                'Browse channels to preview',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
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
            CustomPaint(painter: _TuningWavesPainter(brand: brand, t: _ctrl)),
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
/// the stream hasn't opened yet, PREVIEW for on-demand items. Conditional
/// swaps and direct paint only — no fades over the stage, and only the
/// TUNING state animates so nothing repaints while video is playing.
class _IptvStageChip extends StatefulWidget {
  final IptvChannel? channel;
  final bool showing;
  const _IptvStageChip({required this.channel, required this.showing});

  @override
  State<_IptvStageChip> createState() => _IptvStageChipState();
}

class _IptvStageChipState extends State<_IptvStageChip>
    with SingleTickerProviderStateMixin {
  static const Color _live = Color(0xFF34D399);
  static const Color _amber = Color(0xFFFBBF24);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool get _tuning => widget.channel != null && !widget.showing;

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
    final ch = widget.channel;
    if (ch == null) return const SizedBox.shrink();
    final isLive = ch.isLive;
    final label = widget.showing ? (isLive ? 'LIVE' : 'PREVIEW') : 'TUNING';
    final dot = isLive ? _live : kSeeAllAccent2;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        color: const Color(0xB00B0918),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
                      decoration:
                          BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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

/// Identity block under the stage: logo chip, channel name (resolution pulled
/// out into the sub-line), group. Empty when nothing is focused yet.
class _IptvRailInfo extends StatelessWidget {
  final IptvChannel? channel;
  const _IptvRailInfo({required this.channel});

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    if (ch == null) return const SizedBox.shrink();
    final brand = brandAccentFor(ch.name);

    final resMatch = _railResExp.firstMatch(ch.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? ch.name
        : ch.name
            .replaceRange(resMatch.start, resMatch.end, '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
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
                borderRadius: BorderRadius.circular(11),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.06)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      brand.withValues(alpha: 0.16),
                      const Color(0xFF1E2030),
                    ),
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
                    style: const TextStyle(
                      color: Colors.white,
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
                        color: Colors.white.withValues(alpha: 0.52),
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

/// Bottom-of-rail key hints: OK to watch fullscreen, hold OK to favourite,
/// and — when the focused channel has guide data — RIGHT for its schedule.
class _IptvRailHints extends StatelessWidget {
  final bool showGuide;
  const _IptvRailHints({this.showGuide = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _KeyCap('OK'),
        const SizedBox(width: 6),
        _hint('Watch'),
        const SizedBox(width: 16),
        const _KeyCap('HOLD OK'),
        const SizedBox(width: 6),
        _hint('Favorite'),
        if (showGuide) ...[
          const SizedBox(width: 16),
          const _KeyCap('▶'),
          const SizedBox(width: 6),
          _hint('Guide'),
        ],
      ],
    );
  }

  Widget _hint(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: HomeTheme.focusGold.withValues(alpha: 0.95),
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
