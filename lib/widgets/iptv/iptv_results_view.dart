import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_facades.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_maintenance.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_network.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_presentation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_refresh.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_category_order.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_load_status.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/features/iptv/application/iptv_layout_policy.dart';
import 'package:debrify/features/iptv/application/iptv_load_status_policy.dart';
import 'package:debrify/features/iptv/application/iptv_rail_resolution.dart';
import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/iptv_stage_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_stage_info.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_landing_policy.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_rail_info.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_stage_floor.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_identity.dart';
import 'package:debrify/features/iptv/presentation/spotlight_category_picker_dialog.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kIsWeb,
        mapEquals,
        setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';
import '../../services/debrify_image_cache.dart';
import '../browse/brand_accent.dart';
import '../browse/browse_results_focus.dart';
import '../browse/browse_search_header.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_catalog_key.dart';
import '../../services/iptv_channel_order.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_refresh_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/stremio_service.dart';
import '../../services/xtream_codes_service.dart';
import '../../services/video_player_launcher.dart';
import '../../utils/iptv_player_paging.dart';
import '../../utils/tv_keys.dart' show TvHeldKeyGuard, isActivateOrSpaceKey;
import '../../screens/iptv/xtream_series_detail.dart';
import '../../screens/settings/iptv_settings_page.dart';
import '../hero_trailer_backdrop.dart';
import '../home/cw_card_menu.dart';
import '../../theme/app_theme_scope.dart';
import '../see_all/see_all_filter_bar.dart';
import '../see_all/stremio_dropdown.dart';
import '../../services/iptv_epg_service.dart';
import 'db_channel_list.dart';
import 'iptv_centered_selector.dart';
import 'iptv_filters.dart';
import 'iptv_channel_row.dart';
import 'iptv_empty_state.dart';
import 'iptv_epg_panel.dart';
import 'iptv_command_rail.dart';
import 'iptv_stage_panel.dart';
import 'styles/iptv_console_widgets.dart';
import 'styles/iptv_edition_hero.dart';
import 'styles/iptv_style.dart';
import 'spotlight/iptv_spotlight_layout.dart';
import 'spotlight/spotlight_category_control.dart';
import 'spotlight/spotlight_content_type_control.dart';
import 'spotlight/spotlight_live_timeline.dart';
import 'spotlight/spotlight_programme_hero.dart';
import 'spotlight/spotlight_rail.dart';
import 'spotlight/spotlight_shell.dart';
import '../../screens/settings/recordings_page.dart';
import '../../services/desktop_recording_service.dart';
import '../../services/desktop_schedule_service.dart';
import '../../services/iptv_source_stats.dart';
import '../../services/profiles/profile_preferences.dart';

import '../../services/live_recording_service.dart';
import '../recording_limit_dialogs.dart';









/// Main view for IPTV M3U results, to be embedded in TorrentSearchScreen
class IptvResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;
  final Widget? searchHeader;

  /// Test hook fired only after a startup row has reached Spotlight's logical
  /// cursor. Production callers leave this null.
  @visibleForTesting
  final ValueChanged<int>? debugOnSpotlightStartupFocus;

  /// Clock for deterministic Spotlight paint characterization.
  @visibleForTesting
  final DateTime Function() debugSpotlightNow;

  /// Callback when up arrow is pressed from filters (to go back to source dropdown)
  final VoidCallback? onUpArrowFromFilters;

  const IptvResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    this.onUpArrowFromFilters,
    this.searchHeader,
    this.debugOnSpotlightStartupFocus,
    this.debugSpotlightNow = DateTime.now,
  });

  @override
  State<IptvResultsView> createState() => IptvResultsViewState();
}

