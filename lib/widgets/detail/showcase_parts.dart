import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../../services/imdb_parents_guide_service.dart';
import '../../services/series_source_service.dart';
import '../../services/trakt/trakt_episode_model.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../../utils/platform_util.dart';
import '../../utils/wide_touch_scale.dart';
import '../episodes_panel.dart';
import '../tracker_brand_marks.dart';
import 'detail_model.dart';

/// Card metrics as FRACTIONS of the viewport.
///
/// The mock is 1920 wide; absolute logical pixels derived from it only land
/// correctly on a panel whose logical width is exactly 960. Anywhere else the
/// cards come out the wrong size relative to the screen and the gaps close up
/// — which is exactly what "a bit big, with less space between them" is.
/// The divisors below are the raw 1920-scale numbers from the mock.
class ShowcaseMetrics {
  final double w;

  /// Compact — the phone presentation, chosen by [DetailShowcase] from its
  /// own width AND input (never by width alone: a narrow TV keeps the wide
  /// presentation so the DPAD ladder's widgets all exist). Compact values are
  /// measured off the Apple TV phone app on the reference device — see
  /// design/mockups/spotlight_responsive_mockup/.
  final bool compact;

  /// The INPUT axis, carried so [k] can tell a wide tablet from a TV. False
  /// everywhere the metrics come from the MediaQuery fallback, which keeps
  /// every caller outside the Showcase page at the shipped TV numbers.
  final bool touch;

  const ShowcaseMetrics(this.w, {this.compact = false, this.touch = false});

  /// The type-and-control scale for the wide TOUCH tier.
  ///
  /// The wide tier's fixed values — every `_t` literal, the pill heights, the
  /// guide and DYK cards — are 960-canvas numbers, and a TV's logical width IS
  /// ~960 (the scaled surface). A tablet hits the same tier at its real width:
  /// an iPad Pro lands at 1366, where those fixed values render at ~70% of
  /// their designed proportion — 10.5pt plot text and a 30pt primary pill on a
  /// touch device. Scaling them by w/960 restores the mock's proportions
  /// exactly, and because the proportional values (`w * x/1920`) already track
  /// width, text and cards grow TOGETHER rather than drifting apart.
  ///
  /// Exactly 1.0 on TV (dpad keeps every shipped pixel) and on compact (its
  /// absolutes are hand-measured off the Apple phone app, not derived).
  /// The formula lives in [wideTouchScale], shared with the Home Spotlight
  /// board so the two surfaces can never be retuned apart.
  ///
  /// Radii follow one rule: a radius k-scales exactly when its box does —
  /// capsules (radius = height/2) and the k-sized cards/chips scale, while
  /// boxes sized proportionally off `w` keep their shipped radii.
  double get k => (compact || !touch) ? 1.0 : wideTouchScale(w);

  /// From the space actually GIVEN, not from the screen.
  ///
  /// tvOS reports a full-screen size while the shell insets the content for
  /// overscan safe area, so `MediaQuery.sizeOf` overstates the drawable width
  /// and every card comes out proportionally too large for the band it sits
  /// in. Prefers a [ShowcaseMetricsScope] installed by the page (which knows
  /// both the LayoutBuilder width and the input axis); the MediaQuery
  /// subtraction is the fallback for callers outside the Showcase page.
  factory ShowcaseMetrics.of(BuildContext c) {
    final scoped =
        c.dependOnInheritedWidgetOfExactType<ShowcaseMetricsScope>();
    if (scoped != null) return scoped.metrics;
    final mq = MediaQuery.of(c);
    final w = mq.size.width - mq.padding.horizontal;
    return ShowcaseMetrics(w > 0 ? w : mq.size.width);
  }

  double get gutter => compact ? w * 0.048 : w * (84 / 1920);
  double get title => compact ? 19.0 : w * (26 / 1920);

  /// Compact: the integrated episode card — 62% of the width, the still on
  /// top and a caption plate inside the same rounded rect. Wide: the 1920-
  /// scale mock table, caption below bare art.
  double get epCell => compact ? w * 0.62 : w * (456 / 1920);
  double get stillW => compact ? epCell : w * (432 / 1920);
  double get stillH => stillW * (243 / 432);
  double get epGap => compact ? w * 0.035 : w * (46 / 1920);

  /// The compact card's caption plate: eyebrow, title, 3-line synopsis,
  /// runtime + kebab footer, plus padding.
  double get epPlate => compact ? 128.0 : 0;

  double get circle => compact ? w * 0.23 : w * (250 / 1920);
  double get castGap => compact ? w * 0.04 : w * (52 / 1920);

  double get srcW => compact ? w * 0.75 : w * (560 / 1920);
  double get srcH => w * (132 / 1920);
  double get srcGap => compact ? w * 0.03 : w * (26 / 1920);

  double get poster => compact ? w * 0.243 : w * (260 / 1920);
  double get posterH => poster * (390 / 260);
  double get posterGap => compact ? w * 0.046 : w * (40 / 1920);

  /// Parents Guide category card (wide rail only — compact renders accordion
  /// rows at full width instead). Fixed on the 960 canvas, like the source
  /// cards — [k]-scaled so a tablet keeps the proportion.
  double get guideW => 170.0 * k;
  double get guideH => 76.0 * k;

  /// Did You Know reading card.
  double get dykW => compact ? w * 0.72 : 250.0 * k;
  double get dykH => compact ? 168.0 : 136.0 * k;
}

/// The page's metrics, computed once by [DetailShowcase] from its
/// LayoutBuilder width and input axis, and read by every band through
/// [ShowcaseMetrics.of].
class ShowcaseMetricsScope extends InheritedWidget {
  final ShowcaseMetrics metrics;

  const ShowcaseMetricsScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  @override
  bool updateShouldNotify(ShowcaseMetricsScope old) =>
      old.metrics.w != metrics.w ||
      old.metrics.compact != metrics.compact ||
      old.metrics.touch != metrics.touch;
}

/// Kept for callers that only need the page margin.
const double kShowcaseGutter = 42;

const _ink = Color(0xFFFFFFFF);

/// The fill of a card slot whose art has not arrived, and of the ambient bed
/// behind the bands.
///
/// These were `0xFF17171A` and `0xFF0A0A0B` written out at eight call sites —
/// which meant the detail page was the surface that ignored the Background
/// setting while everything around it followed. Derived now, from the same
/// ground the rest of the app takes.
///
/// A placeholder is deliberately a STEP off the page rather than the page
/// itself: an empty slot has to read as a slot. Pointing it at the ground would
/// make loading cards dissolve into the background instead of holding their
/// place.
Color _slotFill(AppTheme app) =>
    Color.lerp(app.home.bg, app.core.tx, 0.045)!;

/// A contained mark — a channel logo — needs a lighter plate than a poster
/// slot, or a dark logo lands on a dark card.
Color _plateFill(AppTheme app) =>
    Color.lerp(app.home.bg, app.core.tx, 0.10)!;

/// The bed the ambient field is laid on, and the veil over it.
///
/// **Darkens regardless of the ground, and that is not an oversight.** The
/// field is a bed for WHITE text — every band title, episode caption and
/// synopsis on this page is `_ink`, a hardcoded white — so a veil that followed
/// a pale ground would be a translucent white wash under white type.
///
/// Making it follow properly means the text following the ink first, which is
/// the same outstanding work `kDetailThemesShipped` documents when it withholds
/// `broadsheet` and `concrete`. Until that lands, the honest thing is a bed
/// that keeps its own text readable rather than one that tracks a setting and
/// breaks.
Color _ambientBed(AppTheme app) =>
    Color.lerp(app.home.bg, const Color(0xFF000000), 0.55)!;

TextStyle _t(double size, {FontWeight w = FontWeight.w400, double a = 1}) =>
    TextStyle(
      fontSize: size,
      fontWeight: w,
      color: _ink.withValues(alpha: a),
      height: 1.3,
    );


/// OK/Select/Enter, as a remote sends them.
///
/// `GestureDetector.onTap` never fires for a DPAD, so a focusable built only
/// from a gesture is visible, focusable, and completely inert on a TV.
KeyEventResult _activate(KeyEvent e, VoidCallback? onTap) {
  if (e is! KeyDownEvent || onTap == null) return KeyEventResult.ignored;
  final k = e.logicalKey;
  final isOk = k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.gameButtonA;
  if (!isOk) return KeyEventResult.ignored;
  onTap();
  return KeyEventResult.handled;
}

/// Keeps a focused item inside a lazy horizontal rail on screen — **within
/// that rail**, and nowhere else.
///
/// Without it, walking a rail moves focus into cached off-screen children and
/// then stalls at the first node that was never mounted.
///
/// `Scrollable.ensureVisible` walks every ancestor scrollable, so a cell in a
/// horizontal rail also scrolled the page's vertical list. That fights
/// `_reveal`, which is the only thing that knows where a band should park — and
/// with a full-height identity it would drag the hero off screen the moment
/// anything below it took focus. Scrolling the nearest scrollable only keeps
/// horizontal travel horizontal.
void _keepVisible(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached) return;
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null) return;
  // HORIZONTAL only. The identity's action circles have no rail of their own,
  // so the nearest scrollable is the page itself — and centring a button in the
  // page scrolls the full-height hero away the instant one takes focus. Rails
  // want this; the hero does not.
  if (scrollable.position.axis != Axis.horizontal) return;
  scrollable.position.ensureVisible(
    box,
    alignment: 0.5,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
  );
}

