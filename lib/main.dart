import 'dart:async';
import 'dart:io' show Platform, exit;
import 'dart:ui' show AppExitResponse, PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'utils/app_version_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/app_route_observer.dart';
// Old Home board deprecated — moved to screens/deprecated/ and commented out.
// import 'screens/torrent_search_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/cloud_screen.dart';
import 'screens/search_screen.dart';
import 'widgets/iptv/iptv_results_view.dart';
import 'widgets/youtube/youtube_results_view.dart';
import 'screens/debrid_downloads_screen.dart';
import 'screens/torbox/torbox_downloads_screen.dart';
import 'screens/pikpak/pikpak_files_screen.dart';
import 'screens/premiumize/premiumize_files_screen.dart';
import 'screens/alldebrid/alldebrid_files_screen.dart';
import 'screens/webdav/webdav_files_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/settings/profiles_settings_page.dart';
import 'screens/settings/widgets/settings_widgets.dart' show pushSettingsPage;
import 'screens/profiles/profile_gate.dart';
import 'screens/profiles/linux_vault_screen.dart';
import 'screens/profiles/profile_recovery_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/trakt_calendar_screen.dart';
import 'screens/magic_tv_screen.dart';
import 'screens/stremio_tv/stremio_tv_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/addons_screen.dart';
import 'services/android_native_downloader.dart';
import 'services/discover_prefs.dart';
import 'services/hide_watched_prefs.dart';
import 'services/iptv_catalog_db.dart';
import 'services/profiles/profile_bootstrap.dart';
import 'services/profiles/profile_migration_service.dart';
import 'services/profiles/profile_native_lock_bridge.dart';
import 'services/profiles/profile_registry.dart';
import 'services/profiles/connection_resource_service.dart';
import 'services/profiles/profile_device_reset_service.dart';
import 'services/profiles/profile_lock_controller.dart';
import 'services/profiles/profile_runtime.dart';
import 'services/profiles/privacy_log.dart';
import 'services/profiles/desktop_single_instance.dart';
import 'services/diagnostic_log.dart';
import 'models/profiles/profile_policy.dart';
import 'models/profiles/user_profile.dart';
import 'models/sidebar_configuration.dart';
import 'services/secret_vault.dart';
import 'services/play_loader_style.dart';
import 'services/storage_service.dart';
import 'services/tv_hero_artwork_quality_controller.dart';
import 'services/tvos_top_shelf_service.dart';
import 'services/simkl/simkl_service.dart';
import 'services/trakt/trakt_service.dart';
import 'services/mdblist/mdblist_service.dart';
import 'widgets/app_initializer.dart';

import 'widgets/animated_background.dart';
import 'services/main_page_bridge.dart';
import 'services/profiles/profile_policy_guard.dart';
import 'theme/app_surfaces.dart';
import 'theme/app_theme_controller.dart';
import 'theme/idle_dim.dart';
import 'theme/ui_feedback.dart';
import 'theme/app_texture.dart';
import 'theme/app_theme_scope.dart';
import 'theme/legacy_theme_boundary.dart';
import 'theme/system_bars.dart';
import 'models/rd_torrent.dart';
import 'package:window_manager/window_manager.dart';
import 'services/deep_link_service.dart';
import 'services/magnet_link_handler.dart';
import 'services/stremio_service.dart';
import 'widgets/window_drag_area.dart';
import 'widgets/mobile_floating_nav.dart';
import 'widgets/mobile_classic_nav.dart';
import 'widgets/tv_ambient_art_stage.dart';
import 'widgets/tv_sidebar_nav.dart';
import 'widgets/desktop_pill_nav.dart';
import 'widgets/desktop_sidebar_nav.dart';
import 'services/remote_control/remote_control_state.dart';
import 'services/remote_control/remote_command_router.dart';
import 'services/remote_control/remote_constants.dart';
import 'services/analytics_service.dart';
import 'services/text_brightness.dart';
import 'services/support_remote_config_service.dart';
import 'widgets/auto_launch_overlay.dart';
import 'widgets/remote/addon_install_dialog.dart';
import 'widgets/remote/remote_pairing_dialog.dart';
import 'widgets/remote/remote_role_picker_screen.dart';
import 'widgets/support_donation_chooser_dialog.dart';
import 'utils/platform_util.dart';
import 'utils/tvos_device.dart';
import 'services/desktop_recording_service.dart';
import 'services/desktop_schedule_service.dart';
import 'services/update_service.dart';

/// Flutter's default image cache (1000 images / 100 MB) is far too large for a
/// 2 GB Android TV box — a screenful of full-res posters plus offscreen ones
/// pushes it into the OS low-memory killer. Cap it on TV only; phones, tablets
/// and desktop keep the framework defaults untouched. Evicted posters are
/// re-fetched from the on-disk cache, so this trades a little re-decode for a
/// much smaller resident footprint on the constrained device.
Future<void> _capImageCache() async {
  var isTv = false;
  try {
    // Via PlatformUtil (not AndroidNativeDownloader) so this also warms
    // PlatformUtil.isAndroidTvCached before runApp — the synchronous flag the
    // theme's page-transition builder reads on every route push.
    isTv = await PlatformUtil.isAndroidTV();
  } catch (_) {}
  // Apple TV is a television too, and [PlatformUtil.isAndroidTV] short-circuits
  // to false whenever the platform is not Android — so without this the caps
  // below never reach a device that needs them just as much as a TV box does.
  isTv = isTv || PlatformUtil.isTvOS;
  // When the TV probe FAILED (as opposed to answering "no"), cap any Android
  // device: the asymmetry decides it. A phone mistakenly capped loses a
  // little cache headroom; a 1 GB TV box mistakenly left on Flutter's stock
  // 100 MB / 1000-image cache is an OOM kill. The probe failing at all is
  // rare (early-startup channel hiccup), so phones almost never pay this.
  final capAnyway =
      !isTv && !kIsWeb && Platform.isAndroid && PlatformUtil.lastProbeFailed;
  if (!isTv && !capAnyway) {
    return; // leave non-TV devices on the framework defaults
  }
  if (isTv) {
    // Warm the Debrify-keyboard opt-out alongside the TV flag — TvTextField
    // reads StorageService.tvKeyboardEnabledCached synchronously in build.
    try {
      await StorageService.getTvKeyboardEnabled();
    } catch (_) {}
  }
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 140;
  // 56 MB bounds the decoded-image working set. Hero Artwork Quality can use
  // an ~8 MB Full HD landscape texture, but only the active/outgoing hero pair
  // overlaps; the cache evicts older artwork rather than expanding resident
  // memory on a constrained TV box.
  cache.maximumSizeBytes = 56 << 20; // 56 MB
  if (TvosDevice.isLowMemoryCached) {
    // The 2-3 GB Apple TV generations get roughly half the jetsam budget of
    // a modern unit; these devices also decode at the performance artwork
    // size, so the smaller cache still holds a full screen of cards.
    cache.maximumSize = 100;
    cache.maximumSizeBytes = 36 << 20; // 36 MB
  }
}

// The TV-aware page transition moved to `theme/app_theme_adapter.dart`
// (TvAwarePageTransitionsBuilder) along with the root ThemeData construction
// it belongs to — both are shared by the legacy and themed builds.

Future<void> main(List<String> launchArguments) async {
  try {
    await _mainUnchecked(launchArguments);
  } catch (error, stackTrace) {
    WidgetsFlutterBinding.ensureInitialized();
    // Best effort only: diagnostics must never turn an existing startup
    // failure into a second failure or delay the fallback screen indefinitely.
    try {
      await DiagnosticLog.instance.initialize();
      DiagnosticLog.instance.recordError(
        source: 'app',
        event: 'bootstrap_failure',
        error: error,
        stackTrace: stackTrace,
        flushImmediately: false,
      );
      await DiagnosticLog.instance.flush();
    } catch (_) {}
    debugPrint('Application bootstrap failed (${error.runtimeType})');
    debugPrint('$stackTrace');
    // Describing the failure must never become a second failure: an
    // exception here would leave runApp uncalled and the user staring at a
    // blank window, which is strictly worse than the screen this block
    // exists to show. The screen renders with or without the detail.
    String? detail;
    try {
      detail = _describeStartupFailure(error, stackTrace);
    } catch (_) {
      detail = null;
    }
    runApp(_StartupFailureApp(detail: detail));
  }
}

/// One bounded, redacted line naming what actually failed, for
/// [_StartupFailureApp].
///
/// A user who cannot produce a log can still photograph a screen — the same
/// reasoning that put [ProfileBootstrap.legacyReason] on the Profiles row.
/// Without this the screen says only "could not start safely" and the console
/// prints a bare runtimeType, so a desktop report (issue #35) carries nothing
/// to act on: every startup failure looks identical.
///
/// The first stack frame usually names the failing subsystem, which is the
/// difference between "a migration threw" and knowing WHICH one. Redacted
/// through [PrivacyLog] because this text is meant to be shared, and bounded
/// because a photographed screen cannot be scrolled.
String _describeStartupFailure(Object error, StackTrace stackTrace) {
  String clamp(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max - 1)}…';
  // Truncate BEFORE redacting. A sealed-payload or HTTP-body error can carry
  // megabytes, and [PrivacyLog.redact] runs several regexes across the whole
  // string before applying its own cap — on the one code path that must stay
  // fast and allocation-light, because it is already handling a crash.
  final message = PrivacyLog.redact(
    clamp(error.toString(), 2000).replaceAll('\n', ' '),
  );
  final described = message.startsWith('${error.runtimeType}')
      ? message
      : '${error.runtimeType}: $message';
  final frame = stackTrace
      .toString()
      .split('\n')
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
      .trim();
  if (frame.isEmpty) return clamp(described, 300);
  return '${clamp(described, 300)}\n${clamp(PrivacyLog.redact(frame), 160)}';
}

Future<void> _mainUnchecked(List<String> launchArguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await DiagnosticLog.instance.initialize();
  // On a release tvOS build, Dart's print() lands on stdout, which the device
  // console does not carry — so Flutter errors, and anything we log while
  // bringing the port up, are simply invisible on real hardware. Forward
  // debugPrint (which the framework's own error reporting also routes through)
  // to a native channel that NSLogs it, where `devicectl --console` can see it.
  // Debug/profile only: in release this would funnel every debugPrint in the
  // app — tokens and URLs among them — into the device log.
  if (PlatformUtil.isTvOS && !kReleaseMode) {
    const channel = MethodChannel('debrify/tvlog');
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) {
        channel.invokeMethod<void>('log', message).catchError((_) {});
      }
    };
    final view = PlatformDispatcher.instance.views.first;
    debugPrint(
      '[tvOS] physicalSize=${view.physicalSize} dpr=${view.devicePixelRatio}',
    );
  }
  // Install after the optional tvOS sink so that both the Dart console and
  // native device console receive only the redacted form.
  PrivacyLog.install();
  final priorFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    DiagnosticLog.instance.recordFlutterError(details);
    if (priorFlutterErrorHandler != null) {
      priorFlutterErrorHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  // Backstop for async errors nothing awaited (fire-and-forget loads,
  // .then chains without onError). Keep only the stable type and bounded
  // stack in the private rolling log; exception bodies stay console-only.
  PlatformDispatcher.instance.onError = (error, stack) {
    DiagnosticLog.instance.recordError(
      source: 'dart',
      event: 'unhandled_async_error',
      error: error,
      stackTrace: stack,
    );
    debugPrint('Unhandled async error (${error.runtimeType})');
    return true;
  };
  DiagnosticLog.instance.recordEvent(
    source: 'app',
    event: 'session_start',
    fields: <String, Object?>{
      'platform': DiagnosticLabel(kIsWeb ? 'web' : Platform.operatingSystem),
      'buildMode': DiagnosticLabel(
        kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
      ),
    },
  );
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
  }

  // Initialize sqflite FFI for Windows/Linux desktop (sqflite needs FFI on these platforms)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (!kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
      !await DesktopSingleInstance.acquire(launchArguments)) {
    exit(0);
  }

  if (await ProfileDeviceResetService.resumeWithoutRegistryIfNeeded()) {
    await _terminateAfterDeviceReset();
    return;
  }

  // Recovery is mounted before the normal startup warm chain. Resolve TV mode
  // here so its passphrase prompt never falls through to the system TextField
  // path on Chromecast/Google TV. A failed Android probe is treated as TV-safe
  // for this one terminal surface only; a phone seeing the in-app keyboard is
  // recoverable, while a TV seeing an unusable IME can strand the only backup.
  var recoveryNeedsTvSafeInput = PlatformUtil.isTvOS;
  if (!kIsWeb && Platform.isAndroid) {
    final detectedTv = await PlatformUtil.isAndroidTV();
    recoveryNeedsTvSafeInput = detectedTv || PlatformUtil.lastProbeFailed;
  }

  // A legacy install with real media databases is about to be migrated into
  // the profile store — a one-time job that can run for MINUTES on weak TV
  // hardware (integrity scans + hashes over every byte of the IPTV catalog).
  // Without a frame on screen first that whole window is a black screen:
  // users assume a hang, force-close, and restart the migration from
  // scratch. Post-migration launches and fresh installs skip this (authority
  // committed / no legacy databases), so nothing ever flashes.
  //
  // The probe is authority-COMMITTED, deliberately not file-exists: opening
  // the registry creates profiles.db BEFORE migration runs, so a force-close
  // mid-migration leaves the file present while the work is all still ahead —
  // exactly the retry launch that needs this screen the most.
  if (!kIsWeb &&
      ProfileBootstrap.profilesEnabled &&
      ProfileBootstrap.migrationRolloutReady &&
      !await ProfileRegistry.defaultAuthorityIsCommitted() &&
      await ProfileMigrationService.legacyMediaDatabasesExist()) {
    runApp(const _MigrationUpdateScreen());
    // The migration owns startup the moment initialize() runs — make sure
    // the message actually reaches the panel before that happens.
    await WidgetsBinding.instance.endOfFrame;
  }

  // Publish legacy/profile storage mode before any preference, credential,
  // cache, route, or background service can observe application state.
  try {
    await ProfileBootstrap.initialize();
  } on ProfileBootstrapRecoveryRequired {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        home: ProfileRecoveryScreen(
          onRecovered: _resumeAfterProfileRecovery,
          onResetComplete: _terminateAfterDeviceReset,
          forceTvSafeInput: recoveryNeedsTvSafeInput,
        ),
      ),
    );
    return;
  }

  if (ProfileRuntime.isProfileCommitted &&
      await ProfileDeviceResetService.journalExists()) {
    await ProfileDeviceResetService.resumeWithRegistry(
      ProfileBootstrap.registry,
    );
    await _terminateAfterDeviceReset();
    return;
  }

  if (ProfileRuntime.isProfileCommitted) {
    // Capture OS/desktop launch payloads before ProfileGate. They are sealed
    // device-wide and remain unassigned until local unlock.
    await DeepLinkService.preflightLaunchIntent();
    await DeepLinkService.persistPreflightActions();
  }

  if (ProfileBootstrap.requiresLinuxVault) {
    runApp(
      _LinuxVaultBootstrapHost(
        existingVault: ProfileBootstrap.linuxVaultAlreadyConfigured,
      ),
    );
    return;
  }

  await _continueApplicationStartup();
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({this.detail});

  /// What failed, from [_describeStartupFailure]; null only if the failure
  /// somehow produced no describable error.
  final String? detail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Debrify could not start safely. Close the app and try again. '
                  'If this continues, restart the device before changing any data.',
                  textAlign: TextAlign.center,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Please share this with support:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  // Selectable so a desktop reporter can paste it rather than
                  // retype a photographed stack frame.
                  SelectableText(
                    detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _resumeAfterProfileRecovery() async {
  await DeepLinkService.preflightLaunchIntent();
  await DeepLinkService.persistPreflightActions();
  await _continueApplicationStartup();
}

/// The one-time post-update screen. Everything it promises is true: the
/// migration is atomic and resumable, so closing the app is SAFE — but it
/// restarts the work from scratch, which is exactly the loop this screen
/// exists to prevent. Deliberately self-contained (no theme/pref warms have
/// run yet) and dark, matching the launch surface.
class _MigrationUpdateScreen extends StatelessWidget {
  const _MigrationUpdateScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF05070E),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Finishing the update…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Debrify is upgrading your library for this new version. '
                    'This launch can take up to 5 minutes on large setups — '
                    'please don’t close the app or turn off the device. '
                    'This only happens once.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 16,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _terminateAfterDeviceReset() async {
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    exit(0);
  }
  await SystemNavigator.pop();
}

