import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The flat-vector character avatars, drawn in code.
///
/// Deliberately flat: solid fills, no gradients, no specular highlights, no
/// texture. That is the whole visual thesis — the shipped GIF characters read
/// as machine-rendered precisely because of the glossy shading, and these are
/// meant to read as drawn.
///
/// Every painter works in a **256×256 design space** and is scaled to the box
/// by [_scaled], so the geometry below can be read against the source mock
/// (`dev/design/mockups/profile_avatar_mockup/`) without mental arithmetic.
/// Costs a few KB of code each, against ~250 KB for one bundled GIF.
///
/// The only animation is a blink, once per controller cycle — see [_lid]. It
/// is what earns `animated: true`, and it exists because the avatar's motion
/// doubles as the focus indicator across a room.
class ProfileFaceArt {
  ProfileFaceArt._();

  static const double _unit = 256;

  /// Runs [draw] in the 256×256 design space, stretched to fill [size].
  static void _scaled(Canvas canvas, Size size, void Function(Canvas) draw) {
    canvas.save();
    canvas.scale(size.width / _unit, size.height / _unit);
    draw(canvas);
    canvas.restore();
  }

  /// Eye openness, 1 = open, 0 = shut.
  ///
  /// A single blink near the end of the cycle. `t` wraps 0→1 over the view's
  /// 7 s controller, so the blink lands roughly every seven seconds and lasts
  /// about a third of a second — long enough to read, short enough not to draw
  /// the eye on its own.
  static double _lid(double t) {
    const double start = 0.88;
    const double span = 0.045;
    if (t < start || t > start + span) return 1;
    return 1 - math.sin((t - start) / span * math.pi);
  }

  static Paint _fill(Color color) => Paint()..color = color;

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static void _bg(Canvas canvas, Color color) =>
      canvas.drawRect(const Rect.fromLTWH(0, 0, _unit, _unit), _fill(color));

