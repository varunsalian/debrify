import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../episodes_panel.dart';
import '../parents_guide_section.dart';
import 'detail_episode_cells.dart';
import 'detail_identity.dart';
import 'detail_model.dart';
import 'detail_style.dart';

/// **Stage** — a true split: artwork owns the top half, and the bottom half is
/// a tabbed deck holding Episodes, Cast, About, Similar and the Parents Guide.
///
/// The structural axis is **tabs**: everything the page knows has a home, and
/// none of it costs vertical scroll on any device — which is also what makes it
/// the cheapest layout to serve both a series and a movie (a movie simply drops
/// the Episodes tab).
///
/// A tab whose panel would be empty is never rendered, so the deck can't
/// present a blank room — and switching tabs returns focus to the strip rather
/// than into a subtree that just got replaced.
class DetailStage extends StatefulWidget {
  final DetailModel model;
  final Widget Function(
    Widget Function(BuildContext, EpisodesPanelView) contentBuilder,
  )?
  episodesHost;

  const DetailStage({
    super.key,
    required this.model,
    required this.episodesHost,
  });

  @override
  State<DetailStage> createState() => _DetailStageState();
}

enum _Tab { episodes, cast, about, similar, guide }

class _DetailStageState extends State<DetailStage> {
  final DetailCellNodes _cellNodes = DetailCellNodes('stage');
  int _handledGeneration = -1;

  final FocusNode _seasonNode = FocusNode(debugLabel: 'stage-season');
  final FocusNode _retryNode = FocusNode(debugLabel: 'stage-retry');
  final ScrollController _episodeScroll = ScrollController();

  /// Keyed by tab IDENTITY, never by list index: Cast/About/Similar/Guide are
  /// inserted as metadata lands, so an index-keyed node would silently be
  /// reassigned to a different tab under a focused cursor.
  final Map<_Tab, FocusNode> _tabNodes = {};
  final FocusNode _sourcesNode = FocusNode(debugLabel: 'stage-tab-sources');
  _Tab _active = _Tab.episodes;

  @override
  void dispose() {
    _cellNodes.dispose();
    for (final n in _tabNodes.values) {
      n.dispose();
    }
    _sourcesNode.dispose();
    _seasonNode.dispose();
    _retryNode.dispose();
    _episodeScroll.dispose();
    super.dispose();
  }

  FocusNode _tabNode(_Tab t) => _tabNodes.putIfAbsent(
    t,
    () => FocusNode(debugLabel: 'stage-tab-${t.name}'),
  );

  /// First tab in RENDER order — map iteration follows node-creation order, and
  /// Cast/About/Similar arrive as metadata lands, so an existing node can sit
  /// ahead of the tab that is actually drawn first.
  FocusNode? _firstTabNodeFor(DetailModel m) {
    for (final t in _tabsFor(m)) {
      final n = _tabNodes[t];
      if (n != null && n.context != null) return n;
    }
    return _sourcesNode.context != null ? _sourcesNode : null;
  }

  /// Only tabs that actually have something to show.
  List<_Tab> _tabsFor(DetailModel m) => [
    if (!m.isMovie && widget.episodesHost != null) _Tab.episodes,
    if (m.cast.isNotEmpty) _Tab.cast,
    if (m.synopsis?.isNotEmpty == true || m.detailRows.isNotEmpty) _Tab.about,
    if (m.recommendations.isNotEmpty && m.onRecommendationTap != null)
      _Tab.similar,
    if (m.parentsGuide != null && !m.parentsGuide!.isEmpty) _Tab.guide,
  ];

  String _label(_Tab t) => switch (t) {
    _Tab.episodes => 'Episodes',
    _Tab.cast => 'Cast',
    _Tab.about => 'About',
    _Tab.similar => 'Similar',
    _Tab.guide => 'Parents Guide',
  };

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final size = resolveDetailSize(
      isTelevision: m.isTelevision,
      size: MediaQuery.of(context).size,
    );
    final tabs = _tabsFor(m);
    if (tabs.isNotEmpty && !tabs.contains(_active)) _active = tabs.first;
    // Sources is a tab-shaped ACTION, so a movie with no panel content still
    // needs the strip drawn — otherwise the button is unreachable.
    final hasSources = m.isMovie && m.onBrowse != null;
    final showStrip = tabs.isNotEmpty || hasSources;
    final topFraction = size.isPhone ? 0.38 : 0.52;

