import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../episodes_panel.dart';
import '../horizontal_mouse_wheel.dart';
import 'detail_episode_cells.dart';
import 'detail_identity.dart';
import 'detail_model.dart';
import 'detail_style.dart';
import 'theme/detail_theme.dart';

/// **Marquee** — full-bleed artwork with the identity anchored bottom-left and
/// the season laid out as a horizontal rail of wide episode cards.
///
/// The structural axis is that **episodes run horizontally**: DOWN from the
/// actions lands in the rail, LEFT/RIGHT walks the season. The show is the
/// stage; the episodes are the marquee.
///
/// For a movie the rail becomes More Like This — same edges, same geometry.
class DetailMarquee extends StatefulWidget {
  final DetailModel model;

  /// Builds the hosted [EpisodesPanel]. Null for movies (no episode list).
  final Widget Function(
    Widget Function(BuildContext, EpisodesPanelView) contentBuilder,
  )?
  episodesHost;

  const DetailMarquee({
    super.key,
    required this.model,
    required this.episodesHost,
  });

  @override
  State<DetailMarquee> createState() => _DetailMarqueeState();
}

class _DetailMarqueeState extends State<DetailMarquee> {
  /// Resolved once per build; every helper below is called from build, so a
  /// field is simpler than threading it through a dozen signatures.
  late DetailTheme _t;

  /// Layout-owned, generation-keyed. The engine disposes and rebuilds its own
  /// nodes on every season change, so borrowing them risks mounting a disposed
  /// node from an outgoing subtree.
  final DetailCellNodes _cellNodes = DetailCellNodes('marquee');

  final FocusNode _seasonNode = FocusNode(debugLabel: 'marquee-season');
  final FocusNode _retryNode = FocusNode(debugLabel: 'marquee-retry');
  final ScrollController _rail = ScrollController();

  /// Recommendation cards get layout-owned nodes so DOWN from the actions has
  /// something to aim at. A movie has no season control, no Retry and no
  /// episode cells — without these the entire collection was invisible to the
  /// focus graph and DOWN dead-stopped on the action row.
  final List<FocusNode> _recNodes = [];

  /// Which view generation we have already moved focus for, so a rebuild that
  /// isn't a data change never yanks the cursor a second time.
  int _handledGeneration = -1;

