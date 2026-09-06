import '../widgets/see_all/discover_browsing_input.dart';
import '../services/home_catalog_refresh.dart';
import '../services/home_load_deadline.dart';
import '../widgets/home/home_row_focus.dart';
import '../widgets/home/home_continuation_focus.dart';
import '../widgets/home/catalog_continuation_button.dart';
import '../services/home_row_refresh.dart';
import '../services/profiles/connection_resource_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/advanced_search_selection.dart';
import '../theme/app_theme_scope.dart';
import '../theme/artwork_accent.dart';
import '../utils/home_rail_metrics.dart';
import '../utils/platform_util.dart';
import '../utils/tvos_device.dart';
import '../models/debrify_tv/channel.dart';
import '../models/home_collection.dart';
import '../models/iptv_playlist.dart';
import '../models/play_loader_art.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../models/stremio_tv/stremio_tv_channel.dart';
import '../models/stremio_tv/stremio_tv_now_playing.dart';
import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/analytics_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/discover_prefs.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/engine/settings_manager.dart';
import '../services/episode_artwork_service.dart';
import '../services/home_collection_rows.dart';
import '../services/home_collections_store.dart';
import '../services/home_list_rows.dart';
import '../services/home_row_order.dart';
import '../services/filtered_catalog_pager.dart';
import '../services/hide_watched_prefs.dart';
import '../services/watched_filter.dart';
import '../services/watched_status_service.dart';
import '../services/iptv_cw_router.dart';
import '../services/iptv_media_store.dart';
import '../services/local_bound_source_service.dart';
import '../services/main_page_bridge.dart';
import '../models/profiles/profile_policy.dart';
import '../services/profiles/profile_policy_guard.dart';
import '../services/playlist_player_service.dart';
import '../services/premiumize_service.dart';
import '../services/profiles/profile_session_memory.dart';
import '../services/series_source_service.dart';
import '../services/stremio_iptv_service.dart';
import '../services/stremio_service.dart';
import '../services/next_episode_service.dart';
import '../services/episode_tracker_snapshot_revision.dart';
import '../services/local_series_completion_service.dart';
import '../services/source_priority.dart';
import '../services/storage_service.dart';
import '../services/tv_hero_artwork_quality_controller.dart';
import '../services/tvos_top_shelf_service.dart';
import '../services/torbox_service.dart';
import '../services/torrent_bulk_add_service.dart';
import '../services/torrent_playback_service.dart';
import '../services/torrent_service.dart';
import '../services/simkl/simkl_continue_watching_service.dart';
import '../services/trakt/trakt_continue_watching_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/simkl/simkl_service.dart';
import '../services/video_player_launcher.dart';
import '../services/tracking_source_policy.dart';
import '../utils/concurrency.dart';
import '../utils/continue_watching_presentation.dart';
import '../utils/dialog_tap_guard.dart';
import '../utils/episode_progress_merge.dart';
import '../utils/format_tag_detector.dart';
import '../utils/torrent_filter_matcher.dart';
import '../utils/tv_keys.dart';
import '../utils/tv_search_focus_handoff.dart';
import '../services/app_route_observer.dart';
import '../services/imdb_trailer_service.dart';
import '../services/youtube_service.dart';
import '../widgets/add_source_picker_dialog.dart';
import '../widgets/debrid_action_sheet.dart';
import '../widgets/hero_trailer_backdrop.dart';
import '../widgets/home/cw_card_menu.dart';
import '../widgets/home/card_focus_rise.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/home/row_tag_pill.dart';
import '../widgets/home/spotlight_board.dart';
import '../widgets/movie_watched_badge.dart';
import '../widgets/search_loading_animation.dart';
import '../widgets/skeleton_poster.dart';
import '../widgets/source_row.dart';
import '../widgets/torrent_filters_sheet.dart';
import '../widgets/torrent_result_row.dart';
import '../widgets/tv_text_field.dart';
import 'collections/collection_folder_screen.dart';
import 'iptv/xtream_series_detail.dart';
import 'playlist_content_view_screen.dart';
import 'see_all/catalog_see_all_screen.dart';
import 'see_all/continue_watching_see_all_screen.dart';
import 'see_all/trakt_see_all_screen.dart';
import 'see_all/simkl_see_all_screen.dart';
import 'see_all/mdblist_see_all_screen.dart';
import 'see_all/mdblist_lists_see_all_screen.dart';
import '../widgets/see_all/mdblist_list_card.dart';
import '../services/mdblist/mdblist_list_source.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/mdblist/mdblist_continue_watching_service.dart';
import '../services/mdblist/mdblist_sync_coordinator.dart';
import '../services/mdblist/mdblist_models.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../widgets/see_all/stremio_dropdown.dart';
import '../widgets/see_all/discover_detail_rail.dart';
import '../widgets/see_all/discover_card_settings_scope.dart';
import '../widgets/see_all/discover_shelf_scope.dart';
import '../widgets/see_all/discover_trailer_stage.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import 'catalog_item_detail_screen.dart';
import 'merged_series_detail_screen.dart';
import 'settings/tv_home_style_page.dart'
    show effectiveOffTvHomeStyle, shouldUseOffTvSpotlightShell;
import 'debrid_downloads_screen.dart';
import 'episodes_screen.dart';
import 'stremio_tv/stremio_tv_service.dart';
import 'stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import 'torbox/torbox_downloads_screen.dart';
import 'premiumize/premiumize_files_screen.dart';
import 'alldebrid/alldebrid_files_screen.dart';
import 'pikpak/pikpak_files_screen.dart';

part 'search/search_sources.dart';
part 'search/search_card_widgets.dart';
part 'search/search_hero_widgets.dart';
part 'search/search_stage_widgets.dart';

/// TV focus ring for board cards — violet-300, deliberately LIGHTER than the
/// board's chrome accent: a light ring over dark art pops at 10ft, while the
/// deep accent stays for chrome (tags, sidebar). Pairs with the calm 1.045
/// scale. (The old kStremioAccent/kStremioBg palette constants now live in
/// the app theme as `app.home.chromeAccent` / `app.home.bg`.)
const Color kStremioFocusRing = kCardFocusRing;

/// Continue Watching progress-bar fill (Stremio shows a white line; we use red).
const Color _kCwProgressRed = Color(0xFFE50914);

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch as
/// the user scrolls, and how many items to keep per row. Enumerating catalogs is
/// free (manifest metadata) — only fetching each row's items costs a call — so we
/// list every catalog up front and lazily pull batches on scroll (Stremio-style)
/// instead of a hard global row cap.
const int _kBoardBatchSize = 8;

/// When a row's horizontal scroll gets within this many pixels of the end, the
/// next page for that catalog is fetched (Stremio-style unlimited rows).
const double _kRowLoadMoreThreshold = 900;

/// Format a season/episode as a compact 'S2 · E5' label, or null when unknown.
String? _seLabel(int? season, int? episode) {
  if (season == null || episode == null || season <= 0 || episode <= 0) {
    return null;
  }
  return 'S$season · E$episode';
}

/// Dedicated Search tab.
///
/// * CATALOG mode — a Stremio-style board (one horizontal row per addon
///   catalog) with a hero spotlight that reflects the focused title; typing a
///   query searches every searchable addon and shows one horizontal row of
///   results per addon (same board layout).
/// * KEYWORD mode — raw torrent search → tap a result to add/play.
/// * LISTS mode — MDBList public-list search, isolated from title catalogs.
///
/// All playback (catalog auto-best, sources list, keyword) runs in-tab through
/// the isolated [TorrentPlaybackService]; the Home engine is never invoked.
class SearchScreen extends StatefulWidget {
  final bool isTelevision;

  /// Dedicated-search-tab mode (TV only). When true the screen is *only* the
  /// search field + Catalog/Keyword/Lists selector over a blank prompt until
  /// the user types — no hero/board. When false it's the "Home New" board
  /// (chrome-free on TV; persistent search bar on desktop/mobile).
  final bool searchMode;

  /// Discover-tab mode. A single browsable grid with a "Source" dropdown
  /// (Continue Watching / Trakt / …) instead of the board's stacked rails —
  /// reuses this screen's item-open/play handlers and cached CW/Trakt rows.
  final bool discoverMode;

  const SearchScreen({
    super.key,
    this.isTelevision = false,
    this.searchMode = false,
    this.discoverMode = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Mode { catalog, keyword, lists }

/// Snapshot of an in-progress keyword search, preserved across a tab switch so
/// returning restores results + scroll instead of a blank prompt — the nav
/// rebuilds [SearchScreen] fresh on every switch (main.dart `_buildPage`).
/// Mirrors the old `TorrentSearchScreen._preservedState`. Keyed by [variant] so
/// a keyword search started on the Home-New board never restores into the
/// dedicated Search tab (both are [SearchScreen] instances).
class _KwPreservedState {
  final String variant;
  final String query;
  final List<Torrent> all;
  final List<Torrent> results;
  final TorrentFilterState filters;
  final String sort;
  final bool sortAsc;
  final Map<String, List<String>> cache;
  final bool cachedOnly;
  final Map<String, int> directCounts;
  final Map<String, int> torrentCounts;
  final Set<String> selectedDirect;
  final Set<String> selectedTorrent;
  final String? sourceTab;
  final double scrollOffset;
  const _KwPreservedState({
    required this.variant,
    required this.query,
    required this.all,
    required this.results,
    required this.filters,
    required this.sort,
    required this.sortAsc,
    required this.cache,
    required this.cachedOnly,
    required this.directCounts,
    required this.torrentCounts,
    required this.selectedDirect,
    required this.selectedTorrent,
    required this.sourceTab,
    required this.scrollOffset,
  });
}

/// Fixed Discover sources; installed addons are appended dynamically (key
/// 'a:{addonId}').
const String _discCw = 'cw';
const String _discTrakt = 'trakt';
const String _discSimkl = 'simkl';
const String _discMdblist = 'mdblist';
const String _discAddonPrefix = 'a:';

/// Whether an asynchronously loaded Discover landing source may still update
/// the screen. Public only so the lifecycle contract has a focused regression
/// test; production callers are confined to this file.
bool discoverLandingLoadIsCurrent({
  required int capturedRevision,
  required int currentRevision,
  required bool hasPendingHandoff,
}) => !hasPendingHandoff && capturedRevision == currentRevision;

// Metrics for the inline caption under an [_ArtPoster] (the favourites rails).
// Kept as the single source of truth so anything reserving vertical space for
// the caption (the cell height, the hero's row-reserve budget) can't drift from
// the widget's own layout.
const double _kArtTitleGap = 10;
const double _kArtTitleFontSize = 14;
const double _kArtTitleHeight = 1.25;
const int _kArtTitleMaxLines = 2;

/// Height of the caption band under an [_ArtPoster]: the gap plus its up-to-two
/// lines at the current text scale.
double _artPosterCaptionBand(BuildContext context) =>
    _kArtTitleGap +
    MediaQuery.textScalerOf(context).scale(_kArtTitleFontSize) *
        _kArtTitleHeight *
        _kArtTitleMaxLines;

// Metrics for the Canvas bottom column (rail tabs + shelf). Same contract as
// the caption band above: the widgets and the identity block that has to stay
// CLEAR of them read the same numbers, so neither can drift into the other.
// (It drifted once: growing the shelf box by the caption band silently ate the
// identity's whole clearance and the tabs landed on the synopsis.)
const double _kCanvasTabFontSize = 12.5;
const double _kCanvasTabUnderlineGap = 6;
const double _kCanvasTabUnderline = 2.5;

/// Floor for the tab row: the stacked chevron pair beside the labels — two
/// 13px icons (the second is only translated, so it still occupies its line)
/// plus 1px of bottom padding.
const double _kCanvasTabChevronColumn = 27;

/// Gap between the tab row and the shelf below it.
const double _kCanvasTabsGap = 12;

/// Trailing spacer under the shelf, holding it off the screen edge.
const double _kCanvasShelfTail = 22;

/// Slack inside the shelf box, on top of the cell height — the cells centre
/// in it, so a focused card's scale-up isn't clipped at the box edges.
const double _kCanvasShelfSlack = 10;

/// Breathing room between the identity block's bottom and the tab row's top.
const double _kCanvasIdentityGap = 25;

/// Smallest poster art a stage rail will draw before it is simply too small
/// to recognise — the floor every derived rail box respects.
const double _kStageMinPosterH = 56;

// TONIGHT metrics. The rail zone is reserved first and the main zone takes
// what is left, so a short board shrinks the card and drops queue rows rather
// than overlapping them.
const double _kTonightPadX = 48;
const double _kTonightZoneGap = 22;
const double _kTonightRailTail = 24;
const double _kTonightTitleSize = 26;
const double _kTonightHeaderPad = 34;
const double _kTonightRowGap = 12;
const double _kTonightRowMaxH = 118;
const double _kTonightQueueMinW = 260;
const double _kTonightCardRadius = 14;

/// The most of a queue row's width the still may take. The rest is the title
/// and episode, which is what the row exists to tell you.
const double _kTonightThumbShare = 0.40;

// DECK metrics.
const double _kDeckPanelPad = 48;
const double _kDeckCardRightPad = 36;
const double _kDeckCardRadius = 22;
const double _kDeckRailGap = 18;
const double _kDeckRailTail = 26;

// MOSAIC metrics. The head band is a FIXED height so the wall below it never
// shifts when a title's logo is taller than the last one's.
const double _kMosaicPadX = 48;
const double _kMosaicGap = 16;
const double _kMosaicHeadTop = 26;

/// The identity band's height is DERIVED from the scaled content it holds —
/// a fixed band clipped the logo and its meta line at large text scales.
double _mosaicHeadHeight(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  // A title with no logo art falls back to TEXT, which scales — the band has
  // to reserve whichever of the two is taller.
  final titleH = max(_kMosaicLogoH, t.scale(_kStageHeadlineTitleSize) * 1.25);
  // Facts line, then the genres on their own line beneath it. The right-hand
  // column (rail label + hold hint) is shorter than that, so the identity
  // still sets the band's height.
  return titleH + 10 + t.scale(12.5) * 1.4 + 6 + t.scale(12.5) * 1.4 + 6;
}

const double _kMosaicLogoH = 52;

/// The headline variant's text fallback is smaller than a stage title — it is
/// a caption over a wall, not a billboard. Shared with [_mosaicHeadHeight] so
/// the band that reserves space for it can't drift.
const double _kStageHeadlineTitleSize = 24;
const double _kMosaicHeadGap = 18;

// ATRIUM metrics. The wall's height is DERIVED from these (never guessed),
// so the dossier column beside it can't be crowded by a taller row.
const double _kAtriumSplit = 0.38;
const double _kAtriumPanelPad = 48;
const double _kAtriumWallPad = 40;
const double _kAtriumLabelFontSize = 12.0;
const double _kAtriumLabelGap = 10;
const double _kAtriumRowGap = 18;
const double _kAtriumWallTail = 26;

/// The share of the board Atrium's two-row wall may occupy. The row box is
/// derived from what fits inside this, so scaled labels shrink the posters
/// rather than pushing the wall off the bottom.
const double _kAtriumWallBudget = 0.64;

double _atriumLabelHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(_kAtriumLabelFontSize) * 1.35;

// Metrics for the PROMENADE bottom column (centred rail label + strip). Same
// single-source-of-truth contract as the Canvas block above: the widgets and
// the identity block that must stay clear of them read the same numbers.
const double _kPromLabelFontSize = 12.0;

/// Gap between the centred rail label and the strip below it.
const double _kPromLabelGap = 14;

/// Trailing spacer under the strip.
const double _kPromStripTail = 24;

/// Air between the identity block and the label row under it.
const double _kPromIdentityGap = 26;

/// Dim painted over every strip cell that isn't focused, so the centre-locked
/// cell reads as the lit one. A flat fill inside the card's own clip (see
/// [CardFocusRise.restVeil]) — no Opacity, no saveLayer.
const Color _kPromRestVeil = Color(0x8C0D0B1A);

/// Height of Promenade's centred label row at the current text scale (the
/// chevron column is the floor, exactly as in [_canvasTabsHeight]).
double _promenadeLabelHeight(BuildContext context) => max(
  _kCanvasTabChevronColumn,
  MediaQuery.textScalerOf(context).scale(_kPromLabelFontSize) * 1.35,
);

/// Discover STAGE: the air between the identity block and the shelf column
/// below it. The block's clearance is [DiscoverShelfMetrics.columnHeight] plus
/// this — derived from what the shelf actually occupies, never guessed.
const double _kDiscStageIdentityGap = 22;

/// Discover STAGE: the band the quiet filter line owns at the top of the
/// panel — its 16px top padding, one line of segments and its 10px tail,
/// measuring ~56, plus a little air. It never needs a second row: the quiet
/// bar scrolls its segments horizontally rather than wrapping.
const double _kDiscStageFilterBand = 62;

/// Height of the Canvas rail-tab row at the current text scale.
double _canvasTabsHeight(BuildContext context) => max(
  _kCanvasTabChevronColumn,
  MediaQuery.textScalerOf(context).scale(_kCanvasTabFontSize) * 1.35 +
      _kCanvasTabUnderlineGap +
      _kCanvasTabUnderline,
);

/// Intent for a left-arrow on the search field, remapped (via a [Shortcuts]
/// override closer than the default text-editing shortcuts) so an empty field
/// escapes to the sidebar instead of the EditableText silently eating the key.
class _SearchLeftIntent extends Intent {
  const _SearchLeftIntent();
}

/// Escapes an *empty* TV search field to the sidebar on left-arrow. It disables
/// itself the moment there's text, so [Shortcuts] falls through to the default
/// caret/selection handling — meaning the wrapper can stay mounted at all times
/// (a stable subtree root) without the action ever swallowing a real caret move.
class _EmptyFieldLeftAction extends Action<_SearchLeftIntent> {
  _EmptyFieldLeftAction(this._controller, this._onEscape);

  final TextEditingController _controller;
  final VoidCallback _onEscape;

  @override
  bool isEnabled(_SearchLeftIntent intent) => _controller.text.isEmpty;

  @override
  Object? invoke(_SearchLeftIntent intent) {
    _onEscape();
    return null;
  }
}

class _SearchScreenState extends State<SearchScreen>
    with RouteAware, WidgetsBindingObserver {
  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get _tabIndex => widget.searchMode ? 17 : (widget.discoverMode ? 18 : 15);

  final StremioService _stremio = StremioService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search_field');
  final TvSearchFocusHandoff _searchSubmitFocus = TvSearchFocusHandoff();
  // DPAD focus targets for the Catalog / Keyword / Lists selector, so the
  // toggle is reachable with a remote (arrow-up from the search field).
  final FocusNode _modeCatalogNode = FocusNode(debugLabel: 'mode_catalog');
  final FocusNode _modeKeywordNode = FocusNode(debugLabel: 'mode_keyword');
  final FocusNode _modeListsNode = FocusNode(debugLabel: 'mode_lists');
  final FocusNode _modeDropdownNode = FocusNode(debugLabel: 'mode_dropdown');

  // Dedicated MDBList list-search state. Lists is its own Search mode; it
  // never runs as part of Catalog search. Each result card hands off via
  // MainPageBridge.pendingMdblistListOpen. One focus node per card.
  String _listsQuery = '';
  List<MdblistListChoice> _listsResults = const [];
  bool _listsSearching = false;
  String? _listsError;
  int _listsToken = 0;
  final List<FocusNode> _listsNodes = [];
  // Debounce for opening a list from the rail — one fast double-press must not
  // stack two pushed item screens (TV) / double-fire the handoff.
  DateTime? _lastListOpenAt;

  _Mode _mode = _Mode.catalog;

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  String _catalogQuery = '';
  Timer? _catalogDebounce;

  /// The addon that produced the item currently being played/browsed, threaded
  /// into playback so Continue Watching can route resume / next-episode back to
  /// it (matching Home's `addonId`). Set whenever we open a catalog item.
  String? _activeAddonId;

  // Keyword torrent-search state (submit-based).
  bool _kwLoading = false;
  String? _kwError;
  String _kwQuery = '';
  List<Torrent> _kwAll = []; // unfiltered results from the last search
  List<Torrent> _kwResults = []; // filtered + sorted view actually rendered
  final List<FocusNode> _kwNodes = [];
  // Keyboard/DPAD focus targets for the keyword toolbar pills (Sort / Filters /
  // Providers / Sources / Select). A fixed pool of 5 covers the most pills ever
  // shown.
  final List<FocusNode> _kwToolbarNodes = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'kw_tb_$i'),
  );
  TorrentFilterState _kwFilters = const TorrentFilterState.empty();
  String _kwSort = 'relevance';
  // Sort direction for _kwSort (ignored for 'relevance', which is engine order).
  // Defaults follow each field's natural direction; the sort dialog can flip it.
  bool _kwSortAsc = false;
  Map<String, List<String>> _kwCache = {}; // infohash(lower) → ['TB','PM']

  // Provider (stream-type) multi-select filter, ported from the old search
  // screen: results are grouped into "Direct" (direct/external URL streams) and
  // "Torrent" providers by their [Torrent.source], each independently filterable
  // by which sources are ticked. Empty count maps mean "no such group".
  Map<String, int> _kwDirectCounts = {}; // source → count (direct/external)
  Map<String, int> _kwTorrentCounts = {}; // source → count (torrents)
  Set<String> _kwSelectedDirect = {};
  Set<String> _kwSelectedTorrent = {};

  /// True when the results list is being narrowed to TorBox-cached torrents
  /// only (TorBox is the sole usable debrid provider and its cache-check is on)
  /// — mirrors the old screen's `_showingTorboxCachedOnly`. Drives the banner.
  bool _kwCachedOnly = false;

  // Bulk-selection state for keyword results (mirrors Home's multi-select).
  bool _kwSelectionMode = false;
  final Set<String> _kwSelected = {}; // selected torrent infohashes

  /// Monotonic token so a slow earlier keyword search can't clobber a newer one.
  int _kwSearchToken = 0;

  /// Infohashes already dispatched to a provider cache-check for the current
  /// keyword search. Lets each streaming batch check only its fresh hashes.
  final Set<String> _kwCacheChecked = {};

  /// Whether a TorBox cache-check has successfully run this keyword search —
  /// the precondition for cached-only mode (never hide rows on a thrown check).
  bool _kwTbRan = false;

  /// In-flight per-batch cache-check futures for the current search. The
  /// completion sweep awaits these so cached-only mode is decided only once
  /// every batch's badges have landed.
  final List<Future<void>> _kwPendingChecks = [];

  // Cache-check config, resolved ONCE per keyword search (freshly re-read each
  // search, then reused across its streaming batches — no per-batch storage
  // reads). Same gating as Home: pref on AND integration on AND key present.
  bool _kwTbOn = false;
  bool _kwPmOn = false;
  String? _kwTbKey;
  String? _kwPmKey;
  bool _kwOtherProviderActive = false;

  /// Reads the cache-check gating and whether any usable non-TorBox provider
  /// is active. Awaited at the top of each search so streaming batch checks
  /// see up-to-date settings.
  Future<void> _loadKwCacheConfig() async {
    final r = await Future.wait([
      StorageService.getTorboxCacheCheckEnabled(),
      StorageService.getTorboxIntegrationEnabled(),
      StorageService.getTorboxApiKey(),
      StorageService.getPremiumizeCacheCheckEnabled(),
      StorageService.getPremiumizeIntegrationEnabled(),
      StorageService.getPremiumizeApiKey(),
      StorageService.getApiKey(),
      StorageService.getRealDebridIntegrationEnabled(),
      StorageService.getAllDebridApiKey(),
      StorageService.getAllDebridIntegrationEnabled(),
      StorageService.getPikPakEnabled(),
    ]);
    final tbKey = r[2] as String?;
    final pmKey = r[5] as String?;
    final rdKey = r[6] as String?;
    final adKey = r[8] as String?;
    _kwTbOn = (r[0] as bool) && (r[1] as bool) && (tbKey?.isNotEmpty ?? false);
    _kwPmOn = (r[3] as bool) && (r[4] as bool) && (pmKey?.isNotEmpty ?? false);
    _kwTbKey = tbKey;
    _kwPmKey = pmKey;
    final rdActive = (r[7] as bool) && (rdKey?.isNotEmpty ?? false);
    final pmActive = (r[4] as bool) && (pmKey?.isNotEmpty ?? false);
    final adActive = (r[9] as bool) && (adKey?.isNotEmpty ?? false);
    final pikpakActive = r[10] as bool;
    _kwOtherProviderActive = rdActive || pmActive || adActive || pikpakActive;
  }

  // ── Streaming keyword search (per-engine batches, Sources-list parity) ──
  /// Raw per-engine batches accumulated this search; merged provisionally so
  /// first rows paint as soon as the fastest engine answers.
  final List<List<Torrent>> _kwBatches = [];

  /// True while the awaited search is still in flight (drives the "still
  /// searching" strip). Distinct from [_kwLoading], which only covers the
  /// full-screen loader up to the FIRST batch.
  bool _kwSearching = false;

  /// Set on the first real user interaction (scroll drag, row DPAD nav, row
  /// tap/long-press, toolbar use) — later arrivals then park in [_kwPending]
  /// behind the "+N new results" pill instead of reshuffling the list.
  bool _kwStreamFrozen = false;

  /// Full (unfiltered) result set parked while frozen; adopted by the pill,
  /// any toolbar action, or a source-tab tap.
  List<Torrent>? _kwPending;

  /// DPAD focus for the "+N new results" pill.
  final FocusNode _kwPillFocus = FocusNode(debugLabel: 'kw_pill');

  /// DPAD focus for the pre-search "Sources" button (shown in the empty
  /// keyword state before a query). Without its own node it's a bare InkWell
  /// unreachable by the remote — you couldn't pick sources before searching.
  final FocusNode _kwSourcesBtnFocus = FocusNode(debugLabel: 'kw_sources_btn');

  /// DPAD focus for the catalog-mode "Sources" button (empty-prompt state) —
  /// its keyword-mode twin, for picking which searchable addons are queried.
  final FocusNode _catalogSourcesBtnFocus = FocusNode(
    debugLabel: 'catalog_sources_btn',
  );

  /// Whether the unified (non-TV) catalog Sources bar under the field is shown.
  /// Driven by search-field focus with a delayed hide (see
  /// [_onSearchFocusForSources]) so a click on the button isn't lost.
  bool _catalogSourcesBarShown = false;
  Timer? _catalogSourcesHideTimer;

  /// Source tab strip (All / per-source), single-select on top of the
  /// Providers multi-select. Null = All.
  String? _kwSourceTab;
  final List<FocusNode> _kwTabNodes = [];

  /// Provider-group keys ('d:src' / 't:src') already offered this search — a
  /// NEW source auto-selects into the provider filter, but a source the user
  /// unticked stays unticked when a later batch re-reports it.
  final Set<String> _kwProviderSeen = {};

  /// Scroll controller for the keyword results list, so we can preserve/restore
  /// the scroll position across a tab switch (see [_KwPreservedState]).
  final ScrollController _kwScroll = ScrollController();

  /// Last observed keyword-list scroll offset, captured live (the controller is
  /// detached by the time [dispose] runs, so we can't read it there).
  double _kwLastScroll = 0;

  /// Set on restore; the keyword list jumps here once laid out, then clears.
  double? _pendingKwScroll;

  /// Snapshot of the most recently disposed keyword search, kept alive across
  /// a same-profile tab rebuild. The holder rejects content from another
  /// profile/session and participates in profile lifecycle cleanup.
  static final ProfileSessionMemory<_KwPreservedState> _kwPreserved =
      ProfileSessionMemory<_KwPreservedState>();

  /// Captured at mount, not dispose: an outgoing screen may be torn down after
  /// the next profile is published and must still tag its snapshot as outgoing.
  late final ProfileSessionOwner _profileSessionOwner;

  /// Discriminates the three [SearchScreen] variants so a preserved keyword
  /// search only restores into the same kind of tab it came from.
  String get _variantKey => widget.searchMode
      ? 'search'
      : widget.discoverMode
      ? 'discover'
      : 'board';

  /// True when PikPak is the ONLY configured provider. PikPak can't quick-play
  /// (it queues a cloud download), so catalog "Play" is hidden — matching Home.
  bool _pikpakOnly = false;

  /// Experimental flag: route series taps to the merged detail+episodes page.
  /// Loaded once on init; movies and the flag-off path keep the existing flow.
  bool _mergedSeriesPage = false;

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  final Map<String, int> _boundCounts = {};

  // Board state. [_homeSections] is the homepage cache; [_sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  final _catalogContinueNode = FocusNode(debugLabel: 'catalog_continue');
  final _catalogMoreNode = FocusNode(debugLabel: 'catalog_more');
  FocusNode? _catalogReturnFocus;
  bool _catalogContinuing = false;
  int _catalogContinueCursor = 0;
  bool _loading = true;
  String? _error;
  List<CatalogSection> _homeSections = [];
  List<CatalogSection> _sections = [];
  final List<List<FocusNode>> _rowNodes = [];
  // Per-row remembered focus column (leanback-style). DPAD up/down into a row
  // returns to where you left THAT row — the cell it points at is guaranteed
  // mounted, so requestFocus never no-ops on a scrolled-away lazy cell.
  final Map<int, int> _rowCol = {};
  // Board entrance: bumped each time the displayed sections are swapped
  // (initial load, search results in/out), so the first rows replay their
  // one-shot fade/rise entrance. Appends don't bump it.
  int _boardGen = 0;
  DateTime _boardAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _catalogSearching = false;
  int _catalogSearchToken = 0;
  // Catalogs that errored (timeout / HTTP / network) during the current
  // catalog search — distinct from "returned no results". Drives the quiet
  // "N sources didn't respond" note so failing addons don't just vanish.
  int _catalogSearchFailures = 0;

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [_reloadForHomeSettings] when the manager saves.
  Set<String> _homeDisabled = {};

  // The OPT-IN extra rows (Trakt/Simkl list rows, IPTV custom-list rows) from
  // the same manager — default-off, so they live in their own store
  // (`home_extra_rows_v1`). Tracker ids become [HomeListSection]s at the head
  // of the board in [_load]; `iptvlist:` ids drive the IPTV list favourites
  // rows. Refreshed by [_reloadForHomeSettings].
  List<HomeExtraRow> _homeExtras = const [];

  /// The hide-watched switch as of the last board load. Flipping it changes
  /// row membership, so [_reloadForHomeSettings] diffs it like a row toggle.
  bool _hideWatched = HideWatchedPrefs.enabled;

  /// Imported collections — each enabled one is a [HomeCollectionSection] row
  /// of folder tiles. [_homeCollectionsSig] is the store's change token the
  /// settings-changed listener diffs against.
  List<HomeCollection> _homeCollections = const [];
  String _homeCollectionsSig = HomeCollectionsStore.signatureOf(const []);

  /// Stable ids in the user's global Home-row order. Rows not present append
  /// canonically; ids whose backing row is temporarily unavailable stay saved.
  List<String> _homeRowOrder = const [];

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Read in [_load], refreshed by
  /// [_reloadForHomeSettings]; resolved into [_spotlightHeroOverride] by
  /// [_resolveSpotlightHeroSource].
  HomeHeroSource _heroSource = (mode: HomeHeroSourceMode.random, ids: const []);

  /// Whether any Trakt/Simkl list row is opted in — gates the tracker-row
  /// resolve in [_load] and the integrations-triggered reload.
  bool get _trackerExtrasEnabled =>
      _homeExtras.any((r) => HomeExtraRowIds.isTracker(r.id));

  /// Board load generation. [_load] is re-entrant (Home Rows save,
  /// integration connect/disconnect) and mutates shared state
  /// ([_boardRefs]/[_boardCursor]/[_homeSections]); every await inside the
  /// load pipeline re-checks this so a superseded load can neither apply its
  /// stale sections nor advance the new load's cursor.
  int _boardLoadGen = 0;
  bool _boardRefreshing = false;

  /// A triggered board reload arrived while a catalog search was showing its
  /// results — running [_load] then would stomp the search view, so it's
  /// latched here and consumed by [_restoreHome].
  bool _pendingBoardReload = false;

  // Board infinite scroll. Every (addon, catalog) pair is enumerated up front in
  // [_boardRefs] (cheap — manifest metadata, no network), then fetched in batches
  // as the user nears the bottom. [_boardCursor] is the next ref to load; it
  // persists across a search detour so returning to the board keeps its place.
  final List<(StremioAddon, StremioAddonCatalog)> _boardRefs = [];
  int _boardCursor = 0;
  // Updated only when a full board or additional page has been accepted.
  // Refreshes mutate live references, so even overlapping refreshes must use
  // this independent snapshot of the board that is actually displayed.
  HomeBoardSnapshot<(StremioAddon, StremioAddonCatalog), StremioAddon>?
      _committedBoard;
  bool _boardLoadingMore = false;
  final ScrollController _boardScroll = ScrollController();

  /// Whether more board rows remain to lazily load (board mode only — never
  /// during a catalog search, which streams and appends its own rows).
  bool get _boardHasMore =>
      _catalogQuery.isEmpty &&
      !_catalogSearching &&
      _boardCursor < _boardRefs.length;

  // LOCAL Continue Watching rows. Reads the SAME local store Home writes to
  // (StorageService `continue_watching_v1`) — read-only here, so Home is never
  // affected. Split into two recency-ordered rows (Movies, then Series), each
  // shown as a leading board row when non-empty. Removal happens only from the
  // detail screen's action.
  bool _cwEnabled = true;
  List<StremioMeta> _cwMovies = [];
  List<StremioMeta> _cwSeries = [];
  // Movies + series merged in last-watched order (newest first) — the source
  // for the Continue Watching "See All" grid, which filters by type itself.
  List<StremioMeta> _cwAll = [];
  final Map<String, double> _cwProgress = {}; // imdbId → 0..1 watched fraction
  final Map<String, String> _cwEpisode = {}; // imdbId → 'S2 · E5' (series only)
  final Map<String, int> _cwRemainingMinutes = {};
  final Map<String, String> _cwEpisodeArtwork = {};
  final Set<String> _cwIds = {}; // imdbIds currently in Continue Watching
  final Map<String, String?> _cwAddonId = {}; // imdbId → source addon id
  final List<FocusNode> _cwMovieNodes = [];
  final List<FocusNode> _cwSeriesNodes = [];

  // Per-provider "one Continue Watching row" preferences. When a provider is
  // merged, its MOVIES slot carries the combined recency-ordered list (the
  // same `_xxxAll` the See-All grid uses) on the movies node list, and its
  // Series row is suppressed — so row ids, saved Home order, and the
  // hide-rows page keep working off the existing `<provider>:movies` id.
  // Loaded once before the first node sync (each CW loader awaits
  // [_ensureCwMergeFlags]); [_reloadForHomeSettings] re-reads and re-syncs
  // node counts when a toggle changes.
  bool _cwMergeLocal = false;
  bool _cwMergeTrakt = false;
  bool _cwMergeSimkl = false;
  bool _cwMergeMdblist = false;
  Future<void>? _cwMergeFlagsLoad;

  Future<void> _ensureCwMergeFlags() => _cwMergeFlagsLoad ??= () async {
    try {
      final flags = await Future.wait([
        StorageService.getHomeCwMergedRows('local'),
        StorageService.getHomeCwMergedRows('trakt'),
        StorageService.getHomeCwMergedRows('simkl'),
        StorageService.getHomeCwMergedRows('mdblist'),
      ]);
      // Plain assignments: every caller is a CW loader that setStates right
      // after its node sync, so the flags never render stale.
      _cwMergeLocal = flags[0];
      _cwMergeTrakt = flags[1];
      _cwMergeSimkl = flags[2];
      _cwMergeMdblist = flags[3];
    } catch (_) {
      // Keep the split-rows defaults: a failed pref read must never become a
      // failed CW load (this memoized future is awaited by every loader).
    }
  }();

  // IPTV Continue Watching (Xtream VOD movies + series), sourced from the
  // player's own watch history via [IptvCwRouter] — kept separate from the
  // metadata-addon rows above because IPTV items aren't IMDb-keyed, so their
  // progress/episode lookups and routing key off the router's routeKey (stored
  // as the synthetic meta id) instead of an imdbId.
  List<StremioMeta> _iptvCwMovies = [];
  List<StremioMeta> _iptvCwSeries = [];
  final List<FocusNode> _iptvCwMovieNodes = [];
  final List<FocusNode> _iptvCwSeriesNodes = [];
  final Map<String, double> _iptvCwProgress = {}; // routeKey → 0..1
  final Map<String, String> _iptvCwEpisode = {}; // routeKey → 'S2 · E5'
  final Map<String, IptvCwEntry> _iptvCwByKey = {}; // routeKey → routing entry
  int _iptvCwLoadToken = 0;

  /// Monotonic guard so an earlier, slower Continue Watching load (which does
  /// one SharedPreferences round-trip per item) can't finish after a newer one
  /// and dispose the focus nodes / state the newer run just installed.
  int _cwLoadToken = 0;

  /// Set when a real content player launches (any path — in-app route, native
  /// TV activity, external app; never trailers), consumed by
  /// [_refreshAfterPlayback].
  ///
  /// This is what keeps the post-playback refresh from becoming a tax on plain
  /// browsing: Trakt and Simkl each still require multiple paged calls, and
  /// [_refreshAfterPlayback] runs on EVERY detail-page close — so without this
  /// latch, opening a title and pressing Back would hit both tracker APIs. Only
  /// a session that actually played something can have moved a tracker's
  /// position. Tracker rows changed by menu actions (mark watched, remove from
  /// Continue Watching) are refreshed by those handlers directly.
  bool _playedSinceRefresh = false;

  // TRAKT Continue Watching rows ("Trakt Movies" / "Trakt Shows"), fetched live
  // from the Trakt account (no local store). Shown after the local rows when
  // connected + non-empty. Network-loaded on init / integration change,
  // post-playback, and throttled app resume, then cached in memory.
  List<StremioMeta> _traktMovies = [];
  List<StremioMeta> _traktSeries = [];
  // Trakt movies + shows merged in last-watched (paused_at) order — the source
  // for the Trakt Continue Watching "See All" grid.
  List<StremioMeta> _traktAll = [];
  final Map<String, double> _traktProgress = {}; // imdbId → 0..1
  final Map<String, String> _traktEpisode = {}; // imdbId → 'S2 · E5' (series)
  final Map<String, int> _traktRemainingMinutes = {};
  final Map<String, String> _traktEpisodeArtwork = {};
  final Map<String, TraktContinueWatchingItem> _traktByImdb = {};
  final List<FocusNode> _traktMovieNodes = [];
  final List<FocusNode> _traktSeriesNodes = [];

  // SIMKL Continue Watching rows ("Simkl Movies" / "Simkl Shows") — a parallel
  // strip below the Trakt rows, built from the account's paused playback
  // sessions (same `/sync/playback` lists the scrobble resume already fetches).
  // Independent of the Trakt block above so neither can regress the other.
  List<StremioMeta> _simklMovies = [];
  List<StremioMeta> _simklSeries = [];
  List<StremioMeta> _simklAll = []; // paused_at order, for the See-All grid
  final Map<String, double> _simklProgress = {}; // imdbId → 0..1
  final Map<String, String> _simklEpisode = {}; // imdbId → 'S2 · E5' (series)
  final Map<String, String> _simklEpisodeArtwork = {};
  final Map<String, SimklContinueWatchingItem> _simklByImdb = {};
  final List<FocusNode> _simklMovieNodes = [];
  final List<FocusNode> _simklSeriesNodes = [];
  int _simklCwToken = 0;
  List<StremioMeta> _mdblistMovies = [];
  List<StremioMeta> _mdblistSeries = [];
  List<StremioMeta> _mdblistAll = [];
  final Map<String, double> _mdblistProgress = {};
  final Map<String, String> _mdblistEpisode = {};
  final Map<String, MdblistContinueWatchingItem> _mdblistByImdb = {};
  final List<FocusNode> _mdblistMovieNodes = [];
  final List<FocusNode> _mdblistSeriesNodes = [];
  int _mdblistCwToken = 0;
  int _mdblistRevisionRefreshToken = 0;
  // True while a revision-driven delayed CW reload is queued/running, so
  // [_refreshAfterPlayback] can skip its own MDBList reload instead of doing a
  // second full fetch ~1s before the authoritative one lands.
  bool _mdblistRevisionRefreshPending = false;
  // When the last FORCED CW load finished. Covers the slow-device case where
  // the delayed reload completes (clearing the pending flag) while
  // [_refreshAfterPlayback] is still awaiting its local loads — without this
  // it would immediately repeat the full fetch it just skipped for.
  DateTime? _mdblistCwForcedLoadAt;

  bool get _mdblistCwForceFresh {
    final at = _mdblistCwForcedLoadAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 3);
  }

  // Debrify TV favourites — a leading "Debrify TV" row of the user's starred
  // keyword channels, shown between Continue Watching and the catalog rows.
  // Channels have no artwork, so they render as Stremio-shaped cards with a
  // gradient + glyph placeholder (see [_ArtPoster]).
  List<DebrifyTvChannel> _tvFavChannels = [];
  final List<FocusNode> _tvFavNodes = [];

  // Stremio TV favourites — a leading row of the user's starred Stremio
  // "channels" (catalogs treated as TV channels). Each card shows the channel's
  // current now-playing item poster (same time-based rotation as the Home /
  // Stremio TV screens); tapping opens the channel. Loaded once on init.
  List<StremioTvChannel> _stvFavChannels = [];
  final List<FocusNode> _stvFavNodes = [];
  int _stvRotationMinutes = 90;
  int _stvSeriesRotationMinutes = 45;

  // IPTV favourites — a leading row of the user's starred live IPTV channels.
  // Cards show the channel logo (glyph fallback); tapping plays the stream
  // directly via VideoPlayerLauncher (no tab switch). Reloaded whenever list
  // membership or manual order changes.
  List<IptvChannel> _iptvFavChannels = [];
  final List<FocusNode> _iptvFavNodes = [];

  // Debrify's account-independent movie/series watchlist. Full metadata is
  // stored locally and presented as separate movie and series rows, so neither
  // row needs a tracker or catalog network request.
  List<StremioMeta> _watchlistMovieItems = [];
  List<StremioMeta> _watchlistSeriesItems = [];
  final List<FocusNode> _watchlistMovieNodes = [];
  final List<FocusNode> _watchlistSeriesNodes = [];

  // Opted-in IPTV custom lists as Home rows (`iptvlist:` extras), rendered
  // through the favourites-row family after the IPTV favourites row. Rebuilt
  // by [_loadIptvListRows] on init, on Home Rows saves, and whenever
  // [IptvMediaStore.listsRevision] bumps (any list mutation anywhere in the
  // app). Rows own their FocusNodes, reconciled by list id across reloads.
  List<_IptvListRow> _iptvListRows = [];
  int _iptvListRowsLoadToken = 0;

  // Playlist favourites — a leading row of the user's saved playlist items
  // (movies / collections added from search or cloud). Cards show the item
  // poster with resume progress; tapping opens a full action menu (play / play
  // random / view files / favorite / clear progress / launch-on-startup /
  // delete), so this row is a complete playlist manager on its own now that the
  // Home playlist section is being phased out. Loaded once on init.
  List<Map<String, dynamic>> _playlistItems = [];
  final List<FocusNode> _playlistFavNodes = [];
  Map<String, Map<String, dynamic>> _playlistProgress = {};
  Set<String> _playlistFavKeys = {};
  // Guards against launching a second concurrent playback while the first is
  // still resolving links (the menu closes immediately, giving no other cue).
  bool _playlistLaunching = false;

  int _traktCwToken = 0;

  /// Last Trakt CW network attempt. The row is refreshed when the app returns
  /// from the background (where the user may have changed Trakt in another app
  /// or browser), but lifecycle noise within this window is coalesced.
  DateTime? _lastTraktCwRefreshAttemptAt;
  static const Duration _traktCwResumeRefreshInterval = Duration(seconds: 30);

  /// Whether a Trakt Continue Watching fetch is currently in flight for a
  /// connected account. While true — and there are no real Trakt rows to show
  /// yet — the Trakt slot is held open with skeleton placeholders (see
  /// [_traktReserving]) so the real rows fill in place instead of inserting
  /// mid-board and shoving everything below them down. Set at the start of each
  /// load and cleared on every terminal path, so a mid-session connect (which
  /// re-runs the load) reserves the slot again.
  bool _traktCwLoading = false;

  /// TV auto-focus "settle to the top" state. On arrival the board focuses the
  /// best card available immediately (an addon row if the Trakt rows above it
  /// are still loading), remembering that node in [_autoFocusedNode]. As higher
  /// rows load (Trakt, local Continue Watching), focus slides up to the new top
  /// card — but only while the user is idle (focus still sits on the node we
  /// placed). The instant the user moves focus themselves, [_autoFocusSettled]
  /// latches and we never touch focus again.
  FocusNode? _autoFocusedNode;
  bool _autoFocusSettled = false;

  /// Coalesces auto-focus passes: multiple content loads finishing in one frame
  /// schedule a single post-frame placement (which reads the final top after all
  /// their setStates apply), instead of racing several callbacks whose
  /// primaryFocus reads haven't caught up to each other's requestFocus.
  bool _autoFocusScheduled = false;

  /// Whether Trakt is connected — gates the Trakt-syncing detail quick actions
  /// (watchlist / collection / watched / rate / list). App actions (Select
  /// Source, Add to Stremio TV, Search Packs) show regardless.
  bool _isTraktAuthenticated = false;

  /// Whether Simkl is connected — gates the Simkl detail quick actions,
  /// rendered as their own strip alongside Trakt's (see [_isTraktAuthenticated]).
  bool _isSimklAuthenticated = false;

  /// Whether MDBList is connected — gates the MDBList entry in the Discover
  /// source dropdown (hidden when disconnected, so an unauthed user isn't shown
  /// a dead source; kept visible if it's somehow the active source).
  bool _isMdblistAuthenticated = false;

  /// The Progress source, mirrored for the CW card lookups below. Smart until
  /// the first load resolves it (Smart = every row keeps its own numbers,
  /// which is also the pre-Tracking behaviour).
  WatchProgressSource _cwProgressSource = WatchProgressSource.smart;

  /// Continue Watching cards show the title from whichever row owns it, but
  /// the PROGRESS comes from the selected Progress source — so a card can
  /// never advertise a resume point the detail page and Play button refuse to
  /// honour. In Smart mode each row keeps its own numbers (legacy behaviour);
  /// in a dedicated mode a title the chosen source doesn't know simply renders
  /// as a plain poster. IPTV rows are exempt: they are routeKey-keyed player
  /// history that no tracker can describe.
  double? _cwCardProgress(_CwKind kind, StremioMeta item) =>
      _cwCardMaps(kind).progress[item.imdbId];

  String? _cwCardEpisode(_CwKind kind, StremioMeta item) =>
      _cwCardMaps(kind).episode[item.imdbId];

  int? _cwCardRemainingMinutes(_CwKind kind, StremioMeta item) =>
      _cwCardMaps(kind).remaining?[item.imdbId];

  ({
    Map<String, double> progress,
    Map<String, String> episode,
    Map<String, int>? remaining,
  })
  _cwCardMaps(_CwKind kind) {
    final effective = kind == _CwKind.iptv
        ? kind
        : switch (_cwProgressSource) {
            WatchProgressSource.smart => kind,
            WatchProgressSource.local => _CwKind.local,
            WatchProgressSource.trakt => _CwKind.trakt,
            WatchProgressSource.simkl => _CwKind.simkl,
            WatchProgressSource.mdblist => _CwKind.mdblist,
          };
    return switch (effective) {
      _CwKind.local => (
        progress: _cwProgress,
        episode: _cwEpisode,
        remaining: _cwRemainingMinutes,
      ),
      _CwKind.trakt => (
        progress: _traktProgress,
        episode: _traktEpisode,
        remaining: _traktRemainingMinutes,
      ),
      _CwKind.simkl => (
        progress: _simklProgress,
        episode: _simklEpisode,
        remaining: null,
      ),
      _CwKind.mdblist => (
        progress: _mdblistProgress,
        episode: _mdblistEpisode,
        remaining: null,
      ),
      _CwKind.iptv => (
        progress: _iptvCwProgress,
        episode: _iptvCwEpisode,
        remaining: null,
      ),
    };
  }

  // Addons that produced homepage rows, indexed by id, so a Continue Watching
  // tap can route back through the right addon (for Episodes / next-episode).
  final Map<String, StremioAddon> _addonsById = {};

  /// The leading Continue Watching rows to render, in order: local Movies /
  /// Series (when enabled), then Trakt Movies / Shows (when connected). Only
  /// non-empty groups are included. Each row carries its own progress lookup
  /// and open / quick-play handlers so local and Trakt sources coexist.
  List<_CwRow> get _cwRows => [
    // Merged providers ship their combined list through the MOVIES slot (same
    // row id, same node list — see the merge-pref field comment); the episode
    // and artwork lookups are imdbId-keyed maps that only hold series entries,
    // so passing movies through them is a harmless miss.
    if (_cwEnabled &&
        (_cwMergeLocal ? _cwAll : _cwMovies).isNotEmpty &&
        !_homeDisabled.contains('cw:movies'))
      _CwRow(
        rowId: 'cw:movies',
        title: 'Continue Watching',
        tag: _cwMergeLocal ? null : 'Movies',
        kind: _CwKind.local,
        items: _cwMergeLocal ? _cwAll : _cwMovies,
        nodes: _cwMovieNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.local, m),
        episodeOf: _cwMergeLocal
            ? (m) => _cwCardEpisode(_CwKind.local, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.local, m),
        episodeArtworkOf: _cwMergeLocal
            ? (m) => _cwEpisodeArtwork[m.imdbId]
            : (_) => null,
        onOpen: _openContinueItem,
        onQuickPlay: _onContinuePlay,
        onRemove: _removeLocalCwItem,
        onSeeAll: () =>
            _openContinueWatchingSeeAll(_cwMergeLocal ? 'all' : 'movie'),
      ),
    if (!_cwMergeLocal &&
        _cwEnabled &&
        _cwSeries.isNotEmpty &&
        !_homeDisabled.contains('cw:series'))
      _CwRow(
        rowId: 'cw:series',
        title: 'Continue Watching',
        tag: 'Series',
        kind: _CwKind.local,
        items: _cwSeries,
        nodes: _cwSeriesNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.local, m),
        episodeOf: (m) => _cwCardEpisode(_CwKind.local, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.local, m),
        episodeArtworkOf: (m) => _cwEpisodeArtwork[m.imdbId],
        onOpen: _openContinueItem,
        onQuickPlay: _onContinuePlay,
        onRemove: _removeLocalCwItem,
        onSeeAll: () => _openContinueWatchingSeeAll('series'),
      ),
    if ((_cwMergeTrakt ? _traktAll : _traktMovies).isNotEmpty &&
        !_homeDisabled.contains('trakt:movies'))
      _CwRow(
        rowId: 'trakt:movies',
        title: 'Trakt Continue Watching',
        tag: _cwMergeTrakt ? null : 'Movies',
        kind: _CwKind.trakt,
        items: _cwMergeTrakt ? _traktAll : _traktMovies,
        nodes: _traktMovieNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.trakt, m),
        episodeOf: _cwMergeTrakt
            ? (m) => _cwCardEpisode(_CwKind.trakt, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.trakt, m),
        episodeArtworkOf: _cwMergeTrakt
            ? (m) => _traktEpisodeArtwork[m.imdbId]
            : (_) => null,
        onOpen: _openTraktItem,
        onQuickPlay: _playTraktItem,
        onRemove: _removeTraktCwItem,
        onSeeAll: () => _openTraktSeeAll(_cwMergeTrakt ? 'all' : 'movie'),
      ),
    if (!_cwMergeTrakt &&
        _traktSeries.isNotEmpty &&
        !_homeDisabled.contains('trakt:shows'))
      _CwRow(
        rowId: 'trakt:shows',
        title: 'Trakt Continue Watching',
        tag: 'Shows',
        kind: _CwKind.trakt,
        items: _traktSeries,
        nodes: _traktSeriesNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.trakt, m),
        episodeOf: (m) => _cwCardEpisode(_CwKind.trakt, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.trakt, m),
        episodeArtworkOf: (m) => _traktEpisodeArtwork[m.imdbId],
        onOpen: _openTraktItem,
        onQuickPlay: _playTraktItem,
        onRemove: _removeTraktCwItem,
        onSeeAll: () => _openTraktSeeAll('series'),
      ),
    // Simkl rows come after the Trakt rows. Both trackers fetch over the network
    // on a cold start (Simkl's playback/library caches are only warmed by a
    // scrobble or a prior read, not pre-warmed at launch), but only Trakt holds
    // its slot open with skeletons — so when the Simkl rows land they settle in
    // once, like any other content row. (A dedicated Simkl skeleton could make
    // that zero-shift too, but it isn't worth the board index-math complexity.)
    if ((_cwMergeSimkl ? _simklAll : _simklMovies).isNotEmpty &&
        !_homeDisabled.contains('simkl:movies'))
      _CwRow(
        rowId: 'simkl:movies',
        title: 'Simkl Continue Watching',
        tag: _cwMergeSimkl ? null : 'Movies',
        kind: _CwKind.simkl,
        items: _cwMergeSimkl ? _simklAll : _simklMovies,
        nodes: _simklMovieNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.simkl, m),
        episodeOf: _cwMergeSimkl
            ? (m) => _cwCardEpisode(_CwKind.simkl, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.simkl, m),
        episodeArtworkOf: _cwMergeSimkl
            ? (m) => _simklEpisodeArtwork[m.imdbId]
            : (_) => null,
        onOpen: _openSimklCwItem,
        onQuickPlay: _playSimklCwItem,
        onRemove: _removeSimklCwItem,
        onSeeAll: () => _openSimklCwSeeAll(_cwMergeSimkl ? 'all' : 'movie'),
      ),
    if (!_cwMergeSimkl &&
        _simklSeries.isNotEmpty &&
        !_homeDisabled.contains('simkl:shows'))
      _CwRow(
        rowId: 'simkl:shows',
        title: 'Simkl Continue Watching',
        tag: 'Shows',
        kind: _CwKind.simkl,
        items: _simklSeries,
        nodes: _simklSeriesNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.simkl, m),
        episodeOf: (m) => _cwCardEpisode(_CwKind.simkl, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.simkl, m),
        episodeArtworkOf: (m) => _simklEpisodeArtwork[m.imdbId],
        onOpen: _openSimklCwItem,
        onQuickPlay: _playSimklCwItem,
        onRemove: _removeSimklCwItem,
        onSeeAll: () => _openSimklCwSeeAll('series'),
      ),
    if ((_cwMergeMdblist ? _mdblistAll : _mdblistMovies).isNotEmpty &&
        !_homeDisabled.contains('mdblist:movies'))
      _CwRow(
        rowId: 'mdblist:movies',
        title: 'MDBList Continue Watching',
        tag: _cwMergeMdblist ? null : 'Movies',
        kind: _CwKind.mdblist,
        items: _cwMergeMdblist ? _mdblistAll : _mdblistMovies,
        nodes: _mdblistMovieNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.mdblist, m),
        episodeOf: _cwMergeMdblist
            ? (m) => _cwCardEpisode(_CwKind.mdblist, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.mdblist, m),
        episodeArtworkOf: (_) => null,
        onOpen: _openMdblistCwItem,
        onQuickPlay: _playMdblistCwItem,
        onRemove: _removeMdblistCwItem,
        canRemove: _canRemoveMdblistCwItem,
        onSeeAll: () => _openMdblistCwSeeAll(_cwMergeMdblist ? 'all' : 'movie'),
      ),
    if (!_cwMergeMdblist &&
        _mdblistSeries.isNotEmpty &&
        !_homeDisabled.contains('mdblist:shows'))
      _CwRow(
        rowId: 'mdblist:shows',
        title: 'MDBList Continue Watching',
        tag: 'Shows',
        kind: _CwKind.mdblist,
        items: _mdblistSeries,
        nodes: _mdblistSeriesNodes,
        progressOf: (m) => _cwCardProgress(_CwKind.mdblist, m),
        episodeOf: (m) => _cwCardEpisode(_CwKind.mdblist, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(_CwKind.mdblist, m),
        episodeArtworkOf: (_) => null,
        onOpen: _openMdblistCwItem,
        onQuickPlay: _playMdblistCwItem,
        onRemove: _removeMdblistCwItem,
        canRemove: _canRemoveMdblistCwItem,
        onSeeAll: () => _openMdblistCwSeeAll('series'),
      ),
    // IPTV Continue Watching (Xtream VOD). Routes through [IptvCwRouter], not
    // the addon/tracker pipeline — a movie resumes playback, a series opens the
    // merged Xtream series page. Progress/episode key off the synthetic meta id
    // (routeKey) since these metas carry no imdbId.
    if (_iptvCwMovies.isNotEmpty && !_homeDisabled.contains('iptv:movies'))
      _CwRow(
        rowId: 'iptv:movies',
        title: 'IPTV Continue Watching',
        tag: 'Movies',
        kind: _CwKind.iptv,
        items: _iptvCwMovies,
        nodes: _iptvCwMovieNodes,
        progressOf: (m) => _iptvCwProgress[m.id],
        episodeOf: (_) => null,
        remainingMinutesOf: (m) => _iptvRemainingMinutes(m.id),
        episodeArtworkOf: (_) => null,
        onOpen: _openIptvCwItem,
        onQuickPlay: _openIptvCwItem,
        onRemove: _removeIptvCwItem,
      ),
    if (_iptvCwSeries.isNotEmpty && !_homeDisabled.contains('iptv:series'))
      _CwRow(
        rowId: 'iptv:series',
        title: 'IPTV Continue Watching',
        tag: 'Series',
        kind: _CwKind.iptv,
        items: _iptvCwSeries,
        nodes: _iptvCwSeriesNodes,
        progressOf: (m) => _iptvCwProgress[m.id],
        episodeOf: (m) => _iptvCwEpisode[m.id],
        remainingMinutesOf: (m) => _iptvRemainingMinutes(m.id),
        episodeArtworkOf: (m) => _iptvCwByKey[m.id]?.posterUrl,
        onOpen: _openIptvCwItem,
        onQuickPlay: _openIptvCwItem,
        onRemove: _removeIptvCwItem,
      ),
  ];

  /// Whether any Continue Watching row is currently on-screen (drives focus
  /// wiring between it and the first catalog row). Uses allocation-free field
  /// checks (not `_cwRows`) since it's read on the per-card build hot path —
  /// keep these conditions in lock-step with the `_cwRows` row gates above.
  bool get _cwVisible =>
      ((_cwEnabled &&
              (((_cwMergeLocal ? _cwAll : _cwMovies).isNotEmpty &&
                      !_homeDisabled.contains('cw:movies')) ||
                  (!_cwMergeLocal &&
                      _cwSeries.isNotEmpty &&
                      !_homeDisabled.contains('cw:series')))) ||
          ((_cwMergeTrakt ? _traktAll : _traktMovies).isNotEmpty &&
              !_homeDisabled.contains('trakt:movies')) ||
          (!_cwMergeTrakt &&
              _traktSeries.isNotEmpty &&
              !_homeDisabled.contains('trakt:shows')) ||
          ((_cwMergeSimkl ? _simklAll : _simklMovies).isNotEmpty &&
              !_homeDisabled.contains('simkl:movies')) ||
          (!_cwMergeSimkl &&
              _simklSeries.isNotEmpty &&
              !_homeDisabled.contains('simkl:shows')) ||
          ((_cwMergeMdblist ? _mdblistAll : _mdblistMovies).isNotEmpty &&
              !_homeDisabled.contains('mdblist:movies')) ||
          (!_cwMergeMdblist &&
              _mdblistSeries.isNotEmpty &&
              !_homeDisabled.contains('mdblist:shows')) ||
          (_iptvCwMovies.isNotEmpty &&
              !_homeDisabled.contains('iptv:movies')) ||
          (_iptvCwSeries.isNotEmpty &&
              !_homeDisabled.contains('iptv:series'))) &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// Home ordering is presentation state for the Home board only. Search and
  /// Discover share some rail/focus helpers, but keep result-source order.
  bool get _homeRowOrderActive =>
      !widget.searchMode &&
      !widget.discoverMode &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// Saved Home orders created before MDBList was exposed do not contain its
  /// CW ids. Seed those new ids after the Simkl CW family instead of allowing
  /// the generic ordering projection to append them at the bottom. Any MDBList
  /// id already saved keeps its chosen position untouched.
  List<String> get _effectiveHomeRowOrder => HomeRowOrder.seedPinned(
    HomeRowOrder.insertMissingAfter(
      _homeRowOrder,
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    ),
    [
      for (final c in _homeCollections)
        if (c.pinToTop) HomeCollectionRowIds.collection(c.id),
    ],
  );

  /// Whether the Trakt rows should be held open with skeleton placeholders: the
  /// account is connected, its (slow, network) Continue Watching fetch is in
  /// flight, and there are no real Trakt rows on-screen yet. Reserving the slot
  /// keeps the row count stable so the real rows fill in place — nothing below
  /// reflows, and the auto-focus anchor stays put.
  ///
  /// Shown on every platform (the placeholder header omits the phone/desktop
  /// See-All link, which pops in harmlessly when the real row loads). Only on
  /// the homepage board (not the dedicated Search / Discover tabs, and not while
  /// a catalog search is showing its own results). Requiring the real rows to be
  /// empty means a refresh that already has data updates in place — no skeletons
  /// stacked on top of live rows.
  bool get _traktReserving =>
      !widget.searchMode &&
      !widget.discoverMode &&
      _isTraktAuthenticated &&
      _traktCwLoading &&
      _traktMovies.isEmpty &&
      _traktSeries.isEmpty &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  // Hero state. Driven by ValueNotifiers so focus-driven hero swaps rebuild
  // only the spotlight, never the whole board (important on low-power TVs).
  final ValueNotifier<StremioMeta?> _heroItem = ValueNotifier<StremioMeta?>(
    null,
  );
  final ValueNotifier<StremioMeta?> _heroEnriched = ValueNotifier<StremioMeta?>(
    null,
  );
  int _heroReqId = 0;
  Timer? _heroTimer;

  /// Settle debounce for the hero SWAP itself (260ms): while DPAD focus flies
  /// across cards only the card visuals update; the spotlight (backdrop
  /// decode, logo, meta, tint cascade) follows once focus rests.
  Timer? _heroSwapTimer;

  // Hero ambient trailer (Home board, TV only): once DPAD focus RESTS on a
  // card, its trailer crossfades into the hero backdrop — same living-backdrop
  // treatment (and the same HeroTrailerBackdrop machinery: single decoder,
  // route/background pausing) as the detail page. Notifier-driven so a trailer
  // arriving rebuilds only the hero's video layer, never the board.
  final ValueNotifier<YoutubeResolvedStreams?> _heroTrailer =
      ValueNotifier<YoutubeResolvedStreams?>(null);
  Timer? _heroTrailerTimer;
  int _heroTrailerReq = 0;

  /// True from the moment the rest-debounce commits to loading a trailer until
  /// either frames are on screen or the attempt dies (no trailer / resolve
  /// failed / hero moved on) — drives the hero's little "Trailer" pill.
  final ValueNotifier<bool> _heroTrailerLoading = ValueNotifier<bool>(false);

  /// True while trailer frames are actually on screen. The spotlight fades its
  /// static backdrop image out on this signal (the video plays in the board
  /// layer BENEATH the spotlight, so the image must yield to reveal it — the
  /// crossfade the video's own opacity used to provide when it sat on top).
  final ValueNotifier<bool> _heroTrailerShowing = ValueNotifier<bool>(false);

  /// Takeover progress (0 ambient → 1 full-board), published by
  /// [_HeroTrailerLayer] as its promote animation runs. The board content and
  /// the sidebar rail fade fully OUT on it while the compact info overlay
  /// fades in — the film takes the room.
  final ValueNotifier<double> _heroTrailerTakeover = ValueNotifier<double>(0);

  // Live IPTV favourite hero preview: when DPAD focus rests on an "IPTV" row
  // card, its stream plays in the SAME boxed video region as the catalog
  // trailer above — reusing HeroTrailerBackdrop's `live: true` mode, exactly
  // like the IPTV page's own inline channel preview
  // (IptvResultsView._buildPreviewStage). Painted as a layer above
  // [_HeroTrailerLayer] so the two never need to swap types; whichever one
  // actually has a URL to show wins (see [_setHeroLiveIptv]).
  final ValueNotifier<String?> _heroLiveUrl = ValueNotifier<String?>(null);

  /// Set the INSTANT an IPTV favourite gains focus — well before its stream
  /// (if a Stremio-addon channel) finishes resolving. [_HeroLiveLayer] uses
  /// this to occlude the region with the channel's OWN art immediately, so
  /// the previously-focused catalog title's Cinemeta poster never shows
  /// through the resolve/buffer gap underneath.
  final ValueNotifier<IptvChannel?> _heroLiveChannel =
      ValueNotifier<IptvChannel?>(null);

  /// Boolean mirror of [_heroLiveChannel] for [_HeroSpotlight.liveTakeover] —
  /// the spotlight fades its (now-stale) colour field and identity text on
  /// this, and has no other reason to know the IPTV-specific channel type.
  final ValueNotifier<bool> _heroLiveTakeover = ValueNotifier<bool>(false);
  int _heroLiveReq = 0;

  /// Candidate ladder for the live IPTV favourite when it's a Stremio-addon
  /// channel (several upstream links to try in order) — mirrors the IPTV
  /// page's own ladder (IptvResultsView._onPreviewPlaybackFailed). Null for a
  /// plain M3U/Xtream favourite, which has just the one URL.
  List<String>? _heroLiveCandidates;

  /// Set when real content playback launches (any path — in-app route,
  /// native TV activity, external app): the ambient trailer must not resume
  /// behind or after the feature (the behavior ef5f555 shipped; the
  /// backdrop's own per-instance latch dies with the widget when the route
  /// cover kills the trailer, so the host has to remember). Cleared when a
  /// NEW title takes the spotlight or the board reloads.
  bool _heroTrailerSuppressed = false;

  /// The item the last hero-trailer schedule was for — what the suppression
  /// lift above compares against.
  String? _heroTrailerScheduledItemId;

  /// Settings → Home Page toggles, read once per screen life (on TV a tab
  /// switch rebuilds the screen, so Settings changes are picked up on return).
  bool _heroTrailerEnabled = false;

  /// Ambient volume (0–100) for the hero trailer; 0 when the sound toggle is
  /// off. Applied at engine open, so it's also read once per screen life.
  double _heroTrailerVolume = 0;

  /// Trailers only on the TV Home board's full spotlight — never the Search
  /// tab's compact strip (too small, and results should dominate) or off-TV
  /// (the hero itself isn't rendered there). Low-memory Apple TV generations
  /// are excluded outright: an mpv trailer engine alongside the board's
  /// artwork is exactly the load that jetsam-kills a 3 GB first-gen 4K, and
  /// the probe is warmed pre-runApp so this getter stays constant for the
  /// State's lifetime (the init/dispose registrations must agree).
  bool get _heroTrailerActive =>
      widget.isTelevision &&
      !widget.searchMode &&
      !widget.discoverMode &&
      !TvosDevice.isLowMemoryCached;

  /// The hero trailer off-TV: the Spotlight home board's reel, rendered on
  /// phones/tablets/desktop. Deliberately SEPARATE from [_heroTrailerActive]
  /// — that getter is the whole TV shell lifecycle (glass scaffold, sidebar
  /// relays, hardware-key takeover, ambient publish), none of which belongs
  /// on a phone. This one means exactly "this instance may resolve and paint
  /// a hero trailer"; the enabled pref (platform-defaulted: TV/desktop on,
  /// phone/tablet off) gates it at schedule time.
  bool get _heroTrailerOffTvEligible =>
      !widget.isTelevision && !widget.searchMode && !widget.discoverMode;

  /// May THIS instance resolve/render a hero trailer at all.
  bool get _heroTrailerRenderable =>
      _heroTrailerActive || _heroTrailerOffTvEligible;

  // Discover tab: the active source key (CW / tracker / `a:{addonId}`) + its
  // DPAD focus node (the "Source" dropdown is the leading filter of whichever
  // embedded See-All panel is shown). [_discAddons] is the browsable addon list
  // appended to the Source dropdown.
  String _discSource = _discCw;
  // Incremented only for an explicit dropdown choice. Async preference/add-on
  // hydration may apply its captured landing source only while this is still
  // unchanged, so a late manifest response can never undo user input.
  int _discSourceRevision = 0;
  List<StremioAddon> _discAddons = const [];
  final FocusNode _discSourceNode = FocusNode(debugLabel: 'disc_source');

  /// An MDBList list handed off from the Search tab's Lists mode (consumed
  /// from MainPageBridge.pendingMdblistListOpen on mount). Passed into the
  /// MDBList panel, which opens focused on it with the ♥ like toggle.
  MdblistListChoice? _discMdblistList;

  // The grid tile the DPAD is currently on, mirrored into the two-pane detail
  // rail (TV Discover). A ValueNotifier — not setState — so a focus move only
  // rebuilds the rail, never the grid subtree.
  final ValueNotifier<StremioMeta?> _discFocused = ValueNotifier(null);
  void _onDiscFocused(StremioMeta item) => _discFocused.value = item;

  // Discover ambient trailer, shared between the rail (which resolves + owns the
  // single-decoder discipline, writing here) and the full-screen
  // DiscoverTrailerStage (which renders the window and can promote it to a
  // fullscreen takeover). See discover_trailer_stage.dart.
  final ValueNotifier<YoutubeResolvedStreams?> _discTrailerStreams =
      ValueNotifier(null);
  final ValueNotifier<bool> _discTrailerLoading = ValueNotifier(false);
  final ValueNotifier<double> _discTrailerVolume = ValueNotifier(0);
  final ValueNotifier<double> _discTakeover = ValueNotifier(0);
  // The playing trailer's (enriched) title — drives the fullscreen takeover's
  // name/meta overlay. Written by the rail alongside its streams.
  final ValueNotifier<StremioMeta?> _discTrailerMeta = ValueNotifier(null);
  // What the rail is actually rendering (focused item merged with enrichment) —
  // published by the rail, read by the full-frame glass stage that draws the
  // title's backdrop behind both panes.
  final ValueNotifier<StremioMeta?> _discShown = ValueNotifier(null);
  // True while trailer frames are on the stage (set by DiscoverTrailerStage) —
  // drives the AMBIENT chip in the page's status corner.
  final ValueNotifier<bool> _discTrailerShowing = ValueNotifier(false);
  // Theater: after a few seconds of uninterrupted playback the page commits to
  // the trailer — veils thin to near-clear, rail and grid recede to ~15%. Armed
  // by playback and browsing activity; controls return immediately on input
  // and dim again after the idle dwell if trailer playback continues.
  final ValueNotifier<bool> _discTheater = ValueNotifier(false);
  Timer? _discTheaterTimer;
  static const Duration _discTheaterDelay = Duration(seconds: 5);

  void _onDiscShowingChanged() {
    _discTheaterTimer?.cancel();
    if (_discTrailerShowing.value) {
      _discTheaterTimer = Timer(_discTheaterDelay, () {
        if (mounted && _discTrailerShowing.value) _discTheater.value = true;
      });
    } else {
      _discTheater.value = false;
    }
  }

  /// Relay the Discover takeover to the app shell so the TV sidebar hides in
  /// lock-step (a cinema has no menu) — the same signal the Home board uses.
  void _relayDiscoverChromeDim() =>
      MainPageBridge.tvChromeDim.value = _discTakeover.value;

  // ── Discover layout (grid / stage) ───────────────────────────────────────

  /// Last loaded `discover_layout`, kept for the life of the process. The
  /// pref read is async but the layout is needed on the FIRST frame: without
  /// this, every entry to the Discover tab would build the grid, then swap to
  /// the stage a frame later — a visible flash on each tab switch. Only the
  /// very first entry after launch pays it.
  static String _discLayoutCached = 'stage';

  /// Active Discover layout, from `discover_layout`. Stage is the default;
  /// grid is the only thing phone/desktop ever render (see [_discStage]).
  String _discLayout = _discLayoutCached;

  // Warmed before runApp, so the first Discover frame already has the user's
  // poster-card choices instead of flashing the default chrome.
  bool _discShowTypeTags = DiscoverPrefs.showTypeTags;
  bool _discShowRatings = DiscoverPrefs.showRatings;
  bool _discShowTitles = DiscoverPrefs.showTitles;

  /// Whether the STAGE layout is what this surface should render: the pref, on
  /// the Discover tab, on a TV. The canvas-size guard lives in the LayoutBuilder
  /// (a too-small canvas falls back to the flat panel, exactly like the grid's
  /// two-pane does).
  bool get _discStage =>
      widget.discoverMode && widget.isTelevision && _discLayout == 'stage';

  Future<void> _loadDiscoverLayout() async {
    final layout = await StorageService.getDiscoverLayout();
    _discLayoutCached = layout;
    if (!mounted || layout == _discLayout) return;
    setState(() => _discLayout = layout);
  }

  /// Settings picker fired: tear the trailer down BEFORE the relayout, so the
  /// player is never re-parented mid-play into the other layout's tree (the
  /// Home board's rule for the same swap), then re-read the pref and rebuild.
  void _onDiscoverLayoutChanged() {
    if (!mounted) return;
    _discTrailerStreams.value = null;
    _discTrailerMeta.value = null;
    _discTrailerLoading.value = false;
    _discTrailerShowing.value = false;
    _discTheater.value = false;
    _discTheaterTimer?.cancel();
    _discTakeover.value = 0;
    unawaited(_loadDiscoverLayout());
  }

  void _onDiscoverCardSettingsChanged() {
    if (!mounted) return;
    final showTypeTags = DiscoverPrefs.showTypeTags;
    final showRatings = DiscoverPrefs.showRatings;
    final showTitles = DiscoverPrefs.showTitles;
    if (showTypeTags == _discShowTypeTags &&
        showRatings == _discShowRatings &&
        showTitles == _discShowTitles) {
      return;
    }
    setState(() {
      _discShowTypeTags = showTypeTags;
      _discShowRatings = showRatings;
      _discShowTitles = showTitles;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profileSessionOwner = ProfileSessionMemory.captureOwner();
    // This one widget backs three tabs (Home board / dedicated Search / Discover).
    AnalyticsService.screenView(
      widget.searchMode
          ? 'search'
          : widget.discoverMode
          ? 'discover'
          : 'home',
    );
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusContent);
    if (!widget.searchMode && !widget.discoverMode) {
      StorageService.localCompletionRevision.addListener(
        _onLocalCompletionChanged,
      );
      MdblistService.instance.playbackRevision.addListener(
        _onMdblistPlaybackRevision,
      );
      MainPageBridge.addPlaylistChangeListener(_loadPlaylistFavorites);
    }
    if (widget.searchMode) {
      MainPageBridge.registerTabBackHandler('search', _handleSearchBack);
    }
    // A detail-open handed off from another tab (e.g. the Trakt Calendar, a
    // separate tab that can't reach this screen's state). Only the Home board
    // (not the Search/Discover variants) claims it; the opener switches here via
    // switchTab(15) right after setting it, so it's present by the time we mount.
    if (!widget.searchMode && !widget.discoverMode) {
      MainPageBridge.registerCatalogDetailOpenHandler(
        _openPendingCatalogDetail,
      );
      final pending = MainPageBridge.pendingCatalogDetailOpen;
      if (pending != null) {
        MainPageBridge.pendingCatalogDetailOpen = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openPendingCatalogDetail(pending));
        });
      }
    }
    // An MDBList list handed off from the Search tab's Lists mode: start the
    // Discover tab on the MDBList source, focused on that list. The nav
    // rebuilds this screen fresh on every tab switch, so the payload set right
    // before switchTab(18) is present by the time we mount.
    if (widget.discoverMode) {
      final pending = MainPageBridge.pendingMdblistListOpen;
      if (pending != null) {
        MainPageBridge.pendingMdblistListOpen = null;
        _discMdblistList = MdblistListChoice(
          id: (pending['id'] as num?)?.toInt() ?? -1,
          name: pending['name'] as String? ?? 'Untitled list',
          ownerName: pending['ownerName'] as String?,
          itemCount: (pending['itemCount'] as num?)?.toInt() ?? 0,
          liked: pending['liked'] == true,
          likes: (pending['likes'] as num?)?.toInt() ?? 0,
        );
        _discSource = _discMdblist;
        unawaited(StorageService.setDiscoverLastSource(_discMdblist));
      }
    }
    // Ambient hero trailer gates (Home board TV only) — read before the board
    // loads so the seeded first spotlight can already schedule its trailer.
    if (_heroTrailerActive) {
      // The hero doesn't change when the user steps out to the SIDEBAR, so
      // the rest-debounce (or a playing trailer) would happily continue under
      // the expanded rail. Kill it on sidebar enter; re-arm the current
      // spotlight on exit so browsing resumes its normal rest-to-play.
      MainPageBridge.addTvSidebarFocusListener(_onTvSidebarFocusChanged);
      // Relay the takeover arc to the app shell so the sidebar rail hides in
      // lock-step with the board.
      _heroTrailerTakeover.addListener(_relayChromeDim);
      // Relay the ambient lights-off state too: the rail dims with the rows
      // while a trailer plays instead of glowing beside the darkened stage.
      _heroTrailerShowing.addListener(_relayLightsOff);
      // Deliberately NO sidebar tint relay any more: the "colour floods the
      // chrome while the trailer plays" move read as noise, not mood (user
      // call). Playback now dims the stage neutrally instead ("lights down");
      // the rail just stays its quiet dark self. (dispose() already resets
      // the shell's tvHeroTint post-frame, so no stale colour can survive.)
      // Real content playback (from a detail page, Quick Play, anywhere)
      // suppresses the trailer for this spotlight — see _heroTrailerSuppressed.
      MainPageBridge.addPlayerLaunchListener(_onContentPlayerLaunch);
      // While the takeover owns the screen the board is invisible — ANY key
      // must bring it back, even ones that don't change the hero (fav-row
      // tiles, a same-title card in another row). Observe-only: the key still
      // performs its normal action (SELECT opens the showcased title).
      HardwareKeyboard.instance.addHandler(_onTakeoverKey);
      Future.wait([
        StorageService.getHomeHeroTrailerEnabled(),
        StorageService.getAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
        ),
        StorageService.getAmbientTrailerVolume(AmbientTrailerSurface.homeHero),
      ]).then((values) {
        if (!mounted) return;
        final enabled = values[0] as bool;
        setState(() {
          _heroTrailerEnabled = enabled;
          _heroTrailerVolume = (values[1] as bool)
              ? (values[2] as int).toDouble()
              : 0;
        });
        if (!enabled) return;
        // The board usually seeds the hero before this read lands — kick the
        // current spotlight so the billboard still starts on cold open.
        final current = _heroItem.value;
        if (current != null) _scheduleHeroTrailer(current);
      });
    }
    // Discover on TV: relay the trailer takeover to the sidebar chrome-dim so
    // the rail hides when the trailer goes fullscreen. The showing listener
    // arms the theater timer (deep lights-off a few seconds into playback).
    if (widget.discoverMode) {
      MainPageBridge.discoverCardSettingsChanged =
          _onDiscoverCardSettingsChanged;
    }
    if (widget.discoverMode && widget.isTelevision) {
      _discTakeover.addListener(_relayDiscoverChromeDim);
      _discTrailerShowing.addListener(_onDiscShowingChanged);
      // Layout pref (grid/stage): read once here, then live-reloaded whenever
      // the Settings picker fires the bridge. DISCOVER instance only — Home
      // and Search never render this layout and must not take the slot.
      unawaited(_loadDiscoverLayout());
      MainPageBridge.discoverLayoutChanged = _onDiscoverLayoutChanged;
    }
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    // Playback that ran in a separate ACTIVITY (Android TV native player,
    // DeoVR, external app) pushes no Flutter route, so nothing on the board
    // ever learns it ended — the Continue Watching rows would keep showing the
    // episode the user just finished. This is that missing signal.
    MainPageBridge.addPlaybackReturnListener(_onPlaybackReturned);
    // Unconditional (the _heroTrailerActive block below registers its own
    // trailer-suppression listener; this one is just the latch that tells the
    // post-playback refresh whether anything was actually played).
    MainPageBridge.addPlayerLaunchListener(_markPlaybackStarted);
    // Restore a keyword search preserved from a prior tab visit (results +
    // scroll) BEFORE the async default-view load below can start: restoration
    // sets keyword mode synchronously, and a later-resolving catalog default
    // would flip the mode back and could fire a catalog search with the
    // restored keyword text. A successful restore therefore also suppresses
    // the default-view load outright.
    final restoredKeyword =
        widget.isTelevision && !widget.searchMode && !widget.discoverMode
        ? false
        : _restoreKeywordState();
    // Home board only: live-refresh when the Home Rows manager changes which
    // rows are hidden (on non-TV, Settings is a pushed route so the board isn't
    // rebuilt on return; on TV a tab switch already reloads it fresh).
    if (!widget.searchMode && !widget.discoverMode) {
      MainPageBridge.addHomeSettingsListener(_reloadForHomeSettings);
      HomeRowRefreshSignal.addListener(_queueHomeRows);
      _stremio.addAddonsChangedListener(_onHomeAddonsChanged);
      // IPTV list mutations (picker, IPTV settings, provider deletion,
      // reconcile, import) all bump the store revision — the only signal a
      // Home that stays alive across tab switches gets about them.
      IptvMediaStore.listsRevision.addListener(_onIptvListsRevision);
      if (!restoredKeyword) unawaited(_loadHomeDefaultView());
      // Home layout pref: loaded once here, then live-reloaded whenever the
      // Settings picker fires the bridge. HOME board instance only — the
      // Search tab keeps classic and must not steal the single bridge slot.
      // EVERY platform now: off-TV the pref decides Classic vs Spotlight,
      // and without this load the off-TV field would sit on its 'canvas'
      // initial forever (resolved to classic) whatever was chosen.
      unawaited(_loadTvHomeStyle());
      unawaited(_loadHomeCardOrientation());
      MainPageBridge.tvHomeStyleChanged = _onTvHomeStyleChanged;
      if (widget.isTelevision) {
        MainPageBridge.tvHeroArtworkQualityChanged =
            _onTvHeroArtworkQualityChanged;
        // Canvas theater mode: a dwell after trailer frames land recedes the
        // shelf so the video owns the screen; any key wakes it. Observe-only
        // handler (the key still performs its normal action) — same rule as
        // _onTakeoverKey.
        _heroTrailerShowing.addListener(_onCanvasTrailerShowingChanged);
        HardwareKeyboard.instance.addHandler(_onCanvasTheaterKey);
        HardwareKeyboard.instance.addHandler(_onStageHoldKey);
      } else {
        // Off-TV Home: system Back closes the Spotlight search sheet before
        // anything else may handle it. Routed through the bridge's tab-back
        // mechanism — a nested PopScope would race the root scope in
        // main.dart (its didPop==false path continues into double-back-exit
        // arming even when an inner scope consumed the press).
        MainPageBridge.registerTabBackHandler('home', _handleHomeBack);
        // Restored keyword results must come back with the sheet open — the
        // full-bleed shell would otherwise hide them behind a hero.
        if (restoredKeyword) _searchSheetOpen = true;
        // Hero trailer prefs for the OFF-TV Spotlight reel. Only the pieces
        // that mean "resolve and paint a video" — none of the TV shell
        // machinery the _heroTrailerActive block registers.
        MainPageBridge.addPlayerLaunchListener(_onContentPlayerLaunch);
        unawaited(_reloadOffTvHeroTrailerPrefs());
      }
    }
    // Unified (non-TV) layout: drive the catalog Sources bar off search-field
    // focus, with a delayed hide so clicking the button doesn't yank it away
    // before the tap lands (blurring the field would otherwise unmount it
    // mid-click). See _buildUnifiedCatalogSourcesBar.
    if (!widget.isTelevision && !widget.searchMode) {
      _searchFocusNode.addListener(_onSearchFocusForSources);
    }
    // The focus latch: interacting with the field pins the sheet open, even
    // while the Spotlight shell is not yet eligible — an async style/hero
    // arrival can then never unmount a focused (still blank) field.
    if (!widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      _searchFocusNode.addListener(_onSearchFocusLatchSheet);
    }
    _boardScroll.addListener(_onBoardScroll);
    _kwScroll.addListener(() {
      if (_kwScroll.hasClients) _kwLastScroll = _kwScroll.offset;
    });
    _refreshTraktAuthState();
    _refreshSimklAuthState();
    _refreshMdblistAuthState();
    _loadMergedSeriesFlag();
    // (The keyword restore itself ran earlier — before _loadHomeDefaultView —
    // see the ordering comment there.) A restored search carries its own
    // filters, so don't overwrite them with the saved defaults.
    if (!restoredKeyword) unawaited(_loadDefaultKeywordFilters());
    // The dedicated Search tab only shows a field + blank prompt until a query,
    // so it skips the whole board pipeline (home catalogs, Continue Watching,
    // Trakt, favourites) — catalog search fetches its addons on demand. It also
    // never runs _load(), which is what clears _loading, so clear it here or the
    // results grid (_buildBoard) would sit on its initial spinner forever.
    if (widget.searchMode) {
      _loading = false;
    } else if (widget.discoverMode) {
      // Discover browses one source at a time via the Source dropdown, so it
      // skips the board's catalog pipeline and just primes the Continue Watching
      // + Trakt rows its first two sources draw from. _refreshPikpakOnly gates the
      // Quick-Play affordance the same way the board does.
      _loading = false;
      _refreshPikpakOnly();
      _loadDiscoverAddons();
      _primeDiscoverRows();
    } else {
      // TV board: last-resort focus reclaim. Several load/reload paths dispose
      // FocusNodes wholesale (_applySections rebuilds every catalog row's
      // nodes; CW rows re-sync after playback) and any of them can kill the
      // node holding primary focus — leaving the remote dead with no DPAD
      // press able to recover (the shell's recovery only fires when the scope
      // has NO traversable descendants, and the board always has plenty).
      // Watch the FocusManager and re-anchor onto the board when focus dies.
      if (widget.isTelevision) {
        FocusManager.instance.addListener(_onGlobalFocusChange);
      }
      // Kick off every leading-content load. Auto-focus settles to the top as
      // these complete; once they've ALL settled the arrival window is over and
      // re-anchoring latches off (see [_settleAutoFocusAfter]), so a later
      // background reload or a return from playback never yanks focus.
      _settleAutoFocusAfter([
        _load(),
        _loadContinueWatching(),
        _loadTraktContinueWatching(),
        // refreshBound:false — _load()'s bound-source scan (which now covers the
        // Simkl rows) runs after this on cold start, so a 2nd concurrent scan
        // here would be pure duplicate startup work on weak TV hardware.
        _loadSimklContinueWatching(refreshBound: false),
        _loadMdblistContinueWatching(refreshBound: false),
        _loadIptvContinueWatching(),
        _loadTvFavorites(),
        _loadStremioTvFavorites(),
        _loadIptvFavorites(),
        _loadMyWatchlist(),
        _loadIptvListRows(),
        _loadPlaylistFavorites(),
      ]);
    }
  }

  /// Await the initial board content loads, then end the auto-focus "arrival
  /// window": one final placement pass, then latch [_autoFocusSettled] so
  /// re-anchoring never fires again (a background CW/Trakt refresh, or focus
  /// restoration after returning from playback, must not move the user's focus).
  Future<void> _settleAutoFocusAfter(List<Future<void>> loads) async {
    await Future.wait(loads.map((f) => f.catchError((_) {})));
    if (!mounted) return;
    _maybeAutoFocusBoard();
    // Latch on the following frame so the placement pass above runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoFocusSettled = true;
    });
  }

  /// Back on the dedicated Search tab: clear an in-progress search (returning to
  /// the blank prompt) first; a second Back with nothing to clear falls through
  /// to leave the tab. Registered only in [SearchScreen.searchMode].
  bool _handleSearchBack() {
    final hasQuery =
        _searchController.text.isNotEmpty ||
        _catalogQuery.isNotEmpty ||
        _kwQuery.isNotEmpty ||
        _listsQuery.isNotEmpty;
    if (!hasQuery) return false;
    // Back also drops out of Keyword/Lists mode, so the tab returns to its
    // default Catalog prompt (matches the old overlay-close behaviour).
    // _clearQuery rebuilds, so setting the field first is enough.
    _mode = _Mode.catalog;
    _clearQuery();
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
    return true;
  }

  /// Off-TV hero trailer prefs — read at init and RE-read whenever Settings
  /// fires the home-settings bridge, because off-TV Settings is a pushed
  /// route over a surviving Home: without the re-read, flipping the toggle
  /// would do nothing until the tab was recreated. setState because the
  /// board's `trailersEnabled` is a constructor param — its dwell clock only
  /// learns the pref through a rebuild.
  ///
  /// Sound/volume read the DETAIL surface keys off-TV: that is the pair the
  /// settings page has always shown on these platforms, so a stored "sound
  /// off" keeps meaning what it meant. Writes go to both surfaces now, so
  /// the pairs converge on first change.
  Future<void> _reloadOffTvHeroTrailerPrefs() async {
    final values = await Future.wait([
      StorageService.getHomeHeroTrailerEnabled(),
      StorageService.getAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.detail,
      ),
      StorageService.getAmbientTrailerVolume(AmbientTrailerSurface.detail),
    ]);
    if (!mounted) return;
    final enabled = values[0] as bool;
    setState(() {
      _heroTrailerEnabled = enabled;
      _heroTrailerVolume = (values[1] as bool)
          ? (values[2] as int).toDouble()
          : 0;
    });
    if (!enabled) _clearHeroTrailer();
  }

  /// Off-TV Home's Back (via the bridge, tab key 'home'): close the Spotlight
  /// search sheet if it is up. Consuming the press here is what keeps the
  /// root handler from arming double-back-exit while the user is merely
  /// backing out of search.
  bool _handleHomeBack() => _closeSearchSheet();

  /// Focus on the search field latches the sheet open — see [_searchSheetOpen].
  void _onSearchFocusLatchSheet() {
    if (!_searchFocusNode.hasFocus || _searchSheetOpen) return;
    setState(() => _searchSheetOpen = true);
  }

  /// The one reset the sheet's close button and system Back share.
  ///
  /// Atomic by design (plan rev 4): mode returns to catalog BEFORE the close
  /// (`_clearQuery` alone never restores the mode — that lived only in the
  /// Search tab's handler), and the in-flight keyword search is invalidated
  /// (`_kwSearchToken`) so a late batch can't repopulate state Back just
  /// cleared. Returns whether there was a sheet to close, which is also the
  /// "did Back consume the press" answer.
  bool _closeSearchSheet() {
    if (!_searchSheetOpen) return false;
    // Whether this press visibly did something — deliberately captured
    // BEFORE the reset. The guard used to be `_spotlightSelected`, which
    // reopened the race the focus latch exists to close: the style pref
    // loads async, so on a cold start a user could focus the field (latch
    // set) and press Back before the read landed — the handler refused to
    // consume, and the root handler armed double-back-exit under an open
    // sheet. Content/focus is the honest test: it is true throughout that
    // window, and false only for a stale latch on a classic Home, where
    // falling through to the root handler is exactly right.
    final hadContent =
        _sheetForced ||
        _searchController.text.isNotEmpty ||
        _searchFocusNode.hasFocus;
    _kwSearchToken++;
    _kwSearching = false;
    _kwLoading = false;
    _mode = _Mode.catalog;
    _clearQuery(); // clears the field, kw/lists state, and the catalog query
    _searchFocusNode.unfocus();
    setState(() => _searchSheetOpen = false);
    return _spotlightSelected || hadContent;
  }

  /// An integration (Trakt / a debrid provider) was connected or disconnected
  /// elsewhere while this tab stayed alive — refresh the state that gates the
  /// detail quick actions, the PikPak-only Play hiding, and the Trakt rows.
  void _onIntegrationsChanged() {
    _refreshTraktAuthState();
    _refreshSimklAuthState();
    _refreshMdblistAuthState();
    _refreshPikpakOnly();
    // Connect/disconnect can change what the local shelves should hold (the
    // single-owner rule keys off scrobbling), so re-read local CW before the
    // tracker rows; _reloadForHomeSettings can legitimately return early when
    // no row/layout preference changed.
    if (!widget.searchMode && !widget.discoverMode) _loadContinueWatching();
    // Trakt/Simkl Continue Watching rows are never rendered on the dedicated
    // Search tab, so don't refetch them there.
    if (!widget.searchMode) {
      _loadTraktContinueWatching();
      _loadSimklContinueWatching();
      _loadMdblistContinueWatching();
    }
    // Opted-in tracker LIST rows live in the board's section pipeline, so a
    // connect/disconnect needs a board reload to add/drop them. Home board
    // only — this listener is registered by every SearchScreen variant, and
    // Search/Discover must never run the board pipeline. Deferred while a
    // catalog search is showing (see _requestBoardReload); safe against
    // overlap via _boardLoadGen.
    if (!widget.searchMode && !widget.discoverMode && _trackerExtrasEnabled) {
      _requestBoardReload();
    }
  }

  Future<void> _refreshTraktAuthState() async {
    final auth = await TraktService.instance.isAuthenticated();
    if (!mounted || auth == _isTraktAuthenticated) return;
    setState(() => _isTraktAuthenticated = auth);
  }

  Future<void> _refreshSimklAuthState() async {
    final auth = await SimklService.instance.isAuthenticated();
    if (!mounted || auth == _isSimklAuthenticated) return;
    setState(() => _isSimklAuthenticated = auth);
  }

  Future<void> _refreshMdblistAuthState() async {
    final auth = await MdblistService.instance.isAuthenticated();
    if (!mounted || auth == _isMdblistAuthenticated) return;
    final leaveLists = !auth && _mode == _Mode.lists;
    if (leaveLists) {
      _listsToken++;
      _disposeListsNodes();
    }
    setState(() {
      _isMdblistAuthenticated = auth;
      if (leaveLists) {
        _mode = _Mode.catalog;
        _listsQuery = '';
        _listsResults = const [];
        _listsSearching = false;
        _listsError = null;
      }
    });
    // A disconnect can remove the currently selected mode. Keep the shared
    // query useful by resolving it through Catalog after the selector falls
    // back, unless those exact Catalog results are already present.
    if (leaveLists) {
      final query = _searchController.text.trim();
      if (query.isNotEmpty && query != _catalogQuery) {
        _runCatalogSearch(query);
      }
      if (widget.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      }
    }
  }

  /// Restore a preserved keyword search into this instance if one exists for
  /// this variant. Returns true when a restore happened. Called from initState
  /// (pre-first-build) so direct field assignment — not setState — is correct.
  bool _restoreKeywordState() {
    final snap = _kwPreserved.take(
      _profileSessionOwner,
      where: (value) => value.variant == _variantKey && value.query.isNotEmpty,
    );
    if (snap == null) {
      return false;
    }
    // The keyword surface is per-profile; a snapshot saved under a profile
    // that had it must not restore into one that doesn't.
    if (!ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)) {
      return false;
    }
    _mode = _Mode.keyword;
    _kwQuery = snap.query;
    _kwAll = snap.all;
    _kwResults = snap.results;
    _kwFilters = snap.filters;
    _kwSort = snap.sort;
    _kwSortAsc = snap.sortAsc;
    _kwCache = snap.cache;
    _kwCachedOnly = snap.cachedOnly;
    _kwDirectCounts = snap.directCounts;
    _kwTorrentCounts = snap.torrentCounts;
    _kwSelectedDirect = snap.selectedDirect;
    _kwSelectedTorrent = snap.selectedTorrent;
    _kwSourceTab = snap.sourceTab;
    _searchController.text = snap.query;
    _disposeKwNodes();
    for (var i = 0; i < snap.results.length; i++) {
      _kwNodes.add(FocusNode(debugLabel: 'kw_$i'));
    }
    _syncKwTabNodes();
    _pendingKwScroll = snap.scrollOffset;
    return true;
  }

  @override
  void dispose() {
    _catalogContinueNode.dispose();
    _catalogMoreNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mdblistRevisionRefreshToken++;
    _spotlightHeroNode.dispose();
    // Preserve a COMPLETED keyword search so returning to this tab restores
    // results + scroll instead of the blank prompt (the nav rebuilds us fresh).
    // A still-streaming search is NOT preserved: its batches die with this
    // instance, so the snapshot would freeze a partial set that restores
    // looking complete (no strip, no cache badges) — matching pre-streaming
    // behavior, where a mid-flight switch preserved nothing.
    if (_mode == _Mode.keyword &&
        _kwQuery.isNotEmpty &&
        _kwResults.isNotEmpty &&
        !_kwSearching) {
      // Fold a parked (pill) final set into the snapshot — pure field updates,
      // safe in dispose — so restore doesn't resurrect a stale subset while
      // silently dropping the authoritative result.
      final pending = _kwPending;
      if (pending != null) {
        _kwPending = null;
        _kwAll = pending;
        if (_kwSourceTab != null &&
            !pending.any((t) => _kwSourceOf(t) == _kwSourceTab)) {
          _kwSourceTab = null;
        }
        _computeKwProviders(pending);
      }
      _kwPreserved.store(
        _profileSessionOwner,
        _KwPreservedState(
          variant: _variantKey,
          query: _kwQuery,
          all: _kwAll,
          results: _kwResults,
          filters: _kwFilters,
          sort: _kwSort,
          sortAsc: _kwSortAsc,
          cache: _kwCache,
          cachedOnly: _kwCachedOnly,
          directCounts: _kwDirectCounts,
          torrentCounts: _kwTorrentCounts,
          selectedDirect: _kwSelectedDirect,
          selectedTorrent: _kwSelectedTorrent,
          sourceTab: _kwSourceTab,
          scrollOffset: _kwLastScroll,
        ),
      );
    }
    MainPageBridge.unregisterTvContentFocusHandler(_tabIndex, _focusContent);
    StorageService.localCompletionRevision.removeListener(
      _onLocalCompletionChanged,
    );
    MdblistService.instance.playbackRevision.removeListener(
      _onMdblistPlaybackRevision,
    );
    if (!widget.searchMode && !widget.discoverMode) {
      MainPageBridge.removePlaylistChangeListener(_loadPlaylistFavorites);
      MainPageBridge.unregisterCatalogDetailOpenHandler(
        _openPendingCatalogDetail,
      );
    }
    if (widget.searchMode) {
      MainPageBridge.unregisterTabBackHandler('search', _handleSearchBack);
    }
    if (!widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      // Same closure that registered — the bridge's mid-transition contract.
      MainPageBridge.unregisterTabBackHandler('home', _handleHomeBack);
      _searchFocusNode.removeListener(_onSearchFocusLatchSheet);
      MainPageBridge.removePlayerLaunchListener(_onContentPlayerLaunch);
    }
    // Safe no-op in the variants that never registered it.
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    MainPageBridge.removePlayerLaunchListener(_markPlaybackStarted);
    MainPageBridge.removeHomeSettingsListener(_reloadForHomeSettings);
    HomeRowRefreshSignal.removeListener(_queueHomeRows);
    _stremio.removeAddonsChangedListener(_onHomeAddonsChanged);
    _homeRefreshTimer?.cancel();
    IptvMediaStore.listsRevision.removeListener(_onIptvListsRevision);
    for (final row in _iptvListRows) {
      for (final n in row.nodes) {
        n.dispose();
      }
      row.nodes.clear();
    }
    if (MainPageBridge.tvHomeStyleChanged == _onTvHomeStyleChanged) {
      MainPageBridge.tvHomeStyleChanged = null;
    }
    if (MainPageBridge.tvHeroArtworkQualityChanged ==
        _onTvHeroArtworkQualityChanged) {
      MainPageBridge.tvHeroArtworkQualityChanged = null;
    }
    if (widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      _heroTrailerShowing.removeListener(_onCanvasTrailerShowingChanged);
      HardwareKeyboard.instance.removeHandler(_onCanvasTheaterKey);
      HardwareKeyboard.instance.removeHandler(_onStageHoldKey);
    }
    _canvasTheaterTimer?.cancel();
    _canvasFavFocus.dispose();
    _atriumFocusedRailKey.dispose();
    _tonightCard.dispose();
    _stageCol.dispose();
    MainPageBridge.removeTvSidebarFocusListener(_onTvSidebarFocusChanged);
    if (_heroTrailerActive) {
      _heroTrailerTakeover.removeListener(_relayChromeDim);
      _heroTrailerShowing.removeListener(_relayLightsOff);
      MainPageBridge.removePlayerLaunchListener(_onContentPlayerLaunch);
      HardwareKeyboard.instance.removeHandler(_onTakeoverKey);
      appRouteObserver.unsubscribe(this);
      // Reset the shell notifiers AFTER this frame: dispose can run inside
      // finalizeTree (tab switch mid-takeover) while the tree is locked, and
      // a synchronous write would markNeedsBuild the sidebar's listener
      // mid-unmount.
      if (MainPageBridge.tvChromeDim.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvChromeDim.value = 0;
        });
      }
      if (MainPageBridge.tvHeroTint.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvHeroTint.value = null;
        });
      }
      if (MainPageBridge.tvAmbientArt.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvAmbientArt.value = null;
        });
      }
      if (MainPageBridge.tvStageLightsOff.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvStageLightsOff.value = false;
        });
      }
    }
    _catalogDebounce?.cancel();
    _heroTimer?.cancel();
    _heroSwapTimer?.cancel();
    _heroTrailerTimer?.cancel();
    _tintTimer?.cancel();
    _heroItem.dispose();
    _heroEnriched.dispose();
    _heroTrailer.dispose();
    _heroTrailerLoading.dispose();
    _heroTrailerShowing.dispose();
    _heroTrailerTakeover.dispose();
    _heroLiveUrl.dispose();
    _heroLiveChannel.dispose();
    _heroLiveTakeover.dispose();
    _heroTint.dispose();
    _searchController.dispose();
    _catalogSourcesHideTimer?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusForSources);
    _searchFocusNode.dispose();
    _modeCatalogNode.dispose();
    _modeKeywordNode.dispose();
    _modeListsNode.dispose();
    _modeDropdownNode.dispose();
    _disposeListsNodes();
    _discSourceNode.dispose();
    _discFocused.dispose();
    if (MainPageBridge.discoverCardSettingsChanged ==
        _onDiscoverCardSettingsChanged) {
      MainPageBridge.discoverCardSettingsChanged = null;
    }
    if (widget.discoverMode && widget.isTelevision) {
      _discTakeover.removeListener(_relayDiscoverChromeDim);
      _discTrailerShowing.removeListener(_onDiscShowingChanged);
      _discTheaterTimer?.cancel();
      // Only clear the bridge slot if it's still OURS — a newly-mounted
      // Discover instance may have claimed it before this one tears down.
      if (MainPageBridge.discoverLayoutChanged == _onDiscoverLayoutChanged) {
        MainPageBridge.discoverLayoutChanged = null;
      }
      // Never leave the sidebar hidden after Discover is torn down mid-takeover,
      // but reset AFTER this frame: dispose can run inside finalizeTree (tab
      // switch mid-takeover) while the tree is locked, and a synchronous write
      // would markNeedsBuild the sidebar's listener mid-unmount (matches the
      // Home path above).
      if (MainPageBridge.tvChromeDim.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MainPageBridge.tvChromeDim.value = 0;
        });
      }
    }
    _discTrailerStreams.dispose();
    _discTrailerLoading.dispose();
    _discTrailerVolume.dispose();
    _discTakeover.dispose();
    _discTrailerMeta.dispose();
    _discShown.dispose();
    _discTrailerShowing.dispose();
    _discTheater.dispose();
    _boardScroll.dispose();
    _kwScroll.dispose();
    _kwPillFocus.dispose();
    _kwSourcesBtnFocus.dispose();
    _catalogSourcesBtnFocus.dispose();
    for (final n in _kwTabNodes) {
      n.dispose();
    }
    _kwTabNodes.clear();
    _disposeNodes();
    _disposeKwNodes();
    for (final n in [
      ..._cwMovieNodes,
      ..._cwSeriesNodes,
      ..._iptvCwMovieNodes,
      ..._iptvCwSeriesNodes,
      ..._traktMovieNodes,
      ..._traktSeriesNodes,
      ..._simklMovieNodes,
      ..._simklSeriesNodes,
      ..._mdblistMovieNodes,
      ..._mdblistSeriesNodes,
      ..._tvFavNodes,
      ..._stvFavNodes,
      ..._iptvFavNodes,
      ..._watchlistMovieNodes,
      ..._watchlistSeriesNodes,
      ..._playlistFavNodes,
      ..._kwToolbarNodes, // fixed pool — only disposed here, not in _disposeKwNodes
    ]) {
      n.dispose();
    }
    _cwMovieNodes.clear();
    _cwSeriesNodes.clear();
    _iptvCwMovieNodes.clear();
    _iptvCwSeriesNodes.clear();
    _traktMovieNodes.clear();
    _traktSeriesNodes.clear();
    _simklMovieNodes.clear();
    _simklSeriesNodes.clear();
    _mdblistMovieNodes.clear();
    _mdblistSeriesNodes.clear();
    _tvFavNodes.clear();
    _stvFavNodes.clear();
    _iptvFavNodes.clear();
    _watchlistMovieNodes.clear();
    _watchlistSeriesNodes.clear();
    _playlistFavNodes.clear();
    super.dispose();
  }

  void _disposeNodes() {
    for (final row in _rowNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    _rowNodes.clear();
    // Row indices now remap to different content — drop stale column memory.
    _rowCol.clear();
  }

  /// Re-read the hidden-rows set + opted-in extras and reload the board if
  /// either actually changed. Fires on any home-settings change (the
  /// broadcast is shared), so the equality guards skip reloads for unrelated
  /// settings.
  Future<void> _reloadForHomeSettings() async {
    if (!mounted) return;
    final cardSettings = await Future.wait<Object>([
      StorageService.getHomeCardOrientation(),
      StorageService.getHomeHideCardTitlesAndRatings(),
      StorageService.getHomeHideCatalogAddonNames(),
    ]);
    if (!mounted) return;
    final orientation = cardSettings[0] as HomeCardOrientation;
    final hideTitlesAndRatings = cardSettings[1] as bool;
    final hideCatalogAddonNames = cardSettings[2] as bool;
    if (orientation != _homeCardOrientation ||
        hideTitlesAndRatings != _hideHomeCardTitlesAndRatings ||
        hideCatalogAddonNames != _hideHomeCatalogAddonNames) {
      setState(() {
        _homeCardOrientation = orientation;
        _hideHomeCardTitlesAndRatings = hideTitlesAndRatings;
        _hideHomeCatalogAddonNames = hideCatalogAddonNames;
      });
    }
    // Merged-CW toggles: re-read, and on a change re-sync each provider's node
    // lists against the lists already in memory (no refetch needed — the data
    // is the same, only which slot renders it changes).
    final mergeFlags = await Future.wait([
      StorageService.getHomeCwMergedRows('local'),
      StorageService.getHomeCwMergedRows('trakt'),
      StorageService.getHomeCwMergedRows('simkl'),
      StorageService.getHomeCwMergedRows('mdblist'),
    ]);
    if (!mounted) return;
    if (mergeFlags[0] != _cwMergeLocal ||
        mergeFlags[1] != _cwMergeTrakt ||
        mergeFlags[2] != _cwMergeSimkl ||
        mergeFlags[3] != _cwMergeMdblist) {
      setState(() {
        _cwMergeLocal = mergeFlags[0];
        _cwMergeTrakt = mergeFlags[1];
        _cwMergeSimkl = mergeFlags[2];
        _cwMergeMdblist = mergeFlags[3];
        _syncCwNodes(
          _cwMovieNodes,
          _cwMergeLocal ? _cwAll.length : _cwMovies.length,
          'movie',
        );
        _syncCwNodes(
          _cwSeriesNodes,
          _cwMergeLocal ? 0 : _cwSeries.length,
          'series',
        );
        _syncCwNodes(
          _traktMovieNodes,
          _cwMergeTrakt ? _traktAll.length : _traktMovies.length,
          'tmovie',
        );
        _syncCwNodes(
          _traktSeriesNodes,
          _cwMergeTrakt ? 0 : _traktSeries.length,
          'tseries',
        );
        _syncCwNodes(
          _simklMovieNodes,
          _cwMergeSimkl ? _simklAll.length : _simklMovies.length,
          'smovie',
        );
        _syncCwNodes(
          _simklSeriesNodes,
          _cwMergeSimkl ? 0 : _simklSeries.length,
          'sseries',
        );
        _syncCwNodes(
          _mdblistMovieNodes,
          _cwMergeMdblist ? _mdblistAll.length : _mdblistMovies.length,
          'mdbmovie',
        );
        _syncCwNodes(
          _mdblistSeriesNodes,
          _cwMergeMdblist ? 0 : _mdblistSeries.length,
          'mdbseries',
        );
      });
    }
    // Off-TV the hero-trailer prefs ride this same signal — Settings is a
    // pushed route here, so nothing else tells a surviving Home about them.
    if (!widget.isTelevision) {
      unawaited(_reloadOffTvHeroTrailerPrefs());
    }
    await _loadHomeDefaultView();
    if (!mounted) return;
    final disabled = await StorageService.getHomeDisabledSections();
    final extras = await StorageService.getHomeExtraRows();
    final rowOrder = await StorageService.getHomeRowOrder();
    final heroSource = await StorageService.getHomeHeroSource();
    final collections = await _readHomeCollections();
    if (!mounted) return;
    final hideWatched = HideWatchedPrefs.enabled;
    final hideWatchedUnchanged = hideWatched == _hideWatched;
    final collectionsSig = HomeCollectionsStore.signatureOf(collections);
    final collectionsUnchanged = collectionsSig == _homeCollectionsSig;
    final disabledUnchanged =
        disabled.length == _homeDisabled.length &&
        disabled.containsAll(_homeDisabled);
    final heroSourceUnchanged =
        heroSource.mode == _heroSource.mode &&
        listEquals(heroSource.ids, _heroSource.ids);
    final rowOrderUnchanged = HomeRowOrder.equals(rowOrder, _homeRowOrder);
    // Titles participate too: a stored rename must re-render the row header.
    // Diffed per family: `iptvlist:` extras feed the favourites-family rows,
    // everything else feeds the board pipeline — so toggling an IPTV list
    // row must not refetch every addon catalog, and vice versa.
    List<HomeExtraRow> family(List<HomeExtraRow> rows, {required bool iptv}) =>
        [
          for (final r in rows)
            if (HomeExtraRowIds.isIptv(r.id) == iptv) r,
        ];
    bool sameRows(List<HomeExtraRow> a, List<HomeExtraRow> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (i) => a[i].id == b[i].id && a[i].title == b[i].title,
        ).every((same) => same);
    final boardExtrasUnchanged = sameRows(
      family(extras, iptv: false),
      family(_homeExtras, iptv: false),
    );
    final iptvExtrasUnchanged = sameRows(
      family(extras, iptv: true),
      family(_homeExtras, iptv: true),
    );
    if (disabledUnchanged &&
        boardExtrasUnchanged &&
        iptvExtrasUnchanged &&
        rowOrderUnchanged &&
        heroSourceUnchanged &&
        hideWatchedUnchanged &&
        collectionsUnchanged) {
      return;
    }
    setState(() {
      _homeDisabled = disabled;
      _homeExtras = extras;
      _homeRowOrder = rowOrder;
      _heroSource = heroSource;
      _hideWatched = hideWatched;
      _homeCollections = collections;
      _homeCollectionsSig = collectionsSig;
    });
    // Hide-watched changes row MEMBERSHIP, so it takes the full reload path.
    if (!disabledUnchanged ||
        !boardExtrasUnchanged ||
        !hideWatchedUnchanged ||
        !collectionsUnchanged ||
        (!rowOrderUnchanged && !widget.searchMode && !widget.discoverMode)) {
      _requestBoardReload();
    } else if (!heroSourceUnchanged &&
        !widget.searchMode &&
        !widget.discoverMode) {
      // Only the hero source moved — re-roll the reel without refetching the
      // whole board. `_load` isn't rerun here, so resolve from the addons the
      // last load cached.
      unawaited(_resolveSpotlightHeroSource(_addonsById.values.toList()));
    }
    // IPTV list rows live outside the board's section pipeline. The loader
    // reads its own extras from storage, so it can't race the reload above.
    if (!iptvExtrasUnchanged) unawaited(_loadIptvListRows());
  }

  /// Run [_load] for a TRIGGERED reload (Home Rows save, integration
  /// connect/disconnect) — unless a catalog search is showing its results, in
  /// which case `_load`'s visible reset would stomp the search view. The
  /// reload is latched instead and [_restoreHome] performs it when the board
  /// comes back. (The initState load never comes through here.)
  void _requestBoardReload() {
    if (_catalogQuery.isNotEmpty || _catalogSearching) {
      _pendingBoardReload = true;
      return;
    }
    _load();
  }

  Future<void> _loadHomeDefaultView() async {
    // Android TV has dedicated Home and Search tabs. Its Home is always the
    // catalog board, regardless of a preference saved on another platform.
    if (widget.isTelevision) {
      if (_mode != _Mode.catalog) _switchMode(_Mode.catalog);
      return;
    }
    final saved = await StorageService.getHomeDefaultSourceType();
    if (!mounted || widget.searchMode || widget.discoverMode) return;
    final mode =
        saved == 'keyword' &&
            ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)
        ? _Mode.keyword
        : _Mode.catalog;
    if (_mode != mode) _switchMode(mode);
  }

  void _commitBoardSnapshot() {
    _committedBoard = HomeBoardSnapshot(_boardRefs, _boardCursor, _addonsById);
  }

  Future<void> _load({bool preserveVisibleRows = false}) async {
    final keepRows = preserveVisibleRows &&
        _homeSections.isNotEmpty &&
        _committedBoard != null;
    final previousBoard = keepRows ? _committedBoard : null;
    final previouslyLoaded = previousBoard?.cursor ?? 0;
    final previousRows = <String, CatalogSection>{
      if (keepRows)
        for (final row in _homeSections)
          if (row is! HomeListSection) _sectionRowId(row): row,
    };
    final gen = ++_boardLoadGen;
    var completionGen = gen;
    var expired = false;
    // A superseded pagination request may never return. Its finally block is
    // generation-guarded, so it cannot clear a newer request's loading flag.
    _boardLoadingMore = false;
    _boardRefreshing = true;
    setState(() {
      if (!keepRows) _loading = true;
      _error = null;
    });
    unawaited(_refreshPikpakOnly());
    try {
      await runHomeLoadWithDeadline(
        retire: () {
          if (!mounted || gen != _boardLoadGen) return;
          expired = true;
          completionGen = ++_boardLoadGen;
          // Retiring the generation stops stale batches. A refresh timeout
          // must restore the paging state belonging to the still-visible rows.
          if (previousBoard != null) {
            _boardCursor = previousBoard.restore(_boardRefs, _addonsById);
          } else {
            _boardRefs.clear();
            _boardCursor = 0;
          }
        },
        load: () async {
          final disabled = await StorageService.getHomeDisabledSections();
          final extras = await StorageService.getHomeExtraRows();
          final rowOrder = await StorageService.getHomeRowOrder();
          final heroSource = await StorageService.getHomeHeroSource();
          final collections = await _readHomeCollections();
          // Commit the prefs and (crucially) start the tracker fan-out only if
          // this load still owns the board — a superseded run kicking off its own
          // resolve would double the concurrent tracker requests beside the
          // winning generation's and stale-write the shared settings fields.
          if (!mounted || gen != _boardLoadGen) return;
          _homeDisabled = disabled;
          _homeExtras = extras;
          _homeRowOrder = rowOrder;
          _heroSource = heroSource;
          _hideWatched = HideWatchedPrefs.enabled;
          _homeCollections = collections;
          _homeCollectionsSig = HomeCollectionsStore.signatureOf(collections);
          // Opt-in Trakt/Simkl list rows, resolved IN PARALLEL with the first
          // catalog batch below. Home board only — the Search tab runs _load just
          // to warm the catalog refs for its search, and Discover never comes
          // through here. The 5s deadline keeps the rows that finished and drops
          // stragglers, bounding what an enabled config can add to first paint
          // (nothing at all is fetched in the default, nothing-enabled config).
          final listRowsFuture =
              widget.searchMode || widget.discoverMode || !_trackerExtrasEnabled
              ? Future.value(const <HomeListSection>[])
              // catchError at creation, not at the await: a superseded load
              // returns before awaiting this future, and an unawaited throw
              // would surface as an unhandled async error. A resolve failure
              // just means no list rows this load.
              : HomeListRowsService.instance
                    .resolve(_homeExtras, deadline: const Duration(seconds: 5))
                    .catchError((_) => const <HomeListSection>[]);
          // With hide-watched on, wait briefly for the local watched snapshot so
          // the first rows paint already filtered instead of losing titles a beat
          // later. Tracker histories fold in asynchronously and apply from the
          // next load; the timeout keeps a slow disk from stalling first paint.
          if (HideWatchedPrefs.enabled) {
            WatchedStatusService.instance.ensureStarted();
            await WatchedStatusService.instance.firstSnapshot.timeout(
              const Duration(milliseconds: 1500),
              onTimeout: () {},
            );
            if (!mounted || gen != _boardLoadGen) return;
          }
          final addons = await _stremio.getCatalogAddons();
          if (!mounted || gen != _boardLoadGen) return;
          // Enumerate every BROWSABLE catalog across all addons — no global row cap.
          // This is cheap (manifest data); items are pulled lazily in batches on
          // scroll. Catalogs that require a `search` extra are search-only: browsing
          // them without a query just returns empty after a wasted round trip, so
          // skip them here (they still power the Keyword/catalog search path).
          // Catalogs the user hid in the Home Rows manager are skipped too.
          // Catalogs claimed by an enabled collection folder live inside that
          // folder (as in Nuvio) and never double up as plain board rows.
          final claimed = HomeCollectionsStore.claimedCatalogKeys(
            _homeCollections,
            addons,
            disabledRows: _homeDisabled,
            showsCollectionRows: !widget.searchMode && !widget.discoverMode,
          );
          final boardRefs = [
            for (final a in addons)
              for (final c in a.catalogs)
                if (c.isBrowsable &&
                    !_homeDisabled.contains('${a.id}:${c.type}:${c.id}') &&
                    !claimed.contains('${a.id}:${c.type}:${c.id}'))
                  (a, c),
          ];
          _boardRefs
            ..clear()
            ..addAll(
              _homeRowOrderActive
                  ? HomeRowOrder.apply(boardRefs, _homeRowOrder, _catalogRefRowId)
                  : boardRefs,
            );
          _boardCursor = 0;
          _addonsById.clear();
          for (final a in addons) {
            _addonsById.putIfAbsent(a.id, () => a);
          }
          // Resolve the Spotlight hero's own reel in parallel with the first
          // batch — its catalog may sit far down the board (or be hidden as a
          // row), so it can't wait for a batch to happen to include it. Home
          // board only, like the list rows above.
          if (!widget.searchMode && !widget.discoverMode) {
            unawaited(_resolveSpotlightHeroSource(addons));
          }
          // First batch is blocking so the board isn't empty on first paint; skip
          // runs of empty catalogs so we always land on some visible rows.
          final first = await _fetchBoardBatchUntilNonEmpty(gen, previousRows: previousRows);
          // Keep the previously loaded vertical extent when addons change.
          while (gen == _boardLoadGen && _boardCursor < previouslyLoaded &&
              _boardCursor < _boardRefs.length) {
            first.addAll(await _fetchBoardBatch(_kBoardBatchSize, gen, previousRows: previousRows));
          }
          final listRows = await listRowsFuture;
          if (!mounted || gen != _boardLoadGen) return;
          // List rows lead the sections — after the favourites rows, before every
          // addon catalog row. Batching appends after them untouched.
          // Imported collections follow Nuvio's order: pinned ones lead the
          // board, the rest sit after the tracker list rows and before every
          // addon catalog row. No network — folders are static tiles.
          final collectionRows = widget.searchMode || widget.discoverMode
              ? const <HomeCollectionSection>[]
              : _buildCollectionSections();
          final sections = <CatalogSection>[
            for (final s in collectionRows)
              if (s.collection.pinToTop) s,
            ...listRows,
            for (final s in collectionRows)
              if (!s.collection.pinToTop) s,
            ...first,
          ];
          _homeSections = sections;
          _commitBoardSnapshot();
          setState(() => _loading = false);
          MainPageBridge.homeBoardReady.value = true;
          // A catalog search may have STARTED while this load was in flight —
          // `_sections` now holds (or is streaming) search results, and applying
          // the board over them would permanently mix the two views. Same
          // discipline as _loadMoreBoard: the Home cache above is refreshed, the
          // visible view is not — _restoreHome re-applies _homeSections when the
          // search ends.
          if (_catalogQuery.isNotEmpty || _catalogSearching) return;
          _applySections(sections, preserveFocus: keepRows);
          _maybeAutoFocusBoard();
          // Pagination resumes after the refresh releases its cursor below.
        },
      );
    } catch (e) {
      if (!mounted || completionGen != _boardLoadGen) return;
      // Mid-search, the error screen must not replace the search results
      // (_buildBoard renders _error before anything else) — latch a retry
      // for _restoreHome instead.
      if (_catalogQuery.isNotEmpty || _catalogSearching) {
        _pendingBoardReload = true;
        setState(() => _loading = false);
        MainPageBridge.homeBoardReady.value = true;
        return;
      }
      setState(() {
        if (!keepRows) {
          _error = expired
              ? 'Home took too long to load. Please try again.'
              : e.toString();
        }
        _loading = false;
      });
      if (expired && keepRows) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text("Couldn't refresh Home. Showing previous rows."),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                if (mounted) unawaited(_load(preserveVisibleRows: true));
              },
            ),
          ),
        );
      }
      // Terminal state too — the launch splash must not outlive the board's
      // loading phase just because it ended in an error screen.
      MainPageBridge.homeBoardReady.value = true;
    } finally {
      if (completionGen == _boardLoadGen) {
        _boardRefreshing = false;
        if (mounted && !expired) _maybeAutoFillBoard();
      }
    }
  }
  /// Fetch the next batch of catalog rows from [_boardCursor], skipping over any
  /// runs of empty catalogs, and return the non-empty sections (advancing the
  /// cursor as it goes). Empty result ⇒ the board is exhausted — or [gen] went
  /// stale (a newer [_load] owns the cursor now; stop without touching it).
  Future<List<CatalogSection>> _fetchBoardBatchUntilNonEmpty(int gen, {Map<String, CatalogSection> previousRows = const {}}) async {
    while (gen == _boardLoadGen && _boardCursor < _boardRefs.length) {
      final batch = await _fetchBoardBatch(_kBoardBatchSize, gen, previousRows: previousRows);
      if (batch.isNotEmpty) return batch;
    }
    return const [];
  }

  /// Fetch exactly one batch of up to [n] catalog rows in parallel, advancing
  /// [_boardCursor], and return the non-empty ones (order preserved). No-ops
  /// when [gen] is stale so a superseded load can't advance the fresh load's
  /// cursor.
  Future<List<CatalogSection>> _fetchBoardBatch(int n, int gen, {Map<String, CatalogSection> previousRows = const {}}) async {
    if (gen != _boardLoadGen) return const [];
    final end = (_boardCursor + n).clamp(0, _boardRefs.length);
    final slice = _boardRefs.sublist(_boardCursor, end);
    _boardCursor = end;
    final results = await Future.wait(
      slice.map((ref) async {
        final (addon, catalog) = ref;
        try {
          return await loadHomeCatalogSection(
            addon: addon,
            catalog: catalog,
            previous: previousRows[_catalogRefRowId(ref)],
            isCurrent: () => mounted && gen == _boardLoadGen,
            hides: WatchedFilter.predicate,
            fetch: (skip, onRawCount) => _stremio.fetchCatalog(
              addon, catalog, skip: skip, onRawCount: onRawCount,
            ),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<CatalogSection>().toList();
  }

  /// After a batch lands, if the board still doesn't fill the viewport (so the
  /// user can't scroll to trigger more) keep pulling batches until it does or
  /// the board is exhausted. No-ops outside board mode (search sets no cursor).
  void _maybeAutoFillBoard() {
    if (!_boardHasMore || _boardLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_boardHasMore || _boardLoadingMore) return;
      if (!_boardScroll.hasClients) return;
      final pos = _boardScroll.position;
      if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 600) {
        _loadMoreBoard();
      }
    });
  }

  /// Fire off the next batch as the user nears the bottom of the board.
  void _onBoardScroll() {
    if (!_boardHasMore || _boardLoadingMore) return;
    if (!_boardScroll.hasClients) return;
    final pos = _boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMoreBoard();
    }
  }

  /// Load and append the next batch of board rows (deduped against re-entry).
  Future<bool> _loadMoreBoard() async {
    if (_boardRefreshing || _boardLoadingMore ||
        _boardCursor >= _boardRefs.length) {
      return false;
    }
    // Bind this append to the load generation that owns the current cursor —
    // if a full reload lands mid-fetch, the stale batch must not append onto
    // (or advance) the fresh board.
    final gen = _boardLoadGen;
    var appended = false;
    setState(() => _boardLoadingMore = true);
    try {
      final more = await _fetchBoardBatchUntilNonEmpty(gen);
      if (!mounted || gen != _boardLoadGen) return false;
      _commitBoardSnapshot();
      if (more.isNotEmpty) {
        // Always keep the board cache growing so nothing is lost…
        _homeSections = [..._homeSections, ...more];
        // …but only fold into the live view when the board is still what's
        // shown. If a catalog search started while this batch was in flight,
        // `_sections`/`_rowNodes` now hold search results — appending board rows
        // there would corrupt the search view. They'll reappear on _restoreHome.
        if (_catalogQuery.isEmpty && !_catalogSearching) {
          _appendSections(more);
          appended = true;
          // A DPAD-down past the last row may be waiting on this batch —
          // classic's deferred move, and the stage layouts' rail advance.
          _maybeCompleteDeferredDown();
          _maybeCompleteStageAdvance();
        }
      }
    } finally {
      if (mounted && gen == _boardLoadGen) {
        setState(() => _boardLoadingMore = false);
        _maybeAutoFillBoard();
      }
    }
    return appended;
  }

  /// Append newly-loaded board rows without disturbing the rows already shown:
  /// grow the per-row focus nodes in lockstep with [_sections].
  void _appendSections(List<CatalogSection> more) {
    for (final section in more) {
      _rowNodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(debugLabel: 'search_r${_rowNodes.length}_c$i'),
        ),
      );
    }
    setState(() => _sections = [..._sections, ...more]);
    unawaited(_refreshBoundSources());
  }

  /// Fetch the next page for a single catalog row and append it in place, so
  /// rows grow without bound as the user scrolls right (Stremio-style). Only
  /// board rows paginate; search-result rows are single-shot. Safe to call
  /// repeatedly — [CatalogSection.loadingMore]/[CatalogSection.exhausted] guard
  /// re-entrancy and the end of the catalog.
  Future<void> _loadMoreRow(int rowIndex, {bool resume = false}) async {
    // While a catalog search is active, `_sections` holds search results, which
    // don't paginate — leave them alone.
    if (_catalogQuery.isNotEmpty || _catalogSearching) return;
    if (rowIndex < 0 || rowIndex >= _sections.length) return;
    final section = _sections[rowIndex];
    if (section.pagingPaused && !resume) return;
    if (section.loadingMore || section.exhausted) return;
    // Android TV: flip the guard silently. The setState exists to show the
    // classic row's tail spinner, but it fires on the exact keypress that
    // crossed the row-end threshold — a full-screen rebuild landing on the
    // input frame, which an Amlogic box renders as the cursor hitching every
    // time a row pages. The spinner is a nicety; the page landing repaints
    // either way.
    if (PlatformUtil.isAndroidTvCached && !resume) {
      section.loadingMore = true;
    } else {
      setState(() => section.loadingMore = true);
    }
    try {
      // Dedup against what we already have: some addons return valid ids but
      // repeat entries, and some ignore `skip` entirely. The pager advances
      // `skip` by the addon's RAW counts so paging never under-advances into a
      // false "exhausted", and with hide-watched on it tops the window up so a
      // page of watched titles doesn't end the row early.
      final seen = section.items.map((m) => m.id).toSet();
      final page = await fetchFilteredPage(
        (skip, onRaw) => _stremio.fetchCatalog(
          section.addon,
          section.catalog,
          skip: skip,
          onRawCount: onRaw,
        ),
        skip: section.nextSkip,
        hides: WatchedFilter.predicate,
        seenIds: seen,
      );
      if (!mounted) return;
      // The row may have been swapped out (a search started) while in flight.
      if (rowIndex >= _sections.length ||
          !identical(_sections[rowIndex], section)) {
        return;
      }
      section.nextSkip = page.nextSkip;
      if (page.exhausted) section.exhausted = true;
      final fresh = page.items;
      section.pagingPaused = fresh.isEmpty && !page.exhausted;
      if (fresh.isEmpty) return;
      // Grow this row's focus nodes in lockstep with the new items.
      final nodes = _rowNodes[rowIndex];
      final base = nodes.length;
      for (var i = 0; i < fresh.length; i++) {
        nodes.add(FocusNode(debugLabel: 'search_r${rowIndex}_c${base + i}'));
      }
      setState(() => section.items.addAll(fresh));
      // A DPAD-right that ran off the end of this row may be waiting on it.
      _maybeCompleteStageRight();
      unawaited(_refreshBoundSources());
    } catch (_) {
      // Transient fetch failure — leave the row as-is so a later scroll retries.
    } finally {
      if (mounted) {
        setState(() => section.loadingMore = false);
      } else {
        section.loadingMore = false;
      }
    }
  }

  /// IMDb id for a catalog item, or null when it isn't a `tt…` id.
  String? _imdbOf(StremioMeta item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool _isBound(StremioMeta item) {
    final id = _imdbOf(item);
    return id != null && (_boundCounts[id] ?? 0) > 0;
  }

  int _boundCountFor(StremioMeta item) {
    final id = _imdbOf(item);
    return id == null ? 0 : (_boundCounts[id] ?? 0);
  }

  /// Re-read how many pinned sources each currently-displayed title has. Called
  /// after sections load and after any bind/unbind/playback.
  Future<void> _refreshBoundSources() async {
    final counts = <String, int>{};
    final seen = <String>{};
    // Cover every on-screen tile that renders a bound badge: catalog sections
    // AND the Continue Watching rows (whose titles may not appear in any
    // section, so editing their sources must still refresh the CW card badge).
    final items = [
      for (final section in _sections) ...section.items,
      ..._cwMovies,
      ..._cwSeries,
      ..._traktMovies,
      ..._traktSeries,
      ..._simklMovies,
      ..._simklSeries,
      ..._mdblistMovies,
      ..._mdblistSeries,
    ];
    for (final item in items) {
      final imdb = _imdbOf(item);
      if (imdb == null || !seen.add(imdb)) continue;
      final n = (await SeriesSourceService.getSources(imdb)).length;
      if (n > 0) counts[imdb] = n;
    }
    if (!mounted) return;
    setState(
      () => _boundCounts
        ..clear()
        ..addAll(counts),
    );
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() async {
    final pikpak = await StorageService.getPikPakEnabled();
    final rd = await StorageService.getApiKey();
    final tb = await StorageService.getTorboxApiKey();
    final pm = await StorageService.getPremiumizeApiKey();
    final ad = await StorageService.getAllDebridApiKey();
    final anyOther =
        (rd != null && rd.isNotEmpty) ||
        (tb != null && tb.isNotEmpty) ||
        (pm != null && pm.isNotEmpty) ||
        (ad != null && ad.isNotEmpty);
    final onlyPikpak = pikpak && !anyOther;
    if (mounted && onlyPikpak != _pikpakOnly) {
      setState(() => _pikpakOnly = onlyPikpak);
    }
  }

  /// Load the Continue Watching row from the shared local store. Mirrors
  /// Home's join (item list + per-title playback progress) but is read-only —
  /// it never writes, so Home's row is untouched. Safe to call repeatedly
  /// (e.g. after returning from a detail/playback).
  Future<void> _loadContinueWatching() async {
    final token = ++_cwLoadToken;
    // Every CW reload passes through here (init, Home-settings change,
    // integration change, post-playback), so it is the one place the card
    // lookups need their Progress source refreshed.
    final progressSource = await StorageService.getWatchProgressSource();
    final enabled = await StorageService.getHomeContinueWatchingEnabled();
    if (!mounted || token != _cwLoadToken) return;
    if (progressSource != _cwProgressSource) {
      setState(() => _cwProgressSource = progressSource);
    }
    if (!enabled) {
      // Free the focus nodes too — otherwise they linger allocated until
      // dispose while the rows are hidden.
      _syncCwNodes(_cwMovieNodes, 0, 'movie');
      _syncCwNodes(_cwSeriesNodes, 0, 'series');
      setState(() {
        _cwEnabled = false;
        _cwMovies = [];
        _cwSeries = [];
        _cwAll = [];
        _cwIds.clear();
        _cwProgress.clear();
        _cwEpisode.clear();
        _cwRemainingMinutes.clear();
        _cwEpisodeArtwork.clear();
        _cwAddonId.clear();
      });
      return;
    }

    final raw = await StorageService.getContinueWatchingItems();
    final items = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final remainingMinutes = <String, int>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final ids = <String>{};
    final addonIds = <String, String?>{};
    for (final m in raw) {
      final imdbId = m['imdbId'] as String?;
      if (imdbId == null || imdbId.isEmpty) continue;
      final type = (m['contentType'] as String?) ?? 'movie';
      items.add(
        StremioMeta(
          id: imdbId,
          imdbId: imdbId,
          type: type,
          name: (m['title'] as String?) ?? 'Untitled',
          poster: m['posterUrl'] as String?,
          year: m['year'] as String?,
        ),
      );
      ids.add(imdbId);
      addonIds[imdbId] = m['addonId'] as String?;

      // Watched fraction — joined from the playback-state store, exactly like
      // HomeContinueWatchingSection (finished episodes count as 100%).
      double? pct;
      if (type == 'series') {
        final lastEp = await StorageService.getLastPlayedEpisodeByImdbId(
          imdbId,
        );
        if (lastEp != null) {
          final finished = lastEp['finished'] == true;
          final posMs = lastEp['positionMs'] as int? ?? 0;
          final durMs = lastEp['durationMs'] as int? ?? 1;
          if (durMs > 0) {
            pct = finished ? 100.0 : (posMs / durMs * 100).clamp(0.0, 100.0);
          }
          final se = _seLabel(
            lastEp['season'] as int?,
            lastEp['episode'] as int?,
          );
          if (se != null) episode[imdbId] = se;
          final season = lastEp['season'] as int?;
          final episodeNumber = lastEp['episode'] as int?;
          if (season != null &&
              episodeNumber != null &&
              season > 0 &&
              episodeNumber > 0) {
            episodeRefs[imdbId] = (season: season, episode: episodeNumber);
          }
          final left = continueWatchingMinutesLeft(
            positionMs: posMs,
            durationMs: durMs,
          );
          if (left != null) remainingMinutes[imdbId] = left;
        }
      } else {
        final state = await StorageService.getVideoPlaybackStateByImdbId(
          imdbId,
        );
        if (state != null) {
          final posMs = state['positionMs'] as int? ?? 0;
          final durMs = state['durationMs'] as int? ?? 1;
          if (durMs > 0) pct = (posMs / durMs * 100).clamp(0.0, 100.0);
          final left = continueWatchingMinutesLeft(
            positionMs: posMs,
            durationMs: durMs,
          );
          if (left != null) remainingMinutes[imdbId] = left;
        }
      }
      if (pct != null) progress[imdbId] = pct / 100.0;
    }

    await _ensureCwMergeFlags();
    // Bail if a newer load superseded this one while we were awaiting — never
    // dispose/replace nodes or state a later run already committed.
    if (!mounted || token != _cwLoadToken) return;

    // Split into two recency-ordered rows; `items` is already most-recent-first.
    final movies = items.where((m) => m.type != 'series').toList();
    final series = items.where((m) => m.type == 'series').toList();
    // Keep each row's focus-node list length in sync with its item count. Only
    // rebuild when the count changes (a plain refresh keeps the same nodes so
    // an active TV focus isn't dropped). Merged mode renders the combined list
    // through the movies slot, so its node count follows `items`.
    _syncCwNodes(
      _cwMovieNodes,
      _cwMergeLocal ? items.length : movies.length,
      'movie',
    );
    _syncCwNodes(_cwSeriesNodes, _cwMergeLocal ? 0 : series.length, 'series');

    setState(() {
      _cwEnabled = true;
      _cwMovies = movies;
      _cwSeries = series;
      _cwAll = items;
      _cwIds
        ..clear()
        ..addAll(ids);
      _cwProgress
        ..clear()
        ..addAll(progress);
      _cwEpisode
        ..clear()
        ..addAll(episode);
      _cwRemainingMinutes
        ..clear()
        ..addAll(remainingMinutes);
      _cwEpisodeArtwork.clear();
      _cwAddonId
        ..clear()
        ..addAll(addonIds);
    });
    unawaited(
      _enrichCwEpisodeArtwork(
        refs: episodeRefs,
        target: _cwEpisodeArtwork,
        isCurrent: () => token == _cwLoadToken,
      ),
    );
    _maybeAutoFocusBoard();
  }

  void _onLocalCompletionChanged() {
    if (!mounted || widget.searchMode || widget.discoverMode) return;
    unawaited(_loadContinueWatching());
  }

  /// Load the IPTV Continue Watching shelves (Xtream VOD movies + series) from
  /// the player's own watch history. Independent of [_loadContinueWatching] —
  /// different data source, different (non-IMDb) identity — but follows the same
  /// token-guard + node-sync discipline so a slow reload can't clobber a newer
  /// one or drop the focus node the user is sitting on.
  Future<void> _loadIptvContinueWatching() async {
    // Never rendered on the dedicated Search tab (mirrors the tracker rows).
    if (widget.searchMode) return;
    final token = ++_iptvCwLoadToken;
    final rows = await IptvCwRouter.load();
    if (!mounted || token != _iptvCwLoadToken) return;

    StremioMeta metaFor(IptvCwEntry e) => StremioMeta(
      // routeKey as the id (no imdbId → all addon enrichment / bound-source /
      // hero-trailer lookups no-op, which is what we want for IPTV).
      id: e.routeKey,
      type: e.isSeries ? 'series' : 'movie',
      name: e.title,
      poster: e.posterUrl,
    );

    final movies = [for (final e in rows.movies) metaFor(e)];
    final series = [for (final e in rows.series) metaFor(e)];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final byKey = <String, IptvCwEntry>{};
    for (final e in [...rows.movies, ...rows.series]) {
      byKey[e.routeKey] = e;
      progress[e.routeKey] = e.progress;
      if (e.seLabel != null) episode[e.routeKey] = e.seLabel!;
    }

    _syncCwNodes(_iptvCwMovieNodes, movies.length, 'iptv-movie');
    _syncCwNodes(_iptvCwSeriesNodes, series.length, 'iptv-series');

    setState(() {
      _iptvCwMovies = movies;
      _iptvCwSeries = series;
      _iptvCwProgress
        ..clear()
        ..addAll(progress);
      _iptvCwEpisode
        ..clear()
        ..addAll(episode);
      _iptvCwByKey
        ..clear()
        ..addAll(byKey);
    });
    _maybeAutoFocusBoard();
  }

  int? _iptvRemainingMinutes(String routeKey) {
    final raw = _iptvCwByKey[routeKey]?.raw;
    if (raw == null) return null;
    return continueWatchingMinutesLeft(
      positionMs: (raw['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Resolve episode stills away from the build path, at TV-safe concurrency.
  /// A provider refresh owns the result through [isCurrent], so an older batch
  /// can never paint the episode that preceded a newly-resumed one.
  Future<void> _enrichCwEpisodeArtwork({
    required Map<String, ({int season, int episode})> refs,
    required Map<String, String> target,
    required bool Function() isCurrent,
  }) async {
    if (refs.isEmpty) return;
    final resolved = await mapWithConcurrency(refs.entries, (entry) async {
      final art = await EpisodeArtworkService.instance.resolve(
        imdbId: entry.key,
        season: entry.value.season,
        episode: entry.value.episode,
      );
      return (id: entry.key, art: art);
    }, concurrency: 3);
    if (!mounted || !isCurrent()) return;
    final artwork = <String, String>{
      for (final item in resolved)
        if (item.art != null && item.art!.isNotEmpty) item.id: item.art!,
    };
    if (artwork.isEmpty) return;
    setState(() => target.addAll(artwork));
  }

  /// Open an IPTV Continue Watching card: a series routes to the merged Xtream
  /// series page, a movie resumes playback. Both go through [IptvCwRouter];
  /// [_playedSinceRefresh] latches so the return refresh rebuilds the shelves.
  Future<void> _openIptvCwItem(StremioMeta item) async {
    final entry = _iptvCwByKey[item.id];
    if (entry == null) return;
    _playedSinceRefresh = true;
    await IptvCwRouter.open(context, entry, isTelevision: widget.isTelevision);
    if (!mounted) return;
    // Off-TV push() awaits to the pop; on TV the native-return hook
    // ([_onPlaybackReturned]) refreshes. Refresh here too for the in-app path
    // (series detail / in-app player) so a resumed position updates the shelf.
    await _refreshAfterPlayback();
  }

  /// Resize a Continue Watching row's focus-node list to [count], preserving
  /// the surviving prefix. This used to dispose-and-recreate ALL the row's
  /// nodes on any length change — and these re-sync on every return from
  /// playback/detail (the CW list almost always changes then), so it destroyed
  /// the very node focus was sitting on: primary focus died with it and the
  /// remote went dead until app relaunch. Now only a shrinking tail is
  /// disposed, and if focus sat in that tail it's handed to the nearest
  /// survivor.
  void _syncCwNodes(List<FocusNode> nodes, int count, String tag) {
    if (nodes.length == count) return;
    if (count < nodes.length) {
      var tailHadFocus = false;
      for (var i = count; i < nodes.length; i++) {
        if (nodes[i].hasFocus) {
          tailHadFocus = true;
          break;
        }
      }
      while (nodes.length > count) {
        nodes.removeLast().dispose();
      }
      // After the disposal so the dying node can't fight the handoff; a row
      // emptied to zero has no survivor — the dead-focus reclaim listener
      // picks that case up. Mounted-aware move: the last survivor's cell may
      // be virtualized out, and requestFocus on a detached node latches a
      // focus-when-reparented that would yank focus when it scrolls back in.
      if (tailHadFocus && count > 0) {
        _requestRowFocus(nodes, count - 1);
      }
    } else {
      for (var i = nodes.length; i < count; i++) {
        nodes.add(FocusNode(debugLabel: 'search_cw_${tag}_$i'));
      }
    }
  }

  /// Focus a card in the Continue Watching row at [cwIndex] (index into the
  /// visible CW rows), clamping the column to that row's length. Returns
  /// whether a focus move was actually attempted — false means the target row
  /// doesn't exist (yet), so callers can fall through or defer instead of
  /// silently swallowing the DPAD press.
  bool _focusCwRow(int cwIndex, int column) {
    final rows = _cwRows;
    if (cwIndex < 0 || cwIndex >= rows.length) return false;
    final nodes = rows[cwIndex].nodes;
    if (nodes.isEmpty) return false;
    _requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  // The leading favourites rows (between Continue Watching and the catalog) are
  // only shown on the board, never over search results — same gate as
  // [_cwVisible]. Each has its own visibility so an empty source just drops out.
  bool get _iptvFavVisible =>
      _iptvFavChannels.isNotEmpty &&
      !_homeDisabled.contains('fav:iptv') &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;
  bool get _tvFavVisible =>
      _tvFavChannels.isNotEmpty &&
      !_homeDisabled.contains('fav:debrify') &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;
  bool get _stvFavVisible =>
      _stvFavChannels.isNotEmpty &&
      !_homeDisabled.contains('fav:stremio') &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;
  bool get _playlistFavVisible =>
      _playlistItems.isNotEmpty &&
      !_homeDisabled.contains('fav:playlist') &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;
  bool get _watchlistMoviesVisible =>
      _watchlistMovieItems.isNotEmpty &&
      !_homeDisabled.contains('watchlist:movies') &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;
  bool get _watchlistSeriesVisible =>
      _watchlistSeriesItems.isNotEmpty &&
      !_homeDisabled.contains('watchlist:series') &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// The visible saved-content rows in render order: Watchlist Movies,
  /// Watchlist Series, Playlist, Debrify TV, Stremio TV, IPTV favourites, then
  /// opted-in IPTV custom lists.
  /// This is the single source of truth for both rendering ([_buildBoard]) and
  /// the index-based DPAD focus wiring below, so the two never drift out of
  /// sync. IPTV list rows share the favourites gates (board only, non-empty)
  /// and are opt-in by construction — [_iptvListRows] only ever holds enabled
  /// lists.
  // Reach-sweep rule: a feature that's off drops its Home rows too, not
  // just its tab — the profile should never see a shelf it can't open.
  List<_FavRowRef> get _favRowKinds => [
    if (_watchlistMoviesVisible) const _FavRowRef(_FavKind.watchlistMovies),
    if (_watchlistSeriesVisible) const _FavRowRef(_FavKind.watchlistSeries),
    if (_playlistFavVisible) const _FavRowRef(_FavKind.playlist),
    if (_tvFavVisible &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.debrifyTv))
      const _FavRowRef(_FavKind.debrify),
    if (_stvFavVisible &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.stremioTv))
      const _FavRowRef(_FavKind.stremio),
    if (_iptvFavVisible && ProfilePolicyGuard.allowsSync(ProfileFeature.iptv))
      const _FavRowRef(_FavKind.iptv),
    if (_catalogQuery.isEmpty &&
        !_catalogSearching &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.iptv))
      for (var i = 0; i < _iptvListRows.length; i++)
        if (_iptvListRows[i].channels.isNotEmpty) _FavRowRef(_FavKind.iptv, i),
  ];

  int get _favRowCount => _favRowKinds.length;
  bool get _anyFavVisible => _favRowKinds.isNotEmpty;

  String _favRowId(_FavRowRef ref) {
    if (ref.isIptvList) {
      return HomeExtraRowIds.iptvList(_iptvListRows[ref.list].listId);
    }
    return switch (ref.kind) {
      _FavKind.watchlistMovies => 'watchlist:movies',
      _FavKind.watchlistSeries => 'watchlist:series',
      _FavKind.playlist => 'fav:playlist',
      _FavKind.debrify => 'fav:debrify',
      _FavKind.stremio => 'fav:stremio',
      _FavKind.iptv => 'fav:iptv',
    };
  }

  String _sectionRowId(CatalogSection section) => section is HomeListSection
      ? section.rowId
      : section is HomeCollectionSection
      ? section.rowId
      : '${section.addon.id}:${section.catalog.type}:${section.catalog.id}';

  String _catalogRefRowId((StremioAddon, StremioAddonCatalog) ref) =>
      '${ref.$1.id}:${ref.$2.type}:${ref.$2.id}';

  /// The focus-node list backing a favourites row of the given [ref].
  List<FocusNode> _favNodesFor(_FavRowRef ref) {
    if (ref.isIptvList) return _iptvListRows[ref.list].nodes;
    switch (ref.kind) {
      case _FavKind.watchlistMovies:
        return _watchlistMovieNodes;
      case _FavKind.watchlistSeries:
        return _watchlistSeriesNodes;
      case _FavKind.iptv:
        return _iptvFavNodes;
      case _FavKind.debrify:
        return _tvFavNodes;
      case _FavKind.stremio:
        return _stvFavNodes;
      case _FavKind.playlist:
        return _playlistFavNodes;
    }
  }

  /// Focus a card in the favourites row at [favIndex] (index into the visible
  /// favourites rows), clamping the column to that row's length. Returns false
  /// when no such row is focusable (same contract as [_focusCwRow]).
  bool _focusFavRowAt(int favIndex, int column) {
    final kinds = _favRowKinds;
    if (favIndex < 0 || favIndex >= kinds.length) return false;
    final nodes = _favNodesFor(kinds[favIndex]);
    if (nodes.isEmpty) return false;
    _requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  // A DPAD-down pressed while everything below was still loading (Trakt row a
  // focusless skeleton, favourites absent, first catalog batch in flight) used
  // to be swallowed with focus frozen in place — the cell handler had already
  // reported the key handled. Instead the press is remembered briefly and
  // completed the moment a row below lands. Origin node is compared by
  // IDENTITY only (never dereferenced — it may be disposed by then): if focus
  // moved elsewhere meanwhile, the deferred move is dropped, so a late load
  // can never yank focus away from the user.
  FocusNode? _pendingDownOrigin;
  int _pendingDownRowIndex = -1; // set when pressed on a catalog row
  String? _pendingDownHomeRowId; // stable id on the globally ordered Home
  int _pendingDownCol = 0;
  DateTime? _pendingDownAt;
  static const Duration _pendingDownMaxAge = Duration(seconds: 3);

  void _deferDownMove({
    int rowIndex = -1,
    String? homeRowId,
    required int column,
  }) {
    if (!_boardHasMore && !_boardLoadingMore && _focusCatalogContinuation()) return;
    _pendingDownOrigin = FocusManager.instance.primaryFocus;
    if (_pendingDownOrigin == null) return;
    _pendingDownRowIndex = rowIndex;
    _pendingDownHomeRowId = homeRowId;
    _pendingDownCol = column;
    _pendingDownAt = DateTime.now();
  }

  void _clearDeferredDown() {
    _pendingDownOrigin = null;
    _pendingDownAt = null;
    _pendingDownHomeRowId = null;
  }

  /// Complete a recent deferred DPAD-down, called whenever a row load settles.
  /// Post-frame: the freshly-loaded row's cells only mount on the next build,
  /// and [_requestRowFocus] needs mounted cells.
  void _maybeCompleteDeferredDown() {
    if (_pendingDownAt == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final at = _pendingDownAt;
      final origin = _pendingDownOrigin;
      if (at == null || origin == null) return;
      if (DateTime.now().difference(at) > _pendingDownMaxAge) {
        _clearDeferredDown();
        return;
      }
      if (!identical(FocusManager.instance.primaryFocus, origin)) {
        _clearDeferredDown();
        return;
      }
      final col = _pendingDownCol;
      final bool moved;
      final homeRowId = _pendingDownHomeRowId;
      if (homeRowId != null) {
        final rails = _canvasRails;
        final current = rails.indexWhere(
          (rail) => _canvasRailRowId(rail) == homeRowId,
        );
        moved = current >= 0 && _focusHomeRailAt(current + 1, col);
      } else if (_pendingDownRowIndex >= 0) {
        moved = _focusRow(_pendingDownRowIndex + 1, col);
      } else {
        // From the last favourites row.
        moved = _focusRow(0, col);
      }
      if (moved) _clearDeferredDown();
    });
  }

  VoidCallback _favRowOnUp(String rowId, int column) =>
      () => _focusRelativeHomeRail(rowId, -1, column);

  VoidCallback _favRowOnDown(String rowId, int column) =>
      () => _focusRelativeHomeRail(rowId, 1, column);

  final _pendingHomeRows = <HomeRowRefresh>{};
  Timer? _homeRefreshTimer;
  bool _homeAddonsPending = false;
  int _tvFavoritesRevision = 0;
  int _stremioFavoritesRevision = 0;
  int _watchlistRevision = 0;
  int _playlistRevision = 0;

  void _onHomeAddonsChanged() {
    _homeAddonsPending = true;
    _queueHomeRows({HomeRowRefresh.stremioTvFavorites});
  }

  void _queueHomeRows(Set<HomeRowRefresh> rows) {
    if (!mounted) return;
    _pendingHomeRows.addAll(rows.where((row) =>
        row != HomeRowRefresh.playback ||
        !(ModalRoute.of(context)?.isCurrent ?? false)));
    // Visible Home already receives the existing playback-data bridge.

    _homeRefreshTimer ??= Timer(const Duration(milliseconds: 100), () {
      _homeRefreshTimer = null;
      if (!mounted) return;
      final pending = Set<HomeRowRefresh>.of(_pendingHomeRows);
      _pendingHomeRows.clear();
      for (final row in pending) {
        switch (row) {
          case HomeRowRefresh.tvFavorites:
            unawaited(_loadTvFavorites());
          case HomeRowRefresh.stremioTvFavorites:
            unawaited(_loadStremioTvFavorites());
          case HomeRowRefresh.playlist:
            unawaited(_loadPlaylistFavorites());
          case HomeRowRefresh.watchlist:
            unawaited(_loadMyWatchlist());
          case HomeRowRefresh.playback:
            // Do not consume the local playback/tracker refresh latch here.
            unawaited(_loadContinueWatching());
            unawaited(_loadIptvContinueWatching());
        }
      }
      if (_homeAddonsPending) {
        _homeAddonsPending = false;
        if (_catalogQuery.isNotEmpty || _catalogSearching) {
          _pendingBoardReload = true;
        } else {
          unawaited(_load(preserveVisibleRows: true));
        }
      }
    });
  }

  /// Reload starred channels without replacing newer row data.
  Future<void> _loadTvFavorites() async {
    final revision = ++_tvFavoritesRevision;
    try {
      final ids = await StorageService.getDebrifyTvFavoriteChannelIds();
      if (ids.isEmpty) {
        if (!mounted || revision != _tvFavoritesRevision) return;
        setState(() => _tvFavChannels = const []);
        _syncTvFavNodes();
        return;
      }
      final records = await DebrifyTvRepository.instance.fetchAllChannels();
      // fetchAllChannels() is already ordered by channel number; preserve that
      // order (matching the Home row) rather than a redundant, non-stable
      // re-sort that could shuffle channels sharing channelNumber 0.
      final favs = records
          .map(DebrifyTvChannel.fromRecord)
          .where((c) => ids.contains(c.id))
          .toList();
      if (!mounted || revision != _tvFavoritesRevision) return;
      setState(() => _tvFavChannels = favs);
      _syncTvFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  /// Grow/shrink the favourites row's focus nodes to match the channel count.
  void _syncTvFavNodes() {
    while (_tvFavNodes.length < _tvFavChannels.length) {
      _tvFavNodes.add(
        FocusNode(debugLabel: 'search_tvfav_${_tvFavNodes.length}'),
      );
    }
    while (_tvFavNodes.length > _tvFavChannels.length) {
      _tvFavNodes.removeLast().dispose();
    }
  }

  /// Launch a Debrify TV channel (same path the Home screen uses): hand off to
  /// the live player if it's mounted, else queue an auto-play and switch tabs.
  void _playChannel(DebrifyTvChannel channel) {
    if (MainPageBridge.watchDebrifyTvChannel != null) {
      MainPageBridge.watchDebrifyTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(MainTab.debrifyTv);
  }

  /// Load the user's starred Stremio TV channels for the leading favourites row.
  /// Mirrors the Home section: discover all channels, keep the favourited ones
  /// (preserving discovery order), then fetch their items so each card can show
  /// a now-playing poster. Silently leaves the row empty on any error.
  Future<void> _loadStremioTvFavorites() async {
    final revision = ++_stremioFavoritesRevision;
    try {
      final ids = await StorageService.getStremioTvFavoriteChannelIds();
      if (ids.isEmpty) {
        if (!mounted || revision != _stremioFavoritesRevision) return;
        setState(() => _stvFavChannels = const []);
        _syncStvFavNodes();
        return;
      }
      final rotations = await Future.wait([
        StorageService.getStremioTvRotationMinutes(),
        StorageService.getStremioTvSeriesRotationMinutes(),
      ]);
      final rotation = rotations[0];
      final seriesRotation = rotations[1];
      final all = await StremioTvService.instance.discoverChannels();
      final favs = all.where((c) => ids.contains(c.id)).toList();
      await StremioTvService.instance.loadAllChannelItems(favs);
      if (!mounted || revision != _stremioFavoritesRevision) return;
      setState(() {
        _stvRotationMinutes = rotation;
        _stvSeriesRotationMinutes = seriesRotation;
        _stvFavChannels = favs;
      });
      _syncStvFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  void _syncStvFavNodes() {
    while (_stvFavNodes.length < _stvFavChannels.length) {
      _stvFavNodes.add(
        FocusNode(debugLabel: 'search_stvfav_${_stvFavNodes.length}'),
      );
    }
    while (_stvFavNodes.length > _stvFavChannels.length) {
      _stvFavNodes.removeLast().dispose();
    }
  }

  /// First of [a], [b] that is a non-empty string, else null.
  String? _firstNonEmpty(String? a, String? b) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  /// The now-playing item for a Stremio TV channel, using the same time-based
  /// rotation as the Home / Stremio TV screens (series rotate on their own
  /// cadence). Null when the channel has no loaded items.
  StremioTvNowPlaying? _stvNowPlaying(StremioTvChannel channel) {
    return StremioTvService.instance.getNowPlaying(
      channel,
      rotationMinutes: channel.type == 'series'
          ? _stvSeriesRotationMinutes
          : _stvRotationMinutes,
    );
  }

  /// Open a Stremio TV channel (same path the Home screen uses): hand off to the
  /// live player if it's mounted, else queue an auto-play and switch tabs.
  void _playStremioTvChannel(StremioTvChannel channel) {
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(MainTab.stremioTv);
  }

  /// Load the user's starred IPTV channels for the leading favourites row.
  /// Favourites are stored as a url → {name, logoUrl, group} map, so rebuild
  /// [IptvChannel] objects from it in the store's user-defined order.
  Future<void> _loadIptvFavorites() async {
    try {
      final map = await StorageService.getIptvFavoriteChannels();
      if (map.isEmpty) {
        if (!mounted) return;
        setState(() => _iptvFavChannels = const []);
        _syncIptvFavNodes();
        return;
      }
      final favs = map.entries.map((e) {
        final meta = e.value;
        return IptvChannel(
          name: meta['name'] as String? ?? 'Unknown Channel',
          url: e.key,
          logoUrl: meta['logoUrl'] as String?,
          group: meta['group'] as String?,
          duration: -1, // live stream
          attributes: const {},
          httpHeaders: StorageService.iptvFavoriteHeaders(meta),
        );
      }).toList();
      if (!mounted) return;
      setState(() => _iptvFavChannels = favs);
      _syncIptvFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Favourites row just stays hidden.
    }
  }

  void _syncIptvFavNodes() {
    while (_iptvFavNodes.length < _iptvFavChannels.length) {
      _iptvFavNodes.add(
        FocusNode(debugLabel: 'search_iptvfav_${_iptvFavNodes.length}'),
      );
    }
    while (_iptvFavNodes.length > _iptvFavChannels.length) {
      _iptvFavNodes.removeLast().dispose();
    }
  }

  /// Rebuild the opted-in IPTV custom-list rows from the store.
  ///
  /// Channels are rebuilt from the stored list metadata alone (no provider
  /// fetch), keeping ALL presentation fields — content type and duration
  /// drive play routing and the live-preview gate, so the favourites row's
  /// lossy live-only mapping must not be copied here. Order is the list's
  /// explicit saved channel position.
  ///
  /// Token-guarded: the list picker queues several immediate mutations, each
  /// bumping [IptvMediaStore.listsRevision] — an older multi-list read must
  /// not commit after a newer one (stale channels, node reconciliation
  /// against the wrong rows). Only the newest load applies state.
  ///
  /// Nodes reconcile by list id: surviving rows keep their FocusNodes (grown/
  /// shrunk to the channel count), removed rows' nodes are disposed — if one
  /// held DPAD focus, the board's global dead-focus reclaim re-anchors it.
  Future<void> _loadIptvListRows() async {
    final token = ++_iptvListRowsLoadToken;
    try {
      // Read the extras store directly rather than [_homeExtras]: on a cold
      // start this runs CONCURRENTLY with _load() (which populates that
      // field), and losing the race would blank the list rows until the next
      // trigger.
      final extras = await StorageService.getHomeExtraRows();
      if (token != _iptvListRowsLoadToken || !mounted) return;
      final wanted = <String>{
        for (final r in extras)
          if (HomeExtraRowIds.iptvListId(r.id) != null)
            HomeExtraRowIds.iptvListId(r.id)!,
      }..remove(StorageService.iptvFavoritesListId);
      List<_IptvListRow> next = const [];
      if (wanted.isNotEmpty) {
        final metas = await StorageService.getIptvLists();
        final rows = <_IptvListRow>[];
        final prevById = {for (final r in _iptvListRows) r.listId: r};
        for (final meta in metas) {
          if (!wanted.contains(meta.id) || meta.isFavorites) continue;
          final map = await StorageService.getIptvListChannels(meta.id);
          if (token != _iptvListRowsLoadToken || !mounted) return;
          final channels = <IptvChannel>[];
          map.forEach((url, m) {
            final name = (m['name'] as String?) ?? '';
            final logo = (m['logoUrl'] as String?) ?? '';
            final group = (m['group'] as String?) ?? '';
            channels.add(
              IptvChannel(
                name: name.isEmpty ? 'Unknown Channel' : name,
                url: url,
                logoUrl: logo.isEmpty ? null : logo,
                group: group.isEmpty ? null : group,
                channelNumber: (m['channelNumber'] as num?)?.toInt(),
                duration: (m['duration'] as num?)?.toInt() ?? -1,
                contentType: m['contentType'] as String?,
                attributes: {
                  if ((m['playlistId'] as String?)?.isNotEmpty ?? false)
                    'list_playlist_id': m['playlistId'] as String,
                },
                httpHeaders: StorageService.iptvFavoriteHeaders(m),
              ),
            );
          });
          if (channels.isEmpty) continue;
          final row = prevById.remove(meta.id) ?? _IptvListRow(meta.id, '');
          row
            ..title = meta.name
            ..channels = channels;
          while (row.nodes.length < channels.length) {
            row.nodes.add(
              FocusNode(
                debugLabel: 'search_iptvlist_${meta.id}_${row.nodes.length}',
              ),
            );
          }
          while (row.nodes.length > channels.length) {
            row.nodes.removeLast().dispose();
          }
          rows.add(row);
        }
        // Rows that fell out (list deleted/emptied/de-selected): dispose their
        // nodes. The TV board's global focus watcher reclaims focus if one of
        // them held it.
        for (final gone in prevById.values) {
          for (final n in gone.nodes) {
            n.dispose();
          }
          gone.nodes.clear();
        }
        next = rows;
      } else if (_iptvListRows.isEmpty) {
        return; // nothing enabled, nothing shown — no state churn
      } else {
        for (final gone in _iptvListRows) {
          for (final n in gone.nodes) {
            n.dispose();
          }
          gone.nodes.clear();
        }
      }
      if (!mounted || token != _iptvListRowsLoadToken) return;
      setState(() => _iptvListRows = next);
      _maybeAutoFocusBoard();
    } catch (_) {
      // List rows just stay as they were (same policy as the favourites row).
    }
  }

  /// [IptvMediaStore.listsRevision] bumped — some list mutated somewhere in
  /// the app (picker, IPTV settings, provider deletion, reconcile, import).
  void _onIptvListsRevision() {
    if (!mounted) return;
    unawaited(_loadIptvFavorites());
    unawaited(_loadIptvListRows());
  }

  /// Play an IPTV custom-list entry by CONTENT TYPE — a list can hold VOD and
  /// collapsed series alongside live channels, and each routes differently
  /// (mirroring [IptvCwRouter]): live → the favourites-row live launch; VOD →
  /// watch-record + direct launch (the player restores resume by URL); an
  /// `xtream-series://` sentinel → the merged Xtream series page.
  Future<void> _playIptvListChannel(IptvChannel channel) async {
    if (channel.url.startsWith('xtream-series://')) {
      return _openIptvListSeries(channel);
    }
    if (!channel.isLive) {
      // Remember on-demand plays so the IPTV Continue Watching shelf can
      // rebuild the row later — recorded BEFORE the launch (the player
      // process can be killed outright on TV), same as the IPTV page.
      await StorageService.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: channel.attributes['list_playlist_id'],
        httpHeaders: channel.httpHeaders.isEmpty ? null : channel.httpHeaders,
      );
      if (!mounted) return;
    }
    await _playIptvChannel(channel);
  }

  /// A collapsed series sentinel stored in a list: resolve its Xtream origin
  /// and open the merged series page (the episode list / Resume plays from
  /// there) — the sentinel URL itself is not a stream.
  Future<List<IptvPlaylist>?> _readIptvPlaylistsForAction() async {
    try {
      return await StorageService.getIptvPlaylists(forSettings: false);
    } on ResourceAuthorizationException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('IPTV is unavailable. Please retry or sign in.'),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _openIptvListSeries(IptvChannel channel) async {
    // xtream-series://<originId>/<seriesId>
    final rest = channel.url.substring('xtream-series://'.length);
    final slash = rest.indexOf('/');
    final originId = slash < 0
        ? (channel.attributes['list_playlist_id'] ?? '')
        : rest.substring(0, slash);
    final seriesId = slash < 0 ? rest : rest.substring(slash + 1);
    if (seriesId.isEmpty) return;
    final playlists = await _readIptvPlaylistsForAction();
    if (!mounted || playlists == null) return;
    IptvPlaylist? origin;
    for (final p in playlists) {
      if (p.id == originId && p.isXtreamCodes) {
        origin = p;
        break;
      }
    }
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This series' provider is no longer available"),
        ),
      );
      return;
    }
    await openXtreamSeries(
      context,
      playlist: origin,
      series: IptvChannel(
        name: channel.name,
        url: channel.url,
        logoUrl: channel.logoUrl,
        group: channel.group ?? channel.name,
        contentType: 'series',
        attributes: {
          'series_id': seriesId,
          if (originId.isNotEmpty) 'series_playlist_id': originId,
        },
      ),
      isTelevision: widget.isTelevision,
    );
  }

  /// Play an IPTV favourite. Unlike the TV channels there's no bridge/tab
  /// handoff — the stream launches directly in the player (same as Home).
  /// Stremio-addon favourites carry a stremio-tv:// key instead of a stream
  /// URL — resolve it first, and hand the channel through the IPTV path so
  /// both players can walk the remaining candidates if the first one dies.
  /// Latch across the resolve window — repeated OK presses while a Stremio
  /// favourite resolves must not stack player launches.
  bool _iptvFavLaunching = false;

  Future<void> _playIptvChannel(IptvChannel channel) async {
    if (_iptvFavLaunching) return;
    _iptvFavLaunching = true;
    try {
      var videoUrl = channel.url;
      final isStremio = StremioIptvService.isStremioChannelUrl(channel.url);
      if (isStremio) {
        // Explicit play intent: bypass a cached-empty resolve and explain an
        // empty answer specifically (addon unreachable vs. no streams).
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
        videoUrl = candidates.first.url;
      }
      VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: videoUrl,
          title: channel.name,
          subtitle: channel.group ?? 'IPTV',
          viewMode: PlaylistViewMode.sorted,
          // Identify the launch as IPTV for plain channels too (only the
          // Stremio branch used to): it routes playback down the live path
          // and lets the player report a dead stream instead of sitting on a
          // black screen.
          iptvChannels: [channel],
          iptvStartIndex: 0,
          // Playlist-declared headers (+ browser UA fallback) for the launch
          // channel; Stremio-addon links keep the addon's own defaults.
          httpHeaders: isStremio ? null : channel.playbackHeaders,
        ),
      );
    } finally {
      _iptvFavLaunching = false;
    }
  }

  Future<void> _loadMyWatchlist() async {
    final revision = ++_watchlistRevision;
    try {
      final items = await StorageService.getMyWatchlistItems();
      if (!mounted || revision != _watchlistRevision) return;
      setState(() {
        _watchlistMovieItems = [
          for (final item in items)
            if (item.type.toLowerCase() != 'series') item,
        ];
        _watchlistSeriesItems = [
          for (final item in items)
            if (item.type.toLowerCase() == 'series') item,
        ];
      });
      _syncMyWatchlistNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // A local shelf failure is non-fatal; leave it hidden.
    }
  }

  void _syncMyWatchlistNodes() {
    _syncWatchlistNodes(
      nodes: _watchlistMovieNodes,
      itemCount: _watchlistMovieItems.length,
      debugLabel: 'search_watchlist_movie',
    );
    _syncWatchlistNodes(
      nodes: _watchlistSeriesNodes,
      itemCount: _watchlistSeriesItems.length,
      debugLabel: 'search_watchlist_series',
    );
  }

  void _syncWatchlistNodes({
    required List<FocusNode> nodes,
    required int itemCount,
    required String debugLabel,
  }) {
    while (nodes.length < itemCount) {
      nodes.add(FocusNode(debugLabel: '${debugLabel}_${nodes.length}'));
    }
    var removedFocusedNode = false;
    while (nodes.length > itemCount) {
      final removed = nodes.removeLast();
      removedFocusedNode = removedFocusedNode || removed.hasFocus;
      removed.dispose();
    }
    if (removedFocusedNode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (nodes.isNotEmpty) {
          nodes.last.requestFocus();
        } else {
          _focusContent();
        }
      });
    }
  }

  Future<void> _offerRemoveUnavailableWatchlistItem(
    StremioMeta item, {
    required String message,
  }) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Series unavailable'),
        content: Text('$message\n\nRemove it from My Watchlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    try {
      await StorageService.setMyWatchlistItem(item, false);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _loadMyWatchlist();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Removed from My Watchlist')),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update My Watchlist")),
      );
    }
  }

  Future<void> _openMyWatchlistItem(StremioMeta item) async {
    final xtream = parseXtreamSeriesMetaId(item.id);
    if (xtream != null || item.sourceAddon?.id == 'xtream-iptv') {
      if (xtream == null) {
        await _offerRemoveUnavailableWatchlistItem(
          item,
          message: "This series' saved source is invalid.",
        );
        return;
      }

      final playlists = await _readIptvPlaylistsForAction();
      if (!mounted || playlists == null) return;
      IptvPlaylist? playlist;
      for (final candidate in playlists) {
        if (candidate.id == xtream.playlistId && candidate.isXtreamCodes) {
          playlist = candidate;
          break;
        }
      }
      if (playlist == null) {
        await _offerRemoveUnavailableWatchlistItem(
          item,
          message: "This series' provider is no longer available.",
        );
        return;
      }

      await openXtreamSeries(
        context,
        playlist: playlist,
        series: IptvChannel(
          name: item.name,
          url: 'xtream-series://${xtream.seriesId}',
          logoUrl: item.poster,
          group: item.name,
          contentType: 'series',
          attributes: {
            'series_id': xtream.seriesId,
            'series_playlist_id': xtream.playlistId,
            if (item.background?.isNotEmpty ?? false)
              'backdrop': item.background!,
            if (item.description?.isNotEmpty ?? false)
              'plot': item.description!,
            if (item.year?.isNotEmpty ?? false) 'releaseDate': item.year!,
            if (item.imdbRating != null) 'rating': item.imdbRating!.toString(),
            if (item.genres?.isNotEmpty ?? false)
              'genre': item.genres!.join(', '),
          },
        ),
        isTelevision: widget.isTelevision,
      );
      if (mounted) await _refreshAfterPlayback();
      return;
    }

    _openItem(item, _addonForContinue(item.sourceAddon?.id));
  }

  /// Load the user's saved playlist items for the leading Playlist row. Applies
  /// poster overrides and resume progress (same as the Home playlist section),
  /// newest first. Silently leaves the row empty on any error.
  Future<void> _loadPlaylistFavorites() async {
    final revision = ++_playlistRevision;
    try {
      final results = await Future.wait([
        StorageService.getPlaylistItemsRaw(),
        StorageService.getPlaylistFavoriteKeys(),
        StorageService.getAllPlaylistPosterOverrides(),
      ]);
      final items = results[0] as List<Map<String, dynamic>>;
      final favKeys = results[1] as Set<String>;
      final overrides = results[2] as Map<String, String>;

      // Newest first (by addedAt), matching the Home playlist section.
      items.sort((a, b) {
        final at = a['addedAt'] as int? ?? 0;
        final bt = b['addedAt'] as int? ?? 0;
        return bt.compareTo(at);
      });
      // Apply any per-item poster override in a single pass.
      for (final item in items) {
        final key = StorageService.getPlaylistItemUniqueKey(item);
        final ov = overrides[key];
        if (ov != null && ov.isNotEmpty) item['posterUrl'] = ov;
      }

      final progress = await StorageService.buildPlaylistProgressMap(items);
      if (!mounted || revision != _playlistRevision) return;
      setState(() {
        _playlistItems = items;
        _playlistProgress = progress;
        _playlistFavKeys = favKeys;
      });
      _syncPlaylistFavNodes();
      _maybeAutoFocusBoard();
    } catch (_) {
      // Row just stays hidden.
    }
  }

  void _syncPlaylistFavNodes() {
    while (_playlistFavNodes.length < _playlistItems.length) {
      _playlistFavNodes.add(
        FocusNode(debugLabel: 'search_playlistfav_${_playlistFavNodes.length}'),
      );
    }
    while (_playlistFavNodes.length > _playlistItems.length) {
      final removed = _playlistFavNodes.removeLast();
      // Unlike the other fav rows, this one deletes items in-row — so the card
      // being trimmed can be the one that currently holds DPAD focus (delete the
      // focused last card). Disposing a focused node strands focus on a disposed
      // object; hand it to the new last card first (or let it fall out cleanly
      // when the row is now empty).
      final hadFocus = removed.hasFocus;
      removed.dispose();
      if (hadFocus && _playlistFavNodes.isNotEmpty) {
        _playlistFavNodes.last.requestFocus();
      }
    }
  }

  /// Resume fraction (0..1) for a playlist item, or null if it has no progress.
  /// [StorageService.buildPlaylistProgressMap] emits `positionMs`/`durationMs`
  /// (the Home section reads `position`/`duration`, which are never present — so
  /// its bar silently never draws; read the real keys here so ours works).
  double? _playlistProgressFor(Map<String, dynamic> item) {
    final key = StorageService.computePlaylistDedupeKey(item);
    final p = _playlistProgress[key];
    if (p == null) return null;
    final position = (p['positionMs'] as num?)?.toInt();
    final duration = (p['durationMs'] as num?)?.toInt();
    if (position == null || duration == null || duration <= 0) return null;
    return (position / duration).clamp(0.0, 1.0);
  }

  /// The full action menu for a playlist item — the same set of actions as the
  /// Home playlist section (Home is being phased out, so this row is a complete
  /// playlist manager on its own). Rendered with the post-torrent Neon action
  /// sheet: bottom sheet on phones, centered card on desktop/TV, with the
  /// first three actions as primary pills.
  Future<void> _onPlaylistItemTap(Map<String, dynamic> item) async {
    if (!mounted) return;
    final dedupeKey = StorageService.computePlaylistDedupeKey(item);
    final isFavorited = _playlistFavKeys.contains(dedupeKey);
    final hasProgress = _playlistProgress.containsKey(dedupeKey);
    final isCollection = (item['kind'] as String?) != 'single';
    final title = (item['title'] as String?) ?? 'Unknown';

    // The sheet pops itself before running an action, so route every choice
    // through the handler instead of awaiting a dialog result.
    void run(String choice) =>
        unawaited(_handlePlaylistMenuChoice(choice, item, isFavorited));

    final app = AppThemeScope.of(context);
    await showDebridActionSheet(
      context,
      providerLabel: 'Playlist',
      torrentName: title,
      gradient: [app.seeAll.accent, app.seeAll.accent2],
      providerIcon: Icons.playlist_play_rounded,
      subtitle: isCollection
          ? 'Saved collection. Choose your next step.'
          : 'Saved item. Choose your next step.',
      actions: [
        DebridActionItem(
          icon: Icons.play_circle_fill_rounded,
          color: const Color(0xFF10B981),
          title: 'Play',
          subtitle: 'Start playback',
          onTap: () => run('play'),
        ),
        if (isCollection)
          DebridActionItem(
            icon: Icons.shuffle_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Play Random',
            subtitle: 'Start a random file from this collection',
            pillLabel: 'Random',
            onTap: () => run('play_random'),
          ),
        DebridActionItem(
          icon: Icons.folder_open_rounded,
          color: const Color(0xFF818CF8),
          title: 'View Files',
          subtitle: 'Browse folder contents',
          pillLabel: 'Files',
          onTap: () => run('view_files'),
        ),
        DebridActionItem(
          icon: isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
          color: const Color(0xFFFFD700),
          title: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
          subtitle: isFavorited
              ? 'Remove from your favorites list'
              : 'Add to your favorites list',
          pillLabel: 'Favorite',
          onTap: () => run('favorite'),
        ),
        if (hasProgress)
          DebridActionItem(
            icon: Icons.replay_rounded,
            color: const Color(0xFF60A5FA),
            title: 'Clear Progress',
            subtitle: 'Reset playback progress',
            onTap: () => run('clear_progress'),
          ),
        DebridActionItem(
          icon: Icons.delete_outline_rounded,
          color: app.home.danger,
          title: 'Delete',
          subtitle: 'Remove from playlist',
          onTap: () => run('delete'),
        ),
      ],
    );
  }

  Future<void> _handlePlaylistMenuChoice(
    String choice,
    Map<String, dynamic> item,
    bool isFavorited,
  ) async {
    if (!mounted) return;
    switch (choice) {
      case 'play':
        _playPlaylistItem(item);
        break;
      case 'play_random':
        _playPlaylistItem(item, playRandom: true);
        break;
      case 'view_files':
        await Navigator.of(context).push(
          // Both doors are themed now (Search always was, Playlist since
          // phase two), so this screen resolves the same palette either way —
          // which is what the freeze was here to guarantee while they
          // disagreed.
          MaterialPageRoute(
            builder: (_) => PlaylistContentViewScreen(playlistItem: item),
          ),
        );
        // Progress / poster may have changed while browsing.
        _loadPlaylistFavorites();
        break;
      case 'favorite':
        await StorageService.setPlaylistItemFavorited(item, !isFavorited);
        HapticFeedback.mediumImpact();
        _loadPlaylistFavorites();
        break;
      case 'clear_progress':
        // Empty (not 'Unknown') fallback so a null-titled item clears nothing
        // instead of fuzzy-matching the literal word 'unknown' and wiping an
        // unrelated item's resume point — matches the Home section.
        await StorageService.clearPlaylistProgress(
          title: (item['title'] as String?) ?? '',
        );
        HapticFeedback.mediumImpact();
        _loadPlaylistFavorites();
        break;
      case 'delete':
        await _confirmDeletePlaylistItem(item);
        break;
    }
  }

  Future<void> _playPlaylistItem(
    Map<String, dynamic> item, {
    bool playRandom = false,
  }) async {
    if (_playlistLaunching) return;
    _playlistLaunching = true;
    try {
      await PlaylistPlayerService.play(context, item, playRandom: playRandom);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play: $e')));
    } finally {
      if (mounted) _playlistLaunching = false;
    }
  }

  Future<void> _confirmDeletePlaylistItem(Map<String, dynamic> item) async {
    final title = (item['title'] as String?) ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Remove "$title" from your playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppThemeScope.of(dialogContext).home.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final dedupeKey = StorageService.computePlaylistDedupeKey(item);
      await StorageService.removePlaylistItemByKey(dedupeKey);
      HapticFeedback.mediumImpact();
      _loadPlaylistFavorites();
    }
  }

  /// Resolve the addon that a Continue Watching title should route through.
  /// Prefers the stored source addon; falls back to any homepage addon, then a
  /// minimal placeholder so Play still works even if the addon is gone.
  StremioAddon _addonForContinue(String? addonId) {
    if (addonId != null && _addonsById.containsKey(addonId)) {
      return _addonsById[addonId]!;
    }
    // "Any homepage addon" means a REAL catalog addon — the Trakt/Simkl list
    // rows that now lead _homeSections carry only a placeholder addon (empty
    // baseUrl), which can't serve /meta or /stream.
    for (final s in _homeSections) {
      if (s is! HomeListSection && s is! HomeCollectionSection) {
        return s.addon;
      }
    }
    return StremioAddon(
      id: addonId ?? 'continue_watching',
      name: 'Continue Watching',
      manifestUrl: '',
      baseUrl: '',
    );
  }

  /// Open a board-section item through the right pipeline for its source.
  /// Trakt list rows keep Trakt semantics (`isTraktSource` — status chips,
  /// Trakt-first resume label), Simkl rows open plainly (Discover's
  /// [_openSimklItem] routing), and real catalog sections route through their
  /// own addon exactly as before.
  void _sectionOpenItem(
    CatalogSection section,
    StremioMeta item, {
    String? heroTag,
  }) {
    // A folder tile opens the folder's merged grid, never a detail page.
    if (section is HomeCollectionSection) {
      _openCollectionFolder(section, item);
      return;
    }
    if (section is HomeListSection) {
      _openItem(
        item,
        _addonForContinue(item.sourceAddon?.id),
        isTraktSource: section.isTrakt,
        isMdblistSource: section.isMdblist,
        heroTag: heroTag,
      );
      return;
    }
    _openItem(item, section.addon, heroTag: heroTag);
  }

  /// Quick-play counterpart to [_sectionOpenItem]. Trakt rows go through
  /// [_playTraktItem] (CW-cached resume, else catalog play with Trakt-first
  /// resume); Simkl rows play plainly like Discover's lists.
  void _sectionQuickPlay(CatalogSection section, StremioMeta item) {
    // A folder tile has nothing to play — open it instead.
    if (section is HomeCollectionSection) {
      _openCollectionFolder(section, item);
      return;
    }
    if (section is HomeListSection) {
      if (section.isTrakt) {
        _playTraktItem(item);
      } else if (section.isMdblist) {
        _onCatalogPlay(
          item,
          _addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        );
      } else {
        _playSimklItem(item);
      }
      return;
    }
    _onCatalogPlay(item, section.addon);
  }

  Future<List<HomeCollection>> _readHomeCollections() async {
    try {
      return await HomeCollectionsStore.instance.getCollections();
    } catch (_) {
      debugPrint('Home: saved collections could not be loaded');
      return const [];
    }
  }

  /// Every enabled imported collection as a board row (hidden rows skipped).
  List<HomeCollectionSection> _buildCollectionSections() => [
    for (final c in _homeCollections)
      if (c.enabled && c.folders.isNotEmpty && !_homeDisabled.contains(c.rowId))
        HomeCollectionSection(collection: c),
  ];

  /// A folder tile on a collection row opens that folder's merged grid.
  void _openCollectionFolder(HomeCollectionSection section, StremioMeta item) {
    final index = section.folderIndexOf(item);
    _openCollectionScreen(section.collection, index < 0 ? 0 : index);
  }

  /// Push the folder browser on [folderIndex]. Items open through [_openItem]
  /// with the addon that served them (the catalog fetch stamps
  /// `sourceAddon`), so the detail flow is the catalog rows' own.
  void _openCollectionScreen(HomeCollection collection, int folderIndex) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _withHomeExpandedCardSettings(
              CollectionFolderScreen(
                collection: collection,
                initialFolderIndex: folderIndex,
                isTelevision: widget.isTelevision,
                onOpenItem: (item) =>
                    _openItem(item, item.sourceAddon ?? _addonForContinue(null)),
                onQuickPlay: _pikpakOnly
                    ? null
                    : (item) => _onCatalogPlay(
                        item,
                        item.sourceAddon ?? _addonForContinue(null),
                      ),
              ),
            ),
          ),
        )
        .then((_) => _afterSeeAllReturn());
  }

  /// Open a Continue Watching title as a normal detail page (no Home-style
  /// list menu). The detail's action row + a "Remove from Continue Watching"
  /// action are wired via [_openItem] (which detects membership in [_cwIds]).
  void _openContinueItem(StremioMeta item) {
    _openItem(item, _addonForContinue(_cwAddonId[item.imdbId]));
  }

  /// Long-press quick-play for a Continue Watching title — resumes directly
  /// (series resume the last-played episode) without opening the detail.
  void _onContinuePlay(StremioMeta item) {
    _onCatalogPlay(item, _addonForContinue(_cwAddonId[item.imdbId]));
  }

  /// Open a plain Simkl-list title (Discover's Simkl Trending/watchlist lists) —
  /// a normal catalog detail, no resume. The CW list uses [_openSimklCwItem]
  /// instead, so a title browsed fresh here never opens mid-episode.
  void _openSimklItem(StremioMeta item) {
    _openItem(item, _addonForContinue(item.sourceAddon?.id));
  }

  /// Quick-play a plain Simkl-list title like any other catalog item (no
  /// resume). The CW list uses [_playSimklCwItem].
  void _playSimklItem(StremioMeta item) {
    _onCatalogPlay(item, _addonForContinue(item.sourceAddon?.id));
  }

  // ── Trakt Continue Watching ───────────────────────────────────────────────

  /// Fetch the Trakt "Continue Watching" rows (in-progress movies + up-next
  /// episodes) from the connected account. Uses Trakt's intent-aware Up Next
  /// feed plus paged playback checkpoints. Runs on init / integration change,
  /// post-playback, and a throttled app resume — never on every rebuild.
  /// Token-guarded against overlap; hides the rows when Trakt isn't connected.
  /// [refreshBound] runs a bound-source refresh at the end; pass false when the
  /// caller already refreshes bound sources itself (avoids a double pass).
  Future<void> _loadTraktContinueWatching({bool refreshBound = true}) async {
    _lastTraktCwRefreshAttemptAt = DateTime.now();
    final token = ++_traktCwToken;
    // Mark the fetch in flight so the skeleton slot reserves while it runs (only
    // reserves when there are no real rows yet — see [_traktReserving]). Plain
    // assignment, not setState: the sync prefix runs during initState on cold
    // start, and the first build reads the field anyway.
    _traktCwLoading = true;
    final List<TraktContinueWatchingItem> movies;
    final List<TraktContinueWatchingItem> shows;
    try {
      final authed = await TraktService.instance.isAuthenticated();
      if (!mounted || token != _traktCwToken) return;
      if (!authed) {
        _syncCwNodes(_traktMovieNodes, 0, 'tmovie');
        _syncCwNodes(_traktSeriesNodes, 0, 'tseries');
        setState(() {
          _traktCwLoading = false;
          _traktMovies = [];
          _traktSeries = [];
          _traktAll = [];
          _traktProgress.clear();
          _traktEpisode.clear();
          _traktRemainingMinutes.clear();
          _traktEpisodeArtwork.clear();
          _traktByImdb.clear();
        });
        return;
      }
      final cw = TraktContinueWatchingService.instance;
      final reads = await Future.wait<Object?>([
        cw.fetchMoviesOrNull(),
        cw.fetchShowsOrNull(),
      ]);
      final movieRead = reads[0] as List<TraktContinueWatchingItem>?;
      final showRead = reads[1] as List<TraktContinueWatchingItem>?;
      if (movieRead == null || showRead == null) {
        throw StateError('Trakt Continue Watching read failed');
      }
      movies = movieRead;
      shows = showRead;
    } catch (e) {
      // Leave any existing rows in place on a transient Trakt/network error,
      // but stop reserving the skeleton slot so it doesn't shimmer forever.
      debugPrint('SearchScreen: Trakt continue-watching load failed: $e');
      if (mounted && token == _traktCwToken) {
        setState(() => _traktCwLoading = false);
      }
      return;
    }
    await _ensureCwMergeFlags();
    if (!mounted || token != _traktCwToken) return;

    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final remainingMinutes = <String, int>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byImdb = <String, TraktContinueWatchingItem>{};
    void ingest(List<TraktContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = it.id;
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = _seLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
        if (it.season != null &&
            it.episode != null &&
            it.season! > 0 &&
            it.episode! > 0) {
          episodeRefs[id] = (season: it.season!, episode: it.episode!);
        }
        final left = continueWatchingMinutesLeftFromProgress(
          progress: it.progress,
          runtimeMinutes: it.runtime,
        );
        if (left != null) remainingMinutes[id] = left;
      }
    }

    ingest(movies, movieMetas);
    ingest(shows, showMetas);
    // Merge into one last-watched-ordered list for the See-All grid: sort by
    // Trakt's paused_at / last_watched_at (newest first). Items without either
    // sort last. Ties use the original movies-then-shows order so the sort is
    // deterministic (Dart's List.sort isn't stable).
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[a.imdbId]?.pausedAtMs;
      final pb = byImdb[b.imdbId]?.pausedAtMs;
      if (pa != null && pb != null) {
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      } else if (pa == null && pb != null) {
        return 1;
      } else if (pa != null && pb == null) {
        return -1;
      }
      return origIndex[a]!.compareTo(origIndex[b]!);
    });
    // Whether the board already showed Trakt rows before this load — only a
    // fresh appearance (skeleton → content) announces itself below; a refresh
    // of rows the user can already see stays quiet.
    final hadTraktRows = _traktMovies.isNotEmpty || _traktSeries.isNotEmpty;
    _syncCwNodes(
      _traktMovieNodes,
      _cwMergeTrakt ? allMetas.length : movieMetas.length,
      'tmovie',
    );
    _syncCwNodes(
      _traktSeriesNodes,
      _cwMergeTrakt ? 0 : showMetas.length,
      'tseries',
    );
    setState(() {
      _traktCwLoading = false;
      _traktMovies = movieMetas;
      _traktSeries = showMetas;
      _traktAll = allMetas;
      _traktProgress
        ..clear()
        ..addAll(progress);
      _traktEpisode
        ..clear()
        ..addAll(episode);
      _traktRemainingMinutes
        ..clear()
        ..addAll(remainingMinutes);
      _traktEpisodeArtwork.clear();
      _traktByImdb
        ..clear()
        ..addAll(byImdb);
    });
    unawaited(
      _enrichCwEpisodeArtwork(
        refs: episodeRefs,
        target: _traktEpisodeArtwork,
        isCurrent: () => token == _traktCwToken,
      ),
    );
    _maybeAutoFocusBoard();
    if (!hadTraktRows) _maybeAnnounceTraktRows();
    if (refreshBound) unawaited(_refreshBoundSources());
  }

  /// The Trakt rows just landed (skeleton → content), usually seconds after
  /// the rest of the board. Local Continue Watching renders above them; Simkl,
  /// IPTV, favourites and catalog rows below.
  void _maybeAnnounceTraktRows() => _maybeAnnounceCwRows(
    label: 'Trakt',
    // Same merge-aware gates as _cwRows / _cwVisible, so a notice fires
    // exactly when a row actually rendered.
    visible:
        ((_cwMergeTrakt ? _traktAll : _traktMovies).isNotEmpty &&
            !_homeDisabled.contains('trakt:movies')) ||
        (!_cwMergeTrakt &&
            _traktSeries.isNotEmpty &&
            !_homeDisabled.contains('trakt:shows')),
    ownNodes: [_traktMovieNodes, _traktSeriesNodes],
    aboveNodes: [_cwMovieNodes, _cwSeriesNodes],
    belowNodes: [
      _simklMovieNodes,
      _simklSeriesNodes,
      _mdblistMovieNodes,
      _mdblistSeriesNodes,
      _iptvCwMovieNodes,
      _iptvCwSeriesNodes,
    ],
  );

  /// Same for the Simkl rows, which land on their own schedule (and without a
  /// reserved skeleton slot, so they push the board when they arrive). Local
  /// Continue Watching and the Trakt rows render above them, IPTV below.
  void _maybeAnnounceSimklRows() => _maybeAnnounceCwRows(
    label: 'Simkl',
    visible:
        ((_cwMergeSimkl ? _simklAll : _simklMovies).isNotEmpty &&
            !_homeDisabled.contains('simkl:movies')) ||
        (!_cwMergeSimkl &&
            _simklSeries.isNotEmpty &&
            !_homeDisabled.contains('simkl:shows')),
    ownNodes: [_simklMovieNodes, _simklSeriesNodes],
    aboveNodes: [
      _cwMovieNodes,
      _cwSeriesNodes,
      _traktMovieNodes,
      _traktSeriesNodes,
    ],
    belowNodes: [
      _mdblistMovieNodes,
      _mdblistSeriesNodes,
      _iptvCwMovieNodes,
      _iptvCwSeriesNodes,
    ],
  );

  void _maybeAnnounceMdblistRows() => _maybeAnnounceCwRows(
    label: 'MDBList',
    visible:
        ((_cwMergeMdblist ? _mdblistAll : _mdblistMovies).isNotEmpty &&
            !_homeDisabled.contains('mdblist:movies')) ||
        (!_cwMergeMdblist &&
            _mdblistSeries.isNotEmpty &&
            !_homeDisabled.contains('mdblist:shows')),
    ownNodes: [_mdblistMovieNodes, _mdblistSeriesNodes],
    aboveNodes: [
      _cwMovieNodes,
      _cwSeriesNodes,
      _traktMovieNodes,
      _traktSeriesNodes,
      _simklMovieNodes,
      _simklSeriesNodes,
    ],
    belowNodes: [_iptvCwMovieNodes, _iptvCwSeriesNodes],
  );

  /// A tracker's Continue Watching rows just appeared on the board — if the
  /// user is already browsing elsewhere, point them at the new rows with a
  /// small toast, with the direction worked out from where DPAD focus currently
  /// sits. [ownNodes] are the new rows themselves (focus already there → stay
  /// quiet), [aboveNodes] / [belowNodes] the other Continue Watching rows they
  /// slot between; favourites and catalog rows always render below.
  void _maybeAnnounceCwRows({
    required String label,
    required bool visible,
    required List<List<FocusNode>> ownNodes,
    required List<List<FocusNode>> aboveNodes,
    required List<List<FocusNode>> belowNodes,
  }) {
    if (!mounted || !widget.isTelevision) return;
    if (widget.searchMode || widget.discoverMode) return;
    // Still on the brand loading stage: the rows will simply be there when the
    // board first paints — nothing to announce.
    if (_loading) return;
    // Only the board the user is actually looking at announces (not one
    // reloading under a detail page/player or on an inactive tab).
    if (MainPageBridge.activeTvTabIndex != _tabIndex) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    // Rows hidden by the Home Rows manager never reached the screen.
    if (!visible) return;
    final primary = FocusManager.instance.primaryFocus;
    bool onRow(List<FocusNode> nodes) =>
        primary != null && nodes.contains(primary);
    bool onAny(List<List<FocusNode>> rows) => rows.any(onRow);
    if (onAny(ownNodes)) return; // already looking at them
    String? dir;
    if (onAny(aboveNodes)) {
      dir = 'down';
    } else if (onAny(belowNodes)) {
      dir = 'up';
    } else {
      for (final kind in _favRowKinds) {
        if (onRow(_favNodesFor(kind))) {
          dir = 'up';
          break;
        }
      }
      if (dir == null) {
        for (final row in _rowNodes) {
          if (onRow(row)) {
            dir = 'up';
            break;
          }
        }
      }
    }
    final msg = dir == null
        ? '$label Continue Watching loaded'
        : '$label loaded — scroll $dir to view';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ),
    );
  }

  /// Open a Trakt Continue Watching title as a normal detail page.
  void _openTraktItem(StremioMeta item) {
    _openItem(
      item,
      _addonForContinue(item.sourceAddon?.id),
      isTraktSource: true,
    );
  }

  /// Open a detail page requested by another tab (see [initState]). Builds a
  /// minimal Trakt-sourced [StremioMeta] from the handoff map and routes through
  /// the normal [_openItem] path, so every action button behaves exactly as on
  /// the Home board. For a series it scrolls to the requested season/episode,
  /// and it returns to the origin tab when the detail closes.
  Future<void> _openPendingCatalogDetail(Map<String, dynamic> data) async {
    final imdbId = data['imdbId'] as String?;
    if (imdbId == null || imdbId.isEmpty) return;
    // This can run before the board's async flags settle (they're kicked off
    // fire-and-forget in initState). Await the two that shape the detail so we
    // don't open the wrong thing: the merged-page flag (merged vs legacy screen
    // — only the merged one honours initialSeason/Episode, i.e. the scroll) and
    // Trakt auth (status chips + menu). Both are fast local reads, no network.
    await _loadMergedSeriesFlag();
    await _refreshTraktAuthState();
    if (!mounted) return;
    final type = (data['type'] as String?) == 'movie' ? 'movie' : 'series';
    final meta = StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: type,
      name: (data['title'] as String?) ?? '',
      poster: data['poster'] as String?,
      year: (data['year'] as int?)?.toString(),
    );
    _openItem(
      meta,
      _addonForContinue(null),
      isTraktSource: true,
      initialSeason: data['season'] as int?,
      initialEpisode: data['episode'] as int?,
      returnToTabOnClose: data['originTab'] as int?,
    );
  }

  /// Resume a Trakt Continue Watching title — resolves the paused/next episode
  /// (an extra Trakt call for series) and plays.
  Future<void> _playTraktItem(StremioMeta item) async {
    final cwItem = _traktByImdb[_imdbOf(item)];
    if (cwItem == null) {
      // Not in Continue Watching — a fetched Trakt list title (Trending,
      // Watchlist, …). Play it like a catalog title: addon-stream resolution
      // with the same Trakt-first resume the detail page's Play button uses.
      await _onCatalogPlay(
        item,
        _addonForContinue(item.sourceAddon?.id),
        isTraktSource: true,
        preferTraktResume: true,
      );
      return;
    }
    final sel = await TraktContinueWatchingService.instance.selectionForItem(
      cwItem,
    );
    if (!mounted) return;
    if (sel == null) {
      _snack("Couldn't resolve where to resume \"${item.name}\".");
      return;
    }
    _playSelection(sel);
  }

  /// Detail-screen action for a Continue Watching title. Only handles removal;
  /// pops the detail and lets the push's `.then` refresh the row.
  Future<void> _handleContinueDetailAction(
    TraktItemMenuAction action,
    String imdbId,
  ) async {
    if (action != TraktItemMenuAction.removeFromPlayback) return;
    await StorageService.removeContinueWatchingItem(imdbId);
    await StorageService.clearPlaybackStateByImdbId(imdbId);
    if (!mounted) return;
    Navigator.of(context).pop(); // close the detail; `.then` reloads the row
    _snack('Removed from Continue Watching');
  }

  /// Detail-screen action for a Trakt Continue Watching title: delete the
  /// title's playback entries (and watch history, so shows don't reappear via
  /// "Up Next") on Trakt, then pop the detail and reload the Trakt rows —
  /// mirroring the old home screen's remove flow.
  ///
  /// [popDetail] is false when the card's own long-press menu asks for the
  /// removal: there's no detail route open to pop, and popping would take the
  /// board itself off the stack.
  Future<void> _removeFromTraktContinueWatching(
    String imdbId, {
    bool popDetail = true,
  }) async {
    final cwItem = _traktByImdb[imdbId];
    if (cwItem == null) return;
    final removed = await TraktContinueWatchingService.instance.removeItem(
      cwItem,
    );
    if (!mounted) return;
    if (!removed) {
      _snack('Failed to remove from Trakt Continue Watching');
      return;
    }
    if (popDetail) {
      // The Trakt calls take a moment — the user may have already backed out of
      // the detail during the wait, so only pop while it's still the top route.
      Navigator.of(
        context,
      ).popUntil((route) => route.settings.name != kCatalogDetailRouteName);
    }
    _snack('Removed from Trakt Continue Watching');
    await _loadTraktContinueWatching(refreshBound: false);
  }

  // ── Continue Watching card menu (long-press / hold-OK) ────────────────────

  /// Guards against a second menu stacking on the first — on TV the hold-OK
  /// gesture and the tap the platform synthesizes from DPAD Select can both
  /// arrive for one press.
  bool _cwMenuOpen = false;

  /// Long-press (hold-OK on TV) on a Continue Watching card: Play, or take the
  /// title off the row. Each row supplies its own removal (see [_CwRow.onRemove])
  /// because the four sources write to four different places.
  /// When Home's Hold to Quick Play preference is on, the same gesture skips
  /// this menu and invokes the row's Quick Play action directly.
  ///
  /// [cwIndex]/[col] are the card's board coordinates, used to put TV focus back
  /// on a live card once the row rebuilds without the removed one.
  Future<void> _openCwCardMenu(
    _CwRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) async {
    if (_cwMenuOpen) return;
    _cwMenuOpen = true;
    final isSeries = item.type == 'series';
    final playActionAvailable = row.kind == _CwKind.iptv || !_pikpakOnly;
    final removeActionAvailable = row.canRemove?.call(item) ?? true;
    if (!playActionAvailable && !removeActionAvailable) {
      _cwMenuOpen = false;
      return;
    }
    // IPTV series use their primary action to open the series page; that is
    // still useful in the menu, but it is not the immediate playback this
    // preference promises.
    final quickPlayAvailable =
        playActionAvailable && !(row.kind == _CwKind.iptv && isSeries);
    try {
      final holdToQuickPlay = await StorageService.getHomeCwHoldToQuickPlay();
      if (!mounted) return;
      if (holdToQuickPlay && quickPlayAvailable) {
        row.onQuickPlay(item);
        return;
      }
    } catch (_) {
      // A preference read must never take the existing action menu away.
    } finally {
      // The dialog path takes ownership of this guard below. Direct Quick Play
      // and failed preference reads release it here.
      _cwMenuOpen = false;
    }
    if (!mounted) return;
    _cwMenuOpen = true;
    // An IPTV series card routes to its Xtream series page rather than playing
    // outright (see [_openIptvCwItem]) — so name the action for what it does.
    final playLabel = (row.kind == _CwKind.iptv && isSeries)
        ? 'Open series'
        : 'Play';
    final String playDescription;
    final String removeDescription;
    switch (row.kind) {
      case _CwKind.local:
        playDescription = isSeries
            ? 'Jump back into the episode you stopped on.'
            : 'Resume from where you left off.';
        removeDescription =
            'Takes it off this row and clears the position saved on this '
            'device.';
      case _CwKind.trakt:
        playDescription = isSeries
            ? 'Jump back into the episode you stopped on.'
            : 'Resume from where you left off.';
        removeDescription =
            'Deletes this title\'s playback progress (and watch history) on '
            'Trakt, so it leaves the Trakt rows everywhere.';
      case _CwKind.simkl:
        playDescription = isSeries
            ? 'Jump back into the episode you stopped on.'
            : 'Resume from where you left off.';
        removeDescription = isSeries
            ? 'Moves the show to On Hold on Simkl and clears the paused '
                  'position, so it stops resurfacing as up next.'
            : 'Clears this movie\'s paused position on Simkl.';
      case _CwKind.mdblist:
        playDescription = isSeries
            ? 'Jump into the paused or next unwatched episode from MDBList.'
            : 'Resume from the position saved on MDBList.';
        removeDescription =
            'Clears this paused playback position from MDBList.';
      case _CwKind.iptv:
        playDescription = isSeries
            ? 'Open the series and pick up where you left off.'
            : 'Resume from where you left off.';
        removeDescription = isSeries
            ? 'Clears every watched episode of this series from your IPTV '
                  'history.'
            : 'Clears this item from your IPTV watch history and forgets its '
                  'position.';
    }

    final episode = row.episodeOf(item);
    CwCardAction? action;
    try {
      action = await showCwCardMenu(
        context,
        title: item.name,
        isTelevision: widget.isTelevision,
        posterUrl: item.poster,
        subtitle: [row.title, if (episode != null) episode].join('  ·  '),
        // Mirrors the card's own long-press-to-play gate: PikPak-only setups
        // have no quick play, so the menu offers the removal alone.
        showPlay: playActionAvailable,
        showRemove: removeActionAvailable,
        playLabel: playLabel,
        playDescription: playDescription,
        removeDescription: removeDescription,
      );
    } finally {
      _cwMenuOpen = false;
    }
    if (!mounted || action == null) return;
    switch (action) {
      case CwCardAction.play:
        row.onQuickPlay(item);
      case CwCardAction.remove:
        await row.onRemove(item);
        if (!mounted) return;
        _refocusAfterCwRemoval(cwIndex, col);
    }
  }

  /// Put TV focus back on the board after a removal: the card that had it is
  /// gone (and its FocusNode with it, if the row shrank), which would otherwise
  /// leave the remote dead until the global reclaim listener notices.
  void _refocusAfterCwRemoval(int cwIndex, int col) {
    if (!widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Same index first: if this row survived it's still here, and if it
      // emptied out the row below has slid into its place.
      if (_focusCwRow(cwIndex, col)) return;
      for (var i = cwIndex - 1; i >= 0; i--) {
        if (_focusCwRow(i, col)) return;
      }
      // No Continue Watching rows left at all — hand the remote to the shell.
      _leaveBoardTop();
    });
  }

  /// Remove a LOCAL Continue Watching title from the row itself. The same two
  /// writes [_handleContinueDetailAction] makes (list entry + saved position),
  /// without the detail pop — nothing was pushed here.
  Future<void> _removeLocalCwItem(StremioMeta item) async {
    final imdbId = _imdbOf(item) ?? item.id;
    if (imdbId.isEmpty) return;
    await StorageService.removeContinueWatchingItem(imdbId);
    await StorageService.clearPlaybackStateByImdbId(imdbId);
    if (!mounted) return;
    _snack('Removed from Continue Watching');
    await _loadContinueWatching();
  }

  /// Remove a Trakt Continue Watching title from the row itself — the detail
  /// page's flow minus the pop.
  Future<void> _removeTraktCwItem(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    await _removeFromTraktContinueWatching(imdbId, popDetail: false);
  }

  /// Remove a Simkl Continue Watching title from the row itself. Routes through
  /// the shared [handleSimklMenuAction] the detail sheet uses (which shows its
  /// own result snackbar), so a series is moved to On Hold and its paused
  /// session cleared, and a movie just loses the session.
  Future<void> _removeSimklCwItem(StremioMeta item) async {
    await handleSimklMenuAction(
      context,
      item,
      SimklItemMenuAction.removeFromContinueWatching,
    );
    if (!mounted) return;
    await _loadSimklContinueWatching(refreshBound: false);
  }

  /// Remove an IPTV Continue Watching card: a movie drops its own history +
  /// resume entry, a series drops every episode's (the card collapses them, so
  /// leaving one behind would just rebuild it).
  Future<void> _removeIptvCwItem(StremioMeta item) async {
    final entry = _iptvCwByKey[item.id];
    if (entry == null) return;
    if (entry.isSeries) {
      final seriesId = (entry.raw['seriesId'] as String?) ?? '';
      if (seriesId.isEmpty) return;
      await StorageService.removeIptvContinueWatchingSeries(
        playlistId: (entry.raw['playlistId'] as String?) ?? '',
        seriesId: seriesId,
      );
    } else {
      final url = (entry.raw['url'] as String?) ?? entry.routeKey;
      if (url.isEmpty) return;
      await StorageService.removeIptvContinueWatchingItem(url);
    }
    if (!mounted) return;
    _snack('Removed from Continue Watching');
    await _loadIptvContinueWatching();
  }

  // ── Simkl Continue Watching ───────────────────────────────────────────────

  /// Fetch the Simkl "Continue Watching" rows (paused movies + paused episodes)
  /// from the connected account's playback sessions — the same `/sync/playback`
  /// lists the scrobble resume already fetches + caches, so this is cheap. Runs
  /// once on init / integration change and caches in memory. Token-guarded
  /// against overlap; hides the rows when Simkl isn't connected. [refreshBound]
  /// runs a bound-source refresh at the end (skip when the caller already does).
  Future<void> _loadSimklContinueWatching({bool refreshBound = true}) async {
    final token = ++_simklCwToken;
    final result = await SimklContinueWatchingService.instance.fetchItems();
    await _ensureCwMergeFlags();
    if (!mounted || token != _simklCwToken) return;
    // Null = a transient fetch failure — leave any existing rows in place (a
    // real disconnect returns empty lists, which fall through and clear them).
    if (result == null) return;

    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byImdb = <String, SimklContinueWatchingItem>{};
    void ingest(List<SimklContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = it.id;
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        // "Up next" entries have no paused position — no progress bar for them.
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = _seLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
        if (it.season != null &&
            it.episode != null &&
            it.season! > 0 &&
            it.episode! > 0) {
          episodeRefs[id] = (season: it.season!, episode: it.episode!);
        }
      }
    }

    ingest(result.movies, movieMetas);
    ingest(result.shows, showMetas);
    // Merge into one paused-order list for the See-All grid: newest paused_at
    // first, timestamp-less items last, ties fall back to movies-then-shows.
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[a.imdbId]?.pausedAtMs;
      final pb = byImdb[b.imdbId]?.pausedAtMs;
      if (pa != null && pb != null) {
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      } else if (pa == null && pb != null) {
        return 1;
      } else if (pa != null && pb == null) {
        return -1;
      }
      return origIndex[a]!.compareTo(origIndex[b]!);
    });

    // Whether the board already showed Simkl rows before this load — only a
    // fresh appearance announces itself below; a refresh of rows the user can
    // already see stays quiet.
    final hadSimklRows = _simklMovies.isNotEmpty || _simklSeries.isNotEmpty;
    _syncCwNodes(
      _simklMovieNodes,
      _cwMergeSimkl ? allMetas.length : movieMetas.length,
      'smovie',
    );
    _syncCwNodes(
      _simklSeriesNodes,
      _cwMergeSimkl ? 0 : showMetas.length,
      'sseries',
    );
    setState(() {
      _simklMovies = movieMetas;
      _simklSeries = showMetas;
      _simklAll = allMetas;
      _simklProgress
        ..clear()
        ..addAll(progress);
      _simklEpisode
        ..clear()
        ..addAll(episode);
      _simklEpisodeArtwork.clear();
      _simklByImdb
        ..clear()
        ..addAll(byImdb);
    });
    unawaited(
      _enrichCwEpisodeArtwork(
        refs: episodeRefs,
        target: _simklEpisodeArtwork,
        isCurrent: () => token == _simklCwToken,
      ),
    );
    _maybeAutoFocusBoard();
    if (!hadSimklRows) _maybeAnnounceSimklRows();
    if (refreshBound) unawaited(_refreshBoundSources());
  }

  /// Open a Simkl Continue Watching title as a detail page. For a series, scroll
  /// the episodes panel to the paused episode (the same path the Calendar uses);
  /// resume itself is handled by the detail's three-way resume when Simkl is
  /// connected. No `isTraktSource` flag — this is a plain, source-neutral open.
  void _openSimklCwItem(StremioMeta item) {
    final cw = _simklByImdb[_imdbOf(item)];
    _openItem(
      item,
      _addonForContinue(item.sourceAddon?.id),
      initialSeason: (cw != null && !cw.isMovie) ? cw.season : null,
      initialEpisode: (cw != null && !cw.isMovie) ? cw.episode : null,
    );
  }

  /// Resume a Simkl Continue Watching title directly (quick-play): builds a
  /// selection carrying the paused season/episode + Simkl progress percent and
  /// plays it, mirroring the Trakt quick-play.
  Future<void> _playSimklCwItem(StremioMeta item) async {
    final cw = _simklByImdb[_imdbOf(item)];
    if (cw == null) {
      // Not in the CW map (a See-All grid title that fell out of the list) —
      // play it like a plain catalog title; three-way resume still applies.
      await _onCatalogPlay(item, _addonForContinue(item.sourceAddon?.id));
      return;
    }
    _playSelection(SimklContinueWatchingService.instance.selectionForItem(cw));
  }

  /// Desktop "See All" for the Simkl Continue Watching rows — reuses the generic
  /// Continue Watching grid, seeded with the paused-order list + progress.
  void _openSimklCwSeeAll([String initialCategory = 'all']) {
    _pushCwSeeAll(
      title: 'Simkl Continue Watching',
      initialCategory: initialCategory,
      items: _simklAll,
      progressOf: (m) => _cwCardProgress(_CwKind.simkl, m),
      onOpen: _openSimklCwItem,
      onQuickPlay: _pikpakOnly ? null : _playSimklCwItem,
      // One uniform pass instead of an explicit Simkl fetch followed by
      // _afterSeeAllReturn: `trackers: true` because this grid renders Simkl's
      // own list and must refetch whether or not anything was played here, and
      // folding it in stops the two from fetching Simkl twice after a playback.
      onReload: () async {
        await _refreshAfterPlayback(trackers: true);
        return List<StremioMeta>.of(_simklAll);
      },
    );
  }

  Future<void> _loadMdblistContinueWatching({
    bool refreshBound = true,
    bool force = false,
  }) async {
    final token = ++_mdblistCwToken;
    debugPrint(
      '[MDBListDiag] Home CW load start token=$token '
      'refreshBound=$refreshBound force=$force flag=$kMdblistEnabled',
    );
    if (!kMdblistEnabled) {
      if (!mounted) return;
      setState(() {
        _mdblistMovies = [];
        _mdblistSeries = [];
        _mdblistAll = [];
        _mdblistByImdb.clear();
      });
      return;
    }
    await MdblistSyncCoordinator.instance.synchronizeInvalidations();
    if (!mounted || token != _mdblistCwToken) return;
    final result = await MdblistContinueWatchingService.instance.fetch(
      force: force,
    );
    await _ensureCwMergeFlags();
    if (!mounted || token != _mdblistCwToken || !result.isUsable) {
      debugPrint(
        '[MDBListDiag] Home CW load discarded token=$token mounted=$mounted '
        'currentToken=$_mdblistCwToken kind=${result.kind.name}',
      );
      return;
    }
    final snapshot = result.data!;
    final movies = <StremioMeta>[];
    final shows = <StremioMeta>[];
    final progress = <String, double>{};
    final episodes = <String, String>{};
    final byImdb = <String, MdblistContinueWatchingItem>{};
    StremioMeta metaFor(MdblistContinueWatchingItem item) {
      final selection = item.selection;
      return StremioMeta(
        id: selection.imdbId,
        imdbId: selection.imdbId,
        type: selection.isSeries ? 'series' : 'movie',
        name: selection.title,
        poster: selection.posterUrl,
        background:
            'https://images.metahub.space/background/medium/${selection.imdbId}/img',
        year: selection.year,
      );
    }

    void ingest(
      Iterable<MdblistContinueWatchingItem> items,
      List<StremioMeta> target,
    ) {
      for (final item in items) {
        final id = item.selection.imdbId;
        if (byImdb.containsKey(id)) continue;
        target.add(metaFor(item));
        byImdb[id] = item;
        final pct = item.selection.mdblistProgressPercent;
        if (pct != null) progress[id] = (pct / 100).clamp(0, 1);
        final se = _seLabel(item.selection.season, item.selection.episode);
        if (se != null) episodes[id] = se;
      }
    }

    ingest(snapshot.movies, movies);
    ingest(snapshot.shows, shows);
    debugPrint(
      '[MDBListDiag] Home CW ingest token=$token movies=${movies.length} '
      'shows=${shows.length}',
    );
    final all = [...movies, ...shows]
      ..sort((a, b) {
        final aa = byImdb[a.imdbId]?.updatedAt;
        final bb = byImdb[b.imdbId]?.updatedAt;
        return (bb ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aa ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
    final hadRows = _mdblistMovies.isNotEmpty || _mdblistSeries.isNotEmpty;
    _syncCwNodes(
      _mdblistMovieNodes,
      _cwMergeMdblist ? all.length : movies.length,
      'mdbmovie',
    );
    _syncCwNodes(
      _mdblistSeriesNodes,
      _cwMergeMdblist ? 0 : shows.length,
      'mdbseries',
    );
    setState(() {
      _mdblistMovies = movies;
      _mdblistSeries = shows;
      _mdblistAll = all;
      _mdblistProgress
        ..clear()
        ..addAll(progress);
      _mdblistEpisode
        ..clear()
        ..addAll(episodes);
      _mdblistByImdb
        ..clear()
        ..addAll(byImdb);
    });
    if (force) _mdblistCwForcedLoadAt = DateTime.now();
    _maybeAutoFocusBoard();
    if (!hadRows) _maybeAnnounceMdblistRows();
    if (refreshBound) unawaited(_refreshBoundSources());
  }

  void _onMdblistPlaybackRevision() {
    if (widget.searchMode || widget.discoverMode) return;
    MdblistContinueWatchingService.instance.invalidate();
    final token = ++_mdblistRevisionRefreshToken;
    _mdblistRevisionRefreshPending = true;
    unawaited(_refreshMdblistAfterMutation(token));
  }

  Future<void> _refreshMdblistAfterMutation(int token) async {
    try {
      // The stop response can arrive during the final frames of the player pop.
      // Wait until Home is visible, then allow MDBList's watched snapshot a
      // short propagation window before replacing the row with authoritative
      // data.
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!mounted || token != _mdblistRevisionRefreshToken) return;
        if (ModalRoute.of(context)?.isCurrent ?? true) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted || token != _mdblistRevisionRefreshToken) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (!mounted || token != _mdblistRevisionRefreshToken) return;
      await _loadMdblistContinueWatching(refreshBound: false, force: true);
    } finally {
      // Only the newest queued refresh owns the pending flag; a superseded one
      // must not clear it while its successor is still due to run.
      if (token == _mdblistRevisionRefreshToken) {
        _mdblistRevisionRefreshPending = false;
      }
    }
  }

  void _openMdblistCwItem(StremioMeta item) {
    final cw = _mdblistByImdb[_imdbOf(item)];
    _openItem(
      item,
      _addonForContinue(item.sourceAddon?.id),
      initialSeason: cw?.selection.season,
      initialEpisode: cw?.selection.episode,
      isMdblistSource: true,
    );
  }

  Future<void> _playMdblistCwItem(StremioMeta item) async {
    final cw = _mdblistByImdb[_imdbOf(item)];
    if (cw == null) {
      await _onCatalogPlay(
        item,
        _addonForContinue(item.sourceAddon?.id),
        isMdblistSource: true,
      );
      return;
    }
    _playSelection(cw.selection);
  }

  bool _canRemoveMdblistCwItem(StremioMeta item) =>
      _mdblistByImdb[_imdbOf(item)]?.paused == true;

  Future<void> _removeMdblistCwItem(StremioMeta item) async {
    final cw = _mdblistByImdb[_imdbOf(item)];
    if (cw == null || !cw.paused) return;
    final removed = await MdblistContinueWatchingService.instance.clear(cw);
    if (!mounted || !removed) return;
    _snack('Removed from MDBList Continue Watching');
    await _loadMdblistContinueWatching();
  }

  void _openMdblistCwSeeAll([String initialCategory = 'all']) {
    _pushCwSeeAll(
      title: 'MDBList Continue Watching',
      initialCategory: initialCategory,
      items: _mdblistAll,
      progressOf: (m) => _cwCardProgress(_CwKind.mdblist, m),
      onOpen: _openMdblistCwItem,
      onQuickPlay: _pikpakOnly ? null : _playMdblistCwItem,
      onReload: () async {
        await _loadMdblistContinueWatching();
        return List<StremioMeta>.of(_mdblistAll);
      },
    );
  }

  /// Swap the displayed sections (homepage or search results): rebuild the
  /// per-row focus nodes and reset the hero to the first item.
  void _applySections(List<CatalogSection> sections, {bool preserveFocus = false}) {
    _boardGen++;
    _boardAppliedAt = DateTime.now();
    // Rail keys are content-addressed by stable Home-row id, so a reload can
    // preserve the active rail even when its numeric section index changes.
    _pendingStageAdvanceKey = null;
    _pendingStageAdvanceAt = null;
    _stageGeneration++;
    if (preserveFocus) {
      List<List<String>> identities(List<CatalogSection> rows) => [
        for (final row in rows) [
          for (final item in row.items)
            jsonEncode([_sectionRowId(row), item.type, item.id]),
        ],
      ];
      final nextNodes = reconcileHomeRowFocus(
        previousIds: identities(_sections),
        previousNodes: _rowNodes,
        nextIds: identities(sections),
      );
      _rowNodes..clear()..addAll(nextNodes);
      _rowCol.clear();
    } else {
      _disposeNodes();
      for (final section in sections) {
        _rowNodes.add(
          List.generate(
            section.items.length,
            (i) => FocusNode(debugLabel: 'search_r${_rowNodes.length}_c$i'),
          ),
        );
      }
    }
    setState(() => _sections = sections);
    _publishTopShelfSpotlight();
    unawaited(_refreshBoundSources());
    if (preserveFocus && _heroItem.value != null && sections.any((section) =>
        section.items.any((item) => item.id == _heroItem.value!.id &&
            item.type == _heroItem.value!.type))) {
      return;
    }
    // Seed the hero with the first item so it isn't blank before DPAD focus
    // lands (see [_heroActive] for when the hero is shown).
    if (_heroActive) {
      // Seed from the first real title: a pinned collection row can lead the
      // board, and folder tiles can't drive the hero.
      StremioMeta? first;
      for (final section in sections) {
        if (section is HomeCollectionSection) continue;
        if (section.items.isNotEmpty) {
          first = section.items.first;
          break;
        }
      }
      _heroItem.value = first;
      _heroEnriched.value = null;
      // Outside the null-check: a board that reloads EMPTY must clear the
      // shell stage too (null item → null art), not keep the last title's.
      _publishAmbientArt(first, null);
      if (first != null) {
        _enrichHero(first);
        _updateHeroTint(first);
        // Billboard effect: the seeded spotlight starts its trailer too, so
        // opening Home settles into a living hero without any DPAD input.
        // A board reload is a fresh visit — lift any after-the-feature
        // suppression, and drop any Canvas favourites override + live feed
        // (a reload landing while a favourite held focus would otherwise
        // keep its stale art/title on the stage — or resume its stream —
        // with no cell focused, and let the seeded trailer start beneath).
        _heroTrailerSuppressed = false;
        _canvasFavFocus.value = null;
        _clearHeroLiveIptv();
        _scheduleHeroTrailer(first);
      } else {
        _clearHeroTrailer();
        // Clear the COLOUR too, not just the art — an empty reload otherwise
        // left the departed title's tint on the shell stage + sidebar glass.
        _heroTint.value = null;
        _publishHeroTintToShell(null);
      }
    }
  }

  /// Cross-addon catalog search, grouped as one horizontal row per addon so it
  /// matches the board (not a merged grid).
  Future<void> _runCatalogSearch(String query) async {
    final token = ++_catalogSearchToken;
    setState(() {
      _catalogQuery = query;
      _catalogSearching = true;
      _catalogSearchFailures = 0;
    });
    // If DPAD focus is sitting on a result card from the PREVIOUS query, pull it
    // back to the search field before we clear the board below — otherwise
    // disposing that card's FocusNode strands focus. Only reachable on TV, and
    // only when a keystroke's debounce fires after the user jumped down into the
    // old results; the soft keyboard was already up from that keystroke, so this
    // doesn't pop a new one.
    if (widget.isTelevision && !_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
    }
    // Clear the previous query's rows + hero up front. On phone/desktop results
    // then STREAM into the fresh board as they arrive; on TV the board stays on
    // its spinner until every catalog is in and lands in one shot (see below).
    _applySections(const []);
    try {
      // Honour the per-addon toggles from the catalog Sources dialog: skip
      // addons the user disabled for catalog search (empty set = all queried).
      final disabledAddons =
          await StorageService.getCatalogSearchDisabledAddons();
      final addons = (await _stremio.getSearchableAddons())
          .where((a) => !disabledAddons.contains(a.id))
          .toList();
      // One row PER searchable catalog (so Movies and Series land in separate
      // categorised rows, like Stremio) instead of one merged row per addon.
      final catalogTasks =
          <({StremioAddon addon, StremioAddonCatalog catalog})>[];
      for (final addon in addons) {
        for (final catalog in addon.catalogs.where((c) => c.supportsSearch)) {
          catalogTasks.add((addon: addon, catalog: catalog));
        }
      }
      // On TV we deliberately DON'T lazy-stream rows in as they arrive: the
      // incremental appends caused focus/scroll churn while surfing, so TV
      // waits for every catalog and applies them in one shot below. Phone and
      // desktop keep streaming — each row is applied AS IT ARRIVES.
      // _appendSections grows the focus nodes without disposing existing ones,
      // so streamed rows never jump focus.
      //
      // Bound the fan-out either way: with many installed addons this could
      // otherwise fire hundreds of concurrent HTTP requests at once and exhaust
      // sockets/memory on weak hardware.
      final tv = widget.isTelevision;
      var appliedFirst = false;
      final raw = await mapWithConcurrency(catalogTasks, (entry) async {
        List<StremioMeta> items;
        var rawCount = 0;
        try {
          items = await _stremio.searchSingleCatalog(
            entry.addon,
            entry.catalog,
            query,
            throwOnError: true,
            onRawCount: (c) => rawCount = c,
          );
        } catch (_) {
          // Source failed (not "no results") — count it for the status note.
          if (mounted && token == _catalogSearchToken) {
            setState(() => _catalogSearchFailures++);
          }
          return null;
        }
        if (!mounted || token != _catalogSearchToken) return null;
        // Search rows are single-shot (no top-up): a match that's been
        // watched simply doesn't show.
        items = WatchedFilter.apply(items);
        if (items.isEmpty) return null;
        final section = CatalogSection(
          title: CatalogSection.rowTitle(entry.catalog),
          addon: entry.addon,
          catalog: entry.catalog,
          items: items,
          // Carry the query so "See all" keeps searching this catalog rather
          // than browsing it (which would muddy results with non-matches).
          query: query,
          // Seed the paging cursor with the RAW page-1 count (not the
          // invalid-id-filtered items.length), so See All's first search
          // load-more offsets correctly instead of re-fetching page 1.
          nextSkip: rawCount > 0 ? rawCount : items.length,
        );
        // TV: just collect it (applied together after the loop, in stable addon
        // order). Non-TV: stream it into the board now.
        if (!tv) {
          if (!appliedFirst) {
            // First arrival: full apply so the hero seeds from it (the board is
            // empty at this point, so nothing focused gets disposed).
            appliedFirst = true;
            _applySections([section]);
          } else {
            _appendSections([section]);
          }
        }
        return section;
      });
      if (!mounted || token != _catalogSearchToken) return;
      // TV: apply the whole result set at once (mapWithConcurrency preserves
      // input order, so rows land in addon order, not completion order).
      if (tv) {
        _applySections(raw.whereType<CatalogSection>().toList());
      }
      setState(() => _catalogSearching = false);
      if (tv && _rowNodes.isNotEmpty && _rowNodes.first.isNotEmpty) {
        _completeSearchSubmitFocus(_rowNodes.first.first);
      } else if (tv) {
        _searchSubmitFocus.cancel();
      }
    } catch (_) {
      if (!mounted || token != _catalogSearchToken) return;
      _searchSubmitFocus.cancel();
      setState(() => _catalogSearching = false);
    }
  }

  /// Cancel any pending search and return to the homepage board.
  void _restoreHome() {
    _catalogSearchToken++;
    setState(() {
      _catalogQuery = '';
      _catalogSearching = false;
    });
    // A settings/integration reload arrived mid-search and was deferred so it
    // couldn't stomp the results view — run it now instead of restoring the
    // stale cached board.
    if (_pendingBoardReload) {
      _pendingBoardReload = false;
      _load();
      return;
    }
    _applySections(_homeSections);
    _maybeAutoFillBoard();
  }

  // ── Focus entry ──────────────────────────────────────────────────────────

  /// Place — or re-anchor — the board's auto-focus after content loads, so
  /// arriving on the Home tab lands on a card (no stray arrow press) and then
  /// *settles to the top*: focus the best card available now, and as higher rows
  /// arrive (Trakt filling its reserved slot, local Continue Watching) slide up
  /// to the new top card while the user is idle. See [_autoFocusedNode] /
  /// [_autoFocusSettled] for the state machine.
  ///
  /// TV-only, homepage board only. Deferred a frame so the target row is mounted.
  void _maybeAutoFocusBoard() {
    // Every row-load settle path funnels through here, which makes it the one
    // hook needed to complete a DPAD-down deferred while that row was loading.
    // Runs before the settle latch below — deferred moves are USER presses and
    // must work long after auto-focus has handed over control.
    _maybeCompleteDeferredDown();
    if (_autoFocusSettled || _autoFocusScheduled) return;
    if (!widget.isTelevision) return;
    if (widget.searchMode || widget.discoverMode) return;
    _autoFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Coalesced pass: reads the final top after every same-frame load's
      // setState has applied, so multiple loads don't race.
      _autoFocusScheduled = false;
      if (!mounted || _autoFocusSettled) return;
      if (widget.searchMode || widget.discoverMode) return;
      // Only when this is the tab the user is actually looking at. During the
      // ~350ms tab cross-fade the outgoing board is still mounted and shares the
      // ModalRoute, so isCurrent can't tell them apart — the active-tab index
      // can. (main.dart keeps it in lock-step with the rendered tab.)
      if (MainPageBridge.activeTvTabIndex != _tabIndex) return;
      // Don't grab focus if the board isn't the top route — e.g. the user
      // opened a detail page or player and a slow CW/Trakt load only just
      // finished. Stealing focus here would yank it off the pushed screen onto
      // the hidden board below.
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      if (MainPageBridge.isTvSidebarFocused?.call() ?? false) return;

      final primary = FocusManager.instance.primaryFocus;
      final boardFocused = _boardHasFocus();
      if (_autoFocusedNode == null) {
        // Never placed focus yet. If the user already reached a board card on
        // their own, leave it and latch — nothing to auto-place.
        if (boardFocused) {
          _autoFocusSettled = true;
          return;
        }
      } else if (boardFocused && primary != _autoFocusedNode) {
        // We placed focus earlier and it now sits on a *different* board card —
        // the user has taken control. Stop re-anchoring so we never fight them.
        // (Guarded by boardFocused so our own just-applied requestFocus, or a
        // transient null primaryFocus between loads, can't false-trigger this.)
        _autoFocusSettled = true;
        return;
      }

      final top = _topBoardFocusNode();
      if (top == null) return; // nothing focusable yet — retry on the next load
      if (top == _autoFocusedNode) {
        return; // already anchored to the current top
      }
      top.requestFocus();
      _autoFocusedNode = top;
    });
  }

  /// Whether any focusable element on this screen currently holds focus. Used to
  /// avoid stealing focus from the user in [_maybeAutoFocusBoard].
  bool _boardHasFocus() {
    bool anyOf(List<FocusNode> ns) => ns.any((n) => n.hasFocus);
    if (_searchFocusNode.hasFocus ||
        _modeCatalogNode.hasFocus ||
        _modeKeywordNode.hasFocus ||
        _modeListsNode.hasFocus ||
        _modeDropdownNode.hasFocus ||
        _discSourceNode.hasFocus ||
        // Spotlight's hero is a focus target the rail lists know nothing
        // about; without this the arrival machinery thinks the board is
        // unfocused while the hero holds the cursor and steals it back.
        _spotlightHeroNode.hasFocus) {
      return true;
    }
    if (anyOf(_listsNodes)) return true;
    if (anyOf(_cwMovieNodes) ||
        anyOf(_cwSeriesNodes) ||
        anyOf(_traktMovieNodes) ||
        anyOf(_traktSeriesNodes) ||
        anyOf(_simklMovieNodes) ||
        anyOf(_simklSeriesNodes) ||
        anyOf(_mdblistMovieNodes) ||
        anyOf(_mdblistSeriesNodes) ||
        anyOf(_tvFavNodes) ||
        anyOf(_stvFavNodes) ||
        anyOf(_iptvFavNodes) ||
        anyOf(_watchlistMovieNodes) ||
        anyOf(_watchlistSeriesNodes) ||
        anyOf(_playlistFavNodes)) {
      return true;
    }
    for (final row in _rowNodes) {
      if (anyOf(row)) return true;
    }
    return false;
  }

  /// The focus node for the board's current top card — the same target
  /// [_focusContent] would pick on the board path (Continue Watching →
  /// favourites → catalog rows), or null if nothing is focusable yet. Skeleton
  /// Trakt rows carry no nodes, so they're naturally skipped: while Trakt is
  /// reserving, the top is whatever real row sits below the skeletons, and once
  /// the real Trakt rows land they become the top. Drives the "settle to the
  /// top" re-anchor in [_maybeAutoFocusBoard].
  FocusNode? _topBoardFocusNode() {
    // Canvas shows exactly ONE rail — the classic top-row targets are
    // usually unmounted there (and requestFocus on a detached node only
    // latches a stray later grab), so sidebar hand-off / tab re-entry /
    // auto-focus all aim at the displayed rail's nearest mounted cell.
    // Canvas renders exactly ONE rail, so aim at its nearest mounted cell;
    // null (rails still loading) falls through to the classic targets.
    if (_stageActive) return _stageFocusTarget();
    for (final rail in _canvasRails) {
      final nodes = _canvasRailNodes(rail);
      if (nodes.isNotEmpty) return nodes.first;
    }
    return null;
  }

  bool _focusReclaimScheduled = false;

  /// FocusManager listener (TV board only): fires on every app-wide focus
  /// change, so the common path must bail out in a comparison or two. Only a
  /// DEAD state — primary focus fell back to a bare scope (the focused node
  /// was disposed) — schedules the post-frame reclaim pass.
  void _onGlobalFocusChange() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;
    if (_focusReclaimScheduled) return;
    _focusReclaimScheduled = true;
    // Post-frame: the disposal that killed focus is usually mid-rebuild; the
    // board's surviving cells are attached again by the frame's end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusReclaimScheduled = false;
      _reclaimDeadFocus();
    });
  }

  /// Re-anchor focus onto the board after it died. Deliberately picks the
  /// first MOUNTED cell (Continue Watching → favourites → catalog order) — if
  /// the user was deep in the board, the top rows' cells are unmounted and
  /// requestFocus on them is a silent no-op, so walking to a mounted node also
  /// lands focus near where they were looking.
  void _reclaimDeadFocus() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return; // recovered
    if (MainPageBridge.activeTvTabIndex != _tabIndex) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (MainPageBridge.isTvSidebarFocused?.call() ?? false) return;

    // On a stage layout only ONE rail (and, on Tonight, one zone) is mounted,
    // so the data-order walk below would land wherever the first mounted node
    // happens to be — a different rail, or the wrong Tonight zone with the
    // zone flag left lying. Ask the layout where focus belongs first.
    if (_stageActive) {
      final target = _stageFocusTarget();
      if (target != null && (target.context?.mounted ?? false)) {
        target.requestFocus();
        return;
      }
    }

    bool tryRow(List<FocusNode> nodes) {
      for (final n in nodes) {
        if (n.context?.mounted ?? false) {
          n.requestFocus();
          return true;
        }
      }
      return false;
    }

    for (final rail in _canvasRails) {
      if (tryRow(_canvasRailNodes(rail))) return;
    }
  }

  /// DPAD-up from the top row. On the dedicated Search tab the field sits above
  /// the results, so land there; on the Home-New board there's nothing above —
  /// stay put. (This used to hand focus to the sidebar, but the sidebar policy
  /// is now LEFT-only: no other direction may open it.)
  void _leaveBoardTop() {
    if (widget.searchMode) {
      _searchFocusNode.requestFocus();
    }
  }

  void _focusContent() {
    // Discover tab: enter on the Source dropdown (the leading filter); Down from
    // there drops into the grid.
    if (widget.discoverMode) {
      _discSourceNode.requestFocus();
      return;
    }
    // Dedicated Search tab: land on the results when they're on-screen, else the
    // field (the blank prompt has nothing focusable below it). Only focus board
    // rows when a query is actually showing them — otherwise their nodes aren't
    // mounted and focus would be stranded.
    if (widget.searchMode) {
      if (_mode == _Mode.keyword) {
        if (_kwToolbarVisible) {
          _kwToolbarNodes.first.requestFocus();
        } else {
          _searchFocusNode.requestFocus();
        }
        return;
      }
      if (_mode == _Mode.lists) {
        if (_listsResults.isNotEmpty && _listsNodes.isNotEmpty) {
          _listsNodes.first.requestFocus();
        } else {
          _searchFocusNode.requestFocus();
        }
        return;
      }
      // Only when result rows are actually mounted. Mid-search is fine now:
      // the board clears at search start and rows stream in, so a non-empty
      // _rowNodes always belongs to the CURRENT query (never a stale set).
      if (_catalogQuery.isNotEmpty &&
          _rowNodes.isNotEmpty &&
          _rowNodes.first.isNotEmpty) {
        _rowNodes.first.first.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return;
    }
    if (_mode == _Mode.keyword) {
      // Toolbar + result rows render together, so entering the content lands on
      // the toolbar first (Down then reaches the rows). When it isn't visible
      // (loading / error / pre-search) nothing below is focusable, so keep the
      // search field rather than a stale, detached result node.
      if (_kwToolbarVisible) {
        _kwToolbarNodes.first.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return;
    }
    if (_mode == _Mode.lists) {
      if (_listsResults.isNotEmpty && _listsNodes.isNotEmpty) {
        _listsNodes.first.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return;
    }
    // Same top-of-board target the auto-focus "settle to the top" uses, so
    // remote entry and auto-focus always agree on the landing card.
    final top = _topBoardFocusNode();
    if (top != null) {
      top.requestFocus();
      return;
    }
    // Board tab with nothing focusable (empty catalogs). The search field is in
    // the tree on desktop/mobile (persistent bar) but not on the chrome-free TV
    // board — bounce to the sidebar there so the remote never lands nowhere.
    // While the board is still LOADING, though, do nothing: content (and the
    // arrival auto-focus) is moments away, and bouncing to the rail here is
    // exactly the "sidebar opened by itself" the dead-focus recovery used to
    // produce when an arrow landed mid-load.
    if (!widget.isTelevision) {
      _searchFocusNode.requestFocus();
    } else if (!_loading) {
      MainPageBridge.focusTvSidebar?.call();
    }
  }

  /// Focus the Catalog/Keyword/Lists toggle, landing on the segment for the
  /// current mode so its highlight lines up with where the remote cursor sits.
  void _focusModeToggle() {
    if (_useCompactModeMenu) {
      _modeDropdownNode.requestFocus();
      return;
    }
    (switch (_mode) {
      _Mode.catalog => _modeCatalogNode,
      _Mode.keyword => _modeKeywordNode,
      _Mode.lists => _modeListsNode,
    }).requestFocus();
  }

  /// Three labelled segments need more room than the two-mode selector did.
  /// Collapse to one dropdown only when the available header width cannot
  /// carry them comfortably. The TV threshold also protects 720-wide logical
  /// canvases, where the centered search field would otherwise be crushed.
  bool get _useCompactModeMenu {
    if (!kMdblistEnabled) return false;
    final width = MediaQuery.sizeOf(context).width;
    if (widget.isTelevision) return width < 900;
    return width < 342;
  }

  /// Return focus to the search field with the caret at the end of the text, so
  /// leaving the toggle leftward and pressing right again jumps straight back.
  void _focusSearchFieldAtEnd() {
    _searchFocusNode.requestFocus();
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );
  }

  /// Whether the keyword results toolbar (Sort/Filters/Sources/…) is on-screen,
  /// so focus can route into it between the search field and the result rows.
  bool get _kwToolbarVisible =>
      _mode == _Mode.keyword &&
      !_kwLoading &&
      _kwError == null &&
      _kwQuery.isNotEmpty;

  /// Whether the pre-search "Sources" button is on-screen — the empty keyword
  /// state, before a query. It's the only focusable content then, so DPAD-down
  /// from the search field must land on it (see the field's key handler).
  bool get _kwSourcesButtonVisible =>
      _mode == _Mode.keyword &&
      !_kwLoading &&
      _kwError == null &&
      _kwQuery.isEmpty;

  /// Catalog-mode twin of [_kwSourcesButtonVisible]: the Sources button shown
  /// on the empty catalog prompt (Search tab, no query yet, not mid-search).
  bool get _catalogSourcesButtonVisible =>
      _mode == _Mode.catalog &&
      widget.searchMode &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// Returns false when the target catalog row isn't loaded/focusable (after
  /// kicking the next batch load if one is available) — same contract as
  /// [_focusCwRow], so DPAD wiring can defer the move instead of eating it.
  bool _focusRow(int row, int column) {
    if (row >= _rowNodes.length) {
      // Reach visible actions before starting another batch. When no action
      // is mounted, retain the existing deferred move into the next row.
      if (!_boardLoadingMore && _focusCatalogContinuation()) return true;
      if (_boardHasMore) _loadMoreBoard();
      return false;
    }
    if (row < 0) return false;
    final nodes = _rowNodes[row];
    if (nodes.isEmpty) return false;
    // Land on the row's own remembered column, not the source column, so
    // returning to a row you'd scrolled right goes back where you left it (that
    // cell is still mounted). First visit falls back to the incoming column.
    final desired = (_rowCol[row] ?? column).clamp(0, nodes.length - 1);
    _requestRowFocus(nodes, desired);
    return true;
  }

  /// Focus [desired] in [nodes] if its cell is mounted; otherwise the nearest
  /// mounted cell. A horizontal ListView.builder unmounts off-screen cells, and
  /// requestFocus() on an unmounted FocusNode is a silent no-op — so a naive
  /// nodes[desired].requestFocus() leaves focus stranded on the previous row.
  void _requestRowFocus(List<FocusNode> nodes, int desired, {int hops = 0}) {
    // NB: FocusNode.context stays non-null after the owning Focus unmounts
    // (detach() doesn't clear it), so the element's own `mounted` flag — which
    // flips false on unmount — is the reliable "can this node take focus" test.
    bool isMounted(FocusNode n) => n.context?.mounted ?? false;
    if (isMounted(nodes[desired])) {
      nodes[desired].requestFocus();
      return;
    }
    for (var d = 1; d < nodes.length; d++) {
      final lo = desired - d;
      final hi = desired + d;
      if (lo >= 0 && isMounted(nodes[lo])) {
        nodes[lo].requestFocus();
        return;
      }
      if (hi < nodes.length && isMounted(nodes[hi])) {
        nodes[hi].requestFocus();
        return;
      }
    }
    // The whole row is unmounted: it sits beyond the board's deliberately
    // small vertical cacheExtent (300) — the live case is DPAD-down off the
    // last Continue Watching row while TWO Trakt skeleton rows (~380px of
    // focusless shimmer) separate it from the favourites/catalog row below.
    // requestFocus on a detached node would only latch a focus grab for
    // whenever that cell happens to build (a later yank, not a move — the old
    // "blocked DOWN"), so instead nudge the board forward and retry until the
    // row builds. Down-only on purpose: an unmounted target ABOVE can't
    // happen from row-by-row DPAD moves (the row above was just on screen,
    // still inside the cache). Bounded so the total travel stays within the
    // cache above the origin cell — it can't unmount mid-journey — and a
    // settled miss just leaves focus where it was.
    //
    // Glides (was jumpTo — a visible 45%-viewport teleport). The retry MUST
    // wait for the glide to land, not the next frame: per-frame retries would
    // spend all 3 hops inside one animation before the row could ever build.
    if (hops >= 3 || !_boardScroll.hasClients) return;
    final pos = _boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent) return;
    _boardScroll
        .animateTo(
          (pos.pixels + pos.viewportDimension * 0.45).clamp(
            0.0,
            pos.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _requestRowFocus(nodes, desired, hops: hops + 1);
          });
        });
  }

  // ── TV Home layout (classic / canvas) ────────────────────────────────────

  /// Active home layout, from `tv_home_style`. The HOME board renders it on
  /// TV; off-TV the pref is resolved through [effectiveOffTvHomeStyle] and
  /// only Spotlight passes through — Search tab and Discover always render
  /// classic (via [_homeStyleEffective], regardless of this field). Canvas is
  /// the TV default; matching it here avoids a one-frame classic flash at
  /// boot there, and resolves to classic off-TV.
  String _tvHomeStyle = StorageService.tvHomeStyleCached;

  // Landscape default matches the stored default, so a fresh boot doesn't
  // flash portrait rows before the async pref read lands.
  HomeCardOrientation _homeCardOrientation = HomeCardOrientation.landscape;
  bool _hideHomeCardTitlesAndRatings = false;
  bool _hideHomeCatalogAddonNames = false;

  bool get _homeLandscapeCards =>
      _homeCardOrientation == HomeCardOrientation.landscape;

  double get _homeArtPosterCaptionBand =>
      _hideHomeCardTitlesAndRatings ? 0 : _artPosterCaptionBand(context);

  bool get _homeBoardMode =>
      widget.isTelevision && !widget.searchMode && !widget.discoverMode;

  // ── Off-TV Spotlight shell state ─────────────────────────────────────────
  //
  // Four separate questions, deliberately not one predicate (the sheet is a
  // latched state machine — see SPOTLIGHT_RESPONSIVE_PLAN.md):
  //  • [_spotlightSelected] — the resolved pref says Spotlight.
  //  • [_spotlightShellActive] — this Home instance renders the shell branch
  //    (either of its two states) instead of the plain classic Column.
  //  • [_sheetForced] — search state that REQUIRES the header on screen.
  //  • [_searchSheetOpen] — the latch. Set by the search button, by field
  //    focus, and silently whenever [_sheetForced] is observed true; cleared
  //    only by the explicit close/back reset. The latch is what stops the
  //    header collapsing under a focused field when its force condition
  //    momentarily clears (deleting the last character of a query).

  /// The stored style, resolved for this platform, is Spotlight. Off-TV only.
  bool get _spotlightSelected =>
      !widget.isTelevision &&
      effectiveOffTvHomeStyle(_tvHomeStyle) == 'spotlight';

  /// Whether the off-TV Home renders the Spotlight shell branch. While the
  /// selected layout is loading, retain this branch so a newly mounted Home
  /// cannot flash Classic's persistent search bar before its hero arrives.
  /// After loading, the hero guard still matters: CW/favourites-only content
  /// would otherwise render a large empty hero.
  bool get _spotlightShellActive =>
      !widget.searchMode &&
      !widget.discoverMode &&
      shouldUseOffTvSpotlightShell(
        rawStyle: _tvHomeStyle,
        loading: _loading,
        hasHero: _spotlightHero.isNotEmpty,
      );

  /// Search state that forces the header/sheet to be visible. Typing is
  /// covered by the focus latch (one can only type while the field is
  /// focused, and focus latches [_searchSheetOpen]); this covers the states
  /// that arrive WITHOUT the field being touched: the async keyword-default
  /// restore, preserved keyword results, a committed catalog search, or the
  /// dedicated Lists surface.
  bool get _sheetForced =>
      _mode != _Mode.catalog ||
      _catalogQuery.isNotEmpty ||
      _catalogSearching ||
      // Belt to the focus latch's braces: interactive typing always comes
      // through a focused field, but autofill or a programmatic controller
      // write would not — and text on screen must force the header that
      // renders it.
      _searchController.text.isNotEmpty;

  /// The sheet latch. See the block comment above.
  bool _searchSheetOpen = false;

  int get _tvHeroArtworkCacheWidth =>
      TvHeroArtworkQualityController.decodeSize.landscapeWidth;
  int get _tvHeroArtworkCacheHeight =>
      TvHeroArtworkQualityController.decodeSize.posterHeight;

  /// The layout the CURRENT surface should render (guards non-home surfaces).
  /// The layout the CURRENT surface should render. TV: the stored style on
  /// the Home board, classic everywhere else. Off-TV: Spotlight only while
  /// the full-bleed shell is actually on screen — results, keyword mode and
  /// the open search sheet all dispatch to the classic board, so the search
  /// experience is byte-identical to today whenever search is in play.
  String get _homeStyleEffective {
    if (widget.isTelevision) return _homeBoardMode ? _tvHomeStyle : 'classic';
    return _spotlightShellActive && !_searchSheetOpen ? 'spotlight' : 'classic';
  }

  /// Any of the STAGE layouts (everything except classic). They all share one
  /// model — a single active rail, identified by key, whose focused cell owns
  /// a hero stage — so focus routing, rail switching, the favourites override
  /// and the style-change teardown are common to all of them. Only the
  /// painting differs, per `_build*Board`.
  ///
  /// Favourites are first-class rails on every stage layout, so there is no
  /// fallback to classic: the pref alone decides. While everything is still
  /// loading a stage shows the brand stage, and the shared empty-state guards
  /// above the board branch handle the truly-nothing case.
  bool get _stageActive => _homeStyleEffective != 'classic';

  /// Whether this layout gives moving picture a place to live: the ambient
  /// trailer and the IPTV favourite's live preview. Mosaic deliberately opts
  /// out — it has no stage, only a heavily-veiled art wash behind a grid, so
  /// a video there would be invisible AND the most expensive thing on screen.
  bool get _stageWantsAmbient => switch (_homeStyleEffective) {
    'canvas' ||
    'promenade' ||
    'deck' ||
    'atrium' ||
    'tonight' ||
    'spotlight' => true,
    _ => false,
  };

  /// A focused IPTV favourite's LIVE feed is a different question from a
  /// catalog trailer: it is the only way to see what a channel is actually
  /// playing, so every stage layout keeps it — Mosaic included, where the
  /// wall's veil lifts for it. Only the speculative catalog trailer is off
  /// there (see [_stageWantsAmbient]).
  bool get _stageWantsLivePreview => _stageActive;

  /// Whether this layout's ground is the title's ART, edge to edge — the only
  /// case where lighting the app shell behind the ghost rail continues the
  /// board instead of cutting across it. See [_publishAmbientArt].
  bool get _stagePublishesShellArt => switch (_homeStyleEffective) {
    // Spotlight's hero IS the ground, edge to edge, so lighting the shell
    // behind the rail continues the board rather than cutting across it.
    'canvas' || 'promenade' || 'spotlight' => true,
    _ => false,
  };

  /// Theater mode (shelf recedes so the video owns the frame) only makes
  /// sense where the video IS the frame. Atrium's art is a column, Tonight's
  /// is a card among panels, and Mosaic has none.
  bool get _theaterEligible => switch (_homeStyleEffective) {
    'canvas' || 'promenade' || 'deck' || 'spotlight' => true,
    _ => false,
  };

  /// Bumped by every layout transition and every board reseed. Post-frame
  /// focus callbacks capture it (with the style) and bail if either moved —
  /// a callback posted by Canvas must never land focus inside Mosaic.
  int _stageGeneration = 0;

  /// Deferred stage move: DOWN past the last rail asked for a batch that had
  /// not arrived. Keyed by the rail the user pressed DOWN on, so a batch that
  /// lands after they have moved elsewhere is ignored.
  String? _pendingStageAdvanceKey;
  DateTime? _pendingStageAdvanceAt;

  /// The node that pressed the key. A deferred move is only ever completed
  /// while THAT node still holds focus — the rail key alone isn't enough
  /// (moving LEFT along the same rail, or out to the sidebar, leaves it
  /// unchanged), and a late batch must never yank the user somewhere else.
  FocusNode? _pendingStageOrigin;

  /// Atrium-only: the pending move fills the window's EMPTY lower row rather
  /// than scrolling the window on.
  bool _pendingStageAdvanceFillsLower = false;

  /// A RIGHT that ran off the END of a rail whose catalog still had pages.
  /// Mosaic's grid depends on it: DOWN there always leaves for the next rail,
  /// so RIGHT is the only way through a long catalog and eating the keypress
  /// would strand the user at the page boundary.
  String? _pendingStageRightKey;
  int _pendingStageRightCol = -1;
  DateTime? _pendingStageRightAt;
  FocusNode? _pendingStageRightOrigin;

  void _deferStageRight(String railKey, int col) {
    final origin = FocusManager.instance.primaryFocus;
    if (origin == null) return;
    _pendingStageRightKey = railKey;
    _pendingStageRightCol = col;
    _pendingStageRightAt = DateTime.now();
    _pendingStageRightOrigin = origin;
  }

  /// Record a deferred rail move, anchored to whoever pressed the key.
  void _deferStageAdvance(String railKey, {bool fillsLower = false}) {
    final origin = FocusManager.instance.primaryFocus;
    if (origin == null) return;
    _pendingStageAdvanceKey = railKey;
    _pendingStageAdvanceAt = DateTime.now();
    _pendingStageAdvanceFillsLower = fillsLower;
    _pendingStageOrigin = origin;
  }

  /// Shared staleness test for both deferred moves.
  bool _stageDeferralStillValid(DateTime at, FocusNode? origin) =>
      _stageActive &&
      origin != null &&
      identical(FocusManager.instance.primaryFocus, origin) &&
      DateTime.now().difference(at) <= _pendingDownMaxAge;

  /// Called when a ROW's next page lands: completes a deferred RIGHT if the
  /// user is still sitting on the cell they pressed it from.
  void _maybeCompleteStageRight() {
    final key = _pendingStageRightKey;
    final at = _pendingStageRightAt;
    final col = _pendingStageRightCol;
    final origin = _pendingStageRightOrigin;
    if (key == null || at == null) return;
    _pendingStageRightKey = null;
    _pendingStageRightAt = null;
    _pendingStageRightCol = -1;
    _pendingStageRightOrigin = null;
    if (_canvasRailKey != key) return;
    if (!_stageDeferralStillValid(at, origin)) return;
    _stagePostFrameFocus(() {
      // Re-check INSIDE the frame: focus can move during the post-frame gap.
      if (!identical(FocusManager.instance.primaryFocus, origin)) return null;
      final rails = _stageRails;
      final i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
      if (i < 0) return null;
      final nodes = _canvasRailNodes(rails[i]);
      if (col + 1 >= nodes.length) return null;
      return (nodes[col + 1].context?.mounted ?? false) ? nodes[col + 1] : null;
    });
  }

  /// Every piece of per-layout navigation state, cleared as one. Called on a
  /// real layout transition (either the picker or the saved pref landing at
  /// cold start) — never partially, or a layout inherits a rail/zone/column
  /// that means something else in its own geometry.
  void _resetStageNavigation() {
    _canvasFocusSeeded = false;
    _canvasTheaterTimer?.cancel();
    _canvasTheater = false;
    _canvasFavFocus.value = null;
    _canvasRailKey = null;
    _canvasCols.clear();
    _tonightZoneIsQueue = true;
    _tonightQueueCol = 0;
    _tonightQueueKey = null;
    _atriumFocusedRailKey.value = null;
    _tonightCard.value = null;
    _stageCol.value = 0;
    _pendingStageAdvanceKey = null;
    _pendingStageAdvanceAt = null;
    _pendingStageAdvanceFillsLower = false;
    _pendingStageOrigin = null;
    _pendingStageRightKey = null;
    _pendingStageRightAt = null;
    _pendingStageRightCol = -1;
    _pendingStageRightOrigin = null;
    _stageHoldLatchedKey = null;
    _stageGeneration++;
  }

  /// THE single layout-transition path. Both entry points route here — the
  /// Settings picker AND the cold-start load, which is also a transition
  /// (the field starts at the product default, so a saved 'mosaic' relayouts
  /// a board that may already have a trailer or a live preview running).
  void _applyStageTransition(String style) {
    // Tear the live players down BEFORE the relayout: the underlay engine
    // widget must never be re-parented into a different geometry mid-play.
    _clearHeroTrailer();
    _clearHeroLiveIptv();
    _resetStageNavigation();
    // The shell's ambient art is per-layout (ink-ground layouts publish
    // none), so clear it rather than leaving the old layout's lighting in
    // the strip behind the ghost rail.
    _ambientArtItemId = null;
    if (MainPageBridge.tvAmbientArt.value != null) {
      MainPageBridge.tvAmbientArt.value = null;
    }
    setState(() => _tvHomeStyle = style);
    // …then republish for the layout we just switched TO: Canvas/Promenade
    // want the shell lit again, and the ink layouts want it to stay dark.
    // Without this the shell keeps whatever the previous layout left until
    // some unrelated hero change happens to refresh it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishAmbientArt(_heroItem.value, _heroEnriched.value);
      _publishHeroTintToShell(_heroTint.value);
    });
  }

  Future<void> _loadTvHomeStyle() async {
    final style = await StorageService.getTvHomeStyle();
    if (!mounted || style == _tvHomeStyle) return;
    _applyStageTransition(style);
  }

  Future<void> _loadHomeCardOrientation() async {
    final values = await Future.wait<Object>([
      StorageService.getHomeCardOrientation(),
      StorageService.getHomeHideCardTitlesAndRatings(),
      StorageService.getHomeHideCatalogAddonNames(),
    ]);
    if (!mounted) return;
    final orientation = values[0] as HomeCardOrientation;
    final hideTitlesAndRatings = values[1] as bool;
    final hideCatalogAddonNames = values[2] as bool;
    if (orientation == _homeCardOrientation &&
        hideTitlesAndRatings == _hideHomeCardTitlesAndRatings &&
        hideCatalogAddonNames == _hideHomeCatalogAddonNames) {
      return;
    }
    setState(() {
      _homeCardOrientation = orientation;
      _hideHomeCardTitlesAndRatings = hideTitlesAndRatings;
      _hideHomeCatalogAddonNames = hideCatalogAddonNames;
    });
  }

  /// Settings picker fired: tear down live players BEFORE the relayout, so
  /// the underlay engine widget is never re-parented mid-play, then re-read
  /// the pref and rebuild.
  void _onTvHomeStyleChanged() {
    if (!mounted) return;
    unawaited(_loadTvHomeStyle());
  }

  void _onTvHeroArtworkQualityChanged() {
    if (!mounted || !_homeBoardMode) return;
    setState(() {});
  }

  // ── CANVAS view ──────────────────────────────────────────────────────────

  /// IDENTITY of the active Canvas rail (not an index): rails stream in and
  /// reorder — CW rails prepend when Trakt/Simkl land seconds after a cold
  /// start — and a raw index would silently swap the shelf's content and
  /// teleport focus/hero when that happens. Null = first rail.
  String? _canvasRailKey;

  /// The focused column of the active rail, as a notifier — Deck's peek stack
  /// has to re-derive "the next two titles" on every horizontal move, and the
  /// remembered-column MAP is a plain field write that rebuilds nothing.
  final ValueNotifier<int> _stageCol = ValueNotifier<int>(0);

  /// Remembered column per rail key (the Canvas mirror of classic's _rowCol).
  final Map<String, int> _canvasCols = {};

  /// One-shot: hand entry focus to the shelf the first time Canvas builds.
  bool _canvasFocusSeeded = false;

  /// Stage override while a favourites cell has focus (see
  /// [_CanvasFavFocus]). A ValueNotifier — NOT setState — so scrubbing along
  /// a favourites rail repaints only the stage layers that listen (art +
  /// identity), never the whole board (the hero pipeline's own pattern).
  final ValueNotifier<_CanvasFavFocus?> _canvasFavFocus =
      ValueNotifier<_CanvasFavFocus?>(null);

  /// A Canvas favourites cell took focus: remember the column, stop any
  /// catalog trailer machinery (a PENDING hero swap firing later would start
  /// a full-bleed trailer of an unrelated title under favourites browsing),
  /// drive the live preview for IPTV, and hand the stage the favourite's own
  /// art + name.
  void _canvasFavFocused(
    String railKey,
    int col,
    _CanvasFavFocus focus, {
    IptvChannel? liveChannel,
  }) {
    _canvasCols[railKey] = col;
    _stageCol.value = col;
    // Atrium's two-row window needs to know which row owns focus (favourites
    // cells don't go through a _BoardCell onFocused), and favourites only
    // ever live in Tonight's RAIL zone, never its Continue queue.
    _atriumFocusedRailKey.value = railKey;
    _tonightZoneIsQueue = false;
    _heroSwapTimer?.cancel();
    _clearHeroTrailer();
    if (liveChannel != null && _stageWantsLivePreview) {
      _setHeroLiveIptv(liveChannel);
    } else {
      _clearHeroLiveIptv();
    }
    _canvasFavFocus.value = focus;
  }

  /// One favourites cell on the Canvas shelf — the SAME [_FavArtCell] +
  /// [_ArtPoster] stack the classic rows use (identical art, badges, hold
  /// behaviour and open actions), with UP/DOWN rewired to rail switching and
  /// focus driving the Canvas stage override (and the full-bleed live
  /// preview, for IPTV).
  Widget _canvasFavCell(
    _FavRowRef ref,
    String railKey,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
  }) {
    final nodes = _favNodesFor(ref);
    // Rail switching is the default vertical grammar; Mosaic (grid) and
    // Tonight (zones) pass their own.
    final up = onUp ?? () => _stageSwitchRail(-1);
    final down = onDown ?? () => _stageSwitchRail(1);
    // An IPTV custom-list row: same cell stack as the favourites row below,
    // but channels come from the list, play routes by CONTENT TYPE (a list
    // can hold VOD), and only a live entry retunes the stage's live preview.
    if (ref.isIptvList) {
      final row = _iptvListRows[ref.list];
      final channel = row.channels[col];
      final live = channel.isLive;
      return _FavArtCell(
        isTelevision: true,
        column: col,
        rowNodes: nodes,
        onUp: up,
        onDown: down,
        onLeft: onLeft,
        onRight: onRight,
        onUpHold: onUpHold,
        onDownHold: onDownHold,
        child: _ArtPoster(
          imageUrl: channel.logoUrl,
          title: channel.name,
          showTitle: !_hideHomeCardTitlesAndRatings,
          imageFit: BoxFit.contain,
          isTelevision: true,
          ringColor: Colors.white,
          focusNode: nodes[col],
          onOpen: () => _playIptvListChannel(channel),
          onFocused: () => _canvasFavFocused(
            railKey,
            col,
            _CanvasFavFocus(
              art: channel.logoUrl,
              fit: BoxFit.contain,
              title: channel.name,
              subtitle: 'IPTV · ${row.title.toUpperCase()}',
            ),
            liveChannel: live ? channel : null,
          ),
        ),
      );
    }
    switch (ref.kind) {
      case _FavKind.watchlistMovies:
      case _FavKind.watchlistSeries:
        final items = ref.kind == _FavKind.watchlistMovies
            ? _watchlistMovieItems
            : _watchlistSeriesItems;
        final item = items[col];
        return _FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: _ArtPoster(
            imageUrl: item.poster,
            title: item.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => _openMyWatchlistItem(item),
            onFocused: () => _canvasFavFocused(
              railKey,
              col,
              _CanvasFavFocus(
                art: _firstNonEmpty(item.background, item.poster),
                title: item.name,
                subtitle: 'MY WATCHLIST · ${item.type.toUpperCase()}',
              ),
            ),
          ),
        );
      case _FavKind.iptv:
        final channel = _iptvFavChannels[col];
        return _FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: _ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            imageFit: BoxFit.contain,
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => _playIptvChannel(channel),
            // Focus lights the whole stage with this channel's live feed —
            // the classic boxed preview, promoted to full-bleed.
            onFocused: () => _canvasFavFocused(
              railKey,
              col,
              _CanvasFavFocus(
                art: channel.logoUrl,
                fit: BoxFit.contain,
                title: channel.name,
                subtitle: 'IPTV · FAVORITES',
              ),
              liveChannel: channel,
            ),
          ),
        );
      case _FavKind.debrify:
        final channel = _tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return _FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: _ArtPoster(
            imageUrl: null,
            title: channel.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            badge: '$number',
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => _playChannel(channel),
            onFocused: () => _canvasFavFocused(
              railKey,
              col,
              _CanvasFavFocus(
                art: null,
                title: channel.name,
                subtitle: 'DEBRIFY TV · CHANNEL $number',
              ),
            ),
          ),
        );
      case _FavKind.stremio:
        final channel = _stvFavChannels[col];
        final item = _stvNowPlaying(channel)?.item;
        return _FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: _ArtPoster(
            imageUrl: _firstNonEmpty(item?.poster, item?.background),
            title: channel.displayName,
            showTitle: !_hideHomeCardTitlesAndRatings,
            live: true,
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => _playStremioTvChannel(channel),
            onFocused: () => _canvasFavFocused(
              railKey,
              col,
              _CanvasFavFocus(
                // The stage prefers the WIDE art; the card keeps the poster.
                art: _firstNonEmpty(item?.background, item?.poster),
                title: channel.displayName,
                subtitle: item != null
                    ? 'STREMIO TV · NOW: ${item.name}'
                    : 'STREMIO TV · CHANNEL',
              ),
            ),
          ),
        );
      case _FavKind.playlist:
        final item = _playlistItems[col];
        final posterUrl = item['posterUrl'] as String?;
        final title = (item['title'] as String?) ?? 'Unknown';
        return _FavArtCell(
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: _ArtPoster(
            imageUrl: posterUrl,
            title: title,
            showTitle: !_hideHomeCardTitlesAndRatings,
            progress: _playlistProgressFor(item),
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => _onPlaylistItemTap(item),
            onFocused: () => _canvasFavFocused(
              railKey,
              col,
              _CanvasFavFocus(
                art: posterUrl,
                title: title,
                subtitle: 'PLAYLIST · SAVED',
              ),
            ),
          ),
        );
    }
  }

  /// Theater mode: after the ambient trailer has been SHOWING frames for a
  /// dwell, the shelf/tabs (and their bottom scrim) recede so the video owns
  /// the whole screen — logo + AMBIENT chip hold. Any key wakes the lights
  /// (observe-only: the key still does its job), and if playback continues
  /// uninterrupted the dwell re-arms. The shelf is hidden VISUALLY only
  /// (opacity/slide, never unmounted), so focus stays exactly where it was.
  bool _canvasTheater = false;
  Timer? _canvasTheaterTimer;
  static const _canvasTheaterDwell = Duration(seconds: 5);

  void _onCanvasTrailerShowingChanged() {
    if (!mounted) return;
    if (!_theaterEligible) {
      _canvasTheaterTimer?.cancel();
      if (_canvasTheater) setState(() => _canvasTheater = false);
      return;
    }
    if (_heroTrailerShowing.value) {
      _armCanvasTheater();
    } else {
      // Trailer gone (DPAD move cleared it / playback ended) — lights up.
      _canvasTheaterTimer?.cancel();
      if (_canvasTheater) setState(() => _canvasTheater = false);
    }
  }

  void _armCanvasTheater() {
    _canvasTheaterTimer?.cancel();
    _canvasTheaterTimer = Timer(_canvasTheaterDwell, () {
      if (!mounted || !_theaterEligible || !_heroTrailerShowing.value) {
        return;
      }
      setState(() => _canvasTheater = true);
    });
  }

  /// Global key observer (cheap first-compare on the common path): any
  /// key-down during theater wakes the lights and re-arms the dwell. Never
  /// handles the key — it must still perform its normal action.
  bool _onCanvasTheaterKey(KeyEvent event) {
    if (!_canvasTheater || event is! KeyDownEvent) return false;
    if (mounted) setState(() => _canvasTheater = false);
    _armCanvasTheater();
    return false;
  }

  String _canvasRailKeyOf(_CanvasRail rail) {
    return 'row:${_canvasRailRowId(rail)}';
  }

  /// Where the active rail currently sits in [rails] — re-resolved every
  /// build so insertions above it never change WHICH rail is shown.
  int _resolveCanvasRailIndex(List<_CanvasRail> rails) {
    final key = _canvasRailKey;
    if (key != null) {
      final i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
      if (i >= 0) return i;
    }
    return 0;
  }

  /// Nearest MOUNTED node to [col] in [nodes], or null. Canvas only builds
  /// the visible strip of the one displayed rail, so a bare first/last node
  /// may be detached — and requestFocus on a detached node only latches a
  /// stray focus grab for whenever it happens to mount.
  FocusNode? _nearestMountedNode(List<FocusNode> nodes, int col) {
    if (nodes.isEmpty) return null;
    bool isMounted(FocusNode n) => n.context?.mounted ?? false;
    final c = col.clamp(0, nodes.length - 1);
    if (isMounted(nodes[c])) return nodes[c];
    for (var d = 1; d < nodes.length; d++) {
      final lo = c - d;
      final hi = c + d;
      if (lo >= 0 && isMounted(nodes[lo])) return nodes[lo];
      if (hi < nodes.length && isMounted(nodes[hi])) return nodes[hi];
    }
    return null;
  }

  // ── Spotlight ───────────────────────────────────────────────────────────

  final GlobalKey<SpotlightBoardState> _spotlightKey =
      GlobalKey<SpotlightBoardState>();
  final FocusNode _spotlightHeroNode = FocusNode(debugLabel: 'spotlight-hero');

  /// The hero reel fetched from the user's chosen source (`random`/`custom`
  /// modes), fetched by [_resolveSpotlightHeroSource] independently of the
  /// board batches — the chosen catalog may sit pages down the board, or be
  /// hidden as a row entirely. Null in `auto` mode, while the fetch is in
  /// flight, and when every candidate came up dead — all of which fall back
  /// to the first non-empty board row below.
  CatalogSection? _spotlightHeroOverride;

  /// Guards [_resolveSpotlightHeroSource] against overlapping runs (a Home
  /// Rows save landing mid-load): only the newest run may commit.
  int _heroSourceResolveGen = 0;

  /// Fetch the hero reel for the current [_heroSource] pref.
  ///
  /// Candidates come from the FULL browsable set, not [_boardRefs] — hiding a
  /// catalog's row on the board must not blank a hero pinned to that same
  /// catalog. Candidates are shuffled so `random` mode and a multi-pick
  /// `custom` re-roll on every board load; the first candidate that returns
  /// items wins. Attempts are capped so a wall of dead catalogs can't fan out
  /// unbounded fetches; exhausting the cap (or the candidates) clears the
  /// override, which IS the auto fallback.
  Future<void> _resolveSpotlightHeroSource(List<StremioAddon> addons) async {
    final gen = ++_heroSourceResolveGen;
    final source = _heroSource;
    if (source.mode != HomeHeroSourceMode.auto) {
      final all = [
        for (final a in addons)
          for (final c in a.catalogs)
            if (c.isBrowsable) (a, c),
      ];
      final List<(StremioAddon, StremioAddonCatalog)> candidates;
      if (source.mode == HomeHeroSourceMode.random) {
        // Random draws TITLES only. Live catalogs — 'tv' is what the
        // Stremio-IPTV service itself keys on, 'channel'/'radio' are the
        // spec's other live-ish types — serve channel logos as their art, so
        // the reel cover-crops a wordmark to a full screen (TvVoo's logo,
        // full-bleed, was the report). An EXPLICIT custom pick of such a
        // catalog is left alone: choosing it by name is a deliberate act.
        const live = {'tv', 'channel', 'radio'};
        candidates = [
          for (final ref in all)
            if (!live.contains(ref.$2.type.toLowerCase())) ref,
        ];
      } else {
        // Stored picks that no longer resolve (addon uninstalled, catalog
        // gone from its manifest) simply drop out; they are NOT removed from
        // the pref, so reinstalling the addon brings the pick back.
        final byId = {
          for (final (a, c) in all) '${a.id}:${c.type}:${c.id}': (a, c),
        };
        candidates = [
          for (final id in source.ids)
            if (byId.containsKey(id)) byId[id]!,
        ];
      }
      candidates.shuffle(Random());
      const maxAttempts = 8;
      var attempts = 0;
      for (final (addon, catalog) in candidates) {
        if (attempts++ >= maxAttempts) break;
        if (!mounted || gen != _heroSourceResolveGen) return;
        try {
          final page = await fetchFilteredPage(
            (skip, onRaw) => _stremio.fetchCatalog(
              addon,
              catalog,
              skip: skip,
              onRawCount: onRaw,
            ),
            skip: 0,
            hides: WatchedFilter.predicate,
            minItems: 8,
          );
          if (!mounted || gen != _heroSourceResolveGen) return;
          if (page.items.isEmpty) continue;
          setState(() {
            _spotlightHeroOverride = CatalogSection(
              title: CatalogSection.rowTitle(catalog),
              addon: addon,
              catalog: catalog,
              items: page.items.toList(),
              nextSkip: page.nextSkip,
            );
          });
          _publishTopShelfSpotlight();
          return;
        } catch (_) {
          // Dead addon or catalog — try the next candidate.
        }
      }
    }
    // Auto mode, no usable candidate, or every attempt failed — drop any
    // stale override so the reel falls back rather than pinning old prefs.
    if (!mounted || gen != _heroSourceResolveGen) return;
    if (_spotlightHeroOverride != null) {
      setState(() => _spotlightHeroOverride = null);
    }
    _publishTopShelfSpotlight();
  }

  /// The hero reel.
  ///
  /// NOT `_stageRails[0]`: the user's first row may be a channel, playlist, or
  /// Continue Watching rail rather than a catalog, and rails can arrive as
  /// tracker data lands. The hero needs a
  /// stable list of real catalog titles, so it takes the user's resolved
  /// source pick when there is one, else the first section that has any items
  /// — and caps it either way: a reel longer than about eight is a list, not
  /// a hero.
  CatalogSection? get _spotlightHeroSection {
    // A catalog search swaps `_sections` to results, and the reel follows
    // them — the pinned source is Home-board furniture and must not paint
    // over a search.
    final override = _spotlightHeroOverride;
    if (override != null && _catalogQuery.isEmpty && !_catalogSearching) {
      return override;
    }
    for (final section in _sections) {
      // Folder tiles aren't titles, so they can't feed the hero reel.
      if (section is HomeCollectionSection) continue;
      if (section.items.isNotEmpty) return section;
    }
    return null;
  }

  List<StremioMeta> get _spotlightHero =>
      _spotlightHeroSection?.items.take(8).toList() ?? const [];

  void _publishTopShelfSpotlight() {
    if (!PlatformUtil.isTvOS || widget.searchMode || widget.discoverMode) {
      return;
    }
    unawaited(
      TvosTopShelfService.instance.publishSpotlight(
        _spotlightHero,
        sourceTitle: _spotlightHeroSection?.title,
      ),
    );
  }

  List<SpotlightShelf> get _spotlightShelves => [
    for (final rail in _canvasRails) _spotlightShelfForRail(rail),
  ];

  SpotlightShelf _spotlightShelfForRail(_CanvasRail rail) {
    // Rail identity — the same key Canvas/Atrium key their rails by — so the
    // board reuses shelf subtrees when tracker rows front-insert.
    final railKey = _canvasRailKeyOf(rail);
    final row = rail.cw;
    if (row != null) {
      return SpotlightShelf(
        id: railKey,
        title: row.title,
        // The tag used to be folded into the title text; now it IS the tag —
        // the same pill grammar the catalog rows wear.
        tag: row.tag,
        nodes: row.nodes,
        // Already nullable on the row itself — a tracker row with no grid
        // behind it hands over null and simply draws no chevron.
        onSeeAll: row.onSeeAll,
        // Caption-free like catalog rows in PORTRAIT off TV. LANDSCAPE flips
        // the premise: a textless still needs the title, and CW's second line
        // adds its useful episode / remaining-time context.
        captions: _homeLandscapeCards,
        items: [
          for (var col = 0; col < row.items.length; col++)
            _spotlightContinueWatchingCard(
              row,
              row.items[col],
              rail.cwIndex,
              col,
            ),
        ],
      );
    }
    final fav = rail.favKind;
    if (fav != null) return _spotlightFavShelf(fav, id: railKey);
    final i = rail.sectionIndex!;
    final section = _sections[i];
    if (section is HomeCollectionSection) {
      return SpotlightShelf(
        id: railKey,
        title: section.title,
        tag: _catalogSourceTag(section),
        nodes: i < _rowNodes.length ? _rowNodes[i] : const [],
        onSeeAll: () => _openCatalogSeeAll(section),
        // A brand-logo tile needs no caption; captions stay on only while
        // some folder still wants its title drawn.
        captions: section.collection.folders.any((f) => !f.hideTitle),
        items: [
          for (final m in section.items)
            SpotlightCard(
              image: m.poster,
              fallbackImage: m.background,
              previewBuilder: section.focusArtOf(m) == null
                  ? null
                  : (_) => CachedNetworkImage(
                      imageUrl: section.focusArtOf(m)!,
                      memCacheWidth: 640,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                      fit: BoxFit.cover,
                    ),
              title: m.name,
              shape: section.tileAspectRatio == 1
                  ? SpotlightCardShape.square
                  : section.landscapeTiles
                  ? SpotlightCardShape.wide
                  : SpotlightCardShape.poster,
              showCaption: !(section.folderOf(m)?.hideTitle ?? false),
              onOpen: () => _openCollectionFolder(section, m),
            ),
        ],
      );
    }
    return SpotlightShelf(
      id: railKey,
      title: _sections[i].title,
      tag: _catalogSourceTag(_sections[i]),
      nodes: i < _rowNodes.length ? _rowNodes[i] : const [],
      // The same destination the classic rails' "See All" link opens —
      // including the tracker-list rows, which _openCatalogSeeAll routes to
      // their own browser rather than the catalog pager.
      onSeeAll: () => _openCatalogSeeAll(_sections[i]),
      // Catalog cards go caption-free off TV in PORTRAIT — the art is the
      // label; a caption repeating the poster's own title was the
      // reference's one piece of noise we added ourselves. That rationale
      // inverts for LANDSCAPE, where the backdrop is a textless still and
      // the caption is the only identity the card has.
      captions: _homeLandscapeCards,
      items: [
        for (final m in _sections[i].items)
          SpotlightCard(
            image: _homeLandscapeCards ? _wideArtUrl(m) : m.poster,
            fallbackImage: _homeLandscapeCards ? m.poster : null,
            title: m.name,
            rating: m.imdbRating,
            shape: _homeLandscapeCards
                ? SpotlightCardShape.wide
                : SpotlightCardShape.poster,
            watchedImdbId: m.type == 'movie' || m.type == 'series'
                ? (m.effectiveImdbId ?? m.id)
                : null,
            watchedContentType: m.type,
            onOpen: () => _openItem(m, _sections[i].addon),
          ),
      ],
    );
  }

  SpotlightCard _spotlightContinueWatchingCard(
    _CwRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) {
    final wideArt = _wideArtUrl(item);
    final episodeArt = item.type == 'series'
        ? row.episodeArtworkOf(item)
        : null;
    return SpotlightCard(
      image: _homeLandscapeCards ? (episodeArt ?? wideArt) : item.poster,
      // An episode still is best-effort. If it fails at image-decode time (not
      // only during lookup), fall back to the same show art CW used before.
      fallbackImage: _homeLandscapeCards
          ? (episodeArt != null ? wideArt : item.poster)
          : null,
      title: item.name,
      subtitle: continueWatchingCardSubtitle(
        episodeLabel: row.episodeOf(item),
        minutesLeft: row.remainingMinutesOf(item),
      ),
      rating: item.imdbRating,
      shape: _homeLandscapeCards
          ? SpotlightCardShape.wide
          : SpotlightCardShape.poster,
      // `_CwRow` publishes a 0..1 fraction; the card draws 0..100.
      progress: (row.progressOf(item) ?? 0) * 100,
      onOpen: () => row.onOpen(item),
      // Spotlight used to bypass the shared CW hold handler and Quick Play
      // unconditionally. Route through the same preference-aware menu path as
      // every other Home layout so disabled means Play/Remove and enabled
      // means immediate playback on both touch and DPAD.
      onOptions: () => _openCwCardMenu(row, item, cwIndex, col),
    );
  }

  /// A favourites rail as Spotlight cards.
  ///
  /// The four kinds are NOT the same shape. A playlist is a container rather
  /// than a title, so it keeps the poster it was given (or its override) and
  /// says how many items it holds. The three channel kinds carry LOGOS — wide,
  /// frequently transparent marks — which a 2:3 crop cuts in half, so they get
  /// a square tile that contains the art on a plate instead of filling with it.
  SpotlightShelf _spotlightFavShelf(_FavRowRef ref, {String? id}) {
    final nodes = _favNodesFor(ref);
    if (ref.isIptvList) {
      final row = _iptvListRows[ref.list];
      return SpotlightShelf(
        id: id,
        title: row.title,
        nodes: nodes,
        items: [
          for (final ch in row.channels)
            SpotlightCard(
              image: ch.logoUrl,
              title: ch.name,
              subtitle: 'LIVE',
              shape: _homeLandscapeCards
                  ? SpotlightCardShape.wideChannel
                  : SpotlightCardShape.channel,
              onOpen: () => _playIptvListChannel(ch),
              previewBuilder: ch.isLive
                  ? (_) => SpotlightIptvCardPreview(
                      channel: ch,
                      ambientVolume: _heroTrailerVolume,
                    )
                  : null,
            ),
        ],
      );
    }
    switch (ref.kind) {
      case _FavKind.watchlistMovies:
      case _FavKind.watchlistSeries:
        final isMovies = ref.kind == _FavKind.watchlistMovies;
        final items = isMovies ? _watchlistMovieItems : _watchlistSeriesItems;
        return SpotlightShelf(
          id: id,
          title: isMovies ? 'Watchlist Movies' : 'Watchlist Series',
          nodes: nodes,
          // Same rule as the catalog rows off TV: pure poster cards in
          // portrait, captions back for landscape backdrops. The subtitle
          // stays on the card because TV still renders overlay captions
          // (this flag is non-TV only) — dropping it here would have
          // changed TV cards too.
          captions: _homeLandscapeCards,
          items: [
            for (final item in items)
              SpotlightCard(
                image: _homeLandscapeCards ? _wideArtUrl(item) : item.poster,
                fallbackImage: _homeLandscapeCards ? item.poster : null,
                title: item.name,
                rating: item.imdbRating,
                subtitle: isMovies ? 'MOVIE' : 'SERIES',
                shape: _homeLandscapeCards
                    ? SpotlightCardShape.wide
                    : SpotlightCardShape.poster,
                watchedImdbId: item.effectiveImdbId ?? item.id,
                watchedContentType: item.type,
                onOpen: () => _openMyWatchlistItem(item),
              ),
          ],
        );
      case _FavKind.playlist:
        return SpotlightShelf(
          id: id,
          title: 'Playlists',
          nodes: nodes,
          items: [
            for (final item in _playlistItems)
              SpotlightCard(
                image: item['posterUrl'] as String?,
                title: (item['title'] as String?) ?? 'Unknown',
                progress: _playlistProgressFor(item),
                onOpen: () => _onPlaylistItemTap(item),
              ),
          ],
        );
      case _FavKind.iptv:
        return SpotlightShelf(
          id: id,
          title: 'IPTV Favourites',
          nodes: nodes,
          items: [
            for (final ch in _iptvFavChannels)
              SpotlightCard(
                image: ch.logoUrl,
                title: ch.name,
                subtitle: 'LIVE',
                shape: _homeLandscapeCards
                    ? SpotlightCardShape.wideChannel
                    : SpotlightCardShape.channel,
                onOpen: () => _playIptvChannel(ch),
                previewBuilder: ch.isLive
                    ? (_) => SpotlightIptvCardPreview(
                        channel: ch,
                        ambientVolume: _heroTrailerVolume,
                      )
                    : null,
              ),
          ],
        );
      case _FavKind.debrify:
        return SpotlightShelf(
          id: id,
          title: 'Debrify TV',
          nodes: nodes,
          items: [
            for (final ch in _tvFavChannels)
              SpotlightCard(
                title: ch.name,
                subtitle: 'CHANNEL ${ch.channelNumber}',
                shape: _homeLandscapeCards
                    ? SpotlightCardShape.wideChannel
                    : SpotlightCardShape.channel,
                onOpen: () => _playChannel(ch),
              ),
          ],
        );
      case _FavKind.stremio:
        return SpotlightShelf(
          id: id,
          title: 'Stremio TV',
          nodes: nodes,
          items: [
            for (final ch in _stvFavChannels)
              SpotlightCard(
                image: _stvFavArt(ch, landscape: _homeLandscapeCards),
                fallbackImage: _homeLandscapeCards
                    ? _stvNowPlaying(ch)?.item.poster
                    : null,
                title: ch.displayName,
                subtitle: 'STREMIO TV',
                // The now-playing TITLE's rating — the card wears title art,
                // so the rating follows the title, not the channel.
                rating: _stvNowPlaying(ch)?.item.imdbRating,
                // Title art, not a channel logo: follow the user's Spotlight
                // title-card orientation instead of containing it as a square
                // station mark.
                shape: _homeLandscapeCards
                    ? SpotlightCardShape.wide
                    : SpotlightCardShape.poster,
                onOpen: () => _playStremioTvChannel(ch),
              ),
          ],
        );
    }
  }

  /// A Stremio TV favourite's card art: the channel's rotating now-playing
  /// poster — the same resolution the classic and Canvas rails use. Spotlight
  /// landscape mode instead chooses the title's best wide art. Null
  /// (placeholder) until the channel's items load.
  String? _stvFavArt(StremioTvChannel ch, {bool landscape = false}) {
    final item = _stvNowPlaying(ch)?.item;
    if (item == null) return null;
    if (landscape) return _wideArtUrl(item);
    return _firstNonEmpty(item.poster, item.background);
  }

  Widget _buildSpotlightBoard() {
    // Snapshot row descriptors with the shelf list: async inserts must not
    // make a callback page a different catalog than the shelf it came from.
    final rails = _canvasRails;
    return SpotlightBoard(
      key: _spotlightKey,
      hero: _spotlightHero,
      sections: _spotlightShelves,
      heroNode: _spotlightHeroNode,
      heroAddon: _spotlightHeroSection?.addon,
      dpad: widget.isTelevision,
      showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
      onHeroOpen: _openItem,
      onLoadMoreRow: (row) {
        if (row < 0 || row >= rails.length) return;
        final catalogRow = rails[row].sectionIndex;
        if (catalogRow != null) unawaited(_loadMoreRow(catalogRow));
      },
      onLoadMoreShelves: _loadMoreBoard,
      // The board owns the CADENCE; the resolve and the video stay here.
      //
      // Every other entry into `_scheduleHeroTrailer` is still excluded for
      // this style — init, section loads, focus changes, `_applyHero`, route
      // return, sidebar return — so the board's clock is the single owner and
      // the two cannot start a trailer under different titles.
      // NOT && !_heroTrailerSuppressed: suppression is enforced inside
      // _scheduleHeroTrailer. Folding it in here disarms the board's dwell
      // clock entirely — and the dwell is the only event that can LIFT the
      // suppression when the reel moves to a new title, so one post-playback
      // rebuild would have frozen trailers until the tab was recreated.
      trailersEnabled: _heroTrailerEnabled,
      onDwell: (item) => _scheduleHeroTrailer(item, fromSpotlight: true),
      onTrailerStop: _clearHeroTrailer,
      trailer: _heroTrailerRenderable
          ? _HeroTrailerLayer(
              trailer: _heroTrailer,
              isTelevision: widget.isTelevision,
              heroHeight: 540,
              // Full bleed on every form factor — a letterboxed 16:9 band
              // was tried on the phone and read as a TV set embedded in the
              // artwork (user call). The portrait cover-crop is the design;
              // it gets its sharpness from the 1080p resolve and the
              // medium-filter texture sampling instead.
              fullBleed: true,
              volume: _heroTrailerVolume,
              loading: _heroTrailerLoading,
              onPlayingChanged: _onHeroTrailerPlaying,
              takeover: _heroTrailerTakeover,
            )
          : null,
      // TV only: the glass stage the publish feeds exists behind the TV
      // sidebar rail. Off-TV there is no consumer, and writing the shared
      // notifiers from a phone Home would leave stale art for the next TV
      // session of a hot-restarted debug run.
      onAmbient: widget.isTelevision
          ? (art, tint) {
              if (!mounted) return;
              MainPageBridge.tvAmbientArt.value = art;
              MainPageBridge.tvHeroTint.value = tint;
            }
          : null,
    );
  }

  /// The displayed Canvas rail's best focus target (sidebar hand-off, tab
  /// re-entry, auto-focus and dead-focus reclaim all route through this via
  /// [_topBoardFocusNode]).
  FocusNode? _stageFocusTarget() {
    // Spotlight owns its own cursor — the hero is a focusable row, which the
    // rail-based resolution below cannot describe.
    if (_homeStyleEffective == 'spotlight') {
      return _spotlightKey.currentState?.focusTarget() ?? _spotlightHeroNode;
    }
    // Tonight parks focus in its vertical queue until the user walks down
    // into the rail zone; the rail resolution below is only right for the
    // rail zone.
    if (_homeStyleEffective == 'tonight' && _tonightZoneIsQueue) {
      final queue = _tonightQueue;
      if (queue.isNotEmpty) {
        final e = queue[_resolveTonightQueueIndex(queue)];
        return _nearestMountedNode(e.rail.cw!.nodes, e.col);
      }
    }
    final rails = _stageRails;
    if (rails.isEmpty) return null;
    var index = _resolveCanvasRailIndex(rails);
    // ATRIUM shows TWO rails at once, and focus may be in the lower one —
    // which is NOT _canvasRailKey (that identifies the window's top rail).
    // Sidebar re-entry, auto-focus and dead-focus reclaim all come through
    // here, so without this they would teleport the user up a row.
    if (_homeStyleEffective == 'atrium') {
      final focusedKey = _atriumFocusedRailKey.value;
      if (focusedKey != null) {
        final i = rails.indexWhere((r) => _canvasRailKeyOf(r) == focusedKey);
        // Only honour it while it is still inside the visible window.
        if (i == index || i == index + 1) index = i;
      }
    }
    final rail = rails[index];
    final node = _nearestMountedNode(
      _canvasRailNodes(rail),
      _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
    );
    if (node != null) return node;
    // The remembered row may no longer be RENDERED (Atrium drops to a single
    // row on a short board), so fall back to the active rail rather than
    // handing back null and leaving the board unfocusable.
    final active = rails[_resolveCanvasRailIndex(rails)];
    if (identical(active, rail)) return null;
    return _nearestMountedNode(
      _canvasRailNodes(active),
      _canvasCols[_canvasRailKeyOf(active)] ?? 0,
    );
  }

  /// Every non-empty Home rail in the board's built-in order. Search's
  /// dedicated Lists mode has its own body and never enters this collection.
  /// FocusNode lists are reused from the classic board's per-row lists — only
  /// one view is ever mounted, and reuse keeps node counts synced through
  /// paging for free.
  List<_CanvasRail> get _canonicalCanvasRails {
    final rails = <_CanvasRail>[];
    if (_cwVisible) {
      final cwRows = _cwRows;
      for (var i = 0; i < cwRows.length; i++) {
        if (cwRows[i].items.isEmpty) continue;
        rails.add(_CanvasRail(cw: cwRows[i], cwIndex: i));
      }
    }
    for (final ref in _favRowKinds) {
      if (_canvasFavItemCount(ref) == 0) continue;
      rails.add(_CanvasRail(favKind: ref));
    }
    for (var i = 0; i < _sections.length; i++) {
      if (_sections[i].items.isEmpty || i >= _rowNodes.length) continue;
      rails.add(_CanvasRail(sectionIndex: i));
    }
    return [
      for (final rail in rails)
        if (_stageCollection(rail)?.collection.pinToTop ?? false) rail,
      for (final rail in rails)
        if (!(_stageCollection(rail)?.collection.pinToTop ?? false)) rail,
    ];
  }

  /// The canonical rails, globally sorted by the user's saved row ids.
  List<_CanvasRail> get _canvasRails {
    final rails = _canonicalCanvasRails;
    return _homeRowOrderActive
        ? HomeRowOrder.apply(rails, _effectiveHomeRowOrder, _canvasRailRowId)
        : rails;
  }

  /// Classic renders the same globally ordered rails as every stage layout,
  /// plus focusless Trakt placeholders while that account is loading.
  List<_CanvasRail> get _classicHomeRails {
    var rails = _canonicalCanvasRails;
    if (_traktReserving) {
      final skeletons = <_CanvasRail>[];
      if (!_homeDisabled.contains('trakt:movies')) {
        skeletons.add(const _CanvasRail(traktSkeletonIndex: 0));
      }
      // Merged Trakt renders one combined row, so reserve one slot, not two.
      if (!_cwMergeTrakt && !_homeDisabled.contains('trakt:shows')) {
        skeletons.add(const _CanvasRail(traktSkeletonIndex: 1));
      }
      // In the built-in order placeholders belong after the real CW block and
      // before favourites/sections. Build that canonical sequence first, then
      // let a saved order move the placeholders wherever the user requested.
      rails = HomeRowOrder.insertAfterLeadingRun(
        rails,
        skeletons,
        (rail) => rail.cw != null ||
            (_stageCollection(rail)?.collection.pinToTop ?? false),
      );
    }
    return _homeRowOrderActive
        ? HomeRowOrder.apply(rails, _effectiveHomeRowOrder, _canvasRailRowId)
        : rails;
  }

  String _canvasRailRowId(_CanvasRail rail) {
    if (rail.cw != null) return rail.cw!.rowId;
    if (rail.favKind != null) return _favRowId(rail.favKind!);
    if (rail.traktSkeletonIndex >= 0) {
      return rail.traktSkeletonIndex == 0 ? 'trakt:movies' : 'trakt:shows';
    }
    return _sectionRowId(_sections[rail.sectionIndex!]);
  }

  bool _focusHomeRailAt(int index, int column) {
    final rails = _canvasRails;
    if (index < 0 || index >= rails.length) return false;
    final nodes = _canvasRailNodes(rails[index]);
    if (nodes.isEmpty) return false;
    _requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  /// Classic-board vertical focus by stable row id. The ordered list is
  /// re-resolved on every press because tracker/favourite rows can arrive
  /// asynchronously and catalog batches can insert around the current row.
  void _focusRelativeHomeRail(String rowId, int delta, int column) {
    final rails = _canvasRails;
    final current = rails.indexWhere((rail) => _canvasRailRowId(rail) == rowId);
    if (current < 0) return;
    for (var i = current + delta; i >= 0 && i < rails.length; i += delta) {
      if (_focusHomeRailAt(i, column)) return;
    }
    if (delta < 0) {
      _leaveBoardTop();
      return;
    }
    if (!_boardLoadingMore && _focusCatalogContinuation()) return;
    if (_boardHasMore) _loadMoreBoard();
    _deferDownMove(homeRowId: rowId, column: column);
  }

  // ── TONIGHT zone state ───────────────────────────────────────────────────

  /// Tonight splits focus into two zones stacked vertically: the Continue
  /// Watching QUEUE (a vertical list) above, and the usual horizontal rail
  /// below. UP/DOWN walks the two as one column, so this is simply "which
  /// zone currently owns focus".
  bool _tonightZoneIsQueue = true;

  /// A hold-jump fired: swallow the REST OF THAT HOLD. Without it a single
  /// long press would jump zones and then keep acting on the cell it landed
  /// on — repeats keep arriving, and the new cell never saw the key-down that
  /// started them.
  ///
  /// Latched to the specific key until its key-up rather than to a timer: a
  /// timer both let an uninterrupted hold resume once it expired AND ate a
  /// deliberate tap made inside the window. Other keys are never affected.
  LogicalKeyboardKey? _stageHoldLatchedKey;

  bool _stageHoldSwallow(LogicalKeyboardKey key) => _stageHoldLatchedKey == key;

  /// Perform a zone jump and latch the key. [jump] reports whether it
  /// actually moved focus — a jump that found nothing mounted must NOT latch,
  /// or the rest of the hold is swallowed for a move that never happened.
  void _stageHoldJump(LogicalKeyboardKey key, bool Function() jump) {
    if (_stageHoldSwallow(key)) return;
    if (jump()) _stageHoldLatchedKey = key;
  }

  /// Global observer (registered with the theater handler): releases the hold
  /// latch when the key is let go. Returns false — it never consumes the key.
  /// A fresh key-DOWN of the same key also clears it, so a dropped key-up
  /// (focus change, app backgrounded) can't latch it forever.
  bool _onStageHoldKey(KeyEvent event) {
    final latched = _stageHoldLatchedKey;
    if (latched == null) return false;
    if (event.logicalKey != latched) return false;
    if (event is KeyUpEvent || event is KeyDownEvent) {
      _stageHoldLatchedKey = null;
    }
    return false;
  }

  /// Remembered row within the queue — the INDEX is only a fallback. CW rows
  /// stream in and prepend (Trakt/Simkl land seconds after a cold start), so
  /// the identity below is what actually restores the user's place.
  int _tonightQueueCol = 0;

  /// What the big card should say about whatever currently has focus — the
  /// OK hint in particular, which is 'Resume' only for a part-watched title
  /// and 'Play'/'Open' otherwise. A notifier, so a focus move repaints the
  /// caption alone rather than the board.
  final ValueNotifier<_TonightCardInfo?> _tonightCard =
      ValueNotifier<_TonightCardInfo?>(null);

  /// Identity of the remembered queue row: '<rail key>#<column>'. Resolved
  /// against the rebuilt queue every time, exactly like [_canvasRailKey].
  String? _tonightQueueKey;

  /// The queue: every Continue Watching row flattened to (row, column) pairs
  /// in board order. Nodes come from the CW rows themselves — which is why
  /// [_stageRails] drops CW rails on Tonight (a node may be mounted once).
  List<_TonightQueueEntry> get _tonightQueue {
    final out = <_TonightQueueEntry>[];
    if (!_cwVisible) return out;
    for (final rail in _canvasRails) {
      final cw = rail.cw;
      if (cw == null) continue;
      final n = min(cw.items.length, cw.nodes.length);
      for (var col = 0; col < n; col++) {
        out.add(_TonightQueueEntry(rail: rail, col: col));
      }
    }
    return out;
  }

  /// The rails the ACTIVE layout puts on its rail zone. Identical to
  /// [_canvasRails] everywhere except Tonight, which lifts the Continue
  /// Watching rows out into its own vertical queue — leaving them in both
  /// places would mount the same FocusNodes twice.
  List<_CanvasRail> get _stageRails => _homeStyleEffective == 'tonight'
      ? [
          for (final r in _canvasRails)
            if (r.cw == null) r,
        ]
      : _canvasRails;

  int _canvasFavItemCount(_FavRowRef ref) {
    if (ref.isIptvList) return _iptvListRows[ref.list].channels.length;
    switch (ref.kind) {
      case _FavKind.watchlistMovies:
        return _watchlistMovieItems.length;
      case _FavKind.watchlistSeries:
        return _watchlistSeriesItems.length;
      case _FavKind.iptv:
        return _iptvFavChannels.length;
      case _FavKind.debrify:
        return _tvFavChannels.length;
      case _FavKind.stremio:
        return _stvFavChannels.length;
      case _FavKind.playlist:
        return _playlistItems.length;
    }
  }

  String _canvasFavTitle(_FavRowRef ref) {
    if (ref.isIptvList) return _iptvListRows[ref.list].title;
    switch (ref.kind) {
      case _FavKind.watchlistMovies:
        return 'Watchlist Movies';
      case _FavKind.watchlistSeries:
        return 'Watchlist Series';
      case _FavKind.iptv:
        return 'IPTV Favorites';
      case _FavKind.debrify:
        return 'Debrify TV';
      case _FavKind.stremio:
        return 'Stremio TV';
      case _FavKind.playlist:
        return 'Playlist';
    }
  }

  String _canvasRailTitle(_CanvasRail rail) {
    if (rail.cw != null) return rail.cw!.title;
    if (rail.favKind != null) return _canvasFavTitle(rail.favKind!);
    return _sections[rail.sectionIndex!].title;
  }

  List<StremioMeta> _canvasRailItems(_CanvasRail rail) =>
      rail.cw?.items ?? _sections[rail.sectionIndex!].items;

  List<FocusNode> _canvasRailNodes(_CanvasRail rail) {
    if (rail.cw != null) return rail.cw!.nodes;
    if (rail.favKind != null) return _favNodesFor(rail.favKind!);
    return _rowNodes[rail.sectionIndex!];
  }

  /// UP/DOWN on the shelf: swap which rail the shelf shows — the screen never
  /// scrolls. DOWN past the last loaded rail pulls the next catalog batch;
  /// the new rail becomes reachable when it lands.
  void _stageSwitchRail(int delta) {
    final rails = _stageRails;
    if (rails.isEmpty) return;
    final current = _resolveCanvasRailIndex(rails);
    final next = (current + delta).clamp(0, rails.length - 1);
    if (next == current) {
      if (delta > 0 && !_boardLoadingMore && _focusCatalogContinuation()) {
        return;
      }
      if (delta > 0 && _boardHasMore) {
        // Remember the move so it COMPLETES when the batch lands — otherwise
        // the keypress is silently eaten and the user has to press again.
        _deferStageAdvance(_canvasRailKeyOf(rails[current]));
        _loadMoreBoard();
      } else if (delta > 0) {
        _focusCatalogContinuation();
      }
      return;
    }
    final nextKey = _canvasRailKeyOf(rails[next]);
    // A first visit starts the rail at its BEGINNING — inheriting the column
    // you came from (classic's carry-over) opened rails mid-list here, which
    // read as broken with a fresh shelf. Revisits still restore the rail's
    // own remembered column (written by onFocused).
    setState(() {
      _canvasRailKey = nextKey;
      // Atrium's window is [active, active+1] and its focused-row marker is
      // what _stageFocusTarget honours. Moving the window must re-anchor it,
      // or UP from the top row resolves to the row you just left (it is the
      // new window's BOTTOM row) and focus appears not to move.
      if (_homeStyleEffective == 'atrium') {
        _atriumFocusedRailKey.value = nextKey;
      }
    });
    _stagePostFrameFocus(_stageFocusTarget);
  }

  /// The CANVAS home: full-bleed stage (idle art → ambient trailer via the
  /// same underlay engine, whose hole simply gets the whole canvas) with ONE
  /// shelf of large posters at the bottom and quiet rail tabs above it. No
  /// vertical scrolling, nothing clips at a fold, no row headers.
  Widget _buildCanvasBoard() {
    final view = _resolveStageRail();
    if (view == null) {
      // First batch still streaming (or every loaded row is empty) — hold
      // the brand stage rather than an empty black canvas.
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    final rails = view.rails;
    final railIndex = view.index;
    final rail = view.rail;
    final railKey = view.key;
    final bool favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;

    _seedStageFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final double cardH = (boardH * 0.30).clamp(150.0, 220.0);
        // Title cards follow the Home Cards orientation (full shelf height
        // either way — the same grammar as Promenade's strip); favourites
        // keep their portrait cell whatever the setting says.
        final cardW = cardH * _stageCardAspect(rail);
        final favCardW = cardH * 2 / 3;
        // ONE height for the whole bottom column, measured bottom-up, so the
        // identity block above can reserve exactly what the tabs and shelf
        // actually occupy — at any text scale, and whatever the shelf box
        // grows to next.
        final shelfBoxH =
            cardH + _homeArtPosterCaptionBand + _kCanvasShelfSlack;
        final shelfColumnH =
            _kCanvasShelfTail +
            shelfBoxH +
            _kCanvasTabsGap +
            _canvasTabsHeight(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art. Sits BELOW the punch hole,
            // so the video replaces it in place when the trailer starts.
            // While a favourites cell has focus, the favourite's own art
            // overrides the hero pipeline's.
            _CanvasArtLayer(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              cacheWidth: _tvHeroArtworkCacheWidth,
              cacheHeight: _tvHeroArtworkCacheHeight,
            ),
            // Full-bleed ambient trailer: same engine, whole-canvas region.
            if (_heroTrailerActive)
              _HeroTrailerLayer(
                trailer: _heroTrailer,
                isTelevision: widget.isTelevision,
                heroHeight: boardH,
                fullBleed: true,
                volume: _heroTrailerVolume,
                loading: _heroTrailerLoading,
                onPlayingChanged: _onHeroTrailerPlaying,
                takeover: _heroTrailerTakeover,
              ),
            // A focused IPTV favourite's live feed, full-bleed in the SAME
            // region — above the catalog trailer layer so it simply wins
            // whenever a channel has focus (shrinks to nothing otherwise),
            // exactly like the classic board's boxed version.
            if (_heroTrailerActive)
              _HeroLiveLayer(
                channel: _heroLiveChannel,
                streamUrl: _heroLiveUrl,
                heroHeight: boardH,
                fullBleed: true,
                volume: _heroTrailerVolume,
                onPlayingChanged: _onHeroTrailerPlaying,
                onPlaybackFailed: _onHeroLivePlaybackFailed,
              ),
            // ONE scrim set painted above art AND video — identical in both
            // states so trailer start never swaps the lighting. Plain
            // gradient draws over the hole: the proven feather pattern. In
            // theater the BOTTOM ramp fades with the shelf it exists for.
            IgnorePointer(child: _CanvasScrims(theater: _canvasTheater)),
            // Identity (logo art + meta line), settle-driven like the hero.
            // THEATER: the logo glides to the top-left and shrinks — Netflix
            // billboard style — so the clean full-bleed video still carries a
            // quiet signature. Meta + synopsis are already faded by then
            // (they go with trailerShowing, before the dwell), so what
            // travels is effectively just the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: _canvasTheater ? 36 : 0,
                    bottom: _canvasTheater
                        ? 0
                        : shelfColumnH + _kCanvasIdentityGap,
                  ),
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: _canvasTheater
                        ? Alignment.topLeft
                        : Alignment.bottomLeft,
                    duration: _canvasTheater
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedScale(
                      scale: _canvasTheater ? 0.7 : 1.0,
                      alignment: Alignment.topLeft,
                      duration: _canvasTheater
                          ? const Duration(milliseconds: 900)
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      // Favourites focus: the favourite's own name replaces
                      // the hero identity (favourites aren't StremioMeta, so
                      // the logo/meta pipeline has nothing true to say).
                      // Notifier-driven, so a fav scrub repaints only this.
                      child: ValueListenableBuilder<_CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? _StageFavIdentity(fav: fav)
                            : _CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail tabs + the shelf. Theater recede: slide down a touch +
            // fade out (house cadence — slow lights-down, instant lights-up).
            // Opacity/slide only, cells stay MOUNTED: focus survives, and the
            // wake keypress still performs its normal move.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _canvasTheater ? const Offset(0, 0.12) : Offset.zero,
                duration: _canvasTheater
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _canvasTheater ? 0.0 : 1.0,
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kCanvasTabsGap,
                        ),
                        child: _canvasTabs(rails, railIndex),
                      ),
                      SizedBox(
                        // ONE height for every rail (favourites cells carry a
                        // caption band; meta cells centre in the extra slack):
                        // a per-rail height made the tabs row jump ~45px on
                        // every fav↔meta switch and squeezed the outgoing fav
                        // list into a RenderFlex overflow mid-crossfade.
                        // Whatever this becomes, [shelfColumnH] measures it — the
                        // identity block's clearance is derived, never guessed.
                        height: shelfBoxH,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: favRail
                              ? ListView.builder(
                                  // Keyed by rail IDENTITY, like the meta shelf.
                                  key: ValueKey('canvas-rail-$railKey'),
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  cacheExtent: 400,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                  ),
                                  itemCount: _canvasFavItemCount(rail.favKind!),
                                  itemBuilder: (context, col) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    // Centred like the meta cells: splits the
                                    // vertical slack so the focus scale's lift
                                    // isn't clipped at the viewport's top edge.
                                    child: Center(
                                      child: SizedBox(
                                        width: favCardW,
                                        child: _canvasFavCell(
                                          rail.favKind!,
                                          railKey,
                                          col,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  // Keyed by rail IDENTITY: insertions above the active
                                  // rail must never read as a content swap.
                                  key: ValueKey('canvas-rail-$railKey'),
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.hardEdge,
                                  cacheExtent: 400,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 48,
                                  ),
                                  itemCount: items.length,
                                  itemBuilder: (context, col) {
                                    final item = items[col];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: cardW,
                                          height: cardH,
                                          child: _BoardCell(
                                            item: item,
                                            isTelevision: true,
                                            focusNode: nodes[col],
                                            column: col,
                                            rowNodes: nodes,
                                            hasBoundSource: _isBound(item),
                                            // Canvas focus grammar: white ring (the
                                            // violet stays with classic chrome).
                                            ringColor: Colors.white,
                                            aspectRatio: _stageCardAspect(rail),
                                            artUrl: _stageCardArt(rail, item),
                                            focusArtUrl: _stageCollection(rail)?.focusArtOf(item),
                                            showTitleOverlay: !(_stageCollection(rail)?.folderOf(item)?.hideTitle ?? false),
                                            progress: rail.cw?.progressOf(item),
                                            episodeLabel: rail.cw?.episodeOf(
                                              item,
                                            ),
                                            onQuickPlay:
                                                rail.cw != null || _pikpakOnly
                                                ? null
                                                : () => _sectionQuickPlay(
                                                    _sections[rail
                                                        .sectionIndex!],
                                                    item,
                                                  ),
                                            onLongPress: rail.cw == null
                                                ? null
                                                : () => _openCwCardMenu(
                                                    rail.cw!,
                                                    item,
                                                    rail.cwIndex,
                                                    col,
                                                  ),
                                            onFocused: () {
                                              _setHero(item);
                                              _canvasCols[railKey] = col;
                                            },
                                            onUp: () => _stageSwitchRail(-1),
                                            onDown: () => _stageSwitchRail(1),
                                            onOpen: () {
                                              if (rail.cw != null) {
                                                rail.cw!.onOpen(item);
                                              } else {
                                                _sectionOpenItem(
                                                  _sections[rail.sectionIndex!],
                                                  item,
                                                );
                                              }
                                            },
                                            onNearEnd: rail.sectionIndex == null
                                                ? null
                                                : () => _loadMoreRow(
                                                    rail.sectionIndex!,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: _kCanvasShelfTail),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// A post-frame focus request that is only honoured if BOTH the layout and
  /// the stage generation are unchanged when the frame lands. Without this a
  /// callback posted by one layout can grab focus inside the next one (style
  /// switches and board reseeds both bump the generation).
  void _stagePostFrameFocus(FocusNode? Function() resolve) {
    final style = _homeStyleEffective;
    final gen = _stageGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_homeStyleEffective != style || _stageGeneration != gen) return;
      resolve()?.requestFocus();
    });
  }

  /// A DOWN that ran off the end of the rail list asked for another batch.
  /// Called when one lands: completes the move only if the user is STILL on
  /// the rail they pressed DOWN from, and the request hasn't gone stale — a
  /// late batch must never yank focus out of wherever they went instead.
  void _maybeCompleteStageAdvance() {
    final key = _pendingStageAdvanceKey;
    final at = _pendingStageAdvanceAt;
    final fillLower = _pendingStageAdvanceFillsLower;
    final origin = _pendingStageOrigin;
    if (key == null || at == null) return;
    _pendingStageAdvanceKey = null;
    _pendingStageAdvanceAt = null;
    _pendingStageAdvanceFillsLower = false;
    _pendingStageOrigin = null;
    if (!_stageDeferralStillValid(at, origin)) return;
    final rails = _stageRails;
    final i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
    if (i < 0 || i + 1 >= rails.length) return;
    // Still where the key was pressed? On Atrium that means the focused ROW,
    // everywhere else the active rail.
    final whereNow = _homeStyleEffective == 'atrium'
        ? (_atriumFocusedRailKey.value ?? _canvasRailKey)
        : _canvasRailKey;
    if (whereNow != key) return;
    if (fillLower) {
      // Atrium had only a top row: the window stays put and focus drops into
      // the row that just landed beneath it.
      _stagePostFrameFocus(() {
        if (!identical(FocusManager.instance.primaryFocus, origin)) return null;
        final now = _stageRails;
        final at = now.indexWhere((r) => _canvasRailKeyOf(r) == key);
        if (at < 0 || at + 1 >= now.length) return null;
        final rail = now[at + 1];
        _atriumFocusedRailKey.value = _canvasRailKeyOf(rail);
        return _nearestMountedNode(
          _canvasRailNodes(rail),
          _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
        );
      });
      return;
    }
    if (_homeStyleEffective == 'atrium') {
      // Atrium pressed DOWN from the window's BOTTOM row; its own advance
      // re-resolves the window and lands focus on the new bottom row.
      _atriumAdvance(origin: origin);
      return;
    }
    setState(() => _canvasRailKey = _canvasRailKeyOf(rails[i + 1]));
    _stagePostFrameFocus(
      () => identical(FocusManager.instance.primaryFocus, origin)
          ? _stageFocusTarget()
          : null,
    );
  }

  /// A rail strip reserves ONE box height for every rail kind (invariant: a
  /// per-kind height bounces the layout on every fav↔catalog switch). The two
  /// kinds FILL it differently rather than one wasting the other's space: a
  /// catalog poster is the full box, a favourite's poster is the box minus its
  /// caption band, so both end exactly on the box's bottom edge.
  /// TITLE cards follow the Home Cards orientation setting; everything else
  /// (favourites, channels, playlists) keeps its own fixed shape.
  double get _titleCardAspect => _homeLandscapeCards ? 16 / 9 : 2 / 3;

  /// The art for a title card under the current orientation. Null keeps the
  /// cell's own default (the 2:3 poster) — only landscape needs a derived
  /// wide still.
  String? _titleArtUrl(StremioMeta item) =>
      _homeLandscapeCards ? _wideArtUrl(item) : null;

  HomeCollectionSection? _stageCollection(_CanvasRail rail) {
    final index = rail.sectionIndex;
    if (index == null) return null;
    final section = _sections[index];
    return section is HomeCollectionSection ? section : null;
  }

  double _stageCardAspect(_CanvasRail rail, {double? fallback}) =>
      _stageCollection(rail)?.tileAspectRatio ?? fallback ?? _titleCardAspect;

  String? _stageCardArt(_CanvasRail rail, StremioMeta item, {bool wide = false}) =>
      _stageCollection(rail) != null
          ? item.poster
          : wide
          ? _wideArtUrl(item)
          : _titleArtUrl(item);

  double _stageFavW(BuildContext context, double boxH) {
    // Poster + caption must equal the box EXACTLY. A width floor here would
    // make the poster taller than the space left by a scaled caption and
    // overflow the row — so the art simply gets whatever is left (never
    // below a hairline, so the cell is still hit-testable).
    final art = boxH - _homeArtPosterCaptionBand;
    return (art < 16 ? 16.0 : art) * 2 / 3;
  }

  /// The box height a rail strip may actually use: the layout's preference,
  /// but never less than a favourite cell needs at the CURRENT text scale
  /// (its two-line caption grows with accessibility settings, and a fixed box
  /// would clip it), and never more than [maxH].
  double _stageRailBoxH(
    BuildContext context,
    double preferred, {
    required double maxH,
  }) {
    final floor = _homeArtPosterCaptionBand + _kStageMinPosterH;
    final lo = min(floor, maxH);
    return preferred.clamp(lo, max(lo, maxH));
  }

  /// One-shot: hand entry focus to the active rail the first time a stage
  /// board builds. Shared by every stage layout — the target resolution
  /// ([_stageFocusTarget]) already knows which zone owns focus.
  void _seedStageFocusOnce() {
    if (_canvasFocusSeeded) return;
    _canvasFocusSeeded = true;
    _stagePostFrameFocus(() {
      // Don't yank if focus already landed somewhere real (sidebar, etc).
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return null;
      return _stageFocusTarget();
    });
  }

  /// Every stage board resolves the same four things before painting: the
  /// rails, which one is active, its identity key (persisted so a rail
  /// streaming in above it can't swap the content under the user) and its
  /// nodes. Null means "nothing to show yet" — the caller holds the brand
  /// stage.
  _StageRailView? _resolveStageRail() {
    final rails = _stageRails;
    if (rails.isEmpty) return null;
    final index = _resolveCanvasRailIndex(rails);
    final rail = rails[index];
    final key = _canvasRailKeyOf(rail);
    // LOCK ONTO what we actually rendered (plain bookkeeping, no setState):
    // the first build leaves the key null and a vanished key falls back to
    // index 0 — in both cases an unpersisted identity would let a CW rail
    // prepending seconds later silently swap the shelf under the user.
    _canvasRailKey = key;
    return _StageRailView(
      rails: rails,
      index: index,
      rail: rail,
      key: key,
      items: rail.favKind != null
          ? const <StremioMeta>[]
          : _canvasRailItems(rail),
      nodes: _canvasRailNodes(rail),
    );
  }

  // ── PROMENADE view ───────────────────────────────────────────────────────

  /// PROMENADE: Canvas's stage, symmetric. The identity sits centred in the
  /// lower third and the rail becomes a CENTRE-LOCKED strip — the focused
  /// cell is pinned to the middle of the board and the strip travels under
  /// it. Centre-lock is free: board cards already
  /// `ensureVisible(alignment: 0.5)`; the half-viewport pads below simply let
  /// the FIRST and LAST cell reach the middle too, which a plain list can't.
  Widget _buildPromenadeBoard() {
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    _seedStageFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        // ONE box height for every rail kind; the kinds fill it differently
        // (see [_stageFavW]) so neither wastes the other's space.
        final double stripBoxH = _stageRailBoxH(
          context,
          boardH * 0.27,
          maxH: boardH * 0.42,
        );
        final double cellW = favRail
            ? _stageFavW(context, stripBoxH)
            : stripBoxH * _stageCardAspect(rail, fallback: 16 / 9);
        // Measured bottom-up, exactly like Canvas's shelfColumnH, so the
        // identity's clearance is DERIVED and can never drift into the strip.
        final columnH =
            _kPromStripTail +
            stripBoxH +
            _kPromLabelGap +
            _promenadeLabelHeight(context);
        // Half-viewport pads: without them the list clamps at its ends and
        // the first/last cell can never reach the centre lock.
        final double sidePad = ((boardW - cellW) / 2).clamp(0.0, boardW / 2);
        final itemCount = favRail
            ? _canvasFavItemCount(rail.favKind!)
            : items.length;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Stage floor + full-bleed key art, BELOW the punch hole so the
            // video replaces it in place when the trailer starts.
            _CanvasArtLayer(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              cacheWidth: _tvHeroArtworkCacheWidth,
              cacheHeight: _tvHeroArtworkCacheHeight,
            ),
            if (_heroTrailerActive)
              _HeroTrailerLayer(
                trailer: _heroTrailer,
                isTelevision: widget.isTelevision,
                heroHeight: boardH,
                fullBleed: true,
                volume: _heroTrailerVolume,
                loading: _heroTrailerLoading,
                onPlayingChanged: _onHeroTrailerPlaying,
                takeover: _heroTrailerTakeover,
              ),
            if (_heroTrailerActive)
              _HeroLiveLayer(
                channel: _heroLiveChannel,
                streamUrl: _heroLiveUrl,
                heroHeight: boardH,
                fullBleed: true,
                volume: _heroTrailerVolume,
                onPlayingChanged: _onHeroTrailerPlaying,
                onPlaybackFailed: _onHeroLivePlaybackFailed,
              ),
            IgnorePointer(
              child: _CanvasScrims(
                theater: _canvasTheater,
                variant: _StageScrimVariant.centered,
              ),
            ),
            // Centred identity — which glides to the TOP-LEFT in theater, the
            // Netflix billboard move Canvas already makes. A logo parked in
            // the middle of a clean full-screen trailer reads as something
            // left behind; in the corner it reads as a signature. Meta and
            // synopsis have already faded by then (they go with
            // trailerShowing, before the dwell), so what travels is the logo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedPadding(
                  padding: EdgeInsets.only(
                    left: 48,
                    right: 48,
                    top: _canvasTheater ? 36 : 0,
                    bottom: _canvasTheater ? 0 : columnH + _kPromIdentityGap,
                  ),
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedAlign(
                    alignment: _canvasTheater
                        ? Alignment.topLeft
                        : Alignment.bottomCenter,
                    duration: _canvasTheater
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedScale(
                      scale: _canvasTheater ? 0.7 : 1.0,
                      alignment: Alignment.topLeft,
                      duration: _canvasTheater
                          ? const Duration(milliseconds: 900)
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      child: ValueListenableBuilder<_CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? _StageFavIdentity(fav: fav, centered: true)
                            : _CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                                variant: _StageIdentityVariant.centered,
                                maxWidth: boardW - 96,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Rail label + the strip. Theater recede: slide + fade, cells stay
            // MOUNTED so focus survives and the wake keypress still moves.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _canvasTheater ? const Offset(0, 0.12) : Offset.zero,
                duration: _canvasTheater
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _canvasTheater ? 0.0 : 1.0,
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 48,
                          right: 48,
                          bottom: _kPromLabelGap,
                        ),
                        child: _promenadeLabel(view),
                      ),
                      SizedBox(
                        height: stripBoxH,
                        child: ListView.builder(
                          // Keyed by rail IDENTITY: insertions above the
                          // active rail must never read as a content swap.
                          key: ValueKey('prom-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          padding: EdgeInsets.symmetric(horizontal: sidePad),
                          itemCount: itemCount,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: cellW,
                                child: favRail
                                    ? _canvasFavCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: stripBoxH,
                                        child: _promenadeCell(
                                          rail,
                                          railKey,
                                          items,
                                          nodes,
                                          col,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kPromStripTail),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// One wide strip cell — the SAME [_BoardCell] every board uses, in a 16:9
  /// box with derived landscape art, so hold-OK menus, quick-play, paging and
  /// the focus grammar are identical to Canvas's shelf.
  Widget _promenadeCell(
    _CanvasRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
  ) {
    final item = items[col];
    return _BoardCell(
      item: item,
      isTelevision: true,
      focusNode: nodes[col],
      column: col,
      rowNodes: nodes,
      hasBoundSource: _isBound(item),
      ringColor: Colors.white,
      aspectRatio: _stageCardAspect(rail, fallback: 16 / 9),
      artUrl: _stageCardArt(rail, item, wide: true),
      focusArtUrl: _stageCollection(rail)?.focusArtOf(item),
      showTitleOverlay: !(_stageCollection(rail)?.folderOf(item)?.hideTitle ?? false),
      restVeil: _kPromRestVeil,
      progress: rail.cw?.progressOf(item),
      episodeLabel: rail.cw?.episodeOf(item),
      onQuickPlay: rail.cw != null || _pikpakOnly
          ? null
          : () => _sectionQuickPlay(_sections[rail.sectionIndex!], item),
      onLongPress: rail.cw == null
          ? null
          : () => _openCwCardMenu(rail.cw!, item, rail.cwIndex, col),
      onFocused: () {
        _setHero(item);
        _canvasCols[railKey] = col;
      },
      onUp: () => _stageSwitchRail(-1),
      onDown: () => _stageSwitchRail(1),
      onOpen: () {
        if (rail.cw != null) {
          rail.cw!.onOpen(item);
        } else {
          _sectionOpenItem(_sections[rail.sectionIndex!], item);
        }
      },
      onNearEnd: rail.sectionIndex == null
          ? null
          : () => _loadMoreRow(rail.sectionIndex!),
    );
  }

  /// Promenade's centred rail label. The stacked chevron pair is the same
  /// affordance Canvas's tabs carry, and for the same reason: UP/DOWN is what
  /// changes rails, and nothing else on this screen says so.
  Widget _promenadeLabel(
    _StageRailView view, {
    MainAxisAlignment align = MainAxisAlignment.center,
  }) {
    final app = AppThemeScope.of(context);
    final title = _canvasTabTitle(view.rails, view.index);
    return Row(
      mainAxisAlignment: align,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 13,
              color: app.fade(app.core.tx, 0.45),
            ),
            Transform.translate(
              offset: const Offset(0, -5),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: app.fade(app.core.tx, 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _kPromLabelFontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              color: app.fade(app.core.tx, 0.82),
            ),
          ),
        ),
        if (view.rails.length > 1) ...[
          const SizedBox(width: 14),
          // Flexible as well as the title: on a narrow header (Mosaic shares
          // its row with the identity) a rigid counter is what tips the Row
          // into an overflow.
          Flexible(
            child: Text(
              '${view.index + 1}/${view.rails.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _kPromLabelFontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: app.fade(app.core.tx, 0.32),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── ATRIUM view ──────────────────────────────────────────────────────────

  /// Which rail currently owns focus in Atrium's two-row wall — drives the
  /// eyebrow above the identity only, so it is a notifier rather than
  /// setState: crossing between the rows must not rebuild the board.
  final ValueNotifier<String?> _atriumFocusedRailKey = ValueNotifier<String?>(
    null,
  );

  /// Focus the nearest mounted cell of the rail at [index] (its own remembered
  /// column). Both wall rows are mounted, so this always has a target.
  void _atriumFocusRail(int index) {
    final rails = _stageRails;
    if (index < 0 || index >= rails.length) return;
    final rail = rails[index];
    _nearestMountedNode(
      _canvasRailNodes(rail),
      _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
    )?.requestFocus();
  }

  /// DOWN from the BOTTOM row: scroll the two-row window on by one, so the
  /// row you were on becomes the top row and focus lands on the rail below
  /// it. (Plain [_stageSwitchRail] would focus the rail you are already on.)
  void _atriumAdvance({FocusNode? origin}) {
    final rails = _stageRails;
    final cur = _resolveCanvasRailIndex(rails);
    if (cur + 2 >= rails.length) {
      // Nothing below the bottom row yet — pull the next catalog batch and
      // remember the move so it completes when the rail lands.
      if (_boardHasMore) {
        _deferStageAdvance(
          _canvasRailKeyOf(rails[min(cur + 1, rails.length - 1)]),
        );
        _loadMoreBoard();
      }
      return;
    }
    setState(() => _canvasRailKey = _canvasRailKeyOf(rails[cur + 1]));
    _stagePostFrameFocus(() {
      if (_homeStyleEffective != 'atrium') return null;
      // Deferred completions pass the node that pressed DOWN; focus can move
      // during the frame gap, and a late batch must not yank it back.
      if (origin != null &&
          !identical(FocusManager.instance.primaryFocus, origin)) {
        return null;
      }
      // After the shift the window is [cur+1, cur+2]; land on its bottom row.
      final rails = _stageRails;
      final i = _resolveCanvasRailIndex(rails) + 1;
      if (i >= rails.length) return null;
      final rail = rails[i];
      _atriumFocusedRailKey.value = _canvasRailKeyOf(rail);
      return _nearestMountedNode(
        _canvasRailNodes(rail),
        _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
      );
    });
  }

  /// ATRIUM: a hard vertical cut. Left is a flat ink column carrying the
  /// title's dossier and never taking focus; right is the art (and the
  /// trailer, in the same rect — the hole simply follows the layer's box)
  /// with a two-row poster wall standing on its lower half.
  Widget _buildAtriumBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    final rails = view.rails;
    final active = view.index;
    final hasSecondRow = active + 1 < rails.length;

    return LayoutBuilder(
      builder: (context, cons) {
        final boardH = cons.maxHeight;
        final boardW = cons.maxWidth;
        final double splitX = boardW * _kAtriumSplit;
        // ONE row height for every rail kind, filled two ways — reserving the
        // caption band on catalog rows too would cost 45px PER ROW here and
        // push the wall over three quarters of the art.
        //
        // The wall gets a BUDGET (a share of the board) and the row box is
        // derived from what fits inside it, so two scaled labels and a large
        // text scale can shrink the rows instead of running off the board.
        final labelH = _atriumLabelHeight(context);
        // The wall gets a BUDGET. If two rows at the accessibility floor
        // (scaled caption + a recognisable poster) don't fit inside it, show
        // ONE row rather than two clipped ones — the second rail is still one
        // DOWN away.
        final floorH = _homeArtPosterCaptionBand + _kStageMinPosterH;
        double chromeFor(int rows) =>
            rows * (labelH + _kAtriumLabelGap) +
            (rows - 1) * _kAtriumRowGap +
            _kAtriumWallTail;
        final wallBudget = boardH * _kAtriumWallBudget;
        final twoRowsFit =
            hasSecondRow && wallBudget - chromeFor(2) >= floorH * 2;
        final showSecondRow = hasSecondRow && twoRowsFit;
        final rows = showSecondRow ? 2 : 1;
        final budget = wallBudget - chromeFor(rows);
        final rowBoxH = _stageRailBoxH(
          context,
          min(boardH * 0.22, budget / rows),
          maxH: max(budget / rows, floorH),
        );
        final rowUnit = labelH + _kAtriumLabelGap + rowBoxH;
        final wallH =
            (showSecondRow ? rowUnit * 2 + _kAtriumRowGap : rowUnit) +
            _kAtriumWallTail;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ART COLUMN — the right side only. The trailer layer is laid out
            // in the same rect, so the punch hole is exactly this box and the
            // video replaces the art in place with no geometry jump.
            Positioned(
              left: splitX,
              top: 0,
              right: 0,
              bottom: 0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CanvasArtLayer(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    fav: _canvasFavFocus,
                    cacheWidth: _tvHeroArtworkCacheWidth,
                    cacheHeight: _tvHeroArtworkCacheHeight,
                  ),
                  if (_heroTrailerActive)
                    _HeroTrailerLayer(
                      trailer: _heroTrailer,
                      isTelevision: widget.isTelevision,
                      heroHeight: boardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      loading: _heroTrailerLoading,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      takeover: _heroTrailerTakeover,
                    ),
                  if (_heroTrailerActive)
                    _HeroLiveLayer(
                      channel: _heroLiveChannel,
                      streamUrl: _heroLiveUrl,
                      heroHeight: boardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      onPlaybackFailed: _onHeroLivePlaybackFailed,
                    ),
                  const IgnorePointer(
                    child: _CanvasScrims(variant: _StageScrimVariant.seam),
                  ),
                ],
              ),
            ),
            // THE INK PANEL. Opaque: the board's own scaffold turns
            // transparent while a trailer plays (the shell glass stage), so
            // the column has to carry its own ground.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: splitX,
              child: ColoredBox(color: app.home.bg),
            ),
            // The seam itself — one hairline, so the cut reads as deliberate.
            Positioned(
              left: splitX,
              top: 0,
              bottom: 0,
              width: 1,
              child: ColoredBox(color: app.fade(app.core.tx, 0.09)),
            ),
            // THE DOSSIER. Never focusable; vertically centred in the column.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: splitX,
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _kAtriumPanelPad,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<String?>(
                        valueListenable: _atriumFocusedRailKey,
                        builder: (context, key, _) {
                          final i = key == null
                              ? active
                              : rails.indexWhere(
                                  (r) => _canvasRailKeyOf(r) == key,
                                );
                          final title = _canvasTabTitle(
                            rails,
                            i < 0 ? active : i,
                          );
                          return Text(
                            title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.6,
                              color: kCardFocusRing,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      ValueListenableBuilder<_CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? _StageFavIdentity(fav: fav)
                            : _CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                                // Drop the synopsis rather than clip it when
                                // the column is short (small board / large
                                // text scale).
                                variant:
                                    boardH - 64 >=
                                        _stageNarrowIdentityH(context) + 90
                                    ? _StageIdentityVariant.narrow
                                    : _StageIdentityVariant.headline,
                                maxWidth: (splitX - _kAtriumPanelPad * 2).clamp(
                                  120.0,
                                  520.0,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // THE WALL — two rails, stacked, over the art's lower half.
            Positioned(
              left: splitX + _kAtriumWallPad,
              right: _kAtriumWallPad,
              bottom: 0,
              height: wallH,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _atriumRow(
                    rails,
                    active,
                    rowBoxH,
                    isTopRow: true,
                    hasRowBelow: showSecondRow,
                  ),
                  if (showSecondRow) ...[
                    const SizedBox(height: _kAtriumRowGap),
                    _atriumRow(
                      rails,
                      active + 1,
                      rowBoxH,
                      isTopRow: false,
                      hasRowBelow: false,
                    ),
                  ],
                  const SizedBox(height: _kAtriumWallTail),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// One row of Atrium's wall: a quiet rail label over a horizontal strip of
  /// the SAME cells every other board uses.
  Widget _atriumRow(
    List<_CanvasRail> rails,
    int index,
    double rowBoxH, {
    required bool isTopRow,
    required bool hasRowBelow,
  }) {
    final app = AppThemeScope.of(context);
    final rail = rails[index];
    final railKey = _canvasRailKeyOf(rail);
    final favRail = rail.favKind != null;
    final items = favRail ? const <StremioMeta>[] : _canvasRailItems(rail);
    final nodes = _canvasRailNodes(rail);
    final cardW = favRail
        ? _stageFavW(context, rowBoxH)
        : rowBoxH * _stageCardAspect(rail);
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;

    // The window is [active, active+1]. From the top row UP leaves the
    // window; from the bottom row DOWN scrolls it on. Crossing between them
    // is a plain focus request.
    final onUp = isTopRow
        ? () => _stageSwitchRail(-1)
        : () => _atriumFocusRail(index - 1);
    final onDown = isTopRow
        ? (hasRowBelow
              ? () => _atriumFocusRail(index + 1)
              : (rails.length > index + 1
                    // Only one row is drawn: DOWN scrolls the window on.
                    ? () => _stageSwitchRail(1)
                    : () {
                        // No lower row YET — remember the move so focus drops into
                        // it when the batch lands, instead of eating the keypress.
                        if (_boardHasMore) {
                          _deferStageAdvance(railKey, fillsLower: true);
                          _loadMoreBoard();
                        }
                      }))
        : _atriumAdvance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _canvasTabTitle(rails, index).toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _kAtriumLabelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: app.fade(app.core.tx, 0.86),
            shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
          ),
        ),
        const SizedBox(height: _kAtriumLabelGap),
        SizedBox(
          height: rowBoxH,
          child: ListView.builder(
            // Keyed by rail IDENTITY, never index.
            key: ValueKey('atrium-rail-$railKey'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 400,
            itemCount: count,
            itemBuilder: (context, col) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Center(
                child: SizedBox(
                  width: cardW,
                  child: favRail
                      ? _canvasFavCell(
                          rail.favKind!,
                          railKey,
                          col,
                          onUp: () {
                            _atriumFocusedRailKey.value = railKey;
                            onUp();
                          },
                          onDown: () {
                            _atriumFocusedRailKey.value = railKey;
                            onDown();
                          },
                        )
                      : SizedBox(
                          height: rowBoxH,
                          child: _BoardCell(
                            item: items[col],
                            isTelevision: true,
                            focusNode: nodes[col],
                            column: col,
                            rowNodes: nodes,
                            hasBoundSource: _isBound(items[col]),
                            ringColor: Colors.white,
                            aspectRatio: _stageCardAspect(rail),
                            artUrl: _stageCardArt(rail, items[col]),
                            focusArtUrl: _stageCollection(rail)?.focusArtOf(items[col]),
                            showTitleOverlay: !(_stageCollection(rail)?.folderOf(items[col])?.hideTitle ?? false),
                            progress: rail.cw?.progressOf(items[col]),
                            episodeLabel: rail.cw?.episodeOf(items[col]),
                            onQuickPlay: rail.cw != null || _pikpakOnly
                                ? null
                                : () => _sectionQuickPlay(
                                    _sections[rail.sectionIndex!],
                                    items[col],
                                  ),
                            onLongPress: rail.cw == null
                                ? null
                                : () => _openCwCardMenu(
                                    rail.cw!,
                                    items[col],
                                    rail.cwIndex,
                                    col,
                                  ),
                            onFocused: () {
                              _setHero(items[col]);
                              _canvasCols[railKey] = col;
                              _atriumFocusedRailKey.value = railKey;
                            },
                            onUp: onUp,
                            onDown: onDown,
                            onOpen: () {
                              if (rail.cw != null) {
                                rail.cw!.onOpen(items[col]);
                              } else {
                                _sectionOpenItem(
                                  _sections[rail.sectionIndex!],
                                  items[col],
                                );
                              }
                            },
                            onNearEnd: rail.sectionIndex == null
                                ? null
                                : () => _loadMoreRow(rail.sectionIndex!),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── MOSAIC view ──────────────────────────────────────────────────────────

  /// MOSAIC: no hero at all. The active rail becomes a WALL of posters on a
  /// heavily veiled wash of the focused title's art, with the identity moved
  /// to a fixed top band. The cheapest layout on the list: one image, one
  /// flat veil, one grid — and no ambient video (see [_stageWantsAmbient]),
  /// which is why it stays smooth on weak TV hardware.
  Widget _buildMosaicBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;
        // Never negative: a board narrower than its own padding would make
        // every derived width negative and trip a layout assertion.
        final gridW = max(1.0, boardW - _kMosaicPadX * 2);
        // A grid only ever shows ONE rail, and a rail is homogeneous — so
        // the whole wall takes one shape: favourites are always portrait,
        // title cells follow the Home Cards orientation.
        final cellAspect = favRail ? 2 / 3 : _stageCardAspect(rail);
        // Aim for a cell about a third of the board's height — landscape a
        // little shorter, or three backdrops swallow the whole wall — then
        // take whatever whole number of columns actually FITS, as few as one.
        final targetH = boardH * (cellAspect > 1 ? 0.24 : 0.30);
        final targetW = max(1.0, targetH * cellAspect);
        final perRow = (gridW / (targetW + _kMosaicGap)).floor().clamp(1, 8);
        final cellW = max(1.0, (gridW - (perRow - 1) * _kMosaicGap) / perRow);
        // The extent is exactly what this rail's kind needs: the art box,
        // plus the caption band only when the cells actually carry one.
        final extent =
            cellW / cellAspect + (favRail ? _homeArtPosterCaptionBand : 0);

        return Stack(
          fit: StackFit.expand,
          children: [
            _CanvasArtLayer(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              cacheWidth: _tvHeroArtworkCacheWidth,
              cacheHeight: _tvHeroArtworkCacheHeight,
            ),
            // Constant veil. It SNAPS (no tween): a full-screen gradient
            // tween is the single most expensive thing this board could do.
            // While a favourite CHANNEL is previewing, the veil lifts so the
            // live picture is actually visible behind the wall.
            ValueListenableBuilder<IptvChannel?>(
              valueListenable: _heroLiveChannel,
              builder: (context, live, _) => IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: live == null
                        ? const Color(0xDE0D0B1A)
                        : const Color(0x9E0D0B1A),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // The live feed sits ABOVE the veil (a veiled video is a waste of
            // a decoder) with its own lighter scrim for the grid's sake.
            if (_heroTrailerActive)
              _HeroLiveLayer(
                channel: _heroLiveChannel,
                streamUrl: _heroLiveUrl,
                heroHeight: boardH,
                fullBleed: true,
                volume: _heroTrailerVolume,
                onPlayingChanged: _onHeroTrailerPlaying,
                onPlaybackFailed: _onHeroLivePlaybackFailed,
              ),
            ValueListenableBuilder<IptvChannel?>(
              valueListenable: _heroLiveChannel,
              builder: (context, live, _) => IgnorePointer(
                child: live == null
                    ? const SizedBox.shrink()
                    : const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0x8C0D0B1A)),
                        child: SizedBox.expand(),
                      ),
              ),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.85, -0.95),
                    radius: 1.25,
                    colors: [Color(0x2E7B5CFF), Color(0x000D0B1A)],
                    stops: [0.0, 0.62],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kMosaicPadX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: _kMosaicHeadTop),
                  // Identity band: the wall's only chrome. Fixed height so
                  // the grid below it never shifts as titles change.
                  SizedBox(
                    height: _mosaicHeadHeight(context),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<_CanvasFavFocus?>(
                            valueListenable: _canvasFavFocus,
                            builder: (context, fav, _) => Align(
                              alignment: Alignment.bottomLeft,
                              child: fav != null
                                  ? _StageFavIdentity(fav: fav)
                                  : _CanvasIdentity(
                                      item: _heroItem,
                                      enriched: _heroEnriched,
                                      trailerShowing: _heroTrailerShowing,
                                      variant: _StageIdentityVariant.headline,
                                      maxWidth: max(1.0, gridW * 0.5),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        // The windowed TAB STRIP needs the full board width
                        // to show useful context; here it shares a row with
                        // the identity and collapses to a single slot, which
                        // is both cramped and (before the window fix) the
                        // wrong rail. The compact label says the same thing
                        // in a fraction of the width and is correct by
                        // construction: it names the ACTIVE rail and its
                        // position among all of them.
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _promenadeLabel(
                                  view,
                                  align: MainAxisAlignment.end,
                                ),
                                if (view.rails.length > 1) ...[
                                  const SizedBox(height: 8),
                                  // The grid can page for as long as the
                                  // catalog has more, so "walk to the last
                                  // line" is not a way out of it. The hold
                                  // gesture is the way out, and a gesture
                                  // nothing announces may as well not exist.
                                  Text(
                                    'HOLD ▲▼ TO CHANGE ROW',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                      color: app.fade(app.core.tx, 0.34),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _kMosaicHeadGap),
                  Expanded(
                    child: GridView.builder(
                      // Keyed by rail IDENTITY: a rail streaming in above the
                      // active one must never swap the wall's contents.
                      key: ValueKey('mosaic-rail-$railKey'),
                      padding: const EdgeInsets.only(bottom: 24),
                      clipBehavior: Clip.hardEdge,
                      cacheExtent: 600,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: perRow,
                        crossAxisSpacing: _kMosaicGap,
                        mainAxisSpacing: _kMosaicGap,
                        mainAxisExtent: extent,
                      ),
                      itemCount: count,
                      itemBuilder: (context, col) => Center(
                        child: SizedBox(
                          width: cellW,
                          child: _mosaicCell(
                            rail,
                            railKey,
                            items,
                            nodes,
                            col,
                            count,
                            perRow,
                            cellW,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// One wall cell. The grid overrides all four arrows: LEFT hands off to the
  /// sidebar only at a ROW edge (a grid's leftmost cell is not column 0, so
  /// the row grammar would leave the sidebar unreachable from every row but
  /// the first), and UP/DOWN step a whole row before falling through to rail
  /// switching.
  Widget _mosaicCell(
    _CanvasRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
    int count,
    int perRow,
    double cellW,
  ) {
    final atRowStart = col % perRow == 0;
    // Prefetch two rows out, the grid equivalent of the row's six-cards rule.
    void prefetch() {
      if (rail.sectionIndex != null && col >= count - perRow * 2) {
        _loadMoreRow(rail.sectionIndex!);
      }
    }

    void focusAt(int target) {
      if (target < 0 || target >= nodes.length) return;
      nodes[target].requestFocus();
    }

    final onLeft = atRowStart
        ? () => MainPageBridge.focusTvSidebar?.call()
        : () => focusAt(col - 1);
    // RIGHT always advances while a cell exists — wrapping onto the next
    // grid line, the way a wall of posters reads. Stopping at the visual row
    // end would strand every cell past it behind DOWN alone.
    void onRight() {
      prefetch();
      if (col + 1 < nodes.length) {
        focusAt(col + 1);
      } else if (rail.sectionIndex != null) {
        // At the very end with a page in flight: remember the move so it
        // completes when the cells land.
        _deferStageRight(railKey, col);
      }
    }

    final onUp = col - perRow >= 0
        ? () {
            if (_stageHoldSwallow(LogicalKeyboardKey.arrowUp)) return;
            focusAt(col - perRow);
          }
        : () {
            if (_stageHoldSwallow(LogicalKeyboardKey.arrowUp)) return;
            _stageSwitchRail(-1);
          };
    // DOWN steps a whole line, and at the LAST line always leaves for the
    // next rail (prefetching on the way out, so coming back finds more).
    // Consuming DOWN to paginate would trap the user inside a long catalog.
    Null onDown() {
      if (_stageHoldSwallow(LogicalKeyboardKey.arrowDown)) return;
      if (col + perRow < count) {
        prefetch();
        focusAt(col + perRow);
        return;
      }
      prefetch();
      _stageSwitchRail(1);
    }

    // A catalog keeps paging for as long as it has more, so the last grid
    // line is a moving target and DOWN alone can never reliably reach the
    // next rail. HOLDING the key changes rail from anywhere in the grid.
    void onUpHold() => _stageHoldJump(LogicalKeyboardKey.arrowUp, () {
      _stageSwitchRail(-1);
      return true;
    });
    void onDownHold() => _stageHoldJump(LogicalKeyboardKey.arrowDown, () {
      _stageSwitchRail(1);
      return true;
    });

    if (rail.favKind != null) {
      return _canvasFavCell(
        rail.favKind!,
        railKey,
        col,
        onUp: onUp,
        onDown: onDown,
        onLeft: onLeft,
        onRight: onRight,
        onUpHold: onUpHold,
        onDownHold: onDownHold,
      );
    }
    final item = items[col];
    return SizedBox(
      height: cellW / _stageCardAspect(rail),
      child: _BoardCell(
        item: item,
        isTelevision: true,
        focusNode: nodes[col],
        column: col,
        rowNodes: nodes,
        aspectRatio: _stageCardAspect(rail),
        artUrl: _stageCardArt(rail, item),
        focusArtUrl: _stageCollection(rail)?.focusArtOf(item),
        showTitleOverlay: !(_stageCollection(rail)?.folderOf(item)?.hideTitle ?? false),
        hasBoundSource: _isBound(item),
        ringColor: Colors.white,
        progress: rail.cw?.progressOf(item),
        episodeLabel: rail.cw?.episodeOf(item),
        onQuickPlay: rail.cw != null || _pikpakOnly
            ? null
            : () => _sectionQuickPlay(_sections[rail.sectionIndex!], item),
        onLongPress: rail.cw == null
            ? null
            : () => _openCwCardMenu(rail.cw!, item, rail.cwIndex, col),
        onFocused: () {
          _setHero(item);
          _canvasCols[railKey] = col;
        },
        onUp: onUp,
        onDown: onDown,
        onUpHold: onUpHold,
        onDownHold: onDownHold,
        onLeft: onLeft,
        onRight: onRight,
        onOpen: () {
          if (rail.cw != null) {
            rail.cw!.onOpen(item);
          } else {
            _sectionOpenItem(_sections[rail.sectionIndex!], item);
          }
        },
      ),
    );
  }

  // ── DECK view ────────────────────────────────────────────────────────────

  /// DECK: the trailer stops being wallpaper and becomes an OBJECT — a
  /// rounded 16:9 card floating on ink with the next two titles stacked
  /// behind it. The hole follows the card's laid-out rect (Canvas proved that
  /// needs no native work); the rounded corners are four ink wedges painted
  /// ABOVE the layers, because a clip would put a saveLayer over the hole.
  Widget _buildDeckBoard() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    _seedStageFocusOnce();
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;
        // RESERVE THE RAIL FIRST, then let the card have what is left — the
        // other way round, a tall card on a short board silently pushes the
        // rail off the bottom edge.
        final railBoxH = _stageRailBoxH(
          context,
          boardH * 0.24,
          maxH: boardH * 0.34,
        );
        final railZoneH =
            _atriumLabelHeight(context) +
            _kAtriumLabelGap +
            railBoxH +
            _kDeckRailTail;
        final cardTop = boardH * 0.11;
        // The TRUE remainder — never clamped up, which would hand the card
        // height the rail has already been promised.
        var cardH = max(0.0, boardH - cardTop - railZoneH - _kDeckRailGap);
        var cardW = cardH * 16 / 9;
        final maxCardW = boardW * 0.56;
        if (cardW > maxCardW) {
          cardW = maxCardW;
          cardH = cardW * 9 / 16;
        }
        final cardLeft = boardW - cardW - _kDeckCardRightPad;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Constant ground — a single radial, never tweened.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.55, -0.35),
                    radius: 1.15,
                    colors: [
                      Color(0xFF1B1730),
                      Color(0xFF0C0A16),
                      Color(0xFF08070F),
                    ],
                    stops: [0.0, 0.62, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            // The deck's two peek cards — STATIC art of the next two titles
            // on this rail. Never a second video: one engine, one card.
            // Listens to the focused column so the stack DEALS as you move;
            // only this subtree rebuilds.
            ValueListenableBuilder<int>(
              valueListenable: _stageCol,
              builder: (context, focusedCol, _) => Stack(
                children: _deckPeeks(
                  items: items,
                  favRail: favRail,
                  focused: focusedCol,
                  left: cardLeft,
                  top: cardTop,
                  width: cardW,
                  height: cardH,
                ),
              ),
            ),
            // THE CARD.
            Positioned(
              left: cardLeft,
              top: cardTop,
              width: cardW,
              height: cardH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CanvasArtLayer(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    fav: _canvasFavFocus,
                    cacheWidth: _tvHeroArtworkCacheWidth,
                    cacheHeight: _tvHeroArtworkCacheHeight,
                  ),
                  if (_heroTrailerActive)
                    _HeroTrailerLayer(
                      trailer: _heroTrailer,
                      isTelevision: widget.isTelevision,
                      heroHeight: cardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      loading: _heroTrailerLoading,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      takeover: _heroTrailerTakeover,
                    ),
                  if (_heroTrailerActive)
                    _HeroLiveLayer(
                      channel: _heroLiveChannel,
                      streamUrl: _heroLiveUrl,
                      heroHeight: cardH,
                      fullBleed: true,
                      volume: _heroTrailerVolume,
                      onPlayingChanged: _onHeroTrailerPlaying,
                      onPlaybackFailed: _onHeroLivePlaybackFailed,
                    ),
                  // Rounded corners WITHOUT a clip: four ink wedges painted
                  // over the layers. A ClipRRect here would wrap the punch
                  // hole in a saveLayer and break the blend.
                  IgnorePointer(
                    child: CustomPaint(
                      painter: const _CornerWedges(
                        radius: _kDeckCardRadius,
                        color: Color(0xFF0C0A16),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // A hairline inside the wedges reads as the card's edge.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_kDeckCardRadius),
                        border: Border.all(
                          color: app.fade(app.core.tx, 0.10),
                          width: 1,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            // IDENTITY column, left of the card.
            Positioned(
              left: _kDeckPanelPad,
              top: 0,
              width: (cardLeft - _kDeckPanelPad - 40).clamp(140.0, 560.0),
              bottom: railZoneH,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ValueListenableBuilder<_CanvasFavFocus?>(
                    valueListenable: _canvasFavFocus,
                    builder: (context, fav, _) => fav != null
                        ? _StageFavIdentity(fav: fav)
                        : _CanvasIdentity(
                            item: _heroItem,
                            enriched: _heroEnriched,
                            trailerShowing: _heroTrailerShowing,
                            variant:
                                boardH - railZoneH >=
                                    _stageNarrowIdentityH(context)
                                ? _StageIdentityVariant.narrow
                                : _StageIdentityVariant.headline,
                            maxWidth: (cardLeft - _kDeckPanelPad - 40).clamp(
                              140.0,
                              560.0,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            // The rail. Recedes with the lights in theater, cells still
            // MOUNTED so focus survives.
            Positioned(
              left: _kDeckPanelPad,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _canvasTheater ? const Offset(0, 0.12) : Offset.zero,
                duration: _canvasTheater
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _canvasTheater ? 0.0 : 1.0,
                  duration: _canvasTheater
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: _kDeckPanelPad),
                        child: _deckRailLabel(view),
                      ),
                      const SizedBox(height: _kAtriumLabelGap),
                      SizedBox(
                        height: railBoxH,
                        child: ListView.builder(
                          key: ValueKey('deck-rail-$railKey'),
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.hardEdge,
                          cacheExtent: 400,
                          itemCount: count,
                          itemBuilder: (context, col) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Center(
                              child: SizedBox(
                                width: favRail
                                    ? _stageFavW(context, railBoxH)
                                    : railBoxH * _stageCardAspect(rail),
                                child: favRail
                                    ? _canvasFavCell(
                                        rail.favKind!,
                                        railKey,
                                        col,
                                      )
                                    : SizedBox(
                                        height: railBoxH,
                                        child: _stageShelfCell(
                                          rail,
                                          railKey,
                                          items,
                                          nodes,
                                          col,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kDeckRailTail),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Deck's rail label — the same quiet caps as Atrium's rows, with the
  /// stacked chevron pair that says UP/DOWN changes rails.
  Widget _deckRailLabel(_StageRailView view) {
    final app = AppThemeScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 13,
              color: app.fade(app.core.tx, 0.45),
            ),
            Transform.translate(
              offset: const Offset(0, -5),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: app.fade(app.core.tx, 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            _canvasTabTitle(view.rails, view.index).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _kAtriumLabelFontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: app.fade(app.core.tx, 0.86),
            ),
          ),
        ),
      ],
    );
  }

  /// The two cards stacked behind the hero — the NEXT two titles on this
  /// rail, drawn from the focused column so moving along the rail deals them
  /// forward. Static art, no focus, no video.
  List<Widget> _deckPeeks({
    required List<StremioMeta> items,
    required bool favRail,
    required int focused,
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    // Favourites rails have no StremioMeta to draw from — the deck simply
    // shows the single card, which is correct: a favourite has no "next".
    if (favRail || items.isEmpty) return const [];
    final at = focused.clamp(0, items.length - 1);
    final peeks = <Widget>[];
    // Painted far-to-near so the nearer card overlaps the farther one.
    for (final spec in const [
      (step: 2, dx: 0.19, scale: 0.87, alpha: 0.30),
      (step: 1, dx: 0.10, scale: 0.94, alpha: 0.52),
    ]) {
      final i = at + spec.step;
      if (i >= items.length) continue;
      final art = _wideArtUrl(items[i]);
      if (art == null || art.isEmpty) continue;
      peeks.add(
        Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: spec.alpha,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: Offset(spec.dx, 0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: Transform.scale(
                  scale: spec.scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kDeckCardRadius),
                    child: CachedNetworkImage(
                      key: ValueKey('deck-peek-${spec.step}-$art'),
                      imageUrl: art,
                      fit: BoxFit.cover,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return peeks;
  }

  /// The shared poster shelf cell (Canvas grammar: L/R along the rail, U/D
  /// switches rails) — used by Deck and Tonight's bottom strip.
  Widget _stageShelfCell(
    _CanvasRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
    VoidCallback? onFocusedExtra,
  }) {
    final item = items[col];
    return _BoardCell(
      item: item,
      isTelevision: true,
      focusNode: nodes[col],
      column: col,
      rowNodes: nodes,
      hasBoundSource: _isBound(item),
      ringColor: Colors.white,
      aspectRatio: _stageCardAspect(rail),
      artUrl: _stageCardArt(rail, item),
      focusArtUrl: _stageCollection(rail)?.focusArtOf(item),
      showTitleOverlay: !(_stageCollection(rail)?.folderOf(item)?.hideTitle ?? false),
      progress: rail.cw?.progressOf(item),
      episodeLabel: rail.cw?.episodeOf(item),
      onQuickPlay: rail.cw != null || _pikpakOnly
          ? null
          : () => _sectionQuickPlay(_sections[rail.sectionIndex!], item),
      onLongPress: rail.cw == null
          ? null
          : () => _openCwCardMenu(rail.cw!, item, rail.cwIndex, col),
      onFocused: () {
        _setHero(item);
        _canvasCols[railKey] = col;
        _stageCol.value = col;
        onFocusedExtra?.call();
      },
      onUp: onUp ?? () => _stageSwitchRail(-1),
      onDown: onDown ?? () => _stageSwitchRail(1),
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onOpen: () {
        if (rail.cw != null) {
          rail.cw!.onOpen(item);
        } else {
          _sectionOpenItem(_sections[rail.sectionIndex!], item);
        }
      },
      onNearEnd: rail.sectionIndex == null
          ? null
          : () => _loadMoreRow(rail.sectionIndex!),
    );
  }

  // ── TONIGHT view ─────────────────────────────────────────────────────────

  String _tonightQueueKeyOf(_TonightQueueEntry e) =>
      '${_canvasRailKeyOf(e.rail)}#${e.col}';

  /// Where the remembered queue row sits NOW. Identity first (CW rows stream
  /// in and prepend, so a raw index would silently point at another title),
  /// the remembered index only as a fallback.
  int _resolveTonightQueueIndex(List<_TonightQueueEntry> queue) {
    if (queue.isEmpty) return 0;
    final key = _tonightQueueKey;
    if (key != null) {
      final i = queue.indexWhere((e) => _tonightQueueKeyOf(e) == key);
      if (i >= 0) return i;
    }
    return _tonightQueueCol.clamp(0, queue.length - 1);
  }

  bool _tonightFocusQueue() {
    final queue = _tonightQueue;
    if (queue.isEmpty) return false;
    final e = queue[_resolveTonightQueueIndex(queue)];
    var node = _nearestMountedNode(e.rail.cw!.nodes, e.col);
    // The remembered row may have scrolled out of the lazy list's mounted
    // range (CW rows stream in and prepend). Fall back to the FIRST queue
    // entry, which is always built, rather than failing the jump.
    if (node == null && queue.isNotEmpty) {
      final first = queue.first;
      node = _nearestMountedNode(first.rail.cw!.nodes, first.col);
      if (node != null) {
        _tonightQueueCol = 0;
        _tonightQueueKey = _tonightQueueKeyOf(first);
      }
    }
    if (node == null) return false;
    _tonightZoneIsQueue = true;
    node.requestFocus();
    return true;
  }

  bool _tonightFocusRail() {
    final node = () {
      final rails = _stageRails;
      if (rails.isEmpty) return null;
      final rail = rails[_resolveCanvasRailIndex(rails)];
      return _nearestMountedNode(
        _canvasRailNodes(rail),
        _canvasCols[_canvasRailKeyOf(rail)] ?? 0,
      );
    }();
    if (node == null) return false;
    _tonightZoneIsQueue = false;
    node.requestFocus();
    return true;
  }

  /// TONIGHT: resume-first. A large card carries whatever has focus, a
  /// vertical Continue queue stands beside it, and one rail runs underneath.
  /// UP/DOWN walks the two zones as a single column, so the Continue rows sit
  /// "above" the first rail exactly as they read.
  Widget _buildTonightBoard() {
    final queue = _tonightQueue;
    final rails = _stageRails;
    if (queue.isEmpty && rails.isEmpty) {
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    // A zone that no longer exists can't hold focus.
    if (_tonightZoneIsQueue && queue.isEmpty) _tonightZoneIsQueue = false;
    if (!_tonightZoneIsQueue && rails.isEmpty) _tonightZoneIsQueue = true;
    final view = rails.isEmpty ? null : _resolveStageRail();
    _seedStageFocusOnce();

    return LayoutBuilder(
      builder: (context, cons) {
        final boardW = cons.maxWidth;
        final boardH = cons.maxHeight;

        // ── Geometry, derived bottom-up. The rail zone is reserved FIRST,
        // then the main zone takes what is left, then the card and the queue
        // rows are sized from that — so nothing can overlap on a short board.
        final labelH = _atriumLabelHeight(context);
        final double railBoxH = rails.isEmpty
            ? 0
            : _stageRailBoxH(context, boardH * 0.21, maxH: boardH * 0.30);
        final double railZoneH = rails.isEmpty
            ? 0
            : labelH + _kAtriumLabelGap + railBoxH + _kTonightRailTail;
        final headerH = _tonightHeaderHeight(context);
        // The TRUE remainder: clamping this up would re-spend the header's and
        // the rail's reserved height and push them off the board.
        final mainH = max(0.0, boardH - headerH - railZoneH - _kTonightZoneGap);

        var cardH = mainH;
        var cardW = cardH * 16 / 9;
        final maxCardW = boardW * 0.58;
        if (cardW > maxCardW) {
          cardW = maxCardW;
          cardH = cardW * 9 / 16;
        }
        // The queue is the whole point of Tonight, so a board too narrow to
        // hold both shrinks the CARD, never the queue. Only a board narrower
        // than roughly a card floor plus the queue's minimum drops it — and
        // then only when there is a rail left to hold focus.
        if (queue.isNotEmpty) {
          final maxWithQueue =
              boardW -
              _kTonightPadX * 2 -
              _kTonightZoneGap -
              _kTonightQueueMinW;
          if (cardW > maxWithQueue) {
            // Shrink toward the queue, but NEVER widen past what the vertical
            // remainder allows — a wider card is a taller card, and that
            // height belongs to the rail.
            cardW = min(max(maxWithQueue, boardW * 0.34), mainH * 16 / 9);
            cardH = cardW * 9 / 16;
          }
        }
        // How many rows actually FIT — never a fixed four.
        // What a row actually needs at this text scale: two lines of type,
        // the progress bar, their gaps and the row's own padding. Below one
        // of these the queue simply isn't drawn — a 1px row would overflow.
        final rowMinH = _tonightRowMinHeight(context);
        // Zero rows is allowed — but never when the queue is the ONLY thing
        // that could hold focus, or the board would have nothing focusable.
        final minRows = (rails.isEmpty && queue.isNotEmpty) ? 1 : 0;
        final visibleRows = (mainH / (rowMinH + _kTonightRowGap)).floor().clamp(
          minRows,
          4,
        );
        final queueW = (boardW - cardW - _kTonightPadX * 2 - _kTonightZoneGap)
            .clamp(0.0, boardW);
        // Never leave the board with nothing focusable: if the queue can't be
        // drawn and there is no rail either, draw it anyway.
        // With no rail beneath it the queue is the ONLY focusable zone, so
        // it takes the whole board and the card steps aside entirely rather
        // than squeezing it to nothing.
        final queueOnly = rails.isEmpty && queue.isNotEmpty;
        final effQueueW = queueOnly
            ? max(1.0, boardW - _kTonightPadX * 2)
            : queueW;
        final showQueue =
            queue.isNotEmpty &&
            visibleRows > 0 &&
            (queueOnly || effQueueW >= _kTonightQueueMinW) &&
            effQueueW > 0;
        // A zone that isn't on screen must not be the one holding focus.
        if (!showQueue && rails.isNotEmpty) _tonightZoneIsQueue = false;
        // Never taller than the share it actually has: the row height is the
        // MIN of what looks right and what fits.
        final rowH = visibleRows == 0
            ? 0.0
            : min(
                max(
                  (mainH - (visibleRows - 1) * _kTonightRowGap) / visibleRows,
                  rowMinH,
                ),
                _kTonightRowMaxH,
              );
        final queueBoxH = visibleRows == 0
            ? 0.0
            : (rowH * visibleRows + _kTonightRowGap * (visibleRows - 1)).clamp(
                0.0,
                mainH,
              );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Constant ground — one gradient, never tweened.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF161227),
                      Color(0xFF0E0C1B),
                      Color(0xFF0A0813),
                    ],
                    stops: [0.0, 0.46, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            Positioned(
              left: _kTonightPadX,
              right: _kTonightPadX,
              top: 0,
              height: headerH,
              child: _tonightHeader(queue.length),
            ),
            // THE CARD — art, trailer and live all in this rect, so the punch
            // hole is exactly the card. Stood down in queue-only mode, where
            // the queue owns the board.
            if (!(queueOnly && showQueue))
              Positioned(
                left: _kTonightPadX,
                top: headerH,
                width: cardW,
                height: cardH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CanvasArtLayer(
                      item: _heroItem,
                      enriched: _heroEnriched,
                      fav: _canvasFavFocus,
                      cacheWidth: _tvHeroArtworkCacheWidth,
                      cacheHeight: _tvHeroArtworkCacheHeight,
                    ),
                    if (_heroTrailerActive)
                      _HeroTrailerLayer(
                        trailer: _heroTrailer,
                        isTelevision: widget.isTelevision,
                        heroHeight: cardH,
                        fullBleed: true,
                        volume: _heroTrailerVolume,
                        loading: _heroTrailerLoading,
                        onPlayingChanged: _onHeroTrailerPlaying,
                        takeover: _heroTrailerTakeover,
                      ),
                    if (_heroTrailerActive)
                      _HeroLiveLayer(
                        channel: _heroLiveChannel,
                        streamUrl: _heroLiveUrl,
                        heroHeight: cardH,
                        fullBleed: true,
                        volume: _heroTrailerVolume,
                        onPlayingChanged: _onHeroTrailerPlaying,
                        onPlaybackFailed: _onHeroLivePlaybackFailed,
                      ),
                    // Legibility ramp + the caption block, painted ABOVE the
                    // hole (plain draws only).
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xF00A0810),
                              Color(0xA00A0810),
                              Color(0x000A0810),
                            ],
                            stops: [0.0, 0.30, 0.68],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: const _CornerWedges(
                          radius: _kTonightCardRadius,
                          color: Color(0xFF100D1F),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 20,
                      child: IgnorePointer(
                        child: _TonightCardCaption(
                          item: _heroItem,
                          enriched: _heroEnriched,
                          fav: _canvasFavFocus,
                          info: _tonightCard,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // THE QUEUE.
            if (showQueue)
              Positioned(
                left: queueOnly
                    ? _kTonightPadX
                    : _kTonightPadX + cardW + _kTonightZoneGap,
                top: headerH,
                width: effQueueW,
                height: max(rowH, queueBoxH),
                child: _tonightQueueList(
                  queue,
                  rowH,
                  effQueueW,
                  rails.isNotEmpty,
                ),
              ),
            // THE RAIL.
            if (view != null)
              Positioned(
                left: _kTonightPadX,
                right: 0,
                bottom: 0,
                child: _tonightRail(
                  view,
                  railBoxH,
                  queueAbove: queue.isNotEmpty && showQueue,
                ),
              ),
          ],
        );
      },
    );
  }

  /// A queue row's true minimum at the current text scale: title + episode +
  /// their gaps + the progress bar + the row's vertical padding.
  double _tonightRowMinHeight(BuildContext context) {
    final t = MediaQuery.textScalerOf(context);
    return t.scale(13.5) * 1.25 + 5 + t.scale(11.5) * 1.25 + 9 + 4 + 20 + 4;
  }

  double _tonightHeaderHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_kTonightTitleSize) * 1.35 +
      _kTonightHeaderPad;

  Widget _tonightHeader(int inProgress) {
    final app = AppThemeScope.of(context);
    final now = DateTime.now();
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    // A weekday word, not a clock: a minute-accurate label would need a timer
    // ticking on the home board for the whole session.
    final day = days[(now.weekday - 1).clamp(0, 6)];
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Tonight',
              style: TextStyle(
                color: app.core.tx,
                fontSize: _kTonightTitleSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              day,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.40),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            const Spacer(),
            if (inProgress > 0)
              Text(
                '$inProgress IN PROGRESS',
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.40),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tonightQueueList(
    List<_TonightQueueEntry> queue,
    double rowH,
    double queueW,
    bool hasRail,
  ) {
    // The thumb is capped by the row's WIDTH, not just its height. Sized
    // purely as `rowH * 16/9` it ate two thirds of a narrow queue and left
    // the title about ten characters — "Orange Is t…". Whatever is left of
    // 16:9 after this cap, BoxFit.cover crops.
    final thumbW = min(rowH * 16 / 9, queueW * _kTonightThumbShare);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ListView.builder(
            key: const ValueKey('tonight-queue'),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            itemCount: queue.length,
            itemExtent: rowH + _kTonightRowGap,
            itemBuilder: (context, i) {
              final e = queue[i];
              final cw = e.rail.cw!;
              final item = cw.items[e.col];
              return Padding(
                padding: const EdgeInsets.only(bottom: _kTonightRowGap),
                child: _TonightQueueRow(
                  item: item,
                  height: rowH,
                  thumbWidth: thumbW,
                  focusNode: cw.nodes[e.col],
                  episode: cw.episodeOf(item),
                  progress: cw.progressOf(item),
                  hasBoundSource: _isBound(item),
                  onFocused: () {
                    _tonightZoneIsQueue = true;
                    _tonightQueueCol = i;
                    _tonightQueueKey = _tonightQueueKeyOf(e);
                    _tonightCard.value = _TonightCardInfo(
                      // OK opens the detail page for a Continue Watching card
                      // everywhere in the app; the HOLD menu is what resumes.
                      action: 'Open',
                      // HOLD opens the card menu (Play / Remove) — not a
                      // direct resume, so it is named for what it is.
                      holdAction: 'Options',
                      episode: cw.episodeOf(item),
                      progress: cw.progressOf(item),
                    );
                    _setHero(item);
                  },
                  onOpen: () => cw.onOpen(item),
                  onLongPress: () =>
                      _openCwCardMenu(cw, item, e.rail.cwIndex, e.col),
                  onUp: () {
                    if (_stageHoldSwallow(LogicalKeyboardKey.arrowUp)) return;
                    if (i > 0) {
                      _nearestMountedNode(
                        queue[i - 1].rail.cw!.nodes,
                        queue[i - 1].col,
                      )?.requestFocus();
                    }
                  },
                  onDown: () {
                    if (_stageHoldSwallow(LogicalKeyboardKey.arrowDown)) return;
                    if (i + 1 < queue.length) {
                      _nearestMountedNode(
                        queue[i + 1].rail.cw!.nodes,
                        queue[i + 1].col,
                      )?.requestFocus();
                    } else if (hasRail) {
                      _tonightFocusRail();
                    }
                  },
                  // HELD down: leave the queue for the rail in one gesture.
                  // The queue is every Continue Watching item from every
                  // source flattened into one column, so stepping past it a
                  // row at a time can be a long walk.
                  onDownHold: hasRail
                      ? () => _stageHoldJump(
                          LogicalKeyboardKey.arrowDown,
                          _tonightFocusRail,
                        )
                      : null,
                  onLeft: () => MainPageBridge.focusTvSidebar?.call(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tonightRail(
    _StageRailView view,
    double boxH, {
    required bool queueAbove,
  }) {
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail ? _canvasFavItemCount(rail.favKind!) : items.length;
    // UP walks back through the rails and then into the queue — the two zones
    // are one vertical column.
    void up() {
      if (_stageHoldSwallow(LogicalKeyboardKey.arrowUp)) return;
      if (view.index > 0) {
        _stageSwitchRail(-1);
      } else if (queueAbove) {
        _tonightFocusQueue();
      }
    }

    void down() {
      if (_stageHoldSwallow(LogicalKeyboardKey.arrowDown)) return;
      _stageSwitchRail(1);
    }

    // HELD up: back to the Continue queue from any rail, the mirror of the
    // queue's held DOWN.
    final upHold = queueAbove
        ? () => _stageHoldJump(LogicalKeyboardKey.arrowUp, _tonightFocusQueue)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: _kTonightPadX),
          child: _deckRailLabel(view),
        ),
        const SizedBox(height: _kAtriumLabelGap),
        SizedBox(
          height: boxH,
          child: ListView.builder(
            key: ValueKey('tonight-rail-$railKey'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 400,
            itemCount: count,
            itemBuilder: (context, col) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Center(
                child: SizedBox(
                  width: favRail
                      ? _stageFavW(context, boxH)
                      : boxH * _stageCardAspect(rail),
                  child: favRail
                      ? _canvasFavCell(
                          rail.favKind!,
                          railKey,
                          col,
                          onUp: up,
                          onDown: down,
                          onUpHold: upHold,
                        )
                      : SizedBox(
                          height: boxH,
                          child: _stageShelfCell(
                            rail,
                            railKey,
                            items,
                            nodes,
                            col,
                            onUp: up,
                            onDown: down,
                            onUpHold: upHold,
                            onFocusedExtra: () {
                              _tonightZoneIsQueue = false;
                              _tonightCard.value = _TonightCardInfo(
                                action: 'Open',
                                // Only Continue Watching cards arm hold-OK on
                                // TV (they are the ones with a menu); catalog
                                // cards have no hold action, so no hint.
                                holdAction: rail.cw != null ? 'Options' : null,
                                episode: rail.cw?.episodeOf(items[col]),
                                progress: rail.cw?.progressOf(items[col]),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: _kTonightRailTail),
      ],
    );
  }

  /// Tab label for a rail, with colliding titles disambiguated by the
  /// section's provenance tag. Titles carry their content type themselves
  /// now ("Popular Movies" — [CatalogSection.rowTitle]), so the only way two
  /// tabs still collide is the same catalog name+type from two ADDONS — and
  /// the addon is exactly what tells those apart.
  String _canvasTabTitle(List<_CanvasRail> rails, int i) {
    final title = _canvasRailTitle(rails[i]);
    final rail = rails[i];
    if (rail.sectionIndex == null) return title;
    final duplicated = rails.any(
      (r) => !identical(r, rail) && _canvasRailTitle(r) == title,
    );
    if (!duplicated) return title;
    return '$title · ${_sectionTag(_sections[rail.sectionIndex!])}';
  }

  /// Quiet rail-name tabs above the Canvas shelf — a window around the
  /// active rail (display only; UP/DOWN does the switching). The window is
  /// sized to what actually FITS: at some Screen Size settings the board is
  /// narrow enough that four capped labels + chevrons + the "+N more" tail
  /// would overflow the Row.
  Widget _canvasTabs(List<_CanvasRail> rails, int active) {
    final app = AppThemeScope.of(context);
    return LayoutBuilder(
      builder: (context, cons) {
        // Worst-case per-tab footprint: 170px label cap + 26px gap. Reserve
        // the chevron affordance (~25px) and the "+N more" tail (~92px).
        const perTab = 196.0;
        const reserved = 25.0 + 92.0;
        // May legitimately be ZERO: a narrow board (Mosaic's header shares its
        // width with the identity, and Screen Size can shrink the board) has
        // room for the chevrons and the "+N more" tail but not a label — and
        // an unflexible label there would overflow the Row.
        final maxTabs = (((cons.maxWidth - reserved) / perTab).floor()).clamp(
          0,
          4,
        );
        // Zero tabs fit: show no labels at all, but still say how many rails
        // there are (otherwise the row is a pair of chevrons with no context).
        // Leading CONTEXT (starting one rail early) only makes sense once there
        // is room for more than one label. With a single slot, starting at
        // `active - 1` put the ONLY visible label on the rail BEFORE the active
        // one — so the strip named a rail the board wasn't showing, and nothing
        // was styled active because `i == active` never matched. The window must
        // always contain the active rail.
        var start = switch (maxTabs) {
          0 => 0,
          1 => active,
          _ => active - 1,
        };
        if (maxTabs > 0 && start > rails.length - maxTabs) {
          start = rails.length - maxTabs;
        }
        if (start < 0) start = 0;
        var end = start + maxTabs;
        if (end > rails.length) end = rails.length;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // UP/DOWN affordance: a quiet stacked chevron pair in front of the
            // rail names — the one visual clue that vertical DPAD is what
            // switches them (they sit above the shelf, so nothing else says so).
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 13,
                    color: app.fade(app.core.tx, 0.45),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -5),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 13,
                      color: app.fade(app.core.tx, 0.45),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = start; i < end; i++)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          _canvasTabTitle(rails, i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: _kCanvasTabFontSize,
                            fontWeight: i == active
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.3,
                            color: i == active
                                ? app.core.tx
                                : app.fade(app.core.tx, 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: _kCanvasTabUnderlineGap),
                      Container(
                        height: _kCanvasTabUnderline,
                        width: 26,
                        decoration: BoxDecoration(
                          borderRadius: app.shape.br(2),
                          color: i == active ? app.core.tx : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (end < rails.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  '+${rails.length - end} more',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: app.fade(app.core.tx, 0.24),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Whether the hero spotlight is live for the current tab/state: TV-only, on
  /// the board always and on the dedicated Search tab once there are results
  /// (hidden on the blank "type to search" prompt). Single source of truth for
  /// seeding ([_applySections]), focus tracking ([_setHero]) and rendering
  /// ([_buildBoard]) so they can't drift.
  bool get _heroActive =>
      widget.isTelevision && (!widget.searchMode || _catalogQuery.isNotEmpty);

  void _setHero(StremioMeta item) {
    // Off-TV / blank search prompt the hero isn't rendered, so don't track focus
    // or fire the per-item backdrop-enrichment /meta fetch behind it.
    if (!_heroActive) return;
    // Folders own the stage art too, but never request title metadata or video.
    if (item.type == 'folder') {
      _heroTimer?.cancel();
      _heroReqId++;
      _heroSwapTimer?.cancel();
      _clearHeroTrailer();
      _clearHeroLiveIptv();
      _canvasFavFocus.value = null;
      _heroEnriched.value = null;
      _heroItem.value = item;
      _publishAmbientArt(item, null);
      _updateHeroTint(item);
      return;
    }
    // A catalog/CW card owns the stage again — drop any Canvas favourites
    // override so its art/identity yield to the hero pipeline.
    _canvasFavFocus.value = null;
    // A catalog/CW card just took focus (possibly straight from the IPTV
    // favourites row, which has no row in between) — drop any live IPTV feed
    // so the boxed video region falls back to this item's own trailer.
    _clearHeroLiveIptv();
    if (_heroItem.value?.id == item.id) {
      // Back on the current hero (a vertical move within the column, or an
      // A→B→A jiggle inside the swap debounce): drop any pending swap to a
      // neighbour focus merely passed through — and RE-ARM the trailer when
      // the move away already tore it down and nothing is resolving. Without
      // the re-arm, a quick jiggle left the hero permanently trailer-less
      // (cleared on the first keypress, never rescheduled — "some cards
      // never even show the loading pill"). A trailer that's already playing
      // or resolving is left completely alone.
      _heroSwapTimer?.cancel();
      if (_heroTrailer.value == null && !_heroTrailerLoading.value) {
        _scheduleHeroTrailer(item);
      }
      return;
    }
    // Instant + cheap on EVERY move: kill any trailer (timer cancels and
    // notifier flips) so the lights-off veils start lifting with the
    // keypress, even though the hero swap itself waits for the rest below.
    _clearHeroTrailer();
    // First hero (board just landed) shows instantly. After that, the swap
    // waits for a short DPAD rest — holding a direction across a row costs
    // only the card focus visuals (ring + scale), never a spotlight rebuild
    // plus a backdrop decode per step. This is the Nuvio/Netflix billboard
    // settle debounce from the approved Concept-5 foundations, and the
    // second half of the "navigation feels heavy" fix (the first was the
    // tint cache publishing synchronously).
    if (_heroItem.value == null) {
      _applyHero(item);
      return;
    }
    _heroSwapTimer?.cancel();
    _heroSwapTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _applyHero(item);
    });
  }

  /// The real hero swap — everything downstream of "focus has RESTED here".
  void _applyHero(StremioMeta item) {
    _heroItem.value = item;
    _heroEnriched.value = null;
    _publishAmbientArt(item, null);
    _enrichHero(item);
    _updateHeroTint(item);
    // A NEW title in the spotlight lifts the after-the-feature suppression —
    // fresh context, fresh trailer.
    _heroTrailerSuppressed = false;
    _scheduleHeroTrailer(item);
  }

  /// The hero id the shell stage's current art belongs to — lets a re-seed of
  /// the SAME title (board reloads: See-All return, Home Rows change,
  /// integrations refresh) keep the enriched backdrop on screen instead of
  /// downgrading to the poster for the ~300ms until enrichment re-lands
  /// (which was a prominent full-screen double-crossfade).
  String? _ambientArtItemId;

  /// Publish the focused title's key art to the app shell's glass stage
  /// (TvAmbientArtStage — the blurred backdrop BEHIND the sidebar and this
  /// board's transparent scaffold). Rest-cadence only: called from
  /// [_applyHero] (260ms settle) and the enrichment landing, never per
  /// keypress. TV Home board only; other modes leave the shell alone.
  void _publishAmbientArt(StremioMeta? item, StremioMeta? enriched) {
    if (!_heroTrailerActive) return;
    // Layouts whose own ground is INK (Atrium's panel, Deck's and Tonight's
    // fields, Mosaic's veiled wash) must not light the shell: the shell art
    // only shows in the 64px strip behind the ghost rail, so a bright blurred
    // sliver would butt straight into the board's flat ground and read as a
    // seam. Publishing null leaves the shell on its flat page ink, which is
    // exactly what those boards continue.
    if (_stageActive && !_stagePublishesShellArt) {
      _ambientArtItemId = null;
      if (MainPageBridge.tvAmbientArt.value != null) {
        MainPageBridge.tvAmbientArt.value = null;
      }
      return;
    }
    final backdrop = item?.background?.isNotEmpty == true
        ? item!.background
        : (enriched?.background?.isNotEmpty == true
              ? enriched!.background
              : null);
    // Same title, no backdrop in hand (only the poster fallback), and the
    // stage already shows SOMETHING for it → keep what's showing; the
    // enrichment landing republishes the real backdrop moments later.
    if (backdrop == null &&
        item?.id != null &&
        item!.id == _ambientArtItemId &&
        MainPageBridge.tvAmbientArt.value != null) {
      return;
    }
    final art = backdrop ?? item?.poster;
    _ambientArtItemId = item?.id;
    MainPageBridge.tvAmbientArt.value = (art == null || art.isEmpty)
        ? null
        : art;
  }

  /// Debounced ambient-trailer load for the spotlighted title. The previous
  /// trailer is torn down IMMEDIATELY on any hero change (a playing trailer
  /// under the wrong title is worse than the static backdrop), then a new one
  /// only starts once focus has RESTED on the card — flying across a row costs
  /// nothing but a timer reset, never a resolve or a decoder spin-up. Both
  /// lookups (Cinemeta /meta for the YouTube id, then the stream resolve) are
  /// cached in their services, so re-resting on a recent card starts fast.
  void _scheduleHeroTrailer(StremioMeta item, {bool fromSpotlight = false}) {
    if (item.type == 'folder') return;
    // Off-TV nothing ever calls _applyHero (the TV paths that lift the
    // after-playback suppression), so a NEW title arriving through the
    // spotlight dwell lifts it here — fresh context, fresh trailer, the same
    // rule _applyHero implements for TV.
    if (_heroTrailerSuppressed &&
        fromSpotlight &&
        item.id != _heroTrailerScheduledItemId) {
      _heroTrailerSuppressed = false;
    }
    if (!_heroTrailerRenderable ||
        !_heroTrailerEnabled ||
        _heroTrailerSuppressed) {
      return;
    }
    _heroTrailerScheduledItemId = item.id;
    // Spotlight owns its own hero cadence, so the shared scheduler must not
    // also drive it — two systems interleaving on one hero is how a trailer
    // starts under the wrong title.
    //
    // The guard lives HERE rather than at the call sites: scheduling reaches
    // this method from init, section loads, focus changes, `_applyHero`,
    // route return and sidebar return, and a per-site exclusion would miss
    // one. `_heroTrailerActive` is deliberately left style-blind — it governs
    // listener registration across an asynchronously loaded style, and gating
    // it leaks or double-registers listeners.
    if (_homeStyleEffective == 'spotlight' && !fromSpotlight) return;
    // A layout with no place to put moving picture (Mosaic) never resolves a
    // trailer at all — the resolve is a network + engine cost for something
    // that would be invisible under its veil.
    if (_stageActive && !_stageWantsAmbient) return;
    // A Canvas favourite owns the stage (or its live feed does): a catalog
    // trailer must never start beneath it. The next catalog/CW focus goes
    // through _setHero, which clears both and reschedules. Safe to skip the
    // reset lines below: every fav-focus path already ran _clearHeroTrailer.
    if (_canvasFavFocus.value != null || _heroLiveChannel.value != null) {
      return;
    }
    _heroTrailerTimer?.cancel();
    final req = ++_heroTrailerReq;
    if (_heroTrailer.value != null) _heroTrailer.value = null;
    if (_heroTrailerLoading.value) _heroTrailerLoading.value = false;
    if (_heroTrailerShowing.value) _heroTrailerShowing.value = false;
    // Spotlight has already decided that this hero owns the stage. Begin the
    // useful network/decoder work immediately there; other layouts keep the
    // shared 2.4s focus-rest debounce so flying across their rows stays cheap.
    final resolveDelay = fromSpotlight
        ? Duration.zero
        : const Duration(milliseconds: 2400);
    _heroTrailerTimer = Timer(resolveDelay, () async {
      if (!mounted || req != _heroTrailerReq) return;
      // The layout may have changed during the dwell — a stage with nowhere
      // to put moving picture must not spin up an engine.
      if (_stageActive && !_stageWantsAmbient) return;
      // Covered by ANY modal (bottom sheet, dialog — which never reach the
      // PageRoute-only route observer) or a pushed page: a trailer must not
      // start under it. The cover's dismissal path re-arms where relevant
      // (didPopNext for pages); sheets simply wait for the next hero rest.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      // From here the attempt is committed — surface the pill. Every exit
      // below (no trailer, failed resolve, hero moved on) clears it; success
      // keeps it up until the backdrop reports frames (_onHeroTrailerPlaying).
      _heroTrailerLoading.value = true;
      void fail() {
        if (mounted && req == _heroTrailerReq) {
          _heroTrailerLoading.value = false;
        }
      }

      // YouTube id: catalog rows rarely carry it, so fall back to the /meta
      // details (the same fetch — and cache — the hero enrichment uses).
      final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
      String? ytId = item.trailerYtId;
      if (ytId == null || ytId.isEmpty) {
        if (imdb == null) return fail();
        try {
          final full = await _stremio.fetchMetaDetails(
            imdbId: imdb,
            type: item.type,
          );
          ytId = full?.trailerYtId;
        } catch (_) {
          // Meta fetch failed — the IMDb backup below may still carry it.
        }
      }
      if (!mounted || req != _heroTrailerReq) return;
      // Ambient hero backdrop: resolve at a low cap (small region, weak TV).
      var streams = (ytId != null && ytId.isNotEmpty)
          ? await YoutubeService.resolveStreams(
              ytId,
              maxHeightOverride: YoutubeService.ambientTrailerMaxHeight,
              preferVp9: true,
            )
          : null;
      // Backup source: IMDb hosts its own trailer MP4s, so a YouTube block
      // (or a title with no YouTube id at all) still gets a moving hero.
      if ((streams == null || !streams.hasPlayable) && imdb != null) {
        if (!mounted || req != _heroTrailerReq) return;
        streams = await ImdbTrailerService.resolveTrailer(
          imdb,
          maxHeight: YoutubeService.ambientTrailerMaxHeight,
        );
      }
      if (!mounted || req != _heroTrailerReq) return;
      if (streams == null || !streams.hasPlayable) return fail();
      _heroTrailer.value = streams;
      // Failsafe: a dead/bot-blocked stream can error inside the engine
      // before ever producing a frame, in which case onPlayingChanged never
      // fires (it only reports real transitions) — don't let the pill spin
      // forever on a trailer that will never come.
      Timer(const Duration(seconds: 15), fail);
    });
  }

  /// The hero backdrop's playing signal: frames on screen (true) or engine
  /// teardown/error (false). Ends the loading pill either way, and drives the
  /// spotlight's image-yield crossfade.
  void _onHeroTrailerPlaying(bool playing) {
    if (_heroTrailerLoading.value) _heroTrailerLoading.value = false;
    if (_heroTrailerShowing.value != playing) {
      _heroTrailerShowing.value = playing;
    }
  }

  /// Kill any pending/playing hero trailer (hero cleared, board reloading).
  void _clearHeroTrailer() {
    _heroTrailerTimer?.cancel();
    _heroTrailerReq++;
    if (_heroTrailer.value != null) _heroTrailer.value = null;
    if (_heroTrailerLoading.value) _heroTrailerLoading.value = false;
    if (_heroTrailerShowing.value) _heroTrailerShowing.value = false;
  }

  /// DPAD focus rested on an IPTV favourite card — retune the boxed hero video
  /// region to that channel's live stream. A plain M3U/Xtream favourite's URL
  /// is already playable; a Stremio-addon favourite resolves candidates first
  /// (same async ladder [IptvResultsView] uses for its own inline preview),
  /// guarded by [_heroLiveReq] so a fast DPAD move past it can't land a stale
  /// resolve on top of whatever channel focus has since moved to.
  void _setHeroLiveIptv(IptvChannel channel) {
    if (!_heroTrailerActive) return;
    if (_heroLiveChannel.value?.url == channel.url) return;
    _heroLiveChannel.value = channel;
    if (!_heroLiveTakeover.value) _heroLiveTakeover.value = true;
    _heroLiveCandidates = null;
    final req = ++_heroLiveReq;
    // A live feed pre-empts whatever catalog trailer is mid-flight/playing —
    // instant teardown, same as any other hero change.
    _clearHeroTrailer();
    _heroLiveUrl.value = null;
    // The shell's glass-stage backdrop and sidebar tint are ALSO the stale
    // catalog title's art (published by [_publishAmbientArt]/
    // [_publishHeroTintToShell], neither of which this focus path runs) —
    // blank them too rather than leaving that art behind everything,
    // including the sidebar, while an unrelated channel plays.
    MainPageBridge.tvAmbientArt.value = null;
    MainPageBridge.tvHeroTint.value = null;
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _heroLiveUrl.value = channel.url;
      return;
    }
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || req != _heroLiveReq || found.isEmpty) return;
      _heroLiveCandidates = [for (final c in found) c.url];
      _heroLiveUrl.value = _heroLiveCandidates!.first;
    });
  }

  /// DPAD focus left the IPTV favourites row (another favourites row, or a
  /// catalog/CW card) — drop the live feed so the boxed region falls back to
  /// whatever catalog trailer [_heroItem] owns.
  void _clearHeroLiveIptv() {
    _heroLiveReq++;
    final wasLive = _heroLiveChannel.value != null;
    if (wasLive) _heroLiveChannel.value = null;
    if (_heroLiveTakeover.value) _heroLiveTakeover.value = false;
    _heroLiveCandidates = null;
    if (_heroLiveUrl.value != null) _heroLiveUrl.value = null;
    // The unmounting live backdrop can never report playing:false (its
    // dispose doesn't notify), and when the trailer path declines to re-arm
    // (trailers off / suppressed) nothing else resets these — a stuck
    // showing=true kept canvas theater re-firing over a static stage and
    // held the shell's lights off.
    if (wasLive) {
      if (_heroTrailerShowing.value) _heroTrailerShowing.value = false;
      if (_heroTrailerLoading.value) _heroTrailerLoading.value = false;
    }
    // Restore the shell's glass-stage backdrop/tint for whatever catalog
    // title the hero already holds. Needed even when DPAD focus returns to
    // the SAME card it was on before IPTV took over: _setHero's "back on the
    // current hero" branch doesn't re-run _publishAmbientArt/
    // _publishHeroTintToShell (no item change to react to), so without this
    // the shell would stay on the blank/neutral state _setHeroLiveIptv left
    // it in.
    if (wasLive && _heroTrailerActive) {
      _publishAmbientArt(_heroItem.value, _heroEnriched.value);
      // Through the GATE, not straight at the bridge: the ink-ground layouts
      // publish no shell tint, and restoring one here would leave a coloured
      // sidebar sitting on a flat board until something else cleared it.
      _publishHeroTintToShell(_heroTint.value);
    }
  }

  /// The boxed hero region's live IPTV feed genuinely failed (refused to
  /// open, errored, or stalled past the first-frame timeout) — step down its
  /// candidate ladder, mirroring the IPTV page's own inline preview
  /// (IptvResultsView._onPreviewPlaybackFailed). No-op for a plain M3U/Xtream
  /// favourite (single URL, no ladder) or once every candidate is exhausted.
  void _onHeroLivePlaybackFailed() {
    final candidates = _heroLiveCandidates;
    final current = _heroLiveUrl.value;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0 || next >= candidates.length) {
      // Every candidate is dead: forget the cached list so a later attempt
      // re-resolves fresh links instead of replaying the same dead ones for
      // the rest of the 5-minute cache window.
      final channel = _heroLiveChannel.value;
      if (channel != null) StremioIptvService.instance.invalidate(channel.url);
      _heroLiveUrl.value = null;
      return;
    }
    _heroLiveUrl.value = candidates[next];
  }

  /// Mirror the takeover arc onto the app-shell notifier (sidebar rail hide).
  void _relayChromeDim() {
    MainPageBridge.tvChromeDim.value = _heroTrailerTakeover.value;
  }

  /// Mirror the ambient trailer's lights-off state onto the app-shell
  /// notifier — the shell veils the sidebar rail in lock-step with the
  /// board's own row/hero veils, so the whole room goes dark together.
  void _relayLightsOff() {
    MainPageBridge.tvStageLightsOff.value = _heroTrailerShowing.value;
  }

  // ── Route awareness (Home board trailer only) ────────────────────────────
  // The trailer schedule is time-driven, so without this a pushed route
  // (detail page, player) would let the 2.4s debounce fire UNDER the cover
  // and start a trailer behind it — the backdrop's own RouteAware pause can't
  // help because it mounts after the cover was already pushed and never sees
  // a didPushNext. Kill everything when covered; re-arm the spotlight when
  // the cover pops so browsing resumes its normal rest-to-play.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_heroTrailerActive) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (!_heroTrailerActive) return;
    _clearHeroTrailer();
  }

  @override
  void didPopNext() {
    // A board reload UNDER a detail page/player can dispose the focused node;
    // the reclaim listener fires while covered and bails on route.isCurrent,
    // and no focus event re-fires it on the way back — re-run the dead check
    // now that the board is the top route again.
    _onGlobalFocusChange();
    if (!_heroTrailerActive || !_heroTrailerEnabled) return;
    final item = _heroItem.value;
    if (item != null) _scheduleHeroTrailer(item);
  }

  /// Content playback launched (see the listener registration in
  /// [initState]): kill the trailer NOW (native activity launches never push
  /// a Flutter route, so RouteAware alone can't catch them all) and keep it
  /// off for this spotlight — it must not resume behind or after the feature.
  void _onContentPlayerLaunch() {
    if (!_heroTrailerRenderable || !mounted) return;
    _heroTrailerSuppressed = true;
    // The suppression baseline is the hero SHOWING at launch, not the last
    // dwell's item — playback can start before the first dwell (cold open →
    // open a card immediately), or after paging A→B with B's dwell still
    // pending. Without this snapshot the stored id is stale/null and the
    // just-watched title's own dwell would read as "new" and lift the
    // suppression it was meant to hold.
    final showing = _spotlightKey.currentState?.currentHeroId;
    if (showing != null) _heroTrailerScheduledItemId = showing;
    _clearHeroTrailer();
  }

  /// Any key while the takeover owns the screen restores the board — the UI
  /// is at opacity 0, so this can't be left to hero-change detection alone
  /// (fav-row tiles and same-title cards never change the hero). Observe-only
  /// (always returns false): the key still does its normal job, so SELECT
  /// both restores the board and opens the showcased title.
  bool _onTakeoverKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_heroTrailerTakeover.value <= 0.02) return false;
    _clearHeroTrailer();
    return false;
  }

  /// Sidebar focus enter/exit (see the listener registration in [initState]).
  void _onTvSidebarFocusChanged(bool focused) {
    if (!_heroTrailerActive || !_heroTrailerEnabled || !mounted) return;
    if (focused) {
      _clearHeroTrailer();
    } else {
      final item = _heroItem.value;
      if (item != null) _scheduleHeroTrailer(item);
    }
  }

  // ── Dynamic per-title tint ────────────────────────────────────────────────
  // The hero scrim takes on the focused title's dominant poster color, so the
  // screen shifts mood as you browse. Extraction is debounced (only after
  // focus SETTLES — never per card while flying across a row), cached per
  // title, and decodes a 32px thumbnail — negligible on the TV chip.
  final ValueNotifier<Color?> _heroTint = ValueNotifier<Color?>(null);
  final Map<String, Color?> _tintCache = {};
  Timer? _tintTimer;
  int _tintReq = 0;

  void _updateHeroTint(StremioMeta item) {
    _tintTimer?.cancel();
    final req = ++_tintReq;
    // ALWAYS defer — cache hits and empty posters included. Publishing a
    // cached tint synchronously here meant every DPAD step over already-
    // visited cards re-rastered every tint consumer (the full-screen mood
    // field, the hero stage, the 450ms scrim tween, the art feathers) — the
    // "navigation feels heavy" regression. The tint is scenery: it only
    // needs to land once focus RESTS, never while scrubbing a row. (Short
    // now that the 260ms hero-swap settle already ran before this fires.)
    _tintTimer = Timer(const Duration(milliseconds: 120), () async {
      final poster = item.poster;
      if (poster == null || poster.isEmpty) {
        _heroTint.value = null;
        _publishHeroTintToShell(null);
        return;
      }
      if (_tintCache.containsKey(item.id)) {
        _heroTint.value = _tintCache[item.id];
        _publishHeroTintToShell(_tintCache[item.id]);
        return;
      }
      // Via the shared cache: the Home hero re-extracts on every focus rest,
      // and the same posters come back constantly as the user arrows around.
      final color = await DominantColorCache.of(
        poster,
        CachedNetworkImageProvider(poster),
      );
      if (!mounted || req != _tintReq) return; // focus moved on — stale
      // Unbounded growth guard; a full clear is fine, extraction is cheap.
      if (_tintCache.length > 300) _tintCache.clear();
      _tintCache[item.id] = color;
      _heroTint.value = color;
      _publishHeroTintToShell(color);
    });
  }

  /// Relay the settled tint to the app shell — the sidebar's glass blends it
  /// in and the shell's art stage tints its washes with it. Rest-cadence and
  /// CONSTANT across trailer start/stop, so there's no colour flooding in or
  /// out at playback edges (the old complaint); the room simply wears the
  /// focused film's hue while browsing. TV Home board only.
  void _publishHeroTintToShell(Color? color) {
    if (!_heroTrailerActive) return;
    // The tint exists to make the sidebar read as glass over the SHELL ART.
    // Layouts that publish no art (ink grounds — see [_publishAmbientArt])
    // would just get a coloured rail floating on flat ink, so they stay
    // neutral.
    MainPageBridge.tvHeroTint.value = (_stageActive && !_stagePublishesShellArt)
        ? null
        : color;
  }

  /// Title-treatment art URL derivable SYNCHRONOUSLY from an IMDb id — the
  /// same metahub image Cinemeta's /meta `logo` field points at. Lets the
  /// hero start fetching the logo the moment focus settles instead of after
  /// the /meta roundtrip — the roundtrip gap is what flashed the text title
  /// for a beat before the art swapped in over it (the "title comes as text
  /// then updates to image" complaint). A dead URL (title has no logo art)
  /// falls back to the text title inside [_HeroTitleArt].
  String? _derivedHeroLogo(StremioMeta item) {
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return null;
    return 'https://images.metahub.space/logo/medium/$imdb/img';
  }

  /// Debounced backdrop/description enrichment. Catalog list items usually
  /// omit `background`/`description` (they come from the /meta endpoint), so
  /// fetch them lazily — cached in [StremioService], and guarded against the
  /// focus moving on (req id) so a slow fetch never clobbers a newer hero.
  void _enrichHero(StremioMeta item) {
    _heroTimer?.cancel();
    final needsBg = item.background == null || item.background!.isEmpty;
    final needsDesc = item.description == null || item.description!.isEmpty;
    final needsRating = item.imdbRating == null;
    // Catalog list items almost never carry runtime, so without this the /meta
    // fetch (its only source) would be skipped whenever bg+desc+rating are
    // already present — and the hero/takeover runtime would stay blank.
    final needsRuntime = item.runtime == null;
    // Same for the logo title-treatment: catalog items basically never carry
    // it, and without this an item that happens to have bg+desc+rating+runtime
    // (e.g. Continue Watching) would skip the fetch and stay text-titled.
    final needsLogo = item.logo == null || item.logo!.isEmpty;
    if (!needsBg && !needsDesc && !needsRating && !needsRuntime && !needsLogo) {
      return;
    }
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return;
    final reqId = ++_heroReqId;
    // Short: on the board this only fires after the 260ms hero-swap settle.
    _heroTimer = Timer(const Duration(milliseconds: 140), () async {
      final details = await _stremio.fetchMetaDetails(
        imdbId: imdb,
        type: item.type,
      );
      if (!mounted || reqId != _heroReqId || details == null) return;
      _heroEnriched.value = details;
      // The enrichment usually carries the real backdrop a catalog item
      // lacked — upgrade the shell stage from the poster-blur to it.
      _publishAmbientArt(item, details);
    });
  }

  // ── Search field ─────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    _searchSubmitFocus.cancel();
    // Every mode searches on SUBMIT. Because the field is shared, emptying it
    // must invalidate EVERY mode's cached query/result state; otherwise a mode
    // switch can reveal results for text the field no longer contains.
    _catalogDebounce?.cancel();
    if (value.trim().isEmpty) {
      _clearQuery();
    }
  }

  void _onQuerySubmitted(String value) {
    _catalogDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      _searchSubmitFocus.cancel();
    } else {
      _searchSubmitFocus.arm(enabled: widget.isTelevision);
    }
    switch (_mode) {
      case _Mode.keyword:
        _runKeyword(q);
        return;
      case _Mode.catalog:
        if (q.isEmpty) {
          _restoreHome();
        } else {
          _runCatalogSearch(q);
        }
        return;
      case _Mode.lists:
        if (q.isEmpty) {
          _clearListsSearch();
        } else {
          _runListsSearch(q);
        }
        return;
    }
  }

  void _clearQuery() {
    _catalogDebounce?.cancel();
    _searchSubmitFocus.cancel();
    _searchController.clear();
    _kwSearchToken++;
    _disposeKwNodes();
    _disposeListsNodes();
    setState(() {
      _kwSearching = false;
      _kwLoading = false;
      _kwQuery = '';
      _kwAll = [];
      _kwResults = [];
      _kwCache = {};
      _kwError = null;
      _kwPending = null;
      _kwSelectionMode = false;
      _kwSelected.clear();
      _listsToken++; // cancel an in-flight lists search
      _listsQuery = '';
      _listsResults = const [];
      _listsSearching = false;
      _listsError = null;
    });
    _restoreHome();
  }

  void _completeSearchSubmitFocus(FocusNode target) {
    _searchSubmitFocus.complete(
      field: _searchFocusNode,
      isMounted: () => mounted,
      requestFocus: target.requestFocus,
      targetHasFocus: () => target.hasFocus,
    );
  }

  void _disposeListsNodes() {
    for (final n in _listsNodes) {
      n.dispose();
    }
    _listsNodes.clear();
  }

  void _clearListsSearch() {
    _listsToken++;
    _disposeListsNodes();
    if (!mounted) return;
    setState(() {
      _listsQuery = '';
      _listsResults = const [];
      _listsSearching = false;
      _listsError = null;
    });
  }

  /// One focus node per result row, rebuilt to match the current result set.
  void _ensureListsNodes() {
    while (_listsNodes.length < _listsResults.length) {
      _listsNodes.add(FocusNode(debugLabel: 'lists_row_${_listsNodes.length}'));
    }
    while (_listsNodes.length > _listsResults.length) {
      _listsNodes.removeLast().dispose();
    }
  }

  /// Search MDBList's public lists for the dedicated Lists mode. A generation
  /// token prevents a late response from an earlier query or profile state
  /// replacing the current result rail.
  Future<void> _runListsSearch(String query) async {
    // Keep the runtime flag authoritative: when disabled, the selector omits
    // Lists and no list-search request can be issued.
    if (!kMdblistEnabled) {
      _searchSubmitFocus.cancel();
      return;
    }
    final q = query.trim();
    final token = ++_listsToken;
    if (q.isEmpty) {
      _clearListsSearch();
      return;
    }
    _disposeListsNodes();
    setState(() {
      _listsQuery = q;
      _listsResults = const [];
      _listsSearching = true;
      _listsError = null;
    });
    final connected = await MdblistService.instance.isAuthenticated();
    if (!mounted || token != _listsToken) return;
    if (!connected) {
      _searchSubmitFocus.cancel();
      setState(() {
        _listsSearching = false;
        _listsError = 'Connect MDBList in Settings to search public lists.';
      });
      return;
    }
    MdblistResult<List<MdblistListChoice>> result;
    try {
      result = await MdblistListSource.instance.searchListsResult(q);
    } catch (_) {
      result = const MdblistResult.failure(MdblistResultKind.transientFailure);
    }
    if (!mounted || token != _listsToken) return;
    final results = result.data ?? const <MdblistListChoice>[];
    setState(() {
      _listsResults = results;
      _listsSearching = false;
      _listsError = result.isUsable ? null : _listsFailureMessage(result);
      _ensureListsNodes();
    });
    if (_listsNodes.isEmpty) {
      _searchSubmitFocus.cancel();
    } else {
      _completeSearchSubmitFocus(_listsNodes.first);
    }
  }

  String _listsFailureMessage(
    MdblistResult<List<MdblistListChoice>> result,
  ) => switch (result.kind) {
    MdblistResultKind.unauthenticated =>
      'Your MDBList connection has expired. Reconnect it in Settings.',
    MdblistResultKind.denied =>
      'MDBList denied this list search for the connected account.',
    MdblistResultKind.rateLimited =>
      result.retryAfter == null
          ? 'MDBList rate limit reached. Try again later.'
          : 'MDBList rate limit reached. Try again in '
                '${(result.retryAfter!.inSeconds / 60).ceil().clamp(1, 9999)} minutes.',
    MdblistResultKind.malformedResponse =>
      'MDBList returned an unreadable list-search response. Try again.',
    MdblistResultKind.notFound =>
      'MDBList list search is currently unavailable.',
    MdblistResultKind.conflict =>
      'MDBList could not complete this list search. Try again.',
    MdblistResultKind.disabled =>
      'MDBList list search is disabled for this build.',
    MdblistResultKind.transientFailure =>
      'MDBList is not responding right now. Try again shortly.',
    MdblistResultKind.success || MdblistResultKind.partial => '',
  };

  /// Hand the picked list to the Discover tab, which opens it focused (with
  /// the ♥ like toggle). Mirrors the pendingCatalogDetailOpen handoff.
  void _openListsResult(MdblistListChoice choice) {
    // Debounce: a fast double OK/tap must not stack two pushed screens (TV) or
    // double-fire the tab handoff. A route push + Back takes far longer than
    // this, so re-opening the same card after returning still works.
    final now = DateTime.now();
    if (_lastListOpenAt != null &&
        now.difference(_lastListOpenAt!) < const Duration(milliseconds: 600)) {
      return;
    }
    _lastListOpenAt = now;
    AnalyticsService.trackInBackground('mdblist_list_search_open', {
      'liked': choice.liked,
    });
    // TV: switching to the Discover tab rebuilds this Search screen fresh on
    // return (main.dart keys tab content by index), losing the results, scroll,
    // and focused card. Instead PUSH the list's items over the Search board —
    // the screen stays mounted underneath, so Back returns to exactly this
    // state, and we re-focus the tapped rail card so the DPAD cursor lands back
    // on it (its focus handler scrolls it into view). Mobile/laptop keep the
    // Discover-tab landing (with its Source switcher).
    if (widget.isTelevision) {
      _openMdblistListItems(
        context,
        choice,
        onReturn: () {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Re-find by id at return time, so a rail that changed while it was
            // covered still focuses the card that now holds this list.
            final i = _listsResults.indexWhere((l) => l.id == choice.id);
            if (i >= 0 && i < _listsNodes.length) {
              _listsNodes[i].requestFocus();
            }
          });
        },
      );
      return;
    }
    MainPageBridge.pendingMdblistListOpen = {
      'id': choice.id,
      'name': choice.name,
      'ownerName': choice.ownerName,
      'itemCount': choice.itemCount,
      'liked': choice.liked,
      'likes': choice.likes,
    };
    // Discover tab — main.dart `case 18`.
    MainPageBridge.switchTab?.call(MainTab.discover);
  }

  /// Seed the keyword filter set from the user's saved defaults (Settings →
  /// default quality/rip-source/language filters), matching the old search
  /// screen's `_loadDefaultFilters`. Runs once at init; only applies when at
  /// least one default is configured so an empty default keeps filters off.
  Future<void> _loadDefaultKeywordFilters() async {
    try {
      final qualities = await StorageService.getDefaultFilterQualities();
      final sources = await StorageService.getDefaultFilterRipSources();
      final languages = await StorageService.getDefaultFilterLanguages();
      final sizes = await StorageService.getDefaultFilterSizes();
      final ranges = await StorageService.getDefaultFilterDynamicRanges();
      if (!mounted) return;

      final qualitySet = <QualityTier>{};
      final sourceSet = <RipSourceCategory>{};
      final languageSet = <AudioLanguage>{};
      final sizeSet = <SizeBucket>{};
      final rangeSet = <DynamicRange>{};
      for (final q in qualities) {
        for (final e in QualityTier.values) {
          if (e.name == q) qualitySet.add(e);
        }
      }
      for (final s in sources) {
        for (final e in RipSourceCategory.values) {
          if (e.name == s) sourceSet.add(e);
        }
      }
      for (final l in languages) {
        for (final e in AudioLanguage.values) {
          if (e.name == l) languageSet.add(e);
        }
      }
      for (final s in sizes) {
        for (final e in SizeBucket.values) {
          if (e.name == s) sizeSet.add(e);
        }
      }
      for (final r in ranges) {
        for (final e in DynamicRange.values) {
          if (e.name == r) rangeSet.add(e);
        }
      }

      if (qualitySet.isEmpty &&
          sourceSet.isEmpty &&
          languageSet.isEmpty &&
          sizeSet.isEmpty &&
          rangeSet.isEmpty) {
        return;
      }
      // If the user already picked filters while these async reads were in
      // flight, don't clobber their choice with the saved defaults.
      if (_kwFilters.qualities.isNotEmpty ||
          _kwFilters.ripSources.isNotEmpty ||
          _kwFilters.languages.isNotEmpty ||
          _kwFilters.sizes.isNotEmpty ||
          _kwFilters.dynamicRanges.isNotEmpty) {
        return;
      }
      setState(() {
        _kwFilters = TorrentFilterState(
          qualities: qualitySet,
          ripSources: sourceSet,
          languages: languageSet,
          sizes: sizeSet,
          dynamicRanges: rangeSet,
        );
      });
      // If results are already on screen (defaults resolved after a fast
      // search), re-apply so the seeded filters take effect immediately.
      if (_kwAll.isNotEmpty) _recomputeKeyword();
    } catch (_) {
      // Non-fatal: fall back to no default filters.
    }
  }

  /// One-shot: restore DPAD focus to the toolbar at the FIRST streamed paint
  /// (set by _openKeywordSources, whose re-search unmounts the focused pill).
  /// Consumed/cleared on present so a completion refocus can never yank the
  /// remote off a row the user reached mid-stream.
  bool _kwRefocusToolbar = false;

  Future<void> _runKeyword(String query, {bool refocusToolbar = false}) async {
    if (query.isEmpty) return;
    final token = ++_kwSearchToken;
    _kwBatches.clear();
    _kwSearching = true;
    _kwStreamFrozen = false;
    _kwPending = null;
    _kwProviderSeen.clear();
    _kwCacheChecked.clear();
    _kwPendingChecks.clear();
    _kwTbRan = false;
    _kwRefocusToolbar = refocusToolbar;
    setState(() {
      _kwLoading = true;
      _kwError = null;
      _kwQuery = query;
      _kwCache = {};
      _kwCachedOnly = false;
      _kwDirectCounts = {};
      _kwTorrentCounts = {};
      _kwSelectedDirect = {};
      _kwSelectedTorrent = {};
      _kwSelectionMode = false;
      _kwSelected.clear();
      _kwSourceTab = null;
    });
    try {
      // Streaming: each engine's batch lands as soon as THAT engine finishes,
      // so first rows show in seconds instead of after the slowest engine's
      // timeout. Provisional merges use the same mergeSearchResults as the
      // final result, so the list can never drift from what completion shows.
      void onBatch(String source, List<Torrent> batch) {
        if (!mounted || token != _kwSearchToken || batch.isEmpty) return;
        // A timed-out engine's original future keeps running after the
        // timeout fires — its late batch must not mutate the list after the
        // awaited result already snapped it to the authoritative set.
        if (!_kwSearching) return;
        _kwBatches.add(batch);
        _presentKwStreaming(
          TorrentService.mergeSearchResults(_kwBatches),
          token,
        );
        // Stamp TB/PM badges on this engine's rows as they land, and record the
        // future so the completion sweep can await it before deciding cached-
        // only mode (settling it mid-stream would flicker rows in/out).
        _kwPendingChecks.add(_checkKeywordCache(batch, token));
      }

      // Resolve cache-check gating BEFORE the search starts so streaming
      // batches badge against fresh settings (a superseded search's config
      // load is harmless — its batches fail the token guard anyway).
      await _loadKwCacheConfig();
      if (!mounted || token != _kwSearchToken) return;
      final result = await TorrentService.searchAllEngines(
        query,
        onBatch: onBatch,
      );
      // Drop stale results if a newer search started while this was in flight.
      if (!mounted || token != _kwSearchToken) return;
      _kwSearching = false;
      final torrents = (result['torrents'] as List).cast<Torrent>();
      final engineErrors = result['engineErrors'];
      final engineCounts = result['engineCounts'];
      // No engine ran at all (empty counts AND errors) → the user has disabled
      // every source. Point them at Sources instead of a bare "No results".
      // (Both empty-result checks below can only fire when no batch arrived,
      // so the full-screen loader is still up — never an error over rows.)
      final noEngineRan =
          (engineCounts is! Map || engineCounts.isEmpty) &&
          (engineErrors is! Map || engineErrors.isEmpty);
      if (torrents.isEmpty && noEngineRan) {
        _searchSubmitFocus.cancel();
        setState(() {
          _kwError =
              'No sources enabled. Turn on at least one source in '
              'Sources, then try again.';
          _kwLoading = false;
        });
        return;
      }
      // Every source errored and nothing came back → surface the failure
      // instead of a misleading "No results" (searchAllEngines fails soft).
      if (torrents.isEmpty && engineErrors is Map && engineErrors.isNotEmpty) {
        _searchSubmitFocus.cancel();
        setState(() {
          _kwError =
              'Search failed on all sources. Check your connection or '
              'enabled sources and try again.';
          _kwLoading = false;
        });
        return;
      }
      // The awaited result is authoritative — snap to it (or park it).
      _presentKwStreaming(torrents, token);
      _finishKeyword(token);
    } catch (e) {
      if (!mounted || token != _kwSearchToken) return;
      _kwSearching = false;
      _searchSubmitFocus.cancel();
      setState(() {
        _kwError = _friendlyKeywordError(e);
        _kwLoading = false;
      });
    }
  }

  /// Applies a (provisional or final) raw result set: recompute providers and
  /// the filtered view, or — once the user has interacted ([_kwStreamFrozen])
  /// — park it behind the "+N new results" pill so rows never reshuffle
  /// mid-read.
  void _presentKwStreaming(List<Torrent> raw, int token) {
    if (!mounted || token != _kwSearchToken) return;
    // The strip live-updates on every present (frozen or not), so if the
    // remote is ON a tab, capture its source before indices shift.
    final tabAnchor = _focusedKwTabSource();
    if (_kwStreamFrozen) {
      // The user has taken over focus — drop the pending toolbar refocus.
      _kwRefocusToolbar = false;
      _kwPending = raw;
      _syncKwTabNodes(); // live tabs: nodes track the parked set's sources
      setState(() {}); // pill count + tab strip update
      _reanchorKwTab(tabAnchor);
      return;
    }
    _kwAll = raw;
    _computeKwProviders(raw);
    _kwLoading = false; // first batch replaces the full-screen loader
    _recomputeKeyword();
    _reanchorKwTab(tabAnchor);
    if (_kwToolbarVisible) {
      _completeSearchSubmitFocus(_kwToolbarNodes.first);
    }
    if (_kwRefocusToolbar) {
      // The Sources-dialog re-search unmounted the focused toolbar; the
      // toolbar just remounted with this first paint — put the remote back
      // NOW, not at completion (rows are interactive from the first batch).
      _kwRefocusToolbar = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _kwToolbarVisible) _kwToolbarNodes.first.requestFocus();
      });
    }
  }

  /// Completion-only steps: validate the source tab against the final set,
  /// hide the searching strip, and run the cache-badge check.
  void _finishKeyword(int token) {
    if (!mounted || token != _kwSearchToken) return;
    // Validate against the authoritative FULL set (pending included) — an
    // early batch that merely hasn't delivered a source yet must not clear
    // the user's tab mid-stream, so this check only runs here.
    final full = _kwPending ?? _kwAll;
    if (_kwSourceTab != null &&
        !full.any((t) => _kwSourceOf(t) == _kwSourceTab)) {
      _kwSourceTab = null;
      // Recompute over the DISPLAYED set even when arrivals are parked, so
      // the strip ("All" active) and the visible list can't disagree.
      _recomputeKeyword();
    }
    setState(() {}); // searching strip off
    // Completion: await in-flight batch checks, sweep stragglers, then settle
    // cached-only mode over the authoritative full set.
    unawaited(_finalizeKeywordCache(full, token));
  }

  /// First real user interaction → stop live-reshuffling; buffer new arrivals
  /// behind the pill instead.
  void _kwFreeze() {
    _kwStreamFrozen = true;
    _searchSubmitFocus.cancel();
  }

  /// Freeze AND fold any parked arrivals in — used by toolbar/dialog/tab
  /// actions, so the user always sorts/filters/selects over the complete set.
  void _kwFreezeAndAdopt() {
    _kwFreeze();
    _kwAdoptPending();
  }

  /// Folds the parked result set into the list (pill tap / toolbar use) and
  /// refreshes cache badges for the fresh rows.
  void _kwAdoptPending() {
    final p = _kwPending;
    if (p == null) return;
    _kwPending = null;
    // Identity-preserving refocus (Sources-list parity): folding arrivals in
    // can insert rows above the DPAD focus — keep the remote on the SAME
    // torrent, not the same index. This also keeps a long-pressed row under
    // its checkmark when _enterKwSelection adopts before toggling.
    Torrent? focusedTorrent;
    for (var i = 0; i < _kwNodes.length && i < _kwResults.length; i++) {
      if (_kwNodes[i].hasFocus) {
        focusedTorrent = _kwResults[i];
        break;
      }
    }
    _kwAll = p;
    // A tab whose source lost every row to dedupe in the adopted set would
    // otherwise stay "active" over an empty list with no highlighted pill.
    if (_kwSourceTab != null && !p.any((t) => _kwSourceOf(t) == _kwSourceTab)) {
      _kwSourceTab = null;
    }
    _computeKwProviders(p);
    _recomputeKeyword();
    if (focusedTorrent != null) {
      final key = _kwRowKey(focusedTorrent);
      final idx = _kwResults.indexWhere((t) => _kwRowKey(t) == key);
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && idx < _kwNodes.length) _kwNodes[idx].requestFocus();
        });
      }
    }
    unawaited(_checkKeywordCache(_kwAll, _kwSearchToken));
  }

  /// Identity key for pending-row diffing (infohash when real, else the
  /// name+URL pair direct streams are distinguished by).
  static String _kwRowKey(Torrent t) =>
      t.hasRealInfoHash && t.infohash.isNotEmpty
      ? 'h:${t.infohash.toLowerCase()}'
      : 'n:${t.name}|${t.directUrl ?? ''}';

  /// Rows waiting behind the pill (0 hides it) — a SET difference, not a
  /// length delta, so dedupe-shrunk pending sets still count their new rows.
  int get _kwPendingNewCount {
    final p = _kwPending;
    if (p == null) return 0;
    final shown = {for (final t in _kwAll) _kwRowKey(t)};
    var count = 0;
    for (final t in p) {
      if (!shown.contains(_kwRowKey(t))) count++;
    }
    return count;
  }

  /// A torrent's source-tab bucket ('unknown' for empty sources, matching the
  /// provider-filter grouping).
  static String _kwSourceOf(Torrent t) =>
      t.source.isNotEmpty ? t.source : 'unknown';

  /// The fullest known result set: parked arrivals when frozen, else the
  /// displayed set. The tab strip derives from THIS so it live-updates
  /// (counts tick, new source pills appear) even while the rows are frozen —
  /// the strip sits above the list, so it never shifts what's being read.
  List<Torrent> get _kwFullSet => _kwPending ?? _kwAll;

  /// Distinct sources in [_kwFullSet], sorted — drives the tab strip.
  List<String> get _kwSourceList {
    final s = <String>{for (final t in _kwFullSet) _kwSourceOf(t)};
    final l = s.toList()..sort();
    return l;
  }

  /// The tab strip only earns its row when there's a real choice.
  bool get _kwTabsVisible => _kwSourceList.length > 1;

  /// Which SOURCE the focused tab points at ('' = the All tab, null = the
  /// strip isn't focused). Captured BEFORE a strip rebuild so focus can be
  /// re-anchored by identity — new sources insert alphabetically and shift
  /// positional node indices under the remote.
  String? _focusedKwTabSource() {
    for (var i = 0; i < _kwTabNodes.length; i++) {
      if (_kwTabNodes[i].hasFocus) {
        if (i == 0) return '';
        final sources = _kwSourceList;
        return i - 1 < sources.length ? sources[i - 1] : '';
      }
    }
    return null;
  }

  /// Post-frame counterpart of [_focusedKwTabSource]: refocus the tab that
  /// carries [source] at its NEW index (All when it vanished).
  void _reanchorKwTab(String? source) {
    if (source == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = source.isEmpty ? 0 : _kwSourceList.indexOf(source) + 1;
      _focusKwTab(idx > 0 && idx < _kwTabNodes.length ? idx : 0);
    });
  }

  /// Turn a raw search exception into a short, human-readable message — matches
  /// the old screen's network/timeout/generic buckets.
  String _friendlyKeywordError(Object e) {
    final msg = e.toString().replaceAll('Exception: ', '');
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
      return 'Network error. Please check your connection.';
    }
    if (msg.contains('TimeoutException')) {
      return 'Search timed out. Please try again.';
    }
    if (msg.length > 100) return 'Search failed. Please try again.';
    return msg;
  }

  // ── Bulk selection (keyword results) ──────────────────────────────────────
  /// Torrents eligible for bulk actions (excludes direct/external streams).
  List<Torrent> get _kwSelectableResults => _kwResults
      .where((t) => !t.isDirectStream && !t.isExternalStream)
      .toList();

  void _enterKwSelection() {
    // Multi-select over a live-shifting list would let rows move under the
    // checkmarks — freeze and fold parked arrivals in first.
    _kwFreezeAndAdopt();
    // Entering selection swaps the toolbar to 3 pills; if DPAD focus was on the
    // now-gone "Select" pill (index 3), pull it back to the new first pill so
    // the remote doesn't lose focus.
    final refocusToolbar = _kwToolbarNodes.any((n) => n.hasFocus);
    setState(() {
      _kwSelectionMode = true;
      _kwSelected.clear();
    });
    if (refocusToolbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kwToolbarNodes.first.requestFocus();
      });
    }
  }

  void _exitKwSelection() {
    setState(() {
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
  }

  void _toggleKwSelection(Torrent t) {
    setState(() {
      if (_kwSelected.contains(t.infohash)) {
        _kwSelected.remove(t.infohash);
      } else {
        _kwSelected.add(t.infohash);
      }
    });
  }

  void _selectAllKw() {
    setState(() {
      _kwSelected
        ..clear()
        ..addAll(_kwSelectableResults.map((t) => t.infohash));
    });
  }

  /// Clear the selection but stay in selection mode (matches Home's "None").
  void _deselectAllKw() {
    setState(() => _kwSelected.clear());
  }

  bool _kwBulkBusy = false;

  Future<void> _openBulkAdd() async {
    if (_kwBulkBusy) return;
    final chosen = _kwResults
        .where((t) => _kwSelected.contains(t.infohash))
        .toList();
    if (chosen.isEmpty) return;
    _kwBulkBusy = true;
    bool chose = false;
    try {
      chose = await TorrentBulkAddService.showBulkAddDialog(
        context,
        torrents: chosen,
        keyword: _kwQuery,
      );
    } finally {
      _kwBulkBusy = false;
    }
    // Stay in selection mode if the user just dismissed the chooser.
    if (mounted && chose && _kwSelectionMode) _exitKwSelection();
  }

  /// True when [t] is (or is treated as) a direct/external URL stream rather
  /// than an addable torrent — used to bucket results into the provider groups.
  bool _kwIsDirect(Torrent t) => t.isDirectStream || t.isExternalStream;

  /// Action menu for a keyword-result direct/external stream row (parity with
  /// the old direct-stream action dialog): Play/Open, Copy URL, Download.
  void _showKwStreamMenu(Torrent t, int i) {
    final app = AppThemeScope.of(context);
    final external = t.isExternalStream;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded,
                color: app.core.tx,
              ),
              title: Text(external ? 'Open externally' : 'Play now'),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                unawaited(
                  TorrentPlaybackService.activateTorrent(
                    context,
                    t,
                    sources: _kwResults,
                    sourceIndex: i,
                    searchKeyword: _kwQuery,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xFFF59E0B)),
              title: const Text('Copy link'),
              onTap: () async {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                await _copyKwLink(t);
              },
            ),
            if (ProfilePolicyGuard.allowsSync(ProfileFeature.downloads))
              ListTile(
                leading: const Icon(
                  Icons.download_rounded,
                  color: Color(0xFF60A5FA),
                ),
                title: const Text('Download to device'),
                onTap: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(sheetCtx).pop();
                  unawaited(
                    TorrentPlaybackService.downloadDirectStream(context, t),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyKwLink(Torrent t) async {
    final link = t.copyLink;
    if (link == null) {
      _snack('No link available for this source.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) _snack('Link copied to clipboard');
  }

  /// Tally result counts per source, split into Direct vs Torrent groups, and
  /// default every source to selected. Mirrors the old `_calculateStreamTypeCounts`.
  void _computeKwProviders(List<Torrent> torrents) {
    final direct = <String, int>{};
    final torrent = <String, int>{};
    for (final t in torrents) {
      final src = _kwSourceOf(t);
      final bucket = _kwIsDirect(t) ? direct : torrent;
      bucket[src] = (bucket[src] ?? 0) + 1;
    }
    _kwDirectCounts = direct;
    _kwTorrentCounts = torrent;
    // Additive selection: a source never seen this search starts ticked, but
    // one the user unticked stays unticked when a later engine's batch
    // re-reports it — streaming recomputes must not wipe mid-search choices.
    // ([_kwProviderSeen] resets per search, so the first call ticks all.)
    for (final s in direct.keys) {
      if (_kwProviderSeen.add('d:$s')) _kwSelectedDirect.add(s);
    }
    for (final s in torrent.keys) {
      if (_kwProviderSeen.add('t:$s')) _kwSelectedTorrent.add(s);
    }
    // Prune sources that vanished from the merge (dedupe can reattribute a
    // source's only row to a higher-seeded copy) — stale selections corrupt
    // the Providers badge arithmetic and the dialog's All/None check. The
    // seen-key goes too, so a source that REAPPEARS auto-ticks like new.
    _kwSelectedDirect.removeWhere((s) => !direct.containsKey(s));
    _kwSelectedTorrent.removeWhere((s) => !torrent.containsKey(s));
    _kwProviderSeen.removeWhere(
      (k) => k.startsWith('d:')
          ? !direct.containsKey(k.substring(2))
          : !torrent.containsKey(k.substring(2)),
    );
  }

  /// TorBox-cached test used by the cached-only prefilter. Entries without a
  /// real infohash but with a torrent URL (direct links) are always kept, since
  /// they can't be cache-checked — matching the old screen.
  bool _kwIsTorboxCached(Torrent t) {
    if (!t.hasRealInfoHash && t.torrentUrl != null) return true;
    // Key exactly as the cache map is built and as rows render badges
    // (`infohash.toLowerCase()`, no trim) so the filter can't drop a torrent
    // that still shows a TB badge.
    final labels = _kwCache[t.infohash.toLowerCase()];
    return labels != null && labels.contains('TB');
  }

  /// Re-apply cached-only + provider + tab + attribute filters and sort to the
  /// last search's results, then sync focus nodes to the new length.
  void _recomputeKeyword() {
    Iterable<Torrent> base = _kwAll;
    // 1) TorBox cached-only prefilter (when active).
    if (_kwCachedOnly) {
      base = base.where(_kwIsTorboxCached);
    }
    // 2) Provider (stream-type) multi-select. An empty group map means that
    //    group has no providers, so it imposes no constraint on its members.
    if (_kwDirectCounts.isNotEmpty || _kwTorrentCounts.isNotEmpty) {
      base = base.where((t) {
        final src = _kwSourceOf(t);
        if (_kwIsDirect(t)) {
          return _kwDirectCounts.isEmpty || _kwSelectedDirect.contains(src);
        }
        return _kwTorrentCounts.isEmpty || _kwSelectedTorrent.contains(src);
      });
    }
    // 3) Source tab (single-select) narrows on top of the multi-select.
    final tab = _kwSourceTab;
    if (tab != null) {
      base = base.where((t) => _kwSourceOf(t) == tab);
    }
    // 4) Quality / rip-source / language attribute filters.
    final filtered = TorrentFilterMatcher.apply(base.toList(), _kwFilters);
    final sorted = _sortKeyword(filtered);
    _syncKwNodes(sorted.length);
    _syncKwTabNodes();
    setState(() => _kwResults = sorted);
  }

  /// Grows/shrinks [_kwNodes] to the target length without ever disposing the
  /// focused node unanchored. Removed nodes are disposed POST-FRAME — their
  /// row widgets are still mounted this frame, and unmounting a Focus widget
  /// whose node is already disposed asserts (same rule as the Sources list).
  void _syncKwNodes(int length) {
    while (_kwNodes.length < length) {
      _kwNodes.add(FocusNode(debugLabel: 'kw_${_kwNodes.length}'));
    }
    if (_kwNodes.length > length) {
      final removed = <FocusNode>[];
      while (_kwNodes.length > length) {
        final node = _kwNodes.removeLast();
        if (node.hasFocus && _kwNodes.isNotEmpty) _kwNodes.last.requestFocus();
        removed.add(node);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
  }

  /// Same grow/shrink discipline for the source-tab pills ("All" + one per
  /// source in [_kwSourceList]).
  void _syncKwTabNodes() {
    final want = _kwSourceList.length + 1;
    while (_kwTabNodes.length < want) {
      _kwTabNodes.add(FocusNode(debugLabel: 'kw_tab_${_kwTabNodes.length}'));
    }
    if (_kwTabNodes.length > want) {
      final removed = <FocusNode>[];
      while (_kwTabNodes.length > want) {
        final node = _kwTabNodes.removeLast();
        if (node.hasFocus && _kwTabNodes.isNotEmpty) {
          _kwTabNodes.last.requestFocus();
        }
        removed.add(node);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
  }

  List<Torrent> _sortKeyword(List<Torrent> list) {
    final l = [...list];
    // Direction multiplier: descending by default (asc flips it). 'name' compares
    // case-insensitively; the rest are numeric.
    final int dir = _kwSortAsc ? 1 : -1;
    switch (_kwSort) {
      case 'seeders':
        l.sort((a, b) => dir * a.seeders.compareTo(b.seeders));
        break;
      case 'size':
        l.sort((a, b) => dir * a.sizeBytes.compareTo(b.sizeBytes));
        break;
      case 'date':
        l.sort((a, b) => dir * a.createdUnix.compareTo(b.createdUnix));
        break;
      case 'name':
        l.sort(
          (a, b) =>
              dir *
              a.displayTitle.toLowerCase().compareTo(
                b.displayTitle.toLowerCase(),
              ),
        );
        break;
      default: // 'relevance' — keep the engine (seeder-deduped) order
        break;
    }
    return l;
  }

  /// Natural default direction for a sort field: names read A→Z (ascending);
  /// seeders/size/date read most/largest/newest first (descending).
  bool _naturalAscFor(String field) => field == 'name';

  /// Additive cache-check against TorBox/Premiumize (the only providers that
  /// support it), stamping TB/PM badges onto [torrents]' rows. Called per
  /// streaming batch and once as a completion sweep (via [_finalizeKeywordCache]).
  ///
  /// Results MERGE into [_kwCache] so earlier batches' badges survive. A hash is
  /// added to [_kwCacheChecked] ONLY after every enabled provider resolved for
  /// it — a thrown check leaves it un-memoized so a later batch or the finalize
  /// sweep re-queries it (a transient failure must not permanently drop rows).
  /// Cached-only mode is NOT decided here — see [_finalizeKeywordCache].
  Future<void> _checkKeywordCache(List<Torrent> torrents, int token) async {
    final hashes = <String>[];
    for (final t in torrents) {
      final h = t.infohash.toLowerCase();
      // contains (not add): dispatch every not-yet-confirmed hash; memoization
      // happens post-success below, so a failed hash stays retryable.
      if (h.isEmpty || _kwCacheChecked.contains(h)) continue;
      hashes.add(h);
    }
    if (hashes.isEmpty) return;
    final add = <String, List<String>>{};
    // A provider is "done" for these hashes when it's not enabled (nothing to
    // do) OR its check succeeded. Only when BOTH are done do we memoize.
    bool tbDone = !(_kwTbOn && _kwTbKey != null);
    bool pmDone = !(_kwPmOn && _kwPmKey != null);
    bool tbOk = false;
    if (_kwTbOn && _kwTbKey != null) {
      try {
        final cached = await TorboxService.checkCachedTorrents(
          apiKey: _kwTbKey!,
          infoHashes: hashes,
        );
        tbDone = true;
        tbOk = true;
        for (final h in cached) {
          (add[h] ??= <String>[]).add('TB');
        }
      } catch (_) {}
    }
    if (_kwPmOn && _kwPmKey != null) {
      try {
        final res = await PremiumizeService.checkCache(_kwPmKey!, hashes);
        pmDone = true;
        for (var i = 0; i < hashes.length && i < res.length; i++) {
          if (res[i]) (add[hashes[i]] ??= <String>[]).add('PM');
        }
      } catch (_) {}
    }
    // Guard BEFORE mutating any shared state so a superseded search's late
    // batch can't stamp badges, flip _kwTbRan, or memoize hashes for the new one.
    if (!mounted || token != _kwSearchToken) return;
    // A successful TorBox check is the precondition for cached-only mode (a
    // thrown check must NOT hide every result).
    if (tbOk) _kwTbRan = true;
    _kwCache.addAll(add);
    if (tbDone && pmDone) _kwCacheChecked.addAll(hashes);
    setState(() {});
  }

  /// Completion: wait for every in-flight batch check so [_kwCache] and
  /// [_kwTbRan] reflect the whole result set, sweep any hash a batch missed or
  /// whose check failed, THEN settle cached-only mode. Deferring the decision
  /// until the checks resolve is what prevents cached rows from being hidden by
  /// a not-yet-returned batch — the failure mode of settling it mid-flight.
  Future<void> _finalizeKeywordCache(List<Torrent> full, int token) async {
    try {
      await Future.wait(List<Future<void>>.from(_kwPendingChecks));
    } catch (_) {}
    if (!mounted || token != _kwSearchToken) return;
    // Retry any hash still un-memoized (never dispatched, or a failed check).
    await _checkKeywordCache(full, token);
    if (!mounted || token != _kwSearchToken) return;
    // Narrow to TorBox-cached torrents only when TorBox is the sole usable
    // provider. Any other active provider may be able to handle a result that
    // TorBox does not cache, so its rows must remain visible.
    final cachedOnly = _kwTbRan && !_kwOtherProviderActive;
    if (cachedOnly != _kwCachedOnly) {
      // Cached-only mode toggles the visible set → full recompute.
      _kwCachedOnly = cachedOnly;
      _recomputeKeyword();
    } else {
      // Badges-only update: the result list is unchanged, so just repaint the
      // cache labels. Rebuilding _kwNodes here (as a full recompute would) drops
      // TV DPAD focus off whatever row the user navigated to while the async
      // cache check was still in flight.
      setState(() {});
    }
  }

  Future<void> _openKeywordFilters() async {
    // Toolbar use is a deliberate reshuffle: stop live streaming updates and
    // fold parked arrivals in, so the dialog operates on the complete set.
    _kwFreezeAndAdopt();
    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(initialState: _kwFilters),
      ),
    );
    if (result == null || !mounted) return;
    _kwFilters = result;
    _recomputeKeyword();
  }

  /// Info banner shown above the results when the list is narrowed to
  /// TorBox-cached torrents. Mirrors the old `_buildTorboxCachedOnlyNotice`.
  Widget _kwCachedOnlyNotice() {
    final app = AppThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
        borderRadius: app.shape.br(8),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF38BDF8),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing Torbox cached results only. Disable "Check Torbox cache '
              'during searches" in Torbox settings to see every result.',
              style: TextStyle(
                fontSize: 12,
                color: app.fade(app.core.tx, 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// True when the provider (stream-type) filter is worth surfacing: at least
  /// two distinct sources exist across both groups, so filtering can change the
  /// result set. A single source imposes no meaningful choice.
  bool get _kwHasProviderFilter =>
      (_kwDirectCounts.length + _kwTorrentCounts.length) >= 2;

  /// Count of source groups the user has narrowed away from "all selected" —
  /// drives the active state / badge on the Providers pill.
  int get _kwProviderFilterActive {
    var n = 0;
    if (_kwDirectCounts.isNotEmpty &&
        _kwSelectedDirect.length != _kwDirectCounts.length) {
      n += _kwDirectCounts.length - _kwSelectedDirect.length;
    }
    if (_kwTorrentCounts.isNotEmpty &&
        _kwSelectedTorrent.length != _kwTorrentCounts.length) {
      n += _kwTorrentCounts.length - _kwSelectedTorrent.length;
    }
    return n;
  }

  /// Multi-select dialog to filter keyword results by their source, grouped into
  /// Direct and Torrent providers. Ported from the old screen's stream-type
  /// dropdowns, adapted to the new toolbar/dialog idiom.
  Future<void> _openKeywordProviders() async {
    // Freeze + adopt so the provider counts reflect everything found so far.
    _kwFreezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void apply(VoidCallback mutate) {
              setLocal(mutate);
              _recomputeKeyword();
            }

            Widget group(
              String title,
              Map<String, int> counts,
              Set<String> selected,
            ) {
              if (counts.isEmpty) return const SizedBox.shrink();
              final entries = counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final allOn = selected.length == counts.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => apply(() {
                            if (allOn) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..addAll(counts.keys);
                            }
                          }),
                          child: Text(allOn ? 'None' : 'All'),
                        ),
                      ],
                    ),
                  ),
                  ...entries.map(
                    (e) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.contains(e.key),
                      title: Text(
                        e.key,
                        style: TextStyle(fontSize: 13, color: scheme.onSurface),
                      ),
                      secondary: Text(
                        '${e.value}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      onChanged: (_) => apply(() {
                        if (selected.contains(e.key)) {
                          selected.remove(e.key);
                        } else {
                          selected.add(e.key);
                        }
                      }),
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: const Text('Filter by source'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      group('Direct', _kwDirectCounts, _kwSelectedDirect),
                      group('Torrent', _kwTorrentCounts, _kwSelectedTorrent),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openKeywordSort() async {
    // Sorting mid-stream over a shifting set would be meaningless — freeze
    // and fold parked arrivals in first.
    _kwFreezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            // Picking a field resets direction to that field's natural default;
            // the toggle below can then flip it. Changes apply live.
            void applyField(String value) {
              setLocal(() {
                _kwSort = value;
                _kwSortAsc = _naturalAscFor(value);
              });
              _recomputeKeyword();
            }

            void applyDir(bool asc) {
              setLocal(() => _kwSortAsc = asc);
              _recomputeKeyword();
            }

            Widget tile(String value, String label) => ListTile(
              dense: true,
              title: Text(label),
              trailing: _kwSort == value
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => applyField(value),
            );

            final dirEnabled = _kwSort != 'relevance';
            return AlertDialog(
              backgroundColor: scheme.surfaceContainerHigh,
              title: const Text('Sort by'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tile('relevance', 'Relevance'),
                  tile('seeders', 'Seeders'),
                  tile('size', 'Size'),
                  tile('date', 'Date added'),
                  tile('name', 'Name'),
                  const Divider(height: 12),
                  // Direction toggle — disabled for 'relevance' (engine order).
                  Opacity(
                    opacity: dirEnabled ? 1 : 0.4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Direction')),
                          ToggleButtons(
                            isSelected: [!_kwSortAsc, _kwSortAsc],
                            onPressed: dirEnabled
                                ? (i) => applyDir(i == 1)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            constraints: const BoxConstraints(
                              minHeight: 34,
                              minWidth: 46,
                            ),
                            children: const [
                              Icon(Icons.arrow_downward_rounded, size: 18),
                              Icon(Icons.arrow_upward_rounded, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openKeywordSources() async {
    // If the remote was on the toolbar, the re-search below unmounts it (loading
    // spinner) and would strand DPAD focus — restore it at the FIRST streamed
    // paint (see _kwRefocusToolbar), when the toolbar remounts. A completion
    // refocus would arrive seconds after rows became interactive and could
    // yank the remote off a row the user had already navigated to.
    final fromToolbar = _kwToolbarNodes.any((n) => n.hasFocus);
    await showDialog<void>(
      context: context,
      builder: (_) => const _KeywordSourcesDialog(),
    );
    if (!mounted || _kwQuery.isEmpty) return;
    // Re-search with the new enabled set.
    await _runKeyword(_kwQuery, refocusToolbar: fromToolbar);
  }

  void _disposeKwNodes() {
    for (final n in _kwNodes) {
      n.dispose();
    }
    _kwNodes.clear();
  }

  void _switchMode(_Mode mode) {
    // Belt for every entry point at once: the keyword surface is gated per
    // profile (catalog search never is).
    if (mode == _Mode.keyword &&
        !ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)) {
      return;
    }
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      // Leaving the keyword list drops any in-progress multi-selection.
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
    // Carry the typed query across: if there's text in the box, run the target
    // mode's search immediately instead of showing the empty state.
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    switch (mode) {
      case _Mode.keyword:
        if (query != _kwQuery) _runKeyword(query);
        return;
      case _Mode.catalog:
        if (query != _catalogQuery) _runCatalogSearch(query);
        return;
      case _Mode.lists:
        if (query != _listsQuery) _runListsSearch(query);
        return;
    }
  }

  // ── Playback / detail delegation ───────────────────────────────────────────

  /// Load the experimental merged-series-page flag once on init.
  Future<void> _loadMergedSeriesFlag() async {
    final on = await StorageService.getMergedSeriesPageEnabled();
    if (mounted && on != _mergedSeriesPage) {
      setState(() => _mergedSeriesPage = on);
    }
  }

  void _openItem(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Shared-element tag from the tapped board cell: the poster flies into the
    // detail page's backdrop. Null (non-board callers) = regular transition.
    String? heroTag,
    // For a series opened at a specific episode (Trakt Calendar): scroll the
    // episodes panel to this season/episode. Ignored by the movie/legacy paths.
    int? initialSeason,
    int? initialEpisode,
    // When set, switch back to this tab once the detail route closes — lets a
    // cross-tab opener (the Calendar) return the user to where they came from.
    int? returnToTabOnClose,
  }) {
    _activeAddonId = addon.id;
    final imdb = _imdbOf(item);
    // Show a "Remove from Continue Watching" action when this title is on the
    // Continue Watching row (regardless of which row opened it).
    final inCw = imdb != null && _cwIds.contains(imdb);
    // Same for the Trakt Continue Watching rows — removal goes through the
    // Trakt playback/history APIs rather than local storage.
    final inTraktCw = imdb != null && _traktByImdb.containsKey(imdb);
    final inMdblistCw = imdb != null && _mdblistByImdb[imdb]?.paused == true;

    // Full quick-actions menu, mirroring the catalog/aggregated detail screens:
    // app actions (Select Source, Add to Stremio TV, Search Packs, Random
    // Episode) always, Trakt-syncing actions only when connected — plus Remove
    // for Continue Watching titles.
    // Build the quick-actions strip against a (possibly still-unknown) Trakt
    // status. Called with null for the initial/legacy add-only strip, then
    // rebuilt by the merged page once `traktStatusLoader` resolves — so
    // watchlist/collection/rating entries flip to their Remove form when the
    // title is already there.
    final app = AppThemeScope.of(context);
    List<TraktMenuOption> buildMenuOptions(
      TraktTitleStatus? status,
    ) => <TraktMenuOption>[
      ...buildTraktAddOnlyMenuOptions(
        isSeries: item.type == 'series',
        isMovie: item.type == 'movie',
        hasBoundSource: _isBound(item),
        // The Trakt-syncing actions key off the IMDb id, so only offer them
        // for titles that have one (else the sync call fails with an error).
        isTraktAuthenticated: _isTraktAuthenticated && imdb != null,
        status: status,
      ),
      if (inCw)
        TraktMenuOption(
          action: TraktItemMenuAction.removeFromPlayback,
          icon: Icons.delete_sweep_rounded,
          color: app.home.danger,
          label: 'Remove from Continue Watching',
          caption: 'Remove',
        ),
      if (inTraktCw)
        TraktMenuOption(
          action: TraktItemMenuAction.removeFromTraktPlayback,
          icon: Icons.remove_circle_outline_rounded,
          color: app.home.danger,
          label: 'Remove from Trakt Continue Watching',
          caption: 'Remove',
          isTrakt: true,
        ),
    ];
    // Static (status-unknown) strip — the fallback for the merged page until its
    // status loads, and the only strip the legacy CatalogItemDetailScreen uses.
    final options = buildMenuOptions(null);

    // Simkl's own strip — built and rendered entirely separately from Trakt's
    // above (see the Simkl integration plan: parallel, not merged). Gated on
    // connection state the same way the Trakt strip is (isTraktAuthenticated
    // above) — buildSimklMenuOptions itself returns empty when disconnected.
    List<SimklMenuOption> buildSimklOptions(SimklTitleStatus? status) =>
        buildSimklMenuOptions(
          isSeries: item.type == 'series',
          isSimklAuthenticated: _isSimklAuthenticated && imdb != null,
          // Offer "Remove from Continue Watching" for a paused entry (movie or
          // series) — it has a session to delete. Not for "up next" entries
          // (progress null, no session; they leave via a status change). For a
          // series the remove also moves it to On Hold so it doesn't re-surface
          // as an up-next card (see handleSimklMenuAction).
          inContinueWatching:
              imdb != null && (_simklByImdb[imdb]?.progress != null),
          status: status,
        );
    final simklOptions = buildSimklOptions(null);

    List<MdblistMenuOption> buildMdblistOptions(MdblistTitleStatus? status) =>
        buildMdblistMenuOptions(
          authenticated: _isMdblistAuthenticated && imdb != null,
          isSeries: item.type == 'series',
          inContinueWatching: inMdblistCw,
          status: status,
        );
    final mdblistOptions = buildMdblistOptions(null);

    // Experimental: series route to the merged detail+episodes page. Movies and
    // the flag-off path fall through to the existing CatalogItemDetailScreen.
    if ((item.type == 'series' || item.type == 'movie') && _mergedSeriesPage) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              settings: const RouteSettings(name: kCatalogDetailRouteName),
              builder: (_) => MergedDetailScreen(
                item: item,
                addon: addon,
                isTelevision: widget.isTelevision,
                // PikPak quick-plays fine here: onResume → _onCatalogPlay →
                // _playSelection → TorrentPlaybackService.playFromSelection
                // already handles PikPak (same path the episode tiles use, which
                // stay quick-play-enabled for PikPak-only). It queues an offline
                // download and surfaces "still processing" if not ready — same
                // behaviour as the tiles, so the hero button matches them.
                showQuickPlay: true,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
                heroTag: heroTag,
                initialSeason: initialSeason,
                initialEpisode: initialEpisode,
                resumeInfoLoader: () => _resolveResumeInfo(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                ),
                onResume: (promised) => _onCatalogPlay(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                  skipEpisodeFallback: true,
                  // The merged page resolves its own episode target (it can see
                  // watched state the reconciler can't) — Play must land on the
                  // episode its label is showing.
                  promisedTarget: promised,
                  // Play the Trakt paused episode when the Trakt-first label
                  // shows one, so the button and the action agree.
                  preferTraktResume: true,
                ),
                // Movie only: the Sources (manual list) button.
                onBrowse: item.type == 'movie'
                    ? () => _onCatalogBrowse(
                        item,
                        addon,
                        isTraktSource: isTraktSource,
                        isMdblistSource: isMdblistSource,
                      )
                    : null,
                onItemSelected: _browseSelection,
                onQuickPlay: _playSelection,
                onBrowsePrimaryEpisodeSources: (promised) => _onCatalogPlay(
                  item,
                  addon,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                  skipEpisodeFallback: true,
                  preferTraktResume: true,
                  promisedTarget: promised,
                  browseSourcesOnly: true,
                ),
                boundSourceCount: _boundCountFor,
                onSelectSource: _handleEditOrSelectSource,
                traktMenuOptions: options,
                traktMenuBuilder: buildMenuOptions,
                // Live Trakt status (in watchlist / collection / watched /
                // rating) — only when connected and the title has an IMDb id.
                traktStatusLoader: (_isTraktAuthenticated && imdb != null)
                    ? () => TraktService.instance.fetchTitleStatus(
                        imdb,
                        item.type,
                      )
                    : null,
                onTraktAction: (a) => _handleDetailQuickAction(
                  item,
                  addon,
                  a,
                  inCw: inCw,
                  imdb: imdb,
                ),
                // Inline 1–10 strips in the tracker sheets: same handler, with
                // the score already chosen so no dialog opens.
                onTraktRate: (r) => _handleDetailQuickAction(
                  item,
                  addon,
                  TraktItemMenuAction.rate,
                  inCw: inCw,
                  imdb: imdb,
                  presetRating: r,
                ),
                onSimklRate: (r) => _handleDetailSimklQuickAction(
                  item,
                  SimklItemMenuAction.rate,
                  presetRating: r,
                ),
                simklMenuOptions: simklOptions,
                simklMenuBuilder: buildSimklOptions,
                // Live Simkl status (current watchlist status + rating) —
                // only when connected and the title has an IMDb id.
                simklStatusLoader: (_isSimklAuthenticated && imdb != null)
                    ? () => SimklService.instance.fetchTitleStatus(imdb)
                    : null,
                onSimklAction: (a) => _handleDetailSimklQuickAction(item, a),
                mdblistMenuOptions: mdblistOptions,
                mdblistMenuBuilder: buildMdblistOptions,
                mdblistStatusLoader: (_isMdblistAuthenticated && imdb != null)
                    ? () => MdblistService.instance.fetchTitleStatus(
                        imdb,
                        item.type,
                      )
                    : null,
                onMdblistAction: (a) =>
                    _handleDetailMdblistQuickAction(item, a),
                onMdblistRate: (rating) => _handleDetailMdblistQuickAction(
                  item,
                  MdblistItemMenuAction.rate,
                  presetRating: rating,
                ),
                recommendationsLoader: imdb != null
                    ? () => _stremio.getRecommendations(
                        imdbId: imdb,
                        type: item.type,
                      )
                    : null,
                onRecommendationTap: imdb != null
                    ? (rec) => _openItem(rec, rec.sourceAddon ?? addon)
                    : null,
                metaEnricher: (id, type) =>
                    _stremio.fetchMetaDetails(imdbId: id, type: type),
              ),
            ),
          )
          // Playback (or a bind/unbind) may have happened inside the detail
          // flow — _refreshAfterPlayback covers the tracker rows too, and
          // sequences the bound-source pass after the CW reloads.
          .then((_) {
            unawaited(_refreshAfterPlayback());
            _refreshTraktAuthState();
            _refreshSimklAuthState();
            _refreshMdblistAuthState();
            if (returnToTabOnClose != null) {
              MainPageBridge.switchTab?.call(returnToTabOnClose);
            }
          });
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kCatalogDetailRouteName),
            builder: (_) => CatalogItemDetailScreen(
              // Keep the originating addon with the locally-saved My
              // Watchlist row so reopening it can route to the same source.
              item: StorageService.withMyWatchlistSource(item, addon),
              isTelevision: widget.isTelevision,
              // Hide "Play" when PikPak is the only provider — no quick-play.
              showQuickPlay: !_pikpakOnly,
              // Gold-tint the Sources button when a source is already pinned.
              hasBoundSource: _isBound(item),
              resumeInfoLoader: () => _resolveResumeInfo(
                item,
                addon,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
              ),
              // preferTraktResume: this screen's resumeInfoLoader is the same
              // Trakt-authoritative _resolveResumeInfo the merged page uses, so
              // Play must honour the Trakt position too or the button label and
              // playback diverge (button "Resume · S3E4" vs local S01E01).
              onPlay: () => _onCatalogPlay(
                item,
                addon,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
                preferTraktResume: true,
              ),
              // Enriched backdrop/logo/meta for the Marquee play loader —
              // the catalog row that opened this page rarely has any of it.
              onLoaderArt: (art) => _adoptDetailPlayArt(item, art),
              onBrowse: () => _onCatalogBrowse(
                item,
                addon,
                isTraktSource: isTraktSource,
                isMdblistSource: isMdblistSource,
              ),
              onBrowsePrimaryEpisodeSources: item.type == 'series'
                  ? () => _onCatalogPlay(
                      item,
                      addon,
                      isTraktSource: isTraktSource,
                      isMdblistSource: isMdblistSource,
                      skipEpisodeFallback: true,
                      preferTraktResume: true,
                      browseSourcesOnly: true,
                    )
                  : null,
              traktMenuOptions: options,
              onTraktAction: (a) => _handleDetailQuickAction(
                item,
                addon,
                a,
                inCw: inCw,
                imdb: imdb,
              ),
              simklMenuOptions: simklOptions,
              onSimklAction: (a) => _handleDetailSimklQuickAction(item, a),
              mdblistMenuOptions: mdblistOptions,
              onMdblistAction: (a) => _handleDetailMdblistQuickAction(item, a),
              // Live Simkl status — relabels Play → "Rewatch" for a completed
              // movie (matches the merged detail page's simklStatusLoader).
              simklStatusLoader: (_isSimklAuthenticated && imdb != null)
                  ? () => SimklService.instance.fetchTitleStatus(imdb)
                  : null,
              // "More Like This" rail + sparse-item meta backfill, matching the
              // catalog detail flow.
              recommendationsLoader: imdb != null
                  ? () => _stremio.getRecommendations(
                      imdbId: imdb,
                      type: item.type,
                    )
                  : null,
              onRecommendationTap: imdb != null
                  ? (rec) => _openItem(rec, rec.sourceAddon ?? addon)
                  : null,
              metaEnricher: (id, type) =>
                  _stremio.fetchMetaDetails(imdbId: id, type: type),
            ),
          ),
        )
        // A bind/unbind may have happened inside the detail flow; playback may
        // also have changed Continue Watching progress (local AND tracker rows
        // — see _refreshAfterPlayback).
        .then((_) {
          unawaited(_refreshAfterPlayback());
          _refreshTraktAuthState();
          _refreshSimklAuthState();
          _refreshMdblistAuthState();
          if (returnToTabOnClose != null) {
            MainPageBridge.switchTab?.call(returnToTabOnClose);
          }
        });
  }

  /// Dispatch a detail-screen quick action. Reuses the shared
  /// [handleTraktMenuAction] for the standard actions and handles the
  /// Continue-Watching removal locally. The detail page stays underneath (like
  /// Play/Sources), so Back returns to it.
  Future<void> _handleDetailQuickAction(
    StremioMeta item,
    StremioAddon addon,
    TraktItemMenuAction action, {
    required bool inCw,
    String? imdb,
    // Set by the merged detail sheet's inline rating strip, which already knows
    // the score — skips the rating dialog rather than asking twice.
    int? presetRating,
  }) async {
    if (action == TraktItemMenuAction.removeFromPlayback) {
      if (imdb != null) await _handleContinueDetailAction(action, imdb);
      return;
    }
    if (action == TraktItemMenuAction.removeFromTraktPlayback) {
      if (imdb != null) await _removeFromTraktContinueWatching(imdb);
      return;
    }
    await handleTraktMenuAction(
      context,
      item,
      action,
      // "Select Source" when nothing is bound → straight to the picker; when a
      // source is already bound → the rich edit dialog (list / reorder / remove
      // / add). Matches the catalog/aggregated detail flow.
      onSelectSource: _openBindSources,
      onEditSource: _handleEditOrSelectSource,
      onPlayRandomEpisode: (m) => _playRandomEpisodeFromDetail(m, addon),
      onSearchPacks: _searchPacksFromDetail,
      onAddToStremioTv: _addToStremioTvFromDetail,
      presetRating: presetRating,
    );
    // A Trakt watched-state change moves a title in/out of Continue Watching,
    // so reload the board's Trakt rows — otherwise the board is stale when the
    // user backs out of the detail (old home reloads its list after these).
    // Skipped on the dedicated Search tab, which never renders those rows.
    if (mounted &&
        !widget.searchMode &&
        (action == TraktItemMenuAction.markWatched ||
            action == TraktItemMenuAction.markUnwatched)) {
      _loadTraktContinueWatching(refreshBound: false);
    }
  }

  /// Dispatch a detail-screen Simkl quick action — mirrors
  /// [_handleDetailQuickAction], simpler since Simkl's menu has no app
  /// actions (Select Source etc.) or Continue-Watching removal to special-case.
  Future<void> _handleDetailSimklQuickAction(
    StremioMeta item,
    SimklItemMenuAction action, {
    int? presetRating,
  }) async {
    await handleSimklMenuAction(
      context,
      item,
      action,
      presetRating: presetRating,
    );
    // Any status change can add/remove a title from the Simkl CW rows: On Hold
    // and remove/completed/dropped take it OFF, while Watching makes a series
    // newly eligible as an "up next" card. So reload the rows on every one that
    // shifts CW membership. Skipped on the dedicated Search tab (no rows there).
    if (mounted &&
        !widget.searchMode &&
        (action == SimklItemMenuAction.removeFromContinueWatching ||
            action == SimklItemMenuAction.removeFromList ||
            action == SimklItemMenuAction.moveToCompleted ||
            action == SimklItemMenuAction.moveToDropped ||
            action == SimklItemMenuAction.moveToOnHold ||
            action == SimklItemMenuAction.moveToWatching)) {
      _loadSimklContinueWatching(refreshBound: false);
    }
  }

  Future<void> _handleDetailMdblistQuickAction(
    StremioMeta item,
    MdblistItemMenuAction action, {
    int? presetRating,
  }) async {
    if (action == MdblistItemMenuAction.removeFromContinueWatching) {
      await _removeMdblistCwItem(item);
      return;
    }
    await handleMdblistMenuAction(
      context,
      item,
      action,
      presetRating: presetRating,
    );
    if (!mounted || widget.searchMode) return;
    if (action == MdblistItemMenuAction.markWatched ||
        action == MdblistItemMenuAction.markUnwatched ||
        action == MdblistItemMenuAction.drop ||
        action == MdblistItemMenuAction.restore) {
      await _loadMdblistContinueWatching(refreshBound: false);
    }
  }

  /// "Select/Edit Source" entry: edit dialog when a source is already bound,
  /// otherwise the add-source picker.
  Future<void> _handleEditOrSelectSource(StremioMeta item) async {
    final imdb = _imdbOf(item);
    final bound = imdb == null
        ? const <SeriesSource>[]
        : await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    if (bound.isNotEmpty) {
      await _showEditSourceDialog(item, bound);
    } else {
      await _showAddSourcePicker(item);
    }
  }

  /// Manage the bound sources for [item]: list them, reorder by priority
  /// (series — first match wins), delete individually, Remove All, or add
  /// another via the picker. Ported from the catalog/aggregated detail flow.
  Future<void> _showEditSourceDialog(
    StremioMeta item,
    List<SeriesSource> initial,
  ) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    final isMovie = item.type == 'movie';
    final sources = List<SeriesSource>.of(initial);
    if (sources.isEmpty) return;

    // [closeIfEmpty] pops the dialog via its OWN route (passed in from the
    // builder) when the last source is removed — robust to nested navigators,
    // and a callback (not a BuildContext) so it's safe across the awaits here.
    Future<void> refreshInto(
      void Function(void Function()) setDialogState,
      VoidCallback closeIfEmpty,
    ) async {
      final updated = await SeriesSourceService.getSources(imdbId);
      if (!mounted) return;
      setDialogState(() {
        sources
          ..clear()
          ..addAll(updated);
      });
      await _refreshBoundSources();
      if (updated.isEmpty) closeIfEmpty();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final app = AppThemeScope.of(dialogContext);
            void closeIfEmpty() {
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            }

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: isMovie
                            ? ListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                      key: ValueKey(sources[index].bindingKey),
                                      source: sources[index],
                                      index: index,
                                      showDragHandle: false,
                                      onDelete: () async {
                                        await SeriesSourceService.removeSourceEntry(
                                          imdbId,
                                          sources[index],
                                        );
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                        );
                                      },
                                    ),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                onReorder: (oldIndex, newIndex) {
                                  if (newIndex > oldIndex) newIndex--;
                                  setDialogState(() {
                                    final moved = sources.removeAt(oldIndex);
                                    sources.insert(newIndex, moved);
                                  });
                                  SeriesSourceService.setSources(
                                    imdbId,
                                    List.of(sources),
                                  );
                                  _refreshBoundSources();
                                },
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                      color: Colors.transparent,
                                      elevation: 4,
                                      child: child,
                                    ),
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                      key: ValueKey(sources[index].bindingKey),
                                      source: sources[index],
                                      index: index,
                                      onDelete: () async {
                                        await SeriesSourceService.removeSourceEntry(
                                          imdbId,
                                          sources[index],
                                        );
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                        );
                                      },
                                    ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _showAddSourcePicker(item);
                              },
                              icon: Icon(
                                isMovie
                                    ? Icons.swap_horiz_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isMovie ? 'Change Source' : 'Add Source',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: app.shape.br(10),
                                ),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  await _refreshBoundSources();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                  color: app.home.danger,
                                ),
                                label: Text(
                                  'Remove All',
                                  style: TextStyle(color: app.home.danger),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: app.home.danger,
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: app.shape.br(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (isMovie) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  await _refreshBoundSources();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: app.home.danger,
                                ),
                                label: Text(
                                  'Remove',
                                  style: TextStyle(color: app.home.danger),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: app.home.danger,
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: app.shape.br(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Add-source picker: Torrent Search (imdb) / Keyword Search (free-text) /
  /// Local file plus every configured cloud provider.
  Future<void> _showAddSourcePicker(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) {
      _snack('No IMDb match to pin a source for "${item.name}".');
      return;
    }
    // Capture the navigator before the awaits so the RD/TorBox push closures
    // don't reference `context` across an async gap.
    final navigator = Navigator.of(context);
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final premiumizeIntegration =
        await StorageService.getPremiumizeIntegrationEnabled();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;
    final premiumizeEnabled =
        premiumizeIntegration &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridEnabled = allDebridKey != null && allDebridKey.isNotEmpty;
    if (!mounted) return;

    final isMovie = item.type == 'movie';
    final supportsLocal = !LocalBoundSourceService.isLocalBindingDisabled;

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
      await _refreshBoundSources();
    }

    // No cloud providers and no local option → go straight to torrent search.
    if (!rdEnabled &&
        !torboxEnabled &&
        !premiumizeEnabled &&
        !allDebridEnabled &&
        !pikpakEnabled &&
        !supportsLocal) {
      _openBindSources(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => _openBindSources(item),
      onKeywordSearch: () => _openKeywordBind(item),
      onLocal: supportsLocal ? () => _pickAndSaveLocalSource(item) : null,
      localDisabledReason: LocalBoundSourceService.localDisabledReason,
      onRealDebrid: rdEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => DebridDownloadsScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
      onTorbox: torboxEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => TorboxDownloadsScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
      onPremiumize: premiumizeEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => PremiumizeFilesScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
      onAllDebrid: allDebridEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => AllDebridFilesScreen(
                  isPushedRoute: true,
                  initialSearchQuery: item.name,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
      onPikPak: pikpakEnabled
          ? () => navigator.push(
              MaterialPageRoute(
                builder: (_) => PikPakFilesScreen(
                  isPushedRoute: true,
                  selectSourceMode: true,
                  onSourceSelected: saveSource,
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _pickAndSaveLocalSource(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await LocalBoundSourceService.pickSeriesSource(
        context,
        title: item.name,
      );
    } else {
      source = await LocalBoundSourceService.pickMovieSource(
        context,
        title: item.name,
        year: item.year,
      );
    }
    if (source == null) return;
    if (item.type == 'series') {
      await SeriesSourceService.addSource(imdbId, source);
    } else {
      await SeriesSourceService.setSources(imdbId, [source]);
    }
    await _refreshBoundSources();
    if (!mounted) return;
    _snack('Local source set: ${source.torrentName}');
  }

  /// One bound-source row for the edit dialog (index badge, name, provider
  /// chip, delete). Ported from the catalog/aggregated detail flow.
  Widget _buildSourceListTile({
    required Key key,
    required SeriesSource source,
    required int index,
    required VoidCallback onDelete,
    bool showDragHandle = true,
  }) {
    final app = AppThemeScope.of(context);
    Color serviceColor;
    String serviceLabel;
    switch (source.debridService) {
      case 'rd':
        serviceColor = const Color(0xFF10B981);
        serviceLabel = 'Real-Debrid';
      case 'torbox':
        serviceColor = const Color(0xFF3B82F6);
        serviceLabel = 'TorBox';
      case 'pikpak':
        serviceColor = const Color(0xFFF59E0B);
        serviceLabel = 'PikPak';
      case 'premiumize':
        serviceColor = const Color(0xFFFB923C);
        serviceLabel = 'Premiumize';
      case 'alldebrid':
        serviceColor = const Color(0xFF26A69A);
        serviceLabel = 'AllDebrid';
      case SeriesSource.localService:
        serviceColor = const Color(0xFF60A5FA);
        serviceLabel = 'Local';
      case SeriesSource.addonDirectService:
        serviceColor = const Color(0xFFA78BFA);
        serviceLabel = 'Direct addon';
      default:
        serviceColor = Colors.white54;
        serviceLabel = source.debridService;
    }

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, 0.05),
        borderRadius: app.shape.br(8),
        border: Border.all(color: app.fade(app.core.tx, 0.08)),
      ),
      child: Row(
        children: [
          if (showDragHandle) ...[
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
                borderRadius: app.shape.br(6),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.torrentName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: app.shape.br(3),
                  ),
                  child: Text(
                    serviceLabel,
                    style: TextStyle(
                      color: serviceColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 16, color: app.home.danger),
            onPressed: onDelete,
            tooltip: 'Remove source',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (showDragHandle)
            Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: app.core.tx.withValues(alpha: 0x3D / 0xFF),
            ),
        ],
      ),
    );
  }

  Future<void> _addToStremioTvFromDetail(StremioMeta item) async {
    final result = await StremioTvCatalogPickerDialog.show(context, item: item);
    if (!mounted || result == null) return;
    _snack(result.message);
  }

  void _searchPacksFromDetail(StremioMeta item) {
    final imdb = _imdbOf(item);
    if (imdb == null) {
      _snack('No IMDb match to find packs for "${item.name}".');
      return;
    }
    _browseSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  /// Resolve a meta-capable addon (for episode listings): the preferred addon
  /// if it serves meta, otherwise the first enabled addon that does.
  Future<StremioAddon?> _metaAddonFor(StremioAddon preferred) async {
    if (preferred.resources.contains('meta') && preferred.baseUrl.isNotEmpty) {
      return preferred;
    }
    for (final a in await _stremio.getEnabledAddons()) {
      if (a.resources.contains('meta') && a.baseUrl.isNotEmpty) return a;
    }
    return null;
  }

  Future<void> _playRandomEpisodeFromDetail(
    StremioMeta item,
    StremioAddon addon,
  ) async {
    final imdb = _imdbOf(item);
    if (imdb == null) {
      _snack('No IMDb match to pick an episode for "${item.name}".');
      return;
    }
    final metaAddon = await _metaAddonFor(addon);
    // If we fell back to a different meta addon than the item's origin, its
    // content id won't match — query by IMDb id instead of the origin's id.
    final contentId = (metaAddon != null && metaAddon.id == addon.id)
        ? item.id
        : imdb;
    final videos = metaAddon == null
        ? null
        : await _stremio.fetchSeriesMeta(metaAddon, contentId);
    if (!mounted) return;
    if (videos != null) {
      unawaited(
        LocalSeriesCompletionService.instance.recordRawEpisodeInventory(
          imdbId: imdb,
          seriesTitle: item.name,
          videos: videos,
        ),
      );
    }

    final episodes = <({int season, int episode})>[];
    for (final v in videos ?? const <Map<String, dynamic>>[]) {
      final sRaw = v['season'];
      final s = sRaw is num ? sRaw.toInt() : null;
      if (s == null || s <= 0) continue; // skip specials (season 0)
      final eRaw = v['number'] ?? v['episode'];
      final e = eRaw is num ? eRaw.toInt() : null;
      if (e == null) continue;
      episodes.add((season: s, episode: e));
    }
    if (episodes.isEmpty) {
      _snack("Couldn't load episodes for \"${item.name}\".");
      return;
    }

    final pick = episodes[Random().nextInt(episodes.length)];
    _playSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: pick.season,
        episode: pick.episode,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  // Catalog Play = auto-best in-tab; Sources = manual list in-tab. For a series
  // Play auto-plays the resume episode (last-played by imdbId → title, else
  // S01E01) — the Episodes button is the manual picker. Nothing jumps to Home.
  Future<void> _onCatalogPlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Merged series page: episodes are already shown inline, so a no-IMDb
    // series must NOT fall back to pushing a standalone EpisodesScreen (that
    // would stack a duplicate episode list on top). It resolves the resume
    // episode against the raw catalog id and plays via the addon /stream path.
    bool skipEpisodeFallback = false,
    // Merged detail Resume: honour Trakt's paused position for ANY authenticated
    // title (not just Trakt-CW-sourced ones), so Play matches the Trakt-first
    // label from [_resolveResumeInfo]. Off elsewhere (Home/row quick-play keep
    // their local-vs-Trakt-CW split untouched).
    bool preferTraktResume = false,
    // The episode the pressed button was promising, when the caller had already
    // resolved one (merged detail). It wins over [_reconcileSeriesResume]: that
    // reconciler only reads resume/CW positions, while the merged page's episode
    // engine also advances off watched state. A show whose progress lives in a
    // tracker's WATCHED list but not its continue-watching list reconciles to the
    // empty-candidates fallback (S01E01) while the label correctly reads S1E2 —
    // and Play would then start the pilot under a "Resume · S1E2" button.
    ({bool started, int season, int episode})? promisedTarget,
    // Primary-button hold: run the exact same target/scrobble reconciliation,
    // but hand the resulting selection to the manual Sources page instead of
    // auto-playing it. Used for series; movies already have a direct Sources
    // callback and do not need to enter this resolver.
    bool browseSourcesOnly = false,
  }) async {
    final trackingPolicy = await TrackingSourcePolicy.load();
    debugPrint(
      '[SeriesResume] play-pressed title="${item.name}" '
      'id=${item.effectiveImdbId ?? item.id} type=${item.type} '
      'traktSource=$isTraktSource mdblistSource=$isMdblistSource '
      'preferTrackerResume=$preferTraktResume',
    );
    // The loader's backdrop/logo/meta line for this title. Captured here (the
    // one play entry point that still holds the catalog meta) and read back in
    // [_metaFor], which only ever sees a selection.
    _capturePlayArt(item);
    var cancelled = false;
    final resolving = preferTraktResume
        ? TorrentPlaybackService.showResolvingOverlay(
            context,
            meta: PlaybackMeta.catalog(
              imdbId: item.effectiveImdbId,
              contentType: item.type,
              title: item.name,
              posterUrl: item.poster,
              year: item.year,
              addonId: addon.id,
              art: _pendingPlayArt,
            ),
            title: item.name,
            onCancel: () => cancelled = true,
          )
        : null;
    Future<void> launch(AdvancedSearchSelection selection) async {
      debugPrint(
        '[SeriesResume] ${browseSourcesOnly ? 'sources-open' : 'play-launch'} '
        'title="${selection.title}" '
        'id=${selection.imdbId} season=${selection.season} '
        'episode=${selection.episode} trakt=${selection.traktSource} '
        'traktPct=${selection.traktProgressPercent} '
        'simkl=${selection.simklSource} '
        'simklPct=${selection.simklProgressPercent} '
        'mdblist=${selection.mdblistSource} '
        'mdblistPct=${selection.mdblistProgressPercent}',
      );
      resolving?.dismiss();
      if (cancelled) return;
      if (browseSourcesOnly) {
        _browseSelection(selection);
      } else {
        await _playSelection(selection);
      }
    }

    try {
      // Set the active addon before any early return so a movie play carries the
      // right addon id into meta.addonId (addon-stream resume/next), instead of a
      // stale one left over from a previously-browsed series.
      _activeAddonId = addon.id;

      if (isMdblistSource &&
          trackingPolicy.progressFrom(TrackingSource.mdblist)) {
        final owned = await _mdblistResumeItemFor(item);
        if (!mounted || cancelled) return;
        if (owned != null) {
          // This fast path skips the reconciler entirely, so it needs its own
          // promise check — otherwise an in-page watched mutation moves the
          // label while MDBList still reports the previous continue-watching
          // coordinate, and Resume replays the episode the label moved past.
          final p = promisedTarget;
          final stale =
              p != null &&
              (owned.selection.season != p.season ||
                  owned.selection.episode != p.episode);
          if (!stale) {
            await launch(owned.selection);
            return;
          }
          debugPrint(
            '[SeriesResume] play-mdblist-fastpath-skipped title="${item.name}" '
            'owned=S${owned.selection.season}E${owned.selection.episode} '
            'promised=S${p.season}E${p.episode}',
          );
          // Fall through to the reconciled/promised path below.
        }
      }

      // Series on the detail Resume flow (or Trakt-sourced): the SAME
      // reconciled answer the label used (cached ~45s), so the pill and the
      // playback can never land on different episodes — recency across
      // trackers + local, watched-advance; see _reconcileSeriesResume.
      if (item.type == 'series' && (preferTraktResume || isTraktSource)) {
        final r = await _reconcileSeriesResume(
          item,
          isTraktSource: isTraktSource,
        );
        if (!mounted || cancelled) return;
        // The caller's button already promised an episode the reconciler can't
        // see. Honor it: the label is the promise the user acted on, and a
        // silent disagreement here replays an episode they already watched.
        final promised = promisedTarget;
        final overridden =
            promised != null &&
            (promised.season != r.season || promised.episode != r.episode);
        if (overridden) {
          debugPrint(
            '[SeriesResume] play-promise-override title="${item.name}" '
            'reconciled=S${r.season}E${r.episode}/started=${r.started} '
            'promised=S${promised.season}E${promised.episode}',
          );
        }
        // Winner's original selection (Trakt or MDBList) — launches with its
        // own progress percent intact. Unusable once overridden: it points at
        // the older coordinate, so it would re-open the episode we just moved
        // past, carrying that episode's resume percent with it.
        if (!overridden && r.selection != null) {
          await launch(r.selection!);
          return;
        }
        final rTtId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
        final rTracker = (r.sourcePrio ?? 3) <= 2;
        // A promise IS started-evidence — it is what made the button read
        // "Resume". Without this, the empty-candidates fallback (started=false)
        // drops through to the S01E01 tail below. Keyed on the promise itself
        // rather than on [overridden]: when the promised coordinate happens to
        // MATCH the reconciler's fallback, there is no override, yet the button
        // still said "Resume" and must not fall through.
        final started = r.started || (promised?.started ?? false);
        if (started && (rTtId.isNotEmpty || skipEpisodeFallback || rTracker)) {
          await launch(
            AdvancedSearchSelection(
              imdbId: rTtId.isNotEmpty
                  ? rTtId
                  : (item.effectiveImdbId ?? item.id),
              isSeries: true,
              title: item.name,
              year: item.year,
              season: overridden ? promised.season : r.season,
              episode: overridden ? promised.episode : r.episode,
              contentType: item.type,
              posterUrl: item.poster,
              // Source flags from the WINNING provider (advanced or not) so
              // player scrobbling attribution follows the tracker that owned
              // the resume — not from how the page happened to be opened.
              traktSource: isTraktSource || r.sourcePrio == 0,
              // Belongs to the reconciled coordinate — carrying it onto a
              // different episode would seek the new one to a stale position.
              simklProgressPercent: overridden ? null : r.simklProgress,
              simklSource: r.sourcePrio == 1,
              // `isMdblistSource ||` mirrors the traktSource term above: when
              // the MDBList fast path is skipped as stale, the reconciler's
              // winner is usually the local candidate, and without this the
              // play would silently stop attributing to MDBList.
              mdblistSource: isMdblistSource || r.sourcePrio == 2,
            ),
          );
          return;
        }
        // Not started (or no usable id): fall through to the shared tail —
        // episode-picker fallback for id-less shows, default S01E01 otherwise.
      }

      // Trakt-sourced MOVIE keeps its cached-CW fast path (series resolve
      // through the reconciler above).
      if (item.type != 'series' &&
          isTraktSource &&
          trackingPolicy.progressFrom(TrackingSource.trakt)) {
        final cw = _traktByImdb[item.effectiveImdbId] ?? _traktByImdb[item.id];
        if (cw != null) {
          final sel = await TraktContinueWatchingService.instance
              .selectionForItem(cw);
          if (!mounted || cancelled) return;
          if (sel != null) {
            await launch(sel);
            return;
          }
        }
      }

      if (item.type != 'series') {
        // Cross-device movie resume: on the detail-page Play/Resume flow
        // (preferTraktResume, or a tracker-sourced open), pull the movie's paused
        // tracker position and carry it on the selection. The player's resume
        // reconciliation then seeks the furthest of trakt%/simkl%/local — so a
        // movie paused on another device resumes here even when opened from a
        // plain catalog result (previously movies started at 00:00). Row
        // quick-play (no preferTraktResume) keeps its local-only resume.
        double? traktPct;
        double? simklPct;
        double? mdblistPct;
        if (preferTraktResume || isTraktSource) {
          // Concurrent and individually time-boxed: the Play press must never
          // stall behind a degraded tracker API (sequential awaits here could
          // previously block playback for the full HTTP timeouts). On timeout we
          // launch with local-only resume — the reconciliation in the player
          // degrades gracefully to the local position.
          final lookups = await Future.wait<double?>([
            trackingPolicy.progressFrom(TrackingSource.trakt) &&
                    (_isTraktAuthenticated || isTraktSource)
                ? _traktMoviePercent(
                    item,
                  ).timeout(const Duration(seconds: 4), onTimeout: () => null)
                : Future<double?>.value(null),
            trackingPolicy.progressFrom(TrackingSource.simkl) &&
                    _isSimklAuthenticated
                ? _simklMoviePercent(
                    item,
                  ).timeout(const Duration(seconds: 4), onTimeout: () => null)
                : Future<double?>.value(null),
            trackingPolicy.progressFrom(TrackingSource.mdblist) &&
                    _isMdblistAuthenticated
                ? _mdblistMoviePercent(
                    item,
                  ).timeout(const Duration(seconds: 4), onTimeout: () => null)
                : Future<double?>.value(null),
          ]);
          if (!mounted || cancelled) return;
          traktPct = lookups[0];
          simklPct = lookups[1];
          mdblistPct = lookups[2];
        }
        // Rewatch (Simkl): a movie already marked `completed` on Simkl has no
        // resume session, and Simkl won't create one on replay — so it can never
        // re-enter Continue Watching. On the detail Play/Resume flow (the
        // "Rewatch" button surface, preferTraktResume), un-mark it watched first
        // so the upcoming catalog scrobble creates a fresh resume session; the
        // ≥80% stop re-marks it completed when the rewatch finishes. Gated on the
        // sync setting + auth so we never un-complete a movie that won't actually
        // be re-tracked. Row quick-play (no preferTraktResume) is left untouched.
        // WRITE-side action: gated on auth + the Scrobble master (below), NOT
        // the Progress source — a This-device user scrobbling to Simkl still
        // needs the replay session created.
        if (preferTraktResume && _isSimklAuthenticated) {
          // Same id resolution the detail screen's status loader uses (_imdbOf),
          // so the "Rewatch" label and this flip never disagree on the title.
          final imdb = _imdbOf(item);
          final scrobblesSimkl = trackingPolicy.scrobbles(TrackingSource.simkl);
          if (!mounted || cancelled) return;
          if (imdb != null && scrobblesSimkl) {
            // Time-boxed like the tracker-percent lookups above: a degraded Simkl
            // API must never stall the Play press. On timeout we just skip the
            // flip — worst case the rewatch doesn't surface in Continue Watching,
            // exactly today's behaviour.
            final status = await SimklService.instance
                .fetchTitleStatus(imdb)
                .timeout(const Duration(seconds: 4), onTimeout: () => null);
            if (!mounted || cancelled) return;
            if (status?.currentStatus == 'completed') {
              await SimklService.instance
                  .markUnwatched(imdb, 'movie')
                  .timeout(const Duration(seconds: 4), onTimeout: () => false);
              if (!mounted || cancelled) return;
            }
          }
        }
        // Keep the detail page underneath — the cinematic loading overlay covers
        // it, and after playback Back returns to the detail (like Home).
        await launch(
          _movieSelection(
            item,
            isTraktSource: isTraktSource,
            isMdblistSource: isMdblistSource,
            traktProgressPercent: traktPct,
            simklProgressPercent: simklPct,
            mdblistProgressPercent: mdblistPct,
          ),
        );
        return;
      }

      final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
      // Without an IMDb id we can't search torrents for a specific episode, so
      // fall back to the manual episode picker — except from the merged page
      // (episodes are inline there), where we play via the raw id's addon stream.
      if (ttId.isEmpty && !skipEpisodeFallback) {
        if (!cancelled) {
          _openEpisodes(
            item,
            addon,
            isTraktSource: isTraktSource,
            isMdblistSource: isMdblistSource,
          );
        }
        return;
      }
      // Play id: the `tt…` id when present (torrent-resolvable); otherwise the raw
      // catalog id, which playFromSelection routes to the addon /stream endpoint.
      final playId = ttId.isNotEmpty ? ttId : (item.effectiveImdbId ?? item.id);

      // Resolve where to resume, mirroring EpisodesScreen's landing logic:
      // last-played episode for this show (by imdbId, then by title), else S01E01.
      int? season;
      int? episode;
      final byId = trackingPolicy.progressFrom(TrackingSource.local)
          ? await StorageService.getLastPlayedEpisodeByImdbId(playId)
          : null;
      season = byId?['season'] as int?;
      episode = byId?['episode'] as int?;
      final lastFinished = byId?['finished'] == true;
      if (season == null || episode == null) {
        final byTitle = trackingPolicy.progressFrom(TrackingSource.local)
            ? await StorageService.getLastPlayedEpisode(seriesTitle: item.name)
            : null;
        season ??= byTitle?['season'] as int?;
        episode ??= byTitle?['episode'] as int?;
      }
      // No local history — last resort: Simkl's next-to-watch, mirroring the
      // label (_resolveResumeInfo) so the two agree. Only on the detail Resume
      // flow, and TIME-BOXED (4s) like the movie branch so a slow Simkl API never
      // freezes the Play press — on timeout it falls through to S01E01.
      if ((season == null || episode == null) &&
          _isSimklAuthenticated &&
          trackingPolicy.progressFrom(TrackingSource.simkl) &&
          preferTraktResume) {
        final next = await _simklNextToWatchFor(
          item,
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (!mounted || cancelled) return;
        if (next != null) {
          season = next.season;
          episode = next.episode;
        }
      }
      if ((season == null || episode == null) &&
          _isMdblistAuthenticated &&
          trackingPolicy.progressFrom(TrackingSource.mdblist) &&
          preferTraktResume) {
        final next = await _mdblistResumeItemFor(
          item,
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (!mounted || cancelled) return;
        if (next != null) {
          season = next.selection.season;
          episode = next.selection.episode;
        }
      }
      season ??= 1;
      episode ??= 1;
      // If the last-played episode is finished, resume the NEXT one instead of
      // re-opening it — parity with the deprecated home's continue-watching
      // quick-play (only the local, non-Trakt path; Trakt resolves its own next).
      if (lastFinished) {
        final next = await NextEpisodeService.findNextEpisode(
          playId,
          season,
          episode,
        );
        if (!mounted || cancelled) return;
        if (next != null) {
          season = next.season;
          episode = next.episode;
        }
      }
      if (!mounted || cancelled) return;

      await launch(
        AdvancedSearchSelection(
          imdbId: playId,
          isSeries: true,
          title: item.name,
          year: item.year,
          season: season,
          episode: episode,
          contentType: item.type,
          posterUrl: item.poster,
          traktSource: isTraktSource,
          mdblistSource: isMdblistSource,
        ),
      );
    } finally {
      resolving?.dismiss();
    }
  }

  /// Read-only mirror of [_onCatalogPlay]'s resume resolution, used to label the
  /// detail screen's primary button. Returns whether the title has prior
  /// progress and, for a series, the season/episode a Play would actually land
  /// on (the next episode when the last one was finished). Never plays — keep in
  /// sync with [_onCatalogPlay].
  // ── Reconciled series resume ──────────────────────────────────────────────
  // ONE answer per title for "where does Resume land", shared VERBATIM by the
  // button label (_resolveResumeInfo) and Play (_onCatalogPlay) via a short
  // cache — so a tracker call that flakes between page-open and button-press
  // can never make the pill advertise one episode and playback open another.
  final Map<
    String,
    ({
      int atMs,
      String rev,
      ({
        bool started,
        int season,
        int episode,
        double? simklProgress,
        AdvancedSearchSelection? selection,
        int? sourcePrio,
      })
      r,
    })
  >
  _seriesResumeCache = {};

  /// Combined cache identity: per-title tracker revisions (any scrobble/
  /// watched write bumps its provider's counter, so a cached reconciled
  /// answer is invalidated the moment a tracker mutation lands) PLUS the
  /// tracker-availability flags — auth settling, a connect/disconnect, or a
  /// Trakt-sourced reopen must recompute rather than reuse an answer built
  /// from a different set of eligible sources.
  String _seriesResumeRev(
    String playId,
    bool isTraktSource,
    WatchProgressSource progressSource,
  ) =>
      '${EpisodeTrackerSnapshotRevision.identity('trakt', playId)}.'
      '${EpisodeTrackerSnapshotRevision.identity('simkl', playId)}.'
      '${EpisodeTrackerSnapshotRevision.identity('mdblist', playId)}.'
      // 'local' is bumped by in-page local-only mark watched/unwatched — the
      // one resume input with no tracker revision of its own.
      '${EpisodeTrackerSnapshotRevision.identity('local', playId)}.'
      '${_isTraktAuthenticated ? 1 : 0}${_isSimklAuthenticated ? 1 : 0}'
      '${_isMdblistAuthenticated ? 1 : 0}${isTraktSource ? 1 : 0}.'
      '${progressSource.name}';

  /// The reconciled series-resume answer (2026-08-25 redesign — fixes the
  /// home-card / pill / Play three-way disagreement):
  ///
  ///  - Candidates are gathered CONCURRENTLY, each 4s-boxed: Trakt paused/next
  ///    (when connected or Trakt-sourced), Simkl's newest paused session (with
  ///    `paused_at`), MDBList's paused entry (with `updatedAt`), and local
  ///    last-played (with its own timestamp).
  ///  - RECENCY wins, not fixed priority: any candidate carrying a timestamp
  ///    beats every timestampless one, newest first; timestampless candidates
  ///    fall back to the legacy order (Trakt → Simkl → MDBList → local). A
  ///    stale tracker session — orphaned by a failed scrobble stop — can no
  ///    longer outrank last night's actual position.
  ///  - A winner that is effectively DONE (locally finished, or progress ≥ 80,
  ///    the trackers' own watched threshold) advances to the next episode:
  ///    guide-aware [NextEpisodeService] first (handles season boundaries),
  ///    Simkl's server-computed `next_to_watch` as backup — the same signal
  ///    the home Continue Watching card shows, so the surfaces agree.
  ///  - Nothing anywhere: `next_to_watch` → MDBList CW coordinate → an
  ///    unstarted S01E01.
  /// `sourcePrio` names the winning provider (0 Trakt, 1 Simkl, 2 MDBList,
  /// 3 local, null fallback/none) — Play stamps the rebuilt selection's
  /// source flags from it, so an ADVANCED tracker winner keeps its player
  /// scrobbling attribution. The launcher's shared normalization still applies
  /// the independent Scrobble masters before any write reaches a tracker.
  Future<
    ({
      bool started,
      int season,
      int episode,
      double? simklProgress,
      AdvancedSearchSelection? selection,
      int? sourcePrio,
    })
  >
  _reconcileSeriesResume(StremioMeta item, {bool isTraktSource = false}) async {
    final trackingPolicy = await TrackingSourcePolicy.load();
    final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    final playId = ttId.isNotEmpty ? ttId : (item.effectiveImdbId ?? item.id);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rev = _seriesResumeRev(
      playId,
      isTraktSource,
      trackingPolicy.progressSource,
    );
    final hit = _seriesResumeCache[playId];
    if (hit != null && nowMs - hit.atMs < 45000 && hit.rev == rev) {
      debugPrint(
        '[SeriesResume] reconcile-cache-hit title="${item.name}" '
        'id=$playId ageMs=${nowMs - hit.atMs} rev=$rev '
        'result=S${hit.r.season}E${hit.r.episode} '
        'started=${hit.r.started} source=${_resumeSourceName(hit.r.sourcePrio)}',
      );
      return hit.r;
    }
    debugPrint(
      '[SeriesResume] reconcile-start title="${item.name}" id=$playId '
      'rawId=${item.id} effectiveId=${item.effectiveImdbId} '
      'traktAuth=$_isTraktAuthenticated simklAuth=$_isSimklAuthenticated '
      'mdblistAuth=$_isMdblistAuthenticated traktSource=$isTraktSource '
      'rev=$rev cache=${hit == null ? 'miss' : 'stale-or-revised'}',
    );
    _seriesResumeCache.removeWhere((_, v) => nowMs - v.atMs >= 45000);

    // Kick everything off together; a degraded tracker API must never stall
    // the Play press (same 4s boxes the old chain used).
    final traktF =
        trackingPolicy.progressFrom(TrackingSource.trakt) &&
            (_isTraktAuthenticated || isTraktSource)
        ? _traktSelectionFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<({AdvancedSearchSelection sel, int? tsMs})?>.value(null);
    final simklF =
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
            _isSimklAuthenticated
        ? _simklResumeFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<
            ({int season, int episode, double? progress, DateTime? pausedAt})?
          >.value(null);
    final mdbF =
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
            _isMdblistAuthenticated
        ? _mdblistResumeItemFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<MdblistContinueWatchingItem?>.value(null);
    final localF = trackingPolicy.progressFrom(TrackingSource.local)
        ? _localSeriesResumeFor(item, playId)
        : Future<
            ({int season, int episode, double? pct, int? tsMs, bool finished})?
          >.value(null);
    final nextF =
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
            _isSimklAuthenticated
        ? _simklNextToWatchFor(
            item,
          ).timeout(const Duration(seconds: 4), onTimeout: () => null)
        : Future<({int season, int episode})?>.value(null);

    final trakt = await traktF;
    final simkl = await simklF;
    final mdb = await mdbF;
    final local = await localF;
    final simklNext = await nextF;

    debugPrint(
      '[SeriesResume] reconcile-inputs title="${item.name}" id=$playId '
      'trakt=${_formatTraktResume(trakt)} '
      'simkl=${_formatSimklResume(simkl)} '
      'mdblist=${_formatMdblistResume(mdb)} '
      'local=${_formatLocalResume(local)} '
      'simklNext=${simklNext == null ? 'none' : 'S${simklNext.season}E${simklNext.episode}'}',
    );

    final candidates =
        <
          ({
            int prio,
            int? tsMs,
            int s,
            int e,
            double? pct,
            bool finished,
            AdvancedSearchSelection? sel,
          })
        >[];
    if (trakt != null &&
        trakt.sel.season != null &&
        trakt.sel.episode != null) {
      candidates.add((
        prio: 0,
        // Trakt's own activity timestamp.
        tsMs: trakt.tsMs,
        s: trakt.sel.season!,
        e: trakt.sel.episode!,
        pct: trakt.sel.traktProgressPercent,
        finished: false,
        sel: trakt.sel,
      ));
    }
    if (simkl != null) {
      candidates.add((
        prio: 1,
        tsMs: simkl.pausedAt?.millisecondsSinceEpoch,
        s: simkl.season,
        e: simkl.episode,
        pct: simkl.progress,
        finished: false,
        sel: null,
      ));
    }
    final mdbSel = mdb?.selection;
    if (mdb != null &&
        mdb.paused &&
        mdbSel!.season != null &&
        mdbSel.episode != null) {
      candidates.add((
        prio: 2,
        tsMs: mdb.updatedAt?.millisecondsSinceEpoch,
        s: mdbSel.season!,
        e: mdbSel.episode!,
        pct: mdbSel.mdblistProgressPercent,
        // The winner's ORIGINAL selection so a launch keeps its progress
        // percent (a rebuilt coordinate would restart at the local offset).
        finished: false,
        sel: mdbSel,
      ));
    }
    if (local != null) {
      candidates.add((
        prio: 3,
        tsMs: local.tsMs,
        s: local.season,
        e: local.episode,
        pct: local.pct,
        finished: local.finished,
        sel: null,
      ));
    }

    ({
      bool started,
      int season,
      int episode,
      double? simklProgress,
      AdvancedSearchSelection? selection,
      int? sourcePrio,
    })
    result;
    if (candidates.isEmpty) {
      // Fresh device / nothing anywhere. next_to_watch matches the home card;
      // the MDBList CW coordinate is the weaker backup (same as the old tail).
      if (simklNext != null) {
        result = (
          started: true,
          season: simklNext.season,
          episode: simklNext.episode,
          simklProgress: null,
          selection: null,
          sourcePrio: null,
        );
      } else if (mdbSel?.season != null && mdbSel?.episode != null) {
        result = (
          started: true,
          season: mdbSel!.season!,
          episode: mdbSel.episode!,
          simklProgress: null,
          selection: null,
          sourcePrio: null,
        );
      } else {
        result = (
          started: false,
          season: 1,
          episode: 1,
          simklProgress: null,
          selection: null,
          sourcePrio: null,
        );
      }
    } else {
      candidates.sort((a, b) {
        final at = a.tsMs;
        final bt = b.tsMs;
        if (at != null && bt != null) return bt.compareTo(at);
        if (at != null) return -1;
        if (bt != null) return 1;
        return a.prio.compareTo(b.prio);
      });
      final w = candidates.first;
      var season = w.s;
      var episode = w.e;
      var selection = w.sel;
      var simklProgress = w.prio == 1 ? w.pct : null;
      final isTracker = w.prio <= 2;
      final sourcePrio = w.prio;
      // Advance rules. Tracker sessions at ≥80% are the orphan pattern the
      // trackers themselves treat as watched — advance. A LOCAL position at
      // ≥80% only advances when the player marked it finished OR a tracker's
      // resume/up-next frontier confirms the episode is behind it. A local-only
      // pause in the last stretch stays resumable in place.
      final trackerFrontiers = <EpisodeCoordinate>[
        for (final candidate in candidates)
          if (candidate.prio <= 2) (season: candidate.s, episode: candidate.e),
        if (simklNext != null)
          (season: simklNext.season, episode: simklNext.episode),
      ];
      final trackerFrontierAhead = trackerFrontiers.any(
        (frontier) =>
            frontier.season > season ||
            (frontier.season == season && frontier.episode > episode),
      );
      final done = shouldAdvanceEpisodeResume(
        candidate: (season: season, episode: episode),
        finished: w.finished,
        progress: w.pct,
        isTracker: isTracker,
        trackerFrontiers: trackerFrontiers,
      );
      debugPrint(
        '[SeriesResume] reconcile-winner title="${item.name}" id=$playId '
        'source=${_resumeSourceName(w.prio)} base=S${w.s}E${w.e} '
        'pct=${w.pct} timestamp=${_formatResumeTimestamp(w.tsMs)} '
        'finished=${w.finished} trackerFrontierAhead=$trackerFrontierAhead '
        'willAdvance=$done '
        'progressPolicy=${trackingPolicy.progressSource.name}',
      );
      if (done) {
        // 4s-boxed like every other network hop here: the guide fetch's body
        // read is otherwise unbounded, and the PLAY path has no outer box —
        // a stalled read would hang the press. Timeout → null → the defined
        // "keep the winner / adjacent tracker frontier" fallback.
        final next = await NextEpisodeService.findNextEpisode(
          playId,
          season,
          episode,
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        // A tracker-frontier backup is safe ONLY when it is the winner's direct
        // successor. A frontier can be seasons ahead during a rewatch; trusting
        // that blindly when the guide flakes would teleport the rewatch.
        EpisodeCoordinate? adjacentTrackerFrontier;
        for (final frontier in trackerFrontiers) {
          final isDirectSuccessor =
              (frontier.season == season && frontier.episode == episode + 1) ||
              (frontier.season == season + 1 && frontier.episode == 1);
          if (isDirectSuccessor) {
            adjacentTrackerFrontier = frontier;
            break;
          }
        }
        final target = next ?? adjacentTrackerFrontier;
        debugPrint(
          '[SeriesResume] reconcile-advance title="${item.name}" id=$playId '
          'guideNext=${next == null ? 'none' : 'S${next.season}E${next.episode}'} '
          'adjacentTracker=${adjacentTrackerFrontier == null ? 'none' : 'S${adjacentTrackerFrontier.season}E${adjacentTrackerFrontier.episode}'} '
          'chosen=${target == null ? 'keep-S${w.s}E${w.e}' : 'S${target.season}E${target.episode}'}',
        );
        if (target != null) {
          season = target.season;
          episode = target.episode;
          selection = null;
          simklProgress = null;
        }
        // Both unknown (finale / no guide): keep the winner — playing its tail
        // is still truer than inventing an episode.
      }
      result = (
        started: true,
        season: season,
        episode: episode,
        simklProgress: simklProgress,
        selection: selection,
        // The BASE winner's provider survives an advance on purpose — the
        // next episode should scrobble to the tracker that owned the resume.
        sourcePrio: sourcePrio,
      );
    }
    debugPrint(
      '[SeriesResume] reconcile-result title="${item.name}" id=$playId '
      'started=${result.started} target=S${result.season}E${result.episode} '
      'source=${_resumeSourceName(result.sourcePrio)} '
      'hasOriginalSelection=${result.selection != null} '
      'simklPct=${result.simklProgress}',
    );
    _seriesResumeCache[playId] = (atMs: nowMs, rev: rev, r: result);
    return result;
  }

  String _resumeSourceName(int? priority) => switch (priority) {
    0 => 'trakt',
    1 => 'simkl',
    2 => 'mdblist',
    3 => 'local',
    _ => 'fallback',
  };

  String _formatResumeTimestamp(int? timestampMs) {
    if (timestampMs == null) return 'none';
    return DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String();
  }

  String _formatTraktResume(({AdvancedSearchSelection sel, int? tsMs})? value) {
    if (value == null) return 'none';
    return 'S${value.sel.season}E${value.sel.episode}'
        '/pct=${value.sel.traktProgressPercent}'
        '/at=${_formatResumeTimestamp(value.tsMs)}';
  }

  String _formatSimklResume(
    ({int season, int episode, double? progress, DateTime? pausedAt})? value,
  ) {
    if (value == null) return 'none';
    return 'S${value.season}E${value.episode}'
        '/pct=${value.progress}'
        '/at=${value.pausedAt?.toIso8601String() ?? 'none'}';
  }

  String _formatMdblistResume(MdblistContinueWatchingItem? value) {
    if (value == null) return 'none';
    return 'S${value.selection.season}E${value.selection.episode}'
        '/pct=${value.selection.mdblistProgressPercent}'
        '/paused=${value.paused}'
        '/at=${value.updatedAt?.toIso8601String() ?? 'none'}';
  }

  String _formatLocalResume(
    ({int season, int episode, double? pct, int? tsMs, bool finished})? value,
  ) {
    if (value == null) return 'none';
    return 'S${value.season}E${value.episode}'
        '/pct=${value.pct}'
        '/finished=${value.finished}'
        '/at=${_formatResumeTimestamp(value.tsMs)}';
  }

  /// Trakt candidate for the reconciler — the full ready-to-play selection
  /// (paused/next episode with Trakt progress) PLUS the item's `paused_at`,
  /// so a Trakt pause competes on recency like every other source. A Trakt
  /// win launches the exact selection Trakt resolved, never a re-derived
  /// coordinate.
  Future<({AdvancedSearchSelection sel, int? tsMs})?> _traktSelectionFor(
    StremioMeta item,
  ) async {
    final cached = _traktByImdb[item.effectiveImdbId] ?? _traktByImdb[item.id];
    if (cached != null) {
      debugPrint(
        '[SeriesResume] trakt-home-card-hit title="${item.name}" '
        'lookupId=${item.effectiveImdbId ?? item.id} cardId=${cached.id} '
        'card=S${cached.season}E${cached.episode} '
        'cardPct=${cached.progress} '
        'cardPausedAt=${_formatResumeTimestamp(cached.pausedAtMs)}',
      );
      final sel = await TraktContinueWatchingService.instance.selectionForItem(
        cached,
      );
      if (sel == null) return null;
      debugPrint(
        '[SeriesResume] trakt-home-card-selection title="${item.name}" '
        'resolved=S${sel.season}E${sel.episode} '
        'resolvedPct=${sel.traktProgressPercent}',
      );
      return (sel: sel, tsMs: cached.pausedAtMs);
    }
    if (item.type != 'series') return null;
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty) return null;
    // Mirror resolveSelection's lookup but keep the ITEM, so its Trakt activity
    // timestamp survives.
    final items = await TraktContinueWatchingService.instance.fetchItems(
      TraktContinueWatchingService.showsContentType,
    );
    debugPrint(
      '[SeriesResume] trakt-live-lookup title="${item.name}" id=$id '
      'homeCacheMiss=true fetchedItems=${items.length}',
    );
    TraktContinueWatchingItem? selected;
    for (final it in items) {
      if (it.id == id) {
        selected = it;
        break;
      }
    }
    if (selected == null) return null;
    debugPrint(
      '[SeriesResume] trakt-live-match title="${item.name}" id=$id '
      'card=S${selected.season}E${selected.episode} '
      'cardPct=${selected.progress} '
      'cardPausedAt=${_formatResumeTimestamp(selected.pausedAtMs)}',
    );
    final sel = await TraktContinueWatchingService.instance.selectionForItem(
      selected,
    );
    if (sel == null) return null;
    return (sel: sel, tsMs: selected.pausedAtMs);
  }

  /// Local candidate for the reconciler: last-played episode by imdb id (then
  /// by title, same fallback the old chain used), with its progress percent
  /// and updatedAt so it can compete on recency.
  Future<({int season, int episode, double? pct, int? tsMs, bool finished})?>
  _localSeriesResumeFor(StremioMeta item, String playId) async {
    Map<String, dynamic>? entry =
        await StorageService.getLastPlayedEpisodeByImdbId(playId);
    var finished = entry?['finished'] == true;
    if (entry?['season'] is! int || entry?['episode'] is! int) {
      entry = await StorageService.getLastPlayedEpisode(seriesTitle: item.name);
      finished = entry?['finished'] == true;
    }
    final season = entry?['season'];
    final episode = entry?['episode'];
    if (season is! int || episode is! int) return null;
    // Series records store positionMs/durationMs (see saveSeriesPlaybackState);
    // the bare names are kept as a fallback for the video-entry shape.
    final pos = ((entry?['positionMs'] ?? entry?['position']) as num?)
        ?.toDouble();
    final dur = ((entry?['durationMs'] ?? entry?['duration']) as num?)
        ?.toDouble();
    final pct = (pos != null && dur != null && dur > 0)
        ? (pos / dur * 100).clamp(0.0, 100.0)
        : null;
    final tsMs = (entry?['updatedAt'] as num?)?.toInt();
    return (
      season: season,
      episode: episode,
      pct: pct,
      tsMs: tsMs != null && tsMs > 0 ? tsMs : null,
      finished: finished,
    );
  }

  /// Trakt's authoritative resume position for [item], or null when
  /// disconnected / Trakt has no in-progress entry. Shared by the detail-button
  /// label ([_resolveResumeInfo]) and the actual Play ([_onCatalogPlay]) so the
  /// two never disagree ("Resume · S3E4" must play S3E4). Fast path: an
  /// already-loaded Continue Watching item; general path: a one-shot live
  /// playback lookup for any other title (progress made on another device).
  Future<({bool started, int? season, int? episode})?> _traktResumeFor(
    StremioMeta item,
  ) async {
    // No auth-flag short-circuit here: callers gate entry, and both the cached
    // _traktByImdb read and resolveSelection (which self-checks isAuthenticated)
    // are safe/null when disconnected — so a Trakt-sourced item still resolves
    // even if _isTraktAuthenticated hasn't settled yet.
    final cached = _traktByImdb[item.effectiveImdbId] ?? _traktByImdb[item.id];
    if (cached != null) {
      final sel = await TraktContinueWatchingService.instance.selectionForItem(
        cached,
      );
      if (sel == null) return null;
      return (started: true, season: sel.season, episode: sel.episode);
    }
    // General (live) fallback only for SERIES here. An uncached movie returns
    // null from THIS helper on purpose — its cross-device resume is resolved by
    // the dedicated movie branch of _resolveResumeInfo/_onCatalogPlay (via
    // _traktMoviePercent), which the player can now honour. So "null" means
    // "not handled here", not "no Trakt resume for movies".
    if (item.type != 'series') return null;
    // resolveSelection treats an empty itemId as "the first CW item", which would
    // match an unrelated title — so bail when we have no usable id.
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty) return null;
    // Use the SAME resolution _onCatalogPlay's general series branch uses
    // (resolveSelection → fetchItems + selectionForItem). This includes Trakt's
    // Up Next augmentation, so the label matches Play even
    // when the title is only reachable via that augmentation and regardless of
    // whether _traktByImdb has populated yet (fixes the open-before-CW-load race
    // where the cached Play branch and the live label branch disagreed).
    final sel = await TraktContinueWatchingService.instance.resolveSelection(
      traktContentType: TraktContinueWatchingService.showsContentType,
      itemId: id,
    );
    if (sel == null) return null;
    return (started: true, season: sel.season, episode: sel.episode);
  }

  /// Simkl's resume position for [item] — SERIES ONLY, from the show's most
  /// recently paused Simkl playback session. Consulted after Trakt returns
  /// nothing and before local history (episode pick is priority-ordered
  /// Trakt → Simkl → local). Shared by the detail-button label
  /// ([_resolveResumeInfo]) and the actual Play ([_onCatalogPlay]) so the two
  /// never disagree — same lock-step contract as [_traktResumeFor]. Movies
  /// are excluded for the same reason as Trakt's uncached-movie rule: the
  /// movie play path resumes from the local byte offset and can't honour a
  /// tracker percent, so a Simkl-first label would over-promise.
  Future<({int season, int episode, double? progress, DateTime? pausedAt})?>
  _simklResumeFor(StremioMeta item) async {
    if (item.type != 'series') return null;
    final id = item.effectiveImdbId ?? item.id;
    // Simkl lookups are IMDb-keyed — a non-IMDb catalog id can't match.
    if (id.isEmpty || !id.startsWith('tt')) return null;
    // The show's most recently paused session, WITH its paused_at timestamp —
    // it competes on recency inside [_reconcileSeriesResume] rather than
    // holding a fixed slot above local history, so a stale orphaned session
    // (failed scrobble stop) can't outrank last night's actual position.
    return SimklService.instance.fetchShowPlaybackSelection(id);
  }

  /// Simkl's next unwatched episode (server-computed `next_to_watch`) for a
  /// series, or null. This is the WEAKEST resume signal — a computed "next"
  /// rather than a real position — so callers apply it only when neither a
  /// tracker session NOR local history resolved an episode (e.g. a fresh login
  /// on a new device): it turns the default S01E01 into "resume at the next
  /// unwatched episode", matching the Continue Watching up-next card.
  Future<({int season, int episode})?> _simklNextToWatchFor(
    StremioMeta item,
  ) async {
    if (item.type != 'series') return null;
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty || !id.startsWith('tt')) return null;
    return SimklService.instance.fetchNextToWatch(id);
  }

  Future<MdblistContinueWatchingItem?> _mdblistResumeItemFor(
    StremioMeta item,
  ) async {
    final id = (item.effectiveImdbId ?? item.id).toLowerCase();
    if (!id.startsWith('tt')) return null;
    final result = await MdblistContinueWatchingService.instance.fetch();
    if (!result.isUsable) return null;
    for (final candidate in [...result.data!.movies, ...result.data!.shows]) {
      if (candidate.selection.imdbId.toLowerCase() == id) return candidate;
    }
    return null;
  }

  Future<({bool started, int? season, int? episode})> _resolveResumeInfo(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) async {
    final trackingPolicy = await TrackingSourcePolicy.load();
    debugPrint(
      '[SeriesResume] label-resolve-start title="${item.name}" '
      'id=${item.effectiveImdbId ?? item.id} type=${item.type} '
      'traktSource=$isTraktSource mdblistSource=$isMdblistSource',
    );
    if (isMdblistSource &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final owned = await _mdblistResumeItemFor(item);
      if (!mounted) return (started: false, season: null, episode: null);
      if (owned != null) {
        return (
          started: true,
          season: owned.selection.season,
          episode: owned.selection.episode,
        );
      }
    }
    // Series: the ONE reconciled answer — recency across trackers + local,
    // watched-advance, briefly cached — shared verbatim with _onCatalogPlay
    // so the label and playback can never disagree (see
    // _reconcileSeriesResume for the full rules).
    if (item.type == 'series') {
      final r = await _reconcileSeriesResume(
        item,
        isTraktSource: isTraktSource,
      );
      if (!mounted) return (started: false, season: null, episode: null);
      debugPrint(
        '[SeriesResume] label-resolve-result title="${item.name}" '
        'started=${r.started} target=S${r.season}E${r.episode} '
        'source=${_resumeSourceName(r.sourcePrio)}',
      );
      return (started: r.started, season: r.season, episode: r.episode);
    }

    // Trakt-sourced MOVIE: the cached CW selection carries Trakt's position —
    // same fast path the old Trakt-first arm gave movies (a non-Trakt-sourced
    // movie deliberately stays local-first; Play resumes it from the local
    // byte offset, so a tracker-first label would over-promise).
    if (isTraktSource && trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final resume = await _traktResumeFor(item);
      if (!mounted) return (started: false, season: null, episode: null);
      if (resume != null) return resume;
    }

    // Movie (series returned above): "started" if a local position OR a
    // cross-device tracker position exists — so the button reads "Resume" for
    // a movie paused on another device, matching what Play now seeks to (kept
    // in lock-step with the movie branch of _onCatalogPlay).
    final playId = item.imdbId ?? item.effectiveImdbId ?? item.id;
    final st = trackingPolicy.progressFrom(TrackingSource.local)
        ? await StorageService.getVideoPlaybackStateByImdbId(playId)
        : null;
    if (!mounted) return (started: false, season: null, episode: null);
    var started = st != null;
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.trakt) &&
        (_isTraktAuthenticated || isTraktSource)) {
      started = (await _traktMoviePercent(item)) != null;
      if (!mounted) return (started: false, season: null, episode: null);
    }
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
        _isSimklAuthenticated) {
      started = (await _simklMoviePercent(item)) != null;
      if (!mounted) return (started: false, season: null, episode: null);
    }
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
        _isMdblistAuthenticated) {
      started = (await _mdblistMoviePercent(item)) != null;
      if (!mounted) return (started: false, season: null, episode: null);
    }
    return (started: started, season: null, episode: null);
  }

  void _onCatalogBrowse(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    if (item.type == 'series') {
      _openEpisodes(
        item,
        addon,
        isTraktSource: isTraktSource,
        isMdblistSource: isMdblistSource,
      );
    } else {
      _browseSelection(
        _movieSelection(
          item,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        ),
      );
    }
  }

  AdvancedSearchSelection _movieSelection(
    StremioMeta item, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Cross-device resume percents for a movie (0-100), when a tracker has a
    // paused position. Null = no tracker position → the player resumes from
    // the local byte offset as before.
    double? traktProgressPercent,
    double? simklProgressPercent,
    double? mdblistProgressPercent,
  }) => AdvancedSearchSelection(
    // Keep the raw catalog id when there's no `tt…` id — for IPTV/TV channels
    // AND tmdb/kitsu-only movies — so playback/Sources resolve the addon's own
    // /stream endpoint, matching old home (which passed effectiveImdbId ?? id).
    // The torrent engines can't resolve a non-`tt` id, but the addon stream can
    // (playFromSelection routes any non-`tt` id to _playAddonStream), so this
    // plays instead of dead-ending on "No IMDb match".
    imdbId: item.effectiveImdbId ?? item.id,
    isSeries: false,
    title: item.name,
    year: item.year,
    contentType: item.type,
    posterUrl: item.poster,
    // Trakt-sourced movies scrobble to Trakt like the old home view; catalog
    // movies leave this false so scrobble follows the Tracking master
    // setting.
    traktSource: isTraktSource,
    traktProgressPercent: traktProgressPercent,
    simklProgressPercent: simklProgressPercent,
    mdblistSource: isMdblistSource,
    mdblistProgressPercent: mdblistProgressPercent,
  );

  /// Trakt's paused position (0-100) for a movie, or null when it has none.
  /// Reuses the existing Continue Watching resolver (which fetches
  /// `/sync/playback/movies` and returns a selection carrying the percent) —
  /// no new Trakt service code. Trakt is IMDb-keyed, so a non-`tt` id can't
  /// match.
  /// Short-TTL memo for [_traktMoviePercent]: the Resume label
  /// (_resolveResumeInfo) and the Play press (_onCatalogPlay) both need the
  /// percent seconds apart, and resolveSelection has no cache of its own — so
  /// without this every detail open cost two identical /sync/playback/movies
  /// fetches and Play blocked on the second. TTL matches SimklService's own
  /// 30s playback cache (which already gives the Simkl helper this behavior).
  final Map<String, (double?, DateTime)> _traktMoviePctMemo = {};

  Future<double?> _traktMoviePercent(StremioMeta item) async {
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty || !id.startsWith('tt')) return null;
    final memo = _traktMoviePctMemo[id];
    if (memo != null &&
        DateTime.now().difference(memo.$2) < const Duration(seconds: 30)) {
      return memo.$1;
    }
    final sel = await TraktContinueWatchingService.instance.resolveSelection(
      traktContentType: TraktContinueWatchingService.moviesContentType,
      itemId: id,
    );
    final pct = _resumableMoviePercent(sel?.traktProgressPercent);
    _traktMoviePctMemo[id] = (pct, DateTime.now());
    return pct;
  }

  /// Simkl's paused position (0-100) for a movie, or null when it has none.
  /// Mirror of [_traktMoviePercent]; Simkl lookups are IMDb-keyed too.
  Future<double?> _simklMoviePercent(StremioMeta item) async {
    final id = item.effectiveImdbId ?? item.id;
    if (id.isEmpty || !id.startsWith('tt')) return null;
    return _resumableMoviePercent(
      await SimklService.instance.fetchMoviePlaybackProgress(id),
    );
  }

  Future<double?> _mdblistMoviePercent(StremioMeta item) async {
    final candidate = await _mdblistResumeItemFor(item);
    if (candidate == null ||
        !candidate.paused ||
        candidate.selection.isSeries) {
      return null;
    }
    return _resumableMdblistPercent(candidate.selection.mdblistProgressPercent);
  }

  double? _resumableMdblistPercent(double? pct) {
    if (pct == null || pct < 1 || pct >= 80) return null;
    return pct;
  }

  /// A movie tracker percent, narrowed to what the player will actually
  /// forward-seek, or null. The player's resume window is bounded on BOTH ends
  /// (video_player_screen.dart): it seeks only `loMs < traktMs < hiMs`, where
  /// hiMs = 90% of duration and loMs = the 2s minimum position. A percent
  /// outside that band makes the detail button read "Resume" while Play starts
  /// from 00:00 — a label↔Play mismatch. We only have the percent here (no
  /// duration), so the lower guard is a conservative 1%, which maps above 2s for
  /// any real-length movie (1% of even a 4-min clip is >2s). Keep both helpers
  /// on this filter so the label promises only a Resume that Play honours.
  double? _resumableMoviePercent(double? pct) {
    if (pct == null || pct < 1 || pct >= 90) return null;
    return pct;
  }

  void _openEpisodes(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) {
    _activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kEpisodesRouteName),
            builder: (_) => EpisodesScreen(
              show: item,
              addon: addon,
              isTelevision: widget.isTelevision,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
              // EpisodesScreen pops itself (and the detail route) before firing
              // these, so we're back on the Search screen when they run.
              onQuickPlay: _playSelection,
              onItemSelected: _browseSelection,
              // "Select Source" button: manage/pin sources via the same picker
              // the detail screen uses (edit dialog when already bound, else the
              // Torrent Search / Local / RD / TorBox picker) for a consistent
              // entry point.
              boundSourceCount: _boundCountFor,
              onSelectSource: _handleEditOrSelectSource,
            ),
          ),
        )
        .then((_) {
          // EpisodesScreen can mark watched / play; its plays route through
          // _playSelection (which clears too), but marks don't — never let a
          // pre-visit reconciled answer survive the trip.
          _seriesResumeCache.clear();
          _refreshBoundSources();
        });
  }

  /// Open the source picker (bind mode) to pin a source for [show]. For a series
  /// this searches season/complete packs (no episode), matching Home.
  void _openBindSources(StremioMeta show) {
    final imdb = _imdbOf(show);
    if (imdb == null) {
      _snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: show.type == 'series',
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
              bindMode: true,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Free-text keyword bind: push the sources screen seeded with a pack query
  /// (series → `name complete`, movie → `name year`), where tapping a result
  /// pins it as [show]'s bound source. The query is editable.
  void _openKeywordBind(StremioMeta show) {
    final imdb = _imdbOf(show);
    if (imdb == null) {
      _snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final isSeries = show.type == 'series';
    final seed = isSeries
        ? '${show.name} complete'
        : (show.year != null && show.year!.isNotEmpty
              ? '${show.name} ${show.year}'
              : show.name);
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: isSeries,
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
              bindMode: true,
              keywordSeed: seed,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Auto-best in-tab play: search torrents for the selection, pick the best
  /// instantly-playable source, and play — never leaving the Search tab.
  PlaybackMeta _metaFor(AdvancedSearchSelection sel) => PlaybackMeta.catalog(
    // Only a real IMDb id here — the launcher's Trakt auto-sync + local
    // Continue Watching must never fire on an empty or non-IMDb (IPTV) id,
    // even though the search itself still uses sel.imdbId (the addon id).
    imdbId: sel.imdbId.startsWith('tt') ? sel.imdbId : null,
    contentType: sel.contentType ?? (sel.isSeries ? 'series' : 'movie'),
    season: sel.season,
    episode: sel.episode,
    title: sel.title,
    posterUrl: sel.posterUrl,
    year: sel.year,
    addonId: _activeAddonId,
    traktProgressPercent: sel.traktProgressPercent,
    // Trakt-row plays scrobble to Trakt instead of saving a duplicate local
    // Continue Watching entry (mirrors Home passing selection.traktSource).
    traktScrobble: sel.traktSource,
    simklProgressPercent: sel.simklProgressPercent,
    simklScrobble: sel.simklSource,
    mdblistProgressPercent: sel.mdblistProgressPercent,
    mdblistScrobble: sel.mdblistSource,
    art: _artFor(sel.imdbId, sel.title),
  );

  /// Loader artwork for the title being played, captured by [_onCatalogPlay]
  /// from the catalog meta it already holds. Presentation only.
  ///
  /// Keyed, because plays reach [_metaFor] through selections this screen did
  /// not build (tracker continue-watching rows, the episode picker) — an
  /// unkeyed stash would paint the previous title's backdrop behind the next
  /// play. A miss simply means no art, which the loader already handles.
  PlayLoaderArt? _pendingPlayArt;
  String? _pendingPlayArtKey;

  void _capturePlayArt(StremioMeta item) {
    final key = _playArtKey(item.effectiveImdbId ?? item.id, item.name);
    // The detail page publishes a strictly richer version of the same title
    // (logo, runtime, rating, certificate — none of which catalog rows carry),
    // so never let the row's sparse copy overwrite it.
    if (_pendingPlayArt != null && _pendingPlayArtKey == key) return;
    final art = PlayLoaderArt.fromMeta(item);
    if (art.isEmpty) {
      _pendingPlayArt = null;
      _pendingPlayArtKey = null;
      return;
    }
    _pendingPlayArt = art;
    _pendingPlayArtKey = key;
  }

  /// The detail page's enrichment, replacing whatever the row had.
  void _adoptDetailPlayArt(StremioMeta item, PlayLoaderArt art) {
    _pendingPlayArt = art;
    _pendingPlayArtKey = _playArtKey(
      item.effectiveImdbId ?? item.id,
      item.name,
    );
  }

  static String _playArtKey(String? id, String title) =>
      '${id ?? ''}|${title.trim().toLowerCase()}';

  PlayLoaderArt? _artFor(String? id, String title) {
    final art = _pendingPlayArt;
    if (art == null) return null;
    // Either half matching is enough: tracker rows carry the IMDb id but often
    // a differently-punctuated title, and id-less addon titles carry neither.
    final key = _playArtKey(id, title);
    if (key == _pendingPlayArtKey) return art;
    final storedId = _pendingPlayArtKey?.split('|').first ?? '';
    if (storedId.isNotEmpty && id == storedId) return art;
    return null;
  }

  /// Catalog auto-best play — the service picks the provider, shows the real
  /// cinematic overlay, searches, and plays (with source list + content
  /// metadata so the in-player Sources switcher + Continue Watching work).
  Future<void> _playSelection(AdvancedSearchSelection sel) async {
    // Playback is about to change every resume signal — never let a
    // pre-playback reconciled answer survive into the post-playback reads.
    _seriesResumeCache.clear();
    // Row quick-play skips the detail page, so there's no detail route whose
    // pop can drive the post-playback refresh — this method has to do it. WHEN
    // it can depends on the player: the in-app route only completes the await
    // below once it pops (playback over, progress final), while an external
    // activity returns control immediately, still mid-launch. Latch which one
    // took the stream so a native/external launch doesn't fire a pointless
    // tracker refetch while the player is still opening — its real refresh
    // arrives via _onPlaybackReturned.
    var external = false;
    void onExternal() => external = true;
    MainPageBridge.addExternalPlayerLaunchListener(onExternal);
    try {
      await TorrentPlaybackService.playFromSelection(
        context,
        imdbId: sel.imdbId,
        isMovie: !sel.isSeries,
        season: sel.season,
        episode: sel.episode,
        meta: _metaFor(sel),
        // This is the user's own Play press, so it honors "Play button opens".
        // The selection already carries the exact season/episode the button was
        // going to play, so the manual list opens on that episode — no next-up
        // resolution here, and no way for the list to disagree with the button.
        openSourcePicker: () => _browseSelection(sel, forcePlayOnTap: true),
      );
    } finally {
      MainPageBridge.removeExternalPlayerLaunchListener(onExternal);
    }
    if (!mounted) return;
    // The full refresh only when the in-app player has genuinely finished AND
    // the board is what's on screen. An external launch is still opening, and a
    // detail page / See-All on top owns the refresh through its own route
    // callback — the latch keeps that deferred pass aware playback happened, so
    // skipping here loses nothing and avoids refreshing an invisible board.
    final boardOnTop = ModalRoute.of(context)?.isCurrent ?? false;
    if (external || !boardOnTop) {
      // Old-screen parity: a movie auto-binds its source on play, so refresh
      // the board's bound badges (harmless no-op for series and non-IMDb
      // titles, which don't auto-bind).
      await _refreshBoundSources();
      return;
    }
    await _refreshAfterPlayback();
  }

  /// Manual sources list in-tab — the screen searches itself (own loading) and
  /// each tap plays with the full source list + content metadata.
  void _browseSelection(
    AdvancedSearchSelection sel, {
    // Set only by the Play-button hand-off: the press already said "play", so
    // the row the user picks must not re-ask via the post-torrent action.
    bool forcePlayOnTap = false,
  }) {
    // Every route into the manual list lands here — the Play-button hand-off,
    // the movie Sources button, and the episode long-press — so this is where
    // the episode the list will search is finally fixed.
    debugPrint(
      '[SeriesResume] picker-open title="${sel.title}" id=${sel.imdbId} '
      'target=S${sel.season}E${sel.episode} label="${sel.formattedLabel}"',
    );
    if (sel.imdbId.isEmpty) {
      _snack('No IMDb match to find sources for "${sel.title}".');
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TvHeldKeyGuard(
              child: _SourcesScreen(
                selection: sel,
                meta: _metaFor(sel),
                isTelevision: widget.isTelevision,
                forcePlayOnTap: forcePlayOnTap,
              ),
            ),
          ),
        )
        // A long-press pin/unpin may have happened in the sources list — and a
        // tap PLAYS, so the board's Continue Watching can be stale too (the
        // player sits above this screen, so nothing else refreshes for it).
        .then((_) => _refreshAfterPlayback());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The TV Home board is TRANSPARENT down to the app shell: the glass stage
    // (TvAmbientArtStage, painted BEHIND the sidebar rail in main.dart) is the
    // real background, so the focused title's blurred art fills the whole
    // screen — rail strip included. Every other mode keeps the opaque indigo
    // bloom below.
    final glassHome = _heroTrailerActive;
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: glassHome ? Colors.transparent : app.home.bg,
      // A restrained indigo bloom near the top fading fast into near-black —
      // toned down from a saturated purple so the posters carry the colour
      // (Stremio's home grid is nearly monochrome).
      body: Container(
        decoration: glassHome ? null : BoxDecoration(gradient: app.home.wash),
        // Four layouts:
        //  • Dedicated Search tab (searchMode) — the field + Catalog/Keyword
        //    toggle over a blank prompt until the user types (TV only).
        //  • Home-New board on TV — chrome-free hero + rows, no search bar
        //    (search lives in its own tab).
        //  • Off-TV Home with Spotlight selected — the full-bleed shell with
        //    search behind a button (see _buildSpotlightShell). The hero owns
        //    the status-bar region, so SafeArea's top inset is the shell's to
        //    manage.
        //  • Home-New board on desktop/mobile classic — keeps a persistent
        //    search bar above the board; the separate Search tab is an
        //    additional way in on TV and sidebar layouts, not a replacement.
        child: widget.discoverMode
            ? SafeArea(child: _buildDiscover())
            : (widget.isTelevision && !widget.searchMode)
            ? SafeArea(child: _buildBoard())
            : _spotlightShellActive
            ? _buildSpotlightShell()
            : SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildUnifiedCatalogSourcesBar(),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
      ),
    );
  }

  /// Off-TV Home while Spotlight is selected: one branch, two states.
  ///
  /// Sheet hidden — the board is full-bleed (the hero owns the status-bar
  /// region, like the detail page already does) with a search button floating
  /// top-right. Sheet open — today's search layout exactly: the same
  /// `_buildHeader()` + Sources bar + `_buildBody()` the classic branch
  /// renders, so nothing about search is a copy. `_buildBody` (never
  /// `_buildBoard` directly): Keyword-mode routing lives there.
  ///
  /// The latch line below is the belt to the focus-listener's braces: any
  /// build that observes a force condition (keyword mode, committed query,
  /// in-flight search) pins the sheet open, so a state that arrives without
  /// the field ever being touched — the async keyword-default restore — still
  /// opens it. Plain field write, deliberately not setState: we are already
  /// inside build, and the value participates in this very frame.
  Widget _buildSpotlightShell() {
    if (_sheetForced) _searchSheetOpen = true;
    if (_searchSheetOpen) {
      return SafeArea(
        child: Column(
          children: [
            // Close affordance: only on the blank catalog prompt — with any
            // query or keyword state active, Back (hardware or gesture) is
            // the way out, and it resets atomically via _closeSearchSheet.
            if (!_sheetForced && _searchController.text.isEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Hide search',
                    onPressed: _closeSearchSheet,
                  ),
                ),
              ),
            _buildHeader(),
            _buildUnifiedCatalogSourcesBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      );
    }
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
          Positioned(
            top: topInset + 10,
            right: _SpotlightSearchButton.rightInset,
            child: _SpotlightSearchButton(
              onTap: () => setState(() {
                _searchSheetOpen = true;
                // Focus the field once the sheet's frame exists, so the
                // keyboard comes up in the same gesture.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _searchFocusNode.requestFocus();
                });
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// Show/hide the unified catalog Sources bar as the search field gains/loses
  /// focus. The hide is DELAYED: clicking the Sources button blurs the field,
  /// and hiding synchronously would unmount the button before its onTap fires
  /// (the bug where "clicking Sources does nothing"). The delay keeps it up
  /// long enough for the tap; a re-focus within the window cancels the hide.
  void _onSearchFocusForSources() {
    if (_searchFocusNode.hasFocus) {
      _catalogSourcesHideTimer?.cancel();
      if (!_catalogSourcesBarShown) {
        setState(() => _catalogSourcesBarShown = true);
      }
    } else {
      _catalogSourcesHideTimer?.cancel();
      _catalogSourcesHideTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && _catalogSourcesBarShown) {
          setState(() => _catalogSourcesBarShown = false);
        }
      });
    }
  }

  /// On the unified (non-TV) layout there's no dedicated Search tab, so the
  /// catalog Sources button lives just under the search field and appears while
  /// that field is focused (clicked into) in Catalog mode — click away and it
  /// hides. TV keeps it in the dedicated Search tab's prompt instead, so this
  /// renders nothing there.
  Widget _buildUnifiedCatalogSourcesBar() {
    if (widget.isTelevision || widget.searchMode) {
      return const SizedBox.shrink();
    }
    final show = _catalogSourcesBarShown && _mode == _Mode.catalog;
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _catalogSourcesButton(),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final tv = widget.isTelevision;
    // On narrow phones the search box + mode selector crowd each other in one
    // row, so stack the selector underneath. When even the stacked three labels
    // cannot fit, [_ModeToggle] becomes a single dropdown.
    final hasLists = kMdblistEnabled && _isMdblistAuthenticated;
    // Reserve the three-mode layout whenever the integration is compiled in,
    // even before the async auth check lands. This avoids a one-frame inline →
    // stacked jump for connected users on medium-width windows.
    final narrowBreakpoint = kMdblistEnabled ? 900.0 : 620.0;
    final narrow = !tv && MediaQuery.of(context).size.width < narrowBreakpoint;
    final compactModeMenu = _useCompactModeMenu;

    final field = _buildSearchField(tv);
    final toggle = _ModeToggle(
      mode: _mode,
      isTelevision: tv,
      listsAvailable: hasLists,
      fullWidth: narrow,
      compact: compactModeMenu,
      onChanged: _switchMode,
      // Keyboard/DPAD wiring (both desktop + TV): the segments are focusable;
      // up/left leave back to the search field, down drops into the content,
      // select switches mode.
      catalogNode: _modeCatalogNode,
      keywordNode: _modeKeywordNode,
      listsNode: _modeListsNode,
      dropdownNode: _modeDropdownNode,
      onLeaveToField: _focusSearchFieldAtEnd,
      onLeaveToContent: _focusContent,
    );

    if (narrow) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, tv ? 16 : 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field, const SizedBox(height: 10), toggle],
        ),
      );
    }

    // Wide/TV: a centered pill search (Stremio-style) with the mode toggle
    // pinned to the right. A left spacer matching the toggle keeps the search
    // truly centered (sized for the three-segment Catalog/Keyword/Lists bar).
    return Padding(
      padding: EdgeInsets.fromLTRB(20, tv ? 18 : 14, 20, 10),
      child: Row(
        children: [
          SizedBox(width: compactModeMenu ? 156 : 252),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: field,
              ),
            ),
          ),
          const SizedBox(width: 12),
          toggle,
        ],
      ),
    );
  }

  /// Centered translucent pill search — mirrors Stremio's search bar (rounded
  /// pill, centered text, a search glyph on the right that becomes a clear ✕).
  Widget _buildSearchField(bool tv) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final radius = app.shape.br(26);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          // Pre-search Sources button (keyword or catalog empty state) is the
          // only content, and _focusContent keeps focus on the field there —
          // so target it directly, otherwise Down is a dead end.
          if (_kwSourcesButtonVisible) {
            _kwSourcesBtnFocus.requestFocus();
          } else if (_catalogSourcesButtonVisible) {
            _catalogSourcesBtnFocus.requestFocus();
          } else {
            _focusContent();
          }
          return KeyEventResult.handled;
        }
        // Arrow-up jumps to the Catalog/Keyword toggle (top-right). Works on
        // both TV (DPAD) and desktop (keyboard) — up is safe to intercept, a
        // single-line field doesn't use it for the cursor and nothing sits
        // above the search field.
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _focusModeToggle();
          return KeyEventResult.handled;
        }
        // Arrow-right reaches the toggle too — its natural spatial direction —
        // but only once the caret is at the very end of the text, so right
        // still moves the cursor through what you've typed first. A blank field
        // (or caret already at the end) jumps to the toggle immediately.
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final text = _searchController.text;
          final sel = _searchController.selection;
          final atEnd =
              text.isEmpty ||
              sel.baseOffset < 0 ||
              (sel.isCollapsed && sel.baseOffset >= text.length);
          if (atEnd) {
            _focusModeToggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored; // let the caret move right first
        }
        // Arrow-left is handled via a Shortcuts override on the field (below),
        // not here — an EditableText consumes left-at-start for the caret before
        // an ancestor Focus.onKeyEvent can see it.
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          final hasText = value.text.isNotEmpty;
          // TvTextField: on TV (Debrify keyboard on) this is a shell — DPAD
          // landing draws the focus ring but never opens a keyboard; OK
          // starts editing with the in-app DPAD keyboard. Off TV / opted out
          // it renders the same plain TextField as before.
          final field = TvTextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onQueryChanged,
            onSubmitted: _onQuerySubmitted,
            textInputAction: TextInputAction.search,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface, fontSize: tv ? 16 : 15),
            // Shell-mode LEFT: no caret exists at the shell, so left always
            // escapes to the sidebar (the LEFT-only sidebar policy). While
            // EDITING, left moves the keyboard highlight instead — TvTextField
            // consumes it internally. The Shortcuts wrapper below still covers
            // the opted-out plain-TextField path.
            onLeftArrow: tv
                ? () => MainPageBridge.focusTvSidebar?.call()
                : null,
            // Explicit up/down so BOTH keyboard modes use the curated targets
            // (mirrors the ancestor Focus handler below, which otherwise only
            // sees keys the field lets bubble).
            onUpArrow: tv ? _focusModeToggle : null,
            onDownArrow: tv
                ? () {
                    if (_kwSourcesButtonVisible) {
                      _kwSourcesBtnFocus.requestFocus();
                    } else if (_catalogSourcesButtonVisible) {
                      _catalogSourcesBtnFocus.requestFocus();
                    } else {
                      _focusContent();
                    }
                  }
                : null,
            decoration: InputDecoration(
              hintText: switch (_mode) {
                _Mode.catalog => 'Search or paste link',
                _Mode.keyword => 'Search torrents by keyword',
                _Mode.lists => 'Search MDBList lists',
              },
              hintStyle: TextStyle(color: app.fade(app.core.tx, 0.32)),
              suffixIcon: hasText
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: app.fade(app.core.tx, 0.55),
                      ),
                      onPressed: _clearQuery,
                    )
                  : Icon(
                      Icons.search_rounded,
                      color: app.fade(app.core.tx, 0.4),
                    ),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: app.fade(app.home.chromeAccent, 0.6),
                ),
              ),
              filled: true,
              fillColor: app.fade(app.core.tx, 0.06),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: tv ? 16 : 14,
              ),
            ),
          );
          // TV: wrap the field so left-arrow on an EMPTY field escapes to the
          // sidebar (the intuitive direction) — the text editor would otherwise
          // silently eat it. The wrapper is ALWAYS present (a stable subtree root,
          // so typing/clearing never tears the EditableText down); the action
          // disables itself once there's text, so the framework's own caret and
          // selection handling takes over untouched.
          if (!tv) return field;
          return Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _SearchLeftIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SearchLeftIntent: _EmptyFieldLeftAction(
                  _searchController,
                  () => MainPageBridge.focusTvSidebar?.call(),
                ),
              },
              child: field,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == _Mode.keyword) return _buildKeyword();
    if (_mode == _Mode.lists) return _buildListsSearch();
    // Full-screen spinner only until the FIRST result row streams in — after
    // that the board renders and late rows append beneath it (a slim progress
    // strip in _buildBoard signals the search is still running).
    if (_catalogSearching && _sections.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // Dedicated Search tab: blank prompt until there's a query (no hero/board).
    if (widget.searchMode && _catalogQuery.isEmpty) {
      return _buildSearchPrompt();
    }
    return _buildBoard();
  }

  /// Open the full grid of every list that matched the current search. The rail
  /// already holds the complete `/lists/search` result set, so this hands that
  /// list straight to the See-All screen (no refetch, no paging).
  ///
  /// Unlike the rail tap (which jumps to the Discover tab), opening a list from
  /// this grid PUSHES the list's items on top of the grid, so Back retraces
  /// list items → grid → search results — letting the user browse several
  /// lists in a row.
  void _openListsSeeAll() {
    final query = _listsQuery;
    final results = List<MdblistListChoice>.of(_listsResults);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (gridCtx) => MdblistListsSeeAllScreen(
          query: query,
          lists: results,
          isTelevision: widget.isTelevision,
          // Push onto the grid's navigator so Back returns here.
          onOpen: (list) => _openMdblistListItems(gridCtx, list),
        ),
      ),
    );
  }

  /// Push an MDBList list's items as a standalone screen (non-embedded
  /// [MdblistSeeAllScreen]) above [pushCtx]'s route. Reuses the exact item-open
  /// and quick-play handlers the Discover tab wires for MDBList items, so a
  /// title opens / quick-plays identically — just with a Back that returns to
  /// whatever was under the route (the lists grid, or the Search board on TV)
  /// instead of a tab switch. [onReturn] runs after the route pops.
  void _openMdblistListItems(
    BuildContext pushCtx,
    MdblistListChoice list, {
    VoidCallback? onReturn,
  }) {
    Navigator.of(pushCtx)
        .push(
          MaterialPageRoute(
            builder: (_) => MdblistSeeAllScreen(
              initialList: list,
              isTelevision: widget.isTelevision,
              isBound: _isBound,
              onOpen: (item) => _openItem(
                item,
                _addonForContinue(item.sourceAddon?.id),
                isMdblistSource: true,
              ),
              onQuickPlay: _pikpakOnly
                  ? null
                  : (item) => _onCatalogPlay(
                      item,
                      _addonForContinue(item.sourceAddon?.id),
                      isMdblistSource: true,
                    ),
            ),
          ),
        )
        .then((_) {
          _afterSeeAllReturn();
          onReturn?.call();
        });
  }

  Widget _buildListsSearch() {
    if (_listsSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listsError != null) {
      return _message(
        Icons.error_outline_rounded,
        'MDBList search failed',
        _listsError!,
      );
    }
    if (_listsQuery.isEmpty) {
      final app = AppThemeScope.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.playlist_play_rounded,
                size: 54,
                color: app.fade(app.core.tx, 0.22),
              ),
              const SizedBox(height: 16),
              Text(
                'Search MDBList lists',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.8),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Find public lists by name, then open or save them in MDBList.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.5),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_listsResults.isEmpty) {
      return _message(
        Icons.playlist_remove_rounded,
        'No MDBList lists found',
        'No public lists matched "$_listsQuery".',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 32),
      children: [_buildListsRailRow()],
    );
  }

  /// The MDBList list-search result rail. Same 2:3 card
  /// footprint as the poster rows; each card is a gradient tile (list glyph +
  /// centred name + items/likes footer, no artwork). Select opens the list's
  /// items — pushed over the board on TV (Back returns here), or in the
  /// Discover tab on mobile/laptop. DPAD: up → search field, left off card 0 →
  /// sidebar (TV); the single result rail deliberately holds Down in place.
  Widget _buildListsRailRow() {
    final posterW = _railPosterW(context);
    final posterH = posterW * 3 / 2;
    final rowH = posterH + 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader(
          title: 'MDBList Lists',
          tag: 'LISTS',
          // Mobile/laptop get a "See All" link (auto-hidden on TV, where the
          // rail is DPAD-scrollable) → full grid of every matched list.
          onSeeAll: _openListsSeeAll,
        ),
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 400,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: _listsResults.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: SizedBox(
                width: posterW,
                height: posterH,
                child: _buildListRailCard(_listsResults[index], index),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One gradient list-card in the lists rail (see [_buildListsRailRow]).
  Widget _buildListRailCard(MdblistListChoice list, int index) {
    final tv = widget.isTelevision;
    final node = index < _listsNodes.length ? _listsNodes[index] : null;
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (isActivateKey(key)) {
          _openListsResult(list);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (index > 0) {
            _listsNodes[index - 1].requestFocus();
          } else if (tv) {
            MainPageBridge.focusTvSidebar?.call();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          if (index < _listsNodes.length - 1) {
            _listsNodes[index + 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _leaveBoardTop();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          // Lists is a dedicated single-rail search mode; there is no unrelated
          // catalog row below it to receive focus.
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          if (focused) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (node != null && node.hasFocus && context.mounted) {
                Scrollable.ensureVisible(
                  context,
                  alignment: 0.5,
                  alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  duration: const Duration(milliseconds: 150),
                );
              }
            });
          }
          return MdblistListCard(
            list: list,
            focused: focused,
            onTap: () => _openListsResult(list),
          );
        },
      ),
    );
  }

  /// Empty state for the dedicated Search tab before the user types.
  Widget _buildSearchPrompt() {
    final app = AppThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 54,
              color: app.fade(app.core.tx, 0.22),
            ),
            const SizedBox(height: 16),
            Text(
              'Search movies & shows',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.8),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            // Only reached in Catalog mode — _buildBody routes Keyword mode to
            // _buildKeyword (which has its own empty state) before it gets here.
            Text(
              'Type a title to search your catalogs, or switch to Keyword to '
              'search torrents directly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.5),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            // Pick which searchable addons the catalog search queries. Mirrors
            // the keyword tab's Sources button; DPAD reaches it via the search
            // field's Down (see _catalogSourcesButtonVisible).
            _catalogSourcesButton(),
          ],
        ),
      ),
    );
  }

  /// "Sources" button for catalog search — opens a dialog to enable/disable
  /// the search-capable addons, persisted across launches. Catalog-mode twin
  /// of [_kwSourcesButton].
  Widget _catalogSourcesButton() {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _catalogSourcesBtnFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          _openCatalogSources();
          return KeyEventResult.handled;
        }
        // Up returns to the search field, Left hands off to the sidebar.
        if (key == LogicalKeyboardKey.arrowUp) {
          _focusSearchFieldAtEnd();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          MainPageBridge.focusTvSidebar?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _catalogSourcesBtnFocus,
        builder: (context, _) {
          final focused = _catalogSourcesBtnFocus.hasFocus;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openCatalogSources,
              borderRadius: app.shape.brPill,
              canRequestFocus: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: app.shape.brPill,
                  border: Border.all(
                    color: focused
                        ? app.fade(app.core.tx, 0.9)
                        : app.fade(app.core.tx, 0.10),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dns_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sources',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Open the catalog Sources dialog, then re-run the search if one is active
  /// (so toggling an addon reflects immediately, like the keyword twin).
  Future<void> _openCatalogSources() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _CatalogSourcesDialog(),
    );
    if (!mounted) return;
    if (_catalogQuery.isNotEmpty) {
      _runCatalogSearch(_catalogQuery);
    }
  }

  Widget _buildKeyword() {
    if (_kwLoading) {
      // Branded phased loader (parity with the old screen) instead of a bare
      // spinner. Keyword search is never series-aware, so isSeries stays false.
      return SearchLoadingAnimation(
        phase: SearchPhase.searching,
        isTelevision: widget.isTelevision,
      );
    }
    if (_kwError != null) {
      return _message(Icons.error_outline_rounded, 'Search failed', _kwError!);
    }
    if (_kwQuery.isEmpty) {
      // Surface Sources before searching so users can enable/disable the
      // trackers that get queried up front.
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _kwSourcesButton(),
            ),
          ),
          Expanded(
            child: _message(
              Icons.bolt_rounded,
              'Keyword torrent search',
              'Type a title and press search to find torrents across your '
                  'enabled sources, then tap one to play. Use Sources to choose '
                  'which trackers are queried.',
            ),
          ),
        ],
      );
    }
    final narrow =
        !widget.isTelevision && MediaQuery.of(context).size.width < 600;
    // Apply a restored scroll offset once the list is laid out, then clear it so
    // it only fires on the first build after a restore.
    if (_pendingKwScroll != null && _kwResults.isNotEmpty) {
      final off = _pendingKwScroll!;
      _pendingKwScroll = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _kwScroll.hasClients) {
          _kwScroll.jumpTo(off.clamp(0.0, _kwScroll.position.maxScrollExtent));
        }
      });
    }
    final content = Column(
      children: [
        // Tabs are suppressed during multi-select: switching source mid-select
        // would hide checked rows under the user while "Add · N" still counts
        // them (matching the toolbar's own selection lock-out).
        if (_kwTabsVisible && !_kwSelectionMode) _kwSourceTabs(),
        _buildKeywordToolbar(floatingSelect: narrow),
        if (_kwSearching) _kwSearchingStrip(),
        if (_kwCachedOnly && _kwAll.isNotEmpty) _kwCachedOnlyNotice(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _kwResults.isEmpty
                    ? _message(
                        Icons.search_off_rounded,
                        _kwAll.isEmpty ? 'No results' : 'No matches',
                        _kwAll.isEmpty
                            ? 'Nothing found for "$_kwQuery". Try different '
                                  'keywords or enable more sources.'
                            : 'No results match your filters. Adjust or clear them.',
                      )
                    : NotificationListener<ScrollNotification>(
                        // A user drag (not programmatic scrolls) freezes live
                        // reshuffling — arrivals park behind the pill instead.
                        onNotification: (n) {
                          if (n is ScrollStartNotification &&
                              n.dragDetails != null) {
                            _kwFreeze();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _kwScroll,
                          // A focused SourceRow can scale and rise in
                          // Spotlight. The first item starts at scroll offset
                          // zero, so it needs real viewport clearance rather
                          // than relying on ensureVisible to make room.
                          padding: EdgeInsets.symmetric(
                            vertical: widget.isTelevision ? 24 : 8,
                            horizontal: 10,
                          ),
                          cacheExtent: 1200,
                          itemCount: _kwResults.length,
                          itemBuilder: (context, i) {
                            final t = _kwResults[i];
                            final selectable =
                                !t.isDirectStream && !t.isExternalStream;
                            final isStream = !selectable;
                            final labels =
                                _kwCache[t.infohash.toLowerCase()] ?? const [];
                            final tags = isStream
                                ? const <FormatTag>[]
                                : FormatTagDetector.detect(t.name);
                            return SourceRow(
                              key: ValueKey(
                                '${t.infohash}_${_kwSelectionMode}_${_kwSelected.contains(t.infohash)}',
                              ),
                              title: t.displayTitle,
                              titleMaxLines: 6,
                              subtitle: _kwRowSubtitle(t),
                              focusNode: _kwNodes[i],
                              isTelevision: widget.isTelevision,
                              showPlayPill: widget.isTelevision,
                              formatTags: tags,
                              badgeName: t.name,
                              badgeDescription: t.badgeDescription,
                              qualityTag: tags.isEmpty
                                  ? _SourcesScreenState._qualityLabel(t)
                                  : null,
                              cacheLabel: labels.isEmpty
                                  ? null
                                  : labels.join(' | '),
                              streamBadge: t.isExternalStream
                                  ? 'External'
                                  : t.isDirectStream
                                  ? 'Direct'
                                  : null,
                              isSelectionMode: _kwSelectionMode && selectable,
                              isSelected: _kwSelected.contains(t.infohash),
                              onCopy: _kwSelectionMode || t.copyLink == null
                                  ? null
                                  : () => unawaited(_copyKwLink(t)),
                              onTap: () {
                                if (_kwSelectionMode && selectable) {
                                  _toggleKwSelection(t);
                                  return;
                                }
                                // Swallow a SELECT that leaks through as a toolbar
                                // dialog (sort/filter/sources) closes on TV.
                                if (DialogTapGuard.shouldIgnoreTap()) return;
                                // Playing pushes the player — freeze so the list
                                // is exactly as left when the user comes back.
                                _kwFreeze();
                                unawaited(
                                  TorrentPlaybackService.activateTorrent(
                                    context,
                                    t,
                                    // Pass the whole result set so the in-player Sources
                                    // switcher can hop to any other keyword hit (parity
                                    // with the old screen, which always passed _torrents).
                                    sources: _kwResults,
                                    sourceIndex: i,
                                    searchKeyword: _kwQuery,
                                  ),
                                );
                              },
                              onLongPress: _kwSelectionMode
                                  ? null
                                  : selectable
                                  ? () {
                                      _enterKwSelection();
                                      _toggleKwSelection(t);
                                    }
                                  // Direct/external streams aren't selectable — long
                                  // press opens their Play/Copy/Download menu instead
                                  // (parity with the old direct-stream action dialog).
                                  : () {
                                      _kwFreeze();
                                      _showKwStreamMenu(t, i);
                                    },
                              onNavigateUp: () {
                                _kwFreeze();
                                if (i > 0) {
                                  _kwNodes[i - 1].requestFocus();
                                } else if (_kwPendingNewCount > 0 &&
                                    !_kwSelectionMode) {
                                  // Parked arrivals: the pill is the row above
                                  // (unmounted during multi-select, where UP
                                  // must reach the selection toolbar instead).
                                  _kwPillFocus.requestFocus();
                                } else if (_kwToolbarVisible) {
                                  // From the top row, Up lands on the toolbar (Sort…),
                                  // not straight back to the search field.
                                  _kwToolbarNodes.first.requestFocus();
                                } else {
                                  _searchFocusNode.requestFocus();
                                }
                              },
                              onNavigateDown: () {
                                _kwFreeze();
                                if (i < _kwNodes.length - 1) {
                                  _kwNodes[i + 1].requestFocus();
                                }
                              },
                            );
                          },
                        ),
                      ),
              ),
              // Frozen-mode arrivals wait behind this pill so the list never
              // reshuffles under the user. Hidden during multi-select —
              // adopting would renumber rows under the checkmarks.
              if (_kwPendingNewCount > 0 && !_kwSelectionMode)
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(child: _kwNewResultsPill()),
                ),
            ],
          ),
        ),
      ],
    );

    if (!narrow) return content;
    // Small screens: Home-style floating select FAB / selection bar overlaid
    // on the results, instead of the toolbar "Select" pill.
    final canSelect = _kwSelectableResults.isNotEmpty;
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (canSelect)
          _kwSelectionMode ? _buildKwSelectionBar() : _buildKwSelectFab(),
      ],
    );
  }

  /// Standalone "Sources" pill shown in the pre-search keyword state so users
  /// can pick which trackers are queried before typing a query.
  Widget _kwSourcesButton() {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _kwSourcesBtnFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          _openKeywordSources();
          return KeyEventResult.handled;
        }
        // It's the only content in the pre-search state: Up returns to the
        // search field, Left hands off to the sidebar. Down has nowhere to go.
        if (key == LogicalKeyboardKey.arrowUp) {
          _focusSearchFieldAtEnd();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          MainPageBridge.focusTvSidebar?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _kwSourcesBtnFocus,
        builder: (context, _) {
          final focused = _kwSourcesBtnFocus.hasFocus;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openKeywordSources,
              borderRadius: app.shape.brPill,
              canRequestFocus: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: app.shape.brPill,
                  // 1.5px always so focus never shifts layout: white ring when
                  // focused, else the faint idle border.
                  border: Border.all(
                    color: focused
                        ? app.fade(app.core.tx, 0.9)
                        : app.fade(app.core.tx, 0.10),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dns_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sources',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// `size · ↑seeders · ↓leechers · SOURCE · date` meta line for a keyword
  /// row — same grammar as the Sources screen's rows (shared SourceRow look).
  static String _kwRowSubtitle(Torrent t) {
    final parts = <String>[];
    if (t.isDirectStream || t.isExternalStream) {
      if (t.sizeBytes > 0) {
        parts.add(_SourcesScreenState._fmtSize(t.sizeBytes));
      }
      if (t.source.isNotEmpty) parts.add(t.source.toUpperCase());
      return parts.join(' · ');
    }
    if (t.sizeBytes > 0) parts.add(_SourcesScreenState._fmtSize(t.sizeBytes));
    if (t.seeders > 0) parts.add('↑ ${t.seeders}');
    if (t.leechers > 0) parts.add('↓ ${t.leechers}');
    if (t.source.isNotEmpty) parts.add(t.source.toUpperCase());
    final date = _SourcesScreenState._fmtDate(t.createdUnix);
    if (date != null) parts.add(date);
    return parts.join(' · ');
  }

  /// Display name for a source tab ('stremio:foo' → 'Foo').
  static String _kwPrettySource(String s) {
    final v = s.startsWith('stremio:') ? s.substring(8) : s;
    return v.isEmpty ? s : v[0].toUpperCase() + v.substring(1);
  }

  /// Horizontal source tabs (All / per-source with counts) above the toolbar —
  /// the fast single-select layer on top of the Providers multi-select. Only
  /// built when [_kwTabsVisible] (2+ sources). Derives from [_kwFullSet]:
  /// counts tick and new source pills appear live even while the rows below
  /// are frozen behind the pill (activating any tab folds the parked set in
  /// first, so what a tab press shows is always the complete picture). DPAD:
  /// left/right across tabs, up to the search field, down into the toolbar,
  /// select to activate.
  Widget _kwSourceTabs() {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final dim = app.fade(app.core.tx, 0.55);
    final sources = _kwSourceList;
    final full = _kwFullSet;
    final counts = <String, int>{};
    for (final t in full) {
      counts[_kwSourceOf(t)] = (counts[_kwSourceOf(t)] ?? 0) + 1;
    }
    final total = sources.length + 1;

    Widget tab(int navIndex, String label, bool on, VoidCallback onTap) {
      // Nodes are synced in _recomputeKeyword; a mid-build mismatch (e.g. the
      // strip rebuilt by a non-recompute setState) must not range-crash.
      final node = navIndex < _kwTabNodes.length ? _kwTabNodes[navIndex] : null;
      Widget body(bool focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on ? accent : app.fade(app.core.tx, 0.05),
          borderRadius: app.shape.brPill,
          // Always 2px so focus never shifts layout.
          border: Border.all(
            color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            // Scored against the fill the selected tab actually paints.
            // `accent` IS the theme accent, and white fails on 17 of the 18
            // selectable themes (Noir's and Frost's are #FFFFFF), so a
            // hardcoded white label vanished into its own pill. Legacy's
            // #7B5CFF scores 4.36 against white, so inkOn still returns white
            // there — no visual change to today's app.
            color: on ? app.inkOn(accent) : dim,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      final Widget tappable = node == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: app.shape.brPill,
                child: body(false),
              ),
            )
          : Focus(
              focusNode: node,
              onKeyEvent: (n, e) => _handleKwTabKey(navIndex, total, onTap, e),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: app.shape.brPill,
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );
      return Padding(padding: const EdgeInsets.only(right: 6), child: tappable);
    }

    // SingleChildScrollView + Row (not a lazy ListView) so EVERY tab's
    // FocusNode stays mounted — requestFocus on an unmounted node is a silent
    // no-op that would strand DPAD at the viewport edge (same reason the
    // keyword toolbar uses this shape).
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            tab(
              0,
              'All · ${full.length}',
              _kwSourceTab == null,
              () => _setKwSourceTab(null),
            ),
            for (var i = 0; i < sources.length; i++)
              tab(
                i + 1,
                '${_kwPrettySource(sources[i])} · ${counts[sources[i]] ?? 0}',
                _kwSourceTab == sources[i],
                () => _setKwSourceTab(sources[i]),
              ),
          ],
        ),
      ),
    );
  }

  /// Focus a source tab AND scroll the strip to reveal it — a bare
  /// requestFocus doesn't scroll, so an off-screen tab would take focus
  /// invisibly.
  void _focusKwTab(int index) {
    if (index < 0 || index >= _kwTabNodes.length) return;
    final node = _kwTabNodes[index];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (mounted && ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  void _setKwSourceTab(String? source) {
    final tabHadFocus = _kwTabNodes.any((n) => n.hasFocus);
    // A deliberate reshuffle: fold parked arrivals in so the tab filters the
    // complete set (also freezes further live updates).
    _kwFreezeAndAdopt();
    // The tapped source can vanish in the adopt (dedupe reattribution) — an
    // active tab no longer in the strip would strand an empty list.
    if (source != null && !_kwAll.any((t) => _kwSourceOf(t) == source)) {
      source = null;
    }
    if (_kwSourceTab != source) {
      _kwSourceTab = source;
      _recomputeKeyword();
    }
    // Tab nodes are positional and the adopt can re-sort _kwSourceList —
    // re-anchor DPAD focus onto the tab that was actually chosen.
    if (tabHadFocus) {
      final s = source;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final idx = s == null ? 0 : _kwSourceList.indexOf(s) + 1;
        _focusKwTab(idx > 0 && idx < _kwTabNodes.length ? idx : 0);
      });
    }
  }

  /// DPAD/keyboard handling for a focused source tab: select activates,
  /// left/right move between tabs (left edge escapes to the sidebar), up
  /// returns to the search field, down drops into the toolbar pills.
  KeyEventResult _handleKwTabKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _focusSearchFieldAtEnd();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _kwToolbarNodes.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _focusKwTab(index - 1);
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) _focusKwTab(index + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Slim "still searching" strip under the toolbar while engines are in
  /// flight — rows are already usable, this just says more may arrive.
  Widget _kwSearchingStrip() {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Still searching sources…',
            style: TextStyle(
              fontSize: 11.5,
              color: app.fade(app.core.tx, 0.55),
            ),
          ),
        ],
      ),
    );
  }

  /// The "+N new results" pill: tap (or OK on TV) folds the parked arrivals
  /// into the list; DOWN returns to the rows, UP reaches the toolbar.
  Widget _kwNewResultsPill() {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final n = _kwPendingNewCount;
    return Focus(
      focusNode: _kwPillFocus,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(e.logicalKey)) {
          _kwAdoptPending();
          if (_kwNodes.isNotEmpty) _kwNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_kwNodes.isNotEmpty) _kwNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          _kwToolbarNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _kwPillFocus,
        builder: (context, _) {
          final focused = _kwPillFocus.hasFocus;
          return GestureDetector(
            onTap: _kwAdoptPending,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: focused ? app.core.tx : accent,
                borderRadius: app.shape.brPill,
                border: Border.all(
                  color: focused ? app.core.tx : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    // Unfocused the pill is FILLED with the accent, so its ink
                    // has to be scored against it — white is invisible on the
                    // near-white accents (Noir, Frost, Vault). The focused
                    // branch keeps its dark ink on the white focus fill.
                    color: focused
                        ? const Color(0xFF17131F)
                        : app.inkOn(accent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$n new result${n == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: focused
                          ? const Color(0xFF17131F)
                          : app.inkOn(accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// [floatingSelect] true on small screens where the multi-select entry is a
  /// floating FAB + bar (Home-style) rather than a toolbar pill — so the
  /// toolbar stays Sort/Filters/Sources and never swaps to selection controls.
  Widget _buildKeywordToolbar({bool floatingSelect = false}) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Every facet counts. Sizes were already missing here, so a size-only
    // filter quietly trimmed the results while the pill still read "Filters"
    // and rendered inactive — the same trap a dynamic-range-only filter would
    // fall into.
    final filterCount =
        _kwFilters.qualities.length +
        _kwFilters.ripSources.length +
        _kwFilters.languages.length +
        _kwFilters.sizes.length +
        _kwFilters.dynamicRanges.length;

    // [navIndex]/[navTotal], when provided, make the pill keyboard/DPAD
    // focusable at that position in the toolbar (left/right between pills, up to
    // the search field, down into the results, select to activate).
    Widget pill(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
      bool compact = false,
      int? navIndex,
      int navTotal = 0,
    }) {
      Widget body(bool focused) => Container(
        padding: compact
            ? const EdgeInsets.all(10)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: app.shape.brPill,
          // Always 2px so focus never shifts layout: white ring when
          // focused, else the active/idle border.
          border: Border.all(
            color: focused
                ? app.fade(app.core.tx, 0.9)
                : active
                ? scheme.primary.withValues(alpha: 0.5)
                : app.fade(app.core.tx, 0.10),
            width: 2,
          ),
        ),
        child: compact
            ? Icon(
                icon,
                size: 18,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
      );

      final Widget tappable = navIndex == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: app.shape.brPill,
                child: body(false),
              ),
            )
          : Focus(
              focusNode: _kwToolbarNodes[navIndex],
              onKeyEvent: (n, event) =>
                  _handleKwToolbarKey(navIndex, navTotal, onTap, event),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: app.shape.brPill,
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );

      return Padding(padding: const EdgeInsets.only(right: 8), child: tappable);
    }

    if (_kwSelectionMode && !floatingSelect) {
      final selectable = _kwSelectableResults.length;
      final count = _kwSelected.length;
      final allSelected = count > 0 && count == selectable;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            pill(
              Icons.close_rounded,
              'Cancel',
              _exitKwSelection,
              navIndex: 0,
              navTotal: 3,
            ),
            pill(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              allSelected ? 'None' : 'All',
              allSelected ? _deselectAllKw : _selectAllKw,
              navIndex: 1,
              navTotal: 3,
            ),
            pill(
              Icons.playlist_add_rounded,
              count > 0 ? 'Add · $count' : 'Add',
              count > 0 ? _openBulkAdd : () {},
              active: count > 0,
              navIndex: 2,
              navTotal: 3,
            ),
          ],
        ),
      );
    }

    final canSelect = _kwSelectableResults.isNotEmpty;
    final showSelect = canSelect && !floatingSelect;
    final showProviders = _kwHasProviderFilter;
    final providerActive = _kwProviderFilterActive;
    // Build the pill set dynamically so navIndex stays contiguous when the
    // optional Providers / Select pills come and go. Base pills always present:
    // Sort, Filters, Sources (3); Providers and Select are optional.
    final total = 3 + (showProviders ? 1 : 0) + (showSelect ? 1 : 0);
    var idx = 0;
    final pills = <Widget>[
      pill(
        Icons.sort_rounded,
        'Sort · ${_sortLabel(_kwSort)}',
        _openKeywordSort,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      pill(
        Icons.filter_list_rounded,
        filterCount > 0 ? 'Filters · $filterCount' : 'Filters',
        _openKeywordFilters,
        active: filterCount > 0,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      if (showProviders)
        pill(
          Icons.hub_rounded,
          providerActive > 0 ? 'Providers · $providerActive' : 'Providers',
          _openKeywordProviders,
          active: providerActive > 0,
          compact: floatingSelect,
          navIndex: idx++,
          navTotal: total,
        ),
      pill(
        Icons.dns_rounded,
        'Sources',
        _openKeywordSources,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      if (showSelect)
        pill(
          Icons.checklist_rounded,
          'Select',
          _enterKwSelection,
          navIndex: idx++,
          navTotal: total,
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(children: pills),
    );
  }

  /// DPAD/keyboard handling for a focused keyword-toolbar pill: select fires the
  /// pill, left/right move between pills, up returns to the search field, down
  /// drops into the first result row.
  KeyEventResult _handleKwToolbarKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // Source tabs sit between the toolbar and the search field — land on
      // the active tab so the strip context is obvious. Hidden during
      // multi-select (the strip is suppressed then — see _buildKeyword).
      if (!_kwSelectionMode && _kwTabsVisible && _kwTabNodes.isNotEmpty) {
        final tabs = _kwSourceList;
        final active = _kwSourceTab == null
            ? 0
            : tabs.indexOf(_kwSourceTab!) + 1;
        _focusKwTab(active >= 0 && active < _kwTabNodes.length ? active : 0);
        return KeyEventResult.handled;
      }
      _focusSearchFieldAtEnd();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_kwNodes.isNotEmpty) {
        _kwNodes.first.requestFocus();
      } else if (_kwPendingNewCount > 0 && !_kwSelectionMode) {
        // Zero rows (e.g. a no-match filter) but arrivals parked behind the
        // pill: the pill must stay reachable or it's visible-but-dead on TV.
        _kwPillFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _kwToolbarNodes[index - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) _kwToolbarNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Floating checklist FAB (bottom-left) that enters multi-select on small
  /// screens — ported from Home's torrent-search layout.
  Widget _buildKwSelectFab() {
    final app = AppThemeScope.of(context);
    return Positioned(
      left: 16,
      bottom: 16,
      child: GestureDetector(
        onTap: _enterKwSelection,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: app.home.controlBg,
            shape: BoxShape.circle,
            border: Border.all(color: app.fade(app.core.tx, 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.checklist_rounded, color: app.core.tx, size: 20),
        ),
      ),
    );
  }

  /// Floating multi-select bar (bottom) — Home-style. Right-inset so it clears
  /// the mobile floating "Menu" nav.
  Widget _buildKwSelectionBar() {
    final app = AppThemeScope.of(context);
    final selectable = _kwSelectableResults.length;
    final count = _kwSelected.length;
    final allSelected = count > 0 && count == selectable;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    Widget chip(Widget child, VoidCallback? onTap, Color bg) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: app.shape.br(8)),
        child: child,
      ),
    );

    return Positioned(
      left: 12,
      // Clear the bottom-right "Menu" FAB — which only the floating nav
      // style has; the classic bar occupies its own strip below the page.
      right: MainPageBridge.phoneNavStyleCached == 'floating' ? 108 : 12,
      bottom: 12 + bottomPad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: app.shape.br(16),
          border: Border.all(color: app.fade(app.home.chromeAccent, 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            chip(
              Icon(
                Icons.close_rounded,
                color: app.core.tx.withValues(alpha: 0xB3 / 0xFF),
                size: 18,
              ),
              _exitKwSelection,
              app.fade(app.core.tx, 0.1),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '$count selected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: count > 0
                      ? app.home.chromeAccent
                      : app.core.tx.withValues(alpha: 0x8A / 0xFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            chip(
              Text(
                allSelected ? 'None' : 'All',
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0xB3 / 0xFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              allSelected ? _deselectAllKw : _selectAllKw,
              app.fade(app.core.tx, 0.08),
            ),
            const SizedBox(width: 8),
            chip(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    // Enabled, this chip is filled with the OPAQUE accent, so
                    // its ink is scored against it (white disappears on Noir's
                    // and Frost's #FFFFFF accent). Disabled, the fill is a 0.3
                    // wash over the dark bar, where white38 still reads.
                    color: count > 0
                        ? app.inkOn(app.home.chromeAccent)
                        : Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Add',
                    style: TextStyle(
                      color: count > 0
                          ? app.inkOn(app.home.chromeAccent)
                          : Colors.white38,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              count > 0 ? _openBulkAdd : null,
              count > 0
                  ? app.home.chromeAccent
                  : app.fade(app.home.chromeAccent, 0.3),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(String s) =>
      const {
        'relevance': 'Relevance',
        'seeders': 'Seeders',
        'size': 'Size',
        'date': 'Date',
        'name': 'Name',
      }[s] ??
      s;

  /// Poster width for a board rail. On TV the logical canvas can be as short as
  /// 540px (a 1080p panel at density 320 → devicePixelRatio 2.0), where a poster
  /// tuned for a 720-logical canvas leaves no room for a row (plus its header and
  /// the next row's header) under the hero. So scale the poster with the screen
  /// height.
  double _railPosterW(BuildContext context) =>
      homeRailPosterWidth(context, isTelevision: widget.isTelevision);

  /// TITLE-card size for a classic board rail under the Home Cards
  /// orientation. Landscape keeps Spotlight's proportions — about 1.6× the
  /// poster's width, which lands the row at ~60% of the poster row's height —
  /// so backdrops stay readable without a full-poster-height slab of 16:9.
  /// Favourites/channel/playlist cells ignore this and stay on
  /// [_railPosterW]'s portrait geometry.
  double _railTitleCardW(BuildContext context) {
    final posterW = _railPosterW(context);
    return _homeLandscapeCards ? posterW * 1.6 : posterW;
  }

  double _railTitleCardH(BuildContext context) =>
      _railTitleCardW(context) / _titleCardAspect;

  /// TV hero band budget — Concept-5 geometry (tv_home_mockup): the hero owns
  /// ~60% of the board; below it exactly ONE titleless card row fits, plus a
  /// ~24px peek of the NEXT row's header — the "there's more" cue. Budgeted
  /// against the short catalog-row height on purpose: a taller favourites rail
  /// (inline captions) clips at the fold rather than shrinking the hero for
  /// everyone. The Search tab keeps its compact strip via the clamp.
  double _tvHeroBudget(double boardH) {
    final catalogRowH = _railTitleCardH(context) + 14;
    return (boardH - _railHeaderH - catalogRowH - 24).clamp(
      150.0,
      widget.searchMode ? 180.0 : 440.0,
    );
  }

  /// Approximate height of a rail's header (title row). Matches the padding +
  /// line height in [_railHeader]; used only to budget the hero so a row header
  /// (current and next) stays visible.
  double get _railHeaderH => widget.isTelevision ? 44.0 : 52.0;

  // ── Discover tab ────────────────────────────────────────────────────────────

  /// Load Continue Watching + Trakt rows, then refresh the pinned-source badge
  /// counts once. The board's `_load` does this via `_refreshBoundSources`; the
  /// Trakt loader only refreshes bound counts when Trakt is connected, so
  /// non-Trakt users would otherwise never get badges in Discover.
  Future<void> _primeDiscoverRows() async {
    await Future.wait([
      _loadContinueWatching(),
      _loadTraktContinueWatching(refreshBound: false),
      // Populates _simklAll/_simklProgress for the Simkl source's Continue
      // Watching list (folded into that source, like Trakt's).
      _loadSimklContinueWatching(refreshBound: false),
      _loadMdblistContinueWatching(refreshBound: false),
    ]);
    if (mounted) await _refreshBoundSources();
  }

  /// Apply fixed/remembered sources from local preferences immediately, then
  /// hydrate add-ons separately. Add-on defaults wait only for the inventory
  /// needed to validate them, and a source picked during that wait always wins.
  Future<void> _loadDiscoverAddons() async {
    final revision = _discSourceRevision;
    final values = await Future.wait([
      StorageService.getDiscoverDefaultSource(),
      StorageService.getDiscoverLastSource(),
    ]);
    if (!mounted) return;
    final defaultSource = values[0];
    final lastSource = values[1];
    var landing = defaultSource == StorageService.discoverDefaultRememberLast
        ? lastSource
        : defaultSource;
    final fixedSource =
        landing == _discCw ||
        landing == _discTrakt ||
        landing == _discSimkl ||
        (kMdblistEnabled && landing == _discMdblist);

    // Search→MDBList handoff is a stronger, explicit navigation intent. For
    // ordinary fixed defaults, paint now instead of waiting on manifests.
    if (fixedSource &&
        discoverLandingLoadIsCurrent(
          capturedRevision: revision,
          currentRevision: _discSourceRevision,
          hasPendingHandoff: _discMdblistList != null,
        )) {
      if (_discSource != landing) setState(() => _discSource = landing);
      unawaited(StorageService.setDiscoverLastSource(landing));
    }

    List<StremioAddon> addons = const [];
    try {
      addons = await _stremio.getCatalogAddons();
    } catch (_) {}
    if (!mounted) return;
    final browsable = [
      for (final a in addons)
        if (a.catalogs.any((c) => c.isBrowsable)) a,
    ];
    final addonAvailable =
        landing.startsWith(_discAddonPrefix) &&
        browsable.any((addon) => '$_discAddonPrefix${addon.id}' == landing);
    if (!fixedSource && !addonAvailable) landing = _discCw;
    setState(() {
      _discAddons = browsable;
      for (final a in addons) {
        _addonsById.putIfAbsent(a.id, () => a);
      }
      if (!fixedSource &&
          discoverLandingLoadIsCurrent(
            capturedRevision: revision,
            currentRevision: _discSourceRevision,
            hasPendingHandoff: _discMdblistList != null,
          )) {
        _discSource = landing;
      }
    });
    if (!fixedSource &&
        discoverLandingLoadIsCurrent(
          capturedRevision: revision,
          currentRevision: _discSourceRevision,
          hasPendingHandoff: _discMdblistList != null,
        )) {
      unawaited(StorageService.setDiscoverLastSource(landing));
    }
  }

  /// The Discover tab: a "Source" dropdown over a single browsable grid. Each
  /// source is rendered by the matching See-All panel in [embedded] mode (no
  /// Scaffold/back header), with the Source dropdown injected as its leading
  /// filter so DPAD walks Source → the panel's own filters → grid. All item
  /// open/play/bound wiring is this screen's existing board handlers.
  Widget _buildDiscover() => DiscoverBrowsingInput(
    onActivity: () {
      if (_discTheater.value) _discTheater.value = false;
      // Input can leave the same trailer playing (hover or a grid boundary).
      // Restart its idle dwell even when the playback notifier does not change.
      _onDiscShowingChanged();
    },
    child: _buildDiscoverContent(),
  );

  Widget _buildDiscoverContent() {
    final app = AppThemeScope.of(context);
    final panel = DiscoverCardSettingsScope(
      showTypeTags: _discShowTypeTags,
      showRatings: _discShowRatings,
      showTitles: _discShowTitles,
      child: _buildDiscoverPanel(),
    );
    // Touch has no persistent focus, so a reactive detail rail has nothing to
    // react to — keep the full-width grid there. TV gets the glass-stage
    // two-pane layout.
    if (!widget.isTelevision) return panel;
    return LayoutBuilder(
      builder: (context, c) {
        // Guard a degenerate canvas: too narrow leaves no room for a usable grid
        // beside the rail; too short and the rail's fixed identity block can't
        // fit. Either way, fall back to the full-width panel.
        if (c.maxWidth < 720 || c.maxHeight < 420) {
          // The trailer stage (which drives _discTakeover → sidebar chrome-dim,
          // and _discTrailerShowing → the AMBIENT chip) is unmounted in this
          // branch. Clear both post-frame so nothing sticks across the drop.
          if (_discTakeover.value != 0 ||
              _discTrailerShowing.value ||
              _discTheater.value) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _discTakeover.value = 0;
              _discTrailerShowing.value = false;
              _discTheater.value = false;
            });
          }
          return panel;
        }
        if (_discStage) return _buildDiscoverStage(c, panel);
        final railW = (c.maxWidth * 0.375).clamp(320.0, 460.0);
        final panelW = c.maxWidth - railW;
        final mq = MediaQuery.of(context);
        final twoPane = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: railW,
              // Theater: the identity block ghosts to 15% so the trailer owns
              // the art zone. AnimatedOpacity is acceptable here — the layer is
              // rail-sized (not full-screen), pays its saveLayer only during
              // the ~1.2s ease, and composites as a cached raster once settled.
              // It wraps a SIBLING of the video layer, so the underlay punch is
              // untouched. Lights-up is fast to match the veils' cadence.
              child: ValueListenableBuilder<bool>(
                valueListenable: _discTheater,
                // RepaintBoundary: the rail rebuilds on every DPAD step (new
                // title, logo, plot) — keep that raster confined to the rail
                // column instead of dirtying the stage layer behind it.
                child: RepaintBoundary(
                  child: ValueListenableBuilder<StremioMeta?>(
                    valueListenable: _discFocused,
                    builder: (_, item, __) => DiscoverDetailRail(
                      item: item,
                      trailerStreams: _discTrailerStreams,
                      trailerLoading: _discTrailerLoading,
                      trailerVolume: _discTrailerVolume,
                      trailerMeta: _discTrailerMeta,
                      shownItem: _discShown,
                    ),
                  ),
                ),
                builder: (_, theater, child) => AnimatedOpacity(
                  opacity: theater ? 0.15 : 1.0,
                  duration: theater
                      ? const Duration(milliseconds: 1200)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: child,
                ),
              ),
            ),
            // The grid derives its column count from MediaQuery width; report
            // the panel's (narrower) width so it lays out for its real box
            // instead of the full screen and overflowing.
            SizedBox(
              width: panelW,
              // Theater: the grid itself ghosts to ~12% — fading the CONTENT is
              // the only way to unveil the trailer on this side (any ink wash
              // painted over the panel darkens the video with it, and the
              // opaque posters block it regardless). Same layer rules as the
              // rail's fade: sibling of the video layer (punch untouched),
              // saveLayer only during the ~1.2s ease, cached raster after.
              child: ValueListenableBuilder<bool>(
                valueListenable: _discTheater,
                // RepaintBoundary: the filter line's focus pills repaint on
                // every DPAD move across it (the grid viewport below is its own
                // boundary already) — keep panel chrome out of the stage layer.
                child: RepaintBoundary(
                  child: MediaQuery(
                    data: mq.copyWith(size: Size(panelW, mq.size.height)),
                    child: panel,
                  ),
                ),
                builder: (_, theater, child) => AnimatedOpacity(
                  opacity: theater ? 0.12 : 1.0,
                  duration: theater
                      ? const Duration(milliseconds: 1200)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: child,
                ),
              ),
            ),
          ],
        );
        // The glass stage (bottom → top): base ink wash → the focused title's
        // full-frame backdrop → the ambient trailer (which replaces the still,
        // frame one, across the whole canvas) → the tint veils that keep both
        // panes legible (direct translucent paint — never an Opacity layer, and
        // safe over the underlay video's punched hole, exactly like the Home
        // hero's feathers) → the panes themselves → status chips.
        //
        // Layer discipline (the Home hero's): each stage stratum sits in its
        // own RepaintBoundary so a rail swap (every DPAD step) or a veil
        // transition frame re-rasters only itself. Without the boundaries they
        // all share one picture and every keypress re-records + re-rasters the
        // full-screen backdrop AND both veil gradients on the weak TV GPU —
        // the whole page reads as laggy. These are plain composited layers,
        // not saveLayers, so the underlay video's punch is unaffected.
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(decoration: BoxDecoration(gradient: app.home.wash)),
            RepaintBoundary(child: _DiscoverStageBackdrop(shown: _discShown)),
            DiscoverTrailerStage(
              trailer: _discTrailerStreams,
              loading: _discTrailerLoading,
              volume: _discTrailerVolume,
              meta: _discTrailerMeta,
              railRect: Rect.zero,
              takeover: _discTakeover,
              fullStage: true,
              showing: _discTrailerShowing,
            ),
            RepaintBoundary(
              child: _DiscoverStageVeils(
                showing: _discTrailerShowing,
                theater: _discTheater,
              ),
            ),
            twoPane,
            // Lights-off over the grid side while the trailer plays — the Home
            // rows' recede, transplanted. Above the panes (it dims the posters
            // and filter line), feathered on its left edge so no seam cuts the
            // stage. Animated as a baked color (direct paint), never Opacity.
            _DiscoverGridDim(
              showing: _discTrailerShowing,
              theater: _discTheater,
              leftInset: railW,
            ),
            // Recede the two-pane as the trailer takes over — a baked scrim, not
            // an Opacity layer (whose mid-values force a per-frame full-screen
            // saveLayer on weak TV GPUs). Dormant while the takeover stays
            // disabled, kept wired for its revival.
            ValueListenableBuilder<double>(
              valueListenable: _discTakeover,
              builder: (_, t, __) => t <= 0.001
                  ? const SizedBox.shrink()
                  : IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: app.fade(app.home.bg, 0.92 * t),
                        ),
                      ),
                    ),
            ),
            // Status corner: the Home hero's chip pair, handing over in place —
            // equalizer TRAILER pill while resolving/buffering, AMBIENT chip
            // once frames are up. Anchored bottom-left, in the rail column's
            // permanently-empty zone (the plot is capped at 6 lines, so the
            // identity block never reaches it) — the top-right corner belongs
            // to the filter line, which can wrap two rows on 5-segment sources.
            Positioned(
              bottom: 22,
              left: 24,
              child: ValueListenableBuilder<bool>(
                valueListenable: _discTrailerLoading,
                builder: (_, loading, __) =>
                    _HeroTrailerLoadingPill(visible: loading),
              ),
            ),
            Positioned(
              bottom: 22,
              left: 24,
              child: ValueListenableBuilder<bool>(
                valueListenable: _discTrailerShowing,
                builder: (_, showing, __) => ValueListenableBuilder<bool>(
                  valueListenable: _discTrailerLoading,
                  builder: (_, loading, __) =>
                      _HeroAmbientChip(visible: showing && !loading),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The Discover STAGE layout (`discover_layout` = 'stage', TV only).
  ///
  /// Same stage as the grid's two-pane — same backdrop, same full-canvas
  /// trailer, same theater ladder — with the rail dissolved: the focused
  /// title's art owns the whole frame, its identity block sits bottom-left over
  /// it, and the results become ONE shelf across the bottom. The filter line
  /// stays exactly where the grid put it (top-left of the panel), so UP from
  /// the shelf lands on it just as UP from the grid does.
  ///
  /// It is the SAME panel widget as the grid layout: the See-All screen keeps
  /// owning fetch, filters and paging, and only the arrangement of its results
  /// changes — declared by the [DiscoverShelfScope] wrapped around it here.
  Widget _buildDiscoverStage(BoxConstraints c, Widget panel) {
    final app = AppThemeScope.of(context);
    // Canvas's poster proportion (30% of the board, clamped) so the two
    // full-bleed shelves on this TV read as the same furniture.
    final cardH = (c.maxHeight * 0.30).clamp(140.0, 200.0);
    final metrics = DiscoverShelfMetrics(cardHeight: cardH, hPad: 24);
    // The identity block never crosses the middle of the frame — the art on
    // the right half is the point of this layout.
    final identityMax = (c.maxWidth * 0.5).clamp(320.0, 560.0);
    // What the identity block may occupy while BROWSING: the canvas less the
    // filter band above and the shelf column below. Computed here and handed
    // down, because theater animates that box open — a block that measured
    // its live constraint would gain a plot line mid-glide and jump.
    final identityBudget =
        c.maxHeight -
        _kDiscStageFilterBand -
        (metrics.columnHeight + _kDiscStageIdentityGap);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: app.home.wash)),
        RepaintBoundary(
          child: _DiscoverStageBackdrop(
            shown: _discShown,
            // The identity block settles this feed upstream, so no second
            // dwell here — art and title land together, and they crossfade
            // like the Home board's own full-bleed stage.
            dwell: Duration.zero,
            crossfade: true,
          ),
        ),
        DiscoverTrailerStage(
          trailer: _discTrailerStreams,
          loading: _discTrailerLoading,
          volume: _discTrailerVolume,
          meta: _discTrailerMeta,
          railRect: Rect.zero,
          takeover: _discTakeover,
          fullStage: true,
          showing: _discTrailerShowing,
        ),
        RepaintBoundary(
          child: _DiscoverStageVeils(
            showing: _discTrailerShowing,
            theater: _discTheater,
            stage: true,
          ),
        ),
        // The identity block, bottom-left, clearing exactly what the shelf
        // column below occupies — derived from the same metrics the shelf lays
        // itself out with, never guessed.
        //
        // THEATER: the block glides to the top-left and shrinks — the Canvas
        // board's billboard move, so a clean full-bleed trailer still carries
        // a quiet signature. What actually travels is the title art alone:
        // meta and plot faded out earlier, with [_discTrailerShowing], inside
        // the rail widget. Padding/Align/Scale animate on ONE cadence (slow
        // lights-down, instant lights-up) — three transforms and a layout
        // inset, no repaint of the stage under them.
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _discTheater,
              child: RepaintBoundary(
                child: ValueListenableBuilder<StremioMeta?>(
                  valueListenable: _discFocused,
                  builder: (_, item, __) => DiscoverDetailRail(
                    item: item,
                    layout: DiscoverDetailLayout.stage,
                    trailerShowing: _discTrailerShowing,
                    stageMaxWidth: identityMax,
                    stageBudget: identityBudget,
                    // The Home board's billboard settle: holding a direction
                    // across the shelf costs only the cards' focus visuals,
                    // never an identity rebuild plus a full-bleed decode per
                    // step. The trailer still releases on the first keypress.
                    settleDelay: const Duration(milliseconds: 260),
                    trailerStreams: _discTrailerStreams,
                    trailerLoading: _discTrailerLoading,
                    trailerVolume: _discTrailerVolume,
                    trailerMeta: _discTrailerMeta,
                    shownItem: _discShown,
                  ),
                ),
              ),
              builder: (_, deep, kid) => AnimatedPadding(
                // Browse — top: the filter line's band, so a short canvas
                // makes the block shed its plot rather than grow up under the
                // filters; bottom: exactly what the shelf column occupies.
                // Theater — the block rides up to the top corner instead.
                padding: EdgeInsets.only(
                  top: deep ? 30 : _kDiscStageFilterBand,
                  bottom: deep
                      ? 0
                      : metrics.columnHeight + _kDiscStageIdentityGap,
                ),
                duration: deep
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: AnimatedAlign(
                  alignment: deep ? Alignment.topLeft : Alignment.bottomLeft,
                  duration: deep
                      ? const Duration(milliseconds: 900)
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedScale(
                    scale: deep ? 0.7 : 1.0,
                    alignment: Alignment.topLeft,
                    duration: deep
                        ? const Duration(milliseconds: 900)
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: kid,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Filter line + shelf. Theater recede: the Canvas cadence — slow
        // lights-down, instant lights-up — as a slide + fade. The children
        // stay MOUNTED (opacity only), so DPAD focus survives the dark and the
        // wake keypress still performs its normal move. This is the one
        // full-canvas Opacity on the page; it pays its saveLayer during the
        // ease and composites as a cached raster at rest, exactly like the
        // two-pane's panel fade it replaces.
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: _discTheater,
            child: RepaintBoundary(
              child: DiscoverShelfScope(metrics: metrics, child: panel),
            ),
            builder: (_, deep, kid) => AnimatedSlide(
              offset: deep ? const Offset(0, 0.12) : Offset.zero,
              duration: deep
                  ? const Duration(milliseconds: 900)
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: deep ? 0.0 : 1.0,
                duration: deep
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: kid,
              ),
            ),
          ),
        ),
        // Recede everything as the trailer promotes to a fullscreen takeover —
        // a baked scrim, never an Opacity layer. Dormant while the takeover
        // stays disabled, kept wired for its revival (as in the two-pane).
        ValueListenableBuilder<double>(
          valueListenable: _discTakeover,
          builder: (_, t, __) => t <= 0.001
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: app.fade(app.home.bg, 0.92 * t),
                    ),
                  ),
                ),
        ),
        // Status corner: the same TRAILER→AMBIENT chip pair the two-pane
        // shows, moved to the TOP-right — the bottom-left corner belongs to
        // the identity block here.
        Positioned(
          top: 16,
          right: 22,
          child: ValueListenableBuilder<bool>(
            valueListenable: _discTrailerLoading,
            builder: (_, loading, __) =>
                _HeroTrailerLoadingPill(visible: loading),
          ),
        ),
        Positioned(
          top: 16,
          right: 22,
          child: ValueListenableBuilder<bool>(
            valueListenable: _discTrailerShowing,
            builder: (_, showing, __) => ValueListenableBuilder<bool>(
              valueListenable: _discTrailerLoading,
              builder: (_, loading, __) =>
                  _HeroAmbientChip(visible: showing && !loading),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverPanel() {
    final source = StremioDropdown<String>(
      label: 'Source',
      value: _discSource,
      isTelevision: widget.isTelevision,
      // TV: a quiet violet segment leading the filter line — the row's identity
      // color (chrome accent), distinct from the white filter values.
      quiet: widget.isTelevision,
      quietAccent: true,
      focusNode: _discSourceNode,
      options: [
        const StremioDropdownOption(_discCw, 'Continue Watching'),
        const StremioDropdownOption(_discTrakt, 'Trakt'),
        const StremioDropdownOption(_discSimkl, 'Simkl'),
        // MDBList is hidden for the alpha (kMdblistEnabled) AND only when
        // connected — kept if it's somehow already the active source so the
        // dropdown's value always has a matching option.
        if (kMdblistEnabled &&
            (_isMdblistAuthenticated || _discSource == _discMdblist))
          const StremioDropdownOption(_discMdblist, 'MDBList'),
        for (final a in _discAddons)
          StremioDropdownOption('$_discAddonPrefix${a.id}', a.name),
      ],
      onSelected: (s) {
        if (s == _discSource) return;
        // Swapping source re-mounts the grid and drops DPAD focus back onto the
        // Source dropdown — clear the rail (and the stage backdrop behind it)
        // so they show the prompt/ink, not a stale title from the previous
        // source, until a new tile is focused.
        _discFocused.value = null;
        _discShown.value = null;
        setState(() {
          _discSourceRevision++;
          _discSource = s;
        });
        unawaited(StorageService.setDiscoverLastSource(s));
        // The swap re-mounts the embedded panel (new ValueKey), which re-attaches
        // this shared node; pin the DPAD ring back on the Source dropdown so it
        // isn't lost in the dispose/reattach.
        if (widget.isTelevision) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _discSourceNode.requestFocus();
          });
        }
      },
    );

    if (_discSource == _discTrakt) {
      return TraktSeeAllScreen(
        key: const ValueKey('disc_trakt'),
        cwItems: _traktAll,
        cwProgress: _cwCardMaps(_CwKind.trakt).progress,
        onOpen: _openTraktItem,
        onQuickPlay: _pikpakOnly ? null : _playTraktItem,
        onItemFocused: _onDiscFocused,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    if (_discSource == _discSimkl) {
      return SimklSeeAllScreen(
        key: const ValueKey('disc_simkl'),
        // CW is folded in as the leading "List" option (like the Trakt source).
        // Plain open/play for the browse lists; the CW-aware handlers (resume at
        // the paused/up-next episode) apply ONLY while the CW list is showing.
        cwItems: _simklAll,
        cwProgress: _simklProgress,
        onOpen: _openSimklItem,
        onQuickPlay: _pikpakOnly ? null : _playSimklItem,
        cwOnOpen: _openSimklCwItem,
        cwOnQuickPlay: _pikpakOnly ? null : _playSimklCwItem,
        onItemFocused: _onDiscFocused,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    if (_discSource == _discMdblist) {
      // MDBList items are plain catalog titles (StremioMeta w/ imdb id), so they
      // open and quick-play through the same generic catalog paths as an addon
      // catalog item — no MDBList-specific handlers needed.
      return MdblistSeeAllScreen(
        key: const ValueKey('disc_mdblist'),
        initialList: _discMdblistList,
        onOpen: (item) => _openItem(
          item,
          _addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        ),
        onQuickPlay: _pikpakOnly
            ? null
            : (item) => _onCatalogPlay(
                item,
                _addonForContinue(item.sourceAddon?.id),
                isMdblistSource: true,
              ),
        onItemFocused: _onDiscFocused,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
        embedded: true,
        leading: source,
        leadingNode: _discSourceNode,
      );
    }

    // An installed addon catalog source.
    if (_discSource.startsWith(_discAddonPrefix)) {
      final addon = _addonsById[_discSource.substring(_discAddonPrefix.length)];
      final catalog = addon?.catalogs.cast<StremioAddonCatalog?>().firstWhere(
        (c) => c != null && c.isBrowsable,
        orElse: () => null,
      );
      if (addon != null && catalog != null) {
        return CatalogSeeAllScreen(
          key: ValueKey('disc_${addon.id}'),
          addon: addon,
          initialCatalog: catalog,
          isTelevision: widget.isTelevision,
          onOpenItem: (item) => _openItem(item, addon),
          onQuickPlay: _pikpakOnly
              ? null
              : (item) => _onCatalogPlay(item, addon),
          onItemFocused: _onDiscFocused,
          embedded: true,
          leading: source,
          leadingNode: _discSourceNode,
        );
      }
      // Addon vanished (uninstalled) — fall through to Continue Watching.
    }

    // Default: Continue Watching.
    return ContinueWatchingSeeAllScreen(
      key: const ValueKey('disc_cw'),
      title: 'Continue Watching',
      items: _cwAll,
      progressOf: (m) => _cwCardProgress(_CwKind.local, m),
      onOpen: _openContinueItem,
      onQuickPlay: _pikpakOnly ? null : _onContinuePlay,
      onItemFocused: _onDiscFocused,
      isBound: _isBound,
      isTelevision: widget.isTelevision,
      embedded: true,
      leading: source,
      leadingNode: _discSourceNode,
      // Re-fetch when a detail/player route pops back so finished titles drop out
      // (the quick-play path doesn't reload _cwAll on its own).
      onReload: () async {
        await _loadContinueWatching();
        if (!mounted) return const <StremioMeta>[];
        return List<StremioMeta>.of(_cwAll);
      },
    );
  }

  bool _focusCatalogContinuation() {
    final target = [_catalogContinueNode, _catalogMoreNode]
        .where(
          (node) => node.parent != null && (node.context?.mounted ?? false),
        )
        .firstOrNull;
    if (target == null) return false;
    final origin = FocusManager.instance.primaryFocus;
    if (!identical(origin, target)) _catalogReturnFocus = origin;
    target.requestFocus();
    return true;
  }

  void _restoreCatalogContinuationFocus() {
    if (focusMountedHomeNode([
      _catalogReturnFocus,
      _stageFocusTarget(),
      for (final rail in _canvasRails) ..._canvasRailNodes(rail),
    ])) {
      return;
    }
    MainPageBridge.focusTvSidebar?.call();
  }

  Future<void> _continueHomeCatalogs({required bool moreCatalogs}) async {
    if (_catalogContinuing || _boardLoadingMore) return;
    final pending = _sections
        .where((s) => s.pagingPaused && !s.exhausted)
        .toList();
    if (pending.any((s) => s.loadingMore)) return;
    final gen = _boardLoadGen;
    final actionNode = moreCatalogs ? _catalogMoreNode : _catalogContinueNode;
    final ownedFocus = actionNode.hasFocus;
    setState(() => _catalogContinuing = true);
    try {
      if (moreCatalogs) {
        if (_boardHasMore) await _loadMoreBoard();
      } else if (pending.isNotEmpty) {
        final offset = _catalogContinueCursor % pending.length;
        final batch = [
          ...pending.skip(offset),
          ...pending.take(offset),
        ].take(4);
        _catalogContinueCursor = (offset + 4) % pending.length;
        for (final section in batch) {
          if (!mounted || gen != _boardLoadGen) return;
          final i = _sections.indexOf(section);
          if (i >= 0) await _loadMoreRow(i, resume: true);
        }
      }
    } finally {
      if (mounted) setState(() => _catalogContinuing = false);
      if (mounted && gen == _boardLoadGen && ownedFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _boardLoadGen) return;
          // Busy buttons retain focus. Restore only when the completed action
          // disappeared, and do not override a user's move to another card.
          if (actionNode.parent != null &&
              (actionNode.context?.mounted ?? false)) {
            return;
          }
          final focused = FocusManager.instance.primaryFocus;
          if (focused != null && focused is! FocusScopeNode) return;
          _restoreCatalogContinuationFocus();
        });
      }
    }
  }

  Widget _buildBoard() {
    final pending = [
      for (var i = 0; i < _sections.length; i++)
        if (_sections[i].pagingPaused && !_sections[i].exhausted) i,
    ];
    final hasMoreCatalogs = _boardHasMore;
    final showContinuation =
        pending.isNotEmpty ||
        (hasMoreCatalogs && _sections.every((s) => s.items.isEmpty));
    final busy =
        _catalogContinuing ||
        _boardLoadingMore ||
        pending.any((i) => _sections[i].loadingMore);
    return Column(
      children: [
        Expanded(
          child:
              !_loading &&
                  _error == null &&
                  _sections.isNotEmpty &&
                  _sections.every((s) => s.items.isEmpty) &&
                  !_cwVisible &&
                  !_anyFavVisible
              ? _message(
                  Icons.movie_filter_rounded,
                  !showContinuation
                      ? 'No unwatched titles found'
                      : 'No new titles loaded yet',
                  !showContinuation
                      ? 'Try another catalog or turn off Hide watched titles in Tracking settings.'
                      : 'Continue browsing to check more titles in these catalogs.',
                )
              : _buildBoardContent(),
        ),
        if (!_loading && showContinuation)
          SafeArea(
            top: false,
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _restoreCatalogContinuationFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  if (pending.isNotEmpty)
                    CatalogContinuationButton(
                      focusNode: _catalogContinueNode,
                      autofocus: _sections.every((s) => s.items.isEmpty),
                      busy: busy,
                      label: 'Continue paused rows',
                      onPressed: () =>
                          _continueHomeCatalogs(moreCatalogs: false),
                    ),
                  if (hasMoreCatalogs)
                    CatalogContinuationButton(
                      focusNode: _catalogMoreNode,
                      autofocus:
                          pending.isEmpty &&
                          _sections.every((s) => s.items.isEmpty),
                      busy: busy,
                      label: 'Load more catalogs',
                      onPressed: () =>
                          _continueHomeCatalogs(moreCatalogs: true),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBoardContent() {
    if (_loading) {
      // The brand moment: DEBRIFY centred on the ink while catalogs load —
      // replaces the old skeleton-rail wall, which read as a broken app.
      return BrandLoadingStage(isTelevision: widget.isTelevision);
    }
    if (_error != null) {
      return _message(
        Icons.error_outline_rounded,
        "Couldn't load catalogs",
        _error!,
        onRetry: () => unawaited(_load()),
      );
    }
    final showCw = _cwVisible;
    // Don't fall through to the empty-state message while Trakt rows are being
    // reserved — the skeletons below are the board's content until the fetch
    // settles, and showing "No catalogs yet" first would flip to rows with the
    // exact reflow the reservation exists to prevent.
    if (_sections.isEmpty && !showCw && !_anyFavVisible && !_traktReserving) {
      if (_catalogQuery.isNotEmpty) {
        return _message(
          Icons.search_off_rounded,
          'No catalog matches',
          _catalogSearchFailures > 0
              ? 'Nothing in your catalogs for "$_catalogQuery" — and '
                    '$_catalogSearchFailures source'
                    '${_catalogSearchFailures == 1 ? '' : 's'} didn\'t '
                    'respond, so there may be more. Try again, or switch to '
                    'Keyword to search torrents directly.'
              : 'Nothing in your catalogs for "$_catalogQuery". Try different '
                    'keywords, or switch to Keyword to search torrents '
                    'directly.',
        );
      }
      return _message(
        Icons.travel_explore_rounded,
        'No catalogs yet',
        'Install a catalog add-on (e.g. Cinemeta) from Addons to browse '
            'movies and shows here.',
      );
    }

    // STAGE layouts: each owns the whole screen and has its own build path
    // (the loading / error / empty guards above are shared with classic).
    switch (_homeStyleEffective) {
      case 'canvas':
        return _buildCanvasBoard();
      case 'atrium':
        return _buildAtriumBoard();
      case 'mosaic':
        return _buildMosaicBoard();
      case 'promenade':
        return _buildPromenadeBoard();
      case 'deck':
        return _buildDeckBoard();
      case 'tonight':
        return _buildTonightBoard();
      case 'spotlight':
        // The shared guard above lets dispatch through whenever ANY rail has
        // content — including favourites, which Spotlight still does not draw
        // (they are not `StremioMeta`). So test what this board will actually
        // render, not what the screen has: a stylish empty board is worse than
        // classic.
        if (_spotlightShelves.every((s) => s.items.isEmpty)) break;
        return _buildSpotlightBoard();
    }

    final tv = widget.isTelevision;
    final width = MediaQuery.of(context).size.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the hero from the board's own height (below the search header) so a
        // full poster row plus the current + next row headers always stay on
        // screen. On a short-canvas TV (~540 logical) the hero shrinks; tall
        // canvases keep it large and reveal more rows.
        //
        // On the dedicated Search tab it's a compact strip, not a full spotlight:
        // the search field above it already eats vertical space, and results —
        // not a cinematic hero — should dominate, so cap it well below the board's
        // so the first result row isn't squeezed.
        // Fixed hero height, sized to leave a full card row visible below. It is
        // deliberately NOT resized when the trailer plays: animating this band
        // would relayout the rows ListView and re-fit the playing video texture
        // every frame (weak-TV stutter), and would bounce the rows on every
        // focus-rest/move as trailers start and stop. The full-bleed cover-crop
        // of a 16:9 trailer into this wide-short band is accepted as inherent.
        final heroH = tv
            ? _tvHeroBudget(constraints.maxHeight)
            : (width >= 900 ? 300.0 : 196.0);

        // The ambient trailer is hosted BEHIND the spotlight, in the hero band
        // only — a full-bleed frame that covers the band; the spotlight fades its
        // still + text out on play. No fullscreen takeover; the video never
        // moves, resizes or re-fits, so playback simply continues.
        return Stack(
          fit: StackFit.expand,
          children: [
            // The GLASS STAGE (focused title's blurred art) lives in the
            // APP SHELL now (TvAmbientArtStage in main.dart) so it also
            // fills the strip behind the sidebar rail; this board's
            // scaffold is transparent over it and publishes the art/tint
            // via MainPageBridge (see _publishAmbientArt).
            // (The old "ambient colour bleed" — a tinted wash flooding the
            // rows while the trailer played, then draining out on stop — is
            // gone by user call. Playback now reads as LIGHTS DOWN instead:
            // neutral graded veils over the rows (_dimRowsForTrailer) and the
            // hero canvas (spotlight's stage-dim), no hue swinging in/out.
            // The always-on mood field above is the only colour, and it
            // doesn't react to playback at all.)
            _buildTrailerTakeoverRecede(
              Column(
                children: [
                  // The hero spotlight only changes as DPAD focus moves across tiles, so
                  // it's meaningful on TV only. On phones/desktop (no DPAD) it would just
                  // sit frozen on the first item and waste vertical space — hide it.
                  // On the dedicated Search tab it shows once there are results (to help
                  // disambiguate similarly-named titles) but stays hidden on the blank
                  // prompt. See [_heroActive].
                  if (_heroActive)
                    ValueListenableBuilder<StremioMeta?>(
                      valueListenable: _heroItem,
                      builder: (context, item, _) {
                        if (item == null) return const SizedBox.shrink();
                        return ValueListenableBuilder<StremioMeta?>(
                          valueListenable: _heroEnriched,
                          builder: (context, enriched, __) {
                            return _HeroSpotlight(
                              item: item,
                              background: item.background?.isNotEmpty == true
                                  ? item.background
                                  : enriched?.background,
                              description: item.description?.isNotEmpty == true
                                  ? item.description
                                  : enriched?.description,
                              // Catalog list items usually omit the rating; fall back
                              // to the enriched /meta details.
                              rating: item.imdbRating ?? enriched?.imdbRating,
                              runtime:
                                  item.runtimeDisplay ??
                                  enriched?.runtimeDisplay,
                              // Catalog rows rarely carry the title-treatment
                              // art; the enriched /meta details usually do —
                              // but that roundtrip lands AFTER first paint, so
                              // derive the metahub URL from the IMDb id and
                              // start loading it immediately (for tt items the
                              // enriched logo IS this URL, so nothing swaps
                              // when the details arrive).
                              logo: item.logo?.isNotEmpty == true
                                  ? item.logo
                                  : (enriched?.logo?.isNotEmpty == true
                                        ? enriched!.logo
                                        : _derivedHeroLogo(item)),
                              compact: widget.searchMode,
                              isTelevision: tv,
                              height: heroH,
                              artworkCacheWidth: tv
                                  ? (_homeBoardMode
                                        ? _tvHeroArtworkCacheWidth
                                        : HomeTheme.heroBackdropCacheWidthTv)
                                  : HomeTheme.heroBackdropCacheWidth,
                              artworkCacheHeight: tv
                                  ? (_homeBoardMode
                                        ? _tvHeroArtworkCacheHeight
                                        : HomeTheme.heroBackdropCacheHeightTv)
                                  : null,
                              tint: _heroTint,
                              // The Concept-5 stage (region key art + colour
                              // field, text capped at the region's left edge)
                              // is the TV Home LAYOUT, full stop — driven by
                              // the synchronous getter only, never by the
                              // async Settings read (_heroTrailerEnabled).
                              // That read used to pick the layout and could
                              // land AFTER first paint (or never trigger a
                              // rebuild), flipping the hero mid-session; now
                              // it only gates whether a video actually plays
                              // in the region (see _scheduleHeroTrailer).
                              // Trailers-off users keep the same stage — the
                              // region simply always shows the key art.
                              boxedTrailer: _heroTrailerActive,
                              // Pill lives in the trailer region now.
                              trailerLoading: null,
                              // Still passed so the backdrop's Ken Burns drift
                              // freezes while the trailer plays (boxedTrailer
                              // suppresses the image FADE, not this freeze).
                              trailerShowing: _heroTrailerActive
                                  ? _heroTrailerShowing
                                  : null,
                              // An IPTV favourite took the boxed region — this
                              // item's colour field/identity text describe
                              // something that isn't playing anymore, so hide
                              // them (see [_HeroSpotlight.liveTakeover]).
                              liveTakeover: _heroTrailerActive
                                  ? _heroLiveTakeover
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  // Slim, non-focusable status strip for a streaming catalog search:
                  // a hairline progress bar while rows are still arriving, then a
                  // quiet "N sources didn't respond" note if any catalog errored.
                  // Lives above the rows so it never takes DPAD focus and appends
                  // below never move it.
                  if (_catalogQuery.isNotEmpty &&
                      (_catalogSearching || _catalogSearchFailures > 0))
                    _buildSearchStatusStrip(),
                  Expanded(
                    child: _dimRowsForTrailer(
                      Builder(
                        builder: (context) {
                          // Home uses one globally ordered descriptor list across
                          // every row family. Catalog search results never read
                          // that Home order.
                          final orderedHome = _homeRowOrderActive;
                          final homeRails = orderedHome
                              ? _classicHomeRails
                              : const <_CanvasRail>[];
                          final revealPrefix = 'board-reveal-$_boardGen-';
                          final homeRailIndex = <String, int>{
                            for (var i = 0; i < homeRails.length; i++)
                              _canvasRailRowId(homeRails[i]): i,
                          };
                          int? findHomeRailIndex(Key key) {
                            if (!orderedHome || key is! ValueKey<String>) {
                              return null;
                            }
                            final value = key.value;
                            if (!value.startsWith(revealPrefix)) return null;
                            return homeRailIndex[value.substring(
                              revealPrefix.length,
                            )];
                          }

                          final showFooter = _boardLoadingMore;
                          return ListView.builder(
                            controller: _boardScroll,
                            // A lazy sliver cannot relocate a keyed child by
                            // itself. Tracker/CW rows can arrive above the
                            // focused row, so provide the new index to preserve
                            // its entrance state and Focus attachment.
                            findChildIndexCallback: orderedHome
                                ? findHomeRailIndex
                                : null,
                            padding: const EdgeInsets.only(top: 6, bottom: 32),
                            // ~1.5 rows of pre-build. Smaller extent means
                            // smaller, more frequent builds on weak TV chips.
                            cacheExtent: 300,
                            itemCount:
                                (orderedHome
                                    ? homeRails.length
                                    : _sections.length) +
                                (showFooter ? 1 : 0),
                            itemBuilder: (context, i) {
                              Widget row;
                              var revealIdentity = 'index:$i';
                              if (orderedHome && i < homeRails.length) {
                                final rail = homeRails[i];
                                final rowId = _canvasRailRowId(rail);
                                revealIdentity = rowId;
                                if (rail.traktSkeletonIndex >= 0) {
                                  row = _buildTraktSkeletonRow(
                                    rail.traktSkeletonIndex,
                                  );
                                } else if (rail.cw != null) {
                                  row = _buildContinueWatchingRow(
                                    rail.cw!,
                                    rail.cwIndex,
                                    rowId,
                                  );
                                } else if (rail.favKind != null) {
                                  row = _buildFavRow(rail.favKind!, rowId);
                                } else {
                                  row = _buildRow(
                                    rail.sectionIndex!,
                                    homeRowId: rowId,
                                  );
                                }
                              } else if (orderedHome) {
                                return _buildBoardFooter();
                              } else {
                                final s = i;
                                if (s >= _sections.length) {
                                  return _buildBoardFooter();
                                }
                                row = _buildRow(s);
                              }
                              // Staggered entrance for the first screenful of
                              // rows when a fresh board lands.
                              final fresh =
                                  DateTime.now().difference(_boardAppliedAt) <
                                  const Duration(milliseconds: 1800);
                              return _EntranceReveal(
                                key: ValueKey('$revealPrefix$revealIdentity'),
                                play: fresh && i < 6,
                                delayMs: 60 * i,
                                child: row,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The ambient trailer, painted into a right-anchored region of the
            // hero whose edges dissolve into the backdrop (premium-OTT blend).
            // Sits ABOVE the board as an IgnorePointer overlay so the video
            // paints over the hero backdrop while the title/rows keep DPAD focus;
            // the spotlight reserves the right zone (boxedTrailer) so the crisp
            // trailer never overlaps the title text.
            if (_heroTrailerActive)
              Positioned.fill(
                child: _HeroTrailerLayer(
                  trailer: _heroTrailer,
                  isTelevision: widget.isTelevision,
                  heroHeight: heroH,
                  volume: _heroTrailerVolume,
                  loading: _heroTrailerLoading,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  takeover: _heroTrailerTakeover,
                ),
              ),
            // A focused IPTV favourite's live feed, painted into the SAME
            // region — above the catalog trailer layer so it simply wins
            // whenever a channel has focus (shrinks to nothing otherwise,
            // letting the catalog trailer show through).
            if (_heroTrailerActive)
              Positioned.fill(
                child: _HeroLiveLayer(
                  channel: _heroLiveChannel,
                  streamUrl: _heroLiveUrl,
                  heroHeight: heroH,
                  volume: _heroTrailerVolume,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  onPlaybackFailed: _onHeroLivePlaybackFailed,
                ),
              ),
            // While the film owns the board, only the showcased title's
            // name/plot remain on screen — small, top-left, fully readable.
            if (_heroTrailerActive) _buildTakeoverInfoOverlay(),
          ],
        );
      },
    );
  }

  /// Settles the poster rows back while the ambient trailer plays, so the
  /// moving picture owns the frame (Nuvio/Netflix behavior) and any DPAD move
  /// brings them straight back. Implemented as a flat bg-tinted VEIL fading in
  /// ABOVE the rows — NOT an Opacity around them: fading the rows subtree
  /// meant a rows-viewport-sized saveLayer re-rastered on every frame of the
  /// fade (the "trailer start stutters" kind of cost on a weak TV GPU), while
  /// this is one solid fill that paints nothing at all when idle. Rows live
  /// BELOW the hero band, so the veil can never sit over the trailer
  /// underlay's punch-through hole.
  Widget _dimRowsForTrailer(Widget rows) {
    if (!_heroTrailerActive) return rows;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        rows,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _heroTrailerShowing,
              builder: (context, on, _) => AnimatedOpacity(
                opacity: on ? 1.0 : 0.0,
                // LIGHTS OFF, asymmetric: the theatre dims slowly when the
                // picture starts, but any DPAD move brings the room back
                // FAST so navigation never feels gated by an effect.
                duration: on
                    ? const Duration(milliseconds: 900)
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                // Near-black: the rows become ghosts (a whisper of structure
                // stays so pressing DOWN isn't a leap into a void), graded a
                // touch deeper toward the screen's foot.
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xE00D0B1A), Color(0xFA0D0B1A)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Fades the board UI fully OUT as the trailer takes over — cards, rows and
  /// hero block leave the stage entirely (the compact info overlay replaces
  /// them). GPU-frugal by design:
  ///  • the wrapper tree shape is FIXED (Opacity always present), so the
  ///    board subtree — focus nodes, list scroll state — is never re-parented
  ///    when the takeover starts/ends;
  ///  • Opacity is layer-free at 1.0 and paints nothing at all at 0.0; the
  ///    brief mid-fade is over static content (raster-cache friendly);
  ///  • a TickerMode freezes the hidden board's animators (skeleton shimmers)
  ///    so nothing re-records an invisible subtree per frame.
  /// A short follower tween smooths the driving value, so the instant kill
  /// (focus moved → takeover snaps to 0) eases the board back in ~240ms
  /// instead of popping. Focus stays on the hidden card: any arrow restores
  /// the board, and SELECT opens the very title being showcased.
  Widget _buildTrailerTakeoverRecede(Widget board) {
    if (!_heroTrailerActive) return board;
    return ValueListenableBuilder<double>(
      valueListenable: _heroTrailerTakeover,
      child: board,
      builder: (context, target, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          child: child,
          builder: (context, t, kid) {
            final tt = t.clamp(0.0, 1.0);
            return Opacity(
              opacity: 1.0 - tt,
              child: TickerMode(enabled: tt < 0.95, child: kid!),
            );
          },
        );
      },
    );
  }

  /// The takeover's kinetic lower-third: while the film owns the board its
  /// identity sits bottom-left — a growing accent bar, then a whispered kicker,
  /// a big uppercase title, a `year · runtime · ★rating` line and the genres,
  /// each rising in a staggered cascade timed to the mask-open. Purely
  /// informational (IgnorePointer, no focus nodes); every field degrades to
  /// nothing when absent. The text subtrees are built only when the hero item /
  /// enrichment changes and captured as locals — the per-frame builder just
  /// wraps them in cheap Opacity/Transform, never a full-screen save layer.
  Widget _buildTakeoverInfoOverlay() {
    final app = AppThemeScope.of(context);
    const accentLight = Color(0xFFC4B5FD);
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: _heroItem,
      builder: (context, item, __) {
        if (item == null) return const SizedBox.shrink();
        return ValueListenableBuilder<StremioMeta?>(
          valueListenable: _heroEnriched,
          builder: (context, enriched, ___) {
            final rating = item.imdbRating ?? enriched?.imdbRating;
            final runtime = item.runtimeDisplay ?? enriched?.runtimeDisplay;
            final genres = item.genres?.isNotEmpty == true
                ? item.genres
                : enriched?.genres;

            // year · runtime · ★rating — assembled once per item change.
            final meta = <Widget>[];
            void sep() {
              if (meta.isNotEmpty) meta.add(_takeoverMetaDot());
            }

            if (item.year != null && item.year!.isNotEmpty) {
              meta.add(_takeoverMetaText(item.year!));
            }
            if (runtime != null && runtime.isNotEmpty) {
              sep();
              meta.add(_takeoverMetaText(runtime));
            }
            if (rating != null) {
              sep();
              meta.add(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 17, color: app.home.focus),
                    const SizedBox(width: 4),
                    _takeoverMetaText(rating.toStringAsFixed(1)),
                  ],
                ),
              );
            }

            final kicker = Text(
              'NOW PLAYING  ·  OFFICIAL TRAILER',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: accentLight,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            );
            final title = Text(
              item.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 46,
                fontWeight: FontWeight.w800,
                height: 0.98,
                letterSpacing: -0.5,
                color: app.core.tx,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 18,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            );
            final metaRow = Row(mainAxisSize: MainAxisSize.min, children: meta);
            final genresLine = (genres == null || genres.isEmpty)
                ? const SizedBox.shrink()
                : Text(
                    genres.take(3).join('   •   ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: app.fade(app.core.tx, 0.6),
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  );

            return ValueListenableBuilder<double>(
              valueListenable: _heroTrailerTakeover,
              builder: (context, takeover, ____) {
                if (takeover <= 0.001) return const SizedBox.shrink();
                double seg(double a, double b) =>
                    ((takeover - a) / (b - a)).clamp(0.0, 1.0);
                double eo(double x) {
                  final u = 1 - x;
                  return 1 - u * u * u;
                }

                // Each element rises + fades over its own window of the arc.
                Widget rise(Widget w, double a, double b, {double dist = 14}) {
                  final p = seg(a, b);
                  return Opacity(
                    opacity: p,
                    child: Transform.translate(
                      offset: Offset(0, (1 - eo(p)) * dist),
                      child: w,
                    ),
                  );
                }

                final accentP = eo(seg(0.42, 0.72));
                final slideP = eo(seg(0.42, 0.78));

                return IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(52, 0, 48, 54),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Accent bar grows up from the foot of the block.
                            Transform(
                              alignment: Alignment.bottomCenter,
                              transform: Matrix4.diagonal3Values(1, accentP, 1),
                              child: Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  borderRadius: app.shape.br(4),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      app.home.chromeAccent,
                                      accentLight,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            // The whole text block slides in from the left.
                            Transform.translate(
                              offset: Offset(-46 * (1 - slideP), 0),
                              child: Opacity(
                                opacity: seg(0.42, 0.6),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 720,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      rise(kicker, 0.44, 0.6, dist: 8),
                                      const SizedBox(height: 12),
                                      rise(title, 0.5, 0.8),
                                      if (meta.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        rise(metaRow, 0.66, 0.9, dist: 12),
                                      ],
                                      if (genres != null &&
                                          genres.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        rise(genresLine, 0.76, 1.0, dist: 10),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// A metadata token in the takeover's lower-third meta line.
  Widget _takeoverMetaText(String s) {
    final app = AppThemeScope.of(context);
    return Text(
      s,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: app.fade(app.core.tx, 0.9),
        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
      ),
    );
  }

  /// The dot separator between takeover meta tokens.
  Widget _takeoverMetaDot() {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.45),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// Status strip for a streaming catalog search (see the call site in
  /// [_buildBoard]). Fixed height so the swap from "searching" bar to the
  /// failure note doesn't reflow the rows under DPAD focus.
  Widget _buildSearchStatusStrip() {
    final app = AppThemeScope.of(context);
    return SizedBox(
      height: 16,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _catalogSearching
            ? Center(
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: app.home.chromeAccent,
                  backgroundColor: const Color(0x22FFFFFF),
                ),
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$_catalogSearchFailures source'
                  '${_catalogSearchFailures == 1 ? '' : 's'} didn\'t respond',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.45),
                    fontSize: 11,
                  ),
                ),
              ),
      ),
    );
  }

  /// "Movies" / "Series" (etc.) tag for a catalog row, so two "Popular" rows
  /// (one movies, one series) are distinguishable. Null for unknown types.
  /// The row's provenance tag: which SOURCE fills it. Tracker list rows name
  /// their tracker; catalog rows name the addon. The content TYPE stopped
  /// being the tag when it moved into the heading itself ("Popular Movies" —
  /// see [CatalogSection.rowTitle]); the addon moved the other way, out of
  /// the heading it used to shout open ("Cinemeta: Popular") and into the
  /// quiet pill this feeds.
  String _sectionTag(CatalogSection section) {
    if (section is HomeCollectionSection) return 'Collection';
    if (section is HomeListSection) {
      return section.isTrakt
          ? 'Trakt'
          : section.isMdblist
          ? 'MDBList'
          : 'Simkl';
    }
    return section.addon.name;
  }

  /// Applies the Home presentation preference only to catalog/source
  /// provenance. Continue Watching type tags bypass this helper and remain
  /// visible so identically titled Movies/Series rows stay distinguishable.
  String? _catalogSourceTag(CatalogSection section) =>
      _hideHomeCatalogAddonNames ? null : _sectionTag(section);

  /// Poster walls reached by expanding a Home row share Discover's card-detail
  /// controls. Search stays independent: its standalone result walls retain
  /// their normal labels and badges.
  Widget _withHomeExpandedCardSettings(Widget child) {
    if (widget.searchMode || widget.discoverMode) return child;
    return DiscoverCardSettingsScope(
      showTypeTags: DiscoverPrefs.showTypeTags,
      showRatings: DiscoverPrefs.showRatings,
      showTitles: DiscoverPrefs.showTitles,
      child: child,
    );
  }

  /// Open the full-screen Stremio-styled catalog browser for a rail. Seeds the
  /// grid with the rail's already-loaded items + paging cursor so it continues
  /// where the rail left off; item taps route back through [_openItem] so the
  /// existing detail flow (Trakt actions, recommendations) is reused unchanged.
  void _openCatalogSeeAll(CatalogSection section) {
    // Tracker list rows browse in their OWN See-All (list dropdowns, list
    // semantics) — the catalog browser would try to page them through a
    // placeholder addon that can't serve a catalog endpoint.
    if (section is HomeListSection) {
      _openListRowSeeAll(section);
      return;
    }
    if (section is HomeCollectionSection) {
      _openCollectionScreen(section.collection, 0);
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _withHomeExpandedCardSettings(
              CatalogSeeAllScreen(
                addon: section.addon,
                initialCatalog: section.catalog,
                seedItems: List<StremioMeta>.of(section.items),
                seedNextSkip: section.nextSkip,
                // Search sections carry their query → See All keeps searching
                // this catalog (paged) instead of browsing it.
                query: section.query,
                isTelevision: widget.isTelevision,
                onOpenItem: (item) => _openItem(item, section.addon),
                onQuickPlay: _pikpakOnly
                    ? null
                    : (item) => _onCatalogPlay(item, section.addon),
                // Bound-source badges are intentionally omitted here: _isBound only
                // tracks rail/CW items (not See-All paged items) and wouldn't
                // reactively update in a pushed screen, so a badge would be a false
                // negative more often than not. Revisit with a per-item lookup.
              ),
            ),
          ),
        )
        .then((_) => _afterSeeAllReturn());
  }

  /// "See All" for a Trakt/Simkl list row: the tracker's own See-All screen,
  /// opened directly on the row's list (`initialList`). CW items/progress are
  /// passed exactly as the Discover wiring does, so switching the List
  /// dropdown to Continue Watching inside the screen keeps resume semantics
  /// (the Simkl screen needs its SEPARATE CW handlers for that — without
  /// them, CW items would open/play plainly).
  void _openListRowSeeAll(HomeListSection section) {
    final Widget screen;
    if (section.isTrakt) {
      screen = TraktSeeAllScreen(
        initialList: section.traktChoice,
        cwItems: List<StremioMeta>.of(_traktAll),
        cwProgress: _cwCardMaps(_CwKind.trakt).progress,
        onOpen: _openTraktItem,
        onQuickPlay: _pikpakOnly ? null : _playTraktItem,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
      );
    } else if (section.isMdblist) {
      screen = MdblistSeeAllScreen(
        initialList: section.mdblistList,
        initialListIsPublic: section.rowId.startsWith(
          HomeExtraRowIds.mdblistTopPrefix,
        ),
        onOpen: (item) => _openItem(
          item,
          _addonForContinue(item.sourceAddon?.id),
          isMdblistSource: true,
        ),
        onQuickPlay: _pikpakOnly
            ? null
            : (item) => _onCatalogPlay(
                item,
                _addonForContinue(item.sourceAddon?.id),
                isMdblistSource: true,
              ),
        isBound: _isBound,
        isTelevision: widget.isTelevision,
      );
    } else {
      screen = SimklSeeAllScreen(
        initialList: section.simklList,
        cwItems: List<StremioMeta>.of(_simklAll),
        cwProgress: _simklProgress,
        onOpen: _openSimklItem,
        onQuickPlay: _pikpakOnly ? null : _playSimklItem,
        cwOnOpen: _openSimklCwItem,
        cwOnQuickPlay: _pikpakOnly ? null : _playSimklCwItem,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
      );
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _withHomeExpandedCardSettings(screen),
          ),
        )
        // trackers:true — this grid renders the tracker's own lists, and a
        // played title must reflect on return (same as _openTraktSeeAll).
        .then((_) => _refreshAfterPlayback(trackers: true));
  }

  /// A real content player launched — see [_playedSinceRefresh].
  void _markPlaybackStarted() => _playedSinceRefresh = true;

  /// Re-read everything a finished playback (or a detail/See-All visit) can
  /// change: local Continue Watching, then — when something actually played —
  /// the Trakt and Simkl rows, then the bound-source badges.
  ///
  /// The tracker rows matter because they're SEPARATE rows ([_cwRows]):
  /// reloading only the local list left a tracker user staring at the episode
  /// they'd just finished. They're gated on [_playedSinceRefresh] (or an
  /// explicit [trackers]) so plain browsing doesn't hit two APIs per Back press.
  ///
  /// Bound sources go LAST: _refreshBoundSources scans the CW lists the loaders
  /// replace, so running them concurrently would count the pre-reload set.
  ///
  /// Fire-and-forget from route callbacks and the playback-return listener, so
  /// a transient storage/network error must not become an unhandled async
  /// exception (a stale row is recoverable; a crash-log isn't warranted).
  Future<void> _refreshAfterPlayback({bool trackers = false}) async {
    _seriesResumeCache.clear();
    // Consume the latch up front: a second refresh racing this one must not
    // repeat the tracker fetches this one is already doing.
    final withTrackers = trackers || _playedSinceRefresh;
    _playedSinceRefresh = false;
    try {
      await _loadMyWatchlist();
      if (!mounted) return;
      await _loadContinueWatching();
      if (!mounted) return;
      await _loadIptvContinueWatching();
      if (!mounted) return;
      // The dedicated Search tab never renders the tracker rows (mirrors the
      // guard in _onIntegrationsChanged) — don't spend the calls there.
      if (withTrackers && !widget.searchMode) {
        await Future.wait([
          _loadTraktContinueWatching(refreshBound: false),
          _loadSimklContinueWatching(refreshBound: false),
          // A scrobble revision already queued (pending) or just completed
          // (force-fresh) the authoritative MDBList reload; loading here too
          // would only repeat it or fetch pre-propagation data it replaces.
          // When no scrobble fired (e.g. external playback), load as before.
          if (!_mdblistRevisionRefreshPending && !_mdblistCwForceFresh)
            _loadMdblistContinueWatching(refreshBound: false, force: true),
        ]);
        if (!mounted) return;
      }
      await _refreshBoundSources();
    } catch (e) {
      debugPrint('SearchScreen: post-playback refresh failed: $e');
    }
  }

  /// Playback ran in a separate ACTIVITY and the app just came back (see
  /// [MainPageBridge.notifyPlaybackReturned]). Only refresh when the board is
  /// the top route: with a detail page or See-All open on top, THAT screen owns
  /// the refresh and the board re-reads through the covering route's `.then`
  /// when it pops — so this can't double up with it. The latch survives until
  /// then, so the deferred refresh still knows playback happened.
  void _onPlaybackReturned() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    unawaited(_refreshAfterPlayback());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !mounted ||
        widget.searchMode ||
        !_isTraktAuthenticated ||
        _playedSinceRefresh ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    final lastAttempt = _lastTraktCwRefreshAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) <
            _traktCwResumeRefreshInterval) {
      return;
    }
    unawaited(_loadTraktContinueWatching());
  }

  /// Refresh state that a See-All screen may have changed (Continue Watching
  /// progress/removal, bound sources) when it pops back to the board — plus the
  /// tracker rows when the user played something from the grid.
  Future<void> _afterSeeAllReturn() => _refreshAfterPlayback();

  /// Shared push for the Continue Watching "See All" grid (local + Trakt). The
  /// two sources differ only in title/items/callbacks/onReload and what to
  /// refresh on return.
  void _pushCwSeeAll({
    required String title,
    required String initialCategory,
    required List<StremioMeta> items,
    required double? Function(StremioMeta) progressOf,
    required void Function(StremioMeta) onOpen,
    required void Function(StremioMeta)? onQuickPlay,
    required Future<List<StremioMeta>> Function()? onReload,
    VoidCallback? onReturn,
  }) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _withHomeExpandedCardSettings(
              ContinueWatchingSeeAllScreen(
                title: title,
                initialCategory: initialCategory,
                items: List<StremioMeta>.of(items),
                progressOf: progressOf,
                onOpen: onOpen,
                onQuickPlay: onQuickPlay,
                onReload: onReload,
                // CW items are all rail-loaded, so _boundCounts covers them.
                isBound: _isBound,
                isTelevision: widget.isTelevision,
              ),
            ),
          ),
        )
        .then((_) => onReturn?.call());
  }

  /// Local Continue Watching "See All", pre-filtered to [initialCategory]
  /// ('movie' / 'series') of the row the user came from. Re-fetches (via
  /// onReload) whenever a detail/player route pops back onto it, so finished
  /// titles drop out and progress stays fresh.
  void _openContinueWatchingSeeAll([String initialCategory = 'all']) {
    _pushCwSeeAll(
      title: 'Continue Watching',
      initialCategory: initialCategory,
      items: _cwAll,
      progressOf: (m) => _cwCardProgress(_CwKind.local, m),
      onOpen: _openContinueItem,
      onQuickPlay: _pikpakOnly ? null : _onContinuePlay,
      // Reload CW + refresh bound sources (sequenced), then hand the grid the
      // fresh list. This runs on every detail/player return AND keeps the board
      // beneath fresh, so no separate onReturn is needed (it would double the
      // reload when a detail-close is immediately followed by a board-return).
      onReload: () async {
        await _afterSeeAllReturn();
        return List<StremioMeta>.of(_cwAll);
      },
    );
  }

  /// Trakt "See All". Opens on Continue Watching (the row the user came from,
  /// handed in already-loaded) and lets them switch to any standard Trakt list
  /// — Watchlist, History, Collection, Ratings, Recommendations, Trending,
  /// Popular, Anticipated — from the in-screen "List" dropdown; those are
  /// fetched on demand inside [TraktSeeAllScreen].
  ///
  /// The Continue Watching grid keeps its snapshot (no per-return reload).
  /// The board's rows refresh once when the screen pops — `trackers: true`
  /// because that's true whether or not anything was played here. One pass
  /// reloads local CW + both trackers and then runs
  /// the single bound-source refresh against the now-fresh lists (it swallows
  /// its own errors, so the bound refresh still happens if a fetch fails).
  void _openTraktSeeAll([String initialCategory = 'all']) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _withHomeExpandedCardSettings(
              TraktSeeAllScreen(
                initialCategory: initialCategory,
                cwItems: List<StremioMeta>.of(_traktAll),
                // Pass the live progress map (read-only in the screen) so resume
                // bars reflect any refresh while the screen is open, matching the
                // old live-closure behaviour; items stay a snapshot so the grid
                // doesn't shift under the user.
                cwProgress: _cwCardMaps(_CwKind.trakt).progress,
                onOpen: _openTraktItem,
                onQuickPlay: _pikpakOnly ? null : _playTraktItem,
                // CW items are all rail-loaded, so _boundCounts covers them.
                isBound: _isBound,
                isTelevision: widget.isTelevision,
              ),
            ),
          ),
        )
        .then((_) => _refreshAfterPlayback(trackers: true));
  }

  /// Shared header for a board rail: a "Popular Movies"-style title (the
  /// content type lives in the words — [CatalogSection.rowTitle]) with the
  /// source riding beside it as a small [RowTagPill]. The "See All" link is a
  /// mouse/tap affordance shown on desktop only — TV keeps the rail
  /// chrome-free and paginates as the user scrolls.
  Widget _railHeader({
    required String title,
    String? tag,
    VoidCallback? onSeeAll,
  }) {
    final app = AppThemeScope.of(context);
    final tv = widget.isTelevision;
    final compact = !tv && MediaQuery.sizeOf(context).width < 480;
    return Padding(
      // Tighter vertically on TV so the current row's header + a peek of the
      // next row fit under the hero on short-canvas panels.
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        tv ? 14 : 22,
        compact ? 16 : 24,
        tv ? 10 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            // One shape for every tier now: title + provenance pill. The tag
            // used to render as a second line (compact) / a dot-suffix (wide)
            // back when it was the content type; as the ADDON it reads as
            // provenance, and the pill keeps it a footnote on all three tiers
            // (the same chip the Spotlight board's headings wear).
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Poppins for the rail titles too, so headings share one
                    // display face. TV runs them quieter (15px) — the hero
                    // carries the weight, the row title just labels the shelf
                    // (Nuvio's row grammar).
                    style: GoogleFonts.poppins(
                      fontSize: tv || compact ? 15 : 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: app.fade(app.core.tx, 0.92),
                    ),
                  ),
                ),
                if (tag != null) ...[
                  const SizedBox(width: 8),
                  // Intrinsic width under a hard cap — a second Flexible here
                  // would halve the title's max width and wrap it (the
                  // Spotlight heading hit exactly that).
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: RowTagPill(tag, fontSize: 9.5),
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null && !tv)
            _SeeAllLink(onTap: onSeeAll, compact: compact),
        ],
      ),
    );
  }

  Widget _buildRow(int rowIndex, {String? homeRowId}) {
    final section = _sections[rowIndex];
    final nodes = _rowNodes[rowIndex];
    final tv = widget.isTelevision;
    // Bigger, roomier posters on desktop (Stremio-scale); smaller on phones.
    // Titleless cells (Stremio-style) — just the art box + a little headroom
    // for the hover/focus lift. The box follows the Home Cards orientation.
    // Collection rows draw their folders' own tile shape (a brand tile stays
    // wide even when Home cards are portrait) at the same height as every
    // other rail, so the row grammar stays intact.
    final collection = section is HomeCollectionSection ? section : null;
    final cellH = _railTitleCardH(context);
    final cellAspect = collection?.tileAspectRatio ?? _titleCardAspect;
    final posterW = collection == null
        ? _railTitleCardW(context)
        : cellH * cellAspect;
    final rowH = cellH + 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader(
          title: section.title,
          tag: _catalogSourceTag(section),
          onSeeAll: () => _openCatalogSeeAll(section),
        ),
        SizedBox(
          height: rowH,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Pull the next page as the row nears its right edge. Only this
              // row's horizontal scroll reaches here (the vertical board list is
              // an ancestor, so its notifications don't bubble down).
              if (n.metrics.axis == Axis.horizontal &&
                  n.metrics.pixels >=
                      n.metrics.maxScrollExtent - _kRowLoadMoreThreshold) {
                _loadMoreRow(rowIndex);
              }
              return false;
            },
            child: Builder(
              builder: (context) {
                // Rows start straight on the first poster (Stremio-style, no
                // leading See-All tile). DPAD-up from row 0 leaves the board;
                // col-0 DPAD-left drops to the sidebar (handled in _BoardCell
                // when onLeftEdge is null).
                VoidCallback up(int col) => homeRowId != null
                    ? () => _focusRelativeHomeRail(homeRowId, -1, col)
                    : rowIndex == 0
                    ? (_anyFavVisible
                          ? () => _focusFavRowAt(_favRowCount - 1, col)
                          : (_cwVisible
                                ? () => _focusCwRow(_cwRows.length - 1, col)
                                : () => _leaveBoardTop()))
                    : () => _focusRow(rowIndex - 1, col);
                // Down past the last loaded row kicks the next batch load
                // (inside _focusRow) and defers the move until it lands.
                VoidCallback down(int col) => homeRowId != null
                    ? () => _focusRelativeHomeRail(homeRowId, 1, col)
                    : () {
                        if (!_focusRow(rowIndex + 1, col)) {
                          _deferDownMove(rowIndex: rowIndex, column: col);
                        }
                      };
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  // Clip the horizontal viewport so scrolled-off cards don't paint
                  // over the sidebar to the left. rowH has enough headroom that the
                  // hover/focus lift still isn't clipped.
                  clipBehavior: Clip.hardEdge,
                  // ~4 posters of pre-build either side (was 800 ≈ a dozen —
                  // amplified every row mounted by the vertical cache).
                  cacheExtent: 400,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  // +1 trailing paging spinner.
                  itemCount:
                      section.items.length + (section.loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    final col = index;
                    if (col >= section.items.length) {
                      return SizedBox(
                        width: 52,
                        height: cellH,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final item = section.items[col];
                    // Unique per cell AND per SearchScreen instance (Home,
                    // Discover and Search coexist in the tab stack — a shared
                    // tag across them would trip Hero's duplicate-tag assert).
                    final heroTag =
                        'poster-${identityHashCode(this)}-$rowIndex-$col';
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      child: Center(
                        child: SizedBox(
                          width: posterW,
                          height: cellH,
                          child: _BoardCell(
                            item: item,
                            isTelevision: tv,
                            focusNode: nodes[col],
                            column: col,
                            rowNodes: nodes,
                            hasBoundSource: _isBound(item),
                            aspectRatio: cellAspect,
                            artUrl: collection != null
                                ? item.poster
                                : _titleArtUrl(item),
                            focusArtUrl: collection?.focusArtOf(item),
                            showTitleOverlay: collection != null
                                ? !(collection.folderOf(item)?.hideTitle ??
                                      false)
                                : !_hideHomeCardTitlesAndRatings,
                            onQuickPlay: _pikpakOnly || collection != null
                                ? null
                                : () => _sectionQuickPlay(section, item),
                            onFocused: () {
                              _setHero(item);
                              _rowCol[rowIndex] = col;
                            },
                            onUp: up(col),
                            onDown: down(col),
                            onOpen: () => _sectionOpenItem(
                              section,
                              item,
                              heroTag: heroTag,
                            ),
                            onNearEnd: () => _loadMoreRow(rowIndex),
                            heroTag: heroTag,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Bottom-of-board loading indicator shown while more catalog rows stream in.
  Widget _buildBoardFooter() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// A leading Continue Watching row (local or Trakt) — same poster cards as the
  /// catalog rows, plus a bottom progress bar and an optional type tag. Vertical
  /// navigation resolves [homeRowId] against the live global order.
  Widget _buildContinueWatchingRow(_CwRow row, int cwIndex, String homeRowId) {
    final tv = widget.isTelevision;
    final posterW = _railTitleCardW(context);
    final cellH = _railTitleCardH(context);
    final rowH = cellH + 14;
    final items = row.items;
    final nodes = row.nodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader(title: row.title, tag: row.tag, onSeeAll: row.onSeeAll),
        SizedBox(
          height: rowH,
          child: Builder(
            builder: (context) {
              // Rows start on the first poster (no leading See-All tile). DPAD-up
              // from the first CW row leaves the board; col-0 DPAD-left drops to
              // the sidebar (handled in _BoardCell when onLeftEdge is null).
              VoidCallback up(int col) =>
                  () => _focusRelativeHomeRail(homeRowId, -1, col);
              VoidCallback down(int col) =>
                  () => _focusRelativeHomeRail(homeRowId, 1, col);
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                cacheExtent: 400,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final col = index;
                  final item = items[col];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    child: Center(
                      child: SizedBox(
                        width: posterW,
                        height: cellH,
                        child: _BoardCell(
                          item: item,
                          isTelevision: tv,
                          focusNode: nodes[col],
                          column: col,
                          rowNodes: nodes,
                          hasBoundSource: _isBound(item),
                          // A Continue Watching progress bar describes the
                          // active viewing session. A global "watched once"
                          // check from another tracker reads as contradictory
                          // here, especially during a rewatch.
                          showWatchedBadge: false,
                          aspectRatio: _titleCardAspect,
                          artUrl: _titleArtUrl(item),
                          showTitleOverlay: !_hideHomeCardTitlesAndRatings,
                          progress: row.progressOf(item),
                          episodeLabel: row.episodeOf(item),
                          // Long-press / hold-OK opens the Play + Remove menu
                          // rather than playing outright — a Continue Watching
                          // card is the one place removal has to be reachable.
                          onLongPress: () =>
                              _openCwCardMenu(row, item, cwIndex, col),
                          onFocused: () => _setHero(item),
                          onUp: up(col),
                          onDown: down(col),
                          onOpen: () => row.onOpen(item),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// A skeleton Trakt Continue Watching row shown while the account's fetch is
  /// still in flight (see [_traktReserving]). Sized identically to a real CW row
  /// — same header, poster width and cell height — so when the data arrives and
  /// replaces it there's zero layout shift. Purely decorative: no focus nodes,
  /// so the DPAD skips over it entirely. [idx] is 0 (Movies) or 1 (Shows).
  Widget _buildTraktSkeletonRow(int idx) {
    final posterW = _railTitleCardW(context);
    final cellH = _railTitleCardH(context);
    final rowH = cellH + 14;
    return _TraktSkeletonRow(
      header: _railHeader(
        title: 'Trakt Continue Watching',
        tag: idx == 0 ? (_cwMergeTrakt ? null : 'Movies') : 'Shows',
      ),
      posterW: posterW,
      cellH: cellH,
      rowH: rowH,
    );
  }

  /// Dispatch to the right favourites-row builder for [ref].
  Widget _buildFavRow(_FavRowRef ref, String homeRowId) {
    if (ref.isIptvList) {
      return _buildIptvListRow(ref, homeRowId);
    }
    switch (ref.kind) {
      case _FavKind.watchlistMovies:
      case _FavKind.watchlistSeries:
        return _buildWatchlistRow(ref, homeRowId);
      case _FavKind.iptv:
        return _buildIptvFavRow(homeRowId);
      case _FavKind.debrify:
        return _buildTvFavRow(homeRowId);
      case _FavKind.stremio:
        return _buildStremioTvFavRow(homeRowId);
      case _FavKind.playlist:
        return _buildPlaylistFavRow(homeRowId);
    }
  }

  Widget _buildWatchlistRow(_FavRowRef ref, String homeRowId) {
    final tv = widget.isTelevision;
    final isMovies = ref.kind == _FavKind.watchlistMovies;
    final items = isMovies ? _watchlistMovieItems : _watchlistSeriesItems;
    final nodes = isMovies ? _watchlistMovieNodes : _watchlistSeriesNodes;
    return _buildFavRowShell(
      title: isMovies ? 'Watchlist Movies' : 'Watchlist Series',
      tags: [
        _CategoryTag(
          isMovies ? 'Movies' : 'Series',
          icon: Icons.bookmark_rounded,
        ),
      ],
      itemCount: items.length,
      cellBuilder: (col, posterW, cellH) {
        final item = items[col];
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: nodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: _ArtPoster(
            imageUrl: item.poster,
            title: item.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            isTelevision: tv,
            focusNode: nodes[col],
            onOpen: () => _openMyWatchlistItem(item),
            onFocused: _clearHeroLiveIptv,
          ),
        );
      },
    );
  }

  /// Shared scaffold for a favourites row: a header (title + tag pills) above a
  /// horizontal strip of poster-shaped cards, sized exactly like the catalog
  /// rows so the whole board reads as one grid. [cellBuilder] gets the poster
  /// width and full cell height (poster + title band) for each column.
  Widget _buildFavRowShell({
    required String title,
    required List<Widget> tags,
    required int itemCount,
    required Widget Function(int col, double posterW, double cellH) cellBuilder,
  }) {
    final tv = widget.isTelevision;
    final posterW = _railPosterW(context);
    final posterH = posterW * 3 / 2;
    // Reserve the inline caption band so a long title — e.g. a full release-name
    // playlist item — doesn't overflow the cell into the next section's header.
    final cellH = posterH + _homeArtPosterCaptionBand;
    final rowH = cellH + 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tv ? 20 : 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              for (final t in tags) ...[const SizedBox(width: 6), t],
            ],
          ),
        ),
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            cacheExtent: 400,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: itemCount,
            itemBuilder: (context, col) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: SizedBox(
                    width: posterW,
                    height: cellH,
                    child: cellBuilder(col, posterW, cellH),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The "Debrify TV" row of favourited keyword channels, styled to match the
  /// catalog rows (same poster-shaped cards + title below).
  Widget _buildTvFavRow(String homeRowId) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Debrify TV',
      tags: const [
        _CategoryTag('Channels'),
        // Make it explicit this row is the user's STARRED channels, not every
        // channel — otherwise people expect all channels here.
        _CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _tvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _tvFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          // Debrify channels have no artwork — the glyph fallback + channel
          // number badge is the intended look.
          child: _ArtPoster(
            imageUrl: null,
            title: channel.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            badge: '$number',
            isTelevision: tv,
            focusNode: _tvFavNodes[col],
            onOpen: () => _playChannel(channel),
            onFocused: _clearHeroLiveIptv,
          ),
        );
      },
    );
  }

  /// The "Stremio TV" row of favourited channels. Each card shows the channel's
  /// current now-playing item poster (rotating on the same schedule as the Home
  /// / Stremio TV screens); tapping opens the channel.
  Widget _buildStremioTvFavRow(String homeRowId) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Stremio TV',
      tags: const [
        _CategoryTag('Channels'),
        _CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _stvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _stvFavChannels[col];
        final item = _stvNowPlaying(channel)?.item;
        // Prefer the 2:3 poster for this poster-shaped tile; fall back to the
        // (landscape) background so channels whose now-playing meta lacks a
        // poster still show art instead of a blank glyph.
        final art = _firstNonEmpty(item?.poster, item?.background);
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _stvFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: _ArtPoster(
            imageUrl: art,
            title: channel.displayName,
            showTitle: !_hideHomeCardTitlesAndRatings,
            live: true,
            isTelevision: tv,
            focusNode: _stvFavNodes[col],
            onOpen: () => _playStremioTvChannel(channel),
            onFocused: _clearHeroLiveIptv,
          ),
        );
      },
    );
  }

  /// The "IPTV" row of favourited live channels. Cards show the channel logo
  /// (glyph fallback); tapping plays the stream directly.
  Widget _buildIptvFavRow(String homeRowId) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'IPTV',
      tags: const [
        _CategoryTag('Live'),
        _CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _iptvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _iptvFavChannels[col];
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _iptvFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: _ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            // Logos are usually square/wide, not 2:3 — contain so they aren't
            // cropped; the gradient shows around them.
            imageFit: BoxFit.contain,
            isTelevision: tv,
            focusNode: _iptvFavNodes[col],
            onOpen: () => _playIptvChannel(channel),
            // DPAD focus retunes the Home hero's boxed video region to this
            // channel's live stream — same HeroTrailerBackdrop(live: true)
            // mechanism the IPTV page's own inline preview uses.
            onFocused: () => _setHeroLiveIptv(channel),
          ),
        );
      },
    );
  }

  /// An opted-in IPTV custom list as a Home row. Same cell stack as the IPTV
  /// favourites row, but content-aware: play routes by the stored content
  /// type (lists can hold VOD/series alongside live), and only a live entry
  /// retunes the hero's live preview on focus.
  Widget _buildIptvListRow(_FavRowRef ref, String homeRowId) {
    final tv = widget.isTelevision;
    final row = _iptvListRows[ref.list];
    return _buildFavRowShell(
      title: row.title,
      tags: const [
        _CategoryTag('IPTV'),
        _CategoryTag('List', icon: Icons.playlist_play_rounded),
      ],
      itemCount: row.channels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = row.channels[col];
        final live = channel.isLive;
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: row.nodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: _ArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            // Logos are usually square/wide, not 2:3 — contain so they aren't
            // cropped; the gradient shows around them.
            imageFit: BoxFit.contain,
            isTelevision: tv,
            focusNode: row.nodes[col],
            onOpen: () => _playIptvListChannel(channel),
            onFocused: live
                ? () => _setHeroLiveIptv(channel)
                : _clearHeroLiveIptv,
          ),
        );
      },
    );
  }

  /// The "Playlist" row of the user's saved items. Cards show the item poster
  /// with a resume-progress bar; tapping opens the full action menu
  /// ([_onPlaylistItemTap]) — this row is a complete playlist manager on its own.
  Widget _buildPlaylistFavRow(String homeRowId) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Playlist',
      tags: const [_CategoryTag('Saved')],
      itemCount: _playlistItems.length,
      cellBuilder: (col, posterW, cellH) {
        final item = _playlistItems[col];
        final posterUrl = item['posterUrl'] as String?;
        final title = (item['title'] as String?) ?? 'Unknown';
        return _FavArtCell(
          isTelevision: tv,
          column: col,
          rowNodes: _playlistFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: _ArtPoster(
            imageUrl: posterUrl,
            title: title,
            showTitle: !_hideHomeCardTitlesAndRatings,
            progress: _playlistProgressFor(item),
            isTelevision: tv,
            focusNode: _playlistFavNodes[col],
            onOpen: () => _onPlaylistItemTap(item),
            onFocused: _clearHeroLiveIptv,
          ),
        );
      },
    );
  }

  Widget _message(
    IconData icon,
    String title,
    String body, {
    VoidCallback? onRetry,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                autofocus: widget.isTelevision,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
