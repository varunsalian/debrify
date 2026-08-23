/// Brand identity for the trackers Debrify syncs with.
///
/// Nothing branded ships in `assets/` today and the app has no SVG renderer
/// (no `flutter_svg` dependency), so these marks are drawn in code —
/// approximations that are good enough for the tracker pills and sheet
/// lockups to read as "Trakt" and "Simkl" at a glance without adding an asset
/// pipeline or a package. If we ever bundle the official vectors, only these
/// two widgets need to change.
library;

import 'package:flutter/material.dart';

/// Trakt brand red — also the tint for anything Trakt-owned in the UI.
const Color kTraktRed = Color(0xFFED1C24);

/// Simkl's tint. Matches the cyan the Simkl status chips already used, so the
/// colour language carries over from the previous design.
const Color kSimklCyan = Color(0xFF22D3EE);
const Color kMdblistPurple = Color(0xFF8B5CF6);

/// Ink drawn *on* [kSimklCyan] — a dark teal rather than pure black so the
/// mark doesn't punch a hole in a dark surface.
const Color _kSimklInk = Color(0xFF04262C);

/// Trakt's circular mark: a filled disc with the swirl cut across it.
class TraktMark extends StatelessWidget {
  final double size;
  final Color color;

  /// Dims the whole mark — used by the "not tracked" pill state so the brand
  /// reads as present-but-inactive instead of shouting for attention.
  final double opacity;

  const TraktMark({
    super.key,
    this.size = 20,
    this.color = kTraktRed,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _TraktMarkPainter(color)),
      ),
    );
  }
}

class _TraktMarkPainter extends CustomPainter {
  final Color color;
  const _TraktMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, s / 2, Paint()..color = color);

    // Inset hairline ring — the mark reads as a badge rather than a dot.
    canvas.drawCircle(
      c,
      s * 0.388,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.034,
    );

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.069
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(x * s, y * s);

    canvas.drawPath(
      Path()
        ..moveTo(p(0.200, 0.706).dx, p(0.200, 0.706).dy)
        ..lineTo(p(0.559, 0.347).dx, p(0.559, 0.347).dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(0.319, 0.800).dx, p(0.319, 0.800).dy)
        ..lineTo(p(0.644, 0.475).dx, p(0.644, 0.475).dy)
        ..lineTo(p(0.844, 0.681).dx, p(0.844, 0.681).dy),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_TraktMarkPainter old) => old.color != color;
}

/// Simkl's mark: a rounded tile carrying the "S".
class SimklMark extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const SimklMark({
    super.key,
    this.size = 20,
    this.color = kSimklCyan,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        alignment: Alignment.center,
        child: Text(
          'S',
          style: TextStyle(
            color: _kSimklInk,
            fontSize: size * 0.68,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

class MdblistMark extends StatelessWidget {
  const MdblistMark({super.key, this.size = 20, this.opacity = 1});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kMdblistPurple,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        'M',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.62,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    ),
  );
}
