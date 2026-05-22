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

  late AnimationController _particleController;
  late AnimationController _exitController;
  late Animation<double> _exitAnimation;

  List<_Particle> _particles = [];
  final Random _rng = Random(42);

  @override
  void initState() {
    super.initState();

    _particleController = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    );

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _exitAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initParticles();
      _particleController.forward();
    });

    _checkInitializationStatus();
  }

  void _initParticles() {
    final screen = MediaQuery.of(context).size;
    final area = screen.width * screen.height;
    final count = (area / 1600).clamp(200, 650).toInt();

    final cx = screen.width / 2;
    final cy = screen.height / 2;

    final scale = (screen.shortestSide / 420).clamp(0.85, 1.6);

    _particles = [];

    // --- Core particles — converge to a compact cluster at center ---
    final coreCount = (count * 0.55).toInt();
    for (int i = 0; i < coreCount; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final dist = _rng.nextDouble() * 30 * scale;
      final targetX = cx + cos(angle) * dist;
      final targetY = cy + sin(angle) * dist;

      final blend = _rng.nextDouble() * 0.15;
      final r = (0.25 + blend).clamp(0.0, 1.0);
      final g = (0.22 + blend).clamp(0.0, 1.0);
      final b = (0.85 + _rng.nextDouble() * 0.10).clamp(0.0, 1.0);

      _particles.add(_Particle(
        startX: _rng.nextDouble() * screen.width,
        startY: _rng.nextDouble() * screen.height,
        targetX: targetX,
        targetY: targetY,
        size: 1.0 + _rng.nextDouble() * 1.5,
        r: r,
        g: g,
        b: b,
        type: 0,
        delay: 0.02 + _rng.nextDouble() * 0.16,
        driftAngle: _rng.nextDouble() * 2 * pi,
        driftSpeed: 0.3 + _rng.nextDouble() * 0.7,
      ));
    }

    // --- Glow particles (tight halo around center) ---
    final glowCount = (count * 0.18).toInt();
    for (int i = 0; i < glowCount; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final dist = 20 * scale + _rng.nextDouble() * 25 * scale;
      _particles.add(_Particle(
        startX: _rng.nextDouble() * screen.width,
        startY: _rng.nextDouble() * screen.height,
        targetX: cx + cos(angle) * dist,
        targetY: cy + sin(angle) * dist,
        size: 1.0 + _rng.nextDouble() * 1.5,
        r: 0.388,
        g: 0.400,
        b: 0.945,
        type: 1,
        delay: _rng.nextDouble() * 0.2,
        driftAngle: _rng.nextDouble() * 2 * pi,
        driftSpeed: 0.2 + _rng.nextDouble() * 0.5,
      ));
    }

    // --- Ambient particles (star field, fade out) ---
    final ambientCount = count - _particles.length;
    for (int i = 0; i < ambientCount; i++) {
      _particles.add(_Particle(
        startX: _rng.nextDouble() * screen.width,
        startY: _rng.nextDouble() * screen.height,
        targetX: 0,
        targetY: 0,
        size: 0.5 + _rng.nextDouble() * 1.2,
        r: 1.0,
        g: 1.0,
        b: 1.0,
        type: 2,
        delay: 0,
        driftAngle: _rng.nextDouble() * 2 * pi,
        driftSpeed: 0.1 + _rng.nextDouble() * 0.4,
      ));
    }

    setState(() {});
  }

  @override
  void dispose() {
    _particleController.dispose();
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
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      await _showOnboarding();
    } else {
      await Future.delayed(const Duration(milliseconds: 3400));
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
        child: Stack(
          children: [
            Container(color: const Color(0xFF020617)),

            // Particle field
            if (_particles.isNotEmpty)
              AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ParticleFieldPainter(
                      particles: _particles,
                      progress: _particleController.value,
                    ),
                    size: Size.infinite,
                  );
                },
              ),

            // Logo image + text — appears AFTER particles are fully gone
            Center(
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  final p = _particleController.value;

                  // Logo appears: 0.76 → 0.90 (particles gone by 0.74)
                  final logoRaw = ((p - 0.76) / 0.14).clamp(0.0, 1.0);
                  final logoOpacity = Curves.easeOut.transform(logoRaw);
                  final logoScale =
                      0.90 + 0.10 * Curves.easeOutBack.transform(logoRaw);
                  final glowIntensity = Curves.easeOut.transform(logoRaw);

                  return Opacity(
                    opacity: logoOpacity,
                    child: Transform.scale(
                      scale: logoScale,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(
                                alpha: 0.35 * glowIntensity,
                              ),
                              blurRadius: 60 * glowIntensity,
                              spreadRadius: 15 * glowIntensity,
                            ),
                            BoxShadow(
                              color: const Color(0xFF818CF8).withValues(
                                alpha: 0.18 * glowIntensity,
                              ),
                              blurRadius: 120 * glowIntensity,
                              spreadRadius: 40 * glowIntensity,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/splash_logo.png',
                          width: 320,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Particle data
// ---------------------------------------------------------------------------

class _Particle {
  final double startX, startY;
  final double targetX, targetY;
  final double size;
  final double r, g, b;
  final int type; // 0 = logo, 1 = glow, 2 = ambient
  final double delay;
  final double driftAngle;
  final double driftSpeed;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.targetX,
    required this.targetY,
    required this.size,
    required this.r,
    required this.g,
    required this.b,
    required this.type,
    required this.delay,
    required this.driftAngle,
    required this.driftSpeed,
  });
}

// ---------------------------------------------------------------------------
// Particle field painter
// ---------------------------------------------------------------------------

class _ParticleFieldPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  // Timeline:
  // 0.00 – 0.22  Drift (star field floating)
  // 0.22 – 0.60  Converge (particles rush to logo shape)
  // 0.60 – 0.66  Hold (formation visible, brief pause)
  // 0.66 – 0.74  Dissolve + flash (particles vanish, bright pulse)
  // 0.74+        Nothing (clean canvas for logo widget)
  static const double _driftEnd = 0.22;
  static const double _convergeEnd = 0.60;
  static const double _holdEnd = 0.66;
  static const double _dissolveEnd = 0.74;
  static const double _maxDrift = 32.0;

  _ParticleFieldPainter({required this.particles, required this.progress});

  double _ease(double t) {
    if (t < 0.5) {
      return 4 * t * t * t;
    } else {
      final f = (2 * t) - 2;
      return 0.5 * f * f * f + 1;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // After dissolve, nothing to draw
    if (progress >= _dissolveEnd) return;

    final paint = Paint();
    final driftT = (progress / _driftEnd).clamp(0.0, 1.0);

    for (final p in particles) {
      final driftDx = cos(p.driftAngle) * p.driftSpeed * driftT * _maxDrift;
      final driftDy = sin(p.driftAngle) * p.driftSpeed * driftT * _maxDrift;
      final driftedX = p.startX + driftDx;
      final driftedY = p.startY + driftDy;

      double px, py, opacity, drawSize;

      if (p.type == 2) {
        // Ambient: float and fade, gone before hold phase
        final extraDrift = 1.0 + progress * 0.6;
        px = p.startX + driftDx * extraDrift;
        py = p.startY + driftDy * extraDrift;
        final fadeOut = (progress / _convergeEnd).clamp(0.0, 1.0);
        opacity = 0.30 * (1.0 - fadeOut);
        drawSize = p.size;
      } else if (progress <= _driftEnd) {
        // Drift phase
        px = driftedX;
        py = driftedY;
        opacity = 0.45 + 0.35 * driftT;
        drawSize = p.size;
      } else if (progress <= _convergeEnd) {
        // Converge phase
        final rawT =
            ((progress - _driftEnd) / (_convergeEnd - _driftEnd))
                .clamp(0.0, 1.0);
        final delayed =
            ((rawT - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
        final eased = _ease(delayed);

        px = driftedX + (p.targetX - driftedX) * eased;
        py = driftedY + (p.targetY - driftedY) * eased;
        opacity = 0.80 + 0.20 * eased;
        drawSize = p.size * (1.0 + eased * 0.3);
      } else if (progress <= _holdEnd) {
        // Hold phase — particles sit at target
        px = p.targetX;
        py = p.targetY;
        opacity = 1.0;
        drawSize = p.size * 1.3;
      } else {
        // Dissolve phase — fast uniform fadeout
        px = p.targetX;
        py = p.targetY;
        final fadeT =
            ((progress - _holdEnd) / (_dissolveEnd - _holdEnd))
                .clamp(0.0, 1.0);
        opacity = 1.0 - fadeT;
        drawSize = p.size * (1.3 - 0.5 * fadeT);
      }

      if (opacity <= 0.01) continue;

      paint.color = Color.fromRGBO(
        (p.r * 255).toInt(),
        (p.g * 255).toInt(),
        (p.b * 255).toInt(),
        opacity.clamp(0.0, 1.0),
      );

      if (drawSize > 1.0) {
        paint.maskFilter =
            MaskFilter.blur(BlurStyle.normal, drawSize * 0.3);
      } else {
        paint.maskFilter = null;
      }

      canvas.drawCircle(Offset(px, py), drawSize, paint);
    }

    // Flash pulse during dissolve — masks the particle-to-logo handoff
    if (progress > _holdEnd && progress < _dissolveEnd) {
      final flashT =
          ((progress - _holdEnd) / (_dissolveEnd - _holdEnd))
              .clamp(0.0, 1.0);
      // Quick in, slower out
      final flashIntensity = flashT < 0.3
          ? (flashT / 0.3)
          : 1.0 - ((flashT - 0.3) / 0.7);
      final center = Offset(size.width / 2, size.height / 2);

      final flashPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(129, 140, 248, 0.35 * flashIntensity),
            Color.fromRGBO(99, 102, 241, 0.12 * flashIntensity),
            const Color.fromRGBO(99, 102, 241, 0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: 180 + 40 * flashT));

      canvas.drawCircle(center, 180 + 40 * flashT, flashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFieldPainter old) =>
      old.progress != progress;
}
