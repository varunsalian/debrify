import 'dart:math';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(
      duration: const Duration(milliseconds: 1900),
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

    // Kick off the drop-and-bounce reveal on the first frame (nothing to decode
    // now — the mark and wordmark are drawn as vectors).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealController.forward();
    });

    _checkInitializationStatus();
  }

  @override
  void dispose() {
    _revealController.dispose();
    _exitController.dispose();
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
                painter: _DropBouncePainter(_revealController.value),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drop & Bounce reveal painter
// ---------------------------------------------------------------------------
//
// Character animation over the old metaball trickery: the play mark drops in
// from above with real weight (an ease-out bounce), squashing on each contact —
// and the landing shakes the DEBRIFY letters loose so they pop up one by one.
// The mark and each letter are drawn as vectors/text so they move
// independently, and the lockup is sized to ~86% of the frame so it owns the
// screen on big TVs instead of floating in a void.
//
// Timeline (progress 0..1):
//   0.00 – 0.52   Drop — mark falls and bounces to rest (contacts ~.36/.73/.91)
//   0.20 – ~0.75  Shake loose — letters pop up on a damped hop, staggered
//   0.75 – 1.00   Rest
class _DropBouncePainter extends CustomPainter {
  final double p;
  const _DropBouncePainter(this.p);

  static const String _word = 'DEBRIFY';

  static double _cl(double v, double a, double b) => v < a ? a : (v > b ? b : v);
  static double _lp(double a, double b, double t) => a + (b - a) * t;
  static double _outBack(double t, [double s = 1.7]) =>
      1 + (s + 1) * pow(t - 1, 3).toDouble() + s * pow(t - 1, 2).toDouble();
  static double _outBounce(double t) {
    const n = 7.5625, d = 2.75;
    if (t < 1 / d) return n * t * t;
    if (t < 2 / d) {
      t -= 1.5 / d;
      return n * t * t + 0.75;
    }
    if (t < 2.5 / d) {
      t -= 2.25 / d;
      return n * t * t + 0.9375;
    }
    t -= 2.625 / d;
    return n * t * t + 0.984375;
  }

  // Rounded right-pointing play triangle, centred at the origin, inscribed in ±s/2.
  void _playPath(Path path, double s) {
    final pts = [
      Offset(-0.30 * s, -0.40 * s),
      Offset(-0.30 * s, 0.40 * s),
      Offset(0.43 * s, 0),
    ];
    final r = 0.14 * s;
    for (int i = 0; i < 3; i++) {
      final a = pts[i], b = pts[(i + 1) % 3], c = pts[(i + 2) % 3];
      final v1 = a - b, v2 = c - b;
      final l1 = v1.distance == 0 ? 1.0 : v1.distance;
      final l2 = v2.distance == 0 ? 1.0 : v2.distance;
      final t1 = b + v1 * (r / l1), t2 = b + v2 * (r / l2);
      if (i == 0) {
        path.moveTo(t1.dx, t1.dy);
      } else {
        path.lineTo(t1.dx, t1.dy);
      }
      path.quadraticBezierTo(b.dx, b.dy, t2.dx, t2.dy);
    }
    path.close();
  }

  List<TextPainter> _layoutLetters(double fontSize) {
    return _word.split('').map((ch) {
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

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;

    // ---- lockup layout ----
    double boxH = min(w * 0.66, h * 1.7) / 2.15;
    double gs = boxH;
    double fs = boxH * 0.60;
    double ls = fs * 0.11;
    double gap = gs * 0.20;

    List<TextPainter> letters = _layoutLetters(fs);
    double total = 0;
    for (int i = 0; i < letters.length; i++) {
      total += letters[i].width + (i < letters.length - 1 ? ls : 0);
    }
    double lockW = gs + gap + total;

    final maxW = w * 0.86;
    if (lockW > maxW) {
      final k = maxW / lockW;
      boxH *= k;
      gs *= k;
      fs *= k;
      ls *= k;
      gap = gs * 0.20;
      letters = _layoutLetters(fs);
      total = 0;
      for (int i = 0; i < letters.length; i++) {
        total += letters[i].width + (i < letters.length - 1 ? ls : 0);
      }
      lockW = gs + gap + total;
    }

    final startX = cx - lockW / 2;
    final wordX = startX + gs + gap;
    final glyphCx = startX + gs / 2;
    final baseY = cy + fs * 0.35;

    final centers = <double>[];
    double x = wordX;
    for (int i = 0; i < letters.length; i++) {
      centers.add(x + letters[i].width / 2);
      x += letters[i].width + ls;
    }

    // ---- glyph drop + squash ----
    final dt = _cl(p / 0.52, 0, 1);
    final yoff = _lp(-(h * 0.55 + gs), 0, _outBounce(dt));
    double comp = 0;
    for (final cpair in const [
      [0.363, 1.0],
      [0.727, 0.5],
      [0.909, 0.28],
    ]) {
      comp += cpair[1] * exp(-pow((dt - cpair[0]) / 0.045, 2).toDouble());
    }
    comp = _cl(comp, 0, 1) * 0.30;
    _drawGlyph(canvas, glyphCx, cy + yoff, gs, 1 + comp * 0.85, 1 - comp, 0.7 + comp);

    // ---- letters shaken loose ----
    for (int i = 0; i < letters.length; i++) {
      final st = 0.20 + i * 0.03;
      final lt = _cl((p - st) / 0.34, 0, 1);
      if (lt <= 0) continue;
      final hop = sin(lt * pi * 1.6) * exp(-4 * lt);
      final scale = _lp(0.6, 1, _outBack(_cl(lt * 1.4, 0, 1)));
      final alpha = _cl(lt * 1.6, 0, 1);
      _drawLetter(canvas, letters[i], centers[i], baseY, -hop * gs * 0.16, scale, alpha, fs);
    }
  }

  void _drawGlyph(Canvas c, double gx, double gy, double s, double sx, double sy, double glow) {
    c.save();
    c.translate(gx, gy);
    c.scale(sx, sy);
    final path = Path();
    _playPath(path, s);
    if (glow > 0) {
      c.drawPath(
        path,
        Paint()
          ..color = Color.fromRGBO(110, 120, 255, 0.55 * _cl(glow, 0, 1))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.12 * glow),
      );
    }
    const grad = LinearGradient(
      colors: [Color(0xFF4F74FF), Color(0xFF6E6BFF), Color(0xFF8A5CFF)],
      stops: [0, 0.5, 1],
    );
    final rect = Rect.fromCenter(center: Offset.zero, width: s, height: s);
    c.drawPath(path, Paint()..shader = grad.createShader(rect));
    // inner sheen for a touch of depth
    final inner = Path();
    _playPath(inner, s * 0.52);
    c.drawPath(inner, Paint()..color = const Color(0xFFDFE6FF).withValues(alpha: 0.22));
    c.restore();
  }

  void _drawLetter(Canvas c, TextPainter tp, double centerX, double baseY, double dy,
      double scale, double alpha, double fs) {
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    c.save();
    c.translate(centerX, baseY + dy);
    c.scale(scale, scale);
    final needsLayer = alpha < 0.999;
    if (needsLayer) {
      c.saveLayer(
        Rect.fromLTRB(-tp.width, -fs * 1.6, tp.width, fs * 1.2),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    tp.paint(c, Offset(-tp.width / 2, -ascent));
    if (needsLayer) c.restore();
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _DropBouncePainter old) => old.p != p;
}
