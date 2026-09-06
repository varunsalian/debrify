import 'search/favourite_art_cell.dart';
import 'search/stages/stage_favourite_cells.dart';
import 'search/board_cell.dart';
import 'search/stage_visuals.dart';
import 'search/stages/deck_board_stage.dart';
import 'search/stages/atrium_board_stage.dart';
import 'search/stages/mosaic_board_stage.dart';
import 'search/stages/promenade_board_stage.dart';
import 'search/stages/canvas_board_stage.dart';
import 'search/stages/tonight_board_stage.dart';
import 'search/stages/tonight_stage_content.dart';
import 'search/stages/stage_shelf_content.dart';
import 'search/stages/tonight_stage_widgets.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme_scope.dart';
import '../utils/home_rail_metrics.dart';
import '../utils/platform_util.dart';
import '../models/home_collection.dart';
import '../models/iptv_playlist.dart';
import '../models/stremio_addon.dart';
import '../models/stremio_tv/stremio_tv_channel.dart';
import '../services/analytics_service.dart';
import '../services/discover_prefs.dart';
import '../services/home_collection_rows.dart';
import '../services/home_collections_store.dart';
import '../services/home_list_rows.dart';
import '../services/home/home_row_family.dart';
import '../services/home/home_row_registry.dart';
import 'search/home_board_controller.dart';
import 'search/search_board_runtime.dart';
import 'search/search_content_session.dart';
import 'search/catalog_search_controller.dart';
import 'search/title_opener.dart';
import 'search/search_screen_shells.dart';
import 'search/catalog_search_screen.dart';
import 'search/discover_screen.dart';
import 'search/keyword_search_screen.dart';
import 'search/keyword_search_controller.dart';
import 'search/continue_watching_controller.dart';
import 'search/continue_watching_row.dart';
import 'search/fav_rows_controller.dart';
import 'search/fav_row_ref.dart';
import 'search/stages/spotlight_board_stage.dart';
import 'search/stages/spotlight_stage_content.dart';
import 'search/fav_row.dart';
import 'search/hero_presenter.dart';
import 'search/discover_lifecycle.dart';
import 'search/trailer_status_chips.dart';
import 'search/hero_spotlight.dart';
import '../services/filtered_catalog_pager.dart';
import '../services/hide_watched_prefs.dart';
import '../services/watched_status_service.dart';
import '../services/iptv_cw_router.dart';
import '../services/iptv_media_store.dart';
import '../services/main_page_bridge.dart';
import '../models/profiles/profile_policy.dart';
import '../services/profiles/profile_policy_guard.dart';
import '../services/profiles/profile_session_memory.dart';
import '../services/stremio_iptv_service.dart';
import '../services/stremio_service.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import '../services/storage_service.dart';
import '../services/tv_hero_artwork_quality_controller.dart';
import '../services/tvos_top_shelf_service.dart';
import '../services/torrent_bulk_add_service.dart';
import '../services/torrent_playback_service.dart';
import '../services/playback/catalog_play_resolver.dart';
import '../utils/tv_keys.dart';
import '../utils/tv_search_focus_handoff.dart';
import '../services/app_route_observer.dart';
import '../services/youtube_service.dart';
import '../widgets/sources/source_binding_dialogs.dart';
import '../widgets/hero_trailer_backdrop.dart';
import '../widgets/home/card_focus_rise.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/home/row_tag_pill.dart';
import '../widgets/home/spotlight_board.dart';
import '../widgets/skeleton_poster.dart';
import '../widgets/tv_text_field.dart';
import 'collections/collection_folder_screen.dart';
import 'see_all/catalog_see_all_screen.dart';
import 'see_all/trakt_see_all_screen.dart';
import 'see_all/simkl_see_all_screen.dart';
import 'see_all/mdblist_see_all_screen.dart';
import 'see_all/mdblist_lists_see_all_screen.dart';
import '../widgets/see_all/mdblist_list_card.dart';
import '../services/mdblist/mdblist_list_source.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/mdblist/mdblist_models.dart';
import '../widgets/see_all/stremio_dropdown.dart';
import '../widgets/see_all/discover_card_settings_scope.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import 'settings/tv_home_style_page.dart'
    show effectiveOffTvHomeStyle, shouldUseOffTvSpotlightShell;

export 'search/fav_row_ref.dart' show FavKind, FavRowRef;
export 'search/favourite_art_cell.dart' show ArtPoster, FavArtCell;

import 'search/search_sources.dart' show CatalogSourcesDialog, KeywordSourcesDialog;
export 'search/search_sources.dart' show buildSearchSources;
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
const Color _kCwProgressRed = boardCwProgressRed;

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch as
/// the user scrolls, and how many items to keep per row. Enumerating catalogs is
/// free (manifest metadata) — only fetching each row's items costs a call — so we
/// list every catalog up front and lazily pull batches on scroll (Stremio-style)
/// instead of a hard global row cap.
/// Batch size lives on [HomeBoardController] (`kHomeBoardBatchSize`).

/// When a row's horizontal scroll gets within this many pixels of the end, the
/// next page for that catalog is fetched (Stremio-style unlimited rows).
const double _kRowLoadMoreThreshold = 900;

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
///
/// Public constructors stay on this type so `main.dart` is unchanged (G4-style
/// wrapper). Search/Discover delegate to [CatalogSearchScreen] /
/// [DiscoverScreen]; Home stays [SearchScreenHost] in this file.
class SearchScreen extends StatelessWidget {
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

  /// Same `?:` order as the old State flags — [searchMode] wins if both are true.
  static Widget forFlags({
    bool isTelevision = false,
    bool searchMode = false,
    bool discoverMode = false,
  }) {
    if (searchMode) {
      return CatalogSearchScreen(
        isTelevision: isTelevision,
        host: SearchScreenHost(isTelevision: isTelevision, searchMode: true),
      );
    }
    if (discoverMode) {
      return DiscoverScreen(
        isTelevision: isTelevision,
      );
    }
    return SearchScreenHost(isTelevision: isTelevision);
  }

  @override
  Widget build(BuildContext context) => forFlags(
        isTelevision: isTelevision,
        searchMode: searchMode,
        discoverMode: discoverMode,
      );
}

/// Shared host for Home / Search / Discover. Constructs [HomeBoardController],
/// [CatalogSearchController], and [TitleOpener] for every variant (Search
/// still builds the board controller; Discover still builds catalog search).
class SearchScreenHost extends StatefulWidget {
  final bool isTelevision;
  final bool searchMode;
  final bool discoverMode;

  /// Merge-preference IO captured by this host's Continue Watching session.
  final Future<bool> Function(String provider) readCwMergedRows;

  const SearchScreenHost({
    super.key,
    this.isTelevision = false,
    this.searchMode = false,
    this.discoverMode = false,
    this.readCwMergedRows = HomePrefs.getHomeCwMergedRows,
  });

  @override
  // Preserve Home State identity while dispatching Discover before initialization.
  // ignore: no_logic_in_create_state
  State<SearchScreenHost> createState() => discoverMode && !searchMode
      ? _DiscoverCompatibilityState() : _SearchScreenState();
}

/// Direct legacy constructors dispatch before the old content State exists.
/// Home/Search retains its StatefulWidget compatibility surface.
class _DiscoverCompatibilityState extends State<SearchScreenHost> {
  @override
  Widget build(BuildContext context) => DiscoverScreen(
    isTelevision: widget.isTelevision,
    readCwMergedRows: widget.readCwMergedRows,
  );
}

enum SearchBoardMode { catalog, keyword, lists }

/// Fixed Discover sources; installed addons are appended dynamically (key
/// 'a:{addonId}'). Aliases of [kDiscoverSourceCw] etc. so call sites stay put.

/// Whether an asynchronously loaded Discover landing source may still update
/// the screen. Public only so the lifecycle contract has a focused regression
/// test; production callers are confined to this file.
bool discoverLandingLoadIsCurrent({
  required int capturedRevision,
  required int currentRevision,
  required bool hasPendingHandoff,
}) => !hasPendingHandoff && capturedRevision == currentRevision;

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





/// Smallest poster art a stage rail will draw before it is simply too small
/// to recognise — the floor every derived rail box respects.
const double _kStageMinPosterH = 56;













// ATRIUM metrics. The wall's height is DERIVED from these (never guessed),
// so the dossier column beside it can't be crowded by a taller row.
const double _kAtriumLabelFontSize = 12.0;
const double _kAtriumLabelGap = atriumLabelGap;


double _atriumLabelHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(_kAtriumLabelFontSize) * 1.35;

// Metrics for the PROMENADE bottom column (centred rail label + strip). Same
// single-source-of-truth contract as the Canvas block above: the widgets and
// the identity block that must stay clear of them read the same numbers.
const double _kPromLabelFontSize = 12.0;




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

