import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../../utils/artwork_url.dart';
import '../../utils/platform_util.dart';
import '../episodes_panel.dart';
import '../section_reveal.dart';
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

/// One deliberately static, theme-coloured placeholder plane.
///
/// This does not use [ThemedSkeleton]: the legacy profile intentionally keeps
/// its animated shimmer on TV, while this surface exists specifically to give
/// a weak GPU a quiet frame in which to decode and compose the real page.
class _ShowcaseTvSkeletonPlane extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const _ShowcaseTvSkeletonPlane({
    this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: app.core.tx.withValues(alpha: .09),
          borderRadius: borderRadius,
          border: Border.all(color: app.core.tx.withValues(alpha: .035)),
        ),
      ),
    );
  }
}

/// The TV opening state is a small number of static, themed planes. The real
/// page remains mounted beneath it, so its image providers and lazy bands can
/// settle without exposing their incremental arrival.
class _ShowcaseTvOpeningSkeleton extends StatelessWidget {
  const _ShowcaseTvOpeningSkeleton();

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ExcludeFocus(
      child: IgnorePointer(
        child: ColoredBox(
          key: const ValueKey('showcase-tv-opening-skeleton'),
          color: app.home.bg,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = (constraints.maxWidth * .044).clamp(30.0, 52.0);
              return Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ShowcaseTvSkeletonPlane(
                      width: 52,
                      height: 17,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    _ShowcaseTvSkeletonPlane(
                      width: (constraints.maxWidth * .29).clamp(220.0, 350.0),
                      height: 40,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 12),
                    _ShowcaseTvSkeletonPlane(
                      width: 180,
                      height: 13,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 9),
                    _ShowcaseTvSkeletonPlane(
                      width: (constraints.maxWidth * .42).clamp(280.0, 460.0),
                      height: 13,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 18),
                    _ShowcaseTvSkeletonPlane(
                      width: 122,
                      height: 34,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(
                            child: _ShowcaseTvSkeletonPlane(
                              height: 62,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
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

  /// A TV opens on one composed frame, instead of asking the GPU to reveal a
  /// backdrop, wordmark and several off-screen rails independently. The shell
  /// starts its backdrop decode before this body builds; this gate warms the
  /// matching image-cache keys, then lets the page crossfade in once the first
  /// useful frame is ready. It is deliberately TV-only — touch keeps its
  /// existing immediate, scroll-led presentation.
  bool _openingReady = false;
  bool _openingWarmupScheduled = false;
  EpisodesPanelView? _openingView;
  bool _openingUserNavigated = false;
  bool _openingKeyHandlerAttached = false;
  static const _openingMinimum = Duration(milliseconds: 180);
  static const _openingTimeout = Duration(milliseconds: 1200);

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

  /// Compact episodes rail: which card sits at the reading position. Touch
  /// has no cursor, so "focus" is what the scroll has settled on — the IPTV
  /// centered-selector grammar. The settled card wears the same parallax
  /// lift the TV cursor grants, and the highlight hops cell to cell live as
  /// the rail is dragged, so the row reads as alive rather than as a flat
  /// strip. DPAD never consults this — its focus is real.
  late final ScrollController _epScroll = ScrollController()
    ..addListener(_onEpScroll);
  int _epSettled = 0;

  void _onEpScroll() {
    final m = _m;
    if (m == null || !m.compact || !_epScroll.hasClients) return;
    final extent = m.epCell + m.epGap;
    if (extent <= 0) return;
    final settled = (_epScroll.offset / extent).round();
    final clamped = settled < 0 ? 0 : settled;
    if (clamped != _epSettled) setState(() => _epSettled = clamped);
  }

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
        ? off >
              _viewportH *
                  0.30 // stays deep until it drops below 30%
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_usesTvOpeningGate && !_openingWarmupScheduled) {
      _openingWarmupScheduled = true;
      HardwareKeyboard.instance.addHandler(_onOpeningHardwareKey);
      _openingKeyHandlerAttached = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _warmTvOpening());
    }
  }

  bool get _usesTvOpeningGate => widget.dpad && PlatformUtil.isTelevision;

  Future<void> _warmTvOpening() async {
    if (!mounted || !_usesTvOpeningGate) return;
    final watch = Stopwatch()..start();
    // Let the hidden page finish its first layout before taking the provider
    // snapshot. The hosted episode view is supplied during that build.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // IMDb enrichment, recommendations and the hosted episode loader can add
    // whole bands after the first frame. Keep taking the cheap static frames
    // until those producers finish, then snapshot the final opening artwork.
    // The hard deadline prevents a slow metadata service from holding the UI.
    while (mounted &&
        watch.elapsed < _openingTimeout &&
        (!widget.model.openingDataReady || (_openingView?.loading ?? false))) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final providers = _openingImageProviders();
    try {
      final remaining = _openingTimeout - watch.elapsed;
      if (remaining > Duration.zero) {
        await Future.wait<void>([
          for (final provider in providers) _precacheQuietly(provider),
        ]).timeout(remaining);
      }
    } catch (_) {
      // The skeleton has a bounded life even if an artwork host is slow or
      // unavailable. The normal image widgets keep their own placeholders and
      // retry/cache policy after the page arrives.
    }
    final remaining = _openingMinimum - watch.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    // Give the raster thread one more presentation boundary after the decoded
    // images enter the cache. Without this, an already-completed precache can
    // still reveal on the same frame that uploads the texture on weak TV GPUs.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _detachOpeningKeyHandler();
    setState(() => _openingReady = true);
    // The page was deliberately focus-excluded while hidden. Autofocus is only
    // considered when the primary action first mounts, so explicitly restore
    // the normal TV entry point once the gate opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focused = FocusManager.instance.primaryFocus;
      if (!_openingUserNavigated ||
          focused == null ||
          focused == FocusManager.instance.rootScope ||
          focused == widget.model.focus.primaryEntry) {
        widget.model.focus.focusEntry();
      }
    });
  }

  bool _onOpeningHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.tab) {
      _openingUserNavigated = true;
    }
    return false;
  }

