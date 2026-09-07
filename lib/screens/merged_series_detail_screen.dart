import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_util.dart';
import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/analytics_service.dart';
import '../services/series_source_service.dart';
import '../services/app_route_observer.dart';
import '../services/imdb_enrichment_service.dart';
import '../services/imdb_parents_guide_service.dart';
import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';
import '../widgets/detail/detail_episode_cells.dart';
import '../widgets/detail/detail_layout_console.dart';
import '../widgets/detail/detail_layout_dossier.dart';
import '../widgets/detail/detail_layout_marquee.dart';
import '../widgets/detail/detail_layout_premium.dart';
import '../widgets/detail/detail_layout_showcase.dart';
import '../widgets/detail/detail_layout_stage.dart';
import '../widgets/detail/detail_action_buttons.dart';
import '../widgets/detail/detail_focus_chrome.dart';
import '../widgets/detail/detail_primary_sources.dart';
import '../widgets/detail/detail_rail_cards.dart';
import '../widgets/detail/detail_style.dart';
import '../widgets/detail/detail_model.dart';
import '../theme/app_theme_scope.dart';
import '../theme/artwork_accent.dart';
import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/hero_trailer_backdrop.dart';
import '../widgets/episodes_panel.dart';
import '../widgets/horizontal_mouse_wheel.dart';
import '../widgets/parents_guide_section.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/trakt/trakt_service.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import '../services/simkl/simkl_service.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../services/mdblist/mdblist_models.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../widgets/tracker_brand_marks.dart';
import 'merged_detail/detail_tracker_controller.dart';
import 'merged_detail/detail_trailer_controller.dart';
import 'episodes_screen.dart' show kCatalogDetailRouteName;
import 'settings/detail_page_style_page.dart' show effectiveDetailPageStyle;
import '../theme/app_theme_controller.dart';
import '../theme/theme_core_resolver.dart';
import '../theme/theme_overrides.dart';
import '../theme/shipped_themes.dart' show effectiveDetailTheme;
import '../utils/artwork_url.dart';
import '../utils/episode_progress_merge.dart';

/// Merged series page (experimental, flag-gated): the detail screen and the
/// episode drill-down fused into one Stremio-styled screen. Reached only from
/// the Search tab, only for series, only when
/// `StorageService.getMergedSeriesPageEnabled()` is on. Movies and the flag-off
/// path keep the existing `CatalogItemDetailScreen` → `EpisodesScreen` flow.
///
/// The episode list + playback selection is delegated to [EpisodesPanel] (the
/// proven engine, hosted chromeless), so no playback behavior is re-implemented
/// here. This screen owns only presentation + the same detail-metadata loads
/// the detail screen performs (IMDb enrichment, parents guide, recommendations).
class MergedDetailScreen extends StatefulWidget {
  final StremioMeta item;
  final StremioAddon addon;
  final bool isTelevision;
  final bool showQuickPlay;
  final bool isTraktSource;
  final bool isMdblistSource;

  /// Primary play action. Series: resume-and-play (last-played → S01E01).
  /// Movie: play the movie. Mirrors the detail screen's "Play".
  ///
  /// Receives the episode the BUTTON is currently promising, when this screen
  /// has resolved one. The host must honor it over its own re-derivation: this
  /// screen's episode engine advances off watched state, while the host's
  /// reconciler only reads resume positions, so the two legitimately disagree
  /// (a show whose progress lives in a tracker's watched list rather than its
  /// continue-watching list resolves here to S1E2 and there to the S1E1
  /// empty-candidates fallback). Null means this screen has nothing better than
  /// what the host can work out for itself.
  final Future<void> Function(({bool started, int season, int episode})? promised)
  onResume;

  /// Resolves whether the title has prior progress and, for a series, the
  /// season/episode [onResume] would land on — so the button can read
  /// "Start Watching" vs "Resume · S3E4". Null keeps the static label.
  final Future<({bool started, int? season, int? episode})> Function()?
  resumeInfoLoader;

  /// Movie only: open the Sources list (manual pick). Ignored for series (the
  /// episode list is the picker). When null the Sources button is hidden.
  final VoidCallback? onBrowse;

  /// Episode terminal callbacks — the exact ones the Search tab passes to
  /// `EpisodesScreen` today (`_playSelection` / `_browseSelection`).
  final void Function(AdvancedSearchSelection selection)? onItemSelected;
  final Future<void> Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Opens manual sources for the episode represented by the primary button.
  /// The optional promise has the same contract as [onResume], keeping a
  /// watched-frontier target from drifting back to the host's older resolver.
  final Future<void> Function(
    ({bool started, int season, int episode})? promised,
  )?
  onBrowsePrimaryEpisodeSources;

  /// Host-owned source binding.
  final int Function(StremioMeta show)? boundSourceCount;
  final Future<void> Function(StremioMeta show)? onSelectSource;

  /// Quick-action strip (Trakt / app actions). [traktMenuOptions] is the
  /// initial (status-unknown) set shown until [traktStatusLoader] resolves;
  /// [traktMenuBuilder], when provided, rebuilds the strip against the live
  /// Trakt status so Add ↔ Remove toggles reflect the user's real library.
  final List<TraktMenuOption> traktMenuOptions;
  final List<TraktMenuOption> Function(TraktTitleStatus? status)?
  traktMenuBuilder;
  final Future<void> Function(TraktItemMenuAction action)? onTraktAction;

  /// Resolves the user's Trakt relationship to this title (in watchlist /
  /// collection / watched / rating) so the page can badge it and offer the
  /// right toggles. Null (disconnected / no IMDb id) keeps the add-only menu.
  final Future<TraktTitleStatus?> Function()? traktStatusLoader;

  /// Simkl equivalents — render as their own independent quick-actions
  /// button/sheet/status chips next to Trakt's, not merged (both trackers
  /// run in parallel; see the Simkl integration plan).
  final List<SimklMenuOption> simklMenuOptions;
  final List<SimklMenuOption> Function(SimklTitleStatus? status)?
  simklMenuBuilder;
  final Future<void> Function(SimklItemMenuAction action)? onSimklAction;
  final Future<SimklTitleStatus?> Function()? simklStatusLoader;
  final List<MdblistMenuOption> mdblistMenuOptions;
  final List<MdblistMenuOption> Function(MdblistTitleStatus? status)?
  mdblistMenuBuilder;
  final Future<void> Function(MdblistItemMenuAction action)? onMdblistAction;
  final Future<MdblistTitleStatus?> Function()? mdblistStatusLoader;

  /// Submits a 1–10 rating straight from the tracker sheet's inline strip.
  /// When null the strip falls back to firing the sheet's `rate` action, which
  /// opens that tracker's rating dialog instead.
  final Future<void> Function(int rating)? onTraktRate;
  final Future<void> Function(int rating)? onSimklRate;
  final Future<void> Function(int rating)? onMdblistRate;

  /// "More Like This" rail + sparse-item meta backfill (same loaders the detail
  /// screen receives).
  final Future<List<StremioMeta>> Function()? recommendationsLoader;
  final void Function(StremioMeta recommendation)? onRecommendationTap;
  final Future<StremioMeta?> Function(String imdbId, String type)? metaEnricher;

  /// Shared-element tag from the board cell that opened this page: the tapped
  /// poster flies into (and back out of) this page's full-bleed backdrop.
  final String? heroTag;

  /// For a series opened at a specific episode (e.g. from the Trakt Calendar):
  /// the episodes panel lands on and scrolls to this season/episode instead of
  /// its usual next-up/last-played target. Ignored for movies.
  final int? initialSeason;
  final int? initialEpisode;

  /// Direct-source mode (Xtream IPTV series) — forwarded verbatim to
  /// [EpisodesPanel]. See its fields of the same names: [seasonsLoader] is the
  /// sole episode source, [onPlayEpisode] plays a URL-backed episode on top of
  /// this page, [watchProgressLoader] replaces the IMDb-keyed progress merge.
  final Future<List<TraktSeason>> Function()? seasonsLoader;
  final Future<void> Function(TraktEpisode episode)? onPlayEpisode;
  final Future<Map<String, double>> Function()? watchProgressLoader;

  const MergedDetailScreen({
    super.key,
    required this.item,
    required this.addon,
    required this.onResume,
    this.initialSeason,
    this.initialEpisode,
    this.resumeInfoLoader,
    this.onBrowse,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.isTraktSource = false,
    this.isMdblistSource = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.onBrowsePrimaryEpisodeSources,
    this.boundSourceCount,
    this.onSelectSource,
    this.traktMenuOptions = const [],
    this.traktMenuBuilder,
    this.onTraktAction,
    this.traktStatusLoader,
    this.simklMenuOptions = const [],
    this.simklMenuBuilder,
    this.onSimklAction,
    this.simklStatusLoader,
    this.mdblistMenuOptions = const [],
    this.mdblistMenuBuilder,
    this.onMdblistAction,
    this.mdblistStatusLoader,
    this.onTraktRate,
    this.onSimklRate,
    this.onMdblistRate,
    this.recommendationsLoader,
    this.onRecommendationTap,
    this.metaEnricher,
    this.heroTag,
    this.seasonsLoader,
    this.onPlayEpisode,
    this.watchProgressLoader,
  });

  @override
  State<MergedDetailScreen> createState() => _MergedDetailScreenState();
}

