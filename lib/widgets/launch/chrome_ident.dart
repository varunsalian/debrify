import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// Liquid Chrome — AAA title energy. The name slams in at full weight in
/// mirrored chrome with a hard horizon cut, the camera kicks on impact, and
/// one white shine rolls off the metal.
///
/// TV notes: the chrome is a banded gradient baked into the letter set (one
/// shader in letter-local space); the shine is a clip-band redraw of a
/// pre-laid-out near-white set; echo ghosts and the reflection are
/// alpha-baked sets. The shake is progress-derived noise in a bounded
/// window. Zero saveLayer.
///
/// Timeline: 0–.22 slam (echo ghosts) · .22–.36 impact shake ·
/// .26–.50 mark docks in · .46–.76 shine · .78–.98 glint · rest.
class ChromeIdent extends LaunchIdent {
  const ChromeIdent();

  @override
  String get id => 'chrome';
  @override
  String get label => 'Liquid Chrome';
  @override
  String get subtitle =>
      'Heavyweight mirror-chrome slam with a rolling white shine';
  @override
  Duration get revealDuration => const Duration(milliseconds: 2400);
  @override
  Color get baseColor => const Color(0xFF05070E);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        // Studio backdrop with a hard floor line at 72%.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D1220),
            Color(0xFF05070E),
            Color(0xFF0A0E1A),
            Color(0xFF04050B),
          ],
          stops: [0.0, 0.72, 0.721, 1.0],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFFC7D2E8), Color(0xFFF4F8FF)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
    IdentPalette? palette,
  }) =>
      _ChromePainter(animation, isTelevision: isTelevision);
}

