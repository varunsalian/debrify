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
  bool _onboardingComplete = false;
  bool _isAndroidTv = false;

  late AnimationController _sweepController;
  late AnimationController _contentController;
  late AnimationController _exitController;
  late Animation<double> _sweepAnimation;
  late Animation<double> _iconReveal;
  late Animation<double> _iconScale;
  late Animation<double> _textReveal;
  late Animation<double> _glowAnimation;
  late Animation<double> _exitAnimation;

  @override
  void initState() {
    super.initState();

    // Light sweep across screen
    _sweepController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Content reveal (icon + text)
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Exit fade
    _exitController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _sweepAnimation = Tween<double>(begin: -0.3, end: 1.3).animate(
      CurvedAnimation(parent: _sweepController, curve: Curves.easeInOutCubic),
    );

    _iconReveal = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _iconScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _textReveal = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    _exitAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    // Start the sequence: sweep first, content reveals as sweep passes center
    _sweepController.forward();
    _sweepController.addListener(() {
      if (_sweepController.value > 0.35 &&
          !_contentController.isAnimating &&
          !_contentController.isCompleted) {
        _contentController.forward();
      }
    });

    _checkInitializationStatus();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _contentController.dispose();
    _exitController.dispose();
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

      // Start TV listener early so phone can discover TV during onboarding
      // This enables "Send Setup to TV" feature to work on fresh installs
      await _startTvListenerEarly();
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

      // Show onboarding after a brief moment
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      // Show onboarding
      await _showOnboarding();
    } else {
      // No onboarding needed - go straight to MainPage after a brief delay
      await Future.delayed(const Duration(milliseconds: 1000));

      if (!mounted) return;

      // Play exit animation then show main page
      await _exitController.forward();
      if (!mounted) return;

      setState(() {
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

  /// Start TV listener early so phone can discover TV during onboarding
  Future<void> _startTvListenerEarly() async {
    try {
      // Check if remote control is enabled
      final remoteEnabled = await StorageService.getRemoteControlEnabled();
      if (!remoteEnabled) return;

      // Get device name for discovery
      var deviceName = await StorageService.getRemoteTvDeviceName();
      deviceName ??= await PlatformUtil.getDeviceName();
      deviceName ??= 'Debrify TV';

      debugPrint('AppInitializer: Starting TV listener early as "$deviceName"');

      // Start the TV listener
      await RemoteControlState().startTvListener(deviceName);

      // Set up command routing (for receiving config commands during onboarding)
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
            // Dark background
            Container(color: const Color(0xFF020617)),

            // Horizontal light sweep
            AnimatedBuilder(
              animation: _sweepAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: _SweepPainter(progress: _sweepAnimation.value),
                  size: Size.infinite,
                );
              },
            ),

            // Center content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon — revealed by sweep
                  AnimatedBuilder(
                    animation: _contentController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _iconReveal.value,
                        child: Transform.scale(
                          scale: _iconScale.value,
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(
                                    alpha: 0.25 * _glowAnimation.value,
                                  ),
                                  blurRadius: 40 * _glowAnimation.value,
                                  spreadRadius: 8 * _glowAnimation.value,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // App name with staggered letter reveal
                  AnimatedBuilder(
                    animation: _textReveal,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textReveal.value,
                        child: Transform.translate(
                          offset: Offset(0, 8 * (1 - _textReveal.value)),
                          child: const Text(
                            'Debrify',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 6,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal light sweep painter — a soft lens flare moving left to right
class _SweepPainter extends CustomPainter {
  final double progress;

  _SweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * progress;
    final centerY = size.height * 0.48;

    // Main horizontal sweep line
    final sweepPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [
              Colors.transparent,
              const Color(0xFF6366F1).withValues(alpha: 0.08),
              const Color(0xFF818CF8).withValues(alpha: 0.15),
              const Color(0xFF6366F1).withValues(alpha: 0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
          ).createShader(
            Rect.fromCenter(
              center: Offset(centerX, centerY),
              width: size.width * 0.5,
              height: size.height,
            ),
          );

    canvas.drawRect(
      Rect.fromLTWH(
        centerX - size.width * 0.25,
        0,
        size.width * 0.5,
        size.height,
      ),
      sweepPaint,
    );

    // Bright center point
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.04),
              Colors.transparent,
            ],
            stops: const [0.0, 0.3, 1.0],
          ).createShader(
            Rect.fromCircle(center: Offset(centerX, centerY), radius: 80),
          );

    canvas.drawCircle(Offset(centerX, centerY), 80, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
