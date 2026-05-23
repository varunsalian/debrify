import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../services/imdb_enrichment_service.dart';
import '../services/imdb_parents_guide_service.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/parents_guide_section.dart';
import '../widgets/shimmer.dart';
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

  /// Opens the sources/episodes flow (was "Sources" / "Episodes" in the list).
  final VoidCallback onBrowse;

  /// Trakt actions. When non-empty a "More" button appears next to
  /// Play/Browse and opens the cinematic action sheet.
  final List<TraktMenuOption> traktMenuOptions;

  /// Invoked when the user picks a Trakt action from the "More" sheet.
  final void Function(TraktItemMenuAction action)? onTraktAction;

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
  final Future<StremioMeta?> Function(String imdbId, String type)?
  metaEnricher;

  const CatalogItemDetailScreen({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onBrowse,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.hasBoundSource = false,
    this.traktMenuOptions = const [],
    this.onTraktAction,
    this.recommendationsLoader,
    this.onRecommendationTap,
    this.metaEnricher,
  });

  @override
  State<CatalogItemDetailScreen> createState() =>
      _CatalogItemDetailScreenState();
}

class _CatalogItemDetailScreenState extends State<CatalogItemDetailScreen>
    with SingleTickerProviderStateMixin {
  final FocusNode _playFocus = FocusNode(debugLabel: 'detail-play');
  final FocusNode _browseFocus = FocusNode(debugLabel: 'detail-browse');

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

  /// Drives the staggered entrance reveal of the content sections.
  late final AnimationController _revealCtrl;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // TVs are low-powered — skip the staggered entrance reveal entirely
    // (jump straight to the final state, controller stays idle).
    if (widget.isTelevision) _revealCtrl.value = 1.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.isTelevision) _revealCtrl.forward();
      // Land focus on Play (or Sources when Play is hidden, e.g. PikPak) so
      // the remote has a starting point. TV only — on mobile/desktop an
      // auto-applied golden focus border just looks out of place.
      if (widget.isTelevision) {
        (widget.showQuickPlay ? _playFocus : _browseFocus).requestFocus();
      }
      _loadRecommendations();
      _loadEnrichedMeta();
      _loadParentsGuide();
      _loadImdbEnrichment();
    });
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

    final alreadyRich =
        (item.year != null && item.year!.isNotEmpty) ||
        item.imdbRating != null ||
        (item.genres?.isNotEmpty ?? false);
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
          sourceAddon: item.sourceAddon,
        );
      });
    } catch (_) {
      // Non-critical enrichment — swallow and keep the original item.
    }
  }

  Future<void> _loadImdbEnrichment() async {
    final imdbId = _item.effectiveImdbId;
    if (imdbId == null) {
      if (mounted) setState(() => _imdbLoaded = true);
      return;
    }
    try {
      final extra = await ImdbEnrichmentService.fetch(imdbId);
      if (mounted) setState(() { _imdbExtra = extra; _imdbLoaded = true; });
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
      if (mounted) setState(() { _parentsGuide = guide; _parentsGuideLoaded = true; });
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
      if (mounted) setState(() { _recommendations = recs; _recommendationsLoaded = true; });
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
    _revealCtrl.dispose();
    _playFocus.dispose();
    _browseFocus.dispose();
    _wideScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = _wide;
    final backdropUrl = _item.background ?? _item.poster;

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
            height: isWide ? size.height : size.height * 0.55,
            child: _Backdrop(
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
            child: isWide
                ? _buildWideContent(size)
                : _buildNarrowContent(size),
          ),

          // ── Back button ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(widget.isTelevision ? 28 : 8),
                child: _GlassIconButton(
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
    // Prime-style single natural scroll: hero, then title/meta/genres, then
    // Play/Sources high up, the quick-action row, and the synopsis. Nothing
    // is pinned — the important controls already sit in the first screenful.
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: size.height * 0.26, bottom: 36),
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
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
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
    final t = _tight; // vertically-constrained (e.g. Android TV 540px)
    final children = <Widget>[
      _secEyebrow(0.00),
      SizedBox(height: t ? 6 : 10),
      _secTitle(0.10),
      SizedBox(height: t ? 8 : 14),
      _secMeta(0.20),
    ];
    final g = _secGenres(0.28);
    if (g != null) children..add(SizedBox(height: t ? 10 : 18))..add(g);
    final aw = _secAwards(0.32);
    if (aw != null) children..add(SizedBox(height: t ? 6 : 10))..add(aw);
    children
      ..add(SizedBox(height: t ? 16 : 26))
      ..add(_buildActionRow(0.38));
    final d = _secDescription(0.46);
    if (d != null) children..add(SizedBox(height: t ? 12 : 24))..add(d);
    final cr = _secCredits(0.50);
    if (cr != null) children..add(SizedBox(height: t ? 10 : 18))..add(cr);
    final q = _secQuickActions(0.54);
    if (q != null) children..add(SizedBox(height: t ? 14 : 26))..add(q);
    final pg = _secParentsGuide(0.58);
    if (pg != null) children..add(SizedBox(height: t ? 12 : 22))..add(pg);
    final r = _secRecommendations(0.66);
    if (r != null) children..add(SizedBox(height: t ? 16 : 28))..add(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Narrow (Prime-style): one natural scroll — Play/Sources high under the
  /// meta, then the synopsis, then the quick-action grid.
  Widget _buildNarrowColumn() {
    final children = <Widget>[
      _secEyebrow(0.00),
      const SizedBox(height: 8),
      _secTitle(0.10),
      const SizedBox(height: 10),
      _secMeta(0.20),
    ];
    final g = _secGenres(0.28);
    if (g != null) children..add(const SizedBox(height: 14))..add(g);
    final aw = _secAwards(0.32);
    if (aw != null) children..add(const SizedBox(height: 8))..add(aw);
    children
      ..add(const SizedBox(height: 22))
      ..add(_buildActionRow(0.38));
    final d = _secDescription(0.46);
    if (d != null) children..add(const SizedBox(height: 22))..add(d);
    final cr = _secCredits(0.50);
    if (cr != null) children..add(const SizedBox(height: 16))..add(cr);
    final q = _secQuickActions(0.54);
    if (q != null) children..add(const SizedBox(height: 26))..add(q);
    final pg = _secParentsGuide(0.58);
    if (pg != null) children..add(const SizedBox(height: 20))..add(pg);
    final r = _secRecommendations(0.66);
    if (r != null) children..add(const SizedBox(height: 28))..add(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _secEyebrow(double start) => _Reveal(
        parent: _revealCtrl,
        start: start,
        child: Text(
          widget.item.type == 'series' ? 'SERIES' : 'MOVIE',
          style: TextStyle(
            color: HomeTheme.focusGold,
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

  Widget _secTitle(double start) => _Reveal(
        parent: _revealCtrl,
        start: start,
        child: Text(
          _item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
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
              Shadow(
                color: Color(0x66000000),
                blurRadius: 8,
              ),
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
    return _Reveal(
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
              _CertBadge(label: cert),
            ],
            if (runtime != null) ...[
              if (hasYear || cert != null) _dot(),
              Text(runtime),
            ],
            if (showMetaShimmer && cert == null && runtime == null) ...[
              if (hasYear) _dot(),
              Shimmer(width: 28, height: 16, borderRadius: BorderRadius.circular(4)),
              _dot(),
              Shimmer(width: 48, height: 14, borderRadius: BorderRadius.circular(4)),
            ],
            if (rating != null) ...[
              if (hasYear || cert != null || runtime != null) _dot(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Color(0xFFFACC15),
                  ),
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
              Shimmer(width: 60, height: 14, borderRadius: BorderRadius.circular(4)),
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
      return _Reveal(
        parent: _revealCtrl,
        start: start,
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: const [
            Shimmer(width: 64, height: 28, borderRadius: BorderRadius.all(Radius.circular(14))),
            Shimmer(width: 52, height: 28, borderRadius: BorderRadius.all(Radius.circular(14))),
            Shimmer(width: 72, height: 28, borderRadius: BorderRadius.all(Radius.circular(14))),
          ],
        ),
      );
    }
    return _Reveal(
      parent: _revealCtrl,
      start: start,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [for (final g in genres.take(5)) _GenreChip(label: g)],
      ),
    );
  }

  Widget? _secAwards(double start) {
    final extra = _imdbExtra;
    if (extra == null || !extra.hasAwards) return null;
    return _Reveal(
      parent: _revealCtrl,
      start: start,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 15,
            color: Color(0xFFFBBF24),
          ),
          const SizedBox(width: 6),
          Text(
            extra.awardsLine!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: _tight ? 11 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _secCredits(double start) {
    final extra = _imdbExtra;
    if (extra == null) {
      if (_imdbLoaded) return null;
      final h = _tight ? 10.0 : 12.0;
      return _Reveal(
        parent: _revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Shimmer(width: 60, height: h, borderRadius: BorderRadius.circular(4)),
              const SizedBox(width: 10),
              Shimmer(width: 140, height: h, borderRadius: BorderRadius.circular(4)),
            ]),
            SizedBox(height: _tight ? 4 : 8),
            Row(children: [
              Shimmer(width: 60, height: h, borderRadius: BorderRadius.circular(4)),
              const SizedBox(width: 10),
              Shimmer(width: 200, height: h, borderRadius: BorderRadius.circular(4)),
            ]),
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

    return _Reveal(
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
                SizedBox(
                  width: 70,
                  child: Text('Director', style: labelStyle),
                ),
                Expanded(
                  child: Text(extra.director!, style: valueStyle),
                ),
              ],
            ),
            if (hasStars) SizedBox(height: _tight ? 4 : 6),
          ],
          if (hasStars)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 70,
                  child: Text('Stars', style: labelStyle),
                ),
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

  Widget? _secParentsGuide(double start) {
    final guide = _parentsGuide;
    if (guide == null) {
      if (_parentsGuideLoaded) return null;
      final rowH = _tight ? 38.0 : 44.0;
      return _Reveal(
        parent: _revealCtrl,
        start: start,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Shimmer(width: 130, height: 14, borderRadius: BorderRadius.circular(4)),
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
    return _Reveal(
      parent: _revealCtrl,
      start: start,
      child: ParentsGuideSection(
        guide: guide,
        tv: widget.isTelevision,
        dense: _tight,
      ),
    );
  }

  Widget? _secQuickActions(double start) {
    if (widget.traktMenuOptions.isEmpty || widget.onTraktAction == null) {
      return null;
    }
    return _Reveal(
      parent: _revealCtrl,
      start: start,
      child: _QuickActions(
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
    final loading = recs == null && !_recommendationsLoaded && widget.recommendationsLoader != null;

    if (!loading && (recs == null || recs.isEmpty || onTap == null)) return null;

    return _Reveal(
      parent: _revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? Shimmer(width: 130, height: 16, borderRadius: BorderRadius.circular(4))
              : Text(
                  'More Like This',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: _wide && !tight ? 18 : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
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
                            _RecCard(
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
    return _Reveal(
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
                shadows: const [Shadow(color: Color(0x88000000), blurRadius: 8)],
              ),
            ),
            SizedBox(height: _tight ? 6 : 10),
          ],
          if (_wide)
            _Description(
              text: description,
              wide: true,
              dense: _tight,
              collapsedLines: _tight ? 2 : 4,
              expanded: _descriptionExpanded,
              onToggle: () => setState(
                () => _descriptionExpanded = !_descriptionExpanded,
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
                shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
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
    return _Reveal(
      parent: _revealCtrl,
      start: start,
      dy: 16,
      child: _ActionRow(
        compact: !_wide,
        showQuickPlay: widget.showQuickPlay,
        isSeries: item.type == 'series',
        hasBoundSource: widget.hasBoundSource,
        playFocus: _playFocus,
        browseFocus: _browseFocus,
        tv: widget.isTelevision,
        // TV only: the top row is the highest focusable widget, so a D-pad
        // "up" there reveals the header instead of dead-ending.
        onArrowUp: widget.isTelevision ? _scrollWideToTop : null,
        onPlay: widget.onPlay,
        // Neither Play nor Browse pop here: the player pushes on top of
        // this detail screen so the user returns here when playback ends.
        // Browse keeps the detail for the same reason (series drill-down
        // stacks on top). The host handles teardown via _returnToCatalogIfNeeded.
        onBrowse: widget.onBrowse,
      ),
    );
  }

  Widget _dot() => Text(
        '·',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 14,
        ),
      );
}

// ── Staggered entrance reveal ───────────────────────────────────────────────

/// Fades + slides a section in from below, on an [Interval] of [parent] so
/// successive sections cascade. Cheap: a single shared controller drives all.
class _Reveal extends StatelessWidget {
  final AnimationController parent;

  /// Where on the 0‥1 timeline this section starts (earlier = sooner).
  final double start;

  /// How far (px) it travels up into place.
  final double dy;
  final Widget child;

  const _Reveal({
    required this.parent,
    required this.start,
    required this.child,
    this.dy = 26,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: parent,
      curve: Interval(
        start,
        (start + 0.42).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * dy),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ── Backdrop ────────────────────────────────────────────────────────────────

/// Cinematic backdrop: a slow Ken-Burns push-in, a gentle fade-in once the
/// image decodes, a layered vertical scrim, a corner vignette, and (on wide)
/// a left-side scrim where the content sits.
class _Backdrop extends StatefulWidget {
  final String? url;
  final bool isWide;

  /// When false (TV) the Ken-Burns push-in and fade-in are skipped — a
  /// static image, so there's no continuous repaint on low-power devices.
  final bool animate;
  const _Backdrop({
    required this.url,
    required this.isWide,
    this.animate = true,
  });

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop>
    with SingleTickerProviderStateMixin {
  AnimationController? _ken;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ken = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 22),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ken?.dispose();
    super.dispose();
  }

  Widget _image(String url) {
    final ken = _ken;

    // Static (TV): no fade-in, no Ken-Burns — cheapest possible.
    if (ken == null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      );
    }

    return AnimatedBuilder(
      animation: ken,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(ken.value);
        return Transform.scale(
          scale: 1.0 + 0.07 * t,
          alignment: Alignment(0, -0.7 + 0.2 * t),
          child: child,
        );
      },
      child: Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        frameBuilder: (_, child, frame, wasSync) {
          if (wasSync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = widget.isWide;
    final url = widget.url;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            _image(url)
          else
            Container(color: Colors.black),

          // Base darkening wash — guarantees legibility even on pure-white
          // or very bright posters. Uniform tint, no gradient.
          const ColoredBox(color: Color(0x44000000)),

          // Corner vignette — frames the art, cinema style.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.25),
                radius: 1.15,
                colors: [
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x66000000),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // Vertical scrim — heavier than before so content stays readable
          // regardless of poster brightness.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0x33000000),
                  Color(0x66000000),
                  Color(0xCC050507),
                  Color(0xF5050507),
                  Color(0xFF050507),
                ],
                stops: isWide
                    ? const [0.0, 0.30, 0.58, 0.82, 1.0]
                    : const [0.0, 0.32, 0.62, 0.86, 1.0],
              ),
            ),
          ),

          // Side scrim on wide layouts — darken the left where content sits,
          // fade to clear art on the right.
          if (isWide)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xEE050507),
                    Color(0x99050507),
                    Color(0x33000000),
                    Color(0x00000000),
                  ],
                  stops: [0.0, 0.32, 0.60, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Certificate badge ──────────────────────────────────────────────────────

class _CertBadge extends StatelessWidget {
  final String label;
  const _CertBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.50),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          height: 1.3,
        ),
      ),
    );
  }
}

// ── Genre chip ──────────────────────────────────────────────────────────────

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Recommendation ("Watch Next") card ─────────────────────────────────────

class _RecCard extends StatefulWidget {
  final StremioMeta item;
  final double width;
  final double posterHeight;
  final bool tv;
  final VoidCallback onTap;

  const _RecCard({
    required this.item,
    required this.width,
    required this.posterHeight,
    required this.tv,
    required this.onTap,
  });

  @override
  State<_RecCard> createState() => _RecCardState();
}

class _RecCardState extends State<_RecCard> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final poster = widget.item.poster;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            duration:
                widget.tv ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: _active ? 1.05 : 1.0,
            child: SizedBox(
              width: widget.width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: widget.width,
                      height: widget.posterHeight,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: _active
                              ? HomeTheme.focusGold
                              : Colors.white.withValues(alpha: 0.10),
                          width: _active ? 2 : 0.5,
                        ),
                      ),
                      child: (poster != null && poster.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _posterFallback(),
                              errorWidget: (_, __, ___) => _posterFallback(),
                            )
                          : _posterFallback(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: _active ? 1.0 : 0.82),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
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

  Widget _posterFallback() => Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.item.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

// ── Description with "Read more" ───────────────────────────────────────────

class _Description extends StatelessWidget {
  final String text;
  final bool wide;
  final bool dense;
  final int collapsedLines;
  final bool expanded;
  final VoidCallback onToggle;
  const _Description({
    required this.text,
    required this.wide,
    required this.expanded,
    required this.onToggle,
    this.dense = false,
    this.collapsedLines = 4,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.82),
      fontSize: dense ? 13 : (wide ? 17 : 15),
      height: dense ? 1.4 : 1.5,
      letterSpacing: 0.1,
      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: style,
              maxLines: expanded ? null : collapsedLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.fade,
            ),
            if (overflows) ...[
              const SizedBox(height: 6),
              _ReadMoreToggle(
                label: expanded ? 'Show less' : 'Read more',
                onToggle: onToggle,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Focusable "Read more / Show less" toggle. A bare GestureDetector is not
/// reachable or activatable with a D-pad/remote, so this mirrors the
/// focus idiom used by [_QuickAction]: a [Focus] that tracks focus, accepts
/// select/enter/space, and shows a gold affordance when focused or hovered.
class _ReadMoreToggle extends StatefulWidget {
  final String label;
  final VoidCallback onToggle;
  const _ReadMoreToggle({required this.label, required this.onToggle});

  @override
  State<_ReadMoreToggle> createState() => _ReadMoreToggleState();
}

class _ReadMoreToggleState extends State<_ReadMoreToggle> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onToggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onToggle,
          behavior: HitTestBehavior.opaque,
          // Inactive state is byte-identical to the old bare text link (no
          // box/indent, so the phone/touch look is unchanged). Focus/hover is
          // signalled with gold + underline + a transform-only scale (no
          // layout reflow), echoing _QuickAction's scale feedback.
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: _active ? 1.04 : 1.0,
            alignment: Alignment.centerLeft,
            child: Text(
              widget.label,
              style: TextStyle(
                color: _active
                    ? HomeTheme.focusGold
                    : Colors.white.withValues(alpha: 0.95),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                decoration: _active ? TextDecoration.underline : null,
                decorationColor: HomeTheme.focusGold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Action row (PLAY + BROWSE) ──────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final bool compact;
  final bool showQuickPlay;
  final bool isSeries;
  final bool hasBoundSource;
  final FocusNode playFocus;
  final FocusNode browseFocus;
  final bool tv;
  final VoidCallback onPlay;
  final VoidCallback onBrowse;

  /// D-pad "up" handler — the row is the top focusable, so this scrolls the
  /// sheet back to the header rather than letting focus dead-end. Null off TV.
  final VoidCallback? onArrowUp;

  const _ActionRow({
    required this.compact,
    required this.showQuickPlay,
    required this.isSeries,
    required this.hasBoundSource,
    required this.playFocus,
    required this.browseFocus,
    required this.tv,
    required this.onPlay,
    required this.onBrowse,
    this.onArrowUp,
  });

  @override
  Widget build(BuildContext context) {
    final browseLabel = isSeries ? 'Episodes' : 'Sources';
    final browseIcon = isSeries ? Icons.list_alt_rounded : Icons.layers_rounded;
    final gap = compact ? 8.0 : 10.0;

    final browse = _PrimaryButton(
      focusNode: browseFocus,
      icon: browseIcon,
      label: browseLabel,
      filled: !showQuickPlay,
      compact: compact,
      tv: tv,
      onTap: onBrowse,
      onArrowUp: onArrowUp,
      tinted: hasBoundSource,
    );

    if (!showQuickPlay) return browse;

    final play = _PrimaryButton(
      focusNode: playFocus,
      icon: Icons.play_arrow_rounded,
      label: 'Play',
      filled: true,
      compact: compact,
      tv: tv,
      accent: _kNetflixRed,
      onTap: onPlay,
      onArrowUp: onArrowUp,
    );

    // Narrow screens: stack a full-width Play on top of Sources so every
    // label has room and never gets clipped.
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          play,
          SizedBox(height: gap),
          browse,
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: play),
        SizedBox(width: gap),
        Expanded(flex: 2, child: browse),
      ],
    );
  }
}

const Color _kNetflixRed = Color(0xFFE50914);

// ── Quick actions row ───────────────────────────────────────────────────────

/// Prime-style quick actions: a wrapped grid of uniform icon buttons with a
/// caption underneath. Everything is visible at once — no hidden scroll — so
/// users always see every action. Items are a fixed width so rows align.
class _QuickActions extends StatelessWidget {
  final List<TraktMenuOption> options;
  final bool tv;

  /// Phone (narrow layout): lay out as an even 3-column grid so narrow
  /// widths don't drop to an ugly 2-up. Wide/TV keeps the free wrap.
  final bool phone;
  final void Function(TraktItemMenuAction) onSelected;

  const _QuickActions({
    required this.options,
    required this.tv,
    required this.phone,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 16),
        if (phone) _grid() else _wrap(),
      ],
    );
  }

  Widget _wrap() => Wrap(
        spacing: 8,
        runSpacing: 18,
        children: [
          for (final o in options)
            _QuickAction(
              option: o,
              tv: tv,
              onTap: () => onSelected(o.action),
            ),
        ],
      );

  Widget _grid() {
    const cols = 3;
    const gap = 8.0;
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += cols) {
      final cells = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0) cells.add(const SizedBox(width: gap));
        final idx = i + j;
        cells.add(
          Expanded(
            child: idx < options.length
                ? _QuickAction(
                    option: options[idx],
                    tv: tv,
                    expand: true,
                    onTap: () => onSelected(options[idx].action),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      if (i > 0) rows.add(const SizedBox(height: 18));
      rows.add(
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

class _QuickAction extends StatefulWidget {
  final TraktMenuOption option;
  final bool tv;

  /// Grid mode: fill the parent cell instead of a fixed 80px box.
  final bool expand;
  final VoidCallback onTap;

  const _QuickAction({
    required this.option,
    required this.tv,
    required this.onTap,
    this.expand = false,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final o = widget.option;

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            duration: widget.tv
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: _active ? 1.06 : 1.0,
            child: SizedBox(
              width: widget.expand ? null : 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: widget.tv
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white
                              .withValues(alpha: _active ? 0.16 : 0.07),
                          border: Border.all(
                            color: _active
                                ? HomeTheme.focusGold
                                : Colors.white.withValues(alpha: 0.12),
                            width: _active ? 1.6 : 1,
                          ),
                          boxShadow: _active
                              ? [
                                  BoxShadow(
                                    color: HomeTheme.focusGold
                                        .withValues(alpha: 0.32),
                                    blurRadius: 18,
                                    spreadRadius: 0.5,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          o.icon,
                          size: 24,
                          color: Colors.white
                              .withValues(alpha: _active ? 1.0 : 0.92),
                        ),
                      ),
                      if (o.isTrakt)
                        Positioned(
                          top: -4,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFED1C24),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFF050507),
                                width: 1.5,
                              ),
                            ),
                            child: const Text(
                              'TRAKT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 7,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    o.caption,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: _active ? 1.0 : 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      height: 1.15,
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
  final FocusNode focusNode;
  final IconData icon;
  final String label;

  /// Filled buttons get a solid background ([accent] when provided, white
  /// otherwise). Outlined buttons have a glass background.
  final bool filled;
  final bool tinted;

  /// Narrow screens: shorter button, smaller icon/text, tighter spacing.
  final bool compact;

  /// TV: skip the focus tween (instant), keep the highlight.
  final bool tv;

  /// Optional brand accent for a filled button. Falls back to white.
  final Color? accent;
  final VoidCallback onTap;

  /// D-pad "up" handler (TV). Set on the top action row so "up" reveals the
  /// header rather than dead-ending focus traversal.
  final VoidCallback? onArrowUp;

  const _PrimaryButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    this.compact = false,
    this.tv = false,
    this.tinted = false,
    this.accent,
    this.onArrowUp,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final accent = widget.accent;

    final filledBg = accent ?? Colors.white;
    final filledFg = accent == null ? Colors.black : Colors.white;

    final bg = filled
        ? (_focused
            ? Color.lerp(filledBg, Colors.white, 0.12)!
            : filledBg)
        : (_focused
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06));

    final fg = filled ? filledFg : Colors.white;

    // Focus is always shown as a bright gold ring + glow (+ a slight
    // scale-up) regardless of the button's base colour, so it's obvious
    // even on the red Play button.
    final Color borderColor;
    if (_focused) {
      borderColor = HomeTheme.focusGold;
    } else if (filled) {
      borderColor = Colors.transparent;
    } else if (widget.tinted) {
      // A bound source: hint with a soft gold resting border.
      borderColor = HomeTheme.focusGold.withValues(alpha: 0.5);
    } else {
      borderColor = Colors.white.withValues(alpha: 0.18);
    }
    final borderWidth = _focused ? 2.5 : (filled ? 0.0 : 1.2);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // Nothing focusable sits above this row, so consume "up" and use
          // it to bring the header back into view instead of no-op.
          if (widget.onArrowUp != null &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            widget.onArrowUp!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: widget.tv
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          scale: _focused ? 1.035 : 1.0,
          child: AnimatedContainer(
            duration: widget.tv
                ? Duration.zero
                : const Duration(milliseconds: 160),
            height: widget.compact ? 48 : 54,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: HomeTheme.focusGold.withValues(alpha: 0.55),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: fg, size: widget.compact ? 20 : 24),
                SizedBox(width: widget.compact ? 7 : 10),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: widget.compact ? 14 : 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
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

// ── Glass icon button (back) ────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