class _SearchScreenState extends State<SearchScreenHost>
    with RouteAware, WidgetsBindingObserver
    implements SearchContentSurface, SearchContentPresentation {
  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get _tabIndex => searchScreenTabIndex(
        searchMode: widget.searchMode,
        discoverMode: false,
      );

  final SearchContentSession _content = SearchContentSession();
  @override
  void commit(VoidCallback change) => setState(change);
  @override
  void beforeApplySections() {
    _boardGen++;
    _boardAppliedAt = DateTime.now();
  }
  @override
  void resetStageGeneration() => _stageGeneration++;
  @override
  void publishTopShelfSpotlight() => _publishTopShelfSpotlight();
  @override
  void maybeAutoFocusBoard() => _maybeAutoFocusBoard();
  @override
  void focusContent() => _focusContent();
  @override
  Widget wrapSeeAll(Widget child) => _withHomeExpandedCardSettings(child);

  StremioService get _stremio => _content.stremio;

  TextEditingController get _searchController => _content.searchController;
  FocusNode get _searchFocusNode => _content.searchFocusNode;
  TvSearchFocusHandoff get _searchSubmitFocus => _content.searchSubmitFocus;
  // DPAD focus targets for the Catalog / Keyword / Lists selector, so the
  // toggle is reachable with a remote (arrow-up from the search field).
  final FocusNode _modeCatalogNode = FocusNode(debugLabel: 'mode_catalog');
  final FocusNode _modeKeywordNode = FocusNode(debugLabel: 'mode_keyword');
  final FocusNode _modeListsNode = FocusNode(debugLabel: 'mode_lists');
  final FocusNode _modeDropdownNode = FocusNode(debugLabel: 'mode_dropdown');

  // Dedicated MDBList list-search state. Lists is its own Search mode; it
  // never runs as part of Catalog search. Each result card hands off via
  // MainPageBridge.pendingMdblistListOpen. One focus node per card.
  String get _listsQuery => _content.listsQuery;
  set _listsQuery(String value) => _content.listsQuery = value;
  List<MdblistListChoice> get _listsResults => _content.listsResults;
  set _listsResults(List<MdblistListChoice> value) => _content.listsResults = value;
  bool get _listsSearching => _content.listsSearching;
  set _listsSearching(bool value) => _content.listsSearching = value;
  String? get _listsError => _content.listsError;
  set _listsError(String? value) => _content.listsError = value;
  int get _listsToken => _content.listsToken;
  set _listsToken(int value) => _content.listsToken = value;
  List<FocusNode> get _listsNodes => _content.listsNodes;
  // Debounce for opening a list from the rail — one fast double-press must not
  // stack two pushed item screens (TV) / double-fire the handoff.
  DateTime? _lastListOpenAt;

  SearchBoardMode get _mode => _content.mode;
  set _mode(SearchBoardMode value) => _content.mode = value;

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  String get _catalogQuery => _catalogSearch.query;
  Timer? _catalogDebounce;

  /// The addon that produced the item currently being played/browsed, threaded
  /// into playback so Continue Watching can route resume / next-episode back to
  /// it (matching Home's `addonId`). Set whenever we open a catalog item.

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

  /// Captured at mount, not dispose: an outgoing screen may be torn down after
  /// the next profile is published and must still tag its snapshot as outgoing.
  late final ProfileSessionOwner _profileSessionOwner;

  /// Discriminates the three [SearchScreen] variants so a preserved keyword
  /// search only restores into the same kind of tab it came from.
  String get _variantKey => searchScreenVariantKey(
        searchMode: widget.searchMode,
        discoverMode: false,
      );

  /// True when PikPak is the ONLY configured provider. PikPak can't quick-play
  /// (it queues a cloud download), so catalog "Play" is hidden — matching Home.
  bool get _pikpakOnly => _content.pikpakOnly;

  /// Experimental flag: route series taps to the merged detail+episodes page.
  /// Loaded once on init; movies and the flag-off path keep the existing flow.

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  // Compatibility aliases expire with G17 real-owner migration / Q2.

  // Board state. [_homeSections] is the homepage cache; [_sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  bool get _loading => _content.loading;
  set _loading(bool value) => _content.loading = value;
  String? _error;
  List<CatalogSection> get _homeSections => _board.homeSections;
  set _homeSections(List<CatalogSection> value) => _board.homeSections = value;
  List<CatalogSection> get _sections => _boardRuntime.sections;
  List<List<FocusNode>> get _rowNodes => _boardRuntime.rowNodes;
  // Per-row remembered focus column (leanback-style). DPAD up/down into a row
  // returns to where you left THAT row — the cell it points at is guaranteed
  // mounted, so requestFocus never no-ops on a scrolled-away lazy cell.
  Map<int, int> get _rowCol => _boardRuntime.rowCol;
  // Board entrance: bumped each time the displayed sections are swapped
  // (initial load, search results in/out), so the first rows replay their
  // one-shot fade/rise entrance. Appends don't bump it.
  int _boardGen = 0;
  DateTime _boardAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _catalogSearching => _catalogSearch.searching;
  // Catalogs that errored (timeout / HTTP / network) during the current
  // catalog search — distinct from "returned no results". Drives the quiet
  // "N sources didn't respond" note so failing addons don't just vanish.
  int get _catalogSearchFailures => _catalogSearch.failures;

  /// Home board data layer (batches, row paging, hero source, reload diffing).
  HomeBoardController get _board => _content.board;

  /// Catalog search data layer (query, generation token, per-catalog fetch).
  CatalogSearchController get _catalogSearch => _content.catalogSearch;

  /// Keyword torrent-search data layer (query, streamed batches, freeze/adopt).
  KeywordSearchController get _keyword => _content.keyword;

  /// Tracker + local Continue Watching loaders (G1'-4). Node lists live on
  /// [_cwNodes] (row-widget owned).
  CwFocusOwner get _cwNodes => _content.cwNodes;
  ContinueWatchingController get _cw => _content.cw;

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [_reloadForHomeSettings] when the manager saves.
  Set<String> get _homeDisabled => _board.homeDisabled;
  set _homeDisabled(Set<String> value) => _board.homeDisabled = value;

  // The OPT-IN extra rows (Trakt/Simkl list rows, IPTV custom-list rows) from
  // the same manager — default-off, so they live in their own store
  // (`home_extra_rows_v1`). Tracker ids become [HomeListSection]s at the head
  // of the board in [_load]; `iptvlist:` ids drive the IPTV list favourites
  // rows. Refreshed by [_reloadForHomeSettings].
  List<HomeExtraRow> get _homeExtras => _board.homeExtras;
  set _homeExtras(List<HomeExtraRow> value) => _board.homeExtras = value;

  /// Imported collections — each enabled one is a [HomeCollectionSection] row
  /// of folder tiles. [_homeCollectionsSig] is the store's change token the
  /// settings-changed listener diffs against.
  List<HomeCollection> get _homeCollections => _board.homeCollections;
  set _homeCollections(List<HomeCollection> value) =>
      _board.homeCollections = value;
  /// The hide-watched switch as of the last board load. Flipping it changes
  /// row membership, so [_reloadForHomeSettings] diffs it like a row toggle.
  /// Owned by [HomeBoardController.hideWatched].

  /// Stable ids in the user's global Home-row order. Rows not present append
  /// canonically; ids whose backing row is temporarily unavailable stay saved.
  set _homeRowOrder(List<String> value) => _board.homeRowOrder = value;

  /// Home ordering is presentation state for the Home board only. Search and
  /// Discover share some rail/focus helpers, but keep result-source order.
  bool get _homeRowOrderActive => _boardRuntime.homeRowOrderActive;

  /// Saved Home orders created before MDBList was exposed do not contain its
  /// CW ids. Seed those new ids after the Simkl CW family instead of allowing
  /// the generic ordering projection to append them at the bottom. Any MDBList
  /// id already saved keeps its chosen position untouched.

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Owned by [HomeBoardController.heroSource];
  /// resolved into [_spotlightHeroOverride] by [_resolveSpotlightHeroSource].

  /// Whether any Trakt/Simkl list row is opted in — gates the tracker-row
  /// resolve in [_load] and the integrations-triggered reload.
  bool get _trackerExtrasEnabled =>
      _homeExtras.any((r) => HomeExtraRowIds.isTracker(r.id));

  /// Board load generation. [_load] is re-entrant (Home Rows save,
  /// integration connect/disconnect) and mutates shared state
  /// ([_boardRefs]/[_boardCursor]/[_homeSections]); every await inside the
  /// load pipeline re-checks this so a superseded load can neither apply its
  /// stale sections nor advance the new load's cursor.
  int get _boardLoadGen => _board.boardLoadGen;

  /// A triggered board reload arrived while a catalog search was showing its
  /// results — running [_load] then would stomp the search view, so it's
  /// latched here and consumed by [_restoreHome].
  bool _pendingBoardReload = false;

  // Board infinite scroll. Every (addon, catalog) pair is enumerated up front in
  // [_boardRefs] (cheap — manifest metadata, no network), then fetched in batches
  // as the user nears the bottom. [_boardCursor] is the next ref to load; it
  // persists across a search detour so returning to the board keeps its place.
  bool get _boardLoadingMore => _boardRuntime.boardLoadingMore;
  SearchBoardRuntime get _boardRuntime => _content.boardRuntime;
  ScrollController get _boardScroll => _boardRuntime.boardScroll;

  /// Whether more board rows remain to lazily load (board mode only — never
  /// during a catalog search, which streams and appends its own rows).
  bool get _boardHasMore => _boardRuntime.boardHasMore;

  // Continue Watching data lives on [ContinueWatchingController] (G1'-4).
  // Thin accessors keep TitleOpener / CatalogPlayResolver / board chrome on
  // the same map instances the loaders mutate.
  List<FocusNode> get _cwMovieNodes => _cwNodes.movieNodes;
  List<FocusNode> get _cwSeriesNodes => _cwNodes.seriesNodes;
  bool get _cwMergeTrakt => _cw.cwMergeTrakt;

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
  bool get _playedSinceRefresh => _content.playedSinceRefresh;
  List<StremioMeta> get _traktAll => _cw.traktAll;
  List<FocusNode> get _traktMovieNodes => _cwNodes.traktMovieNodes;
  List<FocusNode> get _traktSeriesNodes => _cwNodes.traktSeriesNodes;
  List<StremioMeta> get _simklAll => _cw.simklAll;
  Map<String, double> get _simklProgress => _cw.simklProgress;
  List<FocusNode> get _simklMovieNodes => _cwNodes.simklMovieNodes;
  List<FocusNode> get _simklSeriesNodes => _cwNodes.simklSeriesNodes;
  List<FocusNode> get _mdblistMovieNodes => _cwNodes.mdblistMovieNodes;
  List<FocusNode> get _mdblistSeriesNodes => _cwNodes.mdblistSeriesNodes;

  FavRowsController get _favourites => _content.favourites;


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
  bool get _isTraktAuthenticated => _content.isTraktAuthenticated;

  /// Whether Simkl is connected — gates the Simkl detail quick actions,
  /// rendered as their own strip alongside Trakt's (see [_isTraktAuthenticated]).

  /// Whether MDBList is connected — gates the MDBList entry in the Discover
  /// source dropdown (hidden when disconnected, so an unauthed user isn't shown
  /// a dead source; kept visible if it's somehow the active source).
  bool get _isMdblistAuthenticated => _content.isMdblistAuthenticated;

  // Addons that produced homepage rows, indexed by id, so a Continue Watching
  // tap can route back through the right addon (for Episodes / next-episode).
  Map<String, StremioAddon> get _addonsById => _content.addonsById;

  List<CwRow> get _cwRows => _cw.buildRows(homeDisabled: _homeDisabled);

  bool get _cwVisible => _cw.visible(
        homeDisabled: _homeDisabled,
        catalogQuery: _catalogQuery,
        catalogSearching: _catalogSearching,
      );

  bool get _traktReserving => _cw.traktReserving(
        searchMode: widget.searchMode,
        discoverMode: false,
        isTraktAuthenticated: _isTraktAuthenticated,
        catalogQuery: _catalogQuery,
        catalogSearching: _catalogSearching,
      );

  late final HeroPresenter _hero = HeroPresenter(
    environment: () => HeroEnvironment(
      isTelevision: widget.isTelevision,
      searchMode: widget.searchMode,
      discoverMode: false,
      catalogQuery: _catalogQuery,
      stageActive: _stageActive,
      stagePublishesShellArt: _stagePublishesShellArt,
      stageWantsAmbient: _stageWantsAmbient,
      homeStyle: _homeStyleEffective,
      hasFavouriteFocus: _canvasFavFocus.value != null,
    ),
    isMounted: () => mounted,
    hostContext: () => context,
    updateHost: (change) => setState(change),
    clearFavouriteFocus: () => _canvasFavFocus.value = null,
    showingHeroId: () => _spotlightKey.currentState?.currentHeroId,
  );

  // Stage-part compatibility aliases; removal lane: G1'-8 StageHost conversion.
  ValueNotifier<StremioMeta?> get _heroItem => _hero.heroItem;
  ValueNotifier<StremioMeta?> get _heroEnriched => _hero.heroEnriched;
  ValueNotifier<YoutubeResolvedStreams?> get _heroTrailer => _hero.trailer;
  ValueNotifier<bool> get _heroTrailerLoading => _hero.trailerLoading;
  ValueNotifier<bool> get _heroTrailerShowing => _hero.trailerShowing;
  ValueNotifier<double> get _heroTrailerTakeover => _hero.trailerTakeover;
  ValueNotifier<String?> get _heroLiveUrl => _hero.liveUrl;
  ValueNotifier<IptvChannel?> get _heroLiveChannel => _hero.liveChannel;
  ValueNotifier<bool> get _heroLiveTakeover => _hero.liveTakeover;
  ValueNotifier<Color?> get _heroTint => _hero.tint;
  bool get _heroTrailerEnabled => _hero.trailerEnabled;
  double get _heroTrailerVolume => _hero.trailerVolume;
  bool get _heroTrailerActive => _hero.trailerActive;
  bool get _heroTrailerRenderable => _hero.trailerRenderable;
  bool get _heroActive => _hero.active;

  // Discover tab: the active source key (CW / tracker / `a:{addonId}`) + its
  // DPAD focus node (the "Source" dropdown is the leading filter of whichever
  // embedded See-All panel is shown). [_discAddons] is the browsable addon list
  // appended to the Source dropdown.
  // Incremented only for an explicit dropdown choice. Async preference/add-on
  // hydration may apply its captured landing source only while this is still
  // unchanged, so a late manifest response can never undo user input.
  final DiscoverLifecycle _discover = DiscoverLifecycle();
  // Transitional render adapters expire with real G17 ownership / Q2.
  FocusNode get _discSourceNode => _discover.sourceNode;

  /// An MDBList list handed off from the Search tab's Lists mode (consumed
  /// from MainPageBridge.pendingMdblistListOpen on mount). Passed into the
  /// MDBList panel, which opens focused on it with the ♥ like toggle.


  void _onDiscoverPreferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tonight.board = _boardRuntime;
    _tonight.columns = _canvasCols;
    _tonight.shelf = _stageShelf;
    _tonight.bindings = (
      readStageRails: () => _stageRails,
      resolveRailIndex: _resolveCanvasRailIndex,
      nearestMountedNode: _nearestMountedNode,
      railKeyOf: _canvasRailKeyOf,
      resolveStageRail: _resolveStageRail,
      seedFocusOnce: _seedStageFocusOnce,
      switchRail: _stageSwitchRail,
      holdSwallow: _stageHoldSwallow,
      holdJump: _stageHoldJump,
      setHero: _setHero,
      isBound: _isBound,
      openCwMenu: _openCwCardMenu,
      wideArtUrl: wideArtUrl,
      atriumLabelHeight: _atriumLabelHeight,
      railBoxHeight: _stageRailBoxH,
      posterWidth: _stagePosterW,
      favouriteWidth: _stageFavW,
      buildFavCell: _stageFavouriteCells.build,
      buildRailLabel: _deckRailLabel,
      buildCardLayers: _tonightCardLayers,
      labelGap: _kAtriumLabelGap,
    );
    _content.surface = this;
    _content.presentation = this;
    _content.readOptions = () => (isTelevision: widget.isTelevision,
      searchMode: widget.searchMode, discoverMode: false);
    _boardRuntime.continueStageAdvance = _continueStageAdvance;
    _boardRuntime.continueStageRight = _continueStageRight;
    _boardRuntime.leaveBoardTop = _leaveBoardTop;
    _boardRuntime.stageActive = () => _stageActive;
    _boardRuntime.stageRailKey = () => _canvasRailKey;
    _content.initialize(readMergedRows: widget.readCwMergedRows);
    WidgetsBinding.instance.addObserver(this);
    _profileSessionOwner = ProfileSessionMemory.captureOwner();
    // This one widget backs three tabs (Home board / dedicated Search / Discover).
    AnalyticsService.screenView(
      searchScreenAnalyticsName(
        searchMode: widget.searchMode,
        discoverMode: false,
      ),
    );
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusContent);
    if (!widget.searchMode) {
      StorageService.localCompletionRevision.addListener(
        _onLocalCompletionChanged,
      );
      MdblistService.instance.playbackRevision.addListener(
        _onMdblistPlaybackRevision,
      );
    }
    if (widget.searchMode) {
      MainPageBridge.registerTabBackHandler('search', _handleSearchBack);
    }
    // A detail-open handed off from another tab (e.g. the Trakt Calendar, a
    // separate tab that can't reach this screen's state). Only the Home board
    // (not the Search/Discover variants) claims it; the opener switches here via
    // switchTab(15) right after setting it, so it's present by the time we mount.
    if (!widget.searchMode) {
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

    _hero.registerTv();
    _discover.addListener(_onDiscoverPreferencesChanged);

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
    var restoredKeyword = false;
    if (searchScreenRestoresKeyword(
      isTelevision: widget.isTelevision,
      searchMode: widget.searchMode,
      discoverMode: false,
    )) {
      restoredKeyword = _keyword.restore(_profileSessionOwner, _variantKey);
      if (restoredKeyword) _mode = SearchBoardMode.keyword;
    }
    // Home board only: live-refresh when the Home Rows manager changes which
    // rows are hidden (on non-TV, Settings is a pushed route so the board isn't
    // rebuilt on return; on TV a tab switch already reloads it fresh).
    if (!widget.searchMode) {
      MainPageBridge.addHomeSettingsListener(_reloadForHomeSettings);
      // IPTV list mutations (picker, IPTV settings, provider deletion,
      // reconcile, import) all bump the store revision — the only signal a
      // Home that stays alive across tab switches gets about them.
      IptvMediaStore.listsRevision.addListener(_favourites.onIptvListsRevision);
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
        MainPageBridge.addPlayerLaunchListener(_hero.onContentPlayerLaunch);
        unawaited(_hero.reloadOffTvTrailerPrefs());
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
    if (!widget.isTelevision && !widget.searchMode) {
      _searchFocusNode.addListener(_onSearchFocusLatchSheet);
    }
    _boardScroll.addListener(_onBoardScroll);
    _refreshTraktAuthState();
    _refreshSimklAuthState();
    _refreshMdblistAuthState();
    _loadMergedSeriesFlag();
    // (The keyword restore itself ran earlier — before _loadHomeDefaultView —
    // see the ordering comment there.) A restored search carries its own
    // filters, so don't overwrite them with the saved defaults.
    if (!restoredKeyword) unawaited(_keyword.loadDefaultFilters());
    // The dedicated Search tab only shows a field + blank prompt until a query,
    // so it skips the whole board pipeline (home catalogs, Continue Watching,
    // Trakt, favourites) — catalog search fetches its addons on demand. It also
    // never runs _load(), which is what clears _loading, so clear it here or the
    // results grid (_buildBoard) would sit on its initial spinner forever.
    if (widget.searchMode) {
      _loading = false;
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
        _favourites.loadTvFavorites(),
        _favourites.loadStremioTvFavorites(),
        _favourites.loadIptvFavorites(),
        _favourites.loadMyWatchlist(),
        _favourites.loadIptvListRows(),
        _favourites.loadPlaylistFavorites(),
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
        _keyword.kwQuery.isNotEmpty ||
        _listsQuery.isNotEmpty;
    if (!hasQuery) return false;
    // Back also drops out of Keyword/Lists mode, so the tab returns to its
    // default Catalog prompt (matches the old overlay-close behaviour).
    // _clearQuery rebuilds, so setting the field first is enough.
    _mode = SearchBoardMode.catalog;
    _clearQuery();
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
    return true;
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
    _keyword.invalidate();
    _mode = SearchBoardMode.catalog;
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
    if (!widget.searchMode) _loadContinueWatching();
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
    if (!widget.searchMode && _trackerExtrasEnabled) {
      _requestBoardReload();
    }
  }

  Future<void> _refreshTraktAuthState() => _content.refreshTraktAuthState();

  Future<void> _refreshSimklAuthState() => _content.refreshSimklAuthState();

  Future<void> _refreshMdblistAuthState() => _content.refreshMdblistAuthState();

  @override
  void dispose() {
    _board.removeListener(_content.onBoardChanged);
    _board.dispose();
    _catalogSearch.removeListener(_content.onCatalogSearchChanged);
    _catalogSearch.dispose();
    _keyword.preserve(
      _profileSessionOwner,
      _variantKey,
      modeIsKeyword: _mode == SearchBoardMode.keyword,
    );
    _keyword.dispose();
    _cw.removeListener(_content.onContinueWatchingChanged);
    _cw.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _spotlightHeroNode.dispose();
    MainPageBridge.unregisterTvContentFocusHandler(_tabIndex, _focusContent);
    StorageService.localCompletionRevision.removeListener(
      _onLocalCompletionChanged,
    );
    MdblistService.instance.playbackRevision.removeListener(
      _onMdblistPlaybackRevision,
    );
    if (!widget.searchMode) {
      MainPageBridge.unregisterCatalogDetailOpenHandler(
        _openPendingCatalogDetail,
      );
    }
    if (widget.searchMode) {
      MainPageBridge.unregisterTabBackHandler('search', _handleSearchBack);
    }
    if (!widget.isTelevision && !widget.searchMode) {
      // Same closure that registered — the bridge's mid-transition contract.
      MainPageBridge.unregisterTabBackHandler('home', _handleHomeBack);
      _searchFocusNode.removeListener(_onSearchFocusLatchSheet);
      MainPageBridge.removePlayerLaunchListener(_hero.onContentPlayerLaunch);
    }
    // Safe no-op in the variants that never registered it.
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    MainPageBridge.removePlayerLaunchListener(_markPlaybackStarted);
    MainPageBridge.removeHomeSettingsListener(_reloadForHomeSettings);
    IptvMediaStore.listsRevision.removeListener(_favourites.onIptvListsRevision);
    for (final row in _favourites.iptvListRows) {
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
    if (widget.isTelevision && !widget.searchMode) {
      _heroTrailerShowing.removeListener(_onCanvasTrailerShowingChanged);
      HardwareKeyboard.instance.removeHandler(_onCanvasTheaterKey);
      HardwareKeyboard.instance.removeHandler(_onStageHoldKey);
    }
    _canvasTheaterTimer?.cancel();
    _canvasFavFocus.dispose();
    _atriumFocusedRailKey.dispose();
    _tonight.dispose();
    _stageCol.dispose();
    _hero.detachShell(unsubscribeRoute: () => appRouteObserver.unsubscribe(this));
    _catalogDebounce?.cancel();
    _hero.dispose();
    _searchController.dispose();
    _catalogSourcesHideTimer?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusForSources);
    _searchFocusNode.dispose();
    _modeCatalogNode.dispose();
    _modeKeywordNode.dispose();
    _modeListsNode.dispose();
    _modeDropdownNode.dispose();
    _disposeListsNodes();
    _discover.removeListener(_onDiscoverPreferencesChanged);
    _discover.dispose(isTelevision: false);
    _boardScroll.dispose();
    _catalogSourcesBtnFocus.dispose();
    _disposeNodes();
    for (final n in [
      ..._favourites.tvFavNodes,
      ..._favourites.stvFavNodes,
      ..._favourites.iptvFavNodes,
      ..._favourites.watchlistMovieNodes,
      ..._favourites.watchlistSeriesNodes,
      ..._favourites.playlistFavNodes,
    ]) {
      n.dispose();
    }
    _favourites.tvFavNodes.clear();
    _favourites.stvFavNodes.clear();
    _favourites.iptvFavNodes.clear();
    _favourites.watchlistMovieNodes.clear();
    _favourites.watchlistSeriesNodes.clear();
    _favourites.playlistFavNodes.clear();
    super.dispose();
  }

  void _disposeNodes() => _boardRuntime.disposeNodes();

  /// Re-read the hidden-rows set + opted-in extras and reload the board if
  /// either actually changed. Fires on any home-settings change (the
  /// broadcast is shared), so the equality guards skip reloads for unrelated
  /// settings.
  Future<void> _reloadForHomeSettings() async {
    if (!mounted) return;
    final cardSettings = await Future.wait<Object>([
      HomePrefs.getHomeCardOrientation(),
      HomePrefs.getHomeHideCardTitlesAndRatings(),
      HomePrefs.getHomeHideCatalogAddonNames(),
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
    await _cw.reloadMergeFlags();
    if (!mounted) return;
    // Off-TV the hero-trailer prefs ride this same signal — Settings is a
    // pushed route here, so nothing else tells a surviving Home about them.
    if (!widget.isTelevision) {
      unawaited(_hero.reloadOffTvTrailerPrefs());
    }
    await _loadHomeDefaultView();
    if (!mounted) return;
    final disabled = await HomePrefs.getHomeDisabledSections();
    final extras = await HomePrefs.getHomeExtraRows();
    final rowOrder = await HomePrefs.getHomeRowOrder();
    final heroSource = await HomePrefs.getHomeHeroSource();
    final collections = await HomeCollectionsStore.instance.getCollections();
    if (!mounted) return;
    final action = _board.diffAndApplySettings(
      HomeBoardSettingsSnapshot(
        disabled: disabled,
        extras: extras,
        rowOrder: rowOrder,
        heroSource: heroSource,
        collections: collections,
        hideWatched: HideWatchedPrefs.enabled,
      ),
      isHomeBoard: !widget.searchMode,
    );
    if (action.nothingChanged) return;
    // Hide-watched changes row MEMBERSHIP, so it takes the full reload path.
    if (action.requestBoardReload) {
      _requestBoardReload();
    } else if (action.rerollHero) {
      // Only the hero source moved — re-roll the reel without refetching the
      // whole board. `_load` isn't rerun here, so resolve from the addons the
      // last load cached.
      unawaited(_resolveSpotlightHeroSource(_addonsById.values.toList()));
    }
    // IPTV list rows live outside the board's section pipeline. The loader
    // reads its own extras from storage, so it can't race the reload above.
    if (action.reloadIptvLists) unawaited(_favourites.loadIptvListRows());
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
      if (_mode != SearchBoardMode.catalog) _switchMode(SearchBoardMode.catalog);
      return;
    }
    final saved = await HomePrefs.getHomeDefaultSourceType();
    if (!mounted || widget.searchMode) return;
    final mode =
        saved == 'keyword' &&
            ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)
        ? SearchBoardMode.keyword
        : SearchBoardMode.catalog;
    if (_mode != mode) _switchMode(mode);
  }

  Future<void> _load() async {
    final gen = _board.beginLoad();
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_refreshPikpakOnly());
    try {
      final disabled = await HomePrefs.getHomeDisabledSections();
      final extras = await HomePrefs.getHomeExtraRows();
      final rowOrder = await HomePrefs.getHomeRowOrder();
      final heroSource = await HomePrefs.getHomeHeroSource();
      final collections = await HomeCollectionsStore.instance.getCollections();
      // Commit the prefs and (crucially) start the tracker fan-out only if
      // this load still owns the board — a superseded run kicking off its own
      // resolve would double the concurrent tracker requests beside the
      // winning generation's and stale-write the shared settings fields.
      if (!mounted || gen != _boardLoadGen) return;
      _homeDisabled = disabled;
      _homeExtras = extras;
      _homeRowOrder = rowOrder;
      _board.heroSource = heroSource;
      _homeCollections = collections;
      _board.homeCollectionsSig = HomeCollectionsStore.signatureOf(collections);
      _board.hideWatched = HideWatchedPrefs.enabled;
      // Opt-in Trakt/Simkl list rows, resolved IN PARALLEL with the first
      // catalog batch below. Home board only — the Search tab runs _load just
      // to warm the catalog refs for its search, and Discover never comes
      // through here. The 5s deadline keeps the rows that finished and drops
      // stragglers, bounding what an enabled config can add to first paint
      // (nothing at all is fetched in the default, nothing-enabled config).
      final listRowsFuture =
          widget.searchMode || !_trackerExtrasEnabled
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
      _board.replaceBoardRefs(
        HomeBoardController.enumerateBoardRefs(
          addons: addons,
          disabled: _homeDisabled,
          collections: _homeCollections,
        ),
        applySavedOrder: _homeRowOrderActive,
      );
      _addonsById.clear();
      for (final a in addons) {
        _addonsById.putIfAbsent(a.id, () => a);
      }
      // Resolve the Spotlight hero's own reel in parallel with the first
      // batch — its catalog may sit far down the board (or be hidden as a
      // row), so it can't wait for a batch to happen to include it. Home
      // board only, like the list rows above.
      if (!widget.searchMode) {
        unawaited(_resolveSpotlightHeroSource(addons));
      }
      // First batch is blocking so the board isn't empty on first paint; skip
      // runs of empty catalogs so we always land on some visible rows.
      final first = await _fetchBoardBatchUntilNonEmpty(gen);
      final listRows = await listRowsFuture;
      if (!mounted || gen != _boardLoadGen) return;
      // List rows lead the sections — after the favourites rows, before every
      // addon catalog row. Batching appends after them untouched.
      // Imported collections follow Nuvio's order: pinned ones lead the
      // board, the rest sit after the tracker list rows and before every
      // addon catalog row. No network — folders are static tiles.
      final collectionRows = widget.searchMode
          ? const <HomeCollectionSection>[]
          : HomeBoardController.buildCollectionSections(
              collections: _homeCollections,
              disabled: _homeDisabled,
            );
      final sections = HomeBoardController.assembleHomeSections(
        collectionRows: collectionRows,
        listRows: listRows,
        firstBatch: first,
      );
      _homeSections = sections;
      setState(() => _loading = false);
      MainPageBridge.homeBoardReady.value = true;
      // A catalog search may have STARTED while this load was in flight —
      // `_sections` now holds (or is streaming) search results, and applying
      // the board over them would permanently mix the two views. Same
      // discipline as _loadMoreBoard: the Home cache above is refreshed, the
      // visible view is not — _restoreHome re-applies _homeSections when the
      // search ends.
      if (_catalogQuery.isNotEmpty || _catalogSearching) return;
      _applySections(sections);
      _maybeAutoFocusBoard();
      _maybeAutoFillBoard();
    } catch (e) {
      if (!mounted || gen != _boardLoadGen) return;
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
        _error = e.toString();
        _loading = false;
      });
      // Terminal state too — the launch splash must not outlive the board's
      // loading phase just because it ended in an error screen.
      MainPageBridge.homeBoardReady.value = true;
    }
  }

  /// Fetch the next batch of catalog rows from [_boardCursor], skipping over any
  /// runs of empty catalogs, and return the non-empty sections (advancing the
  /// cursor as it goes). Empty result ⇒ the board is exhausted — or [gen] went
  /// stale (a newer [_load] owns the cursor now; stop without touching it).
  Future<List<CatalogSection>> _fetchBoardBatchUntilNonEmpty(int gen) =>
      _board.fetchBoardBatchUntilNonEmpty(gen);

  /// Production catalog-page adapter for [HomeBoardController]: same
  /// [fetchFilteredPage] + hide-watched predicate as the origin `_fetchBoardBatch`
  /// / `_loadMoreRow` / `_resolveSpotlightHeroSource` inlines.






  /// After a batch lands, if the board still doesn't fill the viewport (so the
  /// user can't scroll to trigger more) keep pulling batches until it does or
  /// the board is exhausted. No-ops outside board mode (search sets no cursor).
  void _maybeAutoFillBoard() => _boardRuntime.maybeAutoFillBoard();

  /// Fire off the next batch as the user nears the bottom of the board.
  void _onBoardScroll() => _boardRuntime.onBoardScroll();

  /// Load and append the next batch of board rows (deduped against re-entry).
  Future<bool> _loadMoreBoard() => _boardRuntime.loadMoreBoard();

  /// Append newly-loaded board rows without disturbing the rows already shown:
  /// grow the per-row focus nodes in lockstep with [_sections].

  /// Fetch the next page for a single catalog row and append it in place, so
  /// rows grow without bound as the user scrolls right (Stremio-style). Only
  /// board rows paginate; search-result rows are single-shot. Safe to call
  /// repeatedly — [CatalogSection.loadingMore]/[CatalogSection.exhausted] guard
  /// re-entrancy and the end of the catalog.
  Future<void> _loadMoreRow(int rowIndex) => _boardRuntime.loadMoreRow(rowIndex);

  /// IMDb id for a catalog item, or null when it isn't a `tt…` id.

  bool _isBound(StremioMeta item) => _content.isBound(item);


  /// Re-read how many pinned sources each currently-displayed title has. Called
  /// after sections load and after any bind/unbind/playback.

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() => _content.refreshPikpakOnly();

  Future<void> _loadContinueWatching() => _cw.loadContinueWatching();

  void _onLocalCompletionChanged() => _cw.onLocalCompletionChanged(
        searchMode: widget.searchMode,
        discoverMode: false,
      );

  Future<void> _loadIptvContinueWatching() =>
      _cw.loadIptvContinueWatching(searchMode: widget.searchMode);

  /// Open an IPTV Continue Watching card: a series routes to the merged Xtream
  /// series page, a movie resumes playback. Both go through [IptvCwRouter];
  /// [_playedSinceRefresh] latches so the return refresh rebuilds the shelves.

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

  /// Resolve the addon that a Continue Watching title should route through.
  /// Prefers the stored source addon; falls back to any homepage addon, then a
  /// minimal placeholder so Play still works even if the addon is gone.
  StremioAddon _addonForContinue(String? addonId) => _content.addonForContinue(addonId);

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
  /// [ContinueWatchingController.playTrakt] (CW-cached resume, else catalog play
  /// with Trakt-first resume); Simkl rows play plainly like Discover's lists.
  void _sectionQuickPlay(CatalogSection section, StremioMeta item) {
    // A folder tile has nothing to play — open it instead.
    if (section is HomeCollectionSection) {
      _openCollectionFolder(section, item);
      return;
    }
    if (section is HomeListSection) {
      if (section.isTrakt) {
        _cw.playTrakt(item);
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
                    _openItem(item, _addonForContinue(item.sourceAddon?.id)),
                onQuickPlay: _pikpakOnly
                    ? null
                    : (item) => _onCatalogPlay(
                        item,
                        _addonForContinue(item.sourceAddon?.id),
                      ),
              ),
            ),
          ),
        )
        .then((_) => _afterSeeAllReturn());
  }

  /// Open a plain Simkl-list title (Discover's Simkl Trending/watchlist lists) —
  /// a normal catalog detail, no resume. The CW list uses [ContinueWatchingController.openSimkl]
  /// instead, so a title browsed fresh here never opens mid-episode.
  void _openSimklItem(StremioMeta item) => _content.actions.openSimklItem(item);

  /// Quick-play a plain Simkl-list title like any other catalog item (no
  /// resume). The CW list uses [ContinueWatchingController.playSimkl].
  void _playSimklItem(StremioMeta item) => _content.actions.playSimklItem(item);

  Future<void> _loadTraktContinueWatching({bool refreshBound = true}) =>
      _cw.loadTraktContinueWatching(refreshBound: refreshBound);

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



  bool _cwMenuOpen = false;

  Future<void> _openCwCardMenu(
    CwRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) =>
      openCwCardMenu(
        context: context,
        row: row,
        item: item,
        cwIndex: cwIndex,
        col: col,
        isTelevision: widget.isTelevision,
        pikpakOnly: _pikpakOnly,
        isMenuOpen: () => _cwMenuOpen,
        setMenuOpen: (v) => _cwMenuOpen = v,
        isLive: () => mounted,
        refocusAfterRemoval: _refocusAfterCwRemoval,
      );

  /// Put TV focus back on the board after a removal: the card that had it is
  /// gone (and its FocusNode with it, if the row shrank), which would otherwise
  /// leave the remote dead until the global reclaim listener notices.
  void _refocusAfterCwRemoval(int cwIndex, int col) {
    if (!widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusCwRow(cwIndex, col)) return;
      for (var i = cwIndex - 1; i >= 0; i--) {
        if (_focusCwRow(i, col)) return;
      }
      _leaveBoardTop();
    });
  }


  Future<void> _loadSimklContinueWatching({bool refreshBound = true}) =>
      _cw.loadSimklContinueWatching(refreshBound: refreshBound);

  Future<void> _loadMdblistContinueWatching({
    bool refreshBound = true,
    bool force = false,
  }) =>
      _cw.loadMdblistContinueWatching(refreshBound: refreshBound, force: force);

  void _onMdblistPlaybackRevision() => _cw.onMdblistPlaybackRevision(
        searchMode: widget.searchMode,
        discoverMode: false,
        isRouteCurrent: () => ModalRoute.of(context)?.isCurrent ?? true,
      );

  /// Swap the displayed sections (homepage or search results): rebuild the
  /// per-row focus nodes and reset the hero to the first item.
  void _applySections(List<CatalogSection> sections) => _content.applySections(sections);

  @override
  void seedHero(List<CatalogSection> sections) => _hero.seedSections(sections);

  /// Cross-addon catalog search, grouped as one horizontal row per addon so it
  /// matches the board (not a merged grid).
  Future<void> _runCatalogSearch(String query) => _content.runCatalogSearch(query);

  /// Cancel any pending search and return to the homepage board.
  void _restoreHome() {
    _catalogSearch.cancel();
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
    _boardRuntime.maybeCompleteDeferredDown();
    if (_autoFocusSettled || _autoFocusScheduled) return;
    if (!widget.isTelevision) return;
    if (widget.searchMode) return;
    _autoFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Coalesced pass: reads the final top after every same-frame load's
      // setState has applied, so multiple loads don't race.
      _autoFocusScheduled = false;
      if (!mounted || _autoFocusSettled) return;
      if (widget.searchMode) return;
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
        anyOf(_favourites.tvFavNodes) ||
        anyOf(_favourites.stvFavNodes) ||
        anyOf(_favourites.iptvFavNodes) ||
        anyOf(_favourites.watchlistMovieNodes) ||
        anyOf(_favourites.watchlistSeriesNodes) ||
        anyOf(_favourites.playlistFavNodes)) {
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
    // Dedicated Search tab: land on the results when they're on-screen, else the
    // field (the blank prompt has nothing focusable below it). Only focus board
    // rows when a query is actually showing them — otherwise their nodes aren't
    // mounted and focus would be stranded.
    if (widget.searchMode) {
      if (_mode == SearchBoardMode.keyword) {
        if (_kwToolbarVisible) {
          _keyword.kwToolbarNodes.first.requestFocus();
        } else {
          _searchFocusNode.requestFocus();
        }
        return;
      }
      if (_mode == SearchBoardMode.lists) {
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
    if (_mode == SearchBoardMode.keyword) {
      // Toolbar + result rows render together, so entering the content lands on
      // the toolbar first (Down then reaches the rows). When it isn't visible
      // (loading / error / pre-search) nothing below is focusable, so keep the
      // search field rather than a stale, detached result node.
      if (_kwToolbarVisible) {
        _keyword.kwToolbarNodes.first.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      return;
    }
    if (_mode == SearchBoardMode.lists) {
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
      SearchBoardMode.catalog => _modeCatalogNode,
      SearchBoardMode.keyword => _modeKeywordNode,
      SearchBoardMode.lists => _modeListsNode,
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
      _mode == SearchBoardMode.keyword && _keyword.kwToolbarVisible;

  /// Whether the pre-search "Sources" button is on-screen — the empty keyword
  /// state, before a query. It's the only focusable content then, so DPAD-down
  /// from the search field must land on it (see the field's key handler).
  bool get _kwSourcesButtonVisible =>
      _mode == SearchBoardMode.keyword && _keyword.kwSourcesButtonVisible;

  /// Catalog-mode twin of [_kwSourcesButtonVisible]: the Sources button shown
  /// on the empty catalog prompt (Search tab, no query yet, not mid-search).
  bool get _catalogSourcesButtonVisible =>
      _mode == SearchBoardMode.catalog &&
      widget.searchMode &&
      _catalogQuery.isEmpty &&
      !_catalogSearching;

  /// Returns false when the target catalog row isn't loaded/focusable (after
  /// kicking the next batch load if one is available) — same contract as
  /// [_focusCwRow], so DPAD wiring can defer the move instead of eating it.
  bool _focusRow(int row, int column) => _boardRuntime.focusRow(row, column);

  /// Focus [desired] in [nodes] if its cell is mounted; otherwise the nearest
  /// mounted cell. A horizontal ListView.builder unmounts off-screen cells, and
  /// requestFocus() on an unmounted FocusNode is a silent no-op — so a naive
  /// nodes[desired].requestFocus() leaves focus stranded on the previous row.
  void _requestRowFocus(List<FocusNode> nodes, int desired, {int hops = 0}) =>
      _boardRuntime.requestRowFocus(nodes, desired, hops: hops);

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
      _hideHomeCardTitlesAndRatings ? 0 : artPosterCaptionBand(context);

  bool get _homeBoardMode =>
      widget.isTelevision && !widget.searchMode;

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
      !false &&
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
      _mode != SearchBoardMode.catalog ||
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
  /// board instead of cutting across it. See [_hero.publishAmbientArt].
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

  /// The node that pressed the key. A deferred move is only ever completed
  /// while THAT node still holds focus — the rail key alone isn't enough
  /// (moving LEFT along the same rail, or out to the sidebar, leaves it
  /// unchanged), and a late batch must never yank the user somewhere else.

  /// Atrium-only: the pending move fills the window's EMPTY lower row rather
  /// than scrolling the window on.

  /// A RIGHT that ran off the END of a rail whose catalog still had pages.
  /// Mosaic's grid depends on it: DOWN there always leaves for the next rail,
  /// so RIGHT is the only way through a long catalog and eating the keypress
  /// would strand the user at the page boundary.

  void _deferStageRight(String railKey, int col) =>
      _boardRuntime.deferStageRight(railKey, col);

  /// Record a deferred rail move, anchored to whoever pressed the key.
  void _deferStageAdvance(String railKey, {bool fillsLower = false}) =>
      _boardRuntime.deferStageAdvance(railKey, fillsLower: fillsLower);

  /// Shared staleness test for both deferred moves.


  /// Called when a ROW's next page lands: completes a deferred RIGHT if the
  /// user is still sitting on the cell they pressed it from.
  void _continueStageRight(String key, int col, FocusNode? origin) {
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
    _tonight.zoneIsQueue = true;
    _tonight.queueCol = 0;
    _tonight.queueKey = null;
    _atriumFocusedRailKey.value = null;
    _tonight.card.value = null;
    _stageCol.value = 0;
    _boardRuntime.pendingStageAdvanceKey = null;
    _boardRuntime.pendingStageAdvanceAt = null;
    _boardRuntime.pendingStageAdvanceFillsLower = false;
    _boardRuntime.pendingStageOrigin = null;
    _boardRuntime.pendingStageRightKey = null;
    _boardRuntime.pendingStageRightAt = null;
    _boardRuntime.pendingStageRightCol = -1;
    _boardRuntime.pendingStageRightOrigin = null;
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
    _hero.clearTrailer();
    _hero.clearLiveIptv();
    _resetStageNavigation();
    // The shell's ambient art is per-layout (ink-ground layouts publish
    // none), so clear it rather than leaving the old layout's lighting in
    // the strip behind the ghost rail.
    _hero.resetAmbientArtIdentity();
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
      _hero.publishAmbientArt(_heroItem.value, _heroEnriched.value);
      _hero.publishTintToShell(_heroTint.value);
    });
  }

  Future<void> _loadTvHomeStyle() async {
    final style = await StorageService.getTvHomeStyle();
    if (!mounted || style == _tvHomeStyle) return;
    _applyStageTransition(style);
  }

  Future<void> _loadHomeCardOrientation() async {
    final values = await Future.wait<Object>([
      HomePrefs.getHomeCardOrientation(),
      HomePrefs.getHomeHideCardTitlesAndRatings(),
      HomePrefs.getHomeHideCatalogAddonNames(),
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
  /// [CanvasFavFocus]). A ValueNotifier — NOT setState — so scrubbing along
  /// a favourites rail repaints only the stage layers that listen (art +
  /// identity), never the whole board (the hero pipeline's own pattern).
  final ValueNotifier<CanvasFavFocus?> _canvasFavFocus =
      ValueNotifier<CanvasFavFocus?>(null);

  /// A Canvas favourites cell took focus: remember the column, stop any
  /// catalog trailer machinery (a PENDING hero swap firing later would start
  /// a full-bleed trailer of an unrelated title under favourites browsing),
  /// drive the live preview for IPTV, and hand the stage the favourite's own
  /// art + name.
  void _canvasFavFocused(
    String railKey,
    int col,
    CanvasFavFocus focus, {
    IptvChannel? liveChannel,
  }) {
    _canvasCols[railKey] = col;
    _stageCol.value = col;
    // Atrium's two-row window needs to know which row owns focus (favourites
    // cells don't go through a _BoardCell onFocused), and favourites only
    // ever live in Tonight's RAIL zone, never its Continue queue.
    _atriumFocusedRailKey.value = railKey;
    _tonight.zoneIsQueue = false;
    _hero.cancelPendingSwap();
    _hero.clearTrailer();
    if (liveChannel != null && _stageWantsLivePreview) {
      _hero.setLiveIptv(liveChannel);
    } else {
      _hero.clearLiveIptv();
    }
    _canvasFavFocus.value = focus;
  }

  late final StageFavouriteCells _stageFavouriteCells = StageFavouriteCells(
    readFavourites: () => _favourites,
    readHideTitles: () => _hideHomeCardTitlesAndRatings,
    switchRail: _stageSwitchRail,
    focused: _canvasFavFocused,
  );

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

  String _canvasRailKeyOf(CanvasRail rail) {
    return 'row:${_canvasRailRowId(rail)}';
  }

  /// Where the active rail currently sits in [rails] — re-resolved every
  /// build so insertions above it never change WHICH rail is shown.
  int _resolveCanvasRailIndex(List<CanvasRail> rails) {
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
  CatalogSection? get _spotlightHeroOverride => _board.spotlightHeroOverride;

  /// Guards [_resolveSpotlightHeroSource] against overlapping runs (a Home
  /// Rows save landing mid-load): only the newest run may commit.
  int get _heroSourceResolveGen => _board.heroSourceResolveGen;

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
    final expected = _heroSourceResolveGen + 1;
    await _board.resolveSpotlightHeroSource(addons);
    if (!mounted || _heroSourceResolveGen != expected) return;
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
    if (!PlatformUtil.isTvOS || widget.searchMode) {
      return;
    }
    unawaited(
      TvosTopShelfService.instance.publishSpotlight(
        _spotlightHero,
        sourceTitle: _spotlightHeroSection?.title,
      ),
    );
  }

  SpotlightStageContent get _spotlightContent => SpotlightStageContent(
    board: _boardRuntime,
    favourites: _favourites,
    bindings: (
      landscapeCards: () => _homeLandscapeCards,
      railKeyOf: _canvasRailKeyOf,
      wideArtUrl: wideArtUrl,
      catalogSourceTag: _catalogSourceTag,
      stvFavArt: _stvFavArt,
      iptvPreview: (channel) => SpotlightIptvCardPreview(
        channel: channel, ambientVolume: _heroTrailerVolume,
      ),
      openCatalogSeeAll: _openCatalogSeeAll,
      openCollectionFolder: _openCollectionFolder,
      openItem: _openItem,
      openCwCardMenu: _openCwCardMenu,
    ),
  );

  List<SpotlightShelf> get _spotlightShelves => _spotlightContent.shelves;

  /// A Stremio TV favourite's card art: the channel's rotating now-playing
  /// poster — the same resolution the classic and Canvas rails use. Spotlight
  /// landscape mode instead chooses the title's best wide art. Null
  /// (placeholder) until the channel's items load.
  String? _stvFavArt(StremioTvChannel ch, {bool landscape = false}) {
    final item = _favourites.stvNowPlaying(ch)?.item;
    if (item == null) return null;
    if (landscape) return wideArtUrl(item);
    return _favourites.firstNonEmpty(item.poster, item.background);
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
    if (_homeStyleEffective == 'tonight' && _tonight.zoneIsQueue) {
      final queue = _tonight.queue;
      if (queue.isNotEmpty) {
        final e = queue[_tonight.resolveQueueIndex(queue)];
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

  /// The canonical rails, globally sorted by the user's saved row ids.
  List<CanvasRail> get _canvasRails => _boardRuntime.canvasRails;

  /// Classic renders the same globally ordered rails as every stage layout,
  /// plus focusless Trakt placeholders while that account is loading.
  List<CanvasRail> get _classicHomeRails => _boardRuntime.classicHomeRails;

  String _canvasRailRowId(CanvasRail rail) => _boardRuntime.canvasRailRowId(rail);


  /// Classic-board vertical focus by stable row id. The ordered list is
  /// re-resolved on every press because tracker/favourite rows can arrive
  /// asynchronously and catalog batches can insert around the current row.
  void _focusRelativeHomeRail(String rowId, int delta, int column) =>
      _boardRuntime.focusRelativeHomeRail(rowId, delta, column);

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

  late final CanvasStageBindings _canvasBindings = (
    resolveRail: _resolveStageRail,
    seedFocus: _seedStageFocusOnce,
    favouriteCount: _canvasFavItemCount,
    readTheater: () => _canvasTheater,
    readTrailerActive: () => _heroTrailerActive,
    cacheWidth: () => _tvHeroArtworkCacheWidth,
    cacheHeight: () => _tvHeroArtworkCacheHeight,
    heroItem: _heroItem,
    enriched: _heroEnriched,
    favourite: _canvasFavFocus,
    trailerShowing: _heroTrailerShowing,
    buildTrailer: (boardH) => _HeroTrailerLayer(
      trailer: _heroTrailer,
      isTelevision: widget.isTelevision,
      heroHeight: boardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      loading: _heroTrailerLoading,
      onPlayingChanged: _onHeroTrailerPlaying,
      takeover: _heroTrailerTakeover,
    ),
    buildLive: (boardH) => _HeroLiveLayer(
      channel: _heroLiveChannel,
      streamUrl: _heroLiveUrl,
      heroHeight: boardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      onPlayingChanged: _onHeroTrailerPlaying,
      onPlaybackFailed: _onHeroLivePlaybackFailed,
    ),
    buildScrims: (theater) => _CanvasScrims(
      theater: theater,
    ),
    readCaptionBand: () => _homeArtPosterCaptionBand,
    tabsHeight: _canvasTabsHeight,
    tabs: _canvasTabs,
    favouriteCell: _stageFavouriteCells.build,
    shelf: _stageShelf,
  );

  late final PromenadeStageBindings _promenadeBindings = (
    resolveRail: _resolveStageRail,
    seedFocus: _seedStageFocusOnce,
    favouriteCount: _canvasFavItemCount,
    readTheater: () => _canvasTheater,
    readTrailerActive: () => _heroTrailerActive,
    cacheWidth: () => _tvHeroArtworkCacheWidth,
    cacheHeight: () => _tvHeroArtworkCacheHeight,
    heroItem: _heroItem,
    enriched: _heroEnriched,
    favourite: _canvasFavFocus,
    trailerShowing: _heroTrailerShowing,
    buildTrailer: (boardH) => _HeroTrailerLayer(
      trailer: _heroTrailer,
      isTelevision: widget.isTelevision,
      heroHeight: boardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      loading: _heroTrailerLoading,
      onPlayingChanged: _onHeroTrailerPlaying,
      takeover: _heroTrailerTakeover,
    ),
    buildLive: (boardH) => _HeroLiveLayer(
      channel: _heroLiveChannel,
      streamUrl: _heroLiveUrl,
      heroHeight: boardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      onPlayingChanged: _onHeroTrailerPlaying,
      onPlaybackFailed: _onHeroLivePlaybackFailed,
    ),
    buildScrims: (theater) => _CanvasScrims(
      theater: theater,
      variant: _StageScrimVariant.centered,
    ),
    railBoxHeight: _stageRailBoxH,
    favouriteWidth: _stageFavW,
    labelHeight: _promenadeLabelHeight,
    railLabel: _promenadeLabel,
    favouriteCell: _stageFavouriteCells.build,
    cell: _promenadeCell,
  );

  late final MosaicStageBindings _mosaicBindings = (
    readTheme: () => AppThemeScope.of(context),
    resolveRail: _resolveStageRail,
    seedFocus: _seedStageFocusOnce,
    favouriteCount: _canvasFavItemCount,
    readAspect: () => _titleCardAspect,
    readCaptionBand: () => _homeArtPosterCaptionBand,
    cacheWidth: () => _tvHeroArtworkCacheWidth,
    cacheHeight: () => _tvHeroArtworkCacheHeight,
    heroItem: _heroItem,
    enriched: _heroEnriched,
    favourite: _canvasFavFocus,
    trailerShowing: _heroTrailerShowing,
    liveChannel: _heroLiveChannel,
    readTrailerActive: () => _heroTrailerActive,
    buildLive: (boardH) => _HeroLiveLayer(
      channel: _heroLiveChannel,
      streamUrl: _heroLiveUrl,
      heroHeight: boardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      onPlayingChanged: _onHeroTrailerPlaying,
      onPlaybackFailed: _onHeroLivePlaybackFailed,
    ),
    railLabel: _promenadeLabel,
    cell: _mosaicCell,
  );

  late final DeckStageBindings _deckBindings = (
    readTheme: () => AppThemeScope.of(context),
    resolveRail: _resolveStageRail,
    seedFocus: _seedStageFocusOnce,
    favouriteCount: _canvasFavItemCount,
    readTheater: () => _canvasTheater,
    readTrailerActive: () => _heroTrailerActive,
    cacheWidth: () => _tvHeroArtworkCacheWidth,
    cacheHeight: () => _tvHeroArtworkCacheHeight,
    column: _stageCol,
    favourite: _canvasFavFocus,
    heroItem: _heroItem,
    enriched: _heroEnriched,
    trailerShowing: _heroTrailerShowing,
    railBoxHeight: _stageRailBoxH,
    labelHeight: _atriumLabelHeight,
    favouriteWidth: _stageFavW,
    posterWidth: _stagePosterW,
    favouriteCell: _stageFavouriteCells.build,
    railLabel: _deckRailLabel,
    buildTrailer: (cardH) => _HeroTrailerLayer(
      trailer: _heroTrailer,
      isTelevision: widget.isTelevision,
      heroHeight: cardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      loading: _heroTrailerLoading,
      onPlayingChanged: _onHeroTrailerPlaying,
      takeover: _heroTrailerTakeover,
    ),
    buildLive: (cardH) => _HeroLiveLayer(
      channel: _heroLiveChannel,
      streamUrl: _heroLiveUrl,
      heroHeight: cardH,
      fullBleed: true,
      volume: _heroTrailerVolume,
      onPlayingChanged: _onHeroTrailerPlaying,
      onPlaybackFailed: _onHeroLivePlaybackFailed,
    ),
    shelf: _stageShelf,
  );

  // Eager Tonight lifetime at the former card-notifier construction slot.
  late final StageShelfContent _stageShelf = StageShelfContent(
    board: _boardRuntime,
    columns: _canvasCols,
    focusedColumn: _stageCol,
    bindings: (
      isBound: _isBound,
      pikpakOnly: () => _pikpakOnly,
      titleAspect: () => _titleCardAspect,
      titleArt: _titleArtUrl,
      setHero: _setHero,
      switchRail: _stageSwitchRail,
      quickPlay: _sectionQuickPlay,
      openItem: _sectionOpenItem,
      openCwMenu: _openCwCardMenu,
      railTitle: (view) => _canvasTabTitle(view.rails, view.index),
    ),
  );

  final TonightStageContent _tonight = TonightStageContent();

  /// The rails the ACTIVE layout puts on its rail zone. Identical to
  /// [_canvasRails] everywhere except Tonight, which lifts the Continue
  /// Watching rows out into its own vertical queue — leaving them in both
  /// places would mount the same FocusNodes twice.
  List<CanvasRail> get _stageRails => _homeStyleEffective == 'tonight'
      ? [
          for (final r in _canvasRails)
            if (r.cw == null) r,
        ]
      : _canvasRails;

  int _canvasFavItemCount(FavRowRef ref) => _boardRuntime.canvasFavItemCount(ref);

  String _canvasFavTitle(FavRowRef ref) {
    if (ref.isIptvList) return _favourites.iptvListRows[ref.list].title;
    switch (ref.kind) {
      case FavKind.watchlistMovies:
        return 'Watchlist Movies';
      case FavKind.watchlistSeries:
        return 'Watchlist Series';
      case FavKind.iptv:
        return 'IPTV Favorites';
      case FavKind.debrify:
        return 'Debrify TV';
      case FavKind.stremio:
        return 'Stremio TV';
      case FavKind.playlist:
        return 'Playlist';
    }
  }

  String _canvasRailTitle(CanvasRail rail) {
    if (rail.cw != null) return rail.cw!.title;
    if (rail.favKind != null) return _canvasFavTitle(rail.favKind!);
    return _sections[rail.sectionIndex!].title;
  }

  List<StremioMeta> _canvasRailItems(CanvasRail rail) =>
      rail.cw?.items ?? _sections[rail.sectionIndex!].items;

  List<FocusNode> _canvasRailNodes(CanvasRail rail) => _boardRuntime.canvasRailNodes(rail);

  /// UP/DOWN on the shelf: swap which rail the shelf shows — the screen never
  /// scrolls. DOWN past the last loaded rail pulls the next catalog batch;
  /// the new rail becomes reachable when it lands.
  void _stageSwitchRail(int delta) {
    final rails = _stageRails;
    if (rails.isEmpty) return;
    final current = _resolveCanvasRailIndex(rails);
    final next = (current + delta).clamp(0, rails.length - 1);
    if (next == current) {
      if (delta > 0 && _boardHasMore) {
        // Remember the move so it COMPLETES when the batch lands — otherwise
        // the keypress is silently eaten and the user has to press again.
        _deferStageAdvance(_canvasRailKeyOf(rails[current]));
        _loadMoreBoard();
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
  void _continueStageAdvance(String key, bool fillLower, FocusNode? origin) {
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
      _homeLandscapeCards ? wideArtUrl(item) : null;

  double _stagePosterW(double boxH) => boxH * _titleCardAspect;

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
  StageRailView? _resolveStageRail() {
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
    return StageRailView(
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


  /// One wide strip cell — the SAME [_BoardCell] every board uses, in a 16:9
  /// box with derived landscape art, so hold-OK menus, quick-play, paging and
  /// the focus grammar are identical to Canvas's shelf.
  Widget _promenadeCell(
    CanvasRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
  ) {
    final item = items[col];
    return BoardCell(
      item: item,
      isTelevision: true,
      focusNode: nodes[col],
      column: col,
      rowNodes: nodes,
      hasBoundSource: _isBound(item),
      ringColor: Colors.white,
      aspectRatio: 16 / 9,
      artUrl: wideArtUrl(item),
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
    StageRailView view, {
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


  /// One row of Atrium's wall: a quiet rail label over a horizontal strip of
  /// the SAME cells every other board uses.
  Text _atriumRailLabel(List<CanvasRail> rails, int index) {
    final app = AppThemeScope.of(context);
    return Text(
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
    );
  }

  AtriumStageFrame? _readAtriumFrame() {
    final app = AppThemeScope.of(context);
    final view = _resolveStageRail();
    if (view == null) return null;
    _seedStageFocusOnce();
    final rails = view.rails;
    final active = view.index;
    return AtriumStageFrame(
      app: app,
      minimumPosterHeight: _kStageMinPosterH,
      hasSecondRow: active + 1 < rails.length,
      wall: (
        label: (offset) => _atriumRailLabel(rails, active + offset),
        captionBand: () => _homeArtPosterCaptionBand,
        rowBoxHeight: _stageRailBoxH,
        row: (offset, height, label, {required isTopRow, required hasRowBelow}) =>
            _atriumRow(rails, active + offset, height,
                isTopRow: isTopRow, hasRowBelow: hasRowBelow, label: label),
      ),
      visuals: (
        backdrop: (boardH) => Stack(
                fit: StackFit.expand,
                children: [
                  CanvasArtLayer(
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
        dossier: (boardH, splitX) => Column(
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
                      ValueListenableBuilder<CanvasFavFocus?>(
                        valueListenable: _canvasFavFocus,
                        builder: (context, fav, _) => fav != null
                            ? StageFavIdentity(fav: fav)
                            : CanvasIdentity(
                                item: _heroItem,
                                enriched: _heroEnriched,
                                trailerShowing: _heroTrailerShowing,
                                // Drop the synopsis rather than clip it when
                                // the column is short (small board / large
                                // text scale).
                                variant:
                                    boardH - 64 >=
                                        stageNarrowIdentityH(context) + 90
                                    ? StageIdentityVariant.narrow
                                    : StageIdentityVariant.headline,
                                maxWidth: (splitX - atriumPanelPad * 2).clamp(
                                  120.0,
                                  520.0,
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _atriumRow(
    List<CanvasRail> rails,
    int index,
    double rowBoxH, {
    required bool isTopRow,
    required bool hasRowBelow,
    required Text label,
  }) {
    final rail = rails[index];
    final railKey = _canvasRailKeyOf(rail);
    final favRail = rail.favKind != null;
    final items = favRail ? const <StremioMeta>[] : _canvasRailItems(rail);
    final nodes = _canvasRailNodes(rail);
    final cardW = favRail
        ? _stageFavW(context, rowBoxH)
        : _stagePosterW(rowBoxH);
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
        label,
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
                      ? _stageFavouriteCells.build(
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
                          child: BoardCell(
                            item: items[col],
                            isTelevision: true,
                            focusNode: nodes[col],
                            column: col,
                            rowNodes: nodes,
                            hasBoundSource: _isBound(items[col]),
                            ringColor: Colors.white,
                            aspectRatio: _titleCardAspect,
                            artUrl: _titleArtUrl(items[col]),
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


  /// One wall cell. The grid overrides all four arrows: LEFT hands off to the
  /// sidebar only at a ROW edge (a grid's leftmost cell is not column 0, so
  /// the row grammar would leave the sidebar unreachable from every row but
  /// the first), and UP/DOWN step a whole row before falling through to rail
  /// switching.
  Widget _mosaicCell(
    CanvasRail rail,
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
      return _stageFavouriteCells.build(
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
      height: cellW / _titleCardAspect,
      child: BoardCell(
        item: item,
        isTelevision: true,
        focusNode: nodes[col],
        column: col,
        rowNodes: nodes,
        aspectRatio: _titleCardAspect,
        artUrl: _titleArtUrl(item),
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


  /// Deck's rail label — the same quiet caps as Atrium's rows, with the
  /// stacked chevron pair that says UP/DOWN changes rails.
  Widget _deckRailLabel(StageRailView view) =>
      _stageShelf.label(context, view);



  /// The shared poster shelf cell (Canvas grammar: L/R along the rail, U/D
  /// switches rails) — used by Deck and Tonight's bottom strip.


  Widget _tonightCardLayers(double cardH) => Stack(
    fit: StackFit.expand,
    children: [
      CanvasArtLayer(
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
              colors: [Color(0xF00A0810), Color(0xA00A0810), Color(0x000A0810)],
              stops: [0.0, 0.30, 0.68],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
      IgnorePointer(
        child: CustomPaint(
          painter: const CornerWedges(
            radius: kTonightCardRadius,
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
            info: _tonight.card,
          ),
        ),
      ),
    ],
  );

  /// Tab label for a rail, with colliding titles disambiguated by the
  /// section's provenance tag. Titles carry their content type themselves
  /// now ("Popular Movies" — [CatalogSection.rowTitle]), so the only way two
  /// tabs still collide is the same catalog name+type from two ADDONS — and
  /// the addon is exactly what tells those apart.
  String _canvasTabTitle(List<CanvasRail> rails, int i) {
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
  Widget _canvasTabs(List<CanvasRail> rails, int active) {
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

  // Callback aliases shared with existing stage parts; expire in G1'-8.
  void _setHero(StremioMeta item) => _hero.setHero(item);
  void _onHeroTrailerPlaying(bool playing) => _hero.onTrailerPlaying(playing);
  void _clearHeroTrailer() => _hero.clearTrailer();
  void _onHeroLivePlaybackFailed() => _hero.onLivePlaybackFailed();
  void _scheduleHeroTrailer(StremioMeta item, {bool fromSpotlight = false}) =>
      _hero.scheduleTrailer(item, fromSpotlight: fromSpotlight);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_heroTrailerActive) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => _hero.didPushNext();

  @override
  void didPopNext() {
    // A board reload UNDER a detail page/player can dispose the focused node;
    // the reclaim listener fires while covered and bails on route.isCurrent,
    // and no focus event re-fires it on the way back — re-run the dead check
    // now that the board is the top route again.
    _onGlobalFocusChange();
    _hero.didPopNext();
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
      case SearchBoardMode.keyword:
        unawaited(_keyword.run(q));
        return;
      case SearchBoardMode.catalog:
        if (q.isEmpty) {
          _restoreHome();
        } else {
          _runCatalogSearch(q);
        }
        return;
      case SearchBoardMode.lists:
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
    _keyword.clear();
    _disposeListsNodes();
    setState(() {
      _listsToken++; // cancel an in-flight lists search
      _listsQuery = '';
      _listsResults = const [];
      _listsSearching = false;
      _listsError = null;
    });
    _restoreHome();
  }

  void _completeSearchSubmitFocus(FocusNode target) => _content.completeSearchSubmitFocus(target);

  void _disposeListsNodes() => _content.disposeListsNodes();

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

  void _switchMode(SearchBoardMode mode) {
    // Belt for every entry point at once: the keyword surface is gated per
    // profile (catalog search never is).
    if (mode == SearchBoardMode.keyword &&
        !ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)) {
      return;
    }
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      // Leaving the keyword list drops any in-progress multi-selection.
      _keyword.kwSelectionMode = false;
      _keyword.kwSelected.clear();
    });
    // Carry the typed query across: if there's text in the box, run the target
    // mode's search immediately instead of showing the empty state.
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    switch (mode) {
      case SearchBoardMode.keyword:
        if (query != _keyword.kwQuery) unawaited(_keyword.run(query));
        return;
      case SearchBoardMode.catalog:
        if (query != _catalogQuery) _runCatalogSearch(query);
        return;
      case SearchBoardMode.lists:
        if (query != _listsQuery) _runListsSearch(query);
        return;
    }
  }

  // ── Playback / detail delegation ───────────────────────────────────────────

  /// Load the experimental merged-series-page flag once on init.
  Future<void> _loadMergedSeriesFlag() => _content.loadMergedSeriesFlag();

  void _openItem(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,


    String? heroTag,


    int? initialSeason,
    int? initialEpisode,


    int? returnToTabOnClose,
  }) => _content.actions.openItem(item, addon, isTraktSource: isTraktSource, isMdblistSource: isMdblistSource, heroTag: heroTag, initialSeason: initialSeason, initialEpisode: initialEpisode, returnToTabOnClose: returnToTabOnClose);

  /// Dispatch a detail-screen quick action. Reuses the shared
  /// [handleTraktMenuAction] for the standard actions and handles the
  /// Continue-Watching removal locally. The detail page stays underneath (like
  /// Play/Sources), so Back returns to it.

  /// Dispatch a detail-screen Simkl quick action — mirrors
  /// [_handleDetailQuickAction], simpler since Simkl's menu has no app
  /// actions (Select Source etc.) or Continue-Watching removal to special-case.


  /// "Select/Edit Source" entry: edit dialog when a source is already bound,
  /// otherwise the add-source picker.

  /// Manage bound sources. Body: [SourceBindingDialogs.showEdit].

  /// Add-source picker. Body: [SourceBindingDialogs.showAdd].



  /// Resolve a meta-capable addon (for episode listings): the preferred addon
  /// if it serves meta, otherwise the first enabled addon that does.


  // Catalog Play = auto-best in-tab; Sources = manual list in-tab. For a series
  // Play auto-plays the resume episode (last-played by imdbId → title, else
  // S01E01) — the Episodes button is the manual picker. Nothing jumps to Home.
  Future<void> _onCatalogPlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,




    bool skipEpisodeFallback = false,




    bool preferTraktResume = false,







    ({bool started, int season, int episode})? promisedTarget,




    bool browseSourcesOnly = false,
  }) => _content.actions.onCatalogPlay(item, addon, isTraktSource: isTraktSource, isMdblistSource: isMdblistSource, skipEpisodeFallback: skipEpisodeFallback, preferTraktResume: preferTraktResume, promisedTarget: promisedTarget, browseSourcesOnly: browseSourcesOnly);

  /// Read-only mirror of [_onCatalogPlay]'s resume resolution, used to label the
  /// detail screen's primary button. Forwarder — body lives on
  /// [CatalogPlayResolver.resolveResumeInfo].

  /// Play/browse selection. Resolve half is [CatalogPlayResolver.onCatalogBrowse];
  /// the host still opens episodes / the Sources page.


  /// Open the source picker (bind mode) to pin a source for [show]. For a series
  /// this searches season/complete packs (no episode), matching Home.

  /// Free-text keyword bind: push the sources screen seeded with a pack query
  /// (series → `name complete`, movie → `name year`), where tapping a result
  /// pins it as [show]'s bound source. The query is editable.

  /// Catalog auto-best play — the service picks the provider, shows the real
  /// cinematic overlay, searches, and plays (with source list + content
  /// metadata so the in-player Sources switcher + Continue Watching work).
  // Decision: this >10-line adapter retains State.context error timing and
  // listener try/finally. Remove with real G17/Q2 caller/lifecycle migration.

  /// Manual sources list in-tab — the screen searches itself (own loading) and
  /// each tap plays with the full source list + content metadata.
  // Decision: this >10-line adapter logs/guards before State.context. Remove
  // with real G17/Q2 caller migration; do not replace with an eager forwarder.

  void _snack(String message) => _content.actions.snack(message);

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
        child: (widget.isTelevision && !widget.searchMode)
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
    final show = _catalogSourcesBarShown && _mode == SearchBoardMode.catalog;
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
            _keyword.kwSourcesBtnFocus.requestFocus();
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
                      _keyword.kwSourcesBtnFocus.requestFocus();
                    } else if (_catalogSourcesButtonVisible) {
                      _catalogSourcesBtnFocus.requestFocus();
                    } else {
                      _focusContent();
                    }
                  }
                : null,
            decoration: InputDecoration(
              hintText: switch (_mode) {
                SearchBoardMode.catalog => 'Search or paste link',
                SearchBoardMode.keyword => 'Search torrents by keyword',
                SearchBoardMode.lists => 'Search MDBList lists',
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
    if (_mode == SearchBoardMode.keyword) {
      return KeywordSearchScreen(
        controller: _keyword,
        isTelevision: widget.isTelevision,
        onOpenStream: (context, torrent, sources, sourceIndex, searchKeyword) {
          unawaited(
            TorrentPlaybackService.activateTorrent(
              context,
              torrent,
              sources: sources,
              sourceIndex: sourceIndex,
              searchKeyword: searchKeyword,
            ),
          );
        },
        onBulkAdd: (context, torrents, keyword) =>
            TorrentBulkAddService.showBulkAddDialog(
              context,
              torrents: torrents,
              keyword: keyword,
            ),
        onOpenSources: () => showDialog<void>(
          context: context,
          builder: (_) => const KeywordSourcesDialog(),
        ),
        onFocusSearchField: _focusSearchFieldAtEnd,
        onFocusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
        onSnack: _snack,
      );
    }
    if (_mode == SearchBoardMode.lists) return _buildListsSearch();
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
      builder: (_) => const CatalogSourcesDialog(),
    );
    if (!mounted) return;
    if (_catalogQuery.isNotEmpty) {
      _runCatalogSearch(_catalogQuery);
    }
  }

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

  /// Apply fixed/remembered sources from local preferences immediately, then
  /// hydrate add-ons separately. Add-on defaults wait only for the inventory
  /// needed to validate them, and a source picked during that wait always wins.


  /// The Discover tab: a "Source" dropdown over a single browsable grid. Each
  /// source is rendered by the matching See-All panel in [embedded] mode (no
  /// Scaffold/back header), with the Source dropdown injected as its leading
  /// filter so DPAD walks Source → the panel's own filters → grid. All item
  /// open/play/bound wiring is this screen's existing board handlers.




  Widget _buildBoard() {
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
      );
    }
    final showCw = _cwVisible;
    // Don't fall through to the empty-state message while Trakt rows are being
    // reserved — the skeletons below are the board's content until the fetch
    // settles, and showing "No catalogs yet" first would flip to rows with the
    // exact reflow the reservation exists to prevent.
    if (_sections.isEmpty && !showCw && !_favourites.anyFavVisible && !_traktReserving) {
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
        return CanvasStage(bindings: _canvasBindings, isTelevision: widget.isTelevision);
      case 'atrium':
        return AtriumStage(readFrame: _readAtriumFrame, isTelevision: widget.isTelevision);
      case 'mosaic':
        return MosaicStage(bindings: _mosaicBindings, isTelevision: widget.isTelevision);
      case 'promenade':
        return PromenadeStage(bindings: _promenadeBindings, isTelevision: widget.isTelevision);
      case 'deck':
        return DeckStage(bindings: _deckBindings, isTelevision: widget.isTelevision);
      case 'tonight':
        return TonightStage(content: _tonight, isTelevision: widget.isTelevision);
      case 'spotlight':
        // The shared guard above lets dispatch through whenever ANY rail has
        // content — including favourites, which Spotlight still does not draw
        // (they are not `StremioMeta`). So test what this board will actually
        // render, not what the screen has: a stylish empty board is worse than
        // classic.
        if (_spotlightShelves.every((s) => s.items.isEmpty)) break;
        return SpotlightStage(readFrame: () {
          // Keep the original child-build timing and paging rail snapshot.
          final rails = _canvasRails;
          return (
            rails: rails,
            boardKey: _spotlightKey,
            hero: _spotlightHero,
            sections: _spotlightShelves,
            heroNode: _spotlightHeroNode,
            heroAddon: _spotlightHeroSection?.addon,
            dpad: widget.isTelevision,
            showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
            onHeroOpen: _openItem,
            board: _boardRuntime,
            trailersEnabled: _heroTrailerEnabled,
            onDwell: (StremioMeta item) =>
                _scheduleHeroTrailer(item, fromSpotlight: true),
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
        });
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
            // via MainPageBridge (see _hero.publishAmbientArt).
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
                            return HeroSpotlight(
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
                                        : _hero.derivedLogo(item)),
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
                              // in the region (see _hero.scheduleTrailer).
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
                              // them (see [HeroSpotlight.liveTakeover]).
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
                              : const <CanvasRail>[];
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
                                row = _buildHomeRail(rail, rowId);
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
                  onPlaybackFailed: _hero.onLivePlaybackFailed,
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
    if (widget.searchMode) return child;
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
        cwProgress: _cw.cwCardMaps(CwKind.trakt).progress,
        onOpen: _cw.openTrakt,
        onQuickPlay: _pikpakOnly ? null : _cw.playTrakt,
        isBound: _isBound,
        isTelevision: widget.isTelevision,
      );
    } else if (section.isMdblist) {
      screen = MdblistSeeAllScreen(
        initialList: section.mdblistList,
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
        cwOnOpen: _cw.openSimkl,
        cwOnQuickPlay: _pikpakOnly ? null : _cw.playSimkl,
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
  void _markPlaybackStarted() => _content.markPlaybackStarted();

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
  Future<void> _refreshAfterPlayback({bool trackers = false}) => _content.refreshAfterPlayback(trackers: trackers);

  /// Playback ran in a separate ACTIVITY and the app just came back (see
  /// [MainPageBridge.notifyPlaybackReturned]). Only refresh when the board is
  /// the top route: with a detail page or See-All open on top, THAT screen owns
  /// the refresh and the board re-reads through the covering route's `.then`
  /// when it pops — so this can't double up with it. The latch survives until
  /// then, so the deferred refresh still knows playback happened.
  void _onPlaybackReturned() => _content.onPlaybackReturned();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (!_cw.maybeRefreshTraktOnResume(
      searchMode: widget.searchMode,
      isTraktAuthenticated: _isTraktAuthenticated,
      playedSinceRefresh: _playedSinceRefresh,
      routeIsCurrent: ModalRoute.of(context)?.isCurrent ?? false,
    )) {
      return;
    }
    unawaited(_loadTraktContinueWatching());
  }

  /// Refresh state that a See-All screen may have changed (Continue Watching
  /// progress/removal, bound sources) when it pops back to the board — plus the
  /// tracker rows when the user played something from the grid.
  Future<void> _afterSeeAllReturn() => _content.afterSeeAllReturn();

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

  /// Registry-driven dispatch for a canonical Home rail. Skeleton placeholders
  /// keep their dedicated builder; live rails follow [HomeRowFamily.boardSlot].
  Widget _buildHomeRail(CanvasRail rail, String rowId) {
    if (rail.traktSkeletonIndex >= 0) {
      return _buildTraktSkeletonRow(rail.traktSkeletonIndex);
    }
    final slot = HomeRowRegistry.instance.familyFor(rowId)?.boardSlot;
    switch (slot) {
      case HomeBoardSlot.continueWatching:
        return _buildContinueWatchingRow(rail.cw!, rail.cwIndex, rowId);
      case HomeBoardSlot.favourites:
        return _buildFavRow(rail.favKind!, rowId);
      case HomeBoardSlot.section:
        return _buildRow(rail.sectionIndex!, homeRowId: rowId);
      case null:
        if (rail.cw != null) {
          return _buildContinueWatchingRow(rail.cw!, rail.cwIndex, rowId);
        }
        if (rail.favKind != null) {
          return _buildFavRow(rail.favKind!, rowId);
        }
        return _buildRow(rail.sectionIndex!, homeRowId: rowId);
    }
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
                    ? (_favourites.anyFavVisible
                          ? () => _favourites.focusFavRowAt(_favourites.favRowCount - 1, col)
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
                          _boardRuntime.deferDownMove(rowIndex: rowIndex, column: col);
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
                          child: BoardCell(
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

  Widget _buildContinueWatchingRow(CwRow row, int cwIndex, String homeRowId) {
    final tv = widget.isTelevision;
    final posterW = _railTitleCardW(context);
    final cellH = _railTitleCardH(context);
    return ContinueWatchingRow(
      row: row,
      cwIndex: cwIndex,
      homeRowId: homeRowId,
      isTelevision: tv,
      posterW: posterW,
      cellH: cellH,
      header: _railHeader(title: row.title, tag: row.tag, onSeeAll: row.onSeeAll),
      cellBuilder: (context, col, item, node, nodes) => BoardCell(
        item: item,
        isTelevision: tv,
        focusNode: node,
        column: col,
        rowNodes: nodes,
        hasBoundSource: _isBound(item),
        showWatchedBadge: false,
        aspectRatio: _titleCardAspect,
        artUrl: _titleArtUrl(item),
        showTitleOverlay: !_hideHomeCardTitlesAndRatings,
        progress: row.progressOf(item),
        episodeLabel: row.episodeOf(item),
        onLongPress: () => _openCwCardMenu(row, item, cwIndex, col),
        onFocused: () => _setHero(item),
        onUp: () => _focusRelativeHomeRail(homeRowId, -1, col),
        onDown: () => _focusRelativeHomeRail(homeRowId, 1, col),
        onOpen: () => row.onOpen(item),
      ),
    );
  }

  Widget _buildTraktSkeletonRow(int idx) {
    final posterW = _railTitleCardW(context);
    final cellH = _railTitleCardH(context);
    return TraktSkeletonRow(
      header: _railHeader(
        title: 'Trakt Continue Watching',
        tag: idx == 0 ? (_cwMergeTrakt ? null : 'Movies') : 'Shows',
      ),
      posterW: posterW,
      cellH: cellH,
      rowH: cellH + 14,
    );
  }

  /// Dispatch to the right favourites-row builder for [ref].
  Widget _buildFavRow(FavRowRef ref, String homeRowId) => FavRow(
    controller: _favourites,
    hostContext: context,
    ref: ref,
    homeRowId: homeRowId,
    isTelevision: widget.isTelevision,
    hideTitles: _hideHomeCardTitlesAndRatings,
    posterW: _railPosterW(context),
    captionBand: _homeArtPosterCaptionBand,
    onUp: _favourites.favRowOnUp,
    onDown: _favourites.favRowOnDown,
    clearHero: _hero.clearLiveIptv,
    setLiveHero: _hero.setLiveIptv,
    tag: (title, {icon}) => _CategoryTag(title, icon: icon),
  );

  Widget _message(IconData icon, String title, String body) {
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
          ],
        ),
      ),
    );
  }
}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
