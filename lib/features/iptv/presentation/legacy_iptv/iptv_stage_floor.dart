import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/iptv/presentation/tuning_waves_painter.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/browse/brand_accent.dart';
import 'package:flutter/material.dart';

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
  State<IptvStageFloor> createState() => _IptvStageFloorState();
}

class _IptvStageFloorState extends State<IptvStageFloor>
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
              painter: TuningWavesPainter(brand: brand, t: _ctrl),
            ),
          Center(child: mark),
        ],
      ),
    );
  }
}
