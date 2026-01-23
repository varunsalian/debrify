import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/android_native_downloader.dart';
import '../services/app_migration_service.dart';
import '../services/main_page_bridge.dart';
import '../widgets/initial_setup_flow.dart';
import '../main.dart';

/// AppInitializer handles the app startup flow:
/// 1. Shows a beautiful loading screen
/// 2. Checks if initial setup is needed
/// 3. Shows InitialSetupFlow if needed (with NOTHING else in background)
/// 4. Then transitions to MainPage
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _onboardingComplete = false;
  bool _isAndroidTv = false;

  late AnimationController _logoAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Setup animations for loading screen
    _logoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _logoFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.easeOut,
    ));

    _logoScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.elasticOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _logoAnimationController.forward();
    _checkInitializationStatus();
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkInitializationStatus() async {
    // Check if running on Android TV
    try {
      _isAndroidTv = await AndroidNativeDownloader.isTelevision();
    } catch (_) {
      _isAndroidTv = false;
    }

    // Update focus highlight strategy based on TV status
    if (_isAndroidTv) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }

    // Run app migrations (auto-add Cinemeta addon on fresh install or update)
    await AppMigrationService.runMigrations();

    // Check if onboarding has been completed
    final hasCompleted = await StorageService.isInitialSetupComplete();

    if (!mounted) return;

    if (!hasCompleted) {
      // Need onboarding - wait for loading animation to complete
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // Show onboarding after a brief moment
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      // Show onboarding
      await _showOnboarding();
    } else {
      // No onboarding needed - go straight to MainPage after a brief delay
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;

      // Stop animations before transitioning to MainPage
      _pulseController.stop();
      _logoAnimationController.stop();

      setState(() {
        _isLoading = false;
        _onboardingComplete = true;
      });
    }
  }

  Future<void> _showOnboarding() async {
    // CRITICAL: Clear any existing focus before showing onboarding
    FocusManager.instance.primaryFocus?.unfocus();

    // Show the onboarding flow
    final configured = await InitialSetupFlow.show(context);

    if (!mounted) return;

    // Mark onboarding as complete
    await StorageService.setInitialSetupComplete(true);

    if (configured) {
      MainPageBridge.notifyIntegrationChanged();
    }

    // Stop animations before transitioning to MainPage
    _pulseController.stop();
    _logoAnimationController.stop();

    setState(() {
      _onboardingComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // If onboarding is complete, show MainPage
    if (_onboardingComplete) {
      return const MainPage();
    }

    // Otherwise show the loading/initialization screen
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          // Beautiful gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF020617), // Slate 950
                  Color(0xFF0F172A), // Slate 900
                  Color(0xFF1E293B), // Slate 800
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Subtle animated mesh/grid overlay
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return CustomPaint(
                painter: _MeshPainter(
                  progress: _pulseController.value,
                ),
                size: Size.infinite,
              );
            },
          ),

          // Center content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated logo/app icon
                FadeTransition(
                  opacity: _logoFadeAnimation,
                  child: ScaleTransition(
                    scale: _logoScaleAnimation,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF6366F1), // Indigo
                                  Color(0xFF8B5CF6), // Purple
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(
                                      alpha: 0.3 * _pulseAnimation.value),
                                  blurRadius: 30 * _pulseAnimation.value,
                                  spreadRadius: 10 * _pulseAnimation.value,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_circle_outline_rounded,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // App name
                FadeTransition(
                  opacity: _logoFadeAnimation,
                  child: const Text(
                    'Debrify',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // Loading indicator
                if (_isLoading)
                  FadeTransition(
                    opacity: _logoFadeAnimation,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Initializing...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the animated mesh background
class _MeshPainter extends CustomPainter {
  final double progress;

  _MeshPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const gridSize = 60.0;
    final offset = progress * gridSize;

    // Draw vertical lines
    for (double x = -gridSize + offset;
        x < size.width + gridSize;
        x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - 20, size.height),
        paint,
      );
    }

    // Draw horizontal lines
    for (double y = -gridSize + offset;
        y < size.height + gridSize;
        y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y - 20),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