/// Pointer hover for a focusable card, feeding the SAME visual the DPAD
/// cursor gets — the ParallaxFocus lift and any focus plate — so mousing
/// across a rail reads like walking it with a remote.
///
/// Purely visual by design: hover never requests real focus, because focus
/// has side effects here ([_keepVisible]'s rail scroll, the guide band's
/// follow-focus select) and a mouse sweeping across the page must not fire
/// them. Owns its own state so each card only ORs the result in.
class _Hover extends StatefulWidget {
  final Widget Function(BuildContext, bool hovered) builder;

  /// Click for cards a tap activates; basic for the focus-only reading cards
  /// (cast, Did You Know) where a pointer press does nothing.
  final MouseCursor cursor;

  const _Hover({
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    // No hover layer on a television. An Apple TV remote's trackpad delivers
    // pointer events (see main.dart), so an ungated MouseRegion parks a
    // second lifted card wherever the thumb last brushed — and every DPAD
    // step's centre-scroll then sweeps cards under that parked pointer,
    // firing lift/drop springs mid-scroll. The Spotlight board's `hoverable`
    // is off on TV for exactly this reason; this is the same gate.
    if (PlatformUtil.isTelevision) return widget.builder(context, false);
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: widget.builder(context, _h),
    );
  }
}

// ── grounds ────────────────────────────────────────────────────────────────

/// The scrolled ground: the same artwork as a low-frequency colour field.
///
/// Decoded at 32px and scaled up rather than blurred. A real
/// `ImageFilter.blur(sigma: 45)` is a full-resolution Gaussian on every
/// repaint; a 32px decode is the same low-frequency information for
/// effectively nothing, and it is a still image so it repaints only when the
/// URL changes.
class ShowcaseAmbient extends StatelessWidget {
  final String? url;
  final bool visible;

  const ShowcaseAmbient({super.key, required this.url, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const SizedBox.shrink();
    final bed = _ambientBed(AppThemeScope.of(context));
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOut,
      opacity: visible ? 1 : 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.15,
            child: CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              cacheManager: DebrifyImageCache.manager,
              memCacheWidth: 32,
              filterQuality: FilterQuality.low,
              placeholder: (_, __) => ColoredBox(color: bed),
              errorWidget: (_, __, ___) => ColoredBox(color: bed),
            ),
          ),
          // The field is a BED for white text, not a picture. Under a .55 veil
          // the artwork starts competing with the episode titles sitting on it.
          ColoredBox(color: bed.withValues(alpha: 0.58)),
        ],
      ),
    );
  }
}

/// The identity scrim: a 100° left fade, so the text side is dark and the art
/// keeps its right two-thirds.
class ShowcaseBackdropScrim extends StatelessWidget {
  final bool visible;

  /// The ambient trailer is rolling: pull the bed in tight so the video
  /// plays clear, keeping only what text legibility strictly needs — the
  /// same move the home hero makes while its picture rolls. Never true on
  /// TV (the page passes it only when `dpad` is false).
  final bool thinned;

  const ShowcaseBackdropScrim({
    super.key,
    required this.visible,
    this.thinned = false,
  });

  @override
  Widget build(BuildContext context) {
    // Two different jobs on two form factors. Wide: the identity sits at the
    // LEFT, so the bed is a diagonal sweep and the art's right half stays
    // clear. Compact: the identity is a centered stack at the FOOT, and that
    // same diagonal just washes the whole portrait frame grey — the art is
    // narrow, so "68% across" is everything. The phone scrim is vertical: a
    // light cap for the status bar, clear art through the middle, and a bed
    // under the identity text only.
    final compact = ShowcaseMetrics.of(context).compact;
    final gradient = compact
        ? (thinned
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x2E000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x66000000),
                  Color(0xA8000000),
                ],
                stops: [0, 0.14, 0.6, 0.86, 1],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xB3000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.18, 0.42, 0.78, 1],
              ))
        : (thinned
            ? const LinearGradient(
                begin: Alignment(-1, -0.2),
                end: Alignment(1, 0.2),
                colors: [
                  Color(0x9E000000),
                  Color(0x66000000),
                  Color(0x1C000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.26, 0.52, 0.68],
              )
            : const LinearGradient(
                begin: Alignment(-1, -0.2),
                end: Alignment(1, 0.2),
                colors: [
                  Color(0xE0000000),
                  Color(0xA8000000),
                  Color(0x2E000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.26, 0.52, 0.68],
              ));
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 550),
        opacity: visible ? 1 : 0,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
        ),
      ),
    );
  }
}

/// The logo re-forming as a centred header once you descend.
class ShowcaseStickyLogo extends StatelessWidget {
  final String? url;
  final String name;
  final bool visible;

  const ShowcaseStickyLogo({
    super.key,
    required this.url,
    required this.name,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0, -0.25),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: (url == null || url!.isEmpty)
                  ? Text(name, style: _t(17 * m.k, w: FontWeight.w700))
                  : CachedNetworkImage(
                      imageUrl: url!,
                      height: 37 * m.k,
                      fit: BoxFit.contain,
                      cacheManager: DebrifyImageCache.manager,
                      // Decode cap follows the k-scaled display size, or the
                      // one scaled element of the header renders soft.
                      memCacheWidth: (420 * m.k).round(),
                      errorWidget: (_, __, ___) =>
                          Text(name, style: _t(17 * m.k, w: FontWeight.w700)),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── identity ───────────────────────────────────────────────────────────────

/// Chip, logo (or title), meta line with tracker marks, synopsis, tech line,
/// and a row of at most four buttons.
class ShowcaseIdentity extends StatelessWidget {
  final DetailModel model;
  final FocusNode primaryNode;
  final List<FocusNode> actionNodes;
  final VoidCallback onFocused;

  /// The hero's height: one viewport, less however much of the next band is
  /// deliberately left showing.
  ///
  /// Computed by the layout, which is the only place that knows both the real
  /// viewport and which band comes next. It cannot be derived here: a
  /// `LayoutBuilder` inside a vertical list is handed an unbounded height, and
  /// `MediaQuery` is the screen — including the overscan inset this body sits
  /// inside — so both are the wrong number.
  final double height;

  const ShowcaseIdentity({
    super.key,
    required this.model,
    required this.primaryNode,
    required this.actionNodes,
    required this.onFocused,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final m = model;
    final actions = <Widget>[];
    var i = 0;
    FocusNode next() {
      final n = actionNodes[i.clamp(0, actionNodes.length - 1)];
      i++;
      return n;
    }

    if (m.onToggleMyWatchlist != null && actionNodes.isNotEmpty) {
      actions.add(_Circle(
        node: next(),
        icon: m.inMyWatchlist
            ? Icons.bookmark_rounded
            : Icons.bookmark_add_outlined,
        label: m.inMyWatchlist ? 'In Watchlist' : 'Watchlist',
        onTap: m.onToggleMyWatchlist!,
      ));
    }
    if (m.onTrackers != null && actionNodes.isNotEmpty) {
      // The screen assigns Trakt to the primary slot when it is connected;
      // otherwise this callback opens Simkl. Keep the mark coupled to that
      // same rule instead of presenting an ambiguous generic `+`.
      actions.add(_Circle.mark(
        node: next(),
        mark: m.hasTrakt ? const TraktMark() : const SimklMark(),
        label: m.hasTrakt ? 'Trakt' : 'Simkl',
        onTap: m.onTrackers!,
      ));
    }
    if (m.onTrackersSecondary != null && i < actionNodes.length) {
      // The secondary slot only exists when both are connected. Trakt owns
      // the primary slot above, so this callback always opens Simkl.
      actions.add(_Circle.mark(
        node: next(),
        mark: const SimklMark(),
        label: 'Simkl',
        onTap: m.onTrackersSecondary!,
      ));
    }
    if (m.hasTrailer && i < actionNodes.length) {
      actions.add(_Circle(
        node: next(),
        icon: Icons.theaters_rounded,
        label: 'Trailer',
        onTap: m.onTrailer,
      ));
    }
    // The source BROWSE. For a movie: the full searchable list, where a tap
    // plays. For a series: the season-pack search — the same thing the More
    // menu's "Search season packs" row opens, surfaced as its own button.
    // Distinct from the Sources band below, whose cards and "Pin source"
    // tile land on the title-level BINDING manager.
    if (m.onBrowse != null && i < actionNodes.length) {
      actions.add(_Circle(
        node: next(),
        icon: Icons.layers_rounded,
        label: m.isMovie ? 'Sources' : 'Season packs',
        onTap: m.onBrowse!,
      ));
    }
    if (m.onAppMenu != null && i < actionNodes.length) {
      actions.add(_Circle(
        node: next(),
        icon: Icons.more_horiz_rounded,
        label: 'More',
        onTap: m.onAppMenu!,
      ));
    }

    // A FIRST SCREENFUL, not a block in the flow.
    //
    // The reference opens on key art with the identity at its foot and the next
    // row peeking in at the bottom edge — the tell that the page continues. As
    // an ordinary 150-padded block the identity floated in the middle of the
    // art with three rows already visible under it.
    //
    // Sized from the viewport the list actually has (`constraints.maxHeight`),
    // not `MediaQuery`: the body is already inside the overscan `SafeArea`, so
    // the screen height overstates it by the top AND bottom insets and the peek
    // would be pushed off the bottom.
    //
    // Compact: the height is a MINIMUM, not a fix — the centered stack's
    // synopsis expands in place (MORE), and growing the band is the only
    // honest response; a fixed box would overflow.
    final metrics = ShowcaseMetrics.of(context);
    if (metrics.compact) {
      return Container(
        constraints: BoxConstraints(minHeight: height),
        alignment: Alignment.bottomCenter,
        child: _identityColumnCompact(context, m, actions, metrics),
      );
    }
    return SizedBox(
      height: height,
      child: _identityColumn(context, m, actions),
    );
  }

  /// The phone identity — the Apple phone idiom: everything centered and
  /// stacked, synopsis clamped to two lines with an inline MORE.
  Widget _identityColumnCompact(
    BuildContext context,
    DetailModel m,
    List<Widget> actions,
    ShowcaseMetrics metrics,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.gutter, 0, metrics.gutter, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(label: m.isMovie ? 'Film' : 'Series'),
          const SizedBox(height: 9),
          _LogoOrTitle(url: m.logo, name: m.name, centered: true),
          const SizedBox(height: 10),
          _MetaLine(model: m),
          const SizedBox(height: 8),
          if (_hasHonors(m)) ...[
            _HonorsLine(model: m),
            const SizedBox(height: 8),
          ],
          if ((m.synopsis ?? '').isNotEmpty) ...[
            _ExpandableSynopsis(text: m.synopsis!),
            const SizedBox(height: 10),
          ],
          _TechLine(model: m),
          const SizedBox(height: 12),
          // Wrap, not Row: a Resume pill plus four circles can pass 390
          // logical on a long episode code, and a phone identity that
          // overflows sideways is worse than one that wraps.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (m.showPrimary)
                _Primary(
                  node: primaryNode,
                  label: m.primaryLabel,
                  onTap: m.onPrimary,
                  onFocused: onFocused,
                ),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }

  Widget _identityColumn(
    BuildContext context,
    DetailModel m,
    List<Widget> actions,
  ) {
    final metrics = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.gutter, 0, metrics.gutter, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Anchored to the FOOT of the screenful, as the reference is.
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.max,
        children: [
          _Chip(label: m.isMovie ? 'Film' : 'Series'),
          const SizedBox(height: 9),
          _LogoOrTitle(url: m.logo, name: m.name),
          const SizedBox(height: 10),
          _MetaLine(model: m),
          const SizedBox(height: 8),
          if (_hasHonors(m)) ...[
            _HonorsLine(model: m),
            const SizedBox(height: 8),
          ],
          if ((m.synopsis ?? '').isNotEmpty)
            SizedBox(
              width: 410 * metrics.k,
              child: Text(
                m.synopsis!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _t(10.5 * metrics.k, a: 0.74).copyWith(height: 1.42),
              ),
            ),
          const SizedBox(height: 11),
          _TechLine(model: m),
          const SizedBox(height: 11),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.showPrimary)
                _Primary(
                  node: primaryNode,
                  label: m.primaryLabel,
                  onTap: m.onPrimary,
                  onFocused: onFocused,
                ),
              for (final a in actions) ...[const SizedBox(width: 7), a],
            ],
          ),
        ],
      ),
    );
  }
}

