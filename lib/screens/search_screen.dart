import '../ui/core/retry_message.dart';
import '../features/home/presentation/home_board_content.dart';
import '../features/search/presentation/search_focus_controller.dart';
import '../features/search/presentation/keyword_focus_controller.dart';
import '../features/search/presentation/keyword_source_tabs.dart';
import '../features/search/presentation/keyword_search_page.dart';
import '../features/search/presentation/keyword_results_list.dart';
import '../features/search/presentation/keyword_toolbar.dart';
import '../features/search/presentation/keyword_selection_overlay.dart';
import '../features/search/presentation/search_header.dart';
import '../features/search/presentation/search_query_field.dart';
import '../features/home/application/home_detail_action_dependencies.dart';
import '../features/home/application/home_detail_dependencies.dart';
import '../features/home/presentation/home_detail_menus.dart';
import '../features/home/presentation/home_detail_presentation.dart';
import '../features/home/presentation/home_catalog_play_action.dart';
import '../features/home/presentation/home_detail_route.dart';
import '../features/home/application/home_simkl_continuation_dependencies.dart';
import '../features/home/application/home_iptv_continuation_dependencies.dart';
import '../features/home/application/home_catalog_playback_resolver_dependencies.dart';
import '../models/simkl_continue_watching_item.dart';
import '../features/home/presentation/home_detail_action_bridge.dart';
import '../features/home/presentation/home_source_editor.dart';
import '../features/home/application/home_source_editing_dependencies.dart';
import '../features/sources/presentation/local_source_picker_composition.dart';
import '../features/home/application/home_local_history_removal_dependencies.dart';
import '../features/home/presentation/home_continuation_row.dart';
import '../features/home/presentation/home_catalog_row.dart';
import '../features/home/presentation/home_catalog_row_header.dart';
import '../features/home/presentation/home_favorite_row.dart';
import '../features/home/application/home_post_playback_refresh_controller.dart';
import '../features/discover/presentation/discover_panels.dart';
import '../features/discover/presentation/discover_content.dart';
import '../features/discover/application/discover_card_settings_controller.dart';
import '../features/discover/models/discover_card_settings.dart';
import '../features/discover/application/discover_layout_controller.dart';
import '../features/discover/presentation/discover_preview.dart';
import '../features/home/presentation/home_stage_theater.dart';
import '../features/home/presentation/home_hero_shell_bridge.dart';
import '../features/home/application/home_hero_tint_loader.dart';
import '../features/home/application/home_hero_tint_dependencies.dart';
import '../features/home/presentation/home_hero_swap.dart';
import '../features/home/presentation/home_hero_spotlight.dart';
import '../features/home/presentation/home_classic_hero.dart';
import '../features/home/presentation/spotlight_iptv_card_preview.dart';
export '../features/home/presentation/spotlight_iptv_card_preview.dart' show SpotlightIptvCardPreview;
import '../features/home/presentation/home_hero_trailer_layer.dart';
import '../features/home/presentation/home_hero_trailer_indicators.dart';
import '../features/home/presentation/home_spotlight_search_button.dart';
import '../features/home/presentation/home_hero_live_layer.dart';
import '../features/home/presentation/home_stage_rail_label.dart';
import '../features/home/presentation/home_promenade_layout.dart';
import '../features/home/presentation/home_atrium_layout.dart';
import '../features/home/presentation/home_atrium_row.dart';
import '../features/home/presentation/home_mosaic_layout.dart';
import '../features/home/presentation/home_deck_layout.dart';
import '../features/home/presentation/home_deck_peeks.dart';
import '../features/home/presentation/home_stage_row_label.dart';
import '../features/home/presentation/home_tonight_layout.dart';
import '../features/home/presentation/home_tonight_header.dart';
import '../features/home/presentation/home_tonight_queue_list.dart';
import '../features/home/presentation/home_tonight_rail.dart';
import '../features/home/presentation/home_stage_hold_latch.dart';
import '../features/home/presentation/home_stage_focus_requests.dart';
import '../features/home/presentation/home_stage_deferred_right.dart';
import '../features/home/presentation/home_stage_deferred_advance.dart';
import '../features/home/presentation/home_hero_preview_policy.dart';
import '../features/home/presentation/home_canvas_tabs.dart';
import '../features/home/presentation/home_canvas_shelf.dart';
import '../features/home/presentation/home_canvas_layout.dart';
import '../features/home/presentation/home_stage_favorite_identity.dart';
import '../widgets/skeleton_poster.dart' show BrandLoadingStage;
import '../features/home/presentation/home_trakt_skeleton_row.dart';
import '../features/home/presentation/home_stage_rows.dart';
import '../features/home/presentation/home_stage_identity.dart';
import '../features/home/presentation/home_stage_art.dart';
import '../features/home/presentation/home_tonight_queue_row.dart';
import '../features/home/presentation/home_tonight_card_caption.dart';
import '../features/home/presentation/home_favorite_focus.dart';
import '../features/home/models/home_tonight_card_info.dart';
import '../features/home/application/home_stage_metadata.dart';
import '../features/home/application/home_hero_metadata_policy.dart';
import '../features/home/application/home_hero_metadata_loader.dart';
import '../features/home/application/home_hero_metadata_dependencies.dart';
import '../features/home/application/home_hero_trailer_dependencies.dart';
import '../features/home/application/home_hero_trailer_loader.dart';
import '../features/home/application/home_hero_live_preview.dart';
import '../features/home/application/home_hero_live_dependencies.dart';
import '../features/home/presentation/home_classic_layout.dart';
import '../features/home/presentation/home_takeover_info.dart';
import '../features/home/presentation/home_trailer_transitions.dart';
import '../features/home/presentation/home_classic_rows.dart';
import '../features/home/presentation/home_board_cell.dart';
import '../features/home/models/home_favorite_row_ref.dart';
import '../features/home/presentation/home_favorite_cell.dart';
import '../features/home/presentation/home_art_poster.dart';
import '../features/home/presentation/home_card_style.dart';
import '../features/discover/application/discover_source_controller.dart';
import '../features/discover/models/discover_source_state.dart';
import '../features/discover/application/metadata_feature_controller.dart';
import '../features/discover/models/metadata_feature_policy.dart';
import '../features/home/application/home_episode_artwork_controller.dart';
import '../features/home/models/home_episode_artwork.dart';
import '../features/home/models/home_tracker_authentication.dart';
import '../features/home/application/home_tracker_authentication_controller.dart';
import '../features/home/models/home_return_snapshot.dart';
import '../features/home/data/home_return_repository.dart';
import '../features/home/application/home_return_dependencies.dart';
import '../features/home/application/home_pikpak_only_controller.dart';
import '../features/home/application/home_bound_counts_controller.dart';
import '../features/home/application/home_configuration_changes.dart';
import '../features/home/application/home_settings_refresh.dart';
import '../features/home/application/home_settings_refresh_dependencies.dart';
import '../features/home/application/home_layout_preference.dart';
import '../features/home/application/home_layout_preference_dependencies.dart';
import '../models/source_appearance.dart';
import '../features/search/application/keyword_appearance_controller.dart';
import '../features/home/application/home_trailer_preferences_controller.dart';
import '../features/home/models/home_trailer_preferences.dart';
import '../features/home/application/home_default_view.dart';
import '../features/home/application/home_default_view_dependencies.dart';
import '../features/home/application/home_display_preferences_controller.dart';
import '../features/home/models/home_display_preferences.dart';
import '../features/home/presentation/home_progress_publication.dart';
import '../features/home/application/home_playlist_controller.dart';
import '../features/home/models/home_playlist.dart';
import '../features/home/application/home_watchlist_controller.dart';
import '../features/home/models/home_watchlist.dart';
import '../features/home/application/home_iptv_lists_controller.dart';
import '../features/home/models/home_iptv_list.dart';
import '../features/home/presentation/home_iptv_list_focus.dart';
import '../features/home/application/home_iptv_favorites_controller.dart';
import '../features/home/application/home_stremio_favorites_controller.dart';
import '../features/home/models/home_stremio_favorites.dart';
import '../features/home/application/home_tv_favorites_controller.dart';
import '../features/home/application/home_mdblist_continuation_controller.dart';
import '../features/home/models/home_mdblist_continuation.dart';
import '../features/home/application/home_simkl_continuation_controller.dart';
import '../features/home/models/home_simkl_continuation.dart';
import '../features/home/presentation/home_progress_view.dart';
import '../features/home/application/home_trakt_continuation_controller.dart';
import '../features/home/models/home_trakt_continuation_state.dart';
import '../features/home/models/home_trakt_continuation.dart';
import '../features/home/application/home_continuation_layout_controller.dart';
import '../features/home/models/home_continuation_layout.dart';
import '../features/home/application/home_iptv_continuation_controller.dart';
import '../features/home/models/home_iptv_continuation_state.dart';
import '../features/home/application/home_local_continuation_controller.dart';
import '../features/home/models/home_continuation_session.dart';
import '../features/home/models/home_local_continuation_state.dart';
import '../features/home/application/home_row_snapshot.dart';
import '../features/home/application/home_board_load.dart';
import '../features/home/application/home_board_dependencies.dart';
import '../features/home/models/home_board_configuration.dart';
import '../features/home/application/home_collections_dependencies.dart';
import '../features/home/application/home_configuration_refresh.dart';
import '../features/home/data/home_collections_repository.dart';
import '../features/home/models/home_catalog_preferences.dart';
import '../features/home/models/home_catalog_session.dart';
import '../features/home/application/home_catalog_controller.dart';
import '../features/home/application/home_catalog_continuation_controller.dart';
import '../features/home/models/home_catalog_state.dart';
import '../features/home/models/home_catalog_plan.dart';
import '../features/home/application/home_catalog_preferences_dependencies.dart';
import '../features/home/presentation/home_sources_navigation.dart';
import '../features/search/application/keyword_snapshot_dependencies.dart';
import '../features/search/data/keyword_snapshot_repository.dart';
import '../features/search/models/keyword_snapshot.dart';
import '../features/search/presentation/keyword_providers_dialog.dart';
import '../features/search/application/keyword_result_snapshot.dart';
import '../features/search/application/keyword_results_controller.dart';
import '../features/search/models/keyword_results_state.dart';
import '../features/search/application/keyword_search_controller.dart';
import '../features/search/models/keyword_search_state.dart';
import '../features/search/application/keyword_cache_controller.dart';
import '../features/search/models/keyword_cache_state.dart';
import '../features/search/presentation/keyword_sources_dialog.dart';
import '../features/search/presentation/catalog_sources_dialog.dart';
import '../features/search/application/catalog_search_controller.dart';
import '../features/search/models/catalog_search_state.dart';
import '../features/search/presentation/catalog_search_projection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/search/application/lists_search_controller.dart';
import '../features/search/models/search_session.dart';
import '../features/search/models/lists_search_state.dart';
import '../features/search/models/search_mode.dart';
import '../features/search/presentation/search_mode_toggle.dart';
import '../features/home/presentation/category_tag.dart';
import '../features/search/application/keyword_providers.dart';
import '../services/native_series_metadata_service.dart';
import '../models/media_identity.dart';
import '../features/home/presentation/home_random_playback_action.dart';
import '../features/home/presentation/home_detail_navigation.dart';
import '../features/home/application/home_random_episode_dependencies.dart';
import '../features/home/application/home_catalog_episode_identity_dependencies.dart';
import '../features/home/application/home_catalog_origin_dependencies.dart';
import '../features/home/application/home_tracking_policy_dependencies.dart';
import '../features/home/application/home_tracker_resume_dependencies.dart';
import '../features/home/data/home_tracker_resume_repository.dart';
import '../features/home/data/home_catalog_playback_payload.dart';
import '../features/home/presentation/home_catalog_playback_bridge.dart';
import '../services/profiles/profile_runtime.dart';
import '../models/metadata_preferences.dart';
import '../services/metadata_preferences_service.dart';
import '../widgets/see_all/discover_browsing_input.dart';
import '../services/home_load_deadline.dart';
import '../services/home_load_progress.dart';
import '../widgets/home/home_row_focus.dart';
import '../widgets/home/home_continuation_focus.dart';
import '../features/home/presentation/home_board_frame.dart';
import '../services/home_row_refresh.dart';
import '../services/profiles/connection_resource_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/material.dart';
import '../models/custom_series_identity.dart';
import 'package:flutter/services.dart';

import '../models/advanced_search_selection.dart';
import '../theme/app_theme_scope.dart';
import '../features/home/presentation/home_classic_row_metrics.dart';
import '../utils/platform_util.dart';
import '../utils/tvos_device.dart';
import '../models/debrify_tv/channel.dart';
import '../models/home_collection.dart';
import '../models/iptv_playlist.dart';
import '../features/home/presentation/home_playback_artwork.dart';
import '../models/playlist_view_mode.dart';
import '../models/stremio_addon.dart';
import '../models/stremio_tv/stremio_tv_now_playing.dart';
import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/analytics_service.dart';
import '../services/home_collection_rows.dart';
import '../services/home_collections_store.dart';
import '../services/home_list_rows.dart';
import '../services/home_row_order.dart';
import '../services/filtered_catalog_pager.dart';
import '../services/hide_watched_prefs.dart';
import '../services/watched_filter.dart';
import '../services/iptv_cw_router.dart';
import '../services/iptv_media_store.dart';
import '../services/main_page_bridge.dart';
import '../models/profiles/profile_policy.dart';
import '../services/profiles/profile_policy_guard.dart';
import '../services/playlist_player_service.dart';
import '../services/profiles/profile_session_memory.dart';
import '../services/stremio_iptv_service.dart';
import '../services/stremio_service.dart';
import '../services/storage_service.dart';
import '../services/tv_hero_artwork_quality_controller.dart';
import '../services/tvos_top_shelf_service.dart';
import '../services/torrent_bulk_add_service.dart';
import '../services/torrent_playback_service.dart';
import '../models/trakt_continue_watching_item.dart';
import '../features/home/application/home_trakt_continuation_dependencies.dart';
import '../services/video_player_launcher.dart';
import '../services/tracking_source_policy.dart';
import '../utils/continue_watching_presentation.dart';
import '../utils/dialog_tap_guard.dart';
import '../features/home/data/home_series_resume_resolver.dart';
import '../features/home/application/home_series_resume_resolver_dependencies.dart';
import '../features/home/models/home_series_resume_signals.dart';
import '../features/home/data/home_series_resume_repository.dart';
import '../features/home/application/home_series_resume_dependencies.dart';
import '../utils/tv_keys.dart';
import '../utils/tv_search_focus_handoff.dart';
import '../services/youtube_service.dart';
import '../widgets/debrid_action_sheet.dart';
import '../features/home/presentation/home_continue_watching_actions.dart';
import '../features/home/application/home_cw_hold_preference.dart';
import '../widgets/home/card_focus_rise.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/home/spotlight_board.dart';
import '../widgets/home/spotlight_catalog_card_cache.dart';
import '../widgets/cinema_sources_layout.dart';
import '../widgets/torrent_filters_sheet.dart';
import '../widgets/text_field_suggestions.dart';
import '../widgets/metadata_title_navigation.dart';
import '../services/tmdb_title_search.dart';
import '../services/metadata_title_service.dart';
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
import '../models/mdblist_continue_watching.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../widgets/see_all/discover_card_settings_scope.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../features/home/application/home_layout_policy.dart';
import 'episodes_screen.dart';
import 'stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';


/// TV focus ring for board cards — violet-300, deliberately LIGHTER than the
/// board's chrome accent: a light ring over dark art pops at 10ft, while the
/// deep accent stays for chrome (tags, sidebar). Pairs with the calm 1.045
/// scale. (The old kStremioAccent/kStremioBg palette constants now live in
/// the app theme as `app.home.chromeAccent` / `app.home.bg`.)
const Color kStremioFocusRing = kCardFocusRing;

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch as
/// the user scrolls, and how many items to keep per row. Enumerating catalogs is
/// free (manifest metadata) — only fetching each row's items costs a call — so we
/// list every catalog up front and lazily pull batches on scroll (Stremio-style)
/// instead of a hard global row cap.
const int _kBoardBatchSize = 8;

/// Dedicated Search tab.
///
/// * CATALOG mode — a Stremio-style board (one horizontal row per addon
///   catalog) with a hero spotlight that reflects the focused title; submitting a
///   query searches every searchable addon and shows one horizontal row of
///   results per addon (same board layout).
/// * KEYWORD mode — raw torrent search → tap a result to add/play.
/// * LISTS mode — MDBList public-list search, isolated from title catalogs.
/// Catalog offers TMDB title suggestions while typing on the
/// dedicated Search tab. Selecting a title opens its existing detail flow.
///
/// All playback (catalog auto-best, sources list, keyword) runs in-tab through
/// the isolated [TorrentPlaybackService]; the Home engine is never invoked.
class SearchScreen extends ConsumerStatefulWidget {
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

  @visibleForTesting
  final TmdbTitleSearch? titleSearch;

  @visibleForTesting
  final Future<StremioMeta> Function(StremioMeta)? suggestedTitleResolver;