  static void _tri(Canvas canvas, Offset a, Offset b, Offset c, Color color) {
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close(),
      _fill(color),
    );
  }

  /// A blinking eye. [ry] collapses toward a slit rather than to nothing, so a
  /// shut eye still reads as an eye and not as a missing shape.
  static void _eye(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double lid,
    Color color,
  ) {
    final double h = math.max(ry * lid, ry * 0.12);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: h * 2),
      _fill(color),
    );
  }

  static void _curve(
    Canvas canvas,
    Offset from,
    Offset control,
    Offset to,
    Color color,
    double width,
  ) {
    canvas.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy),
      _stroke(color, width),
    );
  }

  /// The two-stroke muzzle mouth shared by cat, panda and bear.
  static void _muzzleMouth(
    Canvas canvas,
    Offset from,
    double dx,
    double drop,
    Color color,
    double width,
  ) {
    _curve(
      canvas,
      from,
      Offset(from.dx - dx * 0.5, from.dy + drop),
      Offset(from.dx - dx, from.dy + drop * 0.25),
      color,
      width,
    );
    _curve(
      canvas,
      from,
      Offset(from.dx + dx * 0.5, from.dy + drop),
      Offset(from.dx + dx, from.dy + drop * 0.25),
      color,
      width,
    );
  }

  /// Head-and-shoulders base shared by the three people. Returns nothing; the
  /// face is drawn on top by the caller.
  static void _bust(
    Canvas canvas, {
    required Color shoulders,
    required Color skin,
    required double shoulderInset,
    required double neckTop,
  }) {
    canvas.drawPath(
      Path()
        ..moveTo(shoulderInset, _unit)
        ..lineTo(shoulderInset, 226)
        ..arcToPoint(
          Offset(_unit - shoulderInset, 226),
          radius: Radius.circular((_unit - shoulderInset * 2) / 2),
        )
        ..lineTo(_unit - shoulderInset, _unit)
        ..close(),
      _fill(shoulders),
    );
    canvas.drawRect(Rect.fromLTWH(114, neckTop, 28, 28), _fill(skin));
  }

  // ── animals ───────────────────────────────────────────────────────────────

  static void cat(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color cream = Color(0xFFF2E2CE);
      const Color ink = Color(0xFF2A3340);
      _bg(c, const Color(0xFF1F6F63));
      _tri(c, const Offset(74, 106), const Offset(84, 50), const Offset(126, 84), cream);
      _tri(c, const Offset(182, 106), const Offset(172, 50), const Offset(130, 84), cream);
      _tri(c, const Offset(85, 97), const Offset(90, 68), const Offset(111, 85), const Color(0xFFE0968E));
      _tri(c, const Offset(171, 97), const Offset(166, 68), const Offset(145, 85), const Color(0xFFE0968E));
      c.drawCircle(const Offset(128, 140), 62, _fill(cream));
      _eye(c, const Offset(105, 134), 8.5, 8.5, lid, ink);
      _eye(c, const Offset(151, 134), 8.5, 8.5, lid, ink);
      _tri(c, const Offset(121, 155), const Offset(135, 155), const Offset(128, 163), const Color(0xFFE07A6B));
      _muzzleMouth(c, const Offset(128, 163), 21, 12, ink, 4.5);
      final Paint whisker = _stroke(ink.withValues(alpha: 0.5), 3.5);
      c.drawLine(const Offset(62, 138), const Offset(92, 143), whisker);
      c.drawLine(const Offset(62, 156), const Offset(92, 153), whisker);
      c.drawLine(const Offset(194, 138), const Offset(164, 143), whisker);
      c.drawLine(const Offset(194, 156), const Offset(164, 153), whisker);
    });
  }

  static void fox(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color coat = Color(0xFFE8813F);
      const Color ink = Color(0xFF2A2320);
      _bg(c, const Color(0xFFB4552C));
      _tri(c, const Offset(70, 112), const Offset(78, 48), const Offset(124, 84), coat);
      _tri(c, const Offset(186, 112), const Offset(178, 48), const Offset(132, 84), coat);
      _tri(c, const Offset(82, 100), const Offset(86, 66), const Offset(108, 84), const Color(0xFFF6C9A0));
      _tri(c, const Offset(174, 100), const Offset(170, 66), const Offset(148, 84), const Color(0xFFF6C9A0));
      c.drawPath(
        Path()
          ..moveTo(128, 78)
          ..arcToPoint(const Offset(190, 140), radius: const Radius.circular(62))
          ..quadraticBezierTo(190, 184, 128, 206)
          ..quadraticBezierTo(66, 184, 66, 140)
          ..arcToPoint(const Offset(128, 78), radius: const Radius.circular(62))
          ..close(),
        _fill(coat),
      );
      c.drawPath(
        Path()
          ..moveTo(128, 130)
          ..quadraticBezierTo(88, 136, 88, 164)
          ..quadraticBezierTo(88, 194, 128, 206)
          ..quadraticBezierTo(168, 194, 168, 164)
          ..quadraticBezierTo(168, 136, 128, 130)
          ..close(),
        _fill(const Color(0xFFF8EDE0)),
      );
      _eye(c, const Offset(103, 130), 8.5, 8.5, lid, ink);
      _eye(c, const Offset(153, 130), 8.5, 8.5, lid, ink);
      _tri(c, const Offset(120, 166), const Offset(136, 166), const Offset(128, 176), ink);
    });
  }

  static void panda(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color dark = Color(0xFF2A2E35);
      const Color white = Color(0xFFF7F5F2);
      _bg(c, const Color(0xFF3C6E8F));
      c.drawCircle(const Offset(80, 88), 26, _fill(dark));
      c.drawCircle(const Offset(176, 88), 26, _fill(dark));
      c.drawCircle(const Offset(128, 140), 66, _fill(white));
      for (final (Offset at, double turn) in <(Offset, double)>[
        (const Offset(102, 130), -14),
        (const Offset(154, 130), 14),
      ]) {
        c.save();
        c.translate(at.dx, at.dy);
        c.rotate(turn * math.pi / 180);
        c.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 38, height: 46),
          _fill(dark),
        );
        c.restore();
      }
      _eye(c, const Offset(103, 132), 7, 7, lid, white);
      _eye(c, const Offset(153, 132), 7, 7, lid, white);
      c.drawOval(
        Rect.fromCenter(center: const Offset(128, 164), width: 22, height: 16),
        _fill(dark),
      );
      _muzzleMouth(c, const Offset(128, 172), 19, 11, dark, 4.5);
    });
  }

  static void owl(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color plume = Color(0xFF9B79C4);
      _bg(c, const Color(0xFF6B4E8E));
      _tri(c, const Offset(70, 96), const Offset(92, 62), const Offset(112, 88), plume);
      _tri(c, const Offset(186, 96), const Offset(164, 62), const Offset(144, 88), plume);
      c.drawPath(
        Path()
          ..moveTo(128, 74)
          ..arcToPoint(const Offset(192, 138), radius: const Radius.circular(64))
          ..lineTo(192, 156)
          ..arcToPoint(const Offset(64, 156), radius: const Radius.circular(64))
          ..lineTo(64, 138)
          ..arcToPoint(const Offset(128, 74), radius: const Radius.circular(64))
          ..close(),
        _fill(plume),
      );
      c.drawCircle(const Offset(102, 126), 27, _fill(const Color(0xFFF4EFF9)));
      c.drawCircle(const Offset(154, 126), 27, _fill(const Color(0xFFF4EFF9)));
      _eye(c, const Offset(102, 126), 12, 12, lid, const Color(0xFF2E2440));
      _eye(c, const Offset(154, 126), 12, 12, lid, const Color(0xFF2E2440));
      _tri(c, const Offset(118, 150), const Offset(138, 150), const Offset(128, 166), const Color(0xFFE8A33F));
      _curve(
        c,
        const Offset(100, 186),
        const Offset(128, 202),
        const Offset(156, 186),
        const Color(0xFF7B5AA6),
        7,
      );
    });
  }

  static void bear(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color coat = Color(0xFFC08A57);
      const Color ink = Color(0xFF33261C);
      _bg(c, const Color(0xFF8A5A33));
      c.drawCircle(const Offset(80, 86), 27, _fill(coat));
      c.drawCircle(const Offset(176, 86), 27, _fill(coat));
      c.drawCircle(const Offset(80, 86), 14, _fill(const Color(0xFFE0B489)));
      c.drawCircle(const Offset(176, 86), 14, _fill(const Color(0xFFE0B489)));
      c.drawCircle(const Offset(128, 142), 66, _fill(coat));
      c.drawOval(
        Rect.fromCenter(center: const Offset(128, 166), width: 68, height: 52),
        _fill(const Color(0xFFE8D0B4)),
      );
      _eye(c, const Offset(104, 128), 8.5, 8.5, lid, ink);
      _eye(c, const Offset(152, 128), 8.5, 8.5, lid, ink);
      c.drawOval(
        Rect.fromCenter(center: const Offset(128, 156), width: 24, height: 18),
        _fill(ink),
      );
      _muzzleMouth(c, const Offset(128, 165), 19, 11, ink, 4.5);
    });
  }

  // ── family ────────────────────────────────────────────────────────────────

  static void kiddo(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color ink = Color(0xFF2A3340);
      _bg(c, const Color(0xFFC77E3A));
      _bust(
        c,
        shoulders: const Color(0xFF4C8FBF),
        skin: const Color(0xFFE5B78C),
        shoulderInset: 50,
        neckTop: 168,
      );
      c.drawCircle(const Offset(128, 118), 58, _fill(const Color(0xFF4A3527)));
      c.drawCircle(const Offset(128, 133), 52, _fill(const Color(0xFFF6D6B2)));
      _eye(c, const Offset(109, 130), 7, 7, lid, ink);
      _eye(c, const Offset(147, 130), 7, 7, lid, ink);
      _curve(c, const Offset(112, 152), const Offset(128, 166), const Offset(144, 152), ink, 5);
      final Paint blush = _fill(const Color(0xFFE89A87).withValues(alpha: 0.75));
      c.drawCircle(const Offset(93, 146), 7.5, blush);
      c.drawCircle(const Offset(163, 146), 7.5, blush);
    });
  }

  static void grownup(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color hair = Color(0xFF2E2620);
      const Color ink = Color(0xFF2A2320);
      _bg(c, const Color(0xFF3E7A6B));
      _bust(
        c,
        shoulders: const Color(0xFF26424C),
        skin: const Color(0xFFD9A075),
        shoulderInset: 46,
        neckTop: 166,
      );
      c.drawCircle(const Offset(128, 122), 56, _fill(const Color(0xFFE8B588)));
      c.drawPath(
        Path()
          ..moveTo(74, 116)
          ..arcToPoint(const Offset(182, 116), radius: const Radius.circular(54))
          ..quadraticBezierTo(174, 82, 128, 82)
          ..quadraticBezierTo(82, 82, 74, 116)
          ..close(),
        _fill(hair),
      );
      c.drawPath(
        Path()
          ..moveTo(74, 116)
          ..quadraticBezierTo(68, 142, 80, 150)
          ..quadraticBezierTo(76, 128, 80, 116)
          ..close(),
        _fill(hair),
      );
      c.drawPath(
        Path()
          ..moveTo(182, 116)
          ..quadraticBezierTo(188, 142, 176, 150)
          ..quadraticBezierTo(180, 128, 176, 116)
          ..close(),
        _fill(hair),
      );
      _eye(c, const Offset(109, 126), 7, 7, lid, ink);
      _eye(c, const Offset(147, 126), 7, 7, lid, ink);
      _curve(c, const Offset(114, 150), const Offset(128, 161), const Offset(142, 150), ink, 5);
      _curve(c, const Offset(96, 106), const Offset(108, 99), const Offset(120, 104), hair, 6);
      _curve(c, const Offset(136, 104), const Offset(148, 99), const Offset(160, 106), hair, 6);
    });
  }

  static void sage(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color silver = Color(0xFFD8DCE2);
      const Color ink = Color(0xFF2A2320);
      _bg(c, const Color(0xFF5C6B8A));
      _bust(
        c,
        shoulders: const Color(0xFF7C4F4F),
        skin: const Color(0xFFDCA98A),
        shoulderInset: 46,
        neckTop: 166,
      );
      c.drawCircle(const Offset(128, 122), 56, _fill(const Color(0xFFEFC7A4)));
      c.drawPath(
        Path()
          ..moveTo(72, 118)
          ..arcToPoint(const Offset(184, 118), radius: const Radius.circular(56))
          ..quadraticBezierTo(180, 78, 128, 78)
          ..quadraticBezierTo(76, 78, 72, 118)
          ..close(),
        _fill(silver),
      );
      c.drawPath(
        Path()
          ..moveTo(72, 118)
          ..quadraticBezierTo(64, 142, 76, 150)
          ..quadraticBezierTo(72, 130, 76, 118)
          ..close(),
        _fill(silver),
      );
      c.drawPath(
        Path()
          ..moveTo(184, 118)
          ..quadraticBezierTo(192, 142, 180, 150)
          ..quadraticBezierTo(184, 130, 180, 118)
          ..close(),
        _fill(silver),
      );
      _eye(c, const Offset(107, 128), 6, 6, lid, ink);
      _eye(c, const Offset(151, 128), 6, 6, lid, ink);
      final Paint frame = _stroke(const Color(0xFF4A4034), 4.5);
      c.drawCircle(const Offset(107, 128), 17, frame);
      c.drawCircle(const Offset(151, 128), 17, frame);
      c.drawLine(const Offset(124, 128), const Offset(132, 128), frame);
      _curve(c, const Offset(112, 158), const Offset(128, 170), const Offset(144, 158), ink, 5);
      c.drawPath(
        Path()
          ..moveTo(104, 168)
          ..quadraticBezierTo(128, 190, 152, 168)
          ..quadraticBezierTo(128, 178, 104, 168)
          ..close(),
        _fill(silver),
      );
    });
  }

  // ── funny ─────────────────────────────────────────────────────────────────

  static void ghost(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color ink = Color(0xFF2A2450);
      _bg(c, const Color(0xFF4C3F8F));
      final Path body = Path()
        ..moveTo(64, 214)
        ..lineTo(64, 126)
        ..arcToPoint(const Offset(192, 126), radius: const Radius.circular(64));
      double x = 192;
      while (x > 64.5) {
        body.quadraticBezierTo(x - 16, 232, x - 32, 214);
        x -= 32;
      }
      c.drawPath(body..close(), _fill(const Color(0xFFF4F1FA)));
      _eye(c, const Offset(106, 126), 9, 12, lid, ink);
      _eye(c, const Offset(150, 126), 9, 12, lid, ink);
      c.drawOval(
        Rect.fromCenter(center: const Offset(128, 158), width: 22, height: 16),
        _fill(ink),
      );
      final Paint blush = _fill(const Color(0xFFC9A8E8).withValues(alpha: 0.55));
      c.drawCircle(const Offset(88, 152), 8, blush);
      c.drawCircle(const Offset(168, 152), 8, blush);
    });
  }

  static void blob(Canvas canvas, Size size, double t) {
    _scaled(canvas, size, (c) {
      final double lid = _lid(t);
      const Color skin = Color(0xFF5FCB8E);
      const Color ink = Color(0xFF20402F);
      _bg(c, const Color(0xFF2E6B4F));
      final Paint stalk = _stroke(skin, 7);
      c.drawLine(const Offset(96, 70), const Offset(104, 48), stalk);
      c.drawLine(const Offset(150, 64), const Offset(164, 46), stalk);
      c.drawCircle(const Offset(104, 44), 7, _fill(skin));
      c.drawCircle(const Offset(166, 42), 7, _fill(skin));
      c.drawPath(
        Path()
          ..moveTo(128, 58)
          ..quadraticBezierTo(184, 58, 194, 106)
          ..quadraticBezierTo(204, 154, 172, 182)
          ..quadraticBezierTo(140, 210, 84, 192)
          ..quadraticBezierTo(50, 174, 52, 130)
          ..quadraticBezierTo(54, 80, 94, 66)
          ..quadraticBezierTo(111, 58, 128, 58)
          ..close(),
        _fill(skin),
      );
      c.drawCircle(const Offset(104, 126), 20, _fill(const Color(0xFFF6FBF7)));
      c.drawCircle(const Offset(154, 122), 15, _fill(const Color(0xFFF6FBF7)));
      _eye(c, const Offset(107, 129), 9, 9, lid, ink);
      _eye(c, const Offset(156, 124), 7, 7, lid, ink);
      _curve(c, const Offset(100, 164), const Offset(128, 190), const Offset(156, 162), ink, 6);
    });
  }
}
