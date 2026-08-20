import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_util.dart';
import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../models/playlist_view_mode.dart';
import '../services/analytics_service.dart';
import '../services/series_source_service.dart';
import '../services/app_route_observer.dart';
import '../services/debrify_image_cache.dart';
import '../services/imdb_enrichment_service.dart';
import '../services/imdb_parents_guide_service.dart';
import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';
import '../services/video_player_launcher.dart';
import '../services/imdb_trailer_service.dart';
import '../services/youtube_service.dart';
import '../widgets/detail/detail_layout_console.dart';
import '../widgets/detail/detail_layout_dossier.dart';
import '../widgets/detail/detail_layout_marquee.dart';
import '../widgets/detail/detail_layout_premium.dart';
import '../widgets/detail/detail_layout_showcase.dart';
import '../widgets/detail/detail_layout_stage.dart';
import '../widgets/detail/detail_style.dart';
import '../widgets/detail/detail_model.dart';
import '../theme/app_theme_scope.dart';
import '../theme/artwork_accent.dart';
import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/hero_trailer_backdrop.dart';
import '../widgets/episodes_panel.dart';
import '../widgets/horizontal_mouse_wheel.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/parents_guide_section.dart';
import '../widgets/movie_watched_badge.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/trakt/trakt_service.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import '../services/simkl/simkl_service.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../widgets/tracker_brand_marks.dart';
import 'episodes_screen.dart' show kCatalogDetailRouteName;
import 'settings/detail_page_style_page.dart' show effectiveDetailPageStyle;
import '../theme/app_theme_controller.dart';
import '../theme/theme_core_resolver.dart';
import '../theme/theme_overrides.dart';
import '../theme/shipped_themes.dart' show effectiveDetailTheme;
import '../utils/artwork_url.dart';

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

  /// Primary play action. Series: resume-and-play (last-played → S01E01).
  /// Movie: play the movie. Mirrors the detail screen's "Play".
  final Future<void> Function() onResume;

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

  /// Submits a 1–10 rating straight from the tracker sheet's inline strip.
  /// When null the strip falls back to firing the sheet's `rate` action, which
  /// opens that tracker's rating dialog instead.
  final Future<void> Function(int rating)? onTraktRate;
  final Future<void> Function(int rating)? onSimklRate;

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
    this.onItemSelected,
    this.onQuickPlay,
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
    this.onTraktRate,
    this.onSimklRate,
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
  static const Color _gold = Color(0xFFF5B942);
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

  /// Trailer YouTube ID, resolved from Cinemeta meta. Null until loaded / when
  /// the title has no trailer — the Trailer button only shows once this is set.
  String? _trailerYtId;

  /// Guards against a double-launch while a trailer's streams resolve.
  bool _trailerLoading = false;

  /// One playback launch at a time for the whole merged page. Every visual
  /// theme delegates its primary action here, and the hosted episode panel is
  /// wrapped by the same gate below. The modal resolving route usually absorbs
  /// a second tap, but it is presentation rather than synchronization: two OK
  /// events can otherwise enter the async resume/source resolution together.
  bool _playLaunching = false;

  /// Whether OTT-style trailer autoplay behind the backdrop is on (settings).
  /// Always false on Android TV — the Home hero owns ambient trailers there.
  bool _trailerAutoplayEnabled = false;

  /// Ambient loop volume (0–100) from settings; 0 when the sound toggle is off.
  /// Read alongside [_trailerAutoplayEnabled] and applied when the backdrop
  /// opens its engine (which can't happen before the streams resolve), so it's
  /// always in place by then. Promoting to fullscreen still plays at full
  /// volume — the backdrop handles that, muted ambient or not.
  double _trailerAmbientVolume = 70;

  /// Resolved trailer streams, pre-fetched for the ambient backdrop.
  YoutubeResolvedStreams? _trailerStreams;

  /// Handle to the backdrop so the Trailer button can promote the *same* player
  /// to fullscreen in place (seamless — no second decoder, no re-buffer).
  final GlobalKey<HeroTrailerBackdropState> _backdropKey = GlobalKey();

  /// Whether the trailer is currently brought forward to fullscreen.
  bool _trailerForeground = false;

  /// The ambient backdrop trailer is live with frames on screen — the Trailer
  /// button reads "Watch Trailer" to say "it's playing, tap to view".
  bool _trailerAmbientPlaying = false;

  /// Autoplay pipeline in flight (stream resolve → buffer → first frame) — the
  /// Trailer button shows a spinner.
  bool _trailerResolving = false;

  /// Scrolls the left info column. Focus-anchored (see [_ScrollAnchor]) so that
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

  /// The user's live Trakt relationship to this title (watchlist / collection /
  /// watched / rating). Null until [traktStatusLoader] resolves — the menu then
  /// falls back to the add-only [traktMenuOptions]. Re-read after a quick action
  /// and when the player pops back.
  TraktTitleStatus? _traktStatus;

  /// Whether the status loaders have answered at least once. A null status
  /// means "untracked" only *after* this flips — before it, the answer simply
  /// isn't in yet, and the pill must not claim the title is untracked.
  bool _traktStatusResolved = false;
  bool _simklStatusResolved = false;

  /// The quick-actions strip to render: rebuilt against [_traktStatus] when a
  /// builder was supplied, else the static list passed in.
  List<TraktMenuOption> get _menuOptions =>
      widget.traktMenuBuilder?.call(_traktStatus) ?? widget.traktMenuOptions;

  /// Debrify's own actions. They arrive inside the Trakt option list (that list
  /// has always carried both), but none of them touch Trakt — so they get the
  /// neutral "More" sheet and the Trakt sheet stays purely Trakt. Being app
  /// actions they're also available when Trakt is disconnected, which the old
  /// single-menu arrangement only managed by keeping an always-present Trakt
  /// button.
  static const Set<TraktItemMenuAction> _appOwnedActions = {
    TraktItemMenuAction.selectSource,
    TraktItemMenuAction.addToStremioTv,
    TraktItemMenuAction.playRandomEpisode,
    TraktItemMenuAction.searchPacks,
    TraktItemMenuAction.removeFromPlayback,
  };

  List<TraktMenuOption> get _appMenuOptions => [
    for (final o in _menuOptions)
      if (_appOwnedActions.contains(o.action)) o,
  ];

  List<TraktMenuOption> get _traktOnlyMenuOptions => [
    for (final o in _menuOptions)
      if (!_appOwnedActions.contains(o.action)) o,
  ];

  /// The user's live Simkl relationship to this title. Null until
  /// [simklStatusLoader] resolves — mirrors [_traktStatus] one-for-one.
  SimklTitleStatus? _simklStatus;
  bool _localMovieFinished = false;
  bool _showcaseOpeningDataReady = false;

  /// Debrify's local watchlist is independent of tracker connectivity.
  bool _inMyWatchlist = false;
  bool get _supportsMyWatchlist =>
      StorageService.supportsMyWatchlistItem(_item);
  StremioMeta get _myWatchlistItem => StorageService.withMyWatchlistSource(
    _item,
    widget.item.sourceAddon ?? widget.addon,
  );

  /// The Simkl quick-actions strip to render: rebuilt against [_simklStatus]
  /// when a builder was supplied, else the static list passed in.
  List<SimklMenuOption> get _menuOptionsSimkl =>
      widget.simklMenuBuilder?.call(_simklStatus) ?? widget.simklMenuOptions;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('series_detail');
    MainPageBridge.addPlaybackReturnListener(_onPlaybackReturned);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadShowcaseOpeningData();
      _loadTrailer();
      _loadAccent();
      _loadResumeInfo();
      _loadTraktStatus();
      _loadSimklStatus();
      _loadLocalMovieFinished();
      _loadMyWatchlistState();
    });
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

  void _playPrimary() {
    unawaited(_guardPlay(widget.onResume));
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
    _loadResumeInfo();
    // Watched state (and thus the resume label / badges) may have changed while
    // away — re-read the Trakt status too.
    _loadTraktStatus();
    _loadSimklStatus();
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
    final saved = await StorageService.isInMyWatchlist(_myWatchlistItem);
    if (!mounted || saved == _inMyWatchlist) return;
    setState(() => _inMyWatchlist = saved);
  }

  Future<void> _toggleMyWatchlist() async {
    if (!_supportsMyWatchlist) return;
    final next = !_inMyWatchlist;
    setState(() => _inMyWatchlist = next);
    try {
      await StorageService.setMyWatchlistItem(_myWatchlistItem, next);
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

  /// Resolve the user's Trakt relationship to this title so the menu shows
  /// Add ↔ Remove toggles and the hero can badge Watchlist/Collection/Watched/
  /// rating. Silent on failure — the menu just stays add-only.
  Future<void> _loadTraktStatus() async {
    final loader = widget.traktStatusLoader;
    if (loader == null) return;
    try {
      final status = (await loader())?.preserveWatchedFrom(_traktStatus);
      if (!mounted || status == null) return;
      setState(() => _traktStatus = status);
    } catch (_) {
    } finally {
      // Resolved either way: a failed read is still an answered question as
      // far as the pill is concerned — it stops saying "Checking…" and falls
      // back to the untracked form rather than spinning forever.
      if (mounted && !_traktStatusResolved) {
        setState(() => _traktStatusResolved = true);
      }
    }
  }

  /// Resolve the user's Simkl relationship to this title — mirrors
  /// [_loadTraktStatus] exactly.
  Future<void> _loadSimklStatus() async {
    final loader = widget.simklStatusLoader;
    if (loader == null) return;
    try {
      final status = await loader();
      if (!mounted || status == null) return;
      setState(() => _simklStatus = status);
    } catch (_) {
    } finally {
      if (mounted && !_simklStatusResolved) {
        setState(() => _simklStatusResolved = true);
      }
    }
  }

  Future<void> _loadLocalMovieFinished() async {
    if (!_isMovie) return;
    final imdbId =
        _item.effectiveImdbId ?? (_item.id.startsWith('tt') ? _item.id : null);
    if (imdbId == null || imdbId.isEmpty) return;
    final finished = await StorageService.isMovieFinished(imdbId);
    if (mounted && finished != _localMovieFinished) {
      setState(() => _localMovieFinished = finished);
    }
  }

  Future<void> _loadResumeInfo() async {
    final loader = widget.resumeInfoLoader;
    if (loader == null) return;
    try {
      final info = await loader();
      if (!mounted) return;
      setState(() {
        _resumeLoaded = true;
        _resumeStarted = info.started;
        _resumeSeason = info.season;
        _resumeEpisode = info.episode;
      });
    } catch (_) {
      // Non-critical — leave the static label.
    }
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static Play/Resume label until the resume state resolves.
  String get _primaryLabel {
    // Completion is available independently of the optional resume loader.
    // Keep the rewatch affordance visible for movie routes that omit one.
    if (!_resumeLoaded) {
      if (_isMovie &&
          (_localMovieFinished || _simklStatus?.currentStatus == 'completed')) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Resume';
    }
    if (!_resumeStarted) {
      // A movie already finished on Simkl (status `completed`) has no resume
      // session; its Play un-marks it watched so the rewatch re-enters
      // Continue Watching — surface that intent as "Rewatch".
      if (_isMovie &&
          (_localMovieFinished || _simklStatus?.currentStatus == 'completed')) {
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

  /// Resolve the trailer's YouTube ID from Cinemeta. Runs independently of
  /// [_loadEnrichedMeta] (which short-circuits for already-rich items and so
  /// can't be relied on to carry the trailer). The `fetchMetaDetails` result is
  /// cached in [StremioService], so this shares that fetch rather than doubling
  /// network. Silent on failure — the button simply never appears.
  Future<void> _loadTrailer() async {
    // Resolve the trailer id: prefer what the item arrived with, else ask the
    // metadata addon (Cinemeta).
    String? ytId = widget.item.trailerYtId;
    if (ytId == null || ytId.isEmpty) {
      final enrich = widget.metaEnricher;
      final imdbId = widget.item.effectiveImdbId;
      if (enrich != null && imdbId != null) {
        try {
          final full = await enrich(imdbId, widget.item.type);
          ytId = full?.trailerYtId;
        } catch (_) {}
      }
    }
    if (ytId == null || ytId.isEmpty || !mounted) return;
    setState(() => _trailerYtId = ytId);

    // OTT autoplay: honour the setting, then pre-resolve the stream (also reused
    // by the Trailer button). Silent on failure — the poster simply stays.
    final autoplay = await StorageService.getDetailTrailerAutoplayEnabled();
    // The ambient sound pair is shared with the TV hero (one live surface per
    // platform), so off-TV it governs this backdrop. Read unconditionally so
    // all three land in the one setState below — [autoplay] is false on TV
    // anyway, and these are two prefs reads.
    final soundOn = await StorageService.getAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.detail,
    );
    final volume = await StorageService.getAmbientTrailerVolume(
      AmbientTrailerSurface.detail,
    );
    if (!mounted) return;
    // The backdrop refuses to autoplay under OS reduced-motion — skip the whole
    // pipeline (no resolve, no spinner) rather than spin forever waiting for a
    // player that will never start.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final willAutoplay = autoplay && !reduceMotion;
    setState(() {
      _trailerAutoplayEnabled = autoplay;
      _trailerAmbientVolume = soundOn ? volume.toDouble() : 0;
      // Spinner from here until the backdrop reports first frames (or fails).
      _trailerResolving = willAutoplay;
    });
    if (!willAutoplay) return;
    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }
    // Backup source: IMDb's own trailer MP4s, for when YouTube resolution is
    // blocked (regional client kills) — the backdrop still gets to move.
    if (streams == null || !(streams.playUrl?.isNotEmpty ?? false)) {
      final imdbId = _item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }
    if (!mounted) return;
    final playable = streams?.playUrl?.isNotEmpty ?? false;
    setState(() {
      _trailerStreams = streams;
      // No playable stream → the backdrop never starts, so stop the spinner
      // here; on success the backdrop's onPlayingChanged(true) clears it once
      // frames actually flow.
      if (!playable) _trailerResolving = false;
    });
    if (!playable) return;
    // Safety net: a stream that opens but never renders a first frame would
    // otherwise leave the spinner up forever.
    Future.delayed(const Duration(seconds: 25), () {
      if (mounted && _trailerResolving) {
        setState(() => _trailerResolving = false);
      }
    });
  }

  void _exitTrailerForeground() {
    if (!_trailerForeground) return;
    setState(() => _trailerForeground = false);
    // TV: the page content was focus-excluded while the trailer was fullscreen,
    // so nothing holds focus now — re-anchor the remote on the primary action.
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The left-entry node only has a holder when Play or the source pill is
        // present; if neither is (edge config), fall back to traversal so the
        // remote isn't stranded rather than no-op on an unattached node.
        if (detailNodeMounted(_leftEntryFocusNode)) {
          _leftEntryFocusNode.requestFocus();
        } else {
          FocusScope.of(context).nextFocus();
        }
      });
    }
  }

  /// Trailer button. Seamless path: if the ambient backdrop trailer is already
  /// playing, bring that *same* player forward (unmute + controls) in place — no
  /// second decoder, no re-buffer. Fallback path (autoplay off / not resolved /
  /// reduced motion): resolve fresh and launch the standalone player as before.
  Future<void> _playTrailer() async {
    if (_backdropKey.currentState?.canPromote ?? false) {
      setState(() => _trailerForeground = true);
      return;
    }

    final ytId = _trailerYtId;
    if (ytId == null || _trailerLoading) return;

    // Always resolve fresh on tap. The autoplay-prefetched [_trailerStreams] is
    // deliberately NOT reused here: googlevideo URLs carry an `expire` param and
    // go dead after a few hours, so a page left open would hand the player a
    // stale URL. Re-resolving costs one request and keeps playback reliable.
    setState(() => _trailerLoading = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading trailer…'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }
    // Same backup as the ambient path: a blocked YouTube must not reduce the
    // Trailer button to a "Couldn't load trailer" snackbar when IMDb hosts
    // the same trailer as a plain MP4.
    if (streams == null || !(streams.playUrl?.isNotEmpty ?? false)) {
      final imdbId = _item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _trailerLoading = false);

    final playUrl = streams?.playUrl;
    if (playUrl == null || playUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Couldn\'t load trailer')));
      return;
    }

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: playUrl,
        audioUrl: streams?.audioUrl,
        fallbackUrl: streams?.downloadUrl,
        title: '${_item.name} — Trailer',
        viewMode: PlaylistViewMode.sorted,
      ),
      // Watching the trailer must not suppress the ambient trailer backdrop.
      isTrailer: true,
    );
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
      _trailerAmbientPlaying &&
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
      canPop: !_trailerForeground,
      onPopInvoked: (didPop) {
        if (!didPop) _exitTrailerForeground();
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
                key: _backdropKey,
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
                videoUrl: _trailerAutoplayEnabled && !_bodyDeep
                    ? _trailerStreams?.playUrl
                    : null,
                audioUrl: _trailerAutoplayEnabled && !_bodyDeep
                    ? _trailerStreams?.audioUrl
                    : null,
                // The still is meant to be SEEN first — that is the shape of
                // the reference, poster then motion. Off-TV keeps the shorter
                // default it has always had.
                startDelay: widget.isTelevision
                    ? const Duration(milliseconds: 3200)
                    : const Duration(milliseconds: 1400),
                // Suspend at the Play press, before source/resume resolution.
                // The pipeline loader is a PopupRoute rather than a PageRoute,
                // so RouteAware.didPushNext cannot provide this lifecycle beat.
                enabled: _trailerAutoplayEnabled && !_playLaunching,
                ambientVolume: _trailerAmbientVolume,
                foreground: _trailerForeground,
                onRequestClose: _exitTrailerForeground,
                onPlayingChanged: (playing) {
                  if (!mounted) return;
                  setState(() {
                    _trailerAmbientPlaying = playing;
                    _trailerResolving = false;
                  });
                },
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
                excluding: _trailerForeground,
                child: IgnorePointer(
                  ignoring: _trailerForeground,
                  child: AnimatedOpacity(
                    opacity: _trailerForeground ? 0 : 1,
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
                            !_trailerForeground &&
                            !_trailerAmbientPlaying)
                          Positioned.fill(
                            child: _AmbientStill(
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
            if (_trailerAmbientPlaying && !_trailerForeground)
              Positioned(
                left: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(widget.isTelevision ? 20 : 12),
                    child: _TrailerPlayingChip(
                      onTap: _playTrailer,
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
      sourceCount: widget.boundSourceCount?.call(_item) ?? 0,
      boundSources: _boundSources,
      hasTrailer: _trailerYtId != null,
      trailerBusy: _trailerResolving || _trailerLoading,
      trailerPlaying: _trailerAmbientPlaying,
      hasTrakt: _traktOnlyMenuOptions.isNotEmpty,
      traktTracked: _traktTracked,
      traktLabel: _traktPillLabel,
      traktRating: _traktStatus?.rating,
      hasSimkl: _menuOptionsSimkl.isNotEmpty,
      simklTracked: _simklTracked,
      simklLabel: _simklPillLabel,
      simklRating: _simklStatus?.rating,
      showPrimary: widget.showQuickPlay,
      onPrimary: _playPrimary,
      // A movie browses the full source list the host supplies; a series
      // browses season packs — the same search the More menu's "Search
      // season packs" row opens, promoted to a first-class button. Gated on
      // that row actually being in the menu so the button never mounts for a
      // host that didn't offer the action.
      onBrowse: _isMovie
          ? widget.onBrowse
          : (widget.onTraktAction != null &&
                _appMenuOptions.any(
                  (o) => o.action == TraktItemMenuAction.searchPacks,
                ))
          ? () => widget.onTraktAction!(TraktItemMenuAction.searchPacks)
          : null,
      onTrailer: _playTrailer,
      onSelectSource: widget.onSelectSource == null
          ? null
          : () async {
              await widget.onSelectSource!(_item);
              if (mounted) setState(() {});
            },
      onAppMenu: (_appMenuOptions.isNotEmpty && widget.onTraktAction != null)
          ? _showAppActionsMenu
          : null,
      onTraktMenu: widget.onTraktAction != null ? _showQuickActionsMenu : null,
      onSimklMenu: widget.onSimklAction != null
          ? _showSimklQuickActionsMenu
          : null,
      inMyWatchlist: _inMyWatchlist,
      onToggleMyWatchlist: _supportsMyWatchlist ? _toggleMyWatchlist : null,
      // Both trackers behind one affordance, for a layout whose action row has
      // no room for two branded pills. Whichever single service is configured
      // opens directly; with both, the app menu is the chooser that already
      // lists them.
      // Null when neither service is configured, or the layout mounts a `+`
      // that focuses and does nothing. There is no combined sheet to open —
      // `_showAppActionsMenu` is the APP-action list, not a tracker chooser —
      // so with both configured this opens Trakt's, and Simkl stays reachable
      // through the More button beside it.
      // Gated on whether a tracker is actually CONNECTED, not on whether the
      // host passed a callback — the home screen always passes the Trakt one,
      // so a callback test mounts a `+` that focuses and does nothing for
      // anyone who has not connected Trakt.
      //
      // With both connected this opens Trakt's sheet and Simkl stays reachable
      // from the More button beside it; there is no combined sheet to open,
      // and `_showAppActionsMenu` is the APP-action list, not a chooser.
      onTrackers:
          (_traktOnlyMenuOptions.isNotEmpty && widget.onTraktAction != null)
          ? _showQuickActionsMenu
          : (_menuOptionsSimkl.isNotEmpty && widget.onSimklAction != null
                ? _showSimklQuickActionsMenu
                : null),
      // Only when Trakt already took the first slot; otherwise Simkl IS the
      // first slot above and this would mount the same sheet twice.
      onTrackersSecondary:
          (_traktOnlyMenuOptions.isNotEmpty &&
              widget.onTraktAction != null &&
              _menuOptionsSimkl.isNotEmpty &&
              widget.onSimklAction != null)
          ? _showSimklQuickActionsMenu
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
    Widget themed(Widget body) => DetailThemeScope(
      theme: _theme,
      child: DetailAtmosphere(child: body),
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

    // No entrance stagger on TV: each _StaggerReveal animates Opacity (a
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
          _StaggerReveal(
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
          _StaggerReveal(
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
          _StaggerReveal(
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
            _StaggerReveal(
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
          _StaggerReveal(
            key: const ValueKey('rev-actions'),
            delayMs: 220,
            enabled: animate,
            child: _ScrollAnchor(
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
          _StaggerReveal(
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
          _StaggerReveal(
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
          _StaggerReveal(
            key: const ValueKey('rev-h-meta'),
            delayMs: 110,
            enabled: animate,
            child: _buildMetaBar(year, extra, rating),
          ),
          // Tracker state lives in the action-row pills (see the info pane).
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StaggerReveal(
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
          _StaggerReveal(
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

  /// Whether Trakt holds any relationship to this title. Drives the pill's
  /// tinted (tracked) vs. outline (untracked) form.
  bool get _traktTracked {
    final s = _traktStatus;
    return s != null &&
        (s.inWatchlist ||
            s.inCollection ||
            s.titleWatched == true ||
            s.rating != null);
  }

  bool get _simklTracked =>
      _simklStatus?.currentStatus != null || _simklStatus?.rating != null;

  /// The live Trakt state, compressed to fit inside the pill. Trakt allows
  /// several relationships at once, so they're joined with "·" and capped at
  /// two — the rating rides in the pill's own compartment, not here.
  ///
  /// While the loader is still out this reads "Checking…" rather than "Not
  /// tracked": the row keeps its geometry either way, and asserting the title
  /// *isn't* on your watchlist when it is — for however long the call takes —
  /// is worse than admitting we don't know yet.
  String get _traktPillLabel {
    final s = _traktStatus;
    if (s == null &&
        !_traktStatusResolved &&
        widget.traktStatusLoader != null) {
      return 'Checking…';
    }
    if (s == null) return 'Not tracked';
    final parts = <String>[
      if (s.inWatchlist) 'Watchlist',
      if (s.inCollection) 'Collected',
      if (s.titleWatched == true) 'Watched',
    ];
    if (parts.isEmpty) {
      if (s.rating != null) return 'Rated';
      return s.titleWatched == null ? 'Status unavailable' : 'Not tracked';
    }
    return parts.take(2).join(' · ');
  }

  /// Simkl is single-state by definition, so its pill never needs to join
  /// anything — it's the one watchlist status, or nothing.
  String get _simklPillLabel {
    final status = _simklStatus?.currentStatus;
    if (status != null) return _simklStatusLabel(status);
    if (_simklStatus?.rating != null) return 'Rated';
    if (!_simklStatusResolved && widget.simklStatusLoader != null) {
      return 'Checking…';
    }
    return 'Not tracked';
  }

  static String _simklStatusLabel(String status) {
    switch (status) {
      case 'plantowatch':
        return 'Plan to Watch';
      case 'watching':
        return 'Watching';
      case 'hold':
        return 'On Hold';
      case 'completed':
        return 'Completed';
      case 'dropped':
        return 'Dropped';
      default:
        return status;
    }
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
          _PrimaryButton(
            label: _primaryLabel,
            icon: Icons.play_arrow_rounded,
            onTap: _playPrimary,
            focusNode: _leftEntryFocusNode,
            autofocus: widget.isTelevision && _isMovie,
            glow: _accent,
          ),
        // Trailer — sits right after Play. Only when Cinemeta gave us a YouTube
        // trailer id. Reflects the ambient backdrop's state: spinner while the
        // trailer loads, "Watch Trailer" once it's playing (tap = fullscreen),
        // plain "Trailer" otherwise (tap = resolve & play).
        if (_trailerYtId != null)
          _GhostButton(
            label: _trailerAmbientPlaying ? 'Watch Trailer' : 'Trailer',
            icon: _trailerAmbientPlaying
                ? Icons.play_circle_outline_rounded
                : Icons.movie_outlined,
            busy: _trailerResolving || _trailerLoading,
            onTap: _playTrailer,
          ),
        // Movie: a Sources (manual list) button — the episode list is the
        // picker for series, so this is movie-only.
        if (_isMovie && widget.onBrowse != null)
          _GhostButton(
            label: 'Sources',
            icon: Icons.layers_rounded,
            onTap: widget.onBrowse!,
          ),
        if (_supportsMyWatchlist)
          _GhostButton(
            label: _inMyWatchlist ? 'In My Watchlist' : 'My Watchlist',
            icon: _inMyWatchlist
                ? Icons.bookmark_rounded
                : Icons.bookmark_add_outlined,
            onTap: _toggleMyWatchlist,
          ),
        // Source binding. Takes the LEFT-entry focus node only when Play is
        // hidden (PikPak), so LEFT from an episode always lands on a live target.
        if (widget.onSelectSource != null)
          _SourcePill(
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
        if (_appMenuOptions.isNotEmpty && widget.onTraktAction != null)
          _RoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onTap: _showAppActionsMenu,
          ),
        // Trakt — a branded pill that *carries* the live status (the status
        // chips that used to sit under the title are folded into it, so one
        // control both shows and changes the relationship).
        if (_traktOnlyMenuOptions.isNotEmpty && widget.onTraktAction != null)
          _TrackerPill(
            mark: TraktMark(size: 21, opacity: _traktTracked ? 1 : 0.55),
            brand: 'TRAKT',
            state: _traktPillLabel,
            rating: _traktStatus?.rating,
            accent: kTraktRed,
            tracked: _traktTracked,
            tooltip: 'Trakt options',
            onTap: _showQuickActionsMenu,
          ),
        // Simkl's own pill — a separate button/sheet, not merged with Trakt's,
        // so nothing here touches the button above.
        if (_menuOptionsSimkl.isNotEmpty && widget.onSimklAction != null)
          _TrackerPill(
            mark: SimklMark(size: 21, opacity: _simklTracked ? 1 : 0.55),
            brand: 'SIMKL',
            state: _simklPillLabel,
            rating: _simklStatus?.rating,
            accent: kSimklCyan,
            tracked: _simklTracked,
            tooltip: 'Simkl options',
            onTap: _showSimklQuickActionsMenu,
          ),
      ],
    );
  }

  /// Human-readable description of each quick action, shown in the More menu.
  static String _descriptionFor(TraktItemMenuAction a) {
    switch (a) {
      case TraktItemMenuAction.selectSource:
        return 'Pin a specific torrent or file as this title\'s source so every '
            'play uses it — no re-searching each time. Change or clear it here.';
      case TraktItemMenuAction.addToStremioTv:
        return 'Add this to your Stremio TV channel so it plays in your '
            'always-on rotation alongside your other picks.';
      case TraktItemMenuAction.playRandomEpisode:
        return 'Skip the browsing and jump straight into a random episode from '
            'this series — handy for background or comfort watching.';
      case TraktItemMenuAction.searchPacks:
        return 'Open a search for full-season and complete-series packs, then '
            'do whatever you want with a result — play it, download it, and more.';
      case TraktItemMenuAction.addToWatchlist:
        return 'Save this to your Trakt watchlist so you can find it later, '
            'synced across every device signed into your account.';
      case TraktItemMenuAction.removeFromWatchlist:
        return 'Take this off your Trakt watchlist — it won\'t appear in your '
            '"to watch" list anymore.';
      case TraktItemMenuAction.addToCollection:
        return 'Mark this as part of your Trakt collection — your library of '
            'everything you own or keep track of.';
      case TraktItemMenuAction.removeFromCollection:
        return 'Remove this from your Trakt collection.';
      case TraktItemMenuAction.markWatched:
        return 'Mark every episode of this title as watched on Trakt and sync '
            'that history across all your devices.';
      case TraktItemMenuAction.markUnwatched:
        return 'Clear this title from your Trakt history so it counts as '
            'unwatched again and can resurface in "up next".';
      case TraktItemMenuAction.rate:
        return 'Give this a 1–10 rating on Trakt. Your ratings sync everywhere '
            'and help shape your recommendations.';
      case TraktItemMenuAction.removeRating:
        return 'Remove the rating you previously gave this on Trakt.';
      case TraktItemMenuAction.addToList:
        return 'Add this to one of your custom Trakt lists — like "Weekend", '
            '"With friends" or anything you\'ve made.';
      case TraktItemMenuAction.removeFromList:
        return 'Remove this from one of your custom Trakt lists.';
      case TraktItemMenuAction.removeFromPlayback:
        return 'Remove this from Continue Watching so it stops showing on your '
            'home rows and resume list.';
      case TraktItemMenuAction.removeFromTraktPlayback:
        return 'Delete this title\'s playback progress (and watch history) on '
            'Trakt so it leaves the Trakt Continue Watching rows.';
    }
  }

  /// Human-readable description of each Simkl quick action, shown in its
  /// own More menu — mirrors [_descriptionFor].
  static String _descriptionForSimkl(SimklItemMenuAction a) {
    switch (a) {
      case SimklItemMenuAction.moveToPlanToWatch:
        return 'Move this to your Simkl "Plan to Watch" list — a personal '
            'watch queue synced across every device signed into your account.';
      case SimklItemMenuAction.moveToWatching:
        return 'Mark this as currently watching on Simkl, without changing '
            'any episode watched state.';
      case SimklItemMenuAction.moveToOnHold:
        return 'Pause this on Simkl — keeps it out of Plan to Watch and '
            'Watching until you\'re ready to pick it back up.';
      case SimklItemMenuAction.moveToCompleted:
        return 'Mark this completed on Simkl and sync that history across '
            'all your devices.';
      case SimklItemMenuAction.moveToDropped:
        return 'Mark this dropped on Simkl so it stops showing up as '
            'something you\'re meaning to finish.';
      case SimklItemMenuAction.removeFromContinueWatching:
        return 'Take this off your Simkl Continue Watching rows. A movie just '
            'clears its paused position; a series is moved to On Hold so its '
            'next episode doesn\'t re-surface as an "up next" card.';
      case SimklItemMenuAction.rate:
        return 'Give this a 1–10 rating on Simkl.';
      case SimklItemMenuAction.removeRating:
        return 'Remove the rating you previously gave this on Simkl.';
    }
  }

  /// Debrify's own actions, in a plain labelled list. Closes on selection —
  /// each of these leaves the sheet anyway (a picker, a search, playback).
  void _showAppActionsMenu() {
    final options = _appMenuOptions;
    if (options.isEmpty || widget.onTraktAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      // Same standard sheet chrome as the per-episode ⋮ menu.
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _QuickActionsMenu(
        title: _item.name,
        options: options,
        isTelevision: widget.isTelevision,
        onSelected: (action) async {
          Navigator.of(sheetCtx).pop();
          await widget.onTraktAction?.call(action);
          // Binding a source changes the pill's count, and "Remove from
          // Continue Watching" changes the resume label.
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// The Trakt sheet: watchlist / collection / watched as switches, plus an
  /// inline rating strip and the list actions.
  ///
  /// Unlike the app sheet this one stays open — a tracker sheet is somewhere
  /// you set several things at once, and each row re-reads the live status so
  /// the switches show the truth rather than an optimistic guess.
  void _showQuickActionsMenu() {
    if (_traktOnlyMenuOptions.isEmpty || widget.onTraktAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _TraktSheet(
        title: _item.name,
        isTelevision: widget.isTelevision,
        status: _traktStatus,
        optionsFor: (status) => [
          for (final o
              in widget.traktMenuBuilder?.call(status) ??
                  widget.traktMenuOptions)
            if (!_appOwnedActions.contains(o.action)) o,
        ],
        onAction: (action) async {
          await widget.onTraktAction?.call(action);
        },
        onRate: widget.onTraktRate,
        statusLoader: widget.traktStatusLoader,
        // Keep the pill in sync with whatever the sheet did while it was open.
        onChanged: (status) {
          if (mounted) {
            setState(() {
              _traktStatus = status;
              _traktStatusResolved = true;
            });
          }
        },
      ),
    );
  }

  /// Simkl's own sheet — mirrors [_showQuickActionsMenu], but Simkl's five
  /// statuses are mutually exclusive, so they render as one picker instead of
  /// a list of "Move to X" commands.
  void _showSimklQuickActionsMenu() {
    if (_menuOptionsSimkl.isEmpty || widget.onSimklAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _SimklSheet(
        title: _item.name,
        isTelevision: widget.isTelevision,
        status: _simklStatus,
        optionsFor: (status) =>
            widget.simklMenuBuilder?.call(status) ?? widget.simklMenuOptions,
        onAction: (action) async {
          await widget.onSimklAction?.call(action);
        },
        onRate: widget.onSimklRate,
        statusLoader: widget.simklStatusLoader,
        onChanged: (status) {
          if (mounted) {
            setState(() {
              _simklStatus = status;
              _simklStatusResolved = true;
            });
          }
        },
      ),
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
          _ScrollAnchor(
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
          _ScrollAnchor(
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
              _RailEdgeTrap(
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

  Widget _castTile(CastMember m) => _CastTile(member: m, fallback: _glass2);

  Widget _recCard(StremioMeta rec) => _RecCard(
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
    return _RoundIconButton(
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

// ── Small presentational widgets ───────────────────────────────────────────

/// One-shot entrance for a hero-block item: after [delayMs], fades up from
/// transparent while rising 12px, so the detail header assembles itself around
/// the shared-element poster flight instead of popping in fully formed.
///
/// Cheap and TV-safe: a single 340ms opacity+translate on a small widget, run
/// once on mount (the controller never resets, so metadata-load rebuilds don't
/// replay it). [enabled] is false under OS reduced-motion — the child shows
/// immediately with no controller. Late-arriving sections (their own first
/// mount happens when enrichment lands) simply fade in on arrival.
class _StaggerReveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final bool enabled;

  const _StaggerReveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.enabled = true,
  });

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<_StaggerReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller?.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Gold DPAD focus ring — an in-bounds *foreground* border, exactly like the
/// episode rows in the right pane (and the same [HomeTheme.focusGold] hue, so
/// the cursor doesn't shift color crossing panes). Every interactive element on
/// this screen wraps itself in one — the default InkWell focus overlay is
/// invisible on both the white Play pill and dark glass surfaces, which made
/// the remote cursor untrackable on TV.
///
/// Deliberately NOT a shadow ring: spread shadows paint a *filled* rect behind
/// the child (they bleed through translucent glass surfaces as a solid gold
/// fill), and they paint outside bounds (forcing rails to un-clip and leak
/// scrolled-out tiles). A foreground border stays crisp on any surface, keeps
/// the glass translucency, and never needs `Clip.none`.
class _FocusHalo extends StatelessWidget {
  final bool focused;
  final BorderRadius? radius; // null → circle
  final Widget child;

  /// Null keeps Classic's gold.
  final Color? ringColor;

  const _FocusHalo({
    required this.focused,
    required this.child,
    this.radius,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // Snap on TV (house focus idiom): a 140ms ring fade per DPAD move makes
      // held-key surfing repaint every element in flight on the weak GPU.
      duration: PlatformUtil.isTelevision
          ? Duration.zero
          : const Duration(milliseconds: 140),
      foregroundDecoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: focused
            ? Border.all(color: ringColor ?? HomeTheme.focusGold, width: 2.5)
            : null,
      ),
      child: child,
    );
  }
}

/// Wraps a rail's end cards: consumes LEFT on the first / RIGHT on the last so
/// the DPAD cursor stops at the rail's edge instead of escaping to whatever is
/// geometrically nearest (the episodes pane, the back button). A non-focusable
/// ancestor node sees the key on its way up from the focused card, before the
/// app-level shortcuts turn it into a traversal move.
class _RailEdgeTrap extends StatelessWidget {
  final bool trapLeft;
  final bool trapRight;
  final Widget child;

  /// When set, RIGHT on the last card invokes this (pane crossing) instead of
  /// dead-stopping.
  final VoidCallback? onTrapRight;

  const _RailEdgeTrap({
    required this.trapLeft,
    required this.trapRight,
    required this.child,
    this.onTrapRight,
  });

  @override
  Widget build(BuildContext context) {
    if (!trapLeft && !trapRight) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (trapLeft && key == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (trapRight && key == LogicalKeyboardKey.arrowRight) {
          onTrapRight?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Cast avatar — focusable (no-op tap) so DPAD-down can walk the info column
/// through it, with a visible gold ring while focused.
class _CastTile extends StatefulWidget {
  final CastMember member;
  final Color fallback;
  const _CastTile({required this.member, required this.fallback});

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          _FocusHalo(
            focused: _focused,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {},
                onFocusChange: (f) => setState(() => _focused = f),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: (m.imageUrl != null && m.imageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: m.imageUrl!,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          // 56 logical px avatar (up to dpr 3 on phones) —
                          // never decode a full-res headshot.
                          memCacheWidth: 180,
                          placeholder: (_, __) =>
                              Container(color: widget.fallback),
                          errorWidget: (_, __, ___) =>
                              Container(color: widget.fallback),
                        )
                      : Container(
                          color: widget.fallback,
                          child: Icon(Icons.person, color: Colors.white38),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            m.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// "More Like This" poster card — gold ring + slight scale while focused so the
/// DPAD cursor is unmistakable over artwork.
class _RecCard extends StatefulWidget {
  final StremioMeta rec;
  final Color fallback;
  final VoidCallback onTap;
  const _RecCard({
    required this.rec,
    required this.fallback,
    required this.onTap,
  });

  @override
  State<_RecCard> createState() => _RecCardState();
}

class _RecCardState extends State<_RecCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    return SizedBox(
      width: 100,
      child: _FocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (rec.poster != null && rec.poster!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: rec.poster!,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      // 100 logical px card (up to dpr 3 on phones) — decode
                      // small so ten posters at once don't lean on a 2GB box.
                      memCacheWidth: 300,
                      placeholder: (_, __) => Container(color: widget.fallback),
                      errorWidget: (_, __, ___) =>
                          Container(color: widget.fallback),
                    )
                  else
                    Container(color: widget.fallback),
                  if (rec.type == 'movie' || rec.type == 'series')
                    Positioned(
                      top: 6,
                      right: 6,
                      child: MovieWatchedBadge(
                        imdbId: rec.effectiveImdbId ?? rec.id,
                        contentType: rec.type,
                        compact: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Per-title accent used for the soft glow behind the white pill, so the
  /// primary CTA reads as belonging to this title.
  final Color glow;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.glow = _MergedDetailScreenState._gold,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      // Snap on TV: every frame of the scale pop re-rasters the pill AND its
      // blur-18 glow shadow; instant scale keeps the glow a one-time paint.
      duration: PlatformUtil.isTelevision
          ? Duration.zero
          : const Duration(milliseconds: 140),
      scale: _focused ? 1.05 : 1.0,
      child: _FocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(999),
        // Soft accent glow behind the pill. A static drop shadow (rasterised
        // once, carried by the AnimatedScale transform) — not a per-frame
        // backdrop blur — so it's safe on the weak TV GPU. Animates its color
        // to the title accent when it resolves.
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 500),
          tween: ColorTween(end: widget.glow.withValues(alpha: 0.45)),
          builder: (_, color, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: color ?? Colors.transparent,
                  blurRadius: 18,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: child,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onFocusChange: (f) => setState(() => _focused = f),
              borderRadius: BorderRadius.circular(999),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: const Color(0xFF0D0D10), size: 20),
                    const SizedBox(width: 7),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Color(0xFF0D0D10),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle "trailer playing in background" hint pill. An informational hint, not
/// a primary control (the focusable "Watch Trailer" button is the DPAD way to
/// promote), so it's pointer/touch-tappable only — `canRequestFocus: false`
/// keeps it out of DPAD traversal entirely, so it can never steal focus or
/// strand the remote when it appears/disappears as the trailer plays/pauses.
class _TrailerPlayingChip extends StatelessWidget {
  final VoidCallback onTap;

  /// Null for Classic.
  final DetailTheme? theme;

  const _TrailerPlayingChip({required this.onTap, this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final radius = t?.brBtn ?? BorderRadius.circular(999);
    return Material(
      color:
          t?.ground.withValues(alpha: 0.6) ??
          Colors.black.withValues(alpha: 0.42),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: t?.hair ?? Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: t?.tx ?? Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 7),
              Text(
                'Trailer playing',
                style: TextStyle(
                  color: t?.tx ?? Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Shows a small spinner in place of the icon (e.g. trailer resolving).
  final bool busy;

  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return _FocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourcePill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  const _SourcePill({
    required this.count,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_SourcePill> createState() => _SourcePillState();
}

class _SourcePillState extends State<_SourcePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bound = widget.count > 0;
    const gold = _MergedDetailScreenState._gold;
    final label = bound
        ? (widget.count > 1 ? '${widget.count} sources' : '1 source')
        : 'Bind source';
    return _FocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: bound
            ? gold.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: bound
                    ? gold.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  bound ? Icons.link_rounded : Icons.link_off_rounded,
                  color: bound ? gold : Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: bound ? gold : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto-scrolls the enclosing scrollable when any descendant gains focus.
///
/// [Focus.onFocusChange] fires when this node *or a descendant* changes focus,
/// so wrapping a section with this (non-focusable, traversal-skipping) node
/// lets us react to a child button/tile being focused via DPAD:
///  • [toTop] snaps the column to offset 0 (reveals the header above the first
///    focusable — the "can't scroll back up to the details" fix);
///  • otherwise it `ensureVisible`s the wrapped section at [alignment].
class _ScrollAnchor extends StatelessWidget {
  final Widget child;
  final bool toTop;
  final double alignment;

  /// Only meaningful on TV (DPAD focus scroll). On pointer/desktop this is a
  /// passthrough so a mouse click doesn't yank the column around.
  final bool active;

  const _ScrollAnchor({
    required this.child,
    this.toTop = false,
    this.alignment = 0.5,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // Defer so it wins over the framework's own focus-ensureVisible and
        // runs after layout settles.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (toTop) {
            Scrollable.maybeOf(context)?.position.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          } else {
            Scrollable.ensureVisible(
              context,
              alignment: alignment,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        });
      },
      child: child,
    );
  }
}

/// A tracker's identity in the action row: its brand mark, its name, and the
/// live relationship it holds to this title, in one control that opens that
/// tracker's sheet.
///
/// This replaces the pair of anonymous round icon buttons *and* the status
/// chip rows under the title — the chips rendered exactly the state these
/// pills now carry, so the hero showed every fact twice.
///
/// [tracked] drives the two forms: brand-tinted when the tracker holds the
/// title, plain outline when it doesn't (and while the status loads, so the
/// row keeps its geometry).
class _TrackerPill extends StatefulWidget {
  final Widget mark;

  /// Short brand name, drawn as the pill's uppercase eyebrow.
  final String brand;

  /// The live state line — "Watchlist · Collected", "Watching", "Not tracked".
  final String state;

  /// 1–10 tracker rating, shown in its own compartment when set.
  final int? rating;

  /// The tracker's brand colour, used for the tint, border and rating.
  final Color accent;
  final bool tracked;
  final String tooltip;
  final VoidCallback onTap;

  const _TrackerPill({
    required this.mark,
    required this.brand,
    required this.state,
    required this.rating,
    required this.accent,
    required this.tracked,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_TrackerPill> createState() => _TrackerPillState();
}

class _TrackerPillState extends State<_TrackerPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final tracked = widget.tracked;
    final radius = BorderRadius.circular(999);
    final pill = _FocusHalo(
      focused: _focused,
      radius: radius,
      child: Material(
        color: tracked
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 8, 15, 8),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: tracked
                    ? accent.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.mark,
                const SizedBox(width: 9),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.brand,
                      style: TextStyle(
                        color: tracked
                            ? accent
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.state,
                      style: TextStyle(
                        color: tracked
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                if (widget.rating != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    height: 20,
                    width: 1,
                    color: accent.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${widget.rating}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: widget.tooltip, child: pill);
  }
}

/// Circular translucent icon button used for the hero "More" (⋮) affordance.
class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? background;
  final FocusNode? focusNode;

  /// Null for Classic, which keeps its circle and its gold ring exactly.
  final DetailTheme? theme;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background,
    this.focusNode,
    this.theme,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final circular = t == null || t.radiusBtn >= 999;
    final side = BorderSide(
      color: t?.ghostBorder ?? Colors.white.withValues(alpha: 0.16),
    );
    final shape = circular
        ? CircleBorder(side: side)
        : RoundedRectangleBorder(borderRadius: t.brBtn, side: side);
    final btn = _FocusHalo(
      focused: _focused,
      radius: circular ? null : t.brBtn,
      ringColor: t?.focus,
      child: Material(
        color: widget.background ?? Colors.white.withValues(alpha: 0.08),
        shape: shape,
        child: InkWell(
          customBorder: shape,
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(widget.icon, color: t?.tx ?? Colors.white, size: 22),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}

/// The "More" quick-actions menu — a labelled sheet with an icon, name and a
/// one-line description for every action, so users know what each one does.
class _QuickActionsMenu extends StatelessWidget {
  final String title;
  final List<TraktMenuOption> options;
  final bool isTelevision;
  final void Function(TraktItemMenuAction action) onSelected;

  const _QuickActionsMenu({
    required this.title,
    required this.options,
    required this.isTelevision,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Standard sheet chrome (background + drag handle) is provided by
    // showModalBottomSheet — this widget is just the header + clean list, so it
    // reads the same as the per-episode ⋮ menu.
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'More',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: options.length,
                itemBuilder: (context, i) => _item(options[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(TraktMenuOption o, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: isTelevision && index == 0,
        // The default focus overlay is invisible on the dark sheet — make the
        // DPAD cursor obvious.
        focusColor: Colors.white.withValues(alpha: 0.12),
        onTap: () => onSelected(o.action),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(o.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _MergedDetailScreenState._descriptionFor(o.action),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared chrome for a tracker sheet: the brand lockup, the title it applies
/// to, and a hairline progress line while an action is in flight.
///
/// Only the chrome is shared — the two sheets' bodies stay fully independent,
/// per the "no shared type between the trackers" rule this screen follows.
class _TrackerSheetHeader extends StatelessWidget {
  final Widget mark;
  final String brand;
  final String title;
  final Color accent;
  final bool busy;

  const _TrackerSheetHeader({
    required this.mark,
    required this.brand,
    required this.title,
    required this.accent,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.18), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              mark,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      brand,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: busy
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: accent,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                )
              : Container(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ],
    );
  }
}

/// Section label inside a tracker sheet.
class _SheetGroupLabel extends StatelessWidget {
  final String label;
  const _SheetGroupLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.38),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    ),
  );
}

/// A relationship the tracker either holds or doesn't — rendered as a switch
/// so the current state is readable without parsing an "Add…"/"Remove…" verb.
class _SheetSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Color accent;
  final bool autofocus;
  final VoidCallback onTap;

  const _SheetSwitchRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        focusColor: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: value ? accent : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // A drawn switch rather than a Material Switch: this is a
              // command that round-trips to an API, so it must not animate to
              // the new position before the call lands — the parent re-reads
              // the status and rebuilds with the truth.
              Container(
                width: 42,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? accent : Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain icon + label + description row, for actions that aren't a state
/// (list management, playback removal).
class _SheetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color? color;
  final bool autofocus;
  final VoidCallback onTap;

  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.color,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        focusColor: Colors.white.withValues(alpha: 0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 21, color: tint),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: tint,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 1–10 rating strip. Ten focusable cells beat a modal dialog on both
/// inputs: one tap on touch, a LEFT/RIGHT run and OK on a remote.
class _SheetRatingStrip extends StatelessWidget {
  final int? rating;
  final Color accent;
  final Color onAccent;
  final void Function(int rating) onRate;
  final VoidCallback? onClear;

  /// Puts the DPAD cursor on the current score (or 1 when unrated) — used when
  /// the strip is the first thing in the sheet.
  final bool autofocus;

  const _SheetRatingStrip({
    required this.rating,
    required this.accent,
    required this.onAccent,
    required this.onRate,
    this.onClear,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = rating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 10; i++) ...[
                if (i > 1) const SizedBox(width: 5),
                Expanded(
                  child: Material(
                    color: current == null || i > current
                        ? Colors.white.withValues(alpha: 0.07)
                        : (i == current
                              ? accent
                              : accent.withValues(alpha: 0.22)),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      autofocus: autofocus && i == (current ?? 1),
                      borderRadius: BorderRadius.circular(8),
                      focusColor: Colors.white.withValues(alpha: 0.18),
                      onTap: () => onRate(i),
                      child: SizedBox(
                        height: 32,
                        child: Center(
                          child: Text(
                            '$i',
                            style: TextStyle(
                              color: current != null && i == current
                                  ? onAccent
                                  : Colors.white.withValues(
                                      alpha: current != null && i < current
                                          ? 0.85
                                          : 0.5,
                                    ),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                current != null ? 'Rated $current/10' : 'Not rated',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              if (onClear != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    focusColor: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        'Clear rating',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Trakt's sheet.
///
/// Takes the same option list the old menu did — so every availability rule
/// (connected? has an IMDb id? on a Trakt Continue Watching row?) still lives
/// in `buildTraktAddOnlyMenuOptions` — but renders the add/remove pairs as
/// switches, since each pair is really one on/off relationship.
///
/// Stays open across actions: after each one it re-reads the live status via
/// [statusLoader] and rebuilds its options from it, so the switches always
/// show what Trakt actually holds rather than an optimistic guess.
class _TraktSheet extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final TraktTitleStatus? status;
  final List<TraktMenuOption> Function(TraktTitleStatus? status) optionsFor;
  final Future<void> Function(TraktItemMenuAction action) onAction;
  final Future<void> Function(int rating)? onRate;
  final Future<TraktTitleStatus?> Function()? statusLoader;
  final void Function(TraktTitleStatus? status) onChanged;

  const _TraktSheet({
    required this.title,
    required this.isTelevision,
    required this.status,
    required this.optionsFor,
    required this.onAction,
    required this.onRate,
    required this.statusLoader,
    required this.onChanged,
  });

  @override
  State<_TraktSheet> createState() => _TraktSheetState();
}

class _TraktSheetState extends State<_TraktSheet> {
  late TraktTitleStatus? _status = widget.status;
  bool _busy = false;

  /// Runs one action, then re-reads the status so the sheet (and the pill
  /// behind it, via [onChanged]) reflect the result. Serialised: a second tap
  /// while a call is in flight is dropped rather than racing it.
  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      final loader = widget.statusLoader;
      if (loader != null) {
        final fresh = await loader();
        // Null means "couldn't be trusted" (disconnected, or the library fetch
        // failed), NOT "nothing tracked" — both services document that, and a
        // genuine empty answer comes back as a non-null all-false status. So
        // keep showing the last known state rather than fabricating one.
        if (fresh == null) return;
        // Publish first: the sheet may already be gone (dismissed mid-call),
        // and the screen behind it still needs the result for its pill.
        widget.onChanged(fresh);
        if (!mounted) return;
        setState(() => _status = fresh);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.optionsFor(_status);
    TraktMenuOption? opt(TraktItemMenuAction a) {
      for (final o in options) {
        if (o.action == a) return o;
      }
      return null;
    }

    final watchlistOn = opt(TraktItemMenuAction.removeFromWatchlist);
    final watchlistOff = opt(TraktItemMenuAction.addToWatchlist);
    final collectionOn = opt(TraktItemMenuAction.removeFromCollection);
    final collectionOff = opt(TraktItemMenuAction.addToCollection);
    final markWatched = opt(TraktItemMenuAction.markWatched);
    final markUnwatched = opt(TraktItemMenuAction.markUnwatched);
    // Only `addToList` is ever emitted (and `handleTraktMenuAction` returns
    // early on removeFromList — there's no context for *which* list), so this
    // section is add-only by design.
    final addToList = opt(TraktItemMenuAction.addToList);
    final removePlayback = opt(TraktItemMenuAction.removeFromTraktPlayback);
    final canRate = opt(TraktItemMenuAction.rate) != null;
    final canUnrate = opt(TraktItemMenuAction.removeRating) != null;

    // A series' whole-title watched state is unknown (the episode list owns
    // it), so Trakt offers BOTH mark actions — that can't be a switch, and
    // shows as two explicit commands instead.
    final watchedIsAmbiguous = markWatched != null && markUnwatched != null;

    // TV: whichever row renders first takes the cursor. Which sections exist
    // depends on the live status, so this is claimed in build order rather
    // than hard-coded to one row.
    var focusClaimed = false;
    bool claimFocus() {
      if (!widget.isTelevision || focusClaimed) return false;
      return focusClaimed = true;
    }

    final libraryRows = <Widget>[
      if (watchlistOn != null || watchlistOff != null)
        _SheetSwitchRow(
          icon: Icons.bookmark_rounded,
          label: 'Watchlist',
          subtitle: 'Synced to every device on your Trakt account',
          value: watchlistOn != null,
          accent: kTraktRed,
          autofocus: claimFocus(),
          onTap: () => _run(
            () => widget.onAction((watchlistOn ?? watchlistOff)!.action),
          ),
        ),
      if (collectionOn != null || collectionOff != null)
        _SheetSwitchRow(
          icon: Icons.video_library_rounded,
          label: 'Collection',
          subtitle: 'Your library of everything you own or keep track of',
          value: collectionOn != null,
          accent: kTraktRed,
          autofocus: claimFocus(),
          onTap: () => _run(
            () => widget.onAction((collectionOn ?? collectionOff)!.action),
          ),
        ),
      if (!watchedIsAmbiguous && (markWatched != null || markUnwatched != null))
        _SheetSwitchRow(
          icon: Icons.visibility_rounded,
          label: 'Watched',
          subtitle: 'Syncs your history across all your devices',
          value: markUnwatched != null,
          accent: kTraktRed,
          autofocus: claimFocus(),
          onTap: () => _run(
            () => widget.onAction((markUnwatched ?? markWatched)!.action),
          ),
        ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TrackerSheetHeader(
              mark: const TraktMark(size: 30),
              brand: 'Trakt',
              title: widget.title,
              accent: kTraktRed,
              busy: _busy,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (libraryRows.isNotEmpty) ...[
                      const _SheetGroupLabel('Your library'),
                      ...libraryRows,
                    ],
                    if (watchedIsAmbiguous) ...[
                      const _SheetGroupLabel('History'),
                      _SheetActionRow(
                        icon: markWatched.icon,
                        label: markWatched.label,
                        description: _MergedDetailScreenState._descriptionFor(
                          markWatched.action,
                        ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(markWatched.action)),
                      ),
                      _SheetActionRow(
                        icon: markUnwatched.icon,
                        label: markUnwatched.label,
                        description: _MergedDetailScreenState._descriptionFor(
                          markUnwatched.action,
                        ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(markUnwatched.action)),
                      ),
                    ],
                    if (canRate) ...[
                      const _SheetGroupLabel('Rating'),
                      _SheetRatingStrip(
                        rating: _status?.rating,
                        accent: kTraktRed,
                        onAccent: Colors.white,
                        autofocus: claimFocus(),
                        onRate: (r) => _run(() async {
                          final rate = widget.onRate;
                          // No inline-rate callback wired (e.g. the IPTV
                          // caller) — fall back to the tracker's own dialog.
                          if (rate == null) {
                            await widget.onAction(TraktItemMenuAction.rate);
                          } else {
                            await rate(r);
                          }
                        }),
                        onClear: canUnrate
                            ? () => _run(
                                () => widget.onAction(
                                  TraktItemMenuAction.removeRating,
                                ),
                              )
                            : null,
                      ),
                    ],
                    if (addToList != null) ...[
                      const _SheetGroupLabel('Lists'),
                      _SheetActionRow(
                        icon: addToList.icon,
                        label: addToList.label,
                        description: _MergedDetailScreenState._descriptionFor(
                          addToList.action,
                        ),
                        autofocus: claimFocus(),
                        onTap: () =>
                            _run(() => widget.onAction(addToList.action)),
                      ),
                    ],
                    if (removePlayback != null) ...[
                      const _SheetGroupLabel('Playback'),
                      _SheetActionRow(
                        icon: removePlayback.icon,
                        label: removePlayback.label,
                        description: _MergedDetailScreenState._descriptionFor(
                          removePlayback.action,
                        ),
                        color: const Color(0xFFFF8B8B),
                        autofocus: claimFocus(),
                        // Closes the sheet: whether this title is still on a
                        // Trakt Continue Watching row was decided when the
                        // screen opened, so the row can't refresh itself.
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onAction(removePlayback.action);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simkl's sheet — the same job as [_TraktSheet], deliberately not sharing a
/// type with it (Trakt and Simkl stay independent everywhere in this screen).
///
/// Simkl has no toggle-off: a title sits in exactly one of five lists, and the
/// only move is between them. So the statuses render as one exclusive picker
/// showing where the title is now, rather than four "Move to X" commands with
/// the current state left implicit.
class _SimklSheet extends StatefulWidget {
  final String title;
  final bool isTelevision;
  final SimklTitleStatus? status;
  final List<SimklMenuOption> Function(SimklTitleStatus? status) optionsFor;
  final Future<void> Function(SimklItemMenuAction action) onAction;
  final Future<void> Function(int rating)? onRate;
  final Future<SimklTitleStatus?> Function()? statusLoader;
  final void Function(SimklTitleStatus? status) onChanged;

  const _SimklSheet({
    required this.title,
    required this.isTelevision,
    required this.status,
    required this.optionsFor,
    required this.onAction,
    required this.onRate,
    required this.statusLoader,
    required this.onChanged,
  });

  @override
  State<_SimklSheet> createState() => _SimklSheetState();
}

class _SimklSheetState extends State<_SimklSheet> {
  late SimklTitleStatus? _status = widget.status;
  bool _busy = false;

  /// Simkl's five lists, in the order the service presents them.
  static const _statuses = <(String, String, SimklItemMenuAction, IconData)>[
    (
      'plantowatch',
      'Plan to Watch',
      SimklItemMenuAction.moveToPlanToWatch,
      Icons.bookmark_add_rounded,
    ),
    (
      'watching',
      'Watching',
      SimklItemMenuAction.moveToWatching,
      Icons.visibility_rounded,
    ),
    (
      'hold',
      'On Hold',
      SimklItemMenuAction.moveToOnHold,
      Icons.pause_circle_rounded,
    ),
    (
      'completed',
      'Completed',
      SimklItemMenuAction.moveToCompleted,
      Icons.check_circle_rounded,
    ),
    (
      'dropped',
      'Dropped',
      SimklItemMenuAction.moveToDropped,
      Icons.cancel_rounded,
    ),
  ];

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      final loader = widget.statusLoader;
      if (loader != null) {
        final fresh = await loader();
        // Null means "couldn't be trusted" (disconnected, or the library fetch
        // failed), NOT "nothing tracked" — both services document that, and a
        // genuine empty answer comes back as a non-null all-false status. So
        // keep showing the last known state rather than fabricating one.
        if (fresh == null) return;
        // Publish first: the sheet may already be gone (dismissed mid-call),
        // and the screen behind it still needs the result for its pill.
        widget.onChanged(fresh);
        if (!mounted) return;
        setState(() => _status = fresh);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.optionsFor(_status);
    SimklMenuOption? opt(SimklItemMenuAction a) {
      for (final o in options) {
        if (o.action == a) return o;
      }
      return null;
    }

    final current = _status?.currentStatus;
    final removeCw = opt(SimklItemMenuAction.removeFromContinueWatching);
    final canRate = opt(SimklItemMenuAction.rate) != null;
    final canUnrate = opt(SimklItemMenuAction.removeRating) != null;

    // A status row is offered when its move action is available, and the
    // current one is always shown even though the builder omits it (there's
    // nowhere to move it to). Movies therefore keep hiding Watching and On
    // Hold — Simkl treats them as a single session — with no rule duplicated
    // here: it falls out of what the builder offered.
    final visible = [
      for (final (value, label, action, icon) in _statuses)
        if (opt(action) != null || value == current)
          (value, label, action, icon),
    ];
    // TV: start on the current status when there is one — that's where the
    // user's attention already is, and moving from it is the whole point.
    final currentIndex = visible.indexWhere((s) => s.$1 == current);
    final focusIndex = currentIndex >= 0 ? currentIndex : 0;
    final rows = <Widget>[
      for (final (i, (value, label, action, icon)) in visible.indexed)
        _SimklStatusRow(
          icon: icon,
          label: label,
          selected: value == current,
          autofocus: widget.isTelevision && i == focusIndex,
          // The current row has nothing to move to, so its tap is a no-op —
          // but it must still be *focusable*: a disabled InkWell can't hold
          // the DPAD cursor, so the row you just activated would drop focus
          // the moment it became current.
          onTap: value == current
              ? () {}
              : () => _run(() => widget.onAction(action)),
        ),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TrackerSheetHeader(
              mark: const SimklMark(size: 30),
              brand: 'Simkl',
              title: widget.title,
              accent: kSimklCyan,
              busy: _busy,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isNotEmpty) ...[
                      const _SheetGroupLabel('Status'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rows,
                        ),
                      ),
                    ],
                    if (canRate) ...[
                      const _SheetGroupLabel('Rating'),
                      _SheetRatingStrip(
                        rating: _status?.rating,
                        accent: kSimklCyan,
                        onAccent: const Color(0xFF04262C),
                        autofocus: widget.isTelevision && rows.isEmpty,
                        onRate: (r) => _run(() async {
                          final rate = widget.onRate;
                          if (rate == null) {
                            await widget.onAction(SimklItemMenuAction.rate);
                          } else {
                            await rate(r);
                          }
                        }),
                        onClear: canUnrate
                            ? () => _run(
                                () => widget.onAction(
                                  SimklItemMenuAction.removeRating,
                                ),
                              )
                            : null,
                      ),
                    ],
                    if (removeCw != null) ...[
                      const _SheetGroupLabel('Playback'),
                      _SheetActionRow(
                        icon: removeCw.icon,
                        label: removeCw.label,
                        description:
                            _MergedDetailScreenState._descriptionForSimkl(
                              removeCw.action,
                            ),
                        color: const Color(0xFFFF8B8B),
                        autofocus:
                            widget.isTelevision && rows.isEmpty && !canRate,
                        // Closes for the same reason as Trakt's: whether the
                        // title has a paused session was decided when the
                        // screen opened.
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onAction(removeCw.action);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of Simkl's five lists, shown as a radio-style row so the exclusivity is
/// visible. The current status is marked and inert — there's nothing to do.
class _SimklStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool autofocus;

  /// Never null — the current row passes a no-op so it stays focusable. See
  /// the call site in [_SimklSheetState.build].
  final VoidCallback onTap;

  const _SimklStatusRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(11);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? kSimklCyan.withValues(alpha: 0.13)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          autofocus: autofocus,
          borderRadius: radius,
          focusColor: Colors.white.withValues(alpha: 0.12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? kSimklCyan.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? kSimklCyan : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? kSimklCyan
                          : Colors.white.withValues(alpha: 0.22),
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Color(0xFF04262C),
                        )
                      : null,
                ),
                const SizedBox(width: 13),
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? kSimklCyan
                      : Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? kSimklCyan : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Text(
                    'now',
                    style: TextStyle(
                      color: kSimklCyan.withValues(alpha: 0.7),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The focused episode's frame, painted over the title artwork.
///
/// Switches instantly on TV: a fullscreen animated opacity per DPAD move is
/// exactly what the TV cost budget forbids. Off-TV it cross-fades.
class _AmbientStill extends StatelessWidget {
  final String url;
  final bool isTelevision;

  const _AmbientStill({required this.url, required this.isTelevision});

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      fit: BoxFit.cover,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: 1280,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
    );
    if (isTelevision) return image;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      // The default layout centres children under LOOSE constraints, so a
      // BoxFit.cover image would size itself to its own aspect and letterbox.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: image,
    );
  }
}
