import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Swiss — International Typographic. No glow, no gradient, no bloom: a
/// vermilion rule cuts across, the letters slide up from behind it onto an
/// absolute baseline, and the composition locks. Confidence as an animation.
///
/// TV notes: the cheapest ident in the set by a wide margin — flat fills,
/// clip rects and two small labels. No shaders, no blurs, no alpha fades on
/// type (every reveal is a hard geometric cut), nothing rebuilt per frame.
///
/// Timeline: 0–.34 rule sweeps · .18–.50 mark block rises · .24–.62 letters
/// slide up behind the rule · .62–.88 set copy · rest.
class SwissIdent extends LaunchIdent {
  const SwissIdent();

  @override
  String get id => 'swiss';
  @override
  String get label => 'Swiss';
  @override
  String get subtitle =>
      'Black, bone and one vermilion rule — hard cuts on a strict grid';
  @override
  Duration get revealDuration => const Duration(milliseconds: 1800);
  @override
  Color get baseColor => const Color(0xFF000000);
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFFF3B23), Color(0xFFF2F4F8)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _SwissPainter(animation, isTelevision: isTelevision);
}

class _SwissPainter extends CustomPainter {
  final Animation<double> animation;

  Size? _size;
  IdentWordLayout? _word;
  late double _u, _m, _startX, _baseY, _ruleY, _sq, _sqX, _ruleH;
  late Path _knockout;
  late Path _ticks;
  late TextPainter _tl, _br;

  static const Color _red = Color(0xFFFF3B23);

  // No TV-specific path: this ident is already at the cost floor everywhere.
  _SwissPainter(this.animation, {required bool Function() isTelevision})
      : super(repaint: animation);

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _u = identUnit(size);
    _m = _u * 1.15;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: 0,
        color: const Color(0xFFF2F4F8),
      ),
      fontSize: _u * 2.05,
      trackingFactor: -0.02,
      maxWidth: min(w - _m * 2 - _u * 2.2, _u * 11.5),
    );
    _sq = _u * 1.7;
    final lock = _sq + _u * 0.7 + _word!.width;
    _sqX = w / 2 - lock / 2;
    _startX = _sqX + _sq + _u * 0.7;
    _baseY = h / 2 + _u * 0.72;
    _ruleY = h / 2 + _u * 0.95;
    _ruleH = max(2, _u * 0.11);
    _knockout = identPlayPath(_sq * 0.56);

    _ticks = Path();
    final ty = _m * 0.55, by = h - _m * 0.55;
    for (final x in [_m, w - _m]) {
      _ticks
        ..moveTo(x, ty)
        ..lineTo(x, ty + _u * 0.5)
        ..moveTo(x, by)
        ..lineTo(x, by - _u * 0.5);
    }

    TextPainter lbl(String s, Color c) => TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(
              fontSize: _u * 0.32,
              fontWeight: FontWeight.w600,
              height: 1.0,
              letterSpacing: _u * 0.32 * 0.22,
              color: c,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    _tl = lbl('LAUNCH', const Color(0xB8F2F4F8));
    _br = lbl('DEBRID · TORRENT · IPTV', const Color(0x6BF2F4F8));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    _layout(size);
    final word = _word!;
    final w = size.width, h = size.height;

    // The grid, stated.
    canvas.drawPath(
      _ticks,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x24FFFFFF),
    );

    // The rule.
    final sw = identOutQuint(identClamp(t / 0.34, 0, 1));
    canvas.drawRect(
      Rect.fromLTWH(_m, _ruleY, (w - _m * 2) * sw, _ruleH),
      Paint()..color = _red,
    );

    // Everything above the rule is clipped — letters and block rise out of it.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, _ruleY));

    for (int i = 0; i < kIdentWord.length; i++) {
      final lt = identOutQuint(identClamp((t - (0.24 + i * 0.035)) / 0.34, 0, 1));
      if (lt <= 0) continue;
      word.paintLetter(canvas, word.base, i, _startX, _baseY,
          dy: identLerp(word.fontSize * 0.95, 0, lt));
    }

    final bl = identOutQuint(identClamp((t - 0.18) / 0.32, 0, 1));
    if (bl > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(_sqX, _baseY - _sq, _sq, _sq * bl));
      canvas.drawRect(
          Rect.fromLTWH(_sqX, _baseY - _sq, _sq, _sq), Paint()..color = _red);
      // Knocked out in the ground colour rather than a saveLayer blend.
      canvas.save();
      canvas.translate(_sqX + _sq / 2, _baseY - _sq / 2);
      canvas.drawPath(_knockout, Paint()..color = const Color(0xFF000000));
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();

    // Set copy, hard cut — no fade, in keeping.
    if (t > 0.62) {
      _tl.paint(canvas, Offset(_m + _u * 0.45, _m * 0.55));
      _br.paint(
        canvas,
        Offset(w - _m - _u * 0.45 - _br.width, h - _m * 0.55 - _br.height),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SwissPainter old) =>
      old.animation != animation;
}