  const SearchScreen({
    super.key,
    this.isTelevision = false,
    this.searchMode = false,
    this.discoverMode = false,
    this.titleSearch,
    this.suggestedTitleResolver,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// Fixed Discover sources; installed addons are appended dynamically (key
/// 'a:{addonId}').
const String _discCw = DiscoverSources.cw;
const String _discTmdb = DiscoverSources.tmdb;
const String _discJellyfin = DiscoverSources.jellyfin;
const String _discEmby = DiscoverSources.emby;
const String _discMdblist = DiscoverSources.mdblist;

/// Smallest poster art a stage rail will draw before it is simply too small
/// to recognise — the floor every derived rail box respects.
const double _kStageMinPosterH = 56;

// ATRIUM metrics. The wall's height is DERIVED from these (never guessed),
// so the dossier column beside it can't be crowded by a taller row.
const double _kAtriumSplit = 0.38;
const double _kAtriumLabelGap = 10;

/// The share of the board Atrium's two-row wall may occupy. The row box is
/// derived from what fits inside this, so scaled labels shrink the posters
/// rather than pushing the wall off the bottom.
const double _kAtriumWallBudget = 0.64;

double _atriumLabelHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(homeStageRowLabelFontSize) * 1.35;

/// Dim painted over every strip cell that isn't focused, so the centre-locked
/// cell reads as the lit one. A flat fill inside the card's own clip (see
/// [CardFocusRise.restVeil]) — no Opacity, no saveLayer.
const Color _kPromRestVeil = Color(0x8C0D0B1A);

class _SearchScreenState extends ConsumerState<SearchScreen>
    with RouteAware, WidgetsBindingObserver {
  // Which nav tab this instance backs, for the TV content-focus handler: the
  // dedicated Search tab (17) or the Home-New board (15).
  int get _tabIndex => widget.searchMode ? 17 : (widget.discoverMode ? 18 : 15);

  final StremioService _stremio = StremioService.instance;
  late final HomeCollectionsRepository _homeCollectionsRepository;

  final TextEditingController _searchController = TextEditingController();
  late final _titleSearch = widget.titleSearch ?? TmdbTitleSearch();
  final _titleSuggestions = ValueNotifier<List<TextFieldSuggestion>>(const []);
  final _titleSearchScope = ProfileRuntime.scope.value;
  bool _openingSuggestedTitle = false;
  int _suggestedTitleOpenGeneration = 0;
  bool get _titleSearchPolicyReady => _metadataFeatureController.current.ready;
  String _titleSearchText = '';
  bool _titleSearchComposing = false;
  late final _searchFocus = SearchFocusController(
    onSourcesVisibilityChanged: () {
      if (mounted) setState(() {});
    },
  );
  FocusNode get _searchFocusNode => _searchFocus.field;
  final TvSearchFocusHandoff _searchSubmitFocus = TvSearchFocusHandoff();
  // DPAD focus targets for the Catalog / Keyword / Lists selector, so the
  // toggle is reachable with a remote (arrow-up from the search field).
  FocusNode get _modeCatalogNode => _searchFocus.catalog;
  FocusNode get _modeKeywordNode => _searchFocus.keyword;
  FocusNode get _modeListsNode => _searchFocus.lists;
  FocusNode get _modeDropdownNode => _searchFocus.dropdown;

  // Dedicated MDBList list-search state. Lists is its own Search mode; it
  // never runs as part of Catalog search. Each result card hands off via
  // MainPageBridge.pendingMdblistListOpen. One focus node per card.
  late final SearchSession _searchSession;
  late final ProviderSubscription<ListsSearchState> _listsSubscription;
  ListsSearchState get _listsState => _listsSubscription.read();
  ListsSearchController get _listsController =>
      ref.read(listsSearchProvider(_searchSession).notifier);
  String get _listsQuery => _listsState.query;
  List<MdblistListChoice> get _listsResults => _listsState.results;
  bool get _listsSearching => _listsState.searching;
  String? get _listsError => _listsState.error;
  final List<FocusNode> _listsNodes = [];
  // Debounce for opening a list from the rail — one fast double-press must not
  // stack two pushed item screens (TV) / double-fire the handoff.
  DateTime? _lastListOpenAt;

  SearchMode _mode = SearchMode.catalog;

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  late final ProviderSubscription<CatalogSearchState> _catalogSubscription;
  CatalogSearchState get _catalogState => _catalogSubscription.read();
  CatalogSearchController get _catalogController =>
      ref.read(catalogSearchProvider(_searchSession).notifier);
  String get _catalogQuery => _catalogState.query;
  Timer? _catalogDebounce;

  /// The addon that produced the item currently being played/browsed, threaded
  /// into playback so Continue Watching can route resume / next-episode back to
  /// it (matching Home's `addonId`). Set whenever we open a catalog item.
  String? _activeAddonId;

  // Keyword torrent-search state (submit-based).
  late final ProviderSubscription<KeywordSearchState> _keywordSearchSubscription;
  KeywordSearchController get _keywordSearchController =>
      ref.read(keywordSearchProvider(_searchSession).notifier);
  KeywordSearchState get _keywordSearchState => _keywordSearchSubscription.read();
  bool get _kwLoading => _keywordSearchState.loading;
  String? get _kwError => _keywordSearchState.error;
  String get _kwQuery => _keywordSearchState.query;
  late final ProviderSubscription<KeywordResultsState> _keywordResultsSubscription;
  KeywordResultsController get _keywordResultsController =>
      ref.read(keywordResultsProvider(_searchSession).notifier);
  KeywordResultsState get _keywordResults => _keywordResultsSubscription.read();
  List<Torrent> get _kwAll => _keywordResults.all;
  List<Torrent> get _kwResults => _keywordResults.results;
  late final _keywordFocus = KeywordFocusController(
    focusSearch: _focusSearchFieldAtEnd,
    focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
    focusAboveToolbar: _focusAboveKeywordToolbar,
    hasAccessibleArrivals: () => _kwPendingNewCount > 0 && !_kwSelectionMode,
  );
  List<FocusNode> get _kwNodes => _keywordFocus.rows;
  final _kwCinemaKey = GlobalKey<CinemaSourcesLayoutState>();
  int _lastKeywordCinemaSource = 0;
  // Keyboard/DPAD focus targets for the keyword toolbar pills (Sort / Filters /
  // Providers / Sources / Select). A fixed pool of 5 covers the most pills ever
  // shown.
  List<FocusNode> get _kwToolbarNodes => _keywordFocus.toolbar;
  TorrentFilterState get _kwFilters => _keywordResults.filters;
  String get _kwSort => _keywordResults.sort;
  // Sort direction for _kwSort (ignored for 'relevance', which is engine order).
  // Defaults follow each field's natural direction; the sort dialog can flip it.
  bool get _kwSortAsc => _keywordResults.sortAscending;
  late final ProviderSubscription<KeywordCacheState> _keywordCacheSubscription;
  KeywordCacheController get _keywordCacheController =>
      ref.read(keywordCacheProvider(_searchSession).notifier);
  Map<String, List<String>> get _kwCache => _keywordCacheSubscription.read().badges;

  // Provider (stream-type) multi-select filter, ported from the old search
  // screen: results are grouped into "Direct" (direct/external URL streams) and
  // "Torrent" providers by their [Torrent.source], each independently filterable
  // by which sources are ticked. Empty count maps mean "no such group".
  Map<String, int> get _kwDirectCounts => _keywordResults.providers.directCounts;
  Map<String, int> get _kwTorrentCounts => _keywordResults.providers.torrentCounts;
  Set<String> get _kwSelectedDirect => _keywordResults.providers.selectedDirect;
  Set<String> get _kwSelectedTorrent =>
      _keywordResults.providers.selectedTorrent;

  /// True when the results list is being narrowed to TorBox-cached torrents
  /// only (TorBox is the sole usable debrid provider and its cache-check is on)
  /// — mirrors the old screen's `_showingTorboxCachedOnly`. Drives the banner.
  bool get _kwCachedOnly => _keywordCacheSubscription.read().cachedOnly;

  // Bulk-selection state for keyword results (mirrors Home's multi-select).
  bool get _kwSelectionMode => _keywordResults.selectionMode;
  Set<String> get _kwSelected => _keywordResults.selected;

  int get _kwSearchToken => _keywordSearchState.request;
  bool get _kwSearching => _keywordSearchState.searching;

  /// Set on the first real user interaction (scroll drag, row DPAD nav, row
  /// tap/long-press, toolbar use) — later arrivals then park in [_kwPending]
  /// behind the "+N new results" pill instead of reshuffling the list.
  bool get _kwStreamFrozen => _keywordResults.frozen;

  /// Full (unfiltered) result set parked while frozen; adopted by the pill,
  /// any toolbar action, or a source-tab tap.
  List<Torrent>? get _kwPending => _keywordResults.pending;

  /// DPAD focus for the "+N new results" pill.
  FocusNode get _kwPillFocus => _keywordFocus.arrivals;

  /// DPAD focus for the pre-search "Sources" button (shown in the empty
  /// keyword state before a query). Without its own node it's a bare InkWell
  /// unreachable by the remote — you couldn't pick sources before searching.
  FocusNode get _kwSourcesBtnFocus => _keywordFocus.sources;

  /// DPAD focus for the catalog-mode "Sources" button (empty-prompt state) —
  /// its keyword-mode twin, for picking which searchable addons are queried.
  final FocusNode _catalogSourcesBtnFocus = FocusNode(
    debugLabel: 'catalog_sources_btn',
  );

  /// Whether the unified (non-TV) catalog Sources bar under the field is shown.
  /// Driven by search-field focus with a delayed hide (see
  /// [_onSearchFocusForSources]) so a click on the button isn't lost.
  bool get _catalogSourcesBarShown => _searchFocus.sourcesVisible;

  /// Source tab strip (All / per-source), single-select on top of the
  /// Providers multi-select. Null = All.
  String? get _kwSourceTab => _keywordResults.sourceTab;
  List<FocusNode> get _kwTabNodes => _keywordFocus.tabs;

  /// Scroll controller for the keyword results list, so we can preserve/restore
  /// the scroll position across a tab switch (see [KeywordSnapshot]).
  final ScrollController _kwScroll = ScrollController();

  /// Last observed keyword-list scroll offset, captured live (the controller is
  /// detached by the time [dispose] runs, so we can't read it there).
  double _kwLastScroll = 0;

  /// Set on restore; the keyword list jumps here once laid out, then clears.
  double? _pendingKwScroll;

  // Retain the plain snapshot adapter: disposal must not resolve WidgetRef.
  late final KeywordSnapshotRepository _keywordSnapshots;

  late final HomeReturnRepository _homeReturnRepository;
  int _homeReturnRevision = -1;
  DateTime? _homeLoadedAt;
  double _homeLastScroll = 0;

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
  late final HomePikpakOnlyController _pikpakOnlyController;
  late final ProviderSubscription<bool> _pikpakOnlySubscription;
  bool get _pikpakOnly => _pikpakOnlyController.current;

  /// Experimental flag: route series taps to the merged detail+episodes page.
  /// Loaded once on init; movies and the flag-off path keep the existing flow.
  bool _mergedSeriesPage = false;

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  late final HomeBoundCountsController _boundCountsController;
  late final ProviderSubscription<Map<String, int>> _boundCountsSubscription;
  Map<String, int> get _boundCounts => _boundCountsController.current;

  // Board state. [_homeSections] is the homepage cache; [_sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  final _catalogContinueNode = FocusNode(debugLabel: 'catalog_continue');
  final _catalogMoreNode = FocusNode(debugLabel: 'catalog_more');
  FocusNode? _catalogReturnFocus;
  late final HomeCatalogContinuationController _catalogContinuationController;
  late final ProviderSubscription<bool> _catalogContinuationSubscription;
  bool get _catalogContinuing => _catalogContinuationController.busy;
  bool _loading = true;
  String? _error;
  List<CatalogSection> get _homeSections => _homeCatalogController.rows;
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
  bool get _catalogSearching => _catalogState.searching;
  // Catalogs that errored (timeout / HTTP / network) during the current
  // catalog search — distinct from "returned no results". Drives the quiet
  // "N sources didn't respond" note so failing addons don't just vanish.
  int get _catalogSearchFailures => _catalogState.failures;

  // Rows the user hid via Settings → Home Page → Home Rows (fixed-section
  // leaves like `cw:movies`/`trakt:shows`/`fav:iptv` and catalog leaves
  // `addonId:type:catalogId`). Gates every Home board row below. Refreshed by
  // [_reloadForHomeSettings] when the manager saves.
  // Bootstrap is captured at state construction, matching the previous field
  // initialization. All accepted changes live in the controller afterwards.
  final _initialHomeConfiguration = HomeBoardConfiguration(
    preferences: const HomeCatalogPreferences.empty(),
    collections: const [],
    collectionsSignature: HomeCollectionsStore.signatureOf(const []),
    hideWatched: HideWatchedPrefs.enabled,
  );
  HomeBoardConfiguration get _homeConfiguration =>
      _homeCatalogController.current.configuration;
  Set<String> get _homeDisabled => _homeConfiguration.preferences.disabled;

  // The OPT-IN extra rows (Trakt/Simkl list rows, IPTV custom-list rows) from
  // the same manager — default-off, so they live in their own store
  // (`home_extra_rows_v1`). Tracker ids become [HomeListSection]s at the head
  // of the board in [_load]; `iptvlist:` ids drive the IPTV list favourites
  // rows. Refreshed by [_reloadForHomeSettings].
  List<HomeExtraRow> get _homeExtras => _homeConfiguration.preferences.extras;

  /// Imported collections — each enabled one is a row of folder tiles.
  List<HomeCollection> get _homeCollections => _homeConfiguration.collections;
  late final ProviderSubscription<HomeSettingsRefresh>
  _homeSettingsRefreshSubscription;
  late final _spotlightCatalogCards = SpotlightCatalogCardCache(
    wideArtwork: homeStageWideArtwork,
    onOpen: (item, addon) => _openItem(item, addon),
  );

  /// Stable ids in the user's global Home-row order. Rows not present append
  /// canonically; ids whose backing row is temporarily unavailable stay saved.
  List<String> get _homeRowOrder => _homeConfiguration.preferences.rowOrder;

  /// The Spotlight hero-source pref (`home_hero_source_v1`): which catalog the
  /// hero reel is built from. Read in [_load], refreshed by
  /// [_reloadForHomeSettings]; resolved into [_spotlightHeroOverride] by
  /// [_resolveSpotlightHeroSource].
  HomeHeroSource get _heroSource => _homeConfiguration.preferences.heroSource;

  /// Whether any Trakt/Simkl list row is opted in — gates the tracker-row
  /// resolve in [_load] and the integrations-triggered reload.
  bool get _trackerExtrasEnabled =>
      _homeExtras.any((r) => HomeExtraRowIds.isTracker(r.id));

  /// Board load generation. [_load] is re-entrant (Home Rows save,
  /// integration connect/disconnect) and mutates shared state
  /// ([_boardRefs]/[_boardCursor]/[_homeSections]); every await inside the
  /// load pipeline re-checks this so a superseded load can neither apply its
  /// stale sections nor advance the new load's cursor.
  int get _boardLoadGen => _homeCatalogController.generation;
  bool get _boardRefreshing => _homeCatalogController.current.refreshing;
  bool _progressiveHomeLoadPending = false;
  bool _homePaginationDeferred = false;
  double _classicAnchorTailPadding = 0;
  final _homePublication = HomeProgressPublication();

  void _publishHomeProgress(
    List<CatalogSection> rows,
    bool first,
    int generation,
    Object? scope,
  ) {
    if (!mounted ||
        generation != _boardLoadGen ||
        scope != ProfileRuntime.scope.value) {
      return;
    }
    _homeCatalogController.replaceRows(rows);
    if (_catalogQuery.isNotEmpty || _catalogSearching) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      // Keep data, not new image widgets, while a detail page/player covers
      // Home. Returning first restores the old focused row, then inserts the
      // arrivals with the same scroll-anchor protection as foreground loads.
      _homePublication.defer((
        rows: rows,
        first: first,
        generation: generation,
        scope: scope,
      ));
      return;
    }
    _homePublication.clear();
    if (!first && _boardHasFocus()) _autoFocusSettled = true;
    setState(() {
      _loading = false;
      if (rows.isNotEmpty) _error = null;
    });
    _applySections(rows, preserveFocus: !first, incremental: !first);
    MainPageBridge.homeBoardReady.value = true;
    _maybeAutoFocusBoard();
    _maybeCompleteDeferredDown();
    _maybeCompleteStageAdvance();
  }

  void _resumeHomeProgress() => _homePublication.resume(
    isVisible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
    isCurrent: (pending) =>
        pending.generation == _boardLoadGen &&
        pending.scope == ProfileRuntime.scope.value,
    publish: (pending) => _publishHomeProgress(
      pending.rows,
      pending.first,
      pending.generation,
      pending.scope,
    ),
    onResumed: () => _maybeAutoFillBoard(resumeDeferred: true),
  );

  void _resumeDeferredHomePagination() {
    if (!_homePaginationDeferred || _boardRefreshing || !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _homePaginationDeferred = false;
    if (_boardHasMore) unawaited(_loadMoreBoard());
  }

  /// A triggered board reload arrived while a catalog search was showing its
  /// results — running [_load] then would stomp the search view, so it's
  /// latched here and consumed by [_restoreHome].
  bool _pendingBoardReload = false;

  // Riverpod owns inventory, reservation and the last accepted snapshot for
  // this view. Search detours retain the subscription and its cursor.
  late final ProviderSubscription<HomeDefaultView> _homeDefaultViewSubscription;
  HomeDefaultView get _homeDefaultView => _homeDefaultViewSubscription.read();
  late final HomeCatalogSession _homeCatalogSession;
  late final HomeCatalogController _homeCatalogController;
  late final ProviderSubscription<HomeCatalogState> _homeCatalogSubscription;
  List<HomeCatalogReference> get _boardRefs =>
      _homeCatalogController.current.references;
  int get _boardCursor => _homeCatalogController.current.cursor;
  HomeCatalogSnapshot? get _committedBoard =>
      _homeCatalogController.current.committed;
  bool get _boardLoadingMore => _homeCatalogController.current.loadingMore;
  late final ScrollController _boardScroll;

  /// Whether more board rows remain to lazily load (board mode only — never
  /// during a catalog search, which streams and appends its own rows).
  bool get _boardHasMore =>
      _catalogQuery.isEmpty &&
      !_catalogSearching &&
      _boardCursor < _boardRefs.length;

  /// Reserving a batch advances the cursor before all its rows arrive. This
  /// affects deferred navigation, not whether another batch should be fetched.
  bool get _boardRowsPending =>
      _catalogQuery.isEmpty && !_catalogSearching &&
      (_progressiveHomeLoadPending || _boardLoadingMore);

  bool get _boardCanAdvance => _boardHasMore || _boardRowsPending;

  bool get _canPageHome => mounted &&
      (!PlatformUtil.isAndroidTvCached ||
        ((ModalRoute.of(context)?.isCurrent ?? true) &&
          !_homePublication.hasPending && !_homePublication.isScheduled));

  // LOCAL Continue Watching rows. Reads the SAME local store Home writes to
  // (StorageService `continue_watching_v1`) — read-only here, so Home is never
  // affected. Split into two recency-ordered rows (Movies, then Series), each
  // shown as a leading board row when non-empty. Removal happens only from the
  // detail screen's action.
  late final HomeLocalContinuationController _localContinuationController;
  late final ProviderSubscription<HomeLocalContinuationState>
  _localContinuationSubscription;
  HomeLocalContinuationState get _localContinuation =>
      _localContinuationController.current;
  bool get _cwEnabled => _localContinuation.enabled;
  List<StremioMeta> get _cwMovies => _localContinuation.movies;
  List<StremioMeta> get _cwSeries => _localContinuation.series;
  List<StremioMeta> get _cwAll => _localContinuation.data.items;
  late final Map<String, double> _cwProgress;
  Map<String, String> get _cwEpisode => _localContinuation.data.episode;
  Map<String, int> get _cwRemainingMinutes =>
      _localContinuation.data.remainingMinutes;
  Set<String> get _cwIds => _localContinuation.data.ids;
  Map<String, String?> get _cwAddonId => _localContinuation.data.addonIds;
  Map<String, String> get _cwEpisodeArtwork =>
      _episodeArtworkController.current[HomeEpisodeArtworkSource.local] ??
      const {};

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
  late final HomeContinuationLayoutController _continuationLayoutController;
  late final ProviderSubscription<HomeContinuationLayout>
  _continuationLayoutSubscription;
  bool get _cwMergeLocal => _continuationLayoutController.current.local;
  bool get _cwMergeTrakt => _continuationLayoutController.current.trakt;
  bool get _cwMergeSimkl => _continuationLayoutController.current.simkl;
  bool get _cwMergeMdblist => _continuationLayoutController.current.mdblist;

  Future<void> _ensureCwMergeFlags() =>
      _continuationLayoutController.ensureLoaded(isCurrent: () => mounted);

  // IPTV Continue Watching (Xtream VOD movies + series), sourced from the
  // player's own watch history via [IptvCwRouter] — kept separate from the
  // metadata-addon rows above because IPTV items aren't IMDb-keyed, so their
  // progress/episode lookups and routing key off the router's routeKey (stored
  // as the synthetic meta id) instead of an imdbId.
  late final HomeIptvContinuationController _iptvContinuationController;
  late final ProviderSubscription<HomeIptvContinuationState>
  _iptvContinuationSubscription;
  HomeIptvContinuationState get _iptvContinuation =>
      _iptvContinuationController.current;
  List<StremioMeta> get _iptvCwMovies => _iptvContinuation.movies;
  List<StremioMeta> get _iptvCwSeries => _iptvContinuation.series;
  Map<String, double> get _iptvCwProgress => _iptvContinuation.progress;
  Map<String, String> get _iptvCwEpisode => _iptvContinuation.episode;
  Map<String, IptvCwEntry> get _iptvCwByKey => _iptvContinuation.byKey;
  final List<FocusNode> _iptvCwMovieNodes = [];
  final List<FocusNode> _iptvCwSeriesNodes = [];

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
  late final ProviderSubscription<bool> _postPlaybackRefreshSubscription;
  late final HomePostPlaybackRefreshController _postPlaybackRefreshController;
  bool get _playedSinceRefresh =>
      _postPlaybackRefreshController.playedSinceRefresh;

  // TRAKT Continue Watching rows ("Trakt Movies" / "Trakt Shows"), fetched live
  // from the Trakt account (no local store). Shown after the local rows when
  // connected + non-empty. Network-loaded on init / integration change,
  // post-playback, and throttled app resume, then cached in memory.
  late final HomeTraktContinuationController _traktContinuationController;
  late final ProviderSubscription<HomeTraktContinuationState>
  _traktContinuationSubscription;
  HomeTraktContinuation get _traktContinuation =>
      _traktContinuationController.current.data;
  List<StremioMeta> get _traktMovies => _traktContinuation.movies;
  List<StremioMeta> get _traktSeries => _traktContinuation.series;
  List<StremioMeta> get _traktAll => _traktContinuation.all;
  late final Map<String, double> _traktProgress;
  Map<String, String> get _traktEpisode => _traktContinuation.episode;
  Map<String, int> get _traktRemainingMinutes =>
      _traktContinuation.remainingMinutes;
  Map<String, TraktContinueWatchingItem> get _traktByImdb =>
      _traktContinuation.byImdb;
  Map<String, String> get _traktEpisodeArtwork =>
      _episodeArtworkController.current[HomeEpisodeArtworkSource.trakt] ??
      const {};
  final List<FocusNode> _traktMovieNodes = [];
  final List<FocusNode> _traktSeriesNodes = [];

  // SIMKL Continue Watching rows ("Simkl Movies" / "Simkl Shows") — a parallel
  // strip below the Trakt rows, built from the account's paused playback
  // sessions (same `/sync/playback` lists the scrobble resume already fetches).
  // Independent of the Trakt block above so neither can regress the other.
  late final HomeSimklContinuationController _simklContinuationController;
  late final ProviderSubscription<HomeSimklContinuation>
  _simklContinuationSubscription;
  HomeSimklContinuation get _simklContinuation =>
      _simklContinuationController.current;
  List<StremioMeta> get _simklMovies => _simklContinuation.movies;
  List<StremioMeta> get _simklSeries => _simklContinuation.series;
  List<StremioMeta> get _simklAll => _simklContinuation.all;
  late final Map<String, double> _simklProgress;
  Map<String, String> get _simklEpisode => _simklContinuation.episode;
  Map<String, SimklContinueWatchingItem> get _simklByImdb =>
      _simklContinuation.byImdb;
  Map<String, String> get _simklEpisodeArtwork =>
      _episodeArtworkController.current[HomeEpisodeArtworkSource.simkl] ??
      const {};

  final List<FocusNode> _simklMovieNodes = [];
  final List<FocusNode> _simklSeriesNodes = [];
  late final HomeMdblistContinuationController _mdblistContinuationController;
  late final ProviderSubscription<HomeMdblistContinuation>
  _mdblistContinuationSubscription;
  HomeMdblistContinuation get _mdblistContinuation =>
      _mdblistContinuationController.current;
  List<StremioMeta> get _mdblistMovies => _mdblistContinuation.movies;
  List<StremioMeta> get _mdblistSeries => _mdblistContinuation.series;
  List<StremioMeta> get _mdblistAll => _mdblistContinuation.all;
  late final Map<String, double> _mdblistProgress;
  Map<String, String> get _mdblistEpisode => _mdblistContinuation.episode;
  Map<String, MdblistContinueWatchingItem> get _mdblistByImdb =>
      _mdblistContinuation.byImdb;
  final List<FocusNode> _mdblistMovieNodes = [];
  final List<FocusNode> _mdblistSeriesNodes = [];
  // Debrify TV favourites — a leading "Debrify TV" row of the user's starred
  // keyword channels, shown between Continue Watching and the catalog rows.
  // Channels have no artwork, so they render as Stremio-shaped cards with a
  // gradient + glyph placeholder (see [HomeArtPoster]).
  late final HomeTvFavoritesController _tvFavoritesController;
  late final ProviderSubscription<List<DebrifyTvChannel>>
  _tvFavoritesSubscription;
  List<DebrifyTvChannel> get _tvFavChannels => _tvFavoritesController.current;
  final List<FocusNode> _tvFavNodes = [];

  // Stremio TV favourites — a leading row of the user's starred Stremio
  // "channels" (catalogs treated as TV channels). Each card shows the channel's
  // current now-playing item poster (same time-based rotation as the Home /
  // Stremio TV screens); tapping opens the channel. Loaded once on init.
  late final HomeStremioFavoritesController _stremioFavoritesController;
  late final ProviderSubscription<HomeStremioFavorites>
  _stremioFavoritesSubscription;
  List<HomeStremioFavorite> get _stvFavChannels =>
      _stremioFavoritesController.current.channels;
  final List<FocusNode> _stvFavNodes = [];

  // IPTV favourites — a leading row of the user's starred live IPTV channels.
  // Cards show the channel logo (glyph fallback); tapping plays the stream
  // directly via VideoPlayerLauncher (no tab switch). Reloaded whenever list
  // membership or manual order changes.
  late final HomeIptvFavoritesController _iptvFavoritesController;
  late final ProviderSubscription<List<IptvChannel>> _iptvFavoritesSubscription;
  List<IptvChannel> get _iptvFavChannels => _iptvFavoritesController.current;
  final List<FocusNode> _iptvFavNodes = [];

  // Debrify's account-independent movie/series watchlist. Full metadata is
  // stored locally and presented as separate movie and series rows, so neither
  // row needs a tracker or catalog network request.
  late final HomeWatchlistController _watchlistController;
  late final ProviderSubscription<HomeWatchlist> _watchlistSubscription;
  List<StremioMeta> get _watchlistMovieItems =>
      _watchlistController.current.movies;
  List<StremioMeta> get _watchlistSeriesItems =>
      _watchlistController.current.series;
  final List<FocusNode> _watchlistMovieNodes = [];
  final List<FocusNode> _watchlistSeriesNodes = [];

  // Opted-in IPTV custom lists as Home rows (`iptvlist:` extras), rendered
  // through the favourites-row family after the IPTV favourites row. Rebuilt
  // by [_loadIptvListRows] on init, on Home Rows saves, and whenever
  // [IptvMediaStore.listsRevision] bumps (any list mutation anywhere in the
  // app). The view owns FocusNodes, reconciled by list id across reloads.
  late final HomeIptvListsController _iptvListsController;
  late final ProviderSubscription<List<HomeIptvList>> _iptvListsSubscription;
  List<HomeIptvList> get _iptvListRows => _iptvListsController.current;
  final _iptvListFocus = HomeIptvListFocus();

  // Playlist favourites — a leading row of the user's saved playlist items
  // (movies / collections added from search or cloud). Cards show the item
  // poster with resume progress; tapping opens a full action menu (play / play
  // random / view files / favorite / clear progress / launch-on-startup /
  // delete), so this row is a complete playlist manager on its own now that the
  // Home playlist section is being phased out. Loaded once on init.
  late final HomePlaylistController _playlistController;
  late final ProviderSubscription<HomePlaylist> _playlistSubscription;
  List<HomePlaylistItem> get _playlistItems =>
      _playlistController.current.items;
  final List<FocusNode> _playlistFavNodes = [];
  // Guards against launching a second concurrent playback while the first is
  // still resolving links (the menu closes immediately, giving no other cue).
  bool _playlistLaunching = false;

  /// Last Trakt CW network attempt. The row is refreshed when the app returns
  /// from the background (where the user may have changed Trakt in another app
  /// or browser), but lifecycle noise within this window is coalesced.
  DateTime? get _lastTraktCwRefreshAttemptAt =>
      _traktContinuationController.lastAttemptAt;
  static const Duration _traktCwResumeRefreshInterval = Duration(seconds: 30);

  /// Whether a Trakt Continue Watching fetch is currently in flight for a
  /// connected account. While true — and there are no real Trakt rows to show
  /// yet — the Trakt slot is held open with skeleton placeholders (see
  /// [_traktReserving]) so the real rows fill in place instead of inserting
  /// mid-board and shoving everything below them down. Set at the start of each
  /// load and cleared on every terminal path, so a mid-session connect (which
  /// re-runs the load) reserves the slot again.
  bool get _traktCwLoading => _traktContinuationController.current.loading;

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
  late final Map<HomeTracker, ProviderSubscription<bool>>
  _trackerAuthSubscriptions;
  late final Map<HomeTracker, HomeTrackerAuthenticationController>
  _trackerAuthControllers;
  bool get _isTraktAuthenticated =>
      _trackerAuthControllers[HomeTracker.trakt]!.current;

  /// Whether Simkl is connected — gates the Simkl detail quick actions,
  /// rendered as their own strip alongside Trakt's (see [_isTraktAuthenticated]).
  bool get _isSimklAuthenticated =>
      _trackerAuthControllers[HomeTracker.simkl]!.current;

  /// Whether MDBList is connected — gates the MDBList entry in the Discover
  /// source dropdown (hidden when disconnected, so an unauthed user isn't shown
  /// a dead source; kept visible if it's somehow the active source).
  bool get _isMdblistAuthenticated =>
      _trackerAuthControllers[HomeTracker.mdblist]!.current;

  /// The Progress source, mirrored for the CW card lookups below. Smart until
  /// the first load resolves it (Smart = every row keeps its own numbers,
  /// which is also the pre-Tracking behaviour).
  WatchProgressSource get _cwProgressSource => _localContinuation.progressSource;

  /// Continue Watching cards show the title from whichever row owns it, but
  /// the PROGRESS comes from the selected Progress source — so a card can
  /// never advertise a resume point the detail page and Play button refuse to
  /// honour. In Smart mode each row keeps its own numbers (legacy behaviour);
  /// in a dedicated mode a title the chosen source doesn't know simply renders
  /// as a plain poster. IPTV rows are exempt: they are routeKey-keyed player
  /// history that no tracker can describe.
  String? _simklCardKey(StremioMeta item) =>
      HomeSimklContinuation.cardKey(item);

  String? _cwCardKey(HomeContinuationKind kind, StremioMeta item) =>
      _cwProgressSource == WatchProgressSource.simkl ||
          (_cwProgressSource == WatchProgressSource.smart && kind == HomeContinuationKind.simkl)
      ? _simklCardKey(item) : item.progressId;

  double? _cwCardProgress(HomeContinuationKind kind, StremioMeta item) =>
      CustomSeriesIdentity.isCustom(item.imdbId) ? _cwProgress[item.imdbId] : _cwCardMaps(kind).progress[_cwCardKey(kind, item)];

  String? _cwCardEpisode(HomeContinuationKind kind, StremioMeta item) =>
      CustomSeriesIdentity.isCustom(item.imdbId) ? _cwEpisode[item.imdbId] : _cwCardMaps(kind).episode[_cwCardKey(kind, item)];

  int? _cwCardRemainingMinutes(HomeContinuationKind kind, StremioMeta item) =>
      CustomSeriesIdentity.isCustom(item.imdbId) ? _cwRemainingMinutes[item.imdbId] : _cwCardMaps(kind).remaining?[item.progressId];

  ({
    Map<String, double> progress,
    Map<String, String> episode,
    Map<String, int>? remaining,
  })
  _cwCardMaps(HomeContinuationKind kind) {
    final effective = kind == HomeContinuationKind.iptv
        ? kind
        : switch (_cwProgressSource) {
            WatchProgressSource.smart => kind,
            WatchProgressSource.local => HomeContinuationKind.local,
            WatchProgressSource.trakt => HomeContinuationKind.trakt,
            WatchProgressSource.simkl => HomeContinuationKind.simkl,
            WatchProgressSource.mdblist => HomeContinuationKind.mdblist,
          };
    return switch (effective) {
      HomeContinuationKind.local => (
        progress: _cwProgress,
        episode: _cwEpisode,
        remaining: _cwRemainingMinutes,
      ),
      HomeContinuationKind.trakt => (
        progress: _traktProgress,
        episode: _traktEpisode,
        remaining: _traktRemainingMinutes,
      ),
      HomeContinuationKind.simkl => (
        progress: _simklProgress,
        episode: _simklEpisode,
        remaining: null,
      ),
      HomeContinuationKind.mdblist => (
        progress: _mdblistProgress,
        episode: _mdblistEpisode,
        remaining: null,
      ),
      HomeContinuationKind.iptv => (
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
  List<HomeContinuationRow> get _cwRows => [
    // Merged providers ship their combined list through the MOVIES slot (same
    // row id, same node list — see the merge-pref field comment); the episode
    // and artwork lookups are imdbId-keyed maps that only hold series entries,
    // so passing movies through them is a harmless miss.
    if (_cwEnabled &&
        (_cwMergeLocal ? _cwAll : _cwMovies).isNotEmpty &&
        !_homeDisabled.contains('cw:movies'))
      HomeContinuationRow(
        rowId: 'cw:movies',
        title: 'Continue Watching',
        tag: _cwMergeLocal ? null : 'Movies',
        kind: HomeContinuationKind.local,
        items: _cwMergeLocal ? _cwAll : _cwMovies,
        nodes: _cwMovieNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.local, m),
        episodeOf: _cwMergeLocal
            ? (m) => _cwCardEpisode(HomeContinuationKind.local, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.local, m),
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
      HomeContinuationRow(
        rowId: 'cw:series',
        title: 'Continue Watching',
        tag: 'Series',
        kind: HomeContinuationKind.local,
        items: _cwSeries,
        nodes: _cwSeriesNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.local, m),
        episodeOf: (m) => _cwCardEpisode(HomeContinuationKind.local, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.local, m),
        episodeArtworkOf: (m) => _cwEpisodeArtwork[m.imdbId],
        onOpen: _openContinueItem,
        onQuickPlay: _onContinuePlay,
        onRemove: _removeLocalCwItem,
        onSeeAll: () => _openContinueWatchingSeeAll('series'),
      ),
    if ((_cwMergeTrakt ? _traktAll : _traktMovies).isNotEmpty &&
        !_homeDisabled.contains('trakt:movies'))
      HomeContinuationRow(
        rowId: 'trakt:movies',
        title: 'Trakt Continue Watching',
        tag: _cwMergeTrakt ? null : 'Movies',
        kind: HomeContinuationKind.trakt,
        items: _cwMergeTrakt ? _traktAll : _traktMovies,
        nodes: _traktMovieNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.trakt, m),
        episodeOf: _cwMergeTrakt
            ? (m) => _cwCardEpisode(HomeContinuationKind.trakt, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.trakt, m),
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
      HomeContinuationRow(
        rowId: 'trakt:shows',
        title: 'Trakt Continue Watching',
        tag: 'Shows',
        kind: HomeContinuationKind.trakt,
        items: _traktSeries,
        nodes: _traktSeriesNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.trakt, m),
        episodeOf: (m) => _cwCardEpisode(HomeContinuationKind.trakt, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.trakt, m),
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
      HomeContinuationRow(
        rowId: 'simkl:movies',
        title: 'Simkl Continue Watching',
        tag: _cwMergeSimkl ? null : 'Movies',
        kind: HomeContinuationKind.simkl,
        items: _cwMergeSimkl ? _simklAll : _simklMovies,
        nodes: _simklMovieNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.simkl, m),
        episodeOf: _cwMergeSimkl
            ? (m) => _cwCardEpisode(HomeContinuationKind.simkl, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.simkl, m),
        episodeArtworkOf: _cwMergeSimkl
            ? (m) => _simklEpisodeArtwork[m.progressId]
            : (_) => null,
        onOpen: _openSimklCwItem,
        onQuickPlay: _playSimklCwItem,
        onRemove: _removeSimklCwItem,
        onSeeAll: () => _openSimklCwSeeAll(_cwMergeSimkl ? 'all' : 'movie'),
      ),
    if (!_cwMergeSimkl &&
        _simklSeries.isNotEmpty &&
        !_homeDisabled.contains('simkl:shows'))
      HomeContinuationRow(
        rowId: 'simkl:shows',
        title: 'Simkl Continue Watching',
        tag: 'Shows',
        kind: HomeContinuationKind.simkl,
        items: _simklSeries,
        nodes: _simklSeriesNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.simkl, m),
        episodeOf: (m) => _cwCardEpisode(HomeContinuationKind.simkl, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.simkl, m),
        episodeArtworkOf: (m) => _simklEpisodeArtwork[m.progressId],
        onOpen: _openSimklCwItem,
        onQuickPlay: _playSimklCwItem,
        onRemove: _removeSimklCwItem,
        onSeeAll: () => _openSimklCwSeeAll('series'),
      ),
    if ((_cwMergeMdblist ? _mdblistAll : _mdblistMovies).isNotEmpty &&
        !_homeDisabled.contains('mdblist:movies'))
      HomeContinuationRow(
        rowId: 'mdblist:movies',
        title: 'MDBList Continue Watching',
        tag: _cwMergeMdblist ? null : 'Movies',
        kind: HomeContinuationKind.mdblist,
        items: _cwMergeMdblist ? _mdblistAll : _mdblistMovies,
        nodes: _mdblistMovieNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.mdblist, m),
        episodeOf: _cwMergeMdblist
            ? (m) => _cwCardEpisode(HomeContinuationKind.mdblist, m)
            : (_) => null,
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.mdblist, m),
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
      HomeContinuationRow(
        rowId: 'mdblist:shows',
        title: 'MDBList Continue Watching',
        tag: 'Shows',
        kind: HomeContinuationKind.mdblist,
        items: _mdblistSeries,
        nodes: _mdblistSeriesNodes,
        progressOf: (m) => _cwCardProgress(HomeContinuationKind.mdblist, m),
        episodeOf: (m) => _cwCardEpisode(HomeContinuationKind.mdblist, m),
        remainingMinutesOf: (m) => _cwCardRemainingMinutes(HomeContinuationKind.mdblist, m),
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
      HomeContinuationRow(
        rowId: 'iptv:movies',
        title: 'IPTV Continue Watching',
        tag: 'Movies',
        kind: HomeContinuationKind.iptv,
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
      HomeContinuationRow(
        rowId: 'iptv:series',
        title: 'IPTV Continue Watching',
        tag: 'Series',
        kind: HomeContinuationKind.iptv,
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
  List<String> get _effectiveHomeRowOrder => HomeRowOrder.seedCollections(
    HomeRowOrder.insertMissingAfter(
      _homeRowOrder,
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    ),
    [
      for (final c in _homeCollections)
        if (c.pinToTop) HomeCollectionRowIds.collection(c.id),
      for (final c in _homeCollections)
        if (!c.pinToTop) HomeCollectionRowIds.collection(c.id),
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
  late final ProviderSubscription<HomeHeroMetadataLoader>
  _heroMetadataSubscription;
  late final ProviderSubscription<HomeTrackerResumeRepository>
  _trackerResumeSubscription;
  late final ProviderSubscription<HomeSeriesResumeResolver>
  _seriesResumeResolverSubscription;

  /// Settle debounce for the hero SWAP itself (260ms): while DPAD focus flies
  /// across cards only the card visuals update; the spotlight (backdrop
  /// decode, logo, meta, tint cascade) follows once focus rests.
  final HomeHeroSwap _heroSwap = HomeHeroSwap();

  // Hero ambient trailer (Home board, TV only): once DPAD focus RESTS on a
  // card, its trailer crossfades into the hero backdrop — same living-backdrop
  // treatment (and the same HeroTrailerBackdrop machinery: single decoder,
  // route/background pausing) as the detail page. Notifier-driven so a trailer
  // arriving rebuilds only the hero's video layer, never the board.
  final ValueNotifier<YoutubeResolvedStreams?> _heroTrailer =
      ValueNotifier<YoutubeResolvedStreams?>(null);
  late final ProviderSubscription<HomeHeroTrailerLoader>
  _heroTrailerLoaderSubscription;

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
  /// [HomeHeroTrailerLayer] as its promote animation runs. The board content and
  /// the sidebar rail fade fully OUT on it while the compact info overlay
  /// fades in — the film takes the room.
  final ValueNotifier<double> _heroTrailerTakeover = ValueNotifier<double>(0);

  // Live IPTV favourite hero preview: when DPAD focus rests on an "IPTV" row
  // card, its stream plays in the SAME boxed video region as the catalog
  // trailer above — reusing HeroTrailerBackdrop's `live: true` mode, exactly
  // like the IPTV page's own inline channel preview
  // (IptvResultsView._buildPreviewStage). Painted as a layer above
  // [HomeHeroTrailerLayer] so the two never need to swap types; whichever one
  // actually has a URL to show wins (see [_setHeroLiveIptv]).
  final ValueNotifier<String?> _heroLiveUrl = ValueNotifier<String?>(null);

  /// Set the INSTANT an IPTV favourite gains focus — well before its stream
  /// (if a Stremio-addon channel) finishes resolving. [_HeroLiveLayer] uses
  /// this to occlude the region with the channel's OWN art immediately, so
  /// the previously-focused catalog title's Cinemeta poster never shows
  /// through the resolve/buffer gap underneath.
  final ValueNotifier<IptvChannel?> _heroLiveChannel =
      ValueNotifier<IptvChannel?>(null);

  /// Boolean mirror of [_heroLiveChannel] for [HomeHeroSpotlight.liveTakeover] —
  /// the spotlight fades its (now-stale) colour field and identity text on
  /// this, and has no other reason to know the IPTV-specific channel type.
  final ValueNotifier<bool> _heroLiveTakeover = ValueNotifier<bool>(false);
  late final ProviderSubscription<HomeHeroLivePreview> _heroLiveSubscription;

  HomeHeroShellBridge? _heroShellBinding;
  final HomeHeroPreviewPolicy _heroPreviewPolicy = HomeHeroPreviewPolicy();

  /// Accepted trailer settings, refreshed on settings and sync notifications.
  late final HomeTrailerPreferencesController _heroTrailerPreferencesController;
  late final ProviderSubscription<HomeTrailerPreferences>
  _heroTrailerPreferencesSubscription;
  bool get _heroTrailerEnabled =>
      _heroTrailerPreferencesController.current.enabled;

  /// Effective ambient volume (0–100); zero while the sound toggle is off.
  double get _heroTrailerVolume =>
      _heroTrailerPreferencesController.current.volume;

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
  late final ProviderSubscription<DiscoverSourceState>
  _discoverSourceSubscription;
  late final DiscoverSourceController _discoverSourceController;
  String get _discSource => _discoverSourceController.current.source;
  List<StremioAddon> get _discAddons =>
      _discoverSourceController.current.addons;
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

  // Local preview signals are borrowed by the resolving rail and player stage.
  late final DiscoverPreview _discPreview = DiscoverPreview(
    isCurrent: () => mounted,
  );

  /// Relay the Discover takeover to the app shell so the TV sidebar hides in
  /// lock-step (a cinema has no menu) — the same signal the Home board uses.
  void _relayDiscoverChromeDim() =>
      MainPageBridge.tvChromeDim.value = _discPreview.takeover.value;

  // ── Discover layout (grid / stage) ───────────────────────────────────────

  late final ProviderSubscription<String> _discoverLayoutSubscription;
  late final DiscoverLayoutController _discoverLayoutController;
  String get _discLayout => _discoverLayoutController.current;

  late final ProviderSubscription<DiscoverCardSettings>
  _discoverCardSettingsSubscription;
  late final DiscoverCardSettingsController _discoverCardSettingsController;
  DiscoverCardSettings get _discCardSettings =>
      _discoverCardSettingsController.current;

  /// Whether the STAGE layout is what this surface should render: the pref, on
  /// the Discover tab, on a TV. The canvas-size guard lives in the LayoutBuilder
  /// (a too-small canvas falls back to the flat panel, exactly like the grid's
  /// two-pane does).
  bool get _discStage =>
      widget.discoverMode && widget.isTelevision && _discLayout == 'stage';

  Future<void> _loadDiscoverLayout() => _discoverLayoutController.load(
    isCurrent: () => mounted,
    onChanged: () => setState(() {}),
  );

  /// Settings picker fired: tear the trailer down BEFORE the relayout, so the
  /// player is never re-parented mid-play into the other layout's tree (the
  /// Home board's rule for the same swap), then re-read the pref and rebuild.
  void _onDiscoverLayoutChanged() {
    if (!mounted) return;
    _discPreview.resetPlayback();
    unawaited(_loadDiscoverLayout());
  }

  void _onDiscoverCardSettingsChanged() {
    if (!mounted) return;
    if (_discoverCardSettingsController.refresh(isCurrent: () => mounted)) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _titleSearch.addListener(_publishTitleSuggestions);
    _searchController.addListener(_onTitleSearchEditingChanged);
    ProfileRuntime.scope.addListener(_onSearchProfileChanged);
    MetadataPreferencesService.revision.addListener(_metadataSettingsChanged);
    final metadataSession = (
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    _metadataFeatureSubscription = ref.listenManual(
      metadataFeaturePolicyProvider(metadataSession),
      (previous, next) {},
    );
    _metadataFeatureController = ref.read(
      metadataFeaturePolicyProvider(metadataSession).notifier,
    );
    unawaited(_refreshMetadataFeaturePolicy());
    WidgetsBinding.instance.addObserver(this);
    _profileSessionOwner = ProfileSessionMemory.captureOwner();
    _homeReturnRepository = ref.read(
      homeReturnRepositoryProvider(_profileSessionOwner),
    );
    _homeCollectionsRepository = ref.read(homeCollectionsRepositoryProvider);
    _keywordSnapshots = ref.read(
      keywordSnapshotRepositoryProvider(_profileSessionOwner),
    );
    final keywordSnapshot = _takeKeywordSnapshot();
    _searchSession = SearchSession(
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initialKeywordQuery: keywordSnapshot?.query ?? '',
      initialKeywordResults: keywordSnapshot?.projection,
      initialKeywordCache:
          keywordSnapshot?.cache ?? const KeywordCacheState.empty(),
    );
    _keywordAppearanceSubscription = ref.listenManual(
      keywordAppearanceProvider(_searchSession),
      (previous, next) {},
    );
    _keywordAppearanceController = ref.read(
      keywordAppearanceProvider(_searchSession).notifier,
    );
    unawaited(_loadSourceTextFormatting());
    // Retain state for this screen's mounted lifetime, including covered routes.
    // Returning from a pushed list must not discard results or replay a request.
    _listsSubscription = ref.listenManual(
      listsSearchProvider(_searchSession),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _catalogSubscription = ref.listenManual(
      catalogSearchProvider(_searchSession),
      (previous, next) {
        if (!mounted) return;
        if (!widget.isTelevision && next.rows.isNotEmpty &&
            !identical(previous?.rows, next.rows)) {
          // Keep existing row nodes while new non-TV results stream in.
          final previousCount = previous?.rows.length ?? 0;
          final additions = next.rows.skip(previousCount)
              .map(catalogSearchSection).toList();
          if (previousCount == 0) {
            _applySections(additions);
          } else {
            _appendSections(additions);
          }
        } else {
          setState(() {});
        }
      },
    );
    _keywordCacheSubscription = ref.listenManual(
      keywordCacheProvider(_searchSession),
      (previous, next) {
        // Badges repaint without rebuilding focus nodes. Only the accepted
        // completion wrapper below asks for a cached-only row recomputation.
        if (mounted) setState(() {});
      },
    );
    _keywordResultsSubscription = ref.listenManual(
      keywordResultsProvider(_searchSession),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _keywordSearchSubscription = ref.listenManual(
      keywordSearchProvider(_searchSession),
      (previous, next) {
        if (!mounted) return;
        final results = next.results;
        if (results != null) {
          _presentKwStreaming(results, next.request);
        }
        if (next.status == KeywordSearchStatus.complete) {
          _finishKeyword(next.request);
        } else if (next.status == KeywordSearchStatus.failed) {
          _searchSubmitFocus.cancel();
        }
        setState(() {});
      },
    );
    if (!widget.searchMode && !widget.discoverMode) {
      _homeReturnRepository.observeInvalidation();
    }
    final homeSnapshot = !widget.searchMode && !widget.discoverMode
        ? _homeReturnRepository.take()
        : null;
    final restoredHome = homeSnapshot != null &&
        homeSnapshot.configuration.hideWatched == HideWatchedPrefs.enabled;
    // Seed cached state in provider construction so the first return frame
    // does not mutate a provider during initState or wait for another frame.
    final homeSession = HomeCatalogSession(
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initialBoard: restoredHome && keywordSnapshot == null
          ? homeSnapshot.board : null,
      initialConfiguration: restoredHome && keywordSnapshot == null
          ? homeSnapshot.configuration : _initialHomeConfiguration,
      initialRows: restoredHome && keywordSnapshot == null
          ? homeSnapshot.sections : const [],
      initiallyRefreshing: !widget.searchMode && !widget.discoverMode &&
          !(restoredHome && keywordSnapshot == null),
    );
    _homeCatalogSession = homeSession;
    _homeCatalogSubscription = ref.listenManual(
      homeCatalogProvider(homeSession),
      (previous, next) {},
    );
    _homeCatalogController = ref.read(homeCatalogProvider(homeSession).notifier);
    _catalogContinuationSubscription = ref.listenManual(
      homeCatalogContinuationProvider(homeSession),
      (previous, next) {
        if (mounted) setState(() {});
      },
    );
    _catalogContinuationController = ref.read(
      homeCatalogContinuationProvider(homeSession).notifier,
    );
    _episodeArtworkSubscription = ref.listenManual(
      homeEpisodeArtworkProvider(homeSession),
      (previous, next) {},
    );
    _episodeArtworkController = ref.read(
      homeEpisodeArtworkProvider(homeSession).notifier,
    );
    _trackerAuthSubscriptions = {
      for (final tracker in HomeTracker.values)
        tracker: ref.listenManual(
          homeTrackerAuthenticationProvider((
            view: homeSession,
            tracker: tracker,
          )),
          (previous, next) {},
        ),
    };
    _trackerAuthControllers = {
      for (final tracker in HomeTracker.values)
        tracker: ref.read(
          homeTrackerAuthenticationProvider((
            view: homeSession,
            tracker: tracker,
          )).notifier,
        ),
    };
    _pikpakOnlySubscription = ref.listenManual(
      homePikpakOnlyProvider(homeSession),
      (previous, next) {},
    );
    _pikpakOnlyController = ref.read(
      homePikpakOnlyProvider(homeSession).notifier,
    );
    _boundCountsSubscription = ref.listenManual(
      homeBoundCountsProvider(homeSession),
      (previous, next) {},
    );
    _boundCountsController = ref.read(
      homeBoundCountsProvider(homeSession).notifier,
    );
    _postPlaybackRefreshSubscription = ref.listenManual(
      homePostPlaybackRefreshProvider(homeSession),
      (previous, next) {},
    );
    _postPlaybackRefreshController = ref.read(
      homePostPlaybackRefreshProvider(homeSession).notifier,
    );
    _homeSettingsRefreshSubscription = ref.listenManual(
      homeSettingsRefreshProvider(homeSession),
      (previous, next) {},
    );
    _heroTintSubscription = ref.listenManual(
      homeHeroTintLoaderProvider(homeSession),
      (previous, next) {},
    );
    _heroLiveSubscription = ref.listenManual(
      homeHeroLivePreviewProvider(homeSession),
      (previous, next) {},
    );
    _heroTrailerLoaderSubscription = ref.listenManual(
      homeHeroTrailerLoaderProvider(homeSession),
      (previous, next) {},
    );
    _trackerResumeSubscription = ref.listenManual(
      homeTrackerResumeRepositoryProvider(homeSession),
      (previous, next) {},
    );
    _seriesResumeResolverSubscription = ref.listenManual(
      homeSeriesResumeResolverProvider(homeSession),
      (previous, next) {},
    );
    _heroMetadataSubscription = ref.listenManual(
      homeHeroMetadataLoaderProvider(homeSession),
      (previous, next) {},
    );
    _homeLayoutPreferenceSubscription = ref.listenManual(
      homeLayoutPreferenceProvider(homeSession),
      (previous, next) {},
    );
    _tvHomeStyle = _homeLayoutPreferenceSubscription.read().initialStyle;
    _heroTrailerPreferencesSubscription = ref.listenManual(
      homeTrailerPreferencesProvider(homeSession),
      (previous, next) {},
    );
    _heroTrailerPreferencesController = ref.read(
      homeTrailerPreferencesProvider(homeSession).notifier,
    );
    _homeDefaultViewSubscription = ref.listenManual(
      homeDefaultViewProvider(homeSession),
      (previous, next) {},
    );
    final displaySession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initial: restoredHome && keywordSnapshot == null
          ? (
              orientation: homeSnapshot.cardOrientation,
              hideTitlesAndRatings: homeSnapshot.hideCardTitlesAndRatings,
              hideCatalogAddonNames: homeSnapshot.hideCatalogAddonNames,
              hideCollectionNames: homeSnapshot.hideCollectionNames,
              spotlightFocusDetails: false,
              animationsEnabled: false,
              animationStyle: 'snowy_mountain',
            )
          : initialHomeDisplayPreferences,
    );
    _homeDisplaySubscription = ref.listenManual(
      homeDisplayPreferencesProvider(displaySession),
      (previous, next) {},
    );
    _homeDisplayController = ref.read(
      homeDisplayPreferencesProvider(displaySession).notifier,
    );
    final tvFavoritesSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _tvFavoritesSubscription = ref.listenManual(
      homeTvFavoritesProvider(tvFavoritesSession),
      (previous, next) {},
    );
    _tvFavoritesController = ref.read(
      homeTvFavoritesProvider(tvFavoritesSession).notifier,
    );
    final stremioFavoritesSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _stremioFavoritesSubscription = ref.listenManual(
      homeStremioFavoritesProvider(stremioFavoritesSession),
      (previous, next) {},
    );
    _stremioFavoritesController = ref.read(
      homeStremioFavoritesProvider(stremioFavoritesSession).notifier,
    );
    final iptvFavoritesSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _iptvFavoritesSubscription = ref.listenManual(
      homeIptvFavoritesProvider(iptvFavoritesSession),
      (previous, next) {},
    );
    _iptvFavoritesController = ref.read(
      homeIptvFavoritesProvider(iptvFavoritesSession).notifier,
    );
    final iptvListsSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _iptvListsSubscription = ref.listenManual(
      homeIptvListsProvider(iptvListsSession),
      (previous, next) {},
    );
    _iptvListsController = ref.read(
      homeIptvListsProvider(iptvListsSession).notifier,
    );
    final watchlistSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _watchlistSubscription = ref.listenManual(
      homeWatchlistProvider(watchlistSession),
      (previous, next) {},
    );
    _watchlistController = ref.read(
      homeWatchlistProvider(watchlistSession).notifier,
    );
    final playlistSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _playlistSubscription = ref.listenManual(
      homePlaylistProvider(playlistSession),
      (previous, next) {},
    );
    _playlistController = ref.read(homePlaylistProvider(playlistSession).notifier);
    final localContinuationSession = HomeContinuationSession(
      owner: _profileSessionOwner,
      viewIdentity: Object(),
    );
    _continuationLayoutSubscription = ref.listenManual(
      homeContinuationLayoutProvider(localContinuationSession),
      (previous, next) {},
    );
    _continuationLayoutController = ref.read(
      homeContinuationLayoutProvider(localContinuationSession).notifier,
    );
    _localContinuationSubscription = ref.listenManual(
      homeLocalContinuationProvider(localContinuationSession),
      (previous, next) {},
    );
    _localContinuationController = ref.read(
      homeLocalContinuationProvider(localContinuationSession).notifier,
    );
    _cwProgress = HomeProgressView(
      () => _localContinuationController.current.data.progress,
    );
    final traktContinuationScope = (
      session: localContinuationSession,
      initiallyLoading: !widget.searchMode,
    );
    _traktContinuationSubscription = ref.listenManual(
      homeTraktContinuationProvider(traktContinuationScope),
      (previous, next) {},
    );
    _traktContinuationController = ref.read(
      homeTraktContinuationProvider(traktContinuationScope).notifier,
    );
    _traktProgress = HomeProgressView(
      () => _traktContinuationController.current.data.progress,
    );
    _simklContinuationSubscription = ref.listenManual(
      homeSimklContinuationProvider(localContinuationSession),
      (previous, next) {},
    );
    _simklContinuationController = ref.read(
      homeSimklContinuationProvider(localContinuationSession).notifier,
    );
    _simklProgress = HomeProgressView(
      () => _simklContinuationController.current.progress,
    );
    _mdblistContinuationSubscription = ref.listenManual(
      homeMdblistContinuationProvider(localContinuationSession),
      (previous, next) {},
    );
    _mdblistContinuationController = ref.read(
      homeMdblistContinuationProvider(localContinuationSession).notifier,
    );
    _mdblistProgress = HomeProgressView(
      () => _mdblistContinuationController.current.progress,
    );
    _iptvContinuationSubscription = ref.listenManual(
      homeIptvContinuationProvider(localContinuationSession),
      (previous, next) {},
    );
    _iptvContinuationController = ref.read(
      homeIptvContinuationProvider(localContinuationSession).notifier,
    );
    _homeLastScroll = restoredHome && !widget.isTelevision
        ? homeSnapshot.scrollOffset : 0;
    _boardScroll = ScrollController(initialScrollOffset: _homeLastScroll);
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
      MainPageBridge.activeTab.addListener(_onTitleSearchTabChanged);
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
      }
    }
    final discoverSession = (
      owner: _profileSessionOwner,
      viewIdentity: Object(),
      initialSource: _discMdblistList == null ? _discCw : _discMdblist,
      hasHandoff: _discMdblistList != null,
    );
    final discoverLayoutSession = (
      owner: _profileSessionOwner,
      viewIdentity: discoverSession.viewIdentity,
    );
    _discoverCardSettingsSubscription = ref.listenManual(
      discoverCardSettingsProvider(discoverLayoutSession),
      (previous, next) {},
    );
    _discoverCardSettingsController = ref.read(
      discoverCardSettingsProvider(discoverLayoutSession).notifier,
    );
    _discoverLayoutSubscription = ref.listenManual(
      discoverLayoutProvider(discoverLayoutSession),
      (previous, next) {},
    );
    _discoverLayoutController = ref.read(
      discoverLayoutProvider(discoverLayoutSession).notifier,
    );
    _discoverSourceSubscription = ref.listenManual(
      discoverSourceProvider(discoverSession),
      (previous, next) {},
    );
    _discoverSourceController = ref.read(
      discoverSourceProvider(discoverSession).notifier,
    );
    if (_discMdblistList != null) {
      unawaited(
        _discoverSourceController.rememberCurrent(isCurrent: () => mounted),
      );
    }
    // Ambient hero trailer gates (Home board TV only) — read before the board
    // loads so the seeded first spotlight can already schedule its trailer.
    if (_heroTrailerActive) {
      _heroShellBinding = HomeHeroShellBridge(
        takeover: _heroTrailerTakeover,
        showing: _heroTrailerShowing,
        onSidebarFocus: _onTvSidebarFocusChanged,
        onChromeDim: _relayChromeDim,
        onLightsOff: _relayLightsOff,
        onContentLaunch: _onContentPlayerLaunch,
        onKey: _onTakeoverKey,
        routeAware: this,
      );
      unawaited(_reloadHeroTrailerPrefs(initial: true));
    }
    // Discover on TV: relay the trailer takeover to the sidebar chrome-dim so
    // the rail hides when the trailer goes fullscreen. The showing listener
    // arms the theater timer (deep lights-off a few seconds into playback).
    if (widget.discoverMode) {
      MainPageBridge.discoverCardSettingsChanged =
          _onDiscoverCardSettingsChanged;
    }
    if (widget.discoverMode && widget.isTelevision) {
      _discPreview.takeover.addListener(_relayDiscoverChromeDim);
      _discPreview.observePlayback();
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
    if (widget.isTelevision && widget.searchMode) {
      _reloadSearchCardPrefs();
      MainPageBridge.addHomeSettingsListener(_reloadSearchCardPrefs);
    }
    // Restore a keyword search preserved from a prior tab visit (results +
    // scroll) BEFORE the async default-view load below can start: restoration
    // sets keyword mode synchronously, and a later-resolving catalog default
    // would flip the mode back and could fire a catalog search with the
    // restored keyword text. A successful restore therefore also suppresses
    // the default-view load outright.
    final restoredKeyword = _restoreKeywordState(keywordSnapshot);
    // Home board only: live-refresh when the Home Rows manager changes which
    // rows are hidden. The bridge also invalidates a saved return snapshot.
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
        HardwareKeyboard.instance.addHandler(_stageHold.handleKeyEvent);
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
        unawaited(_reloadHeroTrailerPrefs());
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
        if (restoredHome && !restoredKeyword)
          _restoreHomeSnapshot(homeSnapshot)
        else
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
    _mode = SearchMode.catalog;
    _clearQuery();
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
    return true;
  }

  /// Re-read hero trailer prefs when Home survives Settings or a WebDAV
  /// update. TV also needs the live read now that trailer volume can sync
  /// without switching tabs. The existing audio/enable gates remain local.
  ///
  /// Sound/volume read the DETAIL surface keys off-TV: that is the pair the
  /// settings page has always shown on these platforms, so a stored "sound
  /// off" keeps meaning what it meant. Writes go to both surfaces now, so
  /// the pairs converge on first change.
  void _reloadSearchCardPrefs() {
    unawaited(_loadHomeCardOrientation());
    unawaited(_reloadHeroTrailerPrefs());
  }

  Future<void> _reloadHeroTrailerPrefs({
    bool initial = false,
    bool Function()? isCurrent,
  }) => _heroTrailerPreferencesController.load(
    useHomeAudio: widget.isTelevision,
    isCurrent: () => mounted && (isCurrent?.call() ?? true),
    onAccepted: (preferences) {
      setState(() {});
      if (initial) {
        if (!preferences.enabled) return;
        // The board usually seeds the hero before this read lands.
        final current = _heroItem.value;
        if (current != null) _scheduleHeroTrailer(current);
      } else if (!preferences.enabled) {
        _clearHeroTrailer();
      }
    },
  );

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
    _mode = SearchMode.catalog;
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

  Future<void> _refreshTraktAuthState() =>
      _trackerAuthControllers[HomeTracker.trakt]!.load(
        isCurrent: () => mounted,
        onChanged: (_) => setState(() {}),
      );

  Future<void> _refreshSimklAuthState() =>
      _trackerAuthControllers[HomeTracker.simkl]!.load(
        isCurrent: () => mounted,
        onChanged: (_) => setState(() {}),
      );

  Future<void> _refreshMdblistAuthState() {
    var leaveLists = false;
    return _trackerAuthControllers[HomeTracker.mdblist]!.load(
      isCurrent: () => mounted,
      beforeChange: (auth) {
        leaveLists = !auth && _mode == SearchMode.lists;
        if (leaveLists) _clearListsSearch();
      },
      onChanged: (_) {
        setState(() {
          if (leaveLists) _mode = SearchMode.catalog;
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
      },
    );
  }

  /// Consume the borrowed snapshot once, before constructing providers. Seed
  /// their initial state instead of mutating them during widget initialization.
  KeywordSnapshot? _takeKeywordSnapshot() {
    if (widget.isTelevision && !widget.searchMode && !widget.discoverMode) {
      return null;
    }
    return _keywordSnapshots.take(
      _variantKey,
      allowed: ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
    );
  }

  /// Restore presentation fields before the first build, retaining default-view
  /// suppression and scroll timing. Cache state is already seeded in its owner.
  bool _restoreKeywordState(KeywordSnapshot? snap) {
    if (snap == null) return false;
    _mode = SearchMode.keyword;
    _searchController.text = snap.query;
    _disposeKwNodes();
    _keywordFocus.syncRows(snap.projection.results.length);
    _syncKwTabNodes();
    _pendingKwScroll = snap.scrollOffset;
    return true;
  }

  Future<void> _restoreHomeSnapshot(HomeReturnSnapshot snapshot) async {
    _homeReturnRevision = _homeReturnRepository.revision;
    _homeLoadedAt = snapshot.loadedAt;
    _spotlightHeroOverride = snapshot.hero;
    _addonsById
      ..clear()
      ..addAll(snapshot.board.addons);
    _loading = false;
    _spotlightEntryRevealed = true;
    if (snapshot.heroResolutionPending) {
      unawaited(_resolveSpotlightHeroSource(_addonsById.values.toList()));
    }
    _applySections(_homeSections);
    MainPageBridge.homeBoardReady.value = true;
    _maybeAutoFocusBoard();
    _maybeAutoFillBoard();
    unawaited(_refreshPikpakOnly());
    if (_trackerExtrasEnabled) {
      final generation = _boardLoadGen;
      final owner = _profileSessionOwner;
      unawaited(HomeListRowsService.instance.resolve(
        _homeExtras,
        previous: _homeSections.whereType<HomeListSection>().toList(),
        isCurrent: () => mounted && generation == _boardLoadGen &&
            owner == ProfileSessionMemory.captureOwner(),
        onUpdate: (rows) {
          if (!mounted || generation != _boardLoadGen ||
              owner != ProfileSessionMemory.captureOwner()) {
            return;
          }
          _publishHomeProgress(replaceHomeListRows(_homeSections, rows),
            false, generation, ProfileRuntime.scope.value);
        },
      ).catchError((_) => <HomeListSection>[]));
    }
    // Re-read local configuration too, including imports that bypass the UI
    // bridge. Continue Watching and favourite loaders still run on each visit.
    await _reloadForHomeSettings();
  }

  void _preserveHomeSnapshot() {
    final board = _committedBoard;
    final loadedAt = _homeLoadedAt;
    if (widget.searchMode ||
        widget.discoverMode ||
        board == null ||
        loadedAt == null ||
        _loading ||
        _error != null ||
        _boardRefreshing ||
        _boardLoadingMore ||
        _pendingBoardReload) {
      return;
    }
    _homeReturnRepository.store((
      sections: _homeCatalogController.rowsForReturn(),
      board: board,
      configuration: _homeConfiguration,
      hero: _spotlightHeroOverride == null
          ? null
          : copyHomeRowForReturn(_spotlightHeroOverride!),
      heroResolutionPending: _heroSourceResolutionPending,
      cardOrientation: _homeCardOrientation,
      hideCardTitlesAndRatings: _hideHomeCardTitlesAndRatings,
      hideCatalogAddonNames: _hideHomeCatalogAddonNames,
      hideCollectionNames: _hideHomeCollectionNames,
      loadedAt: loadedAt,
      scrollOffset: _homeLastScroll,
    ), revision: _homeReturnRevision);
  }

  @override
  void dispose() {
    _preserveHomeSnapshot();
    _homePublication.dispose();
    MetadataPreferencesService.revision.removeListener(_metadataSettingsChanged);
    _catalogContinueNode.dispose();
    _catalogMoreNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mdblistContinuationController.cancelRevisionRefresh();
    _spotlightHeroNode.dispose();
    // Preserve a COMPLETED keyword search so returning to this tab restores
    // results + scroll instead of the blank prompt (the nav rebuilds us fresh).
    // A still-streaming search is NOT preserved: its batches die with this
    // instance, so the snapshot would freeze a partial set that restores
    // looking complete (no strip, no cache badges) — matching pre-streaming
    // behavior, where a mid-flight switch preserved nothing.
    if (_mode == SearchMode.keyword &&
        _kwQuery.isNotEmpty &&
        _kwResults.isNotEmpty &&
        !_kwSearching) {
      final projection = keywordResultsSnapshot(
        _keywordResultsSubscription.read(),
      );
      _keywordSnapshots.store(
        KeywordSnapshot(
          variant: _variantKey,
          query: _kwQuery,
          projection: projection,
          cache: _keywordCacheSubscription.read(),
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
      MainPageBridge.activeTab.removeListener(_onTitleSearchTabChanged);
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
    MainPageBridge.removeHomeSettingsListener(_reloadSearchCardPrefs);
    HomeRowRefreshSignal.removeListener(_queueHomeRows);
    _stremio.removeAddonsChangedListener(_onHomeAddonsChanged);
    _homeRefreshTimer?.cancel();
    IptvMediaStore.listsRevision.removeListener(_onIptvListsRevision);
    _iptvListFocus.dispose();
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
      HardwareKeyboard.instance.removeHandler(_stageHold.handleKeyEvent);
    }
    _stageTheater.dispose();
    _canvasFavFocus.dispose();
    _atriumFocusedRailKey.dispose();
    _tonightCard.dispose();
    _stageCol.dispose();
    _heroShellBinding?.dispose();
    _catalogDebounce?.cancel();
    _seriesResumeResolverSubscription.read().dispose();
    _trackerResumeSubscription.read().dispose();
    _heroMetadataSubscription.read().dispose();
    _heroSwap.dispose();
    _heroTrailerLoaderSubscription.read().dispose();
    _heroTintSubscription.read().dispose();
    _heroItem.dispose();
    _heroEnriched.dispose();
    _heroTrailer.dispose();
    _heroTrailerLoading.dispose();
    _heroTrailerShowing.dispose();
    _heroTrailerTakeover.dispose();
    _heroLiveSubscription.read().dispose();
    _heroLiveUrl.dispose();
    _heroLiveChannel.dispose();
    _heroLiveTakeover.dispose();
    _heroTint.dispose();
    _searchController.dispose();
    ProfileRuntime.scope.removeListener(_onSearchProfileChanged);
    _discoverCardSettingsSubscription.close();
    _discoverLayoutSubscription.close();
    _discoverSourceSubscription.close();
    _metadataFeatureSubscription.close();
    _catalogContinuationSubscription.close();
    _homeCatalogSubscription.close();
    _episodeArtworkSubscription.close();
    for (final subscription in _trackerAuthSubscriptions.values) {
      subscription.close();
    }
    _pikpakOnlySubscription.close();
    _boundCountsSubscription.close();
    _postPlaybackRefreshSubscription.close();
    _homeSettingsRefreshSubscription.close();
    _heroTintSubscription.close();
    _heroLiveSubscription.close();
    _heroTrailerLoaderSubscription.close();
    _seriesResumeResolverSubscription.close();
    _trackerResumeSubscription.close();
    _heroMetadataSubscription.close();
    _homeLayoutPreferenceSubscription.close();
    _heroTrailerPreferencesSubscription.close();
    _homeDefaultViewSubscription.close();
    _homeDisplaySubscription.close();
    _localContinuationSubscription.close();
    _iptvContinuationSubscription.close();
    _traktContinuationSubscription.close();
    _simklContinuationSubscription.close();
    _mdblistContinuationSubscription.close();
    _tvFavoritesSubscription.close();
    _stremioFavoritesSubscription.close();
    _iptvFavoritesSubscription.close();
    _iptvListsSubscription.close();
    _watchlistSubscription.close();
    _playlistSubscription.close();
    _continuationLayoutSubscription.close();
    _listsSubscription.close();
    _catalogSubscription.close();
    _keywordAppearanceSubscription.close();
    _keywordResultsSubscription.close();
    _keywordSearchSubscription.close();
    _keywordCacheSubscription.close();
    _titleSearch.removeListener(_publishTitleSuggestions);
    _titleSearch.dispose();
    _titleSuggestions.dispose();
    _searchFocusNode.removeListener(_onSearchFocusForSources);
    _searchFocus.dispose();
    _disposeListsNodes();
    _discSourceNode.dispose();
    _discFocused.dispose();
    if (MainPageBridge.discoverCardSettingsChanged ==
        _onDiscoverCardSettingsChanged) {
      MainPageBridge.discoverCardSettingsChanged = null;
    }
    if (widget.discoverMode && widget.isTelevision) {
      _discPreview.takeover.removeListener(_relayDiscoverChromeDim);
      _discPreview.stopObservingPlayback();
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
    _discPreview.dispose();
    _boardScroll.dispose();
    _kwScroll.dispose();
    _keywordFocus.dispose();
    _catalogSourcesBtnFocus.dispose();

    _disposeNodes();
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
  Future<void> _reloadForHomeSettings() =>
      _homeSettingsRefreshSubscription.read().run(
        isCurrent: () => mounted,
        refreshAppearance: (current) =>
            _loadSourceTextFormatting(isCurrent: current),
        refreshDisplay: (current) =>
            _loadHomeCardOrientation(isCurrent: current),
        refreshContinuation: (current) =>
            _continuationLayoutController.refresh(isCurrent: current),
        reconcileContinuation: _reconcileContinuationLayout,
        refreshTrailers: (current) =>
            _reloadHeroTrailerPrefs(isCurrent: current),
        selectDefaultView: (current) =>
            _loadHomeDefaultView(isCurrent: current),
        refreshConfiguration: (current) =>
            HomeConfigurationRefresh(
              catalog: _homeCatalogController,
              preferences: ref.read(homeCatalogPreferencesRepositoryProvider),
              collections: _homeCollectionsRepository,
              readHideWatched: ref.read(homeBoardServicesProvider).hideWatched,
            ).run(
              isCurrent: current,
              isHome: !widget.searchMode && !widget.discoverMode,
            ),
        applyConfiguration: _applyHomeConfigurationChanges,
      );

  // Reconcile nodes against accepted rows without refetching continuation data.
  void _reconcileContinuationLayout() {
    setState(() {
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

  void _applyHomeConfigurationChanges(HomeConfigurationChanges changes) {
    setState(() {});
    // Hide-watched changes row MEMBERSHIP, so it takes the full reload path.
    if (changes.reloadBoard) {
      _requestBoardReload();
    } else if (changes.reloadHero) {
      // Only the hero source moved — re-roll the reel without refetching the
      // whole board. `_load` isn't rerun here, so resolve from the addons the
      // last load cached.
      unawaited(_resolveSpotlightHeroSource(_addonsById.values.toList()));
    }
    // IPTV list rows live outside the board's section pipeline. The loader
    // reads its own extras from storage, so it can't race the reload above.
    if (changes.reloadIptv) unawaited(_loadIptvListRows());
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

  Future<void> _loadHomeDefaultView({bool Function()? isCurrent}) =>
      _homeDefaultView.load(
        isTelevision: widget.isTelevision,
        isHome: !widget.searchMode && !widget.discoverMode,
        isCurrent: () => mounted && (isCurrent?.call() ?? true),
        select: (mode) {
          if (_mode != mode) _switchMode(mode);
        },
      );

  void _commitBoardSnapshot() {
    _homeCatalogController.commit(_addonsById);
  }

  Future<void> _load({bool preserveVisibleRows = false}) async {
    _homeReturnRevision = _homeReturnRepository.revision;
    _homeLoadedAt = null;
    final previousLists = _homeSections.whereType<HomeListSection>().toList();
    HomeBoardLoad? operation;
    final keepRows =
        preserveVisibleRows &&
        _homeSections.isNotEmpty &&
        _committedBoard != null;
    final previousBoard = keepRows ? _committedBoard : null;
    final previouslyLoaded = previousBoard?.cursor ?? 0;
    final previousRows = <String, CatalogSection>{
      if (keepRows)
        for (final row in _homeSections)
          if (row is! HomeListSection) _sectionRowId(row): row,
    };
    // A superseded pagination request may never return. Its finally block is
    // generation-guarded, so it cannot clear a newer request's loading flag.
    final gen = _homeCatalogController.beginLoad();
    _homePublication.clear();
    final scope = ProfileRuntime.scope.value;
    bool current() =>
        mounted && gen == _boardLoadGen && scope == ProfileRuntime.scope.value;
    // Refreshes already preserve visible rows. Only the Android TV initial
    // Home path changes publication behavior; Search, Discover and tvOS keep
    // their existing loading contract.
    final progressive =
        PlatformUtil.isAndroidTvCached &&
        !widget.searchMode &&
        !widget.discoverMode &&
        !keepRows;
    final progress = progressive
        ? HomeLoadProgress(
            isCurrent: current,
            rowId: _sectionRowId,
            onPublish: (rows, first) {
              if (first) {
                developer.Timeline.instantSync('Home.contentPublished');
              }
              _publishHomeProgress(rows, first, gen, scope);
            },
          )
        : null;
    if (progressive) developer.Timeline.instantSync('Home.loadStarted');
    var completionGen = gen;
    var expired = false;
    _homePaginationDeferred = false;
    _progressiveHomeLoadPending = progressive;
    setState(() {
      if (!keepRows) {
        _loading = true;
        _classicAnchorTailPadding = 0;
      }
      _error = null;
    });
    unawaited(_refreshPikpakOnly());
    try {
      await runHomeLoadWithDeadline(
        retire: () {
          if (!current()) return;
          expired = true;
          _progressiveHomeLoadPending = false;
          completionGen = _homeCatalogController.retireLoad(gen) ?? gen;
          _homePublication.retireGeneration(gen, completionGen);
          // Retiring the generation stops stale batches. A refresh timeout
          // must restore the paging state belonging to the still-visible rows.
          final recovery = progress?.hasPublished == true
              ? _committedBoard
              : previousBoard;
          if (recovery != null) {
            _homeCatalogController.restore(recovery);
            _addonsById
              ..clear()
              ..addAll(recovery.addons);
          } else {
            _homeCatalogController.install(const []);
          }
        },
        load: () {
          final load = HomeBoardLoad(
            catalog: _homeCatalogController,
            preferences: ref.read(homeCatalogPreferencesRepositoryProvider),
            collections: _homeCollectionsRepository,
            services: ref.read(homeBoardServicesProvider),
          );
          operation = load;
          return load.run(
            generation: gen,
            isHome: () => !widget.searchMode && !widget.discoverMode,
            isCurrent: current,
            useSavedOrder: () => _homeRowOrderActive,
            canContinue: () => _canPageHome,
            captureBatchAcceptance: () {
              final batchScope = ProfileRuntime.scope.value;
              return () =>
                  mounted &&
                  gen == _boardLoadGen &&
                  batchScope == ProfileRuntime.scope.value;
            },
            batchSize: _kBoardBatchSize,
            previouslyLoaded: previouslyLoaded,
            previousRows: previousRows,
            previousLists: previousLists,
            progress: progress,
            onResetCatalogs: () {
              _addonsById.clear();
              _commitBoardSnapshot();
            },
            onInventory: (plan, addons) {
              // The metadata lookup is also used by Discover and detail opens.
              _addonsById
                ..clear()
                ..addAll(plan.addonsById);
              if (progress != null) {
                progress.catalogOrder(
                  _boardRefs.map(homeCatalogRowId).toList(),
                );
                _commitBoardSnapshot();
              }
              if (!widget.searchMode && !widget.discoverMode) {
                unawaited(_resolveSpotlightHeroSource(addons));
              }
            },
            onCommitBatch: _commitBoardSnapshot,
            onLateLists: (rows) => _publishHomeProgress(
              replaceHomeListRows(_homeSections, rows),
              false,
              gen,
              scope,
            ),
            onCompleted: (rows) {
              if (rows == null) {
                _commitBoardSnapshot();
                _homeLoadedAt = DateTime.now();
                return;
              }
              _homeCatalogController.replaceRows(rows);
              _commitBoardSnapshot();
              _homeLoadedAt = DateTime.now();
              setState(() => _loading = false);
              MainPageBridge.homeBoardReady.value = true;
              // Keep accepted Home data during a catalog search without
              // replacing its visible results or stealing its focus.
              if (_catalogQuery.isNotEmpty || _catalogSearching) return;
              _applySections(rows, preserveFocus: keepRows);
              _maybeAutoFocusBoard();
            },
          );
        },
      );
    } catch (e) {
      if (!mounted ||
          completionGen != _boardLoadGen ||
          scope != ProfileRuntime.scope.value) {
        return;
      }
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
        if (!keepRows && progress?.hasPublished != true) {
          _error = expired
              ? 'Home took too long to load. Please try again.'
              : e.toString();
        }
        _loading = false;
      });
      if (expired && keepRows) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text(
              "Couldn't refresh Home. Showing previous rows.",
            ),
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
      progress?.dispose();
      operation?.finish();
      if (completionGen == _boardLoadGen &&
          scope == ProfileRuntime.scope.value) {
        _homeCatalogController.finishLoad(completionGen);
        _progressiveHomeLoadPending = false;
        // Empty/failed catalogs can end without another content publication.
        // Rebuild the initial Spotlight gate so its cards fallback is shown.
        if (mounted &&
            !_spotlightEntryRevealed &&
            widget.isTelevision &&
            _homeStyleEffective == 'spotlight') {
          setState(() {});
        }
        if (mounted && !expired) {
          _maybeAutoFillBoard(resumeDeferred: true);
        }
      }
    }
  }

  /// After a batch lands, if the board still doesn't fill the viewport (so the
  /// user can't scroll to trigger more) keep pulling batches until it does or
  /// the board is exhausted. No-ops outside board mode (search sets no cursor).
  void _maybeAutoFillBoard({bool resumeDeferred = false}) {
    if (!_canPageHome || !_boardHasMore || _boardLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canPageHome || !_boardHasMore || _boardLoadingMore) return;
      if (resumeDeferred) _resumeDeferredHomePagination();
      if (_boardLoadingMore) return;
      if (!_boardScroll.hasClients) return;
      final pos = _boardScroll.position;
      if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 600) {
        _loadMoreBoard();
      }
    });
  }

  /// Fire off the next batch as the user nears the bottom of the board.
  void _onBoardScroll() {
    if (_boardScroll.hasClients) _homeLastScroll = _boardScroll.offset;
    if (!_canPageHome || !_boardHasMore || _boardLoadingMore) return;
    if (!_boardScroll.hasClients) return;
    final pos = _boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMoreBoard();
    }
  }

  /// Load and append the next batch of board rows (deduped against re-entry).
  Future<bool> _loadMoreBoard() async {
    if (!_canPageHome) return false;
    if (_boardRefreshing) {
      if (PlatformUtil.isAndroidTvCached && _boardHasMore) {
        _homePaginationDeferred = true;
      }
      return false;
    }
    if (_boardLoadingMore || _boardCursor >= _boardRefs.length) {
      return false;
    }
    // Bind this append to the load generation that owns the current cursor —
    // if a full reload lands mid-fetch, the stale batch must not append onto
    // (or advance) the fresh board.
    final gen = _boardLoadGen;
    final scope = ProfileRuntime.scope.value;
    var appended = false;
    if (!_homeCatalogController.beginPage(gen)) return false;
    setState(() {});
    try {
      final page = await _homeCatalogController.loadNextRows(
        _kBoardBatchSize,
        generation: gen,
        isCurrent: () =>
            mounted &&
            gen == _boardLoadGen &&
            scope == ProfileRuntime.scope.value,
        canContinue: () => !PlatformUtil.isAndroidTvCached || _canPageHome,
        currentAddons: () => _addonsById,
        rowId: _sectionRowId,
      );
      if (!mounted ||
          gen != _boardLoadGen ||
          scope != ProfileRuntime.scope.value) {
        return false;
      }
      if (page != null) {
        // Only fold into the live view when the board is still what's
        // shown. If a catalog search started while this batch was in flight,
        // `_sections`/`_rowNodes` now hold search results — appending board rows
        // there would corrupt the search view. They'll reappear on _restoreHome.
        if (_catalogQuery.isEmpty && !_catalogSearching) {
          if (page.appendOnly &&
              !(PlatformUtil.isAndroidTvCached &&
                  !(ModalRoute.of(context)?.isCurrent ?? true))) {
            _appendSections(page.additions);
          } else {
            _publishHomeProgress(page.rows, false, gen, scope);
          }
          appended = true;
          // A DPAD-down past the last row may be waiting on this batch —
          // classic's deferred move, and the stage layouts' rail advance.
          _maybeCompleteDeferredDown();
          _maybeCompleteStageAdvance();
        }
      }
    } finally {
      if (mounted &&
          gen == _boardLoadGen &&
          scope == ProfileRuntime.scope.value) {
        setState(() => _homeCatalogController.finishPage(gen));
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
    final scope = ProfileRuntime.scope.value;
    int currentIndex() => !mounted || scope != ProfileRuntime.scope.value ||
        _catalogQuery.isNotEmpty || _catalogSearching
        ? -1 : _sections.indexWhere((row) => identical(row, section));
    if (!_homeCatalogController.beginRowPage(section, resume: resume)) return;
    // Android TV: flip the guard silently. The setState exists to show the
    // classic row's tail spinner, but it fires on the exact keypress that
    // crossed the row-end threshold — a full-screen rebuild landing on the
    // input frame, which an Amlogic box renders as the cursor hitching every
    // time a row pages. The spinner is a nicety; the page landing repaints
    // either way.
    if (!PlatformUtil.isAndroidTvCached || resume) setState(() {});
    try {
      // Dedup against what we already have: some addons return valid ids but
      // repeat entries, and some ignore `skip` entirely. The pager advances
      // `skip` by the addon's RAW counts so paging never under-advances into a
      // false "exhausted", and with hide-watched on it tops the window up so a
      // page of watched titles doesn't end the row early.
      final page = await _homeCatalogController.fetchRowPage(
        (section.addon, section.catalog),
        skip: section.nextSkip,
        existingIds: section.items.map((item) => item.id),
        isCurrent: () => currentIndex() >= 0,
      );
      // Progressive arrivals can move the SAME row. Only a removed/replaced
      // row or a changed session invalidates its page, not a new numeric index.
      final index = currentIndex();
      if (index < 0) return;
      _homeCatalogController.acceptRowPage(section, page);
      final fresh = page.items;
      if (fresh.isEmpty) return;
      // Grow this row's focus nodes in lockstep with the new items.
      final nodes = _rowNodes[index];
      final base = nodes.length;
      for (var i = 0; i < fresh.length; i++) {
        nodes.add(FocusNode(debugLabel: 'search_r${index}_c${base + i}'));
      }
      setState(() => _homeCatalogController.appendRowItems(section, fresh));
      // A DPAD-right that ran off the end of this row may be waiting on it.
      _maybeCompleteStageRight();
      unawaited(_refreshBoundSources());
    } catch (_) {
      // Transient fetch failure — leave the row as-is so a later scroll retries.
    } finally {
      if (currentIndex() >= 0) {
        setState(() => _homeCatalogController.finishRowPage(section));
      } else {
        _homeCatalogController.finishRowPage(section);
      }
    }
  }

  /// Stable progress key, including supported native provider identities.
  String? _imdbOf(StremioMeta item) {
    final id = item.progressId ?? (item.id.startsWith('tt') ? item.id : null);
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
  Future<void> _refreshBoundSources() {
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
    return _boundCountsController.load(
      ids: items.map(_imdbOf),
      isCurrent: () => mounted,
      onAccepted: () => setState(() {}),
    );
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() => _pikpakOnlyController.load(
    isCurrent: () => mounted,
    onChanged: () => setState(() {}),
  );

  /// Load the Continue Watching row from the shared local store. Mirrors
  /// Home's join (item list + per-title playback progress) but is read-only —
  /// it never writes, so Home's row is untouched. Safe to call repeatedly
  /// (e.g. after returning from a detail/playback).
  Future<void> _loadContinueWatching() => _localContinuationController.load(
    isCurrent: () => mounted,
    onProgressSourceChanged: () => setState(() {}),
    beforeEnabledRows: _ensureCwMergeFlags,
    beforeRows: (next) {
      // Keep the same nodes on refresh. Merged mode uses the movies slot for
      // every item; disabled rows release their nodes before data publication.
      _syncCwNodes(
        _cwMovieNodes,
        _cwMergeLocal ? next.data.items.length : next.movies.length,
        'movie',
      );
      _syncCwNodes(
        _cwSeriesNodes,
        _cwMergeLocal ? 0 : next.series.length,
        'series',
      );
    },
    onRows: (next, current) {
      setState(
        () => _episodeArtworkController.clear(HomeEpisodeArtworkSource.local),
      );
      if (!next.enabled) return;
      unawaited(
        _enrichCwEpisodeArtwork(
          refs: next.data.episodeRefs,
          source: HomeEpisodeArtworkSource.local,
          isCurrent: current,
        ),
      );
      _maybeAutoFocusBoard();
    },
  );

  void _onLocalCompletionChanged() {
    if (!mounted || widget.searchMode || widget.discoverMode) return;
    unawaited(_loadContinueWatching());
  }

  /// Load the IPTV Continue Watching shelves (Xtream VOD movies + series) from
  /// the player's own watch history. Independent of [_loadContinueWatching] —
  /// different data source, different (non-IMDb) identity — but follows the same
  /// token-guard + node-sync discipline so a slow reload can't clobber a newer
  /// one or drop the focus node the user is sitting on.
  Future<void> _loadIptvContinueWatching() {
    // Dedicated Search does not load IPTV shelves, including playback returns.
    if (widget.searchMode) return Future<void>.value();
    return _iptvContinuationController.load(
      isCurrent: () => mounted,
      beforeRows: (next) {
        _syncCwNodes(_iptvCwMovieNodes, next.movies.length, 'iptv-movie');
        _syncCwNodes(_iptvCwSeriesNodes, next.series.length, 'iptv-series');
      },
      onRows: () {
        setState(() {});
        _maybeAutoFocusBoard();
      },
    );
  }

  int? _iptvRemainingMinutes(String routeKey) =>
      _iptvContinuation.remainingMinutes[routeKey];

  late final ProviderSubscription<HomeEpisodeArtwork>
  _episodeArtworkSubscription;
  late final HomeEpisodeArtworkController _episodeArtworkController;

  Future<void> _enrichCwEpisodeArtwork({
    required Map<String, HomeEpisodeReference> refs,
    required HomeEpisodeArtworkSource source,
    required bool Function() isCurrent,
  }) => _episodeArtworkController.load(
    source: source,
    refs: refs,
    isCurrent: () => mounted && isCurrent(),
    onChanged: () => setState(() {}),
  );

  /// Open an IPTV Continue Watching card: a series routes to the merged Xtream
  /// series page, a movie resumes playback. Both go through [IptvCwRouter];
  /// [_playedSinceRefresh] latches so the return refresh rebuilds the shelves.
  Future<void> _openIptvCwItem(StremioMeta item) async {
    final entry = _iptvCwByKey[item.id];
    if (entry == null) return;
    _markPlaybackStarted();
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
  List<HomeFavoriteRowRef> get _favRowKinds => [
    if (_watchlistMoviesVisible) const HomeFavoriteRowRef(HomeFavoriteKind.watchlistMovies),
    if (_watchlistSeriesVisible) const HomeFavoriteRowRef(HomeFavoriteKind.watchlistSeries),
    if (_playlistFavVisible) const HomeFavoriteRowRef(HomeFavoriteKind.playlist),
    if (_tvFavVisible &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.debrifyTv))
      const HomeFavoriteRowRef(HomeFavoriteKind.debrify),
    if (_stvFavVisible &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.stremioTv))
      const HomeFavoriteRowRef(HomeFavoriteKind.stremio),
    if (_iptvFavVisible && ProfilePolicyGuard.allowsSync(ProfileFeature.iptv))
      const HomeFavoriteRowRef(HomeFavoriteKind.iptv),
    if (_catalogQuery.isEmpty &&
        !_catalogSearching &&
        ProfilePolicyGuard.allowsSync(ProfileFeature.iptv))
      for (var i = 0; i < _iptvListRows.length; i++)
        if (_iptvListRows[i].channels.isNotEmpty) HomeFavoriteRowRef(HomeFavoriteKind.iptv, i),
  ];

  int get _favRowCount => _favRowKinds.length;
  bool get _anyFavVisible => _favRowKinds.isNotEmpty;

  String _favRowId(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) {
      return HomeExtraRowIds.iptvList(_iptvListRows[ref.list].listId);
    }
    return switch (ref.kind) {
      HomeFavoriteKind.watchlistMovies => 'watchlist:movies',
      HomeFavoriteKind.watchlistSeries => 'watchlist:series',
      HomeFavoriteKind.playlist => 'fav:playlist',
      HomeFavoriteKind.debrify => 'fav:debrify',
      HomeFavoriteKind.stremio => 'fav:stremio',
      HomeFavoriteKind.iptv => 'fav:iptv',
    };
  }

  String _sectionRowId(CatalogSection section) => section is HomeListSection
      ? section.rowId
      : section is HomeCollectionSection
      ? section.rowId
      : '${section.addon.id}:${section.catalog.type}:${section.catalog.id}';

  /// The focus-node list backing a favourites row of the given [ref].
  List<FocusNode> _favNodesFor(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) {
      return _iptvListFocus.nodesFor(_iptvListRows[ref.list].listId);
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return _watchlistMovieNodes;
      case HomeFavoriteKind.watchlistSeries:
        return _watchlistSeriesNodes;
      case HomeFavoriteKind.iptv:
        return _iptvFavNodes;
      case HomeFavoriteKind.debrify:
        return _tvFavNodes;
      case HomeFavoriteKind.stremio:
        return _stvFavNodes;
      case HomeFavoriteKind.playlist:
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
    if (!_boardCanAdvance && _focusCatalogContinuation()) return;
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
  Future<void> _loadTvFavorites() => _tvFavoritesController.load(
    isCurrent: () => mounted,
    onRows: (hasFavoriteIds) {
      setState(() {});
      _syncTvFavNodes();
      if (hasFavoriteIds) _maybeAutoFocusBoard();
    },
  );

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

  /// Reload starred Stremio TV channels without replacing newer row data.
  Future<void> _loadStremioTvFavorites() => _stremioFavoritesController.load(
    isCurrent: () => mounted,
    onRows: (hasFavoriteIds) {
      setState(() {});
      _syncStvFavNodes();
      if (hasFavoriteIds) _maybeAutoFocusBoard();
    },
  );

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
  StremioTvNowPlaying? _stvNowPlaying(HomeStremioFavorite channel) {
    if (channel.items.isEmpty) return null;
    return _stremioFavoritesController.playingAt(channel, DateTime.now());
  }

  /// Open a Stremio TV channel (same path the Home screen uses): hand off to the
  /// live player if it's mounted, else queue an auto-play and switch tabs.
  void _playStremioTvChannel(HomeStremioFavorite channel) {
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(MainTab.stremioTv);
  }

  /// Reload the live-only favourites projection; custom lists retain their own mapping.
  Future<void> _loadIptvFavorites() => _iptvFavoritesController.load(
    isCurrent: () => mounted,
    onRows: (hasFavorites) {
      setState(() {});
      _syncIptvFavNodes();
      if (hasFavorites) _maybeAutoFocusBoard();
    },
  );

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

  /// Apply a complete custom-list snapshot while retaining surviving row nodes.
  Future<void> _loadIptvListRows() => _iptvListsController.load(
    isCurrent: () => mounted,
    beforeRows: _iptvListFocus.reconcile,
    onRows: () {
      setState(() {});
      _maybeAutoFocusBoard();
    },
  );

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

  Future<void> _loadMyWatchlist() => _watchlistController.load(
    isCurrent: () => mounted,
    onRows: () {
      setState(() {});
      _syncMyWatchlistNodes();
      _maybeAutoFocusBoard();
    },
  );

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

  /// Refresh accepted playlist rows, posters, favourite flags and progress.
  Future<void> _loadPlaylistFavorites() => _playlistController.load(
    isCurrent: () => mounted,
    onRows: () {
      setState(() {});
      _syncPlaylistFavNodes();
      _maybeAutoFocusBoard();
    },
  );

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

  /// The full action menu for a playlist item — the same set of actions as the
  /// Home playlist section (Home is being phased out, so this row is a complete
  /// playlist manager on its own). Rendered with the post-torrent Neon action
  /// sheet: bottom sheet on phones, centered card on desktop/TV, with the
  /// first three actions as primary pills.
  Future<void> _onPlaylistItemTap(HomePlaylistItem selected) async {
    if (!mounted) return;
    final item = selected.toLegacyItem();
    final playlist = _playlistController.current;
    final isFavorited = playlist.isFavorite(selected);
    final hasProgress = playlist.hasProgress(selected);
    final isCollection = selected.isCollection;
    final title = selected.title;

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
    if (addonId == NativeSeriesMetadataService.addon.id) {
      return NativeSeriesMetadataService.addon;
    }
    for (final addon in _addonsById.values) {
      if (addon.sourceBindingKey == addonId || addon.portableConfigurationKey == addonId) return addon;
    }
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
      if (section.simklList != null) {
        _openSimklItem(item, heroTag: heroTag);
        return;
      }
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
                fromHome: true,
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
    _openItem(item, item.sourceAddon ?? _addonForContinue(_cwAddonId[item.imdbId]));
  }

  /// Long-press quick-play for a Continue Watching title — resumes directly
  /// (series resume the last-played episode) without opening the detail.
  void _onContinuePlay(StremioMeta item) {
    _onCatalogPlay(item, item.sourceAddon ?? _addonForContinue(_cwAddonId[item.imdbId]));
  }

  /// Open a plain Simkl-list title (Discover's Simkl Trending/watchlist lists) —
  /// a normal catalog detail, no resume. The CW list uses [_openSimklCwItem]
  /// instead, so a title browsed fresh here never opens mid-episode.
  void _openSimklItem(StremioMeta item, {String? heroTag}) {
    _openItem(item, NativeSeriesMetadataService.addonForItem(item), heroTag: heroTag);
  }

  /// Quick-play a plain Simkl-list title like any other catalog item (no
  /// resume). The CW list uses [_playSimklCwItem].
  void _playSimklItem(StremioMeta item) {
    _onCatalogPlay(item, NativeSeriesMetadataService.addonForItem(item));
  }

  // ── Trakt Continue Watching ───────────────────────────────────────────────

  /// Fetch the Trakt "Continue Watching" rows (in-progress movies + up-next
  /// episodes) from the connected account. Uses Trakt's intent-aware Up Next
  /// feed plus paged playback checkpoints. Runs on init / integration change,
  /// post-playback, and a throttled app resume — never on every rebuild.
  /// Token-guarded against overlap; hides the rows when Trakt isn't connected.
  /// [refreshBound] runs a bound-source refresh at the end; pass false when the
  /// caller already refreshes bound sources itself (avoids a double pass).
  Future<void> _loadTraktContinueWatching({bool refreshBound = true}) =>
      _traktContinuationController.load(
        attemptedAt: DateTime.now(),
        isCurrent: () => mounted,
        beforeConnectedRows: _ensureCwMergeFlags,
        beforeRows: (next) {
          _syncCwNodes(
            _traktMovieNodes,
            _cwMergeTrakt ? next.all.length : next.movies.length,
            'tmovie',
          );
          _syncCwNodes(
            _traktSeriesNodes,
            _cwMergeTrakt ? 0 : next.series.length,
            'tseries',
          );
        },
        onRows: (next, connected, hadRows, current) {
          setState(
            () =>
                _episodeArtworkController.clear(HomeEpisodeArtworkSource.trakt),
          );
          if (!connected) return;
          unawaited(
            _enrichCwEpisodeArtwork(
              refs: next.episodeRefs,
              source: HomeEpisodeArtworkSource.trakt,
              isCurrent: current,
            ),
          );
          _maybeAutoFocusBoard();
          if (!hadRows) _maybeAnnounceTraktRows();
          if (refreshBound) unawaited(_refreshBoundSources());
        },
        onFailure: (error, accepted) {
          debugPrint(
            'SearchScreen: Trakt continue-watching load failed: $error',
          );
          if (accepted) setState(() {});
        },
      );

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
    if (!_catalogNavigationCurrent()) return;
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
    final resume = await _seriesResumeRepository.traktSelection(
      item,
      cached: cwItem,
      isCurrent: _catalogNavigationCurrent,
    );
    if (!_catalogNavigationCurrent()) return;
    final sel = resume?.sel;
    if (sel == null) {
      _snack("Couldn't resolve where to resume \"${item.name}\".");
      return;
    }
    _playSelection(sel);
  }

  Future<bool> _removeLocalHistory(String id) async {
    if (!_catalogNavigationCurrent()) return false;
    return ref
        .read(homeLocalHistoryRemovalProvider(_profileSessionOwner))
        .remove(id, isCurrent: _catalogNavigationCurrent);
  }

  /// Detail-screen action for a Continue Watching title. Only handles removal;
  /// closes its own detail and lets the route return callback refresh the row.
  Future<void> _handleContinueDetailAction(
    TraktItemMenuAction action,
    String imdbId,
    HomeDetailRoute detailRoute,
  ) async {
    if (!detailRoute.isActive ||
        action != TraktItemMenuAction.removeFromPlayback) {
      return;
    }
    if (!await _removeLocalHistory(imdbId) || !mounted || !detailRoute.isActive) {
      return;
    }
    detailRoute.closeIfCurrent();
    _snack('Removed from Continue Watching');
  }

  /// Detail-screen action for a Trakt Continue Watching title: delete the
  /// title's playback entries (and watch history, so shows don't reappear via
  /// "Up Next") on Trakt, then pop the detail and reload the Trakt rows —
  /// mirroring the old home screen's remove flow.
  ///
  /// Row-menu removals have no detail route. Detail actions carry their exact
  /// route so a delayed response cannot pop a newer page.
  Future<void> _removeFromTraktContinueWatching(
    String imdbId, {
    HomeDetailRoute? detailRoute,
  }) async {
    bool current() =>
        _catalogNavigationCurrent() && (detailRoute?.isActive ?? true);
    if (!current()) return;
    final cwItem = _traktByImdb[imdbId];
    if (cwItem == null) return;
    final removed = await ref
        .read(homeTraktHistoryRemovalProvider(_profileSessionOwner))
        .remove(cwItem, isCurrent: current);
    if (!mounted || removed == null || !current()) return;
    if (!removed) {
      _snack('Failed to remove from Trakt Continue Watching');
      return;
    }
    detailRoute?.closeIfCurrent();
    _snack('Removed from Trakt Continue Watching');
    await _loadTraktContinueWatching(refreshBound: false);
  }

  // ── Continue Watching card menu (long-press / hold-OK) ────────────────────

  final _continueWatchingActions = HomeContinueWatchingActions();

  Future<void> _openCwCardMenu(
    HomeContinuationRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) async {
    if (!_catalogNavigationCurrent()) return;
    final readPreference = ref.read(
      homeCwHoldPreferenceProvider(_profileSessionOwner),
    );
    await _continueWatchingActions.open(
      context: context,
      row: row,
      item: item,
      pikpakOnly: _pikpakOnly,
      isTelevision: () => widget.isTelevision,
      isCurrent: _catalogNavigationCurrent,
      readHoldToQuickPlay: readPreference,
      refocusAfterRemoval: () => _refocusAfterCwRemoval(cwIndex, col),
    );
  }

  /// Put TV focus back on the board after a removal: the card that had it is
  /// gone (and its FocusNode with it, if the row shrank), which would otherwise
  /// leave the remote dead until the global reclaim listener notices.
  void _refocusAfterCwRemoval(int cwIndex, int col) {
    if (!widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_catalogNavigationCurrent()) return;
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
    if (!await _removeLocalHistory(imdbId) || !mounted) return;
    _snack('Removed from Continue Watching');
    await _loadContinueWatching();
  }

  /// Remove a Trakt Continue Watching title from the row itself — the detail
  /// page's flow minus the pop.
  Future<void> _removeTraktCwItem(StremioMeta item) async {
    final imdbId = _imdbOf(item);
    if (imdbId == null) return;
    await _removeFromTraktContinueWatching(imdbId);
  }

  /// Remove a Simkl Continue Watching title from the row itself. Routes through
  /// the shared [handleSimklMenuAction] the detail sheet uses (which shows its
  /// own result snackbar), so a series is moved to On Hold and its paused
  /// session cleared, and a movie just loses the session.
  Future<void> _removeSimklCwItem(StremioMeta item) async {
    if (!_catalogNavigationCurrent()) return;
    await handleSimklMenuAction(
      context,
      item,
      SimklItemMenuAction.removeFromContinueWatching,
      isCurrent: _catalogNavigationCurrent,
      removeContinueWatching: () => ref
          .read(homeSimklHistoryRemovalProvider(_profileSessionOwner))
          .remove(
            item.progressId ?? item.id,
            item.type,
            isCurrent: _catalogNavigationCurrent,
          ),
    );
    if (!_catalogNavigationCurrent()) return;
    await _loadSimklContinueWatching(refreshBound: false);
  }

  /// Remove an IPTV Continue Watching card: a movie drops its own history +
  /// resume entry, a series drops every episode's (the card collapses them, so
  /// leaving one behind would just rebuild it).
  Future<void> _removeIptvCwItem(StremioMeta item) async {
    if (!_catalogNavigationCurrent()) return;
    final entry = _iptvCwByKey[item.id];
    if (entry == null) return;
    final removed = await ref
        .read(homeIptvHistoryRemovalProvider(_profileSessionOwner))
        .remove(entry, isCurrent: _catalogNavigationCurrent);
    if (!removed) return;
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
  Future<void> _loadSimklContinueWatching({bool refreshBound = true}) =>
      _simklContinuationController.load(
        isCurrent: () => mounted,
        ensureLayout: _ensureCwMergeFlags,
        beforeRows: (next) {
          _syncCwNodes(
            _simklMovieNodes,
            _cwMergeSimkl ? next.all.length : next.movies.length,
            'smovie',
          );
          _syncCwNodes(
            _simklSeriesNodes,
            _cwMergeSimkl ? 0 : next.series.length,
            'sseries',
          );
        },
        onRows: (next, hadRows, current) {
          setState(
            () =>
                _episodeArtworkController.clear(HomeEpisodeArtworkSource.simkl),
          );
          unawaited(
            _enrichCwEpisodeArtwork(
              refs: next.episodeRefs,
              source: HomeEpisodeArtworkSource.simkl,
              isCurrent: current,
            ),
          );
          _maybeAutoFocusBoard();
          if (!hadRows) _maybeAnnounceSimklRows();
          if (refreshBound) unawaited(_refreshBoundSources());
        },
      );

  /// Open a Simkl Continue Watching title as a detail page. For a series, scroll
  /// the episodes panel to the paused episode (the same path the Calendar uses);
  /// resume itself is handled by the detail's three-way resume when Simkl is
  /// connected. No `isTraktSource` flag — this is a plain, source-neutral open.
  void _openSimklCwItem(StremioMeta item) {
    final cw = _simklByImdb[_simklCardKey(item)];
    _openItem(
      item,
      NativeSeriesMetadataService.addonForItem(item),
      initialSeason: (cw != null && !cw.isMovie) ? cw.season : null,
      initialEpisode: (cw != null && !cw.isMovie) ? cw.episode : null,
    );
  }

  /// Resume a Simkl Continue Watching title directly (quick-play): builds a
  /// selection carrying the paused season/episode + Simkl progress percent and
  /// plays it, mirroring the Trakt quick-play.
  Future<void> _playSimklCwItem(StremioMeta item) async {
    if (!_catalogNavigationCurrent()) return;
    _activeAddonId = NativeSeriesMetadataService.addonForItem(item).id;
    _playbackArtwork.capture(item);
    final cw = _simklByImdb[_simklCardKey(item)];
    if (cw == null) {
      // Not in the CW map (a See-All grid title that fell out of the list) —
      // play it like a plain catalog title; three-way resume still applies.
      await _onCatalogPlay(item, NativeSeriesMetadataService.addonForItem(item));
      return;
    }
    _playSelection(cw.selection);
  }

  /// Desktop "See All" for the Simkl Continue Watching rows — reuses the generic
  /// Continue Watching grid, seeded with the paused-order list + progress.
  void _openSimklCwSeeAll([String initialCategory = 'all']) {
    _pushCwSeeAll(
      title: 'Simkl Continue Watching',
      initialCategory: initialCategory,
      items: _simklAll,
      progressOf: (m) => _cwCardProgress(HomeContinuationKind.simkl, m),
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
  }) => _mdblistContinuationController.load(
    enabled: kMdblistEnabled,
    force: force,
    refreshBound: refreshBound,
    isCurrent: () => mounted,
    ensureLayout: _ensureCwMergeFlags,
    now: DateTime.now,
    trace: debugPrint,
    onDisabled: () => setState(() {}),
    beforeRows: (next) {
      _syncCwNodes(
        _mdblistMovieNodes,
        _cwMergeMdblist ? next.all.length : next.movies.length,
        'mdbmovie',
      );
      _syncCwNodes(
        _mdblistSeriesNodes,
        _cwMergeMdblist ? 0 : next.series.length,
        'mdbseries',
      );
    },
    onRows: (next, hadRows) {
      setState(() {});
      _maybeAutoFocusBoard();
      if (!hadRows) _maybeAnnounceMdblistRows();
      if (refreshBound) unawaited(_refreshBoundSources());
    },
  );

  void _onMdblistPlaybackRevision() {
    if (widget.searchMode || widget.discoverMode) return;
    unawaited(
      _mdblistContinuationController.refreshAfterRevision(
        isCurrent: () => mounted,
        isVisible: () => ModalRoute.of(context)?.isCurrent ?? true,
        wait: (duration) => Future<void>.delayed(duration),
        reload: () =>
            _loadMdblistContinueWatching(refreshBound: false, force: true),
      ),
    );
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
    if (!_catalogNavigationCurrent()) return;
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
    final removed = await _mdblistContinuationController.remove(
      _imdbOf(item),
      isCurrent: _catalogNavigationCurrent,
    );
    if (!mounted ||
        !removed ||
        _profileSessionOwner != ProfileSessionMemory.captureOwner()) {
      return;
    }
    _snack('Removed from MDBList Continue Watching');
    await _loadMdblistContinueWatching();
  }

  void _openMdblistCwSeeAll([String initialCategory = 'all']) {
    _pushCwSeeAll(
      title: 'MDBList Continue Watching',
      initialCategory: initialCategory,
      items: _mdblistAll,
      progressOf: (m) => _cwCardProgress(HomeContinuationKind.mdblist, m),
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
  void _applySections(List<CatalogSection> sections, {
    bool preserveFocus = false,
    bool incremental = false,
  }) {
    String? anchor;
    double? anchorHeight;
    double anchorTailPadding = 0;
    List<String> previousOrder = const [];
    if (incremental && _homeStyleEffective == 'classic') {
      final rails = _classicHomeRails;
      for (final rail in rails) {
        if (rail.traktSkeletonIndex >= 0) continue;
        final focused = _canvasRailNodes(rail).where((node) => node.hasFocus);
        if (focused.isEmpty) continue;
        anchor = _canvasRailRowId(rail);
        // Newly published rows are catalog/list/collection rows even if the
        // focused anchor is Continue Watching or a favourite in a custom order.
        if (rail.sectionIndex != null) {
          anchorHeight = homeRowHeight(focused.first.context,
            ValueKey('board-reveal-$_boardGen-$anchor'));
        }
        anchorHeight ??= _classicCatalogRowExtent(
          focused.first.context ?? context,
          section: rail.sectionIndex == null
              ? null
              : _sections[rail.sectionIndex!],
        );
        break;
      }
      previousOrder = rails.map(_canvasRailRowId).toList();
      if (anchor != null && _boardScroll.hasClients &&
          _boardScroll.position.maxScrollExtent <= 0) {
        // A short first batch leaves unused viewport space below its rows.
        // Retain that space as tail padding when rows are inserted above the
        // anchor, otherwise scroll physics clamps away the preserved offset.
        final heights = <double>[];
        for (final rail in rails) {
          if (rail.traktSkeletonIndex >= 0) break;
          final nodes = _canvasRailNodes(rail);
          final height = nodes.map((node) => homeRowHeight(node.context,
            ValueKey('board-reveal-$_boardGen-${_canvasRailRowId(rail)}')))
            .whereType<double>().firstOrNull;
          if (height == null) break;
          heights.add(height);
        }
        if (heights.length == rails.length) {
          anchorTailPadding = max(_classicAnchorTailPadding,
            _boardScroll.position.viewportDimension - 38 -
                heights.fold<double>(0, (sum, height) => sum + height));
        }
      }
    }
    // Streaming arrivals are not a fresh board: preserve keyed row elements,
    // entrance state, and any pending user-directed move to the next rail.
    if (!incremental) {
      _boardGen++;
      _boardAppliedAt = DateTime.now();
      // Rail keys are content-addressed by stable Home-row id, so a reload can
      // preserve the active rail even when its numeric section index changes.
      _stageDeferredAdvance.invalidateForBoardReseed();
      _stageFocusRequests.invalidate();
    }
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
      final columns = {
        if (incremental)
          for (var i = 0; i < _sections.length; i++)
            _sectionRowId(_sections[i]): _rowCol[i],
      };
      _rowNodes..clear()..addAll(nextNodes);
      _rowCol
        ..clear()
        ..addAll({
          for (var i = 0; i < sections.length; i++)
            if (columns[_sectionRowId(sections[i])] case final column?) i: column,
        });
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
    setState(() {
      _sections = sections;
      if (anchor != null && anchorHeight != null) {
        final nextOrder = _classicHomeRails.map(_canvasRailRowId).toList();
        if (nextOrder.takeWhile((id) => id != anchor)
            .any((id) => !previousOrder.contains(id))) {
          _classicAnchorTailPadding = max(_classicAnchorTailPadding, anchorTailPadding);
        }
        preserveHomeInsertionAnchor(scroll: _boardScroll,
          previous: previousOrder,
          next: nextOrder,
          anchor: anchor, extentOf: (_) => anchorHeight!);
      }
    });
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
        _heroPreviewPolicy.allowNewHero();
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
    // Reclaim TV focus before disposing the previous result nodes.
    if (widget.isTelevision && !_searchFocusNode.hasFocus) {
      _searchFocusNode.requestFocus();
    }
    final completion = _catalogController.search(
      query,
      batchResults: widget.isTelevision,
    );
    _applySections(const []);
    final result = await completion;
    if (!mounted || result == CatalogSearchCompletion.stale) return;
    if (result == CatalogSearchCompletion.failed) {
      _searchSubmitFocus.cancel();
      return;
    }
    if (widget.isTelevision) {
      // One stable batch, including empty results. Phone/desktop rows arrive
      // through the subscription without replacing already focused rows.
      _applySections(_catalogState.rows.map(catalogSearchSection).toList());
      if (_rowNodes.isNotEmpty && _rowNodes.first.isNotEmpty) {
        _completeSearchSubmitFocus(_rowNodes.first.first);
      } else {
        _searchSubmitFocus.cancel();
      }
    }
  }

  /// Cancel any pending search and return to the homepage board.
  void _restoreHome() {
    _catalogController.clear();
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
    if (_searchFocus.hasFocus ||
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
    _heroPreviewPolicy.resetAttempt();
    if (widget.searchMode) {
      _searchFocusNode.requestFocus();
    }
  }

  void _focusContent() => _searchFocus.focusContent(
    discoverMode: widget.discoverMode,
    searchMode: widget.searchMode,
    isTelevision: widget.isTelevision,
    mode: _mode,
    discoverSource: _discSourceNode,
    keywordToolbar: _kwToolbarVisible ? _kwToolbarNodes.first : null,
    listsResult: _listsResults.isNotEmpty && _listsNodes.isNotEmpty
        ? _listsNodes.first
        : null,
    catalogResult:
        _catalogQuery.isNotEmpty &&
            _rowNodes.isNotEmpty &&
            _rowNodes.first.isNotEmpty
        ? _rowNodes.first.first
        : null,
    focusCatalogShelf: _spotlightKey.currentState == null
        ? null
        : () => _spotlightKey.currentState!.focusShelf(0),
    topBoardNode: _topBoardFocusNode,
    loading: _loading,
    focusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
  );

  void _focusModeToggle() =>
      _searchFocus.focusMode(_mode, compact: _useCompactModeMenu);

  bool get _useCompactModeMenu => SearchFocusController.useCompactModeMenu(
    listsEnabled: kMdblistEnabled,
    isTelevision: widget.isTelevision,
    width: MediaQuery.sizeOf(context).width,
  );

  void _focusSearchFieldAtEnd() =>
      _searchFocus.focusFieldAtEnd(_searchController);

  /// Whether the keyword results toolbar (Sort/Filters/Sources/…) is on-screen,
  /// so focus can route into it between the search field and the result rows.
  bool get _kwToolbarVisible =>
      _mode == SearchMode.keyword &&
      !_kwLoading &&
      _kwError == null &&
      _kwQuery.isNotEmpty;

  /// Whether the pre-search "Sources" button is on-screen — the empty keyword
  /// state, before a query. It's the only focusable content then, so DPAD-down
  /// from the search field must land on it (see the field's key handler).
  bool get _kwSourcesButtonVisible =>
      _mode == SearchMode.keyword &&
      !_kwLoading &&
      _kwError == null &&
      _kwQuery.isEmpty;

  /// Catalog-mode twin of [_kwSourcesButtonVisible]: the Sources button shown
  /// on the empty catalog prompt (Search tab, no query yet, not mid-search).
  bool get _catalogSourcesButtonVisible =>
      _mode == SearchMode.catalog &&
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
  late String _tvHomeStyle;
  late final ProviderSubscription<HomeLayoutPreference>
  _homeLayoutPreferenceSubscription;

  // Landscape default matches the stored default, so a fresh boot doesn't
  // flash portrait rows before the async pref read lands.
  late final HomeDisplayPreferencesController _homeDisplayController;
  late final ProviderSubscription<HomeDisplayPreferences>
  _homeDisplaySubscription;
  HomeDisplayPreferences get _homeDisplay => _homeDisplayController.current;
  HomeCardOrientation get _homeCardOrientation => _homeDisplay.orientation;
  bool get _hideHomeCardTitlesAndRatings => _homeDisplay.hideTitlesAndRatings;
  bool get _hideHomeCatalogAddonNames => _homeDisplay.hideCatalogAddonNames;
  late final KeywordAppearanceController _keywordAppearanceController;
  late final ProviderSubscription<SourceAppearance>
  _keywordAppearanceSubscription;

  Future<void> _loadSourceTextFormatting({bool Function()? isCurrent}) =>
      _keywordAppearanceController.load(
        isCurrent: () => mounted && (isCurrent?.call() ?? true),
        onAccepted: () => setState(() {}),
      );

  bool get _hideHomeCollectionNames => _homeDisplay.hideCollectionNames;
  bool get _spotlightFocusDetails => _homeDisplay.spotlightFocusDetails;
  bool get _homeAnimationsEnabled => _homeDisplay.animationsEnabled;
  String get _homeAnimationStyle => _homeDisplay.animationStyle;

  bool get _homeLandscapeCards =>
      _homeCardOrientation == HomeCardOrientation.landscape;

  double get _homeArtPosterCaptionBand =>
      _hideHomeCardTitlesAndRatings ? 0 : HomeArtCaption.band(context);

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
      _mode != SearchMode.catalog ||
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

  bool get _stageActive => isHomeStageLayout(_homeStyleEffective);

  bool get _stageWantsAmbient => homeStageWantsAmbient(_homeStyleEffective);

  // Live channel previews remain available on every stage, including Mosaic.
  bool get _stageWantsLivePreview => _stageActive;

  bool get _stagePublishesShellArt =>
      homeStagePublishesShellArt(_homeStyleEffective);

  bool get _theaterEligible => homeStageTheaterEligible(_homeStyleEffective);

  late final HomeStageFocusRequests _stageFocusRequests = HomeStageFocusRequests(
    isMounted: () => mounted,
    readStyle: () => _homeStyleEffective,
  );

  late final HomeStageDeferredAdvance _stageDeferredAdvance =
      HomeStageDeferredAdvance(
        stageActive: () => _stageActive,
        maxAge: _pendingDownMaxAge,
      );

  late final HomeStageDeferredRight _stageDeferredRight = HomeStageDeferredRight(
    currentRail: () => _canvasRailKey,
    stageActive: () => _stageActive,
    scheduleFocus: _stageFocusRequests.schedule,
    maxAge: _pendingDownMaxAge,
  );

  void _maybeCompleteStageRight() {
    _stageDeferredRight.complete((key, column) {
      final rails = _stageRails;
      final i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
      if (i < 0) return null;
      final nodes = _canvasRailNodes(rails[i]);
      if (column >= nodes.length) return null;
      return (nodes[column].context?.mounted ?? false) ? nodes[column] : null;
    });
  }

  /// Every piece of per-layout navigation state, cleared as one. Called on a
  /// real layout transition (either the picker or the saved pref landing at
  /// cold start) — never partially, or a layout inherits a rail/zone/column
  /// that means something else in its own geometry.
  void _resetStageNavigation() {
    _canvasFocusSeeded = false;
    _stageTheater.reset();
    _canvasFavFocus.value = null;
    _canvasRailKey = null;
    _canvasCols.clear();
    _tonightZoneIsQueue = true;
    _tonightQueueCol = 0;
    _tonightQueueKey = null;
    _atriumFocusedRailKey.value = null;
    _tonightCard.value = null;
    _stageCol.value = 0;
    _stageDeferredAdvance.reset();
    _stageDeferredRight.reset();
    _stageHold.reset();
    _stageFocusRequests.invalidate();
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

  Future<void> _loadTvHomeStyle() =>
      _homeLayoutPreferenceSubscription.read().load(
        isCurrent: () => mounted,
        currentStyle: () => _tvHomeStyle,
        transition: _applyStageTransition,
      );

  Future<void> _loadHomeCardOrientation({bool Function()? isCurrent}) async {
    final changed = await _homeDisplayController.load(
      isCurrent: () => mounted && (isCurrent?.call() ?? true),
    );
    if (mounted && changed) setState(() {});
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
  /// [HomeFavoriteFocus]). A ValueNotifier — NOT setState — so scrubbing along
  /// a favourites rail repaints only the stage layers that listen (art +
  /// identity), never the whole board (the hero pipeline's own pattern).
  final ValueNotifier<HomeFavoriteFocus?> _canvasFavFocus =
      ValueNotifier<HomeFavoriteFocus?>(null);

  /// A Canvas favourites cell took focus: remember the column, stop any
  /// catalog trailer machinery (a PENDING hero swap firing later would start
  /// a full-bleed trailer of an unrelated title under favourites browsing),
  /// drive the live preview for IPTV, and hand the stage the favourite's own
  /// art + name.
  void _canvasFavFocused(
    String railKey,
    int col,
    HomeFavoriteFocus focus, {
    IptvChannel? liveChannel,
  }) {
    _canvasCols[railKey] = col;
    _stageCol.value = col;
    // Atrium's two-row window needs to know which row owns focus (favourites
    // cells don't go through a HomeBoardCell onFocused), and favourites only
    // ever live in Tonight's RAIL zone, never its Continue queue.
    _atriumFocusedRailKey.value = railKey;
    _tonightZoneIsQueue = false;
    _heroSwap.cancel();
    _clearHeroTrailer();
    if (liveChannel != null && _stageWantsLivePreview) {
      _setHeroLiveIptv(liveChannel);
    } else {
      _clearHeroLiveIptv();
    }
    _canvasFavFocus.value = focus;
  }

  /// One favourites cell on the Canvas shelf — the SAME [HomeFavoriteCell] +
  /// [HomeArtPoster] stack the classic rows use (identical art, badges, hold
  /// behaviour and open actions), with UP/DOWN rewired to rail switching and
  /// focus driving the Canvas stage override (and the full-bleed live
  /// preview, for IPTV).
  Widget _canvasFavCell(
    HomeFavoriteRowRef ref,
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
      return HomeFavoriteCell(
        onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
        isTelevision: true,
        column: col,
        rowNodes: nodes,
        onUp: up,
        onDown: down,
        onLeft: onLeft,
        onRight: onRight,
        onUpHold: onUpHold,
        onDownHold: onDownHold,
        child: HomeArtPoster(
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
            HomeFavoriteFocus(
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
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        final items = ref.kind == HomeFavoriteKind.watchlistMovies
            ? _watchlistMovieItems
            : _watchlistSeriesItems;
        final item = items[col];
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: HomeArtPoster(
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
              HomeFavoriteFocus(
                art: _firstNonEmpty(item.background, item.poster),
                title: item.name,
                subtitle: 'MY WATCHLIST · ${item.type.toUpperCase()}',
              ),
            ),
          ),
        );
      case HomeFavoriteKind.iptv:
        final channel = _iptvFavChannels[col];
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: HomeArtPoster(
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
              HomeFavoriteFocus(
                art: channel.logoUrl,
                fit: BoxFit.contain,
                title: channel.name,
                subtitle: 'IPTV · FAVORITES',
              ),
              liveChannel: channel,
            ),
          ),
        );
      case HomeFavoriteKind.debrify:
        final channel = _tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: HomeArtPoster(
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
              HomeFavoriteFocus(
                art: null,
                title: channel.name,
                subtitle: 'DEBRIFY TV · CHANNEL $number',
              ),
            ),
          ),
        );
      case HomeFavoriteKind.stremio:
        final channel = _stvFavChannels[col];
        final item = _stvNowPlaying(channel)?.item;
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: HomeArtPoster(
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
              HomeFavoriteFocus(
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
      case HomeFavoriteKind.playlist:
        final item = _playlistItems[col];
        final posterUrl = item.posterUrl;
        final title = item.title;
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: true,
          column: col,
          rowNodes: nodes,
          onUp: up,
          onDown: down,
          onLeft: onLeft,
          onRight: onRight,
          onUpHold: onUpHold,
          onDownHold: onDownHold,
          child: HomeArtPoster(
            imageUrl: posterUrl,
            title: title,
            showTitle: !_hideHomeCardTitlesAndRatings,
            progress: _playlistController.current.progressFor(item),
            isTelevision: true,
            ringColor: Colors.white,
            focusNode: nodes[col],
            onOpen: () => _onPlaylistItemTap(item),
            onFocused: () => _canvasFavFocused(
              railKey,
              col,
              HomeFavoriteFocus(
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
  late final HomeStageTheater _stageTheater = HomeStageTheater(
    isCurrent: () => mounted,
    isEligible: () => _theaterEligible,
    isShowing: () => _heroTrailerShowing.value,
    onChanged: () => setState(() {}),
  );
  bool get _canvasTheater => _stageTheater.active;

  void _onCanvasTrailerShowingChanged() => _stageTheater.showingChanged();

  bool _onCanvasTheaterKey(KeyEvent event) => _stageTheater.handleKey(event);

  String _canvasRailKeyOf(HomeRail rail) {
    return 'row:${_canvasRailRowId(rail)}';
  }

  /// Where the active rail currently sits in [rails] — re-resolved every
  /// build so insertions above it never change WHICH rail is shown.
  int _resolveCanvasRailIndex(List<HomeRail> rails) {
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
  bool _heroSourceResolving = false;
  // The presentation deadline can expire while the underlying request is
  // still pending. A return snapshot must resume that request too.
  bool _heroSourceResolutionPending = false;
  bool _spotlightEntryRevealed = false;

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
    _heroSourceResolving = true;
    _heroSourceResolutionPending = true;
    try {
      // The initial presentation must not wait forever on a dead hero source.
      // A late result may still populate the reel after the cards fallback.
      await _fetchSpotlightHeroSource(addons, gen).whenComplete(() {
        if (mounted && gen == _heroSourceResolveGen) {
          _heroSourceResolutionPending = false;
        }
      }).timeout(
        const Duration(seconds: 25),
        onTimeout: () {},
      );
    } finally {
      if (mounted && gen == _heroSourceResolveGen) {
        setState(() => _heroSourceResolving = false);
      }
    }
  }

  Future<void> _fetchSpotlightHeroSource(List<StremioAddon> addons, int gen) async {
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

  SpotlightShelf _spotlightShelfForRail(HomeRail rail) {
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
        tag: _hideHomeCollectionNames ? null : _catalogSourceTag(section),
        showHeader: !_hideHomeCollectionNames,
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
              coverEmoji: section.folderOf(m)?.coverEmoji,
              focusGlowEnabled: section.collection.focusGlowEnabled,
              previewOnKeyboardFocus: true,
              collectionGifUrl: section.focusArtOf(m),
              collectionVideoUrl: section.focusVideoOf(m),
              title: m.name,
              shape: section.tileAspectOf(m) == 1
                  ? SpotlightCardShape.square
                  : section.tileAspectOf(m) > 1
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
      onSeeAll: () => _openCatalogSeeAll(section),
      // Catalog cards go caption-free off TV in PORTRAIT — the art is the
      // label; a caption repeating the poster's own title was the
      // reference's one piece of noise we added ourselves. That rationale
      // inverts for LANDSCAPE, where the backdrop is a textless still and
      // the caption is the only identity the card has.
      captions: _homeLandscapeCards,
      items: [
        for (final m in _sections[i].items)
          _spotlightCatalogCards.resolve(m, section.addon,
            landscape: _homeLandscapeCards),
      ],
    );
  }

  SpotlightCard _spotlightContinueWatchingCard(
    HomeContinuationRow row,
    StremioMeta item,
    int cwIndex,
    int col,
  ) {
    final wideArt = homeStageWideArtwork(item);
    final episodeArt = item.type == 'series'
        ? row.episodeArtworkOf(item)
        : null;
    return SpotlightCard(
      metadata: item,
      episodeArtwork: _homeLandscapeCards && episodeArt != null,
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
      // `HomeContinuationRow` publishes a 0..1 fraction; the card draws 0..100.
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
  SpotlightShelf _spotlightFavShelf(HomeFavoriteRowRef ref, {String? id}) {
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
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        final isMovies = ref.kind == HomeFavoriteKind.watchlistMovies;
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
                image: _homeLandscapeCards ? homeStageWideArtwork(item) : item.poster,
                fallbackImage: _homeLandscapeCards ? item.poster : null,
                title: item.name,
                rating: item.imdbRating,
                subtitle: isMovies ? 'MOVIE' : 'SERIES',
                shape: _homeLandscapeCards
                    ? SpotlightCardShape.wide
                    : SpotlightCardShape.poster,
                watchedImdbId: item.progressId ?? item.id,
                watchedContentType: item.type,
                onOpen: () => _openMyWatchlistItem(item),
              ),
          ],
        );
      case HomeFavoriteKind.playlist:
        return SpotlightShelf(
          id: id,
          title: 'Playlists',
          nodes: nodes,
          items: [
            for (final item in _playlistItems)
              SpotlightCard(
                image: item.posterUrl,
                title: item.title,
                progress: _playlistController.current.progressFor(item),
                onOpen: () => _onPlaylistItemTap(item),
              ),
          ],
        );
      case HomeFavoriteKind.iptv:
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
      case HomeFavoriteKind.debrify:
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
      case HomeFavoriteKind.stremio:
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
  String? _stvFavArt(HomeStremioFavorite ch, {bool landscape = false}) {
    final item = _stvNowPlaying(ch)?.item;
    if (item == null) return null;
    if (landscape) return homeStageWideArtwork(item);
    return _firstNonEmpty(item.poster, item.background);
  }

  Widget _buildSearchSpotlightBoard() {
    final sections = List<CatalogSection>.of(_sections);
    return Column(
      children: [
        // Reserve the status strip so completion never shifts focused cards.
        if (_catalogSearching || _catalogSearchFailures > 0)
          _buildSearchStatusStrip()
        else
          const SizedBox(height: 16),
        Expanded(child: SpotlightBoard(
          key: _spotlightKey,
          hero: const [], heroNode: _spotlightHeroNode, heroAddon: null,
          onHeroOpen: _openItem, shelvesOnly: true, dpad: true,
          showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
          forceCardParallax: true,
          onExitTop: _leaveBoardTop,
          expandFocusedCard: _spotlightFocusDetails,
          trailersEnabled: _heroTrailerEnabled,
          cardTrailerVolume: _heroTrailerVolume,
          onTrailerStop: _clearHeroTrailer,
          sections: [
            for (var i = 0; i < sections.length; i++) SpotlightShelf(
              id: 'search:$_catalogQuery:${sections[i].addon.id}:${sections[i].catalog.id}:$i',
              title: sections[i].title,
              tag: _catalogSourceTag(sections[i]),
              onSeeAll: () => _openCatalogSeeAll(sections[i]),
              nodes: i < _rowNodes.length ? _rowNodes[i] : const [],
              items: [
                for (final item in sections[i].items)
                  SpotlightCard(
                    metadata: item, title: item.name, rating: item.imdbRating,
                    image: _homeLandscapeCards ? homeStageWideArtwork(item) : item.poster,
                    fallbackImage: _homeLandscapeCards ? item.poster : null,
                    shape: _homeLandscapeCards ? SpotlightCardShape.wide : SpotlightCardShape.poster,
                    watchedImdbId: item.progressId ?? item.id,
                    watchedContentType: item.type,
                    onOpen: () => _sectionOpenItem(sections[i], item),
                    onOptions: _pikpakOnly ? null : () => _onCatalogPlay(item, sections[i].addon),
                  ),
              ],
            ),
          ],
          onLoadMoreRow: (row) {
            if (row < 0 || row >= sections.length) return;
            final current = _sections.indexOf(sections[row]);
            if (current >= 0) unawaited(_loadMoreRow(current));
          },
        )),
      ],
    );
  }

  Widget _buildSpotlightBoard() {
    // Snapshot row descriptors with the shelf list: async inserts must not
    // make a callback page a different catalog than the shelf it came from.
    final rails = _canvasRails;
    return SpotlightBoard(
      largeScreenInteractions: true,
      key: _spotlightKey,
      animationsEnabled: _homeAnimationsEnabled,
      animationStyle: _homeAnimationStyle,
      hero: _spotlightHero,
      sections: _spotlightShelves,
      heroNode: _spotlightHeroNode,
      heroAddon: _spotlightHeroSection?.addon,
      dpad: widget.isTelevision,
      showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
      expandFocusedCard: _spotlightFocusDetails,
      cardTrailerVolume: _heroTrailerVolume,
      onHeroOpen: _openItem,
      onLoadMoreRow: (row) {
        if (row < 0 || row >= rails.length) return;
        final catalogRow = rails[row].sectionIndex;
        if (catalogRow != null) unawaited(_loadMoreRow(catalogRow));
      },
      onLoadMoreShelves: _loadMoreBoard,
      pendingShelves: PlatformUtil.isAndroidTvCached && _boardRowsPending,
      // The board owns the CADENCE; the resolve and the video stay here.
      //
      // Every other entry into `_scheduleHeroTrailer` is still excluded for
      // this style — init, section loads, focus changes, `_applyHero`, route
      // return, sidebar return — so the board's clock is the single owner and
      // the two cannot start a trailer under different titles.
      // Suppression is enforced inside
      // _scheduleHeroTrailer. Folding it in here disarms the board's dwell
      // clock entirely — and the dwell is the only event that can LIFT the
      // suppression when the reel moves to a new title, so one post-playback
      // rebuild would have frozen trailers until the tab was recreated.
      trailersEnabled: _heroTrailerEnabled,
      onDwell: (item) => _scheduleHeroTrailer(item, fromSpotlight: true),
      onTrailerStop: _clearHeroTrailer,
      trailer: _heroTrailerRenderable
          ? HomeHeroTrailerLayer(
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
      return _spotlightKey.currentState?.focusTarget();
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
  List<HomeRail> get _canonicalCanvasRails {
    final rails = <HomeRail>[];
    if (_cwVisible) {
      final cwRows = _cwRows;
      for (var i = 0; i < cwRows.length; i++) {
        if (cwRows[i].items.isEmpty) continue;
        rails.add(HomeRail(cw: cwRows[i], cwIndex: i));
      }
    }
    for (final ref in _favRowKinds) {
      if (_canvasFavItemCount(ref) == 0) continue;
      rails.add(HomeRail(favKind: ref));
    }
    for (var i = 0; i < _sections.length; i++) {
      if (_sections[i].items.isEmpty || i >= _rowNodes.length) continue;
      rails.add(HomeRail(sectionIndex: i));
    }
    return HomeRowOrder.defaults(rails, _canvasRailRowId);
  }

  /// The canonical rails, globally sorted by the user's saved row ids.
  List<HomeRail> get _canvasRails {
    final rails = _canonicalCanvasRails;
    return _homeRowOrderActive
        ? HomeRowOrder.apply(rails, _effectiveHomeRowOrder, _canvasRailRowId)
        : rails;
  }

  /// Classic renders the same globally ordered rails as every stage layout,
  /// plus focusless Trakt placeholders while that account is loading.
  List<HomeRail> get _classicHomeRails {
    var rails = _canonicalCanvasRails;
    if (_traktReserving) {
      final skeletons = <HomeRail>[];
      if (!_homeDisabled.contains('trakt:movies')) {
        skeletons.add(const HomeRail(traktSkeletonIndex: 0));
      }
      // Merged Trakt renders one combined row, so reserve one slot, not two.
      if (!_cwMergeTrakt && !_homeDisabled.contains('trakt:shows')) {
        skeletons.add(const HomeRail(traktSkeletonIndex: 1));
      }
      // In the built-in order placeholders belong after the real CW block and
      // before favourites/sections. Build that canonical sequence first, then
      // let a saved order move the placeholders wherever the user requested.
      rails = HomeRowOrder.insertAfterLeadingRun(
        rails,
        skeletons,
        (rail) => rail.cw != null,
      );
    }
    return _homeRowOrderActive
        ? HomeRowOrder.apply(rails, _effectiveHomeRowOrder, _canvasRailRowId)
        : rails;
  }

  String _canvasRailRowId(HomeRail rail) {
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

  final HomeStageHoldLatch _stageHold = HomeStageHoldLatch();

  /// Remembered row within the queue — the INDEX is only a fallback. CW rows
  /// stream in and prepend (Trakt/Simkl land seconds after a cold start), so
  /// the identity below is what actually restores the user's place.
  int _tonightQueueCol = 0;

  /// What the big card should say about whatever currently has focus — the
  /// OK hint in particular, which is 'Resume' only for a part-watched title
  /// and 'Play'/'Open' otherwise. A notifier, so a focus move repaints the
  /// caption alone rather than the board.
  final ValueNotifier<HomeTonightCardInfo?> _tonightCard =
      ValueNotifier<HomeTonightCardInfo?>(null);

  /// Identity of the remembered queue row: '<rail key>#<column>'. Resolved
  /// against the rebuilt queue every time, exactly like [_canvasRailKey].
  String? _tonightQueueKey;

  /// The queue: every Continue Watching row flattened to (row, column) pairs
  /// in board order. Nodes come from the CW rows themselves — which is why
  /// [_stageRails] drops CW rails on Tonight (a node may be mounted once).
  List<HomeTonightQueueEntry> get _tonightQueue {
    final out = <HomeTonightQueueEntry>[];
    if (!_cwVisible) return out;
    for (final rail in _canvasRails) {
      final cw = rail.cw;
      if (cw == null) continue;
      final n = min(cw.items.length, cw.nodes.length);
      for (var col = 0; col < n; col++) {
        out.add(HomeTonightQueueEntry(rail: rail, col: col));
      }
    }
    return out;
  }

  /// The rails the ACTIVE layout puts on its rail zone. Identical to
  /// [_canvasRails] everywhere except Tonight, which lifts the Continue
  /// Watching rows out into its own vertical queue — leaving them in both
  /// places would mount the same FocusNodes twice.
  List<HomeRail> get _stageRails => _homeStyleEffective == 'tonight'
      ? [
          for (final r in _canvasRails)
            if (r.cw == null) r,
        ]
      : _canvasRails;

  int _canvasFavItemCount(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) return _iptvListRows[ref.list].channels.length;
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return _watchlistMovieItems.length;
      case HomeFavoriteKind.watchlistSeries:
        return _watchlistSeriesItems.length;
      case HomeFavoriteKind.iptv:
        return _iptvFavChannels.length;
      case HomeFavoriteKind.debrify:
        return _tvFavChannels.length;
      case HomeFavoriteKind.stremio:
        return _stvFavChannels.length;
      case HomeFavoriteKind.playlist:
        return _playlistItems.length;
    }
  }

  String _canvasFavTitle(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) return _iptvListRows[ref.list].title;
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return 'Watchlist Movies';
      case HomeFavoriteKind.watchlistSeries:
        return 'Watchlist Series';
      case HomeFavoriteKind.iptv:
        return 'IPTV Favorites';
      case HomeFavoriteKind.debrify:
        return 'Debrify TV';
      case HomeFavoriteKind.stremio:
        return 'Stremio TV';
      case HomeFavoriteKind.playlist:
        return 'Playlist';
    }
  }

  String _canvasRailTitle(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.title;
    if (rail.favKind != null) return _canvasFavTitle(rail.favKind!);
    final section = _sections[rail.sectionIndex!];
    if (_hideHomeCollectionNames && section is HomeCollectionSection) {
      return '';
    }
    return section.title;
  }

  List<StremioMeta> _canvasRailItems(HomeRail rail) =>
      rail.cw?.items ?? _sections[rail.sectionIndex!].items;

  List<FocusNode> _canvasRailNodes(HomeRail rail) {
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
      if (delta > 0 && !_boardRowsPending && _focusCatalogContinuation()) {
        return;
      }
      if (delta > 0 && _boardCanAdvance) {
        // Remember the move so it COMPLETES when the batch lands — otherwise
        // the keypress is silently eaten and the user has to press again.
        _stageDeferredAdvance.defer(_canvasRailKeyOf(rails[current]));
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
    _stageFocusRequests.schedule(_stageFocusTarget);
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
        return buildHomeCanvasLayout(
          boardHeight: boardH,
          cardAspect: _stageCardAspect(rail),
          captionBand: _homeArtPosterCaptionBand,
          tabsHeight: homeCanvasTabsHeight(context),
          theater: _canvasTheater,
          artwork: HomeStageArt(
            item: _heroItem,
            enriched: _heroEnriched,
            fav: _canvasFavFocus,
            cacheWidth: _tvHeroArtworkCacheWidth,
            cacheHeight: _tvHeroArtworkCacheHeight,
          ),
          trailer: _heroTrailerActive
              ? HomeHeroTrailerLayer(
                  trailer: _heroTrailer,
                  isTelevision: widget.isTelevision,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  loading: _heroTrailerLoading,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  takeover: _heroTrailerTakeover,
                )
              : null,
          live: _heroTrailerActive
              ? HomeHeroLiveLayer(
                  isAddonChannel: StremioIptvService.isStremioChannelUrl,
                  channel: _heroLiveChannel,
                  streamUrl: _heroLiveUrl,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  onPlaybackFailed: _onHeroLivePlaybackFailed,
                )
              : null,
          identity: ValueListenableBuilder<HomeFavoriteFocus?>(
            valueListenable: _canvasFavFocus,
            builder: (context, fav, _) => fav != null
                ? HomeStageFavoriteIdentity(fav: fav)
                : HomeStageIdentity(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    trailerShowing: _heroTrailerShowing,
                  ),
          ),
          tabs: buildHomeCanvasTabs(
            context: this.context,
            railCount: rails.length,
            active: railIndex,
            titleAt: (i) => _canvasTabTitle(rails, i),
          ),
          shelfBuilder: (cardH, cardW, favCardW) => buildHomeCanvasShelf(
            railKey: railKey,
            itemCount: favRail
                ? _canvasFavItemCount(rail.favKind!)
                : items.length,
            cardWidth: favRail ? favCardW : cardW,
            cardHeight: favRail ? null : cardH,
            itemBuilder: (context, col) {
              if (favRail) return _canvasFavCell(rail.favKind!, railKey, col);
              final item = items[col];
              return HomeBoardCell(
                onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
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
                focusVideoUrl: _stageCollection(rail)?.focusVideoOf(item),
                focusGlowEnabled:
                    _stageCollection(rail)?.collection.focusGlowEnabled ??
                    false,
                showTitleOverlay:
                    !(_stageCollection(rail)?.folderOf(item)?.hideTitle ??
                        false),
                progress: rail.cw?.progressOf(item),
                episodeLabel: rail.cw?.episodeOf(item),
                onQuickPlay: rail.cw != null || _pikpakOnly
                    ? null
                    : () => _sectionQuickPlay(
                        _sections[rail.sectionIndex!],
                        item,
                      ),
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
            },
          ),
        );
      },
    );
  }
  /// A DOWN that ran off the end of the rail list asked for another batch.
  /// Called when one lands: completes the move only if the user is STILL on
  /// the rail they pressed DOWN from, and the request hasn't gone stale — a
  /// late batch must never yank focus out of wherever they went instead.
  void _maybeCompleteStageAdvance() {
    late final List<HomeRail> rails;
    late final int i;
    final move = _stageDeferredAdvance.take(
      waitingForMore: (key) {
        rails = _stageRails;
        i = rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
        return _boardRowsPending && i >= 0 && i + 1 >= rails.length;
      },
    );
    if (move == null) return;
    final key = move.railKey;
    final fillLower = move.fillsLower;
    final origin = move.origin;
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
      _stageFocusRequests.schedule(() {
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
    _stageFocusRequests.schedule(() {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return null;
      final primary = FocusManager.instance.primaryFocus;
      // Deck/Mosaic replace the entire rail. That intentional replacement
      // detaches the origin before this frame callback and leaves route-scope
      // focus. A different attached card still means the user moved elsewhere.
      final detachedBySwap = origin?.parent == null &&
          (primary == null || identical(primary, FocusScope.of(context)));
      return identical(primary, origin) || detachedBySwap
          ? _stageFocusTarget() : null;
    });
  }

  /// A rail strip reserves ONE box height for every rail kind (invariant: a
  /// per-kind height bounces the layout on every fav↔catalog switch). The two
  /// kinds FILL it differently rather than one wasting the other's space: a
  /// catalog poster is the full box, a favourite's poster is the box minus its
  /// caption band, so both end exactly on the box's bottom edge.
  /// TITLE cards follow the Home Cards orientation setting; everything else
  /// (favourites, channels, playlists) keeps its own fixed shape.
  double get _titleCardAspect =>
      homeTitleCardAspect(landscape: _homeLandscapeCards);

  /// The art for a title card under the current orientation. Null keeps the
  /// cell's own default (the 2:3 poster) — only landscape needs a derived
  /// wide still.
  String? _titleArtUrl(StremioMeta item) =>
      _homeLandscapeCards ? homeStageWideArtwork(item) : null;

  HomeCollectionSection? _stageCollection(HomeRail rail) {
    final index = rail.sectionIndex;
    if (index == null) return null;
    final section = _sections[index];
    return section is HomeCollectionSection ? section : null;
  }

  double _stageCardAspect(HomeRail rail, {double? fallback}) =>
      _stageCollection(rail)?.tileAspectRatio ?? fallback ?? _titleCardAspect;

  String? _stageCardArt(HomeRail rail, StremioMeta item, {bool wide = false}) =>
      _stageCollection(rail) != null
          ? item.poster
          : wide
          ? homeStageWideArtwork(item)
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
    _stageFocusRequests.schedule(() {
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
  HomeStageRailView? _resolveStageRail() {
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
    return HomeStageRailView(
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
        final itemCount = favRail
            ? _canvasFavItemCount(rail.favKind!)
            : items.length;
        return buildHomePromenadeLayout(
          boardWidth: boardW,
          stripHeight: stripBoxH,
          cellWidth: cellW,
          labelHeight: homeStageRailLabelHeight(context),
          theater: _canvasTheater,
          railKey: railKey,
          itemCount: itemCount,
          artwork: HomeStageArt(
            item: _heroItem,
            enriched: _heroEnriched,
            fav: _canvasFavFocus,
            cacheWidth: _tvHeroArtworkCacheWidth,
            cacheHeight: _tvHeroArtworkCacheHeight,
          ),
          trailer: _heroTrailerActive
              ? HomeHeroTrailerLayer(
                  trailer: _heroTrailer,
                  isTelevision: widget.isTelevision,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  loading: _heroTrailerLoading,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  takeover: _heroTrailerTakeover,
                )
              : null,
          live: _heroTrailerActive
              ? HomeHeroLiveLayer(
                  isAddonChannel: StremioIptvService.isStremioChannelUrl,
                  channel: _heroLiveChannel,
                  streamUrl: _heroLiveUrl,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  onPlaybackFailed: _onHeroLivePlaybackFailed,
                )
              : null,
          identity: ValueListenableBuilder<HomeFavoriteFocus?>(
            valueListenable: _canvasFavFocus,
            builder: (context, fav, _) => fav != null
                ? HomeStageFavoriteIdentity(fav: fav, centered: true)
                : HomeStageIdentity(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    trailerShowing: _heroTrailerShowing,
                    variant: HomeStageIdentityVariant.centered,
                    maxWidth: boardW - 96,
                  ),
          ),
          label: buildHomeStageRailLabel(
            context: this.context,
            title: _canvasTabTitle(view.rails, view.index),
            railIndex: view.index,
            railCount: view.rails.length,
          ),
          itemBuilder: (context, col) => favRail
              ? _canvasFavCell(rail.favKind!, railKey, col)
              : SizedBox(
                  height: stripBoxH,
                  child: _promenadeCell(rail, railKey, items, nodes, col),
                ),
        );
      },
    );
  }

  /// One wide strip cell — the SAME [HomeBoardCell] every board uses, in a 16:9
  /// box with derived landscape art, so hold-OK menus, quick-play, paging and
  /// the focus grammar are identical to Canvas's shelf.
  Widget _promenadeCell(
    HomeRail rail,
    String railKey,
    List<StremioMeta> items,
    List<FocusNode> nodes,
    int col,
  ) {
    final item = items[col];
    return HomeBoardCell(
      onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
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
      focusVideoUrl: _stageCollection(rail)?.focusVideoOf(item),
      focusGlowEnabled: _stageCollection(rail)?.collection.focusGlowEnabled ?? false,
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
      if (_boardCanAdvance) {
        _stageDeferredAdvance.defer(
          _canvasRailKeyOf(rails[min(cur + 1, rails.length - 1)]),
        );
        _loadMoreBoard();
      }
      return;
    }
    setState(() => _canvasRailKey = _canvasRailKeyOf(rails[cur + 1]));
    _stageFocusRequests.schedule(() {
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
            (rows - 1) * homeAtriumRowGap +
            homeAtriumWallTail;
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
            (showSecondRow ? rowUnit * 2 + homeAtriumRowGap : rowUnit) +
            homeAtriumWallTail;

        return buildHomeAtriumLayout(
          splitX: splitX,
          wallH: wallH,
          panelColor: app.home.bg,
          seamColor: app.fade(app.core.tx, 0.09),
          artwork: HomeStageArt(
            item: _heroItem,
            enriched: _heroEnriched,
            fav: _canvasFavFocus,
            cacheWidth: _tvHeroArtworkCacheWidth,
            cacheHeight: _tvHeroArtworkCacheHeight,
          ),
          trailer: _heroTrailerActive
              ? HomeHeroTrailerLayer(
                  trailer: _heroTrailer,
                  isTelevision: widget.isTelevision,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  loading: _heroTrailerLoading,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  takeover: _heroTrailerTakeover,
                )
              : null,
          live: _heroTrailerActive
              ? HomeHeroLiveLayer(
                  isAddonChannel: StremioIptvService.isStremioChannelUrl,
                  channel: _heroLiveChannel,
                  streamUrl: _heroLiveUrl,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  onPlaybackFailed: _onHeroLivePlaybackFailed,
                )
              : null,
          railLabel: ValueListenableBuilder<String?>(
            valueListenable: _atriumFocusedRailKey,
            builder: (context, key, _) {
              final i = key == null
                  ? active
                  : rails.indexWhere((r) => _canvasRailKeyOf(r) == key);
              final title = _canvasTabTitle(rails, i < 0 ? active : i);
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
          identity: ValueListenableBuilder<HomeFavoriteFocus?>(
            valueListenable: _canvasFavFocus,
            builder: (context, fav, _) => fav != null
                ? HomeStageFavoriteIdentity(fav: fav)
                : HomeStageIdentity(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    trailerShowing: _heroTrailerShowing,
                    // Drop the synopsis rather than clip it when
                    // the column is short (small board / large
                    // text scale).
                    variant:
                        boardH - 64 >=
                            homeStageNarrowIdentityHeight(context) + 90
                        ? HomeStageIdentityVariant.narrow
                        : HomeStageIdentityVariant.headline,
                    maxWidth: (splitX - homeAtriumPanelPadding * 2).clamp(
                      120.0,
                      520.0,
                    ),
                  ),
          ),
          topRow: _atriumRow(
            rails,
            active,
            rowBoxH,
            isTopRow: true,
            hasRowBelow: showSecondRow,
          ),
          bottomRow: showSecondRow
              ? _atriumRow(
                  rails,
                  active + 1,
                  rowBoxH,
                  isTopRow: false,
                  hasRowBelow: false,
                )
              : null,
        );
      },
    );
  }

  /// One row of Atrium's wall: a quiet rail label over a horizontal strip of
  /// the SAME cells every other board uses.
  Widget _atriumRow(
    List<HomeRail> rails,
    int index,
    double rowBoxH, {
    required bool isTopRow,
    required bool hasRowBelow,
  }) {
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
                        if (_boardCanAdvance) {
                          _stageDeferredAdvance.defer(
                            railKey,
                            fillsLower: true,
                          );
                          _loadMoreBoard();
                        }
                      }))
        : _atriumAdvance;

    return buildHomeAtriumRow(
      context: context,
      title: _canvasTabTitle(rails, index),
      androidTv: PlatformUtil.isAndroidTvCached,
      labelGap: _kAtriumLabelGap,
      rowHeight: rowBoxH,
      railKey: railKey,
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
                    child: HomeBoardCell(
                      onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
                      item: items[col],
                      isTelevision: true,
                      focusNode: nodes[col],
                      column: col,
                      rowNodes: nodes,
                      hasBoundSource: _isBound(items[col]),
                      ringColor: Colors.white,
                      aspectRatio: _stageCardAspect(rail),
                      artUrl: _stageCardArt(rail, items[col]),
                      focusArtUrl: _stageCollection(
                        rail,
                      )?.focusArtOf(items[col]),
                      focusVideoUrl: _stageCollection(
                        rail,
                      )?.focusVideoOf(items[col]),
                      focusGlowEnabled:
                          _stageCollection(rail)?.collection.focusGlowEnabled ??
                          false,
                      showTitleOverlay:
                          !(_stageCollection(
                                rail,
                              )?.folderOf(items[col])?.hideTitle ??
                              false),
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
        final geometry = HomeMosaicGeometry(
          boardW: boardW,
          boardH: boardH,
          cellAspect: favRail ? 2 / 3 : _stageCardAspect(rail),
          captionBandHeight: favRail ? _homeArtPosterCaptionBand : 0,
        );
        return buildHomeMosaicLayout(
          context: context,
          geometry: geometry,
          railKey: railKey,
          itemCount: count,
          liveChannel: _heroLiveChannel,
          showRailHint: view.rails.length > 1,
          hintColor: app.fade(app.core.tx, 0.34),
          artwork: HomeStageArt(
            item: _heroItem,
            enriched: _heroEnriched,
            fav: _canvasFavFocus,
            cacheWidth: _tvHeroArtworkCacheWidth,
            cacheHeight: _tvHeroArtworkCacheHeight,
          ),
          liveSurface: _heroTrailerActive
              ? HomeHeroLiveLayer(
                  isAddonChannel: StremioIptvService.isStremioChannelUrl,
                  channel: _heroLiveChannel,
                  streamUrl: _heroLiveUrl,
                  heroHeight: boardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  onPlaybackFailed: _onHeroLivePlaybackFailed,
                )
              : null,
          identity: ValueListenableBuilder<HomeFavoriteFocus?>(
            valueListenable: _canvasFavFocus,
            builder: (context, fav, _) => Align(
              alignment: Alignment.bottomLeft,
              child: fav != null
                  ? HomeStageFavoriteIdentity(fav: fav)
                  : HomeStageIdentity(
                      item: _heroItem,
                      enriched: _heroEnriched,
                      trailerShowing: _heroTrailerShowing,
                      variant: HomeStageIdentityVariant.headline,
                      maxWidth: max(1.0, geometry.gridW * 0.5),
                    ),
            ),
          ),
          railLabel: buildHomeStageRailLabel(
            context: this.context,
            title: _canvasTabTitle(view.rails, view.index),
            railIndex: view.index,
            railCount: view.rails.length,
            align: MainAxisAlignment.end,
          ),
          itemBuilder: (context, col) => _mosaicCell(
            rail,
            railKey,
            items,
            nodes,
            col,
            count,
            geometry.perRow,
            geometry.cellW,
          ),
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
    HomeRail rail,
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
        _stageDeferredRight.defer(railKey, col);
      }
    }

    final onUp = col - perRow >= 0
        ? () {
            if (_stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
            focusAt(col - perRow);
          }
        : () {
            if (_stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
            _stageSwitchRail(-1);
          };
    // DOWN steps a whole line, and at the LAST line always leaves for the
    // next rail (prefetching on the way out, so coming back finds more).
    // Consuming DOWN to paginate would trap the user inside a long catalog.
    Null onDown() {
      if (_stageHold.swallows(LogicalKeyboardKey.arrowDown)) return;
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
    void onUpHold() => _stageHold.jump(LogicalKeyboardKey.arrowUp, () {
      _stageSwitchRail(-1);
      return true;
    });
    void onDownHold() => _stageHold.jump(LogicalKeyboardKey.arrowDown, () {
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
      child: HomeBoardCell(
        onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
        item: item,
        isTelevision: true,
        focusNode: nodes[col],
        column: col,
        rowNodes: nodes,
        aspectRatio: _stageCardAspect(rail),
        artUrl: _stageCardArt(rail, item),
        focusArtUrl: _stageCollection(rail)?.focusArtOf(item),
        focusVideoUrl: _stageCollection(rail)?.focusVideoOf(item),
        focusGlowEnabled: _stageCollection(rail)?.collection.focusGlowEnabled ?? false,
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
        final geometry = HomeDeckGeometry(
          boardW: boardW,
          boardH: boardH,
          railBoxH: railBoxH,
          labelHeight: _atriumLabelHeight(context),
          labelGap: _kAtriumLabelGap,
        );
        return buildHomeDeckLayout(
          geometry: geometry,
          theater: _canvasTheater,
          railKey: railKey,
          itemCount: count,
          borderColor: app.fade(app.core.tx, 0.10),
          peeks: ValueListenableBuilder<int>(
            valueListenable: _stageCol,
            builder: (context, focusedCol, _) => Stack(
              children: buildHomeDeckPeeks(
                items: items,
                favRail: favRail,
                focused: focusedCol,
                left: geometry.cardLeft,
                top: geometry.cardTop,
                width: geometry.cardW,
                height: geometry.cardH,
              ),
            ),
          ),
          artwork: HomeStageArt(
            item: _heroItem,
            enriched: _heroEnriched,
            fav: _canvasFavFocus,
            cacheWidth: _tvHeroArtworkCacheWidth,
            cacheHeight: _tvHeroArtworkCacheHeight,
          ),
          trailer: _heroTrailerActive
              ? HomeHeroTrailerLayer(
                  trailer: _heroTrailer,
                  isTelevision: widget.isTelevision,
                  heroHeight: geometry.cardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  loading: _heroTrailerLoading,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  takeover: _heroTrailerTakeover,
                )
              : null,
          live: _heroTrailerActive
              ? HomeHeroLiveLayer(
                  isAddonChannel: StremioIptvService.isStremioChannelUrl,
                  channel: _heroLiveChannel,
                  streamUrl: _heroLiveUrl,
                  heroHeight: geometry.cardH,
                  fullBleed: true,
                  volume: _heroTrailerVolume,
                  onPlayingChanged: _onHeroTrailerPlaying,
                  onPlaybackFailed: _onHeroLivePlaybackFailed,
                )
              : null,
          identity: ValueListenableBuilder<HomeFavoriteFocus?>(
            valueListenable: _canvasFavFocus,
            builder: (context, fav, _) => fav != null
                ? HomeStageFavoriteIdentity(fav: fav)
                : HomeStageIdentity(
                    item: _heroItem,
                    enriched: _heroEnriched,
                    trailerShowing: _heroTrailerShowing,
                    variant:
                        boardH - geometry.railZoneH >=
                            homeStageNarrowIdentityHeight(context)
                        ? HomeStageIdentityVariant.narrow
                        : HomeStageIdentityVariant.headline,
                    maxWidth: geometry.identityWidth,
                  ),
          ),
          railLabel: buildHomeStageRowLabel(
            context: this.context,
            title: _canvasTabTitle(view.rails, view.index),
          ),
          itemBuilder: (context, col) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Center(
              child: SizedBox(
                width: favRail
                    ? _stageFavW(context, railBoxH)
                    : railBoxH * _stageCardAspect(rail),
                child: favRail
                    ? _canvasFavCell(rail.favKind!, railKey, col)
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
        );
      },
    );
  }

  /// The shared poster shelf cell (Canvas grammar: L/R along the rail, U/D
  /// switches rails) — used by Deck and Tonight's bottom strip.
  Widget _stageShelfCell(
    HomeRail rail,
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
    return HomeBoardCell(
      onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
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
      focusVideoUrl: _stageCollection(rail)?.focusVideoOf(item),
      focusGlowEnabled: _stageCollection(rail)?.collection.focusGlowEnabled ?? false,
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

  String _tonightQueueKeyOf(HomeTonightQueueEntry e) =>
      '${_canvasRailKeyOf(e.rail)}#${e.col}';

  /// Where the remembered queue row sits NOW. Identity first (CW rows stream
  /// in and prepend, so a raw index would silently point at another title),
  /// the remembered index only as a fallback.
  int _resolveTonightQueueIndex(List<HomeTonightQueueEntry> queue) {
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
        final geometry = HomeTonightGeometry(
          boardW: boardW,
          boardH: boardH,
          hasRail: rails.isNotEmpty,
          hasQueue: queue.isNotEmpty,
          railBoxH: railBoxH,
          labelHeight: labelH,
          labelGap: _kAtriumLabelGap,
          headerH: homeTonightHeaderHeight(context),
          rowMinH: _tonightRowMinHeight(context),
        );
        // A zone that isn't on screen must not be the one holding focus.
        if (!geometry.showQueue && rails.isNotEmpty) {
          _tonightZoneIsQueue = false;
        }
        return buildHomeTonightLayout(
          geometry: geometry,
          header: buildHomeTonightHeader(
            context: this.context,
            inProgress: queue.length,
            now: DateTime.now(),
          ),
          cardBuilder: () => buildHomeTonightCardFrame(
            artwork: HomeStageArt(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              cacheWidth: _tvHeroArtworkCacheWidth,
              cacheHeight: _tvHeroArtworkCacheHeight,
            ),
            trailer: _heroTrailerActive
                ? HomeHeroTrailerLayer(
                    trailer: _heroTrailer,
                    isTelevision: widget.isTelevision,
                    heroHeight: geometry.cardH,
                    fullBleed: true,
                    volume: _heroTrailerVolume,
                    loading: _heroTrailerLoading,
                    onPlayingChanged: _onHeroTrailerPlaying,
                    takeover: _heroTrailerTakeover,
                  )
                : null,
            live: _heroTrailerActive
                ? HomeHeroLiveLayer(
                    isAddonChannel: StremioIptvService.isStremioChannelUrl,
                    channel: _heroLiveChannel,
                    streamUrl: _heroLiveUrl,
                    heroHeight: geometry.cardH,
                    fullBleed: true,
                    volume: _heroTrailerVolume,
                    onPlayingChanged: _onHeroTrailerPlaying,
                    onPlaybackFailed: _onHeroLivePlaybackFailed,
                  )
                : null,
            caption: HomeTonightCardCaption(
              item: _heroItem,
              enriched: _heroEnriched,
              fav: _canvasFavFocus,
              info: _tonightCard,
            ),
          ),
          queueBuilder: () => _tonightQueueList(
            queue,
            geometry.rowH,
            geometry.effQueueW,
            rails.isNotEmpty,
          ),
          railBuilder: view == null
              ? null
              : () => _tonightRail(
                  view,
                  railBoxH,
                  queueAbove: queue.isNotEmpty && geometry.showQueue,
                ),
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

  Widget _tonightQueueList(
    List<HomeTonightQueueEntry> queue,
    double rowH,
    double queueW,
    bool hasRail,
  ) {
    return buildHomeTonightQueueList(
      itemCount: queue.length,
      rowHeight: rowH,
      queueWidth: queueW,
      itemBuilder: (context, i, thumbW) {
        final e = queue[i];
        final cw = e.rail.cw!;
        final item = cw.items[e.col];
        return HomeTonightQueueRow(
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
            _tonightCard.value = HomeTonightCardInfo(
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
          onLongPress: () => _openCwCardMenu(cw, item, e.rail.cwIndex, e.col),
          onUp: () {
            if (_stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
            if (i > 0) {
              _nearestMountedNode(
                queue[i - 1].rail.cw!.nodes,
                queue[i - 1].col,
              )?.requestFocus();
            }
          },
          onDown: () {
            if (_stageHold.swallows(LogicalKeyboardKey.arrowDown)) return;
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
              ? () => _stageHold.jump(
                  LogicalKeyboardKey.arrowDown,
                  _tonightFocusRail,
                )
              : null,
          onLeft: () => MainPageBridge.focusTvSidebar?.call(),
        );
      },
    );
  }

  Widget _tonightRail(
    HomeStageRailView view,
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
      if (_stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
      if (view.index > 0) {
        _stageSwitchRail(-1);
      } else if (queueAbove) {
        _tonightFocusQueue();
      }
    }

    void down() {
      if (_stageHold.swallows(LogicalKeyboardKey.arrowDown)) return;
      _stageSwitchRail(1);
    }

    // HELD up: back to the Continue queue from any rail, the mirror of the
    // queue's held DOWN.
    final upHold = queueAbove
        ? () => _stageHold.jump(LogicalKeyboardKey.arrowUp, _tonightFocusQueue)
        : null;

    return buildHomeTonightRail(
      railHeight: boxH,
      labelGap: _kAtriumLabelGap,
      railKey: railKey,
      itemCount: count,
      label: buildHomeStageRowLabel(
        context: context,
        title: _canvasTabTitle(view.rails, view.index),
      ),
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
                        _tonightCard.value = HomeTonightCardInfo(
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
    );
  }

  /// Tab label for a rail, with colliding titles disambiguated by the
  /// section's provenance tag. Titles carry their content type themselves
  /// now ("Popular Movies" — [CatalogSection.rowTitle]), so the only way two
  /// tabs still collide is the same catalog name+type from two ADDONS — and
  /// the addon is exactly what tells those apart.
  String _canvasTabTitle(List<HomeRail> rails, int i) {
    final title = _canvasRailTitle(rails[i]);
    if (title.isEmpty) return '';
    final rail = rails[i];
    if (rail.sectionIndex == null) return title;
    final duplicated = rails.any(
      (r) => !identical(r, rail) && _canvasRailTitle(r) == title,
    );
    if (!duplicated) return title;
    return '$title · ${_sectionTag(_sections[rail.sectionIndex!])}';
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  /// Whether the hero spotlight is live for the current tab/state: TV-only.
  /// Dedicated Search uses in-card previews instead of a separate hero.
  /// Single source of truth for
  /// seeding ([_applySections]), focus tracking ([_setHero]) and rendering
  /// ([_buildBoard]) so they can't drift.
  bool get _heroActive =>
      widget.isTelevision && !widget.searchMode;

  void _setHero(StremioMeta item) {
    _heroPreviewPolicy.focus(item.id);
    // Off-TV / blank search prompt the hero isn't rendered, so don't track focus
    // or fire the per-item backdrop-enrichment /meta fetch behind it.
    if (!_heroActive) return;
    // Folders own the stage art too, but never request title metadata or video.
    if (item.type == 'folder') {
      _heroMetadataSubscription.read().cancel();
      _heroSwap.cancel();
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
      _heroSwap.cancel();
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
    _heroSwap.schedule(
      isCurrent: () => mounted,
      apply: () => _applyHero(item),
    );
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
    _heroPreviewPolicy.allowNewHero();
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
    final update = homeHeroAmbientArtUpdate(
      item: item,
      enriched: enriched,
      publishedItemId: _ambientArtItemId,
      publishedArt: MainPageBridge.tvAmbientArt.value,
    );
    if (update == null) return;
    _ambientArtItemId = update.itemId;
    MainPageBridge.tvAmbientArt.value = update.art;
  }

  /// Debounced ambient-trailer load for the spotlighted title. The previous
  /// trailer is torn down IMMEDIATELY on any hero change (a playing trailer
  /// under the wrong title is worse than the static backdrop), then a new one
  /// only starts once focus has RESTED on the card — flying across a row costs
  /// nothing but a timer reset, never a resolve or a decoder spin-up. Both
  /// lookups (Cinemeta /meta for the YouTube id, then the stream resolve) are
  /// cached in their services, so re-resting on a recent card starts fast.
  late final ProviderSubscription<MetadataFeaturePolicy>
  _metadataFeatureSubscription;
  late final MetadataFeatureController _metadataFeatureController;
  MetadataPreferences? get _metadataFeaturePolicy =>
      _metadataFeatureController.current.preferences;

  Future<void> _refreshMetadataFeaturePolicy() =>
      _metadataFeatureController.load(
        isCurrent: () => mounted,
        onAccepted: (prefs) {
          setState(() {});
          _scheduleTitleSuggestions();
          if (widget.discoverMode &&
              _discSource == _discTmdb &&
              !prefs.features.contains(MetadataFeature.discovery)) {
            _selectDiscoverSource(_discCw);
          }
        },
      );

  void _metadataSettingsChanged() {
    if (!mounted) return;
    _metadataFeatureController.invalidate();
    _cancelTitleSuggestions();
    unawaited(_refreshMetadataFeaturePolicy());
    _episodeArtworkController.refresh(
      isCurrent: () => mounted,
      onChanged: () => setState(() {}),
    );
    _clearHeroTrailer();
    _heroEnriched.value = null;
    final item = _heroItem.value;
    if (item != null) {
      _enrichHero(item);
      _scheduleHeroTrailer(item, fromSpotlight: _homeStyleEffective == 'spotlight');
    }
  }

  void _scheduleHeroTrailer(StremioMeta item, {bool fromSpotlight = false}) {
    // Search previews belong to the focused result card, never a hidden hero.
    if (widget.isTelevision && widget.searchMode) return;
    if (item.type == 'folder') return;
    if (!_heroPreviewPolicy.admitSchedule(
      item.id,
      fromSpotlight: fromSpotlight,
      renderableAndEnabled: () => _heroTrailerRenderable && _heroTrailerEnabled,
    )) {
      return;
    }
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
    if (!fromSpotlight && _heroPreviewPolicy.hasAttempted(item.id)) return;
    // Spotlight already owns the stage; other layouts wait for focus to rest.
    _heroTrailerLoaderSubscription.read().schedule(
      item,
      delay: fromSpotlight ? Duration.zero : const Duration(seconds: 2),
      isCurrent: () => mounted,
      reset: () {
        if (_heroTrailer.value != null) _heroTrailer.value = null;
        if (_heroTrailerLoading.value) _heroTrailerLoading.value = false;
        if (_heroTrailerShowing.value) _heroTrailerShowing.value = false;
      },
      begin: () {
        _heroPreviewPolicy.recordAttempt(item.id);
        // The layout may have changed during the dwell — a stage with nowhere
        // to put moving picture must not spin up an engine.
        if (_stageActive && !_stageWantsAmbient) return false;
        // Covered by ANY modal (bottom sheet, dialog — which never reach the
        // PageRoute-only route observer) or a pushed page: a trailer must not
        // start under it. The cover's dismissal path re-arms where relevant
        // (didPopNext for pages); sheets simply wait for the next hero rest.
        if (ModalRoute.of(context)?.isCurrent != true) return false;
        // From here the attempt is committed — surface the pill. Every exit
        // below (no trailer, failed resolve, hero moved on) clears it; success
        // keeps it up until the backdrop reports frames (_onHeroTrailerPlaying).
        _heroTrailerLoading.value = true;
        return true;
      },
      publish: (streams) => _heroTrailer.value = streams,
      fail: () => _heroTrailerLoading.value = false,
    );
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
    _heroTrailerLoaderSubscription.read().cancel();
    if (_heroTrailer.value != null) _heroTrailer.value = null;
    if (_heroTrailerLoading.value) _heroTrailerLoading.value = false;
    if (_heroTrailerShowing.value) _heroTrailerShowing.value = false;
  }

  /// DPAD focus rested on an IPTV favourite card — retune the boxed hero video
  /// region to that channel's live stream. A plain M3U/Xtream favourite's URL
  /// is already playable; a Stremio-addon favourite resolves candidates first
  /// (same async ladder [IptvResultsView] uses for its own inline preview),
  /// guarded by the live-preview owner so a fast DPAD move cannot land a stale
  /// resolve on top of whatever channel focus has since moved to.
  void _setHeroLiveIptv(IptvChannel channel) {
    if (!_heroTrailerActive) return;
    if (_heroLiveChannel.value?.url == channel.url) return;
    _heroLiveChannel.value = channel;
    if (!_heroLiveTakeover.value) _heroLiveTakeover.value = true;
    _heroLiveSubscription.read().load(
      channel.url,
      isCurrent: () => mounted,
      prepare: () {
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
      },
      publish: (url) => _heroLiveUrl.value = url,
    );
  }

  /// DPAD focus left the IPTV favourites row (another favourites row, or a
  /// catalog/CW card) — drop the live feed so the boxed region falls back to
  /// whatever catalog trailer [_heroItem] owns.
  void _clearHeroLiveIptv() {
    _heroLiveSubscription.read().invalidateRequest();
    final wasLive = _heroLiveChannel.value != null;
    if (wasLive) _heroLiveChannel.value = null;
    if (_heroLiveTakeover.value) _heroLiveTakeover.value = false;
    _heroLiveSubscription.read().clearCandidates();
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
    _heroLiveSubscription.read().playbackFailed(
      currentUrl: _heroLiveUrl.value,
      channelKey: () => _heroLiveChannel.value?.url,
      publish: (url) => _heroLiveUrl.value = url,
    );
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
    if (PlatformUtil.isAndroidTvCached) {
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _resumeHomeProgress();
      } else {
        _clearDeferredDown();
        _stageDeferredAdvance.reset();
      }
    }
    if (_heroTrailerActive) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) _heroShellBinding?.bindRoute(route);
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
    _heroPreviewPolicy.suppressForPlayback(
      () => _spotlightKey.currentState?.currentHeroId,
    );
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
  late final ProviderSubscription<HomeHeroTintLoader> _heroTintSubscription;

  void _updateHeroTint(StremioMeta item) => _heroTintSubscription.read().load(
    item,
    isCurrent: () => mounted,
    publish: (color) {
      _heroTint.value = color;
      _publishHeroTintToShell(color);
    },
  );

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

  /// Debounced backdrop/description enrichment. Catalog list items usually
  /// omit `background`/`description` (they come from the /meta endpoint), so
  /// fetch them lazily — cached in [StremioService], and guarded against the
  /// focus moving on (req id) so a slow fetch never clobbers a newer hero.
  Future<void> _enrichHero(StremioMeta item) =>
      _heroMetadataSubscription.read().load(
        item,
        isCurrent: () => mounted,
        onResolved: (details) {
          _heroEnriched.value = details;
          // Publish after enrichment so shell listeners see the accepted value.
          _publishAmbientArt(item, _heroEnriched.value);
        },
      );

  // ── Search field ─────────────────────────────────────────────────────────

  void _onTitleSearchTabChanged() {
    if (MainPageBridge.activeTab.value != 'search') {
      // Invalidate even if Search is reselected before the transition ends.
      _cancelTitleSuggestions();
    }
  }

  void _onTitleSearchEditingChanged() {
    final editing = _searchController.value;
    final composing = editing.composing.isValid && !editing.composing.isCollapsed;
    if (editing.text == _titleSearchText && composing == _titleSearchComposing) {
      return;
    }
    _titleSearchText = editing.text;
    _titleSearchComposing = composing;
    _cancelSuggestedTitleOpen();
    _scheduleTitleSuggestions();
  }

  void _scheduleTitleSuggestions() {
    final preferences = _metadataFeaturePolicy;
    final editing = _searchController.value;
    _titleSearch.update(
      editing.text,
      language: preferences?.language ?? 'en-US',
      // Title lookup belongs only to Catalog. Keyword, Lists and pasted
      // links retain their own search semantics.
      enabled: widget.searchMode && _mode == SearchMode.catalog &&
          MainPageBridge.activeTab.value == 'search' &&
          _titleSearchPolicyReady &&
          !_openingSuggestedTitle &&
          _titleSearchScope == ProfileRuntime.scope.value &&
          (preferences?.features.contains(MetadataFeature.discovery) ?? false),
      composing: editing.composing.isValid && !editing.composing.isCollapsed,
    );
  }

  void _cancelSuggestedTitleOpen() {
    _suggestedTitleOpenGeneration++;
    _openingSuggestedTitle = false;
  }

  void _cancelTitleSuggestions() {
    _cancelSuggestedTitleOpen();
    _titleSearch.clear();
  }

  void _publishTitleSuggestions() {
    final query = _searchController.text.trim();
    _titleSuggestions.value = [
      for (final item in _titleSearch.value)
        TextFieldSuggestion(
          id: '${item.type}:${item.id}',
          title: item.name,
          subtitle: [
            item.type == 'series' ? 'TV show' : 'Movie',
            if (item.year?.isNotEmpty == true) item.year!,
          ].join(' · '),
          year: item.year,
          onSelected: () => _openSuggestedTitle(item),
        ),
      if (_titleSearch.value.isNotEmpty)
        TextFieldSuggestion(
          id: 'search-query',
          title: 'Search for “$query”',
          subtitle: 'Search catalogs',
          onSelected: () => _onQuerySubmitted(query),
        ),
    ];
  }

  Future<void> _openSuggestedTitle(StremioMeta item) async {
    if (_openingSuggestedTitle || !mounted || _mode != SearchMode.catalog ||
        MainPageBridge.activeTab.value != 'search' ||
        _titleSearchScope != ProfileRuntime.scope.value) {
      return;
    }
    _searchSubmitFocus.cancel();
    _searchController.value = TextEditingValue(
      text: item.name,
      selection: TextSelection.collapsed(offset: item.name.length),
    );
    _cancelTitleSuggestions();
    // Filling the field above goes through the same edit/cancel listener as
    // typing. Capture ownership only after that update has finished.
    final generation = _suggestedTitleOpenGeneration;
    _openingSuggestedTitle = true;
    try {
      await openMetadataTitle(context, item, (selected) {
        if (!mounted || generation != _suggestedTitleOpenGeneration ||
            MainPageBridge.activeTab.value != 'search') {
          return;
        }
        _openItem(selected, selected.sourceAddon ?? StremioAddon(
          id: 'metadata_title', name: 'Title metadata', manifestUrl: '', baseUrl: '',
        ));
      }, resolve: widget.suggestedTitleResolver ?? MetadataTitleService.instance.resolve,
        onUnresolved: (unresolved) => _onQuerySubmitted(unresolved.name),
        isCurrent: () => mounted && generation == _suggestedTitleOpenGeneration &&
            _mode == SearchMode.catalog && MainPageBridge.activeTab.value == 'search');
    } finally {
      // A cancelled lookup can finish while a newer selection is loading.
      if (generation == _suggestedTitleOpenGeneration) {
        _openingSuggestedTitle = false;
      }
    }
  }

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
    _cancelTitleSuggestions();
    _catalogDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      _searchSubmitFocus.cancel();
    } else {
      _searchSubmitFocus.arm(enabled: widget.isTelevision);
    }
    switch (_mode) {
      case SearchMode.keyword:
        _runKeyword(q);
        return;
      case SearchMode.catalog:
        if (q.isEmpty) {
          _restoreHome();
        } else {
          _runCatalogSearch(q);
        }
        return;
      case SearchMode.lists:
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
    _cancelTitleSuggestions();
    _clearKeywordSearch();
    _disposeListsNodes();
    _listsController.clear();
    _restoreHome();
  }

  void _clearKeywordSearch() {
    _keywordSearchController.clear();
    _disposeKwNodes();
    _keywordResultsController.clear();
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

  void _onSearchProfileChanged() {
    _cancelTitleSuggestions();
    if (_profileSessionOwner != ProfileSessionMemory.captureOwner()) {
      _searchController.clear();
      _clearKeywordSearch();
      _clearListsSearch();
      final hadCatalogSearch = _catalogQuery.isNotEmpty || _catalogSearching;
      _catalogController.clear();
      if (hadCatalogSearch) _applySections(const []);
    }
  }

  void _clearListsSearch() {
    if (!mounted) return;
    _disposeListsNodes();
    _listsController.clear();
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

  /// Keep route/focus effects in presentation; the notifier owns requests,
  /// results, errors and stale-completion checks.
  Future<void> _runListsSearch(String query) async {
    if (!kMdblistEnabled) {
      _searchSubmitFocus.cancel();
      return;
    }
    if (query.trim().isEmpty) {
      _clearListsSearch();
      return;
    }
    _disposeListsNodes();
    final accepted = await _listsController.search(query);
    if (!mounted || !accepted) return;
    setState(_ensureListsNodes);
    if (_listsNodes.isEmpty) {
      _searchSubmitFocus.cancel();
    } else {
      _completeSearchSubmitFocus(_listsNodes.first);
    }
  }

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

  Future<void> _loadDefaultKeywordFilters() async {
    final changed = await _keywordResultsController.loadDefaults();
    if (mounted && changed && _kwAll.isNotEmpty) _syncKeywordResults();
  }

  /// One-shot: restore DPAD focus to the toolbar at the FIRST streamed paint
  /// (set by _openKeywordSources, whose re-search unmounts the focused pill).
  /// Consumed/cleared on present so a completion refocus can never yank the
  /// remote off a row the user reached mid-stream.
  bool _kwRefocusToolbar = false;

  Future<void> _runKeyword(String query, {bool refocusToolbar = false}) async {
    // Reject outgoing-view actions before changing its UI or resolving services.
    if (query.isEmpty || !_keywordSearchController.isCurrent) return;
    _keywordResultsController.begin();
    _kwRefocusToolbar = refocusToolbar;
    await _keywordSearchController.search(query);
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
      _keywordResultsController.present(raw);
      _syncKwTabNodes(); // live tabs: nodes track the parked set's sources
      setState(() {}); // pill count + tab strip update
      _reanchorKwTab(tabAnchor);
      return;
    }
    _keywordResultsController.present(raw);
    _syncKeywordResults();
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
    if (_keywordResultsController.finish()) _syncKeywordResults();
    setState(() {}); // searching strip off
    // Completion: await in-flight batch checks, sweep stragglers, then settle
    // cached-only mode over the authoritative full set.
    unawaited(_finalizeKeywordCache(full, token));
  }

  /// First real user interaction → stop live-reshuffling; buffer new arrivals
  /// behind the pill instead.
  void _kwFreeze() {
    _keywordResultsController.freeze();
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
    if (!_keywordResultsController.adopt()) return;
    _syncKeywordResults();
    if (focusedTorrent != null) {
      final key = _kwRowKey(focusedTorrent);
      final idx = _kwResults.indexWhere((t) => _kwRowKey(t) == key);
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && idx < _kwNodes.length) _kwNodes[idx].requestFocus();
        });
      }
    }
    unawaited(_keywordCacheController.check(_kwAll, _kwSearchToken));
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

  /// The fullest known result set: parked arrivals when frozen, else the
  /// displayed set. The tab strip derives from THIS so it live-updates
  /// (counts tick, new source pills appear) even while the rows are frozen —
  /// the strip sits above the list, so it never shifts what's being read.
  List<Torrent> get _kwFullSet => _kwPending ?? _kwAll;

  /// Distinct sources in [_kwFullSet], sorted — drives the tab strip.
  List<String> get _kwSourceList {
    final s = <String>{for (final t in _kwFullSet) keywordSourceOf(t)};
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
      _keywordFocus.focusTab(idx > 0 && idx < _kwTabNodes.length ? idx : 0);
    });
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
    _keywordResultsController.setSelectionMode(true);
    if (refocusToolbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _kwToolbarNodes.first.requestFocus();
      });
    }
  }

  void _exitKwSelection() {
    _keywordResultsController.setSelectionMode(false);
  }

  void _toggleKwSelection(Torrent t) =>
      _keywordResultsController.toggleSelection(t.infohash);

  void _selectAllKw() => _keywordResultsController.selectAll();

  /// Clear the selection but stay in selection mode (matches Home's "None").
  void _deselectAllKw() => _keywordResultsController.deselectAll();

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
            if (ProfilePolicyGuard.allowsSync(ProfileFeature.downloads) &&
                TorrentPlaybackService.supportsDirectStreamDownload(t))
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

  /// Completion-only cache changes explicitly recompute the displayed rows.
  void _recomputeKeyword() {
    _keywordResultsController.recompute();
    _syncKeywordResults();
  }

  void _syncKeywordResults() {
    _syncKwNodes(_kwResults.length);
    _syncKwTabNodes();
    setState(() {});
  }

  void _syncKwNodes(int length) => _keywordFocus.syncRows(length);
  void _syncKwTabNodes() => _keywordFocus.syncTabs(_kwSourceList.length);

  /// Badge updates never reconcile row nodes. Cached-only mode changes do,
  /// and only the completion accepted by this still-mounted search may do so.
  Future<void> _finalizeKeywordCache(List<Torrent> full, int token) async {
    final changed = await _keywordCacheController.finish(full, token);
    if (!mounted || token != _kwSearchToken) return;
    if (changed) _recomputeKeyword();
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
    _keywordResultsController.setFilters(result);
    _syncKeywordResults();
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
    _kwFreezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (_) => KeywordProvidersDialog(
        session: _searchSession,
        onChanged: () {
          if (mounted) _syncKeywordResults();
        },
      ),
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
                _keywordResultsController.setSort(value);
              });
              _syncKeywordResults();
            }

            void applyDir(bool asc) {
              setLocal(() => _keywordResultsController.setSortAscending(asc));
              _syncKeywordResults();
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
      builder: (_) => KeywordSourcesDialog(session: _searchSession),
    );
    if (!mounted || _kwQuery.isEmpty) return;
    // Re-search with the new enabled set.
    await _runKeyword(_kwQuery, refocusToolbar: fromToolbar);
  }

  void _disposeKwNodes() => _keywordFocus.clearRows();

  void _switchMode(SearchMode mode) {
    // Belt for every entry point at once: the keyword surface is gated per
    // profile (catalog search never is).
    if (mode == SearchMode.keyword &&
        !ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)) {
      return;
    }
    if (_mode == mode) return;
    _cancelTitleSuggestions();
    setState(() {
      _mode = mode;
      // Leaving the keyword list drops any in-progress multi-selection.
      _keywordResultsController.setSelectionMode(false);
    });
    // Carry the typed query across: if there's text in the box, run the target
    // mode's search immediately instead of showing the empty state.
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    switch (mode) {
      case SearchMode.keyword:
        if (query != _kwQuery) _runKeyword(query);
        return;
      case SearchMode.catalog:
        if (query != _catalogQuery) _runCatalogSearch(query);
        return;
      case SearchMode.lists:
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
    bool current() =>
        mounted && _profileSessionOwner == ProfileSessionMemory.captureOwner();
    if (!current()) return;
    final navigation = HomeDetailNavigation(
      ref.read(homeCatalogOriginRepositoryProvider(_profileSessionOwner)),
    );
    unawaited(
      navigation.open(
        context: context,
        item: item,
        addon: addon,
        routeName: kCatalogDetailRouteName,
        isCurrent: current,
        hasLocalHistory: (item) => _cwIds.contains(item.imdbId),
        removeLocalHistory: _removeLocalHistory,
        onHistoryRemoved: () async {
          _clearSeriesResume();
          await _loadContinueWatching();
        },
        showMessage: _snack,
        onClosed: () {
          unawaited(_refreshAfterPlayback());
          _refreshTraktAuthState();
          _refreshSimklAuthState();
          _refreshMdblistAuthState();
          if (returnToTabOnClose != null) {
            MainPageBridge.switchTab?.call(returnToTabOnClose);
          }
        },
        prepareBuilder: (item, addon, detailRoute) {
          _activeAddonId = addon.id;
          final imdb = _imdbOf(item);
          // Show a "Remove from Continue Watching" action when this title is on the
          // Continue Watching row (regardless of which row opened it).
          final inCw = imdb != null && _cwIds.contains(imdb);
          // Same for the Trakt Continue Watching rows — removal goes through the
          // Trakt playback/history APIs rather than local storage.
          final inTraktCw = imdb != null && _traktByImdb.containsKey(imdb);
          final inMdblistCw =
              imdb != null && _mdblistByImdb[imdb]?.paused == true;

          final menus = HomeDetailMenus(
            type: item.type,
            identity: imdb,
            removalColor: AppThemeScope.of(context).home.danger,
            inLocalContinueWatching: inCw,
            inTraktContinueWatching: inTraktCw,
            inMdblistContinueWatching: inMdblistCw,
            hasBoundSource: () => _isBound(item),
            traktAuthenticated: () => _isTraktAuthenticated,
            simklAuthenticated: () => _isSimklAuthenticated,
            mdblistAuthenticated: () => _isMdblistAuthenticated,
            hasSimklPause: () =>
                _simklByImdb[_simklCardKey(item)]?.progress != null,
          );

          // Choose the layout at opening time, as before, rather than on a route rebuild.
          final mergedDetail = _mergedSeriesPage;
          final readers = ref.read(
            homeDetailReadersProvider(_profileSessionOwner),
          );
          bool detailCurrent() => detailRoute.isActive;
          return (_) => buildHomeDetail(
            item: item,
            addon: addon,
            merged: mergedDetail,
            isTelevision: widget.isTelevision,
            pikpakOnly: _pikpakOnly,
            hasBoundSource: () => _isBound(item),
            isTraktSource: isTraktSource,
            isMdblistSource: isMdblistSource,
            heroTag: heroTag,
            initialSeason: initialSeason,
            initialEpisode: initialEpisode,
            resumeInfo: () => _resolveResumeInfo(
              item,
              addon,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
            ),
            play:
                ({
                  bool startFromBeginning = false,
                  bool preferTraktResume = false,
                  bool skipEpisodeFallback = false,
                  bool browseSourcesOnly = false,
                  HomeDetailPromise? promisedTarget,
                }) => _onCatalogPlay(
                  item,
                  addon,
                  isCurrent: () => detailRoute.isActive,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                  startFromBeginning: startFromBeginning,
                  preferTraktResume: preferTraktResume,
                  skipEpisodeFallback: skipEpisodeFallback,
                  browseSourcesOnly: browseSourcesOnly,
                  promisedTarget: promisedTarget,
                ),
            browse: () => _onCatalogBrowse(
              item,
              addon,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
            ),
            browseSelection: (selection) => _browseSelection(
              selection,
              metadataAddonId: addon.id,
              catalogItem: item.withSourceAddon(addon),
            ),
            playSelection: (selection) => _playSelection(
              selection,
              metadataAddonId: addon.id,
              catalogItem: item.withSourceAddon(addon),
            ),
            boundSourceCount: _boundCountFor,
            selectSource: (show) {
              if (!detailRoute.isActive) return Future.value();
              _activeAddonId = addon.id;
              return _handleEditOrSelectSource(
                show.withSourceAddon(addon),
                isCurrent: () => detailRoute.isActive,
              );
            },
            adoptArtwork: (art) => _playbackArtwork.adopt(item, art),
            menus: menus,
            traktAction: (action, {rating}) => _handleDetailQuickAction(
              item,
              addon,
              action,
              inCw: inCw,
              detailRoute: detailRoute,
              imdb: imdb,
              presetRating: rating,
            ),
            traktStatus:
                (_isTraktAuthenticated &&
                    imdb != null &&
                    MediaIdentity.isImdb(imdb))
                ? () => readers.trakt(imdb, item.type, isCurrent: detailCurrent)
                : null,
            simklAction: (action, {rating}) => _handleDetailSimklQuickAction(
              item,
              action,
              detailRoute: detailRoute,
              presetRating: rating,
            ),
            simklStatus: (_isSimklAuthenticated && imdb != null)
                ? () => readers.simkl(imdb, item.type, isCurrent: detailCurrent)
                : null,
            mdblistAction: (action, {rating}) =>
                _handleDetailMdblistQuickAction(
                  item,
                  action,
                  detailRoute: detailRoute,
                  presetRating: rating,
                ),
            mdblistStatus:
                (_isMdblistAuthenticated &&
                    imdb != null &&
                    MediaIdentity.isImdb(imdb))
                ? () =>
                      readers.mdblist(imdb, item.type, isCurrent: detailCurrent)
                : null,
            recommendations: imdb != null && MediaIdentity.isImdb(imdb)
                ? () => readers.recommendations(
                    imdb,
                    item.type,
                    isCurrent: detailCurrent,
                  )
                : null,
            openRecommendation: (rec) =>
                _openItem(rec, rec.sourceAddon ?? addon),
            enrich: (id, type) =>
                readers.metadata(id, type, isCurrent: detailCurrent),
          );
        },
      ),
    );
  }

  HomeDetailActionBridge _detailActionBridge(HomeDetailRoute route) =>
      HomeDetailActionBridge(
        isCurrent: () => _catalogNavigationCurrent() && route.isActive,
        isSearch: () => widget.searchMode,
        clearResume: _clearSeriesResume,
        refreshLocal: _loadContinueWatching,
        refreshTrakt: () => _loadTraktContinueWatching(refreshBound: false),
        refreshSimkl: () => _loadSimklContinueWatching(refreshBound: false),
        refreshMdblist: () => _loadMdblistContinueWatching(refreshBound: false),
      );

  Future<void> _handleDetailQuickAction(
    StremioMeta item,
    StremioAddon addon,
    TraktItemMenuAction action, {
    required bool inCw,
    required HomeDetailRoute detailRoute,
    String? imdb,
    int? presetRating,
  }) => _detailActionBridge(detailRoute).trakt(
    action,
    removeLocal: () async {
      if (imdb != null) {
        await _handleContinueDetailAction(action, imdb, detailRoute);
      }
    },
    removeTrakt: () async {
      if (imdb != null) {
        await _removeFromTraktContinueWatching(imdb, detailRoute: detailRoute);
      }
    },
    invoke: (clearOnly) async {
      if (clearOnly) {
        await handleTraktMenuAction(
          context,
          item,
          action,
          actions: ref.read(homeDetailActionsProvider(_profileSessionOwner)),
          isCurrent: () => _catalogNavigationCurrent() && detailRoute.isActive,
        );
        return;
      }
      _activeAddonId = addon.id;
      await handleTraktMenuAction(
        context,
        item.withSourceAddon(addon),
        action,
        onSelectSource: (item) =>
            _openSourceBinding(item, isCurrent: () => detailRoute.isActive),
        onEditSource: (item) => _handleEditOrSelectSource(
          item,
          isCurrent: () => detailRoute.isActive,
        ),
        onPlayRandomEpisode: (m) => _playRandomEpisodeFromDetail(m, addon),
        onSearchPacks: _searchPacksFromDetail,
        onAddToStremioTv: (item) =>
            _addToStremioTvFromDetail(item, detailRoute),
        actions: ref.read(homeDetailActionsProvider(_profileSessionOwner)),
        presetRating: presetRating,
        isCurrent: () => _catalogNavigationCurrent() && detailRoute.isActive,
      );
    },
  );

  Future<void> _handleDetailSimklQuickAction(
    StremioMeta item,
    SimklItemMenuAction action, {
    required HomeDetailRoute detailRoute,
    int? presetRating,
  }) => _detailActionBridge(detailRoute).simkl(
    action,
    invoke: () => handleSimklMenuAction(
      context,
      item,
      action,
      actions: ref.read(homeDetailActionsProvider(_profileSessionOwner)),
      presetRating: presetRating,
      isCurrent: () => _catalogNavigationCurrent() && detailRoute.isActive,
      removeContinueWatching: () => ref
          .read(homeSimklHistoryRemovalProvider(_profileSessionOwner))
          .remove(
            item.progressId ?? item.id,
            item.type,
            isCurrent: () =>
                _catalogNavigationCurrent() && detailRoute.isActive,
          ),
    ),
  );

  Future<void> _handleDetailMdblistQuickAction(
    StremioMeta item,
    MdblistItemMenuAction action, {
    required HomeDetailRoute detailRoute,
    int? presetRating,
  }) => _detailActionBridge(detailRoute).mdblist(
    action,
    remove: () => _removeMdblistCwItem(item),
    invoke: () => handleMdblistMenuAction(
      context,
      item,
      action,
      actions: ref.read(homeDetailActionsProvider(_profileSessionOwner)),
      presetRating: presetRating,
      isCurrent: () => _catalogNavigationCurrent() && detailRoute.isActive,
    ),
  );

  Future<void> _handleEditOrSelectSource(
    StremioMeta item, {
    bool Function()? isCurrent,
  }) async {
    bool current() =>
        _catalogNavigationCurrent() && (isCurrent?.call() ?? true);
    if (!current()) return;
    await HomeSourceEditor(
      context: context,
      item: item,
      id: _imdbOf(item),
      repository: ref.read(
        homeSourceEditingRepositoryProvider(_profileSessionOwner),
      ),
      localPicker: ref.read(localSourcePickerProvider),
      isCurrent: current,
      refreshBindings: _refreshBoundSources,
      showMessage: _snack,
      openTorrent: (item) => _openSourceBinding(item, isCurrent: current),
      openKeyword: (item) =>
          _openSourceBinding(item, keyword: true, isCurrent: current),
    ).open();
  }

  Future<void> _addToStremioTvFromDetail(
    StremioMeta item,
    HomeDetailRoute route,
  ) async {
    bool current() => _catalogNavigationCurrent() && route.isActive;
    if (!current()) return;
    final result = await StremioTvCatalogPickerDialog.show(
      context,
      item: item,
      isCurrent: current,
    );
    if (!current() || result == null) return;
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

  Future<void> _playRandomEpisodeFromDetail(
    StremioMeta item,
    StremioAddon addon,
  ) {
    bool current() =>
        mounted && _profileSessionOwner == ProfileSessionMemory.captureOwner();
    if (!current()) return Future.value();
    return runHomeRandomPlayback(
      context: context,
      item: item,
      addon: addon,
      isCurrent: current,
      prepare: (continuous) => ref
          .read(homeRandomPlaybackRepositoryProvider(_profileSessionOwner))
          .prepare(
            item: item,
            addon: addon,
            progressId: _imdbOf(item),
            continuous: continuous,
            isCurrent: current,
          ),
      showMessage: _snack,
      launch: _playSelection,
    );
  }

  Future<void> _onCatalogPlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool startFromBeginning = false,
    bool skipEpisodeFallback = false,
    bool preferTraktResume = false,
    ({bool started, int season, int episode})? promisedTarget,
    bool browseSourcesOnly = false,
    bool Function()? isCurrent,
  }) async {
    bool current() =>
        _catalogNavigationCurrent() && (isCurrent?.call() ?? true);
    if (!current()) return;
    await HomeCatalogPlayAction(
      log: debugPrint,
      origin: ref.read(
        homeCatalogOriginRepositoryProvider(_profileSessionOwner),
      ),
      policies: ref.read(
        homeTrackingPolicyRepositoryProvider(_profileSessionOwner),
      ),
      targets: ref.read(
        homeCatalogPlaybackResolverProvider(_homeCatalogSession),
      ),
      identity: ref.read(
        homeCatalogEpisodeIdentityProvider(_profileSessionOwner),
      ),
      artwork: _playbackArtwork,
    ).run(
      context,
      item,
      addon,
      isCurrent: current,
      availability: () => (
        trakt: _isTraktAuthenticated,
        simkl: _isSimklAuthenticated,
        mdblist: _isMdblistAuthenticated,
      ),
      cachedTrakt: (item) =>
          _traktByImdb[item.progressId] ?? _traktByImdb[item.id],
      showMessage: _snack,
      activateAddon: (id) => _activeAddonId = id,
      openEpisodes: _openEpisodes,
      browse: _browseSelection,
      play: _playSelection,
      isTraktSource: isTraktSource,
      isMdblistSource: isMdblistSource,
      startFromBeginning: startFromBeginning,
      skipEpisodeFallback: skipEpisodeFallback,
      preferTraktResume: preferTraktResume,
      promisedTarget: promisedTarget,
      browseSourcesOnly: browseSourcesOnly,
    );
  }

  void _clearSeriesResume() {
    if (mounted) _seriesResumeResolverSubscription.read().clear();
  }

  HomeSeriesResumeRepository get _seriesResumeRepository =>
      ref.read(homeSeriesResumeRepositoryProvider(_profileSessionOwner));

  Future<TrackingSourcePolicy?> _loadTrackingPolicy(StremioMeta item) async {
    bool current() =>
        mounted && _profileSessionOwner == ProfileSessionMemory.captureOwner();
    if (!current()) return null;
    return ref
        .read(homeTrackingPolicyRepositoryProvider(_profileSessionOwner))
        .loadForContent(item.progressId, isCurrent: current);
  }

  Future<HomeResumePosition> _resolveResumeInfo(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) async {
    final trackingPolicy = await _loadTrackingPolicy(item);
    if (!_catalogNavigationCurrent() || trackingPolicy == null) {
      return (started: false, season: null, episode: null);
    }
    return ref
        .read(homeCatalogPlaybackResolverProvider(_homeCatalogSession))
        .label(
          item,
          addon,
          trackingPolicy: trackingPolicy,
          availability: () => (
            trakt: _isTraktAuthenticated,
            simkl: _isSimklAuthenticated,
            mdblist: _isMdblistAuthenticated,
          ),
          cachedTrakt: () =>
              _traktByImdb[item.progressId] ?? _traktByImdb[item.id],
          isCurrent: _catalogNavigationCurrent,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        );
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
        homeCatalogMovieSelection(
          item,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        ),
        metadataAddonId: addon.id, catalogItem: item.withSourceAddon(addon),
      );
    }
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
              onQuickPlay: (selection) => _playSelection(
                selection, metadataAddonId: addon.id, catalogItem: item.withSourceAddon(addon),
              ),
              onItemSelected: (selection) => _browseSelection(
                selection, metadataAddonId: addon.id, catalogItem: item.withSourceAddon(addon),
              ),
              // "Select Source" button: manage/pin sources via the same picker
              // the detail screen uses (edit dialog when already bound, else the
              // Torrent Search / Local / RD / TorBox picker) for a consistent
              // entry point.
              boundSourceCount: _boundCountFor,
              onSelectSource: (show) {
                _activeAddonId = addon.id;
                return _handleEditOrSelectSource(show.withSourceAddon(addon));
              },
            ),
          ),
        )
        .then((_) {
          // EpisodesScreen can mark watched / play; its plays route through
          // _playSelection (which clears too), but marks don't — never let a
          // pre-visit reconciled answer survive the trip.
          _clearSeriesResume();
          _refreshBoundSources();
        });
  }

  /// Binding payloads and keyword seeds belong to the Sources presentation bridge.
  void _openSourceBinding(
    StremioMeta item, {
    bool keyword = false,
    bool Function()? isCurrent,
  }) {
    bool current() =>
        _catalogNavigationCurrent() && (isCurrent?.call() ?? true);
    if (!current()) return;
    unawaited(
      ref
          .read(homeSourcesNavigationProvider)
          .bindCatalog(
            context,
            item: item,
            progressId: _imdbOf(item),
            keyword: keyword,
            buildMeta: (selection) => _metaFor(selection, catalogItem: item),
            isTelevision: () => widget.isTelevision,
            isCurrent: current,
            onReturned: _refreshBoundSources,
          ),
    );
  }

  PlaybackMeta _metaFor(
    AdvancedSearchSelection sel, {
    String? addonId,
    StremioMeta? catalogItem,
  }) => homeCatalogPlaybackMeta(
    sel,
    addonId: addonId,
    fallbackAddonId: _activeAddonId,
    catalogItem: catalogItem,
    art: _playbackArtwork.forSelection(sel.imdbId, sel.title),
  );

  final HomePlaybackArtwork _playbackArtwork = HomePlaybackArtwork();

  /// Catalog auto-best play — the service picks the provider, shows the real
  /// cinematic overlay, searches, and plays (with source list + content
  /// metadata so the in-player Sources switcher + Continue Watching work).
  Future<void> _playSelection(
    AdvancedSearchSelection sel, {
    String? metadataAddonId,
    StremioMeta? catalogItem,
  }) async {
    bool current() =>
        mounted && _profileSessionOwner == ProfileSessionMemory.captureOwner();
    if (!current()) return;
    // Capture the originating detail's provider for delayed Sources handoffs.
    final addonId = metadataAddonId ?? _activeAddonId;
    // No pre-playback reconciled answer may survive into post-playback reads.
    _clearSeriesResume();
    await ref
        .read(homeCatalogPlaybackBridgeProvider)
        .play(
          context,
          selection: sel,
          buildMeta: () =>
              _metaFor(sel, addonId: addonId, catalogItem: catalogItem),
          // Honor "Play button opens" for this exact episode. A manual source tap
          // must play directly rather than asking the user's intent a second time.
          openSourcePicker: () => _browseSelection(
            sel,
            forcePlayOnTap: true,
            metadataAddonId: addonId,
            catalogItem: catalogItem,
          ),
          isCurrent: current,
          refreshBoundSources: _refreshBoundSources,
          refreshAfterPlayback: _refreshAfterPlayback,
        );
  }

  bool _catalogNavigationCurrent() =>
      mounted && _profileSessionOwner == ProfileSessionMemory.captureOwner();

  /// Manual sources list in-tab — the screen searches itself (own loading) and
  /// each tap plays with the full source list + content metadata.
  void _browseSelection(
    AdvancedSearchSelection sel, {
    // Play has already expressed intent; manual Sources keeps the usual prompt.
    bool forcePlayOnTap = false,
    String? metadataAddonId,
    StremioMeta? catalogItem,
  }) {
    if (!_catalogNavigationCurrent()) return;
    unawaited(
      ref
          .read(homeSourcesNavigationProvider)
          .browse(
            context,
            selection: sel,
            buildMeta: () => _metaFor(
              sel,
              addonId: metadataAddonId,
              catalogItem: catalogItem,
            ),
            isTelevision: () => widget.isTelevision,
            forcePlayOnTap: forcePlayOnTap,
            isCurrent: _catalogNavigationCurrent,
            onReturned: _refreshAfterPlayback,
          ),
    );
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
            right: HomeSpotlightSearchButton.rightInset,
            child: HomeSpotlightSearchButton(
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
  void _onSearchFocusForSources() => _searchFocus.onFieldFocusForSources();

  /// On the unified (non-TV) layout there's no dedicated Search tab, so the
  /// catalog Sources button lives just under the search field and appears while
  /// that field is focused (clicked into) in Catalog mode — click away and it
  /// hides. TV keeps it in the dedicated Search tab's prompt instead, so this
  /// renders nothing there.
  Widget _buildUnifiedCatalogSourcesBar() {
    if (widget.isTelevision || widget.searchMode) {
      return const SizedBox.shrink();
    }
    final show = _catalogSourcesBarShown && _mode == SearchMode.catalog;
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
    // cannot fit, [SearchModeToggle] becomes a single dropdown.
    final hasLists = kMdblistEnabled && _isMdblistAuthenticated;
    // Reserve the three-mode layout whenever the integration is compiled in,
    // even before the async auth check lands. This avoids a one-frame inline →
    // stacked jump for connected users on medium-width windows.
    final narrowBreakpoint = kMdblistEnabled ? 900.0 : 620.0;
    final narrow = !tv && MediaQuery.of(context).size.width < narrowBreakpoint;
    final compactModeMenu = _useCompactModeMenu;

    final field = _buildSearchField(tv);
    final toggle = SearchModeToggle(
      mode: _mode,
      isTelevision: tv,
      listsAvailable: hasLists,
      keywordAvailable: ProfilePolicyGuard.allowsSync(
        ProfileFeature.keywordSearch,
      ),
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

    return SearchHeader(
      tv: tv,
      dedicatedSearch: widget.searchMode,
      narrow: narrow,
      compactModeMenu: compactModeMenu,
      field: field,
      toggle: toggle,
    );
  }

  /// Centered translucent pill search — mirrors Stremio's search bar (rounded
  /// pill, centered text, a search glyph on the right that becomes a clear ✕).
  Widget _buildSearchField(bool tv) => SearchQueryField(
    tv: tv,
    dedicatedSearch: widget.searchMode,
    mode: _mode,
    controller: _searchController,
    focusNode: _searchFocusNode,
    suggestions: widget.searchMode && _mode == SearchMode.catalog
        ? _titleSuggestions
        : null,
    onChanged: _onQueryChanged,
    onSubmitted: _onQuerySubmitted,
    onClear: _clearQuery,
    onFocusMode: _focusModeToggle,
    onFocusContent: () {
      if (_kwSourcesButtonVisible) {
        _kwSourcesBtnFocus.requestFocus();
      } else if (_catalogSourcesButtonVisible) {
        _catalogSourcesBtnFocus.requestFocus();
      } else {
        _focusContent();
      }
    },
    onFocusSidebar: () => MainPageBridge.focusTvSidebar?.call(),
  );

  Widget _buildBody() {
    if (_mode == SearchMode.keyword) return _buildKeyword();
    if (_mode == SearchMode.lists) return _buildListsSearch();
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
      builder: (_) => CatalogSourcesDialog(session: _searchSession),
    );
    if (!mounted) return;
    if (_catalogQuery.isNotEmpty) {
      _runCatalogSearch(_catalogQuery);
    }
  }

  Widget _buildKeyword() => LayoutBuilder(
    builder: (context, constraints) => _buildKeywordContent(
      cinema: useCinemaSourcesLayout(
        constraints,
        isTelevision: widget.isTelevision,
      ),
    ),
  );

  void _activateKeywordResult(
    BuildContext context,
    Torrent torrent,
    int index,
  ) {
    if (_kwSelectionMode &&
        !torrent.isDirectStream &&
        !torrent.isExternalStream) {
      _toggleKwSelection(torrent);
      return;
    }
    // Ignore Select leaking from a closing toolbar dialog; freeze before playback.
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _kwFreeze();
    unawaited(
      TorrentPlaybackService.activateTorrent(
        context,
        torrent,
        sources: _kwResults,
        sourceIndex: index,
        searchKeyword: _kwQuery,
      ),
    );
  }

  void _longPressKeywordResult(Torrent torrent, int index) {
    if (!torrent.isDirectStream && !torrent.isExternalStream) {
      _enterKwSelection();
      _toggleKwSelection(torrent);
    } else {
      _kwFreeze();
      _showKwStreamMenu(torrent, index);
    }
  }

  void _focusAboveKeywordResults() {
    if (_kwPendingNewCount > 0 && !_kwSelectionMode) {
      _kwPillFocus.requestFocus();
    } else if (_kwToolbarVisible) {
      _kwToolbarNodes.first.requestFocus();
    } else {
      _searchFocusNode.requestFocus();
    }
  }

  Widget _buildKeywordContent({required bool cinema}) => KeywordSearchPage(
    search: _keywordSearchState,
    isTelevision: widget.isTelevision,
    messageBuilder: _message,
    sourcesBuilder: (_) => _kwSourcesButton(),
    resultsBuilder: (_) => _buildKeywordResults(cinema: cinema),
  );

  Widget _buildKeywordResults({required bool cinema}) {
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
        if (!cinema && _kwTabsVisible && !_kwSelectionMode) _kwSourceTabs(),
        _buildKeywordToolbar(floatingSelect: narrow),
        if (_kwSearching && !cinema) const KeywordSearchingStrip(),
        if (_kwCachedOnly && _kwAll.isNotEmpty) _kwCachedOnlyNotice(),
        Expanded(
          child: KeywordResultsList(
            state: _keywordResults,
            cache: _kwCache,
            appearance: _keywordAppearanceSubscription.read(),
            isTelevision: widget.isTelevision,
            cinema: cinema,
            scrollController: _kwScroll,
            focusNodes: _kwNodes,
            onFreeze: _kwFreeze,
            onFocusAbove: _focusAboveKeywordResults,
            onCopy: (torrent) => unawaited(_copyKwLink(torrent)),
            onActivate: _activateKeywordResult,
            onLongPress: _longPressKeywordResult,
            emptyBuilder: (_) => _message(
              Icons.search_off_rounded,
              _kwAll.isEmpty ? 'No results' : 'No matches',
              _kwAll.isEmpty
                  ? 'Nothing found for "$_kwQuery". Try different '
                        'keywords or enable more sources.'
                  : 'No results match your filters. Adjust or clear them.',
            ),
            // Never renumber selected rows by adopting arrivals mid-selection.
            pendingResults: _kwPendingNewCount > 0 && !_kwSelectionMode
                ? _kwNewResultsPill()
                : null,
          ),
        ),
      ],
    );

    return KeywordResultsFrame(
      cinema: cinema,
      narrow: narrow,
      isTelevision: widget.isTelevision,
      search: _keywordSearchState,
      results: _keywordResults,
      full: _kwFullSet,
      sources: _kwSourceList,
      cinemaKey: _kwCinemaKey,
      onProviderSelected: (source) {
        _lastKeywordCinemaSource = 0;
        // Keep the rail's row-zero target mounted after a source switch.
        _pendingKwScroll = null;
        _kwLastScroll = 0;
        if (_kwScroll.hasClients) _kwScroll.jumpTo(0);
        _setKwSourceTab(source);
      },
      onFocusAbove: () => _searchFocusNode.requestFocus(),
      onFocusResults: () {
        if (_kwNodes.isNotEmpty) {
          _kwNodes[_lastKeywordCinemaSource.clamp(0, _kwNodes.length - 1)]
              .requestFocus();
        } else {
          _kwToolbarNodes.first.requestFocus();
        }
      },
      isSourceFocused: () {
        final index = _kwNodes.indexWhere((node) => node.hasFocus);
        if (index >= 0) {
          _lastKeywordCinemaSource = index;
          _kwFreeze();
        }
        return index >= 0;
      },
      selectionOverlay: cinema || !narrow || _kwSelectableResults.isEmpty
          ? null
          : KeywordSelectionOverlay(
              selectionMode: _kwSelectionMode,
              selectableCount: _kwSelectableResults.length,
              selectedCount: _kwSelected.length,
              floatingNavigation:
                  MainPageBridge.phoneNavStyleCached == 'floating',
              onSelect: _enterKwSelection,
              onCancel: _exitKwSelection,
              onDeselectAll: _deselectAllKw,
              onSelectAll: _selectAllKw,
              onAdd: _openBulkAdd,
            ),
      child: content,
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

  /// Horizontal source tabs (All / per-source with counts) above the toolbar —
  /// the fast single-select layer on top of the Providers multi-select. Only
  /// built when [_kwTabsVisible] (2+ sources). Derives from [_kwFullSet]:
  /// counts tick and new source pills appear live even while the rows below
  /// are frozen behind the pill (activating any tab folds the parked set in
  /// first, so what a tab press shows is always the complete picture). DPAD:
  /// left/right across tabs, up to the search field, down into the toolbar,
  /// select to activate.
  Widget _kwSourceTabs() => KeywordSourceTabs(
    sources: _kwSourceList,
    full: _kwFullSet,
    selectedSource: _kwSourceTab,
    focusNodes: _kwTabNodes,
    onKey: _keywordFocus.handleTabKey,
    onChanged: _setKwSourceTab,
  );

  void _setKwSourceTab(String? source) {
    final tabHadFocus = _kwTabNodes.any((n) => n.hasFocus);
    // A deliberate reshuffle: fold parked arrivals in so the tab filters the
    // complete set (also freezes further live updates).
    _kwFreezeAndAdopt();
    if (_keywordResultsController.setSourceTab(source)) _syncKeywordResults();
    source = _kwSourceTab;
    // Tab nodes are positional and the adopt can re-sort _kwSourceList —
    // re-anchor DPAD focus onto the tab that was actually chosen.
    if (tabHadFocus) {
      final s = source;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final idx = s == null ? 0 : _kwSourceList.indexOf(s) + 1;
        _keywordFocus.focusTab(idx > 0 && idx < _kwTabNodes.length ? idx : 0);
      });
    }
  }

  /// DPAD/keyboard handling for a focused source tab: select activates,
  /// left/right move between tabs (left edge escapes to the sidebar), up
  /// returns to the search field, down drops into the toolbar pills.
  /// The "+N new results" pill: tap (or OK on TV) folds the parked arrivals
  /// into the list; DOWN returns to the rows, UP reaches the toolbar.
  Widget _kwNewResultsPill() => KeywordNewResultsPill(
    count: _kwPendingNewCount,
    focusNode: _kwPillFocus,
    onAdopt: _kwAdoptPending,
    onFocusResults: () {
      if (_kwNodes.isNotEmpty) _kwNodes.first.requestFocus();
    },
    onFocusToolbar: () => _kwToolbarNodes.first.requestFocus(),
  );

  /// [floatingSelect] true on small screens where the multi-select entry is a
  /// floating FAB + bar (Home-style) rather than a toolbar pill — so the
  /// toolbar stays Sort/Filters/Sources and never swaps to selection controls.
  Widget _buildKeywordToolbar({bool floatingSelect = false}) => KeywordToolbar(
    selectionMode: _kwSelectionMode,
    floatingSelect: floatingSelect,
    selectableCount: _kwSelectableResults.length,
    selectedCount: _kwSelected.length,
    // Every facet counts, including size-only and dynamic-range-only filters.
    filterCount:
        _kwFilters.qualities.length +
        _kwFilters.ripSources.length +
        _kwFilters.languages.length +
        _kwFilters.sizes.length +
        _kwFilters.dynamicRanges.length,
    showProviderFilter: _kwHasProviderFilter,
    providerFilterCount: _kwProviderFilterActive,
    sortLabel: _sortLabel(_kwSort),
    focusNodes: _kwToolbarNodes,
    onKey: _keywordFocus.handleToolbarKey,
    onCancel: _exitKwSelection,
    onDeselectAll: _deselectAllKw,
    onSelectAll: _selectAllKw,
    onAdd: _openBulkAdd,
    onSort: _openKeywordSort,
    onFilters: _openKeywordFilters,
    onProviders: _openKeywordProviders,
    onSources: _openKeywordSources,
    onSelect: _enterKwSelection,
  );

  /// Resolve the route's current target above the Keyword toolbar.
  void _focusAboveKeywordToolbar() {
    // Source tabs sit between the toolbar and the search field — land on
    // the active tab so the strip context is obvious. Hidden during
    // multi-select (the strip is suppressed then — see _buildKeyword).
    if (!_kwSelectionMode && _kwCinemaKey.currentState != null) {
      _kwCinemaKey.currentState!.focusSelectedProvider();
      return;
    }
    if (!_kwSelectionMode && _kwTabsVisible && _kwTabNodes.isNotEmpty) {
      final tabs = _kwSourceList;
      final active = _kwSourceTab == null ? 0 : tabs.indexOf(_kwSourceTab!) + 1;
      _keywordFocus.focusTab(
        active >= 0 && active < _kwTabNodes.length ? active : 0,
      );
      return;
    }
    _focusSearchFieldAtEnd();
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
      homeRailPosterWidth(context, isTelevision: widget.isTelevision,
        searchResults: widget.searchMode);

  Size _railTitleCardSize(BuildContext context) => homeClassicCardSize(
    posterWidth: _railPosterW(context),
    landscape: _homeLandscapeCards,
  );

  double _railTitleCardW(BuildContext context) =>
      _railTitleCardSize(context).width;
  double _railTitleCardH(BuildContext context) =>
      _railTitleCardSize(context).height;

  double _tvHeroBudget(double boardH) => homeClassicHeroBudget(
    boardHeight: boardH,
    cardHeight: _railTitleCardH(context),
    isTelevision: widget.isTelevision,
    searchResults: widget.searchMode,
  );

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
  Future<void> _loadDiscoverAddons() => _discoverSourceController.load(
    isCurrent: () => mounted,
    mdblistEnabled: kMdblistEnabled,
    discoveryEnabled: () async {
      if (_metadataFeaturePolicy == null) await _refreshMetadataFeaturePolicy();
      return _metadataFeaturePolicy?.features.contains(
            MetadataFeature.discovery,
          ) ==
          true;
    },
    onInventory: (addons) {
      for (final addon in addons) {
        _addonsById.putIfAbsent(addon.id, () => addon);
      }
    },
    onChanged: () => setState(() {}),
  );

  /// The Discover tab: a "Source" dropdown over a single browsable grid. Each
  /// source is rendered by the matching See-All panel in [embedded] mode (no
  /// Scaffold/back header), with the Source dropdown injected as its leading
  /// filter so DPAD walks Source → the panel's own filters → grid. All item
  /// open/play/bound wiring is this screen's existing board handlers.
  Widget _buildDiscover() => DiscoverBrowsingInput(
    onActivity: _discPreview.onActivity,
    child: _buildDiscoverContent(),
  );

  Widget _buildDiscoverContent() => buildDiscoverContent(
    context,
    sourcePanel: _buildDiscoverPanel(),
    cardSettings: _discCardSettings,
    showPreview:
        widget.isTelevision &&
        _discSource != _discJellyfin &&
        _discSource != _discEmby,
    stage: _discStage,
    focused: _discFocused,
    preview: _discPreview,
    isCurrent: () => mounted,
    loadingIndicator: (visible) => HomeHeroTrailerLoadingPill(visible: visible),
    ambientIndicator: (visible) => HomeHeroAmbientChip(visible: visible),
  );

  void _selectDiscoverSource(String source) {
    final selected = _discoverSourceController.select(
      source,
      discoveryEnabled:
          _metadataFeaturePolicy?.features.contains(
            MetadataFeature.discovery,
          ) ==
          true,
      isCurrent: () => mounted,
      beforeChange: () {
        _discFocused.value = null;
        _discPreview.shown.value = null;
        if (source == _discJellyfin || source == _discEmby) {
          _discPreview.resetPlayback();
        }
      },
      onChanged: () => setState(() {}),
    );
    // The embedded panel reattaches this shared node when the source changes.
    if (selected && widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _discSourceNode.requestFocus();
      });
    }
  }

  Widget _buildDiscoverPanel() => buildDiscoverPanels(
    selected: _discSource,
    isTelevision: widget.isTelevision,
    sourceNode: _discSourceNode,
    preferences: _metadataFeaturePolicy,
    mdblistEnabled: kMdblistEnabled,
    mdblistAuthenticated: _isMdblistAuthenticated,
    addons: _discAddons,
    onSelectSource: _selectDiscoverSource,
    pikpakOnly: _pikpakOnly,
    onItemFocused: _onDiscFocused,
    isBound: _isBound,
    findAddon: (id) => _addonsById[id],
    addonForContinue: _addonForContinue,
    onOpenCatalog: _openItem,
    onPlayCatalog: _onCatalogPlay,
    traktItems: _traktAll,
    traktProgress: () => _cwCardMaps(HomeContinuationKind.trakt).progress,
    onOpenTrakt: _openTraktItem,
    onPlayTrakt: _playTraktItem,
    simklItems: _simklAll,
    simklProgress: _simklProgress,
    onOpenSimkl: _openSimklItem,
    onPlaySimkl: _playSimklItem,
    onOpenSimklContinuation: _openSimklCwItem,
    onPlaySimklContinuation: _playSimklCwItem,
    mdblistList: _discMdblistList,
    localItems: _cwAll,
    localProgress: (m) => _cwCardProgress(HomeContinuationKind.local, m),
    onOpenLocal: _openContinueItem,
    onPlayLocal: _onContinuePlay,
    reloadLocal: () async {
      await _loadContinueWatching();
      if (!mounted) return const <StremioMeta>[];
      return List<StremioMeta>.of(_cwAll);
    },
  );

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
    final gen = _boardLoadGen;
    bool current() =>
        mounted &&
        gen == _boardLoadGen &&
        _profileSessionOwner == ProfileSessionMemory.captureOwner();
    final actionNode = moreCatalogs ? _catalogMoreNode : _catalogContinueNode;
    final ownedFocus = actionNode.hasFocus;
    final operation = _catalogContinuationController.start(
      moreCatalogs: moreCatalogs,
      boardLoading: _boardLoadingMore,
      rows: _sections,
      hasMoreCatalogs: () => _boardHasMore,
      isCurrent: current,
      loadMoreCatalogs: () async {
        await _loadMoreBoard();
      },
      resumeRow: (section) async {
        final i = _sections.indexOf(section);
        if (i >= 0) await _loadMoreRow(i, resume: true);
      },
    );
    if (operation == null) return;
    try {
      await operation;
    } finally {
      if (current() && ownedFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!current()) return;
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
    final busy =
        _catalogContinuing ||
        _boardLoadingMore ||
        pending.any((i) => _sections[i].loadingMore);
    return buildHomeBoardFrame(
      loading: _loading,
      hasError: _error != null,
      hasCatalogs: _sections.isNotEmpty,
      catalogsEmpty: _sections.every((s) => s.items.isEmpty),
      continuationVisible: _cwVisible,
      favoritesVisible: _anyFavVisible,
      hasPausedRows: pending.isNotEmpty,
      hasMoreCatalogs: hasMoreCatalogs,
      busy: busy,
      continueNode: _catalogContinueNode,
      moreNode: _catalogMoreNode,
      onRestoreFocus: _restoreCatalogContinuationFocus,
      onContinueRows: () => _continueHomeCatalogs(moreCatalogs: false),
      onMoreCatalogs: () => _continueHomeCatalogs(moreCatalogs: true),
      content: _buildBoardContent,
      message: _message,
    );
  }

  Widget _buildBoardContent() {
    if (!_loading &&
        !_spotlightEntryRevealed &&
        widget.isTelevision &&
        !widget.searchMode &&
        !widget.discoverMode &&
        _catalogQuery.isEmpty &&
        !_catalogSearching &&
        _homeStyleEffective == 'spotlight') {
      if (_spotlightHero.isEmpty &&
          (_boardRefreshing || _heroSourceResolving)) {
        return BrandLoadingStage(isTelevision: true);
      }
      // Reveal once: background refreshes must not hide an already usable
      // board. Hero success enters on the hero; exhaustion enters on a card.
      _spotlightEntryRevealed = true;
      _autoFocusSettled = false;
      _maybeAutoFocusBoard();
    }
    return buildHomeBoardContent(
      loading: _loading,
      isTelevision: widget.isTelevision,
      error: _error,
      continuationVisible: _cwVisible,
      catalogsEmpty: _sections.isEmpty,
      favoritesVisible: _anyFavVisible,
      traktReserving: _traktReserving,
      query: _catalogQuery,
      searchFailures: _catalogSearchFailures,
      searchMode: widget.searchMode,
      style: _homeStyleEffective,
      spotlightHasContent: () =>
          _spotlightShelves.any((s) => s.items.isNotEmpty),
      layouts: {
        'canvas': _buildCanvasBoard,
        'atrium': _buildAtriumBoard,
        'mosaic': _buildMosaicBoard,
        'promenade': _buildPromenadeBoard,
        'deck': _buildDeckBoard,
        'tonight': _buildTonightBoard,
        'spotlight': _buildSpotlightBoard,
      },
      searchSpotlight: _buildSearchSpotlightBoard,
      classic: _buildClassicBoard,
      onRetry: () => unawaited(_load()),
      message: _message,
    );
  }

  Widget _buildClassicBoard() {
    final tv = widget.isTelevision;
    return buildHomeClassicLayout(
      isTelevision: tv,
      viewportWidth: MediaQuery.of(context).size.width,
      tvHeroBudget: _tvHeroBudget,
      trailerActive: _heroTrailerActive,
      takeover: _heroTrailerTakeover,
      boardBuilder: (heroH) => Column(
        children: [
          // The hero spotlight only changes as DPAD focus moves across tiles, so
          // it's meaningful on TV only. On phones/desktop (no DPAD) it would just
          // sit frozen on the first item and waste vertical space — hide it.
          // On the dedicated Search tab it shows once there are results (to help
          // disambiguate similarly-named titles) but stays hidden on the blank
          // prompt. See [_heroActive].
          if (_heroActive)
            buildHomeClassicHero(
              focused: _heroItem,
              enriched: _heroEnriched,
              height: heroH,
              readConfiguration: () => (
                compact: widget.searchMode,
                isTelevision: tv,
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
                trailerActive: _heroTrailerActive,
              ),
              tint: _heroTint,
              trailerShowing: _heroTrailerShowing,
              liveTakeover: _heroLiveTakeover,
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
            child: buildHomeTrailerRowsDim(
              active: _heroTrailerActive,
              showing: _heroTrailerShowing,
              rows: Builder(
                builder: (context) {
                  // Home uses one globally ordered descriptor list across
                  // every row family. Catalog search results never read
                  // that Home order.
                  final orderedHome = _homeRowOrderActive;
                  final homeRails = orderedHome
                      ? _classicHomeRails
                      : const <HomeRail>[];
                  return HomeClassicRows(
                    scrollController: _boardScroll,
                    generation: _boardGen,
                    catalogRowCount: _sections.length,
                    orderedRowIds: orderedHome
                        ? homeRails.map(_canvasRailRowId).toList()
                        : null,
                    showFooter: _boardLoadingMore,
                    tailPadding: _classicAnchorTailPadding,
                    footerBuilder: (_) => _buildBoardFooter(),
                    isFresh: () =>
                        DateTime.now().difference(_boardAppliedAt) <
                        const Duration(milliseconds: 1800),
                    rowBuilder: (context, i) {
                      if (!orderedHome) return _buildRow(i);
                      final rail = homeRails[i];
                      final rowId = _canvasRailRowId(rail);
                      if (rail.traktSkeletonIndex >= 0) {
                        return _buildTraktSkeletonRow(rail.traktSkeletonIndex);
                      }
                      if (rail.cw != null) {
                        return _buildContinueWatchingRow(
                          rail.cw!,
                          rail.cwIndex,
                          rowId,
                        );
                      }
                      if (rail.favKind != null) {
                        return _buildFavRow(rail.favKind!, rowId);
                      }
                      return _buildRow(rail.sectionIndex!, homeRowId: rowId);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      trailerBuilder: (heroH) => HomeHeroTrailerLayer(
        trailer: _heroTrailer,
        isTelevision: widget.isTelevision,
        heroHeight: heroH,
        volume: _heroTrailerVolume,
        loading: _heroTrailerLoading,
        onPlayingChanged: _onHeroTrailerPlaying,
        takeover: _heroTrailerTakeover,
      ),
      liveBuilder: (heroH) => HomeHeroLiveLayer(
        isAddonChannel: StremioIptvService.isStremioChannelUrl,
        channel: _heroLiveChannel,
        streamUrl: _heroLiveUrl,
        heroHeight: heroH,
        volume: _heroTrailerVolume,
        onPlayingChanged: _onHeroTrailerPlaying,
        onPlaybackFailed: _onHeroLivePlaybackFailed,
      ),
      infoBuilder: () => buildHomeTakeoverInfo(
        context,
        heroItem: _heroItem,
        heroEnriched: _heroEnriched,
        heroTakeover: _heroTrailerTakeover,
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
    return section.addon.displayName;
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
    final settings = _discoverCardSettingsController.readSnapshot(
      isCurrent: () => mounted,
    );
    return DiscoverCardSettingsScope(
      showTypeTags: settings.showTypeTags,
      showRatings: settings.showRatings,
      showTitles: settings.showTitles,
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
        cwProgress: _cwCardMaps(HomeContinuationKind.trakt).progress,
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
  void _markPlaybackStarted() =>
      _postPlaybackRefreshController.markPlaybackStarted();

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
  Future<void> _refreshAfterPlayback({bool trackers = false}) =>
      _postPlaybackRefreshController.refresh(
        searchMode: widget.searchMode,
        trackers: trackers,
        isCurrent: () => mounted,
        clearResume: _clearSeriesResume,
        watchlist: _loadMyWatchlist,
        local: _loadContinueWatching,
        iptv: _loadIptvContinueWatching,
        trakt: () => _loadTraktContinueWatching(refreshBound: false),
        simkl: () => _loadSimklContinueWatching(refreshBound: false),
        shouldRefreshMdblist: () => _mdblistContinuationController
            .shouldRefreshAfterPlayback(DateTime.now()),
        mdblist: () =>
            _loadMdblistContinueWatching(refreshBound: false, force: true),
        boundSources: _refreshBoundSources,
        onError: (error) =>
            debugPrint('SearchScreen: post-playback refresh failed: $error'),
      );

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
      progressOf: (m) => _cwCardProgress(HomeContinuationKind.local, m),
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
                cwProgress: _cwCardMaps(HomeContinuationKind.trakt).progress,
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

  double _classicCatalogRowExtent(
    BuildContext context, {
    CatalogSection? section,
  }) => measureHomeClassicRowExtent(
    context,
    hideHeader: _hideHomeCollectionNames && section is HomeCollectionSection,
    hideSourceTags: _hideHomeCatalogAddonNames,
    titleStyle: () => homeCatalogRowTitleStyle(this.context, fontSize: 15),
    cardHeight: () => _railTitleCardH(context),
  );

  Widget _railHeader({
    required String title,
    String? tag,
    VoidCallback? onSeeAll,
  }) => buildHomeCatalogRowHeader(
    context,
    isTelevision: widget.isTelevision,
    title: title,
    tag: tag,
    onSeeAll: onSeeAll,
  );

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
    // Rows start straight on the first poster (Stremio-style, no
    // leading See-All tile). DPAD-up from row 0 leaves the board;
    // col-0 DPAD-left drops to the sidebar (handled in HomeBoardCell
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
    return buildHomeCatalogRow(
      header: collection == null || !_hideHomeCollectionNames
          ? _railHeader(
              title: section.title,
              tag: _catalogSourceTag(section),
              onSeeAll: () => _openCatalogSeeAll(section),
            )
          : const SizedBox(height: 8),
      cellHeight: cellH,
      readChildCount: () =>
          section.items.length + (section.loadingMore ? 1 : 0),
      onLoadMore: () => _loadMoreRow(rowIndex),
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
        final itemAspect = collection?.tileAspectOf(item) ?? cellAspect;
        // Unique per cell AND per SearchScreen instance (Home,
        // Discover and Search coexist in the tab stack — a shared
        // tag across them would trip Hero's duplicate-tag assert).
        final heroTag = 'poster-${identityHashCode(this)}-$rowIndex-$col';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Center(
            child: SizedBox(
              width: collection == null ? posterW : cellH * itemAspect,
              height: cellH,
              child: HomeBoardCell(
                onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
                item: item,
                isTelevision: tv,
                focusNode: nodes[col],
                column: col,
                rowNodes: nodes,
                hasBoundSource: _isBound(item),
                aspectRatio: itemAspect,
                artUrl: collection != null ? item.poster : _titleArtUrl(item),
                focusArtUrl: collection?.focusArtOf(item),
                focusVideoUrl: collection?.focusVideoOf(item),
                focusGlowEnabled:
                    collection?.collection.focusGlowEnabled ?? false,
                showTitleOverlay: collection != null
                    ? !(collection.folderOf(item)?.hideTitle ?? false)
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
                onOpen: () => _sectionOpenItem(section, item, heroTag: heroTag),
                onNearEnd: () => _loadMoreRow(rowIndex),
                heroTag: heroTag,
              ),
            ),
          ),
        );
      },
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

  Widget _buildContinueWatchingRow(
    HomeContinuationRow row,
    int cwIndex,
    String homeRowId,
  ) => buildHomeContinuationRow(
    row: row,
    header: _railHeader(title: row.title, tag: row.tag, onSeeAll: row.onSeeAll),
    isTelevision: widget.isTelevision,
    posterWidth: _railTitleCardW(context),
    cellHeight: _railTitleCardH(context),
    aspectRatio: () => _titleCardAspect,
    showTitleOverlay: () => !_hideHomeCardTitlesAndRatings,
    artOf: _titleArtUrl,
    isBound: _isBound,
    onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
    onFocused: _setHero,
    onMenu: (item, col) => _openCwCardMenu(row, item, cwIndex, col),
    onUp: (col) => _focusRelativeHomeRail(homeRowId, -1, col),
    onDown: (col) => _focusRelativeHomeRail(homeRowId, 1, col),
  );

  /// A skeleton Trakt Continue Watching row shown while the account's fetch is
  /// still in flight (see [_traktReserving]). Sized identically to a real CW row
  /// — same header, poster width and cell height — so when the data arrives and
  /// replaces it there's zero layout shift. Purely decorative: no focus nodes,
  /// so the DPAD skips over it entirely. [idx] is 0 (Movies) or 1 (Shows).
  Widget _buildTraktSkeletonRow(int idx) {
    final posterW = _railTitleCardW(context);
    final cellH = _railTitleCardH(context);
    final rowH = cellH + 14;
    return HomeTraktSkeletonRow(
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
  Widget _buildFavRow(HomeFavoriteRowRef ref, String homeRowId) {
    if (ref.isIptvList) {
      return _buildIptvListRow(ref, homeRowId);
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        return _buildWatchlistRow(ref, homeRowId);
      case HomeFavoriteKind.iptv:
        return _buildIptvFavRow(homeRowId);
      case HomeFavoriteKind.debrify:
        return _buildTvFavRow(homeRowId);
      case HomeFavoriteKind.stremio:
        return _buildStremioTvFavRow(homeRowId);
      case HomeFavoriteKind.playlist:
        return _buildPlaylistFavRow(homeRowId);
    }
  }

  Widget _buildWatchlistRow(HomeFavoriteRowRef ref, String homeRowId) {
    final tv = widget.isTelevision;
    final isMovies = ref.kind == HomeFavoriteKind.watchlistMovies;
    final items = isMovies ? _watchlistMovieItems : _watchlistSeriesItems;
    final nodes = isMovies ? _watchlistMovieNodes : _watchlistSeriesNodes;
    return _buildFavRowShell(
      title: isMovies ? 'Watchlist Movies' : 'Watchlist Series',
      tags: [
        CategoryTag(
          isMovies ? 'Movies' : 'Series',
          icon: Icons.bookmark_rounded,
        ),
      ],
      itemCount: items.length,
      cellBuilder: (col, posterW, cellH) {
        final item = items[col];
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: tv,
          column: col,
          rowNodes: nodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: HomeArtPoster(
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

  Widget _buildFavRowShell({
    required String title,
    required List<Widget> tags,
    required int itemCount,
    required Widget Function(int col, double posterW, double cellH) cellBuilder,
  }) => buildHomeFavoriteRow(
    context,
    isTelevision: widget.isTelevision,
    posterWidth: _railPosterW(context),
    captionBand: _homeArtPosterCaptionBand,
    title: title,
    tags: tags,
    itemCount: itemCount,
    cellBuilder: cellBuilder,
  );

  /// The "Debrify TV" row of favourited keyword channels, styled to match the
  /// catalog rows (same poster-shaped cards + title below).
  Widget _buildTvFavRow(String homeRowId) {
    final tv = widget.isTelevision;
    return _buildFavRowShell(
      title: 'Debrify TV',
      tags: const [
        CategoryTag('Channels'),
        // Make it explicit this row is the user's STARRED channels, not every
        // channel — otherwise people expect all channels here.
        CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _tvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _tvFavChannels[col];
        final number = channel.channelNumber > 0
            ? channel.channelNumber
            : col + 1;
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: tv,
          column: col,
          rowNodes: _tvFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          // Debrify channels have no artwork — the glyph fallback + channel
          // number badge is the intended look.
          child: HomeArtPoster(
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
        CategoryTag('Channels'),
        CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _stvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _stvFavChannels[col];
        final item = _stvNowPlaying(channel)?.item;
        // Prefer the 2:3 poster for this poster-shaped tile; fall back to the
        // (landscape) background so channels whose now-playing meta lacks a
        // poster still show art instead of a blank glyph.
        final art = _firstNonEmpty(item?.poster, item?.background);
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: tv,
          column: col,
          rowNodes: _stvFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: HomeArtPoster(
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
        CategoryTag('Live'),
        CategoryTag('Favorites', icon: Icons.star_rounded),
      ],
      itemCount: _iptvFavChannels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = _iptvFavChannels[col];
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: tv,
          column: col,
          rowNodes: _iptvFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: HomeArtPoster(
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
  Widget _buildIptvListRow(HomeFavoriteRowRef ref, String homeRowId) {
    final tv = widget.isTelevision;
    final row = _iptvListRows[ref.list];
    final nodes = _iptvListFocus.nodesFor(row.listId);
    return _buildFavRowShell(
      title: row.title,
      tags: const [
        CategoryTag('IPTV'),
        CategoryTag('List', icon: Icons.playlist_play_rounded),
      ],
      itemCount: row.channels.length,
      cellBuilder: (col, posterW, cellH) {
        final channel = row.channels[col];
        final live = channel.isLive;
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: tv,
          column: col,
          rowNodes: nodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: HomeArtPoster(
            imageUrl: channel.logoUrl,
            title: channel.name,
            showTitle: !_hideHomeCardTitlesAndRatings,
            // Logos are usually square/wide, not 2:3 — contain so they aren't
            // cropped; the gradient shows around them.
            imageFit: BoxFit.contain,
            isTelevision: tv,
            focusNode: nodes[col],
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
      tags: const [CategoryTag('Saved')],
      itemCount: _playlistItems.length,
      cellBuilder: (col, posterW, cellH) {
        final item = _playlistItems[col];
        final posterUrl = item.posterUrl;
        final title = item.title;
        return HomeFavoriteCell(
          onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
          isTelevision: tv,
          column: col,
          rowNodes: _playlistFavNodes,
          onUp: _favRowOnUp(homeRowId, col),
          onDown: _favRowOnDown(homeRowId, col),
          child: HomeArtPoster(
            imageUrl: posterUrl,
            title: title,
            showTitle: !_hideHomeCardTitlesAndRatings,
            progress: _playlistController.current.progressFor(item),
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
  }) => buildRetryMessage(
    context,
    icon,
    title,
    body,
    isTelevision: widget.isTelevision,
    onRetry: onRetry,
  );



}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
