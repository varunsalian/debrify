import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A viewport-fixed landscape with independently painted snow and mist.
/// Its clock never rebuilds the image, hero, or scrolling shelves.
class SnowyMountainBackground extends StatefulWidget {
  const SnowyMountainBackground({super.key, this.lowPower = false});

  /// Conservative rendering budget for TVs; the UI keeps its normal cadence.
  final bool lowPower;

  @override
  State<SnowyMountainBackground> createState() =>
      _SnowyMountainBackgroundState();
}

class _SnowyMountainBackgroundState extends State<SnowyMountainBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _previous = Duration.zero;
  double _pendingSeconds = 0;
  late final _SnowPainter _painter;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _painter = _SnowPainter(_time);
    _ticker = createTicker((elapsed) {
      final delta = elapsed - _previous;
      _previous = elapsed;
      _pendingSeconds += (delta.inMicroseconds / 1000000).clamp(0.0, 0.05);
      if (!widget.lowPower || _pendingSeconds >= 1 / 30 - 0.0001) {
        _time.value += _pendingSeconds;
        _pendingSeconds = 0;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateClock();
  }

  void _updateClock() {
    final active =
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (active && !_ticker.isActive) {
      _previous = Duration.zero;
      _pendingSeconds = 0;
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _painter.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cover-crop may be height-limited. Include that dimension so tall
            // windows never decode a blurry background; never upscale the asset.
            final ratio = MediaQuery.devicePixelRatioOf(context);
            final decodeWidth =
                (math.max(
                          constraints.maxWidth,
                          constraints.maxHeight * 1672 / 941,
                        ) *
                        ratio)
                    .ceil()
                    .clamp(1, 1672);
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: Image.asset(
                      'assets/images/home_snowy_mountain.jpg',
                      cacheWidth: decodeWidth,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.3, 0),
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFF07111E)),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xB8030A15), Color(0x00030A15)],
                        stops: [0, 0.85],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x1807111E), Color(0xD907111E)],
                      ),
                    ),
                  ),
                  RepaintBoundary(child: CustomPaint(painter: _painter)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SnowPainter extends CustomPainter {
  _SnowPainter(this.time) : super(repaint: time) {
    // Rasterize the soft foreground flake once, not one radial shader per
    // flake per frame. 64px retains smooth edges above the maximum draw size.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, 64, 64);
    canvas.drawCircle(
      const Offset(32, 32),
      32,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x73E6F4FF), Color(0x00E6F4FF)],
        ).createShader(rect),
    );
    final picture = recorder.endRecording();
    _softFlake = picture.toImageSync(64, 64);
    picture.dispose();
  }

  late final ui.Image _softFlake;
  final _paint = Paint();
  final _spritePaint = Paint()..filterQuality = FilterQuality.low;
  Size? _mistSize;
  ui.Shader? _mistShader;

  void dispose() => _softFlake.dispose();

  final ValueNotifier<double> time;
  static final _flakes = List.generate(180, (i) {
    final random = math.Random(i * 79 + 17);
    return (
      x: random.nextDouble(),
      y: random.nextDouble(),
      depth: random.nextDouble(),
      phase: random.nextDouble() * math.pi * 2,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = time.value;
    final paint = _paint..color = Colors.white;
    if (_mistSize != size) {
      _mistSize = size;
      _mistShader =
          const RadialGradient(
            colors: [Color(0x1FACCADC), Color(0x00ACCADC)],
          ).createShader(
            Rect.fromCenter(
              center: Offset.zero,
              width: size.width * 1.6,
              height: size.height * 0.32,
            ),
          );
    }
    // Broad translucent gradients give drifting mist without blur/saveLayer.
    for (var i = 0; i < 2; i++) {
      final center = Offset(
        size.width * (0.5 + math.sin(t * 0.045 + i * 2) * 0.2),
        size.height * (0.43 + i * 0.19),
      );
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 1.6,
        height: size.height * 0.32,
      );
      paint.shader = _mistShader;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.drawOval(rect, paint);
      canvas.restore();
    }
    paint.shader = null;
    // Integrated wind yields continuous gusts, with no jumps when it changes.
    final wind =
        14 * t - 24 / 0.22 * math.cos(t * 0.22) - 8 / 0.61 * math.cos(t * 0.61);
    final count = size.width < 600 ? 100 : _flakes.length;
    for (final f in _flakes.take(count)) {
      final z = f.depth;
      final x =
          (f.x * size.width +
                  wind * (0.3 + z) +
                  math.sin(t * 0.7 + f.phase) * 13) %
              (size.width + 24) -
          12;
      final y =
          (f.y * size.height + t * (12 + z * z * 62)) % (size.height + 24) - 12;
      final radius = 0.5 + z * z * 3.4;
      final center = Offset(x, y);
      if (z > 0.86) {
        final rect = Rect.fromCircle(center: center, radius: radius * 2.5);
        canvas.drawImageRect(
          _softFlake,
          const Rect.fromLTWH(0, 0, 64, 64),
          rect,
          _spritePaint,
        );
      } else {
        paint.color = const Color(
          0xFFE0F0FF,
        ).withValues(alpha: 0.14 + z * 0.46);
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: radius * 1.4,
            height: radius * 2,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SnowPainter oldDelegate) => oldDelegate.time != time;
}
