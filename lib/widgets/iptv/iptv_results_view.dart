import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import '../../models/iptv_playlist.dart';
import '../browse/brand_accent.dart';
import '../browse/browse_results_focus.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/stremio_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../screens/debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../../screens/settings/iptv_settings_page.dart';
import '../hero_trailer_backdrop.dart';
import '../home/home_theme.dart';
import '../see_all/see_all_filter_bar.dart';
import '../see_all/see_all_theme.dart';
import '../see_all/stremio_dropdown.dart';
import '../../services/iptv_epg_service.dart';
import 'iptv_filters.dart';
import 'iptv_channel_row.dart';
import 'iptv_empty_state.dart';
import 'iptv_epg_panel.dart';

/// Matches a trailing resolution the M3U names embed, e.g. "(1080p)" / "(576i)"
/// — pulled out of the rail's big title into its sub-line (the channel rows do
/// the same split for themselves).
final RegExp _railResExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

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

  // Current playlist data
  List<IptvChannel> _allChannels = [];
  List<IptvChannel> _filteredChannels = [];
  List<String> _categories = [];
  String? _selectedCategory;

  // Content type for Xtream Codes playlists
  String _selectedContentType = 'live';

  // Loading state
  bool _isLoading = false;
  String? _errorMessage;

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
    if (playlist.isXtreamCodes) return _selectedContentType == 'vod';
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

  /// The schedule action for a row, or null when the channel can't have
  /// guide data (no RIGHT-key handling, no calendar icon).
  VoidCallback? _scheduleActionFor(IptvChannel channel) {
    if (!IptvEpgService.isEpgCapable(channel)) return null;
    if (widget.isTelevision) return () => _openSchedulePane(channel);
    return () => showIptvScheduleSheet(context, channel);
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

  Future<void> _loadPlaylist(IptvPlaylist playlist) async {
    final ticket = ++_loadTicket;
    _lastProgressiveApply = null;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _errorMessage = null;
      _allChannels = [];
      _filteredChannels = [];
      _categories = [];
      _selectedCategory = null;
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
    } else if (playlist.isXtreamCodes) {
      final xcService = XtreamCodesService.instance;
      if (_selectedContentType == 'vod') {
        result = await xcService.fetchVodStreams(playlist.serverUrl!, playlist.username!, playlist.password!);
      } else {
        result = await xcService.fetchLiveStreams(playlist.serverUrl!, playlist.username!, playlist.password!);
      }
    } else if (playlist.isLocalFile) {
      result = await _iptvService.parseContent(playlist.content!);
    } else {
      result = await _iptvService.fetchPlaylist(playlist.url);
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
      return;
    }

    // Migrate favorites saved under older URL formats (e.g. before the
    // Xtream /live/ URL fix) to the freshly fetched URLs, then reload so
    // the stars line up. (The Favorites view's channels ARE the store —
    // nothing to migrate against.)
    if (!playlist.isFavorites && !playlist.isContinueWatching) {
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
    _updateEpgContext(playlist, result, ticket);
  }

  /// Activate (or clear) XMLTV guide data for the loaded playlist. Fire and
  /// forget: the list renders immediately, and rows re-render with their
  /// schedule affordances if/when the guide lands. Xtream playlists skip
  /// this entirely — their EPG rides on per-stream endpoints.
  void _updateEpgContext(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket,
  ) {
    final service = IptvEpgService.instance;
    final isPlainM3u = !playlist.isFavorites &&
        !playlist.isContinueWatching &&
        !playlist.isStremioAddon &&
        !playlist.isXtreamCodes;
    if (!isPlainM3u) {
      service.clearM3uEpgContext();
      return;
    }
    // A user-configured guide URL beats the playlist header's url-tvg.
    final manual = playlist.epgUrl?.trim();
    final epgUrl =
        (manual != null && manual.isNotEmpty) ? manual : result.epgUrl;
    service
        .setM3uEpgContext(
          playlistKey: playlist.id,
          epgUrl: epgUrl,
          channels: result.channels,
        )
        .then((hasData) {
      // Capability changed: rebuild the rows so EPG-covered channels gain
      // the RIGHT-key/calendar affordance. The rail card refreshes itself
      // via the service's contextVersion listener.
      if (hasData && mounted && ticket == _loadTicket) setState(() {});
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
    _lastProgressiveApply = now;
    setState(() {
      _isLoading = false; // first batch swaps the spinner for real rows
      _isLoadingMore = true;
      _allChannels = channels;
      _categories = categories;
    });
    _applyFilters();
  }

  /// Look up saved positions for the loaded list. Live channels can't have
  /// one, so a playlist with no on-demand items skips the read entirely —
  /// that's the overwhelmingly common case (a live-TV panel).
  Future<void> _loadProgress(int ticket, List<IptvChannel> channels) async {
    final onDemand = [
      for (final channel in channels)
        if (!channel.isLive) channel.url,
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
    _continuePlaylistIds = {
      for (final item in items)
        item['url'] as String: (item['playlistId'] as String?) ?? '',
    };
    final channels = [
      for (final item in items)
        IptvChannel(
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
        ),
    ];
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

  void _onPlaylistChanged(IptvPlaylist? playlist) {
    if (playlist == null || playlist == _selectedPlaylist) return;

    setState(() {
      _selectedPlaylist = playlist;
      _selectedCategory = null;
      if (playlist.isXtreamCodes) {
        _selectedContentType = 'live';
      }
    });

    _loadPlaylist(playlist);
  }

  void _onContentTypeChanged(String contentType) {
    if (contentType == _selectedContentType) return;

    setState(() {
      _selectedContentType = contentType;
      _selectedCategory = null;
    });

    if (_selectedPlaylist != null) {
      _loadPlaylist(_selectedPlaylist!);
    }
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

  Future<void> _playChannelInner(IptvChannel channel) async {
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
    var channelIndex = channels.indexOf(channel);
    if (channelIndex < 0) channelIndex = 0;
    if (channels.length > _kMaxPlayerChannels) {
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
    if (mounted && widget.isTelevision) {
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
      final fresh = {for (final item in items) item['url'] as String};
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

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IptvSettingsPage()),
    ).then((_) {
      // Reload settings when returning
      _loadSettings();
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
    // quiet filters + the channel guide on the right. Falls back to the
    // classic single-column layout on an implausibly narrow canvas.
    if (widget.isTelevision) {
      return LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 760 || c.maxHeight < 380) return _buildClassic();
          return _buildTvTwoPane(c);
        },
      );
    }
    return _buildClassic();
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
    final railW = (c.maxWidth * 0.40).clamp(320.0, 470.0);
    final scheduleChannel = _scheduleChannel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      isTelevision: true,
      quiet: true,
      buildChips: () => [
        StremioDropdown<String>(
          label: 'playlist',
          value: _selectedPlaylist?.id ?? '',
          quiet: true,
          quietAccent: true,
          isTelevision: true,
          focusNode: _playlistFilterFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _focusFirstChannel,
          options: [
            for (final p in _playlists) StremioDropdownOption(p.id, p.name),
            const StremioDropdownOption(_kAddPlaylistSentinel, '＋ Add playlist'),
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
            isTelevision: true,
            focusNode: _contentTypeFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: const [
              StremioDropdownOption('live', 'Live TV'),
              StremioDropdownOption('vod', 'Movies'),
            ],
            onSelected: _onContentTypeChanged,
          ),
        if (_categories.isNotEmpty)
          StremioDropdown<String>(
            label: 'category',
            value: _selectedCategory ?? '',
            quiet: true,
            isTelevision: true,
            focusNode: _categoryFilterFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: [
              const StremioDropdownOption('', 'All'),
              for (final cat in _categories) StremioDropdownOption(cat, cat),
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
      padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
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
              _IptvRailHints(
                showGuide: ch != null && IptvEpgService.isEpgCapable(ch),
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
      return const Center(child: CircularProgressIndicator());
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
                // movies, and both virtual shelves are single-kind).
                mainAxisExtent:
                    _showsPosterRows ? kIptvPosterRowExtent : kIptvRowExtent,
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
                  onFavoriteToggle: (isFavorited) =>
                      _toggleFavorite(channel, isFavorited),
                  onFocused: tvPane ? () => _onChannelFocused(channel) : null,
                  onSchedule: _scheduleActionFor(channel),
                  scheduleOnRightKey: rightEdge,
                  progress: _progressByUrl[channel.url],
                  poster: _showsPosterRows,
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
