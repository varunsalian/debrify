import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'launch/launch_ident.dart';
import 'launch/loading_sweep.dart';
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
  // True once the splash overlay has fully faded off MainPage. Until then the
  // splash keeps animating ON TOP of the (already-mounted, already-loading)
  // main shell, so the user never sees the Home board's own loading state on
  // a cold start — the splash IS the loading screen, held until home is ready.
  bool _splashDone = false;
  // Shows the loading sweep under the lockup during the hold-for-home phase.
  bool _holdingForHome = false;
  bool _isAndroidTv = PlatformUtil.isAndroidTvCached;
  // On TV, let MainPage build and fetch behind an opacity-zero render object,
  // but don't raster its first (very expensive) frame while the loading sweep
  // is moving. _finishSplash gives it a short hidden prepaint window after the
  // sweep has left the track.
  bool _paintHomeBehindSplash = !PlatformUtil.isAndroidTvCached;

  late AnimationController _revealController;
  late AnimationController _exitController;
  // Drives the loading sweep while the splash waits for the Home board.
  late AnimationController _idleController;
  late Animation<double> _exitAnimation;
  // The chosen launch ident — its painter, backdrop and sweep accent.
  // Resolved synchronously from the cache warmed in main().
  late LaunchIdent _ident;
  late CustomPainter _revealPainter;
  late LoadingSweepPainter _loadingPainter;
  Timer? _homeReadyTimeout;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();

    _ident = launchIdentFor(StorageService.launchAnimationCached);

    // The reveal is progress-driven; the splash holds only as long as the
    // ident's animation (plus real init work) — no fixed delays.
    _revealController = AnimationController(
      duration: _ident.revealDuration,
      vsync: this,
    );

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _idleController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    // The painters listen to their controllers directly. Keeping one painter
    // instance lets the reveal cache its text layout, paths, and gradient
    // shaders instead of recreating all of them for every frame.
    _revealPainter = _ident.createPainter(
      _revealController,
      isTelevision: () => _isAndroidTv,
    );
    _loadingPainter =
        LoadingSweepPainter(_idleController, colors: _ident.sweepColors);

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
    MainPageBridge.homeBoardReady.removeListener(_onHomeBoardReady);
    _homeReadyTimeout?.cancel();
    _revealController.dispose();
    _exitController.dispose();
    _idleController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // App initialization logic (unchanged)
  // ---------------------------------------------------------------------------

  Future<void> _checkInitializationStatus() async {
    try {
      // Warmed in main() before runApp — resolves from cache instantly.
      final isAndroidTv = await PlatformUtil.isAndroidTV();
      if (isAndroidTv != _isAndroidTv && mounted) {
        setState(() {
          _isAndroidTv = isAndroidTv;
          _paintHomeBehindSplash = !isAndroidTv;
        });
      } else {
        _isAndroidTv = isAndroidTv;
      }
    } catch (_) {
      _isAndroidTv = false;
      _paintHomeBehindSplash = true;
    }

    if (_isAndroidTv) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      // Needs to be *started* early (discoverable during onboarding), not
      // *finished* early — don't hold the splash on a socket bind + storage
      // reads.
      unawaited(_startTvListenerEarly());
    }

    try {
      // Returning users only pay two prefs reads here. The unseeded-addon
      // path does network manifest fetches — time-box those so a slow or
      // offline network can't hold the splash; seeding continues in the
      // background and is retried next launch if it didn't finish.
      await AppMigrationService.runMigrations().timeout(
        const Duration(seconds: 4),
      );
    } on TimeoutException {
      debugPrint('AppInitializer: migrations still running, not blocking UI');
    }

    final hasCompleted = await StorageService.isInitialSetupComplete();

    if (!mounted) return;

    // Hold the splash only until the reveal animation finishes (it runs
    // concurrently with the init work above) — replaces the old fixed
    // 2300ms/1700ms delays.
    await _waitForReveal();
    if (!mounted) return;

    if (!hasCompleted) {
      await _showOnboarding();
    } else {
      // Returning user: mount MainPage UNDER the still-covering splash (so the
      // Home board starts loading immediately) and switch the splash into its
      // loading phase — the lockup stays put and a sweep animates beneath it —
      // until the board reports its first rows ready. TV then prepaints behind
      // a static lockup; other platforms keep the original fade handoff.
      setState(() {
        _onboardingComplete = true;
        _holdingForHome = true;
      });
      _idleController.repeat();
      if (MainPageBridge.homeBoardReady.value) {
        _finishSplash();
      } else {
        MainPageBridge.homeBoardReady.addListener(_onHomeBoardReady);
        // Safety valve: if the board never settles (hung network with no
        // timeout of its own, or a future tab-order change breaking the
        // signal), don't strand the user on the splash.
        _homeReadyTimeout = Timer(const Duration(seconds: 10), _finishSplash);
      }
    }
  }

  void _onHomeBoardReady() {
    if (MainPageBridge.homeBoardReady.value) _finishSplash();
  }

  Future<void> _finishSplash() async {
    if (_finishing) return;
    _finishing = true;
    MainPageBridge.homeBoardReady.removeListener(_onHomeBoardReady);
    _homeReadyTimeout?.cancel();

    if (_isAndroidTv) {
      // Finish the moving segment before Home is allowed to paint. This keeps
      // Home's first row/image raster burst from stealing frames from the only
      // moving element the user can see. At t=1 the segment is fully clipped
      // off the right edge, so the line can disappear without a visual jump.
      if (_idleController.isAnimating) {
        // homeBoardReady is published immediately after Home's setState. Hold
        // the sweep still for that one pending build/layout frame, then let it
        // leave the track without competing with a large UI-isolate rebuild.
        _idleController.stop();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        try {
          await _idleController.animateTo(
            1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        } catch (_) {}
      }
      if (!mounted) return;
      _idleController.stop();
      setState(() {
        _holdingForHome = false;
        _paintHomeBehindSplash = true;
      });

      // The splash is now completely static, so Home can spend one frame
      // rasterizing rows and uploading its first visible textures invisibly.
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _splashDone = true);
      return;
    }

    // The ready signal fires when the board's first sections are SET, one
    // frame before they paint — and that first paint is the board's heaviest.
    // A short grace lets it land while still fully hidden, so the fade reveals
    // settled rows instead of a mid-jank frame.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await _exitController.forward();
    if (!mounted) return;
    _idleController.stop();
    setState(() => _splashDone = true);
  }

  Future<void> _waitForReveal() async {
    if (_revealController.isCompleted) return;
    try {
      // forward() continues from the current value; the timeout guards the
      // ticker being cancelled mid-flight (widget disposed) so this await can
      // never hang the init flow.
      await _revealController.forward().timeout(
        _ident.revealDuration + const Duration(milliseconds: 300),
        onTimeout: () {},
      );
    } catch (_) {}
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
      // Fresh install: the user just walked through onboarding, so there's no
      // cold-start moment to bridge — skip the hold-for-home overlay phase.
      _onboardingComplete = true;
      // Returning TV users reach the equivalent state through _finishSplash,
      // but first-run onboarding bypasses that method. Reveal MainPage before
      // removing the splash or its TV-only Opacity gate would stay at zero.
      _paintHomeBehindSplash = true;
      _splashDone = true;
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
    if (!_onboardingComplete) {
      return Scaffold(
        backgroundColor: _ident.baseColor,
        body: _buildSplashBody(),
      );
    }
    // MainPage stays child 0 of this Stack for BOTH overlay phases (splash up /
    // splash gone) so removing the overlay never reparents it — a reparent
    // would remount the whole shell and restart the loads the splash just
    // waited for.
    return Stack(
      children: [
        // Opacity zero skips painting but not layout, state initialization, or
        // async loads. That is exactly what the TV splash needs: prepare Home
        // without competing with the visible sweep for raster time.
        Opacity(
          opacity: _isAndroidTv && !_paintHomeBehindSplash ? 0 : 1,
          child: const RepaintBoundary(child: MainPage()),
        ),
        if (!_splashDone)
          Positioned.fill(
            // Absorb, don't ignore: the shell underneath is fully live, and a
            // tap during the hold phase must not activate an invisible button.
            child: AbsorbPointer(child: _buildSplashBody()),
          ),
      ],
    );
  }

  Widget _buildSplashBody() {
    final splash = DecoratedBox(
      // The ident's STATIC backdrop, outside the painter's RepaintBoundary so
      // it rasters once while only the animated elements repaint. Opaque on
      // purpose: as an overlay this must fully cover the shell until the exit
      // fade runs.
      decoration: _ident.backdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Boundary so the sweep's 60fps ticks don't re-rasterize the
          // (settled) lockup every frame during the hold-for-home phase.
          RepaintBoundary(
            child: CustomPaint(size: Size.infinite, painter: _revealPainter),
          ),
          Align(
            // Proportional placement clears the lockup's bottom edge on both
            // the TV's 16:9 canvas and phone portrait.
            alignment: const Alignment(0, 0.55),
            child: AnimatedOpacity(
              opacity: _holdingForHome ? 1.0 : 0.0,
              duration: _isAndroidTv
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: const Size(220, 4),
                  painter: _loadingPainter,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // A full-screen opacity layer over an already-rendered Home page is one of
    // the costliest possible exit effects on weak TV GPUs. TV performs a clean
    // cut after the hidden prepaint above; other platforms retain the fade.
    if (_isAndroidTv) return splash;
    return FadeTransition(opacity: _exitAnimation, child: splash);
  }
}
