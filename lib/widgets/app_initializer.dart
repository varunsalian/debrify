import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/app_theme_controller.dart';
import '../theme/app_surfaces.dart';
import '../theme/legacy_theme_boundary.dart';
import 'launch/launch_ident.dart';
import 'launch/loading_sweep.dart';
import '../services/app_migration_service.dart';
import '../services/main_page_bridge.dart';
import '../services/remote_control/remote_control_state.dart';
import '../services/remote_control/remote_command_router.dart';
import '../utils/platform_util.dart';
import '../widgets/initial_setup_flow.dart';
import '../main.dart';

/// How long the corner spinner takes to fade out on TV. Shared so the widget's
/// fade and _finishSplash's wait for it can never drift apart.
const Duration _kSpinnerFade = Duration(milliseconds: 170);

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
  // Shows the corner spinner during the hold-for-home phase.
  bool _holdingForHome = false;
  bool _isAndroidTv = PlatformUtil.isTelevision;
  // On TV, let MainPage build and fetch behind an opacity-zero render object,
  // but don't raster its first (very expensive) frame while the spinner is
  // moving. _finishSplash gives it a short hidden prepaint window once the
  // spinner has faded out.
  bool _paintHomeBehindSplash = !PlatformUtil.isTelevision;

  late AnimationController _revealController;
  late AnimationController _exitController;
  // Drives the corner spinner while the splash waits for the Home board.
  late AnimationController _idleController;
  late Animation<double> _exitAnimation;
  // The chosen launch ident — its painter, backdrop and sweep accent.
  // Resolved synchronously from the cache warmed in main().
  late LaunchIdent _ident;
  late IdentPalette _palette;
  IdentPalette? _painterPalette;
  late CustomPainter _revealPainter;
  late LoadingSweepPainter _loadingPainter;
  Timer? _homeReadyTimeout;
  bool _finishing = false;
  ReceiverLease? _tvReceiverLease;

  @override
  void initState() {
    super.initState();

    // The launch ident owns the screen from here until the splash fades —
    // system bars and any theme decision must treat the surface as frozen.
    // Re-published here (not only at process start) because the remote-config
    // restart path pushes a fresh AppInitializer mid-session.
    AppSurfaceState.instance.publishBootstrap(true);

    _ident = launchIdentFor(StorageService.launchAnimationCached);
    // The ident's colours: its own by default, the app theme's when the user
    // opted in.
    //
    // Read from `AppThemeController.instance` and NOT from an ambient scope.
    // The splash renders under the bootstrap freeze — `publishBootstrap(true)`
    // three lines up — so `AppThemeScope.of` here would resolve to LEGACY and
    // the feature would silently do nothing. The controller is a singleton
    // already warmed in `main()` before `runApp`, so it is both correct and
    // synchronous, which is what `initState` needs.
    final themed = StorageService.launchIdentPaletteCached == 'theme';
    _palette = themed
        ? IdentPalette.fromTheme(_ident, AppThemeController.instance.theme)
        : _ident.palette;
    // NULL unless the user opted in. `_ident.palette` exposes `sweepColors`
    // as its accent/ink, which are the LOADING SWEEP's colours — not the
    // ring, the tube or the wordmark. Handing that to a painter would repaint
    // the default splash in the sweep's blue, which is a change to what
    // Debrify Classic has always shown. "No palette" must mean "your own
    // literals", and this is what makes that true at runtime as well as in
    // the tests.
    _painterPalette = themed ? _palette : null;

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
      palette: _painterPalette,
    );
    _loadingPainter = LoadingSweepPainter(
      _idleController,
      colors: _palette.sweep,
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

    // NEVER let this read strand the splash. It throws BY DESIGN when the
    // active profile or its data generation moved under it — which is exactly
    // what a remote profile-graph import does: it hands authority to an
    // imported profile mid-onboarding, and the scope change remounts this
    // widget through ProfileGate's epoch key. Before this guard the throw
    // escaped an unguarded async init, so `_splashDone` never flipped and the
    // app rendered NOTHING (the blank screen after an import).
    //
    // Defaulting to "complete" is the safe guess: the only way to reach here
    // with a moved scope is a device that just received a configured profile
    // graph. A wrong guess costs one trip through Home, not a dead screen.
    bool hasCompleted;
    try {
      hasCompleted = await StorageService.isInitialSetupComplete();
    } catch (e) {
      debugPrint('AppInitializer: onboarding state unavailable — $e');
      hasCompleted = true;
    }

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
      // loading phase — the lockup stays put and a small spinner turns in the
      // bottom-right corner — until the board reports its first rows ready. TV
      // then prepaints behind a static lockup; other platforms keep the
      // original fade handoff.
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
      // homeBoardReady is published immediately after Home's setState. Let
      // that pending build/layout frame land before anything else moves.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      // Fade the spinner out while it is still the only moving element on
      // screen. The ring is fully visible at every t — unlike the sweep line
      // it replaced, which was clipped off its own track at t=1 and so could
      // be cut away for free — so there is no orientation at which a
      // zero-duration hide looks intentional. It keeps turning through the
      // fade: freezing it first reads as a stall, and ramping the controller
      // to a fixed angle compressed up to a whole revolution into the ramp,
      // which whipped.
      setState(() => _holdingForHome = false);
      await Future.delayed(_kSpinnerFade);
      if (!mounted) return;
      _idleController.stop();

      // Only now is the splash completely static, so Home can spend a frame
      // rasterizing rows and uploading its first visible textures invisibly
      // without competing with the fade.
      setState(() => _paintHomeBehindSplash = true);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _splashDone = true);
      AppSurfaceState.instance.publishBootstrap(false);
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
    AppSurfaceState.instance.publishBootstrap(false);
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

    // Best-effort. A remote profile-graph import completes onboarding itself
    // and then hands authority to an imported profile, which ProfileGate
    // immediately locks — after which this active-session write is refused
    // ("Active profile session has ended"). Letting that abort the method
    // skipped the setState below, so _splashDone stayed false and the app
    // rendered NOTHING: the blank screen after an import-driven restart.
    try {
      await StorageService.setInitialSetupComplete(true);
    } catch (e) {
      debugPrint('AppInitializer: onboarding flag write skipped — $e');
    }
    if (!mounted) return;

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
    AppSurfaceState.instance.publishBootstrap(false);
    _showPendingPostSetupSnackBarIfNeeded();
  }

  void _showPendingPostSetupSnackBarIfNeeded() {
    final message = MainPageBridge.takePostSetupSnackBar();
    if (message == null || message.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'OPEN SETTINGS',
            onPressed: () => MainPageBridge.switchTab?.call(MainTab.settings),
          ),
        ),
      );
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

      _tvReceiverLease ??= await RemoteControlState().ensureReceiverMode(
        deviceName,
      );

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
      return Scaffold(backgroundColor: _palette.base, body: _buildSplashBody());
    }
    // MainPage stays child 0 of this Stack for BOTH overlay phases (splash up /
    // splash gone) so removing the overlay never reparents it — a reparent
    // would remount the whole shell and restart the loads the splash just
    // waited for.
    return Stack(
      children: [
        // Opacity zero skips painting but not layout, state initialization, or
        // async loads. That is exactly what the TV splash needs: prepare Home
        // without competing with the visible spinner for raster time.
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
      decoration: _palette.backdrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Boundary so the spinner's 60fps ticks don't re-rasterize the
          // (settled) lockup every frame during the hold-for-home phase.
          RepaintBoundary(
            child: CustomPaint(size: Size.infinite, painter: _revealPainter),
          ),
          Align(
            // Bottom-right corner, well clear of the lockup. Inset further on
            // TV: sets overscan the panel edges, and a status detail this
            // small is the first thing a cropped edge would eat.
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(_isAndroidTv ? 48 : 26),
              child: AnimatedOpacity(
                opacity: _holdingForHome ? 1.0 : 0.0,
                // TV fades too, briefly. The ban on opacity layers during the
                // TV handoff is about full-screen fades over an already-
                // rendered Home; an 18x18 RepaintBoundary is nothing, and
                // _finishSplash waits this out before letting Home raster.
                duration: _isAndroidTv
                    ? _kSpinnerFade
                    : const Duration(milliseconds: 350),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(18, 18),
                    painter: _loadingPainter,
                  ),
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
    //
    // LegacyThemeBoundary: launch idents are an excluded surface — they are
    // in-route overlays, not tab bodies or pushed routes, so this is the
    // third containment mechanism (the bootstrap boundary). No messenger:
    // the splash is not a snackbar surface.
    if (_isAndroidTv) return LegacyThemeBoundary(child: splash);
    return LegacyThemeBoundary(
      child: FadeTransition(opacity: _exitAnimation, child: splash),
    );
  }
}