class IptvResultsViewState extends State<IptvResultsView>
    with WidgetsBindingObserver
    implements
        BrowseResultsFocusController,
        BrowseSearchResultsFocusController {
  late final IptvFavorites _favorites = IptvFavorites((
    catalogState: _catalogState,
    membershipState: _membershipState,
    settingsState: _settingsState,
    context: () => context,
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => mounted,
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _onPlaylistChanged(playlist, focusContent: focusContent),
    refreshListShelfPresence: () => _refreshListShelfPresence(),
    setState: setState,
  ));
  late final IptvSettingsLoading _settingsLoading = IptvSettingsLoading((
    catalogState: _catalogState,
    membershipState: _membershipState,
    previewState: _previewState,
    recordingState: _recordingState,
    settingsState: _settingsState,
    listPlaylist: (IptvListMeta list) => IptvFavorites.listPlaylist(list),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => mounted,
    retunePreview: (IptvChannel channel) => _retunePreview(channel),
    setState: setState,
    stopPreviewPlayback: () => _stopPreviewPlayback(),
  ));
  late final IptvCatalogLoading _catalogLoading = IptvCatalogLoading((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    statusState: _statusState,
    applyProgressiveBatch: (int ticket, List<IptvChannel> channels, List<String> categories) => _applyProgressiveBatch(ticket, channels, categories),
    beginLoadStatus: () => _loadStatus.beginLoadStatus(),
    buildContinueResult: () => _buildContinueResult(),
    buildListResult: (String listId) => _buildListResult(listId),
    clearPreview: () => _clearPreview(),
    consumeContentFocusRequest: () => _consumeContentFocusRequest(),
    endLoadStatus: () => _loadStatus.endLoadStatus(),
    fetchCatalogFromNetwork: (IptvPlaylist playlist, String contentType, int ticket) => _catalogNetwork.fetchCatalogFromNetwork(playlist, contentType, ticket),
    mounted: () => mounted,
    onLoadPhase: (int ticket, String phase, {int? bytes, int? totalBytes}) => _loadStatus.onLoadPhase(ticket, phase, bytes: bytes, totalBytes: totalBytes),
    presentCatalog: (IptvPlaylist playlist, int ticket, IptvParseResult result, {bool migrateFavorites = true, String? cacheKey}) => _catalogPresentation.presentCatalog(playlist, ticket, result, migrateFavorites: migrateFavorites, cacheKey: cacheKey),
    presentDbCatalog: (IptvPlaylist playlist, int ticket, CatalogSnapshot snap, {String? warning, bool migrateFavorites = false}) => _catalogPresentation.presentDbCatalog(playlist, ticket, snap, warning: warning, migrateFavorites: migrateFavorites),
    runCatalogMaintenance: (IptvPlaylist playlist, String contentType, String cacheKey, int ticket, {required bool userRequested}) => _catalogMaintenance.runCatalogMaintenance(playlist, contentType, cacheKey, ticket, userRequested: userRequested),
    runPendingMigrations: (String cacheKey, int ticket) => _catalogMaintenance.runPendingMigrations(cacheKey, ticket),
    setState: setState,
  ));
  late final IptvCatalogPresentation _catalogPresentation = IptvCatalogPresentation((
    catalogState: _catalogState,
    applyFilters: () => _applyFilters(),
    consumeContentFocusRequest: () => _consumeContentFocusRequest(),
    context: () => context,
    endLoadStatus: () => _loadStatus.endLoadStatus(),
    landingCategory: (String? orderKey, List<String> categories) => _landingCategory(orderKey, categories),
    loadFavorites: () => _favorites.loadFavorites(),
    loadProgress: (int ticket, List<IptvChannel> channels) => _loadProgress(ticket, channels),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) => _catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => mounted,
    recomputeSourceCounts: () => _recomputeSourceCounts(),
    setState: setState,
    updateEpgContext: (IptvPlaylist playlist, IptvParseResult result, int ticket, {bool quiet = false}) => _updateEpgContext(playlist, result, ticket, quiet: quiet),
  ));
  late final IptvCatalogFacades _catalogFacades = IptvCatalogFacades((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    settingsState: _settingsState,
    applyFilters: () => _applyFilters(),
    mounted: () => mounted,
    setState: setState,
  ));
  late final IptvCatalogMaintenance _catalogMaintenance = IptvCatalogMaintenance((
    catalogState: _catalogState,
    finishMaintenanceChip: ({required bool narrate, required bool numbersMoved}) => _statusChip.finishMaintenanceChip(narrate: narrate, numbersMoved: numbersMoved),
    mounted: () => mounted,
    rebuildDbFacades: (CatalogSnapshot snap) => _catalogFacades.rebuildDbFacades(snap),
    revalidateDbCatalog: (IptvPlaylist playlist, String contentType, String cacheKey, int ticket) => _catalogRefresh.revalidateDbCatalog(playlist, contentType, cacheKey, ticket),
    revalidateSuperseded: (IptvPlaylist playlist, String contentType, int ticket) => _catalogFacades.revalidateSuperseded(playlist, contentType, ticket),
    scheduleMaintenanceChip: (int ticket) => _statusChip.scheduleMaintenanceChip(ticket),
  ));
  late final IptvStatusChip _statusChip = IptvStatusChip((
    catalogState: _catalogState,
    statusState: _statusState,
    mounted: () => mounted,
    recomputeSourceCounts: () => _recomputeSourceCounts(),
    setState: setState,
  ));
  late final IptvCatalogRefresh _catalogRefresh = IptvCatalogRefresh((
    catalogState: _catalogState,
    focusState: _focusState,
    settingsState: _settingsState,
    statusState: _statusState,
    applyFilters: () => _applyFilters(),
    deriveCategories: (CatalogSnapshot snap, List<CatalogGroup> groups) => _catalogPresentation.deriveCategories(snap, groups),
    loadFavorites: () => _favorites.loadFavorites(),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) => _catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => mounted,
    presentCatalog: (IptvPlaylist playlist, int ticket, IptvParseResult result, {bool migrateFavorites = true, String? cacheKey}) => _catalogPresentation.presentCatalog(playlist, ticket, result, migrateFavorites: migrateFavorites, cacheKey: cacheKey),
    revalidateSuperseded: (IptvPlaylist playlist, String contentType, int ticket) => _catalogFacades.revalidateSuperseded(playlist, contentType, ticket),
    rowAttached: (IptvChannel channel) => _rowAttached(channel),
    setState: setState,
    showChip: (CatalogChipState state, String message, {Duration? autoHide, ChipOwner owner = ChipOwner.refresh}) => _statusChip.showChip(state, message, autoHide: autoHide, owner: owner),
    updateEpgContext: (IptvPlaylist playlist, IptvParseResult result, int ticket, {bool quiet = false}) => _updateEpgContext(playlist, result, ticket, quiet: quiet),
  ));
  late final IptvCatalogNetwork _catalogNetwork = IptvCatalogNetwork((
    catalogState: _catalogState,
    settingsState: _settingsState,
    mounted: () => mounted,
    onLoadPhase: (int ticket, String phase, {int? bytes, int? totalBytes}) => _loadStatus.onLoadPhase(ticket, phase, bytes: bytes, totalBytes: totalBytes),
  ));
  late final IptvLoadStatus _loadStatus = IptvLoadStatus((
    catalogState: _catalogState,
    statusState: _statusState,
    context: () => context,
    mounted: () => mounted,
    setState: setState,
  ));

  final _catalogState = IptvCatalogState();
  final _focusState = IptvFocusState();
  final _membershipState = IptvMembershipState();
  final _playerState = IptvPlayerState();
  final _previewState = IptvPreviewState();
  final _recordingState = IptvRecordingState();
  final _selectionState = IptvSelectionState();
  final _settingsState = IptvSettingsState();
  final _statusState = IptvStatusState();




  // ---- Startup channel -----------------------------------------------------
  // Grid metrics, published from the LayoutBuilder so the startup launch can
  // scroll to a not-yet-built row.







  // Playlists and settings


  // ---- Command Center (rail + stage cockpit) ------------------------------





















  bool get _spotlightRequestedForDevice =>
      _settingsState.iptvStyle == IptvStyle.spotlight && (widget.isTelevision || IptvSettingsState.isDesktop);

  static const double tabletTwoPaneMinWidth = IptvLayoutPolicy.tabletTwoPaneMinWidth;
  static const double tabletTwoPaneMinHeight = IptvLayoutPolicy.tabletTwoPaneMinHeight;

  static bool shouldUseTouchTabletTwoPane({
    required bool isTelevision,
    required bool isWeb,
    required TargetPlatform platform,
    required Size availableSize,
  }) => IptvLayoutPolicy.shouldUseTouchTabletTwoPane(isTelevision: isTelevision, isWeb: isWeb, platform: platform, availableSize: availableSize);

  /// Mount the parent-owned Browse search field in the shipped position. The
  /// Spotlight shell takes the same widget as a rail slot instead, so each
  /// build mounts exactly one instance while BrowseScreen retains its query,
  /// controller, IME and TV focus-handoff state.
  Widget _withBrowseSearch(Widget child) {
    final search = widget.searchHeader;
    if (search == null) return child;
    return Column(
      children: [
        search,
        Expanded(child: child),
      ],
    );
  }

  // Current playlist data





  // Search spans the current source; retain the browse category for clearing.
  String? get _effectiveCategory =>
      widget.searchQuery.isNotEmpty ? null : _catalogState.selectedCategory;

















  // Content type for Xtream Codes playlists


  // Loading state



  // Background catalog refresh (stale-while-revalidate) status chip.
  // `updating` appears only when the revalidate is genuinely slow (a real
  // network fetch), so instant in-memory-cache revalidates never flash it.


  // ── Blocking-load status ────────────────────────────────────────────────
  // A first load of a big panel is several seconds behind a spinner, and
  // silence reads as "frozen". These carry what is happening plus a real
  // number when one exists.
  //
  // Deliberately NOT setState-ed per update: byte callbacks fire per network
  // chunk, and repainting on each would be exactly the UI-isolate churn this
  // page has spent so long shedding. They are plain fields, and [_loadTicker]
  // repaints once a second — which also makes the elapsed clock tick.













  // Progressive (Stremio-addon) loads: [_loadTicket] orphans a superseded
  // load's batches AND its final result, and doubles as the cancel signal
  // that stops its catalog walk; [_isLoadingMore] is true from the first
  // streamed batch until the walk completes — every "N channels" readout and
  // empty state must stay honest while it's set (the list is still growing,
  // so a search can have matches on the way).








  // Favorites — the built-in list, kept as its own set because every row's
  // star icon reads it on each build.


















  /// Whether the current view shows on-demand items, which are drawn as 2:3
  /// posters in taller rows. Derived from the selected view rather than by
  /// scanning the channels: the grid needs one answer for every tile, and
  /// scanning tens of thousands of rows per build to get it isn't free.
  ///
  /// M3U playlists keep the logo layout even for their VOD entries — their
  /// content type is a duration heuristic, so a mixed playlist has no single
  /// honest answer here.
  bool get _showsPosterRows {
    final playlist = _settingsState.selectedPlaylist;
    if (playlist == null) return false;
    if (playlist.isContinueWatching) return true;
    if (playlist.isXtreamCodes) {
      return _catalogState.selectedContentType == 'vod' || _catalogState.selectedContentType == 'series';
    }
    return false;
  }



  // Focus nodes for DPAD
















  Map<String, int> get _categoryCounts {
    // Counts come from one GROUP BY at present time — scanning the
    // facade here would page through the whole catalog.
    if (_catalogState.dbSnapshot != null) return _catalogState.dbGroupCounts;
    if (!identical(_catalogState.categoryCountsSource, _catalogState.allChannels) ||
        _catalogState.categoryCountsLength != _catalogState.allChannels.length) {
      final counts = <String, int>{};
      for (final channel in _catalogState.allChannels) {
        final group = channel.group;
        if (group != null && group.isNotEmpty) {
          counts[group] = (counts[group] ?? 0) + 1;
        }
      }
      _catalogState.categoryCountsSource = _catalogState.allChannels;
      _catalogState.categoryCountsLength = _catalogState.allChannels.length;
      _catalogState.categoryCountsCache = counts;
    }
    return _catalogState.categoryCountsCache;
  }

  /// Whether the current list draws EPG rows (now/next inside each row).
  /// Poster lists never do; otherwise sampled from the first few channels —
  /// Xtream capability is homogeneous (URL parse), but XMLTV matching is
  /// per-channel, and a single unmatched channel at position 0 must not veto
  /// the whole list. Rows without data fall back gracefully; the grid needs
  /// one tile height for everything either way.
  bool get _epgRowsActive {
    if (_showsPosterRows) return false;
    final channels = _catalogState.filteredChannels;
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





  // The URL the preview stage actually plays. For M3U/Xtream channels this is
  // just the channel URL; for Stremio-addon channels it is the current rung of
  // the candidate ladder (resolved async on focus, advanced by
  // [_onPreviewPlaybackFailed] until one plays or the list runs out). Null =
  // nothing to play, the stage shows only its static floor.





  // Keyed by channel INSTANCE rather than list position (focus survives
  // category/search filtering, which reuses the same objects) — and rather
  // than URL: playlists routinely list one stream URL under several names,
  // and a URL key would hand those rows a single shared FocusNode, lighting
  // them all up together and scrambling DPAD traversal around the pair.
  // Instances are stable for a playlist's whole life (progressive Stremio
  // batches append to one list; filters select from it), and the map is
  // rebuilt with the instances on every _loadPlaylist.




  void _onRowDetached(IptvChannel channel) {
    _focusState.detachedRows.add(channel);
  }

  FocusNode _focusNodeFor(IptvChannel channel) {
    // Being asked for the node means the row is being (re)built right now.
    _focusState.detachedRows.remove(channel);
    return _focusState.cardFocusNodes.putIfAbsent(
      channel,
      () => FocusNode(debugLabel: 'iptv-card-${channel.name}-${channel.url}'),
    );
  }

  /// Whether [channel]'s row is currently built (its node attached). Nodes
  /// with no map entry count as detached.
  bool _rowAttached(IptvChannel channel) =>
      _focusState.cardFocusNodes.containsKey(channel) && !_focusState.detachedRows.contains(channel);











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
    setState(() => _selectionState.scheduleChannel = channel);
  }

  void _closeSchedulePane() {
    final channel = _selectionState.scheduleChannel;
    if (channel == null) return;
    setState(() => _selectionState.scheduleChannel = null);
    if (!widget.isTelevision &&
        _selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.classic) {
      return;
    }
    // Hand focus back to the row that opened the schedule. Post-frame: the
    // grid (and the cached node's row) only exists again after this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic &&
          _focusState.spotlightTimelineController.restoreFocus()) {
        return;
      }
      final node = _focusState.cardFocusNodes[channel];
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
    StremioService.instance.addAddonsChangedListener(_settingsLoading.onStremioAddonsChanged);
    IptvChannelOrderSignal.revision.addListener(_onChannelOrderChanged);
    IptvCatalogRefreshService.instance.revision.addListener(
      _catalogRefresh.onCatalogRefreshed,
    );
    // Chained, not fire-and-forget: the startup launch needs the playlist list
    // to exist before it can pick the target's provider.
    // Guarded on the error too, not just mounted: _loadSettings now SWALLOWS
    // its failures (it renders them instead), so this callback runs on a path
    // that used to skip it entirely. _maybeRunStartupLaunch consumes the
    // one-shot startup payload, and burning it against an empty playlist set
    // would cancel a boot-to-channel request that Retry could still honour.
    _settingsLoading.loadSettings().then((_) {
      if (mounted && _settingsState.settingsError == null) {
        unawaited(_maybeRunStartupLaunch());
      }
    });
    _favorites.loadFavorites();
    // Stage cockpit: recording availability + the rail's Scheduled badge.
    // Off the critical path; only ever ENABLES affordances.
    unawaited(_initRecordingSupport());
    if (!kIsWeb && Platform.isIOS) {
      unawaited(
        DevicePreferences.instance().then((prefs) {
          if (!mounted) return;
          if (!(prefs.getBool(IptvSettingsState.iosNoticeDismissedPref) ?? false)) {
            setState(() => _settingsState.showIosRecordingNotice = true);
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



  void _onChannelOrderChanged() {
    final playlist = _settingsState.selectedPlaylist;
    final change = IptvChannelOrderSignal.latest;
    if (!mounted || playlist == null || change == null) return;
    final affected = switch (change.scope) {
      IptvChannelOrderScope.list =>
        (playlist.isFavorites &&
                change.target == IptvFavoritesStorage.iptvFavoritesListId) ||
            playlist.customListId == change.target,
      IptvChannelOrderScope.source =>
        change.target.isEmpty || playlist.id == change.target,
      IptvChannelOrderScope.catalog =>
        change.target.isEmpty ||
            IptvCatalogKey.forCategoryOrder(playlist, _catalogState.selectedContentType) ==
                change.target,
    };
    if (affected) unawaited(_catalogLoading.loadPlaylist(playlist));
  }





  IptvPlaylist? _recordingResourceFor(IptvChannel channel) {
    final originId = _favorites.originPlaylistIdFor(channel);
    if (originId == null) return null;
    for (final playlist in _settingsState.playlists) {
      if (playlist.id == originId && playlist.connectionResourceId != null) {
        return playlist;
      }
    }
    return null;
  }















  @override
  void didUpdateWidget(IptvResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Search filter when query changes. Debounced: the field live-filters on
    // every keystroke, and re-scanning a 10k-channel playlist per keypress is
    // what made typing janky. Clearing applies immediately so backing out of
    // a search feels instant.
    if (widget.searchQuery != _selectionState.lastSearchQuery) {
      _selectionState.lastSearchQuery = widget.searchQuery;
      _selectionState.searchDebounce?.cancel();
      if (widget.searchQuery.isEmpty) {
        _applyFilters();
      } else {
        _selectionState.searchDebounce = Timer(const Duration(milliseconds: 220), () {
          if (mounted) _applyFilters();
        });
      }
    }
  }



  @override
  void dispose() {
    IptvCatalogRefreshService.instance.revision.removeListener(
      _catalogRefresh.onCatalogRefreshed,
    );
    _recordingState.sourceCountsDebounce?.cancel();
    _recordingState.androidRecStateDebounce?.cancel();
    LiveRecordingService.schedulesRevision.removeListener(_onSchedulesChanged);
    DesktopRecordingService.instance.revision.removeListener(
      _onDesktopRecordingChanged,
    );
    if (widget.isTelevision) {
      WidgetsBinding.instance.removeObserver(this);
      MainPageBridge.removeTvSidebarFocusListener(_onTvSidebarFocusChanged);
    }
    StremioService.instance.removeAddonsChangedListener(
      _settingsLoading.onStremioAddonsChanged,
    );
    IptvChannelOrderSignal.revision.removeListener(_onChannelOrderChanged);
    _selectionState.searchDebounce?.cancel();
    _selectionState.contentTypeDebounce?.cancel();
    _statusState.loadTicker?.cancel();
    _statusState.maintenanceChipTimer?.cancel();
    _statusState.chipShowTimer?.cancel();
    _statusState.chipHideTimer?.cancel();
    _focusState.scrollController.dispose();
    _focusState.playlistFilterFocusNode.dispose();
    _focusState.categoryFilterFocusNode.dispose();
    _focusState.contentTypeFocusNode.dispose();
    _focusState.spotlightCategoryOptionsFocusNode.dispose();
    _focusState.spotlightPrimaryFocusNode.dispose();
    _focusState.spotlightRailScope.dispose();
    _focusState.spotlightHeroScope.dispose();
    _previewState.previewShown.dispose();
    _previewState.spotlightProgrammeShown.dispose();
    _previewState.previewShowing.dispose();
    _previewState.previewEpoch.dispose();
    _previewState.previewStreamUrl.dispose();
    for (final node in _focusState.cardFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
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
  ) => IptvCategoryOrder.applyStoredLocalCategoryOrder(playlistId, categories);





















































  @visibleForTesting
  static String formatLoadBytes(int bytes) => IptvLoadStatusPolicy.formatLoadBytes(bytes);

  @visibleForTesting
  static String formatLoadElapsed(Duration d) => IptvLoadStatusPolicy.formatLoadElapsed(d);

  /// "12.4 / 50.0 MB" when the transfer is observable, "42.1 MB" when only the
  /// landed size is known, null when there is no honest number to show — a
  /// buffered fetch that has not landed yet must not imply progress it cannot
  /// measure.
  @visibleForTesting
  static String? loadBytesLabel(int? bytes, int? totalBytes) => IptvLoadStatusPolicy.loadBytesLabel(bytes, totalBytes);



  /// Whether a stage owning [incoming] may take the chip from [current].
  /// Pure, so the priority rule is testable without pumping the page.
  @visibleForTesting
  static bool chipClaimAllowed(int current, int incoming) => IptvLoadStatusPolicy.chipClaimAllowed(current, incoming);

  /// Priority ranks, exposed for the same reason.
  @visibleForTesting
  static int get chipRankNone => IptvLoadStatusPolicy.chipRankNone;
  @visibleForTesting
  static int get chipRankGuide => IptvLoadStatusPolicy.chipRankGuide;
  @visibleForTesting
  static int get chipRankMaintenance => IptvLoadStatusPolicy.chipRankMaintenance;
  @visibleForTesting
  static int get chipRankRefresh => IptvLoadStatusPolicy.chipRankRefresh;







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
  /// - Favorites/custom lists: one guide context per originating provider.
  /// - Everything else (Stremio/continue): no guide context.
  void _updateEpgContext(
    IptvPlaylist playlist,
    IptvParseResult result,
    int ticket, {
    // Suppress the user-facing failure hints (background revalidate re-runs
    // already had them surfaced by the foreground pass this visit).
    bool quiet = false,
  }) {
    final service = IptvEpgService.instance;
    _statusState.lastGuideMb = -1;
    if (playlist.isFavorites || playlist.isCustomList) {
      _statusChip.hideChipIfOwned(ChipOwner.guide);
      unawaited(
        Zone.root.run(() => service.setListEpgContext(
          channels: result.channels,
          playlists: _settingsState.playlists,
          isCurrent: () => mounted && ticket == _catalogState.loadTicket,
        )),
      );
      return;
    }
    final isPlainM3u = !playlist.isVirtual && !playlist.isXtreamCodes;
    final isXtreamLive =
        playlist.isXtreamCodes && _catalogState.selectedContentType == 'live';
    if (!isPlainM3u && !isXtreamLive) {
      service.clearM3uEpgContext();
      _statusChip.hideChipIfOwned(ChipOwner.guide);
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
            dbCatalogKey: _catalogState.dbSnapshot?.catalogKey,
            onPhase: (phase, {bytes, totalBytes}) =>
                _statusChip.onGuidePhase(ticket, bytes, totalBytes),
          ),
        )
        .then((status) {
          // The guide is done one way or another — drop its chip if it is
          // still the one speaking.
          _statusChip.hideChipIfOwned(ChipOwner.guide);
          if (!mounted || ticket != _catalogState.loadTicket) return;
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
          _statusChip.hideChipIfOwned(ChipOwner.guide);
          if (!mounted || ticket != _catalogState.loadTicket) return;
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
    if (!mounted || ticket != _catalogState.loadTicket) return;
    final now = DateTime.now();
    final last = _catalogState.lastProgressiveApply;
    final firstBatch = !_catalogState.isLoadingMore;
    if (!firstBatch &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 300)) {
      return;
    }
    final wasFirstBatch = firstBatch;
    _catalogState.lastProgressiveApply = now;
    _loadStatus.endLoadStatus();
    setState(() {
      _catalogState.isLoading = false; // first batch swaps the spinner for real rows
      _catalogState.isLoadingMore = true;
      _catalogState.allChannels = channels;
      _catalogState.categories = categories;
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
    if (_catalogState.dbSnapshot != null) {
      final all = _catalogState.allChannels;
      final filtered = _catalogState.filteredChannels;
      final resident = <IptvChannel>[
        if (all is DbChannelList) ...all.residentChannels(),
        if (filtered is DbChannelList) ...filtered.residentChannels(),
      ];
      final urls = <String>{
        for (final channel in resident)
          if (!channel.isLive && channel.contentType != 'series') channel.url,
      };
      if (urls.isEmpty) return;
      final progress = await IptvHistoryStorage.getIptvProgressForUrls(urls);
      if (!mounted || ticket != _catalogState.loadTicket || progress.isEmpty) return;
      setState(() => _membershipState.progressByUrl = {..._membershipState.progressByUrl, ...progress});
      return;
    }

    final onDemand = [
      for (final channel in channels)
        // Series rows carry a sentinel (non-stream) URL — no position can
        // exist for it; their per-episode progress lives on the detail page.
        if (!channel.isLive && channel.contentType != 'series') channel.url,
    ];
    if (onDemand.isEmpty) {
      if (_membershipState.progressByUrl.isNotEmpty && mounted && ticket == _catalogState.loadTicket) {
        setState(() => _membershipState.progressByUrl = {});
      }
      return;
    }

    final progress = await IptvHistoryStorage.getIptvProgressForUrls(onDemand);
    if (!mounted || ticket != _catalogState.loadTicket) return;
    setState(() => _membershipState.progressByUrl = progress);
  }

  /// Build the virtual "Continue watching" playlist. Like Favorites, the rows
  /// are replayed from metadata captured at play time rather than re-fetched,
  /// so they survive a provider that has since renumbered or expired.
  Future<IptvParseResult> _buildContinueResult() async {
    final items = await IptvHistoryStorage.getIptvContinueWatching();
    _membershipState.continuePlaylistIds = {};
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
        _membershipState.continuePlaylistIds[sentinelUrl] = originId;
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
      _membershipState.continuePlaylistIds[itemUrl] = originId;
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
          httpHeaders: IptvFavoritesStorage.iptvFavoriteHeaders(item),
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
    final stored = await IptvFavoritesStorage.getIptvListChannels(listId);
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
            IptvMembershipState.kListOriginAttribute: meta['playlistId'] as String,
        },
        httpHeaders: IptvFavoritesStorage.iptvFavoriteHeaders(meta),
      );
    }).toList();
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()..sort();
    return IptvParseResult(channels: channels, categories: categories);
  }

  void _applyFilters() {
    _catalogState.spotlightViewGeneration++;
    // A programme cursor belongs to the outgoing projection. The timeline
    // will publish the reconciled row/programme after its next frame.
    _previewState.spotlightProgrammeShown.value = null;
    // DB-backed catalog: the filter IS the query — a new facade with the
    // category/search folded into its SQL. Same substring-over-name+group
    // semantics as searchChannels (the search_key column is the same
    // haystack IptvChannel.searchKey builds).
    final snap = _catalogState.dbSnapshot;
    if (snap != null) {
      setState(() {
        _catalogState.filteredChannels = _catalogFacades.makeDbList(
          snap,
          group: _effectiveCategory,
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
          for (final entry in _focusState.cardFocusNodes.entries)
            if (_focusState.detachedRows.contains(entry.key) && !entry.value.hasFocus)
              entry.key,
        ];
        for (final channel in orphans) {
          _focusState.detachedRows.remove(channel);
          _focusState.cardFocusNodes.remove(channel)?.dispose();
        }
      });
      return;
    }

    var channels = _catalogState.allChannels;

    // Filter by category
    if (_effectiveCategory != null) {
      channels = _settingsState.iptvService.filterByCategory(channels, _effectiveCategory);
    }

    // Filter by search query
    if (widget.searchQuery.isNotEmpty) {
      channels = _settingsState.iptvService.searchChannels(channels, widget.searchQuery);
    }

    setState(() {
      _catalogState.filteredChannels = channels;
    });
  }

  void _onPlaylistChanged(IptvPlaylist? playlist, {bool focusContent = false}) {
    if (playlist == null) return;
    if (playlist == _settingsState.selectedPlaylist) {
      // Re-picking the current source shouldn't reload, but from the rail it
      // still means "take me to the list" — collapse the rail and focus the
      // already-loaded content instead of a dead OK press.
      if (focusContent) {
        if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic) {
          _focusSpotlightContentEntry();
          return;
        }
        _focusState.focusContentAfterLoad = true;
        _consumeContentFocusRequest();
      }
      return;
    }

    // A pending content-type load belongs to the outgoing playlist.
    _selectionState.contentTypeDebounce?.cancel();
    // Honored by the present paths once the new list is on screen. Only the
    // rail/picker set it — a dropdown or programmatic switch keeps focus
    // where it was.
    _focusState.focusContentAfterLoad = focusContent;
    setState(() {
      _settingsState.selectedPlaylist = playlist;
      _catalogState.selectedCategory = null;
      if (playlist.isXtreamCodes) {
        _catalogState.selectedContentType = 'live';
      }
    });

    _catalogLoading.loadPlaylist(playlist);
  }

  /// Move DPAD focus into the content pane after a rail-initiated playlist
  /// switch, which collapses the source rail's overlay. Post-frame so the
  /// grid's first row (and its lazily-created focus node) exists; falls back
  /// to the in-pane filter row when the new catalog is empty or errored, so
  /// focus never strands on the collapsing rail.
  void _consumeContentFocusRequest() {
    if (!_focusState.focusContentAfterLoad) return;
    _focusState.focusContentAfterLoad = false;
    if (!widget.isTelevision &&
        _selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.classic) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_catalogState.filteredChannels.isNotEmpty) {
        if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic &&
            _focusState.spotlightTimelineController.focusFirstChannel()) {
          return;
        }
        _focusNodeFor(_catalogState.filteredChannels.first).requestFocus();
      } else if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic &&
          _focusState.categoryFilterFocusNode.canRequestFocus) {
        _focusState.categoryFilterFocusNode.requestFocus();
      } else {
        _focusState.playlistFilterFocusNode.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }



  void _onContentTypeChanged(String contentType) {
    if (contentType == _catalogState.selectedContentType) return;

    setState(() {
      _catalogState.selectedContentType = contentType;
      _catalogState.selectedCategory = null;
      // The outgoing type's rows leave NOW, not when the debounced load
      // lands: they'd otherwise render for the debounce window under the new
      // type's layout flag (_showsPosterRows flips immediately), and a tap in
      // that window would play an item of a type the filter no longer shows.
      // Mirrors the reset _loadPlaylist performs; the spinner covers the gap
      // exactly as it did when the load was synchronous.
      _catalogState.isLoading = true;
      // The spinner is up NOW but the load is 350ms away, so the status must
      // reset with it — otherwise this window renders the previous load's
      // phase and byte count against a stale start time, with the ticker
      // already stopped: frozen, wrong text rather than merely old.
      _loadStatus.beginLoadStatus();
      _catalogState.allChannels = [];
      _catalogState.filteredChannels = [];
      _catalogState.categories = [];
      _catalogState.dbSnapshot = null;
      _catalogState.dbGroupCounts = const {};
      _membershipState.progressByUrl = {};
      _selectionState.scheduleChannel = null;
    });
    _clearPreview();

    // Debounced: the classic layout's toggle CYCLES Live → Movies → Series,
    // so reaching a non-adjacent type means passing through one the user
    // never wanted — a full playlist load (focus-node disposal, possibly a
    // multi-second uncached panel fetch) per intermediate step. Let the
    // selection settle first; only the type the user stops on loads. Short
    // enough to be imperceptible on a single direct pick (the TV dropdown
    // path).
    _selectionState.contentTypeDebounce?.cancel();
    _selectionState.contentTypeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_settingsState.selectedPlaylist != null) {
        _catalogLoading.loadPlaylist(_settingsState.selectedPlaylist!);
      }
    });
  }

  void _onCategoryChanged(String? category) {
    _catalogState.categoryManuallyChosen = true;
    setState(() => _catalogState.selectedCategory = category);
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
  /// Only a load's FIRST present may seed ([landingSeedArmed]); the
  /// revalidate paths share these present functions and must never re-seed —
  /// the vanished-category resets (hidden, renamed, removed by the provider)
  /// keep their fall-back-to-All behavior, because re-seeding mid-browse
  /// would yank the view.
  String? _landingCategory(String? orderKey, List<String> categories) =>
      !_catalogState.landingSeedArmed
      ? null
      : landingCategoryFor(
          orderKey: orderKey,
          categories: categories,
          manuallyChosen: _catalogState.categoryManuallyChosen,
          searching: widget.searchQuery.isNotEmpty,
        );

  /// Pure decision behind [_landingCategory], split out for tests.
  @visibleForTesting
  static String? landingCategoryFor({
    required String? orderKey,
    required List<String> categories,
    required bool manuallyChosen,
    required bool searching,
  }) => IptvLandingPolicy.landingCategoryFor(orderKey: orderKey, categories: categories, manuallyChosen: manuallyChosen, searching: searching);

  /// Whether categories can be customized in the current view.
  ///
  /// Only catalog-backed sources (M3U / Xtream) qualify: the hidden set is
  /// keyed by catalog, and the virtual shelves (Favorites, custom lists,
  /// Continue watching), Stremio addons and imported files never get one —
  /// they stay materialized in memory. Everything downstream of this getter
  /// can assume [dbSnapshot] is non-null.
  bool get _canShowCategoryOptions => _catalogState.dbSnapshot != null;

  /// Hold-OK (TV) or long-press (touch) on a category: make it the source's
  /// default landing category, or hide it. Routed from the same gestures that
  /// used to jump straight to the hide confirmation; hide still confirms
  /// through [_promptHideCategory], so its wording and semantics are
  /// unchanged.
  Future<void> _promptCategoryOptions(String category) async {
    final app = AppThemeScope.of(context);
    final snap = _catalogState.dbSnapshot;
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
          _statusChip.showChip(
            CatalogChipState.success,
            'Opens on "$category" from now on',
            autoHide: const Duration(milliseconds: 2500),
          );
        } else {
          _statusChip.showChip(
            CatalogChipState.failure,
            'Couldn\'t save the default — try again',
            autoHide: const Duration(milliseconds: 3500),
          );
        }
      case 'clearDefault':
        if (IptvCatalogDb.setDefaultCategory(snap.catalogKey, null)) {
          _statusChip.showChip(
            CatalogChipState.success,
            'Default category cleared',
            autoHide: const Duration(milliseconds: 2500),
          );
        } else {
          _statusChip.showChip(
            CatalogChipState.failure,
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
    final snap = _catalogState.dbSnapshot;
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
      _statusChip.showChip(
        CatalogChipState.failure,
        'Couldn\'t hide "$category" — try again',
        autoHide: const Duration(milliseconds: 3500),
      );
      return;
    }
    await _refreshAfterHiddenChange();
    if (!mounted) return;
    _statusChip.showChip(
      CatalogChipState.success,
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
    final snap = _catalogState.dbSnapshot;
    if (snap == null) return;
    final ticket = _catalogState.loadTicket;
    final groups = await IptvCatalogDb.groupsAsync(snap);
    if (!mounted || ticket != _catalogState.loadTicket) return;
    final categories = _catalogPresentation.deriveCategories(snap, groups);
    setState(() {
      _catalogState.dbGroupCounts = {
        for (final g in groups)
          if (g.name != null && g.name!.isNotEmpty) g.name!: g.count,
      };
      _catalogState.categories = categories;
      _catalogState.allChannels = _catalogFacades.makeDbList(snap);
      // The selected category is the one most likely to have just been
      // hidden — fall back to All rather than leaving the filter pinned to
      // something the list no longer offers.
      if (_catalogState.selectedCategory != null &&
          !categories.contains(_catalogState.selectedCategory)) {
        _catalogState.selectedCategory = null;
      }
    });
    _applyFilters();
  }







  List<Map<String, dynamic>> _playerSourcePayload() => [
    for (final playlist in _settingsState.playlists)
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
  /// is already capped for size (see [kMaxPlayerChannels]).
  List<Map<String, dynamic>> _playerListsPayload() => [
    for (final list in _membershipState.lists)
      {'id': list.id, 'name': list.name, 'isBuiltin': list.isBuiltin},
  ];

  String _playerOriginPlaylistId(IptvChannel channel, IptvPlaylist source) {
    final seriesOrigin = channel.attributes['series_playlist_id'];
    if (seriesOrigin != null && seriesOrigin.isNotEmpty) {
      return seriesOrigin;
    }
    final listId = source.isFavorites
        ? IptvFavoritesStorage.iptvFavoritesListId
        : source.customListId;
    final shelfOrigin = (source.isFavorites || source.isCustomList)
        // Prefer the row's own origin (see [_kListOriginAttribute]); the map
        // is only a fallback for rows that predate it.
        ? (channel.attributes[IptvMembershipState.kListOriginAttribute]?.isNotEmpty ?? false)
              ? channel.attributes[IptvMembershipState.kListOriginAttribute]
              : (listId == null
                    ? null
                    : _membershipState.favoritePlaylistIds[(listId, channel.url)])
        : source.isContinueWatching
        ? _membershipState.continuePlaylistIds[channel.url]
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
    final favoriteUrls = await IptvFavoritesStorage.getIptvFavoriteChannelUrls();
    final resumePositions = await IptvHistoryStorage.getIptvResumePositions([
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
  /// Reuses [categories], which the view already maintains for its own chips
  /// (provider categories in order, else every distinct group) and refreshes on
  /// each catalog load — so the launch/browse path never re-runs a GROUP BY on
  /// the UI isolate. The snapshot/in-memory branches only cover the rare case
  /// where it hasn't been populated yet.
  List<String> _fullCategoryList() {
    if (_catalogState.categories.isNotEmpty) return _catalogState.categories;
    final snap = _catalogState.dbSnapshot;
    if (snap != null) {
      // Same hidden-category filtering [_deriveCategories] applies, so the
      // in-player picker can't offer a category the page doesn't. groups()
      // is already filtered in SQL; the provider list is not.
      if (snap.categories.isNotEmpty) {
        return IptvCatalogDb.applyCategoryOrder(
          snap.catalogKey,
          _catalogPresentation.withoutHidden(snap.catalogKey, snap.categories),
        );
      }
      return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, [
        for (final group in snap.groups())
          if (group.name?.isNotEmpty == true) group.name!,
      ]);
    }
    return <String>{
      for (final channel in _catalogState.allChannels)
        if (channel.group?.isNotEmpty == true) channel.group!,
    }.toList()..sort();
  }

  Future<Map<String, dynamic>?> _providePlayerIptvBrowse(
    Map<String, dynamic> request,
  ) async {
    if (!mounted) return null;
    final action = request['action'] as String? ?? 'browse';
    final query = (request['query'] as String? ?? '').trim();

    final sourceId = request['sourceId'] as String? ?? _settingsState.selectedPlaylist?.id;
    IptvPlaylist? source;
    for (final playlist in _settingsState.playlists) {
      if (playlist.id == sourceId) {
        source = playlist;
        break;
      }
    }
    source ??= _settingsState.selectedPlaylist;
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
        for (final playlist in _settingsState.playlists) {
          if (playlist.id == sentinelOriginId && playlist.isXtreamCodes) {
            episodeSource = playlist;
            break;
          }
        }
      }
      if (!episodeSource.isXtreamCodes) return null;
      if (episodeSource != _settingsState.selectedPlaylist ||
          _catalogState.selectedContentType != 'series') {
        setState(() {
          _settingsState.selectedPlaylist = episodeSource;
          _catalogState.selectedCategory = null;
          _catalogState.selectedContentType = 'series';
        });
        await _catalogLoading.loadPlaylist(episodeSource);
        if (!mounted) return null;
      }
      IptvChannel? series;
      for (final channel in _catalogState.allChannels) {
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
      _playerState.playerSeriesEpisodes = episodes;
      _playerState.playerSeriesEpisodeSourceId = episodeSource.id;
      _playerState.playerSeriesTitle = series.name;
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
        (source.isXtreamCodes ? _catalogState.selectedContentType : 'live');
    if (requestedType == 'episodes') {
      final cached = source.id == _playerState.playerSeriesEpisodeSourceId
          ? _playerState.playerSeriesEpisodes
          : const <IptvChannel>[];
      final terms = query.toLowerCase().split(RegExp(r'\s+'));
      final episodes = cached
          .where(
            (channel) =>
                query.isEmpty || terms.every(channel.searchKey.contains),
          )
          .take(IptvPlayerState.kMaxPlayerChannels)
          .toList();
      return {
        'sourceId': source.id,
        'sourceName': source.name,
        'contentType': 'episodes',
        'title': _playerState.playerSeriesTitle ?? 'Episodes',
        'categories': const <String>[],
        'sources': _playerSourcePayload(),
        'channels': await _playerChannelPayload([
          for (final episode in episodes) (channel: episode, source: source),
        ]),
      };
    }
    final needsLoad =
        source != _settingsState.selectedPlaylist ||
        (source.isXtreamCodes && requestedType != _catalogState.selectedContentType);
    if (needsLoad) {
      setState(() {
        _settingsState.selectedPlaylist = source;
        _catalogState.selectedCategory = null;
        if (source!.isXtreamCodes &&
            const {'live', 'vod', 'series'}.contains(requestedType)) {
          _catalogState.selectedContentType = requestedType;
        }
      });
      await _catalogLoading.loadPlaylist(source);
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
        ? (requestedLimit ?? IptvPlayerState.kPlayerZapPageSize).clamp(1, IptvPlayerState.kMaxPlayerChannels)
        : IptvPlayerState.kMaxPlayerChannels;
    var pageOffset = isPagedRequest
        ? ((request['offset'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30)
        : 0;
    final anchorUrl = (request['anchorUrl'] as String?)?.trim();
    final anchorName = (request['anchorName'] as String?)?.trim();
    final fromEnd = request['fromEnd'] == true;
    List<IptvChannel> channels;
    var totalChannels = 0;
    int? anchorIndex;
    final snap = _catalogState.dbSnapshot;
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
      Iterable<IptvChannel> filtered = _catalogState.allChannels;
      IptvChannel? jumpChannel;
      if (isJump) {
        for (final channel in _catalogState.allChannels) {
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
        channels = filtered.take(IptvPlayerState.kMaxPlayerChannels).toList();
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



  Future<void> _playChannel(
    IptvChannel channel, {
    bool Function()? shouldCancel,
  }) async {
    if (_playerState.launchingChannel) return;
    _playerState.launchingChannel = true;
    try {
      await _playChannelInner(channel, shouldCancel: shouldCancel);
    } finally {
      _playerState.launchingChannel = false;
    }
  }

  // ==========================================================================
  // Startup channel — boot straight into a live channel
  //
  // Runs against the MOUNTED page rather than as a headless launcher: the
  // player's launch payload includes `iptvBrowseProvider`, a closure into this
  // state, and without it a launched channel plays but cannot zap.
  // ==========================================================================



  void _cancelStartupLaunch() {
    _playerState.startupAttempt++;
    if (_playerState.startupLaunchActive) {
      _playerState.startupLaunchActive = false;
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
        payload[StartupIptvStorage.startupIptvFirstAvailable] == true;
    final url = payload['url'];
    final name = payload['name'];
    if (!firstAvailable && (url is! String || url.isEmpty || name is! String)) {
      MainPageBridge.cancelIptvStartupChannel();
      return;
    }

    final attempt = ++_playerState.startupAttempt;
    // The epoch, not just the local attempt: cancellation can land in the gap
    // between consuming the payload and registering the callback below, and
    // would then find nothing to call. The epoch records it regardless.
    final epoch = MainPageBridge.iptvStartupEpoch;
    bool cancelled() =>
        attempt != _playerState.startupAttempt ||
        epoch != MainPageBridge.iptvStartupEpoch ||
        !mounted;
    if (cancelled()) return;
    _playerState.startupLaunchActive = true;
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
      final parked = _previewState.previewRearmPending;
      if (attempt == _playerState.startupAttempt && !parked) {
        _playerState.startupLaunchActive = false;
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
  /// so a foreign instance fails `contains`, falls through to `allChannels`,
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
    if (payload[StartupIptvStorage.startupIptvFirstAvailable] == true) {
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
    if (_settingsState.selectedPlaylist?.id != target.id) {
      _onPlaylistChanged(target);
    }

    final deadline = DateTime.now().add(IptvPlayerState.startupResolveDeadline);

    // 2. Do not read the catalog until the OUTGOING one is gone. `_loadPlaylist`
    //    sets its in-flight ticket synchronously, but `_loadPlaylistInner`
    //    clears `_allChannels`/`_dbSnapshot` only after its first awaits — so
    //    for a window the previous provider's rows are still sitting there, and
    //    matching against them would resolve a channel from the wrong account.
    var ready = false;
    while (!ready && !cancelled() && DateTime.now().isBefore(deadline)) {
      if (_catalogState.inFlightLoadTicket == null) {
        ready = true; // load finished (or a cached catalog was already present)
      } else if (_catalogState.allChannels.isEmpty && _catalogState.dbSnapshot == null) {
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
      if (_settingsState.selectedPlaylist?.id != target.id) return null;
      final snap = _catalogState.dbSnapshot;
      if (snap != null) {
        final entry =
            snap.entryForUrl(url: url, name: name) ??
            (channelNumber != null
                ? snap.entryForChannelNumber(channelNumber)
                : null);
        if (entry != null) {
          return _residentDbRow(entry, url, name, channelNumber);
        }
      } else if (_catalogState.allChannels.isNotEmpty) {
        final match = _materializedStartupMatch(url, name, channelNumber);
        if (match != null) return _adoptStartupCategory(match);
        // A finished load that still doesn't hold the channel is a real miss;
        // an in-flight one may still deliver it.
        if (_catalogState.inFlightLoadTicket == null) return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  /// First live row of whatever the page is currently showing.
  ///
  /// Rows come straight off `filteredChannels`, so they are the facade's own
  /// resident instances — the identity `_playChannelInner` needs — and no
  /// category is adopted, because the landing view is exactly what we want.
  ///
  /// The walk is capped: a VOD-heavy catalog could otherwise page thousands of
  /// rows looking for a live one, and if the first few hundred hold none, the
  /// honest answer is "nothing to start on" rather than a long stall.
  Future<IptvChannel?> _resolveFirstAvailableRow(
    bool Function() cancelled,
  ) async {
    final deadline = DateTime.now().add(IptvPlayerState.startupResolveDeadline);
    while (!cancelled() && DateTime.now().isBefore(deadline)) {
      final channels = _catalogState.filteredChannels;
      if (channels.isNotEmpty) {
        final limit = channels.length < 300 ? channels.length : 300;
        for (var i = 0; i < limit; i++) {
          final channel = channels[i];
          if (channel.isLive) return channel;
        }
        // A finished load with no live row in reach is a real answer; an
        // in-flight one (progressive Stremio) may still deliver.
        if (_catalogState.inFlightLoadTicket == null) return null;
      } else if (_catalogState.inFlightLoadTicket == null && _settingsState.settingsLoaded) {
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
    final snap = _catalogState.dbSnapshot;
    final list = _catalogState.filteredChannels;
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
    for (final channel in _catalogState.allChannels) {
      if (channel.url == url && channel.name == name && channel.isLive) {
        return channel;
      }
    }
    if (storedNumber == null) return null;
    for (final channel in _catalogState.allChannels) {
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
    return _catalogState.filteredChannels.contains(channel) ? channel : null;
  }

  /// Make the target's own group the active category. Without this the landing
  /// category can simply exclude the target, and no amount of correct counting
  /// inside it will ever materialize the row.
  Future<void> _adoptStartupCategoryValue(String? group) async {
    if (_catalogState.selectedCategory != group) {
      setState(() => _catalogState.selectedCategory = group);
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
      for (final playlist in _settingsState.playlists) {
        if (playlist.id == playlistId) return playlist;
      }
    }
    final serverUrl = payload['serverUrl'];
    final username = payload['username'];
    if (serverUrl is String && serverUrl.isNotEmpty && username is String) {
      for (final playlist in _settingsState.playlists) {
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
    final index = _catalogState.filteredChannels is DbChannelList
        ? (_catalogState.filteredChannels as DbChannelList).indexOfInstance(row)
        : _catalogState.filteredChannels.indexOf(row);
    if (index == null || index < 0) return;
    // Spotlight has one logical cursor instead of per-row FocusNodes. Hand it
    // the resolved index directly so a startup target outside the first
    // viewport becomes the hero selection and the BACK landing before the
    // player opens. Retry for a few frames if layout just mounted the timeline.
    if (_spotlightRequestedForDevice && _spotlightUsesTimeline) {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (_focusState.spotlightTimelineController.focusChannelAt(index)) {
          widget.debugOnSpotlightStartupFocus?.call(index);
          return;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    }
    // The touch-tablet two-pane renders IptvCenteredSelector, which owns its
    // OWN controller — `_scrollController` drives the grid only, so scrolling it
    // here would be a no-op. Hand the selector the index through the selection
    // it already reconciles against instead.
    if (_selectionState.touchTabletTwoPaneActive) {
      setState(() => _selectTabletChannel(index, row));
      return;
    }
    if (_focusState.scrollController.hasClients) {
      final target = (index ~/ _selectionState.gridColumns).toDouble() * (_selectionState.gridRowExtent + 4);
      final position = _focusState.scrollController.position;
      if (position.hasContentDimensions) {
        _focusState.scrollController.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
    }
    // The row has to build before it has a focus node to give focus to, and on
    // a slow TV that can take more than the next frame.
    for (var attempt = 0; attempt < 5; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final node = _focusState.cardFocusNodes[row];
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
    if (_playerState.launchingChannel) return;
    _playerState.launchingChannel = true;
    try {
      // Everything origin-dependent is captured BEFORE the first await: the
      // first-use dialect probe can run for tens of seconds, and the user
      // can switch playlists meanwhile — the widget stays mounted, so
      // `mounted` guards don't cover it. Recording with the switched-to
      // playlist's id would break the provider-deletion sweep (deleting B
      // would purge A's replay; deleting A would strand the entry).
      final originPlaylistId = _favorites.originPlaylistIdFor(channel);
      final ticket = _catalogState.loadTicket;
      final replayFromInPlaceSchedule = _selectionState.scheduleChannel?.url == channel.url;
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
      if (ticket != _catalogState.loadTicket) return;
      if (replayFromInPlaceSchedule && _selectionState.scheduleChannel?.url != channel.url) {
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
      await IptvHistoryStorage.recordIptvWatch(
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
      if (mounted && (widget.isTelevision || _selectionState.tvTwoPaneActive)) {
        _previewState.previewRearmPending = true;
      }
      if (!widget.isTelevision && mounted) {
        if (_selectionState.touchTabletTwoPaneActive) {
          _flushPreviewRearm();
        } else {
          await _refreshAfterPlayback();
        }
      }
    } finally {
      _playerState.launchingChannel = false;
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
      await IptvHistoryStorage.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: _favorites.originPlaylistIdFor(channel),
        httpHeaders: channel.httpHeaders,
      );
    }

    // The in-player guide mirrors what the user was browsing: the current
    // category/search filter, not the whole playlist. (Also what keeps the
    // launch payload small when a filter is active.)
    var channels = _catalogState.filteredChannels.contains(channel)
        ? _catalogState.filteredChannels
        : _catalogState.allChannels;
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
      final lo = total > IptvPlayerState.kMaxPlayerChannels
          ? (channelIndex - IptvPlayerState.kMaxPlayerChannels ~/ 2).clamp(
              0,
              total - IptvPlayerState.kMaxPlayerChannels,
            )
          : 0;
      channels = source.effectiveSnapshot.page(
        offset: lo,
        limit: IptvPlayerState.kMaxPlayerChannels,
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
    } else if (channels.length > IptvPlayerState.kMaxPlayerChannels) {
      final lo = (channelIndex - IptvPlayerState.kMaxPlayerChannels ~/ 2).clamp(
        0,
        channels.length - IptvPlayerState.kMaxPlayerChannels,
      );
      channels = channels.sublist(lo, lo + IptvPlayerState.kMaxPlayerChannels);
      channelIndex -= lo;
    }
    final launchSource = _settingsState.selectedPlaylist;
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
        iptvSourceId: _settingsState.selectedPlaylist?.id,
        iptvSourceName: _settingsState.selectedPlaylist?.name,
        iptvSelectedCategory: _effectiveCategory,
        iptvContentType: _settingsState.selectedPlaylist?.isXtreamCodes == true
            ? _catalogState.selectedContentType
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
    if (mounted && (widget.isTelevision || _selectionState.tvTwoPaneActive)) {
      _previewState.previewRearmPending = true;
    }
    // Off TV, push() is awaited to the pop — the position just written is
    // already on disk, so refresh now. On TV push() can return while the
    // native player is still starting, and rebuilding the list under a
    // launching player is the worst possible moment for it; the parked
    // re-arm below is the designated "we're back" hook and refreshes there.
    if (!widget.isTelevision) {
      if (_selectionState.touchTabletTwoPaneActive) {
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
    var playlist = _settingsState.selectedPlaylist;
    if (playlist == null) return;
    // Reached from a virtual shelf (Continue watching): the selected playlist
    // is the shelf itself, not the provider — resolve the series' real Xtream
    // provider from the origin id stored per row.
    if (!playlist.isXtreamCodes) {
      final originId = _favorites.originPlaylistIdFor(channel);
      IptvPlaylist? origin;
      for (final p in _settingsState.playlists) {
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

  /// Offer resume/removal for movies, series and catch-up on the CW shelf.
  Future<void> _showContinueWatchingActions(IptvChannel channel) async {
    // Capture the provider before opening a dialog: series IDs are only
    // unique within their provider, and the selected shelf can change.
    final playlistId = _favorites.originPlaylistIdFor(channel) ?? '';
    final seriesId = channel.attributes['series_id'] ?? '';
    final isSeries = channel.contentType == 'series';
    final action = await showCwCardMenu(
      context,
      title: channel.name,
      posterUrl: channel.logoUrl,
      isTelevision: widget.isTelevision,
      playLabel: isSeries ? 'Open series' : 'Resume',
      playDescription: isSeries ? 'Choose an episode' : 'Continue playback',
      removeDescription: isSeries
          ? 'Clear saved progress for all episodes of this series.'
          : 'Clear saved progress for this item.',
    );
    if (!mounted || action == null) return;
    if (action == CwCardAction.play) {
      await _playChannel(channel);
      return;
    }
    try {
      if (isSeries) {
        if (seriesId.isEmpty) return;
        await IptvHistoryStorage.removeIptvContinueWatchingSeries(
          playlistId: playlistId,
          seriesId: seriesId,
        );
      } else {
        await IptvHistoryStorage.removeIptvContinueWatchingItem(channel.url);
      }
      if (!mounted) return;
      await _refreshAfterPlayback();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removed from Continue Watching')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove item. Please try again.')),
      );
    }
  }

  /// Refresh progress and shelf membership without resetting source selection.
  Future<void> _refreshAfterPlayback() async {
    if (!mounted) return;
    // Read the shelf ONCE and reuse it below. Each read decodes both the
    // watch-history map and the (potentially large) shared resume map off the
    // UI isolate, and this runs at the exact moment the user lands back on
    // the list — the worst time to do it three times over.
    final items = await IptvHistoryStorage.getIptvContinueWatching();
    if (!mounted) return;
    // A recording may have been started (or stopped) from inside the player —
    // the header's record-dot must not lag until the next resume.
    _armAndroidRecStateRefresh();
    await _favorites.loadFavorites();
    if (!mounted) return;
    _refreshContinueShelfPresence(items.length);
    if (!mounted) return;

    // A list shelf can have changed under the user while the player was up —
    // both players can add and remove memberships from their own guide. This
    // covers Favorites AND custom lists; without the custom-list arm a
    // channel removed in the native guide stays on screen until a full
    // reload of the page.
    final shelf = _settingsState.selectedPlaylist;
    final shelfListId = (shelf?.isFavorites ?? false)
        ? IptvFavoritesStorage.iptvFavoritesListId
        : shelf?.customListId;
    if (shelfListId != null) {
      final stored = {
        for (final entry in _membershipState.membership.entries)
          if (entry.value.contains(shelfListId)) entry.key,
      };
      final current = {for (final channel in _catalogState.allChannels) channel.url};
      if (!setEquals(stored, current)) {
        await _catalogLoading.loadPlaylist(shelf!);
        return;
      }
    }

    // The shelf can empty out from under the user — they just finished its
    // last item. Leaving it selected strands the picker: with no matching
    // option the dropdown renders the FIRST option's label instead, so it
    // would read "Favorites" above an empty shelf.
    if (items.isEmpty && (_settingsState.selectedPlaylist?.isContinueWatching ?? false)) {
      final remaining = [
        for (final p in _settingsState.playlists)
          if (!p.isContinueWatching) p,
      ];
      if (remaining.isNotEmpty) {
        _onPlaylistChanged(remaining.first);
        return;
      }
    }

    if (_settingsState.selectedPlaylist?.isContinueWatching ?? false) {
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
      final current = {for (final channel in _catalogState.allChannels) channel.url};
      if (!setEquals(fresh, current)) {
        await _catalogLoading.loadPlaylist(IptvMembershipState.continuePlaylist);
        return;
      }
    }
    await _loadProgress(_catalogState.loadTicket, _catalogState.allChannels);
  }

  /// Add or drop the Continue-watching entry in the picker to match whether
  /// anything is actually half-watched — so the shelf appears after the very
  /// first movie rather than on the next visit to the page, and disappears
  /// once the last item is finished. Selection is left untouched.
  void _refreshContinueShelfPresence(int itemCount) {
    final hasContinue = itemCount > 0;
    final present = _settingsState.playlists.any((p) => p.isContinueWatching);
    if (hasContinue == present && itemCount == _recordingState.continueWatchingCount) return;

    setState(() {
      _recordingState.continueWatchingCount = itemCount;
      if (hasContinue == present) return;
      if (hasContinue) {
        // Directly after Favorites, or first when there is no Favorites row.
        final favoritesIndex = _settingsState.playlists.indexWhere((p) => p.isFavorites);
        _settingsState.playlists = [..._settingsState.playlists]
          ..insert(favoritesIndex + 1, IptvMembershipState.continuePlaylist);
      } else {
        _settingsState.playlists = [
          for (final p in _settingsState.playlists)
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
    final desired = [for (final list in _favorites.customLists) IptvFavorites.listPlaylist(list)];
    final current = [
      for (final p in _settingsState.playlists)
        if (p.isCustomList) p,
    ];
    // Compare names too, not just ids — a rename has to reach the picker.
    String signature(List<IptvPlaylist> entries) =>
        entries.map((p) => '${p.id}\x00${p.name}').join('\x01');
    if (signature(desired) == signature(current)) return;

    // Rebuild in canonical order: Favorites, Continue, lists, real providers.
    final keptVirtuals = [
      for (final p in _settingsState.playlists)
        if (p.isFavorites || p.isContinueWatching) p,
    ];
    final realPlaylists = [
      for (final p in _settingsState.playlists)
        if (!p.isFavorites && !p.isContinueWatching && !p.isCustomList) p,
    ];
    setState(() {
      _settingsState.playlists = [...keptVirtuals, ...desired, ...realPlaylists];
    });

    // The list being viewed can have just been deleted. Leaving it selected
    // strands the picker: with no matching option the dropdown renders the
    // FIRST option's label, so it would read "Favorites" above the wrong grid.
    final selected = _settingsState.selectedPlaylist;
    if (selected != null && !_settingsState.playlists.any((p) => p.id == selected.id)) {
      final fallback = _settingsState.playlists.isEmpty ? null : _settingsState.playlists.first;
      if (fallback != null) _onPlaylistChanged(fallback);
    }
  }



  /// Complete a parked preview re-arm (see [_playChannel]).
  void _flushPreviewRearm() {
    if (!_previewState.previewRearmPending || !mounted) return;
    _previewState.previewRearmPending = false;
    // The startup launch parks its preview suppression here too — this is the
    // designated "we're actually back" hook, and the stage must not remount
    // while the player it launched is still coming up.
    _playerState.startupLaunchActive = false;
    _previewState.previewEpoch.value++;
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
    if (focused) {
      _setSpotlightSourcesExpanded(false);
      _clearPreview();
    }
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
    if (can != _recordingState.pageCanRecord) setState(() => _recordingState.pageCanRecord = can);
    unawaited(_refreshScheduledCount());
    unawaited(_refreshAndroidRecordingState());
  }



  /// Re-read the rail's per-source counts from the catalog. Debounced: a
  /// refresh sweep across several sources lands as ONE recompute, and the
  /// reads themselves are a handful of indexed lookups.
  void _recomputeSourceCounts() {
    _recordingState.sourceCountsDebounce?.cancel();
    _recordingState.sourceCountsDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !IptvCatalogDb.isOpen) return;
      final counts = <String, int>{};
      for (final p in _settingsState.playlists) {
        if (p.isVirtual) continue;
        try {
          final stats = IptvSourceStatsLoader.read(p);
          if (stats.cached) counts[p.id] = stats.total;
        } catch (_) {}
      }
      if (!mapEquals(counts, _recordingState.sourceCounts)) {
        setState(() => _recordingState.sourceCounts = counts);
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
    if (mounted && count != _recordingState.scheduledCount) {
      setState(() => _recordingState.scheduledCount = count);
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
      _recordingState.androidRecordingsByUrl.isNotEmpty ||
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




  void _armAndroidRecStateRefresh() {
    if (kIsWeb || !Platform.isAndroid || !_recordingState.pageCanRecord) return;
    _recordingState.androidRecStateDebounce?.cancel();
    _recordingState.androidRecStateDebounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_refreshAndroidRecordingState());
    });
  }

  Future<void> _refreshAndroidRecordingState() async {
    if (kIsWeb || !Platform.isAndroid || !_recordingState.pageCanRecord) return;
    final recordings = await LiveRecordingService.query();
    if (!mounted) return;
    final fresh = <String, String>{
      for (final r in recordings)
        if (r.isRecording) r.url: r.taskId,
    };
    if (!mapEquals(fresh, _recordingState.androidRecordingsByUrl)) {
      setState(() {
        _recordingState.androidRecordingsByUrl
          ..clear()
          ..addAll(fresh);
      });
    }
  }

  /// The Android engine task recording [channel], if any (url or Xtream twin).
  String? _androidEngineTaskFor(IptvChannel channel) {
    final direct = _recordingState.androidRecordingsByUrl[channel.url];
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(channel.url);
    return twin != null ? _recordingState.androidRecordingsByUrl[twin] : null;
  }

  Future<void> _stageStopAndroidRecording(
    IptvChannel channel,
    String taskId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await LiveRecordingService.stop(taskId);
    if (!mounted) return;
    setState(() {
      _recordingState.androidRecordingsByUrl.removeWhere((_, id) => id == taskId);
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
        setState(() => _recordingState.androidRecordingsByUrl[recordUrl] = result.id!);
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
    if (!_recordingState.pageCanRecord ||
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

  void _navigateToSettings({bool openAddSource = true}) {
    // Captured for the EPG-URL-edit case below: _loadSettings only reloads
    // the playlist when the SELECTION changes, so an edit to the current
    // playlist's guide URL would otherwise sit inert until a manual playlist
    // switch — "EPG URL saved" with nothing happening.
    final beforeId = _settingsState.selectedPlaylist?.id;
    final beforeEpgUrl = _settingsState.selectedPlaylist?.epgUrl;
    // Settings owns the hidden-categories manager, so a trip through it can
    // reveal (or hide) a category behind this page's back. Captured here
    // because _loadSettings only reloads the catalog when the SELECTION
    // changes — otherwise the facades keep the row count and category list
    // they were built with while the category was hidden.
    final beforeHidden = _catalogState.hiddenCategories;
    final beforeCatalogKey = _catalogState.dbSnapshot?.catalogKey;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => IptvSettingsPage(openAddSource: openAddSource),
          ),
        )
        .then((_) async {
          // Reload settings when returning
          await _settingsLoading.loadSettings();
          if (!mounted) return;
          // Only for the SAME catalog: a settings trip that changed the
          // selection has already been re-presented from scratch, hidden set
          // included, and comparing across two catalogs' rules is meaningless.
          final snap = _catalogState.dbSnapshot;
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
          final current = _settingsState.selectedPlaylist;
          final result = _catalogState.lastLoadResult;
          if (current != null &&
              current.id == beforeId &&
              current.epgUrl != beforeEpgUrl &&
              result != null) {
            _updateEpgContext(current, result, _catalogState.loadTicket);
          }
        });
  }

  void _navigateToManageSources() {
    _navigateToSettings(openAddSource: false);
  }

  /// Focus the first filter (for DPAD navigation from search input)
  @override
  void focusFirstFilter() {
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      _focusSpotlightSources();
    } else {
      _focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  @override
  void focusSearchResults() {
    if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic) {
      _focusSpotlightSearchResults();
    } else {
      focusFirstFilter();
    }
  }

  /// Focus the first channel card (for DPAD navigation from filters)
  void _focusFirstChannel() {
    // Only focus if we have filtered channels
    if (_catalogState.filteredChannels.isNotEmpty) {
      if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic &&
          _focusState.spotlightTimelineController.focusFirstChannel()) {
        return;
      }
      _focusNodeFor(_catalogState.filteredChannels.first).requestFocus();
    }
  }

  /// Refresh playlists from storage (call after settings change)
  Future<void> refreshPlaylists() async {
    await _settingsLoading.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsState.settingsLoaded) {
      final settingsError = _settingsState.settingsError;
      if (settingsError == null) {
        return _withBrowseSearch(
          const Center(child: CircularProgressIndicator()),
        );
      }
      return _withBrowseSearch(
        Center(
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
                    setState(() => _settingsState.settingsError = null);
                    unawaited(_settingsLoading.loadSettings(forceReload: true));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Spotlight owns the full canvas because its search lives inside the
    // source rail. Legacy layouts mount search above their body, so their
    // breakpoints must be evaluated by the inner LayoutBuilder after that
    // header has taken its height.
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final outerSize = Size(
          outerConstraints.maxWidth,
          outerConstraints.maxHeight,
        );
        final spotlightRequested = _spotlightRequestedForDevice;
        final spotlightMode = spotlightRequested
            ? resolveIptvSpotlightLayout(outerSize)
            : IptvSpotlightLayoutMode.classic;
        if (spotlightMode != IptvSpotlightLayoutMode.classic) {
          return _buildLoadedLayout(
            outerConstraints,
            spotlightRequested: spotlightRequested,
            spotlightMode: spotlightMode,
          );
        }
        return _withBrowseSearch(
          LayoutBuilder(
            builder: (context, bodyConstraints) => _buildLoadedLayout(
              bodyConstraints,
              spotlightRequested: spotlightRequested,
              spotlightMode: IptvSpotlightLayoutMode.classic,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadedLayout(
    BoxConstraints constraints, {
    required bool spotlightRequested,
    required IptvSpotlightLayoutMode spotlightMode,
  }) {
    final availableSize = Size(constraints.maxWidth, constraints.maxHeight);
    final touchTablet = shouldUseTouchTabletTwoPane(
      isTelevision: widget.isTelevision,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      availableSize: availableSize,
    );
    final twoPaneEligible = widget.isTelevision || IptvSettingsState.isDesktop || touchTablet;
    final spotlightActive = spotlightMode != IptvSpotlightLayoutMode.classic;
    // Spotlight deliberately falls back to the useful single-pane page below
    // its minimum height. Do not route that saved preference into the old
    // two-pane cockpit with Spotlight colours.
    final spotlightFallback = spotlightRequested && !spotlightActive;
    final regularTwoPane =
        !spotlightFallback &&
        twoPaneEligible &&
        constraints.maxWidth >= 760 &&
        constraints.maxHeight >= 380;
    final twoPane = spotlightActive || regularTwoPane;
    final touchTwoPane = regularTwoPane && touchTablet && !spotlightActive;

    if (twoPane != _selectionState.tvTwoPaneActive ||
        touchTwoPane != _selectionState.touchTabletTwoPaneActive ||
        spotlightMode != _selectionState.spotlightLayoutMode) {
      // Never write state synchronously from the layout phase: playback and
      // schedule callbacks consult these flags. One post-frame of lag can only
      // occur while the window is actively changing size.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final wasTouchTablet = _selectionState.touchTabletTwoPaneActive;
        _selectionState.tvTwoPaneActive = twoPane;
        _selectionState.touchTabletTwoPaneActive = touchTwoPane;
        _selectionState.spotlightLayoutMode = spotlightMode;
        if (!twoPane && wasTouchTablet && _selectionState.scheduleChannel != null && mounted) {
          setState(() => _selectionState.scheduleChannel = null);
        }
      });
    }

    final Widget body = spotlightActive
        ? _buildSpotlight(constraints, spotlightMode)
        : !regularTwoPane
        ? _buildClassic()
        : _buildTvTwoPane(constraints, touchSelector: touchTablet);

    // The background-refresh chip floats over whichever layout is active.
    // Stack stays paint-neutral for the native preview underlay.
    final Widget page = _settingsState.showIosRecordingNotice
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
    setState(() => _settingsState.showIosRecordingNotice = false);
    unawaited(
      DevicePreferences.instance().then(
        (prefs) => prefs.setBool(IptvSettingsState.iosNoticeDismissedPref, true),
      ),
    );
  }

  /// Bottom-right status chip for background catalog refreshes. Pure
  /// display: no focusables, no hit-testing — DPAD and touch pass straight
  /// through. Snap show/hide, no tween (TV GPU rule).
  Widget _buildCatalogChip() {
    final app = AppThemeScope.of(context);
    if (_statusState.chipState == CatalogChipState.hidden) {
      return const SizedBox.shrink();
    }
    final Widget leading = switch (_statusState.chipState) {
      CatalogChipState.updating => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: app.seeAll.accent2,
        ),
      ),
      CatalogChipState.success => const Icon(
        Icons.check_circle_rounded,
        size: 15,
        color: Color(0xFF4ADE80),
      ),
      CatalogChipState.failure => const Icon(
        Icons.cloud_off_rounded,
        size: 15,
        color: Color(0xFFFBBF24),
      ),
      CatalogChipState.hidden => const SizedBox.shrink(),
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
                _statusState.chipMessage,
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

  // ── Spotlight Guide ───────────────────────────────────────────────────────

  Widget _buildSpotlight(
    BoxConstraints constraints,
    IptvSpotlightLayoutMode mode,
  ) {
    final selected = _settingsState.selectedPlaylist;
    return SpotlightShell(
      mode: mode,
      searchSlot: _buildSpotlightSearch(mode),
      sourcesWrapper: (child) => FocusScope(
        node: _focusState.spotlightRailScope,
        onFocusChange: (focused) {
          // Dialogs opened from the drawer temporarily own focus. Keep the
          // search available for their return instead of hiding its field.
          if (!focused && ModalRoute.of(context)?.isCurrent != false) {
            _setSpotlightSourcesExpanded(false);
          }
        },
        onKeyEvent: (_, event) {
          if (!widget.isTelevision &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (event is KeyDownEvent) _closeSpotlightSources();
            return KeyEventResult.handled;
          }

          // MainPage's automatic sidebar fallback deliberately excludes
          // nested scopes. This persistent rail must exit explicitly on TV.
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              widget.isTelevision &&
              MainPageBridge.focusTvSidebar != null) {
            if (event is KeyDownEvent) _exitSpotlightSourcesToApp();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
      railSlot: _buildSpotlightRail(
        collapsed:
            mode == IptvSpotlightLayoutMode.wide && !_selectionState.spotlightSourcesExpanded,
      ),
      categorySlot: _spotlightControlNavigation(
        SpotlightCategoryControl(
          dense: true,
          categoryLabel: _effectiveCategory ?? 'All channels',
          channelCount: _catalogState.filteredChannels.length,
          loading: _catalogState.isLoading,
          onPressed: _showSpotlightCategoryPicker,
          focusNode: _focusState.categoryFilterFocusNode,
          optionsFocusNode: _focusState.spotlightCategoryOptionsFocusNode,
          onOpenOptions: _canShowCategoryOptions && _effectiveCategory != null
              ? () => unawaited(_promptCategoryOptions(_catalogState.selectedCategory!))
              : null,
        ),
      ),
      contentTypeSlot: selected?.isXtreamCodes ?? false
          ? _spotlightControlNavigation(
              SpotlightContentTypeControl(
                dense: true,
                value: _catalogState.selectedContentType,
                onChanged: _onContentTypeChanged,
                firstItemFocusNode: _focusState.contentTypeFocusNode,
              ),
            )
          : null,
      heroSlot: FocusScope(
        node: _focusState.spotlightHeroScope,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final direction = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowUp => TraversalDirection.up,
            LogicalKeyboardKey.arrowDown => TraversalDirection.down,
            LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
            LogicalKeyboardKey.arrowRight => TraversalDirection.right,
            _ => null,
          };
          if (direction == null) return KeyEventResult.ignored;
          // Traverse all action rows before leaving the hero. Its scope
          // confines spatial traversal to these buttons, including Wrap rows.
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary.focusInDirection(direction)) {
            return KeyEventResult.handled;
          }
          switch (direction) {
            case TraversalDirection.down:
              _focusState.categoryFilterFocusNode.requestFocus();
            case TraversalDirection.up:
              _focusSpotlightSearchOrExit();
            case TraversalDirection.left:
              _focusSpotlightSources();
            case TraversalDirection.right:
              break;
          }
          return KeyEventResult.handled;
        },
        child: _buildSpotlightHero(mode),
      ),
      contentSlot: _buildSpotlightContent(mode),
      onOpenSources: _showSpotlightSources,
      sourcesExpanded: _selectionState.spotlightSourcesExpanded,
      onToggleSources: () {
        if (_selectionState.spotlightSourcesExpanded) {
          _closeSpotlightSources();
        } else {
          _focusSpotlightSources();
        }
      },
      onCloseSources: _closeSpotlightSources,
      onExitSourcesLeft: _exitSpotlightSourcesToApp,
      onOpenSearch: _openSpotlightSearch,
      compactSourceLabel: selected?.name ?? 'Sources',
      compactSourceCount: _spotlightSelectedSourceCount,
      compactSourceFocusNode: _focusState.playlistFilterFocusNode,
      onSourceDown: _focusSpotlightHero,
      railWidth: 244,
      padding: EdgeInsets.all(mode == IptvSpotlightLayoutMode.wide ? 10 : 8),
    );
  }

  void _setSpotlightSourcesExpanded(bool expanded) {
    if (!mounted || _selectionState.spotlightSourcesExpanded == expanded) return;
    setState(() => _selectionState.spotlightSourcesExpanded = expanded);
  }

  void _closeSpotlightSources() {
    _setSpotlightSourcesExpanded(false);
    _focusSpotlightContentEntry();
  }

  void _exitSpotlightSourcesToApp() {
    final focusSidebar = MainPageBridge.focusTvSidebar;
    if (!widget.isTelevision || focusSidebar == null) return;
    _setSpotlightSourcesExpanded(false);
    focusSidebar();
  }

  void _focusSpotlightSources() {
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      _setSpotlightSourcesExpanded(true);
      final remembered = _focusState.spotlightRailScope.focusedChild;
      // A search field hidden by the collapsed drawer cannot receive focus.
      // Enter on the first source instead of leaving focus on an empty scope.
      if (remembered != null &&
          remembered is! FocusScopeNode &&
          remembered.canRequestFocus) {
        _focusState.spotlightRailScope.requestFocus();
      } else {
        _focusState.playlistFilterFocusNode.requestFocus();
      }
    } else {
      _focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  void _focusSpotlightHero() {
    if (_focusState.spotlightPrimaryFocusNode.context != null) {
      _focusState.spotlightPrimaryFocusNode.requestFocus();
    } else {
      _focusState.categoryFilterFocusNode.requestFocus();
    }
  }

  Widget _spotlightControlNavigation(Widget child) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_focusState.spotlightPrimaryFocusNode.context != null) {
          _focusState.spotlightPrimaryFocusNode.requestFocus();
        } else {
          _focusSpotlightSearchOrExit();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_selectionState.scheduleChannel == null &&
            !_focusState.spotlightTimelineController.restoreFocus()) {
          _focusFirstChannel();
        }
        return _selectionState.scheduleChannel == null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.arrowLeft &&
          (_focusState.contentTypeFocusNode.hasFocus ||
              (!(_settingsState.selectedPlaylist?.isXtreamCodes ?? false) &&
                  _focusState.categoryFilterFocusNode.hasFocus))) {
        _focusSpotlightSources();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );

  Widget _buildSpotlightSearch(IptvSpotlightLayoutMode mode) {
    final search = widget.searchHeader;
    if (search == null) return const SizedBox.shrink();
    if (search is! BrowseSearchHeader) return search;
    final t = IptvStyleTokens.spotlight;
    return BrowseSearchHeader(
      key: search.key,
      controller: search.controller,
      focusNode: search.focusNode,
      hintText: mode == IptvSpotlightLayoutMode.wide
          ? 'Search'
          : search.hintText,
      onChanged: search.onChanged,
      onSubmitted: (value) {
        search.onSubmitted?.call(value);
        // TV's parent coordinates keyboard dismissal before requesting focus.
        // Desktop and standalone headers can enter results immediately.
        if (!widget.isTelevision || search.onSubmitted == null) {
          _focusSpotlightSearchResults();
        }
      },
      onClear: search.onClear,
      onDownArrow: _focusSpotlightSearchResults,
      ink: t.fg,
      fillColor: t.fg.withValues(alpha: 0.055),
      focusedBorderColor: t.accent,
      accent: t.accent,
      keyboardGround: t.panel,
      keyboardInk: t.fg,
      keyboardInkOnAccent: t.focusInk,
      padding: mode == IptvSpotlightLayoutMode.wide
          ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
          : EdgeInsets.zero,
    );
  }

  Widget _buildSpotlightRail({
    bool collapsed = false,
    bool autofocusFirstItem = false,
    ValueChanged<IptvPlaylist>? onSelectPlaylist,
    VoidCallback? onOpenRecordings,
    VoidCallback? onNewList,
    VoidCallback? onAddPlaylist,
    VoidCallback? onAddAddon,
    VoidCallback? onManageSources,
  }) {
    return SpotlightRail(
      collapsed: collapsed,
      onEntryFocus: autofocusFirstItem
          ? null
          : () {
              if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
                _setSpotlightSourcesExpanded(true);
              }
            },
      playlists: _settingsState.playlists,
      selectedPlaylist: _settingsState.selectedPlaylist,
      sourceCounts: _recordingState.sourceCounts,
      customListCounts: {
        for (final list in _favorites.customLists)
          'iptv-list-${list.id}': list.channelCount,
      },
      favoritesCount: _membershipState.favoriteUrls.length,
      continueWatchingCount: _recordingState.continueWatchingCount,
      recordingsCount: _recordingState.scheduledCount,
      showRecordings: _recordingState.pageCanRecord,
      recordingActive: _anyRecordingLive,
      onSelectPlaylist:
          onSelectPlaylist ??
          (playlist) {
            _setSpotlightSourcesExpanded(false);
            _onPlaylistChanged(playlist, focusContent: true);
          },
      onOpenRecordings:
          onOpenRecordings ??
          (_recordingState.pageCanRecord ? _openScheduledRecordings : null),
      onNewList: onNewList ?? () => unawaited(_favorites.promptCreateList()),
      onAddPlaylist: onAddPlaylist ?? _navigateToSettings,
      onAddAddon: onAddAddon ?? _navigateToAddons,
      onManageSources: onManageSources ?? _navigateToManageSources,
      firstItemFocusNode: autofocusFirstItem ? null : _focusState.playlistFilterFocusNode,
      autofocusFirstItem: autofocusFirstItem,
      onUpFromFirstItem: autofocusFirstItem
          ? null
          : _focusSpotlightSearchOrExit,
      onExitRight: autofocusFirstItem ? null : _closeSpotlightSources,
    );
  }

  void _openSpotlightSearch() {
    final search = widget.searchHeader;
    if (search is! BrowseSearchHeader) return;
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      _setSpotlightSourcesExpanded(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide &&
              !_selectionState.spotlightSourcesExpanded)) {
        return;
      }
      if (search.focusNode.canRequestFocus) search.focusNode.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _focusSpotlightSearchOrExit() {
    if (widget.searchHeader is BrowseSearchHeader) {
      _openSpotlightSearch();
    } else {
      widget.onUpArrowFromFilters?.call();
    }
  }

  void _focusSpotlightSearchResults() {
    _selectionState.searchDebounce?.cancel();
    _applyFilters();
    final query = widget.searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.searchQuery != query) return;
      // Keep an empty search editable. A matching query enters its first row.
      if (_catalogState.filteredChannels.isEmpty) {
        _openSpotlightSearch();
        return;
      }
      _setSpotlightSourcesExpanded(false);
      _focusFirstChannel();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _focusSpotlightContentEntry() {
    if (_catalogState.filteredChannels.isNotEmpty) {
      if (!_focusState.spotlightTimelineController.restoreFocus()) _focusFirstChannel();
      return;
    }
    if ((_settingsState.selectedPlaylist?.isXtreamCodes ?? false) &&
        _focusState.contentTypeFocusNode.canRequestFocus) {
      _focusState.contentTypeFocusNode.requestFocus();
      return;
    }
    if (_focusState.categoryFilterFocusNode.canRequestFocus) {
      _focusState.categoryFilterFocusNode.requestFocus();
    }
  }

  int? get _spotlightSelectedSourceCount {
    final selected = _settingsState.selectedPlaylist;
    if (selected == null) return null;
    if (!_catalogState.isLoading) return _catalogState.allChannels.length;
    if (selected.isFavorites) return _membershipState.favoriteUrls.length;
    if (selected.isContinueWatching) return _recordingState.continueWatchingCount;
    if (selected.isCustomList) {
      for (final list in _favorites.customLists) {
        if (selected.customListId == list.id) return list.channelCount;
      }
    }
    return _recordingState.sourceCounts[selected.id];
  }

  Widget _buildSpotlightHero(IptvSpotlightLayoutMode mode) {
    return _stageHoverGuard(
      ValueListenableBuilder<int>(
        valueListenable: _previewState.previewEpoch,
        builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
          valueListenable: _previewState.previewShown,
          builder: (context, channel, _) =>
              ValueListenableBuilder<EpgProgramme?>(
                valueListenable: _previewState.spotlightProgrammeShown,
                builder: (context, programme, _) => SpotlightProgrammeHero(
                  now: widget.debugSpotlightNow,
                  channel: channel,
                  selectedProgramme: programme,
                  // TV uses short/held OK on the guide row for these actions.
                  actionsBuilder: widget.isTelevision
                      ? null
                      : (context, activeProgramme, dense) =>
                            _buildSpotlightHeroActions(
                              channel,
                              programme: activeProgramme,
                              compact:
                                  mode == IptvSpotlightLayoutMode.compact ||
                                  dense,
                            ),
                  // Keep the established preview subtree byte-for-byte.
                  // Spotlight only lays it out beside programme information.
                  previewSlot: Semantics(
                    button: channel != null,
                    label: channel == null
                        ? 'Channel preview'
                        : 'Watch ${channel.name}',
                    child: GestureDetector(
                      key: const ValueKey('spotlight-preview-play'),
                      behavior: HitTestBehavior.opaque,
                      onTap: channel == null
                          ? null
                          : () => unawaited(_playChannel(channel)),
                      child: _buildPreviewStage(channel, epoch),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildSpotlightHeroActions(
    IptvChannel? channel, {
    required EpgProgramme? programme,
    required bool compact,
  }) {
    if (channel == null) return const SizedBox.shrink();
    final t = IptvStyleTokens.spotlight;
    final primary = _spotlightPrimaryAction(channel, programme);
    final rawRecord = _spotlightRecordAction(channel);
    final record =
        programme == null ||
            programme.airsAt(DateTime.now()) ||
            rawRecord?.label == 'Stop'
        ? rawRecord
        : null;
    final isFavorited = _membershipState.favoriteUrls.contains(channel.url);
    final canSave = channel.contentType != 'series';
    final hasMore =
        record != null || canSave || IptvEpgService.isEpgCapable(channel);

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _spotlightActivation(
            primary.action,
            FilledButton.icon(
              focusNode: _focusState.spotlightPrimaryFocusNode,
              onPressed: primary.action,
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: t.focusInk,
                backgroundColor: t.focusFill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(side: _spotlightFocusBorder),
              icon: Icon(primary.icon, size: 19),
              label: Text(primary.label),
            ),
          ),
          if (hasMore) ...[
            const SizedBox(width: 5),
            _spotlightIconAction(
              tooltip: 'More channel actions',
              icon: Icons.more_horiz_rounded,
              onPressed: () =>
                  _showSpotlightChannelActions(channel, programme: programme),
            ),
          ],
        ],
      );
    }

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final compactPadding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 8,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _spotlightActivation(
          primary.action,
          FilledButton.icon(
            focusNode: _focusState.spotlightPrimaryFocusNode,
            style: FilledButton.styleFrom(
              backgroundColor: t.focusFill,
              foregroundColor: t.focusInk,
              padding: compactPadding,
              visualDensity: VisualDensity.compact,
              shape: buttonShape,
            ).copyWith(side: _spotlightFocusBorder),
            onPressed: primary.action,
            icon: Icon(primary.icon, size: 18),
            label: Text(primary.label),
          ),
        ),
        if (record != null)
          _spotlightActivation(
            record.action,
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: record.label == 'Stop' ? t.rec : t.fg,
                side: BorderSide(
                  color: record.label == 'Stop' ? t.rec : t.hairline2,
                ),
                padding: compactPadding,
                visualDensity: VisualDensity.compact,
                shape: buttonShape,
              ),
              onPressed: record.action,
              icon: Icon(record.icon, size: 16),
              label: Text(record.label),
            ),
          ),
        if (canSave)
          _spotlightIconAction(
            tooltip: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
            icon: isFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            selected: isFavorited,
            onPressed: () => unawaited(_favorites.toggleFavorite(channel, !isFavorited)),
          ),
        if ((canSave && _favorites.customLists.isNotEmpty) ||
            IptvEpgService.isEpgCapable(channel))
          _spotlightIconAction(
            tooltip: 'More channel actions',
            icon: Icons.more_horiz_rounded,
            onPressed: () =>
                _showSpotlightChannelActions(channel, programme: programme),
          ),
      ],
    );
  }

  ({String label, IconData icon, VoidCallback action}) _spotlightPrimaryAction(
    IptvChannel channel,
    EpgProgramme? programme,
  ) {
    if (channel.contentType == 'series') {
      return (
        label: 'Open',
        icon: Icons.open_in_new_rounded,
        action: () => unawaited(_playChannel(channel)),
      );
    }
    if (programme != null) {
      final now = DateTime.now();
      if (programme.airsAt(now)) {
        return (
          label: 'Watch',
          icon: Icons.play_arrow_rounded,
          action: () => unawaited(_playChannel(channel)),
        );
      }
      if (IptvEpgService.isCatchupAvailable(channel, programme)) {
        return (
          label: 'Replay',
          icon: Icons.replay_rounded,
          action: () => unawaited(_playCatchup(channel, programme)),
        );
      }
      if (programme.start.isAfter(now)) {
        final recordProgramme = _recordProgrammeActionFor(channel);
        if (recordProgramme != null) {
          return (
            label: 'Record',
            icon: Icons.fiber_manual_record_rounded,
            action: () => recordProgramme(programme),
          );
        }
      }
      return (
        label: 'Guide',
        icon: Icons.calendar_month_rounded,
        action: () => _openSchedulePane(channel),
      );
    }
    return (
      label: 'Watch',
      icon: Icons.play_arrow_rounded,
      action: () => unawaited(_playChannel(channel)),
    );
  }

  ({String label, IconData icon, VoidCallback action})? _spotlightRecordAction(
    IptvChannel channel,
  ) {
    final desktopCapture = _desktopCaptureFor(channel);
    if (desktopCapture != null) {
      return (
        label: 'Stop',
        icon: Icons.stop_rounded,
        action: () => unawaited(_stageStopDesktopRecording(desktopCapture)),
      );
    }
    final androidTask = !kIsWeb && Platform.isAndroid
        ? _androidEngineTaskFor(channel)
        : null;
    if (androidTask != null) {
      return (
        label: 'Stop',
        icon: Icons.stop_rounded,
        action: () =>
            unawaited(_stageStopAndroidRecording(channel, androidTask)),
      );
    }
    if (_recordingState.pageCanRecord && _channelEngineRecordable(channel)) {
      return (
        label: 'Record',
        icon: Icons.fiber_manual_record_rounded,
        action: () => unawaited(_stageRecordNow(channel)),
      );
    }
    return null;
  }

  Future<void> _showSpotlightChannelActions(
    IptvChannel channel, {
    EpgProgramme? programme,
  }) async {
    final t = IptvStyleTokens.spotlight;
    final rawRecord = _spotlightRecordAction(channel);
    final record =
        programme == null ||
            programme.airsAt(DateTime.now()) ||
            rawRecord?.label == 'Stop'
        ? rawRecord
        : null;
    final canSave = channel.contentType != 'series';
    final isFavorited = _membershipState.favoriteUrls.contains(channel.url);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) action();
          });
        }

        Widget actionTile({
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          Color? color,
          bool autofocus = false,
        }) {
          final ink = color ?? t.fg;
          return ListTile(
            autofocus: autofocus,
            leading: Icon(icon, color: ink),
            title: Text(label, style: TextStyle(color: ink)),
            onTap: () => closeThen(onPressed),
          );
        }

        var first = true;
        Widget nextTile({
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          Color? color,
        }) {
          final tile = actionTile(
            icon: icon,
            label: label,
            onPressed: onPressed,
            color: color,
            autofocus: first,
          );
          first = false;
          return tile;
        }

        return TvHeldKeyGuard(
          child: SimpleDialog(
            backgroundColor: t.panel,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: t.hairline2),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.fg, fontWeight: FontWeight.w800),
                  ),
                ),
                CloseButton(onPressed: () => Navigator.of(dialogContext).pop()),
              ],
            ),
            children: [
              if (record != null)
                nextTile(
                  icon: record.icon,
                  label: record.label,
                  color: record.label == 'Stop' ? t.rec : null,
                  onPressed: record.action,
                ),
              if (canSave)
                nextTile(
                  icon: isFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: isFavorited
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  color: isFavorited ? t.accent : null,
                  onPressed: () =>
                      unawaited(_favorites.toggleFavorite(channel, !isFavorited)),
                ),
              if (canSave && _favorites.customLists.isNotEmpty)
                nextTile(
                  icon: Icons.bookmark_add_outlined,
                  label: 'Save to list',
                  onPressed: () => unawaited(_favorites.openListPicker(channel)),
                ),
              if (IptvEpgService.isEpgCapable(channel))
                nextTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Full guide',
                  onPressed: () => _openSchedulePane(channel),
                ),
            ],
          ),
        );
      },
    );
  }

  WidgetStateProperty<BorderSide?> get _spotlightFocusBorder =>
      WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? IptvStyleTokens.spotlight.accent
              : Colors.transparent,
          width: 3,
        ),
      );

  Widget _spotlightActivation(VoidCallback action, Widget child) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (!isActivateOrSpaceKey(event.logicalKey)) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) action();
      return KeyEventResult.handled;
    },
    child: child,
  );

  Widget _spotlightIconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final t = IptvStyleTokens.spotlight;
    return _spotlightActivation(
      onPressed,
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style:
            IconButton.styleFrom(
              foregroundColor: selected ? t.accent : t.fgMid,
              backgroundColor: selected ? t.selectedTint : t.focusTint,
              side: BorderSide(color: selected ? t.accent : t.hairline2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? t.focusFill
                    : selected
                    ? t.selectedTint
                    : t.focusTint,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? t.focusInk
                    : selected
                    ? t.accent
                    : t.fgMid,
              ),
            ),
        icon: Icon(icon, size: 18),
      ),
    );
  }

  Widget _buildSpotlightContent(IptvSpotlightLayoutMode mode) {
    final scheduleChannel = _selectionState.scheduleChannel;
    final browser = _buildSpotlightBrowser(mode);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: scheduleChannel != null,
          child: ExcludeFocus(
            excluding: scheduleChannel != null,
            child: browser,
          ),
        ),
        if (scheduleChannel != null)
          ValueListenableBuilder<int>(
            valueListenable: IptvEpgService.instance.contextVersion,
            builder: (context, epgVersion, _) => IptvSchedulePane(
              // A guide published after the pane opened must replace the
              // once-loaded empty schedule with a fresh one.
              key: ValueKey(
                'spotlight-schedule-${scheduleChannel.url}-$epgVersion',
              ),
              channel: scheduleChannel,
              onClose: _closeSchedulePane,
              isTelevision: widget.isTelevision,
              onPlayProgramme: (programme) =>
                  _playCatchup(scheduleChannel, programme),
              onRecordProgramme: _recordProgrammeActionFor(scheduleChannel),
            ),
          ),
      ],
    );
  }

  Widget _buildSpotlightBrowser(IptvSpotlightLayoutMode mode) {
    if (!_spotlightUsesTimeline) {
      return _buildContent(tvPane: true, cockpit: false);
    }

    // Preserve the existing load/error/empty surfaces. The timeline only
    // replaces the populated live-channel renderer.
    if (_settingsState.playlists.isEmpty ||
        _settingsState.selectedPlaylist == null ||
        _catalogState.isLoading ||
        (_catalogState.errorMessage != null && _catalogState.allChannels.isEmpty) ||
        _catalogState.filteredChannels.isEmpty) {
      return _buildContent(tvPane: true, cockpit: false);
    }

    final selected = _settingsState.selectedPlaylist!;
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<int>(
        valueListenable: IptvEpgService.instance.contextVersion,
        builder: (context, epgVersion, _) => SpotlightLiveTimeline(
          key: _focusState.spotlightTimelineKey,
          now: widget.debugSpotlightNow,
          channels: _catalogState.filteredChannels,
          sourceId: selected.id,
          loadGeneration: Object.hash(_catalogState.loadTicket, _catalogState.spotlightViewGeneration),
          scheduleLoader: (channel) =>
              IptvEpgService.instance.schedule(channel.url),
          controller: _focusState.spotlightTimelineController,
          epgContextVersion: epgVersion,
          onSelectionChanged: _onSpotlightSelection,
          onExitUp: () => _focusState.categoryFilterFocusNode.requestFocus(),
          onExitLeft: _focusSpotlightSources,
          onChannelActions: (entry) => _showSpotlightChannelActions(
            entry.channel,
            programme: _previewState.spotlightProgrammeShown.value,
          ),
          onChannelActivate: (entry) => unawaited(_playChannel(entry.channel)),
          onProgrammeActivate: _activateSpotlightProgramme,
          // Keep short programmes readable on a television: the preceding
          // half-hour ruler interval plus the following hour.
          windowDuration: const Duration(minutes: 90),
          height: constraints.maxHeight,
          identityWidth: mode == IptvSpotlightLayoutMode.wide ? 300 : 260,
          dense: true,
          rowHeight: 46,
          rulerHeight: 32,
        ),
      ),
    );
  }

  bool get _spotlightUsesTimeline {
    final selected = _settingsState.selectedPlaylist;
    if (selected == null) return false;
    // Saved shelves share the guide's row navigation, including its playable
    // no-guide and on-demand rows. Schedule lookup stays channel-based so
    // mixed Xtream providers use their own credentials without switching the
    // page's global XMLTV context for each row.
    if (selected.isFavorites || selected.isCustomList) return true;
    if (selected.isVirtual) return false;
    return !selected.isXtreamCodes || _catalogState.selectedContentType == 'live';
  }

  void _onSpotlightSelection(SpotlightTimelineSelection selection) {
    final channel = selection.entry.channel;
    _onChannelFocused(channel, fromPointer: selection.fromPointer);
    if (identical(_previewState.previewShown.value, channel)) {
      _previewState.spotlightProgrammeShown.value = selection.programme;
    }
  }

  void _activateSpotlightProgramme(
    SpotlightTimelineEntry entry,
    EpgProgramme programme,
  ) {
    final now = DateTime.now();
    if (programme.airsAt(now)) {
      unawaited(_playChannel(entry.channel));
      return;
    }
    if (IptvEpgService.isCatchupAvailable(entry.channel, programme)) {
      unawaited(_playCatchup(entry.channel, programme));
      return;
    }
    if (programme.start.isAfter(now)) {
      final record = _recordProgrammeActionFor(entry.channel);
      if (record != null) {
        record(programme);
        return;
      }
    }
    // A programme without a direct replay/record action still opens the full
    // schedule, where the user can inspect the surrounding listings.
    _openSchedulePane(entry.channel);
  }

  Future<void> _showSpotlightSources() async {
    final size = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) action();
          });
        }

        return TvHeldKeyGuard(
          child: Dialog(
            backgroundColor: IptvStyleTokens.spotlight.panel,
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: IptvStyleTokens.spotlight.hairline2),
            ),
            child: SizedBox(
              width: math.min(390, size.width - 32),
              height: math.min(620, size.height - 32),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Sources')),
                        CloseButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _buildSpotlightRail(
                        autofocusFirstItem: true,
                        onSelectPlaylist: (playlist) => closeThen(
                          () =>
                              _onPlaylistChanged(playlist, focusContent: true),
                        ),
                        onOpenRecordings: _recordingState.pageCanRecord
                            ? () => closeThen(_openScheduledRecordings)
                            : null,
                        onNewList: () =>
                            closeThen(() => unawaited(_favorites.promptCreateList())),
                        onAddPlaylist: () => closeThen(_navigateToSettings),
                        onAddAddon: () => closeThen(_navigateToAddons),
                        onManageSources: () =>
                            closeThen(_navigateToManageSources),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }



  Future<void> _showSpotlightCategoryPicker() async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (_) => SpotlightCategoryPickerDialog(
        categories: List<String>.of(_catalogState.categories, growable: false),
        selectedCategory: _effectiveCategory,
        categoryCounts: Map<String, int>.of(_categoryCounts),
        allChannelCount: _catalogState.allChannels.length,
        showOptionsHint: _canShowCategoryOptions && _catalogState.categories.isNotEmpty,
        allCategoryValue: IptvSelectionState.kSpotlightAllCategory,
      ),
    );
    if (!mounted || picked == null) return;
    _onCategoryChanged(picked == IptvSelectionState.kSpotlightAllCategory ? null : picked);
  }

  /// The single-pane layout: boxed filter bar over a full-width channel list.
  /// Phones keep it (no embedded preview there), and TV/desktop fall back to
  /// it when the canvas can't fit two panes.
  Widget _buildClassic() {
    return Column(
      children: [
        // Filters bar
        IptvFiltersBar(
          playlists: _settingsState.playlists,
          selectedPlaylist: _settingsState.selectedPlaylist,
          categories: _catalogState.categories,
          selectedCategory: _effectiveCategory,
          categoryCounts: _categoryCounts,
          channelCount: _catalogState.filteredChannels.length,
          isLoading: _catalogState.isLoading,
          isLoadingMore: _catalogState.isLoadingMore,
          onPlaylistChanged: _onPlaylistChanged,
          onCategoryChanged: _onCategoryChanged,
          onAddPlaylist: _navigateToSettings,
          playlistFocusNode: _focusState.playlistFilterFocusNode,
          categoryFocusNode: _focusState.categoryFilterFocusNode,
          showContentTypeFilter: _settingsState.selectedPlaylist?.isXtreamCodes ?? false,
          selectedContentType: _catalogState.selectedContentType,
          onContentTypeChanged: _onContentTypeChanged,
          contentTypeFocusNode: _focusState.contentTypeFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _focusFirstChannel,
          onOpenRecordings: _recordingState.pageCanRecord ? _openScheduledRecordings : null,
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
    final scheduleChannel = _selectionState.scheduleChannel;

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
                      _settingsState.iptvStyle == IptvStyle.edition &&
                      gc.maxHeight >= 700)
                    IptvEditionHero(
                      channel: _previewState.previewShown,
                      tokens: IptvStyleTokens.edition,
                      suspended: scheduleChannel != null,
                    ),
                  // Master Control's 6-hour strip — same display-only rules
                  // as the hero. Same budget with its own 96px height:
                  // 50 + 96 + 24 + 8 + 472 + 12 = 662 → 670 with margin.
                  if (cockpit &&
                      _settingsState.iptvStyle == IptvStyle.console &&
                      gc.maxHeight >= 670)
                    IptvConsoleTimeline(
                      channel: _previewState.previewShown,
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
      final cockpitTokens = IptvStyleTokens.of(_settingsState.iptvStyle);
      final cockpitRow = Row(
        key: const ValueKey('iptv-cockpit'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railW,
            child: IptvCommandRail(
              tokens: cockpitTokens,
              playlists: _settingsState.playlists,
              selectedPlaylist: _settingsState.selectedPlaylist,
              customLists: _membershipState.lists,
              sourceCounts: _recordingState.sourceCounts,
              favoritesCount: _membershipState.favoriteUrls.length,
              scheduledCount: _recordingState.scheduledCount,
              // focusContent: OK is a decision, so it lands DPAD on the
              // channels it just loaded. (Merely walking RIGHT does not
              // select — it traverses into the guide, which still shows the
              // selected source.)
              onSelectPlaylist: (p) =>
                  _onPlaylistChanged(p, focusContent: true),
              onOpenScheduled: _openScheduledRecordings,
              onManageSources: _navigateToManageSources,
              // Engine off / unsupported: don't advertise a scheduler that
              // would refuse to work (settings hides its row in this state).
              showScheduled: _recordingState.pageCanRecord,
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
      if (_settingsState.iptvStyle == IptvStyle.console) {
        return Column(
          children: [
            IptvConsoleStatusBar(
              tokens: cockpitTokens,
              sourceName: _settingsState.selectedPlaylist?.name ?? 'IPTV',
              channelCount: _catalogState.filteredChannels.length,
              recCount: (!kIsWeb && Platform.isAndroid)
                  ? _recordingState.androidRecordingsByUrl.length
                  : DesktopRecordingService.instance.isSupported
                  ? DesktopRecordingService.instance.captures.length
                  : 0,
              schedCount: _recordingState.scheduledCount,
              statusText: _statusState.chipState == CatalogChipState.hidden
                  ? null
                  : _statusState.chipMessage,
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
          valueListenable: _previewState.previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewState.previewShown,
            builder: (context, ch, _) {
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: app.shape.br(10),
                  child: ColoredBox(
                    color:
                        IptvStyleTokens.of(_settingsState.iptvStyle)?.panel ??
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
                                      tokens: IptvStyleTokens.of(_settingsState.iptvStyle),
                                      channel: ch,
                                      isTelevision: widget.isTelevision,
                                      isFavorited: _membershipState.favoriteUrls.contains(
                                        ch.url,
                                      ),
                                      canRecord: _recordingState.pageCanRecord,
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
                                              _favorites.toggleFavorite(
                                                ch,
                                                !_membershipState.favoriteUrls.contains(ch.url),
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
    final t = IptvStyleTokens.of(_settingsState.iptvStyle);
    final isConsole = _settingsState.iptvStyle == IptvStyle.console;
    // Styled looks never paint the brand color.
    final brand = t == null ? brandAccentFor(channel.name) : Colors.transparent;
    final resMatch = railResExp.firstMatch(channel.name);
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
          value: _settingsState.selectedPlaylist?.id ?? '',
          quiet: true,
          quietAccent: true,
          isTelevision: widget.isTelevision,
          focusNode: _focusState.playlistFilterFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _focusFirstChannel,
          options: _sourceDropdownOptions(),
          onSelected: (id) {
            if (id == IptvSelectionState.kNewListSentinel) {
              _favorites.promptCreateList();
              return;
            }
            if (id == IptvSelectionState.kAddPlaylistSentinel) {
              _navigateToSettings();
              return;
            }
            if (id == IptvSelectionState.kAddAddonSentinel) {
              _navigateToAddons();
              return;
            }
            for (final p in _settingsState.playlists) {
              if (p.id == id) {
                _onPlaylistChanged(p);
                return;
              }
            }
          },
        ),
        if (_settingsState.selectedPlaylist?.isXtreamCodes ?? false)
          StremioDropdown<String>(
            label: 'type',
            value: _catalogState.selectedContentType,
            quiet: true,
            isTelevision: widget.isTelevision,
            focusNode: _focusState.contentTypeFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: const [
              StremioDropdownOption('live', 'Live TV'),
              StremioDropdownOption('vod', 'Movies'),
              StremioDropdownOption('series', 'Series'),
            ],
            onSelected: _onContentTypeChanged,
          ),
        if (_catalogState.categories.isNotEmpty)
          StremioDropdown<String>(
            label: 'category',
            value: _effectiveCategory ?? '',
            quiet: true,
            isTelevision: widget.isTelevision,
            focusNode: _focusState.categoryFilterFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _focusFirstChannel,
            options: [
              StremioDropdownOption('', 'All · ${_catalogState.allChannels.length}'),
              for (final cat in _catalogState.categories)
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
            _catalogState.isLoading
                ? 'Loading…'
                : '${_catalogState.filteredChannels.length} channel'
                      '${_catalogState.filteredChannels.length == 1 ? '' : 's'}'
                      // The list is still streaming in — never present a
                      // partial count as final.
                      '${_catalogState.isLoadingMore ? ' • loading more…' : ''}',
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





  /// The Sources dropdown, grouped: the two derived shelves, then the user's
  /// own lists, their playlists, and any live-TV catalogs their Stremio addons
  /// expose — each ending with the action that adds another one of its kind.
  ///
  /// The grouping mirrors the order [_loadSettings] already builds, so this
  /// only draws the lines where the list already changes character.
  List<StremioDropdownOption<String>> _sourceDropdownOptions() {
    final quickAccess = [
      for (final p in _settingsState.playlists)
        if (p.isFavorites || p.isContinueWatching) p,
    ];
    final lists = [
      for (final p in _settingsState.playlists)
        if (p.isCustomList) p,
    ];
    final addons = [
      for (final p in _settingsState.playlists)
        if (p.isStremioAddon) p,
    ];
    final playlists = [
      for (final p in _settingsState.playlists)
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
      const StremioDropdownOption(IptvSelectionState.kNewListSentinel, '＋ New list'),
      const StremioDropdownOption.header('__hdr_playlists__', 'Your playlists'),
      for (final p in playlists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(IptvSelectionState.kAddPlaylistSentinel, '＋ Add playlist'),
      // Only for people who actually run addons — an empty section would push
      // Stremio at everyone else.
      if (addons.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_addons__', 'Stremio Addons'),
        for (final p in addons) StremioDropdownOption(p.id, p.name),
        const StremioDropdownOption(IptvSelectionState.kAddAddonSentinel, '＋ Add addon'),
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
    if (_selectionState.scheduleChannel != null) return;
    final channel = _previewState.previewShown.value;
    if (channel != null &&
        _selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic &&
        _focusState.spotlightTimelineController.restoreFocus()) {
      return;
    }
    if (channel != null && _rowAttached(channel)) {
      _focusNodeFor(channel).requestFocus();
      return;
    }
    _focusFirstChannel();
  }



  /// Lets a preview stage claim the pointer, so nothing repoints it while the
  /// cursor is inside on its way to Watch or Record. A row the pointer RESTS on
  /// is exempt (see [_onChannelFocused]) — the cursor cannot be on a row and in
  /// the stage at once, so that exemption also means a flag left stuck true by
  /// a missed onExit can never strand the hover preview.
  Widget _stageHoverGuard(Widget child) {
    if (widget.isTelevision) return child;
    return MouseRegion(
      onEnter: (_) => _previewState.pointerInStage = true,
      onExit: (_) => _previewState.pointerInStage = false,
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
    if (!fromPointer && _previewState.pointerInStage && _previewState.previewShown.value != null) return;
    // The in-app player fallback never pauses the app, so a parked re-arm
    // wouldn't flush via the lifecycle observer — the focus restore after its
    // route pops (or the user's next move) lands here instead.
    _flushPreviewRearm();
    final shown = _previewState.previewShown.value;
    if (identical(shown, channel)) return;
    _previewState.spotlightProgrammeShown.value = null;
    _previewState.previewShown.value = channel;
    if (_settingsState.channelPreviewEnabled) {
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
    _previewState.previewResolveTicket++;
    final ticket = _previewState.previewResolveTicket;
    _previewState.previewCandidates = null;
    // Series carry a sentinel URL, not a stream — the stage rests on its
    // floor (logo slab), like a channel with nothing playable.
    if (channel.contentType == 'series') {
      _previewState.previewStreamUrl.value = null;
      _previewState.previewShowing.value = false;
      return;
    }
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _previewState.previewStreamUrl.value = channel.url;
      return;
    }
    // Unmounting the backdrop skips its teardown notification — reset the
    // "has frames" chip state ourselves or it would keep reading LIVE.
    _previewState.previewStreamUrl.value = null;
    _previewState.previewShowing.value = false;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || ticket != _previewState.previewResolveTicket) return;
      // No playable streams — the stage stays on its floor, exactly like a
      // dead M3U channel.
      if (found.isEmpty) return;
      final urls = [for (final c in found) c.url];
      _previewState.previewCandidates = urls;
      _previewState.previewStreamUrl.value = urls.first;
    });
  }

  /// The stage's current stream genuinely failed (refused to open, errored, or
  /// stalled past the first-frame timeout). Stremio channels step down their
  /// candidate ladder; anything else keeps the old behavior (silent floor).
  /// [ticket] is the ladder generation the failing backdrop was built for —
  /// the notification is post-frame, so by the time it lands the focus may
  /// already be on another channel whose ladder must not be touched.
  void _onPreviewPlaybackFailed(int ticket) {
    if (ticket != _previewState.previewResolveTicket) return;
    final candidates = _previewState.previewCandidates;
    final current = _previewState.previewStreamUrl.value;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0) return; // stale failure for a URL we've already moved off
    if (next >= candidates.length) {
      // Every candidate is dead: drop back to the floor and forget the cached
      // list so a later attempt re-resolves fresh links.
      final shown = _previewState.previewShown.value;
      if (shown != null) StremioIptvService.instance.invalidate(shown.url);
      _previewState.previewStreamUrl.value = null;
      _previewState.previewShowing.value = false;
      return;
    }
    _previewState.previewStreamUrl.value = candidates[next];
  }

  /// First frames arrived — remember which candidate actually plays so the
  /// next preview/play of this channel starts there. Same staleness guard as
  /// the failure path: frames from a previous channel's engine must not
  /// crown the new channel's candidate.
  void _markPreviewWinner(int ticket) {
    if (ticket != _previewState.previewResolveTicket) return;
    final shown = _previewState.previewShown.value;
    final current = _previewState.previewStreamUrl.value;
    if (shown == null || current == null || _previewState.previewCandidates == null) return;
    if (StremioIptvService.isStremioChannelUrl(shown.url)) {
      StremioIptvService.instance.markWinner(shown.url, current);
    }
  }

  /// Release the embedded stream and abandon any in-flight Stremio resolve,
  /// while leaving the selected channel's artwork, metadata and actions in
  /// the stage. This is the persistent-setting path.
  void _stopPreviewPlayback() {
    _previewState.previewResolveTicket++;
    _previewState.previewCandidates = null;
    _previewState.previewStreamUrl.value = null;
    _previewState.previewShowing.value = false;
  }

  /// Empty the stage entirely (playlist switch, sidebar open) and abandon any
  /// in-flight resolve.
  void _clearPreview() {
    _stopPreviewPlayback();
    _previewState.spotlightProgrammeShown.value = null;
    _previewState.previewShown.value = null;
  }

  Widget _buildPreviewRail({required bool touchSelector}) {
    final app = AppThemeScope.of(context);
    return _stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewState.previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewState.previewShown,
            builder: (context, ch, _) {
              if (widget.isTelevision) {
                return _buildTvFocusStage(ch, epoch);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPreviewStage(ch, epoch),
                  const SizedBox(height: 16),
                  Expanded(child: IptvRailInfo(channel: ch)),
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
                        _settingsState.channelPreviewEnabled
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
                        _settingsState.channelPreviewEnabled
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
                  : IptvFocusStageInfo(
                      channel: ch,
                      hasLists: _favorites.customLists.isNotEmpty,
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
              valueListenable: _previewState.previewShowing,
              builder: (context, showing, _) => IptvStageFloor(
                channel: ch,
                tuning: _settingsState.channelPreviewEnabled && ch != null && !showing,
              ),
            ),
            // Startup launch owns the screen: the stage's 900ms dwell would
            // otherwise open a SECOND live stream under the launching player.
            if (ch != null && _settingsState.channelPreviewEnabled && !_playerState.startupLaunchActive)
              ValueListenableBuilder<String?>(
                valueListenable: _previewState.previewStreamUrl,
                builder: (context, streamUrl, _) {
                  // Null while a Stremio channel resolves (or when every
                  // candidate died) — only the floor shows.
                  if (streamUrl == null) return const SizedBox.shrink();
                  // Ladder generation these callbacks belong to — they fire
                  // post-frame, possibly after focus moved to another channel.
                  final ticket = _previewState.previewResolveTicket;
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
                      if (ticket == _previewState.previewResolveTicket) {
                        _previewState.previewShowing.value = p;
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
                valueListenable: _previewState.previewShowing,
                builder: (context, showing, _) => IptvStageChip(
                  channel: ch,
                  showing: showing,
                  previewEnabled: _settingsState.channelPreviewEnabled,
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
    if (_settingsState.playlists.isEmpty) {
      return IptvEmptyState(
        hasPlaylists: false,
        onAddPlaylist: _navigateToSettings,
      );
    }

    // Empty state when no playlist selected
    if (_settingsState.selectedPlaylist == null) {
      return const IptvEmptyState(hasPlaylists: true);
    }

    // Loading
    if (_catalogState.isLoading) {
      return _loadStatus.buildLoadingState(context);
    }

    // Error
    if (_catalogState.errorMessage != null && _catalogState.allChannels.isEmpty) {
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
                _catalogState.errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _settingsLoading.retryLoad,
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
    if (_catalogState.filteredChannels.isEmpty) {
      if (_catalogState.isLoadingMore) {
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
                    : _catalogState.selectedCategory != null
                    ? 'Nothing in this category yet — still loading'
                    : 'Loading channels…',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${_catalogState.allChannels.length} channel'
                '${_catalogState.allChannels.length == 1 ? '' : 's'} loaded so far',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      final isFavoritesView = _settingsState.selectedPlaylist?.isFavorites ?? false;
      final isListView = _settingsState.selectedPlaylist?.isCustomList ?? false;
      final isContinueView = _settingsState.selectedPlaylist?.isContinueWatching ?? false;
      final unfiltered =
          widget.searchQuery.isEmpty && _catalogState.selectedCategory == null;
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
                  ? 'Nothing in ${_settingsState.selectedPlaylist?.name ?? 'this list'} yet'
                  : 'No channels found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : _catalogState.selectedCategory != null
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
            _catalogState.filteredChannels,
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
              final channelList = _catalogState.filteredChannels;
              final itemCount = channelList.length;
              // Published for the startup-channel launch, which must scroll to
              // a row that has never been built (so it has no focus node and
              // no ensureVisible of its own). These are LayoutBuilder locals —
              // unreachable from outside without stashing them.
              _selectionState.gridColumns = columns;
              _selectionState.gridRowExtent = rowExtent;

              // NOT wrapped in TvFocusScrollWrapper: this subtree has no ancestor
              // Scrollable, so the wrapper's ensureVisible walk was a silent no-op
              // — and each row already runs its own ensureVisible on focus, so the
              // wrapper only ever risked a second, competing scroll animation.
              return FocusTraversalGroup(
                child: GridView.builder(
                  controller: _focusState.scrollController,
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
                      onLongPress: (_settingsState.selectedPlaylist?.isContinueWatching ?? false)
                          ? () => _showContinueWatchingActions(channel)
                          : null,
                      focusNode: _focusNodeFor(channel),
                      isFavorited: _membershipState.favoriteUrls.contains(channel.url),
                      inAnyList: _membershipState.membership[channel.url]?.isNotEmpty ?? false,
                      onFavoriteToggle: channel.contentType == 'series'
                          ? null
                          : (isFavorited) =>
                                _favorites.toggleFavorite(channel, isFavorited),
                      onOpenListPicker: channel.contentType == 'series'
                          ? null
                          : () => _favorites.openListPicker(channel),
                      hasCustomLists: _favorites.customLists.isNotEmpty,
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
                      progress: _membershipState.progressByUrl[channel.url],
                      poster: _showsPosterRows,
                      epg: epgRows,
                      twoLineName: cockpit && !_showsPosterRows,
                      // Styled looks exist only in the cockpit, and only for
                      // live/EPG rows — VOD/series posters keep the shipped
                      // layout in every style (plan: posters are untouched).
                      style: cockpit && !_showsPosterRows
                          ? _settingsState.iptvStyle
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
                  ? 'Still loading (${_catalogState.allChannels.length} so far) — '
                        'search results may be incomplete'
                  : 'Still loading channels — '
                        '${_catalogState.allChannels.length} so far',
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
          _catalogState.isLoadingMore ? buildProgressiveStatus() : const SizedBox.shrink(),
          Expanded(
            key: const ValueKey('iptv-tablet-selector-slot'),
            child: channelBrowser,
          ),
        ],
      );
    }

    if (!_catalogState.isLoadingMore) return channelBrowser;
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
          onLongPress: (_settingsState.selectedPlaylist?.isContinueWatching ?? false)
              ? () => _showContinueWatchingActions(channel)
              : null,
          isFavorited: _membershipState.favoriteUrls.contains(channel.url),
          inAnyList: _membershipState.membership[channel.url]?.isNotEmpty ?? false,
          onFavoriteToggle: channel.contentType == 'series'
              ? null
              : (isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
          onOpenListPicker: channel.contentType == 'series'
              ? null
              : () => _favorites.openListPicker(channel),
          hasCustomLists: _favorites.customLists.isNotEmpty,
          onSchedule: openSchedule == null
              ? null
              : () {
                  centerItem();
                  _selectTabletChannel(index, channel);
                  openSchedule();
                },
          progress: _membershipState.progressByUrl[channel.url],
          poster: _showsPosterRows,
          epg: epgRows,
        );
      },
    );
  }

  TabletChannelIdentity _tabletIdentityOf(IptvChannel channel) => (
    channelNumber: channel.channelNumber,
    name: channel.name,
    url: channel.url,
    group: channel.group,
    contentType: channel.contentType,
  );

  ({int index, TabletChannelIdentity identity}) _reconcileTabletSelection(
    List<IptvChannel> channels,
  ) {
    assert(channels.isNotEmpty);
    final wanted = _selectionState.tabletSelectedIdentity;
    if (wanted != null) {
      final previous = _selectionState.tabletSelectedIndex;
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
            _selectionState.tabletSelectedIndex = index;
            return (index: index, identity: wanted);
          }
        }
      } else {
        final shown = _previewState.previewShown.value;
        final index = shown == null ? null : channels.indexOfInstance(shown);
        if (index != null && _tabletIdentityOf(channels[index]) == wanted) {
          _selectionState.tabletSelectedIndex = index;
          return (index: index, identity: wanted);
        }
      }
    }

    final identity = _tabletIdentityOf(channels.first);
    _selectionState.tabletSelectedIndex = 0;
    _selectionState.tabletSelectedIdentity = identity;
    return (index: 0, identity: identity);
  }

  void _selectTabletChannel(int index, IptvChannel channel) {
    _selectionState.tabletSelectedIndex = index;
    _selectionState.tabletSelectedIdentity = _tabletIdentityOf(channel);
    _onChannelFocused(channel);
  }
}





// ── TV preview rail widgets ─────────────────────────────────────────────────





















/// Real production tear-offs and borrowed identities for characterization.
@visibleForTesting
({
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>) browse,
  Future<void> Function(IptvPlaylist) loadPlaylist,
  void Function(String?) chooseCategory,
  Future<void> Function(
    IptvPlaylist,
    String,
    String,
    int, {
    bool usePublishedSnapshot,
  }) refreshCatalog,
  Future<void> Function(
    IptvPlaylist,
    int,
    CatalogSnapshot, {
    String? warning,
    bool migrateFavorites,
  }) presentDbCatalog,
  FocusNode Function(IptvChannel) focusNodeFor,
  bool Function(IptvChannel) rowAttached,
  List<IptvChannel> allChannels,
  List<IptvChannel> filteredChannels,
  List<IptvPlaylist> playlists,
  IptvPlaylist? selectedPlaylist,
  String? selectedCategory,
  CatalogSnapshot? snapshot,
  Map<IptvChannel, FocusNode> focusNodes,
  Set<IptvChannel> detachedRows,
  ValueNotifier<IptvChannel?> previewShown,
  ValueNotifier<EpgProgramme?> programmeShown,
  int loadTicket,
  bool landingSeedArmed,
  bool categoryManuallyChosen,
}) iptvResultsViewTestAccess(IptvResultsViewState state) => (
  browse: state._providePlayerIptvBrowse,
  loadPlaylist: state._catalogLoading.loadPlaylist,
  chooseCategory: state._onCategoryChanged,
  refreshCatalog: state._catalogRefresh.applyDbCatalogRefresh,
  presentDbCatalog: state._catalogPresentation.presentDbCatalog,
  focusNodeFor: state._focusNodeFor,
  rowAttached: state._rowAttached,
  allChannels: state._catalogState.allChannels,
  filteredChannels: state._catalogState.filteredChannels,
  playlists: state._settingsState.playlists,
  selectedPlaylist: state._settingsState.selectedPlaylist,
  selectedCategory: state._catalogState.selectedCategory,
  snapshot: state._catalogState.dbSnapshot,
  focusNodes: state._focusState.cardFocusNodes,
  detachedRows: state._focusState.detachedRows,
  previewShown: state._previewState.previewShown,
  programmeShown: state._previewState.spotlightProgrammeShown,
  loadTicket: state._catalogState.loadTicket,
  landingSeedArmed: state._catalogState.landingSeedArmed,
  categoryManuallyChosen: state._catalogState.categoryManuallyChosen,
);