class _LogoOrTitle extends StatelessWidget {
  final String? url;
  final String name;

  /// Compact identity centers its whole stack; the logo art follows.
  final bool centered;

  const _LogoOrTitle({
    required this.url,
    required this.name,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final alignment = centered ? Alignment.bottomCenter : Alignment.bottomLeft;
    // Metahub ships some logos as BLACK wordmarks, invisible on ink — roughly
    // one title in four. The text fallback is not a degraded path, it is the
    // other half of the design.
    final text = Text(
      name,
      maxLines: 2,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: centered ? 32 : 39 * m.k,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: _ink,
      ),
    );
    // Keep one stable title-art viewport from the first frame. A loose
    // ConstrainedBox let CachedNetworkImage adopt its placeholder's intrinsic
    // width and then relayout around the decoded logo, which made the wordmark
    // visibly slide into place on slower TVs.
    return SizedBox(
      width: 235 * m.k,
      height: 60 * m.k,
      child: Align(
        alignment: alignment,
        child: (url == null || url!.isEmpty)
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: alignment,
                child: text,
              )
            : CachedNetworkImage(
                imageUrl: url!,
                width: 235 * m.k,
                height: 60 * m.k,
                fit: BoxFit.contain,
                alignment: alignment,
                cacheManager: DebrifyImageCache.manager,
                memCacheWidth: 520,
                placeholder: (_, __) => const SizedBox.expand(),
                errorWidget: (_, __, ___) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: alignment,
                  child: text,
                ),
              ),
      ),
    );
  }
}

/// Two lines + MORE; tapping expands in place (the identity band grows).
/// Collapse comes back with LESS — a one-way expander leaves a wall of text
/// parked over the artwork.
class _ExpandableSynopsis extends StatefulWidget {
  final String text;
  const _ExpandableSynopsis({required this.text});

  @override
  State<_ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<_ExpandableSynopsis> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            maxLines: _open ? null : 2,
            textAlign: TextAlign.center,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: _t(12.5, a: 0.78).copyWith(height: 1.5),
          ),
          const SizedBox(height: 3),
          Text(
            _open ? 'LESS' : 'MORE',
            style: _t(10.5, w: FontWeight.w700, a: 0.9)
                .copyWith(letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4 * m.k),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 7.5 * m.k, vertical: 3.5 * m.k),
        child: Text(label, style: _t(9.5 * m.k, w: FontWeight.w600)),
      ),
    );
  }
}

/// The meta line — and where the trackers live.
///
/// Trakt and Simkl are READOUT here, not buttons: filled when tracked, hollow
/// when not, never focusable. Tracker state describes what a title is to you;
/// it is not an errand you came to the page to run, and a row of verbs is the
/// wrong place for it. The branded tracker buttons open their matching sheet.
class _MetaLine extends StatelessWidget {
  final DetailModel model;

  const _MetaLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final m = model;
    final scale = ShowcaseMetrics.of(context).k;
    final bits = <String>[
      if (m.isMovie) 'Film' else 'Series',
      ...m.genres.take(2),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(bits.join(' · '), style: _t(10.5 * scale, a: 0.86)),
        if (m.rating != null) ...[
          const SizedBox(width: 7),
          _RatingBox(value: m.rating!),
        ],
        if (m.hasTrakt) ...[
          const SizedBox(width: 8),
          _TrackerMark(letter: 'T', on: m.traktTracked, tint: const Color(0xFFED1C24)),
        ],
        if (m.hasSimkl) ...[
          const SizedBox(width: 5),
          _TrackerMark(letter: 'S', on: m.simklTracked, tint: const Color(0xFF0B87C4)),
        ],
      ],
    );
  }
}

class _TrackerMark extends StatelessWidget {
  final String letter;
  final bool on;
  final Color tint;

  const _TrackerMark({required this.letter, required this.on, required this.tint});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Container(
      width: 15 * k,
      height: 15 * k,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? tint : null,
        border: on
            ? null
            : Border.all(color: _ink.withValues(alpha: 0.34), width: 0.75),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 7 * k,
          fontWeight: FontWeight.w800,
          color: on ? _ink : _ink.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _RatingBox extends StatelessWidget {
  final double value;

  const _RatingBox({required this.value});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 3 * k, vertical: 0.5 * k),
      decoration: BoxDecoration(
        border: Border.all(color: _ink.withValues(alpha: 0.45), width: 0.75),
        borderRadius: BorderRadius.circular(2.5 * k),
      ),
      child:
          Text('★ ${value.toStringAsFixed(1)}', style: _t(7.5 * k, a: 0.9)),
    );
  }
}

bool _hasHonors(DetailModel m) =>
    m.imdbExtra?.top250Rank != null || m.imdbExtra?.meterRank != null;

/// The honors row — IMDb Top 250 position and the popularity meter, as
/// hairline small-caps chips in the family of [_RatingBox]. Readout, never
/// focusable; monochrome so it sits under the artwork instead of on top of it.
class _HonorsLine extends StatelessWidget {
  final DetailModel model;

  const _HonorsLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final x = model.imdbExtra;
    if (x == null) return const SizedBox.shrink();
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    final chips = <Widget>[
      if (x.top250Rank != null)
        _honorChip(m, 'IMDb TOP 250', '№${x.top250Rank}'),
      if (x.meterRank != null)
        _honorChip(
          m,
          'TRENDING',
          '№${x.meterRank}',
          drift: switch (x.meterDelta) {
            null || 0 => null,
            final d when d > 0 => '▴$d',
            final d => '▾${-d}',
          },
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: compact ? WrapAlignment.center : WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Widget _honorChip(ShowcaseMetrics m, String label, String rank,
      {String? drift}) {
    final compact = m.compact;
    final size = compact ? 9.5 : 7.5 * m.k;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 6 * m.k,
        vertical: compact ? 3.5 : 2.5 * m.k,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: _ink.withValues(alpha: 0.30), width: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: _t(size, w: FontWeight.w700, a: 0.62)
                .copyWith(letterSpacing: 0.8),
          ),
          Text(
            rank,
            style: _t(size, w: FontWeight.w700, a: 0.95)
                .copyWith(letterSpacing: 0.4),
          ),
          if (drift != null)
            Text(
              ' $drift',
              style: _t(size, w: FontWeight.w700, a: 0.45),
            ),
        ],
      ),
    );
  }
}

