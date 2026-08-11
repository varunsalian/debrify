import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../episodes_panel.dart';
import '../parents_guide_section.dart';
import 'detail_episode_cells.dart';
import 'detail_identity.dart';
import 'detail_model.dart';
import 'detail_style.dart';
import 'theme/detail_theme.dart';

/// **Console** — resume-first. A large continue-watching card is the hero, the
/// rest of the season sits beneath it as a dense grid, and the reference
/// material lives in a right column.
///
/// The structural axis is **action before description**: the one thing you most
/// likely want is the biggest element on screen, and everything else is
/// arranged around it by likelihood rather than by category.
///
/// For a movie the hero becomes the movie's own resume card and the grid
/// becomes More Like This — the shape survives intact.
class DetailConsole extends StatefulWidget {
  final DetailModel model;
  final Widget Function(
    Widget Function(BuildContext, EpisodesPanelView) contentBuilder,
  )?
  episodesHost;

  const DetailConsole({
    super.key,
    required this.model,
    required this.episodesHost,
  });

  @override
  State<DetailConsole> createState() => _DetailConsoleState();
}

class _DetailConsoleState extends State<DetailConsole> {
  /// Resolved once per build; every helper below is called from build, so a
  /// field is simpler than threading it through a dozen signatures.
  late DetailTheme _t;

  final DetailCellNodes _cellNodes = DetailCellNodes('console');
  int _handledGeneration = -1;

  final FocusNode _seasonNode = FocusNode(debugLabel: 'console-season');
  final FocusNode _retryNode = FocusNode(debugLabel: 'console-retry');
  final ScrollController _gridScroll = ScrollController();
  final ScrollController _refScroll = ScrollController();
  final FocusNode _refNode = FocusNode(debugLabel: 'console-reference');

  /// Same reason as Marquee's: for a movie the grid is recommendations, which
  /// carried their own internal nodes, so DOWN from the hero found nothing.
  final List<FocusNode> _recNodes = [];

  @override
  void dispose() {
    _cellNodes.dispose();
    _seasonNode.dispose();
    _retryNode.dispose();
    _gridScroll.dispose();
    _refScroll.dispose();
    _refNode.dispose();
    for (final n in _recNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _t = DetailThemeScope.of(context);
    final m = widget.model;
    final size = resolveDetailSize(
      isTelevision: m.isTelevision,
      size: MediaQuery.of(context).size,
    );
    // The reference column only earns its width when the layout is side-by-side
    // AND it has something to show.
    final showRef = _refReachable(m, size);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topStrip(m, size),
        Expanded(
          child: showRef
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _main(m, size)),
                    SizedBox(width: 272, child: _reference(m, size)),
                  ],
                )
              // Stacked, the PAGE scrolls: the column and the grid must take
              // their natural height, or the grid silently swallows the back
              // half of the season with no way to reach it.
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _main(m, size, shrinkWrap: true),
                      if (_referenceHasContent(m))
                        _reference(m, size, flow: true),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// The rail is only enterable when it is actually beside the grid AND has
  /// something in it — otherwise RIGHT would consume the key and go nowhere.
  bool _refReachable(DetailModel m, DetailSize size) =>
      size.isWide && _referenceHasContent(m);

  /// The rail's own opaque ground, shared with its edge fade so the two can't
  /// disagree.
  /// The rail's own opaque ground, shared with its edge fade so the two can't
  /// disagree. Derived from the theme, or a light theme gets a black column.
  Color get _railGround => _t.railBg;

  bool _referenceHasContent(DetailModel m) =>
      (m.synopsis?.isNotEmpty ?? false) ||
      m.detailRows.isNotEmpty ||
      m.cast.isNotEmpty ||
      (m.awards?.isNotEmpty ?? false) ||
      (m.parentsGuide != null && !m.parentsGuide!.isEmpty);

  // ── Top strip ─────────────────────────────────────────────────────────────

