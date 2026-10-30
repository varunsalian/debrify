import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_owners.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_view_sections.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_category_order.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/application/iptv_layout_policy.dart';
import 'package:debrify/features/iptv/application/iptv_load_status_policy.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_landing_policy.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import '../../models/iptv_playlist.dart';
import '../browse/browse_results_focus.dart';
import '../../services/iptv_channel_order.dart';
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_refresh_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../../services/iptv_epg_service.dart';
import 'spotlight/iptv_spotlight_layout.dart';
import '../../services/desktop_recording_service.dart';
import '../../services/profiles/profile_preferences.dart';

import '../../services/live_recording_service.dart';

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
  late final IptvViewSections _sections = IptvViewSections((
    setState: setState,
    mounted: () => mounted,
    context: () => context,
    searchQuery: () => widget.searchQuery,
    isTelevision: () => widget.isTelevision,
    searchHeader: () => widget.searchHeader,
    onUpArrowFromFilters: () => widget.onUpArrowFromFilters,
    debugOnSpotlightStartupFocus: () => widget.debugOnSpotlightStartupFocus,
    debugSpotlightNow: () => widget.debugSpotlightNow,
  ), _owners.states);

  final _owners = IptvCompositionOwners();

  static const double tabletTwoPaneMinWidth =
      IptvLayoutPolicy.tabletTwoPaneMinWidth;
  static const double tabletTwoPaneMinHeight =
      IptvLayoutPolicy.tabletTwoPaneMinHeight;

  static bool shouldUseTouchTabletTwoPane({
    required bool isTelevision,
    required bool isWeb,
    required TargetPlatform platform,
    required Size availableSize,
  }) => IptvLayoutPolicy.shouldUseTouchTabletTwoPane(
    isTelevision: isTelevision,
    isWeb: isWeb,
    platform: platform,
    availableSize: availableSize,
  );

  @override
  void initState() {
    super.initState();
    if (widget.isTelevision) {
      // Lifecycle observer completes the parked preview re-arm when the app
      // returns from the native player (see _playChannel); the sidebar
      // listener stops the preview while the menu overlay is open.
      WidgetsBinding.instance.addObserver(this);
      MainPageBridge.addTvSidebarFocusListener(
        _sections.playback.previewHandoff.onTvSidebarFocusChanged,
      );
    }
    // Virtual Stremio playlists come and go with the installed addon set.
    StremioService.instance.addAddonsChangedListener(
      _sections.catalog.settingsLoading.onStremioAddonsChanged,
    );
    IptvChannelOrderSignal.revision.addListener(
      _sections.browsing.filtersSection.onChannelOrderChanged,
    );
    IptvCatalogRefreshService.instance.revision.addListener(
      _sections.catalog.catalogRefresh.onCatalogRefreshed,
    );
    // Chained, not fire-and-forget: the startup launch needs the playlist list
    // to exist before it can pick the target's provider.
    // Guarded on the error too, not just mounted: _loadSettings now SWALLOWS
    // its failures (it renders them instead), so this callback runs on a path
    // that used to skip it entirely. _maybeRunStartupLaunch consumes the
    // one-shot startup payload, and burning it against an empty playlist set
    // would cancel a boot-to-channel request that Retry could still honour.
    _sections.catalog.settingsLoading.loadSettings().then((_) {
      if (mounted && _owners.settingsState.settingsError == null) {
        unawaited(_sections.playback.startupLaunch.maybeRunStartupLaunch());
      }
    });
    _sections.catalog.favorites.loadFavorites();
    // Stage cockpit: recording availability + the rail's Scheduled badge.
    // Off the critical path; only ever ENABLES affordances.
    unawaited(_sections.recordings.recordingSupport.initRecordingSupport());
    if (!kIsWeb && Platform.isIOS) {
      unawaited(
        DevicePreferences.instance().then((prefs) {
          if (!mounted) return;
          if (!(prefs.getBool(IptvSettingsState.iosNoticeDismissedPref) ??
              false)) {
            setState(() => _owners.settingsState.showIosRecordingNotice = true);
          }
        }),
      );
    }
    // Observe, don't sample: schedule mutations from ANY in-process surface
    // (player sheet, manual timer, desktop scheduler firing) update the rail
    // badge, and desktop capture starts/ends flip the stage's Record↔Stop —
    // including a SCHEDULED capture starting while focus parks on its channel.
    LiveRecordingService.schedulesRevision.addListener(
      _sections.recordings.recordingSupport.onSchedulesChanged,
    );
    DesktopRecordingService.instance.revision.addListener(
      _sections.recordings.recordingSupport.onDesktopRecordingChanged,
    );
  }

  @override
  void didUpdateWidget(IptvResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Search filter when query changes. Debounced: the field live-filters on
    // every keystroke, and re-scanning a 10k-channel playlist per keypress is
    // what made typing janky. Clearing applies immediately so backing out of
    // a search feels instant.
    if (widget.searchQuery != _owners.selectionState.lastSearchQuery) {
      _owners.selectionState.lastSearchQuery = widget.searchQuery;
      _owners.selectionState.searchDebounce?.cancel();
      if (widget.searchQuery.isEmpty) {
        _sections.browsing.filtersSection.applyFilters();
      } else {
        _owners.selectionState.searchDebounce = Timer(
          const Duration(milliseconds: 220),
          () {
            if (mounted) _sections.browsing.filtersSection.applyFilters();
          },
        );
      }
    }
  }

  @override
  void dispose() {
    IptvCatalogRefreshService.instance.revision.removeListener(
      _sections.catalog.catalogRefresh.onCatalogRefreshed,
    );
    _owners.recordingState.sourceCountsDebounce?.cancel();
    _owners.recordingState.androidRecStateDebounce?.cancel();
    LiveRecordingService.schedulesRevision.removeListener(
      _sections.recordings.recordingSupport.onSchedulesChanged,
    );
    DesktopRecordingService.instance.revision.removeListener(
      _sections.recordings.recordingSupport.onDesktopRecordingChanged,
    );
    if (widget.isTelevision) {
      WidgetsBinding.instance.removeObserver(this);
      MainPageBridge.removeTvSidebarFocusListener(
        _sections.playback.previewHandoff.onTvSidebarFocusChanged,
      );
    }
    StremioService.instance.removeAddonsChangedListener(
      _sections.catalog.settingsLoading.onStremioAddonsChanged,
    );
    _sections.catalog.settingsLoading.rememberShelf();
    IptvChannelOrderSignal.revision.removeListener(
      _sections.browsing.filtersSection.onChannelOrderChanged,
    );
    _owners.selectionState.searchDebounce?.cancel();
    _owners.selectionState.contentTypeDebounce?.cancel();
    _owners.statusState.loadTicker?.cancel();
    _owners.statusState.maintenanceChipTimer?.cancel();
    _owners.statusState.chipShowTimer?.cancel();
    _owners.statusState.chipHideTimer?.cancel();
    _owners.focusState.scrollController.dispose();
    _owners.focusState.playlistFilterFocusNode.dispose();
    _owners.focusState.categoryFilterFocusNode.dispose();
    _owners.focusState.contentTypeFocusNode.dispose();
    _owners.focusState.spotlightCategoryOptionsFocusNode.dispose();
    _owners.focusState.spotlightPrimaryFocusNode.dispose();
    _owners.focusState.spotlightRailScope.dispose();
    _owners.focusState.spotlightHeroScope.dispose();
    _owners.focusState.spotlightSportsScope.dispose();
    _owners.previewState.previewShown.dispose();
    _owners.previewState.spotlightProgrammeShown.dispose();
    _owners.previewState.previewShowing.dispose();
    _owners.previewState.previewEpoch.dispose();
    _owners.previewState.previewStreamUrl.dispose();
    for (final node in _owners.focusState.cardFocusNodes.values) {
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
  static String formatLoadBytes(int bytes) =>
      IptvLoadStatusPolicy.formatLoadBytes(bytes);

  @visibleForTesting
  static String formatLoadElapsed(Duration d) =>
      IptvLoadStatusPolicy.formatLoadElapsed(d);

  /// "12.4 / 50.0 MB" when the transfer is observable, "42.1 MB" when only the
  /// landed size is known, null when there is no honest number to show — a
  /// buffered fetch that has not landed yet must not imply progress it cannot
  /// measure.
  @visibleForTesting
  static String? loadBytesLabel(int? bytes, int? totalBytes) =>
      IptvLoadStatusPolicy.loadBytesLabel(bytes, totalBytes);

  /// Whether a stage owning [incoming] may take the chip from [current].
  /// Pure, so the priority rule is testable without pumping the page.
  @visibleForTesting
  static bool chipClaimAllowed(int current, int incoming) =>
      IptvLoadStatusPolicy.chipClaimAllowed(current, incoming);

  /// Priority ranks, exposed for the same reason.
  @visibleForTesting
  static int get chipRankNone => IptvLoadStatusPolicy.chipRankNone;
  @visibleForTesting
  static int get chipRankGuide => IptvLoadStatusPolicy.chipRankGuide;
  @visibleForTesting
  static int get chipRankMaintenance =>
      IptvLoadStatusPolicy.chipRankMaintenance;
  @visibleForTesting
  static int get chipRankRefresh => IptvLoadStatusPolicy.chipRankRefresh;

  /// Pure decision behind [_landingCategory], split out for tests.
  @visibleForTesting
  static String? landingCategoryFor({
    required String? orderKey,
    required List<String> categories,
    required bool manuallyChosen,
    required bool searching,
  }) => IptvLandingPolicy.landingCategoryFor(
    orderKey: orderKey,
    categories: categories,
    manuallyChosen: manuallyChosen,
    searching: searching,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sections.playback.previewHandoff.flushPreviewRearm();
      // Android schedules fire NATIVELY (alarm → service) — no in-process
      // revision bump can see that. Coming back to the foreground is the
      // one reliable moment to reconcile the rail's Scheduled badge and the
      // stage's Record↔Stop state.
      unawaited(_sections.recordings.recordingSupport.refreshScheduledCount());
      unawaited(
        _sections.recordings.androidRecording.refreshAndroidRecordingState(),
      );
    }
  }

  /// Focus the first filter (for DPAD navigation from search input)
  @override
  void focusFirstFilter() {
    if (_owners.selectionState.spotlightLayoutMode ==
        IptvSpotlightLayoutMode.wide) {
      _sections.spotlight.spotlightFocus.focusSpotlightSources();
    } else {
      _owners.focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  @override
  void focusSearchResults() {
    if (_owners.selectionState.spotlightLayoutMode !=
        IptvSpotlightLayoutMode.classic) {
      _sections.spotlight.spotlightFocus.focusSpotlightSearchResults();
    } else {
      focusFirstFilter();
    }
  }

  /// Refresh playlists from storage (call after settings change)
  Future<void> refreshPlaylists() async {
    await _sections.catalog.settingsLoading.loadSettings();
  }

  @override
  Widget build(BuildContext context) =>
      _sections.standardLayouts.rootLayout.build(context);
}

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
  })
  refreshCatalog,
  Future<void> Function(
    IptvPlaylist,
    int,
    CatalogSnapshot, {
    String? warning,
    bool migrateFavorites,
  })
  presentDbCatalog,
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
})
iptvResultsViewTestAccess(IptvResultsViewState state) => (
  browse: state._sections.browsing.playerBrowse.providePlayerIptvBrowse,
  loadPlaylist: state._sections.catalog.catalogLoading.loadPlaylist,
  chooseCategory: state._sections.browsing.filtersSection.onCategoryChanged,
  refreshCatalog: state._sections.catalog.catalogRefresh.applyDbCatalogRefresh,
  presentDbCatalog:
      state._sections.catalog.catalogPresentation.presentDbCatalog,
  focusNodeFor: state._sections.previewAndSelection.rowProjection.focusNodeFor,
  rowAttached: state._sections.previewAndSelection.rowProjection.rowAttached,
  allChannels: state._owners.catalogState.allChannels,
  filteredChannels: state._owners.catalogState.filteredChannels,
  playlists: state._owners.settingsState.playlists,
  selectedPlaylist: state._owners.settingsState.selectedPlaylist,
  selectedCategory: state._owners.catalogState.selectedCategory,
  snapshot: state._owners.catalogState.dbSnapshot,
  focusNodes: state._owners.focusState.cardFocusNodes,
  detachedRows: state._owners.focusState.detachedRows,
  previewShown: state._owners.previewState.previewShown,
  programmeShown: state._owners.previewState.spotlightProgrammeShown,
  loadTicket: state._owners.catalogState.loadTicket,
  landingSeedArmed: state._owners.catalogState.landingSeedArmed,
  categoryManuallyChosen: state._owners.catalogState.categoryManuallyChosen,
);