/// Year · seasons/runtime. NOT Dolby/CC/HDR badges: nothing is fetched at page
/// open, so those could only ever be decoration pretending to be data.
class _TechLine extends StatelessWidget {
  final DetailModel model;

  const _TechLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final bits = <String>[
      if ((model.year ?? '').isNotEmpty) model.year!,
      if ((model.runtime ?? '').isNotEmpty) model.runtime!,
      if ((model.certificate ?? '').isNotEmpty) model.certificate!,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return Text(bits.join('  ·  '),
        style: _t(9.5 * ShowcaseMetrics.of(context).k, a: 0.7));
  }
}

class _Primary extends StatefulWidget {
  final FocusNode node;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onFocused;

  const _Primary({
    required this.node,
    required this.label,
    required this.onTap,
    required this.onFocused,
  });

  @override
  State<_Primary> createState() => _PrimaryState();
}

class _PrimaryState extends State<_Primary> {
  bool _f = false;

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: widget.node,
        autofocus: true,
        onFocusChange: (v) {
          setState(() => _f = v);
          if (v) widget.onFocused();
        },
        // By key IDENTITY, not by keyLabel string — a remote's Select has no
        // label to match and would silently never activate.
        onKeyEvent: (_, e) => _activate(e, widget.onTap),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Builder(builder: (context) {
            // TV draws at the mock's 960-canvas numbers (k = 1); a wide touch
            // surface scales them back to proportion, and a phone needs a real
            // finger target and the phone type ramp — the Apple reference
            // pill is 42pt with 15pt text, and SOLID white at rest (there is
            // no focus state to flip through on touch).
            final m = ShowcaseMetrics.of(context);
            final compact = m.compact;
            final solid = _f || compact;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: compact ? 44 : 30 * m.k,
              padding:
                  EdgeInsets.symmetric(horizontal: compact ? 24 : 17 * m.k),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // The focus flip: ghost at rest, SOLID WHITE on black when
                // focused. The reference's primary is the one thing that does
                // not merely lift.
                color: solid ? _ink : _ink.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(compact ? 22 : 15 * m.k),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: compact ? 20 : 14 * m.k,
                    color: solid ? Colors.black : _ink,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: compact ? 15 : 10.5 * m.k,
                      fontWeight: FontWeight.w600,
                      color: solid ? Colors.black : _ink,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      );
}

class _Circle extends StatefulWidget {
  final FocusNode node;
  final IconData? icon;
  final Widget? mark;
  final String label;
  final VoidCallback onTap;

  const _Circle({
    required this.node,
    required IconData this.icon,
    required this.label,
    required this.onTap,
  }) : mark = null;

  const _Circle.mark({
    required this.node,
    required Widget this.mark,
    required this.label,
    required this.onTap,
  }) : icon = null;

  @override
  State<_Circle> createState() => _CircleState();
}

class _CircleState extends State<_Circle> {
  bool _f = false;
  bool _h = false;

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: widget.node,
        onFocusChange: (v) {
          setState(() => _f = v);
          if (v) _keepVisible(context);
        },
        // Without this the tracker, trailer and More buttons focus correctly
        // and do NOTHING on a remote.
        onKeyEvent: (_, e) => _activate(e, widget.onTap),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _h = true),
          onExit: (_) => setState(() => _h = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Builder(builder: (context) {
              final m = ShowcaseMetrics.of(context);
              final compact = m.compact;
              final d = compact ? 44.0 : 26.0 * m.k;
              // Hover and focus both light the pill: DPAD/keyboard land on
              // `_f`, a desktop pointer on `_h` — same treatment either way.
              final lit = _f || _h;
              final glyph = widget.mark ??
                  Icon(
                    widget.icon,
                    size: compact ? 20 : 13 * m.k,
                    color: lit ? Colors.black : _ink,
                  );
              // Lit (non-compact): the circle stretches into a pill that
              // names itself — the tooltip a DPAD user can actually read.
              // Compact stays a plain circle — touch has no dwell, and a pill
              // popping under a finger would just shove its siblings — so it
              // falls back to the platform's long-press Tooltip below.
              final labelled = lit && !compact;
              final body = AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: d,
                decoration: BoxDecoration(
                  color: lit ? _ink : _ink.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(d / 2),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  child: labelled
                      ? Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 10 * m.k),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              glyph,
                              SizedBox(width: 6 * m.k),
                              Text(
                                widget.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11 * m.k,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SizedBox(
                          width: d,
                          height: d,
                          child: Center(child: glyph),
                        ),
                ),
              );
              if (!compact) return body;
              return Tooltip(
                message: widget.label,
                triggerMode: TooltipTriggerMode.longPress,
                child: body,
              );
            }),
          ),
        ),
      );
}

// ── seasons ────────────────────────────────────────────────────────────────

class ShowcaseSeasons extends StatelessWidget {
  final EpisodesPanelView view;
  final List<FocusNode> nodes;

  const ShowcaseSeasons({super.key, required this.view, required this.nodes});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    // Compact: one pill + an anchored popup — Apple's phone idiom, measured
    // off the reference (no scrim, no sheet, the page stays live behind it).
    // The band carries exactly ONE node then, supplied by the layout.
    if (m.compact) {
      return Padding(
        padding: EdgeInsets.only(left: m.gutter, right: m.gutter, top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _SeasonDropdown(view: view, node: nodes.first),
        ),
      );
    }
    return SizedBox(
      height: 34 * m.k,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: view.seasons.length,
        separatorBuilder: (_, __) => SizedBox(width: 7 * m.k),
        itemBuilder: (context, i) {
          final s = view.seasons[i];
          final active = s.number == view.selectedSeasonNumber;
          return _SeasonPill(
            node: nodes[i],
            label: 'Season ${s.number}',
            active: active,
            onTap: () => view.selectSeason(s.number),
          );
        },
      ),
    );
  }
}

/// The compact season control: a tinted pill that opens an anchored popup
/// menu at its own position. `showMenu` supplies the parts a hand-rolled
/// overlay always forgets — outside-tap dismissal, Escape/Back, viewport-edge
/// repositioning, an internal scroll past ~8 seasons — and returns focus to
/// the anchor's route when it closes.
class _SeasonDropdown extends StatefulWidget {
  final EpisodesPanelView view;
  final FocusNode node;

  const _SeasonDropdown({required this.view, required this.node});

  @override
  State<_SeasonDropdown> createState() => _SeasonDropdownState();
}

