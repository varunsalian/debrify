import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_loading.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_parts.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_watchlist_actions.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/settings/detail_page_style_page.dart'
    show effectiveDetailPageStyle;
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/app_route_observer.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

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
    final deps = MergedDetailDependencies(
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      item: () => widget.item,
      addon: () => widget.addon,
      isTelevision: () => widget.isTelevision,
      showQuickPlay: () => widget.showQuickPlay,
      isTraktSource: () => widget.isTraktSource,
      isMdblistSource: () => widget.isMdblistSource,
      onResume: () => widget.onResume,
      onRewatch: () => widget.onRewatch,
      resumeInfoLoader: () => widget.resumeInfoLoader,
      onBrowse: () => widget.onBrowse,
      onItemSelected: () => widget.onItemSelected,
      onQuickPlay: () => widget.onQuickPlay,
      onBrowsePrimaryEpisodeSources: () => widget.onBrowsePrimaryEpisodeSources,
      boundSourceCount: () => widget.boundSourceCount,
      onSelectSource: () => widget.onSelectSource,
      traktMenuOptions: () => widget.traktMenuOptions,
      traktMenuBuilder: () => widget.traktMenuBuilder,
      onTraktAction: () => widget.onTraktAction,
      traktStatusLoader: () => widget.traktStatusLoader,
      simklMenuOptions: () => widget.simklMenuOptions,
      simklMenuBuilder: () => widget.simklMenuBuilder,
      onSimklAction: () => widget.onSimklAction,
      simklStatusLoader: () => widget.simklStatusLoader,
      mdblistMenuOptions: () => widget.mdblistMenuOptions,
      mdblistMenuBuilder: () => widget.mdblistMenuBuilder,
      onMdblistAction: () => widget.onMdblistAction,
      mdblistStatusLoader: () => widget.mdblistStatusLoader,
      onTraktRate: () => widget.onTraktRate,
      onSimklRate: () => widget.onSimklRate,
      onMdblistRate: () => widget.onMdblistRate,
      recommendationsLoader: () => widget.recommendationsLoader,
      onRecommendationTap: () => widget.onRecommendationTap,
      metaEnricher: () => widget.metaEnricher,
      heroTag: () => widget.heroTag,
      initialSeason: () => widget.initialSeason,
      initialEpisode: () => widget.initialEpisode,
      seasonsLoader: () => widget.seasonsLoader,
      onPlayEpisode: () => widget.onPlayEpisode,
      watchProgressLoader: () => widget.watchProgressLoader,
      focusCoordinator: () => _focusCoordinator,
      presentedItem: () => _item,
      refreshAfterPlayback: _refreshAfterPlayback,
      style: () => _style,
      metadataPreferences: () => metadataPreferences,
      refreshMetadataPresentation: refreshMetadataPresentation,
    );
    _parts = MergedDetailParts(deps);
    deps.parts = _parts;
  }
  MergedDetailFocusState get _f => _parts.focusState;
  MergedDetailMetadataLoading get _ml => _parts.metadataLoading;
  MergedDetailMetadataState get _m => _parts.metadataState;
  MergedDetailModelFactory get _b => _parts.modelFactory;
  MergedDetailResumeActions get _ra => _parts.resumeActions;
  MergedDetailResumeState get _r => _parts.resumeState;
  MergedDetailTrackingActions get _ta => _parts.trackingActions;
  MergedDetailTrailerActions get _tr => _parts.trailerActions;
  MergedDetailWatchlistActions get _wa => _parts.watchlistActions;

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

  @override
  void initState() {
    super.initState();
    TrackingSourceStorage.trackingSourceRevision.addListener(
      _ta.onMovieProgressPolicyChanged,
    );
    MovieProgressStorage.movieFinishedRevision.addListener(
      _ta.loadLocalMovieFinished,
    );
    MdblistService.instance.watchedRevision.addListener(
      _ta.loadLocalMovieFinished,
    );
    AnalyticsService.screenView('series_detail');
    MainPageBridge.addPlaybackReturnListener(_onPlaybackReturned);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ml.loadShowcaseOpeningData();
      _tr.loadTrailer();
      _ml.loadAccent();
      _ra.loadResumeInfo();
      _ta.loadTraktStatus();
      _ta.loadSimklStatus();
      _ta.loadMdblistStatus();
      _ta.loadLocalMovieFinished();
      _wa.loadMyWatchlistState();
    });
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
    _ra.loadResumeInfo();
    // Watched state (and thus the resume label / badges) may have changed while
    // away — re-read the Trakt status too.
    _ta.loadTraktStatus();
    _ta.loadSimklStatus();
    _ta.loadMdblistStatus();
    _ta.loadLocalMovieFinished();
    _wa.loadMyWatchlistState();
    // And the episode list's ticks/progress: episode quick-play now plays on
    // top of this screen (like Resume), so the list is still alive when the
    // player returns and must reflect the session that just ended.
    _f.episodesPanelKey.currentState?.refreshWatchProgress();
    // Sources can be bound from inside the player's own source picker and from
    // the app-action menu, so returning here is the only place that catches
    // both. Cheap — a prefs read, not a network call.
    unawaited(_b.loadBoundSources());
  }

  @override
  void dispose() {
    TrackingSourceStorage.trackingSourceRevision.removeListener(
      _ta.onMovieProgressPolicyChanged,
    );
    MovieProgressStorage.movieFinishedRevision.removeListener(
      _ta.loadLocalMovieFinished,
    );
    MdblistService.instance.watchedRevision.removeListener(
      _ta.loadLocalMovieFinished,
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

  @override
  void onMetadataPolicyChanged() =>
      _parts.metadataLoading.onMetadataPolicyChanged();

  @override
  Widget build(BuildContext context) => _parts.rootLayout.build(context);
}

/// Frozen original-code characterization seam; callbacks remain direct tear-offs.
@visibleForTesting
Map<String, Object?> mergedDetailTestAccess(State<MergedDetailScreen> state) {
  final s = state as _MergedDetailScreenState;
  return {
    'model': s._parts.modelFactory.buildDetailModel,
    'nextEpisode': s._parts.resumeActions.onNextEpisodeChanged,
    'loadResume': s._parts.resumeActions.loadResumeInfo,
    'rewatch': s._parts.playbackActions.rewatchTitle,
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
