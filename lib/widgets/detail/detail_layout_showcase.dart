import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/imdb_enrichment_service.dart';
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

  /// The INPUT axis: true on a television. False (phones, tablets, desktop)
  /// unlocks the touch drivers — the scroll-driven dissolve, the kebab on
  /// episode cells, and (under 600 wide) the compact presentation: centered
  /// identity, integrated episode card, season pill + popup. Width never
  /// implies input — a narrow TV keeps the wide presentation so the DPAD
  /// ladder's widgets all exist.
  final bool dpad;

  const DetailShowcase({
    super.key,
    required this.model,
    required this.episodesHost,
    this.dpad = true,
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
  final List<FocusNode> _guideNodes = [];
  final List<FocusNode> _sourceNodes = [];
  final List<FocusNode> _recNodes = [];
  final List<FocusNode> _uniNodes = [];
  final List<FocusNode> _dykNodes = [];
  final List<FocusNode> _retryNodes = [];

  final GlobalKey _identityKey = GlobalKey();
  final GlobalKey _seasonsKey = GlobalKey();
  final GlobalKey _episodesKey = GlobalKey();
  final GlobalKey _castKey = GlobalKey();
  final GlobalKey _guideKey = GlobalKey();
  final GlobalKey _sourcesKey = GlobalKey();
  final GlobalKey _recsKey = GlobalKey();
  final GlobalKey _uniKey = GlobalKey();
  final GlobalKey _dykKey = GlobalKey();

  /// The focused band by KEY, never by index. Cast arrives when IMDb
  /// enrichment lands and inserts itself above Sources — an index would then
  /// point at the wrong band and the next key would be read as Cast's.
  String _bandKey = 'identity';
  final Map<String, int> _col = {};
  int _handledGeneration = -1;

  /// True once focus has left the identity — drives the backdrop→ambient
  /// dissolve and the sticky logo together, so they can never disagree.
  bool get _deep => _bandKey != 'identity';

  /// The touch counterpart, driven by scroll offset with hysteresis (40% of
  /// the viewport in, 30% out — a gap so the boundary can't flicker under a
  /// finger resting exactly on it). SEPARATE state from [_bandKey]: on touch
  /// nothing ever focuses, so the band cursor must not be faked to fire the
  /// dissolve — it is the DPAD ladder's memory.
  bool _scrollDeep = false;

  /// The one depth every consumer reads — the three visual layers, the
  /// published [DetailModel.onDepth], and nothing else. DPAD pages answer
  /// with the band cursor; touch pages with the scroll.
  bool get _effectiveDeep => widget.dpad ? _deep : _scrollDeep;

  /// The viewport measured by [_page]'s LayoutBuilder — the hysteresis
  /// thresholds are fractions of it.
  double _viewportH = 0;

  /// The page's metrics, computed once per layout pass in [_pageBody] and
  /// read directly by [_peekFor]/[_episodes] (whose State context sits above
  /// the inherited scope the bands read).
  ShowcaseMetrics? _m;

  void _onScrollDepth() {
    if (widget.dpad || _viewportH <= 0 || !_scroll.hasClients) return;
    final off = _scroll.offset;
    final next = _scrollDeep
        ? off > _viewportH * 0.30 // stays deep until it drops below 30%
        : off > _viewportH * 0.40; // becomes deep past 40%
    if (next == _scrollDeep) return;
    setState(() => _scrollDeep = next);
    _publishDepth();
  }

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
    // The EFFECTIVE depth: the parent swaps its sharp/ambient backdrop and
    // stops trailers off this signal, and it must agree with the three layers
    // this page paints — whichever input is driving.
    final deep = _effectiveDeep;
    if (deep == _publishedDeep) return;
    _publishedDeep = deep;
    final cb = widget.model.onDepth;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(deep);
    });
  }

  @override
  void initState() {
    super.initState();
    if (!widget.dpad) _scroll.addListener(_onScrollDepth);
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in [
      ..._actionNodes,
      ..._seasonNodes,
      ..._castNodes,
      ..._guideNodes,
      ..._sourceNodes,
      ..._recNodes,
      ..._uniNodes,
      ..._dykNodes,
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
    final col = _entryCol(band);
    _setBand(band.key);
    _go(band.nodes[col], Offset(0, delta.toDouble()));
    _reveal(band);
  }

  /// The column to LAND on when entering `band` from above or below.
  ///
  /// The remembered column can name a card that is no longer in the tree. A
  /// band that scrolls out of the vertical list is disposed, and its rail keeps
  /// no scroll offset of its own, so it rebuilds at 0 with only the first
  /// screenful of cards built — while `_col` still remembers the sixth. Focus
  /// requested on a node that is not in the focus tree is a SILENT no-op: the
  /// node is merely armed for its next reparent. The band would then be
  /// scrolled into view by `_reveal` with the ring left behind in the band
  /// above, and every further press would repeat that, because the re-sync in
  /// `_onKey` reads the ring back out of the band above. Enter at the nearest
  /// card that IS mounted instead, so the press always moves the ring.
  int _entryCol(_Band band) {
    var col = (_col[band.key] ?? 0).clamp(0, band.nodes.length - 1);
    if (!detailNodeMounted(band.nodes[col])) {
      for (var d = 1; d < band.nodes.length; d++) {
        final lo = col - d;
        final hi = col + d;
        if (lo >= 0 && detailNodeMounted(band.nodes[lo])) {
          col = lo;
          break;
        }
        if (hi < band.nodes.length && detailNodeMounted(band.nodes[hi])) {
          col = hi;
          break;
        }
      }
      // Written back so the band is entered and then WALKED from where the
      // cursor really is. Left stale, LEFT would read as an edge press from a
      // middle card. If nothing in the band is built this is a no-op write and
      // the move degrades to the old behaviour.
      _col[band.key] = col;
    }
    return col;
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
      //
      // Through `focusEntry`, not a bare request on `primaryEntry`: this is a
      // LONG jump, and from a low band the identity is scrolled out of the
      // list and disposed, so the entry node is unmounted exactly as often as
      // a far card is. `focusEntry` falls back to the always-mounted back
      // button rather than no-op into the same dead end. The episode rail's
      // own LEFT edge already crosses this way.
      ParallaxTravel.note(const Offset(-1, 0));
      widget.model.focus.focusEntry();
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
    // The State's context sits ABOVE the metrics scope installed in [_page],
    // so read the field it set — the `.of` fallback would recompute from
    // MediaQuery and could disagree on tvOS. Null only before first layout.
    final m = _m ?? ShowcaseMetrics.of(context);
    // The TOP EDGE of an episode still and nothing more.
    //
    // This was `stillH * 0.34 + 46`, which showed most of a row — captions
    // included, sliced through by the screen edge, which reads as a broken
    // layout rather than as "the page continues". The reference leaves about
    // 45pt of artwork showing and no text at all.
    final episodePeek = m.stillH * 0.18;
    final hasSeasons = view != null && view.seasons.length > 1;
    return hasSeasons
        ? episodePeek + (m.compact ? _seasonPillBandHeight : _seasonsBandHeight)
        : episodePeek;
  }

  /// The seasons row's own height plus the space around it.
  ///
  /// Was 96, guessed. `ShowcaseSeasons` is a bare `SizedBox(height: 34)` — the
  /// guess over-reserved by around 60, and every one of those pixels went to
  /// showing more of the episode row than was ever intended.
  static const double _seasonsBandHeight = 50;

  /// Compact renders the season control as a 34pt pill with more air around
  /// it (a finger needs what a remote never did).
  static const double _seasonPillBandHeight = 56;

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
    // The compact Parents Guide is the ladder's one VERTICAL band — accordion
    // rows, not a rail — so its within-band axis is Up/Down, stepping to the
    // neighbouring band only at its edges. (Compact never has a DPAD, but
    // dpad:false pages still receive arrow keys from real keyboards.)
    final verticalBand = (_m?.compact ?? false) && band.key == 'guide';
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (verticalBand && _liveCol(band) < band.nodes.length - 1) {
          _walk(band, 1);
        } else {
          _step(bands, 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (verticalBand && _liveCol(band) > 0) {
          _walk(band, -1);
        } else {
          _step(bands, -1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (!verticalBand) _walk(band, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (!verticalBand) _walk(band, -1);
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

  // ── IMDb-enriched bands: shared predicates ─────────────────────────────
  //
  // Band presence and node counts are read in BOTH _bands and _pageBody;
  // deriving them once is what keeps topology and rendering incapable of
  // disagreeing.

  ImdbEnrichment? get _x => widget.model.imdbExtra;

  bool get _hasGuide {
    final g = widget.model.parentsGuide;
    return g != null && !g.isEmpty;
  }

  List<UniverseTitle> get _universe => _x?.universe ?? const [];

  /// The band mounts only when at least one READABLE entry survived the
  /// spoiler filter — a rail holding nothing but a "+N on IMDb" card would be
  /// a signpost to content the page can't show. Both _bands and _pageBody
  /// gate on this same list, so topology and rendering agree.
  List<DidYouKnowEntry> get _dyk => _x?.didYouKnow ?? const [];

  /// Cards mounted, plus the terminal "+N" card when IMDb holds more.
  int get _dykNodeCount =>
      _dyk.length + ((_x?.didYouKnowTotal ?? 0) > _dyk.length ? 1 : 0);

  String? get _dykCountLine {
    final x = _x;
    if (x == null) return null;
    final bits = <String>[
      if (x.triviaTotal > 0) '${x.triviaTotal} trivia',
      if (x.goofsTotal > 0)
        '${x.goofsTotal} goof${x.goofsTotal == 1 ? '' : 's'}',
      if (x.quotesTotal > 0)
        '${x.quotesTotal} quote${x.quotesTotal == 1 ? '' : 's'}',
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// A Universe card opens its title through the SAME door as a More Like
  /// This card — the recommendation callback, fed a meta synthesized from
  /// the connection (IMDb id, type, name, poster).
  void _openUniverse(UniverseTitle u) {
    final open = widget.model.onRecommendationTap;
    if (open == null) return;
    open(StremioMeta(
      id: u.imdbId,
      imdbId: u.imdbId,
      type: u.isSeries ? 'series' : 'movie',
      name: u.name,
      poster: u.posterUrl,
      year: u.year?.toString(),
    ));
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
      // Compact renders ONE control — the season pill — so its band carries
      // exactly one node. Listing a node per season here while the rendering
      // mounts a single pill would let a desktop arrow key focus a detached
      // node (dpad:false still receives arrow keys from real keyboards) and
      // strand the cursor. Topology always matches rendering.
      final compact = (_m?.compact ?? false);
      bands.add(_Band(
        'seasons',
        _grow(
          _seasonNodes,
          compact ? 1 : view.seasons.length,
          'showcase-season',
        ),
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
    if (_hasGuide) {
      bands.add(_Band(
        'guide',
        _grow(
          _guideNodes,
          m.parentsGuide!.categories.length,
          'showcase-guide',
        ),
        _guideKey,
        130,
      ));
    }
    bands.add(_Band(
      'sources',
      _grow(
        _sourceNodes,
        // Bound cards + "Find sources" + (movies) "Browse all". The count
        // mirrors ShowcaseSources' itemCount exactly — a node the rendering
        // doesn't mount is a place arrow keys can strand focus.
        m.boundSources.length + 1 + (m.isMovie && m.onBrowse != null ? 1 : 0),
        'showcase-source',
      ),
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
    if (_universe.isNotEmpty) {
      bands.add(_Band(
        'universe',
        _grow(_uniNodes, _universe.length, 'showcase-uni'),
        _uniKey,
        150,
      ));
    }
    if (_dyk.isNotEmpty) {
      bands.add(_Band(
        'dyk',
        _grow(_dykNodes, _dykNodeCount, 'showcase-dyk'),
        _dykKey,
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
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // Built PER KEY EVENT, not captured at build: the band list depends on
      // the metrics tier (compact's seasons band carries one node, wide's one
      // per season), and the tier is only known inside _page's LayoutBuilder.
      // A list captured here would describe the PREVIOUS frame's tier — on
      // the first compact frame that meant one node per season advertised
      // while the pill mounts only the first, and arrow keys could focus a
      // detached node.
      onKeyEvent: (_, e) => _onKey(_bands(view), e),
      child: _page(context, view),
    );
  }

  Widget _page(
    BuildContext context,
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
      builder: (context, constraints) {
        // The page's metrics, once per layout pass: the tier needs the REAL
        // width (tvOS insets the content for overscan, so MediaQuery lies),
        // and compact additionally requires touch — a narrow TV must keep the
        // wide presentation so every DPAD band's widgets exist.
        final metrics = ShowcaseMetrics(
          constraints.maxWidth,
          compact: !widget.dpad && constraints.maxWidth < 600,
        );
        _m = metrics;
        // Bands AFTER metrics — their topology follows the tier (see _shell).
        final bands = _bands(view);
        return ShowcaseMetricsScope(
          metrics: metrics,
          child: _pageBody(context, bands, view, m, constraints.maxHeight),
        );
      },
    );
  }

  Widget _pageBody(
    BuildContext context,
    List<_Band> bands,
    EpisodesPanelView? view,
    DetailModel m,
    double viewport,
  ) {
    _viewportH = viewport;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The ambient field. A separate layer from the backdrop rather than a
        // filter over it, so the crossfade is between two static images and
        // nothing is blurred per frame. All three read the EFFECTIVE depth —
        // band-driven on DPAD, scroll-driven on touch — and can never
        // disagree with what [_publishDepth] told the parent.
        ShowcaseAmbient(url: m.backdrop, visible: _effectiveDeep),
        ShowcaseBackdropScrim(
          visible: !_effectiveDeep,
          // Rolling trailer → bed pulled in tight, video clear. Off-TV only:
          // the TV scrims are the shipped, panel-tuned ones.
          thinned: !widget.dpad && m.trailerPlaying,
        ),
        ShowcaseStickyLogo(url: m.logo, name: m.name, visible: _effectiveDeep),
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
            if (_hasGuide)
              ShowcaseGuide(
                key: _guideKey,
                guide: m.parentsGuide!,
                nodes: _grow(
                  _guideNodes,
                  m.parentsGuide!.categories.length,
                  'showcase-guide',
                ),
                accent: m.accent,
              ),
            ShowcaseSources(
              key: _sourcesKey,
              sources: m.boundSources,
              nodes: _grow(
                _sourceNodes,
                m.boundSources.length +
                    1 +
                    (m.isMovie && m.onBrowse != null ? 1 : 0),
                'showcase-source',
              ),
              onOpen: m.onManageSources ?? m.onSelectSource,
              onBrowseAll: m.isMovie ? m.onBrowse : null,
            ),
            if (m.recommendations.isNotEmpty)
              ShowcaseRecs(
                key: _recsKey,
                items: m.recommendations,
                nodes: _grow(_recNodes, m.recommendations.length, 'showcase-rec'),
                onTap: m.onRecommendationTap,
              ),
            if (_universe.isNotEmpty)
              ShowcaseUniverse(
                key: _uniKey,
                items: _universe,
                nodes: _grow(_uniNodes, _universe.length, 'showcase-uni'),
                onOpen:
                    m.onRecommendationTap != null ? _openUniverse : null,
              ),
            if (_dyk.isNotEmpty)
              ShowcaseDidYouKnow(
                key: _dykKey,
                entries: _dyk,
                total: _x?.didYouKnowTotal ?? _dyk.length,
                countLine: _dykCountLine,
                nodes: _grow(_dykNodes, _dykNodeCount, 'showcase-dyk'),
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
    // The movie source browse — mounted between trailer and the app menu by
    // ShowcaseIdentity; the count here is what keeps its node real.
    if (m.isMovie && m.onBrowse != null) n++;
    if (m.onAppMenu != null) n++;
    return n;
  }

  Widget _episodes(EpisodesPanelView view) {
    final m = _m ?? ShowcaseMetrics.of(context);
    return Padding(
      key: _episodesKey,
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        // The still, plus the caption block below it, plus headroom for the
        // lift. Derived from the still's own measured height so it tracks the
        // viewport instead of assuming one. Compact swaps the caption block
        // for the integrated card's plate.
        height: m.compact ? m.stillH + m.epPlate : m.stillH + 108,
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
              builder: (context, focused) => m.compact
                  ? ShowcaseEpisodeCardCompact(
                      episode: ep,
                      focused: focused,
                      progress: view.progressOf(ep),
                      isNext: view.isNext(ep),
                      fallbackImage: view.showImageUrl,
                      onOptions: () => view.options(ep),
                    )
                  : ShowcaseEpisodeCell(
                      episode: ep,
                      focused: focused,
                      progress: view.progressOf(ep),
                      isNext: view.isNext(ep),
                      fallbackImage: view.showImageUrl,
                      // Touch/pointer without the compact card still needs a
                      // visible way into the options that hold-OK provides on
                      // TV — the kebab. TV passes null and renders untouched.
                      onOptions:
                          widget.dpad ? null : () => view.options(ep),
                    ),
            );
          },
        ),
      ),
    );
  }
}