/// Run a startup step that must never stop the app from starting.
///
/// Everything past [ProfileBootstrap] is warms and one-time migrations:
/// convenience work whose honest worst case is a stale first frame, or a
/// migration that simply retries on the next launch. Until this existed a
/// single throw from any of them reached [main]'s catch and replaced the
/// entire app with [_StartupFailureApp] — so one odd legacy row could lock a
/// user out of Debrify completely (issue #35, a 0.7.0-era install that could
/// not open 0.8.3 at all). Failing these is recoverable; refusing to start is
/// not.
///
/// The label names the step, so a failure is identifiable from the log alone
/// even when the reporter cannot attach a debugger. Steps that must be
/// atomic own that inside themselves: each one below either completes and
/// records its own generation marker, or writes nothing and runs again.
Future<void> _bestEffortStartupStep(
  String step,
  Future<void> Function() run,
) async {
  try {
    await run();
  } catch (error, stackTrace) {
    debugPrint('main: startup step "$step" failed (${error.runtimeType})');
    debugPrint('$stackTrace');
  }
}

Future<void> _continueApplicationStartup() async {
  // This common path is also entered after registry recovery and interactive
  // Linux vault unlock; both must receive the same native lock authority as a
  // normal bootstrap.
  ProfileNativeLockBridge.initialize();
  // These initializers may touch profile-sensitive state and therefore start
  // only after the immutable runtime mode and active scope are installed.
  unawaited(AnalyticsService.init());
  if (!ProfileRuntime.isProfileCommitted) {
    unawaited(SecretVault.warmUp());
  }

  // Set a sensible default orientation: phones stay portrait, Android TV uses
  // landscape. _initOrientation warms PlatformUtil's TV cache, so the
  // _capImageCache call right after resolves without a second channel trip.
  await _initOrientation();
  // Warms playerStartPortraitCached: the player picks its orientation while
  // building, and the IPTV startup channel can open one on the first frame.
  await StorageService.getPlayerStartPortrait();
  // Update-aware defaults: one-time adoption of the current flagship look
  // for every pref the user never wrote (see migrateDefaultsGeneration).
  // MUST precede the brightness/theme warms below — they read migrated keys
  // for the very first frame.
  await _bestEffortStartupStep(
    'defaults-generation-migration',
    StorageService.migrateDefaultsGeneration,
  );
  // Adopt the configurable local watched thresholds for playback recorded by
  // older builds. The generation marker is profile-scoped, so every profile
  // migrates once when it next becomes active. Best-effort because it parses
  // playback state written by builds as old as 0.7.0: an entry whose shape
  // drifted must cost the user a watched badge, not the whole app.
  await _bestEffortStartupStep(
    'playback-completion-migration',
    StorageService.migrateExistingPlaybackCompletionThresholds,
  );
  // Drop the zero-position rows older builds left behind when unwatching an
  // episode; they outrank real progress and pin Continue Watching to an
  // episode the user already declared unwatched. Also profile-scoped and
  // one-shot, and best-effort for the same reason as the step above.
  await _bestEffortStartupStep(
    'resume-ghost-purge',
    StorageService.purgeUnwatchedResumeGhosts,
  );
  // Warm the layout prefs the shell reads through field initializers —
  // without this the first frame paints canvas/ghost/rail and then snaps
  // to the stored (possibly just-migrated) look. A warm that fails costs
  // that one snap; it must not cost the launch.
  await _bestEffortStartupStep('layout-pref-warms', () async {
    await StorageService.getTvHomeStyle();
    await StorageService.getTvSidebarStyle();
    await StorageService.getDesktopSidebarStyle();
    await StorageService.getSidebarConfiguration();
    // Debrify TV reads its mirror synchronously on first build; warmed here,
    // AFTER the migration, so frame one draws what generation 3 just wrote.
    await StorageService.getDebrifyTvStyle();
  });
  // Warms the Appearance → Text Brightness preset: the root theme is built
  // synchronously in DebrifyApp.build, so the stored choice must be readable
  // before the first frame or text would flash bright and then dim.
  await _bestEffortStartupStep(
    'text-brightness-warm',
    TextBrightnessController.warm,
  );
  // Warms Appearance → Play Loader. The play path reads it synchronously (a
  // play cannot await a preference), so an unwarmed session would show Marquee
  // to someone who chose Classic.
  await _bestEffortStartupStep(
    'play-loader-style-warm',
    PlayLoaderStyleController.warm,
  );
  // Warms the app theme AFTER the preset (it is an input), for the same
  // reason: the controller's memoized ThemeData is read in the first build.
  await _bestEffortStartupStep('app-theme-warm', AppThemeController.warm);
  // From here the system-bar owner is the authority — it re-applies on every
  // active-surface or theme change (the _initOrientation call below remains
  // the pre-warm default and matches the legacy style anyway).
  SystemBarsOwner.init();
  // The traversal-feedback dispatcher. Installed AFTER the theme controller
  // because it reads the live theme's sound tokens, and it is a no-op under
  // every theme that asks for silence — which is all of them except Console.
  // Warm the two feedback vetoes before installing the dispatcher: it is
  // consulted from a focus listener that cannot await, so an unwarmed read
  // would use the default for the first few seconds of a session.
  try {
    await StorageService.getUiSounds();
    await StorageService.getUiHaptics();
  } catch (_) {
    debugPrint('main: feedback preferences warm failed; using defaults');
  }
  UiFeedback.instance.install();
  // The idle compositor. Also a no-op under every look with no idle policy,
  // and TV-only in v1 — a phone in a pocket already has a screen timeout.
  IdleDim.instance.install();
  // Bridge the trailer's chrome dim into the compositor's trailer input. The
  // notifier stays where it is — the screens that publish it are the ones that
  // know a trailer is playing — and the compositor only needs to SEE it. It
  // also suspends the idle timer while a trailer runs: idle must never arm
  // during playback, and it restarts from zero when the trailer ends.
  MainPageBridge.tvChromeDim.addListener(() {
    final v = MainPageBridge.tvChromeDim.value;
    IdleDim.instance.trailerDim.value = v;
    if (v > 0) {
      IdleDim.instance.suspend(MainPageBridge.tvChromeDim);
    } else {
      IdleDim.instance.resume(MainPageBridge.tvChromeDim);
    }
  });
  // Warms the launch-ident choice: AppInitializer builds the splash in its
  // initState, so an async-only read would flash the default ident's world
  // for a frame. A cosmetic pref must never block startup.
  try {
    await StorageService.getLaunchAnimation();
    await StorageService.getLaunchIdentPalette();
  } catch (_) {}
  // Warms the details-page layout choice: MergedDetailScreen picks its body in
  // the first build, so an async-only read would paint Classic for a frame and
  // then re-lay-out the entire page. Same rule — a cosmetic pref must never
  // block startup.
  try {
    await StorageService.getDetailPageStyle();
  } catch (_) {}
  // And the details THEME, for the same reason — the page resolves both in its
  // first build, so a stored choice must be readable before the first frame.
  try {
    await StorageService.getDetailTheme();
  } catch (_) {}
  // Parents Guide chooses its presentation synchronously when metadata lands.
  // Warm the cosmetic preference so a stored Classic choice never flashes
  // Compass for one frame.
  try {
    await StorageService.getParentsGuideStyle();
  } catch (_) {}
  // Apple TV hardware generation, warmed FIRST because everything below keys
  // off it: the artwork decode bounds, the image-cache cap, the Home board's
  // ambient trailer, and the Top Shelf preview exporter all downshift on the
  // 2-3 GB units (Apple TV HD, and both the 2017 and 2021 4K models).
  try {
    await TvosDevice.warm();
  } catch (_) {}
  // Resolve TV hero decode bounds before first paint. Otherwise a stored Full
  // HD choice would first decode the default smaller image, then immediately
  // throw it away and upload a second texture when the async preference lands.
  try {
    await TvHeroArtworkQualityController.warm();
  } catch (_) {}
  await _capImageCache();
  await _resolveStartupChannel();
  // Install the Top Shelf action listener before the first Home frame. A cold
  // launch can already carry a title selected on the Apple TV Home Screen;
  // non-tvOS builds return immediately and create no channel traffic.
  await TvosTopShelfService.instance.initialize();
  // Discover's remembered Sort per source, warmed before first frame so the
  // panels can read it synchronously in initState and paint already-sorted.
  // Cheap: SharedPreferences is already open by this point.
  await DiscoverPrefs.warmUp();
  // Same for the hide-watched switch: the catalog filter reads it inline.
  await HideWatchedPrefs.warmUp();
  // Old-playback-state cleanup is pure housekeeping — never block first frame
  // on a storage sweep (slow flash on TV boxes).
  unawaited(_cleanupPlaybackState());
  // NB: no manual app_open — Pug's autoTrack fires app_open/app_close from the
  // app lifecycle automatically (see AnalyticsService.init / PugOptions).
  runApp(const DebrifyApp());
  // Desktop scheduled recordings (Tier 1: fire while the app is running).
  // Arms stored timers + late-joins anything already in its window; no-op on
  // non-desktop platforms.
  unawaited(DesktopScheduleService.instance.init());
  // Desktop captures outlive the screen that started them, so their endings
  // and their final flush need an owner that outlives it too.
  _wireDesktopRecordings();
  // Prepare the paged IPTV catalog while the user is on the startup/home
  // experience. The expensive file open and schema work run on a worker
  // isolate after first paint; opening IPTV later shares this future or finds
  // the DB ready.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_prewarmIptvCatalogDb());
  });

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class _LinuxVaultBootstrapHost extends StatelessWidget {
  final bool existingVault;

  const _LinuxVaultBootstrapHost({required this.existingVault});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData.dark(useMaterial3: true),
    home: LinuxVaultScreen(
      existingVault: existingVault,
      onSubmit: (passphrase) async {
        await ProfileBootstrap.completeLinuxVault(passphrase);
        if (ProfileRuntime.isProfileCommitted) {
          await DeepLinkService.preflightLaunchIntent();
          await DeepLinkService.persistPreflightActions();
        }
        await _continueApplicationStartup();
      },
    ),
  );
}

/// Resolve the IPTV startup channel BEFORE runApp.
///
/// It has to be settled synchronously by the time `_MainPageState` is
/// constructed: `_selectedIndex` is a field initializer, so an async prefs read
/// would land after the first build — Home would mount and begin its cold-start
/// IO before we could swap to IPTV, which is both a visible flash and wasted
/// work. Same reasoning as [PlatformUtil.isAndroidTvCached] being warmed here.
///
/// The launch intent is resolved first and wins: opening the app with a magnet
/// or a shared link is an explicit request that must not be buried under an
/// auto-tuned channel.
Future<void> _resolveStartupChannel() async {
  try {
    // Cheap prefs read FIRST. The intent preflight below costs two platform
    // channel round trips, and this runs before the first frame on every cold
    // start — making every user pay that so the small minority with a startup
    // channel can have one would be a plain boot regression.
    if (!await StorageService.getStartupIptvEnabled()) return;
    await DeepLinkService.preflightLaunchIntent();
    if (DeepLinkService.launchedByIntent) return;
    await StorageService.warmStartupIptv();
    final channel = StorageService.startupIptvChannelCached;
    if (channel != null) {
      MainPageBridge.setIptvStartupChannel(channel);
    }
  } catch (_) {
    // A startup channel is a convenience; never let it break the boot.
    debugPrint('Startup channel resolve failed');
  }
}

Future<void> _prewarmIptvCatalogDb() async {
  if (kIsWeb) return;
  try {
    // Most users never configure IPTV. Do not create a database or compete
    // with Home startup IO unless a stored source could actually use the
    // paged catalog.
    if ((await StorageService.getIptvPlaylists()).isEmpty) return;
    await IptvCatalogDb.open();
  } catch (_) {
    // Prewarming is an optimization. The IPTV page retries through the same
    // open path and owns the user-visible error/loading state if it still
    // cannot initialize.
    debugPrint('IPTV catalog prewarm failed');
  }
}