  void _detachOpeningKeyHandler() {
    if (!_openingKeyHandlerAttached) return;
    HardwareKeyboard.instance.removeHandler(_onOpeningHardwareKey);
    _openingKeyHandlerAttached = false;
  }

  List<ImageProvider> _openingImageProviders() {
    final providers = <ImageProvider>[];
    final seen = <String>{};
    void add(String? url, int width) {
      if (url == null || url.isEmpty || !seen.add('$width:$url')) return;
      providers.add(
        CachedNetworkImageProvider(
          url,
          cacheManager: DebrifyImageCache.manager,
          maxWidth: width,
        ),
      );
    }

    // Match each consumer's decode width. Each rail is capped at its first TV
    // screenful; warming cards that cannot yet be painted would recreate the
    // GPU spike behind the cover instead of smoothing it.
    add(highQualityArtworkUrl(widget.model.backdrop), 1400);
    add(widget.model.logo, 520);
    final view = _openingView;
    if (view != null) {
      for (final episode in view.episodes.take(6)) {
        add(episode.thumbnailUrl ?? view.showImageUrl, 500);
      }
    }
    for (final member in widget.model.cast.take(7)) {
      add(member.imageUrl, 260);
    }
    for (final item in widget.model.recommendations.take(6)) {
      add(item.poster, 300);
    }
    for (final item in _universe.take(6)) {
      add(item.posterUrl, 300);
    }
    return providers;
  }

  Future<void> _precacheQuietly(ImageProvider provider) async {
    try {
      await precacheImage(provider, context);
    } catch (_) {
      // See _warmTvOpening: this is presentation preparation, never a reason
      // to block a usable detail page.
    }
  }

