import 'dart:async';
import 'package:debrify/features/catalog_detail/presentation/catalog_action_row.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_backdrop.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_cert_badge.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_description.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_genre_chip.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_glass_card.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_glass_icon_button.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_metacritic_badge.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_quick_actions.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_rec_card.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_reveal.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_cast_avatar.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_bound_sources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_parts.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_watchlist.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_mdblist_quick_actions.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_simkl_quick_actions.dart';
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
import '../services/metadata_details_service.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../services/simkl/simkl_service.dart';
import '../theme/artwork_accent.dart';
import '../utils/artwork_url.dart';
import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/metadata_franchise_rail.dart';
import '../widgets/metadata_presentation_mixin.dart';
import '../widgets/parents_guide_section.dart';
import '../widgets/shimmer.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import 'metadata_explore_page.dart';

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
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = _wide;
    // The detail backdrop is a display-sized hero, not a shelf card. Upgrade
    // MetaHub's catalog-sized art here without changing the item's shared
    // poster URL (recommendation shelves continue to use their medium source).
    final backdropUrl = highQualityArtworkUrl(
      MetadataDetailsService.backdrop(_item, metadataPreferences),
    );

    return ArtworkAccentScope(
      accent: _m.artworkAccent,
      child: _buildBody(context, size, isWide, backdropUrl),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Size size,
    bool isWide,
    String? backdropUrl,
  ) {
    return Scaffold(
      floatingActionButton: MetadataExploreButton(
        item: _item,
        onOpen: widget.onRecommendationTap,
        isTelevision: widget.isTelevision,
      ),
      backgroundColor: const Color(0xFF050507),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Backdrop ─────────────────────────────────────────────────────
          // Wide screens: full-bleed. Narrow: top half only.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: isWide ? size.height : size.height * 0.62,
            child: CatalogBackdrop(
              url: backdropUrl,
              isWide: isWide,
              animate: !widget.isTelevision,
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          // On wide layouts, content gravitates to the bottom-left third
          // (Apple-TV/Netflix style). On narrow it scrolls under the
          // backdrop normally.
          SafeArea(
            child: isWide ? _buildWideContent(size) : _buildNarrowContent(size),
          ),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(widget.isTelevision ? 28 : 8),
                child: CatalogGlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowContent(Size size) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: size.height * 0.30, bottom: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _buildNarrowColumn(),
      ),
    );
  }

  Widget _buildWideContent(Size size) {
    // Content sheet bottom-left over the full-bleed art. TVs overscan, so
    // keep it well off the physical bezel — including the top: when the
    // content is tall enough to fill the sheet (expanded synopsis + quick
    // actions + recs) the eyebrow/title reach the top edge and the TV
    // overscan clips them, so mirror the bottom inset there.
    final tv = widget.isTelevision;
    final maxWidth = (size.width * 0.56).clamp(440.0, 760.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tv ? 64 : 48,
        tv ? 44 : 0,
        tv ? 48 : 24,
        tv ? 44 : 40,
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _f.wideScroll,
              physics: const BouncingScrollPhysics(),
              // Don't clip the focus glow on Play/Sources/quick actions.
              clipBehavior: Clip.none,
              child: _buildContentColumn(),
            ),
          ),
        ),
      ),
    );
  }

  /// The cinematic bottom-left sheet is the premium look for landscape
  /// screens (incl. TV). Portrait/narrow windows use the single-scroll
  /// phone layout instead.
  bool get _wide {
    if (widget.isTelevision) return true;
    final s = MediaQuery.of(context).size;
    return s.width >= 900 && s.width > s.height;
  }

  /// Limited vertical space (Android TV is only ~540 logical px tall at
  /// DPR 2.0) — shrink typography/spacing so the cinematic layout still
  /// fits on one screen instead of overflowing.
  bool get _tight => MediaQuery.of(context).size.height < 620;

  /// Wide: cinematic bottom-left sheet — info first, Play/Sources at the end.
  Widget _buildContentColumn() {
    final t = _tight;
    final children = <Widget>[
      _secEyebrow(0.00),
      SizedBox(height: t ? 6 : 10),
      _secTitle(0.10),
      SizedBox(height: t ? 8 : 14),
      _secMeta(0.20),
    ];
    final g = _secGenres(0.28);
    if (g != null) {
      children
        ..add(SizedBox(height: t ? 10 : 18))
        ..add(g);
    }
    final aw = _secAwards(0.32);
    if (aw != null) {
      children
        ..add(SizedBox(height: t ? 8 : 12))
        ..add(aw);
    }
    children
      ..add(SizedBox(height: t ? 16 : 26))
      ..add(_buildActionRow(0.38));
    final d = _secDescription(0.46);
    if (d != null) {
      children
        ..add(SizedBox(height: t ? 12 : 24))
        ..add(d);
    }
    final cr = _secCredits(0.50);
    if (cr != null) {
      children
        ..add(SizedBox(height: t ? 10 : 18))
        ..add(cr);
    }
    final ca = _secCast(0.52);
    if (ca != null) {
      children
        ..add(SizedBox(height: t ? 14 : 24))
        ..add(ca);
    }
    final q = _secQuickActions(0.54);
    if (q != null) {
      children
        ..add(SizedBox(height: t ? 14 : 26))
        ..add(q);
    }
    final sq = _secSimklQuickActions(0.55);
    if (sq != null) {
      children
        ..add(SizedBox(height: t ? 14 : 26))
        ..add(sq);
    }
    final mq = _secMdblistQuickActions(0.555);
    if (mq != null) {
      children
        ..add(SizedBox(height: t ? 14 : 26))
        ..add(mq);
    }
    final dt = _secDetails(0.56);
    if (dt != null) {
      children
        ..add(SizedBox(height: t ? 12 : 22))
        ..add(dt);
    }
    final pg = _secParentsGuide(0.58);
    if (pg != null) {
      children
        ..add(SizedBox(height: t ? 12 : 22))
        ..add(pg);
    }
    children.add(
      MetadataFranchiseRail(
        item: _item,
        onOpen: widget.onRecommendationTap == null
            ? null
            : _m.openMetadataRecommendation,
        isTelevision: widget.isTelevision,
      ),
    );
    final r = _secRecommendations(0.66);
    if (r != null) {
      children
        ..add(SizedBox(height: t ? 16 : 28))
        ..add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildNarrowColumn() {
    final children = <Widget>[
      _secEyebrow(0.00),
      const SizedBox(height: 8),
      _secTitle(0.10),
      const SizedBox(height: 12),
      _secMeta(0.20),
    ];
    final g = _secGenres(0.28);
    if (g != null) {
      children
        ..add(const SizedBox(height: 14))
        ..add(g);
    }
    final aw = _secAwards(0.32);
    if (aw != null) {
      children
        ..add(const SizedBox(height: 12))
        ..add(aw);
    }
    children
      ..add(const SizedBox(height: 24))
      ..add(_buildActionRow(0.38));

    // ── Glass info card: synopsis + credits + cast ──
    // All inner sections share the card's start time so they fade in
    // together — no staggered holes inside the card.
    const infoStart = 0.46;
    final infoChildren = <Widget>[];
    final d = _secDescription(infoStart);
    if (d != null) infoChildren.add(d);
    final cr = _secCredits(infoStart);
    if (cr != null) {
      if (infoChildren.isNotEmpty) infoChildren.add(_divider());
      infoChildren.add(cr);
    }
    final ca = _secCast(infoStart);
    if (ca != null) {
      if (infoChildren.isNotEmpty) infoChildren.add(_divider());
      infoChildren.add(ca);
    }
    if (infoChildren.isNotEmpty) {
      children
        ..add(const SizedBox(height: 24))
        ..add(
          CatalogReveal(
            parent: _revealCtrl,
            start: infoStart,
            child: CatalogGlassCard(children: infoChildren),
          ),
        );
    }

    final q = _secQuickActions(0.54);
    if (q != null) {
      children
        ..add(const SizedBox(height: 24))
        ..add(q);
    }
    final sq = _secSimklQuickActions(0.55);
    if (sq != null) {
      children
        ..add(const SizedBox(height: 24))
        ..add(sq);
    }
    final mq = _secMdblistQuickActions(0.555);
    if (mq != null) {
      children
        ..add(const SizedBox(height: 24))
        ..add(mq);
    }

    // ── Glass details card: production details + parents guide ──
    const detailStart = 0.56;
    final detailChildren = <Widget>[];
    final dt = _secDetails(detailStart);
    if (dt != null) detailChildren.add(dt);
    final pg = _secParentsGuide(detailStart);
    if (pg != null) {
      if (detailChildren.isNotEmpty) detailChildren.add(_divider());
      detailChildren.add(pg);
    }
    if (detailChildren.isNotEmpty) {
      children
        ..add(const SizedBox(height: 24))
        ..add(
          CatalogReveal(
            parent: _revealCtrl,
            start: detailStart,
            child: CatalogGlassCard(children: detailChildren),
          ),
        );
    }

    children.add(
      MetadataFranchiseRail(
        item: _item,
        onOpen: widget.onRecommendationTap == null
            ? null
            : _m.openMetadataRecommendation,
        isTelevision: widget.isTelevision,
      ),
    );
    final r = _secRecommendations(0.66);
    if (r != null) {
      children
        ..add(const SizedBox(height: 28))
        ..add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(
      height: 0.5,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0x18FFFFFF),
            Color(0x18FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, 0.2, 0.8, 1.0],
        ),
      ),
    ),
  );

  // ── Sections ──────────────────────────────────────────────────────────────
  Widget _secEyebrow(double start) => CatalogReveal(
    parent: _revealCtrl,
    start: start,
    child: Text(
      widget.item.type == 'series' ? 'SERIES' : 'MOVIE',
      style: TextStyle(
        color: DetailThemeScope.maybeOf(context).focus,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.4,
        shadows: const [
          Shadow(color: Color(0x993B2A00), blurRadius: 12),
          Shadow(color: Color(0x66000000), blurRadius: 6),
        ],
      ),
    ),
  );

  Widget _secTitle(double start) => CatalogReveal(
    parent: _revealCtrl,
    start: start,
    child: Text(
      _item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _wide ? (_tight ? 30 : 44) : 28,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.0,
        height: 1.05,
        shadows: const [
          Shadow(
            color: Color(0xDD000000),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
          Shadow(color: Color(0x66000000), blurRadius: 8),
        ],
      ),
    ),
  );

  Widget _secMeta(double start) {
    final item = _item;
    final extra = _m.imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final hasYear = year != null && year.isNotEmpty;
    final cert = extra?.certificate;
    final runtime = MetadataDetailsService.informationRuntime(
      item,
      extra,
      metadataPreferences,
    );
    final voteCount = extra?.voteCountFormatted;
    final hasVotes = voteCount != null && voteCount.isNotEmpty;
    final showMetaShimmer = !_m.imdbLoaded && extra == null;
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: DefaultTextStyle(
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: _wide && !_tight ? 14 : 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(color: Color(0xBB000000), blurRadius: 10),
            Shadow(color: Color(0x55000000), blurRadius: 4),
          ],
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (hasYear) Text(year),
            if (cert != null) ...[
              if (hasYear) _dot(),
              CatalogCertBadge(label: cert),
            ],
            if (runtime != null) ...[
              if (hasYear || cert != null) _dot(),
              Text(runtime),
            ],
            if (showMetaShimmer && cert == null && runtime == null) ...[
              if (hasYear) _dot(),
              Shimmer(
                width: 28,
                height: 16,
                borderRadius: BorderRadius.circular(4),
              ),
              _dot(),
              Shimmer(
                width: 48,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            if (rating != null) ...[
              if (hasYear || cert != null || runtime != null) _dot(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 16, color: Color(0xFFFACC15)),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1)),
                  if (hasVotes) ...[
                    const SizedBox(width: 3),
                    Text(
                      '($voteCount)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: _wide && !_tight ? 12 : 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ] else if (showMetaShimmer) ...[
              if (hasYear || cert != null || runtime != null) _dot(),
              Shimmer(
                width: 60,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            if (extra?.metacriticScore != null) ...[
              _dot(),
              CatalogMetacriticBadge(score: extra!.metacriticScore!),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _secGenres(double start) {
    final genres = MetadataDetailsService.informationGenres(
      _item,
      _m.imdbExtra,
      metadataPreferences,
    );
    if (genres.isEmpty) {
      if (_m.imdbLoaded) return null;
      return CatalogReveal(
        parent: _revealCtrl,
        start: start,
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: const [
            Shimmer(
              width: 64,
              height: 28,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            Shimmer(
              width: 52,
              height: 28,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            Shimmer(
              width: 72,
              height: 28,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ],
        ),
      );
    }
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [for (final g in genres.take(5)) CatalogGenreChip(label: g)],
      ),
    );
  }

  Widget? _secAwards(double start) {
    final extra = _m.imdbExtra;
    if (extra == null || !extra.hasAwards) return null;
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: _tight ? 10 : 12,
          vertical: _tight ? 6 : 8,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x22FBBF24), Color(0x0AFBBF24)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33FBBF24), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 16,
              color: Color(0xFFFBBF24),
            ),
            const SizedBox(width: 8),
            Text(
              extra.awardsLine!,
              style: TextStyle(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
                fontSize: _tight ? 11 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _secCredits(double start) {
    final extra = _m.imdbExtra;
    if (extra == null) {
      if (_m.imdbLoaded) return null;
      final h = _tight ? 10.0 : 12.0;
      return CatalogReveal(
        parent: _revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Shimmer(
                  width: 60,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(width: 10),
                Shimmer(
                  width: 140,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
            SizedBox(height: _tight ? 4 : 8),
            Row(
              children: [
                Shimmer(
                  width: 60,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(width: 10),
                Shimmer(
                  width: 200,
                  height: h,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final hasDirector = extra.director != null && extra.director!.isNotEmpty;
    final hasStars = extra.stars.isNotEmpty;
    if (!hasDirector && !hasStars) return null;

    const sh = [Shadow(color: Color(0x55000000), blurRadius: 4)];
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: _tight ? 11 : 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      shadows: sh,
    );
    final valueStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: _tight ? 11 : 12,
      fontWeight: FontWeight.w500,
      shadows: sh,
    );

    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasDirector) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 70, child: Text('Director', style: labelStyle)),
                Expanded(child: Text(extra.director!, style: valueStyle)),
              ],
            ),
            if (hasStars) SizedBox(height: _tight ? 4 : 6),
          ],
          if (hasStars)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 70, child: Text('Stars', style: labelStyle)),
                Expanded(
                  child: Text(
                    extra.stars.take(4).join(', '),
                    style: valueStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget? _secCast(double start) {
    final cast = _m.imdbExtra?.cast ?? const [];
    if (cast.isEmpty) {
      if (_m.imdbLoaded) return null;
      return CatalogReveal(
        parent: _revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionHeader('CAST'),
            const SizedBox(height: 12),
            SizedBox(
              height: (_tight ? 56.0 : 68.0) + 42,
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Column(
                      children: [
                        Shimmer(
                          width: _tight ? 56 : 68,
                          height: _tight ? 56 : 68,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 6),
                        Shimmer(
                          width: 50,
                          height: 10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final avatarSize = _tight ? 56.0 : 68.0;
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionHeader('CAST'),
          const SizedBox(height: 12),
          SizedBox(
            height: avatarSize + 42,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cast.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    CatalogCastAvatar(member: cast[i], size: avatarSize),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _secDetails(double start) {
    final extra = _m.imdbExtra;
    if (extra == null) {
      if (_m.imdbLoaded) return null;
      return CatalogReveal(
        parent: _revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionHeader('DETAILS'),
            const SizedBox(height: 10),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Row(
                children: [
                  Shimmer(
                    width: 70,
                    height: 11,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(width: 10),
                  Shimmer(
                    width: 120,
                    height: 11,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final rows = <(String, String)>[];
    if (extra.countries.isNotEmpty) {
      rows.add(('Country', extra.countries.take(2).join(', ')));
    }
    if (extra.languages.isNotEmpty) {
      rows.add(('Language', extra.languages.take(3).join(', ')));
    }
    if (extra.productionCompany != null) {
      rows.add(('Studio', extra.productionCompany!));
    }
    if (extra.boxOffice != null) {
      rows.add(('Box Office', extra.boxOffice!));
    }
    if (rows.isEmpty) return null;

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.40),
      fontSize: _tight ? 11 : 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      shadows: const [Shadow(color: Color(0x55000000), blurRadius: 4)],
    );
    final valueStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.82),
      fontSize: _tight ? 11 : 12,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(color: Color(0x55000000), blurRadius: 4)],
    );

    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionHeader('DETAILS'),
          SizedBox(height: _tight ? 8 : 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: _tight ? 4 : 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 78, child: Text(rows[i].$1, style: labelStyle)),
                Expanded(child: Text(rows[i].$2, style: valueStyle)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: _tight ? 10 : 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.2,
        shadows: const [Shadow(color: Color(0x55000000), blurRadius: 4)],
      ),
    );
  }

  Widget? _secParentsGuide(double start) {
    final guide = _m.parentsGuide;
    if (guide == null) {
      if (_m.parentsGuideLoaded) return null;
      final rowH = _tight ? 38.0 : 44.0;
      return CatalogReveal(
        parent: _revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Shimmer(
              width: 130,
              height: 14,
              borderRadius: BorderRadius.circular(4),
            ),
            SizedBox(height: _tight ? 8 : 10),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(height: _tight ? 6 : 8),
              Shimmer(
                width: double.infinity,
                height: rowH,
                borderRadius: BorderRadius.circular(10),
              ),
            ],
          ],
        ),
      );
    }
    if (guide.isEmpty) return null;
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: ParentsGuideSection(
        guide: guide,
        tv: widget.isTelevision,
        dense: _tight,
      ),
    );
  }

  Widget? _secSimklQuickActions(double start) {
    if (widget.simklMenuOptions.isEmpty || widget.onSimklAction == null) {
      return null;
    }
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: CatalogSimklQuickActions(
        options: widget.simklMenuOptions,
        tv: widget.isTelevision,
        phone: !_wide,
        onSelected: widget.onSimklAction!,
      ),
    );
  }

  Widget? _secMdblistQuickActions(double start) {
    if (widget.mdblistMenuOptions.isEmpty || widget.onMdblistAction == null) {
      return null;
    }
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: CatalogMdblistQuickActions(
        options: widget.mdblistMenuOptions,
        onSelected: widget.onMdblistAction!,
      ),
    );
  }

  Widget? _secQuickActions(double start) {
    if (widget.traktMenuOptions.isEmpty || widget.onTraktAction == null) {
      return null;
    }
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: CatalogQuickActions(
        options: widget.traktMenuOptions,
        tv: widget.isTelevision,
        // Phone (narrow layout): force a tidy 3-up grid. Wide/TV keeps
        // its free-flowing wrap.
        phone: !_wide,
        onSelected: widget.onTraktAction!,
      ),
    );
  }

  Widget? _secRecommendations(double start) {
    final recs = _m.recommendations;
    final onTap = widget.onRecommendationTap == null
        ? null
        : _m.openMetadataRecommendation;
    final tight = _tight;
    final cardW = _wide ? (tight ? 104.0 : 120.0) : 112.0;
    final posterH = cardW * 1.5;
    final loading =
        recs == null &&
        !_m.recommendationsLoaded &&
        widget.recommendationsLoader != null;

    if (!loading && (recs == null || recs.isEmpty || onTap == null)) {
      return null;
    }

    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? Shimmer(
                  width: 130,
                  height: 16,
                  borderRadius: BorderRadius.circular(4),
                )
              : Text(
                  'More Like This',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: _wide && !tight ? 18 : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    shadows: const [
                      Shadow(color: Color(0x99000000), blurRadius: 8),
                    ],
                  ),
                ),
          SizedBox(height: tight ? 8 : 12),
          SizedBox(
            height: posterH + 44,
            child: loading
                ? Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Shimmer(
                              width: cardW,
                              height: posterH,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            const SizedBox(height: 6),
                            Shimmer(
                              width: cardW * 0.8,
                              height: 12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                : FocusTraversalGroup(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      clipBehavior: Clip.none,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < recs!.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            CatalogRecCard(
                              item: recs[i],
                              width: cardW,
                              posterHeight: posterH,
                              tv: widget.isTelevision,
                              onTap: () => onTap!(recs[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _secDescription(double start) {
    var description = _item.description ?? '';
    if (description.isEmpty || description.length < 40) {
      description = _m.imdbExtra?.plot ?? description;
    }
    if (description.isEmpty) return null;
    final tagline = _m.imdbExtra?.tagline;
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tagline != null && tagline.isNotEmpty) ...[
            Text(
              '"$tagline"',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: _tight ? 12 : (_wide ? 15 : 13),
                fontStyle: FontStyle.italic,
                height: 1.4,
                letterSpacing: 0.2,
                shadows: const [
                  Shadow(color: Color(0x88000000), blurRadius: 8),
                ],
              ),
            ),
            SizedBox(height: _tight ? 6 : 10),
          ],
          if (_wide)
            CatalogDescription(
              text: description,
              wide: true,
              dense: _tight,
              collapsedLines: _tight ? 2 : 4,
              expanded: _f.descriptionExpanded,
              onToggle: () => setState(
                () => _f.descriptionExpanded = !_f.descriptionExpanded,
              ),
            )
          else
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 15,
                height: 1.5,
                letterSpacing: 0.1,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 6),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Snap the wide/TV sheet back to the top so the (non-focusable) header
  /// is visible again. Triggered by a D-pad "up" on the top action row,
  /// where focus traversal would otherwise dead-end at Play/Sources.
  void _scrollWideToTop() {
    if (!_f.wideScroll.hasClients || _f.wideScroll.offset <= 0) return;
    _f.wideScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// The Play / Sources action row.
  Widget _buildActionRow(double start) {
    final item = widget.item;
    return CatalogReveal(
      parent: _revealCtrl,
      start: start,
      dy: 16,
      child: CatalogActionRow(
        compact: !_wide,
        showQuickPlay: widget.showQuickPlay,
        isSeries: item.type == 'series',
        hasBoundSource: _hasBoundSource,
        playFocus: _f.playFocus,
        browseFocus: _f.browseFocus,
        watchlistFocus: _f.watchlistFocus,
        tv: widget.isTelevision,
        playLabel: _p.primaryLabel,
        playBusy: _p.primaryBusy,
        // TV only: the top row is the highest focusable widget, so a D-pad
        // "up" there reveals the header instead of dead-ending.
        onArrowUp: widget.isTelevision ? _scrollWideToTop : null,
        onPlay: _p.playPrimary,
        onPlayLongPress: _b.canBrowsePrimarySources
            ? _b.browsePrimarySources
            : null,
        // Neither Play nor Browse pop here: the player pushes on top of
        // this detail screen so the user returns here when playback ends.
        // Browse keeps the detail for the same reason (series drill-down
        // stacks on top). The host handles teardown via _returnToCatalogIfNeeded.
        onBrowse: widget.onBrowse,
        inMyWatchlist: _w.inMyWatchlist,
        onToggleMyWatchlist: _w.supportsMyWatchlist
            ? _w.toggleMyWatchlist
            : null,
      ),
    );
  }

  Widget _dot() => Text(
    '·',
    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
  );
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