Future<void> _initOrientation() async {
  try {
    // If running on Android TV, prefer landscape. Otherwise allow all orientations (respect auto-rotate).
    // Via PlatformUtil so this single channel call also warms
    // PlatformUtil.isAndroidTvCached for everything downstream.
    final isTv = await PlatformUtil.isAndroidTV();
    _updateFocusHighlightStrategy(isTv);
    if (isTv) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // Allow all orientations to respect device auto-rotate setting
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // Set transparent navigation bar for edge-to-edge display
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  } catch (_) {
    _updateFocusHighlightStrategy(false);
    // Fallback to all orientations if detection fails
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Set transparent navigation bar for edge-to-edge display
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
}

void _updateFocusHighlightStrategy(bool isTv) {
  final target = isTv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
  if (FocusManager.instance.highlightStrategy != target) {
    FocusManager.instance.highlightStrategy = target;
  }
}

Future<void> _cleanupPlaybackState() async {
  try {
    await StorageService.cleanupOldPlaybackState();
  } catch (e) {}
}

// Global scaffold messenger key for showing snackbars from anywhere
final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Give desktop recordings a process-scoped owner.
///
/// A capture belongs to the SERVICE, not to whatever screen pressed Record:
/// close the player and it keeps running, exactly like the Android engine's
/// (the Recordings hub is its stop control either way). Two jobs follow from
/// that, and neither can live in a screen:
///
/// * **Endings nobody asked for** — a stream that drops or hits the 6h cap
///   after the player closed used to report to a dead callback. Announced here
///   instead, so it lands wherever the user actually is.
/// * **The final flush** — the HTTP pipe lives in THIS process, so quitting
///   truncates whatever is mid-write. Only cancelable exits get a say; a
///   force-quit or a crash still loses the tail (a raw .ts survives it).
void _wireDesktopRecordings() {
  final service = DesktopRecordingService.instance;
  if (!service.isSupported) return;
  service.lastEnding.addListener(() {
    final report = service.lastEnding.value;
    if (report == null) return;
    final channel = report.channelName.trim();
    final subject = channel.isEmpty ? 'Recording' : 'Recording of $channel';
    final message = switch (report.end) {
      // Whoever asked for the stop reports it themselves, with the size.
      DesktopRecordingEnd.stopped => null,
      DesktopRecordingEnd.streamEnded => '$subject ended — the stream stopped',
      DesktopRecordingEnd.durationCap => '$subject saved (6h limit)',
      // bytes > 0 survives on disk even here (a mid-write crash keeps what it
      // wrote); only the zero-byte case deletes its own file.
      DesktopRecordingEnd.failed =>
        report.bytes > 0
            ? '$subject failed — the partial file was kept'
            : '$subject failed — nothing was captured',
    };
    if (message == null) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  });
  // Unheld on purpose and never disposed: the constructor registers it with
  // WidgetsBinding, which keeps it alive for as long as the process — exactly
  // the scope this needs.
  AppLifecycleListener(
    onExitRequested: () async {
      // Never let a wedged capture hold the window hostage: a truncated .ts
      // still plays, a quit that never finishes does not.
      await service.stopAll().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
      return AppExitResponse.exit;
    },
  );
}

// Global navigator key for app navigation (used for remote config restart)
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class DebrifyApp extends StatefulWidget {
  const DebrifyApp({super.key});

  @override
  State<DebrifyApp> createState() => _DebrifyAppState();
}

class _DebrifyAppState extends State<DebrifyApp> {
  @override
  void initState() {
    super.initState();
    // Rebuild the root when the Text Brightness preset changes: a new
    // ThemeData is an inherited-widget change, so every open screen re-themes
    // in place — including const subtrees, which a mutable color token could
    // never reach (same instance → the element short-circuits the rebuild).
    TextBrightnessController.notifier.addListener(_onTextBrightnessChanged);
    // Same contract for the app theme: the controller memoizes the derived
    // ThemeData/AppTheme pair, so this rebuild only ever READS them — the
    // recompute happened once, inside the controller, when the change fired.
    AppThemeController.instance.addListener(_onAppThemeChanged);
  }

  void _onTextBrightnessChanged() {
    if (mounted) setState(() {});
  }

  void _onAppThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TextBrightnessController.notifier.removeListener(_onTextBrightnessChanged);
    AppThemeController.instance.removeListener(_onAppThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Set up scaffold messenger key for remote command router (TV feedback)
    RemoteCommandRouter().setScaffoldMessengerKey(_scaffoldMessengerKey);

    // The router raises real routes too: the fallback pairing-code dialog
    // when no receive screen is mounted (TV sitting on Home), and the
    // legacy-consent dialog for v1 senders. Without this key neither can
    // appear — the phone would ask for a code the TV never shows.
    RemoteCommandRouter().setNavigatorKey(_navigatorKey);

    // Set up restart callback for remote config (when TV receives setup from phone)
    RemoteCommandRouter().setRestartCallback(() {
      // Keep the existing root ProfileGate alive. Mounting a replacement
      // before the old route's exit animation disposes can let the old gate
      // revoke the new gate's global lock timer and remote lease.
      //
      // Clearing the routes above the gate is normally the GATE's job — only
      // it can name the route that must survive, and it anchors popUntil on
      // that route object (see ProfileGate._openPicker). Popping from here by
      // position instead can empty the navigator and leave nothing to paint.
      unawaited(() async {
        await WidgetsBinding.instance.endOfFrame;
        // Branch on the RUNTIME MODE, never on whether the callback happens to
        // be installed: a null callback in committed mode means the gate is
        // momentarily absent, and falling through to the positional pop would
        // empty the navigator and blank the screen.
        if (ProfileRuntime.isProfileCommitted) {
          // Unconditional, even for a sole profile: a scope change does not
          // reload the gate (its epoch key remounts only the child), so after
          // an import hands authority over — possibly retiring the bootstrap
          // profile down to one imported Admin — the gate still holds
          // `_entered = true` and a lock controller describing a profile that
          // no longer exists. _openPicker relocks and reloads; the gate's own
          // logic then decides whether to ask.
          MainPageBridge.showProfilePicker?.call();
          return;
        }
        // LEGACY MODE. ProfileGate installs no picker here, so nothing else
        // dismisses the onboarding route — the flow only flips to its success
        // panel on `config/complete` and leaves dismissal to this callback.
        // Without a pop the user is stranded on that panel with a fully
        // imported device behind it.
        //
        // `isFirst` is safe on THIS path specifically: legacy mode never
        // pushes a gate/picker above the root, so the predicate is guaranteed
        // to match the home route. Do NOT reach for a canPop loop — pop() only
        // starts the exit animation and leaves the route in history, so a loop
        // over-pops and empties the navigator.
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }());
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      navigatorObservers: [appRouteObserver, AppSurfaceRouteObserver()],
      title: 'Debrify',
      debugShowCheckedModeBanner: false,
      // Performance optimizations for TV with TV-aware text scaling
      builder: (context, child) {
        // Synchronous TV flag — warmed in main() before runApp. The previous
        // FutureBuilder here re-issued an isTelevision channel call and
        // rebuilt the entire app subtree every time this builder ran.
        final isTv = PlatformUtil.isTelevision;

        // The app-theme token scope, ABOVE the root Navigator (builder's
        // child IS the Navigator): every route, dialog, sheet and root
        // overlay inherits it, and excluded surfaces shadow it lower down
        // with a LegacyThemeBoundary. An open overlay restyles live on theme
        // change for free — it inherits from here, not from a capture.
        Widget content = AppThemeScope(
          theme: AppThemeController.instance.theme,
          // The theme's whole-page texture — film grain, Blueprint's rule.
          // INSIDE the scope so it can read the tokens, and self-gating on
          // AppSurfaceState so it never paints over the frozen player or the
          // launch ident (see app_texture.dart). It short-circuits to `child`
          // for legacy and for the seventeen themes that declare neither, so
          // the common path costs one build and no layer.
          child: AppTexture(child: child!),
        );
        // Pointer input counts as presence too — an Apple TV remote's
        // trackpad and an attached mouse both arrive here rather than through
        // the key handler. `Listener` at the root sees moves and downs
        // regardless of what any descendant does with them, and behavior
        // deferToChild keeps it from claiming a single hit.
        content = Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => IdleDim.instance.noteInput(),
          onPointerHover: (_) => IdleDim.instance.noteInput(),
          child: content,
        );
        if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
          content = Focus(
            autofocus: false,
            canRequestFocus: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                // Check if in fullscreen and exit
                windowManager.isFullScreen().then((isFullScreen) {
                  if (isFullScreen) {
                    windowManager.setFullScreen(false);
                  }
                });
                // Don't consume the event - let it propagate to video player etc.
                return KeyEventResult.ignored;
              }
              return KeyEventResult.ignored;
            },
            child: content,
          );
        }

        // Map the remote "OK" keycodes to widget activation app-wide.
        // Flutter's default only maps enter/space to ActivateIntent, but TV
        // remotes commonly send KEYCODE_DPAD_CENTER (select) or
        // KEYCODE_BUTTON_A (gameButtonA), which otherwise leave plain
        // Material controls (InkWell / IconButton / DropdownButton / ListTile)
        // dead on OK. This mirrors [isActivateKey] and is purely additive —
        // screens with their own onKeyEvent activation still take precedence
        // (Focus.onKeyEvent runs before Shortcuts), so nothing regresses.
        content = Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          },
          child: content,
        );

        final mq = MediaQuery.of(context).copyWith(
          // TV: no text scaling at all — a 10-foot layout is already sized for
          // the room, and scaling it overflows rows.
          //
          // Mobile: respect accessibility, capped at 1.3 so layouts hold. This
          // CLAMPS the platform's own scaler rather than sampling it once at
          // size 1.0 and rebuilding a linear one: Android's scaler is
          // non-linear (it grows small text more than headings), so flattening
          // it to a single multiplier threw that curve away and mis-sized
          // large text for anyone using a non-default font size.
          textScaler: isTv
              ? TextScaler.noScaling
              : MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
        );

        // Apple TV hands Flutter a devicePixelRatio of 1.0, so the logical
        // canvas is the full 1920x1080. Android TV reports 2.0 for the very
        // same panel — a 960x540 canvas — and every dimension in this app (type
        // scale, padding, card and row sizes, focus rings) was designed against
        // that. Left alone, the entire UI draws at half its intended physical
        // size: fine at a desk, unreadable from a sofa.
        //
        // The embedder won't tell us otherwise — the engine reads UIScreen.scale
        // (pinned to 1.0 on tvOS) and ignores the view's contentScaleFactor — so
        // halve the logical canvas here and scale the tree back up to fill the
        // surface. Rasterisation still happens at the full 1920x1080, so this
        // costs no sharpness. Placed inside MaterialApp.builder so routes,
        // dialogs and overlays all sit within the scaled subtree.
        if (PlatformUtil.isTvOS) {
          const factor = 2.0;
          final scaled = Size(mq.size.width / factor, mq.size.height / factor);
          return MediaQuery(
            data: mq.copyWith(
              size: scaled,
              devicePixelRatio: mq.devicePixelRatio * factor,
              // Drop the tvOS overscan safe area. Apple TV reports ~80pt
              // horizontal / ~60pt vertical insets; Android TV reports none,
              // and this UI already carries its own 10-foot margins — so
              // honouring these too insets everything a second time and leaves
              // the whole app floating in the middle of the panel with the
              // backdrop showing around it. The layouts are the safe area.
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: mq.viewInsets / factor,
            ),
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: scaled.width,
                height: scaled.height,
                child: content,
              ),
            ),
          );
        }

        return MediaQuery(data: mq, child: content);
      },
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        // Optimize scroll physics for TV
        physics: const ClampingScrollPhysics(),
        // A mouse can drag a list, which by default it cannot: Flutter's
        // dragDevices defaults to touch-like devices only and deliberately
        // leaves `mouse` out. That is survivable on a vertical page, where
        // the wheel scrolls anyway, and fatal on a horizontal rail — the
        // wheel reports only dy, and a horizontal Scrollable reads dx, so
        // the rail answers to nothing a mouse user would try. Shift+wheel
        // flips the axis but nobody discovers that.
        //
        // It went unnoticed because a trackpad is BOTH in the default set
        // and a real source of dx, so every rail behaves perfectly on a
        // laptop. Only a mouse shows the bug.
        //
        // Touch and DPAD are unaffected; this only adds an input.
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      // Memoized in AppThemeController — under `legacy` this is byte-for-byte
      // the theme the app has always shipped (the construction moved verbatim
      // into theme/app_theme_adapter.dart, Text Brightness pass included).
      theme: AppThemeController.instance.themeData,
      home: const ProfileGate(child: AppInitializer()),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _SupportCampaignDialog extends StatefulWidget {
  final SupportCampaignConfig campaign;
  final Future<void> Function() onDismissForever;

  const _SupportCampaignDialog({
    required this.campaign,
    required this.onDismissForever,
  });

  @override
  State<_SupportCampaignDialog> createState() => _SupportCampaignDialogState();
}

