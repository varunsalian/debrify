import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/home/models/home_board_configuration.dart';
import '../features/home/models/home_catalog_preferences.dart';
import '../models/stremio_addon.dart';
import '../services/hide_watched_prefs.dart';
import '../services/home_collections_store.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/tmdb_title_search.dart';
import 'search_screen/search_screen_composer.dart';

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
class SearchScreen extends ConsumerStatefulWidget
    implements SearchScreenConfig {
  @override
  final bool isTelevision;

  /// Dedicated-search-tab mode (TV only). When true the screen is *only* the
  /// search field + Catalog/Keyword/Lists selector over a blank prompt until
  /// the user types — no hero/board. When false it's the "Home New" board
  /// (chrome-free on TV; persistent search bar on desktop/mobile).
  @override
  final bool searchMode;

  /// Discover-tab mode. A single browsable grid with a "Source" dropdown
  /// (Continue Watching / Trakt / …) instead of the board's stacked rails —
  /// reuses this screen's item-open/play handlers and cached CW/Trakt rows.
  @override
  final bool discoverMode;

  @override
  @visibleForTesting
  final TmdbTitleSearch? titleSearch;

  @override
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

class _SearchScreenState extends ConsumerState<SearchScreen>
    with RouteAware, WidgetsBindingObserver {
  // Captured when the State is constructed, as before the composition moved.
  final _titleSearchScope = ProfileRuntime.scope.value;

  // Rows the user hid via Settings → Home Page → Home Rows. Bootstrap is
  // captured at state construction; accepted changes live in the controller.
  final _initialHomeConfiguration = HomeBoardConfiguration(
    preferences: const HomeCatalogPreferences.empty(),
    collections: const [],
    collectionsSignature: HomeCollectionsStore.signatureOf(const []),
    hideWatched: HideWatchedPrefs.enabled,
  );

  late final SearchScreenComposer _composer;

  @override
  void initState() {
    super.initState();
    _composer = SearchScreenComposer(
      (
        widget: () => widget,
        ref: ref,
        mounted: () => mounted,
        context: () => context,
        setState: setState,
        observer: this,
        routeAware: this,
        identity: identityHashCode(this),
      ),
      titleSearchScope: _titleSearchScope,
      initialHomeConfiguration: _initialHomeConfiguration,
    );
    _composer.initialize();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
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
    _composer.didChangeDependencies();
  }

  @override
  void didPushNext() => _composer.didPushNext();

  @override
  void didPopNext() => _composer.didPopNext();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _composer.didChangeAppLifecycleState(state);

  @override
  Widget build(BuildContext context) => _composer.build(context);
}