  @override
  void dispose() {
    _detachOpeningKeyHandler();
    _scroll.dispose();
    _epScroll.dispose();
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
      // LONG jump, and from a low band the identity can be scrolled out of the
      // list and disposed, so the entry node is unmounted just as a far card
      // is. `focusEntry` falls back to the always-mounted back button rather
      // than no-op into the same dead end.
      //
      // The band only follows when the identity is where focus actually WENT.
      // On the fallback the cursor is on a shell control and the list has not
      // moved, so claiming 'identity' would publish a shallow depth: the shell
      // reads that to restore the sharp key art and to hand the trailer a play
      // URL again, which would start a decoder behind a page still parked on a
      // low band. `_step`'s own exit to the back button leaves the band alone
      // for exactly this reason.
      final toIdentity = detailNodeMounted(widget.model.focus.primaryEntry);
      ParallaxTravel.note(const Offset(-1, 0));
      widget.model.focus.focusEntry();
      if (toIdentity) _setBand('identity');
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
        ? episodePeek +
              // Only the ROW k-scales — ShowcaseSeasons renders
              // `SizedBox(height: 34 * k)` while the air around it stays fixed.
              // Scaling the whole 50 over-reserved by 16·(k−1) on wide touch,
              // showing a sliver more episode row than the 0.18 peek pins.
              (m.compact
                  ? _seasonPillBandHeight
                  : _seasonsRowHeight * m.k + _seasonsBandAir)
        : episodePeek;
  }

  /// The seasons row's own height ([ShowcaseSeasons]' SizedBox — k-scaled
  /// there, so k-scaled in the peek) and the fixed air around it. Their sum
  /// was a single guessed 96 once; `ShowcaseSeasons` is a bare 34pt row, and
  /// every over-reserved pixel went to showing more of the episode row than
  /// was ever intended.
  static const double _seasonsRowHeight = 34;
  static const double _seasonsBandAir = 16;

  /// Compact renders the season control as a 34pt pill with more air around
  /// it (a finger needs what a remote never did).
  static const double _seasonPillBandHeight = 56;

  /// Which bands have played their entrance, by band key.
  ///
  /// Held HERE rather than inside the reveal widget because the list is lazy:
  /// scroll a band more than `cacheExtent` away and its element — and any
  /// state it owned — is collected, so a band the user had already watched
  /// arrive would arrive again on every pass down the page.
  final Set<String> _revealed = {};

  /// Touch's answer to the DPAD's band cursor.
  ///
  /// On a remote the lift and `_reveal`'s parking scroll are what say which
  /// band you are in. Under a finger nothing moves but the page itself, so
  /// each band earns its arrival instead: it fades, rises and comes forward
  /// the first time it crosses into the viewport, then holds still while it is
  /// read.
  ///
  /// DPAD gets the band untouched. An entrance there would animate against the
  /// parking scroll that put the band on screen, and the motion tokens already
  /// return [EntranceStyle.none] on television.
  ///
  /// Keyed per band rather than by list position: Seasons and Episodes appear
  /// once their data lands, and without a key the arriving band would inherit
  /// the state of whatever sat at its index before.
  Widget _band(String id, Widget child) => widget.dpad
      ? child
      : SectionReveal(
          key: ValueKey('showcase-band-$id'),
          startWhenVisible: true,
          scaleFrom: 0.98,
          alreadyRevealed: _revealed.contains(id),
          onRevealed: () => _revealed.add(id),
          child: child,
        );