class _SupportCampaignDialogState extends State<_SupportCampaignDialog> {
  final FocusNode _maybeLaterFocusNode = FocusNode(
    debugLabel: 'supportMaybeLater',
  );
  final FocusNode _dismissFocusNode = FocusNode(
    debugLabel: 'supportDismissForever',
  );
  final FocusNode _donateFocusNode = FocusNode(debugLabel: 'supportDonate');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _donateFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _maybeLaterFocusNode.dispose();
    _dismissFocusNode.dispose();
    _donateFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      child: FocusScope(
        autofocus: true,
        child: AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text(widget.campaign.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              widget.campaign.message,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
          actions: [
            TextButton(
              focusNode: _maybeLaterFocusNode,
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Maybe later'),
            ),
            TextButton(
              focusNode: _dismissFocusNode,
              onPressed: () async {
                await widget.onDismissForever();
                if (mounted) {
                  Navigator.of(context).pop(false);
                }
              },
              child: const Text("Don't show again"),
            ),
            FilledButton(
              focusNode: _donateFocusNode,
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(widget.campaign.buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  static bool _didAutoUpdateCheck = false;

  // Home (the Stremio board; old index-0 Home retired) — unless a startup
  // channel is pending, in which case boot straight to IPTV (13) so the page
  // that owns the launch is the one that mounts. Resolved in main() before
  // runApp precisely so this initializer can read it; tab 13 is unconditional
  // in _computeVisibleNavIndices, so it can never be swallowed.
  int _selectedIndex = MainPageBridge.hasPendingIptvStartup
      ? MainTab.iptv
      : MainTab.home;

  // Phone nav chrome: 'classic' (bottom bar, default) vs 'floating' (the
  // glass button). Nothing renders until the pref is read — a one-frame
  // empty strip beats flashing the wrong chrome at a floating-style user.
  String _phoneNavStyle = 'classic';
  bool _phoneNavLoaded = false;

  /// TV sidebar chrome style (see TvSidebarNav.navStyle). Loaded with the
  /// nav prefs; live-reloaded when the Settings picker fires the bridge.
  /// Ghost is the product default — matching it here avoids a one-frame
  /// classic flash before the pref read lands.
  String _tvSidebarStyle = StorageService.tvSidebarStyleCached;

  /// Desktop/tablet sidebar chrome: 'rail' (fixed, the default) or 'pill'
  /// (no rail — content full-bleed, a floating capsule opens the menu).
  /// Same load/reload path as the TV style above.
  String _desktopSidebarStyle = StorageService.desktopSidebarStyleCached;

  /// Shared order and label overrides for living-room and wide-window rails.
  /// Visibility remains owned by [_computeVisibleNavIndices].
  SidebarConfiguration _sidebarConfiguration =
      StorageService.sidebarConfigurationCached;

  /// The classic bar's stored middle-slot picks (real indices; may contain
  /// currently-hidden tabs — validated against visibility at build). Null =
  /// never customized.
  List<int>? _phoneNavBarPicks;

  /// The dedicated Search tab's screen index. Named because it is the one
  /// destination whose presence depends on width rather than on which
  /// providers are configured — sidebar layouts carry it, phones don't.
  static const int _kSearchTabIndex = 17;

  /// Backfill order when picks are missing/invalid: Discover, IPTV, Cloud,
  /// Downloads, YouTube, Debrify TV, Stremio TV, Calendar, Addons, Settings.
  /// Deliberately without [_kSearchTabIndex]: the classic bar's three slots
  /// are all spoken for, and the phone reaches search from the Home board.
  static const List<int> _phoneNavDefaultOrder = [
    18,
    13,
    16,
    2,
    14,
    3,
    9,
    19,
    7,
    8,
  ];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _hasRealDebridKey = false;
  bool _hasTorboxKey = false;
  bool _rdIntegrationEnabled = true;
  bool _tbIntegrationEnabled = true;
  bool _rdHiddenFromNav = false;
  bool _tbHiddenFromNav = false;
  bool _pikpakEnabled = false;
  bool _pikpakHiddenFromNav = false;
  bool _webDavEnabled = false;
  bool _webDavHiddenFromNav = false;
  bool _premiumizeEnabled = false;
  bool _premiumizeHiddenFromNav = false;
  bool _allDebridEnabled = false;
  bool _allDebridHiddenFromNav = false;
  // Whether a Trakt account is connected — gates the Calendar tab (19).
  bool _traktAuthenticated = false;
  // Whether a Simkl account is connected — also gates the Calendar tab (19),
  // which can show either tracker's schedule via an in-page Source dropdown.
  bool _simklAuthenticated = false;
  // MDBList remains independently feature-gated; when disabled its service
  // reports unauthenticated and cannot affect existing Calendar visibility.
  bool _mdblistAuthenticated = false;
  // Seeded from the cache warmed in main() before runApp, so the very first
  // frame already builds the right layout branch — waiting for the async
  // platform check here used to flash the non-TV chrome (the old top bar) on
  // TV for a frame or two before setState flipped the flag.
  bool _isAndroidTv = PlatformUtil.isTelevision;

  /// Covers the boot while the IPTV startup channel resolves and launches.
  /// Torn down by [MainPageBridge.notifyPlayerLaunching] (which every playback
  /// path already calls) or by cancellation.
  bool _showIptvStartupOverlay = false;

  void _hideIptvStartupOverlay() {
    if (!mounted) {
      _showIptvStartupOverlay = false;
      return;
    }
    if (_showIptvStartupOverlay) {
      setState(() => _showIptvStartupOverlay = false);
    }
  }

  /// BACK / timeout during the startup launch. Cancels the attempt itself —
  /// clearing the pending payload alone would not stop work already in flight,
  /// which is why the bridge bumps an epoch and calls into the IPTV page.
  void _cancelIptvStartup() {
    MainPageBridge.cancelIptvStartupChannel();
    _hideIptvStartupOverlay();
  }

  // Back button press tracking for Android TV exit
  DateTime? _lastBackPressTime;
  static const _backPressDuration = Duration(seconds: 2);

  // TV sidebar navigation
  final GlobalKey<TvSidebarNavState> _tvSidebarKey =
      GlobalKey<TvSidebarNavState>();
  // Whether the TV sidebar overlay is expanded — drives the dim scrim over the
  // content behind it (depth, and pulls the eye to the open menu). A
  // ValueNotifier, NOT setState: the sidebar toggles this on every focus
  // enter/exit, and a MainScreen setState would rebuild the entire content
  // page (a new page widget under the same AnimatedSwitcher key → full
  // subtree rebuild of a ~3000-line screen) just to fade a scrim. The
  // notifier scopes that to the scrim's ValueListenableBuilder alone.
  final ValueNotifier<bool> _tvSidebarExpanded = ValueNotifier<bool>(false);
  // Content-side DPAD policy (see _TvContentDirectionalFocusAction). One
  // stable instance + map so rebuilds don't re-register the Actions element.
  final _TvContentDirectionalFocusAction _tvDirectionalFocusAction =
      _TvContentDirectionalFocusAction();
  late final Map<Type, Action<Intent>> _tvContentActions =
      <Type, Action<Intent>>{DirectionalFocusIntent: _tvDirectionalFocusAction};
  bool _tvFocusRecoveryInstalled = false;

  // Remote control state
  bool _remoteControlEnabled = true;
  UserProfile? _profilePolicy;
  StreamSubscription<Map<String, dynamic>>? _autoUpdateDownloadSub;
  String? _autoUpdateDownloadTaskId;
  bool _hasTrackedInitialTab = false;
  bool _didCheckSupportCampaign = false;
  bool _startupModalActive = false;
  bool _supportCampaignResolved = false;
  bool _autoUpdateCheckResolved = false;

  /// True while a Cloud-hub provider route is on the stack, so a rapid re-tap or
  /// a duplicate deep link doesn't stack a second identical provider route.
  bool _cloudProviderRouteOpen = false;

  final List<Widget> _pages = [
    const SizedBox.shrink(), // 0: (deprecated old Home — kept as an inert slot
    // so every later tab index stays stable; removed from the visible nav below
    // and never selected. The new Stremio board at index 15 is now "Home".)
    const PlaylistScreen(), // 1: Playlist
    const DownloadsScreen(), // 2: Downloads
    const DebrifyTVScreen(), // 3: Debrify TV
    const DebridDownloadsScreen(), // 4: Real Debrid
    const TorboxDownloadsScreen(), // 5: Torbox
    const PikPakFilesScreen(), // 6: PikPak
    const AddonsScreen(), // 7: Addons
    const SettingsScreen(), // 8: Settings
    // 9: Stremio TV — overridden in _buildPage so it gets the resolved TV flag;
    // this const entry is only an index-stable fallback (defaults to phone).
    const StremioTvScreen(),
    const WebDavFilesScreen(), // 10: WebDAV
    const PremiumizeFilesScreen(), // 11: Premiumize
    const AllDebridFilesScreen(), // 12: AllDebrid
    // 13: IPTV and 14: YouTube are built on demand by _buildPage (they need the
    // resolved TV flag passed in), so they have no entry in this const list.
  ];

  final List<String> _titles = [
    'Home (deprecated)', // 0: old board, hidden from nav (index kept as a slot)
    'Playlist',
    'Downloads',
    'Debrify TV',
    'Real Debrid',
    'Torbox',
    'PikPak',
    'Addons',
    'Settings',
    'Stremio TV',
    'WebDAV',
    'Premiumize',
    'AllDebrid',
    'IPTV',
    'YouTube',
    'Home', // 15: the Stremio-style board — now THE Home (old index-0 Home is
    // deprecated). Built on demand in _buildPage as SearchScreen().
    'Cloud', // 16: consolidated cloud-provider hub (RD/Torbox/PikPak/…/WebDAV)
    'Search', // 17: dedicated search tab (TV + sidebar layouts)
    'Discover', // 18: source-dropdown browser (Continue Watching / Trakt / …)
    'Calendar', // 19: Trakt/Simkl calendar (visible when either is connected)
  ];

  final List<IconData> _icons = [
    Icons.home_rounded,
    Icons.playlist_play_rounded,
    Icons.download_for_offline_rounded,
    Icons.tv_rounded,
    Icons.cloud_download_rounded,
    Icons.flash_on_rounded,
    Icons.cloud_circle_rounded,
    Icons.extension_rounded,
    Icons.settings_rounded,
    Icons.smart_display_rounded,
    Icons.cloud_sync_rounded,
    Icons.workspace_premium_rounded,
    Icons.all_inclusive_rounded,
    Icons.live_tv_rounded,
    Icons.ondemand_video_rounded,
    Icons.home_rounded, // 15: Home New (board)
    Icons.cloud_rounded, // 16: Cloud
    Icons.search_rounded, // 17: Search
    Icons.explore_rounded, // 18: Discover
    Icons.calendar_month_rounded, // 19: Calendar (Trakt/Simkl)
  ];

  /// Tab index → bridge back-handler key, in ONE place. Every path that
  /// assigns [_selectedIndex] must publish through this — cold start lands
  /// directly on Home (15) via the field initializer without ever passing
  /// through [_onItemTapped], and Back on the very first screen would
  /// otherwise bypass the tab's handler entirely.
  static String? _tabKeyFor(int index) {
    switch (index) {
      case 4:
        return 'realdebrid';
      case 5:
        return 'torbox';
      case 6:
        return 'pikpak';
      case 8:
        return 'settings';
      case 10:
        return 'webdav';
      case 11:
        return 'premiumize';
      case 12:
        return 'alldebrid';
      case 15:
        // Off-TV Home: its handler closes the Spotlight search sheet on Back
        // before the root fallback may arm double-back-exit.
        return 'home';
      case 17:
        // Dedicated Search tab: its handler clears an active query on Back
        // (returning to the blank prompt) before letting Back leave the tab.
        return 'search';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfilePolicy());
    // Active-surface signal: the initializer above picked the boot tab before
    // any tap could, so system-bar ownership needs it published explicitly.
    AppSurfaceState.instance.publishTab(_selectedIndex);
    // Same rule for the bridge's back routing: the boot tab was chosen by the
    // field initializer, not a tap.
    MainPageBridge.setActiveTab(_tabKeyFor(_selectedIndex));
    // Startup channel: show the cover immediately so the user never sees the
    // IPTV page assembling itself underneath, and publish the splash hand-off
    // signal — AppInitializer waits on homeBoardReady, which only the Home
    // board sets, so booting to tab 13 would otherwise stall on its 10s valve.
    // The startup channel resolved before any profile was chosen — the
    // signed-in profile may not be allowed IPTV at all. Cancel BEFORE the
    // IPTV page can mount and start tuning; the guard mirror is valid here
    // because the gate updates it before revealing this tree.
    if (MainPageBridge.hasPendingIptvStartup &&
        !ProfilePolicyGuard.allowsSync(ProfileFeature.iptv)) {
      MainPageBridge.cancelIptvStartupChannel();
      _selectedIndex = MainTab.home;
    }
    if (MainPageBridge.hasPendingIptvStartup) {
      _showIptvStartupOverlay = true;
      MainPageBridge.hideAutoLaunchOverlay = _hideIptvStartupOverlay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MainPageBridge.homeBoardReady.value = true;
      });
    }
    unawaited(_loadPhoneNavPrefs());
    MainPageBridge.tvSidebarStyleChanged = () {
      if (mounted) unawaited(_loadPhoneNavPrefs());
    };
    MainPageBridge.desktopSidebarStyleChanged = () {
      if (mounted) unawaited(_loadPhoneNavPrefs());
    };
    MainPageBridge.sidebarConfigurationChanged = () {
      if (mounted) unawaited(_loadPhoneNavPrefs());
    };
    MainPageBridge.navPrefsChanged = () {
      if (mounted) unawaited(_loadPhoneNavPrefs());
    };
    MainPageBridge.reloadProfilePolicy = () {
      if (mounted) unawaited(_loadProfilePolicy());
    };
    // Expose tab switcher for deep-link flows
    MainPageBridge.switchTab = (int index) {
      if (!mounted) return;
      final visibleIndices = _computeVisibleNavIndices();
      if (!visibleIndices.contains(index)) {
        if (index == MainTab.realDebrid) {
          _showMissingApiKeySnack('Real Debrid');
        } else if (index == MainTab.torbox) {
          _showMissingApiKeySnack('Torbox');
        } else if (index == MainTab.pikPak) {
          // PikPak tab - check if enabled but hidden vs not configured
          if (_pikpakEnabled && _pikpakHiddenFromNav) {
            _showTabHiddenSnack('PikPak');
          } else {
            _showMissingApiKeySnack('PikPak');
          }
        } else if (index == MainTab.webDav) {
          if (_webDavEnabled && _webDavHiddenFromNav) {
            _showTabHiddenSnack('WebDAV');
          } else {
            _showMissingApiKeySnack('WebDAV');
          }
        } else if (index == MainTab.premiumize) {
          if (_premiumizeEnabled && _premiumizeHiddenFromNav) {
            _showTabHiddenSnack('Premiumize');
          } else {
            _showMissingApiKeySnack('Premiumize');
          }
        } else if (index == MainTab.allDebrid) {
          if (_allDebridEnabled && _allDebridHiddenFromNav) {
            _showTabHiddenSnack('AllDebrid');
          } else {
            _showMissingApiKeySnack('AllDebrid');
          }
        } else {
          _showIntegrationRequiredSnack();
        }
        return;
      }
      _onItemTapped(index);
    };
    MainPageBridge.openDebridOptions = (RDTorrent torrent) {
      if (!mounted) return;
      if (!_hasRealDebridKey) {
        _showMissingApiKeySnack('Real Debrid');
        return;
      }
      // Always push as a new route - provides consistent UX where back returns to torrent search
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (!MainPageBridge.handleBackNavigation()) {
                Navigator.of(ctx).pop();
              }
            },
            child: DebridDownloadsScreen(
              initialTorrentForOptions: torrent,
              isPushedRoute: true,
            ),
          ),
        ),
      );
    };
    MainPageBridge.openTorboxFolder = (torboxTorrent) {
      if (!mounted) return;
      if (!_hasTorboxKey) {
        _showMissingApiKeySnack('Torbox');
        return;
      }
      // Always push as a new route - provides consistent UX where back returns to torrent search
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (!MainPageBridge.handleBackNavigation()) {
                Navigator.of(ctx).pop();
              }
            },
            child: TorboxDownloadsScreen(
              initialTorrentToOpen: torboxTorrent,
              isPushedRoute: true,
            ),
          ),
        ),
      );
    };
    MainPageBridge.openPikPakFolder = (fileId, folderName) {
      if (!mounted) return;
      if (!_pikpakEnabled) {
        _showMissingApiKeySnack('PikPak');
        return;
      }
      // Always push as a new route - provides consistent UX where back returns to torrent search
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (!MainPageBridge.handleBackNavigation()) {
                Navigator.of(ctx).pop();
              }
            },
            child: PikPakFilesScreen(
              initialFolderId: fileId,
              initialFolderName: folderName,
              isPushedRoute: true,
            ),
          ),
        ),
      );
    };
    MainPageBridge.openPremiumizeFolder = () {
      if (!mounted) return;
      if (!_premiumizeEnabled) {
        _showMissingApiKeySnack('Premiumize');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (!MainPageBridge.handleBackNavigation()) {
                Navigator.of(ctx).pop();
              }
            },
            child: const PremiumizeFilesScreen(isPushedRoute: true),
          ),
        ),
      );
    };
    MainPageBridge.openAllDebridFolder = () {
      if (!mounted) return;
      if (!_allDebridEnabled) {
        _showMissingApiKeySnack('AllDebrid');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              if (!MainPageBridge.handleBackNavigation()) {
                Navigator.of(ctx).pop();
              }
            },
            child: const AllDebridFilesScreen(isPushedRoute: true),
          ),
        ),
      );
    };
    MainPageBridge.openCloudProvider = _openCloudProvider;
    MainPageBridge.addIntegrationListener(_handleIntegrationChanged);
    _loadIntegrationState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();

    AndroidNativeDownloader.isTelevision().then((isTvProbe) async {
      if (!mounted) return;

      // The probe is an ANDROID method channel: on Apple TV there is no such
      // channel, so it answers false and would drop a living-room device into
      // the phone/desktop shell — and skip the block below, leaving the sidebar
      // with no focus callbacks, so LEFT does nothing. [PlatformUtil] already
      // knows the platform-level answer; this probe can only ever ADD Android
      // TV to it, never take a television away.
      final isTv = isTvProbe || PlatformUtil.isTelevision;

      setState(() {
        _isAndroidTv = isTv;
      });

      // Set up TV sidebar focus callback
      if (isTv) {
        MainPageBridge.focusTvSidebar = () {
          _tvSidebarKey.currentState?.requestFocus();
        };
        MainPageBridge.isTvSidebarFocused = () =>
            _tvSidebarKey.currentState?.hasFocus ?? false;
        MainPageBridge.tvDirectionalLeft = _tvDirectionalFocusAction.handleLeft;
        // The sidebar's nodes skip traversal, so if focus ever dies (a tab
        // with nothing focusable, or the focused widget got disposed and the
        // scope has no traversable descendants left) no DPAD press could
        // recover it — previously a stray arrow landed on the rail. Restore
        // that last-resort recovery explicitly.
        if (!_tvFocusRecoveryInstalled) {
          _tvFocusRecoveryInstalled = true;
          HardwareKeyboard.instance.addHandler(_tvDeadFocusRecovery);
        }
      }

      if (!_hasTrackedInitialTab) {
        _trackCurrentTab();
        _hasTrackedInitialTab = true;
      }

      // Initialize remote control based on device type
      _initializeRemoteControl(isTv);
    });

    // Initialize deep link service for magnet links
    _initializeDeepLinking();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoCheckForUpdates();
    });

    _scheduleSupportCampaignPrompt();
  }

  Future<void> _loadProfilePolicy() async {
    if (!ProfileRuntime.isProfileCommitted) return;
    final scope = ProfileRuntime.capture();
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (!mounted || ProfileRuntime.capture() != scope) return;
    ProfilePolicyGuard.updateActiveProfile(profile);
    setState(() {
      _profilePolicy = profile;
      final visible = _computeVisibleNavIndices();
      if (!visible.contains(_selectedIndex)) {
        _selectedIndex = visible.contains(MainTab.home)
            ? MainTab.home
            : visible.first;
      }
    });
  }

  bool _allowsProfileFeature(ProfileFeature feature) {
    if (!ProfileRuntime.isProfileCommitted) return true;
    final profile = _profilePolicy;
    return profile != null && profile.allows(feature);
  }

  Future<void> _openProfilesFromNavigation() async {
    if (!ProfileRuntime.isProfileCommitted || _profilePolicy == null) return;
    await pushSettingsPage(context, const ProfilesSettingsPage());
    if (!mounted || !ProfileRuntime.isProfileCommitted) return;
    await _loadProfilePolicy();
    if (!mounted) return;
    if (_isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) MainPageBridge.requestTvContentFocus();
      });
    }
  }

  List<int> _applyProfilePolicy(List<int> indices) {
    if (!ProfileRuntime.isProfileCommitted) return indices;
    return indices
        .where((index) {
          final feature = switch (index) {
            MainTab.downloads => ProfileFeature.downloads,
            MainTab.debrifyTv => ProfileFeature.debrifyTv,
            // File-browsing tabs follow the SURFACE feature; provider
            // operations stay on ProfileFeature.cloud (see the enum docs).
            MainTab.realDebrid ||
            MainTab.torbox ||
            MainTab.pikPak ||
            MainTab.webDav ||
            MainTab.premiumize ||
            MainTab.allDebrid ||
            MainTab.cloud => ProfileFeature.cloudFiles,
            MainTab.addons => ProfileFeature.addonsAndEngines,
            MainTab.stremioTv => ProfileFeature.stremioTv,
            MainTab.iptv => ProfileFeature.iptv,
            MainTab.youtube => ProfileFeature.youtube,
            MainTab.discover ||
            MainTab.calendar => ProfileFeature.trackersAndDiscovery,
            _ => null,
          };
          return feature == null || _allowsProfileFeature(feature);
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    MainPageBridge.switchTab = null;
    MainPageBridge.navPrefsChanged = null;
    MainPageBridge.reloadProfilePolicy = null;
    MainPageBridge.tvSidebarStyleChanged = null;
    MainPageBridge.desktopSidebarStyleChanged = null;
    MainPageBridge.sidebarConfigurationChanged = null;
    MainPageBridge.openDebridOptions = null;
    MainPageBridge.openTorboxFolder = null;
    MainPageBridge.openPikPakFolder = null;
    MainPageBridge.openPremiumizeFolder = null;
    MainPageBridge.openAllDebridFolder = null;
    MainPageBridge.openCloudProvider = null;
    MainPageBridge.focusTvSidebar = null;
    MainPageBridge.isTvSidebarFocused = null;
    MainPageBridge.tvDirectionalLeft = null;
    MainPageBridge.hideAutoLaunchOverlay = null;
    if (_tvFocusRecoveryInstalled) {
      HardwareKeyboard.instance.removeHandler(_tvDeadFocusRecovery);
    }
    _animationController.dispose();
    _tvSidebarExpanded.dispose();
    DeepLinkService().dispose();
    RemoteControlState().stop();
    _autoUpdateDownloadSub?.cancel();
    super.dispose();
  }

  /// TV last-resort DPAD recovery: only when NOTHING real holds focus (primary
  /// focus fell back to a bare scope) AND that scope has no traversable
  /// descendants for stock traversal to recover into — i.e. the remote would
  /// otherwise be completely dead — an arrow press focuses the sidebar. Never
  /// fires while a widget has focus, while stock traversal has any candidate,
  /// while the sidebar already has focus, or while another route (dialog,
  /// player, pushed screen) covers MainPage.
  bool _tvDeadFocusRecovery(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!_isAndroidTv) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary is! FocusScopeNode) return false;
    if (primary.traversalDescendants.isNotEmpty) return false;
    final sidebar = _tvSidebarKey.currentState;
    if (sidebar == null || sidebar.hasFocus) return false;
    final ctx = _tvSidebarKey.currentContext;
    if (ctx == null || !(ModalRoute.of(ctx)?.isCurrent ?? false)) return false;
    // LEFT keeps the house rule — it's the ONE key that opens the rail, so a
    // dead-focus LEFT still lands there (and stays the escape hatch on a tab
    // with genuinely nothing focusable).
    if (key == LogicalKeyboardKey.arrowLeft) {
      sidebar.requestFocus();
      return true;
    }
    // Every other arrow prefers re-entering the active tab's content:
    // focusing the rail EXPANDS it, so recovering there reads as "the sidebar
    // opened by itself" — and every later auto-focus pass then declines to
    // steal focus back off it. A tab's handler places focus on its entry
    // element, or deliberately no-ops while the tab is still loading (nothing
    // focusable yet); either way the arrow is spent and the tab's own arrival
    // auto-focus lands once content exists. The rail stays the last resort
    // for tabs that never registered a handler.
    if (MainPageBridge.requestTvContentFocus()) return true;
    sidebar.requestFocus();
    return true;
  }

  /// Initialize remote control based on device type
  Future<void> _initializeRemoteControl(bool isTv) async {
    if (!_allowsProfileFeature(ProfileFeature.remoteControl)) return;
    // Check if remote control is enabled
    _remoteControlEnabled = await StorageService.getRemoteControlEnabled();
    if (!_remoteControlEnabled) return;

    if (isTv) {
      // TV: Start listening for mobile devices.
      // Command dispatch into the router is wired automatically by
      // RemoteControlState.startTvListener so phones/desktops that switch
      // to receive mode mid-session via the Remote picker also work.
      // Priority: 1. User-set custom name, 2. Actual device name, 3. Fallback
      var deviceName = await StorageService.getRemoteTvDeviceName();
      deviceName ??= await PlatformUtil.getDeviceName();
      deviceName ??= 'Debrify TV';
      await RemoteControlState().startTvListener(deviceName);
    } else {
      // Non-TV: Start scanning for TVs
      await RemoteControlState().startMobileDiscovery();
    }
  }

  /// Initialize deep linking for magnet links and shared URLs
  void _initializeDeepLinking() {
    final deepLinkService = DeepLinkService();

    // Set the callback for handling magnet links
    deepLinkService.onMagnetLinkReceived = (magnetUri) async {
      if (!mounted) return;
      if (!_allowsProfileFeature(ProfileFeature.incomingLinks) ||
          !_allowsProfileFeature(ProfileFeature.torrentSearch)) {
        _showPolicyDeniedSnack();
        return;
      }

      // Create handler with callbacks
      final handler = MagnetLinkHandler(
        context: context,
        onRealDebridResult: (result, torrentName, apiKey) async {
          // Use the same post-action flow as torrent search
          await MainPageBridge.handleRealDebridResult?.call(
            result,
            torrentName,
            apiKey,
          );
        },
        onRealDebridAdded: (torrent) {
          // Fallback: Open RealDebrid tab with the added torrent
          MainPageBridge.openDebridOptions?.call(torrent);
        },
        onTorboxResult: (torrent) async {
          // Use the same post-action flow as torrent search
          await MainPageBridge.handleTorboxResult?.call(torrent);
        },
        onTorboxAdded: (torrent) {
          // Fallback: open Torbox in the Cloud hub
          MainPageBridge.openCloudProvider?.call('torbox');
        },
        onPikPakResult: (fileId, fileName) async {
          // Use the same post-action flow as torrent search
          if (MainPageBridge.handlePikPakResult != null) {
            await MainPageBridge.handlePikPakResult!(fileId, fileName);
          } else {
            // Bridge not set (TorrentSearchScreen not mounted), handle inline
            await _handlePikPakPostActionFallback(context, fileId, fileName);
          }
        },
        onPikPakAdded: () {
          // Fallback: open PikPak in the Cloud hub
          MainPageBridge.openCloudProvider?.call('pikpak');
        },
        onPremiumizeAdded: () {
          MainPageBridge.openCloudProvider?.call('premiumize');
        },
        onAllDebridAdded: () {
          MainPageBridge.openCloudProvider?.call('alldebrid');
        },
      );

      // Handle the magnet link
      await handler.handleMagnetLink(magnetUri);
    };

    // Set the callback for handling shared URLs
    deepLinkService.onUrlShared = (url) async {
      if (!mounted) return;
      if (!_allowsProfileFeature(ProfileFeature.incomingLinks) ||
          !_allowsProfileFeature(ProfileFeature.cloud)) {
        _showPolicyDeniedSnack();
        return;
      }

      // Create handler with callbacks for URL handling
      final handler = MagnetLinkHandler(
        context: context,
        onRealDebridUrlResult: (result) {
          // Show success message with download info
          final filename = result['filename']?.toString() ?? 'Link';
          final filesize = result['filesize'] as int?;
          String message = 'Added to RealDebrid: $filename';
          if (filesize != null && filesize > 0) {
            final sizeMB = (filesize / (1024 * 1024)).toStringAsFixed(1);
            message += ' ($sizeMB MB)';
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
        onTorboxUrlResult: (webDownloadId, name) {
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added to Torbox: $name'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
        onPikPakResult: (fileId, fileName) async {
          // Use the same post-action flow as torrent search
          if (MainPageBridge.handlePikPakResult != null) {
            await MainPageBridge.handlePikPakResult!(fileId, fileName);
          } else {
            await _handlePikPakPostActionFallback(context, fileId, fileName);
          }
        },
        onPikPakAdded: () {
          MainPageBridge.openCloudProvider?.call('pikpak');
        },
        onPremiumizeAdded: () {
          MainPageBridge.openCloudProvider?.call('premiumize');
        },
        onAllDebridAdded: () {
          MainPageBridge.openCloudProvider?.call('alldebrid');
        },
        onAllDebridUrlResult: () {
          // Shared web link was saved → open AllDebrid on its Web Downloads
          // view and refresh so the new link is visible. notify() before
          // opening so the freshly-built screen picks up the pending flag.
          MainPageBridge.notifyAllDebridFocusWebDownloads();
          MainPageBridge.openCloudProvider?.call('alldebrid');
        },
      );

      // Handle the shared URL
      await handler.handleSharedUrl(url);
    };

    // Set the callback for handling Stremio addon URLs
    deepLinkService.onStremioAddonReceived = (manifestUrl) async {
      if (!mounted) return;
      if (!_allowsProfileFeature(ProfileFeature.incomingLinks) ||
          !_allowsProfileFeature(ProfileFeature.addonsAndEngines)) {
        _showPolicyDeniedSnack();
        return;
      }

      // Show dialog to choose where to install (phone or TV)
      final choice = await AddonInstallDialog.show(context, manifestUrl);

      if (choice == null || !mounted) return; // User cancelled

      if (choice.target == 'tv' && choice.device != null) {
        // Addon URLs can embed debrid keys — same encrypted-session +
        // pairing gate as the settings transfer flows.
        final session = await ensureAuthorizedSession(
          context,
          RemoteControlState(),
          choice.device!,
        );
        if (session == null || !mounted) return;
        final success = await RemoteControlState().sendAddonCommandToDevice(
          AddonCommand.install,
          choice.device!.ip,
          manifestUrl: manifestUrl,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Addon sent to ${choice.device!.deviceName}'
                  : 'Failed to send addon to TV',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Install on this device
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Installing addon...'),
            ],
          ),
          duration: Duration(seconds: 10),
        ),
      );

      try {
        // Add the addon using StremioService
        final addon = await StremioService.instance.addAddon(manifestUrl);

        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Addon installed: ${addon.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to install addon: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    };

    // Initialize the service
    deepLinkService.initialize();
  }

  void _maybeAutoCheckForUpdates() {
    if (_didAutoUpdateCheck) return;
    _didAutoUpdateCheck = true;
    Future<void>.delayed(const Duration(seconds: 6), () async {
      if (!mounted) return;
      await _runDeferredAutoUpdateCheck();
    });
  }

  void _scheduleSupportCampaignPrompt() {
    if (_didCheckSupportCampaign) return;
    _didCheckSupportCampaign = true;

    Future<void>.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;
      await _runDeferredSupportCampaignPrompt();
    });
  }

  Future<void> _runDeferredSupportCampaignPrompt() async {
    if (!mounted || _supportCampaignResolved) return;
    if (_startupModalActive) {
      Future<void>.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;
        await _runDeferredSupportCampaignPrompt();
      });
      return;
    }

    final completed = await _maybeShowSupportCampaignDialog();
    if (completed) {
      _supportCampaignResolved = true;
      return;
    }

    if (!mounted || _supportCampaignResolved) return;
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _runDeferredSupportCampaignPrompt();
    });
  }

  Future<void> _runDeferredAutoUpdateCheck() async {
    if (!mounted || _autoUpdateCheckResolved) return;
    if (_startupModalActive) {
      Future<void>.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;
        await _runDeferredAutoUpdateCheck();
      });
      return;
    }

    final completed = await _performAutoUpdateCheck();
    if (completed) {
      _autoUpdateCheckResolved = true;
      return;
    }

    if (!mounted || _autoUpdateCheckResolved) return;
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await _runDeferredAutoUpdateCheck();
    });
  }

  Future<bool> _maybeShowSupportCampaignDialog() async {
    final config = await SupportRemoteConfigService.instance.loadConfig();
    final campaign = config.campaign;
    final donation = config.donation;
    if (_startupModalActive) return false;
    if (!campaign.isActiveAt(
      DateTime.now().toUtc(),
      providers: donation.providers,
    )) {
      return true;
    }

    final dismissedIds = await StorageService.getDismissedDonationCampaignIds();
    if (dismissedIds.contains(campaign.id)) return true;
    if (!mounted) return false;

    _startupModalActive = true;
    try {
      final shouldOpenChooser = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _SupportCampaignDialog(
          campaign: campaign,
          onDismissForever: () async {
            await StorageService.dismissDonationCampaign(campaign.id);
          },
        ),
      );

      if (shouldOpenChooser == true && mounted) {
        await showSupportDonationChooserDialog(
          context,
          donation: donation,
          title: donation.settingsLabel,
        );
      }
      return true;
    } finally {
      _startupModalActive = false;
    }
  }

  Future<bool> _performAutoUpdateCheck() async {
    try {
      if (!_allowsProfileFeature(ProfileFeature.appUpdates)) return true;
      final autoEnabled = await StorageService.getUpdateAutoCheckEnabled();
      if (!autoEnabled) return true;
      final packageInfo = await AppVersionInfo.get();
      UpdateSummary summary;
      try {
        summary = await UpdateService.checkForUpdates(
          currentVersion: packageInfo.version,
        );
      } catch (_) {
        return true;
      }
      if (!summary.updateAvailable) return true;
      final ignored = await StorageService.getIgnoredUpdateVersion();
      final releaseVersion = summary.release.versionLabel;
      if (ignored != null &&
          releaseVersion.isNotEmpty &&
          ignored == releaseVersion) {
        return true;
      }
      if (!mounted) return false;
      if (_startupModalActive) {
        Future<void>.delayed(const Duration(seconds: 3), () async {
          if (!mounted) return;
          await _runDeferredAutoUpdateCheck();
        });
        return false;
      }
      _startupModalActive = true;
      try {
        await _showAutoUpdateDialog(summary, packageInfo.version);
        return true;
      } finally {
        _startupModalActive = false;
      }
    } catch (_) {
      _startupModalActive = false;
      // Ignore auto-update failures silently
      return true;
    }
  }

  Future<void> _showAutoUpdateDialog(
    UpdateSummary summary,
    String installedVersion,
  ) async {
    if (!mounted) return;
    final release = summary.release;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final notes = release.body.trim();
    final bool isAndroidDevice = !kIsWeb && Platform.isAndroid;
    final bool canInstallDirectly =
        summary.updateAvailable &&
        isAndroidDevice &&
        release.androidApkAsset != null;
    final String latestLabel = release.versionLabel.isNotEmpty
        ? release.versionLabel
        : 'Latest release';
    final String? publishedLabel = release.publishedAt != null
        ? DateFormat.yMMMd().format(release.publishedAt!.toLocal())
        : null;
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      h2: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      p: textTheme.bodyMedium?.copyWith(height: 1.4),
      strong: const TextStyle(fontWeight: FontWeight.w700),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return FocusTraversalGroup(
          child: AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            title: const Text('Update available'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Installed: $installedVersion',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Latest: $latestLabel',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  if (publishedLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Published $publishedLabel',
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Release notes',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: MarkdownBody(
                          data: notes,
                          selectable: true,
                          styleSheet: markdownStyle,
                          onTapLink: (text, href, title) {
                            if (href == null) return;
                            final uri = Uri.tryParse(href);
                            if (uri != null) {
                              launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: 460,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    TextButton(
                      onPressed: () async {
                        final navigator = Navigator.of(dialogContext);
                        await StorageService.setIgnoredUpdateVersion(
                          release.versionLabel,
                        );
                        navigator.pop();
                      },
                      child: const Text('Skip this release'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Later'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        if (canInstallDirectly) {
                          _startAutoUpdateDownload(release);
                        } else {
                          _openReleasesPage(release.htmlUrl);
                        }
                      },
                      child: Text(
                        canInstallDirectly ? 'Install update' : 'View release',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startAutoUpdateDownload(AppRelease release) async {
    if (kIsWeb || !Platform.isAndroid) {
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    if (_autoUpdateDownloadTaskId != null) {
      _showAutoUpdateSnack('An update download is already running.');
      return;
    }
    final asset = release.androidApkAsset;
    if (asset == null) {
      _showAutoUpdateSnack(
        'This release does not include an Android build yet.',
      );
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    final hasPermission = await _ensureInstallPermissionForUpdate();
    if (!hasPermission) return;

    const mime = 'application/vnd.android.package-archive';
    String? taskId;
    try {
      taskId = await AndroidNativeDownloader.startUpdate(
        url: asset.downloadUrl.toString(),
        fileName: asset.name.isNotEmpty
            ? asset.name
            : 'Debrify-${release.versionLabel}.apk',
        subDir: 'Debrify/Updates',
        mimeType: mime,
      );
    } catch (_) {
      taskId = null;
    }

    if (taskId == null) {
      _showAutoUpdateSnack(
        'Could not start the update download. Please try again later.',
      );
      return;
    }

    _autoUpdateDownloadTaskId = taskId;
    _autoUpdateDownloadSub?.cancel();
    _autoUpdateDownloadSub = AndroidNativeDownloader.events.listen((
      event,
    ) async {
      final String eventTaskId = (event['taskId'] ?? '').toString();
      if (eventTaskId != _autoUpdateDownloadTaskId) return;
      final type = event['type']?.toString();
      if (type == 'complete') {
        final contentUri = (event['contentUri'] ?? '').toString();
        final eventMime = (event['mimeType'] ?? '').toString().isNotEmpty
            ? (event['mimeType'] ?? '').toString()
            : mime;
        try {
          if (contentUri.isNotEmpty) {
            final ok = await AndroidNativeDownloader.openContentUri(
              contentUri,
              eventMime,
            );
            if (!ok) {
              _showAutoUpdateSnack('Installer opened from Downloads.');
            }
          }
        } catch (_) {
          _showAutoUpdateSnack(
            'Could not open the installer. Check your Downloads app.',
          );
        } finally {
          _clearAutoUpdateDownloadState();
          _showAutoUpdateSnack('Update downloaded and ready to install.');
        }
      } else if (type == 'error' || type == 'canceled') {
        _showAutoUpdateSnack('Update download did not finish.');
        _clearAutoUpdateDownloadState();
      }
    });

    _showAutoUpdateSnack(
      'Downloading the update in the background. Watch notifications for progress.',
    );
  }

  void _clearAutoUpdateDownloadState() {
    _autoUpdateDownloadSub?.cancel();
    _autoUpdateDownloadSub = null;
    _autoUpdateDownloadTaskId = null;
  }

  Future<bool> _ensureInstallPermissionForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied || result.isRestricted) {
      _showAutoUpdateSnack(
        'Allow Debrify to install apps from system settings.',
      );
      unawaited(openAppSettings());
    } else {
      _showAutoUpdateSnack(
        'Permission is required to install the downloaded update.',
      );
    }
    return false;
  }

  Future<void> _openReleasesPage(Uri url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showAutoUpdateSnack('Unable to open the releases page right now.');
    }
  }

  void _showAutoUpdateSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fallback handler for PikPak post-action when TorrentSearchScreen is not mounted
  Future<void> _handlePikPakPostActionFallback(
    BuildContext ctx,
    String fileId,
    String fileName,
  ) async {
    final postAction = await StorageService.getPikPakPostTorrentAction();
    final pikpakHidden = await StorageService.getPikPakHiddenFromNav();

    // For 'none' action, just show success
    if (postAction == 'none') {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text('Torrent added to PikPak successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    // For 'open' action, open PikPak folder directly
    if (postAction == 'open') {
      if (!pikpakHidden) {
        MainPageBridge.openPikPakFolder?.call(fileId, fileName);
      }
      return;
    }

    // For 'choose' or other actions, show a simple dialog with available options
    if (!ctx.mounted) return;

    await showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Added to PikPak',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            const Text(
              'What would you like to do?',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          if (!pikpakHidden)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                MainPageBridge.openPikPakFolder?.call(fileId, fileName);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFAA00),
              ),
              child: const Text(
                'Open in PikPak',
                style: TextStyle(color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadPhoneNavPrefs() async {
    final style = await StorageService.getPhoneNavStyle();
    final picks = await StorageService.getPhoneNavBarIndices();
    final tvSidebar = await StorageService.getTvSidebarStyle();
    final desktopSidebar = await StorageService.getDesktopSidebarStyle();
    final sidebarConfiguration = await StorageService.getSidebarConfiguration();
    if (!mounted) return;
    MainPageBridge.phoneNavStyleCached = style;
    setState(() {
      _phoneNavStyle = style;
      _phoneNavBarPicks = picks;
      _tvSidebarStyle = tvSidebar;
      _desktopSidebarStyle = desktopSidebar;
      _sidebarConfiguration = sidebarConfiguration;
      _phoneNavLoaded = true;
    });
  }

  /// The classic bar's effective middle slots. The stored pick COUNT is the
  /// user's choice and is respected (someone who wants a two-slot bar keeps
  /// a two-slot bar); slots lost to GATING (debrid removed, Trakt
  /// disconnected) heal from the defaults so the bar never shows a hole.
  /// Never customized = a full three from the defaults.
  List<int> _phoneNavEffectiveBar(List<int> visible) {
    final stored = _phoneNavBarPicks;
    final target = stored == null ? 3 : stored.length.clamp(0, 3);
    final slots = <int>[];
    for (final index in stored ?? const <int>[]) {
      if (slots.length >= target) break;
      if (!visible.contains(index)) continue;
      if (index == MobileClassicNav.homeIndex) continue;
      if (slots.contains(index)) continue;
      slots.add(index);
    }
    for (final index in _phoneNavDefaultOrder) {
      if (slots.length >= target) break;
      if (index == MobileClassicNav.homeIndex) continue;
      if (!visible.contains(index) || slots.contains(index)) continue;
      slots.add(index);
    }
    for (final index in visible) {
      if (slots.length >= target) break;
      if (index == MobileClassicNav.homeIndex) continue;
      if (slots.contains(index)) continue;
      slots.add(index);
    }
    return slots;
  }

  void _onItemTapped(int index) {
    final visible = _computeVisibleNavIndices();
    if (!visible.contains(index)) {
      return;
    }
    final changed = _selectedIndex != index;
    // A tab switch invalidates a pending "press back again to exit" arm —
    // otherwise tap-tap-back inside the 2s window could exit on what the
    // user experienced as a single back press.
    if (changed) _lastBackPressTime = null;
    setState(() {
      _selectedIndex = index;
    });
    AppSurfaceState.instance.publishTab(index);
    _animationController.reset();
    _animationController.forward();

    // Notify MainPageBridge which tab is now active for back navigation
    MainPageBridge.setActiveTab(_tabKeyFor(index));

    // Update active tab for TV sidebar navigation
    MainPageBridge.setActiveTvTab(index);

    if (changed) {
      _hasTrackedInitialTab = true;
      _trackCurrentTab();
    }
  }

  void _trackCurrentTab() {
    final title = _titles[_selectedIndex];
    AnalyticsService.trackInBackground('tab_opened', <String, Object?>{
      'tab': title,
      'tab_index': _selectedIndex,
      'platform': AnalyticsService.currentPlatformLabel(),
      'tv_mode': _isAndroidTv,
    });
  }

  void _handleIntegrationChanged() {
    _loadIntegrationState();
  }

  Future<void> _loadIntegrationState() async {
    final startingScope = ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    try {
      await _loadIntegrationStateForCurrentProfile();
    } on ResourceAuthorizationException {
      // Opening the picker unmounts this shell and revokes its in-flight
      // credential reads. That is expected cancellation, not an app error.
      if (!mounted ||
          ProfileLockController.instance.lockedProfileId.value != null ||
          (startingScope != null &&
              ProfileRuntime.scope.value != startingScope)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _loadIntegrationStateForCurrentProfile() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();
    final rdHidden = await StorageService.getRealDebridHiddenFromNav();
    final tbHidden = await StorageService.getTorboxHiddenFromNav();
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    final pikpakHidden = await StorageService.getPikPakHiddenFromNav();
    final webDavEnabled = await StorageService.getWebDavEnabled();
    final webDavServers = await StorageService.getWebDavServers();
    final webDavHidden = await StorageService.getWebDavHiddenFromNav();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final premiumizeEnabledPref =
        await StorageService.getPremiumizeIntegrationEnabled();
    final premiumizeHidden = await StorageService.getPremiumizeHiddenFromNav();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final allDebridEnabledPref =
        await StorageService.getAllDebridIntegrationEnabled();
    final allDebridHidden = await StorageService.getAllDebridHiddenFromNav();
    // Trakt/Simkl connection gates the Calendar tab. Login/logout of either
    // fires notifyIntegrationChanged(), so this re-reads on those events too.
    final traktAuthed = await TraktService.instance.isAuthenticated();
    final simklAuthed = await SimklService.instance.isAuthenticated();
    final mdblistAuthed = await MdblistService.instance.isAuthenticated();

    if (!mounted) return;

    final hasRealDebrid = rdEnabled && rdKey != null && rdKey.isNotEmpty;
    final hasTorbox =
        torboxEnabled && torboxKey != null && torboxKey.isNotEmpty;
    final hasPremiumize =
        premiumizeEnabledPref &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final hasAllDebrid =
        allDebridEnabledPref && allDebridKey != null && allDebridKey.isNotEmpty;

    _applyIntegrationState(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      realDebridEnabled: rdEnabled,
      torboxEnabled: torboxEnabled,
      realDebridHidden: rdHidden,
      torboxHidden: tbHidden,
      pikpakEnabled: pikpakEnabled,
      pikpakHidden: pikpakHidden,
      webDavEnabled: webDavEnabled && webDavServers.isNotEmpty,
      webDavHidden: webDavHidden,
      premiumizeEnabled: hasPremiumize,
      premiumizeHidden: premiumizeHidden,
      allDebridEnabled: hasAllDebrid,
      allDebridHidden: allDebridHidden,
      traktAuthenticated: traktAuthed,
      simklAuthenticated: simklAuthed,
      mdblistAuthenticated: mdblistAuthed,
    );
  }

  void _applyIntegrationState({
    required bool hasRealDebrid,
    required bool hasTorbox,
    required bool realDebridEnabled,
    required bool torboxEnabled,
    required bool realDebridHidden,
    required bool torboxHidden,
    required bool pikpakEnabled,
    required bool pikpakHidden,
    required bool webDavEnabled,
    required bool webDavHidden,
    required bool premiumizeEnabled,
    required bool premiumizeHidden,
    required bool allDebridEnabled,
    required bool allDebridHidden,
    required bool traktAuthenticated,
    required bool simklAuthenticated,
    required bool mdblistAuthenticated,
  }) {
    final newVisible = _computeVisibleNavIndices(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      realDebridHidden: realDebridHidden,
      torboxHidden: torboxHidden,
      pikpakEnabled: pikpakEnabled,
      pikpakHidden: pikpakHidden,
      webDavEnabled: webDavEnabled,
      webDavHidden: webDavHidden,
      premiumizeEnabled: premiumizeEnabled,
      premiumizeHidden: premiumizeHidden,
      allDebridEnabled: allDebridEnabled,
      allDebridHidden: allDebridHidden,
      traktAuthenticated: traktAuthenticated,
      simklAuthenticated: simklAuthenticated,
      mdblistAuthenticated: mdblistAuthenticated,
    );

    int nextIndex = _selectedIndex;
    if (!newVisible.contains(nextIndex)) {
      // The current tab disappeared — land on a Home board rather than the first
      // visible tab, which on TV is now the dedicated (blank) Search tab.
      nextIndex = newVisible.contains(15)
          ? 15
          : (newVisible.contains(0) ? 0 : newVisible.first);
    }

    if (_hasRealDebridKey == hasRealDebrid &&
        _hasTorboxKey == hasTorbox &&
        _rdIntegrationEnabled == realDebridEnabled &&
        _tbIntegrationEnabled == torboxEnabled &&
        _rdHiddenFromNav == realDebridHidden &&
        _tbHiddenFromNav == torboxHidden &&
        _pikpakEnabled == pikpakEnabled &&
        _pikpakHiddenFromNav == pikpakHidden &&
        _webDavEnabled == webDavEnabled &&
        _webDavHiddenFromNav == webDavHidden &&
        _premiumizeEnabled == premiumizeEnabled &&
        _premiumizeHiddenFromNav == premiumizeHidden &&
        _allDebridEnabled == allDebridEnabled &&
        _allDebridHiddenFromNav == allDebridHidden &&
        _traktAuthenticated == traktAuthenticated &&
        _simklAuthenticated == simklAuthenticated &&
        _mdblistAuthenticated == mdblistAuthenticated &&
        nextIndex == _selectedIndex) {
      return;
    }

    setState(() {
      _hasRealDebridKey = hasRealDebrid;
      _hasTorboxKey = hasTorbox;
      _rdIntegrationEnabled = realDebridEnabled;
      _tbIntegrationEnabled = torboxEnabled;
      _rdHiddenFromNav = realDebridHidden;
      _tbHiddenFromNav = torboxHidden;
      _pikpakEnabled = pikpakEnabled;
      _pikpakHiddenFromNav = pikpakHidden;
      _webDavEnabled = webDavEnabled;
      _webDavHiddenFromNav = webDavHidden;
      _premiumizeEnabled = premiumizeEnabled;
      _premiumizeHiddenFromNav = premiumizeHidden;
      _allDebridEnabled = allDebridEnabled;
      _allDebridHiddenFromNav = allDebridHidden;
      _traktAuthenticated = traktAuthenticated;
      _simklAuthenticated = simklAuthenticated;
      _mdblistAuthenticated = mdblistAuthenticated;
      _selectedIndex = nextIndex;
    });
    AppSurfaceState.instance.publishTab(nextIndex);
    // Keep back routing in step: this path can move the user off a hidden
    // tab without a tap ever happening.
    MainPageBridge.setActiveTab(_tabKeyFor(nextIndex));
  }

  /// Insert the Trakt Calendar tab (screen-ID 19) just before Downloads (2)
  /// when [authed]. On layouts that omit Downloads (no provider configured) it
  /// lands right after Discover (18) — the same visual slot — so the tab is
  /// always in a consistent place. Mutates [indices] in place.
  void _insertTraktCalendarTab(List<int> indices, bool authed) {
    if (!authed || indices.contains(19)) return;
    var pos = indices.indexOf(2);
    if (pos < 0) {
      final afterDiscover = indices.indexOf(18);
      pos = afterDiscover >= 0 ? afterDiscover + 1 : indices.length;
    }
    indices.insert(pos, 19);
  }

  List<int> _computeVisibleNavIndices({
    bool? hasRealDebrid,
    bool? hasTorbox,
    bool? realDebridHidden,
    bool? torboxHidden,
    bool? pikpakEnabled,
    bool? pikpakHidden,
    bool? webDavEnabled,
    bool? webDavHidden,
    bool? premiumizeEnabled,
    bool? premiumizeHidden,
    bool? allDebridEnabled,
    bool? allDebridHidden,
    bool? traktAuthenticated,
    bool? simklAuthenticated,
    bool? mdblistAuthenticated,
  }) {
    final trakt = traktAuthenticated ?? _traktAuthenticated;
    final simkl = simklAuthenticated ?? _simklAuthenticated;
    final mdblist = mdblistAuthenticated ?? _mdblistAuthenticated;
    // The Calendar tab shows for any connected tracker; the MDBList service
    // returns false while its rollout flag is disabled.
    final calendar = trakt || simkl || mdblist;
    if (_isAndroidTv) {
      final rd = hasRealDebrid ?? _hasRealDebridKey;
      final rdHidden = realDebridHidden ?? _rdHiddenFromNav;
      final tb = hasTorbox ?? _hasTorboxKey;
      final tbHidden = torboxHidden ?? _tbHiddenFromNav;
      final pikpak = pikpakEnabled ?? _pikpakEnabled;
      final ppHidden = pikpakHidden ?? _pikpakHiddenFromNav;
      final webDav = webDavEnabled ?? _webDavEnabled;
      final wdHidden = webDavHidden ?? _webDavHiddenFromNav;
      final premiumize = premiumizeEnabled ?? _premiumizeEnabled;
      final pmHidden = premiumizeHidden ?? _premiumizeHiddenFromNav;
      final allDebrid = allDebridEnabled ?? _allDebridEnabled;
      final adHidden = allDebridHidden ?? _allDebridHiddenFromNav;
      final indices = <int>[
        MainTab.search,
        MainTab.home,
        MainTab.discover,
        MainTab.downloads,
        MainTab.iptv,
        MainTab.youtube,
        MainTab.debrifyTv,
        MainTab.stremioTv,
      ]; // Search, Home, Discover, Downloads, IPTV, YouTube,
      // Debrify TV, Stremio TV. The dedicated Search tab (17) is no longer
      // TV-only — every non-TV layout WIDE enough for a sidebar carries it
      // too (see the phone gate where nonTvIndices is built). The Home board
      // (15) keeps its own persistent search bar regardless; the tab is an
      // additional way in, not a replacement.
      // Consolidated Cloud tab: one entry when ANY provider is enabled & not
      // hidden (replaces the former per-provider RD/Torbox/PikPak/Premiumize/
      // AllDebrid/WebDAV tabs). The in-tab hub lists the available providers.
      if ((rd && !rdHidden) ||
          (tb && !tbHidden) ||
          (pikpak && !ppHidden) ||
          (premiumize && !pmHidden) ||
          (allDebrid && !adHidden) ||
          (webDav && !wdHidden)) {
        indices.add(MainTab.cloud);
      }
      indices.add(MainTab.addons);
      indices.add(MainTab.settings);
      _insertTraktCalendarTab(indices, calendar);
      return _applyProfilePolicy(indices);
    }

    final rd = hasRealDebrid ?? _hasRealDebridKey;
    final rdHidden = realDebridHidden ?? _rdHiddenFromNav;
    final tb = hasTorbox ?? _hasTorboxKey;
    final tbHidden = torboxHidden ?? _tbHiddenFromNav;
    final pikpak = pikpakEnabled ?? _pikpakEnabled;
    final ppHidden = pikpakHidden ?? _pikpakHiddenFromNav;
    final webDav = webDavEnabled ?? _webDavEnabled;
    final wdHidden = webDavHidden ?? _webDavHiddenFromNav;
    final premiumize = premiumizeEnabled ?? _premiumizeEnabled;
    final pmHidden = premiumizeHidden ?? _premiumizeHiddenFromNav;
    final allDebrid = allDebridEnabled ?? _allDebridEnabled;
    final adHidden = allDebridHidden ?? _allDebridHiddenFromNav;
    if (!rd && !tb && !pikpak && !webDav && !premiumize && !allDebrid) {
      final indices = <int>[
        MainTab.search,
        MainTab.home,
        MainTab.discover,
        MainTab.iptv,
        MainTab.youtube,
        MainTab.stremioTv,
        MainTab.addons,
        MainTab.settings,
      ]; // Search, Home, Discover, IPTV, YouTube, Stremio TV, Addons, Settings
      _insertTraktCalendarTab(indices, calendar);
      return _applyProfilePolicy(indices);
    }

    final indices = <int>[
      MainTab.search,
      MainTab.home,
      MainTab.discover,
      MainTab.downloads,
      MainTab.iptv,
      MainTab.youtube,
      MainTab.debrifyTv,
      MainTab.stremioTv,
    ];
    // Consolidated Cloud tab (see TV branch above): one entry when any provider
    // is enabled & not hidden.
    if ((rd && !rdHidden) ||
        (tb && !tbHidden) ||
        (pikpak && !ppHidden) ||
        (premiumize && !pmHidden) ||
        (allDebrid && !adHidden) ||
        (webDav && !wdHidden)) {
      indices.add(MainTab.cloud);
    }
    indices.add(MainTab.addons);
    indices.add(MainTab.settings);
    _insertTraktCalendarTab(indices, calendar);
    return _applyProfilePolicy(indices);
  }

  /// Group label for the desktop sidebar, keyed by screen index (the index
  /// into [_pages]/[_titles], not the visible-nav position).
  String _navSectionForIndex(int screenIndex) {
    switch (screenIndex) {
      case 17: // Search (TV + sidebar layouts)
      case 15: // Home New (board)
      case 18: // Discover
      case 0: // Home
      case 2: // Downloads
      case 19: // Trakt/Simkl Calendar
        return 'Main';
      case 13: // IPTV
      case 14: // YouTube
        return 'Browse';
      case 3: // Debrify TV
      case 9: // Stremio TV
        return 'TV';
      case 16: // Cloud (consolidated provider hub)
      case 4: // Real Debrid (legacy per-provider indices, no longer in nav)
      case 5: // Torbox
      case 6: // PikPak
      case 10: // WebDAV
      case 11: // Premiumize
      case 12: // AllDebrid
        return 'Library';
      case 7: // Addons
      case 8: // Settings
        return 'Setup';
      default:
        return 'Main';
    }
  }

  /// Apply the active profile's ranking only after visibility policy has
  /// filtered the destinations. The default configuration is byte-for-byte
  /// today's former grouped order.
  List<int> _sidebarOrderedIndices(List<int> visibleIndices) =>
      _sidebarConfiguration.orderVisibleTabs(visibleIndices);

  /// Resolve the widget for a nav index, routed through the tab-boundary
  /// factory: FROZEN destinations (see [AppSurfaces.tabs]) are wrapped in a
  /// [LegacyThemeBoundary] so they render today's look under any app theme;
  /// themed destinations inherit the live scope above the Navigator.
  Widget _buildPage(int index) =>
      AppSurfaces.wrapTab(index, _buildTabContent(index));

  /// Most tabs come straight from the const [_pages] list; the "Browse" tabs
  /// (IPTV/YouTube) are built here so the already-resolved [_isAndroidTv]
  /// flag can be passed in (avoiding a first-frame layout/focus flash from
  /// async re-detection).
  Widget _buildTabContent(int index) {
    switch (index) {
      case 9: // Stremio TV — built here (not from the const _pages list) so it
        // gets the resolved native TV flag, like IPTV/YouTube/Home. Without it
        // the screen fell back to a width heuristic that mis-detected the TV.
        return StremioTvScreen(isTelevision: _isAndroidTv);
      case 13: // IPTV
        return BrowseScreen(
          tabIndex: 13,
          hintText: 'Search channels...',
          // Submit-only: the in-page channel filter runs a full-scan COUNT on
          // the UI isolate, so filter on the search key press, not on every
          // keystroke — one scan per deliberate search, no per-keystroke storm.
          submitOnly: true,
          isTelevision: _isAndroidTv,
          viewBuilder: (args) => IptvResultsView(
            key: args.resultKey,
            searchQuery: args.query,
            isTelevision: args.isTelevision,
            onUpArrowFromFilters: args.onUpArrowToSearch,
          ),
        );
      case 14: // YouTube
        return BrowseScreen(
          tabIndex: 14,
          hintText: 'Search YouTube...',
          submitOnly: true,
          isTelevision: _isAndroidTv,
          viewBuilder: (args) => YoutubeResultsView(
            key: args.resultKey,
            searchQuery: args.query,
            searchToken: args.searchToken,
            isTelevision: args.isTelevision,
            onUpArrowFromFilters: args.onUpArrowToSearch,
          ),
        );
      case 15: // Home New (Stremio-style board)
        return SearchScreen(isTelevision: _isAndroidTv);
      case 16: // Cloud (consolidated provider hub)
        return CloudScreen(isTelevision: _isAndroidTv);
      case 17: // Search (dedicated tab — TV + sidebar layouts)
        return SearchScreen(isTelevision: _isAndroidTv, searchMode: true);
      case 18: // Discover (source-dropdown browser)
        return SearchScreen(isTelevision: _isAndroidTv, discoverMode: true);
      case 19: // Calendar (gated on Trakt OR Simkl auth in the nav below)
        return const TraktCalendarScreen();
      default:
        return _pages[index];
    }
  }

  /// Shared fade + slide page switcher used by every layout (TV, desktop
  /// sidebar, top-bar/mobile). Keyed by [_selectedIndex] so tab swaps
  /// animate. Each layout wraps this in its own SafeArea/Column as needed.
  Widget _buildAnimatedPage() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: AnimatedSwitcher(
        // TV: short fade-only swap — the 350ms fade+slide animates two
        // full-screen layers at once, which reads as lag on weak TV GPUs.
        duration: Duration(milliseconds: _isAndroidTv ? 150 : 350),
        transitionBuilder: (child, animation) {
          if (_isAndroidTv) {
            return FadeTransition(opacity: animation, child: child);
          }
          final offsetAnimation =
              Tween<Offset>(
                begin: const Offset(0.02, 0.02),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: _buildPage(_selectedIndex),
        ),
      ),
    );
  }

  void _showMissingApiKeySnack(String provider) {
    final bool integrationDisabled = provider == 'Real Debrid'
        ? !_rdIntegrationEnabled
        : provider == 'Torbox'
        ? !_tbIntegrationEnabled
        : false;
    final message = provider == 'WebDAV'
        ? 'Connect WebDAV in Settings to use this feature.'
        : integrationDisabled
        ? 'Enable $provider in Settings to use this feature.'
        : 'Please add your $provider API key in Settings first!';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showIntegrationRequiredSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Connect Real Debrid, Torbox, Premiumize, PikPak, or WebDAV in Settings to unlock more tabs.',
        ),
      ),
    );
  }

  void _showPolicyDeniedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature is disabled for this profile.'),
      ),
    );
  }

  void _showTabHiddenSnack(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$provider tab is hidden. Enable it in Settings to access.',
        ),
      ),
    );
  }

  /// Open a single cloud provider (from the Cloud hub or a "view in provider" /
  /// post-add deep link). Pushes the provider screen — the same PopScope/pushed
  /// pattern the openXFolder bridges use — so Back returns to wherever the user
  /// was (the Cloud hub, Home, etc.). Preserves the old switchTab guard's UX:
  /// not configured -> missing-key snack; configured but hidden -> hidden snack.
  void _openCloudProvider(String providerKey) {
    if (!mounted) return;
    // Surface gate: this pushes a file-browsing screen. Streaming through
    // the provider is ProfileFeature.cloud and is deliberately NOT checked
    // here-adjacent — hiding the pages never severs the plumbing.
    if (!_allowsProfileFeature(ProfileFeature.cloudFiles)) {
      _showPolicyDeniedSnack();
      return;
    }

    late final bool enabled;
    late final bool hidden;
    late final String name;
    late final Widget child;
    switch (providerKey) {
      case 'realdebrid':
        enabled = _hasRealDebridKey;
        hidden = _rdHiddenFromNav;
        name = 'Real Debrid';
        child = const DebridDownloadsScreen(isPushedRoute: true);
        break;
      case 'torbox':
        enabled = _hasTorboxKey;
        hidden = _tbHiddenFromNav;
        name = 'Torbox';
        child = const TorboxDownloadsScreen(isPushedRoute: true);
        break;
      case 'pikpak':
        enabled = _pikpakEnabled;
        hidden = _pikpakHiddenFromNav;
        name = 'PikPak';
        child = const PikPakFilesScreen(isPushedRoute: true);
        break;
      case 'premiumize':
        enabled = _premiumizeEnabled;
        hidden = _premiumizeHiddenFromNav;
        name = 'Premiumize';
        child = const PremiumizeFilesScreen(isPushedRoute: true);
        break;
      case 'alldebrid':
        enabled = _allDebridEnabled;
        hidden = _allDebridHiddenFromNav;
        name = 'AllDebrid';
        child = const AllDebridFilesScreen(isPushedRoute: true);
        break;
      case 'webdav':
        enabled = _webDavEnabled;
        hidden = _webDavHiddenFromNav;
        name = 'WebDAV';
        // WebDAV returns a CloudScaffold of its own (Material ancestor + the
        // cloud bloom painted edge-to-edge, SafeArea inside). In pushed mode
        // its toolbar shows a Back button and it registers a pushed-route
        // back handler, so system/remote Back folds the stack.
        child = const WebDavFilesScreen(isPushedRoute: true);
        break;
      default:
        return;
    }

    if (!enabled) {
      _showMissingApiKeySnack(name);
      return;
    }
    if (hidden) {
      _showTabHiddenSnack(name);
      return;
    }
    // Don't stack a second provider route on top of one already open (rapid
    // re-tap / a deep link firing while a provider is open) — the user backs out
    // to the hub first, then opens another.
    if (_cloudProviderRouteOpen) return;
    _cloudProviderRouteOpen = true;

    void back(BuildContext ctx) {
      if (!MainPageBridge.handleBackNavigation()) {
        Navigator.of(ctx).pop();
      }
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'cloud_provider'),
            builder: (ctx) => PopScope(
              canPop: false,
              onPopInvoked: (didPop) {
                if (didPop) return;
                back(ctx);
              },
              // Desktop has no system Back gesture and these provider roots may
              // show no back button, so bind Escape to the same back handler.
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      back(ctx),
                },
                child: child,
              ),
            ),
          ),
        )
        .then((_) {
          if (mounted) _cloudProviderRouteOpen = false;
        });
  }

  /// Root-level BACK/Menu handler for the MainPage PopScope below. Runs only
  /// when the press wasn't already meaningful somewhere deeper: the startup
  /// cover, per-tab folder handlers, pushed routes and the non-Home tab-walk
  /// all keep their behavior — this decides what BACK means when there is
  /// nothing left to go back FROM.
  Future<void> _onRootPopInvoked(bool didPop) async {
    if (didPop) return;

    // The startup-channel cover owns BACK while it is up: this is the
    // promised escape hatch, and it has to win over every other handler
    // (including the root exit contract) or a hung launch would be
    // uninterruptible.
    if (_showIptvStartupOverlay) {
      _cancelIptvStartup();
      return;
    }

    // First, check if any child screen wants to handle back navigation
    // (e.g., folder navigation in RealDebrid, TorBox, PikPak, Playlist screens)
    if (MainPageBridge.handleBackNavigation()) {
      return; // Back was handled by child screen (navigated up a folder)
    }

    // Allow navigation within app for all platforms
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
      return;
    }

    // Classic bottom-nav contract (non-TV): BACK from any non-Home
    // tab walks to the Home tab first. Without this every tab was
    // exit-adjacent — the first press armed the exit timer right
    // there, so two quick presses anywhere closed the whole app,
    // which read as "back randomly exits". Only Home arms
    // double-back-to-exit.
    // Apple TV takes this path too. Menu on tvOS means "go back", and
    // its root is the Home tab — without this, BACK from any other tab
    // did nothing at all, because the Android-TV branch below skips the
    // walk and the old `Platform.isIOS` guard (true on tvOS) then
    // swallowed the press. Android TV keeps its sidebar contract.
    if ((!_isAndroidTv || PlatformUtil.isTvOS) && _selectedIndex != 15) {
      final visible = _computeVisibleNavIndices();
      if (visible.contains(15)) {
        _onItemTapped(15);
        return;
      }
    }

    // At root level - platform-specific exit behavior

    // Desktop platforms: Don't exit on back button
    // Users close windows using OS controls (X button, Cmd+Q, etc.)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return; // Do nothing
    }

    // iPhone / iPad: don't force exit — there is no back button, and
    // users leave by swiping up. NOT tvOS: `Platform.isIOS` is true
    // there, and this guard was why BACK did nothing on Apple TV.
    if (PlatformUtil.isIosMobile) {
      return; // Do nothing
    }

    // Apple TV: Menu at the true root opens the rail; Menu with the rail
    // open leaves the app. The old design let the second press "go
    // unhandled" expecting tvOS to take over — but Flutter's unhandled-pop
    // fallback is `SystemNavigator.pop()`, which is a NO-OP on tvOS (its
    // Darwin implementation only pops a navigation controller, and this app
    // installs the FlutterViewController as the window root). So there was
    // no way to exit at all. The runner's `suspend` channel resigns to the
    // tvOS Home Screen (the TV-button animation), then terminates — so the
    // next open is a cold start, boot ident included.
    if (PlatformUtil.isTvOS) {
      if (!(MainPageBridge.isTvSidebarFocused?.call() ?? false)) {
        MainPageBridge.focusTvSidebar?.call();
        return;
      }
      unawaited(
        const MethodChannel(
          'debrify/tvsystem',
        ).invokeMethod<void>('suspend').catchError((_) {}),
      );
      return;
    }

    // Android TV: BACK at root is the sidebar's door — one press opens the
    // rail, a press while the rail is open exits. The bridge null-check
    // keeps the first frames after launch (TV probe unresolved, callbacks
    // not wired yet) on the mobile double-back path below instead of a
    // dead press.
    if (_isAndroidTv && MainPageBridge.focusTvSidebar != null) {
      if (!(MainPageBridge.isTvSidebarFocused?.call() ?? false)) {
        MainPageBridge.focusTvSidebar!();
        return;
      }
      SystemNavigator.pop();
      return;
    }

    // Android mobile: Double back press to exit
    if (Platform.isAndroid) {
      final currentTime = DateTime.now();
      final backButtonPressedTwice =
          _lastBackPressTime != null &&
          currentTime.difference(_lastBackPressTime!) < _backPressDuration;

      if (backButtonPressedTwice) {
        SystemNavigator.pop();
        return;
      }

      // First press - show message
      _lastBackPressTime = currentTime;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Press back again to exit'),
          duration: _backPressDuration,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleIndices = _computeVisibleNavIndices();
    // Read ONCE here and captured by every builder below. The scrim and veil
    // sit inside ValueListenableBuilders that re-run on each sidebar focus
    // enter/exit — frequent enough that this file already avoids setState for
    // them — and the Scaffold sits inside a LayoutBuilder that re-runs on
    // every resize, so a lookup at any of those sites repeats an
    // inherited-widget walk on a hot path.
    final app = AppThemeScope.of(context);

    return Stack(
      children: [
        // Main app content
        // ValueListenableBuilder, not plain state: sidebar focus enter/exit
        // deliberately avoids setState (see _tvSidebarExpanded), yet tvOS
        // needs canPop to follow the rail — so only this PopScope shell
        // rebuilds on it, and the app content rides through as `shell`.
        ValueListenableBuilder<bool>(
          valueListenable: _tvSidebarExpanded,
          builder: (context, tvSidebarOpen, shell) => PopScope(
            // Always intercepted — including Apple TV. The old tvOS
            // "let it through while the rail is open" passthrough dead-ended
            // in SystemNavigator.pop (a no-op there); the handler now owns
            // the whole rail/exit contract via the runner's suspend channel.
            canPop: false,
            onPopInvoked: _onRootPopInvoked,
            child: shell!,
          ),
          child: AnimatedPremiumBackground(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // TV Layout: Sidebar + Content
                if (_isAndroidTv) {
                  // Keep the bridge's active-tab index in lock-step with the tab
                  // actually being rendered — startup and integration-driven tab
                  // changes set _selectedIndex without routing through
                  // _onNavItemSelected, so a screen can't otherwise trust it.
                  MainPageBridge.setActiveTvTab(_selectedIndex);
                  final tvIndices = _sidebarOrderedIndices(visibleIndices);
                  final tvSelected = tvIndices.indexOf(_selectedIndex);
                  // The scope regular tab content lives in — the left-edge
                  // guard in _TvContentDirectionalFocusAction compares against
                  // it so nested focus-trap scopes stay trapped.
                  _tvDirectionalFocusAction.contentScope = FocusScope.of(
                    context,
                  );
                  return Scaffold(
                    backgroundColor: Colors.transparent,
                    // Sidebar is OVERLAID (Stack), not a Row sibling. The content
                    // is inset by the collapsed rail width, so when the sidebar
                    // expands it slides OVER the content instead of reflowing the
                    // whole board every frame — that reflow was the TV sluggishness.
                    body: Stack(
                      children: [
                        // The whole-shell GLASS STAGE: the Home board's
                        // focused title art, tiny-decode blurred, behind BOTH
                        // the content and the sidebar rail (the board's
                        // scaffold is transparent over it). Flat page ink
                        // when nothing is published; other tabs' opaque
                        // scaffolds simply cover it.
                        const Positioned.fill(child: TvAmbientArtStage()),
                        Positioned.fill(
                          // Through the helper, not the constant: 'pill' draws
                          // no rail at rest, and a hardcoded 64 would leave a
                          // dead margin down the left of every screen under
                          // the one style whose point is to reclaim it.
                          left: TvSidebarNav.contentInsetFor(_tvSidebarStyle),
                          child: SafeArea(
                            left: false,
                            // The sidebar's nodes are skipTraversal, so DPAD can
                            // never wander into it; this override is the single,
                            // global way in: LEFT that finds nothing inside the
                            // content (= left edge) focuses the rail.
                            child: Actions(
                              actions: _tvContentActions,
                              // Own layer: without this, every frame of the
                              // sidebar's expand tween (and the scrim fade)
                              // re-recorded and re-rastered the whole content
                              // page behind it — measured on the Mi Box as
                              // ~100ms frames over Home vs ~25ms over a light
                              // tab, i.e. the drawer's cost WAS the content's.
                              // Boundaried, the tween re-rasters only itself
                              // and the page composites from its cached layer.
                              child: RepaintBoundary(
                                child: _buildAnimatedPage(),
                              ),
                            ),
                          ),
                        ),
                        // Dim the content while the sidebar overlay is open —
                        // depth cue that pulls the eye to the menu. IgnorePointer
                        // always (it's purely visual); one fade, no blur, cheap.
                        // ValueListenableBuilder so a sidebar focus enter/exit
                        // rebuilds ONLY this scrim, never the content page.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _tvSidebarExpanded,
                              builder: (context, expanded, _) =>
                                  AnimatedOpacity(
                                    opacity: expanded ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOut,
                                    child: ColoredBox(
                                      color: app.shell.sidebarScrim,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          // Hide the rail entirely while the Home board's
                          // trailer takes over the screen
                          // (MainPageBridge.tvChromeDim → 1): a cinema has no
                          // menu. Fixed wrapper shape (Opacity 1.0 = no layer
                          // at rest, 0.0 paints nothing) with a short
                          // follower tween mirroring the board's soft
                          // restore on an instant kill. The rail stays
                          // FOCUSABLE while invisible: LEFT still lands on it,
                          // which kills the trailer, so it's already fading
                          // back in as it expands — the user never actually
                          // sees an empty menu.
                          // Reads the COMPOSITOR, not the trailer notifier
                          // directly. Two things want the rail out of the way
                          // — a trailer taking the screen, and the room going
                          // idle — and `IdleDim.effective` is their max,
                          // computed once so the two can never fight. Under
                          // legacy the idle half is always 0, so this is
                          // `tvChromeDim` and nothing else.
                          child: ValueListenableBuilder<double>(
                            valueListenable: IdleDim.instance.effective,
                            builder: (context, target, child) =>
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(end: target),
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOut,
                                  child: child,
                                  builder: (context, t, kid) => Opacity(
                                    opacity: 1.0 - t.clamp(0.0, 1.0),
                                    child: kid,
                                  ),
                                ),
                            // The rail's half of the same isolation: its
                            // expanding panel repaints inside this boundary
                            // alone instead of dirtying the shared layer it
                            // used to sit on with the page.
                            child: RepaintBoundary(
                              child: TvSidebarNav(
                                key: _tvSidebarKey,
                                navStyle: _tvSidebarStyle,
                                currentIndex: tvSelected == -1 ? 0 : tvSelected,
                                items: [
                                  for (final index in tvIndices)
                                    TvNavItem(
                                      _icons[index],
                                      _sidebarConfiguration.labelForTab(
                                        index,
                                        _titles[index],
                                      ),
                                      section: _navSectionForIndex(index),
                                    ),
                                ],
                                onTap: (relativeIndex) {
                                  final actualIndex = tvIndices[relativeIndex];
                                  _onItemTapped(actualIndex);
                                  // Focus is handled by sidebar via MainPageBridge
                                },
                                profile: _profilePolicy,
                                onProfileTap: _profilePolicy == null
                                    ? null
                                    : () => unawaited(
                                        _openProfilesFromNavigation(),
                                      ),
                                onFocusContent: () {
                                  // Fallback for screens without registered handler
                                  FocusScope.of(context).nextFocus();
                                },
                                onExpandedChanged: (expanded) {
                                  // No setState — see _tvSidebarExpanded's comment.
                                  if (mounted) {
                                    _tvSidebarExpanded.value = expanded;
                                    MainPageBridge.notifyTvSidebarFocusChanged(
                                      expanded,
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        // LIGHTS OFF, rail edition: while the Home hero's
                        // ambient trailer plays, the board veils its rows and
                        // hero canvas near-black — this mirrors the same veil
                        // over the collapsed rail strip so the menu dims with
                        // the room instead of glowing beside it. Same cadence
                        // as the board's veils (slow dim, fast lights-up).
                        // Collapsed width only: entering the rail clears the
                        // trailer (see _onTvSidebarFocusChanged on the board),
                        // so the veil is already lifting before it expands.
                        // IgnorePointer — purely visual, the rail underneath
                        // stays focusable.
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          // Matches the rail it veils — zero-width under
                          // 'pill', where there is no rail to darken.
                          width: TvSidebarNav.contentInsetFor(_tvSidebarStyle),
                          child: IgnorePointer(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: MainPageBridge.tvStageLightsOff,
                              builder: (context, off, _) => AnimatedOpacity(
                                opacity: off ? 1.0 : 0.0,
                                duration: off
                                    ? const Duration(milliseconds: 900)
                                    : const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                child: ColoredBox(color: app.shell.railVeil),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Keep one stable non-TV content tree across the phone-width
                // breakpoint. Previously the mobile Stack and desktop Row
                // lived in separate return branches, so rotating a phone past
                // 600 px disposed the active page (and rotating back created it
                // again), losing local screen state. Only the navigation chrome
                // is conditional now; the active page remains the first child
                // of the same Stack/SafeArea chain at every non-TV width.
                final isDesktopWide =
                    !_isAndroidTv && constraints.maxWidth >= 600;
                // The Search tab rides the sidebar, so it appears wherever a
                // sidebar does — desktop AND touch tablets. A phone stays out:
                // its bottom bar holds three slots beside Home, all already
                // spoken for, and the Home board's own search bar is the way
                // in there.
                //
                // Width alone cannot express that. A phone in landscape clears
                // 600 comfortably (a Pro Max is 844 wide), so gating on width
                // would hand Search to the one device meant to skip it, and
                // rotating back to portrait would stand the tab down while it
                // was still the selected page — nav highlighting Home over a
                // Search screen. shortestSide is orientation-independent, the
                // standard tablet test, so a phone is excluded in EITHER
                // orientation and every iPad and Android tablet qualifies.
                // Desktop is judged by the window instead: it has no fixed
                // shortest side, and a short wide window is still a desktop.
                //
                // Filtering here rather than in `_computeVisibleNavIndices` is
                // deliberate — that list is what `_onItemTapped` validates
                // against, so dropping 17 from it would make the tab
                // unreachable by any route, not merely absent from the rail.
                final isPhone =
                    !kIsWeb &&
                    (Platform.isAndroid || Platform.isIOS) &&
                    !PlatformUtil.isTelevision &&
                    MediaQuery.of(context).size.shortestSide < 600;
                // Profile sidebar customization stops at the wide-layout
                // boundary. Phone navigation keeps its canonical order and
                // its separate classic-bar picks.
                final nonTvIndices =
                    (isDesktopWide
                            ? _sidebarOrderedIndices(visibleIndices)
                            : visibleIndices)
                        .where(
                          (i) =>
                              (isDesktopWide && !isPhone) ||
                              i != _kSearchTabIndex,
                        )
                        .toList();
                final nonTvSelected = nonTvIndices.indexOf(_selectedIndex);
                // Touch tablets (iPad / Android tablet in landscape) get the
                // wider rail. True desktop keeps the slim rail.
                //
                // The television exclusion is load-bearing: Platform.isIOS is
                // TRUE on Apple TV, so without it a TV would be classed as a
                // touch tablet and given the finger-sized rail.
                final expandDesktopSidebar =
                    !kIsWeb &&
                    (Platform.isAndroid || Platform.isIOS) &&
                    !PlatformUtil.isTelevision;
                // 'pill' is the one style that changes LAYOUT, exactly like
                // its TV namesake: no rail, no reserved gutter — the content
                // runs full-bleed and the capsule floats over it.
                final desktopPill =
                    isDesktopWide && _desktopSidebarStyle == 'pill';
                final desktopSidebarWidth = desktopPill
                    ? 0.0
                    : expandDesktopSidebar
                    ? DesktopSidebarNav.expandedWidth
                    : DesktopSidebarNav.width;

                final classicBottomNav =
                    !isDesktopWide &&
                    _phoneNavLoaded &&
                    _phoneNavStyle == 'classic';
                return Scaffold(
                  // Opaque page ink rather than transparent-to-the-wallpaper.
                  //
                  // The active page is inset by the SafeArea below, so a
                  // transparent shell let the [AnimatedPremiumBackground] wash
                  // — then an animated indigo→violet→cyan gradient — show
                  // through the status-bar and home-indicator strips while the
                  // page itself sat on near-black ink. On a phone those strips
                  // are thin; on an iPad they're tall enough that the screen
                  // read as three mismatched horizontal bands. (That wash is
                  // static now: once this went opaque nothing could see it
                  // move, so the animation was dropped.)
                  //
                  // shell.ink pins #0D0B1A under legacy — the app's de-facto
                  // ink (kStremioBg, kSeeAllBg and HomeTheme.bg are all this
                  // exact colour) — so the strips match every page that uses
                  // it, and under a real app theme they follow its ground.
                  // Safe to keep opaque because no non-TV page is translucent
                  // down to the wallpaper: the one page that goes transparent
                  // on purpose is the glass Home board, which is TV-gated
                  // (`_heroTrailerActive`).
                  //
                  // TV keeps its transparent shell above — TvAmbientArtStage is
                  // the real background there.
                  backgroundColor: app.shell.ink,
                  // The REAL Scaffold slot, not a body child: Scaffold then
                  // owns the geometry — body inset above the bar, descendant
                  // MediaQuery stripped of the bottom padding the bar
                  // absorbs, and fixed SnackBars ("press back again to
                  // exit") anchor ABOVE the bar instead of covering it.
                  bottomNavigationBar: classicBottomNav
                      ? MobileClassicNav(
                          currentIndex: _selectedIndex,
                          visibleIndices: nonTvIndices,
                          barIndices: _phoneNavEffectiveBar(nonTvIndices),
                          icons: _icons,
                          titles: _titles,
                          onTap: _onItemTapped,
                          onBarEdited: (picks) {
                            setState(() => _phoneNavBarPicks = picks);
                            unawaited(
                              StorageService.setPhoneNavBarIndices(picks),
                            );
                          },
                          onRemoteControlTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RemoteRolePickerScreen(),
                              ),
                            );
                          },
                          profile: _profilePolicy,
                          onProfileTap: _profilePolicy == null
                              ? null
                              : () => unawaited(_openProfilesFromNavigation()),
                        )
                      : null,
                  body: Stack(
                    children: [
                      // This exact element chain stays mounted while rotating.
                      // Moving it sideways with Positioned changes constraints
                      // without changing the identity of the active page.
                      // The classic bar OCCUPIES the bottom strip (unlike the
                      // floating button, which overlays) — the page is inset
                      // by the bar plus the safe area the bar absorbs, the
                      // SafeArea below must not apply that inset twice, AND
                      // the inset must be REMOVED from MediaQuery for the
                      // subtree: SafeArea(bottom: false) doesn't strip it, so
                      // pages with their own SafeArea/padding.bottom reads
                      // would re-apply a 34px inset they no longer sit under.
                      Positioned.fill(
                        left: isDesktopWide ? desktopSidebarWidth : 0,
                        child: ClipRect(
                          child: SafeArea(
                            // The rail absorbs the left inset when present;
                            // under 'pill' there is no rail, so the content
                            // must take the inset back (iPad landscape
                            // notch) or the first column sits under it.
                            left: !isDesktopWide || desktopPill,
                            child: Stack(
                              children: [
                                // Page fills the whole area so its own
                                // background covers the animated backdrop.
                                Positioned.fill(child: _buildAnimatedPage()),
                                // Invisible top strip keeps frameless desktop
                                // windows draggable now that the AppBar is gone.
                                if (isDesktopWide)
                                  const Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: WindowDragArea(
                                      child: SizedBox(height: 26),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isDesktopWide && !desktopPill)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: DesktopSidebarNav(
                            expanded: expandDesktopSidebar,
                            currentIndex: nonTvSelected == -1
                                ? 0
                                : nonTvSelected,
                            entries: [
                              for (final index in nonTvIndices)
                                DesktopNavEntry(
                                  _icons[index],
                                  _sidebarConfiguration.labelForTab(
                                    index,
                                    _titles[index],
                                  ),
                                  _navSectionForIndex(index),
                                ),
                            ],
                            onTap: (relativeIndex) {
                              final actualIndex = nonTvIndices[relativeIndex];
                              _onItemTapped(actualIndex);
                            },
                            profile: _profilePolicy,
                            onProfileTap: _profilePolicy == null
                                ? null
                                : () =>
                                      unawaited(_openProfilesFromNavigation()),
                          ),
                        ),
                      // Full-screen layer, but hit-testable only at the
                      // capsule while closed — see DesktopPillNav.
                      if (desktopPill)
                        Positioned.fill(
                          child: DesktopPillNav(
                            expanded: expandDesktopSidebar,
                            currentIndex: nonTvSelected == -1
                                ? 0
                                : nonTvSelected,
                            entries: [
                              for (final index in nonTvIndices)
                                DesktopNavEntry(
                                  _icons[index],
                                  _sidebarConfiguration.labelForTab(
                                    index,
                                    _titles[index],
                                  ),
                                  _navSectionForIndex(index),
                                ),
                            ],
                            onTap: (relativeIndex) {
                              final actualIndex = nonTvIndices[relativeIndex];
                              _onItemTapped(actualIndex);
                            },
                            profile: _profilePolicy,
                            onProfileTap: _profilePolicy == null
                                ? null
                                : () =>
                                      unawaited(_openProfilesFromNavigation()),
                          ),
                        ),
                      if (!isDesktopWide &&
                          _phoneNavLoaded &&
                          _phoneNavStyle == 'floating')
                        MobileFloatingNav(
                          currentIndex: nonTvSelected == -1 ? 0 : nonTvSelected,
                          items: [
                            for (final index in nonTvIndices)
                              MobileNavItem(
                                _icons[index],
                                _titles[index],
                                section: _navSectionForIndex(index),
                              ),
                          ],
                          onTap: (relativeIndex) {
                            final actualIndex = nonTvIndices[relativeIndex];
                            _onItemTapped(actualIndex);
                          },
                          onRemoteControlTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RemoteRolePickerScreen(),
                              ),
                            );
                          },
                          profile: _profilePolicy,
                          onProfileTap: _profilePolicy == null
                              ? null
                              : () => unawaited(_openProfilesFromNavigation()),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // Startup-channel cover — last child so it sits above everything,
        // including the nav chrome. Frozen: it covers the boot into IPTV (a
        // frozen tab) and is an in-route overlay no tab boundary can reach.
        if (_showIptvStartupOverlay)
          Positioned.fill(
            child: LegacyThemeBoundary(
              child: AutoLaunchOverlay(
                launchTitle: 'Starting channel',
                channelName: _iptvStartupChannelName,
                channelNumber: _iptvStartupChannelNumber,
                cancelHint: 'Press BACK to cancel',
                onTimeout: _cancelIptvStartup,
              ),
            ),
          ),
      ],
    );
  }

  String get _iptvStartupChannelName {
    final name = StorageService.startupIptvChannelCached?['name'];
    return name is String && name.isNotEmpty ? name : 'your channel';
  }

  int? get _iptvStartupChannelNumber {
    final number = StorageService.startupIptvChannelCached?['channelNumber'];
    return number is num ? number.toInt() : null;
  }
}

/// TV-only directional focus for the content area (installed above
/// [_MainPageState._buildAnimatedPage]).
///
/// The sidebar's focus nodes are `skipTraversal`, making it unreachable by
/// Flutter's geometric directional search — that's what used to let a stray
/// DOWN/UP/RIGHT at a content edge land on the rail and pop it open. With that
/// closed off, this action provides the one deliberate entry: when LEFT finds
/// no candidate inside the content (the focused widget is at the content's
/// left edge), focus the sidebar. Screens that already intercept LEFT and call
/// [MainPageBridge.focusTvSidebar] themselves handle the key before it ever
/// reaches this action, so their behavior is unchanged; text fields resolve
/// arrow keys to their own editing actions first, so typing is unaffected.
class _TvContentDirectionalFocusAction extends DirectionalFocusAction {
  /// The scope all regular tab content lives in (the MainPage route's scope),
  /// captured each TV build. A failed LEFT search only means "at the content's
  /// left edge" when the focused node belongs to THIS scope — inside a nested
  /// [FocusScope] (the focus-trap pattern used by panels/dropdowns, e.g.
  /// addon_hub_screen / search_source_dropdown) a failed search must stay a
  /// silent no-op, exactly as it was before this action existed.
  FocusScopeNode? contentScope;

  /// The LEFT move with sidebar fallback. Also exposed through
  /// [MainPageBridge.tvDirectionalLeft] so programmatic navigation (the
  /// phone-remote fallback, which calls focusInDirection directly and never
  /// enters the Shortcuts/Actions pipeline) gets identical behavior.
  void handleLeft() {
    final FocusNode? primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    if (primary.focusInDirection(TraversalDirection.left)) return;
    final FocusScopeNode? scope = contentScope;
    if (scope != null && primary.nearestScope != scope) return;
    MainPageBridge.focusTvSidebar?.call();
  }

  @override
  void invoke(DirectionalFocusIntent intent) {
    if (intent.direction == TraversalDirection.left) {
      handleLeft();
      return;
    }
    super.invoke(intent);
  }
}
