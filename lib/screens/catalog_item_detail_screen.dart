import 'dart:async';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_bound_sources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_parts.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_watchlist.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter/material.dart';
import '../models/play_loader_art.dart';
import '../models/stremio_addon.dart';
import '../services/analytics_service.dart';
import '../services/app_route_observer.dart';
import '../services/main_page_bridge.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../services/simkl/simkl_service.dart';
import '../widgets/metadata_presentation_mixin.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';

/// Cinematic detail screen for a catalog item.
///
/// Shows the backdrop hero with a dark scrim, title and metadata, the full
/// description, and primary/secondary actions (Play + Browse Sources).
/// Designed to look premium on phone, tablet, and TV with D-pad support.
class CatalogItemDetailScreen extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final bool showQuickPlay;
  final bool hasBoundSource;

  /// Triggers the primary play action.
  final VoidCallback onPlay;
  final VoidCallback? onRewatch;

  /// Hands the host this title's loader artwork (backdrop, logo, meta line) as
  /// it resolves, so a Play pressed from here opens the Marquee loader with the
  /// enriched art rather than the sparse catalog row. Fires on mount and again
  /// after each enrichment lands; the host keeps the latest. Presentation only
  /// — a host that ignores it just gets the plain loader.
  final ValueChanged<PlayLoaderArt>? onLoaderArt;

  /// Resolves whether the title has prior progress and, for a series, the
  /// season/episode [onPlay] would land on — so the button can read
  /// "Start Watching" vs "Resume · S3E4". Null keeps the static "Play" label.
  final Future<({bool started, int? season, int? episode})> Function()?
  resumeInfoLoader;

  /// Opens the sources/episodes flow (was "Sources" / "Episodes" in the list).
  final VoidCallback onBrowse;

  /// Opens manual sources for the same episode the primary Play/Resume action
  /// would choose. When null, series Play remains tap-only; movies reuse
  /// [onBrowse] directly because that already is their Sources action.
  final Future<void> Function()? onBrowsePrimaryEpisodeSources;

  /// False for detail surfaces whose [onBrowse] is not a source browser (for
  /// example Stremio TV channel details, where both buttons play the channel).
  final bool enablePrimarySourcesHold;

  /// Trakt actions. When non-empty a "More" button appears next to
  /// Play/Browse and opens the cinematic action sheet.
  final List<TraktMenuOption> traktMenuOptions;

  /// Invoked when the user picks a Trakt action from the "More" sheet.
  final void Function(TraktItemMenuAction action)? onTraktAction;

  /// Simkl actions — renders as its own independent quick-actions section
  /// next to Trakt's, not merged (both trackers run in parallel).
  final List<SimklMenuOption> simklMenuOptions;
  final void Function(SimklItemMenuAction action)? onSimklAction;
  final List<MdblistMenuOption> mdblistMenuOptions;
  final void Function(MdblistItemMenuAction action)? onMdblistAction;

  /// Loads the item's live Simkl watchlist status. Used only to relabel the
  /// primary button "Rewatch" (instead of "Play") for a movie already marked
  /// `completed` — a completed movie has no Simkl resume session, so the play
  /// path un-marks it watched first so the rewatch re-enters Continue Watching.
  /// Null (disconnected / no IMDb id) keeps the plain "Play" label.
  final Future<SimklTitleStatus?> Function()? simklStatusLoader;

  /// Lazily loads "Watch Next" recommendations for [item]. When null (no
  /// recommendation-capable addon, or this host doesn't support it) the
  /// rail is omitted entirely. Resolves to an empty list to omit it too.
  final Future<List<StremioMeta>> Function()? recommendationsLoader;

  /// Invoked when the user selects a recommended title from the rail.
  final void Function(StremioMeta recommendation)? onRecommendationTap;

  /// Lazily fetches catalog-quality metadata for [item] by IMDb id. Used to
  /// enrich sparse items (e.g. a tapped "Watch Next" recommendation, which
  /// arrives without year/rating/genres and a raw addon-formatted overview)
  /// so the screen renders identically to a normal catalog open. Null skips
  /// enrichment; resolving to null leaves the original item untouched.
  final Future<StremioMeta?> Function(String imdbId, String type)? metaEnricher;

  const CatalogItemDetailScreen({
    super.key,
    required this.item,
    required this.onPlay,
    this.onRewatch,
    required this.onBrowse,
    this.onBrowsePrimaryEpisodeSources,
    this.enablePrimarySourcesHold = true,
    this.onLoaderArt,
    this.resumeInfoLoader,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.hasBoundSource = false,
    this.traktMenuOptions = const [],
    this.onTraktAction,
    this.simklMenuOptions = const [],
    this.onSimklAction,
    this.mdblistMenuOptions = const [],
    this.onMdblistAction,
    this.simklStatusLoader,
    this.recommendationsLoader,
    this.onRecommendationTap,
    this.metaEnricher,
  });

  @override
  State<CatalogItemDetailScreen> createState() =>
      _CatalogItemDetailScreenState();
}

