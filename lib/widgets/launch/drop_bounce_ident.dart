import 'dart:math';

import 'package:flutter/material.dart';

import 'launch_ident.dart';

/// The shipped reveal, unchanged: the play mark drops in with real weight (an
/// ease-out bounce), squashing on each contact — and the landing shakes the
/// DEBRIFY letters loose so they pop up one by one. Moved here verbatim from
/// app_initializer.dart when the splash became selectable; the default must
/// stay pixel-identical.
///
/// Timeline (progress 0..1):
///   0.00 – 0.52   Drop — mark falls and bounces to rest (contacts ~.36/.73/.91)
///   0.20 – ~0.75  Shake loose — letters pop up on a damped hop, staggered
///   0.75 – 1.00   Rest
class DropBounceIdent extends LaunchIdent {
  const DropBounceIdent();

  @override
  String get id => 'drop';
  @override
  String get label => 'Drop & Bounce';
  @override
  String get subtitle => 'The original — the mark lands with weight and '
      'shakes the letters loose';
  @override
  Duration get revealDuration => const Duration(milliseconds: 1100);
  @override
  Color get baseColor => const Color(0xFF020617);
  @override
  BoxDecoration get backdrop => const BoxDecoration(
        // Subtle radial lift in the backdrop reads richer than flat black —
        // verbatim the DecoratedBox the splash has always drawn.
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [Color(0xFF0B1026), Color(0xFF020617)],
          stops: [0.0, 0.9],
        ),
      );
  @override
  List<Color> get sweepColors =>
      const [Color(0xFF7B5CFF), Color(0xFF818CF8)];

  @override
  CustomPainter createPainter(
    Animation<double> animation, {
    required bool Function() isTelevision,
  }) =>
      DropBouncePainter(animation, isTelevision: isTelevision);
}

class DropBouncePainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() isTelevision;

  Size? _layoutSize;
  _DropBounceLayout? _cachedLayout;

  DropBouncePainter(this.animation, {required this.isTelevision})
      : super(repaint: animation);

  static const LinearGradient _glyphGradient = LinearGradient(
    colors: [Color(0xFF4F74FF), Color(0xFF6E6BFF), Color(0xFF8A5CFF)],
    stops: [0, 0.5, 1],
  );

  List<TextPainter> _layoutLetters(double fontSize) {
    return kIdentWord.split('').map((ch) {
      final tp = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE9EDFF),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    }).toList();
  }

  _DropBounceLayout _layoutFor(Size size) {
    final cached = _cachedLayout;
    if (cached != null && _layoutSize == size) return cached;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final initialBoxHeight = min(w * 0.66, h * 1.7) / 2.15;
    double glyphSize = initialBoxHeight;
    double fontSize = initialBoxHeight * 0.60;
    double letterSpacing = fontSize * 0.11;
    double gap = glyphSize * 0.20;

    List<TextPainter> letters = _layoutLetters(fontSize);
    double total = 0;
    for (int i = 0; i < letters.length; i++) {
      total += letters[i].width + (i < letters.length - 1 ? letterSpacing : 0);
    }
    double lockWidth = glyphSize + gap + total;

    final maxWidth = w * 0.86;
    if (lockWidth > maxWidth) {
      final scale = maxWidth / lockWidth;
      glyphSize *= scale;
      fontSize *= scale;
      letterSpacing *= scale;
      gap = glyphSize * 0.20;
      letters = _layoutLetters(fontSize);
      total = 0;
      for (int i = 0; i < letters.length; i++) {
        total +=
            letters[i].width + (i < letters.length - 1 ? letterSpacing : 0);
      }
      lockWidth = glyphSize + gap + total;
    }

    final startX = cx - lockWidth / 2;
    final wordX = startX + glyphSize + gap;
    final glyphCenterX = startX + glyphSize / 2;
    final baseY = cy + fontSize * 0.35;

    final centers = <double>[];
    final baselines = <double>[];
    double x = wordX;
    for (int i = 0; i < letters.length; i++) {
      centers.add(x + letters[i].width / 2);
      baselines.add(
        letters[i].computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
      x += letters[i].width + letterSpacing;
    }

    final glyphPath = identPlayPath(glyphSize);
    final innerPath = identPlayPath(glyphSize * 0.52);
    final glyphShader = _glyphGradient.createShader(
      Rect.fromCenter(center: Offset.zero, width: glyphSize, height: glyphSize),
    );

    final layout = _DropBounceLayout(
      centerY: cy,
      glyphCenterX: glyphCenterX,
      baseY: baseY,
      glyphSize: glyphSize,
      fontSize: fontSize,
      letters: letters,
      letterCenters: centers,
      letterBaselines: baselines,
      glyphPath: glyphPath,
      innerPath: innerPath,
      glyphShader: glyphShader,
    );
    _layoutSize = size;
    _cachedLayout = layout;
    return layout;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = animation.value;
    final layout = _layoutFor(size);
    final lightweight = isTelevision();

    // ---- glyph drop + squash ----
    final dt = identClamp(p / 0.52, 0, 1);
    final yoff = identLerp(
      -(size.height * 0.55 + layout.glyphSize),
      0,
      identOutBounce(dt),
    );
    double comp = 0;
    for (final cpair in const [
      [0.363, 1.0],
      [0.727, 0.5],
      [0.909, 0.28],
    ]) {
      comp += cpair[1] * exp(-pow((dt - cpair[0]) / 0.045, 2).toDouble());
    }
    comp = identClamp(comp, 0, 1) * 0.30;
    _drawGlyph(
      canvas,
      layout,
      layout.centerY + yoff,
      1 + comp * 0.85,
      1 - comp,
      0.7 + comp,
      lightweight,
    );

    // ---- letters shaken loose ----
    for (int i = 0; i < layout.letters.length; i++) {
      final st = 0.20 + i * 0.03;
      final lt = identClamp((p - st) / 0.34, 0, 1);
      if (lt <= 0) continue;
      final hop = sin(lt * pi * 1.6) * exp(-4 * lt);
      final scale = identLerp(0.6, 1, identOutBack(identClamp(lt * 1.4, 0, 1)));
      final alpha = identClamp(lt * 1.6, 0, 1);
      // TV avoids seven saveLayer operations per frame. The first few nearly
      // transparent frames are skipped, then the hop/scale motion carries the
      // reveal cleanly without an offscreen alpha surface for every letter.
      if (lightweight && alpha < 0.18) continue;
      _drawLetter(
        canvas,
        layout.letters[i],
        layout.letterBaselines[i],
        layout.letterCenters[i],
        layout.baseY,
        -hop * layout.glyphSize * 0.16,
        scale,
        lightweight ? 1 : alpha,
        layout.fontSize,
      );
    }
  }

  void _drawGlyph(
    Canvas canvas,
    _DropBounceLayout layout,
    double y,
    double scaleX,
    double scaleY,
    double glow,
    bool lightweight,
  ) {
    final glyphSize = layout.glyphSize;
    final path = layout.glyphPath;
    canvas.save();
    canvas.translate(layout.glyphCenterX, y);
    canvas.scale(scaleX, scaleY);
    if (glow > 0) {
      if (lightweight) {
        // Two translucent outlines read as a restrained glow without invoking
        // a large Gaussian blur over a TV-sized glyph.
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = glyphSize * 0.075
            ..color =
                Color.fromRGBO(110, 120, 255, 0.10 * identClamp(glow, 0, 1)),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = glyphSize * 0.035
            ..color =
                Color.fromRGBO(134, 139, 255, 0.20 * identClamp(glow, 0, 1)),
        );
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..color =
                Color.fromRGBO(110, 120, 255, 0.55 * identClamp(glow, 0, 1))
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              glyphSize * 0.12 * glow,
            ),
        );
      }
    }
    canvas.drawPath(path, Paint()..shader = layout.glyphShader);
    // inner sheen for a touch of depth
    canvas.drawPath(
      layout.innerPath,
      Paint()..color = const Color(0xFFDFE6FF).withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  void _drawLetter(
    Canvas canvas,
    TextPainter textPainter,
    double baseline,
    double centerX,
    double baseY,
    double dy,
    double scale,
    double alpha,
    double fontSize,
  ) {
    canvas.save();
    canvas.translate(centerX, baseY + dy);
    canvas.scale(scale, scale);
    final needsLayer = alpha < 0.999;
    if (needsLayer) {
      canvas.saveLayer(
        Rect.fromLTRB(
          -textPainter.width,
          -fontSize * 1.6,
          textPainter.width,
          fontSize * 1.2,
        ),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -baseline));
    if (needsLayer) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DropBouncePainter old) =>
      old.animation != animation || old.isTelevision != isTelevision;
}

class _DropBounceLayout {
  final double centerY;
  final double glyphCenterX;
  final double baseY;
  final double glyphSize;
  final double fontSize;
  final List<TextPainter> letters;
  final List<double> letterCenters;
  final List<double> letterBaselines;
  final Path glyphPath;
  final Path innerPath;
  final Shader glyphShader;

  const _DropBounceLayout({
    required this.centerY,
    required this.glyphCenterX,
    required this.baseY,
    required this.glyphSize,
    required this.fontSize,
    required this.letters,
    required this.letterCenters,
    required this.letterBaselines,
    required this.glyphPath,
    required this.innerPath,
    required this.glyphShader,
  });
}
