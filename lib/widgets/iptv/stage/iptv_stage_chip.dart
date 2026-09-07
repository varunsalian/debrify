import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../theme/app_theme_scope.dart';

/// Status chip on the stage: LIVE (emerald dot) once the preview has frames,
/// TUNING (tiny animated amber signal bars) while a channel is selected but
/// the stream hasn't opened yet, PREVIEW for on-demand items, or PREVIEW OFF
/// when automatic tuning is disabled. Conditional swaps and direct paint only
/// — no fades over the stage, and only the TUNING state animates so nothing
/// repaints while video is playing.
class IptvStageChip extends StatefulWidget {
  final IptvChannel? channel;
  final bool showing;
  final bool previewEnabled;
  const IptvStageChip({
    super.key,
    required this.channel,
    required this.showing,
    required this.previewEnabled,
  });

  @override
  State<IptvStageChip> createState() => IptvStageChipState();
}

class IptvStageChipState extends State<IptvStageChip>
    with SingleTickerProviderStateMixin {
  static const Color _amber = Color(0xFFFBBF24);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool get _tuning =>
      widget.previewEnabled && widget.channel != null && !widget.showing;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(IptvStageChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_tuning) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating) {
      _ctrl.stop();
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
    if (ch == null) return const SizedBox.shrink();
    final isLive = ch.isLive;
    final label = !widget.previewEnabled
        ? 'PREVIEW OFF'
        : widget.showing
        ? (isLive ? 'LIVE' : 'PREVIEW')
        : 'TUNING';
    final dot = !widget.previewEnabled
        ? app.iptv.inkFaint
        : isLive
        ? app.iptv.liveDot
        : app.seeAll.accent2;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        // Deliberately NOT iptv.chipSurface: this chip floats over LIVE
        // VIDEO, so it must stay black glass and legible over an arbitrary
        // picture rather than follow the page (see the token's doc).
        color: const Color(0xB00B0918),
        borderRadius: app.shape.brPill,
        // `onGlass`, not `core.tx`: the fill above is black on EVERY theme by
        // design, so its ink must be what reads on black — a paper theme's
        // near-black page ink would draw an invisible edge here. Same reason
        // the label below uses it.
        border: Border.all(color: app.onGlass.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 9,
            height: 9,
            child: _tuning
                ? CustomPaint(painter: IptvTuningBarsPainter(t: _ctrl))
                : Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: app.onGlass,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny equalizer-style signal bars for the TUNING chip — direct paint over
/// the stage (same no-saveLayer rule as everything else on it).
class IptvTuningBarsPainter extends CustomPainter {
  final Animation<double> t;
  IptvTuningBarsPainter({required this.t}) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = IptvStageChipState._amber;
    const barW = 2.0;
    const gap = 1.5;
    for (int i = 0; i < 3; i++) {
      final v = 0.5 + 0.5 * math.sin(2 * math.pi * (t.value + i * 0.32));
      final h = 3.0 + (size.height - 3.0) * v;
      final x = i * (barW + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barW, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(IptvTuningBarsPainter oldDelegate) => false;
}
