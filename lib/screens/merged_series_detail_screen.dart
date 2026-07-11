import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../models/playlist_view_mode.dart';
import '../services/imdb_enrichment_service.dart';
import '../services/imdb_parents_guide_service.dart';
import '../services/video_player_launcher.dart';
import '../services/youtube_service.dart';
import '../widgets/episodes_panel.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/parents_guide_section.dart';
import '../widgets/trakt/trakt_menu_helpers.dart';
import 'episodes_screen.dart' show kCatalogDetailRouteName;

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
  final VoidCallback onResume;

  /// Movie only: open the Sources list (manual pick). Ignored for series (the
  /// episode list is the picker). When null the Sources button is hidden.
  final VoidCallback? onBrowse;

  /// Episode terminal callbacks — the exact ones the Search tab passes to
  /// `EpisodesScreen` today (`_playSelection` / `_browseSelection`).
  final void Function(AdvancedSearchSelection selection)? onItemSelected;
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Host-owned source binding.
  final int Function(StremioMeta show)? boundSourceCount;
  final Future<void> Function(StremioMeta show)? onSelectSource;

  /// Quick-action strip (Trakt / app actions), identical to the detail screen.
  final List<TraktMenuOption> traktMenuOptions;
  final void Function(TraktItemMenuAction action)? onTraktAction;

  /// "More Like This" rail + sparse-item meta backfill (same loaders the detail
  /// screen receives).
  final Future<List<StremioMeta>> Function()? recommendationsLoader;
  final void Function(StremioMeta recommendation)? onRecommendationTap;
  final Future<StremioMeta?> Function(String imdbId, String type)? metaEnricher;

  const MergedDetailScreen({
    super.key,
    required this.item,
    required this.addon,
    required this.onResume,
    this.onBrowse,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.isTraktSource = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.boundSourceCount,
    this.onSelectSource,
    this.traktMenuOptions = const [],
    this.onTraktAction,
    this.recommendationsLoader,
    this.onRecommendationTap,
    this.metaEnricher,
  });

  @override
  State<MergedDetailScreen> createState() =>
      _MergedDetailScreenState();
}

class _MergedDetailScreenState extends State<MergedDetailScreen> {
  // ── Stremio-flat palette (neutral glass + gold state) ──
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _gold = Color(0xFFF5B942);
  static const Color _imdb = Color(0xFFF5C518);
  static Color get _glass2 => Colors.white.withValues(alpha: 0.07);
  static Color get _hair => Colors.white.withValues(alpha: 0.09);

  ImdbEnrichment? _imdbExtra;
  ParentsGuideResult? _parentsGuide;
  List<StremioMeta>? _recommendations;
  StremioMeta? _enriched;

  /// Trailer YouTube ID, resolved from Cinemeta meta. Null until loaded / when
  /// the title has no trailer — the Trailer button only shows once this is set.
  String? _trailerYtId;

  /// Guards against a double-launch while a trailer's streams resolve.
  bool _trailerLoading = false;

  /// Scrolls the left info column. Focus-anchored (see [_ScrollAnchor]) so that
  /// focusing the top action row snaps to the very top (revealing the
  /// title/meta/summary above it), and focusing a lower section brings it fully
  /// into view — fixing the "can't scroll back up to the details" DPAD bug.
  final ScrollController _infoScroll = ScrollController();

  /// The stable LEFT-crossing target for episodes: the info column's primary
  /// action (Play/Resume, or the source pill when Play is hidden). Pressing LEFT
  /// on an episode focuses this instead of a geometry-picked mid-column item.
  final FocusNode _leftEntryFocusNode =
      FocusNode(debugLabel: 'merged-left-entry');

