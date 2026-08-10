import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../../utils/dominant_color.dart';

/// What a card is, once a shelf stops being a list of TITLES.
///
/// Continue Watching and the catalog are `StremioMeta`; the favourites rails
/// are not. A playlist is a container, not a title — it has no poster of its
/// own, which is why poster OVERRIDES exist — and an IPTV channel's logo is a
/// wide, often transparent mark that a 2:3 crop destroys. Forcing all four
/// through a poster model is how they end up looking wrong in four different
/// ways.
class SpotlightCard {
  /// Poster, channel logo, or a user override. Null draws the placeholder.
  final String? image;
  final String title;

  /// Item count, "LIVE", a genre — whatever this KIND of thing is identified
  /// by beyond its name.
  final String? subtitle;

  /// 0..100, or null.
  final double? progress;

  final VoidCallback onOpen;
  final VoidCallback? onOptions;
  final SpotlightCardShape shape;

  const SpotlightCard({
    required this.title,
    required this.onOpen,
    this.image,
    this.subtitle,
    this.progress,
    this.onOptions,
    this.shape = SpotlightCardShape.poster,
  });
}

/// Aspect and fit, per kind.
enum SpotlightCardShape {
  /// 2:3, art cropped to fill. Titles.
  poster(2 / 3, BoxFit.cover),

  /// 1:1, art CONTAINED on a plate. A channel logo is a mark, not a still:
  /// cropping it to fill cuts the wordmark in half.
  channel(1, BoxFit.contain),

  /// 16:9, cropped. Containers and wide art.
  wide(16 / 9, BoxFit.cover);

  const SpotlightCardShape(this.aspect, this.fit);

  /// width ÷ height.
  final double aspect;
  final BoxFit fit;
}

/// One row on the board.
///
/// [progressOf] is what makes Continue Watching possible without the board
/// knowing what Continue Watching IS: a shelf that returns null for every
/// item simply draws no bars.
class SpotlightShelf {
  final String title;
  final List<SpotlightCard> items;

  /// This shelf's focus nodes, owned by the host so focus survives a rebuild.
  /// Carried HERE rather than in a parallel list, because two lists that must
  /// stay the same length eventually will not be.
  final List<FocusNode> nodes;

  const SpotlightShelf({
    required this.title,
    required this.items,
    required this.nodes,
  });
}

/// **Spotlight** — the tvOS Home idiom.
///
/// The hero is **the first item of the scroll**, not a fixed backdrop the
/// shelves ride over. Measured off the reference: every scrolled frame has a
/// flat `rgb(28,28,28)` gutter, so once you are past the hero its art is gone
/// entirely — there is no dimmed artwork under the shelves. Hero and shelves
/// therefore translate together over one ground.
///
/// The hero is also **a focusable row**: LEFT/RIGHT page it, dots show
/// position, and it parks where you left it. That is the piece that changes
/// Home's focus topology rather than its paint — the other boards take their
/// identity from whatever is focused *below* them and have no cursor of their
/// own.
class SpotlightBoard extends StatefulWidget {
  /// The hero reel. Capped by the caller; parked position is restored by ITEM
  /// ID rather than index, because the rail list re-orders as tracker data
  /// arrives.
  final List<StremioMeta> hero;

  /// The shelves, in order.
  ///
  /// NOT `List<CatalogSection>` any more: Continue Watching and the favourites
  /// rails are neither that shape nor that card — they carry progress, a
  /// context menu, and entries that are not `StremioMeta` at all. A descriptor
  /// lets the host say "here is a row of things and what to do with them"
  /// without the board learning about six data sources.
  final List<SpotlightShelf> sections;

  /// The hero's own node. Registered with the host so sidebar re-entry and
  /// dead-focus reclaim can land on it.
  final FocusNode heroNode;


  /// Ask the host for another page of [row]'s items. Called when focus nears
  /// the end of a shelf — without it only each shelf's FIRST page is ever
  /// reachable, because this board owns its own scroll and the host's
  /// scroll-driven pagination never fires.
  final void Function(int row)? onLoadMoreRow;

