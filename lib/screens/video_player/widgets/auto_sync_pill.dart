import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../utils/platform_util.dart';

enum AutoSyncPillPhase { listening, checking, synced, failed }

class AutoSyncPillModel {
  final AutoSyncPillPhase phase;

  /// Seconds left in the 90-second listening window. Only meaningful for
  /// [AutoSyncPillPhase.listening] and [AutoSyncPillPhase.checking].
  final int secondsLeft;

  const AutoSyncPillModel(this.phase, this.secondsLeft);
}

/// The quiet bottom-right auto-sync status pill (design/mockups/
/// subtitle_auto_sync_hint_mockup/countdown_devices.html).
///
/// Display-only: never focusable, never tappable — hosts must wrap it in
/// IgnorePointer. One component at three em scales: ~24px tall on phones,
/// ~30px on desktop, ~40px at TV distance. Result states carry no numbers;
/// the countdown is the only digit that ever appears.
class AutoSyncPill extends StatefulWidget {
  final AutoSyncPillModel model;

  const AutoSyncPill({super.key, required this.model});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Corner inset the host should use: TV stays inside the overscan safe
  /// area, everything else hugs the corner more closely.
  static double get cornerInset =>
      PlatformUtil.isTelevision ? 48 : (_isDesktop ? 24 : 16);

  /// The pill's em scale: 1.0 == the phone footprint from the mock.
  static double get scale =>
      PlatformUtil.isTelevision ? 40 / 24 : (_isDesktop ? 30 / 24 : 1.0);

  @override
  State<AutoSyncPill> createState() => _AutoSyncPillState();
}

class _AutoSyncPillState extends State<AutoSyncPill>
    with SingleTickerProviderStateMixin {
  static const Color _cyan = Color(0xFF7BDCFF);
  static const Color _green = Color(0xFF82E0AD);
  static const Color _amber = Color(0xFFE8C07B);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _isResult =>
      widget.model.phase == AutoSyncPillPhase.synced ||
      widget.model.phase == AutoSyncPillPhase.failed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_isResult || reduceMotion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }

    final u = AutoSyncPill.scale;
    final phase = widget.model.phase;
    final Color statusColor;
    final String label;
    switch (phase) {
      case AutoSyncPillPhase.listening:
        statusColor = Colors.white.withValues(alpha: 0.92);
        label = 'AUTO SYNC';
      case AutoSyncPillPhase.checking:
        statusColor = Colors.white.withValues(alpha: 0.92);
        label = 'CHECKING…';
      case AutoSyncPillPhase.synced:
        statusColor = _green;
        label = 'SUBTITLES SYNCED';
      case AutoSyncPillPhase.failed:
        statusColor = _amber;
        label = 'LEFT UNCHANGED';
    }

    // The pulse invalidates every frame; the boundary keeps that repaint
    // from spilling into the player overlay above the video texture.
    return RepaintBoundary(
      child: Container(
        height: 24 * u,
        padding: EdgeInsets.only(left: 7 * u, right: 9.5 * u),
        decoration: BoxDecoration(
          color: const Color(0xA80C0E12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: switch (phase) {
              AutoSyncPillPhase.synced => _green.withValues(alpha: 0.30),
              AutoSyncPillPhase.failed => _amber.withValues(alpha: 0.30),
              _ => Colors.white.withValues(alpha: 0.13),
            },
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18 * u,
              offset: Offset(0, 5 * u),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isResult)
              Icon(
                phase == AutoSyncPillPhase.synced
                    ? Icons.check_rounded
                    : Icons.priority_high_rounded,
                color: statusColor,
                size: 11.5 * u,
              )
            else
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size.square(12 * u),
                    painter: _CountdownRingPainter(
                      progress:
                          (90 - widget.model.secondsLeft).clamp(0, 90) / 90,
                      arcColor: phase == AutoSyncPillPhase.checking
                          ? Colors.white
                          : _cyan,
                      pulse: reduceMotion ? 0 : _pulse.value,
                    ),
                  );
                },
              ),
            SizedBox(width: 5.5 * u),
            Text(
              label,
              style: TextStyle(
                color: statusColor,
                fontSize: 8.5 * u,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8 * u,
                height: 1,
              ),
            ),
            if (!_isResult) ...[
              SizedBox(width: 5.5 * u),
              Container(
                width: 1,
                height: 9.5 * u,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              SizedBox(width: 5.5 * u),
              SizedBox(
                width: 17 * u,
                child: Text(
                  '${widget.model.secondsLeft.clamp(0, 90)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 9 * u,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double progress;
  final Color arcColor;
  final double pulse;

  const _CountdownRingPainter({
    required this.progress,
    required this.arcColor,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1.2;
    final stroke = size.shortestSide * 0.11;

    if (pulse > 0) {
      canvas.drawCircle(
        center,
        radius * 0.28 + radius * 0.5 * pulse,
        Paint()
          ..color = arcColor.withValues(alpha: 0.32 * (1 - pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = arcColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      center,
      size.shortestSide * 0.14,
      Paint()..color = arcColor,
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) =>
      old.progress != progress ||
      old.arcColor != arcColor ||
      old.pulse != pulse;
}
