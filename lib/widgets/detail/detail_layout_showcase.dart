import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/widgets/parallax_focus.dart';
import '../episodes_panel.dart';
import 'detail_episode_cells.dart';
import 'detail_model.dart';
import 'detail_style.dart';
import 'showcase_parts.dart';

/// **Showcase** — the tvOS idiom.
///
/// The backdrop holds the identity, then dissolves into an ambient colour
/// field lifted off the same artwork as you descend, while the logo re-forms
/// as a centred header.
///
/// ## The band model
///
/// Everything below the identity is a horizontal band, and the bands are built
/// into a LIST at build time and stepped by position. They are deliberately
/// unnumbered: Seasons is absent on a single-season show, Cast is absent when
/// IMDb enrichment failed, and Episodes is absent on a movie. A table of fixed
/// indices would leave holes, and a hole in a DPAD map is a row the remote
/// silently skips — the same defect the settings pane numbering had.
///
/// ## What LEFT does
///
/// Not open the sidebar. This page is a pushed route, so the shell's
/// directional action is not a dependable ancestor and there is no sidebar
/// behind it to open anyway. LEFT at column 0 goes to the primary button,
/// deterministically.
class DetailShowcase extends StatefulWidget {
  final DetailModel model;
  final Widget Function(
    Widget Function(BuildContext, EpisodesPanelView) contentBuilder,
  )?
  episodesHost;

  const DetailShowcase({
    super.key,
    required this.model,
    required this.episodesHost,
  });

  @override
  State<DetailShowcase> createState() => _DetailShowcaseState();
}

/// One horizontal band: its focus nodes, and where it rests when selected.
class _Band {
  final String key;
  final List<FocusNode> nodes;
  final GlobalKey anchor;

  /// Distance from the top of the viewport this band sits at when it owns the
  /// cursor. Larger for bands whose content is tall, so the row above stays
  /// partly visible — which is what tells you the page continues upward.
  final double rest;

  _Band(this.key, this.nodes, this.anchor, this.rest);
}

class _DetailShowcaseState extends State<DetailShowcase> {
  final ScrollController _scroll = ScrollController();
  final DetailCellNodes _cells = DetailCellNodes('showcase');

  final List<FocusNode> _actionNodes = [];
  final List<FocusNode> _seasonNodes = [];
  final List<FocusNode> _castNodes = [];
  final List<FocusNode> _sourceNodes = [];
  final List<FocusNode> _recNodes = [];
  final List<FocusNode> _retryNodes = [];

  final GlobalKey _identityKey = GlobalKey();
  final GlobalKey _seasonsKey = GlobalKey();
  final GlobalKey _episodesKey = GlobalKey();
  final GlobalKey _castKey = GlobalKey();
  final GlobalKey _sourcesKey = GlobalKey();
  final GlobalKey _recsKey = GlobalKey();

  /// The focused band by KEY, never by index. Cast arrives when IMDb
  /// enrichment lands and inserts itself above Sources — an index would then
  /// point at the wrong band and the next key would be read as Cast's.
  String _bandKey = 'identity';
  final Map<String, int> _col = {};
  int _handledGeneration = -1;

  /// True once focus has left the identity — drives the backdrop→ambient
  /// dissolve and the sticky logo together, so they can never disagree.
  bool get _deep => _bandKey != 'identity';

  /// The last depth published to the shell, so only genuine transitions are
  /// sent and a rebuild cannot re-announce the same one.
  bool _publishedDeep = false;

  /// The single writer for [_bandKey].
  ///
  /// Every band change used to `setState` in place, from six call sites. The
  /// shell now needs telling when the page crosses into or out of the hero, and
  /// its handler calls `setState` — so an emit from a build or a focus callback
  /// running during layout would be setState-during-build. Funnelling the
  /// writes through here means the notification happens once, post-frame, and
  /// only when the depth actually changed.
  void _setBand(String key) {
    if (_bandKey == key) return;
    setState(() => _bandKey = key);
    _publishDepth();
  }

