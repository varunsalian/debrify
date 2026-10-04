import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/merged_detail/application/merged_detail_simkl_labels.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_ambient_still.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_cast_tile.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_parts.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_rec_card.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_simkl_sheet.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_trakt_sheet.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/features/merged_detail/presentation/merged_ghost_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_primary_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_quick_actions_menu.dart';
import 'package:debrify/features/merged_detail/presentation/merged_rail_edge_trap.dart';
import 'package:debrify/features/merged_detail/presentation/merged_round_icon_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_scroll_anchor.dart';
import 'package:debrify/features/merged_detail/presentation/merged_source_pill.dart';
import 'package:debrify/features/merged_detail/presentation/merged_stagger_reveal.dart';
import 'package:debrify/features/merged_detail/presentation/merged_tracker_pill.dart';
import 'package:debrify/features/merged_detail/presentation/merged_trailer_playing_chip.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/ambient_trailer_surface.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/episodes_screen.dart'
    show kCatalogDetailRouteName;
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/screens/settings/detail_page_style_page.dart'
    show effectiveDetailPageStyle;
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/imdb_trailer_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/movie_completion_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/ambient_trailer_storage.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/artwork_accent.dart';
import 'package:debrify/theme/shipped_themes.dart' show effectiveDetailTheme;
import 'package:debrify/theme/theme_core_resolver.dart';
import 'package:debrify/theme/theme_overrides.dart';
import 'package:debrify/utils/artwork_url.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_episode_cells.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_layout_premium.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_layout_stage.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/detail_primary_sources.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/horizontal_mouse_wheel.dart';
import 'package:debrify/widgets/metadata_franchise_rail.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:debrify/widgets/metadata_title_navigation.dart';
import 'package:debrify/widgets/parents_guide_section.dart';
import 'package:debrify/widgets/rewatch_progress_dialog.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final Future<void> Function(
    ({bool started, int season, int episode})? promised,
  )
  onResume;
  final Future<void> Function()? onRewatch;

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
    this.onRewatch,
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
    with RouteAware, MetadataPresentationMixin<MergedDetailScreen> {
  // ── Stremio-flat palette (neutral glass + gold state) ──
  late final MergedDetailParts _parts;
  _MergedDetailScreenState() {
    final deps = MergedDetailDependencies();
    _parts = MergedDetailParts(deps);
    deps.parts = _parts;
  }
  MergedDetailFocusState get _f => _parts.focusState;
  MergedDetailMetadataState get _m => _parts.metadataState;
  MergedDetailModelFactory get _b => _parts.modelFactory;
  MergedDetailResumeState get _r => _parts.resumeState;
  MergedDetailTrackingState get _k => _parts.trackingState;
  MergedDetailTrailerState get _t => _parts.trailerState;

  void _openMetadataRecommendation(StremioMeta item) {
    final onOpen = widget.onRecommendationTap;
    if (onOpen != null)
      unawaited(
        openMetadataTitle(
          context,
          _m.recommendationOriginals[item] ?? item,
          onOpen,
        ),
      );
  }

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
      : effectiveDetailPageStyle(DetailPageStorage.detailPageStyleCached);

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
    effectiveDetailTheme(DetailPageStorage.detailThemeCached),
    // Classic is deliberately unthemed, and the controller's own fast path says
    // so. Applying overrides here anyway would make this the one surface that
    // disagreed with it.
    AppThemeController.instance.isLegacy
        ? ThemeOverrides.none
        : AppThemeController.instance.overrides,
  );

  /// Whether this page should show sharp key art at rest at all. Showcase is
  /// the tvOS idiom and the only layout designed around real artwork; every
  /// other layout was drawn against the blurred wash and would lose its text
  /// legibility over a sharp one.
  bool get _wantsSharpStill => _style == 'showcase' && !_f.bodyDeep;

  /// The two focus anchors the shell owns, handed to whichever body draws.
  late final DetailFocusCoordinator _focusCoordinator = DetailFocusCoordinator(
    backNode: _f.backButtonFocusNode,
    primaryEntry: _f.leftEntryFocusNode,
  );

  @override
  StremioMeta get originalMetadata => _m.enriched ?? widget.item;
  // Presentation is for rendering; source searches retain widget.item so a
  // translated display title cannot change file matching or binding queries.
  StremioMeta get _item => presentedMetadata!;
  bool get _primaryBusy => _r.resumePending && !_r.resumeLoaded;

  /// The quick-actions strip to render: rebuilt against [_traktStatus] when a
  /// builder was supplied, else the static list passed in.
  List<TraktMenuOption> get _menuOptions =>
      widget.traktMenuBuilder?.call(_k.traktStatus) ?? widget.traktMenuOptions;

  List<TraktMenuOption> get _appMenuOptions => [
    for (final o in _menuOptions)
      if (appOwnedActions.contains(o.action)) o,
  ];

  List<TraktMenuOption> get _traktOnlyMenuOptions => [
    for (final o in _menuOptions)
      if (!appOwnedActions.contains(o.action)) o,
  ];
  bool get _supportsMyWatchlist =>
      WatchlistStorage.supportsMyWatchlistItem(_item);
  StremioMeta get _myWatchlistItem => WatchlistStorage.withMyWatchlistSource(
    _item,
    widget.item.sourceAddon ?? widget.addon,
  );

  /// The Simkl quick-actions strip to render: rebuilt against [_simklStatus]
  /// when a builder was supplied, else the static list passed in.
  List<SimklMenuOption> get _menuOptionsSimkl =>
      widget.simklMenuBuilder?.call(_k.simklStatus) ?? widget.simklMenuOptions;
  List<MdblistMenuOption> get _menuOptionsMdblist =>
      widget.mdblistMenuBuilder?.call(_k.mdblistStatus) ??
      widget.mdblistMenuOptions;

  @override
  void initState() {
    super.initState();
    TrackingSourceStorage.trackingSourceRevision.addListener(
      _onMovieProgressPolicyChanged,
    );
    MovieProgressStorage.movieFinishedRevision.addListener(
      _loadLocalMovieFinished,
    );
    MdblistService.instance.watchedRevision.addListener(
      _loadLocalMovieFinished,
    );
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
      _loadMdblistStatus();
      _loadLocalMovieFinished();
      _loadMyWatchlistState();
    });
  }

  Future<void> _guardPlay(Future<void> Function() launch) async {
    if (_r.playLaunching || !mounted) return;
    // Rebuild immediately so HeroTrailerBackdrop disables and tears down its
    // engine at the button press. The resolving loader is a RawDialogRoute,
    // which the app's PageRoute observer deliberately does not see; waiting
    // for the eventual player-handoff signal lets the delayed trailer start
    // (or keep playing) behind source resolution.
    setState(() => _r.playLaunching = true);
    try {
      await launch();
    } finally {
      if (mounted) {
        // A cancelled/failed resolve may resume autoplay after its normal
        // delay. A successful launch remains off because the backdrop's
        // content-player signal has independently latched _canPlay false.
        setState(() => _r.playLaunching = false);
      } else {
        _r.playLaunching = false;
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
    final season = _r.resumeSeason;
    final episode = _r.resumeEpisode;
    return (!_isMovie &&
            _r.resumeStarted &&
            _r.hasMergedEpisodeTarget &&
            season != null &&
            episode != null)
        ? (started: true, season: season, episode: episode)
        : null;
  }

  void _playPrimary() {
    if (_primaryLabel == 'Rewatch') {
      unawaited(_guardPlay(_rewatchTitle));
      return;
    }
    final promised = _primaryEpisodePromise;
    debugPrint(
      '[SeriesResume] detail-primary-pressed title="${_item.name}" '
      'label="$_primaryLabel" loaded=${_r.resumeLoaded} started=${_r.resumeStarted} '
      'labelTarget=S${_r.resumeSeason}E${_r.resumeEpisode} '
      'routeTarget=S${widget.initialSeason}E${widget.initialEpisode} '
      'mergedEngineTarget=${_r.hasMergedEpisodeTarget} '
      'loaderInFlight=${_r.resumeLoaderInFlight} '
      'promised=${promised == null ? 'none' : 'S${promised.season}E${promised.episode}'}',
    );
    unawaited(_guardPlay(() => widget.onResume(promised)));
  }

  Future<void> _rewatchTitle() async {
    final restart = widget.onRewatch;
    if (restart == null) return;
    final cleared = await resetProgressForRewatch(
      context,
      id: _item.imdbId ?? _item.id,
      title: _item.name,
      isMovie: _isMovie,
      onConfirmed: () => setState(() => _r.rewatchPending = true),
    );
    if (!mounted) return;
    _f.episodesPanelKey.currentState?.refreshWatchProgress();
    if (!cleared) return;
    ++_k.movieCompletionGeneration; // Discard reads started before the reset.
    setState(() {
      _r.seriesDone = false;
      _r.rewatchPending = false;
      _k.localMovieFinished = false;
      _k.simklStatus = null;
      _r.resumeStarted = false;
      _r.resumeSeason = 1;
      _r.resumeEpisode = 1;
      _r.hasMergedEpisodeTarget = false;
    });
    await restart();
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

    final rules = await QuickPlayStorage.getQuickPlayRules(isMovie: false);
    if (!mounted) return;

    final canBrowsePacks =
        widget.onTraktAction != null &&
        _appMenuOptions.any(
          (option) => option.action == TraktItemMenuAction.searchPacks,
        );
    if (!rules.preferSeriesPacks || !canBrowsePacks) {
      await openEpisode(_primaryEpisodePromise);
      return;
    }

    final season = _r.resumeSeason;
    final episode = _r.resumeEpisode;
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
      if (mounted) setState(() => _m.showcaseOpeningDataReady = true);
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
    _r.hasMergedEpisodeTarget = false;
    _loadResumeInfo();
    // Watched state (and thus the resume label / badges) may have changed while
    // away — re-read the Trakt status too.
    _loadTraktStatus();
    _loadSimklStatus();
    _loadMdblistStatus();
    _loadLocalMovieFinished();
    _loadMyWatchlistState();
    // And the episode list's ticks/progress: episode quick-play now plays on
    // top of this screen (like Resume), so the list is still alive when the
    // player returns and must reflect the session that just ended.
    _f.episodesPanelKey.currentState?.refreshWatchProgress();
    // Sources can be bound from inside the player's own source picker and from
    // the app-action menu, so returning here is the only place that catches
    // both. Cheap — a prefs read, not a network call.
    unawaited(_loadBoundSources());
  }

  Future<void> _loadMyWatchlistState() async {
    if (!_supportsMyWatchlist) return;
    final saved = await WatchlistStorage.isInMyWatchlist(_myWatchlistItem);
    if (!mounted || saved == _k.inMyWatchlist) return;
    setState(() => _k.inMyWatchlist = saved);
  }

  Future<void> _toggleMyWatchlist() async {
    if (!_supportsMyWatchlist) return;
    final next = !_k.inMyWatchlist;
    setState(() => _k.inMyWatchlist = next);
    try {
      await WatchlistStorage.setMyWatchlistItem(_myWatchlistItem, next);
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
      setState(() => _k.inMyWatchlist = !next);
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
      final status = (await loader())?.preserveWatchedFrom(_k.traktStatus);
      if (!mounted || status == null) return;
      setState(() => _k.traktStatus = status);
    } catch (_) {
    } finally {
      // Resolved either way: a failed read is still an answered question as
      // far as the pill is concerned — it stops saying "Checking…" and falls
      // back to the untracked form rather than spinning forever.
      if (mounted && !_k.traktStatusResolved) {
        setState(() => _k.traktStatusResolved = true);
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
      setState(() => _k.simklStatus = status);
    } catch (_) {
    } finally {
      if (mounted && !_k.simklStatusResolved) {
        setState(() => _k.simklStatusResolved = true);
      }
    }
  }

  Future<void> _loadMdblistStatus() async {
    final loader = widget.mdblistStatusLoader;
    if (loader == null) return;
    try {
      final status = await loader();
      if (!mounted || status == null) return;
      setState(() => _k.mdblistStatus = status);
    } catch (_) {
    } finally {
      if (mounted && !_k.mdblistStatusResolved) {
        setState(() => _k.mdblistStatusResolved = true);
      }
    }
  }

  Future<void> _loadLocalMovieFinished() async {
    final generation = ++_k.movieCompletionGeneration;
    if (!_isMovie) return;
    final imdbId =
        _item.effectiveImdbId ?? (_item.id.startsWith('tt') ? _item.id : null);
    if (imdbId == null || imdbId.isEmpty) return;
    final finished = await MovieCompletionService.load(imdbId);
    if (mounted &&
        generation == _k.movieCompletionGeneration &&
        finished != _k.localMovieFinished) {
      setState(() => _k.localMovieFinished = finished);
    }
  }

  void _onMovieProgressPolicyChanged() {
    if (!mounted) return;
    setState(() => _k.localMovieFinished = false);
    _loadLocalMovieFinished();
  }

  Future<void> _loadResumeInfo() async {
    final loader = widget.resumeInfoLoader;
    if (loader == null) return;
    debugPrint(
      '[SeriesResume] detail-loader-start title="${_item.name}" '
      'id=${_item.effectiveImdbId ?? _item.id} '
      'routeTarget=S${widget.initialSeason}E${widget.initialEpisode} '
      'loaded=${_r.resumeLoaded} mergedTarget=${_r.hasMergedEpisodeTarget}',
    );
    // setState, not a plain assignment: this runs post-frame (initState
    // schedules it via addPostFrameCallback), and the spinner must actually
    // be scheduled to paint — a bare write only showed it when a sibling
    // loader happened to rebuild.
    if (!_r.resumeLoaded && mounted) {
      setState(() => _r.resumePending = true);
    }
    _r.resumeLoaderInFlight = true;
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
        'engineAlreadyMerged=${_r.hasMergedEpisodeTarget} '
        'stashedEngine=${_r.pendingEngineTarget == null ? 'none' : 'S${_r.pendingEngineTarget!.season}E${_r.pendingEngineTarget!.episode}/started=${_r.pendingEngineTarget!.started}'}',
      );
      // Once the mounted episode engine has resolved all tracker/local
      // progress, its coordinate is newer and richer than the host loader's
      // cached Continue Watching snapshot. Do not let a slower stale loader
      // overwrite (for example) E7 back to a completed E6. (Pre-settle the
      // engine only stashes, so this guard fires solely on post-settle
      // re-reads — e.g. didPopNext after playback.)
      if (!_isMovie && _r.hasMergedEpisodeTarget) {
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
      final stash = _r.pendingEngineTarget;
      _r.pendingEngineTarget = null;
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
        _r.resumeLoaded = true;
        _r.resumeStarted = info.started;
        _r.resumeSeason = info.season;
        _r.resumeEpisode = info.episode;
      });
    } catch (error, stackTrace) {
      // Non-critical — leave the static label.
      debugPrint(
        '[SeriesResume] detail-loader-failed title="${_item.name}" '
        'error=$error\n$stackTrace',
      );
    } finally {
      _r.resumeLoaderInFlight = false;
      if (_r.resumePending) {
        if (mounted) {
          setState(() => _r.resumePending = false);
        } else {
          _r.resumePending = false;
        }
      }
      // Loader failed (or bailed) without settling: the stashed engine
      // target is better than a pill stuck on the static label. Emissions
      // arriving after this point direct-write (legacy) — the in-flight
      // window is closed, so nothing can strand in the stash.
      if (mounted && !_r.resumeLoaded) {
        final fallback = _r.pendingEngineTarget;
        _r.pendingEngineTarget = null;
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
      'mutation=$mutation loaderInFlight=${_r.resumeLoaderInFlight} '
      'labelLoaded=${_r.resumeLoaded} current=S${_r.resumeSeason}E${_r.resumeEpisode} '
      'currentStarted=${_r.resumeStarted}',
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
    if (_r.resumeLoaderInFlight && !_r.resumeLoaded && !mutation) {
      _r.pendingEngineTarget = next;
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
    if (_r.resumeLoaded &&
        _r.resumeStarted &&
        !mutation &&
        widget.resumeInfoLoader != null) {
      debugPrint(
        '[SeriesResume] detail-engine-discarded title="${_item.name}" '
        'target=S${next.season}E${next.episode} '
        'reason=started-loader-authoritative',
      );
      return;
    }
    if (_r.resumeLoaded &&
        _r.resumeStarted == next.started &&
        _r.resumeSeason == next.season &&
        _r.resumeEpisode == next.episode) {
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
      _r.hasMergedEpisodeTarget = next.started;
      _r.resumeLoaded = true;
      _r.resumeStarted = next.started;
      _r.resumeSeason = next.season;
      _r.resumeEpisode = next.episode;
    });
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static Play/Resume label until the resume state resolves.
  String get _primaryLabel =>
      widget.onRewatch == null && _resolvedPrimaryLabel == 'Rewatch'
      ? 'Play'
      : _resolvedPrimaryLabel;

  String get _resolvedPrimaryLabel {
    if (_r.rewatchPending || (!_isMovie && _r.seriesDone)) return 'Rewatch';
    // Completion is available independently of the optional resume loader.
    // Keep the rewatch affordance visible for movie routes that omit one.
    if (!_r.resumeLoaded) {
      if (_isMovie && _k.localMovieFinished) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Resume';
    }
    if (!_r.resumeStarted) {
      // A movie already finished on Simkl (status `completed`) has no resume
      // session; its Play un-marks it watched so the rewatch re-enters
      // Continue Watching — surface that intent as "Rewatch".
      if (_isMovie && _k.localMovieFinished) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Start Watching';
    }
    if (_isMovie || _r.resumeSeason == null || _r.resumeEpisode == null) {
      return 'Resume';
    }
    return 'Resume · S${_r.resumeSeason}E${_r.resumeEpisode}';
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
      if (c != null && mounted) setState(() => _m.accent = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    TrackingSourceStorage.trackingSourceRevision.removeListener(
      _onMovieProgressPolicyChanged,
    );
    MovieProgressStorage.movieFinishedRevision.removeListener(
      _loadLocalMovieFinished,
    );
    MdblistService.instance.watchedRevision.removeListener(
      _loadLocalMovieFinished,
    );
    appRouteObserver.unsubscribe(this);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    _f.infoScroll.dispose();
    _f.castRailScroll.dispose();
    _f.recommendationRailScroll.dispose();
    _f.leftEntryFocusNode.dispose();
    _f.infoPaneScope.dispose();
    _f.episodesPaneScope.dispose();
    _f.backButtonFocusNode.dispose();
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
        _m.enriched = StremioMeta(
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
      refreshMetadataPresentation();
    } catch (_) {}
  }

  Future<String?> _currentTrailerId() async {
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
    return ytId;
  }

  Future<void> _loadTrailer() async {
    final generation = ++_t.trailerGeneration;
    final scope = ProfileRuntime.scope.value;
    final policyRevision = MetadataPreferencesService.revision.value;
    bool current() =>
        mounted &&
        generation == _t.trailerGeneration &&
        scope == ProfileRuntime.scope.value &&
        policyRevision == MetadataPreferencesService.revision.value;
    try {
      final prefs = await MetadataPreferencesService.loadForBackground(
        isCurrent: current,
      );
      if (prefs == null) return;
      final candidates = await MetadataProviderService.instance.trailers(
        widget.item,
        _currentTrailerId,
        preferences: prefs,
      );
      if (!mounted || !current()) return;
      _t.trailerCandidates = candidates;
      _t.allowTrailerFallback =
          prefs.provider(MetadataCategory.trailers) ==
              MetadataPreferences.current ||
          prefs.fallback;
      final ytId = candidates.firstOrNull?.key;
      if (ytId == null || ytId.isEmpty || !current()) return;
      setState(() => _t.trailerYtId = ytId);

      // OTT autoplay: honour the setting, then pre-resolve the stream (also reused
      // by the Trailer button). Silent on failure — the poster simply stays.
      final autoplay =
          await AmbientTrailerStorage.getDetailTrailerAutoplayEnabled();
      // The ambient sound pair is shared with the TV hero (one live surface per
      // platform), so off-TV it governs this backdrop. Read unconditionally so
      // all three land in the one setState below — [autoplay] is false on TV
      // anyway, and these are two prefs reads.
      final soundOn = await AmbientTrailerStorage.getAmbientTrailerAudioEnabled(
        AmbientTrailerSurface.detail,
      );
      final volume = await AmbientTrailerStorage.getAmbientTrailerVolume(
        AmbientTrailerSurface.detail,
      );
      if (!mounted || !current()) return;
      // The backdrop refuses to autoplay under OS reduced-motion — skip the whole
      // pipeline (no resolve, no spinner) rather than spin forever waiting for a
      // player that will never start.
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      final willAutoplay = autoplay && !reduceMotion;
      setState(() {
        _t.trailerAutoplayEnabled = autoplay;
        _t.trailerAmbientVolume = soundOn ? volume.toDouble() : 0;
        // Spinner from here until the backdrop reports first frames (or fails).
        _t.trailerResolving = willAutoplay;
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
      if (_t.allowTrailerFallback &&
          (streams == null || !(streams.playUrl?.isNotEmpty ?? false))) {
        final imdbId = _item.effectiveImdbId;
        if (imdbId != null) {
          streams = await ImdbTrailerService.resolveTrailer(imdbId);
        }
      }
      if (!mounted || !current()) return;
      final playable = streams?.playUrl?.isNotEmpty ?? false;
      setState(() {
        _t.trailerStreams = streams;
        // No playable stream → the backdrop never starts, so stop the spinner
        // here; on success the backdrop's onPlayingChanged(true) clears it once
        // frames actually flow.
        if (!playable) _t.trailerResolving = false;
      });
      if (!playable) return;
      // Safety net: a stream that opens but never renders a first frame would
      // otherwise leave the spinner up forever.
      Future.delayed(const Duration(seconds: 25), () {
        if (current() && _t.trailerResolving) {
          setState(() => _t.trailerResolving = false);
        }
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _t.trailerResolving = false;
          _t.trailerLoading = false;
        });
      }
    }
  }

  void _exitTrailerForeground() {
    if (!_t.trailerForeground) return;
    setState(() => _t.trailerForeground = false);
    // TV: the page content was focus-excluded while the trailer was fullscreen,
    // so nothing holds focus now — re-anchor the remote on the primary action.
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The left-entry node only has a holder when Play or the source pill is
        // present; if neither is (edge config), fall back to traversal so the
        // remote isn't stranded rather than no-op on an unattached node.
        if (detailNodeMounted(_f.leftEntryFocusNode)) {
          _f.leftEntryFocusNode.requestFocus();
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
    if (_t.trailerLoading) return;
    final generation = _t.trailerGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    String? chosen;
    if (_t.trailerCandidates.length > 1) {
      chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose trailer'),
          children: [
            for (final video in _t.trailerCandidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, video.key),
                child: Text(
                  '${video.title}${video.language.isEmpty ? '' : ' · ${video.language}'}',
                ),
              ),
          ],
        ),
      );
      if (!mounted ||
          chosen == null ||
          generation != _t.trailerGeneration ||
          scope != ProfileRuntime.scope.value ||
          revision != MetadataPreferencesService.revision.value) {
        return;
      }
    }
    await _playSelectedTrailer(chosen);
  }

  Future<void> _playSelectedTrailer(String? chosen) async {
    final generation = _t.trailerGeneration;
    final scope = ProfileRuntime.scope.value;
    bool current() =>
        mounted &&
        generation == _t.trailerGeneration &&
        scope == ProfileRuntime.scope.value;
    if ((chosen == null || chosen == _t.trailerYtId) &&
        (_t.backdropKey.currentState?.canPromote ?? false)) {
      setState(() => _t.trailerForeground = true);
      return;
    }

    final ytId = chosen ?? _t.trailerYtId;
    if (ytId == null || _t.trailerLoading) return;

    // Always resolve fresh on tap. The autoplay-prefetched [_trailerStreams] is
    // deliberately NOT reused here: googlevideo URLs carry an `expire` param and
    // go dead after a few hours, so a page left open would hand the player a
    // stale URL. Re-resolving costs one request and keeps playback reliable.
    setState(() => _t.trailerLoading = true);
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
    if (_t.allowTrailerFallback &&
        (streams == null || !(streams.playUrl?.isNotEmpty ?? false))) {
      final imdbId = _item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }

    if (!mounted || !current()) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _t.trailerLoading = false);

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
        fallbackUrl: streams?.muxedPlaybackFallback,
        title: '${_item.name} — Trailer',
        viewMode: PlaylistViewMode.sorted,
      ),
      // Watching the trailer must not suppress the ambient trailer backdrop.
      isTrailer: true,
    );
  }

  VoidCallback? get _metadataExploreAction =>
      metadataPreferences.features.isNotEmpty &&
          widget.onRecommendationTap != null
      ? _openMetadataExplore
      : null;

  void _openMetadataExplore() {
    final prefs = metadataPreferences;
    final onOpen = widget.onRecommendationTap;
    if (prefs.features.isEmpty || onOpen == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MetadataExplorePage(
          item: _item,
          preferences: prefs,
          onOpen: onOpen,
          isTelevision: widget.isTelevision,
        ),
      ),
    );
  }

  @override
  void onMetadataPolicyChanged() {
    _m.detailsMetadataGeneration++;
    if (!mounted) return;
    setState(() {
      _m.imdbExtra = null;
      _m.recommendations = [];
    });
    unawaited(_loadImdbEnrichment());
    unawaited(_loadRecommendations());
    _t.trailerGeneration++;
    setState(() {
      _t.trailerYtId = null;
      _t.trailerCandidates = [];
      _t.trailerStreams = null;
      _t.trailerForeground = false;
      _t.trailerResolving = false;
      _t.trailerLoading = false;
    });
    unawaited(_loadTrailer());
  }

  Future<void> _loadImdbEnrichment() async {
    final generation = _m.detailsMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool valid() =>
        mounted &&
        generation == _m.detailsMetadataGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    final imdbId = _item.effectiveImdbId;
    try {
      final extra = await MetadataDetailsService.instance.enrich(
        _item,
        loadExisting: () async =>
            imdbId == null ? null : ImdbEnrichmentService.fetch(imdbId),
      );
      if (mounted && valid()) setState(() => _m.imdbExtra = extra);
    } catch (_) {}
  }

  Future<void> _loadParentsGuide() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) return;
    try {
      final guide = await ImdbParentsGuideService.fetch(imdbId);
      if (mounted) setState(() => _m.parentsGuide = guide);
    } catch (_) {}
  }

  Future<void> _loadRecommendations() async {
    final generation = _m.detailsMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    final revision = MetadataPreferencesService.revision.value;
    bool valid() =>
        mounted &&
        generation == _m.detailsMetadataGeneration &&
        scope == ProfileRuntime.scope.value &&
        revision == MetadataPreferencesService.revision.value;
    final loader = widget.recommendationsLoader;
    try {
      final recs = await MetadataDetailsService.instance.recommendations(
        _item,
        loader,
      );
      if (mounted && valid()) {
        _m.recommendationOriginals.clear();
        setState(() => _m.recommendations = recs);
      }
      if (!valid()) return;
      await for (final batch in MetadataProviderService.instance.presentBatches(
        recs,
        isRelevant: valid,
      )) {
        if (!valid()) return;
        for (var index = 0; index < batch.length; index++) {
          _m.recommendationOriginals[batch[index]] = recs[index];
        }
        setState(() => _m.recommendations = batch);
      }
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
      _t.trailerAmbientPlaying &&
      !_f.bodyDeep;

  @override
  Widget build(BuildContext context) {
    // Establishes the dependency that makes an ALREADY OPEN detail route
    // re-theme when a token is edited. `_theme` reads the controller directly,
    // which is a plain field read and notifies nobody — without this line the
    // page you edited from would be the last one to change.
    AppThemeScope.of(context);
    // The backdrop is the one display-sized detail hero. Keep the model's
    // catalog URL intact for rails, but ask MetaHub for the large source here.
    final backdropUrl = highQualityArtworkUrl(
      MetadataDetailsService.backdrop(_item, metadataPreferences),
    );
    return PopScope(
      // While the trailer is fullscreen, Back closes it instead of leaving the
      // page — the same player stays alive and settles back into the backdrop.
      canPop: !_t.trailerForeground,
      onPopInvoked: (didPop) {
        if (!didPop) _exitTrailerForeground();
      },
      child: Scaffold(
        backgroundColor: MergedDetailPalette.bg,
        body: Stack(
          children: [
            // Full-bleed backdrop → the Stremio "one lit surface" feel. When a
            // trailer is available and autoplay is on, it crossfades from this
            // static poster into a looping preview (OTT-style), and the
            // Trailer button promotes this same player to fullscreen in place.
            // Non-focusable and behind all content, so DPAD is unaffected.
            Positioned.fill(
              child: HeroTrailerBackdrop(
                key: _t.backdropKey,
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
                videoUrl: _t.trailerAutoplayEnabled && !_f.bodyDeep
                    ? _t.trailerStreams?.playUrl
                    : null,
                audioUrl: _t.trailerAutoplayEnabled && !_f.bodyDeep
                    ? _t.trailerStreams?.audioUrl
                    : null,
                // Resolution and decoder startup already provide a natural
                // poster dwell. Do not stack an artificial wait on top of that.
                startDelay: Duration.zero,
                // Suspend at the Play press, before source/resume resolution.
                // The pipeline loader is a PopupRoute rather than a PageRoute,
                // so RouteAware.didPushNext cannot provide this lifecycle beat.
                enabled: _t.trailerAutoplayEnabled && !_r.playLaunching,
                ambientVolume: _t.trailerAmbientVolume,
                foreground: _t.trailerForeground,
                onRequestClose: _exitTrailerForeground,
                onPlayingChanged: (playing) {
                  if (!mounted) return;
                  setState(() {
                    _t.trailerAmbientPlaying = playing;
                    _t.trailerResolving = false;
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
                excluding: _t.trailerForeground,
                child: IgnorePointer(
                  ignoring: _t.trailerForeground,
                  child: AnimatedOpacity(
                    opacity: _t.trailerForeground ? 0 : 1,
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
                        if (_f.focusedStillUrl != null &&
                            !_t.trailerForeground &&
                            !_t.trailerAmbientPlaying)
                          Positioned.fill(
                            child: MergedAmbientStill(
                              url: _f.focusedStillUrl!,
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
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.10,
                                        ),
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.24,
                                        ),
                                      ]
                                    : [
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.60,
                                        ),
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.88,
                                        ),
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
                                  end: _m.accent.withValues(
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
                                focusNode: _f.backButtonFocusNode,
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
            if (_t.trailerAmbientPlaying && !_t.trailerForeground)
              Positioned(
                left: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(widget.isTelevision ? 20 : 12),
                    child: MergedTrailerPlayingChip(
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

  /// Called from every path that can change a binding — the source manager,
  /// the app-action menu, and playback return. A band that only refreshes on
  /// one of the three is stale the first time someone uses another.
  Future<void> _loadBoundSources() async {
    final imdb = _item.imdbId;
    if (imdb == null || imdb.isEmpty) return;
    final list = await SeriesSourceService.getSources(imdb);
    if (!mounted) return;
    setState(() => _b.boundSources = list);
  }

  /// and tab state.
  DetailModel _buildDetailModel() {
    return DetailModel(
      item: _item,
      metadataPreferences: metadataPreferences,
      isMovie: _isMovie,
      isTelevision: widget.isTelevision,
      // Signal keeps the poster-extracted accent, which is what ships today.
      // A fixed-palette theme (Noir's white, Phosphor's amber) would be
      // contaminated by it, so it uses its own.
      accent: _theme.useArtworkAccent ? _m.accent : _theme.accent,
      imdbExtra: _m.imdbExtra,
      parentsGuide: _m.parentsGuide,
      recommendations: _m.recommendations ?? const [],
      openingDataReady: _m.showcaseOpeningDataReady,
      primaryLabel: _primaryLabel,
      primaryBusy: _primaryBusy,
      sourceCount: widget.boundSourceCount?.call(widget.item) ?? 0,
      boundSources: _b.boundSources,
      hasTrailer: _t.trailerYtId != null,
      trailerBusy: _t.trailerResolving || _t.trailerLoading,
      trailerPlaying: _t.trailerAmbientPlaying,
      hasTrakt: _traktOnlyMenuOptions.isNotEmpty,
      traktTracked: _traktTracked,
      traktLabel: _traktPillLabel,
      traktRating: _k.traktStatus?.rating,
      hasSimkl: _menuOptionsSimkl.isNotEmpty,
      simklTracked: _simklTracked,
      simklLabel: _simklPillLabel,
      simklRating: _k.simklStatus?.rating,
      hasMdblist: _menuOptionsMdblist.isNotEmpty,
      mdblistTracked: _mdblistTracked,
      mdblistLabel: _mdblistPillLabel,
      mdblistRating: _k.mdblistStatus?.rating,
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
                _appMenuOptions.any(
                  (o) => o.action == TraktItemMenuAction.searchPacks,
                ))
          ? () => widget.onTraktAction!(TraktItemMenuAction.searchPacks)
          : null,
      onTrailer: _playTrailer,
      onSelectSource: widget.onSelectSource == null
          ? null
          : () async {
              await widget.onSelectSource!(widget.item);
              if (mounted) setState(() {});
            },
      onMetadataExplore: _metadataExploreAction,
      onAppMenu: (_appMenuOptions.isNotEmpty && widget.onTraktAction != null)
          ? _showAppActionsMenu
          : null,
      onTraktMenu: widget.onTraktAction != null ? _showQuickActionsMenu : null,
      onSimklMenu: widget.onSimklAction != null
          ? _showSimklQuickActionsMenu
          : null,
      onMdblistMenu: widget.onMdblistAction != null
          ? _showMdblistQuickActionsMenu
          : null,
      inMyWatchlist: _k.inMyWatchlist,
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
                : (_menuOptionsMdblist.isNotEmpty &&
                          widget.onMdblistAction != null
                      ? _showMdblistQuickActionsMenu
                      : null)),
      // Only when Trakt already took the first slot; otherwise Simkl IS the
      // first slot above and this would mount the same sheet twice.
      onTrackersSecondary:
          (_traktOnlyMenuOptions.isNotEmpty &&
              widget.onTraktAction != null &&
              _menuOptionsSimkl.isNotEmpty &&
              widget.onSimklAction != null)
          ? _showSimklQuickActionsMenu
          : (((_traktOnlyMenuOptions.isNotEmpty &&
                        widget.onTraktAction != null) ||
                    (_menuOptionsSimkl.isNotEmpty &&
                        widget.onSimklAction != null)) &&
                _menuOptionsMdblist.isNotEmpty &&
                widget.onMdblistAction != null)
          ? _showMdblistQuickActionsMenu
          : null,
      onTrackersTertiary:
          (_traktOnlyMenuOptions.isNotEmpty &&
              widget.onTraktAction != null &&
              _menuOptionsSimkl.isNotEmpty &&
              widget.onSimklAction != null &&
              _menuOptionsMdblist.isNotEmpty &&
              widget.onMdblistAction != null)
          ? _showMdblistQuickActionsMenu
          : null,
      // There is no per-source host API, so a card in the Sources band and the
      // "Find sources" tile both land on the title-level manager — and the
      // band reloads afterwards, since binding is exactly what changes it.
      onManageSources: widget.onSelectSource == null
          ? null
          : () async {
              await widget.onSelectSource!(widget.item);
              if (!mounted) return;
              setState(() {});
              await _loadBoundSources();
            },
      onRecommendationTap: widget.onRecommendationTap == null
          ? null
          : _openMetadataRecommendation,
      onAmbientStill: (url) {
        if (!mounted || _f.focusedStillUrl == url) return;
        setState(() => _f.focusedStillUrl = url);
      },
      onDepth: (deep) {
        if (!mounted || _f.bodyDeep == deep) return;
        setState(() => _f.bodyDeep = deep);
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
            node: _f.infoPaneScope,
            onKeyEvent: _handleInfoPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    MergedDetailPalette.bg.withValues(alpha: 0.82),
                    MergedDetailPalette.bg.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: _buildInfoPane(),
            ),
          ),
        ),
        Expanded(
          child: FocusScope(
            node: _f.episodesPaneScope,
            onKeyEvent: _handleEpisodesPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0E0B14).withValues(alpha: 0.82),
                border: Border(
                  left: BorderSide(color: MergedDetailPalette.hair),
                ),
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
    final scope = _f.episodesPaneScope;
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
        _f.backButtonFocusNode.requestFocus();
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
          detailNodeMounted(_f.leftEntryFocusNode)) {
        _f.leftEntryFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInfoPane() {
    final item = _item;
    final extra = _m.imdbExtra;
    final t = _tight;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = MetadataDetailsService.informationGenres(
      item,
      extra,
      metadataPreferences,
    );
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
      controller: _f.infoScroll,
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
          MergedStaggerReveal(
            key: const ValueKey('rev-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              _isMovie ? 'MOVIE' : 'SERIES',
              style: TextStyle(
                color: _m.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          SizedBox(height: t ? 5 : 8),
          MergedStaggerReveal(
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
          MergedStaggerReveal(
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
            MergedStaggerReveal(
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
          MergedStaggerReveal(
            key: const ValueKey('rev-actions'),
            delayMs: 220,
            enabled: animate,
            child: MergedScrollAnchor(
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
    final extra = _m.imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = MetadataDetailsService.informationGenres(
      item,
      extra,
      metadataPreferences,
    );

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
          MergedStaggerReveal(
            key: const ValueKey('rev-h-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              'SERIES',
              style: TextStyle(
                color: _m.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          MergedStaggerReveal(
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
          MergedStaggerReveal(
            key: const ValueKey('rev-h-meta'),
            delayMs: 110,
            enabled: animate,
            child: _buildMetaBar(year, extra, rating),
          ),
          // Tracker state lives in the action-row pills (see the info pane).
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            MergedStaggerReveal(
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
          MergedStaggerReveal(
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

    final runtime = MetadataDetailsService.informationRuntime(
      _item,
      extra,
      metadataPreferences,
    );
    if (runtime != null) add(_metaText(runtime));
    if (year != null && year.isNotEmpty) add(_metaText(year));
    final cert = extra?.certificate;
    if (cert != null) {
      add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: MergedDetailPalette.glass2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: MergedDetailPalette.hair),
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
                color: MergedDetailPalette.imdb,
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
    final s = _k.traktStatus;
    return s != null &&
        (s.inWatchlist ||
            s.inCollection ||
            s.titleWatched == true ||
            s.rating != null);
  }

  bool get _simklTracked =>
      _k.simklStatus?.currentStatus != null || _k.simklStatus?.rating != null;

  bool get _mdblistTracked {
    final s = _k.mdblistStatus;
    return s != null &&
        (s.inWatchlist ||
            s.collected ||
            s.watched ||
            s.completed == true ||
            s.dropped == true ||
            s.rating != null);
  }

  /// The live Trakt state, compressed to fit inside the pill. Trakt allows
  /// several relationships at once, so they're joined with "·" and capped at
  /// two — the rating rides in the pill's own compartment, not here.
  ///
  /// While the loader is still out this reads "Checking…" rather than "Not
  /// tracked": the row keeps its geometry either way, and asserting the title
  /// *isn't* on your watchlist when it is — for however long the call takes —
  /// is worse than admitting we don't know yet.
  String get _traktPillLabel {
    final s = _k.traktStatus;
    if (s == null &&
        !_k.traktStatusResolved &&
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
    final status = _k.simklStatus?.currentStatus;
    if (status != null) return MergedDetailSimklLabels.simklStatusLabel(status);
    if (_k.simklStatus?.rating != null) return 'Rated';
    if (!_k.simklStatusResolved && widget.simklStatusLoader != null) {
      return 'Checking…';
    }
    return 'Not tracked';
  }

  String get _mdblistPillLabel {
    final s = _k.mdblistStatus;
    if (s == null &&
        !_k.mdblistStatusResolved &&
        widget.mdblistStatusLoader != null) {
      return 'Checking…';
    }
    if (s == null) return 'Not tracked';
    final parts = <String>[
      if (s.inWatchlist) 'Watchlist',
      if (s.collected) 'Collected',
      if (s.completed == true || s.watched) 'Watched',
      if (s.dropped == true) 'Dropped',
    ];
    if (parts.isEmpty) return s.rating == null ? 'Not tracked' : 'Rated';
    return parts.take(2).join(' · ');
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
    final count = widget.boundSourceCount?.call(widget.item) ?? 0;
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
          MergedPrimaryButton(
            label: _primaryLabel,
            busy: _primaryBusy,
            icon: Icons.play_arrow_rounded,
            onTap: _playPrimary,
            onLongPress:
                ((_isMovie && widget.onBrowse != null) ||
                    (!_isMovie && widget.onBrowsePrimaryEpisodeSources != null))
                ? _browsePrimarySources
                : null,
            focusNode: _f.leftEntryFocusNode,
            autofocus: widget.isTelevision && _isMovie,
            glow: _m.accent,
          ),
        // Trailer — sits right after Play. Only when Cinemeta gave us a YouTube
        // trailer id. Reflects the ambient backdrop's state: spinner while the
        // trailer loads, "Watch Trailer" once it's playing (tap = fullscreen),
        // plain "Trailer" otherwise (tap = resolve & play).
        if (_t.trailerYtId != null)
          MergedGhostButton(
            label: _t.trailerAmbientPlaying ? 'Watch Trailer' : 'Trailer',
            icon: _t.trailerAmbientPlaying
                ? Icons.play_circle_outline_rounded
                : Icons.movie_outlined,
            busy: _t.trailerResolving || _t.trailerLoading,
            onTap: _playTrailer,
          ),
        // Movie: a Sources (manual list) button — the episode list is the
        // picker for series, so this is movie-only.
        if (_isMovie && widget.onBrowse != null)
          MergedGhostButton(
            label: 'Sources',
            icon: Icons.layers_rounded,
            onTap: widget.onBrowse!,
          ),
        if (_supportsMyWatchlist)
          MergedGhostButton(
            label: _k.inMyWatchlist ? 'In My Watchlist' : 'My Watchlist',
            icon: _k.inMyWatchlist
                ? Icons.bookmark_rounded
                : Icons.bookmark_add_outlined,
            onTap: _toggleMyWatchlist,
          ),
        // Source binding. Takes the LEFT-entry focus node only when Play is
        // hidden (PikPak), so LEFT from an episode always lands on a live target.
        if (widget.onSelectSource != null)
          MergedSourcePill(
            count: count,
            focusNode: widget.showQuickPlay ? null : _f.leftEntryFocusNode,
            // A movie with Play hidden (PikPak-only) has no episode list to
            // auto-focus and no Play to autofocus — start the remote here.
            autofocus: widget.isTelevision && _isMovie && !widget.showQuickPlay,
            onTap: () async {
              await widget.onSelectSource!(widget.item);
              if (mounted) setState(() {});
            },
          ),
        // Debrify's own actions (bind source, Stremio TV, random episode,
        // season packs, local Continue Watching) — no tracker involved, so a
        // neutral button rather than a branded one.
        if (_metadataExploreAction != null)
          MergedRoundIconButton(
            icon: Icons.explore_outlined,
            tooltip: 'Explore',
            onTap: _metadataExploreAction!,
          ),
        if (_appMenuOptions.isNotEmpty && widget.onTraktAction != null)
          MergedRoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onTap: _showAppActionsMenu,
          ),
        // Trakt — a branded pill that *carries* the live status (the status
        // chips that used to sit under the title are folded into it, so one
        // control both shows and changes the relationship).
        if (_traktOnlyMenuOptions.isNotEmpty && widget.onTraktAction != null)
          MergedTrackerPill(
            mark: TraktMark(size: 21, opacity: _traktTracked ? 1 : 0.55),
            brand: 'TRAKT',
            state: _traktPillLabel,
            rating: _k.traktStatus?.rating,
            accent: kTraktRed,
            tracked: _traktTracked,
            tooltip: 'Trakt options',
            onTap: _showQuickActionsMenu,
          ),
        // Simkl's own pill — a separate button/sheet, not merged with Trakt's,
        // so nothing here touches the button above.
        if (_menuOptionsSimkl.isNotEmpty && widget.onSimklAction != null)
          MergedTrackerPill(
            mark: SimklMark(size: 21, opacity: _simklTracked ? 1 : 0.55),
            brand: 'SIMKL',
            state: _simklPillLabel,
            rating: _k.simklStatus?.rating,
            accent: kSimklCyan,
            tracked: _simklTracked,
            tooltip: 'Simkl options',
            onTap: _showSimklQuickActionsMenu,
          ),
        if (_menuOptionsMdblist.isNotEmpty && widget.onMdblistAction != null)
          MergedTrackerPill(
            mark: MdblistMark(size: 21, opacity: _mdblistTracked ? 1 : 0.55),
            brand: 'MDBLIST',
            state: _mdblistPillLabel,
            rating: _k.mdblistStatus?.rating,
            accent: kMdblistPurple,
            tracked: _mdblistTracked,
            tooltip: 'MDBList options',
            onTap: _showMdblistQuickActionsMenu,
          ),
      ],
    );
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
      builder: (sheetCtx) => MergedQuickActionsMenu(
        title: _item.name,
        options: options,
        isTelevision: widget.isTelevision,
        onSelected: (action) async {
          Navigator.of(sheetCtx).pop();
          await widget.onTraktAction?.call(action);
          if (mounted && action == TraktItemMenuAction.clearWatchProgress) {
            _refreshAfterPlayback();
          }
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
      builder: (sheetCtx) => MergedTraktSheet(
        title: _item.name,
        isTelevision: widget.isTelevision,
        status: _k.traktStatus,
        optionsFor: (status) => [
          for (final o
              in widget.traktMenuBuilder?.call(status) ??
                  widget.traktMenuOptions)
            if (!appOwnedActions.contains(o.action)) o,
        ],
        onAction: (action) async {
          await widget.onTraktAction?.call(action);
          if (mounted && action == TraktItemMenuAction.clearTraktProgress)
            _refreshAfterPlayback();
        },
        onRate: widget.onTraktRate,
        statusLoader: widget.traktStatusLoader,
        // Keep the pill in sync with whatever the sheet did while it was open.
        onChanged: (status) {
          if (mounted) {
            setState(() {
              _k.traktStatus = status;
              _k.traktStatusResolved = true;
            });
          }
        },
      ),
    );
  }

  /// Simkl's own sheet — mirrors [_showQuickActionsMenu], but Simkl's five
  /// statuses are mutually exclusive, so they render as an exclusive toggle
  /// group instead of a list of "Move to X" commands.
  void _showSimklQuickActionsMenu() {
    if (_menuOptionsSimkl.isEmpty || widget.onSimklAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => MergedSimklSheet(
        title: _item.name,
        isTelevision: widget.isTelevision,
        status: _k.simklStatus,
        optionsFor: (status) =>
            widget.simklMenuBuilder?.call(status) ?? widget.simklMenuOptions,
        onAction: (action) async {
          await widget.onSimklAction?.call(action);
          if (mounted && action == SimklItemMenuAction.clearWatchProgress)
            _refreshAfterPlayback();
        },
        onRate: widget.onSimklRate,
        statusLoader: widget.simklStatusLoader,
        onChanged: (status) {
          if (mounted) {
            setState(() {
              _k.simklStatus = status;
              _k.simklStatusResolved = true;
            });
          }
        },
      ),
    );
  }

  void _showMdblistQuickActionsMenu() {
    if (_menuOptionsMdblist.isEmpty || widget.onMdblistAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).sheetSurface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text(
                _item.name,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'MDBList',
                style: TextStyle(
                  color: kMdblistPurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in _menuOptionsMdblist)
                ListTile(
                  leading: Icon(option.icon, color: option.color),
                  title: Text(option.label),
                  onTap: () async {
                    await widget.onMdblistAction?.call(option.action);
                    if (mounted &&
                        option.action ==
                            MdblistItemMenuAction.clearWatchProgress)
                      _refreshAfterPlayback();
                    await _loadMdblistStatus();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
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
      key: _f.episodesPanelKey,
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
          ? () => _f.leftEntryFocusNode.requestFocus()
          : null,
      onBack: () => Navigator.of(context).maybePop(),
      // Direct-source mode (Xtream IPTV series) — pass-throughs.
      seasonsLoader: widget.seasonsLoader,
      onPlayEpisode: widget.onPlayEpisode == null ? null : _playDirectEpisode,
      watchProgressLoader: widget.watchProgressLoader,
      onNextEpisodeChanged: _onNextEpisodeChanged,
      onSeriesCompletedChanged: (completed) {
        if (mounted && completed != _r.seriesDone) {
          setState(() => _r.seriesDone = completed);
        }
      },
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
      backgroundColor: MergedDetailPalette.bg,
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
    final extra = _m.imdbExtra;
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
              color: MergedDetailPalette.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MergedDetailPalette.gold.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 15,
                  color: MergedDetailPalette.gold,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    awardsLine,
                    style: const TextStyle(
                      color: MergedDetailPalette.gold,
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
          MergedScrollAnchor(
            active: widget.isTelevision,
            alignment: 0.35,
            child: SizedBox(
              height: 92,
              child: _focusRail(
                controller: _f.castRailScroll,
                gap: 14,
                cards: [for (final m in cast) _castTile(m)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    sections.add(
      MetadataFranchiseRail(
        item: _item,
        onOpen: widget.onRecommendationTap == null
            ? null
            : _openMetadataRecommendation,
        isTelevision: widget.isTelevision,
      ),
    );

    // More Like This — placed high (right after Cast) so it's an easy DPAD-down
    // reach, ahead of the long focusable Parents-Guide list.
    final recs = (_m.recommendations ?? const <StremioMeta>[])
        .take(10)
        .toList();
    if (recs.isNotEmpty && widget.onRecommendationTap != null) {
      sections
        ..add(_sectionLabel('More Like This'))
        ..add(const SizedBox(height: 12))
        ..add(
          MergedScrollAnchor(
            active: widget.isTelevision,
            alignment: 0.5,
            child: SizedBox(
              height: 168,
              child: _focusRail(
                controller: _f.recommendationRailScroll,
                gap: 11,
                cards: [for (final r in recs) _recCard(r)],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 22));
    }

    final guide = _m.parentsGuide;
    if (guide != null && !guide.isEmpty) {
      sections
        ..add(_sectionLabel('Parents Guide'))
        ..add(const SizedBox(height: 12))
        ..add(
          ParentsGuideSection(
            guide: guide,
            tv: widget.isTelevision,
            dense: true,
            accent: _m.accent,
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
              MergedRailEdgeTrap(
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

  Widget _castTile(CastMember m) =>
      MergedCastTile(member: m, fallback: MergedDetailPalette.glass2);

  Widget _recCard(StremioMeta rec) => MergedRecCard(
    rec: rec,
    fallback: MergedDetailPalette.glass2,
    onTap: () => _openMetadataRecommendation(rec),
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
      color: MergedDetailPalette.glass2,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: MergedDetailPalette.hair),
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
    return MergedRoundIconButton(
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

/// Frozen original-code characterization seam; callbacks remain direct tear-offs.
@visibleForTesting
Map<String, Object?> mergedDetailTestAccess(State<MergedDetailScreen> state) {
  final s = state as _MergedDetailScreenState;
  return {
    'model': s._buildDetailModel,
    'nextEpisode': s._onNextEpisodeChanged,
    'loadResume': s._loadResumeInfo,
    'rewatch': s._rewatchTitle,
    'refresh': s._refreshAfterPlayback,
    'recommendations': s._parts.metadataState.recommendations,
    'recommendationOriginals': s._parts.metadataState.recommendationOriginals,
    'backdropKey': s._parts.trailerState.backdropKey,
    'episodesPanelKey': s._parts.focusState.episodesPanelKey,
    'infoScroll': s._parts.focusState.infoScroll,
    'castRailScroll': s._parts.focusState.castRailScroll,
    'recommendationRailScroll': s._parts.focusState.recommendationRailScroll,
    'leftEntry': s._parts.focusState.leftEntryFocusNode,
    'infoPane': s._parts.focusState.infoPaneScope,
    'episodesPane': s._parts.focusState.episodesPaneScope,
    'backButton': s._parts.focusState.backButtonFocusNode,
    'movieGeneration': s._parts.trackingState.movieCompletionGeneration,
    'trailerGeneration': s._parts.trailerState.trailerGeneration,
    'metadataGeneration': s._parts.metadataState.detailsMetadataGeneration,
  };
}