  void _reveal(_Band band) {
    // A band the cursor steps into must be sitting at its RESTING transform
    // before anything measures it. `ensureVisible` composes the paint
    // transforms of every ancestor, and an unrevealed band is still holding
    // the entrance's 4% drop and 0.98 scale — so the parking scroll would be
    // computed off a rect that is about to move, and the band would settle
    // off its `rest` alignment. Marking it revealed snaps it to rest; the
    // scroll waits one frame for that to land.
    //
    // dpad:false pages reach here too — they still receive arrow keys from
    // real keyboards — which is exactly the case the wrapper affects.
    if (!widget.dpad && !_revealed.contains(band.key)) {
      setState(() => _revealed.add(band.key));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _park(band);
      });
      return;
    }
    _park(band);
  }

  void _park(_Band band) {
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
    final Widget content = (host == null || widget.model.isMovie)
        ? _shell(context, null)
        : host((context, view) => _shell(context, view));
    // Opt the whole detail page into the FULL parallax on Android TV (spring +
    // tilt + glare). A handful of cards lifting one at a time is a budget the
    // busy home board is not — so home, settings and onboarding stay on the
    // cheap lite body, and only this subtree gets the rich effect.
    return ParallaxRichScope(child: content);
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
    open(
      StremioMeta(
        id: u.imdbId,
        imdbId: u.imdbId,
        type: u.isSeries ? 'series' : 'movie',
        name: u.name,
        poster: u.posterUrl,
        year: u.year?.toString(),
      ),
    );
  }

  /// The bands as they exist for THIS build. Order here is the DPAD order.
  List<_Band> _bands(EpisodesPanelView? view) {
    final m = widget.model;
    final bands = <_Band>[
      _Band(
        'identity',
        [
          if (m.showPrimary) m.focus.primaryEntry,
          ..._grow(_actionNodes, _actionCount(m), 'showcase-act'),
        ],
        _identityKey,
        0,
      ),
    ];
    if (view != null && view.seasons.length > 1) {
      // Compact renders ONE control — the season pill — so its band carries
      // exactly one node. Listing a node per season here while the rendering
      // mounts a single pill would let a desktop arrow key focus a detached
      // node (dpad:false still receives arrow keys from real keyboards) and
      // strand the cursor. Topology always matches rendering.
      final compact = (_m?.compact ?? false);
      bands.add(
        _Band(
          'seasons',
          _grow(
            _seasonNodes,
            compact ? 1 : view.seasons.length,
            'showcase-season',
          ),
          _seasonsKey,
          110,
        ),
      );
    }
    if (view != null && view.episodes.isEmpty && view.unavailable) {
      // A band with one control in it. Without this entry the Retry chip is
      // rendered, focusable, and unreachable — the parent's key handler only
      // ever walks the bands in this list.
      bands.add(
        _Band(
          'retry',
          _grow(_retryNodes, 1, 'showcase-retry'),
          _episodesKey,
          125,
        ),
      );
    }
    if (view != null && view.episodes.isNotEmpty) {
      bands.add(
        _Band(
          'episodes',
          [
            for (final ep in view.episodes)
              _cells.of(view.generation, ep.season, ep.number),
          ],
          _episodesKey,
          125,
        ),
      );
    }
    if (m.cast.isNotEmpty) {
      bands.add(
        _Band(
          'cast',
          _grow(_castNodes, m.cast.length, 'showcase-cast'),
          _castKey,
          150,
        ),
      );
    }
    if (_hasGuide) {
      bands.add(
        _Band(
          'guide',
          _grow(
            _guideNodes,
            m.parentsGuide!.categories.length,
            'showcase-guide',
          ),
          _guideKey,
          130,
        ),
      );
    }
    bands.add(
      _Band(
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
      ),
    );
    if (m.recommendations.isNotEmpty) {
      bands.add(
        _Band(
          'recs',
          _grow(_recNodes, m.recommendations.length, 'showcase-rec'),
          _recsKey,
          150,
        ),
      );
    }
    if (_universe.isNotEmpty) {
      bands.add(
        _Band(
          'universe',
          _grow(_uniNodes, _universe.length, 'showcase-uni'),
          _uniKey,
          150,
        ),
      );
    }
    if (_dyk.isNotEmpty) {
      bands.add(
        _Band(
          'dyk',
          _grow(_dykNodes, _dykNodeCount, 'showcase-dyk'),
          _dykKey,
          150,
        ),
      );
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

  Widget _page(BuildContext context, EpisodesPanelView? view) {
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
          // The input axis, so the metrics' [ShowcaseMetrics.k] scale can tell
          // a wide tablet (960-canvas fixed values rendered small) from a TV
          // (where they are exact and must stay so).
          touch: !widget.dpad,
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
    final opening = _usesTvOpeningGate && !_openingReady;
    if (opening) _openingView = view;
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
        ExcludeFocus(
          excluding: opening,
          child: IgnorePointer(
            ignoring: opening,
            child: AnimatedOpacity(
              opacity: opening ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                // DPAD moves focus before it scrolls. Keep the original broad
                // mount window so the next target has a live node and anchor;
                // the opaque opening plane hides these bands while they warm.
                scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                children: [
                  ShowcaseIdentity(
                    key: _identityKey,
                    model: m,
                    primaryNode: m.focus.primaryEntry,
                    actionNodes: _grow(
                      _actionNodes,
                      _actionCount(m),
                      'showcase-act',
                    ),
                    onFocused: () => _setBand('identity'),
                    height: _heroHeight(view, viewport),
                  ),
                  if (view != null && view.seasons.length > 1)
                    _band(
                      'seasons',
                      ShowcaseSeasons(
                        key: _seasonsKey,
                        view: view,
                        nodes: _grow(
                          _seasonNodes,
                          view.seasons.length,
                          'showcase-season',
                        ),
                      ),
                    ),
                  if (view != null && view.episodes.isNotEmpty)
                    _band('episodes', _episodes(view))
                  else if (view != null && view.loading)
                    // The same slot as the rail it stands in for, so the swap from
                    // note to episodes is not a second arrival.
                    _band(
                      'episodes',
                      const ShowcaseBandNote(text: 'Loading episodes…'),
                    )
                  else if (view != null && view.unavailable)
                    // 'retry' matches this note's key in `_bands` — the ladder
                    // treats it as a band of its own, so the reveal must too, or
                    // the one band the user is staring at is the one that pops in
                    // while its neighbours fade.
                    _band(
                      'retry',
                      ShowcaseBandNote(
                        text: 'Episodes unavailable',
                        actionLabel: 'Retry',
                        onAction: view.onRetry,
                        actionNode: _grow(
                          _retryNodes,
                          1,
                          'showcase-retry',
                        ).first,
                      ),
                    ),
                  if (m.cast.isNotEmpty)
                    _band(
                      'cast',
                      ShowcaseCast(
                        key: _castKey,
                        cast: m.cast,
                        nodes: _grow(
                          _castNodes,
                          m.cast.length,
                          'showcase-cast',
                        ),
                      ),
                    ),
                  if (_hasGuide)
                    _band(
                      'guide',
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
                    ),
                  _band(
                    'sources',
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
                  ),
                  if (m.recommendations.isNotEmpty)
                    _band(
                      'recs',
                      ShowcaseRecs(
                        key: _recsKey,
                        items: m.recommendations,
                        nodes: _grow(
                          _recNodes,
                          m.recommendations.length,
                          'showcase-rec',
                        ),
                        onTap: m.onRecommendationTap,
                      ),
                    ),
                  if (_universe.isNotEmpty)
                    _band(
                      'universe',
                      ShowcaseUniverse(
                        key: _uniKey,
                        items: _universe,
                        nodes: _grow(
                          _uniNodes,
                          _universe.length,
                          'showcase-uni',
                        ),
                        onOpen: m.onRecommendationTap != null
                            ? _openUniverse
                            : null,
                      ),
                    ),
                  if (_dyk.isNotEmpty)
                    _band(
                      'dyk',
                      ShowcaseDidYouKnow(
                        key: _dykKey,
                        entries: _dyk,
                        total: _x?.didYouKnowTotal ?? _dyk.length,
                        countLine: _dykCountLine,
                        nodes: _grow(_dykNodes, _dykNodeCount, 'showcase-dyk'),
                      ),
                    ),
                  // Reference material, last and unfocusable — it is not a band in
                  // the DPAD ladder, it is the page's footer.
                  _band(
                    'details',
                    ShowcaseDetails(rows: m.detailRows, awards: m.awards),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        if (opening) const _ShowcaseTvOpeningSkeleton(),
      ],
    );
  }

  int _actionCount(DetailModel m) {
    var n = 0;
    if (m.onToggleMyWatchlist != null) n++;
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
        // for the integrated card's plate; wide k-scales the caption block in
        // step with its type.
        height: m.compact ? m.stillH + m.epPlate : m.stillH + 108 * m.k,
        child: ListView.separated(
          // The lift, its 7px rise and its 25px shadow all paint outside the
          // cell; a clipping viewport slices exactly the effect off.
          clipBehavior: Clip.none,
          controller: _epScroll,
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
                      // Real focus (a phone with a keyboard exists) OR the
                      // scroll-settled reading position — see [_epSettled].
                      focused: focused || i == _epSettled,
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
                      onOptions: widget.dpad ? null : () => view.options(ep),
                    ),
            );
          },
        ),
      ),
    );
  }
}
