import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'animated_weather_background.dart';

/// One image sample per pixel, with no blur, offscreen textures or per-wave
/// widgets. The shared weather clock pauses when browsing is not visible.
class MoonlitOceanBackground extends StatelessWidget {
  const MoonlitOceanBackground({super.key, this.lowPower = false});

  final bool lowPower;
  static const assetPath = 'assets/images/home_moonlit_ocean.jpg';

  @override
  Widget build(BuildContext context) => AnimatedWeatherBackground(
    assetPath: assetPath,
    assetSize: const Size(1659, 948),
    lowPower: lowPower,
    alignment: Alignment.center,
    bottomShade: const Color(0x60030910),
    backgroundBuilder: (width, time) =>
        _OceanSurface(decodeWidth: width, time: time),
  );
}

class _OceanSurface extends StatefulWidget {
  const _OceanSurface({required this.decodeWidth, required this.time});

  final int decodeWidth;
  final ValueNotifier<double> time;

  @override
  State<_OceanSurface> createState() => _OceanSurfaceState();
}

class _OceanSurfaceState extends State<_OceanSurface> {
  // Cache the program, not shader instances: each visible surface owns its
  // uniforms and image sampler. Unsupported renderers retain the photograph.
  static final Future<ui.FragmentProgram?> _program = _loadProgram();
  static Future<ui.FragmentProgram?> _loadProgram() async {
    try {
      return await ui.FragmentProgram.fromAsset(
        'assets/shaders/moonlit_ocean.frag',
      );
    } catch (_) {
      return null;
    }
  }

  ImageStream? _stream;
  ImageInfo? _image;
  ui.FragmentShader? _shader;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(
      _onImage,
      onError: (Object _, StackTrace? __) {
        // A failed resize keeps the previous image; initial failure stays dark.
      },
    );
    _program.then((program) {
      if (!mounted || program == null) return;
      setState(() => _shader = program.fragmentShader());
    });
  }

  void _onImage(ImageInfo image, bool synchronous) {
    final previous = _image;
    setState(() => _image = image);
    previous?.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(_OceanSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decodeWidth != widget.decodeWidth) _resolveImage();
  }

  void _resolveImage() {
    final next = ResizeImage(
      const AssetImage(MoonlitOceanBackground.assetPath),
      width: widget.decodeWidth,
    ).resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = next..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _shader?.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _OceanPainter(widget.time, _image?.image, _shader));
}

class _OceanPainter extends CustomPainter {
  _OceanPainter(this.time, this.image, this.shader) : super(repaint: time);

  final ValueNotifier<double> time;
  final ui.Image? image;
  final ui.FragmentShader? shader;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final photograph = image;
    final effect = shader;
    if (photograph == null) {
      canvas.drawColor(const Color(0xFF050E18), BlendMode.src);
      return;
    }
    if (effect == null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: photograph,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      return;
    }
    effect
      ..setFloat(0, time.value)
      ..setFloat(1, size.width)
      ..setFloat(2, size.height)
      ..setFloat(3, photograph.width / photograph.height)
      ..setImageSampler(0, photograph);
    _paint.shader = effect;
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(_OceanPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.shader != shader ||
      oldDelegate.time != time;
}
