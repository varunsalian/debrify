import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../utils/platform_util.dart';

enum AutoSyncPillPhase {
  /// The one up-front sentence, shown for ~5s when a listening window opens.
  announce,

  /// An alignment pass is running right now.
  checking,
  synced,

  /// A sync remembered from an earlier session was re-applied at load.
  restored,
  failed,
}

class AutoSyncPillModel {
  final AutoSyncPillPhase phase;

  const AutoSyncPillModel(this.phase);
}

/// The quiet bottom-right auto-sync status surface.
///
/// Lifecycle: an announce line for a few seconds, then NOTHING until
/// something actually happens — brief status text during alignment passes
/// and word-only results. No countdown, no persistent indicator: the engine's
/// pace varies by platform and the surface only speaks on real events.
/// Display-only: never focusable, never tappable — hosts must wrap it in
/// IgnorePointer.
class AutoSyncPill extends StatefulWidget {
  final AutoSyncPillModel model;

  const AutoSyncPill({super.key, required this.model});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Corner inset the host should use: TV stays inside the overscan safe
  /// area, everything else hugs the corner more closely.
  static double get cornerInset =>
      PlatformUtil.isTelevision ? 48 : (_isDesktop ? 24 : 16);

  /// The pill's em scale: 1.0 == the phone footprint.
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

  Widget _dot(double u, bool reduceMotion) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(10 * u),
          painter: _HeartbeatDotPainter(
            color: _cyan,
            pulse: reduceMotion ? 0 : _pulse.value,
          ),
        );
      },
    );
  }

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

    final decoration = BoxDecoration(
      color: const Color(0xA80C0E12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: switch (phase) {
          AutoSyncPillPhase.synced ||
          AutoSyncPillPhase.restored => _green.withValues(alpha: 0.30),
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
    );

    final Color textColor;
    final String label;
    final bool upper;
    switch (phase) {
      case AutoSyncPillPhase.announce:
        textColor = Colors.white.withValues(alpha: 0.92);
        label = 'Trying to auto-sync subtitles — this may take a minute, '
            'keep watching';
        upper = false;
      case AutoSyncPillPhase.checking:
        textColor = Colors.white.withValues(alpha: 0.92);
        label = 'CHECKING…';
        upper = true;
      case AutoSyncPillPhase.synced:
        textColor = _green;
        label = 'SUBTITLES SYNCED';
        upper = true;
      case AutoSyncPillPhase.restored:
        textColor = _green;
        label = 'SYNC RESTORED';
        upper = true;
      case AutoSyncPillPhase.failed:
        textColor = _amber;
        label = 'LEFT UNCHANGED';
        upper = true;
    }

    return RepaintBoundary(
      child: Container(
        height: 24 * u,
        padding: EdgeInsets.only(left: 8 * u, right: 10 * u),
        decoration: decoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isResult)
              Icon(
                phase == AutoSyncPillPhase.synced
                    ? Icons.check_rounded
                    : Icons.priority_high_rounded,
                color: textColor,
                size: 11.5 * u,
              )
            else
              _dot(u, reduceMotion),
            SizedBox(width: 5.5 * u),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 8.5 * u,
                fontWeight: upper ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: (upper ? 0.8 : 0.1) * u,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartbeatDotPainter extends CustomPainter {
  final Color color;
  final double pulse;

  const _HeartbeatDotPainter({required this.color, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (pulse > 0) {
      canvas.drawCircle(
        center,
        r * (0.35 + 0.65 * pulse),
        Paint()
          ..color = color.withValues(alpha: 0.32 * (1 - pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * 0.14,
      );
    }
    canvas.drawCircle(center, r * 0.32, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HeartbeatDotPainter old) =>
      old.pulse != pulse || old.color != color;
}
