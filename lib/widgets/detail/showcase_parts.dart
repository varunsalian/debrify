import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../../services/series_source_service.dart';
import '../../services/trakt/trakt_episode_model.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../episodes_panel.dart';
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
  const ShowcaseMetrics(this.w);

  /// From the space actually GIVEN, not from the screen.
  ///
  /// tvOS reports a full-screen size while the shell insets the content for
  /// overscan safe area, so `MediaQuery.sizeOf` overstates the drawable width
  /// and every card comes out proportionally too large for the band it sits
  /// in. `maxWidth` here is whatever the rail was handed.
  /// The DRAWABLE width, not the screen.
  ///
  /// tvOS reports a full-screen size while the shell insets the content for
  /// overscan safe area, so sizing off `MediaQuery.sizeOf` alone makes every
  /// card proportionally too large for the band it is drawn in. Subtracting
  /// the safe-area padding is exactly that correction, and unlike probing the
  /// render object it is stable during build.
  factory ShowcaseMetrics.of(BuildContext c) {
    final mq = MediaQuery.of(c);
    final w = mq.size.width - mq.padding.horizontal;
    return ShowcaseMetrics(w > 0 ? w : mq.size.width);
  }

  double get gutter => w * (84 / 1920);
  double get title => w * (26 / 1920);

  double get stillW => w * (432 / 1920);
  double get stillH => stillW * (243 / 432);
  double get epCell => w * (456 / 1920);
  double get epGap => w * (46 / 1920);

  double get circle => w * (250 / 1920);
  double get castGap => w * (52 / 1920);

  double get srcW => w * (560 / 1920);
  double get srcH => w * (132 / 1920);
  double get srcGap => w * (26 / 1920);

  double get poster => w * (260 / 1920);
  double get posterH => poster * (390 / 260);
  double get posterGap => w * (40 / 1920);
}

/// Kept for callers that only need the page margin.
const double kShowcaseGutter = 42;

const _ink = Color(0xFFFFFFFF);

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
              placeholder: (_, __) => const ColoredBox(color: Color(0xFF0A0A0B)),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF0A0A0B)),
            ),
          ),
          // The field is a BED for white text, not a picture. Under a .55 veil
          // the artwork starts competing with the episode titles sitting on it.
          const ColoredBox(color: Color(0x940A0A0B)),
        ],
      ),
    );
  }
}

/// The identity scrim: a 100° left fade, so the text side is dark and the art
/// keeps its right two-thirds.
class ShowcaseBackdropScrim extends StatelessWidget {
  final bool visible;

  const ShowcaseBackdropScrim({super.key, required this.visible});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 550),
          opacity: visible ? 1 : 0,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1, -0.2),
                end: Alignment(1, 0.2),
                colors: [
                  Color(0xE0000000),
                  Color(0xA8000000),
                  Color(0x2E000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.26, 0.52, 0.68],
              ),
            ),
          ),
        ),
      );
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
  Widget build(BuildContext context) => IgnorePointer(
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
                    ? Text(name, style: _t(17, w: FontWeight.w700))
                    : CachedNetworkImage(
                        imageUrl: url!,
                        height: 37,
                        fit: BoxFit.contain,
                        cacheManager: DebrifyImageCache.manager,
                        memCacheWidth: 420,
                        errorWidget: (_, __, ___) =>
                            Text(name, style: _t(17, w: FontWeight.w700)),
                      ),
              ),
            ),
          ),
        ),
      );
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

    if (m.onTrackers != null && actionNodes.isNotEmpty) {
      actions.add(_Circle(node: next(), icon: Icons.add_rounded, onTap: m.onTrackers!));
    }
    if (m.onTrackersSecondary != null && i < actionNodes.length) {
      actions.add(_Circle(
        node: next(),
        icon: Icons.bookmark_add_outlined,
        onTap: m.onTrackersSecondary!,
      ));
    }
    if (m.hasTrailer && i < actionNodes.length) {
      actions.add(_Circle(
        node: next(),
        icon: Icons.play_arrow_rounded,
        onTap: m.onTrailer,
      ));
    }
    if (m.onAppMenu != null && i < actionNodes.length) {
      actions.add(_Circle(
        node: next(),
        icon: Icons.more_horiz_rounded,
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
    return SizedBox(
      height: height,
      child: _identityColumn(context, m, actions),
    );
  }

  Widget _identityColumn(
    BuildContext context,
    DetailModel m,
    List<Widget> actions,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kShowcaseGutter, 0, kShowcaseGutter, 26),
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
          if ((m.synopsis ?? '').isNotEmpty)
            SizedBox(
              width: 410,
              child: Text(
                m.synopsis!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _t(10.5, a: 0.74).copyWith(height: 1.42),
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

  const _LogoOrTitle({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    // Metahub ships some logos as BLACK wordmarks, invisible on ink — roughly
    // one title in four. The text fallback is not a degraded path, it is the
    // other half of the design.
    final text = Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 39,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: _ink,
      ),
    );
    if (url == null || url!.isEmpty) return text;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 235, maxHeight: 60),
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.contain,
        alignment: Alignment.bottomLeft,
        cacheManager: DebrifyImageCache.manager,
        memCacheWidth: 520,
        errorWidget: (_, __, ___) => text,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3.5),
          child: Text(label, style: _t(9.5, w: FontWeight.w600)),
        ),
      );
}