class _SeasonDropdownState extends State<_SeasonDropdown> {
  bool _f = false;

  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 6,
        overlay.size.width - origin.dx - 220,
        0,
      ),
      color: const Color(0xFF1B1B1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 200, maxHeight: 380),
      items: [
        for (final s in widget.view.seasons)
          PopupMenuItem<int>(
            value: s.number,
            child: Text(
              'Season ${s.number}',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: s.number == widget.view.selectedSeasonNumber
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: s.number == widget.view.selectedSeasonNumber
                    ? AppThemeScope.of(context).core.accent
                    : Colors.white,
              ),
            ),
          ),
      ],
    );
    if (selected != null) widget.view.selectSeason(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) => _activate(e, _open),
      child: GestureDetector(
        onTap: _open,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _ink.withValues(alpha: _f ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Season ${widget.view.selectedSeasonNumber}',
                style: _t(14, w: FontWeight.w600),
              ),
              const SizedBox(width: 7),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 17, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonPill extends StatefulWidget {
  final FocusNode node;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SeasonPill({
    required this.node,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SeasonPill> createState() => _SeasonPillState();
}

class _SeasonPillState extends State<_SeasonPill> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      // Selecting on FOCUS would reload the episode list on every step of a
      // walk across the seasons. OK commits; the walk is free.
      onKeyEvent: (_, e) => _activate(e, widget.onTap),
      // The wide row is what every TOUCH tablet gets (compact swaps in the
      // dropdown below 600), so the pill needs a finger path too — OK-only
      // left the season control dead under a finger. Opaque: the pill draws
      // no background until it is focused or active, and a bare DecoratedBox
      // defers the hit test to the Text, so the padding would miss.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ParallaxFocus(
          focused: _f,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(12.5 * k),
          child: Container(
            height: 25 * k,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: 15 * k),
            decoration: BoxDecoration(
              color: (_f || widget.active)
                  ? _ink.withValues(alpha: _f ? 0.28 : 0.18)
                  : null,
              borderRadius: BorderRadius.circular(12.5 * k),
            ),
            child: Text(
              widget.label,
              style: _t(12.5 * k,
                  w: FontWeight.w600, a: widget.active || _f ? 1 : 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

// ── episodes ───────────────────────────────────────────────────────────────

/// The still, then the caption BELOW it — and the focused cell gets a plate
/// behind the whole thing, still and text together.
class ShowcaseEpisodeCell extends StatelessWidget {
  final TraktEpisode episode;
  final double? cellWidth;
  final double? stillWidth;
  final double? stillHeight;
  final bool focused;
  final double? progress;
  final bool isNext;
  final String? fallbackImage;

  /// Touch/pointer surfaces only: a visible ⋮ over the still, the discoverable
  /// stand-in for hold-OK. TV passes null and renders exactly as before.
  final VoidCallback? onOptions;

  const ShowcaseEpisodeCell({
    super.key,
    required this.episode,
    required this.focused,
    required this.progress,
    required this.isNext,
    required this.fallbackImage,
    this.cellWidth,
    this.stillWidth,
    this.stillHeight,
    this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress ?? 0;
    final watched = p >= 100;
    final url = episode.thumbnailUrl ?? fallbackImage;

    final m = ShowcaseMetrics.of(context);
    // The plate goes behind the CAPTION, not around the whole cell.
    //
    // A fill around everything sits behind the still too, where it is invisible
    // under the artwork and only shows as a hairline margin — so the focused
    // cell read as barely distinguishable. In the reference the still carries
    // focus by lifting, and the caption below it gains a filled card. Splitting
    // them lets each do its own job.
    final slot = _slotFill(AppThemeScope.of(context));
    return SizedBox(
      width: cellWidth ?? m.epCell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ParallaxFocus(
            focused: focused,
            shape: ParallaxShape.episodeStill,
            radius: BorderRadius.circular(6),
            child: SizedBox(
              width: stillWidth ?? m.stillW,
              height: stillHeight ?? m.stillH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url != null && url.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        cacheManager: DebrifyImageCache.manager,
                        memCacheWidth: 500,
                        placeholder: (_, __) =>
                            ColoredBox(color: slot),
                        errorWidget: (_, __, ___) =>
                            ColoredBox(color: slot),
                      )
                    else
                      ColoredBox(color: slot),
                    if (watched)
                      ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                    if (isNext && !watched)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _Badge(label: 'UP NEXT'),
                      ),
                    if (watched)
                      const Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(Icons.check_rounded,
                            size: 13, color: Colors.white),
                      ),
                    if (p > 0 && p < 100)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: p / 100,
                          minHeight: 2,
                          backgroundColor: Colors.black.withValues(alpha: 0.4),
                          valueColor:
                              const AlwaysStoppedAnimation(Color(0xFFFFFFFF)),
                        ),
                      ),
                    if ((episode.runtime ?? 0) > 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: _Badge(label: '▶ ${episode.runtime}m'),
                      ),
                    if (onOptions != null)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: _KebabButton(onTap: onOptions!),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            // Padded on BOTH states, so gaining the plate does not shift the
            // text sideways — only its ground appears.
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            decoration: BoxDecoration(
              color: focused ? _ink.withValues(alpha: 0.13) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rating rides the eyebrow in the same small-caps monochrome
                // grammar (the _SeverityMark rule: no colored chips against
                // the artwork). Trakt backfills ratings addons omit — see
                // EpisodesPanel._enrichEpisodeRatings — and 0 means unrated.
                Text(
                    (episode.rating ?? 0) > 0
                        ? 'EPISODE ${episode.number} · ★ '
                            '${episode.rating!.toStringAsFixed(1)}'
                        : 'EPISODE ${episode.number}',
                    style:
                        _t(9.5 * m.k, a: 0.55).copyWith(letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(12.5 * m.k, w: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 29 * m.k,
                  child: Text(
                    episode.overview ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _t(10.5 * m.k, a: 0.6).copyWith(height: 1.36),
                  ),
                ),
                if ((episode.firstAired ?? '').isNotEmpty)
                  Text(episode.firstAired!.split('T').first,
                      style: _t(9.5 * m.k, a: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact episode card — one integrated rounded rect: still on top,
/// caption plate inside the same card (eyebrow, title, three-line synopsis,
/// runtime + kebab). The measured Apple phone idiom: ~62% of the width, next
/// card peeking. Tap-to-play and the focus lift are supplied by the
/// `DetailEpisodeInteraction` wrapper, exactly as for the wide cell.
class ShowcaseEpisodeCardCompact extends StatelessWidget {
  final TraktEpisode episode;
  final bool focused;
  final double? progress;
  final bool isNext;
  final String? fallbackImage;
  final VoidCallback onOptions;

  const ShowcaseEpisodeCardCompact({
    super.key,
    required this.episode,
    required this.focused,
    required this.progress,
    required this.isNext,
    required this.fallbackImage,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final app = AppThemeScope.of(context);
    final p = progress ?? 0;
    final watched = p >= 100;
    final url = episode.thumbnailUrl ?? fallbackImage;
    final slot = _slotFill(app);

    return ParallaxFocus(
      focused: focused,
      shape: ParallaxShape.episodeStill,
      radius: BorderRadius.circular(12),
      child: SizedBox(
        width: m.epCell,
        height: m.stillH + m.epPlate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No card fill: still + caption sit straight on the page, the
            // wide/TV cell's anatomy (user call 2026-08-16 — the solid
            // integrated card read as a foreign object on a board where
            // every other surface is the page). The still carries its own
            // full rounded clip now; under the old whole-card clip its
            // bottom corners were squared off against the plate below.
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: m.epCell,
                height: m.stillH,
                child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null && url.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      memCacheWidth: 500,
                      placeholder: (_, __) => ColoredBox(color: slot),
                      errorWidget: (_, __, ___) => ColoredBox(color: slot),
                    ),
                  if (watched)
                    ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                  if (isNext && !watched)
                    Positioned(
                      left: 7,
                      top: 7,
                      child: _Badge(label: 'UP NEXT'),
                    ),
                  if (watched)
                    const Positioned(
                      right: 7,
                      top: 7,
                      child: Icon(Icons.check_rounded,
                          size: 14, color: Colors.white),
                    ),
                  if (p > 0 && p < 100)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: p / 100,
                        minHeight: 3,
                        backgroundColor:
                            Colors.black.withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation(app.core.accent),
                      ),
                    ),
                ],
                ),
              ),
            ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                // The wide/TV cell's answer to focus, echoed here for the
                // scroll-settled card: the caption gains an ink plate while
                // the still lifts. Padded identically in BOTH states so
                // gaining the plate never shifts the text — only its ground
                // appears (the wide cell's own rule).
                decoration: BoxDecoration(
                  color: focused ? _ink.withValues(alpha: 0.13) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                // Near-flush with the still's edge — page text, not card
                // text, now that the resting fill is gone.
                padding: const EdgeInsets.fromLTRB(8, 9, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EPISODE ${episode.number}',
                      style: _t(10, a: 0.5).copyWith(letterSpacing: 0.9),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(14.5, w: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      // Whole lines only. maxLines guards the HORIZONTAL
                      // overflow of the last permitted line — it does nothing
                      // about the box being 2.6 line-heights tall, which
                      // sliced the third line through its middle. Fit the
                      // line count to the height that actually exists
                      // (text-scale aware), and the last line ends in an
                      // ellipsis instead of a crop.
                      child: LayoutBuilder(
                        builder: (context, c) {
                          const fs = 11.5;
                          final line =
                              MediaQuery.textScalerOf(context).scale(fs) * 1.4;
                          final lines =
                              (c.maxHeight / line).floor().clamp(1, 3);
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              episode.overview ?? '',
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  _t(fs, a: 0.55).copyWith(height: 1.4),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        if ((episode.runtime ?? 0) > 0) ...[
                          const Icon(Icons.play_arrow_rounded,
                              size: 13, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text('${episode.runtime}m', style: _t(11.5, a: 0.7)),
                        ] else if ((episode.firstAired ?? '').isNotEmpty)
                          Text(episode.firstAired!.split('T').first,
                              style: _t(11.5, a: 0.5)),
                        // Same monochrome footer grammar as the runtime.
                        if ((episode.rating ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Text('★ ${episode.rating!.toStringAsFixed(1)}',
                              style: _t(11.5, a: 0.7)),
                        ],
                        const Spacer(),
                        _KebabButton(onTap: onOptions),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The visible stand-in for hold-OK on touch surfaces: ⋮ with a real finger
/// target behind a small glyph.
class _KebabButton extends StatelessWidget {
  final VoidCallback onTap;
  const _KebabButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.all(6 * k),
        child:
            Icon(Icons.more_vert_rounded, size: 17 * k, color: Colors.white70),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(3.5 * k),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 5 * k, vertical: 2 * k),
        child: Text(label, style: _t(9.5 * k)),
      ),
    );
  }
}

// ── cast ───────────────────────────────────────────────────────────────────

class ShowcaseCast extends StatelessWidget {
  final List<CastMember> cast;
  final List<FocusNode> nodes;

  const ShowcaseCast({super.key, required this.cast, required this.nodes});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return _Band(
      title: 'Cast & Crew',
      height: m.circle * 1.08 + 46 * m.k,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: cast.length,
        separatorBuilder: (_, __) => SizedBox(width: m.castGap),
        itemBuilder: (context, i) => _CastTile(
          member: cast[i],
          node: nodes[i],
          size: m.circle,
        ),
      ),
    );
  }
}

class _CastTile extends StatefulWidget {
  final CastMember member;
  final FocusNode node;
  final double size;

  const _CastTile({
    required this.member,
    required this.node,
    required this.size,
  });

  @override
  State<_CastTile> createState() => _CastTileState();
}

class _CastTileState extends State<_CastTile> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final url = widget.member.imageUrl;
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      // Basic cursor: a cast tile is ambient reading — SELECT and tap do
      // nothing — but the lift still answers "am I on this one".
      child: _Hover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => SizedBox(
          width: widget.size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ParallaxFocus(
                focused: _f || hovered,
                shape: ParallaxShape.castCircle,
                radius: BorderRadius.circular(widget.size / 2),
                child: ClipOval(
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: (url != null && url.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            cacheManager: DebrifyImageCache.manager,
                            memCacheWidth: 260,
                            placeholder: (_, __) =>
                                const ColoredBox(color: Color(0xFF4A4A55)),
                            errorWidget: (_, __, ___) =>
                                const ColoredBox(color: Color(0xFF4A4A55)),
                          )
                        : const ColoredBox(color: Color(0xFF4A4A55)),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                widget.member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _t(12.5 * k),
              ),
              if ((widget.member.character ?? '').isNotEmpty)
                Text(
                  widget.member.character!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _t(11.5 * k, a: 0.55),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── sources ────────────────────────────────────────────────────────────────

/// The Sources band — this page's "How to Watch".
///
/// Painted from BOUND sources, which are a SharedPreferences read, so the band
/// costs no network on open. Bind stops being a mystery button in the identity
/// row and becomes an action on the card it applies to.
class ShowcaseSources extends StatelessWidget {
  final List<SeriesSource> sources;
  final List<FocusNode> nodes;
  final VoidCallback? onOpen;

  /// The full browse/search source list (movies: a tap there PLAYS) or the
  /// season-pack search (series). When non-null the band gets a second entry
  /// card after "Pin source", and the layout supplies one extra node —
  /// topology always matches rendering.
  final VoidCallback? onBrowseAll;

  /// What that second entry card says — the layout words it per type,
  /// because a series' browse lands on the pack search, not "all sources".
  final String browseAllLabel;

  const ShowcaseSources({
    super.key,
    required this.sources,
    required this.nodes,
    required this.onOpen,
    this.onBrowseAll,
    this.browseAllLabel = '⌕  Browse all',
  });

  @override
  Widget build(BuildContext context) => _Band(
        title: 'Sources',
        height: 96 * ShowcaseMetrics.of(context).k,
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
              horizontal: ShowcaseMetrics.of(context).gutter),
          itemCount: sources.length + 1 + (onBrowseAll != null ? 1 : 0),
          separatorBuilder: (_, __) =>
              SizedBox(width: ShowcaseMetrics.of(context).srcGap),
          itemBuilder: (context, i) {
            if (i == sources.length) {
              return _SourceCard(
                node: nodes[i],
                onTap: onOpen,
                add: true,
              );
            }
            if (i == sources.length + 1) {
              return _SourceCard(
                node: nodes[i],
                onTap: onBrowseAll,
                add: true,
                addLabel: browseAllLabel,
              );
            }
            return _SourceCard(
              node: nodes[i],
              onTap: onOpen,
              source: sources[i],
            );
          },
        ),
      );
}

class _SourceCard extends StatefulWidget {
  final FocusNode node;
  final SeriesSource? source;
  final bool add;

  /// The add-style card's label. Defaults to the binding manager's wording —
  /// a tap there PINS a source to the title, it doesn't play one, so the tile
  /// says "Pin source"; "Find sources" oversold it as a search.
  final String addLabel;
  final VoidCallback? onTap;

  const _SourceCard({
    required this.node,
    required this.onTap,
    this.source,
    this.add = false,
    this.addLabel = '＋  Pin source',
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final mm = ShowcaseMetrics.of(context);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      onKeyEvent: (_, e) => _activate(e, widget.onTap),
      child: _Hover(
        builder: (context, hovered) => GestureDetector(
          onTap: widget.onTap,
          // Same reason as `_Poster`: the Sources band is 96 tall to leave
          // the lift room, and the tight cross-axis constraint would stretch
          // this 66pt card to fill it.
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              shape: ParallaxShape.sourceCard,
              radius: BorderRadius.circular(7 * mm.k),
              child: Container(
                // Wide keeps the shipped 280/150 (k-scaled off TV); compact
                // grows the bound card to 75% of the width (the mock's
                // source card) and the add chip a touch for fingers.
                width: () {
                  if (!mm.compact) {
                    return (widget.add ? 150.0 : 280.0) * mm.k;
                  }
                  return widget.add ? 160.0 : mm.srcW;
                }(),
                height: 66 * mm.k,
                padding: EdgeInsets.symmetric(
                    horizontal: 10 * mm.k, vertical: 9 * mm.k),
                decoration: BoxDecoration(
                  color: widget.add ? null : _ink.withValues(alpha: 0.07),
                  border: Border.all(
                    color: _ink.withValues(alpha: widget.add ? 0.22 : 0.09),
                  ),
                  borderRadius: BorderRadius.circular(7 * mm.k),
                ),
                child: widget.add
                    ? Center(
                        child: Text(widget.addLabel,
                            style: _t(10.5 * mm.k, a: 0.66)),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  s?.torrentName ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(10.5 * mm.k, w: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s?.debridService ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(9.5 * mm.k, a: 0.58),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── more like this ─────────────────────────────────────────────────────────

class ShowcaseRecs extends StatelessWidget {
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final void Function(StremioMeta)? onTap;

  const ShowcaseRecs({
    super.key,
    required this.items,
    required this.nodes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return _Band(
      title: 'More Like This',
      height: m.posterH * 1.10 + 24,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: m.posterGap),
        itemBuilder: (context, i) => _Poster(
          item: items[i],
          node: nodes[i],
          onTap: onTap,
          width: m.poster,
          height: m.posterH,
        ),
      ),
    );
  }
}

class _Poster extends StatefulWidget {
  final StremioMeta item;
  final FocusNode node;
  final void Function(StremioMeta)? onTap;
  final double width;
  final double height;

  const _Poster({
    required this.item,
    required this.node,
    required this.onTap,
    required this.width,
    required this.height,
  });

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final url = widget.item.poster;
    final slot = _slotFill(AppThemeScope.of(context));
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      onKeyEvent: (_, e) => _activate(e, () => widget.onTap?.call(widget.item)),
      child: _Hover(
        builder: (context, hovered) => GestureDetector(
          onTap: () => widget.onTap?.call(widget.item),
          // The band is taller than the card so the lift has somewhere to go,
          // and a horizontal ListView constrains its children to that height
          // TIGHTLY — without an Align the poster is stretched to the band
          // while its width stays `m.poster`, drawing a 2:3 poster at about
          // 0.53:1.
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              radius: BorderRadius.circular(7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: (url != null && url.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          memCacheWidth: 300,
                          placeholder: (_, __) => ColoredBox(color: slot),
                          errorWidget: (_, __, ___) => ColoredBox(color: slot),
                        )
                      : ColoredBox(color: slot),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── parents guide ──────────────────────────────────────────────────────────

List<ParentsGuideItem> _plainOf(ParentsGuideCategory c) =>
    [for (final i in c.items) if (!i.isSpoiler) i];

List<ParentsGuideItem> _spoilersOf(ParentsGuideCategory c) =>
    [for (final i in c.items) if (i.isSpoiler) i];

/// Severity level for the four-segment meter. Unknown wordings render the
/// word with an empty meter rather than guessing a level.
int _severityLevel(String severity) => switch (severity.toLowerCase()) {
      'none' => 1,
      'mild' => 2,
      'moderate' => 3,
      'severe' => 4,
      _ => 0,
    };

/// Small-caps severity word plus the segment meter — monochrome, per the
/// approved mock: no traffic-light chips against the artwork.
class _SeverityMark extends StatelessWidget {
  final String severity;

  const _SeverityMark({required this.severity});

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    final level = _severityLevel(severity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          severity.toUpperCase(),
          style: _t(compact ? 9.5 : 7.5 * m.k, w: FontWeight.w700, a: 0.6)
              .copyWith(letterSpacing: 1.0),
        ),
        SizedBox(width: compact ? 8 : 6 * m.k),
        for (var i = 1; i <= 4; i++) ...[
          Container(
            width: compact ? 10 : 8 * m.k,
            height: compact ? 3.5 : 3 * m.k,
            decoration: BoxDecoration(
              color: _ink.withValues(alpha: i <= level ? 0.88 : 0.16),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 4) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

/// The Parents Guide band — one focus node per category, exactly.
///
/// Wide: a rail of category cards with a plate below that FOLLOWS the
/// selected card (focus on DPAD, tap on pointer) — the season rail's
/// follow-focus pattern. SELECT on the selected card toggles that category's
/// spoiler entries, so expansion never changes the node count.
///
/// Compact: the same categories as full-width accordion rows in the
/// integrated-card style, tap to expand.
///
/// Spoiler entries are WITHHELD, not blurred: a live blur is a per-frame
/// raster cost the Android TV GLES2 path cannot afford, and unrendered text
/// is also the only spoiler treatment that can't be defeated by a screenshot
/// mid-fade. Selection and spoiler state live HERE, not in the layout — the
/// layout owns only the nodes, which is all the DPAD ladder needs.
class ShowcaseGuide extends StatefulWidget {
  final ParentsGuideResult guide;
  final List<FocusNode> nodes;
  final Color accent;

  const ShowcaseGuide({
    super.key,
    required this.guide,
    required this.nodes,
    required this.accent,
  });

  @override
  State<ShowcaseGuide> createState() => _ShowcaseGuideState();
}

class _ShowcaseGuideState extends State<ShowcaseGuide> {
  int _sel = 0;

  /// Wide: spoilers revealed for the SELECTED category; reset on move.
  bool _spoilers = false;

  /// Compact: the one expanded row (-1 none) and its per-category reveals.
  int _open = -1;
  final Set<int> _openSpoilers = {};

  List<ParentsGuideCategory> get _cats => widget.guide.categories;

  @override
  void didUpdateWidget(ShowcaseGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selection, expansion and spoiler reveals are all INDEX-keyed. A new
    // guide result (the screen re-fetching for a different title, or a
    // reload) renumbers the categories, and carried-over state would reveal
    // the wrong category's spoilers.
    if (!identical(oldWidget.guide, widget.guide)) {
      // Follow LIVE focus, not a blind 0: if a card holds focus through the
      // swap, plate and SELECT must keep describing THAT card.
      final focused = widget.nodes.indexWhere((n) => n.hasFocus);
      _sel = focused >= 0 ? focused.clamp(0, _cats.length - 1) : 0;
      _spoilers = false;
      _open = -1;
      _openSpoilers.clear();
    }
  }

  void _select(int i) {
    if (_sel == i) return;
    setState(() {
      _sel = i;
      _spoilers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    if (_cats.isEmpty) return const SizedBox.shrink();
    return m.compact ? _compact(context, m) : _wide(context, m);
  }

  // ── wide: card rail + follow-focus plate ─────────────────────────────────

  Widget _wide(BuildContext context, ShowcaseMetrics m) {
    final sel = _sel.clamp(0, _cats.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Band(
          title: 'Parents Guide',
          height: m.guideH * 1.12 + 18,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: m.gutter),
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _GuideCard(
              category: _cats[i],
              node: widget.nodes[i],
              selected: i == sel,
              onSelect: () => _select(i),
              // SELECT on the focused card: reveal/hide that category's
              // spoilers. Null when there are none, so OK stays inert.
              onOk: _spoilersOf(_cats[i]).isNotEmpty
                  ? () => setState(() => _spoilers = !_spoilers)
                  : null,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(m.gutter, 4, m.gutter, 0),
          child: _plate(context, _cats[sel]),
        ),
      ],
    );
  }

  Widget _plate(BuildContext context, ParentsGuideCategory cat) {
    final k = ShowcaseMetrics.of(context).k;
    final spoilers = _spoilersOf(cat);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.055),
        border: Border.all(color: _ink.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(cat.label, style: _t(11.5 * k, w: FontWeight.w700)),
              const SizedBox(width: 10),
              _SeverityMark(severity: cat.severity),
              const Spacer(),
              if (cat.totalVotes > 0)
                Text(
                  '${cat.severityVotes} of ${cat.totalVotes} rated '
                  '${cat.severity.toLowerCase()}',
                  style: _t(8.5 * k, a: 0.4),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in _plainOf(cat)) _entry(item.text, 10.0 * k),
          if (_spoilers)
            for (final item in spoilers) _entry(item.text, 10.0 * k),
          if (spoilers.isNotEmpty) _spoilerRow(spoilers.length, _spoilers, () {
            setState(() => _spoilers = !_spoilers);
          }),
        ],
      ),
    );
  }

  Widget _entry(String text, double size) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: size * 0.55),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: _ink.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: _t(size, a: 0.78).copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _spoilerRow(int count, bool shown, VoidCallback onToggle) {
    final m = ShowcaseMetrics.of(context);
    final compact = m.compact;
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '$count spoiler ${count == 1 ? 'entry' : 'entries'} '
              '${shown ? 'shown' : 'hidden'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(compact ? 11 : 8.5 * m.k, a: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          // A pill, not a node: on DPAD the toggle is SELECT on the focused
          // card; on touch this is the tap target. The accent's one
          // appearance in the band, per the mock.
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 11 : 9 * m.k,
                vertical: compact ? 4 : 2.5 * m.k,
              ),
              decoration: BoxDecoration(
                border:
                    Border.all(color: _ink.withValues(alpha: 0.24)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                shown ? 'HIDE' : 'SHOW',
                style: TextStyle(
                  fontSize: compact ? 10 : 7.5 * m.k,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: widget.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── compact: accordion rows ──────────────────────────────────────────────

  Widget _compact(BuildContext context, ShowcaseMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.only(left: m.gutter, bottom: 10),
          child: Text('Parents Guide',
              style: _t(19, w: FontWeight.w600, a: 0.84)),
        ),
        for (var i = 0; i < _cats.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(m.gutter, 0, m.gutter, 8),
            child: _accordionRow(context, i),
          ),
      ],
    );
  }

  Widget _accordionRow(BuildContext context, int i) {
    final cat = _cats[i];
    final open = _open == i;
    final spoilers = _spoilersOf(cat);
    final spoilersShown = _openSpoilers.contains(i);
    return Focus(
      focusNode: widget.nodes[i],
      onKeyEvent: (_, e) =>
          _activate(e, () => setState(() => _open = open ? -1 : i)),
      child: GestureDetector(
        onTap: () => setState(() => _open = open ? -1 : i),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _ink.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(cat.label,
                        style: _t(14, w: FontWeight.w600)),
                  ),
                  _SeverityMark(severity: cat.severity),
                  const SizedBox(width: 10),
                  Text(open ? '▲' : '▼', style: _t(10, a: 0.4)),
                ],
              ),
              if (open) ...[
                if (cat.totalVotes > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      '${cat.severityVotes} of ${cat.totalVotes} rated '
                      '${cat.severity.toLowerCase()}',
                      style: _t(10.5, a: 0.38),
                    ),
                  ),
                const SizedBox(height: 2),
                for (final item in _plainOf(cat)) _entry(item.text, 12.5),
                if (spoilersShown)
                  for (final item in spoilers) _entry(item.text, 12.5),
                if (spoilers.isNotEmpty)
                  _spoilerRow(spoilers.length, spoilersShown, () {
                    setState(() {
                      if (!_openSpoilers.add(i)) _openSpoilers.remove(i);
                    });
                  }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One wide-tier category card: title, severity mark, entry count.
class _GuideCard extends StatefulWidget {
  final ParentsGuideCategory category;
  final FocusNode node;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onOk;

  const _GuideCard({
    required this.category,
    required this.node,
    required this.selected,
    required this.onSelect,
    required this.onOk,
  });

  @override
  State<_GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<_GuideCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final cat = widget.category;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) {
          widget.onSelect();
          _keepVisible(context);
        }
      },
      onKeyEvent: (_, e) => _activate(e, widget.onOk),
      child: _Hover(
        builder: (context, hovered) => GestureDetector(
          onTap: widget.onSelect,
          child: Align(
            child: ParallaxFocus(
              focused: _f || hovered,
              radius: BorderRadius.circular(7 * m.k),
              child: Container(
                width: m.guideW,
                height: m.guideH,
                padding: EdgeInsets.fromLTRB(
                    11 * m.k, 10 * m.k, 11 * m.k, 9 * m.k),
                decoration: BoxDecoration(
                  color: _ink.withValues(
                      alpha: widget.selected ? 0.12 : 0.07),
                  border: Border.all(
                    color: _ink.withValues(
                        alpha: widget.selected ? 0.22 : 0.09),
                  ),
                  borderRadius: BorderRadius.circular(7 * m.k),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        cat.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _t(10.5 * m.k, w: FontWeight.w600),
                      ),
                    ),
                    Row(
                      children: [
                        _SeverityMark(severity: cat.severity),
                        const Spacer(),
                        Text(
                          '${cat.items.length}',
                          style: _t(8.5 * m.k, w: FontWeight.w600, a: 0.38),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── universe ───────────────────────────────────────────────────────────────

/// Franchise connections — a poster card with a relation eyebrow, opening the
/// related title exactly as a More Like This card does.
class ShowcaseUniverse extends StatelessWidget {
  final List<UniverseTitle> items;
  final List<FocusNode> nodes;
  final void Function(UniverseTitle)? onOpen;

  const ShowcaseUniverse({
    super.key,
    required this.items,
    required this.nodes,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final capH = m.compact ? 52.0 : 42.0 * m.k;
    return _Band(
      title: 'Universe',
      height: m.posterH * 1.10 + 24 + capH,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: m.posterGap),
        itemBuilder: (context, i) => _UniverseCard(
          item: items[i],
          node: nodes[i],
          onOpen: onOpen,
          width: m.poster,
          height: m.posterH,
        ),
      ),
    );
  }
}

class _UniverseCard extends StatefulWidget {
  final UniverseTitle item;
  final FocusNode node;
  final void Function(UniverseTitle)? onOpen;
  final double width;
  final double height;

  const _UniverseCard({
    required this.item,
    required this.node,
    required this.onOpen,
    required this.width,
    required this.height,
  });

  @override
  State<_UniverseCard> createState() => _UniverseCardState();
}

class _UniverseCardState extends State<_UniverseCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final u = widget.item;
    final slot = _slotFill(AppThemeScope.of(context));
    final url = u.posterUrl;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      onKeyEvent: (_, e) => _activate(
          e, widget.onOpen == null ? null : () => widget.onOpen!(u)),
      child: _Hover(
        builder: (context, hovered) => GestureDetector(
          onTap: () => widget.onOpen?.call(u),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: widget.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParallaxFocus(
                    focused: _f || hovered,
                    radius: BorderRadius.circular(7),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: widget.width,
                        height: widget.height,
                        child: (url != null && url.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                cacheManager: DebrifyImageCache.manager,
                                memCacheWidth: 300,
                                placeholder: (_, __) =>
                                    ColoredBox(color: slot),
                                errorWidget: (_, __, ___) =>
                                    ColoredBox(color: slot),
                              )
                            : ColoredBox(color: slot),
                      ),
                    ),
                  ),
                  SizedBox(height: m.compact ? 8 : 7),
                  Text(
                    u.relation.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(m.compact ? 9 : 7 * m.k,
                            w: FontWeight.w700, a: 0.42)
                        .copyWith(letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    u.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(m.compact ? 12 : 10 * m.k,
                        w: FontWeight.w600, a: 0.9),
                  ),
                  if (u.yearLabel.isNotEmpty)
                    Text(
                      u.yearLabel,
                      style: _t(m.compact ? 10.5 : 8.5 * m.k, a: 0.45),
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

// ── did you know ───────────────────────────────────────────────────────────

/// Trivia / goofs / quotes as reading cards — the page's footnote band.
/// Cards are focusable so the ladder can park on them (and the rail can
/// scroll), but SELECT is deliberately inert in v1: this is ambient reading,
/// like the synopsis.
class ShowcaseDidYouKnow extends StatelessWidget {
  final List<DidYouKnowEntry> entries;

  /// The full IMDb count; when it exceeds what's mounted, a terminal "+N"
  /// card says so (and carries the last focus node).
  final int total;
  final String? countLine;
  final List<FocusNode> nodes;

  const ShowcaseDidYouKnow({
    super.key,
    required this.entries,
    required this.total,
    required this.countLine,
    required this.nodes,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final hasMore = total > entries.length;
    return _Band(
      title: 'Did You Know',
      subtitle: countLine,
      height: m.dykH * 1.10 + 18,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        itemCount: entries.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(width: m.compact ? 13 : 12),
        itemBuilder: (context, i) => i < entries.length
            ? _DykCard(entry: entries[i], node: nodes[i])
            : _DykMoreCard(
                count: total - entries.length,
                node: nodes[entries.length],
              ),
      ),
    );
  }
}

class _DykCard extends StatefulWidget {
  final DidYouKnowEntry entry;
  final FocusNode node;

  const _DykCard({required this.entry, required this.node});

  @override
  State<_DykCard> createState() => _DykCardState();
}

class _DykCardState extends State<_DykCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    final e = widget.entry;
    final quote = e.kind == 'Quote';
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      // Basic cursor: ambient reading, SELECT is deliberately inert.
      child: _Hover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => Align(
          child: ParallaxFocus(
            focused: _f || hovered,
            radius: BorderRadius.circular(7 * m.k),
            child: Container(
              width: m.dykW,
              height: m.dykH,
              padding: EdgeInsets.fromLTRB(
                  m.compact ? 15 : 13 * m.k, m.compact ? 13 : 11 * m.k,
                  m.compact ? 15 : 13 * m.k, m.compact ? 13 : 11 * m.k),
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: _f || hovered ? 0.11 : 0.07),
                border: Border.all(color: _ink.withValues(alpha: 0.09)),
                borderRadius: BorderRadius.circular(7 * m.k),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.kind.toUpperCase(),
                    style: _t(m.compact ? 10 : 7.5 * m.k,
                            w: FontWeight.w700, a: 0.42)
                        .copyWith(letterSpacing: 1.2),
                  ),
                  SizedBox(height: m.compact ? 8 : 6),
                  Expanded(
                    child: Text(
                      quote ? '“${e.text}”' : e.text,
                      maxLines: m.compact ? 6 : 7,
                      overflow: TextOverflow.ellipsis,
                      style: _t(m.compact ? 12.5 : 9.5 * m.k,
                              a: quote ? 0.88 : 0.8)
                          .copyWith(
                        height: 1.5,
                        fontStyle:
                            quote ? FontStyle.italic : FontStyle.normal,
                      ),
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

class _DykMoreCard extends StatefulWidget {
  final int count;
  final FocusNode node;

  const _DykMoreCard({required this.count, required this.node});

  @override
  State<_DykMoreCard> createState() => _DykMoreCardState();
}

class _DykMoreCardState extends State<_DykMoreCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      // Basic cursor: like its siblings, this card is not activatable.
      child: _Hover(
        cursor: MouseCursor.defer,
        builder: (context, hovered) => Align(
          child: ParallaxFocus(
            focused: _f || hovered,
            radius: BorderRadius.circular(7 * m.k),
            child: Container(
              width: m.compact ? 110.0 : 92.0 * m.k,
              height: m.dykH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: _f || hovered ? 0.11 : 0.05),
                border: Border.all(color: _ink.withValues(alpha: 0.09)),
                borderRadius: BorderRadius.circular(7 * m.k),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+${widget.count}',
                    style: _t(m.compact ? 20 : 16 * m.k, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'ON IMDb',
                    style: _t(m.compact ? 9 : 7 * m.k,
                            w: FontWeight.w700, a: 0.4)
                        .copyWith(letterSpacing: 1.1),
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

// ── shared band chrome ─────────────────────────────────────────────────────

class _Band extends StatelessWidget {
  final String title;
  final double height;
  final Widget child;

  /// A quiet count line after the title ("142 trivia · 9 goofs · 26 quotes").
  final String? subtitle;

  const _Band({
    required this.title,
    required this.height,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.only(left: m.gutter, bottom: 10),
          // Compact band titles use the phone heading size; wide keeps the
          // shipped 13pt (the 960-canvas number the TV mock pins), k-scaled
          // back to proportion on wide touch surfaces.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style:
                    _t(m.compact ? 19 : 13 * m.k, w: FontWeight.w600, a: 0.84),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 9),
                Text(
                  subtitle!,
                  style: _t(m.compact ? 11.5 : 8.5 * m.k,
                      w: FontWeight.w600, a: 0.35),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: height, child: child),
      ],
    );
  }
}


/// A band that has nothing to show yet, or could not load.
///
/// Without this a failed episode load reads as the band simply not being
/// there — indistinguishable from a movie, and with no way to retry.
class ShowcaseBandNote extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Supplied by the layout so the chip joins the band ladder. A focusable
  /// control the DPAD map does not know about is a control nobody can reach.
  final FocusNode? actionNode;

  const ShowcaseBandNote({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.actionNode,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 22, m.gutter, 8),
      child: Row(
        children: [
          Text(text, style: _t(11.5 * m.k, a: 0.66)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 12),
            _RetryChip(
              label: actionLabel!,
              onTap: onAction!,
              node: actionNode,
            ),
          ],
        ],
      ),
    );
  }
}

class _RetryChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final FocusNode? node;

  const _RetryChip({required this.label, required this.onTap, this.node});

  @override
  State<_RetryChip> createState() => _RetryChipState();
}

class _RetryChipState extends State<_RetryChip> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final k = ShowcaseMetrics.of(context).k;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) => _activate(e, widget.onTap),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 22 * k,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 11 * k),
          decoration: BoxDecoration(
            color: _f ? _ink : _ink.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(11 * k),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10.5 * k,
              fontWeight: FontWeight.w600,
              color: _f ? Colors.black : _ink,
            ),
          ),
        ),
      ),
    );
  }
}


/// The Details band — Creator/Country/Language/Studio/Box Office, and awards.
///
/// Reference material, not a row of verbs, so it sits at the very bottom and
/// takes no cursor. Two columns because a single column of five short pairs
/// leaves a screen mostly empty at three metres.
class ShowcaseDetails extends StatelessWidget {
  final List<(String, String)> rows;
  final String? awards;

  const ShowcaseDetails({super.key, required this.rows, required this.awards});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && (awards ?? '').isEmpty) return const SizedBox.shrink();
    final m = ShowcaseMetrics.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(m.gutter, 26, m.gutter, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Details', style: _t(13 * m.k, w: FontWeight.w600, a: 0.84)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 46,
            runSpacing: 7,
            children: [
              for (final r in rows)
                SizedBox(
                  width: 240 * m.k,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 74 * m.k,
                          child: Text(r.$1, style: _t(10 * m.k, a: 0.5))),
                      Expanded(
                          child: Text(r.$2, style: _t(10 * m.k, a: 0.82))),
                    ],
                  ),
                ),
            ],
          ),
          if ((awards ?? '').isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(awards!, style: _t(10 * m.k, a: 0.6)),
          ],
        ],
      ),
    );
  }
}
