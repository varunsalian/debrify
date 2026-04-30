import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/torrent_search_screen.dart';
import 'screens/debrid_downloads_screen.dart';
import 'screens/torbox/torbox_downloads_screen.dart';
import 'screens/pikpak/pikpak_files_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/magic_tv_screen.dart';
import 'screens/stremio_tv/stremio_tv_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/addons_screen.dart';
import 'services/android_native_downloader.dart';
import 'services/storage_service.dart';
import 'services/debrify_tv_repository.dart';
import 'screens/stremio_tv/stremio_tv_service.dart';
import 'models/debrify_tv_channel_record.dart';
import 'widgets/app_initializer.dart';
import 'package:collection/collection.dart';

import 'widgets/animated_background.dart';
import 'widgets/premium_nav_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/premium_top_nav.dart';
import 'services/main_page_bridge.dart';
import 'services/playlist_player_service.dart';
import 'models/rd_torrent.dart';
import 'package:window_manager/window_manager.dart';
import 'services/deep_link_service.dart';
import 'services/magnet_link_handler.dart';
import 'services/stremio_service.dart';
import 'widgets/auto_launch_overlay.dart';
import 'widgets/window_drag_area.dart';
import 'widgets/mobile_floating_nav.dart';
import 'widgets/tv_sidebar_nav.dart';
import 'services/remote_control/remote_control_state.dart';
import 'services/remote_control/remote_command_router.dart';
import 'services/remote_control/remote_constants.dart';
import 'services/aptabase_service.dart';
import 'services/support_remote_config_service.dart';
import 'widgets/remote/addon_install_dialog.dart';
import 'widgets/remote/remote_control_screen.dart';
import 'widgets/support_donation_chooser_dialog.dart';
import 'utils/platform_util.dart';
import 'services/update_service.dart';

final WindowListener _desktopFullscreenListener = _DesktopFullscreenListener();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AptabaseService.init();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    windowManager.addListener(_desktopFullscreenListener);
  }

  // Initialize sqflite FFI for Windows/Linux desktop (sqflite needs FFI on these platforms)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Set a sensible default orientation: phones stay portrait, Android TV uses landscape.
  await _initOrientation();
  // Clean up old playback state data
  await _cleanupPlaybackState();
  AptabaseService.trackInBackground('app_started');
  runApp(const DebrifyApp());

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