class _MergedDetailScreenState extends State<MergedDetailScreen>
    with RouteAware {
  // ── Stremio-flat palette (neutral glass + gold state) ──
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _gold = kDetailGold;
  static const Color _imdb = Color(0xFFF5C518);
  static Color get _glass2 => Colors.white.withValues(alpha: 0.07);
  static Color get _hair => Colors.white.withValues(alpha: 0.09);

  /// Per-title accent, extracted once from the poster (same cheap 32px decode
  /// the home hero uses). Colors the eyebrow, an ambient wash behind the title
  /// and the Play button's glow, so the page feels made for *this* title rather
  /// than a template with the artwork swapped in. Falls back to [_gold] until a
  /// colorful dominant color is found (or forever, for a B&W poster).
  Color _accent = _gold;

  ImdbEnrichment? _imdbExtra;
  ParentsGuideResult? _parentsGuide;
  List<StremioMeta>? _recommendations;
  StremioMeta? _enriched;

  /// The trailer lifecycle: Cinemeta id resolution, the OTT ambient-autoplay
  /// pipeline behind the backdrop, fullscreen promotion and the standalone
  /// fallback launch.
  late final DetailTrailerController _trailer = DetailTrailerController(
    read: () => DetailTrailerInputs(
      routeItem: widget.item,
      item: _item,
      isTelevision: widget.isTelevision,
      leftEntryFocusNode: _leftEntryFocusNode,
      metaEnricher: widget.metaEnricher,
    ),
  );

  /// One playback launch at a time for the whole merged page. Every visual
  /// theme delegates its primary action here, and the hosted episode panel is
  /// wrapped by the same gate below. The modal resolving route usually absorbs
  /// a second tap, but it is presentation rather than synchronization: two OK
  /// events can otherwise enter the async resume/source resolution together.
  bool _playLaunching = false;

  /// Scrolls the left info column. Focus-anchored (see [DetailScrollAnchor]) so that
  /// focusing the top action row snaps to the very top (revealing the
  /// title/meta/summary above it), and focusing a lower section brings it fully
  /// into view — fixing the "can't scroll back up to the details" DPAD bug.
  final ScrollController _infoScroll = ScrollController();
  final ScrollController _castRailScroll = ScrollController();
  final ScrollController _recommendationRailScroll = ScrollController();

  /// The stable LEFT-crossing target for episodes: the info column's primary
  /// action (Play/Resume, or the source pill when Play is hidden). Pressing LEFT
  /// on an episode focuses this instead of a geometry-picked mid-column item.
  final FocusNode _leftEntryFocusNode = FocusNode(
    debugLabel: 'merged-left-entry',
  );

  /// Pane containment (two-pane layout). Each pane lives in its own
  /// [FocusScope]: directional traversal only considers candidates inside the
  /// focused node's nearest scope, so Up/Down can never geometry-jump across
  /// the pane border (DOWN on the last episode used to land on a cast tile in
  /// the info column). Crossing is explicit and horizontal only: LEFT from the
  /// episodes pane → [_leftEntryFocusNode]; RIGHT from the info pane →
  /// [_focusEpisodesPane] (the pane's last-focused row, remembered by its
  /// scope).
  final FocusScopeNode _infoPaneScope = FocusScopeNode(
    debugLabel: 'merged-info-pane',
  );
  final FocusScopeNode _episodesPaneScope = FocusScopeNode(
    debugLabel: 'merged-episodes-pane',
  );

  /// The floating back button — the info pane hands focus here when UP is
  /// pressed at its top (it sits outside the pane scopes, so contained
  /// traversal alone could never reach it).
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'merged-back');

  /// Reaches the hosted panel so [didPopNext] can refresh its watched
  /// ticks/progress after inline playback (episode quick-play, hero Resume)
  /// pops back onto this screen. Single key is safe: only one layout (two-pane
  /// or stacked) builds the panel at a time.
  final GlobalKey<EpisodesPanelState> _episodesPanelKey =
      GlobalKey<EpisodesPanelState>();

  /// Which body to draw. Read SYNCHRONOUSLY from the warmed cache so the first
  /// build already has it — an async read would paint Classic for a frame and
  /// then re-lay-out the whole page.
  ///
  /// Direct-source mode (Xtream IPTV series) always gets Classic: that path has
  /// its own contract (URL-backed episodes, a different progress loader,
  /// playback on top of this page) and a single caller, so supporting six
  /// arrangements there would risk a shipped feature for nothing.
  late final String _style = widget.seasonsLoader != null
      ? 'classic'
      : effectiveDetailPageStyle(StorageService.detailPageStyleCached);

  /// The look the alternate layouts are drawn in. Read synchronously from the
  /// warmed cache for the same reason as [_style] — the page resolves both in
  /// its first build, and an async read would repaint the whole thing.
  ///
  /// A GETTER, not a `late final`: selecting an app theme write-through
  /// mirrors into `detail_theme`, and a State-lifetime capture would leave an
  /// already-open details route on the stale look until reopened. Resolving
  /// per read keeps it a 20-entry const lookup — free — and an open route now
  /// restyles on its next rebuild. (Foundation item 2 of the theme rollout;
  /// the full `(app_theme, detail_theme, style)` resolution is step 5.)
  ///
  /// Classic is deliberately unthemed, so this is only consulted by the
  /// alternate bodies.
  ///
  /// Through [ThemeCoreResolver], not the registry directly: the user's token
  /// overrides are applied there, and a page that fetched its own core would be
  /// the one surface in the app still showing the unedited theme.
  DetailTheme get _theme => ThemeCoreResolver.resolve(
    effectiveDetailTheme(StorageService.detailThemeCached),
    // Classic is deliberately unthemed, and the controller's own fast path says
    // so. Applying overrides here anyway would make this the one surface that
    // disagreed with it.
    AppThemeController.instance.isLegacy
        ? ThemeOverrides.none
        : AppThemeController.instance.overrides,
  );

  /// Filmstrip pushes the focused episode's still here. Painted by the shell as
  /// an ambient layer — never as [HeroTrailerBackdrop.imageUrl], which stays
  /// the title art the route Hero flies back into on pop.
  String? _focusedStillUrl;

  /// The Showcase body has descended past its hero.
  ///
  /// Showcase wants the reference's two grounds: sharp key art while the
  /// identity owns the screen, a blurred field once you walk down into the
  /// bands. Both have to be painted HERE, because this backdrop is the only
  /// layer outside the overscan `SafeArea` — art painted inside the body would
  /// stop short of the screen edges and the two states would not line up.
  bool _bodyDeep = false;

  /// Whether this page should show sharp key art at rest at all. Showcase is
  /// the tvOS idiom and the only layout designed around real artwork; every
  /// other layout was drawn against the blurred wash and would lose its text
  /// legibility over a sharp one.
  bool get _wantsSharpStill => _style == 'showcase' && !_bodyDeep;

  /// The two focus anchors the shell owns, handed to whichever body draws.
  late final DetailFocusCoordinator _focusCoordinator = DetailFocusCoordinator(
    backNode: _backButtonFocusNode,
    primaryEntry: _leftEntryFocusNode,
  );

  StremioMeta get _item => _enriched ?? widget.item;

  /// Primary-button resume state. Until loaded the button keeps its static
  /// label; once resolved it reads "Start Watching" (no progress) or "Resume"
  /// (+ an "S3E4" tag for series). Re-read when the player pops back.
  bool _resumeLoaded = false;
  bool _resumeStarted = false;
  int? _resumeSeason;
  int? _resumeEpisode;
  bool _hasMergedEpisodeTarget = false;

  /// A resume lookup is in flight and no answer has landed yet (from the
  /// loader OR the mounted episode engine). The primary button shows a
  /// spinner instead of a label so it never flashes "Start Watching" before
  /// flipping to "Resume · S1E7". Errors clear it (static label fallback).
  bool _resumePending = false;
  bool get _primaryBusy => _resumePending && !_resumeLoaded;

  /// Engine emission received BEFORE the loader settled the pill — held back
  /// so the label can't strobe through intermediate merge states; consumed
  /// (or discarded) by [_loadResumeInfo]'s settle arbitration.
  EpisodeResumeTarget? _pendingEngineTarget;

  /// The loader is genuinely running right now. Engine emissions stash ONLY
  /// during this window — inferring it from _resumeLoaded left two holes: a
  /// FAILED loader stranded later emissions in the stash forever, and a
  /// not-started settle discarded a later started target (order-dependent
  /// "merged progress beats Start Watching").
  bool _resumeLoaderInFlight = false;

  /// The tracker-status engine: the live Trakt / Simkl / MDBList relationships
  /// to this title, the pill labels compressed out of them, the app-vs-tracker
  /// split of the one incoming Trakt option list, and the sheets that change
  /// any of it.
  late final DetailTrackerController _tracker = DetailTrackerController(
    read: () => DetailTrackerInputs(
      title: _item.name,
      isTelevision: widget.isTelevision,
      traktMenuOptions: widget.traktMenuOptions,
      traktMenuBuilder: widget.traktMenuBuilder,
      onTraktAction: widget.onTraktAction,
      traktStatusLoader: widget.traktStatusLoader,
      onTraktRate: widget.onTraktRate,
      simklMenuOptions: widget.simklMenuOptions,
      simklMenuBuilder: widget.simklMenuBuilder,
      onSimklAction: widget.onSimklAction,
      simklStatusLoader: widget.simklStatusLoader,
      onSimklRate: widget.onSimklRate,
      mdblistMenuOptions: widget.mdblistMenuOptions,
      mdblistMenuBuilder: widget.mdblistMenuBuilder,
      onMdblistAction: widget.onMdblistAction,
      mdblistStatusLoader: widget.mdblistStatusLoader,
    ),
  );

  bool _localMovieFinished = false;
  bool _showcaseOpeningDataReady = false;

  /// Debrify's local watchlist is independent of tracker connectivity.
  bool _inMyWatchlist = false;
  bool get _supportsMyWatchlist =>
      MyWatchlistStore.supportsMyWatchlistItem(_item);
  StremioMeta get _myWatchlistItem => MyWatchlistStore.withMyWatchlistSource(
    _item,
    widget.item.sourceAddon ?? widget.addon,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('series_detail');
    MainPageBridge.addPlaybackReturnListener(_onPlaybackReturned);
    // Both controllers stand in for the setState calls their state used to
    // make: one listener each, and the page rebuilds exactly as before.
    _tracker.addListener(_onControllerChanged);
    _trailer.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadShowcaseOpeningData();
      _trailer.load(context);
      _loadAccent();
      _loadResumeInfo();
      _tracker.loadAll();
      _loadLocalMovieFinished();
      _loadMyWatchlistState();
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _guardPlay(Future<void> Function() launch) async {
    if (_playLaunching || !mounted) return;
    // Rebuild immediately so HeroTrailerBackdrop disables and tears down its
    // engine at the button press. The resolving loader is a RawDialogRoute,
    // which the app's PageRoute observer deliberately does not see; waiting
    // for the eventual player-handoff signal lets the delayed trailer start
    // (or keep playing) behind source resolution.
    setState(() => _playLaunching = true);
    try {
      await launch();
    } finally {
      if (mounted) {
        // A cancelled/failed resolve may resume autoplay after its normal
        // delay. A successful launch remains off because the backdrop's
        // content-player signal has independently latched _canPlay false.
        setState(() => _playLaunching = false);
      } else {
        _playLaunching = false;
      }
    }
  }

  /// The engine-only episode promise shared by primary Play and primary hold.
  /// See [_playPrimary] for why loader-derived coordinates are intentionally
  /// left for the host to resolve again.
  ({bool started, int season, int episode})? get _primaryEpisodePromise {
    // Promise ONLY an engine-derived target ([_hasMergedEpisodeTarget]), and
    // only a started one.
    //
    // The engine is the sole reason the label can disagree with the host: it
    // advances off watched state, which the host's reconciler never reads. A
    // label that came from the loader instead already equals what the host
    // would work out for itself, so promising it buys nothing — and costs
    // freshness, because these coordinates are only re-read at page open and on
    // return from playback. Promising a loader echo would let a page left open
    // while an episode was finished elsewhere override a fresher reconcile with
    // the episode the user already watched.
    //
    // This also covers the post-playback window for free:
    // [_refreshAfterPlayback] clears the flag before re-reading, so a press
    // during the refresh promises nothing and the host decides — without having
    // to block the button, which stays pressable throughout. An untouched show
    // resolves to S01E01 with no evidence behind it, hence the started gate.
    final season = _resumeSeason;
    final episode = _resumeEpisode;
    return (!_isMovie &&
            _resumeStarted &&
            _hasMergedEpisodeTarget &&
            season != null &&
            episode != null)
        ? (started: true, season: season, episode: episode)
        : null;
  }

  void _playPrimary() {
    final promised = _primaryEpisodePromise;
    debugPrint(
      '[SeriesResume] detail-primary-pressed title="${_item.name}" '
      'label="$_primaryLabel" loaded=$_resumeLoaded started=$_resumeStarted '
      'labelTarget=S${_resumeSeason}E$_resumeEpisode '
      'routeTarget=S${widget.initialSeason}E${widget.initialEpisode} '
      'mergedEngineTarget=$_hasMergedEpisodeTarget '
      'loaderInFlight=$_resumeLoaderInFlight '
      'promised=${promised == null ? 'none' : 'S${promised.season}E${promised.episode}'}',
    );
    unawaited(_guardPlay(() => widget.onResume(promised)));
  }

  void _browsePrimarySources() {
    unawaited(_browsePrimarySourcesAsync());
  }

  Future<void> _browsePrimarySourcesAsync() async {
    if (_isMovie) {
      widget.onBrowse?.call();
      return;
    }

    final openEpisode = widget.onBrowsePrimaryEpisodeSources;
    if (openEpisode == null) return;

    final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    if (!mounted) return;

    final canBrowsePacks =
        widget.onTraktAction != null &&
        _tracker.appMenuOptions.any(
          (option) => option.action == TraktItemMenuAction.searchPacks,
        );
    if (!rules.preferSeriesPacks || !canBrowsePacks) {
      await openEpisode(_primaryEpisodePromise);
      return;
    }

    final season = _resumeSeason;
    final episode = _resumeEpisode;
    final choice = await showDetailPrimarySourcesSheet(
      context,
      title: _item.name,
      isTelevision: widget.isTelevision,
      episodeLabel: season == null || episode == null
          ? null
          : 'S${season}E$episode',
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case DetailPrimarySourceChoice.seasonPacks:
        await widget.onTraktAction?.call(TraktItemMenuAction.searchPacks);
        return;
      case DetailPrimarySourceChoice.episode:
        await openEpisode(_primaryEpisodePromise);
        return;
    }
  }

  void _quickPlayEpisode(AdvancedSearchSelection selection) {
    final play = widget.onQuickPlay;
    if (play == null) return;
    unawaited(_guardPlay(() => play(selection)));
  }

  void _playDirectEpisode(TraktEpisode episode) {
    final play = widget.onPlayEpisode;
    if (play == null) return;
    unawaited(_guardPlay(() => play(episode)));
  }

  Future<void> _loadShowcaseOpeningData() async {
    try {
      await Future.wait<void>([
        _loadBoundSources(),
        _loadEnrichedMeta(),
        _loadImdbEnrichment(),
        _loadParentsGuide(),
        _loadRecommendations(),
      ]);
    } catch (_) {
      // Each loader is best effort. One failed service must not hold the
      // composed Showcase opening behind its readiness signal.
    } finally {
      if (mounted) setState(() => _showcaseOpeningDataReady = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  /// The IN-APP player (and the Sources screen) pushes a route on top of this
  /// screen, so it pops BACK here when playback ends — refresh the label then.
  @override
  void didPopNext() => _refreshAfterPlayback();

  /// The other half of the same story: the Android TV native player, DeoVR and
  /// external players run in their own ACTIVITY and never push a Flutter route,
  /// so [didPopNext] can never fire for them — without this the resume label and
  /// episode ticks stayed frozen at their pre-playback values until the page was
  /// re-opened. [MainPageBridge.notifyPlaybackReturned] is that missing signal.
  ///
  /// Gated on being the current route: when this page sits buried under another
  /// detail route (series A → recommended series B), the top one owns the
  /// refresh and this one re-reads on its own [didPopNext] once that route pops.
  void _onPlaybackReturned() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _refreshAfterPlayback();
  }

  void _refreshAfterPlayback() {
    // Disarm the engine-outranks latch for the post-playback re-read ONLY.
    // Playback just changed everything the latch's engine target was built
    // from, and with post-settle non-mutation emissions suppressed, an armed
    // latch would freeze the pill for the page's life (loader discarded at
    // its guard, engine re-merge dropped as non-mutation) while Play moved
    // on. Mid-page the latch keeps its job: a slow stale loader still can't
    // overwrite fresher engine data.
    _hasMergedEpisodeTarget = false;
    _loadResumeInfo();
    // Watched state (and thus the resume label / badges) may have changed while
    // away — re-read the Trakt status too.
    _tracker.loadAll();
    _loadLocalMovieFinished();
    _loadMyWatchlistState();
    // And the episode list's ticks/progress: episode quick-play now plays on
    // top of this screen (like Resume), so the list is still alive when the
    // player returns and must reflect the session that just ended.
    _episodesPanelKey.currentState?.refreshWatchProgress();
    // Sources can be bound from inside the player's own source picker and from
    // the app-action menu, so returning here is the only place that catches
    // both. Cheap — a prefs read, not a network call.
    unawaited(_loadBoundSources());
  }

  Future<void> _loadMyWatchlistState() async {
    if (!_supportsMyWatchlist) return;
    final saved = await MyWatchlistStore.isInMyWatchlist(_myWatchlistItem);
    if (!mounted || saved == _inMyWatchlist) return;
    setState(() => _inMyWatchlist = saved);
  }

  Future<void> _toggleMyWatchlist() async {
    if (!_supportsMyWatchlist) return;
    final next = !_inMyWatchlist;
    setState(() => _inMyWatchlist = next);
    try {
      await MyWatchlistStore.setMyWatchlistItem(_myWatchlistItem, next);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              next ? 'Added to My Watchlist' : 'Removed from My Watchlist',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      setState(() => _inMyWatchlist = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t update My Watchlist')),
      );
    }
  }

  Future<void> _loadLocalMovieFinished() async {
    if (!_isMovie) return;
    final imdbId =
        _item.effectiveImdbId ?? (_item.id.startsWith('tt') ? _item.id : null);
    if (imdbId == null || imdbId.isEmpty) return;
    final finished = await PlaybackProgressStore.isMovieFinished(imdbId);
    if (mounted && finished != _localMovieFinished) {
      setState(() => _localMovieFinished = finished);
    }
  }

  Future<void> _loadResumeInfo() async {
    final loader = widget.resumeInfoLoader;
    if (loader == null) return;
    debugPrint(
      '[SeriesResume] detail-loader-start title="${_item.name}" '
      'id=${_item.effectiveImdbId ?? _item.id} '
      'routeTarget=S${widget.initialSeason}E${widget.initialEpisode} '
      'loaded=$_resumeLoaded mergedTarget=$_hasMergedEpisodeTarget',
    );
    // setState, not a plain assignment: this runs post-frame (initState
    // schedules it via addPostFrameCallback), and the spinner must actually
    // be scheduled to paint — a bare write only showed it when a sibling
    // loader happened to rebuild.
    if (!_resumeLoaded && mounted) {
      setState(() => _resumePending = true);
    }
    _resumeLoaderInFlight = true;
    try {
      // Time-boxed: the reconciler boxes its tracker fetches but the guide
      // advance can hang on an unbounded body read — and with engine
      // emissions now stashed pre-settle, a hung loader would spin the pill
      // forever. A timeout throws into the catch/finally path, which applies
      // the stashed engine target.
      final info = await loader().timeout(const Duration(seconds: 12));
      if (!mounted) return;
      debugPrint(
        '[SeriesResume] detail-loader-answer title="${_item.name}" '
        'started=${info.started} season=${info.season} episode=${info.episode} '
        'engineAlreadyMerged=$_hasMergedEpisodeTarget '
        'stashedEngine=${_pendingEngineTarget == null ? 'none' : 'S${_pendingEngineTarget!.season}E${_pendingEngineTarget!.episode}/started=${_pendingEngineTarget!.started}'}',
      );
      // Once the mounted episode engine has resolved all tracker/local
      // progress, its coordinate is newer and richer than the host loader's
      // cached Continue Watching snapshot. Do not let a slower stale loader
      // overwrite (for example) E7 back to a completed E6. (Pre-settle the
      // engine only stashes, so this guard fires solely on post-settle
      // re-reads — e.g. didPopNext after playback.)
      if (!_isMovie && _hasMergedEpisodeTarget) {
        debugPrint(
          '[SeriesResume] detail-loader-discarded title="${_item.name}" '
          'reason=engine-already-authoritative',
        );
        return;
      }
      // Settle arbitration, deterministic where the old code was
      // last-writer-wins. The reconciled loader wins whenever it found a
      // resume: it reads the same trackers + local the engine merges, PLUS
      // recency and the watched frontier — and it is what Play executes, so
      // preferring it keeps the pill and the button provably in lock-step
      // (the engine is frontier-aware but recency-blind: it would call a
      // fresh rewatch "S5" while Play resumes the rewatched episode). The
      // stashed engine target only settles the pill when the loader came
      // back empty-handed — merged in-page progress beats "Start Watching".
      final stash = _pendingEngineTarget;
      _pendingEngineTarget = null;
      if (!_isMovie && !info.started && stash != null && stash.started) {
        debugPrint(
          '[SeriesResume] detail-loader-arbitration title="${_item.name}" '
          'winner=engine target=S${stash.season}E${stash.episode} '
          'reason=loader-unstarted',
        );
        _applyEngineTarget(stash);
        return;
      }
      debugPrint(
        '[SeriesResume] detail-loader-arbitration title="${_item.name}" '
        'winner=loader target=S${info.season}E${info.episode} '
        'engineCandidate=${stash == null ? 'none' : 'S${stash.season}E${stash.episode}/started=${stash.started}'}',
      );
      setState(() {
        _resumeLoaded = true;
        _resumeStarted = info.started;
        _resumeSeason = info.season;
        _resumeEpisode = info.episode;
      });
    } catch (error, stackTrace) {
      // Non-critical — leave the static label.
      debugPrint(
        '[SeriesResume] detail-loader-failed title="${_item.name}" '
        'error=$error\n$stackTrace',
      );
    } finally {
      _resumeLoaderInFlight = false;
      if (_resumePending) {
        if (mounted) {
          setState(() => _resumePending = false);
        } else {
          _resumePending = false;
        }
      }
      // Loader failed (or bailed) without settling: the stashed engine
      // target is better than a pill stuck on the static label. Emissions
      // arriving after this point direct-write (legacy) — the in-flight
      // window is closed, so nothing can strand in the stash.
      if (mounted && !_resumeLoaded) {
        final fallback = _pendingEngineTarget;
        _pendingEngineTarget = null;
        if (fallback != null) _applyEngineTarget(fallback);
      }
    }
  }

  void _onNextEpisodeChanged(
    EpisodeResumeTarget next, {
    bool mutation = false,
  }) {
    if (!mounted || _isMovie) return;
    debugPrint(
      '[SeriesResume] detail-engine-emission title="${_item.name}" '
      'target=S${next.season}E${next.episode} started=${next.started} '
      'mutation=$mutation loaderInFlight=$_resumeLoaderInFlight '
      'labelLoaded=$_resumeLoaded current=S${_resumeSeason}E$_resumeEpisode '
      'currentStarted=$_resumeStarted',
    );
    // While the loader is IN FLIGHT: stash, never write. The episodes engine
    // re-emits as each tracker fetch lands, and letting every emission write
    // the pill strobed it through wrong states ("Start Watching" → S2E8 →
    // S1E7) and killed the busy spinner. The loader's reconciled answer
    // settles the pill exactly ONCE, arbitrating against this stash. A
    // failed/absent loader closes the window, so emissions never strand.
    // Mutations are deliberate single user actions, not strobe — they write
    // through even mid-loader (stashing dropped their tag and let a stale
    // settle discard them); the applied target arms the loader guard, so a
    // later-settling loader cannot overwrite the user's mark.
    if (_resumeLoaderInFlight && !_resumeLoaded && !mutation) {
      _pendingEngineTarget = next;
      debugPrint(
        '[SeriesResume] detail-engine-stashed title="${_item.name}" '
        'target=S${next.season}E${next.episode}',
      );
      return;
    }
    // Settled STARTED: the loader is authoritative (it is literally what
    // Play executes) — only explicit in-page MUTATIONS (mark watched/
    // unwatched) move the pill; a slower engine initial-merge landing after
    // settle must not late-flip it (the loader-vs-engine finish order is a
    // network race). A settle that found NO resume is different: a later
    // started engine target upgrades it — "merged progress beats Start
    // Watching" must not depend on which fetch finished first.
    if (_resumeLoaded &&
        _resumeStarted &&
        !mutation &&
        widget.resumeInfoLoader != null) {
      debugPrint(
        '[SeriesResume] detail-engine-discarded title="${_item.name}" '
        'target=S${next.season}E${next.episode} '
        'reason=started-loader-authoritative',
      );
      return;
    }
    if (_resumeLoaded &&
        _resumeStarted == next.started &&
        _resumeSeason == next.season &&
        _resumeEpisode == next.episode) {
      return;
    }
    _applyEngineTarget(next);
  }

  /// Write an engine target into the pill state (the legacy
  /// [_onNextEpisodeChanged] body): merged playback progress outranks the
  /// host's snapshot, so a started target also arms the loader-overwrite
  /// guard.
  void _applyEngineTarget(EpisodeResumeTarget next) {
    debugPrint(
      '[SeriesResume] detail-engine-applied title="${_item.name}" '
      'target=S${next.season}E${next.episode} started=${next.started}',
    );
    setState(() {
      // A coordinate alone is not resume evidence: an untouched show also
      // resolves to its first episode. Only merged playback progress outranks
      // the host's independently loaded Continue Watching snapshot.
      _hasMergedEpisodeTarget = next.started;
      _resumeLoaded = true;
      _resumeStarted = next.started;
      _resumeSeason = next.season;
      _resumeEpisode = next.episode;
    });
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static Play/Resume label until the resume state resolves.
  String get _primaryLabel {
    // Completion is available independently of the optional resume loader.
    // Keep the rewatch affordance visible for movie routes that omit one.
    if (!_resumeLoaded) {
      if (_isMovie &&
          (_localMovieFinished || _tracker.simklStatus?.currentStatus == 'completed')) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Resume';
    }
    if (!_resumeStarted) {
      // A movie already finished on Simkl (status `completed`) has no resume
      // session; its Play un-marks it watched so the rewatch re-enters
      // Continue Watching — surface that intent as "Rewatch".
      if (_isMovie &&
          (_localMovieFinished || _tracker.simklStatus?.currentStatus == 'completed')) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Start Watching';
    }
    if (_isMovie || _resumeSeason == null || _resumeEpisode == null) {
      return 'Resume';
    }
    return 'Resume · S${_resumeSeason}E$_resumeEpisode';
  }

  /// Pull a per-title accent from the poster (preferred — posters are more
  /// brand-saturated than backdrops). One tiny 32px decode; silent on failure,
  /// leaving the gold fallback. Extracted from the initial artwork only — a
  /// later enrichment swap isn't worth a second pass.
  ///
  /// Through [DominantColorCache] rather than the extractor directly, so
  /// reopening a title costs nothing and two screens asking at once share one
  /// decode. The cache also remembers a NULL answer, which is the common case
  /// for black-and-white artwork and used to be re-decoded on every visit.
  Future<void> _loadAccent() async {
    final url = widget.item.poster ?? widget.item.background;
    if (url == null || url.isEmpty) return;
    try {
      final c = await DominantColorCache.of(
        url,
        CachedNetworkImageProvider(url),
      );
      if (c != null && mounted) setState(() => _accent = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    _infoScroll.dispose();
    _castRailScroll.dispose();
    _recommendationRailScroll.dispose();
    _leftEntryFocusNode.dispose();
    _infoPaneScope.dispose();
    _episodesPaneScope.dispose();
    _backButtonFocusNode.dispose();
    _tracker.dispose();
    _trailer.dispose();
    super.dispose();
  }

  Future<void> _loadEnrichedMeta() async {
    final enrich = widget.metaEnricher;
    final item = widget.item;
    final imdbId = item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;
    // A missing summary is on its own a reason to ask Cinemeta: rows from
    // Trakt / Simkl / MDBList arrive with a year and rating but no overview, and
    // the page has no other source for the description (the IMDb plot is a
    // best-effort scrape that can go away).
    final alreadyRich =
        (item.description?.isNotEmpty ?? false) &&
        ((item.year != null && item.year!.isNotEmpty) ||
            item.imdbRating != null ||
            (item.genres?.isNotEmpty ?? false));
    if (alreadyRich) return;
    try {
      final full = await enrich(imdbId, item.type);
      if (full == null || !mounted) return;
      setState(() {
        _enriched = StremioMeta(
          id: item.id,
          imdbId: item.imdbId,
          type: item.type,
          name: full.name.isNotEmpty ? full.name : item.name,
          poster: full.poster ?? item.poster,
          background: full.background ?? item.background,
          description: (full.description?.isNotEmpty ?? false)
              ? full.description
              : item.description,
          year: full.year ?? item.year,
          imdbRating: full.imdbRating ?? item.imdbRating,
          genres: (full.genres?.isNotEmpty ?? false)
              ? full.genres
              : item.genres,
          runtime: full.runtime ?? item.runtime,
          sourceAddon: item.sourceAddon,
          trailerYtId: full.trailerYtId ?? item.trailerYtId,
          logo: full.logo ?? item.logo,
        );
      });
    } catch (_) {}
  }

  Future<void> _loadImdbEnrichment() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) return;
    try {
      final extra = await ImdbEnrichmentService.fetch(imdbId);
      if (mounted) setState(() => _imdbExtra = extra);
    } catch (_) {}
  }

  Future<void> _loadParentsGuide() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) return;
    try {
      final guide = await ImdbParentsGuideService.fetch(imdbId);
      if (mounted) setState(() => _parentsGuide = guide);
    } catch (_) {}
  }

  Future<void> _loadRecommendations() async {
    final loader = widget.recommendationsLoader;
    if (loader == null) return;
    try {
      final recs = await loader();
      if (mounted) setState(() => _recommendations = recs);
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Two-pane (compact info left | full-height episodes right) on TV + desktop
  /// — episodes get the whole column height, which is the point. Android TV is
  /// only ~540 logical px tall, so a full-width hero would swallow the screen;
  /// the left pane keeps info compact and scrollable instead. Mobile stacks.
  bool get _wide =>
      widget.isTelevision || MediaQuery.of(context).size.width >= 900;

  /// Compact-height screens (TV ~540 logical px): shrink type + spacing.
  bool get _tight => MediaQuery.of(context).size.height < 640;

  bool get _isMovie => _item.type == 'movie';

  /// The reference plays its detail-page preview CRYSTAL CLEAR — no wash, no
  /// glow, no blur. True while the Showcase ambient trailer is actually
  /// rolling off-TV with the page at its hero; every shell-level veil over
  /// the video gates on this. TV is untouched (its washes were tuned on the
  /// panel and nobody has complained at ten feet).
  bool get _trailerClearView =>
      _style == 'showcase' &&
      !widget.isTelevision &&
      _trailer.ambientPlaying &&
      !_bodyDeep;

  @override
  Widget build(BuildContext context) {
    // Establishes the dependency that makes an ALREADY OPEN detail route
    // re-theme when a token is edited. `_theme` reads the controller directly,
    // which is a plain field read and notifies nobody — without this line the
    // page you edited from would be the last one to change.
    AppThemeScope.of(context);
    // The backdrop is the one display-sized detail hero. Keep the model's
    // catalog URL intact for rails, but ask MetaHub for the large source here.
    final backdropUrl = highQualityArtworkUrl(_item.background ?? _item.poster);
    return PopScope(
      // While the trailer is fullscreen, Back closes it instead of leaving the
      // page — the same player stays alive and settles back into the backdrop.
      canPop: !_trailer.foreground,
      onPopInvoked: (didPop) {
        if (!didPop) _trailer.exitForeground(context);
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Full-bleed backdrop → the Stremio "one lit surface" feel. When a
            // trailer is available and autoplay is on, it crossfades from this
            // static poster into a looping preview (OTT-style), and the
            // Trailer button promotes this same player to fullscreen in place.
            // Non-focusable and behind all content, so DPAD is unaffected.
            Positioned.fill(
              child: HeroTrailerBackdrop(
                key: _trailer.backdropKey,
                heroTag: widget.heroTag,
                imageUrl: backdropUrl,
                // Weak-TV GPU: sigma 0 swaps the runtime gaussian for a tiny
                // decode upscaled by cover-fit (visually equivalent under the
                // dark tint, zero per-frame filter cost), and drops the
                // per-frame blur pass over the ambient trailer video.
                imageBlurSigma: widget.isTelevision ? 0 : 42,
                // Showcase at rest is the reference's full-bleed key art; the
                // moment the body goes deep this reverts to the wash, which is
                // the field the bands' white text was tuned against.
                sharpStill: _wantsSharpStill,
                // Sigma 8 was tuned for the classic layout, where the video
                // is an AMBIENT backdrop behind opaque panes. Showcase is the
                // reference's shape — the trailer IS the picture, playing in
                // the key-art frame — and blurring it is why it read as dim
                // mush next to the Apple app. Sharp for Showcase everywhere;
                // the other layouts keep their ambient blur.
                videoBlurSigma: widget.isTelevision || _style == 'showcase'
                    ? 0
                    : 8,
                // Dropped the moment the body walks past its hero: the
                // reference's trailer belongs to the key-art frame, and playing
                // one under a blurred field is a decoder held for nothing. It
                // also frees the process's single video output for whatever the
                // user opens next.
                videoUrl: _trailer.autoplayEnabled && !_bodyDeep
                    ? _trailer.streams?.playUrl
                    : null,
                audioUrl: _trailer.autoplayEnabled && !_bodyDeep
                    ? _trailer.streams?.audioUrl
                    : null,
                // Resolution and decoder startup already provide a natural
                // poster dwell. Do not stack an artificial wait on top of that.
                startDelay: Duration.zero,
                // Suspend at the Play press, before source/resume resolution.
                // The pipeline loader is a PopupRoute rather than a PageRoute,
                // so RouteAware.didPushNext cannot provide this lifecycle beat.
                enabled: _trailer.autoplayEnabled && !_playLaunching,
                ambientVolume: _trailer.ambientVolume,
                foreground: _trailer.foreground,
                onRequestClose: () => _trailer.exitForeground(context),
                onPlayingChanged: _trailer.setAmbientPlaying,
              ),
            ),
            // Page content (tint + panes + back button). Fades out and stops
            // taking input while the trailer is foregrounded, revealing the
            // now-fullscreen, unblurred trailer beneath. ExcludeFocus matters
            // on TV: IgnorePointer only blocks pointers — without it, DPAD OK
            // would still activate the invisible Play/episode tiles under the
            // fullscreen trailer.
            Positioned.fill(
              child: ExcludeFocus(
                excluding: _trailer.foreground,
                child: IgnorePointer(
                  ignoring: _trailer.foreground,
                  child: AnimatedOpacity(
                    opacity: _trailer.foreground ? 0 : 1,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOut,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Ambient still (Filmstrip): the focused episode's frame,
                        // painted over the backdrop art but under everything
                        // else. Inside this AnimatedOpacity so it fades away
                        // with the rest of the content when the trailer is
                        // promoted, and suppressed outright while it is —
                        // otherwise it would cover the fullscreen video.
                        if (_focusedStillUrl != null &&
                            !_trailer.foreground &&
                            !_trailer.ambientPlaying)
                          Positioned.fill(
                            child: DetailAmbientStill(
                              url: _focusedStillUrl!,
                              isTelevision: widget.isTelevision,
                            ),
                          ),
                        // Darker tint so even a bright poster reads as a dark
                        // surface. Skipped for layouts that paint their own
                        // scrim — two stacked washes take the artwork to
                        // near-black, and a full-bleed layout is ABOUT the
                        // artwork. Those layouts keep a much lighter floor so
                        // a blown-out image still can't wash out the chrome.
                        // `shellTint: false` paints NOTHING here — not a
                        // lighter wash, none at all. A layout whose scrim is a
                        // specific angle cannot reach its spec while the shell
                        // is also laying a diagonal over the same artwork.
                        // Lifted entirely while the Showcase ambient trailer
                        // rolls off-TV: the reference plays its preview
                        // crystal clear in the key-art frame, and even this
                        // light floor reads as a haze over motion. The
                        // layout's own scrim (thinned the same way) keeps the
                        // identity text legible. Snapped, not tweened — same
                        // rule as the home hero's rolling scrims.
                        if (_bodySpec.shellTint && !_trailerClearView)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _bodySpec.ownScrim
                                    ? [
                                        _bg.withValues(alpha: 0.10),
                                        _bg.withValues(alpha: 0.24),
                                      ]
                                    : [
                                        _bg.withValues(alpha: 0.60),
                                        _bg.withValues(alpha: 0.88),
                                      ],
                              ),
                            ),
                          ),
                        // Flat editorial ground (Broadsheet). Painted here so
                        // it covers the artwork without ever becoming an
                        // ancestor of the trailer backdrop, and so it fades
                        // out with the content on promotion.
                        if (_bodySpec.inkGround)
                          Positioned.fill(
                            child: ColoredBox(color: _groundColor),
                          ),
                        // Ambient per-title color grade: a soft glow of the
                        // extracted accent in the upper-left, under the content,
                        // so the whole surface is subtly lit by the title's own
                        // color. Animates in when the accent resolves (no pop).
                        // A radial gradient fill is a single cheap paint — no
                        // blur, no layer — so it's safe on the weak TV GPU.
                        if (_bodySpec.shellTint && !_trailerClearView)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: TweenAnimationBuilder<Color?>(
                                duration: const Duration(milliseconds: 500),
                                tween: ColorTween(
                                  end: _accent.withValues(
                                    alpha: _themedBody
                                        ? _theme.washOpacity
                                        : 0.16,
                                  ),
                                ),
                                builder: (_, color, __) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: const Alignment(-0.7, -0.85),
                                      radius: 1.5,
                                      colors: [
                                        color ?? Colors.transparent,
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.7],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        SafeArea(child: _buildBody(backdropUrl)),
                        // Back button.
                        Positioned(
                          top: 0,
                          left: 0,
                          child: SafeArea(
                            child: Padding(
                              padding: EdgeInsets.all(
                                widget.isTelevision ? 20 : 8,
                              ),
                              child: _circleButton(
                                Icons.arrow_back_rounded,
                                () => Navigator.of(context).maybePop(),
                                tooltip: 'Back',
                                focusNode: _backButtonFocusNode,
                                // Square themes (Noir, Concrete, Phosphor,
                                // Blueprint) cannot be forced into a circle.
                                theme: _themedBody ? _theme : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Small "trailer playing in background" hint — only while the
            // ambient trailer is actually playing and not promoted. Tapping it
            // brings the trailer forward (same as the Trailer button).
            if (_trailer.ambientPlaying && !_trailer.foreground)
              Positioned(
                left: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(widget.isTelevision ? 20 : 12),
                    child: DetailTrailerPlayingChip(
                      onTap: () => _trailer.play(context),
                      theme: _themedBody ? _theme : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Everything the alternate layouts render, rebuilt with the screen so every
  /// load, refresh and tracker round-trip reaches them unchanged.
  ///
  /// Layouts are stateless with respect to data — they own only focus, scroll
  /// The bound sources behind Showcase's Sources band.
  ///
  /// A SharedPreferences read plus a JSON decode — no network — which is what
  /// lets the band paint on open. Reloaded after the source manager closes and
  /// on playback return, or it goes stale the moment anyone binds anything.
  List<SeriesSource> _boundSources = const [];

  /// Called from every path that can change a binding — the source manager,
  /// the app-action menu, and playback return. A band that only refreshes on
  /// one of the three is stale the first time someone uses another.
  Future<void> _loadBoundSources() async {
    final imdb = _item.imdbId;
    if (imdb == null || imdb.isEmpty) return;
    final list = await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    setState(() => _boundSources = list);
  }

  /// and tab state.
  DetailModel _buildDetailModel() {
    return DetailModel(
      item: _item,
      isMovie: _isMovie,
      isTelevision: widget.isTelevision,
      // Signal keeps the poster-extracted accent, which is what ships today.
      // A fixed-palette theme (Noir's white, Phosphor's amber) would be
      // contaminated by it, so it uses its own.
      accent: _theme.useArtworkAccent ? _accent : _theme.accent,
      imdbExtra: _imdbExtra,
      parentsGuide: _parentsGuide,
      recommendations: _recommendations ?? const [],
      openingDataReady: _showcaseOpeningDataReady,
      primaryLabel: _primaryLabel,
      primaryBusy: _primaryBusy,
      sourceCount: widget.boundSourceCount?.call(_item) ?? 0,
      boundSources: _boundSources,
      hasTrailer: _trailer.ytId != null,
      trailerBusy: _trailer.resolving || _trailer.loading,
      trailerPlaying: _trailer.ambientPlaying,
      hasTrakt: _tracker.traktOnlyMenuOptions.isNotEmpty,
      traktTracked: _tracker.traktTracked,
      traktLabel: _tracker.traktPillLabel,
      traktRating: _tracker.traktStatus?.rating,
      hasSimkl: _tracker.menuOptionsSimkl.isNotEmpty,
      simklTracked: _tracker.simklTracked,
      simklLabel: _tracker.simklPillLabel,
      simklRating: _tracker.simklStatus?.rating,
      hasMdblist: _tracker.menuOptionsMdblist.isNotEmpty,
      mdblistTracked: _tracker.mdblistTracked,
      mdblistLabel: _tracker.mdblistPillLabel,
      mdblistRating: _tracker.mdblistStatus?.rating,
      showPrimary: widget.showQuickPlay,
      onPrimary: _playPrimary,
      onPrimaryLongPress:
          ((_isMovie && widget.onBrowse != null) ||
              (!_isMovie && widget.onBrowsePrimaryEpisodeSources != null))
          ? _browsePrimarySources
          : null,
      // A movie browses the full source list the host supplies; a series
      // browses season packs — the same search the More menu's "Search
      // season packs" row opens, promoted to a first-class button. Gated on
      // that row actually being in the menu so the button never mounts for a
      // host that didn't offer the action.
      onBrowse: _isMovie
          ? widget.onBrowse
          : (widget.onTraktAction != null &&
                _tracker.appMenuOptions.any(
                  (o) => o.action == TraktItemMenuAction.searchPacks,
                ))
          ? () => widget.onTraktAction!(TraktItemMenuAction.searchPacks)
          : null,
      onTrailer: () => _trailer.play(context),
      onSelectSource: widget.onSelectSource == null
          ? null
          : () async {
              await widget.onSelectSource!(_item);
              if (mounted) setState(() {});
            },
      onAppMenu: (_tracker.appMenuOptions.isNotEmpty && widget.onTraktAction != null)
          ? () => _tracker.showAppActionsMenu(context)
          : null,
      onTraktMenu: widget.onTraktAction != null ? () => _tracker.showTraktQuickActionsMenu(context) : null,
      onSimklMenu: widget.onSimklAction != null
          ? () => _tracker.showSimklQuickActionsMenu(context)
          : null,
      onMdblistMenu: widget.onMdblistAction != null
          ? () => _tracker.showMdblistQuickActionsMenu(context)
          : null,
      inMyWatchlist: _inMyWatchlist,
      onToggleMyWatchlist: _supportsMyWatchlist ? _toggleMyWatchlist : null,
      // Both trackers behind one affordance, for a layout whose action row has
      // no room for two branded pills. Whichever single service is configured
      // opens directly; with both, the app menu is the chooser that already
      // lists them.
      // Null when neither service is configured, or the layout mounts a `+`
      // that focuses and does nothing. There is no combined sheet to open —
      // `DetailTrackerController.showAppActionsMenu` is the APP-action list, not a tracker chooser —
      // so with both configured this opens Trakt's, and Simkl stays reachable
      // through the More button beside it.
      // Gated on whether a tracker is actually CONNECTED, not on whether the
      // host passed a callback — the home screen always passes the Trakt one,
      // so a callback test mounts a `+` that focuses and does nothing for
      // anyone who has not connected Trakt.
      //
      // With both connected this opens Trakt's sheet and Simkl stays reachable
      // from the More button beside it; there is no combined sheet to open,
      // and `DetailTrackerController.showAppActionsMenu` is the APP-action list, not a chooser.
      onTrackers:
          (_tracker.traktOnlyMenuOptions.isNotEmpty && widget.onTraktAction != null)
          ? () => _tracker.showTraktQuickActionsMenu(context)
          : (_tracker.menuOptionsSimkl.isNotEmpty && widget.onSimklAction != null
                ? () => _tracker.showSimklQuickActionsMenu(context)
                : (_tracker.menuOptionsMdblist.isNotEmpty &&
                          widget.onMdblistAction != null
                      ? () => _tracker.showMdblistQuickActionsMenu(context)
                      : null)),
      // Only when Trakt already took the first slot; otherwise Simkl IS the
      // first slot above and this would mount the same sheet twice.
      onTrackersSecondary:
          (_tracker.traktOnlyMenuOptions.isNotEmpty &&
              widget.onTraktAction != null &&
              _tracker.menuOptionsSimkl.isNotEmpty &&
              widget.onSimklAction != null)
          ? () => _tracker.showSimklQuickActionsMenu(context)
          : (((_tracker.traktOnlyMenuOptions.isNotEmpty &&
                        widget.onTraktAction != null) ||
                    (_tracker.menuOptionsSimkl.isNotEmpty &&
                        widget.onSimklAction != null)) &&
                _tracker.menuOptionsMdblist.isNotEmpty &&
                widget.onMdblistAction != null)
          ? () => _tracker.showMdblistQuickActionsMenu(context)
          : null,
      onTrackersTertiary:
          (_tracker.traktOnlyMenuOptions.isNotEmpty &&
              widget.onTraktAction != null &&
              _tracker.menuOptionsSimkl.isNotEmpty &&
              widget.onSimklAction != null &&
              _tracker.menuOptionsMdblist.isNotEmpty &&
              widget.onMdblistAction != null)
          ? () => _tracker.showMdblistQuickActionsMenu(context)
          : null,
      // There is no per-source host API, so a card in the Sources band and the
      // "Find sources" tile both land on the title-level manager — and the
      // band reloads afterwards, since binding is exactly what changes it.
      onManageSources: widget.onSelectSource == null
          ? null
          : () async {
              await widget.onSelectSource!(_item);
              if (!mounted) return;
              setState(() {});
              await _loadBoundSources();
            },
      onRecommendationTap: widget.onRecommendationTap,
      onAmbientStill: (url) {
        if (!mounted || _focusedStillUrl == url) return;
        setState(() => _focusedStillUrl = url);
      },
      onDepth: (deep) {
        if (!mounted || _bodyDeep == deep) return;
        setState(() => _bodyDeep = deep);
      },
      focus: _focusCoordinator,
    );
  }

  /// Hands an alternate layout the hosted engine. Null for movies, which have
  /// no episode list at all.
  Widget Function(Widget Function(BuildContext, EpisodesPanelView))?
  get _episodesHost => _isMovie
      ? null
      : (builder) => _buildEpisodesPanel(contentBuilder: builder);

  /// What the active body wants painted behind it.
  DetailBodySpec get _bodySpec => switch (_style) {
    // Marquee and Stage are showcase layouts — the artwork is the point, and
    // each already paints the gradient its own identity block sits on.
    'marquee' ||
    'stage' ||
    'vista' ||
    'halo' => const DetailBodySpec(ownScrim: true),
    // Showcase paints a SPECIFIC angled scrim (100° from the left) and its own
    // ambient field. `ownScrim` alone only swaps the shell's diagonal for a
    // lighter one; compounded with Showcase's own gradient neither reaches the
    // spec. `shellTint: false` is the only mode that leaves the artwork alone.
    'showcase' => const DetailBodySpec(ownScrim: true, shellTint: false),
    // A light theme cannot sit on the artwork at all: its own ground has to
    // cover it, or black-on-paper text lands on a photograph.
    _ => DetailBodySpec(inkGround: _themedBody && _theme.lightGround),
  };

  /// Whether the active layout is one the theme applies to.
  bool get _themedBody => _style != 'classic';

  /// The ground the shell paints when the body asks for a flat one.
  Color get _groundColor =>
      _themedBody ? _theme.ground : const Color(0xFF0A0A0C);

  /// The one thing that switches on the chosen layout. Everything around it —
  /// PopScope, the trailer backdrop and its promote/dismiss, the tint, the back
  /// button, the trailer chip — is shell, written once.
  Widget _buildBody(String? backdropUrl) {
    // Every alternate body is wrapped; Classic never is, so it cannot be
    // affected by a theme even accidentally.
    // Grid and grain are whole-page textures, so they are applied once here
    // rather than by each layout — and Classic, which is never wrapped, cannot
    // pick them up by accident.
    // DetailHoldHint is the page-level affordance for the episode cells' held
    // OK — one pill in the screen's corner rather than chrome on every card.
    // It sits here, around every alternate layout at once, so no layout has to
    // opt in; it renders nothing off TV and nothing until a cell takes focus.
    Widget themed(Widget body) => DetailThemeScope(
      theme: _theme,
      child: DetailAtmosphere(child: DetailHoldHint(child: body)),
    );

    switch (_style) {
      case 'marquee':
        return themed(
          DetailMarquee(
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'dossier':
        return themed(
          DetailDossier(
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'stage':
        return themed(
          DetailStage(model: _buildDetailModel(), episodesHost: _episodesHost),
        );
      case 'console':
        return themed(
          DetailConsole(
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'vista':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.vista,
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'monolith':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.monolith,
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'mosaic':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.mosaic,
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'halo':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.halo,
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'premiere':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.premiere,
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
          ),
        );
      case 'showcase':
        return themed(
          DetailShowcase(
            model: _buildDetailModel(),
            episodesHost: _episodesHost,
            // The INPUT axis: unlocks the touch drivers (scroll dissolve,
            // kebab, compact presentation under 600 wide) off-TV. Width is
            // deliberately not the test — a narrow TV must stay a TV.
            dpad: PlatformUtil.isTelevision,
          ),
        );
      // Only 'classic' reaches here: every shipped alternate has a case above,
      // and anything not yet drawable was already narrowed to the DEFAULT by
      // effectiveDetailPageStyle — which is no longer Classic, so this arm is
      // now the explicit choice rather than the fallback.
      default:
        return _buildClassicBody(backdropUrl);
    }
  }

  /// Today's screen, unchanged: movie column, two-pane, or stacked.
  Widget _buildClassicBody(String? backdropUrl) {
    if (_isMovie) {
      // A movie has no episode list — one centered, scrollable detail column.
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _buildInfoPane(),
        ),
      );
    }
    if (_wide) return _buildTwoPane(backdropUrl);
    return Column(
      children: [
        _buildHero(),
        Expanded(child: _buildStackedBody()),
      ],
    );
  }

  /// TV + desktop: left info column (scrollable) + right episode column (full
  /// height). Each pane is its own [FocusScope] so vertical traversal is
  /// contained within it; panes are crossed only horizontally — LEFT from an
  /// episode to the info column's primary action, RIGHT from the info column
  /// back to the pane's remembered episode row.
  Widget _buildTwoPane(String? backdropUrl) {
    final w = MediaQuery.of(context).size.width;
    final leftW = (w * 0.42).clamp(320.0, 480.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left info column, darkened so text stays legible over any backdrop.
        SizedBox(
          width: leftW,
          child: FocusScope(
            node: _infoPaneScope,
            onKeyEvent: _handleInfoPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _bg.withValues(alpha: 0.82),
                    _bg.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: _buildInfoPane(),
            ),
          ),
        ),
        Expanded(
          child: FocusScope(
            node: _episodesPaneScope,
            onKeyEvent: _handleEpisodesPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0E0B14).withValues(alpha: 0.82),
                border: Border(left: BorderSide(color: _hair)),
              ),
              child: _buildEpisodesPanel(),
            ),
          ),
        ),
      ],
    );
  }

  /// Cross RIGHT into the episodes pane: the scope remembers its last-focused
  /// row, so re-entry lands where the user left off (first traversable —
  /// season header or first row — on a cold entry).
  void _focusEpisodesPane() {
    final scope = _episodesPaneScope;
    FocusNode? target = scope.focusedChild;
    if (target == null) {
      final descendants = scope.traversalDescendants;
      target = descendants.isEmpty ? null : descendants.first;
    }
    target?.requestFocus();
  }

  /// Info-pane key policy. These fire only for keys the focused child ignored
  /// (buttons/tiles don't handle arrows), and always attempt an in-scope
  /// directional move first — so Play → Trailer etc. still work — falling back
  /// to the explicit pane behavior only at the pane's edge:
  ///  • RIGHT at the right edge crosses into the episodes pane;
  ///  • UP at the top goes to the floating back button;
  ///  • DOWN at the bottom is a dead stop (never leaks into episodes).
  KeyEventResult _handleInfoPaneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!primary.focusInDirection(TraversalDirection.right)) {
        _focusEpisodesPane();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!primary.focusInDirection(TraversalDirection.up)) {
        _backButtonFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Episodes-pane key policy: Up/Down move within the pane only (dead stop at
  /// the first/last row — the scope already contains directional traversal;
  /// handling the key here just stops it from bubbling further). LEFT from the
  /// season header (rows handle their own LEFT) falls through the header
  /// controls and then crosses to the info column's primary action.
  KeyEventResult _handleEpisodesPaneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(
        key == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!primary.focusInDirection(TraversalDirection.left) &&
          detailNodeMounted(_leftEntryFocusNode)) {
        _leftEntryFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInfoPane() {
    final item = _item;
    final extra = _imdbExtra;
    final t = _tight;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = (item.genres?.isNotEmpty ?? false)
        ? item.genres!
        : (extra?.genres ?? const []);
    final summary = (item.description?.isNotEmpty ?? false)
        ? item.description
        : extra?.plot;

    // No entrance stagger on TV: each DetailStaggerReveal animates Opacity (a
    // saveLayer per element per frame) during the exact window the page is
    // also hero-flying and resolving the trailer — the weak TV GPU pays for
    // polish nobody perceives at 3m. Same gate as the Home hero's motion.
    final animate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        !widget.isTelevision;
    return SingleChildScrollView(
      controller: _infoScroll,
      padding: EdgeInsets.fromLTRB(
        widget.isTelevision ? 34 : 24,
        // Clear the floating top-left back button (~64px) on TV so the eyebrow
        // and title don't sit under it.
        widget.isTelevision ? 64 : (t ? 46 : 30),
        18,
        22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailStaggerReveal(
            key: const ValueKey('rev-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              _isMovie ? 'MOVIE' : 'SERIES',
              style: TextStyle(
                color: _accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          SizedBox(height: t ? 5 : 8),
          DetailStaggerReveal(
            key: const ValueKey('rev-title'),
            delayMs: 55,
            enabled: animate,
            child: Text(
              item.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: t ? 22 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.05,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
              ),
            ),
          ),
          SizedBox(height: t ? 8 : 10),
          DetailStaggerReveal(
            key: const ValueKey('rev-meta'),
            delayMs: 110,
            enabled: animate,
            child: _buildMetaBar(year, extra, rating),
          ),
          // No tracker status chips here any more: the Trakt / Simkl pills in
          // the action row carry that state themselves, so this used to render
          // the same fact twice.
          if (genres.isNotEmpty) ...[
            SizedBox(height: t ? 8 : 10),
            DetailStaggerReveal(
              key: const ValueKey('rev-genres'),
              delayMs: 165,
              enabled: animate,
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [for (final g in genres.take(3)) _pill(g)],
              ),
            ),
          ],
          SizedBox(height: t ? 12 : 16),
          // Focusing the action row snaps the column to the very top so the
          // title / meta / genres above it are revealed (fixes "can't scroll
          // back up to details").
          DetailStaggerReveal(
            key: const ValueKey('rev-actions'),
            delayMs: 220,
            enabled: animate,
            child: DetailScrollAnchor(
              toTop: true,
              active: widget.isTelevision,
              child: _buildActionRow(),
            ),
          ),
          if (summary != null && summary.isNotEmpty) ...[
            SizedBox(height: t ? 16 : 20),
            _sectionLabel('Summary'),
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          // Awards / Credits / Cast / Details / Parents Guide / More Like This —
          // all inline & reachable by scrolling (no hidden "Details" sheet).
          ..._referenceSections(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Mobile-only compact hero (wide/TV uses the left info pane instead).
  Widget _buildHero() {
    final item = _item;
    final extra = _imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = (item.genres?.isNotEmpty ?? false)
        ? item.genres!
        : (extra?.genres ?? const []);

    // No boxed hero image: the page already paints one continuous full-bleed
    // backdrop (HeroTrailerBackdrop + dark tint) behind everything — exactly
    // like the movie layout — so a second inset image here read as an ugly
    // floating card. The hero is now pure content over that shared surface,
    // sized to what it holds (the old fixed 220px box overflowed upward when
    // the action row wrapped, shoving the title under the floating back
    // button). Bonus: with autoplay on, the ambient trailer now owns the whole
    // screen behind the page instead of stopping at a card edge. Top padding
    // clears the 46px floating back button.
    final animate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        !widget.isTelevision;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.isTelevision ? 40 : 24,
        widget.isTelevision ? 20 : 64,
        24,
        14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailStaggerReveal(
            key: const ValueKey('rev-h-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              'SERIES',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          DetailStaggerReveal(
            key: const ValueKey('rev-h-title'),
            delayMs: 55,
            enabled: animate,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _wide ? 34 : 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.02,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          DetailStaggerReveal(
            key: const ValueKey('rev-h-meta'),
            delayMs: 110,
            enabled: animate,
            child: _buildMetaBar(year, extra, rating),
          ),
          // Tracker state lives in the action-row pills (see the info pane).
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            DetailStaggerReveal(
              key: const ValueKey('rev-h-genres'),
              delayMs: 165,
              enabled: animate,
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [for (final g in genres.take(4)) _pill(g)],
              ),
            ),
          ],
          const SizedBox(height: 14),
          DetailStaggerReveal(
            key: const ValueKey('rev-h-actions'),
            delayMs: 220,
            enabled: animate,
            child: _buildActionRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaBar(String? year, ImdbEnrichment? extra, double? rating) {
    final parts = <Widget>[];
    void add(Widget w) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 16));
      parts.add(w);
    }

    final runtime = extra?.runtime;
    if (runtime != null) add(_metaText(runtime));
    if (year != null && year.isNotEmpty) add(_metaText(year));
    final cert = extra?.certificate;
    if (cert != null) {
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _glass2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _hair),
          ),
          child: Text(
            cert,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    if (rating != null) {
      add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _imdb,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'IMDb',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }

  Widget _metaText(String s) => Text(
    s,
    style: TextStyle(
      color: Colors.white70,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Action-row key policy (TV). Without this, LEFT/RIGHT on a row button fall
  /// through to the pane's `focusInDirection`, whose geometric search happily
  /// picks a Cast / More-Like-This card sitting below-right of the row (every
  /// rail card is a real widget even when scrolled far out of view) — so RIGHT
  /// on the last button flung the cursor into "More Like This" instead of
  /// crossing into the episodes pane. Here the row owns its horizontal axis:
  /// RIGHT/LEFT walk the row's buttons in reading order; RIGHT past the last
  /// button crosses into the episodes pane (series two-pane only — dead stop
  /// otherwise); LEFT past the first is a dead stop.
  KeyEventResult _handleActionRowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    // The row's buttons in reading order (the Wrap can break onto a second
    // line, so order by line first, then x).
    // Bucket y into coarse lines rather than comparing raw centers: the
    // center-aligned Wrap can leave same-line buttons of different heights a
    // sub-pixel apart, which an exact compare would read as separate lines.
    // Wrap lines are ≥40px apart, so a 24px bucket can never split one.
    int line(FocusNode n) => (n.rect.center.dy / 24).round();
    final buttons = node.traversalDescendants.toList()
      ..sort((a, b) {
        final dy = line(a).compareTo(line(b));
        return dy != 0 ? dy : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    final i = buttons.indexOf(primary);
    if (i < 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (i < buttons.length - 1) {
        buttons[i + 1].requestFocus();
      } else if (!_isMovie && _wide) {
        _focusEpisodesPane();
      }
      return KeyEventResult.handled;
    }
    // LEFT: previous button; dead stop at the first (UP is the way to the
    // back button, and a geometric fallback would dive into the rails).
    if (i > 0) buttons[i - 1].requestFocus();
    return KeyEventResult.handled;
  }

  Widget _buildActionRow() {
    final count = widget.boundSourceCount?.call(_item) ?? 0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleActionRowKey,
      child: _buildActionRowButtons(count),
    );
  }

  Widget _buildActionRowButtons(int count) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Primary play. Hidden for PikPak-only (can't quick-play — it queues a
        // cloud download), mirroring the detail screen's "Play". Holds the
        // LEFT-entry focus node when present; movies autofocus it on TV (a movie
        // has no episode list to auto-focus).
        if (widget.showQuickPlay)
          DetailPrimaryButton(
            label: _primaryLabel,
            busy: _primaryBusy,
            icon: Icons.play_arrow_rounded,
            onTap: _playPrimary,
            onLongPress:
                ((_isMovie && widget.onBrowse != null) ||
                    (!_isMovie && widget.onBrowsePrimaryEpisodeSources != null))
                ? _browsePrimarySources
                : null,
            focusNode: _leftEntryFocusNode,
            autofocus: widget.isTelevision && _isMovie,
            glow: _accent,
          ),
        // Trailer — sits right after Play. Only when Cinemeta gave us a YouTube
        // trailer id. Reflects the ambient backdrop's state: spinner while the
        // trailer loads, "Watch Trailer" once it's playing (tap = fullscreen),
        // plain "Trailer" otherwise (tap = resolve & play).
        if (_trailer.ytId != null)
          DetailGhostButton(
            label: _trailer.ambientPlaying ? 'Watch Trailer' : 'Trailer',
            icon: _trailer.ambientPlaying
                ? Icons.play_circle_outline_rounded
                : Icons.movie_outlined,
            busy: _trailer.resolving || _trailer.loading,
            onTap: () => _trailer.play(context),
          ),
        // Movie: a Sources (manual list) button — the episode list is the
        // picker for series, so this is movie-only.
        if (_isMovie && widget.onBrowse != null)
          DetailGhostButton(
            label: 'Sources',
            icon: Icons.layers_rounded,
            onTap: widget.onBrowse!,
          ),
        if (_supportsMyWatchlist)
          DetailGhostButton(
            label: _inMyWatchlist ? 'In My Watchlist' : 'My Watchlist',
            icon: _inMyWatchlist
                ? Icons.bookmark_rounded
                : Icons.bookmark_add_outlined,
            onTap: _toggleMyWatchlist,
          ),
        // Source binding. Takes the LEFT-entry focus node only when Play is
        // hidden (PikPak), so LEFT from an episode always lands on a live target.
        if (widget.onSelectSource != null)
          DetailSourcePill(
            count: count,
            focusNode: widget.showQuickPlay ? null : _leftEntryFocusNode,
            // A movie with Play hidden (PikPak-only) has no episode list to
            // auto-focus and no Play to autofocus — start the remote here.
            autofocus: widget.isTelevision && _isMovie && !widget.showQuickPlay,
            onTap: () async {
              await widget.onSelectSource!(_item);
              if (mounted) setState(() {});
            },
          ),
        // Debrify's own actions (bind source, Stremio TV, random episode,
        // season packs, local Continue Watching) — no tracker involved, so a
        // neutral button rather than a branded one.
        if (_tracker.appMenuOptions.isNotEmpty && widget.onTraktAction != null)
          DetailRoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onTap: () => _tracker.showAppActionsMenu(context),
          ),
        // Trakt — a branded pill that *carries* the live status (the status
        // chips that used to sit under the title are folded into it, so one
        // control both shows and changes the relationship).
        if (_tracker.traktOnlyMenuOptions.isNotEmpty && widget.onTraktAction != null)
          DetailTrackerPill(
            mark: TraktMark(size: 21, opacity: _tracker.traktTracked ? 1 : 0.55),
            brand: 'TRAKT',
            state: _tracker.traktPillLabel,
            rating: _tracker.traktStatus?.rating,
            accent: kTraktRed,
            tracked: _tracker.traktTracked,
            tooltip: 'Trakt options',
            onTap: () => _tracker.showTraktQuickActionsMenu(context),
          ),
        // Simkl's own pill — a separate button/sheet, not merged with Trakt's,
        // so nothing here touches the button above.
        if (_tracker.menuOptionsSimkl.isNotEmpty && widget.onSimklAction != null)
          DetailTrackerPill(
            mark: SimklMark(size: 21, opacity: _tracker.simklTracked ? 1 : 0.55),
            brand: 'SIMKL',
            state: _tracker.simklPillLabel,
            rating: _tracker.simklStatus?.rating,
            accent: kSimklCyan,
            tracked: _tracker.simklTracked,
            tooltip: 'Simkl options',
            onTap: () => _tracker.showSimklQuickActionsMenu(context),
          ),
        if (_tracker.menuOptionsMdblist.isNotEmpty && widget.onMdblistAction != null)
          DetailTrackerPill(
            mark: MdblistMark(size: 21, opacity: _tracker.mdblistTracked ? 1 : 0.55),
            brand: 'MDBLIST',
            state: _tracker.mdblistPillLabel,
            rating: _tracker.mdblistStatus?.rating,
            accent: kMdblistPurple,
            tracked: _tracker.mdblistTracked,
            tooltip: 'MDBList options',
            onTap: () => _tracker.showMdblistQuickActionsMenu(context),
          ),
      ],
    );
  }

  // ── Bodies ────────────────────────────────────────────────────────────────

  /// [contentBuilder] non-null hands the arrangement to an alternate layout;
  /// the engine (loading, watch merge, enrichment, playback, options) is
  /// identical either way.
  Widget _buildEpisodesPanel({
    Widget Function(BuildContext, EpisodesPanelView)? contentBuilder,
  }) {
    return EpisodesPanel(
      key: _episodesPanelKey,
      contentBuilder: contentBuilder,
      show: widget.item,
      addon: widget.addon,
      initialSeason: widget.initialSeason,
      initialEpisode: widget.initialEpisode,
      isTelevision: widget.isTelevision,
      // Match the standalone `_openEpisodes` flow, which does NOT pass
      // showQuickPlay (defaults true) — episode tiles keep quick-play even for
      // PikPak-only. Only the hero Resume (≙ detail "Play") is PikPak-gated.
      showQuickPlay: true,
      isTraktSource: widget.isTraktSource,
      isMdblistSource: widget.isMdblistSource,
      // Sources / fallback-search render in-tab on the Search host, so tear
      // down every merged/detail route first — popUntil the route name because
      // a single pop would leave a *parent* merged screen (series A →
      // recommended series B → pick episode) underneath instead of returning
      // to Search (every merged/detail route shares kCatalogDetailRouteName).
      // Mirrors the standalone EpisodesScreen._popToHost.
      onItemSelected: widget.onItemSelected == null
          ? null
          : (selection) {
              _popToHost();
              widget.onItemSelected!(selection);
            },
      // Quick-play deliberately does NOT pop: the host pushes the player on
      // top of this screen (same as the hero Resume), so playback pops back to
      // the episode list here — didPopNext then refreshes the ticks.
      onQuickPlay: widget.onQuickPlay == null ? null : _quickPlayEpisode,
      boundSourceCount: widget.boundSourceCount,
      onSelectSource: widget.onSelectSource,
      showChrome: false,
      compact: true,
      // Null when neither Play nor the source pill exists (no holder for the
      // node) — the episode row then leaves LEFT to directional traversal
      // instead of swallowing it as a dead key.
      onFocusLeftEdge: (widget.showQuickPlay || widget.onSelectSource != null)
          ? () => _leftEntryFocusNode.requestFocus()
          : null,
      onBack: () => Navigator.of(context).maybePop(),
      // Direct-source mode (Xtream IPTV series) — pass-throughs.
      seasonsLoader: widget.seasonsLoader,
      onPlayEpisode: widget.onPlayEpisode == null ? null : _playDirectEpisode,
      watchProgressLoader: widget.watchProgressLoader,
      onNextEpisodeChanged: _onNextEpisodeChanged,
    );
  }

  /// Tear every merged/detail route (any drill-down depth) back down to the
  /// Search host, so a selection it renders in-tab isn't hidden behind them.
  void _popToHost() {
    Navigator.of(
      context,
    ).popUntil((r) => r.settings.name != kCatalogDetailRouteName);
  }

  /// Stacked layout — mobile only. Compact hero (with Play/Bind/More) → a
  /// "Details" opener for cast/ratings/parents/recs → episodes. Quick actions
  /// live behind the hero's More (⋮) button.
  Widget _buildStackedBody() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 16, 4),
            child: TextButton.icon(
              onPressed: _openDetailsSheet,
              icon: Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('Cast, ratings & more'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ),
        ),
        Expanded(child: _buildEpisodesPanel()),
      ],
    );
  }

  void _openDetailsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Quick actions already shown in the strip; the sheet holds the rest.
            children: _sideRailSections(),
          ),
        ),
      ),
    );
  }

  // ── Side-rail sections (shared by wide rail + narrow details sheet) ─────────

  /// The reference sections that live inline in the TV info column (awards,
  /// credits, cast, details, parents guide, more like this) — no quick actions,
  /// no summary (both already shown above in the info pane).
  List<Widget> _referenceSections() {
    return [
      const SizedBox(height: 20),
      ..._sideRailSections(includeSummary: false),
    ];
  }

  List<Widget> _sideRailSections({bool includeSummary = true}) {
    final item = _item;
    final extra = _imdbExtra;
    final sections = <Widget>[];

    final summary = (item.description?.isNotEmpty ?? false)
        ? item.description
        : extra?.plot;
    if (includeSummary && summary != null && summary.isNotEmpty) {
      sections
        ..add(_sectionLabel('Summary'))
        ..add(const SizedBox(height: 8))
        ..add(
          Text(
            summary,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // Awards (gold pill) — parity with the detail screen.
    final awardsLine = extra?.hasAwards == true ? extra!.awardsLine : null;
    if (awardsLine != null && awardsLine.isNotEmpty) {
      sections
        ..add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, size: 15, color: _gold),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    awardsLine,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // Credits (director / stars) — parity with the detail screen.
    final creditRows = <(String, String)>[];
    if (extra != null) {
      if (extra.director != null && extra.director!.isNotEmpty) {
        creditRows.add(('Director', extra.director!));
      }
      if (extra.stars.isNotEmpty) {
        creditRows.add(('Stars', extra.stars.take(4).join(', ')));
      }
    }
    if (creditRows.isNotEmpty) {
      sections
        ..add(_sectionLabel('Credits'))
        ..add(const SizedBox(height: 8))
        ..add(_kvBlock(creditRows))
        ..add(const SizedBox(height: 22));
    }

    // Details (country / language / studio / box office) — grouped with the
    // other non-focusable text ABOVE the focusable Cast/Recs/Parents-Guide, so
    // on TV it's revealed while scrolling down to those (never stranded below
    // the last focusable when e.g. Parents Guide is absent).
    final detailRows = <(String, String)>[];
    if (extra != null) {
      if (extra.countries.isNotEmpty) {
        detailRows.add(('Country', extra.countries.take(2).join(', ')));
      }
      if (extra.languages.isNotEmpty) {
        detailRows.add(('Language', extra.languages.take(3).join(', ')));
      }
      if (extra.productionCompany != null) {
        detailRows.add(('Studio', extra.productionCompany!));
      }
      if (extra.boxOffice != null) {
        detailRows.add(('Box Office', extra.boxOffice!));
      }
    }
    if (detailRows.isNotEmpty) {
      sections
        ..add(_sectionLabel('Details'))
        ..add(const SizedBox(height: 8))
        ..add(_kvBlock(detailRows))
        ..add(const SizedBox(height: 22));
    }

    // Cast / More Like This are capped so the rails can build EVERY card up
    // front (see [_focusRail]) without a wall of image fetches — DPAD needs
    // real widgets to walk onto, and a dozen tiny thumbs is plenty of content.
    final cast = (extra?.cast ?? const []).take(12).toList();
    if (cast.isNotEmpty) {
      sections
        ..add(_sectionLabel('Cast'))
        ..add(const SizedBox(height: 12))
        ..add(
          DetailScrollAnchor(
            active: widget.isTelevision,
            alignment: 0.35,
            child: SizedBox(
              height: 92,
              child: _focusRail(
                controller: _castRailScroll,
                gap: 14,
                cards: [for (final m in cast) _castTile(m)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    // More Like This — placed high (right after Cast) so it's an easy DPAD-down
    // reach, ahead of the long focusable Parents-Guide list.
    final recs = (_recommendations ?? const <StremioMeta>[]).take(10).toList();
    if (recs.isNotEmpty && widget.onRecommendationTap != null) {
      sections
        ..add(_sectionLabel('More Like This'))
        ..add(const SizedBox(height: 12))
        ..add(
          DetailScrollAnchor(
            active: widget.isTelevision,
            alignment: 0.5,
            child: SizedBox(
              height: 168,
              child: _focusRail(
                controller: _recommendationRailScroll,
                gap: 11,
                cards: [for (final r in recs) _recCard(r)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    final guide = _parentsGuide;
    if (guide != null && !guide.isEmpty) {
      sections
        ..add(_sectionLabel('Parents Guide'))
        ..add(const SizedBox(height: 12))
        ..add(
          ParentsGuideSection(
            guide: guide,
            tv: widget.isTelevision,
            dense: true,
            accent: _accent,
          ),
        );
    }

    return sections;
  }

  /// Horizontal DPAD rail (Cast / More Like This). Builds ALL cards in a plain
  /// scrollable Row — a lazy ListView only builds what's near the viewport, so
  /// DPAD-right at the build edge found no next card and the focus jumped clean
  /// out of the rail (into the episodes pane) mid-browse. With every card real,
  /// traversal walks the whole rail and the framework auto-scrolls each focused
  /// card into view. The first card traps LEFT as a dead stop; the last card's
  /// RIGHT crosses deterministically into the episodes pane in the series
  /// two-pane layout (dead stop otherwise) — RIGHT is the sanctioned pane
  /// crossing, so it should work from a rail end too.
  Widget _focusRail({
    required ScrollController controller,
    required List<Widget> cards,
    required double gap,
  }) {
    final crossRight = (!_isMovie && _wide) ? _focusEpisodesPane : null;
    return HorizontalMouseWheel(
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              DetailRailEdgeTrap(
                trapLeft: i == 0,
                trapRight: i == cards.length - 1,
                onTrapRight: crossRight,
                child: cards[i],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _castTile(CastMember m) => DetailCastTile(member: m, fallback: _glass2);

  Widget _recCard(StremioMeta rec) => DetailRecCard(
    rec: rec,
    fallback: _glass2,
    onTap: () => widget.onRecommendationTap?.call(rec),
  );

  Widget _sectionLabel(String s) => Text(
    s.toUpperCase(),
    style: TextStyle(
      color: Colors.white38,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
    ),
  );

  /// Label→value rows (Credits / Details), matching the detail screen's layout.
  Widget _kvBlock(List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  rows[i].$1,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _pill(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: _glass2,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _hair),
    ),
    child: Text(s, style: const TextStyle(fontSize: 12)),
  );

  Widget _circleButton(
    IconData icon,
    VoidCallback onTap, {
    String? tooltip,
    FocusNode? focusNode,
    DetailTheme? theme,
  }) {
    return DetailRoundIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      focusNode: focusNode,
      background: theme == null
          ? Colors.black.withValues(alpha: 0.35)
          : theme.ground.withValues(alpha: 0.55),
      theme: theme,
    );
  }
}