  void _publishDepth() {
    final deep = _deep;
    if (deep == _publishedDeep) return;
    _publishedDeep = deep;
    final cb = widget.model.onDepth;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(deep);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in [
      ..._actionNodes,
      ..._seasonNodes,
      ..._castNodes,
      ..._sourceNodes,
      ..._recNodes,
      ..._retryNodes,
    ]) {
      n.dispose();
    }
    _cells.dispose();
    super.dispose();
  }

  List<FocusNode> _grow(List<FocusNode> pool, int n, String label) {
    while (pool.length < n) {
      pool.add(FocusNode(debugLabel: '$label-${pool.length}'));
    }
    return pool.take(n).toList();
  }

  // ── movement ───────────────────────────────────────────────────────────

  /// Every directional move goes through here, and every one records the
  /// travel direction BEFORE moving focus — that is what lets the arriving
  /// card lean the right way. A `requestFocus` that skips this produces a
  /// lift with no lean, which is correct for a tap but wrong for a key.
  void _go(FocusNode node, Offset dir) {
    ParallaxTravel.note(dir);
    node.requestFocus();
  }

  int _indexOf(List<_Band> bands) {
    final i = bands.indexWhere((b) => b.key == _bandKey);
    return i < 0 ? 0 : i;
  }

  void _step(List<_Band> bands, int delta) {
    final next = _indexOf(bands) + delta;
    if (next < 0) {
      _go(widget.model.focus.backNode, const Offset(0, -1));
      return;
    }
    if (next >= bands.length) return;
    final band = bands[next];
    if (band.nodes.isEmpty) return;
    final col = (_col[band.key] ?? 0).clamp(0, band.nodes.length - 1);
    _setBand(band.key);
    _go(band.nodes[col], Offset(0, delta.toDouble()));
    _reveal(band);
  }

  /// Where the cursor ACTUALLY is in this band.
  ///
  /// `_col` is bookkeeping and drifts whenever focus moves without going
  /// through `_walk` — a scroll-into-view, a rebuild, a landing reveal. A
  /// stale column makes LEFT act as though it were at the edge when it is not.
  int _liveCol(_Band band) {
    final i = band.nodes.indexWhere((n) => n.hasFocus);
    if (i >= 0) return i;
    return (_col[band.key] ?? 0).clamp(0, band.nodes.length - 1);
  }

  void _walk(_Band band, int delta) {
    if (band.nodes.isEmpty) return;
    final at = _liveCol(band);
    final next = at + delta;
    if (next < 0) {
      // Column 0 and LEFT again: back to the primary action. Never geometric
      // traversal, which happily lands on a cast tile sitting below-left.
      _go(widget.model.focus.primaryEntry, const Offset(-1, 0));
      _setBand('identity');
      return;
    }
    if (next >= band.nodes.length) return;
    setState(() => _col[band.key] = next);
    _go(band.nodes[next], Offset(delta.toDouble(), 0));
  }

  /// How much of the next band the hero leaves showing.
  ///
  /// Computed from what actually comes next rather than fixed: a multi-season
  /// show puts Seasons between the identity and Episodes, so a constant peek
  /// would show a sliver of season chips and none of the episode art the
  /// reference deliberately leaves visible. When Seasons is present the hero
  /// gives up its whole row plus a slice of the episodes behind it.
  /// The hero's height: the viewport less the peek.
  ///
  /// The viewport is measured by a `LayoutBuilder` wrapping the page, so it is
  /// right on the FIRST frame. `MediaQuery` is the whole screen including the
  /// overscan inset this list sits inside, and the scroll position has no
  /// clients until after layout — either would size the opening frame wrong on
  /// exactly the device this is for.
  double _heroHeight(EpisodesPanelView? view, double viewport) =>
      (viewport - _peekFor(view)).clamp(240.0, double.infinity);

  double _peekFor(EpisodesPanelView? view) {
    final m = ShowcaseMetrics.of(context);
    // The TOP EDGE of an episode still and nothing more.
    //
    // This was `stillH * 0.34 + 46`, which showed most of a row — captions
    // included, sliced through by the screen edge, which reads as a broken
    // layout rather than as "the page continues". The reference leaves about
    // 45pt of artwork showing and no text at all.
    final episodePeek = m.stillH * 0.18;
    final hasSeasons = view != null && view.seasons.length > 1;
    return hasSeasons ? episodePeek + _seasonsBandHeight : episodePeek;
  }

  /// The seasons row's own height plus the space around it.
  ///
  /// Was 96, guessed. `ShowcaseSeasons` is a bare `SizedBox(height: 34)` — the
  /// guess over-reserved by around 60, and every one of those pixels went to
  /// showing more of the episode row than was ever intended.
  static const double _seasonsBandHeight = 50;

  void _reveal(_Band band) {
    final ctx = band.anchor.currentContext;
    if (ctx == null) return;
    // The VIEWPORT, not the screen. `MediaQuery` height includes the overscan
    // safe area this list is already inset by, so every band parked slightly
    // low — invisible while the identity was a short block, obvious once it is
    // a full screenful.
    final h = _scroll.hasClients
        ? _scroll.position.viewportDimension
        : MediaQuery.sizeOf(context).height;
    // `rest` is where this band SITS when it owns the cursor, expressed as a
    // fraction of the viewport. Aligning everything to 0 parked each band
    // hard against the top edge under the sticky logo, with no sight of the
    // row above — which is the thing that tells you the page continues.
    Scrollable.ensureVisible(
      ctx,
      alignment: h <= 0 ? 0 : (band.rest / h).clamp(0.0, 0.6),
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKey(List<_Band> bands, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Re-sync the band from live focus before acting: an asynchronously
    // arriving band (Cast) or a landing reveal can move focus without the key
    // handler ever seeing it.
    for (final b in bands) {
      if (b.nodes.any((n) => n.hasFocus)) {
        // Assigned directly, not through `_setBand`: this runs inside the key
        // handler's re-sync and must not rebuild mid-event. The depth publish
        // below covers it.
        _bandKey = b.key;
        break;
      }
    }
    _publishDepth();
    final band = bands[_indexOf(bands)];
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _step(bands, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _step(bands, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _walk(band, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _walk(band, -1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final host = widget.episodesHost;
    if (host == null || widget.model.isMovie) return _shell(context, null);
    return host((context, view) => _shell(context, view));
  }

  /// The bands as they exist for THIS build. Order here is the DPAD order.
  List<_Band> _bands(EpisodesPanelView? view) {
    final m = widget.model;
    final bands = <_Band>[
      _Band('identity', [
        if (m.showPrimary) m.focus.primaryEntry,
        ..._grow(_actionNodes, _actionCount(m), 'showcase-act'),
      ], _identityKey, 0),
    ];
    if (view != null && view.seasons.length > 1) {
      bands.add(_Band(
        'seasons',
        _grow(_seasonNodes, view.seasons.length, 'showcase-season'),
        _seasonsKey,
        110,
      ));
    }
    if (view != null && view.episodes.isEmpty && view.unavailable) {
      // A band with one control in it. Without this entry the Retry chip is
      // rendered, focusable, and unreachable — the parent's key handler only
      // ever walks the bands in this list.
      bands.add(_Band(
        'retry',
        _grow(_retryNodes, 1, 'showcase-retry'),
        _episodesKey,
        125,
      ));
    }
    if (view != null && view.episodes.isNotEmpty) {
      bands.add(_Band(
        'episodes',
        [
          for (final ep in view.episodes)
            _cells.of(view.generation, ep.season, ep.number),
        ],
        _episodesKey,
        125,
      ));
    }
    if (m.cast.isNotEmpty) {
      bands.add(_Band(
        'cast',
        _grow(_castNodes, m.cast.length, 'showcase-cast'),
        _castKey,
        150,
      ));
    }
    bands.add(_Band(
      'sources',
      _grow(_sourceNodes, m.boundSources.length + 1, 'showcase-source'),
      _sourcesKey,
      165,
    ));
    if (m.recommendations.isNotEmpty) {
      bands.add(_Band(
        'recs',
        _grow(_recNodes, m.recommendations.length, 'showcase-rec'),
        _recsKey,
        150,
      ));
    }
    return bands;
  }

  /// The view is threaded through as an ARGUMENT rather than stashed on the
  /// state during build. Caching it meant `_bands` ran against the *previous*
  /// frame's episodes — so on the first frame the ladder had no episode band
  /// at all, and every season swap moved the DPAD map one frame late.
  Widget _shell(BuildContext context, EpisodesPanelView? view) {
    final bands = _bands(view);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _onKey(bands, e),
      child: _page(context, bands, view),
    );
  }

  Widget _page(
    BuildContext context,
    List<_Band> bands,
    EpisodesPanelView? view,
  ) {
    final m = widget.model;

    if (view != null && view.generation != _handledGeneration) {
      _handledGeneration = view.generation;
      // Landing SCROLLS, it does not steal focus — `revealDetailLanding`'s
      // documented contract, and the reason focus stays on the primary button
      // when the page opens.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final landing = view.landing;
        if (landing == null) return;
        final node = _cells.lookup(
          view.generation,
          landing.season,
          landing.number,
        );
        final ctx = node?.context;
        if (ctx == null) return;
        // The RAIL only. This used to be a global `Scrollable.ensureVisible`,
        // which walks every ancestor scrollable — so opening a series with a
        // resume point scrolled the page's vertical list too, and with a
        // full-height hero that means the page opens already scrolled past its
        // own key art, while `_bandKey` still says `identity`.
        final rail = Scrollable.maybeOf(ctx);
        final box = ctx.findRenderObject();
        if (rail == null || box is! RenderBox || !box.attached) return;
        rail.position.ensureVisible(box, alignment: 0.5);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) =>
          _pageBody(context, bands, view, m, constraints.maxHeight),
    );
  }

  Widget _pageBody(
    BuildContext context,
    List<_Band> bands,
    EpisodesPanelView? view,
    DetailModel m,
    double viewport,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The ambient field. A separate layer from the backdrop rather than a
        // filter over it, so the crossfade is between two static images and
        // nothing is blurred per frame.
        ShowcaseAmbient(url: m.backdrop, visible: _deep),
        ShowcaseBackdropScrim(visible: !_deep),
        ShowcaseStickyLogo(url: m.logo, name: m.name, visible: _deep),
        ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          // Build well past the fold.
          //
          // The identity is a full screenful now, so everything below it starts
          // off-screen — and an unbuilt band has no anchor context, which is
          // what `_reveal` needs to park it and what focus needs to land on.
          // The peek guarantees the NEXT band is mounted; this widens the
          // window so the one after it is ready before the cursor arrives,
          // rather than being built during the glide.
          cacheExtent: 1200,
          children: [
            ShowcaseIdentity(
              key: _identityKey,
              model: m,
              primaryNode: m.focus.primaryEntry,
              actionNodes: _grow(_actionNodes, _actionCount(m), 'showcase-act'),
              onFocused: () => _setBand('identity'),
              height: _heroHeight(view, viewport),
            ),
            if (view != null && view.seasons.length > 1)
              ShowcaseSeasons(
                key: _seasonsKey,
                view: view,
                nodes: _grow(
                  _seasonNodes,
                  view.seasons.length,
                  'showcase-season',
                ),
              ),
            if (view != null && view.episodes.isNotEmpty)
              _episodes(view)
            else if (view != null && view.loading)
              const ShowcaseBandNote(text: 'Loading episodes…')
            else if (view != null && view.unavailable)
              ShowcaseBandNote(
                text: 'Episodes unavailable',
                actionLabel: 'Retry',
                onAction: view.onRetry,
                actionNode: _grow(_retryNodes, 1, 'showcase-retry').first,
              ),
            if (m.cast.isNotEmpty)
              ShowcaseCast(
                key: _castKey,
                cast: m.cast,
                nodes: _grow(_castNodes, m.cast.length, 'showcase-cast'),
              ),
            ShowcaseSources(
              key: _sourcesKey,
              sources: m.boundSources,
              nodes: _grow(
                _sourceNodes,
                m.boundSources.length + 1,
                'showcase-source',
              ),
              onOpen: m.onManageSources ?? m.onSelectSource,
            ),
            if (m.recommendations.isNotEmpty)
              ShowcaseRecs(
                key: _recsKey,
                items: m.recommendations,
                nodes: _grow(_recNodes, m.recommendations.length, 'showcase-rec'),
                onTap: m.onRecommendationTap,
              ),
            // Reference material, last and unfocusable — it is not a band in
            // the DPAD ladder, it is the page's footer.
            ShowcaseDetails(rows: m.detailRows, awards: m.awards),
            const SizedBox(height: 40),
          ],
        ),
      ],
    );
  }

  int _actionCount(DetailModel m) {
    var n = 0;
    if (m.onTrackers != null) n++;
    if (m.onTrackersSecondary != null) n++;
    if (m.hasTrailer) n++;
    if (m.onAppMenu != null) n++;
    return n;
  }

  Widget _episodes(EpisodesPanelView view) {
    final m = ShowcaseMetrics.of(context);
    return Padding(
      key: _episodesKey,
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        // The still, plus the caption block below it, plus headroom for the
        // lift. Derived from the still's own measured height so it tracks the
        // viewport instead of assuming one.
        height: m.stillH + 108,
        child: ListView.separated(
          // The lift, its 7px rise and its 25px shadow all paint outside the
          // cell; a clipping viewport slices exactly the effect off.
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: m.gutter),
          itemCount: view.episodes.length,
          separatorBuilder: (_, __) => SizedBox(width: m.epGap),
          itemBuilder: (context, i) {
            final ep = view.episodes[i];
            final node = _cells.of(view.generation, ep.season, ep.number);
            return DetailEpisodeInteraction(
              focusNode: node,
              gesture: DetailOptionsGesture.holdOk,
              onPlay: () => view.play(ep),
              onOptions: () => view.options(ep),
              // ONLY on the first cell. `DetailEpisodeInteraction` consumes
              // LEFT whenever this is non-null, so setting it on every cell
              // would jump to the identity from the middle of the row.
              onLeftEdge: i == 0
                  ? () {
                      ParallaxTravel.note(const Offset(-1, 0));
                      widget.model.focus.focusEntry();
                      _setBand('identity');
                    }
                  : null,
              ensureVisible: true,
              ensureVisibleAxis: Axis.horizontal,
              builder: (context, focused) => ShowcaseEpisodeCell(
                episode: ep,
                focused: focused,
                progress: view.progressOf(ep),
                isNext: view.isNext(ep),
                fallbackImage: view.showImageUrl,
              ),
            );
          },
        ),
      ),
    );
  }
}