  /// Ask the host for another batch of shelves, when DOWN runs out of them.
  final VoidCallback? onLoadMoreShelves;

  /// The hero has been resting on [item] long enough to be worth a trailer.
  ///
  /// The board owns the CADENCE; the host owns the video. That split is why
  /// the two cannot fight: there is one timer, here, and the host is told when
  /// rather than deciding for itself.
  final void Function(StremioMeta item)? onDwell;

  /// Paints over the hero while a trailer is playing. Null when the host has
  /// no trailer to show, which is also what reduced motion and the
  /// `home_hero_trailer_enabled` pref produce.
  final Widget? trailer;

  /// Off when the user has disabled hero trailers, or under reduced motion.
  /// The reel still advances — the cadence is the layout, the video is not.
  final bool trailersEnabled;

  /// Tear the trailer down. Called on every exit from the rolling state —
  /// advancing, paging by hand, and losing focus — because a video that
  /// outlives the title it was resolved for is worse than no video.
  final VoidCallback? onTrailerStop;

  /// The addon behind the hero reel, which is the shelf it was taken from.
  final StremioAddon? heroAddon;

  /// Opens the hero. Separate from a shelf's own opener because the hero is
  /// its own row, not a member of one.
  final void Function(StremioMeta, StremioAddon) onHeroOpen;

  /// Published so the shell can light the room with the focused title's
  /// colour, exactly as the other stage layouts do.
  final void Function(String? art, Color? tint)? onAmbient;

  const SpotlightBoard({
    super.key,
    required this.hero,
    required this.sections,
    required this.heroNode,
    required this.onHeroOpen,
    required this.heroAddon,
    this.onLoadMoreRow,
    this.onLoadMoreShelves,
    this.onDwell,
    this.onTrailerStop,
    this.trailer,
    this.trailersEnabled = true,
    this.onAmbient,
  });

  /// The scrolled ground. **Measured**, not chosen: `rgb(28,28,28)` at every
  /// gutter of the reference screenshots, a neutral grey drifting ~3 levels
  /// warmer down the page. Not black.
  static const Color ground = Color(0xFF1B1C1C);
  static const Color groundLow = Color(0xFF1F1D1C);

  /// Above this, the backdrop's left third is too busy for text and the
  /// identity stack flips to the right edge. Without it, text lands on a face
  /// roughly a third of the time — metahub backdrops are frame grabs, not
  /// editorial stills composed for a caption.
  static const double leftThirdBusy = 0.32;

  @override
  State<SpotlightBoard> createState() => SpotlightBoardState();
}

/// Card metrics as FRACTIONS of the space the board is actually GIVEN.
///
/// The reference is 1920 wide and its posters are 260 with a 40 gap — a pitch
/// of 300. Expressed as absolute logical pixels those only match a panel whose
/// logical width happens to be exactly half of 1920; on anything else the
/// cards come out the wrong size relative to the screen, which is precisely
/// how "a bit big, and less space between them" happens.
///
/// Proportions hold everywhere. The divisors are the raw 1920-scale numbers.
///
/// Measured against the board's own constraints rather than
/// `MediaQuery.sizeOf`, because those differ: tvOS reports a full-screen size
/// while the shell insets the content for overscan safe area (and, under
/// non-pill sidebar styles, for the rail). Sizing off the screen makes every
/// card proportionally too large for the region it is drawn in — a 260-wide
/// card in a 1920 screen becomes a 260-wide card in a ~1800 visible band.
class _M {
  final double w;
  const _M(this.w);

  double get gutter => w * (84 / 1920);
  double get poster => w * (260 / 1920);
  double get posterH => poster * (390 / 260);
  double get gap => w * (40 / 1920);

  /// What the focus effect paints OUTSIDE the resting card, which the row
  /// reserves so the lift lands on ground instead of on the headings.
  ///
  /// The card grows about its centre, so half of the 10% goes upward, and
  /// `ParallaxFocus` rises it a further 7. Reserving that much means nothing
  /// OPAQUE ever reaches the title above.
  ///
  /// The shadow reaches 9 higher still (25 of blur less its 16 of downward
  /// offset) and is deliberately NOT reserved: it is a soft blur whose far
  /// edge is invisible, and paying for it would push every row apart by more
  /// than the reference puts between them.
  double get liftUp => posterH * 0.05 + 7;

