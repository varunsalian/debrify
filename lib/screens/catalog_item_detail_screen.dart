import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_scope.dart';
import '../theme/artwork_accent.dart';
import '../models/play_loader_art.dart';
import '../models/stremio_addon.dart';
import '../services/analytics_service.dart';
import '../services/app_route_observer.dart';
import '../services/imdb_enrichment_service.dart';
import '../services/imdb_parents_guide_service.dart';
import '../services/main_page_bridge.dart';
import '../services/series_source_service.dart';
import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/detail/catalog_detail_action_row.dart';
import '../widgets/detail/catalog_detail_backdrop.dart';
import '../widgets/detail/catalog_detail_badges.dart';
import '../widgets/detail/catalog_detail_description.dart';
import '../widgets/detail/catalog_detail_glass.dart';
import '../widgets/detail/catalog_detail_quick_actions.dart';
import '../widgets/detail/catalog_detail_rec_card.dart';
import '../widgets/detail/catalog_detail_reveal.dart';
import '../widgets/detail/detail_primary_sources.dart';
import '../widgets/parents_guide_section.dart';
import '../widgets/shimmer.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import '../services/simkl/simkl_menu_helpers.dart';
import '../services/simkl/simkl_service.dart';
import '../services/mdblist/mdblist_menu_helpers.dart';
import '../utils/artwork_url.dart';

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
    with SingleTickerProviderStateMixin, RouteAware {
  final FocusNode _playFocus = FocusNode(debugLabel: 'detail-play');
  final FocusNode _browseFocus = FocusNode(debugLabel: 'detail-browse');
  final FocusNode _watchlistFocus = FocusNode(debugLabel: 'detail-watchlist');

  /// Drives the wide/TV cinematic sheet. Needed so a D-pad "up" on the top
  /// action row can reveal the (non-focusable) eyebrow/title/meta header:
  /// focus traversal alone stops at Play/Sources and never scrolls past it.
  final ScrollController _wideScroll = ScrollController();

  bool _descriptionExpanded = false;

  /// "Watch Next" recommendations. null = not yet loaded / still loading;
  /// empty = loaded but nothing to show (rail stays hidden either way).
  List<StremioMeta>? _recommendations;

  /// Catalog-quality metadata fetched after first paint for a sparse item
  /// (a tapped recommendation). null until/unless enrichment succeeds.
  StremioMeta? _enriched;

  /// Parents guide data. null = not yet loaded; result with empty categories =
  /// loaded but nothing to show.
  ParentsGuideResult? _parentsGuide;

  /// Extra metadata from IMDb GraphQL (runtime, certificate, cast, etc.).
  ImdbEnrichment? _imdbExtra;

  bool _imdbLoaded = false;
  bool _parentsGuideLoaded = false;
  bool _recommendationsLoaded = false;

  /// The item the screen renders — the enriched copy once available,
  /// otherwise whatever the host handed us.
  StremioMeta get _item => _enriched ?? widget.item;
  bool get _supportsMyWatchlist =>
      MyWatchlistStore.supportsMyWatchlistItem(_item);

  /// Drives the staggered entrance reveal of the content sections.
  late final AnimationController _revealCtrl;

  /// Live bound-source flag (drives the Play button's "pinned" accent). Seeded
  /// from the parent's snapshot, then re-read when the player route pops back
  /// onto this screen — so playing a movie (which auto-binds its source) flips
  /// the accent on immediately instead of staying stale until reopen.
  late bool _hasBoundSource = widget.hasBoundSource;

  /// Primary-button resume state. Until loaded the button keeps its static "Play"
  /// label; once resolved it reads "Start Watching" (no progress) or "Resume"
  /// (+ an "S3E4" tag for series). Re-read when the player pops back.
  bool _resumeLoaded = false;
  bool _resumeStarted = false;
  int? _resumeSeason;
  int? _resumeEpisode;

  /// A resume lookup is in flight and unanswered. The primary button shows a
  /// spinner instead of a label so it never flashes "Start Watching" before
  /// flipping to "Resume · S1E7". Errors clear it (static label fallback).
  bool _resumePending = false;
  bool get _primaryBusy => _resumePending && !_resumeLoaded;

  /// Live Simkl status (drives the "Rewatch" relabel). Null until
  /// [simklStatusLoader] resolves — the button keeps "Play" until then.
  SimklTitleStatus? _simklStatus;
  bool _localMovieFinished = false;
  bool _inMyWatchlist = false;

  /// A movie the user has already finished on Simkl (status `completed`). Its
  /// Play button reads "Rewatch" and the play path un-marks it watched so the
  /// rewatch re-enters Continue Watching.
  bool get _isCompletedMovie =>
      _item.type != 'series' &&
      (_localMovieFinished || _simklStatus?.currentStatus == 'completed');

  @override
  void initState() {
    super.initState();
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
      _emitLoaderArt();
      if (!widget.isTelevision) _revealCtrl.forward();
      // Land focus on Play (or Sources when Play is hidden, e.g. PikPak) so
      // the remote has a starting point. TV only — on mobile/desktop an
      // auto-applied golden focus border just looks out of place.
      if (widget.isTelevision) {
        (widget.showQuickPlay ? _playFocus : _browseFocus).requestFocus();
      }
      _loadRecommendations();
      _loadEnrichedMeta();
      _loadArtworkAccent();
      _loadParentsGuide();
      _loadImdbEnrichment();
      _loadResumeInfo();
      _loadSimklStatus();
      _loadLocalMovieFinished();
      _loadMyWatchlistState();
    });
  }

  Future<void> _loadMyWatchlistState() async {
    if (!_supportsMyWatchlist) return;
    final saved = await MyWatchlistStore.isInMyWatchlist(_item);
    if (!mounted || saved == _inMyWatchlist) return;
    setState(() => _inMyWatchlist = saved);
  }

  Future<void> _toggleMyWatchlist() async {
    if (!_supportsMyWatchlist) return;
    final next = !_inMyWatchlist;
    setState(() => _inMyWatchlist = next);
    try {
      final sourceAddon = _item.sourceAddon ?? widget.item.sourceAddon;
      final savedItem = sourceAddon == null
          ? _item
          : _item.withSourceAddon(sourceAddon);
      await MyWatchlistStore.setMyWatchlistItem(savedItem, next);
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

  Future<void> _loadSimklStatus() async {
    final loader = widget.simklStatusLoader;
    if (loader == null) return;
    try {
      final status = await loader();
      if (!mounted || status == null) return;
      setState(() => _simklStatus = status);
    } catch (_) {
      // Non-critical — leave the plain "Play" label.
    }
  }

  Future<void> _loadLocalMovieFinished() async {
    if (_item.type == 'series') return;
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
    // setState, not a plain assignment — this runs from the post-init loader
    // fan (setState-safe), and the spinner must actually be scheduled to
    // paint rather than riding a sibling loader's rebuild.
    if (!_resumeLoaded && mounted) {
      setState(() => _resumePending = true);
    }
    try {
      // Time-boxed: the guide advance inside the reconciler can hang on an
      // unbounded body read; a timeout throws into catch/finally, falling
      // back to the static label instead of spinning forever.
      final info = await loader().timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _resumeLoaded = true;
        _resumeStarted = info.started;
        _resumeSeason = info.season;
        _resumeEpisode = info.episode;
      });
    } catch (_) {
      // Non-critical — leave the static label.
    } finally {
      if (_resumePending) {
        if (mounted) {
          setState(() => _resumePending = false);
        } else {
          _resumePending = false;
        }
      }
    }
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static "Play" until the resume state resolves.
  String get _primaryLabel {
    final isMovie = _item.type != 'series';
    // Some entry points (for example the catalog browser) intentionally omit
    // a resume loader. Local/Simkl completion is still enough to distinguish
    // a new play from a rewatch, so do not hide that state behind the optional
    // resume lookup.
    if (!_resumeLoaded) return _isCompletedMovie ? 'Rewatch' : 'Play';
    if (!_resumeStarted) {
      if (_isCompletedMovie) return 'Rewatch';
      return isMovie ? 'Play' : 'Start Watching';
    }
    if (isMovie || _resumeSeason == null || _resumeEpisode == null) {
      return 'Resume';
    }
    return 'Resume · S${_resumeSeason}E$_resumeEpisode';
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
    _refreshBoundState();
    _loadResumeInfo();
    _loadLocalMovieFinished();
  }

  /// Native-TV / DeoVR / external playback runs in its own ACTIVITY and pushes
  /// no Flutter route, so [didPopNext] never fires for it and the resume label
  /// would stay stale. Mirrors the merged detail page — see
  /// [MainPageBridge.notifyPlaybackReturned] for why this signal exists, and
  /// why it's gated on this being the current route.
  void _onPlaybackReturned() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _refreshBoundState();
    _loadResumeInfo();
    _loadLocalMovieFinished();
  }

  /// Re-read this title's bound-source count and flip the Play accent to match.
  Future<void> _refreshBoundState() async {
    final imdb = _boundKey();
    if (imdb == null) return;
    final bound = (await SeriesSourceService.getSources(imdb)).isNotEmpty;
    if (mounted && bound != _hasBoundSource) {
      setState(() => _hasBoundSource = bound);
    }
  }

  /// The imdb key the binding store is keyed on — mirrors the host's `_imdbOf`
  /// (a `tt…` id, whether it rode in as `imdbId` or the raw catalog id).
  String? _boundKey() {
    final item = widget.item;
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// When the item arrived sparse — no year, rating, or genres, the
  /// signature of a "Watch Next" recommendation built straight from an
  /// addon stream entry — fetch full Cinemeta-grade metadata after first
  /// paint and merge it in, so the screen ends up identical to a normal
  /// catalog open. Fail-soft: any failure leaves the original item as-is.
  Future<void> _loadEnrichedMeta() async {
    final enrich = widget.metaEnricher;
    final item = widget.item;
    final imdbId = item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;

    // An item with no overview is never "rich enough": Trakt / Simkl / MDBList
    // rows carry a year and rating but no description, and the page would show
    // an empty summary if we skipped the fetch on their behalf.
    final alreadyRich =
        (item.description?.isNotEmpty ?? false) &&
        ((item.year != null && item.year!.isNotEmpty) ||
            item.imdbRating != null ||
            (item.genres?.isNotEmpty ?? false));
    if (alreadyRich) return; // a normal catalog item — nothing to add

    try {
      final full = await enrich(imdbId, item.type);
      if (full == null || !mounted) return;
      setState(() {
        // Keep identity/source from the tapped item; take the structured
        // fields and clean overview from the fetched meta, but never let a
        // missing field blank out something we already had.
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
      _emitLoaderArt();
    } catch (_) {
      // Non-critical enrichment — swallow and keep the original item.
    }
  }

  /// Publishes the current best artwork for the play loader. Cheap and
  /// idempotent — the host just keeps the latest.
  void _emitLoaderArt() {
    final sink = widget.onLoaderArt;
    if (sink == null) return;
    final art = PlayLoaderArt.fromMeta(
      _item,
      certificate: _imdbExtra?.certificate,
    );
    if (!art.isEmpty) sink(art);
  }

  Future<void> _loadImdbEnrichment() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) {
      if (mounted) setState(() => _imdbLoaded = true);
      return;
    }
    try {
      final extra = await ImdbEnrichmentService.fetch(imdbId);
      if (mounted) {
        setState(() {
          _imdbExtra = extra;
          _imdbLoaded = true;
        });
        // Adds the certificate to the loader's meta line.
        _emitLoaderArt();
      }
    } catch (_) {
      if (mounted) setState(() => _imdbLoaded = true);
    }
  }

  Future<void> _loadParentsGuide() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) {
      if (mounted) setState(() => _parentsGuideLoaded = true);
      return;
    }
    try {
      final guide = await ImdbParentsGuideService.fetch(imdbId);
      if (mounted) {
        setState(() {
          _parentsGuide = guide;
          _parentsGuideLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _parentsGuideLoaded = true);
    }
  }

  /// Loads recommendations after first paint so the rail never blocks the
  /// detail screen's appearance. Fail-soft: any error leaves the rail hidden.
  Future<void> _loadRecommendations() async {
    final loader = widget.recommendationsLoader;
    if (loader == null) {
      if (mounted) setState(() => _recommendationsLoaded = true);
      return;
    }
    try {
      final recs = await loader();
      if (mounted) {
        setState(() {
          _recommendations = recs;
          _recommendationsLoaded = true;
        });
      }
      final enrich = widget.metaEnricher;
      if (enrich != null) {
        for (final rec in recs.take(8)) {
          final id = rec.effectiveImdbId;
          if (id != null) enrich(id, rec.type);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _recommendationsLoaded = true);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    _revealCtrl.dispose();
    _playFocus.dispose();
    _browseFocus.dispose();
    _watchlistFocus.dispose();
    _wideScroll.dispose();
    super.dispose();
  }

  /// This title's own colour, pulled from its poster.
  ///
  /// Same one-tiny-decode path `merged_series_detail_screen` has always had,
  /// through the shared cache so a revisit is free. Published into
  /// [ArtworkAccentScope] rather than applied here, so descendants — including
  /// the sheets and dialogs this screen raises, which inherit it because the
  /// scope is an `InheritedTheme` — can take it where they paint IDENTITY, and
  /// only there.
  Color? _artworkAccent;

  Future<void> _loadArtworkAccent() async {
    final url = _item.poster ?? _item.background;
    if (url == null || url.isEmpty) return;
    try {
      final raw = await DominantColorCache.of(
        url,
        CachedNetworkImageProvider(url),
      );
      if (raw == null || !mounted) return;
      // The extractor normalises for a DARK ui; on a paper theme that lands
      // low-contrast, so it is re-targeted against the ground it will be seen
      // on before anything paints with it.
      final app = AppThemeScope.of(context);
      setState(() => _artworkAccent = normaliseAccentFor(raw, app));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = _wide;
    // The detail backdrop is a display-sized hero, not a shelf card. Upgrade
    // MetaHub's catalog-sized art here without changing the item's shared
    // poster URL (recommendation shelves continue to use their medium source).
    final backdropUrl = highQualityArtworkUrl(_item.background ?? _item.poster);

    return ArtworkAccentScope(
      accent: _artworkAccent,
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
            child: CatalogDetailBackdrop(
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
                child: CatalogDetailGlassIconButton(
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
              controller: _wideScroll,
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
          CatalogDetailReveal(
            parent: _revealCtrl,
            start: infoStart,
            child: CatalogDetailGlassCard(children: infoChildren),
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
          CatalogDetailReveal(
            parent: _revealCtrl,
            start: detailStart,
            child: CatalogDetailGlassCard(children: detailChildren),
          ),
        );
    }

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

  Widget _secEyebrow(double start) => CatalogDetailReveal(
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

  Widget _secTitle(double start) => CatalogDetailReveal(
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
    final extra = _imdbExtra;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final hasYear = year != null && year.isNotEmpty;
    final cert = extra?.certificate;
    final runtime = extra?.runtime;
    final voteCount = extra?.voteCountFormatted;
    final hasVotes = voteCount != null && voteCount.isNotEmpty;
    final showMetaShimmer = !_imdbLoaded && extra == null;
    return CatalogDetailReveal(
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
            if (cert != null) ...[if (hasYear) _dot(), CatalogDetailCertBadge(label: cert)],
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
              CatalogDetailMetacriticBadge(score: extra!.metacriticScore!),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _secGenres(double start) {
    var genres = _item.genres ?? const <String>[];
    if (genres.isEmpty) genres = _imdbExtra?.genres ?? const [];
    if (genres.isEmpty) {
      if (_imdbLoaded) return null;
      return CatalogDetailReveal(
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
    return CatalogDetailReveal(
      parent: _revealCtrl,
      start: start,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [for (final g in genres.take(5)) CatalogDetailGenreChip(label: g)],
      ),
    );
  }

  Widget? _secAwards(double start) {
    final extra = _imdbExtra;
    if (extra == null || !extra.hasAwards) return null;
    return CatalogDetailReveal(
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
    final extra = _imdbExtra;
    if (extra == null) {
      if (_imdbLoaded) return null;
      final h = _tight ? 10.0 : 12.0;
      return CatalogDetailReveal(
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

    return CatalogDetailReveal(
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
    final cast = _imdbExtra?.cast ?? const [];
    if (cast.isEmpty) {
      if (_imdbLoaded) return null;
      return CatalogDetailReveal(
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
    return CatalogDetailReveal(
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
                    CatalogDetailCastAvatar(member: cast[i], size: avatarSize),
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
    final extra = _imdbExtra;
    if (extra == null) {
      if (_imdbLoaded) return null;
      return CatalogDetailReveal(
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

    return CatalogDetailReveal(
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
    final guide = _parentsGuide;
    if (guide == null) {
      if (_parentsGuideLoaded) return null;
      final rowH = _tight ? 38.0 : 44.0;
      return CatalogDetailReveal(
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
    return CatalogDetailReveal(
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
    return CatalogDetailReveal(
      parent: _revealCtrl,
      start: start,
      child: CatalogDetailSimklQuickActions(
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
    return CatalogDetailReveal(
      parent: _revealCtrl,
      start: start,
      child: CatalogDetailMdblistQuickActions(
        options: widget.mdblistMenuOptions,
        onSelected: widget.onMdblistAction!,
      ),
    );
  }

  Widget? _secQuickActions(double start) {
    if (widget.traktMenuOptions.isEmpty || widget.onTraktAction == null) {
      return null;
    }
    return CatalogDetailReveal(
      parent: _revealCtrl,
      start: start,
      child: CatalogDetailQuickActions(
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
    final recs = _recommendations;
    final onTap = widget.onRecommendationTap;
    final tight = _tight;
    final cardW = _wide ? (tight ? 104.0 : 120.0) : 112.0;
    final posterH = cardW * 1.5;
    final loading =
        recs == null &&
        !_recommendationsLoaded &&
        widget.recommendationsLoader != null;

    if (!loading && (recs == null || recs.isEmpty || onTap == null)) {
      return null;
    }

    return CatalogDetailReveal(
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
                            CatalogDetailRecCard(
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
      description = _imdbExtra?.plot ?? description;
    }
    if (description.isEmpty) return null;
    final tagline = _imdbExtra?.tagline;
    return CatalogDetailReveal(
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
            CatalogDetailDescription(
              text: description,
              wide: true,
              dense: _tight,
              collapsedLines: _tight ? 2 : 4,
              expanded: _descriptionExpanded,
              onToggle: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
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
    if (!_wideScroll.hasClients || _wideScroll.offset <= 0) return;
    _wideScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// The Play / Sources action row.
  Widget _buildActionRow(double start) {
    final item = widget.item;
    return CatalogDetailReveal(
      parent: _revealCtrl,
      start: start,
      dy: 16,
      child: CatalogDetailActionRow(
        compact: !_wide,
        showQuickPlay: widget.showQuickPlay,
        isSeries: item.type == 'series',
        hasBoundSource: _hasBoundSource,
        playFocus: _playFocus,
        browseFocus: _browseFocus,
        watchlistFocus: _watchlistFocus,
        tv: widget.isTelevision,
        playLabel: _primaryLabel,
        playBusy: _primaryBusy,
        // TV only: the top row is the highest focusable widget, so a D-pad
        // "up" there reveals the header instead of dead-ending.
        onArrowUp: widget.isTelevision ? _scrollWideToTop : null,
        onPlay: widget.onPlay,
        onPlayLongPress: _canBrowsePrimarySources
            ? _browsePrimarySources
            : null,
        // Neither Play nor Browse pop here: the player pushes on top of
        // this detail screen so the user returns here when playback ends.
        // Browse keeps the detail for the same reason (series drill-down
        // stacks on top). The host handles teardown via _returnToCatalogIfNeeded.
        onBrowse: widget.onBrowse,
        inMyWatchlist: _inMyWatchlist,
        onToggleMyWatchlist: _supportsMyWatchlist ? _toggleMyWatchlist : null,
      ),
    );
  }

  bool get _canBrowsePrimarySources =>
      widget.enablePrimarySourcesHold &&
      (_item.type != 'series' ||
          widget.onBrowsePrimaryEpisodeSources != null);

  void _browsePrimarySources() {
    unawaited(_browsePrimarySourcesAsync());
  }

  Future<void> _browsePrimarySourcesAsync() async {
    if (_item.type != 'series') {
      widget.onBrowse();
      return;
    }

    final openEpisode = widget.onBrowsePrimaryEpisodeSources;
    if (openEpisode == null) return;

    final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    if (!mounted) return;

    final canBrowsePacks =
        widget.onTraktAction != null &&
        widget.traktMenuOptions.any(
          (option) => option.action == TraktItemMenuAction.searchPacks,
        );
    if (!rules.preferSeriesPacks || !canBrowsePacks) {
      await openEpisode();
      return;
    }

    final choice = await showDetailPrimarySourcesSheet(
      context,
      title: _item.name,
      isTelevision: widget.isTelevision,
      episodeLabel: _resumeSeason == null || _resumeEpisode == null
          ? null
          : 'S${_resumeSeason}E$_resumeEpisode',
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case DetailPrimarySourceChoice.seasonPacks:
        widget.onTraktAction?.call(TraktItemMenuAction.searchPacks);
        return;
      case DetailPrimarySourceChoice.episode:
        await openEpisode();
        return;
    }
  }

  Widget _dot() => Text(
    '·',
    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
  );
}