  @override
  void dispose() {
    _cellNodes.dispose();
    _seasonNode.dispose();
    _retryNode.dispose();
    _rail.dispose();
    for (final n in _recNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _focusBack() => widget.model.focus.backNode.requestFocus();

  @override
  Widget build(BuildContext context) {
    _t = DetailThemeScope.of(context);
    final m = widget.model;
    final size = resolveDetailSize(
      isTelevision: m.isTelevision,
      size: MediaQuery.of(context).size,
    );
    final gutter = size.gutter;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Legibility floor: artwork can be anything, and stops picked against a
        // dark backdrop wash out completely over a bright one.
        DecoratedBox(
          decoration: BoxDecoration(gradient: detailIdentityScrim(_t)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 0),
              child: _identity(m, size),
            ),
            SizedBox(height: size.isTight ? 10 : 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: DetailActionRow(
                model: m,
                onUpEdge: _focusBack,
                onDownEdge: _focusCollection,
              ),
            ),
            SizedBox(height: size.isTight ? 12 : 16),
            _collection(m, size, gutter),
            SizedBox(height: size.isPhone ? 14 : 18),
          ],
        ),
      ],
    );
  }

  void _focusCollection() {
    if (_seasonNode.context != null) {
      _seasonNode.requestFocus();
      return;
    }
    if (_retryNode.context != null) {
      _retryNode.requestFocus();
      return;
    }
    final cell = _cellNodes.firstMounted;
    if (cell != null) {
      cell.requestFocus();
      return;
    }
    final rec = _recNodes.where((n) => n.context != null).firstOrNull;
    // Still nothing (a movie with no recommendations) — DOWN dead-stops on the
    // action row rather than dropping the cursor into a region that isn't
    // there.
    rec?.requestFocus();
  }

  FocusNode _recNode(int i) {
    while (_recNodes.length <= i) {
      _recNodes.add(FocusNode(debugLabel: 'marquee-rec-${_recNodes.length}'));
    }
    return _recNodes[i];
  }

  Widget _identity(DetailModel m, DetailSize size) {
    final logoHeight = switch (size) {
      DetailSize.tv => 66.0,
      DetailSize.desktop => 74.0,
      DetailSize.tabletPortrait => 58.0,
      DetailSize.phone => 50.0,
    };
    final genres = m.genres;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Capped so the artwork keeps its right half — but the ACTION row is
        // not capped, because capping it there forces the tracker pills onto a
        // second line and eats the rail's captions.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.isWide
                ? MediaQuery.of(context).size.width * 0.58
                : double.infinity,
          ),
          child: DetailLogo(model: m, height: logoHeight),
        ),
        SizedBox(height: size.isTight ? 8 : 10),
        DetailMetaBar(model: m, fontSize: size.isTight ? 12 : 13),
        if (genres.isNotEmpty) ...[
          SizedBox(height: size.isTight ? 8 : 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final g in genres.take(3)) DetailPill(g)],
          ),
        ],
      ],
    );
  }

  double _cardWidth(DetailSize size) => switch (size) {
    DetailSize.tv => 172,
    DetailSize.desktop => 196,
    DetailSize.tabletPortrait => 168,
    DetailSize.phone => 148,
  };

  Widget _collection(DetailModel m, DetailSize size, double gutter) {
    if (m.isMovie) return _recsRail(m, size, gutter);
    final host = widget.episodesHost;
    if (host == null) return const SizedBox.shrink();
    return host((context, view) => _episodeRail(m, view, size, gutter));
  }

  // ── Series ────────────────────────────────────────────────────────────────

  Widget _episodeRail(
    DetailModel m,
    EpisodesPanelView view,
    DetailSize size,
    double gutter,
  ) {
    final cardW = _cardWidth(size);
    // One box height, derived — never a magic number: the caption band scales
    // with text size, so a large accessibility scale must not clip it.
    final captionH = 22 * MediaQuery.textScalerOf(context).scale(1);
    final railH = cardW * 9 / 16 + 6 + captionH;

    if (view.loading || view.unavailable) {
      return SizedBox(
        height: railH + 34,
        child: DetailEpisodesStatus(
          loading: view.loading,
          onRetry: view.onRetry,
          onSearchForSources: view.onSearchForSources,
          isTelevision: m.isTelevision,
          retryNode: _retryNode,
          onUpEdge: () => m.focus.focusEntry(),
        ),
      );
    }

    _applyFocusIntent(view);
    final episodes = view.episodes;
    final many = view.seasons.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (many)
          Padding(
            padding: EdgeInsets.only(left: gutter, right: gutter, bottom: 9),
            child: DetailSeasonControl(
              seasonNumber: view.selectedSeasonNumber,
              episodeCount: episodes.length,
              canPrev: _seasonIndex(view) > 0,
              canNext: _seasonIndex(view) < view.seasons.length - 1,
              onPrev: () => view.stepSeason(-1),
              onNext: () => view.stepSeason(1),
              onPick: () => showDetailSeasonPicker(
                context: context,
                seasonNumbers: [for (final s in view.seasons) s.number],
                selected: view.selectedSeasonNumber,
                isTelevision: m.isTelevision,
                theme: _t,
                onSelected: view.selectSeason,
              ),
              focusNode: _seasonNode,
              onUpEdge: () => m.focus.focusEntry(),
              onDownEdge: _focusFirstCell,
              hint: 'OK play · hold OK for options',
            ),
          ),
        SizedBox(
          height: railH,
          child: HorizontalMouseWheel(
            controller: _rail,
            child: ListView.separated(
              controller: _rail,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: gutter),
              itemCount: episodes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (context, i) {
                final e = episodes[i];
                return DetailEdgeTrap(
                  // Dead-stop at both ends: without this the cursor escapes to
                  // whatever is geometrically nearest, which is the action row.
                  trapLeft: i == 0,
                  trapRight: i == episodes.length - 1,
                  trapUp: true,
                  onUp: () =>
                      many ? _seasonNode.requestFocus() : m.focus.focusEntry(),
                  child: DetailEpisodeCard(
                    episode: e,
                    fallbackImage: view.showImageUrl,
                    progress: view.progressOf(e),
                    isNext: view.isNext(e),
                    focusNode: _cellNodes.of(
                      view.generation,
                      e.season,
                      e.number,
                    ),
                    onPlay: () => view.play(e),
                    onOptions: () => view.options(e),
                    width: cardW,
                    captionHeight: captionH,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  int _seasonIndex(EpisodesPanelView view) =>
      view.seasons.indexWhere((s) => s.number == view.selectedSeasonNumber);

  void _focusFirstCell() {
    final first = _cellNodes.firstMounted;
    first?.requestFocus();
  }

  /// Reveal + focus what the engine resolved, once per view generation.
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
        controller: _rail,
        index: index,
        itemCount: view.episodes.length,

        contextOf: () => _cellNodes
            .lookup(view.generation, landing.season, landing.number)
            ?.context,
        alignment: 0.25,
      );
    });
  }

  // ── Movie ─────────────────────────────────────────────────────────────────

  Widget _recsRail(DetailModel m, DetailSize size, double gutter) {
    final recs = m.recommendations;
    // Missing movie metadata is not an error — the region is omitted entirely
    // rather than rendered blank or, worse, as an episode failure.
    if (recs.isEmpty || m.onRecommendationTap == null) {
      return const SizedBox.shrink();
    }
    final cardW = _cardWidth(size) * 0.56;
    final captionH = 20 * MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: gutter, bottom: 9),
          child: DetailSlab('More like this'),
        ),
        SizedBox(
          height: cardW * 3 / 2 + 6 + captionH,
          child: HorizontalMouseWheel(
            controller: _rail,
            child: ListView.separated(
              controller: _rail,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: gutter),
              itemCount: recs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => DetailEdgeTrap(
                trapLeft: i == 0,
                trapRight: i == recs.length - 1,
                trapUp: true,
                onUp: () => m.focus.focusEntry(),
                child: _RecCard(
                  rec: recs[i],
                  width: cardW,
                  focusNode: _recNode(i),
                  onTap: () => m.onRecommendationTap!(recs[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecCard extends StatefulWidget {
  final StremioMeta rec;
  final double width;
  final VoidCallback onTap;

  /// Owned by the layout, so DOWN from the action row can aim at it.
  final FocusNode? focusNode;

  const _RecCard({
    required this.rec,
    required this.width,
    required this.onTap,
    this.focusNode,
  });

  @override
  State<_RecCard> createState() => _RecCardState();
}

class _RecCardState extends State<_RecCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final poster = widget.rec.poster;
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailFocusRing(
            focused: _focused,
            radius: t.imgRadius(8),
            child: Material(
              color: t.panel,
              borderRadius: t.imgRadius(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                focusNode: widget.focusNode,
                onTap: widget.onTap,
                onFocusChange: (f) => setState(() => _focused = f),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: (poster != null && poster.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          memCacheWidth: 300,
                          placeholder: (_, __) =>
                              ColoredBox(color: t.placeholder),
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: t.placeholder),
                        )
                      : ColoredBox(color: t.placeholder),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.rec.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _focused ? t.tx : t.tx2,
            ),
          ),
        ],
      ),
    );
  }
}