  Widget _topStrip(DetailModel m, DetailSize size) {
    // A phone or portrait tablet can't hold identity, meta and five controls on
    // one line — it wraps into a vertical stack, which reads as a mistake. The
    // header keeps only what identifies the page and everything else moves
    // down, where it gets the full width.
    final compact = !size.isWide;
    return Container(
      padding: EdgeInsets.fromLTRB(
        size.gutter,
        m.isTelevision ? 14 : 12,
        size.gutter,
        12,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _t.hair)),
      ),
      child: Row(
        children: [
          // Clears the shell's floating back button.
          SizedBox(width: m.isTelevision ? 46 : 40),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t.displayCase(m.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t.titleStyle(
                    size: 15,
                    weight: FontWeight.w800,
                    tracking: -0.3,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  m.isMovie ? (m.year ?? 'Film') : 'Series',
                  style: TextStyle(
                    color: m.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 18),
            DetailMetaBar(model: m, fontSize: 12.5),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  // ── Main column ───────────────────────────────────────────────────────────

  Widget _main(DetailModel m, DetailSize size, {bool shrinkWrap = false}) {
    final compact = !size.isWide;
    final children = <Widget>[
      if (compact) ...[
        DetailMetaBar(model: m, fontSize: 12.5),
        const SizedBox(height: 11),
      ],
      _hero(m, size),
      const SizedBox(height: 14),
      // Both regions must be the FLEX child themselves — nesting an Expanded
      // inside a plain Column child hands it unbounded height and throws.
      if (m.isMovie)
        _recsRegion(m, size, shrinkWrap: shrinkWrap)
      else
        _episodesRegion(m, size, shrinkWrap: shrinkWrap),
    ];

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: children,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(size.gutter, 14, size.gutter, 16),
      child: column,
    );
  }

  Widget _hero(DetailModel m, DetailSize size) {
    final stacked = size.isPhone;
    final art = _heroArt(m);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'CONTINUE WATCHING',
          style: TextStyle(
            // CALLOUT: "CONTINUE WATCHING" is an attention flag, not a
            // measurement — a theme may colour it apart from progress.
            color: _t.callout,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _t.displayCase(m.name),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _t.titleStyle(
            size: size.isTight ? 18 : 20,
            weight: FontWeight.w700,
            tracking: -0.4,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        DetailActionRow(
          model: m,
          compactTrackers: !size.isPhone,
          onUpEdge: () => m.focus.backNode.requestFocus(),
          onDownEdge: _focusCollection,
          // RIGHT off the end of any line in the hero reaches the rail too, not
          // just from the grid.
          onRightEdge: _refReachable(m, size)
              ? () => _refNode.requestFocus()
              : null,
        ),
      ],
    );

    final box = Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        borderRadius: _t.imgRadius(13),
        border: Border.all(color: _t.hair),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            m.accent.withValues(alpha: 0.11),
            // 50% of a 7% panel — the 3.5% white the hero shipped with.
            _t.fade(_t.panel, 0.5),
          ],
        ),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (art is! SizedBox) ...[art, const SizedBox(height: 11)],
                info,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (art is! SizedBox) ...[
                  SizedBox(width: size.isTight ? 200 : 236, child: art),
                  const SizedBox(width: 16),
                ],
                Expanded(child: info),
              ],
            ),
    );
    return box;
  }

  Widget _heroArt(DetailModel m) {
    final url = m.backdrop;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: _t.imgRadius(9),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          cacheManager: DebrifyImageCache.manager,
          memCacheWidth: 640,
          placeholder: (_, __) => ColoredBox(color: _t.placeholder),
          errorWidget: (_, __, ___) => ColoredBox(color: _t.placeholder),
        ),
      ),
    );
  }

  void _focusCollection() {
    if (detailNodeMounted(_seasonNode)) {
      _seasonNode.requestFocus();
      return;
    }
    if (detailNodeMounted(_retryNode)) {
      _retryNode.requestFocus();
      return;
    }
    final cell = _cellNodes.firstMounted;
    if (cell != null) {
      cell.requestFocus();
      return;
    }
    final rec = _recNodes.where(detailNodeMounted).firstOrNull;
    rec?.requestFocus();
  }

  FocusNode _recNode(int i) {
    while (_recNodes.length <= i) {
      _recNodes.add(FocusNode(debugLabel: 'console-rec-${_recNodes.length}'));
    }
    return _recNodes[i];
  }

  /// The caption band, derived from the live text scale — the grid's aspect
  /// ratio is computed from the same number, so they cannot disagree.
  double _captionH(BuildContext context) =>
      16 * MediaQuery.textScalerOf(context).scale(1);

  static const _gridPad = EdgeInsets.only(top: 4, bottom: 8);

  int _columns(DetailSize size) => switch (size) {
    DetailSize.tv => 4,
    DetailSize.desktop => 4,
    DetailSize.tabletPortrait => 3,
    DetailSize.phone => 2,
  };

  Widget _episodesRegion(
    DetailModel m,
    DetailSize size, {
    required bool shrinkWrap,
  }) {
    final host = widget.episodesHost;
    if (host == null) return const SizedBox.shrink();
    final region = host(
      (context, view) => _grid(m, view, size, shrinkWrap: shrinkWrap),
    );
    return shrinkWrap ? region : Expanded(child: region);
  }

  Widget _grid(
    DetailModel m,
    EpisodesPanelView view,
    DetailSize size, {
    required bool shrinkWrap,
  }) {
    if (view.loading || view.unavailable) {
      return SizedBox(
        height: 200,
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
    final idx = view.seasons.indexWhere(
      (s) => s.number == view.selectedSeasonNumber,
    );
    final cols = _columns(size);

    // The ratio has to come from the cell's REAL width, or it disagrees with
    // the caption band the card reserves and every card overflows by the
    // difference. The old form assumed a 200px cell and dropped the 6px gap
    // entirely — which is precisely what the cards were overflowing by.
    final grid = LayoutBuilder(
      builder: (context, c) {
        final cellW =
            (c.maxWidth - 10 * (cols - 1) - _gridPad.horizontal) / cols;
        // Whichever is TALLER: the height Console shipped with, or the height
        // the content actually needs. Wide cells keep the shipped geometry
        // exactly; narrow ones — which is where the old fixed ratio clipped
        // captions — get just enough to fit.
        final cellH = math.max(
          cellW * (9 / 16 + 26 / 200),
          cellW * 9 / 16 + 6 + _captionH(context),
        );
        return GridView.builder(
          // Stacked, the PAGE scrolls, so the grid must not own a controller too.
          controller: shrinkWrap ? null : _gridScroll,
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: _gridPad,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: cellW / cellH,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, i) {
            final e = episodes[i];
            final lastRowStart = ((episodes.length - 1) ~/ cols) * cols;
            return DetailEdgeTrap(
              trapUp: i < cols,
              // DOWN on a short final row stays put rather than geometry-jumping
              // to whatever sits below-left of it.
              trapDown: i >= lastRowStart,
              // The reference rail is off to the right and scrolls independently,
              // so the grid's right edge is the only way in.
              trapRight:
                  _refReachable(m, size) &&
                  (i % cols == cols - 1 || i == episodes.length - 1),
              onUp: () =>
                  many ? _seasonNode.requestFocus() : m.focus.focusEntry(),
              onDown: () {},
              onRight: () => _refNode.requestFocus(),
              child: DetailEpisodeCard(
                episode: e,
                fallbackImage: view.showImageUrl,
                progress: view.progressOf(e),
                isNext: view.isNext(e),
                focusNode: _cellNodes.of(view.generation, e.season, e.number),
                onPlay: () => view.play(e),
                onOptions: () => view.options(e),
                width: double.infinity,
                captionHeight: _captionH(context),
                scrollAxis: Axis.vertical,
              ),
            );
          },
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (many)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
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
                theme: _t,
                onSelected: view.selectSeason,
              ),
              focusNode: _seasonNode,
              onUpEdge: () => m.focus.focusEntry(),
              onDownEdge: _focusFirstCell,
              hint: 'OK play · hold OK for options',
            ),
          ),
        // No painted fade here: the grid sits over the artwork, and a gradient
        // to opaque ink would band against a translucent surface. Only the
        // rail, which paints its own opaque ground, can carry one.
        if (shrinkWrap) grid else Expanded(child: grid),
      ],
    );
  }

  void _focusFirstCell() {
    final first = _cellNodes.firstMounted;
    first?.requestFocus();
  }

  Widget _recsRegion(
    DetailModel m,
    DetailSize size, {
    required bool shrinkWrap,
  }) {
    final recs = m.recommendations;
    // Missing movie metadata is not an error — omit the region entirely.
    if (recs.isEmpty || m.onRecommendationTap == null) {
      return const SizedBox.shrink();
    }
    final grid = GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns(size),
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 2 / 3,
      ),
      itemCount: recs.length,
      itemBuilder: (context, i) {
        final lastRowStart =
            ((recs.length - 1) ~/ _columns(size)) * _columns(size);
        return DetailEdgeTrap(
          trapUp: i < _columns(size),
          trapDown: i >= lastRowStart,
          onUp: () => m.focus.focusEntry(),
          onDown: () {},
          child: _ConsolePoster(
            poster: recs[i].poster,
            focusNode: _recNode(i),
            onTap: () => m.onRecommendationTap!(recs[i]),
          ),
        );
      },
    );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DetailSlab('More like this'),
        ),
        if (shrinkWrap) grid else Expanded(child: grid),
      ],
    );
    return shrinkWrap ? column : Expanded(child: column);
  }

  // ── Reference column ──────────────────────────────────────────────────────

  /// The reference rail.
  ///
  /// Deliberately **non-focusable throughout**: it is not in this layout's DPAD
  /// graph (the grid is), so anything focusable here would be unreachable on a
  /// remote. Parents Guide therefore uses its read-only mode here: Compass is
  /// still visually consistent with the other layouts, but it introduces no
  /// unreachable controls in this 272px rail.
  Widget _reference(DetailModel m, DetailSize size, {bool flow = false}) {
    final sections = <Widget>[
      ..._awardsSection(m),
      ..._summarySection(m, flow),
      ..._detailsSection(m),
      ..._castSection(m),
      ..._guideSection(m),
    ];
    if (sections.isEmpty) return const SizedBox.shrink();

    // Hairlines between sections, never after the last one.
    final woven = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) {
        woven.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Divider(height: 1, thickness: 1, color: _t.hair),
          ),
        );
      }
      woven.add(sections[i]);
    }

    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        flow ? size.gutter : 20,
        16,
        flow ? size.gutter : 20,
        22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: woven,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        // Opaque, not a black wash: the edge fade below gradients to this
        // exact colour, and over a translucent surface that reads as a band.
        color: _railGround,
        border: flow
            ? Border(top: BorderSide(color: _t.hair))
            : Border(left: BorderSide(color: _t.hair)),
      ),
      child: DetailWash(
        wash: _t.railWash,
        child: flow
            // Stacked, the whole page scrolls, so the pane is plain content.
            ? body
            : _ReferencePane(
                focusNode: _refNode,
                controller: _refScroll,
                onExitLeft: _focusLastGridCell,
                child: DetailScrollFade(
                  ground: _railGround,
                  // Keeps normal physics: the pane drives this controller from
                  // DPAD keys, but the rail also renders on desktop, where a
                  // wheel or trackpad has to work.
                  child: SingleChildScrollView(
                    controller: _refScroll,
                    child: body,
                  ),
                ),
              ),
      ),
    );
  }

  /// LEFT out of the rail returns to the grid — a mounted cell if there is one,
  /// else the page's primary action, so it can never be a one-way trip.
  void _focusLastGridCell() {
    final cell = _cellNodes.firstMounted;
    if (cell != null) {
      cell.requestFocus();
      return;
    }
    widget.model.focus.focusEntry();
  }

  List<Widget> _awardsSection(DetailModel m) {
    final awards = m.awards;
    if (awards == null || awards.isEmpty) return const [];
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          // AWARD: immutable metadata, not computed state.
          color: _t.award.withValues(alpha: 0.12),
          borderRadius: _t.brSm,
          border: Border.all(color: _t.award.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_rounded, size: 14, color: _t.award),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                awards,
                style: TextStyle(
                  color: _t.award,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _summarySection(DetailModel m, bool flow) {
    final synopsis = m.synopsis;
    if (synopsis == null || synopsis.isEmpty) return const [];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailSlab('Summary'),
          const SizedBox(height: 9),
          Text(
            synopsis,
            maxLines: flow ? null : 9,
            overflow: flow ? null : TextOverflow.ellipsis,
            style: TextStyle(color: _t.tx2, fontSize: 12.5, height: 1.55),
          ),
        ],
      ),
    ];
  }

  List<Widget> _detailsSection(DetailModel m) {
    final rows = m.detailRows;
    if (rows.isEmpty) return const [];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailSlab('Details'),
          const SizedBox(height: 9),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      r.$1,
                      style: TextStyle(color: _t.tx3, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: TextStyle(
                        color: _t.tx2,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  /// Cast as a VERTICAL list, not a horizontal strip of circles.
  ///
  /// At 272px a strip fits three and a half portraits and truncates every name
  /// to "Taylor Sc…" — a rail this narrow reads down, not across, and this way
  /// the character name fits too.
  List<Widget> _castSection(DetailModel m) {
    final cast = m.cast;
    if (cast.isEmpty) return const [];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailSlab('Cast'),
          const SizedBox(height: 10),
          for (final member in cast.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _CastPortrait(member: member),
            ),
        ],
      ),
    ];
  }

  List<Widget> _guideSection(DetailModel m) {
    final guide = m.parentsGuide;
    if (guide == null || guide.isEmpty) return const [];
    if (StorageService.parentsGuideStyleCached == 'compass') {
      return [
        ParentsGuideSection(
          guide: guide,
          tv: m.isTelevision,
          dense: true,
          interactive: false,
          accent: m.accent,
          theme: _t,
        ),
      ];
    }
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DetailSlab('Parents guide'),
          const SizedBox(height: 10),
          for (final cat in guide.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _t.tx2, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SeverityChip(severity: cat.severity),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  void _applyFocusIntent(EpisodesPanelView view) {
    if (view.generation == _handledGeneration) return;
    _handledGeneration = view.generation;
    final intent = view.focusIntent;
    if (intent == EpisodeFocusIntent.none) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (intent == EpisodeFocusIntent.seasonControl) {
        if (detailNodeMounted(_seasonNode)) _seasonNode.requestFocus();
        return;
      }
      final landing = view.landing;
      if (landing == null) return;
      final flat = view.episodes.indexWhere(
        (e) => e.season == landing.season && e.number == landing.number,
      );
      final size = resolveDetailSize(
        isTelevision: widget.model.isTelevision,
        size: MediaQuery.of(context).size,
      );
      // A grid scrolls by ROW, so the flat index has to be divided down or the
      // jump overshoots by a factor of the column count.
      final index = flat < 0 ? -1 : flat ~/ _columns(size);
      // Reveal without stealing focus — entry focus belongs to the primary
      // action; this only brings the resumed episode into view.
      revealDetailLanding(
        controller: _gridScroll,
        index: index,
        itemCount: ((view.episodes.length - 1) ~/ _columns(size)) + 1,

        contextOf: () => _cellNodes
            .lookup(view.generation, landing.season, landing.number)
            ?.context,
        alignment: 0.35,
      );
    });
  }
}

