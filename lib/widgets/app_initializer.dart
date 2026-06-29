import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import '../services/android_native_downloader.dart';
import '../services/app_migration_service.dart';
import '../services/main_page_bridge.dart';
import '../services/remote_control/remote_control_state.dart';
import '../services/remote_control/remote_command_router.dart';
import '../utils/platform_util.dart';
import '../widgets/initial_setup_flow.dart';
import '../main.dart';

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with TickerProviderStateMixin {
  bool _onboardingComplete = false;
  bool _isAndroidTv = false;

  late AnimationController _revealController;
  late AnimationController _exitController;
  late Animation<double> _exitAnimation;

  ui.Image? _logoImage;
  // Tight content box of the logo art, normalised 0..1. Replaced with the real
  // alpha bounds once the image loads; this is only a fallback.
  Rect _crop = const Rect.fromLTRB(0.06, 0.29, 0.94, 0.71);
  List<_Blob> _blobs = [];
  final Random _rng = Random(42);

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );

    _exitAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _buildBlobs();
    _loadLogo();

    _checkInitializationStatus();
  }

  // The liquid is a small number of metaball "droplets" that bloom out from the
  // centre. One large core droplet guarantees the wordmark fully resolves; the
  // satellites give the spreading edge its organic, undulating shape. Positions
  // are normalised to the logo box so they scale to any screen.
  void _buildBlobs() {
    final blobs = <_Blob>[
      // Core droplet — grows to cover the entire wordmark.
      _Blob(
        nx: 0,
        ny: 0,
        radiusFrac: 0.66,
        phase: 0,
        freq: 0,
        wobble: 0,
      ),
    ];

    const satellites = 11;
    for (int i = 0; i < satellites; i++) {
      final angle = i / satellites * 2 * pi + _rng.nextDouble() * 0.6;
      final spread = sqrt(_rng.nextDouble());
      blobs.add(_Blob(
        nx: cos(angle) * spread,
        ny: sin(angle) * spread * 0.6,
        radiusFrac: 0.18 + _rng.nextDouble() * 0.18,
        phase: _rng.nextDouble() * 2 * pi,
        freq: 2.0 + _rng.nextDouble() * 2.5,
        wobble: 0.02 + _rng.nextDouble() * 0.035,
      ));
    }

    _blobs = blobs;
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/splash_logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      final crop = await _computeContentBounds(frame.image);
      if (!mounted) return;
      setState(() {
        _logoImage = frame.image;
        _crop = crop;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealController.forward();
      });
    } catch (e) {
      debugPrint('AppInitializer: failed to load splash logo: $e');
      // Still run the controller so timing/handoff stays consistent.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealController.forward();
      });
    }
  }

  // Scan the alpha channel for the tight bounding box of visible pixels, so the
  // art is drawn edge-to-edge with no clipping and no dead margin — whatever the
  // asset's framing. Returns a normalised (0..1) rect with a hair of padding.
  Future<Rect> _computeContentBounds(ui.Image img) async {
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return _crop;
      final w = img.width;
      final h = img.height;
      final bytes = data.buffer.asUint8List();
      int minX = w, minY = h, maxX = -1, maxY = -1;
      const step = 2; // sampling stride — plenty for a bounding box
      const alphaThreshold = 12;
      for (int y = 0; y < h; y += step) {
        final rowOffset = y * w * 4;
        for (int x = 0; x < w; x += step) {
          final a = bytes[rowOffset + x * 4 + 3];
          if (a > alphaThreshold) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      if (maxX < minX || maxY < minY) return _crop;
      final padX = w * 0.015;
      final padY = h * 0.015;
      return Rect.fromLTRB(
        ((minX - padX) / w).clamp(0.0, 1.0),
        ((minY - padY) / h).clamp(0.0, 1.0),
        ((maxX + padX) / w).clamp(0.0, 1.0),
        ((maxY + padY) / h).clamp(0.0, 1.0),
      );
    } catch (e) {
      debugPrint('AppInitializer: content-bounds scan failed: $e');
      return _crop;
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    _exitController.dispose();
    _logoImage?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // App initialization logic (unchanged)
  // ---------------------------------------------------------------------------

  Future<void> _checkInitializationStatus() async {
    try {
      _isAndroidTv = await AndroidNativeDownloader.isTelevision();
    } catch (_) {
      _isAndroidTv = false;
    }

    if (_isAndroidTv) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await _startTvListenerEarly();
    }

    await AppMigrationService.runMigrations();

    final hasCompleted = await StorageService.isInitialSetupComplete();

    if (!mounted) return;

    if (!hasCompleted) {
      await Future.delayed(const Duration(milliseconds: 1700));
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      await _showOnboarding();
    } else {
      await Future.delayed(const Duration(milliseconds: 2300));
      if (!mounted) return;
      await _exitController.forward();
      if (!mounted) return;
      setState(() {
        _onboardingComplete = true;
      });
    }
  }

  Future<void> _showOnboarding() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final configured = await InitialSetupFlow.show(context);

    if (!mounted) return;

    await StorageService.setInitialSetupComplete(true);

    if (configured) {
      MainPageBridge.notifyIntegrationChanged();
    }

    await _exitController.forward();
    if (!mounted) return;

    setState(() {
      _onboardingComplete = true;
    });
    _showPendingPostSetupSnackBarIfNeeded();
  }

  void _showPendingPostSetupSnackBarIfNeeded() {
    final message = MainPageBridge.takePostSetupSnackBar();
    if (message == null || message.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _startTvListenerEarly() async {
    try {
      final remoteEnabled = await StorageService.getRemoteControlEnabled();
      if (!remoteEnabled) return;

      var deviceName = await StorageService.getRemoteTvDeviceName();
      deviceName ??= await PlatformUtil.getDeviceName();
      deviceName ??= 'Debrify TV';

      debugPrint('AppInitializer: Starting TV listener early as "$deviceName"');

      await RemoteControlState().startTvListener(deviceName);

      RemoteControlState().onCommandReceived = (action, command, data) {
        RemoteCommandRouter().dispatchCommand(action, command, data);
      };

      debugPrint(
        'AppInitializer: TV listener started - discoverable during onboarding',
      );
    } catch (e) {
      debugPrint('AppInitializer: Failed to start TV listener early: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_onboardingComplete) {
      return const MainPage();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: FadeTransition(
        opacity: _exitAnimation,
        child: DecoratedBox(
          // Subtle radial lift in the backdrop reads richer than flat black.
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.1,
              colors: [Color(0xFF0B1026), Color(0xFF020617)],
              stops: [0.0, 0.9],
            ),
          ),
          child: AnimatedBuilder(
            animation: _revealController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: _LiquidRevealPainter(
                  progress: _revealController.value,
                  blobs: _blobs,
                  logo: _logoImage,
                  crop: _crop,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liquid droplet data
// ---------------------------------------------------------------------------

class _Blob {
  final double nx, ny; // normalised position within the logo box
  final double radiusFrac; // radius at full coverage, as fraction of logo width
  final double phase, freq, wobble; // organic surface undulation

  const _Blob({
    required this.nx,
    required this.ny,
    required this.radiusFrac,
    required this.phase,
    required this.freq,
    required this.wobble,
  });
}

// ---------------------------------------------------------------------------
// Liquid metaball reveal painter
// ---------------------------------------------------------------------------
//
// Timeline (progress 0..1):
//   0.00 – 0.12   Anticipation — a faint core glow gathers
//   0.12 – 0.72   Reveal — liquid metaballs bloom out, unveiling the wordmark
//   0.50 – 0.88   Light-sweep — a diagonal specular highlight crosses the logo
//   0.74 – 0.95   Settle — wet fill recedes, a clean chromatic glow rests
//   0.95 – 1.00   Hold
//
// The "goo" look comes from the classic metaball trick: draw soft blurred
// droplets, then push their alpha through a high-contrast colour matrix so the
// blurred halos snap together into one connected fluid surface. That surface is
// then used as a dstIn mask to reveal the logo + luminous fill beneath it.
class _LiquidRevealPainter extends CustomPainter {
  final double progress;
  final List<_Blob> blobs;
  final ui.Image? logo;
  final Rect crop;

  _LiquidRevealPainter({
    required this.progress,
    required this.blobs,
    required this.logo,
    required this.crop,
  });

  // Alpha-threshold matrix: blurred edges below the threshold vanish, above it
  // snap to opaque — the merge that makes neighbouring droplets read as one.
  static const ColorFilter _goo = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 26, -2200.0, //
  ]);

  double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final full = Offset.zero & size;

    // Logo geometry (from the cropped, content-only region of the asset).
    final aspect = logo != null
        ? (logo!.width * crop.width) / (logo!.height * crop.height)
        : 2.1;
    final logoW = (size.width * 0.72).clamp(240.0, 560.0).toDouble();
    final logoH = logoW / aspect;
    final logoRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: logoW,
      height: logoH,
    );

    final coverage = Curves.easeOutCubic.transform(
      _smoothstep(0.12, 0.72, p),
    );
    final settle = _smoothstep(0.74, 0.95, p);
    final blurSigma = (logoH * 0.16).clamp(8.0, 26.0);

    // --- Glow ---------------------------------------------------------------
    // A soft indigo halo gathers in anticipation, tracks the reveal, then rests
    // behind the finished wordmark. Drawn behind the logo so it never washes out
    // the (intentionally light, thin) letterforms.
    final anticip = _smoothstep(0.0, 0.12, p);
    final glowAlpha =
        (anticip * 0.30 + coverage * 0.18 + settle * 0.28).clamp(0.0, 1.0);
    if (glowAlpha > 0.01) {
      final glowRadius = logoW * (0.42 + 0.12 * settle);
      // Very subtle chromatic fringing — cyan/magenta offset twins.
      _radialGlow(canvas, Offset(cx - 6, cy), glowRadius,
          const Color(0xFF22D3EE), 0.05 * settle);
      _radialGlow(canvas, Offset(cx + 6, cy), glowRadius,
          const Color(0xFFC084FC), 0.05 * settle);
      _radialGlow(canvas, Offset(cx, cy), glowRadius,
          const Color(0xFF4F46E5), glowAlpha * 0.55);
    }

    if (logo == null) return;

    final iw = logo!.width.toDouble();
    final ih = logo!.height.toDouble();
    final srcRect = Rect.fromLTRB(
      crop.left * iw,
      crop.top * ih,
      crop.right * iw,
      crop.bottom * ih,
    );

    // --- Liquid-masked reveal -----------------------------------------------
    canvas.saveLayer(full, Paint());

    // 1. The wordmark itself, in its true colours.
    canvas.drawImageRect(
      logo!,
      srcRect,
      logoRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    // 2. Diagonal light-sweep — a restrained specular pass over the revealed
    //    art. Kept low so it sheens, not washes.
    final sweepT = _smoothstep(0.5, 0.86, p);
    if (sweepT > 0.0 && sweepT < 1.0) {
      final sweepIntensity = sin(sweepT * pi);
      final bandW = logoW * 0.32;
      final sweepX = ui.lerpDouble(cx - logoW * 0.7, cx + logoW * 0.7, sweepT)!;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(-0.35);
      canvas.translate(-cx, -cy);
      final bandRect = Rect.fromCenter(
        center: Offset(sweepX, cy),
        width: bandW,
        height: size.height * 1.6,
      );
      final sweepPaint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0x00FFFFFF),
            Color.fromRGBO(255, 255, 255, 0.20 * sweepIntensity),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bandRect);
      canvas.drawRect(bandRect, sweepPaint);
      canvas.restore();
    }

    // 3. Cut everything above to the liquid surface (metaball mask).
    canvas.saveLayer(full, Paint()..blendMode = BlendMode.dstIn);
    canvas.saveLayer(full, Paint()..colorFilter = _goo);
    canvas.saveLayer(
      full,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    );
    _drawDroplets(canvas, logoRect, coverage, p);
    canvas.restore(); // blur
    canvas.restore(); // goo threshold
    canvas.restore(); // dstIn mask

    canvas.restore(); // visible composite
  }

  void _drawDroplets(Canvas canvas, Rect logo, double coverage, double p) {
    final paint = Paint()..color = Colors.white;
    final spreadX = logo.width * 0.5;
    final spreadY = logo.height * 0.5;
    final cx = logo.center.dx;
    final cy = logo.center.dy;

    for (final b in blobs) {
      final wob = b.wobble == 0
          ? 0.0
          : sin(p * pi * 2 * b.freq + b.phase) * b.wobble * logo.width;
      final x = cx + b.nx * spreadX * coverage + wob;
      final y = cy + b.ny * spreadY * coverage + wob * 0.6;
      final r = b.radiusFrac *
          logo.width *
          ui.lerpDouble(0.12, 1.0, coverage)!;
      if (r <= 0.5) continue;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _radialGlow(
      Canvas canvas, Offset center, double radius, Color color, double alpha) {
    if (alpha <= 0.01) return;
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _LiquidRevealPainter old) =>
      old.progress != progress || old.logo != logo || old.crop != crop;
}