/// The meta line — and where the trackers live.
///
/// Trakt and Simkl are READOUT here, not buttons: filled when tracked, hollow
/// when not, never focusable. Tracker state describes what a title is to you;
/// it is not an errand you came to the page to run, and a row of verbs is the
/// wrong place for it. The `+` button opens both.
class _MetaLine extends StatelessWidget {
  final DetailModel model;

  const _MetaLine({required this.model});

  @override
  Widget build(BuildContext context) {
    final m = model;
    final bits = <String>[
      if (m.isMovie) 'Film' else 'Series',
      ...m.genres.take(2),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(bits.join(' · '), style: _t(10.5, a: 0.86)),
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
  Widget build(BuildContext context) => Container(
        width: 15,
        height: 15,
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
            fontSize: 7,
            fontWeight: FontWeight.w800,
            color: on ? _ink : _ink.withValues(alpha: 0.5),
          ),
        ),
      );
}

class _RatingBox extends StatelessWidget {
  final double value;

  const _RatingBox({required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
        decoration: BoxDecoration(
          border: Border.all(color: _ink.withValues(alpha: 0.45), width: 0.75),
          borderRadius: BorderRadius.circular(2.5),
        ),
        child: Text('★ ${value.toStringAsFixed(1)}', style: _t(7.5, a: 0.9)),
      );
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
    return Text(bits.join('  ·  '), style: _t(9.5, a: 0.7));
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 17),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // The focus flip: ghost at rest, SOLID WHITE on black when
              // focused. The reference's primary is the one thing that does not
              // merely lift.
              color: _f ? _ink : _ink.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 14,
                  color: _f ? Colors.black : _ink,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _f ? Colors.black : _ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Circle extends StatefulWidget {
  final FocusNode node;
  final IconData icon;
  final VoidCallback onTap;

  const _Circle({required this.node, required this.icon, required this.onTap});

  @override
  State<_Circle> createState() => _CircleState();
}

class _CircleState extends State<_Circle> {
  bool _f = false;

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
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _f ? _ink : _ink.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _f ? Colors.black : _ink,
            ),
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
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: kShowcaseGutter),
          itemCount: view.seasons.length,
          separatorBuilder: (_, __) => const SizedBox(width: 7),
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
  Widget build(BuildContext context) => Focus(
        focusNode: widget.node,
        onFocusChange: (v) {
          setState(() => _f = v);
          if (v) _keepVisible(context);
        },
        // Selecting on FOCUS would reload the episode list on every step of a
        // walk across the seasons. OK commits; the walk is free.
        onKeyEvent: (_, e) => _activate(e, widget.onTap),
        child: ParallaxFocus(
          focused: _f,
          shape: ParallaxShape.pill,
          radius: BorderRadius.circular(12.5),
          child: Container(
            height: 25,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: (_f || widget.active)
                  ? _ink.withValues(alpha: _f ? 0.28 : 0.18)
                  : null,
              borderRadius: BorderRadius.circular(12.5),
            ),
            child: Text(
              widget.label,
              style: _t(12.5,
                  w: FontWeight.w600, a: widget.active || _f ? 1 : 0.55),
            ),
          ),
        ),
      );
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
                            const ColoredBox(color: Color(0xFF17171A)),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF17171A)),
                      )
                    else
                      const ColoredBox(color: Color(0xFF17171A)),
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
                Text('EPISODE ${episode.number}',
                    style: _t(9.5, a: 0.55).copyWith(letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(12.5, w: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 29,
                  child: Text(
                    episode.overview ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _t(10.5, a: 0.6).copyWith(height: 1.36),
                  ),
                ),
                if ((episode.firstAired ?? '').isNotEmpty)
                  Text(episode.firstAired!.split('T').first,
                      style: _t(9.5, a: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(3.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(label, style: _t(9.5)),
        ),
      );
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
      height: m.circle * 1.08 + 46,
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
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      child: SizedBox(
        width: widget.size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ParallaxFocus(
              focused: _f,
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
              style: _t(12.5),
            ),
            if ((widget.member.character ?? '').isNotEmpty)
              Text(
                widget.member.character!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _t(11.5, a: 0.55),
              ),
          ],
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

  const ShowcaseSources({
    super.key,
    required this.sources,
    required this.nodes,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => _Band(
        title: 'Sources',
        height: 96,
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
              horizontal: ShowcaseMetrics.of(context).gutter),
          itemCount: sources.length + 1,
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
  final VoidCallback? onTap;

  const _SourceCard({
    required this.node,
    required this.onTap,
    this.source,
    this.add = false,
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      onKeyEvent: (_, e) => _activate(e, widget.onTap),
      child: GestureDetector(
        onTap: widget.onTap,
        // Same reason as `_Poster`: the Sources band is 96 tall to leave the
        // lift room, and the tight cross-axis constraint would stretch this
        // 66pt card to fill it.
        child: Align(
          child: ParallaxFocus(
            focused: _f,
            shape: ParallaxShape.sourceCard,
            radius: BorderRadius.circular(7),
            child: Container(
              width: widget.add ? 150 : 280,
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: widget.add ? null : _ink.withValues(alpha: 0.07),
                border: Border.all(
                  color: _ink.withValues(alpha: widget.add ? 0.22 : 0.09),
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: widget.add
                  ? Center(
                      child: Text('＋  Find sources',
                          style: _t(10.5, a: 0.66)),
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
                                style: _t(10.5, w: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s?.debridService ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _t(9.5, a: 0.58),
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
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v) _keepVisible(context);
      },
      onKeyEvent: (_, e) => _activate(e, () => widget.onTap?.call(widget.item)),
      child: GestureDetector(
        onTap: () => widget.onTap?.call(widget.item),
        // The band is taller than the card so the lift has somewhere to go,
        // and a horizontal ListView constrains its children to that height
        // TIGHTLY — without an Align the poster is stretched to the band while
        // its width stays `m.poster`, drawing a 2:3 poster at about 0.53:1.
        child: Align(
          child: ParallaxFocus(
            focused: _f,
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
                            const ColoredBox(color: Color(0xFF17171A)),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF17171A)),
                      )
                    : const ColoredBox(color: Color(0xFF17171A)),
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

  const _Band({required this.title, required this.height, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: kShowcaseGutter, bottom: 10),
            child: Text(title, style: _t(13, w: FontWeight.w600, a: 0.84)),
          ),
          SizedBox(height: height, child: child),
        ],
      );
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kShowcaseGutter, 22, kShowcaseGutter, 8),
        child: Row(
          children: [
            Text(text, style: _t(11.5, a: 0.66)),
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
  Widget build(BuildContext context) => Focus(
        focusNode: widget.node,
        onFocusChange: (v) => setState(() => _f = v),
        onKeyEvent: (_, e) => _activate(e, widget.onTap),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 22,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: _f ? _ink : _ink.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: _f ? Colors.black : _ink,
              ),
            ),
          ),
        ),
      );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(kShowcaseGutter, 26, kShowcaseGutter, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Details', style: _t(13, w: FontWeight.w600, a: 0.84)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 46,
            runSpacing: 7,
            children: [
              for (final r in rows)
                SizedBox(
                  width: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 74, child: Text(r.$1, style: _t(10, a: 0.5))),
                      Expanded(child: Text(r.$2, style: _t(10, a: 0.82))),
                    ],
                  ),
                ),
            ],
          ),
          if ((awards ?? '').isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(awards!, style: _t(10, a: 0.6)),
          ],
        ],
      ),
    );
  }
}