class _CastPortrait extends StatelessWidget {
  final CastMember member;
  const _CastPortrait({required this.member});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final url = member.imageUrl;
    return Row(
      children: [
        ClipRRect(
          borderRadius: t.brCast,
          child: SizedBox(
            width: 34,
            height: 34,
            child: (url != null && url.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 110,
                    placeholder: (_, __) => ColoredBox(color: t.placeholder),
                    errorWidget: (_, __, ___) =>
                        ColoredBox(color: t.placeholder),
                  )
                : ColoredBox(color: t.placeholder),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: t.tx,
                ),
              ),
              if (member.character?.isNotEmpty == true)
                Text(
                  member.character!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.tx3, fontSize: 10.5, height: 1.3),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only severity pill, matching the scale ParentsGuideSection uses.
class _SeverityChip extends StatelessWidget {
  final String severity;
  const _SeverityChip({required this.severity});

  /// A semantic scale, like the IMDb badge: green→red means the same thing in
  /// every theme, so it is deliberately not themed.
  static Color _color(String s) => switch (s.toLowerCase()) {
    'none' => const Color(0xFF4ADE80),
    'mild' => const Color(0xFFFBBF24),
    'moderate' => const Color(0xFFFB923C),
    'severe' => const Color(0xFFEF4444),
    // A mid grey rather than a white one: the fallback has to stay visible on
    // Broadsheet's paper as well as on ink.
    _ => const Color(0xFF8A8A8A),
  };

  @override
  Widget build(BuildContext context) {
    if (severity.isEmpty) return const SizedBox.shrink();
    final t = DetailThemeScope.of(context);
    final c = _color(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: t.brBtn,
        border: Border.all(color: c.withValues(alpha: 0.34)),
      ),
      child: Text(
        severity,
        style: TextStyle(
          color: c,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ConsolePoster extends StatefulWidget {
  final String? poster;
  final VoidCallback onTap;

  /// Layout-owned so DOWN from the hero can aim at it.
  final FocusNode? focusNode;

  const _ConsolePoster({
    required this.poster,
    required this.onTap,
    this.focusNode,
  });

  @override
  State<_ConsolePoster> createState() => _ConsolePosterState();
}

class _ConsolePosterState extends State<_ConsolePoster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final p = widget.poster;
    return DetailFocusRing(
      focused: _focused,
      radius: t.imgRadius(9),
      child: Material(
        color: t.panel,
        borderRadius: t.imgRadius(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: (p != null && p.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: p,
                  fit: BoxFit.cover,
                  cacheManager: DebrifyImageCache.manager,
                  memCacheWidth: 300,
                  placeholder: (_, __) => ColoredBox(color: t.placeholder),
                  errorWidget: (_, __, ___) => ColoredBox(color: t.placeholder),
                )
              : ColoredBox(color: t.placeholder),
        ),
      ),
    );
  }
}

/// The reference rail as ONE focusable scroll surface.
///
/// Everything inside is informational — a cast portrait has no action — so
/// making rows focusable purely to enable scrolling would fill the rail with
/// no-op DPAD targets. The pane itself takes focus instead: UP/DOWN scroll it,
/// LEFT returns to the grid.
///
/// Without this the rail was literally unreachable on a remote, and anything
/// below the fold — the parents guide — could never be seen at all.
class _ReferencePane extends StatefulWidget {
  final FocusNode focusNode;
  final ScrollController controller;
  final VoidCallback onExitLeft;
  final Widget child;

  const _ReferencePane({
    required this.focusNode,
    required this.controller,
    required this.onExitLeft,
    required this.child,
  });

  @override
  State<_ReferencePane> createState() => _ReferencePaneState();
}

class _ReferencePaneState extends State<_ReferencePane> {
  bool _focused = false;

  void _scrollBy(double delta) {
    final c = widget.controller;
    if (!c.hasClients) return;
    final target = (c.offset + delta).clamp(0.0, c.position.maxScrollExtent);
    if ((target - c.offset).abs() < 0.5) return;
    c.animateTo(
      target,
      // Effectively instant on TV: a held key retargets an in-flight glide on
      // every repeat, which reads as the pane trailing the press.
      duration: PlatformUtil.isAndroidTvCached
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.arrowLeft) {
          widget.onExitLeft();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown) {
          _scrollBy(120);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp) {
          // At the very top UP leaves, rather than dead-ending in a pane whose
          // only other exit is LEFT.
          if (!widget.controller.hasClients ||
              widget.controller.offset <= 0.5) {
            widget.onExitLeft();
          } else {
            _scrollBy(-120);
          }
          return KeyEventResult.handled;
        }
        // Far edge of the page.
        if (k == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: _focused ? t.focus : Colors.transparent,
              width: t.focusWidthFor(PlatformUtil.isAndroidTvCached),
            ),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
