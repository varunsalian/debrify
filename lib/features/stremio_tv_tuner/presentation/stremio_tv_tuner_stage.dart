import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage_content.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';

// =========================================================================
// The Stage — the cinematic now-playing hero.
// =========================================================================

class StremioTvTunerStage extends StatefulWidget {
  final StremioTvChannel channel;
  final Color ident;
  final StremioTvNowPlaying? nowPlaying;
  final StremioTvNowPlaying? nextPlaying;
  final double displayProgress;
  final bool hideNowPlaying;
  final bool isTelevision;
  final bool loading;
  final VoidCallback? onOpenList;
  final VoidCallback? onOpenDetail;

  const StremioTvTunerStage({
    required this.channel,
    required this.ident,
    required this.nowPlaying,
    required this.nextPlaying,
    required this.displayProgress,
    required this.hideNowPlaying,
    required this.isTelevision,
    required this.loading,
    this.onOpenList,
    this.onOpenDetail,
  });

  @override
  State<StremioTvTunerStage> createState() => StremioTvTunerStageState();
}

class StremioTvTunerStageState extends State<StremioTvTunerStage>
    with TickerProviderStateMixin {
  StremioTvTunerStageContent? _contentCache;
  StremioTvTunerStageContent get _content =>
      _contentCache ??= StremioTvTunerStageContent(this);

  // Slow, endless Ken Burns breathe on the backdrop — same recipe as the Home
  // hero: a pure bottom-anchored zoom on an already-rasterised image, isolated
  // in a RepaintBoundary so only the backdrop layer re-rasters per frame. The
  // long duration keeps the motion barely-there.
  late final AnimationController _ken = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  );

  // Short cascade for the text block when the channel / now-playing changes:
  // tag, title, meta, plot and live bar slide-fade in with tiny staggers
  // instead of hard-swapping (the Home hero's _textFx, verbatim).
  late final AnimationController _textFx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1.0, // first build shows settled text; cascades start on change
  );

  bool _motionOk = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion: hold the backdrop still, skip text cascades.
    _motionOk = !MediaQuery.of(context).disableAnimations;
    _syncKen();
  }

  /// Run the breathe only when something actually paints it: in blur mode —
  /// and on a channel with no backdrop yet (item still loading) — the backdrop
  /// AnimatedBuilder isn't in the tree, and a listener-less repeating
  /// controller would still force engine frames at 60fps for nothing.
  ///
  /// Never on TV: unlike the Home hero (a short strip), the Stage backdrop is
  /// near-full-screen, so the breathe re-rasters almost the whole frame 60fps
  /// forever. On weak TV GPUs that standing load is what makes everything
  /// drawn on top — dial focus pops, the quick-actions sheet, menu focus
  /// moves — feel sluggish, for motion that's barely perceptible anyway.
  void _syncKen() {
    final item = widget.nowPlaying?.item;
    final hasArt = (item?.background ?? item?.poster) != null;
    final wantKen =
        _motionOk && !widget.hideNowPlaying && hasArt && !widget.isTelevision;
    if (!wantKen) {
      _ken.stop();
    } else if (!_ken.isAnimating) {
      _ken.repeat(reverse: true);
    }
    if (!_motionOk) _textFx.value = 1.0;
  }

  @override
  void didUpdateWidget(StremioTvTunerStage old) {
    super.didUpdateWidget(old);
    _syncKen();
    final itemChanged =
        old.nowPlaying?.item.id != widget.nowPlaying?.item.id ||
        old.channel.id != widget.channel.id;
    if (itemChanged && _motionOk) {
      _textFx.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ken.dispose();
    _textFx.dispose();
    super.dispose();
  }

  /// Wraps one text-block line in its slice of the cascade: a quick fade plus
  /// a slight upward drift, offset by [from]..[to] of the controller.
  Widget cascade(Widget child, double from, double to) {
    final curved = CurvedAnimation(
      parent: _textFx,
      curve: Interval(from, to, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, inner) => Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: inner,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.nowPlaying?.item;
    final bg = item?.background ?? item?.poster;
    final blurArt = widget.hideNowPlaying;

    final isNarrow = widget.onOpenList != null;
    final bottomInset = isNarrow
        ? 30.0 + MediaQuery.of(context).padding.bottom + 72.0
        : 30.0;

    return DecoratedBox(
      // Base matches the Home page background (was a colder near-black), so a
      // channel with no backdrop and the Stage's lower fade both land on the
      // same indigo the rest of the app uses.
      decoration: BoxDecoration(color: app.home.bg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cinematic backdrop.
          if (bg != null)
            Builder(
              builder: (context) {
                Widget art = CachedNetworkImage(
                  imageUrl: bg,
                  fit: BoxFit.cover,
                  // The Stage swaps a fresh full-bleed backdrop on every surf
                  // settle, so it uses the shared hero decode cap (1080 on
                  // TV) rather than an oversized decode per step. Hidden mode
                  // on TV decodes at 96px with NO gaussian pass (below): the
                  // cover-fit upscale of a tiny decode reads as the same
                  // obscuring blur for free — the hero backdrop's recipe.
                  memCacheWidth: blurArt
                      ? (widget.isTelevision ? 96 : 480)
                      : (widget.isTelevision
                            ? HomeTheme.heroBackdropCacheWidthTv
                            : HomeTheme.heroBackdropCacheWidth),
                  // On TV, snap the swap instead of a fade — deliberately NOT
                  // the shared HomeTheme token (which now fades 150ms on TV
                  // for the small board posters): the Stage swaps to a FRESH
                  // URL on every surf settle, so the memory-cache no-fade
                  // shortcut never applies here, and even a short fade is a
                  // near-full-screen saveLayer per frame on every surf step —
                  // with no placeholder, the old art would also dip to the
                  // page colour mid-fade. The text cascade provides the
                  // transition polish.
                  fadeInDuration: widget.isTelevision
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  fadeOutDuration: widget.isTelevision
                      ? Duration.zero
                      : const Duration(milliseconds: 1000),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
                if (blurArt && !widget.isTelevision) {
                  art = ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: art,
                  );
                }
                if (widget.isTelevision) {
                  // A full-screen ColorFiltered(darken) is a saveLayer that
                  // gets re-composited on every surf settle — heavy on TV. For
                  // this subtle 12% darken a plain black overlay (srcOver) reads
                  // the same but costs nothing: no saveLayer, no blend pass.
                  art = Stack(
                    fit: StackFit.expand,
                    children: [
                      art,
                      Container(color: Colors.black.withValues(alpha: 0.12)),
                    ],
                  );
                } else {
                  art = ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.12),
                      BlendMode.darken,
                    ),
                    child: art,
                  );
                }
                // Ken Burns breathe (Home hero recipe). Skipped in blur mode —
                // re-running the 32px blur every zoom frame would hammer the
                // weak TV GPU for motion that's invisible under the blur.
                // The RepaintBoundary confines the per-frame re-raster to the
                // backdrop; the ClipRect is load-bearing — the bottom-anchored
                // scale paints upward past the Stage at paint time, which the
                // Stack's own clip never catches.
                if (blurArt) return art;
                return RepaintBoundary(
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _ken,
                      builder: (context, child) {
                        final t = Curves.easeInOut.transform(_ken.value);
                        return Transform.scale(
                          scale: 1.0 + 0.06 * t,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.low,
                          child: child,
                        );
                      },
                      child: art,
                    ),
                  ),
                );
              },
            ),
          // Multi-layer scrim for depth.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.6,
                colors: [
                  widget.ident.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  app.home.bg.withValues(alpha: 0.97),
                  app.home.bg.withValues(alpha: 0.50),
                  widget.ident.withValues(alpha: 0.06),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Legibility scrims share the page hue (home.bg) so the darkened
          // corners meet the base without a colour seam.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  app.home.bg.withAlpha(0xDD),
                  app.home.bg.withAlpha(0x00),
                ],
              ),
            ),
          ),
          // Side vignette for widescreen depth.
          if (!isNarrow)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    app.home.bg.withAlpha(0x66),
                    app.home.bg.withAlpha(0x00),
                    app.home.bg.withAlpha(0x00),
                    app.home.bg.withAlpha(0x33),
                  ],
                  stops: const [0.0, 0.15, 0.85, 1.0],
                ),
              ),
            ),
          // Content with entrance animation.
          Padding(
            padding: EdgeInsets.fromLTRB(
              isNarrow ? 28 : 48,
              isNarrow ? 56 : 28,
              isNarrow ? 28 : 48,
              bottomInset,
            ),
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth),
                    child: _content.buildContent(item, isNarrow),
                  ),
                ),
              ),
            ),
          ),
          if (widget.onOpenDetail != null)
            Positioned(
              top: 14,
              right: 18,
              child: GestureDetector(
                onTap: widget.onOpenDetail,
                child: _content.glassPill(
                  icon: Icons.info_outline_rounded,
                  label: 'Details',
                ),
              ),
            ),
          if (widget.onOpenList != null)
            Positioned(
              top: 14,
              left: 18,
              child: GestureDetector(
                onTap: widget.onOpenList,
                child: _content.glassPill(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'Channels',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
