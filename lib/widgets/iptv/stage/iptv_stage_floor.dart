import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/debrify_image_cache.dart';
import '../../../theme/app_theme_scope.dart';
import '../../browse/brand_accent.dart';

/// The stage's resting surface: a brand-tinted glass slab with the channel's
/// logo (or a placeholder mark). Sits UNDER the embedded player — the video
/// covers/wipes it once frames arrive, so it needs no fade of its own.
///
/// While [tuning] (a channel is focused but no frames yet) it runs a light
/// broadcast ambience: signal rings rippling out from the logo, a breathing
/// brand glow, a diagonal sheen sweep and a gentle logo breathe. Everything is
/// direct canvas paint / matrix transform — this widget shares a layer with
/// the underlay's punched hole, so Opacity/saveLayer wrappers stay banned.
/// The controller stops the moment frames arrive (or focus clears), so
/// nothing keeps repainting under a playing video.
class IptvStageFloor extends StatefulWidget {
  final IptvChannel? channel;
  final bool tuning;
  const IptvStageFloor({
    super.key,
    required this.channel,
    required this.tuning,
  });

  @override
  State<IptvStageFloor> createState() => IptvStageFloorState();
}

class IptvStageFloorState extends State<IptvStageFloor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(IptvStageFloor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final animate = widget.tuning && widget.channel != null;
    if (animate) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating || _ctrl.value != 0) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final ch = widget.channel;
    final brand = ch != null ? brandAccentFor(ch.name) : app.seeAll.accent;
    final logo = ch?.logoUrl;
    final animate = widget.tuning && ch != null;

    Widget mark = ch == null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.live_tv_rounded,
                size: 42,
                color: app.core.tx.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 10),
              Text(
                'Browse channels to preview',
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0.45),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        : (logo != null && logo.isNotEmpty)
        ? Padding(
            padding: const EdgeInsets.all(38),
            child: CachedNetworkImage(
              imageUrl: logo,
              cacheManager: DebrifyImageCache.iptvLogos,
              fit: BoxFit.contain,
              // Cap the decode — see the row logo chip's rationale.
              memCacheHeight: 240,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (_, __, ___) => Icon(
                Icons.live_tv_rounded,
                size: 42,
                color: brand.withValues(alpha: 0.75),
              ),
            ),
          )
        : Icon(
            Icons.live_tv_rounded,
            size: 42,
            color: brand.withValues(alpha: 0.75),
          );

    if (animate) {
      // Transform is a canvas matrix, not a compositing layer — hole-safe.
      mark = AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.015 * math.sin(2 * math.pi * _ctrl.value),
          child: child,
        ),
        child: mark,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              brand.withValues(alpha: 0.18),
              const Color(0xFF171430),
            ),
            const Color(0xFF0F0D20),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (animate)
            CustomPaint(
              painter: IptvTuningWavesPainter(brand: brand, t: _ctrl),
            ),
          Center(child: mark),
        ],
      ),
    );
  }
}

/// The tuning ambience: staggered signal rings expanding from the stage
/// centre, a soft breathing glow behind the logo, and a slow diagonal sheen
/// sweeping the slab. Plain canvas paints only — this layer is the one the
/// video punch-through wipes, so no saveLayer/Opacity is allowed here.
class IptvTuningWavesPainter extends CustomPainter {
  final Color brand;
  final Animation<double> t;
  IptvTuningWavesPainter({required this.brand, required this.t})
    : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final center = size.center(Offset.zero);

    // Breathing glow behind the logo.
    final glowAlpha = 0.10 + 0.05 * math.sin(2 * math.pi * v);
    final glowRadius = size.shortestSide * 0.42;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(center, glowRadius, [
          brand.withValues(alpha: glowAlpha),
          brand.withValues(alpha: 0),
        ]),
    );

    // Signal rings rippling outward from behind the logo.
    final ringColor = Color.lerp(brand, Colors.white, 0.35)!;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final maxGrow = size.shortestSide * 0.62;
    for (int i = 0; i < 3; i++) {
      final phase = (v + i / 3) % 1.0;
      final eased = Curves.easeOut.transform(phase);
      final fade = (1 - phase) * (1 - phase);
      ring.color = ringColor.withValues(alpha: 0.16 * fade);
      canvas.drawCircle(center, 30 + eased * maxGrow, ring);
    }

    // Diagonal sheen sweeping across the slab once per cycle.
    final sweep = Curves.easeInOut.transform(v);
    final x = size.width * (-0.35 + 1.7 * sweep);
    final band = Paint()
      ..shader = ui.Gradient.linear(
        Offset(x - 70, 0),
        Offset(x + 70, size.height),
        [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Offset.zero & size, band);
  }

  @override
  bool shouldRepaint(IptvTuningWavesPainter oldDelegate) =>
      oldDelegate.brand != brand;
}
