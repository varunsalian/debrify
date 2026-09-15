import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shared, lifecycle-aware weather clock. Only the particle layer repaints;
/// the decoded photograph and the browsing UI remain independently cached.
class AnimatedWeatherBackground extends StatefulWidget {
  const AnimatedWeatherBackground({
    super.key,
    required this.assetPath,
    required this.assetSize,
    required this.painterFactory,
    this.lowPower = false,
    this.alignment = const Alignment(0.3, 0),
    this.bottomShade = const Color(0xD907111E),
  });

  final String assetPath;
  final Size assetSize;
  final WeatherPainter Function(ValueNotifier<double>) painterFactory;
  final bool lowPower;
  final Alignment alignment;
  final Color bottomShade;

  @override
  State<AnimatedWeatherBackground> createState() =>
      _AnimatedWeatherBackgroundState();
}

abstract class WeatherPainter extends CustomPainter {
  WeatherPainter({super.repaint});
  void dispose() {}
}

class _AnimatedWeatherBackgroundState extends State<AnimatedWeatherBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _previous = Duration.zero;
  double _pendingSeconds = 0;
  late WeatherPainter _painter;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _painter = widget.painterFactory(_time);
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
  void didUpdateWidget(AnimatedWeatherBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assetPath != oldWidget.assetPath) {
      _painter.dispose();
      _painter = widget.painterFactory(_time);
    }
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
                          constraints.maxHeight * widget.assetSize.aspectRatio,
                        ) *
                        ratio)
                    .ceil()
                    .clamp(1, widget.assetSize.width.toInt());
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: Image.asset(
                      widget.assetPath,
                      cacheWidth: decodeWidth,
                      fit: BoxFit.cover,
                      alignment: widget.alignment,
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
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0x1807111E), widget.bottomShade],
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