  /// Downward the rise works in our favour, so only the growth is reserved.
  double get liftDown => posterH * 0.05;
  double get title => w * (26 / 1920);
  double get caption => w * (21 / 1920);
}

class SpotlightBoardState extends State<SpotlightBoard> {
  static const double _heroHeight = 540;

  final ScrollController _scroll = ScrollController();

  /// Which hero item is showing. Held by ID so a rail re-order does not move
  /// the page under the user.
  String? _heroId;
  int _row = -1; // -1 = the hero owns the cursor
  final Map<int, int> _col = {};

  /// Left-third luminance per backdrop URL. Probed once; the result decides
  /// which side the identity sits on.
  final Map<String, double> _leftThird = {};

  /// The hero's cadence: art, then a trailer, then on to the next title.
  ///
  ///     art (4s) ──▶ trailer (20s cap) ──▶ advance ──▶ art (next)
  ///      ▲                                              │
  ///      └────────── LEFT/RIGHT: cancel, restart ───────┘
  ///
  /// ONE timer with ONE owner. The shared `_scheduleHeroTrailer` is excluded
  /// for this style precisely so the two cannot interleave and start a trailer
  /// under the wrong title.
  ///
  /// Timer-capped rather than completion-driven: `HeroTrailerBackdrop` opens
  /// trailers with `loop: !live` and exposes no completion, position or
  /// duration callback, so the machine advances on its own clock and the video
  /// simply loops until it does.
  static const Duration _artDwell = Duration(seconds: 4);

  Timer? _cadence;

  /// Whether the cadence has asked the host for a trailer.
  ///
  /// Bookkeeping for the CLOCK only — it must never gate the trailer widget.
  /// The host owns the engine's lifetime and tears it down on playback launch,
  /// route push and style change; a second opinion here is how a released
  /// engine stayed mounted.
  bool _rolling = false;

  /// One funnel for leaving the rolling state, so no exit path can forget to
  /// tell the host to tear the video down.
  void _stopRolling() {
    if (!_rolling) return;
    if (mounted) setState(() => _rolling = false);
    widget.onTrailerStop?.call();
  }

  void _restartCadence() {
    _cadence?.cancel();
    _rolling = false;
    // Frozen while focus is elsewhere: a hero that keeps paging while you are
    // three shelves down moves the page under you.
    // Frozen when focus is off the hero. `_row == -1` alone is NOT that test:
    // it only says the cursor was last in the hero band, and it stays -1 when
    // focus goes to the sidebar, another tab, or a pushed detail route — so
    // the timer kept paging and republishing ambient art for a board that was
    // covered. The node's own `hasFocus` is the real question.
    if (_row >= 0 || !widget.heroNode.hasFocus) return;
    if (widget.hero.length < 2 && !widget.trailersEnabled) return;
    if (!mounted) return;
    _cadence = Timer(_artDwell, _onArtDone);
  }

  void _onArtDone() {
    if (!mounted || _row >= 0) return;
    final item = _heroItem;
    if (widget.trailersEnabled && item != null && widget.onDwell != null) {
      // Once a trailer is rolling the reel STOPS. Cutting away from something
      // the user is actually watching to show the next poster is the opposite
      // of what the dwell is for — the carousel exists to offer titles, and a
      // playing trailer means one has already been taken up.
      //
      // It resumes on the next deliberate move: LEFT/RIGHT pages, DOWN leaves.
      setState(() => _rolling = true);
      widget.onDwell!(item);
      return;
    }
    _advance();
  }

  void _advance() {
    if (!mounted || _row >= 0) return;
    _stopRolling();
    if (widget.hero.length > 1) _page(1);
    _restartCadence();
  }

  int get _heroIndex {
    if (widget.hero.isEmpty) return 0;
    final i = widget.hero.indexWhere((m) => m.id == _heroId);
    return i < 0 ? 0 : i;
  }