class _ChromePainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _size;
  IdentWordLayout? _word;
  late double _startX, _baseY, _g;
  late Path _mark;
  late Rect _markRect;
  late Shader _markShader;
  late List<TextPainter> _chrome;
  late List<TextPainter> _keyline;
  late List<TextPainter> _shine;
  late List<TextPainter> _echo;
  late List<TextPainter> _refl;

  _ChromePainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  static const _chromeStops = [
    Color(0xFFF4F8FF),
    Color(0xFFC7D2E8),
    Color(0xFF56627E),
    Color(0xFF232B3E),
    Color(0xFF8A96B4),
    Color(0xFFE6ECFA),
  ];
  static const _bandStops = [0.0, 0.42, 0.46, 0.50, 0.56, 1.0];

  Shader _chromeShader(double fz, {double alpha = 1}) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final c in _chromeStops) c.withValues(alpha: c.a * alpha),
        ],
        stops: _bandStops,
      ).createShader(Rect.fromLTRB(-40, -fz * 0.9, 40, fz * 0.12));

  void _layout(Size size) {
    if (_word != null && _size == size) return;
    _size = size;
    final w = size.width, h = size.height;
    _word = IdentWordLayout.fit(
      styleFor: (fz) => TextStyle(
        fontSize: fz,
        fontWeight: FontWeight.w900,
        height: 1.0,
        color: const Color(0xFFE6ECFA),
      ),
      fontSize: h * 0.20,
      trackingFactor: 0.03,
      maxWidth: w * 0.76,
      scaleX: 1.10,
    );
    _startX = w / 2 - _word!.width / 2;
    _baseY = h * 0.56;
    _g = h * 0.11;
    _mark = identPlayPath(_g);
    _markRect = Rect.fromLTRB(0, -_g / 2, 0, _g / 2);
    _markShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _chromeStops,
      stops: _bandStops,
    ).createShader(_markRect);

    final fz = _word!.fontSize;
    _chrome = _word!.set(
      'chrome',
      (s) => s.copyWith(foreground: Paint()..shader = _chromeShader(fz)),
    );
    _keyline = _word!.set(
      'keyline',
      (s) => s.copyWith(
        color: null,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF070B16),
      ),
    );
    _shine = _word!.set(
      'shine',
      (s) => s.copyWith(color: const Color(0xFFFFFFFF).withValues(alpha: .9)),
    );
    _echo = _word!.set(
      'echo',
      (s) => s.copyWith(
        foreground: Paint()..shader = _chromeShader(fz, alpha: 0.12),
      ),
    );
    _refl = _word!.set(
      'refl',
      (s) => s.copyWith(
        foreground: Paint()..shader = _chromeShader(fz, alpha: 0.10),
      ),
    );
  }

  void _paintWordGroup(
    Canvas canvas,
    List<TextPainter> set, {
    double groupScale = 1,
  }) {
    final word = _word!;
    canvas.save();
    if (groupScale != 1) {
      final cx = _startX + word.width / 2;
      final cy = _baseY - word.fontSize * 0.35;
      canvas.translate(cx, cy);
      canvas.scale(groupScale, groupScale);
      canvas.translate(-cx, -cy);
    }
    for (int i = 0; i < kIdentWord.length; i++) {
      word.paintLetter(canvas, set, i, _startX, _baseY);
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    _layout(size);
    final word = _word!;

    if (t < 0.02) return; // one dark beat before the slam

    // Impact shake — progress-derived, bounded window.
    double shx = 0, shy = 0;
    if (t > 0.22 && t < 0.36) {
      final sh = (1 - (t - 0.22) / 0.14) * 4;
      shx = (identNoise((t * 120).floorToDouble()) - 0.5) * 2 * sh;
      shy = (identNoise((t * 120).floorToDouble() + 9) - 0.5) * 2 * sh;
    }
    canvas.save();
    canvas.translate(shx, shy);

    final imp = identClamp(t / 0.22, 0, 1);
    final scale = identLerp(2.1, 1, identInCubic(imp));
    if (imp < 1) {
      // Echo ghosts trailing the slam.
      _paintWordGroup(canvas, _echo, groupScale: scale * 1.16);
      _paintWordGroup(canvas, _echo, groupScale: scale * 1.08);
    }
    _paintWordGroup(canvas, _chrome, groupScale: scale);
    if (imp >= 1) _paintWordGroup(canvas, _keyline);

    // Rolling shine: a rotated clip band reveals the near-white set.
    final sp = identClamp((t - 0.46) / 0.30, 0, 1);
    if (sp > 0 && sp < 1) {
      final x =
          identLerp(_startX - 120, _startX + word.width + 120, identIoSine(sp));
      canvas.save();
      final band = Path()
        ..moveTo(x - 55, _baseY + word.fontSize * 0.15)
        ..lineTo(x + 15, _baseY + word.fontSize * 0.15)
        ..lineTo(x + 55, _baseY - word.fontSize * 1.05)
        ..lineTo(x - 15, _baseY - word.fontSize * 1.05)
        ..close();
      canvas.clipPath(band);
      _paintWordGroup(canvas, _shine);
      canvas.restore();
    }

    // Floor reflection.
    canvas.save();
    canvas.translate(0, (_baseY + word.fontSize * 0.14) * 2);
    canvas.scale(1, -0.5);
    _paintWordGroup(canvas, _refl);
    canvas.restore();

    // Chrome mark docks in above the word, left-aligned to the D.
    final mk = identOutCubic(identClamp((t - 0.26) / 0.24, 0, 1));
    if (mk > 0) {
      canvas.save();
      canvas.translate(
        _startX + _g * 0.5 + (1 - mk) * -60,
        _baseY - word.fontSize - _g * 0.35,
      );
      // Cached shader once docked; alpha-baked rebuild only during the short
      // slide-in ramp (shader+Paint.color fades are backend-dependent).
      canvas.drawPath(
        _mark,
        Paint()
          ..shader = mk >= 1
              ? _markShader
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    for (final c in _chromeStops)
                      c.withValues(alpha: c.a * mk),
                  ],
                  stops: _bandStops,
                ).createShader(_markRect),
      );
      canvas.drawPath(
        _mark,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF070B16).withValues(alpha: mk),
      );
      canvas.restore();
    }

    // Glint star on the Y.
    final gl = identClamp((t - 0.78) / 0.20, 0, 1);
    if (gl > 0 && gl < 1) {
      final s = sin(gl * pi);
      final gx = _startX + word.width - word.widths[6] * 0.2;
      final gy = _baseY - word.fontSize * 0.82;
      canvas.save();
      canvas.translate(gx, gy);
      canvas.rotate(gl * 0.6);
      final p = Paint()
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.9 * s);
      final r = 14 * s;
      canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
      canvas.drawLine(Offset(0, -r), Offset(0, r), p);
      canvas.drawLine(Offset(-r * .4, -r * .4), Offset(r * .4, r * .4), p);
      canvas.drawLine(Offset(r * .4, -r * .4), Offset(-r * .4, r * .4), p);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChromePainter old) =>
      old.animation != animation;
}
