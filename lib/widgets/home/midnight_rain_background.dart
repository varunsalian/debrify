import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'animated_weather_background.dart';

/// A fixed photographic skyline. Rain is batched by depth rather than drawn
/// as hundreds of widgets, blurred layers, or per-drop gradient shaders.
class MidnightRainBackground extends StatelessWidget {
  const MidnightRainBackground({super.key, this.lowPower = false});

  final bool lowPower;

  @override
  Widget build(BuildContext context) => AnimatedWeatherBackground(
    assetPath: 'assets/images/home_midnight_rain.jpg',
    assetSize: const Size(1672, 941),
    lowPower: lowPower,
    bottomShade: const Color(0xB003090E),
    alignment: const Alignment(0.26, 0),
    painterFactory: _RainPainter.new,
  );
}

class _RainPainter extends WeatherPainter {
  _RainPainter(this.time) : super(repaint: time);

  final ValueNotifier<double> time;
  final _random = math.Random(72);
  final _fogPaint = Paint();
  final _lightPaint = Paint();
  final _glowPaint = Paint()
    ..color = const Color(0x09BEDAEC)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  final _splashPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  final _rainPaints = [
    Paint()
      ..color = const Color(0x17B9D7EA)
      ..strokeWidth = 0.5,
    Paint()
      ..color = const Color(0x2CB9D7EA)
      ..strokeWidth = 0.85,
    Paint()
      ..color = const Color(0x49B9D7EA)
      ..strokeWidth = 1.15,
  ];
  List<Float32List> _points = [];
  Size? _size;
  ui.Shader? _fogShader;
  ui.Shader? _lightShader;
  Rect _fogRect = Rect.zero;
  double _nextLightning = 8;
  double _lightningStart = -100;

  // Preserve foreground streaks and the three depth bands on every device.
  // Only narrow phone windows reduce density; TV keeps the full composition.
  static final _drops = List.generate(3, (layer) {
    final random = math.Random(71 + layer);
    return List.generate(const [240, 140, 40][layer], (_) {
      final z = switch (layer) {
        0 => random.nextDouble() * 0.48,
        1 => 0.48 + random.nextDouble() * 0.39,
        _ => 0.87 + random.nextDouble() * 0.13,
      };
      return (
        x: random.nextDouble(),
        y: random.nextDouble(),
        z: z,
        speed: 250 + z * z * 640,
        length: 6 + z * z * 35,
      );
    });
  });
  static final _splashes = List.generate(28, (i) {
    final random = math.Random(i + 101);
    return (
      x: random.nextDouble(),
      y: 0.78 + random.nextDouble() * 0.22,
      phase: random.nextDouble() * 3,
    );
  });

  void _resize(Size size) {
    _fogShader?.dispose();
    _lightShader?.dispose();
    _size = size;
    final counts = size.width < 600
        ? const [140, 90, 30]
        : const [240, 140, 40];
    // Reuse the native point buffers at every tick; no per-frame lists or
    // individual particle shaders. Two coordinates per point, two per streak.
    _points = [for (final count in counts) Float32List(count * 4)];
    _fogRect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 1.5,
      height: size.height * 0.25,
    );
    _fogShader = const RadialGradient(
      colors: [Color(0x219DB8C6), Color(0x1286A5B9), Color(0x0086A5B9)],
      stops: [0, 0.45, 1],
    ).createShader(_fogRect);
    _lightShader =
        const RadialGradient(
          colors: [Color(0xFFA7CDDD), Color(0x00A7CDDD)],
        ).createShader(
          Rect.fromCenter(
            center: Offset(size.width * 0.78, size.height * 0.05),
            width: size.width * 1.5,
            height: size.height * 1.3,
          ),
        );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (_size != size) _resize(size);
    final t = time.value;
    // Gentle cloud illumination, not a full-screen strobe. Never above 13%
    // opacity; each event lasts 1.6s with at least 16s before the next one.
    if (t >= _nextLightning) {
      _lightningStart = t;
      _nextLightning = t + 16 + _random.nextDouble() * 14;
    }
    final lightAge = t - _lightningStart;
    if (lightAge >= 0 && lightAge < 1.6) {
      _lightPaint
        ..shader = _lightShader
        ..color = Colors.white.withValues(
          alpha: math.sin(lightAge / 1.6 * math.pi) * 0.13,
        );
      canvas.drawRect(Offset.zero & size, _lightPaint);
    }
    // Calm ambient rain, with the same depth and streak angles. Keep fog
    // and lightning on their own clock so their cadence is unchanged.
    final rainTime = t * 0.28;
    final gust = math.sin(rainTime * 0.24) * 18 + math.sin(rainTime * 0.63) * 5;
    // Integrate gust velocity so changing wind never teleports the rain.
    final drift =
        18 / 0.24 * (math.cos(rainTime * 0.24) - 1) +
        5 / 0.63 * (math.cos(rainTime * 0.63) - 1);
    for (var layer = 0; layer < 3; layer++) {
      final points = _points[layer];
      for (var i = 0; i < points.length ~/ 4; i++) {
        final drop = _drops[layer][i];
        final wind = -34 - drop.z * 52;
        final x =
            (drop.x * size.width + wind * rainTime + drift) %
                (size.width + 80) -
            40;
        final y =
            (drop.y * size.height + drop.speed * rainTime) %
                (size.height + 100) -
            50;
        final dx = (wind - gust) / drop.speed * drop.length;
        final offset = i * 4;
        points[offset] = x - dx;
        points[offset + 1] = y - drop.length;
        points[offset + 2] = x;
        points[offset + 3] = y;
      }
      canvas.drawRawPoints(ui.PointMode.lines, points, _rainPaints[layer]);
      if (layer == 0) {
        _fogPaint.shader = _fogShader;
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(
            size.width * (0.45 + math.sin(t * 0.033 + i * 2) * 0.2),
            size.height * (0.39 + i * 0.19),
          );
          canvas.drawOval(_fogRect, _fogPaint);
          canvas.restore();
        }
      }
    }
    // A faint wider pass gives the closest streaks soft edges without blur.
    canvas.drawRawPoints(ui.PointMode.lines, _points[2], _glowPaint);
    for (final splash in _splashes) {
      final age = (t + splash.phase) % 1.65;
      if (age > 0.55) continue;
      _splashPaint.color = const Color(
        0xFFB5D3DF,
      ).withValues(alpha: (1 - age / 0.55) * 0.1);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(splash.x * size.width, splash.y * size.height),
          width: age * 20,
          height: age * 4.4,
        ),
        _splashPaint,
      );
    }
  }

  @override
  void dispose() {
    _fogShader?.dispose();
    _lightShader?.dispose();
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) => oldDelegate.time != time;
}