class _CatalogItemDetailScreenState extends State<CatalogItemDetailScreen>
    with
        SingleTickerProviderStateMixin,
        RouteAware,
        MetadataPresentationMixin<CatalogItemDetailScreen> {
  late final CatalogDetailParts _parts;

  _CatalogItemDetailScreenState() {
    final deps = CatalogDetailDependencies(
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      item: () => widget.item,
      isTelevision: () => widget.isTelevision,
      showQuickPlay: () => widget.showQuickPlay,
      onPlay: () => widget.onPlay,
      onRewatch: () => widget.onRewatch,
      onLoaderArt: () => widget.onLoaderArt,
      resumeInfoLoader: () => widget.resumeInfoLoader,
      onBrowse: () => widget.onBrowse,
      onBrowsePrimaryEpisodeSources: () => widget.onBrowsePrimaryEpisodeSources,
      enablePrimarySourcesHold: () => widget.enablePrimarySourcesHold,
      traktMenuOptions: () => widget.traktMenuOptions,
      onTraktAction: () => widget.onTraktAction,
      simklMenuOptions: () => widget.simklMenuOptions,
      onSimklAction: () => widget.onSimklAction,
      mdblistMenuOptions: () => widget.mdblistMenuOptions,
      onMdblistAction: () => widget.onMdblistAction,
      simklStatusLoader: () => widget.simklStatusLoader,
      recommendationsLoader: () => widget.recommendationsLoader,
      onRecommendationTap: () => widget.onRecommendationTap,
      metaEnricher: () => widget.metaEnricher,
      presentedItem: () => _item,
      metadataPreferences: () => metadataPreferences,
      refreshMetadataPresentation: refreshMetadataPresentation,
      revealController: () => _revealCtrl,
      hasBoundSource: () => _hasBoundSource,
      writeHasBoundSource: (value) => _hasBoundSource = value,
    );
    _parts = CatalogDetailParts(deps);
    deps.parts = _parts;
  }

  CatalogDetailResources get _f => _parts.resources;
  CatalogDetailMetadata get _m => _parts.metadata;
  CatalogDetailWatchlist get _w => _parts.watchlist;
  CatalogDetailPrimaryAction get _p => _parts.primaryAction;
  CatalogDetailBoundSources get _b => _parts.boundSources;

  /// The item the screen renders — the enriched copy once available,
  /// otherwise whatever the host handed us.
  @override
  StremioMeta get originalMetadata => _m.enriched ?? widget.item;

  StremioMeta get _item => presentedMetadata!;

  /// Drives the staggered entrance reveal of the content sections.
  late final AnimationController _revealCtrl;

  /// Live bound-source flag (drives the Play button's "pinned" accent). Seeded
  /// from the parent's snapshot, then re-read when the player route pops back
  /// onto this screen — so playing a movie (which auto-binds its source) flips
  /// the accent on immediately instead of staying stale until reopen.
  late bool _hasBoundSource = widget.hasBoundSource;

  @override
  void initState() {
    super.initState();
    TrackingSourceStorage.trackingSourceRevision.addListener(
      _p.onMovieProgressPolicyChanged,
    );
    MovieProgressStorage.movieFinishedRevision.addListener(
      _p.loadLocalMovieFinished,
    );
    MdblistService.instance.watchedRevision.addListener(
      _p.loadLocalMovieFinished,
    );
    AnalyticsService.screenView('catalog_detail');
    MainPageBridge.addPlaybackReturnListener(_onPlaybackReturned);
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // TVs are low-powered — skip the staggered entrance reveal entirely
    // (jump straight to the final state, controller stays idle).
    if (widget.isTelevision) _revealCtrl.value = 1.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // What we know before enrichment — usually just the backdrop. Emitted
      // now so a Play pressed in the first second still gets a plate.
      _m.emitLoaderArt();
      if (!widget.isTelevision) _revealCtrl.forward();
      // Land focus on Play (or Sources when Play is hidden, e.g. PikPak) so
      // the remote has a starting point. TV only — on mobile/desktop an
      // auto-applied golden focus border just looks out of place.
      if (widget.isTelevision) {
        (widget.showQuickPlay ? _f.playFocus : _f.browseFocus).requestFocus();
      }
      _m.loadRecommendations();
      _m.loadEnrichedMeta();
      _m.loadArtworkAccent();
      _m.loadParentsGuide();
      _m.loadImdbEnrichment();
      _p.loadResumeInfo();
      _p.loadSimklStatus();
      _p.loadLocalMovieFinished();
      _w.loadMyWatchlistState();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  /// The IN-APP player pushes on top of this detail screen, so it pops BACK
  /// here when playback ends. Re-read the binding then: a movie auto-binds on
  /// play, and the Sources screen (also pushed above) can bind/unbind too.
  @override
  void didPopNext() {
    _b.refreshBoundState();
    _p.loadResumeInfo();
    _p.loadLocalMovieFinished();
  }

  /// Native-TV / DeoVR / external playback runs in its own ACTIVITY and pushes
  /// no Flutter route, so [didPopNext] never fires for it and the resume label
  /// would stay stale. Mirrors the merged detail page — see
  /// [MainPageBridge.notifyPlaybackReturned] for why this signal exists, and
  /// why it's gated on this being the current route.
  void _onPlaybackReturned() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _b.refreshBoundState();
    _p.loadResumeInfo();
    _p.loadLocalMovieFinished();
  }

  @override
  void onMetadataPolicyChanged() => _parts.metadata.onMetadataPolicyChanged();

  @override
  void dispose() {
    TrackingSourceStorage.trackingSourceRevision.removeListener(
      _p.onMovieProgressPolicyChanged,
    );
    MovieProgressStorage.movieFinishedRevision.removeListener(
      _p.loadLocalMovieFinished,
    );
    MdblistService.instance.watchedRevision.removeListener(
      _p.loadLocalMovieFinished,
    );
    appRouteObserver.unsubscribe(this);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    _revealCtrl.dispose();
    _f.playFocus.dispose();
    _f.browseFocus.dispose();
    _f.watchlistFocus.dispose();
    _f.wideScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _parts.rootLayout.build(context);
}

// ── Staggered entrance reveal ───────────────────────────────────────────────

// ── Backdrop ────────────────────────────────────────────────────────────────

// ── Certificate badge ──────────────────────────────────────────────────────

// ── Genre chip ──────────────────────────────────────────────────────────────

// ── Metacritic badge ──────────────────────────────────────────────────────

// ── Cast avatar ──────────────────────────────────────────────────────────

// ── Recommendation ("Watch Next") card ─────────────────────────────────────

// ── Description with "Read more" ───────────────────────────────────────────

// ── Action row (PLAY + BROWSE) ──────────────────────────────────────────────

// ── Quick actions row ───────────────────────────────────────────────────────

// ── Glass card ────────────────────────────────────────────────────────────

// ── Glass icon button (back) ────────────────────────────────────────────────