  StremioMeta? get _heroItem =>
      widget.hero.isEmpty ? null : widget.hero[_heroIndex];

  @override
  void initState() {
    super.initState();
    _heroId = widget.hero.isNotEmpty ? widget.hero.first.id : null;
    widget.heroNode.addListener(_onHeroFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probe();
      _restartCadence();
    });
  }

  @override
  void didUpdateWidget(SpotlightBoard old) {
    super.didUpdateWidget(old);
    // The reel can change under us as sections load. Keep the parked item if
    // it is still present; otherwise fall back to the head rather than to a
    // stale index pointing at a different title.
    // The host can hand us a different node across a rebuild; without moving
    // the listener the old node keeps one forever and the new one has none.
    if (old.heroNode != widget.heroNode) {
      old.heroNode.removeListener(_onHeroFocus);
      widget.heroNode.addListener(_onHeroFocus);
    }
    if (_heroId != null && !widget.hero.any((m) => m.id == _heroId)) {
      // The title we were on is gone. Tear the trailer down FIRST: it was
      // resolved for that title, and leaving it rolling paints it over the new
      // head until the 20s cap expires.
      _stopRolling();
      _heroId = widget.hero.isNotEmpty ? widget.hero.first.id : null;
      _restartCadence();
    }
    // A board reload can shrink or reorder the shelves under a parked cursor.
    // `_row` is positional, so without this the next arrow key indexes past
    // the end of `rowNodes` and throws.
    if (_row >= widget.sections.length) {
      _row = widget.sections.isEmpty ? -1 : widget.sections.length - 1;
    }
    for (final row in _col.keys.toList()) {
      if (row >= widget.sections.length) {
        _col.remove(row);
        continue;
      }
      final len = widget.sections[row].nodes.length;
      if (len == 0) {
        _col.remove(row);
      } else if ((_col[row] ?? 0) >= len) {
        _col[row] = len - 1;
      }
    }
    _probe();
  }

  /// Re-arms when the hero actually holds focus and stops the moment it does
  /// not — covering the sidebar, tab switches and pushed routes in one place.
  void _onHeroFocus() {
    if (!mounted) return;
    if (widget.heroNode.hasFocus) {
      _restartCadence();
    } else {
      _cadence?.cancel();
      _stopRolling();
    }
  }

  @override
  void dispose() {
    widget.heroNode.removeListener(_onHeroFocus);
    if (_rolling) widget.onTrailerStop?.call();
    _cadence?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Bumped on every hero change. A probe that resolves after the user has
  /// paged on must not publish its colour over the current one.
  int _probeGen = 0;
  final Map<String, Color?> _tints = {};

  Future<void> _probe() async {
    final url = _heroItem?.background ?? _heroItem?.poster;
    if (url == null || url.isEmpty) return;
    final gen = ++_probeGen;

    // Publish FIRST from cache when we have it. Skipping the publish for a
    // cached URL meant paging A→B→A left B's art and tint on the shell —
    // the cache short-circuited the only code path that told anyone.
    if (_tints.containsKey(url)) {
      widget.onAmbient?.call(url, _tints[url]);
    } else {
      final tint = await extractDominantColor(
        CachedNetworkImageProvider(url,
            cacheManager: DebrifyImageCache.manager),
      );
      if (!mounted || gen != _probeGen) return;
      setState(() => _remember(url, tint));
      widget.onAmbient?.call(url, tint);
    }
    unawaited(_warmNext());
  }

  /// Luminance of the extracted colour stands in for "is the left third busy":
  /// a bright dominant means a bright image, and a bright image is one whose
  /// text side cannot be trusted. A true left-third measurement would be
  /// better and is noted in the plan.
  void _remember(String url, Color? tint) {
    _leftThird[url] = tint == null ? 0.0 : tint.computeLuminance();
    _tints[url] = tint;
  }

  /// Resolve the NEXT slide's art while this one is still showing.
  ///
  /// Without this, freezing the side below would mean every slide's FIRST
  /// appearance used the default side, because the probe cannot possibly have
  /// finished by the time the slide is drawn. The cadence gives us seconds of
  /// lead time; one image is a cheap way to spend it.
  Future<void> _warmNext() async {
    if (widget.hero.length < 2) return;
    final next = widget.hero[(_heroIndex + 1) % widget.hero.length];
    final url = next.background ?? next.poster;
    if (url == null || url.isEmpty || _tints.containsKey(url)) return;
    final tint = await extractDominantColor(
      CachedNetworkImageProvider(url, cacheManager: DebrifyImageCache.manager),
    );
    if (!mounted) return;
    setState(() => _remember(url, tint));
  }

  /// Which item `_flipValue` was decided for.
  String? _flipFor;
  bool _flipValue = false;

  /// The side the identity sits on, FROZEN for as long as an item is showing.
  ///
  /// This used to read `_leftThird` directly on every build. That map is
  /// filled by an async probe, so a slide appeared with its logo on one side
  /// and then, a second or two later, jumped to the other as the probe landed
  /// — the one thing a title card must never do while someone is reading it.
  ///
  /// Memoised by item id rather than recomputed: a probe that resolves for the
  /// slide currently on screen updates the map for NEXT time, and moves
  /// nothing now. `_warmNext` is what keeps "next time" from being the common
  /// case.
  bool get _flip {
    final item = _heroItem;
    if (item == null) return false;
    if (_flipFor != item.id) {
      _flipFor = item.id;
      final url = item.background ?? item.poster;
      _flipValue = url != null &&
          (_leftThird[url] ?? 0) > SpotlightBoard.leftThirdBusy;
    }
    return _flipValue;
  }

  // ── movement ───────────────────────────────────────────────────────────

  void _go(FocusNode node, Offset dir) {
    ParallaxTravel.note(dir);
    node.requestFocus();
  }

  void _page(int delta) {
    if (widget.hero.length < 2) return;
    final n = widget.hero.length;
    final next = (_heroIndex + delta + n) % n;
    _stopRolling();
    setState(() => _heroId = widget.hero[next].id);
    ParallaxTravel.note(Offset(delta.toDouble(), 0));
    _probe();
    _restartCadence();
  }

  void _down() {
    if (_row < 0) {
      if (widget.sections.isEmpty) return;
      _stopRolling();
      setState(() => _row = 0);
      _cadence?.cancel();
      _focusRow(0, const Offset(0, 1));
      return;
    }
    if (_row + 1 >= widget.sections.length) {
      // Out of shelves: ask for the next batch rather than dead-stopping.
      widget.onLoadMoreShelves?.call();
      return;
    }
    setState(() => _row = _row + 1);
    _focusRow(_row, const Offset(0, 1));
  }

  void _up() {
    if (_row <= 0) {
      setState(() => _row = -1);
      _restartCadence();
      _go(widget.heroNode, const Offset(0, -1));
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _row = _row - 1);
    _focusRow(_row, const Offset(0, -1));
  }

  void _focusRow(int row, Offset dir) {
    if (row < 0 || row >= widget.sections.length) return;
    final nodes = widget.sections[row].nodes;
    if (nodes.isEmpty) return;
    final col = (_col[row] ?? 0).clamp(0, nodes.length - 1);
    _go(nodes[col], dir);
  }

  /// Where the cursor ACTUALLY is in [nodes].
  ///
  /// `_col` is bookkeeping and can drift — a scroll-into-view, a rebuild, or
  /// anything that moves focus without going through `_walk` leaves it stale.
  /// A stale column is what made LEFT fall through while focus sat mid-row,
  /// handing the key to the shell's geometric search, which then jumped to
  /// whatever row happened to be nearest.
  int _liveCol(List<FocusNode> nodes) {
    final i = nodes.indexWhere((n) => n.hasFocus);
    if (i >= 0) return i;
    return (_col[_row] ?? 0).clamp(0, nodes.length - 1);
  }

  /// The shelf that actually holds focus, or -1 for the hero.
  int _liveRow() {
    for (var i = 0; i < widget.sections.length; i++) {
      if (widget.sections[i].nodes.any((n) => n.hasFocus)) return i;
    }
    return -1;
  }

  void _walk(int delta) {
    if (_row < 0 || _row >= widget.sections.length) {
      _page(delta);
      return;
    }
    final nodes = widget.sections[_row].nodes;
    if (nodes.isEmpty) return;
    final at = _liveCol(nodes);
    final next = at + delta;
    if (next < 0 || next >= nodes.length) return;
    setState(() => _col[_row] = next);
    _go(nodes[next], Offset(delta.toDouble(), 0));
    // Four from the end is roughly one screen of posters — enough lead time
    // for a page to land before the cursor reaches where it would have
    // stopped.
    if (next >= nodes.length - 4) widget.onLoadMoreRow?.call(_row);
  }

  KeyEventResult _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Re-sync from reality before acting on it.
    final live = _liveRow();
    if (live != _row) _row = live;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _down();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _up();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _walk(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
        // The hero was focusable and inert: arrows paged it, but OK did
        // nothing at all, so the reel could be browsed and never opened.
        final item = _heroItem;
        final addon = widget.heroAddon;
        if (_row < 0 && item != null && addon != null) {
          widget.onHeroOpen(item, addon);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        // Column 0 and LEFT again falls THROUGH, so the shell's sidebar
        // handler sees it. That is the one and only way in, per the LEFT-only
        // policy — nothing here calls focusTvSidebar.
        //
        // Tested against LIVE focus, not `_col`: falling through from the
        // middle of a row hands the key to a geometric search that lands in
        // another row, which is what made the sidebar hard to reach.
        if (_row >= 0 && _row < widget.sections.length) {
          final nodes = widget.sections[_row].nodes;
          if (nodes.isEmpty || _liveCol(nodes) == 0) {
            return KeyEventResult.ignored;
          }
        }
        // The hero obeys the same rule as a shelf: at the FIRST item there is
        // nothing to its left but the sidebar. It used to wrap round to the
        // last slide instead, which made the reel a loop with no exit — the
        // one gesture that opens the sidebar was the one gesture it ate.
        if (_row < 0 && (widget.hero.length < 2 || _heroIndex == 0)) {
          return KeyEventResult.ignored;
        }
        _walk(-1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Where the shell should land focus on re-entry.
  FocusNode? focusTarget() {
    if (_row < 0) return widget.heroNode;
    if (_row >= widget.sections.length) return widget.heroNode;
    final nodes = widget.sections[_row].nodes;
    if (nodes.isEmpty) return widget.heroNode;
    return nodes[(_col[_row] ?? 0).clamp(0, nodes.length - 1)];
  }

  // ── paint ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _onKey(e),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final m = _M(constraints.maxWidth);
          return _board(m);
        },
      ),
    );
  }

  Widget _board(_M m) {
    return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SpotlightBoard.ground, SpotlightBoard.groundLow],
          ),
        ),
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            // Laid out 88 short so the first shelf sits over the hero's lower
            // edge; the hero PAINTS its full height by overflowing downward,
            // which the ListView clips only below the shelves that cover it
            // anyway.
            SizedBox(
              height: _heroHeight - 88,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: _heroHeight,
                child: SizedBox(height: _heroHeight, child: _hero(m)),
              ),
            ),
            // The first shelf overlaps the hero's lower edge — the tell that
            // the page continues.
            //
            // The hero is drawn 88 SHORTER than its visual height rather than
            // the shelves being transformed up over it. A `Transform` moves
            // paint and hit-testing but leaves the ListView's extent alone, so
            // the overlap reappears as a phantom 88px gap at the bottom and
            // the page overscrolls past its own last shelf. Sizing the hero
            // box is the version the scroll extent agrees with.
            Padding(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.sections.length; i++) _shelf(i, m),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
    );
  }

  Widget _hero(_M m) {
    final item = _heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = item.background ?? item.poster;
    final flip = _flip;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            key: ValueKey(url),
            fit: BoxFit.cover,
            cacheManager: DebrifyImageCache.manager,
            memCacheWidth: 1400,
            fadeInDuration: const Duration(milliseconds: 420),
            placeholder: (_, __) =>
                const ColoredBox(color: SpotlightBoard.ground),
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: SpotlightBoard.ground),
          ),
        // Mounted whenever the HOST supplies one — never gated on this
        // board's own `_rolling`.
        //
        // Gating it here kept the layer alive after the host tore the trailer
        // down (`_clearHeroTrailer` on playback launch), so its media_kit
        // engine was still holding a VideoOutput when the player created its
        // own. Two VideoOutputs is SIGABRT on tvOS — the crash was at
        // `enableHardwareAcceleration`, in the second one's constructor.
        //
        // The host already owns this lifecycle for every other board; the
        // board's job is the cadence, and only the cadence.
        if (widget.trailer != null) Positioned.fill(child: widget.trailer!),
        // The identity scrim, on whichever side the text is.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: flip ? const Alignment(1, -0.2) : const Alignment(-1, -0.2),
                end: flip ? const Alignment(-1, 0.2) : const Alignment(1, 0.2),
                colors: const [
                  Color(0xE0000000),
                  Color(0xA8000000),
                  Color(0x2E000000),
                  Color(0x00000000),
                ],
                stops: const [0, 0.26, 0.52, 0.68],
              ),
            ),
          ),
        ),
        // Fades into the SHELF GROUND, not into black — a scrim landing on a
        // colour the page never paints leaves a visible seam where the hero
        // ends.
        const IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      SpotlightBoard.ground,
                      Color(0xEB1B1C1C),
                      Color(0x731B1C1C),
                      Color(0x001B1C1C),
                    ],
                    stops: [0.04, 0.22, 0.56, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: flip ? null : m.gutter,
          right: flip ? m.gutter : null,
          bottom: 128,
          width: m.w * (820 / 1920),
          child: _identity(item, flip),
        ),
        if (widget.hero.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 92,
            child: _dots(),
          ),
        // The hero's focusable surface. IgnorePointer-free and zero-sized in
        // paint terms: the hero shows focus through the page, not through a
        // ring on a full-screen box.
        // `skipTraversal`: the hero is reached ONLY by the explicit UP
        // handler. Left findable, a geometric LEFT/UP search from the first
        // shelves lands on it — which is why LEFT from row 1 and 2 went to the
        // hero instead of falling through to the sidebar. It sits at x=0, so
        // it is the nearest thing to the left of everything.
        Positioned(
          left: 0,
          top: 0,
          child: Focus(
            focusNode: widget.heroNode,
            skipTraversal: true,
            descendantsAreTraversable: false,
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _identity(StremioMeta item, bool flip) {
    final cross = flip ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = flip ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoOrTitle(url: item.logo, name: item.name, align: align),
        const SizedBox(height: 9),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: align,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        if ((item.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            item.description!,
            maxLines: 2,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.42,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.hero.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 2.25),
              width: i == _heroIndex ? 11 : 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == _heroIndex ? 0.95 : 0.34),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      );

  Widget _shelf(int i, _M m) {
    final section = widget.sections[i];
    final nodes = section.nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // The gap under the title is `liftUp`, supplied by the row below —
          // reserved space that is empty at rest and consumed by the lift.
          padding: EdgeInsets.fromLTRB(m.gutter, 20, m.gutter, 0),
          child: Text(
            section.title,
            style: TextStyle(
              fontSize: m.title,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
        ),
        Padding(
          // The room the lift needs sits OUTSIDE the viewport, as padding.
          //
          // It used to be added to the viewport's own height instead, and that
          // was the bug behind cards reading far too tall: a horizontal
          // ListView constrains its children to the viewport height TIGHTLY,
          // so every card was stretched to `posterH * 1.10 + 24` while its
          // width was still computed from `posterH`. A 2:3 poster drew at
          // 0.53:1. No amount of re-deriving the ratio could have fixed it.
          padding: EdgeInsets.only(top: m.liftUp, bottom: m.liftDown),
          child: SizedBox(
            // The viewport IS the card now, so the tight cross-axis constraint
            // hands each card exactly the height it asked for.
            height: m.posterH,
            child: ListView.separated(
              // The lift paints into the padding above and below rather than
              // being sliced off at the viewport edge.
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: m.gutter),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => SizedBox(width: m.gap),
              itemBuilder: (context, c) => _Card(
                card: section.items[c],
                node: c < nodes.length ? nodes[c] : null,
                // Every shape shares the ROW's height and takes the width its
                // aspect implies, so a shelf that mixes posters and channel
                // tiles sits on one baseline instead of stepping up and down.
                height: m.posterH,
                caption: m.caption,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Logo art when it exists and is light enough to see; the title otherwise.
class _LogoOrTitle extends StatelessWidget {
  final String? url;
  final String name;
  final TextAlign align;

  const _LogoOrTitle({required this.url, required this.name, required this.align});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: 2,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 39,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: Colors.white,
      ),
    );
    if (url == null || url!.isEmpty) return text;
    final corner =
        align == TextAlign.right ? Alignment.bottomRight : Alignment.bottomLeft;
    // A RESERVED slot, not a maximum.
    //
    // This was a `ConstrainedBox(maxWidth: 235, maxHeight: 60)`, which sizes
    // itself to whatever is inside it. Before the art lands there is nothing
    // inside it, so the slot collapsed and the identity below sat higher up;
    // when the logo arrived a second or two later the block reflowed and
    // everything settled into a different place. The column is anchored by its
    // BOTTOM, so the whole identity moved, not just the logo.
    //
    // Holding the box at full size from the first frame means the art fades
    // into a space already shaped for it and nothing else moves.
    return SizedBox(
      width: 235,
      height: 60,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.contain,
        alignment: corner,
        cacheManager: DebrifyImageCache.manager,
        memCacheWidth: 520,
        placeholder: (_, __) => const SizedBox.shrink(),
        // The title has to earn its way into the same slot rather than
        // resizing it — scaleDown only shrinks, so short titles keep their
        // intended weight.
        //
        // The inner width is what makes that bearable: FittedBox offers its
        // child unbounded width, so without it `maxLines: 2` never wraps and a
        // long title is scaled down as one very long line.
        errorWidget: (_, __, ___) => Align(
          alignment: corner,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: corner,
            child: SizedBox(width: 235, child: text),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatefulWidget {
  final SpotlightCard card;
  final FocusNode? node;

  /// The ROW's height. Width follows from the shape's aspect, so a shelf that
  /// mixes posters and channel tiles keeps one baseline.
  final double height;
  final double caption;

  const _Card({
    required this.card,
    required this.node,
    required this.height,
    required this.caption,
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final w = widget.height * c.shape.aspect;
    final url = c.image;
    final contained = c.shape.fit == BoxFit.contain;

    final card = ParallaxFocus(
      focused: _f,
      radius: BorderRadius.circular(7),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: w,
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A contained mark needs a plate behind it: channel logos are
              // frequently light-on-transparent and vanish on the ground.
              ColoredBox(
                color: contained
                    ? const Color(0xFF26272A)
                    : const Color(0xFF17171A),
              ),
              if (url != null && url.isNotEmpty)
                Padding(
                  padding: EdgeInsets.all(contained ? w * 0.14 : 0),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: c.shape.fit,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 400,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if ((c.progress ?? 0) > 0 && (c.progress ?? 0) < 100)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: c.progress! / 100,
                    minHeight: 2,
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              // The caption sits INSIDE over a gradient bed — below the card
              // only on a 16:9 episode cell, which this is not.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xDB000000), Color(0x00000000)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 26, 7, 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.title,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.caption,
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                        ),
                        if ((c.subtitle ?? '').isNotEmpty)
                          Text(
                            c.subtitle!,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: widget.caption * 0.85,
                              color: Colors.white.withValues(alpha: 0.58),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.node == null) return card;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v && context.findRenderObject() is RenderBox) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.gameButtonA) {
          c.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: c.onOpen,
        onLongPress: c.onOptions,
        child: card,
      ),
    );
  }
}