    return Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * topFraction,
          child: _stage(m, size),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: DetailPalette.ink),
            child: !showStrip
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tabStrip(m, tabs, size),
                      if (tabs.isNotEmpty) Expanded(child: _panel(m, size)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Stage half ────────────────────────────────────────────────────────────

  Widget _stage(DetailModel m, DetailSize size) {
    final logoHeight = switch (size) {
      DetailSize.tv => 62.0,
      DetailSize.desktop => 70.0,
      DetailSize.tabletPortrait => 54.0,
      DetailSize.phone => 44.0,
    };
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DetailLogo(model: m, height: logoHeight),
        SizedBox(height: size.isTight ? 8 : 10),
        DetailMetaBar(model: m, fontSize: size.isTight ? 12 : 13),
        SizedBox(height: size.isTight ? 10 : 13),
        DetailActionRow(
          model: m,
          onUpEdge: () => m.focus.backNode.requestFocus(),
          onDownEdge: () => _firstTabNodeFor(m)?.requestFocus(),
        ),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: detailStageScrim())),
        Positioned(
          left: size.gutter,
          right: size.gutter,
          bottom: size.isTight ? 12 : 16,
          child: identity,
        ),
      ],
    );
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────

  Widget _tabStrip(DetailModel m, List<_Tab> tabs, DetailSize size) {
    final hasSources = m.isMovie && m.onBrowse != null;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DetailPalette.hair)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: size.gutter),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              _TabButton(
                label: _label(tabs[i]),
                active: tabs[i] == _active,
                focusNode: _tabNode(tabs[i]),
                trapLeft: i == 0,
                // Don't dead-stop RIGHT on the last content tab when Sources
                // sits after it, or Sources can never be reached.
                trapRight: i == tabs.length - 1 && !hasSources,
                onUp: () => m.focus.focusEntry(),
                onDown: _focusPanel,
                onTap: () {
                  final t = tabs[i];
                  if (_active == t) return;
                  // Re-focus the strip, never the subtree that just got
                  // replaced — otherwise switching tabs strands the cursor.
                  setState(() => _active = t);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _tabNode(t).requestFocus();
                  });
                },
              ),
            ],
            // A movie's Sources is an ACTION, not a panel — the screen only
            // exposes a callback, never a source list this deck could render.
            if (hasSources) ...[
              const SizedBox(width: 20),
              _TabButton(
                label: 'Sources',
                active: false,
                focusNode: _sourcesNode,
                trapLeft: tabs.isEmpty,
                trapRight: true,
                onUp: () => m.focus.focusEntry(),
                onDown: _focusPanel,
                onTap: m.onBrowse!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _focusPanel() {
    if (_active == _Tab.episodes) {
      if (_seasonNode.context != null) {
        _seasonNode.requestFocus();
        return;
      }
      if (_retryNode.context != null) {
        _retryNode.requestFocus();
        return;
      }
      final first = _cellNodes.firstMounted;
      first?.requestFocus();
      return;
    }
    // Non-episode panels have at most the Similar rail as a focus target.
    FocusScope.of(context).focusInDirection(TraversalDirection.down);
  }

  void _focusTabs() => _firstTabNodeFor(widget.model)?.requestFocus();

  // ── Panels ────────────────────────────────────────────────────────────────

  Widget _panel(DetailModel m, DetailSize size) {
    switch (_active) {
      case _Tab.episodes:
        final host = widget.episodesHost;
        if (host == null) return const SizedBox.shrink();
        return host((context, view) => _episodes(m, view, size));
      case _Tab.cast:
        return _castPanel(m, size);
      case _Tab.about:
        return _aboutPanel(m, size);
      case _Tab.similar:
        return _similarPanel(m, size);
      case _Tab.guide:
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(size.gutter, 14, size.gutter, 22),
          child: ParentsGuideSection(
            guide: m.parentsGuide!,
            tv: m.isTelevision,
            dense: true,
          ),
        );
    }
  }

  Widget _episodes(DetailModel m, EpisodesPanelView view, DetailSize size) {
    if (view.loading || view.unavailable) {
      return DetailEpisodesStatus(
        loading: view.loading,
        onRetry: view.onRetry,
        onSearchForSources: view.onSearchForSources,
        isTelevision: m.isTelevision,
        retryNode: _retryNode,
        onUpEdge: _focusTabs,
      );
    }
    _applyFocusIntent(view);
    final episodes = view.episodes;
    final many = view.seasons.length > 1;
    final idx = view.seasons.indexWhere(
      (s) => s.number == view.selectedSeasonNumber,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (many)
          Container(
            // The panel Column is start-aligned, so without an explicit width
            // this shrink-wraps the control and the rule stops mid-panel —
            // the same way the tab strip was centring.
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(size.gutter, 11, size.gutter, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: DetailPalette.hair)),
            ),
            child: DetailSeasonControl(
              seasonNumber: view.selectedSeasonNumber,
              episodeCount: episodes.length,
              canPrev: idx > 0,
              canNext: idx < view.seasons.length - 1,
              onPrev: () => view.stepSeason(-1),
              onNext: () => view.stepSeason(1),
              onPick: () => showDetailSeasonPicker(
                context: context,
                seasonNumbers: [for (final s in view.seasons) s.number],
                selected: view.selectedSeasonNumber,
                isTelevision: m.isTelevision,
                onSelected: view.selectSeason,
              ),
              focusNode: _seasonNode,
              onUpEdge: _focusTabs,
              onDownEdge: _focusFirstCell,
              hint: 'OK play · ▶ options',
            ),
          ),
        Expanded(
          child: ListView.separated(
            controller: _episodeScroll,
            padding: EdgeInsets.fromLTRB(size.gutter, 8, size.gutter, 20),
            itemCount: episodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final e = episodes[i];
              return DetailEdgeTrap(
                trapUp: i == 0,
                onUp: () => many ? _seasonNode.requestFocus() : _focusTabs(),
                child: DetailEpisodeRow(
                  episode: e,
                  fallbackImage: view.showImageUrl,
                  progress: view.progressOf(e),
                  isNext: view.isNext(e),
                  focusNode: _cellNodes.of(view.generation, e.season, e.number),
                  onPlay: () => view.play(e),
                  onOptions: () => view.options(e),
                  thumbWidth: size.isPhone ? 92 : 112,
                  showSynopsis: !size.isPhone,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _focusFirstCell() {
    final first = _cellNodes.firstMounted;
    first?.requestFocus();
  }

  Widget _castPanel(DetailModel m, DetailSize size) {
    final cast = m.cast;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(size.gutter, 14, size.gutter, 22),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: size.isPhone ? 220 : 240,
        mainAxisExtent: 58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 10,
      ),
      itemCount: cast.length,
      itemBuilder: (context, i) => _CastLine(member: cast[i]),
    );
  }

  Widget _aboutPanel(DetailModel m, DetailSize size) {
    final synopsis = m.synopsis;
    final rows = m.detailRows;
    final awards = m.awards;
    return ListView(
      padding: EdgeInsets.fromLTRB(size.gutter, 14, size.gutter, 22),
      children: [
        if (awards != null && awards.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: DetailPalette.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: DetailPalette.gold.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 15,
                  color: DetailPalette.gold,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    awards,
                    style: const TextStyle(
                      color: DetailPalette.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (synopsis != null && synopsis.isNotEmpty) ...[
          Text(
            synopsis,
            style: TextStyle(
              color: DetailPalette.tx2,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
        ],
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    r.$1,
                    style: TextStyle(color: DetailPalette.tx3, fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: TextStyle(color: DetailPalette.tx2, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _similarPanel(DetailModel m, DetailSize size) {
    final recs = m.recommendations;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(size.gutter, 14, size.gutter, 22),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: size.isPhone ? 108 : 128,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: recs.length,
      itemBuilder: (context, i) => _StagePoster(
        poster: recs[i].poster,
        onTap: () => m.onRecommendationTap!(recs[i]),
      ),
    );
  }

  void _applyFocusIntent(EpisodesPanelView view) {
    if (view.generation == _handledGeneration) return;
    _handledGeneration = view.generation;
    final intent = view.focusIntent;
    if (intent == EpisodeFocusIntent.none) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (intent == EpisodeFocusIntent.seasonControl) {
        if (_seasonNode.context != null) _seasonNode.requestFocus();
        return;
      }
      final landing = view.landing;
      if (landing == null) return;
      final index = view.episodes.indexWhere(
        (e) => e.season == landing.season && e.number == landing.number,
      );
      // Reveal without stealing focus — entry focus belongs to the primary
      // action; this only brings the resumed episode into view.
      revealDetailLanding(
        controller: _episodeScroll,
        index: index,
        itemCount: view.episodes.length,

        contextOf: () => _cellNodes
            .lookup(view.generation, landing.season, landing.number)
            ?.context,
        alignment: 0.35,
      );
    });
  }
}

class _TabButton extends StatefulWidget {
  final String label;
  final bool active;
  final FocusNode focusNode;
  final bool trapLeft;
  final bool trapRight;
  final VoidCallback onTap;
  final VoidCallback onUp;
  final VoidCallback onDown;

  const _TabButton({
    required this.label,
    required this.active,
    required this.focusNode,
    required this.trapLeft,
    required this.trapRight,
    required this.onTap,
    required this.onUp,
    required this.onDown,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return DetailEdgeTrap(
      trapLeft: widget.trapLeft,
      trapRight: widget.trapRight,
      trapUp: true,
      trapDown: true,
      onUp: widget.onUp,
      onDown: widget.onDown,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !context.mounted) return;
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                duration: Duration.zero,
              );
            });
          }
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && isActivate(event.logicalKey)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 9),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active
                      ? Colors.white
                      : (_focused ? DetailPalette.focus : Colors.transparent),
                  width: 2,
                ),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active
                    ? Colors.white
                    : (_focused ? DetailPalette.focus : DetailPalette.tx3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool isActivate(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.space;
}

class _CastLine extends StatelessWidget {
  final CastMember member;
  const _CastLine({required this.member});

  @override
  Widget build(BuildContext context) {
    final url = member.imageUrl;
    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 42,
            height: 42,
            child: (url != null && url.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 140,
                    placeholder: (_, __) =>
                        ColoredBox(color: DetailPalette.glass),
                    errorWidget: (_, __, ___) =>
                        ColoredBox(color: DetailPalette.glass),
                  )
                : ColoredBox(color: DetailPalette.glass),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (member.character?.isNotEmpty == true)
                Text(
                  member.character!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: DetailPalette.tx3, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StagePoster extends StatefulWidget {
  final String? poster;
  final VoidCallback onTap;
  const _StagePoster({required this.poster, required this.onTap});

  @override
  State<_StagePoster> createState() => _StagePosterState();
}

class _StagePosterState extends State<_StagePoster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.poster;
    return DetailFocusRing(
      focused: _focused,
      radius: BorderRadius.circular(9),
      child: Material(
        color: DetailPalette.glass,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: (p != null && p.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: p,
                  fit: BoxFit.cover,
                  cacheManager: DebrifyImageCache.manager,
                  memCacheWidth: 300,
                  placeholder: (_, __) =>
                      ColoredBox(color: DetailPalette.glass),
                  errorWidget: (_, __, ___) =>
                      ColoredBox(color: DetailPalette.glass),
                )
              : ColoredBox(color: DetailPalette.glass),
        ),
      ),
    );
  }
}