  StremioMeta get _item => _enriched ?? widget.item;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadEnrichedMeta();
      _loadImdbEnrichment();
      _loadParentsGuide();
      _loadRecommendations();
      _loadTrailer();
    });
  }

  @override
  void dispose() {
    _infoScroll.dispose();
    _leftEntryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadEnrichedMeta() async {
    final enrich = widget.metaEnricher;
    final item = widget.item;
    final imdbId = item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;
    final alreadyRich = (item.year != null && item.year!.isNotEmpty) ||
        item.imdbRating != null ||
        (item.genres?.isNotEmpty ?? false);
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
          genres: (full.genres?.isNotEmpty ?? false) ? full.genres : item.genres,
          sourceAddon: item.sourceAddon,
          trailerYtId: full.trailerYtId ?? item.trailerYtId,
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
    // If the item already arrived with a trailer id, use it as-is.
    final existing = widget.item.trailerYtId;
    if (existing != null && existing.isNotEmpty) {
      if (mounted) setState(() => _trailerYtId = existing);
      return;
    }
    final enrich = widget.metaEnricher;
    final imdbId = widget.item.effectiveImdbId;
    if (enrich == null || imdbId == null) return;
    try {
      final full = await enrich(imdbId, widget.item.type);
      final ytId = full?.trailerYtId;
      if (ytId == null || ytId.isEmpty || !mounted) return;
      setState(() => _trailerYtId = ytId);
    } catch (_) {}
  }

  /// Resolve the trailer's YouTube streams on-device and launch the player.
  /// Mirrors the Lemmy/YouTube playback path. Fails gracefully with a snackbar —
  /// youtube_explode can be bot-blocked and not every title has a live trailer.
  Future<void> _playTrailer() async {
    final ytId = _trailerYtId;
    if (ytId == null || _trailerLoading) return;
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _trailerLoading = false);

    final playUrl = streams?.playUrl;
    if (playUrl == null || playUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t load trailer')),
      );
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

  @override
  Widget build(BuildContext context) {
    final backdropUrl = _item.background ?? _item.poster;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Blurred full-bleed backdrop → the Stremio "one lit surface" feel.
          if (backdropUrl != null)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                child: CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Darker tint so even a bright poster reads as a dark surface.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _bg.withValues(alpha: 0.60),
                    _bg.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: _isMovie
                // A movie has no episode list — one centered, scrollable Stremio
                // detail column (same theme as the series page).
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _buildInfoPane(),
                    ),
                  )
                : (_wide
                    ? _buildTwoPane(backdropUrl)
                    : Column(
                        children: [
                          _buildHero(backdropUrl),
                          Expanded(child: _buildStackedBody()),
                        ],
                      )),
          ),
          // Back button.
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(widget.isTelevision ? 20 : 8),
                child: _circleButton(
                  Icons.arrow_back_rounded,
                  () => Navigator.of(context).maybePop(),
                  tooltip: 'Back',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TV + desktop: left info column (scrollable) + right episode column (full
  /// height). Episodes own Up/Down + in-card Left/Right; the info column is
  /// reached by Up to the season selector then Left, or from the back button.
  Widget _buildTwoPane(String? backdropUrl) {
    final w = MediaQuery.of(context).size.width;
    final leftW = (w * 0.42).clamp(320.0, 480.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left info column, darkened so text stays legible over any backdrop.
        SizedBox(
          width: leftW,
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
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0E0B14).withValues(alpha: 0.82),
              border: Border(left: BorderSide(color: _hair)),
            ),
            child: _buildEpisodesPanel(),
          ),
        ),
      ],
    );
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
          Text(
            _isMovie ? 'MOVIE' : 'SERIES',
            style: TextStyle(
              color: _gold,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
            ),
          ),
          SizedBox(height: t ? 5 : 8),
          Text(
            item.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: t ? 22 : 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.05,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
            ),
          ),
          SizedBox(height: t ? 8 : 10),
          _buildMetaBar(year, extra, rating),
          if (genres.isNotEmpty) ...[
            SizedBox(height: t ? 8 : 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [for (final g in genres.take(3)) _pill(g)],
            ),
          ],
          SizedBox(height: t ? 12 : 16),
          // Focusing the action row snaps the column to the very top so the
          // title / meta / genres above it are revealed (fixes "can't scroll
          // back up to details").
          _ScrollAnchor(
              toTop: true,
              active: widget.isTelevision,
              child: _buildActionRow()),
          if (summary != null && summary.isNotEmpty) ...[
            SizedBox(height: t ? 16 : 20),
            _sectionLabel('Summary'),
            const SizedBox(height: 8),
            Text(
              summary,
              style: const TextStyle(
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
  Widget _buildHero(String? backdropUrl) {
    final item = _item;
    final extra = _imdbExtra;
    const heroH = 220.0;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = (item.genres?.isNotEmpty ?? false)
        ? item.genres!
        : (extra?.genres ?? const []);

    return SizedBox(
      height: heroH,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropUrl != null)
            CachedNetworkImage(
              imageUrl: backdropUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _bg.withValues(alpha: 0.10),
                  _bg.withValues(alpha: 0.55),
                  _bg,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.isTelevision ? 40 : 24,
                0,
                24,
                14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SERIES',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
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
                  const SizedBox(height: 10),
                  _buildMetaBar(year, extra, rating),
                  if (genres.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final g in genres.take(4)) _pill(g),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildActionRow(),
                ],
              ),
            ),
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
      add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: _glass2,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _hair),
        ),
        child: Text(
          cert,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ));
    }
    if (rating != null) {
      add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
      ));
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }

  Widget _metaText(String s) => Text(
        s,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _buildActionRow() {
    final count = widget.boundSourceCount?.call(_item) ?? 0;
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
            label: _isMovie ? 'Play' : 'Resume',
            icon: Icons.play_arrow_rounded,
            onTap: widget.onResume,
            focusNode: _leftEntryFocusNode,
            autofocus: widget.isTelevision && _isMovie,
          ),
        // Trailer — sits right after Play. Only when Cinemeta gave us a YouTube
        // trailer id. Plays on-device via youtube_explode (same path as the
        // YouTube/Lemmy tabs).
        if (_trailerYtId != null)
          _GhostButton(
            label: 'Trailer',
            icon: Icons.movie_outlined,
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
        // Source binding. Takes the LEFT-entry focus node only when Play is
        // hidden (PikPak), so LEFT from an episode always lands on a live target.
        if (widget.onSelectSource != null)
          _SourcePill(
            count: count,
            focusNode: widget.showQuickPlay ? null : _leftEntryFocusNode,
            // A movie with Play hidden (PikPak-only) has no episode list to
            // auto-focus and no Play to autofocus — start the remote here.
            autofocus:
                widget.isTelevision && _isMovie && !widget.showQuickPlay,
            onTap: () async {
              await widget.onSelectSource!(_item);
              if (mounted) setState(() {});
            },
          ),
        // More — opens the labelled quick-actions menu (with descriptions).
        if (widget.traktMenuOptions.isNotEmpty && widget.onTraktAction != null)
          _RoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More options',
            onTap: _showQuickActionsMenu,
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
    }
  }

  void _showQuickActionsMenu() {
    final options = widget.traktMenuOptions;
    if (options.isEmpty || widget.onTraktAction == null) return;
    showModalBottomSheet<void>(
      context: context,
      // Same standard sheet chrome as the per-episode ⋮ menu.
      backgroundColor: const Color(0xFF141019),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _QuickActionsMenu(
        title: _item.name,
        options: options,
        isTelevision: widget.isTelevision,
        onSelected: (action) {
          Navigator.of(sheetCtx).pop();
          widget.onTraktAction!(action);
        },
      ),
    );
  }

  // ── Bodies ────────────────────────────────────────────────────────────────

  Widget _buildEpisodesPanel() {
    return EpisodesPanel(
      show: widget.item,
      addon: widget.addon,
      isTelevision: widget.isTelevision,
      // Match the standalone `_openEpisodes` flow, which does NOT pass
      // showQuickPlay (defaults true) — episode tiles keep quick-play even for
      // PikPak-only. Only the hero Resume (≙ detail "Play") is PikPak-gated.
      showQuickPlay: true,
      isTraktSource: widget.isTraktSource,
      onItemSelected: widget.onItemSelected,
      onQuickPlay: widget.onQuickPlay,
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
      // Terminal episode selection: tear down every merged/detail route back to
      // the Search host, then dispatch — mirroring the standalone
      // EpisodesScreen._popToHost. A single pop would leave a *parent* merged
      // screen (series A → recommended series B → pick episode) underneath
      // instead of returning to Search; popUntil the route name tears down any
      // depth (every merged/detail route shares kCatalogDetailRouteName).
      onBeforeTerminalDispatch: () => Navigator.of(context).popUntil(
        (r) => r.settings.name != kCatalogDetailRouteName,
      ),
    );
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
              icon: const Icon(Icons.info_outline_rounded, size: 18),
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
        ..add(Text(
          summary,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13.5,
            height: 1.55,
          ),
        ))
        ..add(const SizedBox(height: 22));
    }

    // Awards (gold pill) — parity with the detail screen.
    final awardsLine = extra?.hasAwards == true ? extra!.awardsLine : null;
    if (awardsLine != null && awardsLine.isNotEmpty) {
      sections
        ..add(Container(
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
        ))
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

    final cast = extra?.cast ?? const [];
    if (cast.isNotEmpty) {
      sections
        ..add(_sectionLabel('Cast'))
        ..add(const SizedBox(height: 12))
        ..add(_ScrollAnchor(
          active: widget.isTelevision,
          alignment: 0.35,
          child: SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _castTile(cast[i]),
            ),
          ),
        ))
        ..add(const SizedBox(height: 22));
    }

    // More Like This — placed high (right after Cast) so it's an easy DPAD-down
    // reach, ahead of the long focusable Parents-Guide list.
    final recs = _recommendations;
    if (recs != null && recs.isNotEmpty && widget.onRecommendationTap != null) {
      sections
        ..add(_sectionLabel('More Like This'))
        ..add(const SizedBox(height: 12))
        ..add(_ScrollAnchor(
          active: widget.isTelevision,
          alignment: 0.5,
          child: SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (_, i) => _recCard(recs[i]),
            ),
          ),
        ))
        ..add(const SizedBox(height: 22));
    }

    final guide = _parentsGuide;
    if (guide != null && !guide.isEmpty) {
      sections
        ..add(_sectionLabel('Parents Guide'))
        ..add(const SizedBox(height: 12))
        ..add(ParentsGuideSection(
          guide: guide,
          tv: widget.isTelevision,
          dense: true,
        ));
    }

    return sections;
  }


  Widget _castTile(CastMember m) => _CastTile(member: m, fallback: _glass2);

  Widget _recCard(StremioMeta rec) => _RecCard(
        rec: rec,
        fallback: _glass2,
        onTap: () => widget.onRecommendationTap?.call(rec),
      );

  Widget _sectionLabel(String s) => Text(
        s.toUpperCase(),
        style: const TextStyle(
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
        child: Text(
          s,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      );

  Widget _circleButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return _RoundIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      background: Colors.black.withValues(alpha: 0.35),
    );
  }
}

// ── Small presentational widgets ───────────────────────────────────────────

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

  const _FocusHalo({required this.focused, required this.child, this.radius});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      foregroundDecoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: focused
            ? Border.all(color: HomeTheme.focusGold, width: 2.5)
            : null,
      ),
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
                          errorWidget: (_, __, ___) =>
                              Container(color: widget.fallback),
                        )
                      : Container(
                          color: widget.fallback,
                          child:
                              const Icon(Icons.person, color: Colors.white38),
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
              child: (rec.poster != null && rec.poster!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: rec.poster!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: widget.fallback),
                    )
                  : Container(color: widget.fallback),
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
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: _focused ? 1.05 : 1.0,
      child: _FocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(999),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
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
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
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
                Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: const TextStyle(
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


/// Circular translucent icon button used for the hero "More" (⋮) affordance.
class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? background;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final btn = _FocusHalo(
      focused: _focused,
      child: Material(
        color: widget.background ?? Colors.white.withValues(alpha: 0.08),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(widget.icon, color: Colors.white, size: 22),
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
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
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
                      'Quick Actions',
                      style: TextStyle(
                        color: Colors.white,
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
                      style: const TextStyle(
                        color: Colors.white,
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