Future<void> _initOrientation() async {
  try {
    // If running on Android TV, prefer landscape. Otherwise allow all orientations (respect auto-rotate).
    final isTv = await AndroidNativeDownloader.isTelevision();
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

class _DesktopFullscreenListener with WindowListener {
  @override
  Future<void> onWindowEvent(String eventName) async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    if (eventName == 'maximize') {
      final isFull = await windowManager.isFullScreen();
      if (!isFull) {
        await windowManager.setFullScreen(true);
      }
    } else if (eventName == 'unmaximize' || eventName == 'restore') {
      final isFull = await windowManager.isFullScreen();
      if (isFull) {
        await windowManager.setFullScreen(false);
      }
    }
  }
}

// Global scaffold messenger key for showing snackbars from anywhere
final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Global navigator key for app navigation (used for remote config restart)
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class DebrifyApp extends StatelessWidget {
  const DebrifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Set up scaffold messenger key for remote command router (TV feedback)
    RemoteCommandRouter().setScaffoldMessengerKey(_scaffoldMessengerKey);

    // Set up restart callback for remote config (when TV receives setup from phone)
    RemoteCommandRouter().setRestartCallback(() {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppInitializer()),
        (_) => false,
      );
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Debrify',
      debugShowCheckedModeBanner: false,
      // Performance optimizations for TV with TV-aware text scaling
      builder: (context, child) {
        // Use FutureBuilder to handle async TV detection
        return FutureBuilder<bool>(
          future: AndroidNativeDownloader.isTelevision(),
          builder: (context, snapshot) {
            // Default to false if detection fails or is pending
            final isTv = snapshot.data ?? false;

            // Debug logging to verify TV detection
            if (snapshot.hasData) {
              debugPrint(
                'Debrify: TV mode detected: $isTv, text scale: ${isTv ? 1.0 : 1.3}',
              );
            }

            // Wrap with global Escape key handler for desktop fullscreen exit
            Widget content = child!;
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

            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                // TV: No text scaling (1.0) to prevent zoom issues
                // Mobile: Respect accessibility but cap at 1.3 for layout consistency
                textScaler: TextScaler.linear(
                  isTv
                      ? 1.0
                      : min(MediaQuery.textScalerOf(context).scale(1.0), 1.3),
                ),
              ),
              child: content,
            );
          },
        );
      },
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        // Optimize scroll physics for TV
        physics: const ClampingScrollPhysics(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(
            0xFF818CF8,
          ), // Indigo 400 (brighter for contrast on dark)
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF3730A3),
          onPrimaryContainer: Colors.white,
          secondary: Color(0xFF34D399), // Emerald 400
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFF065F46),
          onSecondaryContainer: Colors.white,
          tertiary: Color(0xFFFBBF24), // Amber 400
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFF92400E),
          onTertiaryContainer: Colors.white,
          surface: Color(0xFF06080F), // Near black with blue tint
          onSurface: Colors.white,
          surfaceContainerHighest: Color(0xFF141824), // Dark elevated surface
          surfaceContainerHigh: Color(0xFF1C2233), // Input fills
          surfaceContainer: Color(0xFF2A3040), // Mid containers
          surfaceContainerLow: Color(0xFF3A4050), // Lighter containers
          surfaceContainerLowest: Color(0xFF94A3B8), // Slate 400
          background: Color(0xFF020408), // True near-black
          onBackground: Colors.white,
          error: Color(0xFFEF4444), // Red 500
          onError: Colors.white,
          errorContainer: Color(0xFF7F1D1D), // Red 900
          onErrorContainer: Colors.white,
          outline: Color(0xFF475569), // Slate 600
          outlineVariant: Color(0xFF334155), // Slate 700
          shadow: Color(0xFF000000),
          scrim: Color(0xFF000000),
          inverseSurface: Color(0xFFF8FAFC), // Slate 50
          onInverseSurface: Color(0xFF0F172A), // Slate 900
          inversePrimary: Color(0xFF818CF8), // Indigo 400
          surfaceTint: Color(0xFF6366F1), // Indigo 500
        ),
        textTheme: GoogleFonts.interTextTheme(
          const TextTheme(
            displayLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            displayMedium: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.25,
            ),
            displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            headlineMedium: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
            bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            labelLarge: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
            labelMedium: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
            labelSmall: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: const Color(0xFF141824),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            side: const BorderSide(color: Color(0xFF2A3040)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1C2233),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF06080F),
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF141824)),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF141824),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 8,
        ),
      ),
      home: const AppInitializer(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  /// Get the startup channel ID if set (used by DebrifyTVScreen)
  static String? getStartupChannelId() {
    return _MainPageState._getStartupChannelId();
  }

  /// Check if auto-launch overlay is currently showing
  static bool get isAutoLaunchShowingOverlay =>
      _MainPageState.isAutoLaunchShowingOverlay;

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
  static String? _startupChannelIdToLaunch;
  static bool _startupChannelIdConsumed = false;
  static bool _didAutoUpdateCheck = false;

  // Track if auto-launch is currently showing overlay
  static bool _isAutoLaunchShowingOverlay = false;

  // Public getter for other widgets to check
  static bool get isAutoLaunchShowingOverlay => _isAutoLaunchShowingOverlay;

  int _selectedIndex = 0;
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
  bool _isAndroidTv = false;

  // Auto-launch overlay state
  bool _showAutoLaunchOverlay = false;
  String? _autoLaunchChannelName;
  int? _autoLaunchChannelNumber;
  bool _autoLaunchInProgress = false;

  // Back button press tracking for Android TV exit
  DateTime? _lastBackPressTime;
  static const _backPressDuration = Duration(seconds: 2);

  // TV sidebar navigation
  final GlobalKey<TvSidebarNavState> _tvSidebarKey =
      GlobalKey<TvSidebarNavState>();

  // Remote control state
  bool _remoteControlEnabled = true;
  StreamSubscription<Map<String, dynamic>>? _autoUpdateDownloadSub;
  String? _autoUpdateDownloadTaskId;
  bool _hasTrackedInitialTab = false;
  bool _didCheckSupportCampaign = false;
  bool _startupModalActive = false;
  bool _supportCampaignResolved = false;
  bool _autoUpdateCheckResolved = false;

  final List<Widget> _pages = [
    const TorrentSearchScreen(), // 0: Home
    const PlaylistScreen(), // 1: Playlist
    const DownloadsScreen(), // 2: Downloads
    const DebrifyTVScreen(), // 3: Debrify TV
    const DebridDownloadsScreen(), // 4: Real Debrid
    const TorboxDownloadsScreen(), // 5: Torbox
    const PikPakFilesScreen(), // 6: PikPak
    const AddonsScreen(), // 7: Addons
    const SettingsScreen(), // 8: Settings
    const StremioTvScreen(), // 9: Stremio TV
  ];

  final List<String> _titles = [
    'Home',
    'Playlist',
    'Downloads',
    'Debrify TV',
    'Real Debrid',
    'Torbox',
    'PikPak',
    'Addons',
    'Settings',
    'Stremio TV',
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
  ];

  @override
  void initState() {
    super.initState();
    // Expose tab switcher for deep-link flows
    MainPageBridge.switchTab = (int index) {
      if (!mounted) return;
      final visibleIndices = _computeVisibleNavIndices();
      if (!visibleIndices.contains(index)) {
        if (index == 4) {
          _showMissingApiKeySnack('Real Debrid');
        } else if (index == 5) {
          _showMissingApiKeySnack('Torbox');
        } else if (index == 6) {
          // PikPak tab - check if enabled but hidden vs not configured
          if (_pikpakEnabled && _pikpakHiddenFromNav) {
            _showTabHiddenSnack('PikPak');
          } else {
            _showMissingApiKeySnack('PikPak');
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
    MainPageBridge.hideAutoLaunchOverlay = _hideAutoLaunchOverlay;
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

    AndroidNativeDownloader.isTelevision().then((isTv) async {
      if (!mounted) return;

      setState(() {
        _isAndroidTv = isTv;
      });

      // Set up TV sidebar focus callback
      if (isTv) {
        MainPageBridge.focusTvSidebar = () {
          _tvSidebarKey.currentState?.requestFocus();
        };
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

    // Check if startup auto-launch is enabled
    _checkStartupAutoLaunch();
  }

  @override
  void dispose() {
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    MainPageBridge.switchTab = null;
    MainPageBridge.openDebridOptions = null;
    MainPageBridge.openTorboxFolder = null;
    MainPageBridge.openPikPakFolder = null;
    MainPageBridge.hideAutoLaunchOverlay = null;
    MainPageBridge.focusTvSidebar = null;
    _animationController.dispose();
    DeepLinkService().dispose();
    RemoteControlState().stop();
    _autoUpdateDownloadSub?.cancel();
    super.dispose();
  }

  /// Initialize remote control based on device type
  Future<void> _initializeRemoteControl(bool isTv) async {
    // Check if remote control is enabled
    _remoteControlEnabled = await StorageService.getRemoteControlEnabled();
    if (!_remoteControlEnabled) return;

    if (isTv) {
      // TV: Start listening for mobile devices
      // Priority: 1. User-set custom name, 2. Actual device name, 3. Fallback
      var deviceName = await StorageService.getRemoteTvDeviceName();
      deviceName ??= await PlatformUtil.getDeviceName();
      deviceName ??= 'Debrify TV';
      await RemoteControlState().startTvListener(deviceName);

      // Set up command routing
      RemoteControlState().onCommandReceived = (action, command, data) {
        RemoteCommandRouter().dispatchCommand(action, command, data);
      };
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
          // Fallback: Navigate to Torbox tab
          MainPageBridge.switchTab?.call(5); // Torbox tab index
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
          // Fallback: Navigate to PikPak tab
          MainPageBridge.switchTab?.call(6); // PikPak tab index
        },
      );

      // Handle the magnet link
      await handler.handleMagnetLink(magnetUri);
    };

    // Set the callback for handling shared URLs
    deepLinkService.onUrlShared = (url) async {
      if (!mounted) return;

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
          MainPageBridge.switchTab?.call(6); // PikPak tab index
        },
      );

      // Handle the shared URL
      await handler.handleSharedUrl(url);
    };

    // Set the callback for handling Stremio addon URLs
    deepLinkService.onStremioAddonReceived = (manifestUrl) async {
      if (!mounted) return;

      // Show dialog to choose where to install (phone or TV)
      final choice = await AddonInstallDialog.show(context, manifestUrl);

      if (choice == null || !mounted) return; // User cancelled

      if (choice.target == 'tv' && choice.device != null) {
        // Send to TV
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
    if (MainPage.isAutoLaunchShowingOverlay || _startupModalActive) {
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
      final autoEnabled = await StorageService.getUpdateAutoCheckEnabled();
      if (!autoEnabled) return true;
      final packageInfo = await PackageInfo.fromPlatform();
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

  void _onItemTapped(int index) {
    final visible = _computeVisibleNavIndices();
    if (!visible.contains(index)) {
      return;
    }
    final changed = _selectedIndex != index;
    setState(() {
      _selectedIndex = index;
    });
    _animationController.reset();
    _animationController.forward();

    // Notify MainPageBridge which tab is now active for back navigation
    // Map tab indices to handler keys
    String? activeTabKey;
    switch (index) {
      case 4:
        activeTabKey = 'realdebrid';
        break;
      case 5:
        activeTabKey = 'torbox';
        break;
      case 6:
        activeTabKey = 'pikpak';
        break;
    }
    MainPageBridge.setActiveTab(activeTabKey);

    // Update active tab for TV sidebar navigation
    MainPageBridge.setActiveTvTab(index);

    if (changed) {
      _hasTrackedInitialTab = true;
      _trackCurrentTab();
    }
  }

  void _trackCurrentTab() {
    final title = _titles[_selectedIndex];
    AptabaseService.trackInBackground('tab_opened', <String, Object?>{
      'tab': title,
      'tab_index': _selectedIndex,
      'platform': AptabaseService.currentPlatformLabel(),
      'tv_mode': _isAndroidTv,
    });
  }

  void _handleIntegrationChanged() {
    _loadIntegrationState();
  }

  /// Static getter for startup channel ID (used by DebrifyTVScreen)
  static String? _getStartupChannelId() {
    // Check if already consumed (prevents double-read by AnimatedSwitcher)
    if (_startupChannelIdConsumed) {
      debugPrint(
        'MainPage: Startup channel ID already consumed, returning null',
      );
      return null;
    }

    // Mark as consumed and return the value
    _startupChannelIdConsumed = true;
    debugPrint(
      'MainPage: Startup channel ID consumed: $_startupChannelIdToLaunch',
    );
    return _startupChannelIdToLaunch;
  }

  /// Check if startup auto-launch is enabled and navigate to Debrify TV or play playlist item
  Future<void> _checkStartupAutoLaunch() async {
    // Prevent duplicate launches
    if (_autoLaunchInProgress) return;
    _autoLaunchInProgress = true;

    try {
      // Check if auto-launch is enabled
      final autoLaunchEnabled =
          await StorageService.getStartupAutoLaunchEnabled();
      if (!autoLaunchEnabled) {
        _autoLaunchInProgress = false;
        return;
      }

      // Get startup mode
      final startupMode = await StorageService.getStartupMode();

      switch (startupMode) {
        case 'playlist':
          await _launchPlaylistItem();
          break;
        case 'stremio_tv':
          await _launchStremioTvChannel();
          break;
        case 'channel':
        default:
          await _launchChannel();
          break;
      }
    } catch (e) {
      debugPrint('MainPage: Failed to auto-launch: $e');
      // Remove overlay on error
      if (mounted) {
        setState(() {
          _showAutoLaunchOverlay = false;
          _autoLaunchChannelName = null;
          _autoLaunchChannelNumber = null;
        });
      }
      // Clear flags on error
      _isAutoLaunchShowingOverlay = false;
      _startupChannelIdToLaunch = null;
      _startupChannelIdConsumed = false;
    } finally {
      _autoLaunchInProgress = false;
    }
  }

  /// Launch a channel on startup
  Future<void> _launchChannel() async {
    // Load channels
    final channels = await DebrifyTvRepository.instance.fetchAllChannels();
    if (channels.isEmpty) {
      return;
    }

    // Get selected channel ID
    final selectedChannelId =
        await StorageService.getStartupChannelId() ?? 'random';

    // Determine which channel to launch
    DebrifyTvChannelRecord channelToLaunch;

    if (selectedChannelId == 'random') {
      final random = Random();
      channelToLaunch = channels[random.nextInt(channels.length)];
    } else {
      final foundChannel = channels.firstWhereOrNull(
        (c) => c.channelId == selectedChannelId,
      );
      if (foundChannel == null) {
        // Channel not found, fallback to random
        final random = Random();
        channelToLaunch = channels[random.nextInt(channels.length)];
      } else {
        channelToLaunch = foundChannel;
      }
    }

    // Show overlay IMMEDIATELY (before any navigation)
    if (!mounted) {
      return;
    }

    setState(() {
      _showAutoLaunchOverlay = true;
      _autoLaunchChannelName = channelToLaunch.name;
      _autoLaunchChannelNumber = channelToLaunch.channelNumber > 0
          ? channelToLaunch.channelNumber
          : null;
    });

    // Set flag to indicate overlay is showing
    _isAutoLaunchShowingOverlay = true;

    // Set the startup channel for DebrifyTVScreen to pick up
    _startupChannelIdToLaunch = channelToLaunch.channelId;
    _startupChannelIdConsumed = false; // Reset consumption flag
    debugPrint(
      'MainPage: Set startup channel ID: ${channelToLaunch.channelId}',
    );

    // Navigate to Debrify TV tab (index 3) - no delay needed, overlay is showing
    if (!mounted) {
      return;
    }

    _onItemTapped(3); // Debrify TV tab
  }

  /// Launch a Stremio TV channel on startup
  Future<void> _launchStremioTvChannel() async {
    final channels = await StremioTvService.instance.discoverChannels();
    if (channels.isEmpty) {
      return;
    }

    final selectedChannelId =
        await StorageService.getStartupStremioTvChannelId() ?? 'random';

    final channelToLaunch = selectedChannelId == 'random'
        ? channels[Random().nextInt(channels.length)]
        : channels.firstWhereOrNull(
                (channel) => channel.id == selectedChannelId,
              ) ??
              channels[Random().nextInt(channels.length)];

    if (!mounted) {
      return;
    }

    setState(() {
      _showAutoLaunchOverlay = true;
      _autoLaunchChannelName = channelToLaunch.displayName;
      _autoLaunchChannelNumber = channelToLaunch.channelNumber > 0
          ? channelToLaunch.channelNumber
          : null;
    });

    _isAutoLaunchShowingOverlay = true;

    MainPageBridge.notifyStremioTvChannelToAutoPlay(channelToLaunch.id);

    if (!mounted) {
      return;
    }

    _onItemTapped(9); // Stremio TV tab
  }

  /// Launch a playlist item on startup
  Future<void> _launchPlaylistItem() async {
    // Get playlist items
    final playlistItems = await StorageService.getPlaylistItemsRaw();
    if (playlistItems.isEmpty) {
      return;
    }

    // Get selected playlist item ID
    final selectedItemId = await StorageService.getStartupPlaylistItemId();
    if (selectedItemId == null || selectedItemId.isEmpty) {
      return;
    }

    // Find the playlist item
    final playlistItem = playlistItems.firstWhereOrNull(
      (item) => StorageService.computePlaylistDedupeKey(item) == selectedItemId,
    );

    if (playlistItem == null) {
      return;
    }

    // Show overlay
    if (!mounted) {
      return;
    }

    final itemTitle = (playlistItem['title'] as String?) ?? 'Playlist Item';
    setState(() {
      _showAutoLaunchOverlay = true;
      _autoLaunchChannelName = itemTitle;
      _autoLaunchChannelNumber = null;
    });

    // Set flag to indicate overlay is showing
    _isAutoLaunchShowingOverlay = true;

    // Wait a bit for the overlay to show
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) {
      return;
    }

    await PlaylistPlayerService.play(context, playlistItem);
    // Dismiss overlay after play returns (covers early-exit error paths
    // where notifyPlayerLaunching is never called)
    if (mounted) _hideAutoLaunchOverlay();
  }

  void _hideAutoLaunchOverlay() {
    if (!_showAutoLaunchOverlay) return;
    if (!mounted) return;
    setState(() {
      _showAutoLaunchOverlay = false;
      _autoLaunchChannelName = null;
      _autoLaunchChannelNumber = null;
    });

    // Clear flags when overlay is hidden
    _isAutoLaunchShowingOverlay = false;

    // Clean up startup channel variables (optional, for memory cleanup)
    _startupChannelIdToLaunch = null;
    _startupChannelIdConsumed = false;
  }

  Future<void> _loadIntegrationState() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();
    final rdHidden = await StorageService.getRealDebridHiddenFromNav();
    final tbHidden = await StorageService.getTorboxHiddenFromNav();
    final pikpakEnabled = await StorageService.getPikPakEnabled();
    final pikpakHidden = await StorageService.getPikPakHiddenFromNav();

    if (!mounted) return;

    final hasRealDebrid = rdEnabled && rdKey != null && rdKey.isNotEmpty;
    final hasTorbox =
        torboxEnabled && torboxKey != null && torboxKey.isNotEmpty;

    _applyIntegrationState(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      realDebridEnabled: rdEnabled,
      torboxEnabled: torboxEnabled,
      realDebridHidden: rdHidden,
      torboxHidden: tbHidden,
      pikpakEnabled: pikpakEnabled,
      pikpakHidden: pikpakHidden,
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
  }) {
    final newVisible = _computeVisibleNavIndices(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      realDebridHidden: realDebridHidden,
      torboxHidden: torboxHidden,
      pikpakEnabled: pikpakEnabled,
      pikpakHidden: pikpakHidden,
    );

    int nextIndex = _selectedIndex;
    if (!newVisible.contains(nextIndex)) {
      nextIndex = newVisible.first;
    }

    if (_hasRealDebridKey == hasRealDebrid &&
        _hasTorboxKey == hasTorbox &&
        _rdIntegrationEnabled == realDebridEnabled &&
        _tbIntegrationEnabled == torboxEnabled &&
        _rdHiddenFromNav == realDebridHidden &&
        _tbHiddenFromNav == torboxHidden &&
        _pikpakEnabled == pikpakEnabled &&
        _pikpakHiddenFromNav == pikpakHidden &&
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
      _selectedIndex = nextIndex;
    });
  }

  List<int> _computeVisibleNavIndices({
    bool? hasRealDebrid,
    bool? hasTorbox,
    bool? realDebridHidden,
    bool? torboxHidden,
    bool? pikpakEnabled,
    bool? pikpakHidden,
  }) {
    if (_isAndroidTv) {
      final rd = hasRealDebrid ?? _hasRealDebridKey;
      final rdHidden = realDebridHidden ?? _rdHiddenFromNav;
      final tb = hasTorbox ?? _hasTorboxKey;
      final tbHidden = torboxHidden ?? _tbHiddenFromNav;
      final pikpak = pikpakEnabled ?? _pikpakEnabled;
      final ppHidden = pikpakHidden ?? _pikpakHiddenFromNav;
      final indices = <int>[
        0,
        2,
        3,
        9,
      ]; // Torrent, Downloads, Debrify TV, Stremio TV
      if (rd && !rdHidden) {
        indices.add(4); // Real Debrid downloads
      }
      if (tb && !tbHidden) {
        indices.add(5); // Torbox downloads
      }
      if (pikpak && !ppHidden) {
        indices.add(6); // PikPak
      }
      indices.add(7); // Addons
      indices.add(8); // Settings
      return indices;
    }

    final rd = hasRealDebrid ?? _hasRealDebridKey;
    final rdHidden = realDebridHidden ?? _rdHiddenFromNav;
    final tb = hasTorbox ?? _hasTorboxKey;
    final tbHidden = torboxHidden ?? _tbHiddenFromNav;
    final pikpak = pikpakEnabled ?? _pikpakEnabled;
    final ppHidden = pikpakHidden ?? _pikpakHiddenFromNav;
    if (!rd && !tb && !pikpak) {
      return [0, 9, 7, 8]; // Home, Stremio TV, Addons, Settings
    }

    final indices = <int>[0, 2, 3, 9];
    if (rd && !rdHidden) indices.add(4);
    if (tb && !tbHidden) indices.add(5);
    if (pikpak && !ppHidden) indices.add(6);
    indices.add(7); // Addons
    indices.add(8); // Settings
    return indices;
  }

  void _showMissingApiKeySnack(String provider) {
    final bool integrationDisabled = provider == 'Real Debrid'
        ? !_rdIntegrationEnabled
        : !_tbIntegrationEnabled;
    final message = integrationDisabled
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
          'Connect Real Debrid or Torbox in Settings to unlock more tabs.',
        ),
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

  @override
  Widget build(BuildContext context) {
    final visibleIndices = _computeVisibleNavIndices();
    final navItems = [
      for (final index in visibleIndices)
        NavItem(_icons[index], _titles[index]),
    ];
    final navBadges = List<int>.filled(navItems.length, 0);
    final selectedNavIndex = visibleIndices.indexOf(_selectedIndex);
    final currentNavIndex = selectedNavIndex == -1 ? 0 : selectedNavIndex;

    return Stack(
      children: [
        // Main app content
        PopScope(
          canPop: false,
          onPopInvoked: (bool didPop) async {
            if (didPop) return;

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

            // At root level - platform-specific exit behavior

            // Desktop platforms: Don't exit on back button
            // Users close windows using OS controls (X button, Cmd+Q, etc.)
            if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
              return; // Do nothing
            }

            // iOS: Don't force exit - iOS apps don't have back buttons
            // Users exit by swiping up or using home button
            if (Platform.isIOS) {
              return; // Do nothing
            }

            // Android (both mobile and TV): Double back press to exit
            if (Platform.isAndroid) {
              final currentTime = DateTime.now();
              final backButtonPressedTwice =
                  _lastBackPressTime != null &&
                  currentTime.difference(_lastBackPressTime!) <
                      _backPressDuration;

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
          },
          child: AnimatedPremiumBackground(
            isTelevision: _isAndroidTv,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Show floating nav on mobile (narrow screens), but not on TV
                final isMobile = constraints.maxWidth < 600 && !_isAndroidTv;

                // TV Layout: Sidebar + Content
                if (_isAndroidTv) {
                  return Scaffold(
                    backgroundColor: Colors.transparent,
                    body: Row(
                      children: [
                        // TV Sidebar Navigation
                        TvSidebarNav(
                          key: _tvSidebarKey,
                          currentIndex: currentNavIndex,
                          items: [
                            for (final navItem in navItems)
                              TvNavItem(
                                navItem.icon,
                                navItem.label,
                                tag: navItem.tag,
                              ),
                          ],
                          onTap: (relativeIndex) {
                            final actualIndex = visibleIndices[relativeIndex];
                            _onItemTapped(actualIndex);
                            // Focus is handled by sidebar via MainPageBridge
                          },
                          onFocusContent: () {
                            // Fallback for screens without registered handler
                            FocusScope.of(context).nextFocus();
                          },
                        ),
                        // Content area
                        Expanded(
                          child: SafeArea(
                            left: false,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 350),
                                transitionBuilder: (child, animation) {
                                  final offsetAnimation =
                                      Tween<Offset>(
                                        begin: const Offset(0.02, 0.02),
                                        end: Offset.zero,
                                      ).animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutCubic,
                                        ),
                                      );
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: offsetAnimation,
                                      child: child,
                                    ),
                                  );
                                },
                                child: KeyedSubtree(
                                  key: ValueKey<int>(_selectedIndex),
                                  child: _pages[_selectedIndex],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Mobile & Desktop Layout
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  // Hide AppBar on mobile - we'll use floating nav instead
                  appBar: isMobile
                      ? null
                      : AppBar(
                          title: WindowDragArea(
                            child: PremiumTopNav(
                              currentIndex: currentNavIndex,
                              items: navItems,
                              onTap: (relativeIndex) {
                                final actualIndex =
                                    visibleIndices[relativeIndex];
                                _onItemTapped(actualIndex);
                              },
                              badges: navBadges,
                              haptics: true,
                            ),
                          ),
                          automaticallyImplyLeading: false,
                        ),
                  body: Stack(
                    children: [
                      SafeArea(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (child, animation) {
                              final offsetAnimation =
                                  Tween<Offset>(
                                    begin: const Offset(0.02, 0.02),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<int>(_selectedIndex),
                              child: _pages[_selectedIndex],
                            ),
                          ),
                        ),
                      ),
                      // Floating nav on mobile
                      if (isMobile)
                        MobileFloatingNav(
                          currentIndex: currentNavIndex,
                          items: [
                            for (final navItem in navItems)
                              MobileNavItem(
                                navItem.icon,
                                navItem.label,
                                tag: navItem.tag,
                              ),
                          ],
                          onTap: (relativeIndex) {
                            final actualIndex = visibleIndices[relativeIndex];
                            _onItemTapped(actualIndex);
                          },
                          onRemoteControlTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RemoteControlScreen(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Auto-launch overlay (covers everything when shown)
        if (_showAutoLaunchOverlay)
          AutoLaunchOverlay(
            channelName: _autoLaunchChannelName ?? 'Loading...',
            channelNumber: _autoLaunchChannelNumber,
            onTimeout: _hideAutoLaunchOverlay,
          ),
      ],
    );
  }
}
